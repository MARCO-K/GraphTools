Describe "Remove-GTPIMRoleEligibilityInternal" {
    BeforeAll {
        function global:Test-GTUserObject { param($User) return $true }
        function global:Test-GTGuid { param($InputObject) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message'; HttpStatus = 404 } }
        function global:Invoke-GTGraphPagedRequest { param($Uri, [switch]$All) return @() }
        function global:Invoke-GTGraphBatch { param($Requests, $ErrorAction) return @() }

        . "$PSScriptRoot/../internal/functions/Remove-GTPIMRoleEligibilityInternal.ps1"
    }

    AfterAll {
        Remove-Item Function:\global:Test-GTUserObject -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Test-GTGuid -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Write-PSFMessage -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Get-GTGraphErrorDetails -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Invoke-GTGraphPagedRequest -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Invoke-GTGraphBatch -Force -ErrorAction SilentlyContinue
    }

    Context "Batch Removal" {
        It "should remove eligible assignments using batching" {
            $user = [PSCustomObject]@{ Id = '00000000-0000-0000-0000-000000000001'; UserPrincipalName = 'user@contoso.com' }
            $outputBase = @{}
            $results = [System.Collections.Generic.List[PSObject]]::new()

            $mockEligible = @(
                [PSCustomObject]@{
                    id = "Sched2"
                    roleDefinition = [PSCustomObject]@{ displayName = "User Admin" }
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                return $mockEligible
            }

            Mock -CommandName "Invoke-GTGraphBatch" -MockWith {
                return @(
                    [PSCustomObject]@{
                        Id = "Sched2"
                        Status = 204
                    }
                )
            }

            Remove-GTPIMRoleEligibility -User $user -OutputBase $outputBase -Results $results -Confirm:$false

            Assert-MockCalled -CommandName "Invoke-GTGraphBatch" -Times 1 -ParameterFilter {
                $Requests.Count -eq 1 -and $Requests[0].id -eq 'Sched2'
            }
            @($results).Count | Should -Be 1
            $results[0].Status | Should -Be "Success"
        }

        It "should handle batch subrequest failure status" {
            $user = [PSCustomObject]@{ Id = '00000000-0000-0000-0000-000000000001'; UserPrincipalName = 'user@contoso.com' }
            $outputBase = @{}
            $results = [System.Collections.Generic.List[PSObject]]::new()

            $mockEligible = @(
                [PSCustomObject]@{
                    id = "Sched-Fail"
                    roleDefinition = [PSCustomObject]@{ displayName = "Privileged Role Admin" }
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                return $mockEligible
            }

            Mock -CommandName "Invoke-GTGraphBatch" -MockWith {
                return @(
                    [PSCustomObject]@{
                        Id = "Sched-Fail"
                        Status = 400
                        Body = [PSCustomObject]@{ error = [PSCustomObject]@{ message = "Cannot delete active assignment" } }
                    }
                )
            }

            Remove-GTPIMRoleEligibility -User $user -OutputBase $outputBase -Results $results -Confirm:$false

            @($results).Count | Should -Be 1
            $results[0].Status | Should -Be "Failed: Cannot delete active assignment"
        }

        It "should handle batch execution exception" {
            $user = [PSCustomObject]@{ Id = '00000000-0000-0000-0000-000000000001'; UserPrincipalName = 'user@contoso.com' }
            $outputBase = @{}
            $results = [System.Collections.Generic.List[PSObject]]::new()

            $mockEligible = @(
                [PSCustomObject]@{
                    id = "Sched-Throw"
                    roleDefinition = [PSCustomObject]@{ displayName = "Security Admin" }
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                return $mockEligible
            }

            Mock -CommandName "Invoke-GTGraphBatch" -MockWith {
                throw [System.Exception]::new("Batch endpoint timeout")
            }

            Remove-GTPIMRoleEligibility -User $user -OutputBase $outputBase -Results $results -Confirm:$false

            @($results).Count | Should -Be 1
            $results[0].Status | Should -Match "Failed"
        }

        It "should do nothing when no role eligibility schedules are found" {
            $user = [PSCustomObject]@{ Id = '00000000-0000-0000-0000-000000000001'; UserPrincipalName = 'user@contoso.com' }
            $outputBase = @{}
            $results = [System.Collections.Generic.List[PSObject]]::new()

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                return @()
            }

            Mock -CommandName "Invoke-GTGraphBatch" -MockWith { }

            Remove-GTPIMRoleEligibility -User $user -OutputBase $outputBase -Results $results -Confirm:$false

            Assert-MockCalled -CommandName "Invoke-GTGraphBatch" -Times 0
            @($results).Count | Should -Be 0
        }
    }
}

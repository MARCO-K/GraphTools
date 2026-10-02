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
        Remove-Item Function:\global:Test-GTUserObject -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Test-GTGuid -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Write-PSFMessage -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Get-GTGraphErrorDetails -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Invoke-GTGraphPagedRequest -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Invoke-GTGraphBatch -ErrorAction SilentlyContinue
    }

    Context "Batch Removal" {
        It "should handle empty role eligibility schedules" {
            $user = [PSCustomObject]@{ Id = '00000000-0000-0000-0000-000000000001'; UserPrincipalName = 'user@contoso.com' }
            $outputBase = @{}
            $results = [System.Collections.Generic.List[PSObject]]::new()

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @() }
            Mock -CommandName "Invoke-GTGraphBatch" -MockWith { }

            Remove-GTPIMRoleEligibility -User $user -OutputBase $outputBase -Results $results -Confirm:$false

            Should -Invoke -CommandName "Invoke-GTGraphBatch" -Times 0
            @($results).Count | Should -Be 0
        }

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

        It "should handle batch subrequest failures" {
            $user = [PSCustomObject]@{ Id = '00000000-0000-0000-0000-000000000001'; UserPrincipalName = 'user@contoso.com' }
            $outputBase = @{}
            $results = [System.Collections.Generic.List[PSObject]]::new()

            $mockEligible = @(
                [PSCustomObject]@{
                    id = "Sched3"
                    roleDefinition = [PSCustomObject]@{ displayName = "Security Reader" }
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return $mockEligible }
            Mock -CommandName "Invoke-GTGraphBatch" -MockWith {
                return @(
                    [PSCustomObject]@{
                        Id = "Sched3"
                        Status = 403
                        Body = @{ error = @{ message = "Forbidden" } }
                    }
                )
            }

            Remove-GTPIMRoleEligibility -User $user -OutputBase $outputBase -Results $results -Confirm:$false

            @($results).Count | Should -Be 1
            $results[0].Status | Should -Be "Failed: Forbidden"
        }

        It "should handle batch execution exceptions" {
            $user = [PSCustomObject]@{ Id = '00000000-0000-0000-0000-000000000001'; UserPrincipalName = 'user@contoso.com' }
            $outputBase = @{}
            $results = [System.Collections.Generic.List[PSObject]]::new()

            $mockEligible = @(
                [PSCustomObject]@{
                    id = "Sched4"
                    roleDefinition = [PSCustomObject]@{ displayName = "Helpdesk Admin" }
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return $mockEligible }
            Mock -CommandName "Invoke-GTGraphBatch" -MockWith { throw "Network error" }

            Remove-GTPIMRoleEligibility -User $user -OutputBase $outputBase -Results $results -Confirm:$false

            @($results).Count | Should -Be 1
            $results[0].Status | Should -Be "Failed: Mock Error"
        }
    }
}

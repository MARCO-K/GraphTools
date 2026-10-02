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
    }
}

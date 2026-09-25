Describe "Remove-GTPIMRoleEligibility" {
    BeforeAll {
        function global:Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function global:Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession) return $true }
        function global:Get-GTConnection { return [PSCustomObject]@{ AuthType = 'AppOnly' } }
        function global:Test-GTGuid { param($InputObject) return $true }
        function global:Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } }
        function global:Invoke-GTGraphPagedRequest { param($Uri, [switch]$All) return @() }
        function global:Invoke-GTGraphRequest { param($Uri, $Method = 'GET', $Body, $Headers, $ContentType, [switch]$All, [int]$MaxRetries, [int]$RetryBaseDelaySeconds, $Token, [switch]$Raw, $ErrorAction) return @{} }

        . "$PSScriptRoot/../functions/Remove-GTPIMRoleEligibility.ps1"
    }

    Context "Functionality" {
        It "should remove active assignments" {
            $userId = '00000000-0000-0000-0000-000000000001'
            $mockActive = @(
                [PSCustomObject]@{
                    roleAssignmentScheduleId = "Sched1"
                    roleDefinition           = [PSCustomObject]@{ displayName = "Global Admin" }
                }
            )
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                if ($Uri -like "*roleAssignmentScheduleInstances*") {
                    return $mockActive
                }
                return @()
            }
            Mock -CommandName "Invoke-GTGraphRequest" -MockWith { }

            $results = Remove-GTPIMRoleEligibility -UserId $userId -Confirm:$false

            Assert-MockCalled -CommandName "Invoke-GTGraphRequest" -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'beta/roleManagement/directory/roleAssignmentSchedules/Sched1'
            }
            @($results).Count | Should -Be 1
            $results[0].Status | Should -Be "Success"
        }

        It "should remove eligible assignments" {
            $userId = '00000000-0000-0000-0000-000000000001'
            $mockEligible = @(
                [PSCustomObject]@{
                    roleEligibilityScheduleId = "Sched2"
                    roleDefinition            = [PSCustomObject]@{ displayName = "User Admin" }
                }
            )
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                if ($Uri -like "*roleEligibilityScheduleInstances*") {
                    return $mockEligible
                }
                return @()
            }
            Mock -CommandName "Invoke-GTGraphRequest" -MockWith { }

            $results = Remove-GTPIMRoleEligibility -UserId $userId -Confirm:$false

            Assert-MockCalled -CommandName "Invoke-GTGraphRequest" -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'beta/roleManagement/directory/roleEligibilitySchedules/Sched2'
            }
            @($results).Count | Should -Be 1
            $results[0].Status | Should -Be "Success"
        }
    }
}

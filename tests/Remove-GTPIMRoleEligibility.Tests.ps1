Describe "Remove-GTPIMRoleEligibility" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Remove-GTPIMRoleEligibility.ps1"
        if (Test-Path $functionPath) {
            . $functionPath
        }
        else {
            Write-Error "Function file not found at $functionPath"
        }

        function Install-GTRequiredModule {}
        function Initialize-GTGraphConnection {}
        function Get-MgContext {}
        function Get-MgBetaUser {}
        function Test-GTGuid { return $true }
        function Test-GTGraphScopes { return $true }
        function Write-PSFMessage {}
        function Get-GTGraphErrorDetails { return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } }
        
        function Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance { [CmdletBinding()] param($Filter, $ExpandProperty, $All) }
        function Remove-MgBetaRoleManagementDirectoryRoleAssignmentSchedule { [CmdletBinding()] param($UnifiedRoleAssignmentScheduleId) }
        function Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance { [CmdletBinding()] param($Filter, $ExpandProperty, $All) }
        function Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule { [CmdletBinding()] param($UnifiedRoleEligibilityScheduleId) }

        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $true }
        Mock -CommandName "Test-GTGuid" -MockWith { return $true }
        Mock -CommandName "Test-GTGraphScopes" -MockWith { return $true }
        Mock -CommandName "Write-PSFMessage" -MockWith { }
        Mock -CommandName "Get-GTGraphErrorDetails" -MockWith { 
            Write-Host "DEBUG: Args: $($Args | Out-String)"
            if ($Exception) {
                Write-Host "DEBUG: Exception Type: $($Exception.GetType().FullName)"
                Write-Host "DEBUG: Exception Message: $($Exception.Message)"
            }
            else {
                Write-Host "DEBUG: Exception parameter is NULL"
            }
            return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } 
        }
        Mock -CommandName "Get-MgContext" -MockWith { return [PSCustomObject]@{ Account = "admin@contoso.com"; AuthType = "Delegated" } }
        Mock -CommandName "Get-MgUser" -MockWith { return [PSCustomObject]@{ Id = "AdminId" } }
    }

    Context "Functionality" {
        It "should remove active assignments" {
            $mockActive = @(
                [PSCustomObject]@{
                    RoleAssignmentScheduleId = "Sched1"
                    RoleDefinition           = [PSCustomObject]@{ DisplayName = "Global Admin" }
                }
            )
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance" -MockWith { return $mockActive }
            Mock -CommandName "Remove-MgBetaRoleManagementDirectoryRoleAssignmentSchedule" -MockWith { }

            $results = Remove-GTPIMRoleEligibility -UserId "User1" -Confirm:$false
            
            Assert-MockCalled -CommandName "Remove-MgBetaRoleManagementDirectoryRoleAssignmentSchedule" -Times 1 -ParameterFilter { $UnifiedRoleAssignmentScheduleId -eq "Sched1" }
            $results.Count | Should -Be 1
            $results[0].Status | Should -Be "Removed"
        }

        It "should remove eligible assignments" {
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance" -MockWith { return @() }
            
            $mockEligible = @(
                [PSCustomObject]@{
                    RoleEligibilityScheduleId = "Sched2"
                    RoleDefinition            = [PSCustomObject]@{ DisplayName = "User Admin" }
                }
            )
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance" -MockWith { return $mockEligible }
            Mock -CommandName "Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -MockWith { }

            Remove-GTPIMRoleEligibility -UserId "User1" -Confirm:$false

            Assert-MockCalled -CommandName "Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -Times 1 -ParameterFilter { $UnifiedRoleEligibilityScheduleId -eq "Sched2" }
        }
    }
}

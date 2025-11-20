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
        function Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance { param($Filter, $ExpandProperty, $All, $ErrorAction) }
        function Remove-MgBetaRoleManagementDirectoryRoleAssignmentSchedule { param($UnifiedRoleAssignmentScheduleId, $ErrorAction) }
        function Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance { param($Filter, $ExpandProperty, $All, $ErrorAction) }
        function Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule { param($UnifiedRoleEligibilityScheduleId, $ErrorAction) }

        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $true }
        Mock -CommandName "Test-GTGuid" -MockWith { return $true }
        Mock -CommandName "Get-MgContext" -MockWith { return [PSCustomObject]@{ Account = "admin@contoso.com" } }
        Mock -CommandName "Get-MgBetaUser" -MockWith { return [PSCustomObject]@{ Id = "AdminId" } }
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

            $results = Remove-GTPIMRoleEligibility -UserId "User1" -Confirm:$false

            Assert-MockCalled -CommandName "Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -Times 1 -ParameterFilter { $UnifiedRoleEligibilityScheduleId -eq "Sched2" }
        }
    }
}

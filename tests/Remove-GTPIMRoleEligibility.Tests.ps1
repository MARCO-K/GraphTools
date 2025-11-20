Describe "Remove-GTPIMRoleEligibility" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Remove-GTPIMRoleEligibility.ps1"
        # Use Pester Mocks before dot-sourcing so the function file can load and calls are intercepted
        Mock -CommandName Install-GTRequiredModule -MockWith { param($ModuleNames, $Verbose) } -Verifiable
        Mock -CommandName Initialize-GTGraphConnection -MockWith { } -Verifiable
        Mock -CommandName Get-MgContext -MockWith { } -Verifiable
        Mock -CommandName Get-MgBetaUser -MockWith { } -Verifiable
        Mock -CommandName Test-GTGuid -MockWith { return $true } -Verifiable
        Mock -CommandName Test-GTGraphScopes -MockWith { return $true } -Verifiable
        Mock -CommandName Write-PSFMessage -MockWith { } -Verifiable
        Mock -CommandName Get-GTGraphErrorDetails -MockWith { return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } } -Verifiable
        Mock -CommandName Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance -MockWith { } -Verifiable
        Mock -CommandName Remove-MgBetaRoleManagementDirectoryRoleAssignmentSchedule -MockWith { } -Verifiable
        Mock -CommandName Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance -MockWith { } -Verifiable
        Mock -CommandName Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule -MockWith { } -Verifiable
        Mock -CommandName Get-MgUser -MockWith { return [PSCustomObject]@{ Id = 'AdminId' } } -Verifiable

        if (Test-Path $functionPath)
        {
            # Dot-source the function under test
            . $functionPath
        }
        else
        {
            Write-Error "Function file not found at $functionPath"
        }
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

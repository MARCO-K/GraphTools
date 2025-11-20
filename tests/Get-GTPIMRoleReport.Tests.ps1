Describe "Get-GTPIMRoleReport" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Get-GTPIMRoleReport.ps1"
        if (Test-Path $functionPath) {
            . $functionPath
        }
        else {
            Write-Error "Function file not found at $functionPath"
        }

        function Install-GTRequiredModule {}
        function Initialize-GTGraphConnection {}
        function Get-MgBetaRoleManagementDirectoryRoleDefinition {}
        function Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance {}
        function Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance {}
        function Test-GTGuid { return $true }

        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $true }
        Mock -CommandName "Test-GTGuid" -MockWith { return $true }
    }

    Context "Functionality" {
        It "should generate a report with eligible and active assignments" {
            # Mock Role Definitions
            $mockRoles = @(
                [PSCustomObject]@{ Id = "Role1"; DisplayName = "Global Admin" }
                [PSCustomObject]@{ Id = "Role2"; DisplayName = "User Admin" }
            )
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleDefinition" -MockWith { return $mockRoles }

            # Mock Eligible
            $mockEligible = @(
                [PSCustomObject]@{
                    PrincipalId      = "User1"
                    RoleDefinitionId = "Role1"
                    StartDateTime    = (Get-Date)
                    EndDateTime      = (Get-Date).AddDays(1)
                    Principal        = [PSCustomObject]@{ DisplayName = "User One"; AdditionalProperties = @{ userPrincipalName = "user1@contoso.com" } }
                }
            )
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance" -MockWith { return $mockEligible }

            # Mock Active
            $mockActive = @(
                [PSCustomObject]@{
                    PrincipalId      = "User2"
                    RoleDefinitionId = "Role2"
                    AssignmentType   = "Assigned"
                    StartDateTime    = (Get-Date)
                    EndDateTime      = $null
                    Principal        = [PSCustomObject]@{ DisplayName = "User Two"; AdditionalProperties = @{ userPrincipalName = "user2@contoso.com" } }
                }
            )
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance" -MockWith { return $mockActive }

            $results = Get-GTPIMRoleReport
            $results.Count | Should -Be 2
            
            $eligible = $results | Where-Object { $_.Type -eq 'Eligible' }
            $eligible.Role | Should -Be "Global Admin"
            $eligible.User | Should -Be "User One"

            $active = $results | Where-Object { $_.Type -eq 'Active' }
            $active.Role | Should -Be "User Admin"
            $active.AssignmentState | Should -BeLike "Assigned*"
        }

        It "should filter by RoleName" {
            # Mock Role Definitions
            $mockRoles = @(
                [PSCustomObject]@{ Id = "Role1"; DisplayName = "Global Admin" }
            )
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleDefinition" -MockWith { return $mockRoles }
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance" -MockWith { return @() }
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance" -MockWith { return @() }

            Get-GTPIMRoleReport -RoleName "Global Admin"
            # Verify logic inside loop handles filtering (mock returns empty so just ensuring no error)
        }
    }
}

Describe "Get-GTPIMRoleReport" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Get-GTPIMRoleReport.ps1"
        # Use Pester Mocks for external dependencies before dot-sourcing
        Mock -CommandName Install-GTRequiredModule -MockWith { } -Verifiable
        Mock -CommandName Test-GTGraphScopes -MockWith { param($RequiredScopes, $Reconnect, $Quiet) return $true } -Verifiable
        Mock -CommandName Get-MgBetaRoleManagementDirectoryRoleDefinition -MockWith { } -Verifiable
        Mock -CommandName Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance -MockWith { } -Verifiable
        Mock -CommandName Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance -MockWith { } -Verifiable
        Mock -CommandName Test-GTGuid -MockWith { param($InputObject, $Quiet) return $true } -Verifiable
        Mock -CommandName Get-GTGraphErrorDetails -MockWith { return @{ LogLevel = 'Error'; Reason = 'Mock Error' } } -Verifiable
        Mock -CommandName Write-PSFMessage -MockWith { } -Verifiable

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
        It "should generate a report with eligible and active assignments including PrincipalType" {
            # Mock Role Definitions
            $mockRoles = @(
                [PSCustomObject]@{ Id = "Role1"; DisplayName = "Global Admin" }
                [PSCustomObject]@{ Id = "Role2"; DisplayName = "User Admin" }
            )
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleDefinition" -MockWith { return $mockRoles }

            # Mock Eligible (User)
            $mockEligible = @(
                [PSCustomObject]@{
                    PrincipalId      = "User1"
                    RoleDefinitionId = "Role1"
                    StartDateTime    = (Get-Date)
                    EndDateTime      = (Get-Date).AddDays(1)
                    Principal        = [PSCustomObject]@{ 
                        DisplayName          = "User One" 
                        AdditionalProperties = @{ 
                            userPrincipalName = "user1@contoso.com"
                            '@odata.type'     = '#microsoft.graph.user'
                        } 
                    }
                }
            )
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance" -MockWith { return $mockEligible }

            # Mock Active (Group)
            $mockActive = @(
                [PSCustomObject]@{
                    PrincipalId      = "Group1"
                    RoleDefinitionId = "Role2"
                    AssignmentType   = "Assigned"
                    StartDateTime    = (Get-Date)
                    EndDateTime      = $null
                    Principal        = [PSCustomObject]@{ 
                        DisplayName          = "Admin Group" 
                        AdditionalProperties = @{ 
                            '@odata.type' = '#microsoft.graph.group'
                        } 
                    }
                }
            )
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance" -MockWith { return $mockActive }

            $results = Get-GTPIMRoleReport
            $results.Count | Should -Be 2
            
            $eligible = $results | Where-Object { $_.Type -eq 'Eligible' }
            $eligible.Role | Should -Be "Global Admin"
            $eligible.User | Should -Be "User One"
            $eligible.PrincipalType | Should -Be "User"
            $eligible.RoleId | Should -Be "Role1"

            $active = $results | Where-Object { $_.Type -eq 'Active' }
            $active.Role | Should -Be "User Admin"
            $active.User | Should -Be "Admin Group"
            $active.PrincipalType | Should -Be "Group"
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

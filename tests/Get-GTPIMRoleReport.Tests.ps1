Describe "Get-GTPIMRoleReport" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Get-GTPIMRoleReport.ps1"
        if (Test-Path $functionPath) {
            . $functionPath
        }
        else {
            Write-Error "Function file not found at $functionPath"
        }

        # Define dummy functions for mocks
        function Install-GTRequiredModule { param($ModuleNames, $Verbose) }
        function Test-GTGraphScopes { param($RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function Get-MgBetaRoleManagementDirectoryRoleDefinition { param([switch]$All, $Property, $ErrorAction) }
        function Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance { param([switch]$All, $ExpandProperty, $ErrorAction, $Filter) }
        function Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance { param([switch]$All, $ExpandProperty, $ErrorAction, $Filter) }
        function Test-GTGuid { param($InputObject, [switch]$Quiet) return $true }
        function Get-GTGraphErrorDetails { param($Exception, $ResourceType) return @{ LogLevel = 'Error'; Reason = 'Mock Error' } }
        function Write-PSFMessage { param($Level, $Message) }

        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Test-GTGraphScopes" -MockWith { return $true }
        Mock -CommandName "Test-GTGuid" -MockWith { return $true }
        Mock -CommandName "Write-PSFMessage" -MockWith { }
        Mock -CommandName "Get-GTGraphErrorDetails" -MockWith { return @{ LogLevel = 'Error'; Reason = 'Mock Error' } }
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

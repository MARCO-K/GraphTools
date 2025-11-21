## Provide lightweight stubs for common helpers in case they are missing during discovery
if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }
if (-not (Get-Command Get-GTGraphErrorDetails -ErrorAction SilentlyContinue)) { function Get-GTGraphErrorDetails { param($Exception, $ResourceType) return @{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } } }

Describe "Get-GTAdminCountReport" {
    BeforeAll {
        # Mock Get-MgContext to simulate being connected
        Mock -CommandName "Get-MgContext" -MockWith {
            return @{ Scopes = @('RoleManagement.Read.Directory', 'Directory.Read.All') }
        }
        $functionPath = "$PSScriptRoot/../functions/Get-GTAdminCountReport.ps1"
        if (Test-Path $functionPath) { . $functionPath } else { Throw "Function file not found: $functionPath" }
    }

    Context "Parameter Validation" {
        It "should accept RoleName parameter" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith { return @() }
            { Get-GTAdminCountReport -RoleName "Global Administrator" } | Should -Not -Throw
        }

        It "should accept multiple RoleName values" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith { return @() }
            { Get-GTAdminCountReport -RoleName @("Global Administrator", "User Administrator") } | Should -Not -Throw
        }

        It "should accept ShowMembers switch" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith { return @() }
            { Get-GTAdminCountReport -ShowMembers } | Should -Not -Throw
        }

        It "should accept NewSession switch" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith { return @() }
            { Get-GTAdminCountReport -NewSession } | Should -Not -Throw
        }
    }

    Context "Pipeline Input" {
        BeforeEach {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith { return @() }
        }

        It "should accept RoleName from pipeline" {
            $result = "Global Administrator" | Get-GTAdminCountReport
            # Should not throw
            $true | Should -BeTrue
        }

        It "should accept multiple RoleNames from pipeline" {
            $result = @("Global Administrator", "User Administrator") | Get-GTAdminCountReport
            # Should not throw
            $true | Should -BeTrue
        }
    }

    Context "Role Filtering" {
        BeforeEach {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Global Administrator"
                        Members = @(
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user'; userPrincipalName = 'admin@contoso.com' }
                                DisplayName = "Admin User"
                            }
                        )
                    },
                    [PSCustomObject]@{
                        DisplayName = "User Administrator"
                        Members = @(
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user'; userPrincipalName = 'useradmin@contoso.com' }
                                DisplayName = "User Admin"
                            }
                        )
                    }
                )
            }
        }

        It "should filter by specific role name" {
            $result = Get-GTAdminCountReport -RoleName "Global Administrator"
            $result.RoleName | Should -Contain "Global Administrator"
            $result | Where-Object { $_.RoleName -ne "Global Administrator" } | Should -BeNullOrEmpty
        }

        It "should filter by multiple role names" {
            $result = Get-GTAdminCountReport -RoleName @("Global Administrator", "User Administrator")
            $result.Count | Should -Be 2
            $result.RoleName | Should -Contain "Global Administrator"
            $result.RoleName | Should -Contain "User Administrator"
        }

        It "should return all roles when no filter specified" {
            $result = Get-GTAdminCountReport
            $result.Count | Should -Be 2
        }
    }

    Context "Member Counting" {
        It "should count user members correctly" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Global Administrator"
                        Members = @(
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user'; userPrincipalName = 'admin1@contoso.com' }
                                DisplayName = "Admin 1"
                            },
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user'; userPrincipalName = 'admin2@contoso.com' }
                                DisplayName = "Admin 2"
                            }
                        )
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result.UserCount | Should -Be 2
            $result.TotalMembers | Should -Be 2
            $result.ServicePrincipalCount | Should -Be 0
            $result.GroupCount | Should -Be 0
        }

        It "should count service principal members correctly" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Application Administrator"
                        Members = @(
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.servicePrincipal' }
                                DisplayName = "My App SP"
                            },
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.servicePrincipal' }
                                DisplayName = "Another App SP"
                            }
                        )
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result.ServicePrincipalCount | Should -Be 2
            $result.TotalMembers | Should -Be 2
            $result.UserCount | Should -Be 0
            $result.GroupCount | Should -Be 0
        }

        It "should count group members correctly" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Security Administrator"
                        Members = @(
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.group' }
                                DisplayName = "Admin Group"
                            }
                        )
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result.GroupCount | Should -Be 1
            $result.TotalMembers | Should -Be 1
            $result.UserCount | Should -Be 0
            $result.ServicePrincipalCount | Should -Be 0
        }

        It "should count mixed member types correctly" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Global Administrator"
                        Members = @(
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user'; userPrincipalName = 'admin@contoso.com' }
                                DisplayName = "Admin User"
                            },
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.servicePrincipal' }
                                DisplayName = "Admin SP"
                            },
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.group' }
                                DisplayName = "Admin Group"
                            }
                        )
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result.TotalMembers | Should -Be 3
            $result.UserCount | Should -Be 1
            $result.ServicePrincipalCount | Should -Be 1
            $result.GroupCount | Should -Be 1
        }

        It "should handle roles with no members" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Empty Role"
                        Members = $null
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result.TotalMembers | Should -Be 0
            $result.UserCount | Should -Be 0
            $result.ServicePrincipalCount | Should -Be 0
            $result.GroupCount | Should -Be 0
        }
    }

    Context "Risk Tier Classification" {
        It "should classify Tier 0 (Critical) roles correctly" {
            $tier0Roles = @('Global Administrator', 'Privileged Role Administrator', 'Security Administrator', 'Hybrid Identity Administrator')

            foreach ($roleName in $tier0Roles) {
                Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                    return @(
                        [PSCustomObject]@{
                            DisplayName = $roleName
                            Members = @()
                        }
                    )
                }

                $result = Get-GTAdminCountReport
                $result.Tier | Should -Be "Tier 0 (Critical)"
            }
        }

        It "should classify Tier 1 (High) roles correctly" {
            $tier1Roles = @('Exchange Administrator', 'SharePoint Administrator', 'User Administrator', 'Authentication Administrator', 'Cloud Application Administrator', 'Intune Administrator')

            foreach ($roleName in $tier1Roles) {
                Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                    return @(
                        [PSCustomObject]@{
                            DisplayName = $roleName
                            Members = @()
                        }
                    )
                }

                $result = Get-GTAdminCountReport
                $result.Tier | Should -Be "Tier 1 (High)"
            }
        }

        It "should classify other roles as Tier 2 (Standard)" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Helpdesk Administrator"
                        Members = @()
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result.Tier | Should -Be "Tier 2 (Standard)"
        }
    }

    Context "Risk Analysis" {
        It "should flag Global Administrator with >5 users" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                $members = @()
                for ($i = 1; $i -le 6; $i++) {
                    $members += [PSCustomObject]@{
                        AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user'; userPrincipalName = "admin$i@contoso.com" }
                        DisplayName = "Admin $i"
                    }
                }

                return @(
                    [PSCustomObject]@{
                        DisplayName = "Global Administrator"
                        Members = $members
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result.RiskNote | Should -Contain "High: >5 Global Admins detected."
        }

        It "should not flag Global Administrator with <=5 users" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                $members = @()
                for ($i = 1; $i -le 5; $i++) {
                    $members += [PSCustomObject]@{
                        AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user'; userPrincipalName = "admin$i@contoso.com" }
                        DisplayName = "Admin $i"
                    }
                }

                return @(
                    [PSCustomObject]@{
                        DisplayName = "Global Administrator"
                        Members = $members
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result.RiskNote | Should -BeNullOrEmpty
        }

        It "should flag roles with group assignments" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "User Administrator"
                        Members = @(
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.group' }
                                DisplayName = "Admin Users Group"
                            }
                        )
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result.RiskNote | Should -Contain "Warning: Role assigned to Group. Verify Group membership controls."
        }

        It "should not have risk notes for normal assignments" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "User Administrator"
                        Members = @(
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user'; userPrincipalName = 'useradmin@contoso.com' }
                                DisplayName = "User Admin"
                            }
                        )
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result.RiskNote | Should -BeNullOrEmpty
        }
    }

    Context "ShowMembers Functionality" {
        It "should include member details when ShowMembers is used" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Global Administrator"
                        Members = @(
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user'; userPrincipalName = 'admin@contoso.com' }
                                DisplayName = "Admin User"
                            },
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.servicePrincipal' }
                                DisplayName = "Admin SP"
                            }
                        )
                    }
                )
            }

            $result = Get-GTAdminCountReport -ShowMembers
            $result.Members | Should -Not -BeNullOrEmpty
            $result.Members | Should -Match "admin@contoso\.com \(User\)"
            $result.Members | Should -Match "Admin SP \(SP\)"
        }

        It "should not include Members property when ShowMembers is not used" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Global Administrator"
                        Members = @(
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user'; userPrincipalName = 'admin@contoso.com' }
                                DisplayName = "Admin User"
                            }
                        )
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result.PSObject.Properties.Name | Should -Not -Contain "Members"
        }

        It "should handle missing userPrincipalName gracefully" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Global Administrator"
                        Members = @(
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user' }  # No UPN
                                DisplayName = "Admin User"
                            }
                        )
                    }
                )
            }

            $result = Get-GTAdminCountReport -ShowMembers
            $result.Members | Should -Match "Admin User \(User\)"
        }
    }

    Context "Output Format and Sorting" {
        It "should return PSCustomObject with correct properties" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Global Administrator"
                        Members = @()
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result | Should -BeOfType [PSCustomObject]
            $result.PSObject.Properties.Name | Should -Contain "RoleName"
            $result.PSObject.Properties.Name | Should -Contain "Tier"
            $result.PSObject.Properties.Name | Should -Contain "TotalMembers"
            $result.PSObject.Properties.Name | Should -Contain "UserCount"
            $result.PSObject.Properties.Name | Should -Contain "ServicePrincipalCount"
            $result.PSObject.Properties.Name | Should -Contain "GroupCount"
            $result.PSObject.Properties.Name | Should -Contain "RiskNote"
        }

        It "should sort by Tier then TotalMembers (descending)" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Helpdesk Administrator"  # Tier 2, 1 member
                        Members = @([PSCustomObject]@{ AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user' }; DisplayName = "Helpdesk" })
                    },
                    [PSCustomObject]@{
                        DisplayName = "Global Administrator"  # Tier 0, 2 members
                        Members = @(
                            [PSCustomObject]@{ AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user' }; DisplayName = "Admin1" },
                            [PSCustomObject]@{ AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user' }; DisplayName = "Admin2" }
                        )
                    },
                    [PSCustomObject]@{
                        DisplayName = "User Administrator"  # Tier 1, 3 members
                        Members = @(
                            [PSCustomObject]@{ AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user' }; DisplayName = "User1" },
                            [PSCustomObject]@{ AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user' }; DisplayName = "User2" },
                            [PSCustomObject]@{ AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.user' }; DisplayName = "User3" }
                        )
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result[0].Tier | Should -Be "Tier 0 (Critical)"
            $result[0].TotalMembers | Should -Be 2
            $result[1].Tier | Should -Be "Tier 1 (High)"
            $result[1].TotalMembers | Should -Be 3
            $result[2].Tier | Should -Be "Tier 2 (Standard)"
            $result[2].TotalMembers | Should -Be 1
        }

        It "should return empty array when no roles found" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith { return @() }

            $result = Get-GTAdminCountReport
            $result | Should -Be @()
        }
    }

    Context "Error Handling" {
        It "should handle Graph API errors gracefully" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith { throw "Graph API Error" }

            { Get-GTAdminCountReport } | Should -Throw
        }

        It "should handle connection failures" {
            Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $false }

            { Get-GTAdminCountReport } | Should -Throw
        }

        It "should handle scope validation failures" {
            Mock -CommandName "Test-GTGraphScopes" -MockWith { return $false }

            { Get-GTAdminCountReport } | Should -Throw
        }
    }

    Context "Performance and Edge Cases" {
        It "should handle roles with empty members array" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Empty Role"
                        Members = @()
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result.TotalMembers | Should -Be 0
        }

        It "should handle members with missing AdditionalProperties" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Test Role"
                        Members = @(
                            [PSCustomObject]@{
                                DisplayName = "Member without properties"
                            }
                        )
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result.TotalMembers | Should -Be 1
            $result.UserCount | Should -Be 0
            $result.ServicePrincipalCount | Should -Be 0
            $result.GroupCount | Should -Be 0
        }

        It "should handle unknown member types" {
            Mock -CommandName "Get-MgDirectoryRole" -MockWith {
                return @(
                    [PSCustomObject]@{
                        DisplayName = "Test Role"
                        Members = @(
                            [PSCustomObject]@{
                                AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.unknownType' }
                                DisplayName = "Unknown Member"
                            }
                        )
                    }
                )
            }

            $result = Get-GTAdminCountReport
            $result.TotalMembers | Should -Be 1
            $result.UserCount | Should -Be 0
            $result.ServicePrincipalCount | Should -Be 0
            $result.GroupCount | Should -Be 0
        }
    }
}</content>
<parameter name="filePath">c:\tools\personal\git\GraphTools\tests\Get-GTAdminCountReport.Tests.ps1
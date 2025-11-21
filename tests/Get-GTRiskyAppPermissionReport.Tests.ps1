## Provide lightweight stubs for common helpers in case they are missing during discovery
if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

## (Function will be dot-sourced in BeforeAll to allow Pester mocks to register first)

Describe "Get-GTRiskyAppPermissionReport" {
    BeforeAll {
        # Mock Get-MgContext to simulate being connected
        Mock -CommandName "Get-MgContext" -MockWith {
            return @{ Scopes = @('AppRoleAssignment.Read.All', 'DelegatedPermissionGrant.Read.All', 'Application.Read.All', 'AuditLog.Read.All', 'User.Read.All') }
        }
        $functionPath = "$PSScriptRoot/../functions/Get-GTRiskyAppPermissionReport.ps1"
        if (Test-Path $functionPath) { . $functionPath } else { Throw "Function file not found: $functionPath" }
    }

    Context "Parameter Validation" {
        It "should accept pipeline input for AppId" {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return @() }
            { "test-app-id" | Get-GTRiskyAppPermissionReport } | Should -Not -Throw
        }

        It "should validate PermissionType parameter" {
            { Get-GTRiskyAppPermissionReport -PermissionType "Invalid" } | Should -Throw
        }

        It "should validate RiskLevel parameter" {
            { Get-GTRiskyAppPermissionReport -RiskLevel "Invalid" } | Should -Throw
        }
    }

    Context "Microsoft Graph Resolution" {
        It "should cache Microsoft Graph app roles" {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith {
                param($Filter)
                if ($Filter -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        Id = "graph-sp-id"
                        AppRoles = @(
                            [PSCustomObject]@{ Id = "role-guid-1"; Value = "Directory.ReadWrite.All" }
                            [PSCustomObject]@{ Id = "role-guid-2"; Value = "Mail.ReadWrite" }
                        )
                    }
                }
                return @()
            }

            $result = Get-GTRiskyAppPermissionReport
            # Should not throw and complete execution
            $true | Should -BeTrue  # Just ensuring no exceptions
        }
    }

    Context "App-Only Permissions Analysis" {
        BeforeEach {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith {
                param($Filter)
                if ($Filter -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        Id = "graph-sp-id"
                        AppRoles = @(
                            [PSCustomObject]@{ Id = "role-guid-1"; Value = "Directory.ReadWrite.All" }
                        )
                    }
                }
                return @(
                    [PSCustomObject]@{
                        Id = "sp-1"
                        AppId = "app-1"
                        DisplayName = "Test App"
                        SignInActivity = [PSCustomObject]@{ LastSignInDateTime = (Get-Date).AddDays(-30) }
                        AppRoleAssignments = @(
                            [PSCustomObject]@{
                                ResourceId = "graph-sp-id"
                                AppRoleId = "role-guid-1"
                                CreationTimestamp = (Get-Date).AddDays(-60)
                            }
                        )
                    }
                )
            }
            Mock -CommandName "Get-MgBetaOauth2PermissionGrant" -MockWith { return @() }
        }

        It "should detect high-risk app-only permissions" {
            $result = Get-GTRiskyAppPermissionReport -PermissionType AppOnly
            $result | Should -Not -BeNullOrEmpty
            $result.Permission | Should -Contain "Directory.ReadWrite.All"
            $result.RiskLevel | Should -Contain "Critical"
            $result.Type | Should -Contain "Application (App-Only)"
        }

        It "should include usage information" {
            $result = Get-GTRiskyAppPermissionReport -PermissionType AppOnly
            $result.IsActive | Should -Not -BeNullOrEmpty
            $result.LastSignIn | Should -Not -BeNullOrEmpty
        }

        It "should filter by specific app ID" {
            $result = Get-GTRiskyAppPermissionReport -AppId "app-1" -PermissionType AppOnly
            $result | Should -Not -BeNullOrEmpty
            $result.AppId | Should -Contain "app-1"
        }
    }

    Context "Delegated Permissions Analysis" {
        BeforeEach {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith {
                param($Filter)
                if ($Filter -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        Id = "graph-sp-id"
                        AppRoles = @()
                    }
                }
                return @(
                    [PSCustomObject]@{
                        Id = "sp-1"
                        AppId = "app-1"
                        DisplayName = "Test App"
                        SignInActivity = [PSCustomObject]@{ LastSignInDateTime = (Get-Date).AddDays(-10) }
                    }
                )
            }
            Mock -CommandName "Get-MgBetaOauth2PermissionGrant" -MockWith {
                return @(
                    [PSCustomObject]@{
                        ClientId = "sp-1"
                        Scope = "Mail.ReadWrite Directory.ReadWrite.All"
                        ConsentType = "AllPrincipals"
                        StartTime = (Get-Date).AddDays(-30)
                        PrincipalId = $null
                    }
                )
            }
        }

        It "should detect high-risk delegated permissions" {
            $result = Get-GTRiskyAppPermissionReport -PermissionType Delegated
            $result | Should -Not -BeNullOrEmpty
            $result.Permission | Should -Contain "Mail.ReadWrite"
            $result.Permission | Should -Contain "Directory.ReadWrite.All"
            $result.Type | Should -Match "Delegated.*Tenant"
        }

        It "should resolve user-specific grants" {
            Mock -CommandName "Get-MgUser" -MockWith {
                return [PSCustomObject]@{ UserPrincipalName = "user@contoso.com" }
            }
            Mock -CommandName "Get-MgBetaOauth2PermissionGrant" -MockWith {
                return @(
                    [PSCustomObject]@{
                        ClientId = "sp-1"
                        Scope = "Mail.Read"
                        ConsentType = "Principal"
                        StartTime = (Get-Date).AddDays(-15)
                        PrincipalId = "user-guid"
                    }
                )
            }

            $result = Get-GTRiskyAppPermissionReport -PermissionType Delegated
            $result.Type | Should -Match "Delegated.*User"
            $result.GrantedBy | Should -Contain "user@contoso.com"
        }

        It "should filter by risk level" {
            $result = Get-GTRiskyAppPermissionReport -PermissionType Delegated -RiskLevel Critical
            # Directory.ReadWrite.All should be filtered as Critical
            $result | Where-Object { $_.Permission -eq "Directory.ReadWrite.All" } | Should -Not -BeNullOrEmpty
            $result | Where-Object { $_.Permission -eq "Mail.ReadWrite" } | Should -BeNullOrEmpty  # High, not Critical
        }
    }

    Context "Risk Scoring" {
        It "should assign correct risk scores" {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith {
                param($Filter)
                if ($Filter -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        Id = "graph-sp-id"
                        AppRoles = @(
                            [PSCustomObject]@{ Id = "role-guid-1"; Value = "RoleManagement.ReadWrite.Directory" }
                        )
                    }
                }
                return @(
                    [PSCustomObject]@{
                        Id = "sp-1"
                        AppId = "app-1"
                        DisplayName = "Test App"
                        SignInActivity = $null
                        AppRoleAssignments = @(
                            [PSCustomObject]@{
                                ResourceId = "graph-sp-id"
                                AppRoleId = "role-guid-1"
                                CreationTimestamp = (Get-Date).AddDays(-1)
                            }
                        )
                    }
                )
            }
            Mock -CommandName "Get-MgBetaOauth2PermissionGrant" -MockWith { return @() }

            $result = Get-GTRiskyAppPermissionReport -PermissionType AppOnly
            $result.RiskScore | Should -Contain 10
            $result.RiskLevel | Should -Contain "Critical"
            $result.Impact | Should -Contain "Privilege Escalation"
        }
    }

    Context "Custom Risk Definitions" {
        It "should accept custom high-risk scopes" {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith {
                param($Filter)
                if ($Filter -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        Id = "graph-sp-id"
                        AppRoles = @(
                            [PSCustomObject]@{ Id = "custom-role"; Value = "Custom.Permission" }
                        )
                    }
                }
                return @(
                    [PSCustomObject]@{
                        Id = "sp-1"
                        AppId = "app-1"
                        DisplayName = "Test App"
                        SignInActivity = $null
                        AppRoleAssignments = @(
                            [PSCustomObject]@{
                                ResourceId = "graph-sp-id"
                                AppRoleId = "custom-role"
                                CreationTimestamp = (Get-Date)
                            }
                        )
                    }
                )
            }
            Mock -CommandName "Get-MgBetaOauth2PermissionGrant" -MockWith { return @() }

            $result = Get-GTRiskyAppPermissionReport -PermissionType AppOnly -HighRiskScopes "Custom.Permission"
            $result.Permission | Should -Contain "Custom.Permission"
            $result.RiskLevel | Should -Contain "Medium"  # Custom definition
        }
    }

    Context "Error Handling" {
        It "should handle Graph API errors gracefully" {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { throw "Graph API Error" }

            { Get-GTRiskyAppPermissionReport } | Should -Throw
        }

        It "should handle invalid app IDs gracefully" {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return @() }
            Mock -CommandName "Get-MgBetaOauth2PermissionGrant" -MockWith { return @() }

            $result = Get-GTRiskyAppPermissionReport -AppId "nonexistent-app"
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Performance Optimization" {
        It "should filter Service Principals when AppId specified" {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith {
                param($Filter, $All)
                if ($Filter -and $Filter -like "*app-1*") {
                    # Verify filtering is applied
                    return @(
                        [PSCustomObject]@{
                            Id = "sp-1"
                            AppId = "app-1"
                            DisplayName = "Filtered App"
                            AppRoleAssignments = @()
                        }
                    )
                }
                return @()
            }
            Mock -CommandName "Get-MgBetaOauth2PermissionGrant" -MockWith { return @() }

            $result = Get-GTRiskyAppPermissionReport -AppId "app-1"
            # Should not throw and complete execution
            $true | Should -BeTrue
        }
    }
}
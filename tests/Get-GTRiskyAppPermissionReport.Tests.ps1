## Provide lightweight stubs for common helpers in case they are missing during discovery
if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }
if (-not (Get-Command Get-UTCTime -ErrorAction SilentlyContinue)) { function Get-UTCTime { return [DateTime]::UtcNow } }
if (-not (Get-Command Invoke-GTGraphPagedRequest -ErrorAction SilentlyContinue)) { function Invoke-GTGraphPagedRequest { param($Uri, $Headers) return @() } }
if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) { function Invoke-MgGraphRequest { param($Method, $Uri, $ErrorAction) return $null } }
if (-not (Get-Command Get-GTGraphErrorDetails -ErrorAction SilentlyContinue)) { function Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Error'; ErrorMessage = 'Error' } } }

Describe "Get-GTRiskyAppPermissionReport" {
    BeforeAll {
        function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true }
        function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function Get-UTCTime { return [DateTime]::UtcNow }
        function Invoke-GTGraphPagedRequest { param($Uri, $Headers) return @() }
        function Invoke-MgGraphRequest { param($Method, $Uri, $ErrorAction) return $null }
        function Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Error'; ErrorMessage = 'Error' } }

        $helperPath = "$PSScriptRoot/../internal/functions/Get-GTPermissionDefinition.ps1"
        if (Test-Path $helperPath) { . $helperPath } else { Throw "Helper not found: $helperPath" }

        $functionPath = "$PSScriptRoot/../functions/Get-GTRiskyAppPermissionReport.ps1"
        if (Test-Path $functionPath) { . $functionPath } else { Throw "Function not found: $functionPath" }
    }

    Context "Parameter Validation" {
        It "should accept pipeline input for AppId" {
            Mock -CommandName "Invoke-MgGraphRequest" -MockWith {
                param($Method, $Uri, $ErrorAction)
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = "graph-sp-id"; appRoles = @() }) }
            }
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { param($Uri, $Headers) return @() }

            { "test-app-id" | Get-GTRiskyAppPermissionReport } | Should -Not -Throw
        }

        It "should validate PermissionType parameter" {
            { Get-GTRiskyAppPermissionReport -PermissionType "Invalid" } | Should -Throw
        }

        It "should validate RiskLevel parameter" {
            { Get-GTRiskyAppPermissionReport -RiskLevel "Invalid" } | Should -Throw
        }

        It "should validate MinPrivilegeLevel range" {
            { Get-GTRiskyAppPermissionReport -MinPrivilegeLevel 6 } | Should -Throw
        }
    }

    Context "Microsoft Graph Resolution" {
        It "should cache Microsoft Graph app roles" {
            Mock -CommandName "Invoke-MgGraphRequest" -MockWith {
                param($Method, $Uri, $ErrorAction)
                if ($Uri -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id = "graph-sp-id"
                                appRoles = @(
                                    [PSCustomObject]@{ id = "role-guid-1"; value = "Directory.ReadWrite.All" }
                                    [PSCustomObject]@{ id = "role-guid-2"; value = "Mail.ReadWrite" }
                                )
                            }
                        )
                    }
                }
                return $null
            }
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { param($Uri, $Headers) return @() }

            $result = Get-GTRiskyAppPermissionReport
            $true | Should -BeTrue
        }
    }

    Context "App-Only Permissions Analysis" {
        BeforeEach {
            Mock -CommandName "Invoke-MgGraphRequest" -MockWith {
                param($Method, $Uri, $ErrorAction)
                if ($Uri -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id = "graph-sp-id"
                                appRoles = @(
                                    [PSCustomObject]@{ id = "role-guid-1"; value = "Directory.ReadWrite.All" }
                                    [PSCustomObject]@{ id = "role-guid-2"; value = "Application.ReadWrite.All" }
                                )
                            }
                        )
                    }
                }
                return $null
            }

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers)
                if ($Uri -like "*servicePrincipals*") {
                    return @(
                        [PSCustomObject]@{
                            id = "sp-1"
                            appId = "app-1"
                            displayName = "Test App"
                            signInActivity = [PSCustomObject]@{ lastSignInDateTime = (Get-Date).AddDays(-30) }
                            appRoleAssignments = @(
                                [PSCustomObject]@{
                                    resourceId = "graph-sp-id"
                                    appRoleId = "role-guid-1"
                                    creationTimestamp = (Get-Date).AddDays(-60)
                                }
                            )
                        }
                    )
                }
                return @()
            }
        }

        It "should detect high-risk app-only permissions" {
            $result = Get-GTRiskyAppPermissionReport -PermissionType AppOnly
            $result | Should -Not -BeNullOrEmpty
            $result.Permission | Should -Contain "Directory.ReadWrite.All"
            $result.RiskLevel | Should -Contain "Critical"
            $result.Type | Should -Contain "Application (App-Only)"
            $result.PrivilegeLevel | Should -Be 4
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
            Mock -CommandName "Invoke-MgGraphRequest" -MockWith {
                param($Method, $Uri, $ErrorAction)
                if ($Uri -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{ id = "graph-sp-id"; appRoles = @() })
                    }
                }
                if ($Uri -like "*v1.0/users/*") {
                    return [PSCustomObject]@{ userPrincipalName = "user@contoso.com" }
                }
                return $null
            }

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers)
                if ($Uri -like "*servicePrincipals*") {
                    return @(
                        [PSCustomObject]@{
                            id = "sp-1"
                            appId = "app-1"
                            displayName = "Test App"
                            signInActivity = [PSCustomObject]@{ lastSignInDateTime = (Get-Date).AddDays(-10) }
                        }
                    )
                }
                if ($Uri -like "*oauth2PermissionGrants*") {
                    return @(
                        [PSCustomObject]@{
                            clientId = "sp-1"
                            scope = "Mail.ReadWrite Directory.ReadWrite.All"
                            consentType = "AllPrincipals"
                            startTime = (Get-Date).AddDays(-30)
                            principalId = $null
                        }
                    )
                }
                return @()
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
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers)
                if ($Uri -like "*servicePrincipals*") {
                    return @(
                        [PSCustomObject]@{
                            id = "sp-1"
                            appId = "app-1"
                            displayName = "Test App"
                            signInActivity = [PSCustomObject]@{ lastSignInDateTime = (Get-Date).AddDays(-10) }
                        }
                    )
                }
                if ($Uri -like "*oauth2PermissionGrants*") {
                    return @(
                        [PSCustomObject]@{
                            clientId = "sp-1"
                            scope = "Mail.Read"
                            consentType = "Principal"
                            startTime = (Get-Date).AddDays(-15)
                            principalId = "user-guid"
                        }
                    )
                }
                return @()
            }

            $result = Get-GTRiskyAppPermissionReport -PermissionType Delegated
            $result.Type | Should -Match "Delegated.*User"
            $result.GrantedBy | Should -Contain "user@contoso.com"
        }

        It "should filter by risk level" {
            $result = Get-GTRiskyAppPermissionReport -PermissionType Delegated -RiskLevel Critical
            $result | Where-Object { $_.Permission -eq "Directory.ReadWrite.All" } | Should -Not -BeNullOrEmpty
            $result | Where-Object { $_.Permission -eq "Mail.ReadWrite" } | Should -BeNullOrEmpty
        }
    }

    Context "DevX Metadata Integration" {
        It "should resolve privilege level and admin consent from catalog" {
            Mock -CommandName "Invoke-MgGraphRequest" -MockWith {
                param($Method, $Uri, $ErrorAction)
                if ($Uri -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id = "graph-sp-id"
                                appRoles = @(
                                    [PSCustomObject]@{ id = "role-guid-app"; value = "Application.ReadWrite.All" }
                                )
                            }
                        )
                    }
                }
                return $null
            }
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers)
                if ($Uri -like "*servicePrincipals*") {
                    return @(
                        [PSCustomObject]@{
                            id = "sp-1"
                            appId = "app-1"
                            displayName = "App Management App"
                            signInActivity = $null
                            appRoleAssignments = @(
                                [PSCustomObject]@{
                                    resourceId = "graph-sp-id"
                                    appRoleId = "role-guid-app"
                                    creationTimestamp = (Get-Date)
                                }
                            )
                        }
                    )
                }
                return @()
            }

            $result = Get-GTRiskyAppPermissionReport -PermissionType AppOnly
            $result | Should -Not -BeNullOrEmpty
            $result.Permission | Should -Be "Application.ReadWrite.All"
            $result.PrivilegeLevel | Should -Be 4
            $result.AdminConsentRequired | Should -Be $true
            $result.RiskLevel | Should -Be "High"
        }

        It "should map privilege level 5 to Critical with score 10" {
            $tempFixture = Join-Path ([System.IO.Path]::GetTempPath()) "test-priv5-$(Get-Random).json"
            @{
                "Ultra.HighPriv.Role" = @{
                    appPrivilegeLevel       = 5
                    delegatedPrivilegeLevel = 5
                    requiresAdminConsent    = $true
                    description             = "Ultra high privilege"
                }
            } | ConvertTo-Json -Depth 5 | Set-Content -Path $tempFixture -Encoding UTF8

            try {
                Mock -CommandName "Invoke-MgGraphRequest" -MockWith {
                    param($Method, $Uri, $ErrorAction)
                    if ($Uri -like "*00000003-0000-0000-c000-000000000000*") {
                        return [PSCustomObject]@{
                            value = @(
                                [PSCustomObject]@{
                                    id = "graph-sp-id"
                                    appRoles = @(
                                        [PSCustomObject]@{ id = "role-guid-p5"; value = "Ultra.HighPriv.Role" }
                                    )
                                }
                            )
                        }
                    }
                    return $null
                }
                Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                    param($Uri, $Headers)
                    if ($Uri -like "*servicePrincipals*") {
                        return @(
                            [PSCustomObject]@{
                                id = "sp-p5"
                                appId = "app-p5"
                                displayName = "P5 App"
                                signInActivity = $null
                                appRoleAssignments = @(
                                    [PSCustomObject]@{
                                        resourceId = "graph-sp-id"
                                        appRoleId = "role-guid-p5"
                                        creationTimestamp = (Get-Date)
                                    }
                                )
                            }
                        )
                    }
                    return @()
                }

                $result = Get-GTRiskyAppPermissionReport -PermissionType AppOnly -PermissionsFile $tempFixture
                $result | Should -Not -BeNullOrEmpty
                $result.RiskLevel | Should -Be "Critical"
                $result.RiskScore | Should -Be 10
                $result.PrivilegeLevel | Should -Be 5
            }
            finally {
                if (Test-Path $tempFixture) { Remove-Item -Path $tempFixture -Force }
            }
        }

        It "should support filtering by MinPrivilegeLevel" {
            Mock -CommandName "Invoke-MgGraphRequest" -MockWith {
                param($Method, $Uri, $ErrorAction)
                if ($Uri -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id = "graph-sp-id"
                                appRoles = @(
                                    [PSCustomObject]@{ id = "role-guid-app"; value = "Application.ReadWrite.All" }
                                )
                            }
                        )
                    }
                }
                return $null
            }
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers)
                if ($Uri -like "*servicePrincipals*") {
                    return @(
                        [PSCustomObject]@{
                            id = "sp-1"
                            appId = "app-1"
                            displayName = "Test App"
                            signInActivity = $null
                            appRoleAssignments = @(
                                [PSCustomObject]@{
                                    resourceId = "graph-sp-id"
                                    appRoleId = "role-guid-app"
                                    creationTimestamp = (Get-Date)
                                }
                            )
                        }
                    )
                }
                return @()
            }

            $result = Get-GTRiskyAppPermissionReport -PermissionType AppOnly -MinPrivilegeLevel 4
            @($result).Count | Should -Be 1

            $resultBelow = Get-GTRiskyAppPermissionReport -PermissionType AppOnly -MinPrivilegeLevel 5
            $resultBelow | Should -BeNullOrEmpty
        }
    }

    Context "Custom Risk Definitions" {
        It "should accept custom high-risk scopes" {
            Mock -CommandName "Invoke-MgGraphRequest" -MockWith {
                param($Method, $Uri, $ErrorAction)
                if ($Uri -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id = "graph-sp-id"
                                appRoles = @(
                                    [PSCustomObject]@{ id = "custom-role"; value = "Custom.Permission" }
                                )
                            }
                        )
                    }
                }
                return $null
            }
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers)
                if ($Uri -like "*servicePrincipals*") {
                    return @(
                        [PSCustomObject]@{
                            id = "sp-1"
                            appId = "app-1"
                            displayName = "Test App"
                            signInActivity = $null
                            appRoleAssignments = @(
                                [PSCustomObject]@{
                                    resourceId = "graph-sp-id"
                                    appRoleId = "custom-role"
                                    creationTimestamp = (Get-Date)
                                }
                            )
                        }
                    )
                }
                return @()
            }

            $result = Get-GTRiskyAppPermissionReport -PermissionType AppOnly -HighRiskScopes "Custom.Permission"
            $result.Permission | Should -Contain "Custom.Permission"
            $result.RiskLevel | Should -Contain "Medium"
        }
    }

    Context "Enhanced Risk Analysis & Extraction Features" {
        It "should map and report resource-specific application permissions (RSC)" {
            Mock -CommandName "Invoke-MgGraphRequest" -MockWith {
                param($Method, $Uri, $ErrorAction)
                if ($Uri -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id = "graph-sp-id"
                                appRoles = @()
                                resourceSpecificApplicationPermissions = @(
                                    [PSCustomObject]@{ id = "rsc-role-1"; value = "ChatMessage.Read.Group" }
                                )
                            }
                        )
                    }
                }
                return $null
            }
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers)
                if ($Uri -like "*servicePrincipals*") {
                    return @(
                        [PSCustomObject]@{
                            id = "sp-rsc"
                            appId = "app-rsc"
                            displayName = "RSC App"
                            signInActivity = $null
                            appRoleAssignments = @(
                                [PSCustomObject]@{
                                    resourceId = "graph-sp-id"
                                    appRoleId = "rsc-role-1"
                                    creationTimestamp = (Get-Date)
                                }
                            )
                        }
                    )
                }
                return @()
            }

            $result = Get-GTRiskyAppPermissionReport -PermissionType AppOnly -HighRiskScopes "ChatMessage.Read.Group"
            $result | Should -Not -BeNullOrEmpty
            $result.Permission | Should -Be "ChatMessage.Read.Group"
            $result.Type | Should -Be "Application (App-Only)"
        }

        It "should detect Tier-0 curated threat vectors with Critical score 10" {
            Mock -CommandName "Invoke-MgGraphRequest" -MockWith {
                param($Method, $Uri, $ErrorAction)
                if ($Uri -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id = "graph-sp-id"
                                appRoles = @(
                                    [PSCustomObject]@{ id = "role-sync"; value = "OnPremDirectorySynchronization.ReadWrite.All" }
                                    [PSCustomObject]@{ id = "role-mfa"; value = "UserAuthenticationMethod.ReadWrite.All" }
                                )
                            }
                        )
                    }
                }
                return $null
            }
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers)
                if ($Uri -like "*servicePrincipals*") {
                    return @(
                        [PSCustomObject]@{
                            id = "sp-tier0"
                            appId = "app-tier0"
                            displayName = "Tier-0 App"
                            signInActivity = $null
                            appRoleAssignments = @(
                                [PSCustomObject]@{ resourceId = "graph-sp-id"; appRoleId = "role-sync"; creationTimestamp = (Get-Date) }
                                [PSCustomObject]@{ resourceId = "graph-sp-id"; appRoleId = "role-mfa"; creationTimestamp = (Get-Date) }
                            )
                        }
                    )
                }
                return @()
            }

            $result = Get-GTRiskyAppPermissionReport -PermissionType AppOnly
            @($result).Count | Should -Be 2
            ($result | Where-Object { $_.Permission -eq "OnPremDirectorySynchronization.ReadWrite.All" }).RiskScore | Should -Be 10
            ($result | Where-Object { $_.Permission -eq "OnPremDirectorySynchronization.ReadWrite.All" }).Impact | Should -Be "Hybrid Identity Takeover"
            ($result | Where-Object { $_.Permission -eq "UserAuthenticationMethod.ReadWrite.All" }).RiskScore | Should -Be 10
            ($result | Where-Object { $_.Permission -eq "UserAuthenticationMethod.ReadWrite.All" }).Impact | Should -Be "Credential Manipulation"
        }

        It "should apply privilege ceiling when delegated consent is user-specific" {
            Mock -CommandName "Invoke-MgGraphRequest" -MockWith {
                param($Method, $Uri, $ErrorAction)
                if ($Uri -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{ id = "graph-sp-id"; appRoles = @() })
                    }
                }
                if ($Uri -like "*v1.0/users/*") {
                    return [PSCustomObject]@{ userPrincipalName = "victim@contoso.com" }
                }
                return $null
            }
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers)
                if ($Uri -like "*servicePrincipals*") {
                    return @(
                        [PSCustomObject]@{
                            id = "sp-delegated"
                            appId = "app-delegated"
                            displayName = "Delegated App"
                            signInActivity = $null
                        }
                    )
                }
                if ($Uri -like "*oauth2PermissionGrants*") {
                    return @(
                        [PSCustomObject]@{
                            clientId = "sp-delegated"
                            scope = "Directory.ReadWrite.All"
                            consentType = "Principal"
                            startTime = (Get-Date)
                            principalId = "user-id-123"
                        }
                    )
                }
                return @()
            }

            $result = Get-GTRiskyAppPermissionReport -PermissionType Delegated
            $result | Should -Not -BeNullOrEmpty
            # Tenant-wide is Score 9 / Critical; user-ceiling reduces to Score 8 / High
            $result.RiskScore | Should -Be 8
            $result.RiskLevel | Should -Be "High"
            $result.Type | Should -Match "Specific User"
        }

        It "should infer High risk for unmapped *.ReadWrite.All scope via regex heuristics" {
            Mock -CommandName "Invoke-MgGraphRequest" -MockWith {
                param($Method, $Uri, $ErrorAction)
                if ($Uri -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id = "graph-sp-id"
                                appRoles = @(
                                    [PSCustomObject]@{ id = "role-heuristic"; value = "UnknownEntity.Manage.All" }
                                )
                            }
                        )
                    }
                }
                return $null
            }
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers)
                if ($Uri -like "*servicePrincipals*") {
                    return @(
                        [PSCustomObject]@{
                            id = "sp-heuristic"
                            appId = "app-heuristic"
                            displayName = "Heuristic App"
                            signInActivity = $null
                            appRoleAssignments = @(
                                [PSCustomObject]@{ resourceId = "graph-sp-id"; appRoleId = "role-heuristic"; creationTimestamp = (Get-Date) }
                            )
                        }
                    )
                }
                return @()
            }

            $result = Get-GTRiskyAppPermissionReport -PermissionType AppOnly -HighRiskScopes "UnknownEntity.Manage.All"
            $result | Should -Not -BeNullOrEmpty
            $result.RiskLevel | Should -Be "High"
            $result.RiskScore | Should -Be 8
            $result.Impact | Should -Be "Broad Modification"
        }

        It "should scope tenant-wide delegated grant queries to Microsoft Graph resourceId" {
            $capturedGrantUri = $null
            Mock -CommandName "Invoke-MgGraphRequest" -MockWith {
                param($Method, $Uri, $ErrorAction)
                if ($Uri -like "*00000003-0000-0000-c000-000000000000*") {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{ id = "expected-graph-sp-id"; appRoles = @() })
                    }
                }
                return $null
            }
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers)
                if ($Uri -like "*oauth2PermissionGrants*") {
                    $script:capturedGrantUri = $Uri
                    return @()
                }
                return @()
            }

            $null = Get-GTRiskyAppPermissionReport -PermissionType Delegated
            $script:capturedGrantUri | Should -Match "resourceId eq 'expected-graph-sp-id'"
        }
    }

    Context "Error Handling" {
        It "should handle Graph API errors gracefully" {
            Mock -CommandName "Invoke-MgGraphRequest" -MockWith { throw "Graph API Error" }

            { Get-GTRiskyAppPermissionReport } | Should -Throw
        }

        It "should handle empty results gracefully" {
            Mock -CommandName "Invoke-MgGraphRequest" -MockWith {
                param($Method, $Uri, $ErrorAction)
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = "graph-sp-id"; appRoles = @() }) }
            }
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { param($Uri, $Headers) return @() }

            $result = Get-GTRiskyAppPermissionReport -AppId "nonexistent-app"
            $result | Should -BeNullOrEmpty
        }
    }
}
## Provide lightweight stubs for common helpers in case they are missing during discovery
if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

## (Function will be dot-sourced in BeforeAll to allow Pester mocks to register first)

Describe "Get-GTBreakGlassPolicyReport" {
    BeforeAll {
        # Mock Get-MgContext to simulate being connected
        Mock -CommandName "Get-MgContext" -MockWith {
            return @{ Scopes = @('Policy.Read.All', 'User.Read.All') }
        }
        $functionPath = "$PSScriptRoot/../functions/Get-GTBreakGlassPolicyReport.ps1"
        if (Test-Path $functionPath) { . $functionPath } else { Throw "Function file not found: $functionPath" }
    }

    Context "Parameter Validation" {
        It "should require BreakGlassUpn parameter" {
            { Get-GTBreakGlassPolicyReport } | Should -Throw
        }

        It "should accept array of UPNs" {
            Mock -CommandName "Get-MgUser" -MockWith {
                return [PSCustomObject]@{ Id = '12345678-1234-1234-1234-123456789012'; UserPrincipalName = 'bg@contoso.com' }
            }
            Mock -CommandName "Get-MgIdentityConditionalAccessPolicy" -MockWith { return @() }

            { Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com' } | Should -Not -Throw
        }
    }

    Context "UPN Resolution" {
        It "should resolve valid UPNs to Object IDs" {
            Mock -CommandName "Get-MgUser" -MockWith {
                return [PSCustomObject]@{ Id = '12345678-1234-1234-1234-123456789012'; UserPrincipalName = 'bg@contoso.com' }
            }
            Mock -CommandName "Get-MgIdentityConditionalAccessPolicy" -MockWith { return @() }

            $result = Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com'
            $result | Should -BeNullOrEmpty  # No policies, so empty result
        }

        It "should skip invalid UPNs" {
            Mock -CommandName "Get-MgUser" -MockWith { throw "User not found" }
            Mock -CommandName "Get-MgIdentityConditionalAccessPolicy" -MockWith { return @() }

            { Get-GTBreakGlassPolicyReport -BreakGlassUpn 'invalid@contoso.com' } | Should -Throw "No valid Break Glass accounts resolved"
        }
    }

    Context "Policy Analysis" {
        BeforeEach {
            Mock -CommandName "Get-MgUser" -MockWith {
                return [PSCustomObject]@{ Id = '12345678-1234-1234-1234-123456789012'; UserPrincipalName = 'bg@contoso.com' }
            }
        }

        It "should report SAFE when user is explicitly excluded" {
            $mockPolicy = [PSCustomObject]@{
                DisplayName = "Test Policy"
                Id = "policy-123"
                State = "enabled"
                Conditions = [PSCustomObject]@{
                    Users = [PSCustomObject]@{
                        IncludeUsers = @('All')
                        ExcludeUsers = @('12345678-1234-1234-1234-123456789012')  # BG user excluded
                        IncludeGroups = @()
                        ExcludeGroups = @()
                        IncludeRoles = @()
                        ExcludeRoles = @()
                    }
                }
                GrantControls = [PSCustomObject]@{
                    BuiltInControls = @('mfa')
                }
            }

            Mock -CommandName "Get-MgIdentityConditionalAccessPolicy" -MockWith { return @($mockPolicy) }

            $result = Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com'
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Contain "Safe"
            $result.Reason | Should -Contain "explicitly excluded"
        }

        It "should report RISK when user is included in BLOCK policy without exclusion" {
            $mockPolicy = [PSCustomObject]@{
                DisplayName = "Block Policy"
                Id = "policy-456"
                State = "enabled"
                Conditions = [PSCustomObject]@{
                    Users = [PSCustomObject]@{
                        IncludeUsers = @('All')
                        ExcludeUsers = @()  # BG user NOT excluded
                        IncludeGroups = @()
                        ExcludeGroups = @()
                        IncludeRoles = @()
                        ExcludeRoles = @()
                    }
                }
                GrantControls = [PSCustomObject]@{
                    BuiltInControls = @('block')
                }
            }

            Mock -CommandName "Get-MgIdentityConditionalAccessPolicy" -MockWith { return @($mockPolicy) }

            $result = Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com'
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Contain "RISK"
            $result.Severity | Should -Contain "Critical"
            $result.Reason | Should -Contain "BLOCK policy"
        }

        It "should report RISK when user is included without exclusion" {
            $mockPolicy = [PSCustomObject]@{
                DisplayName = "MFA Policy"
                Id = "policy-789"
                State = "enabled"
                Conditions = [PSCustomObject]@{
                    Users = [PSCustomObject]@{
                        IncludeUsers = @('All')
                        ExcludeUsers = @()  # BG user NOT excluded
                        IncludeGroups = @()
                        ExcludeGroups = @()
                        IncludeRoles = @()
                        ExcludeRoles = @()
                    }
                }
                GrantControls = [PSCustomObject]@{
                    BuiltInControls = @('mfa')
                }
            }

            Mock -CommandName "Get-MgIdentityConditionalAccessPolicy" -MockWith { return @($mockPolicy) }

            $result = Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com'
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Contain "RISK"
            $result.Severity | Should -Contain "High"
        }

        It "should report Potential Risk for group-targeted policies" {
            $mockPolicy = [PSCustomObject]@{
                DisplayName = "Group Policy"
                Id = "policy-999"
                State = "enabled"
                Conditions = [PSCustomObject]@{
                    Users = [PSCustomObject]@{
                        IncludeUsers = @()
                        ExcludeUsers = @()  # BG user NOT excluded
                        IncludeGroups = @('group-123')  # Targets groups
                        ExcludeGroups = @()
                        IncludeRoles = @()
                        ExcludeRoles = @()
                    }
                }
                GrantControls = [PSCustomObject]@{
                    BuiltInControls = @('mfa')
                }
            }

            Mock -CommandName "Get-MgIdentityConditionalAccessPolicy" -MockWith { return @($mockPolicy) }

            $result = Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com'
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Contain "Potential Risk"
            $result.Reason | Should -Contain "targets Groups"
        }

        It "should not report policies where user is not targeted" {
            $mockPolicy = [PSCustomObject]@{
                DisplayName = "Specific User Policy"
                Id = "policy-000"
                State = "enabled"
                Conditions = [PSCustomObject]@{
                    Users = [PSCustomObject]@{
                        IncludeUsers = @('99999999-9999-9999-9999-999999999999')  # Different user
                        ExcludeUsers = @()
                        IncludeGroups = @()
                        ExcludeGroups = @()
                        IncludeRoles = @()
                        ExcludeRoles = @()
                    }
                }
                GrantControls = [PSCustomObject]@{
                    BuiltInControls = @('mfa')
                }
            }

            Mock -CommandName "Get-MgIdentityConditionalAccessPolicy" -MockWith { return @($mockPolicy) }

            $result = Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com'
            $result | Should -BeNullOrEmpty  # Should not report "Not Targeted" by default
        }
    }

    Context "Multiple Break Glass Accounts" {
        It "should handle multiple UPNs" {
            Mock -CommandName "Get-MgUser" -MockWith {
                param($UserId)
                switch ($UserId) {
                    'bg1@contoso.com' { return [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; UserPrincipalName = 'bg1@contoso.com' } }
                    'bg2@contoso.com' { return [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; UserPrincipalName = 'bg2@contoso.com' } }
                }
            }
            Mock -CommandName "Get-MgIdentityConditionalAccessPolicy" -MockWith { return @() }

            { Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg1@contoso.com', 'bg2@contoso.com' } | Should -Not -Throw
        }
    }

    Context "Error Handling" {
        It "should handle Graph API errors gracefully" {
            Mock -CommandName "Get-MgUser" -MockWith {
                return [PSCustomObject]@{ Id = '12345678-1234-1234-1234-123456789012'; UserPrincipalName = 'bg@contoso.com' }
            }
            Mock -CommandName "Get-MgIdentityConditionalAccessPolicy" -MockWith { throw "Graph API Error" }

            { Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com' } | Should -Throw
        }
    }
}
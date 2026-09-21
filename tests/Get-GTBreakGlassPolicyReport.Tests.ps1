## Provide lightweight stubs for common helpers in case they are missing during discovery
if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }
if (-not (Get-Command Get-GTGraphErrorDetails -ErrorAction SilentlyContinue)) { function Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Error'; ErrorMessage = 'Error' } } }
if (-not (Get-Command Invoke-GTGraphRequest -ErrorAction SilentlyContinue)) { function Invoke-GTGraphRequest { param($Method, $Uri, $Body, $ContentType, $ErrorAction) } }
if (-not (Get-Command Invoke-GTGraphPagedRequest -ErrorAction SilentlyContinue)) { function Invoke-GTGraphPagedRequest { param($Uri, $Headers) return @() } }

Describe "Get-GTBreakGlassPolicyReport" {
    BeforeAll {
        function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true }
        function Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Error'; ErrorMessage = 'Error' } }
        function Invoke-GTGraphRequest { param($Method, $Uri, $Body, $ContentType, $ErrorAction) }
        function Invoke-GTGraphPagedRequest { param($Uri, $Headers) return @() }

        # Mock Get-MgContext to simulate being connected
        Mock -CommandName "Get-MgContext" -MockWith {
            return @{ Scopes = @('Policy.Read.All', 'User.Read.All'); AuthType = 'Delegated' }
        }
        $functionPath = "$PSScriptRoot/../functions/Get-GTBreakGlassPolicyReport.ps1"
        if (Test-Path $functionPath) { . $functionPath } else { Throw "Function file not found: $functionPath" }
    }

    BeforeEach {
        Mock -CommandName "Invoke-GTGraphRequest" -MockWith {
            param($Method, $Uri)
            if ($Uri -match 'users/([^?]+)') {
                $u = $Matches[1]
                if ($u -eq 'invalid@contoso.com') { throw "User not found" }
                if ($u -eq 'bg1@contoso.com') { return [PSCustomObject]@{ id = '11111111-1111-1111-1111-111111111111'; userPrincipalName = 'bg1@contoso.com' } }
                if ($u -eq 'bg2@contoso.com') { return [PSCustomObject]@{ id = '22222222-2222-2222-2222-222222222222'; userPrincipalName = 'bg2@contoso.com' } }
                return [PSCustomObject]@{ id = '12345678-1234-1234-1234-123456789012'; userPrincipalName = $u }
            }
            return $null
        }
        Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @() }
    }

    Context "Parameter Validation" {
        It "should require BreakGlassUpn parameter" {
            (Get-Command Get-GTBreakGlassPolicyReport).Parameters['BreakGlassUpn'].Attributes.Mandatory -contains $true | Should -BeTrue
        }

        It "should accept array of UPNs" {
            { Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com' } | Should -Not -Throw
        }
    }

    Context "UPN Resolution" {
        It "should resolve valid UPNs to Object IDs" {
            $result = Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com'
            $result | Should -BeNullOrEmpty  # No policies, so empty result
        }

        It "should skip invalid UPNs" {
            { Get-GTBreakGlassPolicyReport -BreakGlassUpn 'invalid@contoso.com' -ErrorAction Stop } | Should -Throw "*Could not find Break Glass user*"
        }
    }

    Context "Policy Analysis" {
        It "should report SAFE when user is explicitly excluded" {
            $mockPolicy = [PSCustomObject]@{
                displayName   = "Test Policy"
                id            = "policy-123"
                state         = "enabled"
                conditions    = [PSCustomObject]@{
                    users = [PSCustomObject]@{
                        includeUsers  = @('All')
                        excludeUsers  = @('12345678-1234-1234-1234-123456789012')  # BG user excluded
                        includeGroups = @()
                        excludeGroups = @()
                        includeRoles  = @()
                        excludeRoles  = @()
                    }
                }
                grantControls = [PSCustomObject]@{
                    builtInControls = @('mfa')
                }
            }

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @($mockPolicy) }

            $result = Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com'
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Safe"
            $result.Reason | Should -Match "explicitly excluded"
        }

        It "should report RISK when user is included in BLOCK policy without exclusion" {
            $mockPolicy = [PSCustomObject]@{
                displayName   = "Block Policy"
                id            = "policy-456"
                state         = "enabled"
                conditions    = [PSCustomObject]@{
                    users = [PSCustomObject]@{
                        includeUsers  = @('All')
                        excludeUsers  = @()  # BG user NOT excluded
                        includeGroups = @()
                        excludeGroups = @()
                        includeRoles  = @()
                        excludeRoles  = @()
                    }
                }
                grantControls = [PSCustomObject]@{
                    builtInControls = @('block')
                }
            }

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @($mockPolicy) }

            $result = Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com'
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "RISK"
            $result.Severity | Should -Be "Critical"
            $result.Reason | Should -Match "BLOCK policy"
        }

        It "should report RISK when user is included without exclusion" {
            $mockPolicy = [PSCustomObject]@{
                displayName   = "MFA Policy"
                id            = "policy-789"
                state         = "enabled"
                conditions    = [PSCustomObject]@{
                    users = [PSCustomObject]@{
                        includeUsers  = @('All')
                        excludeUsers  = @()  # BG user NOT excluded
                        includeGroups = @()
                        excludeGroups = @()
                        includeRoles  = @()
                        excludeRoles  = @()
                    }
                }
                grantControls = [PSCustomObject]@{
                    builtInControls = @('mfa')
                }
            }

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @($mockPolicy) }

            $result = Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com'
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "RISK"
            $result.Severity | Should -Be "High"
        }

        It "should report Potential Risk for group-targeted policies" {
            $mockPolicy = [PSCustomObject]@{
                displayName   = "Group Policy"
                id            = "policy-999"
                state         = "enabled"
                conditions    = [PSCustomObject]@{
                    users = [PSCustomObject]@{
                        includeUsers  = @()
                        excludeUsers  = @()  # BG user NOT excluded
                        includeGroups = @('group-123')  # Targets groups
                        excludeGroups = @()
                        includeRoles  = @()
                        excludeRoles  = @()
                    }
                }
                grantControls = [PSCustomObject]@{
                    builtInControls = @('mfa')
                }
            }

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @($mockPolicy) }

            $result = Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com'
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Potential Risk"
            $result.Reason | Should -Match "targets Groups"
        }

        It "should not report policies where user is not targeted" {
            $mockPolicy = [PSCustomObject]@{
                displayName   = "Specific User Policy"
                id            = "policy-000"
                state         = "enabled"
                conditions    = [PSCustomObject]@{
                    users = [PSCustomObject]@{
                        includeUsers  = @('99999999-9999-9999-9999-999999999999')  # Different user
                        excludeUsers  = @()
                        includeGroups = @()
                        excludeGroups = @()
                        includeRoles  = @()
                        excludeRoles  = @()
                    }
                }
                grantControls = [PSCustomObject]@{
                    builtInControls = @('mfa')
                }
            }

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @($mockPolicy) }

            $result = Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com'
            $result | Should -BeNullOrEmpty  # Should not report "Not Targeted" by default
        }
    }

    Context "Multiple Break Glass Accounts" {
        It "should handle multiple UPNs" {
            { Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg1@contoso.com', 'bg2@contoso.com' } | Should -Not -Throw
        }
    }

    Context "Error Handling" {
        It "should handle Graph API errors gracefully" {
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { throw "Graph API Error" }

            { Get-GTBreakGlassPolicyReport -BreakGlassUpn 'bg@contoso.com' } | Should -Throw
        }
    }
}
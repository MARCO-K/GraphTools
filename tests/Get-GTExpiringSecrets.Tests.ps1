## Provide lightweight stubs for common helpers in case they are missing during discovery
if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param($ModuleNames, $Verbose) } }
if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param($Scopes, $NewSession) return $true } }
if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param($RequiredScopes, $Reconnect, $Quiet) return $true } }
if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "Get-GTExpiringSecrets" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Get-GTExpiringSecrets.ps1"
        # Use Pester Mocks before dot-sourcing so the function file can load and calls are intercepted
        Mock -CommandName Install-GTRequiredModule -MockWith { param($ModuleNames, $Verbose) } -Verifiable
        Mock -CommandName Test-GTGraphScopes -MockWith { param($RequiredScopes, $Reconnect, $Quiet) return $true } -Verifiable
        Mock -CommandName Get-MgBetaApplication -MockWith { } -Verifiable
        Mock -CommandName Get-MgBetaServicePrincipal -MockWith { } -Verifiable

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
        It "should identify expiring secrets" {
            # Use UTC dates to match function's UTC comparisons
            $expiryDate = (Get-Date).ToUniversalTime().AddDays(10)
            $mockApps = @(
                [PSCustomObject]@{
                    Id                  = "1"
                    AppId               = "App1"
                    DisplayName         = "TestApp"
                    PasswordCredentials = @(
                        [PSCustomObject]@{
                            KeyId       = "Key1"
                            EndDateTime = $expiryDate
                        }
                    )
                    KeyCredentials      = @()
                }
            )
            Mock -CommandName "Get-MgBetaApplication" -MockWith { return $mockApps }
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return @() }

            $results = Get-GTExpiringSecrets -DaysUntilExpiry 30
            $results.Count | Should -Be 1
            $results[0].CredentialType | Should -Be "Secret"
            $results[0].DaysRemaining | Should -BeLessThan 11
        }

        It "should respect scope parameter" {
            Mock -CommandName "Get-MgBetaApplication" -MockWith { return @() }
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return @() }

            Get-GTExpiringSecrets -DaysUntilExpiry 30 -Scope Applications
            Assert-MockCalled -CommandName "Get-MgBetaApplication" -Times 1
            Assert-MockCalled -CommandName "Get-MgBetaServicePrincipal" -Times 0
        }

        It "should find expiring certificates on service principals" {
            $expiryDate = (Get-Date).ToUniversalTime().AddDays(5)
            $mockSps = @(
                [PSCustomObject]@{
                    Id                  = 'sp-1'
                    AppId               = 'SPApp1'
                    DisplayName         = 'TestSP'
                    PasswordCredentials = @()
                    KeyCredentials      = @(
                        [PSCustomObject]@{
                            KeyId       = 'Cert1'
                            EndDateTime = $expiryDate
                        }
                    )
                }
            )

            Mock -CommandName "Get-MgBetaApplication" -MockWith { return @() }
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return $mockSps }

            $results = Get-GTExpiringSecrets -DaysUntilExpiry 10 -Scope ServicePrincipals
            $results.Count | Should -Be 1
            $results[0].ResourceType | Should -Be 'ServicePrincipal'
            $results[0].CredentialType | Should -Be 'Certificate'
        }
    }
}

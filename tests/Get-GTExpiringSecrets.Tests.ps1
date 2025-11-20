Describe "Get-GTExpiringSecrets" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Get-GTExpiringSecrets.ps1"
        # Provide minimal stubs so dot-sourcing the function file doesn't fail
        function Install-GTRequiredModule { }
        # Match real signature: Reconnect and Quiet are switches so calling -Reconnect -Quiet binds correctly
        function Test-GTGraphScopes { param($RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function Get-MgBetaApplication { }
        function Get-MgBetaServicePrincipal { }

        if (Test-Path $functionPath)
        {
            # Dot-source the function under test
            . $functionPath
        }
        else
        {
            Write-Error "Function file not found at $functionPath"
        }

        # Replace implementations with Pester mocks where appropriate
        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Test-GTGraphScopes" -MockWith { return $true }
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

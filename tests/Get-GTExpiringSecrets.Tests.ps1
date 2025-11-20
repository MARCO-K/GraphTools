Describe "Get-GTExpiringSecrets" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Get-GTExpiringSecrets.ps1"
        if (Test-Path $functionPath) {
            . $functionPath
        }
        else {
            Write-Error "Function file not found at $functionPath"
        }

        function Install-GTRequiredModule {}
        function Initialize-GTGraphConnection {}
        function Get-MgBetaApplication {}
        function Get-MgBetaServicePrincipal {}
        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $true }
    }

    Context "Functionality" {
        It "should identify expiring secrets" {
            $expiryDate = (Get-Date).AddDays(10)
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
    }
}

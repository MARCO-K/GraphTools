Describe "Get-GTUnusedApps" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Get-GTUnusedApps.ps1"
        if (Test-Path $functionPath) {
            . $functionPath
        }
        else {
            Write-Error "Function file not found at $functionPath"
        }

        function Install-GTRequiredModule {}
        function Initialize-GTGraphConnection {}
        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $true }
    }

    Context "Functionality" {
        It "should identify unused apps correctly" {
            $lastSignIn = (Get-Date).AddDays(-100)
            $mockSPs = @(
                [PSCustomObject]@{
                    Id             = "1"
                    AppId          = "App1"
                    DisplayName    = "UnusedApp"
                    SignInActivity = [PSCustomObject]@{
                        LastSignInDateTime = $lastSignIn
                    }
                }
            )
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return $mockSPs }

            $results = Get-GTUnusedApps -DaysSinceLastSignIn 90
            $results.Count | Should -Be 1
            $results[0].Status | Should -Be "Inactive"
        }

        It "should include never used apps when switch is present" {
            $mockSPs = @(
                [PSCustomObject]@{
                    Id             = "2"
                    AppId          = "App2"
                    DisplayName    = "NeverUsedApp"
                    SignInActivity = $null
                }
            )
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return $mockSPs }

            $results = Get-GTUnusedApps -DaysSinceLastSignIn 90 -IncludeNeverUsed
            $results.Count | Should -Be 1
            $results[0].Status | Should -Be "Never Used"
        }
    }
}

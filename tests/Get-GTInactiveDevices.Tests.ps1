Describe "Get-GTInactiveDevices" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Get-GTInactiveDevices.ps1"
        if (Test-Path $functionPath) {
            . $functionPath
        }
        else {
            Write-Error "Function file not found at $functionPath"
        }

        function Install-GTRequiredModule {}
        function Initialize-GTGraphConnection {}
        function Get-MgBetaDevice {}
        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $true }
    }

    Context "Functionality" {
        It "should identify inactive devices" {
            $lastSignIn = (Get-Date).AddDays(-100)
            $mockDevices = @(
                [PSCustomObject]@{
                    Id                            = "1"
                    DisplayName                   = "InactiveDevice"
                    OperatingSystem               = "Windows"
                    ApproximateLastSignInDateTime = $lastSignIn
                    AccountEnabled                = $true
                }
            )
            Mock -CommandName "Get-MgBetaDevice" -MockWith { return $mockDevices }

            $results = Get-GTInactiveDevices -InactiveDays 90
            $results.Count | Should -Be 1
            $results[0].DaysInactive | Should -BeGreaterOrEqual 100
        }

        It "should filter out disabled devices by default" {
            $lastSignIn = (Get-Date).AddDays(-100)
            $mockDevices = @(
                [PSCustomObject]@{
                    Id                            = "2"
                    DisplayName                   = "DisabledDevice"
                    OperatingSystem               = "Windows"
                    ApproximateLastSignInDateTime = $lastSignIn
                    AccountEnabled                = $false
                }
            )
            Mock -CommandName "Get-MgBetaDevice" -MockWith { return $mockDevices }

            $results = Get-GTInactiveDevices -InactiveDays 90
            $results.Count | Should -Be 0
        }

        It "should include disabled devices when switch is present" {
            $lastSignIn = (Get-Date).AddDays(-100)
            $mockDevices = @(
                [PSCustomObject]@{
                    Id                            = "2"
                    DisplayName                   = "DisabledDevice"
                    OperatingSystem               = "Windows"
                    ApproximateLastSignInDateTime = $lastSignIn
                    AccountEnabled                = $false
                }
            )
            Mock -CommandName "Get-MgBetaDevice" -MockWith { return $mockDevices }

            $results = Get-GTInactiveDevices -InactiveDays 90 -IncludeDisabled
            $results.Count | Should -Be 1
        }
    }
}

Describe "Get-GTInactiveDevices" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Get-GTInactiveDevices.ps1"

        # Provide minimal stubs before dot-sourcing so the function file can load
        function Install-GTRequiredModule { }
        function Initialize-GTGraphConnection { }
        function Test-GTGraphScopes { param($RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function Write-PSFMessage { param($Level, $Message) }
        # Stub the Graph cmdlet so dot-sourcing and runtime calls don't throw; Pester will Mock it in each It block
        function Get-MgBetaDevice { }

        if (Test-Path $functionPath)
        {
            . $functionPath
        }
        else
        {
            Write-Error "Function file not found at $functionPath"
        }

        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $true }
        Mock -CommandName "Test-GTGraphScopes" -MockWith { return $true }
        Mock -CommandName "Write-PSFMessage" -MockWith { }
    }

    Context "Functionality" {
        It "should identify inactive devices" {
            $lastSignIn = (Get-Date).ToUniversalTime().AddDays(-100)
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

        It "should request server-side filter that excludes disabled devices by default" {
            # Capture the Filter parameter passed into Get-MgBetaDevice so we can assert it contains accountEnabled eq true
            $script:CapturedFilter = $null
            Mock -CommandName "Get-MgBetaDevice" -MockWith {
                param($All, $Filter, $Property, $ErrorAction)
                # Capture the Filter parameter (works even when splatted)
                $script:CapturedFilter = $Filter
                return @()
            }

            Get-GTInactiveDevices -InactiveDays 90

            $script:CapturedFilter | Should -Match "accountEnabled eq true"
            Assert-MockCalled -CommandName "Get-MgBetaDevice" -Times 1
        }

        It "should request server-side filter without accountEnabled when -IncludeDisabled is provided" {
            $lastSignIn = (Get-Date).ToUniversalTime().AddDays(-100)
            $mockDevices = @(
                [PSCustomObject]@{
                    Id                            = "2"
                    DisplayName                   = "DisabledDevice"
                    OperatingSystem               = "Windows"
                    ApproximateLastSignInDateTime = $lastSignIn
                    AccountEnabled                = $false
                }
            )

            Mock -CommandName "Get-MgBetaDevice" -MockWith { return $mockDevices } -ParameterFilter {
                # When IncludeDisabled is present, the function should NOT include 'accountEnabled eq true' in the filter
                -not ($Filter -match "accountEnabled eq true")
            }

            $results = Get-GTInactiveDevices -InactiveDays 90 -IncludeDisabled
            $results.Count | Should -Be 1
        }
    }
}

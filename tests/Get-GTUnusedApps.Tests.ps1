Describe "Get-GTUnusedApps" {
    BeforeAll {
        function global:Install-GTRequiredModule {}
        function global:Initialize-GTGraphConnection { return $true }
        function global:Test-GTGraphScopes { return $true }
        function global:Write-PSFMessage {}
        function global:Get-GTGraphErrorDetails { param($Exception) return @{ LogLevel = 'Error'; Reason = 'Error' } }
        function global:Invoke-GTGraphPagedRequest { param($Uri, $Headers) return @() }

        . "$PSScriptRoot/../internal/functions/Get-UTCTime.ps1"
        . "$PSScriptRoot/../internal/functions/Format-ODataDateTime.ps1"

        Mock -CommandName Install-GTRequiredModule -MockWith { } -Verifiable
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true } -Verifiable
        Mock -CommandName Test-GTGraphScopes -MockWith { return $true } -Verifiable

        $functionPath = "$PSScriptRoot/../functions/Get-GTUnusedApps.ps1"
        if (Test-Path $functionPath)
        {
            . $functionPath
        }
        else
        {
            Write-Error "Function file not found at $functionPath"
        }
    }

    Context "Functionality" {
        It "should identify unused apps correctly" {
            $lastSignIn = (Get-Date).ToUniversalTime().AddDays(-100).ToString('o')
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
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return $mockSPs }

            $results = Get-GTUnusedApps -DaysSinceLastSignIn 90
            @($results).Count | Should -Be 1
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
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return $mockSPs }

            $results = Get-GTUnusedApps -DaysSinceLastSignIn 90 -IncludeNeverUsed
            @($results).Count | Should -Be 1
            $results[0].Status | Should -Be "Never Used"
        }
    }
}

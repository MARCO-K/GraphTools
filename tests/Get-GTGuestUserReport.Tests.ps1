Describe "Get-GTGuestUserReport" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Get-GTGuestUserReport.ps1"
        Write-Host "Loading function from: $functionPath"
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

    Context "Parameter Validation" {
        It "should accept PendingOnly switch" {
            Mock -CommandName "Get-MgBetaUser" -MockWith { return @() }
            { Get-GTGuestUserReport -PendingOnly } | Should -Not -Throw
        }

        It "should accept DaysSinceCreation parameter" {
            Mock -CommandName "Get-MgBetaUser" -MockWith { return @() }
            { Get-GTGuestUserReport -DaysSinceCreation 30 } | Should -Not -Throw
        }
    }

    Context "Functionality" {
        It "should filter pending users correctly" {
            $mockUsers = @(
                [PSCustomObject]@{
                    Id                = "1"
                    DisplayName       = "User1"
                    ExternalUserState = "PendingAcceptance"
                    CreatedDateTime   = (Get-Date).AddDays(-10)
                },
                [PSCustomObject]@{
                    Id                = "2"
                    DisplayName       = "User2"
                    ExternalUserState = "Accepted"
                    CreatedDateTime   = (Get-Date).AddDays(-20)
                }
            )
            Mock -CommandName "Get-MgBetaUser" -MockWith { return $mockUsers }

            $results = Get-GTGuestUserReport -PendingOnly
            $results.Count | Should -Be 1
            $results[0].Id | Should -Be "1"
        }

        It "should filter by creation date correctly" {
            $mockUsers = @(
                [PSCustomObject]@{
                    Id                = "1"
                    DisplayName       = "User1"
                    ExternalUserState = "PendingAcceptance"
                    CreatedDateTime   = (Get-Date).AddDays(-10)
                },
                [PSCustomObject]@{
                    Id                = "2"
                    DisplayName       = "User2"
                    ExternalUserState = "Accepted"
                    CreatedDateTime   = (Get-Date).AddDays(-40)
                }
            )
            Mock -CommandName "Get-MgBetaUser" -MockWith { return $mockUsers }

            $results = Get-GTGuestUserReport -DaysSinceCreation 30
            $results.Count | Should -Be 1
            $results[0].Id | Should -Be "2"
        }
    }
}

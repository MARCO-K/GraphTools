Describe "Get-GTGuestUserReport" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Get-GTGuestUserReport.ps1"

        # Provide minimal stubs before dot-sourcing so the function file can load without CommandNotFound errors
        function Install-GTRequiredModule { }
        function Initialize-GTGraphConnection { }
        function Test-GTGraphScopes { param($RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function Write-PSFMessage { param($Level, $Message) }

        if (Test-Path $functionPath)
        {
            # Dot-source the function under test
            . $functionPath
        }
        else
        {
            Write-Error "Function file not found at $functionPath"
        }

        # Replace implementations with Pester mocks for test control
        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $true }
        Mock -CommandName "Test-GTGraphScopes" -MockWith { return $true }
        Mock -CommandName "Write-PSFMessage" -MockWith { }
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
        It "should use server-side filter for pending users" {
            Mock -CommandName "Get-MgBetaUser" -MockWith { return @() } -ParameterFilter { 
                $Filter -match "externalUserState eq 'PendingAcceptance'" -and $Filter -match "userType eq 'Guest'"
            }

            Get-GTGuestUserReport -PendingOnly
            
            # Verification is done via the ParameterFilter in the Mock
            Assert-MockCalled "Get-MgBetaUser" -Times 1
        }

        It "should filter by creation date correctly (client-side)" {
            $mockUsers = @(
                [PSCustomObject]@{
                    Id                = "1"
                    DisplayName       = "User1"
                    ExternalUserState = "PendingAcceptance"
                    CreatedDateTime   = (Get-Date).ToUniversalTime().AddDays(-10)
                    SignInActivity    = [PSCustomObject]@{ LastSignInDateTime = $null }
                },
                [PSCustomObject]@{
                    Id                = "2"
                    DisplayName       = "User2"
                    ExternalUserState = "Accepted"
                    CreatedDateTime   = (Get-Date).ToUniversalTime().AddDays(-40)
                    SignInActivity    = [PSCustomObject]@{ LastSignInDateTime = (Get-Date).ToUniversalTime().AddDays(-5) }
                }
            )
            Mock -CommandName "Get-MgBetaUser" -MockWith { return $mockUsers }

            $results = Get-GTGuestUserReport -DaysSinceCreation 30
            $results.Count | Should -Be 1
            $results[0].Id | Should -Be "2"
        }
    }
}

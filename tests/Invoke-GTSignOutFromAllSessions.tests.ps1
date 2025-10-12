. "$PSScriptRoot/../functions/Invoke-GTSignOutFromAllSessions.ps1"

Describe "Invoke-GTSignOutFromAllSessions" {
    BeforeAll {
        # Mock the required modules and functions
        Mock -ModuleName "Microsoft.Graph.Users" -CommandName "Get-MgUser" -MockWith {
            [PSCustomObject]@{
                Id = "mock-user-id"
            }
        }
        Mock -ModuleName "Microsoft.Graph.Users.Actions" -CommandName "Revoke-MgUserSignInSession" -MockWith { }
    }

    Context "Happy Path" {
        It "should call Revoke-MgUserSignInSession with the correct UserId" {
            Invoke-GTSignOutFromAllSessions -UPN "test.user@example.com"
            Assert-MockCalled -CommandName "Revoke-MgUserSignInSession" -Times 1 -ParameterFilter {
                $UserId -eq "mock-user-id"
            }
        }
    }

    Context "Error Handling" {
        It "should not call Revoke-MgUserSignInSession if Get-MgUser returns null" {
            Mock -ModuleName "Microsoft.Graph.Users" -CommandName "Get-MgUser" -MockWith { $null }
            Invoke-GTSignOutFromAllSessions -UPN "non.existent.user@example.com"
            Assert-MockCalled -CommandName "Revoke-MgUserSignInSession" -Times 0
        }

        It "should throw an error for an invalid UPN" {
            { Invoke-GTSignOutFromAllSessions -UPN "invalid-upn" } | Should -Throw
        }
    }
}
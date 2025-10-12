. "$PSScriptRoot/../functions/Get-GTRecentUser.ps1"

Describe "Get-GTRecentUser" {
    BeforeAll {
        # Mock the required modules and functions
        Mock -ModuleName "Microsoft.Graph.Users" -CommandName "Get-MgUser" -MockWith { }
    }

    Context "Parameter Validation" {
        It "should throw an error for an invalid UPN (no @ symbol)" {
            { Get-GTRecentUser -UserPrincipalName "invalid-user" } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty local part)" {
            { Get-GTRecentUser -UserPrincipalName "@domain.com" } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty domain part)" {
            { Get-GTRecentUser -UserPrincipalName "user@" } | Should -Throw
        }
    }
}
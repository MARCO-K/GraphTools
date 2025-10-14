. "$PSScriptRoot/../functions/Disable-GTUser.ps1"

Describe "Disable-GTUser" {
    BeforeAll {
        # Mock the required modules and functions
        Mock -ModuleName "Microsoft.Graph.Beta.Users" -CommandName "Update-MgBetaUser" -MockWith { }
    }

    Context "Parameter Validation" {
        It "should throw an error for an invalid UPN (no @ symbol)" {
            { Disable-GTUser -UPN "invalid-user" } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty local part)" {
            { Disable-GTUser -UPN "@domain.com" } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty domain part)" {
            { Disable-GTUser -UPN "user@" } | Should -Throw
        }
    }
}
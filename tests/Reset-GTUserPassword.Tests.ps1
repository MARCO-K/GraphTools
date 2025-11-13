. "$PSScriptRoot/../functions/Reset-GTUserPassword.ps1"

Describe "Reset-GTUserPassword" {
    BeforeAll {
        # Mock the required modules and functions
        Mock -ModuleName "Microsoft.Graph.Beta.Users" -CommandName "Update-MgBetaUser" -MockWith { }
    }

    Context "Parameter Validation" {
        It "should throw an error for an invalid UPN (no @ symbol)" {
            { Reset-GTUserPassword -UPN "invalid-user" } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty local part)" {
            { Reset-GTUserPassword -UPN "@domain.com" } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty domain part)" {
            { Reset-GTUserPassword -UPN "user@" } | Should -Throw
        }
    }
}

. "$PSScriptRoot/../functions/Get-M365LicenceOverview.ps1"

Describe "Get-M365LicenseOverview" {
    BeforeAll {
        # Mock the required modules and functions
        Mock -ModuleName "Microsoft.Graph.Beta.Users" -CommandName "Get-MgBetaUser" -MockWith { }
        Mock -ModuleName "Microsoft.Graph.Beta.Identity.DirectoryManagement" -CommandName "Invoke-RestMethod" -MockWith { }
    }

    Context "Parameter Validation" {
        It "should throw an error for an invalid FilterUser (no @ symbol)" {
            { Get-M365LicenseOverview -FilterUser "invalid-user" } | Should -Throw
        }

        It "should throw an error for an invalid FilterUser (empty local part)" {
            { Get-M365LicenseOverview -FilterUser "@domain.com" } | Should -Throw
        }

        It "should throw an error for an invalid FilterUser (empty domain part)" {
            { Get-M365LicenseOverview -FilterUser "user@" } | Should -Throw
        }
    }
}
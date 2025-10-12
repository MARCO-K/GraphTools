. "$PSScriptRoot/../functions/Get-GTRecentUser.ps1"

Describe "Get-GTRecentUser" {
    BeforeAll {
        # Mock the required modules and functions
        Mock -ModuleName "Microsoft.Graph.Users" -CommandName "Get-MgUser" -MockWith { }
    }

    Context "Parameter Validation" {
        It "should throw an error for an invalid UserPrincipalName" {
            { Get-GTRecentUser -UserPrincipalName "invalid-user" } | Should -Throw
        }
    }
}
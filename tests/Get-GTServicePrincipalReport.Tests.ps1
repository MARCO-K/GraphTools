. "$PSScriptRoot/../functions/Get-GTServicePrincipalReport.ps1"

Describe "Get-GTServicePrincipalReport" {
    BeforeAll {
        # Mock required modules and functions
        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Initialize-GTGraphConnection" -MockWith { }
    }

    Context "Parameter Sets" {
        It "should accept AppId parameter" {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return @() }
            { "test-app-id" | Get-GTServicePrincipalReport } | Should -Not -Throw
        }

        It "should accept DisplayName parameter" {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return @() }
            { "TestApp" | Get-GTServicePrincipalReport -DisplayName } | Should -Not -Throw
        }
    }

    Context "Switch Parameters" {
        It "should accept IncludeSignInActivity switch" {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return @() }
            { Get-GTServicePrincipalReport -IncludeSignInActivity } | Should -Not -Throw
        }

        It "should accept IncludeCredentials switch" {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return @() }
            { Get-GTServicePrincipalReport -IncludeCredentials } | Should -Not -Throw
        }

        It "should accept ExpandOwners switch" {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return @() }
            { Get-GTServicePrincipalReport -ExpandOwners } | Should -Not -Throw
        }
    }
}

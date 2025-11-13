. "$PSScriptRoot/../functions/Get-GTInactiveUsers.ps1"

Describe "Get-GTInactiveUsers" {
    BeforeAll {
        # Mock required modules
        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Initialize-GTGraphConnection" -MockWith { }
    }

    Context "Parameter Validation" {
        It "should accept InactiveDaysOlderThan parameter" {
            Mock -CommandName "Get-MgBetaUser" -MockWith { return @() }
            { Get-GTInactiveUsers -InactiveDaysOlderThan 90 } | Should -Not -Throw
        }

        It "should accept DisabledUsersOnly switch" {
            Mock -CommandName "Get-MgBetaUser" -MockWith { return @() }
            { Get-GTInactiveUsers -DisabledUsersOnly } | Should -Not -Throw
        }

        It "should accept ExternalUsersOnly switch" {
            Mock -CommandName "Get-MgBetaUser" -MockWith { return @() }
            { Get-GTInactiveUsers -ExternalUsersOnly } | Should -Not -Throw
        }
    }
}

. "$PSScriptRoot/../functions/Get-GTOrphanedGroup.ps1"

Describe "Get-GTOrphanedGroup" {
    BeforeAll {
        # Mock required modules and functions
        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Initialize-GTGraphConnection" -MockWith { }
    }

    Context "Function Execution" {
        It "should not throw when properly configured" {
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return @() }
            { Get-GTOrphanedGroup } | Should -Not -Throw
        }
    }

    Context "Parameter Handling" {
        It "should accept NewSession switch" {
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return @() }
            { Get-GTOrphanedGroup -NewSession } | Should -Not -Throw
        }

        It "should accept Scope parameter" {
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return @() }
            { Get-GTOrphanedGroup -Scope 'Group.Read.All' } | Should -Not -Throw
        }
    }
}

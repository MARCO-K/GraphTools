. "$PSScriptRoot/../functions/Get-GTPolicyControlGapReport.ps1"

Describe "Get-GTPolicyControlGapReport" {
    BeforeAll {
        # Mock Get-MgContext to simulate being connected
        Mock -CommandName "Get-MgContext" -MockWith {
            return @{ Scopes = @('Policy.Read.All') }
        }
    }

    Context "Graph Connection" {
        It "should require Microsoft Graph connection" {
            Mock -CommandName "Get-MgContext" -MockWith { return $null }
            { Get-GTPolicyControlGapReport } | Should -Throw
        }
    }

    Context "Function Execution" {
        It "should not throw when properly connected" {
            Mock -CommandName "Get-MgBetaIdentityConditionalAccessPolicy" -MockWith { return @() }
            Mock -CommandName "Get-MgBetaUser" -MockWith { return @() }
            { Get-GTPolicyControlGapReport } | Should -Not -Throw
        }
    }
}

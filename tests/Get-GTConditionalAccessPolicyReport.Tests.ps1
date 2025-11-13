. "$PSScriptRoot/../functions/Get-GTConditionalAccessPolicyReport.ps1"

Describe "Get-GTConditionalAccessPolicyReport" {
    BeforeAll {
        # Mock Get-MgContext to simulate being connected
        Mock -CommandName "Get-MgContext" -MockWith {
            return @{ Scopes = @('Policy.Read.All') }
        }
    }

    Context "Graph Connection" {
        It "should require Microsoft Graph connection" {
            Mock -CommandName "Get-MgContext" -MockWith { return $null }
            { Get-GTConditionalAccessPolicyReport } | Should -Throw
        }
    }

    Context "Function Execution" {
        It "should not throw when properly connected" {
            Mock -CommandName "Get-MgBetaIdentityConditionalAccessPolicy" -MockWith {
                return @()
            }
            { Get-GTConditionalAccessPolicyReport } | Should -Not -Throw
        }
    }
}

## Provide lightweight stubs for common helpers in case they are missing during discovery
if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

## (Function will be dot-sourced in BeforeAll to allow Pester mocks to register first)

Describe "Get-GTPolicyControlGapReport" {
    BeforeAll {
        # Mock Get-MgContext to simulate being connected
        Mock -CommandName "Get-MgContext" -MockWith {
            return @{ Scopes = @('Policy.Read.All') }
        }
        $functionPath = "$PSScriptRoot/../functions/Get-GTPolicyControlGapReport.ps1"
        if (Test-Path $functionPath) { . $functionPath } else { Throw "Function file not found: $functionPath" }
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

Describe "Get-GTConditionalAccessPolicyReport" {
    BeforeAll {
        function global:Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function global:Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true }
        function global:Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Invoke-GTGraphPagedRequest { param($Uri, $Headers) return @() }

        $functionPath = "$PSScriptRoot/../functions/Get-GTConditionalAccessPolicyReport.ps1"
        if (Test-Path $functionPath) { . $functionPath } else { Throw "Function file not found: $functionPath" }
    }

    Context "Graph Connection" {
        It "should require Microsoft Graph connection" {
            Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $false }
            { Get-GTConditionalAccessPolicyReport -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Function Execution" {
        It "should not throw when properly connected" {
            Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $true }
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @() }
            { Get-GTConditionalAccessPolicyReport } | Should -Not -Throw
        }
    }
}

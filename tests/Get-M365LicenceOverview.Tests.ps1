Describe "Get-M365LicenseOverview" {
    BeforeAll {
        # Use Pester Mocks before dot-sourcing so the function file can load and calls are intercepted
        # Mock the required modules and functions
        Mock -ModuleName "Microsoft.Graph.Beta.Users" -CommandName "Get-MgBetaUser" -MockWith { }
        Mock -ModuleName "Microsoft.Graph.Beta.Identity.DirectoryManagement" -CommandName "Invoke-RestMethod" -MockWith { }

        ## Provide lightweight stubs for common helpers in case they are missing during discovery
        if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
        if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
        if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
        if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

        # Dot-source the function under test
        . "$PSScriptRoot/../functions/Get-M365LicenceOverview.ps1"
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
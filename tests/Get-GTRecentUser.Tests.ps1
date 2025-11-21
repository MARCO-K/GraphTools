## Provide lightweight stubs for common helpers in case they are missing during discovery
if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

## (Function will be dot-sourced in BeforeAll to allow Pester mocks to register first)

Describe "Get-GTRecentUser" {
    BeforeAll {
        # Define the validation regex used by the function
        $script:GTValidationRegex = @{
            UPN = '^[^@\s]+@[^@\s]+\.[^@\s]+$'
        }

        # Define stubs for dependencies to ensure Mock works
        function Install-GTRequiredModule {}
        function Initialize-GTGraphConnection { return $true }
        function Test-GTGraphScopes { return $true }
        function Write-PSFMessage {}
        function Get-GTGraphErrorDetails {}
        function Get-MgUser {}

        # Use Pester Mocks for dependencies
        Mock -CommandName Install-GTRequiredModule -MockWith {} -Verifiable
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true } -Verifiable
        Mock -CommandName Test-GTGraphScopes -MockWith { return $true } -Verifiable
        Mock -CommandName Write-PSFMessage -MockWith {} -Verifiable
        Mock -CommandName Get-GTGraphErrorDetails -MockWith {} -Verifiable
        Mock -CommandName Get-MgUser -MockWith {} -Verifiable
        Mock -CommandName Get-Module -MockWith { return [PSCustomObject]@{ Name = 'Microsoft.Graph.Users' } } -ParameterFilter { $Name -eq 'Microsoft.Graph.Users' -and $ListAvailable }

        $functionPath = "$PSScriptRoot/../functions/Get-GTRecentUser.ps1"
        if (Test-Path $functionPath) { . $functionPath } else { Throw "Function file not found: $functionPath" }
    }

    Context "Parameter Validation" {
        It "should throw an error for an invalid UPN (no @ symbol)" {
            { Get-GTRecentUser -UserPrincipalName "invalid-user" } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty local part)" {
            { Get-GTRecentUser -UserPrincipalName "@domain.com" } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty domain part)" {
            { Get-GTRecentUser -UserPrincipalName "user@" } | Should -Throw
        }
    }
}
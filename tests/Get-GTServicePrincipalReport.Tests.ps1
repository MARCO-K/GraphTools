Describe "Get-GTServicePrincipalReport" {
    BeforeAll {
        # Use Pester Mocks before dot-sourcing so the function file can load and calls are intercepted
        # Mock required modules and functions
        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Initialize-GTGraphConnection" -MockWith { }

        ## Provide lightweight stubs for common helpers in case they are missing during discovery
        if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
        if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
        if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
        if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

        # Dot-source the function under test
        . "$PSScriptRoot/../functions/Get-GTServicePrincipalReport.ps1"
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

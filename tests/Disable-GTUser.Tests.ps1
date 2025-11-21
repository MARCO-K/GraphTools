Describe "Disable-GTUser" {
    
    BeforeAll {
        # 1. Load the Function
        $functionPath = Join-Path $PSScriptRoot "..\functions\Disable-GTUser.ps1"
        if (-not (Test-Path $functionPath)) { Throw "CRITICAL: Could not find $functionPath" }
        . $functionPath

        # 2. Mock Dependencies
        $script:GTValidationRegex = @{ UPN = '^[^@\s]+@[^@\s]+\.[^@\s]+$' }

        # Mock Helpers - Ensure they return NOTHING (void) unless specified
        function Install-GTRequiredModule { }
        function Initialize-GTGraphConnection { return $true }
        function Test-GTGraphScopes { return $true }
        
        # Provide lightweight stubs for common helpers in case they are missing during discovery
        if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
        if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
        if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
        if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

        # Mock Logging to prevent pollution of the output stream
        function Write-PSFMessage { param([string]$Level, [string]$Message) }

        # Mock Error Helper
        function Get-GTGraphErrorDetails
        { 
            param($Exception) 
            return [PSCustomObject]@{ 
                HttpStatus   = 404; 
                Reason       = "User not found (404)."; 
                LogLevel     = "Error";
                ErrorMessage = "Resource not found"
            } 
        }
    }

    Context "Input Handling" {
        It "returns an empty array when piped an empty array" {
            # Act
            # Force the result into an array context
            [array]$results = @( @() | Disable-GTUser )
            
            # Assert
            # 1. Check Count. This is the most critical check.
            $results.Count | Should -Be 0
            
            # 2. Check Type using the Unary Comma (,)
            #    The comma prevents the empty array from 'unrolling' into nothingness.
            #    It passes the array object itself to Should.
            , $results | Should -BeOfType 'System.Array'
        }

        It "accepts a valid UPN via parameter" {
            Mock -CommandName Update-MgBetaUser -MockWith { }
            
            $results = Disable-GTUser -UPN "test@contoso.com" -Force
            
            $results.Count | Should -Be 1
            $results[0].Status | Should -Be "Disabled"
        }
    }

    Context "Execution Logic" {
        It "calls Update-MgBetaUser with correct arguments" {
            Mock -CommandName Update-MgBetaUser -MockWith { } -Verifiable -ParameterFilter { 
                $UserId -eq 'user@contoso.com' -and $AccountEnabled -eq $false 
            }

            $null = Disable-GTUser -UPN 'user@contoso.com' -Force

            Should -Invoke -CommandName Update-MgBetaUser -Times 1
        }

        It "outputs a 'Disabled' status object on success" {
            Mock -CommandName Update-MgBetaUser -MockWith { }

            $results = Disable-GTUser -UPN 'user@contoso.com' -Force

            # FIXED: Property name is 'User', not 'UserPrincipalName'
            $results.User | Should -Be 'user@contoso.com'
            # FIXED: Status is 'Disabled' in your code (not 'Success')
            $results.Status | Should -Be 'Disabled'
        }
    }

    Context "Error Handling" {
        It "handles Graph API errors gracefully (e.g. 404)" {
            Mock -CommandName Update-MgBetaUser -MockWith { 
                throw [System.Exception]::new("Resource not found") 
            }

            $results = Disable-GTUser -UPN 'missing@contoso.com' -Force

            $results.Status | Should -Be 'Failed'
            # FIXED: Property name is 'Reason', not 'Message'
            $results.Reason | Should -Be "User not found (404)."
        }
    }

    Context "Safety Checks" {
        It "skips execution if WhatIf is used" {
            Mock -CommandName Update-MgBetaUser -MockWith { } 

            $results = Disable-GTUser -UPN 'user@contoso.com' -WhatIf

            Should -Invoke -CommandName Update-MgBetaUser -Times 0
            $results.Status | Should -Be 'Skipped'
        }
    }
}
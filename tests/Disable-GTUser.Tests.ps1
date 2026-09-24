Describe "Disable-GTUser" {
    
    BeforeAll {
        # 1. Load Dependencies
        $validationFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'GTValidation.ps1'
        if (Test-Path $validationFile) { . $validationFile }

        # Provide lightweight stubs for common helpers in case they are missing during discovery
        if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
        if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
        if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
        if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }
        if (-not (Get-Command Get-UTCTime -ErrorAction SilentlyContinue)) { function Get-UTCTime { return [DateTime]::UtcNow } }
        if (-not (Get-Command Invoke-GTGraphRequest -ErrorAction SilentlyContinue)) { function Invoke-GTGraphRequest { param($Method, $Uri, $Body, $ContentType, $ErrorAction, [switch]$All) return $null } }
        $batchFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'Invoke-GTGraphBatch.ps1'
        if (Test-Path $batchFile) { . $batchFile }
        if (-not (Get-Command Invoke-GTGraphBatch -ErrorAction SilentlyContinue)) { function Invoke-GTGraphBatch { param($Requests) return @() } }

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

        # 2. Load the Function
        $functionPath = Join-Path $PSScriptRoot "..\functions\Disable-GTUser.ps1"
        if (-not (Test-Path $functionPath)) { Throw "CRITICAL: Could not find $functionPath" }
        . $functionPath
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
            Mock -CommandName Invoke-GTGraphRequest -MockWith { }
            
            $results = Disable-GTUser -UPN "test@contoso.com" -Force
            
            $results.Count | Should -Be 1
            $results[0].Status | Should -Be "Disabled"
        }
    }

    Context "Execution Logic" {
        It "calls Invoke-GTGraphRequest with correct arguments" {
            Mock -CommandName Invoke-GTGraphRequest -MockWith { } -Verifiable -ParameterFilter {
                $Method -eq 'PATCH' -and
                $Uri -eq 'v1.0/users/user@contoso.com' -and
                $Body.accountEnabled -eq $false -and
                $ContentType -eq 'application/json'
            }

            $null = Disable-GTUser -UPN 'user@contoso.com' -Force

            Should -Invoke -CommandName Invoke-GTGraphRequest -Times 1
        }

        It "outputs a 'Disabled' status object on success" {
            Mock -CommandName Invoke-GTGraphRequest -MockWith { }

            $results = Disable-GTUser -UPN 'user@contoso.com' -Force

            # Property name is 'User', not 'UserPrincipalName'
            $results.User | Should -Be 'user@contoso.com'
            # Status is 'Disabled' in your code (not 'Success')
            $results.Status | Should -Be 'Disabled'
        }
    }

    Context "Error Handling" {
        It "handles Graph API errors gracefully (e.g. 404)" {
            Mock -CommandName Invoke-GTGraphRequest -MockWith { 
                throw [System.Exception]::new("Resource not found") 
            }

            $results = Disable-GTUser -UPN 'missing@contoso.com' -Force

            $results.Status | Should -Be 'Failed'
            # Property name is 'Reason', not 'Message'
            $results.Reason | Should -Be "User not found (404)."
        }
    }

    Context "Safety Checks" {
        It "skips execution if WhatIf is used" {
            Mock -CommandName Invoke-GTGraphRequest -MockWith { } 

            $results = Disable-GTUser -UPN 'user@contoso.com' -WhatIf

            Should -Invoke -CommandName Invoke-GTGraphRequest -Times 0
            $results.Status | Should -Be 'Skipped'
        }
    }

    Context "Batch Execution" {
        It "executes bulk users via Invoke-GTGraphBatch" {
            Mock -CommandName Invoke-GTGraphBatch -MockWith {
                param($Requests)
                return @(
                    [PSCustomObject]@{ Id = 'user1@contoso.com'; Status = 204; Headers = @{}; Body = $null }
                    [PSCustomObject]@{ Id = 'user2@contoso.com'; Status = 204; Headers = @{}; Body = $null }
                )
            }

            $users = @('user1@contoso.com', 'user2@contoso.com')
            $results = Disable-GTUser -UPN $users -Force

            $results.Count | Should -Be 2
            $results[0].Status | Should -Be 'Disabled'
            $results[1].Status | Should -Be 'Disabled'
            Should -Invoke -CommandName Invoke-GTGraphBatch -Times 1
        }
    }
}
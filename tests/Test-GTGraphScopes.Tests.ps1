Describe "Test-GTGraphScopes" {
    BeforeAll {
        # Load the function for testing
        . "$PSScriptRoot/../internal/functions/Test-GTGraphScopes.ps1"
    }

    Context "Function Definition" {
        It "should define the Test-GTGraphScopes function" {
            $function = Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue
            $function | Should -Not -BeNullOrEmpty
        }

        It "should have mandatory RequiredScopes parameter" {
            $function = Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue
            $function.Parameters.ContainsKey('RequiredScopes') | Should -Be $true
        }

        It "should have Reconnect switch parameter" {
            $function = Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue
            $function.Parameters.ContainsKey('Reconnect') | Should -Be $true
        }

        It "should have Quiet switch parameter" {
            $function = Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue
            $function.Parameters.ContainsKey('Quiet') | Should -Be $true
        }
    }

    Context "Syntax Validation" {
        It "should have valid PowerShell syntax" {
            $filePath = "$PSScriptRoot/../internal/functions/Test-GTGraphScopes.ps1"
            { $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $filePath -Raw), [ref]$null) } | Should -Not -Throw
        }
    }
}

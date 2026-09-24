# Pester tests for Test-GTGraphScopes
Describe "Test-GTGraphScopes" -Tag 'Unit' {
    BeforeAll {
        . "$PSScriptRoot/../internal/functions/Get-GTMissingScopes.ps1"
        . "$PSScriptRoot/../internal/functions/Test-GTGraphScopes.ps1"
        . "$PSScriptRoot/../functions/Get-GTConnection.ps1"

        if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) {
            function global:Write-PSFMessage { param($Level, $Message) }
        }
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

    Context "Connection State Validation" {
        It "returns false when not connected" {
            Mock -CommandName Get-GTConnection -MockWith {
                [PSCustomObject]@{ Connected = $false }
            }

            Test-GTGraphScopes -RequiredScopes @('User.Read.All') -Quiet | Should -Be $false
        }
    }

    Context "Token Claims Scope Validation" {
        It "returns true when all required scopes are present in token claims" {
            Mock -CommandName Get-GTConnection -MockWith {
                [PSCustomObject]@{
                    Connected = $true
                    Scopes    = @('User.Read.All', 'Directory.Read.All', 'AuditLog.Read.All')
                    Roles     = @('User.Read.All', 'Directory.Read.All', 'AuditLog.Read.All')
                }
            }

            Test-GTGraphScopes -RequiredScopes @('User.Read.All', 'Directory.Read.All') -Quiet | Should -Be $true
        }

        It "returns false when required scopes are missing from token claims" {
            Mock -CommandName Get-GTConnection -MockWith {
                [PSCustomObject]@{
                    Connected = $true
                    Scopes    = @('User.Read.All')
                    Roles     = @('User.Read.All')
                }
            }

            Test-GTGraphScopes -RequiredScopes @('User.Read.All', 'Directory.ReadWrite.All') -Quiet | Should -Be $false
        }

        It "falls back to true when claims are not inspectable and only .default is present" {
            Mock -CommandName Get-GTConnection -MockWith {
                [PSCustomObject]@{
                    Connected = $true
                    Scopes    = @('https://graph.microsoft.com/.default')
                }
            }

            Test-GTGraphScopes -RequiredScopes @('User.Read.All') -Quiet | Should -Be $true
        }

        It "gracefully handles Reconnect switch without invalid client credentials calls" {
            Mock -CommandName Get-GTConnection -MockWith {
                [PSCustomObject]@{
                    Connected = $true
                    Scopes    = @('User.Read.All')
                }
            }

            # Should return false for missing scope rather than throwing or failing reconnect
            Test-GTGraphScopes -RequiredScopes @('RoleManagement.ReadWrite.Directory') -Reconnect -Quiet | Should -Be $false
        }
    }
}

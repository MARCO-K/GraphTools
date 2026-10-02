Describe "Get-GTMissingScope" {
    BeforeAll {
        # Load the function for testing
        . "$PSScriptRoot/../internal/functions/Get-GTMissingScope.ps1"
    }

    AfterAll {
        Remove-Item Function:\Get-GTMissingScope -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Get-GTMissingScopes -Force -ErrorAction SilentlyContinue
    }

    Context "Alias Support" {
        It "resolves legacy Get-GTMissingScopes alias to Get-GTMissingScope" {
            (Get-Command Get-GTMissingScopes).ResolvedCommandName | Should -Be 'Get-GTMissingScope'
        }
    }

    Context "Function Definition" {
        It "should define the Get-GTMissingScope function" {
            $function = Get-Command Get-GTMissingScope -ErrorAction SilentlyContinue
            $function | Should -Not -BeNullOrEmpty
        }

        It "should have mandatory RequiredScopes parameter" {
            $function = Get-Command Get-GTMissingScope -ErrorAction SilentlyContinue
            $function.Parameters.ContainsKey('RequiredScopes') | Should -Be $true
        }

        It "should have mandatory CurrentScopes parameter" {
            $function = Get-Command Get-GTMissingScope -ErrorAction SilentlyContinue
            $function.Parameters.ContainsKey('CurrentScopes') | Should -Be $true
        }
    }

    Context "Scope Comparison Logic" {
        It "should return missing scopes when some are absent" {
            $required = @('User.Read.All', 'Group.Read.All', 'Directory.Read.All')
            $current = @('User.Read.All')
            
            $result = Get-GTMissingScope -RequiredScopes $required -CurrentScopes $current
            
            $result | Should -HaveCount 2
            $result | Should -Contain 'group.read.all'
            $result | Should -Contain 'directory.read.all'
        }

        It "should return empty array when all scopes are present" {
            $required = @('User.Read.All', 'Group.Read.All')
            $current = @('User.Read.All', 'Group.Read.All', 'Directory.Read.All')
            
            $result = Get-GTMissingScope -RequiredScopes $required -CurrentScopes $current
            
            $result | Should -BeNullOrEmpty
        }

        It "should handle case-insensitive comparison" {
            $required = @('User.Read.All', 'GROUP.READ.ALL')
            $current = @('user.read.all', 'group.read.all')
            
            $result = Get-GTMissingScope -RequiredScopes $required -CurrentScopes $current
            
            $result | Should -BeNullOrEmpty
        }

        It "should handle empty current scopes array" {
            $required = @('User.Read.All', 'Group.Read.All')
            $current = @()
            
            $result = Get-GTMissingScope -RequiredScopes $required -CurrentScopes $current
            
            $result | Should -HaveCount 2
            $result | Should -Contain 'user.read.all'
            $result | Should -Contain 'group.read.all'
        }

        It "should normalize all output to lowercase" {
            $required = @('User.Read.ALL', 'GROUP.read.All')
            $current = @('user.read.all')
            
            $result = Get-GTMissingScope -RequiredScopes $required -CurrentScopes $current
            
            $result | Should -Be 'group.read.all'
        }
    }

    Context "Syntax Validation" {
        It "should have valid PowerShell syntax" {
            $filePath = "$PSScriptRoot/../internal/functions/Get-GTMissingScope.ps1"
            { $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $filePath -Raw), [ref]$null) } | Should -Not -Throw
        }
    }
}

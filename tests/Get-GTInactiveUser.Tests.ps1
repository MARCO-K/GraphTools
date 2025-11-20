# Tests for Get-GTInactiveUser

Describe "Get-GTInactiveUser" {
    BeforeAll {
        # Minimal stubs to prevent CommandNotFound during dot-sourcing
        function Install-GTRequiredModule { param([string[]]$ModuleNames, [switch]$Verbose) }
        function Test-GTGraphScopes { param([switch]$Reconnect, [switch]$Quiet) return $true }
        function Initialize-GTGraphConnection { param($Scopes, [switch]$NewSession) return $true }
        function Get-GTGraphErrorDetails { param($Exception, $ResourceType) return @{ LogLevel = 'Error'; Reason = 'Stub' } }

        # Helpers to capture the last Get-MgBetaUser call and to swap returned users per-test
        $script:LastGetMgBetaUserParams = $null
        $script:CurrentUsers = @()
        function Get-MgBetaUser { param($All, $Property, $Filter, $ErrorAction) $script:LastGetMgBetaUserParams = $PSBoundParameters; return , $script:CurrentUsers }

        # Dot-source the function under test
        . "$PSScriptRoot/../functions/Get-GTInactiveUser.ps1"
    }

    Context "Happy path - user with lastSignInDateTime" {
        BeforeEach {
            $last = (Get-Date).ToUniversalTime().AddDays(-10).ToString('o')
            $user = [PSCustomObject]@{
                DisplayName       = 'Test User'
                Id                = 'id1'
                AccountEnabled    = $true
                UserPrincipalName = 'test@contoso.com'
                CreatedDateTime   = (Get-Date).ToString('o')
                UserType          = 'Member'
                SignInActivity    = [PSCustomObject]@{ LastSignInDateTime = $last; LastSuccessfulSignInDateTime = $null; LastNonInteractiveSignInDateTime = $null }
            }
            $script:CurrentUsers = , $user
        }

        It "returns DaysInactive as integer" {
            $result = Get-GTInactiveUser
            $result | Should -Not -BeNullOrEmpty
            $result[0].DaysInactive | Should -Be 10
        }
    }

    Context "Never logged in - DaysInactive is null and -NeverLoggedIn filters" {
        BeforeEach {
            $user = [PSCustomObject]@{
                DisplayName       = 'New User'
                Id                = 'id2'
                AccountEnabled    = $true
                UserPrincipalName = 'new@contoso.com'
                CreatedDateTime   = (Get-Date).ToString('o')
                UserType          = 'Member'
                SignInActivity    = $null
            }
            $script:CurrentUsers = , $user
        }

        It "returns DaysInactive as $null for users with no sign-ins" {
            $result = Get-GTInactiveUser
            $result[0].DaysInactive | Should -BeNull
        }

        It "is included when -NeverLoggedIn is passed" {
            $result = Get-GTInactiveUser -NeverLoggedIn
            $result | Should -Not -BeNullOrEmpty
            $result[0].UserPrincipalName | Should -Be 'new@contoso.com'
        }
    }

    Context "When -InactiveDaysOlderThan set, function passes Filter to Get-MgBetaUser" {
        BeforeEach {
            $last = (Get-Date).ToUniversalTime().AddDays(-30).ToString('o')
            $user = [PSCustomObject]@{
                DisplayName       = 'Old User'
                Id                = 'id3'
                AccountEnabled    = $true
                UserPrincipalName = 'old@contoso.com'
                CreatedDateTime   = (Get-Date).ToString('o')
                UserType          = 'Member'
                SignInActivity    = [PSCustomObject]@{ LastSignInDateTime = $last }
            }
            $script:CurrentUsers = , $user
            $script:LastGetMgBetaUserParams = $null
        }

        It "sends an OData Filter containing signInActivity/lastSignInDateTime" {
            $null = Get-GTInactiveUser -InactiveDaysOlderThan 15
            $script:LastGetMgBetaUserParams | Should -Not -BeNullOrEmpty
            $script:LastGetMgBetaUserParams['Filter'] | Should -Match 'signInActivity/lastSignInDateTime'
        }
    }
}

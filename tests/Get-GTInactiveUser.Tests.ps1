# Tests for Get-GTInactiveUser

Describe "Get-GTInactiveUser" {
    BeforeAll {
        function global:Install-GTRequiredModule { param($ModuleNames, $Verbose) }
        function global:Test-GTGraphScopes { param($RequiredScopes, $Reconnect, $Quiet) return $true }
        function global:Initialize-GTGraphConnection { param($Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true }
        function global:Get-GTGraphErrorDetails { param($Exception, $ResourceType) return @{ LogLevel = 'Error'; Reason = 'Stub' } }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Invoke-GTGraphRequest { param($Method, $Uri, $Body, $ContentType, $ErrorAction, [switch]$All) return $null }

        # Use Pester Mocks before dot-sourcing so the function file can load and calls are intercepted
        Mock -CommandName Install-GTRequiredModule -MockWith { } -Verifiable
        Mock -CommandName Test-GTGraphScopes -MockWith { param($RequiredScopes, $Reconnect, $Quiet) return $true } -Verifiable
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true } -Verifiable
        Mock -CommandName Get-GTGraphErrorDetails -MockWith { param($Exception, $ResourceType) return @{ LogLevel = 'Error'; Reason = 'Stub' } } -Verifiable

        # Helpers to capture the last users request and to swap returned users per-test
        $script:LastUsersRequestUri = $null
        $script:CurrentUsers = @()
        Mock -CommandName Invoke-GTGraphRequest -MockWith {
            param($Method, $Uri, $Body, $ContentType, $ErrorAction, [switch]$All)

            if ($Uri -like '*users*') {
                $script:LastUsersRequestUri = [string]$Uri
                if ($All) {
                    return @($script:CurrentUsers)
                }
                return [PSCustomObject]@{ value = @($script:CurrentUsers) }
            }

            if ($Uri -like '*/directoryRoles/*/members*') {
                return [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{ id = 'id-admin'; userPrincipalName = 'admin@contoso.com' }
                    )
                }
            }

            if ($Uri -like '*/directoryRoles*') {
                return [PSCustomObject]@{
                    value = @([PSCustomObject]@{ id = 'role-global-admin' })
                }
            }

            return [PSCustomObject]@{ value = @() }
        } -Verifiable

        . "$PSScriptRoot/../internal/functions/Initialize-GTBeginBlock.ps1"
        . "$PSScriptRoot/../internal/functions/New-GTODataFilter.ps1"
        . "$PSScriptRoot/../internal/functions/Format-ODataDateTime.ps1"
        . "$PSScriptRoot/../internal/functions/Invoke-GTGraphPagedRequest.ps1"
        . "$PSScriptRoot/../internal/functions/Get-UTCTime.ps1"

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

    Context "When -InactiveDaysOlderThan set, function sends filter in Graph request" {
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
            $script:LastUsersRequestUri = $null
        }

        It "sends an OData Filter containing signInActivity/lastSignInDateTime" {
            $null = Get-GTInactiveUser -InactiveDaysOlderThan 15
            $script:LastUsersRequestUri | Should -Not -BeNullOrEmpty
            $decodedUri = [System.Uri]::UnescapeDataString($script:LastUsersRequestUri)
            $decodedUri | Should -Match 'signInActivity/lastSignInDateTime'
        }
    }

    Context "Safety exclusions" {
        BeforeEach {
            $script:CurrentUsers = @(
                [PSCustomObject]@{
                    DisplayName       = 'Global Admin User'
                    Id                = 'id-admin'
                    AccountEnabled    = $true
                    UserPrincipalName = 'admin@contoso.com'
                    CreatedDateTime   = (Get-Date).ToString('o')
                    UserType          = 'Member'
                    SignInActivity    = [PSCustomObject]@{ LastSignInDateTime = (Get-Date).ToUniversalTime().AddDays(-120).ToString('o') }
                },
                [PSCustomObject]@{
                    DisplayName       = 'Standard User'
                    Id                = 'id-user'
                    AccountEnabled    = $true
                    UserPrincipalName = 'user@contoso.com'
                    CreatedDateTime   = (Get-Date).ToString('o')
                    UserType          = 'Member'
                    SignInActivity    = [PSCustomObject]@{ LastSignInDateTime = (Get-Date).ToUniversalTime().AddDays(-120).ToString('o') }
                }
            )
        }

        It "excludes specific UPN values when -ExcludeUPN is used" {
            $result = Get-GTInactiveUser -ExcludeUPN 'user@contoso.com'
            $result.UserPrincipalName | Should -Not -Contain 'user@contoso.com'
            $result.UserPrincipalName | Should -Contain 'admin@contoso.com'
        }

        It "excludes Global Administrator members when -ExcludeGlobalAdministrators is used" {
            $result = Get-GTInactiveUser -ExcludeGlobalAdministrators
            $result.UserPrincipalName | Should -Not -Contain 'admin@contoso.com'
            $result.UserPrincipalName | Should -Contain 'user@contoso.com'
        }
    }

    Context "Sign-in-only artifacts" {
        BeforeEach {
            $script:CurrentUsers = @(
                [PSCustomObject]@{
                    DisplayName       = 'Real User'
                    Id                = 'id-real'
                    AccountEnabled    = $true
                    UserPrincipalName = 'real@contoso.com'
                    CreatedDateTime   = (Get-Date).ToString('o')
                    UserType          = 'Member'
                    SignInActivity    = [PSCustomObject]@{ LastSignInDateTime = (Get-Date).ToUniversalTime().AddDays(-100).ToString('o') }
                },
                [PSCustomObject]@{
                    DisplayName       = $null
                    Id                = 'id-artifact'
                    AccountEnabled    = $null
                    UserPrincipalName = $null
                    CreatedDateTime   = $null
                    UserType          = $null
                    SignInActivity    = [PSCustomObject]@{ LastSignInDateTime = (Get-Date).ToUniversalTime().AddDays(-100).ToString('o') }
                }
            )
        }

        It "skips sign-in-only artifacts by default" {
            $result = Get-GTInactiveUser
            $result.Id | Should -Contain 'id-real'
            $result.Id | Should -Not -Contain 'id-artifact'
        }

        It "includes sign-in-only artifacts when -IncludeSignInOnlyRecords is used" {
            $result = Get-GTInactiveUser -IncludeSignInOnlyRecords
            $result.Id | Should -Contain 'id-real'
            $result.Id | Should -Contain 'id-artifact'
        }
    }
}

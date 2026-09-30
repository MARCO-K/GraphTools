if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "Set-GTOAuthSession" -Tag 'Unit' {
    BeforeAll {
        $helperPath = Join-Path $PSScriptRoot '..\internal\functions\Set-GTOAuthSession.ps1'
        if (Test-Path $helperPath) { . $helperPath }

        $tokenFile = Join-Path $PSScriptRoot '..\internal\functions\Get-GTCachedGraphToken.ps1'
        if (Test-Path $tokenFile) { . $tokenFile }

        $savePath = Join-Path $PSScriptRoot '..\internal\functions\Save-GTPersistedTokenCache.ps1'
        if (Test-Path $savePath) { . $savePath }
    }

    BeforeEach {
        $script:GTConnectionConfig = $null
        $script:GTTokenCache = @{
            AccessToken  = $null
            RefreshToken = $null
            ExpiresAt    = [DateTime]::MinValue
            TenantId     = $null
            ClientId     = $null
            Scope        = $null
            AuthType     = $null
            Claims       = $null
            Roles        = @()
            Permissions  = @()
        }
    }

    Context "Interactive Session Setup" {
        It "populates connection config and token cache with LocalPort" {
            $authResult = [PSCustomObject]@{
                AccessToken  = 'mock-interactive-access'
                RefreshToken = 'mock-interactive-refresh'
                ExpiresIn    = 3600
            }

            $result = Set-GTOAuthSession -TenantId 'test-tenant' `
                                         -ClientId 'test-client' `
                                         -AuthType 'Interactive' `
                                         -Scope 'https://graph.microsoft.com/.default' `
                                         -AuthResult $authResult `
                                         -LocalPort 8400

            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.AccessToken | Should -Be 'mock-interactive-access'

            $script:GTConnectionConfig.AuthType | Should -Be 'Interactive'
            $script:GTConnectionConfig.TenantId | Should -Be 'test-tenant'
            $script:GTConnectionConfig.ClientId | Should -Be 'test-client'
            $script:GTConnectionConfig.LocalPort | Should -Be 8400
            $script:GTConnectionConfig.RefreshToken | Should -Be 'mock-interactive-refresh'

            $script:GTTokenCache.AccessToken | Should -Be 'mock-interactive-access'
            $script:GTTokenCache.RefreshToken | Should -Be 'mock-interactive-refresh'
            $script:GTTokenCache.AuthType | Should -Be 'Interactive'
        }
    }

    Context "DeviceCode Session Setup" {
        It "populates connection config and token cache without LocalPort" {
            $authResult = [PSCustomObject]@{
                AccessToken  = 'mock-device-access'
                RefreshToken = 'mock-device-refresh'
                ExpiresIn    = 7200
            }

            $result = Set-GTOAuthSession -TenantId 'test-tenant' `
                                         -ClientId 'test-client' `
                                         -AuthType 'DeviceCode' `
                                         -Scope 'https://graph.microsoft.com/.default' `
                                         -AuthResult $authResult

            $result.Success | Should -Be $true
            $script:GTConnectionConfig.AuthType | Should -Be 'DeviceCode'
            $script:GTConnectionConfig.ContainsKey('LocalPort') | Should -Be $false
            $script:GTTokenCache.AuthType | Should -Be 'DeviceCode'
            $script:GTTokenCache.RefreshToken | Should -Be 'mock-device-refresh'
        }
    }

    Context "Persistence Handling" {
        It "persists refresh token to disk when -PersistRefreshToken is specified" {
            $authResult = [PSCustomObject]@{
                AccessToken  = 'mock-access'
                RefreshToken = 'mock-persisted-refresh'
                ExpiresIn    = 3600
            }

            $script:savedPersistedToken = $null
            Mock -CommandName Save-GTPersistedTokenCache -MockWith {
                param($TenantId, $ClientId, $RefreshToken, $Scope, $AuthType)
                $script:savedPersistedToken = $RefreshToken
                $true
            }

            $null = Set-GTOAuthSession -TenantId 'test-tenant' `
                                       -ClientId 'test-client' `
                                       -AuthType 'Interactive' `
                                       -AuthResult $authResult `
                                       -PersistRefreshToken

            $script:savedPersistedToken | Should -Be 'mock-persisted-refresh'
        }

        It "does not persist token when -PersistRefreshToken is omitted" {
            $authResult = [PSCustomObject]@{
                AccessToken  = 'mock-access'
                RefreshToken = 'mock-persisted-refresh'
                ExpiresIn    = 3600
            }

            $script:saveCalled = $false
            Mock -CommandName Save-GTPersistedTokenCache -MockWith {
                $script:saveCalled = $true
                $true
            }

            $null = Set-GTOAuthSession -TenantId 'test-tenant' `
                                       -ClientId 'test-client' `
                                       -AuthType 'Interactive' `
                                       -AuthResult $authResult

            $script:saveCalled | Should -Be $false
        }
    }
}

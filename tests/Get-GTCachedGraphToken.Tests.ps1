if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "Get-GTCachedGraphToken" -Tag 'Unit' {
    BeforeAll {
        $functionFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Get-GTCachedGraphToken.ps1'
        if (-not (Test-Path $functionFile)) { Throw "Function file not found: $functionFile" }
        . $functionFile
    }

    BeforeEach {
        # Reset token cache and session config before each test
        $script:GTTokenCache = @{
            AccessToken = $null
            ExpiresAt   = [DateTime]::MinValue
            TenantId    = $null
            ClientId    = $null
            Scope       = $null
            AuthType    = $null
        }
        $script:GTConnectionConfig = $null
    }

    Context "Direct Token Parameter Set" {
        It "stores and returns direct access token" {
            $token = Get-GTCachedGraphToken -AccessToken 'mock-direct-token-xyz'
            $token | Should -Be 'mock-direct-token-xyz'
            $script:GTTokenCache.AccessToken | Should -Be 'mock-direct-token-xyz'
            $script:GTTokenCache.AuthType | Should -Be 'DirectToken'
            $script:GTTokenCache.ExpiresAt | Should -BeGreaterThan ([DateTime]::UtcNow)
        }
    }

    Context "In-Memory Caching & Expiration Buffer" {
        It "returns cached token without HTTP call when valid" {
            $script:GTTokenCache.AccessToken = 'valid-cached-token'
            $script:GTTokenCache.ExpiresAt   = [DateTime]::UtcNow.AddHours(1)
            $script:GTTokenCache.TenantId    = 'tenant-123'
            $script:GTTokenCache.ClientId    = 'client-123'

            $script:called = $false
            Mock -CommandName Invoke-RestMethod -MockWith { $script:called = $true; @{ access_token = 'new'; expires_in = 3600 } }

            $token = Get-GTCachedGraphToken
            $token | Should -Be 'valid-cached-token'
            $script:called | Should -Be $false
        }

        It "refreshes token when within BufferMinutes" {
            $script:GTTokenCache.AccessToken = 'about-to-expire'
            # Expiring in 2 minutes, but buffer is 5 minutes
            $script:GTTokenCache.ExpiresAt   = [DateTime]::UtcNow.AddMinutes(2)
            $script:GTTokenCache.TenantId    = 'tenant-123'
            $script:GTTokenCache.ClientId    = 'client-123'
            $script:GTConnectionConfig = @{
                TenantId     = 'tenant-123'
                ClientId     = 'client-123'
                ClientSecret = 'secret-abc'
                Scope        = 'https://graph.microsoft.com/.default'
            }

            Mock -CommandName Invoke-RestMethod -MockWith {
                @{
                    access_token = 'fresh-refreshed-token'
                    expires_in   = 3600
                }
            }

            $token = Get-GTCachedGraphToken -BufferMinutes 5
            $token | Should -Be 'fresh-refreshed-token'
            $script:GTTokenCache.AccessToken | Should -Be 'fresh-refreshed-token'
        }

        It "forces token refresh when -ForceRefresh is specified" {
            $script:GTTokenCache.AccessToken = 'cached-token'
            $script:GTTokenCache.ExpiresAt   = [DateTime]::UtcNow.AddHours(1)
            $script:GTConnectionConfig = @{
                TenantId     = 'tenant-123'
                ClientId     = 'client-123'
                ClientSecret = 'secret-abc'
            }

            Mock -CommandName Invoke-RestMethod -MockWith {
                @{
                    access_token = 'forced-refreshed-token'
                    expires_in   = 3600
                }
            }

            $token = Get-GTCachedGraphToken -ForceRefresh
            $token | Should -Be 'forced-refreshed-token'
        }
    }

    Context "Client Secret Flow" {
        It "sends proper client credentials request and updates cache" {
            $script:capturedBody = $null
            $script:capturedUri = $null

            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:capturedBody = $Body
                $script:capturedUri = $Uri
                @{
                    access_token = 'secret-token-success'
                    expires_in   = 3599
                }
            }

            $token = Get-GTCachedGraphToken -TenantId 'test-tenant' -ClientId 'test-client' -ClientSecret 'my-secret'

            $token | Should -Be 'secret-token-success'
            $script:capturedUri | Should -Be 'https://login.microsoftonline.com/test-tenant/oauth2/v2.0/token'
            $script:capturedBody.grant_type | Should -Be 'client_credentials'
            $script:capturedBody.client_id | Should -Be 'test-client'
            $script:capturedBody.client_secret | Should -Be 'my-secret'
            $script:capturedBody.scope | Should -Be 'https://graph.microsoft.com/.default'
            $script:GTTokenCache.AuthType | Should -Be 'ClientSecret'
        }
    }

    Context "Validation & Error Handling" {
        It "throws error when no credentials or cached tokens exist" {
            { Get-GTCachedGraphToken } | Should -Throw "*No Microsoft Graph credentials configured*"
        }

        It "throws error when neither Certificate nor ClientSecret is provided with TenantId/ClientId" {
            { Get-GTCachedGraphToken -TenantId 't' -ClientId 'c' } | Should -Throw
        }
    }
}

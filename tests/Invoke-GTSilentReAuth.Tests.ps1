if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "Invoke-GTSilentReAuth" -Tag 'Unit' {
    BeforeAll {
        $helperPath = Join-Path $PSScriptRoot '..\internal\functions\Invoke-GTSilentReAuth.ps1'
        if (Test-Path $helperPath) { . $helperPath }

        $renewPath = Join-Path $PSScriptRoot '..\internal\functions\Invoke-GTRefreshTokenRenewal.ps1'
        if (Test-Path $renewPath) { . $renewPath }

        $getPath = Join-Path $PSScriptRoot '..\internal\functions\Get-GTPersistedTokenCache.ps1'
        if (Test-Path $getPath) { . $getPath }

        $savePath = Join-Path $PSScriptRoot '..\internal\functions\Save-GTPersistedTokenCache.ps1'
        if (Test-Path $savePath) { . $savePath }
    }

    BeforeEach {
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

    Context "In-Memory Probe" {
        It "successfully renews token using in-memory refresh token" {
            $script:GTTokenCache.TenantId = 'test-tenant'
            $script:GTTokenCache.ClientId = 'test-client'
            $script:GTTokenCache.RefreshToken = 'in-memory-refresh-token'
            $script:GTTokenCache.AuthType = 'DeviceCode'

            Mock -CommandName Invoke-GTRefreshTokenRenewal -MockWith {
                [PSCustomObject]@{
                    AccessToken  = 'renewed-access-token'
                    RefreshToken = 'renewed-refresh-token'
                    ExpiresIn    = 7200
                }
            }

            $result = Invoke-GTSilentReAuth -TenantId 'test-tenant' `
                                            -ClientId 'test-client' `
                                            -AuthType 'DeviceCode'

            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.AccessToken | Should -Be 'renewed-access-token'
            $result.RefreshToken | Should -Be 'renewed-refresh-token'
            $result.ExpiresIn | Should -Be 7200
        }
    }

    Context "Persisted Cache Probe" {
        It "falls back to persisted token store when in-memory cache is empty" {
            Mock -CommandName Get-GTPersistedTokenCache -MockWith {
                [PSCustomObject]@{
                    RefreshToken = 'disk-persisted-refresh-token'
                    TenantId     = 'test-tenant'
                    ClientId     = 'test-client'
                    AuthType     = 'Interactive'
                }
            }

            Mock -CommandName Invoke-GTRefreshTokenRenewal -MockWith {
                [PSCustomObject]@{
                    AccessToken  = 'disk-renewed-access-token'
                    RefreshToken = 'disk-renewed-refresh-token'
                    ExpiresIn    = 86400
                }
            }

            $result = Invoke-GTSilentReAuth -TenantId 'test-tenant' `
                                            -ClientId 'test-client' `
                                            -AuthType 'Interactive'

            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.AccessToken | Should -Be 'disk-renewed-access-token'
        }
    }

    Context "Failure Modes" {
        It "returns Success = `$false when no refresh token candidate exists" {
            Mock -CommandName Get-GTPersistedTokenCache -MockWith { $null }

            $result = Invoke-GTSilentReAuth -TenantId 'test-tenant' `
                                            -ClientId 'test-client' `
                                            -AuthType 'DeviceCode'

            $result.Success | Should -Be $false
            $result.AccessToken | Should -BeNullOrEmpty
        }

        It "returns Success = `$false when token renewal throws an exception" {
            $script:GTTokenCache.TenantId = 'test-tenant'
            $script:GTTokenCache.ClientId = 'test-client'
            $script:GTTokenCache.RefreshToken = 'expired-token'
            $script:GTTokenCache.AuthType = 'DeviceCode'

            Mock -CommandName Invoke-GTRefreshTokenRenewal -MockWith {
                throw "AADSTS700082: The refresh token has expired due to inactivity."
            }

            $result = Invoke-GTSilentReAuth -TenantId 'test-tenant' `
                                            -ClientId 'test-client' `
                                            -AuthType 'DeviceCode'

            $result.Success | Should -Be $false
            $result.AccessToken | Should -BeNullOrEmpty
        }
    }
}

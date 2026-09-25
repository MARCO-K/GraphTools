if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "Connect-GTGraph, Disconnect-GTGraph & Get-GTConnection" -Tag 'Unit' {
    BeforeAll {
        Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\*.ps1') | ForEach-Object { . $_.FullName }

        $connectFile = Join-Path -Path $PSScriptRoot -ChildPath '..\functions\Connect-GTGraph.ps1'
        if (Test-Path $connectFile) { . $connectFile }

        $disconnectFile = Join-Path -Path $PSScriptRoot -ChildPath '..\functions\Disconnect-GTGraph.ps1'
        if (Test-Path $disconnectFile) { . $disconnectFile }

        $getConnectionFile = Join-Path -Path $PSScriptRoot -ChildPath '..\functions\Get-GTConnection.ps1'
        if (Test-Path $getConnectionFile) { . $getConnectionFile }
    }

    BeforeEach {
        $script:GTConnectionConfig = $null
        $script:GTTokenCache = @{
            AccessToken = $null
            ExpiresAt   = [DateTime]::MinValue
            TenantId    = $null
            ClientId    = $null
            Scope       = $null
            AuthType    = $null
        }
    }

    Context "Connect-GTGraph" {
        It "authenticates via ClientSecret and returns clean PSCustomObject with -PassThru" {
            Mock -CommandName Invoke-RestMethod -MockWith {
                @{
                    access_token = 'mock-secret-access-token'
                    expires_in   = 3600
                }
            }

            $conn = Connect-GTGraph -TenantId 'test-tenant' -ClientId 'test-client' -ClientSecret 'my-secret' -PassThru

            $conn | Should -Not -BeNullOrEmpty
            $conn.Connected | Should -Be $true
            $conn.AuthType | Should -Be 'ClientSecret'
            $conn.TenantId | Should -Be 'test-tenant'
            $conn.ClientId | Should -Be 'test-client'
            $conn.PSObject.TypeNames | Should -Contain 'GraphTools.Connection'
        }

        It "connects via direct AccessToken" {
            $conn = Connect-GTGraph -AccessToken 'mock-raw-bearer-token' -PassThru

            $conn | Should -Not -BeNullOrEmpty
            $conn.Connected | Should -Be $true
            $conn.AuthType | Should -Be 'DirectToken'
        }

        It "authenticates via [System.Security.SecureString] ClientSecret" {
            Mock -CommandName Invoke-RestMethod -MockWith {
                @{
                    access_token = 'mock-secure-token'
                    expires_in   = 3600
                }
            }

            $secureSecret = [System.Security.SecureString]::new()
            'secret-val'.ToCharArray() | ForEach-Object { $secureSecret.AppendChar($_) }
            $conn = Connect-GTGraph -TenantId 'test-tenant' -ClientId 'test-client' -ClientSecret $secureSecret -PassThru

            $conn.Connected | Should -Be $true
            $conn.AuthType | Should -Be 'ClientSecret'
            $script:GTConnectionConfig.ClientSecret | Should -BeOfType [System.Security.SecureString]
        }

        It "authenticates via Azure Managed Identity (System-Assigned)" {
            Mock -CommandName Get-GTManagedIdentityToken -MockWith {
                [PSCustomObject]@{
                    AccessToken = 'mock-msi-token'
                    ExpiresIn   = 3600
                }
            }

            $conn = Connect-GTGraph -Identity -PassThru

            $conn.Connected | Should -Be $true
            $conn.AuthType | Should -Be 'Identity'
            $script:GTConnectionConfig.AuthType | Should -Be 'Identity'
        }

        It "authenticates via Azure Managed Identity (User-Assigned with ClientId)" {
            Mock -CommandName Get-GTManagedIdentityToken -MockWith {
                [PSCustomObject]@{
                    AccessToken = 'mock-user-msi-token'
                    ExpiresIn   = 3600
                }
            }

            $conn = Connect-GTGraph -Identity -IdentityId 'uami-client-id-123' -IdentityType ClientId -PassThru

            $conn.Connected | Should -Be $true
            $conn.AuthType | Should -Be 'Identity'
            $conn.IdentityId | Should -Be 'uami-client-id-123'
            $conn.IdentityType | Should -Be 'ClientId'
        }

        It "authenticates via Interactive browser flow with PKCE" {
            Mock -CommandName Invoke-GTOAuthHttpListener -MockWith {
                [PSCustomObject]@{
                    AccessToken  = 'mock-interactive-access-token'
                    RefreshToken = 'mock-refresh-token'
                    ExpiresIn    = 3600
                }
            }

            $conn = Connect-GTGraph -Interactive -TenantId 'test-tenant' -ClientId 'test-client' -PassThru

            $conn.Connected | Should -Be $true
            $conn.AuthType | Should -Be 'Interactive'
            $conn.RefreshTokenPresent | Should -Be $true
            $script:GTConnectionConfig.RefreshToken | Should -Be 'mock-refresh-token'
        }

        It "authenticates via Device Code flow" {
            Mock -CommandName Invoke-GTDeviceCodeFlow -MockWith {
                [PSCustomObject]@{
                    AccessToken  = 'mock-device-access-token'
                    RefreshToken = 'mock-device-refresh-token'
                    ExpiresIn    = 3600
                }
            }

            $conn = Connect-GTGraph -DeviceCode -TenantId 'test-tenant' -PassThru

            $conn.Connected | Should -Be $true
            $conn.AuthType | Should -Be 'DeviceCode'
            $conn.RefreshTokenPresent | Should -Be $true
            $script:GTConnectionConfig.RefreshToken | Should -Be 'mock-device-refresh-token'
        }
    }

    Context "Get-GTConnection" {
        It "reports connection status accurately when connected" {
            Connect-GTGraph -AccessToken 'active-token'

            $status = Get-GTConnection

            $status | Should -Not -BeNullOrEmpty
            $status.Connected | Should -Be $true
            $status.AuthType | Should -Be 'DirectToken'
            $status.PSObject.TypeNames | Should -Contain 'GraphTools.ConnectionStatus'
        }

        It "reports disconnected when no token exists" {
            Disconnect-GTGraph

            $status = Get-GTConnection

            $status.Connected | Should -Be $false
        }
    }

    Context "Disconnect-GTGraph" {
        It "clears cache and connection state" {
            Connect-GTGraph -AccessToken 'active-token'
            $disc = Disconnect-GTGraph -PassThru

            $disc.Status | Should -Be 'Disconnected'
            $disc.PSObject.TypeNames | Should -Contain 'GraphTools.DisconnectSummary'
            $script:GTConnectionConfig | Should -BeNullOrEmpty
            $script:GTTokenCache.AccessToken | Should -BeNullOrEmpty
        }
    }

    Context "Initialize-GTGraphConnection -SkipConnect" {
        BeforeAll {
            $initFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Initialize-GTGraphConnection.ps1'
            if (Test-Path $initFile) { . $initFile }
        }

        It "returns false when cached token is expired and no SDK context exists" {
            $script:GTTokenCache = @{
                AccessToken = 'expired-token'
                ExpiresAt   = [DateTime]::UtcNow.AddHours(-1)
            }

            $result = Initialize-GTGraphConnection -SkipConnect

            $result | Should -Be $false
        }

        It "returns true when cached token is valid and unexpired" {
            $script:GTTokenCache = @{
                AccessToken = 'valid-token'
                ExpiresAt   = [DateTime]::UtcNow.AddHours(1)
            }

            $result = Initialize-GTGraphConnection -SkipConnect

            $result | Should -Be $true
        }
    }

    Context "Initialize-GTGraphConnection -NewSession" {
        BeforeAll {
            $initFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Initialize-GTGraphConnection.ps1'
            if (Test-Path $initFile) { . $initFile }
        }

        It "refreshes token and preserves connection config when NewSession is specified" {
            $script:GTConnectionConfig = @{
                TenantId     = 'test-tenant'
                ClientId     = 'test-client'
                ClientSecret = 'test-secret'
                Scope        = 'https://graph.microsoft.com/.default'
            }
            $script:GTTokenCache = @{
                AccessToken = 'old-token'
                ExpiresAt   = [DateTime]::UtcNow.AddHours(1)
            }

            Mock -CommandName Invoke-RestMethod -MockWith {
                @{
                    access_token = 'new-refreshed-token'
                    expires_in   = 3600
                }
            }

            $result = Initialize-GTGraphConnection -NewSession

            $result | Should -Be $true
            $script:GTConnectionConfig | Should -Not -BeNullOrEmpty
            $script:GTTokenCache.AccessToken | Should -Be 'new-refreshed-token'
        }

        It "returns false when NewSession is specified without connection configuration" {
            $script:GTConnectionConfig = $null
            $script:GTTokenCache = @{
                AccessToken = 'orphan-token'
                ExpiresAt   = [DateTime]::UtcNow.AddHours(1)
            }

            $result = Initialize-GTGraphConnection -NewSession

            $result | Should -Be $false
            $script:GTTokenCache.AccessToken | Should -BeNullOrEmpty
        }
    }
}

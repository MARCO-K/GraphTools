if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "Connect-GTGraph, Disconnect-GTGraph & Get-GTConnection" -Tag 'Unit' {
    BeforeAll {
        $tokenFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Get-GTCachedGraphToken.ps1'
        if (Test-Path $tokenFile) { . $tokenFile }

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
}

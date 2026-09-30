if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "Persisted Token Cache" -Tag 'Unit' {
    BeforeAll {
        $saveFile = Join-Path $PSScriptRoot '..\internal\functions\Save-GTPersistedTokenCache.ps1'
        if (Test-Path $saveFile) { . $saveFile }

        $getFile = Join-Path $PSScriptRoot '..\internal\functions\Get-GTPersistedTokenCache.ps1'
        if (Test-Path $getFile) { . $getFile }

        $clearFile = Join-Path $PSScriptRoot '..\internal\functions\Clear-GTPersistedTokenCache.ps1'
        if (Test-Path $clearFile) { . $clearFile }

        $script:cacheDir = Join-Path ([System.Environment]::GetFolderPath('LocalApplicationData')) 'GraphTools'
        $script:cacheFile = Join-Path $script:cacheDir 'tokens.json'
        $script:backupFile = Join-Path $script:cacheDir 'tokens.json.testbackup'

        # Backup existing token cache file if present
        if (Test-Path $script:cacheFile) {
            Move-Item -Path $script:cacheFile -Destination $script:backupFile -Force
        }
    }

    AfterAll {
        # Restore backup or clean test artifacts
        if (Test-Path $script:cacheFile) {
            Remove-Item -Path $script:cacheFile -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $script:backupFile) {
            Move-Item -Path $script:backupFile -Destination $script:cacheFile -Force
        }
    }

    BeforeEach {
        if (Test-Path $script:cacheFile) {
            Remove-Item -Path $script:cacheFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Save and Retrieve" {
        It "securely persists and retrieves refresh token with metadata" {
            $saveResult = Save-GTPersistedTokenCache -TenantId 'test-tenant-1' `
                                                    -ClientId 'test-client-1' `
                                                    -RefreshToken 'refresh-token-secret-xyz' `
                                                    -Scope 'https://graph.microsoft.com/.default' `
                                                    -AuthType 'Interactive'

            $saveResult | Should -Be $true
            Test-Path $script:cacheFile | Should -Be $true

            $entry = Get-GTPersistedTokenCache -TenantId 'test-tenant-1' -ClientId 'test-client-1' -AuthType 'Interactive'

            $entry | Should -Not -BeNullOrEmpty
            $entry.RefreshToken | Should -Be 'refresh-token-secret-xyz'
            $entry.TenantId | Should -Be 'test-tenant-1'
            $entry.ClientId | Should -Be 'test-client-1'
            $entry.Scope | Should -Be 'https://graph.microsoft.com/.default'
            $entry.AuthType | Should -Be 'Interactive'
            $entry.Cae | Should -Be $true
        }

        It "maintains cache isolation across distinct tenants and clients" {
            $null = Save-GTPersistedTokenCache -TenantId 'tenant-alpha' -ClientId 'client-alpha' -RefreshToken 'token-alpha' -AuthType 'Interactive'
            $null = Save-GTPersistedTokenCache -TenantId 'tenant-beta' -ClientId 'client-beta' -RefreshToken 'token-beta' -AuthType 'Interactive'

            $entryAlpha = Get-GTPersistedTokenCache -TenantId 'tenant-alpha' -ClientId 'client-alpha'
            $entryBeta = Get-GTPersistedTokenCache -TenantId 'tenant-beta' -ClientId 'client-beta'
            $entryNonExistent = Get-GTPersistedTokenCache -TenantId 'tenant-gamma' -ClientId 'client-alpha'

            $entryAlpha.RefreshToken | Should -Be 'token-alpha'
            $entryBeta.RefreshToken | Should -Be 'token-beta'
            $entryNonExistent | Should -BeNullOrEmpty
        }

        It "returns null when no matching entry exists" {
            $entry = Get-GTPersistedTokenCache -TenantId 'non-existent' -ClientId 'non-existent'
            $entry | Should -BeNullOrEmpty
        }
    }

    Context "Clear" {
        It "clears a targeted identity entry while retaining others" {
            $null = Save-GTPersistedTokenCache -TenantId 'tenant-alpha' -ClientId 'client-alpha' -RefreshToken 'token-alpha' -AuthType 'Interactive'
            $null = Save-GTPersistedTokenCache -TenantId 'tenant-beta' -ClientId 'client-beta' -RefreshToken 'token-beta' -AuthType 'Interactive'

            $clearResult = Clear-GTPersistedTokenCache -TenantId 'tenant-alpha' -ClientId 'client-alpha' -AuthType 'Interactive'

            $clearResult.Cleared | Should -Be $true
            $clearResult.EntriesReset | Should -Be 1

            $entryAlpha = Get-GTPersistedTokenCache -TenantId 'tenant-alpha' -ClientId 'client-alpha'
            $entryBeta = Get-GTPersistedTokenCache -TenantId 'tenant-beta' -ClientId 'client-beta'

            $entryAlpha | Should -BeNullOrEmpty
            $entryBeta | Should -Not -BeNullOrEmpty
            $entryBeta.RefreshToken | Should -Be 'token-beta'
        }

        It "clears all entries when -All is specified" {
            $null = Save-GTPersistedTokenCache -TenantId 'tenant-alpha' -ClientId 'client-alpha' -RefreshToken 'token-alpha' -AuthType 'Interactive'
            $null = Save-GTPersistedTokenCache -TenantId 'tenant-beta' -ClientId 'client-beta' -RefreshToken 'token-beta' -AuthType 'Interactive'

            $clearResult = Clear-GTPersistedTokenCache -All

            $clearResult.Cleared | Should -Be $true
            Test-Path $script:cacheFile | Should -Be $false
        }
    }
}

if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "Get-GTConnection" -Tag 'Unit' {
    BeforeAll {
        . "$PSScriptRoot/../functions/Get-GTConnection.ps1"
    }

    BeforeEach {
        $script:GTTokenCache = $null
        $script:GTConnectionConfig = $null
    }

    Context "Not Connected (No State)" {
        It "returns unconnected state when no config or cache exists" {
            $result = Get-GTConnection

            $result.Connected | Should -Be $false
            $result.TenantId | Should -BeNullOrEmpty
            $result.ClientId | Should -BeNullOrEmpty
            $result.AuthType | Should -BeNullOrEmpty
            $result.Scope | Should -BeNullOrEmpty
            $result.Scopes.Count | Should -Be 0
            $result.Roles.Count | Should -Be 0
            $result.ExpiresAt | Should -BeNullOrEmpty
            $result.IdentityId | Should -BeNullOrEmpty
            $result.IdentityType | Should -BeNullOrEmpty
            $result.RefreshTokenPresent | Should -Be $false
            $result.TimeUtc | Should -Not -BeNullOrEmpty
        }
    }

    Context "Connected with Token Cache Only" {
        It "maps properties correctly from token cache" {
            $futureDate = [DateTime]::UtcNow.AddHours(1)
            $script:GTTokenCache = @{
                AccessToken  = "mock-access-token"
                ExpiresAt    = $futureDate
                TenantId     = "cache-tenant"
                ClientId     = "cache-client"
                AuthType     = "Interactive"
                Scope        = "User.Read Mail.Read"
                Permissions  = @("User.Read", "Mail.Read")
                Roles        = @("Global Administrator")
                RefreshToken = "mock-refresh-token"
            }

            $result = Get-GTConnection

            $result.Connected | Should -Be $true
            $result.TenantId | Should -Be "cache-tenant"
            $result.ClientId | Should -Be "cache-client"
            $result.AuthType | Should -Be "Interactive"
            $result.Scope | Should -Be "User.Read Mail.Read"
            $result.Scopes -join ',' | Should -Be "User.Read,Mail.Read"
            $result.Roles -join ',' | Should -Be "Global Administrator"
            $result.ExpiresAt | Should -Be $futureDate
            $result.RefreshTokenPresent | Should -Be $true
        }
    }

    Context "Expired Token Cache" {
        It "returns connected as false when token is expired" {
            $pastDate = [DateTime]::UtcNow.AddHours(-1)
            $script:GTTokenCache = @{
                AccessToken = "mock-access-token"
                ExpiresAt   = $pastDate
            }

            $result = Get-GTConnection

            $result.Connected | Should -Be $false
            $result.ExpiresAt | Should -Be $pastDate
        }
    }

    Context "Connected with Connection Config Only" {
        It "maps properties correctly from connection config" {
            $script:GTConnectionConfig = @{
                TenantId     = "config-tenant"
                ClientId     = "config-client"
                AuthType     = "ManagedIdentity"
                Scope        = "https://graph.microsoft.com/.default"
                IdentityId   = "mock-identity-id"
                IdentityType = "SystemAssigned"
            }

            $result = Get-GTConnection

            $result.Connected | Should -Be $false # Because there's no actual token yet
            $result.TenantId | Should -Be "config-tenant"
            $result.ClientId | Should -Be "config-client"
            $result.AuthType | Should -Be "ManagedIdentity"
            $result.Scope | Should -Be "https://graph.microsoft.com/.default"
            $result.Scopes -join ',' | Should -Be "https://graph.microsoft.com/.default"
            $result.IdentityId | Should -Be "mock-identity-id"
            $result.IdentityType | Should -Be "SystemAssigned"
            $result.RefreshTokenPresent | Should -Be $false
        }
    }

    Context "Mixed State (Config and Cache present)" {
        It "prioritizes config over cache where appropriate" {
            $script:GTConnectionConfig = @{
                TenantId = "config-tenant"
                ClientId = "config-client"
                AuthType = "Interactive"
                Scope    = "User.Read"
            }
            $script:GTTokenCache = @{
                AccessToken = "mock-token"
                ExpiresAt   = [DateTime]::UtcNow.AddHours(1)
                TenantId    = "cache-tenant"
                ClientId    = "cache-client"
                AuthType    = "ClientSecret"
                Scope       = "Mail.Read"
                Roles       = @("User.Read.All")
                Permissions = @("Mail.Read")
            }

            $result = Get-GTConnection

            $result.Connected | Should -Be $true
            $result.TenantId | Should -Be "config-tenant"
            $result.ClientId | Should -Be "config-client"
            # AuthType logic: if GTTokenCache.AuthType exists, use it; else if GTConnectionConfig exists, use it
            $result.AuthType | Should -Be "ClientSecret"
            # Scope logic: if GTConnectionConfig.Scope exists, use it; else if GTTokenCache exists, use it
            $result.Scope | Should -Be "User.Read"

            # Permissions logic in Get-GTConnection prioritizes GTTokenCache.Permissions if count > 0, else splits GTConnectionConfig.Scope
            $result.Scopes -join ',' | Should -Be "Mail.Read"

            $result.Roles -join ',' | Should -Be "User.Read.All"
        }
    }
}

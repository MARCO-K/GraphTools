function Get-GTPersistedTokenCache
{
    <#
    .SYNOPSIS
        Retrieves a securely persisted OAuth 2.0 refresh token from disk.
    .DESCRIPTION
        Loads and decrypts (via Windows DPAPI on Windows) the persisted token cache
        entry matching the requested Tenant ID, Client ID, and authentication flow.
    .PARAMETER TenantId
        The Microsoft Entra ID Tenant ID or authority domain.
    .PARAMETER ClientId
        The Application (Client) ID.
    .PARAMETER AuthType
        The authentication flow type ('Interactive' or 'DeviceCode'). Defaults to 'Interactive'.
    .OUTPUTS
        [PSCustomObject] containing RefreshToken, TenantId, ClientId, Scope, AuthType, or $null.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter()]
        [string]$AuthType = 'Interactive'
    )

    $cacheDir = Join-Path ([System.Environment]::GetFolderPath('LocalApplicationData')) 'GraphTools'
    $cacheFile = Join-Path $cacheDir 'tokens.json'

    if (-not (Test-Path $cacheFile))
    {
        return $null
    }

    try
    {
        $cache = Get-Content -Path $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $cacheKey = "$TenantId|$ClientId|$AuthType"

        if (-not $cache -or -not $cache.PSObject.Properties[$cacheKey])
        {
            return $null
        }

        $entry = $cache.$cacheKey
        $payloadJson = $null

        if ($entry.encrypted)
        {
            $onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
            if (-not $onWindows)
            {
                return $null
            }

            Add-Type -AssemblyName System.Security
            $encryptedBytes = [Convert]::FromBase64String($entry.data)
            $payloadBytes = [System.Security.Cryptography.ProtectedData]::Unprotect($encryptedBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
            $payloadJson = [System.Text.Encoding]::UTF8.GetString($payloadBytes)
        }
        else
        {
            $payloadJson = $entry.data
        }

        $parsed = $payloadJson | ConvertFrom-Json
        if (-not $parsed.refresh_token)
        {
            return $null
        }

        return [PSCustomObject]@{
            PSTypeName   = 'GraphTools.PersistedTokenCacheEntry'
            RefreshToken = $parsed.refresh_token
            TenantId     = $parsed.tenant_id
            ClientId     = $parsed.client_id
            Scope        = $parsed.scope
            AuthType     = $parsed.auth_type
            Cae          = [bool]$parsed.cae
        }
    }
    catch
    {
        Write-PSFMessage -Level Verbose -Message "Failed to load or decrypt persisted token cache entry: $_"
        return $null
    }
}

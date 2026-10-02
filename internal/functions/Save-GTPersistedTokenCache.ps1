function Save-GTPersistedTokenCache
{
    <#
    .SYNOPSIS
        Securely persists an OAuth 2.0 refresh token to disk using DPAPI encryption.
    .DESCRIPTION
        Stores the refresh token and metadata in the user's LocalApplicationData folder.
        On Windows, payload is encrypted using Windows Data Protection API (DPAPI) via SecureString.
        On non-Windows, directory and file permissions are restricted to user-only (0700/0600).
        Short-lived access tokens are strictly excluded and never written to disk.
    .PARAMETER TenantId
        The Microsoft Entra ID Tenant ID or authority domain.
    .PARAMETER ClientId
        The Application (Client) ID.
    .PARAMETER RefreshToken
        The OAuth 2.0 refresh token to persist.
    .PARAMETER Scope
        The granted permission scope.
    .PARAMETER AuthType
        The authentication flow type ('Interactive' or 'DeviceCode').
    .OUTPUTS
        [bool] Returns $true on successful persistence.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$RefreshToken,

        [Parameter()]
        [string]$Scope = 'https://graph.microsoft.com/.default',

        [Parameter()]
        [string]$AuthType = 'Interactive'
    )

    if ([string]::IsNullOrWhiteSpace($RefreshToken))
    {
        return $false
    }

    $cacheDir = Join-Path ([System.Environment]::GetFolderPath('LocalApplicationData')) 'GraphTools'
    $cacheFile = Join-Path $cacheDir 'tokens.json'

    if (-not (Test-Path $cacheDir))
    {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    $payloadObject = [ordered]@{
        refresh_token = $RefreshToken
        tenant_id     = $TenantId
        client_id     = $ClientId
        scope         = $Scope
        auth_type     = $AuthType
        cae           = $true
    }
    $payloadJson = $payloadObject | ConvertTo-Json -Compress

    $onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

    $entry = $null
    if ($onWindows)
    {
        Add-Type -AssemblyName System.Security
        $payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($payloadJson)
        $encryptedBytes = [System.Security.Cryptography.ProtectedData]::Protect($payloadBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        $encryptedString = [Convert]::ToBase64String($encryptedBytes)

        $entry = [ordered]@{
            encrypted = $true
            data      = $encryptedString
            saved     = [DateTime]::UtcNow.ToString('o')
        }
    }
    else
    {
        $entry = [ordered]@{
            encrypted = $false
            data      = $payloadJson
            saved     = [DateTime]::UtcNow.ToString('o')
        }
    }

    $cache = @{}
    if (Test-Path $cacheFile)
    {
        try
        {
            $existing = Get-Content -Path $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existing)
            {
                foreach ($prop in $existing.PSObject.Properties)
                {
                    $cache[$prop.Name] = $prop.Value
                }
            }
        }
        catch
        {
            Write-PSFMessage -Level Verbose -Message "Existing token cache was unreadable, creating new cache store: $_"
        }
    }

    $cacheKey = "$TenantId|$ClientId|$AuthType"
    $cache[$cacheKey] = $entry

    if (-not $onWindows)
    {
        try
        {
            & chmod 700 $cacheDir 2>$null
            if (-not (Test-Path $cacheFile))
            {
                New-Item -ItemType File -Path $cacheFile -Force | Out-Null
            }
            & chmod 600 $cacheFile 2>$null
        }
        catch
        {
            Write-PSFMessage -Level Warning -Message "Unable to restrict POSIX permissions on token cache file: $_"
        }
    }

    $cache | ConvertTo-Json -Depth 5 | Set-Content -Path $cacheFile -Encoding UTF8 -Force
    return $true
}

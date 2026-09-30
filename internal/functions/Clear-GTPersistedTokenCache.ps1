function Clear-GTPersistedTokenCache
{
    <#
    .SYNOPSIS
        Clears persisted OAuth 2.0 refresh tokens from disk.
    .DESCRIPTION
        Removes the persisted token cache file or a specific cached identity entry.
    .PARAMETER TenantId
        Optional Tenant ID to target a specific entry.
    .PARAMETER ClientId
        Optional Client ID to target a specific entry.
    .PARAMETER AuthType
        Optional authentication flow to target.
    .PARAMETER All
        Clears all persisted tokens across all tenants and clients.
    .OUTPUTS
        [PSCustomObject]
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [string]$AuthType,

        [Parameter()]
        [switch]$All
    )

    $cacheDir = Join-Path ([System.Environment]::GetFolderPath('LocalApplicationData')) 'GraphTools'
    $cacheFile = Join-Path $cacheDir 'tokens.json'

    if (-not (Test-Path $cacheFile))
    {
        return [PSCustomObject]@{
            PSTypeName   = 'GraphTools.CacheClearResult'
            Cleared      = $false
            EntriesReset = 0
            Message      = 'No persisted token cache file found.'
        }
    }

    if ($All -or (-not $TenantId -and -not $ClientId -and -not $AuthType))
    {
        Remove-Item -Path $cacheFile -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{
            PSTypeName   = 'GraphTools.CacheClearResult'
            Cleared      = $true
            EntriesReset = -1
            Message      = 'All persisted tokens cleared.'
        }
    }

    try
    {
        $cache = Get-Content -Path $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $keysToRemove = @()

        foreach ($prop in $cache.PSObject.Properties)
        {
            $k = $prop.Name
            $parts = $k -split '\|'
            $entryTenant = if ($parts.Length -gt 0) { $parts[0] } else { '' }
            $entryClient = if ($parts.Length -gt 1) { $parts[1] } else { '' }
            $entryAuth   = if ($parts.Length -gt 2) { $parts[2] } else { '' }

            $matchTenant = (-not $TenantId) -or ($entryTenant -eq $TenantId)
            $matchClient = (-not $ClientId) -or ($entryClient -eq $ClientId)
            $matchAuth   = (-not $AuthType) -or ($entryAuth -eq $AuthType)

            if ($matchTenant -and $matchClient -and $matchAuth)
            {
                $keysToRemove += $k
            }
        }

        $newCache = @{}
        foreach ($prop in $cache.PSObject.Properties)
        {
            if ($prop.Name -notin $keysToRemove)
            {
                $newCache[$prop.Name] = $prop.Value
            }
        }

        if ($newCache.Keys.Count -eq 0)
        {
            Remove-Item -Path $cacheFile -Force -ErrorAction SilentlyContinue
        }
        else
        {
            $newCache | ConvertTo-Json -Depth 5 | Set-Content -Path $cacheFile -Encoding UTF8 -Force
        }

        return [PSCustomObject]@{
            PSTypeName   = 'GraphTools.CacheClearResult'
            Cleared      = $true
            EntriesReset = $keysToRemove.Count
            Message      = "Cleared $($keysToRemove.Count) matching token cache entry/entries."
        }
    }
    catch
    {
        Write-PSFMessage -Level Warning -Message "Failed to clear persisted token cache: $_"
        return [PSCustomObject]@{
            PSTypeName   = 'GraphTools.CacheClearResult'
            Cleared      = $false
            EntriesReset = 0
            Message      = "Error clearing cache: $_"
        }
    }
}

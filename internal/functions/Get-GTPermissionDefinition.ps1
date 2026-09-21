function Get-GTPermissionDefinition
{
    <#
    .SYNOPSIS
    Loads and caches the Microsoft Graph permissions metadata catalog.

    .DESCRIPTION
    Retrieves permission metadata derived from Microsoft DevX content, providing
    privilege levels (1-5) for Application and DelegatedWork schemes, admin consent
    requirements, and permission descriptions.
    #>
    [CmdletBinding()]
    param (
        # Optional custom file path to load permissions metadata from
        [string]$PermissionsFile,

        # Force reloading from disk bypassing the in-memory cache
        [switch]$ForceRefresh
    )

    if (-not $ForceRefresh -and $script:GTPermissionCache -and -not $PermissionsFile)
    {
        return $script:GTPermissionCache
    }

    $targetFile = if ($PermissionsFile) { $PermissionsFile } else {
        $moduleBase = if ($script:ModuleRoot) { $script:ModuleRoot } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
        Join-Path $moduleBase 'data\graph-permissions.json'
    }

    if (-not (Test-Path -Path $targetFile))
    {
        Write-PSFMessage -Level Verbose -Message "Permissions metadata file not found at '$targetFile'."
        return $null
    }

    try
    {
        $rawJson = Get-Content -Path $targetFile -Raw -ErrorAction Stop
        $parsed = $rawJson | ConvertFrom-Json -AsHashtable -ErrorAction Stop

        # Store in case-insensitive hashtable for resilient lookups
        $ciCatalog = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($key in $parsed.Keys)
        {
            $ciCatalog[$key] = $parsed[$key]
        }

        if (-not $PermissionsFile)
        {
            $script:GTPermissionCache = $ciCatalog
        }

        return $ciCatalog
    }
    catch
    {
        Write-PSFMessage -Level Warning -Message "Failed to load permissions catalog from '$targetFile': $($_.Exception.Message)"
        return $null
    }
}

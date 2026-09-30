function Disconnect-GTGraph
{
    <#
    .SYNOPSIS
        Disconnects the active Microsoft Graph session and clears cached tokens.

    .DESCRIPTION
        Clears cached credentials, tokens, refresh tokens, and session context from the module runspace.
        Optionally clears on-disk DPAPI-encrypted token cache entries when -ClearPersistedCache is specified.

    .PARAMETER ClearPersistedCache
        When specified, also clears all persisted token cache entries stored on disk.

    .PARAMETER PassThru
        Returns the disconnection summary object.

    .OUTPUTS
        [PSCustomObject]

    .EXAMPLE
        Disconnect-GTGraph

    .EXAMPLE
        Disconnect-GTGraph -ClearPersistedCache -PassThru
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$ClearPersistedCache,

        [Parameter()]
        [switch]$PassThru
    )

    $script:GTConnectionConfig = $null
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

    $persistedCleared = $false
    if ($ClearPersistedCache)
    {
        $clearFn = Join-Path $PSScriptRoot '..\internal\functions\Clear-GTPersistedTokenCache.ps1'
        if (-not (Get-Command Clear-GTPersistedTokenCache -ErrorAction SilentlyContinue) -and (Test-Path $clearFn))
        {
            . $clearFn
        }

        if (Get-Command Clear-GTPersistedTokenCache -ErrorAction SilentlyContinue)
        {
            $clearResult = Clear-GTPersistedTokenCache -All
            $persistedCleared = [bool]($clearResult -and $clearResult.Cleared)
        }
    }

    Write-PSFMessage -Level Verbose -Message 'Microsoft Graph session disconnected and token cache cleared.'

    $summary = [PSCustomObject]@{
        PSTypeName            = 'GraphTools.DisconnectSummary'
        Status                = 'Disconnected'
        PersistedCacheCleared = $persistedCleared
        TimeUtc               = [DateTime]::UtcNow.ToString('o')
    }

    if ($PassThru)
    {
        return $summary
    }
}

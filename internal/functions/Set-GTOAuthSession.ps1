function Set-GTOAuthSession
{
    <#
    .SYNOPSIS
        Configures session state and caches credentials for delegated OAuth 2.0 connections.
    .DESCRIPTION
        Centralizes the population of $script:GTConnectionConfig and $script:GTTokenCache across
        Interactive and DeviceCode authentication paths, and optionally persists refresh tokens via DPAPI.
    .PARAMETER TenantId
        Microsoft Entra ID Tenant ID.
    .PARAMETER ClientId
        The Application (Client) ID.
    .PARAMETER AuthType
        The authentication flow ('Interactive' or 'DeviceCode').
    .PARAMETER Scope
        Requested permission scopes.
    .PARAMETER AuthResult
        Authentication result object containing AccessToken, RefreshToken, and ExpiresIn.
    .PARAMETER LocalPort
        Optional ephemeral loopback port for interactive browser sessions.
    .PARAMETER PersistRefreshToken
        When specified, encrypts and stores the refresh token in the on-disk DPAPI token store.
    .OUTPUTS
        [PSCustomObject]
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal helper that sets in-memory module session state.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Interactive', 'DeviceCode')]
        [string]$AuthType,

        [Parameter()]
        [string]$Scope = 'https://graph.microsoft.com/.default',

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AuthResult,

        [Parameter()]
        [int]$LocalPort = 0,

        [Parameter()]
        [switch]$PersistRefreshToken
    )

    $connConfig = @{
        AuthType            = $AuthType
        TenantId            = $TenantId
        ClientId            = $ClientId
        RefreshToken        = $AuthResult.RefreshToken
        Scope               = $Scope
        PersistRefreshToken = [bool]$PersistRefreshToken
    }

    if ($AuthType -eq 'Interactive')
    {
        $connConfig.LocalPort = $LocalPort
    }

    $script:GTConnectionConfig = $connConfig

    # Cache token and extract claims
    $tokenFile = Join-Path $PSScriptRoot 'Get-GTCachedGraphToken.ps1'
    if (-not (Get-Command Get-GTCachedGraphToken -ErrorAction SilentlyContinue) -and (Test-Path $tokenFile))
    {
        . $tokenFile
    }

    $null = Get-GTCachedGraphToken -AccessToken $AuthResult.AccessToken
    $script:GTTokenCache.AuthType = $AuthType
    $script:GTTokenCache.TenantId = $TenantId
    $script:GTTokenCache.ClientId = $ClientId
    $script:GTTokenCache.Scope = $Scope
    $script:GTTokenCache.ExpiresAt = [DateTime]::UtcNow.AddSeconds($AuthResult.ExpiresIn)

    if ($AuthResult.RefreshToken)
    {
        $script:GTTokenCache.RefreshToken = $AuthResult.RefreshToken

        if ($PersistRefreshToken)
        {
            $saveCacheFn = Join-Path $PSScriptRoot 'Save-GTPersistedTokenCache.ps1'
            if (-not (Get-Command Save-GTPersistedTokenCache -ErrorAction SilentlyContinue) -and (Test-Path $saveCacheFn))
            {
                . $saveCacheFn
            }
            if (Get-Command Save-GTPersistedTokenCache -ErrorAction SilentlyContinue)
            {
                $null = Save-GTPersistedTokenCache -TenantId $TenantId `
                                                   -ClientId $ClientId `
                                                   -RefreshToken $AuthResult.RefreshToken `
                                                   -Scope $Scope `
                                                   -AuthType $AuthType
            }
        }
    }

    return [PSCustomObject]@{
        PSTypeName   = 'GraphTools.OAuthSessionResult'
        Success      = $true
        AccessToken  = $AuthResult.AccessToken
        RefreshToken = $AuthResult.RefreshToken
        ExpiresIn    = $AuthResult.ExpiresIn
        AuthType     = $AuthType
    }
}

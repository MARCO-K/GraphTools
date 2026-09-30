function Invoke-GTSilentReAuth
{
    <#
    .SYNOPSIS
        Attempts silent re-authentication using in-memory or persisted OAuth 2.0 refresh tokens.
    .DESCRIPTION
        Probes the in-memory cache and DPAPI-persisted token store for a matching refresh token.
        If found, submits a refresh_token grant to acquire fresh access and rolling refresh tokens.
    .PARAMETER TenantId
        Microsoft Entra ID Tenant ID or authority domain.
    .PARAMETER ClientId
        The Application (Client) ID.
    .PARAMETER AuthType
        The authentication flow ('Interactive' or 'DeviceCode').
    .PARAMETER Scope
        Requested permission scopes.
    .OUTPUTS
        [PSCustomObject]
    #>
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
        [string]$Scope = 'https://graph.microsoft.com/.default'
    )

    $candidateRefreshToken = $null

    # 1. In-memory token cache probe
    if ($script:GTTokenCache -and $script:GTTokenCache.RefreshToken -and
        $script:GTTokenCache.TenantId -eq $TenantId -and
        $script:GTTokenCache.ClientId -eq $ClientId -and
        (-not $script:GTTokenCache.AuthType -or $script:GTTokenCache.AuthType -eq $AuthType))
    {
        $candidateRefreshToken = $script:GTTokenCache.RefreshToken
    }

    # 2. Persisted token cache probe
    if (-not $candidateRefreshToken)
    {
        $persistedFn = Join-Path $PSScriptRoot 'Get-GTPersistedTokenCache.ps1'
        if (-not (Get-Command Get-GTPersistedTokenCache -ErrorAction SilentlyContinue) -and (Test-Path $persistedFn))
        {
            . $persistedFn
        }
        if (Get-Command Get-GTPersistedTokenCache -ErrorAction SilentlyContinue)
        {
            $persistedEntry = Get-GTPersistedTokenCache -TenantId $TenantId -ClientId $ClientId -AuthType $AuthType
            if ($persistedEntry -and $persistedEntry.RefreshToken)
            {
                $candidateRefreshToken = $persistedEntry.RefreshToken
            }
        }
    }

    # 3. Refresh token renewal execution
    if ($candidateRefreshToken)
    {
        $renewFn = Join-Path $PSScriptRoot 'Invoke-GTRefreshTokenRenewal.ps1'
        if (-not (Get-Command Invoke-GTRefreshTokenRenewal -ErrorAction SilentlyContinue) -and (Test-Path $renewFn))
        {
            . $renewFn
        }

        if (Get-Command Invoke-GTRefreshTokenRenewal -ErrorAction SilentlyContinue)
        {
            try
            {
                Write-PSFMessage -Level Verbose -Message "Attempting silent $AuthType re-authentication using cached refresh token..."
                $renewResult = Invoke-GTRefreshTokenRenewal -TenantId $TenantId -ClientId $ClientId -RefreshToken $candidateRefreshToken -Scope $Scope

                return [PSCustomObject]@{
                    PSTypeName   = 'GraphTools.SilentReAuthResult'
                    Success      = $true
                    AccessToken  = $renewResult.AccessToken
                    RefreshToken = $renewResult.RefreshToken
                    ExpiresIn    = $renewResult.ExpiresIn
                }
            }
            catch
            {
                Write-PSFMessage -Level Verbose -Message "Silent $AuthType re-authentication failed, falling back to manual sign-in: $_"
            }
        }
    }

    return [PSCustomObject]@{
        PSTypeName   = 'GraphTools.SilentReAuthResult'
        Success      = $false
        AccessToken  = $null
        RefreshToken = $null
        ExpiresIn    = 0
    }
}

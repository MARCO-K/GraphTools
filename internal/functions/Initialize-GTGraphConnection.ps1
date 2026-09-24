function Initialize-GTGraphConnection
{
    <#
    .SYNOPSIS
        Ensures Microsoft Graph connection is established with required scopes
    .DESCRIPTION
        This internal helper function standardizes Graph connection handling across all GraphTools functions
        using the native zero-dependency REST engine.
        It handles:
        - Optional disconnection of existing sessions via Disconnect-GTGraph
        - Checking for existing token cache or connection configuration
        - Scope validation against active session
        - Error handling and logging
    .PARAMETER Scopes
        Array of Microsoft Graph permission scopes required for the operation
    .PARAMETER NewSession
        If specified, disconnects any existing Graph session before connecting
    .PARAMETER SkipConnect
        If specified, only checks for existing connection without attempting new token acquisition.
        Useful for functions that expect user to connect first.
    .EXAMPLE
        Initialize-GTGraphConnection -Scopes 'User.Read.All'

        Ensures Graph connection with User.Read.All scope
    .EXAMPLE
        Initialize-GTGraphConnection -Scopes 'User.ReadWrite.All' -NewSession

        Closes existing session and connects with User.ReadWrite.All scope
    .EXAMPLE
        Initialize-GTGraphConnection -SkipConnect

        Only checks if connection exists, returns $true or $false
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Scopes,

        [Parameter(Mandatory = $false)]
        [switch]$NewSession,

        [Parameter(Mandatory = $false)]
        [switch]$SkipConnect
    )

    try
    {
        # Refresh session token if requested
        if ($NewSession)
        {
            Write-PSFMessage -Level Verbose -Message 'NewSession requested: refreshing Microsoft Graph token.'
            $script:GTTokenCache = @{
                AccessToken = $null
                ExpiresAt   = [DateTime]::MinValue
                TenantId    = $null
                ClientId    = $null
                Scope       = $null
                AuthType    = $null
            }

            if ($script:GTConnectionConfig)
            {
                try
                {
                    $null = Get-GTCachedGraphToken -ForceRefresh -ErrorAction Stop
                }
                catch
                {
                    Write-PSFMessage -Level Warning -Message "Failed to refresh token for new session: $_"
                    return $false
                }
            }
        }

        $now = [DateTime]::UtcNow
        $hasValidCache = ($null -ne $script:GTTokenCache) -and
                         [bool]$script:GTTokenCache.AccessToken -and
                         ($script:GTTokenCache.ExpiresAt -gt $now)

        if ($SkipConnect)
        {
            return $hasValidCache
        }

        if ($hasValidCache)
        {
            Write-PSFMessage -Level Verbose -Message 'Using existing zero-dependency Microsoft Graph token.'
        }
        elseif ($script:GTConnectionConfig)
        {
            try
            {
                $token = Get-GTCachedGraphToken -ErrorAction Stop
                if (-not $token)
                {
                    Write-PSFMessage -Level Warning -Message 'No active Microsoft Graph connection found. Use Connect-GTGraph to establish a connection.'
                    return $false
                }
                Write-PSFMessage -Level Verbose -Message 'Acquired fresh Microsoft Graph token from active connection configuration.'
            }
            catch
            {
                Write-PSFMessage -Level Warning -Message "Failed to acquire token from connection configuration: $_"
                return $false
            }
        }
        else
        {
            Write-PSFMessage -Level Warning -Message 'No active Microsoft Graph connection found. Use Connect-GTGraph to establish a connection.'
            return $false
        }

        if ($Scopes)
        {
            if (-not (Test-GTGraphScopes -RequiredScopes $Scopes -Quiet))
            {
                Write-PSFMessage -Level Warning -Message "Microsoft Graph session is missing required scopes: $($Scopes -join ', ')"
                return $false
            }
        }

        return $true
    }
    catch
    {
        Write-PSFMessage -Level Error -Message 'Failed to connect to Microsoft Graph.'
        throw "Graph connection failed: $_"
    }
}

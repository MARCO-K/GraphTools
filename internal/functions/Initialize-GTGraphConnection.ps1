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
        # Close existing session if requested
        if ($NewSession)
        {
            Write-PSFMessage -Level Verbose -Message 'Closing existing Microsoft Graph session.'
            Disconnect-GTGraph
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
            $conn = Get-GTConnection
            $currentScopes = if ($conn.Scopes) { $conn.Scopes } elseif ($conn.Scope) { $conn.Scope -split ' ' } else { @() }

            # If using .default (App-only or default consent), skip missing scope check
            $hasDefaultScope = ($currentScopes -contains 'https://graph.microsoft.com/.default') -or ($currentScopes -contains '.default')
            if (-not $hasDefaultScope -and $currentScopes.Count -gt 0)
            {
                $missingScopes = Get-GTMissingScopes -RequiredScopes $Scopes -CurrentScopes $currentScopes
                if ($missingScopes.Count -gt 0)
                {
                    Write-PSFMessage -Level Warning -Message "Existing Microsoft Graph context is missing required scopes: $($missingScopes -join ', ')"
                    return $false
                }
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

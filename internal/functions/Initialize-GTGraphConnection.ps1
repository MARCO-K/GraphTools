function Initialize-GTGraphConnection
{
    <#
    .SYNOPSIS
        Ensures Microsoft Graph connection is established with required scopes
    .DESCRIPTION
        This internal helper function standardizes Graph connection handling across all GraphTools functions.
        It handles:
        - Optional disconnection of existing sessions
        - Checking for existing Graph context
        - Establishing new connection with specified scopes
        - Error handling and logging
    .PARAMETER Scopes
        Array of Microsoft Graph permission scopes required for the operation
    .PARAMETER NewSession
        If specified, disconnects any existing Graph session before connecting
    .PARAMETER SkipConnect
        If specified, only checks for existing context but doesn't establish new connection.
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
            Disconnect-MgGraph -ErrorAction SilentlyContinue
        }
        
        # Check for existing context
        $context = Get-MgContext
        
        if ($SkipConnect)
        {
            # Just return whether context exists
            return ($null -ne $context)
        }
        
        if (-not $context)
        {
            if (-not $Scopes)
            {
                Write-PSFMessage -Level Warning -Message 'No Microsoft Graph context found and no scopes provided.'
                return $false
            }
            
            Write-PSFMessage -Level Verbose -Message 'No Microsoft Graph context found. Attempting to connect.'
            Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop
            Write-PSFMessage -Level Verbose -Message "Successfully connected to Microsoft Graph with scopes: $($Scopes -join ', ')"
        }
        else
        {
            Write-PSFMessage -Level Verbose -Message "Using existing Microsoft Graph context. Current scopes: $($context.Scopes -join ', ')"
        }
        
        return $true
    }
    catch
    {
        Write-PSFMessage -Level Error -Message 'Failed to connect to Microsoft Graph.'
        throw "Graph connection failed: $_"
    }
}

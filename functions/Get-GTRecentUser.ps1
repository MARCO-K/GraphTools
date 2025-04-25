<#
.SYNOPSIS
    Retrieves user accounts created within a specified recent timeframe.

.DESCRIPTION
    This function queries Microsoft Entra ID to find user accounts whose 'createdDateTime'
    property falls within a defined period ending now. By default, it looks for users
    created in the last 24 hours.

    Requires the Microsoft.Graph.Users module.

.PARAMETER HoursAgo
    Specifies the lookback period in hours from the current time. Defaults to 24.

.OUTPUTS
    Microsoft.Graph.PowerShell.Models.IMicrosoftGraphUser
    Outputs the user objects found within the specified timeframe.

.EXAMPLE
    PS C:\> Get-GTRecentUser

    Retrieves users created in the last 24 hours.

.EXAMPLE
    PS C:\> Get-GTRecentUser -HoursAgo 72

    Retrieves users created in the last 72 hours (3 days).

.EXAMPLE
    PS C:\> Get-GTRecentUser -HoursAgo 1 | Select-Object UserPrincipalName, DisplayName, CreatedDateTime

    Retrieves users created in the last hour and displays specific properties.

.NOTES
    Ensure you have the necessary permissions (e.g., User.Read.All, AuditLog.Read.All)
    granted to the Microsoft Graph PowerShell application or the signed-in user.
    Querying the user directory directly is generally more efficient than filtering audit logs
    for this specific purpose if the 'createdDateTime' property suffices.
#>
function Get-GTRecentUser {
    [CmdletBinding()]
    [OutputType([Microsoft.Graph.PowerShell.Models.IMicrosoftGraphUser])]
    param (
        [Parameter(Mandatory = $false,
                   HelpMessage = 'Lookback period in hours from now. Defaults to 24.')]
        [ValidateRange(1, 8760)] # Limit to a reasonable range (1 hour to 1 year)
        [int]$HoursAgo = 24
    )

    Write-Verbose "Starting search for users created in the last $HoursAgo hours."

    # Ensure required module is available
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) {
        Write-Error "Required module 'Microsoft.Graph.Users' not found. Please install it first."
        return
    }

    # Check Graph connection status
    if (-not (Get-MgContext)) {
        Write-Warning "Not connected to Microsoft Graph. Attempting to connect."
        # Add connection logic here if desired, or rely on user being pre-connected.
        Write-Error "Please connect to Microsoft Graph first using Connect-MgGraph with appropriate scopes (e.g., User.Read.All)."
        return
    }

    # Calculate the cutoff time
    $cutoffDateTime = (Get-Date).AddHours(-$HoursAgo).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Verbose "Searching for users created on or after $cutoffDateTime"

    # Construct the filter query
    # Note: Filtering requires the ConsistencyLevel header and $count=true
    # See: https://docs.microsoft.com/en-us/graph/api/user-list?view=graph-rest-1.0&tabs=http#example-4-use-filter-and-orderby-in-the-same-query
    $filter = "createdDateTime ge $cutoffDateTime"

    try {
        Write-Verbose "Querying Microsoft Graph for users with filter: $filter"
        $recentUsers = Get-MgUser -Filter $filter -ConsistencyLevel eventual -CountVariable userCount -All
        Write-Verbose "Found $userCount users created in the last $HoursAgo hours."
    }
    catch {
        Write-Error "Failed to retrieve recent users. Error: $_"
        # Provide more specific error handling if possible (e.g., check for permissions)
        if ($_.Exception.Message -match "Authorization_RequestDenied") {
            Write-Warning "Permission denied. Ensure you have User.Read.All or Directory.Read.All."
        }
        return
    }

    Write-Verbose "Finished searching for recent users."
    return $recentUsers
}

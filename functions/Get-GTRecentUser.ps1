<#
.SYNOPSIS
    Retrieves user accounts created within a specified recent timeframe or by UPN.

.DESCRIPTION
    This function queries Microsoft Entra ID to find user accounts whose 'createdDateTime'
    property falls within a defined period ending now, or it retrieves a specific user by UPN.

    Requires the Microsoft.Graph.Users module.

.PARAMETER HoursAgo
    Specifies the lookback period in hours from the current time. Defaults to 24.

.PARAMETER UserPrincipalName
    The User Principal Name (UPN) of the user to retrieve.

.OUTPUTS
    Microsoft.Graph.PowerShell.Models.IMicrosoftGraphUser
    Outputs the user objects found.

.EXAMPLE
    PS C:\> Get-GTRecentUser

    Retrieves users created in the last 24 hours.

.EXAMPLE
    PS C:\> Get-GTRecentUser -HoursAgo 72

    Retrieves users created in the last 72 hours (3 days).

.EXAMPLE
    PS C:\> Get-GTRecentUser -UserPrincipalName "user@contoso.com"

    Retrieves the specified user.

.NOTES
    Ensure you have the necessary permissions (e.g., User.Read.All, AuditLog.Read.All)
    granted to the Microsoft Graph PowerShell application or the signed-in user.
#>
function Get-GTRecentUser {
    [CmdletBinding(DefaultParameterSetName = 'ByDate')]
    [OutputType([Microsoft.Graph.PowerShell.Models.IMicrosoftGraphUser])]
    param (
        [Parameter(Mandatory = $false,
                   ParameterSetName = 'ByDate',
                   HelpMessage = 'Lookback period in hours from now. Defaults to 24.')]
        [ValidateRange(1, 8760)] # Limit to a reasonable range (1 hour to 1 year)
        [int]$HoursAgo = 24,

        [Parameter(Mandatory = $true,
                   ParameterSetName = 'ByUPN')]
        [ValidateScript({$_ -match $script:GTValidationRegex.UPN})]
        [string]$UserPrincipalName
    )

    Write-Verbose "Starting search for users."

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

    try {
        if ($PSCmdlet.ParameterSetName -eq 'ByUPN') {
            Write-Verbose "Querying Microsoft Graph for user with UPN: $UserPrincipalName"
            $recentUsers = Get-MgUser -UserId $UserPrincipalName
            Write-Verbose "Found user with UPN: $UserPrincipalName"
        } else {
            # Calculate the cutoff time
            $cutoffDateTime = (Get-Date).AddHours(-$HoursAgo).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            Write-Verbose "Searching for users created on or after $cutoffDateTime"

            # Construct the filter query
            $filter = "createdDateTime ge $cutoffDateTime"
            Write-Verbose "Querying Microsoft Graph for users with filter: $filter"
            $recentUsers = Get-MgUser -Filter $filter -ConsistencyLevel eventual -CountVariable userCount -All
            Write-Verbose "Found $userCount users created in the last $HoursAgo hours."
        }
    }
    catch {
        Write-Error "Failed to retrieve users. Error: $_"
        # Provide more specific error handling if possible (e.g., check for permissions)
        if ($_.Exception.Message -match "Authorization_RequestDenied") {
            Write-Warning "Permission denied. Ensure you have User.Read.All or Directory.Read.All."
        }
        return
    }

    Write-Verbose "Finished searching for users."
    return $recentUsers
}
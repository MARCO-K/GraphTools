function Get-GTGuestUserReport {
    <#
    .SYNOPSIS
    Retrieves a report of all guest users with their invitation status.

    .DESCRIPTION
    This function retrieves guest users from Microsoft Entra ID and reports on their status,
    specifically focusing on whether they have accepted their invitation.

    .PARAMETER PendingOnly
    Switch to return only users who haven't accepted the invitation.

    .PARAMETER DaysSinceCreation
    Filter users created more than X days ago.

    .EXAMPLE
    Get-GTGuestUserReport -PendingOnly
    Returns all guest users who have not yet accepted their invitation.

    .EXAMPLE
    Get-GTGuestUserReport -DaysSinceCreation 30
    Returns all guest users created more than 30 days ago.

    .NOTES
    Requires Microsoft Graph PowerShell SDK with User.Read.All permission.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [switch]$PendingOnly,
        [int]$DaysSinceCreation
    )

    begin {
        $modules = @('Microsoft.Graph.Users')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        if (-not (Initialize-GTGraphConnection -Scopes 'User.Read.All')) {
            Write-Error "Failed to initialize Microsoft Graph connection."
            return
        }
    }

    process {
        try {
            Write-PSFMessage -Level Verbose -Message "Fetching guest users from Microsoft Graph..."
            
            # Filter for Guest users
            $filter = "userType eq 'Guest'"
            
            $params = @{
                All         = $true
                Filter      = $filter
                Property    = @('id', 'displayName', 'userPrincipalName', 'createdDateTime', 'externalUserState', 'externalUserStateChangeDateTime', 'signInActivity')
                ErrorAction = 'Stop'
            }

            $guests = Get-MgBetaUser @params

            Write-PSFMessage -Level Verbose -Message "Found $($guests.Count) guest users."

            foreach ($guest in $guests) {
                $daysCreated = if ($guest.CreatedDateTime) { (New-TimeSpan -Start $guest.CreatedDateTime -End (Get-Date)).Days } else { 0 }

                # Apply filters
                if ($PendingOnly -and $guest.ExternalUserState -ne 'PendingAcceptance') { continue }
                if ($PSBoundParameters.ContainsKey('DaysSinceCreation') -and $daysCreated -lt $DaysSinceCreation) { continue }

                [PSCustomObject]@{
                    Id                              = $guest.Id
                    DisplayName                     = $guest.DisplayName
                    UserPrincipalName               = $guest.UserPrincipalName
                    CreatedDateTime                 = $guest.CreatedDateTime
                    ExternalUserState               = $guest.ExternalUserState
                    ExternalUserStateChangeDateTime = $guest.ExternalUserStateChangeDateTime
                    LastSignInDateTime              = $guest.SignInActivity.LastSignInDateTime
                    DaysSinceCreation               = $daysCreated
                }
            }
        }
        catch {
            Stop-PSFFunction -Message "Failed to retrieve guest users: $($_.Exception.Message)" -ErrorRecord $_ -EnableException $true
        }
    }
}

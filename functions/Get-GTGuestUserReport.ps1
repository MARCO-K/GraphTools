function Get-GTGuestUserReport {
    <#
    .SYNOPSIS
    Retrieves a report of all guest users with their invitation status.

    .DESCRIPTION
    This function retrieves guest users from Microsoft Entra ID and reports on their status.
    It leverages server-side filtering for performance when querying pending users.
    
    It includes 'LastSignInDateTime' which requires AuditLog permissions.

    .PARAMETER PendingOnly
    Switch to return only users who haven't accepted the invitation.
    This uses a server-side filter for optimal performance.

    .PARAMETER DaysSinceCreation
    Filter users created more than X days ago.

    .EXAMPLE
    Get-GTGuestUserReport -PendingOnly
    Returns all guest users who have not yet accepted their invitation.
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

        # 1. Scopes Check
        # AuditLog.Read.All is required to populate the 'signInActivity' property reliably.
        $requiredScopes = @('User.Read.All', 'AuditLog.Read.All')
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet)) {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }
    }

    process {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        try {
            Write-PSFMessage -Level Verbose -Message "Fetching guest users from Microsoft Graph..."
            
            # 2. Build Dynamic Filter (Server-Side Optimization)
            # Base filter: Must be a Guest
            $filterParts = [System.Collections.Generic.List[string]]::new()
            $filterParts.Add("userType eq 'Guest'")

            # Optimization: If PendingOnly is requested, filter at the API level
            if ($PendingOnly) {
                $filterParts.Add("externalUserState eq 'PendingAcceptance'")
            }

            # Combine filters with 'and'
            $finalFilter = $filterParts -join ' and '
            
            Write-PSFMessage -Level Verbose -Message "Using Filter: $finalFilter"

            $params = @{
                All         = $true
                Filter      = $finalFilter
                Property    = @('id', 'displayName', 'userPrincipalName', 'createdDateTime', 'externalUserState', 'externalUserStateChangeDateTime', 'signInActivity')
                ErrorAction = 'Stop'
            }

            $guests = Get-MgBetaUser @params

            Write-PSFMessage -Level Verbose -Message "Found $($guests.Count) guest users."

            foreach ($guest in $guests) {
                # Calculate Age
                $daysCreated = if ($guest.CreatedDateTime) { (New-TimeSpan -Start $guest.CreatedDateTime -End (Get-Date)).Days } else { 0 }

                # Client-side Filter: DaysSinceCreation
                # (Date math is harder to do in OData filters, so we keep this client-side)
                if ($PSBoundParameters.ContainsKey('DaysSinceCreation') -and $daysCreated -lt $DaysSinceCreation) { continue }

                # Handle Null ExternalUserState (Common for old guests, implies 'Accepted')
                $status = if ([string]::IsNullOrEmpty($guest.ExternalUserState)) { 'Accepted' } else { $guest.ExternalUserState }

                $results.Add([PSCustomObject]@{
                        Id                              = $guest.Id
                        DisplayName                     = $guest.DisplayName
                        UserPrincipalName               = $guest.UserPrincipalName
                        CreatedDateTime                 = $guest.CreatedDateTime
                        ExternalUserState               = $status
                        ExternalUserStateChangeDateTime = $guest.ExternalUserStateChangeDateTime
                        LastSignInDateTime              = $guest.SignInActivity.LastSignInDateTime
                        DaysSinceCreation               = $daysCreated
                    })
            }

            return $results
        }
        catch {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'Guest User Report'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve guest users: $($err.Reason)"
            
            # Optional: Throw if you want to stop downstream pipeline
            # throw $err.ErrorMessage
        }
    }
}
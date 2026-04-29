function Get-GTGuestUserReport
{
    <#
    .SYNOPSIS
    Retrieves a report of all guest users with their invitation status.

    .DESCRIPTION
    This function retrieves guest users from Microsoft Entra ID and reports on their status.
    It leverages server-side filtering for performance when querying pending users.

    It includes LastSignInDateTime which requires AuditLog permissions.

    .PARAMETER PendingOnly
    Switch to return only users who haven't accepted the invitation.
    This uses a server-side filter for optimal performance.

    .PARAMETER DaysSinceCreation
    Filter users created more than X days ago.

    .EXAMPLE
    Get-GTGuestUserReport -PendingOnly
    Returns all guest users who have not yet accepted their invitation.
    
        .NOTES
            Requires the Microsoft Graph PowerShell SDK module: Microsoft.Graph.Authentication
            Required Graph scopes:
                - User.Read.All
                - AuditLog.Read.All (to populate signInActivity/LastSignInDateTime)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [switch]$PendingOnly,
        [ValidateRange(0, 36500)]
        [int]$DaysSinceCreation
    )

    begin
    {
        $modules = @('Microsoft.Graph.Authentication')
        $requiredScopes = @('User.Read.All', 'AuditLog.Read.All')

        if (-not (Initialize-GTBeginBlock -ModuleNames $modules -RequiredScopes $requiredScopes -ValidateScopes -ScopeValidationErrorMessage "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."))
        {
            return
        }
    }

    process
    {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
        $utcNow = Get-UTCTime

        try
        {
            Write-PSFMessage -Level Verbose -Message "Fetching guest users from Microsoft Graph..."
            
            # 2. Build Dynamic Filter (Server-Side Optimization)
            $filterParts = [System.Collections.Generic.List[string]]::new()
            $filterParts.Add("userType eq 'Guest'")

            if ($PendingOnly)
            {
                $filterParts.Add("externalUserState eq 'PendingAcceptance'")
            }

            $finalFilter = New-GTODataFilter -Clauses $filterParts
            
            Write-PSFMessage -Level Verbose -Message "Using Filter: $finalFilter"

            $selectFields = 'id,displayName,userPrincipalName,createdDateTime,externalUserState,externalUserStateChangeDateTime,signInActivity'
            $encodedSelect = [System.Uri]::EscapeDataString($selectFields)
            $encodedFilter = [System.Uri]::EscapeDataString($finalFilter)
            $nextUri = "/v1.0/users?`$select=$encodedSelect&`$filter=$encodedFilter&`$top=999"
            $guests = Invoke-GTGraphPagedRequest -Uri $nextUri

            Write-PSFMessage -Level Verbose -Message "Found $($guests.Count) guest users."

            foreach ($guest in $guests)
            {
                # 3. Date Math (UTC Fix)
                # Ensure we compare UTC to UTC to avoid timezone offset errors
                $daysCreated = 0
                if ($guest.CreatedDateTime)
                {
                    # Normalize to UTC regardless of original kind (string/DateTime/DateTimeOffset)
                    try
                    {
                        $createdUtc = ([DateTime]$guest.CreatedDateTime).ToUniversalTime()
                    }
                    catch
                    {
                        # Fallback: if cast fails, attempt parsing then ToUniversalTime
                        $createdUtc = [DateTime]::Parse($guest.CreatedDateTime).ToUniversalTime()
                    }

                    # Use TotalDays for consistency and floor to whole days
                    $daysCreated = [math]::Floor((New-TimeSpan -Start $createdUtc -End $utcNow).TotalDays)
                }

                # Client-side Filter: DaysSinceCreation
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
                        LastSignInDateTime              = if ($guest.SignInActivity -and $guest.SignInActivity.LastSignInDateTime) { $guest.SignInActivity.LastSignInDateTime } else { $null }
                        DaysSinceCreation               = $daysCreated
                    })
            }

            # 4. Pipeline Output
            # Output the array so PowerShell unrolls it, allowing for piping to Export-Csv etc.
            return $results.ToArray()
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'Guest User Report'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve guest users: $($err.Reason)"
        }
    }
}
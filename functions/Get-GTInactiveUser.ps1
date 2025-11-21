function Get-GTInactiveUser
{
    <#
    .SYNOPSIS
    Retrieves user accounts with advanced filtering options including inactivity days.

    .DESCRIPTION
    Retrieves users from Microsoft Entra ID.
    Leverages Server-Side Filtering (OData) for performance where possible.
    
    IMPORTANT: Requires 'AuditLog.Read.All' to access sign-in activity.

    .PARAMETER DisabledUsersOnly
    Filter for disabled user accounts (Server-Side Filter).

    .PARAMETER ExternalUsersOnly
    Filter for external users (Server-Side Filter: userType eq 'Guest').

    .PARAMETER NeverLoggedIn
    Filter for users with no login history.

    .PARAMETER InactiveDaysOlderThan
    Filter for users inactive for more than X days (Server-Side Filter).

    .EXAMPLE
    Get-GTInactiveUser -InactiveDaysOlderThan 90
    Finds users inactive for over 3 months (efficiently).

    .NOTES
    - Requires Microsoft Graph PowerShell SDK modules: Microsoft.Graph.Authentication and Microsoft.Graph.Beta.Users
    - Required Graph scopes: User.Read.All and AuditLog.Read.All (AuditLog.Read.All is required to populate sign-in activity)
    - DaysInactive is returned as an integer number of days (floor of total days) when a last sign-in timestamp exists.
      Users who have never signed in will have DaysInactive set to $null.
    - The -NewSession switch forces a fresh Graph connection by calling Initialize-GTGraphConnection -NewSession.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [switch]$DisabledUsersOnly,
        [switch]$ExternalUsersOnly,
        [switch]$NeverLoggedIn,
        
        [ValidateRange(1, 36500)]
        [int]$InactiveDaysOlderThan,

        [switch]$NewSession
    )

    begin
    {
        # Module Management
        $modules = ('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Users')
        Install-GTRequiredModule -ModuleNames $modules -Verbose

        # 1. Scopes Check (Gold Standard)
        # AuditLog.Read.All is MANDATORY for signInActivity. Without it, the property is null.
        $requiredScopes = @('User.Read.All', 'AuditLog.Read.All')
        
        # Allow callers to request a fresh session and ensure Graph connection with required scopes
        if ($NewSession) { Write-PSFMessage -Level Verbose -Message "NewSession requested: attempting reconnection." }

        $connected = Initialize-GTGraphConnection -Scopes $requiredScopes -NewSession:$NewSession
        if (-not $connected)
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }
    }

    process
    {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
        $utcNow = Get-UTCTime

        try
        {
            Write-PSFMessage -Level Verbose -Message "Preparing Microsoft Graph query..."
            
            # 2. Build Dynamic Server-Side Filter (Optimization)
            $filterParts = [System.Collections.Generic.List[string]]::new()

            # A. Filter Disabled
            if ($DisabledUsersOnly)
            {
                $filterParts.Add("accountEnabled eq false")
            }

            # B. Filter Guests (External)
            if ($ExternalUsersOnly)
            {
                $filterParts.Add("userType eq 'Guest'")
            }

            # C. Filter Inactive Date
            # This is the huge performance win. We calculate the date and ask Graph to filter it.
            if ($PSBoundParameters.ContainsKey('InactiveDaysOlderThan'))
            {
                $thresholdDate = $utcNow.AddDays(-$InactiveDaysOlderThan)
                $filterDateStr = $thresholdDate.ToString('yyyy-MM-ddTHH:mm:ssZ')
                
                # Note: This filter implicitly excludes users who have NEVER signed in (null dates).
                # Use an unquoted DateTimeOffset literal for OData (e.g. 2023-01-01T00:00:00Z)
                $filterParts.Add("signInActivity/lastSignInDateTime le $filterDateStr")
            }

            $finalFilter = $filterParts -join ' and '
            if (-not [string]::IsNullOrWhiteSpace($finalFilter))
            {
                Write-PSFMessage -Level Verbose -Message "Using OData Filter: $finalFilter"
            }

            $params = @{
                All         = $true
                Property    = @(
                    'displayName', 'id', 'accountEnabled', 'userPrincipalName', 
                    'createdDateTime', 'userType', 'signInActivity', 
                    'refreshTokensValidFromDateTime'
                )
                ErrorAction = 'Stop'
            }
            
            if (-not [string]::IsNullOrWhiteSpace($finalFilter))
            {
                $params['Filter'] = $finalFilter
            }

            # Execute Query
            $users = Get-MgBetaUser @params

            $userCount = if ($users) { $users.Count } else { 0 }
            Write-PSFMessage -Level Verbose -Message "Processing $userCount users..."

            foreach ($user in $users)
            {
                $signinActivity = $user.SignInActivity

                # 3. Calculate Max Date (UTC)
                # We look at all available sign-in timestamps to find the most recent one
                $loginDates = @()
                if ($signinActivity)
                {
                    if ($signinActivity.LastSignInDateTime) { $loginDates += $signinActivity.LastSignInDateTime }
                    if ($signinActivity.LastSuccessfulSignInDateTime) { $loginDates += $signinActivity.LastSuccessfulSignInDateTime }
                    if ($signinActivity.LastNonInteractiveSignInDateTime) { $loginDates += $signinActivity.LastNonInteractiveSignInDateTime }
                }

                $maxDate = if ($loginDates.Count -gt 0) { ($loginDates | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum) } else { $null }

                # 4. Handle 'Never Logged In' Logic
                if ($NeverLoggedIn)
                {
                    # If user has a date, they HAVE logged in, so skip them
                    if ($maxDate) { continue }
                }
                else
                {
                    # If we are NOT looking for 'Never Logged In', and the user has NO date,
                    # we usually treat them as "Infinite Inactivity".
                    # However, if InactiveDaysOlderThan was used, the server filter already excluded them.
                }

                # Calculate Days Inactive
                # Use $null to represent 'never signed in' for type consistency
                $daysInactive = $null
                if ($maxDate)
                {
                    try
                    {
                        $maxDateUtc = ([DateTime]$maxDate).ToUniversalTime()
                        $daysInactive = [math]::Floor((New-TimeSpan -Start $maxDateUtc -End $utcNow).TotalDays)
                    }
                    catch
                    {
                        # If parsing fails, leave as $null
                        $daysInactive = $null
                    }
                }

                # Client-Side Double Check (Optional but good for edge cases)
                if ($PSBoundParameters.ContainsKey('InactiveDaysOlderThan') -and $null -ne $daysInactive -and $daysInactive -lt $InactiveDaysOlderThan)
                {
                    continue
                }

                $results.Add([PSCustomObject]@{
                        DisplayName                      = $user.DisplayName
                        UserPrincipalName                = $user.UserPrincipalName
                        Id                               = $user.Id
                        AccountEnabled                   = $user.AccountEnabled
                        UserType                         = $user.UserType
                        DaysInactive                     = $daysInactive
                        LastSignInDateTime               = if ($signinActivity) { $signinActivity.LastSignInDateTime } else { $null }
                        LastSuccessfulSignInDateTime     = if ($signinActivity) { $signinActivity.LastSuccessfulSignInDateTime } else { $null }
                        LastNonInteractiveSignInDateTime = if ($signinActivity) { $signinActivity.LastNonInteractiveSignInDateTime } else { $null }
                        CreatedDateTime                  = $user.CreatedDateTime
                    })
            }

            # Output result array
            return $results.ToArray()
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'User Report'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve users: $($err.Reason)"
        }
    }
}

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

    .PARAMETER ExcludeUPN
    Exclude specific user principal names from the output.

    .PARAMETER ExcludeGlobalAdministrators
    Exclude members of the Global Administrator role from the output.
    If role membership cannot be resolved, the command fails to avoid unsafe cleanup actions.

    .PARAMETER IncludeSignInOnlyRecords
    Include Graph sign-in activity artifacts that have an Id and sign-in timestamps but no resolvable user profile fields.
    By default, these records are excluded to keep cleanup candidate output actionable.

    .EXAMPLE
    Get-GTInactiveUser -InactiveDaysOlderThan 90
    Finds users inactive for over 3 months (efficiently).

    .EXAMPLE
    Get-GTInactiveUser -InactiveDaysOlderThan 90 -ExcludeUPN 'breakglass@contoso.com'
    Finds users inactive for over 3 months, excluding protected accounts.

    .EXAMPLE
    Get-GTInactiveUser -InactiveDaysOlderThan 90 -ExcludeGlobalAdministrators
    Finds users inactive for over 3 months, excluding Global Administrator members.

    .NOTES
        - Requires Microsoft Graph PowerShell SDK module: Microsoft.Graph.Authentication
        - Required Graph scopes: User.Read.All and AuditLog.Read.All (AuditLog.Read.All is required to populate sign-in activity)
            Add Directory.Read.All when using -ExcludeGlobalAdministrators.
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

        [Alias('ExcludedUPN', 'SkipUPN', 'ProtectedUPN')]
        [string[]]$ExcludeUPN,

        [switch]$ExcludeGlobalAdministrators,

        [switch]$IncludeSignInOnlyRecords,

        [switch]$NewSession
    )

    begin
    {
        $modules = ('Microsoft.Graph.Authentication')
        $requiredScopes = @('User.Read.All', 'AuditLog.Read.All')
        if ($ExcludeGlobalAdministrators)
        {
            $requiredScopes += 'Directory.Read.All'
        }

        if (-not (Initialize-GTBeginBlock -ModuleNames $modules -RequiredScopes $requiredScopes -InitializeConnection -ValidateScopes -NewSession:$NewSession -ScopeValidationErrorMessage "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."))
        {
            return
        }
    }

    process
    {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
        $utcNow = Get-UTCTime
        $signInOnlyRecordsSkipped = 0
        $excludedUpnSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($ExcludeUPN)
        {
            foreach ($upn in $ExcludeUPN)
            {
                if (-not [string]::IsNullOrWhiteSpace($upn))
                {
                    [void]$excludedUpnSet.Add($upn.Trim())
                }
            }
            Write-PSFMessage -Level Verbose -Message "Excluding $($excludedUpnSet.Count) UPN value(s) from results."
        }

        $excludedGlobalAdminIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $excludedGlobalAdminUpns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        try
        {
            if ($ExcludeGlobalAdministrators)
            {
                $globalAdminTemplateId = '62e90394-69f5-4237-9190-012177145e10'
                $encodedRoleFilter = [System.Uri]::EscapeDataString("roleTemplateId eq '$globalAdminTemplateId'")
                $directoryRoleUri = "/v1.0/directoryRoles?`$filter=$encodedRoleFilter"
                $directoryRoleResponse = Invoke-MgGraphRequest -Method GET -Uri $directoryRoleUri -ErrorAction Stop
                $globalAdminRole = $null
                if ($directoryRoleResponse -and $directoryRoleResponse.value)
                {
                    $globalAdminRole = $directoryRoleResponse.value | Select-Object -First 1
                }

                if ($globalAdminRole -and $globalAdminRole.id)
                {
                    $membersUri = "/v1.0/directoryRoles/$($globalAdminRole.id)/members?`$select=id,userPrincipalName"
                    $membersResponse = Invoke-MgGraphRequest -Method GET -Uri $membersUri -ErrorAction Stop
                    $roleMembers = if ($membersResponse -and $membersResponse.value) { $membersResponse.value } else { @() }
                    foreach ($member in $roleMembers)
                    {
                        if ($member.id)
                        {
                            [void]$excludedGlobalAdminIds.Add([string]$member.id)
                        }
                        if ($member.userPrincipalName)
                        {
                            [void]$excludedGlobalAdminUpns.Add([string]$member.userPrincipalName)
                        }
                    }

                    Write-PSFMessage -Level Verbose -Message "Excluding $($excludedGlobalAdminIds.Count) Global Administrator member(s) from results."
                }
                else
                {
                    Write-PSFMessage -Level Verbose -Message 'Global Administrator role not active in tenant. No role-based exclusions applied.'
                }
            }

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
                $filterDateStr = Format-ODataDateTime -DateTime $thresholdDate
                
                # Note: This filter implicitly excludes users who have NEVER signed in (null dates).
                # Use an unquoted DateTimeOffset literal for OData (e.g. 2023-01-01T00:00:00Z)
                $filterParts.Add("signInActivity/lastSignInDateTime le $filterDateStr")
            }

            $finalFilter = New-GTODataFilter -Clauses $filterParts
            if (-not [string]::IsNullOrWhiteSpace($finalFilter))
            {
                Write-PSFMessage -Level Verbose -Message "Using OData Filter: $finalFilter"
            }

            $selectFields = 'displayName,id,accountEnabled,userPrincipalName,createdDateTime,userType,signInActivity,refreshTokensValidFromDateTime'
            $encodedSelect = [System.Uri]::EscapeDataString($selectFields)
            $usersUri = "/v1.0/users?`$select=$encodedSelect&`$top=500"
            if (-not [string]::IsNullOrWhiteSpace($finalFilter))
            {
                $encodedFilter = [System.Uri]::EscapeDataString($finalFilter)
                $usersUri += "&`$filter=$encodedFilter"
            }

            # Execute query via shared paging helper
            $users = Invoke-GTGraphPagedRequest -Uri $usersUri

            $userCount = if ($users) { $users.Count } else { 0 }
            Write-PSFMessage -Level Verbose -Message "Processing $userCount users..."

            foreach ($user in $users)
            {
                # Graph can return sign-in-only artifacts that contain Id + SignInActivity but no resolvable user profile fields.
                # These are not actionable user objects for cleanup workflows, so exclude them unless explicitly requested.
                $hasProfileData =
                    -not [string]::IsNullOrWhiteSpace([string]$user.UserPrincipalName) -or
                    -not [string]::IsNullOrWhiteSpace([string]$user.DisplayName) -or
                    -not [string]::IsNullOrWhiteSpace([string]$user.UserType) -or
                    ($null -ne $user.CreatedDateTime) -or
                    ($null -ne $user.AccountEnabled)

                if (-not $IncludeSignInOnlyRecords -and -not $hasProfileData)
                {
                    $signInOnlyRecordsSkipped++
                    continue
                }

                if ($user.UserPrincipalName -and $excludedUpnSet.Contains([string]$user.UserPrincipalName))
                {
                    continue
                }

                if ($ExcludeGlobalAdministrators)
                {
                    if (($user.Id -and $excludedGlobalAdminIds.Contains([string]$user.Id)) -or
                        ($user.UserPrincipalName -and $excludedGlobalAdminUpns.Contains([string]$user.UserPrincipalName)))
                    {
                        continue
                    }
                }

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
            if ($signInOnlyRecordsSkipped -gt 0)
            {
                Write-PSFMessage -Level Verbose -Message "Skipped $signInOnlyRecordsSkipped sign-in-only record(s) without resolvable user profile fields. Use -IncludeSignInOnlyRecords to include them."
            }

            return $results.ToArray()
        }
        catch
        {
            if ($ExcludeGlobalAdministrators)
            {
                Write-Error "Failed to resolve Global Administrator membership for exclusion: $($_.Exception.Message)"
                return
            }

            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'User Report'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve users: $($err.Reason)"
        }
    }
}

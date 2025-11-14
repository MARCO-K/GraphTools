function Get-GTInactiveUser
{
    <#
    .SYNOPSIS
    Retrieves user accounts with advanced filtering options including inactivity days.

    .DESCRIPTION
    Enhanced version with PSFramework logging, pipeline-friendly structure, and additional filters.

    .PARAMETER DisabledUsersOnly
    Filter for disabled user accounts

    .PARAMETER ExternalUsersOnly
    Filter for external users (Guests or #EXT# accounts)

    .PARAMETER NeverLoggedIn
    Filter for users with no login history

    .PARAMETER InactiveDaysOlderThan
    Filter for users inactive for more than X days

    .PARAMETER NewSession
    Switch to force a new Graph session

    .PARAMETER Scope
    Scopes for Graph Connection. Default includes User.Read.All and AuditLog.Read.All

    .EXAMPLE
    Get-GTInactiveUser -InactiveDaysOlderThan 90 -Verbose
    Finds users inactive for over 3 months with verbose logging

    .EXAMPLE
    Get-GTInactiveUser -ExternalUsersOnly -DisabledUsersOnly -Debug
    Debugs disabled external user processing

    .EXAMPLE
    Get-GTInactiveUser -NeverLoggedIn
    Retrieves all users who have never logged in

    .EXAMPLE
    Get-GTInactiveUser -InactiveDaysOlderThan 30 -DisabledUsersOnly
    Gets disabled users who have been inactive for more than 30 days

    .NOTES
    Requires Microsoft Graph PowerShell SDK with appropriate permissions:
    - User.Read.All
    - AuditLog.Read.All (for sign-in activity)
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [switch]$DisabledUsersOnly,
        [switch]$ExternalUsersOnly,
        [switch]$NeverLoggedIn,
        [ValidateRange(1, [int]::MaxValue)]
        [int]$InactiveDaysOlderThan,

        # Switch to force a new Graph session
        [switch]$NewSession,

        # Scopes for Graph Connection
        [string[]]$Scope = @('User.Read.All', 'AuditLog.Read.All')
    )

    begin
    {
        # Module Management
        $modules = ('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Users')
        Install-GTRequiredModule -ModuleNames $modules -Verbose

        # Graph Connection Handling
        $graphConnected = Initialize-GTGraphConnection -Scopes 'User.Read.All'
        if (-not $graphConnected) {
            Write-Error "Failed to initialize Microsoft Graph connection. Aborting Get-GTInactiveUser."
            return
        }
    }

    process
    {
        try
        {
            Write-PSFMessage -Level Verbose -Message "Fetching users from Microsoft Graph"
            $users = Get-MgBetaUser -All -Property @(
                'displayName', 'id', 'accountEnabled', 'userPrincipalName',
                'createdDateTime', 'userType', 'signinActivity',
                'RefreshTokensValidFromDateTime', 'AuthorizationInfo'
            ) -ErrorAction Stop
        }
        catch
        {
            # Use centralized error handling helper to parse Graph API exceptions
            $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'user'
            
            # Log appropriate message based on error details
            if ($errorDetails.HttpStatus -in 404, 403) {
                Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to retrieve users - $($errorDetails.Reason)"
                Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
            }
            elseif ($errorDetails.HttpStatus) {
                Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to retrieve users - $($errorDetails.Reason)"
            }
            else {
                Write-PSFMessage -Level Error -Message "Failed to retrieve users. $($errorDetails.ErrorMessage)"
            }
            Stop-PSFFunction -Message $errorDetails.Reason -EnableException $true
        }

        Write-PSFMessage -Level Debug -Message "Processing $($users.Count) users"

        $allUsers = foreach ($user in $users)
        {
            $signinActivity = $user.signinActivity

            # Calculate dates once for reuse
            $loginDates = @(
                $signinActivity.LastSignInDateTime
                $signinActivity.LastSuccessfulSignInDateTime
                $signinActivity.LastNonInteractiveSignInDateTime
            ) | Where-Object { $_ -ne $null }

            $maxDate = if ($loginDates.Count -gt 0)
            {
                $loginDates | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
            }

            [PSCustomObject]@{
                displayName                      = $user.displayName
                id                               = $user.id
                accountEnabled                   = $user.accountEnabled
                userPrincipalName                = $user.userPrincipalName
                createdDateTime                  = $user.createdDateTime
                userType                         = $user.userType
                RefreshTokenValidFrom            = $user.RefreshTokensValidFromDateTime
                LastSuccessfulSignInDateTime     = $signinActivity.LastSuccessfulSignInDateTime
                LastNonInteractiveSignInDateTime = $signinActivity.LastNonInteractiveSignInDateTime
                LastSignInDateTime               = $signinActivity.LastSignInDateTime
                MaxDate                          = $maxDate
                InactiveDays                     = if ($maxDate)
                {
                    (New-TimeSpan -Start $maxDate -End (Get-Date)).Days
                }
                else { 0 }
            }
        }
    }

    end
    {
        try
        {
            Write-PSFMessage -Level Verbose -Message "Applying filters to $($allUsers.Count) processed users"

            # Filter directly on array - no need for list conversion just for filtering
            $filteredUsers = $allUsers | Where-Object {
                # NeverLoggedIn condition
                (-not $NeverLoggedIn -or (-not $_.MaxDate)) -and

                # DisabledUsersOnly condition
                (-not $DisabledUsersOnly -or ($_.accountEnabled -eq $false)) -and

                # ExternalUsersOnly condition
                (-not $ExternalUsersOnly -or (
                    $_.userType -eq 'Guest' -or
                    $_.userPrincipalName -like '*#EXT#*'
                )) -and

                # InactiveDays filter
                (-not $PSBoundParameters.ContainsKey('InactiveDaysOlderThan') -or
                $_.InactiveDays -ge $InactiveDaysOlderThan)
            }

            Write-PSFMessage -Level Verbose -Message "Found $($filteredUsers.Count) matching users"
            $filteredUsers
        }
        catch
        {
            Stop-PSFFunction -Message "Filtering failed" -ErrorRecord $_ -EnableException $true
        }
    }
}
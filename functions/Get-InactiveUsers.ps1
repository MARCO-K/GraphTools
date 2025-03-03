function Get-InactiveUsers
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
    
    .EXAMPLE
    Get-InactiveUsers -InactiveDaysOlderThan 90 -Verbose
    Finds users inactive for over 3 months with verbose logging
    
    .EXAMPLE
    Get-InactiveUsers -ExternalUsersOnly -DisabledUsersOnly -Debug
    Debugs disabled external user processing
    #>
    [CmdletBinding()]
    param(
        [switch]$DisabledUsersOnly,
        [switch]$ExternalUsersOnly,
        [switch]$NeverLoggedIn,
        [ValidateRange(1, [int]::MaxValue)]
        [int]$InactiveDaysOlderThan
    )

    begin
    {
        # Module Management
        $modules = ('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Users')
        Install-GTRequiredModule -ModuleNames $modules -Verbose

        # Graph Connection Handling
        try
        {
            if ($NewSession) 
            { 
                Write-PSFMessage -Level 'Verbose' -Message 'Close existing Microsoft Graph session.'
                Disconnect-MgGraph -ErrorAction SilentlyContinue 
            }
            
            $context = Get-MgContext
            if (-not $context)
            {
                Write-PSFMessage -Level 'Verbose' -Message 'No Microsoft Graph context found. Attempting to connect.'
                Connect-MgGraph -Scopes $Scope -NoWelcome -ErrorAction Stop
            }
        }
        catch
        {
            Write-PSFMessage -Level 'Error' -Message 'Failed to connect to Microsoft Graph.'
            throw "Graph connection failed: $_"
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
            Stop-PSFFunction -Message "Failed to retrieve users" -ErrorRecord $_ -EnableException $true
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
            
            # Convert to List for better performance
            $userList = [System.Collections.Generic.List[object]]::new()
            $userList.AddRange($allUsers)

            $filteredUsers = $userList | Where-Object {
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
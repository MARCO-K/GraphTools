function Get-GTRecentUser
{
    <#
    .SYNOPSIS
    Retrieves user accounts created within a specified recent timeframe or by UPN.

    .DESCRIPTION
    This function queries Microsoft Entra ID to find user accounts whose 'createdDateTime'
    property falls within a defined period ending now, or it retrieves a specific user by UPN.

    It uses Server-Side filtering for performance.

    .PARAMETER HoursAgo
    Specifies the lookback period in hours from the current time. Defaults to 24.

    .PARAMETER UserPrincipalName
    The User Principal Name (UPN) of the user to retrieve.
    Aliases: UPN, UserName, UPNName

    .EXAMPLE
    Get-GTRecentUser -HoursAgo 72
    Retrieves users created in the last 3 days.

    .EXAMPLE
    Get-GTRecentUser -UPN "user@contoso.com"
    Retrieves the specified user.

    .EXAMPLE
    Get-GTRecentUser -HoursAgo 24 -Verbose
    Retrieves users created in the last 24 hours with verbose logging.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByDate')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false, ParameterSetName = 'ByDate', HelpMessage = 'Lookback period in hours.')]
        [ValidateRange(1, 8760)] # 1 hour to 1 year
        [int]$HoursAgo = 24,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByUPN', ValueFromPipeline = $true)]
        [ValidateScript({ $_ -match $script:GTValidationRegex.UPN })]  # Validates UPN format using regex
        [Alias('UPN', 'UserName', 'UPNName')]
        [string]$UserPrincipalName,

        [switch]$NewSession
    )

    begin
    {
        $modules = @('Microsoft.Graph.Users')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        # 1. Scopes Check (Gold Standard)
        # User.Read.All is required to read CreatedDateTime and filter users
        $requiredScopes = @('User.Read.All')
        
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet))
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }

        # 2. Connection Initialization
        if (-not (Initialize-GTGraphConnection -Scopes $requiredScopes -NewSession:$NewSession))
        {
            Write-Error "Failed to initialize session."
            return
        }
    }

    process
    {
        try
        {
            $results = [System.Collections.Generic.List[PSCustomObject]]::new()
            $utcNow = (Get-Date).ToUniversalTime()

            if ($PSCmdlet.ParameterSetName -eq 'ByUPN')
            {
                Write-PSFMessage -Level Verbose -Message "Querying Microsoft Graph for user: $UserPrincipalName"
                
                # Fetch single user
                $users = @(Get-MgUser -UserId $UserPrincipalName -Property Id, DisplayName, UserPrincipalName, CreatedDateTime, AccountEnabled, UserType -ErrorAction Stop)
            }
            else
            {
                # Calculate cutoff (UTC)
                $cutoffDateTime = $utcNow.AddHours(-$HoursAgo)
                $filterDateStr = Format-ODataDateTime -DateTime $cutoffDateTime
                
                Write-PSFMessage -Level Verbose -Message "Searching for users created after $filterDateStr"

                # Construct Server-Side Filter
                # Note: createdDateTime is a DateTimeOffset, filter uses unquoted date for 'ge' operator
                $filter = "createdDateTime ge $filterDateStr"
                
                Write-PSFMessage -Level Verbose -Message "Using OData Filter: $filter"
                
                # Fetch users with filter
                # -ConsistencyLevel eventual is often required for complex filters, though createdDateTime usually works without it. Added for safety.
                $users = Get-MgUser -Filter $filter -ConsistencyLevel eventual -CountVariable userCount -All -Property Id, DisplayName, UserPrincipalName, CreatedDateTime, AccountEnabled, UserType -ErrorAction Stop
                
                Write-PSFMessage -Level Verbose -Message "Found $userCount users."
            }

            foreach ($user in $users)
            {
                # Calculate age friendly string
                $age = "Unknown"
                if ($user.CreatedDateTime)
                {
                    $span = New-TimeSpan -Start $user.CreatedDateTime -End $utcNow
                    if ($span.TotalHours -lt 24)
                    {
                        $age = "{0:N1} Hours" -f $span.TotalHours
                    }
                    else
                    {
                        $age = "{0:N1} Days" -f $span.TotalDays
                    }
                }

                $results.Add([PSCustomObject]@{
                        Id                = $user.Id
                        DisplayName       = $user.DisplayName
                        UserPrincipalName = $user.UserPrincipalName
                        CreatedDateTime   = $user.CreatedDateTime
                        Age               = $age
                        AccountEnabled    = $user.AccountEnabled
                        UserType          = $user.UserType
                    })
            }

            Write-PSFMessage -Level Verbose -Message "Returning $($results.Count) users."

            return $results.ToArray()
        }
        catch
        {
            # 3. Gold Standard Error Handling
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'User'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve recent users: $($err.Reason)"
            
            throw $err.ErrorMessage
        }
    }
}
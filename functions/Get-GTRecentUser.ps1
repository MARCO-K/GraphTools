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
        $modules = @('Microsoft.Graph.Authentication')
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
            $utcNow = Get-UTCTime

            if ($PSCmdlet.ParameterSetName -eq 'ByUPN')
            {
                Write-PSFMessage -Level Verbose -Message "Querying Microsoft Graph for user: $UserPrincipalName"
                
                # Fetch single user
                $resp = Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/$UserPrincipalName?`$select=id,displayName,userPrincipalName,createdDateTime,accountEnabled,userType" -ErrorAction Stop
                $users = @([PSCustomObject]@{ id = $resp.id; displayName = $resp.displayName; userPrincipalName = $resp.userPrincipalName; createdDateTime = $resp.createdDateTime; accountEnabled = $resp.accountEnabled; userType = $resp.userType })
            }
            else
            {
                # Calculate cutoff (UTC)
                $cutoffDateTime = $utcNow.AddHours(-$HoursAgo)
                $filterDateStr = Format-ODataDateTime -DateTime $cutoffDateTime
                
                Write-PSFMessage -Level Verbose -Message "Searching for users created after $filterDateStr"

                # Construct Server-Side Filter
                $filter = "createdDateTime ge $filterDateStr"
                
                Write-PSFMessage -Level Verbose -Message "Using OData Filter: $filter"
                
                # Fetch users with filter; ConsistencyLevel eventual needed for $count and createdDateTime filter
                $users = Invoke-GTGraphPagedRequest -Uri "v1.0/users?`$filter=$([Uri]::EscapeDataString($filter))&`$select=id,displayName,userPrincipalName,createdDateTime,accountEnabled,userType&`$count=true" -Headers @{ ConsistencyLevel = 'eventual' }
                
                Write-PSFMessage -Level Verbose -Message "Found $($users.Count) users."
            }

            foreach ($user in $users)
            {
                # Calculate age friendly string
                $age = "Unknown"
                if ($user.createdDateTime)
                {
                    $span = New-TimeSpan -Start $user.createdDateTime -End $utcNow
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
                        Id                = $user.id
                        DisplayName       = $user.displayName
                        UserPrincipalName = $user.userPrincipalName
                        CreatedDateTime   = $user.createdDateTime
                        Age               = $age
                        AccountEnabled    = $user.accountEnabled
                        UserType          = $user.userType
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
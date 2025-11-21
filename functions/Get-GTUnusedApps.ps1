function Get-GTUnusedApps
{
    <#
    .SYNOPSIS
    Identifies Service Principals that have not had any sign-ins for a specified period.

    .DESCRIPTION
    This function retrieves Service Principals and analyzes their sign-in activity.
    
    PERFORMANCE:
    - By default, uses Server-Side filtering for high performance.
    - If -IncludeNeverUsed is specified, it performs a full directory scan (slower).

    .PARAMETER DaysSinceLastSignIn
    The number of days of inactivity to check for.

    .PARAMETER IncludeNeverUsed
    Switch to include apps that have never had a recorded sign-in.
    WARNING: Using this switch forces a full download of all Service Principals.

    .EXAMPLE
    Get-GTUnusedApps -DaysSinceLastSignIn 90
    Fast. Finds apps inactive for more than 90 days.

    .EXAMPLE
    Get-GTUnusedApps -DaysSinceLastSignIn 90 -IncludeNeverUsed
    Slower. Finds inactive apps AND apps that have never logged in.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$DaysSinceLastSignIn,

        [switch]$IncludeNeverUsed,
        [switch]$NewSession
    )

    begin
    {
        $modules = @('Microsoft.Graph.Beta.Applications')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        # 1. Scopes Check (Gold Standard)
        # Application.Read.All is required to list SPs. AuditLog.Read.All is required for signInActivity.
        $requiredScopes = @('Application.Read.All', 'AuditLog.Read.All')
        
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
        $utcNow = (Get-Date).ToUniversalTime()
        $thresholdDate = $utcNow.AddDays(-$DaysSinceLastSignIn)
        
        # Format for OData: yyyy-MM-ddTHH:mm:ssZ
        $filterDateString = $thresholdDate.ToString('yyyy-MM-ddTHH:mm:ssZ')

        try
        {
            $params = @{
                All         = $true
                Property    = @('id', 'appId', 'displayName', 'signInActivity')
                ErrorAction = 'Stop'
            }

            # 3. Hybrid Filtering Strategy
            if ($IncludeNeverUsed)
            {
                Write-PSFMessage -Level Verbose -Message "Fetching ALL Service Principals (IncludeNeverUsed active)..."
                # No filter - we must scan everything to find nulls
            }
            else
            {
                # Optimization: Server-Side Filter
                Write-PSFMessage -Level Verbose -Message "Fetching inactive Service Principals (Server-Side Filter)..."
                $params['Filter'] = "signInActivity/lastSignInDateTime le $filterDateString"
                Write-PSFMessage -Level Verbose -Message "Using Filter: $($params['Filter'])"
            }

            # 4. Pipeline Streaming
            Get-MgBetaServicePrincipal @params | ForEach-Object {
                $sp = $_
                $lastSignIn = $sp.SignInActivity.LastSignInDateTime
                
                # Logic A: App has signed in, check if it's old
                if ($lastSignIn)
                {
                    # Note: If we used the Server-Side filter, we technically don't need to check dates again,
                    # but it doesn't hurt to double-check, especially if IncludeNeverUsed triggered a full scan.
                    
                    # Ensure we parse UTC correctly
                    $lastSignInUtc = $lastSignIn
                    if ($lastSignIn -is [string]) { $lastSignInUtc = [DateTime]::Parse($lastSignIn) }
                    
                    $daysInactive = (New-TimeSpan -Start $lastSignInUtc -End $utcNow).Days

                    if ($daysInactive -ge $DaysSinceLastSignIn)
                    {
                        [PSCustomObject]@{
                            DisplayName        = $sp.DisplayName
                            AppId              = $sp.AppId
                            Id                 = $sp.Id
                            LastSignInDateTime = $lastSignIn
                            DaysInactive       = $daysInactive
                            Status             = 'Inactive'
                        }
                    }
                }
                # Logic B: App has NEVER signed in
                elseif ($IncludeNeverUsed)
                {
                    [PSCustomObject]@{
                        DisplayName        = $sp.DisplayName
                        AppId              = $sp.AppId
                        Id                 = $sp.Id
                        LastSignInDateTime = $null
                        DaysInactive       = 'Never'
                        Status             = 'Never Used'
                    }
                }
            }
        }
        catch
        {
            # Gold Standard Error Handling
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'Service Principals'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve unused apps: $($err.Reason)"
            
            throw $err.ErrorMessage
        }
    }
}

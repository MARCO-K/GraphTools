function Get-GTInactiveDevices
{
    <#
    .SYNOPSIS
    Retrieves devices that have not signed in for a specified number of days.

    .DESCRIPTION
    This function retrieves devices from Microsoft Entra ID.
    It uses OData server-side filtering to efficiently retrieve only devices that meet the inactivity criteria.

    .PARAMETER InactiveDays
    The number of days of inactivity to check for.

    .PARAMETER DeviceType
    Optional filter for specific operating systems (e.g., 'Windows', 'iOS').
    This uses an exact match ('eq') server-side filter.

    .PARAMETER IncludeDisabled
    Switch to include devices that are already disabled. By default, only enabled devices are returned.

    .EXAMPLE
    Get-GTInactiveDevices -InactiveDays 90
    Finds all enabled devices inactive for more than 90 days.
    
    .NOTES
    Requires the Microsoft Graph PowerShell SDK (Microsoft.Graph.Identity.DirectoryManagement) and the
    Graph scope: Device.Read.All. The function uses server-side OData filtering for efficiency.
    DaysInactive will be an integer number of days (floor of total days) when a last sign-in
    timestamp exists in Graph; when the device has never signed in, DaysInactive will be $null.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 36500)]
        [int]$InactiveDays,

        [string]$DeviceType,

        [switch]$IncludeDisabled
    )

    begin
    {
        $modules = @('Microsoft.Graph.Identity.DirectoryManagement')
        # Prefer the standard -Verbose switch; do not pass $VerbosePreference to a switch parameter
        Install-GTRequiredModule -ModuleNames $modules -Verbose

        # 1. Scopes Check
        $requiredScopes = @('Device.Read.All')
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet))
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }
    }

    process
    {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
        
        # 2. Date Math (UTC & Formatting)
        $utcNow = (Get-Date).ToUniversalTime()
        $thresholdDate = $utcNow.AddDays(-$InactiveDays)
        # Format for OData: yyyy-MM-ddTHH:mm:ssZ
        $filterDateString = Format-ODataDateTime -DateTime $thresholdDate

        try
        {
            Write-PSFMessage -Level Verbose -Message "Calculating threshold: Devices inactive since $filterDateString"

            # 3. Build Dynamic Server-Side Filter
            $filterParts = [System.Collections.Generic.List[string]]::new()

            # Date Filter: approximateLastSignInDateTime is LESS THAN OR EQUAL TO threshold
            # Use an unquoted DateTimeOffset literal for OData (e.g. 2023-01-01T00:00:00Z)
            $filterParts.Add("approximateLastSignInDateTime le $filterDateString")

            # Account Enabled Filter
            if (-not $IncludeDisabled)
            {
                $filterParts.Add("accountEnabled eq true")
            }

            # Device Type Filter
            if ($DeviceType)
            {
                $filterParts.Add("operatingSystem eq '$DeviceType'")
            }

            $finalFilter = $filterParts -join ' and '
            Write-PSFMessage -Level Verbose -Message "Using OData Filter: $finalFilter"

            $params = @{
                All         = $true
                Filter      = $finalFilter
                Property    = @('id', 'displayName', 'operatingSystem', 'approximateLastSignInDateTime', 'accountEnabled')
                ErrorAction = 'Stop'
            }

            $devices = Get-MgBetaDevice @params

            $deviceCount = if ($devices) { $devices.Count } else { 0 }
            Write-PSFMessage -Level Verbose -Message "Found $deviceCount inactive devices."

            foreach ($device in $devices)
            {
                $daysInactive = $null
                if ($device.ApproximateLastSignInDateTime)
                {
                    # Normalize to UTC and calculate days (use TotalDays and floor)
                    try
                    {
                        $lastSignInUtc = ([DateTime]$device.ApproximateLastSignInDateTime).ToUniversalTime()
                    }
                    catch
                    {
                        # If parsing fails, skip days calculation
                        $lastSignInUtc = $null
                    }

                    if ($lastSignInUtc)
                    {
                        $daysInactive = [math]::Floor((New-TimeSpan -Start $lastSignInUtc -End $utcNow).TotalDays)
                    }
                }

                $results.Add([PSCustomObject]@{
                        DisplayName                   = $device.DisplayName
                        DeviceId                      = $device.Id
                        OperatingSystem               = $device.OperatingSystem
                        ApproximateLastSignInDateTime = $device.ApproximateLastSignInDateTime
                        AccountEnabled                = $device.AccountEnabled
                        DaysInactive                  = $daysInactive
                    })
            }

            return $results.ToArray()
        }
        catch
        {
            # 4. Gold Standard Error Handling
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'Inactive Devices'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve inactive devices: $($err.Reason)"
        }
    }
}
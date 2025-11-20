function Get-GTInactiveDevices {
    <#
    .SYNOPSIS
    Retrieves devices that have not signed in for a specified number of days.

    .DESCRIPTION
    This function retrieves devices from Microsoft Entra ID and filters them based on their
    approximate last sign-in date to identify inactive devices.

    .PARAMETER InactiveDays
    The number of days of inactivity to check for.

    .PARAMETER DeviceType
    Optional filter for specific operating systems (e.g., 'Windows', 'iOS').

    .PARAMETER IncludeDisabled
    Switch to include devices that are already disabled. By default, only enabled devices are returned.

    .EXAMPLE
    Get-GTInactiveDevices -InactiveDays 90
    Finds all enabled devices inactive for more than 90 days.

    .EXAMPLE
    Get-GTInactiveDevices -InactiveDays 60 -DeviceType 'Windows'
    Finds enabled Windows devices inactive for more than 60 days.

    .NOTES
    Requires Microsoft Graph PowerShell SDK with Device.Read.All permission.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$InactiveDays,

        [string]$DeviceType,

        [switch]$IncludeDisabled
    )

    begin {
        $modules = @('Microsoft.Graph.Identity.DirectoryManagement')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        if (-not (Initialize-GTGraphConnection -Scopes 'Device.Read.All')) {
            Write-Error "Failed to initialize Microsoft Graph connection."
            return
        }
    }

    process {
        try {
            Write-PSFMessage -Level Verbose -Message "Fetching devices from Microsoft Graph..."
            
            $params = @{
                All         = $true
                Property    = @('id', 'displayName', 'operatingSystem', 'approximateLastSignInDateTime', 'accountEnabled')
                ErrorAction = 'Stop'
            }

            # Apply server-side filter for OS if possible, otherwise client-side
            if ($DeviceType) {
                $params['Filter'] = "operatingSystem eq '$DeviceType'"
            }

            $devices = Get-MgBetaDevice @params
            $results = [System.Collections.Generic.List[PSCustomObject]]::new()
            $now = Get-Date

            foreach ($device in $devices) {
                # Skip disabled devices unless requested
                if (-not $IncludeDisabled -and -not $device.AccountEnabled) { continue }

                $lastSignIn = $device.ApproximateLastSignInDateTime
                $daysInactive = $null

                if ($lastSignIn) {
                    $daysInactive = (New-TimeSpan -Start $lastSignIn -End $now).Days
                    
                    if ($daysInactive -ge $InactiveDays) {
                        $results.Add([PSCustomObject]@{
                                DisplayName                   = $device.DisplayName
                                DeviceId                      = $device.Id
                                OperatingSystem               = $device.OperatingSystem
                                ApproximateLastSignInDateTime = $lastSignIn
                                AccountEnabled                = $device.AccountEnabled
                                DaysInactive                  = $daysInactive
                            })
                    }
                }
            }

            Write-PSFMessage -Level Verbose -Message "Found $($results.Count) inactive devices."
            return $results
        }
        catch {
            Stop-PSFFunction -Message "Failed to retrieve inactive devices: $($_.Exception.Message)" -ErrorRecord $_ -EnableException $true
        }
    }
}

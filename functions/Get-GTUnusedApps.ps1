function Get-GTUnusedApps
{
    <#
    .SYNOPSIS
    Identifies Service Principals that have not had any sign-ins for a specified period.

    .DESCRIPTION
    This function retrieves Service Principals and analyzes their sign-in activity to identify
    those that have been inactive for longer than the specified threshold.

    .PARAMETER DaysSinceLastSignIn
    The number of days of inactivity to check for.

    .PARAMETER IncludeNeverUsed
    Switch to include apps that have never had a recorded sign-in.

    .EXAMPLE
    Get-GTUnusedApps -DaysSinceLastSignIn 90
    Finds apps inactive for more than 90 days.

    .NOTES
    Requires Microsoft Graph PowerShell SDK with AuditLog.Read.All permission.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$DaysSinceLastSignIn,

        [switch]$IncludeNeverUsed
    )

    begin
    {
        $modules = @('Microsoft.Graph.Beta.Applications')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        if (-not (Initialize-GTGraphConnection -Scopes 'AuditLog.Read.All'))
        {
            Write-Error "Failed to initialize Microsoft Graph connection."
            return
        }
    }

    process
    {
        try
        {
            Write-PSFMessage -Level Verbose -Message "Fetching Service Principals with sign-in activity..."
            
            $params = @{
                All         = $true
                Property    = @('id', 'appId', 'displayName', 'signInActivity')
                ErrorAction = 'Stop'
            }

            $sps = Get-MgBetaServicePrincipal @params
            $results = [System.Collections.Generic.List[PSCustomObject]]::new()
            $now = Get-UTCTime

            foreach ($sp in $sps)
            {
                $lastSignIn = $sp.SignInActivity.LastSignInDateTime
                $daysInactive = $null

                if ($lastSignIn)
                {
                    $daysInactive = (New-TimeSpan -Start $lastSignIn -End $now).Days
                    
                    if ($daysInactive -ge $DaysSinceLastSignIn)
                    {
                        $results.Add([PSCustomObject]@{
                                DisplayName        = $sp.DisplayName
                                AppId              = $sp.AppId
                                LastSignInDateTime = $lastSignIn
                                DaysInactive       = $daysInactive
                                Status             = 'Inactive'
                            })
                    }
                }
                elseif ($IncludeNeverUsed)
                {
                    $results.Add([PSCustomObject]@{
                            DisplayName        = $sp.DisplayName
                            AppId              = $sp.AppId
                            LastSignInDateTime = $null
                            DaysInactive       = 'Never'
                            Status             = 'Never Used'
                        })
                }
            }

            Write-PSFMessage -Level Verbose -Message "Found $($results.Count) unused apps."
            return $results
        }
        catch
        {
            Stop-PSFFunction -Message "Failed to retrieve unused apps: $($_.Exception.Message)" -ErrorRecord $_ -EnableException $true
        }
    }
}

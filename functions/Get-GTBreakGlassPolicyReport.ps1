function Get-GTBreakGlassPolicyReport
{
    <#
    .SYNOPSIS
    Audits Conditional Access policies to ensure Break Glass (Emergency Access) accounts are excluded.

    .DESCRIPTION
    This function checks specified Break Glass accounts against all enabled (or reporting) Conditional Access policies.
    It identifies "Risk" scenarios where a Break Glass account is NOT explicitly excluded from a policy that enforces controls.

    It handles:
    - Resolution of UPNs to Object IDs for accurate comparison.
    - Analysis of "All Users", "Specific Users", "Groups", and "Roles" targeting.
    - Detection of Blocking policies (High Risk).

    .PARAMETER BreakGlassUpn
    A list of User Principal Names (UPNs) for your emergency access accounts.

    .PARAMETER State
    Specifies the states of the policies to audit. Defaults to 'enabled' and 'enabledForReportingButNotEnforced'.

    .PARAMETER NewSession
    Forces a new Microsoft Graph session.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]]$BreakGlassUpn,

        [Parameter(Mandatory = $false)]
        [ValidateSet('enabled', 'disabled', 'enabledForReportingButNotEnforced')]
        [string[]]$State = @('enabled', 'enabledForReportingButNotEnforced'),

        [switch]$NewSession
    )

    begin
    {
        $modules = @('Microsoft.Graph.Authentication')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        # 1. Scopes Check
        $requiredScopes = @('Policy.Read.All', 'User.Read.All')
        
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

        # 3. Resolve UPNs to IDs
        Write-PSFMessage -Level Verbose -Message "Resolving Break Glass UPNs to Object IDs..."
        $bgAccounts = @()
        
        foreach ($upn in $BreakGlassUpn)
        {
            try
            {
                $resp = Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/$upn?`$select=id,userPrincipalName" -ErrorAction Stop
                $bgAccounts += [PSCustomObject]@{
                    Id  = $resp.id
                    Upn = $resp.userPrincipalName
                }
                Write-PSFMessage -Level Verbose -Message "Resolved $upn to $($resp.id)"
            }
            catch
            {
                Write-Error "Could not find Break Glass user: $upn. Skipping."
            }
        }

        if ($bgAccounts.Count -eq 0)
        {
            Write-Error "No valid Break Glass accounts resolved. Aborting."
            return
        }
    }

    process
    {
        $report = [System.Collections.Generic.List[PSCustomObject]]::new()

        try
        {
            # 4. Fetch Policies
            $filterConditions = $State | ForEach-Object { "state eq '$_'" }
            $filter = $filterConditions -join ' or '
            
            $props = @('id', 'displayName', 'state', 'conditions', 'grantControls')

            Write-PSFMessage -Level Verbose -Message "Fetching CA policies with state: $($State -join ', ')"
            $policies = Invoke-GTGraphPagedRequest -Uri "v1.0/identity/conditionalAccess/policies?`$filter=$([Uri]::EscapeDataString($filter))&`$select=$($props -join ',')"

            Write-PSFMessage -Level Verbose -Message "Auditing $($policies.Count) policies against $($bgAccounts.Count) break glass accounts..."

            foreach ($policy in $policies)
            {
                $users = $policy.conditions.users
                $controls = $policy.grantControls.builtInControls
                
                # Determine if this is a BLOCK policy (Higher Risk)
                $isBlockPolicy = ($controls -contains 'block')

                foreach ($bgUser in $bgAccounts)
                {
                    $status = "Safe"
                    $reason = "Not Targeted"
                    $severity = "Info"

                    # --- Analysis Logic ---

                    # Check Exclusions (The most important check)
                    $isExcluded = ($users.excludeUsers -contains $bgUser.Id)

                    # Check Inclusions
                    $isTargeted = $false
                    
                    # A. Targeted via "All Users"
                    if ($users.includeUsers -contains 'All')
                    {
                        $isTargeted = $true
                    }
                    # B. Targeted via Specific User ID
                    elseif ($users.includeUsers -contains $bgUser.Id)
                    {
                        $isTargeted = $true
                    }
                    # C. Targeted via Roles
                    elseif ($users.includeRoles.Count -gt 0)
                    {
                        if (-not $isExcluded)
                        {
                            $status = "Potential Risk"
                            $reason = "Policy targets Roles. Ensure BG account does not hold included roles."
                            $severity = "Warning"
                        }
                    }
                    # D. Targeted via Group
                    elseif ($users.includeGroups.Count -gt 0)
                    {
                        if (-not $isExcluded)
                        {
                            $status = "Potential Risk"
                            $reason = "Policy targets Groups. Ensure BG account is not in included groups."
                            $severity = "Warning"
                        }
                    }

                    # --- Final Verdict ---
                    if ($isTargeted)
                    {
                        if ($isExcluded)
                        {
                            $status = "Safe"
                            $reason = "User explicitly excluded."
                            $severity = "Success"
                        }
                        else
                        {
                            $status = "RISK"
                            if ($isBlockPolicy)
                            {
                                $reason = "User is INCLUDED in a BLOCK policy and NOT excluded."
                                $severity = "Critical"
                            }
                            else
                            {
                                $reason = "User is INCLUDED and NOT excluded. Controls applied: $($controls -join ', ')"
                                $severity = "High"
                            }
                        }
                    }

                    # Only report relevant findings (Risk, Warning, or explicit Safe exclusions)
                    if ($status -ne "Not Targeted" -or $PSCmdlet.MyInvocation.BoundParameters["Verbose"])
                    {
                        $report.Add([PSCustomObject]@{
                                PolicyName     = $policy.displayName
                                PolicyId       = $policy.id
                                State          = $policy.state
                                BreakGlassUser = $bgUser.Upn
                                Status         = $status
                                Severity       = $severity
                                Reason         = $reason
                                GrantControls  = $controls -join ', '
                            })
                    }
                }
            }

            # Output Summary
            $risks = $report | Where-Object { $_.Status -eq 'RISK' }
            if ($risks)
            {
                Write-PSFMessage -Level Warning -Message "Found $($risks.Count) policies putting Break Glass accounts at RISK."
            }
            else
            {
                Write-PSFMessage -Level Verbose -Message "No direct risks found."
            }

            return $report.ToArray()
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'CA Policy'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to audit Break Glass policies: $($err.Reason)"
            throw $err.ErrorMessage
        }
    }
}
function Get-GTAdminCountReport
{
    <#
    .SYNOPSIS
    Generates a report of administrative role assignments in the tenant.

    .DESCRIPTION
    Retrieves all active Directory Roles and counts the number of assigned members.
    It categorizes roles by risk tier (Tier 0, 1, 2) to help prioritize security reviews.
    
    It helps identify "Privilege Creep" by highlighting roles with excessive assignments.

    RISK TIERS:
    - Tier 0 (Critical): Global Admin, Privileged Role Admin (Control over the tenant).
    - Tier 1 (High):     Exchange, SharePoint, User, Authentication Admins (Control over data/users).
    - Tier 2 (Standard): Service Support, Reader roles.

    .PARAMETER RoleName
    Optional. Filter by specific role names (e.g., "Global Administrator").

    .PARAMETER ShowMembers
    Switch to include the list of member UPNs in the output object (warning: larger output).

    .PARAMETER NewSession
    Forces a new Microsoft Graph session.

    .EXAMPLE
    Get-GTAdminCountReport
    Returns a summary count of all active admin roles.

    .EXAMPLE
    Get-GTAdminCountReport -RoleName "Global Administrator" -ShowMembers
    Returns the count and the specific list of users who are Global Admins.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Position = 0)]
        [string[]]$RoleName,

        [switch]$ShowMembers,
        [switch]$NewSession
    )

    begin
    {
        $modules = @('Microsoft.Graph.Identity.DirectoryManagement')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        # 1. Scopes Check
        # RoleManagement.Read.Directory allows reading role definitions and assignments
        $requiredScopes = @('RoleManagement.Read.Directory', 'Directory.Read.All')
        
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

        # 3. Define Risk Tiers
        $Tier0 = @('Global Administrator', 'Privileged Role Administrator', 'Security Administrator', 'Hybrid Identity Administrator')
        $Tier1 = @('Exchange Administrator', 'SharePoint Administrator', 'User Administrator', 'Authentication Administrator', 'Cloud Application Administrator', 'Intune Administrator')
    }

    process
    {
        $report = [System.Collections.Generic.List[PSCustomObject]]::new()

        try
        {
            Write-PSFMessage -Level Verbose -Message "Fetching active Directory Roles..."

            # 4. Fetch Roles
            # We only fetch activated roles (those that have members) to save time.
            # Get-MgDirectoryRole returns only roles that have been activated/used in the tenant.
            $roles = Get-MgDirectoryRole -All -ExpandProperty members -ErrorAction Stop

            foreach ($role in $roles)
            {
                # Filter by Name if requested
                if ($RoleName -and $role.DisplayName -notin $RoleName) { continue }

                # Determine Tier
                $tier = "Tier 2 (Standard)"
                if ($Tier0 -contains $role.DisplayName) { $tier = "Tier 0 (Critical)" }
                elseif ($Tier1 -contains $role.DisplayName) { $tier = "Tier 1 (High)" }

                # Count Members
                # Members can be Users, Service Principals, or Groups.
                $memberCount = if ($role.Members) { $role.Members.Count } else { 0 }
                
                # Identify Member Types
                $userCount = 0
                $spCount = 0
                $groupCount = 0
                $memberNames = [System.Collections.Generic.List[string]]::new()

                if ($role.Members)
                {
                    foreach ($member in $role.Members)
                    {
                        $type = $member.AdditionalProperties['@odata.type']
                        
                        if ($type -match 'user') { 
                            $userCount++
                            if ($ShowMembers) { 
                                # Try to get UPN, fallback to DisplayName
                                $name = if ($member.AdditionalProperties.ContainsKey('userPrincipalName')) { $member.AdditionalProperties['userPrincipalName'] } else { $member.DisplayName }
                                $memberNames.Add("$name (User)")
                            }
                        }
                        elseif ($type -match 'servicePrincipal') { 
                            $spCount++ 
                            if ($ShowMembers) { $memberNames.Add("$($member.DisplayName) (SP)") }
                        }
                        elseif ($type -match 'group') { 
                            $groupCount++ 
                            if ($ShowMembers) { $memberNames.Add("$($member.DisplayName) (Group)") }
                        }
                    }
                }

                # 5. Risk Analysis (Heuristics)
                $riskNote = $null
                if ($role.DisplayName -eq "Global Administrator" -and $userCount -gt 5) {
                    $riskNote = "High: >5 Global Admins detected."
                }
                elseif ($groupCount -gt 0) {
                    $riskNote = "Warning: Role assigned to Group. Verify Group membership controls."
                }

                $reportObject = [ordered]@{
                    RoleName      = $role.DisplayName
                    Tier          = $tier
                    TotalMembers  = $memberCount
                    UserCount     = $userCount
                    ServicePrincipalCount = $spCount
                    GroupCount    = $groupCount
                    RiskNote      = $riskNote
                }

                if ($ShowMembers) {
                    $reportObject['Members'] = $memberNames -join '; '
                }

                $report.Add([PSCustomObject]$reportObject)
            }

            # 6. Output Sorting
            # Sort by Tier (0 first), then by Total Members (Descending)
            if ($report.Count -gt 0) {
                Write-PSFMessage -Level Verbose -Message "Found $($report.Count) active admin roles."
                return $report | Sort-Object Tier, TotalMembers
            } else {
                Write-PSFMessage -Level Verbose -Message "No active roles found matching criteria."
                return @()
            }
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'Directory Roles'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve admin report: $($err.Reason)"
            throw $err.ErrorMessage
        }
    }
}
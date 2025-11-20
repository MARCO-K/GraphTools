function Get-GTPIMRoleReport {
    <#
    .SYNOPSIS
    Generates a comprehensive report of all eligible and active PIM role assignments.

    .DESCRIPTION
    Retrieves both eligible and active PIM role assignments from Microsoft Entra ID.
    It distinguishes between 'Eligible' (can activate) and 'Active' (currently active) assignments.
    It caches role definitions to improve performance.
    
    This function handles both User and Group assignments correctly.

    .PARAMETER UserId
    Optional. Filter the report for a specific user by their Object ID (GUID).

    .PARAMETER RoleName
    Optional. Filter the report for a specific role by its display name (e.g., 'Global Administrator').

    .EXAMPLE
    Get-GTPIMRoleReport -UserId '00000000-0000-0000-0000-000000000000'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$UserId,

        [Parameter(Mandatory = $false)]
        [string]$RoleName
    )

    begin {
        # 1. Module Check
        $modules = @('Microsoft.Graph.Identity.Governance', 'Microsoft.Graph.Users')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        # 2. Scope Check (Gold Standard)
        # We need User/Group read permissions to expand the 'principal' details
        $requiredScopes = @('RoleManagement.Read.Directory', 'User.Read.All', 'Group.Read.All')
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet)) {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }

        # 3. Validate User ID (Gold Standard)
        if ($UserId) {
            # This will throw a terminating error if invalid, stopping execution immediately
            Test-GTGuid -InputObject $UserId
        }

        # 4. Cache Role Definitions
        Write-PSFMessage -Level Verbose -Message "Caching Role Definitions..."
        try {
            $allRoles = Get-MgBetaRoleManagementDirectoryRoleDefinition -All -Property Id, DisplayName -ErrorAction Stop
            $roleCache = @{}
            foreach ($role in $allRoles) {
                $roleCache[$role.Id] = $role.DisplayName
            }
            Write-PSFMessage -Level Verbose -Message "Cached $($roleCache.Count) roles."
        }
        catch {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'RoleDefinitions'
            Write-PSFMessage -Level Warning -Message "Failed to cache roles: $($err.Reason)"
            return
        }
    }

    process {
        try {
            $results = [System.Collections.Generic.List[PSCustomObject]]::new()

            # --- Helper to process assignments to avoid code duplication ---
            $ProcessAssignment = {
                param($AssignmentList, $Type)

                foreach ($assignment in $AssignmentList) {
                    $roleDefId = $assignment.RoleDefinitionId
                    $roleDisplayName = if ($roleCache.ContainsKey($roleDefId)) { $roleCache[$roleDefId] } else { $roleDefId }

                    # Client-side filtering for RoleName
                    if ($RoleName -and $roleDisplayName -ne $RoleName) { continue }

                    # Handle Principal Details (User vs Group)
                    $principalName = "Unknown"
                    $principalUPN = $null
                    $principalType = "Unknown"

                    if ($assignment.Principal) {
                        $principalName = $assignment.Principal.DisplayName
                        $odataType = $assignment.Principal.AdditionalProperties['@odata.type']

                        if ($odataType -match 'group') {
                            $principalType = 'Group'
                            $principalUPN = "Group (No UPN)"
                        }
                        elseif ($odataType -match 'servicePrincipal') {
                            $principalType = 'ServicePrincipal'
                            $principalUPN = $assignment.Principal.AdditionalProperties['appId']
                        }
                        else {
                            $principalType = 'User'
                            $principalUPN = $assignment.Principal.AdditionalProperties['userPrincipalName']
                        }
                    }

                    # Determine State
                    $state = $assignment.AssignmentState # Default property
                    if ($Type -eq 'Active') {
                        $state = if ($assignment.AssignmentType -eq 'Assigned') { 'Assigned (Permanent)' } else { 'Activated (Time-bound)' }
                    }

                    $results.Add([PSCustomObject]@{
                            User              = $principalName
                            UserPrincipalName = $principalUPN
                            PrincipalType     = $principalType
                            UserId            = $assignment.PrincipalId
                            Role              = $roleDisplayName
                            RoleId            = $roleDefId
                            Type              = $Type
                            AssignmentState   = $state
                            StartDateTime     = $assignment.StartDateTime
                            EndDateTime       = $assignment.EndDateTime
                        })
                }
            }

            # 1. Fetch Eligible Assignments
            Write-PSFMessage -Level Verbose -Message "Fetching Eligible Assignments..."
            $eligibleParams = @{
                All            = $true
                ExpandProperty = 'principal'
                ErrorAction    = 'Stop'
            }
            if ($UserId) { $eligibleParams['Filter'] = "principalId eq '$UserId'" }
            
            $eligibleAssignments = Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance @eligibleParams
            & $ProcessAssignment -AssignmentList $eligibleAssignments -Type 'Eligible'

            # 2. Fetch Active Assignments
            Write-PSFMessage -Level Verbose -Message "Fetching Active Assignments..."
            $activeParams = @{
                All            = $true
                ExpandProperty = 'principal'
                ErrorAction    = 'Stop'
            }
            if ($UserId) { $activeParams['Filter'] = "principalId eq '$UserId'" }

            $activeAssignments = Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance @activeParams
            & $ProcessAssignment -AssignmentList $activeAssignments -Type 'Active'

            return $results
        }
        catch {
            # Gold Standard Error Handling
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'PIM Report'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to generate PIM report: $($err.Reason)"
            
            # If you want to throw a terminating error to stop a pipeline:
            # throw $err.ErrorMessage
        }
    }
}
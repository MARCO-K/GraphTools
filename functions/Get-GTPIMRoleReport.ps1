function Get-GTPIMRoleReport
{
    <#
    .SYNOPSIS
    Generates a comprehensive report of all eligible and active PIM role assignments.

    .DESCRIPTION
    Retrieves both eligible and active PIM role assignments from Microsoft Entra ID.
    It distinguishes between 'Eligible' (can activate) and 'Active' (currently active) assignments.
    
    PERFORMANCE:
    - Caches role definitions to map Names to IDs.
    - Uses Server-Side filtering for both User and Role lookups to minimize API traffic.
    - Streams output to the pipeline for memory efficiency.

    .PARAMETER UserId
    Optional. Filter the report for a specific user by their Object ID (GUID).

    .PARAMETER RoleName
    Optional. Filter the report for a specific role by its display name (e.g., 'Global Administrator').

    .EXAMPLE
    Get-GTPIMRoleReport -RoleName 'Global Administrator'
    Efficiently retrieves only Global Admins using server-side filtering.

    .EXAMPLE
    Get-GTPIMRoleReport -UserId '12345678-1234-1234-1234-123456789012'
    Retrieves PIM assignments for a specific user by their Object ID.

    .EXAMPLE
    Get-GTPIMRoleReport -UserId '12345678-1234-1234-1234-123456789012' -RoleName 'Global Administrator'
    Combines user and role filters for highly targeted reports.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$UserId,

        [Parameter(Mandatory = $false)]
        [string]$RoleName,

        [switch]$NewSession
    )

    begin
    {
        # 1. Module Check
        $modules = @('Microsoft.Graph.Identity.Governance', 'Microsoft.Graph.Users')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        # 2. Scope Check
        $requiredScopes = @('RoleManagement.Read.Directory', 'User.Read.All', 'Group.Read.All')
        
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet))
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }

        # 3. Connection Initialization
        if (-not (Initialize-GTGraphConnection -Scopes $requiredScopes -NewSession:$NewSession))
        {
            Write-Error "Failed to initialize session."
            return
        }

        # 4. Validate User ID
        if ($UserId) { Test-GTGuid -InputObject $UserId }

        # 5. Cache Role Definitions & Resolve RoleName Filter
        Write-PSFMessage -Level Verbose -Message "Caching Role Definitions..."
        $targetRoleDefId = $null

        try
        {
            $allRoles = Get-MgBetaRoleManagementDirectoryRoleDefinition -All -Property Id, DisplayName -ErrorAction Stop
            $roleCache = @{}
            
            foreach ($role in $allRoles)
            {
                $roleCache[$role.Id] = $role.DisplayName
                
                # Optimization: Find the ID for the requested RoleName immediately
                if ($RoleName -and $role.DisplayName -eq $RoleName)
                {
                    $targetRoleDefId = $role.Id
                }
            }
            Write-PSFMessage -Level Verbose -Message "Cached $($roleCache.Count) roles."

            # Validation: If user asked for a role that doesn't exist, stop early.
            if ($RoleName -and -not $targetRoleDefId)
            {
                Write-Error "Role '$RoleName' not found in directory. Cannot generate report."
                return
            }
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'RoleDefinitions'
            Write-PSFMessage -Level Warning -Message "Failed to cache roles: $($err.Reason)"
            
            throw $err.ErrorMessage
        }
    }

    process
    {
        try
        {
            # --- Helper ScriptBlock for Processing ---
            $ProcessAssignment = {
                param($AssignmentList, $Type)

                foreach ($assignment in $AssignmentList)
                {
                    $roleDefId = $assignment.RoleDefinitionId
                    $roleDisplayName = if ($roleCache.ContainsKey($roleDefId)) { $roleCache[$roleDefId] } else { $roleDefId }

                    # Handle Principal Details
                    $principalName = "Unknown"
                    $principalUPN = $null
                    $principalType = "Unknown"

                    # Determine principal type based on @odata.type (User, Group, or ServicePrincipal)
                    if ($assignment.Principal)
                    {
                        $principalName = $assignment.Principal.DisplayName
                        $odataType = $assignment.Principal.AdditionalProperties['@odata.type']

                        if ($odataType -match 'group')
                        {
                            $principalType = 'Group'
                            $principalUPN = "Group (No UPN)"
                        }
                        elseif ($odataType -match 'servicePrincipal')
                        {
                            $principalType = 'ServicePrincipal'
                            $principalUPN = $assignment.Principal.AdditionalProperties['appId']
                        }
                        else
                        {
                            $principalType = 'User'
                            $principalUPN = $assignment.Principal.AdditionalProperties['userPrincipalName']
                        }
                    }

                    # Determine State
                    $state = $assignment.AssignmentState
                    if ($Type -eq 'Active')
                    {
                        $state = if ($assignment.AssignmentType -eq 'Assigned') { 'Assigned (Permanent)' } else { 'Activated (Time-bound)' }
                    }

                    # Stream Object to Pipeline
                    [PSCustomObject]@{
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
                    }
                }
            }

            # --- Build Dynamic Server-Side Filter ---
            $filterParts = [System.Collections.Generic.List[string]]::new()
            
            if ($UserId) { $filterParts.Add("principalId eq '$UserId'") }
            if ($targetRoleDefId) { $filterParts.Add("roleDefinitionId eq '$targetRoleDefId'") }
            
            $finalFilter = $filterParts -join ' and '
            
            $params = @{
                All            = $true
                ExpandProperty = 'principal'
                ErrorAction    = 'Stop'
            }
            if ($finalFilter)
            {
                Write-PSFMessage -Level Verbose -Message "Using OData Filter: $finalFilter"
                $params['Filter'] = $finalFilter 
            }

            # 1. Fetch Eligible Assignments
            Write-PSFMessage -Level Verbose -Message "Fetching Eligible Assignments..."
            $eligibleAssignments = Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance @params
            Write-PSFMessage -Level Verbose -Message "Fetched $($eligibleAssignments.Count) eligible assignments."
            & $ProcessAssignment -AssignmentList $eligibleAssignments -Type 'Eligible'

            # 2. Fetch Active Assignments
            Write-PSFMessage -Level Verbose -Message "Fetching Active Assignments..."
            $activeAssignments = Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance @params
            Write-PSFMessage -Level Verbose -Message "Fetched $($activeAssignments.Count) active assignments."
            & $ProcessAssignment -AssignmentList $activeAssignments -Type 'Active'
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'PIM Report'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to generate PIM report: $($err.Reason)"
            
            throw $err.ErrorMessage
        }
    }
}
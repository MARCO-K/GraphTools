function Get-GTPIMRoleReport {
    <#
    .SYNOPSIS
    Generates a comprehensive report of all eligible and active PIM role assignments.

    .DESCRIPTION
    This function retrieves both eligible and active PIM role assignments from Microsoft Entra ID.
    It distinguishes between 'Eligible' (can activate) and 'Active' (currently active) assignments.
    It also caches role definitions to improve performance by avoiding repeated API calls for role names.

    .PARAMETER UserId
    Optional. Filter the report for a specific user by their Object ID (GUID).

    .PARAMETER RoleName
    Optional. Filter the report for a specific role by its display name (e.g., 'Global Administrator').

    .EXAMPLE
    Get-GTPIMRoleReport
    Retrieves all PIM assignments for all users.

    .EXAMPLE
    Get-GTPIMRoleReport -UserId '00000000-0000-0000-0000-000000000000'
    Retrieves PIM assignments for the specified user.

    .EXAMPLE
    Get-GTPIMRoleReport -RoleName 'Global Administrator'
    Retrieves all users who have the 'Global Administrator' role (eligible or active).

    .NOTES
    Requires Microsoft Graph PowerShell SDK with RoleManagement.Read.Directory permission.
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
        $modules = @('Microsoft.Graph.Identity.Governance')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        if (-not (Initialize-GTGraphConnection -Scopes 'RoleManagement.Read.Directory')) {
            Write-Error "Failed to initialize Microsoft Graph connection."
            return
        }

        # Validate User ID if provided
        if ($UserId) {
            if (-not (Test-GTGuid -InputObject $UserId -Quiet)) {
                Write-Error "Invalid User ID format. Must be a GUID."
                return
            }
        }

        # Cache Role Definitions
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
            Write-Error "Failed to cache role definitions: $($_.Exception.Message)"
            return
        }
    }

    process {
        try {
            $results = [System.Collections.Generic.List[PSCustomObject]]::new()

            # 1. Fetch Eligible Assignments
            Write-PSFMessage -Level Verbose -Message "Fetching Eligible Assignments..."
            $eligibleParams = @{
                All            = $true
                ExpandProperty = 'principal'
                ErrorAction    = 'Stop'
            }
            if ($UserId) {
                $eligibleParams['Filter'] = "principalId eq '$UserId'"
            }

            $eligibleAssignments = Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance @eligibleParams

            foreach ($assignment in $eligibleAssignments) {
                $roleName = $roleCache[$assignment.RoleDefinitionId]
                
                # Filter by RoleName if specified
                if ($RoleName -and $roleName -ne $RoleName) { continue }

                $results.Add([PSCustomObject]@{
                        User              = $assignment.Principal.DisplayName
                        UserPrincipalName = $assignment.Principal.AdditionalProperties['userPrincipalName'] # Principal expansion might not always have UPN directly
                        UserId            = $assignment.PrincipalId
                        Role              = $roleName
                        Type              = 'Eligible'
                        AssignmentState   = 'Eligible'
                        StartDateTime     = $assignment.StartDateTime
                        EndDateTime       = $assignment.EndDateTime
                    })
            }

            # 2. Fetch Active Assignments
            Write-PSFMessage -Level Verbose -Message "Fetching Active Assignments..."
            $activeParams = @{
                All            = $true
                ExpandProperty = 'principal'
                ErrorAction    = 'Stop'
            }
            if ($UserId) {
                $activeParams['Filter'] = "principalId eq '$UserId'"
            }

            $activeAssignments = Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance @activeParams

            foreach ($assignment in $activeAssignments) {
                $roleName = $roleCache[$assignment.RoleDefinitionId]

                # Filter by RoleName if specified
                if ($RoleName -and $roleName -ne $RoleName) { continue }

                $state = if ($assignment.AssignmentType -eq 'Assigned') { 'Assigned (Permanent/Direct)' } else { 'Activated (PIM)' }

                $results.Add([PSCustomObject]@{
                        User              = $assignment.Principal.DisplayName
                        UserPrincipalName = $assignment.Principal.AdditionalProperties['userPrincipalName']
                        UserId            = $assignment.PrincipalId
                        Role              = $roleName
                        Type              = 'Active'
                        AssignmentState   = $state
                        StartDateTime     = $assignment.StartDateTime
                        EndDateTime       = $assignment.EndDateTime
                    })
            }

            return $results
        }
        catch {
            Stop-PSFFunction -Message "Failed to generate PIM report: $($_.Exception.Message)" -ErrorRecord $_ -EnableException $true
        }
    }
}

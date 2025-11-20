function Remove-GTPIMRoleEligibility {
    <#
    .SYNOPSIS
    Removes both active and eligible PIM role assignments for a user.

    .DESCRIPTION
    This function removes Privileged Identity Management (PIM) role assignments.
    It targets both:
    1. Active assignments (unifiedRoleAssignmentScheduleInstances)
    2. Eligible assignments (unifiedRoleEligibilityScheduleInstances)

    Removing eligible assignments ensures the user cannot re-activate the role later.

    .PARAMETER UserId
    The Object ID (GUID) of the user to remove roles from.

    .PARAMETER RoleDefinitionId
    Optional. The Object ID (GUID) of a specific role definition to remove.
    If not specified, ALL PIM assignments for the user will be removed.

    .EXAMPLE
    Remove-GTPIMRoleEligibility -UserId '00000000-0000-0000-0000-000000000000'
    Removes all PIM assignments (active and eligible) for the specified user.

    .EXAMPLE
    Remove-GTPIMRoleEligibility -UserId $userId -RoleDefinitionId $roleId
    Removes a specific PIM role assignment for the user.

    .NOTES
    Requires Microsoft Graph PowerShell SDK with RoleEligibilitySchedule.ReadWrite.Directory permission.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId,

        [Parameter(Mandatory = $false)]
        [string]$RoleDefinitionId
    )

    begin {
        $modules = @('Microsoft.Graph.Identity.Governance')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        if (-not (Initialize-GTGraphConnection -Scopes 'RoleEligibilitySchedule.ReadWrite.Directory')) {
            Write-Error "Failed to initialize Microsoft Graph connection."
            return
        }

        # Validate User ID
        if (-not (Test-GTGuid -InputObject $UserId -Quiet)) {
            Write-Error "Invalid User ID format. Must be a GUID."
            return
        }

        # Self-Protection Check
        $currentUser = Get-MgContext
        try {
            $me = Get-MgBetaUser -UserId 'me' -Property Id -ErrorAction Stop
            if ($me.Id -eq $UserId) {
                Write-Warning "You are attempting to remove PIM roles from YOURSELF. Proceed with caution."
                if (-not $PSCmdlet.ShouldProcess("YOURSELF ($UserId)", "Remove PIM Roles")) {
                    return
                }
            }
        }
        catch {
            Write-Verbose "Could not verify if target user is self. Proceeding."
        }
    }

    process {
        try {
            $results = [System.Collections.Generic.List[PSCustomObject]]::new()

            # 1. Remove Active Assignments (unifiedRoleAssignmentScheduleInstances)
            Write-PSFMessage -Level Verbose -Message "Checking Active Assignments..."
            $activeFilter = "principalId eq '$UserId'"
            if ($RoleDefinitionId) {
                $activeFilter += " and roleDefinitionId eq '$RoleDefinitionId'"
            }
            
            $activeAssignments = Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance -Filter $activeFilter -ExpandProperty roleDefinition -All -ErrorAction Stop

            foreach ($assignment in $activeAssignments) {
                $roleName = $assignment.RoleDefinition.DisplayName
                if ($PSCmdlet.ShouldProcess("Active Assignment: $roleName", "Remove")) {
                    try {
                        if ($assignment.RoleAssignmentScheduleId) {
                            Remove-MgBetaRoleManagementDirectoryRoleAssignmentSchedule -UnifiedRoleAssignmentScheduleId $assignment.RoleAssignmentScheduleId -ErrorAction Stop
                             
                            $results.Add([PSCustomObject]@{
                                    Role   = $roleName
                                    Type   = 'Active'
                                    Status = 'Removed'
                                })
                        }
                    }
                    catch {
                        $results.Add([PSCustomObject]@{
                                Role   = $roleName
                                Type   = 'Active'
                                Status = "Failed: $($_.Exception.Message)"
                            })
                    }
                }
            }

            # 2. Remove Eligible Assignments (unifiedRoleEligibilityScheduleInstances)
            Write-PSFMessage -Level Verbose -Message "Checking Eligible Assignments..."
            $eligibleFilter = "principalId eq '$UserId'"
            if ($RoleDefinitionId) {
                $eligibleFilter += " and roleDefinitionId eq '$RoleDefinitionId'"
            }

            $eligibleAssignments = Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter $eligibleFilter -ExpandProperty roleDefinition -All -ErrorAction Stop

            foreach ($assignment in $eligibleAssignments) {
                $roleName = $assignment.RoleDefinition.DisplayName
                if ($PSCmdlet.ShouldProcess("Eligible Assignment: $roleName", "Remove")) {
                    try {
                        if ($assignment.RoleEligibilityScheduleId) {
                            Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule -UnifiedRoleEligibilityScheduleId $assignment.RoleEligibilityScheduleId -ErrorAction Stop
                            
                            $results.Add([PSCustomObject]@{
                                    Role   = $roleName
                                    Type   = 'Eligible'
                                    Status = 'Removed'
                                })
                        }
                    }
                    catch {
                        $results.Add([PSCustomObject]@{
                                Role   = $roleName
                                Type   = 'Eligible'
                                Status = "Failed: $($_.Exception.Message)"
                            })
                    }
                }
            }

            return $results
        }
        catch {
            Stop-PSFFunction -Message "Failed to remove PIM eligibility: $($_.Exception.Message)" -ErrorRecord $_ -EnableException $true
        }
    }
}

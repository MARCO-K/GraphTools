function Remove-GTPIMRoleEligibility {
    <#
    .SYNOPSIS
    Removes both active and eligible PIM role assignments for a user.

    .DESCRIPTION
    This function removes Privileged Identity Management (PIM) role assignments.
    It targets both:
    1. Active assignments (unifiedRoleAssignmentScheduleInstances)
    2. Eligible assignments (unifiedRoleEligibilityScheduleInstances)

    .PARAMETER UserId
    The Object ID (GUID) of the user to remove roles from.

    .PARAMETER RoleDefinitionId
    Optional. The Object ID (GUID) of a specific role definition to remove.
    If not specified, ALL PIM assignments for the user will be removed.
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

        # 1. Scopes Check (CRITICAL FIX)
        # PIM splits permissions between "Assignment" (Active) and "Eligibility" (Eligible).
        # You must have BOTH ReadWrite permissions to clean up a user completely.
        $requiredScopes = @(
            'RoleAssignmentSchedule.ReadWrite.Directory', 
            'RoleEligibilitySchedule.ReadWrite.Directory',
            'User.Read' # For the self-protection check
        )
        
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet)) {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }

        # 2. Validation (Gold Standard)
        # Validate UserId
        Test-GTGuid -InputObject $UserId

        # Validate RoleDefinitionId if provided (Prevents OData injection)
        if ($RoleDefinitionId) {
            Test-GTGuid -InputObject $RoleDefinitionId
        }

        # 3. Self-Protection Check
        try {
            $context = Get-MgContext
            if ($context.AuthType -eq 'Delegated') {
                $me = Get-MgUser -UserId 'me' -Property Id -ErrorAction Stop
                if ($me.Id -eq $UserId) {
                    Write-Warning "You are attempting to remove PIM roles from YOURSELF. Proceed with caution."
                    if (-not $PSCmdlet.ShouldProcess("YOURSELF ($UserId)", "Remove PIM Roles")) {
                        # If user says "No", we return a special empty object or just exit
                        return
                    }
                }
            }
        }
        catch {
            Write-Verbose "Could not verify self-protection (likely App-only context). Proceeding."
        }
    }

    process {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        # --- Helper to process removals to avoid code duplication ---
        $ProcessRemoval = {
            param($Assignment, $Type)
            
            $roleName = $Assignment.RoleDefinition.DisplayName
            $targetDesc = "$Type Assignment: $roleName (User: $UserId)"
            
            if ($PSCmdlet.ShouldProcess($targetDesc, "Remove")) {
                try {
                    if ($Type -eq 'Active') {
                        # Revoke Active Assignment
                        Remove-MgBetaRoleManagementDirectoryRoleAssignmentSchedule -UnifiedRoleAssignmentScheduleId $Assignment.RoleAssignmentScheduleId -ErrorAction Stop
                    }
                    else {
                        # Revoke Eligible Assignment
                        Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule -UnifiedRoleEligibilityScheduleId $Assignment.RoleEligibilityScheduleId -ErrorAction Stop
                    }

                    $results.Add([PSCustomObject]@{
                            Role   = $roleName
                            Type   = $Type
                            Status = 'Success'
                            Reason = 'Removed successfully'
                        })
                }
                catch {
                    # Use centralized error helper for inner loop failures
                    $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'PIM Assignment'
                    Write-PSFMessage -Level $err.LogLevel -Message "Failed to remove $Type assignment for $($roleName) : $($err.Reason)"
                    
                    $results.Add([PSCustomObject]@{
                            Role   = $roleName
                            Type   = $Type
                            Status = 'Failed'
                            Reason = $err.Reason
                        })
                }
            }
        }

        try {
            # 1. Remove Active Assignments
            Write-PSFMessage -Level Verbose -Message "Checking Active Assignments..."
            $activeFilter = "principalId eq '$UserId'"
            if ($RoleDefinitionId) { $activeFilter += " and roleDefinitionId eq '$RoleDefinitionId'" }
            
            # Note: We must expand roleDefinition to get the friendly name for logging
            $activeAssignments = Get-MgBetaRoleManagementDirectoryRoleAssignmentScheduleInstance -Filter $activeFilter -ExpandProperty roleDefinition -All -ErrorAction Stop
            
            foreach ($assignment in $activeAssignments) {
                # Only attempt to remove if there is a ScheduleId (Permanent/Direct assignments might differ)
                if ($assignment.RoleAssignmentScheduleId) {
                    & $ProcessRemoval -Assignment $assignment -Type 'Active'
                }
                else {
                    Write-PSFMessage -Level Warning -Message "Skipping Active role '$($assignment.RoleDefinition.DisplayName)' - No ScheduleID found. This might be a direct directory role, not PIM."
                }
            }

            # 2. Remove Eligible Assignments
            Write-PSFMessage -Level Verbose -Message "Checking Eligible Assignments..."
            $eligibleFilter = "principalId eq '$UserId'"
            if ($RoleDefinitionId) { $eligibleFilter += " and roleDefinitionId eq '$RoleDefinitionId'" }

            $eligibleAssignments = Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter $eligibleFilter -ExpandProperty roleDefinition -All -ErrorAction Stop

            foreach ($assignment in $eligibleAssignments) {
                if ($assignment.RoleEligibilityScheduleId) {
                    & $ProcessRemoval -Assignment $assignment -Type 'Eligible'
                }
            }

            return $results
        }
        catch {
            # Centralized Error Handling for the main block
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'PIM Operation'
            Write-PSFMessage -Level $err.LogLevel -Message "Critical failure in PIM removal: $($err.Reason)"
            
            # Re-throw if it's a critical setup failure
            throw $err.ErrorMessage
        }
    }
}
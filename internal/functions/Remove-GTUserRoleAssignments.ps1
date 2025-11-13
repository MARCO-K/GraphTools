function Remove-GTUserRoleAssignments
{
    <#
    .SYNOPSIS
        Removes all directory role assignments from a user (privileged roles)
    .DESCRIPTION
        Removes privileged role assignments like Global Administrator, User Administrator, or other administrative roles.
        This is critical to prevent any residual administrative access.
    .PARAMETER User
        The user object (must have Id and UserPrincipalName properties)
    .PARAMETER OutputBase
        Base output object for logging
    .PARAMETER Results
        Results collection to add output to
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            if ($_.Id -and $_.UserPrincipalName) {
                $true
            } else {
                throw "User object must have 'Id' and 'UserPrincipalName' properties"
            }
        })]
        [object]$User,
        [Parameter(Mandatory = $true)]
        [hashtable]$OutputBase,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[PSObject]]$Results
    )

    try
    {
        $roleAssignments = Get-MgBetaRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$($User.Id)'" -ExpandProperty roleDefinition -All -ErrorAction Stop
        
        if ($roleAssignments)
        {
            foreach ($roleAssignment in $roleAssignments)
            {
                $action = 'RemoveRoleAssignment'
                $output = $OutputBase + @{
                    ResourceName = $roleAssignment.RoleDefinition.DisplayName
                    ResourceType = 'DirectoryRole'
                    ResourceId   = $roleAssignment.Id
                    Action       = $action
                }

                try
                {
                    if ($PSCmdlet.ShouldProcess($roleAssignment.RoleDefinition.DisplayName, $action))
                    {
                        Write-PSFMessage -Level Verbose -Message "Removing role assignment $($roleAssignment.RoleDefinition.DisplayName) from user $($User.UserPrincipalName)"
                        Remove-MgBetaRoleManagementDirectoryRoleAssignment -UnifiedRoleAssignmentId $roleAssignment.Id -ErrorAction Stop
                        $output['Status'] = 'Success'
                    }
                }
                catch
                {
                    Write-PSFMessage -Level Error -Message "Failed to remove role assignment $($roleAssignment.RoleDefinition.DisplayName) from user $($User.UserPrincipalName)."
                    $output['Status'] = "Failed: $($_.Exception.Message)"
                }
                $Results.Add([PSCustomObject]$output)
            }
        }
        else
        {
            Write-PSFMessage -Level Verbose -Message "No role assignments found for user $($User.UserPrincipalName)"
        }
    }
    catch
    {
        Write-PSFMessage -Level Error -Message "Failed to retrieve role assignments for user $($User.UserPrincipalName)."
        $output = $OutputBase + @{
            ResourceName = 'RoleAssignments'
            ResourceType = 'DirectoryRole'
            ResourceId   = $null
            Action       = 'RemoveRoleAssignment'
            Status       = "Failed: $($_.Exception.Message)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

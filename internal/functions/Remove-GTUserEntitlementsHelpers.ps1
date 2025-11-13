<#
.SYNOPSIS
    Helper functions for Remove-GTUserEntitlements cmdlet
.DESCRIPTION
    Contains all helper functions used by Remove-GTUserEntitlements to remove various user entitlements
#>

function Remove-GTUserGroupMemberships
{
    <#
    .SYNOPSIS
        Removes user from all group memberships
    .PARAMETER User
        The user object
    .PARAMETER OutputBase
        Base output object for logging
    .PARAMETER Results
        Results collection to add output to
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$User,
        [Parameter(Mandatory = $true)]
        [hashtable]$OutputBase,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[PSObject]]$Results
    )

    $Groups = Get-MgBetaUserTransitiveMemberOfAsGroup -UserId $User.Id -All -ErrorAction Stop | Where-Object { $_.GroupTypes -ne 'DynamicMembership' }
    foreach ($Group in $Groups)
    {
        $action = 'RemoveGroupMembership'
        $output = $OutputBase + @{
            ResourceName = $Group.DisplayName
            ResourceType = 'Group'
            ResourceId   = $Group.Id
            Action       = $action
        }

        try
        {
            if ($PSCmdlet.ShouldProcess($Group.DisplayName, $action))
            {
                Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from group $($Group.DisplayName)"
                Remove-MgBetaGroupMemberByRef -GroupId $Group.Id -DirectoryObjectId $User.Id -ErrorAction Stop
                $output['Status'] = 'Success'
            }
        }
        catch
        {
            Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from group $($Group.DisplayName)."
            $output['Status'] = "Failed: $($_.Exception.Message)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

function Remove-GTUserGroupOwnerships
{
    <#
    .SYNOPSIS
        Removes user from all group ownerships
    .PARAMETER User
        The user object
    .PARAMETER OutputBase
        Base output object for logging
    .PARAMETER Results
        Results collection to add output to
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$User,
        [Parameter(Mandatory = $true)]
        [hashtable]$OutputBase,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[PSObject]]$Results
    )

    $OwnedGroups = Get-MgBetaUserOwnedObject -UserId $User.Id -All | 
    Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' }
    
    foreach ($Group in $OwnedGroups)
    {
        $action = 'RemoveGroupOwnership'
        $output = $OutputBase + @{
            ResourceName = $Group.AdditionalProperties.displayName
            ResourceType = 'Group'
            ResourceId   = $Group.Id
            Action       = $action
        }

        try
        {
            $owners = Get-MgBetaGroupOwner -GroupId $Group.Id -All -ErrorAction Stop
            if ($owners.Count -eq 1)
            {
                Write-PSFMessage -Level Verbose -Message "Skipping last owner ($($User.Id)) of group $($Group.Id)"
                $output['Status'] = 'Skipped: Last owner'
                $Results.Add([PSCustomObject]$output)
                continue
            }

            if ($PSCmdlet.ShouldProcess($Group.AdditionalProperties.displayName, $action))
            {
                Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from groupowner $($Group.DisplayName)"
                Remove-MgBetaGroupOwnerByRef -GroupId $Group.Id -DirectoryObjectId $User.Id -ErrorAction Stop
                $output['Status'] = 'Success'
            }
        }
        catch
        {
            Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from groupowner $($Group.DisplayName)."
            $output['Status'] = "Failed: $($_.Exception.Message)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

function Remove-GTUserLicenses
{
    <#
    .SYNOPSIS
        Removes all licenses from a user
    .PARAMETER User
        The user object
    .PARAMETER OutputBase
        Base output object for logging
    .PARAMETER Results
        Results collection to add output to
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$User,
        [Parameter(Mandatory = $true)]
        [hashtable]$OutputBase,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[PSObject]]$Results
    )

    $licenses = Get-MgBetaUserLicenseDetail -UserId $User.Id -ErrorAction Stop
    if ($licenses)
    {
        $action = 'RemoveLicenses'
        $output = $OutputBase + @{
            ResourceName = 'Licenses'
            ResourceType = 'License'
            ResourceId   = ($licenses.SkuPartNumber -join ', ')
            Action       = $action
        }

        try
        {
            if ($PSCmdlet.ShouldProcess($User.UserPrincipalName, $action))
            {
                Write-PSFMessage -Level Verbose -Message "Removing licenses from user $($User.UserPrincipalName)"
                Set-MgBetaUserLicense -UserId $User.Id -AddLicenses @() -RemoveLicenses @($licenses.SkuId) -ErrorAction Stop
                $output['Status'] = 'Success'
            }
        }
        catch
        {
            Write-PSFMessage -Level Error -Message "Failed to remove licenses from user $($User.UserPrincipalName)."
            $output['Status'] = "Failed: $($_.Exception.Message)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

function Remove-GTUserServicePrincipalOwnerships
{
    <#
    .SYNOPSIS
        Removes user from service principal ownerships
    .PARAMETER User
        The user object
    .PARAMETER OutputBase
        Base output object for logging
    .PARAMETER Results
        Results collection to add output to
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$User,
        [Parameter(Mandatory = $true)]
        [hashtable]$OutputBase,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[PSObject]]$Results
    )

    $servicePrincipals = Get-MgBetaServicePrincipal -Filter "owners/`$count eq 1" -CountVariable CountVar -Property 'id,displayName,owners' -ConsistencyLevel 'eventual'
    
    if ($global:CountVar -gt 0)
    {
        foreach ($sp in $servicePrincipals)
        {
            $action = 'RemoveServicePrincipalOwnership'
            $output = $OutputBase + @{
                ResourceName = $sp.DisplayName
                ResourceType = 'ServicePrincipal'
                ResourceId   = $sp.Id
                Action       = $action
            }

            try
            {
                if ($PSCmdlet.ShouldProcess($sp.DisplayName, $action))
                {
                    Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from service principal $($sp.DisplayName)"
                    Remove-MgBetaServicePrincipalOwnerByRef -ServicePrincipalId $sp.Id -DirectoryObjectId $User.Id -ErrorAction Stop
                    $output['Status'] = 'Success'
                }
            }
            catch
            {
                Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from service principal $($sp.Id)."
                $output['Status'] = "Failed: $($_.Exception.Message)"
            }
            $Results.Add([PSCustomObject]$output)
        }
    }
    else
    {
        Write-PSFMessage -Level Verbose -Message "No service principals found for user $($User.UserPrincipalName)"
    }
}

function Remove-GTUserAppRoleAssignments
{
    <#
    .SYNOPSIS
        Removes all app role assignments from a user
    .DESCRIPTION
        Explicitly removes any direct or group-based application role assignments to ensure 
        the user loses access to specific applications and their functionalities.
    .PARAMETER User
        The user object
    .PARAMETER OutputBase
        Base output object for logging
    .PARAMETER Results
        Results collection to add output to
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$User,
        [Parameter(Mandatory = $true)]
        [hashtable]$OutputBase,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[PSObject]]$Results
    )

    try
    {
        $AppRoleAssignments = Get-MgBetaUserAppRoleAssignment -UserId $user.Id -All -ErrorAction Stop
        
        if ($null -ne $AppRoleAssignments)
        {
            $AppRoleAssignments | ForEach-Object {
                $action = 'RemoveUserAppRoleAssignments'
                $output = $OutputBase + @{
                    ResourceName = $_.ResourceDisplayName
                    ResourceType = 'UserAppRoleAssignment'
                    ResourceId   = $_.Id
                    Action       = $action
                }
                
                try
                {
                    if ($PSCmdlet.ShouldProcess($_.ResourceDisplayName, $action))
                    {
                        Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from AppRoleAssignments $($_.ResourceDisplayName)"
                        Remove-MgBetaUserAppRoleAssignment -AppRoleAssignmentID $_.Id -UserId $user.Id -ErrorAction Stop
                        $output['Status'] = 'Success'
                    }
                }
                catch
                { 
                    Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from AppRoleAssignments $($_.ResourceDisplayName)"
                    $output['Status'] = "Failed: $($_.Exception.Message)"
                }
                $Results.Add([PSCustomObject]$output)
            }
        }
        else
        {
            Write-PSFMessage -Level Verbose -Message "No app role assignments found for user $($User.UserPrincipalName)"
        }
    }
    catch
    {
        Write-PSFMessage -Level Error -Message "Failed to retrieve app role assignments for user $($User.UserPrincipalName)."
        $output = $OutputBase + @{
            ResourceName = 'AppRoleAssignments'
            ResourceType = 'UserAppRoleAssignment'
            ResourceId   = $null
            Action       = 'RemoveUserAppRoleAssignments'
            Status       = "Failed: $($_.Exception.Message)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

function Remove-GTUserRoleAssignments
{
    <#
    .SYNOPSIS
        Removes all directory role assignments from a user (privileged roles)
    .DESCRIPTION
        Removes privileged role assignments like Global Administrator, User Administrator, or other administrative roles.
        This is critical to prevent any residual administrative access.
    .PARAMETER User
        The user object
    .PARAMETER OutputBase
        Base output object for logging
    .PARAMETER Results
        Results collection to add output to
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
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



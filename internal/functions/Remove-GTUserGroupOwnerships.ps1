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

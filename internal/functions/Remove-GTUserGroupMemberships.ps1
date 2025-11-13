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

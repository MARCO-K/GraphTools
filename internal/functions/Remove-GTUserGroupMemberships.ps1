function Remove-GTUserGroupMemberships
{
    <#
    .SYNOPSIS
        Removes user from all group memberships
    .DESCRIPTION
        Removes the user from all group memberships (excluding dynamic groups which cannot be manually managed).
        This is typically used during offboarding or security incident response to revoke access granted through group membership.
        
        This is an internal helper function used by Remove-GTUserEntitlements.
    .PARAMETER User
        The user object (must have Id and UserPrincipalName properties)
    .PARAMETER OutputBase
        Base output object for logging
    .PARAMETER Results
        Results collection to add output to
    .EXAMPLE
        $user = Get-MgBetaUser -UserId 'user@contoso.com'
        $outputBase = @{ UserPrincipalName = $user.UserPrincipalName }
        $results = [System.Collections.Generic.List[PSObject]]::new()
        Remove-GTUserGroupMemberships -User $user -OutputBase $outputBase -Results $results
        
        Removes the user from all group memberships and adds results to the collection
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

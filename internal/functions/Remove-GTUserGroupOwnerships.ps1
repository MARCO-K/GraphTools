function Remove-GTUserGroupOwnerships
{
    <#
    .SYNOPSIS
        Removes user from all group ownerships
    .DESCRIPTION
        Removes the user from ownership of all groups they own. Group owners have
        administrative control over group membership and settings.
        
        The function skips groups where the user is the last owner to prevent orphaned groups.
        This is typically used during offboarding or security incident response.
        
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
        Remove-GTUserGroupOwnerships -User $user -OutputBase $outputBase -Results $results
        
        Removes the user from all group ownerships and adds results to the collection
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
            # Use centralized error handling helper to parse Graph API exceptions
            $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'resource'
            
            # Log appropriate message based on error details
            if ($errorDetails.HttpStatus) {
                Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to remove user $($User.UserPrincipalName) from groupowner $($Group.DisplayName). $($errorDetails.Reason)"
                if ($errorDetails.HttpStatus -in 404, 403) {
                    Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
                }
            }
            else {
                Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from groupowner $($Group.DisplayName). $($errorDetails.ErrorMessage)"
            }
            $output['Status'] = "Failed: $($errorDetails.Reason)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

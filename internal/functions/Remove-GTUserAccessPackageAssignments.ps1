function Remove-GTUserAccessPackageAssignments
{
    <#
    .SYNOPSIS
        Removes user's active access package assignments
    .DESCRIPTION
        Removes all active access package assignments for the user. Access packages grant collections of resources
        including group memberships, application roles, and SharePoint site access. Removing these assignments
        ensures the user loses all access granted through Entitlement Management.
        
        This is critical for organizations using Identity Governance and Entitlement Management, as access packages
        can grant broad access to multiple resources through a single assignment.
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
        # Get all access package assignments for the user
        $assignments = Get-MgBetaEntitlementManagementAssignment -Filter "targetId eq '$($User.Id)' and state eq 'Delivered'" -ExpandProperty accessPackage -All -ErrorAction Stop
        
        if ($assignments)
        {
            foreach ($assignment in $assignments)
            {
                $action = 'RemoveAccessPackageAssignment'
                $accessPackageName = $assignment.AccessPackage.DisplayName
                
                $output = $OutputBase + @{
                    ResourceName = $accessPackageName
                    ResourceType = 'AccessPackageAssignment'
                    ResourceId   = $assignment.Id
                    Action       = $action
                }

                try
                {
                    if ($PSCmdlet.ShouldProcess($accessPackageName, $action))
                    {
                        Write-PSFMessage -Level Verbose -Message "Removing access package assignment '$accessPackageName' for user $($User.UserPrincipalName)"
                        
                        # Create an assignment request to remove the assignment
                        $requestParams = @{
                            RequestType = "adminRemove"
                            Assignment = @{
                                Id = $assignment.Id
                            }
                        }
                        
                        New-MgBetaEntitlementManagementAssignmentRequest -BodyParameter $requestParams -ErrorAction Stop
                        $output['Status'] = 'Success'
                        
                        Write-PSFMessage -Level Verbose -Message "Successfully created removal request for access package '$accessPackageName'"
                    }
                }
                catch
                {
                    Write-PSFMessage -Level Error -Message "Failed to remove access package assignment '$accessPackageName' for user $($User.UserPrincipalName)."
                    $output['Status'] = "Failed: $($_.Exception.Message)"
                }
                $Results.Add([PSCustomObject]$output)
            }
        }
        else
        {
            Write-PSFMessage -Level Verbose -Message "No active access package assignments found for user $($User.UserPrincipalName)"
        }
    }
    catch
    {
        Write-PSFMessage -Level Error -Message "Failed to retrieve access package assignments for user $($User.UserPrincipalName)."
        $output = $OutputBase + @{
            ResourceName = 'AccessPackageAssignments'
            ResourceType = 'AccessPackageAssignment'
            ResourceId   = $null
            Action       = 'RemoveAccessPackageAssignment'
            Status       = "Failed: $($_.Exception.Message)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

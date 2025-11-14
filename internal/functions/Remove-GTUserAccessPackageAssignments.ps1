function Remove-GTUserAccessPackageAssignments
{
    <#
    .SYNOPSIS
        Removes user's active access package assignments
    .DESCRIPTION
        Removes all active (delivered state) access package assignments for the user. Access packages grant
        collections of resources including group memberships, application roles, and SharePoint site access.
        Removing these assignments ensures the user loses all access granted through Entitlement Management.

        This function uses precise filtering with target/objectId and state='Delivered' to ensure only active
        assignments are targeted for removal. Each removal creates an adminRemove assignment request.

        This is critical for organizations using Identity Governance and Entitlement Management, as access packages
        can grant broad access to multiple resources through a single assignment.
    .PARAMETER User
        The user object (must have Id and UserPrincipalName properties)
    .PARAMETER OutputBase
        Base output object for logging
    .PARAMETER Results
        Results collection to add output to
    .EXAMPLE
        Remove-GTUserAccessPackageAssignments -User $userObject -OutputBase $baseOutput -Results $resultsList

        Removes all delivered access package assignments for the specified user
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
        # Validate that User.Id is a GUID to prevent OData injection
        Test-GTGuid -InputObject $User.Id | Out-Null
        
        # Get all access package assignments for the user with delivered state
        # Using filter with target/objectId for precise user matching
        $filter = "state eq 'Delivered' and target/objectId eq '$($User.Id)'"
        $assignments = Get-MgBetaEntitlementManagementAssignment -Filter $filter -ExpandProperty target,accessPackage -All -ErrorAction Stop

        if ($assignments)
        {
            foreach ($assignment in $assignments)
            {
                $action = 'RemoveAccessPackageAssignment'
                $accessPackageName = if ($assignment.AccessPackage.DisplayName) {
                    $assignment.AccessPackage.DisplayName
                } else {
                    "AccessPackage-$($assignment.AccessPackageId)"
                }

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
                        Write-PSFMessage -Level Verbose -Message "Removing access package assignment '$accessPackageName' (ID: $($assignment.Id)) for user $($User.UserPrincipalName)"

                        # Create an assignment request to remove the assignment
                        $params = @{
                            requestType = "adminRemove"
                            assignment = @{
                                id = $assignment.Id
                            }
                        }

                        New-MgBetaEntitlementManagementAssignmentRequest -BodyParameter $params -ErrorAction Stop
                        $output['Status'] = 'Success'

                        Write-PSFMessage -Level Verbose -Message "Successfully created removal request for access package '$accessPackageName'"
                    }
                }
                catch
                {
                    # Use centralized error handling helper to parse Graph API exceptions
                    $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'resource'
                    
                    # Log appropriate message based on error details
                    if ($errorDetails.HttpStatus -in 404, 403) {
                        Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to remove access package assignment '$accessPackageName' for user $($User.UserPrincipalName) - $($errorDetails.Reason)"
                        Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
                    }
                    elseif ($errorDetails.HttpStatus) {
                        Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to remove access package assignment '$accessPackageName' for user $($User.UserPrincipalName) - $($errorDetails.Reason)"
                    }
                    else {
                        Write-PSFMessage -Level Error -Message "Failed to remove access package assignment '$accessPackageName' for user $($User.UserPrincipalName). $($errorDetails.ErrorMessage)"
                    }
                    $output['Status'] = "Failed: $($errorDetails.Reason)"
                }
                $Results.Add([PSCustomObject]$output)
            }
        }
        else
        {
            Write-PSFMessage -Level Verbose -Message "No active (delivered) access package assignments found for user $($User.UserPrincipalName)"
        }
    }
    catch
    {
        # Use centralized error handling helper to parse Graph API exceptions
        $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'user'
        
        # Log appropriate message based on error details
        if ($errorDetails.HttpStatus -in 404, 403) {
            Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to retrieve access package assignments for user $($User.UserPrincipalName) - $($errorDetails.Reason)"
            Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
        }
        elseif ($errorDetails.HttpStatus) {
            Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to retrieve access package assignments for user $($User.UserPrincipalName) - $($errorDetails.Reason)"
        }
        else {
            Write-PSFMessage -Level Error -Message "Failed to retrieve access package assignments for user $($User.UserPrincipalName). $($errorDetails.ErrorMessage)"
        }
        $output = $OutputBase + @{
            ResourceName = 'AccessPackageAssignments'
            ResourceType = 'AccessPackageAssignment'
            ResourceId   = $null
            Action       = 'RemoveAccessPackageAssignment'
            Status       = "Failed: $($errorDetails.Reason)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

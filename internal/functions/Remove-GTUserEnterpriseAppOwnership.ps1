function Remove-GTUserEnterpriseAppOwnership
{
    <#
    .SYNOPSIS
        Removes user from Enterprise Applications and App Registrations ownerships
    .DESCRIPTION
        Removes the user from ownerships of Enterprise Applications (Service Principals) and App Registrations (Applications).
        This is critical as ownership grants significant control over application configurations and permissions.

        Note: This function will skip removing the user if they are the last owner. Best practice is to transfer
        ownership to an appropriate individual or group before removing the user's access.
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
        Remove-GTUserEnterpriseAppOwnership -User $user -OutputBase $outputBase -Results $results
        
        Removes the user from Enterprise Applications and App Registrations ownerships and adds results to the collection
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

    # Get all owned objects with a single API call
    try
    {
        $allOwnedObjects = Get-MgBetaUserOwnedObject -UserId $User.Id -All -ErrorAction Stop

        # Filter the results in memory
        $ownedApplications = $allOwnedObjects | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.application' }
        $ownedServicePrincipals = $allOwnedObjects | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.servicePrincipal' }
    }
    catch
    {
        # Handle failure to get any owned objects
        # Use centralized error handling helper to parse Graph API exceptions
        $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'user'
        
        # Log appropriate message based on error details
        if ($errorDetails.HttpStatus -in 404, 403) {
            Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to retrieve owned objects for user $($User.UserPrincipalName) - $($errorDetails.Reason)"
            Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
        }
        elseif ($errorDetails.HttpStatus) {
            Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to retrieve owned objects for user $($User.UserPrincipalName) - $($errorDetails.Reason)"
        }
        else {
            Write-PSFMessage -Level Error -Message "Failed to retrieve owned objects for user $($User.UserPrincipalName). $($errorDetails.ErrorMessage)"
        }
        $output = $OutputBase + @{
            ResourceName = 'OwnedObjects'
            ResourceType = 'All'
            ResourceId   = $null
            Action       = 'RetrieveOwnedObjects'
            Status       = "Failed: $($errorDetails.Reason)"
        }
        $Results.Add([PSCustomObject]$output)
        return
    }

    # Process App Registrations (Applications)
    if ($ownedApplications)
    {
        foreach ($app in $ownedApplications)
        {
            $action = 'RemoveAppRegistrationOwnership'
            $output = $OutputBase + @{
                ResourceName = $app.AdditionalProperties.displayName
                ResourceType = 'AppRegistration'
                ResourceId   = $app.Id
                Action       = $action
            }

            try
            {
                # Check if user is the last owner
                $owners = Get-MgBetaApplicationOwner -ApplicationId $app.Id -All -ErrorAction Stop
                if ($owners.Count -eq 1)
                {
                    Write-PSFMessage -Level Warning -Message "Skipping last owner ($($User.UserPrincipalName)) of App Registration: $($app.AdditionalProperties.displayName). Transfer ownership first."
                    $output['Status'] = 'Skipped: Last owner - transfer ownership first'
                    $Results.Add([PSCustomObject]$output)
                    continue
                }

                if ($PSCmdlet.ShouldProcess($app.AdditionalProperties.displayName, $action))
                {
                    Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from App Registration ownership: $($app.AdditionalProperties.displayName)"
                    Remove-MgBetaApplicationOwnerByRef -ApplicationId $app.Id -DirectoryObjectId $User.Id -ErrorAction Stop
                    $output['Status'] = 'Success'
                }
            }
            catch
            {
                # Use centralized error handling helper to parse Graph API exceptions
                $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'resource'
                
                # Log appropriate message based on error details
                if ($errorDetails.HttpStatus -in 404, 403) {
                    Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to remove user $($User.UserPrincipalName) from App Registration: $($app.AdditionalProperties.displayName) - $($errorDetails.Reason)"
                    Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
                }
                elseif ($errorDetails.HttpStatus) {
                    Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to remove user $($User.UserPrincipalName) from App Registration: $($app.AdditionalProperties.displayName) - $($errorDetails.Reason)"
                }
                else {
                    Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from App Registration: $($app.AdditionalProperties.displayName). $($errorDetails.ErrorMessage)"
                }
                $output['Status'] = "Failed: $($errorDetails.Reason)"
            }
            $Results.Add([PSCustomObject]$output)
        }
    }
    else
    {
        Write-PSFMessage -Level Verbose -Message "No App Registration ownerships found for user $($User.UserPrincipalName)"
    }

    # Process Enterprise Applications (Service Principals)
    if ($ownedServicePrincipals)
    {
        foreach ($sp in $ownedServicePrincipals)
        {
            $action = 'RemoveEnterpriseAppOwnership'
            $output = $OutputBase + @{
                ResourceName = $sp.AdditionalProperties.displayName
                ResourceType = 'EnterpriseApplication'
                ResourceId   = $sp.Id
                Action       = $action
            }

            try
            {
                # Check if user is the last owner
                $owners = Get-MgBetaServicePrincipalOwner -ServicePrincipalId $sp.Id -All -ErrorAction Stop
                if ($owners.Count -eq 1)
                {
                    Write-PSFMessage -Level Warning -Message "Skipping last owner ($($User.UserPrincipalName)) of Enterprise Application: $($sp.AdditionalProperties.displayName). Transfer ownership first."
                    $output['Status'] = 'Skipped: Last owner - transfer ownership first'
                    $Results.Add([PSCustomObject]$output)
                    continue
                }

                if ($PSCmdlet.ShouldProcess($sp.AdditionalProperties.displayName, $action))
                {
                    Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from Enterprise Application ownership: $($sp.AdditionalProperties.displayName)"
                    Remove-MgBetaServicePrincipalOwnerByRef -ServicePrincipalId $sp.Id -DirectoryObjectId $User.Id -ErrorAction Stop
                    $output['Status'] = 'Success'
                }
            }
            catch
            {
                # Use centralized error handling helper to parse Graph API exceptions
                $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'resource'
                
                # Log appropriate message based on error details
                if ($errorDetails.HttpStatus -in 404, 403) {
                    Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to remove user $($User.UserPrincipalName) from Enterprise Application: $($sp.AdditionalProperties.displayName) - $($errorDetails.Reason)"
                    Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
                }
                elseif ($errorDetails.HttpStatus) {
                    Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to remove user $($User.UserPrincipalName) from Enterprise Application: $($sp.AdditionalProperties.displayName) - $($errorDetails.Reason)"
                }
                else {
                    Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from Enterprise Application: $($sp.AdditionalProperties.displayName). $($errorDetails.ErrorMessage)"
                }
                $output['Status'] = "Failed: $($errorDetails.Reason)"
            }
            $Results.Add([PSCustomObject]$output)
        }
    }
    else
    {
        Write-PSFMessage -Level Verbose -Message "No Enterprise Application ownerships found for user $($User.UserPrincipalName)"
    }
}

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
        [ValidateScript({ Test-GTUserObject -User $_ })]
        [object]$User,
        [Parameter(Mandatory = $true)]
        [hashtable]$OutputBase,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[PSObject]]$Results
    )

    # Get all owned objects with a single API call
    try
    {
        $allOwnedObjects = Invoke-GTGraphPagedRequest -Uri "v1.0/users/$($User.Id)/ownedObjects?`$select=id,displayName"

        # Filter the results in memory
        $ownedApplications = $allOwnedObjects | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.application' }
        $ownedServicePrincipals = $allOwnedObjects | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.servicePrincipal' }
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

    # Bolt Optimization: Batch fetch owners to eliminate N+1 queries.
    $allOwnersCountMap = @{}
    $batchRequests = [System.Collections.Generic.List[hashtable]]::new()

    if ($ownedApplications) {
        foreach ($app in $ownedApplications) {
            $batchRequests.Add(@{
                id     = "app_$($app.id)"
                method = 'GET'
                # Use $count=true and $top=1 to minimize data transfer if supported, or just select=id
                url    = "v1.0/applications/$($app.id)/owners?`$select=id"
            })
        }
    }

    if ($ownedServicePrincipals) {
        foreach ($sp in $ownedServicePrincipals) {
            $batchRequests.Add(@{
                id     = "sp_$($sp.id)"
                method = 'GET'
                url    = "v1.0/servicePrincipals/$($sp.id)/owners?`$select=id"
            })
        }
    }

    if ($batchRequests.Count -gt 0) {
        try {
            $batchResponses = Invoke-GTGraphBatch -Requests $batchRequests
            foreach ($response in $batchResponses) {
                if ($response.Status -ge 200 -and $response.Status -lt 300 -and $null -ne $response.Body.value) {
                    $allOwnersCountMap[$response.Id] = $response.Body.value.Count
                }
            }
        }
        catch {
            Write-PSFMessage -Level Warning -Message "Batch fetching owners failed. Falling back to individual requests. Details: $($_.Exception.Message)"
        }
    }

    # Process App Registrations (Applications)
    if ($ownedApplications)
    {
        foreach ($app in $ownedApplications)
        {
            $action = 'RemoveAppRegistrationOwnership'
            $output = $OutputBase + @{
                ResourceName = $app.displayName
                ResourceType = 'AppRegistration'
                ResourceId   = $app.id
                Action       = $action
            }

            try
            {
                # Check if user is the last owner
                $ownerCount = 0
                if ($allOwnersCountMap.ContainsKey("app_$($app.id)")) {
                    $ownerCount = $allOwnersCountMap["app_$($app.id)"]
                } else {
                    # Fallback to single API call if batch failed for some reason
                    $owners = Invoke-GTGraphPagedRequest -Uri "v1.0/applications/$($app.id)/owners?`$select=id"
                    $ownerCount = $owners.Count
                }

                if ($ownerCount -eq 1)
                {
                    Write-PSFMessage -Level Warning -Message "Skipping last owner ($($User.UserPrincipalName)) of App Registration: $($app.displayName). Transfer ownership first."
                    $output['Status'] = 'Skipped: Last owner - transfer ownership first'
                    $Results.Add([PSCustomObject]$output)
                    continue
                }

                if ($PSCmdlet.ShouldProcess($app.displayName, $action))
                {
                    Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from App Registration ownership: $($app.displayName)"
                    Invoke-GTGraphRequest -Method DELETE -Uri "v1.0/applications/$($app.id)/owners/$($User.Id)/`$ref" -ErrorAction Stop
                    $output['Status'] = 'Success'
                }
            }
            catch
            {
                # Use centralized error handling helper to parse Graph API exceptions
                $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'resource'

                # Log appropriate message based on error details
                if ($errorDetails.HttpStatus -in 404, 403) {
                    Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to remove user $($User.UserPrincipalName) from App Registration: $($app.displayName) - $($errorDetails.Reason)"
                    Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
                }
                elseif ($errorDetails.HttpStatus) {
                    Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to remove user $($User.UserPrincipalName) from App Registration: $($app.displayName) - $($errorDetails.Reason)"
                }
                else {
                    Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from App Registration: $($app.displayName). $($errorDetails.ErrorMessage)"
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
                ResourceName = $sp.displayName
                ResourceType = 'EnterpriseApplication'
                ResourceId   = $sp.id
                Action       = $action
            }

            try
            {
                # Check if user is the last owner
                $ownerCount = 0
                if ($allOwnersCountMap.ContainsKey("sp_$($sp.id)")) {
                    $ownerCount = $allOwnersCountMap["sp_$($sp.id)"]
                } else {
                    # Fallback to single API call if batch failed for some reason
                    $owners = Invoke-GTGraphPagedRequest -Uri "v1.0/servicePrincipals/$($sp.id)/owners?`$select=id"
                    $ownerCount = $owners.Count
                }

                if ($ownerCount -eq 1)
                {
                    Write-PSFMessage -Level Warning -Message "Skipping last owner ($($User.UserPrincipalName)) of Enterprise Application: $($sp.displayName). Transfer ownership first."
                    $output['Status'] = 'Skipped: Last owner - transfer ownership first'
                    $Results.Add([PSCustomObject]$output)
                    continue
                }

                if ($PSCmdlet.ShouldProcess($sp.displayName, $action))
                {
                    Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from Enterprise Application ownership: $($sp.displayName)"
                    Invoke-GTGraphRequest -Method DELETE -Uri "v1.0/servicePrincipals/$($sp.id)/owners/$($User.Id)/`$ref" -ErrorAction Stop
                    $output['Status'] = 'Success'
                }
            }
            catch
            {
                # Use centralized error handling helper to parse Graph API exceptions
                $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'resource'

                # Log appropriate message based on error details
                if ($errorDetails.HttpStatus -in 404, 403) {
                    Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to remove user $($User.UserPrincipalName) from Enterprise Application: $($sp.displayName) - $($errorDetails.Reason)"
                    Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
                }
                elseif ($errorDetails.HttpStatus) {
                    Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to remove user $($User.UserPrincipalName) from Enterprise Application: $($sp.displayName) - $($errorDetails.Reason)"
                }
                else {
                    Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from Enterprise Application: $($sp.displayName). $($errorDetails.ErrorMessage)"
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

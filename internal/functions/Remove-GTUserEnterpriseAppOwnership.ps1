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

    # Process App Registrations (Applications)
    try
    {
        $ownedApplications = Get-MgBetaUserOwnedObject -UserId $User.Id -All -ErrorAction Stop |
            Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.application' }

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
                    Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from App Registration: $($app.AdditionalProperties.displayName)."
                    $output['Status'] = "Failed: $($_.Exception.Message)"
                }
                $Results.Add([PSCustomObject]$output)
            }
        }
        else
        {
            Write-PSFMessage -Level Verbose -Message "No App Registration ownerships found for user $($User.UserPrincipalName)"
        }
    }
    catch
    {
        Write-PSFMessage -Level Error -Message "Failed to retrieve App Registration ownerships for user $($User.UserPrincipalName)."
        $output = $OutputBase + @{
            ResourceName = 'AppRegistrations'
            ResourceType = 'AppRegistration'
            ResourceId   = $null
            Action       = 'RemoveAppRegistrationOwnership'
            Status       = "Failed: $($_.Exception.Message)"
        }
        $Results.Add([PSCustomObject]$output)
    }

    # Process Enterprise Applications (Service Principals)
    try
    {
        $ownedServicePrincipals = Get-MgBetaUserOwnedObject -UserId $User.Id -All -ErrorAction Stop |
            Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.servicePrincipal' }

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
                    Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from Enterprise Application: $($sp.AdditionalProperties.displayName)."
                    $output['Status'] = "Failed: $($_.Exception.Message)"
                }
                $Results.Add([PSCustomObject]$output)
            }
        }
        else
        {
            Write-PSFMessage -Level Verbose -Message "No Enterprise Application ownerships found for user $($User.UserPrincipalName)"
        }
    }
    catch
    {
        Write-PSFMessage -Level Error -Message "Failed to retrieve Enterprise Application ownerships for user $($User.UserPrincipalName)."
        $output = $OutputBase + @{
            ResourceName = 'EnterpriseApplications'
            ResourceType = 'EnterpriseApplication'
            ResourceId   = $null
            Action       = 'RemoveEnterpriseAppOwnership'
            Status       = "Failed: $($_.Exception.Message)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

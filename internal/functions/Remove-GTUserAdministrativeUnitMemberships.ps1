function Remove-GTUserAdministrativeUnitMemberships
{
    <#
    .SYNOPSIS
        Removes user from all administrative unit memberships
    .DESCRIPTION
        Removes the user from all Administrative Units to revoke any scoped administrative rights they hold.
        Administrative Units are used to scope administrative permissions, and removing these memberships
        ensures the user loses any scoped administrative rights.
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
        # Get all administrative units where the user is a member
        $adminUnits = Get-MgBetaUserMemberOf -UserId $User.Id -All -ErrorAction Stop |
            Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.administrativeUnit' }

        if ($adminUnits)
        {
            foreach ($adminUnit in $adminUnits)
            {
                $action = 'RemoveAdministrativeUnitMembership'
                $output = $OutputBase + @{
                    ResourceName = $adminUnit.AdditionalProperties.displayName
                    ResourceType = 'AdministrativeUnit'
                    ResourceId   = $adminUnit.Id
                    Action       = $action
                }

                try
                {
                    if ($PSCmdlet.ShouldProcess($adminUnit.AdditionalProperties.displayName, $action))
                    {
                        Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from administrative unit $($adminUnit.AdditionalProperties.displayName)"
                        Remove-MgBetaDirectoryAdministrativeUnitMemberByRef -AdministrativeUnitId $adminUnit.Id -DirectoryObjectId $User.Id -ErrorAction Stop
                        $output['Status'] = 'Success'
                    }
                }
                catch
                {
                    Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from administrative unit $($adminUnit.AdditionalProperties.displayName)."
                    $output['Status'] = "Failed: $($_.Exception.Message)"
                }
                $Results.Add([PSCustomObject]$output)
            }
        }
        else
        {
            Write-PSFMessage -Level Verbose -Message "No administrative unit memberships found for user $($User.UserPrincipalName)"
        }
    }
    catch
    {
        Write-PSFMessage -Level Error -Message "Failed to retrieve administrative unit memberships for user $($User.UserPrincipalName)."
        $output = $OutputBase + @{
            ResourceName = 'AdministrativeUnits'
            ResourceType = 'AdministrativeUnit'
            ResourceId   = $null
            Action       = 'RemoveAdministrativeUnitMembership'
            Status       = "Failed: $($_.Exception.Message)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

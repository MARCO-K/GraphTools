function Remove-GTUserServicePrincipalOwnerships
{
    <#
    .SYNOPSIS
        Removes user from service principal ownerships
    .DESCRIPTION
        Removes the user from ownership of service principals (Enterprise Applications).
        Service principal owners have administrative control over the application's configuration.
        
        Note: This function is deprecated. Use Remove-GTUserEnterpriseAppOwnership instead,
        which provides better error handling and covers both App Registrations and Service Principals.
        
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
        Remove-GTUserServicePrincipalOwnerships -User $user -OutputBase $outputBase -Results $results
        
        Removes the user from service principal ownerships and adds results to the collection
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

    $servicePrincipals = Get-MgBetaServicePrincipal -Filter "owners/`$count eq 1" -CountVariable CountVar -Property 'id,displayName,owners' -ConsistencyLevel 'eventual'

    if ($global:CountVar -gt 0)
    {
        foreach ($sp in $servicePrincipals)
        {
            $action = 'RemoveServicePrincipalOwnership'
            $output = $OutputBase + @{
                ResourceName = $sp.DisplayName
                ResourceType = 'ServicePrincipal'
                ResourceId   = $sp.Id
                Action       = $action
            }

            try
            {
                if ($PSCmdlet.ShouldProcess($sp.DisplayName, $action))
                {
                    Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from service principal $($sp.DisplayName)"
                    Remove-MgBetaServicePrincipalOwnerByRef -ServicePrincipalId $sp.Id -DirectoryObjectId $User.Id -ErrorAction Stop
                    $output['Status'] = 'Success'
                }
            }
            catch
            {
                Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from service principal $($sp.Id)."
                $output['Status'] = "Failed: $($_.Exception.Message)"
            }
            $Results.Add([PSCustomObject]$output)
        }
    }
    else
    {
        Write-PSFMessage -Level Verbose -Message "No service principals found for user $($User.UserPrincipalName)"
    }
}

function Remove-GTUserServicePrincipalOwnerships
{
    <#
    .SYNOPSIS
        Removes user from service principal ownerships
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

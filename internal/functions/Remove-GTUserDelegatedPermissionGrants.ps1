function Remove-GTUserDelegatedPermissionGrants
{
    <#
    .SYNOPSIS
        Removes OAuth2 delegated permission grants for a user
    .DESCRIPTION
        Removes all OAuth2 permission grants (delegated permissions) that were granted to applications on behalf of the user.
        These are the permissions that applications have to act on behalf of the user, such as "Read user mail" or "Access user files".

        Delegated permissions are granted when a user consents to an application accessing resources on their behalf.
        Removing these grants revokes the application's ability to access resources using the user's identity.

        This is important for security as delegated permissions can provide applications with broad access to user data.
    .PARAMETER User
        The user object (must have Id and UserPrincipalName properties)
    .PARAMETER OutputBase
        Base output object for logging
    .PARAMETER Results
        Results collection to add output to
    .EXAMPLE
        Remove-GTUserDelegatedPermissionGrants -User $userObject -OutputBase $baseOutput -Results $resultsList

        Removes all OAuth2 permission grants (delegated permissions) for the specified user
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
        # Get all OAuth2 permission grants for the user
        # These are delegated permissions granted to apps on behalf of the user
        $permissionGrants = Get-MgBetaOauth2PermissionGrant -Filter "principalId eq '$($User.Id)'" -All -ErrorAction Stop

        if ($permissionGrants)
        {
            foreach ($grant in $permissionGrants)
            {
                $action = 'RemoveDelegatedPermissionGrant'

                # Get service principal details for better logging
                try
                {
                    $servicePrincipal = Get-MgBetaServicePrincipal -ServicePrincipalId $grant.ClientId -ErrorAction SilentlyContinue
                    $appName = if ($servicePrincipal) { $servicePrincipal.DisplayName } else { "App-$($grant.ClientId)" }
                }
                catch
                {
                    $appName = "App-$($grant.ClientId)"
                }

                $output = $OutputBase + @{
                    ResourceName = $appName
                    ResourceType = 'OAuth2PermissionGrant'
                    ResourceId   = $grant.Id
                    Action       = $action
                }

                try
                {
                    # Get the scope details for logging
                    $scopes = if ($grant.Scope) { $grant.Scope } else { "Default scopes" }

                    if ($PSCmdlet.ShouldProcess("$appName (Scopes: $scopes)", $action))
                    {
                        Write-PSFMessage -Level Verbose -Message "Removing delegated permission grant for application '$appName' from user $($User.UserPrincipalName). Scopes: $scopes"

                        Remove-MgBetaOauth2PermissionGrant -OAuth2PermissionGrantId $grant.Id -ErrorAction Stop
                        $output['Status'] = 'Success'

                        Write-PSFMessage -Level Verbose -Message "Successfully removed delegated permissions for '$appName'"
                    }
                }
                catch
                {
                    Write-PSFMessage -Level Error -Message "Failed to remove delegated permission grant for '$appName' from user $($User.UserPrincipalName). Error: $($_.Exception.Message)"
                    $output['Status'] = "Failed: $($_.Exception.Message)"
                }
                $Results.Add([PSCustomObject]$output)
            }
        }
        else
        {
            Write-PSFMessage -Level Verbose -Message "No delegated permission grants found for user $($User.UserPrincipalName)"
        }
    }
    catch
    {
        Write-PSFMessage -Level Error -Message "Failed to retrieve delegated permission grants for user $($User.UserPrincipalName)."
        $output = $OutputBase + @{
            ResourceName = 'DelegatedPermissionGrants'
            ResourceType = 'OAuth2PermissionGrant'
            ResourceId   = $null
            Action       = 'RemoveDelegatedPermissionGrant'
            Status       = "Failed: $($_.Exception.Message)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

function Remove-GTUserAppRoleAssignments
{
    <#
    .SYNOPSIS
        Removes all app role assignments from a user
    .DESCRIPTION
        Explicitly removes any direct or group-based application role assignments to ensure 
        the user loses access to specific applications and their functionalities.
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
        $AppRoleAssignments = Get-MgBetaUserAppRoleAssignment -UserId $user.Id -All -ErrorAction Stop
        
        if ($null -ne $AppRoleAssignments)
        {
            $AppRoleAssignments | ForEach-Object {
                $action = 'RemoveUserAppRoleAssignments'
                $output = $OutputBase + @{
                    ResourceName = $_.ResourceDisplayName
                    ResourceType = 'UserAppRoleAssignment'
                    ResourceId   = $_.Id
                    Action       = $action
                }
                
                try
                {
                    if ($PSCmdlet.ShouldProcess($_.ResourceDisplayName, $action))
                    {
                        Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from AppRoleAssignments $($_.ResourceDisplayName)"
                        Remove-MgBetaUserAppRoleAssignment -AppRoleAssignmentID $_.Id -UserId $user.Id -ErrorAction Stop
                        $output['Status'] = 'Success'
                    }
                }
                catch
                { 
                    Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from AppRoleAssignments $($_.ResourceDisplayName)"
                    $output['Status'] = "Failed: $($_.Exception.Message)"
                }
                $Results.Add([PSCustomObject]$output)
            }
        }
        else
        {
            Write-PSFMessage -Level Verbose -Message "No app role assignments found for user $($User.UserPrincipalName)"
        }
    }
    catch
    {
        Write-PSFMessage -Level Error -Message "Failed to retrieve app role assignments for user $($User.UserPrincipalName)."
        $output = $OutputBase + @{
            ResourceName = 'AppRoleAssignments'
            ResourceType = 'UserAppRoleAssignment'
            ResourceId   = $null
            Action       = 'RemoveUserAppRoleAssignments'
            Status       = "Failed: $($_.Exception.Message)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

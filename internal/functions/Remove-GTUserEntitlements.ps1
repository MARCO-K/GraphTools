<#
.SYNOPSIS
    Removes all user entitlements including group memberships, ownerships, licenses, role assignments, and service principal relationships
.DESCRIPTION
    Comprehensive removal of user access across multiple Microsoft 365 components including:
    - Group memberships
    - Group ownerships
    - Licenses
    - Service principal ownerships
    - User app role assignments (application access)
    - Directory role assignments (privileged roles)
    - Administrative unit memberships (scoped administrative rights)
.PARAMETER UserUPNs
    Array of user principal names to process. Must be valid email format (e.g., user@domain.com)
.PARAMETER removeGroups
    Remove user from all group memberships
.PARAMETER removeGroupOwners
    Remove user from all group ownerships
.PARAMETER removeLicenses
    Remove all licenses from the user
.PARAMETER removeServicePrincipals
    Remove user from service principal ownerships
.PARAMETER removeUserAppRoleAssignments
    Remove all user app role assignments to revoke access to specific applications
.PARAMETER removeRoleAssignments
    Remove all directory role assignments (privileged roles like Global Administrator)
.PARAMETER removeAdministrativeUnitMemberships
    Remove all administrative unit memberships to revoke scoped administrative rights
.PARAMETER removeAll
    Remove all types of entitlements
.EXAMPLE
    Remove-GTUserEntitlements -UserUPNs 'user1@contoso.com' -removeAll
    
    Removes all entitlements from the specified user
.EXAMPLE
    Remove-GTUserEntitlements -UserUPNs 'user1@contoso.com','user2@contoso.com' -removeGroups -removeLicenses
    
    Removes group memberships and licenses from multiple users
#>
function Remove-GTUserEntitlements
{
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateScript({$_ -match $script:GTValidationRegex.UPN})]
        [string[]]$UserUPNs,
        [switch]$removeGroups,
        [switch]$removeGroupOwners,
        [switch]$removeLicenses,
        [switch]$removeServicePrincipals,
        [switch]$removeUserAppRoleAssignments,
        [switch]$removeRoleAssignments,
        [switch]$removeAdministrativeUnitMemberships,
        [switch]$removeAll
    )

    begin
    {
        $results = [System.Collections.Generic.List[PSObject]]::new()
        
        # check for required scopes
        $RequieredScopes = @('GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'AdministrativeUnit.ReadWrite.All')
        $missingScopes = $RequieredScopes | Where-Object { $_ -notin (Get-MgContext).Scopes }
        if ($missingScopes)
        {
            throw "Required scopes are missing: $($missingScopes -join ', ')"
        }
        else { Write-PSFMessage -Level Verbose -Message "All required scopes are present" }

        # install required modules
        $requiremodules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Groups', 'Microsoft.Graph.Beta.Users', 'Microsoft.Graph.Beta.Applications', 'Microsoft.Graph.Beta.Users.Actions', 'Microsoft.Graph.Beta.Identity.Governance', 'Microsoft.Graph.Beta.Identity.DirectoryManagement')
        Install-GTRequiredModule -ModuleNames $requiremodules

    }

    process
    {
        foreach ($UPN in $UserUPNs)
        {
            try
            {
                $User = Get-MgBetaUser -UserId $UPN -ErrorAction Stop
                $outputBase = @{
                    UPN       = $UPN
                    UserId    = $User.Id
                    Timestamp = [datetime]::UtcNow
                }

                # 1. Remove Group Memberships
                if ($removeGroups -or $removeAll)
                {
                    Remove-GTUserGroupMemberships -User $User -OutputBase $outputBase -Results $results
                }

                # 2. Remove Group Ownerships
                if ($removeGroupOwners -or $removeAll)
                {
                    Remove-GTUserGroupOwnerships -User $User -OutputBase $outputBase -Results $results
                }

                # 3. Remove Licenses
                if ($removeLicenses -or $removeAll)
                {
                    Remove-GTUserLicenses -User $User -OutputBase $outputBase -Results $results
                }

                # 4. Remove Service Principal Ownerships
                if ($removeServicePrincipals -or $removeAll)
                {
                    Remove-GTUserServicePrincipalOwnerships -User $User -OutputBase $outputBase -Results $results
                }

                # 5. Remove UserAppRoleAssignment
                if ($removeUserAppRoleAssignments -or $removeAll)
                {
                    Remove-GTUserAppRoleAssignments -User $User -OutputBase $outputBase -Results $results
                }

                # 6. Remove Role Assignments (Privileged Roles)
                if ($removeRoleAssignments -or $removeAll)
                {
                    Remove-GTUserRoleAssignments -User $User -OutputBase $outputBase -Results $results
                }

                # 7. Remove Administrative Unit Memberships
                if ($removeAdministrativeUnitMemberships -or $removeAll)
                {
                    Remove-GTUserAdministrativeUnitMemberships -User $User -OutputBase $outputBase -Results $results
                }
            }
            catch
            {
                $results.Add([PSCustomObject]($outputBase + @{
                            ResourceName = 'UserLookup'
                            ResourceType = 'User'
                            ResourceId   = $null
                            Action       = 'UserRetrieval'
                            Status       = "Failed: $($_.Exception.Message)"
                        }))
            }
        }
    }

    end
    {
        return $results
    }
}


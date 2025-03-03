<#
.SYNOPSIS
    Removes all user entitlements including group memberships, ownerships, licenses, and service principal relationships
.DESCRIPTION
    Comprehensive removal of user access across multiple Microsoft 365 components
.PARAMETER UserUPNs
    Array of user principal names to process
.EXAMPLE
    Remove-UserEntitlements -UserUPNs "user1@contoso.com","user2@contoso.com"
#>
function Remove-GTUserEntitlements
{
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$UserUPNs
    )

    begin
    {
        $results = [System.Collections.Generic.List[PSObject]]::new()

        # install required modules
        $requiremodules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Groups', 'Microsoft.Graph.Beta.Users', 'Microsoft.Graph.Beta.Applications', 'Microsoft.Graph.Beta.Users.Actions')
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
                $Groups = Get-MgBetaUserTransitiveMemberOfAsGroup -UserId $User.Id -All -ErrorAction Stop
                foreach ($Group in $Groups)
                {
                    $action = "RemoveGroupMembership"
                    $output = $outputBase + @{
                        ResourceName = $Group.DisplayName
                        ResourceType = "Group"
                        ResourceId   = $Group.Id
                        Action       = $action
                    }

                    try
                    {
                        if ($PSCmdlet.ShouldProcess($Group.DisplayName, $action))
                        {
                            Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from group $($Group.DisplayName)"
                            Remove-MgBetaGroupMemberByRef -GroupId $Group.Id -DirectoryObjectId $User.Id -ErrorAction Stop
                            $output['Status'] = "Success"
                        }
                    }
                    catch
                    {
                        Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from group $($Group.DisplayName)."
                        $output['Status'] = "Failed: $($_.Exception.Message)"
                    }
                    $results.Add([PSCustomObject]$output)
                }

                # 2. Remove Group Ownerships
                $OwnedGroups = Get-MgBetaUserOwnedObject -UserId $User.Id -All | 
                Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' }
                
                foreach ($Group in $OwnedGroups)
                {
                    $action = "RemoveGroupOwnership"
                    $output = $outputBase + @{
                        ResourceName = $Group.AdditionalProperties.displayName
                        ResourceType = "Group"
                        ResourceId   = $Group.Id
                        Action       = $action
                    }

                    try
                    {
                        $owners = Get-MgBetaGroupOwner -GroupId $Group.Id -All -ErrorAction Stop
                        if ($owners.Count -eq 1)
                        {
                            Write-PSFMessage -Level Verbose -Message "Skipping last owner ($($User.Id)) of group $($Group.Id)"
                            $output['Status'] = "Skipped: Last owner"
                            continue
                        }

                        if ($PSCmdlet.ShouldProcess($Group.AdditionalProperties.displayName, $action))
                        {
                            Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from groupowner $($Group.DisplayName)"
                            Remove-MgBetaGroupOwnerByRef -GroupId $Group.Id -DirectoryObjectId $User.Id -ErrorAction Stop
                            $output['Status'] = "Success"
                        }
                    }
                    catch
                    {
                        Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from groupowner $($Group.DisplayName)."
                        $output['Status'] = "Failed: $($_.Exception.Message)"
                    }
                    $results.Add([PSCustomObject]$output)
                }

                # 3. Remove Licenses
                $licenses = Get-MgBetaUserLicenseDetail -UserId $User.Id -ErrorAction Stop
                if ($licenses)
                {
                    $action = "RemoveLicenses"
                    $output = $outputBase + @{
                        ResourceName = "Licenses"
                        ResourceType = "License"
                        ResourceId   = ($licenses.SkuId -join ", ")
                        Action       = $action
                    }

                    try
                    {
                        if ($PSCmdlet.ShouldProcess($UPN, $action))
                        {
                            Write-PSFMessage -Level Verbose -Message "Removing licenses from user $($User.UserPrincipalName)"
                            Set-MgBetaUserLicense -UserId $User.Id -AddLicenses @() -RemoveLicenses @($licenses.SkuId) -ErrorAction Stop
                            $output['Status'] = "Success"
                        }
                    }
                    catch
                    {
                        Write-PSFMessage -Level Error -Message "Failed to remove licenses from user $($User.UserPrincipalName)."
                        $output['Status'] = "Failed: $($_.Exception.Message)"
                    }
                    $results.Add([PSCustomObject]$output)
                }

                # 4. Remove Service Principal Ownerships
                $servicePrincipals = Get-MgBetaServicePrincipal -Filter "owners/any(o:o/id eq '$($User.Id)')" -All
                foreach ($sp in $servicePrincipals)
                {
                    $action = "RemoveServicePrincipalOwnership"
                    $output = $outputBase + @{
                        ResourceName = $sp.DisplayName
                        ResourceType = "ServicePrincipal"
                        ResourceId   = $sp.Id
                        Action       = $action
                    }

                    try
                    {
                        if ($PSCmdlet.ShouldProcess($sp.DisplayName, $action))
                        {
                            Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from service principal $($sp.DisplayName)"
                            Remove-MgBetaServicePrincipalOwnerByRef -ServicePrincipalId $sp.Id -DirectoryObjectId $User.Id -ErrorAction Stop
                            $output['Status'] = "Success"
                        }
                    }
                    catch
                    {
                        Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from service principal $($sp.Id)."
                        $output['Status'] = "Failed: $($_.Exception.Message)"
                    }
                    $results.Add([PSCustomObject]$output)
                }
            }
            catch
            {
                $results.Add([PSCustomObject]($outputBase + @{
                            ResourceName = "UserLookup"
                            ResourceType = "User"
                            ResourceId   = $null
                            Action       = "UserRetrieval"
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


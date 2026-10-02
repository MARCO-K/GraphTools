Describe "Remove-GTUserEntitlement" {
    BeforeAll {
        function global:Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function global:Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession) return $true }
        function global:Get-GTConnection { 
            return [PSCustomObject]@{
                Scopes = @('GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'RoleEligibilitySchedule.ReadWrite.Directory', 'AdministrativeUnit.ReadWrite.All', 'EntitlementManagement.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All')
            }
        }
        function global:Get-GTMissingScope { [Alias('Get-GTMissingScopes')] param($RequiredScopes, $CurrentScopes) 
            return @($RequiredScopes | Where-Object { $CurrentScopes -notcontains $_ })
        }
        function global:Test-GTGraphScope { [Alias('Test-GTGraphScopes')] param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } }
        function global:Invoke-GTGraphRequest { param($Uri, $Method = 'GET', $Body, $Headers, $ContentType, [switch]$All, [int]$MaxRetries, [int]$RetryBaseDelaySeconds, $Token, [switch]$Raw, $ErrorAction)
            return @{
                id = "test-user-id"
                userPrincipalName = "test@contoso.com"
            }
        }
        function global:Remove-GTUserGroupMembership { [Alias('Remove-GTUserGroupMemberships')] param($User, $OutputBase, $Results) }
        function global:Remove-GTUserGroupOwnership { [Alias('Remove-GTUserGroupOwnerships')] param($User, $OutputBase, $Results) }
        function global:Remove-GTUserLicense { [Alias('Remove-GTUserLicenses')] param($User, $OutputBase, $Results) }
        function global:Remove-GTUserServicePrincipalOwnership { [Alias('Remove-GTUserServicePrincipalOwnerships')] param($User, $OutputBase, $Results) }
        function global:Remove-GTUserEnterpriseAppOwnership { param($User, $OutputBase, $Results) }
        function global:Remove-GTUserAppRoleAssignment { [Alias('Remove-GTUserAppRoleAssignments')] param($User, $OutputBase, $Results) }
        function global:Remove-GTUserRoleAssignment { [Alias('Remove-GTUserRoleAssignments')] param($User, $OutputBase, $Results) }
        function global:Remove-GTPIMRoleEligibilityInternal { param($User, $OutputBase, $Results) }
        function global:Remove-GTUserAdministrativeUnitMembership { [Alias('Remove-GTUserAdministrativeUnitMemberships')] param($User, $OutputBase, $Results) }
        function global:Remove-GTUserAccessPackageAssignment { [Alias('Remove-GTUserAccessPackageAssignments')] param($User, $OutputBase, $Results) }
        function global:Remove-GTUserDelegatedPermissionGrant { [Alias('Remove-GTUserDelegatedPermissionGrants')] param($User, $OutputBase, $Results) }

        # Dot-source GTValidation for UPN regex
        . "$PSScriptRoot/../internal/functions/GTValidation.ps1"

        # Dot-source the function under test
        . "$PSScriptRoot/../functions/Remove-GTUserEntitlement.ps1"
    }

    AfterAll {
        Remove-Item Function:\Install-GTRequiredModule -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Initialize-GTGraphConnection -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-GTConnection -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-GTMissingScope -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Get-GTMissingScopes -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-GTGraphScope -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Test-GTGraphScopes -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Write-PSFMessage -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-GTGraphErrorDetails -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-GTGraphRequest -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-GTUserGroupMembership -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Remove-GTUserGroupMemberships -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-GTUserGroupOwnership -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Remove-GTUserGroupOwnerships -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-GTUserLicense -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Remove-GTUserLicenses -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-GTUserServicePrincipalOwnership -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Remove-GTUserServicePrincipalOwnerships -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-GTUserEnterpriseAppOwnership -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-GTUserAppRoleAssignment -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Remove-GTUserAppRoleAssignments -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-GTUserRoleAssignment -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Remove-GTUserRoleAssignments -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-GTPIMRoleEligibilityInternal -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-GTUserAdministrativeUnitMembership -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Remove-GTUserAdministrativeUnitMemberships -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-GTUserAccessPackageAssignment -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Remove-GTUserAccessPackageAssignments -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-GTUserDelegatedPermissionGrant -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Remove-GTUserDelegatedPermissionGrants -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-GTUserEntitlement -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Remove-GTUserEntitlements -Force -ErrorAction SilentlyContinue
    }

    Context "Alias Support" {
        It "resolves the legacy Remove-GTUserEntitlements alias to Remove-GTUserEntitlement" {
            (Get-Command Remove-GTUserEntitlements).ResolvedCommandName | Should -Be 'Remove-GTUserEntitlement'
        }
    }

    BeforeEach {
        Mock -CommandName Get-GTConnection -MockWith {
            [PSCustomObject]@{
                Scopes = @('GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'RoleEligibilitySchedule.ReadWrite.Directory', 'AdministrativeUnit.ReadWrite.All', 'EntitlementManagement.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All')
            }
        }
        Mock -CommandName Invoke-GTGraphRequest -MockWith {
            param($Uri, $Method)
            return [PSCustomObject]@{
                id                = "test-user-id"
                userPrincipalName = "test@contoso.com"
            }
        }
        Mock -CommandName Remove-GTUserGroupMembership -MockWith { }
        Mock -CommandName Remove-GTUserGroupOwnership -MockWith { }
        Mock -CommandName Remove-GTUserLicense -MockWith { }
        Mock -CommandName Remove-GTUserServicePrincipalOwnership -MockWith { }
        Mock -CommandName Remove-GTUserEnterpriseAppOwnership -MockWith { }
        Mock -CommandName Remove-GTUserAppRoleAssignment -MockWith { }
        Mock -CommandName Remove-GTUserRoleAssignment -MockWith { }
        Mock -CommandName Remove-GTPIMRoleEligibilityInternal -MockWith { }
        Mock -CommandName Remove-GTUserAdministrativeUnitMembership -MockWith { }
        Mock -CommandName Remove-GTUserAccessPackageAssignment -MockWith { }
        Mock -CommandName Remove-GTUserDelegatedPermissionGrant -MockWith { }
    }

    Context "Parameter Validation" {
        It "should throw an error for an invalid UPN (no @ symbol)" {
            { Remove-GTUserEntitlement -UserUPNs "invalid-user" -removeAll } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty local part)" {
            { Remove-GTUserEntitlement -UserUPNs "@domain.com" -removeAll } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty domain part)" {
            { Remove-GTUserEntitlement -UserUPNs "user@" -removeAll } | Should -Throw
        }

        It "should accept valid UPN format" {
            { Remove-GTUserEntitlement -UserUPNs "test@contoso.com" -removeAll -WhatIf } | Should -Not -Throw
        }

        It "should throw when neither removeAll nor any remove* switch is specified" {
            { Remove-GTUserEntitlement -UserUPNs "test@contoso.com" } | Should -Throw "*No entitlement action selected*"
        }
    }

    Context "Scope Validation" {
        It "should throw an error when required scopes are missing" {
            Mock -CommandName "Get-GTConnection" -MockWith { 
                [PSCustomObject]@{
                    Scopes = @('User.Read')
                }
            }
            { Remove-GTUserEntitlement -UserUPNs "test@contoso.com" -removeAll } | Should -Throw "*Required scopes are missing*"
        }

        It "should include RoleEligibilitySchedule.ReadWrite.Directory in required scopes" {
            Mock -CommandName "Get-GTConnection" -MockWith { 
                [PSCustomObject]@{
                    Scopes = @('GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'AdministrativeUnit.ReadWrite.All', 'EntitlementManagement.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All')
                }
            }
            { Remove-GTUserEntitlement -UserUPNs "test@contoso.com" -removeAll } | Should -Throw "*Required scopes are missing*RoleEligibilitySchedule.ReadWrite.Directory*"
        }

        It "should dynamically require GroupMember.ReadWrite.All and User.Read.All when only removeGroups is specified" {
            Mock -CommandName "Get-GTConnection" -MockWith { 
                [PSCustomObject]@{
                    Scopes = @('GroupMember.ReadWrite.All')
                }
            }
            { Remove-GTUserEntitlement -UserUPNs "test@contoso.com" -removeGroups } | Should -Throw "*Required scopes are missing*user.read.all*"
        }

        It "should succeed when Directory.ReadWrite.All satisfies User.Read.All for selective removals" {
            Mock -CommandName "Get-GTConnection" -MockWith { 
                [PSCustomObject]@{
                    Scopes = @('GroupMember.ReadWrite.All', 'Directory.ReadWrite.All')
                }
            }
            { Remove-GTUserEntitlement -UserUPNs "test@contoso.com" -removeGroups -WhatIf } | Should -Not -Throw
        }
    }

    Context "PIM Role Eligibility Removal" {
        It "should call Remove-GTPIMRoleEligibilityInternal when removePIMRoleEligibility is specified" {
            Remove-GTUserEntitlement -UserUPNs "test@contoso.com" -removePIMRoleEligibility -WhatIf
            
            Should -Invoke -CommandName "Remove-GTPIMRoleEligibilityInternal" -Times 1
        }

        It "should call Remove-GTPIMRoleEligibilityInternal when removeAll is specified" {
            Remove-GTUserEntitlement -UserUPNs "test@contoso.com" -removeAll -WhatIf
            
            Should -Invoke -CommandName "Remove-GTPIMRoleEligibilityInternal" -Times 1
        }

        It "should not call Remove-GTPIMRoleEligibilityInternal when removePIMRoleEligibility is not specified" {
            Remove-GTUserEntitlement -UserUPNs "test@contoso.com" -removeGroups -WhatIf
            
            Should -Invoke -CommandName "Remove-GTPIMRoleEligibilityInternal" -Times 0
        }
    }
}

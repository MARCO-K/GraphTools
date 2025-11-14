Describe "Remove-GTUserEntitlements" {
    BeforeAll {
        # Create stub functions for all cmdlets used (before sourcing the function)
        function Get-MgContext { }
        function Install-GTRequiredModule { }
        function Get-MgBetaUser { }
        function Remove-GTUserGroupMemberships { }
        function Remove-GTUserGroupOwnerships { }
        function Remove-GTUserLicenses { }
        function Remove-GTUserServicePrincipalOwnerships { }
        function Remove-GTUserEnterpriseAppOwnership { }
        function Remove-GTUserAppRoleAssignments { }
        function Remove-GTUserRoleAssignments { }
        function Remove-GTPIMRoleEligibility { }
        function Remove-GTUserAdministrativeUnitMemberships { }
        function Remove-GTUserAccessPackageAssignments { }
        function Remove-GTUserDelegatedPermissionGrants { }
        function Write-PSFMessage { }
        
        # Source the GTValidation script for UPN regex
        . "$PSScriptRoot/../internal/functions/GTValidation.ps1"
        
        # Now source the function under test
        . "$PSScriptRoot/../functions/Remove-GTUserEntitlements.ps1"
        
        # Mock the required modules and functions
        Mock -CommandName "Get-MgContext" -MockWith { 
            [PSCustomObject]@{
                Scopes = @('GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'AdministrativeUnit.ReadWrite.All', 'EntitlementManagement.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All')
            }
        }
        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Get-MgBetaUser" -MockWith { 
            [PSCustomObject]@{
                Id = "test-user-id"
                UserPrincipalName = "test@contoso.com"
            }
        }
        Mock -CommandName "Remove-GTUserGroupMemberships" -MockWith { }
        Mock -CommandName "Remove-GTUserGroupOwnerships" -MockWith { }
        Mock -CommandName "Remove-GTUserLicenses" -MockWith { }
        Mock -CommandName "Remove-GTUserServicePrincipalOwnerships" -MockWith { }
        Mock -CommandName "Remove-GTUserEnterpriseAppOwnership" -MockWith { }
        Mock -CommandName "Remove-GTUserAppRoleAssignments" -MockWith { }
        Mock -CommandName "Remove-GTUserRoleAssignments" -MockWith { }
        Mock -CommandName "Remove-GTPIMRoleEligibility" -MockWith { }
        Mock -CommandName "Remove-GTUserAdministrativeUnitMemberships" -MockWith { }
        Mock -CommandName "Remove-GTUserAccessPackageAssignments" -MockWith { }
        Mock -CommandName "Remove-GTUserDelegatedPermissionGrants" -MockWith { }
    }

    Context "Parameter Validation" {
        It "should throw an error for an invalid UPN (no @ symbol)" {
            { Remove-GTUserEntitlements -UserUPNs "invalid-user" -removeAll } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty local part)" {
            { Remove-GTUserEntitlements -UserUPNs "@domain.com" -removeAll } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty domain part)" {
            { Remove-GTUserEntitlements -UserUPNs "user@" -removeAll } | Should -Throw
        }

        It "should accept valid UPN format" {
            Mock -CommandName "Get-MgContext" -MockWith { 
                [PSCustomObject]@{
                    Scopes = @('GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'RoleEligibilitySchedule.ReadWrite.Directory', 'AdministrativeUnit.ReadWrite.All', 'EntitlementManagement.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All')
                }
            }
            { Remove-GTUserEntitlements -UserUPNs "test@contoso.com" -removeAll -WhatIf } | Should -Not -Throw
        }
    }

    Context "Scope Validation" {
        It "should throw an error when required scopes are missing" {
            Mock -CommandName "Get-MgContext" -MockWith { 
                [PSCustomObject]@{
                    Scopes = @('User.Read')
                }
            }
            { Remove-GTUserEntitlements -UserUPNs "test@contoso.com" -removeAll } | Should -Throw "*Required scopes are missing*"
        }

        It "should include RoleEligibilitySchedule.ReadWrite.Directory in required scopes" {
            Mock -CommandName "Get-MgContext" -MockWith { 
                [PSCustomObject]@{
                    Scopes = @('GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'AdministrativeUnit.ReadWrite.All', 'EntitlementManagement.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All')
                }
            }
            { Remove-GTUserEntitlements -UserUPNs "test@contoso.com" -removeAll } | Should -Throw "*Required scopes are missing*RoleEligibilitySchedule.ReadWrite.Directory*"
        }
    }

    Context "PIM Role Eligibility Removal" {
        It "should call Remove-GTPIMRoleEligibility when removePIMRoleEligibility is specified" {
            Mock -CommandName "Get-MgContext" -MockWith { 
                [PSCustomObject]@{
                    Scopes = @('GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'RoleEligibilitySchedule.ReadWrite.Directory', 'AdministrativeUnit.ReadWrite.All', 'EntitlementManagement.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All')
                }
            }
            Mock -CommandName "Remove-GTPIMRoleEligibility" -MockWith { }
            
            Remove-GTUserEntitlements -UserUPNs "test@contoso.com" -removePIMRoleEligibility -WhatIf
            
            Should -Invoke -CommandName "Remove-GTPIMRoleEligibility" -Times 1
        }

        It "should call Remove-GTPIMRoleEligibility when removeAll is specified" {
            Mock -CommandName "Get-MgContext" -MockWith { 
                [PSCustomObject]@{
                    Scopes = @('GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'RoleEligibilitySchedule.ReadWrite.Directory', 'AdministrativeUnit.ReadWrite.All', 'EntitlementManagement.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All')
                }
            }
            Mock -CommandName "Remove-GTPIMRoleEligibility" -MockWith { }
            
            Remove-GTUserEntitlements -UserUPNs "test@contoso.com" -removeAll -WhatIf
            
            Should -Invoke -CommandName "Remove-GTPIMRoleEligibility" -Times 1
        }

        It "should not call Remove-GTPIMRoleEligibility when removePIMRoleEligibility is not specified" {
            Mock -CommandName "Get-MgContext" -MockWith { 
                [PSCustomObject]@{
                    Scopes = @('GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'RoleEligibilitySchedule.ReadWrite.Directory', 'AdministrativeUnit.ReadWrite.All', 'EntitlementManagement.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All')
                }
            }
            Mock -CommandName "Remove-GTPIMRoleEligibility" -MockWith { }
            
            Remove-GTUserEntitlements -UserUPNs "test@contoso.com" -removeGroups -WhatIf
            
            Should -Invoke -CommandName "Remove-GTPIMRoleEligibility" -Times 0
        }
    }
}

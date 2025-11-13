. "$PSScriptRoot/../functions/Remove-GTUserEntitlements.ps1"

Describe "Remove-GTUserEntitlements" {
    BeforeAll {
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
    }
}

Describe "Remove-GTUserEntitlements" {
    BeforeAll {
        function global:Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function global:Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession) return $true }
        function global:Get-GTConnection { 
            return [PSCustomObject]@{
                Scopes = @('GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'RoleEligibilitySchedule.ReadWrite.Directory', 'AdministrativeUnit.ReadWrite.All', 'EntitlementManagement.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All')
            }
        }
        function global:Get-GTMissingScopes { param($RequiredScopes, $CurrentScopes) 
            return @($RequiredScopes | Where-Object { $CurrentScopes -notcontains $_ })
        }
        function global:Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } }
        function global:Invoke-GTGraphRequest { param($Uri, $Method = 'GET', $Body, $Headers, $ContentType, [switch]$All, [int]$MaxRetries, [int]$RetryBaseDelaySeconds, $Token, [switch]$Raw, $ErrorAction)
            return @{
                id = "test-user-id"
                userPrincipalName = "test@contoso.com"
            }
        }
        function global:Remove-GTUserGroupMemberships { param($User, $OutputBase, $Results) }
        function global:Remove-GTUserGroupOwnerships { param($User, $OutputBase, $Results) }
        function global:Remove-GTUserLicenses { param($User, $OutputBase, $Results) }
        function global:Remove-GTUserServicePrincipalOwnerships { param($User, $OutputBase, $Results) }
        function global:Remove-GTUserEnterpriseAppOwnership { param($User, $OutputBase, $Results) }
        function global:Remove-GTUserAppRoleAssignments { param($User, $OutputBase, $Results) }
        function global:Remove-GTUserRoleAssignments { param($User, $OutputBase, $Results) }
        function global:Remove-GTPIMRoleEligibilityInternal { param($User, $OutputBase, $Results) }
        function global:Remove-GTUserAdministrativeUnitMemberships { param($User, $OutputBase, $Results) }
        function global:Remove-GTUserAccessPackageAssignments { param($User, $OutputBase, $Results) }
        function global:Remove-GTUserDelegatedPermissionGrants { param($User, $OutputBase, $Results) }

        # Dot-source GTValidation for UPN regex
        . "$PSScriptRoot/../internal/functions/GTValidation.ps1"

        # Dot-source the function under test
        . "$PSScriptRoot/../functions/Remove-GTUserEntitlements.ps1"
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
        Mock -CommandName Remove-GTUserGroupMemberships -MockWith { }
        Mock -CommandName Remove-GTUserGroupOwnerships -MockWith { }
        Mock -CommandName Remove-GTUserLicenses -MockWith { }
        Mock -CommandName Remove-GTUserServicePrincipalOwnerships -MockWith { }
        Mock -CommandName Remove-GTUserEnterpriseAppOwnership -MockWith { }
        Mock -CommandName Remove-GTUserAppRoleAssignments -MockWith { }
        Mock -CommandName Remove-GTUserRoleAssignments -MockWith { }
        Mock -CommandName Remove-GTPIMRoleEligibilityInternal -MockWith { }
        Mock -CommandName Remove-GTUserAdministrativeUnitMemberships -MockWith { }
        Mock -CommandName Remove-GTUserAccessPackageAssignments -MockWith { }
        Mock -CommandName Remove-GTUserDelegatedPermissionGrants -MockWith { }
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
            Mock -CommandName "Get-GTConnection" -MockWith { 
                [PSCustomObject]@{
                    Scopes = @('User.Read')
                }
            }
            { Remove-GTUserEntitlements -UserUPNs "test@contoso.com" -removeAll } | Should -Throw "*Required scopes are missing*"
        }

        It "should include RoleEligibilitySchedule.ReadWrite.Directory in required scopes" {
            Mock -CommandName "Get-GTConnection" -MockWith { 
                [PSCustomObject]@{
                    Scopes = @('GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'AdministrativeUnit.ReadWrite.All', 'EntitlementManagement.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All')
                }
            }
            { Remove-GTUserEntitlements -UserUPNs "test@contoso.com" -removeAll } | Should -Throw "*Required scopes are missing*RoleEligibilitySchedule.ReadWrite.Directory*"
        }
    }

    Context "PIM Role Eligibility Removal" {
        It "should call Remove-GTPIMRoleEligibilityInternal when removePIMRoleEligibility is specified" {
            Remove-GTUserEntitlements -UserUPNs "test@contoso.com" -removePIMRoleEligibility -WhatIf
            
            Should -Invoke -CommandName "Remove-GTPIMRoleEligibilityInternal" -Times 1
        }

        It "should call Remove-GTPIMRoleEligibilityInternal when removeAll is specified" {
            Remove-GTUserEntitlements -UserUPNs "test@contoso.com" -removeAll -WhatIf
            
            Should -Invoke -CommandName "Remove-GTPIMRoleEligibilityInternal" -Times 1
        }

        It "should not call Remove-GTPIMRoleEligibilityInternal when removePIMRoleEligibility is not specified" {
            Remove-GTUserEntitlements -UserUPNs "test@contoso.com" -removeGroups -WhatIf
            
            Should -Invoke -CommandName "Remove-GTPIMRoleEligibilityInternal" -Times 0
        }
    }
}

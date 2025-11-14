# User Security Response Functions

This document describes the separate functions available in GraphTools for responding to user security incidents in Microsoft Entra ID (Azure AD).

## Overview

When a user account is compromised or needs to be secured, GraphTools provides five distinct functions that can be used individually or together:

1. **Revoke-GTSignOutFromAllSessions** - Revoke refresh tokens
2. **Disable-GTUser** - Disable the user account
3. **Reset-GTUserPassword** - Reset the user's password
4. **Disable-GTUserDevice** - Disable user's registered devices
5. **Remove-GTUserEntitlements** - Remove access rights and privileges (including PIM role eligibilities)

## Functions

### 1. Revoke-GTSignOutFromAllSessions

Revokes all refresh tokens for a user, effectively signing them out from all applications and devices.

**Purpose**: Invalidates all refresh tokens issued to applications and clears session cookies in the user's browser.

**Required Permissions**: `User.ReadWrite.All`

**Example**:
```powershell
Revoke-GTSignOutFromAllSessions -UPN 'user@contoso.com'
```

### 2. Disable-GTUser

Disables a user account in Microsoft Entra ID by setting the AccountEnabled property to false.

**Purpose**: Prevents any new sign-in attempts from the user account.

**Required Permissions**: `User.ReadWrite.All`

**Example**:
```powershell
Disable-GTUser -UPN 'user@contoso.com'
```

### 3. Reset-GTUserPassword

Resets a user's password to a randomly generated password.

**Purpose**: Signals applications supporting Continuous Access Evaluation (CAE) to terminate active sessions. Forces the user to change their password on next sign-in.

**Required Permissions**: `User.ReadWrite.All`

**Example**:
```powershell
Reset-GTUserPassword -UPN 'user@contoso.com'
```

### 4. Disable-GTUserDevice

Disables all devices registered to a user in Microsoft Entra ID.

**Purpose**: Prevents access from all devices registered to the user account, adding an additional layer of security.

**Required Permissions**: `Directory.AccessAsUser.All`

**Example**:
```powershell
Disable-GTUserDevice -UPN 'user@contoso.com'
```

### 5. Remove-GTUserEntitlements

Removes all user entitlements including group memberships, licenses, role assignments, PIM role eligibilities, and application access.

**Purpose**: Complete privilege revocation during offboarding or security incident response. Includes removal of PIM (Privileged Identity Management) role eligibility schedules to prevent users from activating privileged roles.

**Required Permissions**: `GroupMember.ReadWrite.All`, `Group.ReadWrite.All`, `Directory.ReadWrite.All`, `RoleManagement.ReadWrite.Directory`, `RoleEligibilitySchedule.ReadWrite.Directory`, `AdministrativeUnit.ReadWrite.All`, `EntitlementManagement.ReadWrite.All`, `DelegatedPermissionGrant.ReadWrite.All`

**Examples**:
```powershell
# Remove all entitlements (including PIM role eligibilities)
Remove-GTUserEntitlements -UserUPNs 'user@contoso.com' -removeAll

# Remove only privileged access
Remove-GTUserEntitlements -UserUPNs 'admin@contoso.com' `
    -removeRoleAssignments `
    -removePIMRoleEligibility

# Remove specific entitlements
Remove-GTUserEntitlements -UserUPNs 'user@contoso.com' `
    -removeGroups `
    -removeLicenses `
    -removePIMRoleEligibility
```

**What Gets Removed**:
- Group memberships and ownerships
- Microsoft 365 licenses
- Directory role assignments (active roles)
- **PIM role eligibility schedules (eligible roles)** ⚠️ New in v0.9.0
- Administrative unit memberships
- Application role assignments
- Enterprise application ownerships
- Access package assignments
- Delegated permission grants

## Comprehensive Security Response

For a complete security response when a user account is compromised, you can execute all five functions in sequence:

```powershell
$compromisedUser = 'user@contoso.com'

# 1. Revoke all refresh tokens to sign out from all sessions
Revoke-GTSignOutFromAllSessions -UPN $compromisedUser

# 2. Disable the user account to prevent new sign-ins
Disable-GTUser -UPN $compromisedUser

# 3. Reset the password to terminate CAE-enabled sessions
Reset-GTUserPassword -UPN $compromisedUser

# 4. Disable all registered devices
Disable-GTUserDevice -UPN $compromisedUser

# 5. Remove all entitlements (including PIM role eligibilities)
Remove-GTUserEntitlements -UserUPNs $compromisedUser -removeAll
```

### Multiple Users

All functions support pipeline input for batch operations:

```powershell
$compromisedUsers = @('user1@contoso.com', 'user2@contoso.com')

$compromisedUsers | Revoke-GTSignOutFromAllSessions
$compromisedUsers | Disable-GTUser
$compromisedUsers | Reset-GTUserPassword
$compromisedUsers | Disable-GTUserDevice
$compromisedUsers | Remove-GTUserEntitlements -removeAll
```

## Common Parameters

All functions support the following common parameters:

- **UPN** (Mandatory): User Principal Name(s) in valid email format
  - Aliases: `UserPrincipalName`, `Users`, `User`, `UserName`, `UPNName`
- **NewSession** (Optional): Creates a new Microsoft Graph session by disconnecting any existing session first

### Parameter Name Conventions and Aliases

To improve usability and reduce confusion, the GraphTools module supports multiple parameter names through aliases:

#### User Identity Parameters

| Canonical Parameter | Accepted Aliases | Usage Context | Example Functions |
|---------------------|------------------|---------------|-------------------|
| `-UPN` | `-UserPrincipalName`, `-Users`, `-User`, `-UserName`, `-UPNName` | Pipeline-style commands accepting multiple users (string[]) | Disable-GTUser |
| `-UPN` | `-UserPrincipalName`, `-Users`, `-UserName`, `-UPNName` | Pipeline-style commands accepting multiple users (string[]) | Reset-GTUserPassword, Disable-GTUserDevice |
| `-UPN` | `-UserPrincipalName`, `-Users`, `-UserName`, `-UPNName` | Single user commands (string) | Revoke-GTSignOutFromAllSessions |
| `-UserPrincipalName` | `-UPN`, `-UserName`, `-UPNName` | Single user lookup commands (string) | Get-GTRecentUser |
| `-UserPrincipalName` | `-UPN`, `-Users`, `-User`, `-UserName`, `-UPNName` | Report generation accepting multiple users (string[]) | Get-MFAReport |
| `-FilterUser` | `-User`, `-UPN`, `-UserPrincipalName`, `-UserName`, `-UPNName` | Filter parameters for license queries | Get-M365LicenceOverview |
| `-UserIds` | `-Users`, `-UPN`, `-UserPrincipalName`, `-UserName`, `-UPNName` | Audit log queries accepting user arrays | Invoke-AuditLogQuery |

#### When to Use Which Parameter

- **Use `-UPN`** for pipeline-style operations and batch processing where you need to act on multiple user accounts
- **Use `-UserPrincipalName`** for single-user lookups or when you prefer more explicit parameter names
- **Use `-UserName` or `-UPNName` as convenient alternatives that may be more familiar**
- **Use `-Users` or `-User`** as convenient shortcuts that match your mental model

All aliases are functionally equivalent - choose the one that makes your code most readable. The canonical parameter name is preserved for backwards compatibility.

#### Examples Using Different Aliases

```powershell
# All of these commands are equivalent:
Disable-GTUser -UPN 'user@contoso.com'
Disable-GTUser -UserPrincipalName 'user@contoso.com'
Disable-GTUser -UserName 'user@contoso.com'
Disable-GTUser -UPNName 'user@contoso.com'
Disable-GTUser -User 'user@contoso.com'

# For multiple users:
Disable-GTUser -Users 'user1@contoso.com', 'user2@contoso.com'
Disable-GTUser -UPN 'user1@contoso.com', 'user2@contoso.com'

# For filtering license queries:
Get-M365LicenseOverview -FilterUser 'john@contoso.com'
Get-M365LicenseOverview -UPN 'john@contoso.com'
Get-M365LicenseOverview -UserName 'john@contoso.com'

# For audit log queries:
Invoke-AuditLogQuery -UserIds 'user@contoso.com'
Invoke-AuditLogQuery -Users 'user@contoso.com'
Invoke-AuditLogQuery -UPN 'user@contoso.com'
```

## Security & Input Validation

GraphTools implements comprehensive input validation to protect against injection attacks:

### UPN Validation
All user-supplied UPN parameters are validated against a strict email format regex pattern before use:
- Pattern: `^[^@\s]+@[^@\s]+\.[^@\s]+$`
- Validates: Basic email structure with local part, @ symbol, and domain
- Blocks: Invalid formats, injection attempts, malformed input

```powershell
# Valid UPNs
Disable-GTUser -UPN 'user@contoso.com'        # ✅ Valid
Disable-GTUser -UPN 'john.doe@company.co.uk'  # ✅ Valid

# Invalid UPNs (will throw validation error)
Disable-GTUser -UPN 'invalid-user'            # ❌ Blocked: No domain
Disable-GTUser -UPN 'user@'                   # ❌ Blocked: Missing domain
Disable-GTUser -UPN '@domain.com'             # ❌ Blocked: Missing local part
```

### GUID Validation
Internal functions that build OData filters with user/device IDs validate GUIDs before interpolation:
- Pattern: `^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$`
- Validates: Strict GUID format (8-4-4-4-12 hexadecimal pattern)
- Prevents: OData filter injection through malicious ID values

Protected functions:
- `Disable-GTUserDevice` - Validates user IDs before device filter queries
- `Remove-GTUserRoleAssignments` - Validates principal IDs in role queries
- `Remove-GTUserDelegatedPermissionGrants` - Validates OAuth grant principals
- `Remove-GTPIMRoleEligibility` - Validates PIM role schedule principals
- `Remove-GTUserAccessPackageAssignments` - Validates access package assignment targets

### Audit Log Parameter Validation
`Invoke-AuditLogQuery` implements strict character whitelisting for all filter parameters:

**Operations Parameter**: Only alphanumeric, hyphens, and underscores
```powershell
Invoke-AuditLogQuery -Operations 'FileDeleted','User_Logon'  # ✅ Valid
Invoke-AuditLogQuery -Operations "File'; DROP TABLE--"       # ❌ Blocked
```

**RecordType Parameter**: Only alphanumeric, hyphens, and underscores
```powershell
Invoke-AuditLogQuery -RecordType 'Exchange','SharePoint'     # ✅ Valid
Invoke-AuditLogQuery -RecordType "Type' OR 1=1--"            # ❌ Blocked
```

**Properties Parameter**: Only alphanumeric, dots (for nested properties), and underscores
```powershell
Invoke-AuditLogQuery -Properties 'Id','auditData.property'   # ✅ Valid
Invoke-AuditLogQuery -Properties "prop' OR '1'='1"           # ❌ Blocked
```

### Why This Matters
These validations prevent:
- **SQL Injection**: Blocks SQL command injection through parameter values
- **OData Injection**: Prevents filter manipulation and unauthorized data access
- **XSS Attacks**: Blocks script injection through parameters
- **Path Traversal**: Prevents directory traversal attempts
- **Account Enumeration**: Generic error messages for failed lookups prevent user discovery

## Notes

- All functions automatically manage Microsoft Graph authentication
- All functions validate UPN format before execution
- All parameters are sanitized against injection attacks
- All functions provide verbose logging for troubleshooting
- All functions handle errors gracefully with detailed error messages
- Functions can be used independently based on your security requirements

## Best Practices

1. **Always revoke tokens first** to immediately terminate active sessions
2. **Disable the account** to prevent new authentication attempts
3. **Reset the password** to ensure CAE-compliant applications terminate sessions
4. **Disable devices** to prevent device-based access
5. **Remove all entitlements** including PIM role eligibilities to ensure complete privilege revocation

### Critical Security Note: PIM Role Eligibilities

⚠️ **Important**: Prior to v0.9.0, removing role assignments did not remove PIM (Privileged Identity Management) role eligibility schedules. This meant users could still activate privileged roles even after remediation.

**v0.9.0+ closes this security gap** by removing both active role assignments AND PIM role eligibilities when using:
- `Remove-GTUserEntitlements -removeAll`
- `Remove-GTUserEntitlements -removePIMRoleEligibility`

Always use the `-removePIMRoleEligibility` parameter or `-removeAll` when offboarding privileged users to ensure they cannot activate eligible roles.

## See Also

- [Microsoft Entra ID Documentation](https://learn.microsoft.com/en-us/entra/identity/)
- [Continuous Access Evaluation](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-continuous-access-evaluation)
- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/)

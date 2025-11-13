# User Security Response Functions

This document describes the separate functions available in GraphTools for responding to user security incidents in Microsoft Entra ID (Azure AD).

## Overview

When a user account is compromised or needs to be secured, GraphTools provides four distinct functions that can be used individually or together:

1. **Revoke-GTSignOutFromAllSessions** - Revoke refresh tokens
2. **Disable-GTUser** - Disable the user account
3. **Reset-GTUserPassword** - Reset the user's password
4. **Disable-GTUserDevice** - Disable user's registered devices

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

## Comprehensive Security Response

For a complete security response when a user account is compromised, you can execute all four functions in sequence:

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
```

### Multiple Users

All functions support pipeline input for batch operations:

```powershell
$compromisedUsers = @('user1@contoso.com', 'user2@contoso.com')

$compromisedUsers | Revoke-GTSignOutFromAllSessions
$compromisedUsers | Disable-GTUser
$compromisedUsers | Reset-GTUserPassword
$compromisedUsers | Disable-GTUserDevice
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
- **Use `-UserName`** or `-UPNName`** as convenient alternatives that may be more familiar
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

## Notes

- All functions automatically manage Microsoft Graph authentication
- All functions validate UPN format before execution
- All functions provide verbose logging for troubleshooting
- All functions handle errors gracefully with detailed error messages
- Functions can be used independently based on your security requirements

## Best Practices

1. **Always revoke tokens first** to immediately terminate active sessions
2. **Disable the account** to prevent new authentication attempts
3. **Reset the password** to ensure CAE-compliant applications terminate sessions
4. **Disable devices** as a final step to prevent device-based access

## See Also

- [Microsoft Entra ID Documentation](https://learn.microsoft.com/en-us/entra/identity/)
- [Continuous Access Evaluation](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-continuous-access-evaluation)
- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/)

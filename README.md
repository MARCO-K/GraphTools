# MS Graph tools

## GraphTools: PowerShell Module for Microsoft Entra ID Management & Reporting

![GraphTools](image.png)

**GraphTools** is a robust PowerShell module designed for IT security professionals focused on Entra ID and Microsoft 365.

It provides a suite of efficient, forward-thinking cmdlets that simplify complex security tasks such as risk detection, conditional access management, audit log analysis, and incident response.

By leveraging Microsoft Graph, GraphTools enables proactive identity protection and streamlined security management. Whether you're automating routine security checks or responding to emerging threats, this module empowers you to secure your environment with precision and confidence.

## Features

### User Security Response Functions

GraphTools provides comprehensive security incident response capabilities for user accounts:

- **Revoke-GTSignOutFromAllSessions**: Revoke refresh tokens to sign out users from all sessions
- **Disable-GTUser**: Disable user accounts to prevent new sign-in attempts
- **Reset-GTUserPassword**: Reset passwords to terminate CAE-enabled sessions
- **Disable-GTUserDevice**: Disable all devices registered to a user account
- **Remove-GTUserEntitlements**: Comprehensive removal of user entitlements including:
  - Group memberships and ownerships
  - Microsoft 365 licenses
  - Enterprise Applications and App Registrations ownerships (with last-owner protection)
  - Application role assignments
  - Directory role assignments (privileged roles like Global Administrator)
  - Administrative unit memberships (scoped administrative rights)
  - Access package assignments (Entitlement Management)

See [User Security Response Documentation](docs/User-Security-Response.md) for detailed usage examples.

### Reporting and Analysis

- **Get-M365LicenseOverview**: Comprehensive view of user licenses and service plans across the organization
- **Get-MFAReport**: Collects MFA registration details from Microsoft Graph with filtering options
- **Invoke-AuditLogQuery**: Query Microsoft 365 audit logs with filtering by Operations or RecordTypes
- **Get-GTInactiveUsers**: Retrieve user accounts with advanced filtering options including inactivity days

## Manual Installation

1. Clone or download the repository.
2. Copy the GraphTools folder to one of your PowerShell module directories (e.g., $env:USERPROFILE\Documents\PowerShell\Modules).

## Usage

1. Import the Module:

```powershell
Import-Module GraphTools
```

1. Run a Function: For example, to list risky users:

```powershell
Get-GTMFAReport -UsersWithoutMFA -NoGuestUser
```

## Immediate Steps to Revoke Access

### Complete security response workflow

```powershell
$user = 'compromised@contoso.com'

Revoke-GTSignOutFromAllSessions -UPN $user  # Invalidate tokens
Disable-GTUser -UPN $user                    # Block sign-ins
Reset-GTUserPassword -UPN $user              # Terminate CAE sessions
Disable-GTUserDevice -UPN $user              # Disable registered devices

# Remove all entitlements to ensure complete access revocation
Remove-GTUserEntitlements -UserUPNs $user -removeAll
```

### Selective entitlement removal

```powershell
# Remove only specific entitlements
Remove-GTUserEntitlements -UserUPNs 'user@contoso.com' -removeGroups -removeLicenses

# Remove privileged roles, admin units, app ownerships, and access packages
Remove-GTUserEntitlements -UserUPNs 'admin@contoso.com' -removeRoleAssignments -removeAdministrativeUnitMemberships -removeEnterpriseAppOwnership -removeAccessPackageAssignments

# Process multiple users
'user1@contoso.com','user2@contoso.com' | Remove-GTUserEntitlements -removeAll
```

### Batch operations supported via pipeline

```powershell
$users | Disable-GTUserDevice
```

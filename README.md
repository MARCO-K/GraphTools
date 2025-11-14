# GraphTools

![GraphTools](image.png)

> A comprehensive PowerShell module for Microsoft Entra ID (Azure AD) security management, incident response, and reporting via Microsoft Graph API.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PSScriptAnalyzer](https://github.com/MARCO-K/GraphTools/actions/workflows/powershell.yml/badge.svg)](https://github.com/MARCO-K/GraphTools/actions/workflows/powershell.yml)

## 📋 Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Security Incident Response](#security-incident-response)
- [Reporting & Analysis](#reporting--analysis)
- [Parameter Flexibility](#parameter-flexibility)
- [Prerequisites](#prerequisites)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## 🎯 Overview

**GraphTools** is a robust PowerShell module designed for IT security professionals and administrators working with Microsoft Entra ID (formerly Azure AD) and Microsoft 365 environments.

### Why GraphTools?

- **🚨 Rapid Incident Response**: Quickly contain compromised accounts with dedicated security response functions
- **📊 Comprehensive Reporting**: Deep insights into licensing, MFA adoption, inactive users, and audit logs
- **🔄 Automation-Friendly**: Full pipeline support for batch operations and scripting
- **🎨 Flexible Parameters**: Multiple parameter aliases reduce confusion and improve code readability
- **🛡️ Enterprise-Ready**: Built-in validation, error handling, and verbose logging

## 🔑 Key Features

### Security Incident Response

Respond to security incidents with purpose-built cmdlets:

| Function | Purpose | Use Case |
|----------|---------|----------|
| `Revoke-GTSignOutFromAllSessions` | Invalidate refresh tokens | Immediate session termination |
| `Disable-GTUser` | Block account sign-ins | Prevent unauthorized access |
| `Reset-GTUserPassword` | Force password reset | Terminate CAE-enabled sessions |
| `Disable-GTUserDevice` | Disable registered devices | Block device-based access |
| `Remove-GTUserEntitlements` | Remove access rights | Complete privilege revocation |

### Identity & Access Management

- **Group Management**: Remove memberships and ownerships
- **License Management**: Revoke Microsoft 365 licenses
- **Role Management**: Remove directory and administrative unit roles
- **PIM Role Management**: Remove Privileged Identity Management role eligibility schedules
- **Application Access**: Revoke app role assignments and OAuth permissions
- **Entitlement Management**: Remove access package assignments

### Reporting & Analytics

| Function | Description |
|----------|-------------|
| `Get-MFAReport` | MFA registration status and authentication methods |
| `Get-M365LicenseOverview` | License and service plan utilization |
| `Invoke-AuditLogQuery` | Query unified audit logs with filtering |
| `Get-GTInactiveUsers` | Identify dormant accounts by last sign-in |
| `Get-GTRecentUser` | Find recently created user accounts |

## 📦 Installation

### Prerequisites

- PowerShell 5.1 or PowerShell 7+
- Microsoft Graph PowerShell SDK modules (automatically managed by GraphTools)
- Appropriate Microsoft Graph API permissions

### Install from Repository

1. Clone the repository:
   ```powershell
   git clone https://github.com/MARCO-K/GraphTools.git
   ```

2. Copy to your PowerShell modules directory:
   ```powershell
   Copy-Item -Path .\GraphTools -Destination "$env:USERPROFILE\Documents\PowerShell\Modules\" -Recurse
   ```

3. Import the module:
   ```powershell
   Import-Module GraphTools
   ```

4. Verify installation:
   ```powershell
   Get-Command -Module GraphTools
   ```

## 🚀 Quick Start

### Connect to Microsoft Graph

```powershell
# Import the module
Import-Module GraphTools

# Functions automatically handle Graph connection
# You'll be prompted to authenticate when needed
```

### Common Scenarios

#### Check MFA Status

```powershell
# Get users without MFA (excluding guests)
Get-MFAReport -UsersWithoutMFA -NoGuestUser

# Check specific users
'user1@contoso.com', 'user2@contoso.com' | Get-MFAReport
```

#### Find Inactive Accounts

```powershell
# Users inactive for 90+ days
Get-GTInactiveUser -InactiveDaysOlderThan 90

# Disabled external accounts
Get-GTInactiveUser -DisabledUsersOnly -ExternalUsersOnly
```

#### Review License Usage

```powershell
# All licenses for a user
Get-M365LicenseOverview -FilterUser 'john.doe@contoso.com'

# Filter by license SKU
Get-M365LicenseOverview -FilterLicenseSKU 'ENTERPRISEPACK'
```

## 🚨 Security Incident Response

### Complete Containment Workflow

When a user account is compromised, execute this comprehensive response:

```powershell
$compromisedUser = 'compromised@contoso.com'

# Step 1: Invalidate all refresh tokens
Revoke-GTSignOutFromAllSessions -UPN $compromisedUser

# Step 2: Block new sign-in attempts
Disable-GTUser -UPN $compromisedUser

# Step 3: Force password reset (terminates CAE sessions)
Reset-GTUserPassword -UPN $compromisedUser

# Step 4: Disable all registered devices
Disable-GTUserDevice -UPN $compromisedUser

# Step 5: Remove all entitlements
Remove-GTUserEntitlements -UserUPNs $compromisedUser -removeAll
```

### Selective Entitlement Removal

Remove specific privileges while maintaining basic access:

```powershell
# Remove groups and licenses only
Remove-GTUserEntitlements -UserUPNs 'user@contoso.com' `
    -removeGroups `
    -removeLicenses

# Remove privileged access (including PIM eligibilities)
Remove-GTUserEntitlements -UserUPNs 'admin@contoso.com' `
    -removeRoleAssignments `
    -removePIMRoleEligibility `
    -removeAdministrativeUnitMemberships `
    -removeEnterpriseAppOwnership
```

### Batch Operations

Process multiple users efficiently using the pipeline:

```powershell
# Disable multiple compromised accounts
$compromisedAccounts = @(
    'user1@contoso.com',
    'user2@contoso.com',
    'user3@contoso.com'
)

$compromisedAccounts | Revoke-GTSignOutFromAllSessions
$compromisedAccounts | Disable-GTUser
$compromisedAccounts | Reset-GTUserPassword
$compromisedAccounts | Disable-GTUserDevice

# Or use pipeline for entitlements
$compromisedAccounts | Remove-GTUserEntitlements -removeAll
```

## 📊 Reporting & Analysis

### Multi-Factor Authentication Analysis

```powershell
# Admins with MFA status
Get-MFAReport -AdminsOnly -MarkMethods

# Users without MFA registration
Get-MFAReport -UsersWithoutMFA -NoGuestUser

# Users capable of MFA
Get-MFAReport -MFACapable
```

### Audit Log Queries

```powershell
# File deletions in the last 7 days
Invoke-AuditLogQuery -Operations 'FileDeleted'

# Specific user activity over 30 days
Invoke-AuditLogQuery -UserIds 'admin@contoso.com' -StartDays 30

# Filter by IP address
Invoke-AuditLogQuery -IpAddresses '192.168.1.100' -StartDays 14
```

### License Reporting

```powershell
# Service plan details for a user
Get-M365LicenseOverview -FilterUser 'john@contoso.com'

# Users with Exchange licenses
Get-M365LicenseOverview -FilterServicePlan 'EXCHANGE'

# Inactive users with licenses
Get-M365LicenseOverview -FilterUser 'user@contoso.com' -LastLogin 90
```

## 🎨 Parameter Flexibility

GraphTools supports multiple parameter aliases for user identifiers, allowing you to choose the most readable option:

### All Functions Accept These Aliases

```powershell
# These are all equivalent:
Disable-GTUser -UPN 'user@contoso.com'
Disable-GTUser -UserPrincipalName 'user@contoso.com'
Disable-GTUser -UserName 'user@contoso.com'
Disable-GTUser -UPNName 'user@contoso.com'
Disable-GTUser -User 'user@contoso.com'

# For multiple users:
Reset-GTUserPassword -Users 'user1@contoso.com', 'user2@contoso.com'
Reset-GTUserPassword -UPN 'user1@contoso.com', 'user2@contoso.com'
```

### Supported Aliases by Parameter Type

| Canonical Parameter | Aliases |
|---------------------|---------|
| `-UPN` | `-UserPrincipalName`, `-UserName`, `-UPNName`, `-User`, `-Users` |
| `-UserPrincipalName` | `-UPN`, `-UserName`, `-UPNName`, `-User`, `-Users` |
| `-FilterUser` | `-User`, `-UPN`, `-UserPrincipalName`, `-UserName`, `-UPNName` |
| `-UserIds` | `-Users`, `-UPN`, `-UserPrincipalName`, `-UserName`, `-UPNName` |

See [detailed documentation](docs/User-Security-Response.md) for complete alias mappings.

## 📋 Prerequisites

### Required Modules

GraphTools automatically manages required Microsoft Graph modules:

- `Microsoft.Graph.Authentication`
- `Microsoft.Graph.Users`
- `Microsoft.Graph.Beta.Users`
- `Microsoft.Graph.Identity.DirectoryManagement`
- `Microsoft.Graph.Beta.Reports`
- Additional modules loaded on-demand

### Required Permissions

Depending on the functions used, you'll need appropriate Microsoft Graph permissions:

| Function Category | Required Scopes |
|-------------------|-----------------|
| User Management | `User.ReadWrite.All` |
| Device Management | `Directory.AccessAsUser.All` |
| License Management | `Organization.Read.All`, `User.Read.All` |
| Role Management | `RoleManagement.ReadWrite.Directory` |
| PIM Role Management | `RoleEligibilitySchedule.ReadWrite.Directory` |
| Audit Logs | `AuditLog.Read.All`, `AuditLogsQuery.Read.All` |
| MFA Reports | `User.Read.All`, `AuditLog.Read.All` |

Functions will prompt for necessary permissions during execution.

## 📚 Documentation

- **[Changelog](CHANGELOG.md)** - Version history and release notes
- **[User Security Response Guide](docs/User-Security-Response.md)** - Detailed incident response procedures
- **Function Help** - Use `Get-Help <Function-Name> -Full` for detailed documentation
- **Examples** - Use `Get-Help <Function-Name> -Examples` for usage examples

### Get Help

```powershell
# View detailed help
Get-Help Disable-GTUser -Full

# View examples only
Get-Help Reset-GTUserPassword -Examples

# List all functions
Get-Command -Module GraphTools
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [Microsoft Graph PowerShell SDK](https://github.com/microsoftgraph/msgraph-sdk-powershell)
- Leverages [PSFramework](https://psframework.org/) for logging and messaging

---

**Note**: GraphTools is designed for security professionals and administrators. Always test in a non-production environment first and ensure you have appropriate authorization before making changes to user accounts or security settings.

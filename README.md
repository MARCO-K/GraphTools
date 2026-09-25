# GraphTools

![GraphTools](assets/hero-banner.jpg)

> A comprehensive PowerShell module for Microsoft Entra ID (Azure AD) security management, incident response, and reporting via Microsoft Graph API.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PSScriptAnalyzer](https://github.com/MARCO-K/GraphTools/actions/workflows/powershell.yml/badge.svg)](https://github.com/MARCO-K/GraphTools/actions/workflows/powershell.yml)

## 📋 Table of Contents

<!-- markdownlint-disable MD051 -->
- [Overview](#overview)
- [Key Features](#key-features)
  - [Zero-Dependency Microsoft Graph REST Engine](#zero-dependency-microsoft-graph-rest-engine)
  - [Security Incident Response](#security-incident-response)
  - [Identity & Access Management](#identity--access-management)
  - [Reporting & Governance](#reporting--governance)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Security Incident Response](#security-incident-response-1)
- [Reporting & Analysis](#reporting--analysis)
- [Parameter Flexibility](#parameter-flexibility)
- [Error Handling & Reliability](#error-handling--reliability)
- [Security & Input Validation](#security--input-validation)
- [Prerequisites & Architecture](#prerequisites--architecture)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)
<!-- markdownlint-enable MD051 -->

## 🎯 Overview

**GraphTools** is a high-performance, enterprise-grade PowerShell module designed for IT security professionals, identity architects, and cloud administrators managing Microsoft Entra ID (formerly Azure AD) and Microsoft 365.

Starting in **v0.20.0**, GraphTools features a **native zero-dependency REST engine** that eliminates runtime dependencies on the heavyweight `Microsoft.Graph.*` SDK modules. It leverages native .NET cryptographic primitives, OAuth 2.0 token caching, and resilient HTTP batching for blazingly fast cold starts and enterprise-grade reliability.

### Why GraphTools?

- **⚡ Zero SDK Dependencies**: Eliminates over 50+ MB of external SDK dependencies, reducing cold-start execution time from ~1.8s to ~120ms.
- **🔐 RFC 7523 Certificate Security**: Signs RS256 JWT client assertions directly from the Windows Certificate Store (`Cert:\LocalMachine\My` or `CurrentUser\My`) without exporting private keys.
- **🛡️ Token Caching & Rate-Limit Shield**: In-memory sliding expiration cache eliminates Entra ID token endpoint throttling (HTTP 429).
- **📦 Correlated `$batch` Processing**: Bundles up to 20 subrequests per HTTP roundtrip with automated chunking and subrequest-level 429/503/504 throttling retries.
- **🚨 Rapid Incident Response**: Quickly contain compromised accounts with purpose-built containment workflows.
- **📊 Deep Governance Reporting**: Comprehensive auditing for Tier-0 roles, CA policy gaps, break-glass accounts, DevX permissions, and legacy protocols.
- **🔒 Security-Hardened**: Strict regex validation against OData filter injections and account enumeration.
- **🔄 Pure Pipeline Contracts**: Consistent `[PSCustomObject]` pipeline output across all cmdlets.

## 🔑 Key Features

### Zero-Dependency Microsoft Graph REST Engine

| Component | Function / Feature | Description |
|-----------|--------------------|-------------|
| **Authentication** | `Connect-GTGraph` | Connects via Certificate (Thumbprint or X509Certificate2), Client Secret, or direct Access Token. |
| **Session Status** | `Get-GTConnection` | Inspects active connection status, tenant, client, auth type, and token expiration. |
| **Session Cleanup** | `Disconnect-GTGraph` | Flushes session state and purges in-memory token caches. |
| **REST Invoker** | `Invoke-GTGraphRequest` | Internal invoker with URI normalization, header injection (`ConsistencyLevel`), pagination (`-All`), and 429 backoff. |
| **Batch Orchestrator** | `Invoke-GTGraphBatch` | Executes JSON `$batch` queries (slices of 20) with subrequest-level 429/503 retry and backoff. |

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
- **PIM Role Management**: Report on and remove Privileged Identity Management role eligibility schedules
- **Application Access**: Revoke app role assignments and OAuth permissions
- **Entitlement Management**: Remove access package assignments

### Guest Management

- **Reporting**: Track guest user status and pending invitations
- **Cleanup**: Automate removal of expired guest invitations

### Security & Compliance

- **Credential Monitoring**: Track expiring secrets and certificates
- **App Hygiene**: Identify and remove unused applications
- **DevX Metadata Updates**: `Update-GTRiskyPermissionData` refreshes local Microsoft Graph DevX permissions metadata

### Device Management

- **Hygiene**: Identify inactive devices for cleanup

### Reporting & Governance

| Function | Description |
|----------|-------------|
| `Get-MFAReport` | MFA registration status and authentication methods |
| `Get-M365LicenseOverview` | License and service plan utilization |
| `Invoke-AuditLogQuery` | Query unified audit logs with filtering |
| `Get-GTInactiveUsers` | Identify dormant accounts by last sign-in |
| `Get-GTRecentUser` | Find recently created user accounts |
| `Get-GTOrphanedServicePrincipal` | Identify orphaned or insecure Service Principals |
| `Get-GTGuestUserReport` | Report on guest users and invitation status |
| `Remove-GTExpiredInvites` | Remove expired pending guest invitations |
| `Get-GTExpiringSecrets` | Find expiring secrets and certificates |
| `Get-GTUnusedApps` | Identify unused Service Principals |
| `Get-GTInactiveDevices` | Identify inactive devices |
| `Get-GTPIMRoleReport` | Report on eligible and active PIM role assignments |
| `Get-GTPolicyControlGapReport` | Analyze Conditional Access policies for security gaps |
| `Get-GTBreakGlassPolicyReport` | Audit CA policies against emergency access accounts |
| `Get-GTRiskyAppPermissionReport` | Audit Service Principals for high-risk permissions and Tier-0 attack vectors |
| `Get-GTLegacyAuthReport` | Identify Legacy Authentication usage in sign-in logs |
| `Get-GTAdminCountReport` | Analyze administrative roles with member counts and risk tiers |
| `Update-GTRiskyPermissionData` | Update local offline Microsoft Graph DevX permissions metadata |

## 📦 Installation

### Prerequisites

- **PowerShell Version**: PowerShell 5.1 or PowerShell 7+ (cross-platform compatible)
- **Zero SDK Dependencies**: No `Microsoft.Graph.*` modules required. All requests and cryptographic operations are performed via native .NET and PowerShell REST primitives.
- **Entra ID App Registration**: Application permissions or delegated permissions scoped to your administration needs.

> 💡 **New to this setup?** Follow the [step-by-step setup guide](docs/App-Registration-Setup-Guide.md) for a walkthrough covering new app registration configuration including permission setup for different usage scenarios.

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

### 1. Connect to Microsoft Graph

GraphTools provides native connection management with zero external dependencies and sliding token caching:

```powershell
# Recommended: Certificate-based authentication (RFC 7523 RS256 Client Assertion)
Connect-GTGraph -TenantId "fa8b2a79-cd59-468b-a25d-a6fef0b4dad1" `
                -ClientId "af20edf7-7120-4dbd-af20-e1e58e49b0ff" `
                -Thumbprint "FC57D22ABE444FF1159ED82F971074D9C2443245" `
                -PassThru

# Alternative: Client Secret authentication (for CI/CD or containers)
Connect-GTGraph -TenantId $TenantId -ClientId $ClientId -ClientSecret $Secret

# Alternative: Direct Bearer Token (Azure CLI, GitHub Actions OIDC, or external runners)
Connect-GTGraph -AccessToken $BearerToken

# Check active connection status and token validity
Get-GTConnection
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

# Exclude protected users and Global Administrators from candidate list
Get-GTInactiveUser -InactiveDaysOlderThan 90 -ExcludeUPN 'breakglass@contoso.com' -ExcludeGlobalAdministrators

# Include unresolved sign-in artifacts (off by default to keep output actionable)
Get-GTInactiveUser -InactiveDaysOlderThan 90 -IncludeSignInOnlyRecords

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

### Automated Containment Orchestration

Contain compromised accounts with a single command using `Invoke-GTUserContainment`:

```powershell
# Standard safe containment (sessions, account, password, devices)
Invoke-GTUserContainment -UPN 'compromised@contoso.com'

# Full containment (including permanent entitlement removal)
'compromised@contoso.com' | Invoke-GTUserContainment -FullContainment -Force
```

### Granular Containment Primitives

You can also execute individual containment actions independently:

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

# Filter by source IP address
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

### Administrative Role Analysis

```powershell
# Analyze all administrative roles with member counts and risk tiers
Get-GTAdminCountReport

# Focus on high-risk Tier 0 roles only
Get-GTAdminCountReport -RiskTier Tier0

# Include detailed member lists for each role
Get-GTAdminCountReport -ShowMembers

# Sort by member count (most populated roles first)
Get-GTAdminCountReport -SortBy MemberCount

# Pipeline support for specific roles
'Global Administrator', 'User Administrator' | Get-GTAdminCountReport
```

### Orphaned Resources

```powershell
# Find groups with no owners, disabled owners, or no members
Get-GTOrphanedGroup -Verbose

# Find Service Principals with no owners or disabled owners
Get-GTOrphanedServicePrincipal -Verbose

# Find Service Principals with expired credentials
Get-GTOrphanedServicePrincipal -CheckExpiredCredentials
```

### Conditional Access Policy Analysis

```powershell
# Analyze all enabled Conditional Access policies for security gaps
Get-GTPolicyControlGapReport

# Check policies in reporting mode only
Get-GTPolicyControlGapReport -State 'enabledForReportingButNotEnforced'

# Force new Graph session for analysis
Get-GTPolicyControlGapReport -NewSession
```

### Break Glass Account Auditing

```powershell
# Audit emergency access accounts against all active CA policies
Get-GTBreakGlassPolicyReport -BreakGlassUpn "breakglass1@contoso.com", "breakglass2@contoso.com"

# Find only policies where break glass accounts are at risk
Get-GTBreakGlassPolicyReport -BreakGlassUpn "bg@contoso.com" | Where-Object { $_.Status -eq 'RISK' }

# Force new Graph session for auditing
Get-GTBreakGlassPolicyReport -BreakGlassUpn "emergency@contoso.com" -NewSession
```

### Application Permission Risk Analysis

```powershell
# Audit all Service Principals for high-risk permissions
Get-GTRiskyAppPermissionReport

# Focus on specific applications
Get-GTRiskyAppPermissionReport -AppId "12345678-1234-1234-1234-123456789012"

# Check only delegated permissions
Get-GTRiskyAppPermissionReport -PermissionType Delegated

# Find only critical risks
Get-GTRiskyAppPermissionReport -RiskLevel Critical

# Pipeline support for batch analysis
"app1-id", "app2-id" | Get-GTRiskyAppPermissionReport -PermissionType AppOnly
```

### Legacy Authentication Analysis

```powershell
# Analyze legacy authentication usage in the last 7 days
Get-GTLegacyAuthReport

# Focus on specific users
Get-GTLegacyAuthReport -UserPrincipalName "user@contoso.com"

# Check only successful legacy authentications (security gaps)
Get-GTLegacyAuthReport -SuccessOnly

# Filter by specific legacy protocol
Get-GTLegacyAuthReport -ClientAppUsed "POP3"

# Filter by source IP address
Get-GTLegacyAuthReport -IPAddress "192.168.1.100"

# IPv6 addresses are also supported
Get-GTLegacyAuthReport -IPAddress "2001:db8::1"

# Pipeline support for batch analysis
"pop3", "imap4" | Get-GTLegacyAuthReport -DaysAgo 30
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

## 🔍 Error Handling & Reliability

GraphTools v0.10.0 introduces centralized error handling for all Microsoft Graph API operations, providing consistent, informative error messages across all functions.

### Centralized Error Processing

All Graph API errors are processed through the `Get-GTGraphErrorDetails` helper function, which:

- **Extracts HTTP Status Codes**: Automatically detects status codes from Graph API exceptions (404, 403, 429, 400, etc.)
- **Provides Context-Aware Messages**: Different error types receive appropriate user-facing messages
- **Enhances Security**: Uses generic messages for 404/403 errors to prevent account enumeration attacks
- **Supports Debugging**: Detailed error information available at Debug log level
- **Handles Throttling**: Special handling for rate limit errors (429) with retry guidance

### Error Response Format

Functions return structured error information including:

```powershell
# Example: Disable-GTUser error response
@{
    User             = 'user@contoso.com'
    Status           = 'Failed'
    TimeUtc          = '2025-01-14T12:30:00.000Z'
    HttpStatus       = 404
    Reason           = 'Operation failed. The user could not be processed.'
    ExceptionMessage = 'Original error details...'
}
```

> **Note:** The `HttpStatus` field is only present when an HTTP status code can be extracted from the error. In some cases, it may be `$null` or omitted entirely.

### Example: Error response when HTTP status is not available

@{
    User             = '<user@contoso.com>'
    Status           = 'Failed'
    TimeUtc          = '2025-01-14T12:30:00.000Z'
    Reason           = 'Operation failed. The user could not be processed.'
    ExceptionMessage = 'Original error details...'
}

### Logging Levels

Errors are logged at appropriate levels:

- **Error**: Most failures and unrecognized errors
- **Warning**: Throttling (429) errors with retry guidance
- **Debug**: Detailed HTTP status codes and full exception messages

### Example: Handling Errors in Scripts

```powershell
# Error handling with structured output
$results = Disable-GTUser -UPN 'user1@contoso.com','user2@contoso.com'

foreach ($result in $results) {
    if ($result.Status -eq 'Failed') {
        Write-Warning "Failed to disable $($result.User): $($result.Reason)"
        
        # Check for specific HTTP status codes
        if ($result.HttpStatus -eq 429) {
            Start-Sleep -Seconds 60  # Wait before retry
        }
    }
}
```

## 🔒 Security & Input Validation

GraphTools implements comprehensive input validation to protect against injection attacks and ensure safe parameter usage.

### Parameter Validation

All user-supplied parameters are validated before being used in API calls or filters:

#### User Principal Names (UPN)

```powershell
# UPN validation: Must be valid email format
Invoke-AuditLogQuery -UserIds 'user@contoso.com'  # ✅ Valid
Invoke-AuditLogQuery -UserIds 'invalid-user'      # ❌ Blocked
```

#### Operations and Record Types

```powershell
# Operations/RecordType: Alphanumeric, hyphens, underscores only
Invoke-AuditLogQuery -Operations 'FileDeleted','User_Logon'  # ✅ Valid
Invoke-AuditLogQuery -Operations "File'; DROP TABLE--"       # ❌ Blocked: Injection attempt
```

#### Properties

```powershell
# Properties: Alphanumeric, dots (for nested properties), underscores only
Invoke-AuditLogQuery -Properties 'Id','UserId','auditData.property'  # ✅ Valid
Invoke-AuditLogQuery -Properties "property' OR '1'='1"               # ❌ Blocked: Injection attempt
```

#### GUID Validation

```powershell
# Internal functions use Test-GTGuid for ID validation
# Prevents OData filter injection through user/device IDs
# Example from Disable-GTUserDevice:
Test-GTGuid -InputObject $userId  # Validates before filter interpolation
```

### Protected Functions

The following functions have built-in GUID validation for filter safety:

- `Disable-GTUserDevice` - Validates user IDs before device queries
- `Remove-GTUserRoleAssignments` - Validates principal IDs
- `Remove-GTUserDelegatedPermissionGrants` - Validates OAuth grant principals
- `Remove-GTPIMRoleEligibility` - Validates PIM role principals
- `Remove-GTUserAccessPackageAssignments` - Validates access package assignments

### Security Best Practices

When using GraphTools in production:

1. **Use Least Privilege**: Grant only the minimum required Graph API permissions
2. **Validate Input**: The module validates parameters, but verify user input before passing to cmdlets
3. **Audit Operations**: Use `Invoke-AuditLogQuery` to track administrative actions
4. **Test First**: Use `-WhatIf` with cmdlets that support it (e.g., `Disable-GTUser -WhatIf`)
5. **Review Output**: Check Status field in results for failed operations

## 📋 Prerequisites & Architecture

### Zero External SDK Dependencies

Unlike traditional Graph automation tools, GraphTools does **not** depend on `Microsoft.Graph.*` SDK modules:

- **Transport & Security**: Built on native .NET cryptographic providers (`RSACertificateExtensions`) and PowerShell REST primitives (`Invoke-RestMethod`).
- **Logging & Messaging**: Leverages [`PSFramework`](https://psframework.org/) for robust, configurable enterprise logging.
- **SDK Interoperability**: If an existing interactive SDK session is present in the runspace, GraphTools can seamlessly adopt it as a fallback.

### Required Microsoft Graph Permissions

Configure your Microsoft Entra ID App Registration with the appropriate scopes based on your operational scenarios:

| Category | Typical Scopes | Notes |
|----------|----------------|-------|
| **Connection / Read** | `User.Read.All`, `Directory.Read.All` | Basic tenant read access |
| **User Incident Containment** | `User.ReadWrite.All` | Account block, password reset, session revoke |
| **Device Hygiene** | `Device.ReadWrite.All` | Registered device disabling |
| **Role & PIM Governance** | `RoleManagement.Read.Directory`, `RoleEligibilitySchedule.Read.Directory` | Tier-0 role audits and PIM reporting |
| **CA & Security Auditing** | `Policy.Read.All` | Conditional Access and break-glass analysis |
| **App & Permission Risk** | `Application.Read.All`, `DelegatedPermissionGrant.Read.All` | Service Principal risk auditing |
| **Audit Log Analysis** | `AuditLog.Read.All` | Unified audit log queries |

## 📚 Documentation

- **[Zero-Dependency REST Architecture](docs/Zero-Dependency-REST-Architecture.md)** - Technical specification of the native REST engine, RFC 7523 JWT assertion, sliding token cache, and two-tiered `$batch` retry
- **[Connect-GTGraph Guide](docs/Connect-GTGraph.md)** - Comprehensive guide to headless certificate auth, client secrets, and session management
- **[Risky Application Permission Report](docs/Get-GTRiskyAppPermissionReport.md)** - DevX permissions metadata, Tier-0 curated attack vectors, and delegated privilege ceiling
- **[Admin Role Count & Risk Report](docs/Admin-Count-Analysis.md)** - Administrative role analysis and Tier-0 governance
- **[Conditional Access & Break Glass Policy Analysis](docs/Conditional-Access-Analysis.md)** - Policy control gap reporting and emergency access auditing across Conditional Access policies
- **[Legacy Authentication Analysis](docs/Legacy-Authentication-Analysis.md)** - Legacy protocol detection and reporting
- **[License Cost & Waste Report](docs/Get-GTLicenseCostReport.md)** - License optimization and unused assignment detection
- **[PIM Role Governance Guide](docs/PIM-Management.md)** - Privileged Identity Management role eligibility reporting and schedule removal
- **[User Security Response Guide](docs/User-Security-Response.md)** - Incident containment runbooks and containment workflows
- **[Technical Highlights](docs/Technical-Highlights.md)** - Deep dive into architecture, parameter binding, and performance
- **[Changelog](CHANGELOG.md)** - Version history and release notes

### Get Help

```powershell
# View detailed help
Get-Help Connect-GTGraph -Full

# View examples only
Get-Help Get-GTRiskyAppPermissionReport -Examples

# List all module functions
Get-Command -Module GraphTools
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built using native **.NET Cryptography** (`System.Security.Cryptography`) and **PowerShell REST** primitives
- Leverages [PSFramework](https://psframework.org/) for enterprise-grade logging and message dispatching
- Incorporates official [Microsoft Graph DevX](https://github.com/microsoftgraph/microsoft-graph-devx-content) permissions metadata catalogs

---

**Note**: GraphTools is designed for security professionals and administrators. Always test in a non-production environment first and ensure you have appropriate authorization before making changes to user accounts or security settings.

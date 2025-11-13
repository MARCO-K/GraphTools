# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.5] - 2025-01-13

### Added
- Security incident response cmdlets for compromised account containment
  - `Revoke-GTSignOutFromAllSessions` - Invalidate refresh tokens
  - `Disable-GTUser` - Block account sign-ins
  - `Reset-GTUserPassword` - Force password reset
  - `Disable-GTUserDevice` - Disable registered devices
  - `Remove-GTUserEntitlements` - Remove access rights and privileges
- Identity and access management functions
  - Group membership and ownership management
  - License management capabilities
  - Role assignment management (directory and administrative units)
  - Application access and OAuth permission management
  - Entitlement management for access packages
- Reporting and analytics cmdlets
  - `Get-MFAReport` - MFA registration status and authentication methods
  - `Get-M365LicenseOverview` - License and service plan utilization
  - `Invoke-AuditLogQuery` - Query unified audit logs with filtering
  - `Get-GTInactiveUsers` - Identify dormant accounts
  - `Get-GTRecentUser` - Find recently created accounts
  - `Get-GTConditionalAccessPolicyReport` - Conditional access policy analysis
  - `Get-GTPolicyControlGapReport` - Policy control gap reporting
  - `Get-GTServicePrincipalReport` - Service principal reporting
  - `Get-GTOrphanedGroup` - Identify orphaned groups
- Parameter flexibility with multiple aliases for user identifiers
  - Support for `-UPN`, `-UserPrincipalName`, `-UserName`, `-UPNName`, `-User`, `-Users`
  - Improved code readability and reduced confusion
- Full pipeline support for batch operations
- Built-in validation and error handling
- Verbose logging support via PSFramework
- Automatic Microsoft Graph module management
- Comprehensive comment-based help documentation

### Changed
- Standardized user parameter names across all cmdlets for consistency
- Improved parameter aliasing to support multiple naming conventions

### Dependencies
- PowerShell 5.1 or PowerShell 7+
- PSFramework (>= 1.9.270)
- Microsoft.Graph.Beta.Reports (>= 2.25.0)
- Various Microsoft Graph PowerShell SDK modules (loaded on-demand)

---

[Unreleased]: https://github.com/MARCO-K/GraphTools/compare/v0.0.5...main
[0.0.5]: https://github.com/MARCO-K/GraphTools/releases/tag/v0.0.5

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Orphaned Resource Detection** - Enhanced capabilities to identify unmanaged resources
  - New function `Get-GTOrphanedServicePrincipal` to detect Service Principals with no owners, disabled owners, or expired credentials
  - added `Get-GTOrphanedServicePrincipal` to the module export list

### Changed
- **Get-GTOrphanedGroup** - Enhanced detection logic
  - Now identifies groups where *all* owners are disabled (previously only checked for zero owners)
  - Now identifies empty groups (no members)
  - Added `OrphanReason` property to output object for better classification

### Security
- **Input Validation for Invoke-AuditLogQuery** - Enhanced security through parameter validation
  - Added strict character whitelisting for `Operations` parameter (alphanumeric, hyphens, underscores only)
  - Added strict character whitelisting for `RecordType` parameter (alphanumeric, hyphens, underscores only)
  - Added strict character whitelisting for `Properties` parameter (alphanumeric, dots, underscores only)
  - Prevents potential injection attacks through malicious parameter values
  - New validation patterns added to `GTValidation.ps1`: `AuditLogFilterValue` and `AuditLogProperty`
  - Enhanced function documentation with security notes and valid input examples
  
### Testing
- Added 12 new security test cases for `Invoke-AuditLogQuery`
  - Tests for valid inputs (Operations, RecordType, Properties)
  - Tests for SQL injection attempts
  - Tests for OData filter injection attempts
  - Tests for special character injection (quotes, parentheses, semicolons)
  - Test coverage increased from 14 to 26 test cases (+86%)

## [0.14.0] - 2025-11-20

### Added
- **PIM Management** - New capabilities for Privileged Identity Management
  - `Get-GTPIMRoleReport` - Generate comprehensive report of eligible and active PIM role assignments
  - `Remove-GTPIMRoleEligibility` - Remove both active and eligible PIM role assignments (Public function)

## [0.13.0] - 2025-11-20

### Added
- **Device Management** - New capabilities for managing devices
  - `Get-GTInactiveDevices` - Identify devices that have not signed in for a specified number of days

## [0.12.0] - 2025-11-20

### Added
- **Security & Compliance** - Enhanced security monitoring capabilities
  - `Get-GTExpiringSecrets` - Identify Applications and Service Principals with expiring secrets or certificates
  - `Get-GTUnusedApps` - Detect Service Principals with no sign-in activity for a specified period

## [0.11.0] - 2025-11-20

### Added
- **Guest Management** - New capabilities for managing guest users
  - `Get-GTGuestUserReport` - Report on guest users and their invitation status
  - `Remove-GTExpiredInvites` - Automatically clean up pending guest invitations older than X days
- **Performance** - Pipeline optimization
  - `Get-GTInactiveUsers` - Optimized for better pipeline performance and memory usage

## [0.10.0] - 2025-01-14

### Changed
- **Centralized Error Handling** - Major refactoring of Graph API error handling across all functions
  - Refactored 11 functions (5 public, 6 internal) to use the centralized `Get-GTGraphErrorDetails` helper
  - Standardized error messages and logging patterns across all Graph API operations
  - Improved error context with HTTP status code extraction and user-friendly messages
  - Enhanced security by using generic error messages for 404/403 errors to prevent enumeration attacks
  - Better diagnostics with separate user-facing messages and debug-level detailed error information
  
### Improved
- **Public Functions** - Enhanced error handling in:
  - `Get-GTInactiveUsers` - Better error reporting for user retrieval failures
  - `Get-GTOrphanedGroup` - Improved error context for group query failures
  - `Get-MFAReport` - Standardized error messaging for MFA report retrieval
  - `Get-M365LicenceOverview` - Enhanced error handling for license processing
  - `Remove-GTUserEntitlements` - Better error reporting for user lookup failures

- **Internal Helper Functions** - Consistent error handling in:
  - `Remove-GTPIMRoleEligibility` - Improved error reporting for PIM role eligibility operations
  - `Remove-GTUserAccessPackageAssignments` - Better error context for access package operations
  - `Remove-GTUserAdministrativeUnitMemberships` - Enhanced error handling for administrative unit operations
  - `Remove-GTUserRoleAssignments` - Standardized error messages for role assignment operations
  - `Remove-GTUserDelegatedPermissionGrants` - Improved error reporting for OAuth permission operations
  - `Remove-GTUserEnterpriseAppOwnership` - Better error context for application ownership operations

### Testing
- Updated test files to properly source `Get-GTGraphErrorDetails` helper function
- Validated all modified functions pass syntax validation and existing tests

### Developer Experience
- More consistent error handling patterns make it easier to add new Graph API operations
- Centralized error parsing reduces code duplication and maintenance burden
- Improved logging helps with troubleshooting Graph API issues in production environments

## [0.9.1] - 2025-01-14

### Fixed
- **Test-GTGraphScopes** - Improved internal Graph connection validation function
  - Uncommented `return $false` for fail-fast behavior when no Graph context exists
  - Prevents "You cannot call a method on a null-valued expression" errors
  - Preserves existing scopes during reconnection by combining current and required scopes
  - Added post-reconnect verification to ensure all requested permissions were granted
  - Enhanced error messages for better troubleshooting

### Changed
- **Test-GTGraphScopes** - Improved reconnection logic to maintain user's existing Graph API permissions

## [0.9.0] - 2025-01-14

### Added
- **PIM Role Eligibility Removal** - Critical security enhancement for offboarding processes
  - New internal function `Remove-GTPIMRoleEligibility` to remove PIM (Privileged Identity Management) role eligibility schedules
  - Prevents users from activating privileged roles after offboarding
  - Integrated into `Remove-GTUserEntitlements` with new `-removePIMRoleEligibility` switch parameter
  - Automatically included when using `-removeAll` parameter
  - Added required Graph API scope: `RoleEligibilitySchedule.ReadWrite.Directory`
  - Comprehensive test coverage with 11 unit tests

### Fixed
- Added `[AllowEmptyCollection()]` attribute to new function's collection parameter for PowerShell 7+ compatibility

### Security
- Closed critical security gap: Users with PIM role eligibilities can no longer activate privileged roles after account remediation

## [0.8.1] - 2025-01-13

### Added
- Made `Remove-GTUserEntitlements` a public function for direct use by module consumers

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

[Unreleased]: https://github.com/MARCO-K/GraphTools/compare/v0.10.0...main
[0.10.0]: https://github.com/MARCO-K/GraphTools/compare/v0.9.1...v0.10.0
[0.9.1]: https://github.com/MARCO-K/GraphTools/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/MARCO-K/GraphTools/compare/v0.8.1...v0.9.0
[0.8.1]: https://github.com/MARCO-K/GraphTools/compare/v0.0.5...v0.8.1
[0.0.5]: https://github.com/MARCO-K/GraphTools/releases/tag/v0.0.5

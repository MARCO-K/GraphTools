# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.24.1] - 2026-09-25

### Added

- **App Registration Setup & Permission Scenarios Guide (`docs/App-Registration-Setup-Guide.md`)**:
  - Added end-to-end technical walkthrough for provisioning and securing Microsoft Entra ID App Registrations for GraphTools.
  - Details certificate-based authentication (RFC 7523), Azure Managed Identity, client secrets, and interactive PKCE flows.
  - Categorizes least-privilege permission profiles across 4 operational scenarios: Read-Only Security Auditing, Emergency Incident Response, Tenant Hygiene, and Interactive Delegated Console.
  - Provides automated clean PowerShell scripts (`New-MgApplication`, `New-MgServicePrincipal`, `Add-MgApplicationKey`) for SDK-equipped administrators and native OpenSSL commands for Linux/macOS.
  - Highlights essential security rationale for certificate credentials (asymmetric isolation, non-exportable DPAPI protection, elimination of secret leaks).
  - Linked walkthrough from `README.md` and `docs/Connect-GTGraph.md`.

## [0.24.0] - 2026-09-25

### Added

- **Emergency Incident Response Orchestration (`Invoke-GTUserContainment`)**:
  - Implemented single-command containment orchestrator coordinating the 5-step incident response playbook:
    1. Invalidate active OAuth refresh tokens and session cookies (`Revoke-GTSignOutFromAllSessions`).
    2. Disable user account in Microsoft Entra ID (`Disable-GTUser`).
    3. Rotate password to trigger Continuous Access Evaluation (CAE) revocation (`Reset-GTUserPassword`).
    4. Disable all registered and workplace-joined devices (`Disable-GTUserDevice`).
    5. Optionally strip all directory entitlements, group memberships, licenses, and PIM eligibilities (`Remove-GTUserEntitlements`).
  - Supports standard safe containment by default (steps 1-4) and full destructive containment via `-FullContainment` or selective switches (`-RevokeSessions`, `-DisableAccount`, `-ResetPassword`, `-DisableDevices`, `-StripEntitlements`).
  - Full support for pipeline input, `-WhatIf`, `-Confirm`, and `-Force`.
  - Emits structured `PSCustomObject` containment report with per-action outcomes, execution timestamps, and aggregated error reporting.
  - Added full test coverage in `tests/Invoke-GTUserContainment.Tests.ps1` and comprehensive documentation in `docs/Invoke-GTUserContainment.md`.
- **Repository Visual Identity & Branding**:
  - Added new cybersecurity hex shield logo (`assets/logo.jpg`) featuring Entra ID graph topology and circuit-trace wrench.
  - Added wide 16:9 panoramic hero banner (`assets/hero-banner.jpg`) for GitHub and social preview cards.
  - Updated `README.md` to showcase the new high-resolution hero banner and cleaned up legacy root image.

### Fixed

- **Scope Alignment & Least-Privilege Enforcing (`Invoke-GTUserContainment`)**:
  - Updated required device containment scope check to `Device.ReadWrite.All` instead of legacy delegated `Directory.AccessAsUser.All`.
  - Enforced strict least-privilege scoping: `User.ReadWrite.All` is now conditionally requested only when user-specific containment actions are active, allowing isolated device or entitlement containment without over-requesting permissions.
- **Documentation Link Integrity & Scopes**:
  - Converted local markdown links to repository-relative links in `docs/Invoke-GTUserContainment.md`.
  - Added dedicated `## REQUIRED PERMISSIONS` section and updated `docs/User-Security-Response.md`.
  - Added CI integrity test in `tests/Documentation.Tests.ps1` prohibiting local `file:///` URIs in `docs/`.

## [0.23.1] - 2026-09-25

### Fixed

- **Windows PowerShell 5.1 Test Suite & Join-Path Compatibility**:
  - Replaced multi-argument `Join-Path` invocations across 9 test files (`Disable-GTUser`, `Disable-GTUserDevice`, `Get-GTRecentUser`, `Get-M365LicenseOverview`, `Get-MFAReport`, `Invoke-AuditLogQuery`, `Remove-GTUserEnterpriseAppOwnership`, `Reset-GTUserPassword`, `Test-GTGuid`) with single relative child paths (`Join-Path $PSScriptRoot '..\...'`), eliminating `ParameterBindingException` under Windows PowerShell 5.1.
  - Wrapped scalar `PSCustomObject` results in array subexpressions `@(...)` across Pester `.Count | Should -Be 1` assertions, resolving `$null` count failures on Windows PowerShell 5.1.
- **Pipeline Parameter Collision (`Get-GTLegacyAuthReport`)**:
  - Resolved parameter binding collisions where piping values (e.g. `"user@contoso.com" | Get-GTLegacyAuthReport`) triggered false validation errors against `IPAddress`. Routed direct pipeline input through `InputObject` with type/format classification, retaining `ValueFromPipelineByPropertyName` on named parameters.
- **IPv6 Scope Identifier Parsing & Normalization (`Get-GTLegacyAuthReport`)**:
  - Handled IPv6 zone/scope identifiers (e.g. `fe80::1%eth0`) in `IPAddress` parameter validation before passing to `[System.Net.IPAddress]::TryParse()`, fixing validation failures on Windows .NET Framework.
  - Normalized IP strings by stripping zone/scope identifiers upon accumulation into `$targetIPs` and during log filtering comparisons to avoid false negative mismatches against unscoped Graph sign-in log IPs.

## [0.23.0] - 2026-09-25

### Added

- **SecureString Support for Client Secrets (`Connect-GTGraph`, `Get-GTCachedGraphToken`)**:
  - `-ClientSecret` now accepts both encrypted `[System.Security.SecureString]` and plaintext `[string]`.
  - Credentials passed as `SecureString` are retained encrypted in memory and unmarshalled only in-flight during HTTP dispatch.
- **Azure Managed Identity Authentication (`Connect-GTGraph -Identity`)**:
  - Added `-Identity` parameter set for zero-credential authentication within Azure workloads (VMs, App Services, Functions, Container Apps, Automation).
  - Supports System-Assigned Managed Identity and User-Assigned Managed Identity (`-IdentityId`, `-IdentityType ClientId|ResourceId|PrincipalId`).
  - Added internal helper `internal/functions/Get-GTManagedIdentityToken.ps1` with automated IMDS / App Service detection.
- **Interactive Browser Authentication with PKCE (`Connect-GTGraph -Interactive`)**:
  - Implemented OAuth 2.0 Authorization Code flow with Proof Key for Code Exchange (RFC 7636) via local `[System.Net.HttpListener]`.
  - Automatically launches the default browser, intercepts the OAuth callback on `http://localhost:$LocalPort/`, displays a completion page, and completes token exchange.
  - Added internal helper `internal/functions/Invoke-GTOAuthHttpListener.ps1`.
- **Device Code Authentication (`Connect-GTGraph -DeviceCode`)**:
  - Added OAuth 2.0 Device Authorization Grant flow for headless Linux/container environments, remote SSH, and PowerShell remoting sessions.
  - Displays verification URL and code, polling Microsoft identity platform until authorization completes.
  - Added internal helper `internal/functions/Invoke-GTDeviceCodeFlow.ps1`.
- **Automated Silent Refresh Token Renewal (`Get-GTCachedGraphToken`, `Invoke-GTRefreshTokenRenewal`)**:
  - Caches and tracks OAuth 2.0 `refresh_token` across interactive and device code sessions.
  - Automatically executes silent renewal (`grant_type=refresh_token`) when tokens expire or are within the sliding buffer, seamlessly preserving sessions and rolling refresh tokens without re-prompting.
  - Added internal helper `internal/functions/Invoke-GTRefreshTokenRenewal.ps1`.

## [0.22.0] - 2026-09-24

### Added

- **Automated Documentation Link Validation Test (`tests/Documentation.Tests.ps1`)**:
  - Added Pester test to automatically verify relative markdown link integrity across all documentation files, preventing link rot in CI and review workflows.
- **Mid-Pagination Token Refresh & 401 Recovery (`Invoke-GTGraphRequest`)**:
  - Dynamically evaluates cached token expiration before requesting subsequent pages (`@odata.nextLink`) during multi-page queries (`-All`).
  - Added automatic recovery on HTTP `401 Unauthorized`: if token expires or is invalidated mid-pagination, forces cache refresh via `Get-GTCachedGraphToken -ForceRefresh` and retries up to `$MaxRetries`.
  - Added unit test in `tests/Invoke-GTGraphRequest.Tests.ps1` covering 401 recovery and token refresh.
- **Bulk Batch Processing in `Disable-GTUser`**:
  - Pipelined and multi-UPN inputs are now accumulated and processed in chunks of 20 via `Invoke-GTGraphBatch`, reducing HTTP roundtrips from O(N) to O(N/20) while retaining resilient subrequest throttling retries.
  - Preserved single-call execution path for single-user invocations for optimal latency and full backward compatibility.
  - Added batch execution unit tests in `tests/Disable-GTUser.Tests.ps1`.

### Changed

- **Beta Endpoint Discipline (`Invoke-AuditLogQuery`)**:
  - Added explicit architectural justification comments to all Microsoft Graph `/beta/` endpoint calls (`/beta/security/auditLog/queries/`), ensuring full compliance with beta endpoint standards.

### Fixed

- **URL-Encoding for User Principal Names (`Disable-GTUser`)**:
  - Applied `[System.Uri]::EscapeDataString` to UPN paths across both single and batch execution flows, properly escaping characters such as `#` (e.g. for guest accounts with `#EXT#`) to prevent URI truncation.
- **Resilient Batch Exception Handling (`Disable-GTUser`)**:
  - Wrapped `Invoke-GTGraphBatch` in try/catch to ensure all pending users receive structured `Failed` result objects rather than terminating the cmdlet if batch invocation throws.
- **Enriched Link Validation Assertion (`tests/Documentation.Tests.ps1`)**:
  - Added `-Because` failure details displaying all broken relative links directly in the Pester assertion output for actionable CI logs.

## [0.21.0] - 2026-09-24

### Added

- **Resilient Batch Subrequest Throttling & Error Handling (`Invoke-GTGraphBatch`)**:
  - Implemented automated subrequest-level retry for HTTP `429` (Too Many Requests), `503` (Service Unavailable), and `504` (Gateway Timeout).
  - Inspects subrequest `headers` in the JSON batch response for `Retry-After` (supporting integer delta seconds and RFC 1123 HTTP-dates) with case-insensitive parsing.
  - Automatically isolates and re-batches *only* the throttled subrequests up to `-MaxSubrequestRetries` (default: 3) with jittered exponential backoff fallback.
  - Handles dropped subrequests with structured `MissingBatchResponse` diagnostics.
  - Preserves original subrequest sequence in the aggregated output array.
  - Added Pester unit tests covering subrequest 429 retries, retries exhaustion, and permanent error handling.
- **JWT Claim Decoding & Permission Introspection (`Get-GTTokenClaims`)**:
  - Implemented `Get-GTTokenClaims` internal helper to decode base64url JWT access token payloads without external dependencies across Windows PowerShell 5.1 and PowerShell 7+.
  - `Get-GTCachedGraphToken` now automatically decodes token claims on acquisition, populating granted `Roles` (`roles` claim) and `Permissions` (`roles` or `scp` claim) in `$script:GTTokenCache`.
  - `Get-GTConnection` now returns real granted `Scopes` and `Roles` from decoded JWT claims, providing true visibility into active App-only and delegated token permissions.
  - Added unit test suite `tests/Get-GTTokenClaims.Tests.ps1`.

### Changed

- **Harmonized Scope Validation & Connection Gatekeeping (`Test-GTGraphScopes`, `Initialize-GTGraphConnection`)**:
  - Refactored `Test-GTGraphScopes` to validate required scopes against real decoded token claims instead of bypassing validation on `.default`.
  - Added graceful fallback in `Test-GTGraphScopes` when claims cannot be inspected and only `.default` is present.
  - Deprecated dynamic runtime scope renegotiation via `-Reconnect` in `Test-GTGraphScopes`, reflecting the RFC 6749 / Entra ID client credentials standard where application permissions are determined by App Registration roles rather than negotiated per call.
  - `Initialize-GTGraphConnection` now delegates scope checking directly to `Test-GTGraphScopes` as the single source of truth.
  - Harmonized all 17 public reporting and containment cmdlets to follow the canonical execution sequence: connection initialization first, followed by scope validation (without invalid `-Reconnect`).
  - Added `-NewSession` parameter support across `Disable-GTUser`, `Get-GTExpiringSecrets`, `Get-GTInactiveDevices`, `Remove-GTPIMRoleEligibility`, `Remove-GTUserEntitlements`, and `Get-GTConditionalAccessPolicyReport`.

### Fixed

- **`Invoke-AuditLogQuery`**: Corrected parameter typo `RequieredScopes` -> `RequiredScopes` while maintaining `RequieredScopes` as an alias for backward compatibility; replaced unsafe session disconnect in begin block with standard `Initialize-GTGraphConnection`.
- **`Disable-GTUserDevice`**: Updated required scope check from legacy delegated `Directory.AccessAsUser.All` to REST application permission `Device.ReadWrite.All`.
- **`Remove-GTUserEntitlements`**: Replaced inlined `.default` bypass check with unified `Initialize-GTGraphConnection` and `Test-GTGraphScopes`.
- **`Get-GTTokenClaims`**: Sanitized catch block error logging to output only the exception message, eliminating potential exposure of token payload or claim strings in verbose logs.
- **Cmdlet Documentation**: Documented `.PARAMETER NewSession` in comment-based help across 13 public cmdlets to ensure full discoverability via `Get-Help`.

## [0.20.0] - 2026-09-21

### Added

- **Zero-Dependency Microsoft Graph REST Engine**:
  - Implemented `Get-GTCachedGraphToken` supporting RFC 7523 Certificate-based Client Assertion (RS256 JWT via native .NET cryptography) and Client Secret credentials with sliding expiration buffers to eliminate token-endpoint throttling (HTTP 429).
  - Implemented `Invoke-GTGraphRequest` central REST invoker providing automatic Bearer token injection, URL normalization (relative to full endpoint URI), header management (`ConsistencyLevel`, `client-request-id`), automatic `@odata.nextLink` pagination (`-All`), and resilient retry with exponential backoff on HTTP 429 and 503.
  - Added new public connection management cmdlets:
    - `Connect-GTGraph`: Zero-dependency authentication via Certificate Thumbprint, `X509Certificate2` object, Client Secret, or direct Access Token.
    - `Disconnect-GTGraph`: Flushes session context and in-memory token cache.
    - `Get-GTConnection`: Inspects active connection status and token expiration.
  - Comprehensive documentation added in `docs/Connect-GTGraph.md`.
  - Implemented `Invoke-GTGraphBatch` internal helper supporting Microsoft Graph JSON batching (combining up to 20 subrequests into a single HTTP POST to `/$batch` with automatic chunking for arbitrary request counts).
  - Pester 5.7+ test suites added in `tests/Get-GTCachedGraphToken.Tests.ps1`, `tests/Invoke-GTGraphRequest.Tests.ps1`, `tests/Connect-GTGraph.Tests.ps1`, `tests/Invoke-GTGraphPagedRequest.Tests.ps1`, and `tests/Invoke-GTGraphBatch.Tests.ps1`.
- **Enhanced Permission Extraction & Risk Analysis (`Get-GTRiskyAppPermissionReport`)**:
  - Added support for Microsoft Graph Resource-Specific Consent (RSC) permissions via `resourceSpecificApplicationPermissions` caching.
  - Scoped tenant-wide OAuth2 delegated permission grant queries strictly to the Microsoft Graph resource ID (`$filter=resourceId eq '{graphSpId}'`).
  - Added Tier-0 curated attack vectors: `OnPremDirectorySynchronization.ReadWrite.All` (Score 10, Hybrid Identity Takeover), `Domain.ReadWrite.All` (Score 10, Domain Takeover), `UserAuthenticationMethod.ReadWrite.All` (Score 10, Credential Manipulation), `DelegatedPermissionGrant.ReadWrite.All` (Score 10, Privilege Escalation), and `BitlockerKey.Read.All` (Score 8, Cryptographic Exfiltration).
  - Implemented Delegated Privilege Ceiling: adjusts score and level when delegated permissions are granted via user consent (`consentType = 'Principal'`), recognizing that user-scoped grants cannot exceed the delegating user's privileges.
  - Added regex naming heuristics (`\.(ReadWrite|Write|Manage)\.All$`, etc.) with application-scope elevation (+1 score) for unmapped or custom permissions.
- **DevX Permissions Metadata Integration (`Get-GTRiskyAppPermissionReport`)** - Resolves [#80](https://github.com/MARCO-K/GraphTools/issues/80):
  - Integrates official Microsoft Graph DevX permissions metadata with `privilegeLevel` (1–5) for both `Application` and `DelegatedWork` schemes.
  - Added compiled offline metadata fixture `data/graph-permissions.json` (926 permissions) for fast, zero-latency runtime evaluation without external HTTP dependencies.
  - Added internal helper `Get-GTPermissionDefinition` with in-memory caching and custom `-PermissionsFile` support.
  - Added new public utility `Update-GTRiskyPermissionData` to fetch, compile, and update local metadata from upstream DevX on demand.
  - Added `-MinPrivilegeLevel` and `-PermissionsFile` parameters to `Get-GTRiskyAppPermissionReport`.
  - Enriched output `[PSCustomObject]` with `PrivilegeLevel` and `AdminConsentRequired` properties while maintaining complete backward compatibility with existing properties and curated attack vector profiles (*Privilege Escalation*, *Tenant Destruction*).
  - Added dedicated documentation in `docs/Get-GTRiskyAppPermissionReport.md`.
- **License Cost Reporting (`Get-GTLicenseCostReport`)**:
  - Generates license utilization and cost optimization reports across the tenant.
  - Detects "shelfware" (unassigned licenses) and "zombie" licenses (assigned to inactive users).
  - Accepts flexible price input via `-PriceList` (by SkuPartNumber or SkuId string) and supports decimal parsing.
  - Supports `-SkuNameMap` or `-SkuNameFile` to resolve SKU friendly names; falls back to shipped `data/sku-names.json` fixture.
  - Provides `MinWastedThreshold` to filter trivial waste and returns ordered results with `WastedSpend` and remediation recommendations.
  - Includes Pester tests and shipped fixture for deterministic CI runs.
  - Added documentation in `docs/Get-GTLicenseCostReport.md`.
- **Inactive User Safety Filters (`Get-GTInactiveUser`)**:
  - Added `-ExcludeUPN` parameter to explicitly protect specific UPNs from appearing in cleanup candidate output.
  - Added `-ExcludeGlobalAdministrators` switch to exclude members of the Global Administrator role.
  - When `-ExcludeGlobalAdministrators` is requested, role membership resolution failures stop processing to avoid unsafe actions.

### Changed

- **Complete Elimination of External SDK Dependencies**:
  - Fully decoupled the entire module from `Microsoft.Graph.Authentication`, `Microsoft.Graph.*`, `Connect-MgGraph`, `Disconnect-MgGraph`, `Get-MgContext`, and `Invoke-MgGraphRequest`.
  - All 22+ public functions and 27 internal helpers now strictly interact with Microsoft Graph via native REST invokers (`Invoke-GTGraphRequest`, `Invoke-GTGraphPagedRequest`, and `Invoke-GTGraphBatch`) and native token caching (`Connect-GTGraph`, `Get-GTCachedGraphToken`).
  - Removed obsolete `Install-GTRequiredModule` invocations and SDK pre-requisite declarations across all cmdlets.
- **`Invoke-GTGraphPagedRequest`**: Updated to delegate directly to `Invoke-GTGraphRequest -All`, immediately upgrading all module callers to the zero-dependency REST engine without breaking backward compatibility.
- **`Initialize-GTGraphConnection`**: Updated to purely inspect and reuse `$script:GTTokenCache` and connection configuration from `Connect-GTGraph` without external SDK fallback.
- **`GraphTools.psd1`**: Removed external SDK dependencies from `RequiredModules`; only `PSFramework` is now a hard dependency at module level.
- **Beta Endpoint Audit**: All functions validated against Microsoft Learn docs; `beta` is now strictly used only where the property or endpoint is genuinely unavailable in `v1.0`:
  - `signInActivity` on servicePrincipal (not in v1.0): `Get-GTUnusedApps`, `Get-GTServicePrincipalReport` (when `-IncludeSignInActivity`), `Get-GTRiskyAppPermissionReport`
  - `authenticationMethodsUserRegistrationDetails` (not in v1.0): `Get-MFAReport`
  - PIM `roleManagement/directory/*` endpoints: `Get-GTPIMRoleReport`, `Remove-GTPIMRoleEligibility`, `internal/Remove-GTUserRoleAssignments`, `internal/Remove-GTPIMRoleEligibilityInternal`
- **Property Casing Standardization**: All REST response property accesses updated from PascalCase (SDK) to camelCase (REST); output `PSCustomObject` property names preserved in PascalCase for backward compatibility.
- **Elimination of `AdditionalProperties`**: Removed all `$obj.AdditionalProperties['key']` lookups across all models and replaced with direct property access `$obj.key`.
- **`Get-GTInactiveUser`**: Sign-in-only artifact records (Id + sign-in timestamps with no user profile fields) are now excluded by default for safer cleanup targeting; added opt-in switch `-IncludeSignInOnlyRecords`. Switched role and user queries to `v1.0` endpoints (`/directoryRoles` and `/users` with `signInActivity`).
- **DRY Refactoring**: Added internal helpers `Initialize-GTBeginBlock`, `New-GTODataFilter`, and `Invoke-GTGraphPagedRequest` to centralize bootstrap, OData filter composition, and Microsoft Graph pagination handling.
- **Repository Layout & Development Guidance**:
  - Moved `Get-GTAdminCountReport.ps1` and `Get-GTLegacyAuthReport.ps1` into `functions/` so module loading and tests use the same path.
  - Updated `.github/copilot-instructions.md` to reflect native REST invokers and zero external SDK dependencies.
- **UTC Standardization**: Aligned timestamp generation across public functions to `Get-UTCTime` and `[DateTime]::UtcNow`.
- **Loop Control**: Replaced `return` with `continue` in `Get-GTLegacyAuthReport` and `Get-GTOrphanedGroup` filter loops.

### Fixed

- Changelog maintenance: Resolved previously committed merge conflict markers in this file.
- `Initialize-GTGraphConnection`: Fixed `-NewSession` logic to flush only the token cache and force a fresh token acquisition via `Get-GTCachedGraphToken -ForceRefresh`, preserving `$script:GTConnectionConfig` credentials needed for reconnection.
- `Initialize-GTGraphConnection`: Validated token expiration before returning `$true` in `-SkipConnect` mode.
- `Remove-GTPIMRoleEligibilityInternal`: Restored missing `.EXAMPLE` tag in comment-based help to prevent `Get-Help` parameter description truncation.
- `Get-GTInactiveUser`: Removed forced `-Verbose` from dependency installation call so normal executions stay quiet unless caller explicitly requests verbose output.
- `Get-M365LicenseOverview`: Escaped single quotes in `-FilterUser` before building OData `startsWith` filters to prevent invalid filters and unintended semantics.
- `Initialize-GTBeginBlock`: Fixed execution order when both `-InitializeConnection` and `-ValidateScopes` are specified. Connection is now established before scope validation, preventing false failures when no prior `Get-MgContext` exists.
- Tests (`Get-GTGuestUserReport`, `Get-GTInactiveUser`, `Get-M365LicenseOverview`): Added missing `Get-UTCTime.ps1` dot-source in `BeforeAll` to prevent `Get-UTCTime is not recognized` failures when tests run in isolation.
- Tests (`Get-GTLegacyAuthReport`, `Get-GTRiskyAppPermissionReport`): Added missing `Get-UTCTime` stub so test suites work in isolation after those functions adopted the helper.
- `Get-GTGraphErrorDetails`: Explicit null-guard on `InnerException` before accessing `.Response`; merged duplicate 403/404 `switch` cases; added 401 Unauthorized detection and message; updated tests to cover 401 and removed redundant stubs duplicated inside `BeforeAll`.
- `Get-GTGraphErrorDetails` tests: Simplified helper file path composition to a single `Join-Path -Path ... -ChildPath '..\\internal\\functions\\Get-GTGraphErrorDetails.ps1'` call for clearer PowerShell 5.1-compatible test setup.

## [0.19.1] - 2025-11-21

### Added

- Release: Minor maintenance and documentation updates (see Unreleased for details)

## [0.19.0] - 2025-11-21

### Added

- **Administrative Role Security Analysis** - Comprehensive admin role assignment auditing
  - New function `Get-GTAdminCountReport` to analyze Directory Role assignments and member counts
  - Implements risk tier classification (Tier 0 Critical, Tier 1 High, Tier 2 Standard) for security prioritization
  - Categorizes members by type: Users, Service Principals, and Groups with individual counts
  - Provides risk analysis heuristics including Global Admin over-assignment detection (>5 users) and group assignment warnings
  - Supports targeted analysis with RoleName filtering and optional member listing (-ShowMembers)
  - Pipeline support for batch role analysis
  - Automatic sorting by risk tier and member count for security review prioritization
  - Comprehensive test coverage with 15+ test scenarios covering parameter validation, member counting, risk analysis, and output formatting


- **Test Coverage Enhancement** - Comprehensive test suite for application permission risk analysis
  - Added `Get-GTRiskyAppPermissionReport.Tests.ps1` with full Pester test coverage
  - Tests parameter validation, pipeline input, risk scoring logic, and error handling
  - Mocks Microsoft Graph API calls for isolated unit testing
  - Validates app-only and delegated permission analysis scenarios
  - Tests custom risk definitions and filtering capabilities

- **Technical Documentation** - Comprehensive technical architecture guide
  - Added `docs/Technical-Highlights.md` with detailed technical implementation details
  - Documents module architecture, security features, performance characteristics, and integration capabilities
  - Covers advanced analytics features, testing framework, and development practices
  - Provides technical deep-dive complementing user-focused documentation

- **Legacy Authentication Security Analysis** - Comprehensive legacy protocol detection and gap analysis
  - New function `Get-GTLegacyAuthReport` to identify Legacy Authentication usage in Azure AD sign-in logs
  - Implements defensive protocol detection (Legacy list + Modern exclusion) to reduce false positives
  - Classifies successful legacy auth as "Security Gap" and failed attempts as "Attack Attempt"
  - Maps error codes to descriptive failure reasons (MFA blocked, account locked, etc.)
  - Supports targeted filtering by User Principal Name, Client App, and IP Address
  - Pipeline support for batch analysis of users, IPs, and protocols
  - Server-side time filtering for optimal performance
  - Enhanced input validation with UPN regex validation and IP address format checking (IPv4 and IPv6)
  - Standard user parameter aliases (UPN, UserPrincipalName, Users, User, UserName, UPNName)
  - Comprehensive test coverage with 15+ test scenarios covering validation, filtering, and output formatting

### Changed

### Added

- **Application Permission Security Analysis** - Comprehensive app permission risk assessment
  - New function `Get-GTRiskyAppPermissionReport` to audit Service Principal permissions for security risks
  - Analyzes both Application permissions (app roles) and Delegated permissions (OAuth grants)
  - Implements sophisticated risk scoring (1-10 scale) with impact categories (Privilege Escalation, Data Exfiltration, etc.)
  - Provides forensic context: who granted permissions, when, and usage patterns (last sign-in activity)
  - Supports targeted analysis with AppId, PermissionType, and RiskLevel filtering
  - Differentiates tenant-wide vs user-specific permission grants
  - Includes activity monitoring (90-day usage windows) to identify dormant risky permissions
  - Custom risk definitions support via HighRiskScopes parameter
  - Pipeline support for batch application analysis

### Changed

- **UTC Time Handling** - Standardized UTC time retrieval across reporting functions (partial implementation)
  - Added `Get-UTCTime` helper function for consistent UTC time handling
  - Updated reporting functions `Get-GTRecentUser`, `Get-GTUnusedApps`, `Get-GTOrphanedServicePrincipal`, `Get-GTInactiveUser`, `Get-GTInactiveDevices`, and `Get-GTGuestUserReport` to use the helper
  - Note: Other functions (e.g., `Disable-GTUser`, `Disable-GTUserDevice`, `Get-GTExpiringSecrets`) still use the old pattern and will be updated in a future release

### Added

- **Break Glass Account Auditing** - Critical emergency access account security validation
  - New function `Get-GTBreakGlassPolicyReport` to audit Conditional Access policies against emergency access accounts
  - Ensures Break Glass accounts are properly excluded from policies that could block access during incidents
  - Resolves UPNs to Object IDs for accurate policy exclusion checking
  - Prioritizes BLOCK policies as Critical risks vs other controls as High risks
  - Handles complex targeting scenarios: All Users, Specific Users, Groups, and Roles
  - Provides clear risk assessment with actionable remediation guidance
  - Includes NewSession parameter for session management consistency

### Changed

- **UTC Time Handling** - Standardized UTC time retrieval across reporting functions (partial implementation)
  - Added `Get-UTCTime` helper function for consistent UTC time handling
  - Updated reporting functions `Get-GTRecentUser`, `Get-GTUnusedApps`, `Get-GTOrphanedServicePrincipal`, `Get-GTInactiveUser`, `Get-GTInactiveDevices`, and `Get-GTGuestUserReport` to use the helper
  - Note: Other functions (e.g., `Disable-GTUser`, `Disable-GTUserDevice`, `Get-GTExpiringSecrets`) still use the old pattern and will be updated in a future release

### Added

- **Conditional Access Security Analysis** - New comprehensive gap analysis capabilities
  - New function `Get-GTPolicyControlGapReport` to analyze Conditional Access policies for security gaps
  - Detects three types of security gaps: Implicit Allow, Weak Only controls, and Weak Bypass vectors
  - Resolves Authentication Strength GUIDs to friendly names (e.g., "Phishing Resistant")
  - Identifies Custom Controls (3rd party MFA) and bypass scenarios
  - Provides detailed PolicyContext showing user and application scope with exclusion awareness
  - Includes NewSession parameter for session management consistency

### Changed

- **UTC Time Handling** - Standardized UTC time retrieval across reporting functions (partial implementation)
  - Added `Get-UTCTime` helper function for consistent UTC time handling
  - Updated reporting functions `Get-GTRecentUser`, `Get-GTUnusedApps`, `Get-GTOrphanedServicePrincipal`, `Get-GTInactiveUser`, `Get-GTInactiveDevices`, and `Get-GTGuestUserReport` to use the helper
  - Note: Other functions (e.g., `Disable-GTUser`, `Disable-GTUserDevice`, `Get-GTExpiringSecrets`) still use the old pattern and will be updated in a future release

## [0.14.2] - 2025-11-21

### Added

- **Orphaned Resource Detection** - Enhanced capabilities to identify unmanaged resources
  - New function `Get-GTOrphanedServicePrincipal` to detect Service Principals with no owners, disabled owners, or expired credentials
  - added `Get-GTOrphanedServicePrincipal` to the module export list

### Changed

- **Date Formatting** - Standardized OData date formatting across functions
  - Added `Format-ODataDateTime` helper function for consistent ISO 8601 formatting
  - Updated `Get-GTRecentUser`, `Get-GTUnusedApps`, `Get-GTInactiveUser`, `Get-GTInactiveDevices` to use the helper
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
  - `Get-M365LicenseOverview` - Enhanced error handling for license processing
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

[Unreleased]: https://github.com/MARCO-K/GraphTools/compare/v0.24.1...main
[0.24.1]: https://github.com/MARCO-K/GraphTools/compare/v0.24.0...v0.24.1
[0.24.0]: https://github.com/MARCO-K/GraphTools/compare/v0.23.1...v0.24.0
[0.23.1]: https://github.com/MARCO-K/GraphTools/compare/v0.23.0...v0.23.1
[0.23.0]: https://github.com/MARCO-K/GraphTools/compare/v0.22.0...v0.23.0
[0.14.2]: https://github.com/MARCO-K/GraphTools/compare/v0.14.1...v0.14.2
[0.14.0]: https://github.com/MARCO-K/GraphTools/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/MARCO-K/GraphTools/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/MARCO-K/GraphTools/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/MARCO-K/GraphTools/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/MARCO-K/GraphTools/compare/v0.9.1...v0.10.0
[0.9.1]: https://github.com/MARCO-K/GraphTools/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/MARCO-K/GraphTools/compare/v0.8.1...v0.9.0
[0.8.1]: https://github.com/MARCO-K/GraphTools/compare/v0.0.5...v0.8.1
[0.0.5]: https://github.com/MARCO-K/GraphTools/releases/tag/v0.0.5

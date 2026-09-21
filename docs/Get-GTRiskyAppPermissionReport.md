# Get-GTRiskyAppPermissionReport

Audits Microsoft Entra ID (Azure AD) Service Principals for high-risk permissions across the tenant. Evaluates both Application (App-Only) assignments and Delegated OAuth2 permission grants using official Microsoft Graph DevX metadata (`privilegeLevel` 1–5), curated high-impact security threat profiles, and regex-based heuristic analysis for unmapped scopes.

## Purpose & Threat Model

Enterprise applications and service principals represent one of the primary lateral movement and privilege escalation attack vectors in cloud identity systems. Unlike human accounts, service principals often lack multi-factor authentication, conditional access enforcement, or credential rotation lifecycles.

`Get-GTRiskyAppPermissionReport` enables security engineers, threat hunters, and tenant administrators to:
- Identify **Tier-0 tenant takeover pathways** (e.g., directory role assignment capabilities, domain manipulation, hybrid identity sync tampering).
- Detect **broad data exfiltration channels** (e.g., tenant-wide mailbox reads, full SharePoint/OneDrive file access, audit log access).
- Differentiate between **unbounded application permissions** and **user-bounded delegated grants** via the *Delegated Privilege Ceiling*.
- Uncover **dormant or orphaned applications** retaining elevated privileges despite having no operational sign-ins within the last 90 days.

---

## Architecture & Execution Flow

The cmdlet operates in two distinct evaluation phases with dedicated caching and query optimization:

```
[Start]
  │
  ├── 1. Auth & Scopes Check (AppRoleAssignment, DelegatedPermissionGrant, Application, AuditLog, User)
  ├── 2. Load Permissions Catalog (data/graph-permissions.json with in-memory caching)
  ├── 3. Resolve Microsoft Graph Service Principal (00000003-0000-0000-c000-000000000000)
  │      └─ Caches both appRoles and resourceSpecificApplicationPermissions (RSC)
  ├── 4. Retrieve Service Principals (beta/servicePrincipals with signInActivity & appRoleAssignments)
  │
  ├── Phase 1: Application (App-Only) Audit
  │      ├─ Iterates service principals and appRoleAssignments
  │      ├─ Maps appRoleId to friendly permission name via roleMap
  │      ├─ Evaluates risk: Curated -> DevX Scheme-aware -> Heuristic Regex
  │      └─ Computes 90-day activity status from signInActivity
  │
  └── Phase 2: Delegated OAuth2 Permission Grants Audit
         ├─ Queries oauth2PermissionGrants scoped to Graph resourceId
         ├─ Expands space-separated scopes
         ├─ Resolves consenting principal (UPN from user cache or Entire Tenant)
         ├─ Applies Delegated Privilege Ceiling (score decrement for user-consented grants)
         └─ Merges into final report stream
```

### 1. Permission Resolution & RSC Support
At initialization, the cmdlet queries the Microsoft Graph service principal (`appId eq '00000003-0000-0000-c000-000000000000'`) to extract both standard application permissions (`appRoles`) and Resource-Specific Consent permissions (`resourceSpecificApplicationPermissions`). This ensures that scoped permissions (such as Teams or Chat application roles) are resolved into human-readable strings without missing custom or preview roles.

### 2. Scoped Delegated Querying
When evaluating tenant-wide delegated permissions, the cmdlet queries:
```http
GET /v1.0/oauth2PermissionGrants?$filter=resourceId eq '{graphServicePrincipalObjectId}'
```
Filtering by `resourceId` at the API level eliminates downloading grants targeted at third-party applications, Exchange Online, SharePoint Online, or custom enterprise APIs, significantly reducing bandwidth and processing time in large directories.

### 3. Dormancy & Activity Tracking
The cmdlet calculates account activity by evaluating `signInActivity.lastSignInDateTime` against `(Get-UTCTime)`:
- If `lastSignInDateTime` is within the last 90 days, `IsActive` is set to `$true`.
- If older than 90 days (or if the application has never signed in), `IsActive` is `$false`.
*Note*: Querying `signInActivity` requires the `beta` endpoint and `AuditLog.Read.All` privileges.

### 4. In-Memory Caching Strategies
- **DevX Catalog Cache**: Shipped offline metadata (`data/graph-permissions.json`) is loaded once and stored in `$script:GTPermissionCache` for zero-latency lookups across repeated invocations.
- **User Identity Cache**: Consenting user identities (`principalId` on user-scoped grants) are cached in an ephemeral `$UserCache` hashtable during execution to eliminate redundant `v1.0/users/{id}` lookups.

---

## Risk Scoring Framework

`Get-GTRiskyAppPermissionReport` implements a multi-tier evaluation pipeline with three layers of precedence:

```
[Permission Name + Scheme + ConsentType]
                 │
      ┌──────────┴──────────┐
      ▼                     ▼
[In Curated Overrides?] ──► Yes ──► Assign Curated Score & Impact
      │ No                               │
      ▼                                  │
[In DevX Catalog?]      ──► Yes ──► Assign DevX privilegeLevel (1-5)
      │ No                               │
      ▼                                  │
[Regex Naming Heuristics]                │
      │                                  │
      └──────────────────┬───────────────┘
                         ▼
             [Is Delegated + Principal?]
                         │
                 ┌───────┴───────┐
                 ▼ Yes           ▼ No
         [Apply Ceiling]    [Keep Score]
         (Score - 1,        (Full Blast Radius)
          Crit -> High)
```

### 1. Curated Threat Vectors (Tier-0 / High Impact)

Permissions carrying known, catastrophic blast radiuses retain explicit curated scores and impact categorizations:

| Permission | Score | Level | Attack Vector & Impact | Technical Rationale |
| :--- | :---: | :---: | :--- | :--- |
| **`RoleManagement.ReadWrite.Directory`** | 10 | `Critical` | *Privilege Escalation* | Can assign the `Global Administrator` role to itself or another principal. |
| **`AppRoleAssignment.ReadWrite.All`** | 10 | `Critical` | *Privilege Escalation* | Can grant itself any Microsoft Graph application permission without admin intervention. |
| **`OnPremDirectorySynchronization.ReadWrite.All`** | 10 | `Critical` | *Hybrid Identity Takeover* | Can impersonate or tamper with Microsoft Entra Connect sync accounts to compromise on-premises AD and cloud identities. |
| **`Domain.ReadWrite.All`** | 10 | `Critical` | *Domain Takeover* | Can modify tenant verified domains, create federation hijacking paths, or add custom subdomains. |
| **`UserAuthenticationMethod.ReadWrite.All`** | 10 | `Critical` | *Credential Manipulation* | Can reset MFA methods, register FIDO2 keys, and change passwords for all users including admins. |
| **`DelegatedPermissionGrant.ReadWrite.All`** | 10 | `Critical` | *Privilege Escalation* | Can create arbitrary OAuth2 delegated grants across the tenant, bypassing interactive user or admin consent. |
| **`Directory.ReadWrite.All`** | 9 | `Critical` | *Tenant Destruction* | Can delete users, groups, application registrations, and directory objects. |
| **`Mail.ReadWrite`** | 8 | `High` | *Data Integrity* | Can read, modify, and delete all mailbox content across all user accounts in the tenant. |
| **`Files.ReadWrite.All`** | 8 | `High` | *Data Integrity* | Can read, modify, encrypt, or delete all files in OneDrive and SharePoint document libraries. |
| **`BitlockerKey.Read.All`** | 8 | `High` | *Cryptographic Exfiltration* | Can extract all BitLocker drive encryption recovery keys for joined Windows endpoints. |
| **`Mail.Read`** | 7 | `High` | *Data Exfiltration* | Can read all emails in all mailboxes across the organization without restriction. |
| **`Files.Read.All`** | 7 | `High` | *Data Exfiltration* | Can read all files stored across OneDrive and SharePoint sites. |
| **`Mail.Send`** | 6 | `Medium` | *Impersonation* | Can send emails originating from any user identity within the organization. |
| **`User.ReadWrite.All`** | 6 | `Medium` | *User Modification* | Can modify user profiles, directory extensions, and basic identity attributes. |

### 2. Microsoft DevX Metadata Catalog

If a permission is not defined in the curated overrides, it is resolved against official Microsoft Graph DevX metadata (`data/graph-permissions.json`), evaluating the exact scheme (`Application` vs `DelegatedWork`):

| DevX Privilege Level | GraphTools Risk Level | Default Score | Profile Description |
| :---: | :---: | :---: | :--- |
| **5** | `Critical` | 10 | Highest privilege tier: full tenant control, identity takeover, credential manipulation |
| **4** | `High` | 8 | Broad directory mutation, broad mail/files/chat access |
| **3** | `Medium` | 6 | Standard tenant-wide read or scoped write access |
| **2** | `Low` | 4 | Low-privilege basic reads or scoped operations |
| **1** | `Low` | 2 | Least-privilege basic reads or per-user operations |

### 3. Delegated Privilege Ceiling

A fundamental security principle in OAuth2 is that **delegated permissions cannot grant more authority than the executing user possesses**:
- **Tenant-Wide Consent (`consentType = 'AllPrincipals'`)**: Granted by an administrator on behalf of the entire organization. The application can act in the context of any user, including administrators. **Full risk score and risk level are maintained.**
- **User-Specific Consent (`consentType = 'Principal'`)**: Consented by an individual user for their own account only. Even if an application is granted `Directory.ReadWrite.All` or `Mail.ReadWrite`, an unprivileged user cannot perform tenant-wide destruction or read other mailboxes. In this case, `Get-GTRiskyAppPermissionReport` applies a **privilege ceiling**:
  - Score is decremented by 1 (`Score = Max(2, Score - 1)`).
  - Any `Critical` rating is capped at `High`.
  - Scores $\le 6$ map to `Medium`; scores $\le 4$ map to `Low`.

### 4. Dynamic Naming Heuristics (Unmapped Scopes)

For newly released, custom, or private-preview permissions absent from both the curated overrides and the offline metadata fixture, the report dynamically infers risk based on Graph naming conventions:
- `\.(ReadWrite|Write|Manage)\.All$` → Base Score 7 (`High`), Impact *Broad Modification*
- `\.(ReadWrite|Write)$` → Base Score 5 (`Medium`), Impact *Scoped Modification*
- `\.(Read|ReadBasic)\.All$` → Base Score 5 (`Medium`), Impact *Broad Read Access*
- Other scopes → Base Score 5 (`Medium`), Impact *Custom Definition*

**Scheme Adjustments for Heuristic Scopes**:
- If granted as an **Application (App-Only)** permission, the score is elevated by `+1` (capped at 10) to reflect the unconstrained blast radius of background daemon services.
- If granted as a **Delegated (User-Specific)** permission, the score is reduced by `-1` (minimum 2) in accordance with the delegated privilege ceiling.
- `AdminConsentRequired` evaluates to `$null` for heuristic fallbacks to prevent asserting unverified consent requirements for unknown APIs.

---

## Syntax

```powershell
Get-GTRiskyAppPermissionReport [[-AppId] <string[]>] [-PermissionType <string>] [-RiskLevel <string[]>] [-MinPrivilegeLevel <int>] [-PermissionsFile <string>] [-HighRiskScopes <string[]>] [-NewSession] [<CommonParameters>]
```

---

## Parameters

- **`-AppId`** `[string[]]`  
  Optional. Limits analysis to one or more specific Application (Client) IDs. Supports pipeline input by value and property name.

- **`-PermissionType`** `[string]`  
  Filters the permission categories to evaluate.  
  *Accepted values*: `'Both'` (default), `'AppOnly'`, `'Delegated'`.

- **`-RiskLevel`** `[string[]]`  
  Filters the output to specific qualitative risk tiers.  
  *Accepted values*: `'Critical'`, `'High'`, `'Medium'`, `'Low'`.  
  *Default*: Only `Critical` and `High` permissions (or curated overrides) are output when this parameter is omitted.

- **`-MinPrivilegeLevel`** `[int]`  
  Filters permissions by minimum Microsoft DevX privilege level (1–5). For example, `-MinPrivilegeLevel 4` returns only Level 4 and Level 5 permissions.

- **`-PermissionsFile`** `[string]`  
  Custom absolute or relative path to a `graph-permissions.json` metadata fixture. When omitted, defaults to the module's compiled fixture at `data/graph-permissions.json`.

- **`-HighRiskScopes`** `[string[]]`  
  Additional custom permission names or scopes to flag as high-risk regardless of their default catalog classification.

- **`-NewSession`** `[switch]`  
  Forces re-initialization of the Microsoft Graph connection session.

---

## Output Properties

Each detected permission assignment is returned as a strongly typed `[PSCustomObject]` with the following properties:

| Property | Type | Description | Example |
| :--- | :--- | :--- | :--- |
| **`AppName`** | `[string]` | Display name of the client application / service principal. | `"Contoso Sync Service"` |
| **`AppId`** | `[string]` | Application (Client) ID. | `"11111111-2222-3333-4444-555555555555"` |
| **`Type`** | `[string]` | Grant modality: `Application (App-Only)` or `Delegated (Entire Tenant / Specific User)`. | `"Delegated (Entire Tenant)"` |
| **`Permission`** | `[string]` | Identifier of the permission or role. | `"Directory.ReadWrite.All"` |
| **`RiskLevel`** | `[string]` | Qualitative risk classification (`Critical`, `High`, `Medium`, `Low`). | `"Critical"` |
| **`RiskScore`** | `[int]` | Numeric severity score on a 1–10 scale. | `9` |
| **`PrivilegeLevel`** | `[int]` | Official Microsoft DevX privilege level (1–5). `$null` for unmapped scopes. | `5` |
| **`AdminConsentRequired`** | `[bool]` | Whether administrator consent is required. `$null` for unmapped scopes. | `$true` |
| **`Impact`** | `[string]` | Descriptive primary attack vector or privilege classification. | `"Tenant Destruction"` |
| **`GrantedDate`** | `[datetime]` | Timestamp when the assignment or consent grant was created. | `2026-01-15 08:30:00Z` |
| **`GrantedBy`** | `[string]` | Consenting authority (`"Administrator"` or specific user UPN). | `"admin@contoso.com"` |
| **`LastSignIn`** | `[datetime]` | Timestamp of the most recent sign-in activity recorded for the service principal. | `2026-03-01 12:45:00Z` |
| **`IsActive`** | `[bool]` | `$true` if the application has signed in within the past 90 days; otherwise `$false`. | `$false` |
| **`Description`** | `[string]` | Capability summary extracted from metadata or curated definitions. | `"Can delete users, groups, and apps"` |

---

## Required Graph Permissions

Executing `Get-GTRiskyAppPermissionReport` requires authentication with the following Microsoft Graph scopes (delegated or application):

- `AppRoleAssignment.Read.All` (read service principal role assignments)
- `DelegatedPermissionGrant.Read.All` (read OAuth2 permission grants)
- `Application.Read.All` (read service principal and application registrations)
- `AuditLog.Read.All` (read sign-in activity telemetry on service principals)
- `User.Read.All` (resolve consenting user UPNs on user-scoped delegated grants)

---

## Metadata Maintenance

To refresh the local offline metadata fixture with the latest definitions directly from the Microsoft Graph DevX repository:

```powershell
Update-GTRiskyPermissionData -Force
```

This compiles upstream permissions into `data/graph-permissions.json`, extracting privilege levels, descriptions, and admin consent requirements for both Application and DelegatedWork schemes.

---

## Practical Examples

### Example 1 — Full Tenant Security Audit
Audit all service principals across the tenant for High and Critical permissions:

```powershell
Get-GTRiskyAppPermissionReport
```

### Example 2 — Detect Dormant Tier-0 Applications (Immediate Remediation Candidates)
Find inactive service principals (no sign-in in >90 days) holding Critical privileges:

```powershell
Get-GTRiskyAppPermissionReport -RiskLevel Critical |
    Where-Object { -not $_.IsActive } |
    Select-Object AppName, AppId, Permission, RiskScore, LastSignIn, Impact |
    Format-Table -AutoSize
```

### Example 3 — Review Delegated Grants Consented by Specific Users
Identify risky delegated grants consented by regular users rather than tenant admins:

```powershell
Get-GTRiskyAppPermissionReport -PermissionType Delegated |
    Where-Object { $_.Type -like "*Specific User*" } |
    Select-Object AppName, Permission, GrantedBy, RiskScore, RiskLevel
```

### Example 4 — Audit Specific App Registration with Pipeline Export
Audit a specific application by Client ID and export the comprehensive findings to CSV:

```powershell
Get-GTRiskyAppPermissionReport -AppId "a0b1c2d3-e4f5-6789-0123-456789abcdef" -RiskLevel Critical, High, Medium |
    Export-Csv -Path ".\RiskyAppPermissions_Report.csv" -NoTypeInformation
```

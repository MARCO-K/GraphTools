# Get-GTAppConsentReport

Audits Microsoft Entra ID (Azure AD) OAuth 2.0 delegated permission grants (`oauth2PermissionGrants`), third-party application attack surface, and illicit consent risks. Correlates permission grants with Service Principal security metadata (`verifiedPublisher`, `appOwnerOrganizationId`, `replyUrls`) and consenting user identities to identify OAuth consent phishing and privilege escalation vectors.

---

## Purpose & Threat Model

OAuth 2.0 consent grant attacks (OAuth consent phishing) allow malicious or unverified multi-tenant applications to access organizational data under user delegation without acquiring administrative credentials or triggering Multi-Factor Authentication (MFA) prompts once consent has been established.

`Get-GTAppConsentReport` enables SecOps engineers, identity architects, and compliance auditors to:
- **Detect Illicit Consent Grants / Phishing**: Pinpoint unverified external applications that were consented to by individual users (`ConsentType = 'Principal'`) with broad data access scopes (`Mail.ReadWrite`, `Files.ReadWrite.All`).
- **Audit Third-Party Attack Surface**: Identify all multi-tenant applications hosted in external tenants that hold delegated permissions in the local directory.
- **Surface High-Privilege Scopes**: Audit tenant-wide admin consent grants (`AllPrincipals`) possessing critical directory write privileges (`Directory.ReadWrite.All`, `RoleManagement.*`).
- **Enforce Publisher Verification Policies**: Isolate unverified application publishers that have bypassed administrative review.
- **Generate Tenant Posture KPI Summaries**: Provide aggregate compliance metric cards (`-Summary`) for security dashboards and executive reporting.

---

## Security Architecture & Guardrails

To adhere to enterprise security standards, `Get-GTAppConsentReport` incorporates dedicated defensive controls:

1. **Bounded Input Validation**:
   - `AppId`: Enforces `[ValidateLength(1, 128)]` and `[ValidateCount(1, 500)]` on pipeline collections to prevent buffer expansion and memory exhaustion.
   - `DisplayName`: Enforces `[ValidateLength(1, 256)]` and `[ValidateCount(1, 500)]`.
   - `UserId`: Enforces `[ValidateLength(1, 128)]`.
   - `TimeoutSeconds`: Enforces `[ValidateRange(5, 300)]` (defaults to 30 seconds).
2. **Information Leakage Defense (Sanitized Errors)**:
   - User-facing error records are strictly sanitized: raw bearer tokens, internal endpoint URLs, query parameters, and execution stack traces are never emitted to standard error.
   - Detailed forensic exception details are routed exclusively to `Write-PSFMessage -Level Debug` and `-Level Verbose`.
3. **External API Timeouts**:
   - Every Microsoft Graph REST query enforces an operation deadline across both PowerShell 7+ (`OperationTimeoutSeconds`) and Windows PowerShell 5.1 (`TimeoutSec`), mitigating socket exhaustion and Slowloris thread hangs.
4. **Security-Focused Code Comments**:
   - All internal validation rules, OData escaping boundaries, and risk classification routines are annotated with clear threat model rationales explaining *why* the guardrails exist.

---

## Risk Scoring Matrix

Permissions and applications are evaluated against official Microsoft DevX metadata and curated high-impact security profiles:

| Risk Level | Score | Conditions | Action Required |
| :--- | :---: | :--- | :--- |
| **`Critical`** | 9–10 | • Unverified publisher app + user-consented (`Principal`) + high-risk data access (`Mail.*`, `Files.*`)<br>• Any grant with critical directory write permissions (`Directory.ReadWrite.All`, `RoleManagement.ReadWrite.Directory`) | **Immediate Incident Response**: Possible active OAuth consent phishing or severe privilege escalation. Revoke grant immediately. |
| **`High`** | 7–8 | • Admin tenant-wide consent (`AllPrincipals`) for high-privilege scopes (`Mail.ReadWrite`, `Files.ReadWrite.All`, `BitlockerKey.*`)<br>• User-consented grant to unverified publisher with write access (`User.ReadWrite.All`, `Group.ReadWrite.All`) | Audit business justification. Verify application ownership and data access requirements. |
| **`Medium`** | 5–6 | • Verified third-party application granted elevated permissions<br>• Unverified application with non-sensitive or read-only scopes | Periodic review during regular access governance cycles. |
| **`Low`** | 1–4 | • First-party Microsoft applications or verified publisher apps holding basic identity scopes (`User.Read`, `openid`, `profile`, `email`) | Compliant baseline. No action required. |

---

## Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `-AppId` | `[string[]]` | `None` | Filter by one or more Application (Client) IDs. Supports pipeline input by value and property name. |
| `-DisplayName` | `[string[]]` | `None` | Filter by one or more Application Display Names. Supports pipeline input by property name. |
| `-UserId` | `[string]` | `None` | Filter grants consented by a specific User Object ID or UserPrincipalName. |
| `-ConsentType` | `[string]` | `'All'` | Filter by consent scope: `'All'`, `'AllPrincipals'` (admin consent), `'Principal'` (user consent). |
| `-RiskLevel` | `[string[]]` | `None` | Filter output to specific risk levels: `'Critical'`, `'High'`, `'Medium'`, `'Low'`. |
| `-UnverifiedOnly` | `[switch]` | `False` | Filter exclusively for applications whose publisher is not verified by Microsoft. |
| `-ThirdPartyOnly` | `[switch]` | `False` | Filter exclusively for external multi-tenant applications owned outside the local tenant. |
| `-Summary` | `[switch]` | `False` | Emits an aggregated tenant KPI summary card rather than individual grant records. |
| `-PermissionsFile` | `[string]` | `None` | Optional custom file path to a `graph-permissions.json` metadata fixture. |
| `-TimeoutSeconds` | `[int]` | `30` | Timeout deadline in seconds for Microsoft Graph HTTP requests (5–300). |
| `-NewSession` | `[switch]` | `False` | Forces initialization of a fresh Microsoft Graph session. |

---

## Output Objects

### Detailed Grant Record (`[PSCustomObject]`)

```powershell
GrantId                      : abc123def456
AppDisplayName               : SuspiciousPDFSync
AppId                        : 00000000-0000-0000-0000-000000000001
ServicePrincipalId           : 11111111-1111-1111-1111-111111111111
PublisherName                : Unknown Entity
IsPublisherVerified          : False
VerifiedPublisherId          : 
AppOwnerTenantId             : external-tenant-999
IsThirdParty                 : True
ConsentType                  : Principal
ConsentedByUserId            : user-guid-001
ConsentedByUserPrincipalName : alice@contoso.com
ResourceDisplayName          : Microsoft Graph
ResourceId                   : 00000003-0000-0000-c000-000000000000
Scopes                       : {User.Read, Mail.ReadWrite}
HighRiskScopes               : {Mail.ReadWrite}
RiskLevel                    : Critical
RiskScore                    : 9
RiskReasons                  : {Unverified Publisher: Application publisher has not been verified by Microsoft,
                               Third-Party Application: Owned by external tenant (external-tenant-999),
                               High-Risk Scope 'Mail.ReadWrite': Email Exfiltration / Tampering,
                               OAuth Phishing Vector: User consented to high-risk scopes for an unverified publisher}
```

### Summary KPI Card (`-Summary`)

```powershell
TotalGrantsScanned    : 48
TotalAppsScanned      : 22
CriticalCount         : 3
HighCount             : 7
MediumCount           : 14
LowCount              : 24
UnverifiedAppsCount   : 9
ThirdPartyAppsCount   : 15
UserConsentedCount    : 31
AdminConsentedCount   : 17
ScanTimestamp         : 2026-10-01T18:00:00Z
```

---

## Examples

### Example 1: Discover High-Risk & Critical OAuth Grants
```powershell
Get-GTAppConsentReport -RiskLevel Critical, High | Format-Table AppDisplayName, ConsentType, ConsentedByUserPrincipalName, RiskLevel, HighRiskScopes
```

### Example 2: Detect Potential OAuth Phishing Vectors
```powershell
Get-GTAppConsentReport -ConsentType Principal -UnverifiedOnly -ThirdPartyOnly
```

### Example 3: Pipeline Filtering by Application ID
```powershell
"00000000-0000-0000-0000-000000000001", "00000000-0000-0000-0000-000000000002" | Get-GTAppConsentReport
```

### Example 4: Tenant Consent Posture Summary
```powershell
Get-GTAppConsentReport -Summary
```

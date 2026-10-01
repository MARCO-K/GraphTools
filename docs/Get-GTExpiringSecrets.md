# Get-GTExpiringSecrets

Audits Microsoft Entra ID (Azure AD) Applications and Service Principals for expired, expiring, and out-dated credentials (client secrets and certificates). Enriches findings with **Operational Impact Analysis** to evaluate Single Point of Failure (SPOF) risks, active service liveness (`signInActivity`), and ownership accountability.

---

## Purpose & Threat Model

Application and Service Principal credentials represent long-lived authentication keys for automated systems, background daemons, and CI/CD pipelines. Unlike human identities, workloads do not prompt for MFA when credentials expire or leak.

`Get-GTExpiringSecrets` enables security engineers, IT administrators, and DevOps teams to:
- **Prevent Service Outages**: Identify critical credentials approaching expiration before automated workflows or integrations break.
- **Isolate Single Points of Failure (SPOF)**: Detect applications where an expiring secret is the *sole active credential*, eliminating surprises when a rollover has not been configured.
- **Purge Outdated / Abandoned Credentials**: Audit lingering expired secrets that remain attached to enterprise applications as unrotated technical debt and latent attack surface.
- **Identify Orphaned Applications**: Correlate expiring credentials with application ownership to identify high-risk workloads lacking designated team custodians.

---

## Urgency Status Tiers

Credentials are categorized into four standardized urgency tiers based on configurable thresholds:

| Status | Condition | Operational Meaning |
| :--- | :--- | :--- |
| **`Expired`** | `DaysRemaining < 0` | Credential has already expired. Lingering technical debt that should be revoked from the object. |
| **`Critical`** | `0 <= DaysRemaining <= CriticalDays` (default: 7) | Imminent expiration. Requires immediate emergency rotation. |
| **`Warning`** | `CriticalDays < DaysRemaining <= WarningDays` (default: 30) | Standard rotation window. Action required in the current sprint. |
| **`Healthy`** | `DaysRemaining > WarningDays` | Compliant credential with sufficient validity. |

---

## Impact Analysis Engine

When `-IncludeImpactAnalysis` is enabled, the cmdlet calculates operational context to distinguish between active production outages and dormant assets:

### 1. Single Point of Failure (SPOF) Detection
- **`IsSoleCredential` (`[bool]`)**: Checks whether the expiring credential is the *only* currently valid credential on the application or service principal.
  - If `$true`: Expiration results in an immediate 100% hard outage.
  - If `$false`: An alternative valid certificate or secret is present, indicating that a rollover or redundancy strategy is in place.
- **`TotalActiveCredentials` (`[int]`)**: Total count of active, non-expired credentials configured on the target object.

### 2. Active Outage Risk Scoring
Correlates expiration urgency with Microsoft Entra ID sign-in telemetry (`signInActivity.lastSignInDateTime`):

| OutageRisk Score | Conditions | Action Required |
| :--- | :--- | :--- |
| **`Immediate Outage`** | `Critical` or `Expired` + `IsSoleCredential` + sign-in activity within the last 30 days | **P1 Incident Risk**: Active production workload will halt immediately upon expiration. |
| **`High`** | `Critical` or `Expired` + `IsSoleCredential` + sign-in activity unavailable | High probability of service disruption. Verify workload ownership. |
| **`Medium`** | `Critical` or `Expired` with alternative active credentials (rollover in progress), OR sign-in activity between 30 and 90 days ago, OR `Warning` tier with `IsSoleCredential` | Planned rotation or verification of secondary rollover credential. |
| **`Low`** | `Warning` tier with multiple active credentials, OR dormant workload (no sign-ins in >90 days) | Regular maintenance or decommission candidate. |
| **`None`** | `Healthy` tier | No action required. |

### 3. Ownership & Custody Verification
- **`Owners` (`[string]`)**: Semicolon-delimited list of owner UserPrincipalNames or DisplayNames resolved via Microsoft Graph `$expand=owners`.
- **`IsOrphaned` (`[bool]`)**: Flagged as `$true` if the application has zero assigned owners. Orphaned apps with expiring credentials represent severe operational risk because automated notification emails cannot reach a responsible team.

---

## Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `-CriticalDays` | `[int]` | `7` | Threshold in days for `Critical` urgency classification. |
| `-WarningDays` | `[int]` | `30` | Threshold in days for `Warning` urgency classification. |
| `-DaysUntilExpiry` | `[int]` | `None` | Legacy backward-compatibility parameter. Sets warning threshold and limits output to future expiring items. |
| `-Status` | `[string[]]` | `Expired, Critical, Warning` | Filter by status: `All`, `Expired`, `Critical`, `Warning`, `Healthy`. |
| `-IncludeExpired` | `[switch]` | `False` | Includes already-expired credentials in the audit. |
| `-IncludeImpactAnalysis`| `[switch]` | `False` | Enriches results with SPOF detection, outage risk scoring, sign-in telemetry, and owner accountability. |
| `-Summary` | `[switch]` | `False` | Emits an aggregated KPI object rather than individual credential records. |
| `-Scope` | `[string]` | `All` | Scope to scan: `All`, `Applications`, `ServicePrincipals`. |
| `-AppId` | `[string[]]` | `None` | Filter by specific Application (Client) IDs. Supports pipeline input. |
| `-DisplayName` | `[string[]]` | `None` | Filter by Application or Service Principal display names. Supports pipeline input. |
| `-NewSession` | `[switch]` | `False` | Disconnects and re-establishes a fresh Microsoft Graph session. |

---

## Output Properties

### Standard Output Object (`[PSCustomObject]`)

```powershell
Name           : Contoso-Billing-Service
AppId          : 00000000-0000-0000-0000-000000000001
Id             : 11111111-1111-1111-1111-111111111111
ResourceType   : Application
CredentialType : Secret
KeyId          : aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
Hint           : c7x
ExpiryDate     : 2026-10-08T12:00:00Z
DaysRemaining  : 7
Status         : Critical
```

### Impact Analysis Properties (when `-IncludeImpactAnalysis` is specified)

```powershell
IsSoleCredential       : True
TotalActiveCredentials : 1
OutageRisk             : Immediate Outage
LastSignInDateTime     : 2026-10-01T10:30:00Z
Owners                 : devops-lead@contoso.com; svc-admin@contoso.com
IsOrphaned             : False
```

### Summary Output Object (when `-Summary` is specified)

```powershell
TotalAppsScanned        : 142
TotalCredentialsFound   : 210
ExpiredCount            : 18
CriticalCount           : 4
WarningCount            : 12
HealthyCount            : 176
SoleCredentialRiskCount : 3
OrphanedAppsCount       : 2
ScanTimestamp           : 2026-10-01T17:00:00Z
```

---

## Usage Examples

### Example 1: Critical Outage Risk Scan with Impact Analysis
Identifies all credentials expiring in the next 7 days, highlighting single points of failure and production sign-in activity:
```powershell
Get-GTExpiringSecrets -CriticalDays 7 -IncludeImpactAnalysis |
    Where-Object { $_.Status -eq 'Critical' -and $_.IsSoleCredential } |
    Format-Table Name, CredentialType, DaysRemaining, OutageRisk, Owners
```

### Example 2: Audit Lingering Expired Secrets
Scans for all out-dated secrets lingering on tenant applications:
```powershell
Get-GTExpiringSecrets -Status Expired -IncludeImpactAnalysis |
    Select-Object Name, AppId, CredentialType, DaysRemaining, Owners, IsOrphaned
```

### Example 3: Pipeline Input by App ID
Checks a specific application pipeline feed:
```powershell
"00000000-0000-0000-0000-000000000042" | Get-GTExpiringSecrets -IncludeImpactAnalysis
```

### Example 4: Tenant Executive KPI Summary
Generates a rolled-up metric card for operational reporting:
```powershell
Get-GTExpiringSecrets -IncludeImpactAnalysis -Summary
```

---

## Required Permissions

| Operation | Microsoft Graph Permission | Endpoint |
| :--- | :--- | :--- |
| **Directory Credential Scan** | `Application.Read.All` | `v1.0/applications`, `v1.0/servicePrincipals` |
| **Sign-In Telemetry** | `AuditLog.Read.All` (Optional) | `beta/servicePrincipals?$select=signInActivity` |

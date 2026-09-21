# Get-GTRiskyAppPermissionReport

Audits Service Principals for high-risk permissions across the tenant. Evaluates both Application (App-Only) roles and Delegated OAuth2 permission grants using official Microsoft Graph DevX metadata (`privilegeLevel` 1–5) and curated high-impact security profiles.

## Purpose

Enables security engineers and tenant administrators to detect dangerous permissions granted to enterprise applications and service principals, such as tenant takeover vectors, sensitive data exfiltration pathways, and unmonitored high-privilege delegated grants.

## Risk Scoring & DevX Metadata

Permissions are evaluated against the Microsoft Graph DevX metadata catalog (`data/graph-permissions.json`), differentiating between `Application` and `DelegatedWork` schemes:

| DevX Privilege Level | GraphTools Risk Level | Default Score | Profile Description |
| :---: | :---: | :---: | :--- |
| **5** | `Critical` | 10 | Full tenant control, identity takeover, credential manipulation |
| **4** | `High` | 8 | Broad directory mutation, broad mail/files/chat access |
| **3** | `Medium` | 6 | Standard tenant-wide read or scoped write access |
| **1–2** | `Low` | 2–4 | Least-privilege basic reads or user-scoped operations |

### Curated Threat Vectors

Specific critical attack vectors retain curated risk classifications:
- **`RoleManagement.ReadWrite.Directory`**, **`AppRoleAssignment.ReadWrite.All`**, **`DelegatedPermissionGrant.ReadWrite.All`**: Score 10 (`Critical`), Impact *Privilege Escalation*
- **`OnPremDirectorySynchronization.ReadWrite.All`**: Score 10 (`Critical`), Impact *Hybrid Identity Takeover*
- **`Domain.ReadWrite.All`**: Score 10 (`Critical`), Impact *Domain Takeover*
- **`UserAuthenticationMethod.ReadWrite.All`**: Score 10 (`Critical`), Impact *Credential Manipulation*
- **`Directory.ReadWrite.All`**: Score 9 (`Critical`), Impact *Tenant Destruction*
- **`Mail.ReadWrite`**, **`Files.ReadWrite.All`**: Score 8 (`High`), Impact *Data Integrity*
- **`BitlockerKey.Read.All`**: Score 8 (`High`), Impact *Cryptographic Exfiltration*
- **`Mail.Read`**, **`Files.Read.All`**: Score 7 (`High`), Impact *Data Exfiltration*
- **`Mail.Send`**, **`User.ReadWrite.All`**: Score 6 (`Medium`), Impact *Impersonation* / *User Modification*

### Delegated Privilege Ceiling

When an application is granted permissions via user delegation (`consentType = 'Principal'`), the effective blast radius is bounded by the delegating user's direct directory roles. In these scenarios, `Get-GTRiskyAppPermissionReport` applies a privilege ceiling adjustment (score decremented by 1, with `Critical` capped at `High`). Tenant-wide administrator consents (`consentType = 'AllPrincipals'`) retain full risk weighting.

### Heuristic Fallback & RSC Permissions

- **Resource-Specific Application Permissions (RSC)**: Automatically discovers and maps application permissions defined under `resourceSpecificApplicationPermissions` on the Microsoft Graph service principal (e.g. Teams/Chat scopes).
- **Naming Heuristics**: Permissions unmapped in the offline catalog are dynamically inferred from standard naming conventions (e.g., `*.ReadWrite.All` → Score 7/8 `High`, `*.Read.All` → Score 5/6 `Medium`) with an application-scope elevation (+1 score) when running unconstrained without user context.

## Syntax

```powershell
Get-GTRiskyAppPermissionReport [[-AppId] <string[]>] [-PermissionType <string>] [-RiskLevel <string[]>] [-MinPrivilegeLevel <int>] [-PermissionsFile <string>] [-HighRiskScopes <string[]>] [-NewSession] [<CommonParameters>]
```

## Parameters

- **`AppId`** `[string[]]`  
  Optional. Filter by specific Application (Client) IDs. Supports pipeline input.

- **`PermissionType`** `[string]`  
  Filter the type of permissions to analyze: `'AppOnly'`, `'Delegated'`, or `'Both'` (default: `'Both'`).

- **`RiskLevel`** `[string[]]`  
  Filter output by specific risk levels: `'Critical'`, `'High'`, `'Medium'`, `'Low'`. By default, only High and Critical permissions (or curated overrides) are reported.

- **`MinPrivilegeLevel`** `[int]`  
  Optional. Filter permissions by minimum Microsoft DevX privilege level (1–5).

- **`PermissionsFile`** `[string]`  
  Optional. Custom file path to a `graph-permissions.json` metadata fixture. Defaults to the module's shipped `data/graph-permissions.json`.

- **`HighRiskScopes`** `[string[]]`  
  Optional. Additional custom scopes or permissions to flag.

- **`NewSession`** `[switch]`  
  Forces a new Microsoft Graph session.

## Output

Returns `[PSCustomObject]` instances with the following properties:

- **`AppName`** `[string]` — Display name of the client application.
- **`AppId`** `[string]` — Application (Client) ID.
- **`Type`** `[string]` — Grant type (`Application (App-Only)` or `Delegated (Entire Tenant / Specific User)`).
- **`Permission`** `[string]` — Permission/role identifier (e.g. `Directory.ReadWrite.All`).
- **`RiskLevel`** `[string]` — Qualitative risk level (`Critical`, `High`, `Medium`, `Low`).
- **`RiskScore`** `[int]` — Numeric risk score (1–10).
- **`PrivilegeLevel`** `[int]` — Microsoft DevX numerical privilege level (1–5).
- **`AdminConsentRequired`** `[bool]` — Whether admin consent is required for this permission.
- **`Impact`** `[string]` — Primary attack vector or privilege classification.
- **`GrantedDate`** `[datetime]` — Timestamp when the permission was assigned or granted.
- **`GrantedBy`** `[string]` — Consenting entity (`Administrator` or user UPN).
- **`LastSignIn`** `[datetime]` — Most recent sign-in timestamp for the service principal.
- **`IsActive`** `[bool]` — Indicates whether the app signed in within the last 90 days.
- **`Description`** `[string]` — Descriptive summary of the permission's capability.

## Updating Permissions Metadata

To update the local permissions catalog with the latest Microsoft DevX definitions:

```powershell
Update-GTRiskyPermissionData -Force
```

## Examples

### Example 1 — Audit all high-risk permissions across tenant

```powershell
Get-GTRiskyAppPermissionReport
```

### Example 2 — Target a specific application for all permissions with privilege level >= 3

```powershell
Get-GTRiskyAppPermissionReport -AppId "11111111-2222-3333-4444-555555555555" -MinPrivilegeLevel 3
```

### Example 3 — Scan only App-Only Critical permissions

```powershell
Get-GTRiskyAppPermissionReport -PermissionType AppOnly -RiskLevel Critical
```

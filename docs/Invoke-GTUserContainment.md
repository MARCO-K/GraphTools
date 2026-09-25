# Invoke-GTUserContainment

## SYNOPSIS
Orchestrates rapid security containment workflows for compromised Microsoft Entra ID user accounts.

## SYNTAX

```powershell
Invoke-GTUserContainment [-UPN] <String[]>
 [-RevokeSessions]
 [-DisableAccount]
 [-ResetPassword]
 [-DisableDevices]
 [-StripEntitlements]
 [-FullContainment]
 [-Force]
 [-NewSession]
 [-WhatIf]
 [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION
`Invoke-GTUserContainment` is an automated, enterprise-grade incident response orchestrator designed to contain suspected or confirmed compromised Microsoft Entra ID accounts with minimum operational latency.

It coordinates the 5-step containment lifecycle:
1. **Revoke Sessions (`Revoke-GTSignOutFromAllSessions`)**: Invalidates all OAuth 2.0 refresh tokens and browser session cookies.
2. **Disable Account (`Disable-GTUser`)**: Sets `accountEnabled = $false` via Microsoft Graph REST API to block new authentication requests.
3. **Reset Password (`Reset-GTUserPassword`)**: Generates a high-entropy temporary password to trigger Continuous Access Evaluation (CAE) token revocation in supporting applications.
4. **Disable Devices (`Disable-GTUserDevice`)**: Queries all registered and workplace-joined devices owned by the user and sets their status to disabled.
5. **Strip Entitlements (`Remove-GTUserEntitlements`)**: Revokes group memberships, directory roles, licenses, app role assignments, and Privileged Identity Management (PIM) eligibility schedules.

### Default Behavior
By default, standard safe containment executes steps 1 through 4. Step 5 (`StripEntitlements`) is destructive and is only executed when `-StripEntitlements` or `-FullContainment` is explicitly requested.

## REQUIRED PERMISSIONS
The cmdlet dynamically resolves and verifies permissions based on requested actions:
- **Standard Safe Containment** (default): `User.ReadWrite.All`, `Device.ReadWrite.All`
- **Selective Containment**: Only scopes corresponding to the selected action flags
- **Entitlement Stripping** (`-StripEntitlements` / `-FullContainment`): Adds `GroupMember.ReadWrite.All`, `Group.ReadWrite.All`, `Directory.ReadWrite.All`, `RoleManagement.ReadWrite.Directory`, `RoleEligibilitySchedule.ReadWrite.Directory`, `AdministrativeUnit.ReadWrite.All`, `EntitlementManagement.ReadWrite.All`, `DelegatedPermissionGrant.ReadWrite.All`

## PARAMETERS

### -UPN
One or more User Principal Names (UPNs) of the accounts to contain. Must match valid email format (`user@domain.com`).
Accepts pipeline input by value and by property name.

* **Type**: `String[]`
* **Aliases**: `UserPrincipalName`, `Users`, `User`, `UserName`, `UPNName`
* **Position**: 0
* **Default value**: None
* **Accept pipeline input**: True (ByValue, ByPropertyName)

### -RevokeSessions
Invalidates all active OAuth refresh tokens and browser session cookies.

* **Type**: `SwitchParameter`

### -DisableAccount
Sets `accountEnabled` to `$false` to block new authentication requests.

* **Type**: `SwitchParameter`

### -ResetPassword
Generates a high-entropy random password to trigger Continuous Access Evaluation (CAE) session revocation.

* **Type**: `SwitchParameter`

### -DisableDevices
Disables all registered devices associated with the user account.

* **Type**: `SwitchParameter`

### -StripEntitlements
Removes all user entitlements including group memberships, directory roles, licenses, and PIM eligibilities.

* **Type**: `SwitchParameter`

### -FullContainment
Executes all five containment actions including entitlement stripping.

* **Type**: `SwitchParameter`

### -Force
Suppresses confirmation prompts during containment execution.

* **Type**: `SwitchParameter`

### -NewSession
If specified, creates a new Microsoft Graph session by disconnecting any existing session first.

* **Type**: `SwitchParameter`

### -WhatIf
Shows what would happen if the cmdlet runs without making changes.

* **Type**: `SwitchParameter`

### -Confirm
Prompts for confirmation before executing the containment actions.

* **Type**: `SwitchParameter`

## OUTPUTS

### System.Management.Automation.PSCustomObject[]
Returns a structured containment report object per processed account:

| Property | Type | Description |
|---|---|---|
| `UserPrincipalName` | `String` | Target user account UPN |
| `Status` | `String` | `'Contained'` \| `'PartiallyContained'` \| `'Failed'` \| `'WhatIf'` |
| `TimeUtc` | `String` | ISO-8601 UTC execution timestamp |
| `SessionsRevoked` | `Boolean / String` | Session revocation outcome |
| `AccountDisabled` | `Boolean / String` | Account disable outcome |
| `PasswordReset` | `Boolean / String` | Password reset outcome |
| `DevicesDisabled` | `String` | Device disable summary (e.g. `'Disabled (2 device(s))'`) |
| `EntitlementsStripped` | `String` | Entitlement removal status (`'Stripped'`, `'Skipped'`, or `'Failed'`) |
| `ActionsExecuted` | `String[]` | Array of executed action names |
| `Errors` | `String[]` | Array of error messages encountered during execution |

## EXAMPLES

### Example 1: Standard Safe Containment
```powershell
Invoke-GTUserContainment -UPN 'compromised.user@contoso.com'
```
Executes standard safe containment: revokes sessions, disables account, rotates password, and disables all registered devices.

### Example 2: Full Emergency Containment via Pipeline
```powershell
'compromised1@contoso.com', 'compromised2@contoso.com' | Invoke-GTUserContainment -FullContainment -Force
```
Executes all five containment steps including permanent entitlement removal without confirmation prompts.

### Example 3: Selective Containment
```powershell
Invoke-GTUserContainment -UPN 'suspect@contoso.com' -RevokeSessions -ResetPassword
```
Executes selective containment actions: invalidates active sessions and rotates password while leaving account and devices enabled.

### Example 4: Dry-Run with WhatIf
```powershell
Invoke-GTUserContainment -UPN 'user@contoso.com' -WhatIf
```
Displays planned containment actions without executing them against Microsoft Graph.

## RELATED LINKS
- [`Revoke-GTSignOutFromAllSessions`](../functions/Revoke-GTSignOutFromAllSessions.ps1)
- [`Disable-GTUser`](../functions/Disable-GTUser.ps1)
- [`Reset-GTUserPassword`](../functions/Reset-GTUserPassword.ps1)
- [`Disable-GTUserDevice`](../functions/Disable-GTUserDevice.ps1)
- [`Remove-GTUserEntitlements`](../functions/Remove-GTUserEntitlements.ps1)
- [User Security Response Guide](User-Security-Response.md)

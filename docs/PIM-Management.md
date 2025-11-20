# PIM Management Features Walkthrough

This walkthrough demonstrates the new Privileged Identity Management (PIM) features added in version 0.14.0 of GraphTools.

## 1. Generate PIM Role Report

The `Get-GTPIMRoleReport` function provides a comprehensive view of all eligible and active PIM role assignments.

```powershell
# Get a report for all users
$report = Get-GTPIMRoleReport -Verbose

# Display the results
$report | Format-Table User, Role, Type, AssignmentState, EndDateTime -AutoSize
```

**Sample Output:**

| User | Role | Type | AssignmentState | EndDateTime |
|------|------|------|-----------------|-------------|
| John Doe | Global Administrator | Eligible | Eligible | 12/31/2025 11:59:59 PM |
| Jane Smith | User Administrator | Active | Activated (PIM) | 11/20/2025 04:00:00 PM |
| Admin User | Security Administrator | Active | Assigned (Permanent) | |

## 2. Remove PIM Role Eligibility

The `Remove-GTPIMRoleEligibility` function allows you to remove both active and eligible assignments, ensuring complete offboarding.

```powershell
# Remove all PIM roles for a specific user (supports WhatIf)
Remove-GTPIMRoleEligibility -UserId '00000000-0000-0000-0000-000000000000' -Verbose -WhatIf
```

**Key Features:**
- **Dual Targeting**: Removes both `Eligible` (schedules) and `Active` (instances) assignments.
- **Self-Protection**: Warns and requires confirmation if you attempt to remove roles from your own account.
- **Safety**: Supports `-WhatIf` and `-Confirm` parameters.

## 3. Integration with User Offboarding

The `Remove-GTUserEntitlements` function has been updated to include PIM removal.

```powershell
# Complete user offboarding including PIM roles
Remove-GTUserEntitlements -UserUPNs 'user@contoso.com' -removePIMRoleEligibility -Verbose
```

## Verification

The following tests were run to validate the new features:
- `Get-GTPIMRoleReport.Tests.ps1`: Verified report generation and caching logic.
- `Remove-GTPIMRoleEligibility.Tests.ps1`: Verified removal of both active and eligible assignments.

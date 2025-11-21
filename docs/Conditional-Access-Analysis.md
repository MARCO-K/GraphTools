# Conditional Access Policy Analysis

This document describes the two new Conditional Access policy analysis functions in GraphTools: `Get-GTPolicyControlGapReport` and `Get-GTBreakGlassPolicyReport`.

## Overview

Conditional Access policies are critical security controls in Microsoft Entra ID (Azure AD) that enforce access requirements based on user, device, location, and risk conditions. However, misconfigurations can create security gaps or unintended access restrictions. GraphTools now provides specialized functions to audit and validate Conditional Access policy configurations.

## Get-GTPolicyControlGapReport

### Purpose

Analyzes Conditional Access policies to identify security gaps in grant controls, including Authentication Strength policies and Custom Controls.

### Key Features

- **Gap Detection**: Identifies three types of security gaps:
  - **Critical: Implicit Allow** - Policies with no grant controls configured
  - **Critical: Weak Only** - Policies relying solely on weak controls (Terms of Use, password, etc.)
  - **Warning: Weak Bypass** - Strong controls that can be bypassed via OR operator

- **Authentication Strength Resolution**: Converts GUIDs to friendly names (e.g., "Phishing Resistant")
- **Custom Controls Detection**: Identifies 3rd party MFA providers
- **Policy Context Analysis**: Shows user→application scope with exclusion awareness

### Usage Examples

```powershell
# Analyze all enabled policies
Get-GTPolicyControlGapReport

# Check reporting-only policies
Get-GTPolicyControlGapReport -State 'enabledForReportingButNotEnforced'

# Force new Graph session
Get-GTPolicyControlGapReport -NewSession
```

### Sample Output

```powershell
PolicyName      : Require MFA for External Users
PolicyId        : 12345678-1234-1234-1234-123456789012
State           : enabled
GapSeverity     : Warning: Weak Bypass
PolicyContext   : All Users -> All Cloud Apps
GrantOperator   : OR
CurrentControls : mfa, termsOfUse
MissingControls : Operator: AND (Require all)
Reason          : Policy allows bypassing Strong Auth by satisfying Terms of Use.
```

## Get-GTBreakGlassPolicyReport

### Purpose

Audits Conditional Access policies to ensure Break Glass (emergency access) accounts are properly excluded from policies that could block access during security incidents.

### Key Features

- **Emergency Access Protection**: Prevents lockout of critical emergency accounts
- **UPN Resolution**: Converts user input to Object IDs for accurate policy checking
- **Risk Prioritization**:
  - **Critical**: BLOCK policies where accounts are not excluded
  - **High**: Other controls where accounts are not excluded
  - **Potential Risk**: Group-targeted policies (requires manual verification)

- **Comprehensive Targeting Analysis**: Handles All Users, Specific Users, Groups, and Roles
- **Smart Filtering**: Reduces noise by only reporting relevant findings

### Usage Examples

```powershell
# Audit single break glass account
Get-GTBreakGlassPolicyReport -BreakGlassUpn "breakglass@contoso.com"

# Audit multiple emergency accounts
Get-GTBreakGlassPolicyReport -BreakGlassUpn "bg1@contoso.com", "bg2@contoso.com"

# Find critical risks only
Get-GTBreakGlassPolicyReport -BreakGlassUpn "emergency@contoso.com" |
    Where-Object { $_.Severity -eq 'Critical' }
```

### Sample Output

```powershell
PolicyName      : Block Legacy Authentication
PolicyId        : 87654321-4321-4321-4321-210987654321
State           : enabled
BreakGlassUser  : breakglass@contoso.com
Status          : RISK
Severity        : Critical
Reason          : User is INCLUDED in a BLOCK policy and NOT excluded.
GrantControls   : block
```

## Common Use Cases

### Security Audits

- **Monthly Reviews**: Run both functions to ensure policy hygiene
- **Pre-Incident Validation**: Verify break glass accounts before security events
- **Policy Changes**: Audit impact after modifying Conditional Access policies

### Incident Response

- **Emergency Access Verification**: Confirm break glass accounts remain accessible
- **Policy Gap Assessment**: Identify weak points that could be exploited
- **Risk Mitigation**: Address critical gaps before they cause issues

## Required Permissions

Both functions require:

- `Policy.Read.All` - To read Conditional Access policies
- `User.Read.All` - To resolve UPNs to Object IDs (Break Glass function only)

## Best Practices

### Regular Auditing

- Run `Get-GTPolicyControlGapReport` monthly to maintain policy hygiene
- Execute `Get-GTBreakGlassPolicyReport` before and after policy changes
- Include in automated security monitoring workflows

### Break Glass Account Management

- Maintain accurate list of emergency access accounts
- Regularly verify exclusions in critical policies
- Document break glass procedures and account usage

### Policy Design

- Use AND operators for strong controls to prevent bypass
- Explicitly exclude break glass accounts from restrictive policies
- Regularly review authentication strength assignments

## Integration with Existing Workflows

These functions complement existing GraphTools capabilities:

- **With Security Incident Response**: Use break glass auditing during incidents
- **With User Management**: Validate policies after user entitlement changes
- **With Reporting**: Include in comprehensive security assessment reports

## Troubleshooting

### Common Issues

- **"No valid Break Glass accounts resolved"**
- Verify UPNs are correct and users exist
- Check User.Read.All permissions
- Ensure accounts are not disabled

#### Empty Results

- Ensure there are Conditional Access policies configured
- Confirm Policy.Read.All permissions
- Check if policies exist in specified states
- Verify Graph connection is active

#### Unexpected Risk Findings

- Review policy conditions and exclusions
- Check for nested group memberships
- Validate authentication strength assignments

## Related Functions

- `Get-MFAReport` - MFA status and methods analysis
- `Get-GTConditionalAccessPolicyReport` - General CA policy reporting
- `Disable-GTUser` - User account management during incidents
- `Revoke-GTSignOutFromAllSessions` - Session termination
- `Get-GTRiskyAppPermissionReport` - Application permission security analysis

---

**Note**: These functions are designed for security professionals and administrators. Always test policy changes in a non-production environment first and ensure appropriate authorization before implementing security controls.

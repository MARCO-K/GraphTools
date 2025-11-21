# Administrative Role Analysis with Get-GTAdminCountReport

## Overview

The `Get-GTAdminCountReport` function provides comprehensive analysis of Microsoft Entra ID administrative roles, including member counts, risk tier classification, and detailed member listings. This function helps security administrators understand role distribution, identify over-privileged roles, and assess security posture across administrative assignments.

## Risk Tier Classification

The function categorizes administrative roles into three risk tiers based on Microsoft's security best practices:

### Tier 0 (Critical)

- **Global Administrator** - Complete access to all administrative features
- **Privileged Role Administrator** - Can manage role assignments
- **User Access Administrator** - Can manage user access to Azure resources
- **Privileged Authentication Administrator** - Can reset passwords and manage authentication methods

### Tier 1 (High Risk)

- **Security Administrator** - Manages security features and policies
- **Exchange Administrator** - Manages Exchange Online
- **SharePoint Administrator** - Manages SharePoint Online
- **Intune Administrator** - Manages device and application policies

### Tier 2 (Standard)

- All other administrative roles not classified as Tier 0 or Tier 1

## Function Parameters

### -RoleName

- **Type**: `string[]`
- **Aliases**: `Roles`, `Role`, `Name`
- **Description**: Specify one or more administrative role names to analyze. Supports pipeline input.
- **Default**: All administrative roles

### -RiskTier

- **Type**: `string`
- **Valid Values**: `Tier0`, `Tier1`, `Tier2`
- **Description**: Filter results to show only roles within the specified risk tier.

### -ShowMembers

- **Type**: `switch`
- **Description**: Include detailed member information for each role, showing individual users, service principals, and groups.

### -SortBy

- **Type**: `string`
- **Valid Values**: `RoleName`, `MemberCount`, `RiskTier`
- **Default**: `RoleName`
- **Description**: Sort the output by the specified property.

### -NewSession

- **Type**: `switch`
- **Description**: Force a new Microsoft Graph connection session.

## Output Properties

### Standard Output (without -ShowMembers)

- **RoleName**: The display name of the administrative role
- **MemberCount**: Total number of members (users + service principals + groups)
- **UserCount**: Number of user members
- **ServicePrincipalCount**: Number of service principal members
- **GroupCount**: Number of group members
- **RiskTier**: Risk classification (Tier0, Tier1, Tier2)
- **RiskLevel**: Human-readable risk description

### Detailed Output (with -ShowMembers)

All standard properties plus:

- **Members**: Array of member objects with the following properties:
  - **DisplayName**: Member display name
  - **UserPrincipalName**: UPN for users (null for service principals/groups)
  - **Id**: Microsoft Graph object ID
  - **Type**: Member type (`User`, `ServicePrincipal`, `Group`)

## Usage Examples

### Basic Usage

```powershell
# Analyze all administrative roles
Get-GTAdminCountReport

# Focus on critical Tier 0 roles only
Get-GTAdminCountReport -RiskTier Tier0

# Analyze specific roles
Get-GTAdminCountReport -RoleName 'Global Administrator', 'Security Administrator'
```

### Detailed Member Analysis

```powershell
# Include member details for all roles
Get-GTAdminCountReport -ShowMembers

# Analyze specific role with member details
Get-GTAdminCountReport -RoleName 'Global Administrator' -ShowMembers

# Focus on high-risk roles with members
Get-GTAdminCountReport -RiskTier Tier1 -ShowMembers
```

### Sorting and Filtering

```powershell
# Sort by member count (most populated roles first)
Get-GTAdminCountReport -SortBy MemberCount

# Sort by risk tier
Get-GTAdminCountReport -SortBy RiskTier

# Combine filtering and sorting
Get-GTAdminCountReport -RiskTier Tier0 -SortBy MemberCount
```

### Pipeline Support

```powershell
# Pipeline role names
'Global Administrator', 'User Administrator', 'Security Administrator' | Get-GTAdminCountReport

# Pipeline with member details
'Global Administrator' | Get-GTAdminCountReport -ShowMembers
```

### Advanced Analysis

```powershell
# Find roles with high member counts (potential security concern)
Get-GTAdminCountReport | Where-Object { $_.MemberCount -gt 10 }

# Identify roles with service principal members (automation accounts)
Get-GTAdminCountReport -ShowMembers | Where-Object { $_.ServicePrincipalCount -gt 0 }

# Export to CSV for reporting
Get-GTAdminCountReport -ShowMembers | Export-Csv -Path 'AdminRoleAnalysis.csv' -NoTypeInformation
```

## Security Considerations

### Risk Assessment Logic

The function implements security heuristics to identify potentially problematic role assignments:

- **Global Administrator with >5 users**: High risk due to broad access
- **Group-based assignments**: May hide individual accountability
- **Service Principal assignments**: Should be limited and monitored
- **Empty roles**: May indicate configuration issues or unused permissions

### Member Type Analysis

- **Users**: Individual administrative accounts - should follow least privilege
- **Service Principals**: Application/service accounts - should have minimal required permissions
- **Groups**: Role-assignable groups - enable dynamic membership but require careful management

## Required Permissions

- **Directory.Read.All** or **Directory.ReadWrite.All**: Required to read directory role definitions and memberships
- **RoleManagement.Read.Directory**: Required for role management operations

## Error Handling

The function includes comprehensive error handling:

- **Connection Issues**: Automatic retry with user-friendly error messages
- **Permission Errors**: Clear indication of missing Graph API permissions
- **Invalid Role Names**: Validation of role name parameters
- **API Throttling**: Built-in handling of rate limiting with retry logic

## Performance Considerations

- **Large Directories**: Function processes all administrative roles and their members
- **Member Expansion**: `-ShowMembers` parameter retrieves detailed member information
- **Caching**: Results are not cached; each run queries current directory state
- **Pipeline Efficiency**: Supports pipeline input for batch processing

## Integration with Other GraphTools Functions

```powershell
# Combine with user analysis
$adminUsers = Get-GTAdminCountReport -ShowMembers | Select-Object -ExpandProperty Members | Where-Object { $_.Type -eq 'User' }
$adminUsers.UserPrincipalName | Get-MFAReport

# Check for inactive administrators
$adminUsers.UserPrincipalName | Get-GTInactiveUsers -InactiveDaysOlderThan 90

# Audit recent role changes
Invoke-AuditLogQuery -Operations 'Add member to role', 'Remove member from role' -StartDays 30
```

## Output Examples

### Standard Output

```powershell
RoleName                  MemberCount UserCount ServicePrincipalCount GroupCount RiskTier RiskLevel
--------                  ----------- --------- -------------------- ---------- -------- ---------
Global Administrator               3         2                    1          0     Tier0 Critical
Security Administrator             5         4                    0          1     Tier1 High Risk
User Administrator                 8         7                    1          0     Tier1 High Risk
```

### Detailed Output with Members

```powershell
RoleName             : Global Administrator
MemberCount          : 3
UserCount            : 2
ServicePrincipalCount: 1
GroupCount           : 0
RiskTier             : Tier0
RiskLevel            : Critical
Members              : {@{DisplayName=John Admin; UserPrincipalName=john@contoso.com; Id=12345...; Type=User}, @{DisplayName=Jane Admin; UserPrincipalName=jane@contoso.com; Id=67890...; Type=User}, @{DisplayName=Automation Service; UserPrincipalName=; Id=abcde...; Type=ServicePrincipal}}
```

## Troubleshooting

### Common Issues

1. **"Access denied" errors**: Verify Directory.Read.All permission is granted
2. **Empty results**: Check that administrative roles exist in the tenant
3. **Slow performance**: Large directories may take time to enumerate all members
4. **Connection timeouts**: Use `-NewSession` to establish fresh Graph connection

### Validation

```powershell
# Verify permissions
Get-MgContext | Select-Object -ExpandProperty Scopes

# Test basic connectivity
Get-MgDirectoryRole | Select-Object -First 1

# Check role exists
Get-MgDirectoryRole -Filter "displayName eq 'Global Administrator'"
```

## Best Practices

1. **Regular Auditing**: Run this report monthly to monitor administrative role changes
2. **Principle of Least Privilege**: Use member counts to identify over-assigned roles
3. **Service Account Management**: Monitor service principal assignments carefully
4. **Group-Based Assignment**: Consider using role-assignable groups for dynamic membership
5. **Emergency Access**: Ensure break-glass accounts are properly identified and monitored

## Related Functions

- `Get-GTPIMRoleReport`: Analyze Privileged Identity Management role assignments
- `Get-GTConditionalAccessPolicyReport`: Review Conditional Access policies
- `Get-GTBreakGlassPolicyReport`: Audit emergency access accounts
- `Remove-GTUserEntitlements`: Remove administrative role assignments

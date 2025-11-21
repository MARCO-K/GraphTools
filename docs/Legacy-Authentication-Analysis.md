# Legacy Authentication Analysis

## Overview

Legacy authentication protocols represent a significant security risk in modern Microsoft 365 environments. The `Get-GTLegacyAuthReport` function provides comprehensive analysis of Azure AD sign-in logs to identify Legacy Authentication usage, helping security teams identify security gaps and potential attack vectors.

## What is Legacy Authentication?

Legacy authentication refers to older protocols that don't support modern security features like:

- **Multi-Factor Authentication (MFA)**
- **Conditional Access policies**
- **Token-based authentication**
- **Certificate-based authentication**

### Common Legacy Protocols

| Protocol | Description | Security Risk |
|----------|-------------|---------------|
| **POP3** | Post Office Protocol v3 | High - No MFA support |
| **IMAP4** | Internet Message Access Protocol v4 | High - No MFA support |
| **SMTP** | Simple Mail Transfer Protocol | High - Basic auth only |
| **Exchange ActiveSync** | Mobile device synchronization | Medium - Limited CA support |
| **MAPI over HTTP** | Outlook MAPI protocol | Medium - Legacy protocol |
| **Exchange Online PowerShell** | Remote PowerShell | Low - Admin tool |
| **Exchange Web Services** | Exchange API access | Low - Modern protocol |

## Function Capabilities

### Core Features

- **Defensive Protocol Detection**: Uses both inclusion (legacy protocols) and exclusion (modern protocols) for accuracy
- **Security Classification**: Automatically classifies successful legacy auth as "Security Gap" and failed attempts as "Attack Attempt"
- **Error Code Mapping**: Translates Azure AD error codes to descriptive failure reasons
- **Pipeline Support**: Efficient batch processing of users, IPs, and protocols
- **Server-Side Filtering**: Optimized performance with time-based filtering at the API level

### Advanced Filtering

```powershell
# Analyze specific users
Get-GTLegacyAuthReport -UserPrincipalName "user@contoso.com"

# Check multiple protocols
Get-GTLegacyAuthReport -ClientAppUsed "POP3", "IMAP4"

# Filter by source IP
Get-GTLegacyAuthReport -IPAddress "192.168.1.100"

# IPv6 addresses are also supported
Get-GTLegacyAuthReport -IPAddress "2001:db8::1"

# Focus on security gaps only
Get-GTLegacyAuthReport -SuccessOnly

# Extended timeframe
Get-GTLegacyAuthReport -DaysAgo 30
```

## Output Analysis

### Result Classification

The function returns structured data with security-focused classification:

```powershell
# Security Gap (successful legacy authentication)
@{
    CreatedDateTime   = "2025-11-21T10:30:00Z"
    UserPrincipalName = "user@contoso.com"
    ClientAppUsed     = "POP3"
    Result            = "Security Gap (Success)"
    Status            = "Success"
    ErrorCode         = 0
    FailureReason     = $null
    IPAddress         = "192.168.1.100"
    Location          = "Seattle, US"
    AppDisplayName    = "Outlook"
    RequestId         = "abc123-def456"
}

# Attack Attempt (failed legacy authentication)
@{
    CreatedDateTime   = "2025-11-21T10:35:00Z"
    UserPrincipalName = "attacker@external.com"
    ClientAppUsed     = "POP3"
    Result            = "Attack Attempt (Failed)"
    Status            = "Failure"
    ErrorCode         = 50126
    FailureReason     = "Invalid username/password"
    IPAddress         = "203.0.113.1"
    Location          = "Unknown, Unknown"
    AppDisplayName    = "Outlook"
    RequestId         = "xyz789-uvw012"
}
```

### Error Code Mapping

Common Azure AD error codes are mapped to security-relevant descriptions:

| Error Code | Description | Security Context |
|------------|-------------|------------------|
| `50034` | User not found | Account enumeration attempt |
| `50053` | Account locked | Brute force protection triggered |
| `50055` | Password expired | Stale credential usage |
| `50056` | Invalid password | Authentication failure |
| `50057` | User disabled | Disabled account access attempt |
| `50076` | MFA required (Legacy Blocked) | **Critical**: Legacy protocol blocked by MFA policy |
| `50079` | MFA enrollment required | MFA setup required |
| `50126` | Invalid username/password | Credential stuffing attack |
| `53003` | Blocked by CA | Conditional Access policy enforcement |

## Security Use Cases

### 1. Security Gap Identification

Identify users successfully using legacy protocols that bypass modern security controls:

```powershell
# Find all successful legacy authentication in the last 7 days
$securityGaps = Get-GTLegacyAuthReport -SuccessOnly

# Group by user to identify patterns
$securityGaps | Group-Object UserPrincipalName | Sort-Object Count -Descending

# Focus on high-risk protocols
$securityGaps | Where-Object { $_.ClientAppUsed -in @("POP3", "IMAP4") }
```

### 2. Attack Detection

Monitor for failed legacy authentication attempts that may indicate attacks:

```powershell
# Find failed legacy authentication attempts
$attackAttempts = Get-GTLegacyAuthReport | Where-Object { $_.Status -eq "Failure" }

# Identify brute force patterns
$attackAttempts | Group-Object IPAddress | Where-Object { $_.Count -gt 5 }

# Check for MFA bypass attempts
$attackAttempts | Where-Object { $_.ErrorCode -eq 50076 }
```

### 3. Compliance Monitoring

Track legacy protocol usage for compliance and migration planning:

```powershell
# Monthly legacy authentication report
Get-GTLegacyAuthReport -DaysAgo 30 | Export-Csv -Path "LegacyAuth-November2025.csv"

# Identify users needing migration
$legacyUsers = Get-GTLegacyAuthReport -SuccessOnly |
    Select-Object UserPrincipalName -Unique

# Protocol usage statistics
Get-GTLegacyAuthReport | Group-Object ClientAppUsed
```

### 4. Conditional Access Validation

Verify that legacy protocols are properly blocked by Conditional Access policies:

```powershell
# Check if legacy auth is being blocked
$blockedAttempts = Get-GTLegacyAuthReport |
    Where-Object { $_.ErrorCode -eq 53003 }  # Blocked by CA

if ($blockedAttempts.Count -eq 0) {
    Write-Warning "No legacy authentication blocked by Conditional Access - review policies!"
}
```

## Performance Considerations

### Optimization Features

- **Server-Side Time Filtering**: Uses OData `$filter` for efficient date-based queries
- **Pipeline Accumulation**: Collects all input before making API calls (accumulate-then-execute pattern)
- **Defensive Filtering**: Reduces false positives through dual inclusion/exclusion logic
- **Streaming Processing**: Processes large result sets without loading everything into memory

### Best Practices

```powershell
# Use specific timeframes for better performance
Get-GTLegacyAuthReport -DaysAgo 7  # Faster than 30 days

# Filter at the source when possible
Get-GTLegacyAuthReport -UserPrincipalName "vip@contoso.com" -SuccessOnly

# Use pipeline for batch operations
$criticalUsers | Get-GTLegacyAuthReport -ClientAppUsed "POP3"
```

## Integration with Other GraphTools Functions

### Combined Security Analysis

```powershell
# Find users with legacy auth and check their MFA status
$legacyUsers = Get-GTLegacyAuthReport -SuccessOnly |
    Select-Object -ExpandProperty UserPrincipalName -Unique

Get-MFAReport -UserPrincipalName $legacyUsers -UsersWithoutMFA
```

### Incident Response Workflow

```powershell
# Identify compromised account using legacy protocols
$suspiciousActivity = Get-GTLegacyAuthReport -IPAddress "suspicious.ip.address"

if ($suspiciousActivity) {
    $user = $suspiciousActivity[0].UserPrincipalName

    # Execute containment
    Revoke-GTSignOutFromAllSessions -UPN $user
    Disable-GTUser -UPN $user
    Reset-GTUserPassword -UPN $user
}
```

### Audit Log Correlation

```powershell
# Correlate legacy auth with audit logs
$legacyEvents = Get-GTLegacyAuthReport -UserPrincipalName "user@contoso.com"

foreach ($event in $legacyEvents) {
    # Query audit logs around the same time
    Invoke-AuditLogQuery -UserIds $event.UserPrincipalName `
        -StartDate $event.CreatedDateTime.AddMinutes(-5) `
        -EndDate $event.CreatedDateTime.AddMinutes(5)
}
```

## Migration Strategies

### Phase 1: Discovery and Assessment

```powershell
# Baseline current legacy usage
$baseline = Get-GTLegacyAuthReport -DaysAgo 30
$baseline | Export-Csv -Path "LegacyAuth-Baseline.csv"

# Identify high-risk users
$highRiskUsers = $baseline |
    Where-Object { $_.ClientAppUsed -in @("POP3", "IMAP4", "SMTP") } |
    Group-Object UserPrincipalName |
    Sort-Object Count -Descending
```

### Phase 2: Targeted Remediation

```powershell
# Disable legacy protocols for high-risk users
$highRiskUsers | ForEach-Object {
    # Implement Conditional Access policies
    # Update user training
    # Replace legacy clients with modern alternatives
}
```

### Phase 3: Monitoring and Enforcement

```powershell
# Continuous monitoring
$dailyReport = Get-GTLegacyAuthReport -DaysAgo 1

if ($dailyReport.Count -gt 0) {
    # Alert security team
    Send-MailMessage -To "security@contoso.com" `
        -Subject "Legacy Authentication Detected" `
        -Body "Found $($dailyReport.Count) legacy authentication events"
}
```

## Troubleshooting

### Common Issues

#### No Results Returned

- Verify Microsoft Graph permissions include `AuditLog.Read.All`
- Check that the specified timeframe contains sign-in activity
- Ensure the user has recent sign-in activity

#### Performance Issues

- Reduce the `DaysAgo` parameter for faster queries
- Use specific filters to reduce result set size
- Consider breaking large queries into smaller timeframes

#### False Positives

- The function uses defensive detection to minimize false positives
- Modern protocols like "Browser" and "Mobile Apps" are excluded
- Review the protocol lists if you encounter unexpected classifications

### Validation Queries

```powershell
# Verify function is working
Get-GTLegacyAuthReport -DaysAgo 1 | Select-Object -First 5

# Check for modern protocols being incorrectly included
Get-GTLegacyAuthReport | Where-Object { $_.ClientAppUsed -in @("Browser", "Mobile Apps and Desktop clients") }

# Validate error code mapping
Get-GTLegacyAuthReport | Where-Object { $_.Status -eq "Failure" } | Select-Object ErrorCode, FailureReason
```

```powershell
# Verify function is working
Get-GTLegacyAuthReport -DaysAgo 1 | Select-Object -First 5

# Check for modern protocols being incorrectly included
Get-GTLegacyAuthReport | Where-Object { $_.ClientAppUsed -in @("Browser", "Mobile Apps and Desktop clients") }

# Validate error code mapping
Get-GTLegacyAuthReport | Where-Object { $_.Status -eq "Failure" } | Select-Object ErrorCode, FailureReason
```

## Related Functions

- `Get-MFAReport` - Check MFA status of users using legacy protocols
- `Get-GTPolicyControlGapReport` - Analyze Conditional Access policies for legacy auth blocking
- `Invoke-AuditLogQuery` - Correlate with detailed audit log information
- `Disable-GTUser` - Respond to compromised accounts identified through legacy auth analysis

## Security Recommendations

1. **Block Legacy Authentication**: Implement Conditional Access policies to block legacy protocols
2. **Monitor Continuously**: Regular analysis of legacy authentication usage
3. **User Education**: Train users on modern authentication methods
4. **MFA Enforcement**: Ensure MFA is required for all authentication methods
5. **Client Migration**: Replace legacy email clients with modern alternatives
6. **Network Controls**: Implement network-level controls for legacy protocol blocking

## References

- [Microsoft: Legacy authentication protocols](https://learn.microsoft.com/en-us/entra/identity/conditional-access/block-legacy-authentication)
- [Microsoft: Plan your legacy authentication strategy](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-block-legacy)
- [Microsoft Graph: Sign-in logs API](https://learn.microsoft.com/en-us/graph/api/resources/signin)
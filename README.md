# MS Graph tools

![GraphTools](image.png)

**GraphTools** is a robust PowerShell module designed for IT security professionals focused on Entra ID and Microsoft 365.

It provides a suite of efficient, forward-thinking cmdlets that simplify complex security tasks such as risk detection, conditional access management, audit log analysis, and incident response.

By leveraging Microsoft Graph, GraphTools enables proactive identity protection and streamlined security management. Whether you’re automating routine security checks or responding to emerging threats, this module empowers you to secure your environment with precision and confidence.

## New Features

### Get-M365LicenseOverview

This function provides a comprehensive view of user licenses and service plans across the organization

### Get-MFAReport

This function collects MFA registration details from Microsoft Graph and provides filtering options for analysis.

### New-AuditLogQuery

This function queries Microsoft 365 audit logs, waits for completion, processes results. You can filter by different Operations or RecordTypes.

### Get-InactiveUsers

Retrieves user accounts with advanced filtering options including inactivity days.

## Manual Installation

1. Clone or download the repository.
2. Copy the GraphTools folder to one of your PowerShell module directories (e.g., $env:USERPROFILE\Documents\PowerShell\Modules).

## Usage

1. Import the Module:

```powershell
Import-Module GraphTools
```

2. Run a Function: For example, to list risky users:

```powershell
Get-MFAReport -UsersWithoutMFA -NoGuestUser
```

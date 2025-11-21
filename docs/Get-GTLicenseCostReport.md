# Get-GTLicenseCostReport

Generates a license utilization and cost optimization report for the tenant. The report identifies purchased vs assigned licenses, unassigned "shelfware", and "zombie" licenses assigned to users inactive for a configurable number of days. It also calculates estimated monthly spend and potential savings.

## Purpose

This function helps administrators and finance teams quickly identify wasted spend on Microsoft 365 licenses and prioritize reclamation actions.

## Syntax

Get-GTLicenseCostReport [-InactiveDays <int>] [-PriceList <IDictionary>] [-SkuNameMap <IDictionary>] [-SkuNameFile <string>] [-MinWastedThreshold <decimal>] [-NewSession]

## Parameters

- InactiveDays [int]
  - Default: 90
  - Threshold (days) to consider an assigned license as "inactive"/"zombie".

- PriceList [IDictionary]
  - A dictionary or hashtable mapping SKU identifiers to a monthly price. Keys may be either the SKU part number (e.g., `ENTERPRISEPACK`) or the SKU ID GUID string.
  - Values can be numeric or strings parseable to decimal (uses invariant culture). Example shapes:
    - `@{ 'ENTERPRISEPACK' = 10.0 }`
    - `@{ '11111111-2222-3333-4444-555555555555' = 8.5 }`

- SkuNameMap [IDictionary]
  - Optional in-memory mapping (hashtable or dictionary) mapping SKU ID strings to friendly names. If supplied, the function prefers this map over any on-disk fixture. Ideal for automation and tests.

- SkuNameFile [string]
  - Optional path to a JSON file containing `{ "SkuNames": { "<SkuId>": "Friendly Name" } }`. Used if `-SkuNameMap` is not provided.

- MinWastedThreshold [decimal]
  - Default: 0.0
  - Filters out SKUs where `WastedSpend` is less than this value. Useful to reduce noise for large tenants.

- NewSession [switch]
  - Forces a new Microsoft Graph session when the function initializes the Graph connection.

## Output

The function returns an array of objects with the following properties (ordered):

- FriendlyName (string)
- SkuPartNumber (string)
- SkuId (string)
- Purchased (int)
- Assigned (int)
- UtilizationPct (decimal)
- Available (int)
- InactiveAssigned (int)
- TotalWastedUnits (int)
- UnitPrice (decimal)
- MonthlySpend (decimal)
- WastedSpend (decimal)
- Recommendation (string)

## Examples

### Example 1 — Basic price list by part number

```powershell
$price = @{ 'ENTERPRISEPACK' = 10.0; 'SPECONLY' = 5.0 }
Get-GTLicenseCostReport -PriceList $price
```

### Example 2 — Price list by SKU ID string

```powershell
$price = @{ '11111111-1111-1111-1111-111111111111' = 8.5 }
Get-GTLicenseCostReport -PriceList $price
```

### Example 3 — Inject friendly names from a hashtable (recommended for automation)

```powershell
$skuMap = @{ '11111111-1111-1111-1111-111111111111' = 'Office 365 E3' }
Get-GTLicenseCostReport -PriceList $price -SkuNameMap $skuMap
```

### Example 4 — Use a file with friendly names

```powershell
# JSON file example (data/sku-names.json)
# { "SkuNames": { "11111111-1111-1111-1111-111111111111": "Office 365 E3" } }
Get-GTLicenseCostReport -PriceList $price -SkuNameFile .\data\sku-names.json
```

## Implementation notes & recommendations

- The function parses price values using invariant culture and coerces them to decimal. Provide numeric values using `.` as the decimal separator to avoid culture mismatch.
- For CI and offline runs the function uses a shipped fixture `data/sku-names.json` when no `-SkuNameMap` or `-SkuNameFile` is provided.
- The function intentionally uses a typed dictionary for price lookups and a typed dictionary for zombie counts to keep memory and CPU usage reasonable for large tenants.
- Use `-MinWastedThreshold` to filter out trivial amounts of wasted spend.

## Troubleshooting

- If you see `Get-MgSubscribedSku` or `Get-MgBetaUser` errors, ensure the Microsoft Graph modules are installed and the calling account has the necessary scopes (`Organization.Read.All`, `User.Read.All`, `AuditLog.Read.All`).
- If friendly names are missing, provide an explicit `-SkuNameMap` or `-SkuNameFile` with the correct SKU ID strings (GUIDs) as keys.

## Tests

- The module includes Pester tests `tests/Get-GTLicenseCostReport.Tests.ps1` which mock Graph calls and validate the computation. Tests inject an in-memory SKU name map and do not modify repository fixtures.

## Related functions

- `Get-M365LicenseOverview` — per-user license details and service plans
- `Remove-GTUserEntitlements` — remove licenses for remediation

---

## Remediation playbook & CSV export

After you run `Get-GTLicenseCostReport`, you can export the results to CSV for finance or ticketing systems and generate a simple remediation playbook. Example pipeline:

```powershell
# 1) Generate the report (inject price list or use defaults)
$report = Get-GTLicenseCostReport -PriceList @{ 'ENTERPRISEPACK' = 10.0 } -MinWastedThreshold 10.0

# 2) Export full report to CSV for finance
$report | Export-Csv -Path .\license-waste-report.csv -NoTypeInformation -Encoding UTF8

# 3) Create a remediation playbook grouped by Recommendation
$playbook = $report | Group-Object -Property Recommendation | ForEach-Object {
  [PSCustomObject]@{
    Recommendation = $_.Name
    Count = ($_.Group).Count
    TotalWasted = ($_.Group | Measure-Object -Property WastedSpend -Sum).Sum
    Actions = ($_.Group | Select-Object SkuId, SkuPartNumber, Available, InactiveAssigned)
  }
}

# 4) Save playbook to JSON for automation teams
$playbook | ConvertTo-Json -Depth 5 | Set-Content -Path .\license-remediation-playbook.json -Encoding UTF8

# 5) Example: automatically queue reclamation tasks for SKUs with "Reclaim" recommendation
$report | Where-Object { $_.Recommendation -like 'Reclaim*' } | ForEach-Object {
  # This is a placeholder for your provisioning system (ticket API, ServiceNow, etc.)
  # Example: create-ticket -Title "Reclaim $($_.InactiveAssigned) licenses for $($_.FriendlyName)" -Body "Details: $($_ | ConvertTo-Json)"
}
```


If you want, I can also add a short example that exports the report to CSV and groups by `Recommendation` to create a remediation playbook.

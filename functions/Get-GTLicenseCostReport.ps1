function Get-GTLicenseCostReport
{
    <#
    .SYNOPSIS
    Generates a license utilization and cost optimization report.

    .DESCRIPTION
    Analyzes the tenant's subscription status to identify:
    1. Utilization: Purchased vs. Assigned vs. Available.
    2. "Shelfware": Unassigned licenses sitting on the shelf.
    3. "Zombie Licenses": Licenses assigned to users who haven't logged in for X days.
    4. Financial Impact: Estimated monthly costs and potential savings based on a provided price list.

    .PARAMETER InactiveDays
    The threshold to consider an assigned license as "Waste" (Zombie). Default is 90 days.

    .PARAMETER PriceList
    A hashtable mapping License SKU Part Numbers (e.g., 'ENTERPRISEPACK') to a monthly cost.
    If not provided, costs default to 0.

    .PARAMETER NewSession
    Forces a new Microsoft Graph session.

    .EXAMPLE
    Get-GTLicenseCostReport -InactiveDays 90
    Generates a report of utilization and waste based on 90-day inactivity.

    .EXAMPLE
    $prices = @{ 'ENTERPRISEPACK' = 32.00; 'EMS' = 10.00 }
    Get-GTLicenseCostReport -PriceList $prices
    Generates a report with financial calculations based on your specific contract prices.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [ValidateRange(30, 365)]
        [int]$InactiveDays = 90,

        [hashtable]$PriceList,

        [switch]$NewSession
    )

    begin
    {
        $modules = @('Microsoft.Graph.Identity.DirectoryManagement', 'Microsoft.Graph.Beta.Users')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        # 1. Scopes Check
        # Organization.Read.All: Required for SubscribedSkus (License counts)
        # User.Read.All + AuditLog.Read.All: Required to find inactive users
        $requiredScopes = @('Organization.Read.All', 'User.Read.All', 'AuditLog.Read.All')
        
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet))
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }

        # 2. Connection Initialization
        if (-not (Initialize-GTGraphConnection -Scopes $requiredScopes -NewSession:$NewSession))
        {
            Write-Error "Failed to initialize session."
            return
        }

        # 3. Load License Reference Cache (Reuse logic from Overview function if available)
        if (-not $script:GTLicenseRefCache)
        {
            Write-PSFMessage -Level Verbose -Message "Initializing License Reference Cache..."
            # Simplified cache logic for this function (PartNumber -> FriendlyName)
            # In a full module, this would be a shared internal helper function.
            $script:GTLicenseRefCache = @{ SkuNames = @{} }
            try
            {
                $csvUrl = 'https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv'
                $skuTable = Invoke-RestMethod -Uri $csvUrl -ErrorAction Stop | ConvertFrom-Csv
                foreach ($row in $skuTable)
                {
                    if ($row.GUID) { $script:GTLicenseRefCache.SkuNames[$row.GUID] = $row.Product_Display_Name }
                }
            }
            catch { Write-Warning "Could not download friendly names. Using SKU IDs." }
        }
    }

    process
    {
        $report = [System.Collections.Generic.List[PSCustomObject]]::new()
        $utcNow = (Get-Date).ToUniversalTime()

        try
        {
            # --- Step 1: Get Inventory (Subscribed SKUs) ---
            Write-PSFMessage -Level Verbose -Message "Fetching Subscription Inventory..."
            $skus = Get-MgSubscribedSku -All -ErrorAction Stop

            # --- Step 2: Find Zombie Users (Inactive) ---
            # We need to know WHICH licenses the inactive users hold.
            # Server-Side Filter: Users who haven't signed in for X days.
            $cutoff = $utcNow.AddDays(-$InactiveDays).ToString("yyyy-MM-ddTHH:mm:ssZ")
            
            Write-PSFMessage -Level Verbose -Message "Scanning for users inactive since $cutoff..."
            
            # We fetch only users who are inactive AND have licenses
            $userParams = @{
                Filter           = "signInActivity/lastSignInDateTime le $cutoff and assignedLicenses/any()"
                Property         = @('id', 'assignedLicenses')
                ConsistencyLevel = 'eventual'
                CountVariable    = 'InactiveCount'
                All              = $true
                ErrorAction      = 'Stop'
            }

            $inactiveUsers = Get-MgBetaUser @userParams
            Write-PSFMessage -Level Verbose -Message "Found $InactiveCount users inactive for >$InactiveDays days."

            # Aggregate Zombie Counts per SKU
            $zombieCountBySku = @{}
            foreach ($u in $inactiveUsers)
            {
                foreach ($lic in $u.AssignedLicenses)
                {
                    if (-not $zombieCountBySku.ContainsKey($lic.SkuId)) { $zombieCountBySku[$lic.SkuId] = 0 }
                    $zombieCountBySku[$lic.SkuId]++
                }
            }

            # --- Step 3: Build Report ---
            foreach ($sku in $skus)
            {
                # Skip "free" or "unlimited" internal SKUs if they clutter the report
                # if ($sku.SkuPartNumber -match "FLOW_FREE") { continue }

                $skuId = $sku.SkuId
                $partNumber = $sku.SkuPartNumber
                
                # Resolve Friendly Name
                $friendlyName = if ($script:GTLicenseRefCache.SkuNames[$skuId]) { $script:GTLicenseRefCache.SkuNames[$skuId] } else { $partNumber }

                # Counts
                $totalPurchased = $sku.PrepaidUnits.Enabled
                $totalAssigned = $sku.ConsumedUnits
                $totalAvailable = $totalPurchased - $totalAssigned # Shelfware
                $totalZombie = if ($zombieCountBySku[$skuId]) { $zombieCountBySku[$skuId] } else { 0 }
                
                # Financials
                $unitPrice = 0
                if ($PriceList -and $PriceList.ContainsKey($partNumber))
                {
                    $unitPrice = $PriceList[$partNumber]
                }
                
                $totalSpend = $totalPurchased * $unitPrice
                $shelfwareCost = $totalAvailable * $unitPrice
                $zombieCost = $totalZombie * $unitPrice
                $potentialSavings = $shelfwareCost + $zombieCost

                # Utilization %
                $utilization = 0
                if ($totalPurchased -gt 0)
                {
                    $utilization = [math]::Round(($totalAssigned / $totalPurchased) * 100, 1)
                }

                $report.Add([PSCustomObject]@{
                        FriendlyName     = $friendlyName
                        SkuPartNumber    = $partNumber
                        Purchased        = $totalPurchased
                        Assigned         = $totalAssigned
                        UtilizationPct   = $utilization
                    
                        # Waste Metrics
                        Available        = $totalAvailable # Unassigned
                        InactiveAssigned = $totalZombie    # Assigned to inactive users
                        TotalWastedUnits = $totalAvailable + $totalZombie
                    
                        # Financial Metrics
                        UnitPrice        = $unitPrice
                        MonthlySpend     = $totalSpend
                        WastedSpend      = $potentialSavings
                        Recommendation   = if ($totalAvailable -gt 0) { "Reduce count by $totalAvailable" } elseif ($totalZombie -gt 0) { "Reclaim $totalZombie licenses" } else { "Optimized" }
                    })
            }

            # Sort by Wasted Spend (Descending) to show biggest money pits first
            return $report | Sort-Object WastedSpend -Descending
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'License Report'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to generate cost report: $($err.Reason)"
            throw $err.ErrorMessage
        }
    }
}
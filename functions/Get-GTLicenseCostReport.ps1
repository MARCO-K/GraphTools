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

    .OUTPUTS
    System.Object
        Properties:
            FriendlyName (string)
            SkuPartNumber (string)
            SkuId (string)
            Purchased (int)
            Assigned (int)
            UtilizationPct (decimal)
            Available (int)
            InactiveAssigned (int)
            TotalWastedUnits (int)
            UnitPrice (decimal)
            MonthlySpend (decimal)
            WastedSpend (decimal)
            Recommendation (string)

    .PARAMETER InactiveDays
    The threshold to consider an assigned license as "Waste" (Zombie). Default is 90 days.

    .PARAMETER PriceList
    A dictionary or hashtable mapping License SKU Part Numbers (e.g., 'ENTERPRISEPACK') OR SKU IDs to a monthly cost.
    Accepts [Hashtable] or [System.Collections.Generic.Dictionary].

    .PARAMETER MinWastedThreshold
    Filter out SKUs where the 'WastedSpend' is below this amount. 
    Useful for large tenants to hide trivial waste (e.g., $0.00). Default is 0.0.

    .PARAMETER NewSession
    Forces a new Microsoft Graph session.

    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [ValidateRange(30, 365)]
        [int]$InactiveDays = 90,

        [System.Collections.IDictionary]$PriceList,
        [System.Collections.IDictionary]$SkuNameMap,
        [string]$SkuNameFile,

        [decimal]$MinWastedThreshold = 0.0,

        [switch]$NewSession
    )

    begin
    {
        # 1. Initialize Collection
        $report = [System.Collections.Generic.List[PSCustomObject]]::new()

        # 2. Module Check
        $modules = @('Microsoft.Graph.Identity.DirectoryManagement', 'Microsoft.Graph.Beta.Users')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        # 3. Scopes Check
        $requiredScopes = @('Organization.Read.All', 'User.Read.All', 'AuditLog.Read.All')
        
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet))
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }

        # 4. Connection Initialization
        if (-not (Initialize-GTGraphConnection -Scopes $requiredScopes -NewSession:$NewSession))
        {
            Write-Error "Failed to initialize session."
            return
        }

        # 5. Load License Reference Cache
        if (-not $script:GTLicenseRefCache)
        {
            Write-PSFMessage -Level Verbose -Message "Initializing License Reference Cache..."
            $script:GTLicenseRefCache = @{ SkuNames = @{} }

            # 5a. First honor an injected hashtable (e.g., tests or automation)
            if ($SkuNameMap -and $SkuNameMap.Keys.Count -gt 0)
            {
                foreach ($k in $SkuNameMap.Keys) { $script:GTLicenseRefCache.SkuNames[[string]$k] = $SkuNameMap[$k] }
            }
            else
            {
                # 5b. Next honor an explicit file path if provided
                if ($SkuNameFile -and (Test-Path $SkuNameFile))
                {
                    try {
                        $json = Get-Content -Path $SkuNameFile -Raw | ConvertFrom-Json
                        if ($json -and $json.SkuNames) {
                            foreach ($prop in $json.SkuNames.PSObject.Properties) { $script:GTLicenseRefCache.SkuNames[$prop.Name] = $prop.Value }
                        }
                    } catch { Write-PSFMessage -Level Verbose -Message "Failed loading SKU names from file: $($_.Exception.Message)" }
                }
                else
                {
                    # 5c. Fallback: try the shipped fixture under module root
                    try
                    {
                        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
                        $skuJsonFile = Join-Path $moduleRoot 'data\sku-names.json'

                        if (Test-Path $skuJsonFile)
                        {
                            $json = Get-Content -Path $skuJsonFile -Raw | ConvertFrom-Json
                            if ($json -and $json.SkuNames)
                            {
                                foreach ($prop in $json.SkuNames.PSObject.Properties)
                                {
                                    $script:GTLicenseRefCache.SkuNames[$prop.Name] = $prop.Value
                                }
                            }
                        }
                    }
                    catch
                    {
                        Write-PSFMessage -Level Verbose -Message "Failed loading SKU names fixture: $($_.Exception.Message)"
                    }
                }
            }
        }

        # 6. Optimize Price List (Ingest into Typed Dictionary)
        # Using OrdinalIgnoreCase allows case-insensitive lookup (e.g. 'EnterprisePack' vs 'ENTERPRISEPACK')
        $priceDict = [System.Collections.Generic.Dictionary[string, decimal]]::new([System.StringComparer]::OrdinalIgnoreCase)
        
        if ($PriceList)
        {
            foreach ($key in $PriceList.Keys)
            {
                $val = $PriceList[$key]
                if ($null -ne $val)
                {
                    # Optimization: If input is already numeric, skip string parsing overhead
                    if ($val -is [decimal] -or $val -is [int] -or $val -is [double]) 
                    {
                        $priceDict[[string]$key] = [decimal]$val
                    }
                    else 
                    {
                        $parsed = 0
                        if ([decimal]::TryParse([string]$val, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed))
                        {
                            $priceDict[[string]$key] = $parsed
                        }
                    }
                }
            }
        }
    }

    process
    {
        $utcNow = if (Get-Command Get-UTCTime -ErrorAction SilentlyContinue) { Get-UTCTime } else { (Get-Date).ToUniversalTime() }

        try
        {
            # --- Step 1: Get Inventory ---
            Write-PSFMessage -Level Verbose -Message "Fetching Subscription Inventory..."
            $skus = Get-MgSubscribedSku -All -ErrorAction Stop

            if (-not $skus)
            {
                Write-PSFMessage -Level Verbose -Message "No subscriptions found in the tenant."
                return @()
            }

            # --- Step 2: Find Zombie Users ---
            $cutoff = $utcNow.AddDays(-$InactiveDays).ToString("yyyy-MM-ddTHH:mm:ssZ")
            
            Write-PSFMessage -Level Verbose -Message "Scanning for users inactive since $cutoff..."
            
            $userParams = @{
                Filter           = "signInActivity/lastSignInDateTime le '$cutoff' and assignedLicenses/any()"
                Property         = @('id', 'assignedLicenses')
                ConsistencyLevel = 'eventual'
                CountVariable    = 'InactiveCount'
                All              = $true
                ErrorAction      = 'Stop'
            }

            $inactiveUsers = Get-MgBetaUser @userParams
            Write-PSFMessage -Level Verbose -Message "Found $InactiveCount users inactive for >$InactiveDays days."

            # Aggregate Zombie Counts
            $zombieCountBySku = [System.Collections.Generic.Dictionary[string, int]]::new()
            
            foreach ($u in $inactiveUsers)
            {
                if (-not $u) { continue }
                if (-not $u.PSObject.Properties.Match('assignedLicenses')) { continue }
                
                $assigned = $u.assignedLicenses
                if (-not $assigned) { continue }

                foreach ($lic in $assigned)
                {
                    if (-not $lic) { continue }
                    $sId = $lic.SkuId.ToString()
                    
                    if (-not $zombieCountBySku.ContainsKey($sId)) { $zombieCountBySku.Add($sId, 0) }
                    $zombieCountBySku[$sId] += 1
                }
            }

            # --- Step 3: Build Report ---
            foreach ($sku in $skus)
            {
                $stringSkuId = $sku.SkuId.ToString()
                $partNumber = $sku.SkuPartNumber

                # Resolve Friendly Name
                $friendlyName = $partNumber
                if ($script:GTLicenseRefCache -and $script:GTLicenseRefCache.SkuNames -and $script:GTLicenseRefCache.SkuNames.ContainsKey($stringSkuId))
                {
                    $friendlyName = $script:GTLicenseRefCache.SkuNames[$stringSkuId]
                }

                # Counts
                $totalPurchased = [int]$sku.PrepaidUnits.Enabled
                $totalAssigned = [int]$sku.ConsumedUnits
                $totalAvailable = [math]::Max(0, $totalPurchased - $totalAssigned)

                # Safe Zombie Lookup
                $totalZombie = 0
                if ($zombieCountBySku.ContainsKey($stringSkuId))
                { 
                    $totalZombie = $zombieCountBySku[$stringSkuId] 
                }
                
                # Financials: Optimized Dictionary Lookup (O(1))
                $unitPrice = [decimal]0
                if ($priceDict.Count -gt 0)
                {
                    # Try PartNumber first, then SkuId
                    if (-not $priceDict.TryGetValue($partNumber, [ref]$unitPrice))
                    {
                        $priceDict.TryGetValue($stringSkuId, [ref]$unitPrice) | Out-Null
                    }
                }
                
                # Strict Decimal Math
                $totalSpend = [math]::Round([decimal]($totalPurchased * $unitPrice), 2)
                $shelfwareCost = [decimal]($totalAvailable * $unitPrice)
                $zombieCost = [decimal]($totalZombie * $unitPrice)
                $potentialSavings = [math]::Round([decimal]($shelfwareCost + $zombieCost), 2)

                # Filter based on threshold
                if ($potentialSavings -lt $MinWastedThreshold) { continue }

                # Utilization %
                $utilization = 0
                if ($totalPurchased -gt 0)
                {
                    $utilization = [math]::Round(($totalAssigned / $totalPurchased) * 100, 1)
                }

                $report.Add([PSCustomObject][ordered]@{
                        FriendlyName     = $friendlyName
                        SkuPartNumber    = $partNumber
                        SkuId            = $stringSkuId
                        
                        # Inventory
                        Purchased        = $totalPurchased
                        Assigned         = $totalAssigned
                        UtilizationPct   = $utilization
                    
                        # Waste Metrics
                        Available        = $totalAvailable
                        InactiveAssigned = $totalZombie
                        TotalWastedUnits = $totalAvailable + $totalZombie
                    
                        # Financial Metrics
                        UnitPrice        = $unitPrice
                        MonthlySpend     = $totalSpend
                        WastedSpend      = $potentialSavings
                        
                        # Action
                        Recommendation   = if ($totalAvailable -gt 0) { "Reduce count by $totalAvailable" } elseif ($totalZombie -gt 0) { "Reclaim $totalZombie licenses" } else { "Optimized" }
                    })
            }
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'License Report'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to generate cost report: $($err.Reason)"
            throw $err.ErrorMessage
        }
    }

    end
    {
        $out = @()
        if ($report.Count -gt 0)
        {
            $out = $report.ToArray() | Sort-Object -Property WastedSpend -Descending
        }
        return $out
    }
}
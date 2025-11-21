function Get-M365LicenseOverview
{
    <#
    .SYNOPSIS
    Retrieves Microsoft 365 license information with detailed service plan analysis.

    .DESCRIPTION
    This function provides a comprehensive view of user licenses and service plans.
    It downloads the official Microsoft Licensing CSV to map GUIDs to Friendly Names.

    PERFORMANCE:
    - Caches the Microsoft CSV in a script-scope variable to avoid re-downloading every run.
    - Uses Server-Side filtering for User and Date queries.

    .PARAMETER FilterLicenseSKU
    Filters results by specific license SKU (e.g., "E5"). Accepts partial matches.

    .PARAMETER FilterServicePlan
    Filters results by service plan name (e.g., "EXCHANGE"). Accepts partial matches.

    .PARAMETER FilterUser
    Filters results by user principal name (server-side 'startsWith').

    .PARAMETER DaysInactive
    Filters for users who have NOT logged in for X days. Uses server-side filtering for optimal performance.

    .PARAMETER NewSession
    Forces a new Graph connection.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$FilterLicenseSKU,

        [Parameter()]
        [string]$FilterServicePlan,

        [Parameter()]
        [Alias('User','UPN','UserPrincipalName','UserName','UPNName')]
        [string]$FilterUser,

        [Parameter()]
        [ValidateRange(1, 3650)]
        [int]$DaysInactive,

        [Switch]$NewSession
    )

    begin
    {
        # 1. Module Check
        $requiredModules = @('Microsoft.Graph.Beta.Users', 'Microsoft.Graph.Beta.Identity.DirectoryManagement')
        Install-GTRequiredModule -ModuleNames $requiredModules -Verbose:$VerbosePreference

        # 2. Scopes Check
        $requiredScopes = @('User.Read.All', 'Organization.Read.All', 'AuditLog.Read.All')
        
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet))
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }

        # 3. Connection
        if (-not (Initialize-GTGraphConnection -Scopes $requiredScopes -NewSession:$NewSession))
        {
            Write-Error "Failed to initialize session."
            return
        }

        # 4. Load & Cache Reference Data
        if (-not $script:GTLicenseRefCache)
        {
            try
            {
                Write-PSFMessage -Level Verbose -Message 'Downloading license reference data from Microsoft...'
                
                # Try direct CSV URL first (more reliable), fallback to scraping
                # Note: Microsoft rotates these URLs, so the scraping fallback is essential.
                $csvUrl = 'https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv'
                try {
                    $skuTable = Invoke-RestMethod -Uri $csvUrl -ErrorAction Stop | ConvertFrom-Csv
                }
                catch {
                    Write-PSFMessage -Level Verbose -Message "Direct CSV download failed, attempting to scrape documentation page..."
                    $pageUrl = 'https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference'
                    $pageContent = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing -ErrorAction Stop
                    $csvLink = $pageContent.Links | Where-Object href -match 'licensing\.csv' | Select-Object -First 1 -ExpandProperty href

                    if (-not $csvLink) { throw "Could not find CSV link on Microsoft documentation page." }
                    $skuTable = Invoke-RestMethod -Uri $csvLink -ErrorAction Stop | ConvertFrom-Csv
                }
                
                # Build optimized lookup tables
                $script:GTLicenseRefCache = @{
                    SkuNames = @{}
                    PlanNames = @{}
                }

                foreach ($row in $skuTable) {
                    if ($row.GUID) {
                        if (-not $script:GTLicenseRefCache.SkuNames.ContainsKey($row.GUID)) {
                            $script:GTLicenseRefCache.SkuNames[$row.GUID] = $row.Product_Display_Name
                        }
                        if ($row.Service_Plan_Id -and -not $script:GTLicenseRefCache.PlanNames.ContainsKey($row.Service_Plan_Id)) {
                            $script:GTLicenseRefCache.PlanNames[$row.Service_Plan_Id] = $row.Service_Plan_Friendly_Name
                        }
                    }
                }
                Write-PSFMessage -Level Verbose -Message "Cached $($script:GTLicenseRefCache.SkuNames.Count) SKUs and $($script:GTLicenseRefCache.PlanNames.Count) Service Plans."
            }
            catch
            {
                Write-Warning "Failed to download license reference CSV. Friendly names will be missing. Error: $_"
                $script:GTLicenseRefCache = @{ SkuNames = @{}; PlanNames = @{} }
            }
        }
    }

    process
    {
        try
        {
            # 5. Build Dynamic Filter
            $filterParts = [System.Collections.Generic.List[string]]::new()
            $utcNow = (Get-Date).ToUniversalTime()

            if ($FilterUser) {
                $filterParts.Add("startsWith(userPrincipalName, '$FilterUser')")
            }

            if ($DaysInactive) {
                $cutoff = $utcNow.AddDays(-$DaysInactive).ToString("yyyy-MM-ddTHH:mm:ssZ")
                $filterParts.Add("signInActivity/lastSignInDateTime le $cutoff")
            }

            $params = @{
                All              = $true
                Property         = @('id','userPrincipalName','displayName','signInActivity','assignedLicenses')
                ConsistencyLevel = 'eventual'
                ErrorAction      = 'Stop'
            }

            if ($filterParts.Count -gt 0) {
                $filterStr = $filterParts -join ' and '
                Write-PSFMessage -Level Verbose -Message "Using OData Filter: $filterStr"
                $params['Filter'] = $filterStr
            }

            # 6. Process Users
            Get-MgBetaUser @params | ForEach-Object {
                $user = $_
                
                if (-not $user.AssignedLicenses) { return }

                foreach ($license in $user.AssignedLicenses)
                {
                    # Lookup SKU Name
                    $skuName = if ($script:GTLicenseRefCache.SkuNames.ContainsKey($license.SkuId)) { 
                        $script:GTLicenseRefCache.SkuNames[$license.SkuId] 
                    } else { 
                        $license.SkuId
                    }

                    # Filter by SKU (Client-side)
                    if ($FilterLicenseSKU -and $skuName -notmatch $FilterLicenseSKU) { continue }

                    # Iterate actual assigned plans
                    foreach ($assignedPlan in $license.ServicePlans)
                    {
                        # Lookup Plan Name
                        $planName = if ($script:GTLicenseRefCache.PlanNames.ContainsKey($assignedPlan.ServicePlanId)) {
                            $script:GTLicenseRefCache.PlanNames[$assignedPlan.ServicePlanId]
                        } else {
                            $assignedPlan.ServicePlanId
                        }

                        # Filter by Service Plan (Client-side)
                        if ($FilterServicePlan -and $planName -notmatch $FilterServicePlan) { continue }

                        # Calculate Days Inactive
                        $daysInactiveStr = "Never"
                        if ($user.SignInActivity.LastSignInDateTime) {
                            # Use New-TimeSpan for robust calculation
                            $lastSignIn = [DateTime]::Parse($user.SignInActivity.LastSignInDateTime)
                            $days = (New-TimeSpan -Start $lastSignIn -End $utcNow).Days
                            $daysInactiveStr = $days
                        }

                        # Create Output
                        [PSCustomObject]@{
                            UserPrincipalName        = $user.UserPrincipalName
                            DisplayName              = $user.DisplayName
                            LicenseSKU               = $skuName
                            ServicePlan              = $planName
                            ProvisioningStatus       = $assignedPlan.ProvisioningStatus
                            LastInteractiveSignIn    = $user.SignInActivity.LastSignInDateTime
                            DaysInactive             = $daysInactiveStr
                        }
                    }
                }
            }
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'User Licenses'
            Write-PSFMessage -Level $err.LogLevel -Message "License processing failed: $($err.Reason)"
            throw $err.ErrorMessage
        }
    }
}
function Get-M365LicenseOverview
{
    <#
    .SYNOPSIS
    Retrieves Microsoft 365 license information with detailed service plan analysis.

    .DESCRIPTION
    It downloads the official Microsoft Licensing CSV to map GUIDs to Friendly Names.

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
        $requiredModules = @('Microsoft.Graph.Authentication')
        $requiredScopes = @('User.Read.All', 'Organization.Read.All', 'AuditLog.Read.All')

        if (-not (Initialize-GTBeginBlock -ModuleNames $requiredModules -RequiredScopes $requiredScopes -ValidateScopes -InitializeConnection -NewSession:$NewSession -ScopeValidationErrorMessage "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting." -ConnectionErrorMessage 'Failed to initialize session.'))
        {
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
                    $csvPayload = Invoke-RestMethod -Uri $csvUrl -ErrorAction Stop
                    $skuTable = if ($csvPayload -is [string]) { $csvPayload | ConvertFrom-Csv } else { @($csvPayload) }
                }
                catch {
                    Write-PSFMessage -Level Verbose -Message "Direct CSV download failed, attempting to scrape documentation page..."
                    $pageUrl = 'https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference'
                    $pageContent = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing -ErrorAction Stop
                    $csvLink = $pageContent.Links | Where-Object href -match '\.csv' | Select-Object -First 1 -ExpandProperty href

                    if (-not $csvLink) { throw "Could not find CSV link on Microsoft documentation page." }
                    $csvPayload = Invoke-RestMethod -Uri $csvLink -ErrorAction Stop
                    $skuTable = if ($csvPayload -is [string]) { $csvPayload | ConvertFrom-Csv } else { @($csvPayload) }
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
            if ($FilterUser -and $FilterUser.Contains('@') -and $FilterUser -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
                throw "FilterUser must be either a prefix (for startsWith) or a valid UPN."
            }

            # 5. Build Dynamic Filter
            $filterParts = [System.Collections.Generic.List[string]]::new()
            $utcNow = (Get-Date).ToUniversalTime()

            if ($FilterUser) {
                $escapedFilterUser = $FilterUser.Replace("'", "''")
                $filterParts.Add("startsWith(userPrincipalName, '$escapedFilterUser')")
            }

            if ($DaysInactive) {
                $cutoff = $utcNow.AddDays(-$DaysInactive).ToString("yyyy-MM-ddTHH:mm:ssZ")
                $filterParts.Add("signInActivity/lastSignInDateTime le $cutoff")
            }

            $selectFields = 'id,userPrincipalName,displayName,signInActivity,assignedLicenses'
            $encodedSelect = [System.Uri]::EscapeDataString($selectFields)
            $nextUri = "/v1.0/users?`$select=$encodedSelect&`$top=999"

            $filterStr = New-GTODataFilter -Clauses $filterParts
            if (-not [string]::IsNullOrWhiteSpace($filterStr)) {
                Write-PSFMessage -Level Verbose -Message "Using OData Filter: $filterStr"
                $encodedFilter = [System.Uri]::EscapeDataString($filterStr)
                $nextUri += "&`$filter=$encodedFilter"
            }

            # 6. Process Users
            $users = Invoke-GTGraphPagedRequest -Uri $nextUri -Headers @{ ConsistencyLevel = 'eventual' }
            foreach ($user in $users) {
                    if ($FilterUser -and (-not [string]$user.UserPrincipalName -or -not ([string]$user.UserPrincipalName).StartsWith($FilterUser, [System.StringComparison]::OrdinalIgnoreCase))) {
                        continue
                    }

                    if (-not $user.AssignedLicenses) { continue }

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

                                if ($DaysInactive -and $days -lt $DaysInactive) {
                                    continue
                                }
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
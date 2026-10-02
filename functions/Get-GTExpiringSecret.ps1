function Get-GTExpiringSecret
{
    <#
    .SYNOPSIS
    Scans Applications and Service Principals for expired and expiring credentials with impact analysis.

    .DESCRIPTION
    Scans Applications and Service Principals to evaluate credentials (client secrets and certificates).
    Categorizes credential status into Expired, Critical (default <= 7 days), Warning (default <= 30 days), or Healthy.
    Optionally evaluates operational impact:
    - Single Point of Failure (SPOF): detects if an expiring credential is the sole active credential.
    - Active Outage Risk: correlates with sign-in activity (lastSignInDateTime).
    - Ownership Accountability: identifies owners and flags orphaned apps.

    .PARAMETER DaysUntilExpiry
    Legacy parameter for backward compatibility. Sets the warning threshold in days (equivalent to -WarningDays).
    
    .PARAMETER CriticalDays
    Threshold in days for 'Critical' expiration warning. Default is 7.

    .PARAMETER WarningDays
    Threshold in days for 'Warning' expiration warning. Default is 30.

    .PARAMETER Status
    Filters results by credential status: 'All', 'Expired', 'Critical', 'Warning', 'Healthy'.
    Defaults to @('Expired', 'Critical', 'Warning').

    .PARAMETER IncludeExpired
    Includes already expired credentials (endDateTime < Now).

    .PARAMETER IncludeImpactAnalysis
    Enriches output with outage risk, sole credential detection, sign-in activity, and owner details.

    .PARAMETER Summary
    Emits a high-level summary KPI object instead of individual credential records.

    .PARAMETER Scope
    Specifies whether to check 'Applications', 'ServicePrincipals', or 'All'. Default is 'All'.

    .PARAMETER AppId
    Filter by specific Application (Client) ID(s). Supports pipeline input.

    .PARAMETER DisplayName
    Filter by specific Display Name(s). Supports pipeline input.

    .PARAMETER NewSession
    If specified, creates a new Microsoft Graph session by disconnecting any existing session first.

    .EXAMPLE
    Get-GTExpiringSecret -CriticalDays 7 -WarningDays 30 -IncludeImpactAnalysis
    Finds credentials expiring soon with outage risk assessment and owner accountability.

    .EXAMPLE
    Get-GTExpiringSecret -DaysUntilExpiry 30
    Legacy usage: finds all credentials expiring in the next 30 days.

    .EXAMPLE
    Get-GTExpiringSecret -Status Expired -IncludeImpactAnalysis
    Audits all already-expired credentials across applications to identify unrotated technical debt.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias('Get-GTExpiringSecrets')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'Legacy', Position = 0)]
        [ValidateRange(1, 3650)]
        [int]$DaysUntilExpiry,

        [Parameter(ParameterSetName = 'Default')]
        [ValidateRange(1, 365)]
        [int]$CriticalDays = 7,

        [Parameter(ParameterSetName = 'Default')]
        [ValidateRange(1, 3650)]
        [int]$WarningDays = 30,

        [Parameter(ParameterSetName = 'Default')]
        [ValidateSet('All', 'Expired', 'Critical', 'Warning', 'Healthy')]
        [string[]]$Status = @('Expired', 'Critical', 'Warning'),

        [Parameter(ParameterSetName = 'Default')]
        [switch]$IncludeExpired,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Legacy')]
        [switch]$IncludeImpactAnalysis,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Legacy')]
        [switch]$Summary,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Legacy')]
        [ValidateSet('All', 'Applications', 'ServicePrincipals')]
        [string]$Scope = 'All',

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Default')]
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Legacy')]
        [string[]]$AppId,

        [Parameter(ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Default')]
        [Parameter(ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Legacy')]
        [string[]]$DisplayName,

        [switch]$NewSession
    )

    begin
    {
        # Permissions required for directory scan
        $requiredScopes = @('Application.Read.All')
        if (-not (Initialize-GTGraphConnection -Scopes $requiredScopes -NewSession:$NewSession))
        {
            Write-Error "Failed to initialize session."
            return
        }

        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Quiet))
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }

        # Capability flag for sign-in telemetry
        $canReadSignInActivity = $false
        if ($IncludeImpactAnalysis)
        {
            $canReadSignInActivity = Test-GTGraphScopes -RequiredScopes @('AuditLog.Read.All') -Quiet
            if (-not $canReadSignInActivity)
            {
                Write-PSFMessage -Level Verbose -Message "AuditLog.Read.All permission not detected; sign-in activity analysis will be skipped."
            }
        }

        $appIdList = [System.Collections.Generic.List[string]]::new()
        $displayNameList = [System.Collections.Generic.List[string]]::new()
    }

    process
    {
        if ($DisplayName) { $displayNameList.AddRange($DisplayName) }

        if ($AppId)
        {
            foreach ($item in $AppId)
            {
                # Disambiguate piped bare strings: GUIDs are AppIds; non-GUID values are DisplayNames
                $parsedGuid = [guid]::Empty
                if ([guid]::TryParse($item, [ref]$parsedGuid))
                {
                    $appIdList.Add($item)
                }
                else
                {
                    $displayNameList.Add($item)
                }
            }
        }
    }

    end
    {
        $now = Get-UTCTime
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
        $appsScannedCount = 0

        # Parameter resolution for backward compatibility
        $isLegacyMode = $PSBoundParameters.ContainsKey('DaysUntilExpiry') -and (-not $PSBoundParameters.ContainsKey('Status')) -and (-not $IncludeExpired)
        $effectiveCriticalDays = $CriticalDays
        $effectiveWarningDays = if ($PSBoundParameters.ContainsKey('DaysUntilExpiry')) { $DaysUntilExpiry } else { $WarningDays }

        # Effective status filter list
        $effectiveStatusFilter = if ($Status -contains 'All')
        {
            @('Expired', 'Critical', 'Warning', 'Healthy')
        }
        else
        {
            $activeList = [System.Collections.Generic.List[string]]::new([string[]]$Status)
            if ($IncludeExpired -and (-not ($activeList -contains 'Expired')))
            {
                $activeList.Add('Expired')
            }
            $activeList.ToArray()
        }

        # Dynamic OData filter construction
        $filter = $null
        if ($appIdList.Count -gt 0)
        {
            $safeAppIds = $appIdList | ForEach-Object { ($_ -replace "'", "''") }
            $filter = "appId in ('" + ($safeAppIds -join "','") + "')"
        }
        elseif ($displayNameList.Count -gt 0)
        {
            $safeNames = $displayNameList | ForEach-Object { ($_ -replace "'", "''") }
            $filter = "displayName in ('" + ($safeNames -join "','") + "')"
        }

        # Shared credential evaluation scriptblock
        $ProcessItemCredentials = {
            param(
                [object]$Item,
                [string]$ResourceType
            )

            $allCreds = [System.Collections.Generic.List[object]]::new()
            if ($Item.passwordCredentials) { $allCreds.AddRange($Item.passwordCredentials) }
            if ($Item.keyCredentials) { $allCreds.AddRange($Item.keyCredentials) }

            # Identify non-expired credentials currently valid
            $validCreds = @($allCreds | Where-Object {
                $_.endDateTime -and ([datetime]$_.endDateTime -gt $now)
            })

            # Resolved application owners
            $ownersList = @()
            if ($Item.owners)
            {
                $ownersList = $Item.owners | ForEach-Object {
                    if ($_.userPrincipalName) { $_.userPrincipalName }
                    elseif ($_.displayName) { $_.displayName }
                    elseif ($_.id) { $_.id }
                } | Where-Object { $_ }
            }
            $isOrphaned = ($ownersList.Count -eq 0)

            # Last sign in activity timestamp
            $lastSignIn = $null
            if ($Item.signInActivity -and $Item.signInActivity.lastSignInDateTime)
            {
                $lastSignIn = [datetime]$Item.signInActivity.lastSignInDateTime
            }

            # Evaluate each credential entry
            $EvaluateCredential = {
                param(
                    [object]$Cred,
                    [string]$CredentialType
                )

                if (-not $Cred.endDateTime) { return }

                $expiryDate = [datetime]$Cred.endDateTime
                $diff = $expiryDate - $now
                $daysRemaining = [math]::Ceiling($diff.TotalDays)

                # Credential urgency status classification
                $status = if ($daysRemaining -lt 0)
                {
                    'Expired'
                }
                elseif ($daysRemaining -le $effectiveCriticalDays)
                {
                    'Critical'
                }
                elseif ($daysRemaining -le $effectiveWarningDays)
                {
                    'Warning'
                }
                else
                {
                    'Healthy'
                }

                # Evaluate filter inclusion
                $shouldInclude = if ($isLegacyMode)
                {
                    ($daysRemaining -ge 0 -and $daysRemaining -le $effectiveWarningDays)
                }
                else
                {
                    $status -in $effectiveStatusFilter
                }

                if (-not $shouldInclude) { return }

                # Single Point of Failure (SPOF) assessment
                $otherValidCreds = @($validCreds | Where-Object { $_.keyId -ne $Cred.keyId })
                $isSoleCredential = ($otherValidCreds.Count -eq 0)

                # Outage and blast radius risk scoring
                $outageRisk = if ($status -eq 'Healthy')
                {
                    'None'
                }
                elseif ($status -in 'Expired', 'Critical')
                {
                    if ($isSoleCredential)
                    {
                        if ($lastSignIn)
                        {
                            $daysSinceSignIn = ($now - $lastSignIn).TotalDays
                            if ($daysSinceSignIn -le 30)
                            {
                                'Immediate Outage'
                            }
                            elseif ($daysSinceSignIn -gt 90)
                            {
                                'Low'
                            }
                            else
                            {
                                'Medium'
                            }
                        }
                        elseif ($null -eq $lastSignIn)
                        {
                            'High'
                        }
                        else
                        {
                            'Medium'
                        }
                    }
                    else
                    {
                        'Medium'
                    }
                }
                elseif ($status -eq 'Warning')
                {
                    if ($isSoleCredential) { 'Medium' } else { 'Low' }
                }
                else
                {
                    'Low'
                }

                $record = [ordered]@{
                    Name           = $Item.displayName
                    AppId          = $Item.appId
                    Id             = $Item.id
                    ResourceType   = $ResourceType
                    CredentialType = $CredentialType
                    KeyId          = $Cred.keyId
                    Hint           = if ($CredentialType -eq 'Secret') { $Cred.hint } else { $null }
                    ExpiryDate     = $Cred.endDateTime
                    DaysRemaining  = [int]$daysRemaining
                    Status         = $status
                }

                if ($IncludeImpactAnalysis)
                {
                    $record['IsSoleCredential']       = [bool]$isSoleCredential
                    $record['TotalActiveCredentials'] = [int]$validCreds.Count
                    $record['OutageRisk']             = $outageRisk
                    $record['LastSignInDateTime']     = if ($lastSignIn) { Format-ODataDateTime -DateTime $lastSignIn } else { $null }
                    $record['Owners']                 = $ownersList -join '; '
                    $record['IsOrphaned']             = [bool]$isOrphaned
                }

                $results.Add([PSCustomObject]$record)
            }

            # Process client secrets
            if ($Item.passwordCredentials)
            {
                foreach ($secret in $Item.passwordCredentials)
                {
                    & $EvaluateCredential -Cred $secret -CredentialType 'Secret'
                }
            }

            # Process certificates
            if ($Item.keyCredentials)
            {
                foreach ($cert in $Item.keyCredentials)
                {
                    & $EvaluateCredential -Cred $cert -CredentialType 'Certificate'
                }
            }
        }

        try
        {
            # Query Applications
            if ($Scope -in 'All', 'Applications')
            {
                Write-PSFMessage -Level Verbose -Message "Scanning Applications for credentials..."
                $appSelect = 'id,appId,displayName,keyCredentials,passwordCredentials'
                $appExpand = if ($IncludeImpactAnalysis) { '&$expand=owners($select=id,userPrincipalName,displayName)' } else { '' }
                $appUri = "v1.0/applications?`$select=$appSelect$appExpand"
                if ($filter) { $appUri += "&`$filter=$([Uri]::EscapeDataString($filter))" }

                $apps = @()
                try
                {
                    $apps = Invoke-GTGraphPagedRequest -Uri $appUri
                }
                catch
                {
                    if ($appExpand -and $_.Exception.Message -match 'expand|400|BadRequest')
                    {
                        Write-PSFMessage -Level Verbose -Message "Expand owners unsupported on applications query; executing without expand."
                        $fallbackAppUri = "v1.0/applications?`$select=$appSelect"
                        if ($filter) { $fallbackAppUri += "&`$filter=$([Uri]::EscapeDataString($filter))" }
                        $apps = Invoke-GTGraphPagedRequest -Uri $fallbackAppUri
                    }
                    else
                    {
                        throw
                    }
                }

                foreach ($app in $apps)
                {
                    $appsScannedCount++
                    & $ProcessItemCredentials -Item $app -ResourceType 'Application'
                }
            }

            # Query Service Principals
            if ($Scope -in 'All', 'ServicePrincipals')
            {
                Write-PSFMessage -Level Verbose -Message "Scanning Service Principals for credentials..."
                $spSelect = 'id,appId,displayName,keyCredentials,passwordCredentials'
                if ($IncludeImpactAnalysis -and $canReadSignInActivity)
                {
                    $spSelect += ',signInActivity'
                }

                $spExpand = if ($IncludeImpactAnalysis) { '&$expand=owners($select=id,userPrincipalName,displayName)' } else { '' }
                # signInActivity requires beta endpoint; v1.0 used otherwise
                $apiVersion = if ($IncludeImpactAnalysis -and $canReadSignInActivity) { 'beta' } else { 'v1.0' }
                $spUri = "$apiVersion/servicePrincipals?`$select=$spSelect$spExpand"
                if ($filter) { $spUri += "&`$filter=$([Uri]::EscapeDataString($filter))" }

                $sps = @()
                try
                {
                    $sps = Invoke-GTGraphPagedRequest -Uri $spUri
                }
                catch
                {
                    if ($spExpand -and $_.Exception.Message -match 'expand|400|BadRequest')
                    {
                        Write-PSFMessage -Level Verbose -Message "Expand owners unsupported on servicePrincipals query; executing without expand."
                        $fallbackSpUri = "$apiVersion/servicePrincipals?`$select=$spSelect"
                        if ($filter) { $fallbackSpUri += "&`$filter=$([Uri]::EscapeDataString($filter))" }
                        $sps = Invoke-GTGraphPagedRequest -Uri $fallbackSpUri
                    }
                    else
                    {
                        throw
                    }
                }

                foreach ($sp in $sps)
                {
                    $appsScannedCount++
                    & $ProcessItemCredentials -Item $sp -ResourceType 'ServicePrincipal'
                }
            }

            # KPI Summary emission mode
            if ($Summary)
            {
                $orphanedAppIds = @($results | Where-Object { $_.IsOrphaned -eq $true } | ForEach-Object { $_.Id } | Select-Object -Unique)
                $soleCredAppIds = @($results | Where-Object { $_.IsSoleCredential -eq $true } | ForEach-Object { $_.Id } | Select-Object -Unique)

                $summaryObj = [PSCustomObject]@{
                    TotalAppsScanned        = [int]$appsScannedCount
                    TotalCredentialsFound   = [int]$results.Count
                    ExpiredCount            = [int]@($results | Where-Object { $_.Status -eq 'Expired' }).Count
                    CriticalCount           = [int]@($results | Where-Object { $_.Status -eq 'Critical' }).Count
                    WarningCount            = [int]@($results | Where-Object { $_.Status -eq 'Warning' }).Count
                    HealthyCount            = [int]@($results | Where-Object { $_.Status -eq 'Healthy' }).Count
                    SoleCredentialRiskCount = [int]$soleCredAppIds.Count
                    OrphanedAppsCount       = [int]$orphanedAppIds.Count
                    ScanTimestamp           = Format-ODataDateTime -DateTime $now
                }
                return $summaryObj
            }

            return [object[]]$results.ToArray()
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'Secret Scan'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve expiring secrets: $($err.Reason)"
            throw
        }
    }
}

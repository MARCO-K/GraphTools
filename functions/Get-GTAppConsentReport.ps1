function Get-GTAppConsentReport
{
    <#
    .SYNOPSIS
        Audits OAuth 2.0 delegated permission grants, third-party application attack surface, and illicit consent risks.

    .DESCRIPTION
        Scans all Microsoft Entra ID delegated permission grants (oauth2PermissionGrants) and correlates
        them with Service Principal security metadata (publisher verification, multi-tenant ownership, reply URLs)
        and consenting user identities.

        Identifies high-risk attack vectors including:
        - Illicit Consent Grants / OAuth Phishing: Unverified third-party apps granted sensitive scopes by end users.
        - High-Privilege Scopes: Grants exposing broad data access (e.g., Mail.ReadWrite, Files.ReadWrite.All).
        - Shadow IT: Multi-tenant applications consented without centralized administrative governance.
        - Orphaned / Stale Grants: Grants associated with deleted or inaccessible identities.

        SECURITY CONTROLS:
        - Bounded Input Constraints: Enforces strict length and count limits to prevent memory and DoS abuse.
        - Information Leakage Prevention: Sanitizes user-facing error messages to avoid exposing tokens or endpoints.
        - External API Timeouts: Enforces request deadlines across REST invokers to prevent thread hangs.

    .PARAMETER AppId
        Filter by one or more Application (Client) IDs. Supports pipeline input by value and property name.
        Bounded to maximum 128 characters per identifier.

    .PARAMETER DisplayName
        Filter by one or more Application Display Names. Supports pipeline input by property name.
        Bounded to maximum 256 characters per name.

    .PARAMETER UserId
        Filter grants consented by a specific User Object ID or UserPrincipalName.
        Bounded to maximum 128 characters.

    .PARAMETER ConsentType
        Filter by consent scope:
        - 'All': Returns all grants (default).
        - 'AllPrincipals': Returns tenant-wide administrator consent grants.
        - 'Principal': Returns user-delegated consent grants.

    .PARAMETER RiskLevel
        Filter output to specific risk levels: 'Critical', 'High', 'Medium', 'Low'.

    .PARAMETER UnverifiedOnly
        Switch to filter exclusively for applications whose publisher is not verified by Microsoft.

    .PARAMETER ThirdPartyOnly
        Switch to filter exclusively for external multi-tenant applications owned outside the local tenant.

    .PARAMETER Summary
        Switch to emit an aggregated tenant-wide KPI summary card instead of individual grant records.

    .PARAMETER PermissionsFile
        Optional custom file path to a graph-permissions.json metadata fixture.

    .PARAMETER TimeoutSeconds
        Operation timeout in seconds for Microsoft Graph HTTP requests. Defaults to 30 seconds.
        Bounded between 5 and 300 seconds.

    .PARAMETER NewSession
        Forces initialization of a fresh Microsoft Graph session.

    .OUTPUTS
        [PSCustomObject]
        Stream of enriched permission grant records, or a single KPI summary card when -Summary is specified.

    .EXAMPLE
        # Audit all grants with elevated risk
        Get-GTAppConsentReport -RiskLevel Critical, High

    .EXAMPLE
        # Find unverified third-party apps consented by standard users
        Get-GTAppConsentReport -ConsentType Principal -UnverifiedOnly -ThirdPartyOnly

    .EXAMPLE
        # Emit tenant-level OAuth consent posture summary card
        Get-GTAppConsentReport -Summary
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [OutputType([PSCustomObject])]
    param (
        # Security Guardrail: Constrain identifier length and collection size to prevent allocation exhaustion
        [Parameter(ParameterSetName = 'Default', ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Parameter(ParameterSetName = 'Summary', ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [ValidateCount(1, 500)]
        [string[]]$AppId,

        # Security Guardrail: Constrain display name length to prevent OData buffer expansion
        [Parameter(ParameterSetName = 'Default', ValueFromPipelineByPropertyName = $true)]
        [Parameter(ParameterSetName = 'Summary', ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 256)]
        [ValidateCount(1, 500)]
        [string[]]$DisplayName,

        # Security Guardrail: Constrain user identifier length
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Summary')]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [string]$UserId,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Summary')]
        [ValidateSet('All', 'AllPrincipals', 'Principal')]
        [string]$ConsentType = 'All',

        [Parameter(ParameterSetName = 'Default')]
        [ValidateSet('Critical', 'High', 'Medium', 'Low')]
        [string[]]$RiskLevel,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Summary')]
        [switch]$UnverifiedOnly,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Summary')]
        [switch]$ThirdPartyOnly,

        [Parameter(ParameterSetName = 'Summary', Mandatory = $true)]
        [switch]$Summary,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Summary')]
        [ValidateLength(1, 512)]
        [string]$PermissionsFile,

        # Security Guardrail: Enforce request timeout limit to mitigate socket hanging and Slowloris-style thread starvation
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Summary')]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Summary')]
        [switch]$NewSession
    )

    begin
    {
        # Helper: Emit sanitized error records without leaking sensitive URLs, tokens, or directory internals
        $EmitSanitizedError = {
            param(
                [string]$UserMessage,
                [string]$ErrorId,
                [System.Management.Automation.ErrorCategory]$Category,
                [System.Exception]$OriginalException
            )
            # Route detailed raw diagnostic information to secure PSF debug stream
            if ($OriginalException)
            {
                Write-PSFMessage -Level Debug -Message "Sanitized exception [$ErrorId]: $($OriginalException.ToString())"
            }
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($UserMessage),
                $ErrorId,
                $Category,
                $null
            )
            $PSCmdlet.WriteError($errorRecord)
        }

        # 1. Verify session connectivity and required delegated/app scopes
        $requiredScopes = @('DelegatedPermissionGrant.Read.All', 'Application.Read.All')
        if (-not (Initialize-GTGraphConnection -Scopes $requiredScopes -NewSession:$NewSession))
        {
            & $EmitSanitizedError -UserMessage "Failed to initialize Microsoft Graph session. Please authenticate via Connect-GTGraph." -ErrorId 'SessionInitializationFailed' -Category ConnectionError
            return
        }

        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Quiet))
        {
            & $EmitSanitizedError -UserMessage "Insufficient privileges. Required scopes: $($requiredScopes -join ', ')." -ErrorId 'InsufficientGraphScopes' -Category PermissionDenied
            return
        }

        # 2. Load DevX permissions metadata catalog for granular privilege level scoring
        $permissionCatalog = Get-GTPermissionDefinition -PermissionsFile $PermissionsFile

        # Security Rationale: Curated critical high-impact delegated scopes frequently targeted in OAuth phishing
        # Scopes providing full mailbox access, directory-wide writes, or silent file sync represent maximum blast radius.
        $CuratedHighRiskScopes = @{
            'RoleManagement.ReadWrite.Directory'           = @{ Score = 10; Level = 'Critical'; Reason = 'Privilege Escalation: Can grant directory administrator roles' }
            'AppRoleAssignment.ReadWrite.All'              = @{ Score = 10; Level = 'Critical'; Reason = 'Privilege Escalation: Can grant arbitrary application roles' }
            'OnPremDirectorySynchronization.ReadWrite.All' = @{ Score = 10; Level = 'Critical'; Reason = 'Hybrid Identity Compromise: Can tamper with directory sync' }
            'Domain.ReadWrite.All'                         = @{ Score = 10; Level = 'Critical'; Reason = 'Domain Takeover: Can modify verified organization domains' }
            'UserAuthenticationMethod.ReadWrite.All'       = @{ Score = 10; Level = 'Critical'; Reason = 'Credential Manipulation: Can reset user MFA and auth methods' }
            'DelegatedPermissionGrant.ReadWrite.All'       = @{ Score = 10; Level = 'Critical'; Reason = 'Privilege Escalation: Can grant arbitrary delegated permissions' }
            'Directory.ReadWrite.All'                      = @{ Score = 9;  Level = 'Critical'; Reason = 'Tenant Destruction: Can create, update, and delete directory objects' }
            'Directory.AccessAsUser.All'                   = @{ Score = 9;  Level = 'Critical'; Reason = 'Full Impersonation: Can access directory as signed-in user' }
            'Mail.ReadWrite'                               = @{ Score = 8;  Level = 'High';     Reason = 'Email Exfiltration / Tampering: Full read and write access to mailboxes' }
            'Mail.Read'                                    = @{ Score = 7;  Level = 'High';     Reason = 'Email Exfiltration: Read access to user mailboxes' }
            'Mail.Send'                                    = @{ Score = 7;  Level = 'High';     Reason = 'Impersonation / Phishing: Can send emails as consenting user' }
            'Files.ReadWrite.All'                          = @{ Score = 8;  Level = 'High';     Reason = 'Data Exfiltration / Ransomware: Read and write access to all SharePoint/OneDrive files' }
            'Files.Read.All'                               = @{ Score = 7;  Level = 'High';     Reason = 'Data Exfiltration: Read access to all SharePoint/OneDrive files' }
            'BitlockerKey.Read.All'                        = @{ Score = 8;  Level = 'High';     Reason = 'Cryptographic Exfiltration: Can read BitLocker recovery keys' }
            'User.ReadWrite.All'                           = @{ Score = 6;  Level = 'Medium';   Reason = 'User Modification: Can alter directory user profiles' }
            'Group.ReadWrite.All'                          = @{ Score = 6;  Level = 'Medium';   Reason = 'Group Manipulation: Can alter security groups and memberships' }
        }

        # 3. Determine local tenant ID to identify multi-tenant third-party applications
        $currentTenantId = $null
        try
        {
            $conn = Get-GTConnection
            if ($conn -and $conn.TenantId)
            {
                $currentTenantId = $conn.TenantId
            }
            else
            {
                $org = Invoke-GTGraphRequest -Uri "v1.0/organization?`$select=id" -TimeoutSeconds $TimeoutSeconds
                if ($org -and $org.value -and $org.value[0].id)
                {
                    $currentTenantId = $org.value[0].id
                }
            }
        }
        catch
        {
            Write-PSFMessage -Level Verbose -Message "Tenant ID auto-detection deferred; third-party classification will rely on external organization pointers."
        }

        # Pipeline accumulation lists
        $appIdList = [System.Collections.Generic.List[string]]::new()
        $displayNameList = [System.Collections.Generic.List[string]]::new()
    }

    process
    {
        # Disambiguate pipeline input: GUID strings route to AppId, arbitrary strings route to DisplayName
        if ($AppId)
        {
            foreach ($entry in $AppId)
            {
                if ([string]::IsNullOrWhiteSpace($entry)) { continue }
                $parsedGuid = [guid]::Empty
                if ([guid]::TryParse($entry, [ref]$parsedGuid))
                {
                    $appIdList.Add($entry.Trim())
                }
                else
                {
                    $displayNameList.Add($entry.Trim())
                }
            }
        }

        if ($DisplayName)
        {
            foreach ($name in $DisplayName)
            {
                if (-not [string]::IsNullOrWhiteSpace($name))
                {
                    $displayNameList.Add($name.Trim())
                }
            }
        }
    }

    end
    {
        # 4. Fetch all OAuth 2.0 permission grants from Microsoft Graph
        Write-PSFMessage -Level Verbose -Message "Querying oauth2PermissionGrants with timeout limit of $TimeoutSeconds seconds..."
        $grants = @()
        try
        {
            $grantsUri = "v1.0/oauth2PermissionGrants"
            $grants = Invoke-GTGraphPagedRequest -Uri $grantsUri -TimeoutSeconds $TimeoutSeconds
        }
        catch
        {
            $statusCode = Get-GTGraphHttpStatus -Exception $_.Exception
            & $EmitSanitizedError -UserMessage "Failed to retrieve OAuth permission grants from Microsoft Graph (HTTP $statusCode). Verify connectivity and permissions." -ErrorId 'OAuthGrantsQueryFailed' -Category ResourceUnavailable -OriginalException $_.Exception
            return
        }

        if (-not $grants -or $grants.Count -eq 0)
        {
            Write-PSFMessage -Level Verbose -Message "No oauth2PermissionGrants found in directory."
            if ($Summary)
            {
                return [PSCustomObject]@{
                    TotalGrantsScanned        = 0
                    TotalAppsScanned          = 0
                    CriticalCount             = 0
                    HighCount                 = 0
                    MediumCount               = 0
                    LowCount                  = 0
                    UnverifiedAppsCount       = 0
                    ThirdPartyAppsCount       = 0
                    UserConsentedCount        = 0
                    AdminConsentedCount       = 0
                    ScanTimestamp             = Format-ODataDateTime -DateTime (Get-UTCTime)
                }
            }
            return
        }

        # 5. Retrieve and index Service Principals for fast O(1) in-memory metadata correlation
        Write-PSFMessage -Level Verbose -Message "Retrieving Service Principals for OAuth grant correlation..."
        $spMap = @{}
        try
        {
            $spSelect = "id,appId,displayName,publisherName,verifiedPublisher,appOwnerOrganizationId,replyUrls"
            $spUri = "v1.0/servicePrincipals?`$select=$spSelect"
            $spList = Invoke-GTGraphPagedRequest -Uri $spUri -TimeoutSeconds $TimeoutSeconds

            foreach ($sp in $spList)
            {
                if ($sp.id) { $spMap[$sp.id] = $sp }
            }
        }
        catch
        {
            $statusCode = Get-GTGraphHttpStatus -Exception $_.Exception
            & $EmitSanitizedError -UserMessage "Failed to retrieve Service Principals metadata (HTTP $statusCode). Grants correlation may be degraded." -ErrorId 'ServicePrincipalsQueryFailed' -Category ResourceUnavailable -OriginalException $_.Exception
            # Continue processing if grants are present; correlation will yield generic placeholders
        }

        # 6. Cache consenting user identities to resolve UPN without redundant Graph queries
        $userCache = @{}
        $ResolveUser = {
            param([string]$PrincipalId)
            if ([string]::IsNullOrWhiteSpace($PrincipalId)) { return $null }
            if ($userCache.ContainsKey($PrincipalId)) { return $userCache[$PrincipalId] }

            try
            {
                # Security Guardrail: Escape user ID in OData path to prevent directory traversal
                $sanitizedId = [Uri]::EscapeDataString($PrincipalId)
                $userObj = Invoke-GTGraphRequest -Uri "v1.0/users/$($sanitizedId)?`$select=id,userPrincipalName,displayName" -TimeoutSeconds $TimeoutSeconds
                if ($userObj)
                {
                    $userCache[$PrincipalId] = $userObj
                    return $userObj
                }
            }
            catch
            {
                Write-PSFMessage -Level Debug -Message "Could not resolve user principal ID '$PrincipalId': $($_.Exception.Message)"
            }

            $userCache[$PrincipalId] = $null
            return $null
        }

        # 7. Evaluate each grant through the risk classification engine
        $records = [System.Collections.Generic.List[object]]::new()
        $appsEncountered = [System.Collections.Generic.HashSet[string]]::new()

        foreach ($grant in $grants)
        {
            # Filter by ConsentType if requested
            if ($ConsentType -ne 'All' -and $grant.consentType -ne $ConsentType)
            {
                continue
            }

            # Filter by UserId if specified
            if ($UserId)
            {
                if ($grant.consentType -ne 'Principal' -or $grant.principalId -ne $UserId)
                {
                    # Also test against resolved UPN if UserId was given as an email/UPN
                    $userLookup = & $ResolveUser -PrincipalId $grant.principalId
                    if ($null -eq $userLookup -or $userLookup.userPrincipalName -ne $UserId)
                    {
                        continue
                    }
                }
            }

            # Resolve Client Service Principal (the app receiving the permissions)
            $clientSp = if ($grant.clientId -and $spMap.ContainsKey($grant.clientId)) { $spMap[$grant.clientId] } else { $null }

            $appIdVal       = if ($clientSp) { $clientSp.appId } else { $grant.clientId }
            $displayNameVal = if ($clientSp) { $clientSp.displayName } else { "App-$($grant.clientId)" }
            $publisherName  = if ($clientSp -and $clientSp.publisherName) { $clientSp.publisherName } else { 'Unknown' }

            # Security Check: Verify whether the application publisher has passed Microsoft verification
            $isVerified = [bool]($clientSp -and $clientSp.verifiedPublisher -and -not [string]::IsNullOrWhiteSpace($clientSp.verifiedPublisher.verifiedPublisherId))
            $verifiedPubId = if ($isVerified) { $clientSp.verifiedPublisher.verifiedPublisherId } else { $null }

            # Security Check: Multi-tenant ownership (third-party app)
            $ownerTenantId = if ($clientSp) { $clientSp.appOwnerOrganizationId } else { $null }
            $isThirdParty = [bool]($ownerTenantId -and $currentTenantId -and ($ownerTenantId -ne $currentTenantId))

            # Apply Pipeline / Parameter Filters
            if ($appIdList.Count -gt 0 -and $appIdVal -notin $appIdList)
            {
                continue
            }
            if ($displayNameList.Count -gt 0 -and $displayNameVal -notin $displayNameList)
            {
                continue
            }
            if ($UnverifiedOnly -and $isVerified)
            {
                continue
            }
            if ($ThirdPartyOnly -and -not $isThirdParty)
            {
                continue
            }

            # Resolve Resource API Service Principal (e.g. Microsoft Graph)
            $resourceSp = if ($grant.resourceId -and $spMap.ContainsKey($grant.resourceId)) { $spMap[$grant.resourceId] } else { $null }
            $resourceName = if ($resourceSp) { $resourceSp.displayName } else { "Resource-$($grant.resourceId)" }

            # Parse granted scopes
            $scopeTokens = if ($grant.scope) { @($grant.scope -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { @() }

            # Correlate Consenting User
            $consentedUser = if ($grant.consentType -eq 'Principal') { & $ResolveUser -PrincipalId $grant.principalId } else { $null }
            $consentedUpn = if ($consentedUser) { $consentedUser.userPrincipalName } else { $null }

            # Evaluate Risk Score, Risk Level, and High-Risk Scopes
            $detectedHighRiskScopes = [System.Collections.Generic.List[string]]::new()
            $riskReasons = [System.Collections.Generic.List[string]]::new()
            $maxScore = 1

            if (-not $isVerified)
            {
                $riskReasons.Add("Unverified Publisher: Application publisher has not been verified by Microsoft")
            }
            if ($isThirdParty)
            {
                $riskReasons.Add("Third-Party Application: Owned by external tenant ($ownerTenantId)")
            }

            foreach ($s in $scopeTokens)
            {
                if ($CuratedHighRiskScopes.ContainsKey($s))
                {
                    $highRiskMeta = $CuratedHighRiskScopes[$s]
                    $detectedHighRiskScopes.Add($s)
                    $riskReasons.Add("High-Risk Scope '$s': $($highRiskMeta.Reason)")
                    if ($highRiskMeta.Score -gt $maxScore)
                    {
                        $maxScore = $highRiskMeta.Score
                    }
                }
                elseif ($permissionCatalog -and $permissionCatalog.ContainsKey($s))
                {
                    $devx = $permissionCatalog[$s]
                    $privLevel = [int]$devx.delegatedPrivilegeLevel
                    if ($privLevel -ge 4)
                    {
                        $detectedHighRiskScopes.Add($s)
                        $riskReasons.Add("Elevated Delegated Scope '$s' (DevX Level $privLevel)")
                        if (7 -gt $maxScore) { $maxScore = 7 }
                    }
                }
            }

            # Security Rationale: Illicit Consent Phishing Detection
            # If an unverified third-party app was consented by an individual end user (consentType = Principal)
            # and requests high-risk data access scopes (e.g. Mail/Files), elevate immediately to Critical.
            if ($grant.consentType -eq 'Principal')
            {
                if (-not $isVerified -and $detectedHighRiskScopes.Count -gt 0)
                {
                    $maxScore = [Math]::Max($maxScore, 9)
                    $riskReasons.Add("OAuth Phishing Vector: User consented to high-risk scopes for an unverified publisher")
                }
                elseif (-not $isVerified)
                {
                    $maxScore = [Math]::Max($maxScore, 5)
                    $riskReasons.Add("User-consented grant to unverified publisher without admin oversight")
                }
            }
            else
            {
                # Admin consent granted tenant-wide
                if ($detectedHighRiskScopes.Count -gt 0)
                {
                    $riskReasons.Add("Tenant-Wide Admin Consent: Elevated scopes granted organization-wide")
                }
            }

            # Finalize Risk Level
            $calculatedLevel = if ($maxScore -ge 9) { 'Critical' }
                               elseif ($maxScore -ge 7) { 'High' }
                               elseif ($maxScore -ge 5) { 'Medium' }
                               else { 'Low' }

            if ($RiskLevel -and $calculatedLevel -notin $RiskLevel)
            {
                continue
            }

            [void]$appsEncountered.Add($appIdVal)

            $record = [PSCustomObject]@{
                GrantId                     = $grant.id
                AppDisplayName              = $displayNameVal
                AppId                       = $appIdVal
                ServicePrincipalId          = $grant.clientId
                PublisherName               = $publisherName
                IsPublisherVerified         = $isVerified
                VerifiedPublisherId         = $verifiedPubId
                AppOwnerTenantId            = $ownerTenantId
                IsThirdParty                = $isThirdParty
                ConsentType                 = $grant.consentType
                ConsentedByUserId           = $grant.principalId
                ConsentedByUserPrincipalName = $consentedUpn
                ResourceDisplayName         = $resourceName
                ResourceId                  = $grant.resourceId
                Scopes                      = $scopeTokens
                HighRiskScopes              = @($detectedHighRiskScopes)
                RiskLevel                   = $calculatedLevel
                RiskScore                   = [int]$maxScore
                RiskReasons                 = @($riskReasons)
            }

            $records.Add($record)
        }

        # 8. Output results
        if ($Summary)
        {
            $summaryObj = [PSCustomObject]@{
                TotalGrantsScanned    = [int]$records.Count
                TotalAppsScanned      = [int]$appsEncountered.Count
                CriticalCount         = [int]@($records | Where-Object { $_.RiskLevel -eq 'Critical' }).Count
                HighCount             = [int]@($records | Where-Object { $_.RiskLevel -eq 'High' }).Count
                MediumCount           = [int]@($records | Where-Object { $_.RiskLevel -eq 'Medium' }).Count
                LowCount              = [int]@($records | Where-Object { $_.RiskLevel -eq 'Low' }).Count
                UnverifiedAppsCount   = [int]@($records | Where-Object { -not $_.IsPublisherVerified } | Select-Object -ExpandProperty AppId -Unique).Count
                ThirdPartyAppsCount   = [int]@($records | Where-Object { $_.IsThirdParty } | Select-Object -ExpandProperty AppId -Unique).Count
                UserConsentedCount    = [int]@($records | Where-Object { $_.ConsentType -eq 'Principal' }).Count
                AdminConsentedCount   = [int]@($records | Where-Object { $_.ConsentType -eq 'AllPrincipals' }).Count
                ScanTimestamp         = Format-ODataDateTime -DateTime (Get-UTCTime)
            }
            return $summaryObj
        }

        return @($records)
    }
}

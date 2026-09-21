function Get-GTRiskyAppPermissionReport
{
    <#
    .SYNOPSIS
    Scans Service Principals for high-risk permissions with targeted filtering options.

    .DESCRIPTION
    Retrieves Service Principals and analyzes their permissions (App Roles & OAuth Grants).
    Evaluates permissions using official Microsoft Graph DevX metadata (privilegeLevel 1-5)
    and curated high-impact security profiles. Adds forensic context (Who, When, Usage)
    and supports targeted analysis by App, Type, and Risk.

    RISK SCORING:
    - 9-10 (Critical): Full Tenant Takeover / Destruction.
    - 7-8 (High): Broad Data Access / Exfiltration / Privilege Escalation.
    - 5-6 (Medium): Standard Write Access / Impersonation.
    - 1-4 (Low): Least Privilege / Basic Read Access.

    .PARAMETER AppId
    Optional. Filter by specific Application (Client) IDs.
    If provided, only these apps are scanned.

    .PARAMETER PermissionType
    Filter the type of permissions to analyze: 'AppOnly', 'Delegated', or 'Both'. Default is 'Both'.

    .PARAMETER RiskLevel
    Filter output by specific risk levels (e.g., 'Critical', 'High'). Default returns all identified risks.

    .PARAMETER MinPrivilegeLevel
    Optional. Filter permissions by minimum Microsoft DevX privilege level (1-5).

    .PARAMETER PermissionsFile
    Optional. Custom file path to a graph-permissions.json metadata fixture. Defaults to data/graph-permissions.json.

    .PARAMETER HighRiskScopes
    Optional. Additional scopes to flag.

    .PARAMETER NewSession
    Forces a new Microsoft Graph session.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string[]]$AppId,

        [ValidateSet('AppOnly', 'Delegated', 'Both')]
        [string]$PermissionType = 'Both',

        [ValidateSet('Critical', 'High', 'Medium', 'Low')]
        [string[]]$RiskLevel,

        [ValidateRange(1, 5)]
        [int]$MinPrivilegeLevel,

        [string]$PermissionsFile,

        [string[]]$HighRiskScopes,
        [switch]$NewSession
    )

    begin
    {
        $modules = @('Microsoft.Graph.Authentication')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        # 1. Scopes Check
        $requiredScopes = @('AppRoleAssignment.Read.All', 'DelegatedPermissionGrant.Read.All', 'Application.Read.All', 'AuditLog.Read.All', 'User.Read.All')
        
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

        # 3. Load DevX Permissions Catalog
        $permissionCatalog = Get-GTPermissionDefinition -PermissionsFile $PermissionsFile

        # 4. Curated High-Impact Overrides
        $CuratedOverrides = @{
            'RoleManagement.ReadWrite.Directory'           = @{ Score = 10; Level = 'Critical'; Impact = 'Privilege Escalation';       Desc = 'Can promote self to Global Admin' }
            'AppRoleAssignment.ReadWrite.All'              = @{ Score = 10; Level = 'Critical'; Impact = 'Privilege Escalation';       Desc = 'Can grant self any permission' }
            'OnPremDirectorySynchronization.ReadWrite.All' = @{ Score = 10; Level = 'Critical'; Impact = 'Hybrid Identity Takeover';   Desc = 'Can tamper with directory synchronization accounts' }
            'Domain.ReadWrite.All'                         = @{ Score = 10; Level = 'Critical'; Impact = 'Domain Takeover';            Desc = 'Can manipulate verified tenant domains' }
            'UserAuthenticationMethod.ReadWrite.All'       = @{ Score = 10; Level = 'Critical'; Impact = 'Credential Manipulation';    Desc = 'Can reset MFA and authentication methods for users' }
            'DelegatedPermissionGrant.ReadWrite.All'       = @{ Score = 10; Level = 'Critical'; Impact = 'Privilege Escalation';       Desc = 'Can grant arbitrary delegated permissions' }
            'Directory.ReadWrite.All'                      = @{ Score = 9;  Level = 'Critical'; Impact = 'Tenant Destruction';         Desc = 'Can delete users, groups, and apps' }
            'Mail.ReadWrite'                               = @{ Score = 8;  Level = 'High';     Impact = 'Data Integrity';             Desc = 'Can read and modify all email' }
            'Files.ReadWrite.All'                          = @{ Score = 8;  Level = 'High';     Impact = 'Data Integrity';             Desc = 'Can read/modify all files' }
            'BitlockerKey.Read.All'                        = @{ Score = 8;  Level = 'High';     Impact = 'Cryptographic Exfiltration'; Desc = 'Can extract BitLocker volume recovery keys' }
            'Mail.Read'                                    = @{ Score = 7;  Level = 'High';     Impact = 'Data Exfiltration';          Desc = 'Can read all email' }
            'Files.Read.All'                               = @{ Score = 7;  Level = 'High';     Impact = 'Data Exfiltration';          Desc = 'Can read all files' }
            'Mail.Send'                                    = @{ Score = 6;  Level = 'Medium';   Impact = 'Impersonation';              Desc = 'Can send email as any user' }
            'User.ReadWrite.All'                           = @{ Score = 6;  Level = 'Medium';   Impact = 'User Modification';          Desc = 'Can modify user profiles' }
        }

        $UserCache = @{}
        $targetAppIds = [System.Collections.Generic.List[string]]::new()
    }

    process
    {
        if ($AppId) { $targetAppIds.AddRange($AppId) }
    }

    end
    {
        $CalculateRisk = {
            param(
                [string]$PermissionName,
                [ValidateSet('Application', 'Delegated')][string]$Scheme = 'Application',
                [string]$ConsentType = 'AllPrincipals'
            )

            # Check curated attack profiles first
            if ($CuratedOverrides.ContainsKey($PermissionName))
            {
                $curated = $CuratedOverrides[$PermissionName]
                $devxMeta = if ($permissionCatalog -and $permissionCatalog.ContainsKey($PermissionName)) { $permissionCatalog[$PermissionName] } else { $null }
                $devxPriv = if ($devxMeta) {
                    if ($Scheme -eq 'Application') { $devxMeta['appPrivilegeLevel'] } else { $devxMeta['delegatedPrivilegeLevel'] }
                } else { $null }
                $adminConsent = if ($devxMeta) { $devxMeta['requiresAdminConsent'] } else { $true }

                $curatedScore = $curated.Score
                $curatedLevel = $curated.Level

                # Delegated privilege ceiling: user-consented grants cannot exceed the delegating user's rights
                if ($Scheme -eq 'Delegated' -and $ConsentType -eq 'Principal')
                {
                    $curatedScore = [Math]::Max(2, $curatedScore - 1)
                    if ($curatedLevel -eq 'Critical') { $curatedLevel = 'High' }
                    elseif ($curatedScore -le 4) { $curatedLevel = 'Low' }
                    elseif ($curatedScore -le 6) { $curatedLevel = 'Medium' }
                }

                return [PSCustomObject]@{
                    Score                = $curatedScore
                    Level                = $curatedLevel
                    Impact               = $curated.Impact
                    Desc                 = $curated.Desc
                    PrivilegeLevel       = if ($null -ne $devxPriv) { [int]$devxPriv } else { 4 }
                    AdminConsentRequired = [bool]$adminConsent
                }
            }

            # Evaluate DevX catalog metadata
            if ($permissionCatalog -and $permissionCatalog.ContainsKey($PermissionName))
            {
                $meta = $permissionCatalog[$PermissionName]
                $privLevel = if ($Scheme -eq 'Application') { $meta['appPrivilegeLevel'] } else { $meta['delegatedPrivilegeLevel'] }

                if ($null -eq $privLevel)
                {
                    $privLevel = if ($Scheme -eq 'Application') { $meta['delegatedPrivilegeLevel'] } else { $meta['appPrivilegeLevel'] }
                }

                $adminConsent = [bool]$meta['requiresAdminConsent']
                $desc = if ($meta['description']) { $meta['description'] } else { "Microsoft Graph permission: $PermissionName" }

                $catScore = 2
                $catLevel = 'Low'
                $catImpact = 'Least Privilege'

                switch ($privLevel)
                {
                    { $_ -ge 5 } {
                        $catScore = 10
                        $catLevel = 'Critical'
                        $catImpact = 'Critical Privilege'
                    }
                    4 {
                        $catScore = 8
                        $catLevel = 'High'
                        $catImpact = 'High Privilege'
                    }
                    3 {
                        $catScore = 6
                        $catLevel = 'Medium'
                        $catImpact = 'Medium Privilege'
                    }
                    2 {
                        $catScore = 4
                        $catLevel = 'Low'
                        $catImpact = 'Low Privilege'
                    }
                    default {
                        $catScore = 2
                        $catLevel = 'Low'
                        $catImpact = 'Least Privilege'
                    }
                }

                # Delegated privilege ceiling: user-consented grants cannot exceed the delegating user's rights
                if ($Scheme -eq 'Delegated' -and $ConsentType -eq 'Principal')
                {
                    $catScore = [Math]::Max(2, $catScore - 1)
                    if ($catLevel -eq 'Critical') { $catLevel = 'High' }
                    elseif ($catScore -le 4) { $catLevel = 'Low' }
                    elseif ($catScore -le 6) { $catLevel = 'Medium' }
                }

                return [PSCustomObject]@{
                    Score                = $catScore
                    Level                = $catLevel
                    Impact               = $catImpact
                    Desc                 = $desc
                    PrivilegeLevel       = if ($null -ne $privLevel) { [int]$privLevel } else { 1 }
                    AdminConsentRequired = $adminConsent
                }
            }

            # 3. Heuristic fallback for unmapped or custom scopes
            $baseScore = 5
            $baseLevel = 'Medium'
            $impact = 'Custom Definition'
            $desc = 'Unmapped scope inferred from naming convention'

            if ($PermissionName -match '\.(ReadWrite|Write|Manage)\.All$')
            {
                $baseScore = 7
                $baseLevel = 'High'
                $impact = 'Broad Modification'
            }
            elseif ($PermissionName -match '\.(ReadWrite|Write)$')
            {
                $baseScore = 5
                $baseLevel = 'Medium'
                $impact = 'Scoped Modification'
            }
            elseif ($PermissionName -match '\.(Read|ReadBasic)\.All$')
            {
                $baseScore = 5
                $baseLevel = 'Medium'
                $impact = 'Broad Read Access'
            }
            else
            {
                $baseScore = 5
                $baseLevel = 'Medium'
                $impact = 'Custom Definition'
                $desc = 'Flagged by user parameter'
            }

            # Application permissions run without user context (bump score by +1)
            if ($Scheme -eq 'Application' -and $baseScore -lt 10)
            {
                $baseScore = [Math]::Min($baseScore + 1, 10)
                if ($baseScore -ge 8) { $baseLevel = 'High' }
                elseif ($baseScore -ge 6) { $baseLevel = 'Medium' }
            }

            # Delegated privilege ceiling for user-scoped consent
            if ($Scheme -eq 'Delegated' -and $ConsentType -eq 'Principal' -and $baseScore -gt 2)
            {
                $baseScore = [Math]::Max(2, $baseScore - 1)
                if ($baseScore -le 4) { $baseLevel = 'Low' }
                elseif ($baseScore -le 6) { $baseLevel = 'Medium' }
            }

            return [PSCustomObject]@{
                Score                = $baseScore
                Level                = $baseLevel
                Impact               = $impact
                Desc                 = $desc
                PrivilegeLevel       = $null
                AdminConsentRequired = ($Scheme -eq 'Application' -or $baseScore -ge 6)
            }
        }

        $report = [System.Collections.Generic.List[PSCustomObject]]::new()
        $utcNow = Get-UTCTime

        try
        {
            # Cache Microsoft Graph App Roles and Resource-Specific Application Permissions for app-only ID-to-Name resolution
            Write-PSFMessage -Level Verbose -Message "Caching Microsoft Graph App Roles..."
            $graphSpResp = Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'&`$select=id,appRoles,resourceSpecificApplicationPermissions" -ErrorAction Stop
            $graphSp = $graphSpResp.value[0]
            $roleMap = @{}
            if ($graphSp.appRoles) {
                foreach ($role in $graphSp.appRoles) { $roleMap[$role.id] = $role.value }
            }
            if ($graphSp.resourceSpecificApplicationPermissions) {
                foreach ($rsc in $graphSp.resourceSpecificApplicationPermissions) { $roleMap[$rsc.id] = $rsc.value }
            }

            # Fetch Service Principals
            # beta required: signInActivity is not available on servicePrincipals in v1.0
            if ($targetAppIds.Count -gt 0) {
                $safeIds = $targetAppIds | ForEach-Object { ($_ -replace "'", "''") }
                $spFilter = "appId in ('" + ($safeIds -join "','") + "')"
                Write-PSFMessage -Level Verbose -Message "Fetching specific Service Principals ($($targetAppIds.Count))..."
                $sps = Invoke-GTGraphPagedRequest -Uri "beta/servicePrincipals?`$filter=$([Uri]::EscapeDataString($spFilter))&`$select=id,appId,displayName,signInActivity&`$expand=appRoleAssignments" -Headers @{ ConsistencyLevel = 'eventual' }
            }
            else {
                Write-PSFMessage -Level Verbose -Message "Fetching ALL Service Principals..."
                $sps = Invoke-GTGraphPagedRequest -Uri "beta/servicePrincipals?`$select=id,appId,displayName,signInActivity&`$expand=appRoleAssignments"
            }
            
            $spLookup = @{}
            foreach ($sp in $sps) { $spLookup[$sp.id] = $sp }

            # Phase 1: App-Only Permissions
            if ($PermissionType -in 'Both', 'AppOnly')
            {
                Write-PSFMessage -Level Verbose -Message "Analyzing App-Only Assignments..."
                
                foreach ($sp in $sps)
                {
                    $lastSignIn = $sp.signInActivity.lastSignInDateTime
                    $isActive = $false
                    if ($lastSignIn) {
                        $daysSince = (New-TimeSpan -Start $lastSignIn -End $utcNow).Days
                        if ($daysSince -le 90) { $isActive = $true }
                    }

                    if ($sp.appRoleAssignments)
                    {
                        foreach ($assign in $sp.appRoleAssignments)
                        {
                            if ($assign.resourceId -eq $graphSp.id)
                            {
                                $permName = $roleMap[$assign.appRoleId]
                                
                                if ($permName)
                                {
                                    $riskInfo = & $CalculateRisk -PermissionName $permName -Scheme 'Application'

                                    # Inclusion decision
                                    $isCandidate = $false
                                    if ($HighRiskScopes -and ($HighRiskScopes -contains $permName)) {
                                        $isCandidate = $true
                                    }
                                    elseif ($MinPrivilegeLevel) {
                                        if ($riskInfo.PrivilegeLevel -and ($riskInfo.PrivilegeLevel -ge $MinPrivilegeLevel)) {
                                            $isCandidate = $true
                                        }
                                    }
                                    elseif ($RiskLevel) {
                                        if ($riskInfo.Level -in $RiskLevel) {
                                            $isCandidate = $true
                                        }
                                    }
                                    else {
                                        if ($riskInfo.Level -in @('Critical', 'High') -or $CuratedOverrides.ContainsKey($permName)) {
                                            $isCandidate = $true
                                        }
                                    }

                                    if ($isCandidate)
                                    {
                                        $report.Add([PSCustomObject]@{
                                            AppName              = $sp.displayName
                                            AppId                = $sp.appId
                                            Type                 = "Application (App-Only)"
                                            Permission           = $permName
                                            RiskLevel            = $riskInfo.Level
                                            RiskScore            = $riskInfo.Score
                                            PrivilegeLevel       = $riskInfo.PrivilegeLevel
                                            AdminConsentRequired = $riskInfo.AdminConsentRequired
                                            Impact               = $riskInfo.Impact
                                            GrantedDate          = $assign.creationTimestamp
                                            GrantedBy            = "Administrator"
                                            LastSignIn           = $lastSignIn
                                            IsActive             = $isActive
                                            Description          = $riskInfo.Desc
                                        })
                                    }
                                }
                            }
                        }
                    }
                }
            }

            # Phase 2: Delegated Permissions
            if ($PermissionType -in 'Both', 'Delegated')
            {
                Write-PSFMessage -Level Verbose -Message "Fetching Delegated Grants..."
                
                if ($targetAppIds.Count -gt 0) {
                    $spObjectIds = $sps | ForEach-Object { $_.id }
                    if ($spObjectIds) {
                        $grantFilter = "clientId in ('" + ($spObjectIds -join "','") + "')"
                        $grants = Invoke-GTGraphPagedRequest -Uri "v1.0/oauth2PermissionGrants?`$filter=$([Uri]::EscapeDataString($grantFilter))" -Headers @{ ConsistencyLevel = 'eventual' }
                    } else {
                        $grants = @()
                    }
                }
                else {
                    $grants = Invoke-GTGraphPagedRequest -Uri "v1.0/oauth2PermissionGrants?`$filter=resourceId eq '$($graphSp.id)'"
                }

                foreach ($grant in $grants)
                {
                    $grantedScopes = $grant.scope -split ' '
                    
                    foreach ($scope in $grantedScopes)
                    {
                        if (-not [string]::IsNullOrWhiteSpace($scope))
                        {
                            $riskInfo = & $CalculateRisk -PermissionName $scope -Scheme 'Delegated' -ConsentType $grant.consentType

                            # Inclusion decision
                            $isCandidate = $false
                            if ($HighRiskScopes -and ($HighRiskScopes -contains $scope)) {
                                $isCandidate = $true
                            }
                            elseif ($MinPrivilegeLevel) {
                                if ($riskInfo.PrivilegeLevel -and ($riskInfo.PrivilegeLevel -ge $MinPrivilegeLevel)) {
                                    $isCandidate = $true
                                }
                            }
                            elseif ($RiskLevel) {
                                if ($riskInfo.Level -in $RiskLevel) {
                                    $isCandidate = $true
                                }
                            }
                            else {
                                if ($riskInfo.Level -in @('Critical', 'High') -or $CuratedOverrides.ContainsKey($scope)) {
                                    $isCandidate = $true
                                }
                            }

                            if ($isCandidate)
                            {
                                $clientSp = $spLookup[$grant.clientId]
                                $appName = if ($clientSp) { $clientSp.displayName } else { $grant.clientId }
                                $appId = if ($clientSp) { $clientSp.appId } else { "Unknown" }
                                
                                $lastSignIn = if ($clientSp) { $clientSp.signInActivity.lastSignInDateTime } else { $null }
                                $isActive = $false
                                if ($lastSignIn) {
                                    $daysSince = (New-TimeSpan -Start $lastSignIn -End $utcNow).Days
                                    if ($daysSince -le 90) { $isActive = $true }
                                }

                                $grantedBy = "Unknown"
                                $target = "Specific User"

                                if ($grant.consentType -eq 'AllPrincipals') {
                                    $target = "Entire Tenant"
                                    $grantedBy = "Administrator"
                                }
                                elseif ($grant.principalId) {
                                    if (-not $UserCache.ContainsKey($grant.principalId)) {
                                        try {
                                            $uResp = Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/$($grant.principalId)?`$select=userPrincipalName" -ErrorAction SilentlyContinue
                                            $UserCache[$grant.principalId] = if ($uResp) { $uResp.userPrincipalName } else { "Deleted User ($($grant.principalId))" }
                                        } catch {
                                            $UserCache[$grant.principalId] = "Unknown"
                                        }
                                    }
                                    $grantedBy = $UserCache[$grant.principalId]
                                }

                                $report.Add([PSCustomObject]@{
                                    AppName              = $appName
                                    AppId                = $appId
                                    Type                 = "Delegated ($target)"
                                    Permission           = $scope
                                    RiskLevel            = $riskInfo.Level
                                    RiskScore            = $riskInfo.Score
                                    PrivilegeLevel       = $riskInfo.PrivilegeLevel
                                    AdminConsentRequired = $riskInfo.AdminConsentRequired
                                    Impact               = $riskInfo.Impact
                                    GrantedDate          = $grant.startTime
                                    GrantedBy            = $grantedBy
                                    LastSignIn           = $lastSignIn
                                    IsActive             = $isActive
                                    Description          = $riskInfo.Desc
                                })
                            }
                        }
                    }
                }
            }

            if ($RiskLevel) {
                $report = @($report | Where-Object { $_.RiskLevel -in $RiskLevel })
            }

            if (@($report).Count -gt 0) {
                Write-PSFMessage -Level Warning -Message "Found $(@($report).Count) risky assignments."
                return @($report | Sort-Object RiskScore -Descending)
            } else {
                Write-PSFMessage -Level Verbose -Message "No high-risk permissions found matching criteria."
                return @()
            }
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'Permissions'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to audit permissions: $($err.Reason)"
            throw $err.ErrorMessage
        }
    }
}
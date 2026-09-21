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
            'RoleManagement.ReadWrite.Directory' = @{ Score = 10; Level = 'Critical'; Impact = 'Privilege Escalation'; Desc = 'Can promote self to Global Admin' }
            'AppRoleAssignment.ReadWrite.All'    = @{ Score = 10; Level = 'Critical'; Impact = 'Privilege Escalation'; Desc = 'Can grant self any permission' }
            'Directory.ReadWrite.All'            = @{ Score = 9;  Level = 'Critical'; Impact = 'Tenant Destruction';   Desc = 'Can delete users, groups, and apps' }
            'Mail.ReadWrite'                     = @{ Score = 8;  Level = 'High';     Impact = 'Data Integrity';       Desc = 'Can read and modify all email' }
            'Files.ReadWrite.All'                = @{ Score = 8;  Level = 'High';     Impact = 'Data Integrity';       Desc = 'Can read/modify all files' }
            'Mail.Read'                          = @{ Score = 7;  Level = 'High';     Impact = 'Data Exfiltration';    Desc = 'Can read all email' }
            'Files.Read.All'                     = @{ Score = 7;  Level = 'High';     Impact = 'Data Exfiltration';    Desc = 'Can read all files' }
            'Mail.Send'                          = @{ Score = 6;  Level = 'Medium';   Impact = 'Impersonation';        Desc = 'Can send email as any user' }
            'User.ReadWrite.All'                 = @{ Score = 6;  Level = 'Medium';   Impact = 'User Modification';    Desc = 'Can modify user profiles' }
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
                [ValidateSet('Application', 'Delegated')][string]$Scheme = 'Application'
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

                return [PSCustomObject]@{
                    Score                = $curated.Score
                    Level                = $curated.Level
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

                switch ($privLevel)
                {
                    { $_ -ge 5 } {
                        return [PSCustomObject]@{
                            Score                = 10
                            Level                = 'Critical'
                            Impact               = 'Critical Privilege'
                            Desc                 = $desc
                            PrivilegeLevel       = [int]$privLevel
                            AdminConsentRequired = $adminConsent
                        }
                    }
                    4 {
                        return [PSCustomObject]@{
                            Score                = 8
                            Level                = 'High'
                            Impact               = 'High Privilege'
                            Desc                 = $desc
                            PrivilegeLevel       = [int]$privLevel
                            AdminConsentRequired = $adminConsent
                        }
                    }
                    3 {
                        return [PSCustomObject]@{
                            Score                = 6
                            Level                = 'Medium'
                            Impact               = 'Medium Privilege'
                            Desc                 = $desc
                            PrivilegeLevel       = 3
                            AdminConsentRequired = $adminConsent
                        }
                    }
                    2 {
                        return [PSCustomObject]@{
                            Score                = 4
                            Level                = 'Low'
                            Impact               = 'Low Privilege'
                            Desc                 = $desc
                            PrivilegeLevel       = 2
                            AdminConsentRequired = $adminConsent
                        }
                    }
                    default {
                        return [PSCustomObject]@{
                            Score                = 2
                            Level                = 'Low'
                            Impact               = 'Least Privilege'
                            Desc                 = $desc
                            PrivilegeLevel       = if ($null -ne $privLevel) { [int]$privLevel } else { 1 }
                            AdminConsentRequired = $adminConsent
                        }
                    }
                }
            }

            # Unknown or custom scope
            return [PSCustomObject]@{
                Score                = 5
                Level                = 'Medium'
                Impact               = 'Custom Definition'
                Desc                 = 'Flagged by user parameter'
                PrivilegeLevel       = $null
                AdminConsentRequired = $null
            }
        }

        $report = [System.Collections.Generic.List[PSCustomObject]]::new()
        $utcNow = Get-UTCTime

        try
        {
            # Cache Microsoft Graph App Roles for app-only ID-to-Name resolution
            Write-PSFMessage -Level Verbose -Message "Caching Microsoft Graph App Roles..."
            $graphSpResp = Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'&`$select=id,appRoles" -ErrorAction Stop
            $graphSp = $graphSpResp.value[0]
            $roleMap = @{}
            foreach ($role in $graphSp.appRoles) { $roleMap[$role.id] = $role.value }

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
                    $grants = Invoke-GTGraphPagedRequest -Uri "v1.0/oauth2PermissionGrants"
                }

                foreach ($grant in $grants)
                {
                    $grantedScopes = $grant.scope -split ' '
                    
                    foreach ($scope in $grantedScopes)
                    {
                        if (-not [string]::IsNullOrWhiteSpace($scope))
                        {
                            $riskInfo = & $CalculateRisk -PermissionName $scope -Scheme 'Delegated'

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
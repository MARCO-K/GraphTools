function Get-GTRiskyAppPermissionReport
{
    <#
    .SYNOPSIS
    Scans Service Principals for high-risk permissions with targeted filtering options.

    .DESCRIPTION
    Retrieves Service Principals and analyzes their permissions (App Roles & OAuth Grants).
    It adds forensic context (Who, When, Usage) and supports targeted analysis by App, Type, and Risk.

    RISK SCORING:
    - 10 (Critical): Full Tenant Takeover.
    - 7-9 (High): Data Exfiltration/Destruction.
    - 6 (Medium): Impersonation.

    .PARAMETER AppId
    Optional. Filter by specific Application (Client) IDs.
    If provided, only these apps are scanned.

    .PARAMETER PermissionType
    Filter the type of permissions to analyze: 'AppOnly', 'Delegated', or 'Both'. Default is 'Both'.

    .PARAMETER RiskLevel
    Filter output by specific risk levels (e.g., 'Critical', 'High'). Default returns all identified risks.

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

        [string[]]$HighRiskScopes,
        [switch]$NewSession
    )

    begin
    {
        $modules = @('Microsoft.Graph.Beta.Applications', 'Microsoft.Graph.Beta.Identity.SignIns', 'Microsoft.Graph.Users')
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

        # 3. Define Risk Engine
        $RiskEngine = @{
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

        $TargetScopes = [System.Collections.Generic.List[string]]::new($RiskEngine.Keys)
        if ($HighRiskScopes) {
            foreach ($s in $HighRiskScopes) { if (-not $TargetScopes.Contains($s)) { $TargetScopes.Add($s) } }
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
            param($PermissionName)
            if ($RiskEngine.ContainsKey($PermissionName)) { return $RiskEngine[$PermissionName] }
            else { return @{ Score = 5; Level = 'Medium'; Impact = 'Custom Definition'; Desc = 'Flagged by user parameter' } }
        }

        $report = [System.Collections.Generic.List[PSCustomObject]]::new()
        $utcNow = (Get-Date).ToUniversalTime()

        try
        {
            # --- Pre-Req: Cache Microsoft Graph App Roles ---
            Write-PSFMessage -Level Verbose -Message "Caching Microsoft Graph App Roles..."
            $graphSp = Get-MgBetaServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -Property Id, AppRoles -ErrorAction Stop
            $roleMap = @{}
            foreach ($role in $graphSp.AppRoles) { $roleMap[$role.Id] = $role.Value }

            # --- Fetch Service Principals (Targeted or All) ---
            $spParams = @{
                All = $true
                Property = @('id', 'appId', 'displayName', 'signInActivity')
                ExpandProperty = @('appRoleAssignments')
                ErrorAction = 'Stop'
            }

            if ($targetAppIds.Count -gt 0) {
                # Build safe filter for specific App IDs
                $safeIds = $targetAppIds | ForEach-Object { ($_ -replace "'", "''") }
                $spParams['Filter'] = "appId in ('" + ($safeIds -join "','") + "')"
                $spParams.Remove('All') # Filter implies not all
                Write-PSFMessage -Level Verbose -Message "Fetching specific Service Principals ($($targetAppIds.Count))..."
            }
            else {
                Write-PSFMessage -Level Verbose -Message "Fetching ALL Service Principals..."
            }

            $sps = Get-MgBetaServicePrincipal @spParams
            
            # Create lookup for later OAuth matching
            $spLookup = @{}
            foreach ($sp in $sps) { $spLookup[$sp.Id] = $sp }

            # --- Phase 1: App-Only Permissions ---
            if ($PermissionType -in 'Both', 'AppOnly')
            {
                Write-PSFMessage -Level Verbose -Message "Analyzing App-Only Assignments..."
                
                foreach ($sp in $sps)
                {
                    # Check Usage
                    $lastSignIn = $sp.SignInActivity.LastSignInDateTime
                    $isActive = $false
                    if ($lastSignIn) {
                        $daysSince = (New-TimeSpan -Start $lastSignIn -End $utcNow).Days
                        if ($daysSince -le 90) { $isActive = $true }
                    }

                    if ($sp.AppRoleAssignments)
                    {
                        foreach ($assign in $sp.AppRoleAssignments)
                        {
                            if ($assign.ResourceId -eq $graphSp.Id)
                            {
                                $permName = $roleMap[$assign.AppRoleId]
                                
                                if ($permName -and ($TargetScopes -contains $permName))
                                {
                                    $riskInfo = & $CalculateRisk -PermissionName $permName
                                    
                                    $report.Add([PSCustomObject]@{
                                        AppName        = $sp.DisplayName
                                        AppId          = $sp.AppId
                                        Type           = "Application (App-Only)"
                                        Permission     = $permName
                                        RiskLevel      = $riskInfo.Level
                                        RiskScore      = $riskInfo.Score
                                        Impact         = $riskInfo.Impact
                                        GrantedDate    = $assign.CreationTimestamp
                                        GrantedBy      = "Administrator"
                                        LastSignIn     = $lastSignIn
                                        IsActive       = $isActive
                                        Description    = $riskInfo.Desc
                                    })
                                }
                            }
                        }
                    }
                }
            }

            # --- Phase 2: Delegated Permissions ---
            if ($PermissionType -in 'Both', 'Delegated')
            {
                Write-PSFMessage -Level Verbose -Message "Fetching Delegated Grants..."
                
                $oauthParams = @{ All = $true; ErrorAction = 'Stop' }
                
                # Optimization: If targeting specific Apps, filter OAuth grants by ClientId (which is the SP Object ID)
                if ($targetAppIds.Count -gt 0) {
                    $spObjectIds = $sps.Id
                    if ($spObjectIds) {
                        # OData 'IN' filter for clientIds
                        $oauthParams['Filter'] = "clientId in ('" + ($spObjectIds -join "','") + "')"
                        $oauthParams.Remove('All')
                    }
                }

                $grants = Get-MgBetaOauth2PermissionGrant @oauthParams

                foreach ($grant in $grants)
                {
                    $grantedScopes = $grant.Scope -split ' '
                    
                    foreach ($scope in $grantedScopes)
                    {
                        if ($TargetScopes -contains $scope)
                        {
                            # Resolve Client App Details
                            $clientSp = $spLookup[$grant.ClientId]
                            
                            $appName = if ($clientSp) { $clientSp.DisplayName } else { $grant.ClientId }
                            $appId = if ($clientSp) { $clientSp.AppId } else { "Unknown" }
                            
                            # Usage Check
                            $lastSignIn = if ($clientSp) { $clientSp.SignInActivity.LastSignInDateTime } else { $null }
                            $isActive = $false
                            if ($lastSignIn) {
                                $daysSince = (New-TimeSpan -Start $lastSignIn -End $utcNow).Days
                                if ($daysSince -le 90) { $isActive = $true }
                            }

                            # Resolve "Who"
                            $grantedBy = "Unknown"
                            $target = "Specific User"

                            if ($grant.ConsentType -eq 'AllPrincipals') {
                                $target = "Entire Tenant"
                                $grantedBy = "Administrator"
                            }
                            elseif ($grant.PrincipalId) {
                                if (-not $UserCache.ContainsKey($grant.PrincipalId)) {
                                    try {
                                        $u = Get-MgUser -UserId $grant.PrincipalId -Property UserPrincipalName -ErrorAction SilentlyContinue
                                        $UserCache[$grant.PrincipalId] = if ($u) { $u.UserPrincipalName } else { "Deleted User ($($grant.PrincipalId))" }
                                    } catch {
                                        $UserCache[$grant.PrincipalId] = "Unknown"
                                    }
                                }
                                $grantedBy = $UserCache[$grant.PrincipalId]
                            }

                            $riskInfo = & $CalculateRisk -PermissionName $scope

                            $report.Add([PSCustomObject]@{
                                AppName        = $appName
                                AppId          = $appId
                                Type           = "Delegated ($target)"
                                Permission     = $scope
                                RiskLevel      = $riskInfo.Level
                                RiskScore      = $riskInfo.Score
                                Impact         = $riskInfo.Impact
                                GrantedDate    = $grant.StartTime
                                GrantedBy      = $grantedBy
                                LastSignIn     = $lastSignIn
                                IsActive       = $isActive
                                Description    = $riskInfo.Desc
                            })
                        }
                    }
                }
            }

            # --- Filter & Sort ---
            if ($RiskLevel) {
                $report = $report | Where-Object { $_.RiskLevel -in $RiskLevel }
            }

            if ($report.Count -gt 0) {
                Write-PSFMessage -Level Warning -Message "Found $($report.Count) risky assignments."
                return $report | Sort-Object RiskScore -Descending
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
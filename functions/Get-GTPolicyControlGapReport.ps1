function Get-GTPolicyControlGapReport
{
    <#
    .SYNOPSIS
    Analyzes Conditional Access policies to identify security gaps, including Auth Strength, Custom Controls, and Bypass vectors.

    .DESCRIPTION
    Retrieves Conditional Access policies and analyzes their 'Grant' controls.
    It includes a detailed 'PolicyContext' field to show exactly who and what the policy targets.

    GAP TYPES:
    1. "Critical: Implicit Allow" - No controls configured.
    2. "Critical: Weak Only"      - Only weak controls (e.g., Terms of Use) are required.
    3. "Warning: Weak Bypass"     - Strong controls exist but can be bypassed via 'OR' operator.

    .PARAMETER State
    Specifies the states of the Conditional Access policies to retrieve.

    .PARAMETER NewSession
    Forces a new Microsoft Graph session.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet('enabled', 'disabled', 'enabledForReportingButNotEnforced')]
        [string[]]$State = @('enabled', 'enabledForReportingButNotEnforced'),

        [switch]$NewSession
    )

    begin
    {
        $modules = @('Microsoft.Graph.Identity.SignIns')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        # 1. Scopes Check
        $requiredScopes = @('Policy.Read.All')
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

        # 3. Cache Authentication Strengths
        Write-PSFMessage -Level Verbose -Message "Caching Authentication Strength policies..."
        $authStrengthCache = @{}
        try {
            $strengths = Get-MgIdentityConditionalAccessAuthenticationStrengthPolicy -All -ErrorAction SilentlyContinue
            foreach ($s in $strengths) {
                $authStrengthCache[$s.Id] = $s.DisplayName
            }
            Write-PSFMessage -Level Verbose -Message "Cached $($authStrengthCache.Count) Auth Strength definitions."
        }
        catch {
            Write-PSFMessage -Level Warning -Message "Could not resolve Auth Strength names. GUIDs will be displayed."
        }
    }

    process
    {
        $gapReport = [System.Collections.Generic.List[PSCustomObject]]::new()

        try
        {
            Write-PSFMessage -Level Verbose -Message "Starting CA policy gap analysis for states: $($State -join ', ')"

            # 4. Build Dynamic Filter
            $filterConditions = $State | ForEach-Object { "state eq '$_'" }
            $filter = $filterConditions -join ' or '
            
            # 5. Optimize Property Selection
            $props = @('id', 'displayName', 'state', 'grantControls', 'conditions')

            $policies = Get-MgIdentityConditionalAccessPolicy -Filter $filter -Property $props -ErrorAction Stop

            Write-PSFMessage -Level Verbose -Message "Analyzing $($policies.Count) policies..."

            foreach ($policy in $policies)
            {
                # --- Analysis Logic ---
                
                # Check for BLOCK (Ultimate Security)
                if ($policy.GrantControls.BuiltInControls -contains 'block') {
                    continue 
                }

                $controls = $policy.GrantControls.BuiltInControls
                $operator = $policy.GrantControls.Operator
                $authStrength = $policy.GrantControls.AuthenticationStrength
                $customControls = $policy.GrantControls.CustomAuthenticationFactors

                # Identify Strong Controls
                $hasMfa = ($controls -contains 'mfa')
                $hasAuthStrength = ($null -ne $authStrength) 
                $hasDeviceTrust = ($controls -contains 'compliantDevice') -or ($controls -contains 'domainJoinedDevice')
                $hasCustomControl = ($null -ne $customControls -and $customControls.Count -gt 0)

                $isStrong = ($hasMfa -or $hasAuthStrength -or $hasDeviceTrust -or $hasCustomControl)

                # Identify Weak Controls / Bypass Vectors
                $weakControlsFound = [System.Collections.Generic.List[string]]::new()
                
                if ($controls -contains 'termsOfUse') { $weakControlsFound.Add('termsOfUse') }
                if ($controls -contains 'passwordChange') { $weakControlsFound.Add('passwordChange') }
                if ($controls -contains 'password') { $weakControlsFound.Add('password') }
                if ($controls -contains 'approvedApplication') { $weakControlsFound.Add('approvedApplication') }
                if ($controls -contains 'compliantApp') { $weakControlsFound.Add('compliantApp') }

                $gapType = $null
                $reason = $null
                $missing = [System.Collections.Generic.List[string]]::new()

                # --- Scenario A: No Controls (Implicit Allow) ---
                if (-not $policy.GrantControls -or (-not $controls -and -not $authStrength -and -not $customControls))
                {
                    $gapType = "Critical: Implicit Allow"
                    $reason = "Policy has no Grant controls configured."
                    $missing.Add("Any Grant Control")
                }
                # --- Scenario B: Weak Controls Only (No Strong Auth) ---
                elseif (-not $isStrong)
                {
                    $gapType = "Critical: Weak Only"
                    $reason = "Policy relies solely on weak/app-based controls ($($weakControlsFound -join ', '))."
                    $missing.Add("Strong Authentication")
                    $missing.Add("Device Compliance")
                }
                # --- Scenario C: Weak Bypass (The 'OR' Trap) ---
                elseif ($isStrong -and ($weakControlsFound.Count -gt 0) -and $operator -eq 'OR')
                {
                    $gapType = "Warning: Weak Bypass"
                    $reason = "Policy allows bypassing Strong Auth by satisfying: $($weakControlsFound -join ' OR ')."
                    $missing.Add("Operator: AND (Require all)")
                }

                # --- Reporting ---
                if ($gapType)
                {
                    # Flatten controls for display
                    $displayControls = [System.Collections.Generic.List[string]]::new()
                    if ($controls) { $displayControls.AddRange($controls) }
                    
                    if ($authStrength) { 
                        $name = if ($authStrengthCache.ContainsKey($authStrength.Id)) { $authStrengthCache[$authStrength.Id] } else { $authStrength.Id }
                        $displayControls.Add("AuthStrength: $name") 
                    }
                    if ($customControls) { $displayControls.Add("CustomControl: $($customControls -join ', ')") }
                    
                    # --- Enhanced Context Parsing ---
                    $users = $policy.Conditions.Users
                    $apps = $policy.Conditions.Applications

                    # Determine User Scope
                    $hasExclusions = ($users.ExcludeUsers.Count -gt 0) -or ($users.ExcludeGroups.Count -gt 0) -or ($users.ExcludeRoles.Count -gt 0)

                    $userScope = switch ($users) {
                        { $_.IncludeUsers -contains 'All' -and -not $hasExclusions } { "All Users (No Exclusions)"; break }
                        { $_.IncludeUsers -contains 'All' } { "All Users (With Exclusions)"; break }
                        { $_.IncludeUsers -contains 'GuestsOrExternalUsers' } { "Guests"; break }
                        { $_.IncludeRoles.Count -gt 0 } { "Role Holders ($($_.IncludeRoles.Count))"; break }
                        { $_.IncludeGroups.Count -gt 0 } { "Group Members ($($_.IncludeGroups.Count))"; break }
                        default { "Specific Users" }
                    }

                    # Determine App Scope (Updated with Generic Action Catch-all)
                    $appScope = switch ($apps) {
                        { $_.IncludeApplications -contains 'All' } { "All Cloud Apps"; break }
                        { $_.IncludeUserActions -contains 'RegisterSecurityInformation' } { "Security Info Reg"; break }
                        { $_.IncludeUserActions -contains 'RegisterDevice' } { "Device Reg"; break }
                        { $_.IncludeUserActions.Count -gt 0 } { "$($_.IncludeUserActions.Count) User Actions"; break }
                        default { "Specific Apps" }
                    }
                    
                    $context = "$userScope -> $appScope"

                    $gapReport.Add([PSCustomObject]@{
                        PolicyName      = $policy.DisplayName
                        PolicyId        = $policy.Id
                        State           = $policy.State
                        GapSeverity     = $gapType
                        PolicyContext   = $context
                        GrantOperator   = $operator
                        CurrentControls = $displayControls -join ', '
                        MissingControls = $missing -join ' OR '
                        Reason          = $reason
                    })
                }
            }

            if ($gapReport.Count -gt 0) {
                Write-PSFMessage -Level Warning -Message "Found $($gapReport.Count) policies with potential security gaps."
            } else {
                Write-PSFMessage -Level Verbose -Message "No gaps found."
            }

            return $gapReport.ToArray()
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'CA Policy'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve CA policies: $($err.Reason)"
            throw $err.ErrorMessage
        }
    }
}
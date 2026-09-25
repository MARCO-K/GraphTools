<#
.SYNOPSIS
    Orchestrates rapid security containment workflows for compromised Microsoft Entra ID user accounts.

.DESCRIPTION
    Executes a comprehensive, multi-step incident containment playbook to neutralize compromised
    user accounts with minimum latency.

    Containment steps orchestrated:
    1. Revoke active refresh tokens and browser session cookies (Revoke-GTSignOutFromAllSessions)
    2. Disable the user account to block future authentication attempts (Disable-GTUser)
    3. Reset the account password to terminate Continuous Access Evaluation (CAE) sessions (Reset-GTUserPassword)
    4. Disable all registered and workplace-joined devices to block token replay (Disable-GTUserDevice)
    5. Optionally strip all directory entitlements, group memberships, and role assignments (Remove-GTUserEntitlements)

    By default, standard containment executes steps 1-4. Step 5 (StripEntitlements) is destructive
    and is only executed when -StripEntitlements or -FullContainment is explicitly specified.

    Supports -WhatIf and -Confirm via ShouldProcess.

.PARAMETER UPN
    One or more User Principal Names (UPNs) of the accounts to contain. Must match valid email format.
    Accepts pipeline input by value and by property name.

    Aliases: UserPrincipalName, Users, User, UserName, UPNName

.PARAMETER RevokeSessions
    Invalidate all active OAuth refresh tokens and browser session cookies.

.PARAMETER DisableAccount
    Set accountEnabled to false to block new authentication requests.

.PARAMETER ResetPassword
    Generate a high-entropy random password to trigger Continuous Access Evaluation (CAE) session revocation.

.PARAMETER DisableDevices
    Disable all registered devices associated with the user account.

.PARAMETER StripEntitlements
    Remove all user entitlements including group memberships, directory roles, licenses, and PIM eligibilities.

.PARAMETER FullContainment
    Executes all containment actions including entitlement stripping (steps 1 through 5).

.PARAMETER Force
    Suppresses confirmation prompts during containment execution.

.PARAMETER NewSession
    If specified, creates a new Microsoft Graph session by disconnecting any existing session first.

.OUTPUTS
    System.Management.Automation.PSCustomObject[]
    Returns a structured containment report object per processed account with:
      - UserPrincipalName
      - Status ('Contained' | 'PartiallyContained' | 'Failed' | 'WhatIf')
      - TimeUtc
      - SessionsRevoked
      - AccountDisabled
      - PasswordReset
      - DevicesDisabled
      - EntitlementsStripped
      - ActionsExecuted
      - Errors

.EXAMPLE
    Invoke-GTUserContainment -UPN 'compromised.user@contoso.com'

    Executes standard safe containment (revokes sessions, disables account, resets password, disables devices).

.EXAMPLE
    'compromised@contoso.com' | Invoke-GTUserContainment -FullContainment -Force

    Executes full containment including entitlement stripping without interactive confirmation prompts.

.EXAMPLE
    Invoke-GTUserContainment -UPN 'suspect@contoso.com' -RevokeSessions -ResetPassword

    Executes selective containment (only revoking sessions and rotating password).

.EXAMPLE
    Invoke-GTUserContainment -UPN 'compromised@contoso.com' -WhatIf

    Displays containment actions that would be performed without executing them.
#>
function Invoke-GTUserContainment
{
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject[]])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({ $_ -match $script:GTValidationRegex.UPN })]
        [Alias('UserPrincipalName', 'Users', 'User', 'UserName', 'UPNName')]
        [string[]]$UPN,

        [switch]$RevokeSessions,
        [switch]$DisableAccount,
        [switch]$ResetPassword,
        [switch]$DisableDevices,
        [switch]$StripEntitlements,
        [switch]$FullContainment,

        [switch]$Force,
        [switch]$NewSession
    )

    begin
    {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Determine which actions are requested
        $selectiveActionsSpecified = (
            $PSBoundParameters.ContainsKey('RevokeSessions') -or
            $PSBoundParameters.ContainsKey('DisableAccount') -or
            $PSBoundParameters.ContainsKey('ResetPassword') -or
            $PSBoundParameters.ContainsKey('DisableDevices') -or
            $PSBoundParameters.ContainsKey('StripEntitlements')
        )

        $doRevokeSessions = $false
        $doDisableAccount = $false
        $doResetPassword  = $false
        $doDisableDevices = $false
        $doStripEntitlements = $false

        if ($FullContainment)
        {
            $doRevokeSessions    = $true
            $doDisableAccount    = $true
            $doResetPassword     = $true
            $doDisableDevices    = $true
            $doStripEntitlements = $true
        }
        elseif ($selectiveActionsSpecified)
        {
            $doRevokeSessions    = [bool]$RevokeSessions
            $doDisableAccount    = [bool]$DisableAccount
            $doResetPassword     = [bool]$ResetPassword
            $doDisableDevices    = [bool]$DisableDevices
            $doStripEntitlements = [bool]$StripEntitlements
        }
        else
        {
            # Default standard safe containment (all containment actions except destructive entitlement stripping)
            $doRevokeSessions = $true
            $doDisableAccount = $true
            $doResetPassword  = $true
            $doDisableDevices = $true
        }

        # Determine required permissions based on planned actions
        $requiredScopes = [System.Collections.Generic.List[string]]::new()
        $requiredScopes.Add('User.ReadWrite.All')

        if ($doDisableDevices)
        {
            $requiredScopes.Add('Directory.AccessAsUser.All')
        }

        if ($doStripEntitlements)
        {
            $entitlementScopes = @(
                'GroupMember.ReadWrite.All',
                'Group.ReadWrite.All',
                'Directory.ReadWrite.All',
                'RoleManagement.ReadWrite.Directory',
                'RoleEligibilitySchedule.ReadWrite.Directory',
                'AdministrativeUnit.ReadWrite.All',
                'EntitlementManagement.ReadWrite.All',
                'DelegatedPermissionGrant.ReadWrite.All'
            )
            foreach ($scope in $entitlementScopes)
            {
                if (-not $requiredScopes.Contains($scope))
                {
                    $requiredScopes.Add($scope)
                }
            }
        }

        # Initialize session and acquire scopes
        if (-not (Initialize-GTGraphConnection -Scopes $requiredScopes.ToArray() -NewSession:$NewSession))
        {
            Write-Error "Failed to establish Microsoft Graph connection."
            return
        }

        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes.ToArray() -Quiet))
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }

        Write-PSFMessage -Level Verbose -Message "Containment playbook initialized. Actions configured: RevokeSessions=$doRevokeSessions, DisableAccount=$doDisableAccount, ResetPassword=$doResetPassword, DisableDevices=$doDisableDevices, StripEntitlements=$doStripEntitlements"
    }

    process
    {
        foreach ($targetUser in $UPN)
        {
            if ([string]::IsNullOrWhiteSpace($targetUser)) { continue }

            $timeUtc = (Get-UTCTime).ToString('o')
            $actionsRun = [System.Collections.Generic.List[string]]::new()
            $errors = [System.Collections.Generic.List[string]]::new()

            $sessionsRevokedResult     = 'Skipped'
            $accountDisabledResult     = 'Skipped'
            $passwordResetResult       = 'Skipped'
            $devicesDisabledResult     = 'Skipped'
            $entitlementsStrippedResult= 'Skipped'

            $actionTargetDescription = "Execute containment actions on $targetUser"
            if ($WhatIfPreference)
            {
                $null = $PSCmdlet.ShouldProcess($targetUser, $actionTargetDescription)
                $whatIfResult = [PSCustomObject]@{
                    UserPrincipalName    = $targetUser
                    Status               = 'WhatIf'
                    TimeUtc              = $timeUtc
                    SessionsRevoked      = if ($doRevokeSessions) { 'Pending' } else { 'Skipped' }
                    AccountDisabled      = if ($doDisableAccount) { 'Pending' } else { 'Skipped' }
                    PasswordReset        = if ($doResetPassword) { 'Pending' } else { 'Skipped' }
                    DevicesDisabled      = if ($doDisableDevices) { 'Pending' } else { 'Skipped' }
                    EntitlementsStripped = if ($doStripEntitlements) { 'Pending' } else { 'Skipped' }
                    ActionsExecuted      = @()
                    Errors               = @()
                }
                $results.Add($whatIfResult)
                continue
            }

            if (-not $Force -and -not $PSCmdlet.ShouldProcess($targetUser, $actionTargetDescription))
            {
                $skippedResult = [PSCustomObject]@{
                    UserPrincipalName    = $targetUser
                    Status               = 'Skipped'
                    TimeUtc              = $timeUtc
                    SessionsRevoked      = 'Skipped'
                    AccountDisabled      = 'Skipped'
                    PasswordReset        = 'Skipped'
                    DevicesDisabled      = 'Skipped'
                    EntitlementsStripped = 'Skipped'
                    ActionsExecuted      = @()
                    Errors               = @('Execution cancelled by confirmation prompt')
                }
                $results.Add($skippedResult)
                continue
            }

            Write-PSFMessage -Level Important -Message "Starting containment execution for user: $targetUser"

            # ---------------------------------------------------------
            # Step 1: Invalidate active refresh tokens and session cookies
            # ---------------------------------------------------------
            if ($doRevokeSessions)
            {
                $actionsRun.Add('RevokeSessions')
                try
                {
                    Write-PSFMessage -Level Verbose -Message "$targetUser - Revoking all active sign-in sessions..."
                    Revoke-GTSignOutFromAllSessions -UPN $targetUser -ErrorAction Stop
                    $sessionsRevokedResult = $true
                    Write-PSFMessage -Level Verbose -Message "$targetUser - Sessions revoked successfully."
                }
                catch
                {
                    $sessionsRevokedResult = $false
                    $errMsg = "RevokeSessions failed: $($_.Exception.Message)"
                    $errors.Add($errMsg)
                    Write-PSFMessage -Level Warning -Message "$targetUser - $errMsg"
                }
            }

            # ---------------------------------------------------------
            # Step 2: Block new sign-in attempts (Disable Account)
            # ---------------------------------------------------------
            if ($doDisableAccount)
            {
                $actionsRun.Add('DisableAccount')
                try
                {
                    Write-PSFMessage -Level Verbose -Message "$targetUser - Disabling user account..."
                    $disableOutput = Disable-GTUser -UPN $targetUser -Force:$Force -ErrorAction Stop
                    $userDisableStatus = ($disableOutput | Where-Object { $_.User -eq $targetUser } | Select-Object -First 1)

                    if ($userDisableStatus -and $userDisableStatus.Status -eq 'Disabled')
                    {
                        $accountDisabledResult = $true
                        Write-PSFMessage -Level Verbose -Message "$targetUser - Account disabled successfully."
                    }
                    else
                    {
                        $accountDisabledResult = $false
                        $reason = if ($userDisableStatus.Reason) { $userDisableStatus.Reason } else { "Failed to disable account" }
                        $errMsg = "DisableAccount failed: $reason"
                        $errors.Add($errMsg)
                        Write-PSFMessage -Level Warning -Message "$targetUser - $errMsg"
                    }
                }
                catch
                {
                    $accountDisabledResult = $false
                    $errMsg = "DisableAccount exception: $($_.Exception.Message)"
                    $errors.Add($errMsg)
                    Write-PSFMessage -Level Warning -Message "$targetUser - $errMsg"
                }
            }

            # ---------------------------------------------------------
            # Step 3: Rotate password to invalidate CAE active sessions
            # ---------------------------------------------------------
            if ($doResetPassword)
            {
                $actionsRun.Add('ResetPassword')
                try
                {
                    Write-PSFMessage -Level Verbose -Message "$targetUser - Resetting password to terminate CAE sessions..."
                    Reset-GTUserPassword -UPN $targetUser -ErrorAction Stop
                    $passwordResetResult = $true
                    Write-PSFMessage -Level Verbose -Message "$targetUser - Password reset successfully."
                }
                catch
                {
                    $passwordResetResult = $false
                    $errMsg = "ResetPassword failed: $($_.Exception.Message)"
                    $errors.Add($errMsg)
                    Write-PSFMessage -Level Warning -Message "$targetUser - $errMsg"
                }
            }

            # ---------------------------------------------------------
            # Step 4: Disable registered & workplace-joined devices
            # ---------------------------------------------------------
            if ($doDisableDevices)
            {
                $actionsRun.Add('DisableDevices')
                try
                {
                    Write-PSFMessage -Level Verbose -Message "$targetUser - Disabling registered devices..."
                    $deviceOutputs = Disable-GTUserDevice -UPN $targetUser -Force:$Force -ErrorAction Stop
                    $userDevices = @($deviceOutputs | Where-Object { $_.User -eq $targetUser })

                    $disabledCount = @($userDevices | Where-Object { $_.Status -eq 'Disabled' }).Count
                    $failedCount   = @($userDevices | Where-Object { $_.Status -eq 'Failed' }).Count
                    $hasNoDevices  = @($userDevices | Where-Object { $_.Status -eq 'NoDevices' }).Count -gt 0

                    if ($failedCount -gt 0)
                    {
                        $devicesDisabledResult = "Failed ($failedCount devices failed)"
                        $errMsg = "DisableDevices failed for $failedCount device(s)."
                        $errors.Add($errMsg)
                        Write-PSFMessage -Level Warning -Message "$targetUser - $errMsg"
                    }
                    elseif ($disabledCount -gt 0)
                    {
                        $devicesDisabledResult = "Disabled ($disabledCount device(s))"
                        Write-PSFMessage -Level Verbose -Message "$targetUser - $disabledCount device(s) disabled successfully."
                    }
                    elseif ($hasNoDevices -or @($userDevices).Count -eq 0)
                    {
                        $devicesDisabledResult = "NoDevices"
                        Write-PSFMessage -Level Verbose -Message "$targetUser - No registered devices found."
                    }
                    else
                    {
                        $devicesDisabledResult = "Processed ($(@($userDevices).Count) device(s))"
                    }
                }
                catch
                {
                    $devicesDisabledResult = "Failed"
                    $errMsg = "DisableDevices exception: $($_.Exception.Message)"
                    $errors.Add($errMsg)
                    Write-PSFMessage -Level Warning -Message "$targetUser - $errMsg"
                }
            }

            # ---------------------------------------------------------
            # Step 5: Strip Entitlements (Groups, Roles, Licenses, PIM)
            # ---------------------------------------------------------
            if ($doStripEntitlements)
            {
                $actionsRun.Add('StripEntitlements')
                try
                {
                    Write-PSFMessage -Level Verbose -Message "$targetUser - Stripping all entitlements..."
                    Remove-GTUserEntitlements -UserUPNs $targetUser -removeAll -ErrorAction Stop
                    $entitlementsStrippedResult = 'Stripped'
                    Write-PSFMessage -Level Verbose -Message "$targetUser - Entitlements stripped successfully."
                }
                catch
                {
                    $entitlementsStrippedResult = 'Failed'
                    $errMsg = "StripEntitlements exception: $($_.Exception.Message)"
                    $errors.Add($errMsg)
                    Write-PSFMessage -Level Warning -Message "$targetUser - $errMsg"
                }
            }

            # ---------------------------------------------------------
            # Evaluate Overall Containment Status
            # ---------------------------------------------------------
            $plannedActionCount = $actionsRun.Count
            $failedActionCount = 0

            if ($doRevokeSessions -and ($sessionsRevokedResult -ne $true)) { $failedActionCount++ }
            if ($doDisableAccount -and ($accountDisabledResult -ne $true)) { $failedActionCount++ }
            if ($doResetPassword -and ($passwordResetResult -ne $true)) { $failedActionCount++ }
            if ($doDisableDevices -and ($devicesDisabledResult -like 'Failed*')) { $failedActionCount++ }
            if ($doStripEntitlements -and ($entitlementsStrippedResult -eq 'Failed')) { $failedActionCount++ }

            $overallStatus = if ($failedActionCount -eq 0)
            {
                'Contained'
            }
            elseif ($failedActionCount -lt $plannedActionCount)
            {
                'PartiallyContained'
            }
            else
            {
                'Failed'
            }

            $userResult = [PSCustomObject]@{
                UserPrincipalName    = $targetUser
                Status               = $overallStatus
                TimeUtc              = $timeUtc
                SessionsRevoked      = $sessionsRevokedResult
                AccountDisabled      = $accountDisabledResult
                PasswordReset        = $passwordResetResult
                DevicesDisabled      = $devicesDisabledResult
                EntitlementsStripped = $entitlementsStrippedResult
                ActionsExecuted      = @($actionsRun)
                Errors               = @($errors)
            }

            $results.Add($userResult)
            Write-PSFMessage -Level Important -Message "$targetUser containment completed with status: $overallStatus"
        }
    }

    end
    {
        if ($results.Count -gt 0)
        {
            Write-Output ($results.ToArray())
        }
        else
        {
            Write-Output @()
        }
    }
}

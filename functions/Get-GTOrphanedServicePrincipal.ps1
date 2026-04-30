function Get-GTOrphanedServicePrincipal
{
    <#
    .SYNOPSIS
    Retrieves a list of Service Principals from Microsoft Entra ID that are orphaned or have security issues.

    .DESCRIPTION
    Connects to Microsoft Graph to fetch Service Principals and checks for:
    - No assigned owners.
    - All owners are disabled.
    - Expired secrets or certificates (optional).

    PERFORMANCE NOTE:
    - By default, this checks for OWNERS only.
    - Use -CheckExpiredCredentials to check for expired credentials.
    - This expands additional properties (keyCredentials, passwordCredentials) and may be slower.

    .PARAMETER CheckExpiredCredentials
    Switch to include checks for expired secrets and certificates.

    .PARAMETER NewSession
    Forces a new Microsoft Graph session.

    .EXAMPLE
    Get-GTOrphanedServicePrincipal -Verbose
    Retrieves all orphaned Service Principals (no owners or disabled owners).

    .EXAMPLE
    Get-GTOrphanedServicePrincipal -CheckExpiredCredentials
    Retrieves orphaned Service Principals AND those with expired credentials.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [switch]$CheckExpiredCredentials,
        [switch]$NewSession
    )

    begin
    {
        $modules = @('Microsoft.Graph.Authentication')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        # 1. Scopes Check (Gold Standard)
        # Directory.Read.All is needed to read owner status (User/SP accountEnabled)
        $requiredScopes = @('Application.Read.All', 'Directory.Read.All')
        
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
    }

    process
    {
        try
        {
            Write-PSFMessage -Level Verbose -Message "Fetching Service Principals from Microsoft Graph..."
            
            # Select specific properties to optimize bandwidth
            $properties = @('id', 'appId', 'displayName', 'servicePrincipalType', 'accountEnabled')
            
            if ($CheckExpiredCredentials)
            {
                $properties += 'keyCredentials'
                $properties += 'passwordCredentials'
            }

            Write-PSFMessage -Level Verbose -Message "Expanding properties: $($properties -join ', ')"

            # 3. UTC Date for Comparisons
            $utcNow = Get-UTCTime

            # 4. Collect SPs (with streaming-like processing via foreach)
            $selectStr = $properties -join ','
            $sps = Invoke-GTGraphPagedRequest -Uri "v1.0/servicePrincipals?`$select=$selectStr&`$expand=owners"
            foreach ($sp in $sps) {
                $sp = $sp
                $issues = [System.Collections.Generic.List[string]]::new()

                # --- Check 1: No Owners ---
                if (-not $sp.owners -or $sp.owners.Count -eq 0)
                {
                    $issues.Add("NoOwners")
                }
                else
                {
                    # --- Check 2: All Owners Disabled ---
                    $activeOwners = 0
                    $statusUnknown = 0

                    foreach ($owner in $sp.owners)
                    {
                        $isEnabled = $null
                        
                        # Invoke-MgGraphRequest returns hashtables; access accountEnabled directly
                        if ($null -ne $owner.accountEnabled)
                        {
                            $isEnabled = $owner.accountEnabled
                        }

                        if ($null -ne $isEnabled)
                        {
                            if ($isEnabled -eq $true) { $activeOwners++ }
                        }
                        else
                        {
                            # If property is missing, we can't prove they are disabled.
                            $statusUnknown++
                        }
                    }

                    if ($activeOwners -eq 0 -and $statusUnknown -eq 0)
                    {
                        $issues.Add("AllOwnersDisabled")
                    }
                }

                # --- Check 3: Expired Credentials (Optional) ---
                if ($CheckExpiredCredentials)
                {
                    $hasExpiredCreds = $false

                    # Check Secrets
                    if ($sp.passwordCredentials)
                    {
                        foreach ($cred in $sp.passwordCredentials)
                        {
                            if ($cred.endDateTime -and $cred.endDateTime -lt $utcNow)
                            {
                                $hasExpiredCreds = $true
                                break
                            }
                        }
                    }

                    # Check Certificates
                    if (-not $hasExpiredCreds -and $sp.keyCredentials)
                    {
                        foreach ($cred in $sp.keyCredentials)
                        {
                            if ($cred.endDateTime -and $cred.endDateTime -lt $utcNow)
                            {
                                $hasExpiredCreds = $true
                                break
                            }
                        }
                    }

                    if ($hasExpiredCreds)
                    {
                        $issues.Add("ExpiredCredentials")
                    }
                }

                # --- Output ---
                if ($issues.Count -gt 0)
                {
                    $issueString = $issues -join ', '
                    Write-PSFMessage -Level Debug -Message "Found SP issue: $($sp.DisplayName) (AppID: $($sp.AppId)). Issues: $issueString"
                    
                    [PSCustomObject]@{
                        DisplayName          = $sp.displayName
                        ObjectId             = $sp.id
                        AppId                = $sp.appId
                        ServicePrincipalType = $sp.servicePrincipalType
                        AccountEnabled       = $sp.accountEnabled
                        OrphanReason         = $issueString
                    }
                }
            }
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'Service Principals'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve Service Principals: $($err.Reason)"
            
            throw $err.ErrorMessage
        }
    }
}
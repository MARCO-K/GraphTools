function Get-GTOrphanedServicePrincipal {
    <#
    .SYNOPSIS
    Retrieves a list of Service Principals from Microsoft Entra ID that are orphaned or have security issues.

    .DESCRIPTION
    Connects to Microsoft Graph to fetch Service Principals and checks for:
    - No assigned owners.
    - All owners are disabled.
    - Expired secrets or certificates (optional).

    .PARAMETER CheckExpiredCredentials
    Switch to include checks for expired secrets and certificates.

    .EXAMPLE
    Get-GTOrphanedServicePrincipal -Verbose
    Retrieves all orphaned Service Principals (no owners or disabled owners).

    .EXAMPLE
    Get-GTOrphanedServicePrincipal -CheckExpiredCredentials
    Retrieves orphaned Service Principals AND those with expired credentials.

    .NOTES
    Requires Microsoft Graph PowerShell SDK with appropriate permissions:
    - Application.Read.All
    - Directory.Read.All (to check owner status)
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [switch]$CheckExpiredCredentials,
        [switch]$NewSession,
        [string[]]$Scope = @('Application.Read.All', 'Directory.Read.All')
    )

    begin {
        $requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Applications')
        Install-GTRequiredModule -ModuleNames $requiredModules -Verbose:$VerbosePreference
        Initialize-GTGraphConnection -Scopes $Scope -NewSession:$NewSession
    }

    process {
        $orphanedSPs = [System.Collections.Generic.List[object]]::new()
        try {
            Write-PSFMessage -Level Verbose -Message "Fetching Service Principals from Microsoft Graph..."
            
            $properties = @('id', 'appId', 'displayName', 'servicePrincipalType', 'accountEnabled')
            if ($CheckExpiredCredentials) {
                $properties += 'keyCredentials'
                $properties += 'passwordCredentials'
            }

            # Expand owners to check for existence and account status
            $sps = Get-MgBetaServicePrincipal -All -Property $properties -ExpandProperty 'owners' -ErrorAction Stop
        }
        catch {
            $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'resource'
            Write-PSFMessage -Level Error -Message "Failed to retrieve Service Principals. $($errorDetails.ErrorMessage)"
            Stop-PSFFunction -Message $errorDetails.Reason -ErrorRecord $_ -EnableException $true
            return
        }

        Write-PSFMessage -Level Debug -Message "Processing $($sps.Count) Service Principals."

        foreach ($sp in $sps) {
            $issues = [System.Collections.Generic.List[string]]::new()

            # Check 1: No Owners
            if (-not $sp.Owners -or $sp.Owners.Count -eq 0) {
                $issues.Add("NoOwners")
            }
            else {
                # Check 2: All Owners Disabled
                $activeOwnersCount = 0
                foreach ($owner in $sp.Owners) {
                    # Check for accountEnabled property
                    if ($owner.AdditionalProperties.ContainsKey('accountEnabled')) {
                        if ($owner.AdditionalProperties['accountEnabled'] -eq $true) { $activeOwnersCount++ }
                    }
                    elseif ($null -ne $owner.AccountEnabled) {
                        if ($owner.AccountEnabled -eq $true) { $activeOwnersCount++ }
                    }
                    else {
                        # Assume active if unknown
                        $activeOwnersCount++ 
                    }
                }

                if ($activeOwnersCount -eq 0) {
                    $issues.Add("AllOwnersDisabled")
                }
            }

            # Check 3: Expired Credentials
            if ($CheckExpiredCredentials) {
                $hasExpiredCreds = $false
                $now = Get-Date

                if ($sp.PasswordCredentials) {
                    foreach ($cred in $sp.PasswordCredentials) {
                        if ($cred.EndDateTime -and [datetime]$cred.EndDateTime -lt $now) {
                            $hasExpiredCreds = $true
                            break
                        }
                    }
                }
                if (-not $hasExpiredCreds -and $sp.KeyCredentials) {
                    foreach ($cred in $sp.KeyCredentials) {
                        if ($cred.EndDateTime -and [datetime]$cred.EndDateTime -lt $now) {
                            $hasExpiredCreds = $true
                            break
                        }
                    }
                }

                if ($hasExpiredCreds) {
                    $issues.Add("ExpiredCredentials")
                }
            }

            if ($issues.Count -gt 0) {
                $issueString = $issues -join ', '
                Write-PSFMessage -Level Debug -Message "Found SP issue: $($sp.DisplayName) (AppID: $($sp.AppId)). Issues: $issueString"
                
                $orphanedSPs.Add(
                    [PSCustomObject]@{
                        DisplayName          = $sp.DisplayName
                        ObjectId             = $sp.Id
                        AppId                = $sp.AppId
                        ServicePrincipalType = $sp.ServicePrincipalType
                        AccountEnabled       = $sp.AccountEnabled
                        Issues               = $issueString
                    }
                )
            }
        }

        Write-PSFMessage -Level Verbose -Message "Found $($orphanedSPs.Count) Service Principals with issues."
        return $orphanedSPs
    }
}

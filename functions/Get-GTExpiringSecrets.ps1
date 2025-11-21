function Get-GTExpiringSecrets
{
    <#
    .SYNOPSIS
    Retrieves Applications and Service Principals with secrets or certificates expiring within a specified timeframe.

    .DESCRIPTION
    This function scans Applications and Service Principals to identify credentials 
    (secrets or certificates) expiring within the specified number of days.
    
    It handles UTC time conversions correctly to ensure accurate expiration reporting.

    .PARAMETER DaysUntilExpiry
    The number of days to look ahead for expiration.

    .PARAMETER Scope
    Specifies whether to check 'Applications', 'ServicePrincipals', or 'All'. Default is 'All'.

    .EXAMPLE
    Get-GTExpiringSecrets -DaysUntilExpiry 30
    Finds all credentials expiring in the next 30 days.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 3650)]
        [int]$DaysUntilExpiry,

        [ValidateSet('All', 'Applications', 'ServicePrincipals')]
        [string]$Scope = 'All'
    )

    begin
    {
        $modules = @('Microsoft.Graph.Applications')
        Install-GTRequiredModule -ModuleNames $modules -Verbose

        $requiredScopes = @('Application.Read.All')
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet))
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }
    }

    process
    {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
        
        # 2. Date Math (Must be UTC)
        $now = Get-UTCTime
        $expiryThreshold = $now.AddDays($DaysUntilExpiry)

        # --- Helper Logic to Avoid Duplication ---
        $ProcessCredentials = {
            param($ItemList, $ResourceType)

            foreach ($item in $ItemList)
            {
                # Process Secrets (PasswordCredentials)
                foreach ($cred in $item.PasswordCredentials)
                {
                    if ($cred.EndDateTime -and $cred.EndDateTime -le $expiryThreshold -and $cred.EndDateTime -ge $now)
                    {
                        # Use TotalDays and round up so partial days count as a day remaining
                        $daysRemaining = [math]::Ceiling((New-TimeSpan -Start $now -End $cred.EndDateTime).TotalDays)
                        $results.Add([PSCustomObject]@{
                                Name           = $item.DisplayName
                                AppId          = $item.AppId
                                Id             = $item.Id
                                ResourceType   = $ResourceType
                                CredentialType = 'Secret'
                                KeyId          = $cred.KeyId
                                Hint           = $cred.Hint # Useful to identify which secret it is
                                ExpiryDate     = $cred.EndDateTime
                                DaysRemaining  = $daysRemaining
                            })
                    }
                }

                # Process Certificates (KeyCredentials)
                foreach ($cred in $item.KeyCredentials)
                {
                    if ($cred.EndDateTime -and $cred.EndDateTime -le $expiryThreshold -and $cred.EndDateTime -ge $now)
                    {
                        $daysRemaining = [math]::Ceiling((New-TimeSpan -Start $now -End $cred.EndDateTime).TotalDays)
                        $results.Add([PSCustomObject]@{
                                Name           = $item.DisplayName
                                AppId          = $item.AppId
                                Id             = $item.Id
                                ResourceType   = $ResourceType
                                CredentialType = 'Certificate'
                                KeyId          = $cred.KeyId
                                Hint           = $null # Certs don't have hints, usually thumbprint is in customKeyIdentifier
                                ExpiryDate     = $cred.EndDateTime
                                DaysRemaining  = $daysRemaining
                            })
                    }
                }
            }
        }

        try
        {
            # 3. Scan Applications
            if ($Scope -in 'All', 'Applications')
            {
                Write-PSFMessage -Level Verbose -Message "Scanning Applications..."
                # Optimization: Select only needed properties to reduce bandwidth
                $apps = Get-MgBetaApplication -All -Property Id, AppId, DisplayName, KeyCredentials, PasswordCredentials -ErrorAction Stop
                & $ProcessCredentials -ItemList $apps -ResourceType 'Application'
            }

            # 4. Scan Service Principals
            if ($Scope -in 'All', 'ServicePrincipals')
            {
                Write-PSFMessage -Level Verbose -Message "Scanning Service Principals..."
                $sps = Get-MgBetaServicePrincipal -All -Property Id, AppId, DisplayName, KeyCredentials, PasswordCredentials -ErrorAction Stop
                & $ProcessCredentials -ItemList $sps -ResourceType 'ServicePrincipal'
            }

            # Return a plain array so PowerShell pipelines enumerate results predictably
            return $results.ToArray()
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'Secret Scan'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve expiring secrets: $($err.Reason)"
        }
    }
}

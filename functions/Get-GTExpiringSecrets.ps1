function Get-GTExpiringSecrets {
    <#
    .SYNOPSIS
    Retrieves Applications and Service Principals with secrets or certificates expiring within a specified timeframe.

    .DESCRIPTION
    This function scans all Applications and Service Principals in the directory and identifies those
    with credentials (secrets or certificates) that are set to expire within the specified number of days.

    .PARAMETER DaysUntilExpiry
    The number of days to look ahead for expiration.

    .PARAMETER Scope
    Specifies whether to check 'Applications', 'ServicePrincipals', or 'All'. Default is 'All'.

    .EXAMPLE
    Get-GTExpiringSecrets -DaysUntilExpiry 30
    Finds all credentials expiring in the next 30 days.

    .NOTES
    Requires Microsoft Graph PowerShell SDK with Application.Read.All permission.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$DaysUntilExpiry,

        [ValidateSet('All', 'Applications', 'ServicePrincipals')]
        [string]$Scope = 'All'
    )

    begin {
        $modules = @('Microsoft.Graph.Applications')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        if (-not (Initialize-GTGraphConnection -Scopes 'Application.Read.All')) {
            Write-Error "Failed to initialize Microsoft Graph connection."
            return
        }
    }

    process {
        try {
            $results = [System.Collections.Generic.List[PSCustomObject]]::new()
            $expiryThreshold = (Get-Date).AddDays($DaysUntilExpiry)
            $now = Get-Date

            if ($Scope -in 'All', 'Applications') {
                Write-PSFMessage -Level Verbose -Message "Scanning Applications..."
                $apps = Get-MgBetaApplication -All -Property Id, AppId, DisplayName, KeyCredentials, PasswordCredentials -ErrorAction Stop
                
                foreach ($app in $apps) {
                    # Check Password Credentials
                    foreach ($cred in $app.PasswordCredentials) {
                        if ($cred.EndDateTime -and $cred.EndDateTime -le $expiryThreshold -and $cred.EndDateTime -ge $now) {
                            $results.Add([PSCustomObject]@{
                                    Name           = $app.DisplayName
                                    AppId          = $app.AppId
                                    Type           = 'Application'
                                    CredentialType = 'Secret'
                                    KeyId          = $cred.KeyId
                                    ExpiryDate     = $cred.EndDateTime
                                    DaysRemaining  = (New-TimeSpan -Start $now -End $cred.EndDateTime).Days
                                })
                        }
                    }

                    # Check Key Credentials (Certificates)
                    foreach ($cred in $app.KeyCredentials) {
                        if ($cred.EndDateTime -and $cred.EndDateTime -le $expiryThreshold -and $cred.EndDateTime -ge $now) {
                            $results.Add([PSCustomObject]@{
                                    Name           = $app.DisplayName
                                    AppId          = $app.AppId
                                    Type           = 'Application'
                                    CredentialType = 'Certificate'
                                    KeyId          = $cred.KeyId
                                    ExpiryDate     = $cred.EndDateTime
                                    DaysRemaining  = (New-TimeSpan -Start $now -End $cred.EndDateTime).Days
                                })
                        }
                    }
                }
            }

            if ($Scope -in 'All', 'ServicePrincipals') {
                Write-PSFMessage -Level Verbose -Message "Scanning Service Principals..."
                $sps = Get-MgBetaServicePrincipal -All -Property Id, AppId, DisplayName, KeyCredentials, PasswordCredentials -ErrorAction Stop
                
                foreach ($sp in $sps) {
                    # Check Password Credentials
                    foreach ($cred in $sp.PasswordCredentials) {
                        if ($cred.EndDateTime -and $cred.EndDateTime -le $expiryThreshold -and $cred.EndDateTime -ge $now) {
                            $results.Add([PSCustomObject]@{
                                    Name           = $sp.DisplayName
                                    AppId          = $sp.AppId
                                    Type           = 'ServicePrincipal'
                                    CredentialType = 'Secret'
                                    KeyId          = $cred.KeyId
                                    ExpiryDate     = $cred.EndDateTime
                                    DaysRemaining  = (New-TimeSpan -Start $now -End $cred.EndDateTime).Days
                                })
                        }
                    }

                    # Check Key Credentials (Certificates)
                    foreach ($cred in $sp.KeyCredentials) {
                        if ($cred.EndDateTime -and $cred.EndDateTime -le $expiryThreshold -and $cred.EndDateTime -ge $now) {
                            $results.Add([PSCustomObject]@{
                                    Name           = $sp.DisplayName
                                    AppId          = $sp.AppId
                                    Type           = 'ServicePrincipal'
                                    CredentialType = 'Certificate'
                                    KeyId          = $cred.KeyId
                                    ExpiryDate     = $cred.EndDateTime
                                    DaysRemaining  = (New-TimeSpan -Start $now -End $cred.EndDateTime).Days
                                })
                        }
                    }
                }
            }

            return $results
        }
        catch {
            Stop-PSFFunction -Message "Failed to retrieve expiring secrets: $($_.Exception.Message)" -ErrorRecord $_ -EnableException $true
        }
    }
}

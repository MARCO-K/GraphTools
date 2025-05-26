function Get-GTServicePrincipalReport
{
    <#
    .SYNOPSIS
    Retrieves a report of Service Principals from Microsoft Entra ID.

    .DESCRIPTION
    Connects to Microsoft Graph to fetch all Service Principals and reports key details
    including App ID, owners, sign-in activity, and credential expiry dates.

    .EXAMPLE
    Get-GTServicePrincipalReport -Verbose
    Retrieves a report for all Service Principals with verbose logging.

    .NOTES
    Requires Microsoft Graph PowerShell SDK with appropriate permissions:
    - Application.Read.All (to read service principals and their properties)
    - Directory.Read.All (for expanding owner information)
    - AuditLog.Read.All (for sign-in activity)
    Ensure the GraphTools module's internal functions like Install-GTRequiredModule are available.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        # Switch to force a new Graph session
        [switch]$NewSession,

        # Scopes for Graph Connection
        [string[]]$Scope = @('Application.Read.All', 'Directory.Read.All', 'AuditLog.Read.All')
    )

    begin
    {
        # Module Management
        $requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Applications') # Corrected: Get-MgBetaServicePrincipal is in Microsoft.Graph.Beta.Applications
        Install-GTRequiredModule -ModuleNames $requiredModules -Verbose:$VerbosePreference

        # Graph Connection Handling
        try
        {
            if ($NewSession) 
            { 
                Write-PSFMessage -Level 'Verbose' -Message 'Closing existing Microsoft Graph session.'
                Disconnect-MgGraph -ErrorAction SilentlyContinue 
            }
            
            $context = Get-MgContext
            if (-not $context)
            {
                Write-PSFMessage -Level 'Verbose' -Message 'No Microsoft Graph context found. Attempting to connect.'
                Connect-MgGraph -Scopes $Scope -NoWelcome -ErrorAction Stop
            }
        }
        catch
        {
            Write-PSFMessage -Level 'Error' -Message "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
            throw "Graph connection failed: $_" # Re-throw to stop execution
        }
    }

    process
    {
        try
        {
            Write-PSFMessage -Level Verbose -Message "Fetching Service Principals from Microsoft Graph..."
            $servicePrincipals = Get-MgBetaServicePrincipal -All -Property ('id,appId,displayName,servicePrincipalType,accountEnabled,signInActivity,keyCredentials,passwordCredentials') -ExpandProperty 'owners' -ErrorAction Stop
        }
        catch
        {
            Stop-PSFFunction -Message "Failed to retrieve Service Principals: $($_.Exception.Message)" -ErrorRecord $_ -EnableException $true
            return # Exit if fetching fails
        }

        Write-PSFMessage -Level Debug -Message "Processing $($servicePrincipals.Count) Service Principals."
        
        $report = foreach ($sp in $servicePrincipals)
        {
            $lastSignInDateTime = $sp.SignInActivity.LastSignInDateTime
            $lastSignInRequestId = $sp.SignInActivity.LastSignInRequestId # Useful for audit correlation

            $ownerDisplayNames = @()
            if ($sp.Owners)
            {
                $ownerDisplayNames = $sp.Owners | ForEach-Object { $_.AdditionalProperties['displayName'] } # owners expanded might not have displayName directly
            }

            $keyCredentialExpiryDates = $sp.KeyCredentials | ForEach-Object { $_.EndDateTime }
            $passwordCredentialExpiryDates = $sp.PasswordCredentials | ForEach-Object { $_.EndDateTime }

            [PSCustomObject]@{
                DisplayName                   = $sp.DisplayName
                ObjectId                      = $sp.Id
                AppId                         = $sp.AppId
                ServicePrincipalType          = $sp.ServicePrincipalType
                AccountEnabled                = $sp.AccountEnabled
                LastSignInDateTime            = $lastSignInDateTime
                LastSignInRequestId           = $lastSignInRequestId
                OwnerDisplayNames             = $ownerDisplayNames -join '; '
                KeyCredentialExpiryDates      = $keyCredentialExpiryDates | Sort-Object | ForEach-Object { $_.ToString('yyyy-MM-dd HH:mm:ss') }
                PasswordCredentialExpiryDates = $passwordCredentialExpiryDates | Sort-Object | ForEach-Object { $_.ToString('yyyy-MM-dd HH:mm:ss') }
                KeyCredentialsCount           = $sp.KeyCredentials.Count
                PasswordCredentialsCount      = $sp.PasswordCredentials.Count
            }
        }

        Write-PSFMessage -Level Verbose -Message "Successfully processed $($report.Count) Service Principals."
        return $report
    }

    end
    {
        # No specific end processing needed for this function
    }
}

function Get-GTServicePrincipalReport
{
    <#
    .SYNOPSIS
    Retrieves a report of Service Principals from Microsoft Entra ID.

    .DESCRIPTION
    Connects to Microsoft Graph to fetch all Service Principals or a filtered subset
    and reports key details including App ID, owners, sign-in activity, and credential expiry dates.
    Supports pipeline input for AppId and DisplayName.

    .PARAMETER AppId
    The Application (client) ID of the service principal to retrieve. Can be provided via pipeline.

    .PARAMETER DisplayName
    The display name of the service principal to retrieve. Can be provided via pipeline.

    .EXAMPLE
    Get-GTServicePrincipalReport -Verbose
    Retrieves a report for all Service Principals with verbose logging.

    .EXAMPLE
    "d4a2b2b2-2b2b-4b2b-8b2b-2b2b2b2b2b2b" | Get-GTServicePrincipalReport
    Retrieves the service principal with the specified App ID.

    .EXAMPLE
    "My App", "Another App" | Get-GTServicePrincipalReport -DisplayName
    Retrieves the service principals with the specified display names.

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
        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'ByAppId')]
        [string[]]$AppId,

        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'ByDisplayName')]
        [string[]]$DisplayName,

        # Switch to force a new Graph session
        [switch]$NewSession,

        # Scopes for Graph Connection
        [string[]]$Scope = @('Application.Read.All', 'Directory.Read.All', 'AuditLog.Read.All')
    )

    begin
    {
        $appIdList = [System.Collections.Generic.List[string]]::new()
        $displayNameList = [System.Collections.Generic.List[string]]::new()

        # Module Management
        $requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Applications') # Confirm module location for your SDK version
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
        if ($AppId) {
            $appIdList.AddRange($AppId)
        }
        if ($DisplayName) {
            $displayNameList.AddRange($DisplayName)
        }
    }

    end
    {
        try
        {
            # Build safe filters: escape single quotes and prepare both an 'in' filter and an OR-based fallback
            $filter = $null
            $fallbackFilter = $null

            if ($appIdList.Count -gt 0) {
                $safeAppIds = $appIdList | ForEach-Object { ($_ -replace "'", "''") }
                # Prefer 'in' for readability; not all endpoints support it, so prepare an OR-based fallback
                $inFilter = "appId in ('" + ($safeAppIds -join "','") + "')"
                $orFilter = ($safeAppIds | ForEach-Object { "appId eq '$_'" }) -join ' or '
                $filter = $inFilter
                $fallbackFilter = $orFilter
            }
            elseif ($displayNameList.Count -gt 0) {
                $safeNames = $displayNameList | ForEach-Object { ($_ -replace "'", "''") }
                $inFilter = "displayName in ('" + ($safeNames -join "','") + "')"
                $orFilter = ($safeNames | ForEach-Object { "displayName eq '$_'" }) -join ' or '
                $filter = $inFilter
                $fallbackFilter = $orFilter
            }

            # Properties to request (keep minimal by default)
            $properties = 'id,appId,displayName,servicePrincipalType,accountEnabled,signInActivity,keyCredentials,passwordCredentials'
            $expand = @('owners')  # expand owners when available

            if ($filter) {
                Write-PSFMessage -Level Verbose -Message "Fetching Service Principals from Microsoft Graph with filter: $filter"
                try {
                    # request all pages when filtering
                    $servicePrincipals = Get-MgBetaServicePrincipal -Filter $filter -All -Property $properties -ExpandProperty $expand -ErrorAction Stop
                }
                catch {
                    # If Graph rejects the 'in' operator or the filter, retry with OR-based filter
                    $errMsg = $_.Exception.Message
                    if ($fallbackFilter -and ($errMsg -match 'Invalid|unsupported|not supported|Bad Request|400')) {
                        Write-PSFMessage -Level Warning -Message "Graph rejected the 'in' filter. Retrying with OR-based filter."
                        try {
                            $servicePrincipals = Get-MgBetaServicePrincipal -Filter $fallbackFilter -All -Property $properties -ExpandProperty $expand -ErrorAction Stop
                        }
                        catch {
                            Stop-PSFFunction -Message "Failed to retrieve Service Principals (after fallback): $($_.Exception.Message)" -ErrorRecord $_ -EnableException $true
                            return
                        }
                    }
                    else {
                        Stop-PSFFunction -Message "Failed to retrieve Service Principals: $errMsg" -ErrorRecord $_ -EnableException $true
                        return
                    }
                }
            } else {
                Write-PSFMessage -Level Verbose -Message "Fetching all Service Principals from Microsoft Graph..."
                $servicePrincipals = Get-MgBetaServicePrincipal -All -Property $properties -ExpandProperty $expand -ErrorAction Stop
            }
        }
        catch
        {
            Stop-PSFFunction -Message "Failed to retrieve Service Principals: $($_.Exception.Message)" -ErrorRecord $_ -EnableException $true
            return # Exit if fetching fails
        }

        Write-PSFMessage -Level Debug -Message "Processing $($servicePrincipals.Count) Service Principals."
        
        $report = foreach ($sp in $servicePrincipals)
        {
            # Null-safe sign-in activity
            $lastSignInDateTime = $null
            $lastSignInRequestId = $null
            if ($sp.SignInActivity) {
                $lastSignInDateTime = $sp.SignInActivity.LastSignInDateTime
                $lastSignInRequestId = $sp.SignInActivity.LastSignInRequestId
            }

            $ownerDisplayNames = @()
            if ($sp.Owners) {
                # owners expanded might provide AdditionalProperties or direct properties
                $ownerDisplayNames = $sp.Owners | ForEach-Object {
                    if ($_.AdditionalProperties.ContainsKey('displayName')) { $_.AdditionalProperties['displayName'] }
                    elseif ($_.DisplayName) { $_.DisplayName }
                    else { $null }
                } | Where-Object { $_ }
            }

            $keyCredentialExpiryDates = @()
            if ($sp.KeyCredentials) {
                $keyCredentialExpiryDates = $sp.KeyCredentials | ForEach-Object { if ($_.EndDateTime) { [datetime]$_.EndDateTime } } | Where-Object { $_ }
            }
            $passwordCredentialExpiryDates = @()
            if ($sp.PasswordCredentials) {
                $passwordCredentialExpiryDates = $sp.PasswordCredentials | ForEach-Object { if ($_.EndDateTime) { [datetime]$_.EndDateTime } } | Where-Object { $_ }
            }

            [PSCustomObject]@{
                DisplayName                   = $sp.DisplayName
                ObjectId                      = $sp.Id
                AppId                         = $sp.AppId
                ServicePrincipalType          = $sp.ServicePrincipalType
                AccountEnabled                = $sp.AccountEnabled
                LastSignInDateTime            = $lastSignInDateTime
                LastSignInRequestId           = $lastSignInRequestId
                OwnerDisplayNames             = ($ownerDisplayNames -join '; ')
                KeyCredentialExpiryDates      = ($keyCredentialExpiryDates | Sort-Object) | ForEach-Object { $_.ToString('yyyy-MM-dd HH:mm:ss') }
                PasswordCredentialExpiryDates = ($passwordCredentialExpiryDates | Sort-Object) | ForEach-Object { $_.ToString('yyyy-MM-dd HH:mm:ss') }
                KeyCredentialsCount           = ($sp.KeyCredentials | Measure-Object).Count
                PasswordCredentialsCount      = ($sp.PasswordCredentials | Measure-Object).Count
            }
        }

        Write-PSFMessage -Level Verbose -Message "Successfully processed $($report.Count) Service Principals."
        return $report
    }
}
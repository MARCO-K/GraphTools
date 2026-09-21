function Get-GTServicePrincipalReport
{
    <#
    .SYNOPSIS
    Retrieves a report of Service Principals from Microsoft Entra ID.

    .DESCRIPTION
    Connects to Microsoft Graph to fetch all Service Principals or a filtered subset.
    Reports key details including App ID, owners, sign-in activity, and credential expiry dates.
    
    PERFORMANCE:
    - Uses Server-Side filtering for AppId/DisplayName lookups.
    - Streams output to the pipeline for memory efficiency.

    .PARAMETER AppId
    The Application (client) ID of the service principal to retrieve.

    .PARAMETER DisplayName
    The display name of the service principal to retrieve.

    .EXAMPLE
    Get-GTServicePrincipalReport -Verbose
    Retrieves a report for all Service Principals.

    .EXAMPLE
    "d4a2b2b2-2b2b-4b2b-8b2b-2b2b2b2b2b2b" | Get-GTServicePrincipalReport
    Retrieves specific SP by App ID.
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'ByAppId')]
        [string[]]$AppId,

        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'ByDisplayName')]
        [string[]]$DisplayName,

        [switch]$IncludeSignInActivity,
        [switch]$IncludeCredentials,
        [switch]$ExpandOwners,
        [switch]$NewSession
    )

    begin
    {
        $appIdList = [System.Collections.Generic.List[string]]::new()
        $displayNameList = [System.Collections.Generic.List[string]]::new()

        # Module Management
        $requiredModules = @('Microsoft.Graph.Authentication')
        Install-GTRequiredModule -ModuleNames $requiredModules -Verbose:$VerbosePreference

        # 1. Scopes Definition
        $requiredScopes = [System.Collections.Generic.List[string]]::new()
        $requiredScopes.Add('Application.Read.All')
        if ($ExpandOwners) { $requiredScopes.Add('Directory.Read.All') }
        if ($IncludeSignInActivity) { $requiredScopes.Add('AuditLog.Read.All') }

        # 2. Scopes Check (Gold Standard)
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet))
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }

        # 3. Connection Initialization
        if (-not (Initialize-GTGraphConnection -Scopes $requiredScopes -NewSession:$NewSession))
        {
            Write-Error "Failed to initialize session."
            return
        }
    }

    process
    {
        # Collect pipeline input
        if ($AppId) { $appIdList.AddRange($AppId) }
        if ($DisplayName) { $displayNameList.AddRange($DisplayName) }
    }

    end
    {
        try
        {
            # --- Build Dynamic Filters ---
            $filter = $null
            $fallbackFilter = $null

            if ($appIdList.Count -gt 0)
            {
                $safeAppIds = $appIdList | ForEach-Object { ($_ -replace "'", "''") }
                # 'IN' filter (Preferred)
                $filter = "appId in ('" + ($safeAppIds -join "','") + "')"
                # 'OR' filter (Fallback)
                $fallbackFilter = ($safeAppIds | ForEach-Object { "appId eq '$_'" }) -join ' or '
            }
            elseif ($displayNameList.Count -gt 0)
            {
                $safeNames = $displayNameList | ForEach-Object { ($_ -replace "'", "''") }
                $filter = "displayName in ('" + ($safeNames -join "','") + "')"
                $fallbackFilter = ($safeNames | ForEach-Object { "displayName eq '$_'" }) -join ' or '
            }

            # --- Build Properties & Expand ---
            $properties = [System.Collections.Generic.List[string]]::new(@('id', 'appId', 'displayName', 'servicePrincipalType', 'accountEnabled'))
            $expand = [System.Collections.Generic.List[string]]::new()

            if ($IncludeSignInActivity) { $properties.Add('signInActivity') }
            if ($IncludeCredentials) { $properties.AddRange([string[]]@('keyCredentials', 'passwordCredentials')) }
            if ($ExpandOwners) { $expand.Add('owners') }

            # --- Build URI ---
            # signInActivity requires beta endpoint; v1.0 used otherwise
            $apiVersion = if ($IncludeSignInActivity) { 'beta' } else { 'v1.0' }
            $selectStr = $properties -join ','
            $expandStr = if ($expand.Count -gt 0) { "&`$expand=$($expand -join ',')" } else { '' }

            $baseUri = "$apiVersion/servicePrincipals?`$select=$selectStr$expandStr"

            # --- Execute Query ---
            $sps = if ($filter)
            {
                Write-PSFMessage -Level Verbose -Message "Fetching Service Principals with filter: $filter"
                try
                {
                    Invoke-GTGraphPagedRequest -Uri "$baseUri&`$filter=$([Uri]::EscapeDataString($filter))" -Headers @{ ConsistencyLevel = 'eventual' }
                }
                catch
                {
                    $errMsg = $_.Exception.Message
                    if ($fallbackFilter -and ($errMsg -match 'Invalid|unsupported|not supported|Bad Request|400'))
                    {
                        Write-PSFMessage -Level Warning -Message "Graph rejected 'IN' filter. Retrying with 'OR' filter."
                        Invoke-GTGraphPagedRequest -Uri "$baseUri&`$filter=$([Uri]::EscapeDataString($fallbackFilter))"
                    }
                    else { throw $_ }
                }
            }
            else
            {
                Write-PSFMessage -Level Verbose -Message "Fetching ALL Service Principals..."
                Invoke-GTGraphPagedRequest -Uri $baseUri
            }

            # --- Process & Output ---
            foreach ($sp in $sps)
            {
                
                $reportObject = [ordered]@{
                    DisplayName          = $sp.displayName
                    ObjectId             = $sp.id
                    AppId                = $sp.appId
                    ServicePrincipalType = $sp.servicePrincipalType
                    AccountEnabled       = $sp.accountEnabled
                }

                if ($IncludeSignInActivity)
                {
                    $reportObject['LastSignInDateTime'] = if ($sp.signInActivity) { $sp.signInActivity.lastSignInDateTime } else { $null }
                    $reportObject['LastSignInRequestId'] = if ($sp.signInActivity) { $sp.signInActivity.lastSignInRequestId } else { $null }
                }

                if ($ExpandOwners)
                {
                    $ownerDisplayNames = @()
                    if ($sp.owners)
                    {
                        $ownerDisplayNames = $sp.owners | ForEach-Object {
                            if ($_.displayName) { $_.displayName } else { 'Unknown' }
                        }
                    }
                    $reportObject['OwnerDisplayNames'] = $ownerDisplayNames -join '; '
                }

                if ($IncludeCredentials)
                {
                    $reportObject['KeyCredentialsCount'] = if ($sp.keyCredentials) { $sp.keyCredentials.Count } else { 0 }
                    $reportObject['PasswordCredentialsCount'] = if ($sp.passwordCredentials) { $sp.passwordCredentials.Count } else { 0 }
                    
                    $reportObject['KeyCredentialExpiryDates'] = if ($sp.keyCredentials) { 
                        ($sp.keyCredentials | ForEach-Object { $_.endDateTime } | Where-Object { $_ } | Sort-Object | ForEach-Object { ([datetime]$_).ToString('yyyy-MM-ddTHH:mm:ssZ') }) -join '; ' 
                    } else { $null }
                    
                    $reportObject['PasswordCredentialExpiryDates'] = if ($sp.passwordCredentials) { 
                        ($sp.passwordCredentials | ForEach-Object { $_.endDateTime } | Where-Object { $_ } | Sort-Object | ForEach-Object { ([datetime]$_).ToString('yyyy-MM-ddTHH:mm:ssZ') }) -join '; ' 
                    } else { $null }
                }

                # Output immediately to pipeline
                [PSCustomObject]$reportObject
            }
        }
        catch
        {
            # Gold Standard Error Handling
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'resource'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve Service Principals: $($err.Reason)"
            
            throw $err.ErrorMessage
        }
    }
}

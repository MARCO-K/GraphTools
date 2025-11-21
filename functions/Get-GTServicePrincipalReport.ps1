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
        $requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Applications')
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
            # FIX: Initialize with empty constructor, then AddRange to avoid constructor overload errors
            $properties = [System.Collections.Generic.List[string]]::new()
            $properties.AddRange([string[]]@('id', 'appId', 'displayName', 'servicePrincipalType', 'accountEnabled'))
            
            $expand = [System.Collections.Generic.List[string]]::new()

            if ($IncludeSignInActivity) { $properties.Add('signInActivity') }
            if ($IncludeCredentials) { $properties.AddRange([string[]]@('keyCredentials', 'passwordCredentials')) }
            if ($ExpandOwners) { $expand.Add('owners') }

            $params = @{
                All         = $true
                Property    = $properties.ToArray()
                ErrorAction = 'Stop'
            }
            if ($expand.Count -gt 0) { $params['ExpandProperty'] = $expand }

            # --- Execute Query with Fallback Logic ---
            $ExecuteGraphQuery = {
                if ($filter)
                {
                    Write-PSFMessage -Level Verbose -Message "Fetching Service Principals with filter: $filter"
                    $params['Filter'] = $filter
                    try
                    {
                        Get-MgBetaServicePrincipal @params
                    }
                    catch
                    {
                        # Fallback logic for filters
                        $errMsg = $_.Exception.Message
                        if ($fallbackFilter -and ($errMsg -match 'Invalid|unsupported|not supported|Bad Request|400'))
                        {
                            Write-PSFMessage -Level Warning -Message "Graph rejected 'IN' filter. Retrying with 'OR' filter."
                            $params['Filter'] = $fallbackFilter
                            Get-MgBetaServicePrincipal @params
                        }
                        else
                        {
                            throw $_ 
                        }
                    }
                }
                else
                {
                    Write-PSFMessage -Level Verbose -Message "Fetching ALL Service Principals..."
                    Get-MgBetaServicePrincipal @params
                }
            }

            # --- Process & Stream Output ---
            & $ExecuteGraphQuery | ForEach-Object {
                $sp = $_
                
                $reportObject = [ordered]@{
                    DisplayName          = $sp.DisplayName
                    ObjectId             = $sp.Id
                    AppId                = $sp.AppId
                    ServicePrincipalType = $sp.ServicePrincipalType
                    AccountEnabled       = $sp.AccountEnabled
                }

                if ($IncludeSignInActivity)
                {
                    $reportObject['LastSignInDateTime'] = if ($sp.SignInActivity) { $sp.SignInActivity.LastSignInDateTime } else { $null }
                    $reportObject['LastSignInRequestId'] = if ($sp.SignInActivity) { $sp.SignInActivity.LastSignInRequestId } else { $null }
                }

                if ($ExpandOwners)
                {
                    $ownerDisplayNames = @()
                    if ($sp.Owners)
                    {
                        $ownerDisplayNames = $sp.Owners | ForEach-Object {
                            if ($_.AdditionalProperties -and $_.AdditionalProperties.ContainsKey('displayName')) { $_.AdditionalProperties['displayName'] }
                            elseif ($_.DisplayName) { $_.DisplayName }
                            else { "Unknown" }
                        }
                    }
                    $reportObject['OwnerDisplayNames'] = $ownerDisplayNames -join '; '
                }

                if ($IncludeCredentials)
                {
                    $reportObject['KeyCredentialsCount'] = if ($sp.KeyCredentials) { $sp.KeyCredentials.Count } else { 0 }
                    $reportObject['PasswordCredentialsCount'] = if ($sp.PasswordCredentials) { $sp.PasswordCredentials.Count } else { 0 }
                    
                    $reportObject['KeyCredentialExpiryDates'] = if ($sp.KeyCredentials)
                    { 
                        ($sp.KeyCredentials | Select-Object -ExpandProperty EndDateTime | Sort-Object | ForEach-Object { $_.ToString('yyyy-MM-ddTHH:mm:ssZ') }) -join '; ' 
                    }
                    else { $null }
                    
                    $reportObject['PasswordCredentialExpiryDates'] = if ($sp.PasswordCredentials)
                    { 
                        ($sp.PasswordCredentials | Select-Object -ExpandProperty EndDateTime | Sort-Object | ForEach-Object { $_.ToString('yyyy-MM-ddTHH:mm:ssZ') }) -join '; ' 
                    }
                    else { $null }
                }

                [PSCustomObject]$reportObject
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
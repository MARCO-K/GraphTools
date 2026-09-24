function Invoke-GTGraphRequest
{
    <#
    .SYNOPSIS
        Executes a Microsoft Graph REST request with automatic token injection, pagination, and retry logic.

    .DESCRIPTION
        Zero-dependency REST invoker for Microsoft Graph API. Handles:
        - Automatic Bearer token resolution via Get-GTCachedGraphToken
        - Transparent URL normalization (relative to full endpoint URI)
        - Header management (ConsistencyLevel, client-request-id)
        - Resilient retry on HTTP 429 (throttling) and HTTP 503 with Retry-After header evaluation and exponential backoff
        - Automatic pagination traversal via @odata.nextLink when -All is specified
        - Seamless error diagnostics integration via Get-GTGraphErrorDetails

    .PARAMETER Uri
        The Microsoft Graph API URI. Can be relative (e.g. 'v1.0/users', 'beta/servicePrincipals')
        or absolute (e.g. 'https://graph.microsoft.com/v1.0/users').

    .PARAMETER Method
        HTTP method: GET, POST, PATCH, PUT, DELETE. Defaults to 'GET'.

    .PARAMETER Body
        The payload to send. Can be a hashtable, PSCustomObject, array, or JSON string.

    .PARAMETER Headers
        Hashtable of additional or overriding HTTP headers.

    .PARAMETER ContentType
        The request Content-Type header. Defaults to 'application/json; charset=utf-8'.

    .PARAMETER All
        When specified, follows @odata.nextLink until exhausted and returns all accumulated items.

    .PARAMETER MaxRetries
        Maximum number of retries for transient errors (HTTP 429, 503). Defaults to 3.

    .PARAMETER RetryBaseDelaySeconds
        Base seconds used for exponential backoff calculations if Retry-After header is omitted. Defaults to 2.

    .PARAMETER Token
        Explicit Bearer token override. If omitted, uses Get-GTCachedGraphToken.

    .PARAMETER Raw
        When specified, returns the raw deserialized response object without unwrapping.

    .OUTPUTS
        System.Object, System.Object[]

    .EXAMPLE
        # Single GET request
        $user = Invoke-GTGraphRequest -Uri "v1.0/users/admin@contoso.com"

    .EXAMPLE
        # Paged collection with ConsistencyLevel
        $allUsers = Invoke-GTGraphRequest -Uri "v1.0/users?`$filter=accountEnabled eq true" -Headers @{ ConsistencyLevel = 'eventual' } -All

    .EXAMPLE
        # PATCH request
        Invoke-GTGraphRequest -Method PATCH -Uri "v1.0/users/user-id" -Body @{ accountEnabled = $false }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Uri,

        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string]$Method = 'GET',

        [object]$Body,

        [hashtable]$Headers,

        [string]$ContentType = 'application/json; charset=utf-8',

        [switch]$All,

        [int]$MaxRetries = 3,

        [int]$RetryBaseDelaySeconds = 2,

        [string]$Token,

        [switch]$Raw
    )

    # 1. Normalize target URI
    $normalizedUri = $Uri.Trim()
    if ($normalizedUri -notmatch '^https?://')
    {
        $normalizedUri = $normalizedUri.TrimStart('/')
        $normalizedUri = "https://graph.microsoft.com/$normalizedUri"
    }

    # 2. Acquire access token if not passed directly
    $authToken = $Token
    if ([string]::IsNullOrWhiteSpace($authToken))
    {
        $authToken = Get-GTCachedGraphToken
    }

    # 3. Assemble baseline request headers
    $requestHeaders = @{
        'Authorization'     = "Bearer $authToken"
        'client-request-id' = [Guid]::NewGuid().ToString()
        'Accept'            = 'application/json'
    }

    if ($Headers)
    {
        foreach ($key in $Headers.Keys)
        {
            $requestHeaders[$key] = $Headers[$key]
        }
    }

    # 4. Prepare payload
    $serializedBody = $null
    if ($null -ne $Body)
    {
        if ($Body -is [string])
        {
            $serializedBody = $Body
        }
        else
        {
            $serializedBody = $Body | ConvertTo-Json -Depth 10 -Compress
        }
    }

    # Helper: extract HTTP status code across PS 5.1 and PS 7+
    function Get-HttpStatusFromException($ex)
    {
        if ($ex.Response -and $ex.Response.StatusCode)
        {
            return [int]$ex.Response.StatusCode
        }
        if ($ex.InnerException -and $ex.InnerException.Response -and $ex.InnerException.Response.StatusCode)
        {
            return [int]$ex.InnerException.Response.StatusCode
        }
        if ($ex.Message -match '\b(400|401|403|404|429|500|502|503|504)\b')
        {
            return [int]$Matches[1]
        }
        return $null
    }

    # Helper: extract Retry-After seconds across PS 5.1 and PS 7+
    function Get-HttpRetryAfterSecond($ex)
    {
        try
        {
            $responseHeaders = $ex.Response.Headers
            if ($responseHeaders)
            {
                if ($responseHeaders['Retry-After'])
                {
                    $val = [string]($responseHeaders['Retry-After'])
                    if ($val -as [int])
                    {
                        return [int]$val
                    }
                }
                elseif ($responseHeaders.RetryAfter -and $responseHeaders.RetryAfter.Delta)
                {
                    return [int]$responseHeaders.RetryAfter.Delta.TotalSeconds
                }
            }
        }
        catch
        {
            Write-PSFMessage -Level Verbose -Message "Unable to parse Retry-After header: $_"
        }
        return $null
    }

    # 5. Execution and pagination loop
    $currentUri = $normalizedUri
    $accumulatedItems = [System.Collections.Generic.List[object]]::new()

    do
    {
        # Mid-pagination token renewal: refresh token if cached entry has reached the sliding expiration buffer
        if ([string]::IsNullOrWhiteSpace($Token))
        {
            $freshToken = Get-GTCachedGraphToken
            if ($freshToken -and $freshToken -ne $authToken)
            {
                $authToken = $freshToken
                $requestHeaders['Authorization'] = "Bearer $authToken"
            }
        }

        $attempt = 0
        $requestSucceeded = $false
        $response = $null

        while (-not $requestSucceeded -and $attempt -le $MaxRetries)
        {
            try
            {
                $restParams = @{
                    Method      = $Method
                    Uri         = $currentUri
                    Headers     = $requestHeaders
                    ErrorAction = 'Stop'
                }

                if ($null -ne $serializedBody -and $Method -ne 'GET')
                {
                    $restParams['Body']        = $serializedBody
                    $restParams['ContentType'] = $ContentType
                }

                $response = Invoke-RestMethod @restParams
                $requestSucceeded = $true
            }
            catch
            {
                $statusCode = Get-HttpStatusFromException $_.Exception
                if ($statusCode -in 429, 503 -and $attempt -lt $MaxRetries)
                {
                    $retryAfter = Get-HttpRetryAfterSecond $_.Exception
                    if (-not $retryAfter -or $retryAfter -le 0)
                    {
                        $retryAfter = [int]($RetryBaseDelaySeconds * [Math]::Pow(2, $attempt)) + (Get-Random -Minimum 1 -Maximum 3)
                    }

                    Write-PSFMessage -Level Warning -Message "HTTP $statusCode encountered calling '$currentUri'. Retrying after $retryAfter seconds (Attempt $($attempt + 1)/$MaxRetries)..."
                    Start-Sleep -Seconds $retryAfter
                    $attempt++
                }
                elseif ($statusCode -eq 401 -and [string]::IsNullOrWhiteSpace($Token) -and $attempt -lt $MaxRetries)
                {
                    # Mid-pagination or expired token recovery: force token refresh and retry
                    Write-PSFMessage -Level Warning -Message "HTTP 401 Unauthorized encountered calling '$currentUri'. Refreshing token and retrying (Attempt $($attempt + 1)/$MaxRetries)..."
                    $authToken = Get-GTCachedGraphToken -ForceRefresh
                    $requestHeaders['Authorization'] = "Bearer $authToken"
                    $attempt++
                }
                else
                {
                    $errDetails = Get-GTGraphErrorDetails -Exception $_.Exception -Context $currentUri
                    Write-PSFMessage -Level $errDetails.LogLevel -Message "Microsoft Graph request failed: $($errDetails.Reason)"
                    throw
                }
            }
        }

        # Return immediately if raw response requested or non-paged query
        if ($Raw -or -not $All)
        {
            return $response
        }

        # Accumulate paged items
        if ($response -and ($response.PSObject.Properties.Name -contains 'value'))
        {
            if ($null -ne $response.value)
            {
                foreach ($item in $response.value)
                {
                    [void]$accumulatedItems.Add($item)
                }
            }
        }
        elseif ($response -is [System.Collections.IEnumerable] -and -not ($response -is [string]))
        {
            foreach ($item in $response)
            {
                [void]$accumulatedItems.Add($item)
            }
        }
        else
        {
            if ($null -ne $response)
            {
                [void]$accumulatedItems.Add($response)
            }
        }

        # Check for next page link
        $nextLink = $null
        if ($response -and ($response.PSObject.Properties.Name -contains '@odata.nextLink'))
        {
            $nextLink = [string]$response.'@odata.nextLink'
        }

        $currentUri = $nextLink

    } while ($All -and -not [string]::IsNullOrWhiteSpace($currentUri))

    return [object[]]$accumulatedItems.ToArray()
}

function Invoke-GTGraphBatch
{
    <#
    .SYNOPSIS
        Executes Microsoft Graph JSON batch requests combining up to 20 subrequests per HTTP call.

    .DESCRIPTION
        Combines multiple Microsoft Graph API operations into a single HTTP POST request against /$batch.
        If more than 20 requests are provided, Invoke-GTGraphBatch automatically chunks them into slices
        of 20 (the Microsoft Graph limit) and aggregates all responses.

    .PARAMETER Requests
        An array of hashtables or PSCustomObjects representing individual requests.
        Each item should contain:
        - url    : The relative endpoint URL (e.g. '/users/id', '/groups')
        - method : (Optional) HTTP method: GET, POST, PATCH, PUT, DELETE. Defaults to 'GET'.
        - id     : (Optional) Unique identifier for the subrequest. Auto-generated if omitted.
        - body   : (Optional) Payload for POST/PATCH/PUT subrequests.
        - headers: (Optional) Hashtable of headers specific to this subrequest.

    .PARAMETER BatchSize
        Maximum subrequests per batch chunk. Defaults to 20 (Microsoft Graph maximum).

    .PARAMETER MaxSubrequestRetries
        Maximum number of retries for throttled or transient failed subrequests (HTTP 429, 503, 504). Defaults to 3.

    .PARAMETER RetryBaseDelaySeconds
        Base delay seconds for exponential backoff when subrequests omit the Retry-After header. Defaults to 2.

    .OUTPUTS
        [PSCustomObject[]]
        Array of response objects containing Id, Status, Headers, and Body.

    .EXAMPLE
        $requests = @(
            @{ url = '/users/AdeleV@sc3210.onmicrosoft.com' }
            @{ url = '/organization' }
            @{ url = '/groups' }
        )
        Invoke-GTGraphBatch -Requests $requests
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$Requests,

        [ValidateRange(1, 20)]
        [int]$BatchSize = 20,

        [int]$MaxSubrequestRetries = 3,

        [int]$RetryBaseDelaySeconds = 2
    )

    begin
    {
        $allRequests = [System.Collections.Generic.List[hashtable]]::new()
    }

    process
    {
        foreach ($req in $Requests)
        {
            if ($null -eq $req) { continue }

            $url = if ($req -is [hashtable] -and $req.ContainsKey('url')) { $req['url'] } else { $req.url }
            $method = if ($req -is [hashtable] -and $req.ContainsKey('method')) { $req['method'] } else { $req.method }
            $id = if ($req -is [hashtable] -and $req.ContainsKey('id')) { $req['id'] } else { $req.id }
            $body = if ($req -is [hashtable] -and $req.ContainsKey('body')) { $req['body'] } else { $req.body }
            $headers = if ($req -is [hashtable] -and $req.ContainsKey('headers')) { $req['headers'] } else { $req.headers }

            if ([string]::IsNullOrWhiteSpace($url))
            {
                throw "Each batch subrequest must specify a 'url'."
            }

            # Graph batch URLs must be relative and start with '/'
            $normalizedUrl = $url.Trim()
            if ($normalizedUrl -match '^https?://graph\.microsoft\.com/(?:v1\.0|beta)(/.*)$')
            {
                $normalizedUrl = $Matches[1]
            }
            elseif ($normalizedUrl -match '^(?:v1\.0|beta)(/.*)$')
            {
                $normalizedUrl = $Matches[1]
            }
            if (-not $normalizedUrl.StartsWith('/'))
            {
                $normalizedUrl = "/$normalizedUrl"
            }

            $subReq = @{
                id     = if (-not [string]::IsNullOrWhiteSpace($id)) { [string]$id } else { [Guid]::NewGuid().ToString() }
                method = if (-not [string]::IsNullOrWhiteSpace($method)) { [string]$method.ToUpperInvariant() } else { 'GET' }
                url    = $normalizedUrl
            }

            if ($null -ne $body)
            {
                $subReq['body'] = $body
            }

            if ($null -ne $headers)
            {
                $subReq['headers'] = $headers
            }

            [void]$allRequests.Add($subReq)
        }
    }

    end
    {
        if ($allRequests.Count -eq 0)
        {
            return [PSCustomObject[]]@()
        }

        $allResponses = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Chunk requests into batches of $BatchSize (max 20)
        for ($i = 0; $i -lt $allRequests.Count; $i += $BatchSize)
        {
            $count = [Math]::Min($BatchSize, $allRequests.Count - $i)
            $chunk = $allRequests.GetRange($i, $count)

            Write-PSFMessage -Level Verbose -Message "Executing batch request chunk ($($chunk.Count) subrequests)..."

            # Pending subrequests for this chunk
            $pendingRequests = [System.Collections.Generic.List[hashtable]]::new($chunk)
            # Storage for completed subrequest responses indexed by request id
            $chunkResponses = [System.Collections.Generic.Dictionary[string, PSCustomObject]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $subAttempt = 0

            while ($pendingRequests.Count -gt 0 -and $subAttempt -le $MaxSubrequestRetries)
            {
                $batchPayload = @{
                    requests = @($pendingRequests)
                }

                $batchResult = Invoke-GTGraphRequest -Uri 'v1.0/$batch' -Method POST -Body $batchPayload

                $retryRequests = [System.Collections.Generic.List[hashtable]]::new()
                $maxSubDelay = 0

                if ($batchResult -and $batchResult.responses)
                {
                    # Build lookup for quick access to returned responses by id
                    $returnedById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($resp in $batchResult.responses)
                    {
                        if ($null -ne $resp.id)
                        {
                            $returnedById[[string]$resp.id] = $resp
                        }
                    }

                    foreach ($req in $pendingRequests)
                    {
                        $reqId = [string]$req['id']
                        if ($returnedById.ContainsKey($reqId))
                        {
                            $resp = $returnedById[$reqId]
                            $statusCode = [int]$resp.status

                            # Check for transient subrequest throttling / outage
                            if ($statusCode -in 429, 503, 504 -and $subAttempt -lt $MaxSubrequestRetries)
                            {
                                [void]$retryRequests.Add($req)

                                # Parse Retry-After header from subrequest headers if present
                                $retryAfterSec = 0
                                if ($resp.headers)
                                {
                                    $headerVal = $null
                                    if ($resp.headers -is [hashtable])
                                    {
                                        foreach ($k in $resp.headers.Keys)
                                        {
                                            if ($k -like 'retry-after*')
                                            {
                                                $headerVal = [string]$resp.headers[$k]
                                                break
                                            }
                                        }
                                    }
                                    elseif ($resp.headers.PSObject -and $resp.headers.PSObject.Properties)
                                    {
                                        foreach ($p in $resp.headers.PSObject.Properties)
                                        {
                                            if ($p.Name -like 'retry-after*')
                                            {
                                                $headerVal = [string]$p.Value
                                                break
                                            }
                                        }
                                    }

                                    if ($headerVal)
                                    {
                                        $parsedInt = 0
                                        $parsedDate = [DateTime]::MinValue
                                        if ([int]::TryParse($headerVal, [ref]$parsedInt))
                                        {
                                            $retryAfterSec = $parsedInt
                                        }
                                        elseif ([DateTime]::TryParse($headerVal, [ref]$parsedDate))
                                        {
                                            $diff = $parsedDate.ToUniversalTime() - [DateTime]::UtcNow
                                            $retryAfterSec = [int][Math]::Max(1, $diff.TotalSeconds)
                                        }
                                    }
                                }

                                if ($retryAfterSec -gt $maxSubDelay)
                                {
                                    $maxSubDelay = $retryAfterSec
                                }
                            }
                            else
                            {
                                # Permanent response or retries exhausted
                                $chunkResponses[$reqId] = [PSCustomObject]@{
                                    PSTypeName = 'GraphTools.BatchResponse'
                                    Id         = $resp.id
                                    Status     = $statusCode
                                    Headers    = $resp.headers
                                    Body       = $resp.body
                                }
                            }
                        }
                        else
                        {
                            # Subrequest was missing from responses array (unexpected batch failure)
                            if ($subAttempt -lt $MaxSubrequestRetries)
                            {
                                [void]$retryRequests.Add($req)
                            }
                            else
                            {
                                $chunkResponses[$reqId] = [PSCustomObject]@{
                                    PSTypeName = 'GraphTools.BatchResponse'
                                    Id         = $reqId
                                    Status     = 500
                                    Headers    = $null
                                    Body       = @{
                                        error = @{
                                            code    = 'MissingBatchResponse'
                                            message = "Subrequest '$reqId' was missing from batch response."
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                else
                {
                    # No responses received at all
                    if ($subAttempt -lt $MaxSubrequestRetries)
                    {
                        $retryRequests = [System.Collections.Generic.List[hashtable]]::new($pendingRequests)
                    }
                    else
                    {
                        foreach ($req in $pendingRequests)
                        {
                            $reqId = [string]$req['id']
                            $chunkResponses[$reqId] = [PSCustomObject]@{
                                PSTypeName = 'GraphTools.BatchResponse'
                                Id         = $reqId
                                Status     = 500
                                Headers    = $null
                                Body       = @{
                                    error = @{
                                        code    = 'EmptyBatchResponse'
                                        message = 'Batch request returned empty response.'
                                    }
                                }
                            }
                        }
                    }
                }

                if ($retryRequests.Count -gt 0)
                {
                    $subAttempt++
                    if ($maxSubDelay -le 0)
                    {
                        $maxSubDelay = [int]($RetryBaseDelaySeconds * [Math]::Pow(2, $subAttempt - 1)) + (Get-Random -Minimum 1 -Maximum 3)
                    }

                    Write-PSFMessage -Level Warning -Message "Batch chunk contains $($retryRequests.Count) throttled subrequest(s). Retrying after $maxSubDelay seconds (Attempt $subAttempt/$MaxSubrequestRetries)..."
                    Start-Sleep -Seconds $maxSubDelay
                    $pendingRequests = $retryRequests
                }
                else
                {
                    $pendingRequests.Clear()
                }
            }

            # Add responses in original chunk sequence
            foreach ($req in $chunk)
            {
                $reqId = [string]$req['id']
                if ($chunkResponses.ContainsKey($reqId))
                {
                    [void]$allResponses.Add($chunkResponses[$reqId])
                }
            }
        }

        return [PSCustomObject[]]$allResponses.ToArray()
    }
}

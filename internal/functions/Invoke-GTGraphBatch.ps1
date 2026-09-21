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
        [int]$BatchSize = 20
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
            return @()
        }

        $allResponses = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Chunk requests into batches of $BatchSize (max 20)
        for ($i = 0; $i -lt $allRequests.Count; $i += $BatchSize)
        {
            $count = [Math]::Min($BatchSize, $allRequests.Count - $i)
            $chunk = $allRequests.GetRange($i, $count)

            Write-PSFMessage -Level Verbose -Message "Executing batch request chunk ($($chunk.Count) subrequests)..."

            $batchPayload = @{
                requests = @($chunk)
            }

            $batchResult = Invoke-GTGraphRequest -Uri 'v1.0/$batch' -Method POST -Body $batchPayload

            if ($batchResult -and $batchResult.responses)
            {
                foreach ($resp in $batchResult.responses)
                {
                    $entry = [PSCustomObject]@{
                        PSTypeName = 'GraphTools.BatchResponse'
                        Id         = $resp.id
                        Status     = [int]$resp.status
                        Headers    = $resp.headers
                        Body       = $resp.body
                    }
                    [void]$allResponses.Add($entry)
                }
            }
        }

        return [PSCustomObject[]]$allResponses.ToArray()
    }
}

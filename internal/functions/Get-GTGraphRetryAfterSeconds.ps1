function Get-GTGraphRetryAfterSeconds
{
    <#
    .SYNOPSIS
        Extracts and parses Retry-After delay seconds from HTTP response headers or exceptions.
    .DESCRIPTION
        Parses integer delay seconds, TimeSpan deltas, or RFC 1123 HTTP-date timestamps from response
        headers or exception objects across both single-request and batch execution engines.
    .PARAMETER Headers
        The response headers collection (hashtable, dictionary, or PSCustomObject).
    .PARAMETER Exception
        An exception object containing HTTP response headers.
    .OUTPUTS
        System.Nullable[int]
    .EXAMPLE
        $retryAfter = Get-GTGraphRetryAfterSeconds -Headers $resp.headers
    .EXAMPLE
        $retryAfter = Get-GTGraphRetryAfterSeconds -Exception $_.Exception
    #>
    [CmdletBinding(DefaultParameterSetName = 'Headers')]
    [OutputType([int])]
    param(
        [Parameter(ParameterSetName = 'Headers', Position = 0)]
        [object]$Headers,

        [Parameter(ParameterSetName = 'Exception', Position = 0)]
        [object]$Exception
    )

    $responseHeaders = $Headers
    if ($PSCmdlet.ParameterSetName -eq 'Exception' -and $Exception)
    {
        if ($Exception.Response -and $Exception.Response.Headers)
        {
            $responseHeaders = $Exception.Response.Headers
        }
        elseif ($Exception.InnerException -and $Exception.InnerException.Response -and $Exception.InnerException.Response.Headers)
        {
            $responseHeaders = $Exception.InnerException.Response.Headers
        }
    }

    if (-not $responseHeaders)
    {
        return $null
    }

    try
    {
        # 1. Delta TimeSpan support (HttpResponseHeaders.RetryAfter.Delta)
        if ($responseHeaders.RetryAfter -and $responseHeaders.RetryAfter.Delta)
        {
            return [int]$responseHeaders.RetryAfter.Delta.TotalSeconds
        }

        # 2. Extract header string value across Hashtable, Dictionary, or PSCustomObject
        $headerVal = $null
        if ($responseHeaders -is [System.Collections.IDictionary])
        {
            foreach ($key in $responseHeaders.Keys)
            {
                if ($key -like 'retry-after*')
                {
                    $headerVal = [string]$responseHeaders[$key]
                    break
                }
            }
        }
        elseif ($responseHeaders.PSObject -and $responseHeaders.PSObject.Properties)
        {
            foreach ($prop in $responseHeaders.PSObject.Properties)
            {
                if ($prop.Name -like 'retry-after*')
                {
                    $headerVal = [string]$prop.Value
                    break
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($headerVal))
        {
            $parsedInt = 0
            $parsedDate = [DateTime]::MinValue
            if ([int]::TryParse($headerVal, [ref]$parsedInt))
            {
                return $parsedInt
            }
            elseif ([DateTime]::TryParse($headerVal, [ref]$parsedDate))
            {
                $now = if (Get-Command -Name Get-UTCTime -ErrorAction SilentlyContinue) { Get-UTCTime } else { [DateTime]::UtcNow }
                $diff = $parsedDate.ToUniversalTime() - $now
                return [int][Math]::Max(1, $diff.TotalSeconds)
            }
        }
    }
    catch
    {
        Write-PSFMessage -Level Verbose -Message "Unable to parse Retry-After header: $_"
    }

    return $null
}

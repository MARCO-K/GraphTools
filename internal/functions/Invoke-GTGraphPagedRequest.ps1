function Invoke-GTGraphPagedRequest {
    <#
    .SYNOPSIS
    Executes a paged Microsoft Graph request and aggregates all items.

    .DESCRIPTION
    Calls Invoke-MgGraphRequest starting from the supplied URI and follows
    @odata.nextLink until exhausted. Supports both Graph envelope responses
    (with value) and enumerable payloads.

    .PARAMETER Uri
    Initial relative Microsoft Graph URI.

    .PARAMETER Headers
    Optional headers passed to Invoke-MgGraphRequest.

    .OUTPUTS
    System.Object[]
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [hashtable]$Headers
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $nextUri = $Uri

    while (-not [string]::IsNullOrWhiteSpace($nextUri)) {
        $requestParams = @{
            Method      = 'GET'
            Uri         = $nextUri
            ErrorAction = 'Stop'
        }
        if ($Headers) {
            $requestParams.Headers = $Headers
        }

        $response = Invoke-MgGraphRequest @requestParams

        if ($response -and ($response.PSObject.Properties.Name -contains 'value')) {
            foreach ($item in @($response.value)) {
                [void]$results.Add($item)
            }
        }
        elseif ($response -is [System.Collections.IEnumerable] -and -not ($response -is [string])) {
            foreach ($item in $response) {
                [void]$results.Add($item)
            }
        }

        $nextUri = $null
        if ($response -and ($response.PSObject.Properties.Name -contains '@odata.nextLink')) {
            $nextUri = [string]$response.'@odata.nextLink'
        }

        if (-not [string]::IsNullOrWhiteSpace($nextUri) -and $nextUri.StartsWith('https://graph.microsoft.com', [System.StringComparison]::OrdinalIgnoreCase)) {
            $nextUri = $nextUri.Substring('https://graph.microsoft.com'.Length)
        }
    }

    return $results.ToArray()
}

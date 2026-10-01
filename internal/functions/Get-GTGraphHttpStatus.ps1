function Get-GTGraphHttpStatus
{
    <#
    .SYNOPSIS
        Extracts the HTTP status code from an exception or response.
    .DESCRIPTION
        Inspects WebException, HttpRequestException, and Graph client exceptions to determine
        the integer HTTP status code across Windows PowerShell 5.1 and PowerShell 7+.
    .PARAMETER Exception
        The exception object to inspect.
    .OUTPUTS
        System.Nullable[int]
    .EXAMPLE
        $statusCode = Get-GTGraphHttpStatus -Exception $_.Exception
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$Exception
    )

    process
    {
        if ($null -eq $Exception)
        {
            return $null
        }

        if ($Exception.Response -and $Exception.Response.StatusCode)
        {
            try
            {
                return [int]$Exception.Response.StatusCode
            }
            catch
            {
                # Fallback to regex extraction if direct cast fails
                $null = $_
            }
        }
        if ($Exception.InnerException -and $Exception.InnerException.Response -and $Exception.InnerException.Response.StatusCode)
        {
            try
            {
                return [int]$Exception.InnerException.Response.StatusCode
            }
            catch
            {
                # Fallback to regex extraction if direct cast fails
                $null = $_
            }
        }

        $msg = $Exception.Message
        if ($msg -match '\b(400|401|403|404|429|500|502|503|504)\b')
        {
            return [int]$Matches[1]
        }
        if ($msg -imatch 'not found') { return 404 }
        if ($msg -imatch 'Insufficient privileges') { return 403 }
        if ($msg -imatch 'Unauthorized') { return 401 }
        if ($msg -imatch 'throttl') { return 429 }
        if ($msg -imatch 'Bad Request') { return 400 }

        return $null
    }
}

function Get-GTGraphErrorDetails
{
    <#
    .SYNOPSIS
    Parses Microsoft Graph API exception and extracts HTTP status code with user-friendly reason

    .DESCRIPTION
    Internal helper function that analyzes Graph SDK exceptions to extract HTTP status codes
    and compose user-friendly error messages. This function implements a centralized error
    parsing strategy to avoid code duplication across multiple cmdlets.

    The function attempts to extract status codes from:
    1. Exception.Response.StatusCode property
    2. Exception.InnerException.Response.StatusCode property
    3. Pattern matching in the error message text

    It then maps common HTTP status codes to user-friendly messages following security
    best practices (e.g., generic messages for 404/403 to prevent enumeration attacks).

    .PARAMETER Exception
    The exception object caught from a Graph API operation

    .PARAMETER Context
    Optional context string to include in log messages (e.g., user UPN, device name)

    .PARAMETER ResourceType
    Optional resource type string (e.g., 'user', 'device') to customize error messages

    .OUTPUTS
    PSCustomObject with the following properties:
    - HttpStatus      : Extracted HTTP status code (int or $null)
    - Reason          : User-friendly reason string
    - ErrorMessage    : Original exception message
    - LogLevel        : Recommended PSFramework log level ('Error', 'Warning', 'Debug')

    .EXAMPLE
    try {
        Update-MgBetaUser -UserId $userId -AccountEnabled $false
    }
    catch {
        $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'user'
        Write-PSFMessage -Level $errorDetails.LogLevel -Message "$userId - $($errorDetails.Reason)"
    }

    .NOTES
    This is an internal helper function not exported from the module.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Exception]$Exception,

        [Parameter()]
        [string]$Context = '',

        [Parameter()]
        [ValidateSet('user', 'device', 'resource')]
        [string]$ResourceType = 'resource'
    )

    $httpStatus = $null
    $errorMsg = $Exception.Message

    # Attempt to extract status code from common locations used by HTTP-based SDK exceptions
    if ($Exception.Response -and $Exception.Response.StatusCode) {
        try { $httpStatus = [int]$Exception.Response.StatusCode } catch {}
    }
    if (-not $httpStatus -and $Exception.InnerException.Response -and $Exception.InnerException.Response.StatusCode) {
        try { $httpStatus = [int]$Exception.InnerException.Response.StatusCode } catch {}
    }

    # Some SDKs surface status code as numeric string in the message; attempt pattern matching
    if (-not $httpStatus) {
        if ($errorMsg -imatch '\b404\b' -or $errorMsg -imatch 'not found') { $httpStatus = 404 }
        elseif ($errorMsg -imatch '\b403\b' -or $errorMsg -imatch 'Insufficient privileges') { $httpStatus = 403 }
        elseif ($errorMsg -imatch '\b429\b' -or $errorMsg -imatch 'throttl') { $httpStatus = 429 }
        elseif ($errorMsg -imatch '\b400\b' -or $errorMsg -imatch 'Bad Request') { $httpStatus = 400 }
    }

    # Compose a user-friendly reason and logging level based on status
    $reason = "Failed: $errorMsg"
    $logLevel = 'Error'

    switch ($httpStatus) {
        404 {
            # Security best practice: Use a generic error message for 404 and 403 to prevent enumeration.
            $reason = "Operation failed. The $ResourceType could not be processed."
            $logLevel = 'Error'
        }
        403 {
            # Security best practice: Use a generic error message for 404 and 403 to prevent enumeration.
            $reason = "Operation failed. The $ResourceType could not be processed."
            $logLevel = 'Error'
        }
        429 {
            $reason = 'Throttled by Graph API (429). Consider retrying after a delay or implementing exponential backoff.'
            $logLevel = 'Warning'
        }
        400 {
            $reason = "Bad request (400). $errorMsg"
            $logLevel = 'Error'
        }
        default {
            # For unrecognized status codes or no status code, keep the generic reason
            $logLevel = 'Error'
        }
    }

    # Return structured error details
    [PSCustomObject]@{
        HttpStatus   = $httpStatus
        Reason       = $reason
        ErrorMessage = $errorMsg
        LogLevel     = $logLevel
    }
}

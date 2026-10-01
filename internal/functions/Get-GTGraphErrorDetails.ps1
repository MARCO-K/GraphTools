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

    if (-not (Get-Command -Name Get-GTGraphHttpStatus -ErrorAction SilentlyContinue))
    {
        $statusHelper = Join-Path $PSScriptRoot 'Get-GTGraphHttpStatus.ps1'
        if (Test-Path $statusHelper) { . $statusHelper }
    }

    $httpStatus = Get-GTGraphHttpStatus -Exception $Exception
    $errorMsg = if ($Exception) { $Exception.Message } else { '' }

    # Compose a user-friendly reason and logging level based on status
    $reason = "Failed: $errorMsg"
    $logLevel = 'Error'

    switch ($httpStatus) {
        { $_ -in @(403, 404) } {
            # Security best practice: generic message for 403/404 to prevent enumeration.
            $reason = "Operation failed. The $ResourceType could not be processed."
            $logLevel = 'Error'
        }
        401 {
            $reason = 'Unauthorized (401). The token may be expired or missing required audience/scopes.'
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

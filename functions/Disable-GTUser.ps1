<#
.SYNOPSIS
    Disables user accounts in Microsoft Entra ID (Azure AD)
.DESCRIPTION
    Disables one or more user accounts by setting the AccountEnabled property to false.
    This function requires Microsoft.Graph.Authentication and Microsoft.Graph.Beta.Users modules.
    It validates UPN format and manages Microsoft Graph connection automatically.

    This cmdlet supports -WhatIf and -Confirm via ShouldProcess (SupportsShouldProcess = $true).
.PARAMETER UPN
    One or more User Principal Names (UPNs) to disable. Must be in valid email format.

    Aliases: UserPrincipalName, Users, User, UserName, UPNName
.PARAMETER Force
    Suppresses confirmation prompts and forces the disable operation. Use with caution in automation.

.OUTPUTS
    System.Object[]
    Returns a single array (emitted once in End) of PSCustomObjects, one per processed UPN with the following properties:
      - User            : The UPN that was processed
      - Status          : 'Disabled' | 'Skipped' | 'Failed'
      - TimeUtc         : ISO-8601 UTC timestamp of when the action completed/was skipped
      - HttpStatus      : HTTP status code detected from the Graph error (if applicable)
      - Reason          : Short human-readable reason or guidance
      - ExceptionMessage: Raw exception message (for troubleshooting)
.EXAMPLE
    Disable-GTUser -UPN 'user1@contoso.com'

    Disables a single user account using the UPN parameter.
.EXAMPLE
    Disable-GTUser -UserName 'user1@contoso.com'

    Disables a single user account using the UserName alias.
.EXAMPLE
    Disable-GTUser -UPN 'user1@contoso.com','user2@contoso.com'

    Disables multiple user accounts.
.EXAMPLE
    Disable-GTUser -Users 'user1@contoso.com','user2@contoso.com'

    Disables multiple user accounts using the Users alias.
.EXAMPLE
    $users | Disable-GTUser

    Disables users from pipeline input.
#>
Function Disable-GTUser
{
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([object[]])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateScript({$_ -match $script:GTValidationRegex.UPN})]
        [Alias('UserPrincipalName','Users','User','UserName','UPNName')]
        [string[]]$UPN,

        [Parameter()]
        [switch]$Force
    )

    begin
    {
        # Prepare a collection for results. We'll emit a single array in End().
        $results = New-Object System.Collections.ArrayList

        # Module Management
        $modules = ('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Users')
        Install-GTRequiredModule -ModuleNames $modules -Verbose

        # Graph Connection Handling
        $connectionResult = Initialize-GTGraphConnection -Scopes 'User.ReadWrite.All'
        if (-not $connectionResult) {
            Write-PSFMessage -Level Error -Message "Failed to initialize Microsoft Graph connection. Aborting user disable operation."
            return
        }
    }

    process
    {
        foreach ($User in $UPN)
        {
            # Describe the target and action for ShouldProcess
            $target = $User
            $action = "Disable user account (set AccountEnabled to False)"
            $timeUtc = (Get-Date).ToUniversalTime().ToString('o')

            try
            {
                if ($PSCmdlet.ShouldProcess($target, $action)) {
                    Update-MgBetaUser -UserId $User -AccountEnabled:$false -ErrorAction Stop
                    Write-PSFMessage -Level Verbose -Message "$User - Disable User Action - User Disabled"

                    $result = [PSCustomObject]@{
                        User            = $User
                        Status          = 'Disabled'
                        TimeUtc         = $timeUtc
                        HttpStatus      = $null  # No actual HTTP status available; indicates success
                        Reason          = 'User disabled'
                        ExceptionMessage= ''
                    }
                    [void]$results.Add($result)
                }
                else {
                    # When -WhatIf or user declines via -Confirm, operation is not performed.
                    Write-PSFMessage -Level Verbose -Message "$User - Disable User Action - Skipped (WhatIf/Confirmed=false)"

                    $result = [PSCustomObject]@{
                        User            = $User
                        Status          = 'Skipped'
                        TimeUtc         = $timeUtc
                        HttpStatus      = $null
                        Reason          = 'Operation skipped (WhatIf/confirmation declined)'
                        ExceptionMessage= ''
                    }
                    [void]$results.Add($result)
                }
            }
            catch
            {
                # Improved error handling: attempt to detect common HTTP status codes from the Graph SDK exception,
                # fall back to message pattern matching, then return a structured failure object.

                $ex = $_.Exception
                $httpStatus = $null
                $errorMsg = $ex.Message

                # Attempt to extract status code from common locations used by HTTP-based SDK exceptions
                if ($ex.Response -and $ex.Response.StatusCode) {
                    try { $httpStatus = [int]$ex.Response.StatusCode } catch {}
                }
                if (-not $httpStatus -and $ex.InnerException.Response -and $ex.InnerException.Response.StatusCode) {
                    try { $httpStatus = [int]$ex.InnerException.Response.StatusCode } catch {}
                }

                # Some SDKs surface status code as StatusCode, HttpStatusCode or numeric string in the message; attempt pattern matching
                if (-not $httpStatus) {
                    if ($errorMsg -match '\b404\b' -or $errorMsg -match 'not found') { $httpStatus = 404 }
                    elseif ($errorMsg -match '\b403\b' -or $errorMsg -match 'Insufficient privileges') { $httpStatus = 403 }
                    elseif ($errorMsg -match '\b429\b' -or $errorMsg -match 'throttl') { $httpStatus = 429 }
                    elseif ($errorMsg -match '\b400\b' -or $errorMsg -match 'Bad Request') { $httpStatus = 400 }
                }

                # Compose a user-friendly reason and logging level based on status
                $reason = "Failed: $errorMsg"
                switch ($httpStatus) {
                    404 {
                        $reason = 'User not found (404). Verify the UPN or object exists.'
                        Write-PSFMessage -Level Error -Message "$User - Disable User Action - $reason"
                    }
                    403 {
                        $reason = "Access denied (403). Ensure the account running this command has 'User.ReadWrite.All' permission and that consent has been granted."
                        Write-PSFMessage -Level Error -Message "$User - Disable User Action - $reason"
                    }
                    429 {
                        $reason = 'Throttled by Graph API (429). Consider retrying after a delay or implementing exponential backoff.'
                        Write-PSFMessage -Level Warning -Message "$User - Disable User Action - $reason"
                    }
                    400 {
                        $reason = "Bad request (400). $errorMsg"
                        Write-PSFMessage -Level Error -Message "$User - Disable User Action - $reason"
                    }
                    default {
                        Write-PSFMessage -Level Error -Message "$User - Disable User Action - Failed: $errorMsg"
                        Write-PSFMessage -Level Debug -Message ($ex | Out-String)
                    }
                }

                $result = [PSCustomObject]@{
                    User            = $User
                    Status          = 'Failed'
                    TimeUtc         = $timeUtc
                    HttpStatus      = $httpStatus
                    Reason          = $reason
                    ExceptionMessage= $errorMsg
                }
                [void]$results.Add($result)
            }
        }
    }

    end
    {
        # Emit a single array of all per-user result objects for easier consumption by callers/automation.
        # Use ToArray() so a true array is returned instead of an ArrayList to keep type expectations simple.
        if ($results.Count -gt 0) {
            Write-Output ($results.ToArray())
        }
        else {
            # No results (e.g., no input); return an empty array
            Write-Output @()
        }
    }
}
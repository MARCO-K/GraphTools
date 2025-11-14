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
                # Use centralized error handling helper to parse Graph API exceptions
                $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'user'

                # Log appropriate message based on error details
                if ($errorDetails.HttpStatus -in 404, 403) {
                    Write-PSFMessage -Level $errorDetails.LogLevel -Message "$User - Disable User Action - $($errorDetails.Reason)"
                    Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
                }
                elseif ($errorDetails.HttpStatus) {
                    Write-PSFMessage -Level $errorDetails.LogLevel -Message "$User - Disable User Action - $($errorDetails.Reason)"
                }
                else {
                    Write-PSFMessage -Level Error -Message "$User - Disable User Action - Failed: $($errorDetails.ErrorMessage)"
                    Write-PSFMessage -Level Debug -Message ($_.Exception | Out-String)
                }

                $result = [PSCustomObject]@{
                    User            = $User
                    Status          = 'Failed'
                    TimeUtc         = $timeUtc
                    HttpStatus      = $errorDetails.HttpStatus
                    Reason          = $errorDetails.Reason
                    ExceptionMessage= $errorDetails.ErrorMessage
                }
                [void]$results.Add($result)
            }
        }
    }

    end
    {
        # Emit a single array of all per-user result objects for easier consumption by callers/automation.
        # Use ToArray() so a true array is returned instead of an ArrayList to keep type expectations simple.
        ,$results.ToArray()
    }
}
<#
.SYNOPSIS
    Disables user accounts in Microsoft Entra ID (Azure AD).

.DESCRIPTION
    Disables one or more user accounts by setting the AccountEnabled property to false.
    This function requires Microsoft.Graph.Authentication and Microsoft.Graph.Beta.Users modules.
    It validates UPN format and manages Microsoft Graph connection automatically.

    This cmdlet supports -WhatIf and -Confirm via ShouldProcess.

.PARAMETER UPN
    One or more User Principal Names (UPNs) to disable. Must be in valid email format.
    Aliases: UserPrincipalName, Users, User, UserName, UPNName

.PARAMETER Force
    Suppresses confirmation prompts and forces the disable operation. Use with caution in automation.

.OUTPUTS
    System.Object[]
    Returns a single array (emitted once in End) of PSCustomObjects, one per processed UPN.

.EXAMPLE
    Disable-GTUser -UPN 'user1@contoso.com'
    Disables a single user account.

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
        [ValidateScript({ $_ -match $script:GTValidationRegex.UPN })]
        [Alias('UserPrincipalName', 'Users', 'User', 'UserName', 'UPNName')]
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
        # Capture output to prevent pipeline pollution
        $null = Install-GTRequiredModule -ModuleNames $modules -Verbose

        # Graph Connection & Scope Handling
        $requiredScopes = @('User.ReadWrite.All')
        
        # CRITICAL FIX: Capture the boolean result in an 'if' statement.
        # Do not let Test-GTGraphScopes output directly to the pipeline.
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet))
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
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
                if ($Force -or $PSCmdlet.ShouldProcess($target, $action))
                {
                    Update-MgBetaUser -UserId $User -AccountEnabled:$false -ErrorAction Stop
                    Write-PSFMessage -Level Verbose -Message "$User - Disable User Action - User Disabled"

                    $result = [PSCustomObject]@{
                        User             = $User
                        Status           = 'Disabled'
                        TimeUtc          = $timeUtc
                        HttpStatus       = 200
                        Reason           = 'User disabled successfully'
                        ExceptionMessage = ''
                    }
                    [void]$results.Add($result)
                }
                else
                {
                    # When -WhatIf or user declines via -Confirm
                    Write-PSFMessage -Level Verbose -Message "$User - Disable User Action - Skipped (WhatIf/Confirmed=false)"

                    $result = [PSCustomObject]@{
                        User             = $User
                        Status           = 'Skipped'
                        TimeUtc          = $timeUtc
                        HttpStatus       = $null
                        Reason           = 'Operation skipped (WhatIf/confirmation declined)'
                        ExceptionMessage = ''
                    }
                    [void]$results.Add($result)
                }
            }
            catch
            {
                # Use centralized error helper
                $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'user'
                
                # Log to console/file using PSFramework
                Write-PSFMessage -Level $err.LogLevel -Message "$User - Disable User Action - $($err.Reason)"
                
                # Add failure object to results
                $result = [PSCustomObject]@{
                    User             = $User
                    Status           = 'Failed'
                    TimeUtc          = $timeUtc
                    HttpStatus       = $err.HttpStatus
                    Reason           = $err.Reason
                    ExceptionMessage = $err.ErrorMessage
                }
                [void]$results.Add($result)
            }
        }
    }

    end
    {
        # Emit a single array of all results
        if ($results.Count -gt 0)
        {
            Write-Output ($results.ToArray())
        }
        else
        {
            Write-Output @()
        }
    }
}
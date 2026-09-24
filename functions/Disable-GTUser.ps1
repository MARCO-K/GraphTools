<#
.SYNOPSIS
    Disables user accounts in Microsoft Entra ID (Azure AD).

.DESCRIPTION
    Disables one or more user accounts by setting the AccountEnabled property to false.
    It validates UPN format and manages Microsoft Graph connection automatically.

    This cmdlet supports -WhatIf and -Confirm via ShouldProcess.

.PARAMETER UPN
    One or more User Principal Names (UPNs) to disable. Must be in valid email format.
    Aliases: UserPrincipalName, Users, User, UserName, UPNName

.PARAMETER Force
    Suppresses confirmation prompts and forces the disable operation. Use with caution in automation.

.PARAMETER NewSession
    If specified, creates a new Microsoft Graph session by disconnecting any existing session first.

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
        [switch]$Force,

        [Parameter()]
        [switch]$NewSession
    )

    begin
    {
        # Prepare a collection for results. We'll emit a single array in End().
        $results = New-Object System.Collections.ArrayList
        $approvedUsers = [System.Collections.Generic.List[string]]::new()

        # Graph Connection & Scope Handling
        $requiredScopes = @('User.ReadWrite.All')
        if (-not (Initialize-GTGraphConnection -Scopes $requiredScopes -NewSession:$NewSession))
        {
            Write-Error "Failed to initialize session."
            return
        }

        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Quiet))
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
            $timeUtc = (Get-UTCTime).ToString('o')

            if ($Force -or $PSCmdlet.ShouldProcess($target, $action))
            {
                [void]$approvedUsers.Add($User)
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
    }

    end
    {
        if ($approvedUsers.Count -eq 1)
        {
            $User = $approvedUsers[0]
            $encodedUser = [System.Uri]::EscapeDataString($User)
            $timeUtc = (Get-UTCTime).ToString('o')
            try
            {
                Invoke-GTGraphRequest -Method PATCH -Uri ("v1.0/users/{0}" -f $encodedUser) -Body @{ accountEnabled = $false } -ContentType 'application/json' -ErrorAction Stop
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
            catch
            {
                $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'user'
                Write-PSFMessage -Level $err.LogLevel -Message "$User - Disable User Action - $($err.Reason)"

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
        elseif ($approvedUsers.Count -gt 1)
        {
            $batchRequests = @()
            foreach ($User in $approvedUsers)
            {
                $batchRequests += @{
                    id      = $User
                    method  = 'PATCH'
                    url     = "/users/$([System.Uri]::EscapeDataString($User))"
                    body    = @{ accountEnabled = $false }
                    headers = @{ 'Content-Type' = 'application/json' }
                }
            }

            Write-PSFMessage -Level Verbose -Message "Disabling $($approvedUsers.Count) users via JSON batch processing..."
            $batchResponses = $null
            try
            {
                $batchResponses = Invoke-GTGraphBatch -Requests $batchRequests -ErrorAction Stop
            }
            catch
            {
                $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'user'
                Write-PSFMessage -Level $err.LogLevel -Message "Batch request failed: $($err.Reason)"

                foreach ($User in $approvedUsers)
                {
                    $result = [PSCustomObject]@{
                        User             = $User
                        Status           = 'Failed'
                        TimeUtc          = (Get-UTCTime).ToString('o')
                        HttpStatus       = $err.HttpStatus
                        Reason           = $err.Reason
                        ExceptionMessage = $err.ErrorMessage
                    }
                    [void]$results.Add($result)
                }
            }

            if ($batchResponses)
            {
                $responseLookup = @{}
                foreach ($resp in $batchResponses)
                {
                    $responseLookup[$resp.Id] = $resp
                }

                foreach ($User in $approvedUsers)
                {
                    $timeUtc = (Get-UTCTime).ToString('o')
                    if ($responseLookup.ContainsKey($User))
                    {
                        $resp = $responseLookup[$User]
                        if ($resp.Status -in 200, 204)
                        {
                            Write-PSFMessage -Level Verbose -Message "$User - Disable User Action - User Disabled"
                            $result = [PSCustomObject]@{
                                User             = $User
                                Status           = 'Disabled'
                                TimeUtc          = $timeUtc
                                HttpStatus       = $resp.Status
                                Reason           = 'User disabled successfully'
                                ExceptionMessage = ''
                            }
                            [void]$results.Add($result)
                        }
                        else
                        {
                            $reason = if ($resp.Body -and $resp.Body.error -and $resp.Body.error.message) { $resp.Body.error.message } else { "Batch subrequest returned HTTP $($resp.Status)" }
                            Write-PSFMessage -Level Warning -Message "$User - Disable User Action - Failed ($reason)"
                            $result = [PSCustomObject]@{
                                User             = $User
                                Status           = 'Failed'
                                TimeUtc          = $timeUtc
                                HttpStatus       = $resp.Status
                                Reason           = $reason
                                ExceptionMessage = $reason
                            }
                            [void]$results.Add($result)
                        }
                    }
                    else
                    {
                        $result = [PSCustomObject]@{
                            User             = $User
                            Status           = 'Failed'
                            TimeUtc          = $timeUtc
                            HttpStatus       = 500
                            Reason           = 'No batch response received for user'
                            ExceptionMessage = 'Missing batch subrequest response'
                        }
                        [void]$results.Add($result)
                    }
                }
            }
        }

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
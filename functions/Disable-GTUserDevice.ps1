<#
.SYNOPSIS
    Disables all registered devices for a user in Microsoft Entra ID (Azure AD)
.DESCRIPTION
    Disables all devices registered to a user account to prevent access from those devices.
    This function retrieves all registered devices for a user and disables them by setting AccountEnabled to false.
    Requires Microsoft.Graph.Authentication, Microsoft.Graph.Users, and Microsoft.Graph.Identity.DirectoryManagement modules.
    It validates UPN format and manages Microsoft Graph connection automatically.

    This cmdlet supports -WhatIf and -Confirm via ShouldProcess (SupportsShouldProcess = $true).
.PARAMETER UPN
    One or more User Principal Names (UPNs) whose devices should be disabled. Must be in valid email format.

    Aliases: UserPrincipalName, Users, UserName, UPNName
.PARAMETER NewSession
    If specified, creates a new Microsoft Graph session by disconnecting any existing session first.

.PARAMETER Force
    Suppresses confirmation prompts and forces the disable operation. Use with caution in automation.

.OUTPUTS
    System.Object[]
    Returns a single array (emitted once in End) of PSCustomObjects, one per processed device with the following properties:
      - User            : The UPN of the user owning the device
      - DeviceId        : The device identifier
      - DeviceName      : The display name of the device
      - Status          : 'Disabled' | 'Skipped' | 'AlreadyDisabled' | 'Failed' | 'NoDevices'
      - TimeUtc         : ISO-8601 UTC timestamp of when the action completed/was skipped
      - HttpStatus      : HTTP status code detected from the Graph error (if applicable)
      - Reason          : Short human-readable reason or guidance
      - ExceptionMessage: Raw exception message (for troubleshooting)
.EXAMPLE
    Disable-GTUserDevice -UPN 'user1@contoso.com'

    Disables all devices registered to a single user using the UPN parameter.
.EXAMPLE
    Disable-GTUserDevice -UserName 'user1@contoso.com'

    Disables all devices registered to a single user using the UserName alias.
.EXAMPLE
    Disable-GTUserDevice -UPN 'user1@contoso.com','user2@contoso.com'

    Disables devices for multiple users.
.EXAMPLE
    Disable-GTUserDevice -Users 'user1@contoso.com','user2@contoso.com'

    Disables devices for multiple users using the Users alias.
.EXAMPLE
    $users | Disable-GTUserDevice

    Disables devices for users from pipeline input.
.EXAMPLE
    Disable-GTUserDevice -UPN 'user1@contoso.com' -WhatIf

    Shows what would happen if the command runs without actually disabling devices.
.EXAMPLE
    Disable-GTUserDevice -UPN 'user1@contoso.com' -Force

    Disables devices without prompting for confirmation.
#>
Function Disable-GTUserDevice
{
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([object[]])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateScript({$_ -match $script:GTValidationRegex.UPN})]
        [Alias('UserPrincipalName','Users','UserName','UPNName')]
        [string[]]$UPN,

        [Parameter()]
        [switch]$NewSession,

        [Parameter()]
        [switch]$Force
    )

    begin
    {
        # Prepare a collection for results. We'll emit a single array in End().
        $results = New-Object System.Collections.ArrayList

        # Module Management
        $modules = ('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Identity.DirectoryManagement')
        Install-GTRequiredModule -ModuleNames $modules -Verbose

        # Graph Connection Handling
        $connectionResult = Initialize-GTGraphConnection -Scopes 'Directory.AccessAsUser.All' -NewSession:$NewSession
        if (-not $connectionResult) {
            Write-PSFMessage -Level Error -Message "Failed to initialize Microsoft Graph connection. Aborting device disable operation."
            return
        }
    }

    process
    {
        foreach ($User in $UPN)
        {
            $timeUtc = (Get-Date).ToUniversalTime().ToString('o')

            try
            {
                # Get all registered devices for the user
                $registeredDevices = Get-MgUserRegisteredDevice -UserId $User -ErrorAction Stop

                if ($null -eq $registeredDevices -or $registeredDevices.Count -eq 0)
                {
                    Write-PSFMessage -Level Verbose -Message "$User - Disable Device Action - No registered devices found"
                    $result = [PSCustomObject]@{
                        User            = $User
                        DeviceId        = $null
                        DeviceName      = $null
                        Status          = 'NoDevices'
                        TimeUtc         = $timeUtc
                        HttpStatus      = $null
                        Reason          = 'No registered devices found for user'
                        ExceptionMessage= ''
                    }
                    [void]$results.Add($result)
                    continue
                }

                foreach ($device in $registeredDevices)
                {
                    $deviceTimeUtc = (Get-Date).ToUniversalTime().ToString('o')
                    try
                    {
                        # The device object from Get-MgUserRegisteredDevice returns a DirectoryObject
                        # We need to get it as a Device to access the properties
                        $deviceDetail = Get-MgUserRegisteredDeviceAsDevice -UserId $User -DirectoryObjectId $device.Id -ErrorAction Stop

                        if ($deviceDetail.AccountEnabled -eq $true)
                        {
                            # Describe the target and action for ShouldProcess
                            $target = "$User - Device: $($deviceDetail.DisplayName) (ID: $($device.Id))"
                            $action = "Disable device (set AccountEnabled to False)"

                            if ($PSCmdlet.ShouldProcess($target, $action)) {
                                Update-MgDevice -DeviceId $device.Id -AccountEnabled:$false -ErrorAction Stop
                                Write-PSFMessage -Level Verbose -Message "$User - Disable Device Action - Device disabled: $($deviceDetail.DisplayName) (ID: $($device.Id))"

                                $result = [PSCustomObject]@{
                                    User            = $User
                                    DeviceId        = $device.Id
                                    DeviceName      = $deviceDetail.DisplayName
                                    Status          = 'Disabled'
                                    TimeUtc         = $deviceTimeUtc
                                    HttpStatus      = $null
                                    Reason          = 'Device disabled'
                                    ExceptionMessage= ''
                                }
                                [void]$results.Add($result)
                            }
                            else {
                                # When -WhatIf or user declines via -Confirm, operation is not performed.
                                Write-PSFMessage -Level Verbose -Message "$User - Disable Device Action - Skipped (WhatIf/Confirmed=false): $($deviceDetail.DisplayName) (ID: $($device.Id))"

                                $result = [PSCustomObject]@{
                                    User            = $User
                                    DeviceId        = $device.Id
                                    DeviceName      = $deviceDetail.DisplayName
                                    Status          = 'Skipped'
                                    TimeUtc         = $deviceTimeUtc
                                    HttpStatus      = $null
                                    Reason          = 'Operation skipped (WhatIf/confirmation declined)'
                                    ExceptionMessage= ''
                                }
                                [void]$results.Add($result)
                            }
                        }
                        else
                        {
                            Write-PSFMessage -Level Verbose -Message "$User - Disable Device Action - Device already disabled: $($deviceDetail.DisplayName) (ID: $($device.Id))"
                            $result = [PSCustomObject]@{
                                User            = $User
                                DeviceId        = $device.Id
                                DeviceName      = $deviceDetail.DisplayName
                                Status          = 'AlreadyDisabled'
                                TimeUtc         = $deviceTimeUtc
                                HttpStatus      = $null
                                Reason          = 'Device was already disabled'
                                ExceptionMessage= ''
                            }
                            [void]$results.Add($result)
                        }
                    }
                    catch
                    {
                        # Improved error handling: attempt to detect common HTTP status codes from the Graph SDK exception
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
                                # Security best practice: Use a generic error message for 404 and 403 to prevent enumeration.
                                $reason = 'Operation failed. The device could not be processed.'
                                Write-PSFMessage -Level Error -Message "$User - Disable Device Action - $reason (Device: $($device.Id))"
                                Write-PSFMessage -Level Debug -Message "Detailed error (404): $errorMsg"
                            }
                            403 {
                                # Security best practice: Use a generic error message for 404 and 403 to prevent enumeration.
                                $reason = 'Operation failed. The device could not be processed.'
                                Write-PSFMessage -Level Error -Message "$User - Disable Device Action - $reason (Device: $($device.Id))"
                                Write-PSFMessage -Level Debug -Message "Detailed error (403): $errorMsg"
                            }
                            429 {
                                $reason = 'Throttled by Graph API (429). Consider retrying after a delay or implementing exponential backoff.'
                                Write-PSFMessage -Level Warning -Message "$User - Disable Device Action - $reason (Device: $($device.Id))"
                            }
                            400 {
                                $reason = "Bad request (400). $errorMsg"
                                Write-PSFMessage -Level Error -Message "$User - Disable Device Action - $reason (Device: $($device.Id))"
                            }
                            default {
                                Write-PSFMessage -Level Error -Message "$User - Disable Device Action - Failed to disable device $($device.Id): $errorMsg"
                                Write-PSFMessage -Level Debug -Message ($ex | Out-String)
                            }
                        }

                        $result = [PSCustomObject]@{
                            User            = $User
                            DeviceId        = $device.Id
                            DeviceName      = $null
                            Status          = 'Failed'
                            TimeUtc         = $deviceTimeUtc
                            HttpStatus      = $httpStatus
                            Reason          = $reason
                            ExceptionMessage= $errorMsg
                        }
                        [void]$results.Add($result)
                    }
                }
            }
            catch
            {
                # Handle errors getting registered devices for the user
                $ex = $_.Exception
                $httpStatus = $null
                $errorMsg = $ex.Message

                # Attempt to extract status code
                if ($ex.Response -and $ex.Response.StatusCode) {
                    try { $httpStatus = [int]$ex.Response.StatusCode } catch {}
                }
                if (-not $httpStatus -and $ex.InnerException.Response -and $ex.InnerException.Response.StatusCode) {
                    try { $httpStatus = [int]$ex.InnerException.Response.StatusCode } catch {}
                }

                # Pattern matching for status codes
                if (-not $httpStatus) {
                    if ($errorMsg -match '\b404\b' -or $errorMsg -match 'not found') { $httpStatus = 404 }
                    elseif ($errorMsg -match '\b403\b' -or $errorMsg -match 'Insufficient privileges') { $httpStatus = 403 }
                    elseif ($errorMsg -match '\b429\b' -or $errorMsg -match 'throttl') { $httpStatus = 429 }
                    elseif ($errorMsg -match '\b400\b' -or $errorMsg -match 'Bad Request') { $httpStatus = 400 }
                }

                # Compose user-friendly reason
                $reason = "Failed: $errorMsg"
                switch ($httpStatus) {
                    404 {
                        $reason = 'Operation failed. The user could not be processed.'
                        Write-PSFMessage -Level Error -Message "$User - Disable Device Action - $reason"
                        Write-PSFMessage -Level Debug -Message "Detailed error (404): $errorMsg"
                    }
                    403 {
                        $reason = 'Operation failed. The user could not be processed.'
                        Write-PSFMessage -Level Error -Message "$User - Disable Device Action - $reason"
                        Write-PSFMessage -Level Debug -Message "Detailed error (403): $errorMsg"
                    }
                    429 {
                        $reason = 'Throttled by Graph API (429). Consider retrying after a delay or implementing exponential backoff.'
                        Write-PSFMessage -Level Warning -Message "$User - Disable Device Action - $reason"
                    }
                    400 {
                        $reason = "Bad request (400). $errorMsg"
                        Write-PSFMessage -Level Error -Message "$User - Disable Device Action - $reason"
                    }
                    default {
                        Write-PSFMessage -Level Error -Message "$User - Disable Device Action - $errorMsg"
                        Write-PSFMessage -Level Debug -Message ($ex | Out-String)
                    }
                }

                $result = [PSCustomObject]@{
                    User            = $User
                    DeviceId        = $null
                    DeviceName      = $null
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
        # Emit a single array of all per-device result objects for easier consumption by callers/automation.
        # Use ToArray() so a true array is returned instead of an ArrayList to keep type expectations simple.
        ,$results.ToArray()
    }
}

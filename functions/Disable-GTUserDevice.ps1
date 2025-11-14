<#
.SYNOPSIS
    Disables all registered devices for a user in Microsoft Entra ID (Azure AD)
.DESCRIPTION
    Disables all enabled devices registered to a user account to prevent access from those devices.
    This function uses an optimized query to retrieve enabled devices for a user with minimal API calls,
    then disables them by setting AccountEnabled to false.
    
    Performance optimization: Instead of getting generic device objects and then fetching details for each,
    this function gets all enabled devices directly with a single filtered query per user, reducing
    API calls from 1+N to just 2 per user (1 for user ID, 1 for filtered devices).
    
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
      - Status          : 'Disabled' | 'Skipped' | 'Failed' | 'NoDevices'
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
                # Performance Optimization: Get user ID first, then query devices directly with filter
                # This reduces API calls from 1+N to just 2 per user (1 for user ID, 1 for all enabled devices)
                $userObject = Get-MgUser -UserId $User -Property Id -ErrorAction Stop
                $userId = $userObject.Id

                # Validate that userId is a GUID to prevent OData injection
                Test-GTGuid -InputObject $userId | Out-Null
                # Get all enabled devices registered to this user in a single API call
                # This replaces Get-MgUserRegisteredDevice + Get-MgUserRegisteredDeviceAsDevice loop
                $devicesToDisable = Get-MgDevice -All -Filter "accountEnabled eq true and registeredUsers/any(u:u/id eq '$userId')" -ErrorAction Stop

                if ($null -eq $devicesToDisable -or $devicesToDisable.Count -eq 0)
                {
                    Write-PSFMessage -Level Verbose -Message "$User - Disable Device Action - No enabled devices found"
                    $result = [PSCustomObject]@{
                        User            = $User
                        DeviceId        = $null
                        DeviceName      = $null
                        Status          = 'NoDevices'
                        TimeUtc         = $timeUtc
                        HttpStatus      = $null
                        Reason          = 'No enabled devices found for user'
                        ExceptionMessage= ''
                    }
                    [void]$results.Add($result)
                    continue
                }

                # Process each device that needs to be disabled
                foreach ($device in $devicesToDisable)
                {
                    $deviceTimeUtc = (Get-Date).ToUniversalTime().ToString('o')
                    try
                    {
                        # Describe the target and action for ShouldProcess
                        $target = "$User - Device: $($device.DisplayName) (ID: $($device.Id))"
                        $action = "Disable device (set AccountEnabled to False)"

                        if ($PSCmdlet.ShouldProcess($target, $action)) {
                            Update-MgDevice -DeviceId $device.Id -AccountEnabled:$false -ErrorAction Stop
                            Write-PSFMessage -Level Verbose -Message "$User - Disable Device Action - Device disabled: $($device.DisplayName) (ID: $($device.Id))"

                            $result = [PSCustomObject]@{
                                User            = $User
                                DeviceId        = $device.Id
                                DeviceName      = $device.DisplayName
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
                            Write-PSFMessage -Level Verbose -Message "$User - Disable Device Action - Skipped (WhatIf/Confirmed=false): $($device.DisplayName) (ID: $($device.Id))"

                            $result = [PSCustomObject]@{
                                User            = $User
                                DeviceId        = $device.Id
                                DeviceName      = $device.DisplayName
                                Status          = 'Skipped'
                                TimeUtc         = $deviceTimeUtc
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
                        $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'device'

                        # Log appropriate message based on error details
                        if ($errorDetails.HttpStatus -in 404, 403) {
                            Write-PSFMessage -Level $errorDetails.LogLevel -Message "$User - Disable Device Action - $($errorDetails.Reason) (Device: $($device.Id))"
                            Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
                        }
                        elseif ($errorDetails.HttpStatus) {
                            Write-PSFMessage -Level $errorDetails.LogLevel -Message "$User - Disable Device Action - $($errorDetails.Reason) (Device: $($device.Id))"
                        }
                        else {
                            Write-PSFMessage -Level Error -Message "$User - Disable Device Action - Failed to disable device $($device.Id): $($errorDetails.ErrorMessage)"
                            Write-PSFMessage -Level Debug -Message ($_.Exception | Out-String)
                        }

                        $result = [PSCustomObject]@{
                            User            = $User
                            DeviceId        = $device.Id
                            DeviceName      = $device.DisplayName
                            Status          = 'Failed'
                            TimeUtc         = $deviceTimeUtc
                            HttpStatus      = $errorDetails.HttpStatus
                            Reason          = $errorDetails.Reason
                            ExceptionMessage= $errorDetails.ErrorMessage
                        }
                        [void]$results.Add($result)
                    }
                }
            }
            catch
            {
                # Handle errors getting user or devices for the user
                # Use centralized error handling helper to parse Graph API exceptions
                $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'user'

                # Log appropriate message based on error details
                if ($errorDetails.HttpStatus -in 404, 403) {
                    Write-PSFMessage -Level $errorDetails.LogLevel -Message "$User - Disable Device Action - $($errorDetails.Reason)"
                    Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
                }
                elseif ($errorDetails.HttpStatus) {
                    Write-PSFMessage -Level $errorDetails.LogLevel -Message "$User - Disable Device Action - $($errorDetails.Reason)"
                }
                else {
                    Write-PSFMessage -Level Error -Message "$User - Disable Device Action - $($errorDetails.ErrorMessage)"
                    Write-PSFMessage -Level Debug -Message ($_.Exception | Out-String)
                }

                $result = [PSCustomObject]@{
                    User            = $User
                    DeviceId        = $null
                    DeviceName      = $null
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
        # Emit a single array of all per-device result objects for easier consumption by callers/automation.
        # Use ToArray() so a true array is returned instead of an ArrayList to keep type expectations simple.
        ,$results.ToArray()
    }
}

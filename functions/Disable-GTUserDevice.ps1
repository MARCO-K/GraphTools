<#
.SYNOPSIS
    Disables all registered devices for a user in Microsoft Entra ID (Azure AD)
.DESCRIPTION
    Disables all devices registered to a user account to prevent access from those devices.
    This function retrieves all registered devices for a user and disables them by setting AccountEnabled to false.
    Requires Microsoft.Graph.Authentication, Microsoft.Graph.Users, and Microsoft.Graph.Identity.DirectoryManagement modules.
    It validates UPN format and manages Microsoft Graph connection automatically.
.PARAMETER UPN
    One or more User Principal Names (UPNs) whose devices should be disabled. Must be in valid email format.
    
    Aliases: UserPrincipalName, Users, UserName, UPNName
.PARAMETER NewSession
    If specified, creates a new Microsoft Graph session by disconnecting any existing session first.
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
#>
Function Disable-GTUserDevice
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateScript({$_ -match $script:GTValidationRegex.UPN})]
        [Alias('UserPrincipalName','Users','UserName','UPNName')]
        [string[]]$UPN,

        [Switch]$NewSession
    )

    begin
    {
        # Module Management
        $modules = ('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Identity.DirectoryManagement')
        Install-GTRequiredModule -ModuleNames $modules -Verbose

        # Graph Connection Handling
        Initialize-GTGraphConnection -Scopes 'Directory.AccessAsUser.All' -NewSession:$NewSession
    }

    process
    {
        foreach ($User in $UPN)
        {
            try
            {
                # Get all registered devices for the user
                $registeredDevices = Get-MgUserRegisteredDevice -UserId $User -ErrorAction Stop

                if ($null -eq $registeredDevices -or $registeredDevices.Count -eq 0)
                {
                    Write-PSFMessage -Level Verbose -Message "$User - Disable Device Action - No registered devices found"
                    continue
                }

                foreach ($device in $registeredDevices)
                {
                    try
                    {
                        # The device object from Get-MgUserRegisteredDevice returns a DirectoryObject
                        # We need to get it as a Device to access the properties
                        $deviceDetail = Get-MgUserRegisteredDeviceAsDevice -UserId $User -DirectoryObjectId $device.Id -ErrorAction Stop

                        if ($deviceDetail.AccountEnabled -eq $true)
                        {
                            Update-MgDevice -DeviceId $device.Id -AccountEnabled:$false -ErrorAction Stop
                            Write-PSFMessage -Level Verbose -Message "$User - Disable Device Action - Device disabled: $($deviceDetail.DisplayName) (ID: $($device.Id))"
                        }
                        else
                        {
                            Write-PSFMessage -Level Verbose -Message "$User - Disable Device Action - Device already disabled: $($deviceDetail.DisplayName) (ID: $($device.Id))"
                        }
                    }
                    catch
                    {
                        Write-PSFMessage -Level Error -Message "$User - Disable Device Action - Failed to disable device $($device.Id): $($_.Exception.Message)"
                    }
                }
            }
            catch
            {
                Write-PSFMessage -Level Error -Message "$User - Disable Device Action - $($_.Exception.Message)"
            }
        }
    }

    end
    {
    }
}

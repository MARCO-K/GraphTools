function Get-MFAReport
{
    [CmdletBinding()]
    Param (
        [Switch]$NewSession,
        [Switch]$AdminsOnly,
        [Switch]$UsersWithoutMFA,
        [Switch]$NoGuestUser,
        [Switch]$MFACapable,
        [Switch]$MarkMethods,
        [string[]]$Scope = @('User.Read.All', 'AuditLog.Read.All'),
        [string[]]$WeakMethods = @('SMS', 'PhoneAppNotification', 'PhoneAppOTP', 'Email', 'softwareOneTimePasscode', 'mobilePhone'),
        [string[]]$StrongMethods = @('FIDO2', 'WindowsHelloForBusiness', 'microsoftAuthenticatorPush', 'microsoftAuthenticatorPasswordless', 'passKeyDeviceBound')
    )

    Begin
    {

        if (-not (Get-Module -Name Microsoft.Graph.Beta.Reports -ListAvailable))
        {
            Write-PSFMessage -Level 'Verbose' -Message 'Microsoft Graph Beta module is not available.'
            try
            {
                Install-Module -Name Microsoft.Graph.Beta.Reports -Scope CurrentUser -Force
            }
            catch
            {
                Write-PSFMessage -Level 'Error' -Message 'Failed to install Microsoft.Graph.Beta.Reports module.'
                return
            }
        }

        if ($NewSession)
        {
            Write-PSFMessage -Level 'Verbose' -Message 'Close existing Microsoft Graph session.'
            Disconnect-MgGraph
        }

        $mgContext = Get-MgContext
        if (-not $mgContext.Account -or -not $mgContext.TenantId)
        {
            Write-PSFMessage -Level 'Verbose' -Message 'No Microsoft Graph context found. Attempting to connect.'
            try
            {
                Connect-MgGraph -Scopes $scope -NoWelcome
            }
            catch
            {
                Write-PSFMessage -Level 'Error' -Message 'Failed to connect to Microsoft Graph.'
                return
            }
        }

        try
        {
            $report = Get-MgBetaReportAuthenticationMethodUserRegistrationDetail -All
        }
        catch
        {
            Write-PSFMessage -Level 'Error' -Message 'Failed to retrieve MFA report from Microsoft Graph.'
            return
        }
    }

    Process
    {
        $MFAList = $report | ForEach-Object {
            [PSCustomObject][ordered]@{
                UPN                                    = $_.UserPrincipalName
                DisplayName                            = $_.UserDisplayName
                IsAdmin                                = $_.IsAdmin
                UserType                               = $_.UserType
                MethodCount                            = ($_.MethodsRegistered | Measure-Object).Count
                RegisteredMethods                      = $_.MethodsRegistered
                UserPreferredAuthMethod                = $_.UserPreferredMethodForSecondaryAuthentication
                IsSystemPreferredAuthenticationEnabled = $_.IsSystemPreferredAuthenticationMethodEnabled
                IsPasswordlessCapable                  = $_.IsPasswordlessCapable
                IsMfaRegistered                        = $_.IsMfaRegistered
                IsMfaCapable                           = $_.IsMfaCapable
                SystemPreferredAuthenticationMethod    = $_.SystemPreferredAuthenticationMethods -join ","
            }
        }
    }

    End
    {
        Write-PSFMessage -Level 'Verbose' -Message 'Filtering the MFA report based on the provided parameters.'
        if ($MFACapable)
        {
            $MFAList = $MFAList | Where-Object { $_.IsMfaCapable -eq $true }
        }
        if ($AdminsOnly)
        {
            $MFAList = $MFAList | Where-Object { $_.IsAdmin -eq $true }
        }
        if ($UsersWithoutMFA)
        {
            $MFAList = $MFAList | Where-Object { $_.IsMfaRegistered -eq $false }
        }
        if ($NoGuestUser)
        {
            $MFAList = $MFAList | Where-Object { $_.UserType -eq 'Member' }
        }
        if ($MarkMethods)
        {
            $MFAList  | ForEach-Object {
                foreach ($method in $_.RegisteredMethods)
                {
                    if ($WeakMethods -contains $method)
                    {
                        $_ | Add-Member -MemberType NoteProperty -Name 'WeakMethod' -Value $true -Force
                    }
                    if ($StrongMethods -contains $method)
                    {
                        $_ | Add-Member -MemberType NoteProperty -Name 'StrongMethod' -Value $true -Force
            
                    }
                }
            }
        }
        Write-PSFMessage -Level 'Verbose' -Message 'MFA report collected successfully. The report contains $($MFAList.Count) entries.'
        $MFAList
    }
}


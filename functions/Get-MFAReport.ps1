<#
.SYNOPSIS
    Retrieves and analyzes Multi-Factor Authentication (MFA) registration details for users.
.DESCRIPTION
    This function collects MFA registration details from Microsoft Graph and provides filtering options for analysis.
.PARAMETER NewSession
    Establishes a fresh Microsoft Graph connection
.PARAMETER AdminsOnly
    Filters results to admin users only
.PARAMETER UsersWithoutMFA
    Filters results to users without registered MFA
.PARAMETER NoGuestUser
    Excludes guest users from results
.PARAMETER MFACapable
    Filters to users capable of MFA
.PARAMETER MarkMethods
    Adds method strength analysis to results
.PARAMETER Scope
    Microsoft Graph permission scopes required
.PARAMETER WeakMethods
    Authentication methods considered weak
.PARAMETER StrongMethods
    Authentication methods considered strong
.EXAMPLE
    Get-MFAReport -AdminsOnly -MarkMethods
.EXAMPLE
    Get-MFAReport -UsersWithoutMFA -NoGuestUser
#>
function Get-MFAReport
{
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
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

    begin
    {
        # Module Management
        if (-not (Get-Module -Name Microsoft.Graph.Beta.Reports -ListAvailable))
        {
            try
            {
                Install-Module -Name Microsoft.Graph.Beta.Reports -Scope CurrentUser -Force -ErrorAction Stop
            }
            catch
            {
                throw "Module installation failed: $_"
            }
        }

        # Graph Connection Handling
        try
        {
            if ($NewSession) 
            { 
                Write-PSFMessage -Level 'Verbose' -Message 'Close existing Microsoft Graph session.'
                Disconnect-MgGraph -ErrorAction SilentlyContinue 
            }
            
            $context = Get-MgContext
            if (-not $context)
            {
                Write-PSFMessage -Level 'Verbose' -Message 'No Microsoft Graph context found. Attempting to connect.'
                Connect-MgGraph -Scopes $Scope -NoWelcome -ErrorAction Stop
            }
        }
        catch
        {
            Write-PSFMessage -Level 'Error' -Message 'Failed to connect to Microsoft Graph.'
            throw "Graph connection failed: $_"
        }

        # Data Collection
        try
        {
            $report = Get-MgBetaReportAuthenticationMethodUserRegistrationDetail -All -ErrorAction Stop
        }
        catch
        {
            Write-PSFMessage -Level 'Error' -Message 'Failed to retrieve MFA report from Microsoft Graph.'
            throw "Failed to retrieve MFA data: $_"
        }
    }

    process
    {
        # Data Transformation
        $MFAList = foreach ($item in $report)
        {
            [PSCustomObject][ordered]@{
                UPN                                    = $item.UserPrincipalName
                DisplayName                            = $item.UserDisplayName
                IsAdmin                                = $item.IsAdmin
                UserType                               = $item.UserType
                MethodCount                            = $item.MethodsRegistered.Count
                RegisteredMethods                      = $item.MethodsRegistered
                UserPreferredAuthMethod                = $item.UserPreferredMethodForSecondaryAuthentication
                IsSystemPreferredAuthenticationEnabled = $item.IsSystemPreferredAuthenticationMethodEnabled
                IsPasswordlessCapable                  = $item.IsPasswordlessCapable
                IsMfaRegistered                        = $item.IsMfaRegistered
                IsMfaCapable                           = $item.IsMfaCapable
                SystemPreferredAuthenticationMethod    = $item.SystemPreferredAuthenticationMethods -join ','
            }
        }

        # Filter Pipeline
        Write-PSFMessage -Level 'Verbose' -Message 'Filtering the MFA report based on the provided parameters.'
        $filtered = $MFAList | Where-Object {
            (-not $AdminsOnly -or $_.IsAdmin) -and
            (-not $UsersWithoutMFA -or -not $_.IsMfaRegistered) -and
            (-not $NoGuestUser -or $_.UserType -eq 'Member') -and
            (-not $MFACapable -or $_.IsMfaCapable)
        }

        # Method Analysis
        if ($MarkMethods)
        {
            $filtered = $filtered | Select-Object *, 
            @{Name = 'WeakMethod'; Expression = { [bool]($_.RegisteredMethods | Where-Object { $_ -in $WeakMethods }) } },
            @{Name = 'StrongMethod'; Expression = { [bool]($_.RegisteredMethods | Where-Object { $_ -in $StrongMethods }) } }
        }

        $filtered
    }

    end
    {
        Write-PSFMessage -Level 'Verbose' -Message 'MFA report collected successfully. The report contains $($MFAList.Count) entries.'    
    }
}
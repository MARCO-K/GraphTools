<#
.SYNOPSIS
    Retrieves and analyzes Multi-Factor Authentication (MFA) registration details for users.
.DESCRIPTION
    This function collects MFA registration details from Microsoft Graph and provides filtering options for analysis.
.PARAMETER UserPrincipalName
    Accepts one or more User Principal Names from the pipeline or as an argument.
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
.EXAMPLE
    'adele.vance@contoso.com', 'grad.y@contoso.com' | Get-MFAReport
#>
function Get-MFAReport
{
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(ValueFromPipeline = $true, Position = 0)]
        [ValidateScript({$_ -match $script:GTValidationRegex.UPN})]
        [Alias('UPN','Users','User')]
        [string[]]$UserPrincipalName,

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
        if ($AdminsOnly -and $UsersWithoutMFA) {
            throw "You cannot use -AdminsOnly and -UsersWithoutMFA together."
        }
        # Module Management
        $modules = ('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Reports')
        Install-GTRequiredModule -ModuleNames $modules -Verbose

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

        $UPNList = [System.Collections.Generic.List[string]]::new()
    }

    process
    {
        if ($UserPrincipalName) {
            foreach($upn in $UserPrincipalName) {
                $UPNList.Add($upn)
            }
        }
    }

    end
    {
        # Data Collection
        try
        {
            $params = @{ All = $true; ErrorAction = 'Stop' }
            if ($UPNList.Count -gt 0) {
                $filterString = "userPrincipalName in ('" + ($UPNList -join "','") + "')"
                $params.Filter = $filterString
            }
            $report = Get-MgBetaReportAuthenticationMethodUserRegistrationDetail @params
        }
        catch
        {
            Write-PSFMessage -Level 'Error' -Message 'Failed to retrieve MFA report from Microsoft Graph.'
            throw "Failed to retrieve MFA data: $_"
        }

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
            # Convert to hashtables for faster lookups
            $weakMethodsSet = @{}
            $WeakMethods | ForEach-Object { $weakMethodsSet[$_] = $true }
            $strongMethodsSet = @{}
            $StrongMethods | ForEach-Object { $strongMethodsSet[$_] = $true }
            
            $filtered = $filtered | Select-Object *, 
            @{Name = 'WeakMethod'; Expression = { 
                $hasWeak = $false
                foreach ($method in $_.RegisteredMethods) {
                    if ($weakMethodsSet.ContainsKey($method)) {
                        $hasWeak = $true
                        break
                    }
                }
                $hasWeak
            }},
            @{Name = 'StrongMethod'; Expression = { 
                $hasStrong = $false
                foreach ($method in $_.RegisteredMethods) {
                    if ($strongMethodsSet.ContainsKey($method)) {
                        $hasStrong = $true
                        break
                    }
                }
                $hasStrong
            }}
        }

        $filtered
        Write-PSFMessage -Level 'Verbose' -Message 'MFA report collected successfully. The report contains $($MFAList.Count) entries.'
    }
}
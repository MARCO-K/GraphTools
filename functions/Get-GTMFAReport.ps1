<#
.SYNOPSIS
    Retrieves and analyzes Multi-Factor Authentication (MFA) registration details for users.
.DESCRIPTION
    This function collects MFA registration details from Microsoft Graph and provides filtering options for analysis.
.PARAMETER UserPrincipalName
    Accepts one or more User Principal Names from the pipeline or as an argument.

    Aliases: UPN, Users, User, UserName, UPNName
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
    Get-GTMFAReport -AdminsOnly -MarkMethods
.EXAMPLE
    Get-GTMFAReport -UsersWithoutMFA -NoGuestUser
.EXAMPLE
    'adele.vance@contoso.com', 'grad.y@contoso.com' | Get-GTMFAReport

    Gets MFA report for specific users using pipeline input.

.EXAMPLE
    Get-GTMFAReport -UPN 'user@contoso.com'

    Gets MFA report for a single user using the UPN alias.

.EXAMPLE
    Get-GTMFAReport -Users 'user1@contoso.com', 'user2@contoso.com'

    Gets MFA report for multiple users using the Users alias.
#>
function Get-GTMFAReport
{
    [Alias('Get-MFAReport')]
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(ValueFromPipeline = $true, Position = 0)]
        [ValidateScript({$_ -match $script:GTValidationRegex.UPN})]
        [Alias('UPN','Users','User','UserName','UPNName')]
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

        # Graph Connection Handling
        $graphConnected = Initialize-GTGraphConnection -Scopes $Scope -NewSession:$NewSession
        if (-not $graphConnected) {
            throw "Failed to establish Microsoft Graph connection. Aborting Get-MFAReport."
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
            # beta required: authenticationMethodsUserRegistrationDetails is not available in v1.0
            $baseUri = 'beta/reports/authenticationMethodsUserRegistrationDetails'
            if ($UPNList.Count -gt 0) {
                $filterString = "userPrincipalName in ('" + ($UPNList -join "','") + "')"
                $report = Invoke-GTGraphPagedRequest -Uri "$($baseUri)?`$filter=$([Uri]::EscapeDataString($filterString))"
            } else {
                $report = Invoke-GTGraphPagedRequest -Uri $baseUri
            }
        }
        catch
        {
            # Use centralized error handling helper to parse Graph API exceptions
            $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'user'

            # Log appropriate message based on error details
            if ($errorDetails.HttpStatus -in 404, 403) {
                Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to retrieve MFA report from Microsoft Graph - $($errorDetails.Reason)"
                Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
            }
            elseif ($errorDetails.HttpStatus) {
                Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to retrieve MFA report from Microsoft Graph - $($errorDetails.Reason)"
            }
            else {
                Write-PSFMessage -Level Error -Message "Failed to retrieve MFA report from Microsoft Graph. $($errorDetails.ErrorMessage)"
            }
            throw "Failed to retrieve MFA data: $($errorDetails.Reason)"
        }

        # Bolt Optimization: Combine data transformation, filtering, and method analysis into a single O(N) loop.
        # This eliminates expensive pipeline passes (Where-Object and Select-Object) and avoids creating intermediate objects.
        if ($MarkMethods)
        {
            # Use HashSet for fast O(1) lookups
            $weakMethodsSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($m in $WeakMethods) { $null = $weakMethodsSet.Add($m) }

            $strongMethodsSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($m in $StrongMethods) { $null = $strongMethodsSet.Add($m) }
        }

        Write-PSFMessage -Level 'Verbose' -Message 'Transforming and filtering the MFA report based on the provided parameters.'

        $filtered = [System.Collections.Generic.List[object]]::new()
        $totalItems = 0

        foreach ($item in $report)
        {
            $totalItems++
            $isAdmin = [bool]$item.isAdmin
            $isMfaRegistered = [bool]$item.isMfaRegistered
            $userType = $item.userType
            $isMfaCapable = [bool]$item.isMfaCapable

            if ($AdminsOnly -and -not $isAdmin) { continue }
            if ($UsersWithoutMFA -and $isMfaRegistered) { continue }
            if ($NoGuestUser -and $userType -ne 'Member') { continue }
            if ($MFACapable -and -not $isMfaCapable) { continue }

            $obj = [ordered]@{
                UPN                                    = $item.userPrincipalName
                DisplayName                            = $item.userDisplayName
                IsAdmin                                = $isAdmin
                UserType                               = $userType
                MethodCount                            = if ($item.methodsRegistered) { $item.methodsRegistered.Count } else { 0 }
                RegisteredMethods                      = $item.methodsRegistered
                UserPreferredAuthMethod                = $item.userPreferredMethodForSecondaryAuthentication
                IsSystemPreferredAuthenticationEnabled = $item.isSystemPreferredAuthenticationMethodEnabled
                IsPasswordlessCapable                  = $item.isPasswordlessCapable
                IsMfaRegistered                        = $isMfaRegistered
                IsMfaCapable                           = $isMfaCapable
                SystemPreferredAuthenticationMethod    = $item.systemPreferredAuthenticationMethods -join ','
            }

            if ($MarkMethods)
            {
                $hasWeak = $false
                $hasStrong = $false
                if ($item.methodsRegistered) {
                    foreach ($method in $item.methodsRegistered) {
                        if (-not $hasWeak -and $weakMethodsSet.Contains($method)) {
                            $hasWeak = $true
                        }
                        if (-not $hasStrong -and $strongMethodsSet.Contains($method)) {
                            $hasStrong = $true
                        }
                        if ($hasWeak -and $hasStrong) { break }
                    }
                }
                $obj.Add('WeakMethod', $hasWeak)
                $obj.Add('StrongMethod', $hasStrong)
            }

            $filtered.Add([PSCustomObject]$obj)
        }

        $filtered.ToArray()
        Write-PSFMessage -Level 'Verbose' -Message "MFA report collected successfully. The report contains $($totalItems) entries."
    }
}
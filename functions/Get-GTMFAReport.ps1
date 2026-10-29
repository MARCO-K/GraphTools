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

        # Data Transformation and Filtering
        Write-PSFMessage -Level 'Verbose' -Message 'Processing and filtering the MFA report based on the provided parameters.'

        # Convert to HashSets for faster lookups if MarkMethods is enabled
        if ($MarkMethods) {
            $weakMethodsSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $WeakMethods | ForEach-Object { [void]$weakMethodsSet.Add($_) }

            $strongMethodsSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $StrongMethods | ForEach-Object { [void]$strongMethodsSet.Add($_) }
        }

        $filtered = [System.Collections.Generic.List[PSObject]]::new()
        $totalCount = 0

        foreach ($item in $report)
        {
            $totalCount++

            # Apply filters early to avoid unnecessary processing
            if ($AdminsOnly -and -not $item.isAdmin) { continue }
            if ($UsersWithoutMFA -and $item.isMfaRegistered) { continue }
            if ($NoGuestUser -and $item.userType -ne 'Member') { continue }
            if ($MFACapable -and -not $item.isMfaCapable) { continue }

            $record = [ordered]@{
                UPN                                    = $item.userPrincipalName
                DisplayName                            = $item.userDisplayName
                IsAdmin                                = $item.isAdmin
                UserType                               = $item.userType
                MethodCount                            = $item.methodsRegistered.Count
                RegisteredMethods                      = $item.methodsRegistered
                UserPreferredAuthMethod                = $item.userPreferredMethodForSecondaryAuthentication
                IsSystemPreferredAuthenticationEnabled = $item.isSystemPreferredAuthenticationMethodEnabled
                IsPasswordlessCapable                  = $item.isPasswordlessCapable
                IsMfaRegistered                        = $item.isMfaRegistered
                IsMfaCapable                           = $item.isMfaCapable
                SystemPreferredAuthenticationMethod    = $item.systemPreferredAuthenticationMethods -join ','
            }

            if ($MarkMethods)
            {
                $hasWeak = $false
                $hasStrong = $false

                foreach ($method in $item.methodsRegistered) {
                    if (-not $hasWeak -and $weakMethodsSet.Contains($method)) {
                        $hasWeak = $true
                    }
                    if (-not $hasStrong -and $strongMethodsSet.Contains($method)) {
                        $hasStrong = $true
                    }
                    if ($hasWeak -and $hasStrong) {
                        break
                    }
                }

                $record['WeakMethod'] = $hasWeak
                $record['StrongMethod'] = $hasStrong
            }

            $filtered.Add([PSCustomObject]$record)
        }

        $filtered.ToArray()
        Write-PSFMessage -Level 'Verbose' -Message "MFA report collected successfully. The report contains $totalCount entries."
    }
}
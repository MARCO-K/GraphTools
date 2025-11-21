function Get-GTLegacyAuthReport
{
    <#
    .SYNOPSIS
    Analyzes sign-in logs to identify Legacy Authentication usage with targeted filtering.

    .DESCRIPTION
    Retrieves Azure AD Sign-in logs for a specified timeframe and filters for Legacy Authentication protocols.
    
    PERFORMANCE:
    - Supports Pipeline input for Users, IPs, and Apps efficiently (Accumulate-then-Execute pattern).
    - Uses Server-Side time filtering.
    - Uses "Defensive" protocol detection (Legacy List + Modern Exclusion).

    .PARAMETER DaysAgo
    The number of days to look back in the logs. Default is 7.

    .PARAMETER UserPrincipalName
    Optional. Filter by specific User Principal Names (UPNs). Accepts pipeline input.

    .PARAMETER ClientAppUsed
    Optional. Filter by specific legacy protocols. Accepts pipeline input.

    .PARAMETER IPAddress
    Optional. Filter by a specific source IP address (IPv4 or IPv6). Accepts pipeline input.

    .PARAMETER SuccessOnly
    Switch to return only successful legacy authentications.

    .PARAMETER NewSession
    Forces a new Microsoft Graph session.

    .OUTPUTS
    PSCustomObject with the following properties:
    - CreatedDateTime: Date and time of the sign-in event
    - UserPrincipalName: The UPN of the user
    - ClientAppUsed: The client application used
    - Result: Classification as "Security Gap (Success)" or "Attack Attempt (Failed)"
    - Status: "Success" or "Failure"
    - ErrorCode: The error code from the sign-in
    - FailureReason: Description of the failure reason if applicable
    - IPAddress: Source IP address
    - Location: City and country/region
    - AppDisplayName: Display name of the application
    - RequestId: Unique request ID

    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Position = 0)]
        [ValidateRange(1, 30)]
        [int]$DaysAgo = 7,

        [Parameter(ValueFromPipeline = $true)]
        [Alias('UPN','UserPrincipalName','Users','User','UserName','UPNName')]
        [ValidateScript({$_ -match $script:GTValidationRegex.UPN})]
        [string[]]$UserPrincipalName,

        [Parameter(ValueFromPipeline = $true)]
        [string[]]$ClientAppUsed,

        [Parameter(ValueFromPipeline = $true)]
        [ValidateScript({
            $ip = $null
            [System.Net.IPAddress]::TryParse($_, [ref]$ip)
        })]
        [string[]]$IPAddress,

        [switch]$SuccessOnly,
        [switch]$NewSession
    )

    begin
    {
        # 1. Initialize Collections for Pipeline Accumulation
        $targetUsers = [System.Collections.Generic.List[string]]::new()
        $targetApps  = [System.Collections.Generic.List[string]]::new()
        $targetIPs   = [System.Collections.Generic.List[string]]::new()

        $modules = @('Microsoft.Graph.Identity.SignIns')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        # 2. Scopes Check
        $requiredScopes = @('AuditLog.Read.All')
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet))
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }

        # 3. Connection Initialization
        if (-not (Initialize-GTGraphConnection -Scopes $requiredScopes -NewSession:$NewSession))
        {
            Write-Error "Failed to initialize session."
            return
        }

        # 4. Define Protocol Lists
        $LegacyProtocols = @(
            'Authenticated SMTP', 'AutoDiscover', 'Exchange ActiveSync', 
            'Exchange Online PowerShell', 'IMAP4', 'MAPI over HTTP', 
            'Outlook Anywhere', 'Outlook Service', 'POP3', 
            'Reporting Web Services', 'Other Clients', 'FTP'
        )

        $ModernProtocols = @(
            'Browser', 
            'Mobile Apps and Desktop clients', 
            'Exchange Services', 
            'Microsoft Office'
        )
        
        Write-PSFMessage -Level Verbose -Message "Protocol Definition Loaded. Targeting Legacy protocols."
    }

    process
    {
        # 5. Accumulate Pipeline Input (Do NOT query Graph here)
        if ($UserPrincipalName) { $targetUsers.AddRange($UserPrincipalName) }
        if ($ClientAppUsed)     { $targetApps.AddRange($ClientAppUsed) }
        if ($IPAddress)         { $targetIPs.AddRange($IPAddress) }
    }

    end
    {
        $utcNow = (Get-Date).ToUniversalTime()
        $startDate = $utcNow.AddDays(-$DaysAgo)
        $filterDate = $startDate.ToString('yyyy-MM-ddTHH:mm:ssZ')

        try
        {
            Write-PSFMessage -Level Verbose -Message "Fetching Sign-in Logs since $filterDate..."

            # 6. Build Server-Side Filter
            $filter = "createdDateTime ge $filterDate"
            if ($SuccessOnly) { $filter += " and status/errorCode eq 0" }

            # Only fetch fields we actually use to reduce bandwidth/memory
            $props = @(
                'id', 'createdDateTime', 'userPrincipalName', 'clientAppUsed', 
                'status', 'ipAddress', 'location', 'appDisplayName'
            )

            $params = @{
                Filter      = $filter
                All         = $true
                ErrorAction = 'Stop'
                Property    = $props
            }

            # 7. Stream and Process (The Heavy Lifting)
            Get-MgAuditLogSignIn @params | ForEach-Object {
                $log = $_
                $appUsed = $log.ClientAppUsed

                # --- FILTERING LOGIC ---

                # A. Protocol Detection (The User's Request)
                # Must be in Legacy list AND NOT in Modern list (Defensive check)
                if (-not ($LegacyProtocols -contains $appUsed -and $ModernProtocols -notcontains $appUsed)) { return }

                # B. Filter by Client App (if specified)
                if ($targetApps.Count -gt 0 -and $appUsed -notin $targetApps) { return }

                # C. Filter by User (if specified)
                if ($targetUsers.Count -gt 0 -and $log.UserPrincipalName -notin $targetUsers) { return }

                # D. Filter by IP (if specified)
                if ($targetIPs.Count -gt 0 -and $log.IpAddress -notin $targetIPs) { return }

                # --- PROCESSING ---

                $isSuccess = ($log.Status.ErrorCode -eq 0)
                
                $resultType = if ($isSuccess) { "Security Gap (Success)" } else { "Attack Attempt (Failed)" }
                
                $failureReason = $null
                if (-not $isSuccess) {
                    $failureReason = switch ($log.Status.ErrorCode) {
                        50034 { "User not found" }
                        50053 { "Account locked" }
                        50055 { "Password expired" }
                        50056 { "Invalid password" }
                        50057 { "User disabled" }
                        50076 { "MFA required (Legacy Blocked)" }
                        50079 { "MFA enrollment required" }
                        50126 { "Invalid username/password" }
                        53003 { "Blocked by CA" }
                        default { $log.Status.FailureReason }
                    }
                }

                [PSCustomObject]@{
                    CreatedDateTime   = $log.CreatedDateTime
                    UserPrincipalName = $log.UserPrincipalName
                    ClientAppUsed     = $appUsed
                    Result            = $resultType
                    Status            = if ($isSuccess) { "Success" } else { "Failure" }
                    ErrorCode         = $log.Status.ErrorCode
                    FailureReason     = $failureReason
                    IPAddress         = $log.IpAddress
                    Location          = "$($log.Location.City), $($log.Location.CountryOrRegion)"
                    AppDisplayName    = $log.AppDisplayName
                    RequestId         = $log.Id
                }
            }
        }
        catch
        {
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'Sign-in Logs'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve sign-in logs: $($err.Reason)"
            throw $err.ErrorMessage
        }
    }
}
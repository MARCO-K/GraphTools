function Invoke-GTDeviceCodeFlow
{
    <#
    .SYNOPSIS
        Performs OAuth 2.0 Device Authorization Grant flow.
    .DESCRIPTION
        Initiates device code authentication, displays verification URL and user code to the host,
        and polls Microsoft identity platform until authorization completes or times out.
    .PARAMETER TenantId
        Microsoft Entra ID Tenant ID or authority domain ('organizations', 'common', or GUID).
    .PARAMETER ClientId
        The Application (Client) ID.
    .PARAMETER Scope
        Requested permission scopes. Defaults to 'https://graph.microsoft.com/.default'.
    .PARAMETER TimeoutSeconds
        Maximum duration to wait for user to complete sign-in. Defaults to 900 seconds (15 minutes).
    .OUTPUTS
        [PSCustomObject] containing AccessToken, RefreshToken, and ExpiresIn.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter()]
        [string]$Scope = 'https://graph.microsoft.com/.default',

        [Parameter()]
        [int]$TimeoutSeconds = 900
    )

    $deviceCodeEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode"
    $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    # Ensure offline_access is present to obtain refresh token
    $requestedScope = if ($Scope -notmatch '\boffline_access\b') { "$Scope offline_access".Trim() } else { $Scope }

    $initBody = @{
        client_id = $ClientId
        scope     = $requestedScope
    }

    try
    {
        $deviceCodeResponse = Invoke-RestMethod -Method Post `
                                                -Uri $deviceCodeEndpoint `
                                                -ContentType 'application/x-www-form-urlencoded' `
                                                -Body $initBody `
                                                -ErrorAction Stop
    }
    catch
    {
        Write-PSFMessage -Level Error -Message "Failed to initiate device code flow: $_"
        throw
    }

    if ($deviceCodeResponse.message)
    {
        Write-PSFMessage -Level Host -Message $deviceCodeResponse.message
    }
    else
    {
        $verifyUrl = if ($deviceCodeResponse.verification_uri) { $deviceCodeResponse.verification_uri } else { 'https://microsoft.com/devicelogin' }
        Write-PSFMessage -Level Host -Message "To sign in, use a web browser to open the page $verifyUrl and enter the code $($deviceCodeResponse.user_code) to authenticate."
    }

    $interval = if ($null -ne $deviceCodeResponse.interval) { [int]$deviceCodeResponse.interval } else { 5 }
    $serverExpiresIn = if ($null -ne $deviceCodeResponse.expires_in) { [int]$deviceCodeResponse.expires_in } else { $TimeoutSeconds }
    $effectiveTimeout = [Math]::Min($TimeoutSeconds, $serverExpiresIn)
    $deadline = [DateTime]::UtcNow.AddSeconds($effectiveTimeout)

    $pollBody = @{
        grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
        client_id   = $ClientId
        device_code = $deviceCodeResponse.device_code
    }

    while ([DateTime]::UtcNow -lt $deadline)
    {
        Start-Sleep -Seconds $interval
        try
        {
            $tokenResponse = Invoke-RestMethod -Method Post `
                                               -Uri $tokenEndpoint `
                                               -ContentType 'application/x-www-form-urlencoded' `
                                               -Body $pollBody `
                                               -ErrorAction Stop

            if ($tokenResponse.access_token)
            {
                return [PSCustomObject]@{
                    AccessToken  = $tokenResponse.access_token
                    RefreshToken = $tokenResponse.refresh_token
                    ExpiresIn    = if ($tokenResponse.expires_in) { [int]$tokenResponse.expires_in } else { 3600 }
                }
            }
        }
        catch
        {
            $errString = $_.ToString()
            if ($errString -match 'authorization_pending')
            {
                continue
            }
            elseif ($errString -match 'slow_down')
            {
                $interval += 5
                continue
            }
            elseif ($errString -match 'expired_token')
            {
                throw "Device authorization code has expired. Please run Connect-GTGraph -DeviceCode again."
            }
            elseif ($errString -match 'authorization_declined')
            {
                throw "Device authorization request was declined by the user."
            }
            else
            {
                throw
            }
        }
    }

    throw "Device code authentication timed out after $effectiveTimeout seconds."
}

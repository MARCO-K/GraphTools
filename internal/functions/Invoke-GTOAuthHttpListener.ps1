function New-GTPkcePair
{
    <#
    .SYNOPSIS
        Generates an RFC 7636 Proof Key for Code Exchange (PKCE) verifier and challenge pair.
    .OUTPUTS
        [PSCustomObject] containing CodeVerifier and CodeChallenge.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $bytes = [byte[]]::new(32)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $verifier = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $challengeBytes = $sha256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($verifier))
    $challenge = [Convert]::ToBase64String($challengeBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    return [PSCustomObject]@{
        CodeVerifier  = $verifier
        CodeChallenge = $challenge
    }
}

function Invoke-GTOAuthHttpListener
{
    <#
    .SYNOPSIS
        Performs OAuth 2.0 Authorization Code flow with PKCE via a local HTTP listener.
    .DESCRIPTION
        Starts a local HTTP listener on localhost, opens the system default browser
        to the Microsoft identity platform authorization endpoint, intercepts the authorization code callback,
        renders a browser completion page, and exchanges the code for access and refresh tokens.
    .PARAMETER TenantId
        Microsoft Entra ID Tenant ID or authority domain ('organizations', 'common', or GUID).
    .PARAMETER ClientId
        The Application (Client) ID.
    .PARAMETER LocalPort
        Local port for HTTP listener callback. Defaults to 8400.
    .PARAMETER Scope
        Requested permission scopes. Defaults to 'https://graph.microsoft.com/.default'.
    .PARAMETER TimeoutSeconds
        Timeout waiting for browser sign-in. Defaults to 180 seconds.
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
        [int]$LocalPort = 8400,

        [Parameter()]
        [string]$Scope = 'https://graph.microsoft.com/.default',

        [Parameter()]
        [int]$TimeoutSeconds = 180
    )

    $redirectUri = "http://localhost:$LocalPort/"
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($redirectUri)

    try
    {
        $listener.Start()
    }
    catch
    {
        throw "Failed to start local HTTP listener on $redirectUri. Ensure port $LocalPort is available or specify a different -LocalPort. Error: $_"
    }

    try
    {
        $pkce = New-GTPkcePair
        $state = [Guid]::NewGuid().ToString()

        $requestedScope = if ($Scope -notmatch '\boffline_access\b') { "$Scope offline_access".Trim() } else { $Scope }

        $authParams = @(
            "client_id=$([System.Uri]::EscapeDataString($ClientId))",
            "response_type=code",
            "redirect_uri=$([System.Uri]::EscapeDataString($redirectUri))",
            "response_mode=query",
            "scope=$([System.Uri]::EscapeDataString($requestedScope))",
            "state=$([System.Uri]::EscapeDataString($state))",
            "code_challenge=$([System.Uri]::EscapeDataString($pkce.CodeChallenge))",
            "code_challenge_method=S256"
        )
        $authorizeUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize?{0}" -f ($authParams -join '&')

        Write-PSFMessage -Level Host -Message "Opening default browser for interactive authentication to Microsoft Graph..."
        Write-PSFMessage -Level Verbose -Message "Navigating to: $authorizeUrl"

        try
        {
            Start-Process $authorizeUrl
        }
        catch
        {
            Write-PSFMessage -Level Host -Message "Could not launch default browser automatically. Please open this URL manually:`n$authorizeUrl"
        }

        # Wait for callback
        $contextTask = $listener.GetContextAsync()
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        while (-not $contextTask.IsCompleted)
        {
            if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds)
            {
                throw "Interactive login timed out after $TimeoutSeconds seconds waiting for browser callback."
            }
            Start-Sleep -Milliseconds 200
        }

        $context = $contextTask.Result
        $request = $context.Request
        $response = $context.Response

        $query = $request.Url.Query.TrimStart('?')
        $queryParams = @{}
        foreach ($item in ($query -split '&'))
        {
            if ($item)
            {
                $parts = $item -split '=', 2
                $k = [System.Uri]::UnescapeDataString($parts[0])
                $v = if ($parts.Length -gt 1) { [System.Uri]::UnescapeDataString($parts[1]) } else { '' }
                $queryParams[$k] = $v
            }
        }

        # Render friendly browser response
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Authentication Successful - GraphTools</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; text-align: center; padding-top: 60px; background-color: #f8fafc; color: #1e293b; }
        .card { background: white; max-width: 480px; margin: 0 auto; padding: 40px; border-radius: 12px; box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1); border: 1px solid #e2e8f0; }
        h2 { color: #0f172a; margin-bottom: 8px; }
        p { color: #64748b; font-size: 15px; }
    </style>
</head>
<body>
    <div class="card">
        <h2>Authentication Complete</h2>
        <p>You have successfully authenticated to Microsoft Graph. You can now close this browser window and return to PowerShell.</p>
    </div>
</body>
</html>
"@
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
        $response.ContentLength64 = $bytes.Length
        $response.ContentType = 'text/html; charset=utf-8'
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        $response.OutputStream.Flush()
        $response.Close()

        if ($queryParams.ContainsKey('error'))
        {
            $desc = if ($queryParams.ContainsKey('error_description')) { $queryParams['error_description'] } else { $queryParams['error'] }
            throw "Interactive authentication failed: $desc"
        }

        if (-not $queryParams.ContainsKey('code'))
        {
            throw "No authorization code was returned by Microsoft identity platform."
        }

        if ($queryParams.ContainsKey('state') -and ($queryParams['state'] -ne $state))
        {
            throw "State mismatch detected during interactive authentication callback. Rejecting response."
        }

        $authCode = $queryParams['code']
    }
    finally
    {
        $listener.Stop()
        $listener.Close()
    }

    # Exchange Authorization Code + PKCE verifier for Tokens
    $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $tokenBody = @{
        client_id     = $ClientId
        grant_type    = 'authorization_code'
        code          = $authCode
        redirect_uri  = $redirectUri
        code_verifier = $pkce.CodeVerifier
        scope         = $requestedScope
    }

    try
    {
        $tokenResponse = Invoke-RestMethod -Method Post `
                                           -Uri $tokenEndpoint `
                                           -ContentType 'application/x-www-form-urlencoded' `
                                           -Body $tokenBody `
                                           -ErrorAction Stop

        if (-not $tokenResponse.access_token)
        {
            throw "Token endpoint did not return an access_token."
        }

        return [PSCustomObject]@{
            AccessToken  = $tokenResponse.access_token
            RefreshToken = $tokenResponse.refresh_token
            ExpiresIn    = if ($tokenResponse.expires_in) { [int]$tokenResponse.expires_in } else { 3600 }
        }
    }
    catch
    {
        Write-PSFMessage -Level Error -Message "Failed to exchange authorization code for tokens: $_"
        throw
    }
}

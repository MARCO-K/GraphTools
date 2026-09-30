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
    try
    {
        $rng.GetBytes($bytes)
    }
    finally
    {
        $rng.Dispose()
    }
    $verifier = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        $challengeBytes = $sha256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($verifier))
    }
    finally
    {
        $sha256.Dispose()
    }
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
        Binds a local HTTP listener on localhost (using an OS-assigned dynamic port by default),
        opens the system default browser to the Microsoft identity platform authorization endpoint,
        filters out non-OAuth stray browser requests, intercepts the authorization code callback,
        validates CSRF state, renders a completion card, and exchanges the code for tokens.
    .PARAMETER TenantId
        Microsoft Entra ID Tenant ID or authority domain ('organizations', 'common', or GUID).
    .PARAMETER ClientId
        The Application (Client) ID.
    .PARAMETER LocalPort
        Local port for HTTP listener callback. Defaults to 0 (dynamic port discovery).
    .PARAMETER Scope
        Requested permission scopes. Defaults to 'https://graph.microsoft.com/.default'.
    .PARAMETER TimeoutSeconds
        Timeout waiting for browser sign-in. Defaults to 180 seconds.
    .PARAMETER ForceConsent
        Forces interactive consent prompt (prompt=consent).
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
        [int]$LocalPort = 0,

        [Parameter()]
        [string]$Scope = 'https://graph.microsoft.com/.default',

        [Parameter()]
        [int]$TimeoutSeconds = 180,

        [Parameter()]
        [switch]$ForceConsent
    )

    $freePortHelper = Join-Path $PSScriptRoot 'Get-GTFreePort.ps1'
    if (-not (Get-Command Get-GTFreePort -ErrorAction SilentlyContinue) -and (Test-Path $freePortHelper))
    {
        . $freePortHelper
    }

    $autoPort = (-not $LocalPort -or $LocalPort -le 0)
    $maxBindAttempts = if ($autoPort) { 5 } else { 1 }
    $listener = $null
    $activePort = $LocalPort

    for ($attempt = 1; $attempt -le $maxBindAttempts; $attempt++)
    {
        if ($autoPort)
        {
            $activePort = Get-GTFreePort
        }
        $candidate = [System.Net.HttpListener]::new()
        $candidate.Prefixes.Add("http://localhost:$activePort/")
        try
        {
            $candidate.Start()
            $listener = $candidate
            break
        }
        catch
        {
            $candidate.Close()
            if ($attempt -eq $maxBindAttempts)
            {
                throw "Failed to start local HTTP listener on http://localhost:$activePort/ after $attempt attempt(s): $_"
            }
        }
    }
    $redirectUri = "http://localhost:$activePort/"

    try
    {
        $pkce = New-GTPkcePair

        $stateBytes = [byte[]]::new(16)
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try
        {
            $rng.GetBytes($stateBytes)
        }
        finally
        {
            $rng.Dispose()
        }
        $state = [Convert]::ToBase64String($stateBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

        $caeClaims = '{"access_token":{"xms_cc":{"values":["CP1"]}}}'
        $prompt = if ($ForceConsent) { 'consent' } else { 'select_account' }
        $requestedScope = if ($Scope -notmatch '\boffline_access\b') { "$Scope offline_access".Trim() } else { $Scope }

        $authParams = @(
            "client_id=$([System.Uri]::EscapeDataString($ClientId))",
            "response_type=code",
            "redirect_uri=$([System.Uri]::EscapeDataString($redirectUri))",
            "response_mode=query",
            "scope=$([System.Uri]::EscapeDataString($requestedScope))",
            "state=$([System.Uri]::EscapeDataString($state))",
            "code_challenge=$([System.Uri]::EscapeDataString($pkce.CodeChallenge))",
            "code_challenge_method=S256",
            "claims=$([System.Uri]::EscapeDataString($caeClaims))",
            "prompt=$([System.Uri]::EscapeDataString($prompt))"
        )
        $authorizeUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize?{0}" -f ($authParams -join '&')

        Write-PSFMessage -Level Host -Message "Opening default browser for interactive authentication to Microsoft Graph (listening on $redirectUri)..."
        Write-PSFMessage -Level Verbose -Message "Navigating to: $authorizeUrl"

        try
        {
            Start-Process $authorizeUrl
        }
        catch
        {
            Write-PSFMessage -Level Host -Message "Could not launch default browser automatically. Please open this URL manually:`n$authorizeUrl"
        }

        # Wait for callback while ignoring stray requests (e.g., favicon.ico, browser preconnects)
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $context = $null

        while (-not $context)
        {
            $remainingSeconds = $TimeoutSeconds - $stopwatch.Elapsed.TotalSeconds
            if ($remainingSeconds -le 0)
            {
                throw "Interactive login timed out after $TimeoutSeconds seconds waiting for browser callback."
            }

            $contextTask = $listener.GetContextAsync()
            $waitMs = [int][Math]::Min([Math]::Max(100, $remainingSeconds * 1000), 5000)
            if (-not $contextTask.Wait($waitMs))
            {
                continue
            }

            $candidateContext = $contextTask.Result
            $rawQuery = $candidateContext.Request.Url.Query.TrimStart('?')
            $hasAuthResponse = ($rawQuery -match '(^|&)code=') -or ($rawQuery -match '(^|&)error=')

            if ($hasAuthResponse)
            {
                $context = $candidateContext
            }
            else
            {
                $candidateContext.Response.StatusCode = 404
                $candidateContext.Response.Close()
            }
        }

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

        $hasError = $queryParams.ContainsKey('error')
        $returnedState = $queryParams['state']
        $isStateValid = ($returnedState -eq $state)
        $authCode = $queryParams['code']

        if ($hasError -or -not $isStateValid -or -not $authCode)
        {
            $errDesc = if ($queryParams.ContainsKey('error_description')) { $queryParams['error_description'] } else { $queryParams['error'] }
            if (-not $errDesc -and -not $isStateValid) { $errDesc = 'CSRF state verification failed.' }
            if (-not $errDesc -and -not $authCode) { $errDesc = 'Missing authorization code in server response.' }

            $errorHtml = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Authentication Failed - GraphTools</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; text-align: center; padding-top: 60px; background-color: #fef2f2; color: #991b1b; }
        .card { background: white; max-width: 480px; margin: 0 auto; padding: 40px; border-radius: 12px; box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1); border: 1px solid #fecaca; }
        h2 { color: #dc2626; margin-bottom: 8px; }
        p { color: #7f1d1d; font-size: 15px; }
    </style>
</head>
<body>
    <div class="card">
        <h2>Authentication Failed</h2>
        <p>$([System.Net.WebUtility]::HtmlEncode($errDesc))</p>
    </div>
</body>
</html>
"@
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($errorHtml)
            $response.StatusCode = 400
            $response.ContentLength64 = $bytes.Length
            $response.ContentType = 'text/html; charset=utf-8'
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.OutputStream.Flush()
            $response.Close()

            if (-not $isStateValid)
            {
                throw "State mismatch detected during interactive authentication callback. Rejecting response."
            }
            if ($hasError)
            {
                throw "Interactive authentication failed: $errDesc"
            }
            throw "No authorization code was returned by Microsoft identity platform."
        }

        # Render successful response
        $successHtml = @"
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
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($successHtml)
        $response.StatusCode = 200
        $response.ContentLength64 = $bytes.Length
        $response.ContentType = 'text/html; charset=utf-8'
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        $response.OutputStream.Flush()
        $response.Close()
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
        claims        = $caeClaims
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

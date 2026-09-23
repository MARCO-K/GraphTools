# Script-scoped token cache
if (-not $script:GTTokenCache)
{
    $script:GTTokenCache = @{
        AccessToken = $null
        ExpiresAt   = [DateTime]::MinValue
        TenantId    = $null
        ClientId    = $null
        Scope       = $null
        AuthType    = $null
    }
}

function Get-GTCachedGraphToken
{
    <#
    .SYNOPSIS
        Acquires and caches an OAuth 2.0 access token for Microsoft Graph without external SDK dependencies.

    .DESCRIPTION
        Implements OAuth 2.0 token acquisition and in-memory caching. Supports:
        - RFC 7523 Certificate-based Client Assertion (RS256 signed JWT via native .NET cryptography)
        - Client Secret-based Client Credentials
        - Direct Bearer token passthrough
        - In-memory caching with a sliding expiration buffer to prevent redundant calls and throttling (HTTP 429).

    .PARAMETER TenantId
        The Microsoft Entra ID Tenant ID (Directory ID).

    .PARAMETER ClientId
        The Application (Client) ID of the registered App.

    .PARAMETER Thumbprint
        The SHA-1 thumbprint of an X.509 certificate in Cert:\LocalMachine\My or Cert:\CurrentUser\My.

    .PARAMETER Certificate
        An explicit [System.Security.Cryptography.X509Certificates.X509Certificate2] object.

    .PARAMETER ClientSecret
        The client secret string for the registered application.

    .PARAMETER AccessToken
        Direct access token string to store and use.

    .PARAMETER Scope
        OAuth 2.0 scope for token request. Defaults to 'https://graph.microsoft.com/.default'.

    .PARAMETER BufferMinutes
        Minutes before actual token expiration to trigger an early refresh. Defaults to 5 minutes.

    .PARAMETER ForceRefresh
        Forces requesting a new token even if the cached token is still valid.

    .OUTPUTS
        System.String (The Bearer access token)

    .EXAMPLE
        Get-GTCachedGraphToken -TenantId $TenantId -ClientId $ClientId -Thumbprint $CertThumbprint

    .EXAMPLE
        Get-GTCachedGraphToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $Secret

    .EXAMPLE
        # Uses session configuration previously set by Connect-GTGraph
        $token = Get-GTCachedGraphToken
    #>
    [CmdletBinding(DefaultParameterSetName = 'SessionConfig')]
    [OutputType([string])]
    param(
        [Parameter(ParameterSetName = 'Certificate', Mandatory = $true)]
        [Parameter(ParameterSetName = 'CertObject', Mandatory = $true)]
        [Parameter(ParameterSetName = 'ClientSecret', Mandatory = $true)]
        [string]$TenantId,

        [Parameter(ParameterSetName = 'Certificate', Mandatory = $true)]
        [Parameter(ParameterSetName = 'CertObject', Mandatory = $true)]
        [Parameter(ParameterSetName = 'ClientSecret', Mandatory = $true)]
        [string]$ClientId,

        [Parameter(ParameterSetName = 'Certificate', Mandatory = $true)]
        [Alias('CertificateThumbprint')]
        [string]$Thumbprint,

        [Parameter(ParameterSetName = 'CertObject', Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(ParameterSetName = 'ClientSecret', Mandatory = $true)]
        [Alias('Secret')]
        [string]$ClientSecret,

        [Parameter(ParameterSetName = 'DirectToken', Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(ParameterSetName = 'Certificate')]
        [Parameter(ParameterSetName = 'CertObject')]
        [Parameter(ParameterSetName = 'ClientSecret')]
        [Parameter(ParameterSetName = 'SessionConfig')]
        [string]$Scope = 'https://graph.microsoft.com/.default',

        [Parameter(ParameterSetName = 'Certificate')]
        [Parameter(ParameterSetName = 'CertObject')]
        [Parameter(ParameterSetName = 'ClientSecret')]
        [Parameter(ParameterSetName = 'SessionConfig')]
        [int]$BufferMinutes = 5,

        [switch]$ForceRefresh
    )

    # 1. Direct token assignment
    if ($PSCmdlet.ParameterSetName -eq 'DirectToken')
    {
        $script:GTTokenCache.AccessToken = $AccessToken
        $script:GTTokenCache.ExpiresAt   = [DateTime]::UtcNow.AddHours(1)
        $script:GTTokenCache.AuthType    = 'DirectToken'
        return $AccessToken
    }

    # 2. Fall back to global session config if parameters are omitted
    if ($PSCmdlet.ParameterSetName -eq 'SessionConfig')
    {
        if ($script:GTConnectionConfig)
        {
            if (-not $TenantId) { $TenantId = $script:GTConnectionConfig.TenantId }
            if (-not $ClientId) { $ClientId = $script:GTConnectionConfig.ClientId }
            if (-not $Thumbprint -and $script:GTConnectionConfig.Thumbprint) { $Thumbprint = $script:GTConnectionConfig.Thumbprint }
            if (-not $Certificate -and $script:GTConnectionConfig.Certificate) { $Certificate = $script:GTConnectionConfig.Certificate }
            if (-not $ClientSecret -and $script:GTConnectionConfig.ClientSecret) { $ClientSecret = $script:GTConnectionConfig.ClientSecret }
            if ($script:GTConnectionConfig.Scope) { $Scope = $script:GTConnectionConfig.Scope }
        }
    }

    $now = [DateTime]::UtcNow

    # 3. Check for valid cached token
    if (-not $ForceRefresh -and $script:GTTokenCache.AccessToken)
    {
        if ($script:GTTokenCache.ExpiresAt.AddMinutes(-$BufferMinutes) -gt $now)
        {
            Write-PSFMessage -Level Verbose -Message "Valid Microsoft Graph token retrieved from cache (valid until $($script:GTTokenCache.ExpiresAt.ToString('u')))."
            return $script:GTTokenCache.AccessToken
        }
        else
        {
            Write-PSFMessage -Level Verbose -Message 'Cached Microsoft Graph token has expired or is within refresh buffer window. Refreshing...'
        }
    }

    # 4. Validate that credentials exist to request a token
    if (-not $TenantId -or -not $ClientId)
    {
        # Check if we have an active access token regardless
        if ($script:GTTokenCache.AccessToken -and ($script:GTTokenCache.ExpiresAt -gt $now))
        {
            return $script:GTTokenCache.AccessToken
        }
        throw "No Microsoft Graph credentials configured. Call Connect-GTGraph or supply TenantId and ClientId with Thumbprint or ClientSecret."
    }

    $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    # Helper function for Base64Url encoding (RFC 7515)
    function ConvertTo-GTBase64Url([byte[]]$Bytes)
    {
        return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    }

    # 5. Acquire token via Certificate (RFC 7523 Client Assertion)
    if ($Certificate -or $Thumbprint)
    {
        $cert = $Certificate
        if (-not $cert)
        {
            $cleanThumbprint = $Thumbprint -replace '\s+', ''
            $cert = Get-Item "Cert:\LocalMachine\My\$cleanThumbprint" -ErrorAction SilentlyContinue
            if (-not $cert)
            {
                $cert = Get-Item "Cert:\CurrentUser\My\$cleanThumbprint" -ErrorAction SilentlyContinue
            }
            if (-not $cert)
            {
                throw "Certificate with thumbprint '$cleanThumbprint' not found in Cert:\LocalMachine\My or Cert:\CurrentUser\My."
            }
        }

        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
        if (-not $rsa)
        {
            throw "No private RSA key found for certificate with thumbprint $($cert.Thumbprint)."
        }

        # Build JWT Header (x5t is Base64Url-encoded SHA-1 thumbprint bytes)
        $cleanThumb = $cert.Thumbprint -replace '\s+', ''
        $thumbBytes = for ($i = 0; $i -lt $cleanThumb.Length; $i += 2)
        {
            [Convert]::ToByte($cleanThumb.Substring($i, 2), 16)
        }

        $jwtHeaderJson = @{
            alg = "RS256"
            typ = "JWT"
            x5t = ConvertTo-GTBase64Url -Bytes $thumbBytes
        } | ConvertTo-Json -Compress
        $headerBase64 = ConvertTo-GTBase64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jwtHeaderJson))

        # Build JWT Payload (RFC 7523 claims)
        $epochNow = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $jwtPayloadJson = @{
            aud = $tokenEndpoint
            iss = $ClientId
            sub = $ClientId
            jti = [Guid]::NewGuid().ToString()
            nbf = $epochNow
            exp = $epochNow + 300
        } | ConvertTo-Json -Compress
        $payloadBase64 = ConvertTo-GTBase64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jwtPayloadJson))

        # Cryptographically sign raw assertion with SHA-256 and PKCS#1
        $rawAssertion = "$headerBase64.$payloadBase64"
        $signatureBytes = $rsa.SignData(
            [System.Text.Encoding]::UTF8.GetBytes($rawAssertion),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
        $clientAssertion = "$rawAssertion.$(ConvertTo-GTBase64Url -Bytes $signatureBytes)"

        $requestBody = @{
            client_id             = $ClientId
            client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
            client_assertion      = $clientAssertion
            grant_type            = "client_credentials"
            scope                 = $Scope
        }
        $authType = 'Certificate'
    }
    # 6. Acquire token via Client Secret
    elseif ($ClientSecret)
    {
        $requestBody = @{
            client_id     = $ClientId
            client_secret = $ClientSecret
            grant_type    = "client_credentials"
            scope         = $Scope
        }
        $authType = 'ClientSecret'
    }
    else
    {
        throw "Neither Certificate/Thumbprint nor ClientSecret was provided for authentication."
    }

    try
    {
        Write-PSFMessage -Level Verbose -Message "Requesting new OAuth2 token from Microsoft Identity Platform for Client ID '$ClientId'..."
        $response = Invoke-RestMethod -Method Post `
                                      -Uri $tokenEndpoint `
                                      -ContentType "application/x-www-form-urlencoded" `
                                      -Body $requestBody `
                                      -ErrorAction Stop

        if (-not $response.access_token)
        {
            throw "Token response did not contain an access_token."
        }

        # Store in cache
        $script:GTTokenCache.AccessToken = $response.access_token
        $script:GTTokenCache.ExpiresAt   = [DateTime]::UtcNow.AddSeconds([int]$response.expires_in)
        $script:GTTokenCache.TenantId    = $TenantId
        $script:GTTokenCache.ClientId    = $ClientId
        $script:GTTokenCache.Scope       = $Scope
        $script:GTTokenCache.AuthType    = $authType

        Write-PSFMessage -Level Verbose -Message "Acquired new Microsoft Graph token ($authType). Expires at $($script:GTTokenCache.ExpiresAt.ToString('u'))."
        return $script:GTTokenCache.AccessToken
    }
    catch
    {
        Write-PSFMessage -Level Error -Message "Failed to acquire Microsoft Graph token: $_"
        throw
    }
}

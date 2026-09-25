# Script-scoped token cache
if (-not $script:GTTokenCache)
{
    $script:GTTokenCache = @{
        AccessToken  = $null
        RefreshToken = $null
        ExpiresAt    = [DateTime]::MinValue
        TenantId     = $null
        ClientId     = $null
        Scope        = $null
        AuthType     = $null
        Claims       = $null
        Roles        = @()
        Permissions  = @()
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
        - Client Secret-based Client Credentials (supporting both String and SecureString)
        - Azure Managed Identity (System-Assigned and User-Assigned)
        - Silent token renewal via OAuth 2.0 refresh_token
        - Direct Bearer token passthrough
        - In-memory caching with a sliding expiration buffer to prevent redundant calls and throttling (HTTP 429).

    .PARAMETER TenantId
        The Microsoft Entra ID Tenant ID (Directory ID) or authority domain.

    .PARAMETER ClientId
        The Application (Client) ID of the registered App.

    .PARAMETER Thumbprint
        The SHA-1 thumbprint of an X.509 certificate in Cert:\LocalMachine\My or Cert:\CurrentUser\My.

    .PARAMETER Certificate
        An explicit [System.Security.Cryptography.X509Certificates.X509Certificate2] object.

    .PARAMETER ClientSecret
        The client secret for application authentication. Supports [string] or [System.Security.SecureString].

    .PARAMETER AccessToken
        Direct access token string to store and use.

    .PARAMETER Identity
        Acquires token via Azure Managed Identity (MSI).

    .PARAMETER IdentityId
        Identifier for a User-Assigned Managed Identity.

    .PARAMETER IdentityType
        Specifies how IdentityId is interpreted ('ClientId', 'ResourceId', 'PrincipalId'). Defaults to 'ClientId'.

    .PARAMETER RefreshToken
        An OAuth 2.0 refresh token string used to acquire a fresh access token.

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
        Get-GTCachedGraphToken -Identity

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
        [object]$ClientSecret,

        [Parameter(ParameterSetName = 'DirectToken', Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(ParameterSetName = 'Identity', Mandatory = $true)]
        [switch]$Identity,

        [Parameter(ParameterSetName = 'Identity')]
        [string]$IdentityId,

        [Parameter(ParameterSetName = 'Identity')]
        [ValidateSet('ClientId', 'ResourceId', 'PrincipalId')]
        [string]$IdentityType = 'ClientId',

        [Parameter(ParameterSetName = 'RefreshToken', Mandatory = $true)]
        [string]$RefreshToken,

        [Parameter(ParameterSetName = 'Certificate')]
        [Parameter(ParameterSetName = 'CertObject')]
        [Parameter(ParameterSetName = 'ClientSecret')]
        [Parameter(ParameterSetName = 'Identity')]
        [Parameter(ParameterSetName = 'RefreshToken')]
        [Parameter(ParameterSetName = 'SessionConfig')]
        [string]$Scope = 'https://graph.microsoft.com/.default',

        [Parameter(ParameterSetName = 'Certificate')]
        [Parameter(ParameterSetName = 'CertObject')]
        [Parameter(ParameterSetName = 'ClientSecret')]
        [Parameter(ParameterSetName = 'Identity')]
        [Parameter(ParameterSetName = 'RefreshToken')]
        [Parameter(ParameterSetName = 'SessionConfig')]
        [int]$BufferMinutes = 5,

        [switch]$ForceRefresh
    )

    function ConvertTo-GTPlainSecret
    {
        param($Secret)
        if ($Secret -is [System.Security.SecureString])
        {
            return [System.Net.NetworkCredential]::new('', $Secret).Password
        }
        return [string]$Secret
    }

    function Set-GTTokenCacheEntry
    {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
        param(
            [string]$Token,
            [DateTime]$ExpiresAt,
            [string]$TenantId,
            [string]$ClientId,
            [string]$Scope,
            [string]$AuthType,
            [string]$RefreshToken
        )

        $claims = if (Get-Command Get-GTTokenClaims -ErrorAction SilentlyContinue)
        {
            Get-GTTokenClaims -Token $Token
        }
        else
        {
            $claimsFile = Join-Path $PSScriptRoot 'Get-GTTokenClaims.ps1'
            if (Test-Path $claimsFile)
            {
                . $claimsFile
                Get-GTTokenClaims -Token $Token
            }
            else
            {
                $null
            }
        }
        $permissions = [System.Collections.Generic.List[string]]::new()
        $roles = @()

        if ($claims)
        {
            if ($claims.PSObject.Properties['roles'] -and $claims.roles)
            {
                $roles = [string[]]$claims.roles
                foreach ($r in $roles) { $permissions.Add($r) }
            }
            if ($claims.PSObject.Properties['scp'] -and $claims.scp)
            {
                foreach ($s in ($claims.scp -split '\s+'))
                {
                    if (-not [string]::IsNullOrWhiteSpace($s) -and -not $permissions.Contains($s))
                    {
                        $permissions.Add($s)
                    }
                }
            }
            if (-not $TenantId -and $claims.PSObject.Properties['tid'])
            {
                $TenantId = [string]$claims.tid
            }
            if (-not $ClientId)
            {
                if ($claims.PSObject.Properties['appid']) { $ClientId = [string]$claims.appid }
                elseif ($claims.PSObject.Properties['azp']) { $ClientId = [string]$claims.azp }
            }
            if ($claims.PSObject.Properties['exp'] -and $claims.exp)
            {
                try
                {
                    $ExpiresAt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$claims.exp).UtcDateTime
                }
                catch
                {
                    # Retain calculated ExpiresAt on conversion error
                    $null = $_
                }
            }
        }

        if ($permissions.Count -eq 0 -and $Scope)
        {
            foreach ($s in ($Scope -split '\s+'))
            {
                if (-not [string]::IsNullOrWhiteSpace($s)) { $permissions.Add($s) }
            }
        }

        $script:GTTokenCache.AccessToken  = $Token
        $script:GTTokenCache.ExpiresAt    = $ExpiresAt
        $script:GTTokenCache.TenantId     = $TenantId
        $script:GTTokenCache.ClientId     = $ClientId
        $script:GTTokenCache.Scope        = $Scope
        $script:GTTokenCache.AuthType     = $AuthType
        $script:GTTokenCache.Claims       = $claims
        $script:GTTokenCache.Roles        = $roles
        $script:GTTokenCache.Permissions  = [string[]]$permissions

        if ($RefreshToken)
        {
            $script:GTTokenCache.RefreshToken = $RefreshToken
            if ($script:GTConnectionConfig)
            {
                $script:GTConnectionConfig.RefreshToken = $RefreshToken
            }
        }
    }

    # 1. Direct token assignment
    if ($PSCmdlet.ParameterSetName -eq 'DirectToken')
    {
        Set-GTTokenCacheEntry -Token $AccessToken `
                              -ExpiresAt ([DateTime]::UtcNow.AddHours(1)) `
                              -TenantId $TenantId `
                              -ClientId $ClientId `
                              -Scope $Scope `
                              -AuthType 'DirectToken'
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
            if (-not $RefreshToken -and $script:GTConnectionConfig.RefreshToken) { $RefreshToken = $script:GTConnectionConfig.RefreshToken }
            if (-not $Identity -and ($script:GTConnectionConfig.AuthType -eq 'Identity'))
            {
                $Identity = $true
                $IdentityId = $script:GTConnectionConfig.IdentityId
                $IdentityType = if ($script:GTConnectionConfig.IdentityType) { $script:GTConnectionConfig.IdentityType } else { 'ClientId' }
            }
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

    # 4. Managed Identity Acquisition / Renewal
    if ($Identity -or ($PSCmdlet.ParameterSetName -eq 'Identity'))
    {
        $idFn = Join-Path $PSScriptRoot 'Get-GTManagedIdentityToken.ps1'
        if (-not (Get-Command Get-GTManagedIdentityToken -ErrorAction SilentlyContinue) -and (Test-Path $idFn))
        {
            . $idFn
        }

        $idResult = Get-GTManagedIdentityToken -Resource 'https://graph.microsoft.com' -IdentityId $IdentityId -IdentityType $IdentityType
        Set-GTTokenCacheEntry -Token $idResult.AccessToken `
                              -ExpiresAt ([DateTime]::UtcNow.AddSeconds($idResult.ExpiresIn)) `
                              -TenantId $null `
                              -ClientId $IdentityId `
                              -Scope $Scope `
                              -AuthType 'Identity'

        Write-PSFMessage -Level Verbose -Message "Acquired new Microsoft Graph token via Managed Identity. Expires at $($script:GTTokenCache.ExpiresAt.ToString('u'))."
        return $script:GTTokenCache.AccessToken
    }

    # 5. Refresh Token Renewal (Delegated Interactive / Device Code flows)
    $hasRefreshToken = [bool]$RefreshToken -or ($null -ne $script:GTTokenCache.RefreshToken)
    $effectiveRefreshToken = if ($RefreshToken) { $RefreshToken } else { $script:GTTokenCache.RefreshToken }
    if ($hasRefreshToken -and $TenantId -and $ClientId -and ($PSCmdlet.ParameterSetName -in 'RefreshToken', 'SessionConfig'))
    {
        $renewFn = Join-Path $PSScriptRoot 'Invoke-GTRefreshTokenRenewal.ps1'
        if (-not (Get-Command Invoke-GTRefreshTokenRenewal -ErrorAction SilentlyContinue) -and (Test-Path $renewFn))
        {
            . $renewFn
        }

        try
        {
            $authType = if ($script:GTConnectionConfig -and $script:GTConnectionConfig.AuthType) { $script:GTConnectionConfig.AuthType } else { 'RefreshToken' }
            $renewResult = Invoke-GTRefreshTokenRenewal -TenantId $TenantId -ClientId $ClientId -RefreshToken $effectiveRefreshToken -Scope $Scope
            Set-GTTokenCacheEntry -Token $renewResult.AccessToken `
                                  -ExpiresAt ([DateTime]::UtcNow.AddSeconds($renewResult.ExpiresIn)) `
                                  -TenantId $TenantId `
                                  -ClientId $ClientId `
                                  -Scope $Scope `
                                  -AuthType $authType `
                                  -RefreshToken $renewResult.RefreshToken

            Write-PSFMessage -Level Verbose -Message "Silently renewed Microsoft Graph token via refresh_token ($authType). Expires at $($script:GTTokenCache.ExpiresAt.ToString('u'))."
            return $script:GTTokenCache.AccessToken
        }
        catch
        {
            Write-PSFMessage -Level Warning -Message "Refresh token renewal failed: $_"
            # If explicit RefreshToken parameter set, rethrow; otherwise fall through to credentials
            if ($PSCmdlet.ParameterSetName -eq 'RefreshToken')
            {
                throw
            }
        }
    }

    # 6. Validate that credentials exist to request a token
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

    # 7. Acquire token via Certificate (RFC 7523 Client Assertion)
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
    # 8. Acquire token via Client Secret (supports string or SecureString)
    elseif ($ClientSecret)
    {
        $plainSecret = ConvertTo-GTPlainSecret $ClientSecret
        $requestBody = @{
            client_id     = $ClientId
            client_secret = $plainSecret
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
        Set-GTTokenCacheEntry -Token $response.access_token `
                              -ExpiresAt ([DateTime]::UtcNow.AddSeconds([int]$response.expires_in)) `
                              -TenantId $TenantId `
                              -ClientId $ClientId `
                              -Scope $Scope `
                              -AuthType $authType

        Write-PSFMessage -Level Verbose -Message "Acquired new Microsoft Graph token ($authType). Expires at $($script:GTTokenCache.ExpiresAt.ToString('u'))."
        return $script:GTTokenCache.AccessToken
    }
    catch
    {
        Write-PSFMessage -Level Error -Message "Failed to acquire Microsoft Graph token: $_"
        throw
    }
}

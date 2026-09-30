function Connect-GTGraph
{
    <#
    .SYNOPSIS
        Connects to Microsoft Graph using zero-dependency OAuth 2.0 authentication.

    .DESCRIPTION
        Establishes an active Microsoft Graph session by authenticating via:
        - X.509 Certificate (RFC 7523 client assertion via local certificate store)
        - In-memory X509Certificate2 object
        - Client Secret (Application credentials, supporting both String and SecureString)
        - Azure Managed Identity (System-Assigned & User-Assigned)
        - Interactive Browser (Delegated OAuth 2.0 with PKCE via dynamic loopback HttpListener)
        - Device Code flow (Delegated OAuth 2.0 for headless/remote CLI)
        - Direct Access Token (Bearer token passthrough)

        Stores connection context in the module runspace and caches tokens in memory with an automatic
        sliding expiration buffer and silent refresh_token renewal. Supports optional DPAPI-encrypted
        refresh token persistence across PowerShell sessions via -PersistRefreshToken.

    .PARAMETER TenantId
        Microsoft Entra ID Directory (Tenant) ID or authority domain ('organizations', 'common', or GUID).

    .PARAMETER ClientId
        Microsoft Entra ID Application (Client) ID. Defaults to Microsoft Graph Command Line Tools client
        in Interactive and DeviceCode modes.

    .PARAMETER Thumbprint
        Thumbprint of the certificate located in Cert:\LocalMachine\My or Cert:\CurrentUser\My.

    .PARAMETER Certificate
        An explicit [System.Security.Cryptography.X509Certificates.X509Certificate2] object.

    .PARAMETER ClientSecret
        Client Secret for application authentication. Accepts [string] or [System.Security.SecureString].

    .PARAMETER Identity
        Connects using the current Azure Managed Identity (System-Assigned or User-Assigned).

    .PARAMETER IdentityId
        Identifier (ClientId, ResourceId, or PrincipalId) of a User-Assigned Managed Identity.

    .PARAMETER IdentityType
        Specifies how IdentityId is interpreted ('ClientId', 'ResourceId', 'PrincipalId'). Defaults to 'ClientId'.

    .PARAMETER Interactive
        Authenticates interactively via default web browser using OAuth 2.0 Authorization Code flow with PKCE.

    .PARAMETER LocalPort
        Local HTTP port for browser redirect callback in Interactive mode. Defaults to 0 (dynamic OS-assigned free port).

    .PARAMETER ForceConsent
        Forces the interactive consent prompt (prompt=consent) during interactive authentication.

    .PARAMETER PersistRefreshToken
        Opt-in switch to securely persist the refresh token to disk using DPAPI encryption (Windows)
        for silent re-authentication across PowerShell sessions.

    .PARAMETER DeviceCode
        Authenticates using OAuth 2.0 Device Authorization flow for headless or remote CLI environments.

    .PARAMETER AccessToken
        Direct Bearer token to use for subsequent requests.

    .PARAMETER Scope
        OAuth2 scope. Defaults to 'https://graph.microsoft.com/.default'.

    .PARAMETER PassThru
        Returns the connection summary object.

    .OUTPUTS
        [PSCustomObject]

    .EXAMPLE
        Connect-GTGraph -TenantId $TenantId -ClientId $ClientId -Thumbprint $Thumbprint

    .EXAMPLE
        Connect-GTGraph -TenantId $TenantId -ClientId $ClientId -ClientSecret $SecureSecret

    .EXAMPLE
        Connect-GTGraph -Identity

    .EXAMPLE
        Connect-GTGraph -Identity -IdentityId $userAssignedClientId

    .EXAMPLE
        Connect-GTGraph -Interactive -TenantId $TenantId

    .EXAMPLE
        Connect-GTGraph -Interactive -PersistRefreshToken

    .EXAMPLE
        Connect-GTGraph -DeviceCode -TenantId $TenantId

    .EXAMPLE
        Connect-GTGraph -AccessToken $token -PassThru
    #>
    [CmdletBinding(DefaultParameterSetName = 'Certificate')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'Certificate', Mandatory = $true)]
        [Parameter(ParameterSetName = 'CertObject', Mandatory = $true)]
        [Parameter(ParameterSetName = 'ClientSecret', Mandatory = $true)]
        [Parameter(ParameterSetName = 'Interactive', Mandatory = $false)]
        [Parameter(ParameterSetName = 'DeviceCode', Mandatory = $false)]
        [string]$TenantId = 'organizations',

        [Parameter(ParameterSetName = 'Certificate', Mandatory = $true)]
        [Parameter(ParameterSetName = 'CertObject', Mandatory = $true)]
        [Parameter(ParameterSetName = 'ClientSecret', Mandatory = $true)]
        [Parameter(ParameterSetName = 'Interactive', Mandatory = $false)]
        [Parameter(ParameterSetName = 'DeviceCode', Mandatory = $false)]
        [string]$ClientId = '14d82eec-204b-4a57-bc6d-141461f58e68',

        [Parameter(ParameterSetName = 'Certificate', Mandatory = $true)]
        [Alias('CertificateThumbprint')]
        [string]$Thumbprint,

        [Parameter(ParameterSetName = 'CertObject', Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(ParameterSetName = 'ClientSecret', Mandatory = $true)]
        [Alias('Secret')]
        [object]$ClientSecret,

        [Parameter(ParameterSetName = 'Identity', Mandatory = $true)]
        [switch]$Identity,

        [Parameter(ParameterSetName = 'Identity', Mandatory = $false)]
        [string]$IdentityId,

        [Parameter(ParameterSetName = 'Identity', Mandatory = $false)]
        [ValidateSet('ClientId', 'ResourceId', 'PrincipalId')]
        [string]$IdentityType = 'ClientId',

        [Parameter(ParameterSetName = 'Interactive', Mandatory = $true)]
        [switch]$Interactive,

        [Parameter(ParameterSetName = 'Interactive', Mandatory = $false)]
        [int]$LocalPort = 0,

        [Parameter(ParameterSetName = 'Interactive', Mandatory = $false)]
        [switch]$ForceConsent,

        [Parameter(ParameterSetName = 'Interactive', Mandatory = $false)]
        [Parameter(ParameterSetName = 'DeviceCode', Mandatory = $false)]
        [switch]$PersistRefreshToken,

        [Parameter(ParameterSetName = 'DeviceCode', Mandatory = $true)]
        [switch]$DeviceCode,

        [Parameter(ParameterSetName = 'AccessToken', Mandatory = $true)]
        [Alias('Token')]
        [string]$AccessToken,

        [Parameter(ParameterSetName = 'Certificate')]
        [Parameter(ParameterSetName = 'CertObject')]
        [Parameter(ParameterSetName = 'ClientSecret')]
        [Parameter(ParameterSetName = 'Identity')]
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'DeviceCode')]
        [string]$Scope = 'https://graph.microsoft.com/.default',

        [switch]$PassThru
    )

    $authType = $null
    $token = $null

    # 1. Managed Identity
    if ($Identity -or ($PSCmdlet.ParameterSetName -eq 'Identity'))
    {
        $idFn = Join-Path $PSScriptRoot '..\internal\functions\Get-GTManagedIdentityToken.ps1'
        if (-not (Get-Command Get-GTManagedIdentityToken -ErrorAction SilentlyContinue) -and (Test-Path $idFn))
        {
            . $idFn
        }

        $idResult = Get-GTManagedIdentityToken -Resource 'https://graph.microsoft.com' -IdentityId $IdentityId -IdentityType $IdentityType
        $token = $idResult.AccessToken

        $script:GTConnectionConfig = @{
            AuthType     = 'Identity'
            IdentityId   = $IdentityId
            IdentityType = $IdentityType
            Scope        = $Scope
        }

        # Cache token
        $null = Get-GTCachedGraphToken -Identity -IdentityId $IdentityId -IdentityType $IdentityType -Scope $Scope -ForceRefresh
        $authType = 'Identity'
    }
    # 2. Interactive Browser Auth with PKCE
    elseif ($Interactive -or ($PSCmdlet.ParameterSetName -eq 'Interactive'))
    {
        $silentSuccess = $false
        $candidateRefreshToken = $null

        # Attempt silent re-authentication via in-memory or persisted refresh token
        if (-not $ForceConsent)
        {
            if ($script:GTTokenCache -and $script:GTTokenCache.RefreshToken -and
                $script:GTTokenCache.TenantId -eq $TenantId -and $script:GTTokenCache.ClientId -eq $ClientId)
            {
                $candidateRefreshToken = $script:GTTokenCache.RefreshToken
            }
            else
            {
                $persistedFn = Join-Path $PSScriptRoot '..\internal\functions\Get-GTPersistedTokenCache.ps1'
                if (-not (Get-Command Get-GTPersistedTokenCache -ErrorAction SilentlyContinue) -and (Test-Path $persistedFn))
                {
                    . $persistedFn
                }
                if (Get-Command Get-GTPersistedTokenCache -ErrorAction SilentlyContinue)
                {
                    $persistedEntry = Get-GTPersistedTokenCache -TenantId $TenantId -ClientId $ClientId -AuthType 'Interactive'
                    if ($persistedEntry -and $persistedEntry.RefreshToken)
                    {
                        $candidateRefreshToken = $persistedEntry.RefreshToken
                    }
                }
            }

            if ($candidateRefreshToken)
            {
                $renewFn = Join-Path $PSScriptRoot '..\internal\functions\Invoke-GTRefreshTokenRenewal.ps1'
                if (-not (Get-Command Invoke-GTRefreshTokenRenewal -ErrorAction SilentlyContinue) -and (Test-Path $renewFn))
                {
                    . $renewFn
                }

                if (Get-Command Invoke-GTRefreshTokenRenewal -ErrorAction SilentlyContinue)
                {
                    try
                    {
                        Write-PSFMessage -Level Verbose -Message "Attempting silent interactive re-authentication using cached refresh token..."
                        $renewResult = Invoke-GTRefreshTokenRenewal -TenantId $TenantId -ClientId $ClientId -RefreshToken $candidateRefreshToken -Scope $Scope
                        $token = $renewResult.AccessToken

                        $script:GTConnectionConfig = @{
                            AuthType            = 'Interactive'
                            TenantId            = $TenantId
                            ClientId            = $ClientId
                            RefreshToken        = $renewResult.RefreshToken
                            Scope               = $Scope
                            LocalPort           = $LocalPort
                            PersistRefreshToken = [bool]$PersistRefreshToken
                        }

                        $tokenFile = Join-Path $PSScriptRoot '..\internal\functions\Get-GTCachedGraphToken.ps1'
                        if (-not (Get-Command Get-GTCachedGraphToken -ErrorAction SilentlyContinue) -and (Test-Path $tokenFile))
                        {
                            . $tokenFile
                        }

                        $null = Get-GTCachedGraphToken -AccessToken $renewResult.AccessToken
                        $script:GTTokenCache.AuthType = 'Interactive'
                        $script:GTTokenCache.TenantId = $TenantId
                        $script:GTTokenCache.ClientId = $ClientId
                        $script:GTTokenCache.Scope = $Scope
                        $script:GTTokenCache.ExpiresAt = [DateTime]::UtcNow.AddSeconds($renewResult.ExpiresIn)
                        $script:GTTokenCache.RefreshToken = $renewResult.RefreshToken

                        if ($PersistRefreshToken)
                        {
                            $saveCacheFn = Join-Path $PSScriptRoot '..\internal\functions\Save-GTPersistedTokenCache.ps1'
                            if (-not (Get-Command Save-GTPersistedTokenCache -ErrorAction SilentlyContinue) -and (Test-Path $saveCacheFn))
                            {
                                . $saveCacheFn
                            }
                            if (Get-Command Save-GTPersistedTokenCache -ErrorAction SilentlyContinue)
                            {
                                $null = Save-GTPersistedTokenCache -TenantId $TenantId -ClientId $ClientId -RefreshToken $renewResult.RefreshToken -Scope $Scope -AuthType 'Interactive'
                            }
                        }

                        $authType = 'Interactive'
                        $silentSuccess = $true
                        Write-PSFMessage -Level Verbose -Message "Silent interactive re-authentication succeeded."
                    }
                    catch
                    {
                        Write-PSFMessage -Level Verbose -Message "Silent re-authentication failed, falling back to browser flow: $_"
                    }
                }
            }
        }

        if (-not $silentSuccess)
        {
            $listenerFn = Join-Path $PSScriptRoot '..\internal\functions\Invoke-GTOAuthHttpListener.ps1'
            if (-not (Get-Command Invoke-GTOAuthHttpListener -ErrorAction SilentlyContinue) -and (Test-Path $listenerFn))
            {
                . $listenerFn
            }

            $authResult = Invoke-GTOAuthHttpListener -TenantId $TenantId `
                                                     -ClientId $ClientId `
                                                     -LocalPort $LocalPort `
                                                     -Scope $Scope `
                                                     -ForceConsent:$ForceConsent
            $token = $authResult.AccessToken

            $script:GTConnectionConfig = @{
                AuthType            = 'Interactive'
                TenantId            = $TenantId
                ClientId            = $ClientId
                RefreshToken        = $authResult.RefreshToken
                Scope               = $Scope
                LocalPort           = $LocalPort
                PersistRefreshToken = [bool]$PersistRefreshToken
            }

            # Cache token & refresh token directly
            $tokenFile = Join-Path $PSScriptRoot '..\internal\functions\Get-GTCachedGraphToken.ps1'
            if (-not (Get-Command Get-GTCachedGraphToken -ErrorAction SilentlyContinue) -and (Test-Path $tokenFile))
            {
                . $tokenFile
            }

            $null = Get-GTCachedGraphToken -AccessToken $authResult.AccessToken
            $script:GTTokenCache.AuthType = 'Interactive'
            $script:GTTokenCache.TenantId = $TenantId
            $script:GTTokenCache.ClientId = $ClientId
            $script:GTTokenCache.Scope = $Scope
            $script:GTTokenCache.ExpiresAt = [DateTime]::UtcNow.AddSeconds($authResult.ExpiresIn)
            if ($authResult.RefreshToken)
            {
                $script:GTTokenCache.RefreshToken = $authResult.RefreshToken

                if ($PersistRefreshToken)
                {
                    $saveCacheFn = Join-Path $PSScriptRoot '..\internal\functions\Save-GTPersistedTokenCache.ps1'
                    if (-not (Get-Command Save-GTPersistedTokenCache -ErrorAction SilentlyContinue) -and (Test-Path $saveCacheFn))
                    {
                        . $saveCacheFn
                    }
                    if (Get-Command Save-GTPersistedTokenCache -ErrorAction SilentlyContinue)
                    {
                        $null = Save-GTPersistedTokenCache -TenantId $TenantId -ClientId $ClientId -RefreshToken $authResult.RefreshToken -Scope $Scope -AuthType 'Interactive'
                    }
                }
            }

            $authType = 'Interactive'
        }
    }
    # 3. Device Code Flow
    elseif ($DeviceCode -or ($PSCmdlet.ParameterSetName -eq 'DeviceCode'))
    {
        $deviceFn = Join-Path $PSScriptRoot '..\internal\functions\Invoke-GTDeviceCodeFlow.ps1'
        if (-not (Get-Command Invoke-GTDeviceCodeFlow -ErrorAction SilentlyContinue) -and (Test-Path $deviceFn))
        {
            . $deviceFn
        }

        $authResult = Invoke-GTDeviceCodeFlow -TenantId $TenantId -ClientId $ClientId -Scope $Scope
        $token = $authResult.AccessToken

        $script:GTConnectionConfig = @{
            AuthType            = 'DeviceCode'
            TenantId            = $TenantId
            ClientId            = $ClientId
            RefreshToken        = $authResult.RefreshToken
            Scope               = $Scope
            PersistRefreshToken = [bool]$PersistRefreshToken
        }

        # Cache token & refresh token directly
        $tokenFile = Join-Path $PSScriptRoot '..\internal\functions\Get-GTCachedGraphToken.ps1'
        if (-not (Get-Command Get-GTCachedGraphToken -ErrorAction SilentlyContinue) -and (Test-Path $tokenFile))
        {
            . $tokenFile
        }

        $null = Get-GTCachedGraphToken -AccessToken $authResult.AccessToken
        $script:GTTokenCache.AuthType = 'DeviceCode'
        $script:GTTokenCache.TenantId = $TenantId
        $script:GTTokenCache.ClientId = $ClientId
        $script:GTTokenCache.Scope = $Scope
        $script:GTTokenCache.ExpiresAt = [DateTime]::UtcNow.AddSeconds($authResult.ExpiresIn)
        if ($authResult.RefreshToken)
        {
            $script:GTTokenCache.RefreshToken = $authResult.RefreshToken

            if ($PersistRefreshToken)
            {
                $saveCacheFn = Join-Path $PSScriptRoot '..\internal\functions\Save-GTPersistedTokenCache.ps1'
                if (-not (Get-Command Save-GTPersistedTokenCache -ErrorAction SilentlyContinue) -and (Test-Path $saveCacheFn))
                {
                    . $saveCacheFn
                }
                if (Get-Command Save-GTPersistedTokenCache -ErrorAction SilentlyContinue)
                {
                    $null = Save-GTPersistedTokenCache -TenantId $TenantId -ClientId $ClientId -RefreshToken $authResult.RefreshToken -Scope $Scope -AuthType 'DeviceCode'
                }
            }
        }

        $authType = 'DeviceCode'
    }
    # 4. Standard Certificate, ClientSecret, DirectToken flows
    else
    {
        if ($PSCmdlet.ParameterSetName -eq 'ClientSecret')
        {
            if ($null -eq $ClientSecret -or (-not ($ClientSecret -is [string]) -and -not ($ClientSecret -is [System.Security.SecureString])))
            {
                throw [System.ArgumentException]::new("ClientSecret must be a [string] or [System.Security.SecureString].", "ClientSecret")
            }
        }

        # Store global configuration
        $script:GTConnectionConfig = @{
            TenantId     = if ($AccessToken) { $null } else { $TenantId }
            ClientId     = if ($AccessToken) { $null } else { $ClientId }
            Thumbprint   = $Thumbprint
            Certificate  = $Certificate
            ClientSecret = $ClientSecret
            Scope        = $Scope
            AuthType     = if ($AccessToken) { 'DirectToken' } elseif ($Certificate -or $Thumbprint) { 'Certificate' } else { 'ClientSecret' }
        }

        # Validate and acquire initial token
        $tokenParams = @{ ForceRefresh = $true }
        if ($AccessToken)
        {
            $tokenParams['AccessToken'] = $AccessToken
        }
        elseif ($Certificate)
        {
            $tokenParams['TenantId']    = $TenantId
            $tokenParams['ClientId']    = $ClientId
            $tokenParams['Certificate'] = $Certificate
            $tokenParams['Scope']       = $Scope
        }
        elseif ($Thumbprint)
        {
            $tokenParams['TenantId']   = $TenantId
            $tokenParams['ClientId']   = $ClientId
            $tokenParams['Thumbprint'] = $Thumbprint
            $tokenParams['Scope']      = $Scope
        }
        elseif ($ClientSecret)
        {
            $tokenParams['TenantId']     = $TenantId
            $tokenParams['ClientId']     = $ClientId
            $tokenParams['ClientSecret'] = $ClientSecret
            $tokenParams['Scope']        = $Scope
        }

        $token = Get-GTCachedGraphToken @tokenParams
        $authType = if ($AccessToken) { 'DirectToken' } elseif ($Certificate -or $Thumbprint) { 'Certificate' } else { 'ClientSecret' }
    }

    Write-PSFMessage -Level Host -Message "Successfully connected to Microsoft Graph ($authType)."

    $summary = [PSCustomObject]@{
        PSTypeName           = 'GraphTools.Connection'
        TenantId             = if ($script:GTConnectionConfig -and $script:GTConnectionConfig.TenantId) { $script:GTConnectionConfig.TenantId } elseif ($script:GTTokenCache -and $script:GTTokenCache.TenantId) { $script:GTTokenCache.TenantId } else { $null }
        ClientId             = if ($script:GTConnectionConfig -and $script:GTConnectionConfig.ClientId) { $script:GTConnectionConfig.ClientId } elseif ($script:GTTokenCache -and $script:GTTokenCache.ClientId) { $script:GTTokenCache.ClientId } else { $null }
        AuthType             = $authType
        Scope                = $Scope
        ExpiresAt            = if ($script:GTTokenCache) { $script:GTTokenCache.ExpiresAt } else { $null }
        Connected            = ($null -ne $token)
        IdentityId           = if ($script:GTConnectionConfig -and $script:GTConnectionConfig.IdentityId) { $script:GTConnectionConfig.IdentityId } else { $null }
        IdentityType         = if ($script:GTConnectionConfig -and $script:GTConnectionConfig.IdentityType) { $script:GTConnectionConfig.IdentityType } else { $null }
        RefreshTokenPresent  = [bool]($script:GTTokenCache -and $script:GTTokenCache.RefreshToken)
    }

    if ($PassThru)
    {
        return $summary
    }
}

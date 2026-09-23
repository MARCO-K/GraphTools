function Connect-GTGraph
{
    <#
    .SYNOPSIS
        Connects to Microsoft Graph using zero-dependency OAuth 2.0 authentication.

    .DESCRIPTION
        Establishes an active Microsoft Graph session by authenticating via:
        - X.509 Certificate (RFC 7523 client assertion via local certificate store)
        - In-memory X509Certificate2 object
        - Client Secret (Application credentials)
        - Direct Access Token (Bearer token passthrough)

        Stores connection context in the module runspace and caches tokens in memory with an automatic sliding expiration buffer.

    .PARAMETER TenantId
        Microsoft Entra ID Directory (Tenant) ID.

    .PARAMETER ClientId
        Microsoft Entra ID Application (Client) ID.

    .PARAMETER Thumbprint
        Thumbprint of the certificate located in Cert:\LocalMachine\My or Cert:\CurrentUser\My.

    .PARAMETER Certificate
        An explicit [System.Security.Cryptography.X509Certificates.X509Certificate2] object.

    .PARAMETER ClientSecret
        Client Secret for application authentication.

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
        Connect-GTGraph -TenantId $TenantId -ClientId $ClientId -ClientSecret $Secret

    .EXAMPLE
        Connect-GTGraph -AccessToken $token -PassThru
    #>
    [CmdletBinding(DefaultParameterSetName = 'Certificate')]
    [OutputType([PSCustomObject])]
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

        [Parameter(ParameterSetName = 'AccessToken', Mandatory = $true)]
        [Alias('Token')]
        [string]$AccessToken,

        [Parameter(ParameterSetName = 'Certificate')]
        [Parameter(ParameterSetName = 'CertObject')]
        [Parameter(ParameterSetName = 'ClientSecret')]
        [string]$Scope = 'https://graph.microsoft.com/.default',

        [switch]$PassThru
    )

    # Store global configuration
    $script:GTConnectionConfig = @{
        TenantId     = $TenantId
        ClientId     = $ClientId
        Thumbprint   = $Thumbprint
        Certificate  = $Certificate
        ClientSecret = $ClientSecret
        Scope        = $Scope
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
    Write-PSFMessage -Level Host -Message "Successfully connected to Microsoft Graph ($authType)."

    $summary = [PSCustomObject]@{
        PSTypeName = 'GraphTools.Connection'
        TenantId   = $TenantId
        ClientId   = $ClientId
        AuthType   = $authType
        Scope      = $Scope
        ExpiresAt  = if ($script:GTTokenCache) { $script:GTTokenCache.ExpiresAt } else { $null }
        Connected  = ($null -ne $token)
    }

    if ($PassThru)
    {
        return $summary
    }
}

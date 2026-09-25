function Get-GTManagedIdentityToken
{
    <#
    .SYNOPSIS
        Acquires a Microsoft Graph token using Azure Managed Identity (MSI).
    .DESCRIPTION
        Acquires an OAuth 2.0 access token from Azure Instance Metadata Service (IMDS)
        or Azure App Service / Functions / Container Apps / Automation managed identity endpoints.
        Supports both System-Assigned and User-Assigned managed identities.
    .PARAMETER Resource
        The target resource URI. Defaults to 'https://graph.microsoft.com'.
    .PARAMETER IdentityId
        Identifier for a User-Assigned Managed Identity.
    .PARAMETER IdentityType
        Specifies how IdentityId is interpreted ('ClientId', 'ResourceId', 'PrincipalId').
        Defaults to 'ClientId'.
    .OUTPUTS
        [PSCustomObject] containing AccessToken and ExpiresIn (seconds).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$Resource = 'https://graph.microsoft.com',

        [Parameter()]
        [string]$IdentityId,

        [Parameter()]
        [ValidateSet('ClientId', 'ResourceId', 'PrincipalId')]
        [string]$IdentityType = 'ClientId'
    )

    if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER)
    {
        $endpoint = $env:IDENTITY_ENDPOINT
        $headers = @{ 'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER }
        $apiVersion = if ($env:IDENTITY_API_VERSION) { $env:IDENTITY_API_VERSION } else { '2019-08-01' }
    }
    elseif ($env:MSI_ENDPOINT -and $env:MSI_SECRET)
    {
        $endpoint = $env:MSI_ENDPOINT
        $headers = @{ 'X-IDENTITY-HEADER' = $env:MSI_SECRET }
        $apiVersion = '2019-08-01'
    }
    else
    {
        $endpoint = 'http://169.254.169.254/metadata/identity/oauth2/token'
        $headers = @{ Metadata = 'true' }
        $apiVersion = '2018-02-01'
    }

    $encodedResource = [System.Uri]::EscapeDataString($Resource)
    $queryDelimiter = if ($endpoint -match '\?') { '&' } else { '?' }
    $uri = "$endpoint$queryDelimiter`resource=$encodedResource&api-version=$apiVersion"
    if ($IdentityId)
    {
        $typeParamMap = @{
            ClientId    = 'client_id'
            ResourceId  = 'mi_res_id'
            PrincipalId = 'principal_id'
        }
        $paramName = $typeParamMap[$IdentityType]
        if (-not $paramName) { $paramName = 'client_id' }
        $uri += "&$paramName=$([System.Uri]::EscapeDataString($IdentityId))"
    }

    try
    {
        Write-PSFMessage -Level Verbose -Message "Requesting token from Managed Identity endpoint ($endpoint)..."
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET -ErrorAction Stop

        if (-not $response.access_token)
        {
            throw "Managed Identity endpoint response did not contain an access_token."
        }

        $expiresIn = if ($response.expires_in)
        {
            [int]$response.expires_in
        }
        elseif ($response.expires_on)
        {
            $epochNow = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            [Math]::Max(60, ([int64]$response.expires_on - $epochNow))
        }
        else
        {
            3600
        }

        return [PSCustomObject]@{
            AccessToken = $response.access_token
            ExpiresIn   = $expiresIn
        }
    }
    catch
    {
        Write-PSFMessage -Level Error -Message "Failed to acquire token via Managed Identity: $_"
        throw
    }
}

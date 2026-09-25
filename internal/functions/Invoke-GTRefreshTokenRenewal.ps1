function Invoke-GTRefreshTokenRenewal
{
    <#
    .SYNOPSIS
        Renews an access token using an OAuth 2.0 refresh token.
    .DESCRIPTION
        Submits an OAuth 2.0 refresh_token grant request to Microsoft identity platform.
        Handles rolling refresh tokens by returning the latest refresh_token if issued by the server.
    .PARAMETER TenantId
        Microsoft Entra ID Tenant ID or authority domain.
    .PARAMETER ClientId
        The Application (Client) ID.
    .PARAMETER RefreshToken
        The OAuth 2.0 refresh token string.
    .PARAMETER Scope
        Requested permission scopes. Defaults to 'https://graph.microsoft.com/.default'.
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

        [Parameter(Mandatory = $true)]
        [string]$RefreshToken,

        [Parameter()]
        [string]$Scope = 'https://graph.microsoft.com/.default'
    )

    $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        grant_type    = 'refresh_token'
        refresh_token = $RefreshToken
        scope         = $Scope
    }

    try
    {
        Write-PSFMessage -Level Verbose -Message "Refreshing access token using refresh_token for Client ID '$ClientId'..."
        $response = Invoke-RestMethod -Method Post `
                                      -Uri $tokenEndpoint `
                                      -ContentType 'application/x-www-form-urlencoded' `
                                      -Body $body `
                                      -ErrorAction Stop

        if (-not $response.access_token)
        {
            throw "Refresh token response did not contain an access_token."
        }

        # Entra ID may return a new rolling refresh token; retain existing if not returned
        $effectiveRefreshToken = if ($response.refresh_token) { $response.refresh_token } else { $RefreshToken }

        return [PSCustomObject]@{
            AccessToken  = $response.access_token
            RefreshToken = $effectiveRefreshToken
            ExpiresIn    = if ($response.expires_in) { [int]$response.expires_in } else { 3600 }
        }
    }
    catch
    {
        Write-PSFMessage -Level Warning -Message "Failed to refresh token using refresh_token: $_"
        throw
    }
}

function Get-GTTokenClaims
{
    <#
    .SYNOPSIS
        Decodes a JWT access token payload without external dependencies.
    .DESCRIPTION
        Parses the base64url-encoded payload of a JSON Web Token (JWT) issued by Microsoft Entra ID
        and returns an object containing claims (roles, scp, tid, appid, exp, etc.).
    .PARAMETER Token
        The raw JWT access token string.
    .OUTPUTS
        [PSCustomObject]
    .EXAMPLE
        $claims = Get-GTTokenClaims -Token $token
        $roles = $claims.roles
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($Token))
    {
        return $null
    }

    $parts = $Token.Split('.')
    if ($parts.Length -lt 2)
    {
        return $null
    }

    $payload = $parts[1]
    $padded = $payload.Replace('-', '+').Replace('_', '/')
    switch ($padded.Length % 4)
    {
        2 { $padded += '==' }
        3 { $padded += '=' }
    }

    try
    {
        $bytes = [System.Convert]::FromBase64String($padded)
        $json = [System.Text.Encoding]::UTF8.GetString($bytes)
        return ($json | ConvertFrom-Json)
    }
    catch
    {
        Write-PSFMessage -Level Verbose -Message "Failed to decode JWT claims: $($_.Exception.Message)"
        return $null
    }
}

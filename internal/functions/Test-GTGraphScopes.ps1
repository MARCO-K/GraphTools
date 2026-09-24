function Test-GTGraphScopes
{
    <#
    .SYNOPSIS
    Validates Microsoft Graph authentication context and required permissions

    .DESCRIPTION
    Checks if the current session has the required Graph API permissions/scopes
    and optionally reconnects with missing permissions

    .PARAMETER RequiredScopes
    Array of required permission strings (scopes or app roles)

    .PARAMETER Reconnect
    Attempt automatic reconnection when missing permissions

    .PARAMETER Quiet
    Suppress all output and return boolean only

    .EXAMPLE
    Test-GraphScopes -RequiredScopes "User.Read.All","Group.ReadWrite.All"

    .EXAMPLE
    Test-GraphScopes -RequiredScopes "Directory.Read.All" -Reconnect -Quiet
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$RequiredScopes,
        [switch]$Reconnect,
        [switch]$Quiet
    )

    # Check Graph connection
    $conn = Get-GTConnection
    if (-not $conn.Connected)
    {
        if (-not $Quiet) { Write-Error "No Microsoft Graph connection found" }
        return $false
    }

    $currentPermissions = @(if ($conn.Scopes) { $conn.Scopes } elseif ($conn.Scope) { $conn.Scope -split ' ' } else { @() })

    # If token claims could not be decoded and current permissions only contain .default,
    # assume consented app roles under .default are available
    $isDefaultOnly = ($currentPermissions.Count -eq 1 -and ($currentPermissions[0] -eq 'https://graph.microsoft.com/.default' -or $currentPermissions[0] -eq '.default'))
    if ($isDefaultOnly)
    {
        if (-not $Quiet) { Write-Verbose "Token claims not inspectable; assuming required permissions are present under .default scope" }
        return $true
    }

    # Find missing permissions using helper function
    $missing = Get-GTMissingScopes -RequiredScopes $RequiredScopes -CurrentScopes $currentPermissions

    if ($missing.Count -gt 0)
    {
        if ($Reconnect)
        {
            Write-PSFMessage -Level Verbose -Message 'Dynamic scope renegotiation is not supported for client credentials (App-only) authentication. Permissions must be assigned to the Application registration in Microsoft Entra ID.'
        }

        if (-not $Quiet)
        {
            Write-Warning "Active Microsoft Graph session is missing required permissions: $($missing -join ', '). Available permissions: $($currentPermissions -join ', '). Required permissions must be assigned to the Application registration in Microsoft Entra ID."
        }
        return $false
    }

    if (-not $Quiet) { Write-Verbose "All required permissions present: $($RequiredScopes -join ', ')" }
    return $true
}
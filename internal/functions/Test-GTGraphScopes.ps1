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

    $currentPermissions = if ($conn.Scopes) { $conn.Scopes } elseif ($conn.Scope) { $conn.Scope -split ' ' } else { @() }

    # If App-only (.default), all consented app roles are available
    $hasDefaultScope = ($currentPermissions -contains 'https://graph.microsoft.com/.default') -or ($currentPermissions -contains '.default')
    if ($hasDefaultScope)
    {
        if (-not $Quiet) { Write-Verbose "All required permissions present (.default scope)" }
        return $true
    }

    # Find missing permissions using helper function
    $missing = Get-GTMissingScopes -RequiredScopes $RequiredScopes -CurrentScopes $currentPermissions

    if ($missing.Count -gt 0)
    {
        if (-not $Quiet)
        {
            Write-Warning "Missing scopes: $($missing -join ', ')"
        }

        if ($Reconnect -and $script:GTConnectionConfig)
        {
            try
            {
                # Combine current scopes with all required scopes for reconnect
                $allScopes = ($currentPermissions + $RequiredScopes) | Select-Object -Unique
                $connectParams = @{
                    Scope = ($allScopes -join ' ')
                }
                if ($script:GTConnectionConfig.TenantId) { $connectParams['TenantId'] = $script:GTConnectionConfig.TenantId }
                if ($script:GTConnectionConfig.ClientId) { $connectParams['ClientId'] = $script:GTConnectionConfig.ClientId }
                if ($script:GTConnectionConfig.Thumbprint) { $connectParams['Thumbprint'] = $script:GTConnectionConfig.Thumbprint }
                if ($script:GTConnectionConfig.Certificate) { $connectParams['Certificate'] = $script:GTConnectionConfig.Certificate }
                if ($script:GTConnectionConfig.ClientSecret) { $connectParams['ClientSecret'] = $script:GTConnectionConfig.ClientSecret }

                $null = Connect-GTGraph @connectParams -ErrorAction Stop

                $newConn = Get-GTConnection
                if (-not $newConn.Connected)
                {
                    if (-not $Quiet) { Write-Error "Reconnection succeeded but connection validation failed" }
                    return $false
                }

                $newPermissions = if ($newConn.Scopes) { $newConn.Scopes } elseif ($newConn.Scope) { $newConn.Scope -split ' ' } else { @() }
                $stillMissing = Get-GTMissingScopes -RequiredScopes $RequiredScopes -CurrentScopes $newPermissions

                if ($stillMissing.Count -gt 0)
                {
                    if (-not $Quiet)
                    {
                        Write-Warning "Reconnection completed but some scopes were not granted: $($stillMissing -join ', ')"
                    }
                    return $false
                }

                if (-not $Quiet) { Write-Verbose "Successfully reconnected with all required permissions" }
                return $true
            }
            catch
            {
                if (-not $Quiet) { Write-Error "Reconnection failed: $_" }
                return $false
            }
        }
        return $false
    }

    if (-not $Quiet) { Write-Verbose "All required permissions present" }
    return $true
}
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
    $context = Get-MgContext
    if (-not $context)
    {
        if (-not $Quiet) { Write-Error "No Microsoft Graph connection found" }
        return $false
    }

    # Determine permission type (delegated vs application)
    $permissionType = if ($context.AuthType -eq 'Delegated') { 'Scopes' } else { 'AppRoles' }
    $currentPermissions = $context.$permissionType

    # Normalize case for comparison
    $required = $RequiredScopes.ForEach{ $_.ToLower() }
    $current = $currentPermissions.ForEach{ $_.ToLower() }

    # Find missing permissions
    $missing = $required | Where-Object { $_ -notin $current }

    if ($missing.Count -gt 0)
    {
        if (-not $Quiet)
        {
            Write-Error "Missing scopes: $($missing -join ', ')" -ErrorAction Continue
        }

        if ($Reconnect)
        {
            try
            {
                if ($permissionType -eq 'Scopes')
                {
                    # Combine current scopes with all required scopes for a seamless reconnect
                    $allScopes = ($context.Scopes + $RequiredScopes) | Select-Object -Unique
                    $null = Connect-MgGraph -Scopes $allScopes -NoWelcome -ErrorAction Stop
                    
                    # Post-reconnect verification: ensure all required permissions were granted
                    $newContext = Get-MgContext
                    if (-not $newContext)
                    {
                        if (-not $Quiet) { Write-Error "Reconnection succeeded but context validation failed" }
                        return $false
                    }
                    
                    # Verify all required scopes are present in the new context
                    $newCurrent = $newContext.Scopes.ForEach{ $_.ToLower() }
                    $stillMissing = $required | Where-Object { $_ -notin $newCurrent }
                    
                    if ($stillMissing.Count -gt 0)
                    {
                        if (-not $Quiet)
                        {
                            Write-Warning "Reconnection completed but some scopes were not granted: $($stillMissing -join ', ')"
                        }
                        return $false
                    }
                }
                else
                {
                    if (-not $Quiet)
                    {
                        Write-Warning "Application permissions require manual reconnection"
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
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
                    $null = Connect-MgGraph -Scopes $RequiredScopes -NoWelcome -ErrorAction Stop
                }
                else
                {
                    if (-not $Quiet)
                    {
                        Write-Warning "Application permissions require manual reconnection"
                    }
                    return $false
                }
                
                if (-not $Quiet) { Write-Verbose "Successfully reconnected" }
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
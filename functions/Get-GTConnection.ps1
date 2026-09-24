function Get-GTConnection
{
    <#
    .SYNOPSIS
        Gets the current Microsoft Graph connection state and cached token status.

    .DESCRIPTION
        Inspects the active session configuration and in-memory token cache,
        returning details about the connected tenant, client ID, authentication type,
        and token validity.

    .OUTPUTS
        [PSCustomObject]

    .EXAMPLE
        Get-GTConnection
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $now = [DateTime]::UtcNow
    $hasToken = ($null -ne $script:GTTokenCache -and -not [string]::IsNullOrWhiteSpace($script:GTTokenCache.AccessToken))
    $isValid = ($hasToken -and ($script:GTTokenCache.ExpiresAt -gt $now))

    $tenantId = if ($script:GTConnectionConfig) { $script:GTConnectionConfig.TenantId } elseif ($script:GTTokenCache) { $script:GTTokenCache.TenantId } else { $null }
    $clientId = if ($script:GTConnectionConfig) { $script:GTConnectionConfig.ClientId } elseif ($script:GTTokenCache) { $script:GTTokenCache.ClientId } else { $null }
    $authType = if ($script:GTTokenCache) { $script:GTTokenCache.AuthType } else { $null }
    $scope    = if ($script:GTConnectionConfig) { $script:GTConnectionConfig.Scope } elseif ($script:GTTokenCache) { $script:GTTokenCache.Scope } else { $null }
    $expires  = if ($script:GTTokenCache) { $script:GTTokenCache.ExpiresAt } else { $null }

    $permissions = if ($script:GTTokenCache -and $script:GTTokenCache.Permissions -and $script:GTTokenCache.Permissions.Count -gt 0)
    {
        [string[]]$script:GTTokenCache.Permissions
    }
    elseif ($scope)
    {
        @($scope -split ' ')
    }
    else
    {
        @()
    }

    $roles = if ($script:GTTokenCache -and $script:GTTokenCache.Roles)
    {
        [string[]]$script:GTTokenCache.Roles
    }
    else
    {
        @()
    }

    [PSCustomObject]@{
        PSTypeName = 'GraphTools.ConnectionStatus'
        Connected  = $isValid
        TenantId   = $tenantId
        ClientId   = $clientId
        AuthType   = $authType
        Scope      = $scope
        Scopes     = $permissions
        Roles      = $roles
        ExpiresAt  = $expires
        TimeUtc    = $now.ToString('o')
    }
}

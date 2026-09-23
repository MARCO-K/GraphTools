function Disconnect-GTGraph
{
    <#
    .SYNOPSIS
        Disconnects the active Microsoft Graph session and clears cached tokens.

    .DESCRIPTION
        Clears cached credentials, tokens, and session context from the module runspace.

    .PARAMETER PassThru
        Returns the disconnection summary object.

    .OUTPUTS
        [PSCustomObject]

    .EXAMPLE
        Disconnect-GTGraph
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [switch]$PassThru
    )

    $script:GTConnectionConfig = $null
    $script:GTTokenCache = @{
        AccessToken = $null
        ExpiresAt   = [DateTime]::MinValue
        TenantId    = $null
        ClientId    = $null
        Scope       = $null
        AuthType    = $null
    }

    Write-PSFMessage -Level Verbose -Message 'Microsoft Graph session disconnected and token cache cleared.'

    $summary = [PSCustomObject]@{
        PSTypeName = 'GraphTools.DisconnectSummary'
        Status     = 'Disconnected'
        TimeUtc    = [DateTime]::UtcNow.ToString('o')
    }

    if ($PassThru)
    {
        return $summary
    }
}

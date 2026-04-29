function Initialize-GTBeginBlock {
    <#
    .SYNOPSIS
    Standardizes common begin-block Graph initialization steps.

    .DESCRIPTION
    Installs required modules, optionally validates scopes, and optionally initializes
    a Graph connection for the calling function.

    .PARAMETER ModuleNames
    Module names to install via Install-GTRequiredModule.

    .PARAMETER RequiredScopes
    Scopes required by the operation.

    .PARAMETER ValidateScopes
    When set, validates scopes using Test-GTGraphScopes.

    .PARAMETER InitializeConnection
    When set, initializes Graph connection using Initialize-GTGraphConnection.

    .PARAMETER NewSession
    Passed to Initialize-GTGraphConnection when InitializeConnection is set.

    .PARAMETER ScopeValidationErrorMessage
    Error text emitted when scope validation fails.

    .PARAMETER ConnectionErrorMessage
    Error text emitted when Graph connection initialization fails.

    .OUTPUTS
    System.Boolean

    .EXAMPLE
    Initialize-GTBeginBlock -ModuleNames @('Microsoft.Graph.Users') -RequiredScopes @('User.Read.All') -ValidateScopes
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ModuleNames,

        [Parameter(Mandatory = $true)]
        [string[]]$RequiredScopes,

        [switch]$ValidateScopes,

        [switch]$InitializeConnection,

        [switch]$NewSession,

        [string]$ScopeValidationErrorMessage = "Failed to acquire required permissions ($($RequiredScopes -join ', ')). Aborting.",

        [string]$ConnectionErrorMessage = 'Failed to initialize session.'
    )

    Install-GTRequiredModule -ModuleNames $ModuleNames -Verbose:$VerbosePreference

    if ($ValidateScopes) {
        if (-not (Test-GTGraphScopes -RequiredScopes $RequiredScopes -Reconnect:$true -Quiet:$true)) {
            Write-Error $ScopeValidationErrorMessage
            return $false
        }
    }

    if ($InitializeConnection) {
        if ($NewSession) {
            Write-PSFMessage -Level Verbose -Message 'NewSession requested: attempting reconnection.'
        }

        if (-not (Initialize-GTGraphConnection -Scopes $RequiredScopes -NewSession:$NewSession)) {
            Write-Error $ConnectionErrorMessage
            return $false
        }
    }

    return $true
}

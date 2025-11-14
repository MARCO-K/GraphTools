<#
.SYNOPSIS
    Signs a user out from all sessions.
.DESCRIPTION
    This function revokes all refresh tokens for a user, effectively signing them out from all applications and devices.
.PARAMETER UPN
    The User Principal Name of the user to sign out.

    Aliases: UserPrincipalName, Users, UserName, UPNName
.PARAMETER NewSession
    If specified, a new Microsoft Graph session will be created.
.EXAMPLE
    Revoke-GTSignOutFromAllSessions -UPN "test.user@example.com"

    Signs out the user from all sessions using the UPN parameter.
.EXAMPLE
    Revoke-GTSignOutFromAllSessions -UserPrincipalName "test.user@example.com"

    Signs out the user from all sessions using the UserPrincipalName alias.
.EXAMPLE
    Revoke-GTSignOutFromAllSessions -UserName "test.user@example.com"

    Signs out the user from all sessions using the UserName alias.
#>
function Revoke-GTSignOutFromAllSessions
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateScript({$_ -match $script:GTValidationRegex.UPN})]
        [Alias('UserPrincipalName','Users','UserName','UPNName')]
        [string]$UPN,

        [Switch]$NewSession
    )

    Begin {
        # Module Management
        $modules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users.Actions')
        Install-GTRequiredModule -ModuleNames $modules -Verbose

        # Graph Connection Handling
        if (-not (Initialize-GTGraphConnection -Scopes 'User.ReadWrite.All' -NewSession:$NewSession)) {
            throw "Failed to establish Microsoft Graph connection"
        }
    }
    Process {
        try
        {
            $user = Get-MgUser -UserId $UPN
            if ($user) {
                Revoke-MgUserSignInSession -UserId $user.Id
                Write-PSFMessage -Level Verbose -Message "$($UPN) - Sign out from all sessions action - User signed out"
            } else {
                Write-PSFMessage -Level Warning -Message "$($UPN) - User not found."
            }
        }
        catch
        {
            # Use centralized error handling helper to parse Graph API exceptions
            $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'user'
            
            # Log appropriate message based on error details
            if ($errorDetails.HttpStatus -in 404, 403) {
                Write-PSFMessage -Level $errorDetails.LogLevel -Message "$UPN - Sign out from all sessions action - $($errorDetails.Reason)"
                Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
            }
            elseif ($errorDetails.HttpStatus) {
                Write-PSFMessage -Level $errorDetails.LogLevel -Message "$UPN - Sign out from all sessions action - $($errorDetails.Reason)"
            }
            else {
                Write-PSFMessage -Level Error -Message "$UPN - Sign out from all sessions action - $($errorDetails.ErrorMessage)"
            }
        }
    }
    End {
    }
}
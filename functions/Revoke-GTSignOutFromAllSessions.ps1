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
        Initialize-GTGraphConnection -Scopes 'User.ReadWrite.All' -NewSession:$NewSession
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
            $ErrorLog = "$($UPN) - Sign out from all sessions action - " + $Error[0].Exception.Message
            Write-PSFMessage -Level Error -Message $ErrorLog
        }
    }
    End {
    }
}
<#
.SYNOPSIS
    Signs a user out from all sessions.
.DESCRIPTION
    This function revokes all refresh tokens for a user, effectively signing them out from all applications and devices.
.PARAMETER UPN
    The User Principal Name of the user to sign out.
.EXAMPLE
    PS C:\> Revoke-GTSignOutFromAllSessions -UPN "test.user@example.com"
    This command signs out the user with the UPN "test.user@example.com" from all sessions.
#>
function Revoke-GTSignOutFromAllSessions
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateScript({ Test-GTUPN -UPN $_ })]
        [string]$UPN
    )

    Begin {
        # Module Management
        $modules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users.Actions')
        Install-GTRequiredModule -ModuleNames $modules -Verbose

        # Graph Connection Handling
        try
        {
            if ($NewSession)
            {
                Write-PSFMessage -Level 'Verbose' -Message 'Close existing Microsoft Graph session.'
                Disconnect-MgGraph -ErrorAction SilentlyContinue
            }

            $context = Get-MgContext
            if (-not $context)
            {
                Write-PSFMessage -Level 'Verbose' -Message 'No Microsoft Graph context found. Attempting to connect.'
                Connect-MgGraph -Scopes 'User.ReadWrite.All' -NoWelcome -ErrorAction Stop
            }
        }
        catch
        {
            Write-PSFMessage -Level 'Error' -Message 'Failed to connect to Microsoft Graph.'
            throw "Graph connection failed: $_"
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
            $ErrorLog = "$($UPN) - Sign out from all sessions action - " + $Error[0].Exception.Message
            Write-PSFMessage -Level Error -Message $ErrorLog
        }
    }
    End {
    }
}
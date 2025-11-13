<#
.SYNOPSIS
    Resets user passwords in Microsoft Entra ID (Azure AD)
.DESCRIPTION
    Resets one or more user passwords to a randomly generated password.
    This function requires Microsoft.Graph.Authentication and Microsoft.Graph.Beta.Users modules.
    It validates UPN format and manages Microsoft Graph connection automatically.
    The password reset signals applications supporting Continuous Access Evaluation (CAE) to terminate active sessions.
.PARAMETER UPN
    One or more User Principal Names (UPNs) to reset passwords for. Must be in valid email format.
    
    Aliases: UserPrincipalName, Users, UserName, UPNName
.PARAMETER NewSession
    If specified, creates a new Microsoft Graph session by disconnecting any existing session first.
.EXAMPLE
    Reset-GTUserPassword -UPN 'user1@contoso.com'

    Resets password for a single user account using the UPN parameter.
.EXAMPLE
    Reset-GTUserPassword -UserPrincipalName 'user1@contoso.com'

    Resets password for a single user account using the UserPrincipalName alias.
.EXAMPLE
    Reset-GTUserPassword -UPN 'user1@contoso.com','user2@contoso.com'

    Resets passwords for multiple user accounts.
.EXAMPLE
    Reset-GTUserPassword -Users 'user1@contoso.com','user2@contoso.com'

    Resets passwords for multiple user accounts using the Users alias.
.EXAMPLE
    $users | Reset-GTUserPassword

    Resets passwords for users from pipeline input.
#>
Function Reset-GTUserPassword
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateScript({$_ -match $script:GTValidationRegex.UPN})]
        [Alias('UserPrincipalName','Users','UserName','UPNName')]
        [string[]]$UPN,

        [Switch]$NewSession
    )

    begin
    {
        # Module Management
        $modules = ('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Users')
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

    process
    {
        foreach ($User in $UPN)
        {
            try
            {
                $Password = New-GTPassword

                $Passwordprofile = @{
                    forceChangePasswordNextSignIn = $true
                    password                      = $Password
                }

                Update-MgBetaUser -UserId $User -PasswordProfile $Passwordprofile -ErrorAction Stop
                Write-PSFMessage -Level Verbose -Message "$User - Reset Password Action - Password reset to random value"
            }
            catch
            {
                Write-PSFMessage -Level Error -Message "$User - Reset Password Action - $($_.Exception.Message)"
            }
        }
    }

    end
    {
    }
}

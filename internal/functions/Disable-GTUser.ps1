<#
.SYNOPSIS
    Disables user accounts in Microsoft Entra ID (Azure AD)
.DESCRIPTION
    Disables one or more user accounts by setting the AccountEnabled property to false.
    This function requires Microsoft.Graph.Authentication and Microsoft.Graph.Beta.Users modules.
.PARAMETER UPN
    One or more User Principal Names (UPNs) to disable
.EXAMPLE
    Disable-GTUser -UPN 'user1@contoso.com'
    
    Disables a single user account
.EXAMPLE
    Disable-GTUser -UPN 'user1@contoso.com','user2@contoso.com'
    
    Disables multiple user accounts
.EXAMPLE
    $users | Disable-GTUser
    
    Disables users from pipeline input
#>
Function Disable-GTUser
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$UPN
    )

    begin
    {
        # Module Management
        $modules = ('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Users')
        Install-GTRequiredModule -ModuleNames $modules -Verbose
    }
    process
    {
        foreach ($User in $UPN)
        {
            try
            {
                Update-MgBetaUser -UserId $User -AccountEnabled:$false -ErrorAction Stop
                Write-PSFMessage -Level Verbose -Message "$User - Disable User Action - User Disabled"
            }
            catch
            {
                Write-PSFMessage -Level Error -Message "$User - Disable User Action - $($_.Exception.Message)"
            }
        }
    }
    end
    {
    }
}
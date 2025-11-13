<#
.SYNOPSIS
    Disables user accounts in Microsoft Entra ID (Azure AD)
.DESCRIPTION
    Disables one or more user accounts by setting the AccountEnabled property to false.
    This function requires Microsoft.Graph.Authentication and Microsoft.Graph.Beta.Users modules.
    It validates UPN format and manages Microsoft Graph connection automatically.
.PARAMETER UPN
    One or more User Principal Names (UPNs) to disable. Must be in valid email format.
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
        [ValidateScript({$_ -match $script:GTValidationRegex.UPN})]
        [Alias('UserPrincipalName','Users','User','UserName','UPNName')]
        [string[]]$UPN
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
                Connect-MgGraph -Scopes $Scope -NoWelcome -ErrorAction Stop
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
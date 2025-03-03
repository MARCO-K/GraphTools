Function Disable-GTUser
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string[]]$UPN
    )

    begin
    {
        # Module Management
        $modules = ('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Users')
        Install-RequiredModule -ModuleNames $modules -Verbose
    }
    process
    {

        try
        {
            foreach ($User in $UPN)
            {
                Update-MgBetaUser -UserId $User -AccountEnabled:$false
                Write-PSFMessage -Level Verbose -Message "$($User) - Disable User Action - User Disabled"
            }
        }
        catch
        {
            $ErrorLog = "$($User) - Disable User Action - $($Error[0].Exception.Message)"
            Write-PSFMessage -Level Error -Message $ErrorLog
        }
    }
    end
    {
    }
}
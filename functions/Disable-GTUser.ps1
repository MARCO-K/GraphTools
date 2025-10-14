Function Disable-GTUser
{
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateScript({$_ -match $script:GTValidationRegex.UPN})]
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

        try
        {
            foreach ($User in $UPN)
            {
                Update-MgBetaUser -UserId $UPN -AccountEnabled:$false
                Write-PSFMessage -Level Verbose -Message "$($UPN) - Disable User Action - User Disabled"
            }
        }
        catch
        {
            $ErrorLog = "$($UPN) - Disable User Action - " + $Error[0].Exception.Message
            Write-PSFMessage -Level Error -Message $ErrorLog
        }
    }
    end
    {
    }
}
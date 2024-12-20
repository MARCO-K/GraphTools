function Get-M365LicenceOverview
{

    [CmdletBinding(DefaultParameterSetName = 'All')]
    param (
        [Parameter(ParameterSetName = "SKU")]
        [string]$FilterLicenceSKU,

        [Parameter(ParameterSetName = "ServicePlan")]
        [string]$FilterServicePlan,

        [Parameter(ParameterSetName = "User")]
        [string]$FilterUser,

        [Parameter(ParameterSetName = "User")]
        [int]$LastLogin,

        [Switch]$NewSession,

        [string[]]$Scopes = ('User.Read.All', 'Organization.Read.All')
    )

    Begin
    {

        # Ensure required modules are imported
        $requiredModules = @(
            'Microsoft.Graph.Beta.Users',
            'Microsoft.Graph.Beta.Identity.DirectoryManagement'
        )

        foreach ($module in $requiredModules)
        {
            if (-not (Get-Module -Name $module -ListAvailable))
            {
                Write-PSFMessage -Level 'Verbose' -Message "Module '$module' is not installed. Please install it before running this function."
                return
            }
            Import-Module -Name $module -Global -WarningAction SilentlyContinue | Out-Null
        }

        if ($NewSession)
        {
            Write-PSFMessage -Level 'Verbose' -Message 'Close existing Microsoft Graph session.'
            Disconnect-MgGraph
        }

        $mgContext = Get-MgContext
        if (-not $mgContext.Account -or -not $mgContext.TenantId)
        {
            try
            {
                Write-PSFMessage -Level 'Verbose' -Message 'No Microsoft Graph context found. Attempting to connect.'
                Connect-MgGraph -Scopes $Scopes -NoWelcome
            }
            catch
            {
                Write-PSFMessage -Level 'Error' -Message 'Failed to connect to Microsoft Graph.'
                return
            }
        }


        try
        {
            $learnUrl = 'https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference'
            $learnPage = Invoke-WebRequest -Uri $learnUrl -UseBasicParsing
            $csvLink = $learnPage.Links | Where-Object Href -Match 'licensing.csv' | Select-Object -First 1 -ExpandProperty Href
            $csvlink = ((Invoke-WebRequest -Uri $link -UseBasicParsing).Links | where-Object Href -Match 'CSV').href
            $csv = Invoke-WebRequest -Uri $csvlink
            $skucsv = [System.Text.Encoding]::UTF8.GetString($csv.RawContentStream.ToArray()) | ConvertFrom-Csv -Delimiter ','
        } 
        catch
        {
            Write-PSFMessage -Level 'Error' -Message 'Failed to retrieve license overview from Microsoft.'
            break
        }

        # Retrieve users based on parameters
        try
        {
            switch ($PSCmdlet.ParameterSetName)
            {
                'User'
                {
                    if ($LastLogin)
                    {
                        $filter = "signInActivity/lastSignInDateTime ge $([datetime]::UtcNow.AddDays(-$LastLogin).ToString('s'))Z"
                        $users = Get-MgBetaUser -Filter $filter -All -Property Id, UserPrincipalName, DisplayName, SignInActivity
                    }
                    else
                    {
                        $users = Get-MgBetaUser -Filter "UserPrincipalName -like '$FilterUser'" -All -Property Id, UserPrincipalName, DisplayName, SignInActivity
                    }
                }
                Default
                {
                    $users = Get-MgBetaUser -All -Property Id, UserPrincipalName, DisplayName, SignInActivity
                }
            }
        }
        catch
        {
            Write-PSFMessage -Level Error -Message "Failed to retrieve users: $_"
            return
        }
    }

    Process
    {
        $UsersLicenses = foreach ($user in $users)
        {

            $Licenses = Get-MgBetaUserLicenseDetail -UserId $user.UserPrincipalname
            if ($licences)
            {
                Write-PSFMessage -Level 'Verbose' -Message ("Processing user {0}" -f $user.UserPrincipalName) 
                foreach ($License in $Licenses)
                {
                    # Get SKU friendly name
                    $SKUfriendlyname = $skucsv | Where-Object String_Id -Contains $License.SkuPartNumber | Select-Object -First 1
                    # Get service plans for the SKU
                    $SKUserviceplan = $skucsv | Where-Object GUID -Contains $License.SkuId

                    foreach ($serviceplan in $SKUserviceplan)
                    {
                        # Apply filters if specified
                        if ($FilterLicenceSKU)
                        {
                            if ($SKUfriendlyname.Product_Display_Name -match $FilterLicenceSKU )
                            {
                                [PSCustomObject][ordered]@{
                                    User                      = $User.UserPrincipalName
                                    LicenseSKU                = $SKUfriendlyname.Product_Display_Name
                                    Serviceplan               = $serviceplan.Service_Plans_Included_Friendly_Names
                                    AppliesTo                 = ($licenses.ServicePlans | Where-Object ServicePlanId -eq $serviceplan.Service_Plan_Id).AppliesTo | Select-Object -First 1
                                    ProvisioningStatus        = ($licenses.ServicePlans | Where-Object ServicePlanId -eq $serviceplan.Service_Plan_Id).ProvisioningStatus | Select-Object -First 1
                                    LastInteractiveSignIn     = $User.SignInActivity.LastSignInDateTime
                                    LastNonInteractiveSignin  = $User.SignInActivity.LastNonInteractiveSignInDateTime
                                    LastSuccessfullSignInDate = $User.SignInActivity.LastSuccessfulSignInDateTime
                                }
                            }
                        }
                        elseif ($FilterServicePlan)
                        {
                            if ($serviceplan.Service_Plans_Included_Friendly_Names -match $FilterServicePlan)
                            {
                                [PSCustomObject][ordered]@{
                                    User                      = $User.UserPrincipalName
                                    LicenseSKU                = $SKUfriendlyname.Product_Display_Name
                                    Serviceplan               = $serviceplan.Service_Plans_Included_Friendly_Names
                                    AppliesTo                 = ($licenses.ServicePlans | Where-Object ServicePlanId -eq $serviceplan.Service_Plan_Id).AppliesTo | Select-Object -First 1
                                    ProvisioningStatus        = ($licenses.ServicePlans | Where-Object ServicePlanId -eq $serviceplan.Service_Plan_Id).ProvisioningStatus | Select-Object -First 1
                                    LastInteractiveSignIn     = $User.SignInActivity.LastSignInDateTime
                                    LastNonInteractiveSignin  = $User.SignInActivity.LastNonInteractiveSignInDateTime
                                    LastSuccessfullSignInDate = $User.SignInActivity.LastSuccessfulSignInDateTime
                                }
                            }
                        }
                        else
                        {
                            [PSCustomObject][ordered]@{
                                User                      = $User.UserPrincipalName
                                LicenseSKU                = $SKUfriendlyname.Product_Display_Name
                                Serviceplan               = $serviceplan.Service_Plans_Included_Friendly_Names
                                AppliesTo                 = ($licenses.ServicePlans | Where-Object ServicePlanId -eq $serviceplan.Service_Plan_Id).AppliesTo | Select-Object -First 1
                                ProvisioningStatus        = ($licenses.ServicePlans | Where-Object ServicePlanId -eq $serviceplan.Service_Plan_Id).ProvisioningStatus | Select-Object -First 1
                                LastInteractiveSignIn     = $User.SignInActivity.LastSignInDateTime
                                LastNonInteractiveSignin  = $User.SignInActivity.LastNonInteractiveSignInDateTime
                                LastSuccessfullSignInDate = $User.SignInActivity.LastSuccessfulSignInDateTime
                            }
                        }
                    }
                }
            }
        }
    }

    End
    {
        Write-PSFMessage -Level 'Verbose' -Message 'Output all license information'
        if ($UsersLicenses.count -gt 0)
        {
            $UsersLicenses
        }

        else
        {
            Write-PSFMessage -Level  'Error' -Message 'No licenses found, check permissions and/or -Filter value'
        }
    }
}

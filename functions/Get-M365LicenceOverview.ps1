<#
.SYNOPSIS
    Retrieves Microsoft 365 license information with detailed service plan analysis
.DESCRIPTION
    This function provides a comprehensive view of user licenses and service plans across the organization
.PARAMETER FilterLicenseSKU
    Filters results by specific license SKU
.PARAMETER FilterServicePlan
    Filters results by service plan name
.PARAMETER FilterUser
    Filters results by user principal name
.PARAMETER LastLogin
    Filters users by last login date (days since last login)
.PARAMETER NewSession
    Forces a new Graph connection
.PARAMETER Scopes
    Microsoft Graph permission scopes
.EXAMPLE
    Get-M365LicenseOverview -FilterLicenseSKU "ENTERPRISE"
.EXAMPLE
    Get-M365LicenseOverview -FilterServicePlan "EXCHANGE" -LastLogin 90
#>
function Get-M365LicenseOverview
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSObject])]
    param(
        [Parameter(ParameterSetName = "SKU")]
        [ValidateNotNullOrEmpty()]
        [string]$FilterLicenseSKU,

        [Parameter(ParameterSetName = "ServicePlan")]
        [ValidateNotNullOrEmpty()]
        [string]$FilterServicePlan,

        [Parameter(ParameterSetName = "User", Mandatory = $false)]
        [string]$FilterUser,

        [Parameter(ParameterSetName = "User", Mandatory = $false)]
        [ValidateRange(1, 3650)]
        [int]$LastLogin,

        [Switch]$NewSession,

        [ValidateSet('User.Read.All', 'Organization.Read.All')]
        [string[]]$Scopes = ('User.Read.All', 'Organization.Read.All')
    )

    begin
    {
        # Ensure required modules are imported
        $requiredModules = @(
            'Microsoft.Graph.Beta.Users',
            'Microsoft.Graph.Beta.Identity.DirectoryManagement'
        )
        Install-RequiredModules -RequiredModules $requiredModules

        # Handle Graph connection
        try
        {
            if ($NewSession)
            { 
                Write-PSFMessage -Level 'Verbose' -Message 'Close existing Microsoft Graph session.'
                Disconnect-MgGraph -ErrorAction SilentlyContinue 
            }
            
            $ctx = Get-MgContext
            if (-not $ctx)
            {
                Write-PSFMessage -Level 'Verbose' -Message 'No Microsoft Graph context found. Attempting to connect.'
                Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop
            }
        }
        catch
        {
            Write-PSFMessage -Level 'Error' -Message 'Failed to connect to Microsoft Graph.'
            throw "Graph connection failed: $_"
        }

        # Load service plan data
        try
        {
            Write-PSFMessage -Level 'Verbose' -Message 'Retrieve license overview from Microsoft.'
            $csvUrl = 'https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference'
            $csvLink = (Invoke-WebRequest -Uri $csvUrl -UseBasicParsing).Links |
            Where-Object href -match 'licensing.csv' |
            Select-Object -First 1 -ExpandProperty href

            $skuTable = Invoke-RestMethod -Uri $csvLink | ConvertFrom-Csv
        }
        catch
        {
            Write-PSFMessage -Level 'Error' -Message 'Failed to retrieve license overview from Microsoft.'
            throw "Failed to load service plan data: $_"
        }

        # Build lookup tables for better performance
        Write-PSFMessage -Level 'Verbose' -Message 'Build lookup tables.'
        $skuLookup = @{}
        $servicePlanLookup = @{}
        $skuTable | ForEach-Object {
            $skuLookup[$_.GUID] = $_
            if (-not $servicePlanLookup.ContainsKey($_.GUID))
            {
                $servicePlanLookup[$_.GUID] = [Collections.Generic.List[object]]::new()
            }
            $servicePlanLookup[$_.GUID].Add($_)
        }
    }

    process
    {
        try
        {
            # Build user filter
            $userParams = @{}
            $userParams = @{
                All              = $true
                Property         = 'Id,UserPrincipalName,DisplayName,SignInActivity,AssignedLicenses'
                ConsistencyLevel = 'eventual'
            }

            switch ($PSCmdlet.ParameterSetName)
            {
                'User'
                {
                    if ($LastLogin)
                    {
                        Write-PSFMessage -Level 'Verbose' -Message "Retrieving users that have not logged in for $LastLogin days."
                        $filter = "signInActivity/lastSignInDateTime ge $([datetime]::UtcNow.AddDays(-$LastLogin).ToString('s'))Z"
                        $userParams['Filter'] = $filter
                    }
                    if ($FilterUser)
                    {
                        Write-PSFMessage -Level 'Verbose' -Message "Retrieving users with UPN: $FilterUser."
                        $userParams['Filter'] = "startsWith(userPrincipalName, '$FilterUser')"
                    }
                }
            }

            # Process users
            Write-PSFMessage -Level 'Verbose' -Message "Process users."
            Get-MgBetaUser @userParams | ForEach-Object {
                $user = $_
                Write-PSFMessage -Level 'Verbose' -Message "Process user: $($user.DisplayName)."
                foreach ($license in $user.AssignedLicenses)
                {
                    $skuData = $skuLookup[$license.SkuId]
                    if (-not $skuData) { continue }
                    $servicePlans = $servicePlanLookup[$license.SkuId]
                    foreach ($plan in $servicePlans)
                    {
                        # Apply filters early in pipeline
                        if ($FilterLicenseSKU -and $skuData.String_Id -notmatch $FilterLicenseSKU) { continue }
                        if ($FilterServicePlan -and $plan.Service_Plans_Included_Friendly_Names -notmatch $FilterServicePlan) { continue }

                        # Create output object
                        [PSCustomObject]@{
                            UserPrincipalName        = $user.UserPrincipalName
                            LicenseFriendlyName      = $skuData.Product_Display_Name
                            LicenseSKU               = $skuData.String_Id
                            ServicePlan              = $plan.Service_Plans_Included_Friendly_Names
                            AppliesTo                = $license.ServicePlans.AppliesTo
                            ProvisioningStatus       = $license.ServicePlans.ProvisioningStatus
                            LastInteractiveSignIn    = $user.SignInActivity.LastSignInDateTime
                            LastNonInteractiveSignIn = $user.SignInActivity.LastNonInteractiveSignInDateTime
                            LastSuccessfulSignInDate = $user.SignInActivity.LastSuccessfulSignInDateTime
                        }
                    }
                }
            }
        }
        catch
        {
            throw "License processing failed: $_"
        }
    }
}
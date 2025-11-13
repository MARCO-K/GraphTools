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
    Filters results by user principal name.

    Aliases: User, UPN, UserPrincipalName, UserName, UPNName
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

    Gets license overview filtered by Exchange service plan for users inactive for 90 days.

.EXAMPLE
    Get-M365LicenseOverview -FilterUser "john.doe@contoso.com"

    Gets license overview for a specific user using the FilterUser parameter.

.EXAMPLE
    Get-M365LicenseOverview -UPN "john.doe@contoso.com"

    Gets license overview for a specific user using the UPN alias.

.EXAMPLE
    Get-M365LicenseOverview -UserName "john.doe@contoso.com"

    Gets license overview for a specific user using the UserName alias.
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
        [ValidateScript({$_ -match $script:GTValidationRegex.UPN})]
        [Alias('User','UPN','UserPrincipalName','UserName','UPNName')]
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
        Install-GTRequiredModules -RequiredModules $requiredModules

        # Handle Graph connection
        Initialize-GTGraphConnection -Scopes $Scopes -NewSession:$NewSession

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
        # Use Group-Object for more efficient grouping
        $skuGroups = $skuTable | Group-Object -Property GUID -AsHashTable -AsString

        # Build separate lookups - first item for SKU info, all items for service plans
        $skuLookup = @{}
        $servicePlanLookup = @{}
        foreach ($guid in $skuGroups.Keys)
        {
            $items = $skuGroups[$guid]
            $skuLookup[$guid] = $items[0]  # First item has the SKU info
            $servicePlanLookup[$guid] = [Collections.Generic.List[object]]::new($items)  # All items for service plans
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

                    # Apply SKU filter early to skip entire license if it doesn't match
                    if ($FilterLicenseSKU -and $skuData.String_Id -notmatch $FilterLicenseSKU) { continue }

                    $servicePlans = $servicePlanLookup[$license.SkuId]
                    foreach ($plan in $servicePlans)
                    {
                        # Apply service plan filter
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
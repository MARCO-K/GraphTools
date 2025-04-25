<#
.SYNOPSIS
    Retrieves a comprehensive report of all Microsoft Entra Conditional Access policies.

.DESCRIPTION
    This function connects to Microsoft Graph to fetch all Conditional Access policies
    (enabled, disabled, and report-only) and extracts detailed configuration settings
    for each policy. It provides a structured output suitable for analysis and review.

    Requires the Microsoft.Graph.Identity.SignIns module.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    Outputs a custom object for each Conditional Access policy found, containing detailed
    properties as described in the specification (Name, State, Assignments, Conditions,
    Grant Controls, Session Controls).

.EXAMPLE
    PS C:\> Get-GTConditionalAccessPolicyReport

    Retrieves and displays a report of all Conditional Access policies in the tenant.

.EXAMPLE
    PS C:\> Get-GTConditionalAccessPolicyReport | Export-Csv -Path "C:\temp\CAPolicyReport.csv" -NoTypeInformation

    Retrieves the policy report and exports it to a CSV file.

.NOTES
    Ensure you have the necessary permissions (e.g., Policy.Read.All) granted to the
    Microsoft Graph PowerShell application or the signed-in user.
#>
function Get-GTConditionalAccessPolicyReport
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

    Write-Verbose "Starting Conditional Access policy report generation."

    # Ensure required module is available
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Identity.SignIns))
    {
        Write-Error "Required module 'Microsoft.Graph.Identity.SignIns' not found. Please install it first."
        return
    }

    # Check Graph connection status
    if (-not (Get-MgContext))
    {
        Write-Warning "Not connected to Microsoft Graph. Attempting to connect."
        # Add connection logic here if desired, or rely on user being pre-connected.
        # For now, we'll assume the user connects beforehand or handle connection outside.
        Write-Error "Please connect to Microsoft Graph first using Connect-MgGraph with appropriate scopes (e.g., Policy.Read.All)."
        return
    }

    Write-Verbose "Retrieving Conditional Access policies..."
    try
    {
        $policies = Get-MgIdentityConditionalAccessPolicy -ErrorAction Stop
        Write-Verbose "Successfully retrieved $($policies.Count) policies."
    }
    catch
    {
        Write-Error "Failed to retrieve Conditional Access policies. Error: $_"
        return
    }

    $report = foreach ($policy in $policies)
    {
        Write-Verbose "Processing policy: $($policy.DisplayName) ($($policy.Id))"
        [PSCustomObject]@{
            PolicyName       = $policy.DisplayName
            PolicyId         = $policy.Id
            State            = $policy.State
            Assignments      = @{
                IncludeUsers        = $policy.Conditions.Users.IncludeUsers
                ExcludeUsers        = $policy.Conditions.Users.ExcludeUsers
                IncludeGroups       = $policy.Conditions.Users.IncludeGroups
                ExcludeGroups       = $policy.Conditions.Users.ExcludeGroups
                IncludeRoles        = $policy.Conditions.Users.IncludeRoles
                ExcludeRoles        = $policy.Conditions.Users.ExcludeRoles
                IncludeApplications = $policy.Conditions.Applications.IncludeApplications
                ExcludeApplications = $policy.Conditions.Applications.ExcludeApplications
                IncludeUserActions  = $policy.Conditions.Applications.IncludeUserActions
                IncludeAuthContexts = $policy.Conditions.Applications.IncludeAuthenticationContextClassReferences # Renamed for clarity
                IncludePlatforms    = $policy.Conditions.Platforms.IncludePlatforms
                ExcludePlatforms    = $policy.Conditions.Platforms.ExcludePlatforms
                IncludeLocations    = $policy.Conditions.Locations.IncludeLocations
                ExcludeLocations    = $policy.Conditions.Locations.ExcludeLocations
                IncludeDeviceStates = $policy.Conditions.Devices.IncludeDeviceStates # Deprecated, use DeviceFilter
                ExcludeDeviceStates = $policy.Conditions.Devices.ExcludeDeviceStates # Deprecated, use DeviceFilter
            }
            Conditions       = @{
                SignInRiskLevels           = $policy.Conditions.SignInRiskLevels
                UserRiskLevels             = $policy.Conditions.UserRiskLevels
                ClientAppTypes             = $policy.Conditions.ClientAppTypes
                DeviceFilterMode           = $policy.Conditions.Devices.DeviceFilter.Mode
                DeviceFilterRule           = $policy.Conditions.Devices.DeviceFilter.Rule
                ClientApplications         = $policy.Conditions.ClientApplications # Added based on potential structure
                ServicePrincipalRiskLevels = $policy.Conditions.ServicePrincipalRiskLevels # Added based on potential structure
            }
            GrantControls    = @{
                Operator        = $policy.GrantControls.Operator
                BuiltInControls = $policy.GrantControls.BuiltInControls
                CustomControls  = $policy.GrantControls.CustomAuthenticationFactors # Correct property name
                TermsOfUse      = $policy.GrantControls.TermsOfUse
            }
            SessionControls  = @{
                ApplicationEnforcedRestrictions = $policy.SessionControls.ApplicationEnforcedRestrictions.IsEnabled
                CloudAppSecurity                = $policy.SessionControls.CloudAppSecurity.IsEnabled
                CloudAppSecurityType            = $policy.SessionControls.CloudAppSecurity.CloudAppSecurityType
                SignInFrequencyInterval         = $policy.SessionControls.SignInFrequency.Value
                SignInFrequencyUnit             = $policy.SessionControls.SignInFrequency.Type
                SignInFrequencyAuthType         = $policy.SessionControls.SignInFrequency.AuthenticationType # Added based on potential structure
                PersistentBrowserSessionMode    = $policy.SessionControls.PersistentBrowserSession.Mode
                DisableResilienceDefaults       = $policy.SessionControls.DisableResilienceDefaults # Added based on potential structure
                SecureSignInSession             = $policy.SessionControls.SecureSignInSession.IsEnabled # Added based on potential structure
            }
            ModifiedDateTime = $policy.ModifiedDateTime
            CreatedDateTime  = $policy.CreatedDateTime
            TemplateId       = $policy.TemplateId # Added based on potential structure
        }
    }

    Write-Verbose "Finished processing policies."
    return $report
}

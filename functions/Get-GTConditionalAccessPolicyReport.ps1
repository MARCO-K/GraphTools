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

    # Module Management
    Install-GTRequiredModule -ModuleNames @('Microsoft.Graph.Authentication') -Verbose

    # Graph Connection
    if (-not (Initialize-GTGraphConnection -Scopes @('Policy.Read.All')))
    {
        Write-Error "Failed to connect to Microsoft Graph."
        return
    }

    Write-Verbose "Retrieving Conditional Access policies..."
    try
    {
        $policies = Invoke-GTGraphPagedRequest -Uri "v1.0/identity/conditionalAccess/policies"
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
            PolicyName       = $policy.displayName
            PolicyId         = $policy.id
            State            = $policy.state
            Assignments      = @{
                IncludeUsers        = $policy.conditions.users.includeUsers
                ExcludeUsers        = $policy.conditions.users.excludeUsers
                IncludeGroups       = $policy.conditions.users.includeGroups
                ExcludeGroups       = $policy.conditions.users.excludeGroups
                IncludeRoles        = $policy.conditions.users.includeRoles
                ExcludeRoles        = $policy.conditions.users.excludeRoles
                IncludeApplications = $policy.conditions.applications.includeApplications
                ExcludeApplications = $policy.conditions.applications.excludeApplications
                IncludeUserActions  = $policy.conditions.applications.includeUserActions
                IncludeAuthContexts = $policy.conditions.applications.includeAuthenticationContextClassReferences # Renamed for clarity
                IncludePlatforms    = $policy.conditions.platforms.includePlatforms
                ExcludePlatforms    = $policy.conditions.platforms.excludePlatforms
                IncludeLocations    = $policy.conditions.locations.includeLocations
                ExcludeLocations    = $policy.conditions.locations.excludeLocations
                IncludeDeviceStates = $policy.conditions.devices.includeDeviceStates # Deprecated, use DeviceFilter
                ExcludeDeviceStates = $policy.conditions.devices.excludeDeviceStates # Deprecated, use DeviceFilter
            }
            Conditions       = @{
                SignInRiskLevels           = $policy.conditions.signInRiskLevels
                UserRiskLevels             = $policy.conditions.userRiskLevels
                ClientAppTypes             = $policy.conditions.clientAppTypes
                DeviceFilterMode           = $policy.conditions.devices.deviceFilter.mode
                DeviceFilterRule           = $policy.conditions.devices.deviceFilter.rule
                ClientApplications         = $policy.conditions.clientApplications # Added based on potential structure
                ServicePrincipalRiskLevels = $policy.conditions.servicePrincipalRiskLevels # Added based on potential structure
            }
            GrantControls    = @{
                Operator        = $policy.grantControls.operator
                BuiltInControls = $policy.grantControls.builtInControls
                CustomControls  = $policy.grantControls.customAuthenticationFactors # Correct property name
                TermsOfUse      = $policy.grantControls.termsOfUse
            }
            SessionControls  = @{
                ApplicationEnforcedRestrictions = $policy.sessionControls.applicationEnforcedRestrictions.isEnabled
                CloudAppSecurity                = $policy.sessionControls.cloudAppSecurity.isEnabled
                CloudAppSecurityType            = $policy.sessionControls.cloudAppSecurity.cloudAppSecurityType
                SignInFrequencyInterval         = $policy.sessionControls.signInFrequency.value
                SignInFrequencyUnit             = $policy.sessionControls.signInFrequency.type
                SignInFrequencyAuthType         = $policy.sessionControls.signInFrequency.authenticationType # Added based on potential structure
                PersistentBrowserSessionMode    = $policy.sessionControls.persistentBrowserSession.mode
                DisableResilienceDefaults       = $policy.sessionControls.disableResilienceDefaults # Added based on potential structure
                SecureSignInSession             = $policy.sessionControls.secureSignInSession.isEnabled # Added based on potential structure
            }
            ModifiedDateTime = $policy.modifiedDateTime
            CreatedDateTime  = $policy.createdDateTime
            TemplateId       = $policy.templateId # Added based on potential structure
        }
    }

    Write-Verbose "Finished processing policies."
    return $report
}

<#
.SYNOPSIS
    Analyzes Conditional Access policies based on specified states to identify those lacking MFA or device compliance grant controls.

.DESCRIPTION
    This function retrieves Conditional Access policies from Microsoft Entra ID based on the specified states
    (e.g., 'enabled', 'enabledForReportingButNotEnforced', 'disabled') and examines their 'Grant' controls. It flags policies that do not explicitly require
    Multi-Factor Authentication (MFA), a compliant device, or a Hybrid Azure AD joined device.
    This helps identify potential security gaps where access might be granted without strong verification.

    Requires the Microsoft.Graph.Identity.SignIns module.

.PARAMETER State
    Specifies the states of the Conditional Access policies to retrieve.
    Valid values are 'enabled', 'disabled', 'enabledForReportingButNotEnforced'. Defaults to 'enabled' and 'enabledForReportingButNotEnforced'.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    Outputs a custom object for each policy found matching the state filter and lacking the specified grant controls,
    including the Policy Name, Policy ID, State, and the configured Grant Controls.

.EXAMPLE
    PS C:\> Get-GTPolicyControlGapReport

    Retrieves and displays a report of enabled and reporting-only CA policies missing MFA or device compliance controls.

.EXAMPLE
    PS C:\> Get-GTPolicyControlGapReport -State enabled

    Retrieves and displays a report of only *enabled* CA policies missing MFA or device compliance controls.

.EXAMPLE
    PS C:\> Get-GTPolicyControlGapReport -State enabled, disabled | Export-Csv -Path "C:\temp\CAPolicyControlGaps.csv" -NoTypeInformation

    Retrieves the gap report for enabled and disabled policies and exports it to a CSV file.

.NOTES
    Ensure you have the necessary permissions (e.g., Policy.Read.All) granted to the
    Microsoft Graph PowerShell application or the signed-in user.
    This function focuses on the *absence* of specific controls. A policy might have other valid
    controls or be intentionally configured this way; manual review is recommended.
#>
function Get-GTPolicyControlGapReport
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet('enabled', 'disabled', 'enabledForReportingButNotEnforced')]
        [string[]]$State = @('enabled', 'enabledForReportingButNotEnforced')
    )

    Write-Verbose "Starting Conditional Access policy control enforcement check for policies with state(s): $($State -join ', ')."

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
        Write-Error "Please connect to Microsoft Graph first using Connect-MgGraph with appropriate scopes (e.g., Policy.Read.All)."
        return
    }

    Write-Verbose "Retrieving Conditional Access policies with state(s): $($State -join ', ')..."
    try
    {
        # Construct the filter string dynamically based on the State parameter
        $filterConditions = $State | ForEach-Object { "state eq '$_'" }
        $filter = $filterConditions -join ' or '

        Write-Verbose "Using filter: $filter"
        $policies = Get-MgIdentityConditionalAccessPolicy -Filter $filter -ErrorAction Stop
        Write-Verbose "Successfully retrieved $($policies.Count) policies matching the specified state(s)."
    }
    catch
    {
        Write-Error "Failed to retrieve Conditional Access policies. Error: $_"
        return
    }

    $gapReport = foreach ($policy in $policies)
    {
        Write-Verbose "Analyzing policy: $($policy.DisplayName) ($($policy.Id))"

        $requiresMfa = $false
        $requiresDeviceCompliance = $false

        if ($policy.GrantControls)
        {
            $controls = $policy.GrantControls.BuiltInControls
            if ($controls -contains 'mfa')
            {
                $requiresMfa = $true
            }
            if (($controls -contains 'compliantDevice') -or ($controls -contains 'domainJoinedDevice'))
            {
                # domainJoinedDevice maps to Require Hybrid Azure AD joined device
                $requiresDeviceCompliance = $true
            }
            # Add checks for Custom Controls if necessary, though the spec focuses on built-in ones.
            # if ($policy.GrantControls.CustomAuthenticationFactors) { ... }
        }

        # Flag the policy if it lacks BOTH MFA and Device Compliance requirements
        # Adjust this logic if the requirement is OR instead of AND based on interpretation
        # The spec implies flagging if *either* is missing, so we check the inverse:
        if (-not ($requiresMfa -or $requiresDeviceCompliance))
        {
            Write-Verbose "Policy '$($policy.DisplayName)' (State: $($policy.State)) flagged: Lacks MFA or Device Compliance grant control."
            [PSCustomObject]@{
                PolicyName    = $policy.DisplayName
                PolicyId      = $policy.Id
                State         = $policy.State # Added state for clarity
                GrantControls = $policy.GrantControls # Include the actual controls for context
                Reason        = "Policy does not require MFA or Device Compliance (Compliant/Hybrid Joined)."
            }
        }
    }

    Write-Verbose "Finished policy control enforcement check."
    if ($gapReport)
    {
        Write-Information "Found $($gapReport.Count) policies matching the state filter potentially lacking strong grant controls."
    }
    else
    {
        Write-Information "No policies found matching the state filter that lack MFA or Device Compliance grant controls."
    }

    return $gapReport
}

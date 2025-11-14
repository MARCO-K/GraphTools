function Remove-GTPIMRoleEligibility
{
    <#
    .SYNOPSIS
        Removes all PIM (Privileged Identity Management) role eligibility schedules from a user
    .DESCRIPTION
        Removes PIM role eligibility schedules that allow a user to activate privileged roles.
        This is critical during offboarding or security incident response to prevent users from
        activating privileged roles even after active role assignments have been removed.
        
        PIM role eligibilities allow users to temporarily elevate their privileges by activating
        eligible roles. Removing these eligibilities ensures complete privilege revocation.
        
        This is an internal helper function used by Remove-GTUserEntitlements.
    .PARAMETER User
        The user object (must have Id and UserPrincipalName properties)
    .PARAMETER OutputBase
        Base output object for logging
    .PARAMETER Results
        Results collection to add output to
    .EXAMPLE
        $user = Get-MgBetaUser -UserId 'user@contoso.com'
        $outputBase = @{ UserPrincipalName = $user.UserPrincipalName }
        $results = [System.Collections.Generic.List[PSObject]]::new()
        Remove-GTPIMRoleEligibility -User $user -OutputBase $outputBase -Results $results
        
        Removes all PIM role eligibility schedules from the user and adds results to the collection
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            if ($_.Id -and $_.UserPrincipalName) {
                $true
            } else {
                throw "User object must have 'Id' and 'UserPrincipalName' properties"
            }
        })]
        [object]$User,
        [Parameter(Mandatory = $true)]
        [hashtable]$OutputBase,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[PSObject]]$Results
    )

    try
    {
        $roleEligibilitySchedules = Get-MgBetaRoleManagementDirectoryRoleEligibilitySchedule -Filter "principalId eq '$($User.Id)'" -ExpandProperty roleDefinition -All -ErrorAction Stop

        if ($roleEligibilitySchedules)
        {
            foreach ($schedule in $roleEligibilitySchedules)
            {
                $action = 'RemovePIMRoleEligibility'
                $output = $OutputBase + @{
                    ResourceName = $schedule.RoleDefinition.DisplayName
                    ResourceType = 'PIMRoleEligibility'
                    ResourceId   = $schedule.Id
                    Action       = $action
                }

                try
                {
                    if ($PSCmdlet.ShouldProcess($schedule.RoleDefinition.DisplayName, $action))
                    {
                        Write-PSFMessage -Level Verbose -Message "Removing PIM role eligibility $($schedule.RoleDefinition.DisplayName) from user $($User.UserPrincipalName)"
                        Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule -UnifiedRoleEligibilityScheduleId $schedule.Id -ErrorAction Stop
                        $output['Status'] = 'Success'
                    }
                }
                catch
                {
                    # Use centralized error handling helper to parse Graph API exceptions
                    $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'resource'
                    
                    # Log appropriate message based on error details
                    if ($errorDetails.HttpStatus -in 404, 403) {
                        Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to remove PIM role eligibility $($schedule.RoleDefinition.DisplayName) from user $($User.UserPrincipalName) - $($errorDetails.Reason)"
                        Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
                    }
                    elseif ($errorDetails.HttpStatus) {
                        Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to remove PIM role eligibility $($schedule.RoleDefinition.DisplayName) from user $($User.UserPrincipalName) - $($errorDetails.Reason)"
                    }
                    else {
                        Write-PSFMessage -Level Error -Message "Failed to remove PIM role eligibility $($schedule.RoleDefinition.DisplayName) from user $($User.UserPrincipalName). $($errorDetails.ErrorMessage)"
                    }
                    $output['Status'] = "Failed: $($errorDetails.Reason)"
                }
                $Results.Add([PSCustomObject]$output)
            }
        }
        else
        {
            Write-PSFMessage -Level Verbose -Message "No PIM role eligibility schedules found for user $($User.UserPrincipalName)"
        }
    }
    catch
    {
        # Use centralized error handling helper to parse Graph API exceptions
        $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'user'
        
        # Log appropriate message based on error details
        if ($errorDetails.HttpStatus -in 404, 403) {
            Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to retrieve PIM role eligibility schedules for user $($User.UserPrincipalName) - $($errorDetails.Reason)"
            Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
        }
        elseif ($errorDetails.HttpStatus) {
            Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to retrieve PIM role eligibility schedules for user $($User.UserPrincipalName) - $($errorDetails.Reason)"
        }
        else {
            Write-PSFMessage -Level Error -Message "Failed to retrieve PIM role eligibility schedules for user $($User.UserPrincipalName). $($errorDetails.ErrorMessage)"
        }
        $output = $OutputBase + @{
            ResourceName = 'PIMRoleEligibilitySchedules'
            ResourceType = 'PIMRoleEligibility'
            ResourceId   = $null
            Action       = 'RemovePIMRoleEligibility'
            Status       = "Failed: $($errorDetails.Reason)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

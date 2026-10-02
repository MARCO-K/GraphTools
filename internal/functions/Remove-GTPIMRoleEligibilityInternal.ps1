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
        $user = Invoke-GTGraphRequest -Uri 'v1.0/users/user@contoso.com'
        $outputBase = @{ UserPrincipalName = $user.UserPrincipalName }
        $results = [System.Collections.Generic.List[PSObject]]::new()
        Remove-GTPIMRoleEligibility -User $user -OutputBase $outputBase -Results $results
        
        Removes all PIM role eligibility schedules from the user and adds results to the collection
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-GTUserObject -User $_ })]
        [object]$User,
        [Parameter(Mandatory = $true)]
        [hashtable]$OutputBase,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[PSObject]]$Results
    )

    try
    {
        # Validate that User.Id is a GUID to prevent OData injection
        Test-GTGuid -InputObject $User.Id | Out-Null
        
        # beta required: PIM roleManagement endpoints are only available in the beta API
        $filter = "principalId eq '$($User.Id)'"
        $roleEligibilitySchedules = Invoke-GTGraphPagedRequest -Uri "beta/roleManagement/directory/roleEligibilitySchedules?`$filter=$([Uri]::EscapeDataString($filter))&`$expand=roleDefinition"

        if ($roleEligibilitySchedules)
        {
            # Batch role eligibility removal requests via Invoke-GTGraphBatch to eliminate N+1 latency
            $batchRequests = [System.Collections.Generic.List[hashtable]]::new()
            $processedSchedules = [System.Collections.Generic.List[object]]::new()

            foreach ($schedule in $roleEligibilitySchedules)
            {
                $action = 'RemovePIMRoleEligibility'
                if ($PSCmdlet.ShouldProcess($schedule.roleDefinition.displayName, $action))
                {
                    Write-PSFMessage -Level Verbose -Message "Queueing PIM role eligibility $($schedule.roleDefinition.displayName) removal for user $($User.UserPrincipalName)"
                    $batchRequests.Add(@{
                        id     = $schedule.id
                        method = 'DELETE'
                        url    = "beta/roleManagement/directory/roleEligibilitySchedules/$($schedule.id)"
                    })
                    $processedSchedules.Add($schedule)
                }
            }

            if ($batchRequests.Count -gt 0)
            {
                $batchResponses = $null
                try
                {
                    $batchResponses = Invoke-GTGraphBatch -Requests $batchRequests -ErrorAction Stop
                }
                catch
                {
                    $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'resource'
                    Write-PSFMessage -Level $err.LogLevel -Message "Batch request failed: $($err.Reason)"

                    foreach ($schedule in $processedSchedules)
                    {
                        $output = $OutputBase + @{
                            ResourceName = $schedule.roleDefinition.displayName
                            ResourceType = 'PIMRoleEligibility'
                            ResourceId   = $schedule.id
                            Action       = 'RemovePIMRoleEligibility'
                            Status       = "Failed: $($err.Reason)"
                        }
                        $Results.Add([PSCustomObject]$output)
                    }
                    return
                }

                $responseLookup = @{}
                if ($batchResponses)
                {
                    foreach ($resp in $batchResponses)
                    {
                        $responseLookup[$resp.Id] = $resp
                    }
                }

                foreach ($schedule in $processedSchedules)
                {
                    $output = $OutputBase + @{
                        ResourceName = $schedule.roleDefinition.displayName
                        ResourceType = 'PIMRoleEligibility'
                        ResourceId   = $schedule.id
                        Action       = 'RemovePIMRoleEligibility'
                    }

                    if ($responseLookup.ContainsKey($schedule.id))
                    {
                        $resp = $responseLookup[$schedule.id]
                        if ($resp.Status -in 200, 204)
                        {
                            Write-PSFMessage -Level Verbose -Message "Successfully removed PIM role eligibility $($schedule.roleDefinition.displayName) from user $($User.UserPrincipalName)"
                            $output['Status'] = 'Success'
                        }
                        else
                        {
                            $reason = if ($resp.Body -and $resp.Body.error -and $resp.Body.error.message) { $resp.Body.error.message } else { "Batch subrequest returned HTTP $($resp.Status)" }
                            Write-PSFMessage -Level Warning -Message "Failed to remove PIM role eligibility $($schedule.roleDefinition.displayName) from user $($User.UserPrincipalName) - $reason"
                            $output['Status'] = "Failed: $reason"
                        }
                    }
                    else
                    {
                        Write-PSFMessage -Level Error -Message "Failed to remove PIM role eligibility $($schedule.roleDefinition.displayName) from user $($User.UserPrincipalName) - Missing from batch response"
                        $output['Status'] = 'Failed: Batch response missing'
                    }
                    $Results.Add([PSCustomObject]$output)
                }
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

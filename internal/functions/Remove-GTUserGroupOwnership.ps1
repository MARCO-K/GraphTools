function Remove-GTUserGroupOwnership
{
    <#
    .SYNOPSIS
        Removes user from all group ownerships
    .DESCRIPTION
        Removes the user from ownership of all groups they own. Group owners have
        administrative control over group membership and settings.

        The function skips groups where the user is the last owner to prevent orphaned groups.
        This is typically used during offboarding or security incident response.

        This is an internal helper function used by Remove-GTUserEntitlement.
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
        Remove-GTUserGroupOwnership -User $user -OutputBase $outputBase -Results $results

        Removes the user from all group ownerships and adds results to the collection
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Alias('Remove-GTUserGroupOwnerships')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-GTUserObject -User $_ })]
        [object]$User,
        [Parameter(Mandatory = $true)]
        [hashtable]$OutputBase,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[PSObject]]$Results
    )

    $OwnedGroups = Invoke-GTGraphPagedRequest -Uri "v1.0/users/$($User.Id)/ownedObjects/microsoft.graph.group?`$select=id,displayName"

    # Bolt Optimization: Batch fetch owners to eliminate N+1 queries.
    $allOwnersCountMap = @{}
    $batchRequests = [System.Collections.Generic.List[hashtable]]::new()

    if ($OwnedGroups) {
        foreach ($Group in $OwnedGroups) {
            $batchRequests.Add(@{
                id     = "group_$($Group.id)"
                method = 'GET'
                # Query only owner IDs to minimize payload size while allowing accurate owner count detection
                url    = "v1.0/groups/$($Group.id)/owners?`$select=id"
            })
        }
    }

    if ($batchRequests.Count -gt 0) {
        try {
            $batchResponses = Invoke-GTGraphBatch -Requests $batchRequests
            foreach ($response in $batchResponses) {
                if ($response.Status -ge 200 -and $response.Status -lt 300 -and $null -ne $response.Body.value) {
                    $allOwnersCountMap[$response.Id] = @($response.Body.value).Count
                }
            }
        }
        catch {
            Write-PSFMessage -Level Warning -Message "Batch fetching owners failed. Falling back to individual requests. Details: $($_.Exception.Message)"
        }
    }

    foreach ($Group in $OwnedGroups)
    {
        $action = 'RemoveGroupOwnership'
        $output = $OutputBase + @{
            ResourceName = $Group.displayName
            ResourceType = 'Group'
            ResourceId   = $Group.id
            Action       = $action
        }

        try
        {
            $ownerCount = 0
            if ($allOwnersCountMap.ContainsKey("group_$($Group.id)")) {
                $ownerCount = $allOwnersCountMap["group_$($Group.id)"]
            } else {
                # Fallback to single API call if batch failed
                $owners = Invoke-GTGraphPagedRequest -Uri "v1.0/groups/$($Group.id)/owners?`$select=id"
                $ownerCount = @($owners).Count
            }

            if ($ownerCount -eq 1)
            {
                Write-PSFMessage -Level Verbose -Message "Skipping last owner ($($User.Id)) of group $($Group.id)"
                $output['Status'] = 'Skipped: Last owner'
                $Results.Add([PSCustomObject]$output)
                continue
            }

            if ($PSCmdlet.ShouldProcess($Group.displayName, $action))
            {
                Write-PSFMessage -Level Verbose -Message "Removing user $($User.UserPrincipalName) from groupowner $($Group.displayName)"
                Invoke-GTGraphRequest -Method DELETE -Uri "v1.0/groups/$($Group.id)/owners/$($User.Id)/`$ref" -ErrorAction Stop
                $output['Status'] = 'Success'
            }
        }
        catch
        {
            # Use centralized error handling helper to parse Graph API exceptions
            $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'resource'

            # Log appropriate message based on error details
            if ($errorDetails.HttpStatus) {
                Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to remove user $($User.UserPrincipalName) from groupowner $($Group.DisplayName). $($errorDetails.Reason)"
                if ($errorDetails.HttpStatus -in 404, 403) {
                    Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
                }
            }
            else {
                Write-PSFMessage -Level Error -Message "Failed to remove user $($User.UserPrincipalName) from groupowner $($Group.DisplayName). $($errorDetails.ErrorMessage)"
            }
            $output['Status'] = "Failed: $($errorDetails.Reason)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

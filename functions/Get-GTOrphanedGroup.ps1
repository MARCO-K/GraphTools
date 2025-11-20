function Get-GTOrphanedGroup {
    <#
    .SYNOPSIS
    Retrieves a list of groups from Microsoft Entra ID that have no assigned owners.

    .DESCRIPTION
    Connects to Microsoft Graph to fetch all groups and their owner information.
    It then filters this list to identify and report only those groups that are orphaned (have no owners).
    This is useful for identifying unmanaged groups and ensuring accountability.

    .EXAMPLE
    Get-GTOrphanedGroup -Verbose
    Retrieves all orphaned groups in the tenant with verbose logging.

    .NOTES
    Requires Microsoft Graph PowerShell SDK with appropriate permissions:
    - Group.Read.All (to read group properties and memberships)
    - Directory.Read.All (potentially needed for expanding owner information, though Get-MgBetaGroup -ExpandProperty owners should suffice with Group.Read.All)
    Ensure the GraphTools module's internal functions like Install-GTRequiredModule are available.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        # Switch to force a new Graph session
        [switch]$NewSession,

        # Scopes for Graph Connection
        [string[]]$Scope = @('Group.Read.All', 'Directory.Read.All')
    )

    begin {
        # Module Management
        $requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Groups')
        Install-GTRequiredModule -ModuleNames $requiredModules -Verbose:$VerbosePreference

        # Graph Connection Handling
        Initialize-GTGraphConnection -Scopes $Scope -NewSession:$NewSession
    }

    process {
        $orphanedGroups = [System.Collections.Generic.List[object]]::new()
        try {
            Write-PSFMessage -Level Verbose -Message "Fetching Groups from Microsoft Graph..."
            # Select specific properties to reduce data transfer, ensure owners is expanded
            $selectProperties = @(
                'id',
                'displayName',
                'mailEnabled',
                'securityEnabled',
                'groupTypes',
                'visibility',
                'createdDateTime',
                'deletedDateTime' # To filter out soft-deleted groups if not already handled by API
            )
            # Expand owners to check for existence and account status
            # Expand members to check for emptiness (fetching just the first page is sufficient to determine if it's empty)
            $groups = Get-MgBetaGroup -All -Property $selectProperties -ExpandProperty @('owners', 'members') -ErrorAction Stop
        }
        catch {
            # Use centralized error handling helper to parse Graph API exceptions
            $errorDetails = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'resource'
            
            # Log appropriate message based on error details
            if ($errorDetails.HttpStatus -in 404, 403) {
                Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to retrieve Groups - $($errorDetails.Reason)"
                Write-PSFMessage -Level Debug -Message "Detailed error ($($errorDetails.HttpStatus)): $($errorDetails.ErrorMessage)"
            }
            elseif ($errorDetails.HttpStatus) {
                Write-PSFMessage -Level $errorDetails.LogLevel -Message "Failed to retrieve Groups - $($errorDetails.Reason)"
            }
            else {
                Write-PSFMessage -Level Error -Message "Failed to retrieve Groups. $($errorDetails.ErrorMessage)"
            }
            Stop-PSFFunction -Message $errorDetails.Reason -ErrorRecord $_ -EnableException $true
            return # Exit if fetching fails
        }

        Write-PSFMessage -Level Debug -Message "Processing $($groups.Count) Groups."

        foreach ($group in $groups) {
            # Ensure the group is not soft-deleted (deletedDateTime will be set if it is)
            if ($group.deletedDateTime) {
                Write-PSFMessage -Level Debug -Message "Skipping soft-deleted group $($group.DisplayName) (ID: $($group.Id))"
                continue
            }

            $orphanReasons = [System.Collections.Generic.List[string]]::new()

            # Check 1: No Owners
            if (-not $group.Owners -or $group.Owners.Count -eq 0) {
                $orphanReasons.Add("NoOwners")
            }
            else {
                # Check 2: All Owners Disabled
                # We need to check the 'accountEnabled' property of the owners.
                # Note: Get-MgBetaGroup expansion returns DirectoryObjects. We need to ensure we can access accountEnabled.
                # If the expansion returns generic objects, we might need to check the property dictionary or cast.
                # Usually, for User owners, accountEnabled is present. For ServicePrincipal owners, it is also present.
                
                $activeOwnersCount = 0
                foreach ($owner in $group.Owners) {
                    # Check if AccountEnabled property exists and is true
                    if ($owner.AdditionalProperties.ContainsKey('accountEnabled')) {
                        if ($owner.AdditionalProperties['accountEnabled'] -eq $true) {
                            $activeOwnersCount++
                        }
                    }
                    elseif ($null -ne $owner.AccountEnabled) { # Direct property access if PS object mapping works
                        if ($owner.AccountEnabled -eq $true) {
                            $activeOwnersCount++
                        }
                    }
                    else {
                        # If we can't determine, assume active to be safe, or treat as edge case.
                        # For safety, if we can't read it, we assume it's NOT disabled.
                        $activeOwnersCount++ 
                    }
                }

                if ($activeOwnersCount -eq 0) {
                    $orphanReasons.Add("AllOwnersDisabled")
                }
            }

            # Check 3: Empty Group (No Members)
            # If members expansion returned nothing, it's empty.
            if (-not $group.Members -or $group.Members.Count -eq 0) {
                $orphanReasons.Add("EmptyGroup")
            }

            if ($orphanReasons.Count -gt 0) {
                $reasonsString = $orphanReasons -join ', '
                Write-PSFMessage -Level Debug -Message "Found orphaned/empty group: $($group.DisplayName) (ID: $($group.Id)). Reason: $reasonsString"
                
                $orphanedGroups.Add(
                    [PSCustomObject]@{
                        DisplayName     = $group.DisplayName
                        Id              = $group.Id
                        MailEnabled     = $group.MailEnabled
                        SecurityEnabled = $group.SecurityEnabled
                        GroupTypes      = $group.GroupTypes -join ', '
                        Visibility      = $group.Visibility
                        CreatedDateTime = $group.CreatedDateTime
                        OrphanReason    = $reasonsString
                    }
                )
            }
        }

        Write-PSFMessage -Level Verbose -Message "Found $($orphanedGroups.Count) groups matching criteria."
        return $orphanedGroups
    }

    end {
        # No specific end processing needed for this function
    }
}

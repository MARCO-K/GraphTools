function Get-GTOrphanedGroup
{
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

    begin
    {
        # Module Management
        $requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Groups')
        Install-GTRequiredModule -ModuleNames $requiredModules -Verbose:$VerbosePreference

        # Graph Connection Handling
        Initialize-GTGraphConnection -Scopes $Scope -NewSession:$NewSession
    }

    process
    {
        $orphanedGroups = [System.Collections.Generic.List[object]]::new()
        try
        {
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
            $groups = Get-MgBetaGroup -All -Property $selectProperties -ExpandProperty 'owners' -ErrorAction Stop
        }
        catch
        {
            Stop-PSFFunction -Message "Failed to retrieve Groups: $($_.Exception.Message)" -ErrorRecord $_ -EnableException $true
            return # Exit if fetching fails
        }

        Write-PSFMessage -Level Debug -Message "Processing $($groups.Count) Groups."

        foreach ($group in $groups)
        {
            # Ensure the group is not soft-deleted (deletedDateTime will be set if it is)
            if ($group.deletedDateTime)
            {
                Write-PSFMessage -Level Debug -Message "Skipping soft-deleted group $($group.DisplayName) (ID: $($group.Id))"
                continue
            }

            if (-not $group.Owners -or $group.Owners.Count -eq 0)
            {
                Write-PSFMessage -Level Debug -Message "Found orphaned group: $($group.DisplayName) (ID: $($group.Id))"
                $orphanedGroups.Add(
                    [PSCustomObject]@{
                        DisplayName     = $group.DisplayName
                        Id              = $group.Id
                        MailEnabled     = $group.MailEnabled
                        SecurityEnabled = $group.SecurityEnabled
                        GroupTypes      = $group.GroupTypes -join ', '
                        Visibility      = $group.Visibility
                        CreatedDateTime = $group.CreatedDateTime
                    }
                )
            }
        }

        Write-PSFMessage -Level Verbose -Message "Found $($orphanedGroups.Count) orphaned groups."
        return $orphanedGroups
    }

    end
    {
        # No specific end processing needed for this function
    }
}

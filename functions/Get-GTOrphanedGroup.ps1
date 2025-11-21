function Get-GTOrphanedGroup
{
    <#
    .SYNOPSIS
    Retrieves a list of groups from Microsoft Entra ID that have no assigned owners.

    .DESCRIPTION
    Connects to Microsoft Graph to fetch groups and owner information.
    It identifies "Orphaned" groups (No owners) and optionally "Empty" groups (No members).

    PERFORMANCE NOTE:
    By default, this checks for OWNERS only.
    Use -CheckEmpty to check for members, but be aware this significantly increases execution time
    and bandwidth as it must download member lists for every group.

    .PARAMETER CheckEmpty
    Switch to also check for groups with no members. Warning: Slower performance.

    .PARAMETER CheckDisabledOwners
    Switch to inspect if existing owners are disabled. 
    Note: This relies on the API returning account status in the expansion, which is not always guaranteed.

    .EXAMPLE
    Get-GTOrphanedGroup
    Fast scan. Returns groups with 0 owners.

    .EXAMPLE
    Get-GTOrphanedGroup -CheckEmpty
    Slower scan. Returns groups with 0 owners OR 0 members.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [switch]$CheckEmpty,
        [switch]$CheckDisabledOwners,
        [switch]$NewSession
    )

    begin
    {
        $modules = @('Microsoft.Graph.Beta.Groups')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        # 1. Scopes Check
        # User.Read.All is helpful if we try to inspect owner details
        $requiredScopes = @('Group.Read.All', 'User.Read.All')
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet))
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }
    }

    process
    {
        $orphanedGroups = [System.Collections.Generic.List[PSCustomObject]]::new()

        try
        {
            Write-PSFMessage -Level Verbose -Message "Fetching Groups from Microsoft Graph..."
            
            # 2. Optimize Property Selection
            $selectProps = @('id', 'displayName', 'groupTypes', 'visibility', 'createdDateTime', 'deletedDateTime', 'mailEnabled', 'securityEnabled')
            
            # 3. Dynamic Expansion (The Fix for the "Expansion Bomb")
            # Only expand members if explicitly requested to save bandwidth
            $expandProps = [System.Collections.Generic.List[string]]::new()
            $expandProps.Add('owners')
            
            if ($CheckEmpty) { $expandProps.Add('members') }
            
            # Fetch Groups
            $groups = Get-MgBetaGroup -All -Property $selectProps -ExpandProperty $expandProps -ErrorAction Stop

            Write-PSFMessage -Level Verbose -Message "Processing $($groups.Count) Groups."

            foreach ($group in $groups)
            {
                # Skip soft-deleted groups
                if ($group.DeletedDateTime) { continue }

                $orphanReasons = [System.Collections.Generic.List[string]]::new()

                # --- Check 1: No Owners ---
                if (-not $group.Owners -or $group.Owners.Count -eq 0)
                {
                    $orphanReasons.Add("NoOwners")
                }
                elseif ($CheckDisabledOwners)
                {
                    # --- Check 2: All Owners Disabled (Optional & Advanced) ---
                    $activeOwners = 0
                    $statusUnknown = 0

                    foreach ($owner in $group.Owners)
                    {
                        # Handle PSObject wrapping to find accountEnabled safely
                        $isEnabled = $null
                        
                        # Try standard property access
                        if ($null -ne $owner.AccountEnabled)
                        {
                            $isEnabled = $owner.AccountEnabled
                        }
                        # Try dictionary access (common in Graph SDK dynamic objects)
                        elseif ($owner.AdditionalProperties -and $owner.AdditionalProperties.ContainsKey('accountEnabled'))
                        {
                            $isEnabled = $owner.AdditionalProperties['accountEnabled']
                        }

                        if ($null -ne $isEnabled)
                        {
                            if ($isEnabled -eq $true) { $activeOwners++ }
                        }
                        else
                        {
                            # If property is missing, we can't prove they are disabled.
                            # We treat this as "Unknown" to avoid false positives.
                            $statusUnknown++
                        }
                    }

                    # Only flag if we are SURE there are 0 active owners and we didn't have unknowns
                    if ($activeOwners -eq 0 -and $statusUnknown -eq 0)
                    {
                        $orphanReasons.Add("AllOwnersDisabled")
                    }
                }

                # --- Check 3: Empty Group (Optional) ---
                if ($CheckEmpty)
                {
                    # If expansion happened, Members will be an array (or null if empty)
                    if (-not $group.Members -or $group.Members.Count -eq 0)
                    {
                        $orphanReasons.Add("EmptyGroup")
                    }
                }

                # --- Output ---
                if ($orphanReasons.Count -gt 0)
                {
                    $orphanedGroups.Add([PSCustomObject]@{
                            DisplayName     = $group.DisplayName
                            Id              = $group.Id
                            MailEnabled     = $group.MailEnabled
                            SecurityEnabled = $group.SecurityEnabled
                            GroupTypes      = if ($group.GroupTypes) { $group.GroupTypes -join ', ' } else { 'Security' }
                            Visibility      = $group.Visibility
                            CreatedDateTime = $group.CreatedDateTime
                            OrphanReason    = $orphanReasons -join ', '
                        })
                }
            }

            return $orphanedGroups.ToArray()
        }
        catch
        {
            # 4. Gold Standard Error Handling
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'Groups'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve Groups: $($err.Reason)"
        }
    }
}
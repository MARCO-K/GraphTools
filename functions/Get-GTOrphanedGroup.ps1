function Get-GTOrphanedGroup
{
    <#
    .SYNOPSIS
    Retrieves a list of groups from Microsoft Entra ID that have no assigned owners.

    .DESCRIPTION
    Connects to Microsoft Graph to fetch groups and owner information.
    It identifies "Orphaned" groups (No owners) and optionally "Empty" groups (No members).

    PERFORMANCE NOTE:
    - By default, this checks for OWNERS only.
    - Use -CheckEmpty to check for members.
    - This function outputs to the pipeline immediately (streaming), which is memory efficient.

    .PARAMETER CheckEmpty
    Switch to also check for groups with no members. Warning: Slower performance.

    .PARAMETER CheckDisabledOwners
    Switch to inspect if existing owners are disabled. 

    .PARAMETER NewSession
    Forces a new Microsoft Graph session.

    .EXAMPLE
    Get-GTOrphanedGroup
    Fast scan. Returns groups with 0 owners.

    .EXAMPLE
    Get-GTOrphanedGroup -CheckEmpty
    Returns groups with no owners or no members. Note: Slower due to member expansion.

    .EXAMPLE
    Get-GTOrphanedGroup -CheckDisabledOwners
    Returns groups where all assigned owners are disabled accounts.

    .EXAMPLE
    Get-GTOrphanedGroup -CheckEmpty -CheckDisabledOwners
    Comprehensive scan for orphaned groups, including empty groups and disabled owners.
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

        # 1. Scopes Check (Gold Standard)
        $requiredScopes = @('Group.Read.All', 'User.Read.All')
        
        # Use Test-GTGraphScopes for validation
        if (-not (Test-GTGraphScopes -RequiredScopes $requiredScopes -Reconnect -Quiet))
        {
            Write-Error "Failed to acquire required permissions ($($requiredScopes -join ', ')). Aborting."
            return
        }

        # 2. Connection Initialization (if forced new session)
        # We call Initialize regardless, but pass NewSession if requested
        if (-not (Initialize-GTGraphConnection -Scopes $requiredScopes -NewSession:$NewSession))
        {
            Write-Error "Failed to initialize session."
            return
        }
    }

    process
    {
        try
        {
            Write-PSFMessage -Level Verbose -Message "Fetching Groups from Microsoft Graph..."
            
            # Optimize Property Selection
            $selectProps = @('id', 'displayName', 'groupTypes', 'visibility', 'createdDateTime', 'deletedDateTime', 'mailEnabled', 'securityEnabled')
            
            # Dynamic Expansion
            $expandProps = [System.Collections.Generic.List[string]]::new()
            $expandProps.Add('owners')
            if ($CheckEmpty) { $expandProps.Add('members') }
            
            Write-PSFMessage -Level Verbose -Message "Expanding properties: $($expandProps -join ', ')"
            
            # Fetch Groups and process via Pipeline (Streaming)
            # This is memory efficient for large tenants
            Get-MgBetaGroup -All -Property $selectProps -ExpandProperty $expandProps -ErrorAction Stop | ForEach-Object {
                $group = $_
        
                # Skip soft-deleted groups
                # In ForEach-Object, 'return' acts like 'continue' (skips current item)
                if ($group.DeletedDateTime)
                { 
                    Write-PSFMessage -Level Verbose -Message "Skipping soft-deleted group: $($group.DisplayName)"
                    return 
                }

                $orphanReasons = [System.Collections.Generic.List[string]]::new()

                # --- Check 1: No Owners ---
                if (-not $group.Owners -or $group.Owners.Count -eq 0)
                {
                    $orphanReasons.Add("NoOwners")
                }
                elseif ($CheckDisabledOwners)
                {
                    # --- Check 2: All Owners Disabled (Optional) ---
                    $activeOwners = 0
                    $statusUnknown = 0

                    foreach ($owner in $group.Owners)
                    {
                        $isEnabled = $null
                
                        # Try standard property access
                        if ($null -ne $owner.AccountEnabled)
                        {
                            $isEnabled = $owner.AccountEnabled
                        }
                        # Try dictionary access
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
                            $statusUnknown++
                        }
                    }

                    if ($activeOwners -eq 0 -and $statusUnknown -eq 0)
                    {
                        $orphanReasons.Add("AllOwnersDisabled")
                    }
                }

                # --- Check 3: Empty Group (Optional) ---
                if ($CheckEmpty)
                {
                    if (-not $group.Members -or $group.Members.Count -eq 0)
                    {
                        $orphanReasons.Add("EmptyGroup")
                    }
                }

                # --- Output ---
                if ($orphanReasons.Count -gt 0)
                {
                    [PSCustomObject]@{
                        DisplayName     = $group.DisplayName
                        Id              = $group.Id
                        MailEnabled     = $group.MailEnabled
                        SecurityEnabled = $group.SecurityEnabled
                        GroupTypes      = if ($group.GroupTypes) { $group.GroupTypes -join ', ' } else { $null }
                        Visibility      = $group.Visibility
                        CreatedDateTime = $group.CreatedDateTime
                        OrphanReason    = $orphanReasons -join ', '
                    }
                }
            }
        }
        catch
        {
            # Gold Standard Error Handling
            $err = Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'Groups'
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to retrieve Groups: $($err.Reason)"
        }
    }
}
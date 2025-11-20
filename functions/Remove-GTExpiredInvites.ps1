function Remove-GTExpiredInvites {
    <#
    .SYNOPSIS
    Removes guest users who have not accepted their invitation within a specified timeframe.

    .DESCRIPTION
    This function identifies guest users with 'PendingAcceptance' status who were created
    older than the specified number of days and removes them.

    .PARAMETER DaysOlderThan
    The number of days an invitation can be pending before removal.

    .PARAMETER Force
    Bypasses the confirmation prompt.

    .EXAMPLE
    Remove-GTExpiredInvites -DaysOlderThan 90 -WhatIf
    Shows which users would be removed if they haven't accepted invites sent over 90 days ago.

    .NOTES
    Requires Microsoft Graph PowerShell SDK with User.ReadWrite.All permission.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [int]$DaysOlderThan,

        [switch]$Force
    )

    begin {
        $modules = @('Microsoft.Graph.Users')
        Install-GTRequiredModule -ModuleNames $modules -Verbose:$VerbosePreference

        if (-not (Initialize-GTGraphConnection -Scopes 'User.ReadWrite.All')) {
            Write-Error "Failed to initialize Microsoft Graph connection."
            return
        }
    }

    process {
        try {
            Write-PSFMessage -Level Verbose -Message "Searching for pending invites older than $DaysOlderThan days..."
            
            # Reuse Get-GTGuestUserReport logic if available, or reimplement for standalone
            # Here we call the function assuming it's loaded or we implement logic directly.
            # For robustness in a module, it's often safer to rely on the module structure.
            
            # We'll use the logic directly to ensure this function is self-contained if needed, 
            # but calling the sibling function is cleaner if guaranteed to be present.
            # Let's call the sibling function.
            
            $expiredGuests = Get-GTGuestUserReport -PendingOnly -DaysSinceCreation $DaysOlderThan

            if (-not $expiredGuests) {
                Write-PSFMessage -Level Verbose -Message "No expired pending invites found."
                return
            }

            Write-PSFMessage -Level Verbose -Message "Found $($expiredGuests.Count) expired pending invites."

            foreach ($guest in $expiredGuests) {
                if ($PSCmdlet.ShouldProcess("$($guest.DisplayName) ($($guest.UserPrincipalName))", "Remove Guest User (Expired Invite)")) {
                    if ($Force -or $PSCmdlet.ShouldContinue("Are you sure you want to delete guest user '$($guest.DisplayName)'?", "Confirm Deletion")) {
                        try {
                            Remove-MgUser -UserId $guest.Id -ErrorAction Stop
                            Write-PSFMessage -Level Output -Message "Removed guest user: $($guest.DisplayName)"
                        }
                        catch {
                            Write-PSFMessage -Level Error -Message "Failed to remove user $($guest.DisplayName): $($_.Exception.Message)"
                        }
                    }
                }
            }
        }
        catch {
            Stop-PSFFunction -Message "Failed to process expired invites: $($_.Exception.Message)" -ErrorRecord $_ -EnableException $true
        }
    }
}

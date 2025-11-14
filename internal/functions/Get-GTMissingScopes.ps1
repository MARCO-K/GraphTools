function Get-GTMissingScopes
{
    <#
    .SYNOPSIS
    Compares required scopes against current scopes to find missing permissions
    
    .DESCRIPTION
    Internal helper function that performs case-insensitive comparison to identify
    which required scopes are not present in the current scope list.
    
    .PARAMETER RequiredScopes
    Array of required permission strings to check for
    
    .PARAMETER CurrentScopes
    Array of currently granted permission strings
    
    .EXAMPLE
    Get-GTMissingScopes -RequiredScopes @('User.Read.All','Group.Read.All') -CurrentScopes @('user.read.all')
    Returns: 'group.read.all' (normalized to lowercase)
    
    .NOTES
    This function normalizes all scope names to lowercase for comparison.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$RequiredScopes,
        
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$CurrentScopes
    )
    
    # Normalize case for comparison
    $required = $RequiredScopes.ForEach{ $_.ToLower() }
    $current = $CurrentScopes.ForEach{ $_.ToLower() }
    
    # Return missing permissions
    return $required | Where-Object { $_ -notin $current }
}

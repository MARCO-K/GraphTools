function Remove-GTUserLicenses
{
    <#
    .SYNOPSIS
        Removes all licenses from a user
    .DESCRIPTION
        Removes all Microsoft 365 licenses assigned to a user. This revokes access to
        licensed services such as Exchange Online, SharePoint, Teams, and other
        Microsoft 365 applications.
        
        This is typically used during offboarding or security incident response.
        
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
        Remove-GTUserLicenses -User $user -OutputBase $outputBase -Results $results
        
        Removes all licenses from the user and adds results to the collection
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
        [System.Collections.Generic.List[PSObject]]$Results
    )

    $licenses = Get-MgBetaUserLicenseDetail -UserId $User.Id -ErrorAction Stop
    if ($licenses)
    {
        $action = 'RemoveLicenses'
        $output = $OutputBase + @{
            ResourceName = 'Licenses'
            ResourceType = 'License'
            ResourceId   = ($licenses.SkuPartNumber -join ', ')
            Action       = $action
        }

        try
        {
            if ($PSCmdlet.ShouldProcess($User.UserPrincipalName, $action))
            {
                Write-PSFMessage -Level Verbose -Message "Removing licenses from user $($User.UserPrincipalName)"
                Set-MgBetaUserLicense -UserId $User.Id -AddLicenses @() -RemoveLicenses @($licenses.SkuId) -ErrorAction Stop
                $output['Status'] = 'Success'
            }
        }
        catch
        {
            Write-PSFMessage -Level Error -Message "Failed to remove licenses from user $($User.UserPrincipalName)."
            $output['Status'] = "Failed: $($_.Exception.Message)"
        }
        $Results.Add([PSCustomObject]$output)
    }
}

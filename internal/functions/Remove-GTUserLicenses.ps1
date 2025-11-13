function Remove-GTUserLicenses
{
    <#
    .SYNOPSIS
        Removes all licenses from a user
    .PARAMETER User
        The user object (must have Id and UserPrincipalName properties)
    .PARAMETER OutputBase
        Base output object for logging
    .PARAMETER Results
        Results collection to add output to
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

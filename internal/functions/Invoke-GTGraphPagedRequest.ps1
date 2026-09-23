function Invoke-GTGraphPagedRequest
{
    <#
    .SYNOPSIS
    Executes a paged Microsoft Graph request and aggregates all items.

    .DESCRIPTION
    Delegates to the zero-dependency Invoke-GTGraphRequest with the -All switch,
    following @odata.nextLink until all items are accumulated. Provides 100% backward
    compatibility for existing GraphTools cmdlets.

    .PARAMETER Uri
    Initial relative or absolute Microsoft Graph URI.

    .PARAMETER Headers
    Optional hashtable of HTTP headers passed to the request (e.g. @{ ConsistencyLevel = 'eventual' }).

    .OUTPUTS
    System.Object[]
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [hashtable]$Headers
    )

    return (Invoke-GTGraphRequest -Uri $Uri -Headers $Headers -All)
}

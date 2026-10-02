function Format-GTODataDateTime
{
    <#
    .SYNOPSIS
    Formats a DateTime object to the ISO 8601 format required for Microsoft Graph OData filters.

    .DESCRIPTION
    Converts a DateTime to the 'yyyy-MM-ddTHH:mm:ssZ' format used in Microsoft Graph API OData queries.
    This ensures consistent formatting across all Graph API calls in the module.

    .PARAMETER DateTime
    The DateTime object to format.

    .EXAMPLE
    $date = (Get-Date).AddDays(-7)
    Format-GTODataDateTime -DateTime $date
    Returns: "2023-11-16T12:00:00Z" (example output)

    .OUTPUTS
    [string]
    #>
    [Alias('Format-ODataDateTime')]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [DateTime]$DateTime
    )

    $DateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
}
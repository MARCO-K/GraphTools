<#
.SYNOPSIS
    Validates the format of a User Principal Name (UPN).
.DESCRIPTION
    This function checks if a given string is a valid UPN format (e.g., user@domain.com).
.PARAMETER UPN
    The UPN to validate.
.EXAMPLE
    PS C:\> Test-GTUPN -UPN "test.user@example.com"
    True
.EXAMPLE
    PS C:\> Test-GTUPN -UPN "invalid-upn"
    False
#>
function Test-GTUPN
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$UPN
    )

    Process {
        # UPNs typically follow the RFC 822 format, which is similar to an email address.
        # This regex is a common pattern for email validation.
        $regex = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        return [bool]($UPN -match $regex)
    }
}
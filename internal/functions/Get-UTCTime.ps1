function Get-UTCTime
{
    <#
    .SYNOPSIS
    Gets the current UTC time as a DateTime object.

    .DESCRIPTION
    Returns the current UTC time using (Get-Date).ToUniversalTime().
    This provides consistent UTC time handling across the GraphTools module.

    .EXAMPLE
    $utcNow = Get-UTCTime
    Returns the current UTC time as a DateTime object.

    .OUTPUTS
    [DateTime]

    .NOTES
    Internal helper function for consistent UTC time handling across GraphTools module functions.
    Introduced in version 0.14.2 to standardize UTC time retrieval.
    Used by multiple internal and public module functions.
    #>
    [OutputType([DateTime])]
    param()

    (Get-Date).ToUniversalTime()
}
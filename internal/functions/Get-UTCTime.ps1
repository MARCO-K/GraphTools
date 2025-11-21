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
    #>
    [OutputType([DateTime])]
    param()

    (Get-Date).ToUniversalTime()
}
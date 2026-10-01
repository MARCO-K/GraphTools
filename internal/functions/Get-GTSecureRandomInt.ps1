function Get-GTSecureRandomInt
{
    <#
    .SYNOPSIS
        Generates a cryptographically secure random integer within a specified range.
    .DESCRIPTION
        Generates a cryptographically secure pseudo-random integer in the half-open interval [Minimum, Maximum)
        using System.Security.Cryptography.RandomNumberGenerator with rejection sampling to eliminate modulo bias.
        Compatible with both Windows PowerShell 5.1 and PowerShell 7+.
    .PARAMETER Minimum
        The inclusive lower bound of the random number returned. Defaults to 0.
    .PARAMETER Maximum
        The exclusive upper bound of the random number returned. Maximum must be greater than Minimum.
    .OUTPUTS
        System.Int32
    .EXAMPLE
        Get-GTSecureRandomInt -Minimum 1 -Maximum 3
        # Returns 1 or 2 with uniform probability.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Position = 0)]
        [int]$Minimum = 0,

        [Parameter(Mandatory = $true, Position = 1)]
        [int]$Maximum
    )

    if ($Maximum -le $Minimum)
    {
        throw "Maximum ($Maximum) must be greater than Minimum ($Minimum)."
    }

    $range = [uint64]([int64]$Maximum - [int64]$Minimum)
    $fullSets = [uint32]::MaxValue - ([uint32]::MaxValue % $range)
    $byteBuffer = [byte[]]::new(4)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try
    {
        do
        {
            $rng.GetBytes($byteBuffer)
            $rand = [BitConverter]::ToUInt32($byteBuffer, 0)
        } while ($rand -ge $fullSets)

        return [int]([int64]$Minimum + ([int64]($rand % $range)))
    }
    finally
    {
        $rng.Dispose()
    }
}

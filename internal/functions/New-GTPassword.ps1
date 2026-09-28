function New-GTPassword
{
    <#
    .SYNOPSIS
        Generates a secure random password
    .DESCRIPTION
        Creates a cryptographically random password that meets complexity requirements.
        The password includes at least one character from each category:
        - Uppercase letters (A-Z)
        - Lowercase letters (a-z)
        - Numbers (0-9)
        - Special characters (!@#$%^&*()_+-=[]{}|;:,.<>?/`~)
    .PARAMETER CharacterCount
        The total number of characters in the generated password.
        Must be between 10 and 20 characters. Defaults to 12.
    .EXAMPLE
        New-GTPassword
        
        Generates a 12-character random password with mixed case, numbers, and special characters
    .EXAMPLE
        New-GTPassword -CharacterCount 16
        
        Generates a 16-character random password
    #>
    [CmdletBinding()]
    param (
        [ValidateRange(10, 20)]
        [int]$CharacterCount = 12
    )

    # Define character sets
    $Uppercase = 65..90 | ForEach-Object { [char]$_ }   # A-Z
    $Lowercase = 97..122 | ForEach-Object { [char]$_ }  # a-z
    $Numbers   = 48..57 | ForEach-Object { [char]$_ }   # 0-9
    $Special   = [char[]]'!@#$%^&*()_+-=[]{}|;:,.<>?/`~'

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $byteBuffer = [byte[]]::new(4)

    # Rejection sampling helper to eliminate modulo bias
    $GetSecureBoundedIndex = {
        param([uint32]$Max)
        $fullSets = [uint32]::MaxValue - ([uint32]::MaxValue % $Max)
        do {
            $rng.GetBytes($byteBuffer)
            $rand = [BitConverter]::ToUInt32($byteBuffer, 0)
        } while ($rand -ge $fullSets)
        return [int]($rand % $Max)
    }

    try {
        # Ensure at least one character from each set
        $Password = [System.Collections.Generic.List[char]]::new()
        $Password.Add($Uppercase[(& $GetSecureBoundedIndex -Max $Uppercase.Count)])
        $Password.Add($Lowercase[(& $GetSecureBoundedIndex -Max $Lowercase.Count)])
        $Password.Add($Numbers[(& $GetSecureBoundedIndex -Max $Numbers.Count)])
        $Password.Add($Special[(& $GetSecureBoundedIndex -Max $Special.Count)])

        # Fill remaining characters randomly from all sets
        $AllChars = $Uppercase + $Lowercase + $Numbers + $Special
        while ($Password.Count -lt $CharacterCount) {
            $Password.Add($AllChars[(& $GetSecureBoundedIndex -Max $AllChars.Count)])
        }

        # Fisher-Yates shuffle with rejection sampling
        for ($i = $Password.Count - 1; $i -gt 0; $i--) {
            $j = & $GetSecureBoundedIndex -Max ($i + 1)
            $temp = $Password[$i]
            $Password[$i] = $Password[$j]
            $Password[$j] = $temp
        }

        return (-join $Password)
    }
    finally {
        $rng.Dispose()
    }
}

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
    param (
        [ValidateRange(10, 20)][int]$CharacterCount = 12
    )

    # Define character sets
    $Uppercase = 65..90 | ForEach-Object { [char]$_ }   # A-Z
    $Lowercase = 97..122 | ForEach-Object { [char]$_ }  # a-z
    $Numbers = 48..57 | ForEach-Object { [char]$_ }   # 0-9
    $Special = '!@#$%^&*()_+-=[]{}|;:,.<>?/`~' -split ''

    # Initialize cryptographic random number generator
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    # Helper scriptblock to select random items
    $GetRandomElement = {
        param([array]$Array, [int]$Count = 1)
        $result = @()
        for ($i = 0; $i -lt $Count; $i++) {
            $bytes = New-Object byte[] 4
            $rng.GetBytes($bytes)
            # Use bitwise AND to ensure positive integer and avoid Math.Abs overflow on Int32.MinValue
            $index = ([BitConverter]::ToInt32($bytes, 0) -band 0x7FFFFFFF) % $Array.Count
            $result += $Array[$index]
        }
        if ($Count -eq 1) { return $result[0] }
        return $result
    }

    # Ensure at least one character from each set
    $Password = @(
        (& $GetRandomElement -Array $Uppercase)
        (& $GetRandomElement -Array $Lowercase)
        (& $GetRandomElement -Array $Numbers)
        (& $GetRandomElement -Array $Special)
    )

    # Fill remaining characters randomly from all sets
    $AllChars = $Uppercase + $Lowercase + $Numbers + $Special
    $remainingCount = $CharacterCount - $Password.Count
    if ($remainingCount -gt 0) {
        $Password += & $GetRandomElement -Array $AllChars -Count $remainingCount
    }

    # Shuffle the password cryptographically
    $shuffledPassword = $Password | ForEach-Object {
        $bytes = New-Object byte[] 4
        $rng.GetBytes($bytes)
        [PSCustomObject]@{
            Char = $_
            Rand = [BitConverter]::ToInt32($bytes, 0)
        }
    } | Sort-Object Rand | Select-Object -ExpandProperty Char

    $rng.Dispose()

    -join $shuffledPassword
}
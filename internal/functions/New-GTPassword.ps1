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

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $byteBuffer = [byte[]]::new(4)

    # Helper function to get secure random items
    $GetSecureRandomItem = {
        param([array]$Collection, [int]$Count)
        $result = @()
        for ($i = 0; $i -lt $Count; $i++) {
            $rng.GetBytes($byteBuffer)
            $index = [BitConverter]::ToUInt32($byteBuffer, 0) % $Collection.Count
            $result += $Collection[$index]
        }
        return $result
    }

    try {
        # Ensure at least one character from each set
        $Password = @(
            (& $GetSecureRandomItem -Collection $Uppercase -Count 1)
            (& $GetSecureRandomItem -Collection $Lowercase -Count 1)
            (& $GetSecureRandomItem -Collection $Numbers -Count 1)
            (& $GetSecureRandomItem -Collection $Special -Count 1)
        )

        # Fill remaining characters randomly from all sets
        $AllChars = $Uppercase + $Lowercase + $Numbers + $Special
        $remaining = $CharacterCount - $Password.Count
        if ($remaining -gt 0) {
            $Password += (& $GetSecureRandomItem -Collection $AllChars -Count $remaining)
        }

        # Shuffle the password securely (Fisher-Yates)
        for ($i = $Password.Count - 1; $i -gt 0; $i--) {
            $rng.GetBytes($byteBuffer)
            $j = [BitConverter]::ToUInt32($byteBuffer, 0) % ($i + 1)
            $temp = $Password[$i]
            $Password[$i] = $Password[$j]
            $Password[$j] = $temp
        }

        $Password = -join $Password
    } finally {
        $rng.Dispose()
    }

    $Password
}
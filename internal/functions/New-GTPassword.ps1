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

    # Ensure at least one character from each set
    $Password = [System.Collections.Generic.List[char]]::new()
    $Password.Add($Uppercase[(Get-GTSecureRandomInt -Maximum $Uppercase.Count)])
    $Password.Add($Lowercase[(Get-GTSecureRandomInt -Maximum $Lowercase.Count)])
    $Password.Add($Numbers[(Get-GTSecureRandomInt -Maximum $Numbers.Count)])
    $Password.Add($Special[(Get-GTSecureRandomInt -Maximum $Special.Count)])

    # Fill remaining characters randomly from all sets
    $AllChars = $Uppercase + $Lowercase + $Numbers + $Special
    while ($Password.Count -lt $CharacterCount) {
        $Password.Add($AllChars[(Get-GTSecureRandomInt -Maximum $AllChars.Count)])
    }

    # Fisher-Yates shuffle using CSPRNG
    for ($i = $Password.Count - 1; $i -gt 0; $i--) {
        $j = Get-GTSecureRandomInt -Maximum ($i + 1)
        $temp = $Password[$i]
        $Password[$i] = $Password[$j]
        $Password[$j] = $temp
    }

    return (-join $Password)
}

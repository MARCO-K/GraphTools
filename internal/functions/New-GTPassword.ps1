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

    # Ensure at least one character from each set
    $Password = @(
        ($Uppercase | Get-Random -Count 1)
        ($Lowercase | Get-Random -Count 1)
        ($Numbers   | Get-Random -Count 1)
        ($Special   | Get-Random -Count 1)
    )

    # Fill remaining characters randomly from all sets
    $AllChars = $Uppercase + $Lowercase + $Numbers + $Special
    $Password += ($AllChars | Get-Random -Count ($CharacterCount - $Password.Count))

    # Shuffle the password
    $Password = -join ($Password | Get-Random -Count $Password.Count)

    $Password
}
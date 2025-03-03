function New-GTPassword
{
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
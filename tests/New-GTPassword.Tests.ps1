Describe "New-GTPassword" -Tag 'Unit' {
    BeforeAll {
        . "$PSScriptRoot/../internal/functions/New-GTPassword.ps1"
    }

    Context "Parameter Validation" {
        It "defaults to 12 characters when CharacterCount is omitted" {
            $password = New-GTPassword
            $password.Length | Should -Be 12
        }

        It "accepts valid CharacterCount boundaries" -TestCases @(
            @{ Count = 10 }
            @{ Count = 12 }
            @{ Count = 16 }
            @{ Count = 20 }
        ) {
            param($Count)
            $password = New-GTPassword -CharacterCount $Count
            $password.Length | Should -Be $Count
        }

        It "throws validation error when CharacterCount is below 10" {
            { New-GTPassword -CharacterCount 9 } | Should -Throw
        }

        It "throws validation error when CharacterCount exceeds 20" {
            { New-GTPassword -CharacterCount 21 } | Should -Throw
        }
    }

    Context "Cryptographic & Complexity Constraints" {
        It "consistently satisfies all character category requirements across 200 iterations" {
            $specialPattern = '[!@#\$%\^&\*\(\)_\+\-=\[\]\{\}\|;:,\.<>\?\/`~]'

            for ($i = 0; $i -lt 200; $i++) {
                $pwd = New-GTPassword -CharacterCount 12
                $pwd.Length | Should -Be 12 -Because "Password length must strictly match CharacterCount on iteration $i"
                $pwd | Should -Match '[A-Z]' -Because "Password must contain uppercase letters on iteration $i"
                $pwd | Should -Match '[a-z]' -Because "Password must contain lowercase letters on iteration $i"
                $pwd | Should -Match '[0-9]' -Because "Password must contain numbers on iteration $i"
                $pwd | Should -Match $specialPattern -Because "Password must contain special characters on iteration $i"
            }
        }

        It "generates unique passwords on successive calls" {
            $passwords = 1..20 | ForEach-Object { New-GTPassword }
            $uniqueCount = ($passwords | Select-Object -Unique).Count
            $uniqueCount | Should -Be 20
        }
    }
}

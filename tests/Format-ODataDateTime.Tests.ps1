# Pester tests for Format-ODataDateTime
# Requires Pester 5.x

Describe "Format-ODataDateTime" -Tag 'Unit' {
    BeforeAll {
        . "$PSScriptRoot/../internal/functions/Format-ODataDateTime.ps1"
    }

    Context "Formatting DateTime objects" {
        It "should format a specific DateTime object correctly" {
            $date = [DateTime]::new(2023, 11, 16, 12, 34, 56)
            $result = Format-ODataDateTime -DateTime $date
            $result | Should -Be '2023-11-16T12:34:56Z'
        }

        It "should format a string castable to DateTime correctly" {
            # PowerShell implicitly casts standard date strings to DateTime
            $result = Format-ODataDateTime -DateTime "2024-01-01 15:00:00"
            $result | Should -Be '2024-01-01T15:00:00Z'
        }

        It "should format DateTime.MinValue correctly" {
            $date = [DateTime]::MinValue
            $result = Format-ODataDateTime -DateTime $date
            $result | Should -Be '0001-01-01T00:00:00Z'
        }

        It "should format DateTime.MaxValue correctly" {
            $date = [DateTime]::MaxValue
            $result = Format-ODataDateTime -DateTime $date
            $result | Should -Be '9999-12-31T23:59:59Z'
        }
    }

    Context "Error conditions" {
        It "should throw if invalid string is provided that cannot be cast to DateTime" {
            { Format-ODataDateTime -DateTime "not-a-date" } | Should -Throw
        }
    }
}

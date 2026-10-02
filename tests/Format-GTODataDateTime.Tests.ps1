# Pester tests for Format-GTODataDateTime
# Requires Pester 5.x

Describe "Format-GTODataDateTime" -Tag 'Unit' {
    BeforeAll {
        $functionFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Format-GTODataDateTime.ps1'
        if (-not (Test-Path $functionFile)) { Throw "Function file not found: $functionFile" }
        . $functionFile
    }

    AfterAll {
        Remove-Item Function:\Format-GTODataDateTime -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Format-ODataDateTime -Force -ErrorAction SilentlyContinue
    }

    Context "Alias Support" {
        It "resolves legacy Format-ODataDateTime alias to Format-GTODataDateTime" {
            (Get-Command Format-ODataDateTime).ResolvedCommandName | Should -Be 'Format-GTODataDateTime'
        }
    }

    Context "Parameter Validation" {
        It "should require DateTime parameter" {
            (Get-Command Format-GTODataDateTime).Parameters['DateTime'].Attributes.Mandatory -contains $true | Should -BeTrue
        }
    }

    Context "Formatting DateTime objects" {
        It "should format a specific DateTime object correctly" {
            $date = [DateTime]::new(2023, 11, 16, 12, 34, 56)
            $result = Format-GTODataDateTime -DateTime $date
            $result | Should -Be '2023-11-16T12:34:56Z'
        }

        It "should format a string castable to DateTime correctly" {
            # PowerShell implicitly casts standard date strings to DateTime
            $result = Format-GTODataDateTime -DateTime "2024-01-01 15:00:00"
            $result | Should -Be '2024-01-01T15:00:00Z'
        }

        It "should format DateTime.MinValue correctly" {
            $date = [DateTime]::MinValue
            $result = Format-GTODataDateTime -DateTime $date
            $result | Should -Be '0001-01-01T00:00:00Z'
        }

        It "should format DateTime.MaxValue correctly" {
            $date = [DateTime]::MaxValue
            $result = Format-GTODataDateTime -DateTime $date
            $result | Should -Be '9999-12-31T23:59:59Z'
        }
    }

    Context "Error conditions" {
        It "should throw if null is provided for DateTime" {
            { Format-GTODataDateTime -DateTime $null } | Should -Throw
        }

        It "should throw if invalid string is provided that cannot be cast to DateTime" {
            { Format-GTODataDateTime -DateTime "not-a-date" } | Should -Throw
        }
    }
}

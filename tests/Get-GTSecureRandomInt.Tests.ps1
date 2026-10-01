Describe "Get-GTSecureRandomInt" -Tag 'Unit' {
    BeforeAll {
        $functionFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Get-GTSecureRandomInt.ps1'
        if (-not (Test-Path $functionFile)) { Throw "Function file not found: $functionFile" }
        . $functionFile
    }

    AfterAll {
        Remove-Item Function:\Get-GTSecureRandomInt -Force -ErrorAction SilentlyContinue
    }

    Context "Boundary Adherence & Return Typing" {
        It "returns an integer within [Minimum, Maximum) interval" {
            $sample = Get-GTSecureRandomInt -Minimum 1 -Maximum 3
            $sample | Should -BeOfType [int]
            $sample | Should -BeGreaterOrEqual 1
            $sample | Should -BeLessThan 3
        }

        It "generates all possible outcomes in a small range over multiple iterations" {
            $results = [System.Collections.Generic.HashSet[int]]::new()
            for ($i = 0; $i -lt 100; $i++) {
                $val = Get-GTSecureRandomInt -Minimum 1 -Maximum 3
                $val | Should -BeGreaterOrEqual 1
                $val | Should -BeLessThan 3
                [void]$results.Add($val)
            }
            $results.Contains(1) | Should -BeTrue
            $results.Contains(2) | Should -BeTrue
            $results.Contains(3) | Should -BeFalse
        }

        It "handles single-value range where Maximum is Minimum + 1" {
            for ($i = 0; $i -lt 20; $i++) {
                $val = Get-GTSecureRandomInt -Minimum 42 -Maximum 43
                $val | Should -Be 42
            }
        }

        It "defaults Minimum to 0 when omitted" {
            $results = [System.Collections.Generic.HashSet[int]]::new()
            for ($i = 0; $i -lt 50; $i++) {
                $val = Get-GTSecureRandomInt -Maximum 5
                $val | Should -BeGreaterOrEqual 0
                $val | Should -BeLessThan 5
                [void]$results.Add($val)
            }
            $results.Count | Should -BeGreaterThan 1
        }

        It "handles negative ranges correctly" {
            for ($i = 0; $i -lt 50; $i++) {
                $val = Get-GTSecureRandomInt -Minimum -10 -Maximum -5
                $val | Should -BeGreaterOrEqual -10
                $val | Should -BeLessThan -5
            }
        }
    }

    Context "Parameter Validation" {
        It "throws when Maximum is equal to Minimum" {
            { Get-GTSecureRandomInt -Minimum 5 -Maximum 5 } | Should -Throw "*must be greater than*"
        }

        It "throws when Maximum is less than Minimum" {
            { Get-GTSecureRandomInt -Minimum 10 -Maximum 2 } | Should -Throw "*must be greater than*"
        }
    }
}

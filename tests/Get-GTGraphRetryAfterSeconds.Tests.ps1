Describe "Get-GTGraphRetryAfterSeconds" -Tag 'Unit' {
    BeforeAll {
        $functionFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Get-GTGraphRetryAfterSeconds.ps1'
        if (-not (Test-Path $functionFile)) { Throw "Function file not found: $functionFile" }
        . $functionFile
    }

    AfterAll {
        Remove-Item Function:\Get-GTGraphRetryAfterSeconds -Force -ErrorAction SilentlyContinue
    }

    Context "Headers Parameter" {
        It "extracts seconds from RetryAfter.Delta TimeSpan object" {
            $headers = [PSCustomObject]@{
                RetryAfter = [PSCustomObject]@{
                    Delta = [TimeSpan]::FromSeconds(45)
                }
            }
            $seconds = Get-GTGraphRetryAfterSeconds -Headers $headers
            $seconds | Should -Be 45
        }

        It "extracts integer seconds from hashtable with 'Retry-After' key" {
            $headers = @{
                'Retry-After' = '30'
            }
            $seconds = Get-GTGraphRetryAfterSeconds -Headers $headers
            $seconds | Should -Be 30
        }

        It "matches header keys case-insensitively" {
            $headers = @{
                'retry-after' = '15'
            }
            $seconds = Get-GTGraphRetryAfterSeconds -Headers $headers
            $seconds | Should -Be 15
        }

        It "extracts integer seconds from PSCustomObject properties" {
            $headers = [PSCustomObject]@{
                'Retry-After' = '20'
            }
            $seconds = Get-GTGraphRetryAfterSeconds -Headers $headers
            $seconds | Should -Be 20
        }

        It "parses RFC 1123 HTTP-date and computes positive delta seconds" {
            $futureDate = [DateTime]::UtcNow.AddSeconds(60).ToString('R')
            $headers = @{
                'Retry-After' = $futureDate
            }
            $seconds = Get-GTGraphRetryAfterSeconds -Headers $headers
            $seconds | Should -BeGreaterThan 0
            $seconds | Should -BeLessOrEqual 65
        }

        It "enforces minimum 1 second delay for past dates" {
            $pastDate = [DateTime]::UtcNow.AddSeconds(-30).ToString('R')
            $headers = @{
                'Retry-After' = $pastDate
            }
            $seconds = Get-GTGraphRetryAfterSeconds -Headers $headers
            $seconds | Should -Be 1
        }

        It "returns null for non-parsable string value" {
            $headers = @{
                'Retry-After' = 'invalid-header-value'
            }
            $seconds = Get-GTGraphRetryAfterSeconds -Headers $headers
            $seconds | Should -BeNullOrEmpty
        }

        It "returns null when no Retry-After header exists" {
            $headers = @{
                'Content-Type' = 'application/json'
            }
            $seconds = Get-GTGraphRetryAfterSeconds -Headers $headers
            $seconds | Should -BeNullOrEmpty
        }

        It "returns null for null headers input" {
            $seconds = Get-GTGraphRetryAfterSeconds -Headers $null
            $seconds | Should -BeNullOrEmpty
        }
    }

    Context "Exception Parameter" {
        It "extracts retry seconds from Exception.Response.Headers" {
            $mockEx = [PSCustomObject]@{
                Response = [PSCustomObject]@{
                    Headers = @{
                        'Retry-After' = '12'
                    }
                }
            }
            $seconds = Get-GTGraphRetryAfterSeconds -Exception $mockEx
            $seconds | Should -Be 12
        }

        It "extracts retry seconds from Exception.InnerException.Response.Headers" {
            $mockEx = [PSCustomObject]@{
                Response       = $null
                InnerException = [PSCustomObject]@{
                    Response = [PSCustomObject]@{
                        Headers = @{
                            'Retry-After' = '25'
                        }
                    }
                }
            }
            $seconds = Get-GTGraphRetryAfterSeconds -Exception $mockEx
            $seconds | Should -Be 25
        }

        It "returns null when Exception contains no headers" {
            $mockEx = [PSCustomObject]@{
                Response       = $null
                InnerException = $null
                Message        = "Throttled without headers"
            }
            $seconds = Get-GTGraphRetryAfterSeconds -Exception $mockEx
            $seconds | Should -BeNullOrEmpty
        }

        It "returns null for null Exception input" {
            $seconds = Get-GTGraphRetryAfterSeconds -Exception $null
            $seconds | Should -BeNullOrEmpty
        }
    }
}

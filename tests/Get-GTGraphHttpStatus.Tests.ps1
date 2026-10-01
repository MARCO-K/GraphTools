Describe "Get-GTGraphHttpStatus" -Tag 'Unit' {
    BeforeAll {
        $functionFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Get-GTGraphHttpStatus.ps1'
        if (-not (Test-Path $functionFile)) { Throw "Function file not found: $functionFile" }
        . $functionFile
    }

    AfterAll {
        Remove-Item Function:\Get-GTGraphHttpStatus -Force -ErrorAction SilentlyContinue
    }

    Context "Response StatusCode Extraction" {
        It "extracts integer status code from Exception.Response.StatusCode" {
            $mockEx = [PSCustomObject]@{
                Response = [PSCustomObject]@{ StatusCode = 404 }
                Message  = "Item not found"
            }
            $status = Get-GTGraphHttpStatus -Exception $mockEx
            $status | Should -Be 404
        }

        It "extracts integer status code from Exception.InnerException.Response.StatusCode" {
            $mockEx = [PSCustomObject]@{
                Response       = $null
                InnerException = [PSCustomObject]@{
                    Response = [PSCustomObject]@{ StatusCode = 429 }
                }
                Message        = "Throttled"
            }
            $status = Get-GTGraphHttpStatus -Exception $mockEx
            $status | Should -Be 429
        }
    }

    Context "Message Regex Fallback" {
        It "extracts status code from message pattern matching" -TestCases @(
            @{ Message = "Error 400 Bad Request"; Expected = 400 }
            @{ Message = "Unauthorized (401)"; Expected = 401 }
            @{ Message = "Server returned 403 Forbidden"; Expected = 403 }
            @{ Message = "Resource 404 was not found"; Expected = 404 }
            @{ Message = "Request throttled with 429"; Expected = 429 }
            @{ Message = "General failure 500"; Expected = 500 }
            @{ Message = "Bad gateway 502"; Expected = 502 }
            @{ Message = "Service unavailable 503"; Expected = 503 }
            @{ Message = "Gateway timeout 504"; Expected = 504 }
            @{ Message = "The item was not found in directory"; Expected = 404 }
            @{ Message = "Insufficient privileges to complete the operation"; Expected = 403 }
            @{ Message = "User was throttled due to high activity"; Expected = 429 }
            @{ Message = "Unauthorized access attempt"; Expected = 401 }
            @{ Message = "Bad Request syntax encountered"; Expected = 400 }
        ) {
            param($Message, $Expected)
            $mockEx = [PSCustomObject]@{
                Response       = $null
                InnerException = $null
                Message        = $Message
            }
            $status = Get-GTGraphHttpStatus -Exception $mockEx
            $status | Should -Be $Expected
        }

        It "returns null when no status code is detectable" {
            $mockEx = [PSCustomObject]@{
                Response       = $null
                InnerException = $null
                Message        = "Unknown network error without numbers"
            }
            $status = Get-GTGraphHttpStatus -Exception $mockEx
            $status | Should -BeNullOrEmpty
        }

        It "returns null for null exception" {
            $status = Get-GTGraphHttpStatus -Exception $null
            $status | Should -BeNullOrEmpty
        }
    }
}

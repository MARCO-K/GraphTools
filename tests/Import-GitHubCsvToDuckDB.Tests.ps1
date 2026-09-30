Describe "Import-GitHubCsvToDuckDB" {
    BeforeAll {
        function global:Write-PSFMessage { param($Level, $Message) }
        function global:New-DuckDBConnection { param($DB) return [PSCustomObject]@{ sql = { param($q) }; Close = { } } }

        . "$PSScriptRoot/../internal/functions/Import-GitHubCsvToDuckDB.ps1"
    }

    AfterAll {
        Remove-Item Function:\global:Write-PSFMessage -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:New-DuckDBConnection -Force -ErrorAction SilentlyContinue
    }

    Context "GitHub API URL and Branch Encoding" {
        It "should query GitHub API with URL encoded ref parameter" {
            Mock -CommandName Invoke-RestMethod -MockWith {
                return @(
                    [PSCustomObject]@{ name = 'users.csv'; download_url = 'https://raw.githubusercontent.com/org/repo/feature/users.csv' }
                )
            }
            $mockConn = [PSCustomObject]@{
                Close = { }
            } | Add-Member -MemberType ScriptMethod -Name sql -Value { param($q) } -PassThru
            Mock -CommandName Write-PSFMessage -MockWith { }

            Import-GitHubCsvToDuckDB -Owner 'myorg' -Repository 'myrepo' -Branch 'feature/test-branch' -Directory 'data' -DBConn $mockConn

            Assert-MockCalled -CommandName Invoke-RestMethod -Times 1 -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/myorg/myrepo/contents/data?ref=feature%2Ftest-branch'
            }
        }
    }

    Context "Table Creation and Fail-Fast Error Propagation" {
        It "should throw when table creation fails" {
            Mock -CommandName Invoke-RestMethod -MockWith {
                return @(
                    [PSCustomObject]@{ name = 'users.csv'; download_url = 'https://raw.githubusercontent.com/org/repo/main/users.csv' }
                )
            }
            $mockConn = [PSCustomObject]@{
                sql = { param($q) throw "DuckDB syntax error" }
            }

            { Import-GitHubCsvToDuckDB -Owner 'myorg' -Repository 'myrepo' -Directory 'data' -DBConn $mockConn } | Should -Throw
        }

        It "should throw when GitHub API fails" {
            Mock -CommandName Invoke-RestMethod -MockWith {
                throw "GitHub 404 Not Found"
            }
            $mockConn = [PSCustomObject]@{
                sql = { param($q) }
            }

            { Import-GitHubCsvToDuckDB -Owner 'myorg' -Repository 'myrepo' -Directory 'data' -DBConn $mockConn } | Should -Throw
        }
    }
}

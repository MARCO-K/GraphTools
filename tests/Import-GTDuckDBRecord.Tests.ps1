Describe "Import-GTDuckDBRecord" {
    BeforeAll {
        function global:Write-PSFMessage { param($Level, $Message) }
        function global:New-DuckDBConnection { param($DB) return [PSCustomObject]@{ sql = { param($q) }; Close = { } } }

        . "$PSScriptRoot/../internal/functions/Import-GTDuckDBRecord.ps1"
    }

    AfterAll {
        Remove-Item Function:\global:Write-PSFMessage -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:New-DuckDBConnection -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Import-GTDuckDBRecord -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Import-DuckDBRecords -Force -ErrorAction SilentlyContinue
    }

    Context "Alias Support" {
        It "resolves legacy Import-DuckDBRecords alias to Import-GTDuckDBRecord" {
            (Get-Command Import-DuckDBRecords).ResolvedCommandName | Should -Be 'Import-GTDuckDBRecord'
        }
    }

    Context "Pipeline Processing and Deduplication" {
        It "should accumulate records and deduplicate in end block" {
            $executedQueries = [System.Collections.Generic.List[string]]::new()
            $mockConn = [PSCustomObject]@{} |
                Add-Member -MemberType ScriptMethod -Name Close -Value { } -PassThru |
                Add-Member -MemberType ScriptMethod -Name sql -Value {
                    param($q)
                    $executedQueries.Add($q)
                    if ($q -like "SELECT COUNT(*)*") {
                        return [PSCustomObject]@{ 'count_star()' = 2 }
                    }
                } -PassThru

            $records = @(
                [PSCustomObject]@{ ID = 'rec-1'; Name = 'Alice'; Age = 30 }
                [PSCustomObject]@{ ID = 'rec-2'; Name = 'Bob'; Age = 25 }
                [PSCustomObject]@{ ID = 'rec-1'; Name = 'Alice Duplicate'; Age = 30 }
            )

            $records | Import-GTDuckDBRecord -TableName 'Users' -DBConn $mockConn

            # Verify table creation query
            $executedQueries | Should -Contain "CREATE OR REPLACE TABLE Users (ID VARCHAR, Name VARCHAR, Age INTEGER);"
            # Verify transaction control
            $executedQueries | Should -Contain "BEGIN TRANSACTION"
            $executedQueries | Should -Contain "COMMIT"
            # Verify that only 2 unique inserts were executed (not 3)
            $inserts = $executedQueries | Where-Object { $_ -like "INSERT INTO Users VALUES*" }
            $inserts.Count | Should -Be 2
        }

        It "should skip records missing the ID property" {
            $executedQueries = [System.Collections.Generic.List[string]]::new()
            $mockConn = [PSCustomObject]@{} |
                Add-Member -MemberType ScriptMethod -Name Close -Value { } -PassThru |
                Add-Member -MemberType ScriptMethod -Name sql -Value {
                    param($q)
                    $executedQueries.Add($q)
                    if ($q -like "SELECT COUNT(*)*") {
                        return [PSCustomObject]@{ 'count_star()' = 1 }
                    }
                } -PassThru

            $records = @(
                [PSCustomObject]@{ ID = 'valid-1'; Name = 'Valid' }
                [PSCustomObject]@{ OtherProp = 'no-id'; Name = 'Invalid' }
            )

            $records | Import-GTDuckDBRecord -TableName 'ValidOnly' -DBConn $mockConn

            $inserts = $executedQueries | Where-Object { $_ -like "INSERT INTO ValidOnly VALUES*" }
            $inserts.Count | Should -Be 1
        }

        It "should throw when no unique records are found" {
            $mockConn = [PSCustomObject]@{} |
                Add-Member -MemberType ScriptMethod -Name Close -Value { } -PassThru |
                Add-Member -MemberType ScriptMethod -Name sql -Value { param($q) } -PassThru

            $records = @(
                [PSCustomObject]@{ OtherProp = 'no-id-1' }
                [PSCustomObject]@{ OtherProp = 'no-id-2' }
            )

            { $records | Import-GTDuckDBRecord -TableName 'NoRecords' -DBConn $mockConn } | Should -Throw "*No unique records found for processing*"
        }

        It "should safely escape single quotes without mutating data" {
            $executedQueries = [System.Collections.Generic.List[string]]::new()
            $mockConn = [PSCustomObject]@{} |
                Add-Member -MemberType ScriptMethod -Name Close -Value { } -PassThru |
                Add-Member -MemberType ScriptMethod -Name sql -Value {
                    param($q)
                    $executedQueries.Add($q)
                    if ($q -like "SELECT COUNT(*)*") {
                        return [PSCustomObject]@{ 'count_star()' = 1 }
                    }
                } -PassThru

            $records = @(
                [PSCustomObject]@{ ID = 'user-1'; Name = "O'Connor"; Note = "User's test note" }
            )

            $records | Import-GTDuckDBRecord -TableName 'EscapedUsers' -DBConn $mockConn

            $insert = $executedQueries | Where-Object { $_ -like "INSERT INTO EscapedUsers VALUES*" }
            $insert | Should -Be "INSERT INTO EscapedUsers VALUES ('user-1', 'O''Connor', 'User''s test note')"
        }
    }
}

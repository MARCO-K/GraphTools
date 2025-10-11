. "$PSScriptRoot/../functions/Invoke-AuditLogQuery.ps1"

BeforeAll {
    # Mock the required modules and functions
    Mock -ModuleName "Microsoft.Graph.Authentication" -CommandName "Install-GTRequiredModule" -MockWith { }
    Mock -ModuleName "Microsoft.Graph.Authentication" -CommandName "Test-GTGraphScopes" -MockWith { $true }
    Mock -ModuleName "Microsoft.Graph.Authentication" -CommandName "Set-MgRequestContext" -MockWith { }
}

Describe "Invoke-AuditLogQuery" {
    BeforeEach {
        $mockRecords = @(
            @{
                Id = "test-record-1"
                Operation = "FileDeleted"
                UserId = "user1@contoso.com"
                auditData = "{'some':'data'}"
                createdDateTime = (Get-Date).AddDays(-1)
            },
            @{
                Id = "test-record-2"
                Operation = "FileModified"
                UserId = "user2@contoso.com"
                auditData = "{'other':'data'}"
                createdDateTime = (Get-Date).AddDays(-8)
            }
        )

        Mock -ModuleName "Microsoft.Graph.Authentication" -CommandName "Invoke-MgGraphRequest" -MockWith {
            param($Uri, $Body)
            if ($Uri -like "*auditLog/queries*") {
                return @{
                    Id = "test-query-id"
                    status = "succeeded"
                }
            }
            if ($Uri -like "*records*") {
                $filter = $Body | ConvertFrom-Json
                $records = $mockRecords
                if ($filter.filter.OperationFilters) {
                    $records = $records | Where-Object { $_.Operation -in $filter.filter.OperationFilters }
                }
                if ($filter.filter.userIdsFilters) {
                    $records = $records | Where-Object { $_.UserId -in $filter.filter.userIdsFilters }
                }
                $startDate = Get-Date($filter.filter.filterStartDateTime)
                $records = $records | Where-Object { $_.createdDateTime -ge $startDate }

                return @{
                    value = $records
                }
            }
        }
    }

    It "should return all audit log records when no filters are applied" {
        $result = Invoke-AuditLogQuery
        $result.Count | Should -Be 2
    }

    It "should filter by operation" {
        $result = Invoke-AuditLogQuery -Operations "FileDeleted"
        $result.Count | Should -Be 1
        $result.Operation | Should -Be "FileDeleted"
    }

    It "should filter by user ID" {
        $result = Invoke-AuditLogQuery -UserIds "user1@contoso.com"
        $result.Count | Should -Be 1
        $result.UserId | Should -Be "user1@contoso.com"
    }

    It "should filter by date" {
        $result = Invoke-AuditLogQuery -StartDays 7
        $result.Count | Should -Be 1
        $result.Operation | Should -Be "FileDeleted"
    }

    It "should throw an error for invalid date range" {
        { Invoke-AuditLogQuery -StartDays 10 -EndDays 20 } | Should -Throw "Start date must be before end date."
    }

    It "should assign a custom type name to the output" {
        $result = Invoke-AuditLogQuery
        $result[0].PSObject.TypeNames[0] | Should -Be "GraphTools.AuditLogRecord"
    }

    It "should pass the correct filter to the API" {
        Invoke-AuditLogQuery -Operations "FileDeleted" -UserIds "user1@contoso.com"
        Assert-MockCalled -CommandName "Invoke-MgGraphRequest" -ParameterFilter {
            $body = $Body | ConvertFrom-Json
            ($body.filter.OperationFilters -contains "FileDeleted") -and ($body.filter.userIdsFilters -contains "user1@contoso.com")
        } -Times 1
    }
}
. "$PSScriptRoot/../functions/Invoke-AuditLogQuery.ps1"

BeforeAll {
    # Mock the required modules and functions
    Mock -ModuleName "Microsoft.Graph.Authentication" -CommandName "Install-GTRequiredModule" -MockWith { }
    Mock -ModuleName "Microsoft.Graph.Authentication" -CommandName "Test-GTGraphScopes" -MockWith { $true }
    Mock -ModuleName "Microsoft.Graph.Authentication" -CommandName "Set-MgRequestContext" -MockWith { }

    # Mock Get-Date to return a fixed timestamp
    $fixedNow = Get-Date '2025-10-10T00:00:00Z'
    Mock Get-Date { $fixedNow }
}

Describe "Invoke-AuditLogQuery" {
    BeforeEach {
        $script:storedFilter = $null
        $fixedNow = Get-Date '2025-10-10T00:00:00Z'
        $mockRecords = @(
            @{
                Id = "test-record-1"
                Operation = "FileDeleted"
                UserId = "user1@contoso.com"
                auditData = "{'some':'data'}"
                createdDateTime = $fixedNow.AddDays(-1)
            },
            @{
                Id = "test-record-2"
                Operation = "FileModified"
                UserId = "user2@contoso.com"
                auditData = "{'other':'data'}"
                createdDateTime = $fixedNow.AddDays(-8)
            }
        )

        Mock -ModuleName "Microsoft.Graph.Authentication" -CommandName "Invoke-MgGraphRequest" -MockWith {
            param($Uri, $Body, $Method)
            if ($Uri -like "*/auditLog/queries" -and $Method -eq "POST") {
                $script:storedFilter = ($Body | ConvertFrom-Json).filter
                return @{
                    Id = "test-query-id"
                    status = "succeeded"
                }
            }
            if ($Uri -like "*/auditLog/queries/test-query-id" -and $Method -eq "GET") {
                return @{
                    Id = "test-query-id"
                    status = "succeeded"
                }
            }
            if ($Uri -like "*/auditLog/queries/test-query-id/records" -and $Method -eq "GET") {
                $records = $mockRecords
                if ($script:storedFilter.OperationFilters) {
                    $records = $records | Where-Object { $_.Operation -in $script:storedFilter.OperationFilters }
                }
                if ($script:storedFilter.userIdsFilters) {
                    $records = $records | Where-Object { $_.UserId -in $script:storedFilter.userIdsFilters }
                }
                $startDate = Get-Date($script:storedFilter.filterStartDateTime)
                $records = $records | Where-Object { $_.createdDateTime -ge $startDate }

                return @{
                    value = $records
                }
            }
        }
    }

    It "should return all audit log records when no filters are applied" {
        $result = Invoke-AuditLogQuery -StartDays 30
        $result.Count | Should -Be 2
    }

    It "should filter by operation" {
        $result = Invoke-AuditLogQuery -Operations "FileDeleted"
        $result | ForEach-Object { $_.Operation } | Should -BeExactly 'FileDeleted'
    }

    It "should filter by user ID" {
        $result = Invoke-AuditLogQuery -UserIds "user1@contoso.com"
        $result.Count | Should -Be 1
        $result.UserId | Should -Be "user1@contoso.com"
    }

    It "drops records older than the start date" {
        $result = Invoke-AuditLogQuery -StartDays 7
        $result.Id | Should -BeExactly 'test-record-1'
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

    It "should call the correct URIs" {
        Invoke-AuditLogQuery -Delete
        Assert-MockCalled -CommandName "Invoke-MgGraphRequest" -ParameterFilter { $Uri -like "*/auditLog/queries" -and $Method -eq "POST" } -Times 1
        Assert-MockCalled -CommandName "Invoke-MgGraphRequest" -ParameterFilter { $Uri -eq "/beta/security/auditLog/queries/test-query-id" -and $Method -eq "GET" } -AtLeast 1
        Assert-MockCalled -CommandName "Invoke-MgGraphRequest" -ParameterFilter { $Uri -eq "/beta/security/auditLog/queries/test-query-id/records" -and $Method -eq "GET" } -Times 1
        Assert-MockCalled -CommandName "Invoke-MgGraphRequest" -ParameterFilter { $Uri -eq "/beta/security/auditLog/queries/test-query-id" -and $Method -eq "DELETE" } -Times 1
    }
}
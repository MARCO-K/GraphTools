BeforeAll {
    # Mock the required modules and functions
    Mock -ModuleName "Microsoft.Graph.Authentication" -CommandName "Install-GTRequiredModule" -MockWith { }
    Mock -ModuleName "Microsoft.Graph.Authentication" -CommandName "Test-GTGraphScopes" -MockWith { $true }
    Mock -ModuleName "Microsoft.Graph.Authentication" -CommandName "Set-MgRequestContext" -MockWith { }
    Mock -ModuleName "Microsoft.Graph.Authentication" -CommandName "Invoke-MgGraphRequest" -MockWith {
        param($Uri)
        if ($Uri -like "*auditLog/queries*") {
            return @{
                Id = "test-query-id"
                status = "succeeded"
            }
        }
        if ($Uri -like "*records*") {
            return @{
                value = @(
                    @{
                        Id = "test-record-1"
                        Operation = "FileDeleted"
                        UserId = "user1@contoso.com"
                        auditData = "{'some':'data'}"
                    },
                    @{
                        Id = "test-record-2"
                        Operation = "FileModified"
                        UserId = "user2@contoso.com"
                        auditData = "{'other':'data'}"
                    }
                )
            }
        }
    }
}

Describe "Invoke-AuditLogQuery" {
    It "should return audit log records" {
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

    It "should throw an error for invalid date range" {
        { Invoke-AuditLogQuery -StartDays 10 -EndDays 20 } | Should -Throw "Start date must be before end date."
    }

    It "should assign a custom type name to the output" {
        $result = Invoke-AuditLogQuery
        $result[0].PSObject.TypeNames[0] | Should -Be "GraphTools.AuditLogRecord"
    }
}
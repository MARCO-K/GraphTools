Describe "Invoke-AuditLogQuery" {
    BeforeAll {
        $validationFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'GTValidation.ps1'
        if (Test-Path $validationFile) { . $validationFile }

        # Define stub functions FIRST
        function global:Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function global:Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function global:Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Invoke-GTGraphRequest { param($Uri, $Method = 'GET', $Body, $Headers, $ContentType, [switch]$All, [int]$MaxRetries, [int]$RetryBaseDelaySeconds, $Token, [switch]$Raw, $ErrorAction) return @{} }

        # Mock Get-Date to return a fixed timestamp
        $script:fixedNow = [DateTime]'2025-10-10T00:00:00Z'
        Mock Get-Date { $script:fixedNow }

        # Dot-source the function under test AFTER stubs
        . "$PSScriptRoot/../functions/Invoke-AuditLogQuery.ps1"
    }
    BeforeEach {
        $script:storedFilter = $null
        $mockRecords = @(
            @{
                Id              = "test-record-1"
                Operation       = "FileDeleted"
                UserId          = "user1@contoso.com"
                auditData       = "{'some':'data'}"
                createdDateTime = (Get-Date).AddDays(-1)
            },
            @{
                Id              = "test-record-2"
                Operation       = "FileModified"
                UserId          = "user2@contoso.com"
                auditData       = "{'other':'data'}"
                createdDateTime = (Get-Date).AddDays(-8)
            }
        )

        Mock -CommandName "Invoke-GTGraphRequest" -MockWith {
            param($Uri, $Method = 'GET', $Body, $Headers, $ContentType, [switch]$All, [int]$MaxRetries, [int]$RetryBaseDelaySeconds, $Token, [switch]$Raw, $ErrorAction)
            # POST: Create query
            if ($Uri -like "*auditLog/queries*" -and $Method -eq "POST")
            {
                $bodyObj = if ($Body -is [string]) { $Body | ConvertFrom-Json } else { $Body }
                $script:storedFilter = if ($bodyObj.filter -is [string]) { $bodyObj.filter | ConvertFrom-Json } else { $bodyObj.filter }
                return @{
                    Id     = "test-query-id"
                    status = "succeeded"
                }
            }
            # GET: Check query status (not records)
            if ($Uri -eq "/beta/security/auditLog/queries/test-query-id" -and $Method -eq "GET")
            {
                return @{
                    Id     = "test-query-id"
                    status = "succeeded"
                }
            }
            # GET: Fetch records
            if ($Uri -eq "/beta/security/auditLog/queries/test-query-id/records" -and $Method -eq "GET")
            {
                $records = @($mockRecords)
                if ($script:storedFilter -and $script:storedFilter.OperationFilters)
                {
                    $records = @($records | Where-Object { $_.Operation -in $script:storedFilter.OperationFilters })
                }
                if ($script:storedFilter -and $script:storedFilter.userIdsFilters)
                {
                    $records = @($records | Where-Object { $_.UserId -in $script:storedFilter.userIdsFilters })
                }
                if ($script:storedFilter -and $script:storedFilter.filterStartDateTime)
                {
                    $startDate = [DateTime]$script:storedFilter.filterStartDateTime
                    $records = @($records | Where-Object { $_.createdDateTime -ge $startDate })
                }

                return @{
                    value = $records
                }
            }
            # DELETE: Clean up query
            if ($Uri -eq "/beta/security/auditLog/queries/test-query-id" -and $Method -eq "DELETE")
            {
                return @{ status = "deleted" }
            }
        }

        # Mock Start-Sleep to avoid delays in tests
        Mock -CommandName "Start-Sleep" -MockWith { }
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
        Assert-MockCalled -CommandName "Invoke-GTGraphRequest" -ParameterFilter {
            $body = if ($Body -is [string]) { $Body | ConvertFrom-Json } else { $Body }
            $filter = if ($body.filter -is [string]) { $body.filter | ConvertFrom-Json } else { $body.filter }
            ($filter.OperationFilters -contains "FileDeleted") -and ($filter.userIdsFilters -contains "user1@contoso.com")
        } -Times 1
    }

    It "should call the correct URIs" {
        Invoke-AuditLogQuery -Delete
        Assert-MockCalled -CommandName "Invoke-GTGraphRequest" -ParameterFilter { $Uri -like "*/auditLog/queries*" -and $Method -eq "POST" } -Times 1
        Assert-MockCalled -CommandName "Invoke-GTGraphRequest" -ParameterFilter { $Uri -eq "/beta/security/auditLog/queries/test-query-id" -and $Method -eq "GET" } -Times 1
        Assert-MockCalled -CommandName "Invoke-GTGraphRequest" -ParameterFilter { $Uri -eq "/beta/security/auditLog/queries/test-query-id/records" -and $Method -eq "GET" } -Times 1
        Assert-MockCalled -CommandName "Invoke-GTGraphRequest" -ParameterFilter { $Uri -eq "/beta/security/auditLog/queries/test-query-id" -and $Method -eq "DELETE" } -Times 1
    }

    Context "Parameter Validation" {
        It "should throw an error for an invalid UserIds (no @ symbol)" {
            { Invoke-AuditLogQuery -UserIds "invalid-user" } | Should -Throw
        }

        It "should throw an error for an invalid UserIds (empty local part)" {
            { Invoke-AuditLogQuery -UserIds "@domain.com" } | Should -Throw
        }

        It "should throw an error for an invalid UserIds (empty domain part)" {
            { Invoke-AuditLogQuery -UserIds "user@" } | Should -Throw
        }

        It "should accept valid Operations values" {
            { Invoke-AuditLogQuery -Operations "FileDeleted", "FileModified", "User_Logon" } | Should -Not -Throw
        }

        It "should throw an error for Operations with special characters" {
            { Invoke-AuditLogQuery -Operations "File'; DROP TABLE--" } | Should -Throw "*Invalid Operation value*"
        }

        It "should throw an error for Operations with single quotes" {
            { Invoke-AuditLogQuery -Operations "Operation' OR '1'='1" } | Should -Throw "*Invalid Operation value*"
        }

        It "should throw an error for Operations with parentheses" {
            { Invoke-AuditLogQuery -Operations "Operation()" } | Should -Throw "*Invalid Operation value*"
        }

        It "should accept valid RecordType values" {
            { Invoke-AuditLogQuery -RecordType "Exchange", "SharePoint", "AzureAD_Login" } | Should -Not -Throw
        }

        It "should throw an error for RecordType with special characters" {
            { Invoke-AuditLogQuery -RecordType "Type'; DELETE FROM" } | Should -Throw "*Invalid RecordType value*"
        }

        It "should throw an error for RecordType with single quotes" {
            { Invoke-AuditLogQuery -RecordType "Type' OR 1=1--" } | Should -Throw "*Invalid RecordType value*"
        }

        It "should accept valid Properties values" {
            { Invoke-AuditLogQuery -Properties "Id", "UserId", "auditData.property" } | Should -Not -Throw
        }

        It "should throw an error for Properties with special characters" {
            { Invoke-AuditLogQuery -Properties "property'; DROP--" } | Should -Throw "*Invalid Property value*"
        }

        It "should throw an error for Properties with single quotes" {
            { Invoke-AuditLogQuery -Properties "property' OR '1'='1" } | Should -Throw "*Invalid Property value*"
        }

        It "should throw an error for Properties with spaces" {
            { Invoke-AuditLogQuery -Properties "Invalid Property" } | Should -Throw "*Invalid Property value*"
        }
    }
}
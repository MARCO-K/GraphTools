# Pester tests for Test-GTGuid
# Requires Pester 5.x

Describe "Test-GTGuid" -Tag 'Unit' {
    BeforeAll {
        # Load the validation functions
        $validationFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'GTValidation.ps1'
        if (-not (Test-Path $validationFile)) {
            throw "Validation file not found: $validationFile"
        }
        . $validationFile
    }

    Context "Valid GUID Validation" {
        It "should return true for a valid GUID in standard format" {
            $result = Test-GTGuid -InputObject '12345678-1234-1234-1234-123456789abc' -Quiet
            $result | Should -Be $true
        }

        It "should return true for a valid GUID with uppercase letters" {
            $result = Test-GTGuid -InputObject '12345678-ABCD-ABCD-ABCD-123456789ABC' -Quiet
            $result | Should -Be $true
        }

        It "should return true for a valid GUID with mixed case" {
            $result = Test-GTGuid -InputObject 'a1b2c3d4-E5F6-A7B8-C9D0-E1F2A3B4C5D6' -Quiet
            $result | Should -Be $true
        }

        It "should return true for all zeros GUID" {
            $result = Test-GTGuid -InputObject '00000000-0000-0000-0000-000000000000' -Quiet
            $result | Should -Be $true
        }

        It "should return true for all F's GUID" {
            $result = Test-GTGuid -InputObject 'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF' -Quiet
            $result | Should -Be $true
        }

        It "should not throw for valid GUID without -Quiet" {
            { Test-GTGuid -InputObject '12345678-1234-1234-1234-123456789abc' } | Should -Not -Throw
        }

        It "should return true for valid GUID without -Quiet" {
            $result = Test-GTGuid -InputObject '12345678-1234-1234-1234-123456789abc'
            $result | Should -Be $true
        }
    }

    Context "Invalid GUID Validation" {
        It "should return false for an invalid GUID with -Quiet" {
            $result = Test-GTGuid -InputObject 'not-a-guid' -Quiet
            $result | Should -Be $false
        }

        It "should throw for empty string with -Quiet due to ValidateNotNullOrEmpty" {
            { Test-GTGuid -InputObject '' -Quiet } | Should -Throw '*null*'
        }

        It "should return false for GUID without dashes with -Quiet" {
            $result = Test-GTGuid -InputObject '12345678123412341234123456789abc' -Quiet
            $result | Should -Be $false
        }

        It "should return false for GUID with wrong number of segments with -Quiet" {
            $result = Test-GTGuid -InputObject '1234-5678-1234' -Quiet
            $result | Should -Be $false
        }

        It "should return false for GUID with invalid characters with -Quiet" {
            $result = Test-GTGuid -InputObject '12345678-1234-1234-1234-12345678ZZZZ' -Quiet
            $result | Should -Be $false
        }

        It "should return false for GUID with wrong segment lengths with -Quiet" {
            $result = Test-GTGuid -InputObject '123-1234-1234-1234-123456789abc' -Quiet
            $result | Should -Be $false
        }

        It "should return false for SQL injection attempt with -Quiet" {
            $result = Test-GTGuid -InputObject "12345678-1234-1234-1234-123456789abc' OR '1'='1" -Quiet
            $result | Should -Be $false
        }

        It "should return false for OData injection attempt with -Quiet" {
            $result = Test-GTGuid -InputObject "12345678-1234-1234-1234-123456789abc' OR principalId ne ''" -Quiet
            $result | Should -Be $false
        }

        It "should throw for invalid GUID without -Quiet" {
            { Test-GTGuid -InputObject 'not-a-guid' } | Should -Throw '*Invalid canonical GUID format*'
        }

        It "should throw for empty string without -Quiet" {
            { Test-GTGuid -InputObject '' } | Should -Throw '*null*'
        }

        It "should throw for GUID with invalid characters without -Quiet" {
            { Test-GTGuid -InputObject '12345678-1234-1234-1234-12345678ZZZZ' } | Should -Throw '*Invalid canonical GUID format*'
        }
    }

    Context "Pipeline Support" {
        It "should accept GUID from pipeline with -Quiet" {
            $result = '12345678-1234-1234-1234-123456789abc' | Test-GTGuid -Quiet
            $result | Should -Be $true
        }

        It "should accept invalid GUID from pipeline with -Quiet" {
            $result = 'not-a-guid' | Test-GTGuid -Quiet
            $result | Should -Be $false
        }

        It "should process multiple GUIDs from pipeline with -Quiet" {
            $guids = @(
                '12345678-1234-1234-1234-123456789abc',
                'a1b2c3d4-E5F6-A7B8-C9D0-E1F2A3B4C5D6',
                '00000000-0000-0000-0000-000000000000'
            )
            $results = $guids | Test-GTGuid -Quiet
            $results.Count | Should -Be 3
            $results[0] | Should -Be $true
            $results[1] | Should -Be $true
            $results[2] | Should -Be $true
        }

        It "should process mixed valid and invalid GUIDs from pipeline with -Quiet" {
            $inputs = @(
                '12345678-1234-1234-1234-123456789abc',
                'not-a-guid',
                'a1b2c3d4-E5F6-A7B8-C9D0-E1F2A3B4C5D6',
                'invalid',
                '00000000-0000-0000-0000-000000000000'
            )
            $results = $inputs | Test-GTGuid -Quiet
            $results.Count | Should -Be 5
            $results[0] | Should -Be $true
            $results[1] | Should -Be $false
            $results[2] | Should -Be $true
            $results[3] | Should -Be $false
            $results[4] | Should -Be $true
        }
    }

    Context "Real-world GUID Examples" {
        It "should validate typical Azure AD user GUID" {
            # Typical user GUID pattern from Azure AD
            $result = Test-GTGuid -InputObject 'a1234567-89ab-cdef-0123-456789abcdef' -Quiet
            $result | Should -Be $true
        }

        It "should validate typical Microsoft Graph API response GUID" {
            # GUIDs commonly seen in Graph API responses
            $result = Test-GTGuid -InputObject '00000000-0000-0000-0000-000000000001' -Quiet
            $result | Should -Be $true
        }
    }

    Context "Edge Cases" {
        It "should throw for null input due to ValidateNotNullOrEmpty" {
            # ValidateNotNullOrEmpty will throw before the function body executes
            { Test-GTGuid -InputObject $null -Quiet } | Should -Throw '*null*'
        }

        It "should handle whitespace-only string with -Quiet" {
            $result = Test-GTGuid -InputObject '   ' -Quiet
            $result | Should -Be $false
        }

        It "should handle GUID with leading/trailing spaces with -Quiet" {
            $result = Test-GTGuid -InputObject ' 12345678-1234-1234-1234-123456789abc ' -Quiet
            $result | Should -Be $false
        }
    }
}

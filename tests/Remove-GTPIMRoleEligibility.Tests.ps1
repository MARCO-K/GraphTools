Describe "Remove-GTPIMRoleEligibility" {
    BeforeAll {
        # Mock PSFramework logging first (before sourcing the function)
        function Write-PSFMessage { }
        
        # Load the error handling helper function (required by Remove-GTPIMRoleEligibility)
        $errorHelperFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'Get-GTGraphErrorDetails.ps1'
        if (Test-Path $errorHelperFile) {
            . $errorHelperFile
        } else {
            throw "Required helper function Get-GTGraphErrorDetails.ps1 not found at: $errorHelperFile"
        }
        
        # Mock Microsoft Graph cmdlets as stubs
        function Get-MgBetaRoleManagementDirectoryRoleEligibilitySchedule { }
        function Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule { }
        
        # Import the internal function for testing
        . "$PSScriptRoot/../internal/functions/Remove-GTPIMRoleEligibility.ps1"
        
        # Create test user object
        $script:testUser = [PSCustomObject]@{
            Id = "test-user-id-12345"
            UserPrincipalName = "testuser@contoso.com"
        }
        
        # Create test output base
        $script:testOutputBase = @{
            UPN = "testuser@contoso.com"
            UserId = "test-user-id-12345"
            Timestamp = [datetime]::UtcNow
        }
        
        # Create test results collection
        $script:testResults = [System.Collections.Generic.List[PSObject]]::new()
    }
    
    BeforeEach {
        $script:testResults = [System.Collections.Generic.List[PSObject]]::new()
    }

    Context "Parameter Validation" {
        It "should throw error when User object is missing Id property" {
            $invalidUser = [PSCustomObject]@{
                UserPrincipalName = "test@contoso.com"
            }
            { Remove-GTPIMRoleEligibility -User $invalidUser -OutputBase $testOutputBase -Results $testResults } | Should -Throw "*Id*"
        }

        It "should throw error when User object is missing UserPrincipalName property" {
            $invalidUser = [PSCustomObject]@{
                Id = "test-id"
            }
            { Remove-GTPIMRoleEligibility -User $invalidUser -OutputBase $testOutputBase -Results $testResults } | Should -Throw "*UserPrincipalName*"
        }

        It "should accept valid User object with Id and UserPrincipalName" {
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -MockWith { @() }
            $results = [System.Collections.Generic.List[PSObject]]::new()
            Remove-GTPIMRoleEligibility -User $testUser -OutputBase $testOutputBase -Results $results -WhatIf
            # If we get here without error, test passes
            $true | Should -Be $true
        }
    }

    Context "PIM Role Eligibility Retrieval" {
        It "should successfully execute with valid parameters" {
            $results = [System.Collections.Generic.List[PSObject]]::new()
            
            { Remove-GTPIMRoleEligibility -User $testUser -OutputBase $testOutputBase -Results $results } | Should -Not -Throw
            
            # Verify no errors were added to results when no schedules exist
            $results.Count | Should -Be 0
        }

        It "should handle user with no PIM role eligibilities" {
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -MockWith { @() }
            $results = [System.Collections.Generic.List[PSObject]]::new()
            
            Remove-GTPIMRoleEligibility -User $testUser -OutputBase $testOutputBase -Results $results
            
            $results.Count | Should -Be 0
        }

        It "should handle errors when retrieving PIM role eligibilities" {
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -MockWith { 
                throw "Access denied"
            }
            $results = [System.Collections.Generic.List[PSObject]]::new()
            
            Remove-GTPIMRoleEligibility -User $testUser -OutputBase $testOutputBase -Results $results
            
            $results.Count | Should -Be 1
            $results[0].Status | Should -BeLike "*Failed*"
            $results[0].ResourceType | Should -Be "PIMRoleEligibility"
            $results[0].Action | Should -Be "RemovePIMRoleEligibility"
        }
    }

    Context "PIM Role Eligibility Removal" {
        It "should process single PIM role eligibility correctly" {
            # Redefine the stub to return test data
            function Get-MgBetaRoleManagementDirectoryRoleEligibilitySchedule { 
                return @([PSCustomObject]@{
                    Id = "schedule-id-1"
                    RoleDefinition = [PSCustomObject]@{ DisplayName = "Global Administrator" }
                })
            }
            $results = [System.Collections.Generic.List[PSObject]]::new()
            
            Remove-GTPIMRoleEligibility -User $testUser -OutputBase $testOutputBase -Results $results
            
            # Verify the result was added correctly
            $results.Count | Should -Be 1
            $results[0].ResourceName | Should -Be "Global Administrator"
            $results[0].ResourceType | Should -Be "PIMRoleEligibility"
            $results[0].Status | Should -Be "Success"
        }

        It "should remove multiple PIM role eligibilities" {
            $mockSchedules = @(
                [PSCustomObject]@{
                    Id = "schedule-id-1"
                    RoleDefinition = [PSCustomObject]@{
                        DisplayName = "Global Administrator"
                    }
                },
                [PSCustomObject]@{
                    Id = "schedule-id-2"
                    RoleDefinition = [PSCustomObject]@{
                        DisplayName = "User Administrator"
                    }
                },
                [PSCustomObject]@{
                    Id = "schedule-id-3"
                    RoleDefinition = [PSCustomObject]@{
                        DisplayName = "Security Administrator"
                    }
                }
            )
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -MockWith { $mockSchedules }
            Mock -CommandName "Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -MockWith { }
            $results = [System.Collections.Generic.List[PSObject]]::new()
            
            Remove-GTPIMRoleEligibility -User $testUser -OutputBase $testOutputBase -Results $results
            
            Should -Invoke -CommandName "Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -Times 3
            $results.Count | Should -Be 3
            $results[0].ResourceName | Should -Be "Global Administrator"
            $results[1].ResourceName | Should -Be "User Administrator"
            $results[2].ResourceName | Should -Be "Security Administrator"
            $results | ForEach-Object { $_.Status | Should -Be "Success" }
        }

        It "should handle removal failure for individual role eligibility" {
            $mockSchedule = [PSCustomObject]@{
                Id = "schedule-id-1"
                RoleDefinition = [PSCustomObject]@{
                    DisplayName = "Global Administrator"
                }
            }
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -MockWith { @($mockSchedule) }
            Mock -CommandName "Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -MockWith { 
                throw "Insufficient permissions"
            }
            $results = [System.Collections.Generic.List[PSObject]]::new()
            
            Remove-GTPIMRoleEligibility -User $testUser -OutputBase $testOutputBase -Results $results
            
            $results.Count | Should -Be 1
            $results[0].Status | Should -BeLike "*Failed*Insufficient permissions*"
            $results[0].ResourceName | Should -Be "Global Administrator"
        }
    }

    Context "ShouldProcess Support" {
        It "should respect WhatIf parameter" {
            $mockSchedule = [PSCustomObject]@{
                Id = "schedule-id-1"
                RoleDefinition = [PSCustomObject]@{
                    DisplayName = "Global Administrator"
                }
            }
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -MockWith { @($mockSchedule) }
            Mock -CommandName "Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -MockWith { }
            $results = [System.Collections.Generic.List[PSObject]]::new()
            
            Remove-GTPIMRoleEligibility -User $testUser -OutputBase $testOutputBase -Results $results -WhatIf
            
            Should -Invoke -CommandName "Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -Times 0
        }
    }

    Context "Output Validation" {
        It "should add correct properties to output object" {
            $mockSchedule = [PSCustomObject]@{
                Id = "schedule-id-1"
                RoleDefinition = [PSCustomObject]@{
                    DisplayName = "Global Administrator"
                }
            }
            Mock -CommandName "Get-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -MockWith { @($mockSchedule) }
            Mock -CommandName "Remove-MgBetaRoleManagementDirectoryRoleEligibilitySchedule" -MockWith { }
            $results = [System.Collections.Generic.List[PSObject]]::new()
            
            Remove-GTPIMRoleEligibility -User $testUser -OutputBase $testOutputBase -Results $results
            
            $output = $results[0]
            $output.UPN | Should -Be "testuser@contoso.com"
            $output.UserId | Should -Be "test-user-id-12345"
            $output.ResourceName | Should -Be "Global Administrator"
            $output.ResourceType | Should -Be "PIMRoleEligibility"
            $output.ResourceId | Should -Be "schedule-id-1"
            $output.Action | Should -Be "RemovePIMRoleEligibility"
            $output.Status | Should -Be "Success"
        }
    }
}

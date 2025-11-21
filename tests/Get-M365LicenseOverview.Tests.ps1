Describe "Get-M365LicenseOverview" {
    BeforeAll {
        # Mock required functions and modules
        Mock Install-GTRequiredModule { }
        Mock Test-GTGraphScopes { $true }
        Mock Initialize-GTGraphConnection { $true }
        Mock Get-GTGraphErrorDetails {
            [PSCustomObject]@{
                LogLevel = 'Error'
                Reason = 'Test error'
                ErrorMessage = 'Test error message'
            }
        }
        Mock Write-PSFMessage { }

        # Mock Invoke-RestMethod for CSV download
        Mock Invoke-RestMethod {
            @(
                [PSCustomObject]@{
                    GUID = '12345678-1234-1234-1234-123456789012'
                    Product_Display_Name = 'Microsoft 365 E5'
                    Service_Plan_Id = '87654321-4321-4321-4321-210987654321'
                    Service_Plan_Friendly_Name = 'Exchange Online'
                },
                [PSCustomObject]@{
                    GUID = 'abcdef12-3456-7890-abcd-ef1234567890'
                    Product_Display_Name = 'Microsoft 365 E3'
                    Service_Plan_Id = 'fedcba98-7654-3210-fedc-ba9876543210'
                    Service_Plan_Friendly_Name = 'SharePoint Online'
                }
            )
        }

        # Dot-source the function under test
        . "$PSScriptRoot/../functions/Get-M365LicenseOverview.ps1"
    }

    BeforeEach {
        # Clear any cached data between tests
        $script:GTLicenseRefCache = $null
    }

    Context "Parameter Validation" {
        It "should throw an error for an invalid FilterUser (no @ symbol)" {
            { Get-M365LicenseOverview -FilterUser "invalid-user" } | Should -Throw
        }

        It "should throw an error for an invalid FilterUser (empty local part)" {
            { Get-M365LicenseOverview -FilterUser "@domain.com" } | Should -Throw
        }

        It "should throw an error for an invalid FilterUser (empty domain part)" {
            { Get-M365LicenseOverview -FilterUser "user@" } | Should -Throw
        }

        It "should accept valid FilterUser" {
            Mock Get-MgBetaUser { @() }
            { Get-M365LicenseOverview -FilterUser "user@domain.com" } | Should -Not -Throw
        }

        It "should validate DaysInactive range" {
            { Get-M365LicenseOverview -DaysInactive 0 } | Should -Throw
            { Get-M365LicenseOverview -DaysInactive 3651 } | Should -Throw
            { Get-M365LicenseOverview -DaysInactive 90 } | Should -Not -Throw
        }
    }

    Context "CSV Caching and Download" {
        It "should cache CSV data in script scope" {
            Mock Get-MgBetaUser { @() }

            # First call should download and cache
            Get-M365LicenseOverview | Out-Null

            # Verify cache was created
            $script:GTLicenseRefCache | Should -Not -BeNullOrEmpty
            $script:GTLicenseRefCache.SkuNames | Should -Contain '12345678-1234-1234-1234-123456789012'
            $script:GTLicenseRefCache.PlanNames | Should -Contain '87654321-4321-4321-4321-210987654321'
        }

        It "should reuse cached data on subsequent calls" {
            Mock Get-MgBetaUser { @() }

            # First call
            Get-M365LicenseOverview | Out-Null
            Assert-MockCalled Invoke-RestMethod -Times 1 -Exactly

            # Second call should use cache
            Get-M365LicenseOverview | Out-Null
            Assert-MockCalled Invoke-RestMethod -Times 1 -Exactly  # Still only called once
        }

        It "should handle CSV download failure gracefully" {
            Mock Invoke-RestMethod { throw "Network error" }
            Mock Get-MgBetaUser { @() }

            # Should not throw, should continue with empty cache
            { Get-M365LicenseOverview } | Should -Not -Throw

            # Should have empty cache
            $script:GTLicenseRefCache.SkuNames | Should -BeNullOrEmpty
        }

        It "should fallback to scraping when direct download fails" {
            Mock Invoke-RestMethod {
                if ($Uri -match 'download\.microsoft\.com') {
                    throw "Direct download failed"
                } else {
                    # Return CSV data for scraping fallback
                    @(
                        [PSCustomObject]@{
                            GUID = 'fallback-sku-id'
                            Product_Display_Name = 'Fallback Product'
                            Service_Plan_Id = 'fallback-plan-id'
                            Service_Plan_Friendly_Name = 'Fallback Plan'
                        }
                    )
                }
            }
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    Links = @([PSCustomObject]@{ href = 'https://example.com/fallback.csv' })
                }
            }
            Mock Get-MgBetaUser { @() }

            Get-M365LicenseOverview | Out-Null

            # Should have used fallback data
            $script:GTLicenseRefCache.SkuNames['fallback-sku-id'] | Should -Be 'Fallback Product'
        }
    }

    Context "User Data Processing" {
        BeforeEach {
            # Mock user data with licenses
            Mock Get-MgBetaUser {
                @(
                    [PSCustomObject]@{
                        UserPrincipalName = 'user1@contoso.com'
                        DisplayName = 'User One'
                        SignInActivity = [PSCustomObject]@{
                            LastSignInDateTime = (Get-Date).AddDays(-30).ToString('o')
                        }
                        AssignedLicenses = @(
                            [PSCustomObject]@{
                                SkuId = '12345678-1234-1234-1234-123456789012'
                                ServicePlans = @(
                                    [PSCustomObject]@{
                                        ServicePlanId = '87654321-4321-4321-4321-210987654321'
                                        ProvisioningStatus = 'Success'
                                    }
                                )
                            }
                        )
                    },
                    [PSCustomObject]@{
                        UserPrincipalName = 'user2@contoso.com'
                        DisplayName = 'User Two'
                        SignInActivity = $null
                        AssignedLicenses = @(
                            [PSCustomObject]@{
                                SkuId = 'abcdef12-3456-7890-abcd-ef1234567890'
                                ServicePlans = @(
                                    [PSCustomObject]@{
                                        ServicePlanId = 'fedcba98-7654-3210-fedc-ba9876543210'
                                        ProvisioningStatus = 'Pending'
                                    }
                                )
                            }
                        )
                    }
                )
            }
        }

        It "should process users with licenses correctly" {
            $results = Get-M365LicenseOverview

            $results | Should -HaveCount 2
            $results[0].UserPrincipalName | Should -Be 'user1@contoso.com'
            $results[0].LicenseSKU | Should -Be 'Microsoft 365 E5'
            $results[0].ServicePlan | Should -Be 'Exchange Online'
            $results[0].ProvisioningStatus | Should -Be 'Success'
            $results[0].DaysInactive | Should -BeOfType [int]
        }

        It "should handle users with no sign-in activity" {
            $results = Get-M365LicenseOverview

            $user2Result = $results | Where-Object { $_.UserPrincipalName -eq 'user2@contoso.com' }
            $user2Result.DaysInactive | Should -Be "Never"
        }

        It "should skip users with no assigned licenses" {
            Mock Get-MgBetaUser {
                @(
                    [PSCustomObject]@{
                        UserPrincipalName = 'user3@contoso.com'
                        DisplayName = 'User Three'
                        AssignedLicenses = @()
                    }
                )
            }

            $results = Get-M365LicenseOverview
            $results | Should -HaveCount 0
        }
    }

    Context "Filtering Logic" {
        BeforeEach {
            Mock Get-MgBetaUser {
                @(
                    [PSCustomObject]@{
                        UserPrincipalName = 'john.doe@contoso.com'
                        DisplayName = 'John Doe'
                        SignInActivity = [PSCustomObject]@{ LastSignInDateTime = (Get-Date).AddDays(-10).ToString('o') }
                        AssignedLicenses = @(
                            [PSCustomObject]@{
                                SkuId = '12345678-1234-1234-1234-123456789012'
                                ServicePlans = @(
                                    [PSCustomObject]@{ ServicePlanId = '87654321-4321-4321-4321-210987654321'; ProvisioningStatus = 'Success' }
                                )
                            }
                        )
                    },
                    [PSCustomObject]@{
                        UserPrincipalName = 'jane.smith@contoso.com'
                        DisplayName = 'Jane Smith'
                        SignInActivity = [PSCustomObject]@{ LastSignInDateTime = (Get-Date).AddDays(-100).ToString('o') }
                        AssignedLicenses = @(
                            [PSCustomObject]@{
                                SkuId = 'abcdef12-3456-7890-abcd-ef1234567890'
                                ServicePlans = @(
                                    [PSCustomObject]@{ ServicePlanId = 'fedcba98-7654-3210-fedc-ba9876543210'; ProvisioningStatus = 'Success' }
                                )
                            }
                        )
                    }
                )
            }
        }

        It "should filter by FilterUser (server-side)" {
            $results = Get-M365LicenseOverview -FilterUser 'john'

            $results | Should -HaveCount 1
            $results[0].UserPrincipalName | Should -Be 'john.doe@contoso.com'
        }

        It "should filter by FilterLicenseSKU (client-side)" {
            $results = Get-M365LicenseOverview -FilterLicenseSKU 'E5'

            $results | Should -HaveCount 1
            $results[0].LicenseSKU | Should -Be 'Microsoft 365 E5'
        }

        It "should filter by FilterServicePlan (client-side)" {
            $results = Get-M365LicenseOverview -FilterServicePlan 'SharePoint'

            $results | Should -HaveCount 1
            $results[0].ServicePlan | Should -Be 'SharePoint Online'
        }

        It "should filter by DaysInactive (server-side)" {
            $results = Get-M365LicenseOverview -DaysInactive 50

            # Should only return users inactive for more than 50 days
            $results | Should -HaveCount 1
            $results[0].UserPrincipalName | Should -Be 'jane.smith@contoso.com'
        }

        It "should combine multiple filters" {
            $results = Get-M365LicenseOverview -FilterUser 'jane' -FilterLicenseSKU 'E3'

            $results | Should -HaveCount 1
            $results[0].UserPrincipalName | Should -Be 'jane.smith@contoso.com'
            $results[0].LicenseSKU | Should -Be 'Microsoft 365 E3'
        }
    }

    Context "Error Handling" {
        It "should handle scope validation failure" {
            Mock Test-GTGraphScopes { $false }

            { Get-M365LicenseOverview } | Should -Throw
        }

        It "should handle connection failure" {
            Mock Initialize-GTGraphConnection { $false }

            { Get-M365LicenseOverview } | Should -Throw
        }

        It "should handle Get-MgBetaUser errors gracefully" {
            Mock Get-MgBetaUser { throw "Graph API Error" }

            { Get-M365LicenseOverview } | Should -Throw
            Assert-MockCalled Get-GTGraphErrorDetails -Times 1
        }
    }

    Context "Output Format" {
        It "should return correct object properties" {
            Mock Get-MgBetaUser {
                @(
                    [PSCustomObject]@{
                        UserPrincipalName = 'test@contoso.com'
                        DisplayName = 'Test User'
                        SignInActivity = [PSCustomObject]@{ LastSignInDateTime = (Get-Date).AddDays(-5).ToString('o') }
                        AssignedLicenses = @(
                            [PSCustomObject]@{
                                SkuId = '12345678-1234-1234-1234-123456789012'
                                ServicePlans = @(
                                    [PSCustomObject]@{ ServicePlanId = '87654321-4321-4321-4321-210987654321'; ProvisioningStatus = 'Success' }
                                )
                            }
                        )
                    }
                )
            }

            $result = Get-M365LicenseOverview

            $result | Should -BeOfType [PSCustomObject]
            $result | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Should -Contain 'UserPrincipalName'
            $result | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Should -Contain 'DisplayName'
            $result | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Should -Contain 'LicenseSKU'
            $result | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Should -Contain 'ServicePlan'
            $result | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Should -Contain 'ProvisioningStatus'
            $result | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Should -Contain 'LastInteractiveSignIn'
            $result | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Should -Contain 'DaysInactive'
        }

        It "should handle GUID fallback when SKU not in cache" {
            Mock Get-MgBetaUser {
                @(
                    [PSCustomObject]@{
                        UserPrincipalName = 'test@contoso.com'
                        DisplayName = 'Test User'
                        SignInActivity = $null
                        AssignedLicenses = @(
                            [PSCustomObject]@{
                                SkuId = 'unknown-sku-guid'
                                ServicePlans = @(
                                    [PSCustomObject]@{ ServicePlanId = 'unknown-plan-guid'; ProvisioningStatus = 'Success' }
                                )
                            }
                        )
                    }
                )
            }

            $result = Get-M365LicenseOverview

            $result.LicenseSKU | Should -Be 'unknown-sku-guid'
            $result.ServicePlan | Should -Be 'unknown-plan-guid'
        }
    }

    Context "Edge Cases" {
        It "should handle empty user results" {
            Mock Get-MgBetaUser { @() }

            $results = Get-M365LicenseOverview
            $results | Should -HaveCount 0
        }

        It "should handle users with multiple licenses" {
            Mock Get-MgBetaUser {
                @(
                    [PSCustomObject]@{
                        UserPrincipalName = 'multi@contoso.com'
                        DisplayName = 'Multi License User'
                        SignInActivity = $null
                        AssignedLicenses = @(
                            [PSCustomObject]@{
                                SkuId = '12345678-1234-1234-1234-123456789012'
                                ServicePlans = @(
                                    [PSCustomObject]@{ ServicePlanId = '87654321-4321-4321-4321-210987654321'; ProvisioningStatus = 'Success' }
                                )
                            },
                            [PSCustomObject]@{
                                SkuId = 'abcdef12-3456-7890-abcd-ef1234567890'
                                ServicePlans = @(
                                    [PSCustomObject]@{ ServicePlanId = 'fedcba98-7654-3210-fedc-ba9876543210'; ProvisioningStatus = 'Success' }
                                )
                            }
                        )
                    }
                )
            }

            $results = Get-M365LicenseOverview
            $results | Should -HaveCount 2
            ($results | Where-Object { $_.LicenseSKU -eq 'Microsoft 365 E5' }).ServicePlan | Should -Be 'Exchange Online'
            ($results | Where-Object { $_.LicenseSKU -eq 'Microsoft 365 E3' }).ServicePlan | Should -Be 'SharePoint Online'
        }

        It "should handle licenses with no service plans" {
            Mock Get-MgBetaUser {
                @(
                    [PSCustomObject]@{
                        UserPrincipalName = 'test@contoso.com'
                        DisplayName = 'Test User'
                        SignInActivity = $null
                        AssignedLicenses = @(
                            [PSCustomObject]@{
                                SkuId = '12345678-1234-1234-1234-123456789012'
                                ServicePlans = @()
                            }
                        )
                    }
                )
            }

            $results = Get-M365LicenseOverview
            $results | Should -HaveCount 0  # No service plans means no output
        }
    }
}
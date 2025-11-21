## Provide lightweight stubs for common helpers in case they are missing during discovery
if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }
if (-not (Get-Command Get-GTGraphErrorDetails -ErrorAction SilentlyContinue)) { function Get-GTGraphErrorDetails { param($Exception, $ResourceType) return @{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } } }

## Mock the validation regex
$script:GTValidationRegex = @{
    UPN = '^[^@\s]+@[^@\s]+\.[^@\s]+$'
}

Describe "Get-GTLegacyAuthReport" {
    BeforeAll {
        # Mock Get-MgContext to simulate being connected
        Mock -CommandName "Get-MgContext" -MockWith {
            return @{ Scopes = @('AuditLog.Read.All') }
        }
        $functionPath = "$PSScriptRoot/../functions/Get-GTLegacyAuthReport.ps1"
        if (Test-Path $functionPath) { . $functionPath } else { Throw "Function file not found: $functionPath" }
    }

    Context "Parameter Validation" {
        It "should validate DaysAgo range (1-30)" {
            { Get-GTLegacyAuthReport -DaysAgo 0 } | Should -Throw
            { Get-GTLegacyAuthReport -DaysAgo 31 } | Should -Throw
            { Get-GTLegacyAuthReport -DaysAgo 7 } | Should -Not -Throw
        }

        It "should validate UPN format" {
            { Get-GTLegacyAuthReport -UserPrincipalName "invalid-upn" } | Should -Throw
            { Get-GTLegacyAuthReport -UserPrincipalName "user@contoso.com" } | Should -Not -Throw
        }

        It "should validate IP address format" {
            { Get-GTLegacyAuthReport -IPAddress "invalid-ip" } | Should -Throw
            { Get-GTLegacyAuthReport -IPAddress "192.168.1.1" } | Should -Not -Throw
            { Get-GTLegacyAuthReport -IPAddress "10.0.0.1" } | Should -Not -Throw
            { Get-GTLegacyAuthReport -IPAddress "2001:db8::1" } | Should -Not -Throw
            { Get-GTLegacyAuthReport -IPAddress "::1" } | Should -Not -Throw
            { Get-GTLegacyAuthReport -IPAddress "fe80::1%eth0" } | Should -Not -Throw
        }

        It "should accept standard UPN aliases" {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith { return @() }
            { Get-GTLegacyAuthReport -UPN "user@contoso.com" } | Should -Not -Throw
            { Get-GTLegacyAuthReport -Users "user@contoso.com" } | Should -Not -Throw
            { Get-GTLegacyAuthReport -User "user@contoso.com" } | Should -Not -Throw
        }
    }

    Context "Pipeline Input" {
        BeforeEach {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith { return @() }
        }

        It "should accept single UPN from pipeline" {
            $result = "user@contoso.com" | Get-GTLegacyAuthReport
            # Should not throw
            $true | Should -BeTrue
        }

        It "should accept multiple UPNs from pipeline" {
            $result = @("user1@contoso.com", "user2@contoso.com") | Get-GTLegacyAuthReport
            # Should not throw
            $true | Should -BeTrue
        }

        It "should accept ClientAppUsed from pipeline" {
            $result = "POP3" | Get-GTLegacyAuthReport
            # Should not throw
            $true | Should -BeTrue
        }

        It "should accept IPAddress from pipeline" {
            $result = "192.168.1.1" | Get-GTLegacyAuthReport
            # Should not throw
            $true | Should -BeTrue
        }

        It "should accept IPv6 addresses from pipeline" {
            $result = "2001:db8::1" | Get-GTLegacyAuthReport
            # Should not throw
            $true | Should -BeTrue
        }
    }

    Context "Protocol Detection" {
        BeforeEach {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                return @(
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "192.168.1.1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-1"
                    },
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user@contoso.com"
                        ClientAppUsed = "Browser"
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "192.168.1.1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook Web"
                        Id = "request-2"
                    }
                )
            }
        }

        It "should identify legacy protocols" {
            $result = Get-GTLegacyAuthReport
            $result | Where-Object { $_.ClientAppUsed -eq "POP3" } | Should -Not -BeNullOrEmpty
            $result | Where-Object { $_.ClientAppUsed -eq "Browser" } | Should -BeNullOrEmpty
        }

        It "should filter by specific legacy protocol" {
            $result = Get-GTLegacyAuthReport -ClientAppUsed "POP3"
            $result.ClientAppUsed | Should -Contain "POP3"
            $result | Where-Object { $_.ClientAppUsed -ne "POP3" } | Should -BeNullOrEmpty
        }

        It "should handle all legacy protocols" {
            $legacyProtocols = @(
                'Authenticated SMTP', 'AutoDiscover', 'Exchange ActiveSync',
                'Exchange Online PowerShell', 'IMAP4', 'MAPI over HTTP',
                'Outlook Anywhere', 'Outlook Service', 'POP3',
                'Reporting Web Services', 'Other Clients', 'FTP'
            )

            foreach ($protocol in $legacyProtocols) {
                Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                    return @(
                        [PSCustomObject]@{
                            CreatedDateTime = (Get-Date).AddDays(-1)
                            UserPrincipalName = "user@contoso.com"
                            ClientAppUsed = $protocol
                            Status = [PSCustomObject]@{ ErrorCode = 0 }
                            IpAddress = "192.168.1.1"
                            Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                            AppDisplayName = "Test App"
                            Id = "request-1"
                        }
                    )
                }

                $result = Get-GTLegacyAuthReport
                $result.ClientAppUsed | Should -Contain $protocol
            }
        }
    }

    Context "User Filtering" {
        BeforeEach {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                return @(
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user1@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "192.168.1.1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-1"
                    },
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user2@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "192.168.1.2"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-2"
                    }
                )
            }
        }

        It "should filter by specific user" {
            $result = Get-GTLegacyAuthReport -UserPrincipalName "user1@contoso.com"
            $result.UserPrincipalName | Should -Contain "user1@contoso.com"
            $result | Where-Object { $_.UserPrincipalName -ne "user1@contoso.com" } | Should -BeNullOrEmpty
        }

        It "should filter by multiple users" {
            $result = Get-GTLegacyAuthReport -UserPrincipalName @("user1@contoso.com", "user2@contoso.com")
            $result.Count | Should -Be 2
            $result.UserPrincipalName | Should -Contain "user1@contoso.com"
            $result.UserPrincipalName | Should -Contain "user2@contoso.com"
        }
    }

    Context "IP Address Filtering" {
        BeforeEach {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                return @(
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "192.168.1.1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-1"
                    },
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "10.0.0.1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-2"
                    }
                )
            }
        }

        It "should filter by specific IP" {
            $result = Get-GTLegacyAuthReport -IPAddress "192.168.1.1"
            $result.IPAddress | Should -Contain "192.168.1.1"
            $result | Where-Object { $_.IPAddress -ne "192.168.1.1" } | Should -BeNullOrEmpty
        }

        It "should filter by IPv6 address" {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                return @(
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "2001:db8::1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-1"
                    },
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "::1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-2"
                    }
                )
            }

            $result = Get-GTLegacyAuthReport -IPAddress "2001:db8::1"
            $result.IPAddress | Should -Contain "2001:db8::1"
            $result | Where-Object { $_.IPAddress -ne "2001:db8::1" } | Should -BeNullOrEmpty
        }
    }

    Context "Success/Failure Classification" {
        It "should classify successful legacy auth as security gap" {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                return @(
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "192.168.1.1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-1"
                    }
                )
            }

            $result = Get-GTLegacyAuthReport
            $result.Result | Should -Contain "Security Gap (Success)"
            $result.Status | Should -Contain "Success"
            $result.FailureReason | Should -BeNullOrEmpty
        }

        It "should classify failed legacy auth as attack attempt" {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                return @(
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 50056; FailureReason = "Invalid password" }
                        IpAddress = "192.168.1.1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-1"
                    }
                )
            }

            $result = Get-GTLegacyAuthReport
            $result.Result | Should -Contain "Attack Attempt (Failed)"
            $result.Status | Should -Contain "Failure"
            $result.FailureReason | Should -Contain "Invalid password"
        }

        It "should map error codes to descriptive reasons" {
            $errorMappings = @{
                50034 = "User not found"
                50053 = "Account locked"
                50055 = "Password expired"
                50056 = "Invalid password"
                50057 = "User disabled"
                50076 = "MFA required (Legacy Blocked)"
                50079 = "MFA enrollment required"
                50126 = "Invalid username/password"
                53003 = "Blocked by CA"
            }

            foreach ($errorCode in $errorMappings.Keys) {
                Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                    return @(
                        [PSCustomObject]@{
                            CreatedDateTime = (Get-Date).AddDays(-1)
                            UserPrincipalName = "user@contoso.com"
                            ClientAppUsed = "POP3"
                            Status = [PSCustomObject]@{ ErrorCode = $errorCode; FailureReason = "Original reason" }
                            IpAddress = "192.168.1.1"
                            Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                            AppDisplayName = "Outlook"
                            Id = "request-1"
                        }
                    )
                }

                $result = Get-GTLegacyAuthReport
                $result.FailureReason | Should -Contain $errorMappings[$errorCode]
            }
        }

        It "should use original failure reason for unmapped errors" {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                return @(
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 99999; FailureReason = "Custom error" }
                        IpAddress = "192.168.1.1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-1"
                    }
                )
            }

            $result = Get-GTLegacyAuthReport
            $result.FailureReason | Should -Contain "Custom error"
        }
    }

    Context "SuccessOnly Switch" {
        It "should filter to only successful authentications when SuccessOnly is used" {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                return @(
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "192.168.1.1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-1"
                    },
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 50056; FailureReason = "Invalid password" }
                        IpAddress = "192.168.1.2"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-2"
                    }
                )
            }

            $result = Get-GTLegacyAuthReport -SuccessOnly
            $result.Count | Should -Be 1
            $result.Status | Should -Contain "Success"
            $result.IPAddress | Should -Contain "192.168.1.1"
        }
    }

    Context "Output Format" {
        BeforeEach {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                return @(
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "192.168.1.1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-12345"
                    }
                )
            }
        }

        It "should return PSCustomObject with correct properties" {
            $result = Get-GTLegacyAuthReport
            $result | Should -BeOfType [PSCustomObject]
            $result.PSObject.Properties.Name | Should -Contain "CreatedDateTime"
            $result.PSObject.Properties.Name | Should -Contain "UserPrincipalName"
            $result.PSObject.Properties.Name | Should -Contain "ClientAppUsed"
            $result.PSObject.Properties.Name | Should -Contain "Result"
            $result.PSObject.Properties.Name | Should -Contain "Status"
            $result.PSObject.Properties.Name | Should -Contain "ErrorCode"
            $result.PSObject.Properties.Name | Should -Contain "FailureReason"
            $result.PSObject.Properties.Name | Should -Contain "IPAddress"
            $result.PSObject.Properties.Name | Should -Contain "Location"
            $result.PSObject.Properties.Name | Should -Contain "AppDisplayName"
            $result.PSObject.Properties.Name | Should -Contain "RequestId"
        }

        It "should format location correctly" {
            $result = Get-GTLegacyAuthReport
            $result.Location | Should -Contain "Seattle, US"
        }

        It "should include all required data" {
            $result = Get-GTLegacyAuthReport
            $result.CreatedDateTime | Should -Not -BeNullOrEmpty
            $result.UserPrincipalName | Should -Be "user@contoso.com"
            $result.ClientAppUsed | Should -Be "POP3"
            $result.IPAddress | Should -Be "192.168.1.1"
            $result.AppDisplayName | Should -Be "Outlook"
            $result.RequestId | Should -Be "request-12345"
        }
    }

    Context "Error Handling" {
        It "should handle Graph API errors gracefully" {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith { throw "Graph API Error" }

            { Get-GTLegacyAuthReport } | Should -Throw
        }

        It "should handle connection failures" {
            Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $false }

            { Get-GTLegacyAuthReport } | Should -Throw
        }

        It "should handle scope validation failures" {
            Mock -CommandName "Test-GTGraphScopes" -MockWith { return $false }

            { Get-GTLegacyAuthReport } | Should -Throw
        }
    }

    Context "Performance and Filtering" {
        It "should apply server-side time filtering" {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                param($Filter)
                # Verify the filter contains date filtering
                $Filter | Should -Match "createdDateTime ge"
                return @()
            }

            Get-GTLegacyAuthReport -DaysAgo 5
        }

        It "should apply SuccessOnly filter server-side" {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                param($Filter)
                # Verify the filter contains success filtering when SuccessOnly is used
                $Filter | Should -Match "status/errorCode eq 0"
                return @()
            }

            Get-GTLegacyAuthReport -SuccessOnly
        }

        It "should accumulate pipeline input correctly" {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                return @(
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user1@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "192.168.1.1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-1"
                    },
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user2@contoso.com"
                        ClientAppUsed = "POP3"
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "192.168.1.2"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-2"
                    }
                )
            }

            $users = @("user1@contoso.com", "user2@contoso.com")
            $result = $users | Get-GTLegacyAuthReport
            $result.Count | Should -Be 2
        }
    }

    Context "Defensive Protocol Detection" {
        It "should exclude modern protocols even if listed as legacy" {
            # This tests the defensive logic where a protocol must be in Legacy AND NOT in Modern
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                return @(
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user@contoso.com"
                        ClientAppUsed = "Browser"  # This is in ModernProtocols list
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "192.168.1.1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook Web"
                        Id = "request-1"
                    }
                )
            }

            $result = Get-GTLegacyAuthReport
            $result | Should -BeNullOrEmpty  # Browser should be excluded
        }

        It "should include protocols that are legacy but not modern" {
            Mock -CommandName "Get-MgAuditLogSignIn" -MockWith {
                return @(
                    [PSCustomObject]@{
                        CreatedDateTime = (Get-Date).AddDays(-1)
                        UserPrincipalName = "user@contoso.com"
                        ClientAppUsed = "POP3"  # Legacy but not modern
                        Status = [PSCustomObject]@{ ErrorCode = 0 }
                        IpAddress = "192.168.1.1"
                        Location = [PSCustomObject]@{ City = "Seattle"; CountryOrRegion = "US" }
                        AppDisplayName = "Outlook"
                        Id = "request-1"
                    }
                )
            }

            $result = Get-GTLegacyAuthReport
            $result.ClientAppUsed | Should -Contain "POP3"
        }
    }
}
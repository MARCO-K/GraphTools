Describe "Get-GTAppConsentReport" -Tag 'Unit' {
    BeforeAll {
        function global:Initialize-GTGraphConnection { param($Scopes, [switch]$NewSession) return $true }
        function global:Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Get-GTGraphHttpStatus { param($Exception) return 500 }
        function global:Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } }
        function global:Invoke-GTGraphPagedRequest { param($Uri, $Headers, [int]$TimeoutSeconds = 30) return @() }
        function global:Invoke-GTGraphRequest { param($Uri, $Method = 'GET', $Body, $Headers, $Token, [switch]$All, [int]$TimeoutSeconds = 30) return @() }
        function global:Format-ODataDateTime { param([DateTime]$DateTime) return $DateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
        function global:Get-GTConnection { return [PSCustomObject]@{ TenantId = 'tenant-local-001' } }

        . "$PSScriptRoot/../internal/functions/Get-UTCTime.ps1"
        . "$PSScriptRoot/../internal/functions/Get-GTPermissionDefinition.ps1"
        . "$PSScriptRoot/../functions/Get-GTAppConsentReport.ps1"
    }

    AfterAll {
        Remove-Item Function:\Get-GTAppConsentReport -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Initialize-GTGraphConnection -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-GTGraphScopes -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Write-PSFMessage -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-GTGraphHttpStatus -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-GTGraphErrorDetails -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-GTGraphPagedRequest -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-GTGraphRequest -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Format-ODataDateTime -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-GTConnection -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-UTCTime -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-GTPermissionDefinition -Force -ErrorAction SilentlyContinue
    }

    Context "Input Validation & Length Limits" {
        It "rejects AppId exceeding 128 characters" {
            $excessiveAppId = "a" * 129
            { Get-GTAppConsentReport -AppId $excessiveAppId } | Should -Throw
        }

        It "rejects DisplayName exceeding 256 characters" {
            $excessiveDisplayName = "a" * 257
            { Get-GTAppConsentReport -DisplayName $excessiveDisplayName } | Should -Throw
        }

        It "rejects UserId exceeding 128 characters" {
            $excessiveUserId = "a" * 129
            { Get-GTAppConsentReport -UserId $excessiveUserId } | Should -Throw
        }

        It "rejects TimeoutSeconds outside 5-300 range" {
            { Get-GTAppConsentReport -TimeoutSeconds 2 } | Should -Throw
            { Get-GTAppConsentReport -TimeoutSeconds 301 } | Should -Throw
        }

        It "rejects invalid ConsentType" {
            { Get-GTAppConsentReport -ConsentType "InvalidType" } | Should -Throw
        }

        It "rejects invalid RiskLevel" {
            { Get-GTAppConsentReport -RiskLevel "Extreme" } | Should -Throw
        }
    }

    Context "Information Leakage Defense (Sanitized Errors)" {
        It "emits sanitized error record without exposing internal URL or tokens on query failure" {
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                $fakeToken = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.sensitive-internal-token.signature"
                $ex = [System.Exception]::new("Connection refused at https://internal.graph.priv/v1.0/oauth2PermissionGrants with token $fakeToken")
                throw $ex
            }
            Mock -CommandName "Get-GTGraphHttpStatus" -MockWith { return 503 }

            $reportErrors = $null
            Get-GTAppConsentReport -ErrorVariable reportErrors -ErrorAction SilentlyContinue

            $sanitizedError = @($reportErrors | Where-Object { $_.FullyQualifiedErrorId -like 'OAuthGrantsQueryFailed*' })
            $sanitizedError.Count | Should -Be 1

            $errorMessage = $sanitizedError[0].ToString()
            $errorMessage | Should -Match "Failed to retrieve OAuth permission grants from Microsoft Graph \(HTTP 503\)"
            $errorMessage | Should -Not -Match "https://internal.graph.priv"
            $errorMessage | Should -Not -Match "sensitive-internal-token"
        }
    }

    Context "External API Timeout Propagation" {
        It "forwards configured TimeoutSeconds to Graph invokers" {
            $script:capturedPagedTimeout = $null

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers, [int]$TimeoutSeconds)
                $script:capturedPagedTimeout = $TimeoutSeconds
                return @()
            }

            $null = Get-GTAppConsentReport -TimeoutSeconds 45

            $script:capturedPagedTimeout | Should -Be 45
        }
    }

    Context "OAuth Consent Phishing & Risk Scoring" {
        BeforeEach {
            # Mock Service Principals:
            # 1. Unverified 3rd-party app (phishing candidate)
            # 2. Verified 3rd-party app
            # 3. Microsoft Graph (resource)
            $mockSps = @(
                [PSCustomObject]@{
                    id                     = 'sp-client-unverified'
                    appId                  = '00000000-0000-0000-0000-000000000001'
                    displayName            = 'SuspiciousSyncTool'
                    publisherName          = 'Unknown Entity'
                    verifiedPublisher      = $null
                    appOwnerOrganizationId = 'external-tenant-999'
                    replyUrls              = @('https://suspicious.phish/oauth')
                },
                [PSCustomObject]@{
                    id                     = 'sp-client-verified'
                    appId                  = '00000000-0000-0000-0000-000000000002'
                    displayName            = 'EnterprisePayroll'
                    publisherName          = 'Verified Corp'
                    verifiedPublisher      = [PSCustomObject]@{ verifiedPublisherId = 'mpn-12345' }
                    appOwnerOrganizationId = 'external-tenant-888'
                    replyUrls              = @('https://payroll.verified.com/callback')
                },
                [PSCustomObject]@{
                    id                     = 'sp-resource-graph'
                    appId                  = '00000003-0000-0000-c000-000000000000'
                    displayName            = 'Microsoft Graph'
                    publisherName          = 'Microsoft Services'
                    verifiedPublisher      = [PSCustomObject]@{ verifiedPublisherId = 'microsoft' }
                    appOwnerOrganizationId = 'tenant-local-001'
                    replyUrls              = @()
                }
            )

            # Mock Grants:
            # 1. User consented high-risk Mail.ReadWrite to unverified 3rd-party app (Classic OAuth Phishing -> Critical)
            # 2. Admin consented Files.ReadWrite.All tenant-wide to verified app (High)
            # 3. User consented User.Read to verified app (Low)
            $mockGrants = @(
                [PSCustomObject]@{
                    id          = 'grant-phish-01'
                    clientId    = 'sp-client-unverified'
                    consentType = 'Principal'
                    principalId = 'user-alice-01'
                    resourceId  = 'sp-resource-graph'
                    scope       = 'User.Read Mail.ReadWrite'
                },
                [PSCustomObject]@{
                    id          = 'grant-admin-02'
                    clientId    = 'sp-client-verified'
                    consentType = 'AllPrincipals'
                    principalId = $null
                    resourceId  = 'sp-resource-graph'
                    scope       = 'User.Read Files.ReadWrite.All'
                },
                [PSCustomObject]@{
                    id          = 'grant-benign-03'
                    clientId    = 'sp-client-verified'
                    consentType = 'Principal'
                    principalId = 'user-bob-02'
                    resourceId  = 'sp-resource-graph'
                    scope       = 'User.Read openid profile'
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers, [int]$TimeoutSeconds = 30)
                if ($Uri -like "*oauth2PermissionGrants*") { return $mockGrants }
                if ($Uri -like "*servicePrincipals*") { return $mockSps }
                return @()
            }

            Mock -CommandName "Invoke-GTGraphRequest" -MockWith {
                param($Uri, $Method = 'GET', $Body, $Headers, $Token, [switch]$All, [int]$TimeoutSeconds = 30)
                if ($Uri -like "*users/user-alice-01*") {
                    return [PSCustomObject]@{ id = 'user-alice-01'; userPrincipalName = 'alice@contoso.com'; displayName = 'Alice Cooper' }
                }
                if ($Uri -like "*users/user-bob-02*") {
                    return [PSCustomObject]@{ id = 'user-bob-02'; userPrincipalName = 'bob@contoso.com'; displayName = 'Bob Dylan' }
                }
                return $null
            }
        }

        It "flags unverified third-party app with user-consented high-risk scope as Critical risk" {
            $report = Get-GTAppConsentReport -AppId '00000000-0000-0000-0000-000000000001'

            @($report).Count | Should -Be 1
            $r = $report[0]
            $r.AppDisplayName | Should -Be 'SuspiciousSyncTool'
            $r.IsPublisherVerified | Should -Be $false
            $r.IsThirdParty | Should -Be $true
            $r.ConsentType | Should -Be 'Principal'
            $r.ConsentedByUserPrincipalName | Should -Be 'alice@contoso.com'
            $r.HighRiskScopes | Should -Contain 'Mail.ReadWrite'
            $r.RiskLevel | Should -Be 'Critical'
            $r.RiskScore | Should -BeGreaterOrEqual 9
            $r.RiskReasons -join ' ' | Should -Match "OAuth Phishing Vector"
        }

        It "evaluates admin tenant-wide consent for broad files access as High risk" {
            $report = Get-GTAppConsentReport -ConsentType 'AllPrincipals'

            @($report).Count | Should -Be 1
            $r = $report[0]
            $r.AppDisplayName | Should -Be 'EnterprisePayroll'
            $r.IsPublisherVerified | Should -Be $true
            $r.ConsentType | Should -Be 'AllPrincipals'
            $r.HighRiskScopes | Should -Contain 'Files.ReadWrite.All'
            $r.RiskLevel | Should -Be 'High'
        }

        It "evaluates basic user consent for benign identity scopes as Low risk" {
            $report = Get-GTAppConsentReport -RiskLevel 'Low'

            @($report).Count | Should -Be 1
            $r = $report[0]
            $r.AppDisplayName | Should -Be 'EnterprisePayroll'
            $r.RiskLevel | Should -Be 'Low'
            $r.ConsentedByUserPrincipalName | Should -Be 'bob@contoso.com'
        }

        It "filters by UnverifiedOnly switch" {
            $report = Get-GTAppConsentReport -UnverifiedOnly

            @($report).Count | Should -Be 1
            $report[0].AppDisplayName | Should -Be 'SuspiciousSyncTool'
        }

        It "filters by ThirdPartyOnly switch" {
            $report = Get-GTAppConsentReport -ThirdPartyOnly

            @($report).Count | Should -Be 3
        }

        It "filters by UserId parameter matching UPN" {
            $report = Get-GTAppConsentReport -UserId 'alice@contoso.com'

            @($report).Count | Should -Be 1
            $report[0].ConsentedByUserPrincipalName | Should -Be 'alice@contoso.com'
        }
    }

    Context "Summary KPI Mode" {
        BeforeEach {
            $mockSps = @(
                [PSCustomObject]@{
                    id                     = 'sp-1'
                    appId                  = '00000000-0000-0000-0000-000000000001'
                    displayName            = 'App1'
                    publisherName          = 'Pub1'
                    verifiedPublisher      = $null
                    appOwnerOrganizationId = 'ext-1'
                },
                [PSCustomObject]@{
                    id                     = 'sp-2'
                    appId                  = '00000000-0000-0000-0000-000000000002'
                    displayName            = 'App2'
                    publisherName          = 'Pub2'
                    verifiedPublisher      = [PSCustomObject]@{ verifiedPublisherId = 'mpn-999' }
                    appOwnerOrganizationId = 'tenant-local-001'
                }
            )

            $mockGrants = @(
                [PSCustomObject]@{ id = 'g-1'; clientId = 'sp-1'; consentType = 'Principal'; principalId = 'u-1'; resourceId = 'r-1'; scope = 'Mail.ReadWrite' },
                [PSCustomObject]@{ id = 'g-2'; clientId = 'sp-2'; consentType = 'AllPrincipals'; principalId = $null; resourceId = 'r-1'; scope = 'User.Read' }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers, [int]$TimeoutSeconds = 30)
                if ($Uri -like "*oauth2PermissionGrants*") { return $mockGrants }
                if ($Uri -like "*servicePrincipals*") { return $mockSps }
                return @()
            }
            Mock -CommandName "Invoke-GTGraphRequest" -MockWith { return $null }
        }

        It "aggregates tenant consent metrics into a single KPI card" {
            $summary = Get-GTAppConsentReport -Summary

            $summary.TotalGrantsScanned | Should -Be 2
            $summary.TotalAppsScanned | Should -Be 2
            $summary.CriticalCount | Should -Be 1
            $summary.LowCount | Should -Be 1
            $summary.UnverifiedAppsCount | Should -Be 1
            $summary.ThirdPartyAppsCount | Should -Be 1
            $summary.UserConsentedCount | Should -Be 1
            $summary.AdminConsentedCount | Should -Be 1
            $summary.ScanTimestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context "Pipeline Filtering" {
        BeforeEach {
            $mockSps = @(
                [PSCustomObject]@{ id = 'sp-1'; appId = '00000000-0000-0000-0000-000000000099'; displayName = 'FinApp'; verifiedPublisher = $null },
                [PSCustomObject]@{ id = 'sp-2'; appId = '00000000-0000-0000-0000-000000000088'; displayName = 'SalesApp'; verifiedPublisher = $null }
            )
            $mockGrants = @(
                [PSCustomObject]@{ id = 'g-1'; clientId = 'sp-1'; consentType = 'Principal'; scope = 'User.Read' },
                [PSCustomObject]@{ id = 'g-2'; clientId = 'sp-2'; consentType = 'Principal'; scope = 'User.Read' }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers, [int]$TimeoutSeconds = 30)
                if ($Uri -like "*oauth2PermissionGrants*") { return $mockGrants }
                if ($Uri -like "*servicePrincipals*") { return $mockSps }
                return @()
            }
            Mock -CommandName "Invoke-GTGraphRequest" -MockWith { return $null }
        }

        It "filters by AppId passed via pipeline as bare GUID string" {
            $res = "00000000-0000-0000-0000-000000000099" | Get-GTAppConsentReport
            @($res).Count | Should -Be 1
            $res[0].AppDisplayName | Should -Be 'FinApp'
        }

        It "filters by DisplayName passed via pipeline as bare string" {
            $res = "SalesApp" | Get-GTAppConsentReport
            @($res).Count | Should -Be 1
            $res[0].AppDisplayName | Should -Be 'SalesApp'
        }

        It "filters by DisplayName property passed via pipeline object" {
            $res = [PSCustomObject]@{ DisplayName = "FinApp" } | Get-GTAppConsentReport
            @($res).Count | Should -Be 1
            $res[0].AppDisplayName | Should -Be 'FinApp'
        }
    }
}

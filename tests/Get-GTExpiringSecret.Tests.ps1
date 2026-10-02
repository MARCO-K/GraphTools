Describe "Get-GTExpiringSecret" -Tag 'Unit' {
    BeforeAll {
        function global:Initialize-GTGraphConnection { param($Scopes, [switch]$NewSession) return $true }
        function global:Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } }
        function global:Invoke-GTGraphPagedRequest { param($Uri, $Headers) return @() }
        function global:Format-ODataDateTime { param([DateTime]$DateTime) return $DateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }

        . "$PSScriptRoot/../internal/functions/Get-GTUtcTime.ps1"
        . "$PSScriptRoot/../functions/Get-GTExpiringSecret.ps1"
    }

    AfterAll {
        Remove-Item Function:\Initialize-GTGraphConnection -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-GTGraphScopes -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Write-PSFMessage -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-GTGraphErrorDetails -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-GTGraphPagedRequest -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Format-ODataDateTime -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-GTExpiringSecret -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Get-GTExpiringSecrets -Force -ErrorAction SilentlyContinue
    }

    Context "Alias Support" {
        It "resolves the legacy Get-GTExpiringSecrets alias to Get-GTExpiringSecret" {
            (Get-Command Get-GTExpiringSecrets).ResolvedCommandName | Should -Be 'Get-GTExpiringSecret'
        }
    }

    Context "Backward Compatibility (Legacy Mode)" {
        It "identifies credentials expiring within DaysUntilExpiry" {
            $now = Get-UTCTime
            $mockApps = @(
                [PSCustomObject]@{
                    id                  = "app-1"
                    appId               = "00000000-0000-0000-0000-000000000001"
                    displayName         = "LegacyApp"
                    passwordCredentials = @(
                        [PSCustomObject]@{
                            keyId       = "secret-1"
                            hint        = "sec"
                            endDateTime = $now.AddDays(10)
                        }
                    )
                    keyCredentials      = @()
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                if ($Uri -like "*applications*") { return $mockApps }
                return @()
            }

            $results = Get-GTExpiringSecret -DaysUntilExpiry 30
            @($results).Count | Should -Be 1
            $results[0].CredentialType | Should -Be "Secret"
            $results[0].DaysRemaining | Should -BeLessThan 11
            $results[0].DaysRemaining | Should -BeGreaterThan 0
            $results[0].Status | Should -Be "Warning"
        }

        It "excludes expired credentials when in pure legacy mode" {
            $now = Get-UTCTime
            $mockApps = @(
                [PSCustomObject]@{
                    id                  = "app-expired"
                    appId               = "00000000-0000-0000-0000-000000000002"
                    displayName         = "ExpiredApp"
                    passwordCredentials = @(
                        [PSCustomObject]@{
                            keyId       = "secret-expired"
                            endDateTime = $now.AddDays(-5)
                        }
                    )
                    keyCredentials      = @()
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                if ($Uri -like "*applications*") { return $mockApps }
                return @()
            }

            $results = Get-GTExpiringSecret -DaysUntilExpiry 30
            @($results).Count | Should -Be 0
        }

        It "respects Scope parameter for Applications and ServicePrincipals" {
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @() }

            Get-GTExpiringSecret -DaysUntilExpiry 30 -Scope Applications
            Assert-MockCalled -CommandName "Invoke-GTGraphPagedRequest" -Times 1 -ParameterFilter { $Uri -like "*applications*" }
            Assert-MockCalled -CommandName "Invoke-GTGraphPagedRequest" -Times 0 -ParameterFilter { $Uri -like "*servicePrincipals*" }

            Get-GTExpiringSecret -DaysUntilExpiry 30 -Scope ServicePrincipals
            Assert-MockCalled -CommandName "Invoke-GTGraphPagedRequest" -Times 1 -ParameterFilter { $Uri -like "*servicePrincipals*" }
        }
    }

    Context "Multi-Tier Urgency Categorization" {
        It "categorizes Expired, Critical, Warning, and Healthy credentials accurately" {
            $now = Get-UTCTime
            $mockApps = @(
                [PSCustomObject]@{
                    id                  = "app-multi"
                    appId               = "00000000-0000-0000-0000-000000000003"
                    displayName         = "MultiCredApp"
                    passwordCredentials = @(
                        [PSCustomObject]@{ keyId = "k-expired"; endDateTime = $now.AddDays(-2) },
                        [PSCustomObject]@{ keyId = "k-critical"; endDateTime = $now.AddDays(4) },
                        [PSCustomObject]@{ keyId = "k-warning"; endDateTime = $now.AddDays(20) },
                        [PSCustomObject]@{ keyId = "k-healthy"; endDateTime = $now.AddDays(100) }
                    )
                    keyCredentials      = @()
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                if ($Uri -like "*applications*") { return $mockApps }
                return @()
            }

            # Query All statuses
            $results = Get-GTExpiringSecret -Status All -Scope Applications
            @($results).Count | Should -Be 4

            $expired = $results | Where-Object { $_.KeyId -eq 'k-expired' }
            $expired.Status | Should -Be 'Expired'
            $expired.DaysRemaining | Should -BeLessThan 0

            $critical = $results | Where-Object { $_.KeyId -eq 'k-critical' }
            $critical.Status | Should -Be 'Critical'
            $critical.DaysRemaining | Should -BeLessOrEqual 7

            $warning = $results | Where-Object { $_.KeyId -eq 'k-warning' }
            $warning.Status | Should -Be 'Warning'
            $warning.DaysRemaining | Should -BeGreaterThan 7

            $healthy = $results | Where-Object { $_.KeyId -eq 'k-healthy' }
            $healthy.Status | Should -Be 'Healthy'
            $healthy.DaysRemaining | Should -BeGreaterThan 30
        }

        It "filters specifically by Status parameter" {
            $now = Get-UTCTime
            $mockApps = @(
                [PSCustomObject]@{
                    id                  = "app-filter"
                    appId               = "00000000-0000-0000-0000-000000000004"
                    displayName         = "FilteredApp"
                    passwordCredentials = @(
                        [PSCustomObject]@{ keyId = "k1"; endDateTime = $now.AddDays(-10) },
                        [PSCustomObject]@{ keyId = "k2"; endDateTime = $now.AddDays(3) }
                    )
                    keyCredentials      = @()
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                if ($Uri -like "*applications*") { return $mockApps }
                return @()
            }

            $onlyExpired = Get-GTExpiringSecret -Status Expired -Scope Applications
            @($onlyExpired).Count | Should -Be 1
            $onlyExpired[0].KeyId | Should -Be 'k1'

            $onlyCritical = Get-GTExpiringSecret -Status Critical -Scope Applications
            @($onlyCritical).Count | Should -Be 1
            $onlyCritical[0].KeyId | Should -Be 'k2'
        }
    }

    Context "Impact Analysis Engine" {
        It "detects Single Point of Failure (IsSoleCredential = true) when no alternative valid credential exists" {
            $now = Get-UTCTime
            $mockApps = @(
                [PSCustomObject]@{
                    id                  = "app-spof"
                    appId               = "00000000-0000-0000-0000-000000000005"
                    displayName         = "SPOFApp"
                    passwordCredentials = @(
                        [PSCustomObject]@{ keyId = "sole-cred"; endDateTime = $now.AddDays(2) }
                    )
                    keyCredentials      = @()
                    owners              = @(
                        [PSCustomObject]@{ id = "u1"; userPrincipalName = "admin@contoso.com"; displayName = "Admin User" }
                    )
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                if ($Uri -like "*applications*") { return $mockApps }
                return @()
            }

            $res = Get-GTExpiringSecret -IncludeImpactAnalysis -Scope Applications
            @($res).Count | Should -Be 1
            $res[0].IsSoleCredential | Should -Be $true
            $res[0].TotalActiveCredentials | Should -Be 1
            $res[0].Owners | Should -Be "admin@contoso.com"
            $res[0].IsOrphaned | Should -Be $false
        }

        It "detects rollover in progress (IsSoleCredential = false) when an alternative valid credential is present" {
            $now = Get-UTCTime
            $mockApps = @(
                [PSCustomObject]@{
                    id                  = "app-rollover"
                    appId               = "00000000-0000-0000-0000-000000000006"
                    displayName         = "RolloverApp"
                    passwordCredentials = @(
                        [PSCustomObject]@{ keyId = "old-cred"; endDateTime = $now.AddDays(3) },
                        [PSCustomObject]@{ keyId = "new-cred"; endDateTime = $now.AddDays(365) }
                    )
                    keyCredentials      = @()
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                if ($Uri -like "*applications*") { return $mockApps }
                return @()
            }

            $res = Get-GTExpiringSecret -IncludeImpactAnalysis -Scope Applications
            $expiringOld = $res | Where-Object { $_.KeyId -eq 'old-cred' }
            $expiringOld.IsSoleCredential | Should -Be $false
            $expiringOld.TotalActiveCredentials | Should -Be 2
            $expiringOld.OutageRisk | Should -Be 'Medium'
        }

        It "evaluates Active Outage Risk using sign-in telemetry on Service Principals" {
            $now = Get-UTCTime
            $mockSps = @(
                [PSCustomObject]@{
                    id                  = "sp-active"
                    appId               = "00000000-0000-0000-0000-000000000007"
                    displayName         = "ActiveProdSP"
                    passwordCredentials = @(
                        [PSCustomObject]@{ keyId = "active-cred"; endDateTime = $now.AddDays(1) }
                    )
                    keyCredentials      = @()
                    signInActivity      = [PSCustomObject]@{
                        lastSignInDateTime = $now.AddDays(-2).ToString("o")
                    }
                    owners              = @()
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                if ($Uri -like "*servicePrincipals*") { return $mockSps }
                return @()
            }

            $res = Get-GTExpiringSecret -IncludeImpactAnalysis -Scope ServicePrincipals
            @($res).Count | Should -Be 1
            $res[0].OutageRisk | Should -Be "Immediate Outage"
            $res[0].IsOrphaned | Should -Be $true
            $res[0].LastSignInDateTime | Should -Not -BeNullOrEmpty
        }

        It "scores OutageRisk as Low for dormant workloads (sign-ins older than 90 days)" {
            $now = Get-UTCTime
            $mockSps = @(
                [PSCustomObject]@{
                    id                  = "sp-dormant"
                    appId               = "00000000-0000-0000-0000-000000000099"
                    displayName         = "DormantSP"
                    passwordCredentials = @(
                        [PSCustomObject]@{ keyId = "dormant-cred"; endDateTime = $now.AddDays(1) }
                    )
                    keyCredentials      = @()
                    signInActivity      = [PSCustomObject]@{
                        lastSignInDateTime = $now.AddDays(-120).ToString("o")
                    }
                    owners              = @()
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                if ($Uri -like "*servicePrincipals*") { return $mockSps }
                return @()
            }

            $res = Get-GTExpiringSecret -IncludeImpactAnalysis -Scope ServicePrincipals
            @($res).Count | Should -Be 1
            $res[0].OutageRisk | Should -Be "Low"
        }
    }

    Context "Summary KPI Mode" {
        It "returns aggregated metrics when -Summary switch is specified" {
            $now = Get-UTCTime
            $mockApps = @(
                [PSCustomObject]@{
                    id                  = "app-sum-1"
                    appId               = "00000000-0000-0000-0000-000000000008"
                    displayName         = "SummaryApp1"
                    passwordCredentials = @(
                        [PSCustomObject]@{ keyId = "k-exp"; endDateTime = $now.AddDays(-1) },
                        [PSCustomObject]@{ keyId = "k-crit"; endDateTime = $now.AddDays(2) }
                    )
                    keyCredentials      = @()
                    owners              = @()
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                if ($Uri -like "*applications*") { return $mockApps }
                return @()
            }

            $summary = Get-GTExpiringSecret -IncludeImpactAnalysis -Summary -Scope Applications
            $summary.TotalAppsScanned | Should -Be 1
            $summary.TotalCredentialsFound | Should -Be 2
            $summary.ExpiredCount | Should -Be 1
            $summary.CriticalCount | Should -Be 1
            $summary.OrphanedAppsCount | Should -Be 1
            $summary.ScanTimestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context "Pipeline Filtering" {
        It "filters queries by AppId passed via pipeline" {
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @() }

            "00000000-0000-0000-0000-000000000099" | Get-GTExpiringSecret -Scope Applications
            Assert-MockCalled -CommandName "Invoke-GTGraphPagedRequest" -Times 1 -ParameterFilter {
                $Uri -match "filter=.*appId.*00000000-0000-0000-0000-000000000099"
            }
        }

        It "filters queries by DisplayName passed via pipeline as bare string" {
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @() }

            "FinanceApp" | Get-GTExpiringSecret -Scope Applications
            Assert-MockCalled -CommandName "Invoke-GTGraphPagedRequest" -Times 1 -ParameterFilter {
                $Uri -match "filter=.*displayName.*FinanceApp"
            }
        }

        It "filters queries by DisplayName property passed via pipeline object" {
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @() }

            [PSCustomObject]@{ DisplayName = "BillingApp" } | Get-GTExpiringSecret -Scope Applications
            Assert-MockCalled -CommandName "Invoke-GTGraphPagedRequest" -Times 1 -ParameterFilter {
                $Uri -match "filter=.*displayName.*BillingApp"
            }
        }
    }
}

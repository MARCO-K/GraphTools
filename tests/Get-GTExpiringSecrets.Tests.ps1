Describe "Get-GTExpiringSecrets" {
    BeforeAll {
        function global:Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function global:Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } }
        function global:Invoke-GTGraphPagedRequest { param($Uri, [switch]$All) return @() }

        . "$PSScriptRoot/../internal/functions/Get-UTCTime.ps1"
        . "$PSScriptRoot/../functions/Get-GTExpiringSecrets.ps1"
    }

    Context "Functionality" {
        It "should identify expiring secrets" {
            $expiryDate = (Get-UTCTime).AddDays(10)
            $mockApps = @(
                [PSCustomObject]@{
                    id                  = "1"
                    appId               = "App1"
                    displayName         = "TestApp"
                    passwordCredentials = @(
                        [PSCustomObject]@{
                            keyId       = "Key1"
                            endDateTime = $expiryDate
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

            $results = Get-GTExpiringSecrets -DaysUntilExpiry 30
            @($results).Count | Should -Be 1
            $results[0].CredentialType | Should -Be "Secret"
            $results[0].DaysRemaining | Should -BeLessThan 11
        }

        It "should respect scope parameter" {
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @() }

            Get-GTExpiringSecrets -DaysUntilExpiry 30 -Scope Applications
            Assert-MockCalled -CommandName "Invoke-GTGraphPagedRequest" -Times 1 -ParameterFilter { $Uri -like "*applications*" }
            Assert-MockCalled -CommandName "Invoke-GTGraphPagedRequest" -Times 0 -ParameterFilter { $Uri -like "*servicePrincipals*" }
        }

        It "should find expiring certificates on service principals" {
            $expiryDate = (Get-UTCTime).AddDays(5)
            $mockSps = @(
                [PSCustomObject]@{
                    id                  = 'sp-1'
                    appId               = 'SPApp1'
                    displayName         = 'TestSP'
                    passwordCredentials = @()
                    keyCredentials      = @(
                        [PSCustomObject]@{
                            keyId       = 'Cert1'
                            endDateTime = $expiryDate
                        }
                    )
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                if ($Uri -like "*servicePrincipals*") { return $mockSps }
                return @()
            }

            $results = Get-GTExpiringSecrets -DaysUntilExpiry 10 -Scope ServicePrincipals
            @($results).Count | Should -Be 1
            $results[0].ResourceType | Should -Be 'ServicePrincipal'
            $results[0].CredentialType | Should -Be 'Certificate'
        }
    }
}

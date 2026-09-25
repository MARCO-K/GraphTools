Describe "Get-GTOrphanedServicePrincipal" {
    BeforeAll {
        function global:Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function global:Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession) return $true }
        function global:Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Stop-PSFFunction { param($Message, $ErrorRecord, [switch]$EnableException) throw $Message }
        function global:Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } }
        function global:Get-UTCTime { return [DateTime]::UtcNow }
        function global:Invoke-GTGraphPagedRequest { param($Uri, [switch]$All) return @() }

        . "$PSScriptRoot/../internal/functions/Get-UTCTime.ps1"
        . "$PSScriptRoot/../functions/Get-GTOrphanedServicePrincipal.ps1"
    }

    Context "Function Execution" {
        It "should not throw when properly configured" {
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @() }
            { Get-GTOrphanedServicePrincipal } | Should -Not -Throw
        }
    }

    Context "Logic Verification" {
        It "should identify SPs with no owners" {
            $mockSP = @(
                [PSCustomObject]@{
                    Id             = "1"
                    AppId          = "app1"
                    DisplayName    = "No Owner SP"
                    Owners         = @()
                    AccountEnabled = $true
                }
            )
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return $mockSP }
            
            $result = Get-GTOrphanedServicePrincipal
            @($result).Count | Should -Be 1
            $result[0].OrphanReason | Should -Match "NoOwners"
        }

        It "should identify SPs with all owners disabled" {
            $mockOwner = [PSCustomObject]@{
                Id                   = "o1"
                AccountEnabled       = $false
                AdditionalProperties = @{ accountEnabled = $false }
            }
            $mockSP = @(
                [PSCustomObject]@{
                    Id             = "2"
                    AppId          = "app2"
                    DisplayName    = "Disabled Owner SP"
                    Owners         = @($mockOwner)
                    AccountEnabled = $true
                }
            )
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return $mockSP }

            $result = Get-GTOrphanedServicePrincipal
            @($result).Count | Should -Be 1
            $result[0].OrphanReason | Should -Match "AllOwnersDisabled"
        }

        It "should identify expired credentials when switch is on" {
            $expiredDate = (Get-UTCTime).AddDays(-1)
            $mockSP = @(
                [PSCustomObject]@{
                    Id                  = "3"
                    AppId               = "app3"
                    DisplayName         = "Expired Creds SP"
                    Owners              = @(@{ AccountEnabled = $true; AdditionalProperties = @{ accountEnabled = $true } })
                    AccountEnabled      = $true
                    PasswordCredentials = @(@{ EndDateTime = $expiredDate })
                }
            )
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return $mockSP }

            $result = Get-GTOrphanedServicePrincipal -CheckExpiredCredentials
            @($result).Count | Should -Be 1
            $result[0].OrphanReason | Should -Match "ExpiredCredentials"
        }
    }
}

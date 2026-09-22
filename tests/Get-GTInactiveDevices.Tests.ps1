Describe "Get-GTInactiveDevices" {
    BeforeAll {
        function global:Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function global:Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession) return $true }
        function global:Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } }
        function global:Invoke-GTGraphPagedRequest { param($Uri, [switch]$All) return @() }

        . "$PSScriptRoot/../internal/functions/Get-UTCTime.ps1"
        . "$PSScriptRoot/../internal/functions/Format-ODataDateTime.ps1"
        . "$PSScriptRoot/../functions/Get-GTInactiveDevices.ps1"
    }

    Context "Functionality" {
        It "should identify inactive devices" {
            $lastSignIn = (Get-UTCTime).AddDays(-100)
            $mockDevices = @(
                [PSCustomObject]@{
                    id                            = "1"
                    displayName                   = "InactiveDevice"
                    operatingSystem               = "Windows"
                    approximateLastSignInDateTime = $lastSignIn
                    accountEnabled                = $true
                }
            )
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return $mockDevices }

            $results = Get-GTInactiveDevices -InactiveDays 90
            $results.Count | Should -Be 1
            $results[0].DaysInactive | Should -BeGreaterOrEqual 100
        }

        It "should request server-side filter that excludes disabled devices by default" {
            $script:CapturedUri = $null
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                $script:CapturedUri = $Uri
                return @()
            }

            Get-GTInactiveDevices -InactiveDays 90

            $unescaped = [Uri]::UnescapeDataString($script:CapturedUri)
            $unescaped | Should -Match "accountEnabled eq true"
            Assert-MockCalled -CommandName "Invoke-GTGraphPagedRequest" -Times 1
        }

        It "should request server-side filter without accountEnabled when -IncludeDisabled is provided" {
            $lastSignIn = (Get-UTCTime).AddDays(-100)
            $mockDevices = @(
                [PSCustomObject]@{
                    id                            = "2"
                    displayName                   = "DisabledDevice"
                    operatingSystem               = "Windows"
                    approximateLastSignInDateTime = $lastSignIn
                    accountEnabled                = $false
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                $unescaped = [Uri]::UnescapeDataString($Uri)
                if (-not ($unescaped -match "accountEnabled eq true")) {
                    return $mockDevices
                }
                return @()
            }

            $results = Get-GTInactiveDevices -InactiveDays 90 -IncludeDisabled
            $results.Count | Should -Be 1
        }
    }
}

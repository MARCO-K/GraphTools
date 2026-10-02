Describe "Get-GTInactiveDevice" {
    BeforeAll {
        function global:Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function global:Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession) return $true }
        function global:Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } }
        function global:Invoke-GTGraphPagedRequest { param($Uri, [switch]$All) return @() }

        $statusHelper = Join-Path $PSScriptRoot '..\internal\functions\Get-GTGraphHttpStatus.ps1'
        if (Test-Path $statusHelper) { . $statusHelper }

        . "$PSScriptRoot/../internal/functions/Get-GTUtcTime.ps1"
        . "$PSScriptRoot/../internal/functions/Format-GTODataDateTime.ps1"
        . "$PSScriptRoot/../functions/Get-GTInactiveDevice.ps1"
    }

    AfterAll {
        Remove-Item Function:\Get-GTInactiveDevice -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Get-GTInactiveDevices -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Install-GTRequiredModule -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Initialize-GTGraphConnection -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Test-GTGraphScopes -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Write-PSFMessage -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Get-GTGraphErrorDetails -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Invoke-GTGraphPagedRequest -Force -ErrorAction SilentlyContinue
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

            $results = Get-GTInactiveDevice -InactiveDays 90
            @($results).Count | Should -Be 1
            $results[0].DaysInactive | Should -BeGreaterOrEqual 100
        }

        It "should support the legacy Get-GTInactiveDevices alias" {
            (Get-Command Get-GTInactiveDevices).ResolvedCommandName | Should -Be 'Get-GTInactiveDevice'
        }

        It "should request server-side filter that excludes disabled devices by default" {
            $script:CapturedUri = $null
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri)
                $script:CapturedUri = $Uri
                return @()
            }

            Get-GTInactiveDevice -InactiveDays 90

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

            $results = Get-GTInactiveDevice -InactiveDays 90 -IncludeDisabled
            @($results).Count | Should -Be 1
        }
    }
}

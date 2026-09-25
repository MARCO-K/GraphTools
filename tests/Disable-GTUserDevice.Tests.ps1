# Pester tests for Disable-GTUserDevice
# Provide lightweight stubs for common helpers in case they are missing during discovery
if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param($ModuleNames, $Verbose) } }
if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param($RequiredScopes, $Reconnect, $Quiet) return $true } }
if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }
if (-not (Get-Command Get-UTCTime -ErrorAction SilentlyContinue)) { function Get-UTCTime { return [DateTime]::UtcNow } }
if (-not (Get-Command Invoke-GTGraphRequest -ErrorAction SilentlyContinue)) { function Invoke-GTGraphRequest { param($Method, $Uri, $Body, $ContentType, $ErrorAction) } }
if (-not (Get-Command Invoke-GTGraphPagedRequest -ErrorAction SilentlyContinue)) { function Invoke-GTGraphPagedRequest { param($Uri) return @() } }

Describe "Disable-GTUserDevice" -Tag 'Unit' {
    BeforeAll {
        $validationFile = Join-Path $PSScriptRoot '..\internal\functions\GTValidation.ps1'
        if (Test-Path $validationFile) { . $validationFile }

        $guidHelper = Join-Path $PSScriptRoot '..\internal\functions\Test-GTGuid.ps1'
        if (Test-Path $guidHelper) { . $guidHelper }

        $errorHelperFile = Join-Path $PSScriptRoot '..\internal\functions\Get-GTGraphErrorDetails.ps1'
        if (Test-Path $errorHelperFile) { . $errorHelperFile }

        $utcHelper = Join-Path $PSScriptRoot '..\internal\functions\Get-UTCTime.ps1'
        if (Test-Path $utcHelper) { . $utcHelper }

        $installHelper = Join-Path $PSScriptRoot '..\internal\functions\Install-GTRequiredModule.ps1'
        if (Test-Path $installHelper) { . $installHelper }

        $initHelper = Join-Path $PSScriptRoot '..\internal\functions\Initialize-GTGraphConnection.ps1'
        if (Test-Path $initHelper) { . $initHelper }

        function Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function Install-GTRequiredModule { }
        function Initialize-GTGraphConnection { return $true }
        function Test-GTGraphScopes { return $true }
        function Invoke-GTGraphRequest { param($Method, $Uri, $Body, $ContentType, $ErrorAction) }
        function Invoke-GTGraphPagedRequest { param($Uri) return @() }

        $functionFile = Join-Path $PSScriptRoot '..\functions\Disable-GTUserDevice.ps1'
        if (-not (Test-Path $functionFile)) { Throw "Function file not found: $functionFile" }

        . $functionFile
    }

    BeforeEach {
        Mock -CommandName Install-GTRequiredModule -MockWith { }
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true }
        Mock -CommandName Test-GTGraphScopes -MockWith { return $true }
        Mock -CommandName Write-PSFMessage -MockWith { }
        Mock -CommandName Invoke-GTGraphRequest -MockWith {
            param($Method, $Uri, $Body)
            if ($Method -eq 'GET') {
                return [PSCustomObject]@{ id = '12345678-1234-1234-1234-123456789abc' }
            }
            return $null
        }
        Mock -CommandName Invoke-GTGraphPagedRequest -MockWith { return @() }
    }

    Context "Parameter Validation" {
        It "should throw an error for an invalid UPN (no @ symbol)" {
            { Disable-GTUserDevice -UPN "invalid-user" } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty local part)" {
            { Disable-GTUserDevice -UPN "@domain.com" } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty domain part)" {
            { Disable-GTUserDevice -UPN "user@" } | Should -Throw
        }
    }

    Context "Device Disabling" {
        It "disables devices for a user and returns a single array of Disabled results" {
            $upn = 'alice@contoso.com'
            $userId = '12345678-1234-1234-1234-123456789abc'

            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                param($Method, $Uri, $Body)
                if ($Method -eq 'GET') {
                    return [PSCustomObject]@{ id = '12345678-1234-1234-1234-123456789abc' }
                }
                return $null
            }

            Mock -CommandName Invoke-GTGraphPagedRequest -MockWith {
                @(
                    [PSCustomObject]@{
                        id             = "device-id-1"
                        displayName    = "Test Device"
                        accountEnabled = $true
                    }
                )
            }

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.GetType().Name | Should -Be 'Object[]'
            $results.Count | Should -Be 1

            $results[0].Status | Should -Be 'Disabled'
            $results[0].User | Should -Be $upn
            $results[0].DeviceId | Should -Be "device-id-1"
            $results[0].DeviceName | Should -Be "Test Device"

            Should -Invoke -CommandName Invoke-GTGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It "handles users with no enabled devices" {
            $upn = 'nodevices@contoso.com'
            $userId = 'a1b2c3d4-e5f6-a7b8-c9d0-e1f2a3b4c5d6'

            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return [PSCustomObject]@{ id = 'a1b2c3d4-e5f6-a7b8-c9d0-e1f2a3b4c5d6' }
                }
                return $null
            }

            Mock -CommandName Invoke-GTGraphPagedRequest -MockWith { @() }

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.Count | Should -Be 1
            $results[0].Status | Should -Be 'NoDevices'
            $results[0].User | Should -Be $upn
            $results[0].Reason | Should -Match 'No enabled devices'
        }

        It "honors -Force and invokes patch" {
            $upn = 'charlie@contoso.com'
            $userId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return [PSCustomObject]@{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
                }
                return $null
            }

            Mock -CommandName Invoke-GTGraphPagedRequest -MockWith {
                @(
                    [PSCustomObject]@{
                        id             = "device-id-3"
                        displayName    = "Test Device"
                        accountEnabled = $true
                    }
                )
            }

            $results = Disable-GTUserDevice -UPN $upn -Force -Confirm:$false

            $results.Count | Should -Be 1
            $results[0].Status | Should -Be 'Disabled'
            Should -Invoke -CommandName Invoke-GTGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It "returns Failed with HttpStatus 404 when Graph returns a not found error for device operation" {
            $upn = 'user@contoso.com'
            $userId = '11111111-2222-3333-4444-555555555555'

            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return [PSCustomObject]@{ id = '11111111-2222-3333-4444-555555555555' }
                }
                if ($Method -eq 'PATCH') {
                    throw [System.Exception]::new('404 Not Found - The device does not exist')
                }
                return $null
            }

            Mock -CommandName Invoke-GTGraphPagedRequest -MockWith {
                @(
                    [PSCustomObject]@{
                        id             = "device-id-404"
                        displayName    = "Test Device"
                        accountEnabled = $true
                    }
                )
            }

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.Count | Should -Be 1
            $entry = $results[0]
            $entry.Status | Should -Be 'Failed'
            $entry.HttpStatus | Should -Be 404
            $entry.Reason | Should -Match 'could not be processed'
        }

        It "returns Failed with HttpStatus 403 when Graph returns insufficient privileges error" {
            $upn = 'user@contoso.com'
            $userId = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'

            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return [PSCustomObject]@{ id = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' }
                }
                if ($Method -eq 'PATCH') {
                    throw [System.Exception]::new('403 Insufficient privileges to complete the operation')
                }
                return $null
            }

            Mock -CommandName Invoke-GTGraphPagedRequest -MockWith {
                @(
                    [PSCustomObject]@{
                        id             = "device-id-403"
                        displayName    = "Test Device"
                        accountEnabled = $true
                    }
                )
            }

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.Count | Should -Be 1
            $entry = $results[0]
            $entry.Status | Should -Be 'Failed'
            $entry.HttpStatus | Should -Be 403
        }

        It "returns Failed when user retrieval fails with 404" {
            $upn = 'doesnotexist@contoso.com'

            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    throw [System.Exception]::new('404 Not Found - The user does not exist')
                }
                return $null
            }

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.Count | Should -Be 1
            $entry = $results[0]
            $entry.Status | Should -Be 'Failed'
            $entry.HttpStatus | Should -Be 404
            $entry.Reason | Should -Match 'could not be processed'
        }

        It "processes multiple devices for a single user" {
            $upn = 'multidevice@contoso.com'
            $userId = 'fedcba98-7654-3210-fedc-ba9876543210'

            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                param($Method, $Uri)
                if ($Method -eq 'GET') {
                    return [PSCustomObject]@{ id = 'fedcba98-7654-3210-fedc-ba9876543210' }
                }
                return $null
            }

            Mock -CommandName Invoke-GTGraphPagedRequest -MockWith {
                @(
                    [PSCustomObject]@{
                        id             = "device-1"
                        displayName    = "Device device-1"
                        accountEnabled = $true
                    },
                    [PSCustomObject]@{
                        id             = "device-2"
                        displayName    = "Device device-2"
                        accountEnabled = $true
                    }
                )
            }

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.Count | Should -Be 2
            $results[0].Status | Should -Be 'Disabled'
            $results[1].Status | Should -Be 'Disabled'
            Should -Invoke -CommandName Invoke-GTGraphRequest -Times 2 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }
}

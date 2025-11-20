# Pester tests for Disable-GTUserDevice
# Provide lightweight stubs for common helpers in case they are missing during discovery
if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param($ModuleNames, $Verbose) } }
if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param($Scopes, $NewSession) return $true } }
if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param($RequiredScopes, $Reconnect, $Quiet) return $true } }
if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }
# Requires Pester 5.x
# Place this file in the repository under: tests/Disable-GTUserDevice.Tests.ps1

Describe "Disable-GTUserDevice" -Tag 'Unit' {
    # Dot-source the function under test. Adjust path if your tests run from a different working directory.
    BeforeAll {
        # Load the validation regex first (required by the function)
        $validationFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'GTValidation.ps1'
        if (Test-Path $validationFile)
        {
            . $validationFile
        }

        # Load the error handling helper function (required by Disable-GTUserDevice)
        $errorHelperFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'Get-GTGraphErrorDetails.ps1'
        if (Test-Path $errorHelperFile)
        {
            . $errorHelperFile
        }

        $functionFile = Join-Path $PSScriptRoot '..' 'functions' 'Disable-GTUserDevice.ps1'
        if (-not (Test-Path $functionFile))
        {
            Throw "Function file not found: $functionFile"
        }

        # Use Pester Mocks for external dependencies BEFORE loading the function
        # These will be replaced or configured in BeforeEach and in individual tests
        Mock -CommandName Write-PSFMessage -MockWith { param($Level, $Message, $ErrorRecord) } -Verifiable
        Mock -CommandName Install-GTRequiredModule -MockWith { param($ModuleNames, $Verbose) } -Verifiable
        Mock -CommandName Initialize-GTGraphConnection -MockWith { param($Scopes, $NewSession) return $true } -Verifiable
        Mock -CommandName Get-MgUser -MockWith { param($UserId, $Property, $ErrorAction) } -Verifiable
        Mock -CommandName Get-MgDevice -MockWith { param($All, $Filter, $ErrorAction) } -Verifiable
        Mock -CommandName Update-MgDevice -MockWith { param($DeviceId, $AccountEnabled, $ErrorAction) } -Verifiable

        # Dot-source the function under test after mocks are in place
        . $functionFile
    }

    BeforeEach {
        # Ensure required external interactions are mocked so tests do not call real Graph modules.
        Mock -CommandName Install-GTRequiredModule -MockWith { param($ModuleNames, $Verbose) }
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true }
        Mock -CommandName Write-PSFMessage -MockWith { param($Level, $Message) } # no-op
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

            # Mock user retrieval
            Mock -CommandName Get-MgUser -MockWith {
                [PSCustomObject]@{ Id = '12345678-1234-1234-1234-123456789abc' }
            } -Verifiable

            # Mock device retrieval with optimized query
            Mock -CommandName Get-MgDevice -MockWith {
                @(
                    [PSCustomObject]@{
                        Id             = "device-id-1"
                        DisplayName    = "Test Device"
                        AccountEnabled = $true
                    }
                )
            } -Verifiable

            Mock -CommandName Update-MgDevice -MockWith { } -Verifiable

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            # Validate that we received an array
            $results.GetType().Name | Should -Be 'Object[]'
            $results.Count | Should -Be 1

            # Entry should have Status = 'Disabled'
            $results[0].Status | Should -Be 'Disabled'
            $results[0].User | Should -Be $upn
            $results[0].DeviceId | Should -Be "device-id-1"
            $results[0].DeviceName | Should -Be "Test Device"

            # Ensure Update-MgDevice was called once
            Assert-MockCalled -CommandName Update-MgDevice -Times 1
        }

        It "handles users with no enabled devices" {
            $upn = 'nodevices@contoso.com'
            $userId = 'a1b2c3d4-e5f6-a7b8-c9d0-e1f2a3b4c5d6'

            Mock -CommandName Get-MgUser -MockWith {
                [PSCustomObject]@{ Id = 'a1b2c3d4-e5f6-a7b8-c9d0-e1f2a3b4c5d6' }
            }

            Mock -CommandName Get-MgDevice -MockWith {
                @()
            } -Verifiable

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.Count | Should -Be 1
            $results[0].Status | Should -Be 'NoDevices'
            $results[0].User | Should -Be $upn
            $results[0].Reason | Should -Match 'No enabled devices'
        }

        It "honors -Force and invokes Update-MgDevice" {
            $upn = 'charlie@contoso.com'
            $userId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

            Mock -CommandName Get-MgUser -MockWith {
                [PSCustomObject]@{ Id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
            }

            Mock -CommandName Get-MgDevice -MockWith {
                @(
                    [PSCustomObject]@{
                        Id             = "device-id-3"
                        DisplayName    = "Test Device"
                        AccountEnabled = $true
                    }
                )
            }

            Mock -CommandName Update-MgDevice -MockWith { } -Verifiable

            $results = Disable-GTUserDevice -UPN $upn -Force -Confirm:$false

            $results.Count | Should -Be 1
            $results[0].Status | Should -Be 'Disabled'
            Assert-MockCalled -CommandName Update-MgDevice -Times 1
        }

        It "returns Failed with HttpStatus 404 when Graph returns a not found error for device operation" {
            $upn = 'user@contoso.com'
            $userId = '11111111-2222-3333-4444-555555555555'

            Mock -CommandName Get-MgUser -MockWith {
                [PSCustomObject]@{ Id = '11111111-2222-3333-4444-555555555555' }
            }

            Mock -CommandName Get-MgDevice -MockWith {
                @(
                    [PSCustomObject]@{
                        Id             = "device-id-404"
                        DisplayName    = "Test Device"
                        AccountEnabled = $true
                    }
                )
            }

            Mock -CommandName Update-MgDevice -MockWith {
                throw [System.Exception]::new('404 Not Found - The device does not exist')
            } -Verifiable

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.Count | Should -Be 1
            $entry = $results[0]
            $entry.Status | Should -Be 'Failed'
            $entry.HttpStatus | Should -Be 404
            $entry.Reason | Should -Match 'could not be processed'
            Assert-MockCalled -CommandName Update-MgDevice -Times 1
        }

        It "returns Failed with HttpStatus 403 when Graph returns insufficient privileges error" {
            $upn = 'user@contoso.com'
            $userId = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'

            Mock -CommandName Get-MgUser -MockWith {
                [PSCustomObject]@{ Id = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' }
            }

            Mock -CommandName Get-MgDevice -MockWith {
                @(
                    [PSCustomObject]@{
                        Id             = "device-id-403"
                        DisplayName    = "Test Device"
                        AccountEnabled = $true
                    }
                )
            }

            Mock -CommandName Update-MgDevice -MockWith {
                throw [System.Exception]::new('403 Insufficient privileges to complete the operation')
            } -Verifiable

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.Count | Should -Be 1
            $entry = $results[0]
            $entry.Status | Should -Be 'Failed'
            $entry.HttpStatus | Should -Be 403
            Assert-MockCalled -CommandName Update-MgDevice -Times 1
        }

        It "returns Failed when user retrieval fails with 404" {
            $upn = 'doesnotexist@contoso.com'

            Mock -CommandName Get-MgUser -MockWith {
                throw [System.Exception]::new('404 Not Found - The user does not exist')
            } -Verifiable

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.Count | Should -Be 1
            $entry = $results[0]
            $entry.Status | Should -Be 'Failed'
            $entry.HttpStatus | Should -Be 404
            $entry.Reason | Should -Match 'could not be processed'
            Assert-MockCalled -CommandName Get-MgUser -Times 1
        }

        It "processes multiple devices for a single user" {
            $upn = 'multidevice@contoso.com'
            $userId = 'fedcba98-7654-3210-fedc-ba9876543210'

            Mock -CommandName Get-MgUser -MockWith {
                [PSCustomObject]@{ Id = 'fedcba98-7654-3210-fedc-ba9876543210' }
            }

            Mock -CommandName Get-MgDevice -MockWith {
                @(
                    [PSCustomObject]@{
                        Id             = "device-1"
                        DisplayName    = "Device device-1"
                        AccountEnabled = $true
                    },
                    [PSCustomObject]@{
                        Id             = "device-2"
                        DisplayName    = "Device device-2"
                        AccountEnabled = $true
                    }
                )
            }

            Mock -CommandName Update-MgDevice -MockWith { }

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.Count | Should -Be 2
            $results[0].Status | Should -Be 'Disabled'
            $results[1].Status | Should -Be 'Disabled'
            Assert-MockCalled -CommandName Update-MgDevice -Times 2
        }
    }
}

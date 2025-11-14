# Pester tests for Disable-GTUserDevice
# Requires Pester 5.x
# Place this file in the repository under: tests/Disable-GTUserDevice.Tests.ps1

Describe "Disable-GTUserDevice" -Tag 'Unit' {
    # Dot-source the function under test. Adjust path if your tests run from a different working directory.
    BeforeAll {
        # Load the validation regex first (required by the function)
        $validationFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'GTValidation.ps1'
        if (Test-Path $validationFile) {
            . $validationFile
        }

        $functionFile = Join-Path $PSScriptRoot '..' 'functions' 'Disable-GTUserDevice.ps1'
        if (-not (Test-Path $functionFile)) {
            Throw "Function file not found: $functionFile"
        }
        . $functionFile

        # Create stub functions for external dependencies AFTER loading the function
        # These will be replaced by mocks in BeforeEach and in individual tests
        function Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function Install-GTRequiredModule { param($ModuleNames) }
        function Initialize-GTGraphConnection { param($Scopes) return $true }
        function Get-MgUserRegisteredDevice { param($UserId, $ErrorAction) }
        function Get-MgUserRegisteredDeviceAsDevice { param($UserId, $DirectoryObjectId, $ErrorAction) }
        function Update-MgDevice { param($DeviceId, $AccountEnabled, $ErrorAction) }
    }

    BeforeEach {
        # Ensure required external interactions are mocked so tests do not call real Graph modules.
        Mock -CommandName Install-GTRequiredModule -MockWith { }
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true }
        Mock -CommandName Write-PSFMessage -MockWith { param($Level,$Message) } # no-op
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

            # Mock device retrieval
            Mock -CommandName Get-MgUserRegisteredDevice -MockWith {
                @(
                    [PSCustomObject]@{ Id = "device-id-1" }
                )
            } -Verifiable

            Mock -CommandName Get-MgUserRegisteredDeviceAsDevice -MockWith {
                [PSCustomObject]@{
                    Id = "device-id-1"
                    DisplayName = "Test Device"
                    AccountEnabled = $true
                }
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

        It "handles users with no registered devices" {
            $upn = 'nodevices@contoso.com'

            Mock -CommandName Get-MgUserRegisteredDevice -MockWith {
                @()
            } -Verifiable

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.Count | Should -Be 1
            $results[0].Status | Should -Be 'NoDevices'
            $results[0].User | Should -Be $upn
            $results[0].Reason | Should -Match 'No registered devices'
        }

        It "handles already disabled devices" {
            $upn = 'user@contoso.com'

            Mock -CommandName Get-MgUserRegisteredDevice -MockWith {
                @([PSCustomObject]@{ Id = "device-id-2" })
            }

            Mock -CommandName Get-MgUserRegisteredDeviceAsDevice -MockWith {
                [PSCustomObject]@{
                    Id = "device-id-2"
                    DisplayName = "Already Disabled Device"
                    AccountEnabled = $false
                }
            }

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.Count | Should -Be 1
            $results[0].Status | Should -Be 'AlreadyDisabled'
            $results[0].DeviceName | Should -Be "Already Disabled Device"
        }

        It "honors -Force and invokes Update-MgDevice" {
            $upn = 'charlie@contoso.com'

            Mock -CommandName Get-MgUserRegisteredDevice -MockWith {
                @([PSCustomObject]@{ Id = "device-id-3" })
            }

            Mock -CommandName Get-MgUserRegisteredDeviceAsDevice -MockWith {
                [PSCustomObject]@{
                    Id = "device-id-3"
                    DisplayName = "Test Device"
                    AccountEnabled = $true
                }
            }

            Mock -CommandName Update-MgDevice -MockWith { } -Verifiable

            $results = Disable-GTUserDevice -UPN $upn -Force -Confirm:$false

            $results.Count | Should -Be 1
            $results[0].Status | Should -Be 'Disabled'
            Assert-MockCalled -CommandName Update-MgDevice -Times 1
        }

        It "returns Failed with HttpStatus 404 when Graph returns a not found error for device operation" {
            $upn = 'user@contoso.com'

            Mock -CommandName Get-MgUserRegisteredDevice -MockWith {
                @([PSCustomObject]@{ Id = "device-id-404" })
            }

            Mock -CommandName Get-MgUserRegisteredDeviceAsDevice -MockWith {
                throw [System.Exception]::new('404 Not Found - The device does not exist')
            } -Verifiable

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.Count | Should -Be 1
            $entry = $results[0]
            $entry.Status | Should -Be 'Failed'
            $entry.HttpStatus | Should -Be 404
            $entry.Reason | Should -Match 'could not be processed'
            Assert-MockCalled -CommandName Get-MgUserRegisteredDeviceAsDevice -Times 1
        }

        It "returns Failed with HttpStatus 403 when Graph returns insufficient privileges error" {
            $upn = 'user@contoso.com'

            Mock -CommandName Get-MgUserRegisteredDevice -MockWith {
                @([PSCustomObject]@{ Id = "device-id-403" })
            }

            Mock -CommandName Get-MgUserRegisteredDeviceAsDevice -MockWith {
                [PSCustomObject]@{
                    Id = "device-id-403"
                    DisplayName = "Test Device"
                    AccountEnabled = $true
                }
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

            Mock -CommandName Get-MgUserRegisteredDevice -MockWith {
                throw [System.Exception]::new('404 Not Found - The user does not exist')
            } -Verifiable

            $results = Disable-GTUserDevice -UPN $upn -Confirm:$false

            $results.Count | Should -Be 1
            $entry = $results[0]
            $entry.Status | Should -Be 'Failed'
            $entry.HttpStatus | Should -Be 404
            $entry.Reason | Should -Match 'could not be processed'
            Assert-MockCalled -CommandName Get-MgUserRegisteredDevice -Times 1
        }

        It "processes multiple devices for a single user" {
            $upn = 'multidevice@contoso.com'

            Mock -CommandName Get-MgUserRegisteredDevice -MockWith {
                @(
                    [PSCustomObject]@{ Id = "device-1" },
                    [PSCustomObject]@{ Id = "device-2" }
                )
            }

            Mock -CommandName Get-MgUserRegisteredDeviceAsDevice -MockWith {
                param($UserId, $DirectoryObjectId)
                [PSCustomObject]@{
                    Id = $DirectoryObjectId
                    DisplayName = "Device $DirectoryObjectId"
                    AccountEnabled = $true
                }
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

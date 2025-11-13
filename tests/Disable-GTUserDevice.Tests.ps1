. "$PSScriptRoot/../functions/Disable-GTUserDevice.ps1"

Describe "Disable-GTUserDevice" {
    BeforeAll {
        # Mock the required modules and functions
        Mock -ModuleName "Microsoft.Graph.Users" -CommandName "Get-MgUserRegisteredDevice" -MockWith {
            @(
                [PSCustomObject]@{
                    Id = "device-id-1"
                }
            )
        }
        Mock -ModuleName "Microsoft.Graph.Users" -CommandName "Get-MgUserRegisteredDeviceAsDevice" -MockWith {
            [PSCustomObject]@{
                Id = "device-id-1"
                DisplayName = "Test Device"
                AccountEnabled = $true
            }
        }
        Mock -ModuleName "Microsoft.Graph.Identity.DirectoryManagement" -CommandName "Update-MgDevice" -MockWith { }
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
}

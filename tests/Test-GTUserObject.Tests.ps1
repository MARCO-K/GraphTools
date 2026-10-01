Describe "Test-GTUserObject" -Tag 'Unit' {
    BeforeAll {
        $validationFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\GTValidation.ps1'
        if (-not (Test-Path $validationFile)) {
            Throw "Validation file not found: $validationFile"
        }
        . $validationFile
    }

    AfterAll {
        Remove-Item Function:\Test-GTUserObject -Force -ErrorAction SilentlyContinue
    }

    Context "Valid User Objects" {
        It "returns true for PSCustomObject with Id and UserPrincipalName" {
            $user = [PSCustomObject]@{
                Id                = '11111111-1111-1111-1111-111111111111'
                UserPrincipalName = 'user@contoso.com'
                DisplayName       = 'Test User'
            }
            Test-GTUserObject -User $user | Should -Be $true
        }

        It "returns true for Hashtable with Id and UserPrincipalName" {
            $user = @{
                Id                = '11111111-1111-1111-1111-111111111111'
                UserPrincipalName = 'user@contoso.com'
            }
            Test-GTUserObject -User $user | Should -Be $true
        }

        It "returns true with -Quiet parameter" {
            $user = [PSCustomObject]@{
                Id                = '11111111-1111-1111-1111-111111111111'
                UserPrincipalName = 'user@contoso.com'
            }
            Test-GTUserObject -User $user -Quiet | Should -Be $true
        }

        It "supports pipeline input" {
            $user = [PSCustomObject]@{
                Id                = '11111111-1111-1111-1111-111111111111'
                UserPrincipalName = 'user@contoso.com'
            }
            $result = $user | Test-GTUserObject
            $result | Should -Be $true
        }
    }

    Context "Invalid User Objects" {
        It "throws when Id is missing without -Quiet" {
            $user = [PSCustomObject]@{
                UserPrincipalName = 'user@contoso.com'
            }
            { Test-GTUserObject -User $user } | Should -Throw "*User object must have 'Id' and 'UserPrincipalName' properties*"
        }

        It "returns false when Id is missing with -Quiet" {
            $user = [PSCustomObject]@{
                UserPrincipalName = 'user@contoso.com'
            }
            $result = Test-GTUserObject -User $user -Quiet
            $result | Should -Be $false
        }

        It "throws when UserPrincipalName is missing without -Quiet" {
            $user = [PSCustomObject]@{
                Id = '11111111-1111-1111-1111-111111111111'
            }
            { Test-GTUserObject -User $user } | Should -Throw "*User object must have 'Id' and 'UserPrincipalName' properties*"
        }

        It "returns false when UserPrincipalName is missing with -Quiet" {
            $user = [PSCustomObject]@{
                Id = '11111111-1111-1111-1111-111111111111'
            }
            $result = Test-GTUserObject -User $user -Quiet
            $result | Should -Be $false
        }

        It "throws when property value is null/empty" {
            $user = [PSCustomObject]@{
                Id                = ''
                UserPrincipalName = 'user@contoso.com'
            }
            { Test-GTUserObject -User $user } | Should -Throw "*User object must have 'Id' and 'UserPrincipalName' properties*"
        }

        It "throws when input is null due to ValidateNotNullOrEmpty" {
            { Test-GTUserObject -User $null } | Should -Throw
        }
    }
}

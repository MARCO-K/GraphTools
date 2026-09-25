# Load dependencies
$validationFile = Join-Path $PSScriptRoot '..\internal\functions\GTValidation.ps1'
if (Test-Path $validationFile)
{
    . $validationFile
}

$errorHelperFile = Join-Path $PSScriptRoot '..\internal\functions\Get-GTGraphErrorDetails.ps1'
if (Test-Path $errorHelperFile)
{
    . $errorHelperFile
}

Describe "Reset-GTUserPassword" {
    BeforeAll {
        # Load dependencies inside BeforeAll
        $validationFile = Join-Path $PSScriptRoot '..\internal\functions\GTValidation.ps1'
        if (Test-Path $validationFile) { . $validationFile }

        $errorHelperFile = Join-Path $PSScriptRoot '..\internal\functions\Get-GTGraphErrorDetails.ps1'
        if (Test-Path $errorHelperFile) { . $errorHelperFile }

        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true }
        function global:New-GTPassword { return 'TempPassword123!' }
        function global:Invoke-GTGraphRequest { param($Method, $Uri, $Body, $ContentType, $ErrorAction) return $null }

        Mock -CommandName Write-PSFMessage -MockWith { }
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true }
        Mock -CommandName New-GTPassword -MockWith { return 'TempPassword123!' }
        Mock -CommandName Invoke-GTGraphRequest -MockWith { return $null }

        # Dot-source the function under test after mocks are registered
        . "$PSScriptRoot/../functions/Reset-GTUserPassword.ps1"
    }

    Context "Parameter Validation" {
        It "should throw an error for an invalid UPN (no @ symbol)" {
            { Reset-GTUserPassword -UPN "invalid-user" } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty local part)" {
            { Reset-GTUserPassword -UPN "@domain.com" } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty domain part)" {
            { Reset-GTUserPassword -UPN "user@" } | Should -Throw
        }
    }

    Context "Password Reset Execution" {
        It "should call Invoke-GTGraphRequest with PATCH method and correct URI" {
            Mock -CommandName Invoke-GTGraphRequest -MockWith { return $null }

            Reset-GTUserPassword -UPN "test@contoso.com" -Confirm:$false

            Should -Invoke -CommandName Invoke-GTGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -eq 'v1.0/users/test@contoso.com'
            }
        }
    }
}

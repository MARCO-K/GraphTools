# Load dependencies
$validationFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'GTValidation.ps1'
if (Test-Path $validationFile)
{
    . $validationFile
}

$errorHelperFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'Get-GTGraphErrorDetails.ps1'
if (Test-Path $errorHelperFile)
{
    . $errorHelperFile
}

Describe "Reset-GTUserPassword" {
    BeforeAll {
        # Use Pester Mocks for external dependencies
        Mock -CommandName Write-PSFMessage -MockWith { } -Verifiable
        Mock -CommandName Install-GTRequiredModule -MockWith { } -Verifiable
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true } -Verifiable
        Mock -CommandName New-GTPassword -MockWith { return 'TempPassword123!' } -Verifiable
        Mock -CommandName Update-MgBetaUser -MockWith { param($UserId, $PasswordProfile, $ErrorAction) } -Verifiable

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
}

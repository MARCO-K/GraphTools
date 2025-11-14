# Load dependencies
$validationFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'GTValidation.ps1'
if (Test-Path $validationFile) {
    . $validationFile
}

$errorHelperFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'Get-GTGraphErrorDetails.ps1'
if (Test-Path $errorHelperFile) {
    . $errorHelperFile
}

. "$PSScriptRoot/../functions/Reset-GTUserPassword.ps1"

Describe "Reset-GTUserPassword" {
    BeforeAll {
        # Create stub functions for external dependencies
        function Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function Install-GTRequiredModule { param($ModuleNames) }
        function Initialize-GTGraphConnection { param($Scopes, $NewSession) return $true }
        function New-GTPassword { return 'TempPassword123!' }
        function Update-MgBetaUser { param($UserId, $PasswordProfile, $ErrorAction) }
        
        # Mock the required modules and functions
        Mock -CommandName Install-GTRequiredModule -MockWith { }
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true }
        Mock -CommandName New-GTPassword -MockWith { return 'TempPassword123!' }
        Mock -CommandName Update-MgBetaUser -MockWith { }
        Mock -CommandName Write-PSFMessage -MockWith { }
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

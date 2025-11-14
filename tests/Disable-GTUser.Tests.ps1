# Pester tests for Disable-GTUser
# Requires Pester 5.x
# Place this file in the repository under: tests/Disable-GTUser.Tests.ps1

Describe "Disable-GTUser" -Tag 'Unit' {
    # Dot-source the function under test. Adjust path if your tests run from a different working directory.
    BeforeAll {
        # Load the validation regex first (required by the function)
        $validationFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'GTValidation.ps1'
        if (Test-Path $validationFile) {
            . $validationFile
        }

        # Load the error handling helper function (required by Disable-GTUser)
        $errorHelperFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'Get-GTGraphErrorDetails.ps1'
        if (Test-Path $errorHelperFile) {
            . $errorHelperFile
        }

        $functionFile = Join-Path $PSScriptRoot '..' 'functions' 'Disable-GTUser.ps1'
        if (-not (Test-Path $functionFile)) {
            Throw "Function file not found: $functionFile"
        }
        . $functionFile

        # Create stub functions for external dependencies AFTER loading the function
        # These will be replaced by mocks in BeforeEach and in individual tests
        function Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function Install-GTRequiredModule { param($ModuleNames) }
        function Initialize-GTGraphConnection { param($Scopes) return $true }
        function Update-MgBetaUser { param($UserId, $AccountEnabled) }
    }

    BeforeEach {
        # Ensure required external interactions are mocked so tests do not call real Graph modules.
        Mock -CommandName Install-GTRequiredModule -MockWith { }
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true }
        Mock -CommandName Write-PSFMessage -MockWith { param($Level,$Message) } # no-op
    }

    It "disables multiple users and returns a single array of Disabled results" {
        $users = @('alice@contoso.com','bob@contoso.com')

        # Track calls to Update-MgBetaUser and simulate success
        Mock -CommandName Update-MgBetaUser -MockWith {
            param($UserId, $AccountEnabled)
            # simulate API work, no exception => success
        } -Verifiable

        $results = Disable-GTUser -UPN $users

        # Validate that we received an array with two items
        $results.GetType().Name | Should -Be 'Object[]'
        $results.Count | Should -Be $users.Count

        # All entries should have Status = 'Disabled'
        ($results | Where-Object { $_.Status -ne 'Disabled' }).Count | Should -Be 0

        # Ensure Update-MgBetaUser was called once per user
        Assert-MockCalled -CommandName Update-MgBetaUser -Times $users.Count
    }

    It "honors -Force and invokes Update-MgBetaUser" {
        $users = @('charlie@contoso.com')

        Mock -CommandName Update-MgBetaUser -MockWith { } -Verifiable

        $results = Disable-GTUser -UPN $users -Force

        $results.Count | Should -Be 1
        $results[0].Status | Should -Be 'Disabled'
        Assert-MockCalled -CommandName Update-MgBetaUser -Times 1
    }

    It "returns Failed with HttpStatus 404 when Graph returns a not found error" {
        $users = @('doesnotexist@contoso.com')

        # Simulate Update-MgBetaUser throwing an exception that contains '404' / 'not found'
        Mock -CommandName Update-MgBetaUser -MockWith {
            throw [System.Exception]::new('404 Not Found - The resource does not exist')
        } -Verifiable

        $results = Disable-GTUser -UPN $users

        $results.Count | Should -Be 1
        $entry = $results[0]
        $entry.Status | Should -Be 'Failed'
        $entry.HttpStatus | Should -Be 404
        # For security, 404 errors return generic message to prevent enumeration
        $entry.Reason.ToLower() | Should -Match 'could not be processed'
        Assert-MockCalled -CommandName Update-MgBetaUser -Times 1
    }

    It "returns an empty array when called with empty pipeline input" {
        Mock -CommandName Update-MgBetaUser -MockWith { }

        $results = @() | Disable-GTUser
        $results | Should -BeOfType 'object[]'
        $results.Count | Should -Be 0
    }
}
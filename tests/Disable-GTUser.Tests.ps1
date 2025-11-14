# Pester tests for Disable-GTUser
# Requires Pester 5.x
# Place this file in the repository under: tests/Disable-GTUser.Tests.ps1

Describe "Disable-GTUser" -Tag 'Unit' {
    # Dot-source the function under test. Adjust path if your tests run from a different working directory.
    BeforeAll {
        $functionFile = Join-Path $PSScriptRoot '..' 'functions' 'Disable-GTUser.ps1'
        if (-not (Test-Path $functionFile)) {
            Throw "Function file not found: $functionFile"
        }
        . $functionFile
    }

    BeforeEach {
        # Ensure required external interactions are mocked so tests do not call real Graph modules.
        Mock -CommandName Install-GTRequiredModule -MockWith { return $true }
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
        $results | Should -BeOfType 'object[]'
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
        # Reason should mention 'not found' (case-insensitive)
        $entry.Reason.ToLower() | Should -Match 'not found'
        Assert-MockCalled -CommandName Update-MgBetaUser -Times 1
    }

    It "returns an empty array when no users are passed (defensive)" {
        # The function requires UPN parameter Mandatory = $true, but test defensively by capturing output when called with zero-length array
        Mock -CommandName Update-MgBetaUser -MockWith { } -Verifiable

        $results = Disable-GTUser -UPN @()
        # Expect an empty array
        $results | Should -BeOfType 'object[]'
        $results.Count | Should -Be 0
    }
}

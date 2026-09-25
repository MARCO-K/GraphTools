Describe "Get-GTRecentUser" {
    BeforeAll {
        $validationFile = Join-Path $PSScriptRoot '..\internal\functions\GTValidation.ps1'
        if (Test-Path $validationFile) { . $validationFile }

        # Define stubs for dependencies to ensure Mock works
        function global:Install-GTRequiredModule {}
        function global:Initialize-GTGraphConnection { return $true }
        function global:Test-GTGraphScopes { return $true }
        function global:Write-PSFMessage {}
        function global:Get-GTGraphErrorDetails {}
        function global:Invoke-GTGraphRequest { param($Method, $Uri, $Body, $ContentType, $ErrorAction, [switch]$All) return $null }
        function global:Invoke-GTGraphPagedRequest { param($Uri, $Headers) return @() }

        # Use Pester Mocks for dependencies
        Mock -CommandName Install-GTRequiredModule -MockWith {} -Verifiable
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true } -Verifiable
        Mock -CommandName Test-GTGraphScopes -MockWith { return $true } -Verifiable
        Mock -CommandName Write-PSFMessage -MockWith {} -Verifiable
        Mock -CommandName Get-GTGraphErrorDetails -MockWith {} -Verifiable

        $functionPath = "$PSScriptRoot/../functions/Get-GTRecentUser.ps1"
        if (Test-Path $functionPath) { . $functionPath } else { Throw "Function file not found: $functionPath" }
    }

    Context "Parameter Validation" {
        It "should throw an error for an invalid UPN (no @ symbol)" {
            { Get-GTRecentUser -UserPrincipalName "invalid-user" } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty local part)" {
            { Get-GTRecentUser -UserPrincipalName "@domain.com" } | Should -Throw
        }

        It "should throw an error for an invalid UPN (empty domain part)" {
            { Get-GTRecentUser -UserPrincipalName "user@" } | Should -Throw
        }
    }
}
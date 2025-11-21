Describe "Get-GTServicePrincipalReport" {
    BeforeAll {
        # 1. Mock Internal Helpers
        function Install-GTRequiredModule {}
        function Initialize-GTGraphConnection { return $true }
        function Test-GTGraphScopes { return $true }
        function Write-PSFMessage {}
        
        # 2. Mock Error Helper - TRANSPARENT MODE
        # We pass the REAL exception message through. 
        # If the test fails, the error message will now say "Stub Failed: Parameter 'x' not found" 
        # instead of just "Mock Error".
        function Get-GTGraphErrorDetails
        { 
            param($Exception)
            return [PSCustomObject]@{ 
                LogLevel     = 'Error'
                Reason       = "Stub Failed: $($Exception.Message)"
                ErrorMessage = $Exception.Message 
            } 
        }

        # 3. Define a GLOBAL Stub for the Graph Cmdlet
        # Using 'global:' ensures this function shadows any real Cmdlets loaded in the session.
        # ValueFromRemainingArguments = $true accepts any splatted parameters (Filter, Property, etc.)
        function global:Get-MgBetaServicePrincipal
        { 
            [CmdletBinding()]
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                $Any
            )
            return @() 
        }

        # 4. Setup Pester Mocks
        Mock -CommandName Install-GTRequiredModule -MockWith {} -Verifiable
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true } -Verifiable
        Mock -CommandName Test-GTGraphScopes -MockWith { return $true } -Verifiable
        
        # Load the function under test
        . "$PSScriptRoot/../functions/Get-GTServicePrincipalReport.ps1"
    }

    # Cleanup the global stub to avoid affecting other tests
    AfterAll {
        Remove-Item Function:\global:Get-MgBetaServicePrincipal -ErrorAction SilentlyContinue
    }

    Context "Parameter Sets" {
        It "should accept AppId parameter" {
            { Get-GTServicePrincipalReport -AppId "test-app-id" } | Should -Not -Throw
        }

        It "should accept DisplayName parameter" {
            { Get-GTServicePrincipalReport -DisplayName "TestApp" } | Should -Not -Throw
        }
    }

    Context "Switch Parameters" {
        It "should accept IncludeSignInActivity switch" {
            { Get-GTServicePrincipalReport -IncludeSignInActivity } | Should -Not -Throw
        }

        It "should accept IncludeCredentials switch" {
            { Get-GTServicePrincipalReport -IncludeCredentials } | Should -Not -Throw
        }

        It "should accept ExpandOwners switch" {
            { Get-GTServicePrincipalReport -ExpandOwners } | Should -Not -Throw
        }
    }
}
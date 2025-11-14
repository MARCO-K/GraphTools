Describe "Remove-GTUserEnterpriseAppOwnership" {
    BeforeAll {
        # Mock PSFramework logging
        function Write-PSFMessage { }
        
        # Load the error handling helper function (required by Remove-GTUserEnterpriseAppOwnership)
        $errorHelperFile = Join-Path $PSScriptRoot '..' 'internal' 'functions' 'Get-GTGraphErrorDetails.ps1'
        if (Test-Path $errorHelperFile) {
            . $errorHelperFile
        }
        
        # Import the internal function for testing
        . "$PSScriptRoot/../internal/functions/Remove-GTUserEnterpriseAppOwnership.ps1"
    }
    
    Context "Parameter Validation" {
        It "should reject a user object without Id property" {
            $invalidUser = [PSCustomObject]@{
                UserPrincipalName = 'test@contoso.com'
            }
            $outputBase = @{ UserPrincipalName = 'test@contoso.com' }
            $results = [System.Collections.Generic.List[PSObject]]::new()
            
            { Remove-GTUserEnterpriseAppOwnership -User $invalidUser -OutputBase $outputBase -Results $results } | Should -Throw
        }
        
        It "should reject a user object without UserPrincipalName property" {
            $invalidUser = [PSCustomObject]@{
                Id = 'test-id-123'
            }
            $outputBase = @{ UserPrincipalName = 'test@contoso.com' }
            $results = [System.Collections.Generic.List[PSObject]]::new()
            
            { Remove-GTUserEnterpriseAppOwnership -User $invalidUser -OutputBase $outputBase -Results $results } | Should -Throw
        }
    }
}

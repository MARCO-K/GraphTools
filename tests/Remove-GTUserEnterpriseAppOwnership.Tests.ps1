. "$PSScriptRoot/../internal/functions/Remove-GTUserEnterpriseAppOwnership.ps1"

Describe "Remove-GTUserEnterpriseAppOwnership" {
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

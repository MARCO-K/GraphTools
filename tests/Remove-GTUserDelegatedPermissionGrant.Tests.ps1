Describe "Remove-GTUserDelegatedPermissionGrant" {
    BeforeAll {
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Test-GTGuid { param($InputObject, [switch]$Quiet) return $true }
        function global:Invoke-GTGraphPagedRequest { param($Uri) }
        function global:Invoke-GTGraphRequest { param($Uri, $Method = 'GET', $Body, $Headers, $ContentType, [switch]$All, [int]$MaxRetries, [int]$RetryBaseDelaySeconds, $Token, [switch]$Raw, $ErrorAction) }
        function global:Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ HttpStatus = 500; LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error' } }

        . "$PSScriptRoot/../internal/functions/GTValidation.ps1"
        . "$PSScriptRoot/../internal/functions/Remove-GTUserDelegatedPermissionGrant.ps1"
    }

    AfterAll {
        Remove-Item Function:\global:Write-PSFMessage -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Test-GTGuid -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Invoke-GTGraphPagedRequest -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Invoke-GTGraphRequest -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Get-GTGraphErrorDetails -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-GTUserObject -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-GTUserDelegatedPermissionGrant -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Remove-GTUserDelegatedPermissionGrants -Force -ErrorAction SilentlyContinue
    }

    Context "Alias Support" {
        It "resolves legacy Remove-GTUserDelegatedPermissionGrants alias to Remove-GTUserDelegatedPermissionGrant" {
            (Get-Command Remove-GTUserDelegatedPermissionGrants).ResolvedCommandName | Should -Be 'Remove-GTUserDelegatedPermissionGrant'
        }
    }

    Context "Service Principal Caching and Deletion" {
        It "should cache service principal display name lookups per clientId" {
            $user = [PSCustomObject]@{
                Id                = '11111111-1111-1111-1111-111111111111'
                UserPrincipalName = 'user@contoso.com'
            }
            $outputBase = @{
                UPN       = 'user@contoso.com'
                UserId    = $user.Id
                Timestamp = [datetime]::UtcNow
            }
            $results = [System.Collections.Generic.List[PSObject]]::new()

            Mock -CommandName Invoke-GTGraphPagedRequest -MockWith {
                return @(
                    [PSCustomObject]@{ id = 'grant-1'; clientId = 'client-aaa'; scope = 'User.Read' },
                    [PSCustomObject]@{ id = 'grant-2'; clientId = 'client-aaa'; scope = 'Mail.Read' }
                )
            }
            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                param($Uri, $Method)
                if ($Method -eq 'GET' -and $Uri -like 'v1.0/servicePrincipals/client-aaa*') {
                    return [PSCustomObject]@{ displayName = 'CachedApp' }
                }
                return $null
            }

            Remove-GTUserDelegatedPermissionGrant -User $user -OutputBase $outputBase -Results $results -Confirm:$false

            # SP lookup should only be invoked once for client-aaa due to caching
            Assert-MockCalled -CommandName Invoke-GTGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like 'v1.0/servicePrincipals/client-aaa*'
            }

            # DELETE should be invoked for both grants
            Assert-MockCalled -CommandName Invoke-GTGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'v1.0/oauth2PermissionGrants/grant-1'
            }
            Assert-MockCalled -CommandName Invoke-GTGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'v1.0/oauth2PermissionGrants/grant-2'
            }

            $results.Count | Should -Be 2
            $results[0].ResourceName | Should -Be 'CachedApp'
            $results[1].ResourceName | Should -Be 'CachedApp'
        }

        It "should safely handle missing clientId by falling back to grant id" {
            $user = [PSCustomObject]@{
                Id                = '11111111-1111-1111-1111-111111111111'
                UserPrincipalName = 'user@contoso.com'
            }
            $outputBase = @{
                UPN       = 'user@contoso.com'
                UserId    = $user.Id
                Timestamp = [datetime]::UtcNow
            }
            $results = [System.Collections.Generic.List[PSObject]]::new()

            Mock -CommandName Invoke-GTGraphPagedRequest -MockWith {
                return @(
                    [PSCustomObject]@{ id = 'grant-missing-client'; clientId = ''; scope = 'User.Read' }
                )
            }
            Mock -CommandName Invoke-GTGraphRequest -MockWith { return $null }

            Remove-GTUserDelegatedPermissionGrant -User $user -OutputBase $outputBase -Results $results -Confirm:$false

            # Should not call GET for service principal
            Assert-MockCalled -CommandName Invoke-GTGraphRequest -Times 0 -ParameterFilter {
                $Method -eq 'GET'
            }

            $results.Count | Should -Be 1
            $results[0].ResourceName | Should -Be 'App-grant-missing-client'
        }
    }
}

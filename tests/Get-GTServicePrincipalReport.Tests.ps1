Describe "Get-GTServicePrincipalReport" {
    BeforeAll {
        # 1. Mock Internal Helpers
        function global:Install-GTRequiredModule {}
        function global:Initialize-GTGraphConnection { return $true }
        function global:Test-GTGraphScopes { return $true }
        function global:Write-PSFMessage {}
        function global:Invoke-GTGraphPagedRequest { param($Uri, $Headers) return @() }
        
        # 2. Mock Error Helper
        function global:Get-GTGraphErrorDetails
        { 
            param($Exception)
            return [PSCustomObject]@{ 
                LogLevel     = 'Error'
                Reason       = "Stub Failed: $($Exception.Message)"
                ErrorMessage = $Exception.Message 
            } 
        }

        # 3. Setup Pester Mocks
        Mock -CommandName Install-GTRequiredModule -MockWith {} -Verifiable
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true } -Verifiable
        Mock -CommandName Test-GTGraphScopes -MockWith { return $true } -Verifiable
        Mock -CommandName Invoke-GTGraphPagedRequest -MockWith { return @() }
        
        $formatFile = "$PSScriptRoot/../internal/functions/Format-ODataDateTime.ps1"
        if (Test-Path $formatFile) { . $formatFile }
        
        # Load the function under test
        . "$PSScriptRoot/../functions/Get-GTServicePrincipalReport.ps1"
    }

    AfterAll {
        Remove-Item Function:\Get-GTServicePrincipalReport -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Format-ODataDateTime -Force -ErrorAction SilentlyContinue
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

    Context "Credential Expiry Formatting" {
        It "formats key and password credential expiry dates using Format-ODataDateTime" {
            $testExpiry = [DateTime]::new(2027, 5, 20, 14, 30, 0, [System.DateTimeKind]::Utc)
            $mockSp = [PSCustomObject]@{
                id = 'sp-123'
                appId = 'app-123'
                displayName = 'Test SP'
                servicePrincipalType = 'Application'
                accountEnabled = $true
                keyCredentials = @(
                    [PSCustomObject]@{ endDateTime = $testExpiry }
                )
                passwordCredentials = @(
                    [PSCustomObject]@{ endDateTime = $testExpiry }
                )
            }
            Mock -CommandName Invoke-GTGraphPagedRequest -MockWith { return @($mockSp) }

            $result = Get-GTServicePrincipalReport -AppId 'app-123' -IncludeCredentials
            $result.KeyCredentialExpiryDates | Should -Be "2027-05-20T14:30:00Z"
            $result.PasswordCredentialExpiryDates | Should -Be "2027-05-20T14:30:00Z"
        }
    }
}
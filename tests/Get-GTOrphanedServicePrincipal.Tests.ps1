Describe "Get-GTOrphanedServicePrincipal" {
    BeforeAll {
        # Define dependencies in the Describe scope
        function Install-GTRequiredModule {}
        function Initialize-GTGraphConnection {}
        function Write-PSFMessage {}
        function Stop-PSFFunction {}
        function Get-GTGraphErrorDetails {}

        # Dot-source the function in the Describe scope
        . "$PSScriptRoot/../functions/Get-GTOrphanedServicePrincipal.ps1"
    }

    Context "Function Execution" {
        It "should not throw when properly configured" {
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return @() }
            { Get-GTOrphanedServicePrincipal } | Should -Not -Throw
        }
    }

    Context "Logic Verification" {
        It "should identify SPs with no owners" {
            $mockSP = [PSCustomObject]@{
                Id             = "1"
                AppId          = "app1"
                DisplayName    = "No Owner SP"
                Owners         = @()
                AccountEnabled = $true
            }
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return $mockSP }
            
            $result = Get-GTOrphanedServicePrincipal
            $result.Count | Should -Be 1
            $result[0].Issues | Should -Match "NoOwners"
        }

        It "should identify SPs with all owners disabled" {
            $mockOwner = [PSCustomObject]@{
                Id                   = "o1"
                AccountEnabled       = $false
                AdditionalProperties = @{ accountEnabled = $false }
            }
            $mockSP = [PSCustomObject]@{
                Id             = "2"
                AppId          = "app2"
                DisplayName    = "Disabled Owner SP"
                Owners         = @($mockOwner)
                AccountEnabled = $true
            }
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return $mockSP }

            $result = Get-GTOrphanedServicePrincipal
            $result.Count | Should -Be 1
            $result[0].Issues | Should -Match "AllOwnersDisabled"
        }

        It "should identify expired credentials when switch is on" {
            $expiredDate = (Get-Date).AddDays(-1)
            $mockSP = [PSCustomObject]@{
                Id                  = "3"
                AppId               = "app3"
                DisplayName         = "Expired Creds SP"
                Owners              = @(@{AccountEnabled = $true; AdditionalProperties = @{accountEnabled = $true } })
                AccountEnabled      = $true
                PasswordCredentials = @(@{EndDateTime = $expiredDate })
            }
            Mock -CommandName "Get-MgBetaServicePrincipal" -MockWith { return $mockSP }

            $result = Get-GTOrphanedServicePrincipal -CheckExpiredCredentials
            $result.Count | Should -Be 1
            $result[0].Issues | Should -Match "ExpiredCredentials"
        }
    }
}

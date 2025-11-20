Describe "Get-GTOrphanedGroup" {
    BeforeAll {
        # Define dependencies in the Describe scope
        function Install-GTRequiredModule {}
        function Initialize-GTGraphConnection {}
        function Write-PSFMessage {}
        function Stop-PSFFunction {}
        function Get-GTGraphErrorDetails {}

        # Dot-source the function in the Describe scope
        . "$PSScriptRoot/../functions/Get-GTOrphanedGroup.ps1"
    }

    Context "Function Execution" {
        It "should not throw when properly configured" {
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return @() }
            { Get-GTOrphanedGroup } | Should -Not -Throw
        }
    }

    Context "Parameter Handling" {
        It "should accept NewSession switch" {
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return @() }
            { Get-GTOrphanedGroup -NewSession } | Should -Not -Throw
        }

        It "should accept Scope parameter" {
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return @() }
            { Get-GTOrphanedGroup -Scope 'Group.Read.All' } | Should -Not -Throw
        }
    }

    Context "Logic Verification" {
        It "should identify groups with no owners" {
            $mockGroup = [PSCustomObject]@{
                Id              = "1"
                DisplayName     = "No Owner Group"
                Owners          = @()
                Members         = @(@{Id = "m1" })
                DeletedDateTime = $null
            }
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return $mockGroup }
            
            $result = Get-GTOrphanedGroup
            $result.Count | Should -Be 1
            $result[0].OrphanReason | Should -Match "NoOwners"
        }

        It "should identify groups with all owners disabled" {
            $mockOwner = [PSCustomObject]@{
                Id                   = "o1"
                AccountEnabled       = $false
                AdditionalProperties = @{ accountEnabled = $false }
            }
            $mockGroup = [PSCustomObject]@{
                Id              = "2"
                DisplayName     = "Disabled Owner Group"
                Owners          = @($mockOwner)
                Members         = @(@{Id = "m1" })
                DeletedDateTime = $null
            }
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return $mockGroup }

            $result = Get-GTOrphanedGroup
            $result.Count | Should -Be 1
            $result[0].OrphanReason | Should -Match "AllOwnersDisabled"
        }

        It "should identify empty groups" {
            $mockOwner = [PSCustomObject]@{
                Id                   = "o1"
                AccountEnabled       = $true
                AdditionalProperties = @{ accountEnabled = $true }
            }
            $mockGroup = [PSCustomObject]@{
                Id              = "3"
                DisplayName     = "Empty Group"
                Owners          = @($mockOwner)
                Members         = @()
                DeletedDateTime = $null
            }
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return $mockGroup }

            $result = Get-GTOrphanedGroup
            $result.Count | Should -Be 1
            $result[0].OrphanReason | Should -Match "EmptyGroup"
        }
    }
}

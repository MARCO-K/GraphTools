Describe "Get-GTOrphanedGroup" {
    BeforeAll {
        # Use Pester Mocks for dependencies
        Mock -CommandName Install-GTRequiredModule -MockWith { } -Verifiable
        Mock -CommandName Initialize-GTGraphConnection -MockWith { } -Verifiable
        Mock -CommandName Write-PSFMessage -MockWith { } -Verifiable
        Mock -CommandName Stop-PSFFunction -MockWith { } -Verifiable
        Mock -CommandName Get-GTGraphErrorDetails -MockWith { } -Verifiable

        # Dot-source the function in the Describe scope
        . "$PSScriptRoot/../functions/Get-GTOrphanedGroup.ps1"
        
        # Now add Get-MgBetaGroup stub AFTER the function is loaded
        function Get-MgBetaGroup { param($All, $Property, $ExpandProperty, $ErrorAction) return @() }
    }

    Context "Function Execution" {
        BeforeEach {
            # Mock Get-MgBetaGroup before each test in this context
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return @() }
        }
        It "should not throw when properly configured" {
            { Get-GTOrphanedGroup } | Should -Not -Throw
        }
    }

    Context "Parameter Handling" {
        BeforeEach {
            # Mock Get-MgBetaGroup before each test in this context
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return @() }
        }

        It "should accept NewSession switch" {
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

            $result = Get-GTOrphanedGroup -CheckDisabledOwners
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

            $result = Get-GTOrphanedGroup -CheckEmpty
            $result.Count | Should -Be 1
            $result[0].OrphanReason | Should -Match "EmptyGroup"
        }

        It "should skip soft-deleted groups" {
            $mockGroup = @([PSCustomObject]@{
                    Id              = "4"
                    DisplayName     = "Deleted Group"
                    Owners          = @()
                    Members         = @()
                    DeletedDateTime = (Get-Date)
                    MailEnabled     = $false
                    SecurityEnabled = $true
                    GroupTypes      = @()
                    Visibility      = "Private"
                    CreatedDateTime = (Get-Date)
                })
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return $mockGroup }

            $result = Get-GTOrphanedGroup
            $result.Count | Should -Be 0
        }

        It "should return no results for groups with owners" {
            $mockOwner = [PSCustomObject]@{
                Id                   = "o1"
                AccountEnabled       = $true
                AdditionalProperties = @{ accountEnabled = $true }
            }
            $mockGroup = @([PSCustomObject]@{
                    Id              = "5"
                    DisplayName     = "Normal Group"
                    Owners          = @($mockOwner)
                    Members         = @(@{Id = "m1" })
                    DeletedDateTime = $null
                    MailEnabled     = $false
                    SecurityEnabled = $true
                    GroupTypes      = @()
                    Visibility      = "Private"
                    CreatedDateTime = (Get-Date)
                })
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return $mockGroup }

            $result = Get-GTOrphanedGroup
            $result.Count | Should -Be 0
        }
    }
}

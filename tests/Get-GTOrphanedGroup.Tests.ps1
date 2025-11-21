Describe "Get-GTOrphanedGroup" {
    BeforeAll {
        # Define stub functions FIRST
        function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function Get-GTGraphErrorDetails { param($Exception, $ResourceType) return @{ LogLevel = 'Error'; Reason = 'Mock error' } }
        function Get-MgBetaGroup { param($All, $Property, $ExpandProperty, $ErrorAction) return @() }

        # Dot-source the function AFTER stubs
        . "$PSScriptRoot/../functions/Get-GTOrphanedGroup.ps1"
    }

    BeforeEach {
        # Mock Get-MgBetaGroup before each test
        Mock -CommandName "Get-MgBetaGroup" -MockWith { return @() }
    }

    Context "Function Execution" {
        It "should not throw when properly configured" {
            { Get-GTOrphanedGroup } | Should -Not -Throw
        }
    }

    Context "Parameter Handling" {
        It "should accept NewSession switch" {
            { Get-GTOrphanedGroup -NewSession } | Should -Not -Throw
        }

        It "should accept CheckEmpty switch" {
            { Get-GTOrphanedGroup -CheckEmpty } | Should -Not -Throw
        }

        It "should accept CheckDisabledOwners switch" {
            { Get-GTOrphanedGroup -CheckDisabledOwners } | Should -Not -Throw
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
                MailEnabled     = $false
                SecurityEnabled = $true
                GroupTypes      = @()
                Visibility      = "Private"
                CreatedDateTime = (Get-Date)
            }
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return $mockGroup }
            
            $result = Get-GTOrphanedGroup
            $result.Count | Should -Be 1
            $result[0].OrphanReason | Should -Match "NoOwners"
        }

        It "should identify groups with all owners disabled when CheckDisabledOwners is used" {
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
                MailEnabled     = $false
                SecurityEnabled = $true
                GroupTypes      = @()
                Visibility      = "Private"
                CreatedDateTime = (Get-Date)
            }
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return $mockGroup }

            $result = Get-GTOrphanedGroup -CheckDisabledOwners
            $result.Count | Should -Be 1
            $result[0].OrphanReason | Should -Match "AllOwnersDisabled"
        }

        It "should identify empty groups when CheckEmpty is used" {
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
                MailEnabled     = $false
                SecurityEnabled = $true
                GroupTypes      = @()
                Visibility      = "Private"
                CreatedDateTime = (Get-Date)
            }
            Mock -CommandName "Get-MgBetaGroup" -MockWith { return $mockGroup }

            $result = Get-GTOrphanedGroup -CheckEmpty
            $result.Count | Should -Be 1
            $result[0].OrphanReason | Should -Match "EmptyGroup"
        }
    }
}

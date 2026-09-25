Describe "Get-GTOrphanedGroup" {
    BeforeAll {
        function global:Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function global:Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession) return $true }
        function global:Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Stop-PSFFunction { param($Message, $ErrorRecord, [switch]$EnableException) throw $Message }
        function global:Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } }
        function global:Invoke-GTGraphPagedRequest { param($Uri, [switch]$All) return @() }

        # Dot-source the function in the Describe scope
        . "$PSScriptRoot/../functions/Get-GTOrphanedGroup.ps1"
    }

    Context "Function Execution" {
        It "should not throw when properly configured" {
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @() }
            { Get-GTOrphanedGroup } | Should -Not -Throw
        }
    }

    Context "Parameter Handling" {
        It "should accept NewSession switch" {
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @() }
            { Get-GTOrphanedGroup -NewSession } | Should -Not -Throw
        }

        It "should accept CheckEmpty switch" {
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @() }
            { Get-GTOrphanedGroup -CheckEmpty } | Should -Not -Throw
        }

        It "should accept CheckDisabledOwners switch" {
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return @() }
            { Get-GTOrphanedGroup -CheckDisabledOwners } | Should -Not -Throw
        }
    }

    Context "Logic Verification" {
        It "should identify groups with no owners" {
            $mockGroup = @([PSCustomObject]@{
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
                })
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return $mockGroup }
            
            $result = Get-GTOrphanedGroup
            @($result).Count | Should -Be 1
            $result[0].OrphanReason | Should -Match "NoOwners"
        }

        It "should identify groups with all owners disabled when -CheckDisabledOwners is used" {
            $mockOwner = [PSCustomObject]@{
                Id                   = "o1"
                AccountEnabled       = $false
                AdditionalProperties = @{ accountEnabled = $false }
            }
            $mockGroup = @([PSCustomObject]@{
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
                })
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return $mockGroup }

            $result = Get-GTOrphanedGroup -CheckDisabledOwners
            @($result).Count | Should -Be 1
            $result[0].OrphanReason | Should -Match "AllOwnersDisabled"
        }

        It "should identify empty groups when -CheckEmpty is used" {
            $mockOwner = [PSCustomObject]@{
                Id                   = "o1"
                AccountEnabled       = $true
                AdditionalProperties = @{ accountEnabled = $true }
            }
            $mockGroup = @([PSCustomObject]@{
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
                })
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return $mockGroup }

            $result = Get-GTOrphanedGroup -CheckEmpty
            @($result).Count | Should -Be 1
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
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return $mockGroup }

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
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return $mockGroup }

            $result = Get-GTOrphanedGroup
            $result.Count | Should -Be 0
        }
    }
}

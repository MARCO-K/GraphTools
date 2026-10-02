Describe "Remove-GTExpiredInvite" {
    BeforeAll {
        function global:Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function global:Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Stop-PSFFunction { param($Message, $ErrorRecord, [switch]$EnableException) throw $Message }
        function global:Get-GTGuestUserReport { param([switch]$PendingOnly, [int]$DaysSinceCreation) }
        function global:Invoke-GTGraphRequest { param($Uri, $Method = 'GET', $Body, $Headers, $ContentType, [switch]$All, [int]$MaxRetries, [int]$RetryBaseDelaySeconds, $Token, [switch]$Raw, $ErrorAction) return @{} }

        . "$PSScriptRoot/../functions/Remove-GTExpiredInvite.ps1"
    }

    AfterAll {
        Remove-Item Function:\Install-GTRequiredModule -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Initialize-GTGraphConnection -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Write-PSFMessage -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Stop-PSFFunction -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-GTGuestUserReport -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-GTGraphRequest -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-GTExpiredInvite -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Remove-GTExpiredInvites -Force -ErrorAction SilentlyContinue
    }

    Context "Alias Support" {
        It "resolves the legacy Remove-GTExpiredInvites alias to Remove-GTExpiredInvite" {
            (Get-Command Remove-GTExpiredInvites).ResolvedCommandName | Should -Be 'Remove-GTExpiredInvite'
        }
    }

    Context "Execution" {
        BeforeEach {
            Mock -CommandName Get-GTGuestUserReport -MockWith { 
                return @(
                    [PSCustomObject]@{
                        Id                = "1"
                        DisplayName       = "ExpiredUser"
                        UserPrincipalName = "expired@test.com"
                    }
                )
            }
            Mock -CommandName Invoke-GTGraphRequest -MockWith { }
        }

        It "should call Invoke-GTGraphRequest DELETE for expired users when Force is specified" {
            Remove-GTExpiredInvite -DaysOlderThan 30 -Force

            Assert-MockCalled -CommandName "Invoke-GTGraphRequest" -Times 1 -ParameterFilter {
                $Method -eq "DELETE" -and $Uri -eq "v1.0/users/1"
            }
        }

        It "should not call Invoke-GTGraphRequest DELETE when WhatIf is specified, even with Force" {
            Remove-GTExpiredInvite -DaysOlderThan 30 -Force -WhatIf

            Assert-MockCalled -CommandName "Invoke-GTGraphRequest" -Times 0
        }

        It "should emit non-terminating error and continue processing remaining users if one deletion fails" {
            Mock -CommandName Get-GTGuestUserReport -MockWith {
                return @(
                    [PSCustomObject]@{ Id = "1"; DisplayName = "User1"; UserPrincipalName = "user1@test.com" },
                    [PSCustomObject]@{ Id = "2"; DisplayName = "User2"; UserPrincipalName = "user2@test.com" }
                )
            }
            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                param($Method, $Uri)
                if ($Uri -eq 'v1.0/users/1') {
                    throw "Graph 403 Forbidden"
                }
            }

            $invErrors = $null
            Remove-GTExpiredInvite -DaysOlderThan 30 -Force -ErrorVariable invErrors -ErrorAction SilentlyContinue

            $userError = $invErrors | Where-Object { $_.FullyQualifiedErrorId -like 'FailedToRemoveGuestUser*' }
            $userError | Should -Not -BeNullOrEmpty
            Assert-MockCalled -CommandName "Invoke-GTGraphRequest" -Times 2
        }

        It "should halt on error when ErrorAction Stop is specified" {
            Mock -CommandName Get-GTGuestUserReport -MockWith {
                return @(
                    [PSCustomObject]@{ Id = "1"; DisplayName = "User1"; UserPrincipalName = "user1@test.com" },
                    [PSCustomObject]@{ Id = "2"; DisplayName = "User2"; UserPrincipalName = "user2@test.com" }
                )
            }
            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                param($Method, $Uri)
                if ($Uri -eq 'v1.0/users/1') {
                    throw "Graph 403 Forbidden"
                }
            }

            { Remove-GTExpiredInvite -DaysOlderThan 30 -Force -ErrorAction Stop } | Should -Throw
        }
    }
}

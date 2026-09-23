Describe "Remove-GTExpiredInvites" {
    BeforeAll {
        function global:Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function global:Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Stop-PSFFunction { param($Message, $ErrorRecord, [switch]$EnableException) throw $Message }
        function global:Get-GTGuestUserReport { param([switch]$PendingOnly, [int]$DaysSinceCreation) }
        function global:Invoke-GTGraphRequest { param($Uri, $Method = 'GET', $Body, $Headers, $ContentType, [switch]$All, [int]$MaxRetries, [int]$RetryBaseDelaySeconds, $Token, [switch]$Raw, $ErrorAction) return @{} }

        . "$PSScriptRoot/../functions/Remove-GTExpiredInvites.ps1"
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
            Remove-GTExpiredInvites -DaysOlderThan 30 -Force

            Assert-MockCalled -CommandName "Invoke-GTGraphRequest" -Times 1 -ParameterFilter {
                $Method -eq "DELETE" -and $Uri -eq "v1.0/users/1"
            }
        }
    }
}

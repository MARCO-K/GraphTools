Describe "Revoke-GTSignOutFromAllSessions" {
    BeforeAll {
        function global:Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function global:Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Mock Error'; ErrorMessage = 'Mock Error Message' } }
        function global:Invoke-GTGraphRequest { param($Uri, $Method = 'GET', $Body, $Headers, $ContentType, [switch]$All, [int]$MaxRetries, [int]$RetryBaseDelaySeconds, $Token, [switch]$Raw, $ErrorAction) return @{} }

        . "$PSScriptRoot/../internal/functions/GTValidation.ps1"
        . "$PSScriptRoot/../functions/Revoke-GTSignOutFromAllSessions.ps1"
    }

    BeforeEach {
        Mock -CommandName Invoke-GTGraphRequest -MockWith {
            param($Uri, $Method)
            if ($Method -eq 'GET' -and $Uri -like "v1.0/users/*") {
                return [PSCustomObject]@{ Id = "mock-user-id" }
            }
            return @{}
        }
    }

    Context "Happy Path" {
        It "should call Invoke-GTGraphRequest revokeSignInSessions with the correct UserId" {
            Revoke-GTSignOutFromAllSessions -UPN "test.user@example.com"
            Assert-MockCalled -CommandName "Invoke-GTGraphRequest" -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq "v1.0/users/mock-user-id/revokeSignInSessions"
            }
        }
    }

    Context "Error Handling" {
        It "should not call revokeSignInSessions if user lookup returns null" {
            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                param($Uri, $Method)
                if ($Method -eq 'GET') {
                    return $null
                }
                return @{}
            }
            Revoke-GTSignOutFromAllSessions -UPN "non.existent.user@example.com"
            Assert-MockCalled -CommandName "Invoke-GTGraphRequest" -Times 0 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like "*revokeSignInSessions*"
            }
        }

        It "should throw an error for an invalid UPN" {
            { Revoke-GTSignOutFromAllSessions -UPN "invalid-upn" } | Should -Throw
        }
    }
}
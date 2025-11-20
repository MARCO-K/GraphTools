## Provide lightweight stubs for common helpers in case they are missing during discovery
if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param($ModuleNames, $Verbose) } }
if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param($Scopes, $NewSession) return $true } }
if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param($RequiredScopes, $Reconnect, $Quiet) return $true } }
if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "Get-GTGuestUserReport" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Get-GTGuestUserReport.ps1"

        # Use Pester Mocks before dot-sourcing so the function file can load and calls are intercepted
        Mock -CommandName Install-GTRequiredModule -MockWith { param($ModuleNames, $Verbose) } -Verifiable
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true } -Verifiable
        Mock -CommandName Test-GTGraphScopes -MockWith { param($RequiredScopes, $Reconnect, $Quiet) return $true } -Verifiable
        Mock -CommandName Write-PSFMessage -MockWith { param($Level, $Message) } -Verifiable

        if (Test-Path $functionPath)
        {
            # Dot-source the function under test
            . $functionPath
        }
        else
        {
            Write-Error "Function file not found at $functionPath"
        }
    }

    Context "Parameter Validation" {
        It "should accept PendingOnly switch" {
            Mock -CommandName "Get-MgBetaUser" -MockWith { return @() }
            { Get-GTGuestUserReport -PendingOnly } | Should -Not -Throw
        }

        It "should accept DaysSinceCreation parameter" {
            Mock -CommandName "Get-MgBetaUser" -MockWith { return @() }
            { Get-GTGuestUserReport -DaysSinceCreation 30 } | Should -Not -Throw
        }
    }

    Context "Functionality" {
        It "should use server-side filter for pending users" {
            Mock -CommandName "Get-MgBetaUser" -MockWith { return @() } -ParameterFilter { 
                $Filter -match "externalUserState eq 'PendingAcceptance'" -and $Filter -match "userType eq 'Guest'"
            }

            Get-GTGuestUserReport -PendingOnly
            
            # Verification is done via the ParameterFilter in the Mock
            Assert-MockCalled "Get-MgBetaUser" -Times 1
        }

        It "should filter by creation date correctly (client-side)" {
            $mockUsers = @(
                [PSCustomObject]@{
                    Id                = "1"
                    DisplayName       = "User1"
                    ExternalUserState = "PendingAcceptance"
                    CreatedDateTime   = (Get-Date).ToUniversalTime().AddDays(-10)
                    SignInActivity    = [PSCustomObject]@{ LastSignInDateTime = $null }
                },
                [PSCustomObject]@{
                    Id                = "2"
                    DisplayName       = "User2"
                    ExternalUserState = "Accepted"
                    CreatedDateTime   = (Get-Date).ToUniversalTime().AddDays(-40)
                    SignInActivity    = [PSCustomObject]@{ LastSignInDateTime = (Get-Date).ToUniversalTime().AddDays(-5) }
                }
            )
            Mock -CommandName "Get-MgBetaUser" -MockWith { return $mockUsers }

            $results = Get-GTGuestUserReport -DaysSinceCreation 30
            $results.Count | Should -Be 1
            $results[0].Id | Should -Be "2"
        }
    }
}

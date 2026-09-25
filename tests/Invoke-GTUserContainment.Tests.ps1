Describe "Invoke-GTUserContainment" {

    BeforeAll {
        # 1. Load Dependencies
        $validationFile = Join-Path $PSScriptRoot '..\internal\functions\GTValidation.ps1'
        if (Test-Path $validationFile) { . $validationFile }

        # Provide stubs for common helpers
        if (-not (Get-Command Install-GTRequiredModule -ErrorAction SilentlyContinue)) { function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) } }
        if (-not (Get-Command Initialize-GTGraphConnection -ErrorAction SilentlyContinue)) { function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true } }
        if (-not (Get-Command Test-GTGraphScopes -ErrorAction SilentlyContinue)) { function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true } }
        if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }
        if (-not (Get-Command Get-UTCTime -ErrorAction SilentlyContinue)) { function Get-UTCTime { return [DateTime]::UtcNow } }
        if (-not (Get-Command Get-GTGraphErrorDetails -ErrorAction SilentlyContinue)) { function Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ HttpStatus = 500; Reason = "Error"; LogLevel = "Error"; ErrorMessage = $Exception.Message } } }

        # Provide stubs for containment sub-cmdlets
        if (-not (Get-Command Revoke-GTSignOutFromAllSessions -ErrorAction SilentlyContinue)) { function Revoke-GTSignOutFromAllSessions { param($UPN, [switch]$NewSession) } }
        if (-not (Get-Command Disable-GTUser -ErrorAction SilentlyContinue)) { function Disable-GTUser { param($UPN, [switch]$Force, [switch]$NewSession) return @([PSCustomObject]@{ User = $UPN; Status = 'Disabled'; Reason = 'User disabled' }) } }
        if (-not (Get-Command Reset-GTUserPassword -ErrorAction SilentlyContinue)) { function Reset-GTUserPassword { param($UPN, [switch]$NewSession) } }
        if (-not (Get-Command Disable-GTUserDevice -ErrorAction SilentlyContinue)) { function Disable-GTUserDevice { param($UPN, [switch]$Force, [switch]$NewSession) return @([PSCustomObject]@{ User = $UPN; DeviceId = 'dev-1'; Status = 'Disabled' }) } }
        if (-not (Get-Command Remove-GTUserEntitlements -ErrorAction SilentlyContinue)) { function Remove-GTUserEntitlements { param($UserUPNs, [switch]$removeAll, [switch]$NewSession) return @() } }

        # 2. Load Function Under Test
        $functionPath = Join-Path $PSScriptRoot '..\functions\Invoke-GTUserContainment.ps1'
        if (-not (Test-Path $functionPath)) { Throw "CRITICAL: Could not find $functionPath" }
        . $functionPath
    }

    Context "Parameter Validation" {
        It "throws when UPN format is invalid" {
            { Invoke-GTUserContainment -UPN 'invaliduser' } | Should -Throw
            { Invoke-GTUserContainment -UPN '@contoso.com' } | Should -Throw
            { Invoke-GTUserContainment -UPN 'user@' } | Should -Throw
        }

        It "accepts valid UPN format" {
            Mock -CommandName "Revoke-GTSignOutFromAllSessions" -MockWith { }
            Mock -CommandName "Disable-GTUser" -MockWith { return @([PSCustomObject]@{ User = 'valid.user@contoso.com'; Status = 'Disabled' }) }
            Mock -CommandName "Reset-GTUserPassword" -MockWith { }
            Mock -CommandName "Disable-GTUserDevice" -MockWith { return @([PSCustomObject]@{ User = 'valid.user@contoso.com'; Status = 'Disabled' }) }

            { Invoke-GTUserContainment -UPN 'valid.user@contoso.com' } | Should -Not -Throw
        }

        It "binds aliases correctly" {
            Mock -CommandName "Revoke-GTSignOutFromAllSessions" -MockWith { }
            Mock -CommandName "Disable-GTUser" -MockWith { return @([PSCustomObject]@{ User = 'alias@contoso.com'; Status = 'Disabled' }) }
            Mock -CommandName "Reset-GTUserPassword" -MockWith { }
            Mock -CommandName "Disable-GTUserDevice" -MockWith { return @([PSCustomObject]@{ User = 'alias@contoso.com'; Status = 'Disabled' }) }

            $res = Invoke-GTUserContainment -UserPrincipalName 'alias@contoso.com'
            @($res).Count | Should -Be 1
            $res.UserPrincipalName | Should -Be 'alias@contoso.com'
        }

        It "processes UPNs from pipeline input" {
            Mock -CommandName "Revoke-GTSignOutFromAllSessions" -MockWith { }
            Mock -CommandName "Disable-GTUser" -MockWith { param($UPN) return @([PSCustomObject]@{ User = $UPN; Status = 'Disabled' }) }
            Mock -CommandName "Reset-GTUserPassword" -MockWith { }
            Mock -CommandName "Disable-GTUserDevice" -MockWith { param($UPN) return @([PSCustomObject]@{ User = $UPN; Status = 'Disabled' }) }

            $results = @('pipe1@contoso.com', 'pipe2@contoso.com') | Invoke-GTUserContainment
            @($results).Count | Should -Be 2
            $results[0].UserPrincipalName | Should -Be 'pipe1@contoso.com'
            $results[1].UserPrincipalName | Should -Be 'pipe2@contoso.com'
        }
    }

    Context "Default Safe Containment Execution" {
        BeforeEach {
            Mock -CommandName "Revoke-GTSignOutFromAllSessions" -MockWith { }
            Mock -CommandName "Disable-GTUser" -MockWith { return @([PSCustomObject]@{ User = 'victim@contoso.com'; Status = 'Disabled' }) }
            Mock -CommandName "Reset-GTUserPassword" -MockWith { }
            Mock -CommandName "Disable-GTUserDevice" -MockWith { return @([PSCustomObject]@{ User = 'victim@contoso.com'; Status = 'Disabled' }) }
            Mock -CommandName "Remove-GTUserEntitlements" -MockWith { }
        }

        It "executes steps 1-4 but defers entitlement stripping by default" {
            $report = Invoke-GTUserContainment -UPN 'victim@contoso.com'

            @($report).Count | Should -Be 1
            $report.Status | Should -Be 'Contained'
            $report.SessionsRevoked | Should -BeTrue
            $report.AccountDisabled | Should -BeTrue
            $report.PasswordReset | Should -BeTrue
            $report.DevicesDisabled | Should -Be 'Disabled (1 device(s))'
            $report.EntitlementsStripped | Should -Be 'Skipped'
            $report.Errors.Count | Should -Be 0

            Assert-MockCalled -CommandName "Revoke-GTSignOutFromAllSessions" -Times 1 -Exactly
            Assert-MockCalled -CommandName "Disable-GTUser" -Times 1 -Exactly
            Assert-MockCalled -CommandName "Reset-GTUserPassword" -Times 1 -Exactly
            Assert-MockCalled -CommandName "Disable-GTUserDevice" -Times 1 -Exactly
            Assert-MockCalled -CommandName "Remove-GTUserEntitlements" -Times 0 -Exactly
        }

        It "handles users with no registered devices" {
            Mock -CommandName "Disable-GTUserDevice" -MockWith { return @([PSCustomObject]@{ User = 'victim@contoso.com'; Status = 'NoDevices' }) }

            $report = Invoke-GTUserContainment -UPN 'victim@contoso.com'
            $report.Status | Should -Be 'Contained'
            $report.DevicesDisabled | Should -Be 'NoDevices'
        }
    }

    Context "Selective Containment Actions" {
        BeforeEach {
            Mock -CommandName "Revoke-GTSignOutFromAllSessions" -MockWith { }
            Mock -CommandName "Disable-GTUser" -MockWith { return @([PSCustomObject]@{ User = 'target@contoso.com'; Status = 'Disabled' }) }
            Mock -CommandName "Reset-GTUserPassword" -MockWith { }
            Mock -CommandName "Disable-GTUserDevice" -MockWith { }
            Mock -CommandName "Remove-GTUserEntitlements" -MockWith { }
        }

        It "executes only requested actions when specific switches are provided" {
            $report = Invoke-GTUserContainment -UPN 'target@contoso.com' -RevokeSessions -ResetPassword

            $report.Status | Should -Be 'Contained'
            $report.SessionsRevoked | Should -BeTrue
            $report.PasswordReset | Should -BeTrue
            $report.AccountDisabled | Should -Be 'Skipped'
            $report.DevicesDisabled | Should -Be 'Skipped'
            $report.EntitlementsStripped | Should -Be 'Skipped'

            Assert-MockCalled -CommandName "Revoke-GTSignOutFromAllSessions" -Times 1 -Exactly
            Assert-MockCalled -CommandName "Reset-GTUserPassword" -Times 1 -Exactly
            Assert-MockCalled -CommandName "Disable-GTUser" -Times 0 -Exactly
            Assert-MockCalled -CommandName "Disable-GTUserDevice" -Times 0 -Exactly
            Assert-MockCalled -CommandName "Remove-GTUserEntitlements" -Times 0 -Exactly
        }
    }

    Context "Full Containment Mode" {
        BeforeEach {
            Mock -CommandName "Revoke-GTSignOutFromAllSessions" -MockWith { }
            Mock -CommandName "Disable-GTUser" -MockWith { return @([PSCustomObject]@{ User = 'all@contoso.com'; Status = 'Disabled' }) }
            Mock -CommandName "Reset-GTUserPassword" -MockWith { }
            Mock -CommandName "Disable-GTUserDevice" -MockWith { return @([PSCustomObject]@{ User = 'all@contoso.com'; Status = 'Disabled' }) }
            Mock -CommandName "Remove-GTUserEntitlements" -MockWith { }
        }

        It "executes all 5 actions when FullContainment is specified" {
            $report = Invoke-GTUserContainment -UPN 'all@contoso.com' -FullContainment

            $report.Status | Should -Be 'Contained'
            $report.SessionsRevoked | Should -BeTrue
            $report.AccountDisabled | Should -BeTrue
            $report.PasswordReset | Should -BeTrue
            $report.DevicesDisabled | Should -Be 'Disabled (1 device(s))'
            $report.EntitlementsStripped | Should -Be 'Stripped'

            Assert-MockCalled -CommandName "Remove-GTUserEntitlements" -Times 1 -Exactly
        }
    }

    Context "ShouldProcess and WhatIf Support" {
        BeforeEach {
            Mock -CommandName "Revoke-GTSignOutFromAllSessions" -MockWith { }
            Mock -CommandName "Disable-GTUser" -MockWith { }
            Mock -CommandName "Reset-GTUserPassword" -MockWith { }
            Mock -CommandName "Disable-GTUserDevice" -MockWith { }
            Mock -CommandName "Remove-GTUserEntitlements" -MockWith { }
        }

        It "respects WhatIf and does not execute containment actions" {
            $report = Invoke-GTUserContainment -UPN 'whatif.user@contoso.com' -WhatIf

            @($report).Count | Should -Be 1
            $report.Status | Should -Be 'WhatIf'
            $report.SessionsRevoked | Should -Be 'Pending'
            $report.AccountDisabled | Should -Be 'Pending'
            $report.PasswordReset | Should -Be 'Pending'
            $report.DevicesDisabled | Should -Be 'Pending'
            $report.EntitlementsStripped | Should -Be 'Skipped'

            Assert-MockCalled -CommandName "Revoke-GTSignOutFromAllSessions" -Times 0 -Exactly
            Assert-MockCalled -CommandName "Disable-GTUser" -Times 0 -Exactly
            Assert-MockCalled -CommandName "Reset-GTUserPassword" -Times 0 -Exactly
            Assert-MockCalled -CommandName "Disable-GTUserDevice" -Times 0 -Exactly
        }
    }

    Context "Error Handling & Partial Containment" {
        BeforeEach {
            Mock -CommandName "Revoke-GTSignOutFromAllSessions" -MockWith { }
            Mock -CommandName "Disable-GTUser" -MockWith { return @([PSCustomObject]@{ User = 'partial@contoso.com'; Status = 'Disabled' }) }
            Mock -CommandName "Reset-GTUserPassword" -MockWith { throw "Graph error rotating password" }
            Mock -CommandName "Disable-GTUserDevice" -MockWith { return @([PSCustomObject]@{ User = 'partial@contoso.com'; Status = 'Disabled' }) }
        }

        It "reports PartiallyContained status and aggregates error when one action fails" {
            $report = Invoke-GTUserContainment -UPN 'partial@contoso.com' -WarningAction SilentlyContinue

            $report.Status | Should -Be 'PartiallyContained'
            $report.SessionsRevoked | Should -BeTrue
            $report.AccountDisabled | Should -BeTrue
            $report.PasswordReset | Should -BeFalse
            $report.DevicesDisabled | Should -Be 'Disabled (1 device(s))'
            @($report.Errors).Count | Should -BeGreaterThan 0
            $report.Errors[0] | Should -Match "ResetPassword failed"
        }

        It "reports Failed status when all planned actions fail" {
            Mock -CommandName "Revoke-GTSignOutFromAllSessions" -MockWith { throw "Revoke failed" }
            Mock -CommandName "Disable-GTUser" -MockWith { throw "Disable failed" }
            Mock -CommandName "Reset-GTUserPassword" -MockWith { throw "Password failed" }
            Mock -CommandName "Disable-GTUserDevice" -MockWith { throw "Device failed" }

            $report = Invoke-GTUserContainment -UPN 'partial@contoso.com' -WarningAction SilentlyContinue
            $report.Status | Should -Be 'Failed'
            @($report.Errors).Count | Should -Be 4
        }
    }

    Context "Scope Requirements" {
        It "aborts when required Graph scopes cannot be acquired" {
            Mock -CommandName "Test-GTGraphScopes" -MockWith { return $false }

            $errOutput = $null
            try {
                Invoke-GTUserContainment -UPN 'scopetest@contoso.com' -ErrorAction Stop -ErrorVariable errOutput
            } catch {
                # Expected error
            }

            $errOutput | Should -Not -BeNullOrEmpty
        }

        It "requests Device.ReadWrite.All for device containment instead of Directory.AccessAsUser.All" {
            Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $true }
            Mock -CommandName "Test-GTGraphScopes" -MockWith { return $true }
            Mock -CommandName "Revoke-GTSignOutFromAllSessions" -MockWith { }
            Mock -CommandName "Disable-GTUser" -MockWith { return @([PSCustomObject]@{ User = 'scopecheck@contoso.com'; Status = 'Disabled' }) }
            Mock -CommandName "Reset-GTUserPassword" -MockWith { }
            Mock -CommandName "Disable-GTUserDevice" -MockWith { return @([PSCustomObject]@{ User = 'scopecheck@contoso.com'; Status = 'Disabled' }) }

            $null = Invoke-GTUserContainment -UPN 'scopecheck@contoso.com'

            Assert-MockCalled -CommandName "Initialize-GTGraphConnection" -Times 1 -Exactly -ParameterFilter {
                $Scopes -contains 'User.ReadWrite.All' -and
                $Scopes -contains 'Device.ReadWrite.All' -and
                $Scopes -notcontains 'Directory.AccessAsUser.All'
            }
            Assert-MockCalled -CommandName "Test-GTGraphScopes" -Times 1 -Exactly -ParameterFilter {
                $RequiredScopes -contains 'User.ReadWrite.All' -and
                $RequiredScopes -contains 'Device.ReadWrite.All' -and
                $RequiredScopes -notcontains 'Directory.AccessAsUser.All'
            }
        }

        It "enforces least-privilege by excluding User.ReadWrite.All when only -DisableDevices is requested" {
            Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $true }
            Mock -CommandName "Test-GTGraphScopes" -MockWith { return $true }
            Mock -CommandName "Disable-GTUserDevice" -MockWith { return @([PSCustomObject]@{ User = 'devicesonly@contoso.com'; Status = 'Disabled' }) }

            $null = Invoke-GTUserContainment -UPN 'devicesonly@contoso.com' -DisableDevices

            Assert-MockCalled -CommandName "Initialize-GTGraphConnection" -Times 1 -Exactly -ParameterFilter {
                $Scopes -contains 'Device.ReadWrite.All' -and
                $Scopes -notcontains 'User.ReadWrite.All' -and
                $Scopes -notcontains 'Directory.AccessAsUser.All'
            }
        }

        It "enforces least-privilege by excluding User.ReadWrite.All and Device.ReadWrite.All when only -StripEntitlements is requested" {
            Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $true }
            Mock -CommandName "Test-GTGraphScopes" -MockWith { return $true }
            Mock -CommandName "Remove-GTUserEntitlements" -MockWith { return @() }

            $null = Invoke-GTUserContainment -UPN 'entitlementsonly@contoso.com' -StripEntitlements

            Assert-MockCalled -CommandName "Initialize-GTGraphConnection" -Times 1 -Exactly -ParameterFilter {
                $Scopes -contains 'GroupMember.ReadWrite.All' -and
                $Scopes -notcontains 'User.ReadWrite.All' -and
                $Scopes -notcontains 'Device.ReadWrite.All'
            }
        }
    }
}

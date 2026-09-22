Describe "Get-GTGuestUserReport" {
    BeforeAll {
        function global:Install-GTRequiredModule { param($ModuleNames, $Verbose) }
        function global:Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession, [switch]$SkipConnect) return $true }
        function global:Test-GTGraphScopes { param($RequiredScopes, $Reconnect, $Quiet) return $true }
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function global:Invoke-GTGraphPagedRequest { param($Uri, $Headers) return @() }
        function global:Invoke-GTGraphRequest { param($Method, $Uri, $Body, $ContentType, $ErrorAction, [switch]$All) return @() }

        $functionPath = "$PSScriptRoot/../functions/Get-GTGuestUserReport.ps1"

        # Use Pester Mocks before dot-sourcing so the function file can load and calls are intercepted
        Mock -CommandName Install-GTRequiredModule -MockWith { } -Verifiable
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true } -Verifiable
        Mock -CommandName Test-GTGraphScopes -MockWith { param($RequiredScopes, $Reconnect, $Quiet) return $true } -Verifiable
        Mock -CommandName Write-PSFMessage -MockWith { } -Verifiable

        . "$PSScriptRoot/../internal/functions/Initialize-GTBeginBlock.ps1"
        . "$PSScriptRoot/../internal/functions/New-GTODataFilter.ps1"
        . "$PSScriptRoot/../internal/functions/Invoke-GTGraphPagedRequest.ps1"
        . "$PSScriptRoot/../internal/functions/Get-UTCTime.ps1"

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
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { @() }
            { Get-GTGuestUserReport -PendingOnly } | Should -Not -Throw
        }

        It "should accept DaysSinceCreation parameter" {
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { @() }
            { Get-GTGuestUserReport -DaysSinceCreation 30 } | Should -Not -Throw
        }
    }

    Context "Functionality" {
        It "should use server-side filter for pending users" {
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { @() } -ParameterFilter {
                $Uri -match '/v1.0/users' -and
                [System.Uri]::UnescapeDataString([string]$Uri) -match "externalUserState eq 'PendingAcceptance'" -and
                [System.Uri]::UnescapeDataString([string]$Uri) -match "userType eq 'Guest'"
            }

            Get-GTGuestUserReport -PendingOnly
            
            # Verification is done via the ParameterFilter in the Mock
            Assert-MockCalled "Invoke-GTGraphPagedRequest" -Times 1
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
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith { return $mockUsers }

            $results = Get-GTGuestUserReport -DaysSinceCreation 30
            @($results).Count | Should -Be 1
            @($results)[0].Id | Should -Be "2"
        }
    }
}

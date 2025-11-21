Describe "Remove-GTExpiredInvites" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Remove-GTExpiredInvites.ps1"
        # Use Pester Mocks before dot-sourcing so the function file can load and calls are intercepted
        Mock -CommandName Install-GTRequiredModule -MockWith { } -Verifiable
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true } -Verifiable
        # Mock the sibling function
        Mock -CommandName Get-GTGuestUserReport -MockWith { 
            return @(
                [PSCustomObject]@{
                    Id                = "1"
                    DisplayName       = "ExpiredUser"
                    UserPrincipalName = "expired@test.com"
                }
            )
        } -Verifiable

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

    Context "Execution" {
        It "should call Remove-MgUser for expired users when Force is specified" {
            Mock -CommandName "Remove-MgUser" -MockWith { }
            
            Remove-GTExpiredInvites -DaysOlderThan 30 -Force

            Assert-MockCalled -CommandName "Remove-MgUser" -Times 1 -ParameterFilter { $UserId -eq "1" }
        }
    }
}

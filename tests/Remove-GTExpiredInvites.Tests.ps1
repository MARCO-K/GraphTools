Describe "Remove-GTExpiredInvites" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Remove-GTExpiredInvites.ps1"
        if (Test-Path $functionPath) {
            . $functionPath
        }
        else {
            Write-Error "Function file not found at $functionPath"
        }

        function Install-GTRequiredModule {}
        function Initialize-GTGraphConnection {}
        function Get-GTGuestUserReport {}
        Mock -CommandName "Install-GTRequiredModule" -MockWith { }
        Mock -CommandName "Initialize-GTGraphConnection" -MockWith { return $true }
        
        # Mock the sibling function
        Mock -CommandName "Get-GTGuestUserReport" -MockWith { 
            return @(
                [PSCustomObject]@{
                    Id                = "1"
                    DisplayName       = "ExpiredUser"
                    UserPrincipalName = "expired@test.com"
                }
            )
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

Describe "Get-MFAReport" {
    BeforeAll {
        # Define stub functions FIRST
        function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession) return $true }
        function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function Get-MgBetaReportAuthenticationMethodUserRegistrationDetail { param($Filter) return @() }

        # Set up validation regex
        $script:GTValidationRegex = @{
            UPN = '^[^@\s]+@[^@\s]+\.[^@\s]+$'
        }

        # Dot-source the function under test AFTER stubs
        . "$PSScriptRoot/../functions/Get-MFAReport.ps1"

        # Define mock data
        $script:mockReport = @(
            @{
                UserPrincipalName = 'adele.vance@contoso.com'
                UserDisplayName   = 'Adele Vance'
                IsAdmin           = $true
                UserType          = 'Member'
                IsMfaRegistered   = $true
                IsMfaCapable      = $true
                MethodsRegistered = @('microsoftAuthenticatorPush', 'FIDO2')
            },
            @{
                UserPrincipalName = 'grad.y@contoso.com'
                UserDisplayName   = 'Grady Archie'
                IsAdmin           = $false
                UserType          = 'Member'
                IsMfaRegistered   = $false
                IsMfaCapable      = $true
                MethodsRegistered = @()
            },
            @{
                UserPrincipalName = 'guest@contoso.com'
                UserDisplayName   = 'Guest User'
                IsAdmin           = $false
                UserType          = 'Guest'
                IsMfaRegistered   = $false
                IsMfaCapable      = $false
                MethodsRegistered = @()
            }
        )
    }

    BeforeEach {
        Mock -CommandName "Get-MgBetaReportAuthenticationMethodUserRegistrationDetail" -MockWith {
            param($Filter)
            if ($Filter)
            {
                $upns = ($Filter -split "'").Where({ $_ -like '*@*' })
                $script:mockReport | Where-Object { $_.UserPrincipalName -in $upns }
            }
            else
            {
                $script:mockReport
            }
        } -Verifiable
    }

    It "should return a report for a single user from the pipeline" {
        $result = 'adele.vance@contoso.com' | Get-MFAReport
        $result.UPN | Should -Be 'adele.vance@contoso.com'
        $result.Count | Should -Be 1
        Assert-MockCalled -CommandName "Get-MgBetaReportAuthenticationMethodUserRegistrationDetail" -ParameterFilter {
            $Filter -like "*'adele.vance@contoso.com'*"
        } -Times 1 -Scope It
    }

    It "should return a report for multiple users from the pipeline" {
        $users = @('adele.vance@contoso.com', 'grad.y@contoso.com')
        $result = $users | Get-MFAReport
        $result.UPN | Should -Be $users
        $result.Count | Should -Be 2
        Assert-MockCalled -CommandName "Get-MgBetaReportAuthenticationMethodUserRegistrationDetail" -ParameterFilter {
            ($Filter -like "*'adele.vance@contoso.com'*") -and ($Filter -like "*'grad.y@contoso.com'*")
        } -Times 1 -Scope It
    }

    It "should return all users when no pipeline input is provided" {
        $result = Get-MFAReport
        $result.Count | Should -Be 3
        Assert-MockCalled -CommandName "Get-MgBetaReportAuthenticationMethodUserRegistrationDetail" -ParameterFilter {
            $Filter -eq $null
        } -Times 1 -Scope It
    }

    It "should filter for admins only" {
        $result = Get-MFAReport -AdminsOnly
        $result.UPN | Should -Be 'adele.vance@contoso.com'
    }

    It "should filter for users without MFA" {
        $result = Get-MFAReport -UsersWithoutMFA
        $result.UPN | Should -Contain 'grad.y@contoso.com'
        $result.UPN | Should -Contain 'guest@contoso.com'
        $result.Count | Should -Be 2
    }

    It "should exclude guest users" {
        $result = Get-MFAReport -NoGuestUser
        $result.UPN | Should -Not -Contain 'guest@contoso.com'
        $result.Count | Should -Be 2
    }

    It "should throw an error for invalid UPN format" {
        { Get-MFAReport -UserPrincipalName 'invalid-upn' } | Should -Throw
    }

    It "should throw an error for conflicting parameters" {
        { Get-MFAReport -AdminsOnly -UsersWithoutMFA } | Should -Throw "You cannot use -AdminsOnly and -UsersWithoutMFA together."
    }
}
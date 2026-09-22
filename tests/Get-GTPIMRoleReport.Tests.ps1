Describe "Get-GTPIMRoleReport" {
    BeforeAll {
        # Define stubs for dependencies to ensure Mock works
        function global:Install-GTRequiredModule {}
        function global:Test-GTGraphScopes { return $true }
        function global:Initialize-GTGraphConnection { return $true }
        function global:Write-PSFMessage {}
        function global:Get-GTGraphErrorDetails { return @{ LogLevel = 'Error'; Reason = 'Mock Error' } }
        function global:Test-GTGuid { return $true }
        function global:Invoke-GTGraphPagedRequest { param($Uri, $Headers) return @() }
        function global:Invoke-GTGraphRequest { param($Method, $Uri, $Body, $ContentType, $ErrorAction, [switch]$All) return $null }

        $functionPath = "$PSScriptRoot/../functions/Get-GTPIMRoleReport.ps1"
        # Use Pester Mocks for external dependencies before dot-sourcing
        Mock -CommandName Install-GTRequiredModule -MockWith {} -Verifiable
        Mock -CommandName Test-GTGraphScopes -MockWith { return $true } -Verifiable
        Mock -CommandName Initialize-GTGraphConnection -MockWith { return $true } -Verifiable
        Mock -CommandName Test-GTGuid -MockWith { return $true } -Verifiable
        Mock -CommandName Get-GTGraphErrorDetails -MockWith { return @{ LogLevel = 'Error'; Reason = 'Mock Error' } } -Verifiable
        Mock -CommandName Write-PSFMessage -MockWith {} -Verifiable

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

    Context "Functionality" {
        It "should generate a report with eligible and active assignments including PrincipalType" {
            # Mock Role Definitions
            $mockRoles = @(
                [PSCustomObject]@{ id = "Role1"; displayName = "Global Admin" }
                [PSCustomObject]@{ id = "Role2"; displayName = "User Admin" }
            )

            # Mock Eligible (User)
            $mockEligible = @(
                [PSCustomObject]@{
                    principalId      = "User1"
                    roleDefinitionId = "Role1"
                    startDateTime    = (Get-Date)
                    endDateTime      = (Get-Date).AddDays(1)
                    principal        = [PSCustomObject]@{ 
                        displayName       = "User One" 
                        userPrincipalName = "user1@contoso.com"
                        '@odata.type'     = '#microsoft.graph.user'
                    }
                }
            )

            # Mock Active (Group)
            $mockActive = @(
                [PSCustomObject]@{
                    principalId      = "Group1"
                    roleDefinitionId = "Role2"
                    assignmentType   = "Assigned"
                    startDateTime    = (Get-Date)
                    endDateTime      = $null
                    principal        = [PSCustomObject]@{ 
                        displayName  = "Admin Group" 
                        '@odata.type' = '#microsoft.graph.group'
                    }
                }
            )

            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers)
                if ($Uri -like "*roleDefinitions*") { return $mockRoles }
                if ($Uri -like "*roleEligibilityScheduleInstances*") { return $mockEligible }
                if ($Uri -like "*roleAssignmentScheduleInstances*") { return $mockActive }
                return @()
            }

            $results = Get-GTPIMRoleReport
            $results.Count | Should -Be 2
            
            $eligible = $results | Where-Object { $_.Type -eq 'Eligible' }
            $eligible.Role | Should -Be "Global Admin"
            $eligible.User | Should -Be "User One"
            $eligible.PrincipalType | Should -Be "User"
            $eligible.RoleId | Should -Be "Role1"

            $active = $results | Where-Object { $_.Type -eq 'Active' }
            $active.Role | Should -Be "User Admin"
            $active.User | Should -Be "Admin Group"
            $active.PrincipalType | Should -Be "Group"
            $active.AssignmentState | Should -BeLike "Assigned*"
        }

        It "should filter by RoleName" {
            # Mock Role Definitions
            $mockRoles = @(
                [PSCustomObject]@{ id = "Role1"; displayName = "Global Admin" }
            )
            Mock -CommandName "Invoke-GTGraphPagedRequest" -MockWith {
                param($Uri, $Headers)
                if ($Uri -like "*roleDefinitions*") { return $mockRoles }
                return @()
            }

            Get-GTPIMRoleReport -RoleName "Global Admin"
            # Verify logic inside loop handles filtering (mock returns empty so just ensuring no error)
        }
    }
}

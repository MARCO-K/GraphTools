Describe "Remove-GTUserGroupOwnership" {
    BeforeAll {
        # Mock PSFramework logging
        if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) {
            function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        }

        $statusHelper = Join-Path $PSScriptRoot '..\internal\functions\Get-GTGraphHttpStatus.ps1'
        if (Test-Path $statusHelper) { . $statusHelper }

        $errorHelperFile = Join-Path $PSScriptRoot '..\internal\functions\Get-GTGraphErrorDetails.ps1'
        if (Test-Path $errorHelperFile) {
            . $errorHelperFile
        } else {
            throw "Required helper function Get-GTGraphErrorDetails.ps1 not found at: $errorHelperFile"
        }

        $validationFile = Join-Path $PSScriptRoot '..\internal\functions\GTValidation.ps1'
        if (Test-Path $validationFile) { . $validationFile }

        # Define stubs for mocked commands
        function global:Invoke-GTGraphRequest { param($Uri, $Method = 'GET', $Body, $Headers, $ContentType, [switch]$All, [int]$MaxRetries, [int]$RetryBaseDelaySeconds, $Token, [switch]$Raw, $ErrorAction) }
        function global:Invoke-GTGraphBatch { param($Requests, $ErrorAction) }
        function global:Invoke-GTGraphPagedRequest { param($Uri, $Headers, $ErrorAction) }

        # Import the internal function under test
        . "$PSScriptRoot/../internal/functions/Remove-GTUserGroupOwnership.ps1"
    }

    AfterAll {
        Remove-Item Function:\Remove-GTUserGroupOwnership -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Remove-GTUserGroupOwnerships -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-GTUserObject -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Write-PSFMessage -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Invoke-GTGraphRequest -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Invoke-GTGraphBatch -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Invoke-GTGraphPagedRequest -Force -ErrorAction SilentlyContinue
    }

    Context "Naming & Alias Compatibility" {
        It "resolves legacy Remove-GTUserGroupOwnerships alias to Remove-GTUserGroupOwnership" {
            (Get-Command Remove-GTUserGroupOwnerships).ResolvedCommandName | Should -Be 'Remove-GTUserGroupOwnership'
        }
    }

    Context "Parameter Validation" {
        It "should reject a user object without Id property" {
            $invalidUser = [PSCustomObject]@{
                UserPrincipalName = 'test@contoso.com'
            }
            $outputBase = @{ UserPrincipalName = 'test@contoso.com' }
            $results = [System.Collections.Generic.List[PSObject]]::new()

            { Remove-GTUserGroupOwnership -User $invalidUser -OutputBase $outputBase -Results $results } | Should -Throw
        }

        It "should reject a user object without UserPrincipalName property" {
            $invalidUser = [PSCustomObject]@{
                Id = 'test-id-123'
            }
            $outputBase = @{ UserPrincipalName = 'test@contoso.com' }
            $results = [System.Collections.Generic.List[PSObject]]::new()

            { Remove-GTUserGroupOwnership -User $invalidUser -OutputBase $outputBase -Results $results } | Should -Throw
        }
    }

    Context "Batch fetching group owners" {
        BeforeEach {
            Mock Invoke-GTGraphRequest { param($Uri, $Method) return $null }
            Mock Invoke-GTGraphBatch { param($Requests) return @() }

            $global:mockUser = [PSCustomObject]@{
                Id                = 'user-1'
                UserPrincipalName = 'test@example.com'
            }
            $global:mockOutputBase = @{ UserPrincipalName = 'test@example.com' }
        }

        It "should pre-fetch owner counts in batch and remove ownership when user is not the last owner" {
            Mock Invoke-GTGraphPagedRequest {
                param($Uri)
                if ($Uri -match "ownedObjects") {
                    return @(
                        [PSCustomObject]@{
                            id          = "group-100"
                            displayName = "Multi-Owner Group"
                        },
                        [PSCustomObject]@{
                            id          = "group-200"
                            displayName = "Solo-Owner Group"
                        }
                    )
                }
            } -ParameterFilter { $Uri -match "ownedObjects" }

            Mock Invoke-GTGraphBatch {
                param($Requests)
                return @(
                    [PSCustomObject]@{
                        Id     = "group_group-100"
                        Status = 200
                        Body   = @{
                            value = @(
                                [PSCustomObject]@{ id = "user-1" },
                                [PSCustomObject]@{ id = "user-2" }
                            )
                        }
                    },
                    [PSCustomObject]@{
                        Id     = "group_group-200"
                        Status = 200
                        Body   = @{
                            value = @(
                                [PSCustomObject]@{ id = "user-1" }
                            )
                        }
                    }
                )
            }

            $results = [System.Collections.Generic.List[PSObject]]::new()
            $results.Add([PSCustomObject]@{ Placeholder = $true })
            Remove-GTUserGroupOwnership -User $global:mockUser -OutputBase $global:mockOutputBase -Results $results -Confirm:$false
            $results.RemoveAt(0)

            # Assert batch was invoked once and per-group owner queries were avoided
            Assert-MockCalled Invoke-GTGraphBatch -Times 1 -Exactly
            Assert-MockCalled Invoke-GTGraphPagedRequest -Times 0 -Exactly -ParameterFilter { $Uri -match "/owners\?" }

            # Assert deletion was executed for multi-owner group only
            Assert-MockCalled Invoke-GTGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -match 'v1\.0/groups/group-100/owners/user-1/\$ref'
            }

            $results.Count | Should -Be 2
            $results[0].ResourceId | Should -Be 'group-100'
            $results[0].Status | Should -Be 'Success'

            $results[1].ResourceId | Should -Be 'group-200'
            $results[1].Status | Should -Be 'Skipped: Last owner'
        }

        It "should fall back to Invoke-GTGraphPagedRequest when batch returns non-200 status" {
            Mock Invoke-GTGraphPagedRequest {
                param($Uri)
                if ($Uri -match "ownedObjects") {
                    return @(
                        [PSCustomObject]@{
                            id          = "group-300"
                            displayName = "Fallback Group"
                        }
                    )
                } else {
                    return @(
                        [PSCustomObject]@{ id = "user-1" },
                        [PSCustomObject]@{ id = "user-2" }
                    )
                }
            }

            Mock Invoke-GTGraphBatch {
                param($Requests)
                return @(
                    [PSCustomObject]@{
                        Id     = "group_group-300"
                        Status = 500
                        Body   = $null
                    }
                )
            }

            $results = [System.Collections.Generic.List[PSObject]]::new()
            $results.Add([PSCustomObject]@{ Placeholder = $true })
            Remove-GTUserGroupOwnership -User $global:mockUser -OutputBase $global:mockOutputBase -Results $results -Confirm:$false
            $results.RemoveAt(0)

            Assert-MockCalled Invoke-GTGraphBatch -Times 1 -Exactly
            # Batch failed to populate map -> fall back to per-group paged request
            Assert-MockCalled Invoke-GTGraphPagedRequest -Times 1 -Exactly -ParameterFilter { $Uri -match "/owners\?" }

            $results.Count | Should -Be 1
            $results[0].ResourceId | Should -Be 'group-300'
            $results[0].Status | Should -Be 'Success'
        }

        It "should fall back to Invoke-GTGraphPagedRequest when Invoke-GTGraphBatch throws an exception" {
            Mock Invoke-GTGraphPagedRequest {
                param($Uri)
                if ($Uri -match "ownedObjects") {
                    return @(
                        [PSCustomObject]@{
                            id          = "group-400"
                            displayName = "Exception Fallback Group"
                        }
                    )
                } else {
                    return @(
                        [PSCustomObject]@{ id = "user-1" },
                        [PSCustomObject]@{ id = "user-2" }
                    )
                }
            }

            Mock Invoke-GTGraphBatch {
                param($Requests)
                throw "Batch service unavailable"
            }

            $results = [System.Collections.Generic.List[PSObject]]::new()
            $results.Add([PSCustomObject]@{ Placeholder = $true })
            Remove-GTUserGroupOwnership -User $global:mockUser -OutputBase $global:mockOutputBase -Results $results -Confirm:$false
            $results.RemoveAt(0)

            Assert-MockCalled Invoke-GTGraphBatch -Times 1 -Exactly
            Assert-MockCalled Invoke-GTGraphPagedRequest -Times 1 -Exactly -ParameterFilter { $Uri -match "/owners\?" }

            $results.Count | Should -Be 1
            $results[0].ResourceId | Should -Be 'group-400'
            $results[0].Status | Should -Be 'Success'
        }
    }
}

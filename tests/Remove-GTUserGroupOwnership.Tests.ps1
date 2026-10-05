Describe "Remove-GTUserGroupOwnership" {
    BeforeAll {
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }

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

        function global:Invoke-GTGraphRequest { param($Uri, $Method = 'GET', $Body, $Headers, $ContentType, [switch]$All, [int]$MaxRetries, [int]$RetryBaseDelaySeconds, $Token, [switch]$Raw, $ErrorAction) }
        function global:Invoke-GTGraphBatch { param($Requests, $ErrorAction) }
        function global:Invoke-GTGraphPagedRequest { param($Uri, $Headers, $ErrorAction) }

        . "$PSScriptRoot/../internal/functions/Remove-GTUserGroupOwnership.ps1"
    }

    AfterAll {
        Remove-Item Function:\Remove-GTUserGroupOwnership -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-GTUserObject -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Write-PSFMessage -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Invoke-GTGraphRequest -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Invoke-GTGraphBatch -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Invoke-GTGraphPagedRequest -Force -ErrorAction SilentlyContinue
    }

    Context "Batch fetching owners" {
        BeforeEach {
            Mock Invoke-GTGraphRequest { param($Uri, $Method) return $null }
            Mock Invoke-GTGraphBatch { param($Requests) return @() }

            $global:mockUser = [PSCustomObject]@{
                Id = 'user-1'
                UserPrincipalName = 'test@example.com'
            }
            $global:mockOutputBase = @{ UserPrincipalName = 'test@example.com' }
        }

        It "should use Invoke-GTGraphBatch to fetch owner counts for groups" {
            Mock Invoke-GTGraphPagedRequest {
                param($Uri)
                if ($Uri -match "ownedObjects/microsoft.graph.group") {
                    return @(
                        [PSCustomObject]@{
                            id = "group-123"
                            displayName = "Test Group"
                        }
                    )
                }
            } -ParameterFilter { $Uri -match "ownedObjects" }

            Mock Invoke-GTGraphBatch {
                param($Requests)

                $responses = @()
                foreach ($req in $Requests) {
                    $responses += [PSCustomObject]@{
                        Id = $req.id
                        Status = 200
                        Body = @{
                            value = @( @{id="owner-1"}, @{id="owner-2"} )
                        }
                    }
                }
                return $responses
            }

            $results = [System.Collections.Generic.List[PSObject]]::new()
            $results.Add([PSCustomObject]@{ Placeholder = $true })
            Remove-GTUserGroupOwnership -User $global:mockUser -OutputBase $global:mockOutputBase -Results $results -Confirm:$false
            $results.RemoveAt(0)

            Assert-MockCalled Invoke-GTGraphBatch -Times 1 -Exactly
            Assert-MockCalled Invoke-GTGraphPagedRequest -Times 0 -Exactly -ParameterFilter { $Uri -match "/owners\?" }

            $results.Count | Should -Be 1
            $results[0].Action | Should -Be 'RemoveGroupOwnership'
            $results[0].Status | Should -Be 'Success'
        }

        It "should fall back to Invoke-GTGraphPagedRequest if batch request fails or doesn't return data" {
            Mock Invoke-GTGraphPagedRequest {
                param($Uri)
                if ($Uri -match "ownedObjects/microsoft.graph.group") {
                    return @(
                        [PSCustomObject]@{
                            id = "group-123"
                            displayName = "Test Group"
                        }
                    )
                } else {
                    return @( [PSCustomObject]@{id="owner-1"}, [PSCustomObject]@{id="owner-2"} )
                }
            }

            Mock Invoke-GTGraphBatch {
                param($Requests)
                $responses = @()
                foreach ($req in $Requests) {
                    $responses += [PSCustomObject]@{
                        Id = $req.id
                        Status = 500
                        Body = $null
                    }
                }
                return $responses
            }

            $results = [System.Collections.Generic.List[PSObject]]::new()
            $results.Add([PSCustomObject]@{ Placeholder = $true })
            Remove-GTUserGroupOwnership -User $global:mockUser -OutputBase $global:mockOutputBase -Results $results -Confirm:$false
            $results.RemoveAt(0)

            Assert-MockCalled Invoke-GTGraphBatch -Times 1 -Exactly
            Assert-MockCalled Invoke-GTGraphPagedRequest -Times 1 -ParameterFilter { $Uri -match "/owners\?" }

            $results.Count | Should -Be 1
            $results[0].Status | Should -Be 'Success'
        }
    }
}

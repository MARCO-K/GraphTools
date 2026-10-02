# Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# Create a module path if we need Pester
Import-Module Pester -RequiredVersion 5.3.3 -ErrorAction SilentlyContinue

# Import dependencies
. "$PSScriptRoot/internal/functions/Get-GTGraphHttpStatus.ps1"
. "$PSScriptRoot/internal/functions/Get-GTGraphErrorDetails.ps1"
. "$PSScriptRoot/internal/functions/GTValidation.ps1"

Describe "Performance Benchmark" {
    BeforeAll {
        function Write-PSFMessage { }
        function global:Invoke-GTGraphPagedRequest { param($Uri) }
        function global:Invoke-GTGraphRequest { param($Uri, $Method, $Body) }
        function global:Invoke-GTGraphBatch { param($Requests) }
        function global:Test-GTUserObject { param($User) return $true }

        . "$PSScriptRoot/internal/functions/Remove-GTUserEnterpriseAppOwnership.ps1"
    }

    It "Measures N+1 execution time" {
        Mock Invoke-GTGraphPagedRequest {
            param($Uri)
            Start-Sleep -Milliseconds 50 # simulate network delay
            if ($Uri -match "ownedObjects") {
                $objects = @()
                for ($i = 1; $i -le 10; $i++) {
                    $objects += [PSCustomObject]@{
                        id = "app-$i"
                        displayName = "App $i"
                        '@odata.type' = '#microsoft.graph.application'
                    }
                }
                for ($i = 1; $i -le 10; $i++) {
                    $objects += [PSCustomObject]@{
                        id = "sp-$i"
                        displayName = "SP $i"
                        '@odata.type' = '#microsoft.graph.servicePrincipal'
                    }
                }
                return $objects
            } else {
                # Owners call
                return @( [PSCustomObject]@{ id = "owner-1" }, [PSCustomObject]@{ id = "owner-2" } )
            }
        }

        Mock Invoke-GTGraphRequest {
            param($Uri, $Method, $Body, $ErrorAction)
            Start-Sleep -Milliseconds 50
        }

        Mock Invoke-GTGraphBatch {
            param($Requests)
            Start-Sleep -Milliseconds 50
            # A simple mock for the batch to work
            $responses = @()
            foreach ($req in $Requests) {
                $responses += [PSCustomObject]@{
                    Id = $req.id
                    Status = 200
                    Body = @{
                        value = @( @{ id = "owner-1" }, @{ id = "owner-2" } )
                    }
                }
            }
            return $responses
        }

        $user = [PSCustomObject]@{
            Id = 'user-1'
            UserPrincipalName = 'user@example.com'
        }
        $outputBase = @{ UserPrincipalName = $user.UserPrincipalName }

        $results = [System.Collections.Generic.List[PSObject]]::new()
        $results.Add([PSCustomObject]@{ Placeholder = $true })

        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        Remove-GTUserEnterpriseAppOwnership -User $user -OutputBase $outputBase -Results $results -Confirm:$false

        $sw.Stop()
        Write-Host "Execution Time: $($sw.ElapsedMilliseconds) ms"

        # 1 placeholder + 20 results = 21
        $results.Count | Should -Be 21
    }
}

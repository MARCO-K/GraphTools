if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "Invoke-GTGraphPagedRequest" -Tag 'Unit' {
    BeforeAll {
        $reqFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Invoke-GTGraphRequest.ps1'
        if (Test-Path $reqFile) { . $reqFile }

        $functionFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Invoke-GTGraphPagedRequest.ps1'
        if (-not (Test-Path $functionFile)) { Throw "Function file not found: $functionFile" }
        . $functionFile
    }

    Context "Delegation to Invoke-GTGraphRequest" {
        It "delegates to Invoke-GTGraphRequest with -All" {
            $script:capturedUri = $null
            $script:capturedHeaders = $null
            $script:capturedAll = $false

            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                $script:capturedUri = $Uri
                $script:capturedHeaders = $Headers
                $script:capturedAll = $All.IsPresent
                return @(
                    [PSCustomObject]@{ id = 'item-1' },
                    [PSCustomObject]@{ id = 'item-2' }
                )
            }

            $headers = @{ ConsistencyLevel = 'eventual' }
            $results = Invoke-GTGraphPagedRequest -Uri "v1.0/users" -Headers $headers

            $script:capturedUri | Should -Be "v1.0/users"
            $script:capturedHeaders['ConsistencyLevel'] | Should -Be 'eventual'
            $script:capturedAll | Should -Be $true
            $results.Count | Should -Be 2
            $results[0].id | Should -Be 'item-1'
        }
    }
}

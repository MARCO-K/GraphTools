if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "Invoke-GTGraphBatch" -Tag 'Unit' {
    BeforeAll {
        $reqFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Invoke-GTGraphRequest.ps1'
        if (Test-Path $reqFile) { . $reqFile }

        $functionFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Invoke-GTGraphBatch.ps1'
        if (-not (Test-Path $functionFile)) { Throw "Function file not found: $functionFile" }
        . $functionFile
    }

    Context "Batch Execution & URL Normalization" {
        It "normalizes URLs, sends requests to /$batch, and returns structured responses" {
            $script:capturedUri = $null
            $script:capturedBody = $null

            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                $script:capturedUri = $Uri
                $script:capturedBody = $Body
                return @{
                    responses = @(
                        @{ id = 'req-1'; status = 200; body = @{ displayName = 'Org' } },
                        @{ id = 'req-2'; status = 200; body = @{ displayName = 'Adele' } }
                    )
                }
            }

            $requests = @(
                @{ id = 'req-1'; url = 'organization' }
                @{ id = 'req-2'; url = 'https://graph.microsoft.com/v1.0/users/adele' }
            )

            $responses = Invoke-GTGraphBatch -Requests $requests

            $script:capturedUri | Should -Be 'v1.0/$batch'
            $script:capturedBody.requests.Count | Should -Be 2
            $script:capturedBody.requests[0].url | Should -Be '/organization'
            $script:capturedBody.requests[1].url | Should -Be '/users/adele'

            $responses.Count | Should -Be 2
            $responses[0].Id | Should -Be 'req-1'
            $responses[0].Status | Should -Be 200
            $responses[0].Body.displayName | Should -Be 'Org'
            $responses[0].PSObject.TypeNames | Should -Contain 'GraphTools.BatchResponse'
        }
    }

    Context "Chunking Large Requests" {
        It "automatically chunks requests exceeding 20 into multiple batch calls" {
            $script:callCount = 0

            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                $script:callCount++
                $ret = @(
                    foreach ($sub in $Body.requests) {
                        @{ id = $sub.id; status = 200; body = @{ id = $sub.id } }
                    }
                )
                return @{ responses = $ret }
            }

            # Generate 25 requests
            $requests = 1..25 | ForEach-Object {
                @{ id = "id-$_"; url = "/users/user-$_" }
            }

            $responses = Invoke-GTGraphBatch -Requests $requests

            $script:callCount | Should -Be 2
            $responses.Count | Should -Be 25
        }
    }
}

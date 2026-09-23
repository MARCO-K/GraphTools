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

    Context "Subrequest Throttling & Retry (HTTP 429 / 503 / 504)" {
        It "retries throttled subrequests (HTTP 429) and merges successful retry responses" {
            $script:callCount = 0
            $script:recordedRequests = [System.Collections.Generic.List[object]]::new()

            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                $script:callCount++
                $script:recordedRequests.Add($Body.requests)

                if ($script:callCount -eq 1) {
                    return @{
                        responses = @(
                            @{ id = 'req-1'; status = 200; body = @{ displayName = 'User 1' } },
                            @{ id = 'req-2'; status = 429; headers = @{ 'Retry-After' = '1' }; body = @{ error = @{ code = 'ActivityLimitReached' } } }
                        )
                    }
                }
                else {
                    return @{
                        responses = @(
                            @{ id = 'req-2'; status = 200; body = @{ displayName = 'User 2' } }
                        )
                    }
                }
            }

            Mock -CommandName Start-Sleep -MockWith {}

            $requests = @(
                @{ id = 'req-1'; url = '/users/user1' }
                @{ id = 'req-2'; url = '/users/user2' }
            )

            $responses = Invoke-GTGraphBatch -Requests $requests -MaxSubrequestRetries 3 -RetryBaseDelaySeconds 0

            $script:callCount | Should -Be 2
            # First call had both requests
            $script:recordedRequests[0].Count | Should -Be 2
            # Second call had only throttled req-2
            $script:recordedRequests[1].Count | Should -Be 1
            $script:recordedRequests[1][0]['id'] | Should -Be 'req-2'

            # Both responses merged and in original order
            $responses.Count | Should -Be 2
            $responses[0].Id | Should -Be 'req-1'
            $responses[0].Status | Should -Be 200
            $responses[0].Body.displayName | Should -Be 'User 1'

            $responses[1].Id | Should -Be 'req-2'
            $responses[1].Status | Should -Be 200
            $responses[1].Body.displayName | Should -Be 'User 2'
        }

        It "stops retrying and returns last error when subrequest retries are exhausted" {
            $script:callCount = 0

            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                $script:callCount++
                return @{
                    responses = @(
                        @{ id = 'req-fail'; status = 429; body = @{ error = @{ code = 'ActivityLimitReached' } } }
                    )
                }
            }

            Mock -CommandName Start-Sleep -MockWith {}

            $responses = Invoke-GTGraphBatch -Requests @(@{ id = 'req-fail'; url = '/users/fail' }) -MaxSubrequestRetries 2 -RetryBaseDelaySeconds 0

            # 1 initial attempt + 2 retries = 3 calls
            $script:callCount | Should -Be 3
            $responses.Count | Should -Be 1
            $responses[0].Id | Should -Be 'req-fail'
            $responses[0].Status | Should -Be 429
        }

        It "does not retry permanent client errors (HTTP 400, 404)" {
            $script:callCount = 0

            Mock -CommandName Invoke-GTGraphRequest -MockWith {
                $script:callCount++
                return @{
                    responses = @(
                        @{ id = 'req-notfound'; status = 404; body = @{ error = @{ code = 'Request_ResourceNotFound' } } }
                    )
                }
            }

            $responses = Invoke-GTGraphBatch -Requests @(@{ id = 'req-notfound'; url = '/users/unknown' })

            $script:callCount | Should -Be 1
            $responses.Count | Should -Be 1
            $responses[0].Status | Should -Be 404
        }
    }
}

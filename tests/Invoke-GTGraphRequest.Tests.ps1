if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }
if (-not (Get-Command Get-GTGraphErrorDetails -ErrorAction SilentlyContinue)) {
    $errFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Get-GTGraphErrorDetails.ps1'
    if (Test-Path $errFile) { . $errFile }
    else { function Get-GTGraphErrorDetails { param($Exception, $ResourceType, $Uri) [PSCustomObject]@{ HttpStatus = 500; Reason = $Exception.Message; LogLevel = 'Error' } } }
}

Describe "Invoke-GTGraphRequest" -Tag 'Unit' {
    BeforeAll {
        $tokenFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Get-GTCachedGraphToken.ps1'
        if (Test-Path $tokenFile) { . $tokenFile }

        $functionFile = Join-Path -Path $PSScriptRoot -ChildPath '..\internal\functions\Invoke-GTGraphRequest.ps1'
        if (-not (Test-Path $functionFile)) { Throw "Function file not found: $functionFile" }
        . $functionFile
    }

    BeforeEach {
        $script:mockToken = 'mock-bearer-token-12345'
        Mock -CommandName Get-GTCachedGraphToken -MockWith { return $script:mockToken }
    }

    Context "URI Normalization & Headers" {
        It "normalizes relative v1.0 URI to full graph.microsoft.com endpoint" {
            $script:capturedParams = $null

            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:capturedParams = @{
                    Uri     = $Uri
                    Headers = $Headers
                    Method  = $Method
                }
                return @{ value = @( @{ id = 'user-1' } ) }
            }

            $result = Invoke-GTGraphRequest -Uri "v1.0/users"

            $script:capturedParams.Uri | Should -Be "https://graph.microsoft.com/v1.0/users"
            $script:capturedParams.Headers['Authorization'] | Should -Be "Bearer mock-bearer-token-12345"
            $script:capturedParams.Headers['client-request-id'] | Should -Not -BeNullOrEmpty
            $script:capturedParams.Method | Should -Be "GET"
        }

        It "preserves absolute URI and merges custom headers" {
            $script:capturedHeaders = $null
            $script:capturedUri = $null

            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:capturedUri = $Uri
                $script:capturedHeaders = $Headers
                return @{ value = @() }
            }

            $customHeaders = @{
                'ConsistencyLevel' = 'eventual'
                'Custom-Tracking'  = 'unit-test'
            }

            $result = Invoke-GTGraphRequest -Uri "https://graph.microsoft.com/beta/groups" -Headers $customHeaders

            $script:capturedUri | Should -Be "https://graph.microsoft.com/beta/groups"
            $script:capturedHeaders['ConsistencyLevel'] | Should -Be 'eventual'
            $script:capturedHeaders['Custom-Tracking'] | Should -Be 'unit-test'
            $script:capturedHeaders['Authorization'] | Should -Be "Bearer mock-bearer-token-12345"
        }
    }

    Context "HTTP Methods & Body Serialization" {
        It "serializes hashtable body to JSON for PATCH request" {
            $script:capturedMethod = $null
            $script:capturedBody = $null
            $script:capturedContentType = $null

            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:capturedMethod = $Method
                $script:capturedBody = $Body
                $script:capturedContentType = $ContentType
                return @{ id = 'user-1'; accountEnabled = $false }
            }

            $bodyPayload = @{ accountEnabled = $false }
            $result = Invoke-GTGraphRequest -Uri "v1.0/users/user-1" -Method PATCH -Body $bodyPayload

            $script:capturedMethod | Should -Be 'PATCH'
            $script:capturedContentType | Should -Be 'application/json; charset=utf-8'
            $script:capturedBody | Should -Match '"accountEnabled":false'
        }
    }

    Context "Pagination (-All)" {
        It "follows @odata.nextLink across multiple pages and returns accumulated items" {
            $script:callCount = 0

            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    return [PSCustomObject]@{
                        '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=page2'
                        value = @(
                            [PSCustomObject]@{ id = 'user-1'; displayName = 'Alice' },
                            [PSCustomObject]@{ id = 'user-2'; displayName = 'Bob' }
                        )
                    }
                }
                elseif ($script:callCount -eq 2) {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'user-3'; displayName = 'Charlie' }
                        )
                    }
                }
            }

            $allUsers = Invoke-GTGraphRequest -Uri "v1.0/users" -All

            $script:callCount | Should -Be 2
            $allUsers.Count | Should -Be 3
            $allUsers[0].displayName | Should -Be 'Alice'
            $allUsers[1].displayName | Should -Be 'Bob'
            $allUsers[2].displayName | Should -Be 'Charlie'
        }
    }

    Context "Resilience & Throttling (HTTP 429 Retry)" {
        It "retries on 429 throttling and succeeds on subsequent attempt" {
            $script:attemptCount = 0

            Mock -CommandName Start-Sleep -MockWith { param($Seconds) }

            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:attemptCount++
                if ($script:attemptCount -eq 1) {
                    $mockResponse = [PSCustomObject]@{
                        StatusCode = 429
                        Headers    = @{ 'Retry-After' = '1' }
                    }
                    $ex = [System.Exception]::new('Too Many Requests')
                    $ex | Add-Member -NotePropertyName 'Response' -NotePropertyValue $mockResponse -Force
                    throw $ex
                }
                return @{ value = @( @{ id = 'retry-success' } ) }
            }

            $result = Invoke-GTGraphRequest -Uri "v1.0/users" -MaxRetries 2

            $script:attemptCount | Should -Be 2
            $result.value[0].id | Should -Be 'retry-success'
        }

        It "refreshes token on 401 Unauthorized and retries successfully" {
            $script:attemptCount = 0
            $script:refreshed = $false

            Mock -CommandName Get-GTCachedGraphToken -MockWith {
                param([switch]$ForceRefresh)
                if ($ForceRefresh) {
                    $script:refreshed = $true
                    return 'refreshed-token-67890'
                }
                return 'initial-token-12345'
            }

            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:attemptCount++
                if ($script:attemptCount -eq 1) {
                    $mockResponse = [PSCustomObject]@{ StatusCode = 401 }
                    $ex = [System.Exception]::new('Unauthorized')
                    $ex | Add-Member -NotePropertyName 'Response' -NotePropertyValue $mockResponse -Force
                    throw $ex
                }
                return @{ value = @( @{ id = 'token-refresh-success' } ) }
            }

            $result = Invoke-GTGraphRequest -Uri "v1.0/users" -MaxRetries 2

            $script:attemptCount | Should -Be 2
            $script:refreshed | Should -Be $true
            $result.value[0].id | Should -Be 'token-refresh-success'
        }
    }
}

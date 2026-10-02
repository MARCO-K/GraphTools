if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "OAuth HttpListener & PKCE" -Tag 'Unit' {
    BeforeAll {
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

        $helperPath = Join-Path $PSScriptRoot '..\internal\functions\Invoke-GTOAuthHttpListener.ps1'
        if (Test-Path $helperPath) { . $helperPath }

        $freePortPath = Join-Path $PSScriptRoot '..\internal\functions\Get-GTFreePort.ps1'
        if (Test-Path $freePortPath) { . $freePortPath }
    }

    Context "New-GTPkcePair" {
        It "generates valid RFC 7636 PKCE pair with S256 challenge" {
            $pkce = New-GTPkcePair

            $pkce | Should -Not -BeNullOrEmpty
            $pkce.CodeVerifier | Should -Not -BeNullOrEmpty
            $pkce.CodeVerifier.Length | Should -BeGreaterOrEqual 43
            $pkce.CodeVerifier | Should -Not -Match '[+/=]'

            $pkce.CodeChallenge | Should -Not -BeNullOrEmpty
            $pkce.CodeChallenge | Should -Not -Match '[+/=]'

            # Verify that S256 computation of verifier reproduces challenge
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $expectedHash = $sha256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($pkce.CodeVerifier))
            $expectedChallenge = [Convert]::ToBase64String($expectedHash).TrimEnd('=').Replace('+', '-').Replace('/', '_')
            $pkce.CodeChallenge | Should -Be $expectedChallenge
        }
    }

    Context "Invoke-GTOAuthHttpListener Stray Request Filtering & Auth Callback" {
        It "handles stray requests with 404 and accepts valid OAuth callback code" {
            $port = Get-GTFreePort

            Mock -CommandName Start-Process -MockWith {
                param($FilePath)
                # Parse the state generated in the authorize URL
                $uri = [System.Uri]::new($FilePath)
                $query = $uri.Query.TrimStart('?')
                $params = @{}
                foreach ($pair in ($query -split '&')) {
                    $parts = $pair -split '=', 2
                    $params[[System.Uri]::UnescapeDataString($parts[0])] = if ($parts.Length -gt 1) { [System.Uri]::UnescapeDataString($parts[1]) } else { '' }
                }
                $state = $params['state']

                # Fire stray request first, then valid auth callback asynchronously via HttpClient
                $httpClient = [System.Net.Http.HttpClient]::new()
                $null = $httpClient.GetAsync("http://localhost:$port/favicon.ico")
                $null = $httpClient.GetAsync("http://localhost:$port/?code=auth-code-12345&state=$state")
            }

            Mock -CommandName Invoke-RestMethod -MockWith {
                param($Uri, $Body)
                $script:capturedTokenBody = $Body
                [PSCustomObject]@{
                    access_token  = 'mock-interactive-access-token'
                    refresh_token = 'mock-interactive-refresh-token'
                    expires_in    = 86400
                }
            }

            $result = Invoke-GTOAuthHttpListener -TenantId 'test-tenant' `
                                                 -ClientId 'test-client' `
                                                 -LocalPort $port `
                                                 -TimeoutSeconds 15

            $result | Should -Not -BeNullOrEmpty
            $result.AccessToken | Should -Be 'mock-interactive-access-token'
            $result.RefreshToken | Should -Be 'mock-interactive-refresh-token'
            $result.ExpiresIn | Should -Be 86400

            # Verify claims parameter includes CP1
            $script:capturedTokenBody.claims | Should -Match 'CP1'
            $script:capturedTokenBody.code | Should -Be 'auth-code-12345'
            $script:capturedTokenBody.grant_type | Should -Be 'authorization_code'
        }

        It "throws a timeout error if no callback is received before timeout expires" {
            $port = Get-GTFreePort
            Mock -CommandName Start-Process -MockWith { param($FilePath) }

            {
                Invoke-GTOAuthHttpListener -TenantId 'test-tenant' `
                                           -ClientId 'test-client' `
                                           -LocalPort $port `
                                           -TimeoutSeconds 1
            } | Should -Throw "*timed out after 1 seconds*"
        }
    }
}

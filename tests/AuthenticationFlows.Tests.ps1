if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "Authentication Flows & Helpers" -Tag 'Unit' {
    BeforeAll {
        $pkceFile = Join-Path $PSScriptRoot '..\internal\functions\Invoke-GTOAuthHttpListener.ps1'
        if (Test-Path $pkceFile) { . $pkceFile }

        $msiFile = Join-Path $PSScriptRoot '..\internal\functions\Get-GTManagedIdentityToken.ps1'
        if (Test-Path $msiFile) { . $msiFile }

        $renewFile = Join-Path $PSScriptRoot '..\internal\functions\Invoke-GTRefreshTokenRenewal.ps1'
        if (Test-Path $renewFile) { . $renewFile }

        $deviceFile = Join-Path $PSScriptRoot '..\internal\functions\Invoke-GTDeviceCodeFlow.ps1'
        if (Test-Path $deviceFile) { . $deviceFile }
    }

    Context "New-GTPkcePair" {
        It "generates valid RFC 7636 PKCE CodeVerifier and CodeChallenge" {
            $pkce = New-GTPkcePair

            $pkce | Should -Not -BeNullOrEmpty
            $pkce.CodeVerifier | Should -Not -BeNullOrEmpty
            $pkce.CodeVerifier.Length | Should -BeGreaterOrEqual 43
            $pkce.CodeVerifier | Should -Not -Match '[+/=]'

            $pkce.CodeChallenge | Should -Not -BeNullOrEmpty
            $pkce.CodeChallenge | Should -Not -Match '[+/=]'
        }
    }

    Context "Get-GTManagedIdentityToken" {
        BeforeEach {
            # Backup & clear environment variables
            $script:origEndpoint = $env:IDENTITY_ENDPOINT
            $script:origHeader   = $env:IDENTITY_HEADER
            $script:origMsiEndpoint = $env:MSI_ENDPOINT
            $script:origMsiSecret   = $env:MSI_SECRET

            $env:IDENTITY_ENDPOINT = $null
            $env:IDENTITY_HEADER   = $null
            $env:MSI_ENDPOINT      = $null
            $env:MSI_SECRET        = $null
        }

        AfterEach {
            $env:IDENTITY_ENDPOINT = $script:origEndpoint
            $env:IDENTITY_HEADER   = $script:origHeader
            $env:MSI_ENDPOINT      = $script:origMsiEndpoint
            $env:MSI_SECRET        = $script:origMsiSecret
        }

        It "queries Azure VM IMDS endpoint with Metadata header by default" {
            $script:capturedHeaders = $null
            $script:capturedUri = $null

            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:capturedHeaders = $Headers
                $script:capturedUri = $Uri
                [PSCustomObject]@{
                    access_token = 'msi-imds-token'
                    expires_in   = 3600
                }
            }

            $token = Get-GTManagedIdentityToken

            $token.AccessToken | Should -Be 'msi-imds-token'
            $script:capturedUri | Should -Match 'http://169\.254\.169\.254/metadata/identity/oauth2/token'
            $script:capturedHeaders.Metadata | Should -Be 'true'
        }

        It "queries App Service endpoint when IDENTITY_ENDPOINT and IDENTITY_HEADER are present" {
            $env:IDENTITY_ENDPOINT = 'http://127.0.0.1:41741/MSI/token/'
            $env:IDENTITY_HEADER   = 'test-header-key'

            $script:capturedHeaders = $null
            $script:capturedUri = $null

            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:capturedHeaders = $Headers
                $script:capturedUri = $Uri
                [PSCustomObject]@{
                    access_token = 'appservice-msi-token'
                    expires_in   = 1800
                }
            }

            $token = Get-GTManagedIdentityToken

            $token.AccessToken | Should -Be 'appservice-msi-token'
            $token.ExpiresIn | Should -Be 1800
            $script:capturedHeaders['X-IDENTITY-HEADER'] | Should -Be 'test-header-key'
            $script:capturedUri | Should -Match 'http://127\.0\.0\.1:41741/MSI/token/'
        }

        It "queries classic App Service endpoint when MSI_ENDPOINT and MSI_SECRET are present" {
            $env:MSI_ENDPOINT = 'http://127.0.0.1:41741/MSI/token/'
            $env:MSI_SECRET   = 'test-msi-secret'

            $script:capturedHeaders = $null
            $script:capturedUri = $null

            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:capturedHeaders = $Headers
                $script:capturedUri = $Uri
                [PSCustomObject]@{
                    access_token = 'classic-appservice-token'
                    expires_in   = 1800
                }
            }

            $token = Get-GTManagedIdentityToken

            $token.AccessToken | Should -Be 'classic-appservice-token'
            $script:capturedHeaders['secret'] | Should -Be 'test-msi-secret'
            $script:capturedUri | Should -Match 'api-version=2017-09-01'
        }

        It "appends client_id parameter for User-Assigned identity with ClientId type" {
            $script:capturedUri = $null

            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:capturedUri = $Uri
                [PSCustomObject]@{
                    access_token = 'uami-token'
                    expires_in   = 3600
                }
            }

            $null = Get-GTManagedIdentityToken -IdentityId 'uami-guid-123' -IdentityType ClientId

            $script:capturedUri | Should -Match 'client_id=uami-guid-123'
        }

        It "appends mi_res_id parameter for User-Assigned identity with ResourceId type" {
            $script:capturedUri = $null

            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:capturedUri = $Uri
                [PSCustomObject]@{
                    access_token = 'uami-res-token'
                    expires_in   = 3600
                }
            }

            $null = Get-GTManagedIdentityToken -IdentityId '/subscriptions/sub1/resourcegroups/rg1/providers/Microsoft.ManagedIdentity/userAssignedIdentities/myId' -IdentityType ResourceId

            $script:capturedUri | Should -Match 'mi_res_id='
        }
    }

    Context "Invoke-GTRefreshTokenRenewal" {
        It "submits grant_type=refresh_token and returns updated tokens" {
            $script:capturedBody = $null

            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:capturedBody = $Body
                [PSCustomObject]@{
                    access_token  = 'new-access'
                    refresh_token = 'new-refresh'
                    expires_in    = 3599
                }
            }

            $result = Invoke-GTRefreshTokenRenewal -TenantId 'tenant-x' -ClientId 'client-y' -RefreshToken 'old-refresh'

            $result.AccessToken | Should -Be 'new-access'
            $result.RefreshToken | Should -Be 'new-refresh'
            $result.ExpiresIn | Should -Be 3599
            $script:capturedBody.grant_type | Should -Be 'refresh_token'
            $script:capturedBody.client_id | Should -Be 'client-y'
            $script:capturedBody.refresh_token | Should -Be 'old-refresh'
        }
    }

    Context "Invoke-GTDeviceCodeFlow" {
        It "initiates flow and polls until authorization_pending resolves" {
            $script:callCount = 0

            Mock -CommandName Invoke-RestMethod -MockWith {
                param($Uri)
                if ($Uri -match '/devicecode$') {
                    return [PSCustomObject]@{
                        device_code      = 'dev-code-123'
                        user_code        = 'ABCD-EFGH'
                        verification_uri = 'https://microsoft.com/devicelogin'
                        expires_in       = 900
                        interval         = 0
                        message          = 'Sign in message'
                    }
                }
                else {
                    $script:callCount++
                    if ($script:callCount -eq 1) {
                        throw [System.Exception]::new("authorization_pending")
                    }
                    return [PSCustomObject]@{
                        access_token  = 'device-access-token'
                        refresh_token = 'device-refresh-token'
                        expires_in    = 3600
                    }
                }
            }

            $result = Invoke-GTDeviceCodeFlow -TenantId 'tenant-x' -ClientId 'client-y' -TimeoutSeconds 10

            $result.AccessToken | Should -Be 'device-access-token'
            $result.RefreshToken | Should -Be 'device-refresh-token'
            $script:callCount | Should -BeGreaterThan 1
        }
    }
}

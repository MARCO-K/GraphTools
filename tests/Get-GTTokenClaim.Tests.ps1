# Pester tests for Get-GTTokenClaim
Describe "Get-GTTokenClaim" -Tag 'Unit' {
    BeforeAll {
        . "$PSScriptRoot/../internal/functions/Get-GTTokenClaim.ps1"
        if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) {
            function global:Write-PSFMessage { param($Level, $Message) }
        }

        # Helper to construct mock JWT strings
        function New-MockJwt {
            param(
                [hashtable]$Header = @{ alg = 'RS256'; typ = 'JWT' },
                [hashtable]$Payload = @{}
            )
            $headerJson = $Header | ConvertTo-Json -Compress
            $payloadJson = $Payload | ConvertTo-Json -Compress
            $headerB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($headerJson)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
            $payloadB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payloadJson)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
            return "$headerB64.$payloadB64.dummy_signature"
        }
    }

    AfterAll {
        Remove-Item Function:\Get-GTTokenClaim -Force -ErrorAction SilentlyContinue
        Remove-Item Alias:\Get-GTTokenClaims -Force -ErrorAction SilentlyContinue
    }

    Context "Alias Support" {
        It "resolves legacy Get-GTTokenClaims alias to Get-GTTokenClaim" {
            (Get-Command Get-GTTokenClaims).ResolvedCommandName | Should -Be 'Get-GTTokenClaim'
        }
    }

    Context "Valid JWT Payload Decoding" {
        It "decodes App-only JWT with roles array" {
            $jwt = New-MockJwt -Payload @{
                roles = @('User.Read.All', 'Directory.Read.All')
                tid   = 'tenant-1234'
                appid = 'app-5678'
                exp   = 1893456000
            }

            $claims = Get-GTTokenClaim -Token $jwt
            $claims | Should -Not -BeNullOrEmpty
            $claims.roles | Should -Contain 'User.Read.All'
            $claims.roles | Should -Contain 'Directory.Read.All'
            $claims.tid | Should -Be 'tenant-1234'
            $claims.appid | Should -Be 'app-5678'
            $claims.exp | Should -Be 1893456000
        }

        It "decodes Delegated JWT with scp string" {
            $jwt = New-MockJwt -Payload @{
                scp = 'User.Read Directory.Read.All'
                upn = 'admin@contoso.com'
            }

            $claims = Get-GTTokenClaim -Token $jwt
            $claims | Should -Not -BeNullOrEmpty
            $claims.scp | Should -Be 'User.Read Directory.Read.All'
            $claims.upn | Should -Be 'admin@contoso.com'
        }
    }

    Context "Error and Edge Case Handling" {
        It "returns null for empty or whitespace token" {
            Get-GTTokenClaim -Token "" | Should -BeNullOrEmpty
            Get-GTTokenClaim -Token "   " | Should -BeNullOrEmpty
        }

        It "returns null for non-JWT strings" {
            Get-GTTokenClaim -Token "not-a-jwt-token" | Should -BeNullOrEmpty
        }

        It "returns null for corrupt base64 payload" {
            Get-GTTokenClaim -Token "header.!!!invalid-base64!!!.sig" | Should -BeNullOrEmpty
        }
    }
}

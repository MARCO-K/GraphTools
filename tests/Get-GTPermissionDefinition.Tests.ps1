if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "Get-GTPermissionDefinition" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../internal/functions/Get-GTPermissionDefinition.ps1"
        if (Test-Path $functionPath) { . $functionPath } else { Throw "Function file not found: $functionPath" }
    }

    Context "Default Fixture Loading" {
        It "should load the shipped graph-permissions fixture" {
            $catalog = Get-GTPermissionDefinition -ForceRefresh
            $catalog | Should -Not -BeNullOrEmpty
            $catalog.ContainsKey("Directory.ReadWrite.All") | Should -BeTrue
            $catalog["Directory.ReadWrite.All"]["appPrivilegeLevel"] | Should -Be 4
        }

        It "should provide case-insensitive key lookups" {
            $catalog = Get-GTPermissionDefinition
            $catalog.ContainsKey("directory.readwrite.all") | Should -BeTrue
            $catalog["DIRECTORY.READWRITE.ALL"]["appPrivilegeLevel"] | Should -Be 4
        }

        It "should return cached catalog on subsequent calls" {
            $catalog1 = Get-GTPermissionDefinition
            $catalog2 = Get-GTPermissionDefinition
            [object]::ReferenceEquals($catalog1, $catalog2) | Should -BeTrue
        }
    }

    Context "Custom Permissions File" {
        BeforeAll {
            $testTempFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-permissions-$(Get-Random).json"
            @{
                "Custom.Perm.One" = @{
                    appPrivilegeLevel = 4
                    delegatedPrivilegeLevel = 3
                    requiresAdminConsent = $true
                    description = "Custom test permission"
                }
            } | ConvertTo-Json -Depth 5 | Set-Content -Path $testTempFile -Encoding UTF8
        }

        AfterAll {
            if (Test-Path $testTempFile) { Remove-Item -Path $testTempFile -Force }
        }

        It "should load custom permissions file when provided" {
            $customCatalog = Get-GTPermissionDefinition -PermissionsFile $testTempFile
            $customCatalog | Should -Not -BeNullOrEmpty
            $customCatalog.ContainsKey("Custom.Perm.One") | Should -BeTrue
            $customCatalog["Custom.Perm.One"]["appPrivilegeLevel"] | Should -Be 4
        }

        It "should return null gracefully when file does not exist" {
            $result = Get-GTPermissionDefinition -PermissionsFile "C:\nonexistent\path\file.json"
            $result | Should -BeNullOrEmpty
        }
    }
}

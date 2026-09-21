if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }
if (-not (Get-Command Get-GTGraphErrorDetails -ErrorAction SilentlyContinue)) { function Get-GTGraphErrorDetails { param($Exception, $ResourceType) return [PSCustomObject]@{ LogLevel = 'Error'; Reason = 'Error'; ErrorMessage = 'Error' } } }

Describe "Update-GTRiskyPermissionData" {
    BeforeAll {
        $functionPath = "$PSScriptRoot/../functions/Update-GTRiskyPermissionData.ps1"
        if (Test-Path $functionPath) { . $functionPath } else { Throw "Function file not found: $functionPath" }
    }

    Context "Execution and File Generation" {
        BeforeEach {
            $testOutFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-out-permissions-$(Get-Random).json"
            $mockPayload = @{
                permissions = @{
                    "Directory.ReadWrite.All" = @{
                        description = "Sample description"
                        schemes = @{
                            Application = @{
                                privilegeLevel = 4
                                requiresAdminConsent = $true
                                adminDescription = "Directory app description"
                            }
                            DelegatedWork = @{
                                privilegeLevel = 4
                                requiresAdminConsent = $true
                                adminDescription = "Directory delegated description"
                            }
                        }
                    }
                }
            }
        }

        AfterEach {
            if (Test-Path $testOutFile) { Remove-Item -Path $testOutFile -Force }
        }

        It "should fetch and write compiled permissions to target path" {
            Mock -CommandName "Invoke-RestMethod" -MockWith { return $mockPayload }

            $result = Update-GTRiskyPermissionData -OutputPath $testOutFile -Force
            $result | Should -Not -BeNullOrEmpty
            $result.PermissionCount | Should -Be 1
            $result.Status | Should -Be "Success"

            Test-Path $testOutFile | Should -BeTrue
            $content = Get-Content -Path $testOutFile -Raw | ConvertFrom-Json
            $content.PSObject.Properties['Directory.ReadWrite.All'] | Should -Not -BeNullOrEmpty
            $content.'Directory.ReadWrite.All'.appPrivilegeLevel | Should -Be 4
        }

        It "should respect WhatIf and not write to target path" {
            Mock -CommandName "Invoke-RestMethod" -MockWith { return $mockPayload }

            Update-GTRiskyPermissionData -OutputPath $testOutFile -Force -WhatIf
            Test-Path $testOutFile | Should -BeFalse
        }

        It "should throw if source payload contains no permissions" {
            Mock -CommandName "Invoke-RestMethod" -MockWith { return @{} }

            { Update-GTRiskyPermissionData -OutputPath $testOutFile -Force } | Should -Throw
        }
    }
}

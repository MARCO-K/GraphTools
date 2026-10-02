BeforeAll {
    if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) {
        function global:Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
    }

    $functionPath = "$PSScriptRoot/../internal/functions/Get-GTAuditLogRecordType.ps1"
    . $functionPath
}

AfterAll {
    Remove-Item Function:\Get-GTAuditLogRecordType -Force -ErrorAction SilentlyContinue
    Remove-Item Alias:\Get-GTAuditLogRecordTypes -Force -ErrorAction SilentlyContinue
    Remove-Item Function:\global:Write-PSFMessage -Force -ErrorAction SilentlyContinue
}

Describe "Get-GTAuditLogRecordType" {
    Context "Naming & Alias Compatibility" {
        It "resolves legacy Get-GTAuditLogRecordTypes alias to Get-GTAuditLogRecordType" {
            (Get-Command Get-GTAuditLogRecordTypes).ResolvedCommandName | Should -Be 'Get-GTAuditLogRecordType'
        }
    }

    Context "Scraping and Parsing" {
        It "parses HTML table into PSCustomObject records" {
            $mockHtml = @"
<html>
<body>
<h4 id="auditlogrecordtype">AuditLogRecordType</h4>
<table>
<tr><th>Name</th><th>Value</th><th>Description</th></tr>
<tr><td>ExchangeAdmin</td><td>1</td><td>Admin operations in Exchange</td></tr>
<tr><td>SharePoint</td><td>4</td><td>SharePoint operations</td></tr>
</table>
<h3>Next Section</h3>
</body>
</html>
"@
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                    Content    = $mockHtml
                }
            }

            $result = Get-GTAuditLogRecordType
            $result.Count | Should -Be 2
            $result[0].Name | Should -Be 'ExchangeAdmin'
            $result[0].Value | Should -Be '1'
            $result[1].Name | Should -Be 'SharePoint'
        }

        It "works through the legacy alias" {
            $mockHtml = @"
<html>
<body>
<h4 id="auditlogrecordtype">AuditLogRecordType</h4>
<table>
<tr><th>Name</th><th>Value</th></tr>
<tr><td>AzureActiveDirectory</td><td>8</td></tr>
</table>
<h3>Next</h3>
</body>
</html>
"@
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                    Content    = $mockHtml
                }
            }

            $result = Get-GTAuditLogRecordTypes
            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'AzureActiveDirectory'
        }

        It "throws if status code is not 200" {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 500
                    Content    = "Error"
                }
            }

            { Get-GTAuditLogRecordType } | Should -Throw "*Unexpected status code*"
        }
    }
}

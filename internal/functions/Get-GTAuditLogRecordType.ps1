<#
.SYNOPSIS
    Retrieves AuditLogRecordType information from Microsoft documentation
.DESCRIPTION
    Scrapes and parses the AuditLogRecordType table from Microsoft's official documentation
.PARAMETER DocUrl
    URL of the documentation page (default: Office 365 Management API schema)
.EXAMPLE
    Get-GTAuditLogRecordTypes | Format-Table
.EXAMPLE
    Get-GTAuditLogRecordTypes -Verbose | Export-Csv AuditLogRecordTypes.csv
#>
function Get-GTAuditLogRecordTypes
{
    [CmdletBinding()]
    [OutputType([PSObject[]])]
    param(
        [string]$DocUrl = "https://learn.microsoft.com/en-us/office/office-365-management-api/office-365-management-activity-api-schema#auditlogrecordtype"
    )

    begin
    {
        # Configure regex patterns upfront
        $patterns = @{
            SectionSplit = '(?si)<h4 id="auditlogrecordtype">AuditLogRecordType</h4>(.*?)<h3'
            TablePattern = '(?si)<table.*?>(.*?)</table>'
            RowPattern   = '(?si)<tr.*?>(.*?)</tr>'
            CellPattern  = '(?si)<t(h|d).*?>(.*?)</t(h|d)>'
        }
    }

    process
    {
        try
        {
            # Retrieve documentation page
            Write-PSFMessage -Level Verbose -Message "Fetching documentation from: $DocUrl"
            $response = Invoke-WebRequest -Uri $DocUrl -UseBasicParsing -ErrorAction Stop
            
            if ($response.StatusCode -ne 200)
            {
                throw "Unexpected status code: $($response.StatusCode)"
            }

            # Extract relevant section
            $contentSections = $response.Content -split $patterns.SectionSplit
            if ($contentSections.Count -lt 2)
            {
                throw "Could not find AuditLogRecordType section in documentation"
            }

            $recordTypeSection = $contentSections[1].Trim()

            # Validate and extract table
            if (-not ($recordTypeSection -match $patterns.TablePattern))
            {
                throw "Table structure not found in documentation section"
            }
            
            $tableContent = $matches[1]
            Write-PSFMessage -Level Verbose -Message "Successfully extracted table content"

            # Process table rows
            $rows = [regex]::Matches($tableContent, $patterns.RowPattern)
            if ($rows.Count -eq 0)
            {
                throw "No rows found in table"
            }

            # Extract headers
            $headerRow = $rows[0].Groups[1].Value
            $headers = [regex]::Matches($headerRow, $patterns.CellPattern) | 
            ForEach-Object { ($_.Groups[2].Value -replace '<.*?>', '').Trim() }

            # Process data rows
            $results = for ($i = 1; $i -lt $rows.Count; $i++)
            {
                $rowCells = [regex]::Matches($rows[$i].Groups[1].Value, $patterns.CellPattern)
                
                if ($rowCells.Count -eq 0) { continue }

                $rowData = [ordered]@{}
                for ($j = 0; $j -lt [Math]::Min($headers.Count, $rowCells.Count); $j++)
                {
                    $cleanValue = ($rowCells[$j].Groups[2].Value -replace '<.*?>', '').Trim()
                    $rowData[$headers[$j]] = $cleanValue -replace '&nbsp;', ' '
                }

                [PSCustomObject]$rowData
            }

            if (-not $results)
            {
                Write-PSFMessage -Level Error -Message  "No valid records found in table"
            }

            $results
        }
        catch
        {
            Write-PSFMessage -Level Error -Message  "Failed to retrieve AuditLogRecordType information: $_"
            throw
        }
    }
}

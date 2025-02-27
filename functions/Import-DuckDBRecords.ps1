<#
.SYNOPSIS
Imports records into DuckDB with automatic schema creation and deduplication.

.DESCRIPTION
This function creates a DuckDB table from input records, handles duplicates, 
and performs efficient batch inserts with transaction control.

.PARAMETER Records
Input records to process (must contain ID field)

.PARAMETER TableName
Name of the DuckDB table to create/replace

.PARAMETER DbPath
Path to DuckDB database file

.PARAMETER BatchSize
Number of records per transaction commit (default: 10000)

.EXAMPLE
$records = Get-MgAuditLogs -Start 7
Import-DuckDBRecords -Records $records -TableName 'AuditLogs' -DbPath 'C:\data\audit.db'

.EXAMPLE
$csvData = Import-Csv .\data.csv
Import-DuckDBRecords -Records $csvData -TableName 'CsvImport' -DbPath 'C:\data\mydb.db' -BatchSize 5000
#>
function Import-DuckDBRecords
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$Records,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'newDB')]
        [ValidateScript({ Test-Path $_ -IsValid })]
        [string]$LocalPath,
        [Parameter(Mandatory = $false, ParameterSetName = 'newDB')]
        [string]$DbName = "demo2.db",
        [Parameter(Mandatory = $false, ParameterSetName = 'ExistingDB')]
        [ValidateScript({ $_ })]
        [Object]$DBConn,
        
        [Parameter(Mandatory = $false)]
        [int]$BatchSize = 10000
    )

    begin
    {
        # Validate at least one record
        if ($Records.Count -eq 0)
        {
            throw "No records provided for processing"
        }

        # Create output directory and connect to DB based on parameter set
        if ($PSCmdlet.ParameterSetName -eq 'newDB')
        {
            if (-not (Test-Path -Path $LocalPath -PathType Container))
            {
                New-Item -Path $LocalPath -ItemType Directory -Force | Out-Null
            }
            $dbPath = Join-Path -Path $LocalPath -ChildPath $DbName
            # Create new DuckDB connection
            $conn = New-DuckDBConnection -DB $dbPath
        }
        # For 'ExistingDB' parameter set, $conn is already provided and validated

        # Initialize duplicate tracking
        $seenIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $uniqueRecords = [System.Collections.Generic.List[object]]::new()
    }

    process
    {
        # Process records and deduplicate
        foreach ($record in $Records)
        {
            if (-not $record.ID)
            {
                Write-PSFMessage -Level Warning -Message "Skipping record: missing ID field"
                continue
            }
            
            if ($seenIds.Add($record.ID))
            {
                $uniqueRecords.Add($record)
            }
        }
    }

    end
    {
        try
        {
            # Create dynamic table schema
            if ($uniqueRecords.Count -eq 0)
            {
                throw "No unique records found for processing"
            }
            $firstRecord = $uniqueRecords[0]
            $columns = @()

            foreach ($prop in $firstRecord.PSObject.Properties)
            {
                $duckdbType = switch -Regex ($prop.TypeNameOfValue)
                {
                    'DateTime' { 'TIMESTAMP' }
                    'Int\d{1,2}' { 'INTEGER' }
                    'Double' { 'DOUBLE' }
                    'Boolean' { 'BOOLEAN' }
                    default { 'VARCHAR' }
                }
                $columns += "$($prop.Name) $duckdbType"
            }

            $createTableQuery = @"
CREATE OR REPLACE TABLE $TableName (
    $($columns -join ", ")
);
"@
            $conn.sql($createTableQuery)
            Write-PSFMessage -Level Verbose -Message "Created table $TableName with schema: $($columns -join ', ')"

            # Batch insert with transaction control
            $counter = 0
            $conn.sql("BEGIN TRANSACTION")

            foreach ($item in $uniqueRecords)
            {
                # Generate safe SQL values
                $values = foreach ($prop in $item.PSObject.Properties)
                {
                    if ($null -eq $prop.Value)
                    {
                        "NULL"
                    }
                    else
                    {
                        switch -Regex ($prop.Value.GetType().Name)
                        {
                            'DateTime' { "'{0:yyyy-MM-dd HH:mm:ss}'" -f $prop.Value }
                            'String' { "'{0}'" -f ($prop.Value -replace "'", "''") }
                            'Boolean' { if ($prop.Value) { 'TRUE' } else { 'FALSE' } }
                            default { $prop.Value.ToString() }
                        }
                    }
                }

                # Execute insert
                write-psfmessage -level verbose -message "INSERT INTO $TableName VALUES ($($values[0] -join ', '))"
                $conn.sql("INSERT INTO $TableName VALUES ($($values -join ', '))")
                $counter++

                # Commit in batches
                if ($counter % $BatchSize -eq 0)
                {
                    $conn.sql("COMMIT")
                    $conn.sql("BEGIN TRANSACTION")
                    Write-Verbose "Committed $counter records"
                }
            }

            # Final commit
            $conn.sql("COMMIT")
            Write-PSFMessage -Level Verbose -Message "Total records inserted: $counter"

            # Verify results
            $rowCount = ($conn.sql("SELECT COUNT(*) FROM $TableName")).'count_star()' -as [int]
            Write-PSFMessage -Level Verbose -Message "Successfully inserted $rowCount records into $TableName"
        }
        catch
        {
            $conn.sql("ROLLBACK")
            throw "Database operation failed: $_"
        }
        finally
        {
            if ($conn) { $conn.Close() }
            Write-PSFMessage -Level Verbose -Message "Database connection closed"
        }
    }
}

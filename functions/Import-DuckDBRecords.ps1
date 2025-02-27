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
        
        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if (-not (Test-Path (Split-Path $_ -Parent)))
                {
                    throw "Parent directory does not exist"
                }
                $true
            })]
        [string]$DbPath,
        
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

        # Create database connection
        try
        {
            $conn = New-DuckDBConnection $DbPath
            Write-Verbose "Connected to DuckDB at $DbPath"
        }
        catch
        {
            throw "Failed to connect to DuckDB: $_"
        }

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
                Write-Warning "Record missing ID field, skipping"
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
            Write-Verbose "Created table $TableName with schema: $($columns -join ', ')"

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
            Write-Verbose "Total records inserted: $counter"

            # Verify results
            $rowCount = ($conn.sql("SELECT COUNT(*) FROM $TableName")).'count_star()' -as [int]
            Write-Host "Successfully inserted $rowCount records into $TableName"
        }
        catch
        {
            $conn.sql("ROLLBACK")
            throw "Database operation failed: $_"
        }
        finally
        {
            if ($conn) { $conn.Close() }
            Write-Verbose "Database connection closed"
        }
    }
}

# Usage example:
#ToDo parameterize dbName
# $dbpath = 'c:\temp\MSA\demo3.db'
# Import-DuckDBRecords -Records $Records -TableName 'UAL' -DbPath $dbpath -Verbose
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
        [PSObject]$InputObject,

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
        Write-PSFMessage -Level Verbose -Message "Starting import to table $TableName"
        # Initialize collection to hold records if processing multiple pipeline items
        $records = @()

        # Create output directory and connect to DB based on parameter set
        if ($PSCmdlet.ParameterSetName -eq 'newDB')
        {
            write-psfmessage -level verbose -message "Creating new DuckDB database at $LocalPath\$DbName"
            if (-not (Test-Path -Path $LocalPath -PathType Container))
            {
                New-Item -Path $LocalPath -ItemType Directory -Force | Out-Null
            }
            $dbPath = Join-Path -Path $LocalPath -ChildPath $DbName
            # Create new DuckDB connection
            $conn = New-DuckDBConnection -DB $dbPath
        }
        # For 'ExistingDB' parameter set, $conn is already provided and validated
        else
        {
            Write-PSFMessage -Level Verbose -Message "Using existing DuckDB connection"
        }

        # Initialize duplicate tracking
        $seenIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $uniqueRecords = [System.Collections.Generic.List[object]]::new()
    }

    process
    {
        if ($null -ne $InputObject)
        {
            # For single object input, add to records collection
            $records += $InputObject
            Write-PSFMessage -Level Verbose -Message "Added records to processing queue: $($records.count)"
        }
        else
        {
            Write-PSFMessage -Level Error -Message "Received null input object"
            throw "Null input object"
        }


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
            Write-PSFMessage -Level Verbose -Message "Validating columns for table $TableName"
            $firstRecord = $uniqueRecords[0]
            $columns = @()

            foreach ($prop in $firstRecord.PSObject.Properties)
            {
                $duckdbType = switch -Regex ($prop.TypeNameOfValue)
                {
                    'DateTime' { 'TIMESTAMP' }
                    'Int\d{1,2}' { 'INTEGER' }
                    #'Double' { 'DOUBLE' }
                    'Boolean' { 'BOOLEAN' }
                    default { 'VARCHAR' }
                }
                $cn = ($prop.Name).Replace(' ', '_')
                $columns += "$($cn) $duckdbType"
            }

            $createTableQuery = @"
CREATE OR REPLACE TABLE $TableName ($($columns -join ", "));
"@
            Write-PSFMessage -Level Verbose -Message "Creating table with schema: $createTableQuery"
            $conn.sql($createTableQuery)
            Write-PSFMessage -Level Verbose -Message "Created table $TableName"

            # Batch insert with transaction control
            $counter = 0
            $conn.sql("BEGIN TRANSACTION")
            Write-PSFMessage -Level Verbose -Message "Started transaction"
            foreach ($item in $uniqueRecords)
            {
                # Write-PSFMessage -level verbose -message "Processing record: $($item.ID)"
                # Generate safe SQL values
                $values =
                foreach ($prop in $item.PSObject.Properties)
                {
                    if ([string]::IsNullOrEmpty($prop.Value))
                    {
                        $prop.Value = 'Null'
                    }
                    $prop.Value = $prop.Value.ToString()
                    $p = ($prop.Value).Replace("'", "_")
                    "`'$p`'"
                }

                # Execute insert
                $InsertQuery = @"
INSERT INTO $TableName VALUES ($($values -join ', '))
"@
                Write-PSFMessage -level verbose -message "$insertQuery"
                $conn.sql($InsertQuery)
                $counter++

                # Commit in batches
                if ($counter % $BatchSize -eq 0)
                {
                    $conn.sql("COMMIT")
                    $conn.sql("BEGIN TRANSACTION")
                    Write-PSFMessage -level verbose -message "Committed $counter records"
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

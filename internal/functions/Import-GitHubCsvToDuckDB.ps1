<#
.SYNOPSIS
Imports CSV files from a GitHub repository directory into DuckDB tables.

.DESCRIPTION
This function connects to a GitHub repository, retrieves CSV files from a specified directory,
and creates DuckDB tables from their contents using read_csv_auto.

.PARAMETER Owner
GitHub repository owner/organization name

.PARAMETER Repository
GitHub repository name

.PARAMETER Branch
GitHub branch name (default: main)

.PARAMETER Directory
Directory path within the repository containing CSV files

.PARAMETER LocalPath
Local path to store the DuckDB database file

.PARAMETER DbName
Name of the DuckDB database file (default: demo2.db)


.EXAMPLE
Import-GitHubCsvToDuckDB -Owner "myorg" -Repository "myrepo" -Branch "dev" `
    -Directory "data/csv" -LocalPath "D:\data" -DbName "analysis.db"
#>
function Import-GitHubCsvToDuckDB
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [string]$Repository,
        [Parameter(Mandatory = $false)]
        [string]$Branch = "main",
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [Parameter(Mandatory = $false)]
        [string]$FileType = "*.csv",
        [Parameter(Mandatory = $false, ParameterSetName = 'newDB')]
        [ValidateScript({ Test-Path $_ -IsValid })]
        [string]$LocalPath,
        [Parameter(Mandatory = $false, ParameterSetName = 'newDB')]
        [string]$DbName = "demo2.db",
        [Parameter(Mandatory = $false, ParameterSetName = 'ExistingDB')]
        [ValidateScript({ $_ })]
        [Object]$DBConn
    )

    # Create output directory and connect to DB based on parameter set
    if ($PSCmdlet.ParameterSetName -eq 'newDB')
    {
        if (-not (Test-Path -Path $LocalPath))
        {
            New-Item -Path $LocalPath -ItemType Directory -Force | Out-Null
        }
        $dbPath = Join-Path -Path $LocalPath -ChildPath $DbName
        # Create new DuckDB connection
        $conn = New-DuckDBConnection -DB $dbPath
    }
    # For 'ExistingDB' parameter set, $conn is already provided and validated

    try
    {
        # Get repository contents
        $apiUrl = "https://api.github.com/repos/$Owner/$Repository/contents/$Directory"
        Write-PSFMessage -Level Verbose -Message "Retrieving CSV files from GitHub repository: $apiUrl."

        $headers = @{
            "Accept" = "application/vnd.github.v3+json"
        }

        $contents = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get

        # Filter CSV files
        $csvFiles = $contents | Where-Object { $_.name -like $FileType }

        if (-not $csvFiles)
        {
            Write-PSFMessage -Level Warning -Message  "No CSV files found in the specified directory."
            return
        }

        # Process each CSV file
        foreach ($file in $csvFiles)
        {
            $fileName = $file.name
            $tableName = "'$($fileName -replace '\.csv$' -replace '-','_')'"
            $downloadUrl = $file.download_url

            try
            {
                # Create table from CSV
                $query = @"
CREATE OR REPLACE TABLE $tableName 
AS SELECT * FROM read_csv_auto('$downloadUrl');
"@
                $conn.sql($query)
                Write-PSFMessage -Level Verbose -Message "Successfully created table: $tableName"
            }
            catch
            {
                Write-PSFMessage -Level Error -Message  "Failed to create table $tableName"
            }
        }

        # Show created tables
        $tables = $conn.sql('SELECT * FROM pg_catalog.pg_tables;')
        Write-PSFMessage -Level Verbose -Message "Created tables: $($tables.tablename -join ', ')"
    }
    catch
    {
        Write-PSFMessage -Level Error -Message "Operation failed: $_"
    }
    finally
    {
        if ($PSCmdlet.ParameterSetName -eq 'newDB')
        {
            $conn.Close()
        }
    }
}

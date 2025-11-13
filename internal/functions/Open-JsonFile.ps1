function Open-JsonFile
{
    <#
    .SYNOPSIS
    Opens and parses JSON files with validation and error handling

    .DESCRIPTION
    Accepts file paths or FileInfo objects, validates JSON structure, and returns parsed objects

    .PARAMETER InputObject
    Path to JSON file or FileInfo object

    .EXAMPLE
    Get-ChildItem config.json | Open-JsonFile

    .EXAMPLE
    Open-JsonFile -InputObject "C:\data\settings.json"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("FullName")]
        [ValidateScript({
                if ($_ -is [string]) { Test-Path $_ }
                else { $_.Exists }
            })]
        [ValidatePattern('\.json$')]
        [object]$InputObject,

        [ValidateSet('UTF8', 'Unicode', 'UTF32', 'ASCII')]
        [string]$Encoding = 'UTF8'
    )

    begin
    {
    }

    process
    {
        try
        {
            # Resolve file path
            $filePath = if ($InputObject -is [string])
            {
                $InputObject
            }
            else
            {
                $InputObject.FullName
            }

            # Validate file type
            if (-not (Test-Path -Path $filePath -PathType Leaf))
            {
                throw "Path is not a file: $filePath"
            }

            # Confirm action
            if (-not $PSCmdlet.ShouldProcess($filePath, "Open JSON file"))
            {
                return
            }

            # Read file
            Write-PSFMessage -Level Verbose -Message "Reading file: $filePath"
            $jsonContent = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::$Encoding)

            # Parse JSON
            Write-PSFMessage -Level Verbose -Message "Parsing JSON content"
            $parsedData = $jsonContent | ConvertFrom-Json -Depth 10

            Write-PSFMessage -Level Verbose -Message "Returning $($parsedData.Count) objects"
            return $parsedData
        }
        catch [System.IO.FileNotFoundException]
        {
            Write-PSFMessage -Level Error -Message "File not found: $filePath"
            return $null
        }
        catch [System.Management.Automation.ItemNotFoundException]
        {
            Write-PSFMessage -Level Error -Message "Path invalid: $filePath"
            return $null
        }
        catch [System.ArgumentException]
        {
            Write-PSFMessage -Level Error -Message "Invalid JSON path: $filePath"
            return $null
        }
        catch
        {
            Write-PSFMessage -Level Error -Message "Error processing JSON file: $($_.Exception.Message)" -ErrorRecord $_
            return $null
        }
    }

    end
    {
        Write-PSFMessage -Level Verbose -Message "Operation completed."
    }
}
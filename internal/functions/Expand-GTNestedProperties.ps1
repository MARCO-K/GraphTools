<#
.SYNOPSIS
    Expands nested properties of PSObjects into a flat structure.

.DESCRIPTION
    This function takes PSObjects with nested properties and expands them into a flat structure.
    It processes both base properties and nested array properties, handling different nested object types.

.PARAMETER InputObject
    The PSObject(s) to be processed. This parameter is mandatory and accepts input from the pipeline.

.EXAMPLE
    $input = [PSCustomObject]@{ Name = 'Test'; Properties = @([PSCustomObject]@{ Name = 'Nested'; Value = 'Value' }) }
    $input | Expand-GTNestedProperties

#>
function Expand-GTNestedProperties
{
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [PSObject[]]$InputObject
    )
    begin
    {
        # Initialize collection variables at the function scope
        $allColumns = [ordered]@{}
        $processedData = @()
        $standardizedData = @()
    }

    process
    {
        try
        {
            foreach ($record in $InputObject)
            {
                $output = @{}
                # Process base properties
                $record.PSObject.Properties | Where-Object {
                    $_.TypeNameOfValue -ne 'System.Object[]' -and $_.Name -notmatch '@odata\.type'
                } | ForEach-Object {
                    if ($_.TypeNameOfValue -eq 'System.DateTime')
                    {
                        [string]$output[$_.Name] = $_.Value.ToString('yyyy-MM-ddTHH:mm:ss')
                    }
                    else { $output[$_.Name] = $_.Value }
                }
            
                # Process extented properties
                $record.PSObject.Properties | Where-Object {
                    $_.TypeNameOfValue -eq 'System.Object[]'
                } | ForEach-Object {
                    $nestedValues = $_.Value
                    if ($_.Value.count -eq 0)
                    { 
                        $name = $_.Name 
                        $value = '' 
                        $output[$name] = $value
                    }
                    else
                    {
                        $nestedValues | ForEach-Object {
                            # Handle different nested object types
                            if ($_.PSObject.Properties['Name'] -and $_.PSObject.Properties['Value'])
                            {
                                # Name/Value pair pattern (ExtendedProperties)
                                $name = $_.Name
                                $value = If ($_.Value -gt 0) { $_.Value } Else { '' }
                                $output[$name] = $value
                            }
        
                        }
                    }
        
                }
                $processedData += $output 
                # Collect all possible columns across all items
                foreach ($key in $output.Keys)
                {
                    $allColumns[$key] = $true
                }
                
            }
            
        }
        catch
        {
            Write-PSFMessage -Level Error -Message "Error processing record $($record.Id): $_"
            continue
        }
    }
    end
    {
        # Ensure every item has all columns (fill missing ones with $null)
        $standardizedData = foreach ($item in $processedData)
        {
            $row = @{}
            foreach ($col in $allColumns.Keys)
            {
                $row[$col] = if ($item.ContainsKey($col)) { $item[$col] } else { $null }
            }
            [pscustomobject]$row
        }

        # Return the final result
        return $standardizedData
    }
}
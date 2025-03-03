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

    process
    {
        foreach ($record in $InputObject)
        {
            $output = [ordered]@{}

            # Process base properties
            #Write-Verbose "Processing base properties"
            $record.PSObject.Properties | Where-Object {
                $_.TypeNameOfValue -ne 'System.Object[]'
            } | ForEach-Object {
                #Write-Verbose "Processing property: $($_.Name)"
                $output[$_.Name] = $_.Value
            }

            # Process nested array properties
            #write-verbose "Processing nested array properties"
            $record.PSObject.Properties | Where-Object {
                $_.TypeNameOfValue -eq 'System.Object[]' -and $_.Value.Count -gt 0
            } | ForEach-Object {
                #Write-Verbose "Processing property: $($_.Name)"
                $nestedValues = $_.Value
                $nestedValues | ForEach-Object {
                    # Handle different nested object types
                    if ($_.PSObject.Properties['Name'] -and $_.PSObject.Properties['Value'])
                    {
                        # Name/Value pair pattern (ExtendedProperties)
                        #Write-Verbose "Processing property: $($_.Name) with $($_.Value)"
                        $name = $_.Name
                        $value = $_.Value
                    }
                    # add output
                    $output[$name] = $value
                }
            }
            [PSCustomObject]$output
        }
    }
}
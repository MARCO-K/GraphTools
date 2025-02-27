function Expand-NestedProperties
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
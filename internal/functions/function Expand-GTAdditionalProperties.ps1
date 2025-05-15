function Expand-GTAdditionalProperties
{
    <#
    .SYNOPSIS
    Expands the 'AdditionalProperties' hash property to the main object (flattens object).

    .DESCRIPTION
    Expands the 'AdditionalProperties' hash property to the main object (flattens object).
    By default, it is returned by commands like Get-MgDirectoryObjectById, Get-MgGroupMember, etc.

    .PARAMETER InputObject
    Object returned by Mg* command that contains 'AdditionalProperties' property.

    .PARAMETER Force
    Overwrites existing properties on the InputObject if they conflict with keys in AdditionalProperties.

    .EXAMPLE
    Get-MgGroupMember -GroupId 8ec67d38-82df-4683-b286-4896a73b8a6a | Expand-GTAdditionalProperties

    .EXAMPLE
    Get-MgDirectoryObjectById -ids 8ec67d38-82df-4683-b286-4896a73b8a6a | Expand-GTAdditionalProperties -Force
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [object] $InputObject,

        [switch] $Force
    )

    process
    {
        if ($InputObject.AdditionalProperties -is [System.Collections.IDictionary])
        {
            foreach ($item in $InputObject.AdditionalProperties.GetEnumerator())
            {
                $key = $item.Key
                $value = $item.Value

                # Add properties from AdditionalProperties
                $params = @{
                    MemberType  = 'NoteProperty'
                    Name        = $key
                    Value       = $value
                    ErrorAction = 'Stop'
                }
                if ($Force) { $params['Force'] = $true }

                try
                {
                    $InputObject | Add-Member @params
                    Write-Verbose "Added property '$key' to the pipeline object"
                }
                catch
                {
                    if ($_.Exception.Message -like "*already exists*")
                    {
                        Write-Verbose "Property '$key' already exists. Use -Force to overwrite."
                    }
                    else
                    {
                        Write-Error $_
                    }
                }

                # Handle '@odata.type' to extract ObjectType
                if ($key -eq '@odata.type')
                {
                    $objectTypeValue = $value -replace '^#microsoft\.graph\.', ''
                    $params['Name'] = 'ObjectType'
                    $params['Value'] = $objectTypeValue

                    try
                    {
                        $InputObject | Add-Member @params
                        Write-Verbose "Added property 'ObjectType' to the pipeline object"
                    }
                    catch
                    {
                        if ($_.Exception.Message -like "*already exists*")
                        {
                            Write-Verbose "Property 'ObjectType' already exists. Use -Force to overwrite."
                        }
                        else
                        {
                            Write-Error $_
                        }
                    }
                }
            }

            # Output object without AdditionalProperties
            $InputObject | Select-Object -Property * -ExcludeProperty AdditionalProperties
        }
        else
        {
            Write-Verbose "Input object does not contain an 'AdditionalProperties' dictionary."
            $InputObject
        }
    }
}
$script:GTValidationRegex = @{
    UPN = '^[^@\s]+@[^@\s]+\.[^@\s]+$'
    GUID = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    # Audit log Operations and RecordTypes: alphanumeric, underscore, hyphen only (no injection characters)
    AuditLogFilterValue = '^[a-zA-Z0-9_\-]+$'
    # Properties: alphanumeric, dots (for nested properties), underscore only
    AuditLogProperty = '^[a-zA-Z0-9_.]+$'
}

<#
.SYNOPSIS
    Validates that a string is a properly formatted GUID
.DESCRIPTION
    Tests whether a given string matches the standard GUID format (8-4-4-4-12 hexadecimal pattern).
    This function should be used before interpolating IDs into OData filter strings to prevent
    potential injection attacks.
    
    The function uses both regex validation and .NET Guid.TryParse for comprehensive validation.
.PARAMETER InputObject
    The string to validate as a GUID. Can be a single string or array of strings.
.PARAMETER Quiet
    When specified, returns $true/$false instead of throwing an error for invalid GUIDs.
.OUTPUTS
    System.Boolean
    Returns $true if the input is a valid GUID, $false otherwise (when -Quiet is used).
    Throws an error if the input is not a valid GUID (when -Quiet is not used).
.EXAMPLE
    Test-GTGuid -InputObject '12345678-1234-1234-1234-123456789abc'
    
    Returns $true if the GUID is valid
.EXAMPLE
    Test-GTGuid -InputObject 'not-a-guid'
    
    Throws an error for invalid GUID
.EXAMPLE
    Test-GTGuid -InputObject 'not-a-guid' -Quiet
    
    Returns $false for invalid GUID without throwing an error
.EXAMPLE
    if (Test-GTGuid -InputObject $userId -Quiet) {
        # Safe to use $userId in OData filter
        $filter = "principalId eq '$userId'"
    }
#>
function Test-GTGuid
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$InputObject,

        [Parameter()]
        [switch]$Quiet
    )

    begin
    {
        # Use the script-scoped regex to ensure a single source of truth
        $strictGuidRegex = $script:GTValidationRegex.GUID
    }

    process
    {
        foreach ($item in $InputObject)
        {
            # 1. Strict format validation for OData safety
            $regexMatch = $item -match $strictGuidRegex
            
            # 2. Definitive logical validation
            $guidRef = [ref][Guid]::Empty
            $parseSuccess = [Guid]::TryParse($item, $guidRef)
            
            # A GUID is only valid for our purposes if BOTH checks pass.
            $isValid = $regexMatch -and $parseSuccess
            
            if (-not $isValid -and -not $Quiet)
            {
                # Use a terminating error to stop the pipeline if an invalid GUID is found
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.FormatException]::new("Invalid canonical GUID format: '$item'. A strict, hyphenated format is required for security."),
                        'InvalidGuidFormat',
                        [System.Management.Automation.ErrorCategory]::InvalidData,
                        $item
                    )
                )
            }

            if ($isValid -or $Quiet) { Write-Output $isValid }
        }
    }
}
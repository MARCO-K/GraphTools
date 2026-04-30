function New-GTODataFilter {
    <#
    .SYNOPSIS
    Builds a normalized OData filter string.

    .DESCRIPTION
    Accepts one or more potential OData clause strings, removes null/empty values,
    and joins remaining clauses with the provided logical operator.

    .PARAMETER Clauses
    Candidate OData clause strings.

    .PARAMETER JoinOperator
    Logical operator used to join clauses. Defaults to 'and'.

    .OUTPUTS
    System.String

    .EXAMPLE
    New-GTODataFilter -Clauses @("userType eq 'Guest'", "accountEnabled eq false")
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Clauses,

        [ValidateSet('and', 'or')]
        [string]$JoinOperator = 'and'
    )

    $normalizedClauses = [System.Collections.Generic.List[string]]::new()
    foreach ($clause in $Clauses) {
        if (-not [string]::IsNullOrWhiteSpace($clause)) {
            [void]$normalizedClauses.Add($clause.Trim())
        }
    }

    if ($normalizedClauses.Count -eq 0) {
        return ''
    }

    return ($normalizedClauses -join " $JoinOperator ")
}

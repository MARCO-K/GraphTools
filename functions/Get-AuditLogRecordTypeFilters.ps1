function Get-AuditLogRecordTypeFilters
{
    [CmdletBinding()]
    param(
        [ValidateSet('v1.0', 'beta')]
        [string]$ApiVersion = "beta"
    )

    # Official Microsoft documented record types (as of latest update)
    $documentedTypes = @(
        "AzureActiveDirectory",
        "AzureActiveDirectoryAccountLogon",
        "AzureActiveDirectoryStsLogon",
        "ComplianceDLPSharePoint",
        "ComplianceDLPExchange",
        "ComplianceDLPSharePointClassification",
        "ExchangeAdmin",
        "ExchangeItem",
        "ExchangeItemGroup",
        "SharePoint",
        "SharePointFileOperation",
        "General",
        "DataLossPrevention",
        "PowerBIAudit",
        "TeamsAdmin",
        "TeamsCommunication",
        "ThreatIntelligence",
        "ThreatIntelligenceUrl",
        "ThreatIntelligenceFile",
        "SecurityComplianceCenterEOPCmdlet",
        "SecurityComplianceUserChange"
    )

    try
    {
        # Attempt to get dynamic values from metadata
        $metadata = Invoke-RestMethod -Uri "https://graph.microsoft.com/$ApiVersion/`$metadata"
        $recordTypes = ($metadata.'#text' | 
            Select-String '<EnumType Name="AuditLogRecordType".*?>.*?</EnumType>' -AllMatches).Matches.Value | 
        ForEach-Object {
                ([xml]$_).EnumType.Member | 
            Select-Object -ExpandProperty Name
        }

        if ($recordTypes)
        {
            $recordTypes
        }
        else
        {
            Write-Warning "Could not parse metadata, returning documented types"
            $documentedTypes
        }
    }
    catch
    {
        Write-Warning "Metadata request failed ($_), returning documented types"
        $documentedTypes
    }
}

# Usage examples:
#$allRecordTypes = Get-AuditLogRecordTypeFilters
#$allRecordTypes | Format-Table
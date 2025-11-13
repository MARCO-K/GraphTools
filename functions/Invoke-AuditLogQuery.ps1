<#
.SYNOPSIS
Retrieves and processes Microsoft 365 audit logs through the Graph API.

.DESCRIPTION
This function queries Microsoft 365 audit logs, waits for completion, processes results,
and optionally cleans up the query job. It supports filtering by date range, operations,
record types, user IDs, and IP addresses.

.PARAMETER Scopes
Required Microsoft Graph permissions. Defaults to all AuditLogsQuery permissions.

.PARAMETER StartDays
Number of days back to start the search. The maximum value is 30. Defaults to 7.

.PARAMETER EndDays
Number of days forward from the start date to end the search. Defaults to 0.

.PARAMETER Delete
A switch to delete the audit query job after completion. Defaults to $true.

.PARAMETER Operations
An array of operations to filter the audit logs.

.PARAMETER RecordType
An array of record types to filter the audit logs.

.PARAMETER UserIds
An array of user IDs to filter the audit logs.

Aliases: Users, UPN, UserPrincipalName, UserName, UPNName

.PARAMETER IpAddresses
An array of IP addresses to filter the audit logs.

.PARAMETER Properties
An array of properties to return in the results.

.PARAMETER maxWaitMinutes
The maximum time in minutes to wait for the query to complete. Defaults to 10.

.PARAMETER sleepSeconds
The time in seconds to wait between query status checks. Defaults to 30.

.EXAMPLE
# Retrieve audit logs for file deletions in the last 7 days
Invoke-AuditLogQuery -Operations "FileDeleted"

.EXAMPLE
# Retrieve audit logs for a specific user in the last 30 days and keep the query job
Invoke-AuditLogQuery -UserIds "user@contoso.com" -StartDays 30 -Delete:$false

.EXAMPLE
# Retrieve audit logs for a user using the UPN alias
Invoke-AuditLogQuery -UPN "user@contoso.com" -StartDays 7

.EXAMPLE
# Retrieve audit logs for multiple users using the Users alias
Invoke-AuditLogQuery -Users "user1@contoso.com","user2@contoso.com" -StartDays 14

.EXAMPLE
# Retrieve audit logs from a specific IP address and select specific properties
Invoke-AuditLogQuery -IpAddresses "192.168.1.1" -Properties "Id","Operation","UserId","auditData"
#>
function Invoke-AuditLogQuery
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$RequieredScopes = @('AuditLogsQuery-CRM.Read.All', 'AuditLogsQuery-Endpoint.Read.All', 'AuditLogsQuery-Exchange.Read.All', 'AuditLogsQuery-OneDrive.Read.All', 'AuditLogsQuery-SharePoint.Read.All', 'AuditLogsQuery.Read.All'),

        [Parameter(Mandatory = $false)]
        [switch]$NewSession,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$StartDays = 7,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$EndDays = 0,

        [Parameter(Mandatory = $false)]
        [switch]$Delete,

        [Parameter(Mandatory = $false)]
        [array]$Operations,

        [Parameter(Mandatory = $false)]
        [array]$RecordType,

        [Parameter(Mandatory = $false)]
        [ValidateScript({$_ -match $script:GTValidationRegex.UPN})]
        [Alias('Users','UPN','UserPrincipalName','UserName','UPNName')]
        [array]$UserIds,

        [Parameter(Mandatory = $false)]
        [array]$IpAddresses,

        [Parameter(Mandatory = $false)]
        [array]$Properties = @('Id', 'createdDateTime', 'auditLogRecordType', 'Operation', 'service', 'UserId', 'UserType', 'userPrincipalName', 'auditData'),

        [Parameter(Mandatory = 'False')]
        [OutputType('PSCustomObject')]

        [Parameter(Mandatory = $false)]
        [int]$maxWaitMinutes = 10,

        [Parameter(Mandatory = $false)]
        [int]$sleepSeconds = 30
    )

    begin
    {
        # Module Management
        $modules = ('Microsoft.Graph.Authentication')
        Install-GTRequiredModule -ModuleNames $modules

        # Validate date range
        if ($StartDays -gt 30) {
            Write-Warning "The maximum value for StartDays is 30. Please select a smaller value."
            $StartDays = 30
        }

        if ($StartDays -lt $EndDays) {
            throw "Start date must be before end date."
        }


        # Connect to Microsoft Graph
        if ($NewSession)
        {
            Write-PSFMessage -Level 'Verbose' -Message 'Closing existing Microsoft Graph session.'
            Disconnect-MgGraph -ErrorAction SilentlyContinue
        }

        $session = Test-GTGraphScopes -RequiredScopes $RequiredScopes -Reconnect -Quiet
        if (-not $session)
        {
            throw "Graph connection failed: Required scopes not available"
        }
        Write-PSFMessage -Level 'Verbose' -Message 'Connected to Microsoft Graph and required scopes are available.'

        # Configure request context
        Set-MgRequestContext -MaxRetry 10 -RetryDelay 15
    }

    process
    {
        try
        {
            # Region: Query Setup
            # ----------------------------------
            $filterExpression = @{
                "filterStartDateTime" = (Get-Date).AddDays(-$StartDays).ToString("s")
                "filterEndDateTime"   = (Get-Date).AddDays($EndDays).ToString("s")
            }
            if ($Operations) { $filterExpression.Add("OperationFilters", $Operations) }
            if ($RecordType) { $filterExpression.Add("RecordTypeFilters", $RecordType) }
            if ($UserIds) { $filterExpression.Add("userIdsFilters", $UserIds) }
            if ($IpAddresses) { $filterExpression.Add("ipAddressFilters", $IpAddresses) }

            $queryParams = @{
                "@odata.type" = "#microsoft.graph.security.auditLogQuery"
                "displayName" = "Audit Job created at $(Get-Date)"
                "filter"      = $filterExpression | ConvertTo-Json -Compress
            }

            # Region: Query Execution
            # ----------------------------------
            Write-PSFMessage -Level Verbose -Message "Submitting audit query..."
            Write-PSFMessage -Level Verbose -Message "Query parameters: $($queryParams | ConvertTo-Json)"
            $auditJob = Invoke-MgGraphRequest -Uri 'https://graph.microsoft.com/beta/security/auditLog/queries/' `
                -Method POST `
                -Body ($queryParams | ConvertTo-Json)

            # Region: Query Monitoring
            # ----------------------------------
            $uri = ("/beta/security/auditLog/queries/{0}" -f $AuditJob.Id)
            $status = $null
            $attempt = 1

            do
            {
                $response = Invoke-MgGraphRequest -Uri $uri -Method GET
                $status = $response.status

                Write-PSFMessage -Level Verbose -Message "Query status: $status (Attempt $attempt)"

                if ($status -ne 'succeeded')
                {
                    $attempt++
                    Start-Sleep -Seconds $sleepSeconds
                }

                if (($attempt * $sleepSeconds) -gt ($maxWaitMinutes * 60))
                {
                    throw "Query did not complete within $maxWaitMinutes minutes"
                }
            } while ($status -ne 'succeeded')

            # Region: Results Processing
            # ----------------------------------
            Write-PSFMessage -Level Verbose -Message "Collecting results..."
            $records = [System.Collections.Generic.List[object]]::new()
            $resultsUri = "/beta/security/auditLog/queries/$($auditJob.Id)/records"

            do
            {
                $response = Invoke-MgGraphRequest -Uri $resultsUri -Method GET
                $records.AddRange($response.value)
                $resultsUri = $response.'@odata.nextLink'

                Write-PSFMessage -Level Verbose -Message "Retrieved $($records.Count) records so far..."
            } while ($null -ne $resultsUri)

            # Region: Data Transformation
            # ----------------------------------
            $processedResults = foreach ($entry in $records) {
                $props = [ordered] @{}
                foreach ($prop in $Properties) {
                    $value = $entry
                    foreach ($segment in ($prop -split '\.')) {
                        $value = $value.$segment
                        if ($null -eq $value) { break }
                    }
                    $props[$prop] = $value
                }
                $obj = New-Object -TypeName PSCustomObject -Property $props
                $obj.PSObject.TypeNames.Insert(0, "GraphTools.AuditLogRecord")
                $obj
            }

            # Region: Cleanup
            # ----------------------------------
            if ($Delete)
            {
                Write-PSFMessage -Level Verbose -Message "Cleaning up audit query..."
                Invoke-MgGraphRequest -Uri $uri -Method DELETE | Out-Null
            }

            # Output results
            $processedResults
        }
        catch
        {
            Write-PSFMessage -Level Error -Message "Audit log operation failed: $_"
            throw
        }
    }

    end
    {
        Write-PSFMessage -Level Verbose -Message "Audit log processing completed"
    }
}
<#
.SYNOPSIS
Retrieves and processes Microsoft 365 audit logs through the Graph API.

.DESCRIPTION
This function queries Microsoft 365 audit logs, waits for completion, processes results, 
and optionally cleans up the query job.

.PARAMETER Scopes
Required Microsoft Graph permissions (default: AuditLogsQuery.Read.All)

.PARAMETER StartDays
Number of days back to start the search (default: 7)

.PARAMETER EndDays
Number of days forward from start for end date (default: 1)

.PARAMETER Delete
Switch to delete the audit query job after completion (default: true)

.PARAMETER Operations
Array of operations to filter

.PARAMETER RecordType
Array of record types to filter

.PARAMETER Properties
Array of properties to return in results

.PARAMETER maxWaitMinutes
Maximum time to wait for query completion (default: 10)

.PARAMETER sleepSeconds
Time to wait between query status checks (default: 30)

.EXAMPLE
New-AuditLogQuery -Start 30 -End 0 -Operations "FileDeleted" -Properties "Id","Operation","UserId"

.EXAMPLE
New-AuditLogQuery -Scopes "AuditLog.Read.All" -Delete:$false -Verbose
#>
function New-AuditLogQuery
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
        [array]$Operations = @(),
        
        [Parameter(Mandatory = $false)]
        [array]$RecordType = @(),
        
        [Parameter(Mandatory = $false)]
        [array]$Properties = @('Id', 'createdDateTime', 'auditLogRecordType', 'Operation', 'service', 'UserId', 'UserType', 'userPrincipalName', 'auditData'),

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
        if (-not $Enddays)
        {
            $EndDays = 0
        }
        if (-not $StartDays)
        {
            $StartDays = 30
        }


        # Connect to Microsoft Graph
        try
        {
            if ($NewSession) 
            { 
                Write-PSFMessage -Level 'Verbose' -Message 'Close existing Microsoft Graph session.'
                Disconnect-MgGraph -ErrorAction SilentlyContinue 
            }
            
            $session = Test-GTGraphScopes -RequiredScopes $RequieredScopes -Reconnect -Quiet
            if ($session)
            {
                Write-PSFMessage -Level 'Verbose' -Message 'Connected to Microsoft Graph and required scopes are available.'
            }
            else
            {
                throw "Graph connection failed: $_"
            }

        }
        catch
        {
            Write-PSFMessage -Level 'Error' -Message 'Failed to connect to Microsoft Graph.'
            throw "Graph connection failed: $_"
        }

        # Configure request context
        Set-MgRequestContext -MaxRetry 10 -RetryDelay 15
    }

    process
    {
        try
        {
            # Region: Query Setup
            # ----------------------------------
            $queryParams = @{
                "@odata.type"       = "#microsoft.graph.security.auditLogQuery"
                displayName         = "Audit Job created at $(Get-Date)"
                filterStartDateTime = (Get-Date).AddDays(-$StartDays).ToString("s")
                filterEndDateTime   = (Get-Date).AddDays($EndDays).ToString("s")
            }

            if ($Operations) { $queryParams.Add("OperationFilters", $Operations) }
            if ($RecordType) { $queryParams.Add("RecordTypeFilters", $RecordType) }

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
            $records = @()
            $resultsUri = "/beta/security/auditLog/queries/$($auditJob.Id)/records"
            
            do
            {
                $response = Invoke-MgGraphRequest -Uri $resultsUri -Method GET
                $records += $response.value
                $resultsUri = $response.'@odata.nextLink'
                
                Write-PSFMessage -Level Verbose -Message "Retrieved $($records.Count) records so far..."
            } while ($null -ne $resultsUri)

            # Region: Data Transformation
            # ----------------------------------
            $processedResults = foreach ($entry in $records)
            {
                $props = [ordered]@{}
                
                foreach ($prop in $Properties)
                {
                    $value = $entry
                    foreach ($segment in ($prop -split '\.'))
                    {
                        $value = $value.$segment
                        if ($null -eq $value) { break }
                    }
                    $props[$prop] = $value
                }
                [PSCustomObject]$props
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


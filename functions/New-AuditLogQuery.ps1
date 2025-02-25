function New-AuditLogQuery
{
    [CmdletBinding()]
    param (
        [string[]]$Scopes = ('AuditLogsQuery.Read.All'),
        [int]$Start = 7,
        [int]$End = 1,
        [switch]$delete,
        [array]$Operations,
        [ValidateSet('AzureActiveDirectory', 'SharePoint', 'Exchange', 'General', 'DLP', 'ThreatIntelligence', 'CloudAppSecurity', 'PowerBI', 'Teams', 'SecurityComplianceCenter', 'Viva Engage', 'InformationBarriers', 'Project', 'SharePointFileOperation', 'SharePointSharingOperation', 'SharePointPageOperation')][string[]]$RecordType,
        [array]$Properties = @('Id', 'CreationTime', 'Operation', 'UserId', 'UserType', 'ClientIP', 'Workload', 'RecordType', 'OrganizationId', 'ObjectId')
    )

    begin
    {
        Write-Verbose "Starting New-AuditLogQuery function"
        if (Get-MgContext)
        {
            Write-Verbose "Using existing connection"
        }
        else
        {
            Write-Verbose "Connecting to Microsoft Graph"
            Connect-MgGraph -Scopes $Scopes -NoWelcome
        }

        # Set retry policy
        Set-MgRequestContext -MaxRetry 10 -RetryDelay 15
    }

    process
    {
        # Collect query informations
        $AuditQueryName = ("Audit Job created at {0}" -f (Get-Date))
        $StartDate = (Get-Date).AddDays(-$Start)
        $EndDate = (Get-Date).AddDays($End)
        $AuditQueryStart = (Get-Date $StartDate -format s)
        $AuditQueryEnd = (Get-Date $EndDate -format s)
        $AuditQueryParameters = @{}
        $AuditQueryParameters.Add("@odata.type", "#microsoft.graph.security.auditLogQuery")
        $AuditQueryParameters.Add("displayName", $AuditQueryName)
        if ($Operations)
        {
            $AuditQueryParameters.Add("OperationFilters", $Operations)
        }
        if ($RecordType)
        {
            $AuditQueryParameters.Add("RecordTypeFilters", $RecordType)
        }
        $AuditQueryParameters.Add("filterStartDateTime", $AuditQueryStart)
        $AuditQueryParameters.Add("filterEndDateTime", $AuditQueryEnd)

        # Submit the audit query
        $URI = '/beta/security/auditLog/queries/'
        $AuditJob = Invoke-MgGraphRequest -Uri $Uri -Method POST -Body $($AuditQueryParameters | ConvertTo-Json)

        # Check the audit query status every 30 seconds until it completes
        [int]$i = 1
        [int]$SleepSeconds = 30
        [int]$SecondsElapsed = 0
        $SearchFinished = $false
        Write-Verbose "Checking audit query status..."
        Start-Sleep -Seconds $SecondsElapsed
        $Uri = '/beta/security/auditLog/queries/' + $AuditJob.Id
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET
        $AuditQueryStatus = $response.status
        Write-Verbose ("Waiting for audit search to complete. Check {0} after {1} seconds. Current state {2}" -f $i, $SecondsElapsed, $AuditQueryStatus)
        While ($SearchFinished -eq $false)
        {
            $i++
            Write-Verbose ("Waiting for audit search to complete. Check {0} after {1} seconds. Current state {2}" -f $i, $SecondsElapsed, $AuditQueryStatus)
            If ($AuditQueryStatus -eq 'succeeded')
            {
                $SearchFinished = $true
            }
            Else
            {
                Start-Sleep -Seconds $SleepSeconds
                $SecondsElapsed = $SecondsElapsed + $SleepSeconds
                $response = Invoke-MgGraphRequest -Uri $Uri -Method GET
                $AuditQueryStatus = $response.status
            }
        }

        # collect the results
        $uri = ("/beta/security/auditLog/queries/{0}/records" -f $AuditJob.Id)
        [array]$SearchRecords = Invoke-MgGraphRequest -Uri $Uri -Method GET
        $AuditRecords = $SearchRecords.value
        Write-Verbose ("{0} audit records fetched so far..." -f $AuditRecords.count)
        # Paginate to fetch all available audit records
        $NextLink = $SearchRecords.'@Odata.NextLink'
        While ($null -ne $NextLink)
        {
            #$SearchRecords = $null
            [array]$SearchRecords = Invoke-MgGraphRequest -Uri $NextLink -Method GET
            $AuditRecords += $SearchRecords.value
            Write-Verbose ("{0} audit records fetched so far..." -f $AuditRecords.count)
            $NextLink = $SearchRecords.'@odata.NextLink'
        }

        # Select the properties to display
        $Records = @()
        if ($Properties)
        {
            $Records = $AuditRecords.auditData | Select-Object -Property $Properties
        }
        else
        {
            $Records = $AuditRecords.auditData
        }


        # Process results and create custom objects
        $results =
        foreach ($entry in $Records)
        {
            $props = [ordered]@{}

            # Dynamically map properties from API response
            foreach ($prop in $Properties)
            {
                # Handle nested properties using dot notation
                $propPath = $prop -split '\.'
                $value = $entry
                foreach ($segment in $propPath)
                {
                    $value = $value.$segment
                    if ($null -eq $value)
                    {
                        break
                    }
                }
                $props[$prop] = $value
            }
            # Create the custom object
            [PSCustomObject]$props
        }

        $results
    }

    end
    {
        # Delete the audit query
        if ($delete)
        {
            $Uri = ("/beta/security/auditLog/queries/{0}" -f $AuditJob.Id)
            $result = Invoke-MgGraphRequest -Uri $Uri -Method 'DELETE'
            Write-Verbose "Audit query deleted."
            $result.value
        }
        Write-Verbose "New-AuditLogQuery function completed"
    }
}

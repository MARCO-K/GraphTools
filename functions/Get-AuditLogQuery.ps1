
[string[]]$Scopes = ('AuditLogsQuery.Read.All')
[int]$Start = 7
[int]$end = 1

Connect-MgGraph -NoWelcome -Scopes $Scopes
Get-MgContext

Get-MgRequestContext
Set-MgRequestContext -MaxRetry 10 -RetryDelay 15
$AuditQueryName = ("Audit Job created at {0}" -f (Get-Date))
$StartDate = (Get-Date).AddDays(-$start)
$EndDate = (Get-Date).AddDays($End)
$AuditQueryStart = (Get-Date $StartDate -format s)
$AuditQueryEnd = (Get-Date $EndDate -format s)
[array]$AuditQueryOperations = "FileModified", "FileUploaded"
$AuditQueryParameters = @{}
$AuditQueryParameters.Add("@odata.type", "#microsoft.graph.security.auditLogQuery")
$AuditQueryParameters.Add("displayName", $AuditQueryName)
$AuditQueryParameters.Add("OperationFilters", $AuditQueryOperations)
$AuditQueryParameters.Add("filterStartDateTime", $AuditQueryStart)
$AuditQueryParameters.Add("filterEndDateTime", $AuditQueryEnd)

# Submit the audit query
$AuditJob = New-MgBetaSecurityAuditLogQuery -BodyParameter $AuditQueryParameters

# Check the audit query status every 20 seconds until it completes
[int]$i = 1
[int]$SleepSeconds = 20
$SearchFinished = $false
[int]$SecondsElapsed = 20
Write-Host "Checking audit query status..."
Start-Sleep -Seconds 30
#$AuditQueryStatus = Get-MgBetaSecurityAuditLogQuery -AuditLogQueryId $AuditJob.Id
$uri = 'https://graph.microsoft.com/beta/security/auditLog/queries/' + $AuditJob.Id
$response = Invoke-MgGraphRequest -Uri $Uri -Method GET
$AuditQueryStatus = $response.status

While ($SearchFinished -eq $false)
{
    $i++
    Write-Host ("Waiting for audit search to complete. Check {0} after {1} seconds. Current state {2}" -f $i, $SecondsElapsed, $AuditQueryStatus.status)
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

##[array]$AuditRecords = Get-MgBetaSecurityAuditLogQueryRecord -AuditLogQueryId $AuditJob.Id -All -PageSize 999
$Uri = ("https://graph.microsoft.com/beta/security/auditLog/queries/{0}/records" -f $AuditJob.Id)
[array]$SearchRecords = Invoke-MgGraphRequest -Uri $Uri -Method GET
$AuditRecords = $SearchRecords.value
# Paginate to fetch all available audit records
$NextLink = $SearchRecords.'@Odata.NextLink'
While ($null -ne $NextLink)
{
    $SearchRecords = $null
    [array]$SearchRecords = Invoke-MgGraphRequest -Uri $NextLink -Method GET 
    $AuditRecords += $SearchRecords.value
    Write-Host ("{0} audit records fetched so far..." -f $AuditRecords.count)
    $NextLink = $SearchRecords.'@odata.NextLink' 
}

$AuditRecords.auditData | ForEach-Object {
    [PSCustomObject]@{
        Workload         = $_.Workload
        Id               = $_.Id
        CreationDateTime = $_.CreationDateTime
        EventSource      = $_.EventSource
        SourceFileName   = $_.SourceFileName
        Operation        = $_.Operation
    } }





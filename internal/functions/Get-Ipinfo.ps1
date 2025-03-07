function Get-Ipinfo
{
    <#
    .SYNOPSIS
    Retrieves IP information from IP addresses using the IPInfo API.

    .DESCRIPTION
    Retrieves detailed geolocation and network information for IP addresses using the IPInfo API,
    returning structured objects with consistent properties including a unique ID for each result.

    .PARAMETER AddressList
    List of IP addresses to query. Accepts both pipeline input and array input.

    .PARAMETER Token
    API token for IPInfo authentication. Recommended to use a secure string.

    .PARAMETER Fields
    Comma-separated list of fields to retrieve from the API.

    .EXAMPLE
    Get-Ipinfo -Token 'your-api-token' -AddressList '8.8.8.8', '1.1.1.1'
    
    .EXAMPLE
    '8.8.8.8', '1.1.1.1' | Get-Ipinfo -Token 'your-api-token'
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('IPAddress', 'FullName')]
        [ValidateScript({
                if ($_ -match '^(\d{1,3}\.){3}\d{1,3}$|^([\da-fA-F]{0,4}:){2,7}[\da-fA-F]{0,4}$') { $true }
                else { throw "Invalid IP address format: $_" }
            })]
        [string[]]$AddressList,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [string]$Fields = 'ip,hostname,anycast,city,region,country,country_name,loc,org,postal,timezone'
    )
    
    begin
    {
        # Initialize counters and containers
        $ipCounter = 0
        $uniqueIPs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $results = [System.Collections.Generic.List[PSObject]]::new()


    
        $ipinfoPath = "$env:LOCALAPPDATA\ipinfo\ipinfo.exe"
        if (-not (Test-Path $ipinfoPath))
        {
            Write-PSFMessage -Level Error -Message "IPInfo executable not found: $ipinfoPath"
            throw "IPInfo executable not found: $ipinfoPath"
        }
    
        Write-PSFMessage -Level Verbose -Message "Starting IP info retrieval for $($AddressList.Count) unique IP addresses"
    }
    
    process
    {
        try
        {
            Write-PSFMessage -Level Verbose -Message "Executing IPInfo command"
            foreach ($ip in $AddressList)
            {
                # Skip duplicates and invalid IPs
                if (-not $uniqueIPs.Add($ip))
                {
                    Write-Verbose "Skipping duplicate IP: $ip"
                    continue
                }
            }

            Write-PSFMessage -Level Verbose -Message "Processing $($uniqueIPs.count) IP records"
            # Execute IPInfo CLI
            $cliArgs = @('-t', $Token, '-f', $Fields, '-j')
            $rawResult = $uniqueIPs | & $ipinfoPath $cliArgs

            # Explicit UTF-8 conversion
            $resultData = $rawResult | ConvertFrom-Csv -Delimiter ','

            # Process each result
            foreach ($data in $resultData)
            {
                $ipCounter++
                [PSCustomObject]@{
                    ID           = $ipCounter
                    ASN          = ($data.org -split ' ', 2)[0] -replace 'AS' -as [int]
                    Organization = ($data.org -split ' ', 2)[1].Trim()
                    IP           = [System.Net.IPAddress]$data.ip
                    Hostname     = $data.hostname
                    Anycast      = [System.Convert]::ToBoolean($data.anycast)
                    City         = $data.city
                    Region       = $data.region
                    Country      = $data.country
                    CountryName  = $data.country_name
                    Location     = $data.loc
                    PostalCode   = $data.postal
                    Timezone     = $data.timezone
                    Latitude     = ($data.loc -split ',')[0] -as [double]
                    Longitude    = ($data.loc -split ',')[1] -as [double]
                } 
            }
        }
        catch
        {
            Write-PSFMessage -Level Error -Message "Failed to process IP $ip : $($_.Exception.Message)"
            continue
        }
    }
    
    end
    {
        Write-PSFMessage -Level Verbose -Message "IP info retrieval completed successfully"
        # Output results
        $results
    }
}
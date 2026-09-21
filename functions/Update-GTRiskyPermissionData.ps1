function Update-GTRiskyPermissionData
{
    <#
    .SYNOPSIS
    Updates the local Microsoft Graph permissions metadata cache from Microsoft DevX content.

    .DESCRIPTION
    Fetches the latest permissions schema from the official microsoft-graph-devx-content repository,
    extracts privilege levels for Application and DelegatedWork schemes, and compiles an optimized
    offline fixture into data/graph-permissions.json. Compatible with Windows PowerShell 5.1 and
    PowerShell 7+.

    .PARAMETER OutputPath
    Custom path to write the compiled JSON metadata. Defaults to data/graph-permissions.json in the module.

    .PARAMETER SourceUri
    Custom URL to fetch the raw permissions JSON from. Defaults to the official Microsoft DevX repository.

    .PARAMETER Force
    Overwrites the existing fixture file without prompting.

    .OUTPUTS
    [PSCustomObject] Summary report of the update operation.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param (
        # Optional destination file path
        [string]$OutputPath,

        # Optional source URI for permissions metadata
        [string]$SourceUri = 'https://raw.githubusercontent.com/microsoftgraph/microsoft-graph-devx-content/master/permissions/new/permissions.json',

        # Overwrite existing file without confirmation
        [switch]$Force
    )

    process
    {
        $targetPath = if ($OutputPath) { $OutputPath } else {
            $moduleBase = if ($script:ModuleRoot) { $script:ModuleRoot } else { Split-Path $PSScriptRoot -Parent }
            Join-Path $moduleBase 'data\graph-permissions.json'
        }

        if (-not $PSCmdlet.ShouldProcess($targetPath, "Update Graph Permissions Metadata from $SourceUri"))
        {
            return
        }

        if (-not $Force -and (Test-Path -Path $targetPath))
        {
            if (-not $PSCmdlet.ShouldProcess($targetPath, "Overwrite existing permissions fixture"))
            {
                return
            }
        }

        try
        {
            Write-PSFMessage -Level Verbose -Message "Fetching DevX permissions from $SourceUri..."
            $rawPayload = Invoke-RestMethod -Uri $SourceUri -ErrorAction Stop

            $parsedJson = if ($rawPayload -is [System.Collections.IDictionary])
            {
                $rawPayload
            }
            elseif ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('AsHashtable'))
            {
                $rawPayload | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            }
            else
            {
                # Fallback for Windows PowerShell 5.1 to handle case-collision keys safely
                Add-Type -AssemblyName System.Web.Extensions
                $jsSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
                $jsSerializer.MaxJsonLength = [int]::MaxValue
                $jsSerializer.DeserializeObject($rawPayload)
            }

            $rawPermissions = $parsedJson['permissions']
            if (-not $rawPermissions -or $rawPermissions.Count -eq 0)
            {
                throw "No valid 'permissions' property found in source payload."
            }

            $compiledCatalog = [ordered]@{}
            foreach ($permName in ($rawPermissions.Keys | Sort-Object))
            {
                $entry = $rawPermissions[$permName]
                $schemes = $entry['schemes']
                $appScheme = if ($schemes) { $schemes['Application'] } else { $null }
                $delScheme = if ($schemes) { $schemes['DelegatedWork'] } else { $null }

                $appPriv = if ($appScheme -and $null -ne $appScheme['privilegeLevel']) { [int]$appScheme['privilegeLevel'] } else { $null }
                $delPriv = if ($delScheme -and $null -ne $delScheme['privilegeLevel']) { [int]$delScheme['privilegeLevel'] } else { $null }
                $adminReq = if ($appScheme -and $appScheme['requiresAdminConsent']) { $true } elseif ($delScheme -and $delScheme['requiresAdminConsent']) { $true } else { $false }
                $descText = if ($appScheme -and $appScheme['adminDescription']) { $appScheme['adminDescription'] } elseif ($delScheme -and $delScheme['adminDescription']) { $delScheme['adminDescription'] } else { $entry['description'] }

                $compiledCatalog[$permName] = [ordered]@{
                    appPrivilegeLevel       = $appPriv
                    delegatedPrivilegeLevel = $delPriv
                    requiresAdminConsent    = $adminReq
                    description             = $descText
                }
            }

            # Ensure parent directory exists
            $parentDir = Split-Path -Path $targetPath -Parent
            if ($parentDir -and -not (Test-Path -Path $parentDir))
            {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }

            $jsonString = $compiledCatalog | ConvertTo-Json -Depth 5
            [System.IO.File]::WriteAllText($targetPath, $jsonString, [System.Text.Encoding]::UTF8)

            # Invalidate module in-memory cache
            $script:GTPermissionCache = $null

            Write-PSFMessage -Level Verbose -Message "Successfully compiled $($compiledCatalog.Count) permissions to $targetPath."

            [PSCustomObject]@{
                PermissionCount = $compiledCatalog.Count
                OutputPath      = $targetPath
                SourceUri       = $SourceUri
                LastUpdated     = [DateTime]::UtcNow
                Status          = 'Success'
            }
        }
        catch
        {
            $err = if (Get-Command Get-GTGraphErrorDetails -ErrorAction SilentlyContinue) {
                Get-GTGraphErrorDetails -Exception $_.Exception -ResourceType 'PermissionsMetadata'
            } else {
                [PSCustomObject]@{ LogLevel = 'Error'; Reason = $_.Exception.Message }
            }
            Write-PSFMessage -Level $err.LogLevel -Message "Failed to update permissions metadata: $($err.Reason)"
            throw $_
        }
    }
}

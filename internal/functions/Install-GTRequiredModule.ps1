<#
.SYNOPSIS
    Ensures required PowerShell modules are installed
.DESCRIPTION
    Checks for module existence and installs from PSGallery if missing
.PARAMETER ModuleNames
    One or more module names to verify/install
.PARAMETER Scope
    Installation scope (CurrentUser or AllUsers)
.PARAMETER AllowPrerelease
    Allow installation of prerelease versions
.EXAMPLE
    Install-GTRequiredModule -ModuleNames Microsoft.Graph.Beta.Reports, Pester
.EXAMPLE
    Install-GTRequiredModule -ModuleNames Az -Scope AllUsers -Verbose
#>
function Install-GTRequiredModule
{
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ModuleNames,

        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope = 'CurrentUser',

        [switch]$AllowPrerelease
    )

    begin
    {
        # Check PowerShell Gallery availability
        if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue))
        {
            throw "PSGallery repository is not available. Please register it first."
        }
    }

    process
    {
        foreach ($module in $ModuleNames)
        {
            try
            {
                # Check if module is already installed
                if (Get-Module -Name $module -ListAvailable -ErrorAction Stop)
                {
                    Write-PSFMessage -Level Verbose -Message "Module $module is already installed"
                    continue
                }

                if ($PSCmdlet.ShouldProcess($module, "Install module from PSGallery"))
                {
                    # Install parameters
                    $installParams = @{
                        Name         = $module
                        Scope        = $Scope
                        Force        = $true
                        ErrorAction  = 'Stop'
                        AllowClobber = $true
                        Confirm      = $false
                    }

                    if ($AllowPrerelease)
                    {
                        $installParams['AllowPrerelease'] = $true
                    }

                    Write-PSFMessage -Level Verbose -Message "Installing module: $module"
                    Install-Module @installParams

                    # Verify installation
                    if (-not (Get-Module -Name $module -ListAvailable -ErrorAction SilentlyContinue))
                    {
                        throw "Module $module failed to install successfully"
                    }
                }
            }
            catch
            {
                throw "Failed to install module $($module): $_"
            }
        }
    }
}

Describe "Get-GTLicenseCostReport" {
    BeforeAll {
        # Define stub helper functions used by the module
        function Install-GTRequiredModule { param([string[]]$ModuleNames, [string]$Scope, [switch]$AllowPrerelease) }
        function Initialize-GTGraphConnection { param([string[]]$Scopes, [switch]$NewSession) return $true }
        function Test-GTGraphScopes { param([string[]]$RequiredScopes, [switch]$Reconnect, [switch]$Quiet) return $true }
        function Write-PSFMessage { param($Level, $Message, $ErrorRecord) }
        function Get-GTGraphErrorDetails { param($Exception, $ResourceType) return @{ LogLevel = 'Error'; Reason = $Exception.Message; ErrorMessage = $Exception.Message } }

        # Provide minimal stub implementations for Graph cmdlets so dot-sourcing
        # the function does not throw CommandNotFoundException in this environment.
        function Get-MgSubscribedSku { param([switch]$All, $ErrorAction) }
        function Get-MgBetaUser { param($Filter, $Property, $ConsistencyLevel, $All, $ErrorAction) }
        # Provide a UTC time helper used by the function under test
        # Use the module's internal UTC helper for consistency
        . "$PSScriptRoot/../internal/functions/Get-UTCTime.ps1"

        # Dot-source the function under test AFTER stubs
        . "$PSScriptRoot/../functions/Get-GTLicenseCostReport.ps1"

        # Sample SKUs
        $script:mockSkus = @(
            [PSCustomObject]@{
                SkuId         = [Guid]::NewGuid()
                SkuPartNumber = 'ENTERPRISEPACK'
                PrepaidUnits  = [PSCustomObject]@{ Enabled = 100 }
                ConsumedUnits = 80
            },
            [PSCustomObject]@{
                SkuId         = [Guid]::NewGuid()
                SkuPartNumber = 'SPECONLY'
                PrepaidUnits  = [PSCustomObject]@{ Enabled = 50 }
                ConsumedUnits = 10
            }
        )

        # Create some inactive users with assignedLicenses
        $sku1Id = $script:mockSkus[0].SkuId
        $sku2Id = $script:mockSkus[1].SkuId

        # Five inactive users assigned sku1, two inactive users assigned sku2
        $script:inactiveUsers = @()
        1..5 | ForEach-Object {
            $script:inactiveUsers += [PSCustomObject]@{ id = "inactive$_"; assignedLicenses = @([PSCustomObject]@{ SkuId = $sku1Id }) }
        }
        1..2 | ForEach-Object {
            $script:inactiveUsers += [PSCustomObject]@{ id = "inactive_s2_$_"; assignedLicenses = @([PSCustomObject]@{ SkuId = $sku2Id }) }
        }

        # One user without assignedLicenses (should be skipped safely)
        $script:inactiveUsers += [PSCustomObject]@{ id = 'noAssigned'; }
    }

    BeforeEach {
        Mock -CommandName "Get-MgSubscribedSku" -MockWith {
            return $script:mockSkus
        } -Verifiable

        Mock -CommandName "Get-MgBetaUser" -MockWith {
            param($Filter, $Property, $ConsistencyLevel, $All, $ErrorAction)
            # Always return the set of prepared inactive users for the function's filter
            return $script:inactiveUsers
        } -Verifiable

        # Prepare an in-memory SKU name map and inject via -SkuNameMap when calling the function
        $skuMap = @{
            ($script:mockSkus[0].SkuId.ToString()) = 'Test Enterprise Pack'
            ($script:mockSkus[1].SkuId.ToString()) = 'Test Spec Only'
        }
    }

    It "computes wasted spend using PriceList keyed by part number" {
        $priceList = @{ 'ENTERPRISEPACK' = 10; 'SPECONLY' = 5 }

    $result = Get-GTLicenseCostReport -PriceList $priceList -InactiveDays 90 -SkuNameMap $skuMap

        $result | Should -Not -BeNullOrEmpty

        # Find the ENTERPRISEPACK row
        $ep = $result | Where-Object { $_.SkuPartNumber -eq 'ENTERPRISEPACK' }
        $ep | Should -Not -BeNullOrEmpty

        # Purchased 100, Assigned 80, Available = 20, Zombies = 5 => Wasted = (20+5)*10 = 250
        $ep.Purchased | Should -Be 100
        $ep.Assigned | Should -Be 80
        $ep.Available | Should -Be 20
        $ep.InactiveAssigned | Should -Be 5
        $ep.WastedSpend | Should -Be 250
    }

    It "accepts PriceList keyed by SkuId string" {
        $sku1Id = $script:mockSkus[0].SkuId.ToString()
        $priceList = @{ $sku1Id = 20 }

    $result = Get-GTLicenseCostReport -PriceList $priceList -InactiveDays 90 -SkuNameMap $skuMap
        $ep = $result | Where-Object { $_.SkuId -eq $sku1Id }
        $ep.UnitPrice | Should -Be 20
    }

    It "defaults to zero price when PriceList is missing" {
    $result = Get-GTLicenseCostReport -InactiveDays 90 -SkuNameMap $skuMap
        $ep = $result | Where-Object { $_.SkuPartNumber -eq 'ENTERPRISEPACK' }
        $ep.UnitPrice | Should -Be 0
        $ep.WastedSpend | Should -Be 0
    }

    It "handles users without assignedLicenses gracefully" {
        # This test ensures the user with no assignedLicenses doesn't break the run
    $result = Get-GTLicenseCostReport -InactiveDays 90 -SkuNameMap $skuMap
        $result.Count | Should -BeGreaterThan 0
    }
}

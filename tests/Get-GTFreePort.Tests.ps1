if (-not (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) { function Write-PSFMessage { param($Level, $Message, $ErrorRecord) } }

Describe "Get-GTFreePort" -Tag 'Unit' {
    BeforeAll {
        $helperPath = Join-Path $PSScriptRoot '..\internal\functions\Get-GTFreePort.ps1'
        if (Test-Path $helperPath) { . $helperPath }
    }

    It "returns an integer representing an available ephemeral TCP port" {
        $port = Get-GTFreePort

        $port | Should -BeOfType [int]
        $port | Should -BeGreaterThan 1024
        $port | Should -BeLessThan 65536
    }

    It "releases the port so it can be immediately bound by a listener" {
        $port = Get-GTFreePort
        $testListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)

        {
            $testListener.Start()
            $testListener.Stop()
        } | Should -Not -Throw
    }
}

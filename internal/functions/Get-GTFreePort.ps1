function Get-GTFreePort
{
    <#
    .SYNOPSIS
        Discovers an available OS-assigned TCP port on the loopback interface.
    .DESCRIPTION
        Binds a transient TCP listener to port 0 on the loopback IP (127.0.0.1)
        to request an ephemeral port from the operating system network stack.
    .OUTPUTS
        [int] The available local TCP port number.
    .EXAMPLE
        $port = Get-GTFreePort
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()

    $tcpListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $tcpListener.Start()
    try
    {
        return [int]$tcpListener.LocalEndpoint.Port
    }
    finally
    {
        $tcpListener.Stop()
    }
}

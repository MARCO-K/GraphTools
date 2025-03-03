

Function Reset-GTUserPassword
{
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$UPN
    )

    try
    {
        Install-RequiredModule Microsoft.Graph.Beta.Users
    }
    catch
    {
        throw "Failed to install required module: $_.Exception.Message"
    }
    
    $Password = New-GTPassword
    $UserPwd = ConvertTo-SecureString $Password -AsPlainText -Force
    
    foreach ($user in $UPN)
    {
        try
        {
            $Passwordprofile = @{
                forceChangePasswordNextSignIn = $true
                password                      = $UserPwd
            }
            Update-MgBetaUser -UserId $user -PasswordProfile $Passwordprofile
            Write-PSFMessage -Level Verbose -Message "Password Reset to Random for $user"
        }
        catch
        {
            Write-PSFMessage -Level Error -Message "Failed to Reset Password for $user"
        }
    }
}
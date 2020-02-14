#
#   To run this type the commandL
#           powershell -ExecutionPolicy  unRestricted  office-vpn.ps1
#
#  
$cert = "-----BEGIN CERTIFICATE-----
MIIE2TCCA8GgAwIBAgIBADANBgkqhkiG9w0BAQsFADCBpDELMAkGA1UEBhMCQ0Ex
............................................................
INSERT YOUR PUBLIC SelfSigned Cert here
............................................................
-----END CERTIFICATE-----
" 

# Get the ID and security principal of the current user account
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)

# Get the security principal for the Administrator role
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator

# Check to see if we are currently running "as Administrator"
if ($myWindowsPrincipal.IsInRole($adminRole))
   {
   # We are running "as Administrator" - so change the title and background color to indicate this
   $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + "(Elevated)"
#   $Host.UI.RawUI.BackgroundColor = "Blue"
#   $Host.UI.RawUI.ForeGroundColor = "White"
#   clear-host
   }
else
   {
   # We are not running "as Administrator" - so relaunch as administrator

   # Create a new process object that starts PowerShell
   $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
   
   # Specify the current script path and name as a parameter
   Write-Host "Attempting to Running as Administator.... "
   $newProcess.Arguments = '-ExecutionPolicy Unrestricted  -File "' + $myInvocation.MyCommand.Definition + '"';
   
   # Indicate that the process should be elevated
   $newProcess.Verb = "runas";
   # write-host $newProcess.Arguments;
   
   # Start the new process
   
   [System.Diagnostics.Process]::Start($newProcess);
   # Exit from the current, unelevated, process

   if ($Error -ne "") {
        Write-Output 'Please ensure you allow this script to run as Administrtor'
        Write-Output ' '
        Write-Output 'Rerun script and click the Run as Administator button'
        Write-Output ' '
        pause
    }
   exit

   }
   
# Run your code that needs to be elevated here
# Load assembly
$oLoad = [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

$msgBoxInput =  [System.Windows.Forms.MessageBox]::Show('Would you like to install the VPN Connection for the Office?',[System.Windows.Forms.MessageBoxIcon]::Question, [System.Windows.Forms.MessageBoxButtons]::YesNo)

  switch  ($msgBoxInput) {

    'Yes' {

        $installCert = [System.IO.Path]::GetTempFileName()


        Add-Content -Path $installCert -Force -Value $cert

        if (Test-Path $installCert) {

        } Else {
	        Write-Error "Failed: Cannot created temp file  "  $installCert
	
	        pause
	        exit 2
        }



        write-output "------------------------------------------ "
        write-output "          Installing Certificate"
        write-output "------------------------------------------ "
        write-output " "

        $i = Import-Certificate -FilePath $installCert -CertStoreLocation  Cert:\LocalMachine\Root

        Remove-Item -Path $installCert
        write-output " "

        write-output "        Creating VPN Connection"
        write-output "------------------------------------------ "
        #
        # Split tunnel only route the one subnetfor a PFSense Server for VPN
        #
        Add-VpnConnection -Name "Office" -ServerAddress "vpn.mydomain.com" -TunnelType IKEv2 -EncryptionLevel Required -AuthenticationMethod EAP -SplitTunneling -RememberCredential -DnsSuffix office.local 
        $null = Add-VpnConnectionRoute -ConnectionName "Office" -DestinationPrefix 192.168.3.0/24 -PassThru
        write-output " "

        write-output " "
        write-output "     ++++ Success!!!!!"
        write-output "------------------------------------------ "
        write-output " "


        write-output "      VPN Connect Name is    Office   (Located on your Network icon connection)"
        write-output "      User Name is           xxxxxx"
        write-output "You will be asked to login once, it will remember the username and password next time"
        write-output " "


        Write-Host -NoNewLine "Press any key to continue..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

    }

    'No' {

        Write-Host 'Cancelled Installation'
      }

  

  }


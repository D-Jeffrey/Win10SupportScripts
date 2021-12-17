# https://docs.microsoft.com/powershell/azure/active-directory/overview

function TestAdmin {
  return  (new-object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(([System.Security.Principal.SecurityIdentifier]"S-1-5-32-544"))
}

  <#
    .SYNOPSIS
    Test a credential

    .DESCRIPTION
    Test a credential object or a username and password against a machine or domain.
    Can be used to validate service account passwords.

    .PARAMETER Credential
    Credential to test

    .PARAMETER UserName
    Username to test

    .PARAMETER Password
    Clear text password to test. 
    ATT!: Be aware that the password is written to screen and memory in clear text, it might also be stored in clear text on your computer.

    .PARAMETER ContextType
    Set where to validate the credential.
    Can be Domain, Machine or ApplicationDirectory

    .PARAMETER Server
    Set remote computer or domain to validate against.

    .EXAMPLE
    Test-SWADCredential -UserName svc-my-service -Password Kgse(70g!S.
    True

    .EXAMPLE
    Test-SWADCredential -Credential $Cred
    True
#>
function Test-SWADCredential 
{
    [CmdletBinding(DefaultParameterSetName='Credential')]
    Param
    (
        [Parameter(Mandatory=$true,ParameterSetName='Credential')]
        [pscredential]
        $Credential,
        
        [Parameter(Mandatory=$true,ParameterSetName='Cleartext')]
        [ValidateNotNullOrEmpty()]
        [string]$UserName,
        
        [Parameter(Mandatory=$true,ParameterSetName='Cleartext')]
        [string]$Password,

        [Parameter(Mandatory=$false,ParameterSetName='Cleartext')]
        [Parameter(Mandatory=$false,ParameterSetName='Credential')]
        [ValidateSet('ApplicationDirectory','Domain','Machine')]
        [string]$ContextType = 'Domain',

        [Parameter(Mandatory=$false,ParameterSetName='Cleartext')]
        [Parameter(Mandatory=$false,ParameterSetName='Credential')]
        [String]$Server
    )
    
    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement -ErrorAction Stop
        if($PSCmdlet.ParameterSetName -eq 'ClearText') {
            $EncPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
            $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UserName,$EncPassword
        }
        try {
            if($PSBoundParameters.ContainsKey('Server'))
            {
                $PrincipalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($ContextType,$Server)
            }
            else
            {
                $PrincipalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($ContextType)
            }
        }
        catch {
            Write-Error -Message "Failed to connect to server using contect: $ContextType"
        }
        try
        {
            $PrincipalContext.ValidateCredentials($Credential.UserName, $Credential.GetNetworkCredential().Password)
        }
        catch [UnauthorizedAccessException]
        {
            Write-Warning -Message "Access denied when connecting to server."
            return $false
        }
        catch
        {
            Write-Error -Exception $_.Exception -Message "Unhandled error occured"
        }
    }
    catch {
        throw
    }
}

Write-Host '* Ready *' -ForegroundColor Green

if (-not (TestAdmin)) {
  Write-Host '*********** Must be run as Admin ********' -ForegroundColor Red -BackgroundColor White
  

  sleep 10
  break 
}
Write-Host '*********** Starting ********' -ForegroundColor Green 

#
#   $username = "adconnect@southcalgary.onmicrosoft.com"
#
Import-Module "C:\Program Files\Microsoft Azure Active Directory Connect\AzureADSSO.psd1"




$creds = Get-Credential "SCCC\Administrator"  -Message "Please enter your SCCC Administartor password" 

if ($creds -eq $null ) {
  Write-Host 'No Password given - Stopping' -ForegroundColor Red -BackgroundColor White
  sleep 10
  break
}
if (Test-SWADCredential -Credential $creds) {
  Write-Host ("Domain account value : " + $creds.UserName)  -ForegroundColor Green
}
else {

  Write-Host ("Invalid Domain account and/or password : " + $creds.UserName) -ForegroundColor Red -BackgroundColor White

  sleep 10
  break
}

Write-Host "Login wiht Azure user account (Role Global Admin) "

try {
# This command should give you a popup to enter your tenant's Global Administrator credentials.
New-AzureADSSOAuthenticationContext  
} catch {
	throw "Did not authenicate.  *****   -------------------- Halted"
	sleep 10
	break
}

Get-ADComputer AZUREADSSOACC -Properties * | FL Name,PasswordLastSet
#
# Get-AzureADSSOStatus | ConvertFrom-Json    #  `. This command provides you the list of AD forests (look at the "Domains" list) on which this feature has been enabled.
#

#*Step 2. Update the Kerberos decryption key

    # `. When prompted, enter the Domain Administrator credentials for the intended AD forest.
Write-Host '*********** Rotating Kerb' -ForegroundColor Green
Update-AzureADSSOForest -OnPremCredentials $creds        # This command updates the Kerberos decryption key for the `AZUREADSSOACC` computer account in this specific AD forest and updates it in Azure AD.
Get-ADComputer AZUREADSSOACC -Properties * | FL Name,PasswordLastSet
Write-Host '*********** Completed reation of Kerb credientions... Do not re-run this script for at least 1 day' -ForegroundColor Yellow
write-host 'End' -ForegroundColor Green

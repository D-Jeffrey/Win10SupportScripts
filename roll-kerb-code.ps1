#
# My version of a Kerberos key roll for AD join computer intergration with AD Sync Connector
# I only have a single tenant, so the extra steps are not required for password reset.
#
# https://docs.microsoft.com/powershell/azure/active-directory/overview
# Until this get enough votes to get completed: 
# https://feedback.azure.com/forums/169401-azure-active-directory/suggestions/33773926-automate-seamless-sso-kerberos-decryption-key-roll?tracking_code=7692a629bf86f0973236aab87ea3e996

$myonprem = "yourADdomain"

function TestAdmin {
  return  (new-object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(([System.Security.Principal.SecurityIdentifier]"S-1-5-32-544"))
}
Write-Output '* Ready *'

if (-not (TestAdmin)) {
  Write-Host '*********** Must be run as Admin ********'
  Write-Output '*********** Must be run as Admin ********'

  sleep 2000
  Exit 
}
Write-Output '*********** Starting ********'

Import-Module "C:\Program Files\Microsoft Azure Active Directory Connect\AzureADSSO.psd1"


try {

  $creds = Get-Credential ($myonprem + "\Administrator") 

  Write-Host "Login wiht Azure Global admin user id"

# This command should give you a popup to enter your tenant's Global Administrator credentials.
New-AzureADSSOAuthenticationContext  
} catch {
	throw "Did not authenicate.  *****   -------------------- Halted"
	sleep 2000
	exit
}

Get-ADComputer AZUREADSSOACC -Properties * | FL Name,PasswordLastSet
Get-AzureADSSOStatus | ConvertFrom-Json    #  `. This command provides you the list of AD forests (look at the "Domains" list) on which this feature has been enabled.


#*Step 2. Update the Kerberos decryption key
   
Write-Host '*********** Rotating Kerb'
Update-AzureADSSOForest -OnPremCredentials $creds        # This command updates the Kerberos decryption key for the `AZUREADSSOACC` computer account in this specific AD forest and updates it in Azure AD.
Get-ADComputer AZUREADSSOACC -Properties * | FL Name,PasswordLastSet
Write-Host '*********** Completed reation of Kerb credientions... Do not re-run this script for at least 1 day'
write-host 'End'

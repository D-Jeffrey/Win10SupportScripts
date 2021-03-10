#
# All the interesting things you want to know about users and guest while you are migrating to Office 365.
#
# This was create through many iterations and trial/error.  I'm sure there is a cleaner way of bring this information together,
# but it evolved over time.  For the AzureAD queries has components of MSOL and EXO within it.  I'm sure there is a better way to do this.
# 
#  -Summary            will give a summary of Licenses, Groups Mailboxes (if IncludeExchange is used)
#  -IncludeExchange    Pull mailbox information
#  -CheckFor           Allow to search for a user or part of a user  ..  -CheckFor Darren
#                      This also makes it just displays the results instead of putting them into a CSV
#  -ShowMFA            Displays the MFA authenications details
#  -ShowAllColumns     Pull everything... all columns
#                      If none of the filters are applied it will pull all the objects
#  -IncludeTeams       give information about TeamsUpgradePolicy and ExternalAccessPolicy, but it is a very slow process
#
#  -EnabledOnly
#  -DisabledOnly
#  -AdminOnly
#  -LicensedUserOnly
#  -ConditionalAccessOnly 
#
# if you use the ___Only parameters the results may be not complete.
# Caching - it takes time to query MS, so in order to acccelrate that, caching was added for Roles, Exo, Groups, AD Users
#       AAD Users, this can reduces the look time for a query from 20 seconds down to 4 seconds.
#       The cache TTL is 24 hours,  It caches, groups, AD Users, Exo state, and Roles.
#       The 'Live data' is the MSOL/AAD state of users
# For us, we used groups to apply licenses which is why we want those.
#
# There is a still a need to adjust Fix the 2nd logon for Teams
# and add more error checking.  Disabling Caching is not well tested.
# I'm sure if I re-wrote some of this in Graph it would be faster (especially the Teams queries)
#
#   Look for CONFIGURATIONHERE for please you may need to adjus for your configuration.
#
# Orginal sources Robert Luck 
#     https://gallery.technet.microsoft.com/scriptcenter/Export-Office-365-Users-81747c73
#     https://o365reports.com/2019/05/09/export-office-365-users-mfa-status-csv/ 
# 
#
# This script uses the following Modules:
#    ActiveDirectory
#    MSOnline
#    MicrosoftTeams
#    ExchangeOnlineManagement
#    AzureAD
#    SMAAuthoringToolkit
#    
#    It does not yet use the new Teams Module released in Mar 2021
#
# Recommend command-line:
#         & '.\CheckUser365.ps1' -IncludeSummary -IncludeExchange -ShowMFA -ShowAllColumns -IncludeTeams
# or to look up a person
#         & '.\CheckUser365.ps1' -IncludeExchange -ShowMFA -ShowAllColumns -CheckFor Darren
#
#--------------------------------------------------------------------------------


param
(
  [Parameter(Mandatory = $false)]
  [switch]$Summary,                    # Summary of objects & Licenses
  [switch]$IncludeSummary,             # Do the Summary after the extract
  [switch]$IncludeExchange,            # QUery Exchange for Mailbox state
  [string]$CheckFor = "",              # Part search string for user
  [switch]$DisabledOnly,
  [switch]$EnabledOnly,
  [switch]$EnforcedOnly,
  [switch]$ShowMFA,
  [switch]$ShowAllColumns,
  [switch]$ConditionalAccessOnly,
  [switch]$AdminOnly,
  [switch]$LicensedUserOnly,
  [switch]$ShowEmpNum,

  [Nullable[boolean]]$SignInAllowed = $null,
  [string]$UserName,
  [string]$Password,
  [switch]$IncludeTeams,
  [switch]$IncludeGroups,              # Include Office 365 Groups
  [switch]$FlushCache,                # to clear all the program generated caches 
  [int32]$TopX = -1,
  [switch]$TeamCount
)

# Extra Licenses to look for  
# CONFIGURATIONHERE

$selectSkus = @(
  [pscustomobject]@{ Code = "MCOMEETADV"; Name = "Microsoft365AudioConferencing" }
  [pscustomobject]@{ Code = "MCOEV"; Name = "Microsoft365PhoneSystem" }
  [pscustomobject]@{ Code = "POWERAPPS_O365_P2"; Name = "PowerApp365"}
  [pscustomobject]@{ Code = "POWERAPPS_INDIVIDUAL_USER"; Name = "PowerAppsUser" }
  [pscustomobject]@{ Code = "POWERAPPS_PER_APP_IW"; Name = "PowerAppsIW" }
  [pscustomobject]@{ Code = "FLOW_O365_P2"; Name = "Flow365" }
  [pscustomobject]@{ Code = "FLOW_P2_VIRAL"; Name = "FlowViral" }
  [pscustomobject]@{ Code = "FLOW_P2_VIRAL_REAL"; Name = "FlowViral" }
  [pscustomobject]@{ Code = "INTUNE_O365"; Name = "InTune365" }
  [pscustomobject]@{ Code = "POWERAPPS_VIRAL"; Name = "PowerAppsViral" }
  [pscustomobject]@{ Code = "POWERAPPS_P2_VIRAL"; Name = "PowerAppsViral2" }
  [pscustomobject]@{ Code = "POWERVIDEOSFREE" ; Name = "PowerVideoFree"}
  [pscustomobject]@{ Code = "POWERFLOWSFREE"; Name = "PowerFLOWSFREE"}
  [pscustomobject]@{ Code = "POWERAPPSFREE"; Name = "PowerAPPSFREE"}
  
)

# If you want to call out membership in special groups
# CONFIGURATIONHERE

$ShowSpecialGroups = @( "App_IPP_Users", "NoPSTGrowth", "FAB-GuestUsers" )
  


$scriptversion = "v.21.03.126"
$runtime = Get-Date



#$sku = "*:ENTERPRISEPACK"
$sku = "*"
# The group users for License assignment CONFIGURATIONHERE
$E5GName = "Azure_License_MBaseE5"

#Caching files to speed up startup run of script
$UseCaching = 1
$CacheAge = -1    # one day Cache
$EXOCache = $env:TEMP  + "\CheckUser365.Exo.Cache"
$GrpCache1 = $env:TEMP  + "\CheckUser365.grp1.Cache"
$GrpCache2 = $env:TEMP  + "\CheckUser365.grp2.Cache"
$OGrpCache = $env:TEMP  + "\CheckUser365.ogrp.Cache"
$UsrCache = $env:TEMP  + "\CheckUser365.usr.Cache"
$AADCache = $env:TEMP  + "\CheckUser365.AAD.Cache"
$RolCache = $env:TEMP  + "\CheckUser365.Rol.Cache"

$AllMailboxtypes = {"DynamicDistributionGroup", "MailContact", "MailNonUniversalGroup", "MailUniversalDistributionGroup",
        "MailUniversalSecurityGroup", "MailUser", "PublicFolder", "UserMailbox"}

#Output file declaration 
$ExportCSV = ".\DisabledUserReport_$((Get-Date -format yyyy-MMM-dd-ddd` hh-mm` tt).ToString()).csv"
$ExportCSVReport = ".\EnabledUserReport_$((Get-Date -format yyyy-MMM-dd-ddd` hh-mm` tt).ToString()).csv"
$ExportCSVTeams = ".\Teams_$((Get-Date -format yyyy-MMM-dd-ddd` hh-mm` tt).ToString()).csv"

function Get-CurrentLine {
  -join ("Line: ",$Myinvocation.ScriptlineNumber)
}

function UseCache {
param (
        [string[]]$CacheFile,
        [boolean[]]$isSeemStatic
    )
    if ($isSeemStatic) {
        $age = $CacheAge*10
    } else {
        $age = $CacheAge
    
    }
    Return  ($UseCaching -and  ((Get-Item -LiteralPath $CacheFile -ErrorAction SilentlyContinue).LastWriteTime -gt (Get-Date).AddDays($CacheAge)))
    
    
 }
Function WriteError
{
    param 
    (
        [Parameter(Mandatory=$true,Position=0)]
        [string]$Message
    )
    if ($AAMode) {
       Write-Output ((get-date -Format "dd-MMM-yyyy hh:mm:ss tt") + ": ERROR: $Message")
    } else {
       Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": ERROR: $Message" -ForegroundColor RED
       }
}

Function Get-RecursiveAzureAdGroupMemberUsers{
[cmdletbinding()]
param(
   [parameter(Mandatory=$True,ValueFromPipeline=$true)]
   $AzureGroup
)
    Begin{
        If(-not(Get-AzureADCurrentSessionInfo)){Connect-AzureAD}
    }
    Process {
        Write-Verbose -Message "Enumerating $($AzureGroup.DisplayName)"
        $Members = Get-AzureADGroupMember -ObjectId $AzureGroup.ObjectId -All $true
        $UserMembers = $Members | Where-Object{$_.ObjectType -eq 'User'}
        If($Members | Where-Object{$_.ObjectType -eq 'Group'}){
            $UserMembers += $Members | Where-Object{$_.ObjectType -eq 'Group'} | ForEach-Object{ Get-RecursiveAzureAdGroupMemberUsers -AzureGroup $_}
        }
    }
    end {
        Return $UserMembers
    }
}
Function WriteInfo
{
    param 
    (
        [Parameter(Mandatory=$true,Position=0)]
        [string]$Message
    )
    if ($AAMode) {
       Write-Output ((get-date -Format "dd-MMM-yyyy hh:mm:ss tt") + ": INFO: $Message")
    } else {
        Write-Host (get-date -Format "dd-MMM-yyyy hh:mm:ss tt") ": INFO: $Message" -ForegroundColor Yellow
        }
}




$EmpoyeeCount = 0
$ContractCount = 0
$EmpoyeeCountLeft = 0
$ContractCountLeft = 0

# --------------------------------------------------------------------------------------------------------------
# Function doSummary
#
#--------------------------------------------------------------------------------------------------------------

function doSummary {

  Write-Host "----------     Summary       -----------" -BackgroundColor DarkYellow
  # Look for Teams and O365 Groups
  if ($IncludeExchange.IsPresent) {
    $UGroups = (Get-UnifiedGroup -Filter 'ResourceProvisioningOptions -ne $null' )
    }

  Write-Output ("Total users/groups/mailboxes/accounts in Azure " + $who.count)

  if ($IncludeExchange.IsPresent) {
    Write-Output ("Mailboxes")
    $EXOList.StorageGroupName | Select-Object -Unique | ForEach-Object { 
        $R = $_
        if ($R -like "-") { $R = "Account Only" }
        Write-Output ("  " + $R.PadRight(20) + ": " + ($EXOList | Where-Object StorageGroupName -eq $r ).count )
        if (($R -like "On-Premise") -and $Summary.IsPresent) {
            Write-Output ("   - This will miss count on-premise mailboxes as some could be only accounts w/o mailboxes - run without '-Summary'")
            }
        }


  }
  if ($EmpoyeeCount -ne 0) {
   $line = ""
    if ($IncludeExchange.IsPresent) {
        $line = ", Exchange-online" 
        }
    Write-Output "People Accounts Activated$line & Licensed"
    Write-Output ("  Total          " + ($EmpoyeeCount + $ContractCount)) 
    Write-Output "    Employees    $EmpoyeeCount"
    Write-Output "    Contractor   $ContractCount"
    if ($IncludeExchange.IsPresent) {
    Write-Output "Still On-Premise (Employee number based)"
    Write-Output "    Employees    $EmpoyeeCountLeft"
    Write-Output "    Contractor   $ContractCountLeft"
    }
  
  }
  

  # we have to look this one up because it is not cached
  Write-Output ("Users in Azure License E5     " + $E5GroupList.count + " vs " + (Get-ADGroup "Azure_License_NonMBaseE5" | Get-ADGroupMember).count  + " Nonbase E5")

  # Pull information about Office 365 Groups
  if ($IncludeExchange.IsPresent) {
  
    Write-Output ("Teams Sites/Groups            " + $UGroups.count)
    Write-Output ("    - no users   : "  + ($UGroups | Where-Object GroupMemberCount -eq 0).count)
    Write-Output ("    - 1 user     : "  + ($UGroups | Where-Object GroupMemberCount -eq 1).count)
    Write-Output ("    - with guests: "  + ($UGroups | Where-Object GroupExternalMemberCount -ne 0).count)
    $UGroups | select DisplayName, ManagedByDetails, Notes, GroupMemberCount, GroupExternalMemberCount,  AllowAddGuests, ExpirationTime, WhenCreated, SensitivityLabel, ResourceProvisioningOptions     | Export-Csv -Notype -Path $ExportCSVTeams 
    
    }
  write-Output ("Disabled Users with a License " + (Get-MsolUser -EnabledFilter DisabledOnly -All | Where-Object  isLicensed -EQ true  | Where-Object  {$_.Licenses.AccountSkuId -contains ":SPE_E5"}).count) 
  
  }




#  ==========================================================================
# reset connections
#
  if ($FlushCache.IsPresent) {
        Disconnect-AzureAD  -ErrorAction SilentlyContinue
        Disconnect-ExchangeOnline -ErrorAction SilentlyContinue
        Disconnect-MicrosoftTeams -ErrorAction SilentlyContinue
        Get-PSSession | Remove-PSSession

  }


 #ERICH
 $Modules = Get-Module -Name SMAAuthoringToolkit -ListAvailable  #needed for Get-AutomationVariable 
if ($Modules.count -eq 0)
{
  WriteError Please install SMAAuthoringToolkit module using below command: `nInstall-Module SMAAuthoringToolkit
  exit
}
 
$ClientID = Get-AutomationVariable -Name 'ClientID' -WarningAction SilentlyContinue

if ($ClientID -eq $null) {
    $AAMode = $false
    $username = (get-aduser $env:username -Properties UserPrincipalName).UserPrincipalName
    } else {
# Azure Automate Mode
    $AAMode = $true
# Turn off Caching for Automate
    if ($UseCaching) {
        $UseCaching = $false
        }
}

#Check for MSOnline module 
$Modules = Get-Module -Name MSOnline -ListAvailable
if ($Modules.count -eq 0)
{
  WriteError "Please install MSOnline module using below command: `nInstall-Module MSOnline"
  exit
}

Write-Host -BackgroundColor DarkGreen ("CheckUser365 : " + $scriptversion)
Write-Progress -Activity ("CheckUser365 - " + $scriptversion + "`n... Connecting... `n")
#Storing credential in script for scheduling purpose/ Passing credential as parameter  
if (($UserName -ne "") -and ($Password -ne ""))
{
  $SecuredPassword = ConvertTo-SecureString -AsPlainText $Password -Force
  $Credential = New-Object System.Management.Automation.PSCredential $UserName,$SecuredPassword
  WriteInfo "Connect Direct MSOL"    
  Connect-MsolService -accountid $credential
}
else
{
  if ($AAMode) {
   $credObject = Get-AutomationPSCredential -Name "Office-Credentials" 
   Connect-MsolService -Credential $credObject
   Connect-MsolService  -AzureEnvironment "AzureCloud"
   }
   else {
  try {
    WriteInfo "Testing Domain for MSOL"    
    Get-MsolDomain -ErrorAction Stop | Out-Null
  } catch {
    WriteInfo "Connecting to MSOL"
    Write-Progress -Activity ("CheckUser365 - " + $scriptversion + "`n... Connecting ... `n")
    Connect-MsolService | Out-Null

  }
  }

}

# this required TeamsAdmin or GlobalAdmin
if ($TeamCount.IsPresent -or $IncludeTeams.IsPresent) {
  $Modules = Get-Module -Name MicrosoftTeams -ListAvailable
  if ($Modules.count -eq 0)
  {
    WriteError Please install MicrosoftTeams module using below command: `nInstall-Module MicrosoftTeams 
    exit
  }
  Write-Host " -IncludeTeams is a slow option (maybe 4X slower)" -BackgroundColor DarkRed
  if ((Get-PSSession | Where-Object Name -like "SfBPowerShellSession*").count -eq 1) {
    $id = ((Get-PSSession | Where-Object Name -like "SfBPowerShellSession*").InstanceId) 
#    #if ((Get-PSSession -InstanceId $id).State -like "Broken") {
      Remove-PSSession -InstanceId $id
#    #  }
      
     }
  if ((Get-PSSession | Where-Object Name -like "SfBPowerShellSession*").count -eq 0)  {
    Import-Module MicrosoftTeams
    $sfbSession = New-CsOnlineSession -Credential $credObject
    Import-PSSession $sfbSession -AllowClobber | Out-Null
  }

}

if ($IncludeExchange.IsPresent) {
  $Modules = Get-Module -Name ExchangeOnlineManagement -ListAvailable
  if ($Modules.count -eq 0)
  {
    WriteError Please install ExchangeOnlineManagement module using below command: `nInstall-Module ExchangeOnlineManagement 
    exit
  }
  if (!((Pssession).Name -like "Exchange*")) {
  #ERICH
    Connect-ExchangeOnline -ConnectionUri https://outlook.office365.com/powershell-liveid/ -UserPrincipalName $UserName | Out-Null
  }


if ($ShowAllColumns.IsPresent) {
  $Modules = Get-Module -Name AzureAD -ListAvailable
  if ($Modules.count -eq 0)
  {
    WriteError Please install AzureAD module using below command: `nInstall-Module AzureAD 
    exit
  }
  try {
    Get-AzureADCurrentSessionInfo -ErrorAction Stop | Out-Null
  } catch {
    #ERICH
    Connect-AzureAD -accountid $username |Out-Null
  }

}
}

$Result = ""
$Results = @()
$UserCount = 0
$PrintedUser = 0


 $DisplayIt  = ($CheckFor -ne "") 




$DisplayResult = ""

#
# Get Groups  
#
# Caching is used to reduce the query time by preloading the groups, Exchange Receiptients and AAD objects (Specific attributes)
#

$EXOList = @()

if ($FlushCache.IsPresent) {
  Remove-Item -LiteralPath $EXOCache -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $GrpCache1 -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $GrpCache2 -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $OGrpCache -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $UsrCache -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $AADCache -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $RolCache -ErrorAction SilentlyContinue
}




if (UseCache($GrpCache2, $false)) {
  Write-Progress -Activity "Loading Cached Special Group List"
  $SpecialGroupList = (Get-Content -Raw -LiteralPath $GrpCache2) | ConvertFrom-Json
  

} else {
    $SpecialGroupList = [pscustomobject]@()

    Write-Progress -Activity "Loading Group  List"
    
    $ShowSpecialGroups |  forEach-object {
            $G = $_
           Get-AzureADGroup -SearchString $G | Get-RecursiveAzureAdGroupMemberUsers   | ForEach-Object { 
           
            $SpecialGroupList += [pscustomobject]@{ 
                id = -join ($G, $_.ObjectId) ;
                Name = $G;
                
                objectID = $_.ObjectId;
                }
            }
        }
  
  if ($UseCaching) {
    $SpecialGroupList | ConvertTo-Json -Depth 1 -Compress | Set-Content -LiteralPath $GrpCache2
    }
}


if (UseCache($GrpCache1, $false)) {
  Write-Progress -Activity "Loading Cached Special Group List"
  $E5GroupList = (Get-Content -Raw -LiteralPath $GrpCache1) | ConvertFrom-Json
  

} else {

    Write-Progress -Activity "Loading Group  List"
  $E5GroupList = Get-ADGroup $E5GName | Get-ADGroupMember | Select-Object SID

  
  if ($UseCaching) {
    $E5GroupList | ConvertTo-Json -Depth 1 -Compress | Set-Content -LiteralPath $GrpCache1
    }
}


 
if ($IncludeGroups.IsPresent) {
if (UseCache($OGrpCache, $false)) {
  Write-Progress -Activity "Loading Cached Office Group List"
  $OfficeGroupList = (Get-Content -Raw -LiteralPath $OGrpCache) | ConvertFrom-Json
  

} else {

  Write-Progress -Activity "Loading OfficGroup  List"
  $OfficeGroupList = Get-ADGroup $OGrpName | Get-ADGroupMember | Select-Object SID

}
}


if ($ShowAllColumns.IsPresent) {

  if (UseCache($RolCache, $true)) {
    Write-Progress -Activity "Loading Cached Admin Roles"
    $RolesList = (Get-Content -Raw -LiteralPath $RolCache) | ConvertFrom-Json

  } else {
    Write-Progress -Activity "Loading Admin Roles" 

    $RolesList = [pscustomobject]@()

    $i = 1
    $GMR = (get-msolrole)
    $AMR  = (Get-AzureADDirectoryRole )
    
     $GMR | ForEach-Object { 
        $RName = $_.Name
        Write-Progress -Activity "Loading MSOL Admin Roles" -CurrentOperation  ($i.ToString() + "- " +$Rname) -PercentComplete ($i * 100 / ($GMR.count ))
        $i++
        Get-MsolRoleMember -RoleObjectId $_.ObjectID  | forEach-object {
          $RolesList += [pscustomobject]@{ 
                Key = -join ($_.ObjectID, $_.EmailAddress) ;
                Name = $RName ;
                ObjectID = $_.ObjectID ;
                RoleMemberType = $_.RoleMemberType ;
                EmailAddress = $_.EmailAddress ;
                DisplayName = $_.DisplayName
                }
            }
        }
 

    
  
  if ($UseCaching) {

    $RolesList | ConvertTo-Json | Set-Content -LiteralPath $RolCache
    
    }
  }
}


if ($IncludeExchange.IsPresent) {
  if (UseCache( $EXOCache, $false)) {
    Write-Progress -Activity "Loading Cached Exchange List"
    $EXOList = (Get-Content -Raw -LiteralPath $EXOCache | ConvertFrom-Json)
    
  }
  else {
    
    Write-Progress -Activity "Loading Exchange List"
    # $EXOList = (Get-EXORecipient -ResultSize 50000 -Properties PrimarySmtpAddress,RecipientType,RecipientTypeDetails,DistinguishedName -RecipientType DynamicDistributionGroup,MailContact,MailNonUniversalGroup,MailUniversalDistributionGroup,MailUniversalDistributionGroup,MailUser,UserMailbox)
    # Ignore Health mailboxes
    $EXOList = (Get-EXORecipient -ResultSize 50000 -Properties PrimarySmtpAddress,RecipientType,RecipientTypeDetails,DistinguishedName, ExternalDirectoryObjectId, Capabilities, Database,StorageGroupName -RecipientType DynamicDistributionGroup,MailNonUniversalGroup,MailUniversalDistributionGroup,MailUniversalDistributionGroup,MailUser,UserMailbox) | Where-Object PrimarySmtpAddress -NotLike "Health*"

    
    for ($i = 0; $i -lt $EXOList.Length; $i++)
    {
      $EXOList[$i].PrimarySmtpAddress = $EXOList[$i].PrimarySmtpAddress.ToLower()
    
      # Re-write/re-purpose the StorageGroupName field to be a Mailbox type field  
      $EXOList[$i].StorageGroupName = switch ($EXOList[$i].RecipientTypeDetails) {
            'MailUser'                       {'On-Premise' }
            'UserMailbox'                    {'Online' }
            'MailContact'                    {'Contact' }
            'MailUniversalDistributionGroup' {'Distribution Group' }
            'GuestMailUser'                  {'Guest user' }
            'MailUniversalSecurityGroup'     {'Security Group' }
            default { $EXOList[$i].RecipientTypeDetails.Replace('Mailbox', ' Mailbox') }
            }    
    }
    if ($UseCaching) {
        ($EXOList) | ConvertTo-Json -Compress | Set-Content -LiteralPath $EXOCache
        }
  }
    
  Write-Progress -Activity ("Exchange list size: " + $EXOList.count)
}

$AADList = $null

if ($ShowAllColumns.IsPresent -and !$DisplayIt) {
  if (UseCache( $AADCache, $false)) {
    
    $AADList = (Get-Content -Raw -LiteralPath $AADCache | ConvertFrom-Json)

  }
  else {
    
    $AADList = Get-AzureADUser -All $true | Select-Object ObjectID,UserType,CreationType,UserStateChangedOn,UserState,DisplayName,DirSyncEnabled 
    if ($UseCaching) {
        $AADList | ConvertTo-Json -Compress | Set-Content -LiteralPath $AADCache
        }
  }
}
#
# This are system level objects
#
#
$IgnoreObjects = @("HealthMailbox*")

  Write-Progress -Activity "Querying MSO Services" 

if ($CheckFor -ne "") {
  $who = (Get-MsolUser -SearchString $CheckFor)
  Write-Host "Searching for Users: " $CheckFor -BackgroundColor DarkYellow

 
} else {
  if ($EnabledOnly.IsPresent) {
    $who = (Get-MsolUser -EnabledFilter EnabledOnly -All)
  } elseif ($DisabledOnly.IsPresent) {
    $who = (Get-MsolUser -EnabledFilter DisabledOnly -All)
  } elseif ($TopX -ne -1) {
    $who = (Get-MsolUser -MaxResults $TopX)

 # } elseif ($Summary.IsPresent -or $IncludeSummary.IsPresent ) {
 #   $who = (Get-MsolUser -All | Where-Object isLicensed -EQ true)
  } else {
    $who = (Get-MsolUser -All)

  }
 
}


#--------------------------------------------------------------------------------------------------------------
# Summary and end
#--------------------------------------------------------------------------------------------------------------


$progressCnt = $who.count

if ($Summary.IsPresent) {
  doSummary
  exit
}
if ((Get-Item -LiteralPath $UsrCache -ErrorAction SilentlyContinue).LastWriteTime -gt (Get-Date).AddDays($CacheAge)) {

  ($AdAllUsers) = (Get-Content -Raw -LiteralPath $UsrCache | ConvertFrom-Json)
}
else {

  $AdAllUsers = Get-ADUser -Filter * -Properties msRTCSIP-DeploymentLocator,msRTCSIP-UserEnabled,DistinguishedName,msRTCSIP-PrimaryHomeServer,manager,Title,UserPrincipalName,EmployeeNumber,msExchHomeServerName -ResultSetSize 50000
  for ($i = 0; $i -lt $AdAllUsers.Length; $i++)
  {
    try {
      $AdAllUsers[$i].UserPrincipalName = $AdAllUsers[$i].UserPrincipalName.ToLower()
    }
    catch {
      # $i
      # Get-CurrentLine
    }
  }

  ($AdAllUsers) | Select-Object msRTCSIP-DeploymentLocator,msRTCSIP-UserEnabled,DistinguishedName,msRTCSIP-PrimaryHomeServer,manager,Title,SID,UserPrincipalName,ObjectGUID,ObjectClass,Name,EmployeeNumber,msExchHomeServerName | ConvertTo-Json -Compress | Set-Content -LiteralPath $UsrCache
}

#--------------------------------------------------------------------------------------------------------------
# Build the list of fields that will be dumped
#
#
# Column List
#--------------------------------------------------------------------------------------------------------------

$ColumnOut = 'DisplayName','UserPrincipalName'
if ($ShowAllColumns.IsPresent) {
  $ColumnOut += 'MFAStatus'
}
$ColumnOut += 'ActivationStatus','DefaultMFAMethod'
if ($ShowMFA.IsPresent) {
  $ColumnOut += 'AllMFAMethods','MFAPhone','MFAEmail'
}

$ColumnOut += 'LicenseStatus','SignInStatus','SIPLocation'

if ($IncludeTeams.IsPresent) {
  $ColumnOut += 'TeamsState', 'TeamsFederated'
}
if ($ShowAllColumns.IsPresent) {
  $ColumnOut += 'TeamsVoice'
}
if ($IncludeExchange.IsPresent) {
  $ColumnOut += 'ExOStatus'
  if ($ShowAllColumns.IsPresent) {  
    $ColumnOut += 'ExODetails'
    }
}

$ColumnOut += 'E5Licensed'
if ($ShowAllColumns.IsPresent) {
    $ColumnOut +='SpecialGroups'
    }

if ($ShowAllColumns.IsPresent) {
  $ColumnOut += 'PrimarySMTP','IsAdmin','AdminRoles','ExtraLicense'
}
if ($ShowAllColumns.IsPresent) {
  $ColumnOut +=  'Title','Manager','Type','Source', 'EmployeeNumber', 'CreateType', 'PhoneNumber', 'GroupCount'
}




$looptime = Get-Date
#--------------------------------------------------------------------------------------------------------------
#
#Loop through each user 
#
#--------------------------------------------------------------------------------------------------------------
$who | ForEach-Object {
  $UserCount++

  $DisplayName = $_.DisplayName
  $LastName = $_.LastName
  $Oid = $_.ObjectId
  $GroupCount ="-"

  $Upn = $_.UserPrincipalName
  $Lupn = $upn.ToLower()
  $thisUser = $_

  # Is this a System Object that we can ignore?
  
  $nextone = $False

  foreach ($IgnoreObj in $IgnoreObjects) {
    if ($Upn -like $IgnoreObj) {
        Write-Verbose ("Ignoring " + $DisplayName)
        $nextone = $true
        }
    }
  
  if ($nextone) {
    return
    }

  
  $isTeams = ""
  $ExOStatus = "NC"
  $ExODetails = ""
  $UserType = ""
  $CreateType = ""
  $MFAStatus = $_.StrongAuthenticationRequirements.State
  $MethodTypes = $_.StrongAuthenticationMethods
  $E5Licensed = ""
  $SpecialGroups = ""
  $ExOStatus = "NC"
  $Manager = "NC"
  $ExtraLicense = ""
  $Title = "NC"
  $PrimeSMTP = ""
  $DirSource = ""
  $EmployeeNumber = ""
  $lastTime = ""

  $projTime = ((Get-Date).Subtract($looptime).TotalSeconds * (($progressCnt / $UserCount) - 1.0))
  $elapTime = ((Get-Date).Subtract($runtime)).ToString('hh\:mm\:ss')
  Write-Progress -Activity "`n     Processed user count: $UserCount / $progressCnt  - $DisplayName   " `n" Elaspsed: $elapTime  " -PercentComplete (100 * $UserCount / $progressCnt) -SecondsRemaining $projTime    





  if ($_.BlockCredential -eq "True")
  {
    $SignInStatus = "False"
    $SignInStat = "Denied"
  }
  else
  {
    $SignInStatus = "True"
    $SignInStat = "Allowed"
  }

  #Filter result based on SignIn status 
  if (($SignInAllowed -ne $null) -and ([string]$SignInAllowed -ne [string]$SignInStatus))
  {

    return
  }

  # if ($LastName -eq "") -or $LastName -eq $null)) {

  #   return
  # }
  # $lastTime = $thisUser.lastSignInDateTime


  #Filter result based on License status 
  if ((($LicensedUserOnly.IsPresent) -and ($_.IsLicensed -eq $False)) -and -not $ShowAllColumns.IsPresent)
  {

    return
  }

  #Check for user's Admin role 

  $Roles = $RolesList | Where-Object { $_.ObjectId -eq $oid} 
  if ($Roles.count -eq 0)
  {
    $RolesAssigned = "-"
    $IsAdmin = "-"
  }
  else
  {
    $IsAdmin = "True"
    $RolesAssigned = ""
    foreach ($Role in $Roles)
    {
      if ($RolesAssigned -ne "") {
        $RolesAssigned = $RolesAssigned + ","
        }
      $RolesAssigned = $RolesAssigned + $Role.Name
      
    }
  }
  #Filter result based on Admin users 
  if (($AdminOnly.IsPresent) -and ([string]$IsAdmin -eq "-"))
  {
    return
  }

  #--------------------------------------------------------------------------------------------------------------
  # MFA
  #
  #


  # checking this user if the not disabled, has MFA or if ListAll

  #Check for MFA enabled user 
  if ((($MethodTypes -ne $Null) -or ($MFAStatus -ne $Null) -and (-not ($DisabledOnly.IsPresent))) -or $ShowAllColumns.IsPresent)
  {
    #Check for Conditional Access 
    if (($MethodTypes -eq $null) -and ($MFAStatus -eq $null))
    {
      $MFAStatus = 'None'
    } else {
      if ($MFAStatus -eq $null) {

        $MFAStatus = 'Enabled via Conditional Access'
      }
    }

    #Filter result based on EnforcedOnly filter 
    if ((([string]$MFAStatus -eq "Enabled") -or ([string]$MFAStatus -eq "Enabled via Conditional Access")) -and ($EnforcedOnly.IsPresent))
    {
      return
    }

    #Filter result based on EnabledOnly filter 
    if (([string]$MFAStatus -eq "Enforced") -and ($EnabledOnly.IsPresent))
    {
      return
    }

    #Filter result based on MFA enabled via conditional access 
    if ((($MFAStatus -eq "Enabled") -or ($MFAStatus -eq "Enforced")) -and ($ConditionalAccessOnly.IsPresent))
    {
      return
    }

    $Methods = ""
    $MethodTypes = ""
    $MethodTypes = $_.StrongAuthenticationMethods.MethodType
    $DefaultMFAMethod = ($_.StrongAuthenticationMethods | Where-Object { $_.IsDefault -eq "True" }).MethodType
    $MFAPhone = $_.StrongAuthenticationUserDetails.PhoneNumber
    if ($MFAPhone -like "+1*") {
      $MFAPhone = ($MFAPhone.Substring(1,5)) + "-" + ($MFAPhone.Substring(6,1)) + "xx-xx" + ($MFAPhone.Substring($MFAPhone.Length - 2))
    }
    $MFAEmail = $_.StrongAuthenticationUserDetails.Email

    if ($MFAPhone -eq $Null)
    { $MFAPhone = "-" }
    if ($MFAEmail -eq $Null)
    { $MFAEmail = "-" }


    #  $findupn = -join ('userprincipalName -like "', $upn, '"') 

    # $lUPN

    # $AdAllUsers.UserPrincipalName.Indexof($LUpn)

    $findAD = $AdAllUsers[$AdAllUsers.UserPrincipalName.IndexOf($LUpn)]
    if ($findAD.UserPrincipalName -ne $Lupn) {
        $findAD = $null
        Write-Verbose ("NO Person in AD for ObjectId:" + $oid)
        }
    if ($ShowAllColumns.IsPresent) {
      
      if ($findAD.manager -eq $null) {
        $Manager = "<blank>"
      } else {
        $Manager = ($AdAllUsers[$AdAllUsers.DistinguishedName.IndexOf($findAD.manager)]).Name

      }
    }
    $Title = $findAD.Title

    # If you have EMployee or contractor attributes used or not users in on-premise AD.    CONFIGURATIONHERE
    if ($ShowEmpNum.IsPresent) {
        $EmployeeNumber = $findAD.EmployeeNumber
        }
    else
        {
        if ($findAD -ne $null) {
            $EmployeeNumber = $findAD.EmployeeNumber
            if ($EmployeeNumber -ne $null) {
                $EmployeeNumber = $EmployeeNumber.ToString()
                if ($EmployeeNumber.Length -gt 3) {
                    $EmployeeNumber = $EmployeeNumber -replace "\d\d\d$", "xxx"  
                    }
                }
            }
        }


#--------------------------------------------------------------------------------------------------------------
# GROUPS
#
#

    $E5Licensed = "-"
    $SpecialGroups = "-"

    # $E5GroupList.SID
    if ($findAD.DistinguishedName -ne $null) {
      if ($findAD.SID.Value -in $E5GroupList.SID) {
        $E5Licensed = "True"
      }
      
       $SpecialGroups = ($SpecialGroupList |Where-Object objectID -like $oid).Name
       
      
    }

#--------------------------------------------------------------------------------------------------------------
# Licensing 
#
#
# https://docs.microsoft.com/en-us/azure/active-directory/users-groups-roles/licensing-service-plan-reference


        $lic = $thisUser | Select-Object -ExpandProperty licenses | Where-Object accountskuid -Like $sku | Select-Object -ExpandProperty servicestatus
        # $lic | ft
        for ($k = 0; $k -lt ($lic).count; $k++)
        {
        
          if (($lic.serviceplan[$k].servicename -in ($selectSkus).Code) -and ($lic.provisioningstatus[$k] -ne "Disabled")) {
            $findsku = $selectSkus | Where-Object Code -EQ $lic.serviceplan[$k].servicename
            
            if ($lic.serviceplan[$k].servicename -like "MCO*") {
              if ($isTeams.Length -gt 1) { $isTeams = $isTeams + ", " }
            
              $isTeams += -join ($findsku.Name,"(",$lic.provisioningstatus[$k],")")

            }
            else {
              $n = $findsku.Name
              if ($ExtraLicense.Length -gt 1) { $ExtraLicense = $ExtraLicense + ", " }
              $ExtraLicense = $ExtraLicense + -join ($n,"(",$lic.provisioningstatus[$k],")")
            }


          }
        }
    
    # You can only see Teams List if you are Teams Admin
    if ($TeamCount.IsPresent) {
      $cntTeams = (Get-Team -user $upn).count
    }

    if ($MethodTypes -ne $Null)
    {
      $ActivationStatus = "Yes"
      foreach ($MethodType in $MethodTypes)
      {
        if ($Methods -ne "")
        {
          $Methods = $Methods + ","
        }
        $Methods = $Methods + $MethodType
      }


    }

    else
    {
      $ActivationStatus = "No"
      $Methods = "-"
      $DefaultMFAMethod = "-"
      $MFAPhone = "-"
      $MFAEmail = "-"
      $E5Licensed = "-"
      $SpecialGroups = "-"
      $ExOStatus = "NC-"
      $Manager = "-"

    }
                   

#--------------------------------------------------------------------------------------------------------------
# Exchange
#
#

    if ($IncludeExchange.IsPresent) {

      $ExOStatus = "Nobox"
      $SIPLocation = ""

      # $find = ($EXOList | Where-Object {$_.PrimarySmtpAddress -like $Upn})

      # $ExOStatus = $find.RecipientTypeDetails

      $i = ($EXOList.ExternalDirectoryObjectId | Select-String $oid).LineNumber - 1
            
      if (($i -ne $null) -and ($i -ne -1)) {
        if  ($EXOList[$i].StorageGroupName -like "On-Premise") {
            if ($findAD.msExchHomeServerName -like "") {
                $EXOList[$i].StorageGroupName  = "-"
                $EXOList[$i].RecipientType = "-"
                
                }
            }

        $ExOStatus = $EXOList[$i].StorageGroupName 
        $ExODetails = $EXOList[$i].RecipientType + "/" + $EXOList[$i].RecipientTypeDetails
        $PrimeSMTP = $EXOList[$i].PrimarySmtpAddress
        
        }
        else { $PrimeSMTP ="<??>" }
    


    }

#--------------------------------------------------------------------------------------------------------------
# Teams/Skype Status
#
#

    $spl = @("","")
    if ($findad -ne $null) {
    if ((($findad).'msRTCSIP-PrimaryHomeServer') -ne $null) {
      $spl = (($findad).'msRTCSIP-PrimaryHomeServer').split(",",4)
      $spl = $spl.split("=",2)
      
      
    }


    $SIPLocation = switch (($findad).'msRTCSIP-DeploymentLocator') {
      "sipfed.online.lync.com" { "TeamsOnly" }
      "SRV:" { -join ("SkypeOnPrem#", $spl[5]) }
      default { "" }
    }
    
    }
    $TeamsCS = @{}
    $TeamsState = ""
    $TeamsFedState = ""
    if (($IncludeTeams.IsPresent) -and ($UserType -eq "User")) {
      $TeamsCS = (get-csonlineuser -Identity $Upn) 
      $TeamsState =  $TeamsCS | Select-Object -ExpandProperty TeamsUpgradeEffectiveMode -ErrorAction SilentlyContinue
      $TeamsState += "," + $TeamsCS | Select-Object -ExpandProperty TeamsUpgradePolicy -ErrorAction SilentlyContinue
      $TeamsState += "," + $TeamsCS | Select-Object -ExpandProperty HostedVoicemailPolicy -ErrorAction SilentlyContinue
      $TeamsFedState =  $TeamsCS | Select-Object -ExpandProperty ExternalAccessPolicy -ErrorAction SilentlyContinue      
    }

 # ------------------------------------------------------
 # Count Staff Conditional
 #
 #
    if ($findAD -ne $null) {
        if  ($ActivationStatus -eq "Yes" -and $_.IsLicensed) {        
            $n = $findAD.EmployeeNumber
            
                # if online with ExO switch otherwise igore Online
                # Numbering of Contractors is different than employees
                if ($n -gt 0) {                    
                     if ($ExOStatus -eq "Online" -or (-not $IncludeExchange.IsPresent)) { 
                        if ($EmployeeNumber -lt 400000) {
                            $EmpoyeeCount++
                            }
                        else {
                            $ContractCount++
                            }
                        
                     } else {
                        if ($EmployeeNumber -lt 400000) {
                            $EmpoyeeCountLeft++
                            }
                        else {
                            $ContractCountLeft++
                            }
                        }
                   
                   }
                }
            }
        
 

#--------------------------------------------------------------------------------------------------------------
# Extra attributes
#   E-mail address
#   Creation date and state for Guest
#   Source
#
#

    if ($ShowAllColumns.IsPresent) {
      if ($AADList -eq $null) {
         $AzUser = Get-AzureADUser -ObjectId $Oid
      } else {
        $i = ($AADList.ObjectId | Select-String $oid).LineNumber - 1
        if ($i -eq -1) { 
            Write-Warning ("AAD Object not found" + $oid) 
            $AzUser = $null
            }
        else {
            $AzUser = $AADList[$i]
            }
        

      }
      $UserType = $AzUser.UserType

      $GroupCount = ($AzUser | Get-AzureADUserMembership).count
      #
      # Guests
      #
      if ($PrimeSMTP -eq "<??>" -or $PrimeSMTP -eq "") {
        if ($thisUser.SignInName -ne "" ) {
        $PrimeSMTP = $thisUser.SignInName
        }
      }

      if ($AzUser.DirSyncEnabled -like "") {
        $DirSource = "Cloud" }
        else {
         $DirSource = "WindowsAD"
         }

      $CreateType = $AzUser.CreationType
      if ($CreateType -eq $null) {
        If ($UserType -eq "Guest") {
            $CreateType = -join ("(Created:", $thisUser.WhenCreated)
            }
      } else {
        $CreateType = -join ($CreateType," (",$AzUser.UserState,":",$AzUser.UserStateChangedOn,")")
      }
      
    }
    #Print to output file 
    $PrintedUser++
    ## # not exporting "cntTeams"=$cntTeams;

    $Result = @{ 'DisplayName' = $DisplayName; 'UserPrincipalName' = $upn; 'MFAStatus' = $MFAStatus; 'ActivationStatus' = $ActivationStatus; 'DefaultMFAMethod' = $DefaultMFAMethod; 
    'AllMFAMethods' = $Methods; 'MFAPhone' = $MFAPhone; 'MFAEmail' = $MFAEmail; 'LicenseStatus' = $_.IsLicensed; 'IsAdmin' = $IsAdmin; 'AdminRoles' = $RolesAssigned; 'SignInStatus' = $SigninStat; 
    'E5Licensed' = $E5Licensed; 'SpecialGroups' = $SpecialGroups; "TeamsVoice" = $isTeams; "TeamsState" = $TeamsState; "TeamsFederated" = $TeamsFedState; "SIPLocation" = $SIPLocation; "ExOStatus" = $ExOStatus;
    "ExODetails" = $ExODetails; "ExtraLicense" = $ExtraLicense; "Manager" = $Manager; "Title" = $Title; "Type" = $UserType; "CreateType" = $CreateType; 'PrimarySMTP' = $PrimeSMTP; 'EmployeeNumber' = $EmployeeNumber; 
     'Source' = $DirSource; 'LastSignin' = $lastTime ; 'PhoneNumber' = $thisUser.PhoneNumber; 'GroupCount' = $GroupCount}
    $Results = New-Object PSObject -Property $Result


    $ResultOut = ($Results | Select-Object $ColumnOut)

    if ($DisplayIt) {
      $ResultOut | Format-List
    } else  {
      $ResultOut | Export-Csv -Path $ExportCSVReport -Notype -Append
    }
  }
#--------------------------------------------------------------------------------------------------------------
# Disabled Users
#
#

  #Check for disabled userwe 
  elseif (($DisabledOnly.IsPresent) -and ($MFAStatus -eq $Null) -and ($_.StrongAuthenticationMethods.MethodType -eq $Null))
  {
    $MFAStatus = "Disabled"
    $Department = $_.Department
    if ($Department -eq $Null)
    { $Department = "-" }
    $PrintedUser++

    $Result = @{ 'DisplayName' = $DisplayName; 'UserPrincipalName' = $upn; '$Department' = $Department; 'MFAStatus' = $MFAStatus; 'LicenseStatus' = $_.IsLicensed; 'IsAdmin' = $IsAdmin; 'AdminRoles' = $RolesAssigned; 'SignInStatus' = $SigninStat }
    $Results = New-Object PSObject -Property $Result
#--------------------------------------------------------------------------------------------------------------
# Show or Write to a CSV file the results
#
#

    if ($DisplayIt) {
      $Results | Select-Object DisplayName,UserPrincipalName,MFAStatus,LicenseStatus,IsAdmin,AdminRoles,SignInStatus,lastSignInDateTime | Format-List
    } else{   
      $Results | Select-Object DisplayName,UserPrincipalName,MFAStatus,LicenseStatus,IsAdmin,AdminRoles,SignInStatus,lastSignInDateTime | Export-Csv -Path $ExportCSV -Notype -Append
    }

  }
}

#--------------------------------------------------------------------------------------------------------------
# Wrap up
#
#




#Open output file after execution  
Write-Host Script executed successfully - Completed (Get-Date -DisplayHint Time) ((Get-Date).Subtract($runtime).ToString('dd\.hh\:mm\:ss'))

if ($IncludeSummary.IsPresent) {
   doSummary
   }
if ($DisplayIt) {
  if ($PrintedUser -gt 0) {
    Write-Host Found $PrintedUser users
  }
  else {
    if ($UserCount -gt 0) {
      Write-Host User found: $UserCount but without MFA
    }
    else {
      Write-Host No user found that matches your criteria.
    }
  }
} else {
  if ((Test-Path -Path $ExportCSV) -eq "True")
  {
    Write-Host "MFA Disabled user report available in: $ExportCSV"
    $Prompt = New-Object -ComObject wscript.shell
    $UserInput = $Prompt.popup("Do you want to open output file?",
      0,"Open Output File",4)
    if ($UserInput -eq 6)
    {
      Invoke-Item "$ExportCSV"
    }
    Write-Host Exported report has $PrintedUser users
  }
  elseif ((Test-Path -Path $ExportCSVReport) -eq "True")
  {
    Write-Host "MFA Enabled user report available in: $ExportCSVReport" -ForegroundColor DarkYellow

    $Prompt = New-Object -ComObject wscript.shell
    $UserInput = $Prompt.popup("Do you want to open output file?",10,"Open Output File",0x124)
    if ($UserInput -eq 6)
    {
      Invoke-Item "$ExportCSVReport"
    }
    Write-Host Exported report has $PrintedUser users of $progressCnt
    }
  if ((Test-Path -Path $ExportCSVTeams) -eq "True")
  {
    Write-Host "Teams Summary report available in: $ExportCSVTeams" -ForegroundColor DarkYellow

    $Prompt = New-Object -ComObject wscript.shell
    $UserInput = $Prompt.popup("Do you want to open output file?",10,"Open Teams Report",0x124)
    if ($UserInput -eq 6)
    {
      Invoke-Item "$ExportCSVTeams"
    }
    Write-Host Exported report has $PrintedUser users of $progressCnt
    Write-Host "Teams Site Summary : $ExportCSVTeams" -ForegroundColor DarkYellow

  }
  else
  {
    if ($UserCount -gt 0) {
      Write-Host User found: $UserCount but without MFA
    }
    else {
      Write-Host No user found that matches your criteria.
    }
  }
}




#Clean up session  
# Get-PSSession | Remove-PSSession

#--------------------------------------------------------------------------------
#  CheckUser365.ps1
#
# DISCLAIMER - Trial and error built... it may work/stop working  in a few months based on what MS does in Azure
#
# All the interesting things you want to know about users and guest while you are migrating to Office 365.
#
# This was create through many iterations and trial/error.  I'm sure there is a cleaner way of bring this information together,
# but it evolved over time.  For the AzureAD queries has components of MSOL and EXO within it.  I'm sure there is a better way to do this.
# The Cache is used since 
#  -Summary            will give a summary of Licenses, Groups Mailboxes (if IncludeExchange is used)
#  -IncludeExchange    Pull mailbox information
#  -CheckFor           Allow to search for a user or part of a user  ..  -CheckFor Darren
#                      This also makes it just displays the results instead of putting them into a CSV
#  -ShowMFA            Displays the MFA authenications details
#  -ShowAllColumns     Pull everything... all columns
#                      If none of the filters are applied it will pull all the objects
#  -IncludeTeams       give information about TeamsUpgradePolicy and ExternalAccessPolicy, but it is a very slow process
#  
#
# Caching - it takes time to query MS, so in order to acccelrate that, caching was added for Roles, Exo, Groups, AD Users
#       AAD Users, this can reduces the look time for a query from 20 seconds down to 4 seconds.
#       The cache TTL is 24 hours,  It caches, groups, AD Users, Exo state, and Roles.
#       The 'Live data' is the MSOL/AAD state of users
#
# Orginal sources Robert Luck 
#     https://gallery.technet.microsoft.com/scriptcenter/Export-Office-365-Users-81747c73
#     https://o365reports.com/2019/05/09/export-office-365-users-mfa-status-csv/
# Other github reference 
#     https://github.com/michelvoillery/The-Code-Repository/blob/5d7b64aa4eed433dfa506e7d4289afa823b54ff9/Scripts/Export%20Office%20365%20Users%20MFA%20Status.md
# 
# For us we used groups to apply licenses which is why we want those.
# 
#--------------------------------------------------------------------------------


param
(
  [Parameter(Mandatory = $false)]
  [switch]$Summary,                    # Summary of objects & Licenses
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
  [switch]$FlushCache,                # to clear all the program generated caches 
  [int32]$TopX = -1,
  [switch]$TeamCount
)


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


$scriptversion = "v.20.10.4"
$runtime = Get-Date


#$sku = "*:ENTERPRISEPACK"
$sku = "*"
$E5GName = "Azure_License_MBaseE5"
$CRMGName = "CRM 2015 Users Test"

#Caching files to speed up startup run of script
$UseCaching = 1
$CacheAge = -1    # one day Cache
$EXOCache = $env:TEMP  + "\CheckUser365.Exo.Cache"
$GrpCache1 = $env:TEMP  + "\CheckUser365.grp1.Cache"
$GrpCache2 = $env:TEMP  + "\CheckUser365.grp2.Cache"
$UsrCache = $env:TEMP  + "\CheckUser365.usr.Cache"
$AADCache = $env:TEMP  + "\CheckUser365.AAD.Cache"
$RolCache = $env:TEMP  + "\CheckUser365.Rol.Cache"


#Output file declaration 
$ExportCSV = ".\MFADisabledUserReport_$((Get-Date -format yyyy-MMM-dd-ddd` hh-mm` tt).ToString()).csv"
$ExportCSVReport = ".\MFAEnabledUserReport_$((Get-Date -format yyyy-MMM-dd-ddd` hh-mm` tt).ToString()).csv"

function Get-CurrentLine {
  -join ("Line: ",$Myinvocation.ScriptlineNumber)
}

function UseCache {
param (
        [string[]]$CacheFile
    )
    
    Return  ($UseCaching -and  ((Get-Item -LiteralPath $CacheFile -ErrorAction SilentlyContinue).LastWriteTime -gt (Get-Date).AddDays($CacheAge)))
    
    
 }





#Check for MSOnline module 
$Modules = Get-Module -Name MSOnline -ListAvailable
if ($Modules.count -eq 0)
{
  Write-Host Please install MSOnline module using below command: `nInstall-Module MSOnline -ForegroundColor yellow
  exit
}

Write-Host -BackgroundColor DarkGreen ("CheckUser365 : " + $scriptversion)
Write-Progress -Activity ("CheckUser365 - " + $scriptversion + "`n... Connecting... `n")
#Storing credential in script for scheduling purpose/ Passing credential as parameter  
if (($UserName -ne "") -and ($Password -ne ""))
{
  $SecuredPassword = ConvertTo-SecureString -AsPlainText $Password -Force
  $Credential = New-Object System.Management.Automation.PSCredential $UserName,$SecuredPassword
  Connect-MsolService -Credential $credential
}
else
{

  try {
    Get-MsolDomain -ErrorAction Stop | Out-Null
  } catch {
    Write-Progress -Activity ("CheckUser365 - " + $scriptversion + "`n... Connecting ... `n")
    Connect-MsolService | Out-Null

  }

}

# this required TeamsAdmin or GlobalAdmin
if ($TeamCount.IsPresent -or $IncludeTeams.IsPresent) {
  $Modules = Get-Module -Name MicrosoftTeams -ListAvailable
  if ($Modules.count -eq 0)
  {
    Write-Host Please install MicrosoftTeams module using below command: `nInstall-Module MicrosoftTeams -ForegroundColor yellow
    exit
  }
  Write-Host " -IncludeTeams is a slow option" -BackgroundColor DarkRed
  try {
    Get-TeamsApp -ErrorAction Stop | Out-Null
  } catch {
    Connect-MicrosoftTeams | Out-Null
    
  }

}

if ($IncludeExchange.IsPresent) {
  $Modules = Get-Module -Name ExchangeOnlineManagement -ListAvailable
  if ($Modules.count -eq 0)
  {
    Write-Host Please install ExchangeOnlineManagement module using below command: `nInstall-Module ExchangeOnlineManagement -ForegroundColor yellow
    exit
  }
  if (!((Pssession).Name -like "Exchange*")) {
    Connect-ExchangeOnline | Out-Null
  }


if ($ShowAllColumns.IsPresent) {
  $Modules = Get-Module -Name AzureADPreview -ListAvailable
  if ($Modules.count -eq 0)
  {
    Write-Host Please install AzureADPreview module using below command: `nInstall-Module AzureADPreview -ForegroundColor yellow
    exit
  }
  try {
    Get-AzureADCurrentSessionInfo -ErrorAction Stop | Out-Null
  } catch {
    Connect-AzureAD | Out-Null
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
  Remove-Item -LiteralPath $UsrCache -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $AADCache -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $RolCache -ErrorAction SilentlyContinue
}




if (UseCache($GrpCache1)) {
  Write-Progress -Activity "Loading Cached Group List"
  $E5GroupList = (Get-Content -Raw -LiteralPath $GrpCache1) | ConvertFrom-Json
  $CRMgroupList = (Get-Content -Raw -LiteralPath $GrpCache2) | ConvertFrom-Json


} else {

    Write-Progress -Activity "Loading Group  List"
  $E5GroupList = Get-ADGroup $E5GName | Get-ADGroupMember | Select-Object SID

  $CRMgroupList = Get-ADGroup $CRMGName | Get-ADGroupMember | Select-Object SID

  if ($UseCaching) {
    $E5GroupList | ConvertTo-Json -Depth 1 -Compress | Set-Content -LiteralPath $GrpCache1
    $CRMgroupList | ConvertTo-Json -Depth 1 -Compress | Set-Content -LiteralPath $GrpCache2
    }
}

if (UseCache($RolCache)) {
  Write-Progress -Activity "Loading Cached Admin Roles"
  $RolesList = (Get-Content -Raw -LiteralPath $RolCache) | ConvertFrom-Json

} else {
  Write-Progress -Activity "Loading Admin Roles" 

  $RolesList = [pscustomobject]@()

    $i = 1
    $GMR = (get-msolrole)
    $GMR | ForEach-Object { 
        $RName = $_.Name
        Write-Progress -Activity "Loading Admin Roles" -CurrentOperation  ($i.ToString() + "- " +$Rname) -PercentComplete ($i * 100 / $GMR.count)
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



if ($IncludeExchange.IsPresent) {
  if (UseCache( $EXOCache, "Exchange")) {
    Write-Progress -Activity "Loading Cached Exchange List"
    $EXOList = (Get-Content -Raw -LiteralPath $EXOCache | ConvertFrom-Json)
    
  }
  else {
    
    Write-Progress -Activity "Loading Exchange List"
    $EXOList = (Get-EXORecipient -ResultSize 50000 -Properties PrimarySmtpAddress,RecipientType,RecipientTypeDetails,DistinguishedName -RecipientType DynamicDistributionGroup,MailContact,MailNonUniversalGroup,MailUniversalDistributionGroup,MailUniversalDistributionGroup,MailUser,UserMailbox)


    
    for ($i = 0; $i -lt $EXOList.Length; $i++)
    {
      $EXOList[$i].PrimarySmtpAddress = $EXOList[$i].PrimarySmtpAddress.ToLower()
    }
    if ($UseCaching) {
        ($EXOList) | ConvertTo-Json -Compress | Set-Content -LiteralPath $EXOCache
        }
  }
    
  Write-Progress -Activity ("Exchange list size" + $EXOList.count)
}

$AADList = $null

if ($ShowAllColumns.IsPresent -and !$DisplayIt) {
  if (UseCache( $AADCache, "AAD")) {
    
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
  Write-Host "Searching for Users: " $CheckFor -

 
} else {
  if ($EnabledOnly.IsPresent) {
    $who = (Get-MsolUser -EnabledFilter EnabledOnly -All)
  } elseif ($DisabledOnly.IsPresent) {
    $who = (Get-MsolUser -EnabledFilter DisabledOnly -All)
  } elseif ($TopX -ne -1) {
    $who = (Get-MsolUser -MaxResults $TopX)

  } elseif ($Summary.IsPresent) {
    $who = (Get-MsolUser -EnabledFilter EnabledOnly -All | Where-Object isLicensed -EQ true)
  } else {
    $who = (Get-MsolUser -All)

  }
 
}


$progressCnt = $who.count

if ($Summary.IsPresent) {
  Write-Host "----------     Summary       -----------" -BackgroundColor DarkYellow

  Write-Output ("Total users account in Azure " + $progressCnt)
  if ($IncludeExchange.IsPresent) {
    Write-Output ("Mailboxes")
    Write-Output ("   online          " + ($EXOList.RecipientType | Select-String "UserMailbox").count)
    Write-Output ("   On-Premise      " + ($EXOList.RecipientType | Select-String "MailUser").count)
    Write-Output ("   Contacts        " + ($EXOList.RecipientType | Select-String "MailContact").count)
    Write-Output ("   Distribute List " + ($EXOList.RecipientType | Select-String "MailUniversalDistributionGroup").count)
    Write-Output ("   Guest IDs       " + ($EXOList.RecipientTypeDetails | Select-String "GuestMailUser").count)


  }
  Write-Output ("Licensed & Enabled accounts " + $who.count)
  Write-Output ("Users in Azure License E5   " + $E5GroupList.count)
  Write-Output ("Users in CRM Group          " + $CRMgroupList.count)
  exit
}
if ((Get-Item -LiteralPath $UsrCache -ErrorAction SilentlyContinue).LastWriteTime -gt (Get-Date).AddDays($CacheAge)) {

  ($AdAllUsers) = (Get-Content -Raw -LiteralPath $UsrCache | ConvertFrom-Json)
}
else {

  $AdAllUsers = Get-ADUser -Filter * -Properties msRTCSIP-DeploymentLocator,msRTCSIP-UserEnabled,DistinguishedName,msRTCSIP-PrimaryHomeServer,manager,Title,UserPrincipalName,EmployeeNumber -ResultSetSize 50000
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

  ($AdAllUsers) | Select-Object msRTCSIP-DeploymentLocator,msRTCSIP-UserEnabled,DistinguishedName,msRTCSIP-PrimaryHomeServer,manager,Title,SID,UserPrincipalName,ObjectGUID,ObjectClass,Name,EmployeeNumber | ConvertTo-Json -Compress | Set-Content -LiteralPath $UsrCache
}

# Build the list of fields that will be dumped

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
}

$ColumnOut += 'E5Licensed'
if ($ShowAllColumns.IsPresent) {
    $ColumnOut +='CRMuser'
    }

if ($ShowAllColumns.IsPresent) {
  $ColumnOut += 'PrimarySMTP','IsAdmin','AdminRoles','ExtraLicense'
}
if ($ShowAllColumns.IsPresent) {
  $ColumnOut +=  'Title','Manager','Type','Source', 'EmployeeNumber', 'CreateType','LastSignin'
}

$looptime = Get-Date
#
#
#Loop through each user 
#
$who | ForEach-Object {
  $UserCount++

  $DisplayName = $_.DisplayName
  $LastName = $_.LastName
  $Oid = $_.ObjectId


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
  $ExOStatus = ""
  $UserType = ""
  $CreateType = ""
  $MFAStatus = $_.StrongAuthenticationRequirements.State
  $MethodTypes = $_.StrongAuthenticationMethods
  $E5Licensed = ""
  $CRMuser = ""
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
  $lastTime = $thisUser.lastSignInDateTime


  #Filter result based on License status 
  if (($LicensedUserOnly.IsPresent) -and ($_.IsLicensed -eq $False))
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
  if (($AdminOnly.IsPresent) -and ([string]$IsAdmin -eq "False"))
  {
    return
  }

  

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
      $MFAPhone = ($MFAPhone.Substring(1,5)) + "-xxx-xx" + ($MFAPhone.Substring($MFAPhone.Length - 2))
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
                    $EmployeeNumber = -join($EmployeeNumber.remove(3), "xxx")
                    }
                }
            }
        }
    $E5Licensed = "-"
    $CRMuser = "-"

    # $E5GroupList.SID
    if ($findAD.DistinguishedName -ne $null) {
      if ($findAD.SID.Value -in $E5GroupList.SID) {
        $E5Licensed = "True"
      }
      # if ($CRMGname -in $adgroups.name) {
      if ($findAD.SID.Value -in $CRMgroupList.SID) {
        $CRMuser = "True"
      }
    }

    # $EXOList = (Get-EXORecipient -PrimarySmtpAddress $upn -ResultSize 10  -RecipientType MailUser, UserMailbox -ErrorAction Ignore| Select-Object PrimarySmtpAddress,  RecipientType, RecipientTypeDetails)

    #        }
    #    else {
    #       
    #       if ($Oid -in $E5.Objectid )
    #       {
    #         $E5Licensed="True" 
    #
    #        } 
    #        if ($Oid -in $CRMgroup.Objectid)
    #        {
    #          $CRMuser="True" 
    #
    #        } 
    #    }


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
      $CRMuser = "-"
      $ExOStatus = "-"
      $Manager = "-"

    }
    if ($IncludeExchange.IsPresent) {

      $ExOStatus = ""
      $SIPLocation = ""

      # $find = ($EXOList | Where-Object {$_.PrimarySmtpAddress -like $Upn})

      # $ExOStatus = $find.RecipientTypeDetails

      $i = ($EXOList.ExternalDirectoryObjectId | Select-String $oid).LineNumber - 1
            
      if (($i -ne $null) -and ($i -ne -1)) {
        $ExOStatus = $EXOList[$i].RecipientTypeDetails
        $PrimeSMTP = $EXOList[$i].PrimarySmtpAddress
        }
        else { $PrimeSMTP ="<??>" }
    


      $ExOStatus = switch ($ExOStatus) {
        "UserMailbox" { "ExchangeOneline" }
        "MailUser" { "On-Premise" }
        "MailContact" { "Contact" }
        default { $ExOStatus }
      }
    }
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

    $TeamState = ""
    $TeamFedState = ""
    if ($IncludeTeams.IsPresent) {
      $TeamState = Get-CsUserPolicyAssignment -PolicyType TeamsUpgradePolicy -Identity $Upn -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PolicyName
      
      $TeamFedState += Get-CsUserPolicyAssignment -PolicyType ExternalAccessPolicy -Identity $Upn -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PolicyName
      
      # $TeamState = $TeamState -join (Get-CsUserPolicyAssignment -PolicyType OnlineVoiceRoutingPolicy  -Identity $Upn       | Select-Object -ExpandProperty PolicyName)
      # if ($TeamState -eq "") { $TeamState = "Default" }
      # if ($TeamFedState -eq "") { $TeamFedState = "Default" }
    }
    else {
      $TeamState = ""
    }


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

    $Result = @{ 'DisplayName' = $DisplayName; 'UserPrincipalName' = $upn; 'MFAStatus' = $MFAStatus; 'ActivationStatus' = $ActivationStatus; 'DefaultMFAMethod' = $DefaultMFAMethod; 'AllMFAMethods' = $Methods; 'MFAPhone' = $MFAPhone; 'MFAEmail' = $MFAEmail; 'LicenseStatus' = $_.IsLicensed; 'IsAdmin' = $IsAdmin; 'AdminRoles' = $RolesAssigned; 'SignInStatus' = $SigninStat; 'E5Licensed' = $E5Licensed; 'CRMuser' = $CRMuser; "TeamsVoice" = $isTeams; "TeamsState" = $TeamState; "TeamsFederated" = $TeamFedState; "SIPLocation" = $SIPLocation; "ExOStatus" = $ExOStatus; "ExtraLicense" = $ExtraLicense; "Manager" = $Manager; "Title" = $Title; "Type" = $UserType; "CreateType" = $CreateType; 'PrimarySMTP' = $PrimeSMTP; 'EmployeeNumber' = $EmployeeNumber; 'Source' = $DirSource; 'LastSignin' = $lastTime }
    $Results = New-Object PSObject -Property $Result


    $ResultOut = ($Results | Select-Object $ColumnOut)

    if ($DisplayIt) {
      $ResultOut | Format-List
    } else  {
      $ResultOut | Export-Csv -Path $ExportCSVReport -Notype -Append
    }
  }

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

    if ($DisplayIt) {
      $Results | Select-Object DisplayName,UserPrincipalName,MFAStatus,LicenseStatus,IsAdmin,AdminRoles,SignInStatus,lastSignInDateTime | Format-List
    } else{   
      $Results | Select-Object DisplayName,UserPrincipalName,MFAStatus,LicenseStatus,IsAdmin,AdminRoles,SignInStatus,lastSignInDateTime | Export-Csv -Path $ExportCSV -Notype -Append
    }

  }
}

#Open output file after execution  
Write-Host Script executed successfully - Completed (Get-Date -DisplayHint Time) ((Get-Date).Subtract($runtime).ToString('dd\.hh\:mm\:ss'))
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
    Write-Host "MFA Enabled user report available in: $ExportCSVReport"

    $Prompt = New-Object -ComObject wscript.shell
    $UserInput = $Prompt.popup("Do you want to open output file?",0,"Open Output File",4)
    if ($UserInput -eq 6)
    {
      Invoke-Item "$ExportCSVReport"
    }
    Write-Host Exported report has $PrintedUser users of $progressCnt

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

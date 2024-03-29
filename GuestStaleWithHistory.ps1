
#Requires -Modules AzureADPreview
# , Exch-Rest
#
# WIP - Purge old Guest accounts by running this perodically to get the list of accounts, keep it for future runs, then after it pasts the cutoffage, remove the acount
# also remove accountw which have not accepting their invition and are older then 30 days credit 
# to https://github.com/chadmcox/Azure_Active_Directory_Scripts/tree/master/Guests
#
#  TODO
#    Check age of State file so if there is more than 30 days between runs, then warn about that
#    Add a ClearHistory Switch to Reset state
#    Send E-mail notifications to users when we have removed them from the system
#    Send Grace period Warning messages that their account will be deleted
#    Send Grace period warning summary alerts to delegates for invited people
#    Using Group Membership we can see if the guests are a member of anything we need to flag to others.
#    Summary info for how many we put into what state
# GuestStaleWithHistory.ps1
# D-Jeffrey on github.com
#
# can use AD if module is present
#    -- if you can overcome module issues with 
#    import-Module  AzureADPreview  -Force
#
param
(
  [Parameter(Mandatory = $false)]
  [switch]$FirstRun,                    # This must be used if this is the first time
  [switch]$ForceBack,                    # assume that something was missed and run the process looking back 29 days instead of just the last time it was run
  [switch]$QuickCheck,                       # Using the state of the last run, run a quick report which does not read the Sign-In Logs, it just used the state from before.  QuickCheck Disabled the Production Run.
  [switch]$ResetConnection,             # Re-connect to services
  [boolean]$TestOnly = $true,
  [boolean]$SendMail = $false
)

#.......    Grace - Warning      (E-mail warning)
#..........................Grace (Delete account)

$Version = "2023.6.19"
$GuestGrace = 390     #days 
$GuestWarning = 14   #days 
$AcceptInvite = 30          #days    #  (Max limit of design is 30 days)
$GuestInformGroupOwner = $false      # NOT BUILT


$GuestHistoryLog = "GuestHistory." + (get-date -F yyyy-MM-dd) +".Log"

$ProductionRun = !$TestOnly


# Special words
# %TENANT%, %DISPLAYNAME%, %GRACEDATE%, %INACTIVITY%, %UPNMAIL%, %GROUPNAME%, %TODAY%

$MsgBody = "Notification of Pending Removal of Access
Attention %DISPLAYNAME%,

Your access to the %TENANT% Azure/Office 365 services will be removed due to inactivity, effective %GRACEDATE%.  You have not used our systems in at least the last %INACTIVITY% days.

If you access your services at %TENANT% before %GRACEDATE%, your account will stay active, otherwise it will be permanently removed.  These services could Teams, SharePoint, Project Management or others Microsoft Office 365 Services shared with you. `
If you no longer require access to %TENANT%, then please disregard this e-mail.

Account information
   Guest Account: %UPNMAIL%
   Associated Services: %GROUPNAMES% 

Do not reply to this message, the mailbox is unmonitored.
%TENANT% IT Services"


# --------------- end of Confug
#
#
#
#

Function GetAccessToken {
    param (
        [Parameter(Position=0, Mandatory=$false)]
        [string] $ClientId,
        [Parameter(Position=1, Mandatory=$false)]
        [string] $RedirectUri,
        [Parameter(Position=2, Mandatory=$false)] 
        [string] $Office365Username, 
        [Parameter(Position=3, Mandatory=$false)]
        [string] $Office365Password,    
        [Parameter(Position=4, Mandatory=$false)]
        [boolean] $ExchRest = $false    
      )
    # Set ADAL (Microsoft.IdentityModel.Clients.ActiveDirectory.dll) assembly path from Azure AD module location
    try {
    $AADModule = Import-Module -Name AzureAD -ErrorAction Stop -PassThru
    }
    catch {
    throw 'The AzureAD PowerShell module not installed'
    }
    $adalPath = Join-Path $AADModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
    $adalformPath = Join-Path $AADModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    [System.Reflection.Assembly]::LoadFrom($adalPath) | Out-Null
    [System.Reflection.Assembly]::LoadFrom($adalformPath) | Out-Null  
 
    if ($ExchRest) {
    # Use Exch-Rest client id of for sending mail. 
    $ClientId = "1d236c67-7e0b-42bc-88fd-d0b70a3df50a"
    $RedirectUri = "urn:ietf:wg:oauth:2.0:oob"
    }
    # If client not proivded, we are setting the id of an Azure AD app which is pre-registered by Microsoft
    if([string]::IsNullOrEmpty($ClientId) -eq $true)
    {    
    # This is a well known and pre-registered Azure AD client id of PowerShell client. 
    $ClientId = "1950a258-227b-4e31-a9cf-717495945fc2"
    $RedirectUri = "urn:ietf:wg:oauth:2.0:oob"
    }
    elseIf ([string]::IsNullOrEmpty($RedirectUri) -eq $true)
    {
      throw "The RedirectUri not provided"
    }
    $resourceURI = "https://graph.microsoft.com"
    $authority = "https://login.microsoftonline.com/common"
    $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
      
    #Acquire token without user interaction
    if (([string]::IsNullOrEmpty($Office365Username) -eq $false) -and ([string]::IsNullOrEmpty($Office365Password) -eq $false))
    {
    $SecurePassword = ConvertTo-SecureString -AsPlainText $Office365Password -Force
    #Build Azure AD credentials object
    $AADCredential = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserPasswordCredential" -ArgumentList $Office365Username,$SecurePassword
    # Get token without login prompts.
    $authResult = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContextIntegratedAuthExtensions]::AcquireTokenAsync($authContext, $resourceURI,$ClientId, $AADCredential)
    $accessToken = $authResult.Result.AccessToken
    }
    else
    {
    # Get token by prompting login window.
    $platformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList "Always"
    $authResult = $authContext.AcquireTokenAsync($resourceURI, $ClientID, $RedirectUri, $platformParameters)
    $accessToken = $authResult.Result.AccessToken
    }
 
    return $accessToken
}




function SendMyMessage {
 param (
        [Parameter(Position=0, Mandatory=$true)]
        [string] $token,
        [Parameter(Position=1, Mandatory=$true)]
        [string] $subject,
        [Parameter(Position=2, Mandatory=$true)] 
        [string] $body
        
      )


$Params = @{
  "URI"         = 'https://graph.microsoft.com/v1.0/me/sendMail'
  "Headers"     = @{
    "Authorization" = ("Bearer {0}" -F $Token)
  }
  "Method"      = "POST"
  "ContentType" = 'application/json'
  "Body" = (@{
    "message" = @{
      "subject" = 'This is a test message.'
      "body"    = @{
        "contentType" = 'Text'
        "content"     = 'This is a test email'
      }
      "toRecipients" = @(
        @{
          "emailAddress" = @{
            "address" = 'darrenjeffrey@hotmail.com'
          }
        }
      )
    }
  }) | ConvertTo-JSON -Depth 10
}

Invoke-RestMethod @Params


}



Import-Module AzureADPreview -Force

$hasAD = ((get-module -ListAvailable -name ActiveDirectory).count -gt 0)    # Used to Auto-logon

if ($QuickCheck.IsPresent) {
    $ProductionRun = $false
    }

if ($ResetConnection.IsPresent) {
        Disconnect-AzureAD  -ErrorAction SilentlyContinue
        Disconnect-ExchangeOnline -ErrorAction SilentlyContinue
        Disconnect-MicrosoftTeams -ErrorAction SilentlyContinue
        Get-PSSession | Remove-PSSession
  }

if ($hasAD) {
    $username = (get-aduser $env:username -Properties UserPrincipalName).UserPrincipalName
    }

  try {
    Get-AzureADCurrentSessionInfo -ErrorAction Stop | Out-Null
  } catch {
    if ($hasAD) {
        Connect-AzureAD -accountid $username |Out-Null
        } else {
        Connect-AzureAD |Out-Null
        }
  }


##### INCOMPLETE
# $Token = GetAccessToken -ExchRest $true
#


  
# Use the Tenant ID to avoid issues with multi-tenant testing
$Tent = (Get-AzureADTenantDetail)
$GuestStateHistoryPath = $env:OneDriveCommercial  + "\Documents\Security\GuestState"
$GuestStateHistory = $GuestStateHistoryPath + "\GuestStateHistory." + $Tent.ObjectID + ".state"

Write-Verbose ("Working on Tenant " + $Tent.DisplayName + " " + $Tent.ObjectID)
$StartingTime = (get-date) 



if ($FirstRun.IsPresent -and (test-Path -LiteralPath $GuestStateHistory)) { 
    Write-host "This Script has been run before, this is not the firstRun"
    Break
    }

$ReadyToGo = (Get-Item -LiteralPath $GuestStateHistory -ErrorAction SilentlyContinue).LastWriteTime -gt (Get-Date).AddDays(-29)
if (-not $ReadyToGo) { 
    # override that fact that this is too old
    if ($ForceBack.IsPresent) {
        if ( test-Path -LiteralPath $GuestStateHistory) {
            $ReadyToGo = $true
            }
        }
    }
# Is the file existing or current enough
if ($ReadyToGo ) {
    write-Progress "Loading State..."
    $guestStateAll = (Get-Content -Raw -LiteralPath $GuestStateHistory) | ConvertFrom-Json
    write-Progress ("Loaded: " + ($guestStateAll).Count)
    $lastRun = ((Get-Item $GuestStateHistory).LastWriteTime)
    $LastRunTxt = "Last Run " + $lastRun
} else {
    if ($FirstRun.IsPresent) { 
        $guestStateAll =  [pscustomobject]@()
        $lastRun = (Get-date).AddDays(-29)
        $LastRunTxt = "NEVER run before"
        if (-not (Test-Path -LiteralPath $GuestStateHistoryPath)) {
            New-Item -Path $GuestStateHistoryPath -ItemType directory| Out-Null
        }
    } else {
    Write-Host "`
   Warning - running without a previous Guest State History, only continue if this is the first time you have started this process`
    Or the history may be more than 30 days old, which means you may have lost records (Using -ForceBack to override)
       History file: $GuestStateHistory                                        `
                                                                                                                                  `
  If this is really the first run this use "  -ForegroundColor Red -BackgroundColor Yellow -NoNewline
     Write-Host " -FirstRun " -ForegroundColor Green -BackgroundColor DarkGreen

    break
    }
 }
    if ($ForceBack.IsPresent) { 
        
        $lastRun = (Get-date).AddDays(-29)
        $LastRunTxt = $LastRunTxt + " with Extra Look back"
        }


if ($ProductionRun) {
    Write-Host "GETTING Ready to RUN for real.... Stop now before we start to delete accounts" -ForegroundColor Yellow

    Start-Sleep 5
    Write-Host "Ready Now?" -ForegroundColor Yellow
    Start-Sleep 5
    Write-Host "...Okay here we go" -ForegroundColor Yellow
    
    }
     else {
    Write-Host "... Test mode only.  Use -TestMode `$false  for production`n" -ForegroundColor Yellow
    }
# TODO
# check date of state file to make sure it is not more than x days ago

Write-Host "# Reviewing Guests for : " $Tent.DisplayName  " using " $Version

Write-Host ("="*(35+$Tent.DisplayName.Length + $version.Length))

if ($QuickCheck.ispresent) {
    Write-host ("   Quick Check Only" )  -ForegroundColor Green
    }

Write-host $lastRunTxt -ForegroundColor darkyellow
Write-verbose ("GuestInvite = $GuestInvite  (Non accept Invite = delete) for " + (get-date).adddays(-$AcceptInvite))
Write-verbose ("GuestWarninge = $GuestWarning  (Grace-Warning = email) for " + (get-date).adddays(-$GuestGrace+$GuestWarning))
Write-verbose ("GuestGrace    = $GuestGrace = (Delete) for " + (get-date).adddays(-$GuestGrace) )


$lastRun = $lastRun.AddHours(-1)  # Set the clock back 1 hour just in case
$queryStartDateTimeFilter = '{0:yyyy-MM-dd}T{0:HH:mm:sszzz}' -f $lastRun.AddHours(-1)


$InviterTxt = ""
$warnedCnt = 0
$shouldwarnedCnt = 0


 # Check to see if they fail to run AD Audit

if (-not $QuickCheck.ispresent) { 

     $FailedAudit = $false
     try { $lastAudit = Get-AzureADAuditSignInLogs -Top 1 -ErrorAction Stop 
        } catch {
        $FailedAudit = $true
        }
    if ($FailedAudit) {
        # check again
        Start-Sleep 5
        try { $lastAudit = Get-AzureADAuditSignInLogs -Top 1 -ErrorAction Stop 
        } catch {
            Write-Host "It appears you do not have SignInLogs access - STOPPING" -ForegroundColor Red -BackgroundColor Yellow
            break 
            }
        }
    }

Write-Progress -Activity "Getting Old Expire Invite Guest" 
 #Delete guest that are pending acceptance and disabled for longer than $AcceptInvite days
  write-verbose "Getting accounts to Delete because they have not accepted their invite in $AcceptInvite days" 
$PendingAcceptGuests = Get-AzureADUser -Filter "userType eq 'Guest'" -all $true -PipelineVariable guest | `
    where {($_.userstate -eq 'PendingAcceptance') -and ([datetime](get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$AcceptInvite)))} 
   


 #   userType eq 'Member'
$guestUsers = Get-AzureADUser -Filter "userType eq 'Guest'"  -all $true
  #### -top 10
  
 

$TG = $guestUsers.count
$guestState30 = [pscustomobject]@() 



write-verbose "Getting Active Guests "
Write-Progress -Activity "Getting accounts" 

#if (-not $QuickCheck.ispresent) {   ###########################


Write-Verbose "Reading Guest's logins"
$timer = [System.Diagnostics.Stopwatch]::StartNew()

$lastLoginDates = @{}

$day = (get-date).Date
$i = 0
$days = ($day - $lastrun).days
while ($day -gt $lastrun) {
    $elapsedSecondsTop = $timer.Elapsed.TotalMilliseconds 
    # Convert the day to the required format for filtering
    $filterDate = 
    $filterDate  = '{0:yyyy-MM-dd}T{0:HH:mm:sszzz}' -f $day

    $eodfilterDate = '{0:yyyy-MM-dd}T{0:HH:mm:sszzz}' -f $day.AddDays(1).AddMilliseconds(-1)
    $Looking = $true
    $DelayIt = 1
    $theday = $day.tostring("dd/MMM/yyyy")
    if ($remainingTime -le 60) {
        $rtime = "$remainingTime seconds"
    } else {
        $rtime = ($remainingTime/60).ToString('.0') + " minutes"
        }
     = 
    
    Write-Progress ("Reading logs for $theday [$rtime]") -PercentComplete (100 * $i / $days)
    while ($Looking) {
   
        try{
            # Query the Azure AD audit sign-in logs for guest sign-ins on the specific day
            # "createdDateTime ge $filterDate and createdDateTime lt $eodfilterDate and userType eq 'Guest' "
            $guestSignIns = Get-AzureADAuditSignInLogs -Filter "createdDateTime ge $filterDate and createdDateTime lt $eodfilterDate and userType eq 'Guest'" -Top 5000
            $Looking = $False
            }
        Catch {
            #Write-Output "An error occurred:"
            # Write-Output $_
            Write-Progress ("Stalled - Reading logs for date $theday (retry $DelayIt)") -PercentComplete (100 * $i / $days)
            Write-Verbose "Stalled reading AzureADAuditSignInLogs"

            if ($DelayIt -gt 10) { 
                $Looking = $False
                Write-Host ("Problem getting AuditSignInLogs for : $theday ") -ForegroundColor DarkRed -BackgroundColor Yellow
            } else {
                # we will see if this slows the script enough that MS let's it continue
                Start-Sleep (15 * $DelayIt)
                $DelayIt = 1 + $DelayIt
                }
            }
        }
        # Loop through each guest sign-in
    $baseper = 100 * $i / $days
    $gsc = $guestSignIns.Count / $days * 100
    $k = 0
    foreach ($guestSignIn in $guestSignIns) {
        $userPrincipalName = $guestSignIn.UserPrincipalName
        Write-Progress ("Reading logs for user $userPrincipalName (retry $DelayIt)") -PercentComplete ($baseper + $k/$gsc)
        # Check if the user's last login date has already been recorded
        if ($lastLoginDates.ContainsKey($userPrincipalName)) {
                
        }
        else {
            $Looking = $true
            $DelayIt = 1
            # Retrieve the last sign-in time for the user and store it in the hashtable
            while ($Looking) {
                try{
        
                    $lastLogin = Get-AzureADAuditSignInLogs -Filter "UserPrincipalName eq '$userPrincipalName'" -Top 1 
                    $Looking = $False
                    Write-Progress ("Reading logs for user $userPrincipalName (retry $DelayIt)") -PercentComplete ($baseper + $k/$gsc)
                    }
                Catch {
                    Write-Progress ("Stalled - Reading logs for user $userPrincipalName (retry $DelayIt)") -PercentComplete ($baseper + $k/$gsc)
                    Write-Verbose "Stalled reading AzureADAuditSignInLogs"
                    if ($DelayIt -gt 10) { 
                        $Looking = $False
                        Write-Host ("Problem getting AuditSignInLogs for : $theday ") -ForegroundColor DarkRed -BackgroundColor Yellow
                    } else {
                        # we will see if this slows the script enough that MS let's it continue
                        Start-Sleep (15 * $DelayIt)
                        $DelayIt = 1 + $DelayIt
                    }
                }
            }

            $lastLoginDates[$userPrincipalName] = $lastLogin.CreatedDateTime
            Write-Verbose ("$DN was active " + $lastLogin.CreatedDateTime)
        }
        $k = $k+1
    } # foreach
    # Move to the previous day
    $day = $day.AddDays(-1)
    
    $i = $i+1
    
    $remainingTime = [Math]::Floor($timer.Elapsed.TotalMilliseconds  / ($days - $i) / $days / 1000)
}



$i = 0
$ActiveGuestsTxt = ""
$ActiveGuest = @()
$theOldGuest = [pscustomobject]@()
#For each Guest user, validate there is a login in the last week


$timer = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($guestUser in $guestUsers)
{
    $elapsedSecondsTop = $timer.Elapsed.TotalMilliseconds 
    $DN = $guestUser.DisplayName
    $userPrincipalName = $guestUser.userPrincipalName
    $ag = $ActiveGuest.count
    
    if ($guestUser.Mail -ne $Null) {
        $M = $guestUser.Mail
        } else {
        $M = $guestUser.OtherMails 
        } 
    $t = [Math]::Floor($elapsedSecondsTop/1000)
    $gc = $guestUsers.count
    Write-Progress "Reading logs for Guest: $DN  ($i of $TG) [Time: $elapsedSecondsMember s ~ $remainingTimeseconds s @ $t s ] " -PercentComplete ($i / ($guestUsers.count) * 100) -Status "Active Guests: $ag"
    Write-Verbose ("Reading: $DN (" +   $M + ")")

    # TODO Error checking for no membership
    
    if ($lastLoginDates.ContainsKey($userPrincipalName)) {
        $guestUserSignIns = $lastLoginDates[$userPrincipalName]
    } else {
        $guestUserSignIns = $null
        }
    
    if ($guestUserSignIns -eq $null) {
        $memberOf = $guestUser | Get-AzureADUserMembership
        $mDisplay = $memberOf.DisplayName
        # No longs in the last X days
        $oldMissingGuest= ($guestUser | select UserState, UserStateChangedOn) 
        #
        # Force all null to today (so we don't age them out too quickly)  very useful during FirstRun
        #
    
        if ($guestStateAll -ne $null -and ! $guestStateAll.ObjectID.Contains($guestUser.ObjectID)) {
           if ($null -ne $oldMissingGuest.Warned) {
                  $Warned = $oldMissingGuest.Warned
           } else { 
                  $Warned = $false
           }
           if (($oldMissingGuest.UserStateChangedOn) -eq $null) {
               $oldMissingGuest.UserStateChangedOn = $queryStartDateTimeFilter
               $oldMissingGuest.UserState = $oldMissingGuest.UserState + "/ForcedChangedOn"
               $Warned = $false
               }
           $oldMissingGuest.UserState = $oldMissingGuest.UserState + "/ForcedLastAccess"
           
                
           $theOldGuest += [pscustomobject]@{
                ObjectID = $guestUser.ObjectID;
                userprincipalname = $guestUser.userprincipalname;
                Mail = $M;
                CreationType = $guestUser.CreationType;
                UserState = $oldMissingGuest.UserState;
                UserStateChangedOn = $oldMissingGuest.UserStateChangedOn;
                LastAccess = $queryStartDateTimeFilter;
                Warned = $Warned;
                DeletedOn = $null;
                MemberOf = $mDisplay;
                
                }
        
       
          }
      } else {
          
          Write-Verbose ("$DN was active " + $guestUserSignIns)
          
          $ActiveGuestsTxt = $ActiveGuestsTxt + "`n$DN ($M) was active " + [DateTime]$guestUserSignIns
          $ActiveGuest += $guestUser
            
          $theOldGuest += [pscustomobject]@{ 
            ObjectID = $guestUser.ObjectID;
            userprincipalname = $guestUser.userprincipalname;
            Mail = $M;
            CreationType = $guestUser.CreationType;
            UserState = $guestUser.UserState;
            UserStateChangedOn = $guestUser.UserStateChangedOn;
            LastAccess = $guestUserSignIns;
            Warned = $false;         # If they are active then reset the Warned flag
            DeletedOn = $null;
            MemberOf = $mDisplay;
            
          }
      }
    
    

     
     $i = $i+1

     $remainingTimeseconds = [Math]::Floor($timer.Elapsed.TotalMilliseconds / $i * $TG / 1000)
}

$timer.Stop()



$ActionTime = ((get-date) -f "{D}")
# Read thru the events to see who did the operations to create the new guests.
# TODO this will most likely need some error checking and retry
 
 
$addedUserEvents = Get-AzureADAuditDirectoryLogs -Filter "ActivityDisplayName eq 'Add user' and ActivityDateTime ge $queryStartDateTimeFilter"

#Processing added users
foreach ($addedUserEvent in $addedUserEvents) 
{
    Write-Verbose "Processing added user event"

    if ($inviterId = $addedUserEvent.InitiatedBy.User -ne $null) {

        #Get the inviter reference from the InitiatedBy field
        $inviterId = $addedUserEvent.InitiatedBy.User.Id
        $inviteUser = get-AzureADUser -ObjectID  $inviterId
        $inviteDisplay = $inviteUser.DisplayName
  
    } else {
        if ($addedUserEvent.InitiatedBy.App -ne $null) {
            $inviterId = $addedUserEvent.InitiatedBy.App.ServicePrincipalId
            $inviteDisplay = "App:" + $addedUserEvent.InitiatedBy.App.DisplayName
            }
        else {
            $inviteUser = $null
            $inviteDisplay = "-None-"
            }
    }
     
    #For each TargetResources, check to see if it's a guest user, and if so, add its Manager
    foreach ($targetResource in $addedUserEvent.TargetResources)
    {
        Write-Verbose "Processing target resource"
        $addedUser = $null
        $addedUser = Get-AzureADUser -ObjectID $targetResource.Id -ErrorAction SilentlyContinue
        
        if ($targetResource.GroupType -eq "User") {
        
            if ($addedUser.UserType -eq "Guest") {
                $memberOf = $addedUser | Get-AzureADUserMembership
                $mDisplay = $memberOf.DisplayName
                Write-Output ("Guest " + $addedUser.DisplayName + " invited by " + $inviteDisplay)
                $InviterTxt += "Guest: " + $addedUser.DisplayName + " ("+ $addedUser.Mail + ")  invited by " + $inviteDisplay + " On " + $addedUserEvent.ActivityDateTime + ".  Member:" + $memberOf.DisplayName + "`n"
                }
        } else {
            # This is most likely a 
            Write-Verbose ("Other Resource added: " + $addedUser.DisplayName + " " + $targetResource.Id)
        }
    }
}

# } ###################################################

    
write-verbose ("Processing Active Guests : " + $ActiveGuest.count)   
# $theOldGuest | ConvertTo-Json -Depth 1 | Set-Content -LiteralPath ".\Guest30.txt"


#
# Force all null to today (so we don't age them out too quickly)  very useful during FirstRun
#


# Sorting on UserState will keep ForceAge with the older (no-null) date
$GuestAll = ($theOldGuest + $guestStateAll) | Sort-Object  -Property ObjectID, LastAccess  | Sort-Object -Unique -Property ObjectID

$GuestAll| Add-Member -MemberType NoteProperty -Name DeletedOn -Value $null -ErrorAction SilentlyContinue
$GuestAll| Add-Member -MemberType NoteProperty -Name Warned -Value $null -ErrorAction SilentlyContinue


write-verbose "Guests who did not accept the invitation - which should be removed"
$theOldGuest = $GuestAll | where { (get-date $($_.LastAccess)) -lt $((get-date).adddays(-$GuestGrace)) -and $(get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$GuestGrace))} 

$PendingAcceptGuests | Format-table -Property ObjectId, UserPrincipalName, mail, UserState, UserStateChangedOn

    
# Just cancel any Invites which have not been 
Write-Progress -Activity "Removing unaccepted Guests older than $AcceptInvite days" 
if ($ProductionRun) {
    $PendingAcceptGuests | Remove-AzureADUser
    
}

        
Write-Progress -Activity "Removing aged inactive accounts grace expired" 
        
$theOldGuest  | where { (get-date $($_.LastAccess)) -lt $((get-date).adddays(-$GuestGrace)) -and (get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$GuestGrace))} | `
    ForEach-Object {
        $this = $_

        if ( $_.DeletedOn -eq $Null) { 
            
            # TODO This assumes the last Delete took effect
            # Need to add notifcaiton e-mail and the resposible person
            if ($QuickCheck.IsPresent) {
                $isOkay = $true
                } else 
            {
            try {
                $g = get-AzureADUser -ObjectID $_.ObjectID
                $isOkay = $true
                }
            catch {
                $g = $null 
                Write-Verbose ("-+ Account Removed " + $_.ObjectID + " (" + $_.userprincipalname + ")")
                $this.DeletedOn = $ActionTime
                $isOkay = $false
                }
            }
            if ($isOkay) {
                if ($g -eq $null) {
                    $memberOf = ($g | Get-AzureADUserMembership -ErrorAction SilentlyContinue)
                } else {
                    $memberof = @()
                    }
                Write-Output ("--" + $_.Mail + ", last access as " + $_.LastAccess + ", StateChange " + $_.UserStateChangedOn + ".  Member:" + ($memberOf.DisplayName -join ",") )
                if ($ProductionRun) {
                    try { 
                        Remove-AzureADUser -ObjectID $_.ObjectID
                        $this.DeletedOn = $ActionTime
                        Write-Output ("|REMOVED account " + $_.ObjectID + " (" + $_.userprincipalname + ")")
                        }
                    Catch {
                        Write-Output ("|SHOULD REMOVE account " + $this.ObjectID + " (" + $this.userprincipalname + ")")
                        }
                    }
                    else {
                        Write-Output (" |SHOULD REMOVE account " + $_.ObjectID + " (" + $_.userprincipalname + ")")
                    }
                    
            }
            
            # TODO
            # We should get rid of the record in $GuestAll
            # BUG BUG BUG without deletng those records, if the same account is added back in, then it would have a Deleted and WARN Record which needs to be cleared


            }
    }
            
Write-Progress -Activity "Send a warning message for inactive accounts before grace runs out" 
$theOldGuest  | where { (get-date $($_.LastAccess)) -lt $((get-date).adddays(-$GuestGrace+$GuestWarning)) -and (get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$GuestGrace+$GuestWarning)) -and $($_.DeletedOn) -eq $null } | `
ForEach-Object {
    $this = $_
     Write-Verbose ("User Warn: " + $_.Mail + ", last access as " + $_.LastAccess)
     $shouldwarnedCnt++
     if (( $_.Warned -eq $null) -and ($_.Deleted -eq $null)) {
         if ((get-date $($_.LastAccess)) -ge $((get-date).adddays(-$GuestGrace))) {
            Write-Verbose ("User SHOULD have been deleted: " + $_.Mail + ", last access as " + $_.LastAccess)
         } else {
            # TODO 
            # Need to add notifcaiton e-mail and the resposible person
                    
               $mof = $null
               if ($QuickCheck.IsPresent) {
                    $mof =  $this.MemberOf
                    }
               else {
                    $mof =  (Get-AzureADUserMembership -ObjectId $this.ObjectId).DisplayName -join ", "
                    }       
            Write-Output ("++Send warning e-mail to " + $_.Mail + ", last access as " + $_.LastAccess + ", StateChange on " + $_.UserStateChangedOn + ") about to expire.  Member:" + $mof)
            $emailBody = $MsgBody
            if ($QuickCheck.IsPresent) {
                $isOkay = $true
                } else 
            {
            try { 
                $go = (get-azureADUser -objectid $this.objectid)
                $isOkay = $true
                }
            catch { 
                Write-Verbose ("-+ Account Removed " + $this.ObjectID + " (" + $this.userprincipalname + ")")
                $this.DeletedOn = $ActionTime
                $isOkay = $false
                }
            }
            if ($isOkay) {
                $mof = $null
                if ($QuickCheck.IsPresent) {
                    $mof =  $this.MemberOf
                    }
                else {
                    $mof =  (Get-AzureADUserMembership -ObjectId $go.ObjectId).DisplayName -join ", "
                    }
                if ($mof -eq $null -or $mof -eq "") { $mof = "<none>" }
                    Write-Verbose ("Member of : " + $mof + " for " + $go.ObjectId)  

                $replacetable = @{}
                $replacetable.'%TODAY%' = (get-date -F "D")
                $replacetable.'%DISPLAYNAME%' = $go.DisplayName
                $replacetable.'%TENANT%' = $Tent.DisplayName
                $replacetable.'%GRACEDATE%'=  Get-Date -Date (([datetime]$_.LastAccess).adddays($GuestGrace))  -f "D"
                $replacetable.'%INACTIVITY%'= "" + (((get-date) - [datetime]$_.LastAccess).Days)
                $replacetable.'%UPNMAIL%'= $_.Mail
                $replacetable.'%GROUPNAMES%'= $mof
                Foreach ($key in $replacetable.Keys) {
                    $emailBody = $emailBody.Replace($key, $replacetable.$key)
                    }

                Write-Verbose ("Email Body `n" + $emailBody) 

                # TODO WARN E-MAIL logic goes here
                $warnedCnt++
                if ($ProductionRun) {
                    if ($SendMail) { 
                        
                    $_.Warned =  $ActionTime
                    Write-Output (" |WARNED account " + $_.ObjectID + " (" + $_.userprincipalname + ")")
                 } else {
                    Write-Output (" |Should WARN account " + $_.ObjectID + " (" + $_.userprincipalname + ")")
                    }
                 }
  }  
            }
        }
    }
    

   
if (-not $QuickCheck.IsPresent) {
    if ($GuestAll.count -eq 0) {
        Write-Host "`nAwareness - you have no guest, therefor a state file was not created`n" -ForegroundColor Yellow

    } else {
        write-host ("Saving State for Next Run " + $GuestStateHistory) -ForegroundColor Green

        #  -Compress 
        if (Test-Path -LiteralPath $GuestStateHistory) {
            copy-item $GuestStateHistory $GuestStateHistory+".sav" -Force
            }
        $GuestAll | ConvertTo-Json -Depth 2 | Set-Content -LiteralPath $GuestStateHistory

        #set the time back to when we started this.
        $setFile = Get-item -Path $GuestStateHistory
        $setFile.CreationTime = $setFile.LastWriteTime = $setFile.LastAccessTime= $StartingTime
        }
    }


$oldCnt = $theOldGuest.count
$warnCnt = ($GuestAll | where { $_.Warned -eq $true -and $_.DeletedOn -eq $null } ).ObjectID.count
$delCnt = ($GuestAll | where { $_.DeletedOn -ne $null } ).ObjectID.count
$act30 = ($GuestAll  | where { (get-date $($_.LastAccess)) -gt $((get-date).adddays(-28))})    # 4 weeks rolling window
$act7 = ($GuestAll  | where { (get-date $($_.LastAccess)) -gt $((get-date).adddays(-7))})    # 4 weeks rolling window

Write-Host "`nSummary`n--------------------------------------- `nVersion: $Version, Grace: $GuestGrace, Warning: $GuestWarning, Invite: $AcceptInvite" -ForegroundColor Yellow

$results =  (  "Guests active since last run     : " + $ActiveGuest.count)
$results += ("`nGuests active in last  7 days    : " + $Act7.ObjectID.count)
$results += ("`nGuests active in last 28 days    : " + $Act30.ObjectID.count)
$results += ("`nPending older than $AcceptInvite days       : " + $PendingAcceptGuests.count)
$results += ("`nGuest who are older than "  + $GuestGrace +" days : " + $oldCnt)
$results += ("`nGuest who are warned             : " + $warnCnt)
$results += ("`nGuest who are should be warned   : " + ($shouldwarnedCnt))
$results += ("`nGuest historically deleted       : " + $delCnt)
$results += ("`nTotal Guests                     : " + $guestUsers.count)

Write-Output $results
$TN = $Tent.DisplayName
if (!(Test-Path -Path $GuestHistoryLog)) {
    "Report for $TN `n" | Out-File -file $GuestHistoryLog 
    }

"`n######## GuestHistory Run: " + (get-date) + " ########" | Out-File -file $GuestHistoryLog -Append
"Last Run: " + $lastRun + " `n" + $results +"`n###`n" | Out-File -file $GuestHistoryLog -Append
$PendingAcceptGuests | Sort-Object -Property UserStateChangedOn   | Format-Table -Property Mail,CreationType,UserState,UserStateChangedOn  |  Out-File -file $GuestHistoryLog -Append
("Guest who are older than $GuestPurge days: " + $theOldGuest.count) |  Out-File -file $GuestHistoryLog -Append
$theOldGuest | Sort-Object -Property UserStateChangedOn   | Format-Table -Property Mail,CreationType,UserState,UserStateChangedOn,LastAccess,Warned,DeletedOn   |  Out-File -file $GuestHistoryLog -Append

"`nActive Guests are:`n" + $ActiveGuestsTxt  |  Out-File -file $GuestHistoryLog -Append

$a = $Act30 | where { (get-date $($_.LastAccess)) -gt $((get-date).adddays(-7))} | Select Mail, LastAccess
"`nActive Guests 0 to 7:`n" |  Out-File -file $GuestHistoryLog -Append
 $a |  Out-File -file $GuestHistoryLog -Append
$a = $Act30 | where { (get-date $($_.LastAccess)) -le $((get-date).adddays(-7))} | Select Mail, LastAccess
"`nActive Guests 7 to 30:`n" |  Out-File -file $GuestHistoryLog -Append
$a |  Out-File -file $GuestHistoryLog -Append
if ($InviterTxt -ne "") { 
    "`nInvited Guests:`n" + $InviterTxt   |  Out-File -file $GuestHistoryLog -Append
    }

$a = ""
$groupsCnt = @{}

for ($i = 0; $i -lt $guestStateAll.Length; $i++) {
    if ($guestStateAll[$i].Memberof -ne $null) {
        if ($guestStateAll[$i].Memberof.getType().BaseType.Name -eq "Array") { 
            For ($m=0; $m -lt $guestStateAll[$i].MemberOf.count; $m++) { 
                $groupsCnt[$guestStateAll[$i].MemberOf[$m]]++; 
                }
         } else {
            $groupsCnt[$guestStateAll[$i].MemberOf]++; 
         }
        
        }
    }
foreach ($g in  $groupsCnt.Keys) {
    $a += ( " $($groupsCnt.Item($g)) : $g`n") 
    }    

"`Summary of Guests in Groups :`n$a" |  Out-File -file $GuestHistoryLog -Append

"`n######## End ########" | Out-File -file $GuestHistoryLog -Append

write-host "[End] Results in $GuestHistoryLog" -ForegroundColor Green

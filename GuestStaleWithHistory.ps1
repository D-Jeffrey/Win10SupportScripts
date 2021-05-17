#Requires -Modules AzureADPreview, Exch-Rest
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
#
param
(
  [Parameter(Mandatory = $false)]
  [switch]$FirstRun,                    # This must be used if this is the first time
  [switch]$ForceBack,                    # assume that something was missed and run the process looking back 29 days instead of just the last time it was run
  [switch]$ResetConnection,             # Re-connect to services
  [boolean]$TestOnly = $true
)

#.......    Grace - Warning      (E-mail warning)
#..........................Grace (Delete account)

$Version = "2021.5.9"
$GuestGrace = 90     #days 
$GuestWarning = 14   #days 
$AcceptInvite = 30          #days     
$GuestInformGroupOwner = $false      # NOT BUILT


$GuestHistoryLog = "GuestHistory." + (get-date -F yyyy-MM-dd) +".Log"

$ProductionRun = !$TestOnly


# Special words
# %TENANT%, %DISPLAYNAME%, %GRACEDATE%, %INACTIVITY%, %UPNMAIL%, %GROUPNAME%, %TODAY%

$MsgBody = "<!DOCTYPE html>
<html>
<head>
<meta charset='utf-8'>
<title>Notification of Pending Removal of Access</title>
</head>
<body>
Attention %DISPLAYNAME%,

Your access to the %TENANT% Azure/Office 365 services will be removed due to inactivity, effective %GRACEDATE%.  You have not used our systems in the last %INACTIVITY% days.

If you access your services at %TENANT% before %GRACEDATE%, your account will stay active, otherwise it will be permanently removed.

Account information
   Guest Account: %UPNMAIL%
   Associated Services: %GROUPNAMES% 
</body>
</html>
"


# --------------- end of Confug
#
#
#
#

$hasAD = ((get-module -ListAvailable -name ActiveDirectory).count -gt 0)    # Used to Auto-logon


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



  
# Use the Tenant ID to avoid issues with multi-tenant testing
$Tent = (Get-AzureADTenantDetail)
$GuestStateHistory = $env:TEMP  + "\GuestStateHistory." + $Tent.ObjectID + ".state"

Write-Verbose ("Working on Tenant " + $Tent.DisplayName + " " + $Tent.ObjectID)
$StartingTime = (get-date) 



if ($FirstRun.IsPresent -and (test-Path -LiteralPath $GuestStateHistory)) { 
    Write-host "This Script has been run before, this is not the firstRun"
    Break
    }
# Is the file existing or current enough
if ((Get-Item -LiteralPath $GuestStateHistory -ErrorAction SilentlyContinue).LastWriteTime -gt (Get-Date).AddDays(-29)) {
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
    } else {
    Write-Host "`
   Warning - running without a previous Guest State History, only continue if this is the first time you have started this process`
    Or the history may be more than 30 days old, which means you may have lost records                                            `
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
Write-Host "============================================"


Write-host $lastRunTxt
Write-verbose ("GuestInvite = $GuestInvite  (Non accept Invite = delete) for " + (get-date).adddays(-$AcceptInvite))
Write-verbose ("GuestWarninge = $GuestWarning  (Grace-Warning = email) for " + (get-date).adddays(-$GuestGrace+$GuestWarning))
Write-verbose ("GuestGrace    = $GuestGrace = (Delete) for " + (get-date).adddays(-$GuestGrace) )


$lastRun = $lastRun.AddHours(-1)  # Set the clock back 1 hour just in case
$queryStartDateTimeFilter = '{0:yyyy-MM-dd}T{0:HH:mm:sszzz}' -f $lastRun.AddHours(-1)

 # Check to see if they fail to run AD Audit

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

Write-Progress -Activity "Getting Old Expire Invite Guest" 
 #Delete guest that are pending acceptance and disabled for longer than $AcceptInvite days
  write-verbose "Getting accounts to Delete because they have not accepted their invite in $AcceptInvite days" 
  $PendingAcceptGuests = Get-AzureADUser -Filter "userType eq 'Guest'" -all $true -PipelineVariable guest | `
  where {($_.userstate -eq 'PendingAcceptance') -and ((get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$AcceptInvite))) -and $_.accountenabled -eq $false} 
   



  $guestUsers = Get-AzureADUser -Filter "userType eq 'Guest'"  -all $true
  #### -top 10
  
 

$TG = $guestUsers.count
write-verbose "Getting Active Guests "
Write-Progress -Activity "Getting accounts" 




$guestState30 = [pscustomobject]@() 

Write-Verbose "Reading Guest's logins"

$ActiveGuestsTxt = ""
    
$i = 0
$ActiveGuest = @()
$theOldGuest = [pscustomobject]@()
#For each Guest user, validate there is a login in the last week
foreach ($guestUser in $guestUsers)
{
    $DN = $guestUser.DisplayName
    $ag = $ActiveGuest.count
    Write-Progress "Reading logs for Guest: $DN  ($i of $TG)" -PercentComplete ($i / $guestUsers.count*100) -Status "Active Guests: $ag"
    Write-Verbose ("Reading: $DN (" +   $guestUser.Mail + ")")
    # This can trigger errors "Message: This request is throttled."
    # TODO need to better detect and fix
    # get the Guest users most recent signins

    $Looking = $true
    $DelayIt = 1
    while ($Looking) {
        try {
                   # ....... this is the MONEY QUERY ..............

            $guestUserSignIns = Get-AzureADAuditSignInLogs -Top 1 -Filter "createdDateTime ge $queryStartDateTimeFilter and UserID eq '$($guestUser.ObjectID)'" -ErrorAction SilentlyContinue
            $Looking = $false
            }
        Catch {
            Write-Progress ("Stalled - Reading logs for Guest $DN (" + $DelayIt + ")") -PercentComplete ($i / $guestUsers.count*100)
            Write-Verbose "Stalled reading AzureADAuditSignInLogs"

            if ($DelayIt -gt 10) { 
                $Looking = $False
                Write-Host ("Problem getting AuditSignInLogs for : " + $guestUsers.DisplayName + "(" +$guestUsers.Mail +")") -ForegroundColor DarkRed -BackgroundColor Yellow
            } else {
    
                # we will see if this slows the script enough that MS let's it continue
                Start-Sleep (40 * $DelayIt)
                $DelayIt += 1
            }
        }
    }
    $memberOf = $guestUser | Get-AzureADUserMembership
    $mDisplay = $memberOf.DisplayName 
    if ($guestUserSignIns -eq $null) {
        # No longs in the last X days
        $oldMissingGuest= ($guestUser | select UserState, UserStateChangedOn) 
        #
        # Force all null to today (so we don't age them out too quickly)  very useful during FirstRun
        #

          
        if ($guestStateAll -ne $null -and ! $guestStateAll.ObjectID.Contains($guestUser.ObjectID)) {
           if (($oldMissingGuest.UserStateChangedOn) -eq $null) {
               $oldMissingGuest.UserStateChangedOn = $queryStartDateTimeFilter
               $oldMissingGuest.UserState = $oldMissingGuest.UserState + "/ForcedChangedOn"
               $oldMissingGuest.Warned = $false
               $oldMissingGuest.MemberOf = $mDisplay;
               }
           $oldMissingGuest.UserState = $oldMissingGuest.UserState + "/ForcedLastAccess"
           $theOldGuest += [pscustomobject]@{
                ObjectID = $guestUser.ObjectID;
                userprincipalname = $guestUser.userprincipalname;
                Mail = $guestUser.Mail;
                CreationType = $guestUser.CreationType;
                UserState = $oldMissingGuest.UserState;
                UserStateChangedOn = $oldMissingGuest.UserStateChangedOn;
                LastAccess = $queryStartDateTimeFilter;
                Warned = $oldMissingGuest.Warned;
                DeletedOn = $null;
                MemberOf = $mDisplay;
                }

       
          }
      } else {
          
          Write-Verbose ("$DN was active " + $guestUserSignIns.CreatedDateTime)
          $MN = $guestUser.Mail
          $ActiveGuestsTxt = $ActiveGuestsTxt + "`n$DN ($MN) was active " + [DateTime]$guestUserSignIns.CreatedDateTime
          $ActiveGuest += $guestUser
            
          $theOldGuest += [pscustomobject]@{ 
            ObjectID = $guestUser.ObjectID;
            userprincipalname = $guestUser.userprincipalname;
            Mail = $guestUser.Mail;
            CreationType = $guestUser.CreationType;
            UserState = $guestUser.UserState;
            UserStateChangedOn = $guestUser.UserStateChangedOn;
            LastAccess = $guestUserSignIns.CreatedDateTime;
            Warned = $false;         # If they are active then reset the Warned flag
            DeletedOn = $null;
            MemberOf = $mDisplay;
             
          }
      
     }
     $i = $i+1



}
 
# Read thru the events to see who did the operations to create the new guests.
# TODO this will most likely need some error checking and retry
$InviterTxt = "" 
 
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
        
            if ($addedUser.UserType -eq "Guest")
            {
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

    
write-verbose ("Processing Active Guests : " + $ActiveGuest.count)   
# $theOldGuest | ConvertTo-Json -Depth 1 | Set-Content -LiteralPath ".\Guest30.txt"


#
# Force all null to today (so we don't age them out too quickly)  very useful during FirstRun
#


# Sorting on UserState will keep ForceAge with the older (no-null) date
$GuestAll = ($theOldGuest + $guestStateAll) | Sort-Object  -Property ObjectID, LastAccess  | Sort-Object -Unique -Property ObjectID

$GuestAll| Add-Member -MemberType NoteProperty -Name DeletedOn -Value $null -ErrorAction SilentlyContinue
$GuestAll| Add-Member -MemberType NoteProperty -Name Warned -Value $null -ErrorAction SilentlyContinue


write-verbose "Old Guests - which should be removed"
$theOldGuest = $GuestAll | where { (get-date $($_.LastAccess)) -lt $((get-date).adddays(-$GuestGrace)) -and $(get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$GuestGrace))} 


    
# Just cancel any Invites which have not been 
Write-Progress -Activity "Removing unaccepted Guests older than $AcceptInvite days" 
if ($ProductionRun) {
    $PendingAcceptGuests | Remove-AzureADUser
    }

        
Write-Progress -Activity "Removing aged inactive accounts grace expired" 
        
$theOldGuest  | where { (get-date $($_.LastAccess)) -lt $((get-date).adddays(-$GuestGrace)) -and (get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$GuestGrace))} | `
    ForEach-Object {

        if ( $_.DeletedOn -eq $Null) { 
            # TODO This assumes the last Delete took effect
            # Need to add notifcaiton e-mail and the resposible person
            $memberOf = get-AzureADUser -ObjectID $_.ObjectID | Get-AzureADUserMembership
            Write-Output ("Email  to " + $_.Mail + ", last access as " + $_.LastAccess + ", StateChange " + $_.UserStateChangedOn + ".  Member:" + $memberOf.DisplayName)
            if ($ProductionRun) {
                Remove-AzureADUser -ObjectID $_.ObjectID
                }
                    
            $_.DeletedOn = ((get-date) -f "{D}")
            Write-Output ("|REMOVED account " + $_.ObjectID + " (" + $_.userprincipalname + ")")
            # TODO
            # We should get rid of the record in $GuestAll

            }
    }
            
Write-Progress -Activity "Send a warning message for inactive accounts before grace runs out" 
$theOldGuest  | where { (get-date $($_.LastAccess)) -lt $((get-date).adddays(-$GuestGrace+$GuestWarning)) -and (get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$GuestGrace+$GuestWarning)) -and $($_DeletedOn) -eq $null } | `
    ForEach-Object {
        Write-Verbose "User Warn: " $_.Mail + ", last access as " + $_.LastAccess 
        if (( $_.Warned -eq $null) -and ($_.Deleted -eq $null)) { 
            # TODO 
            # Need to add notifcaiton e-mail and the resposible person
                    
                   
            Write-Output ("Send warning e-mail to " + $_.Mail + ", last access as " + $_.LastAccess + ", StateChange on " + $_.UserStateChangedOn + ") disabling account.  Member:" + ($memberOf.DisplayName -join ", "))
            $emailBody = $MsgBody
            $go = (get-azureADUser -objectid $_.objectid)
            $mof = $null
            $mof =  (Get-AzureADUserMembership -ObjectId $go.ObjectId).DisplayName -join ", "
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



            if ($ProductionRun) {
                Set-AzureADUser -ObjectID $_.ObjectID -AccountEnabled $false
                        
                Get-AzureADUser -ObjectID $_.ObjectID | FT -HideTableHeaders DisplayName, Mail, userprincipalname, AccountEnabled
                }
            $_.Warned =  (get-date) -f "{D}"
            Write-Output ("|WARNED account " + $_.ObjectID + " (" + $_.userprincipalname + ")")
    
            }
    }
    

   

write-host ("Saving State for Next Run " + $GuestStateHistory) -ForegroundColor Green

#  -Compress 
if (Test-Path -LiteralPath $GuestStateHistory) {
    copy-item $GuestStateHistory $GuestStateHistory+".sav" -Force
    }
 $GuestAll | ConvertTo-Json -Depth 2 | Set-Content -LiteralPath $GuestStateHistory

#set the time back to when we started this.

$setFile = Get-item -Path $GuestStateHistory
$setFile.CreationTime = $setFile.LastWriteTime = $setFile.LastAccessTime= $StartingTime


$oldCnt = $theOldGuest.count
$warnCnt = ($GuestAll | where { $_.Warned -eq $true -and $_.DeletedOn -eq $null } ).ObjectID.count
$delCnt = ($GuestAll | where { $_.DeletedOn -ne $null } ).ObjectID.count
$act30 = ($GuestAll  | where { (get-date $($_.LastAccess)) -gt $((get-date).adddays(-28))}).ObjectID.count    # 4 weeks rolling window

Write-Host "`nSummary`n---------------------------------------" -ForegroundColor Yellow

$results =  (  "Guests active since last run     : " + $ActiveGuest.count)
$results += ("`nGuests active in last 28 days    : " + $Act30)
$results += ("`nPending older than $AcceptInvite days       : " + $PendingAcceptGuests.count)
$results += ("`nGuest who are older than "  + $GuestGrace +" days : " + $oldCnt)
$results += ("`nGuest who are warned             : " + $warnCnt)
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
if ($InviterTxt -ne "") { 
    "`nInvited Guests:`n" + $InviterTxt   |  Out-File -file $GuestHistoryLog -Append
    }

"`n######## End ########" | Out-File -file $GuestHistoryLog -Append

write-host "[End] Results in $GuestHistoryLog" -ForegroundColor Green

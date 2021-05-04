#Requires -Modules AzureADPreview
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
  [boolean]$TestOnly = $true
)

$Version = "2021.5.7"
$GuestHistoryPurge = 90    #days 
$GuestHistoryGrace = 30    #days 
$AcceptInvite = 30         #days     
$GuestHistoryLog = "GuestHistory.Log"
$hasAD = ((get-module -ListAvailable -name ActiveDirectory).count -gt 0)


$ProductionRun = !$TestOnly


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
Write-verbose "GuestHistoryPurge = $GuestHistoryPurge"
Write-verbose "GuestHistoryGrace = $GuestHistoryGrace"


$lastRun = $lastRun.AddHours(-1)
$queryStartDateTimeFilter = '{0:yyyy-MM-dd}T{0:HH:mm:sszzz}' -f $lastRun.AddHours(-1)

 # Check to see if they fail to run AD Audit

 try { $lastAudit = Get-AzureADAuditSignInLogs -Top 1 -ErrorAction Stop 
    } catch {
    Write-Host "It appears you do not have SignInLogs access - STOPPING" -ForegroundColor Red -BackgroundColor Yellow
    break 
    }


Write-Progress -Activity "Getting Old Expire Invite Guest" 
 #Delete guest that are pending acceptance and disabled for longer than $AcceptInvite days
  write-verbose "Getting accounts to Delete because they have not accepted their invite in $AcceptInvite days" 
  $PendingAcceptGuests = Get-AzureADUser -Filter "userType eq 'Guest'" -all $true -PipelineVariable guest | `
  where {($_.userstate -eq 'PendingAcceptance') -and ((get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$AcceptInvite))) -and $_.accountenabled -eq $false} 
   




$MsgBody = "<!DOCTYPE html>
<html>
<head>
<meta charset='utf-8'>
<title>Notification of Access Removal</title>
</head>
<body>
%LOGO%

Your access to the %TENANT% has been removed due to inactivity, effective %TODAY%.  You have not used our systems in the last %INACTIVITY% days.

If you should need access again, you will have 30 days to have your access re-activated, after which time, your account will be fully removed from our systems.


Account information
   Guest Account : %UPN%
   Associated Services: %GROUPS%


This is a mandatory service communication. 

%COMPANYADDRESS% 

                </body>
</html>
"

  $guestUsers = Get-AzureADUser -Filter "userType eq 'Guest'" -all $true

$TG = $guestUsers.count
write-verbose "Getting Active Guests "
Write-Progress -Activity "Getting accounts" 


# ....... this is the MONEY QUERY 


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
            $inviteDisplay = $addedUserEvent.InitiatedBy.App.DisplayName
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
        $addedUser = Get-AzureADUser -ObjectID $targetResource.Id
        
        if ($addedUser.UserType -eq "Guest")
        {
             $memberOf = $addedUser | Get-AzureADUserMembership
             $mDisplay = $memberOf.DisplayName
             Write-Output ("Guest " + $addedUser.DisplayName + " invited by " + $inviteDisplay)
             $InviterTxt += "Guest: " + $addedUser.DisplayName + " ("+ $addedUser.Mail + ")  invited by " + $inviteDisplay + " On " + $addedUserEvent.ActivityDateTime + ".  Member:" + $memberOf.DisplayName + "`n"
            
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


write-verbose "Old Guests - which should be removed"
$theOldGuest = $GuestAll | where { (get-date $($_.LastAccess)) -lt $((get-date).adddays(-$GuestHistoryPurge-$GuestHistoryGrace)) -and $(get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$GuestHistoryPurge-$GuestHistoryGrace))} 


    
        # Just cancel any Invites which have not been 
        Write-Progress -Activity "Removing unaccepted Guests older than $AcceptInvite days" 
       if ($ProductionRun) {
            $PendingAcceptGuests | Remove-AzureADUser
            }

        
        Write-Progress -Activity "Removing aged inactive accounts grace expired" 
        
        $theOldGuest  | where { (get-date $($_.LastAccess)) -lt $((get-date).adddays(-$GuestHistoryPurge)) -and (get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$GuestHistoryPurge))} | `
            ForEach-Object {

                if (! $_.Warned ) { 
                    # TODO 
                    # Need to add notifcaiton e-mail and the resposible person
                    $memberOf = get-AzureADUser -ObjectID $_.ObjectID | Get-AzureADUserMembership
                    Write-Output ("notepad  to " + $_.Mail + ", last access as " + $_.LastAccess + ", StateChange " + $_.UserStateChangedOn + ".  Member:" + $memberOf.DisplayName)
                    if ($ProductionRun) {
                        Remove-AzureADUser -ObjectID $_.ObjectID
                        $_ | Add-Member -MemberType NoteProperty -Name DeletedOn -Value ((get-date) -f "{D}")
                       

                        }
                    Write-Output ("|Removed account " + $_.ObjectID + " (" + $_.userprincipalname + ")")
                    # TODO
                    # We should get rid of the record in $GuestAll

                    }
            }
            
        Write-Progress -Activity "Disable aged inactive accounts with grace" 
        $theOldGuest  | where { (get-date $($_.LastAccess)) -lt $((get-date).adddays(-$GuestHistoryPurge)) -and (get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$GuestHistoryPurge)) -and $($_DeletedOn) -eq $null } | `
            ForEach-Object {
                if (! $_.Warned) { 
                    # TODO 
                    # Need to add notifcaiton e-mail and the resposible person
                    
                    $memberOf = get-AzureADUser -ObjectID $_.ObjectID  | Get-AzureADUserMembership
                    
                    Write-Output ("Send warning e-mail to " + $_.Mail + ", last access as " + $_.LastAccess + ", StateChange on " + $_.UserStateChangedOn + ") disabling account.  Member:" + $memberOf.DisplayName)
                    if ($ProductionRun) {
                        Set-AzureADUser -ObjectID $_.ObjectID -AccountEnabled $false
                        $_.Warned = $true
                        Get-AzureADUser -ObjectID $_.ObjectID | FT -HideTableHeaders DisplayName, Mail, userprincipalname, AccountEnabled
                        }
                    
                    Write-Output ("|Disable account " + $_.ObjectID + " (" + $_.userprincipalname + ")")
    
                    }
            }
    

      

write-host ("Saving State for Next Run " + $GuestStateHistory) -ForegroundColor Green

#  -Compress 

 $GuestAll | ConvertTo-Json -Depth 1 | Set-Content -LiteralPath $GuestStateHistory

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
$results += ("`nGuest who are older than "  + $GuestHistoryPurge +" days : " + $oldCnt)
$results += ("`nGuest who are warned             : " + $warnCnt)
$results += ("`nGuest historically deleted       : " + $delCnt)
$results += ("`nTotal Guests                     : " + $guestUsers.count)

Write-Output $results
$TN = $Tent.DisplayName
if (!(Test-Path -Path $GuestHistoryLog)) {
    "Report for $TN `n" | Out-File -file $GuestHistoryLog -Append   
    }

"`n######## GuestHistory Run: " + (get-date) + "########" | Out-File -file $GuestHistoryLog -Append
$lastRun + " `n" + $results | Out-File -file $GuestHistoryLog -Append
$PendingAcceptGuests | Sort-Object -Property UserStateChangedOn   | Format-Table -Property Mail,CreationType,UserState,UserStateChangedOn  |  Out-File -file $GuestHistoryLog -Append
("Guest who are older than $GuestHistoryPurge days: " + $theOldGuest.count) |  Out-File -file $GuestHistoryLog -Append
$theOldGuest | Sort-Object -Property UserStateChangedOn   | Format-Table -Property Mail,CreationType,UserState,UserStateChangedOn,LastAccess,Warned,DeletedOn   |  Out-File -file $GuestHistoryLog -Append

"`nActive Guests are:`n" + $ActiveGuestsTxt  |  Out-File -file $GuestHistoryLog -Append
if ($InviterTxt -ne "") { 
    "`nInvited Guests:`n" + $InviterTxt   |  Out-File -file $GuestHistoryLog -Append
    }

"`n######## End ########" | Out-File -file $GuestHistoryLog -Append

write-host "[End] Results in $GuestHistoryLog" -ForegroundColor Green

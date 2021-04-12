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
  [switch]$ForceBack
)

$Version = "2021.4."
$GuestHistoryPurge = 90
$GuestHistoryLog = "GuestHistory.Log"
$hasAD = ((get-module -ListAvailable -name ActiveDirectory).count -gt 0);


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
$GuestStateHistory = $env:TEMP  + "\GuestStateHistory." + $Tent.objectid + ".state"

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


# TODO
# check date of state file to make sure it is not more than x days ago

Write-Host "# Reviewing Guests for : " $Tent.DisplayName  " using " $Version
Write-Host "============================================"


Write-host $lastRunTxt
$lastRun = $lastRun.AddHours(-1)
$queryStartDateTimeFilter = '{0:yyyy-MM-dd}T{0:HH:mm:sszzz}' -f $lastRun.AddHours(-1)

 # Check to see if they fail to run AD Audit

 try { $lastAudit = Get-AzureADAuditSignInLogs -Top 1 -ErrorAction Stop 
    } catch {
    Write-Host "It appears you do not have SignInLogs access - STOPPING" -ForegroundColor Red -BackgroundColor Yellow
    break 
    }

Write-Progress -Activity "Getting Old Expire Invite Guest" 
 #Delete guest that are pending acceptance and disabled for longer than 30 days
  write-host "Accounts to Delete because they have not accepted their invite in 30 days" -ForegroundColor Yellow
  $PendingAcceptGuests = Get-AzureADUser -Filter "userType eq 'Guest'" -all $true -PipelineVariable guest | `
  where {($_.userstate -eq 'PendingAcceptance') -and ((get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-30))) -and $_.accountenabled -eq $false} 
   
  # $PendingAcceptGuests | Remove-AzureADUser 

  $guestUsers = Get-AzureADUser -Filter "userType eq 'Guest'" -all $true

write-host "Getting Active Guests " -ForegroundColor Green
Write-Progress -Activity "Getting accounts" 


# ....... this is the MONEY QUERY 


$guestState30 = [pscustomobject]@() 

Write-Output "Reading Guest's logins"

$ActiveGuestsTxt = ""
    
$i = 0
$ActiveGuest = @()
$theOldGuest = [pscustomobject]@()
#For each Guest user, validate there is a login in the last week
foreach ($guestUser in $guestUsers)
{
    $DN = $guestUser.DisplayName
    $ag = $ActiveGuest.count
    Write-Progress "Reading logs for Guest $DN" -PercentComplete ($i / $guestUsers.count*100) -Status "Active Guests $ag"

    # This can trigger errors "Message: This request is throttled."
    # TODO need to better detect and fix
    if ($i % 100 -eq 0) {
        Start-Sleep 10
        }
    # get the Guest users most recent signins

    try {
        $guestUserSignIns = Get-AzureADAuditSignInLogs -Top 1 -Filter "UserID eq '$($guestUser.ObjectID)' and createdDateTime ge $queryStartDateTimeFilter" -ErrorAction SilentlyContinue
        }
    Catch {
        Write-Progress "Stalled - Reading logs for Guest $DN" -PercentComplete ($i / $guestUsers.count*100)
         # we will see if this slows the script enough that MS let's it continue
        Start-Sleep 10
        $guestUserSignIns = Get-AzureADAuditSignInLogs -Top 1 -Filter "UserID eq '$($guestUser.ObjectID)' and createdDateTime ge $queryStartDateTimeFilter" 
        }

    if ($guestUserSignIns -eq $null) {
        # No longs in the last X days
        $oldMissingGuest= ($guestUser | select UserState, UserStateChangedOn) 
        #
        # Force all null to today (so we don't age them out too quickly)  very useful during FirstRun
        #
        
        if ($guestStateAll -ne $null -and ! $guestStateAll.ObjectId.Contains($guestUser.objectid)) {
           if (($oldMissingGuest.UserStateChangedOn) -eq $null) {
               $oldMissingGuest.UserStateChangedOn = $queryStartDateTimeFilter
               $oldMissingGuest.UserState = $oldMissingGuest.UserState + "/ForcedChangedOn"
               }
           $oldMissingGuest.UserState = $oldMissingGuest.UserState + "/ForcedLastAccess"
           $theOldGuest += [pscustomobject]@{
                objectid = $guestUser.objectid;
                userprincipalname = $guestUser.userprincipalname;
                Mail = $guestUser.Mail;
                CreationType = $guestUser.CreationType;
                UserState = $oldMissingGuest.UserState;
                UserStateChangedOn = $oldMissingGuest.UserStateChangedOn;
                LastAccess = $queryStartDateTimeFilter
                }

       
          }
      } else {
          
          Write-Verbose ("$DN was active " + $guestUserSignIns.CreatedDateTime)
          $MN = $guestUser.Mail
          $ActiveGuestsTxt = $ActiveGuestsTxt + "`n$DN ($MN) was active " + $guestUserSignIns.CreatedDateTime
          $ActiveGuest += $guestUser
          $theOldGuest += [pscustomobject]@{ 
            objectid = $guestUser.objectid;
            userprincipalname = $guestUser.userprincipalname;
            Mail = $guestUser.Mail;
            CreationType = $guestUser.CreationType;
            UserState = $guestUser.UserState;
            UserStateChangedOn = $guestUser.UserStateChangedOn;
            LastAccess = $guestUserSignIns.CreatedDateTime
          }
      
     }
     $i = $i+1



}
    
write-host ("Progressing Active Guests : " + $guestsum.count)   -ForegroundColor Green
$theOldGuest | ConvertTo-Json -Depth 1 | Set-Content -LiteralPath ".\Guest30.txt"


#
# Force all null to today (so we don't age them out too quickly)  very useful during FirstRun
#



# Sorting on UserState will keep ForceAge with the older (no-null) date
$GuestAll = ($theOldGuest + $guestStateAll) | Sort-Object  -Property ObjectId, LastAccess  | Sort-Object -Unique -Property ObjectId


write-host "Old Guests - which should be removed"
$theOldGuest = $GuestAll | where { (get-date $($_.LastAccess)) -lt $((get-date).adddays(-$GuestHistoryPurge)) -and (get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$GuestHistoryPurge))} 

  #  $theOldGuest | Remove-AzureADUser 
      
# TODO 
# Need to add notifcaiton e-mail and other logging, but the concept is sound.      


write-host ("Saving State for Next Run " + $GuestStateHistory)

#  -Compress 

 $GuestAll | ConvertTo-Json -Depth 1 | Set-Content -LiteralPath $GuestStateHistory

#set the time back to when we started this.

$setFile = Get-item -Path GuestStateHistory
$setFile.CreationTime = $StartingTime
$setFile.LastWriteTime = $StartingTime

$oldCnt = $theOldGuest.count
Write-Host "---------------------------------------" -ForegroundColor Yellow

Write-Output ("Guests active in last 30 days    : " + $guestState30.count)
Write-Output ("Pending older than 30 days       : " + $PendingAcceptGuests.count)
Write-Output ("Guest who are older than $GuestHistoryPurge days : " + $oldCnt)
Write-Output ("Total Guests                     : " + $guestUsers.count)

$TN = $Tent.DisplayName
"Report for $TN `n" | Out-File -file $GuestHistoryLog
("Pending older than 30 days: " + $PendingAcceptGuests.count) | Out-File -file $GuestHistoryLog
$PendingAcceptGuests | Sort-Object -Property UserStateChangedOn   | Format-Table -Property Mail,CreationType,UserState,UserStateChangedOn  |  Out-File -file $GuestHistoryLog -Append
("Guest who are older than $GuestHistoryPurge days: " + $theOldGuest.count) |  Out-File -file $GuestHistoryLog -Append
$theOldGuest | Sort-Object -Property UserStateChangedOn   | Format-Table -Property Mail,CreationType,UserState,UserStateChangedOn,LastAccess   |  Out-File -file $GuestHistoryLog -Append

"`nActive Guests are:`n" + $ActiveGuestsTxt  |  Out-File -file $GuestHistoryLog -Append

write-host "[End] Results in $GuestHistoryLog" -ForegroundColor Green

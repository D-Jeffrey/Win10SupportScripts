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
# D-jeffrey on github.com
#
# can use AD if module is present
#
param
(
  [Parameter(Mandatory = $false)]
  [switch]$FirstRun                    # This must be used if this is the first time
)

$GuestHistoryPurge = 90
$GuestHistoryLog = "GuestHistory.Log"
$hasAD = ((get-module -ListAvailable -name ActiveDirectory).count -gt 0);

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


if ($FirstRun.IsPresent -and (test-Path -LiteralPath $GuestStateHistory)) { 
    Write-host "This Script has been run before, this is not the firstRun"
    Break
    }
# Is the file existing or current enough
if ((Get-Item -LiteralPath $GuestStateHistory -ErrorAction SilentlyContinue).LastWriteTime -gt (Get-Date).AddDays(-29)) {
    write-Progress "Loading State..."
    $guestStateAll = (Get-Content -Raw -LiteralPath $GuestStateHistory) | ConvertFrom-Json
    
} else {
    if ($FirstRun.IsPresent) { 
        $guestStateAll =  [pscustomobject]@()
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



# TODO
# check date of state file to make sure it is not more than x days ago

Write-Host "# Reviewing Guests for : " $Tent.DisplayName
Write-Host "============================================"
Write-host "Last Run "  ((Get-Item $GuestStateHistory).LastWriteTime)
$lastRun = ((Get-Item $GuestStateHistory).LastWriteTime).AddDays(-1)
$queryStartDateTimeFilter = '{0:yyyy-MM-dd}T{0:HH:mm:sszzz}' -f $lastRun

 # Check to see if they fail to run AD Audit

 try { $lastAudit = Get-AzureADAuditSignInLogs -Top 1 -ErrorAction Stop 
    } catch {
    Write-Host "It appears you do not have SignInLogs access - STOPPING" -ForegroundColor Red -BackgroundColor Yellow
    break 
    }


 #Delete guest that are pending acceptance and disabled for longer than 30 days
  write-host "Accounts to Delete because they have not accepted their invite in 30 days" -ForegroundColor Yellow
  $PendingAcceptGuests = Get-AzureADUser -Filter "userType eq 'Guest'" -all $true -PipelineVariable guest | `
  where {($_.userstate -eq 'PendingAcceptance') -and ((get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-30))) -and $_.accountenabled -eq $false} 
   
  # $PendingAcceptGuests | Remove-AzureADUser 

  $allGuests = Get-AzureADUser -Filter "userType eq 'Guest'" -all $true

write-host "Getting Guests " -ForegroundColor Green
Write-Progress -Activity "Getting accounts" 

# $g30 = ( Get-AzureADUser -Filter "userType eq 'Guest'" -All $true -PipelineVariable guest | where {$_.userstate -ne 'PendingAcceptance'})

$guestUsers = Get-AzureADUser -Filter "UserType eq 'Guest' and AccountEnabled eq true and userstate ne 'PendingAcceptance'"

# Would like to do with this a Write-Progress but MS will trigger with 'This request is throttled' errors

# TODO ....... this is the MONEY QUERY .... but not working yet.


$guestState30 = [pscustomobject]@() 

    Write-Output "Getting User's logins for the last week"
    $guestUserSignIns = Get-AzureADAuditSignInLogs -Filter "UserID eq '$($guestUser.ObjectID)' and createdDateTime ge $queryStartDateTimeFilter"

#$guestUsers | ForEach-Object 
#        $guestState30 = $guestState30 + ($_ | where {!(Get-AzureADAuditSignInLogs -Filter "userid eq '$($guest.objectid)'" -top 1)} | `
#         select objectid, userprincipalname, Mail,CreationType, UserState, UserStateChangedOn )
#
        
#      }




$theOldGuest = [pscustomobject]@() 
#For each Guest user, validate there is a login in the last week
foreach ($guestUser in $guestUsers)
{
    Write-Output "Getting User's logins for the last week"
    $guestUserSignIns = Get-AzureADAuditSignInLogs -Filter "UserID eq '$($guestUser.ObjectID)' and createdDateTime ge $queryStartDateTimeFilter"

    if ($guestUserSignIns -eq $null) {
        # No longs in the last X days
        $theOldGuest += ($guestUser | select objectid, userprincipalname, Mail,CreationType, UserState, UserStateChangedOn) 
        #
        # Force all null to today (so we don't age them out too quickly)  very useful during FirstRun
        #

        if (($theOldGuest[$theOldGuest.count-1].UserStateChangedOn) -eq $null) {
            $guestState30[$i].UserStateChangedOn = $queryStartDateTimeFilter
            $guestState30[$i].UserState = "ForcedAge"
            }
      } else {
      $guestUserSignIns
      $theOldGuest += ($guestUser | select objectid, userprincipalname, Mail,CreationType, UserState, UserStateChangedOn)
      
     }
     $i = $i+1
     Write-Progress "Searching Guests " -PercentComplete ($i / $guestUsers.count*100)


}
    
write-host ("Progressing Active Guests : " + $guestsum.count)   -ForegroundColor Green
$guestState30 | ConvertTo-Json -Depth 1 | Set-Content -LiteralPath ".\Guest30.txt"


#
# Force all null to today (so we don't age them out too quickly)  very useful during FirstRun
#



# Sorting on UserState will keep ForceAge with the older (no-null) date
$GuestAll = ($guestState30 + $guestStateAll) | Sort-Object -Property ObjectId, UserStateChangedOn  ##################################### | Sort-Object -Unique -Property ObjectId


write-host "Old Guests - which should be removed"
$theOldGuest = $GuestAll | where { (get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$GuestHistoryPurge))} 

  #  $theOldGuest | Remove-AzureADUser 
      
# TODO 
# Need to add notifcaiton e-mail and other logging, but the concept is sound.      


write-host ("Saving State for Next Run " + $GuestStateHistory)

#  -Compress 

 $GuestAll | ConvertTo-Json -Depth 1 | Set-Content -LiteralPath $GuestStateHistory

Write-Host "---------------------------------------" -ForegroundColor Yellow

Write-Output ("Guests active in last 30 days " + $guestState30.count)
Write-Output ("Pending older than 30 days    " + $PendingAcceptGuests.count)
Write-Output ("Guest who are older than $GuestHistoryPurge days " + $theOldGuest.count)
Write-Output ("Total Guests      " + $allGuests.count)

("Pending older than 30 days: " + $PendingAcceptGuests.count) | Out-File -file $GuestHistoryLog
$PendingAcceptGuests | Sort-Object -Property UserStateChangedOn   | Format-Table -Property Mail,CreationType,UserState,UserStateChangedOn  |  Out-File -file $GuestHistoryLog -Append
("Guest who are older than $GuestHistoryPurge days: " + $theOldGuest.count) |  Out-File -file $GuestHistoryLog -Append
$theOldGuest | Sort-Object -Property UserStateChangedOn   | Format-Table -Property Mail,CreationType,UserState,UserStateChangedOn   |  Out-File -file $GuestHistoryLog -Append

write-host "[End] Results in $GuestHistoryLog" -ForegroundColor Green

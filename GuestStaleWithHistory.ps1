#Requires -Modules AzureADPreview
#
# WIP - Purge old Guest accounts by running this perodically to get the list of accounts, keep it for future runs, then after it pasts the cutoffage, remove the acount
# also remove accountw which have not accepting their invition and are older then 30 days credit 
# to https://github.com/chadmcox/Azure_Active_Directory_Scripts/tree/master/Guests
#

$GuestStateHistory = $env:TEMP  + "\GuestStateHistory.state"
$GuestHistoryPurge = 90


# Is the file existing or current enough
if ((Get-Item -LiteralPath $GuestStateHistory -ErrorAction SilentlyContinue).LastWriteTime -gt (Get-Date).AddDays(-29)) {
    $guestStateAll = (Get-Content -Raw -LiteralPath $GuestStateHistory) | ConvertFrom-Json
    write-host "loading State"
} else {
    $guestStateAll =  [pscustomobject]@()
    Write-Host "Warning - running without a previous Guest State History, only continue if this is the first time you have started this process"
    Write-Host "   Or the history may be more than 30 days old, which means you may have lost records"

    # Add prompt to continue


 }



 #Delete guest that are pending acceptance and disabled for longer than 30 days
  write-host "Should Delete the following accounts" -ForegroundColor Yellow
  Get-AzureADUser -Filter "userType eq 'Guest'" -all $true -PipelineVariable guest | `
  where {($_.userstate -eq 'PendingAcceptance') -and ((get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-30))) -and $_.accountenabled -eq $false} | `
      Out-Host
      # Remove-AzureADUser 
write-host "Getting Guests "
$guestState30 = ( Get-AzureADUser -Filter "userType eq 'Guest'" -All $true -PipelineVariable guest | where {$_.userstate -ne 'PendingAcceptance'} | `
    where {!(Get-AzureADAuditSignInLogs -Filter "userid eq '$($guest.objectid)'" -top 1 -ErrorAction SilentlyContinue)} | `
        select objectid, userprincipalname, Mail,CreationType, UserState, UserStateChangedOn )

$guestsum = $guestState30 + $guestStateAll


$GuestAll = ($guestState30 + $guestStateAll) | Sort-Object -Descending -Property ObjectId, UserStateChangedOn | Sort-Object -Unique -Property ObjectId

#
# Force all null to today (so we don't age them out too quickly)
#
$i=0 
while ($i -lt $GuestAll.count) {
 if (($GuestAll[$i].UserStateChangedOn) -eq $null)  {
        $GuestAll[$i].UserStateChangedOn = (get-date).ToString()
        $GuestAll[$i].UserState = "ForcedAge"
    }
    $i++
    }

write-host "Old Guests"
$GuestAll | where { (get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-$GuestHistoryPurge))} | `
     Out-Host
      # Remove-AzureADUser 
      
# Need to add notifcaiton e-mail and other logging, but the concept is sound.      



# $guestStateAll | ConvertTo-Json -Depth 1 -Compress | Set-Content -LiteralPath $GuestStateHistory
 $guestStateAll | ConvertTo-Json -Depth 1 | Set-Content -LiteralPath $GuestStateHistory

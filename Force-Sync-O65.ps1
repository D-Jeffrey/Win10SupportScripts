# Force-Sync-O65.ps1
#
# Trigger an AD Connect Sync to AAD
#
# Get-ADSyncScheduler
# Start-sleep 10


Write-Host "Initializing Azure AD Delta Sync..." -ForegroundColor Yellow

$attemps = 5

try
{
        Start-ADSyncSyncCycle -PolicyType Delta | Out-Null
    
        do
        {
            Start-sleep 15
            Write-Host "." -NoNewline
        }
        until ((Get-ADSyncConnectorRunStatus).runstate -eq $null)
        Write-Host "+"

        $out = "Syncronization Successfully Completed"
        
        
        Write-Host " | Complete!" -ForegroundColor Green
     
 
}
catch
{
    $out = $_.Exception.Message
}

Write-Host $out

Write-Host " | END (this window can be closed) " 
Start-sleep 60

    # Test for URL Issues
    #
    #
    
       $localpath = $env:TEMP
       $prefix = "AccessURL-"
       $startnumber = 0
       
$issueURL = @(
    "https://t.ssl.ak.dynamic.tiles.virtualearth.net/comp/ch/0213033?mkt=en-GB&it=G,LC,BX,RL&shading=hill&n=z&og=1926&cstl=rd&key=AqTrPBPn-2KPU6aSfuOMHbmetsYCgJyAd5RHBbTU8g8bHEatRUSPTqZOqWCigvXy",
    "https://dev.virtualearth.net/webservices/v1/LoggingService/LoggingService.svc/Log?entry=0&fmt=1&type=3&group=MapControl&name=MVC&version=v8&mkt=en-CA&auth=AqTrPBPn-2KPU6aSfuOMHbmetsYCgJyAd5RHBbTU8g8bHEatRUSPTqZOqWCigvXy&jsonp=Microsoft.Maps.NetworkCallbacks.f_logCallbackRequest",
    "https://go.microsoft.com/fwlink/?linkid=867439",
    "https://aka.ms/mfasetup",
    "https://az416426.vo.msecnd.net/scripts/a/ai.0.js",
    "https://az495088.vo.msecnd.net/app-logo/customappsso_215.png",
    "https://strep-prod-streaming-amsprodquickhelpcus-usct.streaming.media.azure.net/29aaae13-f622-4e32-bef8-ec67579c653a/TEAMS_Where_Are_Shared_Files_Sav.ism/manifest(format=mpd-time-csf)",
    "https://www.youtube.com/iframe_api",
    "https://hothardware.com/news/win11-update-broke-the-start-menu",
    "https://www.google.com",
    "https://www.office.com") 




    $client = new-object System.Net.WebClient 

    
    $successcnt= 0
    
    $issueURL | ForEach-Object {
        $sourceuri = $_
        $startnumber = $startnumber + 1
        $lname = $prefix + $startnumber.ToString("D2") + ".tmp"
             
        $filename = $localpath + "\" + $lname
        

        write-host ("# Item #" + $startnumber + " :" + $sourceuri )
           
        
        try
        {
            $client.DownloadFile($sourceuri, $filename) 
            write-host "Downloaded $sourceuri" -ForegroundColor Green
            $successcnt = $successcnt+1         
        }
        catch
        {
            write-host "--- Failed $sourceuri" -ForegroundColor Yellow
        }
        
       } 
       
       # get-item -Path ($localpath + "\$prefix*.tmp") 
       remove-item -Path  ($localpath + "\$prefix*.tmp") 

       $issuecnt = $issueURL.Count
       $res = ($successcnt / $issuecnt) 
       
       $res = $res.ToString("P") 
       if ($successcnt -eq $issuecnt) {
            $res = $res + " PERFECT"
       } else   {
            $res = $res + " Something is NOT RIGHT"
       }

       
        write-host "`n========= Complete : Successful $successcnt vs $issuecnt tries = $res" -ForegroundColor Cyan
        

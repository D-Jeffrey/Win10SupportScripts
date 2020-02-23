$build = [System.Environment]::OSVersion.Version.Build
$appKey = 'HKLM:\Software\DJ\Post\'

$sysDrv = ([System.Environment]::SystemDirectory.Substring(0,2))

Start-Transcript -Path ($sysDrv + "\transcripts\Post-Update-Run.txt") -Append


if (Test-Path ($appKey) -ErrorAction SilentlyContinue) {
    $lastbuild = Get-ItemProperty -path $appKey -name  "Build"   
    }
else {
    New-Item -Path ($appKey -replace "Post\\", "")
    New-Item -Path $appKey
    $lastbuild = 0
    }
if ($lastbuild -ne $build) {
  $sysDrv = ([System.Environment]::SystemDirectory.Substring(0,2))

  if (test-Path ($sysDrv + "\Users\Public\is-real-public.txt")) {
    Stop-Transcript 
    exit
  } 
  else 
  {
    
    Set-ItemProperty -Path $appKey  -Name "Updating"  (get-date)
 
      $sysDrv = ([System.Environment]::SystemDirectory.Substring(0,2))
      Push-Location ($sysDrv + "\")

     if (test-Path "\users\Public.del\" -ErrorAction Ignore) {
        attrib -s -h \users\Public.del\*.*
        takeown /r /d y /f \users\Public.del
        attrib -s -h \users\Public.del\*.*
        remove-item -Path "\users\Public.del" -Recurse -Force -ErrorAction Continue
    }


      Rename-Item ($sysDrv + "\Users\Public") "Public.del"
      # Make a new Public Directory structire
      New-item -ItemType directory -Path  ($sysDrv + "\Users\Public") 

      # we are going to remount Partition 3 (Spin harddrive to SSD harddrive mount point)
      if (test-path "\Users\darre\downloads\desktop.ini" -ErrorAction Ignore) {
        attrib -s -h  \Users\darre\downloads\desktop.ini
        del \users\darre\downloads\desktop.ini
        }

      # Remove-PartitionAccessPath -DiskNumber 1 -PartitionNumber 3 -AccessPath ($sysdrv + "\users\Darre\Downloads") -ErrorAction Ignore
      Remove-PartitionAccessPath -DiskNumber 1 -PartitionNumber 4 -AccessPath ($sysDrv + "\windows.old\users\Public") -ErrorAction Ignore
      Remove-PartitionAccessPath -DiskNumber 1 -PartitionNumber 3 -AccessPath ($sysDrv + "\windows.old\users\darre\Downloads") -ErrorAction Ignore
      Remove-PartitionAccessPath -DiskNumber 1 -PartitionNumber 3 -AccessPath ($sysDrv + "\Users\darre\downloads (1)") -ErrorAction Ignore

      Get-Partition -DiskNumber 1 -PartitionNumber 3 | Add-PartitionAccessPath -AccessPath ($sysDrv + "\users\Darre\Downloads") -ErrorAction Continue
      Get-Partition -DiskNumber 1 -PartitionNumber 4 | Add-PartitionAccessPath -AccessPath ($sysDrv + "\users\Public") -ErrorAction Continue
      
   }
   Set-ItemProperty -Path $appKey -Name "Build" $build  
}
Stop-Transcript
exit 




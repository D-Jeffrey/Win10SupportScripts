# PST-Move-fixup.PS1
# Designed to move PST files outside of OneDrive at logon time.
#
# Support for WhatIf, Verbose and Debug options
#
# This is a scanner for use on the Registry check the profiles of V16.0 Outlook, files the associated PST files, check to see if it is in OneDrive space, and moves it if it is.
#
#  Place this in a directory everyone can access.
#  run script with   -install to hook to to the logon (-remove to unhook)
#  Running the script when Outlook is not running it will map and remap outlook files.
#
#  There is still a possible race condition depend on how the computer logon/startup works.


param
(
  [Parameter(Mandatory = $false)]
  [switch]$WhatIf,          # Test only
  # [switch]$Verbose,         # Implictly supported
  # [switch]$Debug,           # Implictly supported

  [switch]$Install,         # Hook to the Schedule tasks of the computer
  [switch]$Remove           # Remove Scheduled task

)


if ($PSBoundParameters.ContainsKey('Install')) {
    #Write-Host "Install Not Yet Supported"

    $scriptname = $PSScriptRoot + "\" + $PSCmdlet.CommandRuntime
    $cmd = 'Powershell.exe -WindowStyle Minimized  -File "' + $scriptname +'" '
    
    # $cmd = 'Powershell.exe -WindowStyle Hidden -File "' + $scriptname +'" '
    
    
    try {
        New-ItemProperty -Path "hklm:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "PSTOnedrive" -Value $cmd -Propertytype STRING -Force -ErrorAction Stop | Out-Null 
        write-host "Installed for All Users"
    } catch {
        
        New-ItemProperty -Path "hkcu:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "PSTOnedrive" -Value $cmd -Propertytype STRING -Force | Out-Null 
        write-host "Installed for this users only"
       }
    
     

    return
    }
if ($PSBoundParameters.ContainsKey('Remove')) {
    # Brute force and keep on going...
    
    remove-ItemProperty -Path "hklm:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "PSTOnedrive"  -Force -ErrorAction SilentlyContinue | Out-Null 
    remove-ItemProperty -Path "hkcu:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "PSTOnedrive"  -Force -ErrorAction SilentlyContinue| Out-Null 
    write-host "Removed"
    return
    }


# This is the magic switch which causes the edits to occur (Turn it off to do What if

$proceed = $true
if ($WhatIf.IsPresent) {
    $proceed = $false
    Write-Host "WhatIf Testing only" -ForegroundColor Yellow
    }

$scriptRegName = "HKCU:\Software\W10Stuff\PSTMoveFromOneDrive"
$scriptRegProfile = "PSTFix"
$scriptVersion =  20210202
$scriptRegValue = "Version"
        

# This script support Verbose and Debug
if (!$VerbosePreference) {
  $oldVerbose =  $VerbosePreference
  }
write-host $PSBoundParameters

if ($PSBoundParameters.ContainsKey('Verbose')) {
   $VerbosePreference = "Continue"
   } else {
   $VerbosePreference = "SilentlyContinue"
   }
 

if (!$DebugPreference) { 
  $oldDebug =  $DebugPreference
  }
if ($PSBoundParameters.ContainsKey('Debug')) { 
   $DebugPreference = "Continue"
   } else {
  $DebugPreference = "SilentlyContinue"
   }

if(!(Test-Path $scriptRegName))   {

    New-Item -Path $scriptRegName -Force | Out-Null
    $lastRun = 0
    
   } else {

    $lastRun = Get-ItemPropertyValue -Path $scriptRegName -Name $scriptRegValue 
   }


if ($proceed) {
    New-ItemProperty -Path $scriptRegName -Name $scriptRegValue -Value $scriptVersion -Propertytype DWORD -Force | Out-Null
    New-ItemProperty -Path $scriptRegName -Name "Last Run" -Value (Get-Date -format yyyy-MMM-dd` hh-mm` tt).ToString() -Propertytype STRING -Force | Out-Null
    }




#=============================
# Make sure the file is not a duplicate, it is is a duplicate, then cfigure out a new name for the by add a (1) or if there is already a "(n)." then determine how to increase the number
#
function UniqueFileInstance {
 param ([string[]]$filespec ) 

    Write-Debug ("UniqueFileInstance for    : " + $filespec)

    $i = 0
    if ((Split-Path -path $filespec -Leaf) -match("\((\d+)\)\..{3,4}$")) {
        $i = [int]$Matches[1]
    }
    
    if ($i -lt 1 -or $i -eq $null) { $i = 0 }
    $newfilepathname = $filespec 

    
    $basename = (Split-Path -path $filespec -Parent) + "#\" + ((Split-Path -path $filespec -Leaf)  -replace("(\((\d+)\))*(\..{3,4})$", ""))
    $Matches = $null
    if ((Split-Path -path $filespec -Leaf) -match("(\..{3,4})$")) {
        $ext = $Matches[1]
        } else {
        $ext = ".pst"
    }
    # write-debug ("#b: [" + $basename + "]  #c: $i  #e: [" + $ext + "]") 
    while (Test-Path -path $newfilepathname) {
        $i = $i + 1

        $newfilepathname = $basename + "(" + $i + ")" + $ext
        }
    Write-Debug ("UniqueFileInstance result : " + $newfilepathname)

    return $newfilepathname
}

#-----------
#
# Scan the registry for PST files in the Outlook Profile
#
#-----------

  if ((Get-Process -Name "Outlook").count -ne 0) {
     Write-Verbose "Outlook is running, skipping remapping of open PST files" 
     }
  else { 
     # We are only checking the current version of Office  V 16
     Get-ChildItem -recurse "hkcu:\Software\Microsoft\Office\16.0\Outlook\Profiles" -ErrorAction SilentlyContinue | foreach { 
     $path = $_.PSPath
     
     $name = $_
     Write-Debug ("Checking " + $path )
     $prop = $null
     $prop = get-itemproperty -path $path -name "001f6700" -ErrorAction SilentlyContinue
     if ($prop -ne $null) {
        #  Found a PST file attribute

        $filepathname = [System.Text.Encoding]::Unicode.GetString($prop."001f6700")
        $filepathname =$filepathname.Trim([char]0x00)
        Write-Verbose "Found PST in Reg @ $name  for Filepath  [$filepathname]"

        # Test to see if it is within the OneDrive directory space
        if ($filepathname -like $env:OneDriveCommercial + "\*") {
            Write-Debug "Found in OneDrive space"

            # make sure we don't try and move overtop of another PST by the same name -- otherwise generate a (1).pst or (2).pst type name to avoid duplciations
            $newfilepathname = UniqueFileInstance ($env:USERPROFILE + "\localFiles\" + (get-item($filepathname) | select BaseName ).BaseName + ".pst")
            
            $propName = ""
            Write-Verbose "New Locaiton will be [$newfilepathname]"
            try {
                if ($proceed) {
                    move-item -Path $filepathname -Destination $newfilepathname 
                    $propName = "001f6700"

                } else { 
                    move-item -Path $filepathname -Destination $newfilepathname -WhatIf
                    $propName = "001f6700x"
        
                    }  
              } catch { 
                $propName = "" 
              }
            if ($propName -ne "") {
                $newbytes = [System.Text.Encoding]::Unicode.GetBytes($newfilepathname+[char]0x00)
                write-debug ("Update Registry : " + $newbytes)
                # update the registry path (depend on testing or not, slightly different reg values
                Set-ItemProperty -path $path -name $propName  -ErrorAction Stop -Value $newbytes
                Write-Host ("Moved File $filepathname to $newfilepathname ") -ForegroundColor DarkYellow
                }
            } # in OneDrive Space

        } # found PST
      } # for Each Get-Item
      } # Is Outlook running


    Get-ChildItem -Recurse $env:OneDriveCommercial -Filter "*.pst" | ForEach-Object { 
        $filepathname = $_.FullName
        $newfilepathname = UniqueFileInstance ($env:USERPROFILE + "\localFiles\" + $_.BaseName + ".pst")
    
        Write-Debug ($filepathname  + " -> " + $newfilepathname)
        
        if ($proceed) {
                  move-item -Path $filepathname -Destination $newfilepathname -ErrorAction Continue
                  Write-Host ("Moved File $filepathname to $newfilepathname ") -ForegroundColor DarkYellow
            } else { 
                  move-item -Path $filepathname -Destination $newfilepathname -WhatIf
            
        }
    }


if ($oldVerbose) {  $VerbosePreference = $oldVerbose ;   Remove-Variable $oldVerbose }
if ($oldDebug) {  $DebugPreference =   $oldDebug ; Remove-Variable $oldDebug }

Write-Verbose "End of Script - waiting for sleep" 
# get rid of this pause when we roll it out.
sleep 20

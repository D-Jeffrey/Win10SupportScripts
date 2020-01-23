# RReg-Search.PS1
# Designed to Rip a Folder Redirection off a computer
#
#
#
# Simplicist Support for Verbose and Debug options
#
# This is a scanner for use on the Registry and do a mass edit of paths or other changes to the registry
# This was created to move folder from one server to others.
# Is was also contructed to deal re-writing of paths after disabling Folder Redirector to Server
#
# It uses a progress bar to indicate it is still working.
# It is designed to go in a reoccuring logon script or something else, so it checked the version to see if it completed.  The idea being that you change the table, then increase the version and it will run again.
#
# when altering the Table of Find Replace:
#   - it is pairs
#   - Be specific on how you are replacing names
#   - do not just replace the name of a server, with another server , unless you have moved everything (printers, folders, shares, web urls) as an exact close
#   - There is NO UNDO for this.  So TEST TEST TEST
#
# there are options for snapshoting the registry
#      http://portableapps.com/apps/utilities/regshot_portable
#        http://sourceforge.net/projects/regshot/
#
# Second component is clearing of OST keys in the profile if the file is on the server ... \\ in the path
#
#   Darren Jeffrey 
#   Last: May 6, 2019
#   20190506
#
#
$FindReplaceTable = @( 
    ("\\oldServer\bookkeeping\",            "\\theServer\bookkeeping\"),
    ("\\oldserver\general\",                "\\theServer\general\"),
    ("\\oldserver\executive\",              "\\theServer\executive\"),
    ("//olderver.sccc.local/users/",       "//theServer/users/"),
    ("\\oldserver.sccc.local\users\",       "\\theServer\users\"),
    ("\\oldserver\users\",                  "\\theServer\users\"),
#    ("\\OLDSERVER\Folder Redirection\jim\", "c:\users\jim\"),
#    ("//OLDSERVER/Folder%20Redirection/JIM/", "c:/users/jim/",
    ("\\Churchserver\children\",               "\\theServer\children\"),
    ("/oldServer/bookkeeping/",             "/theServer/bookkeeping/"), 
    ("/oldserver/general/",                 "/theServer/general/"),
    ("/oldserver/executive/",               "/theServer/executive/"),
    ("/oldserver/children/",                "/theServer/children/")
    )
        
    

$top = "hkcu:\Software\"


# This is the magic switch which causes the edits to occur (Turn it off to do What if
$proceed = $true

$skiplist = "StartupItems|osfinstaller|RemoteSettings|MathFonts|VisualStudio|Panose|ApplicationAssociationToasts|FileExts|ContentDelivryManager|CloudStore|OpenWithList|FeatureUsage|OpenWithList|Discardable|PushNotifications|LogonUI|\?|Classes"

$FindItSize = $FindReplaceTable.Length
$MatchType = ($FindReplaceTable[0][0]).Gettype()


$scriptRegName = "HKCU:\Software\SCCC\FolderMove"
$scriptRegValue = "Version"
$scriptRegOST = "FixProfile"
$scriptRegProfile = "FixProfile"
$scriptVersion =  1
                # 1 was the first pass 2
$p = 0
$pp = 0
$fix = 0


if (!$VerbosePreference) {
  $oldVerbose =  $VerbosePreference
  }
  # $VerbosePreference = "SilentlyContinue"
   $VerbosePreference = "Continue"
 

if (!$DebugPreference) { 
  $oldDebug =  $DebugPreference
  }
  # $DebugPreference = "Continue"
  $DebugPreference = "SilentlyContinue"
 


if(!(Test-Path $scriptRegName))   {

    New-Item -Path $scriptRegName -Force | Out-Null
    $lastRun = 0
    
   } else {

    $lastRun = Get-ItemPropertyValue -Path $scriptRegName -Name $scriptRegValue 
   }

   
   if ($lastRun -gt  $scriptVersion)  {
        Write-Output "Folder Move not needed"
    
    } else {

        $m = "Working with an edit table of " + $FindItSize.ToString() + " @ " + $top
   write-Verbose $m

   if ($proceed) { Write-Host "Proceeding to Update Search and replace, abort now if you made a mistake" -ForegroundColor Yellow ; sleep 5 ; Write-Host "Ready" -ForegroundColor Green  ; sleep 3 }


New-ItemProperty -Path $scriptRegName -Name $scriptRegValue -Value $scriptVersion -Propertytype DWORD -Force | Out-Null


Get-ChildItem -recurse $top -Exclude "Classes*" -depth 5 -ErrorAction SilentlyContinue | foreach { 
  $path = $_.PSPath
  
  
  
  if ($path -match $skiplist) 
  {
  write-Debug "Skipping $path" 
  $pp++
  if ($pp -gt 40 ) {$pp = 0 ; 
      $pos = $path.IndexOf("Software\")+9
      $m = "##"+ $path.Substring($pos) 
      Write-Progress -Activity “Scanning Registry” -status $m -percentComplete (($p++) % 2000 / 20)
      }

  } else {
  Write-debug $path
  $pos = $path.IndexOf("Software\")+9
  $m  = $path.Substring($pos)
  
  if ($p++ % 10 -eq 0) { Write-Progress -Activity “Scanning Registry” -status $m -percentComplete ($p % 2000 / 20) }
 
  
  # if ($_.Property.Length -gt 50) { write-host $_.Property.Length +" : " + $path    }
  $_.Property | foreach {

    $name = $_
    $srcString = $null
    if ($name) {
try {
    $srcString = get-itemproperty -path $path -name $name -ErrorAction Stop |  select -expand $name -ErrorAction Stop
    } catch {
    
    $mm = "$m \ $name : " + $_.Exception.Message

    Write-Debug $mm 
    

    }
}
    # write-host $srcString.Gettype().fullName 
    if ($srcString) {
          # $xx = $srcString.ToString() ; Write-host "$path\$name  $xx"
          if ($srcString.Gettype()  -eq $MatchType) {
          #  Write-host "$path\$name "
            
            for ($i=0; $i -le $FindItSize-1; $i++ ) {
        
                if ($srcString -like ("*" + $FindReplaceTable[$i][0] + "*") )  {
                    
                    $newString = $srcString -replace ([System.Text.RegularExpressions.Regex]::Escape($FindReplaceTable[$i][0]), $FindReplaceTable[$i][1])
                    $itChanged = ($newString -cne $srcString) 
                    
                    Write-Verbose "$m\$name :  $Changed"
                    Write-Verbose "     $srcString"                 
                    Write-Verbose "  -> $newString" 
                    if ($itChanged) {
                        if ($proceed) { set-itemproperty -path $path -name $name -value $newString   }
                        else { set-itemproperty -path $path -name $name -value $newString  -verbose  -whatif }
                        $fix++
                    } else {
                      write-host "$m\$name (Unchanged): $newString" -ForegroundColor Green
                    }
                }
            }
         }
    } # if null
    
    }
  }
}

#set it to indicate this release was completed.

if ($proceed) { 
  $scriptVersion++
  New-ItemProperty -Path $scriptRegName -Name $scriptRegValue -Value $scriptVersion  -Propertytype DWORD -Force | Out-Null 
  New-ItemProperty -Path $scriptRegName -Name "Last Run" -Value (Get-Date).toString() -Propertytype STRING -Force | Out-Null
}

Write-Output ("** Completed:" + (Get-Date).toString() + " with " + $fix + " fixed up entries.")
}



#-----------
#
# Clear OST from Profile
#
#-----------

$fixOST = Get-ItemProperty -Path $scriptRegName -Name $scriptRegOST -ErrorAction SilentlyContinue |  select -expand $scriptRegOST -ErrorAction SilentlyContinue 
if ($fixOST -ne 1) {

  $p = 0
  Get-ChildItem -recurse "hkcu:\Software\Microsoft\Office\16.0\Outlook\Profiles" -ErrorAction SilentlyContinue | foreach { 
     $path = $_.PSPath
     $pos = $path.IndexOf("16.0\")+5
     $m  = $path.Substring($pos)
     # Write-debug $m
     $_.Property | foreach {
         Write-Progress -Activity “Clearing OST Files ” -status $m -percentComplete ($p % 100) 
         $name = $_
         $srcString = $null
         if ($name) {
             # Write-debug ($m  +"\" + $name)
     
             # write-Output ($name + ": " + $srcString)
            
             if ($name -match ("001f6610")) { 

                 $srcString = get-itemproperty -path $path -name $name -ErrorAction Stop |  select -expand $name -ErrorAction Stop
              
                 $asciiChars = $srcString -split ' ' | ForEach-Object { if ($_ -ne 0) {[char][byte]"$_"}}
                 $asciiString = $asciiChars -join ''

                 $xx = $srcString.ToString() ; 
                 Write-Verbose "Found     : $m\$name #### $asciiString"
                 if ($asciiString -match("\\\\")) {
                 Write-Output  "Removing  : $m\$name "
                   if ($proceed) { remove-itemproperty -path $path -name $name  }
                   else { remove-itemproperty -path $path -name $name  -verbose  -whatif }
                   }
              } # - match
            
            
        }    #$name null             
         

    } # foreach property
    } # for Each Get-Item
    if ($proceed) { 
        New-ItemProperty -Path $scriptRegName -Name $scriptRegOST -Value 1  -Propertytype DWORD -Force | Out-Null 
        }
}  # Outlook OST edit

#-----------
#
# Profile Check
#
#-----------

$shellPath = "hkcu:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders\"

function ProfileCheck
{
Param ([string] $key, [string] $def)

   $setProfile = "-"
   try {
     $name = Get-ItemProperty -Path  $shellPath -name $key  | select -expand $key
     $setProfile = $name
     write-host $name
     $pos = $name.IndexOf("\\")
     if ($pos -eq 0) {
        Write-Verbose "Setting $key to default $def (was: $name)"
        Set-ItemProperty -Path  $shellPath -Name $key -Value $def -WhatIf
        $setProfile = $def
        }
      } catch {
      }
      
  
return $setProfile
}


$fixOST = Get-ItemProperty -Path $scriptRegName -Name $scriptRegProfile -ErrorAction SilentlyContinue |  select -expand $scriptRegProfile -ErrorAction SilentlyContinue 
if ($fixOST -ne 1) {

  $p = 0
  $name = Get-ItemProperty -Path  "hkcu:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders\"   -ErrorAction SilentlyContinue | select -expand "desktop"
      
  
     $pos = $path.IndexOf("\\")
     $m  = $path.Substring($pos)
     # Write-debug $m
     $_.Property | foreach {
         Write-Progress -Activity “Clearing OST Files ” -status $m -percentComplete ($p % 100) 
         $name = $_
         $srcString = $null
         if ($name) {
             # Write-debug ($m  +"\" + $name)
     
             # write-Output ($name + ": " + $srcString)
            
             if ($name -match ("001f6610")) { 

                 $srcString = get-itemproperty -path $path -name $name -ErrorAction Stop |  select -expand $name -ErrorAction Stop
              
                 $asciiChars = $srcString -split ' ' | ForEach-Object { if ($_ -ne 0) {[char][byte]"$_"}}
                 $asciiString = $asciiChars -join ''

                 $xx = $srcString.ToString() ; 
                 Write-Verbose "Found     : $m\$name #### $asciiString"
                 if ($asciiString -match("\\\\")) {
                 Write-Output  "Removing  : $m\$name "
                   if ($proceed) { remove-itemproperty -path $path -name $name  }
                   else { remove-itemproperty -path $path -name $name  -verbose  -whatif }
                   }
              } # - match
            
            
        }    #$name null             
         

    } # foreach property
    } # for Each Get-Item
    if ($proceed) { 
        New-ItemProperty -Path $scriptRegName -Name $scriptRegProfile -Value 1  -Propertytype DWORD -Force | Out-Null 
        }
}  # Outlook OST edit

if ($oldVerbose) {  $VerbosePreference = $oldVerbose }
if ($oldDebug) {  $DebugPreference =   $oldDebug }


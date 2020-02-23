# Credit to https://github.com/MatsHellman
#
# 
############################################
#  Check Outlook Running and close if needed
############################################
function CheckOutlookRunning {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName PresentationFramework
    
    $OutlookRunningMessage  =   "Your Outlook is open and it needs to be closed before we continue. Please save" +
                                " all your on-going work. By selecting YES, your Outlook will be automatically closed." +
                                " Select NO if you would like to continue later."
    # get Outlook process
    $outlook = Get-Process Outlook -ErrorAction SilentlyContinue

    if ($outlook) {
        $msgCloseOutlook = [System.Windows.Messagebox]::Show(
            $OutlookRunningMessage,
            'Outlook needs to be closed',
            'YesNo',
            'Error'
        )
        switch ($msgCloseOutlook) {
            Yes { 
                $Answer = $True 

                # Try gracefully first
                $outlook.CloseMainWindow()
                # Kill after fifteen seconds
                Start-Sleep 15
                if (!$outlook.HasExited) {
                $outlook | Stop-Process -Force
                }
            }
            Default {
                $Answer = $False
            }
        }
    }
    Return $Answer
}

#############################################
# Get the users to find a folder SelectTarget
#############################################
function SelectTarget {
    
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms")|Out-Null

    $foldername = New-Object System.Windows.Forms.FolderBrowserDialog
    $foldername.Description = "Please select a folder. Ex. C:\Temp, all files will be moved here."
    $foldername.rootfolder = "MyComputer"

    if($foldername.ShowDialog() -eq "OK")
    {
        $folder += $foldername.SelectedPath
    }
    return $folder
    
}

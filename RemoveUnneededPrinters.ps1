#This Powershell script removes superfluous printers from a new Windows 10 PC.  
#August 1, 2018
#Josh Gold

#Forces my script to follow Powershell best practices
Set-StrictMode -Version Latest
# $ErrorActionPreference = 'SilentlyContinue'

$PrintersToRemove = @("Microsoft XPS Document Writer", "Fax", "OneNote for Windows 10", "Send To OneNote 16")
#$drivers = Get-PrinterDriver -Name

$allprinters = Get-Printer

foreach ($Printer in $PrintersToRemove)
{
	if ($allprinters.Name -like $Printer) { 
		write-Output "Remove $Printer"
		Remove-Printer -Name $Printer
    } else  {
		write-Output "No $Printer"
	}
    
}
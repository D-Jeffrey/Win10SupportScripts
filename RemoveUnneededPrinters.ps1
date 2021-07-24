#This Powershell script removes the extra built in printers from Windows 10 

Set-StrictMode -Version Latest

$PrintersToRemove = @("Microsoft XPS Document Writer", "Fax", "OneNote for Windows 10", "Send To OneNote 16")

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

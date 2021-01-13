# Win10SupportScripts
Misc Scripts use on Windows 10 computers to do some PC Pro support tasks

## __Rreg-search.ps1__

Simplicity support for Verbose and Debug options

This is a scanner script for use on the Registry and do a mass edit of paths or other changes to the registry
This was created to move folder from one server to others.
Is was also constructed to deal re-writing of paths after disabling __Folder Redirector__ to a Windows Server

It uses a progress bar to indicate it is still working.
It is designed to go in a recurring logon script or something else, so it checked the version to see if it completed (run one).  The idea being that you change the table, then increase the version and it will run again.

When altering the Table of Find and Replace list:
  - it is pairs
  - Be specific on how you are replacing names
  - do not just replace the name of a server, with another server , unless you have moved everything (printers, folders, shares, web urls) as an exact clone
  - There is NO UNDO for this.  So TEST TEST TEST

There are options for snapshotting the registry
     http://portableapps.com/apps/utilities/regshot_portable
       http://sourceforge.net/projects/regshot/

The second component of this script clears of OST keys in the profile so it will recreate the file in a different location (within Appdata) especially if it was embbedded into a folder redirection path to a server ... \\ in the path

## __office_vpn.ps1__  
Create a VPN Connection on Windows 10 and installed a self sign certifcate to make it work.  That required administrator.  So it will run as administrator if it can to make sure the cert is installed.  Is is specifically configured to use a PFSense Firewall VPN connection (IKE with split tunnel).  https://docs.netgate.com/pfsense/en/latest/vpn/ipsec/configuring-an-ipsec-remote-access-mobile-vpn-using-ikev2-with-eap-mschapv2.html 

- [ ] It does not have checking to see if the cert is already installed.  
- [ ] It is not generalized so it can be easily modified.
- [ ] Should make it VpnConnectionTriggerApplication for dynamic connection

## __post-update-run.ps1__
// this currently not working.  trying to run from the Task Scheduler as System now...
I'm old school with a new gen approach. I have SSD as my C drive and I have traditional spin hard drives as my Downloads and Public Drive partitions (I keep tons of pictures & videos there).  This script is used during boot running within Task Scheduler (run As Startup), so that it can fixup and remount my external drives.  A lot of people don't know about mount points, and Microsoft doesn't talk about them.  (See Junctions below).  Because I'm messing with the restricted security directory of Public, it needs to run before Explorer or other processes that created locks on the \users\Public directory structure, which is why it needs to run as part of at Startup.

>junction64.exe c:\Users\Public
>
>Junction v1.07 - Creates and lists directory links
>Copyright (C) 2005-2016 Mark Russinovich
>Sysinternals - www.sysinternals.com
>
>c:\Users\Public: MOUNT POINT
>   Print Name     : \??\Volume{2f5b6ca6-50d6-4fbd-a874-82dd838461a3}\
>   Substitute Name: Volume{2f5b6ca6-50d6-4fbd-a874-82dd838461a3}\ 


### precommit.cmd
This works as part of above.  Using https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-enable-custom-actions#custom-action-script-locations-and-examples precommit custom actions, I dismount the drives using a old school cmd which inputs to diskpart

## __AdjustPrivilege.ps1__
This is from Ondřej Ševeček (https://www.sevecek.com/EnglishPages/default.aspx)
Backup privilege (SeBackupPrivilege),can be enabled for a process or thread it automatically gives the generic read permission to any resource operation.  I will use it for PST scan scripts without requiring a change in user permissions to directories.


## ConnectO365Services.ps1
Connect to O365 Services with MFA support
Source https://o365reports.com/2019/10/05/connect-all-office-365-services-powershell/?src=github


## CheckUser365.ps1
This is a complex script which has grown over time.  It was started by Robert Luck 
- https://gallery.technet.microsoft.com/scriptcenter/Export-Office-365-Users-81747c73
- https://o365reports.com/2019/05/09/export-office-365-users-mfa-status-csv/
- https://github.com/michelvoillery/The-Code-Repository/blob/5d7b64aa4eed433dfa506e7d4289afa823b54ff9/Scripts/Export%20Office%20365%20Users%20MFA%20Status.md
And I have added a lot into... it is a WIP.
- Queries MSOL for users and builds a CSV with the following attributes:
DisplayName, UserPrincipalName, MFAStatus, AllMFAMethods, MFAPhone, MFAEmail, MSOL LicenseStatus, 
Azure SignInStatus, Skype SIPLocation, TeamsState, TeamsFederated,  TeamsVoice, Exchange Online Status, Group membership for Licensing, PrimarySMTP,
IsAdmin, AdminRoles, ExtraLicense, Title, Manager, Type, Source, EmployeeNumber, CreateType, PhoneNumber
- List of Teams And the admins of those teams with attributes of 
DisplayName, ManagedByDetails, Notes, GroupMemberCount, GroupExternalMemberCount, AllowAddGuests, ExpirationTime, WhenCreated 

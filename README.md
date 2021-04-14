# Win10 and Office 365 Support Scripts
Misc Scripts use on Windows 10 computersand others for Office 365 to do some PC Pro support tasks

## CheckUser365.ps1
 
`-Summary`            will give a summary of Licenses, Groups Mailboxes (if IncludeExchange is used)
`-IncludeExchange`    Pull mailbox information
`-CheckFor`           Allow to search for a user or part of a user  ..  -CheckFor Darren
                      This also makes it just displays the results instead of putting them into a CSV
`-ShowMFA`            Displays the MFA authenications details
`-ShowAllColumns`     Pull everything... all columns
                      If none of the filters are applied it will pull all the objects
`-IncludeTeams`       give information about TeamsUpgradePolicy and ExternalAccessPolicy, but it is a very slow process
`-EnabledOnly`
`-DisabledOnly`
`-AdminOnly`
`-LicensedUserOnly`
`-ConditionalAccessOnly`


This is a complex script which has grown over time.  It was started by Robert Luck 
- https://gallery.technet.microsoft.com/scriptcenter/Export-Office-365-Users-81747c73
- https://o365reports.com/2019/05/09/export-office-365-users-mfa-status-csv/

And I have added a lot into... it is a WIP.
- Queries MSOL for users and builds a CSV with the following attributes:
DisplayName, UserPrincipalName, MFAStatus, AllMFAMethods, MFAPhone, MFAEmail, MSOL LicenseStatus, 
Azure SignInStatus, Skype SIPLocation, TeamsState, TeamsFederated,  TeamsVoice, Exchange Online Status, Group membership for Licensing, PrimarySMTP,
IsAdmin, AdminRoles, ExtraLicense, Title, Manager, Type, Source, EmployeeNumber, CreateType, PhoneNumber
- List of Teams And the admins of those teams with attributes of 
DisplayName, ManagedByDetails, Notes, GroupMemberCount, GroupExternalMemberCount, AllowAddGuests, ExpirationTime, WhenCreated

| DisplayName | UserPrincipalName | MFAStatus | ActivationStatus | DefaultMFAMethod | AllMFAMethods | MFAPhone | MFAEmail | LicenseStatus | SignInStatus | SIPLocation | TeamsState | TeamsFederated | TeamsVoice | ExOStatus | ExODetails | E5Licensed | SpecialGroups | PrimarySMTP | IsAdmin | AdminRoles | ExtraLicense | Title | Manager | Type | Source | EmployeeNumber | CreateType | PhoneNumber | GroupCount |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Cam, Jim | Jim.Cam@myCompany.com | Enabled via Conditional Access | Yes | PhoneAppNotification | PhoneAppOTP,PhoneAppNotification | - | - | TRUE | Allowed | TeamsOnly |  |  | Microsoft365AudioConferencing(Success), Microsoft365PhoneSystem(Success) | Online | UserMailbox/UserMailbox | TRUE |  | jim.cam@myCompany.com | - | - | InTune365(PendingActivation), FlowViral(Success), PowerAppsViral2(Success), FlowViral(Success) | Front Line Support | James, Dave | Member | WindowsAD | 104xxx |  | 555-555-1212 | 62 |
| Lost Faxes  | FaxLost@myCompany.onmicrosoft.com | Enabled via Conditional Access | No | - | - | - | - | FALSE | Allowed |  |  |  |  | Nobox |  | - | - | FaxLost@myCompany.onmicrosoft.com | - | - |  |  | - | Member | WindowsAD |  |  |  | 0 |
| Customer Excellence | CExcellence@myCompany.onmicrosoft.com | Enabled via Conditional Access | No | - | - | - | - | FALSE | Denied |  |  |  |  | Shared Mailbox | UserMailbox/SharedMailbox | - | - | cexcellence@myCompany.com | - | - |  |  | - | Member | WindowsAD |  |  |  | 0 |
| Meet 123 West Room (Seats 7) | Meet123W@myCompany.com | Enabled via Conditional Access | No | - | - | - | - | TRUE | Denied |  |  |  | Microsoft365PhoneSystem(Success), Microsoft365AudioConferencing(Success) | Room Mailbox | UserMailbox/RoomMailbox | - | - | meet123w@myCompany.com | - | - |  |  | - | Member | WindowsAD |  |  | 555-555-1233 | 2|


## __GuestHistory.ps1__
 WIP - Purge old Guest accounts by running this perodically to get the list of accounts, keep it for future runs, then after it pasts the cutoff age, remove the acount
also remove accountw which have not accepting their invition and are older then 30 days credit 
 to https://github.com/chadmcox/Azure_Active_Directory_Scripts/tree/master/Guests

    Check age of State file so if there is more than 30 days between runs, then warn about that
    TODO Add a ClearHistory Switch to Reset state
    TODO Send E-mail notifications to users when we have removed them from the system
    TODO Send Grace period Warning messages that their account will be deleted
    TODO Send Grace period warning summary alerts to delegates for invited people
 

## __PSTMoveFromOneDrive.ps1__
 Designed to move PST files outside of OneDrive directory space at logon time.
 
 Put it in a directory. Open powershell.  And just run the script… no parameters works… 

If you want to see everything, but don’t do anything use these parameters
 `   .\PST-fixup.ps1 -Verbose -WhatIf -Debug` 

There is a 20 second pause at the end and it runs minimized for early testing (it could run hidden, not sure if that would make it start faster)

You can use 
`   .\PST-fixup.ps1  -install`
To hook it in to run after right after logon.  (if you don’t have Outlook autostarting, then it will work, otherwise you might see errors for “in use”)
`   .\PST-fixup.ps1  -remove`
To unhook it
The idea wasto push the file onto your computers and this will hook for all users and run for anyone..   if it run hidden, then it would not be noticed by people, but we should unhook it after a while.

There where some times when it could move the files from under Outlook but it would appear buggy to the users, so it will check to see if Outlook is running and skip messing with the Open/mounted PST files.

There maybe a issue with the way files are detected as 'inside' OneDrive space
 
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



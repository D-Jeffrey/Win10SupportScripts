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




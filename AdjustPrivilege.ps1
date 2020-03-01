#
# To call this and grant BackupPriviledge use this 
#Implement-AdjustPrivilege 
#[Sevecek.Win32API.Privileges]::AdjustPrivilege('SeBackupPrivilege', $true)
#
#
# You must be member of local Administrators group usually or have the right granted explicitly
#
#------------------------------------------------


function Implement-AdjustPrivilege ()
{
  $win32api = @'

using System;
using System.Runtime.InteropServices;

namespace Sevecek.Win32API
{
  [StructLayout(LayoutKind.Sequential)]
  public struct LUID
  {
    public UInt32 LowPart;
    public Int32 HighPart;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct LUID_AND_ATTRIBUTES
  {
    public LUID Luid;
    public UInt32 Attributes;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct TOKEN_PRIVILEGES
  {
    public UInt32 PrivilegeCount;
    public LUID Luid;
    public UInt32 Attributes;
  }

  public class Privileges
  {
    public const UInt32 DELETE = 0x00010000;
    public const UInt32 READ_CONTROL = 0x00020000;
    public const UInt32 WRITE_DAC = 0x00040000;
    public const UInt32 WRITE_OWNER = 0x00080000;
    public const UInt32 SYNCHRONIZE = 0x00100000;
    public const UInt32 STANDARD_RIGHTS_ALL = (
                                                READ_CONTROL |
                                                WRITE_OWNER |
                                                WRITE_DAC |
                                                DELETE |
                                                SYNCHRONIZE
                                            );
    public const UInt32 STANDARD_RIGHTS_REQUIRED = 0x000F0000u;
    public const UInt32 STANDARD_RIGHTS_READ = 0x00020000u;

    public const UInt32 SE_PRIVILEGE_ENABLED_BY_DEFAULT = 0x00000001u;
    public const UInt32 SE_PRIVILEGE_ENABLED = 0x00000002u;
    public const UInt32 SE_PRIVILEGE_REMOVED = 0x00000004u;
    public const UInt32 SE_PRIVILEGE_USED_FOR_ACCESS = 0x80000000u;

    public const UInt32 TOKEN_QUERY = 0x00000008;
    public const UInt32 TOKEN_ADJUST_PRIVILEGES = 0x00000020;

    public const UInt32 TOKEN_ASSIGN_PRIMARY = 0x00000001u;
    public const UInt32 TOKEN_DUPLICATE = 0x00000002u;
    public const UInt32 TOKEN_IMPERSONATE = 0x00000004u;
    public const UInt32 TOKEN_QUERY_SOURCE = 0x00000010u;
    public const UInt32 TOKEN_ADJUST_GROUPS = 0x00000040u;
    public const UInt32 TOKEN_ADJUST_DEFAULT = 0x00000080u;
    public const UInt32 TOKEN_ADJUST_SESSIONID = 0x00000100u;
    public const UInt32 TOKEN_READ = (
                                      STANDARD_RIGHTS_READ |
                                      TOKEN_QUERY
                                   );
    public const UInt32 TOKEN_ALL_ACCESS = (
                                            STANDARD_RIGHTS_REQUIRED |
                                            TOKEN_ASSIGN_PRIMARY |
                                            TOKEN_DUPLICATE |
                                            TOKEN_IMPERSONATE |
                                            TOKEN_QUERY |
                                            TOKEN_QUERY_SOURCE |
                                            TOKEN_ADJUST_PRIVILEGES |
                                            TOKEN_ADJUST_GROUPS |
                                            TOKEN_ADJUST_DEFAULT |
                                            TOKEN_ADJUST_SESSIONID
                                         );

    [DllImport("kernel32.dll", SetLastError = true, ExactSpelling = true)]
    public static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", SetLastError = true, ExactSpelling = true)]
    public static extern IntPtr GetCurrentThread();

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, UInt32 BufferLengthInBytes, IntPtr PreviousStateNull, IntPtr ReturnLengthInBytesNull);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, UInt32 DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool OpenThreadToken(IntPtr ThreadHandle, UInt32 DesiredAccess, bool OpenAsSelf, out IntPtr TokenHandle);

    [DllImport("ntdll.dll", EntryPoint = "RtlAdjustPrivilege")]
    public static extern int RtlAdjustPrivilege(
                UInt32 Privilege,
                bool Enable,
                bool CurrentThread,
                ref bool Enabled
                );

    [DllImport("Kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr handle);

    //
    //

    private static LUID LookupPrivilege(string privilegeName)
    {
      LUID privilegeValue = new LUID();
      
      bool res = LookupPrivilegeValue(null, privilegeName, out privilegeValue);

      if (!res)
      {
        throw new Exception("Error: LookupPrivilegeValue()");
      }

      return privilegeValue;
    }

    //
    //

    public static void AdjustPrivilege(string privilegeName, bool enable)
    {
      IntPtr accessToken = IntPtr.Zero;
      bool res = false;

      try
      {
        LUID privilegeValue = LookupPrivilege(privilegeName);

        res = OpenThreadToken(GetCurrentThread(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, false, out accessToken);
        
        if (!res)
        {
          res = OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out accessToken);

          if (!res)
          {
            throw new Exception("Error: OpenProcessToken()");
          }
        }

        TOKEN_PRIVILEGES tokenPrivileges = new TOKEN_PRIVILEGES();
        tokenPrivileges.PrivilegeCount = 1;
        tokenPrivileges.Luid = privilegeValue;

        if (enable)
        {
          tokenPrivileges.Attributes = SE_PRIVILEGE_ENABLED;
        }
        else
        {
          tokenPrivileges.Attributes = 0;
        }

        res = AdjustTokenPrivileges(accessToken, false, ref tokenPrivileges, (uint)System.Runtime.InteropServices.Marshal.SizeOf(tokenPrivileges), IntPtr.Zero, IntPtr.Zero);
        
        if (!res)
        {
          throw new Exception("Error: AdjustTokenPrivileges()");
        }
      }

      finally
      {
        if (accessToken != IntPtr.Zero)
        {
          CloseHandle(accessToken);
          accessToken = IntPtr.Zero;
        }
      }
    }
  }
}

'@

  if ([object]::Equals(('Sevecek.Win32API.Privileges' -as [type]), $null)) {

    Add-Type -TypeDefinition $win32api
  }
}


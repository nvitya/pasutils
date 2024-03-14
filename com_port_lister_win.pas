(*-----------------------------------------------------------------------------
  This file is a part of the PASUTILS project: https://github.com/nvitya/pasutils
  Copyright (c) 2023 Viktor Nagy, nvitya

  This software is provided 'as-is', without any express or implied warranty.
  In no event will the authors be held liable for any damages arising from
  the use of this software. Permission is granted to anyone to use this
  software for any purpose, including commercial applications, and to alter
  it and redistribute it freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software in
     a product, an acknowledgment in the product documentation would be
     appreciated but is not required.

  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.

  3. This notice may not be removed or altered from any source distribution.
  --------------------------------------------------------------------------- */
   file:     com_port_lister.pas
   brief:    Enumerating connected COM ports with their properties like USB serial number or VID:PID
   date:     2024-03-13
   authors:  nvitya
   notes:
     The algorythms were taken from the list_ports module of the Python 'serial' package.
     Only Linux and Windows are supported
*)

unit com_port_lister_win;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, windows;

//-----------------------------------------------------------------------------
// Minimal Windows Setup API DLL bindings for com port listings

const
  DIREG_DEV  = $00000001; // Open/Create/Delete device key
  DIREG_DRV  = $00000002; // Open/Create/Delete driver key
  DIREG_BOTH = $00000004; // Delete both driver and Device key

  DIGCF_PRESENT         = $00000002;

  DICS_FLAG_GLOBAL         = $00000001;  // make change in all hardware profiles
  DICS_FLAG_CONFIGSPECIFIC = $00000002;  // make change in specified profile only
  DICS_FLAG_CONFIGGENERAL  = $00000004;  // 1 or more hardware profile-specific

  SPDRP_DEVICEDESC                  = $00000000; // DeviceDesc (R/W)
  SPDRP_HARDWAREID                  = $00000001; // HardwareID (R/W)
  SPDRP_MFG                         = $0000000B; // Mfg (R/W)
  SPDRP_FRIENDLYNAME                = $0000000C; // FriendlyName (R/W)


type
  HDEVINFO = Pointer;

  SP_DEVINFO_DATA = packed record
    cbSize: DWORD;
    ClassGuid: TGUID;
    DevInst: DWORD; // DEVINST handle
    Reserved: ULONG_PTR;
  end;

  pSP_DEVINFO_DATA = ^SP_DEVINFO_DATA;

//------------------------------------

function SetupDiClassGuidsFromNameA(const ClassName: PChar; ClassGuidList: PGUID;
  ClassGuidListSize: DWORD; var RequiredSize: DWORD): LongBool; stdcall; external 'SetupApi.dll';

function SetupDiGetClassDevsA(ClassGuid: PGUID; const Enumerator: PAnsiChar;
  hwndParent: HWND; Flags: DWORD): HDEVINFO; stdcall; external 'SetupApi.dll';

function SetupDiEnumDeviceInfo(DeviceInfoSet: HDEVINFO;
  MemberIndex: DWORD; DeviceInfoData: pSP_DEVINFO_DATA): LongBool; stdcall; external 'SetupApi.dll';

function SetupDiOpenDevRegKey(DeviceInfoSet: HDEVINFO;
  DeviceInfoData: pSP_DEVINFO_DATA; Scope, HwProfile, KeyType: DWORD;
  samDesired: REGSAM): HKEY; stdcall; external 'SetupApi.dll';

function SetupDiDestroyDeviceInfoList(DeviceInfoSet: HDEVINFO): LongBool; stdcall; external 'SetupApi.dll';

function SetupDiGetDeviceRegistryPropertyA(DeviceInfoSet: HDEVINFO;
  DeviceInfoData: pSP_DEVINFO_DATA; Property_: DWORD;
  PropertyRegDataType : PDWORD; PropertyBuffer: PBYTE; PropertyBufferSize: DWORD;
  var RequiredSize: DWORD): LongBool; stdcall; external 'SetupApi.dll';

function SetupDiGetDeviceInstanceIdA(DeviceInfoSet: HDEVINFO;
  DeviceInfoData: pSP_DEVINFO_DATA; DeviceInstanceId: PAnsiChar;
  DeviceInstanceIdSize: DWORD; var RequiredSize: DWORD): LongBool; stdcall; external 'SetupApi.dll';

//--------

function CM_Get_Parent(pdnDevInst : PDWORD; dnDevInst : DWORD;
  ulFlags : ULONG) : LONG; stdcall; external 'Cfgmgr32.dll';

function CM_Get_Device_IDA(dnDevInst : DWORD;
  buffer : PBYTE; BufferLen : ULONG; ulFlags : ULONG) : LONG; stdcall; external 'Cfgmgr32.dll';

function CM_MapCrToWin32Err(CmReturnCode : DWORD;
  DefaultErr : DWORD) : DWORD; stdcall; external 'Cfgmgr32.dll';

implementation

end.


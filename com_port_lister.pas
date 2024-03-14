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

unit com_port_lister;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils
  {$ifdef WINDOWS}
  ,windows, registry, com_port_lister_win
  {$endif}
  ;

type

  { TComPortListItem }

  TComPortListItem = class
  public
    devstr         : string;
    serial_number  : string;
    usb_vid        : uint16;
    usb_pid        : uint16;
    manufacturer   : string;  // usually "Microsoft" because it comes from the driver
    location       : string;  // might be empty
    description    : string;

    // Linux only
    subsystem      : string;
    num_interfaces : integer;
    interfacename  : string;

    // Windows only
    interfacenum   : integer;

    constructor Create(adevstr : string);

    {$ifdef WINDOWS}
      procedure LoadProperties(g_hdi : HDEVINFO; pdevinfo : pSP_DEVINFO_DATA);
    {$else}
      procedure LoadProperties;
    {$endif}
  end;

  { TComPortLister }

  TComPortLister = class
  public
    items : array of TComPortListItem;

    constructor Create;
    destructor Destroy; override;
    procedure Clear;

    function CollectComPorts : integer;

  public
    {$ifdef WINDOWS}

    {$else}
      function CollectComPattern(apattern : string) : integer;
    {$endif}
  end;

var
  comportlister : TComPortLister;

implementation

uses
  strutils;

function Hex2DecDef(astr : string; adefvalue : integer) : integer;
begin
  if astr = '' then EXIT(adefvalue);
  try
    result := Hex2Dec(astr);
  except
    result := adefvalue;
  end;
end;

{ TComPortListItem }

constructor TComPortListItem.Create(adevstr : string);
begin
  devstr := adevstr;
  serial_number := '';
  usb_vid := 0;
  usb_pid := 0;
  manufacturer := '';
  location := '';
  interfacenum := 0;
  interfacename := '';
  num_interfaces := 0;
  subsystem := '';
  description := '';
end;

{ TComPortLister }

constructor TComPortLister.Create;
begin
  items := [];
end;

destructor TComPortLister.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TComPortLister.Clear;
var
  cli : TComPortListItem;
begin
  for cli in items do cli.free;
  items := [];
end;

{$ifdef WINDOWS}

procedure TComPortListItem.LoadProperties(g_hdi: HDEVINFO; pdevinfo: pSP_DEVINFO_DATA);
var
  s : ansistring = '';
  rlen : DWORD;
  hwid : ansistring = '';
  sarr : array of string;
  devinst, new_devinst : DWORD;
  depth : integer;
  r    : LONG;
begin
  // hardware ID
  SetLength(s, 256);
  rlen := length(s);
  // try to get ID that includes serial number
  if SetupDiGetDeviceInstanceIdA(g_hdi, pdevinfo, @s[1], length(s) - 1, rlen) then
  begin
    hwid := PChar(@s[1]);
  end
  else
  begin
    // fall back to more generic hardware ID if that would fail
    if SetupDiGetDeviceRegistryPropertyA(g_hdi, pdevinfo,
            SPDRP_HARDWAREID, nil, @s[1], length(s) - 1, rlen) then
    begin
      hwid := PChar(@s[1]);
    end;
  end;

  if hwid <> '' then
  begin
    // writeln(devstr,': ', hwid);
  end;

  // hwid samples:
  //COM4 : USB\VID_6666&PID_9930&MI_02\8&2536B8EF&0&0002
  //COM5 : USB\VID_BABE&PID_BEE6&MI_00\8&267AD337&0&0000
  //COM6 : USB\VID_BABE&PID_BEE6&MI_02\8&267AD337&0&0002
  //COM7 : FTDIBUS\VID_0403+PID_6001+A50285BIA\0000

  if hwid.StartsWith('USB') then
  begin
    sarr := hwid.split('\');
    if length(sarr) > 1 then
    begin
      //serial_number := copy(sarr[1], 19, length(sarr[1]));
      usb_vid := Hex2DecDef(copy(sarr[1],  5, 4), 0);
      usb_pid := Hex2DecDef(copy(sarr[1], 14, 4), 0);
      interfacenum := StrToIntDef(copy(sarr[1], 22, 2), 0);
    end;
    if length(sarr) > 2 then
    begin
      sarr := sarr[2].Split('&');
      if length(sarr) > 1 then
      begin
        serial_number := sarr[1];
        // This serial number might be a pseudo serial number for composite devices
        depth := 0;
        devinst := pdevinfo^.devinst;
        repeat
          r := CM_Get_Parent(@new_devinst, devinst, 0);
          if r = 0 then
          begin
            SetLength(s, 256);
            r := CM_Get_Device_IDA(new_devinst, @s[1], length(s) - 1, 0);
            if r = 0 then
            begin
              //writeln('parent-', depth,': ',hwid);
              hwid := PChar(@s[1]);
              // check if it contains the same VID + PID
              if (hwid.IndexOf('VID_'+IntToHex(usb_vid, 4)) >= 0)
                 and (hwid.IndexOf('PID_'+IntToHex(usb_pid, 4)) >= 0) then
              begin
                // sample: "USB\VID_6666&PID_9930\FA6A1395"
                sarr := hwid.split('\');
                if length(sarr) > 2 then serial_number := sarr[2];
              end;
              devinst := new_devinst;
              Inc(depth);
            end;
          end;
        until (r <> 0) or (depth > 5);

        //serial_number := GetParentSerialNumber(pdevinfo^.DevInst); // uses the previously set usb_vid + usb_pid
      end;
    end;
  end
  else if hwid.StartsWith('FTDIBUS') then
  begin
    sarr := hwid.split('\');
    if length(sarr) > 1 then
    begin
      serial_number := copy(sarr[1], 19, length(sarr[1]));
      usb_vid := Hex2DecDef(copy(sarr[1],  5, 4), 0);
      usb_pid := Hex2DecDef(copy(sarr[1], 14, 4), 0);
    end;
    // location info, interfacenum is hidden by the FTDI driver
  end;

  // friendly name
  SetLength(s, 256);
  rlen := length(s);
  if SetupDiGetDeviceRegistryPropertyA(
        g_hdi, pdevinfo, SPDRP_FRIENDLYNAME, nil, @s[1], length(s)-1, rlen) then
  begin
    description := PChar(@s[1]);
  end;

  // manufacturer
  rlen := length(s);
  if SetupDiGetDeviceRegistryPropertyA(
        g_hdi, pdevinfo, SPDRP_MFG, nil, @s[1], length(s)-1, rlen) then
  begin
    manufacturer := PChar(@s[1]);
  end;
end;

function TComPortLister.CollectComPorts : integer;
var
  n : integer;
  RequiredSize  : Cardinal = 0;
  GUIDSize      : DWORD;
  guid_list     : array[0..1] of TGUID;

  g_hdi         : HDEVINFO;
  devinfo       : SP_DEVINFO_DATA;
  MemberIndex   : Cardinal;

  regkey        : Hkey;
  port_name     : ansistring = '';
  port_name_len : ULONG;

  cli : TComPortListItem;

begin
  result := 0;
  Clear;

  GUIDSize := 1;
  if not SetupDiClassGuidsFromNameA('Ports', @guid_list[0], GUIDSize, RequiredSize)
  then
      EXIT;

  GUIDSize := 1;
  if not SetupDiClassGuidsFromNameA('Modem', @guid_list[1], GUIDSize, RequiredSize)
  then
      EXIT;

  for n := 0 to 1 do
  begin
    g_hdi := SetupDiGetClassDevsA(@guid_list[n], Nil, 0, DIGCF_PRESENT);
    if THANDLE(g_hdi) <> Invalid_Handle_Value then
    begin
      devinfo.DevInst := 0; // to avoid fpc hint
      FillChar(devinfo, SizeOf(devinfo), 0);
      devinfo.cbSize := SizeOf(devinfo);
      MemberIndex := 0;
      while SetupDiEnumDeviceInfo(g_hdi, MemberIndex, @devinfo) do
      begin
        // get the real com port name
        regkey := SetupDiOpenDevRegKey(g_hdi, @devinfo, DICS_FLAG_GLOBAL, 0,
            DIREG_DEV,  // DIREG_DRV for SW info
            KEY_READ);

        SetLength(port_name, 252);
        port_name_len := length(port_name);
        RegQueryValueEx(regkey, 'PortName', nil, nil, @port_name[1], @port_name_len);
        RegCloseKey(regkey);
        SetLength(port_name, port_name_len);

        // unfortunately does this method also include parallel ports.
        // we could check for names starting with COM or just exclude LPT
        // and hope that other "unknown" names are serial ports...
        if not port_name.StartsWith('LPT') then
        begin
          cli := TComPortListItem.Create(port_name);
          cli.LoadProperties(g_hdi, @devinfo);
          insert(cli, items, length(items));
          result += 1;
        end;

        Inc(MemberIndex);
      end;
      SetupDiDestroyDeviceInfoList(g_hdi);
    end;
  end;
end;

{$else}

// linux only helpers

function RealPath(apath : string) : string;
var
  sarr : array of string;
  s : string;
  newpath : string;
  rpath : RawByteString;
begin
  result := '';
  sarr := apath.split('/');
  for s in sarr do
  begin
    if s <> '' then
    begin
      newpath := result + '/' + s;
      if FileGetSymLinkTarget(newpath, rpath) then
      begin
        result := ExpandFileName(result + '/' + rpath)
      end
      else
      begin
        result := ExpandFileName(newpath);
      end;
    end;
  end;
end;

function ReadDevValue(apath : string) : string;
begin
  if not FileExists(apath) then EXIT('');
  result := trim(GetFileAsString(apath));
end;

procedure TComPortListItem.LoadProperties;
var
  devname : string;
  full_ttydev_path : string;
  usb_dev_path : string;
  usb_if_path  : string;
  if_path_end  : string;
  i : integer;
begin
  devname := ExtractFileName(devstr);

  full_ttydev_path := '/sys/class/tty/'+devname+'/device';
  subsystem := ExtractFileName(RealPath(full_ttydev_path + '/subsystem'));

  if subsystem = 'platform'  // non-present internal serial port
  then
      EXIT;

  usb_if_path  := RealPath(full_ttydev_path);
  if_path_end  := ExtractFileName(usb_if_path);
  if if_path_end.StartsWith('tty') then // for FTDI / usb-serial
  begin
    // sample: /sys/devices/pci0000:00/0000:00:08.1/0000:09:00.3/usb3/3-2/3-2.4/3-2.4:1.1/ttyUSB1
    usb_if_path := ExtractFileDir(usb_if_path); // one back
  end;
  usb_dev_path := ExtractFileDir(usb_if_path);

  if (subsystem <> 'usb') and (subsystem <> 'usb-serial') then
  begin
    usb_dev_path := ''; // unknown
  end;

  if usb_dev_path <> '' then
  begin
    try
      num_interfaces := StrToIntDef(ReadDevValue(usb_dev_path+'/bNumInterfaces'), 0);
    except
      num_interfaces := 1;
    end;

    location := ExtractFileName(usb_if_path);
    i := location.LastIndexOf('.');
    interfacenum := StrToIntDef(location.Substring(i + 1, 2), 0);

    usb_vid   := Hex2DecDef(ReadDevValue(usb_dev_path+'/idVendor'), 0);
    usb_pid   := Hex2DecDef(ReadDevValue(usb_dev_path+'/idProduct'), 0);
    serial_number := ReadDevValue(usb_dev_path+'/serial');
    description   := ReadDevValue(usb_dev_path+'/product');
    manufacturer  := ReadDevValue(usb_dev_path+'/manufacturer');
    try
      interfacename := ReadDevValue(usb_if_path+'/interface');
    except
      interfacename := '';
    end;
  end;
end;

function TComPortLister.CollectComPorts : integer;
begin
  result := 0;

  Clear;
  result += CollectComPattern('/dev/ttyS*');     // built-in serial ports
  result += CollectComPattern('/dev/ttyUSB*');   // usb-serial with own driver
  result += CollectComPattern('/dev/ttyXRUSB*'); // xr-usb-serial port exar (DELL Edge 3001)
  result += CollectComPattern('/dev/ttyACM*');   // usb-serial with CDC-ACM profile
  result += CollectComPattern('/dev/ttyAMA*');   // ARM internal port (raspi)
  result += CollectComPattern('/dev/rfcomm*');   // BT serial devices
  result += CollectComPattern('/dev/ttyAP*');    // Advantech multi-port serial controllers
end;

function TComPortLister.CollectComPattern(apattern : string) : integer;
var
  srec : TSearchRec;
  bok : boolean;
  cli : TComPortListItem;
  inspos : integer;
begin
  result := 0;
  bok := (0 = FindFirst(apattern, faAnyFile, srec));
  if bok then
  begin
    while bok do
    begin
      cli := TComPortListItem.Create('/dev/'+srec.Name);
      cli.LoadProperties;
      if cli.subsystem = 'platform' then // non-present internal serial port
      begin
        cli.Free;
      end
      else
      begin
        // add to items sorted
        inspos := 0;
        while (inspos < length(items)) and (items[inspos].devstr < cli.devstr) do
        begin
          Inc(inspos);
        end;
        insert(cli, items, inspos);
        result += 1;
      end;

      bok := (0 = FindNext(srec));
    end;
    FindClose(srec);
  end;
end;

{$endif}  // linux

initialization
begin
  comportlister := TComPortLister.Create;
end;

end.


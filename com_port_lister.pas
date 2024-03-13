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
  Classes, SysUtils;

type

  { TComPortListItem }

  TComPortListItem = class
  public
    devstr         : string;
    subsystem      : string;
    serial_number  : string;
    usb_vid        : uint16;
    usb_pid        : uint16;
    num_interfaces : integer;

    manufacturer   : string;
    product        : string;
    interfacename  : string;
    usb_interface_path : string;

    constructor Create(adevstr : string);
    procedure LoadProperties;
  end;

  { TComPortLister }

  TComPortLister = class
  public
    items : array of TComPortListItem;

    constructor Create;
    destructor Destroy; override;

    function CollectComPorts : integer;
    function CollectComPattern(apattern : string) : integer;

    procedure Clear;

  end;

var
  comportlister : TComPortLister;

implementation

uses
  strutils;

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

function Hex2DecDef(astr : string; adefvalue : integer) : integer;
begin
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
  product := '';
  interfacename := '';
  num_interfaces := 0;
  usb_interface_path := '';
  subsystem := '';
end;

procedure TComPortListItem.LoadProperties;
var
  devname : string;
  full_dev_path : string;
  dev_symlink_target : string;
  usb_dev_path : string;
begin
  devname := ExtractFileName(devstr);
  full_dev_path := '/sys/class/tty/'+devname+'/device';

  dev_symlink_target := RealPath(full_dev_path);
  subsystem := ExtractFileName(RealPath(full_dev_path + '/subsystem'));

  usb_dev_path := ExtractFileDir(dev_symlink_target);

  if 'usb' = subsystem             then  usb_interface_path := usb_dev_path
  else if 'usb-serial' = subsystem then  usb_interface_path := ExtractFileDir(usb_dev_path)
  else                                   usb_interface_path := '';

  if usb_interface_path <> '' then
  begin
    try
      num_interfaces := StrToIntDef(ReadDevValue(usb_dev_path+'/bNumInterfaces'), 0);
    except
      num_interfaces := 1;
    end;
    usb_vid   := Hex2DecDef(ReadDevValue(usb_dev_path+'/idVendor'), 0);
    usb_pid   := Hex2DecDef(ReadDevValue(usb_dev_path+'/idProduct'), 0);
    serial_number := ReadDevValue(usb_dev_path+'/serial');
    product   := ReadDevValue(usb_dev_path+'/product');
    manufacturer  := ReadDevValue(usb_dev_path+'/manufacturer');
    try
      interfacename := ReadDevValue(usb_dev_path+'/interface');
    except
      interfacename := '';
    end;
  end;
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
begin
  result := 0;
  bok := (0 = FindFirst(apattern, faAnyFile, srec));
  if bok then
  begin
    while bok do
    begin
      cli := TComPortListItem.Create(srec.Name);
      cli.LoadProperties;
      if cli.subsystem = 'platform' then // non-present internal serial port
      begin
        cli.Free;
      end
      else
      begin
        insert(cli, items, length(items));
        result += 1;
      end;

      bok := (0 = FindNext(srec));
    end;
    FindClose(srec);
  end;
end;

procedure TComPortLister.Clear;
var
  cli : TComPortListItem;
begin
  for cli in items do cli.free;
  items := [];
end;

initialization
begin
  comportlister := TComPortLister.Create;
end;

end.


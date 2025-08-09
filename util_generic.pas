(*-----------------------------------------------------------------------------
  This file is a part of the PASUTILS project: https://github.com/nvitya/pasutils
  Copyright (c) 2022 Viktor Nagy, nvitya

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
   file:     util_generic.pas
   brief:    Generic utilities for FreePascal
   date:     2025-08-09
   authors:  nvitya
*)
unit util_generic;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

function ReadFileToStr(const afilename : string) : ansistring;
function ReadFileToBytes(const afilename : string) : TBytes;
procedure WriteStrToFile(const afilename, afiledata : string);
procedure WriteBytesToFile(const afilename : string; afiledata : TBytes);
procedure AppendStrToFile(const afilename, afiledata : string);
procedure OutVarInit(out v); // dummy proc for avoid false FPC hints

function GetLoggedInUserName : string;

procedure InitExceptionsLineInfo;   // should be called very early, required for FPC RLT bug workaround
function GetLastExceptionCallStack(stopfuncname : string) : string;

implementation

uses
  {$PUSH} {$WARNINGS OFF}
    lineinfo
  {$POP}
  {$ifdef WINDOWS}
    ,windows
  {$endif}
  ;

{$PUSH} {$WARNINGS OFF} {$HINTS OFF}
function GetShortLineInfo(const addr : pointer; out funcname : shortstring) : string;
var
  source : shortstring;
  line : integer;
begin
  result := '';
  funcname := '';
  if (not GetLineInfo(longword(addr), funcname, source, line)) or (funcname = '') then
  begin
    EXIT;
  end;

  result := funcname+'@'+source + '(' + IntToStr(line) + ')';
end;
{$POP}

function GetLastExceptionCallStack(stopfuncname : string) : string;
var
  olddir : string;
  funcname : shortstring;
  i : Integer;
  Frames : PPointer;
  s : string;
begin
  // FPC RTL BUG: no line info when the current directory is different than the EXE directory !

  olddir := GetCurrentDir;
  SetCurrentDir(ExtractFilePath(ParamStr(0)));

  result := '';

  s := GetShortLineInfo(ExceptAddr, funcname);
  if funcname <> stopfuncname then
  begin
    result := s;

    Frames := ExceptFrames;
    for i := 0 to ExceptFrameCount - 1 do
    begin
      s := GetShortLineInfo(Frames[i], funcname);
      if funcname = stopfuncname then
      begin
        break;
      end;

      if result <> '' then result := result + ' <- ';
      result := result + s;
    end;
  end;

  SetCurrentDir(olddir);
end;

procedure InitExceptionsLineInfo; // should be called very early
var
  s : string;
  fn : shortstring;
begin
  s := GetShortLineInfo(@GetLastExceptionCallStack, fn);  // loads and caches exe info
  if s <> '' then
  begin
    // do nothing, just ignores warning
  end;
end;

procedure AppendStrToFile(const afilename, afiledata : string);
var
  f : File;
begin
  if length(afiledata) <= 0 then EXIT;

  Assign(f, afilename);
  if not FileExists(afilename) then
  begin
    Rewrite(f, 1);
  end
  else
  begin
    Reset(f, 1);
    Seek(f, FileSize(f));
  end;
  BlockWrite(f, afiledata[1], length(afiledata));
  close(f);
end;

procedure OutVarInit(out v);
begin
  //
end;

function GetLoggedInUserName : string;
{$ifdef WINDOWS}
var
  ns : DWord;
begin
  ns := 1024;
  result := '';
  SetLength(result, ns);
  if not GetUserName(PChar(result), ns) then RaiseLastOSError;
  SetLength(result, ns-1);
end;
{$else}
begin
  result := GetEnvironmentVariable('USER');
end;
{$endif}

function ReadFileToStr(const afilename : string) : ansistring;
var
  f : File;
  flen : int64;
begin
  if not FileExists(afilename) then
  begin
    result := '';
    EXIT;
  end;

  try
    Assign(f, afilename);
    Reset(f, 1);
    flen := FileSize(f);
    result := '';
    SetLength(result, flen);
    BlockRead(f, result[1], flen);
    close(f);
  except
    result := '';
  end;
end;

function ReadFileToBytes(const afilename : string) : TBytes;
var
  f : File;
  flen : int64;
begin
  if not FileExists(afilename) then
  begin
    result := [];
    EXIT;
  end;

  try
    Assign(f, afilename);
    Reset(f, 1);
    flen := FileSize(f);
    result := [];
    SetLength(result, flen);
    BlockRead(f, result[0], flen);
    close(f);
  except
    result := [];
  end;
end;

procedure WriteStrToFile(const afilename, afiledata : string);
var
  f : File;
begin
  Assign(f, afilename);
  Rewrite(f, 1);
  if length(afiledata) > 0 then
  begin
    BlockWrite(f, afiledata[1], length(afiledata));
  end;
  close(f);
end;

procedure WriteBytesToFile(const afilename : string; afiledata : TBytes);
var
  f : File;
begin
  Assign(f, afilename);
  Rewrite(f, 1);
  if length(afiledata) > 0 then
  begin
    BlockWrite(f, afiledata[0], length(afiledata));
  end;
  close(f);
end;

end.


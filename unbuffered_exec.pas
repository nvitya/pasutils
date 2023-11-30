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
   file:     unbuffered_exec.pas
   brief:    Executing console applications with non-blocking, unbuffered output pipe
   date:     2023-11-30
   authors:  nvitya
*)

unit unbuffered_exec;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Windows, Pipes;

type

  { TUnbufferedExec }

  TUnbufferedExec = class
  public
    FProcessID : Integer;
    FThreadID : Integer;
    FProcessHandle : Thandle;
    FThreadHandle : Thandle;

    FStartupInfo : STARTUPINFOW;
    FStartupInfoa : STARTUPINFOA;

    procedure InitStartupInfo;

    procedure FreeStreams;

  public
    FInputStream  : TOutputPipeStream;
    FOutputStream : TInputPipeStream;

    running    : boolean;
    returncode : integer;
    FExitCode  : integer;

    constructor Create;
    destructor Destroy; override;

    procedure Exec(acmdline : string; aparams : string);

    function  ReadOutput : string;
    procedure WriteInput(astr : string);

    function CheckRunning : boolean;

    property Input  : TOutputPipeStream Read FInputStream;
    property Output : TInputPipeStream  Read FOutputStream;
    property ExitCode : integer read FExitCode;

  end;

implementation

{

For Unbuffered Exec the process should be started with special startupinfo:

https://stackoverflow.com/questions/40965496/windows-how-to-stop-buffering-of-redirected-stdout-using-createprocess

}


{ TUnbufferedExec }

constructor TUnbufferedExec.Create;
begin
  running := false;
  returncode := -1;
  FInputStream := nil;
  FOutputStream := nil;
end;

function TUnbufferedExec.CheckRunning : boolean;
var
  ecode : cardinal = 0;
begin
  if GetExitCodeProcess(FProcessHandle, ecode) then
  begin
    if ecode <> 259 then
    begin
      FExitCode := ecode;
      running := false;
    end;
  end;
  result := running;
end;

destructor TUnbufferedExec.Destroy;
begin
  FreeStreams;
  inherited Destroy;
end;

function WStrAsUniquePWideChar(var s: UnicodeString): PWideChar;
begin
  UniqueString(s);
  if s<>'' then
    Result:=PWideChar(s)
  else
    Result:=nil;
end;

Const
  piInheritablePipe : TSecurityAttributes = (
                           nlength:SizeOF(TSecurityAttributes);
                           lpSecurityDescriptor:Nil;
                           Binherithandle:True);

  piNonInheritablePipe : TSecurityAttributes = (
                         nlength:SizeOF(TSecurityAttributes);
                         lpSecurityDescriptor:Nil;
                         Binherithandle:False);


Function CreatePipeHandles(Var Inhandle, OutHandle : THandle; APipeBufferSize : Cardinal) : Boolean;
begin
  Result := CreatePipe(@Inhandle, @OutHandle, @piNonInheritablePipe, APipeBufferSize);
end;

{ The handles that are to be passed to the child process must be
  inheritable. On the other hand, only non-inheritable handles
  allow the sending of EOF when the write-end is closed. This
  function is used to duplicate the child process's ends of the
  handles into inheritable ones, leaving the parent-side handles
  non-inheritable.
}
function DuplicateHandleFP(var handle: THandle): Boolean;
var
  oldHandle: THandle;
begin
  oldHandle := handle;
  Result := DuplicateHandle(
    GetCurrentProcess(),
    oldHandle,
    GetCurrentProcess(),
    @handle,
    0,
    true,
    DUPLICATE_SAME_ACCESS
  );
  if Result then
    Result := CloseHandle(oldHandle);
end;

procedure TUnbufferedExec.Exec(acmdline : string; aparams : string);
const
  PipeBufSize = 1024;
var
  WDir, WCommandLine : UnicodeString;
  PWDir, PWCommandLine : PWideChar;

  HI, HO : THandle;

  FCreationFlags : Cardinal;
  FProcessAttributes : TSecurityAttributes;
  FThreadAttributes : TSecurityAttributes;
  FProcessInformation : TProcessInformation;

  siextra : array of byte;

  pipemode : DWORD;
begin
  running := false;

  WCommandLine := UnicodeString(acmdline);
  if aparams <> '' then WCommandLine += ' ' + UnicodeString(aparams);
  WDir := UnicodeString(GetCurrentDir);

  FCreationFlags := NORMAL_PRIORITY_CLASS + CREATE_UNICODE_ENVIRONMENT;

  // initialize variables to avoid FPC warnings
  FProcessAttributes.nLength := 0;
  FThreadAttributes.nLength := 0;
  HI := 0;
  HO := 0;
  FProcessInformation.dwProcessId := 0;

  FillChar(FProcessAttributes, SizeOf(FProcessAttributes), 0);
  FProcessAttributes.nLength := SizeOf(FProcessAttributes);

  FillChar(FThreadAttributes, SizeOf(FThreadAttributes), 0);
  FThreadAttributes.nLength := SizeOf(FThreadAttributes);

  InitStartupInfo();

  // Create the pipes, stderr redirected to stdout
  CreatePipeHandles(FStartupInfo.hStdInput, HI, PipeBufSize);
  DuplicateHandleFP(FStartupInfo.hStdInput);
  CreatePipeHandles(HO, FStartupInfo.hStdOutput, PipeBufSize);
  DuplicateHandleFP(FStartupInfo.hStdOutput);
  FStartupInfo.hStdError := FStartupInfo.hStdOutput;

  // Now the non-documented non-buffered request hinting
  // lpReserved Structure:
  //   u32     : number of file handles = 2
  //   u8      : = 0x41 = (FOPEN | FDEV) file 0 attributes
  //   u8      : = 0x41 = (FOPEN | FDEV) file 1 attributes
  //   u32/u64 : child process stdinput file handle
  //   u32/u64 : child process stdoutput file handle

  siextra := [];
  SetLength(siextra, 4 + (2 * (1 + sizeof(THANDLE))));
  FStartupInfo.cbReserved2 := length(siextra);
  FStartupInfo.lpReserved2 := @siextra[0];

  PInteger(@siextra[0])^ := 2; // passing two file handles
  siextra[4] := $41;
  siextra[5] := $41;
  PHandle(@siextra[6])^ := FStartupInfo.hStdInput;
  PHandle(@siextra[6 + sizeof(THandle)])^ := FStartupInfo.hStdOutput;

  try
    // Beware: CreateProcess can alter the strings
    // Beware: nil is not the same as a pointer to a #0
    PWCommandLine := WStrAsUniquePWideChar(WCommandLine);
    PWDir := WStrAsUniquePWideChar(WDir);

    If not CreateProcessW(nil, PWCommandLine, @FProcessAttributes, @FThreadAttributes,
                 true, FCreationFlags, nil {FEnv}, PWDir, FStartupInfo, FProcessInformation) then
    begin
      raise Exception.CreateFmt('Execute error: %s: %d', [acmdline, GetLastError]);
    end;

    FProcessHandle := FProcessInformation.hProcess;
    FThreadHandle  := FProcessInformation.hThread;
    FThreadId      := FProcessInformation.dwThreadId;
    FProcessID     := FProcessINformation.dwProcessID;

  finally

    FileClose(FStartupInfo.hStdInput);
    FileClose(FStartupInfo.hStdOutput);

    // request non-blocking mode for the output pipe
    pipemode := PIPE_NOWAIT;
    if SetNamedPipeHandleState(HO, pipemode, nil, nil) then
    begin
      //
    end;

    FInputStream  := TOutputPipeStream.Create(HI);
    FOutputStream := TInputPipeStream.Create(HO);
  end;

  running := true;
end;

procedure TUnbufferedExec.FreeStreams;
begin
  if FOutputStream <> nil then FreeAndNil(FOutputStream);
  if FInputStream <> nil  then FreeAndNil(FInputStream);
end;

procedure TUnbufferedExec.InitStartupInfo;
{

TShowWindowOptions = (swoNone,swoHIDE,swoMaximize,swoMinimize,swoRestore,swoShow,
                      swoShowDefault,swoShowMaximized,swoShowMinimized,
                      swoshowMinNOActive,swoShowNA,swoShowNoActivate,swoShowNormal);

Const
  SWC : Array [TShowWindowOptions] of Cardinal =
             (0, SW_HIDE, SW_Maximize, SW_Minimize, SW_Restore, SW_Show,
             SW_ShowDefault, SW_ShowMaximized, SW_ShowMinimized,
               SW_showMinNOActive, SW_ShowNA, SW_ShowNoActivate, SW_ShowNormal);
}

begin
  FillChar(FStartupInfo, SizeOf(FStartupInfo), 0);
  FStartupInfo.cb      := SizeOf(FStartupInfo);

  FStartupInfo.wShowWindow := SW_HIDE;
  FStartupInfo.dwFlags := STARTF_USESTDHANDLES; // for pipes
end;

function TUnbufferedExec.ReadOutput : string;
begin
  result := '';
end;

procedure TUnbufferedExec.WriteInput(astr : string);
begin
  if astr <> '' then
  begin
    //
  end;
end;

end.


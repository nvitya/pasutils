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
   file:     util_microtime.pas
   brief:    Very simple high resolution absolute and relative timer in microseconds
   date:     2025-06-15
   authors:  nvitya
*)

unit util_microtime;

interface

uses
  Classes, SysUtils;

function real_microtime() : int64;  // can be coverted to real time but might get jumps at clock adjustments
function mono_microtime() : int64;  // ensured monotonic, but harder to convert to real-time

function microtime() : int64;  // same as mono_microtime()

implementation

{$ifdef WINDOWS}
uses
  windows;
{$else} // linux
uses
  BaseUnix, linux;
{$endif}

function microtime() : int64; inline;
begin
  result := mono_microtime();
end;

{$ifdef WINDOWS}

var
  qpcmsscale : double;

procedure init_microtime();
var
  freq : int64;
begin
  nstime_sys_offset := 0;

  freq := 0;
	QueryPerformanceFrequency(freq);
	qpcmsscale := 1000000 / freq;
end;

function mono_microtime() : int64;
var
  qpc : int64;
begin
  qpc := 0;
  QueryPerformanceCounter(qpc);
  result := trunc(qpcmsscale * qpc);
end;

function real_microtime() : int64;
begin
  result := mono_microtime(); // TODO: implement
end;

{$else} // linux

function real_microtime() : int64;
var
  ts : timespec;
begin
  clock_gettime(CLOCK_REALTIME, @ts);
  result := int64(ts.tv_sec) * int64(1000000) + (ts.tv_nsec + 500) div 1000;
end;

function mono_microtime() : int64;
var
  ts : timespec;
begin
  clock_gettime(CLOCK_MONOTONIC, @ts);
  result := int64(ts.tv_sec) * int64(1000000) + (ts.tv_nsec + 500) div 1000;
end;

procedure init_microtime();
begin
  // nothing required on linux so far
end;

{$endif}

initialization
begin
  init_microtime();
end;

end.


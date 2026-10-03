{ Where the program keeps its files.  It is portable, so settings, draft and
  scratch files live beside the program and each copy keeps its own; a copy
  must not pick up another copy's draft.  When its folder cannot be written
  (/usr/bin, Program Files) the user's config folder is used instead. }
unit hsPaths;

{$mode objfpc}{$H+}

interface

{ The folder for settings, draft and scratch, ending in a path separator. }
function AppDataDir: string;
{ True when that is the program's own folder rather than the user's home. }
function IsPortable: Boolean;
{ The source tree when running from its bin folder, otherwise ''. }
function SourceTreeDir: string;
function ConfigFile: string;
function DraftFile: string;
{ What a program being updated leaves for its replacement: every sheet,
  its file name and any unsaved work. }
function HandoffFile: string;
{ Where the example drawings are put. }
function ExamplesDir: string;

{ Default Save and Export folders, beside the program so work travels with
  a portable copy.  Made on first use.  The caller remembers where the user
  goes instead; these are only the defaults. }
function DrawingsDir: string;
function ExportsDir: string;
{ The local manual's index.html, or '' when there is none and the caller
  should use the website instead. }
function HelpPage: string;

{ A folder beside the program, made if missing.  '' if it cannot be made,
  so the caller lets the dialog decide. }
function WorkDir(const Name: string): string;

implementation

uses
  SysUtils, Classes;

var
  Cached: string = '';
  CachedPortable: Boolean = False;

function CanWriteIn(const Dir: string): Boolean;
var
  F: TFileStream;
  Probe: string;
begin
  Result := False;
  if Dir = '' then Exit;
  Probe := IncludeTrailingPathDelimiter(Dir) + '.hsk-write-probe';
  try
    F := TFileStream.Create(Probe, fmCreate);
    F.Free;
    DeleteFile(Probe);
    Result := True;
  except
    Result := False;
  end;
end;

function AppDataDir: string;
var
  Own: string;
begin
  if Cached <> '' then Exit(Cached);
  Own := ExtractFilePath(ExpandFileName(ParamStr(0)));
  if CanWriteIn(Own) then
  begin
    Cached := Own;
    CachedPortable := True;
  end
  else
  begin
    Cached := IncludeTrailingPathDelimiter(GetAppConfigDir(False));
    CachedPortable := False;
    ForceDirectories(Cached);
  end;
  Result := Cached;
end;

function IsPortable: Boolean;
begin
  AppDataDir;
  Result := CachedPortable;
end;

{ The build goes into bin/, so the tree's own folders (jigs, the manual)
  are one level up. }
function SourceTreeDir: string;
var
  Up: string;
begin
  Result := '';
  Up := ExpandFileName(AppDataDir + '..' + PathDelim);
  if FileExists(Up + 'etchasketch.lpi') then Result := IncludeTrailingPathDelimiter(Up);
end;

function ConfigFile: string;
begin
  Result := AppDataDir + 'heckers-sketch.cfg';
end;

function DraftFile: string;
begin
  Result := AppDataDir + 'heckers-sketch-draft.hsk';
end;

function HandoffFile: string;
begin
  Result := AppDataDir + 'heckers-sketch-handoff.hsk';
end;

function ExamplesDir: string;
begin
  Result := AppDataDir + 'examples' + PathDelim;
end;

function HelpPage: string;
begin
  Result := AppDataDir + 'help' + PathDelim + 'index.html';
  if FileExists(Result) then Exit;
  { running from the source tree, it is under docs }
  Result := AppDataDir + 'docs' + PathDelim + 'help' + PathDelim + 'index.html';
  if FileExists(Result) then Exit;
  if SourceTreeDir <> '' then
  begin
    Result := SourceTreeDir + 'docs' + PathDelim + 'help' + PathDelim + 'index.html';
    if FileExists(Result) then Exit;
  end;
  Result := '';
end;

function WorkDir(const Name: string): string;
begin
  Result := AppDataDir + Name + PathDelim;
  if not DirectoryExists(Result) then
    if not ForceDirectories(Result) then
      Result := '';
end;

function DrawingsDir: string;
begin
  Result := WorkDir('drawings');
end;

function ExportsDir: string;
begin
  Result := WorkDir('exports');
end;

end.

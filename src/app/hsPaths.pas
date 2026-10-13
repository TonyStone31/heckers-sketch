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
function IsPortable: boolean;
{ The source tree when running from its bin folder, otherwise ''. }
function SourceTreeDir: string;
function ConfigFile: string;
function DraftFile: string;
{ What a program being updated leaves for its replacement: every sheet,
  its file name and any unsaved work. }
function HandoffFile: string;
{ Notes a second copy leaves for the running one: files to open, or an
  empty note meaning "come to the front".  Read and deleted on the tick. }
function OpenRequestMask: string;
function NewOpenRequestName: string;
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
  SysUtils, Classes, LazFileUtils;

var
  Cached: string = '';
  CachedPortable: boolean = False;

{$ifdef darwin}
{ An .app is replaced whole, and macOS may run it from a read-only copy, so
  nothing is kept in one: settings go under Library and work under
  Documents, where a Mac user looks for them.  '' outside a bundle. }
function BundleHome(const Under: string): string;
begin
  if Pos('.app/Contents/MacOS/', ExpandFileName(ParamStr(0))) = 0 then Exit('');
  Result := IncludeTrailingPathDelimiter(GetUserDir) + Under + '/Heckers Sketch/';
end;

{$endif}

function AppDataDir: string;
var
  Own: string;
begin
  if Cached <> '' then Exit(Cached);
  Own := ExtractFilePath(ExpandFileName(ParamStr(0)));
  {$ifdef darwin}
  if BundleHome('') <> '' then Own := '';
  {$endif}
  if (Own <> '') and DirectoryIsWritable(Own) then
  begin
    Cached := Own;
    CachedPortable := True;
  end
  else
  begin
    Cached := IncludeTrailingPathDelimiter(GetAppConfigDir(False));
    {$ifdef darwin}
    if BundleHome('') <> '' then Cached := BundleHome('Library/Application Support');
    {$endif}
    CachedPortable := False;
    ForceDirectories(Cached);
  end;
  Result := Cached;
end;

function IsPortable: boolean;
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
  if FileExists(Up + 'heckerssketch.lpi') then Result := IncludeTrailingPathDelimiter(Up);
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

function OpenRequestMask: string;
begin
  Result := AppDataDir + 'heckers-sketch-open-*.req';
end;

function NewOpenRequestName: string;
begin
  Result := AppDataDir + 'heckers-sketch-open-' + IntToStr(GetProcessID) + '.req';
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
  {$ifdef darwin}
  if BundleHome('') <> '' then Result := BundleHome('Documents') + Name + PathDelim;
  {$endif}
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

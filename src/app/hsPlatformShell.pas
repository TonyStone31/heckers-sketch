{ Showing a file in the file manager.  LCL's SelectInFolder is newer than
  Lazarus 4; without it Finder is asked, and elsewhere the folder is opened. }
unit hsPlatformShell;

{$mode objfpc}{$H+}

interface

function ShowFileInFolder(const Path: string): boolean;

implementation

uses SysUtils, Process, LCLIntf;

function ShowFileInFolder(const Path: string): boolean;
  {$ifdef DARWIN}
var
  Output: String;
  {$endif}
begin
  {$if declared(SelectInFolder)}
  Result := SelectInFolder(Path);
  {$else}
  {$ifdef DARWIN}
  Result := RunCommand('/usr/bin/open', ['-R', ExpandFileName(Path)], Output);
  {$else}
  Result := OpenDocument(ExtractFileDir(ExpandFileName(Path)));
  {$endif}
  {$endif}
end;

end.

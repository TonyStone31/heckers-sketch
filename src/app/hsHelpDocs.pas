unit hsHelpDocs;

{ Keeps a local copy of the manual so it works offline.  Fetches the
  release's heckers-sketch-help.zip, checks it against SHA256SUMS and
  unpacks it into a help folder beside the program.  Release downloads do
  not count against the GitHub API limit.  Prefers the pages for the running
  version, else the latest.  No windows here, so the tests can run it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  HELP_ZIP = 'heckers-sketch-help.zip';
  { written into the zip by build.sh, holding the tag the pages came from }
  HELP_VERSION_FILE = 'VERSION';

type
  THelpProgress = procedure(BytesReceived, TotalBytes: Int64) of object;

{ Beside the program when portable, else in the user's own folder. }
function HelpFolder: string;
{ index.html of the local copy, or '' when there is none.  A copy running
  from the source tree reads docs/help directly. }
function LocalHelpIndex: string;
{ The release the local pages came from, or '' when unknown or absent. }
function LocalHelpVersion: string;
function HelpZipURL(const Tag: string): string;
function HelpSumsURL(const Tag: string): string;

{ Unpacks ZipPath into Dest, replacing the old copy only once the new one is
  complete.  Refuses entries that would land outside Dest, anything
  implausibly large, and a zip with no index.html. }
function InstallHelpZip(const ZipPath, Dest: string; out Err: string): Boolean;

{ Fetches, checks and installs the pages for Tag, or the latest release
  when Tag has none.  GotTag says which release they came from. }
function FetchHelp(const Tag: string; OnProgress: THelpProgress;
  out GotTag, Err: string): Boolean;

{ True when the local pages are missing or from another release, as right
  after an update.  Never true when running from the source tree. }
function HelpIsStale(const ProgramTag: string): Boolean;

type
  { FetchHelp on its own thread.  OnDone and OnProgress run on the main
    thread and may be nil.  Frees itself. }
  THelpFetch = class(TThread)
  private
    FTag, FGotTag, FErr: string;
    FOK: Boolean;
    FGot, FTotal: Int64;
    FOnProgress: THelpProgress;
    FOnDone: TNotifyEvent;
    procedure Progress(BytesReceived, TotalBytes: Int64);
    procedure SyncProgress;
    procedure SyncDone;
  protected
    procedure Execute; override;
  public
    constructor Create(const ATag: string; AOnProgress: THelpProgress;
      AOnDone: TNotifyEvent);
    property OK: Boolean read FOK;
    property GotTag: string read FGotTag;
    property Err: string read FErr;
  end;

var
  { the running fetch; there is never more than one }
  HelpFetching: THelpFetch = nil;

{ False when a fetch is already running. }
function StartHelpFetch(const Tag: string; AOnProgress: THelpProgress;
  AOnDone: TNotifyEvent): Boolean;

implementation

uses
  zipper, hsPaths, hsUpdater, hsNet;

const
  { the manual is a few megabytes; anything near these is wrong }
  MAX_FILES = 5000;
  MAX_BYTES = 200 * 1024 * 1024;

function HelpFolder: string;
begin
  Result := AppDataDir + 'help' + PathDelim;
end;

function LocalHelpIndex: string;
begin
  Result := HelpPage;
end;

function LocalHelpVersion: string;
var
  L: TStringList;
  F: string;
begin
  Result := '';
  F := HelpFolder + HELP_VERSION_FILE;
  if not FileExists(F) then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(F);
      if L.Count > 0 then Result := Trim(L[0]);
    except
      Result := '';
    end;
  finally
    L.Free;
  end;
end;

function HelpZipURL(const Tag: string): string;
begin
  Result := 'https://github.com/' + UPDATE_REPO + '/releases/download/' +
    Tag + '/' + HELP_ZIP;
end;

function HelpSumsURL(const Tag: string): string;
begin
  Result := 'https://github.com/' + UPDATE_REPO + '/releases/download/' +
    Tag + '/SHA256SUMS';
end;

{ A zip entry name made safe, or '' to refuse it.  Names that climb (..),
  start at a root or drive, or are empty are refused, and the caller then
  rejects the whole zip. }
function SafeName(const Name: string): string;
var
  S, Part: string;
  Parts: TStringList;
  I: Integer;
begin
  Result := '';
  S := StringReplace(Name, '\', '/', [rfReplaceAll]);
  if (S = '') or (S[1] = '/') or (Pos(':', S) > 0) then Exit;
  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := '/';
    Parts.DelimitedText := S;
    for I := 0 to Parts.Count - 1 do
    begin
      Part := Parts[I];
      if (Part = '..') then Exit('');
      if (Part = '') or (Part = '.') then Continue;
      if Result <> '' then Result := Result + PathDelim;
      Result := Result + Part;
    end;
  finally
    Parts.Free;
  end;
end;

function RemoveTree(const Dir: string): Boolean;
var
  SR: TSearchRec;
  D: string;
begin
  D := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(D + '*', faAnyFile or faSymLink, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      { delete a link itself; never follow it into what it points at }
      if (SR.Attr and faSymLink) <> 0 then
        DeleteFile(D + SR.Name)
      else if (SR.Attr and faDirectory) <> 0 then
        RemoveTree(D + SR.Name)
      else
        DeleteFile(D + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  Result := RemoveDir(Dir);
end;

function InstallHelpZip(const ZipPath, Dest: string; out Err: string): Boolean;
var
  Z: TUnZipper;
  I, N: Integer;
  Total: Int64;
  Target, Fresh, Old: string;
  Entry: TFullZipFileEntry;
begin
  Result := False;
  Err := '';
  Target := ExcludeTrailingPathDelimiter(Dest);
  Fresh := Target + '.new';
  Old := Target + '.old';
  if DirectoryExists(Fresh) then RemoveTree(Fresh);
  if DirectoryExists(Old) then RemoveTree(Old);

  Z := TUnZipper.Create;
  try
    try
      Z.FileName := ZipPath;
      Z.Examine;
      N := Z.Entries.Count;
      if N = 0 then
      begin
        Err := 'the help archive is empty';
        Exit;
      end;
      if N > MAX_FILES then
      begin
        Err := 'the help archive has too many files in it';
        Exit;
      end;
      Total := 0;
      for I := 0 to N - 1 do
      begin
        Entry := Z.Entries.FullEntries[I];
        if SafeName(Entry.ArchiveFileName) = '' then
        begin
          if Entry.IsDirectory and (Trim(Entry.ArchiveFileName) = '') then
            Continue;
          Err := 'the help archive has a file that would land outside ' +
            'its folder (' + Entry.ArchiveFileName + ')';
          Exit;
        end;
        Inc(Total, Entry.Size);
        if Total > MAX_BYTES then
        begin
          Err := 'the help archive unpacks to more than it should';
          Exit;
        end;
      end;

      ForceDirectories(Fresh);
      Z.OutputPath := Fresh;
      Z.UnZipAllFiles;
    except
      on E: Exception do
      begin
        Err := 'the help archive could not be unpacked: ' + E.Message;
        if DirectoryExists(Fresh) then RemoveTree(Fresh);
        Exit;
      end;
    end;
  finally
    Z.Free;
  end;

  if not FileExists(Fresh + PathDelim + 'index.html') then
  begin
    Err := 'the help archive has no index.html in it';
    RemoveTree(Fresh);
    Exit;
  end;

  { Move the old copy aside rather than delete it until the new one is in
    place, so a failure leaves one copy or the other. }
  if DirectoryExists(Target) and not RenameFile(Target, Old) then
  begin
    Err := 'the old help folder could not be moved aside';
    RemoveTree(Fresh);
    Exit;
  end;
  if not RenameFile(Fresh, Target) then
  begin
    Err := 'the new help folder could not be put in place';
    if DirectoryExists(Old) then RenameFile(Old, Target);
    RemoveTree(Fresh);
    Exit;
  end;
  if DirectoryExists(Old) then RemoveTree(Old);
  Result := True;
end;

function FetchHelp(const Tag: string; OnProgress: THelpProgress;
  out GotTag, Err: string): Boolean;
var
  Tried, Want, Tmp, Sum: string;
  Info: TUpdateInfo;
  LatestErr: string;

  function TryTag(const T: string): Boolean;
  begin
    Result := False;
    Want := ExpectedSum(HelpSumsURL(T), HELP_ZIP);
    { no help zip for this tag; not an error yet, the latest may have one }
    if Want = '' then Exit;
    Tmp := GetTempFileName(GetTempDir(False), 'hskhelp');
    try
      if not Download(HelpZipURL(T), Tmp, 0, OnProgress, Err) then
      begin
        Err := 'the download failed: ' + NetFriendlyError(Err);
        Exit;
      end;
      Sum := Sha256Of(Tmp);
      if not SameText(Sum, Want) then
      begin
        Err := 'the downloaded help did not match its checksum, so it was ' +
          'not used';
        Exit;
      end;
      if not InstallHelpZip(Tmp, HelpFolder, Err) then Exit;
      GotTag := T;
      Result := True;
    finally
      if FileExists(Tmp) then DeleteFile(Tmp);
    end;
  end;

begin
  Result := False;
  GotTag := '';
  Err := '';
  Tried := '';
  if NetOffline then
  begin
    Err := 'offline (--offline)';
    Exit;
  end;

  { this version's pages first, so the manual matches the program }
  if (Tag <> '') and (Tag[1] = 'v') and (Pos('dev', Tag) = 0) then
  begin
    Tried := Tag;
    if TryTag(Tag) then Exit(True);
    if Err <> '' then Exit;
  end;

  { otherwise the newest release's }
  if not FetchLatest(Info, LatestErr) then
  begin
    Err := 'could not find the latest release - ' + LatestErr;
    Exit;
  end;
  if Info.Tag = Tried then
  begin
    Err := 'release ' + Tried + ' has no help pages attached';
    Exit;
  end;
  if TryTag(Info.Tag) then Exit(True);
  if Err = '' then
    Err := 'release ' + Info.Tag + ' has no help pages attached';
end;

function HelpIsStale(const ProgramTag: string): Boolean;
var
  Index: string;
begin
  Index := LocalHelpIndex;
  { the source tree's own pages are always the current ones }
  if Pos(PathDelim + 'docs' + PathDelim + 'help' + PathDelim, Index) > 0 then
    Exit(False);
  if Index = '' then Exit(True);
  { a non-release build cannot tell which pages match; any will do }
  if (ProgramTag = '') or (ProgramTag[1] <> 'v') or (Pos('dev', ProgramTag) > 0) then
    Exit(False);
  Result := LocalHelpVersion <> ProgramTag;
end;

constructor THelpFetch.Create(const ATag: string; AOnProgress: THelpProgress;
  AOnDone: TNotifyEvent);
begin
  FTag := ATag;
  FOnProgress := AOnProgress;
  FOnDone := AOnDone;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure THelpFetch.Progress(BytesReceived, TotalBytes: Int64);
begin
  FGot := BytesReceived;
  FTotal := TotalBytes;
  if Assigned(FOnProgress) then Queue(@SyncProgress);
end;

procedure THelpFetch.SyncProgress;
begin
  if Assigned(FOnProgress) then FOnProgress(FGot, FTotal);
end;

procedure THelpFetch.SyncDone;
begin
  HelpFetching := nil;
  if Assigned(FOnDone) then FOnDone(Self);
end;

procedure THelpFetch.Execute;
begin
  try
    FOK := FetchHelp(FTag, @Progress, FGotTag, FErr);
  except
    on E: Exception do
    begin
      FOK := False;
      FErr := E.Message;
    end;
  end;
  Synchronize(@SyncDone);
end;

function StartHelpFetch(const Tag: string; AOnProgress: THelpProgress;
  AOnDone: TNotifyEvent): Boolean;
begin
  Result := HelpFetching = nil;
  if Result then HelpFetching := THelpFetch.Create(Tag, AOnProgress, AOnDone);
end;

end.

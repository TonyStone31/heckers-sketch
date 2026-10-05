{ Sends reports to a Filebin bin.  A GitHub Action rotates the bin and
  writes its address into a file in the repo; only that file's address is
  compiled in, so never hardcode a bin.
  The bin is public, so every byte is sealed by hsReportCrypto first (see
  src/vendor/crypto/README.md).  Nothing here may raise or interrupt: a
  report that cannot be sent is simply not sent. }
unit hsBugReport;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  { The one compiled-in address; everything else is looked up. }
  ENDPOINT_URL =
    'https://raw.githubusercontent.com/TonyStone31/heckers-sketch/' +
    'main/docs/bug-report-endpoint.json';

type
  { Where reports go now.  Cached locally so a report can still go out when
    GitHub is unreachable but the bin is alive. }
  TEndpoint = record
    UploadBase: string;   { https://filebin.net/<bin> }
    Bin: string;
    Updated: string;
  end;

{ Asks GitHub where reports go.  False, with a reason, on failure. }
function FetchEndpoint(out E: TEndpoint; out Err: string): Boolean;

{ The last endpoint that worked, or a blank one. }
function CachedEndpoint(out E: TEndpoint): Boolean;
procedure RememberEndpoint(const E: TEndpoint);

{ Size of the last report once sealed, shown in the send window. }
var
  LastSealedBytes: Integer = 0;

{ Sends Body as FileName.  Tries the cached bin first; if the refusal means
  the bin is gone, asks GitHub again and tries once more. }
function SendReport(const FileName, Body: string; out Err: string): Boolean;

{ The same, for something that is not text - a picture of the screen. }
function SendBinary(const FileName: string; Data: TStream;
  const ContentType: string; out Err: string): Boolean;

{ A name no other report will have. }
function UniqueReportName(const Prefix, Version: string): string;

implementation

uses
  hsNet, fpjson, jsonparser, IniFiles, hsPaths, hsReportCrypto;

function HttpGet(const URL: string; out Body, Err: string): Boolean;
begin
  Result := NetGetText(URL, '', Body, Err);
end;

function FetchEndpoint(out E: TEndpoint; out Err: string): Boolean;
var
  Body: string;
  J: TJSONData;
  O: TJSONObject;
begin
  Result := False;
  E.UploadBase := '';
  E.Bin := '';
  E.Updated := '';
  if not HttpGet(ENDPOINT_URL, Body, Err) then Exit;
  J := nil;
  try
    try
      J := GetJSON(Body);
    except
      on Ex: Exception do
      begin
        Err := 'the endpoint file could not be read';
        Exit;
      end;
    end;
    if not (J is TJSONObject) then
    begin
      Err := 'the endpoint file was not what was expected';
      Exit;
    end;
    O := TJSONObject(J);
    E.UploadBase := Trim(O.Get('upload_base', ''));
    E.Bin := Trim(O.Get('current_bin', ''));
    E.Updated := Trim(O.Get('updated_utc', ''));
    if E.UploadBase = '' then
    begin
      Err := 'the endpoint file names no place to upload to';
      Exit;
    end;
    while (E.UploadBase <> '') and
          (E.UploadBase[Length(E.UploadBase)] = '/') do
      SetLength(E.UploadBase, Length(E.UploadBase) - 1);
    Result := True;
  finally
    J.Free;
  end;
end;

function CachedEndpoint(out E: TEndpoint): Boolean;
var
  Ini: TIniFile;
begin
  E.UploadBase := '';
  E.Bin := '';
  E.Updated := '';
  Result := False;
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      E.UploadBase := Ini.ReadString('report', 'upload_base', '');
      E.Bin := Ini.ReadString('report', 'bin', '');
      E.Updated := Ini.ReadString('report', 'updated', '');
      Result := E.UploadBase <> '';
    finally
      Ini.Free;
    end;
  except
    Result := False;
  end;
end;

procedure RememberEndpoint(const E: TEndpoint);
var
  Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      Ini.WriteString('report', 'upload_base', E.UploadBase);
      Ini.WriteString('report', 'bin', E.Bin);
      Ini.WriteString('report', 'updated', E.Updated);
    finally
      Ini.Free;
    end;
  except
    { remembering is a convenience, not a requirement }
  end;
end;

{ True when the status means the bin is gone, so a fresh lookup is worth a
  retry.  Any other refusal would just fail the same way again. }
function BinIsGone(Status: Integer): Boolean;
begin
  case Status of
    401, 403, 404, 405, 409, 410, 423: Result := True;
  else
    Result := False;
  end;
end;

{ Every upload goes through here and is sealed first, so it is always sent
  as application/octet-stream whatever ContentType says. }
function PostStream(const Base, FileName: string; Data: TStream;
  const ContentType: string; out Status: Integer; out Err: string): Boolean;
var
  Plain, Sealed: TBytes;
  Sent: TMemoryStream;
begin
  Result := False;
  SetLength(Plain, Data.Size);
  if Data.Size > 0 then
  begin
    Data.Position := 0;
    Data.ReadBuffer(Plain[0], Data.Size);
  end;
  Sealed := EncryptReportBytes(Plain);
  LastSealedBytes := Length(Sealed);
  if Sealed = nil then
  begin
    { treated like a network failure: report it, do not raise }
    Err := 'the report could not be encrypted for sending';
    Exit;
  end;
  Sent := TMemoryStream.Create;
  try
    if Length(Sealed) > 0 then Sent.WriteBuffer(Sealed[0], Length(Sealed));
    Sent.Position := 0;
    Result := NetPost(Base + '/' + FileName, Sent, 'application/octet-stream',
      Status, Err);
    if (not Result) and (Status > 0) then
      Err := 'the postbox answered ' + IntToStr(Status);
  finally
    Sent.Free;
  end;
end;

function PostTo(const Base, FileName, Body: string;
  out Status: Integer; out Err: string): Boolean;
var
  Src: TStringStream;
begin
  { PostStream seals it, so this content type is not what gets sent }
  Src := TStringStream.Create(Body);
  try
    Result := PostStream(Base, FileName, Src, 'text/plain; charset=utf-8',
      Status, Err);
  finally
    Src.Free;
  end;
end;

function SendReport(const FileName, Body: string; out Err: string): Boolean;
var
  E: TEndpoint;
  Status: Integer;
  E2: TEndpoint;
  Err2: string;
begin
  Result := False;
  Err := '';
  try
    if CachedEndpoint(E) then
    begin
      if PostTo(E.UploadBase, FileName, Body, Status, Err) then
      begin
        Result := True;
        Exit;
      end;
      { only a gone bin is worth a fresh lookup }
      if not BinIsGone(Status) and (Status <> 0) then Exit;
    end;

    if not FetchEndpoint(E2, Err2) then
    begin
      if Err = '' then Err := Err2 else Err := Err + '; ' + Err2;
      Exit;
    end;
    RememberEndpoint(E2);
    Result := PostTo(E2.UploadBase, FileName, Body, Status, Err);
  except
    on Ex: Exception do
    begin
      Result := False;
      Err := Ex.Message;
    end;
  end;
end;

function SendBinary(const FileName: string; Data: TStream;
  const ContentType: string; out Err: string): Boolean;
var
  E, E2: TEndpoint;
  Status: Integer;
  Err2: string;
begin
  Result := False;
  Err := '';
  try
    if CachedEndpoint(E) then
    begin
      if PostStream(E.UploadBase, FileName, Data, ContentType, Status, Err) then
        Exit(True);
      if not BinIsGone(Status) and (Status <> 0) then Exit;
    end;
    if not FetchEndpoint(E2, Err2) then
    begin
      if Err = '' then Err := Err2 else Err := Err + '; ' + Err2;
      Exit;
    end;
    RememberEndpoint(E2);
    Result := PostStream(E2.UploadBase, FileName, Data, ContentType,
      Status, Err);
  except
    on Ex: Exception do
    begin
      Result := False;
      Err := Ex.Message;
    end;
  end;
end;

function UniqueReportName(const Prefix, Version: string): string;
var
  Tag, V: string;
  I: Integer;
begin
  Tag := IntToHex(Random($1000000), 6);
  V := '';
  for I := 1 to Length(Version) do
    if Version[I] in ['0'..'9', 'A'..'Z', 'a'..'z', '.', '-'] then
      V := V + Version[I];
  Result := Prefix + '-' + FormatDateTime('yyyymmdd-hhnnss', Now) +
    '-' + V + '-' + Tag + '.txt';
end;

end.

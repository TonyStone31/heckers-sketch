unit hsAssistantContext;

{ What the assistant would be given: its settings, its key, and the manual
  as plain text.  Nothing is sent anywhere yet.  No windows here, so the
  tests can run it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TAssistantSettings = record
    Provider: string;      { one of PROVIDERS }
    Endpoint: string;      { '' for the provider's own }
    Model: string;
    SendManual: Boolean;   { the manual: Writing Heck }
    SendSheet: Boolean;    { the whole sheet as Heck }
    SendPicked: Boolean;   { which lines are picked }
    Think: Boolean;        { a model that reasons may first; off answers at once }
  end;

const
  PROVIDERS: array[0..2] of string = ('Anthropic', 'OpenAI', 'A server of my own');
  PROV_ANTHROPIC = 0;
  PROV_OPENAI = 1;
  PROV_OWN = 2;

  { the pages the assistant reads, from the help folder: Writing Heck is the
    whole language, and the overview beside it only says much of it again
    in tokens a small model cannot spare }
  MANUAL_PAGES: array[0..0] of string = ('writing-heck.html');

function DefaultAssistantSettings: TAssistantSettings;
{ which of PROVIDERS; a name from an older settings file asks the
  chat-completions way it did }
function ProviderOf(const S: TAssistantSettings): Integer;
function LoadAssistantSettings: TAssistantSettings;
procedure SaveAssistantSettings(const S: TAssistantSettings);

{ The key is kept in a file of its own, readable by this user only, and
  never in the settings file that a bug report may describe. }
function AssistantKeyFile: string;
function LoadAssistantKey: string;
procedure SaveAssistantKey(const Key: string);

{ A help page as text: headings on their own lines, examples kept as they
  are, tags gone and entities decoded. }
function HtmlToText(const Html: string): string;

{ MANUAL_PAGES as one text, each under its title.  Missing names the pages
  not found; '' when all were. }
function ManualText(out Missing: string): string;

implementation

uses
  IniFiles, hsPaths {$IFDEF UNIX}, BaseUnix{$ENDIF};

const
  SECTION = 'assistant';

function DefaultAssistantSettings: TAssistantSettings;
begin
  Result.Provider := PROVIDERS[0];
  Result.Endpoint := '';
  Result.Model := '';
  Result.SendManual := True;
  Result.SendSheet := True;
  Result.SendPicked := True;
  Result.Think := True;
end;

function ProviderOf(const S: TAssistantSettings): Integer;
var
  I: Integer;
begin
  for I := 0 to High(PROVIDERS) do
    if SameText(S.Provider, PROVIDERS[I]) then Exit(I);
  Result := PROV_OPENAI;
end;

function LoadAssistantSettings: TAssistantSettings;
var
  Ini: TIniFile;
begin
  Result := DefaultAssistantSettings;
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      Result.Provider := Ini.ReadString(SECTION, 'provider', Result.Provider);
      Result.Endpoint := Ini.ReadString(SECTION, 'endpoint', Result.Endpoint);
      Result.Model := Ini.ReadString(SECTION, 'model', Result.Model);
      Result.SendManual := Ini.ReadBool(SECTION, 'sendmanual', Result.SendManual);
      Result.SendSheet := Ini.ReadBool(SECTION, 'sendsheet', Result.SendSheet);
      Result.SendPicked := Ini.ReadBool(SECTION, 'sendpicked', Result.SendPicked);
      Result.Think := Ini.ReadBool(SECTION, 'think', Result.Think);
    finally
      Ini.Free;
    end;
  except
    Result := DefaultAssistantSettings;
  end;
end;

procedure SaveAssistantSettings(const S: TAssistantSettings);
var
  Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      Ini.WriteString(SECTION, 'provider', S.Provider);
      Ini.WriteString(SECTION, 'endpoint', S.Endpoint);
      Ini.WriteString(SECTION, 'model', S.Model);
      Ini.WriteBool(SECTION, 'sendmanual', S.SendManual);
      Ini.WriteBool(SECTION, 'sendsheet', S.SendSheet);
      Ini.WriteBool(SECTION, 'sendpicked', S.SendPicked);
      Ini.WriteBool(SECTION, 'think', S.Think);
    finally
      Ini.Free;
    end;
  except
    { an unwritable config is not worth an error here }
  end;
end;

function AssistantKeyFile: string;
begin
  Result := AppDataDir + 'assistant-key.txt';
end;

function LoadAssistantKey: string;
var
  L: TStringList;
begin
  Result := '';
  if not FileExists(AssistantKeyFile) then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(AssistantKeyFile);
      if L.Count > 0 then Result := Trim(L[0]);
    except
      Result := '';
    end;
  finally
    L.Free;
  end;
end;

procedure SaveAssistantKey(const Key: string);
var
  F: TFileStream;
  S: string;
begin
  if Trim(Key) = '' then
  begin
    if FileExists(AssistantKeyFile) then DeleteFile(AssistantKeyFile);
    Exit;
  end;
  S := Trim(Key) + LineEnding;
  try
    F := TFileStream.Create(AssistantKeyFile, fmCreate);
    try
      {$IFDEF UNIX}
      { closed to others before the key goes in }
      FpChmod(AssistantKeyFile, &600);
      {$ENDIF}
      F.WriteBuffer(S[1], Length(S));
    finally
      F.Free;
    end;
  except
    { left unsaved; the settings window says so when it reads it back }
  end;
end;

function HtmlToText(const Html: string): string;
var
  I, J, N: Integer;
  Tag, Ent, Lw: string;
  InPre: Boolean;
  Sb: TStringBuilder;

  procedure Gap;
  begin
    { a blank line, but never two }
    while (Sb.Length > 0) and (Sb.Chars[Sb.Length - 1] = ' ') do Sb.Length := Sb.Length - 1;
    if Sb.Length = 0 then Exit;
    if Sb.Chars[Sb.Length - 1] <> #10 then Sb.Append(#10);
    if (Sb.Length > 1) and (Sb.Chars[Sb.Length - 2] <> #10) then Sb.Append(#10);
  end;

  procedure Brk;
  begin
    if (Sb.Length > 0) and (Sb.Chars[Sb.Length - 1] <> #10) then Sb.Append(#10);
  end;

begin
  Sb := TStringBuilder.Create;
  try
    InPre := False;
    I := 1;
    N := Length(Html);
    { only the body; the head is styling }
    J := Pos('<body', LowerCase(Html));
    if J > 0 then I := J;
    while I <= N do
    begin
      if Html[I] = '<' then
      begin
        J := I;
        while (J <= N) and (Html[J] <> '>') do Inc(J);
        Tag := LowerCase(Copy(Html, I + 1, J - I - 1));
        I := J + 1;
        if (Copy(Tag, 1, 6) = 'script') or (Copy(Tag, 1, 5) = 'style') then
        begin
          J := Pos('</' + Copy(Tag, 1, Pos(' ', Tag + ' ') - 1), LowerCase(Copy(Html, I, MaxInt)));
          if J > 0 then I := I + J - 1;
          Continue;
        end;
        Lw := Copy(Tag, 1, Pos(' ', Tag + ' ') - 1);
        if Lw = 'pre' then begin Gap; InPre := True; end
        else if Lw = '/pre' then begin InPre := False; Gap; end
        else if (Lw = 'h1') or (Lw = 'h2') or (Lw = 'h3') then begin Gap; Sb.Append('== '); end
        else if (Lw = '/h1') or (Lw = '/h2') or (Lw = '/h3') then begin Sb.Append(' =='); Gap; end
        else if (Lw = 'p') or (Lw = '/p') or (Lw = 'ul') or (Lw = '/ul') or
                (Lw = 'table') or (Lw = '/table') then Gap
        else if Lw = 'li' then begin Brk; Sb.Append('* '); end
        else if (Lw = 'br') or (Lw = 'br/') or (Lw = 'tr') then Brk
        else if (Lw = 'td') or (Lw = 'th') then Sb.Append(' | ');
        Continue;
      end;
      if Html[I] = '&' then
      begin
        J := I;
        while (J <= N) and (J - I < 10) and (Html[J] <> ';') do Inc(J);
        Ent := Copy(Html, I, J - I + 1);
        if Ent = '&amp;' then Sb.Append('&')
        else if Ent = '&lt;' then Sb.Append('<')
        else if Ent = '&gt;' then Sb.Append('>')
        else if Ent = '&quot;' then Sb.Append('"')
        else if (Ent = '&#39;') or (Ent = '&#x27;') or (Ent = '&apos;') then Sb.Append('''')
        else if Ent = '&rsaquo;' then Sb.Append('>')
        else if Ent = '&rarr;' then Sb.Append('->')
        else if Ent = '&larr;' then Sb.Append('<-')
        else if Ent = '&uarr;' then Sb.Append('up')
        else if Ent = '&darr;' then Sb.Append('down')
        else if Ent = '&nbsp;' then Sb.Append(' ')
        else if Ent = '&middot;' then Sb.Append('-')
        else if (Ent = '&mdash;') or (Ent = '&ndash;') then Sb.Append('-')
        else if Ent = '&deg;' then Sb.Append(#$C2#$B0)
        else
        begin
          Sb.Append('&');
          Inc(I);
          Continue;
        end;
        I := J + 1;
        Continue;
      end;
      if InPre then Sb.Append(Html[I])
      else if Html[I] in [#9, #10, #13, ' '] then
      begin
        if (Sb.Length > 0) and not (Sb.Chars[Sb.Length - 1] in [' ', #10]) then Sb.Append(' ');
      end
      else Sb.Append(Html[I]);
      Inc(I);
    end;
    Result := Trim(Sb.ToString);
  finally
    Sb.Free;
  end;
end;

function ManualText(out Missing: string): string;
var
  Dir, F: string;
  I: Integer;
  L: TStringList;
begin
  Result := '';
  Missing := '';
  F := HelpPage;
  if F = '' then Dir := '' else Dir := ExtractFilePath(F);
  L := TStringList.Create;
  try
    for I := 0 to High(MANUAL_PAGES) do
    begin
      F := Dir + MANUAL_PAGES[I];
      if (Dir = '') or not FileExists(F) then
      begin
        if Missing <> '' then Missing := Missing + ', ';
        Missing := Missing + MANUAL_PAGES[I];
        Continue;
      end;
      try
        L.LoadFromFile(F);
      except
        L.Clear;
      end;
      if Result <> '' then Result := Result + LineEnding + LineEnding;
      Result := Result + '######## ' + MANUAL_PAGES[I] + LineEnding + LineEnding + HtmlToText(L.Text);
    end;
  finally
    L.Free;
  end;
end;

end.

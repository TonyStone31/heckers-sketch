unit hsText;

{ Small text helpers more than one unit needs, kept in one place.  No LCL,
  so the tests can use it.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

var
  { Numbers written for a file or another program to read: a dot for the
    decimal point whatever the desktop's locale, and no thousands
    separator. }
  DotFS: TFormatSettings;

{ & < > made safe for HTML, SVG or LazInk markup }
function HtmlEsc(const S: string): string;
{ a quoted value back to its text - 'it''s' to it's; anything not quoted
  comes back trimmed }
function Unquote(const V: string): string;

implementation

function HtmlEsc(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
end;

function Unquote(const V: string): string;
var
  T: string;
begin
  T := Trim(V);
  if (Length(T) >= 2) and (T[1] = '''') and (T[Length(T)] = '''') then
    Result := StringReplace(Copy(T, 2, Length(T) - 2), '''''', '''', [rfReplaceAll])
  else
    Result := T;
end;

initialization
  DotFS := DefaultFormatSettings;
  DotFS.DecimalSeparator := '.';
  DotFS.ThousandSeparator := #0;
end.

unit hsCommandText;

{ Colors the command bar's text: names, lengths, commands and keys each get
  their own color so they read at a glance.  This unit only turns plain text
  into LazInk markup; the bar draws it (pbCmdPaint) and hands in the colors.
  Kept out of hsMainForm so it can be tested without a window. }

{$mode objfpc}{$H+}

interface

type
  { the colors as #RRGGBB, so they go straight into markup }
  TCmdPalette = record
    Text: string;      { plain words }
    Dim: string;       { units and the quiet parts }
    Name: string;      { "a name in quotes" }
    Number: string;    { a length, an angle, a count }
    Command: string;   { /a command, and the sums' operators }
    Key: string;       { Ctrl+Z, Esc, Enter }
    KeyBack: string;   { the little key cap behind it }
    Units: string;     { the feet and inch marks, mm, a degree }
    Op: string;        { + -- * / and brackets in a sum }
    Sep: string;       { the x between two sizes }
  end;

{ the no-break space, as the character itself: a run that must not wrap }
const
  NBSP = #$C2#$A0;

{ & < > made safe for markup }
function CmdEsc(const S: string): string;
{ S in a color, bold if asked }
function Painted(const Col, S: string; Bold: Boolean = False): string;
{ a message, with its names, lengths, commands and keys picked out }
function MarkMessage(const S: string; const P: TCmdPalette): string;
{ what is being typed: a command and its words, or a length and its sum }
function MarkTyped(const S: string; const P: TCmdPalette): string;

implementation

uses
  SysUtils;

const
  KEY_WORDS: array[0..14] of string = ('Ctrl', 'Shift', 'Alt', 'Esc',
    'Escape', 'Enter', 'Return', 'Tab', 'Delete', 'Backspace', 'Space',
    'Home', 'End', 'PgUp', 'PgDn');

function CmdEsc(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    case S[I] of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
    else
      Result := Result + S[I];
    end;
end;

function Painted(const Col, S: string; Bold: Boolean): string;
begin
  if S = '' then Exit('');
  Result := '<font color="' + Col + '">' + CmdEsc(S) + '</font>';
  if Bold then Result := '<b>' + Result + '</b>';
end;

function IsDigit(C: Char): Boolean; inline;
begin
  Result := C in ['0'..'9'];
end;

function IsLetter(C: Char): Boolean; inline;
begin
  Result := C in ['a'..'z', 'A'..'Z'];
end;

{ True at the start of a word, so "v2026" and "x3" are not lengths and
  "and/or" is not a command }
function WordStart(const S: string; I: Integer): Boolean;
begin
  Result := (I = 1) or not (IsLetter(S[I - 1]) or IsDigit(S[I - 1]) or
    (S[I - 1] in ['_', '.']));
end;

{ A length as the trade writes it, starting at I: 12'-6", 8' 10 1/2", 3/4",
  1200mm, 45°, 5.0s, 13 ms.  Returns its length in bytes, or 0. }
function LengthAt(const S: string; I: Integer): Integer;
var
  J, K: Integer;
begin
  Result := 0;
  if not IsDigit(S[I]) or not WordStart(S, I) then Exit;
  J := I;
  while J <= Length(S) do
  begin
    if IsDigit(S[J]) or (S[J] in ['.', '/', '''', '"', '%']) then Inc(J)
    { the degree sign, two bytes in UTF-8 }
    else if (S[J] = #$C2) and (J < Length(S)) and (S[J + 1] = #$B0) then Inc(J, 2)
    { 12'-6": a dash after the feet and before a figure }
    else if (S[J] = '-') and (J > I) and (S[J - 1] = '''') and
            (J < Length(S)) and IsDigit(S[J + 1]) then Inc(J)
    { 8' 10 1/2": a space between figures after the feet, or before a
      fraction }
    else if (S[J] = ' ') and (J < Length(S)) and IsDigit(S[J + 1]) and
            ((Pos('''', Copy(S, I, J - I)) > 0) or
             ((J + 2 <= Length(S)) and (Pos('/', Copy(S, J + 1, 4)) > 0) and
              (Pos(' ', Copy(S, J + 1, 4)) = 0))) then Inc(J)
    else Break;
  end;
  { a fraction's slash or a trailing dot is not the end of a length }
  while (J > I) and (S[J - 1] in ['.', '/', '-']) do Dec(J);
  { a unit written on - mm, ms, ft, in, px - or after one space }
  K := J;
  if (K <= Length(S)) and (S[K] = ' ') then Inc(K);
  if (K + 1 <= Length(S)) and
     (((LowerCase(Copy(S, K, 2)) = 'mm') or (LowerCase(Copy(S, K, 2)) = 'ms') or
       (LowerCase(Copy(S, K, 2)) = 'ft') or (LowerCase(Copy(S, K, 2)) = 'px') or
       (LowerCase(Copy(S, K, 2)) = 'in')) and
      ((K + 2 > Length(S)) or not IsLetter(S[K + 2]))) then
    J := K + 2
  else if (K <= Length(S)) and (K = J) and (S[K] in ['s', 'm']) and
          ((K + 1 > Length(S)) or not IsLetter(S[K + 1])) then
    J := K + 1;
  Result := J - I;
end;

{ a key, or keys joined by +: Ctrl+Shift+Z, Esc, F1 }
function KeyAt(const S: string; I: Integer): Integer;
var
  J, K, L: Integer;
  Hit: Boolean;
begin
  Result := 0;
  if not WordStart(S, I) then Exit;
  J := I;
  repeat
    Hit := False;
    for K := 0 to High(KEY_WORDS) do
    begin
      L := Length(KEY_WORDS[K]);
      if (Copy(S, J, L) = KEY_WORDS[K]) and
         ((J + L > Length(S)) or not IsLetter(S[J + L])) then
      begin
        Inc(J, L);
        Hit := True;
        Break;
      end;
    end;
    { F1 to F12 }
    if not Hit and (J < Length(S)) and (S[J] = 'F') and IsDigit(S[J + 1]) then
    begin
      Inc(J, 2);
      if (J <= Length(S)) and IsDigit(S[J]) then Inc(J);
      Hit := True;
    end;
    { after a +, one letter or figure is a key too: the Z of Ctrl+Z }
    if not Hit and (J > I) and (J <= Length(S)) and
       (IsLetter(S[J]) or IsDigit(S[J])) and
       ((J + 1 > Length(S)) or not (IsLetter(S[J + 1]) or IsDigit(S[J + 1]))) then
    begin
      Inc(J);
      Hit := True;
    end;
    if not Hit then Break;
    Result := J - I;
    if (J <= Length(S)) and (S[J] = '+') then Inc(J) else Break;
  until False;
end;

{ /a-command, at the start of a word }
function CommandAt(const S: string; I: Integer): Integer;
var
  J: Integer;
begin
  Result := 0;
  if (S[I] <> '/') or (I = Length(S)) or not IsLetter(S[I + 1]) then Exit;
  if (I > 1) and not (S[I - 1] in [' ', '(', '"', '''', '-']) then Exit;
  J := I + 1;
  while (J <= Length(S)) and (IsLetter(S[J]) or IsDigit(S[J])) do Inc(J);
  Result := J - I;
end;

function MarkMessage(const S: string; const P: TCmdPalette): string;
var
  I, N, J: Integer;
  Plain: string;

  procedure Flush;
  begin
    if Plain <> '' then Result := Result + Painted(P.Text, Plain);
    Plain := '';
  end;

begin
  Result := '';
  Plain := '';
  I := 1;
  while I <= Length(S) do
  begin
    { "a name", quotes and all }
    if S[I] = '"' then
    begin
      J := I + 1;
      while (J <= Length(S)) and (S[J] <> '"') do Inc(J);
      if (J <= Length(S)) and (J > I + 1) then
      begin
        Flush;
        Result := Result + Painted(P.Name, Copy(S, I, J - I + 1), True);
        I := J + 1;
        Continue;
      end;
    end;
    N := CommandAt(S, I);
    if N > 0 then
    begin
      Flush;
      Result := Result + Painted(P.Command, Copy(S, I, N), True);
      Inc(I, N);
      Continue;
    end;
    N := KeyAt(S, I);
    if N > 0 then
    begin
      Flush;
      Result := Result + '<font color="' + P.Key + '" bgcolor="' + P.KeyBack +
        '" pad="1 3" radius="5">' + CmdEsc(Copy(S, I, N)) + '</font>';
      Inc(I, N);
      Continue;
    end;
    N := LengthAt(S, I);
    if N > 0 then
    begin
      Flush;
      Result := Result + Painted(P.Number, Copy(S, I, N), True);
      Inc(I, N);
      { 12'x8' - the x between two sizes, and the size after it }
      while (I < Length(S)) and (S[I] in ['x', 'X']) and IsDigit(S[I + 1]) do
      begin
        Result := Result + Painted(P.Sep, S[I], True);
        Inc(I);
        N := 0;
        while (I + N <= Length(S)) and (IsDigit(S[I + N]) or (S[I + N] in ['.', '/', '''', '"', '-'])) do Inc(N);
        while (N > 0) and (S[I + N - 1] in ['.', '/', '-']) do Dec(N);
        Result := Result + Painted(P.Number, Copy(S, I, N), True);
        Inc(I, N);
      end;
      Continue;
    end;
    Plain := Plain + S[I];
    Inc(I);
  end;
  Flush;
end;

function MarkTyped(const S: string; const P: TCmdPalette): string;
var
  I, J: Integer;
  W: string;
begin
  Result := '';
  if S = '' then Exit;
  { a command: the word in its color, what follows it as a message would be }
  if S[1] = '/' then
  begin
    J := 2;
    while (J <= Length(S)) and (S[J] <> ' ') do Inc(J);
    Result := Painted(P.Command, Copy(S, 1, J - 1), True);
    if J <= Length(S) then Result := Result + MarkMessage(Copy(S, J, MaxInt), P);
    Exit;
  end;
  I := 1;
  while I <= Length(S) do
  begin
    { a figure, a decimal, a fraction 3/4 }
    if IsDigit(S[I]) or ((S[I] = '.') and (I < Length(S)) and IsDigit(S[I + 1])) then
    begin
      J := I;
      while (J <= Length(S)) and (IsDigit(S[J]) or (S[J] = '.') or
        ((S[J] = '/') and (J > I) and (J < Length(S)) and IsDigit(S[J + 1]))) do Inc(J);
      Result := Result + Painted(P.Number, Copy(S, I, J - I), True);
      I := J;
    end
    { feet and inches, and the degree sign }
    else if S[I] in ['''', '"'] then
    begin
      Result := Result + Painted(P.Units, S[I], True);
      Inc(I);
    end
    else if (S[I] = #$C2) and (I < Length(S)) and (S[I + 1] = #$B0) then
    begin
      Result := Result + Painted(P.Units, Copy(S, I, 2), True);
      Inc(I, 2);
    end
    { -- always takes away }
    else if (S[I] = '-') and (I < Length(S)) and (S[I + 1] = '-') then
    begin
      Result := Result + Painted(P.Op, '--', True);
      Inc(I, 2);
    end
    { one dash: the 1-6 of feet and inches, part of the length - or at the
      very start, the minus that flips a rectangle's side }
    else if S[I] = '-' then
    begin
      if Trim(Copy(S, 1, I - 1)) = '' then Result := Result + Painted(P.Op, '-', True)
      else Result := Result + Painted(P.Units, '-', True);
      Inc(I);
    end
    else if S[I] in ['+', '*', '/', '(', ')', '='] then
    begin
      Result := Result + Painted(P.Op, S[I], True);
      Inc(I);
    end
    else if S[I] in ['[', ']', '<', '>', ',', ';'] then
    begin
      Result := Result + Painted(P.Dim, S[I], True);
      Inc(I);
    end
    else if IsLetter(S[I]) then
    begin
      J := I;
      while (J <= Length(S)) and IsLetter(S[J]) do Inc(J);
      W := LowerCase(Copy(S, I, J - I));
      { the x of 8x10 - and of 3x, the count of an array }
      if W = 'x' then Result := Result + Painted(P.Sep, Copy(S, I, J - I), True)
      else if (W = 'ft') or (W = 'in') or (W = 'mm') or (W = 'cm') or (W = 'm') or
              (W = 'deg') or (W = 's') then
        Result := Result + Painted(P.Units, Copy(S, I, J - I), True)
      else Result := Result + Painted(P.Text, Copy(S, I, J - I));
      I := J;
    end
    else
    begin
      Result := Result + Painted(P.Text, S[I]);
      Inc(I);
    end;
  end;
end;

end.

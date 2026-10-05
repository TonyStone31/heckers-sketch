unit hsGroupData;

{ A group's Data: what the tool that made it knew, so the group can be
  reopened in that tool or reprinted later.  Written in Heck's shape:
  "name = value" lines, and a bare name opening a block up to "end".  Values
  are numbers, true/false, 'quoted text', or comma lists of numbers or x y z
  points.  Every line is kept as read, so data from a newer version survives. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, hsDrawing, hsText;

type
  TDataNums = array of Double;

  { one line of the data, or a block and what is in it }
  TDataNode = class
  private
    FKids: TList;
  public
    Key, Value: string;
    Block: Boolean;
    constructor Create;
    destructor Destroy; override;
    function Count: Integer;
    function Kid(I: Integer): TDataNode;
    function Add(const AKey, AValue: string; ABlock: Boolean): TDataNode;
    { the first line or block called K, or nil }
    function Find(const K: string): TDataNode;
    { every block called K, in order }
    function Blocks(const K: string): TList;
    function Has(const K: string): Boolean;
    function Num(const K: string; Def: Double = 0): Double;
    function Int(const K: string; Def: Integer = 0): Integer;
    function Bool(const K: string; Def: Boolean = False): Boolean;
    function Text(const K: string; const Def: string = ''): string;
    function Nums(const K: string): TDataNums;
    function Pts(const K: string): TP3Array;
  end;

  { the data a line at a time - Open a block, and Close it }
  TDataWriter = class
  private
    FL: TStringList;
    FDepth: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Num(const K: string; V: Double);
    procedure Int(const K: string; V: Integer);
    procedure Bool(const K: string; V: Boolean);
    procedure Text(const K, V: string);
    procedure Nums(const K: string; const V: array of Double);
    procedure Pts(const K: string; const P: array of TP3);
    procedure Open(const K: string);
    procedure Close;
    { every block closed, the lines with a line break between }
    function Done: string;
  end;

{ Never nil: a line that makes no sense is kept with no value, and an
  extra "end" is ignored. }
function ReadData(const S: string): TDataNode;
{ the lines indented two spaces per block, for the source window }
function DataIndented(const S: string): TStringList;
{ always a decimal point whatever the locale, and no extra digits }
function DataNum(V: Double): string;
{ a text as the data writes it, and back }
function DataQuote(const S: string): string;
function DataUnquote(const V: string): string;

implementation

function DataNum(V: Double): string;
begin
  if IsNan(V) or IsInfinite(V) then Exit('0');
  Result := FloatToStrF(V, ffGeneral, 15, 0, DotFS);
end;

{ a coordinate to 0.00001 ft (about a thousandth of an inch) }
function PtNum(V: Double): string;
begin
  if IsNan(V) or IsInfinite(V) then Exit('0');
  Result := FormatFloat('0.#####', V, DotFS);
  if Result = '-0' then Result := '0';
end;

function DataQuote(const S: string): string;
var
  T: string;
begin
  T := StringReplace(S, '\', '\\', [rfReplaceAll]);
  T := StringReplace(T, #13#10, '\n', [rfReplaceAll]);
  T := StringReplace(T, #10, '\n', [rfReplaceAll]);
  T := StringReplace(T, #13, '\n', [rfReplaceAll]);
  Result := '''' + StringReplace(T, '''', '''''', [rfReplaceAll]) + '''';
end;

function DataUnquote(const V: string): string;
var
  T: string;
  I: Integer;
begin
  T := Trim(V);
  if (Length(T) >= 2) and (T[1] = '''') and (T[Length(T)] = '''') then
    T := StringReplace(Copy(T, 2, Length(T) - 2), '''''', '''', [rfReplaceAll]);
  Result := '';
  I := 1;
  while I <= Length(T) do
  begin
    if (T[I] = '\') and (I < Length(T)) then
    begin
      if T[I + 1] = 'n' then Result := Result + LineEnding
      else Result := Result + T[I + 1];
      Inc(I, 2);
      Continue;
    end;
    Result := Result + T[I];
    Inc(I);
  end;
end;

{ ---- the reader's side ---- }

constructor TDataNode.Create;
begin
  inherited Create;
  FKids := TList.Create;
end;

destructor TDataNode.Destroy;
var
  I: Integer;
begin
  for I := 0 to FKids.Count - 1 do TDataNode(FKids[I]).Free;
  FKids.Free;
  inherited Destroy;
end;

function TDataNode.Count: Integer;
begin
  Result := FKids.Count;
end;

function TDataNode.Kid(I: Integer): TDataNode;
begin
  Result := TDataNode(FKids[I]);
end;

function TDataNode.Add(const AKey, AValue: string; ABlock: Boolean): TDataNode;
begin
  Result := TDataNode.Create;
  Result.Key := AKey;
  Result.Value := AValue;
  Result.Block := ABlock;
  FKids.Add(Result);
end;

function TDataNode.Find(const K: string): TDataNode;
var
  I: Integer;
  L: string;
begin
  L := LowerCase(K);
  for I := 0 to FKids.Count - 1 do
    if TDataNode(FKids[I]).Key = L then Exit(TDataNode(FKids[I]));
  Result := nil;
end;

function TDataNode.Blocks(const K: string): TList;
var
  I: Integer;
  L: string;
begin
  L := LowerCase(K);
  Result := TList.Create;
  for I := 0 to FKids.Count - 1 do
    if TDataNode(FKids[I]).Block and (TDataNode(FKids[I]).Key = L) then Result.Add(FKids[I]);
end;

function TDataNode.Has(const K: string): Boolean;
begin
  Result := Find(K) <> nil;
end;

function TDataNode.Num(const K: string; Def: Double): Double;
var
  N: TDataNode;
begin
  N := Find(K);
  if (N = nil) or N.Block then Exit(Def);
  Result := StrToFloatDef(Trim(N.Value), Def, DotFS);
end;

function TDataNode.Int(const K: string; Def: Integer): Integer;
var
  V: Double;
begin
  V := Num(K, Def);
  if (V > MaxInt) or (V < -MaxInt) then Result := Def else Result := Round(V);
end;

function TDataNode.Bool(const K: string; Def: Boolean): Boolean;
var
  N: TDataNode;
  V: string;
begin
  N := Find(K);
  if (N = nil) or N.Block then Exit(Def);
  V := LowerCase(Trim(N.Value));
  if (V = 'true') or (V = '1') or (V = 'yes') then Result := True
  else if (V = 'false') or (V = '0') or (V = 'no') then Result := False
  else Result := Def;
end;

function TDataNode.Text(const K: string; const Def: string): string;
var
  N: TDataNode;
begin
  N := Find(K);
  if (N = nil) or N.Block then Exit(Def);
  Result := DataUnquote(N.Value);
end;

function TDataNode.Nums(const K: string): TDataNums;
var
  N: TDataNode;
  Parts: TStringArray;
  I: Integer;
begin
  SetLength(Result, 0);
  N := Find(K);
  if (N = nil) or N.Block or (Trim(N.Value) = '') then Exit;
  Parts := N.Value.Split([',']);
  SetLength(Result, Length(Parts));
  for I := 0 to High(Parts) do Result[I] := StrToFloatDef(Trim(Parts[I]), 0, DotFS);
end;

function TDataNode.Pts(const K: string): TP3Array;
var
  N: TDataNode;
  Parts, W: TStringArray;
  I, C: Integer;
begin
  SetLength(Result, 0);
  N := Find(K);
  if (N = nil) or N.Block or (Trim(N.Value) = '') then Exit;
  Parts := N.Value.Split([',']);
  SetLength(Result, Length(Parts));
  C := 0;
  for I := 0 to High(Parts) do
  begin
    W := Trim(Parts[I]).Split([' '], TStringSplitOptions.ExcludeEmpty);
    if Length(W) < 2 then Continue;
    Result[C].X := StrToFloatDef(W[0], 0, DotFS);
    Result[C].Y := StrToFloatDef(W[1], 0, DotFS);
    if Length(W) >= 3 then Result[C].Z := StrToFloatDef(W[2], 0, DotFS) else Result[C].Z := 0;
    Inc(C);
  end;
  SetLength(Result, C);
end;

{ the "=" that is not in a text, or 0 }
function EqualsAt(const Line: string): Integer;
var
  K: Integer;
  InText: Boolean;
begin
  InText := False;
  for K := 1 to Length(Line) do
  begin
    if Line[K] = '''' then InText := not InText
    else if (Line[K] = '=') and not InText then Exit(K);
  end;
  Result := 0;
end;

function ReadData(const S: string): TDataNode;
var
  Lines: TStringList;
  Stack: TList;
  I, E: Integer;
  Line: string;
  Top, N: TDataNode;
begin
  Result := TDataNode.Create;
  Result.Block := True;
  Lines := TStringList.Create;
  Stack := TList.Create;
  try
    Lines.Text := S;
    Top := Result;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if Line = '' then Continue;
      if LowerCase(Line) = 'end' then
      begin
        if Stack.Count > 0 then
        begin
          Top := TDataNode(Stack[Stack.Count - 1]);
          Stack.Delete(Stack.Count - 1);
        end;
        Continue;
      end;
      E := EqualsAt(Line);
      if E > 0 then
        Top.Add(LowerCase(Trim(Copy(Line, 1, E - 1))), Trim(Copy(Line, E + 1, MaxInt)), False)
      else
      begin
        N := Top.Add(LowerCase(Line), '', True);
        Stack.Add(Top);
        Top := N;
      end;
    end;
  finally
    Stack.Free;
    Lines.Free;
  end;
end;

function DataIndented(const S: string): TStringList;
var
  Lines: TStringList;
  I, Depth: Integer;
  Line: string;
begin
  Result := TStringList.Create;
  Lines := TStringList.Create;
  try
    Lines.Text := S;
    Depth := 0;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if Line = '' then Continue;
      if LowerCase(Line) = 'end' then
      begin
        { a stray "end" would close the group's data block itself; drop it }
        if Depth = 0 then Continue;
        Dec(Depth);
        Result.Add(StringOfChar(' ', Depth * 2) + Line);
        Continue;
      end;
      Result.Add(StringOfChar(' ', Depth * 2) + Line);
      if EqualsAt(Line) = 0 then Inc(Depth);
    end;
    { close any block left open }
    while Depth > 0 do
    begin
      Dec(Depth);
      Result.Add(StringOfChar(' ', Depth * 2) + 'end');
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- the writer's side ---- }

constructor TDataWriter.Create;
begin
  inherited Create;
  FL := TStringList.Create;
end;

destructor TDataWriter.Destroy;
begin
  FL.Free;
  inherited Destroy;
end;

procedure TDataWriter.Num(const K: string; V: Double);
begin
  FL.Add(K + ' = ' + DataNum(V));
end;

procedure TDataWriter.Int(const K: string; V: Integer);
begin
  FL.Add(K + ' = ' + IntToStr(V));
end;

procedure TDataWriter.Bool(const K: string; V: Boolean);
begin
  if V then FL.Add(K + ' = true') else FL.Add(K + ' = false');
end;

procedure TDataWriter.Text(const K, V: string);
begin
  FL.Add(K + ' = ' + DataQuote(V));
end;

procedure TDataWriter.Nums(const K: string; const V: array of Double);
var
  I: Integer;
  S: string;
begin
  S := '';
  for I := 0 to High(V) do
  begin
    if I > 0 then S := S + ', ';
    S := S + DataNum(V[I]);
  end;
  FL.Add(K + ' = ' + S);
end;

procedure TDataWriter.Pts(const K: string; const P: array of TP3);
var
  I: Integer;
  S: string;
begin
  S := '';
  for I := 0 to High(P) do
  begin
    if I > 0 then S := S + ', ';
    S := S + PtNum(P[I].X) + ' ' + PtNum(P[I].Y) + ' ' + PtNum(P[I].Z);
  end;
  FL.Add(K + ' = ' + S);
end;

procedure TDataWriter.Open(const K: string);
begin
  FL.Add(K);
  Inc(FDepth);
end;

procedure TDataWriter.Close;
begin
  if FDepth = 0 then Exit;
  FL.Add('end');
  Dec(FDepth);
end;

function TDataWriter.Done: string;
var
  I: Integer;
begin
  while FDepth > 0 do Close;
  Result := '';
  for I := 0 to FL.Count - 1 do
  begin
    if I > 0 then Result := Result + #10;
    Result := Result + FL[I];
  end;
end;

end.

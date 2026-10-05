unit hsDxf;

{ Writes DXF in the old R12 dialect ("AC1009"), since cutting-table software
  is old and reads R12 without complaint.
  A DXF has no units of its own: imperial goes out in inches, metric in
  millimeters, and the file says which in a comment and in $INSUNITS. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, hsText;

type
  TDxfWriter = class
  private
    FEnts: TStringList;
    FLayers: TStringList;
    FMinX, FMinY, FMinZ, FMaxX, FMaxY, FMaxZ: Double;
    FAny: Boolean;
    procedure Extend(X, Y, Z: Double);
    procedure Put(Code: Integer; const Value: string);
    procedure PutF(Code: Integer; V: Double);
  public
    constructor Create;
    destructor Destroy; override;
    { Declare layers before use so they show up in the layer table, not only
      on the entities.  Color is an AutoCAD color index. }
    procedure Layer(const Name: string; Color: Integer; Dashed: Boolean = False);
    procedure Line(const Lay: string; X1, Y1, Z1, X2, Y2, Z2: Double);
    procedure Face3D(const Lay: string; const X, Y, Z: array of Double);
    procedure Text(const Lay: string; X, Y, Z, Height: Double; const S: string);
    { Inches says which units the numbers were written in. }
    procedure SaveTo(L: TStrings; Inches: Boolean);
  end;

implementation

constructor TDxfWriter.Create;
begin
  inherited Create;
  FEnts := TStringList.Create;
  FLayers := TStringList.Create;
  FAny := False;
end;

destructor TDxfWriter.Destroy;
begin
  FEnts.Free;
  FLayers.Free;
  inherited Destroy;
end;

procedure TDxfWriter.Extend(X, Y, Z: Double);
begin
  if not FAny then
  begin
    FMinX := X; FMaxX := X; FMinY := Y; FMaxY := Y; FMinZ := Z; FMaxZ := Z;
    FAny := True;
    Exit;
  end;
  if X < FMinX then FMinX := X; if X > FMaxX then FMaxX := X;
  if Y < FMinY then FMinY := Y; if Y > FMaxY then FMaxY := Y;
  if Z < FMinZ then FMinZ := Z; if Z > FMaxZ then FMaxZ := Z;
end;

procedure TDxfWriter.Put(Code: Integer; const Value: string);
begin
  FEnts.Add(Format('%3d', [Code]));
  FEnts.Add(Value);
end;

procedure TDxfWriter.PutF(Code: Integer; V: Double);
begin
  Put(Code, FormatFloat('0.######', V, DotFS));
end;

procedure TDxfWriter.Layer(const Name: string; Color: Integer; Dashed: Boolean);
begin
  if FLayers.IndexOfName(Name) >= 0 then Exit;
  FLayers.Values[Name] := Format('%d,%d', [Color, Ord(Dashed)]);
end;

procedure TDxfWriter.Line(const Lay: string; X1, Y1, Z1, X2, Y2, Z2: Double);
begin
  Put(0, 'LINE');
  Put(8, Lay);
  PutF(10, X1); PutF(20, Y1); PutF(30, Z1);
  PutF(11, X2); PutF(21, Y2); PutF(31, Z2);
  Extend(X1, Y1, Z1);
  Extend(X2, Y2, Z2);
end;

procedure TDxfWriter.Face3D(const Lay: string; const X, Y, Z: array of Double);
var
  I, N: Integer;
begin
  { A 3DFACE has three or four corners.  Bigger faces are fanned from the
    first corner: exact when convex, close enough for a shop drawing when not. }
  N := Length(X);
  if N < 3 then Exit;
  if N <= 4 then
  begin
    Put(0, '3DFACE');
    Put(8, Lay);
    for I := 0 to N - 1 do
    begin
      PutF(10 + I, X[I]); PutF(20 + I, Y[I]); PutF(30 + I, Z[I]);
      Extend(X[I], Y[I], Z[I]);
    end;
    if N = 3 then
    begin
      PutF(13, X[2]); PutF(23, Y[2]); PutF(33, Z[2]);
    end;
    Exit;
  end;
  for I := 1 to N - 2 do
  begin
    Put(0, '3DFACE');
    Put(8, Lay);
    PutF(10, X[0]);     PutF(20, Y[0]);     PutF(30, Z[0]);
    PutF(11, X[I]);     PutF(21, Y[I]);     PutF(31, Z[I]);
    PutF(12, X[I + 1]); PutF(22, Y[I + 1]); PutF(32, Z[I + 1]);
    PutF(13, X[I + 1]); PutF(23, Y[I + 1]); PutF(33, Z[I + 1]);
    Extend(X[I], Y[I], Z[I]);
  end;
  Extend(X[0], Y[0], Z[0]);
  Extend(X[N - 1], Y[N - 1], Z[N - 1]);
end;

procedure TDxfWriter.Text(const Lay: string; X, Y, Z, Height: Double;
  const S: string);
begin
  if Trim(S) = '' then Exit;
  Put(0, 'TEXT');
  Put(8, Lay);
  PutF(10, X); PutF(20, Y); PutF(30, Z);
  PutF(40, Height);
  Put(1, S);
  Extend(X, Y, Z);
end;

procedure TDxfWriter.SaveTo(L: TStrings; Inches: Boolean);
var
  I, Color, Dashed: Integer;
  Name, V: string;
begin
  L.Clear;
  L.Add('999');
  if Inches then L.Add('Heckers Sketch - units are inches')
  else L.Add('Heckers Sketch - units are millimeters');

  { --- header --- }
  L.Add('  0'); L.Add('SECTION');
  L.Add('  2'); L.Add('HEADER');
  L.Add('  9'); L.Add('$ACADVER');
  L.Add('  1'); L.Add('AC1009');
  L.Add('  9'); L.Add('$INSUNITS');
  L.Add(' 70'); if Inches then L.Add('1') else L.Add('4');
  if FAny then
  begin
    L.Add('  9'); L.Add('$EXTMIN');
    L.Add(' 10'); L.Add(FormatFloat('0.######', FMinX, DotFS));
    L.Add(' 20'); L.Add(FormatFloat('0.######', FMinY, DotFS));
    L.Add(' 30'); L.Add(FormatFloat('0.######', FMinZ, DotFS));
    L.Add('  9'); L.Add('$EXTMAX');
    L.Add(' 10'); L.Add(FormatFloat('0.######', FMaxX, DotFS));
    L.Add(' 20'); L.Add(FormatFloat('0.######', FMaxY, DotFS));
    L.Add(' 30'); L.Add(FormatFloat('0.######', FMaxZ, DotFS));
  end;
  L.Add('  0'); L.Add('ENDSEC');

  { --- tables: two line types and the layers --- }
  L.Add('  0'); L.Add('SECTION');
  L.Add('  2'); L.Add('TABLES');
  L.Add('  0'); L.Add('TABLE');
  L.Add('  2'); L.Add('LTYPE');
  L.Add(' 70'); L.Add('2');
  L.Add('  0'); L.Add('LTYPE');
  L.Add('  2'); L.Add('CONTINUOUS');
  L.Add(' 70'); L.Add('0');
  L.Add('  3'); L.Add('Solid line');
  L.Add(' 72'); L.Add('65');
  L.Add(' 73'); L.Add('0');
  L.Add(' 40'); L.Add('0');
  L.Add('  0'); L.Add('LTYPE');
  L.Add('  2'); L.Add('DASHED');
  L.Add(' 70'); L.Add('0');
  L.Add('  3'); L.Add('Dashed line');
  L.Add(' 72'); L.Add('65');
  L.Add(' 73'); L.Add('2');
  L.Add(' 40'); L.Add('0.75');
  L.Add(' 49'); L.Add('0.5');
  L.Add(' 49'); L.Add('-0.25');
  L.Add('  0'); L.Add('ENDTAB');
  L.Add('  0'); L.Add('TABLE');
  L.Add('  2'); L.Add('LAYER');
  L.Add(' 70'); L.Add(IntToStr(FLayers.Count));
  for I := 0 to FLayers.Count - 1 do
  begin
    Name := FLayers.Names[I];
    V := FLayers.ValueFromIndex[I];
    Color := StrToIntDef(Copy(V, 1, Pos(',', V) - 1), 7);
    Dashed := StrToIntDef(Copy(V, Pos(',', V) + 1, MaxInt), 0);
    L.Add('  0'); L.Add('LAYER');
    L.Add('  2'); L.Add(Name);
    L.Add(' 70'); L.Add('0');
    L.Add(' 62'); L.Add(IntToStr(Color));
    L.Add('  6'); if Dashed = 1 then L.Add('DASHED') else L.Add('CONTINUOUS');
  end;
  L.Add('  0'); L.Add('ENDTAB');
  L.Add('  0'); L.Add('ENDSEC');

  { --- the entities themselves --- }
  L.Add('  0'); L.Add('SECTION');
  L.Add('  2'); L.Add('ENTITIES');
  L.AddStrings(FEnts);
  L.Add('  0'); L.Add('ENDSEC');
  L.Add('  0'); L.Add('EOF');
end;


end.

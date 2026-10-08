unit hsHeckWriter;

{ Writes a sheet as Heck: the saved file (hsHeckFile) and
  the source window's text.  If this unit and the doc disagree, find out which
  is wrong before going further.  Lengths are written the friendly way only
  when exact; a solid's corners are named once; a point along an axis from an
  earlier one is written as a step from it; only non-default settings are written. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, hsDrawing, hsFaceFinder, hsImpliedFaces, hsGroupData, hsText;

const
  { the first line of every Heck file }
  HECK_MAGIC = 'HeckersSketch 2';

  { the colors Heck has names for, as TColor; any other is written #RRGGBB }
  HECK_COLOR_NAMES: array[0..9] of string = ('black', 'white', 'gray', 'red',
    'orange', 'yellow', 'green', 'blue', 'purple', 'brown');
  HECK_COLOR_VALUES: array[0..9] of Integer = ($000000, $FFFFFF, $808080,
    $0000FF, $3CB0FF, $00FFFF, $008000, $FF0000, $800080, $2A2AA5);

  { a box's sides, in the order the reader makes them; "open = top" names them }
  BOX_SIDES: array[0..5] of string = ('bottom', 'top', 'south', 'east', 'north', 'west');

  { Sides of a circle when none are given: what the circle tool draws and
    what a one-line circle reads back with. }
  HECK_SIDES = 24;
  { drawings up to this size leave implied faces unwritten; see ReadBack }
  IMPLY_LIMIT = 20000;
  { a million-millionth of a foot }
  FRIENDLY_TOL = 1E-12;
  { A value this close to a friendly length is written as the friendly one.
    It absorbs arithmetic noise and the six-place feet rounding that older
    drawings still carry (1.4 inches stored as 1.400004). }
  ROUNDING_NOISE = 1.2E-6;    { a difference of two such numbers has twice the error }

{ L gets the text.  LineThing gives each line's entity, or -1.  First and
  Last give an entity's lines; First > Last when it has none of its own (an
  edge a solid's faces imply). }
{ Hints, if given, gets a line per line of L: where a point written as a
  step actually is, for the source window's hover; empty otherwise. }
{ Names, if given, gets "line|name=place" for every named point, ring
  corners included, where line is the "points" line of the naming block.
  A name is looked up from where it is used by taking the nearest block above. }
procedure WriteFormat2(D: TWorkDoc; const SheetName: string; U: TUnitSystem;
  L: TStrings; out First, Last, LineThing: TIntArrayW; Hints: TStrings = nil;
  Names: TStrings = nil; SheetLines: TStrings = nil; Quick: Boolean = False);

type
  TBoolArray = array of Boolean;
  { The reader.  Implied comes back with one flag per thing: True for a face
    the reader would have made by itself from its scope's edges, facing the
    same way. }
  TReadBack = function(L: TStrings; D: TWorkDoc; U: TUnitSystem;
    out ErrLine: Integer; out Err: string; out Implied: TBoolArray): Boolean;

var
  { The reader, so the writer can see what its own text becomes; hsHeckReader
    sets it.  Which loops the reader closes depends on the numbers as written
    and rounded, so the writer writes once with every face, reads that back,
    and leaves out exactly the faces the reader restored.  Without a reader
    every face is written, which is never wrong, only longer. }
  ReadBack: TReadBack = nil;

{ A whole circle.  Older drawings, rounded to six places, hold the circle
  tool's circles as sweeps a hair short of 2 pi (359.9999824 degrees). }
function FullCircle(Sweep: Double): Boolean;

{ A fingerprint of solid G's geometry in group Part: its faces, lines and
  circles, in any order, to a hundred-thousandth of a foot.  A statement the
  writer cannot work out from geometry (a loft) is kept with the fingerprint
  of what it made, and written back only while that still matches. }
function SolidPrint(D: TWorkDoc; G, Part: Integer): string;

{ the two directions a flat thing's angles are measured in: from east when
  facing up or down, otherwise from its level line (up x facing) }
procedure SpecAxes(const F: TP3; out AU, AV: TP3);

{ One length as the file writes it; always positive, since the direction
  word carries the sign. }
function Len2(V: Double; U: TUnitSystem): string;
{ a place ("1" east, 1" north, 0 up") or, with Offset, a step giving only
  what changes }
function Place2(const P: TP3; U: TUnitSystem; Offset: Boolean): string;

implementation

uses
  Contnrs;

function FullCircle(Sweep: Double): Boolean;
begin
  Result := Abs(Abs(Sweep) - 2 * Pi) < 1E-5;
end;

function SolidPrint(D: TWorkDoc; G, Part: Integer): string;
var
  All, One: TStringList;
  I, K, H: Integer;
  Hash: QWord;
  Txt: string;

  function Key(const P: TP3): string;
  begin
    Result := Format('%d,%d,%d', [Round(P.X * 1E5), Round(P.Y * 1E5), Round(P.Z * 1E5)]);
  end;

begin
  All := TStringList.Create;
  One := TStringList.Create;
  try
    for I := 0 to D.Live - 1 do
    begin
      { a group's record keeps its own number in Grp; it is no solid's }
      if (D[I].Grp <> G) or (D[I].Part <> Part) or (D[I].Kind = ekPart) then Continue;
      One.Clear;
      case D[I].Kind of
        ekFace:
          begin
            for K := 0 to High(D[I].Poly) do One.Add(Key(D[I].Poly[K]));
            for H := 0 to High(D[I].Holes) do
              for K := 0 to High(D[I].Holes[H]) do One.Add('h' + Key(D[I].Holes[H][K]));
          end;
        ekLine:
          begin
            One.Add(Key(D[I].A));
            One.Add(Key(D[I].B));
            if D[I].Soft then One.Add('soft');
          end;
        ekArc:
          begin
            One.Add(Key(D[I].C));
            One.Add(IntToStr(Round(D[I].R * 1E5)));
          end;
      end;
      One.Sort;
      All.Add(IntToStr(Ord(D[I].Kind)) + ':' + One.CommaText);
    end;
    All.Sort;
    { FNV-1a over the lot; it wraps on purpose }
    Txt := All.Text;
    Hash := QWord($CBF29CE484222325);
    {$PUSH}{$Q-}{$R-}
    for I := 1 to Length(Txt) do
    begin
      Hash := Hash xor Ord(Txt[I]);
      Hash := Hash * QWord($100000001B3);
    end;
    {$POP}
    Result := IntToHex(Hash, 16) + '.' + IntToStr(All.Count);
  finally
    One.Free;
    All.Free;
  end;
end;

var
  { pass one is running: every face is written and no noface }
  InPass1: Boolean = False;

type
  TPt = record
    P: TP3;
    Read: TP3;           { where the reader will put it, from the text }
    Name: string;
    Ring: Integer;       { which ring it is a corner of, or -1 }
    InHole: Boolean;     { a corner of a hole, and of no outline }
  end;
  TPts = array of TPt;

  { Corners spaced evenly around a circle, given once: center, size, count,
    facing and where the first one is. }
  TRing = record
    Name: string;
    C, Facing: TP3;
    R, Starts: Double;
    N: Integer;
  end;
  TRings = array of TRing;

function Len2(V: Double; U: TUnitSystem): string;
var
  Inches, R, Frac: Double;
  Feet, Whole, Num, Den: Integer;
  S: string;
begin
  V := Abs(V);
  if V < FRIENDLY_TOL then Exit('0');
  if U = usMetric then
  begin
    { Stored in feet whatever the sheet shows; millimeters to a thousandth
      when exact, in full otherwise. }
    R := V * 304.8;
    if Abs(Round(R * 1000) / 1000 / 304.8 - V) <= FRIENDLY_TOL then
      S := FloatToStrF(Round(R * 1000) / 1000, ffGeneral, 12, 0, DotFS)
    else
      S := FloatToStrF(R, ffGeneral, 15, 0, DotFS);
    Exit(S);
  end;
  Inches := V * 12;
  R := Round(Inches * 64) / 64;
  if Abs(R / 12 - V) > ROUNDING_NOISE then
  begin
    { Not a sixty-fourth: write a short decimal if it is one (within the
      rounding noise), otherwise in full. }
    R := Round(Inches * 1000) / 1000;
    if Abs(R / 12 - V) <= ROUNDING_NOISE then
      Exit(FloatToStrF(R, ffGeneral, 12, 0, DotFS) + '"');
    Exit(FloatToStrF(Inches, ffGeneral, 12, 0, DotFS) + '"');
  end;
  Feet := Trunc(R / 12 + 1E-9);
  R := R - Feet * 12;
  Whole := Trunc(R + 1E-9);
  Frac := R - Whole;
  Num := Round(Frac * 64);
  Den := 64;
  while (Num > 0) and (Num mod 2 = 0) do begin Num := Num div 2; Den := Den div 2; end;
  S := '';
  if Feet > 0 then S := IntToStr(Feet) + '''';
  if (Whole > 0) or (Num > 0) then
  begin
    if S <> '' then S := S + ' ';
    if Whole > 0 then S := S + IntToStr(Whole);
    if Num > 0 then
    begin
      if Whole > 0 then S := S + ' ';
      S := S + IntToStr(Num) + '/' + IntToStr(Den);
    end;
    S := S + '"';
  end;
  { Anything that rounds to nothing must still write "0", or a step like
    "+ 14" west,  north" has a missing number. }
  if S = '' then S := '0';
  Result := S;
end;

{ What a length reads back as once written.  Steps are taken from where
  the reader will be, not where the drawing is, so each corner reads back as
  its own rounded self; otherwise forty-eight tiny errors drift a disk off
  its ring. }
function AsRead(V: Double; U: TUnitSystem): Double;
var
  A, Inches, R: Double;
begin
  A := Abs(V);
  Result := 0;
  if A < FRIENDLY_TOL then Exit;
  if U = usMetric then
  begin
    R := A * 304.8;
    if Abs(Round(R * 1000) / 1000 / 304.8 - A) <= FRIENDLY_TOL then
      Result := Round(R * 1000) / 1000 / 304.8
    else
      Result := StrToFloat(FloatToStrF(R, ffGeneral, 15, 0, DotFS), DotFS) / 304.8;
  end
  else
  begin
    Inches := A * 12;
    R := Round(Inches * 64) / 64;
    if Abs(R / 12 - A) > ROUNDING_NOISE then
    begin
      R := Round(Inches * 1000) / 1000;
      if Abs(R / 12 - A) <= ROUNDING_NOISE then Result := R / 12
      else Result := StrToFloat(FloatToStrF(Inches, ffGeneral, 12, 0, DotFS), DotFS) / 12;
    end
    else
      Result := R / 12;
  end;
  if V < 0 then Result := -Result;
end;

function AsRead3(const P: TP3; U: TUnitSystem): TP3;
begin
  Result := P3(AsRead(P.X, U), AsRead(P.Y, U), AsRead(P.Z, U));
end;

{ A place always gives all three parts ("1" east, 1" north, 0 up"), so the
  height is visible; "0 up" is on the floor.  West, south and down carry the
  sign, so no number is negative.  A step gives only the parts that change. }
function Place2(const P: TP3; U: TUnitSystem; Offset: Boolean): string;

  procedure Part(V: Double; const Plus, Minus: string);
  var
    S: string;
  begin
    S := Len2(V, U);
    { a step gives only what changes, and parts that write as zero are dropped }
    if Offset and (S = '0') then Exit;
    if Result <> '' then Result := Result + ', ';
    if V >= -FRIENDLY_TOL then Result := Result + S + ' ' + Plus
    else Result := Result + S + ' ' + Minus;
  end;

begin
  Result := '';
  Part(P.X, 'east', 'west');
  Part(P.Y, 'north', 'south');
  Part(P.Z, 'up', 'down');
  if Result = '' then Result := '0 east';
end;

function SameP(const A, B: TP3): Boolean;
begin
  Result := (Abs(A.X - B.X) < 1E-9) and (Abs(A.Y - B.Y) < 1E-9) and
            (Abs(A.Z - B.Z) < 1E-9);
end;

{ how many of the three parts of a difference are not zero }
function AxesUsed(const V: TP3): Integer;
begin
  Result := Ord(Abs(V.X) > 1E-9) + Ord(Abs(V.Y) > 1E-9) + Ord(Abs(V.Z) > 1E-9);
end;

function FacingWord(const N: TP3): string;
begin
  Result := '';
  if AxesUsed(N) <> 1 then Exit;
  if N.X > 0.5 then Result := 'east' else if N.X < -0.5 then Result := 'west'
  else if N.Y > 0.5 then Result := 'north' else if N.Y < -0.5 then Result := 'south'
  else if N.Z > 0.5 then Result := 'up' else Result := 'down';
end;

{ The two directions a flat thing's angles are measured in ("facing").  Facing up or down: from east.  Otherwise from its level line,
  up x facing.  V is facing x U, so turning is counterclockwise seen from the
  side it faces. }
procedure SpecAxes(const F: TP3; out AU, AV: TP3);
var
  L: Double;
begin
  if (Abs(F.X) < 1E-9) and (Abs(F.Y) < 1E-9) then
    AU := P3(1, 0, 0)
  else
  begin
    AU := P3(-F.Y, F.X, 0);                       { up x facing }
    L := Sqrt(AU.X * AU.X + AU.Y * AU.Y);
    AU := P3(AU.X / L, AU.Y / L, 0);
  end;
  AV := P3(F.Y * AU.Z - F.Z * AU.Y, F.Z * AU.X - F.X * AU.Z, F.X * AU.Y - F.Y * AU.X);
end;

function Deg2(A: Double): string;
begin
  A := RadToDeg(A);
  if Abs(A - Round(A * 1000) / 1000) < 1E-7 then A := Round(A * 1000) / 1000;
  if Abs(A) < 1E-9 then A := 0;
  Result := FloatToStrF(A, ffGeneral, 10, 0, DotFS) + '°';
end;

{ "up", "east"... or for a tilted thing, how far it leans from up and which
  way: "up, leaning 30° toward east".  When the angles are not clean, the
  three numbers, which are always right. }
function Facing2(const N: TP3): string;
var
  Tilt, Head, T2, H2: Double;
  W: string;
  Back: TP3;

  { a plain decimal, never 8.28E-15: noise that small is nought }
  function Way(V: Double; const Plus, Minus: string): string;
  begin
    if Abs(V) < 1E-9 then V := 0;
    if V < 0 then Result := FormatFloat('0.#########', -V, DotFS) + ' ' + Minus
    else Result := FormatFloat('0.#########', V, DotFS) + ' ' + Plus;
  end;

begin
  Result := FacingWord(N);
  if Result <> '' then Exit;
  Tilt := ArcCos(EnsureRange(N.Z, -1, 1));
  Head := ArcTan2(N.Y, N.X);
  T2 := DegToRad(Round(RadToDeg(Tilt) * 1000) / 1000);
  H2 := DegToRad(Round(RadToDeg(Head) * 1000) / 1000);
  Back := P3(Sin(T2) * Cos(H2), Sin(T2) * Sin(H2), Cos(T2));
  if SameP(Back, N) then
  begin
    if Abs(H2) < 1E-9 then W := 'east'
    else if Abs(H2 - Pi / 2) < 1E-9 then W := 'north'
    else if Abs(Abs(H2) - Pi) < 1E-9 then W := 'west'
    else if Abs(H2 + Pi / 2) < 1E-9 then W := 'south'
    else W := Deg2(H2) + ' round from east';
    Exit('up, leaning ' + Deg2(T2) + ' toward ' + W);
  end;
  { the word carries the sign, as in a place: 0.28 south, not -0.28 north }
  Result := Way(N.X, 'east', 'west') + ', ' + Way(N.Y, 'north', 'south') + ', ' + Way(N.Z, 'up', 'down');
end;

function Color2(C: TColor): string;
var
  I: Integer;
begin
  C := C and $FFFFFF;
  for I := 0 to High(HECK_COLOR_NAMES) do
    if C = HECK_COLOR_VALUES[I] then Exit(HECK_COLOR_NAMES[I]);
  Result := Format('#%.2x%.2x%.2x', [C and $FF, (C shr 8) and $FF, (C shr 16) and $FF]);
end;

procedure WriteFormat2(D: TWorkDoc; const SheetName: string; U: TUnitSystem;
  L: TStrings; out First, Last, LineThing: TIntArrayW; Hints: TStrings = nil;
  Names: TStrings = nil; SheetLines: TStrings = nil; Quick: Boolean = False);
var
  NextHint: string;
  DefInk: TColor;
  DefWidth: Single;
  NLine: Integer;
  Circles: TIntArrayW;        { the whole circles on the sheet: c1, c2... }
  CircleNames: TStringArray;  { their names: the one each was given, or c1, c2... }
  { the solid being written has corners named by the text, so a name made
    up for another corner has to be checked against them }
  Given: Boolean;
  { from pass one: the faces the reader restores by itself, and the loops it
    closes that are not faces of the drawing }
  ImpliedGeom: array of Boolean;
  NoFaceLoops: TLoopArray;
  NoFaceScope: array of Integer;   { the Grp each loop was closed in }
  NoFacePart: array of Integer;    { and the group (Part) it is in }

  function CircleName(I: Integer): string;
  var
    K: Integer;
  begin
    Result := '';
    for K := 0 to High(Circles) do
      if Circles[K] = I then Exit(CircleNames[K]);
  end;

  procedure Put(Depth: Integer; const S: string; Thing: Integer);
  begin
    L.Add(StringOfChar(' ', Depth * 2) + S);
    if Hints <> nil then Hints.Add(NextHint);
    NextHint := '';
    if NLine >= Length(LineThing) then SetLength(LineThing, NLine * 2 + 64);
    LineThing[NLine] := Thing;
    if Thing >= 0 then
    begin
      if First[Thing] > Last[Thing] then First[Thing] := NLine;
      Last[Thing] := NLine;
    end;
    Inc(NLine);
  end;

  { A name as written after its kind: bare when it is a word, quoted when
    not, nothing when there is none. }
  function NameWord(const Nm: string): string;
  var
    K: Integer;
    Bare: Boolean;
  begin
    if Nm = '' then Exit('');
    Bare := Nm[1] in ['A'..'Z', 'a'..'z', '_'];
    for K := 2 to Length(Nm) do
      if not (Nm[K] in ['A'..'Z', 'a'..'z', '_', '0'..'9']) then Bare := False;
    if Bare then Result := ' ' + Nm else Result := ' ' + QuotedStr(Nm);
  end;

  { the comments kept with a thing (TWorkEnt.Note): those above it here, and
    TailNote gives the one that goes at the end of its first line }
  procedure PutNote(Depth: Integer; const Note: string; Thing: Integer);
  var
    Parts: TStringList;
    K: Integer;
  begin
    if Note = '' then Exit;
    Parts := TStringList.Create;
    try
      Parts.Text := Note;
      for K := 0 to Parts.Count - 1 do
        if (Parts[K] <> '') and (Parts[K][1] <> #9) then Put(Depth, Parts[K], Thing);
    finally
      Parts.Free;
    end;
  end;

  function TailNote(const Note: string): string;
  var
    Parts: TStringList;
    K: Integer;
  begin
    Result := '';
    if Pos(#9, Note) = 0 then Exit;
    Parts := TStringList.Create;
    try
      Parts.Text := Note;
      for K := 0 to Parts.Count - 1 do
        if (Parts[K] <> '') and (Parts[K][1] = #9) then
          Result := Result + '   ' + Copy(Parts[K], 2, MaxInt);
    finally
      Parts.Free;
    end;
  end;

  { a solid's name and comments, from whichever member carries them }
  procedure SolidNaming(Part_, G: Integer; out Nm, Note: string);
  var
    I: Integer;
  begin
    Nm := '';
    Note := '';
    for I := 0 to D.Live - 1 do
      if (D[I].Grp = G) and (D[I].Part = Part_) and ((D[I].SName <> '') or (D[I].SNote <> '')) then
      begin
        Nm := D[I].SName;
        Note := D[I].SNote;
        Exit;
      end;
  end;

  { A circle keeps the name it was given when that is a word no other
    circle has; the rest are c1, c2... skipping names taken. }
  procedure NameCircles;
  var
    K, N: Integer;
    Taken: TStringList;
  begin
    SetLength(CircleNames, Length(Circles));
    Taken := TStringList.Create;
    try
      Taken.CaseSensitive := False;
      for K := 0 to High(Circles) do
      begin
        CircleNames[K] := '';
        if (D[Circles[K]].Name <> '') and (Trim(NameWord(D[Circles[K]].Name)) = D[Circles[K]].Name) and
           (Taken.IndexOf(D[Circles[K]].Name) < 0) then
        begin
          CircleNames[K] := D[Circles[K]].Name;
          Taken.Add(CircleNames[K]);
        end;
      end;
      N := 0;
      for K := 0 to High(Circles) do
        if CircleNames[K] = '' then
        begin
          repeat
            Inc(N);
          until Taken.IndexOf('c' + IntToStr(N)) < 0;
          CircleNames[K] := 'c' + IntToStr(N);
          Taken.Add(CircleNames[K]);
        end;
    finally
      Taken.Free;
    end;
  end;

  { The commonest ink and width become the sheet's and go unwritten.  Count
    everything, not a sample, so the choice does not depend on read order. }
  procedure FindDefaults;
  var
    I, K, Best: Integer;
    Inks: array of record C: TColor; N: Integer; end;
    Wds: array of record W: Single; N: Integer; end;
  begin
    DefInk := $201C1A;
    DefWidth := 1;
    SetLength(Inks, 0);
    SetLength(Wds, 0);
    for I := 0 to D.Live - 1 do
      if D[I].Kind in [ekLine, ekArc, ekFace] then
      begin
        { lines, arcs and faces all carry an ink; the commonest over all of them
          is left unwritten most }
        K := 0;
        while (K < Length(Inks)) and (Inks[K].C <> D[I].Ink) do Inc(K);
        if K = Length(Inks) then
        begin
          SetLength(Inks, K + 1);
          Inks[K].C := D[I].Ink;
          Inks[K].N := 0;
        end;
        Inc(Inks[K].N);
        if D[I].Kind = ekFace then Continue;
        K := 0;
        while (K < Length(Wds)) and (Abs(Wds[K].W - D[I].Weight) > 1E-3) do Inc(K);
        if K = Length(Wds) then
        begin
          SetLength(Wds, K + 1);
          Wds[K].W := D[I].Weight;
          Wds[K].N := 0;
        end;
        Inc(Wds[K].N);
      end;
    Best := 0;
    for K := 0 to High(Inks) do
      if Inks[K].N > Best then begin Best := Inks[K].N; DefInk := Inks[K].C; end;
    Best := 0;
    for K := 0 to High(Wds) do
      if Wds[K].N > Best then begin Best := Wds[K].N; DefWidth := Wds[K].W; end;
  end;

  function PointName(Index, Count: Integer): string;
  begin
    if Count <= 23 then Result := Chr(Ord('a') + Index)
    else Result := 'p' + IntToStr(Index + 1);
  end;

  function FindPt(const Pts: TPts; const P: TP3): Integer;
  var
    I: Integer;
  begin
    for I := 0 to High(Pts) do
      if SameP(Pts[I].P, P) then Exit(I);
    Result := -1;
  end;

  procedure AddPt(var Pts: TPts; const P: TP3);
  begin
    if FindPt(Pts, P) >= 0 then Exit;
    SetLength(Pts, Length(Pts) + 1);
    Pts[High(Pts)].P := P;
    Pts[High(Pts)].Read := P;
    Pts[High(Pts)].Ring := -1;
    Pts[High(Pts)].Name := '';
    Pts[High(Pts)].InHole := True;
  end;

  function Ref(const Pts: TPts; const P: TP3): string;
  var
    K: Integer;
  begin
    K := FindPt(Pts, P);
    if K >= 0 then Result := Pts[K].Name
    else Result := Place2(P, U, False);
  end;

  { A list of places.  Named corners are just names; written-out places are
    a walk, the first absolute and each after it a step from the one before:
    "0; + 4' east; + 4' north; + 4' west" is a square. }
  function Items(const Pts: TPts; const Poly: array of TP3): TStringArray;
  var
    K, F: Integer;
    Acc, Step: TP3;
  begin
    SetLength(Result, Length(Poly));
    Acc := P3(0, 0, 0);
    for K := 0 to High(Poly) do
    begin
      F := FindPt(Pts, Poly[K]);
      if F >= 0 then
      begin
        Result[K] := Pts[F].Name;
        Acc := Pts[F].Read;
      end
      else if K = 0 then
      begin
        Result[K] := Place2(Poly[K], U, False);
        Acc := AsRead3(Poly[K], U);
      end
      else
      begin
        { step from where the reader will be, so this corner reads back as its
          own rounded self }
        Step := Sub3(Poly[K], Acc);
        Result[K] := '+ ' + Place2(Step, U, True);
        Acc := P3(Acc.X + AsRead(Step.X, U), Acc.Y + AsRead(Step.Y, U), Acc.Z + AsRead(Step.Z, U));
      end;
    end;
  end;

  function Named(const It: TStringArray): Boolean;
  var
    K: Integer;
  begin
    Result := Length(It) > 0;
    for K := 0 to High(It) do
      if Pos(' ', It[K]) > 0 then Exit(False);
  end;

  { a run of three or more names counting up or down by one is written as
    its ends: ra1..ra24 }
  function Runs(const It: TStringArray): TStringArray;
  var
    K, J, N, Step, A, B, Q: Integer;
    Stem: string;

    function Split(const S: string; out St: string; out Num: Integer): Boolean;
    var
      P: Integer;
    begin
      P := Length(S);
      while (P > 0) and (S[P] in ['0'..'9']) do Dec(P);
      St := Copy(S, 1, P);
      Result := (P < Length(S)) and (P > 0) and TryStrToInt(Copy(S, P + 1, 9), Num);
    end;

  begin
    SetLength(Result, Length(It));
    N := 0;
    K := 0;
    while K <= High(It) do
    begin
      J := K;
      if Split(It[K], Stem, A) and (K < High(It)) and Split(It[K + 1], Result[N], B) and
         (Result[N] = Stem) and (Abs(B - A) = 1) then
      begin
        Step := B - A;
        J := K + 1;
        while (J < High(It)) and Split(It[J + 1], Result[N], Q) and (Result[N] = Stem) and
              (Q - B = Step) do
        begin
          B := Q;
          Inc(J);
        end;
      end;
      if J - K >= 2 then
      begin
        Result[N] := It[K] + '..' + It[J];
        K := J + 1;
      end
      else
      begin
        Result[N] := It[K];
        Inc(K);
      end;
      Inc(N);
    end;
    SetLength(Result, N);
  end;

  function Joined(const It: TStringArray): string;
  var
    K: Integer;
  begin
    Result := '';
    for K := 0 to High(It) do
    begin
      if K > 0 then
        if Named(It) then Result := Result + ' ' else Result := Result + ' to ';
      Result := Result + It[K];
    end;
  end;

  { "key = list" on one line when it fits, else LFM style: "key = (", the
    list over as many lines as needed, ")". }
  procedure PutList(Depth: Integer; const Key: string; const It: TStringArray;
    Thing: Integer; const Note: string = '');
  const
    WIDE = 78;
  var
    K: Integer;
    Row, Sep: string;
  begin
    if Depth * 2 + Length(Key) + 3 + Length(Joined(It)) <= WIDE then
    begin
      Put(Depth, Key + ' = ' + Joined(It) + Note, Thing);
      Exit;
    end;
    if Named(It) then Sep := ' ' else Sep := ' to ';
    Put(Depth, Key + ' = (' + Note, Thing);
    Row := '';
    for K := 0 to High(It) do
    begin
      if (Row <> '') and ((Depth + 1) * 2 + Length(Row) + Length(Sep) + Length(It[K]) > WIDE) then
      begin
        { each row of places ends in "to", so the rows read as one list }
        if Sep <> ' ' then Row := Row + ' to';
        Put(Depth + 1, Row, Thing);
        Row := '';
      end;
      if Row <> '' then Row := Row + Sep;
      Row := Row + It[K];
    end;
    if Row <> '' then Put(Depth + 1, Row, Thing);
    Put(Depth, ')', Thing);
  end;

  { If this loop is one of the sheet's circles, corner for corner, write it
    by name ("face = c1") instead of thirty-two places. }
  function CircleNamed(const Poly: array of TP3; Part_: Integer): string;
  var
    C, K, Q, N, Hit: Integer;
    P: TP3;
    Ok_: Boolean;
  begin
    Result := '';
    N := Length(Poly);
    if N < 8 then Exit;
    for C := 0 to High(Circles) do
    begin
      if D[Circles[C]].Part <> Part_ then Continue;
      Ok_ := True;
      for K := 0 to N - 1 do
      begin
        P := ArcPoint(D[Circles[C]].C, D[Circles[C]].R,
          D[Circles[C]].A0 + K * D[Circles[C]].Sweep / N, D[Circles[C]].Plane, D[Circles[C]].Nm);
        { Tolerance covers the six-place rounding older drawings carry; ring
          corners are far further apart than that. }
        Hit := -1;
        for Q := 0 to N - 1 do
          if SamePt(Poly[Q], P, 2E-5) then begin Hit := Q; Break; end;
        if Hit < 0 then begin Ok_ := False; Break; end;
      end;
      if Ok_ then Exit(CircleNames[C]);
    end;
  end;

  { the way a circle faces, as the reader will turn the disk "face = c1" }
  function CircleFacing(const Nm: string): TP3;
  var
    I: Integer;
  begin
    Result := P3(0, 0, 1);
    I := StrToIntDef(Copy(Nm, 2, MaxInt), 0) - 1;
    if (I < 0) or (I > High(Circles)) then Exit;
    case D[Circles[I]].Plane of
      plXZ: Result := P3(0, -1, 0);
      plYZ: Result := P3(1, 0, 0);
      plFree: Result := D[Circles[I]].Nm;
    end;
  end;

  function Outline(const Pts: TPts; const Poly: array of TP3; Part_: Integer;
    IsHole: Boolean = False): TStringArray;
  var
    Nm: string;
    Lp: TP3Array;
    K: Integer;
  begin
    Nm := CircleNamed(Poly, Part_);
    { A circle by name is the disk facing the circle's way; a face turned the
      other way (the bottom of a pulled disk) is written as corners.  A hole runs
      against its face and is the circle whichever way. }
    if (Nm <> '') and not IsHole then
    begin
      SetLength(Lp, Length(Poly));
      for K := 0 to High(Poly) do Lp[K] := Poly[K];
      if Dot3(LoopNormal(Lp), CircleFacing(Nm)) < 0 then Nm := '';
    end;
    if Nm <> '' then
    begin
      SetLength(Result, 1);
      Result[0] := Nm;
    end
    else
    begin
      Result := Items(Pts, Poly);
      if Named(Result) then Result := Runs(Result);
    end;
  end;

  function NameKey(const Nm: string): string;
  var
    P: Integer;
    Stem: string;
  begin
    P := Length(Nm);
    while (P > 0) and (Nm[P] in ['0'..'9']) do Dec(P);
    Stem := Copy(Nm, 1, P);
    { floor before mid before top before anything else, then the number }
    if Stem = 'floor' then Result := '1'
    else if Stem = 'floorin' then Result := '2'
    else if Stem = 'mid' then Result := '3'
    else if Stem = 'midin' then Result := '4'
    else if Stem = 'top' then Result := '5'
    else if Stem = 'topin' then Result := '6'
    else Result := '7' + Stem;
    Result := Result + Format('%.4d', [StrToIntDef(Copy(Nm, P + 1, 9), 0)]);
  end;

  { by NameKey; the keys are worked out once, since names kept from the text
    come in any order and an insertion sort of thousands is too slow }
  procedure SortByName(var Pts: TPts);
  var
    Keys: TStringList;
    Was: TPts;
    I: Integer;
  begin
    if Length(Pts) < 2 then Exit;
    Keys := TStringList.Create;
    try
      Keys.CaseSensitive := True;
      Keys.UseLocale := False;
      for I := 0 to High(Pts) do
        Keys.AddObject(NameKey(Pts[I].Name) + #1 + Format('%.9d', [I]), TObject(PtrInt(I)));
      Keys.Sort;
      Was := Copy(Pts);
      for I := 0 to High(Pts) do Pts[I] := Was[PtrInt(Keys.Objects[I])];
    finally
      Keys.Free;
    end;
  end;

  function TakenName(const Pts: TPts; const Nm: string): Boolean;
  var
    I: Integer;
  begin
    for I := 0 to High(Pts) do
      if SameText(Pts[I].Name, Nm) then Exit(True);
    Result := False;
  end;

  { Stem and N, or the next number up that no corner has yet }
  function Fresh(const Pts: TPts; const Stem: string; N: Integer): string;
  begin
    if not Given then Exit(Stem + IntToStr(N));
    repeat
      Result := Stem + IntToStr(N);
      Inc(N);
    until not TakenName(Pts, Result);
  end;

  { The names the text gave a solid's corners, from its faces, edges and
    bores (TWorkEnt.Corners).  A face split or copied can carry a name to the
    wrong place, so each name goes to the place most of them give it. }
  procedure GivenNames(var Pts: TPts; Part_, G: Integer);
  var
    Votes, At, Taken: TFPHashList;
    VPt, VCount: array of Integer;
    VName: TStringArray;
    NV, I, J, K, H, N, Pt, Most, C: Integer;
    Parts: TStringArray;
    Nm: string;

    function KeyOf(const P: TP3): shortstring;
    begin
      Result := IntToStr(Round(P.X * 1E7)) + ',' + IntToStr(Round(P.Y * 1E7)) + ',' + IntToStr(Round(P.Z * 1E7));
    end;

    procedure Vote(const P: TP3; const Name_: string);
    var
      X, V: Integer;
    begin
      if Name_ = '' then Exit;
      X := At.FindIndexOf(KeyOf(P));
      if X < 0 then Exit;
      X := PtrInt(At.Items[X]) - 1;
      if Pts[X].Ring >= 0 then Exit;
      V := Votes.FindIndexOf(IntToStr(X) + '|' + Name_);
      if V >= 0 then V := PtrInt(Votes.Items[V]) - 1
      else
      begin
        if NV >= Length(VPt) then
        begin
          SetLength(VPt, NV * 2 + 64);
          SetLength(VCount, Length(VPt));
          SetLength(VName, Length(VPt));
        end;
        V := NV;
        VPt[V] := X;
        VName[V] := Name_;
        VCount[V] := 0;
        Inc(NV);
        Votes.Add(IntToStr(X) + '|' + Name_, Pointer(PtrInt(V + 1)));
      end;
      Inc(VCount[V]);
    end;

  begin
    Given := False;
    K := -1;
    for I := 0 to D.Live - 1 do
      if (D[I].Grp = G) and (D[I].Part = Part_) and (D[I].Corners <> '') then begin K := I; Break; end;
    if K < 0 then Exit;
    NV := 0;
    Votes := TFPHashList.Create;
    At := TFPHashList.Create;
    Taken := TFPHashList.Create;
    try
      { stored one up: a nil item is an empty slot to TFPHashList }
      for I := 0 to High(Pts) do
      begin
        if At.FindIndexOf(KeyOf(Pts[I].P)) < 0 then At.Add(KeyOf(Pts[I].P), Pointer(PtrInt(I + 1)));
        if Pts[I].Name <> '' then Taken.Add(LowerCase(Pts[I].Name), Pointer(1));
      end;
      for I := K to D.Live - 1 do
      begin
        if (D[I].Grp <> G) or (D[I].Part <> Part_) or (D[I].Corners = '') then Continue;
        Parts := D[I].Corners.Split(['|']);
        case D[I].Kind of
          ekLine:
            if Length(Parts) = 2 then
            begin
              Vote(D[I].A, Parts[0]);
              Vote(D[I].B, Parts[1]);
            end;
          ekFace, ekBore:
            begin
              N := Length(D[I].Poly);
              for H := 0 to High(D[I].Holes) do Inc(N, Length(D[I].Holes[H]));
              if Length(Parts) <> N then Continue;
              N := 0;
              for J := 0 to High(D[I].Poly) do begin Vote(D[I].Poly[J], Parts[N]); Inc(N); end;
              for H := 0 to High(D[I].Holes) do
                for J := 0 to High(D[I].Holes[H]) do begin Vote(D[I].Holes[H][J], Parts[N]); Inc(N); end;
            end;
        end;
      end;
      { the names with most votes first; a name or a corner already given
        is passed over }
      Most := 0;
      for I := 0 to NV - 1 do Most := Max(Most, VCount[I]);
      for C := Most downto 1 do
        for I := 0 to NV - 1 do
        begin
          if VCount[I] <> C then Continue;
          Pt := VPt[I];
          Nm := VName[I];
          if (Pts[Pt].Name <> '') or (Trim(NameWord(Nm)) <> Nm) or
             (Taken.FindIndexOf(LowerCase(Nm)) >= 0) then Continue;
          Pts[Pt].Name := Nm;
          Taken.Add(LowerCase(Nm), Pointer(1));
          Given := True;
        end;
    finally
      Taken.Free;
      At.Free;
      Votes.Free;
    end;
  end;

  { floor1..N, top1..N, mid1..N, or nothing when the corners do not fall
    into a few levels }
  procedure NameByPlace(var Pts: TPts);
  var
    I, J, N, NLevels, Best, Pass: Integer;
    Z: array of Double;
    Level: array of Integer;
    Count: array of Integer;
    Order: array of Integer;
    Ang, BestAng, BestAng2, CX, CY: Double;
    W: string;

  begin
    N := 0;
    for I := 0 to High(Pts) do
      if Pts[I].Ring < 0 then Inc(N);
    if (N < 4) or (N > 24) then Exit;
    { the distinct heights }
    SetLength(Z, 0);
    SetLength(Level, Length(Pts));
    for I := 0 to High(Pts) do
    begin
      Level[I] := -1;
      if Pts[I].Ring >= 0 then Continue;
      for J := 0 to High(Z) do
        if Abs(Z[J] - Pts[I].P.Z) < 1E-6 then begin Level[I] := J; Break; end;
      if Level[I] < 0 then
      begin
        SetLength(Z, Length(Z) + 1);
        Z[High(Z)] := Pts[I].P.Z;
        Level[I] := High(Z);
      end;
    end;
    NLevels := Length(Z);
    if (NLevels < 1) or (NLevels > 3) then Exit;
    { one level only is a flat thing: its corners go around from the one
      nearest the origin, as floor1, floor2... }
    { the levels sorted low to high: floor, mid, top }
    SetLength(Order, NLevels);
    for I := 0 to NLevels - 1 do
    begin
      Order[I] := 0;
      for J := 0 to NLevels - 1 do
        if Z[J] < Z[I] - 1E-6 then Inc(Order[I]);
    end;
    { around each level: by angle about the level's middle, starting from the
      corner nearest the origin }
    SetLength(Count, NLevels);
    for I := 0 to NLevels - 1 do Count[I] := 0;
    for J := 0 to NLevels - 1 do
    begin
      CX := 0; CY := 0; N := 0;
      for I := 0 to High(Pts) do
        if Level[I] = J then begin CX := CX + Pts[I].P.X; CY := CY + Pts[I].P.Y; Inc(N); end;
      if N = 0 then Continue;
      CX := CX / N; CY := CY / N;
      Best := -1;
      for I := 0 to High(Pts) do
        if (Level[I] = J) and ((Best < 0) or
           (Sqr(Pts[I].P.X) + Sqr(Pts[I].P.Y) < Sqr(Pts[Best].P.X) + Sqr(Pts[Best].P.Y) - 1E-9)) then
          Best := I;
      BestAng := ArcTan2(Pts[Best].P.Y - CY, Pts[Best].P.X - CX);
      { number them counterclockwise from that one }
      for I := 0 to High(Pts) do
        if Level[I] = J then
        begin
          Ang := ArcTan2(Pts[I].P.Y - CY, Pts[I].P.X - CX) - BestAng;
          while Ang < -1E-9 do Ang := Ang + 2 * Pi;
          Count[J] := Count[J] + 1;
        end;
      { the names in that order: the outline's corners first, then any of a
        hole cut in that level, as "in" corners }
      for Pass := 0 to 1 do
      begin
      N := 0;
      while N < Count[J] do
      begin
        Best := -1;
        for I := 0 to High(Pts) do
          if (Level[I] = J) and (Pts[I].Name = '') and (Ord(Pts[I].InHole) = Pass) then
          begin
            Ang := ArcTan2(Pts[I].P.Y - CY, Pts[I].P.X - CX) - BestAng;
            while Ang < -1E-9 do Ang := Ang + 2 * Pi;
            if (Best < 0) or (Ang < BestAng2) then begin Best := I; BestAng2 := Ang; end;
          end;
        if Best < 0 then Break;
        case NLevels of
          1: W := 'p';
          2: if Order[J] = 0 then W := 'floor' else W := 'top';
        else
          case Order[J] of
            0: W := 'floor';
            1: W := 'mid';
          else
            W := 'top';
          end;
        end;
        if Pass = 1 then W := W + 'in';
        Pts[Best].Name := Fresh(Pts, W, N + 1);
        Inc(N);
      end;
      end;
    end;
  end;

  { lower, then further south, then further west: the order corners are
    numbered in when nothing better names them }
  function Below(const A, B: TP3): Boolean;
  begin
    Result := (A.Z < B.Z - 1E-9) or
      ((Abs(A.Z - B.Z) <= 1E-9) and (A.Y < B.Y - 1E-9)) or
      ((Abs(A.Z - B.Z) <= 1E-9) and (Abs(A.Y - B.Y) <= 1E-9) and (A.X < B.X - 1E-9));
  end;

  procedure PutPoints(Depth: Integer; var Pts: TPts; const Rings: TRings);
  var
    I, J, From, Loose, K: Integer;
    Nm: string;
    V: TP3;
    Tmp: TPt;
    Slots: TIntArrayW;
  begin
    if Length(Pts) = 0 then Exit;
    Loose := 0;
    for I := 0 to High(Pts) do
      if Pts[I].Ring < 0 then Inc(Loose);
    { Corners are named by where they stand so a line between them reads
      naturally: lowest are floor, highest top, between mid, numbered around
      from the one nearest the origin.  "line = floor1 to top1" is an upright.
      A solid whose corners are all at different heights falls back on a, b, c. }
    NameByPlace(Pts);
    { Number the rest by position (lowest, then south to north, then west to
      east), not by face order, so the same solid is named the same way
      whichever side wrote it. }
    SetLength(Slots, 0);
    for I := 0 to High(Pts) do
      if (Pts[I].Ring < 0) and (Pts[I].Name = '') then
      begin
        SetLength(Slots, Length(Slots) + 1);
        Slots[High(Slots)] := I;
      end;
    for I := 1 to High(Slots) do
      for J := I downto 1 do
        if Below(Pts[Slots[J]].P, Pts[Slots[J - 1]].P) then
        begin
          Tmp := Pts[Slots[J]]; Pts[Slots[J]] := Pts[Slots[J - 1]]; Pts[Slots[J - 1]] := Tmp;
        end
        else Break;
    K := 0;
    for I := 0 to High(Pts) do
      if (Pts[I].Ring < 0) and (Pts[I].Name = '') then
      begin
        if Length(Rings) > 0 then Pts[I].Name := Fresh(Pts, 'p', K + 1)
        else
        begin
          Nm := PointName(K, Loose);
          if Given and TakenName(Pts, Nm) then Nm := Fresh(Pts, 'p', K + 1);
          Pts[I].Name := Nm;
        end;
        Inc(K);
      end;
    { in name order: floor1, floor2... then top1... }
    SortByName(Pts);
    if Names <> nil then
      for I := 0 to High(Pts) do
        Names.Add(IntToStr(NLine) + '|' + LowerCase(Pts[I].Name) + '=' + Place2(Pts[I].P, U, False));
    Put(Depth, 'points', -1);
    for I := 0 to High(Rings) do
    begin
      Put(Depth + 1, 'ring ' + Rings[I].Name, -1);
      Put(Depth + 2, 'center = ' + Place2(Rings[I].C, U, False), -1);
      Put(Depth + 2, 'radius = ' + Len2(Rings[I].R, U), -1);
      Put(Depth + 2, 'sides  = ' + IntToStr(Rings[I].N), -1);
      Put(Depth + 2, 'facing = ' + Facing2(Rings[I].Facing), -1);
      if Abs(Rings[I].Starts) > 1E-9 then
        Put(Depth + 2, 'starts = ' + Deg2(Rings[I].Starts), -1);
      Put(Depth + 1, 'end', -1);
    end;
    for I := 0 to High(Pts) do
    begin
      if Pts[I].Ring >= 0 then Continue;
      { From an earlier point along one axis: the latest such, preferring one
        that can be given with east, north or up over one that needs west. }
      From := -1;
      for J := I - 1 downto 0 do
      begin
        V := Sub3(Pts[I].P, Pts[J].P);
        if AxesUsed(V) <> 1 then Continue;
        { the axis it runs along, not the noise on the other two, or the
          choice flips from one save to the next }
        if (V.X > 1E-9) or (V.Y > 1E-9) or (V.Z > 1E-9) then begin From := J; Break; end;
        if From < 0 then From := J;
      end;
      if From >= 0 then NextHint := Place2(Pts[I].P, U, False);
      if From >= 0 then
      begin
        { step from where the reader will have put the other, so nothing drifts }
        V := Sub3(Pts[I].P, Pts[From].Read);
        Put(Depth + 1, Format('%s = %s + %s', [Pts[I].Name, Pts[From].Name,
          Place2(V, U, True)]), -1);
        Pts[I].Read := P3(Pts[From].Read.X + AsRead(V.X, U), Pts[From].Read.Y + AsRead(V.Y, U),
          Pts[From].Read.Z + AsRead(V.Z, U));
      end
      else
      begin
        Put(Depth + 1, Format('%s = %s', [Pts[I].Name, Place2(Pts[I].P, U, False)]), -1);
        Pts[I].Read := AsRead3(Pts[I].P, U);
      end;
    end;
    Put(Depth, 'end', -1);
    Given := False;
  end;

  { If these corners are spaced evenly around a circle, they are a ring. }
  function RingOf(const Poly: array of TP3; out Rg: TRing): Boolean;
  var
    K, N: Integer;
    C, Nm, AU, AV, W0, W1: TP3;
    R, A, A1: Double;
  begin
    Result := False;
    N := Length(Poly);
    if N < 8 then Exit;
    C := P3(0, 0, 0);
    for K := 0 to N - 1 do C := P3(C.X + Poly[K].X / N, C.Y + Poly[K].Y / N, C.Z + Poly[K].Z / N);
    R := Dist(Poly[0], C);
    if R < 1E-9 then Exit;
    for K := 0 to N - 1 do
      if Abs(Dist(Poly[K], C) - R) > 1E-9 then Exit;
    { the facing follows the order its corners turn }
    W0 := Sub3(Poly[0], C);
    W1 := Sub3(Poly[1], C);
    Nm := P3(W0.Y * W1.Z - W0.Z * W1.Y, W0.Z * W1.X - W0.X * W1.Z, W0.X * W1.Y - W0.Y * W1.X);
    A := Sqrt(Nm.X * Nm.X + Nm.Y * Nm.Y + Nm.Z * Nm.Z);
    if A < 1E-12 then Exit;
    Nm := P3(Nm.X / A, Nm.Y / A, Nm.Z / A);
    SpecAxes(Nm, AU, AV);
    A := ArcTan2(Dot3(W0, AV), Dot3(W0, AU));
    for K := 1 to N - 1 do
    begin
      A1 := A + K * 2 * Pi / N;
      if not SameP(Poly[K], P3(C.X + (AU.X * Cos(A1) + AV.X * Sin(A1)) * R,
                               C.Y + (AU.Y * Cos(A1) + AV.Y * Sin(A1)) * R,
                               C.Z + (AU.Z * Cos(A1) + AV.Z * Sin(A1)) * R)) then Exit;
    end;
    Rg.C := C;
    Rg.R := R;
    Rg.N := N;
    Rg.Facing := Nm;
    Rg.Starts := A;
    Result := True;
  end;

  { a group's data, as it came; see hsGroupData }
  procedure PutData(Depth: Integer; const Data: string; I: Integer);
  var
    Lines: TStringList;
    K: Integer;
  begin
    Lines := DataIndented(Data);
    try
      Put(Depth, 'data', I);
      for K := 0 to Lines.Count - 1 do Put(Depth + 1, Lines[K], I);
      Put(Depth, 'end', I);
    finally
      Lines.Free;
    end;
  end;

  procedure PutInk(Depth, I: Integer);
  begin
    if D[I].Ink <> DefInk then Put(Depth, 'ink = ' + Color2(D[I].Ink), I);
    if (D[I].Kind in [ekLine, ekArc]) and (Abs(D[I].Weight - DefWidth) > 1E-3) then
      Put(Depth, 'width = ' + FloatToStrF(D[I].Weight, ffGeneral, 4, 0, DotFS), I);
  end;

  { HasMat/Mat: what the solid says its faces are made of, so a face only
    gives a material when it differs }
  procedure PutFace(Depth, I: Integer; const Pts: TPts; HasMat: Boolean = False;
    Mat: TColor = 0);
  var
    K: Integer;
    Note, W: string;
    SameMat: Boolean;
  begin
    W := FacingWord(D.FaceNormal(I));
    if W <> '' then Note := '   { facing ' + W + ' }' else Note := '';
    Note := Note + TailNote(D[I].Note);
    PutNote(Depth, D[I].Note, I);
    SameMat := (D[I].MatSet = HasMat) and ((not HasMat) or (D[I].Mat = Mat));
    if SameMat and (Length(D[I].Holes) = 0) and (D[I].Ink = DefInk) then
    begin
      PutList(Depth, 'face' + NameWord(D[I].Name), Outline(Pts, D[I].Poly, D[I].Part), I, Note);
      Exit;
    end;
    Put(Depth, 'face' + NameWord(D[I].Name) + Note, I);
    PutList(Depth + 1, 'points', Outline(Pts, D[I].Poly, D[I].Part), I);
    for K := 0 to High(D[I].Holes) do
      PutList(Depth + 1, 'hole', Outline(Pts, D[I].Holes[K], D[I].Part, True), I);
    if not SameMat then
      if D[I].MatSet then Put(Depth + 1, 'paint = ' + Color2(D[I].Mat), I)
      else Put(Depth + 1, 'paint = none', I);
    if D[I].Ink <> DefInk then Put(Depth + 1, 'ink = ' + Color2(D[I].Ink), I);
    Put(Depth, 'end', I);
  end;

  { A line is two points; their order means nothing. }
  procedure PutLine(Depth, I: Integer; const Pts: TPts);
  var
    Ends: string;
  begin
    Ends := Ref(Pts, D[I].A) + ' to ' + Ref(Pts, D[I].B);
    PutNote(Depth, D[I].Note, I);
    if (D[I].Ink = DefInk) and (Abs(D[I].Weight - DefWidth) <= 1E-3) and
       (not D[I].Soft) and (not D[I].Dim) then
    begin
      Put(Depth, 'line' + NameWord(D[I].Name) + ' = ' + Ends + TailNote(D[I].Note), I);
      Exit;
    end;
    Put(Depth, 'line' + NameWord(D[I].Name) + TailNote(D[I].Note), I);
    Put(Depth + 1, 'points = ' + Ends, I);
    PutInk(Depth + 1, I);
    if D[I].Soft then Put(Depth + 1, 'soft = true', I);
    if D[I].Dim then Put(Depth + 1, 'ref = true', I);
    Put(Depth, 'end', I);
  end;

  { Named lines joined end to end, as the reader makes them from
    "line Cable = a to b to c": one statement again.  Chain is in order and
    Poly its places. }
  procedure PutChain(Depth: Integer; const Chain: TIntArrayW; const Poly: TP3Array);
  var
    I, K, Header: Integer;
    It: TStringArray;
    None: TPts;
  begin
    I := Chain[0];
    SetLength(None, 0);
    It := Items(None, Poly);
    Header := NLine;
    PutNote(Depth, D[I].Note, I);
    if (D[I].Ink = DefInk) and (Abs(D[I].Weight - DefWidth) <= 1E-3) and
       (not D[I].Soft) and (not D[I].Dim) then
      PutList(Depth, 'line' + NameWord(D[I].Name), It, I, TailNote(D[I].Note))
    else
    begin
      Put(Depth, 'line' + NameWord(D[I].Name) + TailNote(D[I].Note), I);
      PutList(Depth + 1, 'points', It, I);
      PutInk(Depth + 1, I);
      if D[I].Soft then Put(Depth + 1, 'soft = true', I);
      if D[I].Dim then Put(Depth + 1, 'ref = true', I);
      Put(Depth, 'end', I);
    end;
    for K := 0 to High(Chain) do
    begin
      First[Chain[K]] := Header;
      Last[Chain[K]] := NLine - 1;
    end;
  end;

  procedure PutOther(Depth, I: Integer);
  var
    Parts: TStringList;
    K: Integer;
    Nm, AU, AV, P0: TP3;
    A0: Double;
    Tl: string;
  begin
    PutNote(Depth, D[I].Note, I);
    Tl := TailNote(D[I].Note);
    case D[I].Kind of
      ekArc:
        begin
          { Facing follows its own turning, and the start is measured the grammar's
            way (from the level line), whatever axes the program keeps for the plane. }
          Nm := P3(0, 0, 1);
          case D[I].Plane of
            plXZ: Nm := P3(0, -1, 0);
            plYZ: Nm := P3(1, 0, 0);
            plFree: Nm := D[I].Nm;
          end;
          SpecAxes(Nm, AU, AV);
          P0 := Sub3(ArcPoint(D[I].C, D[I].R, D[I].A0, D[I].Plane, D[I].Nm), D[I].C);
          A0 := ArcTan2(Dot3(P0, AV), Dot3(P0, AU));
          { A plain circle is one line: center, radius, and facing only when not up.
            Anything more (start, its own sides, an ink) makes it a block. }
          if FullCircle(D[I].Sweep) and (Abs(A0) <= 1E-9) and
             (D[I].Sides = HECK_SIDES) and (D[I].Ink = DefInk) and
             (Abs(D[I].Weight - DefWidth) <= 1E-3) then
          begin
            if Abs(Nm.Z - 1) < 1E-9 then
              Put(Depth, Trim('circle ' + CircleName(I)) + ' = ' + Place2(D[I].C, U, False) +
                '; ' + Len2(D[I].R, U) + Tl, I)
            else
              Put(Depth, Trim('circle ' + CircleName(I)) + ' = ' + Place2(D[I].C, U, False) +
                '; ' + Len2(D[I].R, U) + '; ' + Facing2(Nm) + Tl, I);
            Exit;
          end;
          if FullCircle(D[I].Sweep) then Put(Depth, 'circle ' + CircleName(I) + Tl, I)
          else Put(Depth, 'arc' + NameWord(D[I].Name) + Tl, I);
          Put(Depth + 1, 'center = ' + Place2(D[I].C, U, False), I);
          Put(Depth + 1, 'radius = ' + Len2(D[I].R, U), I);
          Put(Depth + 1, 'facing = ' + Facing2(Nm), I);
          if Abs(A0) > 1E-9 then Put(Depth + 1, 'starts = ' + Deg2(A0), I);
          if not FullCircle(D[I].Sweep) then
            Put(Depth + 1, 'sweep = ' + Deg2(D[I].Sweep), I);
          { the ring's sides for the faces it implies, written whenever they differ
            from what a one-line circle reads back with }
          if ArcSteps(D[I]) <> HECK_SIDES then Put(Depth + 1, 'sides = ' + IntToStr(ArcSteps(D[I])), I);
          PutInk(Depth + 1, I);
          Put(Depth, 'end', I);
        end;
      ekDim:
        begin
          Put(Depth, 'dim' + NameWord(D[I].Name) + Tl, I);
          Put(Depth + 1, 'from = ' + Place2(D[I].A, U, False), I);
          Put(Depth + 1, 'to = ' + Place2(D[I].B, U, False), I);
          Put(Depth + 1, 'off = ' + Place2(D[I].C, U, True), I);
          if D[I].Txt <> '' then Put(Depth + 1, 'label = ' + QuotedStr(D[I].Txt), I);
          PutInk(Depth + 1, I);
          Put(Depth, 'end', I);
        end;
      ekGuide:
        if SameP(D[I].A, D[I].B) then
          Put(Depth, 'guide' + NameWord(D[I].Name) + ' = ' + Place2(D[I].A, U, False) + Tl, I)
        else
          Put(Depth, 'guide' + NameWord(D[I].Name) + ' = ' + Place2(D[I].A, U, False) + ' to ' +
            Place2(D[I].B, U, False) + Tl, I);
      ekText:
        begin
          Put(Depth, 'note' + NameWord(D[I].Name) + Tl, I);
          Put(Depth + 1, 'at = ' + Place2(D[I].A, U, False), I);
          if not SameP(D[I].A, D[I].B) then
            Put(Depth + 1, 'to = ' + Place2(D[I].B, U, False), I);
          Parts := TStringList.Create;
          try
            Parts.Text := D[I].Txt;
            for K := 0 to Parts.Count - 1 do
              Put(Depth + 1, 'text = ' + QuotedStr(Parts[K]), I);
          finally
            Parts.Free;
          end;
          if (D[I].Size > 0) and (Abs(D[I].Size - 1) > 1E-6) then
            Put(Depth + 1, 'size = ' + FloatToStrF(D[I].Size, ffGeneral, 4, 0, DotFS), I);
          PutInk(Depth + 1, I);
          Put(Depth, 'end', I);
        end;
    end;
  end;

  { Is this solid exactly a box and nothing more?  Eight corners on two
    heights, six axis-square four-corner faces with no holes, twelve ordinary
    edges, one paint or none.  Then it can be written as one, a primitive
    being a fold.  A box with a circle hole in its top is not, yet. }
  { Is this face what its scope's lines already imply (hsImpliedFaces's rule,
    which the reader applies)?  Then it is not written.  Loose covers the
    level's loose lines, since a disk in a box's top is implied by the circle
    drawn beside the box. }
  function FaceImplied(I: Integer; HasMat: Boolean; SMat: TColor): Boolean;
  begin
    Result := False;
    if InPass1 or (I >= Length(ImpliedGeom)) or not ImpliedGeom[I] then Exit;
    if D[I].Ink <> DefInk then Exit;
    if D[I].MatSet and not (HasMat and (D[I].Mat = SMat)) then Exit;
    if (not D[I].MatSet) and HasMat then Exit;
    Result := True;
  end;

  { Loops that close but are not faces, which the reader must not restore.
    Their corners use the drawing's names where it has them. }
  procedure PutNoFaces(Depth: Integer; const Pts: TPts; Part_, G: Integer);
  var
    R, K, F: Integer;
    Lp: TP3Array;
  begin
    if InPass1 then Exit;
    for R := 0 to High(NoFaceLoops) do
    begin
      if (NoFaceScope[R] <> G) or (NoFacePart[R] <> Part_) then Continue;
      Lp := Copy(NoFaceLoops[R]);
      for K := 0 to High(Lp) do
      begin
        for F := 0 to High(Pts) do
          if SamePt(Pts[F].P, Lp[K], 1E-5) then begin Lp[K] := Pts[F].P; Break; end;
      end;
      { a loop that is no face has no way round: a circle by its name either way }
      PutList(Depth, 'noface', Outline(Pts, Lp, Part_, True), -1);
    end;
  end;

  { A rectangle on the sheet, as the RECT tool makes it: four loose
    axis-square lines that close, and the plain face they imply.  Written
    "rect = corner; size", or as a block with a paint.  Anything else (odd
    lines, a reversed face, a hole, no face) is written as its lines. }
  { are A and B neighboring corners of face F, either way around? }
  function EdgeOf(F: Integer; const A, B: TP3): Boolean;
  var
    K, N: Integer;
  begin
    Result := False;
    N := Length(D[F].Poly);
    for K := 0 to N - 1 do
      if (SameP(D[F].Poly[K], A) and SameP(D[F].Poly[(K + 1) mod N], B)) or
         (SameP(D[F].Poly[K], B) and SameP(D[F].Poly[(K + 1) mod N], A)) then Exit(True);
  end;

  function IsRect(Part_, I: Integer; out Lines: TIntArrayW; out Face: Integer;
    out Lo, Size: TP3; out HasPaint: Boolean; out Paint: TColor; out Ink: TColor; out Wd: Single): Boolean;
  var
    K, J, F: Integer;
    Pts: array[0..3] of TP3;
    Hi: TP3;
    Loop: TP3Array;

    function Plain(L: Integer): Boolean;
    begin
      Result := (D[L].Kind = ekLine) and (D[L].Part = Part_) and (D[L].Grp = 0) and
        (not D[L].Soft) and (not D[L].Dim) and (D[L].Ink = D[I].Ink) and
        (Abs(D[L].Weight - D[I].Weight) <= 1E-3) and (AxesUsed(Sub3(D[L].B, D[L].A)) = 1);
    end;

    { Walk around, trying every plain line that leaves the corner and turns;
      three lines can meet at a corner and the first that turns may not be the
      rectangle's. }
    function Walk(K: Integer; const Cur: TP3): Boolean;
    var
      J: Integer;
      Nxt: TP3;
    begin
      Result := False;
      if K = 4 then Exit(SameP(Cur, Pts[0]));
      Pts[K] := Cur;
      for J := 0 to D.Live - 1 do
      begin
        if (J = Lines[0]) or not Plain(J) then Continue;
        if (K > 1) and ((J = Lines[1]) or ((K > 2) and (J = Lines[2]))) then Continue;
        if SameP(D[J].A, Cur) then Nxt := D[J].B
        else if SameP(D[J].B, Cur) then Nxt := D[J].A
        else Continue;
        if SameP(Nxt, Pts[K - 1]) then Continue;            { back the way we came }
        { a corner: the next edge runs along a different axis }
        if (Abs(Nxt.X - Cur.X) > 1E-9) = (Abs(Pts[K - 1].X - Cur.X) > 1E-9) then
          if (Abs(Nxt.Y - Cur.Y) > 1E-9) = (Abs(Pts[K - 1].Y - Cur.Y) > 1E-9) then Continue;
        Lines[K] := J;
        if Walk(K + 1, Nxt) then Exit(True);
      end;
    end;

  begin
    Result := False;
    Face := -1;
    HasPaint := False;
    Paint := 0;
    SetLength(Lines, 0);
    if (D[I].Kind <> ekLine) or not Plain(I) then Exit;
    Ink := D[I].Ink;
    Wd := D[I].Weight;
    SetLength(Lines, 4);
    Lines[0] := I;
    Pts[0] := D[I].A;
    if not Walk(1, D[I].B) then Exit;
    for K := 0 to 3 do
      for J := K + 1 to 3 do
        if (Lines[K] = Lines[J]) or SameP(Pts[K], Pts[J]) then Exit;
    { in one plane, square to it: two axes used across the four corners }
    Lo := Pts[0]; Hi := Pts[0];
    for K := 1 to 3 do
    begin
      Lo := P3(Min(Lo.X, Pts[K].X), Min(Lo.Y, Pts[K].Y), Min(Lo.Z, Pts[K].Z));
      Hi := P3(Max(Hi.X, Pts[K].X), Max(Hi.Y, Pts[K].Y), Max(Hi.Z, Pts[K].Z));
    end;
    Size := Sub3(Hi, Lo);
    if AxesUsed(Size) <> 2 then Exit;
    { the face: the plain one these corners imply, or a painted one }
    SetLength(Loop, 4);
    for K := 0 to 3 do Loop[K] := Pts[K];
    for F := 0 to D.Live - 1 do
      if (D[F].Kind = ekFace) and (D[F].Part = Part_) and (D[F].Grp = 0) and
         (Length(D[F].Holes) = 0) and (D[F].Ink = DefInk) and SameLoop(D[F].Poly, Loop) then
      begin
        Face := F;
        Break;
      end;
    if Face < 0 then Exit;
    { Its own four lines only: an edge shared with another face (the next
      stair step, the next window pane) is one line here and would become two
      if each rect made its own. }
    for K := 0 to 3 do
      for F := 0 to D.Live - 1 do
        if (D[F].Kind = ekFace) and (F <> Face) and EdgeOf(F, D[Lines[K]].A, D[Lines[K]].B) then Exit;
    if D[Face].MatSet then
    begin
      HasPaint := True;
      Paint := D[Face].Mat;
      { turned the way the reader turns one it paints: OrientFace's way }
      if Dot3(D.FaceNormal(Face), P3(Ord(Abs(Size.X) < 1E-9), Ord((Abs(Size.X) >= 1E-9) and (Abs(Size.Y) < 1E-9)),
           Ord((Abs(Size.X) >= 1E-9) and (Abs(Size.Y) >= 1E-9)))) <= 0 then Exit;
    end
    else if not FaceImplied(Face, False, 0) then Exit;
    Result := True;
  end;

  { A disk in a box's face: a face of the solid whose outline is a named
    circle.  Written after the box as "face = c1"; the reader cuts the hole
    again from the circle. }
  function IsDisk(I, Part_: Integer): Boolean;
  begin
    Result := (D[I].Kind = ekFace) and (Length(D[I].Poly) >= 8) and
      (Length(D[I].Holes) = 0) and (CircleNamed(D[I].Poly, Part_) <> '');
  end;

  { One pen over all of a fold's lines, any ink or width as long as they all
    match; written in the block when not the sheet's. }
  function OnePen(Part_, G: Integer; out Ink: TColor; out Wd: Single): Boolean;
  var
    I, N: Integer;
  begin
    Result := False;
    N := 0;
    Ink := DefInk;
    Wd := DefWidth;
    for I := 0 to D.Live - 1 do
      if (D[I].Kind = ekLine) and (D[I].Grp = G) and (D[I].Part = Part_) then
      begin
        if N = 0 then begin Ink := D[I].Ink; Wd := D[I].Weight; end
        else if (D[I].Ink <> Ink) or (Abs(D[I].Weight - Wd) > 1E-3) then Exit;
        Inc(N);
      end;
    Result := N > 0;
  end;

  { a hole whose sides are all loose lines of the group (a rectangle drawn
    on the face): written on its own, it cuts the face again when read }
  function LooseLoop(const Lp: array of TP3; Part_: Integer): Boolean;
  var
    K, L: Integer;
    Found: Boolean;

    function OnLine(const P: TP3; L: Integer): Boolean;
    var
      T, Len2: Double;
      Q: TP3;
    begin
      Q := Sub3(D[L].B, D[L].A);
      Len2 := Dot3(Q, Q);
      if Len2 < 1E-18 then Exit(False);
      T := Dot3(Sub3(P, D[L].A), Q) / Len2;
      if (T < -1E-9) or (T > 1 + 1E-9) then Exit(False);
      Result := Dist(P, Add3(D[L].A, Mul3(Q, T))) < 1E-6;
    end;

  begin
    Result := False;
    for K := 0 to High(Lp) do
    begin
      Found := False;
      for L := 0 to D.Live - 1 do
        if (D[L].Kind = ekLine) and (D[L].Grp = 0) and (D[L].Part = Part_) and
           OnLine(Lp[K], L) and OnLine(Lp[(K + 1) mod Length(Lp)], L) then
        begin
          Found := True;
          Break;
        end;
      if not Found then Exit;
    end;
    Result := True;
  end;

  { Is this solid exactly a box and nothing more?  Eight corners on two
    heights, twelve ordinary edges, and a four-corner face facing out on
    each side but those left open (Open, a bit per BOX_SIDES), with no
    hole but a circle drawn on it; one paint or none. }
  function IsBox(Part_, G: Integer; out Lo, Hi: TP3; out HasPaint: Boolean; out Paint: TColor;
    out Ink: TColor; out Wd: Single; out Open: Integer): Boolean;
  const
    FACINGS: array[0..5] of string = ('down', 'up', 'south', 'east', 'north', 'west');
  var
    I, K, NF, NL, NPaint, Side, Have: Integer;
    Pts: TPts;
    W: string;
    OnSide: Boolean;
    Sides: array[0..5] of Integer;
  begin
    Result := False;
    Open := 0;
    SetLength(Pts, 0);
    NF := 0; NL := 0; NPaint := 0; Have := 0;
    HasPaint := False; Paint := 0;
    if not OnePen(Part_, G, Ink, Wd) then Exit;
    for I := 0 to D.Live - 1 do
    begin
      if (D[I].Grp <> G) or (D[I].Part <> Part_) then Continue;
      if IsDisk(I, Part_) then Continue;
      case D[I].Kind of
        ekFace:
          begin
            Inc(NF);
            if (Length(D[I].Poly) <> 4) or (D[I].Ink <> DefInk) then Exit;
            { a hole is allowed when it is a circle drawn on the face: the box is
              still a box, and the circle is written on its own }
            for K := 0 to High(D[I].Holes) do
              if (CircleNamed(D[I].Holes[K], Part_) = '') and not LooseLoop(D[I].Holes[K], Part_) then Exit;
            W := FacingWord(D.FaceNormal(I));
            Side := High(FACINGS);
            while (Side >= 0) and (FACINGS[Side] <> W) do Dec(Side);
            if (Side < 0) or (Have and (1 shl Side) <> 0) then Exit;
            Have := Have or (1 shl Side);
            Sides[Side] := I;
            if D[I].MatSet then
            begin
              if (NPaint > 0) and (D[I].Mat <> Paint) then Exit;
              Paint := D[I].Mat;
              Inc(NPaint);
            end;
          end;
        ekLine:
          begin
            Inc(NL);
            if D[I].Soft or D[I].Dim then Exit;
            if AxesUsed(Sub3(D[I].B, D[I].A)) <> 1 then Exit;
            AddPt(Pts, D[I].A);
            AddPt(Pts, D[I].B);
          end;
        ekBore: Exit;
      end;
    end;
    if (NF < 1) or (NL <> 12) or (Length(Pts) <> 8) then Exit;
    if (NPaint <> 0) and (NPaint <> NF) then Exit;
    HasPaint := NPaint = NF;
    Lo := Pts[0].P; Hi := Pts[0].P;
    for I := 1 to 7 do
    begin
      Lo := P3(Min(Lo.X, Pts[I].P.X), Min(Lo.Y, Pts[I].P.Y), Min(Lo.Z, Pts[I].P.Z));
      Hi := P3(Max(Hi.X, Pts[I].P.X), Max(Hi.Y, Pts[I].P.Y), Max(Hi.Z, Pts[I].P.Z));
    end;
    { every corner at a min or max of each axis: the eight of a box }
    for I := 0 to 7 do
      if not ((Abs(Pts[I].P.X - Lo.X) < 1E-9) or (Abs(Pts[I].P.X - Hi.X) < 1E-9)) or
         not ((Abs(Pts[I].P.Y - Lo.Y) < 1E-9) or (Abs(Pts[I].P.Y - Hi.Y) < 1E-9)) or
         not ((Abs(Pts[I].P.Z - Lo.Z) < 1E-9) or (Abs(Pts[I].P.Z - Hi.Z) < 1E-9)) then Exit;
    if (Hi.X - Lo.X < 1E-9) or (Hi.Y - Lo.Y < 1E-9) or (Hi.Z - Lo.Z < 1E-9) then Exit;
    { each face on its own side, facing out }
    for Side := 0 to 5 do
    begin
      if Have and (1 shl Side) = 0 then
      begin
        Open := Open or (1 shl Side);
        Continue;
      end;
      for K := 0 to 3 do
      begin
        case Side of
          0: OnSide := Abs(D[Sides[Side]].Poly[K].Z - Lo.Z) < 1E-9;
          1: OnSide := Abs(D[Sides[Side]].Poly[K].Z - Hi.Z) < 1E-9;
          2: OnSide := Abs(D[Sides[Side]].Poly[K].Y - Lo.Y) < 1E-9;
          3: OnSide := Abs(D[Sides[Side]].Poly[K].X - Hi.X) < 1E-9;
          4: OnSide := Abs(D[Sides[Side]].Poly[K].Y - Hi.Y) < 1E-9;
        else
          OnSide := Abs(D[Sides[Side]].Poly[K].X - Lo.X) < 1E-9;
        end;
        if not OnSide then Exit;
      end;
    end;
    Result := True;
  end;

  { the open sides as words, "top north" }
  function OpenWords(Open: Integer): string;
  var
    K: Integer;
  begin
    Result := '';
    for K := 0 to High(BOX_SIDES) do
      if Open and (1 shl K) <> 0 then
      begin
        if Result <> '' then Result := Result + ' ';
        Result := Result + BOX_SIDES[K];
      end;
  end;

  { the pen of a fold's lines, when it is not the sheet's }
  procedure PutPen(Depth: Integer; Ink: TColor; Wd: Single);
  begin
    if Ink <> DefInk then Put(Depth, 'ink = ' + Color2(Ink), -1);
    if Abs(Wd - DefWidth) > 1E-3 then Put(Depth, 'width = ' + FloatToStrF(Wd, ffGeneral, 4, 0, DotFS), -1);
  end;

  function PlainPen(Ink: TColor; Wd: Single): Boolean;
  begin
    Result := (Ink = DefInk) and (Abs(Wd - DefWidth) <= 1E-3);
  end;

  procedure PutBox(Depth, Part_, G: Integer; const Lo, Hi: TP3; HasPaint: Boolean; Paint: TColor;
    Ink: TColor; Wd: Single; Open: Integer);
  var
    I, Header: Integer;
    NoPts: TPts;
    Nm, Note: string;
  begin
    Header := NLine;
    SolidNaming(Part_, G, Nm, Note);
    PutNote(Depth, Note, -1);
    if HasPaint or not PlainPen(Ink, Wd) then
    begin
      Put(Depth, 'box' + NameWord(Nm) + TailNote(Note), -1);
      Put(Depth + 1, 'at   = ' + Place2(Lo, U, False), -1);
      Put(Depth + 1, 'size = ' + Place2(Sub3(Hi, Lo), U, True), -1);
      if Open <> 0 then Put(Depth + 1, 'open = ' + OpenWords(Open), -1);
      if HasPaint then Put(Depth + 1, 'paint = ' + Color2(Paint), -1);
      PutPen(Depth + 1, Ink, Wd);
      Put(Depth, 'end', -1);
    end
    else if Open <> 0 then
      Put(Depth, 'box' + NameWord(Nm) + ' = ' + Place2(Lo, U, False) + '; ' + Place2(Sub3(Hi, Lo), U, True) +
        '; open ' + OpenWords(Open) + TailNote(Note), -1)
    else
      Put(Depth, 'box' + NameWord(Nm) + ' = ' + Place2(Lo, U, False) + '; ' + Place2(Sub3(Hi, Lo), U, True) +
        TailNote(Note), -1);
    { every face and edge maps to this statement, so picking on the sheet
      lights up the box }
    for I := 0 to D.Live - 1 do
      if (D[I].Grp = G) and (D[I].Part = Part_) and (D[I].Kind in [ekFace, ekLine]) and
         not IsDisk(I, Part_) then
      begin
        First[I] := Header;
        Last[I] := NLine - 1;
      end;
    { and the disks in its faces by their circles' names, unless the circle
      beside the box already gives them }
    SetLength(NoPts, 0);
    for I := 0 to D.Live - 1 do
      if (D[I].Grp = G) and (D[I].Part = Part_) and IsDisk(I, Part_) then
        if FaceImplied(I, HasPaint, Paint) then
        begin
          First[I] := Header;
          Last[I] := Header;
        end
        else
          PutFace(Depth, I, NoPts, HasPaint, Paint);
    { and a disk rubbed out of a circle on it, or the loop would close again }
    PutNoFaces(Depth, NoPts, Part_, G);
  end;

  { A pull: a flat outline moved some distance, what push/pull makes of a
    face, including the cylinder of a pulled disk.  It needs a bottom face, its
    twin a step away, and a wall per side: no hole or bore, one paint or none,
    every line an edge of those (uprights soft around a circle).  Every face must
    face the way the reader will turn it, since the reader rebuilds them. }
  function IsPull(Part_, G: Integer; out Bottom: Integer; out By: TP3; out Round_: Boolean;
    out HasPaint: Boolean; out Paint: TColor; out Ink: TColor; out Wd: Single): Boolean;
  var
    I, J, K, C, N, NF, NPaint, Top, Best, NBottom, NTop, NUp, NArc: Integer;
    V, Mid: TP3;
    Segs: TSegArray;
    Faces: array of Integer;
    Used: array of Boolean;
    Q: TP3Array;
    Hit, Ok_: Boolean;
    Outer: TP3Array;
    Holes: TLoopArray;
    R: TRegion;

    function CornerAt(const P: TP3; const Poly: TP3Array): Integer;
    var
      C: Integer;
    begin
      Result := -1;
      for C := 0 to High(Poly) do
        if SameP(Poly[C], P) then Exit(C);
    end;

  begin
    Result := False;
    Bottom := -1;
    Round_ := False;
    HasPaint := False;
    Paint := 0;
    SetLength(Faces, 0);
    NPaint := 0;
    if not OnePen(Part_, G, Ink, Wd) then Exit;
    for I := 0 to D.Live - 1 do
    begin
      if (D[I].Grp <> G) or (D[I].Part <> Part_) then Continue;
      case D[I].Kind of
        ekFace:
          begin
            if D[I].Ink <> DefInk then Exit;
            { a circle drawn on an end (a motor on a housing) is written on
              its own and cuts the end again when read, as on a box }
            for K := 0 to High(D[I].Holes) do
              if CircleNamed(D[I].Holes[K], Part_) = '' then Exit;
            SetLength(Faces, Length(Faces) + 1);
            Faces[High(Faces)] := I;
            if D[I].MatSet then
            begin
              if (NPaint > 0) and (D[I].Mat <> Paint) then Exit;
              Paint := D[I].Mat;
              Inc(NPaint);
            end;
          end;
        ekBore: Exit;
        ekLine:
          if D[I].Dim then Exit;
      end;
    end;
    NF := Length(Faces);
    if NF < 5 then Exit;
    if (NPaint <> 0) and (NPaint <> NF) then Exit;
    HasPaint := NPaint = NF;
    { the bottom and its twin: the two faces with the most corners, a step
      apart; the bottom is the one the step goes away from }
    Best := 0;
    for I := 0 to NF - 1 do
      if Length(D[Faces[I]].Poly) > Best then Best := Length(D[Faces[I]].Poly);
    N := Best;
    if N + 2 <> NF then Exit;
    Top := -1;
    for I := 0 to NF - 1 do
    begin
      if Length(D[Faces[I]].Poly) <> N then Continue;
      for J := 0 to NF - 1 do
      begin
        if (J = I) or (Length(D[Faces[J]].Poly) <> N) then Continue;
        { The step: from the first bottom corner to its twin on top.  The top
          need not start where the bottom does. }
        for C := 0 to N - 1 do
        begin
          V := Sub3(D[Faces[J]].Poly[C], D[Faces[I]].Poly[0]);
          Ok_ := AxesUsed(V) > 0;
          for K := 0 to N - 1 do
            if Ok_ and (CornerAt(Add3(D[Faces[I]].Poly[K], V), D[Faces[J]].Poly) < 0) then Ok_ := False;
          if Ok_ and (Dot3(D.FaceNormal(Faces[I]), V) < 0) and (Dot3(D.FaceNormal(Faces[J]), V) > 0) then
          begin
            { Either end could be the bottom.  Prefer the circle (the tool pulled the
              disk up from it), else the one the step goes up, north or east from, so
              the same solid is always written the same way. }
            if (Top < 0) or (CircleNamed(D[Faces[I]].Poly, Part_) <> '') or
               ((CircleNamed(D[Bottom].Poly, Part_) = '') and
                (V.Z + V.Y * 1E-3 + V.X * 1E-6 > By.Z + By.Y * 1E-3 + By.X * 1E-6)) then
            begin
              Bottom := Faces[I];
              Top := Faces[J];
              By := V;
            end;
            Break;
          end;
        end;
      end;
    end;
    if Top < 0 then Exit;
    { every other face a wall: two neighboring bottom corners and their
      twins above }
    SetLength(Used, NF);
    for I := 0 to NF - 1 do Used[I] := (Faces[I] = Bottom) or (Faces[I] = Top);
    for K := 0 to N - 1 do
    begin
      SetLength(Q, 4);
      Q[0] := D[Bottom].Poly[K];
      Q[1] := D[Bottom].Poly[(K + 1) mod N];
      Q[2] := Add3(Q[1], By);
      Q[3] := Add3(Q[0], By);
      Hit := False;
      for I := 0 to NF - 1 do
        if not Used[I] and (Length(D[Faces[I]].Poly) = 4) and SameLoop(D[Faces[I]].Poly, Q) then
        begin
          Used[I] := True;
          Hit := True;
          Break;
        end;
      if not Hit then Exit;
    end;
    { round: the bottom is a named circle, and the uprights are soft }
    Round_ := CircleNamed(D[Bottom].Poly, Part_) <> '';
    { Every line must be a bottom, top or upright edge and every such edge a
      line of this solid, since the reader makes them all.  So a solid sharing
      its bottom edges with the one it stands on is not a pull. }
    NBottom := 0; NTop := 0; NUp := 0; NArc := 0;
    for I := 0 to D.Live - 1 do
    begin
      if (D[I].Grp <> G) or (D[I].Part <> Part_) then Continue;
      if D[I].Kind = ekArc then
      begin
        if not Round_ or (CircleName(I) = '') then Exit;
        Inc(NArc);
        Continue;
      end;
      if D[I].Kind <> ekLine then Continue;
      J := CornerAt(D[I].A, D[Bottom].Poly);
      K := CornerAt(D[I].B, D[Bottom].Poly);
      if (J >= 0) and (K >= 0) then
      begin
        if Round_ or (Abs(J - K) <> 1) and (Abs(J - K) <> N - 1) then Exit;   { a bottom edge, not for a circle }
        if D[I].Soft then Exit;
        Inc(NBottom);
        Continue;
      end;
      Ok_ := False;
      if (J >= 0) and (CornerAt(D[I].B, D[Top].Poly) >= 0) then
        Ok_ := SameP(D[I].B, Add3(D[I].A, By))
      else if (K >= 0) and (CornerAt(D[I].A, D[Top].Poly) >= 0) then
        Ok_ := SameP(D[I].A, Add3(D[I].B, By));
      if Ok_ then
      begin
        if D[I].Soft <> Round_ then Exit;      { an upright }
        Inc(NUp);
        Continue;
      end;
      J := CornerAt(D[I].A, D[Top].Poly);
      K := CornerAt(D[I].B, D[Top].Poly);
      if (J < 0) or (K < 0) or ((Abs(J - K) <> 1) and (Abs(J - K) <> N - 1)) then Exit;
      if D[I].Soft then Exit;                  { a top edge }
      Inc(NTop);
    end;
    if (NTop <> N) or (NUp <> N) then Exit;
    { Round: the circle may be this solid's or another's (a disk drawn on a
      box and pulled stands on the box's hole), but there are no bottom lines. }
    if Round_ then begin if (NArc > 1) or (NBottom <> 0) then Exit; end
    else if NBottom <> N then Exit;
    { and facing the way the reader will turn them: away from the middle of
      the edges it will be given }
    SetLength(Segs, 3 * N);
    for K := 0 to N - 1 do
    begin
      Segs[3 * K].A := D[Bottom].Poly[K];
      Segs[3 * K].B := D[Bottom].Poly[(K + 1) mod N];
      Segs[3 * K + 1].A := P3(Segs[3 * K].A.X + By.X, Segs[3 * K].A.Y + By.Y, Segs[3 * K].A.Z + By.Z);
      Segs[3 * K + 1].B := P3(Segs[3 * K].B.X + By.X, Segs[3 * K].B.Y + By.Y, Segs[3 * K].B.Z + By.Z);
      Segs[3 * K + 2].A := Segs[3 * K].A;
      Segs[3 * K + 2].B := Segs[3 * K + 1].A;
    end;
    Mid := ScopeMid(Segs);
    for I := 0 to NF - 1 do
    begin
      R.Outer := Copy(D[Faces[I]].Poly);
      SetLength(R.Holes, 0);
      R.Normal := D.FaceNormal(Faces[I]);
      ImpliedLoop(R, True, Mid, Outer, Holes);
      if Dot3(LoopNormal(Outer), D.FaceNormal(Faces[I])) <= 0 then Exit;
    end;
    Result := True;
  end;

  procedure PutPull(Depth, Part_, G, Bottom: Integer; const By: TP3; Round_, HasPaint: Boolean;
    Paint: TColor; Ink: TColor; Wd: Single);
  var
    I, Header, Best: Integer;
    NoPts: TPts;
    It: TStringArray;
    Step, Nm, Note: string;
    Poly: TP3Array;
  begin
    Header := NLine;
    SolidNaming(Part_, G, Nm, Note);
    PutNote(Depth, Note, -1);
    SetLength(NoPts, 0);
    { Start from the corner nearest the origin, going the way the face goes,
      so the same solid is always written the same way. }
    Poly := Copy(D[Bottom].Poly);
    Best := 0;
    for I := 1 to High(Poly) do
      if (Poly[I].X < Poly[Best].X - 1E-9) or
         ((Abs(Poly[I].X - Poly[Best].X) <= 1E-9) and (Poly[I].Y < Poly[Best].Y - 1E-9)) or
         ((Abs(Poly[I].X - Poly[Best].X) <= 1E-9) and (Abs(Poly[I].Y - Poly[Best].Y) <= 1E-9) and
          (Poly[I].Z < Poly[Best].Z - 1E-9)) then Best := I;
    for I := 0 to High(Poly) do Poly[I] := D[Bottom].Poly[(Best + I) mod Length(Poly)];
    { a named circle whichever way the bottom faces: a pull's outline has no
      facing of its own }
    if Round_ then
    begin
      SetLength(It, 1);
      It[0] := CircleNamed(D[Bottom].Poly, Part_);
    end
    else
      It := Outline(NoPts, Poly, Part_);
    Step := Place2(By, U, True);
    { one line while it fits ("pull = c1; 2' up"), a block when the outline
      runs long or there is a paint }
    if not HasPaint and PlainPen(Ink, Wd) and (Depth * 2 + 9 + Length(NameWord(Nm)) + Length(Joined(It)) + Length(Step) <= 78) then
      Put(Depth, 'pull' + NameWord(Nm) + ' = ' + Joined(It) + '; ' + Step + TailNote(Note), -1)
    else
    begin
      Put(Depth, 'pull' + NameWord(Nm) + TailNote(Note), -1);
      PutList(Depth + 1, 'points', It, -1);
      Put(Depth + 1, 'by = ' + Step, -1);
      if HasPaint then Put(Depth + 1, 'paint = ' + Color2(Paint), -1);
      PutPen(Depth + 1, Ink, Wd);
      Put(Depth, 'end', -1);
    end;
    for I := 0 to D.Live - 1 do
      if (D[I].Grp = G) and (D[I].Part = Part_) and (D[I].Kind in [ekFace, ekLine]) then
      begin
        First[I] := Header;
        Last[I] := NLine - 1;
      end;
    PutNoFaces(Depth, NoPts, Part_, G);
  end;

  { A solid a statement made (a loft) and nothing since: its fingerprint
    still matches, one paint or none, one pen, and every circle it names is
    still there by that name.  Gives the statement's outlines and open ends. }
  function MadeAs(Part_, G: Integer; out Through, OpenW, Exact: string; out HasPaint: Boolean;
    out Paint: TColor; out Ink: TColor; out Wd: Single; out Extras: TIntArrayW): Boolean;
  var
    I, K, NPaint, NF: Integer;
    Made, Stmt, Fp, W: string;
    Found: Boolean;
  begin
    Result := False;
    Through := '';
    OpenW := '';
    Exact := '';
    HasPaint := False;
    Paint := 0;
    Made := '';
    SetLength(Extras, 0);
    NPaint := 0;
    NF := 0;
    for I := 0 to D.Live - 1 do
      if (D[I].Grp = G) and (D[I].Part = Part_) and (D[I].Kind <> ekPart) then
      begin
        if D[I].Made = '' then Exit;
        { a face that joined the loft is written beside it }
        if D[I].Made[1] = #4 then
        begin
          if D[I].Kind <> ekFace then Exit;
          SetLength(Extras, Length(Extras) + 1);
          Extras[High(Extras)] := I;
          Continue;
        end;
        if Made = '' then Made := D[I].Made
        else if D[I].Made <> Made then Exit;
        if D[I].Kind = ekFace then
        begin
          Inc(NF);
          if D[I].MatSet then
          begin
            if (NPaint > 0) and (D[I].Mat <> Paint) then Exit;
            Paint := D[I].Mat;
            Inc(NPaint);
          end;
        end;
      end;
    if Made = '' then Exit;
    if (NPaint <> 0) and (NPaint <> NF) then Exit;
    HasPaint := NPaint > 0;
    if not OnePen(Part_, G, Ink, Wd) then Exit;
    K := Pos(#2, Made);
    if K = 0 then Exit;
    Stmt := Copy(Made, 1, K - 1);
    Fp := Copy(Made, K + 1, MaxInt);
    if SolidPrint(D, G, Part_) <> Fp then Exit;
    for I := 0 to High(Extras) do
      if D[Extras[I]].Made <> #4 + Fp then Exit;
    K := Pos(#3, Stmt);
    if K > 0 then
    begin
      Exact := Copy(Stmt, K + 1, MaxInt);
      Stmt := Copy(Stmt, 1, K - 1);
    end;
    K := Pos(#1, Stmt);
    if K > 0 then
    begin
      Through := Copy(Stmt, 1, K - 1);
      OpenW := Copy(Stmt, K + 1, MaxInt);
    end
    else Through := Stmt;
    for W in Through.Split([';']) do
      if (Pos(' ', Trim(W)) = 0) and (Pos(',', Trim(W)) = 0) then
      begin
        Found := False;
        for K := 0 to High(CircleNames) do
          if SameText(CircleNames[K], Trim(W)) then Found := True;
        if not Found then Exit;
      end;
    Result := True;
  end;

  procedure PutMade(Depth, Part_, G: Integer; Through: string; const OpenW, Exact: string;
    HasPaint: Boolean; Paint: TColor; Ink: TColor; Wd: Single; const Extras: TIntArrayW);
  var
    I, K, Header: Integer;
    Nm, Note, W, C: string;
    Outlines, Ex, It: TStringArray;
    Polys: array of array of TP3;
    Pts, NoPts: TPts;
    Named_: Boolean;

    { on one line if it fits, else an outline to a line between brackets }
    procedure PutThrough(D_: Integer; const Head: string);
    var
      K: Integer;
    begin
      if D_ * 2 + Length(Head) + 3 + Length(Through) <= 78 then
      begin
        Put(D_, Head + ' = ' + Through, -1);
        Exit;
      end;
      Put(D_, Head + ' = (', -1);
      Outlines := Through.Split([';']);
      for K := 0 to High(Outlines) do
        if K < High(Outlines) then Put(D_ + 1, Trim(Outlines[K]) + ';', -1)
        else Put(D_ + 1, Trim(Outlines[K]), -1);
      Put(D_, ')', -1);
    end;

  begin
    Header := NLine;
    { corners named when it was read are named again, in its own points }
    SetLength(Pts, 0);
    SetLength(NoPts, 0);
    Ex := Exact.Split([';']);
    Outlines := Through.Split([';']);
    SetLength(Polys, Length(Ex));
    for I := 0 to High(Ex) do
    begin
      SetLength(Polys[I], 0);
      for C in Ex[I].Split([' '], TStringSplitOptions.ExcludeEmpty) do
      begin
        It := C.Split([',']);
        SetLength(Polys[I], Length(Polys[I]) + 1);
        Polys[I][High(Polys[I])] := P3(StrToFloat(It[0], DotFS), StrToFloat(It[1], DotFS), StrToFloat(It[2], DotFS));
      end;
      for K := 0 to High(Polys[I]) do
      begin
        AddPt(Pts, Polys[I][K]);
        Pts[High(Pts)].InHole := False;
      end;
    end;
    GivenNames(Pts, Part_, G);
    Named_ := Given and (Length(Ex) = Length(Outlines));
    SolidNaming(Part_, G, Nm, Note);
    PutNote(Depth, Note, -1);
    W := TailNote(Note);
    if not Named_ and not HasPaint and PlainPen(Ink, Wd) and (OpenW = '') and (W = '') then
      PutThrough(Depth, 'loft' + NameWord(Nm))
    else
    begin
      Put(Depth, 'loft' + NameWord(Nm) + W, -1);
      if Named_ then
      begin
        PutPoints(Depth + 1, Pts, nil);
        Through := '';
        for I := 0 to High(Outlines) do
        begin
          if I > 0 then Through := Through + '; ';
          if Length(Polys[I]) = 0 then Through := Through + Trim(Outlines[I])
          else Through := Through + String.Join(' ', Runs(Items(Pts, Polys[I])));
        end;
      end;
      PutThrough(Depth + 1, 'through');
      if OpenW <> '' then Put(Depth + 1, 'open = ' + OpenW, -1);
      if HasPaint then Put(Depth + 1, 'paint = ' + Color2(Paint), -1);
      PutPen(Depth + 1, Ink, Wd);
      Put(Depth, 'end', -1);
    end;
    for I := 0 to D.Live - 1 do
      if (D[I].Grp = G) and (D[I].Part = Part_) and (D[I].Kind in [ekFace, ekLine]) and
         (D[I].Made[1] <> #4) then
      begin
        First[I] := Header;
        Last[I] := NLine - 1;
      end;
    SetLength(NoPts, 0);
    for I := 0 to High(Extras) do PutFace(Depth, Extras[I], NoPts);
    { openings cut in it (a port in a hull); the loft's own rings it makes again }
    PutNoFaces(Depth, NoPts, Part_, G);
  end;

  { One solid: its corners once, its faces, and only unusual edges; the rest
    are the faces' sides and go unwritten. }
  procedure PutSolid(Depth, Part_, G: Integer);
  var
    Pts: TPts;
    I, J, K, N, Header, Best, LinesFrom: Integer;
    HasMat: Boolean;
    SMat: TColor;
    Rings: TRings;
    Rg: TRing;
    Implied: array of Boolean;
    Nm, Note: string;

  begin
    SetLength(Implied, D.Live);
    SetLength(Pts, 0);
    N := 0;
    for I := 0 to D.Live - 1 do
      if (D[I].Kind = ekFace) and (D[I].Grp = G) and (D[I].Part = Part_) then
      begin
        Inc(N);
        { a loop that is a named circle ("face = c1", "hole = c1") has no corners
          to list }
        if CircleNamed(D[I].Poly, Part_) = '' then
          for K := 0 to High(D[I].Poly) do
          begin
            AddPt(Pts, D[I].Poly[K]);
            Pts[FindPt(Pts, D[I].Poly[K])].InHole := False;
          end;
        for J := 0 to High(D[I].Holes) do
          if CircleNamed(D[I].Holes[J], Part_) = '' then
            for K := 0 to High(D[I].Holes[J]) do AddPt(Pts, D[I].Holes[J][K]);
      end;
    { what most of its faces are made of is given once, for the solid }
    HasMat := False;
    SMat := 0;
    Best := 0;
    for I := 0 to D.Live - 1 do
      if (D[I].Kind = ekFace) and (D[I].Grp = G) and (D[I].Part = Part_) and D[I].MatSet then
      begin
        K := 0;
        for J := 0 to D.Live - 1 do
          if (D[J].Kind = ekFace) and (D[J].Grp = G) and (D[J].Part = Part_) and
             D[J].MatSet and (D[J].Mat = D[I].Mat) then Inc(K);
        if K > Best then begin Best := K; SMat := D[I].Mat; end;
        if Best * 2 > N then Break;
      end;
    HasMat := (Best >= 2) and (Best * 2 > N);
    { Round faces' corners are rings, each given once, corners named ra1,
      ra2... in the order that face goes around. }
    SetLength(Rings, 0);
    for I := 0 to High(Pts) do Pts[I].Ring := -1;
    for I := 0 to D.Live - 1 do
      if (D[I].Kind = ekFace) and (D[I].Grp = G) and (D[I].Part = Part_) then
        for J := -1 to High(D[I].Holes) do
        begin
          if J < 0 then Best := Ord(RingOf(D[I].Poly, Rg))
          else Best := Ord(RingOf(D[I].Holes[J], Rg));
          if Best = 0 then Continue;
          if J < 0 then begin if CircleNamed(D[I].Poly, Part_) <> '' then Continue; end
          else if CircleNamed(D[I].Holes[J], Part_) <> '' then Continue;
          if J < 0 then K := FindPt(Pts, D[I].Poly[0]) else K := FindPt(Pts, D[I].Holes[J][0]);
          if (K < 0) or (Pts[K].Ring >= 0) then Continue;   { that ring is known }
          Rg.Name := 'r' + Chr(Ord('a') + Length(Rings) mod 26);
          if Length(Rings) >= 26 then Rg.Name := Rg.Name + IntToStr(Length(Rings) div 26);
          SetLength(Rings, Length(Rings) + 1);
          Rings[High(Rings)] := Rg;
          for Best := 0 to Rg.N - 1 do
          begin
            if J < 0 then K := FindPt(Pts, D[I].Poly[Best]) else K := FindPt(Pts, D[I].Holes[J][Best]);
            if (K >= 0) and (Pts[K].Ring < 0) then
            begin
              Pts[K].Ring := High(Rings);
              Pts[K].Name := Rg.Name + IntToStr(Best + 1);
            end;
          end;
        end;
    Header := NLine;
    GivenNames(Pts, Part_, G);
    SolidNaming(Part_, G, Nm, Note);
    PutNote(Depth, Note, -1);
    Put(Depth, 'solid' + NameWord(Nm) + TailNote(Note), -1);
    if HasMat then Put(Depth + 1, 'paint = ' + Color2(SMat), -1);
    PutPoints(Depth + 1, Pts, Rings);
    for I := 0 to D.Live - 1 do
      if (D[I].Kind = ekFace) and (D[I].Grp = G) and (D[I].Part = Part_) then
      begin
        Implied[I] := FaceImplied(I, HasMat, SMat);
        if not Implied[I] then PutFace(Depth + 1, I, Pts, HasMat, SMat);
      end;
    PutNoFaces(Depth + 1, Pts, Part_, G);
    LinesFrom := NLine;
    for I := 0 to D.Live - 1 do
      if (D[I].Kind = ekLine) and (D[I].Grp = G) and (D[I].Part = Part_) then
      begin
        PutLine(Depth + 1, I, Pts);
      end
      else if (D[I].Kind = ekBore) and (D[I].Grp = G) and (D[I].Part = Part_) then
      begin
        Put(Depth + 1, 'bore', I);
        PutList(Depth + 2, 'points', Items(Pts, D[I].Poly), I);
        Put(Depth + 2, 'goes = ' + Place2(Sub3(D[I].B, D[I].Poly[0]), U, True), I);
        Put(Depth + 1, 'end', I);
      end;
    { an unwritten face maps to its edges, so picking it lights up the lines }
    for I := 0 to D.Live - 1 do
      if (D[I].Kind = ekFace) and (D[I].Grp = G) and (D[I].Part = Part_) and Implied[I] then
      begin
        First[I] := LinesFrom;
        Last[I] := NLine - 1;
      end;
    Put(Depth, 'end', -1);
  end;

  { everything in one group (Part_ 0 is the sheet), then the groups inside it }
  procedure PutLevel(Depth, Part_: Integer);
  var
    I, J, G, LinesFrom, PBottom, RFace, Header, BOpen: Integer;
    MThrough, MOpen, MExact: string;
    MExtras: TIntArrayW;
    Done: array of Integer;
    Seen, BPaintOn, PRound: Boolean;
    None: TPts;
    BLo, BHi, PBy, RLo, RSize: TP3;
    BPaint, PInk: TColor;
    PWd: Single;
    Implied, RectDone, RectAt, ChainDone: array of Boolean;
    RLines, Chain: TIntArrayW;
    ChainPoly: TP3Array;

    { the named loose lines that carry on from line I, end to end, in the
      same pen }
    procedure FindChain(I: Integer);
    var
      K: Integer;
      Tip: TP3;
      More: Boolean;
    begin
      SetLength(Chain, 1);
      Chain[0] := I;
      SetLength(ChainPoly, 2);
      ChainPoly[0] := D[I].A;
      ChainPoly[1] := D[I].B;
      Tip := D[I].B;
      repeat
        More := False;
        for K := I + 1 to D.Live - 1 do
          if (D[K].Kind = ekLine) and not ChainDone[K] and not RectDone[K] and (D[K].Part = Part_) and
             (D[K].Grp = 0) and (D[K].Name = D[I].Name) and (D[K].Ink = D[I].Ink) and
             (Abs(D[K].Weight - D[I].Weight) <= 1E-3) and (D[K].Soft = D[I].Soft) and
             (D[K].Dim = D[I].Dim) and (SameP(D[K].A, Tip) or SameP(D[K].B, Tip)) then
          begin
            if SameP(D[K].A, Tip) then Tip := D[K].B else Tip := D[K].A;
            ChainDone[K] := True;
            SetLength(Chain, Length(Chain) + 1);
            Chain[High(Chain)] := K;
            SetLength(ChainPoly, Length(ChainPoly) + 1);
            ChainPoly[High(ChainPoly)] := Tip;
            More := True;
            Break;
          end;
      until not More;
    end;

  begin
    SetLength(None, 0);
    SetLength(Done, 0);
    SetLength(Implied, D.Live);
    SetLength(RectDone, D.Live);
    for I := 0 to D.Live - 1 do RectDone[I] := False;
    SetLength(ChainDone, D.Live);
    for I := 0 to D.Live - 1 do ChainDone[I] := False;
    { Rectangles first, so a face met before its lines is known to be one;
      each is written where its first line falls. }
    SetLength(RectAt, D.Live);
    for I := 0 to D.Live - 1 do RectAt[I] := False;
    for I := 0 to D.Live - 1 do
      if (D[I].Kind = ekLine) and (D[I].Part = Part_) and (D[I].Grp = 0) and not RectDone[I] and
         IsRect(Part_, I, RLines, RFace, RLo, RSize, BPaintOn, BPaint, PInk, PWd) then
      begin
        for J := 0 to 3 do RectDone[RLines[J]] := True;
        RectDone[RFace] := True;
        RectAt[I] := True;
      end;
    LinesFrom := -1;
    { All circles first, at the top level: faces, holes and pulls below refer
      to them by name, and a name given inside one solid block is out of reach
      of the next (a cylinder standing on a box's hole).  The reader gives a
      pulled circle to its pull. }
    for I := 0 to D.Live - 1 do
      if (D[I].Part = Part_) and (CircleName(I) <> '') then PutOther(Depth, I);
    for I := 0 to D.Live - 1 do
    begin
      if D[I].Part <> Part_ then Continue;
      if D[I].Kind = ekPart then Continue;
      if CircleName(I) <> '' then Continue;
      G := D[I].Grp;
      if (G <> 0) and (D[I].Kind in [ekFace, ekLine, ekBore]) then
      begin
        Seen := False;
        for J := 0 to High(Done) do
          if Done[J] = G then begin Seen := True; Break; end;
        if Seen then Continue;
        SetLength(Done, Length(Done) + 1);
        Done[High(Done)] := G;
        if MadeAs(Part_, G, MThrough, MOpen, MExact, BPaintOn, BPaint, PInk, PWd, MExtras) then
          PutMade(Depth, Part_, G, MThrough, MOpen, MExact, BPaintOn, BPaint, PInk, PWd, MExtras)
        else if IsBox(Part_, G, BLo, BHi, BPaintOn, BPaint, PInk, PWd, BOpen) then
          PutBox(Depth, Part_, G, BLo, BHi, BPaintOn, BPaint, PInk, PWd, BOpen)
        else if IsPull(Part_, G, PBottom, PBy, PRound, BPaintOn, BPaint, PInk, PWd) then
          PutPull(Depth, Part_, G, PBottom, PBy, PRound, BPaintOn, BPaint, PInk, PWd)
        else
          PutSolid(Depth, Part_, G);
        Continue;
      end;
      if RectDone[I] and not RectAt[I] then Continue;
      if ChainDone[I] then Continue;
      case D[I].Kind of
        ekFace:
          begin
            Implied[I] := FaceImplied(I, False, 0);
            if not Implied[I] then PutFace(Depth, I, None);
          end;
        ekLine:
          if RectAt[I] and IsRect(Part_, I, RLines, RFace, RLo, RSize, BPaintOn, BPaint, PInk, PWd) then
          begin
            Header := NLine;
            PutNote(Depth, D[RLines[0]].Note, -1);
            if BPaintOn or not PlainPen(PInk, PWd) then
            begin
              Put(Depth, 'rect' + NameWord(D[RLines[0]].Name) + TailNote(D[RLines[0]].Note), -1);
              Put(Depth + 1, 'at   = ' + Place2(RLo, U, False), -1);
              Put(Depth + 1, 'size = ' + Place2(RSize, U, True), -1);
              if BPaintOn then Put(Depth + 1, 'paint = ' + Color2(BPaint), -1);
              PutPen(Depth + 1, PInk, PWd);
              Put(Depth, 'end', -1);
            end
            else
              Put(Depth, 'rect' + NameWord(D[RLines[0]].Name) + ' = ' + Place2(RLo, U, False) + '; ' +
                Place2(RSize, U, True) + TailNote(D[RLines[0]].Note), -1);
            for J := 0 to 3 do
            begin
              RectDone[RLines[J]] := True;
              First[RLines[J]] := Header;
              Last[RLines[J]] := NLine - 1;
            end;
            RectDone[RFace] := True;
            First[RFace] := Header;
            Last[RFace] := NLine - 1;
          end
          else
          begin
            if LinesFrom < 0 then LinesFrom := NLine;
            if D[I].Name <> '' then FindChain(I) else SetLength(Chain, 1);
            if Length(Chain) > 1 then PutChain(Depth, Chain, ChainPoly)
            else PutLine(Depth, I, None);
          end;
      else
        PutOther(Depth, I);
      end;
    end;
    PutNoFaces(Depth, None, Part_, 0);
    for I := 0 to D.Live - 1 do
      if (D[I].Kind = ekFace) and (D[I].Part = Part_) and (D[I].Grp = 0) and Implied[I] then
      begin
        if LinesFrom >= 0 then First[I] := LinesFrom;
        Last[I] := NLine - 1;
      end;
    for I := 0 to D.Live - 1 do
      if (D[I].Kind = ekPart) and (D[I].Part = Part_) then
      begin
        PutNote(Depth, D[I].Note, I);
        Put(Depth, 'group ' + QuotedStr(D[I].Txt) + TailNote(D[I].Note), I);
        if D[I].Solid then Put(Depth + 1, 'locked = true', I);
        if D[I].Hidden then Put(Depth + 1, 'hidden = true', I);
        if D[I].Jig <> '' then Put(Depth + 1, 'jig = ' + D[I].Jig, I);
        if D[I].Data <> '' then PutData(Depth + 1, D[I].Data, I);
        PutLevel(Depth + 1, D[I].Grp);
        Put(Depth, 'end', I);
      end;
  end;

  { Pass one has been read back into E.  Find which of D's faces the reader
    restored by itself, and which loops it closed that D has no face for.
    Faces are matched by geometry (corners to the text's rounding, same facing),
    since the reader's order is its own. }
  procedure Decide(E: TWorkDoc; const EImplied: TBoolArray);
  var
    F, I, K, S, R, Grp, Prt, C: Integer;
    Match: array of Integer;
    Taken: array of Boolean;
    Found: Boolean;
    DFaces, DLines: TLoopIndex;
    Cands: TIntArrayW;
    GrpMap: array of record E, D: Integer; end;
    Seg: TP3Array;

    { E's groups are numbered as the reader numbers them; each maps to the D
      group its lines are in }
    function GrpOfE(G: Integer): Integer;
    var
      K: Integer;
    begin
      Result := 0;
      if G = 0 then Exit;
      for K := 0 to High(GrpMap) do
        if GrpMap[K].E = G then Exit(GrpMap[K].D);
      Result := -1;
    end;

    function MatchOf(F: Integer): Integer;
    var
      C, I, Want: Integer;
    begin
      Result := -1;
      Want := GrpOfE(E[F].Grp);
      Cands := DFaces.Near(E[F].Poly);
      for C := 0 to High(Cands) do
      begin
        I := Cands[C];
        if Taken[I] or (D[I].Grp <> Want) then Continue;
        if (Length(D[I].Holes) = Length(E[F].Holes)) and
           SameLoopTol(D[I].Poly, E[F].Poly, 1E-4) then
          Exit(I);
      end;
    end;

    { One to one: two solids lying on each other (a copy set down on the
      original) have the same lines, and each needs a group of its own. }
    procedure MapGroups;
    var
      F, I, K, C: Integer;
      Known, Used: Boolean;
    begin
      SetLength(GrpMap, 0);
      SetLength(Seg, 2);
      for F := 0 to E.Live - 1 do
      begin
        if (E[F].Kind <> ekLine) or (E[F].Grp = 0) then Continue;
        Known := False;
        for K := 0 to High(GrpMap) do
          if GrpMap[K].E = E[F].Grp then begin Known := True; Break; end;
        if Known then Continue;
        Seg[0] := E[F].A; Seg[1] := E[F].B;
        Cands := DLines.Near(Seg);
        for C := 0 to High(Cands) do
        begin
          I := Cands[C];
          if D[I].Grp = 0 then Continue;
          if ((SamePt(D[I].A, E[F].A, 1E-4) and SamePt(D[I].B, E[F].B, 1E-4)) or
              (SamePt(D[I].A, E[F].B, 1E-4) and SamePt(D[I].B, E[F].A, 1E-4))) then
          begin
            Used := False;
            for K := 0 to High(GrpMap) do
              if GrpMap[K].D = D[I].Grp then begin Used := True; Break; end;
            if Used then Continue;
            SetLength(GrpMap, Length(GrpMap) + 1);
            GrpMap[High(GrpMap)].E := E[F].Grp;
            GrpMap[High(GrpMap)].D := D[I].Grp;
            Break;
          end;
        end;
      end;
      { a solid with no lines of its own (every edge loose, as a jig may build
        it) is matched by a face instead }
      for F := 0 to E.Live - 1 do
      begin
        if (E[F].Kind <> ekFace) or (E[F].Grp = 0) then Continue;
        Known := False;
        for K := 0 to High(GrpMap) do
          if GrpMap[K].E = E[F].Grp then begin Known := True; Break; end;
        if Known then Continue;
        Cands := DFaces.Near(E[F].Poly);
        for C := 0 to High(Cands) do
        begin
          I := Cands[C];
          if (D[I].Grp = 0) or not SameLoopTol(D[I].Poly, E[F].Poly, 1E-4) then Continue;
          Used := False;
          for K := 0 to High(GrpMap) do
            if GrpMap[K].D = D[I].Grp then begin Used := True; Break; end;
          if Used then Continue;
          SetLength(GrpMap, Length(GrpMap) + 1);
          GrpMap[High(GrpMap)].E := E[F].Grp;
          GrpMap[High(GrpMap)].D := D[I].Grp;
          Break;
        end;
      end;
    end;

  begin
    SetLength(ImpliedGeom, D.Live);
    for I := 0 to D.Live - 1 do ImpliedGeom[I] := False;
    SetLength(NoFaceLoops, 0);
    SetLength(NoFaceScope, 0);
    SetLength(NoFacePart, 0);
    DFaces := TLoopIndex.Create;
    DLines := TLoopIndex.Create;
    try
      SetLength(Seg, 2);
      SetLength(Taken, D.Live);
      for I := 0 to D.Live - 1 do
      begin
        Taken[I] := False;
        if D[I].Kind = ekFace then DFaces.Add(D[I].Poly, I)
        else if D[I].Kind = ekLine then
        begin
          Seg[0] := D[I].A; Seg[1] := D[I].B;
          DLines.Add(Seg, I);
        end;
      end;
      { each face of E to one face of D: two coincident faces both stay, the
        second written out }
      MapGroups;
      SetLength(Match, E.Live);
      for F := 0 to E.Live - 1 do
      begin
        Match[F] := -1;
        if E[F].Kind <> ekFace then Continue;
        Match[F] := MatchOf(F);
        if Match[F] >= 0 then Taken[Match[F]] := True;
      end;
      { faces the reader closes by itself: D's face goes unwritten when it faces
        the way the reader would turn it }
      for F := 0 to E.Live - 1 do
        if (F <= High(EImplied)) and EImplied[F] and (Match[F] >= 0) and
           (Dot3(E.FaceNormal(F), D.FaceNormal(Match[F])) > 0) then
          ImpliedGeom[Match[F]] := True;
      { Faces of E with no match in D are loops the reader closed on its own and
        must be told not to.  They go in the scope of D their edges are in. }
      for F := 0 to E.Live - 1 do
        if (E[F].Kind = ekFace) and (Match[F] < 0) then
        begin
          { The D scope it belongs in: the one whose lines closed it.  A loose one
            is placed by a D line along it, or the D arc it is the ring of. }
          Grp := 0;
          Prt := -1;
          if (E[F].Grp <> 0) and (GrpOfE(E[F].Grp) > 0) then
          begin
            Grp := GrpOfE(E[F].Grp);
            Prt := E[F].Part;
            for I := 0 to D.Live - 1 do
              if (D[I].Kind = ekLine) and (D[I].Grp = Grp) then begin Prt := D[I].Part; Break; end;
          end
          else
          for S := 0 to High(E[F].Poly) do
          begin
            Seg[0] := E[F].Poly[S]; Seg[1] := E[F].Poly[(S + 1) mod Length(E[F].Poly)];
            Cands := DLines.Near(Seg);
            for C := 0 to High(Cands) do
            begin
              I := Cands[C];
              if (SamePt(D[I].A, Seg[0], 1E-4) and SamePt(D[I].B, Seg[1], 1E-4)) or
                 (SamePt(D[I].A, Seg[1], 1E-4) and SamePt(D[I].B, Seg[0], 1E-4)) then
              begin
                Grp := D[I].Grp;
                Prt := D[I].Part;
                Break;
              end;
            end;
            if Prt >= 0 then Break;
          end;
          if Prt < 0 then
            for I := 0 to D.Live - 1 do
              if (D[I].Kind = ekArc) and
                 (Abs(Dist(D[I].C, E[F].Poly[0]) - D[I].R) < 1E-4) and
                 (Abs(Dist(D[I].C, E[F].Poly[Length(E[F].Poly) div 2]) - D[I].R) < 1E-4) then
              begin
                Grp := D[I].Grp;
                Prt := D[I].Part;
                Break;
              end;
          if Prt < 0 then Prt := 0;
          { once per scope: a ring closed by two solids' edges is a noface of each,
            and two in one scope are one }
          Found := False;
          for R := 0 to High(NoFaceLoops) do
            if (NoFaceScope[R] = Grp) and (NoFacePart[R] = Prt) and
               SameLoopTol(NoFaceLoops[R], E[F].Poly, 1E-4) then begin Found := True; Break; end;
          if Found then Continue;
          SetLength(NoFaceLoops, Length(NoFaceLoops) + 1);
          NoFaceLoops[High(NoFaceLoops)] := Copy(E[F].Poly);
          SetLength(NoFaceScope, Length(NoFaceScope) + 1);
          NoFaceScope[High(NoFaceScope)] := Grp;
          SetLength(NoFacePart, Length(NoFacePart) + 1);
          NoFacePart[High(NoFacePart)] := Prt;
        end;
      { An unwritten face whose loop is also a noface would be lost, since a
        noface holds everywhere, so it is written out instead. }
      for I := 0 to D.Live - 1 do
        if ImpliedGeom[I] then
          for R := 0 to High(NoFaceLoops) do
            if SameLoopTol(NoFaceLoops[R], D[I].Poly, 1E-4) then
            begin
              ImpliedGeom[I] := False;
              Break;
            end;
    finally
      DLines.Free;
      DFaces.Free;
    end;
  end;

var
  I, EL: Integer;
  T0, T1, T2: QWord;
  Pass1: TStringList;
  EImplied: TBoolArray;
  E: TWorkDoc;
  F1, L1, LT1: TIntArrayW;
  Err: string;
begin
  SetLength(ImpliedGeom, 0);
  SetLength(NoFaceLoops, 0);
  SetLength(NoFaceScope, 0);
  { Only up to a size: the read-back costs seconds on a forty-thousand-thing
    drawing and the source window writes on every edit.  Past it every face is
    written, which is never wrong, only longer. }
  { Quick (drafts, written every few seconds) skips it too }
  if Assigned(ReadBack) and not InPass1 and not Quick and (D.Live <= IMPLY_LIMIT) then
  begin
    InPass1 := True;
    Pass1 := TStringList.Create;
    E := TWorkDoc.Create;
    try
      T0 := GetTickCount64;
      WriteFormat2(D, SheetName, U, Pass1, F1, L1, LT1);
      T1 := GetTickCount64;
      if ReadBack(Pass1, E, U, EL, Err, EImplied) then
      begin
        T2 := GetTickCount64;
        Decide(E, EImplied);
        if GetEnvironmentVariable('HECK_TIMING') <> '' then
          WriteLn(StdErr, Format('pass one: write %d ms, read %d ms, decide %d ms',
            [T1 - T0, T2 - T1, GetTickCount64 - T2]));
      end;
    finally
      E.Free;
      Pass1.Free;
      InPass1 := False;
    end;
  end;
  NLine := 0;
  NextHint := '';
  Given := False;
  SetLength(LineThing, 256);
  SetLength(First, D.Live);
  SetLength(Last, D.Live);
  for I := 0 to D.Live - 1 do begin First[I] := 0; Last[I] := -1; end;
  FindDefaults;
  SetLength(Circles, 0);
  for I := 0 to D.Live - 1 do
    if (D[I].Kind = ekArc) and FullCircle(D[I].Sweep) then
    begin
      SetLength(Circles, Length(Circles) + 1);
      Circles[High(Circles)] := I;
    end;
  NameCircles;

  Put(0, HECK_MAGIC, -1);
  if U = usMetric then Put(0, 'units = mm', -1)
  else Put(0, 'units = ft in', -1);
  Put(0, '', -1);
  PutNote(0, D.HeadNote, -1);
  Put(0, 'sheet ' + QuotedStr(SheetName), -1);
  Put(1, 'ink = ' + Color2(DefInk), -1);
  Put(1, 'width = ' + FloatToStrF(DefWidth, ffGeneral, 4, 0, DotFS), -1);
  { the sheet's own settings, as the file keeps them; see hsHeckFile }
  if SheetLines <> nil then
    for I := 0 to SheetLines.Count - 1 do Put(1, SheetLines[I], -1);
  { Every face written in full (no reader, or too big to ask), and the
    reader is to make none of its own. }
  if not InPass1 and (Length(ImpliedGeom) = 0) then Put(1, 'faces = said', -1);
  Put(0, '', -1);
  PutLevel(1, 0);
  PutNote(1, D.TailNote, -1);
  Put(0, 'end', -1);
  SetLength(LineThing, NLine);
end;

end.

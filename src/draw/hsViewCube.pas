unit hsViewCube;

{ The view cube: a small cube in the corner that turns with the model and
  shows which way you are facing.  Click one of its 26 faces, edges or
  corners to look from there; drag it to orbit.  It is drawn in the
  program's own theme and must not be called "ViewCube" (Autodesk's name).
  Front faces +X, right +Y, top +Z, matching the view presets so /front and
  the cube's FRONT agree.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, hsSurface, hsDrawing, hsSkin;

type
  { One of the 26 click targets.  Dir is the direction to look FROM, each
    component -1, 0 or 1: one non-zero is a face, two an edge, three a corner. }
  TCubeTarget = record
    Dir: TP3;
    Name: string;
  end;

{ How wide the cube wants to be, in pixels, at a given interface scale. }
function CubeSize(UIScale: Single): Integer;

{ The target under a screen point, if any.  CX, CY and Half (pixels) are the
  same numbers PaintCube is given. }
function CubeAt(const V: TProjector; CX, CY, Half, SX, SY: Double;
  out T: TCubeTarget): Boolean;

{ Azimuth and elevation for a target.  Az is in and out: straight up or down
  gives no azimuth, so the current one is kept. }
procedure CubeAzEl(const Dir: TP3; var Az: Double; out El: Double);

{ The target nearest the camera.  Look is the direction the camera stands
  in, same sense as Dir.  Near_ is the dot product of the two unit vectors:
  1 is dead on, 0 a right angle away, so a caller can snap only when close. }
function CubeNearest(const Look: TP3; out Near_: Double): TCubeTarget;

{ One keyboard step between targets.  Left/Right go round the sides (face,
  edge, next face); Up/Down tip over the top or under the bottom.  Az says
  which way a camera looking straight down is turned.  Looking straight up or
  down, Left/Right return Dir unchanged and the caller turns the camera. }
type
  TCubeStep = (csLeft, csRight, csUp, csDown);

function CubeStep(const Dir: TP3; Az: Double; Step: TCubeStep): TP3;

{ Draw the cube centered in its own square surface, at least 2 * Half plus a
  few pixels across.  Hot is the target under the pointer.  Labels need a
  font, so the caller writes them using CubeLabels. }
procedure PaintCube(S: TArtSurface; const V: TProjector; Half: Double;
  const Th: TTheme; HaveHot: Boolean; const HotDir: TP3);

{ The visible faces, their names, and where the middle of each one is in the
  surface PaintCube just drew.  Up to three come back. }
type
  TCubeLabel = record
    Name: string;
    X, Y: Double;
    Facing: Double;     { how square-on it is, 0 to 1 - dim the steep ones }
  end;
  TCubeLabels = array of TCubeLabel;

function CubeLabels(const V: TProjector; Half: Double): TCubeLabels;

{ Where a target's middle is drawn on screen.  Edges and corners belong to
  several faces; the one most square-on to the camera is used.  False when
  the target is round the back. }
function CubeTargetAt(const V: TProjector; const Dir: TP3;
  CX, CY, Half: Double; out P: TPointF): Boolean;

implementation

const
  { Where a face stops and its edges begin, as a fraction of the half-width.
    Kept generous so the edge strips are easy to hit. }
  BAND = 0.65;

type
  TFaceDef = record
    N, A, B: TP3;     { normal, and the two directions across the face }
  end;

const
  FACES: array[0..5] of TFaceDef = (
    (N: (X: 1; Y: 0; Z: 0);  A: (X: 0; Y: 1; Z: 0);  B: (X: 0; Y: 0; Z: 1)),
    (N: (X: -1; Y: 0; Z: 0); A: (X: 0; Y: -1; Z: 0); B: (X: 0; Y: 0; Z: 1)),
    (N: (X: 0; Y: 1; Z: 0);  A: (X: -1; Y: 0; Z: 0); B: (X: 0; Y: 0; Z: 1)),
    (N: (X: 0; Y: -1; Z: 0); A: (X: 1; Y: 0; Z: 0);  B: (X: 0; Y: 0; Z: 1)),
    (N: (X: 0; Y: 0; Z: 1);  A: (X: 1; Y: 0; Z: 0);  B: (X: 0; Y: 1; Z: 0)),
    (N: (X: 0; Y: 0; Z: -1); A: (X: 1; Y: 0; Z: 0);  B: (X: 0; Y: -1; Z: 0)));

function CubeSize(UIScale: Single): Integer;
begin
  Result := Round(104 * UIScale);
end;

{ The name of a direction: front/back, then left/right, then top/bottom,
  the order people say it in. }
function DirName(const D: TP3): string;
begin
  Result := '';
  if D.X > 0.5 then Result := 'FRONT'
  else if D.X < -0.5 then Result := 'BACK';
  if D.Y > 0.5 then Result := Trim(Result + ' RIGHT')
  else if D.Y < -0.5 then Result := Trim(Result + ' LEFT');
  if D.Z > 0.5 then Result := Trim(Result + ' TOP')
  else if D.Z < -0.5 then Result := Trim(Result + ' BOTTOM');
end;

{ See the interface. }
const
  { the sides, in the order a camera meets them turning with Az }
  RING: array[0..7] of TPoint = (
    (X: 1; Y: 0), (X: 1; Y: 1), (X: 0; Y: 1), (X: -1; Y: 1),
    (X: -1; Y: 0), (X: -1; Y: -1), (X: 0; Y: -1), (X: 1; Y: -1));

function CubeStep(const Dir: TP3; Az: Double; Step: TCubeStep): TP3;
var
  X, Y, Z, K, Best: Integer;
  D, BestD: Double;
begin
  X := Round(Dir.X); Y := Round(Dir.Y); Z := Round(Dir.Z);
  Result := P3(X, Y, Z);
  if (X = 0) and (Y = 0) then
  begin
    { over the top or under the bottom: the side a step down lands on is
      the one the camera is already turned towards }
    Best := 0;
    BestD := -2;
    for K := 0 to 7 do
    begin
      D := (RING[K].X * Cos(Az) + RING[K].Y * Sin(Az)) /
           Sqrt(Sqr(RING[K].X) + Sqr(RING[K].Y));
      if D > BestD then
      begin
        BestD := D;
        Best := K;
      end;
    end;
    case Step of
      csDown: if Z > 0 then Result := P3(RING[Best].X, RING[Best].Y, 1);
      csUp:   if Z < 0 then Result := P3(RING[Best].X, RING[Best].Y, -1);
    end;
    Exit;
  end;
  K := 0;
  while (K < 7) and ((RING[K].X <> X) or (RING[K].Y <> Y)) do Inc(K);
  case Step of
    csRight: Result := P3(RING[(K + 1) mod 8].X, RING[(K + 1) mod 8].Y, Z);
    csLeft:  Result := P3(RING[(K + 7) mod 8].X, RING[(K + 7) mod 8].Y, Z);
    csUp:    if Z < 1 then Result := P3(X, Y, Z + 1) else Result := P3(0, 0, 1);
    csDown:  if Z > -1 then Result := P3(X, Y, Z - 1) else Result := P3(0, 0, -1);
  end;
end;

function CubeNearest(const Look: TP3; out Near_: Double): TCubeTarget;
var
  IX, IY, IZ: Integer;
  D, L: TP3;
  Len, Dot, Best: Double;
begin
  Result.Dir := P3(0, 0, 1);
  Result.Name := DirName(Result.Dir);
  Near_ := -1;
  Best := -2;
  Len := Sqrt(Look.X * Look.X + Look.Y * Look.Y + Look.Z * Look.Z);
  if Len < 1E-12 then Exit;
  L := P3(Look.X / Len, Look.Y / Len, Look.Z / Len);
  for IX := -1 to 1 do
    for IY := -1 to 1 do
      for IZ := -1 to 1 do
      begin
        { the middle of the cube is not a direction }
        if (IX = 0) and (IY = 0) and (IZ = 0) then Continue;
        D := P3(IX, IY, IZ);
        Len := Sqrt(D.X * D.X + D.Y * D.Y + D.Z * D.Z);
        D := P3(D.X / Len, D.Y / Len, D.Z / Len);
        Dot := D.X * L.X + D.Y * L.Y + D.Z * L.Z;
        if Dot > Best then
        begin
          Best := Dot;
          Result.Dir := P3(IX, IY, IZ);
          Result.Name := DirName(Result.Dir);
        end;
      end;
  Near_ := Best;
end;

{ A point of the cube, in the surface's pixels.  The cube is one unit from
  the middle to each face, so a coordinate runs -1 to 1. }
function OnScreen(const V: TProjector; const P: TP3;
  CX, CY, Half: Double): TPointF;
var
  R, U: TP3;
begin
  R := ViewRight(V);
  U := ViewUp(V);
  Result.X := CX + Dot3(P, R) * Half;
  Result.Y := CY - Dot3(P, U) * Half;
end;

procedure CubeAzEl(const Dir: TP3; var Az: Double; out El: Double);
var
  Flat: Double;
begin
  Flat := Sqrt(Dir.X * Dir.X + Dir.Y * Dir.Y);
  { straight up or straight down says nothing about which way round to be,
    so keep the turn that is already in force }
  if Flat > 1E-9 then Az := ArcTan2(Dir.Y, Dir.X);
  El := ArcTan2(Dir.Z, Flat);
  { the same limit the orbit has; dead overhead is gimbal lock }
  if El < -1.45 then El := -1.45;
  if El > 1.45 then El := 1.45;
end;

function CubeAt(const V: TProjector; CX, CY, Half, SX, SY: Double;
  out T: TCubeTarget): Boolean;
var
  R, U, D, O, Dir, P: TP3;
  A, B, TMin, TMax, T1, T2, Tmp: Double;
  K: Integer;

  { one axis of the slab test }
  function Slab(Oi, Di: Double): Boolean;
  begin
    Result := True;
    if Abs(Di) < 1E-12 then
    begin
      { the ray runs along this slab: it either starts inside it or misses
        the cube altogether }
      if Abs(Oi) > 1 then Result := False;
      Exit;
    end;
    T1 := (-1 - Oi) / Di;
    T2 := (1 - Oi) / Di;
    if T1 > T2 then
    begin
      Tmp := T1; T1 := T2; T2 := Tmp;
    end;
    if T1 > TMin then TMin := T1;
    if T2 < TMax then TMax := T2;
  end;

begin
  Result := False;
  T.Dir := P3(0, 0, 0);
  T.Name := '';
  if Half <= 0 then Exit;

  R := ViewRight(V);
  U := ViewUp(V);
  { ViewDir points from the model towards the eye, so the ray goes the other
    way - away from the camera, into the cube }
  D := ViewDir(V);
  Dir := P3(-D.X, -D.Y, -D.Z);

  { the point of the cube's own space that this pixel looks along }
  A := (SX - CX) / Half;
  B := (CY - SY) / Half;
  O := P3(A * R.X + B * U.X, A * R.Y + B * U.Y, A * R.Z + B * U.Z);

  TMin := -1E30;
  TMax := 1E30;
  if not Slab(O.X, Dir.X) then Exit;
  if not Slab(O.Y, Dir.Y) then Exit;
  if not Slab(O.Z, Dir.Z) then Exit;
  if TMin > TMax then Exit;

  { where it goes in - the near face, which is the one being pointed at }
  P := P3(O.X + TMin * Dir.X, O.Y + TMin * Dir.Y, O.Z + TMin * Dir.Z);

  { and which of the twenty-six that is: every coordinate out past the band
    counts towards the direction, the rest do not }
  T.Dir := P3(0, 0, 0);
  if P.X > BAND then T.Dir.X := 1 else if P.X < -BAND then T.Dir.X := -1;
  if P.Y > BAND then T.Dir.Y := 1 else if P.Y < -BAND then T.Dir.Y := -1;
  if P.Z > BAND then T.Dir.Z := 1 else if P.Z < -BAND then T.Dir.Z := -1;

  { A point on the cube is on at least one face; this only catches rounding
    putting it a hair inside. }
  if (T.Dir.X = 0) and (T.Dir.Y = 0) and (T.Dir.Z = 0) then
  begin
    K := 0;
    if Abs(P.Y) > Abs(P.X) then K := 1;
    if (Abs(P.Z) > Abs(P.X)) and (Abs(P.Z) > Abs(P.Y)) then K := 2;
    case K of
      0: T.Dir.X := Sign(P.X);
      1: T.Dir.Y := Sign(P.Y);
    else T.Dir.Z := Sign(P.Z);
    end;
  end;

  T.Name := DirName(T.Dir);
  Result := True;
end;

function CubeLabels(const V: TProjector; Half: Double): TCubeLabels;
var
  F: Integer;
  D: TP3;
  Face: TFaceDef;
  Lit: Double;
  P: TPointF;
begin
  SetLength(Result, 0);
  D := ViewDir(V);
  for F := 0 to High(FACES) do
  begin
    Face := FACES[F];
    Lit := Dot3(Face.N, D);
    { facing away or too edge-on to read.  Kept low: the top face at a
      normal working angle is only about 0.4 square-on and still readable. }
    if Lit < 0.26 then Continue;
    P := OnScreen(V, Face.N, 0, 0, Half);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Name := DirName(Face.N);
    Result[High(Result)].X := P.X;
    Result[High(Result)].Y := P.Y;
    Result[High(Result)].Facing := Lit;
  end;
end;

function CubeTargetAt(const V: TProjector; const Dir: TP3;
  CX, CY, Half: Double; out P: TPointF): Boolean;
var
  F, Best: Integer;
  D, Pt: TP3;
  Lit, BestLit, Mid, U, W: Double;
begin
  Result := False;
  P := PointF(CX, CY);
  D := ViewDir(V);
  Best := -1;
  BestLit := 0.001;
  for F := 0 to High(FACES) do
  begin
    { adjacent, meaning this target lies on this face }
    if Dot3(Dir, FACES[F].N) < 0.5 then Continue;
    Lit := Dot3(FACES[F].N, D);
    if Lit > BestLit then
    begin
      BestLit := Lit;
      Best := F;
    end;
  end;
  if Best < 0 then Exit;

  { the middle of the cell: the middle of the outer band where the target
    runs off that way, the middle of the face where it does not }
  Mid := (BAND + 1) / 2;
  U := Dot3(Dir, FACES[Best].A) * Mid;
  W := Dot3(Dir, FACES[Best].B) * Mid;
  Pt := P3(FACES[Best].N.X + U * FACES[Best].A.X + W * FACES[Best].B.X,
           FACES[Best].N.Y + U * FACES[Best].A.Y + W * FACES[Best].B.Y,
           FACES[Best].N.Z + U * FACES[Best].A.Z + W * FACES[Best].B.Z);
  P := OnScreen(V, Pt, CX, CY, Half);
  Result := True;
end;

procedure PaintCube(S: TArtSurface; const V: TProjector; Half: Double;
  const Th: TTheme; HaveHot: Boolean; const HotDir: TP3);
var
  F, I, J: Integer;
  Face: TFaceDef;
  D, N, Cell: TP3;
  Lit, Up: Double;
  CX, CY: Double;
  Q: array[0..3] of TPointF;
  G0, G1: TPointF;
  Fill, Line: TPix;
  Hot: Boolean;

  { the corners of cell I,J of a face, in cube space }
  function Corner(const AFace: TFaceDef; UI, WI: Integer): TP3;
  var
    Ub, Wb: Double;
  begin
    case UI of
      0: Ub := -1;
      1: Ub := -BAND;
      2: Ub := BAND;
    else Ub := 1;
    end;
    case WI of
      0: Wb := -1;
      1: Wb := -BAND;
      2: Wb := BAND;
    else Wb := 1;
    end;
    Result := P3(AFace.N.X + Ub * AFace.A.X + Wb * AFace.B.X,
                 AFace.N.Y + Ub * AFace.A.Y + Wb * AFace.B.Y,
                 AFace.N.Z + Ub * AFace.A.Z + Wb * AFace.B.Z);
  end;

begin
  if (S = nil) or (Half <= 0) then Exit;
  CX := S.Width / 2;
  CY := S.Height / 2;
  D := ViewDir(V);

  { No backing pad or drop shadow: extra outlines around the cube make it
    read as some other shape. }

  for F := 0 to High(FACES) do
  begin
    Face := FACES[F];
    N := Face.N;
    Lit := Dot3(N, D);
    if Lit <= 0.001 then Continue;      { facing away }

    for I := 0 to 2 do
      for J := 0 to 2 do
      begin
        { which of the twenty-six this cell is: the face itself in the
          middle, an edge along a side, a corner in a corner }
        Cell := N;
        if I = 0 then Cell := P3(Cell.X - Face.A.X, Cell.Y - Face.A.Y, Cell.Z - Face.A.Z)
        else if I = 2 then Cell := P3(Cell.X + Face.A.X, Cell.Y + Face.A.Y, Cell.Z + Face.A.Z);
        if J = 0 then Cell := P3(Cell.X - Face.B.X, Cell.Y - Face.B.Y, Cell.Z - Face.B.Z)
        else if J = 2 then Cell := P3(Cell.X + Face.B.X, Cell.Y + Face.B.Y, Cell.Z + Face.B.Z);

        Hot := HaveHot and (Abs(Cell.X - HotDir.X) < 0.01) and
               (Abs(Cell.Y - HotDir.Y) < 0.01) and (Abs(Cell.Z - HotDir.Z) < 0.01);

        Q[0] := OnScreen(V, Corner(Face, I, J), CX, CY, Half);
        Q[1] := OnScreen(V, Corner(Face, I + 1, J), CX, CY, Half);
        Q[2] := OnScreen(V, Corner(Face, I + 1, J + 1), CX, CY, Half);
        Q[3] := OnScreen(V, Corner(Face, I, J + 1), CX, CY, Half);

        { Shaded by how square-on the face is, and brightened toward the top
          so it reads as lit from above.  Facing alone makes the top the
          darkest face, which looks like a hole. }
        if Hot then
          Fill := ShadePix(Th.Accent, 0.85 + 0.35 * Lit)
        else
          Fill := MixPix(Th.Panel, Pix(255, 255, 255),
                         0.10 + 0.20 * Lit + 0.14 * Max(0, N.Z));

        S.Triangle(Q[0], Q[1], Q[2], Fill, 1.0);
        S.Triangle(Q[0], Q[2], Q[3], Fill, 1.0);
      end;

    { The face outline, with a rim light on the upper edges so it looks
      beveled, like the panels and buttons. }
    Line := MixPix(Th.PanelHi, Pix(255, 255, 255), 0.35);
    Q[0] := OnScreen(V, Corner(Face, 0, 0), CX, CY, Half);
    Q[1] := OnScreen(V, Corner(Face, 3, 0), CX, CY, Half);
    Q[2] := OnScreen(V, Corner(Face, 3, 3), CX, CY, Half);
    Q[3] := OnScreen(V, Corner(Face, 0, 3), CX, CY, Half);
    S.Line(Q[0].X, Q[0].Y, Q[1].X, Q[1].Y, 1.2, Line, 0.85);
    S.Line(Q[1].X, Q[1].Y, Q[2].X, Q[2].Y, 1.2, Line, 0.85);
    S.Line(Q[2].X, Q[2].Y, Q[3].X, Q[3].Y, 1.2, Line, 0.85);
    S.Line(Q[3].X, Q[3].Y, Q[0].X, Q[0].Y, 1.2, Line, 0.85);

    for I := 0 to 3 do
    begin
      J := (I + 1) mod 4;
      { the higher an edge sits on the screen, the more light it catches }
      Up := 1 - (Q[I].Y + Q[J].Y) / 2 / Max(1, S.Height);
      if Up < 0.55 then Continue;
      S.Line(Q[I].X, Q[I].Y, Q[J].X, Q[J].Y, 1.4,
        MixPix(Th.PanelHi, Pix(255, 255, 255), 0.75), (Up - 0.55) * 1.6);
    end;

    { --- square on to a face: show the ring of targets round it ---------

      Square on, the real edges and corners have no width on screen, so the
      eight border cells (which CubeAt still hits) are drawn faintly to show
      you can get back to them.  Only when nearly square on. }
    if Lit > 0.97 then
    begin
      Line := MixPix(Th.PanelHi, Pix(255, 255, 255), 0.55);
      for I := 1 to 2 do
      begin
        G0 := OnScreen(V, Corner(Face, I, 0), CX, CY, Half);
        G1 := OnScreen(V, Corner(Face, I, 3), CX, CY, Half);
        S.Line(G0.X, G0.Y, G1.X, G1.Y, 1.0, Line, 0.55);
        G0 := OnScreen(V, Corner(Face, 0, I), CX, CY, Half);
        G1 := OnScreen(V, Corner(Face, 3, I), CX, CY, Half);
        S.Line(G0.X, G0.Y, G1.X, G1.Y, 1.0, Line, 0.55);
      end;
    end;
  end;
  S.Touch;
end;

end.

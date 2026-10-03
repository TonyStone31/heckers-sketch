{ Flat regions worked out from a bag of segments, with no knowledge of the
  document or the screen.  Steps: cut segments where they cross, weld close
  ends, group edges by plane, walk the smallest half-edge cycles in each
  plane, and make a loop inside another a hole in it.  One tolerance,
  REGION_TOL, decides every "close enough" question. }
unit hsFaceFinder;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Contnrs, hsDrawing;

const
  { Feet: about a ten-thousandth of an inch.  Far below anything drawable,
    far above rounding noise. }
  REGION_TOL = 1E-6;

type
  TSeg = record
    A, B: TP3;
  end;
  TSegArray = array of TSeg;

  TLoopArray = array of TP3Array;

  { A flat area: the plane it lies in, the loop round the outside, and the
    loops of anything cut out of it. }
  TRegion = record
    Normal: TP3;
    Outer: TP3Array;
    Holes: TLoopArray;
  end;
  TRegionArray = array of TRegion;

  { A plane in comparable form: CanonicalNormal's unit normal and the
    offset along it. }
  TPlaneKey = record
    N: TP3;
    D: Double;
  end;
  TPlaneArray = array of TPlaneKey;

  { Lets a rebuild skip planes whose edges did not move.  Pass the same one
    back each time. }
  TRegionCache = record
    Keys: TPlaneArray;
    Sig: array of Int64;
    Found: array of TRegionArray;
  end;

{ A plane's unit normal, picked the same way every time so two descriptions
  of one plane compare equal. }
function CanonicalNormal(const N: TP3): TP3;

{ Keep a loop found more than once only once.  Public so tests can call it. }
procedure DropTwinRegions(var R: TRegionArray; Tol: Double = REGION_TOL);

{ Segments in, regions out. }
function BuildRegions(const Segs: TSegArray; Tol: Double = REGION_TOL): TRegionArray;

{ The same, but a plane whose segments have not changed keeps last time's
  regions, so editing one wall does not redo the whole model.  An empty
  cache means a full rebuild. }
function BuildRegionsCached(const Segs: TSegArray; var Cache: TRegionCache;
  Tol: Double = REGION_TOL): TRegionArray;

{ Step 1 on its own, for testing: cut every segment wherever another
  crosses or touches it. }
function SplitAtCrossings(const Segs: TSegArray; Tol: Double = REGION_TOL): TSegArray;

{ Signed area of a closed loop, in its own plane. }
function LoopArea(const Loop: TP3Array; const Normal: TP3): Double;

{ Is the point inside the flat loop?  The point is assumed in its plane; on
  the boundary counts as inside. }
function PointInLoop(const P: TP3; const Loop: TP3Array; const Normal: TP3;
  Tol: Double = REGION_TOL): Boolean;

{ A point truly inside the loop.  The corner average can fall outside (a
  wall with a half-round bite in it), so this falls back to an edge's middle
  nudged inward. }
function InnerPoint(const Loop: TP3Array; const Normal: TP3): TP3;

{ The same for a region with openings: inside the outline and in no hole.
  A ring's center is in its hole, so that point would not do. }
function InnerPointOf(const Outer: TP3Array; const Holes: array of TP3Array;
  const Normal: TP3): TP3;

implementation

type
  TIntArray = array of Integer;

  TDart = record
    V0, V1: Integer;      { from, to }
    Twin: Integer;
    Ang: Double;          { direction leaving V0, in the plane's coordinates }
    Used: Boolean;
  end;

{ ---------------------------------------------------------------- helpers - }

function Len3(const A: TP3): Double; inline;
begin
  Result := Sqrt(A.X * A.X + A.Y * A.Y + A.Z * A.Z);
end;

function Sub3(const A, B: TP3): TP3; inline;
begin
  Result := P3(A.X - B.X, A.Y - B.Y, A.Z - B.Z);
end;

function Add3(const A, B: TP3): TP3; inline;
begin
  Result := P3(A.X + B.X, A.Y + B.Y, A.Z + B.Z);
end;

function Mul3(const A: TP3; S: Double): TP3; inline;
begin
  Result := P3(A.X * S, A.Y * S, A.Z * S);
end;

function Lerp(const A, B: TP3; T: Double): TP3; inline;
begin
  Result := P3(A.X + (B.X - A.X) * T, A.Y + (B.Y - A.Y) * T,
               A.Z + (B.Z - A.Z) * T);
end;

{ Where P falls along AB, and how far off it is.  T is clamped so Off is the
  distance to the segment, not its infinite line. }
procedure ClosestOnSeg(const P, A, B: TP3; out T, Off: Double);
var
  D: TP3;
  L2: Double;
begin
  D := Sub3(B, A);
  L2 := D.X * D.X + D.Y * D.Y + D.Z * D.Z;
  if L2 < 1E-18 then
  begin
    T := 0;
    Off := Dist(P, A);
    Exit;
  end;
  T := ((P.X - A.X) * D.X + (P.Y - A.Y) * D.Y + (P.Z - A.Z) * D.Z) / L2;
  T := EnsureRange(T, 0, 1);
  Off := Dist(P, Add3(A, Mul3(D, T)));
end;

{ Pick the sign from the normal's dot with a golden-ratio direction rather
  than from the first nonzero part.  Drawn faces sit exactly where a part is
  zero, and cross-product noise (about 1E-8) would flip the sign and give one
  plane two keys.  No face anybody draws is square to this direction. }
function CanonicalNormal(const N: TP3): TP3;
const
  PHI = 0.6180339887498949;
var
  L: Double;
begin
  L := Len3(N);
  if L < 1E-12 then Exit(P3(0, 0, 1));
  Result := Mul3(N, 1 / L);
  if Result.X + Result.Y * PHI + Result.Z * PHI * PHI < 0 then
    Result := Mul3(Result, -1);
end;

{ Keep each loop once.  A nearly flat face can produce two planes just over
  the "same plane" tolerance apart, and both find the same loop; without
  this, every rebuild stacks another copy.  Loosening the plane tolerance
  would merge real planes instead.  Loops match when every corner is within
  10*Tol; the middles go in a grid so this is not all-pairs. }
procedure DropTwinRegions(var R: TRegionArray; Tol: Double);
const
  CELL = 1E-3;
var
  Mid: TP3Array;
  Keep: array of Boolean;
  Next: TIntArray;
  Head: TFPHashList;
  I, N, Kept: Integer;

  function CellKey(CX, CY, CZ: Int64; Corners: Int64): shortstring;
  begin
    SetLength(Result, 32);
    Move(CX, Result[1], 8);
    Move(CY, Result[9], 8);
    Move(CZ, Result[17], 8);
    Move(Corners, Result[25], 8);
  end;

  { same corner count and every corner of A near one of B }
  function SameLoop(A, B: Integer): Boolean;
  var
    P, Q: Integer;
    Found: Boolean;
  begin
    Result := False;
    if Length(R[A].Outer) <> Length(R[B].Outer) then Exit;
    for P := 0 to High(R[A].Outer) do
    begin
      Found := False;
      for Q := 0 to High(R[B].Outer) do
        if Len3(Sub3(R[A].Outer[P], R[B].Outer[Q])) <= 10 * Tol then
        begin
          Found := True;
          Break;
        end;
      if not Found then Exit;
    end;
    Result := True;
  end;

  function TwinOf(I: Integer): Integer;
  var
    CX, CY, CZ, DX, DY, DZ: Int64;
    Q: Integer;
  begin
    Result := -1;
    CX := Floor(Mid[I].X / CELL);
    CY := Floor(Mid[I].Y / CELL);
    CZ := Floor(Mid[I].Z / CELL);
    for DX := -1 to 1 do
      for DY := -1 to 1 do
        for DZ := -1 to 1 do
        begin
          Q := PtrInt(Head.Find(CellKey(CX + DX, CY + DY, CZ + DZ,
            Length(R[I].Outer)))) - 1;
          while Q >= 0 do
          begin
            if SameLoop(I, Q) then Exit(Q);
            Q := Next[Q];
          end;
        end;
  end;

  procedure Note(I: Integer);
  var
    Key: shortstring;
    At: Integer;
  begin
    Key := CellKey(Floor(Mid[I].X / CELL), Floor(Mid[I].Y / CELL),
      Floor(Mid[I].Z / CELL), Length(R[I].Outer));
    At := Head.FindIndexOf(Key);
    if At < 0 then
    begin
      Next[I] := -1;
      Head.Add(Key, Pointer(PtrInt(I + 1)));
    end
    else
    begin
      Next[I] := PtrInt(Head.Items[At]) - 1;
      Head.Items[At] := Pointer(PtrInt(I + 1));
    end;
  end;

var
  K: Integer;
begin
  N := Length(R);
  if N < 2 then Exit;
  SetLength(Mid, N);
  SetLength(Keep, N);
  SetLength(Next, N);
  for I := 0 to N - 1 do
  begin
    Mid[I] := P3(0, 0, 0);
    for K := 0 to High(R[I].Outer) do
      Mid[I] := Add3(Mid[I], R[I].Outer[K]);
    if Length(R[I].Outer) > 0 then
      Mid[I] := Mul3(Mid[I], 1 / Length(R[I].Outer));
  end;
  Head := TFPHashList.Create;
  try
    Kept := 0;
    for I := 0 to N - 1 do
    begin
      Keep[I] := (Length(R[I].Outer) < 3) or (TwinOf(I) < 0);
      if Keep[I] then
      begin
        if Length(R[I].Outer) >= 3 then Note(I);
        Inc(Kept);
      end;
    end;
  finally
    Head.Free;
  end;
  if Kept = N then Exit;
  Kept := 0;
  for I := 0 to N - 1 do
    if Keep[I] then
    begin
      if Kept <> I then R[Kept] := R[I];
      Inc(Kept);
    end;
  SetLength(R, Kept);
end;

function MakePlane(const N: TP3; const Through: TP3): TPlaneKey;
var
  U: TP3;
begin
  U := CanonicalNormal(N);
  Result.N := U;
  Result.D := U.X * Through.X + U.Y * Through.Y + U.Z * Through.Z;
end;

function SamePlane(const A, B: TPlaneKey; Tol: Double): Boolean;
begin
  Result := (Abs(A.N.X - B.N.X) < 1E-6) and (Abs(A.N.Y - B.N.Y) < 1E-6) and
            (Abs(A.N.Z - B.N.Z) < 1E-6) and (Abs(A.D - B.D) < Tol);
end;

{ Two axes across a plane, so points in it can be treated as flat. }
procedure PlaneBasis(const N: TP3; out U, W: TP3);
var
  T: TP3;
begin
  if Abs(N.Z) < 0.9 then T := P3(0, 0, 1) else T := P3(1, 0, 0);
  U := Norm3(Cross3(T, N));
  W := Norm3(Cross3(N, U));
end;

{ ------------------------------------------------- 1. cut at the crossings - }

{ Where two segments properly cross, each through the other's middle.  Ends
  landing on a segment, and overlapping segments, are handled separately in
  SplitAtCrossings as "this point lies on that segment". }
function MeetAt(const A1, A2, B1, B2: TP3; Tol: Double;
  out TA, TB: Double): Boolean;
var
  U, V, W, PA, PB: TP3;
  A, B, C, D, E, Den: Double;
begin
  Result := False;
  TA := 0;
  TB := 0;

  U := Sub3(A2, A1);
  V := Sub3(B2, B1);
  W := Sub3(A1, B1);

  A := Dot3(U, U);
  B := Dot3(U, V);
  C := Dot3(V, V);
  D := Dot3(U, W);
  E := Dot3(V, W);
  Den := A * C - B * B;
  if (A < 1E-18) or (C < 1E-18) then Exit;

  { parallel: overlaps are handled by the endpoint pass }
  if Abs(Den) < 1E-15 * A * C then Exit;

  TA := (B * E - C * D) / Den;
  TB := (A * E - B * D) / Den;
  { strictly inside both, or it is an endpoint case and not ours }
  if (TA <= Tol) or (TA >= 1 - Tol) or (TB <= Tol) or (TB >= 1 - Tol) then Exit;

  PA := Add3(A1, Mul3(U, TA));
  PB := Add3(B1, Mul3(V, TB));
  if Dist(PA, PB) > Tol then Exit;      { skew, passing at a distance }
  Result := True;
end;

function SplitAtCrossings(const Segs: TSegArray; Tol: Double): TSegArray;
var
  Cuts: array of array of Double;
  I, J, K, M, N, Count, GMask: Integer;
  TA, TB, Tmp, Cell: Double;
  P, Q, Lo, Hi: TP3;
  Grid: array of TIntArray;
  Near: TIntArray;

  procedure GrowBox(const R: TP3);
  begin
    Lo := P3(Min(Lo.X, R.X), Min(Lo.Y, R.Y), Min(Lo.Z, R.Z));
    Hi := P3(Max(Hi.X, R.X), Max(Hi.Y, R.Y), Max(Hi.Z, R.Z));
  end;

  function GridHash(CX, CY, CZ: Int64): Integer;
  begin
    Result := Integer((CX * 73856093) xor (CY * 19349663) xor (CZ * 83492791))
      and GMask;
  end;

  { Visit the cells this segment's box covers: add it if Add, else gather
    what is already there into Near. }
  procedure Visit(Which: Integer; Add: Boolean);
  var
    X0, Y0, Z0, X1, Y1, Z1, CX, CY, CZ: Int64;
    H, Q2: Integer;
  begin
    X0 := Floor(Min(Segs[Which].A.X, Segs[Which].B.X) / Cell);
    X1 := Floor(Max(Segs[Which].A.X, Segs[Which].B.X) / Cell);
    Y0 := Floor(Min(Segs[Which].A.Y, Segs[Which].B.Y) / Cell);
    Y1 := Floor(Max(Segs[Which].A.Y, Segs[Which].B.Y) / Cell);
    Z0 := Floor(Min(Segs[Which].A.Z, Segs[Which].B.Z) / Cell);
    Z1 := Floor(Max(Segs[Which].A.Z, Segs[Which].B.Z) / Cell);
    for CX := X0 to X1 do
      for CY := Y0 to Y1 do
        for CZ := Z0 to Z1 do
        begin
          H := GridHash(CX, CY, CZ);
          if Add then
          begin
            SetLength(Grid[H], Length(Grid[H]) + 1);
            Grid[H][High(Grid[H])] := Which;
          end
          else
            for Q2 := 0 to High(Grid[H]) do
            begin
              SetLength(Near, Length(Near) + 1);
              Near[High(Near)] := Grid[H][Q2];
            end;
        end;
  end;

  procedure AddCut(Which: Integer; T: Double);
  var
    Z: Integer;
  begin
    if (T <= Tol) or (T >= 1 - Tol) then Exit;
    for Z := 0 to High(Cuts[Which]) do
      if Abs(Cuts[Which][Z] - T) < Tol then Exit;
    SetLength(Cuts[Which], Length(Cuts[Which]) + 1);
    Cuts[Which][High(Cuts[Which])] := T;
  end;

begin
  N := Length(Segs);
  SetLength(Cuts, N);

  { Only pairs sharing a cell of a coarse grid are tried, not every pair.
    Trying a pair twice is harmless; a repeated cut is ignored. }
  Lo := Segs[0].A; Hi := Segs[0].A;
  for I := 0 to N - 1 do
  begin
    GrowBox(Segs[I].A);
    GrowBox(Segs[I].B);
  end;
  Cell := Max(Dist(Lo, Hi) / Max(4, Round(Sqrt(N))), 1E-9);
  GMask := 1;
  while GMask < N * 4 do GMask := GMask * 2;
  Dec(GMask);
  SetLength(Grid, GMask + 1);
  for I := 0 to N - 1 do
    Visit(I, True);

  for I := 0 to N - 1 do
  begin
    SetLength(Near, 0);
    Visit(I, False);
    for K := 0 to High(Near) do
    begin
      J := Near[K];
      if J <= I then Continue;
      { a proper crossing, each through the other's middle }
      if MeetAt(Segs[I].A, Segs[I].B, Segs[J].A, Segs[J].B, Tol, TA, TB) then
      begin
        AddCut(I, TA);
        AddCut(J, TB);
      end;
      { and every end that lands on the other one.  This covers T-junctions
        and segments lying along each other. }
      ClosestOnSeg(Segs[J].A, Segs[I].A, Segs[I].B, TA, TB);
      if TB < Tol then AddCut(I, TA);
      ClosestOnSeg(Segs[J].B, Segs[I].A, Segs[I].B, TA, TB);
      if TB < Tol then AddCut(I, TA);
      ClosestOnSeg(Segs[I].A, Segs[J].A, Segs[J].B, TA, TB);
      if TB < Tol then AddCut(J, TA);
      ClosestOnSeg(Segs[I].B, Segs[J].A, Segs[J].B, TA, TB);
      if TB < Tol then AddCut(J, TA);
    end;
  end;

  Count := 0;
  SetLength(Result, N);
  for I := 0 to N - 1 do
  begin
    { sort this segment's cuts along it }
    for J := 1 to High(Cuts[I]) do
    begin
      Tmp := Cuts[I][J];
      K := J - 1;
      while (K >= 0) and (Cuts[I][K] > Tmp) do
      begin
        Cuts[I][K + 1] := Cuts[I][K];
        Dec(K);
      end;
      Cuts[I][K + 1] := Tmp;
    end;

    P := Segs[I].A;
    for J := 0 to Length(Cuts[I]) do
    begin
      if J = Length(Cuts[I]) then Q := Segs[I].B
      else Q := Lerp(Segs[I].A, Segs[I].B, Cuts[I][J]);
      if Dist(P, Q) > Tol then
      begin
        if Count >= Length(Result) then SetLength(Result, Count * 2 + 8);
        Result[Count].A := P;
        Result[Count].B := Q;
        Inc(Count);
      end;
      P := Q;
    end;
  end;
  SetLength(Result, Count);
  M := 0;
  if M > 0 then ;
end;

{ ------------------------------------------------------------- the rest - }

function LoopArea(const Loop: TP3Array; const Normal: TP3): Double;
var
  I, N: Integer;
  Acc: TP3;
begin
  Result := 0;
  N := Length(Loop);
  if N < 3 then Exit;
  Acc := P3(0, 0, 0);
  for I := 0 to N - 1 do
    Acc := Add3(Acc, Cross3(Loop[I], Loop[(I + 1) mod N]));
  Result := Dot3(Acc, Normal) / 2;
end;

function InnerPointOf(const Outer: TP3Array; const Holes: array of TP3Array;
  const Normal: TP3): TP3;
var
  I, N, F: Integer;
  Mid, E, Side, N1, Q: TP3;
  Size, Step: Double;

  function InHole(const P: TP3): Boolean;
  var
    K: Integer;
  begin
    Result := False;
    for K := 0 to High(Holes) do
      if PointInLoop(P, Holes[K], Normal) then Exit(True);
  end;

begin
  Result := InnerPoint(Outer, Normal);
  if (Length(Holes) = 0) or not InHole(Result) then Exit;
  { the middle is in a hole: try points just inside each edge, stepping
    further in, until one is in the region }
  N := Length(Outer);
  N1 := Norm3(Normal);
  Size := 0;
  for I := 0 to N - 1 do
    Size := Max(Size, Dist(Outer[I], Outer[0]));
  for F := 1 to 3 do
  begin
    Step := Size * 1E-3 * F * F;
    for I := 0 to N - 1 do
    begin
      E := Sub3(Outer[(I + 1) mod N], Outer[I]);
      if Len3(E) < Step then Continue;
      Mid := P3((Outer[I].X + Outer[(I + 1) mod N].X) / 2,
                (Outer[I].Y + Outer[(I + 1) mod N].Y) / 2,
                (Outer[I].Z + Outer[(I + 1) mod N].Z) / 2);
      Side := Norm3(Cross3(N1, E));
      Q := P3(Mid.X + Side.X * Step, Mid.Y + Side.Y * Step, Mid.Z + Side.Z * Step);
      if PointInLoop(Q, Outer, Normal) and not InHole(Q) then Exit(Q);
      Q := P3(Mid.X - Side.X * Step, Mid.Y - Side.Y * Step, Mid.Z - Side.Z * Step);
      if PointInLoop(Q, Outer, Normal) and not InHole(Q) then Exit(Q);
    end;
  end;
end;

function InnerPoint(const Loop: TP3Array; const Normal: TP3): TP3;
var
  I, N: Integer;
  Mid, E, Side, N1, Q: TP3;
  Size, Step: Double;
begin
  N := Length(Loop);
  Result := P3(0, 0, 0);
  if N = 0 then Exit;
  for I := 0 to N - 1 do
    Result := P3(Result.X + Loop[I].X, Result.Y + Loop[I].Y, Result.Z + Loop[I].Z);
  Result := P3(Result.X / N, Result.Y / N, Result.Z / N);
  if N < 3 then Exit;
  { the corner average is fine when it is inside, which is most of the time }
  if PointInLoop(Result, Loop, Normal) then Exit;
  N1 := Norm3(Normal);
  Size := 0;
  for I := 0 to N - 1 do
    Size := Max(Size, Dist(Loop[I], Loop[0]));
  Step := Size * 1E-4;
  for I := 0 to N - 1 do
  begin
    E := Sub3(Loop[(I + 1) mod N], Loop[I]);
    if Len3(E) < Step then Continue;
    Mid := P3((Loop[I].X + Loop[(I + 1) mod N].X) / 2,
              (Loop[I].Y + Loop[(I + 1) mod N].Y) / 2,
              (Loop[I].Z + Loop[(I + 1) mod N].Z) / 2);
    Side := Norm3(Cross3(N1, E));
    Q := P3(Mid.X + Side.X * Step, Mid.Y + Side.Y * Step, Mid.Z + Side.Z * Step);
    if PointInLoop(Q, Loop, Normal) then Exit(Q);
    Q := P3(Mid.X - Side.X * Step, Mid.Y - Side.Y * Step, Mid.Z - Side.Z * Step);
    if PointInLoop(Q, Loop, Normal) then Exit(Q);
  end;
end;

function PointInLoop(const P: TP3; const Loop: TP3Array; const Normal: TP3;
  Tol: Double): Boolean;
var
  I, J, N: Integer;
  U, W: TP3;
  PU, PV: Double;
  AU, AV, BU, BV: Double;
  Inside: Boolean;
  T, Off: Double;
begin
  Result := False;
  N := Length(Loop);
  if N < 3 then Exit;
  PlaneBasis(Normal, U, W);

  { the boundary is checked separately; a ray cast is unreliable on an edge }
  for I := 0 to N - 1 do
  begin
    ClosestOnSeg(P, Loop[I], Loop[(I + 1) mod N], T, Off);
    if Off < Tol then Exit(True);
  end;

  PU := Dot3(Sub3(P, Loop[0]), U);
  PV := Dot3(Sub3(P, Loop[0]), W);
  Inside := False;
  J := N - 1;
  for I := 0 to N - 1 do
  begin
    AU := Dot3(Sub3(Loop[I], Loop[0]), U);
    AV := Dot3(Sub3(Loop[I], Loop[0]), W);
    BU := Dot3(Sub3(Loop[J], Loop[0]), U);
    BV := Dot3(Sub3(Loop[J], Loop[0]), W);
    if ((AV > PV) <> (BV > PV)) and
       (PU < (BU - AU) * (PV - AV) / (BV - AV) + AU) then
      Inside := not Inside;
    J := I;
  end;
  Result := Inside;
end;

{ Every plane the segments can lie in, without splitting or welding.  Cheap
  enough to run on every edit. }
function PlanesOf(const Segs: TSegArray; Tol: Double): TPlaneArray;
{ Ends and planes are looked up through hash grids (neighbor cells checked
  too) because linear scans are far too slow on big drawings. }
const
  CELL = 1E-4;       { ends: the grid cell; the tolerance is far inside it }
  PCELL = 1E-3;      { planes: the cell along the offset }
var
  I, J, K, N, NP: Integer;
  Ends: TP3Array;
  NEnds: Integer;
  AtEnd: array of TIntArray;
  Key: TPlaneKey;
  Dir1, Dir2: TP3;
  EndHead, PlaneHead: TFPHashList;
  EndNext, PlaneNext: TIntArray;
  Found: TPlaneArray;

  function CellKey(X, Y, Z, W: Int64): shortstring;
  begin
    SetLength(Result, 32);
    Move(X, Result[1], 8);
    Move(Y, Result[9], 8);
    Move(Z, Result[17], 8);
    Move(W, Result[25], 8);
  end;

  { the entry chained at the head of a cell, or -1 }
  function HeadOf(H: TFPHashList; const K: shortstring): Integer;
  begin
    Result := PtrInt(H.Find(K)) - 1;
  end;

  procedure Chain(H: TFPHashList; var Next: TIntArray; const K: shortstring; Ix: Integer);
  var
    At: Integer;
  begin
    if Ix >= Length(Next) then SetLength(Next, Max(16, Ix * 2));
    At := H.FindIndexOf(K);
    if At < 0 then
    begin
      Next[Ix] := -1;
      H.Add(K, Pointer(PtrInt(Ix + 1)));
    end
    else
    begin
      Next[Ix] := PtrInt(H.Items[At]) - 1;
      H.Items[At] := Pointer(PtrInt(Ix + 1));
    end;
  end;

  function EndOf(const P: TP3): Integer;
  var
    CX, CY, CZ, DX, DY, DZ: Int64;
    Q: Integer;
  begin
    CX := Floor(P.X / CELL);
    CY := Floor(P.Y / CELL);
    CZ := Floor(P.Z / CELL);
    for DX := -1 to 1 do
      for DY := -1 to 1 do
        for DZ := -1 to 1 do
        begin
          Q := HeadOf(EndHead, CellKey(CX + DX, CY + DY, CZ + DZ, 0));
          while Q >= 0 do
          begin
            if Dist(Ends[Q], P) < Tol then Exit(Q);
            Q := EndNext[Q];
          end;
        end;
    if NEnds >= Length(Ends) then SetLength(Ends, Max(16, NEnds * 2));
    Ends[NEnds] := P;
    Result := NEnds;
    Inc(NEnds);
    Chain(EndHead, EndNext, CellKey(CX, CY, CZ, 0), Result);
  end;

  { is this plane already listed?  The normal is rounded to a thousandth; a
    part near a rounding boundary is looked up on both sides. }
  function KnownPlane(const Kp: TPlaneKey): Boolean;
  var
    NX, NY, NZ, D0: Int64;
    AX, AY, AZ: array[0..1] of Int64;
    CX, CY, CZ: Integer;
    IX, IY, IZ, ID: Integer;
    Q: Integer;

    procedure Cands(V: Double; var A: array of Int64; out C: Integer);
    var
      S: Double;
    begin
      S := V * 1000;
      A[0] := Round(S);
      C := 1;
      if Abs(Frac(S)) > 0.5 - 2E-3 then
      begin
        if S >= A[0] then A[1] := A[0] + 1 else A[1] := A[0] - 1;
        C := 2;
      end;
    end;

  begin
    Cands(Kp.N.X, AX, CX);
    Cands(Kp.N.Y, AY, CY);
    Cands(Kp.N.Z, AZ, CZ);
    D0 := Floor(Kp.D / PCELL);
    for IX := 0 to CX - 1 do
      for IY := 0 to CY - 1 do
        for IZ := 0 to CZ - 1 do
          for ID := -1 to 1 do
          begin
            Q := HeadOf(PlaneHead, CellKey(AX[IX], AY[IY], AZ[IZ], D0 + ID));
            while Q >= 0 do
            begin
              if SamePlane(Found[Q], Kp, Tol) then Exit(True);
              Q := PlaneNext[Q];
            end;
          end;
    Result := False;
  end;

  procedure NotePlane(const Kp: TPlaneKey; Ix: Integer);
  begin
    Chain(PlaneHead, PlaneNext,
      CellKey(Round(Kp.N.X * 1000), Round(Kp.N.Y * 1000), Round(Kp.N.Z * 1000),
              Floor(Kp.D / PCELL)), Ix);
  end;

begin
  Result := nil;
  N := Length(Segs);
  if N < 3 then Exit;
  NEnds := 0;
  SetLength(Ends, N * 2);
  SetLength(AtEnd, N * 2);
  EndHead := TFPHashList.Create;
  PlaneHead := TFPHashList.Create;
  try
    for I := 0 to N - 1 do
    begin
      if Assigned(Progress) and (N > 20000) and ((I and 8191) = 0) then
        if not Progress('Sorting the lines by plane', 0.5 * I / N) then Exit;
      J := EndOf(Segs[I].A);
      SetLength(AtEnd[J], Length(AtEnd[J]) + 1);
      AtEnd[J][High(AtEnd[J])] := I;
      J := EndOf(Segs[I].B);
      SetLength(AtEnd[J], Length(AtEnd[J]) + 1);
      AtEnd[J][High(AtEnd[J])] := I;
    end;

    NP := 0;
    SetLength(Found, 8);
    for K := 0 to NEnds - 1 do
    begin
      if Assigned(Progress) and (N > 20000) and ((K and 4095) = 0) then
        if not Progress('Sorting the lines by plane', 0.5 + 0.5 * K / NEnds) then Break;
      for I := 0 to High(AtEnd[K]) - 1 do
        for J := I + 1 to High(AtEnd[K]) do
        begin
          Dir1 := Sub3(Segs[AtEnd[K][I]].B, Segs[AtEnd[K][I]].A);
          Dir2 := Sub3(Segs[AtEnd[K][J]].B, Segs[AtEnd[K][J]].A);
          if Len3(Cross3(Dir1, Dir2)) < 1E-9 then Continue;
          Key := MakePlane(Cross3(Dir1, Dir2), Ends[K]);
          if KnownPlane(Key) then Continue;
          if NP >= Length(Found) then SetLength(Found, NP * 2);
          Found[NP] := Key;
          NotePlane(Key, NP);
          Inc(NP);
        end;
    end;
    SetLength(Found, NP);
    Result := Found;
  finally
    EndHead.Free;
    PlaneHead.Free;
  end;
end;

{ The segments in one plane, plus a signature that changes when they do, so
  an unchanged plane can reuse its cached regions. }
function SegsInPlane(const Segs: TSegArray; const K: TPlaneKey; Tol: Double;
  out Sig: Int64): TSegArray;
var
  I, N: Integer;

  function Mix(const P: TP3): Int64;
  begin
    Result := Round(P.X / Tol) * 73856093;
    Result := Result xor (Round(P.Y / Tol) * 19349663);
    Result := Result xor (Round(P.Z / Tol) * 83492791);
  end;

begin
  N := 0;
  Sig := 0;
  SetLength(Result, Length(Segs));
  for I := 0 to High(Segs) do
    if (Abs(Dot3(K.N, Segs[I].A) - K.D) < Tol) and
       (Abs(Dot3(K.N, Segs[I].B) - K.D) < Tol) then
    begin
      Result[N] := Segs[I];
      { summed, so segment order does not matter }
      Sig := Sig + (Mix(Segs[I].A) + Mix(Segs[I].B));
      Inc(N);
    end;
  SetLength(Result, N);
  Sig := Sig xor (Int64(N) * 2654435761);
end;

function BuildRegionsCached(const Segs: TSegArray; var Cache: TRegionCache;
  Tol: Double): TRegionArray;
var
  Keys: TPlaneArray;
  Mine: TSegArray;
  Fresh: TRegionCache;
  Sig: Int64;
  I, J, N, Count: Integer;
  Hit: Boolean;
begin
  Result := nil;
  Keys := PlanesOf(Segs, Tol);
  if Length(Keys) = 0 then
  begin
    Cache.Keys := nil;
    Cache.Sig := nil;
    Cache.Found := nil;
    Exit;
  end;

  N := Length(Keys);
  SetLength(Fresh.Keys, N);
  SetLength(Fresh.Sig, N);
  SetLength(Fresh.Found, N);
  Count := 0;

  for I := 0 to N - 1 do
  begin
    { report progress on big drawings and stop if asked; the caller copes
      with a short result }
    if Assigned(Progress) and (N > 20) and ((I and 7) = 0) then
      if not Progress('Finding the flat areas', I / N) then Break;
    Mine := SegsInPlane(Segs, Keys[I], Tol, Sig);
    Fresh.Keys[I] := Keys[I];
    Fresh.Sig[I] := Sig;

    Hit := False;
    for J := 0 to High(Cache.Keys) do
      if (Cache.Sig[J] = Sig) and SamePlane(Cache.Keys[J], Keys[I], Tol) then
      begin
        Fresh.Found[I] := Cache.Found[J];
        Hit := True;
        Break;
      end;
    if not Hit then
      Fresh.Found[I] := BuildRegions(Mine, Tol);

    Inc(Count, Length(Fresh.Found[I]));
  end;

  Cache := Fresh;
  SetLength(Result, Count);
  Count := 0;
  for I := 0 to N - 1 do
    for J := 0 to High(Fresh.Found[I]) do
    begin
      Result[Count] := Fresh.Found[I][J];
      Inc(Count);
    end;
  { Two keys for one plane find the same loops; drop the twins here, not by
    skipping a key, or the cache could keep an empty entry for the key that
    was skipped. }
  DropTwinRegions(Result, Tol);
end;

function BuildRegions(const Segs: TSegArray; Tol: Double): TRegionArray;
var
  Cut: TSegArray;
  Verts: TP3Array;
  NV: Integer;
  Bucket: array of TIntArray;
  EBucket: array of TIntArray;
  Parent: TIntArray;
  HashMask: Integer;

  EA, EB: TIntArray;          { each undirected edge, as two vertex numbers }
  NE: Integer;
  Planes: array of TPlaneKey;
  NP: Integer;
  Loops: TLoopArray;
  LoopPlane: TIntArray;
  NLoop: Integer;

  { any mixing will do; a cell holds one or two vertices }
  function CellHash(CX, CY, CZ: Int64): Integer;
  begin
    Result := Integer((CX * 73856093) xor (CY * 19349663) xor (CZ * 83492791))
      and HashMask;
  end;

  { Has this edge been added already, either way round?  Records it if not.
    Both directions must match: a duplicate edge makes the walk trace a slit
    instead of dividing the face.  EA/EB keep the drawn direction, which the
    dart builder needs. }
  function EdgeSeen(A, B: Integer): Boolean;
  var
    H, K, T, W: Integer;
  begin
    if A > B then begin T := A; A := B; B := T; end;
    H := ((A * 92837111) xor (B * 689287499)) and HashMask;
    if H < 0 then H := -H and HashMask;
    for K := 0 to High(EBucket[H]) do
    begin
      W := EBucket[H][K];
      if ((EA[W] = A) and (EB[W] = B)) or
         ((EA[W] = B) and (EB[W] = A)) then Exit(True);
    end;
    SetLength(EBucket[H], Length(EBucket[H]) + 1);
    EBucket[H][High(EBucket[H])] := NE;
    Result := False;
  end;

  { Which connected piece a vertex belongs to.  Only loops in different
    pieces can nest, so this avoids testing every loop against every other. }
  function Root(V: Integer): Integer;
  begin
    while Parent[V] <> V do
    begin
      Parent[V] := Parent[Parent[V]];
      V := Parent[V];
    end;
    Result := V;
  end;

  { Welds through a grid of cells one tolerance across, so a match is in this
    cell or one of the 26 around it; a linear scan is far too slow. }
  function VertexOf(const P: TP3): Integer;
  var
    CX, CY, CZ, DX, DY, DZ: Int64;
    H, I, K: Integer;
  begin
    CX := Floor(P.X / Tol);
    CY := Floor(P.Y / Tol);
    CZ := Floor(P.Z / Tol);
    for DX := -1 to 1 do
      for DY := -1 to 1 do
        for DZ := -1 to 1 do
        begin
          H := CellHash(CX + DX, CY + DY, CZ + DZ);
          for K := 0 to High(Bucket[H]) do
          begin
            I := Bucket[H][K];
            if Dist(Verts[I], P) < Tol then Exit(I);
          end;
        end;
    if NV >= Length(Verts) then SetLength(Verts, Max(16, NV * 2));
    Verts[NV] := P;
    Result := NV;
    H := CellHash(CX, CY, CZ);
    SetLength(Bucket[H], Length(Bucket[H]) + 1);
    Bucket[H][High(Bucket[H])] := NV;
    Inc(NV);
  end;

  procedure NotePlane(const N, Through: TP3);
  var
    K: TPlaneKey;
    I: Integer;
  begin
    if Len3(N) < 1E-9 then Exit;
    K := MakePlane(N, Through);
    for I := 0 to NP - 1 do
      if SamePlane(Planes[I], K, Tol) then Exit;
    if NP >= Length(Planes) then SetLength(Planes, Max(8, NP * 2));
    Planes[NP] := K;
    Inc(NP);
  end;

  function EdgeInPlane(E: Integer; const K: TPlaneKey): Boolean;
  begin
    Result := (Abs(Dot3(K.N, Verts[EA[E]]) - K.D) < Tol) and
              (Abs(Dot3(K.N, Verts[EB[E]]) - K.D) < Tol);
  end;

  { Walk one plane's sub-graph and collect every cycle that goes round the
    right way. }
  procedure WalkPlane(PI: Integer);
  var
    K: TPlaneKey;
    U, W: TP3;
    Darts: array of TDart;
    ND, I, J, E, D, T, Start, Cur, Best, Steps: Integer;
    Out_: array of TIntArray;      { darts leaving each vertex, by angle }
    Loop: TP3Array;
    NL: Integer;
    Ang: Double;
    Tmp: Integer;
  begin
    K := Planes[PI];
    PlaneBasis(K.N, U, W);

    ND := 0;
    SetLength(Darts, NE * 2);
    for E := 0 to NE - 1 do
    begin
      if not EdgeInPlane(E, K) then Continue;
      Darts[ND].V0 := EA[E];
      Darts[ND].V1 := EB[E];
      Darts[ND].Twin := ND + 1;
      Darts[ND + 1].V0 := EB[E];
      Darts[ND + 1].V1 := EA[E];
      Darts[ND + 1].Twin := ND;
      Inc(ND, 2);
    end;
    SetLength(Darts, ND);
    if ND < 6 then Exit;             { fewer than three edges encloses nothing }

    for I := 0 to ND - 1 do
    begin
      Darts[I].Used := False;
      Darts[I].Ang := ArcTan2(
        Dot3(Sub3(Verts[Darts[I].V1], Verts[Darts[I].V0]), W),
        Dot3(Sub3(Verts[Darts[I].V1], Verts[Darts[I].V0]), U));
    end;

    { the darts leaving each vertex, sorted anticlockwise }
    SetLength(Out_, NV);
    for I := 0 to NV - 1 do SetLength(Out_[I], 0);
    for I := 0 to ND - 1 do
    begin
      J := Darts[I].V0;
      SetLength(Out_[J], Length(Out_[J]) + 1);
      Out_[J][High(Out_[J])] := I;
    end;
    for I := 0 to NV - 1 do
      for J := 1 to High(Out_[I]) do
      begin
        Tmp := Out_[I][J];
        Ang := Darts[Tmp].Ang;
        T := J - 1;
        while (T >= 0) and (Darts[Out_[I][T]].Ang > Ang) do
        begin
          Out_[I][T + 1] := Out_[I][T];
          Dec(T);
        end;
        Out_[I][T + 1] := Tmp;
      end;

    for Start := 0 to ND - 1 do
    begin
      if Darts[Start].Used then Continue;
      Cur := Start;
      NL := 0;
      SetLength(Loop, 8);
      Steps := 0;
      repeat
        Darts[Cur].Used := True;
        if NL >= Length(Loop) then SetLength(Loop, NL * 2);
        Loop[NL] := Verts[Darts[Cur].V0];
        Inc(NL);

        { arrived along Cur; leave by the dart immediately clockwise of the
          way back }
        D := Darts[Cur].Twin;
        J := Darts[D].V0;
        Best := -1;
        for I := 0 to High(Out_[J]) do
          if Out_[J][I] = D then
          begin
            if Length(Out_[J]) = 1 then Best := D
            else if I = 0 then Best := Out_[J][High(Out_[J])]
            else Best := Out_[J][I - 1];
            Break;
          end;
        if Best < 0 then Break;
        Cur := Best;
        Inc(Steps);
      until (Cur = Start) or (Steps > ND + 2);

      if (Cur <> Start) or (NL < 3) then Continue;
      SetLength(Loop, NL);
      { the one wound the other way is the space around the drawing }
      if LoopArea(Loop, K.N) <= Tol then Continue;
      if NLoop >= Length(Loops) then
      begin
        SetLength(Loops, Max(8, NLoop * 2));
        SetLength(LoopPlane, Length(Loops));
      end;
      Loops[NLoop] := Copy(Loop, 0, NL);
      LoopPlane[NLoop] := PI;
      Inc(NLoop);
    end;
  end;

var
  I, J, K, E, Count: Integer;
  Dir1, Dir2: TP3;
  Mid: TP3;
  AtVert: array of TIntArray;
  LoopArea_: array of Double;
  LoopPart: TIntArray;
  Between: Boolean;
  KMid: TP3;
begin
  Result := nil;
  Cut := SplitAtCrossings(Segs, Tol);
  if Length(Cut) < 3 then Exit;

  { 2. weld the ends together }
  NV := 0;
  SetLength(Verts, 32);
  HashMask := 1;
  while HashMask < Length(Cut) * 4 do HashMask := HashMask * 2;
  Dec(HashMask);
  SetLength(Bucket, HashMask + 1);
  SetLength(EBucket, HashMask + 1);
  NE := 0;
  SetLength(EA, Length(Cut));
  SetLength(EB, Length(Cut));
  SetLength(Parent, Length(Cut) * 2 + 4);
  for I := 0 to High(Parent) do Parent[I] := I;
  for I := 0 to High(Cut) do
  begin
    J := VertexOf(Cut[I].A);
    E := VertexOf(Cut[I].B);
    if J = E then Continue;
    { skip a repeated edge (hashed, for speed) }
    if EdgeSeen(J, E) then Continue;
    EA[NE] := J;
    EB[NE] := E;
    Inc(NE);
    Parent[Root(J)] := Root(E);
  end;
  SetLength(Verts, NV);
  if NE < 3 then Exit;

  { 3. every plane two edges meeting at a vertex can lie in.  Going through
       the vertices avoids trying every pair of edges. }
  SetLength(AtVert, NV);
  for I := 0 to NV - 1 do SetLength(AtVert[I], 0);
  for I := 0 to NE - 1 do
  begin
    SetLength(AtVert[EA[I]], Length(AtVert[EA[I]]) + 1);
    AtVert[EA[I]][High(AtVert[EA[I]])] := I;
    SetLength(AtVert[EB[I]], Length(AtVert[EB[I]]) + 1);
    AtVert[EB[I]][High(AtVert[EB[I]])] := I;
  end;
  NP := 0;
  SetLength(Planes, 8);
  for K := 0 to NV - 1 do
    for I := 0 to High(AtVert[K]) - 1 do
      for J := I + 1 to High(AtVert[K]) do
      begin
        Dir1 := Sub3(Verts[EB[AtVert[K][I]]], Verts[EA[AtVert[K][I]]]);
        Dir2 := Sub3(Verts[EB[AtVert[K][J]]], Verts[EA[AtVert[K][J]]]);
        NotePlane(Cross3(Dir1, Dir2), Verts[K]);
      end;

  { 4. walk each plane }
  NLoop := 0;
  SetLength(Loops, 16);
  SetLength(LoopPlane, 16);
  for I := 0 to NP - 1 do
    WalkPlane(I);
  SetLength(Loops, NLoop);
  SetLength(LoopPlane, NLoop);
  if NLoop = 0 then Exit;

  { 5. a loop inside another is a hole in it and also a region of its own,
       so either can be pushed.  Only loops in different connected pieces can
       nest; joined loops were already separated by the walk. }
  SetLength(LoopArea_, NLoop);
  SetLength(LoopPart, NLoop);
  for I := 0 to NLoop - 1 do
  begin
    LoopArea_[I] := Abs(LoopArea(Loops[I], Planes[LoopPlane[I]].N));
    LoopPart[I] := Root(VertexOf(Loops[I][0]));
  end;

  Count := 0;
  SetLength(Result, NLoop);
  for I := 0 to NLoop - 1 do
  begin
    Result[Count].Normal := Planes[LoopPlane[I]].N;
    Result[Count].Outer := Loops[I];
    SetLength(Result[Count].Holes, 0);
    for J := 0 to NLoop - 1 do
    begin
      if J = I then Continue;
      if LoopPart[J] = LoopPart[I] then Continue;
      if LoopPlane[J] <> LoopPlane[I] then Continue;
      if LoopArea_[J] >= LoopArea_[I] then Continue;
      Mid := Loops[J][0];
      for E := 1 to High(Loops[J]) do Mid := Add3(Mid, Loops[J][E]);
      Mid := Mul3(Mid, 1 / Length(Loops[J]));
      if not PointInLoop(Mid, Loops[I], Planes[LoopPlane[I]].N, Tol) then
        Continue;
      { Only the nearest loop around J takes it as a hole.  With three
        nested squares, the middle is a hole in the inner ring only. }
      Between := False;
      for K := 0 to NLoop - 1 do
      begin
        if (K = I) or (K = J) then Continue;
        if LoopPlane[K] <> LoopPlane[I] then Continue;
        if (LoopArea_[K] <= LoopArea_[J]) or (LoopArea_[K] >= LoopArea_[I]) then Continue;
        if not PointInLoop(Mid, Loops[K], Planes[LoopPlane[K]].N, Tol) then Continue;
        KMid := Loops[K][0];
        for E := 1 to High(Loops[K]) do KMid := Add3(KMid, Loops[K][E]);
        KMid := Mul3(KMid, 1 / Length(Loops[K]));
        if PointInLoop(KMid, Loops[I], Planes[LoopPlane[I]].N, Tol) then
        begin
          Between := True;
          Break;
        end;
      end;
      if Between then Continue;
      SetLength(Result[Count].Holes, Length(Result[Count].Holes) + 1);
      Result[Count].Holes[High(Result[Count].Holes)] := Loops[J];
    end;
    Inc(Count);
  end;
  SetLength(Result, Count);
  DropTwinRegions(Result, Tol);
end;

end.

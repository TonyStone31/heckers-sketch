unit hsTriangulate;

{ Cutting a polygon into triangles, by ear clipping, with holes bridged
  into the outline first.  Faces are drawn as triangles because a triangle
  is always flat, so its depth is exact even when the face is warped.  STL
  export uses it too, so it works on 2D index rings into the caller's points.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math;

type
  { triples of indices into the caller's vertex list }
  TTriList = array of Integer;
  TIndexRing = array of Integer;
  TIndexRings = array of TIndexRing;

{ Cut an outline and its holes into triangles.  Outline and holes are index
  rings into Pts, in any winding.  Tris comes back as index triples.  False
  means the ring was degenerate; Tris is then empty. }
function Triangulate(const Pts: array of TPointF; const Outline: TIndexRing;
  const Holes: TIndexRings; out Tris: TTriList): Boolean;

{ Signed area, positive anticlockwise.  Public so a triangulation can be
  checked: the pieces must add up to the whole. }
function RingArea(const Pts: array of TPointF; const Ring: TIndexRing): Double;

implementation

function RingArea(const Pts: array of TPointF; const Ring: TIndexRing): Double;
var
  I, J, N: Integer;
begin
  Result := 0;
  N := Length(Ring);
  if N < 3 then Exit;
  for I := 0 to N - 1 do
  begin
    J := (I + 1) mod N;
    { keep the casts: TPointF holds singles, and without them each product
      is rounded to single before the subtraction }
    Result := Result + (Double(Pts[Ring[I]].X) * Double(Pts[Ring[J]].Y) -
                        Double(Pts[Ring[J]].X) * Double(Pts[Ring[I]].Y));
  end;
  Result := Result / 2;
end;

{ Twice the signed area of a triangle: positive when A, B, C turn
  anticlockwise. }
function Cross2(const A, B, C: TPointF): Double; inline;
begin
  Result := (Double(B.X) - A.X) * (Double(C.Y) - A.Y) -
            (Double(C.X) - A.X) * (Double(B.Y) - A.Y);
end;

{ Is P inside triangle ABC?  A point on an edge counts as inside, so an ear
  with a vertex on its edge is refused; otherwise slivers overlap. }
function InTri(const A, B, C, P: TPointF): Boolean;
var
  D1, D2, D3: Double;
  Neg, Pos: Boolean;
begin
  D1 := Cross2(A, B, P);
  D2 := Cross2(B, C, P);
  D3 := Cross2(C, A, P);
  Neg := (D1 < 0) or (D2 < 0) or (D3 < 0);
  Pos := (D1 > 0) or (D2 > 0) or (D3 > 0);
  Result := not (Neg and Pos);
end;

{ Splice one hole into the ring (Eberly's method).  Cast a ray right from
  the hole's rightmost corner M to the first ring edge, and aim at that
  edge's right end P, unless a reflex corner sits inside triangle M-X-P; then
  aim at the one at the shallowest angle.  The hole goes in out and back
  along the bridge, so both ends appear twice. }
procedure BridgeHole(const Pts: array of TPointF; var Ring: TIndexRing;
  const Hole: TIndexRing);
var
  I, J, N, M, HStart, Best, K: Integer;
  HX, HY, X, T, BestX, Ang, BestAng: Double;
  A, B, Mp, Xp, Pp: TPointF;
  Merged: TIndexRing;
  EdgeI: Integer;
begin
  N := Length(Ring);
  M := Length(Hole);
  if (N < 3) or (M < 3) then Exit;

  { the hole's rightmost corner }
  HStart := 0;
  for I := 1 to M - 1 do
    if Pts[Hole[I]].X > Pts[Hole[HStart]].X then HStart := I;
  Mp := Pts[Hole[HStart]];
  HX := Mp.X;
  HY := Mp.Y;

  { where the ray to the right first meets the ring }
  EdgeI := -1;
  BestX := 1E300;
  for I := 0 to N - 1 do
  begin
    J := (I + 1) mod N;
    A := Pts[Ring[I]];
    B := Pts[Ring[J]];
    if (A.Y > HY) = (B.Y > HY) then Continue;
    T := (HY - A.Y) / (B.Y - A.Y);
    X := A.X + (B.X - A.X) * T;
    if X < HX - 1E-12 then Continue;
    if X < BestX then
    begin
      BestX := X;
      EdgeI := I;
    end;
  end;
  if EdgeI < 0 then Exit;

  Xp.X := BestX;
  Xp.Y := HY;

  { the right-hand end of that edge is the candidate to aim at }
  A := Pts[Ring[EdgeI]];
  B := Pts[Ring[(EdgeI + 1) mod N]];
  if A.X >= B.X then Best := EdgeI else Best := (EdgeI + 1) mod N;
  Pp := Pts[Ring[Best]];

  { unless a reflex corner of the ring is in the way, in which case aim at
    the shallowest one of those }
  BestAng := 1E300;
  for I := 0 to N - 1 do
  begin
    if I = Best then Continue;
    J := (I + N - 1) mod N;
    K := (I + 1) mod N;
    { skip convex corners: only a reflex corner can block the bridge }
    if Cross2(Pts[Ring[J]], Pts[Ring[I]], Pts[Ring[K]]) > 0 then Continue;
    if Pts[Ring[I]].X < HX then Continue;
    if not InTri(Mp, Xp, Pp, Pts[Ring[I]]) then Continue;
    { shallowest angle from the ray, nearest first on a tie }
    Ang := Abs(Pts[Ring[I]].Y - HY) / Max(1E-12, Pts[Ring[I]].X - HX);
    if Ang < BestAng then
    begin
      BestAng := Ang;
      Best := I;
    end;
  end;

  { out along the bridge, round the hole, and back }
  SetLength(Merged, N + M + 2);
  K := 0;
  for I := 0 to Best do begin Merged[K] := Ring[I]; Inc(K); end;
  for I := 0 to M do
  begin
    Merged[K] := Hole[(HStart + I) mod M];
    Inc(K);
  end;
  for I := Best to N - 1 do begin Merged[K] := Ring[I]; Inc(K); end;
  SetLength(Merged, K);
  Ring := Merged;
end;

function Triangulate(const Pts: array of TPointF; const Outline: TIndexRing;
  const Holes: TIndexRings; out Tris: TTriList): Boolean;
var
  Ring: TIndexRing;
  Work: TIndexRings;
  Order: array of Integer;
  N, I, J, K, P, Q, R, NT, Stuck: Integer;
  A, B, C: TPointF;
  Ear: Boolean;
  Rightmost: array of Double;
  TI: Integer;
begin
  Tris := nil;
  Result := False;
  if Length(Outline) < 3 then Exit;

  SetLength(Ring, Length(Outline));
  for I := 0 to High(Outline) do Ring[I] := Outline[I];

  { everything below assumes an anticlockwise ring }
  if RingArea(Pts, Ring) < 0 then
  begin
    N := Length(Ring);
    for I := 0 to (N div 2) - 1 do
    begin
      K := Ring[I];
      Ring[I] := Ring[N - 1 - I];
      Ring[N - 1 - I] := K;
    end;
  end;

  { holes run clockwise, and are bridged rightmost first so an earlier
    bridge never blocks a later one }
  SetLength(Work, 0);
  SetLength(Rightmost, 0);
  for I := 0 to High(Holes) do
  begin
    if Length(Holes[I]) < 3 then Continue;
    K := Length(Work);
    SetLength(Work, K + 1);
    SetLength(Rightmost, K + 1);
    SetLength(Work[K], Length(Holes[I]));
    for J := 0 to High(Holes[I]) do Work[K][J] := Holes[I][J];
    if RingArea(Pts, Work[K]) > 0 then
      for J := 0 to High(Work[K]) div 2 do
      begin
        R := Work[K][J];
        Work[K][J] := Work[K][High(Work[K]) - J];
        Work[K][High(Work[K]) - J] := R;
      end;
    Rightmost[K] := -1E300;
    for J := 0 to High(Work[K]) do
      if Pts[Work[K][J]].X > Rightmost[K] then Rightmost[K] := Pts[Work[K][J]].X;
  end;

  SetLength(Order, Length(Work));
  for I := 0 to High(Order) do Order[I] := I;
  for I := 0 to High(Order) - 1 do
    for J := 0 to High(Order) - 1 - I do
      if Rightmost[Order[J]] < Rightmost[Order[J + 1]] then
      begin
        TI := Order[J]; Order[J] := Order[J + 1]; Order[J + 1] := TI;
      end;

  for I := 0 to High(Order) do
    BridgeHole(Pts, Ring, Work[Order[I]]);

  N := Length(Ring);
  if N < 3 then Exit;

  SetLength(Tris, (N - 2) * 3);
  NT := 0;
  I := 0;
  Stuck := 0;
  while Length(Ring) > 3 do
  begin
    N := Length(Ring);
    { a full lap with no ear means the input is not a simple polygon; keep
      what we have }
    if Stuck > N then Break;
    P := (I + N - 1) mod N;
    Q := I mod N;
    R := (I + 1) mod N;
    A := Pts[Ring[P]];
    B := Pts[Ring[Q]];
    C := Pts[Ring[R]];

    { a corner that turns the wrong way is a notch, not an ear }
    Ear := Cross2(A, B, C) > 0;

    { and it is only an ear if nothing else of the ring is inside it }
    if Ear then
      for J := 0 to N - 1 do
      begin
        if (J = P) or (J = Q) or (J = R) then Continue;
        { the doubled ends of a bridge share an index with the corner; they
          are not inside it }
        if (Ring[J] = Ring[P]) or (Ring[J] = Ring[Q]) or (Ring[J] = Ring[R]) then
          Continue;
        if InTri(A, B, C, Pts[Ring[J]]) then
        begin
          Ear := False;
          Break;
        end;
      end;

    if not Ear then
    begin
      Inc(Stuck);
      I := R;
      Continue;
    end;

    if NT + 3 > Length(Tris) then SetLength(Tris, NT + 3);
    Tris[NT] := Ring[P]; Tris[NT + 1] := Ring[Q]; Tris[NT + 2] := Ring[R];
    Inc(NT, 3);

    { snip the corner off and carry on from what has taken its place }
    for J := Q to Length(Ring) - 2 do Ring[J] := Ring[J + 1];
    SetLength(Ring, Length(Ring) - 1);
    Stuck := 0;
    I := Q mod Length(Ring);
  end;

  if Length(Ring) = 3 then
  begin
    if NT + 3 > Length(Tris) then SetLength(Tris, NT + 3);
    Tris[NT] := Ring[0]; Tris[NT + 1] := Ring[1]; Tris[NT + 2] := Ring[2];
    Inc(NT, 3);
  end;
  SetLength(Tris, NT);
  Result := NT >= 3;
end;

end.

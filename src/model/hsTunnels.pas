unit hsTunnels;

{ Tunnels that cross.  When a new tunnel passes through an old one in the
  same solid, both sets of walls are cut along the crossing, the pieces
  inside the other bore are dropped, and the crossing is drawn.  SketchUp
  leaves this to Intersect Faces by hand; here it happens at the push. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, hsDrawing, hsFaceFinder;

{ Cut the bore NewBore (an ekBore entity) against every other bore of the
  same solid it crosses.  Returns how many walls were divided. }
function CutCrossingBores(D: TWorkDoc; NewBore: Integer): Integer;

{ Strictly inside the tunnel's bore - not on its walls, not at its mouths. }
function InsideBore(D: TWorkDoc; Bore: Integer; const P: TP3; Tol: Double): Boolean;

{ How far the face can be pushed before it hits an existing tunnel wall:
  Dist if nothing is in the way, else the signed distance to the first wall.
  Push/pull stops there, like SketchUp; Drill does not use it. }
function BoreLimit(D: TWorkDoc; Face: Integer; Dist: Double): Double;

implementation

type
  TCut = record
    FA, FB: Integer;       { the two walls that cross }
    S0, S1: TP3;           { where they do }
  end;

function BoreAxis(D: TWorkDoc; Bore: Integer): TP3;
begin
  Result := Norm3(Sub3(D[Bore].B, D[Bore].Poly[0]));
end;

function BoreLen(D: TWorkDoc; Bore: Integer): Double;
begin
  Result := Dist(D[Bore].B, D[Bore].Poly[0]);
end;

{ how far P is from the nearest edge of the loop, both taken in the plane }
function DistToLoop(const P: TP3; const Loop: TP3Array): Double;
var
  I, N: Integer;
  A, B, E: TP3;
  T, L: Double;
begin
  Result := 1E300;
  N := Length(Loop);
  for I := 0 to N - 1 do
  begin
    A := Loop[I];
    B := Loop[(I + 1) mod N];
    E := Sub3(B, A);
    L := Len3(E);
    if L < 1E-12 then Continue;
    T := Dot3(Sub3(P, A), E) / (L * L);
    if T < 0 then T := 0 else if T > 1 then T := 1;
    Result := Min(Result, Dist(P, Add3(A, Mul3(E, T))));
  end;
end;

function InsideBore(D: TWorkDoc; Bore: Integer; const P: TP3; Tol: Double): Boolean;
var
  Ax, Q: TP3;
  T: Double;
begin
  Result := False;
  Ax := BoreAxis(D, Bore);
  T := Dot3(Sub3(P, D[Bore].Poly[0]), Ax);
  if (T <= Tol) or (T >= BoreLen(D, Bore) - Tol) then Exit;
  Q := Sub3(P, Mul3(Ax, T));
  if not PointInLoop(Q, D[Bore].Poly, Ax) then Exit;
  Result := DistToLoop(Q, D[Bore].Poly) > Tol;
end;

{ on the tunnel's wall surface: along its length and on the outline }
function OnBoreWall(D: TWorkDoc; Bore: Integer; const P: TP3; Tol: Double;
  out T: Double): Boolean;
var
  Ax, Q: TP3;
begin
  Result := False;
  Ax := BoreAxis(D, Bore);
  T := Dot3(Sub3(P, D[Bore].Poly[0]), Ax);
  if (T < -Tol) or (T > BoreLen(D, Bore) + Tol) then Exit;
  Q := Sub3(P, Mul3(Ax, T));
  Result := DistToLoop(Q, D[Bore].Poly) <= Tol;
end;

{ A lining wall has every corner on the bore's wall surface, spread along
  its length; corners all at one depth are a face across the mouth. }
function IsLining(D: TWorkDoc; Bore, F: Integer; Tol: Double): Boolean;
var
  I: Integer;
  T, TMin, TMax: Double;
begin
  Result := False;
  if (D[F].Kind <> ekFace) or (D[F].Grp <> D[Bore].Grp) or (Length(D[F].Poly) < 3) then Exit;
  TMin := 1E300; TMax := -1E300;
  for I := 0 to High(D[F].Poly) do
  begin
    if not OnBoreWall(D, Bore, D[F].Poly[I], Tol, T) then Exit;
    TMin := Min(TMin, T); TMax := Max(TMax, T);
  end;
  Result := TMax - TMin > Tol;
end;

{ Where the line L0 + t*Dir enters and leaves a flat polygon, as pairs of t.
  Even-odd crossing count, in the polygon's plane. }
procedure LineThroughPoly(const L0, Dir: TP3; const Poly: TP3Array; const N: TP3;
  out Ts: array of Double; out Count: Integer; Tol: Double);
var
  AU, AV, A, B: TP3;
  I, J, K, M: Integer;
  lu, lv, du, dv, pu, pv, qu, qv, eu, ev, Den, T, S, Tmp: Double;
begin
  Count := 0;
  AxesFromNormal(N, AU, AV);
  lu := Dot3(L0, AU); lv := Dot3(L0, AV);
  du := Dot3(Dir, AU); dv := Dot3(Dir, AV);
  M := Length(Poly);
  for I := 0 to M - 1 do
  begin
    A := Poly[I]; B := Poly[(I + 1) mod M];
    pu := Dot3(A, AU); pv := Dot3(A, AV);
    qu := Dot3(B, AU); qv := Dot3(B, AV);
    eu := qu - pu; ev := qv - pv;
    Den := du * ev - dv * eu;
    if Abs(Den) < 1E-12 then
    begin
      { An edge lying on the line counts as inside, both ends as a pair.
        This happens when a flat floor meets a round tunnel exactly at a crease. }
      if Abs((pu - lu) * dv - (pv - lv) * du) < Tol * Max(1, Abs(du) + Abs(dv)) then
      begin
        if Count + 1 >= Length(Ts) then Exit;
        if Abs(du) > Abs(dv) then
        begin
          Ts[Count] := (pu - lu) / du; Ts[Count + 1] := (qu - lu) / du;
        end
        else
        begin
          Ts[Count] := (pv - lv) / dv; Ts[Count + 1] := (qv - lv) / dv;
        end;
        Inc(Count, 2);
      end;
      Continue;
    end;
    { L0 + t Dir = A + s E.  Half open in s, so a vertex on the line is
      counted once, not twice. }
    T := ((pu - lu) * ev - (pv - lv) * eu) / Den;
    S := ((pu - lu) * dv - (pv - lv) * du) / Den;
    if (S < -1E-9) or (S >= 1 - 1E-9) then Continue;
    if Count >= Length(Ts) then Exit;
    Ts[Count] := T;
    Inc(Count);
  end;
  { sorted; an even count pairs up into the stretches inside }
  for I := 0 to Count - 2 do
    for J := I + 1 to Count - 1 do
      if Ts[J] < Ts[I] then begin Tmp := Ts[I]; Ts[I] := Ts[J]; Ts[J] := Tmp; end;
  if Odd(Count) then Count := Count - 1;
end;

{ Where two flat polygons cross: the segments of the line their planes share
  that lie inside both.  Parallel ones do not cross. }
function PolyCross(const PA: TP3Array; NA: TP3; const PB: TP3Array; NB: TP3;
  Tol: Double; out Segs: array of TCut; out NSegs: Integer): Boolean;
var
  Dir, L0: TP3;
  dA, dB, D2, T0, T1: Double;
  TA, TB: array[0..63] of Double;
  CA, CB, I, J: Integer;
begin
  Result := False;
  NSegs := 0;
  NA := Norm3(NA);
  NB := Norm3(NB);
  Dir := Cross3(NA, NB);
  D2 := Dot3(Dir, Dir);
  if D2 < 1E-12 then Exit;
  dA := Dot3(NA, PA[0]);
  dB := Dot3(NB, PB[0]);
  { a point on both planes }
  L0 := Mul3(Add3(Mul3(Cross3(NB, Dir), dA), Mul3(Cross3(Dir, NA), dB)), 1 / D2);
  Dir := Norm3(Dir);
  LineThroughPoly(L0, Dir, PA, NA, TA, CA, Tol);
  LineThroughPoly(L0, Dir, PB, NB, TB, CB, Tol);
  { the intervals inside A are (TA[0],TA[1]), (TA[2],TA[3]) ...; same for B;
    the crossing is where those overlap }
  I := 0;
  while I + 1 < CA do
  begin
    J := 0;
    while J + 1 < CB do
    begin
      T0 := Max(TA[I], TB[J]);
      T1 := Min(TA[I + 1], TB[J + 1]);
      if (T1 - T0 > Tol) and (NSegs < Length(Segs)) then
      begin
        Segs[NSegs].FA := -1;
        Segs[NSegs].FB := -1;
        Segs[NSegs].S0 := Add3(L0, Mul3(Dir, T0));
        Segs[NSegs].S1 := Add3(L0, Mul3(Dir, T1));
        Inc(NSegs);
        Result := True;
      end;
      Inc(J, 2);
    end;
    Inc(I, 2);
  end;
end;

function FaceCross(D: TWorkDoc; FA, FB: Integer; Tol: Double;
  out Segs: array of TCut; out NSegs: Integer): Boolean;
var
  K: Integer;
begin
  Result := PolyCross(D[FA].Poly, D.FaceNormal(FA), D[FB].Poly, D.FaceNormal(FB), Tol, Segs, NSegs);
  for K := 0 to NSegs - 1 do
  begin
    Segs[K].FA := FA;
    Segs[K].FB := FB;
  end;
end;

function BoreLimit(D: TWorkDoc; Face: Integer; Dist: Double): Double;
var
  Nm, Ax: TP3;
  N, I, J, F, Bore, NSeg, K: Integer;
  Side: TP3Array;
  Segs: array[0..15] of TCut;
  Tol, Size, T, Best: Double;
  G: Integer;

  function Along(const P: TP3): Double;
  begin
    Result := Dot3(Sub3(P, D[Face].Poly[0]), Ax);
  end;

begin
  Result := Dist;
  if (Face < 0) or (Face >= D.Live) or (D[Face].Kind <> ekFace) then Exit;
  N := Length(D[Face].Poly);
  if (N < 3) or (Abs(Dist) < 1E-9) then Exit;
  { whose solid: the face's own group, or the wall it lies on }
  G := D[Face].Grp;
  if G = 0 then
    for F := 0 to D.Live - 1 do
      if (D[F].Kind = ekFace) and D[F].Solid and (D[F].Grp <> 0) and
         (Abs(Abs(Dot3(Norm3(D.FaceNormal(F)), Norm3(D.FaceNormal(Face)))) - 1) < 1E-6) and
         (Abs(Dot3(Norm3(D.FaceNormal(F)), Sub3(D[Face].Poly[0], D[F].Poly[0]))) < 1E-6) and
         PointInLoop(InnerPoint(D[Face].Poly, D.FaceNormal(Face)), D[F].Poly, D.FaceNormal(F)) then
      begin
        G := D[F].Grp;
        Break;
      end;
  if G = 0 then Exit;
  Nm := Norm3(D.FaceNormal(Face));
  Ax := Mul3(Nm, Sign(Dist));          { the way the push goes }
  Size := Abs(Dist);
  for I := 0 to N - 1 do Size := Max(Size, hsDrawing.Dist(D[Face].Poly[I], D[Face].Poly[0]));
  Tol := 1E-6 * (1 + Size);
  Best := Abs(Dist);
  SetLength(Side, 4);
  for Bore := 0 to D.Live - 1 do
  begin
    if (D[Bore].Kind <> ekBore) or (D[Bore].Grp <> G) then Continue;
    for F := 0 to D.Live - 1 do
    begin
      if not IsLining(D, Bore, F, Tol) then Continue;
      { the walls of the push, one per edge of the face, out to Dist }
      for I := 0 to N - 1 do
      begin
        J := (I + 1) mod N;
        Side[0] := D[Face].Poly[I];
        Side[1] := D[Face].Poly[J];
        Side[2] := Add3(D[Face].Poly[J], Mul3(Ax, Abs(Dist)));
        Side[3] := Add3(D[Face].Poly[I], Mul3(Ax, Abs(Dist)));
        if PolyCross(Side, Cross3(Sub3(Side[1], Side[0]), Sub3(Side[3], Side[0])),
                     D[F].Poly, D.FaceNormal(F), Tol, Segs, NSeg) then
          for K := 0 to NSeg - 1 do
          begin
            T := Min(Along(Segs[K].S0), Along(Segs[K].S1));
            if (T > Tol) and (T < Best) then Best := T;
          end;
      end;
      { and a wall of the tunnel that the push's own face would land on or
        pass through: its corners inside the swept prism }
      for I := 0 to High(D[F].Poly) do
      begin
        T := Along(D[F].Poly[I]);
        if (T > Tol) and (T < Best) and
           PointInLoop(Sub3(D[F].Poly[I], Mul3(Ax, T)), D[Face].Poly, Nm) then
          Best := T;
      end;
    end;
  end;
  if Best < Abs(Dist) - Tol then Result := Sign(Dist) * Best;
end;

{ The part of segment A-B inside the bore, as fractions from A to B.  The
  bore is treated as a convex prism, clipped against each side and mouth. }
function SegInBore(const Loop: TP3Array; const FarOfFirst: TP3; const A, B: TP3;
  out TA, TB: Double): Boolean;
var
  Ax, N, P0, E, Side: TP3;
  I, M: Integer;
  L: Double;

  { keep the part of [TA,TB] on the inner side of the plane through P0 with
    outward normal N }
  procedure Clip(const P0, N: TP3);
  var
    DA, DB: Double;
  begin
    DA := Dot3(Sub3(A, P0), N);
    DB := Dot3(Sub3(B, P0), N);
    if (DA > 0) and (DB > 0) then begin TA := 1; TB := 0; Exit; end;   { all outside }
    if (DA <= 0) and (DB <= 0) then Exit;                              { all inside }
    if DA > 0 then TA := Max(TA, DA / (DA - DB))                      { A outside, enters }
    else TB := Min(TB, DA / (DA - DB));                               { B outside, leaves }
  end;

begin
  TA := 0; TB := 1;
  Ax := Norm3(Sub3(FarOfFirst, Loop[0]));
  L := Dist(FarOfFirst, Loop[0]);
  M := Length(Loop);
  { the mouths }
  Clip(Loop[0], Mul3(Ax, -1));
  Clip(Add3(Loop[0], Mul3(Ax, L)), Ax);
  { the sides: outward is away from the opening's middle }
  Side := P3(0, 0, 0);
  for I := 0 to M - 1 do Side := Add3(Side, Loop[I]);
  Side := Mul3(Side, 1 / M);
  for I := 0 to M - 1 do
  begin
    P0 := Loop[I];
    E := Sub3(Loop[(I + 1) mod M], P0);
    N := Norm3(Cross3(E, Ax));
    if Dot3(N, Sub3(Side, P0)) > 0 then N := Mul3(N, -1);
    Clip(P0, N);
    if TA >= TB then Exit(False);
  end;
  Result := TB - TA > 1E-9;
end;

{ Cut out the part of every edge of the solid that runs through the bore, so
  no crease is left hanging in the other tunnel's open space. }
procedure TrimLinesInBore(D: TWorkDoc; const Loop: TP3Array; const Far: TP3;
  G: Integer; Tol: Double);
var
  I, N: Integer;
  A, B, PA, PB: TP3;
  TA, TB: Double;
  Ink: TColor;
  Wt: Single;
  Soft: Boolean;
begin
  { The bore is passed by value on purpose: deleting lines shifts every index
    above, so a bore index would point at the wrong entity and crash. }
  if Length(Loop) < 3 then Exit;
  N := D.Live;
  for I := N - 1 downto 0 do
  begin
    if (D[I].Kind <> ekLine) or (D[I].Grp <> G) then Continue;
    A := D[I].A; B := D[I].B;
    if not SegInBore(Loop, Far, A, B, TA, TB) then Continue;
    { only a real stretch, not a touch at a wall }
    if (TB - TA) * Dist(A, B) < Tol * 10 then Continue;
    Ink := D[I].Ink; Wt := D[I].Weight; Soft := D[I].Soft;
    PA := Add3(A, Mul3(Sub3(B, A), TA));
    PB := Add3(A, Mul3(Sub3(B, A), TB));
    D.Delete(I);
    if Dist(A, PA) > Tol * 10 then
    begin
      D.AddLine(A, PA, Ink, Wt, False);
      D.SetGroup(D.Live - 1, G);
      D.SetSoft(D.Live - 1, Soft);
    end;
    if Dist(PB, B) > Tol * 10 then
    begin
      D.AddLine(PB, B, Ink, Wt, False);
      D.SetGroup(D.Live - 1, G);
      D.SetSoft(D.Live - 1, Soft);
    end;
  end;
end;

function CutCrossingBores(D: TWorkDoc; NewBore: Integer): Integer;
type
  TReplace = record
    Face: Integer;
    Pieces: array of TP3Array;
  end;
var
  Other, F, I, J, K, G, NCuts, NSeg, NRep: Integer;
  Tol, Size: Double;
  LA, LB: array of Integer;
  Cuts: array of TCut;
  Segs: array[0..15] of TCut;
  Reps: array of TReplace;
  Tmp: TReplace;
  Crossed, CrossedOrd: array of Integer;
  BoreA, BoreB, NewBoreOrd: Integer;
  LoopA, LoopB: TP3Array;
  FarA, FarB: TP3;
  FN: TP3;
  Ink: TColor;

  procedure Note(F: Integer; var L: array of Integer; var N: Integer);
  begin
    if N >= Length(L) then Exit;
    L[N] := F;
    Inc(N);
  end;

  { every corner of the wall inside the bore or on its surface, and its
    middle inside: the whole wall is in the void }
  function WhollyInside(F, Against: Integer): Boolean;
  var
    I: Integer;
  begin
    Result := InsideBore(D, Against, InnerPoint(D[F].Poly, D.FaceNormal(F)), Tol);
    if not Result then Exit;
    for I := 0 to High(D[F].Poly) do
      if not InsideBore(D, Against, D[F].Poly[I], -1E-9) then Exit(False);
  end;

  { divide wall F by the cuts across it, dropping what lies in bore Against }
  procedure Divide(F, Against: Integer);
  var
    S: TSegArray;
    R: TRegionArray;
    NS, I, M, Kept: Integer;
    Drop: array of Boolean;
    Mid: TP3;
  begin
    M := Length(D[F].Poly);
    NS := 0;
    SetLength(S, M + NCuts);
    for I := 0 to M - 1 do
    begin
      S[NS].A := D[F].Poly[I];
      S[NS].B := D[F].Poly[(I + 1) mod M];
      Inc(NS);
    end;
    for I := 0 to NCuts - 1 do
      if (Cuts[I].FA = F) or (Cuts[I].FB = F) then
      begin
        S[NS].A := Cuts[I].S0;
        S[NS].B := Cuts[I].S1;
        Inc(NS);
      end;
    if NS = M then
    begin
      { Nothing crosses this wall.  It is either clear of the other bore or
        wholly inside it (a small round-tunnel facet in a square opening),
        and then it all goes. }
      if WhollyInside(F, Against) then
      begin
        SetLength(Reps, NRep + 1);
        Reps[NRep].Face := F;
        Reps[NRep].Pieces := nil;
        Inc(NRep);
      end;
      Exit;
    end;
    SetLength(S, NS);
    R := BuildRegions(S);
    if Length(R) < 2 then
    begin
      { crossed only at a corner or along an edge, so nothing was divided:
        the wall is either clear of the other bore or wholly inside it }
      if WhollyInside(F, Against) then
      begin
        SetLength(Reps, NRep + 1);
        Reps[NRep].Face := F;
        Reps[NRep].Pieces := nil;
        Inc(NRep);
      end;
      Exit;
    end;
    SetLength(Drop, Length(R));
    Kept := 0;
    for I := 0 to High(R) do
    begin
      Mid := InnerPoint(R[I].Outer, R[I].Normal);
      Drop[I] := InsideBore(D, Against, Mid, Tol);
      if not Drop[I] then Inc(Kept);
    end;
    if Kept = Length(R) then Exit;       { crossed, but nothing of it is in the other bore }
    SetLength(Reps, NRep + 1);
    Reps[NRep].Face := F;
    SetLength(Reps[NRep].Pieces, Kept);
    Kept := 0;
    for I := 0 to High(R) do
      if not Drop[I] then
      begin
        Reps[NRep].Pieces[Kept] := Copy(R[I].Outer, 0, Length(R[I].Outer));
        Inc(Kept);
      end;
    Inc(NRep);
  end;

begin
  Result := 0;
  if (NewBore < 0) or (NewBore >= D.Live) or (D[NewBore].Kind <> ekBore) then Exit;
  G := D[NewBore].Grp;
  Size := BoreLen(D, NewBore);
  for I := 0 to High(D[NewBore].Poly) do
    Size := Max(Size, Dist(D[NewBore].Poly[I], D[NewBore].Poly[0]));
  Tol := 1E-6 * (1 + Size);
  NRep := 0;
  Reps := nil;
  Crossed := nil;
  CrossedOrd := nil;
  NewBoreOrd := 0;
  for I := 0 to NewBore - 1 do
    if D[I].Kind = ekBore then Inc(NewBoreOrd);

  for Other := 0 to D.Live - 1 do
  begin
    if (Other = NewBore) or (D[Other].Kind <> ekBore) or (D[Other].Grp <> G) then Continue;

    { the walls of each }
    SetLength(LA, D.Live); SetLength(LB, D.Live);
    I := 0; J := 0;
    for F := 0 to D.Live - 1 do
    begin
      if IsLining(D, Other, F, Tol) then Note(F, LA, I);
      if IsLining(D, NewBore, F, Tol) then Note(F, LB, J);
    end;
    SetLength(LA, I); SetLength(LB, J);
    if (Length(LA) = 0) or (Length(LB) = 0) then Continue;

    { every crossing between a wall of one and a wall of the other }
    NCuts := 0;
    SetLength(Cuts, 0);
    for I := 0 to High(LA) do
      for J := 0 to High(LB) do
        if FaceCross(D, LA[I], LB[J], Tol, Segs, NSeg) then
          for K := 0 to NSeg - 1 do
          begin
            SetLength(Cuts, NCuts + 1);
            Cuts[NCuts] := Segs[K];
            Inc(NCuts);
          end;
    if NCuts = 0 then Continue;

    for I := 0 to High(LA) do Divide(LA[I], NewBore);
    for I := 0 to High(LB) do Divide(LB[I], Other);
    SetLength(Crossed, Length(Crossed) + 1);
    Crossed[High(Crossed)] := Other;
    SetLength(CrossedOrd, Length(Crossed));
    CrossedOrd[High(CrossedOrd)] := 0;
    for I := 0 to Other - 1 do
      if D[I].Kind = ekBore then Inc(CrossedOrd[High(CrossedOrd)]);

    { the crossings are edges now, so they draw }
    for I := 0 to NCuts - 1 do
      if not D.HasLine(Cuts[I].S0, Cuts[I].S1) then
      begin
        D.AddLine(Cuts[I].S0, Cuts[I].S1, D[LA[0]].Ink, 1, False);
        D.SetGroup(D.Live - 1, G);
      end;
  end;

  { replace the divided walls by their pieces - highest index first, so the
    numbers below do not shift; each piece faces the way its wall faced }
  for I := 0 to NRep - 2 do
    for J := 0 to NRep - 2 - I do
      if Reps[J].Face < Reps[J + 1].Face then
      begin
        Tmp := Reps[J];
        Reps[J] := Reps[J + 1];
        Reps[J + 1] := Tmp;
      end;
  for I := 0 to NRep - 1 do
  begin
    F := Reps[I].Face;
    FN := D.FaceNormal(F);
    Ink := D[F].Ink;
    D.Delete(F);
    for J := 0 to High(Reps[I].Pieces) do
    begin
      D.AddFaceRaw(Reps[I].Pieces[J], Ink, True);
      D.SetFaceGroup(D.Live - 1, G);
      if Dot3(D.FaceNormal(D.Live - 1), FN) < 0 then D.FlipFace(D.Live - 1);
    end;
    Inc(Result);
  end;

  { The edges.  Deleting walls has moved every index, so the bores are
    found again: they were never deleted, and they keep their order. }
  if Length(Crossed) > 0 then
  begin
    BoreB := -1;
    K := 0;
    for I := 0 to D.Live - 1 do
      if D[I].Kind = ekBore then
      begin
        if K = NewBoreOrd then BoreB := I;
        Inc(K);
      end;
    if BoreB >= 0 then
      for J := 0 to High(Crossed) do
      begin
        BoreA := -1;
        K := 0;
        for I := 0 to D.Live - 1 do
          if D[I].Kind = ekBore then
          begin
            if K = CrossedOrd[J] then BoreA := I;
            Inc(K);
          end;
        if BoreA < 0 then Continue;
        { both bores by value before either trim touches the list }
        LoopA := Copy(D[BoreA].Poly, 0, Length(D[BoreA].Poly)); FarA := D[BoreA].B;
        LoopB := Copy(D[BoreB].Poly, 0, Length(D[BoreB].Poly)); FarB := D[BoreB].B;
        TrimLinesInBore(D, LoopB, FarB, G, Tol);   { the old tunnel's creases, where the new one runs }
        TrimLinesInBore(D, LoopA, FarA, G, Tol);   { and the new one's, where the old one runs }
      end;
  end;
end;

end.

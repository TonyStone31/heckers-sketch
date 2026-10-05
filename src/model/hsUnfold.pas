unit hsUnfold;

{ Flat patterns for sheet metal.  The faces are unfolded across shared
  edges along a spanning tree: kept edges become bends, the rest cuts, and
  every edge keeps its length so the pattern fits.  Only developable shapes
  (planes, cylinders, cones) come out right.  Seam and bend allowance,
  grain and nesting are not handled here. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, hsDrawing, hsDxf;

type
  TIntArray = array of Integer;

  { A point on the sheet; its own type so this unit needs no widget set. }
  TFlatPt = record
    X, Y: Double;
  end;

  { What an edge of the pattern turns out to be. }
  TFoldKind = (
    fkCut,     // nothing joined here: it gets cut
    fkBend,    // joined, and the metal turns: it gets a bend line
    fkNotch    // a nick at the end of a bend, so the brake can be set to it
  );

const
  { Feet (a quarter inch).  Leg length of the V cut at each end of a fold,
    which the brake is lined up on. }
  NOTCH_LEN = 0.25 / 12;

type
  TFlatEdge = record
    AX, AY, BX, BY: Double;   // where it lies on the sheet
    Kind: TFoldKind;
    Angle: Double;            // how far the metal turns, radians, signed
  end;

  { One face of the model laid flat, same shape and size. }
  TFlatFace = record
    P: array of TFlatPt;
    { openings in the panel, laid flat the same way, so they get cut too }
    Holes: array of array of TFlatPt;
    Face: Integer;            // which face of the document it came from
  end;

  TFlatPattern = record
    Faces: array of TFlatFace;
    Edges: array of TFlatEdge;
    MinX, MinY, MaxX, MaxY: Double;   // the sheet it needs
    Overlaps: Boolean;                // it folds back onto itself
    Laid: Integer;                    // panels placed
    Total: Integer;                   // panels asked for
    Ok: Boolean;
    Why: string;
  end;

{ Lay the given faces of a document out flat.  Pass every face of one piece. }
function Unfold(const Doc: TWorkDoc; const Faces: array of Integer;
  Tol: Double = 1E-6): TFlatPattern;

{ Every face belonging to the same solid as the one given, so a click on any
  part of a piece lays the whole piece out. }
function SolidFaces(const Doc: TWorkDoc; Index: Integer): TIntArray;

{ The pattern as a DXF a table can cut: CUT, BEND and NOTCH on layers of
  their own, in inches or millimeters according to the drawing's units. }
procedure PatternToDxf(const Pat: TFlatPattern; U: TUnitSystem; L: TStrings);

implementation

type
  TPanel = record
    Doc: Integer;                 // index in the document
    V: TIntArray;                 // welded vertex numbers, in order
    L: array of TFlatPt;          // the panel in its own plane
    LH: array of array of TFlatPt;  // its openings, in that same plane
    Q: array of TFlatPt;          // and where it ended up on the sheet
    Nm: TP3;
    Placed: Boolean;
  end;

  TEdgeRef = record
    A, B: Integer;
    F: array[0..1] of Integer;    // the panels that share it
    N: Integer;
  end;

function SolidFaces(const Doc: TWorkDoc; Index: Integer): TIntArray;
var
  I, N, G: Integer;
begin
  Result := nil;
  if (Index < 0) or (Index >= Doc.Live) then Exit;
  G := Doc[Index].Grp;
  N := 0;
  SetLength(Result, Doc.Live);
  for I := 0 to Doc.Live - 1 do
    if (Doc[I].Kind = ekFace) and (Length(Doc[I].Poly) >= 3) then
      { Grp 0 is loose drawing, so a loose face is a piece on its own. }
      if ((G <> 0) and (Doc[I].Grp = G)) or ((G = 0) and (I = Index)) then
      begin
        Result[N] := I;
        Inc(N);
      end;
  SetLength(Result, N);
end;

procedure PatternToDxf(const Pat: TFlatPattern; U: TUnitSystem; L: TStrings);
var
  W: TDxfWriter;
  I: Integer;
  K: Double;
  Lay: string;
begin
  { feet to inches, or meters to millimeters - a table wants shop units }
  if U = usImperial then K := 12 else K := 1000;
  W := TDxfWriter.Create;
  try
    { colors are AutoCAD's index: 7 white/black, 1 red, 5 blue }
    W.Layer('CUT', 7);
    W.Layer('BEND', 5, True);
    W.Layer('NOTCH', 1);
    for I := 0 to High(Pat.Edges) do
    begin
      case Pat.Edges[I].Kind of
        fkBend:  Lay := 'BEND';
        fkNotch: Lay := 'NOTCH';
      else       Lay := 'CUT';
      end;
      W.Line(Lay, Pat.Edges[I].AX * K, Pat.Edges[I].AY * K, 0,
                  Pat.Edges[I].BX * K, Pat.Edges[I].BY * K, 0);
    end;
    W.SaveTo(L, U = usImperial);
  finally
    W.Free;
  end;
end;

{ Do two laid-out panels overlap?  Both are shrunk slightly toward their
  middles first so panels touching along a fold do not count.  Separating
  axis test on every edge of both. }
function PanelsOverlap(const A, B: TFlatFace): Boolean;
const
  SHRINK = 0.02;
var
  P, Q: array of TFlatPt;
  I, J, K, N: Integer;
  EX, EY, D, MinA, MaxA, MinB, MaxB: Double;

  procedure Pull(const S: TFlatFace; out R: array of TFlatPt);
  var
    M: Integer;
    MX, MY: Double;
  begin
    MX := 0; MY := 0;
    for M := 0 to High(S.P) do
    begin
      MX := MX + S.P[M].X;
      MY := MY + S.P[M].Y;
    end;
    MX := MX / Length(S.P);
    MY := MY / Length(S.P);
    for M := 0 to High(S.P) do
    begin
      R[M].X := S.P[M].X + (MX - S.P[M].X) * SHRINK;
      R[M].Y := S.P[M].Y + (MY - S.P[M].Y) * SHRINK;
    end;
  end;

begin
  Result := False;
  if (Length(A.P) < 3) or (Length(B.P) < 3) then Exit;
  SetLength(P, Length(A.P));
  SetLength(Q, Length(B.P));
  Pull(A, P);
  Pull(B, Q);
  for K := 0 to 1 do
  begin
    if K = 0 then N := High(P) else N := High(Q);
    for I := 0 to N do
    begin
      if K = 0 then
      begin
        EX := P[(I + 1) mod Length(P)].Y - P[I].Y;
        EY := P[I].X - P[(I + 1) mod Length(P)].X;
      end
      else
      begin
        EX := Q[(I + 1) mod Length(Q)].Y - Q[I].Y;
        EY := Q[I].X - Q[(I + 1) mod Length(Q)].X;
      end;
      MinA := 1E30; MaxA := -1E30; MinB := 1E30; MaxB := -1E30;
      for J := 0 to High(P) do
      begin
        D := P[J].X * EX + P[J].Y * EY;
        MinA := Min(MinA, D); MaxA := Max(MaxA, D);
      end;
      for J := 0 to High(Q) do
      begin
        D := Q[J].X * EX + Q[J].Y * EY;
        MinB := Min(MinB, D); MaxB := Max(MaxB, D);
      end;
      if (MaxA <= MinB) or (MaxB <= MinA) then Exit(False);
    end;
  end;
  Result := True;
end;

function Unfold(const Doc: TWorkDoc; const Faces: array of Integer;
  Tol: Double): TFlatPattern;
var
  Pan: array of TPanel;
  Verts: array of TP3;
  Edges: array of TEdgeRef;
  NP, NV, NE: Integer;
  Order, Parent: TIntArray;
  I, J, K, F, H, Head, Tail, T, O, E, Ai, Bi, NE2: Integer;
  DX, DY, PX, PY, Len: Double;
  OnEdge: Boolean;
  U, V, Nm, D3: TP3;
  Poly: TP3Array;
  Dot, Ang, Sx, Sy, Cs, Sn, LenL, LenP: Double;
  PA, PB, LA, LB, Inside: TFlatPt;

  function WeldVertex(const Q: TP3): Integer;
  var
    M2: Integer;
  begin
    for M2 := 0 to NV - 1 do
      if (Abs(Verts[M2].X - Q.X) < Tol) and (Abs(Verts[M2].Y - Q.Y) < Tol) and
         (Abs(Verts[M2].Z - Q.Z) < Tol) then Exit(M2);
    if NV >= Length(Verts) then SetLength(Verts, Max(16, NV * 2));
    Verts[NV] := Q;
    Result := NV;
    Inc(NV);
  end;

  function FindEdge(A, B: Integer): Integer;
  var
    M2: Integer;
  begin
    for M2 := 0 to NE - 1 do
      if ((Edges[M2].A = A) and (Edges[M2].B = B)) or
         ((Edges[M2].A = B) and (Edges[M2].B = A)) then Exit(M2);
    Result := -1;
  end;

  procedure NoteEdge(A, B, Panel: Integer);
  var
    M2: Integer;
  begin
    M2 := FindEdge(A, B);
    if M2 < 0 then
    begin
      if NE >= Length(Edges) then SetLength(Edges, Max(32, NE * 2));
      M2 := NE;
      Edges[M2].A := A;
      Edges[M2].B := B;
      Edges[M2].N := 0;
      Inc(NE);
    end;
    if Edges[M2].N < 2 then
    begin
      Edges[M2].F[Edges[M2].N] := Panel;
      Inc(Edges[M2].N);
    end;
  end;

  function CornerOf(Panel, Vtx: Integer): Integer;
  var
    M2: Integer;
  begin
    Result := -1;
    for M2 := 0 to High(Pan[Panel].V) do
      if Pan[Panel].V[M2] = Vtx then Exit(M2);
  end;

  function Mid(const S: array of TFlatPt): TFlatPt;
  var
    M2: Integer;
  begin
    Result.X := 0;
    Result.Y := 0;
    for M2 := 0 to High(S) do
    begin
      Result.X := Result.X + S[M2].X;
      Result.Y := Result.Y + S[M2].Y;
    end;
    Result.X := Result.X / Length(S);
    Result.Y := Result.Y / Length(S);
  end;

  { Map a point from the panel's plane (L) to the sheet (Q).  The move is
    rigid: two corners fix the turn and shift, and the third tells whether
    the panel was also mirrored. }
  function Carried(const L, Q: array of TFlatPt; const X: TFlatPt): TFlatPt;
  var
    EX, EY, FX, FY, LenE, LenF, A, B, Sg: Double;
    T: TFlatPt;
  begin
    Result := X;
    if (Length(L) < 2) or (Length(Q) < 2) then Exit;
    EX := L[1].X - L[0].X; EY := L[1].Y - L[0].Y;
    FX := Q[1].X - Q[0].X; FY := Q[1].Y - Q[0].Y;
    LenE := Sqrt(EX * EX + EY * EY);
    LenF := Sqrt(FX * FX + FY * FY);
    if (LenE < 1E-12) or (LenF < 1E-12) then Exit;
    EX := EX / LenE; EY := EY / LenE;
    FX := FX / LenF; FY := FY / LenF;
    Sg := 1;
    if Length(L) >= 3 then
    begin
      { the third corner, carried as if there were no mirror }
      A := (L[2].X - L[0].X) * EX + (L[2].Y - L[0].Y) * EY;
      B := (L[2].X - L[0].X) * (-EY) + (L[2].Y - L[0].Y) * EX;
      T.X := Q[0].X + A * FX + B * (-FY);
      T.Y := Q[0].Y + A * FY + B * FX;
      if Sqr(T.X - Q[2].X) + Sqr(T.Y - Q[2].Y) > 1E-12 then Sg := -1;
    end;
    A := (X.X - L[0].X) * EX + (X.Y - L[0].Y) * EY;
    B := ((X.X - L[0].X) * (-EY) + (X.Y - L[0].Y) * EX) * Sg;
    Result.X := Q[0].X + A * FX + B * (-FY);
    Result.Y := Q[0].Y + A * FY + B * FX;
  end;

  { Which side of the line PA..PB a point falls. }
  function Side(const PA2, PB2, Pt: TFlatPt): Double;
  begin
    Result := (PB2.X - PA2.X) * (Pt.Y - PA2.Y) -
              (PB2.Y - PA2.Y) * (Pt.X - PA2.X);
  end;

begin
  Result := Default(TFlatPattern);
  NP := 0; NV := 0; NE := 0;
  SetLength(Pan, Max(4, Length(Faces)));
  SetLength(Verts, 64);
  SetLength(Edges, 128);

  { --- every face, in its own plane ---------------------------------- }
  for I := 0 to High(Faces) do
  begin
    F := Faces[I];
    if (F < 0) or (F >= Doc.Live) then Continue;
    if Doc[F].Kind <> ekFace then Continue;
    Poly := Doc[F].Poly;
    if Length(Poly) < 3 then Continue;
    if NP >= Length(Pan) then SetLength(Pan, NP * 2);
    Nm := Doc.FaceNormal(F);
    AxesFromNormal(Nm, U, V);
    Pan[NP].Doc := F;
    Pan[NP].Nm := Nm;
    Pan[NP].Placed := False;
    SetLength(Pan[NP].V, Length(Poly));
    SetLength(Pan[NP].L, Length(Poly));
    SetLength(Pan[NP].Q, Length(Poly));
    for J := 0 to High(Poly) do
    begin
      Pan[NP].V[J] := WeldVertex(Poly[J]);
      D3 := Sub3(Poly[J], Poly[0]);
      Pan[NP].L[J].X := Dot3(D3, U);
      Pan[NP].L[J].Y := Dot3(D3, V);
    end;
    { openings use the same basis and origin as the panel }
    SetLength(Pan[NP].LH, Length(Doc[F].Holes));
    for H := 0 to High(Doc[F].Holes) do
    begin
      SetLength(Pan[NP].LH[H], Length(Doc[F].Holes[H]));
      for J := 0 to High(Doc[F].Holes[H]) do
      begin
        D3 := Sub3(Doc[F].Holes[H][J], Poly[0]);
        Pan[NP].LH[H][J].X := Dot3(D3, U);
        Pan[NP].LH[H][J].Y := Dot3(D3, V);
      end;
    end;
    Inc(NP);
  end;
  Result.Total := NP;
  if NP = 0 then
  begin
    Result.Why := 'there are no faces here to lay out';
    Exit;
  end;

  { --- which panel touches which -------------------------------------- }
  for I := 0 to NP - 1 do
    for J := 0 to High(Pan[I].V) do
      NoteEdge(Pan[I].V[J], Pan[I].V[(J + 1) mod Length(Pan[I].V)], I);

  { --- walk the piece, unfolding as we go ----------------------------- }
  SetLength(Order, NP);
  SetLength(Parent, NP);
  for I := 0 to NP - 1 do Parent[I] := -1;

  Pan[0].Q := Copy(Pan[0].L);
  Pan[0].Placed := True;
  Order[0] := 0;
  Head := 0; Tail := 1;

  while Head < Tail do
  begin
    T := Order[Head];
    Inc(Head);
    for J := 0 to High(Pan[T].V) do
    begin
      E := FindEdge(Pan[T].V[J], Pan[T].V[(J + 1) mod Length(Pan[T].V)]);
      if (E < 0) or (Edges[E].N < 2) then Continue;
      if Edges[E].F[0] = T then O := Edges[E].F[1] else O := Edges[E].F[0];
      if (O < 0) or (O >= NP) or Pan[O].Placed then Continue;

      Ai := CornerOf(T, Edges[E].A);
      Bi := CornerOf(T, Edges[E].B);
      if (Ai < 0) or (Bi < 0) then Continue;
      PA := Pan[T].Q[Ai];
      PB := Pan[T].Q[Bi];

      Ai := CornerOf(O, Edges[E].A);
      Bi := CornerOf(O, Edges[E].B);
      if (Ai < 0) or (Bi < 0) then Continue;
      LA := Pan[O].L[Ai];
      LB := Pan[O].L[Bi];

      { Turn and shift the panel so the shared edge lands on the parent's
        copy of it.  It is the same edge, so no stretching is needed. }
      LenL := Sqrt(Sqr(LB.X - LA.X) + Sqr(LB.Y - LA.Y));
      LenP := Sqrt(Sqr(PB.X - PA.X) + Sqr(PB.Y - PA.Y));
      if (LenL < 1E-12) or (LenP < 1E-12) then Continue;
      Cs := ((LB.X - LA.X) * (PB.X - PA.X) +
             (LB.Y - LA.Y) * (PB.Y - PA.Y)) / (LenL * LenP);
      Sn := ((LB.X - LA.X) * (PB.Y - PA.Y) -
             (LB.Y - LA.Y) * (PB.X - PA.X)) / (LenL * LenP);

      for K := 0 to High(Pan[O].L) do
      begin
        Sx := Pan[O].L[K].X - LA.X;
        Sy := Pan[O].L[K].Y - LA.Y;
        Pan[O].Q[K].X := PA.X + Sx * Cs - Sy * Sn;
        Pan[O].Q[K].Y := PA.Y + Sx * Sn + Sy * Cs;
      end;

      { It must open away from the parent: if both middles are on the same
        side of the shared edge, mirror the new panel across it. }
      Inside := Mid(Pan[T].Q);
      if Side(PA, PB, Mid(Pan[O].Q)) * Side(PA, PB, Inside) > 0 then
        for K := 0 to High(Pan[O].Q) do
        begin
          Sx := Pan[O].Q[K].X - PA.X;
          Sy := Pan[O].Q[K].Y - PA.Y;
          Cs := (PB.X - PA.X) / LenP;
          Sn := (PB.Y - PA.Y) / LenP;
          { reflect in the line through PA along (Cs, Sn) }
          Pan[O].Q[K].X := PA.X + Sx * (Cs * Cs - Sn * Sn) + Sy * (2 * Cs * Sn);
          Pan[O].Q[K].Y := PA.Y + Sx * (2 * Cs * Sn) - Sy * (Cs * Cs - Sn * Sn);
        end;

      Pan[O].Placed := True;
      Parent[O] := T;
      Order[Tail] := O;
      Inc(Tail);
    end;
  end;

  { --- hand back the panels ------------------------------------------- }
  Result.Laid := 0;
  SetLength(Result.Faces, NP);
  for I := 0 to NP - 1 do
    if Pan[I].Placed then
    begin
      Result.Faces[Result.Laid].Face := Pan[I].Doc;
      SetLength(Result.Faces[Result.Laid].P, Length(Pan[I].Q));
      for J := 0 to High(Pan[I].Q) do
        Result.Faces[Result.Laid].P[J] := Pan[I].Q[J];
      { The openings follow the panel.  No transform was kept, so Carried
        reads it back off the corners. }
      SetLength(Result.Faces[Result.Laid].Holes, Length(Pan[I].LH));
      for H := 0 to High(Pan[I].LH) do
      begin
        SetLength(Result.Faces[Result.Laid].Holes[H], Length(Pan[I].LH[H]));
        for J := 0 to High(Pan[I].LH[H]) do
          Result.Faces[Result.Laid].Holes[H][J] :=
            Carried(Pan[I].L, Pan[I].Q, Pan[I].LH[H][J]);
      end;
      Inc(Result.Laid);
    end;
  SetLength(Result.Faces, Result.Laid);

  { --- and say what every edge is ------------------------------------- }
  SetLength(Result.Edges, NE);
  K := 0;
  for I := 0 to NE - 1 do
  begin
    T := Edges[I].F[0];
    if (T < 0) or (T >= NP) or not Pan[T].Placed then Continue;
    Ai := CornerOf(T, Edges[I].A);
    Bi := CornerOf(T, Edges[I].B);
    if (Ai < 0) or (Bi < 0) then Continue;
    Result.Edges[K].AX := Pan[T].Q[Ai].X;
    Result.Edges[K].AY := Pan[T].Q[Ai].Y;
    Result.Edges[K].BX := Pan[T].Q[Bi].X;
    Result.Edges[K].BY := Pan[T].Q[Bi].Y;
    Result.Edges[K].Angle := 0;
    Result.Edges[K].Kind := fkCut;
    if Edges[I].N = 2 then
    begin
      O := Edges[I].F[1];
      if O = T then O := Edges[I].F[0];
      Dot := EnsureRange(Dot3(Pan[T].Nm, Pan[O].Nm), -1, 1);
      Ang := ArcCos(Dot);
      D3 := Sub3(Verts[Edges[I].B], Verts[Edges[I].A]);
      if Dot3(Cross3(Pan[T].Nm, Pan[O].Nm), D3) < 0 then Ang := -Ang;
      Result.Edges[K].Angle := Ang;
      if (Parent[O] = T) or (Parent[T] = O) then
        Result.Edges[K].Kind := fkBend;
    end;
    Inc(K);
  end;
  { every edge of an opening is a cut }
  for I := 0 to High(Result.Faces) do
    for H := 0 to High(Result.Faces[I].Holes) do
      for J := 0 to High(Result.Faces[I].Holes[H]) do
      begin
        if K >= Length(Result.Edges) then
          SetLength(Result.Edges, Max(16, K * 2));
        O := (J + 1) mod Length(Result.Faces[I].Holes[H]);
        Result.Edges[K].AX := Result.Faces[I].Holes[H][J].X;
        Result.Edges[K].AY := Result.Faces[I].Holes[H][J].Y;
        Result.Edges[K].BX := Result.Faces[I].Holes[H][O].X;
        Result.Edges[K].BY := Result.Faces[I].Holes[H][O].Y;
        Result.Edges[K].Angle := 0;
        Result.Edges[K].Kind := fkCut;
        Inc(K);
      end;
  { --- notches, so the sheet can be set in the brake ------------------
    A small V at each end of a fold, pointing along it.  Only ends on the
    sheet's edge get one; a fold ending inside the sheet has nothing to nick. }
  NE2 := K;
  for I := 0 to NE2 - 1 do
  begin
    if Result.Edges[I].Kind <> fkBend then Continue;
    DX := Result.Edges[I].BX - Result.Edges[I].AX;
    DY := Result.Edges[I].BY - Result.Edges[I].AY;
    Len := Sqrt(DX * DX + DY * DY);
    if Len < 1E-9 then Continue;
    DX := DX / Len; DY := DY / Len;
    for E := 0 to 1 do
    begin
      if E = 0 then begin PX := Result.Edges[I].AX; PY := Result.Edges[I].AY; end
      else begin PX := Result.Edges[I].BX; PY := Result.Edges[I].BY; DX := -DX; DY := -DY; end;
      { on the sheet's edge means: an end of some cut is right here }
      OnEdge := False;
      for J := 0 to NE2 - 1 do
        if Result.Edges[J].Kind = fkCut then
          if (Sqr(Result.Edges[J].AX - PX) + Sqr(Result.Edges[J].AY - PY) < 1E-12) or
             (Sqr(Result.Edges[J].BX - PX) + Sqr(Result.Edges[J].BY - PY) < 1E-12) then
          begin
            OnEdge := True;
            Break;
          end;
      if not OnEdge then Continue;
      { the V: two legs from the edge point, in along the fold and a little
        to either side }
      for J := 0 to 1 do
      begin
        if K >= Length(Result.Edges) then SetLength(Result.Edges, Max(16, K * 2));
        Result.Edges[K].AX := PX;
        Result.Edges[K].AY := PY;
        if J = 0 then
        begin
          Result.Edges[K].BX := PX + DX * NOTCH_LEN - DY * NOTCH_LEN * 0.5;
          Result.Edges[K].BY := PY + DY * NOTCH_LEN + DX * NOTCH_LEN * 0.5;
        end
        else
        begin
          Result.Edges[K].BX := PX + DX * NOTCH_LEN + DY * NOTCH_LEN * 0.5;
          Result.Edges[K].BY := PY + DY * NOTCH_LEN - DX * NOTCH_LEN * 0.5;
        end;
        Result.Edges[K].Angle := 0;
        Result.Edges[K].Kind := fkNotch;
        Inc(K);
      end;
    end;
  end;
  SetLength(Result.Edges, K);

  { --- the sheet it needs --------------------------------------------- }
  Result.MinX := 1E30; Result.MinY := 1E30;
  Result.MaxX := -1E30; Result.MaxY := -1E30;
  for I := 0 to High(Result.Faces) do
    for J := 0 to High(Result.Faces[I].P) do
    begin
      Result.MinX := Min(Result.MinX, Result.Faces[I].P[J].X);
      Result.MaxX := Max(Result.MaxX, Result.Faces[I].P[J].X);
      Result.MinY := Min(Result.MinY, Result.Faces[I].P[J].Y);
      Result.MaxY := Max(Result.MaxY, Result.Faces[I].P[J].Y);
    end;

  { --- does it fold back onto itself? --------------------------------- }
  Result.Overlaps := False;
  for I := 0 to High(Result.Faces) do
  begin
    for J := I + 1 to High(Result.Faces) do
      if PanelsOverlap(Result.Faces[I], Result.Faces[J]) then
      begin
        Result.Overlaps := True;
        Break;
      end;
    if Result.Overlaps then Break;
  end;

  Result.Ok := True;
  if Result.Laid < Result.Total then
    Result.Why := 'some of it is not joined to the rest';
end;

end.

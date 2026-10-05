{ hsMainForm - small helpers.  Part of TMainForm; included by hsMainForm.pas }

{ ======================================================================== }
{ small helpers                                                             }
{ ======================================================================== }

function TMainForm.Theme: TTheme;
begin
  Result := Themes[FThemeIdx];
end;

function TMainForm.CurScale: TDrawScale;
begin
  Result := ScaleTable(FD.Units, FD.ScaleIdx);
end;

{ Pixels per world unit on screen.  The drawing scale sets the true size and
  FD.Zoom only magnifies it, so zooming never changes what prints. }
function TMainForm.Ppu: Double;
begin
  Result := PixelsPerUnit(FD.Units, CurScale, Screen.PixelsPerInch) * FD.Zoom;
end;

function TMainForm.SnapStep: Double;
begin
  Result := SnapValue(FD.Units, FD.SnapIdx);
end;

function TMainForm.Proj: TProjector;
begin
  Result.Kind := FD.View;
  Result.Ppu := Ppu;
  Result.OX := FD.ViewX;
  Result.OY := FD.ViewY;
  Result.Az := FD.Az;
  Result.El := FD.El;
end;

function TMainForm.ScreenOf(const P: TP3): TPointF;
begin
  Result := Project(Proj, P);
end;

function TMainForm.WorldAt(SX, SY: Double): TP3;
var
  Base: TP3;
begin
  Base := FCur;
  { A locked plane is pinned to where the shape started, not to where the
    cursor has wandered.  If it followed the cursor, one inference off the
    plane would move it and the outline would never close into a face. }
  if FPlaneHeld and (FStage > 0) then Base := FP1;
  { In a plan with a cut, the bottom of the slice is the drawing plane: set
    it to 9'-0" and you are drawing on the second story. }
  if (FD.View = vkPlan) and FD.SliceOn then Base.Z := FD.SliceLo;
  Result := Unproject(Proj, SX, SY, FD.Plane, Base);
end;

{ The four corners of the rectangle with A and B at opposite corners, in the
  working plane.  The third coordinate stays at A's, which keeps it flat and
  gives its face a usable normal. }
function RectCorners(const A, B: TP3; Pl: TPlane): TP3Array;
var
  FO, FU, FV, FN, D: TP3;
  Du, Dv: Double;
begin
  Result := nil;
  SetLength(Result, 4);
  if Pl = plFree then
  begin
    { laid out along the plane's own two directions, not world axes, so a
      rectangle can be drawn on a roof }
    GetFreePlane(FO, FU, FV, FN);
    D := P3(B.X - A.X, B.Y - A.Y, B.Z - A.Z);
    Du := D.X * FU.X + D.Y * FU.Y + D.Z * FU.Z;
    Dv := D.X * FV.X + D.Y * FV.Y + D.Z * FV.Z;
    Result[0] := A;
    Result[1] := P3(A.X + FU.X * Du, A.Y + FU.Y * Du, A.Z + FU.Z * Du);
    Result[2] := P3(Result[1].X + FV.X * Dv, Result[1].Y + FV.Y * Dv,
                    Result[1].Z + FV.Z * Dv);
    Result[3] := P3(A.X + FV.X * Dv, A.Y + FV.Y * Dv, A.Z + FV.Z * Dv);
    Exit;
  end;
  case Pl of
    plXZ:
      begin
        Result[0] := P3(A.X, A.Y, A.Z);
        Result[1] := P3(B.X, A.Y, A.Z);
        Result[2] := P3(B.X, A.Y, B.Z);
        Result[3] := P3(A.X, A.Y, B.Z);
      end;
    plYZ:
      begin
        Result[0] := P3(A.X, A.Y, A.Z);
        Result[1] := P3(A.X, B.Y, A.Z);
        Result[2] := P3(A.X, B.Y, B.Z);
        Result[3] := P3(A.X, A.Y, B.Z);
      end;
  else
    begin
      Result[0] := P3(A.X, A.Y, A.Z);
      Result[1] := P3(B.X, A.Y, A.Z);
      Result[2] := P3(B.X, B.Y, A.Z);
      Result[3] := P3(A.X, B.Y, A.Z);
    end;
  end;
end;

{ the two side lengths of that rectangle, in the plane's own order }
procedure RectSides(const A, B: TP3; Pl: TPlane; out W, H: Double);
var
  FO, FU, FV, FN, D: TP3;
begin
  if Pl = plFree then
  begin
    GetFreePlane(FO, FU, FV, FN);
    D := P3(B.X - A.X, B.Y - A.Y, B.Z - A.Z);
    W := Abs(D.X * FU.X + D.Y * FU.Y + D.Z * FU.Z);
    H := Abs(D.X * FV.X + D.Y * FV.Y + D.Z * FV.Z);
    Exit;
  end;
  case Pl of
    plXZ: begin W := Abs(B.X - A.X); H := Abs(B.Z - A.Z); end;
    plYZ: begin W := Abs(B.Y - A.Y); H := Abs(B.Z - A.Z); end;
  else    begin W := Abs(B.X - A.X); H := Abs(B.Y - A.Y); end;
  end;
end;

function TMainForm.SnapToGrid(const P: TP3): TP3;
var
  S: Double;
begin
  S := SnapStep;
  if S <= 0 then
    Result := P
  else
    Result := P3(Round(P.X / S) * S, Round(P.Y / S) * S, Round(P.Z / S) * S);
end;

{ Points on the drawing beat the grid, as in SketchUp.  Failing a direct hit,
  the cursor is pulled into line with a point sharing one of its coordinates,
  and a guide is shown back to it. }
function TMainForm.ResolveSnapRaw(SX, SY: Double): TP3;
var
  Hit: TSnapHit;
  Pts: TP3Array;
  I, BestAxis, Near: Integer;
  Tol, Best, KeepTol: Double;
  PrevGuide: Boolean;
  PrevFrom: TP3;
  W, Wf, AxRef, AxPt, EdgeP, EdgeA, EdgeB, MidP, AxSnapP: TP3;
  SP: TPointF;
  PtOK: Boolean;
  PtPx, AxPx: Double;
  AxIdx, EdgeI, AxSnapK: Integer;

  { An alignment is only shown when the point differs in exactly one
    direction, so the guide is a clean axis-parallel line.  (In plan every
    point shares Z, so allowing two would drag the guide to stray corners.) }
  procedure Consider(const C: TP3);
  var
    DX, DY, DZ, Score: Double;
    Big: Integer;
  begin
    DX := Abs(W.X - C.X);
    DY := Abs(W.Y - C.Y);
    DZ := Abs(W.Z - C.Z);

    Big := 0;
    if DX > Tol then Inc(Big);
    if DY > Tol then Inc(Big);
    if DZ > Tol then Inc(Big);
    if Big <> 1 then Exit;

    { and only when it is far enough away to be a visible guide }
    if Dist(W, C) * Ppu < 18 then Exit;

    Score := DX + DY + DZ;
    if DX > Tol then Score := Score - DX
    else if DY > Tol then Score := Score - DY
    else Score := Score - DZ;

    if Score < Best then
    begin
      Best := Score;
      BestAxis := 1;          // marks "found"; the axes are snapped below
      FGuideFrom := C;
    end;
  end;

  { The second half of a compound inference.  With an axis pinning two
    coordinates, the third can still be pulled level with a held point.
    This is what closes a rectangle square: run along red from the top
    corner and land on the X of the corner you rested on earlier. }
  procedure AlignFree(var Q: TP3; FreeAxis: Integer);
  var
    I: Integer;
    APts: TP3Array;
    Cur, BestOff: Double;
    BestPt: TP3;
    Got: Boolean;

    function Coord(const C: TP3): Double;
    begin
      case FreeAxis of
        0: Result := C.X;
        1: Result := C.Y;
      else Result := C.Z;
      end;
    end;

    function TryLevel(const C: TP3; Tol: Double): Boolean;
    var
      Off: Double;
    begin
      Result := False;
      Off := Abs(Coord(C) - Cur) * Ppu;
      if Off > Tol then Exit;
      { it has to be somewhere else, or the guide is a dot on the cursor }
      if Dist(Q, C) * Ppu < 18 then Exit;
      if Off >= BestOff then Exit;
      BestOff := Off;
      BestPt := C;
      Got := True;
      Result := True;
    end;

  begin
    Cur := Coord(Q);
    BestOff := 1E30;
    Got := False;

    { A point you rested on was asked for, so it goes first and holds from
      much further out than one the engine merely noticed. }
    if not (FLockOn and TryLevel(FLockPt, HOLD_PX)) then
    begin
      { leveling with other points waits for a slow hand }
      if FMoveSpeed <= FAST_PX_S then
      begin
        FD.Doc.SnapPoints(APts);
        for I := 0 to High(APts) do TryLevel(APts[I], INFER_PX);
        if FStage > 0 then TryLevel(FP1, INFER_PX);
      end;
    end;
    if not Got then Exit;

    case FreeAxis of
      0: Q.X := BestPt.X;
      1: Q.Y := BestPt.Y;
    else Q.Z := BestPt.Z;
    end;
    FGuide := True;
    FGuideFrom := BestPt;
  end;

  { One direction offered from a reference point.  Kind 0, 1, 2 for the
    axes, 3 parallel to the reference edge, 4 perpendicular to it.
    Measured on screen against the axis as drawn, not in model space: in
    iso or 3D, unprojecting pins one coordinate to the working plane, so a
    model-space test can never see blue (risers came out as diagonals). }
  procedure DirTry(const R, AD0: TP3; Kind: Integer);
  var
    Off, Along, T, LenSq: Double;
    PR, PA: TPointF;
    AD: TP3;
    UX, UY, VX, VY: Double;
  begin
    AD := Norm3(AD0);
    if Sqr(AD.X) + Sqr(AD.Y) + Sqr(AD.Z) < 0.5 then Exit;
    PR := ScreenOf(R);
    begin
      PA := ScreenOf(P3(R.X + AD.X, R.Y + AD.Y, R.Z + AD.Z));
      UX := PA.X - PR.X;
      UY := PA.Y - PR.Y;
      LenSq := UX * UX + UY * UY;

      { An axis pointing nearly at the camera projects to a stub: every
        cursor position is "on" it, and the distance along it blows up past
        1E12, which crashed the rubber band.  A unit must project to at least
        a fifth of a square-on unit, so axes steeper than about 78 degrees are
        ignored.  Only the free camera can get there. }
      if LenSq < Sqr(0.2 * Ppu) then Exit;

      VX := SX - PR.X;
      VY := SY - PR.Y;
      Along := (VX * UX + VY * UY) / LenSq;      // in axis units
      Off := Abs(VX * UY - VY * UX) / Sqrt(LenSq);

      if Abs(Along) * Sqrt(LenSq) < AXIS_MIN_PX then Exit;
      if Off < AxPx then
      begin
        { reject NaN, infinity, or anything further out than a drawing could be }
        T := Along;
        if IsNan(T) or IsInfinite(T) or (Abs(T) > 1E9) then Exit;
        AxPx := Off;
        AxIdx := Kind;
        AxRef := R;
        { the point on the axis nearest the cursor, in the model }
        AxPt := P3(R.X + AD.X * T, R.Y + AD.Y * T, R.Z + AD.Z * T);
      end;
    end;
  end;

  { where the axis through R crosses the edge A-B, if they actually meet:
    the point on the edge }
  function AxisMeetsEdge(const R: TP3; Axis: Integer; const A, B: TP3;
    out P: TP3): Boolean;
  var
    D, E, W: TP3;
    A2, B2, D2, DD, EE, DE, T, U, Den: Double;
  begin
    Result := False;
    case Axis of
      0: D := P3(1, 0, 0);
      1: D := P3(0, 1, 0);
    else D := P3(0, 0, 1);
    end;
    E := P3(B.X - A.X, B.Y - A.Y, B.Z - A.Z);
    W := P3(A.X - R.X, A.Y - R.Y, A.Z - R.Z);
    DD := Dot3(D, D); EE := Dot3(E, E); DE := Dot3(D, E);
    Den := DD * EE - DE * DE;
    if (EE < 1E-18) or (Abs(Den) < 1E-12 * DD * EE) then Exit;   { parallel }
    A2 := Dot3(D, W); B2 := Dot3(E, W);
    T := (A2 * EE - B2 * DE) / Den;         { along the axis }
    U := (A2 * DE - B2 * DD) / Den;         { along the edge, 0..1 }
    if (U < -1E-9) or (U > 1 + 1E-9) then Exit;
    P := P3(A.X + E.X * U, A.Y + E.Y * U, A.Z + E.Z * U);
    { the two lines have to actually meet, not just pass near }
    D2 := Sqr(R.X + D.X * T - P.X) + Sqr(R.Y + D.Y * T - P.Y) + Sqr(R.Z + D.Z * T - P.Z);
    Result := D2 < 1E-12;
  end;

  procedure AxisTry(const R: TP3);
  begin
    DirTry(R, P3(1, 0, 0), 0);
    DirTry(R, P3(0, 1, 0), 1);
    DirTry(R, P3(0, 0, 1), 2);
  end;

  { parallel to the reference edge, and square to it in the working plane
    (SketchUp's magenta pair) }
  procedure ParPerpTry(const R: TP3);
  var
    AU, AV, Nm, Perp: TP3;
  begin
    if not FParHas then Exit;
    DirTry(R, FParDir, 3);
    PlaneAxes(FD.Plane, AU, AV);
    Nm := Cross3(AU, AV);
    Perp := Cross3(Nm, FParDir);
    if Sqr(Perp.X) + Sqr(Perp.Y) + Sqr(Perp.Z) > 1E-12 then
      DirTry(R, Perp, 4);
  end;

begin
  PrevGuide := FGuide;
  PrevFrom := FGuideFrom;
  FGuide := False;
  FAxisLock := -1;

  { SNAP OFF means off: no grid, no points, no guides. }
  if SnapStep <= 0 then
  begin
    FSnapKind := snNone;
    Exit(WorldAt(SX, SY));
  end;

  Wf := WorldAt(SX, SY);

  { Still holding the last point?  A point is taken from close in and
    released from much further out, so a small slide does not drop it (as in
    SketchUp).  Only real points; a grid intersection has nothing to stick to. }
  if FStickOn and (FStickKind in [snEndpoint, snMidpoint, snCenter, snCross,
                                  snSubMid]) then
  begin
    SP := ScreenOf(FStickPt);
    if Sqr(SX - SP.X) + Sqr(SY - SP.Y) <= Sqr(STICK_PX * FUIScale) then
    begin
      FSnapKind := FStickKind;
      Exit(FStickPt);
    end;
    FStickOn := False;
  end;

  PtOK := FD.Doc.BestSnap(Proj, SX, SY, SNAP_PX, Hit);
  PtPx := 1E30;
  if PtOK then
  begin
    SP := ScreenOf(Hit.P);
    PtPx := Sqrt(Sqr(SX - SP.X) + Sqr(SY - SP.Y));
  end;

  { A definite point right under the cursor wins outright.  Piece midpoints
    do not count: they appear at every quarter point of split lines and would
    steal the cursor. }
  if PtOK and (PtPx <= LOCK_PX) and
     (Hit.Kind in [snEndpoint, snCross, snCenter, snMidpoint, snOrigin]) then
  begin
    FSnapKind := Hit.Kind;
    FStickOn := True;
    FStickPt := Hit.P;
    FStickKind := Hit.Kind;
    Exit(Hit.P);
  end;

  { Piece midpoints get a shorter reach of their own: they should not grab
    from as far as a corner, but they are what you aim at when dividing. }
  if PtOK and (PtPx <= PIECE_PX) and (Hit.Kind = snSubMid) then
  begin
    FSnapKind := Hit.Kind;
    Exit(Hit.P);
  end;

  { A line under the pointer means a point on that line (SketchUp's On
    Edge).  It beats the guides, since real geometry is more definite than
    an alignment to something far off, but it loses to any named point
    within reach, or line middles become nearly impossible to hit. }
  if (not PtOK) and
     FD.Doc.EdgeUnder(Proj, SX, SY, EDGE_PX * FUIScale, EdgeP,
                      EdgeA, EdgeB, EdgeI) then
  begin
    { The edge's middle is worked out here, not cached: face outline sides
      are not in the snap cache (too many to project on every camera move),
      and the edge under the cursor is already known, so it costs nothing. }
    MidP := P3((EdgeA.X + EdgeB.X) / 2, (EdgeA.Y + EdgeB.Y) / 2,
               (EdgeA.Z + EdgeB.Z) / 2);
    SP := ScreenOf(MidP);
    if Sqr(SX - SP.X) + Sqr(SY - SP.Y) <= Sqr(LOCK_PX * FUIScale) then
    begin
      FSnapKind := snMidpoint;
      FStickOn := True;
      FStickPt := MidP;
      FStickKind := snMidpoint;
      Exit(MidP);
    end;
    { On the edge and on an axis through the start: take the crossing point,
      exactly on both.  Otherwise the nearest edge point slides with every
      pixel and the line comes out slightly off square. }
    if (FStage > 0) and (FDirLock < 0) and (FInferMode = imAll) then
    begin
      AxIdx := -1;
      AxPx := AXIS_PX;
      AxPt := Wf;
      AxRef := Wf;
      FParPerp := 0;
      AxisTry(FP1);
      if FLockOn then AxisTry(FLockPt);
      if (AxIdx >= 0) and (AxIdx <= 2) and
         AxisMeetsEdge(AxRef, AxIdx, EdgeA, EdgeB, MidP) then
      begin
        FAxisLock := AxIdx;
        FAxisFrom := AxRef;
        FSnapKind := snOnEdge;
        Exit(MidP);
      end;
    end;
    FSnapKind := snOnEdge;
    Exit(EdgeP);
  end;

  { The three axes, as lines the cursor can be on (SketchUp's On Red Axis
    and friends).  Below real geometry, above alignment guides.  This is all
    an empty sheet has to snap to, and it is what lets Z read a real height:
    otherwise the cursor is pinned to the working plane. }
  if (not PtOK) and (FInferMode = imAll) and
     AxisSnap(Proj, SX, SY, EDGE_PX * FUIScale, AxSnapP, AxSnapK) then
  begin
    FSnapKind := snOnAxis;
    FSnapAxis := AxSnapK;
    Exit(AxSnapP);
  end;

  { Otherwise a 90 degree relation to a chosen point (the line start, or a
    rested-on point) beats other nearby snaps; going straight up from the
    start corner is nearly always what was wanted. }
  AxIdx := -1;
  AxPx := AXIS_PX;
  AxPt := Wf;
  AxRef := Wf;              { only read once AxisTry has set it; quiets the compiler }
  FSnapFromPt := False;
  FParPerp := 0;
  if FDirLock < 0 then
  begin
    { Alt says which of these are on offer - see TInferMode }
    if FInferMode = imAll then
    begin
      if FStage > 0 then AxisTry(FP1);
      if FLockOn then AxisTry(FLockPt);
    end;
    if FInferMode in [imAll, imParPerp] then
    begin
      if FStage > 0 then ParPerpTry(FP1);
      if FLockOn then ParPerpTry(FLockPt);
    end;
  end;

  { A definite point near an axis guide does not take the cursor off the
    guide: it says how far ALONG it.  The result is the point on the axis
    nearest the corner (SketchUp's rule), so square stays square.  A corner
    on the axis projects to itself.  Parallel/perpendicular guides simply
    give way to the point. }
  if PtOK and (AxIdx >= 0) and (AxIdx <= 2) and
     (Hit.Kind in [snEndpoint, snCross, snCenter, snMidpoint, snOrigin]) then
  begin
    AxPt := AxRef;
    case AxIdx of
      0: AxPt.X := Hit.P.X;
      1: AxPt.Y := Hit.P.Y;
    else AxPt.Z := Hit.P.Z;
    end;
    FSnapFromPt := True;
  end
  else if PtOK and (AxIdx >= 3) and
     (Hit.Kind in [snEndpoint, snCross, snCenter, snMidpoint, snOrigin]) then
    AxIdx := -1;

  if AxIdx >= 3 then
  begin
    { Parallel or square to an edge: the point comes straight off the ray,
      since there are no axis coordinates to hold. }
    W := AxPt;
    FParPerp := AxIdx - 2;
    FAxisLock := -1;
    FAxisFrom := AxRef;
    FSnapKind := snGrid;
    Exit(W);
  end;

  if AxIdx >= 0 then
  begin
    { The distance along the axis snaps to the grid, unless a corner set it;
      the other two coordinates come from the reference, which puts it
      exactly on the axis. }
    if FSnapFromPt then W := AxPt else W := SnapToGrid(AxPt);
    case AxIdx of
      0: begin W.Y := AxRef.Y; W.Z := AxRef.Z; end;
      1: begin W.X := AxRef.X; W.Z := AxRef.Z; end;
    else begin W.X := AxRef.X; W.Y := AxRef.Y; end;
    end;
    FAxisLock := AxIdx;
    FAxisFrom := AxRef;
    FSnapKind := snGrid;
    { and the third coordinate can still line up with something }
    AlignFree(W, AxIdx);
    Exit(W);
  end;

  if PtOK then
  begin
    FSnapKind := Hit.Kind;
    Exit(Hit.P);
  end;

  W := SnapToGrid(Wf);
  FSnapKind := snGrid;

  { a locked direction is already a constraint; inferring another on top
    makes the cursor feel glued to the start }
  if FDirLock >= 0 then
    Exit(W);

  Tol := INFER_PX / Max(1E-9, Ppu);
  Best := 1E30;
  BestAxis := -1;
  { A fast hand is going somewhere, not lining up: no nudges until it slows.
    One already taken is kept out to a wider tolerance so it does not
    flicker at the edge. }
  if PrevGuide then
  begin
    KeepTol := Tol * KEEP_FACTOR;
    Near := 0;
    if Abs(W.X - PrevFrom.X) <= KeepTol then Inc(Near);
    if Abs(W.Y - PrevFrom.Y) <= KeepTol then Inc(Near);
    if Abs(W.Z - PrevFrom.Z) <= KeepTol then Inc(Near);
    if (Near = 2) and (Dist(W, PrevFrom) * Ppu >= 18) then
    begin
      if Abs(W.X - PrevFrom.X) <= KeepTol then W.X := PrevFrom.X;
      if Abs(W.Y - PrevFrom.Y) <= KeepTol then W.Y := PrevFrom.Y;
      if Abs(W.Z - PrevFrom.Z) <= KeepTol then W.Z := PrevFrom.Z;
      FGuideFrom := PrevFrom;
      FGuide := True;
      Exit(W);
    end;
  end;
  if FMoveSpeed > FAST_PX_S then Exit(W);

  FD.Doc.SnapPoints(Pts);
  for I := 0 to High(Pts) do
    Consider(Pts[I]);
  if FStage > 0 then
    Consider(FP1);

  if BestAxis >= 0 then
  begin
    { pull the matching axes onto the point; the odd one out is the guide }
    if Abs(W.X - FGuideFrom.X) <= Tol then W.X := FGuideFrom.X;
    if Abs(W.Y - FGuideFrom.Y) <= Tol then W.Y := FGuideFrom.Y;
    if Abs(W.Z - FGuideFrom.Z) <= Tol then W.Z := FGuideFrom.Z;
    FGuide := True;
  end;

  Result := W;
end;

{ A point pulled back onto the face being drawn on.  Some inferences do not
  know about the face: the model axes run along the base of anything on the
  ground and would pull the point sideways off it. }
function TMainForm.HeldToFace(const P: TP3): TP3;
var
  D: Double;
begin
  Result := P;
  if not FPlaneFromFace then Exit;
  D := (P.X - FFacePt.X) * FFaceNm.X + (P.Y - FFacePt.Y) * FFaceNm.Y +
       (P.Z - FFacePt.Z) * FFaceNm.Z;
  Result := P3(P.X - FFaceNm.X * D, P.Y - FFaceNm.Y * D, P.Z - FFaceNm.Z * D);
end;

function TMainForm.ResolveSnapAt(SX, SY: Double): TP3;
var
  HF: Integer;
  HP, N, Raw: TP3;
  RU1, RV1, RU2, RV2: Double;
begin
  Result := ResolveSnapRaw(SX, SY);
  { Held to the face, except when the point came from an axis lock or a named
    point.  Those are more definite than a held plane: standing a gable up
    off the floor follows blue as SketchUp does, and an endpoint aimed at
    must not be flattened onto some other plane. }
  if (FAxisLock < 0) and not (FSnapKind in [snEndpoint, snMidpoint, snCenter,
       snCross, snSubMid, snOrigin, snQuadrant]) then
    Result := HeldToFace(Result);
  { A plane locked with the arrows is deliberate, so even an endpoint off it
    does not win; it would stop the outline closing.  Only an axis lock,
    the same kind of statement made more recently, overrides it. }
  if FPlaneHeld and (FStage > 0) and (FAxisLock < 0) then
    case FD.Plane of
      plXY: Result.Z := FP1.Z;
      plXZ: Result.Y := FP1.Y;
      plYZ: Result.X := FP1.X;
    end;
  { A rectangle may not have a side of zero length.  Alignments are built
    for lines, and leveling a rectangle's corner with its start leaves a
    zero side, which the tool rejects with no visible reason.  If an
    inference flattened a side the bare cursor had, that side goes back; the
    other side keeps its alignment. }
  if (FTool = ptRect) and (FStage = 1) and (FD.Plane <> plFree) then
  begin
    { snapped to the grid, or restoring the bare cursor gives odd fractions.
      If the grid itself flattens it, the message below says so. }
    Raw := SnapToGrid(WorldAt(SX, SY));
    RectSides(FP1, Result, FD.Plane, RU1, RV1);
    RectSides(FP1, Raw, FD.Plane, RU2, RV2);
    if (RU1 <= 1E-9) and (RU2 > 1E-9) then
      case FD.Plane of
        plYZ: Result.Y := Raw.Y;
      else    Result.X := Raw.X;
      end;
    if (RV1 <= 1E-9) and (RV2 > 1E-9) then
      case FD.Plane of
        plXY: Result.Y := Raw.Y;
      else    Result.Z := Raw.Z;
      end;
  end;

  { A free point resting on a face reads On Face, as in SketchUp, but only
    when it really lies on that face's plane. }
  if (FSnapKind = snGrid) and FD.Doc.FaceUnder(Proj, SX, SY, HF, HP) then
  begin
    N := Norm3(FD.Doc.FaceNormal(HF));
    if Abs(Dot3(N, P3(Result.X - HP.X, Result.Y - HP.Y, Result.Z - HP.Z))) < 1E-6 then
      FSnapKind := snOnFace;
  end;
end;

function TMainForm.AnnotColor: TPix;
begin
  Result := Pix($44, $48, $52);
end;

procedure TMainForm.UIFont(C: TCanvas; Size: Integer; Bold: Boolean;
  const Col: TPix; Mono: Boolean);
begin
  {$IFDEF WINDOWS}
  if Mono then C.Font.Name := 'Consolas' else C.Font.Name := 'Segoe UI';
  {$ELSE}
    {$IFDEF DARWIN}
    if Mono then C.Font.Name := 'Menlo' else C.Font.Name := 'Helvetica Neue';
    {$ELSE}
    if Mono then C.Font.Name := 'Monospace' else C.Font.Name := 'Sans';
    {$ENDIF}
  {$ENDIF}
  C.Font.Height := -Round(Size * FUIScale);
  if Bold then C.Font.Style := [fsBold] else C.Font.Style := [];
  C.Font.Color := PixToColor(Col);
  C.Brush.Style := bsClear;
end;

function TMainForm.TrackedText(C: TCanvas; X, Y: Integer; const S: string;
  Tracking: Integer): Integer;
var
  I, X0: Integer;
begin
  X0 := X;
  for I := 1 to Length(S) do
  begin
    C.TextOut(X, Y, S[I]);
    Inc(X, C.TextWidth(S[I]) + Tracking);
  end;
  Result := X - X0;
end;

function TMainForm.ToolName(T: TTool): string;
begin
  Result := TOOL_NAMES[T];
end;

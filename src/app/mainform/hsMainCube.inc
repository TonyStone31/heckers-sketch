{ hsMainForm - the view cube.  Part of TMainForm; included by hsMainForm.pas }

{ ======================================================================== }
{ the view cube                                                             }
{ ======================================================================== }

{ The cube's square, in the chosen corner of the drawing area (top right by
  default, under the VIEW button, as Revit places its own). }
function TMainForm.CubeRect: TRect;
var
  Sz, M, L, T: Integer;
begin
  Sz := CubeSize(FUIScale);
  M := Round(14 * FUIScale);
  { the bottom corners leave room for the scale bar along the foot }
  if FCubeCorner in [0, 2] then L := M else L := pbScreen.Width - M - Sz;
  if FCubeCorner in [0, 1] then T := M
  else T := pbScreen.Height - Round(46 * FUIScale) - Sz;
  Result := Rect(L, T, L + Sz, T + Sz);
end;

{ The cube's patch: its square plus a margin.  The hexagon sits in a square,
  so aiming at its edge puts the pointer off the shape; the crosshair, snap
  mark and chip must not draw over it while someone is trying to click it. }
function TMainForm.CubeZone(X, Y: Integer): Boolean;
var
  R: TRect;
  M: Integer;
begin
  Result := False;
  if (not FCubeOn) or (FD = nil) or (FD.View <> vkOrbit) then
    Exit;
  R := CubeRect;
  M := Round(10 * FUIScale);
  { the hot target's name is written under it, so the zone covers that too }
  Result := (X >= R.Left - M) and (X <= R.Right + M) and
            (Y >= R.Top - M) and (Y <= R.Bottom + M + Round(16 * FUIScale));
end;

{ Is the pointer on the cube itself?  For things that only need to stand
  aside (the wheel, the cursor). }
function TMainForm.OverCube(X, Y: Integer): Boolean;
var
  R: TRect;
  T: TCubeTarget;
begin
  Result := False;
  if (not FCubeOn) or (FD = nil) or (FD.View <> vkOrbit) then
    Exit;
  if FCubeDrag then Exit(True);
  R := CubeRect;
  Result := CubeAt(Proj, (R.Left + R.Right) / 2, (R.Top + R.Bottom) / 2,
    (R.Right - R.Left) / 2 / 1.75, X, Y, T);
end;

procedure TMainForm.PaintViewCube(C: TCanvas);
var
  R: TRect;
  Half: Double;
  Labels: TCubeLabels;
  I, TW: Integer;
  Col: TPix;
begin
  if not FCubeOn then Exit;
  { only in the free 3D view: the paper modes are fixed conventions }
  if (FD = nil) or (FD.View <> vkOrbit) then Exit;

  R := CubeRect;
  if FCubeSkin = nil then FCubeSkin := TArtSurface.Create(16, 16);
  FCubeSkin.SetSize(R.Right - R.Left, R.Bottom - R.Top);
  FCubeSkin.ClearTransparent;
  FCubeSkin.PreserveAlpha := True;

  { room to turn without corners leaving the surface (a cube's long
    diagonal is root three) }
  Half := (R.Right - R.Left) / 2 / 1.75;
  { the pointer's target, or while an orbit is snapping, the one it will
    snap to }
  if FSnapHasHot then
    PaintCube(FCubeSkin, Proj, Half, Theme, True, FSnapHot.Dir)
  else
    PaintCube(FCubeSkin, Proj, Half, Theme, FCubeHasHot, FCubeHot.Dir);
  FCubeSkin.DrawTo(C, R.Left, R.Top);

  { the names, on the canvas because they want a font }
  Labels := CubeLabels(Proj, Half);
  for I := 0 to High(Labels) do
  begin
    Col := OnPix(MixPix(Theme.Panel, Pix(255, 255, 255), 0.30));
    UIFont(C, 8, True, Col);
    TW := C.TextWidth(Labels[I].Name);
    { a face seen nearly edge-on has no room for a word }
    if Labels[I].Facing < 0.26 then Continue;
    C.TextOut(R.Left + Round((R.Right - R.Left) / 2 + Labels[I].X - TW / 2),
      R.Top + Round((R.Bottom - R.Top) / 2 + Labels[I].Y - C.TextHeight('X') / 2),
      Labels[I].Name);
  end;

  { what is under the pointer, in words under the cube }
  if FSnapHasHot and (FSnapHot.Name <> '') then
  begin
    C.Font.Color := PixToColor(Theme.Accent);
    TW := C.TextWidth(FSnapHot.Name);
    C.TextOut(R.Left + (R.Right - R.Left - TW) div 2,
      R.Bottom + Round(2 * FUIScale), FSnapHot.Name);
  end
  else if FCubeHasHot and (FCubeHot.Name <> '') then
  begin
    UIFont(C, 9, True, Theme.Accent);
    TW := C.TextWidth(FCubeHot.Name);
    C.TextOut(R.Left + ((R.Right - R.Left) - TW) div 2,
      R.Bottom + Round(2 * FUIScale), FCubeHot.Name);
  end;
end;

{ A compass in a top corner the cube is not in, while the grid is on: north
  is the green axis, east red, up blue, each drawn as the view shows it
  (flat in plan, turning in iso and orbit) in its axis color. }
procedure TMainForm.PaintCompass(C: TCanvas);
const
  TAGS: array[0..4] of string = ('E', 'W', 'N', 'S', 'U');
var
  R, M, Pad, CX, CY, K, TX, TY, OX, OY: Integer;
  Rt, Up, Dir: TP3;
  DX, DY, L: Double;
  Col: TPix;
begin
  if not FShowGrid or (FD = nil) then Exit;
  R := Round(20 * FUIScale);
  M := Round(14 * FUIScale);
  Pad := Round(12 * FUIScale);
  { top right; top left when the cube is there }
  if FCubeOn and (FD.View = vkOrbit) and (FCubeCorner = 1) then CX := M + Pad + R
  else CX := pbScreen.Width - M - Pad - R;
  CY := M + Pad + R;
  Rt := ViewRight(Proj);
  Up := ViewUp(Proj);
  C.Brush.Style := bsClear;
  C.Pen.Width := 1;
  C.Pen.Color := PixToColor(Theme.Grid);
  C.Ellipse(CX - R, CY - R, CX + R + 1, CY + R + 1);
  UIFont(C, 9, True, Pix(0, 0, 0));
  for K := 0 to High(TAGS) do
  begin
    case K of
      0: Dir := P3(1, 0, 0);
      1: Dir := P3(-1, 0, 0);
      2: Dir := P3(0, 1, 0);
      3: Dir := P3(0, -1, 0);
    else Dir := P3(0, 0, 1);
    end;
    DX := Dot3(Dir, Rt); DY := -Dot3(Dir, Up);
    L := Hypot(DX, DY);
    { pointing at the eye (up, in plan): nothing to draw }
    if L < 0.2 then Continue;
    Col := AxisPix(K div 2);
    C.Pen.Color := PixToColor(Col);
    if K mod 2 = 0 then C.Pen.Width := Max(2, Round(2 * FUIScale)) else C.Pen.Width := 1;
    C.Line(CX, CY, CX + Round(DX * R), CY + Round(DY * R));
    { the letter just past the point, outlined in black like the axes' }
    TX := CX + Round(DX / L * (R * L + Pad * 0.75)) - C.TextWidth(TAGS[K]) div 2;
    TY := CY + Round(DY / L * (R * L + Pad * 0.75)) - C.TextHeight(TAGS[K]) div 2;
    C.Font.Color := clBlack;
    for OX := -1 to 1 do
      for OY := -1 to 1 do
        if (OX <> 0) or (OY <> 0) then C.TextOut(TX + OX, TY + OY, TAGS[K]);
    C.Font.Color := PixToColor(Col);
    C.TextOut(TX, TY, TAGS[K]);
  end;
  C.Pen.Width := 1;
end;

{ The pointer over the cube; True when the cube took it.  Down starts a
  click or a drag; Up decides.  A press that travels orbits, one that does
  not goes to the target under it. }
function TMainForm.CubeMouse(X, Y: Integer; Down, Up: Boolean): Boolean;
var
  R: TRect;
  Half, Az, El, NewAz, NewEl, FitZ, FitX, FitY, Near_: Double;
  T: TCubeTarget;
  Was: Boolean;
begin
  Result := False;
  if (not FCubeOn) or (FD = nil) or (FD.View <> vkOrbit) then
  begin
    FCubeHasHot := False;
    Exit;
  end;

  R := CubeRect;
  Half := (R.Right - R.Left) / 2 / 1.75;

  { a drag that started on the cube keeps it until release, even off it }
  if FCubeDrag and not Down then
  begin
    Result := True;
    if Up then
    begin
      FCubeDrag := False;
      { a drag released within 8 degrees of one of the 26 views snaps to it;
        Ctrl snaps to the nearest from anywhere, as on the orbit tool }
      if FCubeMoved then
      begin
        T := CubeNearest(ViewDir(Proj), Near_);
        if (ssCtrl in GetKeyShiftState) or (Near_ >= Cos(DegToRad(8))) then
        begin
          Az := FD.Az;
          CubeAzEl(T.Dir, Az, El);
          FViewPreset := -1;
          GlideTo(Az, El);
          FCmdMsg := T.Name + '.';
        end;
        Exit;
      end;
      { it never traveled, so it was a click }
      if not FCubeMoved and
         CubeAt(Proj, (R.Left + R.Right) / 2, (R.Top + R.Bottom) / 2,
                Half, X, Y, T) then
      begin
        Az := FD.Az;
        CubeAzEl(T.Dir, Az, El);
        FViewPreset := -1;
        { with something picked (and fit-selection on) it glides to center
          and size it in one movement; otherwise it turns and keeps the
          user's zoom }
        if FCubeFitSel and (Length(FSel) > 0) and
           FitTarget(True, Az, El, FitZ, FitX, FitY) then
          GlideCamera(Az, El, FitZ, FitX, FitY)
        else
          GlideTo(Az, El);
        FCmdMsg := T.Name + '.';
      end;
      Exit;
    end;
    { a press becomes a drag only after it travels more than 4 px; counting
      one pixel made clicks randomly read as drags }
    if (Abs(X - FCubePressX) > 4) or (Abs(Y - FCubePressY) > 4) then
      FCubeMoved := True;
    if FCubeMoved and ((X <> FCubeDragX) or (Y <> FCubeDragY)) then
    begin
      FGlideT := 0;                 { the hand wins over any glide }
      { locals first: see the -O3 note in ServiceMotion }
      NewAz := FD.Az - (X - FCubeDragX) * 0.010;
      NewEl := FD.El + (Y - FCubeDragY) * 0.010;
      if NewEl < -1.45 then NewEl := -1.45;
      if NewEl > 1.45 then NewEl := 1.45;
      FD.Az := NewAz;
      FD.El := NewEl;
      FViewPreset := -1;
      HoldTurn;
      FCubeDragX := X;
      FCubeDragY := Y;
      FCameraMoving := True;
      FLastWheel := GetTickCount64;
      { the paper too: the axes and ground grid are ruled on it }
      RepaintPaper;
      RenderInk;
      RecomposeAll;
      Invalidate;
    end;
    Exit;
  end;

  Was := FCubeHasHot;
  FCubeHasHot := CubeAt(Proj, (R.Left + R.Right) / 2,
    (R.Top + R.Bottom) / 2, Half, X, Y, T);
  if FCubeHasHot then FCubeHot := T;
  if FCubeHasHot <> Was then FScreenDirty := True
  else if FCubeHasHot then FScreenDirty := True;

  if not FCubeHasHot then Exit;
  Result := True;
  if Down then
  begin
    FCubeDrag := True;
    FCubeMoved := False;
    FCubeDragX := X;
    FCubeDragY := Y;
    FCubePressX := X;
    FCubePressY := Y;
    { a cube drag turns about the same point a click glides about }
    FTurnPivot := TurnPivot;
    FTurnAnchor := ScreenOf(FTurnPivot);
    FTurnAnchored := not (IsNan(FTurnAnchor.X) or IsNan(FTurnAnchor.Y) or
                          IsInfinite(FTurnAnchor.X) or IsInfinite(FTurnAnchor.Y)) and
                     (Abs(FTurnAnchor.X) < 1E6) and (Abs(FTurnAnchor.Y) < 1E6);
  end;
end;

{ What a turn turns about: the middle of the selection, or of the whole
  drawing when nothing is picked (Revit's rule).  Never the world origin,
  which would swing a drawing far from zero out of the window. }
function TMainForm.TurnPivot: TP3;
begin
  if (FD = nil) or not FD.Doc.MiddleOf(FSel, Result) then Result := P3(0, 0, 0);
end;

{ Put the pivot back where it was on screen after the angles moved.  A
  TProjector turns about the world origin, so every turn gets its pivot this
  way.  A pivot that projects to nonsense is ignored rather than adding
  millions to the view position. }
procedure TMainForm.HoldTurn;
var
  OP: TPointF;
begin
  if not FTurnAnchored then Exit;
  OP := ScreenOf(FTurnPivot);
  if IsNan(OP.X) or IsNan(OP.Y) or IsInfinite(OP.X) or IsInfinite(OP.Y) then Exit;
  if (Abs(OP.X) > 1E6) or (Abs(OP.Y) > 1E6) then Exit;
  FD.ViewX := FD.ViewX + (FTurnAnchor.X - OP.X);
  FD.ViewY := FD.ViewY + (FTurnAnchor.Y - OP.Y);
end;

{ What a fit would come out as, without doing it, so a glide can aim at its
  final framing.  Computed at the destination angles, which decide where the
  middle lands. }
function TMainForm.FitTarget(OnSelection: Boolean; AzT, ElT: Double;
  out NewZoom, NewOX, NewOY: Double): Boolean;
var
  Lo, Hi, Mid: TP3;
  V: TProjector;
  P: TPointF;
  BaseP, W, H, Z: Double;
begin
  NewZoom := FD.Zoom;
  NewOX := FD.ViewX;
  NewOY := FD.ViewY;
  if OnSelection and (Length(FSel) > 0) then
    Result := FD.Doc.SpanOf(FSel, Lo, Hi)
  else
    Result := FD.Doc.Bounds(Lo, Hi);
  if not Result then Exit;

  BaseP := PixelsPerUnit(FD.Units, CurScale, Screen.PixelsPerInch);
  case FD.View of
    vkIso:
      begin
        W := Max((Abs(Hi.X - Lo.X) + Abs(Hi.Y - Lo.Y)) * ISO_COS, 1E-6);
        H := Max((Hi.X - Lo.X + Hi.Y - Lo.Y) * ISO_SIN + (Hi.Z - Lo.Z), 1E-6);
      end;
    vkOrbit:
      begin
        { the diagonal is a safe bound from any camera angle }
        W := Max(Sqrt(Sqr(Hi.X - Lo.X) + Sqr(Hi.Y - Lo.Y) + Sqr(Hi.Z - Lo.Z)), 1E-6);
        H := W;
      end;
  else
    begin
      W := Max(Hi.X - Lo.X, 1E-6);
      H := Max(Hi.Y - Lo.Y, 1E-6);
    end;
  end;
  Z := Min((FArt.Width * 0.80) / (W * BaseP), (FArt.Height * 0.80) / (H * BaseP));
  if Z < ZOOM_MIN then Z := ZOOM_MIN;
  if Z > ZOOM_MAX then Z := ZOOM_MAX;
  NewZoom := Z;

  { where the middle would land, at that zoom and those angles }
  Mid := P3((Lo.X + Hi.X) / 2, (Lo.Y + Hi.Y) / 2, (Lo.Z + Hi.Z) / 2);
  V.Kind := FD.View;
  V.Ppu := BaseP * Z;
  V.OX := 0;
  V.OY := 0;
  V.Az := AzT;
  V.El := ElT;
  P := Project(V, Mid);
  NewOX := FArt.Width / 2 - P.X;
  NewOY := FArt.Height / 2 - P.Y;
end;

{ A glide that carries the framing too: turns, slides and zooms at once, so
  the target arrives centered and sized without a jump at either end. }
procedure TMainForm.GlideCamera(Az, El, Zoom, OX, OY: Double);
begin
  if FD = nil then Exit;
  GlideTo(Az, El);
  FGlideZ0 := FD.Zoom;
  FGlideZ1 := Zoom;
  FGlideOX0 := FD.ViewX;
  FGlideOX1 := OX;
  FGlideOY0 := FD.ViewY;
  FGlideOY1 := OY;
  { worth moving for the framing alone (the FIT button) }
  if (FGlideT = 0) and
     ((Abs(FGlideZ1 - FGlideZ0) > 1E-4 * Max(1, FGlideZ0)) or
      (Abs(FGlideOX1 - FGlideOX0) > 0.5) or (Abs(FGlideOY1 - FGlideOY0) > 0.5)) then
  begin
    FGlideD0 := FGlideD1;
    FGlideT := 1E-6;
    FGlideAt := GetTickCount64;
    FCameraMoving := True;
  end;
  FGlideFrame := FGlideT > 0;
end;

{ The view an orbit would snap to if released now: the nearest of the cube's
  26 (6 faces, 12 edges, 8 corners).  Free 3D view only. }
function TMainForm.OrbitSnapTarget(out T: TCubeTarget): Boolean;
var
  Near_: Double;
begin
  Result := False;
  if (FD = nil) or (FD.View <> vkOrbit) then Exit;
  T := CubeNearest(ViewDir(Proj), Near_);
  { Every direction has a nearest of the 26, worst case 27.4 degrees away
    (TestOrbitSnapFindsTheNearestView), so there is no distance limit; a
    limit would make the key silently do nothing. }
  Result := Near_ > -1;
end;

{ Let go and glide into it, so you do not lose track of the model. }
procedure TMainForm.SnapOrbitToNearest;
var
  T: TCubeTarget;
  Az, El: Double;
begin
  if not OrbitSnapTarget(T) then Exit;
  Az := FD.Az;
  { straight up or down says nothing about which way round, so CubeAzEl
    keeps the current turn }
  CubeAzEl(T.Dir, Az, El);
  GlideTo(Az, El);
  FCmdMsg := 'Snapped to ' + T.Name + '.';
  Trail('orbit snapped to ' + T.Name);
end;

{ Ctrl+arrow: one step round the 26, gliding as a cube click does.  3D view
  only. }
procedure TMainForm.StepCubeView(Key: Word);
var
  T: TCubeTarget;
  Near_, Az, El: Double;
  Dir: TP3;
  Step: TCubeStep;
begin
  if (FD = nil) or (FD.View <> vkOrbit) then Exit;
  case Key of
    VK_LEFT:  Step := csLeft;
    VK_RIGHT: Step := csRight;
    VK_UP:    Step := csUp;
  else
    Step := csDown;
  end;
  { from where a running glide is going, so a quick second press carries on }
  if FGlideT > 0 then
    Az := FGlideAz1
  else
    Az := FD.Az;
  if FGlideT > 0 then
    T := CubeNearest(P3(Cos(FGlideEl1) * Cos(FGlideAz1),
      Cos(FGlideEl1) * Sin(FGlideAz1), Sin(FGlideEl1)), Near_)
  else
    T := CubeNearest(ViewDir(Proj), Near_);
  Dir := CubeStep(T.Dir, Az, Step);
  if (Dir.X = 0) and (Dir.Y = 0) and (Step in [csLeft, csRight]) then
  begin
    { looking straight down or up: turn the drawing a side's worth }
    if Step = csRight then Az := Az + Pi / 4 else Az := Az - Pi / 4;
    El := FD.El;
    if FGlideT > 0 then El := FGlideEl1;
  end
  else
    CubeAzEl(Dir, Az, El);
  T := CubeNearest(Dir, Near_);
  FViewPreset := -1;
  GlideTo(Az, El);
  FCmdMsg := T.Name + '  - Ctrl and the arrows walk round the view cube.';
  Trail('cube step to ' + T.Name);
end;

procedure TMainForm.GlideTo(Az, El: Double);
var
  D: Double;

  { where the camera stands, as a direction }
  function DirOf(A, E: Double): TP3;
  begin
    Result := P3(Cos(E) * Cos(A), Cos(E) * Sin(A), Sin(E));
  end;

begin
  if FD = nil then Exit;
  FGlideAz0 := FD.Az;
  FGlideEl0 := FD.El;
  { start a camera move, the short way round; none if already there }
  D := Az - FD.Az;
  while D > Pi do D := D - 2 * Pi;
  while D < -Pi do D := D + 2 * Pi;
  FGlideAz1 := FD.Az + D;
  FGlideEl1 := El;
  if (Abs(D) < 1E-4) and (Abs(El - FD.El) < 1E-4) then
  begin
    FGlideT := 0;
    Exit;
  end;
  { the two camera directions, which StepGlide interpolates }
  FGlideD0 := DirOf(FGlideAz0, FGlideEl0);
  FGlideD1 := DirOf(FGlideAz1, FGlideEl1);
  { what it turns about, and where that is on screen now }
  FTurnPivot := TurnPivot;
  FTurnAnchor := ScreenOf(FTurnPivot);
  FTurnAnchored := not (IsNan(FTurnAnchor.X) or IsNan(FTurnAnchor.Y) or
                        IsInfinite(FTurnAnchor.X) or IsInfinite(FTurnAnchor.Y)) and
                   (Abs(FTurnAnchor.X) < 1E6) and (Abs(FTurnAnchor.Y) < 1E6);
  FGlideT := 1E-6;
  FGlideAt := GetTickCount64;
  FGlideFrame := False;
  FCameraMoving := True;
end;

{ Dt is unused: this runs on the clock, not on how often the timer fired. }
procedure TMainForm.StepGlide(Dt: Double);
var
  K, NewAz, NewEl, Dot, Ang, S0, S1, Flat: Double;
  NewZ, NewOX, NewOY: Double;
  D: TP3;
begin
  if FGlideT <= 0 then Exit;
  if FD = nil then
  begin
    FGlideT := 0;
    Exit;
  end;
  FGlideT := (GetTickCount64 - FGlideAt) / (GLIDE_SECONDS * 1000);
  if FGlideT >= 1 then FGlideT := 1;
  { ease in and out, so it reads as the model turning }
  K := FGlideT * FGlideT * (3 - 2 * FGlideT);

  { The camera rolls along the great circle between the two directions at a
    constant rate, rather than interpolating azimuth and elevation, which
    swings it sideways on the way from corner to far corner. }
  Dot := FGlideD0.X * FGlideD1.X + FGlideD0.Y * FGlideD1.Y +
         FGlideD0.Z * FGlideD1.Z;
  if Dot > 1 then Dot := 1;
  if Dot < -1 then Dot := -1;
  Ang := ArcCos(Dot);
  if Ang < 1E-6 then
    D := FGlideD1
  else
  begin
    S0 := Sin((1 - K) * Ang) / Sin(Ang);
    S1 := Sin(K * Ang) / Sin(Ang);
    D := P3(FGlideD0.X * S0 + FGlideD1.X * S1,
            FGlideD0.Y * S0 + FGlideD1.Y * S1,
            FGlideD0.Z * S0 + FGlideD1.Z * S1);
  end;

  { and back into turn and tilt }
  Flat := Sqrt(D.X * D.X + D.Y * D.Y);
  if Flat > 1E-9 then NewAz := ArcTan2(D.Y, D.X) else NewAz := FD.Az;
  NewEl := ArcTan2(D.Z, Flat);
  if NewEl < -1.45 then NewEl := -1.45;
  if NewEl > 1.45 then NewEl := 1.45;
  { the arc is the short way round the sphere, but the azimuth can come out
    the long way round; keep it near where it was }
  while NewAz - FD.Az > Pi do NewAz := NewAz - 2 * Pi;
  while NewAz - FD.Az < -Pi do NewAz := NewAz + 2 * Pi;
  { land exactly where aimed }
  if FGlideT >= 1 then
  begin
    NewAz := FGlideAz1;
    NewEl := FGlideEl1;
  end;
  FD.Az := NewAz;
  FD.El := NewEl;
  if FGlideFrame then
  begin
    { zoom interpolates geometrically: halfway from 1x to 4x is 2x }
    NewZ := FGlideZ0 * Exp(Ln(Max(1E-9, FGlideZ1 / Max(1E-9, FGlideZ0))) * K);
    NewOX := FGlideOX0 + (FGlideOX1 - FGlideOX0) * K;
    NewOY := FGlideOY0 + (FGlideOY1 - FGlideOY0) * K;
    if FGlideT >= 1 then
    begin
      NewZ := FGlideZ1;
      NewOX := FGlideOX1;
      NewOY := FGlideOY1;
    end;
    { through a local and clamped by hand (see FitView and ServiceMotion on
      -O3) }
    if NewZ < ZOOM_MIN then NewZ := ZOOM_MIN;
    if NewZ > ZOOM_MAX then NewZ := ZOOM_MAX;
    FD.Zoom := NewZ;
    FD.ViewX := NewOX;
    FD.ViewY := NewOY;
  end
  else
    HoldTurn;
  if FGlideT >= 1 then
  begin
    FGlideT := 0;
    FCameraMoving := False;
    { the framing came with the glide, so nothing more on arrival }
    RepaintPaper;
  end
  else
    FCameraMoving := True;
  { the axes and grid live on the paper and must turn too (see CubeMouse) }
  RepaintPaper;
  RenderInk;
  RecomposeAll;

  { Paint now with Update, not just Invalidate: the tick-driven glide keeps
    the message loop too busy to paint between steps, so without this the
    move appears to teleport. }
  pbScreen.Invalidate;
  pbScreen.Update;
end;

{ hsMainForm - the tools.  Part of TMainForm; included by hsMainForm.pas }

{ ======================================================================== }
{ the tools                                                                 }
{ ======================================================================== }

function TMainForm.PlaneName: string;
begin
  if FD.Plane = plFree then Exit('on the face');
  Result := Copy('XYXZYZ', Ord(FD.Plane) * 2 + 1, 2);
end;

{ The arrows pick the plane before a shape is started, so drawing in 3D is
  not always flat.  Once a line is under way the arrows lock its direction
  instead. }
procedure TMainForm.PlaneByArrow(Key: Word);
var
  Was: TPlane;
begin
  Was := FD.Plane;
  { As SketchUp, the plane is named by its normal's axis color: right is
    red (YZ), left is green (XZ), up or down is blue (flat).  Esc releases it. }
  case Key of
    VK_RIGHT: FD.Plane := plYZ;     // normal is red, X
    VK_LEFT: FD.Plane := plXZ;      // normal is green, Y
  else
    FD.Plane := plXY;               // up or down: normal is blue, Z
  end;
  FPlaneHeld := True;
  if FD.Plane <> Was then
  begin
    RepaintPaper;
    RenderInk;
    RecomposeAll;
  end;
  case FD.Plane of
    plXZ: FCmdMsg := 'Drawing upright, on the XZ plane.';
    plYZ: FCmdMsg := 'Drawing on the side, the YZ plane.';
  else
    FCmdMsg := 'Drawing flat, on the XY plane.';
  end;
  FCmdMsg := FCmdMsg + '  Esc to follow faces again.';
  pbCmd.Invalidate;
  FScreenDirty := True;
end;

{ Leave a standard view for the free camera, aimed where you were looking.
  Zoom and pan are kept, so picking orbit while zoomed in does not reframe
  the whole drawing. }
procedure TMainForm.EnterFreeCamera(AtCorner: Boolean);
begin
  if FD.View = vkOrbit then Exit;
  if AtCorner then
  begin
    { for push/pull, which cannot see the face it moves from straight above }
    FD.Az := -Pi / 4;
    FD.El := ISO_EL;
  end
  else if FD.View = vkIso then
  begin
    FD.Az := -Pi / 4;
    FD.El := ISO_EL;
  end
  else
  begin
    FD.Az := 0;
    FD.El := 1.45;                  // as near straight down as it tilts
  end;
  FD.View := vkOrbit;
  FViewPreset := -1;
  RebuildDeck;
  pbDeck.Invalidate;
  pbView.Invalidate;
  RepaintPaper;
  RenderInk;
  RecomposeAll;
end;

procedure TMainForm.SetTool(T: TTool);
begin
  { Changing tool while picking stairs releases the pick and brings the stair
    dialog back, as Esc does; the new tool would otherwise start in pick mode. }
  if FStairPick > 0 then
  begin
    FStairPick := 0;
    FInput := '';
    FCmdMsg := 'Stairs: the pick is let go of - back to the stairs.  Finish or cancel them first.';
    pbCmd.Invalidate;
    pbScreen.Invalidate;
    Application.QueueAsyncCall(@StairResume, 0);
    Exit;
  end;
  Trail('tool ' + TOOL_NAMES[T]);
  Act('tool ' + TOOL_NAMES[T]);
  FArray.Live := False;
  { Push/pull along a normal pointing at the camera cannot be seen or judged
    in plan, so switch to a view where it means something. }
  if (T in [ptPush, ptDrill, ptFollow]) and (FD.View = vkPlan) then
  begin
    EnterFreeCamera(True);
    FCmdMsg := 'Push/pull needs to see the face - switched to the corner view.';
  end;
  if (T = ptOrbit) and (FD.View <> vkOrbit) then
  begin
    EnterFreeCamera;
    FCmdMsg := 'Orbit - drag to spin.  Shift pans; hold Ctrl and let go to click into the nearest view.';
  end;
  if T = ptOrbit then pbScreen.Cursor := crSizeAll
  else pbScreen.Cursor := crCross;
  FTool := T;
  ResetTool;
  pbDeck.Invalidate;
  pbCmd.Invalidate;
  Invalidate;
end;

procedure TMainForm.ResetTool;
begin
  FStage := 0;
  FDimArc := -1;
  { Alt's inference cycle is per run, not per session }
  FInferMode := imAll;
  FParHas := False;
  FParPerp := 0;
  FArcTanHas := False;
  FArcTanLock := False;
  FOffsetRaw := False;
  FRotFree := False;
  FFollowFace := -1;
  FUnfoldPick := False;
  FNoteDrag := -1;
  FStickOn := False;
  FSliceEdit := 0;
  { Every sheet change comes through here and each sheet has its own cut, so
    this guarantees the document never slices by the last sheet's numbers. }
  ApplySlice;
  { -1 means no dimension being edited.  Zero is a valid index, and with
    FDimEdit >= 0 every key goes into the command bar instead of being a
    shortcut. }
  FDimEdit := -1;
  FHoverEnt := -1;
  FHoverFace := -1;
  FPlaneHeld := False;
  FGuide := False;
  FAxisLock := -1;
  FLockOn := False;
  FDirLock := -1;
  FRotAxisIx := -1;
  FInput := '';
  FBoxing := False;
  FMoveCopy := False;
  FMoveRigid := False;
  FDimMove := -1;
  SetLength(FMoveVerts, 0);
  SetLength(FMoveGroupEnts, 0);
  pbScreen.Invalidate;
  pbCmd.Invalidate;
end;

function TMainForm.PlanePix(Pl: TPlane): TPix;
begin
  case Pl of
    plXZ: Result := AxisPix(1);      { faces along Y, green }
    plYZ: Result := AxisPix(0);      { faces along X, red }
    { a sloped face points along no axis, so it gets no axis color }
    plFree: Result := Theme.Accent;
  else
    Result := AxisPix(2);            { flat, faces up Z, blue }
  end;
end;

{ Which of the three paper axes an ISO line is meant to run along (an
  AxisDir index), or -1 before the drag shows a direction.  On iso paper
  every leg runs along an axis, so the line is locked to the nearest, not
  nudged.  All three axes, not just the current isoplane, so a run can chain
  across then down without a keystroke.  Measured on screen, like AxisTry. }
function TMainForm.IsoRunAxis(const From: TP3; out Along: Double): Integer;
var
  K: Integer;
  PR, PA: TPointF;
  UX, UY, VX, VY, LenSq, Off, Best, Step: Double;
  AD: TP3;
begin
  Result := -1;
  Along := 0;
  PR := ScreenOf(From);
  VX := FMouseSX - PR.X;
  VY := FMouseSY - PR.Y;
  { under a few pixels the drag has no direction yet }
  if VX * VX + VY * VY < Sqr(6 * FUIScale) then Exit;
  Best := 1E30;
  for K := 0 to 2 do
  begin
    AD := AxisDir(K * 2);
    PA := ScreenOf(Add3(From, AD));
    UX := PA.X - PR.X;
    UY := PA.Y - PR.Y;
    LenSq := UX * UX + UY * UY;
    if LenSq < Sqr(0.2 * Ppu) then Continue;
    { how far off this axis the cursor is, in pixels }
    Off := Abs(VX * UY - VY * UX) / Sqrt(LenSq);
    if Off < Best then
    begin
      Best := Off;
      Result := K * 2;
      { The distance along it comes from the same screen measurement that
        chose it, not from the snapped cursor, which may sit on a different
        axis.  PA is one world unit away, so this is in world units. }
      Along := (VX * UX + VY * UY) / LenSq;
    end;
  end;
  if Result < 0 then Exit;
  { land on the grid ruling; the length is ours to round }
  Step := SnapStep;
  if Step > 1E-9 then Along := Round(Along / Step) * Step;
end;

{ Which axis a segment runs along, or -1.  Nearly exact: an edge either lies
  on an axis or it does not. }
function TMainForm.AxisAlong(const A, B: TP3): Integer;
var
  DX, DY, DZ, L: Double;
begin
  Result := -1;
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  DZ := B.Z - A.Z;
  L := Sqrt(DX * DX + DY * DY + DZ * DZ);
  if L < 1E-9 then Exit;
  if Abs(DX) / L > 0.9999 then Result := 0
  else if Abs(DY) / L > 0.9999 then Result := 1
  else if Abs(DZ) / L > 0.9999 then Result := 2;
end;

function TMainForm.LiveMeasure: string;
var
  T: TP3;
  W, H, L, LBulge: Double;
  LPl: TPlane;
  LFil: TFillet;
  LTyped: Boolean;
begin
  Result := '';
  case FTool of
    ptLine:
      if FStage = 1 then
        Result := FormatLen(Dist(FP1, PreviewTarget), FD.Units);
    ptRect:
      if FStage = 1 then
      begin
        RectSides(FP1, RectTarget, FD.Plane, W, H);
        { the comma is how SketchUp takes two sides, and so do we }
        Result := FormatLen(W, FD.Units) + ', ' + FormatLen(H, FD.Units);
      end;
    ptCircle:
      if FStage = 1 then
        Result := FormatLen(Dist(FP1, FCur), FD.Units);
    ptArc:
      if FStage = 1 then
        Result := FormatLen(Dist(FP1, FCur), FD.Units)
      else if FStage = 2 then
      begin
        if ArcFillet(LFil, LTyped) then
          Result := 'radius ' + FormatLen(LFil.R, FD.Units)
        else if ArcPicks(FCur, LPl, T, W, H, L, LBulge) then
          Result := 'bulge ' + FormatLen(Abs(LBulge), FD.Units);
      end;
    ptRotate, ptProtractor:
      if FStage >= 1 then
        Result := FormatAngle(RadToDeg(RotAngle));
    ptPush, ptDrill:
      if (FStage = 1) and (FPushFace >= 0) then
      begin
        L := PushDistance;
        if Abs(L) > 1E-9 then Result := FormatLen(Abs(L), FD.Units);
        if FPushFlush then Result := Result + '  flush';
      end;
    ptOffset:
      if FStage = 1 then
      begin
        L := OffsetDistance;
        if Abs(L) > 1E-9 then Result := FormatLen(Abs(L), FD.Units);
      end;
    ptMeasure, ptDim:
      if FStage >= 1 then
      begin
        T := PreviewTarget;
        if Dist(FP1, T) > 1E-9 then Result := FormatLen(Dist(FP1, T), FD.Units);
      end;
  end;
end;

{ What the cursor is holding, in words, for the status sentence (the chip
  says it in capitals). }
function TMainForm.SnapSays: string;
begin
  if FAxisLock in [0..2] then
    Exit('held on the ' + AxisName(FAxisLock) + ' axis');
  if FParPerp = 1 then Exit('parallel to the last edge');
  if FParPerp = 2 then Exit('square to the last edge');
  case FSnapKind of
    snEndpoint: Result := 'on the end of an edge';
    snMidpoint: Result := 'on the middle of an edge';
    snSubMid:   Result := 'on the middle of a piece';
    snCenter:   Result := 'on a center';
    snCross:    Result := 'where two lines cross';
    snOnEdge:   Result := 'on an edge';
    snOnFace:   Result := 'on a face';
    snQuadrant: Result := 'on the quarter of a circle';
    snOrigin:   Result := 'on the origin';
    snOnAxis:
      case FSnapAxis of
        0: Result := 'on the red axis';
        1: Result := 'on the green axis';
      else Result := 'on the blue axis';
      end;
  else
    Result := '';
  end;
end;

{ The keys that do something right now for the tool and its stage, as
  SketchUp's status bar shows.  Only what is true now: a modifier named when
  it does nothing gets tried once and never again. }
function TMainForm.ModifierTip: string;
begin
  Result := '';
  case FTool of
    ptSelect:
      if Length(FSel) = 0 then
        Result := 'Ctrl adds, Shift toggles, double-click takes what is ' +
                  'attached, three clicks take all of it'
      else
        Result := 'Ctrl adds, Shift toggles, Ctrl+Shift takes away';
    ptLine:
      if FStage = 0 then
        Result := 'arrows pick the plane, Alt holds it where it is'
      else
        case FInferMode of
          imNoLinear: Result := 'Alt: back to parallel and square, then to all - ' +
            'points still snap';
          imParPerp: Result := 'parallel and square only - Alt for all of them';
        else
          Result := 'arrows lock red, green or blue, Shift holds the one you ' +
                    'are on, Alt steps through the inferences';
        end;
    ptRect:
      if FStage = 0 then Result := 'arrows pick the plane, Alt holds it'
      else Result := 'type 8x10, or a minus to flip a side';
    ptCircle, ptArc:
      if FStage = 0 then
        Result := '+ and - change the sides, arrows pick the plane'
      else if (FTool = ptArc) and (FStage = 2) and FArcTanHas then
        Result := specialize IfThen<string>(FArcTanLock,
          'tangent to the edge it started on, held - Alt lets go',
          '+ and - change the sides, Alt runs it out of its edge smoothly')
      else
        Result := '+ and - change the sides, or type 24s';
    ptPush:
      if FLastPush <> 0 then
        Result := Format('double-click repeats the last push (%s)',
          [FormatLen(Abs(FLastPush), FD.Units)])
      else
        Result := 'type how far, or rest on an edge to go to it';
    ptOffset:
      if FOffsetRaw then Result := 'overlaps kept - Alt tidies them again'
      else Result := 'type the offset - a minus goes inward, Alt keeps the overlaps';
    ptMove:
      if FStage = 0 then Result := 'Ctrl leaves a copy behind'
      else Result := 'Ctrl copies, Shift holds the axis, then 3x or /3 for an array';
    ptErase: Result := 'Ctrl softens an edge instead, Ctrl+Shift brings it back';
    ptMeasure: Result := 'Ctrl changes what it leaves behind - ' + TapeDropSays;
    ptOrbit: Result := 'Shift pans, Ctrl clicks into the nearest view when you let go';
    ptRotate, ptProtractor:
      if FRotFree then
        Result := 'free of the face under the cursor - arrows pick the plane, ' +
                  'Alt follows faces again'
      else
        Result := 'arrows pick the plane by color, Alt frees it from the face';
    ptDim: Result := 'click the body of an edge for all of it';
    ptText: Result := 'Shift+Enter for a second line';
  end;
end;

{ ModifierTip, short enough for the card beside the pointer }
function TMainForm.ShortKeys: string;
begin
  Result := '';
  case FTool of
    ptSelect:   Result := 'Ctrl adds  Shift toggles  double-click takes more';
    ptLine:     if FStage = 0 then Result := 'arrows: the plane   Alt: hold it'
                else if FInferMode = imNoLinear then Result := 'Alt: inferences back on'
                else if FInferMode = imParPerp then Result := 'parallel and square only   Alt: all'
                else Result := 'arrows: lock an axis   Shift: hold it   Alt: what it infers';
    ptRect:     if FStage = 0 then Result := 'arrows: the plane   Alt: hold it';
    ptCircle, ptArc: Result := '+ and -: sides';
    ptPush:     if FLastPush <> 0 then Result := 'double-click: the last push again';
    ptMove:     Result := 'Ctrl: leave a copy   Shift: hold the axis';
    ptErase:    Result := 'Ctrl: soften   Ctrl+Shift: bring back';
    ptMeasure:  Result := 'Ctrl: what it leaves behind';
    ptOrbit:    Result := 'Shift: pan   Ctrl: click into a view';
    ptRotate, ptProtractor:
      if FRotFree then Result := 'free of the face   Alt: follow faces'
      else Result := 'arrows: the plane   Alt: free of the face';
  end;
end;

function TMainForm.PromptForTool: string;
var
  PromptAlong: Double;
  PMoveB: Boolean;
  PFil: TFillet;
  PTyped: Boolean;
begin
  case FTool of
    ptLine:
      if FStage = 0 then
      begin
        if (FD.View = vkOrbit) and not FPlaneHeld then
          Result := 'pick a start point   (arrows lock a flat plane: ' +
                    'left or right upright, up or down flat, Esc to let go)'
        else if FPlaneHeld then
          Result := 'pick a start point - locked to the ' + PlaneName +
                    ' plane, and it stays there'
        else
          Result := 'pick a start point';
      end
      else if FPlaneHeld and (FDirLock < 0) then
        Result := 'to the next point - held on the ' + PlaneName +
                  ' plane whatever you point at.  Double-click to finish'
      else if FDirLock >= 0 then
        Result := 'going ' + AxisName(FDirLock) + ' - length?'
      else if (FD.View = vkIso) and (ssShift in FMoveShift) then
        Result := 'off the grid - Shift held.  Let go to snap back to it'
      else if (FD.View = vkIso) and (IsoRunAxis(FP1, PromptAlong) >= 0) then
        Result := 'going ' + AxisName(IsoRunAxis(FP1, PromptAlong)) +
          ' on the grid - length?  Shift to come off it'
      else
        Result := 'to the next point, or type a length  -  double-click to finish';
    ptArc:
      case FStage of
        0:
          if FLastFilletR > 0 then
            Result := 'pick the first end - or double-click a corner to round it ' +
              FormatLen(FLastFilletR, FD.Units)
          else
            Result := 'pick the first end - on an edge near a corner to round it';
        1: Result := 'pick the second end';
      else
        if ArcFillet(PFil, PTyped) then
          Result := 'TANGENT TO EDGE - click, double-click to trim the corner, ' +
            'or type a radius'
        else if FilletCandidate(PFil) then
          Result := 'pull the middle towards the corner until it turns tangent, ' +
            'or type the bulge'
        else
          Result := 'pull the middle out, or type the bulge';
      end;
    ptRect:
      if FStage = 0 then Result := 'pick a corner'
      else Result := 'opposite corner, or type 12''x8''';
    ptCircle:
      if FStage = 0 then Result := 'pick the center' else Result := 'radius?';
    ptText:
      if FStage = 0 then
        Result := 'click what the note is about'
      else
        Result := 'type it - Shift+Enter for another line - then move away and Enter';
    ptPush, ptDrill:
      if FStage = 0 then
        Result := 'click a face'
      else
        Result := 'how far?  type it, or move and click';
    ptFollow:
      case FStage of
        0: Result := 'click the outline to spin - half of the shape, seen edge on';
        1: Result := 'the axis: click the straight side of the outline - ' +
                     'or two points down one side of it';
      else
        Result := 'the axis: a second point straight along it - type 90 ' +
                  'first for a quarter turn';
      end;
    ptDim:
      case FStage of
        0:
          if (FHoverEnt >= 0) and (FD.Doc[FHoverEnt].Kind = ekArc) then
          begin
            if Abs(FD.Doc[FHoverEnt].Sweep) >= 2 * Pi - 1E-9 then
              Result := 'click for the diameter of the lit circle'
            else
              Result := 'click for the radius of the lit arc';
          end
          else if FHoverEnt >= 0 then
            Result := 'click the lit edge to dimension all of it'
          else if DimAnchored then
            Result := 'click an edge, or a first point to measure from'
          else
            { said before the click: nothing here to measure from }
            Result := 'nothing here to measure - find a corner, a midpoint, ' +
                      'a center, or an edge';
        1:
          if DimAnchored then
            Result := 'second point - on a corner, a midpoint, a center or an edge'
          else
            Result := 'the other end has to be on something too';
      else
        Result := 'move away to place the line, then click';
      end;
    ptOrbit:
      { with Ctrl down mid-orbit, say where letting go will snap to (the
        cube shows it too, but is off by default) }
      if FSnapHasHot and (FSnapHot.Name <> '') then
        Result := 'let go to click into ' + FSnapHot.Name
      else
        Result := 'drag to spin the view - Shift pans, Ctrl snaps to a view';
    ptSelect:
      if Length(FSel) = 0 then
        Result := 'click to pick, or drag a box   (Ctrl adds, Shift toggles)'
      else
        if (Length(FSel) = 1) and (FD.Doc[FSel[0]].Kind = ekText) then
          Result := '1 picked - M to move, + and - for the text size, Delete to remove'
        else if SelectedDim >= 0 then
          Result := 'dimension picked - type a size and the drawing follows'
        else if (SelectedLine >= 0) and FD.Doc.LineLengthEnd(SelectedLine, PMoveB) then
          Result := 'line picked - type a length and Enter; the free end moves'
        else
        Result := Format('%d picked - M to move, Delete to remove',
          [Length(FSel)]);
    ptMove:
      if FStage = 0 then
        Result := 'grab a point on what you are moving'
      else if FMoveCopy then
        Result := 'where does the copy go?  a length, [x,y,z] or <x,y,z>'
      else if FDetachMove then
        Result := 'where does it go, on its own?  a length, [x,y,z] or ' +
          '<x,y,z> - /detach off to join it back on'
      else
        Result := 'where does it go?  a length, [x,y,z] or <x,y,z>';
    ptErase:
      Result := 'click an edge to delete it - or hold and drag across ' +
        'several.  Ctrl softens instead, Ctrl+Shift brings it back';
    ptRotate, ptProtractor:
      case FStage of
        0: if FTool = ptRotate then
             Result := 'click the center to turn about   (arrows: red, green or blue plane)'
           else
             Result := 'click the vertex of the angle   (arrows: red, green or blue plane)';
        1: Result := 'click a point to measure the angle from, or type the angle';
      else
        Result := 'swing to the angle and click, or type it - 45, 22.5, or 8:12 ' +
          'for a slope.  Negative goes the other way.';
      end;
  else
    case FStage of
      0: Result := 'measure from...';
      1: Result := 'measure to...';
    else
      Result := 'Enter keeps it as a dimension';
    end;
  end;
end;

{ Shift + arrow hops to the next real point in that direction, for getting
  around by keyboard or touch. }
procedure TMainForm.JumpSnap(DX, DY: Integer);
var
  I: Integer;
  Here, P: TPointF;
  Best, D, Along, Across: Double;
  Target: TP3;
  Found: Boolean;

  procedure Try_(const Q: TP3);
  begin
    P := ScreenOf(Q);
    Along := (P.X - Here.X) * DX + (P.Y - Here.Y) * DY;
    Across := Abs((P.X - Here.X) * DY - (P.Y - Here.Y) * DX);
    if Along < 2 then Exit;
    D := Along + Across * 2.5;
    if D < Best then
    begin
      Best := D;
      Target := Q;
      Found := True;
    end;
  end;

begin
  Here := ScreenOf(FCur);
  Best := 1E30;
  Found := False;
  for I := 0 to FD.Doc.Live - 1 do
  begin
    Try_(FD.Doc[I].A);
    Try_(FD.Doc[I].B);
    if FD.Doc[I].Kind = ekArc then
      Try_(FD.Doc[I].C);
  end;
  if Found then
  begin
    FCur := Target;
    FSnapKind := snEndpoint;
    FCmdMsg := 'Snapped to a point.';
  end
  else
    FCmdMsg := 'Nothing that way.';
  pbScreen.Invalidate;
  InvalidateStatus;
end;

procedure TMainForm.ToolClick;
var
  I, J: Integer;
  P: TPointF;
  T: TP3;
  U1, V1, U2, V2: Double;
  WasLine, Closed: Boolean;
begin
  { any click ends the copy that could have become an array, except the
    copy's own placing click }
  if FStage = 0 then FArray.Live := False;
  case FTool of
    ptOrbit: ;   // the drag does the work

    ptSelect: ;   // the press and release do the work

    { Grab a point, then say where it goes.  With nothing selected it picks
      up whatever is under the cursor first. }
    ptMove:
      if FStage = 0 then
      begin
        { nothing picked and the cursor on a corner: take just that corner
          (SketchUp's stretch), to pull a box out of square }
        if (Length(FSel) = 0) and (FSnapKind = snEndpoint) then
        begin
          SetLength(FMoveVerts, 1);
          FMoveVerts[0] := FCur;
          FP1 := FCur;
          FStage := 1;
          FDirLock := -1;
          FInput := '';
          FCmdMsg := 'Stretching from that corner.  ' +
            'Click where it goes, or type a distance.';
          Exit;
        end;
        PruneSelection;
        FMoveTook := False;
        if Length(FSel) = 0 then
        begin
          I := PickToGrab(FMouseSX, FMouseSY);
          if I < 0 then
          begin
            FCmdMsg := 'Nothing there to move.';
            Exit;
          end;
          SelectOnly(I);
          FMoveTook := True;
        end;
        { a dimension taken by its line is repositioned, not moved: its two
          points stay and the line goes where the cursor puts it, as in
          SketchUp }
        if (Length(FSel) = 1) and (FD.Doc[FSel[0]].Kind = ekDim) and
           ((Copy(FD.Doc[FSel[0]].Txt, 1, 2) = 'R ') or
            (Copy(FD.Doc[FSel[0]].Txt, 1, 4) = 'DIA ')) and
           (Pos('<>', FD.Doc[FSel[0]].Txt) > 0) then
        begin
          { a radius or diameter sits on its curve; it has nowhere to go }
          FCmdMsg := 'A radius or a diameter sits on its curve - erase it and ' +
            'dimension the curve again to turn it.';
          Exit;
        end;
        if (Length(FSel) = 1) and (FD.Doc[FSel[0]].Kind = ekDim) then
        begin
          FDimMove := FSel[0];
          FDimPrefer := P3(0, 0, 0);
          FP1 := FD.Doc[FDimMove].A;
          FP2 := FD.Doc[FDimMove].B;
          FStage := 1;
          FDirLock := -1;
          FInput := '';
          FCmdMsg := 'Moving the dimension line - click where it should sit.  ' +
            'It goes the way the pointer goes, flat or standing up.';
          Exit;
        end;
        FP1 := FCur;
        if not SplitMoveSelection then Exit;
        FStage := 1;
        FDirLock := -1;
        FInput := '';
        FCmdMsg := 'Click where it goes, or type a distance.  ' +
          'Arrows lock an axis, Ctrl leaves a copy.';
      end
      else
        ToolCommit;

    ptRotate, ptProtractor:
      case FStage of
        0:
          begin
            if FTool = ptRotate then
            begin
              if Length(FSel) = 0 then
              begin
                I := PickToGrab(FMouseSX, FMouseSY);
                if I < 0 then
                begin
                  FCmdMsg := 'Nothing there to rotate - pick something first.';
                  Exit;
                end;
                { With nothing picked, take everything joined to it, not one
                  face; turning one face of a box twists the box.  Pick first
                  to turn a part alone. }
                if FD.Doc.TopPartIn(I) > 0 then SelectOnly(I) else SelectConnected(I);
              end;
              if not SplitMoveSelection then Exit;
            end;
            FP1 := FCur;
            { the plane: an arrow key's, else the face under the cursor's,
              else flat (what a duct run turns in) }
            if FRotAxisIx >= 0 then
              FRotAxis := AxisDir(FRotAxisIx)
            else if (not FRotFree) and
                    FD.Doc.FaceUnder(Proj, FMouseSX, FMouseSY, I, T) then
              FRotAxis := Norm3(FD.Doc.FaceNormal(I))
            else
              { Alt freed it from the face: flat unless an arrow says
                otherwise }
              FRotAxis := P3(0, 0, 1);
            FStage := 1;
            FDirLock := -1;
            FInput := '';
            FCmdMsg := '';
          end;
        1:
          begin
            if Dist(FCur, FP1) < 1E-6 then
            begin
              FCmdMsg := 'Pick a point away from the center to measure from.';
              Exit;
            end;
            FRotRef := FCur;
            FStage := 2;
            FInput := '';
            FCmdMsg := '';
          end;
      else
        ToolCommit;
      end;

    ptErase:
      begin
        { hit test the raw pointer; a snap to a nearby endpoint would miss
          the thing clicked }
        P := PtF(FMouseSX, FMouseSY);
        I := FD.Doc.HitEdge(Proj, P.X, P.Y, 9 * FUIScale);
        if I < 0 then I := FD.Doc.HitTest(Proj, P.X, P.Y, 9 * FUIScale);
        { Ctrl softens rather than deletes, Ctrl+Shift brings it back }
        if (I >= 0) and (FEraseMode <> 0) then
        begin
          SetLength(FDoomed, 1);
          FDoomed[0] := I;
          SoftenDoomed(FEraseMode = 1);
        end
        else if I >= 0 then
        begin
          PushUndo;
          { a line between two regions held them apart; removing it should
            leave one region }
          WasLine := FD.Doc[I].Kind in [ekLine, ekArc];
          FD.Doc.Delete(I);
          { merging areas or opening a shape both fall out of rebuilding the
            faces, so neither needs its own rule }
          J := FaceCount;
          if WasLine and (RebuildFlatFaces < J) then
            FCmdMsg := 'Deleted - the faces either side are one now.'
          else
            FCmdMsg := 'Deleted.';
          SelectNone;
          RenderInk;
          RecomposeAll;
        end
        else
          FCmdMsg := 'Nothing under the cursor.';
      end;

    ptLine:
      if FStage = 0 then
      begin
        FP1 := FCur;
        FStage := 1;
        FDirLock := -1;
        { parallel and perpendicular start from the edge this line starts on
          (SketchUp's magenta pair); once a piece is drawn it takes over (see
          ToolCommit) }
        FInferMode := imAll;
        FParHas := False;
        I := FD.Doc.HitEdge(Proj, FMouseSX, FMouseSY, 9 * FUIScale,
          GUIDE_PICK_PX * FUIScale);
        if (I >= 0) and (FD.Doc[I].Kind = ekLine) and not FD.Doc[I].Dim then
        begin
          FParDir := Sub3(FD.Doc[I].B, FD.Doc[I].A);
          FParHas := Sqr(FParDir.X) + Sqr(FParDir.Y) + Sqr(FParDir.Z) > 1E-12;
        end;
      end
      else if FClickN >= 2 then
      begin
        { Double-click ends the run.  SketchUp does not do this, but a way to
          finish with the mouse was wanted.  The second click must not place
          a point too: it would leave a zero-length line, an invisible stray
          snap point. }
        ResetTool;
        FCmdMsg := 'Line finished.  Esc does the same.';
      end
      else
        ToolCommit;

    ptRect:
      if FStage = 0 then
      begin
        FP1 := FCur;
        FStage := 1;
        FInput := '';
      end
      else
        ToolCommit;

    ptArc:
      if FStage = 0 then
      begin
        FP1 := FCur;
        FStage := 1;
        { the edge this arc starts on, for Alt's tangent lock (see
          TangentBulge) }
        FArcTanHas := False;
        FArcTanLock := False;
        I := FD.Doc.HitEdge(Proj, FMouseSX, FMouseSY, 9 * FUIScale,
          GUIDE_PICK_PX * FUIScale);
        if (I >= 0) and (FD.Doc[I].Kind = ekLine) and not FD.Doc[I].Dim then
        begin
          FArcTanDir := Sub3(FD.Doc[I].B, FD.Doc[I].A);
          FArcTanHas := Sqr(FArcTanDir.X) + Sqr(FArcTanDir.Y) +
                        Sqr(FArcTanDir.Z) > 1E-12;
        end;
      end
      else if FStage = 1 then
      begin
        FP2 := FCur;
        FStage := 2;
      end
      else
        ToolCommit;

    ptCircle:
      if FStage = 0 then
      begin
        FP1 := FCur;
        FStage := 1;
      end
      else
        ToolCommit;

    ptText:
      if FStage = 0 then
      begin
        { SketchUp: double-click a face with the Text tool to label its area }
        if FClickN >= 2 then
        begin
          I := InContextFace(FaceAtPress);
          if I >= 0 then
          begin
            PushUndo;
            FD.Doc.AddText(FCur,
              FormatArea(FD.Doc.FaceArea(I), FD.Units), FInkColor);
            RenderInk;
            RecomposeAll;
            FCmdMsg := 'Area ' + FormatArea(FD.Doc.FaceArea(I), FD.Units);
            Exit;
          end;
        end;
        FP1 := FCur;
        FStage := 1;
        FInput := '';
      end
      else
        ToolCommit;

    ptFollow:
      case FStage of
        0:
          begin
            I := InContextFace(FaceAtPress);
            if I < 0 then
            begin
              FCmdMsg := 'Click the face to follow - that is the profile.';
              Exit;
            end;
            FFollowFace := I;
            FStage := 1;
            FInput := '';
            { edges picked beforehand are the path, SketchUp's first way of
              using the tool }
            for J := 0 to High(FSel) do
              if FD.Doc[FSel[J]].Kind in [ekLine, ekArc] then
              begin
                DoSweep(ChainFrom(FSel[J], Closed), Closed);
                Exit;
              end;
            FCmdMsg := 'Now the path: click a line or arc to follow along, a circle to ' +
              'follow round, or two points for an axis to spin on.';
          end;
        1:
          begin
            { a circle under the cursor means turning about its center; a
              line or open arc starts a path }
            I := FD.Doc.HitEdge(Proj, FMouseSX, FMouseSY, 9 * FUIScale);
            if (I >= 0) and (FD.Doc[I].Kind = ekArc) and (I <> FFollowFace) and
               (Abs(FD.Doc[I].Sweep) >= 2 * Pi - 1E-9) then
            begin
              DoRevolve(FD.Doc[I].C, ArcNormal(I), I);
              Exit;
            end;
            { An edge of the outline itself is the axis: a glass outline has
              one straight side down its middle, and clicking it is what
              anyone does.  Sweeping a face along its own edge means nothing.
              Any other line is still a sweep path. }
            if (I >= 0) and (FD.Doc[I].Kind = ekLine) and IsProfileEdge(I) then
            begin
              DoRevolve(FD.Doc[I].A,
                Sub3(FD.Doc[I].B, FD.Doc[I].A));
              Exit;
            end;
            if (I >= 0) and (FD.Doc[I].Kind in [ekLine, ekArc]) then
            begin
              DoSweep(ChainFrom(I, Closed), Closed);
              Exit;
            end;
            FAxisA := FCur;
            FStage := 2;
            FCmdMsg := 'Second point on the axis.  Type 90 first for a quarter turn, or just click for all the way round.';
          end;
      else
        begin
          if Dist(FCur, FAxisA) < 1E-9 then
          begin
            FCmdMsg := 'The second point has to be somewhere else along the axis.';
            Exit;
          end;
          DoRevolve(FAxisA, Sub3(FCur, FAxisA));
        end;
      end;

    ptPush, ptDrill:
      if FStage = 0 then
      begin
        { double-click another face to repeat the last pull, as SketchUp
          does for a row of identical extrusions }
        if (FClickN >= 2) and (Abs(FLastPush) > 1E-9) then
        begin
          I := InContextFace(FaceAtPress);
          if I >= 0 then
          begin
            PushUndo;
            if FD.Doc.PushPull(I, FLastPush) then
            begin
              RenderInk;
              RecomposeAll;
              FCmdMsg := 'Same again - ' + FormatLen(Abs(FLastPush), FD.Units);
            end;
            Exit;
          end;
        end;
        FPushFace := InContextFace(FaceAtPress);
        { a face too small or crowded to click can be picked first, then
          pushed }
        if (FPushFace < 0) and (Length(FSel) = 1) and
           (FD.Doc[FSel[0]].Kind = ekFace) then
          FPushFace := FSel[0];
        if FPushFace < 0 then
          FCmdMsg := 'No face there.  Close a loop of lines to make one.'
        else
        begin
          FP1 := FCur;
          FPushSX := FMouseSX;
          FPushSY := FMouseSY;
          FStage := 1;
          if Abs(Dot3(FD.Doc.FaceNormal(FPushFace), ViewDir(Proj))) > 0.98 then
            FCmdMsg := 'Type a distance, or move and click.  ' +
              'Press V for a 3D view to watch it move.'
          else
            FCmdMsg := 'Type a distance, or move and click.';
        end;
      end
      else
        ToolCommit;

    ptOffset:
      if FStage = 0 then
      begin
        FOffFace := InContextFace(FaceAtPress);
        { as with push/pull, a crowded face can be selected first }
        if (FOffFace < 0) and (Length(FSel) = 1) and
           (FD.Doc[FSel[0]].Kind = ekFace) then
          FOffFace := FSel[0];
        if FOffFace < 0 then
          FCmdMsg := 'No face there.  Close a loop of lines to make one.'
        else
        begin
          { Hold the cursor to this face's plane until done; otherwise the
            infinite model axes can pull it far off the face being offset. }
          FFacePt := FD.Doc[FOffFace].Poly[0];
          FFaceNm := Norm3(FD.Doc.FaceNormal(FOffFace));
          FPlaneFromFace := True;
          FStage := 1;
          FInput := '';
          FCmdMsg := 'Move in or out, or type a wall thickness.';
        end;
      end
      else
        CommitOffset;

    ptDim:
      case FStage of
        0:
          begin
            { Click the body of a line and move away to dimension the whole
              line (from SketchUp's docs).  A snapped point (corner, midpoint,
              center) is a point-to-point start; only a free cursor on an
              edge takes the edge.  What the hover lit is what the click
              takes, so the two cannot disagree. }
            FDimPrefer := P3(0, 0, 0);
            if (FHoverEnt >= 0) and (FD.Doc[FHoverEnt].Kind = ekArc) then
            begin
              { a curve is not measured by one of its straight pieces: a
                circle gives its diameter, an arc its radius (SketchUp's
                rule), and the end on the curve follows the pointer }
              FDimArc := FHoverEnt;
              FStage := 2;
              if Abs(FD.Doc[FHoverEnt].Sweep) >= 2 * Pi - 1E-9 then
                FCmdMsg := 'The diameter - move round the circle to turn it, click to place.'
              else
                FCmdMsg := 'The radius - move along the arc to turn it, click to place.';
            end
            else if FHoverEdgeOK and (Dist(FHoverEdgeA, FHoverEdgeB) > 1E-9) then
            begin
              FP1 := FHoverEdgeA;
              FP2 := FHoverEdgeB;
              FStage := 2;
              FCmdMsg := 'The whole edge, ' +
                FormatLen(Dist(FP1, FP2), FD.Units) +
                ' - move away to place the line.';
            end
            else if not DimAnchored then
            begin
              { Nothing to anchor to.  A dimension must hang off real
                geometry (end, midpoint, on-edge, intersection, center) so it
                updates with the model; a floating number goes stale. }
              FCmdMsg := 'A dimension has to measure something - a corner, ' +
                         'a midpoint, a center, or a point on an edge.';
              InvalidateStatus;
            end
            else
            begin
              FP1 := FCur;
              FStage := 1;
            end;
          end;
        1:
          { the far end must be anchored too }
          if DimAnchored then
          begin
            FP2 := FCur;
            FStage := 2;
          end
          else
          begin
            FCmdMsg := 'The other end has to be on something too - a corner, ' +
                       'a midpoint, a center, or a point on an edge.';
            InvalidateStatus;
          end;
      else
        ToolCommit;
      end;

    ptMeasure:
      if FStage = 0 then
      begin
        FP1 := FCur;
        { what the tape starts from decides the guide: an edge gives a
          parallel guide line, anything else a point (SketchUp's rule) }
        FMeasEdge := FD.Doc.HitEdge(Proj, FMouseSX, FMouseSY, 9 * FUIScale);
        if (FMeasEdge >= 0) and
           not (FD.Doc[FMeasEdge].Kind in [ekLine, ekArc]) then
          FMeasEdge := -1;
        FStage := 1;
      end
      else if FStage = 1 then
      begin
        FP2 := FCur;
        LayGuide;
        FRunOK := True;
        FRunA := FP1;
        FRunB := FP2;
        FCmdMsg := RunReading(FP1, FP2) + '   /keep makes it a dimension';
        ResetTool;
      end
      else
      begin
        FP1 := FCur;
        FStage := 1;
      end;
  end;
  pbScreen.Invalidate;
  pbCmd.Invalidate;
  FLastStatus := 0;
  InvalidateStatus;
end;

{ Why a typed measurement was not taken, in useful words, or '' if it is
  fine. }
function TMainForm.WhyNotAMeasurement(const S: string): string;
var
  T, LW, LH: string;
  P, NDash, Ix: Integer;
  D, CX, CY, CZ: Double;
  Fields: array[0..2] of string;
begin
  Result := '';
  T := Trim(S);
  if T = '' then Exit;

  { a place or an offset, which move and line read }
  if (T[1] = '[') or (T[1] = '<') then
  begin
    if ParseTriple(T, FD.Units, CX, CY, CZ) > 0 then Exit;
    Result := 'That is not a place.  [4,0,8] is a point in the drawing, ' +
      '<4,0,8> is that far from here.';
    Exit;
  end;

  { two sides at once, which only the rectangle asks for }
  P := Pos('x', LowerCase(T));
  if P = 0 then P := Pos(',', T);
  if (P > 0) and (FTool = ptRect) then
  begin
    LW := Trim(Copy(T, 1, P - 1));
    LH := Trim(Copy(T, P + 1, MaxInt));
    if ((LW = '') or ParseLen(LW, FD.Units, D)) and
       ((LH = '') or ParseLen(LH, FD.Units, D)) and
       ((LW <> '') or (LH <> '')) then Exit;
    Result := 'Two sides, like 8x10 - or 8/10 from the number pad.';
    Exit;
  end;

  { One length where the rectangle wants two: it parses as a length, so
    without this RectTarget gives up silently and the corner comes from the
    cursor.  6-8-15x4-0-0 is the form that works. }
  if (FTool = ptRect) and (P = 0) and ParseLen(T, FD.Units, D) then
  begin
    Result := Format('%s reads fine - a rectangle wants both sides.  ' +
      'Type %s x 4-0-0, or %s/4-0-0 from the number pad.  A comma on the ' +
      'end instead sets that side and leaves the other on the cursor.',
      [T, T, T]);
    Exit;
  end;

  if ParseLen(T, FD.Units, D) then Exit;

  { The dashed form's usual mistake: a field out of range for the drawing's
    precision.  Say which number and what the drawing counts in. }
  NDash := 0;
  Fields[0] := '';
  Fields[1] := '';
  Fields[2] := '';
  for Ix := 1 + Ord(T[1] = '-') to Length(T) do
    if T[Ix] = '-' then
    begin
      Inc(NDash);
      if NDash > 2 then Break;
    end
    else
      Fields[NDash] := Fields[NDash] + T[Ix];

  if (NDash = 2) and (Fields[2] <> '') and TryStrToFloat(Fields[2], D) and
     (D >= LenDenom) then
  begin
    Result := Format('The last number counts in 1/%d of an inch, so it has ' +
      'to be under %d - you typed %s.  Change PREC if this drawing is in ' +
      'something else.', [LenDenom, LenDenom, Fields[2]]);
    Exit;
  end;
  if (NDash = 2) and (Fields[1] <> '') and TryStrToFloat(Fields[1], D) and
     (D >= 12) then
  begin
    Result := 'The middle number is inches, so it has to be under 12.';
    Exit;
  end;

  Result := Format('I cannot read "%s" as a length.  Try 12, or 12''6", or ' +
    '3 1/2 - or feet-inches-1/%d like 6-8-15, which is six foot eight and ' +
    'fifteen %dths.', [T, LenDenom, LenDenom]);
end;

procedure TMainForm.ToolCommit;
var
  Fil: TFillet;
  FilTyped: Boolean;
  I, NPieces, NWas, NBroke: Integer;
  T, C: TP3;
  Loop: TP3Array;
  L, R, A0, Sweep, Bulge, U1, V1, U2, V2, UC, VC, NU, NV, Ln: Double;
  K: Integer;
  Ok: Boolean;
  Ang: Double;
  RA, RB: TP3;
  RNote: string;
  Base: Integer;
  Copies: array of Integer;
  ArcPl: TPlane;
  Stopped, DrillTyped: Boolean;
  Tk: QWord;
  WasRigid: Boolean;
begin
  Trail('commit ' + TOOL_NAMES[FTool] + ' stage=' + IntToStr(FStage));
  case FTool of
    ptRotate:
      begin
        if FStage < 1 then Exit;
        Ang := RotAngle;
        if Abs(Ang) < 1E-9 then
        begin
          FCmdMsg := 'Nothing turned - the angle was nought.';
          ResetTool;
          Exit;
        end;
        PushUndo;
        if FMoveCopy then
        begin
          { the copy stands alone and turns whole; the original and what
            hangs off it stay put }
          FArray.Live := True;
          FArray.Rotate := True;
          FArray.C := FP1;
          FArray.Axis := FRotAxis;
          FArray.Ang := Ang;
          SetLength(FArray.Src, Length(FSel));
          for I := 0 to High(FSel) do FArray.Src[I] := FSel[I];
          FD.Doc.ArrayRotate(FArray.Src, FP1, FRotAxis, Ang, 1, False, FArray.Made);
          SetLength(Copies, Length(FArray.Made));
          for I := 0 to High(Copies) do Copies[I] := FArray.Made[I];
          SelectNone;
          for I := 0 to High(Copies) do SelectAdd(Copies[I]);
          FCmdMsg := 'Copied, turned ' + FormatAngle(RadToDeg(Ang)) +
            '.  Type 6x for six round, or /6 to divide the turn.';
        end
        else
        begin
          FD.Doc.RotateEnts(FMoveGroupEnts, FP1, FRotAxis, Ang);
          FD.Doc.RotateVerts(FMoveVerts, FP1, FRotAxis, Ang);
          FCmdMsg := 'Turned ' + FormatAngle(RadToDeg(Ang));
        end;
        RebuildFlatFaces;
        RenderInk;
        RecomposeAll;
        SetLength(FMoveVerts, 0);
        FMoveCopy := False;
              ResetTool;
        FInput := '';
      end;

    ptProtractor:
      begin
        if FStage < 1 then Exit;
        Ang := RotAngle;
        T := RotV(RotRefDir, FRotAxis, Ang);
        PushUndo;
        FD.Doc.AddGuide(FP1, Add3(FP1, T));
        RenderInk;
        RecomposeAll;
        FCmdMsg := 'Guide laid at ' + FormatAngle(RadToDeg(Ang)) + '.';
        ResetTool;
        FInput := '';
      end;

    ptOffset:
      begin
        CommitOffset;
        Exit;
      end;
    ptFollow:
      begin
        if FStage = 2 then
          DoRevolve(FAxisA, Sub3(FCur, FAxisA));
        Exit;
      end;

    ptLine:
      begin
        T := PreviewTarget;
        if Dist(FP1, T) > 1E-9 then
        begin
          PushUndo;
          { This line says the areas it bounds are wanted, even drawn over an
            existing edge; that is how an erased face comes back (SketchUp's
            healing, see FHealOn). }
          FHealOn := True;
          FHealA := FP1;
          FHealB := T;
          if FD.Doc.HasLine(FP1, T) then
            FCmdMsg := FormatLen(Dist(FP1, T), FD.Units) + '   (already an edge)'
          else
          begin
            { drawn along an existing edge, the overlap is split into one
              edge rather than two stacked; otherwise a plain add }
            NPieces := FD.Doc.AddLineSplit(FP1, T, FInkColor, FEdgeW);
            if NPieces > 1 then
              FCmdMsg := FormatLen(Dist(FP1, T), FD.Units) +
                Format('   (split along an edge - %d pieces)', [NPieces])
            else
              FCmdMsg := FormatLen(Dist(FP1, T), FD.Units);
            { and both are cut where it crosses something.  Count from the
              end: AddLineSplit deletes what it overlapped and appends the
              pieces, shifting indices above them. }
            NWas := FD.Doc.Live - Max(1, NPieces);
            NBroke := FD.Doc.SplitCrossings(NWas);
            if NBroke > 0 then
              FCmdMsg := FCmdMsg + Format('   (broke %d edge%s at the crossings)',
                [NBroke, IfThen(NBroke = 1, '', 's')]);
          end;
          { whatever this did to the flat areas is worked out by asking what
            the edges enclose, not by a rule per case }
          { parallel and perpendicular are now measured from the piece just
            drawn (see TInferMode) }
          FParDir := Sub3(T, FP1);
          FParHas := Sqr(FParDir.X) + Sqr(FParDir.Y) + Sqr(FParDir.Z) > 1E-12;
          I := FaceCount;
          K := RebuildFlatFaces;
          FHealOn := False;
          if K > I then
            FCmdMsg := FCmdMsg + Format('   %d face%s now',
              [K, IfThen(K = 1, '', 's')]);
          RenderInk;
          RecomposeAll;
          FP1 := T;
          FCur := T;
        end;
        FInput := '';
        FDirLock := -1;
      end;

    ptRect:
      begin
        T := RectTarget;
        RectSides(FP1, T, FD.Plane, U1, V1);
        if (U1 > 1E-9) and (V1 > 1E-9) then
        begin
          PushUndo;
          NWas := FD.Doc.Live;
          Loop := RectCorners(FP1, T, FD.Plane);
          { An edge exactly on an existing one is the same edge; adding it
            again stacks lines and labels.  And a side drawn over an edge
            says the area it bounds is wanted (healing, see FHealOn), so a
            rectangle traced round an opening brings the face back.  One
            side is enough. }
          for I := 0 to 3 do
            if not FD.Doc.HasLine(Loop[I], Loop[(I + 1) mod 4]) then
              FD.Doc.AddLine(Loop[I], Loop[(I + 1) mod 4],
                FInkColor, FEdgeW, False)
            else if not FHealOn then
            begin
              FHealOn := True;
              FHealA := Loop[I];
              FHealB := Loop[(I + 1) mod 4];
            end;
          FD.Doc.SplitCrossings(NWas);
          RebuildFlatFaces;
          FHealOn := False;
          RenderInk;
          RecomposeAll;
          Trail('rect made, ' + IntToStr(FaceCount) + ' faces now');
          FCmdMsg := Format('%s x %s   area %s',
            [FormatLen(U1, FD.Units), FormatLen(V1, FD.Units),
             FormatArea(U1 * V1, FD.Units)]);
        end
        else
        begin
          { Say why: usually one side was within half a snap step of zero
            (on a 1' snap, anything within 6" of straight), rounded away. }
          RectSides(FP1, WorldAt(FMouseSX, FMouseSY), FD.Plane, U2, V2);
          FCmdMsg := Format('A rectangle needs two sides - that one is %s by %s.',
            [FormatLen(U2, FD.Units), FormatLen(V2, FD.Units)]);
          if (SnapStep > 0) and (Min(U2, V2) > 1E-9) and
             (Min(U2, V2) < SnapStep / 2) then
            FCmdMsg := FCmdMsg + Format('  The snap is %s, so the short side ' +
              'rounded away to nothing - a finer snap, or pull it further out.',
              [FormatLen(SnapStep, FD.Units)]);
        end;
        ResetTool;
        FInput := '';
      end;

    ptArc:
      begin
        { Rounding a corner: the arc goes in and the two lines are cut at the
          touch points, leaving the square corner pieces to erase or keep, as
          SketchUp does.  Only the second click of a double-click trims them. }
        if ArcFillet(Fil, FilTyped) then
        begin
          PushUndo;
          FD.Doc.ApplyFillet(Fil, FSidesArc, FInkColor, FEdgeW, False);
          FLastFilletR := Fil.R;
          RebuildFlatFaces;
          RenderInk;
          RecomposeAll;
          FCmdMsg := 'Arc tangent to both edges, radius ' +
            FormatLen(Fil.R, FD.Units) +
            '.  The corner is still there - erase it, or double-click to trim it.';
          FLastFillet := Fil;
          FFilletPending := True;
          FFilletSeq := FEditSeq;
          FFilletTick := GetTickCount64;
          ResetTool;
          Exit;
        end;
        Ok := ArcPicks(FCur, ArcPl, C, R, A0, Sweep, Bulge);
        if not Ok and (Dist(FP1, FP2) < 1E-9) then
        begin
          ResetTool;
          Exit;
        end;
        if Ok then
        begin
          PushUndo;
          NWas := FD.Doc.Live;
          FD.Doc.AddArc(C, R, A0, Sweep, ArcPl, FInkColor, FEdgeW);
          FD.Doc.SetArcSides(FD.Doc.Live - 1, FSidesArc);
          FCmdMsg := 'Arc radius ' + FormatLen(R, FD.Units);
          NBroke := FD.Doc.SplitCrossings(NWas);
          if NBroke > 0 then
            FCmdMsg := FCmdMsg + Format('   (broke %d edge%s at the crossings)',
              [NBroke, IfThen(NBroke = 1, '', 's')]);
          I := FaceCount;
          if RebuildFlatFaces > I then
            FCmdMsg := FCmdMsg + '   closed a face';
          RenderInk;
          RecomposeAll;
        end;
        ResetTool;
      end;

    ptCircle:
      begin
        if (FInput <> '') and ParseLen(FInput, FD.Units, L) then
          R := L
        else
          R := Dist(FP1, FCur);
        if R > 1E-9 then
        begin
          PushUndo;
          NWas := FD.Doc.Live;
          FD.Doc.AddArc(FP1, R, 0, 2 * Pi, FD.Plane, FInkColor, FEdgeW);
          FD.Doc.SetArcSides(FD.Doc.Live - 1, FSidesCircle);
          NBroke := FD.Doc.SplitCrossings(NWas);
          RebuildFlatFaces;
          RenderInk;
          RecomposeAll;
          FCmdMsg := Format('Circle radius %s   area %s',
            [FormatLen(R, FD.Units), FormatArea(Pi * R * R, FD.Units)]);
          if NBroke > 0 then
            FCmdMsg := FCmdMsg + Format('   (broke %d edge%s at the crossings)',
              [NBroke, IfThen(NBroke = 1, '', 's')]);
        end;
        ResetTool;
      end;

    ptMove:
      begin
        if FDimMove >= 0 then
        begin
          PushUndo;
          FD.Doc.SetDimOffset(FDimMove, DimOffset3);
          RenderInk;
          RecomposeAll;
          FCmdMsg := 'Dimension moved.';
          ResetTool;
          Exit;
        end;
        T := MoveDelta;
        if (Abs(T.X) > 1E-9) or (Abs(T.Y) > 1E-9) or (Abs(T.Z) > 1E-9) then
        begin
          PushUndo;
          if FMoveCopy then
          begin
            { a copy stands on its own, so nothing stretches to reach it }
            FArray.Live := True;
            FArray.Rotate := False;
            FArray.D := T;
            SetLength(FArray.Src, Length(FSel));
            for I := 0 to High(FSel) do FArray.Src[I] := FSel[I];
            FD.Doc.ArrayMove(FArray.Src, T, 1, False, FArray.Made);
            FCmdMsg := 'Copied ' + FormatLen(
              Sqrt(Sqr(T.X) + Sqr(T.Y) + Sqr(T.Z)), FD.Units) +
              '.  Type 3x for three that far apart, or /3 to divide the run.';
          end
          else if FMoveRigid then
          begin
            { a part just built goes as one piece; nothing comes along,
              whatever corners it shared where it was made }
            FD.Doc.TranslateEnts(FSel, T);
            FCmdMsg := 'Placed.';
          end
          else if FDetachMove then
          begin
            { /detach: take it away alone, leaving what it was joined to.
              SketchUp always stretches, but a guide-like line should not
              drag other geometry along. }
            FD.Doc.TranslateEnts(FSel, T);
            FCmdMsg := 'Moved ' + FormatLen(
              Sqrt(Sqr(T.X) + Sqr(T.Y) + Sqr(T.Z)), FD.Units) +
              '   (on its own - nothing stretched to follow)';
          end
          else
          begin
            { every corner where a moving one sat travels too, so joined
              geometry stretches to follow }
            Tk := GetTickCount64;
            { whole groups first, each as one piece; then the loose corners }
            FD.Doc.TranslateEnts(FMoveGroupEnts, T);
            FD.Doc.MoveVerts(FMoveVerts, T);
            Took('move the corners', Tk);
            FCmdMsg := 'Moved ' + FormatLen(
              Sqrt(Sqr(T.X) + Sqr(T.Y) + Sqr(T.Z)), FD.Units);
          end;
          { Moving an edge changes what the edges enclose, so faces are rebuilt
            (which also stretches them).  A built part placed whole is the
            exception: rebuilding would cap its open duct ends, so its
            openings are seeded as seen instead. }
          Tk := GetTickCount64;
          if FMoveRigid then SeedRegions else RebuildFlatFaces;
          Took('work the faces out', Tk);
          Tk := GetTickCount64;
          RenderInk;
          Took('render', Tk);
          Tk := GetTickCount64;
          RecomposeAll;
          Took('recompose', Tk);
        end;
        SetLength(FMoveVerts, 0);
        FMoveCopy := False;
              WasRigid := FMoveRigid;
        ResetTool;
        FInput := '';
        { A placed built part is let go and the select tool comes back;
          left selected, the next click would pick it up again. }
        if WasRigid then
        begin
          SelectNone;
          SetTool(ptSelect);
          FCmdMsg := 'Placed.';
        end
        { what the move tool picked up by itself is released once moved; a
          selection the user made stays }
        else if FMoveTook and not FArray.Live then SelectNone;
        FMoveTook := False;
      end;

    ptPush, ptDrill:
      begin
        R := PushDistance;
        Stopped := False;
        FCmdMsg := '';
        { A drill goes through: the far end must land exactly on the far
          wall's plane or there is no tunnel (see TWorkDoc.ThroughDistance).
          With a typed depth it is a blind hole that deep, through any
          passages on the way (push/pull stops at the first).  Passages a
          blind hole crosses are not cut open into it yet. }
        DrillTyped := (FTool = ptDrill) and (FInput <> '') and ParseLen(FInput, FD.Units, L);
        if (FTool = ptDrill) and (Abs(R) > 1E-9) and not DrillTyped then
          R := FD.Doc.ThroughDistance(FPushFace, R);
        { a drill goes in, never out, whichever way the mouse drifted: the
          block's far wall says which way is in }
        if DrillTyped and (Abs(R) > 1E-9) then
        begin
          if Abs(FD.Doc.ThroughDistance(FPushFace, -1E-3) + 1E-3) > 1E-9 then R := -Abs(R)
          else if Abs(FD.Doc.ThroughDistance(FPushFace, 1E-3) - 1E-3) > 1E-9 then R := Abs(R);
        end;
        { push/pull stops at a tunnel already through the solid, as
          SketchUp's does; drill goes on, and crossing holes are cut open
          into each other }
        if (FTool = ptPush) and (Abs(R) > 1E-9) then
        begin
          L := BoreLimit(FD.Doc, FPushFace, R);
          if Abs(L) < Abs(R) - 1E-9 then
          begin
            R := L;
            Stopped := True;
          end;
        end;
        if Abs(R) > 1E-9 then
        begin
          PushUndo;
          if FD.Doc.PushPull(FPushFace, R) then
          begin
            FLastPush := R;      // so a double-click can repeat it
            { the click that finished this push is not the first half of a
              double-click; a quick second click would repeat the push }
            FClickT := 0;
            if (FTool = ptDrill) and (FD.Doc.LastBore >= 0) then
              if CutCrossingBores(FD.Doc, FD.Doc.LastBore) > 0 then
                FCmdMsg := 'Drilled through - the tunnels cut into each other.';
            { Every area the push made is known now (above all a tunnel's far
              end, an opening that must not be capped by the next rebuild).
              Pressed flat, the solid is a loose face again and whatever it
              stood on must be cut round it, or the two share a plane. }
            if FD.Doc.LastFlattened then RebuildFlatFaces;
            SeedRegions;
            SelectNone;
            RenderInk;
            RecomposeAll;
            if Stopped then
              FCmdMsg := 'Stopped at the tunnel, ' + FormatLen(Abs(R), FD.Units) +
                ' in.  Drill (B) goes on through.'
            else if FCmdMsg = '' then
            begin
              if (FTool = ptDrill) and DrillTyped then
                FCmdMsg := 'Drilled ' + FormatLen(Abs(R), FD.Units) +
                  ' in, and stopped there.'
              else if FTool = ptDrill then
                FCmdMsg := 'Drilled through, ' + FormatLen(Abs(R), FD.Units)
              else
                FCmdMsg := 'Pulled ' + FormatLen(Abs(R), FD.Units);
            end;
          end;
        end;
        FPushFace := -1;
        ResetTool;
      end;

    ptText:
      begin
        { Nothing typed is no note, but not a reason to put the tool away
          either: resetting would turn every following letter back into a
          tool shortcut. }
        if Trim(FInput) = '' then
        begin
          FCmdMsg := 'Type the note first, then move away and press Enter.';
          Exit;
        end;
        begin
          PushUndo;
          { FP1 is what the note is about; the cursor is where it goes.  The
            same point gives a plain label; moving away first adds a leader. }
          FD.Doc.AddNote(FCur, FP1, Trim(FInput), FInkColor);
          RenderInk;
          RecomposeAll;
          if Dist(FCur, FP1) > 1E-9 then
            FCmdMsg := 'Note added, pointing at where you started.'
          else
            FCmdMsg := 'Note added.  Next time, move away before Enter for ' +
              'a leader line.';
        end;
        ResetTool;
      end;

    ptDim:
      begin
        if (FDimArc >= 0) and DimRadialAt(RA, RB, RNote) then
        begin
          { a diameter or radius: on the circle, no offset }
          PushUndo;
          FD.Doc.AddDim(RA, RB, FInkColor, P3(0, 0, 0), RNote);
          RenderInk;
          RecomposeAll;
          FCmdMsg := IfThen(Copy(RNote, 1, 1) = 'R', 'Radius ', 'Diameter ') + FormatLen(Dist(RA, RB), FD.Units);
        end
        else if Dist(FP1, FP2) > 1E-9 then
        begin
          PushUndo;
          FD.Doc.AddDim(FP1, FP2, FInkColor, DimOffset3);
          RenderInk;
          RecomposeAll;
          FCmdMsg := 'Dimension ' + FormatLen(Dist(FP1, FP2), FD.Units);
        end;
        ResetTool;
      end;

    ptMeasure:
      begin
        if FStage = 1 then
        begin
          { A typed distance is the second click: the point lands that far
            along the run's direction and the guide goes down as a click
            leaves it. }
          FP2 := PreviewTarget;
          if Dist(FP1, FP2) < 1E-9 then
          begin
            FCmdMsg := 'Type how far, or click the second point.';
            Exit;
          end;
          FInput := '';
          LayGuide;
          FRunOK := True;
          FRunA := FP1;
          FRunB := FP2;
          FCmdMsg := RunReading(FP1, FP2) + '   /keep makes it a dimension';
          RenderInk;
          RecomposeAll;
        end;
        { That is the whole tape.  No third stage waits for Enter: one would
          leave a phantom rubber band and drop a dimension much later.  /keep
          makes a dimension of the run. }
        ResetTool;
      end;
    ptSelect, ptErase, ptOrbit: ;   // these act on the drag; nothing to commit
  end;
  pbScreen.Invalidate;
  pbCmd.Invalidate;
  pbDeck.Invalidate;
  FLastStatus := 0;
  InvalidateStatus;
end;

{ What a run measures, in trade terms: length and components, plus the fall
  (degrees off level; 0 level, 90 a riser) and the swing (heading in plan
  from the red axis), which together describe a rolling offset.  Two
  decimals, since 44.98 vs 45 is the error worth seeing. }
function TMainForm.RunReading(const A, B: TP3): string;
var
  DX, DY, DZ, Flat, Fall, Swing: Double;
begin
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  DZ := B.Z - A.Z;
  Result := Format('%s   (dX %s  dY %s  dZ %s)',
    [FormatLen(Dist(A, B), FD.Units), FormatLen(Abs(DX), FD.Units),
     FormatLen(Abs(DY), FD.Units), FormatLen(Abs(DZ), FD.Units)]);

  Flat := Sqrt(DX * DX + DY * DY);
  if (Flat < 1E-9) and (Abs(DZ) < 1E-9) then Exit;

  if Flat < 1E-9 then
    Result := Result + '   straight up'
  else
  begin
    Fall := RadToDeg(ArcTan2(DZ, Flat));
    Swing := RadToDeg(ArcTan2(DY, DX));
    if Swing < 0 then Swing := Swing + 360;
    if Abs(Fall) < 1E-4 then
      Result := Result + '   level'
    else
      Result := Result + Format('   %.2f' + #176 + ' off level',
        [Abs(Fall)]);
    Result := Result + Format(',  %.2f' + #176 + ' round', [Swing]);
  end;
end;

{ everything after the first word, exactly as typed, for path arguments }
function RawTail(const S: string): string;
var
  P: Integer;
begin
  P := Pos(' ', Trim(S));
  if P <= 0 then Result := ''
  else Result := Trim(Copy(Trim(S), P + 1, MaxInt));
end;

{ The typed commands. }
function TMainForm.RunCommand(const S: string): Boolean;
var
  ReDoomed: array of Boolean;
  W, Rest: string;
  P, I, N, J, K: Integer;
  RL, RL2: Double;
begin
  Result := True;
  W := LowerCase(Trim(S));
  Rest := '';
  P := Pos(' ', W);
  if P > 0 then
  begin
    Rest := Trim(Copy(W, P + 1, MaxInt));
    W := Copy(W, 1, P - 1);
  end;

  { however it arrived (typed, picked, menu), it counts as used }
  { by its canonical name, so /e and /erase are one entry }
  I := CmdIndex(W);
  if I >= 0 then NoteCmdUsed(CMD_LIST[I].Name);

  if (W = 'line') or (W = 'l') then SetTool(ptLine)
  else if (W = 'select') or (W = 's') then SetTool(ptSelect)
  else if (W = 'move') or (W = 'mv') then SetTool(ptMove)
  else if (W = 'arc') or (W = 'a') then SetTool(ptArc)
  else if (W = 'circle') or (W = 'c') then SetTool(ptCircle)
  else if (W = 'text') or (W = 'note') or (W = 'n') then SetTool(ptText)
  else if (W = 'erase') or (W = 'e') or (W = 'del') then SetTool(ptErase)
  else if (W = 'orbit') or (W = 'spin') then SetTool(ptOrbit)
  { a size for the picked dimension; a bare length does this too, the
    command is for the other end and for scripts }
  else if (W = 'resize') or (W = 'size') then
  begin
    if SelectedDim < 0 then
      FCmdMsg := 'Pick one dimension first, then say what it should read.'
    else
    begin
      { "14' start" or "14' other" moves the end it was drawn from }
      W := Trim(Rest);
      I := LastDelimiter(' ', W);
      N := 1;                            { 1 = the end it was drawn to }
      if I > 0 then
      begin
        Rest := Trim(Copy(W, I + 1, MaxInt));
        if (Rest = 'start') or (Rest = 'first') or (Rest = 'other') or
           (Rest = 'a') or (Rest = 'from') then
        begin
          N := 0;
          W := Trim(Copy(W, 1, I - 1));
        end;
      end;
      if not ParseLen(W, FD.Units, RL) then
        FCmdMsg := 'I could not read "' + W + '" as a size.'
      else
        ApplyDimResize(RL, N = 1);
    end;
  end
  { the same as the right-click menu, for keyboard and scripts }
  else if (W = 'reverse') or (W = 'rev') or (W = 'flip') then
  begin
    N := 0;
    for I := 0 to High(FSel) do
      if FD.Doc[FSel[I]].Kind = ekFace then Inc(N);
    if N = 0 then
      FCmdMsg := 'Pick a face first - reverse turns over the faces you have selected.'
    else
    begin
      PushUndo;
      N := ReverseSelectedFaces;
      if N = 1 then FCmdMsg := 'Face turned over.'
      else FCmdMsg := Format('%d faces turned over.', [N]);
    end;
  end
  else if (W = 'group') or (W = 'makegroup') then MakeGroup
  else if (W = 'explode') or (W = 'ungroup') then ExplodeGroups
  else if (W = 'edit') or (W = 'opengroup') then
  begin
    if SoleGroup > 0 then OpenGroup(SoleGroup)
    else FCmdMsg := 'Pick one group first - or double-click it.';
  end
  else if (W = 'leave') or (W = 'closegroup') then
  begin
    if FD.Doc.Context <> 0 then CloseGroup
    else FCmdMsg := 'No group is open.';
  end
  else if (W = 'hide') or (W = 'putaway') then
    { the name as typed; groups match it whatever the case }
    if Rest = '' then HideGroups(True, '')
    else HideGroups(True, Copy(Trim(S), Pos(' ', Trim(S)) + 1, MaxInt))
  else if (W = 'show') or (W = 'unhide') then
    if Rest = '' then HideGroups(False, '')
    else HideGroups(False, Copy(Trim(S), Pos(' ', Trim(S)) + 1, MaxInt))
  else if W = 'lock' then LockGroups(True)
  else if W = 'unlock' then LockGroups(False)
  else if (W = 'name') or (W = 'rename') then
    { the name as typed, not lowercased with the command }
    if Rest = '' then RenameGroup('')
    else RenameGroup(Copy(Trim(S), Pos(' ', Trim(S)) + 1, MaxInt))
  else if (W = 'rect') or (W = 'rectangle') or (W = 'r') then SetTool(ptRect)
  else if (W = 'measure') or (W = 'm') or (W = 'tape') then SetTool(ptMeasure)
  else if (W = 'dimension') or (W = 'dim') then SetTool(ptDim)
  else if (W = 'offset') or (W = 'f') then SetTool(ptOffset)
  else if (W = 'rotate') or (W = 'q') or (W = 'turn') then SetTool(ptRotate)
  else if (W = 'protractor') or (W = 'angle') then SetTool(ptProtractor)
  else if (W = 'drill') or (W = 'bore') or (W = 'punch') then SetTool(ptDrill)
  { the tool is REVOLVE; Follow Me (SketchUp's name) still works }
  else if (W = 'revolve') or (W = 'followme') or (W = 'follow') or
          (W = 'lathe') then SetTool(ptFollow)
  { not /new here: that is a new sheet further down, and the first match
    wins }
  else if (W = 'whatsnew') or (W = 'changes') then ShowWhatsNew
  else if (W = 'transition') or (W = 'trans') or (W = 'fitting') or (W = 'elbow') or (W = 'tee') then BuildTransitionWizard
  else if (W = 'spool') or (W = 'pipe') or (W = 'scratchpad') then BuildSpoolWizard
  else if (W = 'stairs') or (W = 'stair') then BuildStairWizard
  else if (W = 'radiant') or (W = 'pex') or (W = 'hydronic') then BuildRadiantWizard
  else if W = 'rendertime' then RenderTiming
  else if W = 'quick' then
  begin
    FQuickFrames := not FQuickFrames;
    FCameraMoving := False;
    RepaintPaper; RenderInk; RecomposeAll; Invalidate;
    if FQuickFrames then FCmdMsg := 'Quick frames while the camera moves: on.'
    else FCmdMsg := 'Quick frames while the camera moves: off - every frame at full quality.';
  end
  else if W = 'threads' then
  begin
    FThreads := not FThreads;
    DefaultThreads := FThreads;
    for I := 0 to High(FDrawings) do FDrawings[I].Doc.Threads := FThreads;
    RenderInk; RecomposeAll; Invalidate;
    if FThreads then FCmdMsg := 'Worker threads: on - the lines-on-faces cache is built off the main thread.'
    else FCmdMsg := 'Worker threads: off - everything on the main thread.';
  end
  else if (W = 'report') or (W = 'bug') then ReportBug('', '', '')
  else if W = 'touch' then
    FCmdMsg := Format('Touch: hook %s, %d events so far, %d fingers down.',
      [BoolToStr(FTouchOn, True), FTouchCount, Length(FTouches)])
  else if (W = 'sysinfo') or (W = 'machine') then
  begin
    { what a report would say about this machine, to see before sending }
    FCmdMsg := 'That is what goes with a report about this machine.';
    WriteLn(MachineText);
    Flush(Output);
    Trail('machine:' + LineEnding + MachineText);
    ShowFacts('This machine, as a report says it', MachineText);
  end
  { for testing: what an update does at the end, without the update.  Start
    again with --updated to see the drawings come back. }
  else if W = 'handoff' then
  begin
    SaveDraft;
    WriteHandoff;
    FHandingOver := True;
    Close;
  end
  else if W = 'state' then
  begin
    { the rest of a report: what the program is doing and how it is set }
    FCmdMsg := 'That is what goes with a report about the program right now.';
    WriteLn(DiagnosticText);
    WriteLn(SettingsText);
    Flush(Output);
    ShowLongText('The program, as a report says it',
      DiagnosticText + LineEnding + SettingsText);
  end
  else if W = 'timings' then
  begin
    { on, do the slow thing, off: turning it off shows what it saw.
      "/timings show" looks without stopping. }
    if Rest = 'show' then
      ShowTimingLog
    else
    begin
      FTimings := not FTimings;
      if FTimings then
      begin
        FTimingLog := nil;
        FCmdMsg := 'Step timings on.  Do the slow thing, then /timings again to see them.';
      end
      else
      begin
        FCmdMsg := 'Step timings off.';
        ShowTimingLog;
      end;
    end;
  end
  else if (W = 'all') or (W = 'selectall') then
  begin
    SelectNone;
    BeginBulkSelect;
    for I := 0 to FD.Doc.Live - 1 do
      if FD.Doc[I].Kind in [ekLine, ekArc, ekFace, ekDim, ekText] then SelectAdd(I);
    EndBulkSelect;
    FCmdMsg := Format('%d things selected.', [Length(FSel)]);
    pbScreen.Invalidate;
  end
  else if (W = 'update') or (W = 'upgrade') then
  begin
    if Rest = 'never' then
    begin
      with TIniFile.Create(ConfigFile) do
      try
        WriteBool('update', 'check', False);
      finally
        Free;
      end;
      FCmdMsg := 'It will not look for updates again.  /update still works ' +
        'when you ask it to.';
    end
    else if Rest = 'always' then
    begin
      with TIniFile.Create(ConfigFile) do
      try
        WriteBool('update', 'check', True);
      finally
        Free;
      end;
      FCmdMsg := 'It will look once a day again.';
    end
    else
      DoUpdate;
  end
  else if W = 'version' then FCmdMsg := 'Heckers Sketch ' + CurrentVersion
  else if (W = 'push') or (W = 'pull') or (W = 'pushpull') or (W = 'p') then
    SetTool(ptPush)
  else if (W = 'undo') or (W = 'u') then DoUndo
  else if W = 'redo' then DoRedo
  { the shop tool by name; the SHOP list is the discoverable way in }
  else if (W = 'unfold') or (W = 'layout') then StartUnfold
  else if (W = 'fit') or (W = 'zoom') then FitView
  else if W = 'view' then CycleViewPreset(1)
  else if (W = 'top') or (W = 'down') then ApplyViewPreset(10)
  else if W = 'front' then ApplyViewPreset(6)
  else if W = 'right' then ApplyViewPreset(7)
  else if W = 'back' then ApplyViewPreset(8)
  else if W = 'left' then ApplyViewPreset(9)
  else if W = 'corner' then ApplyViewPreset(2)
  else if W = 'iso' then SetView(vkIso)
  { /orbit is the orbit tool, above; this is only reached by /3d }
  else if W = '3d' then SetView(vkOrbit)
  else if (W = 'plan') or (W = '2d') or (W = 'flat') then SetView(vkPlan)
  { the slice: "/cut off", "/cut all", or "/cut 0 9'" for bottom and top }
  else if (W = 'cut') or (W = 'slice') then
  begin
    if (Rest = 'off') or (Rest = 'none') then
      SetSlice(False, FD.SliceLo, FD.SliceHi)
    else if (Rest = 'all') or (Rest = 'whole') then
    begin
      if FD.Doc.ZRange(RL, RL2) then SetSlice(True, RL, RL2)
      else FCmdMsg := 'Nothing on this sheet to measure.';
    end
    else if Rest = '' then
      FCmdMsg := SliceText + '.  "/cut 0 9''" sets it, "/cut all" opens it ' +
                 'right up, "/cut off" turns it off.'
    else
    begin
      P := Pos(' ', Rest);
      if P <= 0 then
        FCmdMsg := 'Two heights, a bottom and a top - "/cut 0 9''".'
      else if not ParseLen(Trim(Copy(Rest, 1, P - 1)), FD.Units, RL) then
        FCmdMsg := 'I could not read "' + Trim(Copy(Rest, 1, P - 1)) + '" as a height.'
      else if not ParseLen(Trim(Copy(Rest, P + 1, MaxInt)), FD.Units, RL2) then
        FCmdMsg := 'I could not read "' + Trim(Copy(Rest, P + 1, MaxInt)) + '" as a height.'
      else
      begin
        if FD.View <> vkPlan then SetView(vkPlan);
        SetSlice(True, RL, RL2);
      end;
    end;
  end
  else if W = 'plane' then
  begin
    if Rest = 'xz' then FD.Plane := plXZ
    else if Rest = 'yz' then FD.Plane := plYZ
    else if Rest = 'xy' then FD.Plane := plXY
    else FD.Plane := TPlane((Ord(FD.Plane) + 1) mod 3);
    FCmdMsg := 'Working plane: ' + Copy('XYXZYZ', Ord(FD.Plane) * 2 + 1, 2);
  end
  else if (W = 'origin') or (W = 'o') then SetOriginHere
  else if W = 'grid' then
  begin
    FShowGrid := not FShowGrid;
    RepaintPaper;
    RecomposeAll;
    pbDeck.Invalidate;
  end
  else if W = 'regions' then ReportRegions
  else if W = 'forget' then
  begin
    { for testing: forget every area ever seen, then rebuild the faces }
    PushUndo;
    SetLength(FD.Seen, 0);
    I := RebuildFlatFaces;
    RenderInk;
    RecomposeAll;
    FCmdMsg := Format('Forgot what was seen and worked the faces out again: %d.', [I]);
  end
  else if (W = 'center') or (W = 'middle') then
    CenterSelection
  { the near bottom corner on the origin.  Not /corner, which is a view. }
  else if (W = 'tozero') or (W = 'zero') or (W = 'tuck') then
    CornerSelection
  { /keep: the tape's last run as a dimension.  A command so it cannot
    happen by accident. }
  else if (W = 'keep') or (W = 'keepdim') then
  begin
    if not FRunOK then
      FCmdMsg := 'Nothing measured yet.  Take the tape across something ' +
        'first, then /keep writes that run on the drawing.'
    else if Dist(FRunA, FRunB) < 1E-9 then
      FCmdMsg := 'That run was no length at all.'
    else
    begin
      PushUndo;
      FD.Doc.AddDim(FRunA, FRunB, FInkColor, DimOffset3);
      RenderInk;
      RecomposeAll;
      FCmdMsg := 'Kept as a dimension: ' + FormatLen(Dist(FRunA, FRunB), FD.Units) + '.';
    end;
  end
  { the groups and entity panels; commands, since the bottom row is full }
  else if (W = 'groups') or (W = 'outliner') then
  begin
    if Rest = 'on' then SetGroupsPanel(True)
    else if Rest = 'off' then SetGroupsPanel(False)
    else SetGroupsPanel(not FGroupsOn);
  end
  else if (W = 'info') or (W = 'entity') or (W = 'properties') then
  begin
    if Rest = 'on' then FInfoOn := True
    else if Rest = 'off' then FInfoOn := False
    else FInfoOn := not FInfoOn;
    FInfoSig := -1;
    Relayout;
    if FInfoOn then
    begin
      RebuildInfo;
      pbInfo.Invalidate;
      FCmdMsg := 'The entity panel is on the right.  Pick something to see ' +
        'what it is; a few of the figures can be changed from there.';
    end
    else
      FCmdMsg := 'Entity panel off.  /info brings it back.';
    Invalidate;
  end
  else if (W = 'detach') or (W = 'loose') then
  begin
    if Rest = 'on' then FDetachMove := True
    else if Rest = 'off' then FDetachMove := False
    else FDetachMove := not FDetachMove;
    if FDetachMove then
      FCmdMsg := 'A move takes what is picked away on its own now.  ' +
        'Nothing it is joined to will stretch to follow.  /detach off puts ' +
        'that back.'
    else
      FCmdMsg := 'A move stretches what it is joined to again, which is how ' +
        'SketchUp does it.';
  end
  else if (W = 'postcard') or (W = 'hello') then
  begin
    hsDialogSkin.UseTheme(Themes[FThemeIdx]);
    OfferPostcard(Self, CurrentVersion, True);
  end
  else if (W = 'light') or (W = 'lamp') then
  begin
    if (Rest = 'on') or (Rest = 'off') then CameraLamp := Rest = 'on'
    else if Rest = '' then CameraLamp := not CameraLamp
    else FCmdMsg := 'The light takes on or off.';
    if FCmdMsg = '' then
    begin
      if CameraLamp then
        FCmdMsg := 'The light follows the camera: the face turned towards ' +
                   'you is the bright one.  /light off for the old fixed lamp.'
      else
        FCmdMsg := 'The light is fixed, as it used to be: the same grays ' +
                   'from every angle.  /light on has it follow the camera.';
    end;
    RenderInk;
    RecomposeAll;
    FScreenDirty := True;
    pbScreen.Invalidate;
  end
  else if (W = 'source') or (W = 'src') or (W = 'text-view') then
  begin
    ShowSource;
    { "/source sample" loads the sample, "/source apply" presses Apply }
    if Rest = 'sample' then SourceForm.LoadSample
    else if Rest = 'apply' then SourceForm.ApplyNow
    { "/source complete off": the word list only on Ctrl+Space; remembered }
    else if (Rest = 'complete off') or (Rest = 'complete on') then
    begin
      FSourceComplete := Rest = 'complete on';
      SourceForm.SetAutoComplete(FSourceComplete);
      if FSourceComplete then
        FCmdMsg := 'The source window offers words as you type.  /source complete off stops it.'
      else
        FCmdMsg := 'The source window offers words only on Ctrl+Space.  /source complete on brings them back.';
    end
    else if Rest <> '' then FCmdMsg := '/source takes sample, apply, complete on or complete off.';
  end
  else if (W = 'jig') or (W = 'jigs') then
  begin
    if SoleGroup > 0 then
    begin
      if RunJigOf(SoleGroup) then
      begin
        RebuildFlatFaces;
        FCmdMsg := 'The jig was run again.';
      end;
      RenderInk;
      RecomposeAll;
    end
    else
      RunAllJigs;
    pbScreen.Invalidate;
  end
  else if (W = 'cube') or (W = 'viewcube') then
  begin
    FCubeHasHot := False;
    if (Rest = 'on') or (Rest = 'off') then
      FCubeOn := Rest = 'on'
    else if (Rest = 'tl') or (Rest = 'tr') or (Rest = 'bl') or (Rest = 'br') then
    begin
      if Rest = 'tl' then FCubeCorner := 0
      else if Rest = 'tr' then FCubeCorner := 1
      else if Rest = 'bl' then FCubeCorner := 2
      else FCubeCorner := 3;
      FCubeOn := True;
      FCmdMsg := 'The cube is ' + CORNER_NAME[FCubeCorner] + '.';
    end
    else if Copy(Rest, 1, 12) = 'fitselection' then
    begin
      N := Pos(' ', Rest);
      if N > 0 then Rest := Trim(Copy(Rest, N + 1, MaxInt)) else Rest := '';
      if Rest = 'off' then FCubeFitSel := False
      else if Rest = 'on' then FCubeFitSel := True
      else FCubeFitSel := not FCubeFitSel;
      if FCubeFitSel then
        FCmdMsg := 'A cube click brings what is picked into the middle and ' +
                   'sizes it.  With nothing picked it just goes to the view.'
      else
        FCmdMsg := 'A cube click goes to the view and leaves the framing alone.';
    end
    else if Rest <> '' then
      FCmdMsg := 'The cube takes on, off, tl, tr, bl, br, or ' +
                 'fitselection on/off.'
    else
      FCubeOn := not FCubeOn;

    if FCmdMsg = '' then
    begin
      if FCubeOn and (FD <> nil) and (FD.View <> vkOrbit) then
        FCmdMsg := 'The cube is on - it shows in a 3D view, and this is not ' +
                   'one.  /3d, or the VIEW button.'
      else if FCubeOn then
        FCmdMsg := 'The cube is on, ' + CORNER_NAME[FCubeCorner] +
                   '.  Click a face, an edge or a corner to look from there; ' +
                   'drag it to turn.'
      else
        FCmdMsg := 'The cube is off.';
    end;
    FScreenDirty := True;
    Relayout;
    pbScreen.Invalidate;
  end
  else if (W = 'holes') or (W = 'openedges') or (W = 'notclosed') then
  begin
    ShowOpenEdges;
  end
  else if W = 'rebuild' then
  begin
    PushUndo;
    I := RebuildFlatFaces;
    RenderInk;
    RecomposeAll;
    if FTurned > 0 then
      FCmdMsg := Format('Worked the faces out again: %d, and turned %d of ' +
        'them the right way out.', [I, FTurned])
    else
      FCmdMsg := Format('Worked the faces out again: %d.', [I]);
  end
  else if (W = 'rebuildfaces') or (W = 'reface') then
  begin
    { Throw the flat faces away and rebuild them from the lines, for files
      whose faces no longer match their lines.  Solid faces are kept: they
      were pulled out of a face and have no lines under them to rebuild
      from, so deleting them would lose them for good. }
    PushUndo;
    SetLength(ReDoomed, FD.Doc.Live);
    J := 0;
    K := 0;
    for I := 0 to FD.Doc.Live - 1 do
    begin
      ReDoomed[I] := (FD.Doc[I].Kind = ekFace) and not FD.Doc[I].Solid;
      if ReDoomed[I] then Inc(J)
      else if FD.Doc[I].Kind = ekFace then Inc(K);
    end;
    FD.Doc.DeleteMarked(ReDoomed);
    SetLength(FD.Seen, 0);
    I := RebuildFlatFaces;
    RenderInk;
    RecomposeAll;
    if K > 0 then
      FCmdMsg := Format('Threw %d flat faces away and worked out %d from the ' +
        'lines.  Left %d alone that belong to a solid - there are no lines ' +
        'under those to work them out from.', [J, I, K])
    else
      FCmdMsg := Format('Threw the faces away and worked them out from the ' +
        'lines: %d.', [I]);
  end
  else if (W = 'guides') or (W = 'noguides') then
  begin
    { SketchUp's Edit > Delete Guides }
    I := FD.Doc.GuideCount;
    if I = 0 then
      FCmdMsg := 'No guides to clear.'
    else
    begin
      PushUndo;
      FD.Doc.ClearGuides;
      RenderInk;
      RecomposeAll;
      FCmdMsg := Format('Cleared %d guide%s.', [I, IfThen(I = 1, '', 's')]);
    end;
  end
  else if W = 'units' then SetUnits(TUnitSystem(1 - Ord(FD.Units)))
  else if (W = 'new') or (W = 'tab') then NewDrawing(-1)
  else if W = 'sheet' then AddSheetHere
  else if W = 'saveall' then DoSaveAll
  else if W = 'example' then
  begin
    NewDrawing(-1);
    LoadExample;
  end
  else if W = 'close' then CloseDrawing(FTabIdx)
  else if W = 'clear' then StartErase
  else if W = 'save' then DoSave
  else if (W = 'saveas') or (W = 'save-as') then DoSaveAs
  else if W = 'print' then
  begin
    if (Rest = 'full') or (Rest = '1:1') or (Rest = 'fullsize') or
       (Rest = 'full size') then DoPrintFull('')
    else if (Rest = 'all') or (Rest = 'sheets') then DoPrintSheets(True)
    else DoPrint;
  end
  { the same tiles as pictures, for a print shop or a preview }
  else if (W = 'tiles') and (Rest <> '') then DoPrintFull(RawTail(S))
  else if W = 'scale' then
  begin
    for I := 0 to SCALE_COUNT - 1 do
      if LowerCase(ScaleTable(FD.Units, I).Name) = Rest then
      begin
        SetScaleIdx(I);
        Exit;
      end;
    FCmdMsg := 'Scales: 1/16" 1/8" 1/4" 1/2" 1"';
  end
  { A path keeps its case: the command is lowercased, so take the tail from
    the line as typed. }
  else if W = 'replay' then
    DoReplayFile(RawTail(S))
  else if (W = 'session') or (W = 'acts') then
  begin
    { What has been recorded so far, the same lines a report carries, ready
      for /replay.  The path keeps its case, as for /replay. }
    Rest := RawTail(S);
    if Rest = '' then Rest := 'session.txt';
    try
      with TStringList.Create do
      try
        Text := ActsText;
        SaveToFile(Rest);
        FCmdMsg := Format('%d actions written to %s', [Count, Rest]);
      finally
        Free;
      end;
    except
      on E: Exception do FCmdMsg := 'Could not write it: ' + E.Message;
    end;
  end
  else if (W = 'manual') or (W = 'docs') then OpenManual
  else if (W = 'help') or (W = '?') then ShowAbout
  else
    Result := False;
end;

procedure TMainForm.CommandEnter;
var
  L: Double;
  Why: string;
  SidesN, ArrN: Integer;
  ArrDiv: Boolean;
begin
  { Record the typing and the Enter, which turn a direction into a measured
    run.  A /command is not recorded: its setter records what it changes,
    and /session and /replay must not run again inside a replay. }
  if Copy(FInput, 1, 1) <> '/' then
  begin
    if FInput <> '' then Act('input ' + FInput);
    Act('enter');
  end;
  if FDimEdit >= 0 then
  begin
    CommitDimNote;
    pbCmd.Invalidate;
    Exit;
  end;
  { a cut field is open, so what was typed is a height for it }
  if FSliceEdit <> 0 then
  begin
    CommitSliceEdit;
    pbCmd.Invalidate;
    Exit;
  end;

  if (FTool = ptText) and (FStage = 1) then
  begin
    ToolCommit;
    Exit;
  end;

  { picking the stairs: a length typed is the run, then the width }
  if (FStairPick > 0) and (Copy(FInput, 1, 1) <> '/') then
  begin
    StairTyped;
    Exit;
  end;

  if FInput = '' then
  begin
    if FStage > 0 then ToolCommit else ToolClick;
    Exit;
  end;

  if FArray.Live and ArrayCommand(FInput, ArrN, ArrDiv) then
  begin
    FInput := '';
    ApplyArray(ArrN, ArrDiv);
    Exit;
  end;

  if Copy(FInput, 1, 1) = '/' then
  begin
    if not RunCommand(Copy(FInput, 2, MaxInt)) then
      FCmdMsg := 'I do not know "' + Copy(FInput, 2, MaxInt) + '"';
    FInput := '';
    pbCmd.Invalidate;
    Exit;
  end;

  { 24s or s24 on the circle or arc tool: how many sides, not how big }
  if (FTool in [ptCircle, ptArc]) and ParseSides(FInput, SidesN) then
  begin
    if FTool = ptCircle then FSidesCircle := SidesN else FSidesArc := SidesN;
    FCmdMsg := Format('%d sides from now on.', [SidesN]);
    FInput := '';
    pbCmd.Invalidate;
    pbScreen.Invalidate;
    Exit;
  end;

  { Not every entry is a plain length (8',20' for a rectangle, [x,y,z] and
    <x,y,z> for move and line).  Anything that starts like a measurement goes
    to the tool; bare words fall through to the command list. }
  if (FStage > 0) and (FInput <> '') and
     (FInput[1] in ['0'..'9', '-', '.', '[', '<', ',', 'x', 'X']) then
  begin
    { An unreadable number must not silently commit at the cursor.  This is
      also where the dashed notation (6-8-15) can explain itself. }
    Why := WhyNotAMeasurement(FInput);
    if Why <> '' then
    begin
      FCmdMsg := Why;
      pbCmd.Invalidate;
      pbScreen.Invalidate;
      Exit;
    end;
    ToolCommit;
    FInput := '';
    pbCmd.Invalidate;
    Exit;
  end;

  if ParseLen(FInput, FD.Units, L) then
  begin
    if FStage > 0 then
      ToolCommit
    { a dimension picked and a length typed: what it should read.  Typing a
      length and Enter is how every size is given here. }
    else if (SelectedDim >= 0) and ApplyDimResize(L, True) then
      { already reported }
    else if SelectedDim >= 0 then
      { refused, and said why }
    else if (SelectedLine >= 0) and ApplyLineLength(L) then
      { a picked line: its length, SketchUp's Entity Info way }
    else
      FCmdMsg := FInput + ' = ' + FormatLen(L, FD.Units) + ' (pick a start point first)';
    FInput := '';
    pbCmd.Invalidate;
    Exit;
  end;

  if RunCommand(FInput) then
    FInput := ''
  else
    FCmdMsg := 'I do not know "' + FInput + '"';
  pbCmd.Invalidate;
end;

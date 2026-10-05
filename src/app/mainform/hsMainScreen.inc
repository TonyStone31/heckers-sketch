{ hsMainForm - drawing the screen.  Part of TMainForm; included by hsMainForm.pas }

{ ======================================================================== }
{ the screen                                                                }
{ ======================================================================== }

{ How much drawn ink a rectangle would hide, sampled every fourth pixel each
  way since it runs on every mouse move.  The ink surface, not the finished
  picture, so the paper grid does not count. }
function TMainForm.InkUnder(const R: TRect): Integer;
var
  X, Y, X0, X1, Y1: Integer;
  P: PPix;
  Ink: TArtSurface;
begin
  Result := 0;
  Ink := FInk;
  if Ink = nil then Exit;
  X0 := Max(0, R.Left);
  X1 := Min(R.Right, Ink.Width);
  Y1 := Min(R.Bottom, Ink.Height);
  Y := Max(0, R.Top);
  while Y < Y1 do
  begin
    P := Ink.ScanLine(Y);
    X := X0;
    while X < X1 do
    begin
      if (P + X)^.A > 8 then Inc(Result);
      Inc(X, 4);
    end;
    Inc(Y, 4);
  end;
end;

{ a dotted line the cursor is on, for the chip to keep off (see TipOnLine) }
procedure TMainForm.TipAvoid(X0, Y0, X1, Y1: Integer);
begin
  SetLength(FTipLines, Length(FTipLines) + 1);
  FTipLines[High(FTipLines)] := Rect(X0, Y0, X1, Y1);
end;

{ Dotted lines are drawn after the ink, so InkUnder cannot see them; a
  corner one crosses costs more than any amount of drawing. }
function TMainForm.TipOnLine(const R: TRect): Integer;
var
  K, N, I: Integer;
  X, Y: Double;
  Grown: TRect;
begin
  Result := 0;
  Grown := Rect(R.Left - 4, R.Top - 4, R.Right + 4, R.Bottom + 4);
  for K := 0 to High(FTipLines) do
  begin
    { walked a few pixels at a time; a chip is never thinner than that }
    N := Max(1, Max(Abs(FTipLines[K].Right - FTipLines[K].Left), Abs(FTipLines[K].Bottom - FTipLines[K].Top)) div 3);
    for I := 0 to N do
    begin
      X := FTipLines[K].Left + (FTipLines[K].Right - FTipLines[K].Left) * I / N;
      Y := FTipLines[K].Top + (FTipLines[K].Bottom - FTipLines[K].Top) * I / N;
      if (X >= Grown.Left) and (X <= Grown.Right) and (Y >= Grown.Top) and (Y <= Grown.Bottom) then
      begin
        Inc(Result, 100000);
        Break;
      end;
    end;
  end;
end;

{ Where to put the chip beside the cursor: the candidate corner covering
  least of the drawing.  Candidates are clamped inside the canvas before
  judging.  The current corner must be beaten by a clear margin, or it
  flips sides on every pixel when two are close. }
function TMainForm.TipSpot(SX, SY, BoxW, BoxH: Integer): TRect;
var
  K, Gap, AX, AY, Sc, Best, BestK, Cur: Integer;
  Cand: array[0..7] of TRect;
begin
  { Four corners close in, and the same four further out for when every near
    corner is crowded.  Near first and strictly better, so a far corner only
    wins by covering less. }
  for K := 0 to 7 do
  begin
    if K < 4 then Gap := Round(16 * FUIScale)
    else Gap := Round(96 * FUIScale);
    if (K and 1) = 0 then AX := SX + Gap else AX := SX - Gap - BoxW;
    if (K and 2) = 0 then AY := SY + Gap else AY := SY - Gap - BoxH;
    AX := EnsureRange(AX, 4, Max(4, pbScreen.Width - BoxW - 4));
    AY := EnsureRange(AY, 4, Max(4, pbScreen.Height - BoxH - 4));
    Cand[K] := Rect(AX, AY, AX + BoxW, AY + BoxH);
  end;

  FTipCorner := EnsureRange(FTipCorner, 0, 7);
  Cur := InkUnder(Cand[FTipCorner]) + TipOnLine(Cand[FTipCorner]);
  Best := Cur;
  BestK := FTipCorner;
  for K := 0 to 7 do
  begin
    if K = FTipCorner then Continue;
    Sc := InkUnder(Cand[K]) + TipOnLine(Cand[K]);
    if Sc < Best then
    begin
      Best := Sc;
      BestK := K;
    end;
  end;
  { a third less covered, and enough difference to be worth the jump }
  if (BestK <> FTipCorner) and (Best * 3 < Cur * 2) and (Cur - Best > 12) then
    FTipCorner := BestK;
  Result := Cand[FTipCorner];
end;

function TMainForm.SnapLabel: string;
const
  { named by color, like the axis inferences }
  AXIS_LABEL: array[0..2] of string =
    ('LOCKED TO RED', 'LOCKED TO GREEN', 'LOCKED TO BLUE');
begin
  if FAxisLock in [0..2] then Exit(AXIS_LABEL[FAxisLock]);
  { SketchUp's magenta pair, by its names }
  if FParPerp = 1 then Exit('PARALLEL TO EDGE');
  if FParPerp = 2 then Exit('PERPENDICULAR TO EDGE');
  case FSnapKind of
    snEndpoint: Result := 'ENDPOINT';
    snMidpoint: Result := 'MIDPOINT';
    snSubMid:   Result := 'ON SEGMENT';
    snCenter:   Result := 'CENTER';
    snCross:    Result := 'CROSSING';
    snOnEdge:   Result := 'ON EDGE';
    snOnFace:   Result := 'ON FACE';
    snQuadrant: Result := 'QUADRANT';
    snOrigin:   Result := 'ORIGIN';
    snOnAxis:   case FSnapAxis of
                  0: Result := 'ON RED AXIS';
                  1: Result := 'ON GREEN AXIS';
                else Result := 'ON BLUE AXIS';
                end;
    snGrid:     Result := 'GRID';
  else
    Result := '';
  end;
end;

{ The rectangle's far corner.  Typing 12'x8' sets both sides; the cursor
  still says which way each goes. }
function TMainForm.RectTarget: TP3;
var
  I: Integer;
  Txt, LW, LH: string;
  W, H, SX, SY: Double;
begin
  Result := FCur;
  if FStage <> 1 then Exit;

  Txt := LowerCase(Trim(FInput));
  I := Pos('x', Txt);
  if I = 0 then I := Pos(',', Txt);
  if I = 0 then Exit;

  { As SketchUp: "3'," sets the first side and leaves the second to the
    cursor, ",3'" the other way.  A negative side runs the opposite way. }
  LW := Trim(Copy(Txt, 1, I - 1));
  LH := Trim(Copy(Txt, I + 1, MaxInt));
  RectSides(FP1, FCur, FD.Plane, W, H);
  if (LW <> '') and not ParseLen(LW, FD.Units, W) then Exit;
  if (LH <> '') and not ParseLen(LH, FD.Units, H) then Exit;
  if (LW = '') and (LH = '') then Exit;

  { sign from where the cursor is now }
  case FD.Plane of
    plXZ:
      begin
        if FCur.X < FP1.X then SX := -1 else SX := 1;
        if FCur.Z < FP1.Z then SY := -1 else SY := 1;
        if W < 0 then begin SX := -SX; W := -W; end;
        if H < 0 then begin SY := -SY; H := -H; end;
        Result := P3(FP1.X + W * SX, FP1.Y, FP1.Z + H * SY);
      end;
    plYZ:
      begin
        if FCur.Y < FP1.Y then SX := -1 else SX := 1;
        if FCur.Z < FP1.Z then SY := -1 else SY := 1;
        if W < 0 then begin SX := -SX; W := -W; end;
        if H < 0 then begin SY := -SY; H := -H; end;
        Result := P3(FP1.X, FP1.Y + W * SX, FP1.Z + H * SY);
      end;
  else
    begin
      if FCur.X < FP1.X then SX := -1 else SX := 1;
      if FCur.Y < FP1.Y then SY := -1 else SY := 1;
      if W < 0 then begin SX := -SX; W := -W; end;
      if H < 0 then begin SY := -SY; H := -H; end;
      Result := P3(FP1.X + W * SX, FP1.Y + H * SY, FP1.Z);
    end;
  end;
end;

{ Where the rubber band ends: a typed distance wins, then a locked
  direction, then the cursor. }
function TMainForm.PreviewTarget: TP3;
var
  L, Len, CX, CY, CZ: Double;
  Typed: Boolean;
  D: TP3;
  Txt: string;
  K: Integer;
  AlongL: Double;
begin
  Result := FCur;
  if FStage <> 1 then Exit;

  { [x,y,z] is a point in the drawing, <x,y,z> an offset from the start }
  Txt := Trim(FInput);
  if (Length(Txt) >= 2) and (Txt[1] in ['[', '<']) then
  begin
    if ParseTriple(Txt, FD.Units, CX, CY, CZ) > 0 then
    begin
      if Txt[1] = '[' then Result := P3(CX, CY, CZ)
      else Result := P3(FP1.X + CX, FP1.Y + CY, FP1.Z + CZ);
    end;
    Exit;
  end;

  Typed := (FInput <> '') and ParseLen(FInput, FD.Units, L);

  if FDirLock >= 0 then
  begin
    D := AxisDir(FDirLock);
    if not Typed then
      { no number yet: slide along the locked axis under the cursor, either
        direction }
      L := (FCur.X - FP1.X) * D.X + (FCur.Y - FP1.Y) * D.Y + (FCur.Z - FP1.Z) * D.Z;
    Result := P3(FP1.X + D.X * L, FP1.Y + D.Y * L, FP1.Z + D.Z * L);
    Exit;
  end;

  { On the iso paper grid the line is held to the three axes; an off-axis
    leg there is a slip of the hand.  Shift releases it for a 45 or a rolling
    offset.  Not Alt: Alt cycles the working plane. }
  if (FD.View = vkIso) and (FTool = ptLine) and
     not (ssShift in FMoveShift) then
  begin
    K := IsoRunAxis(FP1, AlongL);
    if K >= 0 then
    begin
      D := AxisDir(K);
      if not Typed then L := AlongL;
      Result := P3(FP1.X + D.X * L, FP1.Y + D.Y * L, FP1.Z + D.Z * L);
      Exit;
    end;
  end;

  { Green means green: when the band is drawn in an axis color (within
    AxisAlong's tolerance, about a degree) the point is squared onto that
    axis, keeping its distance along.  Otherwise a line could show green and
    be an eighth out over a foot, and nested rectangles would not close. }
  if FParPerp = 0 then
  begin
    { the axis the band is drawn in, by the same test the painter uses: a
      lock the resolver set, or a run lying along one }
    if FAxisLock in [0..2] then K := FAxisLock
    else if FInferMode = imAll then K := AxisAlong(FP1, Result)
    else K := -1;
    if K >= 0 then
    begin
      { K is an axis (0 X, 1 Y, 2 Z) but AxisDir counts directions, two per
        axis }
      D := AxisDir(K * 2);
      AlongL := (Result.X - FP1.X) * D.X + (Result.Y - FP1.Y) * D.Y + (Result.Z - FP1.Z) * D.Z;
      Result := P3(FP1.X + D.X * AlongL, FP1.Y + D.Y * AlongL, FP1.Z + D.Z * AlongL);
      FAxisLock := K;
      FAxisFrom := FP1;
    end;
  end;

  if Typed then
  begin
    D := Sub3(FCur, FP1);
    Len := Sqrt(D.X * D.X + D.Y * D.Y + D.Z * D.Z);
    if Len < 1E-9 then
    begin
      D := P3(1, 0, 0);
      Len := 1;
    end;
    Result := P3(FP1.X + D.X * L / Len, FP1.Y + D.Y * L / Len, FP1.Z + D.Z * L / Len);
  end;
end;

{ The dimension as it will be (witness lines, slashes, reading), from the
  same routine the renderer uses, so what you drag is what you get. }
procedure TMainForm.PaintDimPreview(C: TCanvas);
var
  G: TDimGeom;
  Sz: TSize;
  TP: TPoint;
  RA, RB: TP3;
  RNote: string;
begin
  if FDimArc >= 0 then
  begin
    if not DimRadialAt(RA, RB, RNote) or
       not DimGeometry(Proj, RA, RB, P3(0, 0, 0), FD.Units, G, RNote) then Exit;
    PaintDimEnds(C, RA, RB);
  end
  else
  begin
    if not DimGeometry(Proj, FP1, FP2, DimOffset3, FD.Units, G) then Exit;
    PaintDimEnds(C, FP1, FP2);
  end;
  C.Pen.Style := psSolid;
  C.Pen.Color := PixToColor(AnnotColor);
  C.Pen.Width := 1;
  C.MoveTo(Round(G.A.X), Round(G.A.Y));   C.LineTo(Round(G.W1.X), Round(G.W1.Y));
  C.MoveTo(Round(G.B.X), Round(G.B.Y));   C.LineTo(Round(G.W2.X), Round(G.W2.Y));
  C.Pen.Width := Max(1, Round(1.5 * FUIScale));
  C.MoveTo(Round(G.LA.X), Round(G.LA.Y));  C.LineTo(Round(G.LB.X), Round(G.LB.Y));
  C.MoveTo(Round(G.S1A.X), Round(G.S1A.Y)); C.LineTo(Round(G.S1B.X), Round(G.S1B.Y));
  C.MoveTo(Round(G.S2A.X), Round(G.S2A.Y)); C.LineTo(Round(G.S2B.X), Round(G.S2B.Y));
  C.Pen.Width := 1;
  C.Brush.Style := bsClear;
  UIFont(C, 9, False, AnnotColor);
  Sz := C.TextExtent(G.Txt);
  TP := DimTextTopLeft(G, Sz.cx, Sz.cy);
  C.TextOut(TP.X, TP.Y, G.Txt);
end;

{ The two points a dimension measures, as dots, so it is clear where it
  starts and stops (a face may be split into pieces). }
procedure TMainForm.PaintDimEnds(C: TCanvas; const A, B: TP3);
var
  P: TPointF;
  R, K: Integer;
begin
  R := Max(3, Round(4 * FUIScale));
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.Pen.Color := PixToColor(Theme.Screen1);
  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(HINT_BLUE);
  for K := 0 to 1 do
  begin
    if K = 0 then P := ScreenOf(A) else P := ScreenOf(B);
    C.Ellipse(Round(P.X) - R, Round(P.Y) - R, Round(P.X) + R + 1, Round(P.Y) + R + 1);
  end;
  C.Brush.Style := bsClear;
end;

{ what it will read, beside what it will measure, before the click }
procedure TMainForm.PaintDimTag(C: TCanvas; X, Y: Double; const S: string);
var
  Sz: TSize;
begin
  UIFont(C, 10, True, HINT_BLUE);
  Sz := C.TextExtent(S);
  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(Theme.Screen1);
  C.TextOut(Round(X - Sz.cx / 2), Round(Y - Sz.cy / 2), S);
  C.Brush.Style := bsClear;
end;

{ A point along a bent stick: the quadratic through A, the bowed middle M,
  and B.  Straight when M is halfway, which is what makes the bow read. }
function QuadAt(const A, M, B: TPointF; T: Double): TPointF;
var
  U: Double;
begin
  U := 1 - T;
  Result.X := U * U * A.X + 2 * U * T * M.X + T * T * B.X;
  Result.Y := U * U * A.Y + 2 * U * T * M.Y + T * T * B.Y;
end;

{ Is there a newer build?  Quiet unless there is, and at most every six
  hours; a drawing program should not ping a server on every launch. }
procedure TMainForm.CheckForUpdate(Loud: Boolean);
var
  Info: TUpdateInfo;
  Err, Last: string;
  Ini: TIniFile;
begin
  if not Loud then
  begin
    Ini := TIniFile.Create(ConfigFile);
    try
      { /update never turns this off for good.  It only asks GitHub for the
        newest release and sends nothing about the machine or the drawing. }
      if not Ini.ReadBool('update', 'check', True) then Exit;
      Last := Ini.ReadString('update', 'checked', '');
    finally
      Ini.Free;
    end;
    { six hours, not a calendar day, so a day of releases is not missed }
    if (Last <> '') and (Now - StrToFloatDef(Last, 0) < 0.25) then Exit;
  end;

  if not FetchLatest(Info, Err) then
  begin
    if Loud then FCmdMsg := 'Could not check for an update - ' + Err;
    Exit;
  end;

  Ini := TIniFile.Create(ConfigFile);
  try
    Ini.WriteString('update', 'checked', FloatToStr(Now));
    Ini.WriteString('update', 'latest', Info.Tag);
  finally
    Ini.Free;
  end;

  if NewerThan(Info.Tag, CurrentVersion) then
  begin
    FUpdateTag := Info.Tag;
    FCmdMsg := Info.Tag + ' is out - you have ' + CurrentVersion +
      '.  Type /update, or use the help button.';
    Invalidate;
    { Found at startup: offer it now, as /update would.  Not where this copy
      cannot update itself, not for a source build, and not twice for a
      declined version (that waits for /update). }
    if (not Loud) and (WhyNotUpdate = '') and (Pos('dev', LowerCase(CurrentVersion)) = 0) then
    begin
      Ini := TIniFile.Create(ConfigFile);
      try
        Last := Ini.ReadString('update', 'declined', '');
        if Last <> Info.Tag then Ini.WriteString('update', 'declined', Info.Tag);
      finally
        Ini.Free;
      end;
      if Last <> Info.Tag then
      begin
        pbCmd.Invalidate;
        DoUpdate;
        Exit;
      end;
    end;
  end
  else
  begin
    FUpdateTag := '';
    if Loud then FCmdMsg := 'Up to date - ' + CurrentVersion + '.';
  end;
  pbCmd.Invalidate;
end;

{ 3x, x3, *3: three copies at the spacing of the one just made.  /3, 3/:
  the run divided into three. }
function TMainForm.ArrayCommand(const S: string; out N: Integer; out Divide: Boolean): Boolean;
var
  T: string;
begin
  Result := False;
  N := 0;
  Divide := False;
  T := LowerCase(Trim(S));
  if Length(T) < 2 then Exit;
  if T[1] in ['x', '*', '/'] then
  begin
    Divide := T[1] = '/';
    Delete(T, 1, 1);
  end
  else if T[Length(T)] in ['x', '*', '/'] then
  begin
    Divide := T[Length(T)] = '/';
    Delete(T, Length(T), 1);
  end
  else
    Exit;
  Result := TryStrToInt(Trim(T), N) and (N >= 2) and (N <= 500);
end;

{ Make the copy just placed into N.  Earlier copies are taken back first so
  a new count replaces the old; they are the last entities, so that means
  deleting from the end. }
procedure TMainForm.ApplyArray(N: Integer; Divide: Boolean);
var
  I: Integer;
begin
  if not FArray.Live then Exit;
  PushUndo;
  for I := High(FArray.Made) downto 0 do
    FD.Doc.Delete(FArray.Made[I]);
  if FArray.Rotate then
    FD.Doc.ArrayRotate(FArray.Src, FArray.C, FArray.Axis, FArray.Ang, N, Divide, FArray.Made)
  else
    FD.Doc.ArrayMove(FArray.Src, FArray.D, N, Divide, FArray.Made);
  SelectNone;
  for I := 0 to High(FArray.Made) do SelectAdd(FArray.Made[I]);
  SeedRegions;
  RenderInk;
  RecomposeAll;
  if Divide then
    FCmdMsg := Format('Divided into %d.  Another count replaces it.', [N])
  else
    FCmdMsg := Format('%d copies.  Another count replaces it.', [N]);
  pbScreen.Invalidate;
  pbCmd.Invalidate;
end;

{ /timings: how long the steps of an edit took }
procedure TMainForm.Took(const What: string; T0: QWord);
begin
  if not FTimings then Exit;
  TimingLine(Format('took %d ms: %s', [GetTickCount64 - T0, What]));
end;

{ One line of /timings: to the console where there is one, and kept for the
  box since Windows has none.  The oldest drop off once it is long. }
procedure TMainForm.TimingLine(const S: string);
const
  KEEP = 400;
var
  N: Integer;
begin
  WriteLn(S);
  Flush(Output);
  N := Length(FTimingLog);
  if N >= KEEP then
  begin
    FTimingLog := Copy(FTimingLog, N - KEEP div 2, MaxInt);
    N := Length(FTimingLog);
  end;
  SetLength(FTimingLog, N + 1);
  FTimingLog[N] := FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + S;
end;

procedure TMainForm.ShowTimingLog;
var
  I: Integer;
  T: string;
begin
  if Length(FTimingLog) = 0 then
  begin
    FCmdMsg := 'No timings collected yet - /timings, do something, then /timings again.';
    Exit;
  end;
  T := '';
  for I := 0 to High(FTimingLog) do T := T + FTimingLog[I] + LineEnding;
  ShowLongText('Step timings, oldest first', T);
end;

procedure TMainForm.RenderTiming;
var
  T0: QWord;
  I, N: Integer;
  Ms, Ov, Qk, Bl, Gd: Double;
  Ph: array[0..5] of Double;
  WasMoving: Boolean;
  Box: string;
begin
  N := 10;
  for I := 0 to 5 do FD.Doc.ProfMs[I] := 0;
  { a whole frame as an orbit makes one: paper, drawing, composite }
  T0 := GetTickCount64;
  for I := 1 to N do
  begin
    FScreenDirty := True;
    RepaintPaper;
    RenderInk;
    RecomposeAll;
  end;
  Ms := (GetTickCount64 - T0) / N;
  for I := 0 to 5 do Ph[I] := FD.Doc.ProfMs[I] / N;
  { the same frame the quick way, as an orbit in progress draws it }
  WasMoving := FCameraMoving;
  FCameraMoving := FQuickFrames;
  T0 := GetTickCount64;
  for I := 1 to N do
  begin
    FScreenDirty := True;
    RepaintPaper;
    RenderInk;
    RecomposeAll;
  end;
  Qk := (GetTickCount64 - T0) / N;
  FCameraMoving := WasMoving;
  RepaintPaper; RenderInk; RecomposeAll;
  { and the overlay on top, the selection outlines above all }
  T0 := GetTickCount64;
  for I := 1 to N do pbScreen.Repaint;
  Ov := (GetTickCount64 - T0) / N;
  { The blit alone, apart from the overlay drawing, to tell which half of
    the paint handler the time belongs to. }
  T0 := GetTickCount64;
  for I := 1 to N do FArt.DrawTo(pbScreen.Canvas, FJitterX, FJitterY);
  Bl := (GetTickCount64 - T0) / N;
  { and the guides, rubber band and readouts on their own }
  Gd := 0;
  T0 := GetTickCount64;
  for I := 1 to N do PaintOverlay(pbScreen.Canvas);
  Gd := (GetTickCount64 - T0) / N;
  FCmdMsg := Format('A frame takes %.0f ms (%d things: %d faces).  index and edges %.0f, faces sorted and painted %.0f, lines on faces %.0f, the rest %.0f',
    [Ms, FD.Doc.Live, FaceCount + SolidFaceCount, Ph[0], Ph[1] + Ph[2], Ph[3], Ph[4]]);
  FCmdMsg := FCmdMsg + Format('; quick frame %.0f ms; overlay %.0f ms (blit %.0f, guides %.0f) with %d selected',
    [Qk, Ov, Bl, Gd, Length(FSel)]);
  { too long for the bar, so the whole thing goes in a copyable box }
  Box := Format(
    'A whole frame (paper, drawing, composite):  %.1f ms' + LineEnding +
    '  things on the sheet:                     %d  (%d faces)' + LineEnding +
    '  index and edges:                         %.1f ms' + LineEnding +
    '  faces sorted and painted:                %.1f ms' + LineEnding +
    '  lines on faces:                          %.1f ms' + LineEnding +
    '  the rest:                                %.1f ms' + LineEnding +
    'A quick frame, as an orbit draws it:       %.1f ms' + LineEnding +
    'The paint on top:                          %.1f ms' + LineEnding +
    '  the picture onto the window:             %.1f ms' + LineEnding +
    '  guides, rubber band and readouts:        %.1f ms' + LineEnding +
    '  with this many picked:                   %d' + LineEnding + LineEnding +
    'Lines-on-faces cache: built %d times, threads %s, last build %.0f ms on %s,' + LineEnding +
    '  taken %.0f ms after it was done; frames that went without it: %d' + LineEnding +
    '  (%.0f ms on the last), discarded %d, failed %d' + LineEnding + LineEnding +
    'Window %dx%d at %.2f scaling, zoom %.3f, view %s.  Each figure is the average of %d.',
    [Ms, FD.Doc.Live, FaceCount + SolidFaceCount, Ph[0], Ph[1] + Ph[2], Ph[3], Ph[4],
     Qk, Ov, Bl, Gd, Length(FSel),
     FD.Doc.OnFaceBuilds, BoolToStr(FD.Doc.Threads, 'on', 'off'),
     FD.Doc.OnFaceWorkerMs, FD.Doc.OnFaceBuiltOn, FD.Doc.OnFaceLagMs,
     FD.Doc.OnFaceFallbacks, FD.Doc.OnFaceFallbackMs,
     FD.Doc.OnFaceDiscarded, FD.Doc.OnFaceFailed,
     pbScreen.Width, pbScreen.Height, FUIScale, FD.Zoom, VIEW_NAMES[FD.View], N]);
  WriteLn('rendertime ', Ms:0:1, ' ms/frame (paper+render+composite), ', FD.Doc.Live, ' things; index+edges ',
    Ph[0]:0:1, ' faces ', (Ph[1] + Ph[2]):0:1, ' lines-on-faces ',
    Ph[3]:0:1, ' rest ', Ph[4]:0:1, '; quick frame ', Qk:0:1, '; overlay ', Ov:0:1, ' ms of which blit ', Bl:0:1, ' guides ', Gd:0:1, ', with ', Length(FSel), ' selected; onface builds so far ', FD.Doc.OnFaceBuilds,
    '; threads ', FD.Doc.Threads, ' last cache build ', FD.Doc.OnFaceWorkerMs:0:0, ' ms on ', FD.Doc.OnFaceBuiltOn, ', taken ', FD.Doc.OnFaceLagMs:0:0, ' ms after done; a frame without the cache spent ', FD.Doc.OnFaceFallbackMs:0:0, ' ms on lines-on-faces; frames without cache ',
    FD.Doc.OnFaceFallbacks, ', discarded ', FD.Doc.OnFaceDiscarded, ', failed ', FD.Doc.OnFaceFailed);
  Flush(Output);
  Trail(FCmdMsg);
  FCmdMsg := Format('A frame takes %.0f ms - the rest is in the box.', [Ms]);
  pbCmd.Invalidate;
  ShowLongText('How long a frame takes', Box);
end;

{ the normal of an arc's plane }
function TMainForm.ArcNormal(I: Integer): TP3;
var
  AU, AV: TP3;
begin
  if FD.Doc[I].Plane = plFree then Result := Norm3(FD.Doc[I].Nm)
  else
  begin
    PlaneAxes(FD.Doc[I].Plane, AU, AV);
    Result := Norm3(Cross3(AU, AV));
  end;
end;

{ Is this line one of the outline's own sides: both ends are corners of the
  outline, next to each other round it? }
function TMainForm.IsProfileEdge(I: Integer): Boolean;
const
  TOL = 1E-6;
var
  K, N, A, B: Integer;
begin
  Result := False;
  if (I < 0) or (I >= FD.Doc.Live) or (FD.Doc[I].Kind <> ekLine) then Exit;
  if (FFollowFace < 0) or (FFollowFace >= FD.Doc.Live) then Exit;
  if FD.Doc[FFollowFace].Kind <> ekFace then Exit;
  N := Length(FD.Doc[FFollowFace].Poly);
  A := -1;
  B := -1;
  for K := 0 to N - 1 do
  begin
    if Dist(FD.Doc[FFollowFace].Poly[K], FD.Doc[I].A) < TOL then A := K;
    if Dist(FD.Doc[FFollowFace].Poly[K], FD.Doc[I].B) < TOL then B := K;
  end;
  if (A < 0) or (B < 0) then Exit;
  Result := (Abs(A - B) = 1) or (Abs(A - B) = N - 1);
end;

function TMainForm.AxisSplitsProfile(const AxisP, AxisDir: TP3;
  out RLo, RHi: Double): Boolean;
begin
  Result := FD.Doc.AxisSplitsFace(FFollowFace, AxisP, AxisDir, RLo, RHi);
end;

procedure TMainForm.PaintRevolvePreview(C: TCanvas);
const
  RING_N = 48;
var
  D, AP, Q: TP3;
  RLo, RHi, L: Double;
  Bad: Boolean;
  K, N: Integer;
  Col: TPix;
  U, W, Nf: TP3;
  PA, PB: TPointF;

  procedure Circle(R: Double);
  var
    J: Integer;
    A: Double;
    P0, P1: TPointF;
  begin
    if R < 1E-9 then Exit;
    P0 := ScreenOf(P3(AP.X + U.X * R, AP.Y + U.Y * R, AP.Z + U.Z * R));
    for J := 1 to RING_N do
    begin
      A := 2 * Pi * J / RING_N;
      P1 := ScreenOf(P3(AP.X + (U.X * Cos(A) + W.X * Sin(A)) * R,
                        AP.Y + (U.Y * Cos(A) + W.Y * Sin(A)) * R,
                        AP.Z + (U.Z * Cos(A) + W.Z * Sin(A)) * R));
      C.Line(Round(P0.X), Round(P0.Y), Round(P1.X), Round(P1.Y));
      P0 := P1;
    end;
  end;

begin
  D := Sub3(FCur, FAxisA);
  L := Dist(D, P3(0, 0, 0));
  if L < 1E-9 then Exit;
  D := P3(D.X / L, D.Y / L, D.Z / L);
  Bad := AxisSplitsProfile(FAxisA, D, RLo, RHi);

  if Bad then Col := Pix(220, 60, 60) else Col := Theme.Accent;
  C.Pen.Color := PixToColor(Col);
  C.Pen.Width := Max(1, Round(2 * FUIScale));
  C.Brush.Style := bsClear;

  { the axis, run well past both ends: the shape turns about the whole line }
  N := Round(Max(RHi * 3, L * 2));
  PA := ScreenOf(P3(FAxisA.X - D.X * N, FAxisA.Y - D.Y * N, FAxisA.Z - D.Z * N));
  PB := ScreenOf(P3(FAxisA.X + D.X * N, FAxisA.Y + D.Y * N, FAxisA.Z + D.Z * N));
  C.Line(Round(PA.X), Round(PA.Y), Round(PB.X), Round(PB.Y));

  { the rings the outline's nearest and furthest corners sweep, about the
    axis at the outline's middle }
  Nf := Norm3(FD.Doc.FaceNormal(FFollowFace));
  U := Norm3(Cross3(D, Nf));
  W := Norm3(Cross3(D, U));
  Q := P3(0, 0, 0);
  N := Length(FD.Doc[FFollowFace].Poly);
  if N = 0 then Exit;
  for K := 0 to N - 1 do
    Q := P3(Q.X + FD.Doc[FFollowFace].Poly[K].X / N,
            Q.Y + FD.Doc[FFollowFace].Poly[K].Y / N,
            Q.Z + FD.Doc[FFollowFace].Poly[K].Z / N);
  { the middle of the outline, brought onto the axis }
  Q := Sub3(Q, FAxisA);
  AP := P3(FAxisA.X + D.X * Dot3(Q, D), FAxisA.Y + D.Y * Dot3(Q, D),
           FAxisA.Z + D.Z * Dot3(Q, D));
  C.Pen.Width := 1;
  Circle(RHi);
  Circle(RLo);
end;

{ Follow Me round an axis: the typed angle in degrees, or a full turn.  The
  gore count scales with the circle side count, so a quarter turn gets a
  quarter of them. }
procedure TMainForm.DoRevolve(const AxisP, AxisDir: TP3; PathArc: Integer);
var
  Deg, Ang: Double;
  Steps, First, Made: Integer;
var
  RLo, RHi: Double;
  Split: Boolean;
begin
  Ang := 2 * Pi;
  if (FInput <> '') and TryStrToFloat(Trim(FInput), Deg) and (Deg <> 0) then
    Ang := DegToRad(Deg);
  Steps := Max(1, Round(FSidesCircle * Abs(Ang) / (2 * Pi)));
  { Checked before acting: an axis through the middle of the outline sweeps
    the two halves into each other, a knot with no outside. }
  Split := AxisSplitsProfile(AxisP, AxisDir, RLo, RHi);
  if Split then
  begin
    FCmdMsg := 'The axis runs through the middle of the outline, so the two ' +
      'halves would sweep into each other.  A glass is spun about a line ' +
      'down one side of its outline, not through it.  Nothing done - move ' +
      'the axis to the edge and click again.';
    Exit;
  end;
  PushUndo;
  Made := FD.Doc.Live;
  First := FD.Doc.Revolve(FFollowFace, AxisP, AxisDir, Ang, Steps);
  if First < 0 then
  begin
    FCmdMsg := 'That could not be spun - it needs a face and an axis of some length.';
    Exit;
  end;
  Made := FD.Doc.Live - Made;
  { the circle that was followed lies on the new surface: make it a soft
    seam of the solid, not a hard ring }
  if (PathArc >= 0) and (PathArc < FD.Doc.Live) and (First < FD.Doc.Live) then
  begin
    FD.Doc.SetSoft(PathArc, True);
    FD.Doc.SetGroup(PathArc, FD.Doc[First].Grp);
  end;
  SeedRegions;
  SelectNone;
  RenderInk;
  RecomposeAll;
  FCmdMsg := Format('Spun %s in %d gores, %s to %s across.',
    [FormatAngle(RadToDeg(Ang)), Steps,
     FormatLen(RLo * 2, FD.Units), FormatLen(RHi * 2, FD.Units)]);
  if Made > 0 then ;
  ResetTool;
  FInput := '';
end;

{ The chain through edge I, followed each way while there is exactly one
  edge to follow.  Points come back in order end to end, or round to the
  start when it closes. }
function TMainForm.ChainFrom(I: Integer; out Closed: Boolean): TP3Array;
var
  Used: array of Boolean;
  Pts, More: TP3Array;
  J, K, Found, Guard: Integer;
  Tail: TP3;
  Fwd: Boolean;

  function Tip(J: Integer; AtA: Boolean): TP3;
  begin
    if AtA then Result := FD.Doc[J].A else Result := FD.Doc[J].B;
  end;

  { the one unused edge with an end at P, or -1 when none or several }
  function NextAt(const P: TP3; out AtA: Boolean): Integer;
  var
    E, Count: Integer;
  begin
    Result := -1;
    Count := 0;
    AtA := True;
    for E := 0 to FD.Doc.Live - 1 do
      if (not Used[E]) and (FD.Doc[E].Kind in [ekLine, ekArc]) then
      begin
        if Dist(FD.Doc[E].A, P) < 1E-6 then begin Inc(Count); Result := E; AtA := True; end
        else if Dist(FD.Doc[E].B, P) < 1E-6 then begin Inc(Count); Result := E; AtA := False; end;
      end;
    if Count <> 1 then Result := -1;
  end;

  procedure Append(var L: TP3Array; const P: TP3Array; Reverse: Boolean);
  var
    Q: Integer;
  begin
    for Q := 0 to High(P) do
    begin
      if Reverse then K := High(P) - Q else K := Q;
      if (Length(L) > 0) and (Dist(L[High(L)], P[K]) < 1E-9) then Continue;
      SetLength(L, Length(L) + 1);
      L[High(L)] := P[K];
    end;
  end;

begin
  Result := nil;
  Closed := False;
  SetLength(Used, FD.Doc.Live);
  Used[I] := True;
  FD.Doc.EdgePoints(I, Pts);
  if Length(Pts) < 2 then Exit;
  { forward from the end of I }
  Guard := 0;
  repeat
    Tail := Pts[High(Pts)];
    if Dist(Tail, Pts[0]) < 1E-6 then
    begin
      Closed := True;
      Break;
    end;
    Found := NextAt(Tail, Fwd);
    if Found < 0 then Break;
    Used[Found] := True;
    FD.Doc.EdgePoints(Found, More);
    Append(Pts, More, not Fwd);
    Inc(Guard);
  until Guard > 10000;
  if not Closed then
  begin
    { and backward from the start of I }
    Guard := 0;
    repeat
      Found := NextAt(Pts[0], Fwd);
      if Found < 0 then Break;
      Used[Found] := True;
      FD.Doc.EdgePoints(Found, More);
      { reverse the chain, append, reverse back }
      for J := 0 to High(Pts) div 2 do
      begin
        Tail := Pts[J]; Pts[J] := Pts[High(Pts) - J]; Pts[High(Pts) - J] := Tail;
      end;
      Append(Pts, More, not Fwd);
      for J := 0 to High(Pts) div 2 do
      begin
        Tail := Pts[J]; Pts[J] := Pts[High(Pts) - J]; Pts[High(Pts) - J] := Tail;
      end;
      if Dist(Pts[0], Pts[High(Pts)]) < 1E-6 then
      begin
        Closed := True;
        Break;
      end;
      Inc(Guard);
    until Guard > 10000;
  end;
  Result := Pts;
end;

{ Follow Me along a path.  The profile rides from whichever end is nearer,
  so the path can be drawn either way. }
procedure TMainForm.DoSweep(const Path: TP3Array; Closed: Boolean);
var
  P: TP3Array;
  Cen: TP3;
  I, First: Integer;
  DA, DB: Double;
begin
  if Length(Path) < 2 then
  begin
    FCmdMsg := 'That path has nothing to follow.';
    Exit;
  end;
  P := Copy(Path);
  if not Closed then
  begin
    Cen := P3(0, 0, 0);
    for I := 0 to High(FD.Doc[FFollowFace].Poly) do
      Cen := P3(Cen.X + FD.Doc[FFollowFace].Poly[I].X / Length(FD.Doc[FFollowFace].Poly),
                Cen.Y + FD.Doc[FFollowFace].Poly[I].Y / Length(FD.Doc[FFollowFace].Poly),
                Cen.Z + FD.Doc[FFollowFace].Poly[I].Z / Length(FD.Doc[FFollowFace].Poly));
    DA := Dist(Cen, P[0]);
    DB := Dist(Cen, P[High(P)]);
    if DB < DA then
      for I := 0 to High(P) div 2 do
      begin
        Cen := P[I]; P[I] := P[High(P) - I]; P[High(P) - I] := Cen;
      end;
  end;
  PushUndo;
  First := FD.Doc.Sweep(FFollowFace, P, Closed);
  if First < 0 then
  begin
    FCmdMsg := 'That could not be followed - it needs a face and a path of some length.';
    Exit;
  end;
  SeedRegions;
  SelectNone;
  RenderInk;
  RecomposeAll;
  if Closed then FCmdMsg := 'Followed the path all the way round.'
  else FCmdMsg := Format('Followed the path, %d legs.', [Length(P) - 1]);
  ResetTool;
  FInput := '';
end;

{ The pipe fitter's iso: the spool as legs with lengths, built as one solid
  and placed like a fitting. }
procedure TMainForm.BuildSpoolWizard;
var
  Spec: TSpoolSpec;
  First: Integer;
begin
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  if not TSpoolForm.Ask(FD.Units, Spec) then Exit;
  if FD.View = vkPlan then EnterFreeCamera(True);
  PushUndo;
  First := BuildSpool(FD.Doc, Spec, FInkColor, FEdgeW);
  if First < 0 then
  begin
    FCmdMsg := 'The spool could not be built.';
    Exit;
  end;
  SeedRegions;
  RenderInk;
  RecomposeAll;
  PlaceBuilt(First, P3(0, 0, 0));
end;

procedure TMainForm.BuildTransitionWizard;
var
  Spec: TTransitionSpec;
  First: Integer;
begin
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  if not TTransitionForm.Ask(FD.Units, Spec) then Exit;
  if FD.View = vkPlan then EnterFreeCamera(True);
  PushUndo;
  First := BuildFitting(FD.Doc, Spec, FInkColor, FEdgeW);
  SeedRegions;
  RenderInk;
  RecomposeAll;
  PlaceBuilt(First, P3(0, 0, 0));
end;

{ Stairs.  Two lines picked: the flight stands on them (lower where the
  first riser stands, upper at the landing edge).  A stair group picked:
  the dialog opens on what it remembers and changes it in place.  Otherwise
  sizes are typed, or three points picked from the dialog, and the flight is
  built in place or follows the pointer to be placed. }
procedure TMainForm.BuildStairWizard;
var
  A, B: TWorkEnt;
  G: Integer;
begin
  FStairJob := Default(TStairJob);
  FStairJob.Mode := smFree;
  FStairEdit := 0;
  G := SoleGroup;
  if (G > 0) and IsStairJig(FD.Doc.PartJig(G)) and
     StairFromJig(FD.Doc.PartJig(G), FD.Units, FStairJob.Frame, FStairJob.Spec, FStairJob.Use) then
  begin
    FStairJob.Frame.Bottom := StairWhereNow(G, FStairJob.Frame, FStairJob.Spec);
    FStairJob.Mode := smPlaced;
    FStairJob.HaveSpec := True;
    FStairJob.Editing := True;
    FStairJob.Note := 'The flight picked, as it was built.';
    FStairEdit := G;
  end
  else if Length(FSel) = 2 then
  begin
    A := FD.Doc[FSel[0]]; B := FD.Doc[FSel[1]];
    if (A.Kind = ekLine) and (B.Kind = ekLine) then
    begin
      FStairJob.Mode := smLines;
      FStairJob.LA := A.A; FStairJob.LB := A.B; FStairJob.HA := B.A; FStairJob.HB := B.B;
    end;
  end;
  StairDialog;
end;

{ Where a stair group's flight stands now: its jig line's position, shifted
  by however far the group's boards have moved since (compared with a fresh
  build's box).  Rotation by hand is not followed. }
function TMainForm.StairWhereNow(G: Integer; const F: TStairFrame; const S: TStairSpec): TP3;
var
  T: TWorkDoc;
  M: TIntArrayW;
  I, J: Integer;
  Lo1, Hi1, Lo2, Hi2: TP3;

  procedure Grow(const P: TP3; var Lo, Hi: TP3);
  begin
    Lo := P3(Min(Lo.X, P.X), Min(Lo.Y, P.Y), Min(Lo.Z, P.Z));
    Hi := P3(Max(Hi.X, P.X), Max(Hi.Y, P.Y), Max(Hi.Z, P.Z));
  end;

begin
  Result := F.Bottom;
  Lo1 := P3(1E300, 1E300, 1E300); Hi1 := P3(-1E300, -1E300, -1E300);
  Lo2 := Lo1; Hi2 := Hi1;
  M := FD.Doc.PartMembers(G, False);
  for I := 0 to High(M) do
    if FD.Doc[M[I]].Kind = ekFace then
      for J := 0 to High(FD.Doc[M[I]].Poly) do Grow(FD.Doc[M[I]].Poly[J], Lo1, Hi1);
  T := TWorkDoc.Create;
  try
    try
      BuildStairs(T, F, S, clBlack, 1);
    except
      Exit;
    end;
    for I := 0 to T.Live - 1 do
      if T[I].Kind = ekFace then
        for J := 0 to High(T[I].Poly) do Grow(T[I].Poly[J], Lo2, Hi2);
  finally
    T.Free;
  end;
  if (Lo1.X > Hi1.X) or (Lo2.X > Hi2.X) then Exit;
  { same flight elsewhere means the same size box }
  if (Abs((Hi1.X - Lo1.X) - (Hi2.X - Lo2.X)) > 1E-4) or (Abs((Hi1.Y - Lo1.Y) - (Hi2.Y - Lo2.Y)) > 1E-4) or
     (Abs((Hi1.Z - Lo1.Z) - (Hi2.Z - Lo2.Z)) > 1E-4) then Exit;
  Result := P3(F.Bottom.X + Lo1.X - Lo2.X, F.Bottom.Y + Lo1.Y - Lo2.Y, F.Bottom.Z + Lo1.Z - Lo2.Z);
end;

{ Empty stair group G (keeping its own record) and rebuild the flight into
  it from F and S, updating its jig line.  The caller owns the undo step. }
procedure TMainForm.StairRebuild(G: Integer; const F: TStairFrame; const S: TStairSpec; Use: TStairUse);
var
  M: TIntArrayW;
  Doomed: array of Boolean;
  I, Rec: Integer;
begin
  LeaveSheet;
  ResetTool;
  M := FD.Doc.PartMembers(G, False);
  Rec := FD.Doc.PartEnt(G);
  SetLength(Doomed, FD.Doc.Live);
  for I := 0 to High(Doomed) do Doomed[I] := False;
  for I := 0 to High(M) do
    if M[I] <> Rec then Doomed[M[I]] := True;
  FD.Doc.DeleteMarked(Doomed);
  BuildStairs(FD.Doc, F, S, FInkColor, FEdgeW, G, StairJig(F, S, Use));
  FD.Dirty := True;
end;

{ the stair dialog on FStairJob, and what it closed for: build, or pick
  points on the sheet }
procedure TMainForm.StairDialog;
var
  First, I: Integer;
begin
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  case TStairForm.Ask(FD.Units, FStairJob) of
    saCancel: Exit;
    saPick:
      begin
        FStairPick := 1;
        ResetTool;
        FCmdMsg := 'Stairs: click the TOP - the landing''s edge, at its height.  Esc goes back to the stairs.';
        pbScreen.Invalidate; pbCmd.Invalidate;
        Exit;
      end;
  end;
  PushUndo;
  with FStairJob do
  begin
    if FStairEdit > 0 then
    begin
      StairRebuild(FStairEdit, Frame, Spec, Use);
      { selected again, as before the change }
      SelectNone;
      for I := 0 to High(FD.Doc.PartMembers(FStairEdit, False)) do
        SelectAdd(FD.Doc.PartMembers(FStairEdit, False)[I]);
      FCmdMsg := 'The stairs are built again.';
    end
    else
    begin
      First := BuildStairs(FD.Doc, Frame, Spec, FInkColor, FEdgeW, 0, StairJig(Frame, Spec, Use));
      FCmdMsg := Format('Built stairs: %d risers of %s, %d treads of %s.',
        [Spec.Risers, StairLen(Frame.Rise / Spec.Risers, FD.Units), Spec.Risers - 1,
         StairLen(Frame.Run / (Spec.Risers - 1), FD.Units)]);
      if Mode = smFree then
      begin
        SeedRegions;
        RenderInk; RecomposeAll;
        { held by the foot of the first riser, to be clicked into place }
        PlaceBuilt(First, P3(0, 0, 0));
        FCmdMsg := FCmdMsg + '  Click to place it.';
        pbScreen.Invalidate; pbCmd.Invalidate;
        Exit;
      end;
      SelectNone;
      for I := First to FD.Doc.Live - 1 do SelectAdd(I);
    end;
  end;
  SeedRegions;
  RebuildFlatFaces;
  RenderInk; RecomposeAll;
  pbScreen.Invalidate; pbCmd.Invalidate;
end;

{ The flight from the two picked points and a third (the side the width
  goes).  The top is picked first, but whichever point is lower is the
  bottom.  Picked level (in plan), the second is the bottom and the rise is
  the typed one. }
function TMainForm.StairPickFrame(const Third: TP3; out F: TStairFrame; out Why: string): Boolean;
var
  Hi, Lo: TP3;
begin
  Hi := FStairPts[0]; Lo := FStairPts[1];
  if Hi.Z < Lo.Z - 1E-6 then begin Hi := FStairPts[1]; Lo := FStairPts[0]; end;
  Result := StairFramePicked(Lo, Hi, Third, F, Why);
  if not Result then Exit;
  if F.Rise <= 1E-6 then F.Rise := FStairJob.Frame.Rise;
  if F.Width <= 1E-6 then F.Width := FStairJob.Frame.Width;
end;

{ A point picked for the stairs (the snapped cursor).  After the third, the
  dialog reopens on them. }
procedure TMainForm.StairTakePoint(const P: TP3);
var
  F: TStairFrame;
  Why: string;
  S: TStairSpec;
begin
  FStairPts[FStairPick - 1] := P;
  Inc(FStairPick);
  case FStairPick of
    2: FCmdMsg := 'Stairs: now the BOTTOM - where the first riser stands - or type the run.  Esc goes back.';
    3: FCmdMsg := 'Stairs: and the SIDE - click as far out as the stairs are wide, or type the width.  Esc goes back.';
  else
    FStairPick := 0;
    if StairPickFrame(FStairPts[2], F, Why) then
    begin
      if Abs(FStairPts[0].Z - FStairPts[1].Z) <= 1E-6 then
        FStairJob.Note := 'At the points picked - level, so the rise is as typed.'
      else
        FStairJob.Note := 'At the points picked.';
      if (F.Rise > 0) and (F.Width > 0) then
      begin
        FStairJob.Frame := F;
        FStairJob.Mode := smPlaced;
        { start with the riser count that fits the points; the points stay
          where they were put }
        if FStairJob.HaveSpec then S := FStairJob.Spec else S := StairDefaults(F, FD.Units);
        S.Risers := RecommendStairs(F, FD.Units, FStairJob.Use, S).SuggestedRisers;
        FStairJob.Spec := S;
        FStairJob.HaveSpec := True;
      end;
    end
    else FStairJob.Note := Why;
    Application.QueueAsyncCall(@StairResume, 0);
  end;
  pbCmd.Invalidate;
  pbScreen.Invalidate;
end;

procedure TMainForm.StairTyped;
var
  L, H: Double;
  D, P: TP3;
  F: TStairFrame;
  Why: string;
begin
  if Trim(FInput) = '' then Exit;
  if not ParseLen(FInput, FD.Units, L) or (L <= 0) then
  begin
    FCmdMsg := 'Stairs: that is not a length - 10'', 12''6", 6-8-15.';
    pbCmd.Invalidate;
    Exit;
  end;
  case FStairPick of
    1:
      begin
        FCmdMsg := 'Stairs: click the top first - then a length typed is the run.';
        FInput := '';
        pbCmd.Invalidate;
        Exit;
      end;
    2:
      begin
        { the run, level from the top toward the cursor; the bottom at the
          cursor's height }
        D := P3(FCur.X - FStairPts[0].X, FCur.Y - FStairPts[0].Y, 0);
        H := Sqrt(Sqr(D.X) + Sqr(D.Y));
        if H < 1E-9 then
        begin
          FCmdMsg := 'Stairs: point the cursor the way the stairs run, then type the run.';
          pbCmd.Invalidate;
          Exit;
        end;
        P := P3(FStairPts[0].X + D.X / H * L, FStairPts[0].Y + D.Y / H * L, FCur.Z);
      end;
  else
    begin
      { the width, across the flight on the cursor's side }
      if not StairPickFrame(FCur, F, Why) then
      begin
        FCmdMsg := 'Stairs: ' + Why;
        pbCmd.Invalidate;
        Exit;
      end;
      P := P3(F.Bottom.X + F.Across.X * L, F.Bottom.Y + F.Across.Y * L, F.Bottom.Z);
    end;
  end;
  FInput := '';
  StairTakePoint(P);
end;

{ The stair pick so far, drawn on the sheet, with a guide beside the cursor
  saying what the next click is.  Picked points are labeled; after the top a
  line runs to the cursor; after the bottom the flight itself follows the
  cursor so the third click is made looking at the result. }
procedure TMainForm.PaintStairPick(C: TCanvas; SX, SY: Integer);
var
  Ink: TColor;
  F: TStairFrame;
  Why, Word_: string;
  K, N, GX, GY, U: Integer;
  A, B: TPointF;
  R, G: Double;

  function At(X, Y, Z: Double): TPointF;
  var
    W: TP3;
  begin
    W := P3(F.Bottom.X + F.Forward.X * X + F.Across.X * Y, F.Bottom.Y + F.Forward.Y * X + F.Across.Y * Y,
      F.Bottom.Z + Z);
    Result := ScreenOf(W);
  end;

  procedure Seg(const P, Q: TPointF);
  begin
    C.MoveTo(Round(P.X), Round(P.Y));
    C.LineTo(Round(Q.X), Round(Q.Y));
  end;

  procedure Mark(const P: TP3; const Name: string);
  var
    Q: TPointF;
    D: Integer;
  begin
    Q := ScreenOf(P);
    D := Round(5 * FUIScale);
    C.Pen.Style := psSolid;
    C.Brush.Style := bsSolid;
    C.Brush.Color := Ink;
    C.Ellipse(Round(Q.X) - D, Round(Q.Y) - D, Round(Q.X) + D + 1, Round(Q.Y) + D + 1);
    C.Brush.Style := bsClear;
    UIFont(C, 9, True, Theme.Text);
    C.Font.Color := Ink;
    C.TextOut(Round(Q.X) + D + 4, Round(Q.Y) - D - C.TextHeight('X'), Name);
  end;

  { a size on the drawing, on a card so it reads over lines }
  procedure Tag_(const At_: TPointF; const Words: string);
  var
    W, H, X, Y, Pad: Integer;
  begin
    UIFont(C, 9, True, Theme.Text);
    W := C.TextWidth(Words);
    H := C.TextHeight('Xg');
    Pad := Round(4 * FUIScale);
    X := Round(At_.X) - W div 2;
    Y := Round(At_.Y) - H div 2;
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
    C.Pen.Color := Ink;
    C.Brush.Style := bsSolid;
    C.Brush.Color := PixToColor(MixPix(Theme.Panel, Pix(0, 0, 0), 0.15));
    C.RoundRect(X - Pad, Y - Pad div 2, X + W + Pad, Y + H + Pad div 2, Pad * 2, Pad * 2);
    C.Brush.Style := bsClear;
    C.Font.Color := PixToColor(Theme.Text);
    C.TextOut(X, Y, Words);
    C.Pen.Width := Max(2, Round(2 * FUIScale));
    C.Pen.Color := Ink;
  end;

begin
  Ink := RGBToColor($F0, $80, $10);
  C.Pen.Color := Ink;
  C.Pen.Width := Max(2, Round(2 * FUIScale));
  if FStairPick >= 2 then Mark(FStairPts[0], 'TOP');
  if FStairPick = 2 then
  begin
    { from the top to where the bottom will go }
    C.Pen.Style := psDash;
    A := ScreenOf(FStairPts[0]);
    Seg(A, PointF(SX, SY));
    TipAvoid(Round(A.X), Round(A.Y), SX, SY);
    C.Pen.Style := psSolid;
    { the run and rise so far, halfway along }
    R := Abs(FStairPts[0].Z - FCur.Z);
    G := Sqrt(Sqr(FCur.X - FStairPts[0].X) + Sqr(FCur.Y - FStairPts[0].Y));
    if R < 1E-6 then
      Tag_(PointF((A.X + SX) / 2, (A.Y + SY) / 2),
        'run ' + FormatLen(G, FD.Units) + '   rise ' + FormatLen(FStairJob.Frame.Rise, FD.Units) + ' as typed')
    else
      Tag_(PointF((A.X + SX) / 2, (A.Y + SY) / 2),
        'run ' + FormatLen(G, FD.Units) + '   rise ' + FormatLen(R, FD.Units));
  end;
  if FStairPick = 3 then
  begin
    Mark(FStairPts[1], 'BOTTOM');
    if StairPickFrame(FCur, F, Why) then
    begin
      C.Pen.Style := psSolid;
      C.Pen.Width := Max(2, Round(2 * FUIScale));
      { the footprint and the landing's edge }
      Seg(At(0, 0, 0), At(0, F.Width, 0));
      Seg(At(0, 0, 0), At(F.Run, 0, 0));
      Seg(At(0, F.Width, 0), At(F.Run, F.Width, 0));
      Seg(At(F.Run, 0, F.Rise), At(F.Run, F.Width, F.Rise));
      { every nosing at its height, using the riser count the dialog will
        open with }
      if FStairJob.HaveSpec then
        N := RecommendStairs(F, FD.Units, FStairJob.Use, FStairJob.Spec).SuggestedRisers
      else
        N := RecommendStairs(F, FD.Units, FStairJob.Use, StairDefaults(F, FD.Units)).SuggestedRisers;
      N := EnsureRange(N, 2, 200);
      R := F.Rise / N; G := F.Run / (N - 1);
      C.Pen.Width := Max(1, Round(FUIScale));
      for K := 0 to N - 2 do
      begin
        Seg(At(K * G, 0, (K + 1) * R), At(K * G, F.Width, (K + 1) * R));
        { the side's sawtooth, both sides }
        Seg(At(K * G, 0, K * R), At(K * G, 0, (K + 1) * R));
        Seg(At(K * G, 0, (K + 1) * R), At((K + 1) * G, 0, (K + 1) * R));
        Seg(At(K * G, F.Width, K * R), At(K * G, F.Width, (K + 1) * R));
        Seg(At(K * G, F.Width, (K + 1) * R), At((K + 1) * G, F.Width, (K + 1) * R));
      end;
      Seg(At(F.Run, 0, (N - 1) * R), At(F.Run, 0, F.Rise));
      Seg(At(F.Run, F.Width, (N - 1) * R), At(F.Run, F.Width, F.Rise));
      A := At(0, 0, 0); B := At(0, F.Width, 0);
      TipAvoid(Round(A.X), Round(A.Y), Round(B.X), Round(B.Y));
      { width across the foot, run along the side, and the steps }
      Tag_(At(0, F.Width / 2, 0), 'width ' + FormatLen(F.Width, FD.Units));
      Tag_(At(F.Run / 2, 0, 0), 'run ' + FormatLen(F.Run, FD.Units));
      Tag_(At(F.Run, F.Width / 2, F.Rise), Format('rise %s - %d risers of %s, treads %s',
        [FormatLen(F.Rise, FD.Units), N, StairLen(R, FD.Units), StairLen(G, FD.Units)]));
    end;
  end;

  { beside the cursor: a three-step icon with the next point lit, and its
    name }
  U := Max(1, Round(FUIScale));
  GX := SX + 14 * U; GY := SY - 34 * U;
  C.Pen.Style := psSolid;
  C.Pen.Width := Max(2, Round(2 * FUIScale));
  C.Pen.Color := Ink;
  C.MoveTo(GX, GY + 24 * U);
  C.LineTo(GX + 8 * U, GY + 24 * U); C.LineTo(GX + 8 * U, GY + 16 * U);
  C.LineTo(GX + 16 * U, GY + 16 * U); C.LineTo(GX + 16 * U, GY + 8 * U);
  C.LineTo(GX + 24 * U, GY + 8 * U); C.LineTo(GX + 24 * U, GY);
  C.LineTo(GX + 34 * U, GY);
  C.Brush.Style := bsSolid;
  C.Brush.Color := Ink;
  C.Pen.Color := Ink;
  { the lit point: bigger than the line, ringed to read on any paper }
  C.Pen.Color := PixToColor(Theme.Text);
  C.Pen.Width := Max(1, Round(FUIScale));
  case FStairPick of
    1: begin C.Ellipse(GX + 19 * U, GY - 6 * U, GX + 31 * U, GY + 6 * U); Word_ := 'TOP'; end;
    2: begin C.Ellipse(GX - 6 * U, GY + 18 * U, GX + 6 * U, GY + 30 * U); Word_ := 'BOTTOM'; end;
  else
    begin
      { the width: an arrow across the flight }
      C.Brush.Style := bsClear;
      C.Pen.Color := Ink;
      C.Pen.Width := Max(2, Round(2 * FUIScale));
      C.MoveTo(GX + 2 * U, GY + 30 * U); C.LineTo(GX + 30 * U, GY + 30 * U);
      C.MoveTo(GX + 30 * U, GY + 30 * U); C.LineTo(GX + 25 * U, GY + 26 * U);
      C.MoveTo(GX + 30 * U, GY + 30 * U); C.LineTo(GX + 25 * U, GY + 34 * U);
      Word_ := 'SIDE';
    end;
  end;
  C.Brush.Style := bsClear;
  UIFont(C, 10, True, Theme.Text);
  C.Font.Color := Ink;
  C.TextOut(GX + 40 * U, GY - 2 * U, IntToStr(FStairPick) + '  ' + Word_);
  C.Pen.Width := 1;
  { and the chip keeps off it }
  TipAvoid(GX, GY + 24 * U, GX + 40 * U + C.TextWidth('3  BOTTOM'), GY);
end;

procedure TMainForm.StairResume(Data: PtrInt);
begin
  StairDialog;
end;

{ The radiant heat layout wizard.  It fills the selected floor where it is,
  so nothing is placed afterward; the new lines are left selected, as a push
  leaves its result selected. }
procedure TMainForm.BuildRadiantWizard(Again: Integer);
var
  Zones: TRadiantZones;
  Holes: TRadiantHoles;
  I, J, First, Z, K: Integer;
  Job, Was: TRadiantJob;
  JobId: string;
  Old, M: TIntArrayW;
  Doomed: array of Boolean;
  Spec: TRadiantSpec;
  Manifolds: TP3Array;
  Ports: TIntArray;
  Layouts: TRadiantResults;
  ZoneNames: TStringArray;
  R: TRadiantResult;
  Loops: Integer;
  Ft: Double;
begin
  { Each selected face is a zone with its own manifold (a floor drawn as one
    rectangle with lines across it is several zones); a face cut out of one
    is a hole and a no-go.  Ctrl+A or a drag both work: lines are ignored. }
  SetLength(Zones, 0);
  { a kept job reopened: its zones are its own, not the selection's }
  if Again > 0 then
  begin
    Old := nil;
    if RadiantGroupOf(Again, JobId) > 0 then Old := RadiantJobGroups(JobId, Was);
    if Length(Old) = 0 then
    begin
      FCmdMsg := 'That is not a radiant layout the drawing kept the job of - one built before 28 September was not kept.';
      pbCmd.Invalidate;
      Exit;
    end;
    hsDialogSkin.UseTheme(Themes[FThemeIdx]);
    if not TRadiantForm.Reopen(FD.Units, Was, Zones, Spec, Manifolds, Ports, Layouts, ZoneNames, Job) then Exit;
    PushUndo;
    { remove the job as built (every zone group and its contents) and put
      the wizard's result in its place, in one undo step }
    LeaveSheet;
    ResetTool;
    FD.Doc.Context := 0;
    SetLength(Doomed, FD.Doc.Live);
    for I := 0 to High(Doomed) do Doomed[I] := False;
    for K := 0 to High(Old) do
    begin
      M := FD.Doc.PartMembers(Old[K], True);
      for I := 0 to High(M) do Doomed[M[I]] := True;
    end;
    FD.Doc.DeleteMarked(Doomed);
  end
  else
  for I := 0 to High(FSel) do
    if (FSel[I] >= 0) and (FSel[I] < FD.Doc.Live) and (FD.Doc[FSel[I]].Kind = ekFace) then
    begin
      SetLength(Zones, Length(Zones) + 1);
      Zones[High(Zones)].Outline := FD.Doc[FSel[I]].Poly;
      SetLength(Zones[High(Zones)].Holes, Length(FD.Doc[FSel[I]].Holes));
      for J := 0 to High(FD.Doc[FSel[I]].Holes) do
        Zones[High(Zones)].Holes[J] := FD.Doc[FSel[I]].Holes[J];
    end;
  if Length(Zones) = 0 then
  begin
    FCmdMsg := 'Select the floor first - a face for each zone, or everything - then Radiant heat layout.';
    pbCmd.Invalidate;
    ShowMessage(FCmdMsg);
    Exit;
  end;
  if Again <= 0 then
  begin
    { the dialogs share one palette, the window's }
    hsDialogSkin.UseTheme(Themes[FThemeIdx]);
    if not TRadiantForm.Ask(FD.Units, Zones, Spec, Manifolds, Ports, Layouts, ZoneNames, Job) then Exit;
    JobId := NewRadiantJobId;
    PushUndo;
  end;
  First := FD.Doc.Live;
  Loops := 0; Ft := 0;
  for Z := 0 to High(Zones) do
  begin
    Holes := Copy(Zones[Z].Holes);
    for I := 0 to High(Spec.Extra) do
    begin
      SetLength(Holes, Length(Holes) + 1);
      Holes[High(Holes)] := Spec.Extra[I];
    end;
    SetLength(Spec.Manifolds, 1); SetLength(Spec.Ports, 1);
    Spec.Manifolds[0] := Manifolds[Z]; Spec.Ports[0] := Ports[Z];
    { use the layout the wizard already searched and showed; searching again
      took as long with nothing on screen }
    if Z > High(Layouts) then Continue;
    R := Layouts[Z];
    if not R.Ok then Continue;
    { the job's name and the zone's own, where given }
    J := BuildRadiant(FD.Doc, Zones[Z].Outline, Zones[Z].Holes, R, Spec, RGBToColor(200, 48, 32),
      IfThen(Spec.Tag <> '', Spec.Tag + ' ', 'Radiant ') + 'zone ' + IntToStr(Z + 1) +
      IfThen((Z <= High(ZoneNames)) and (ZoneNames[Z] <> ''), ' - ' + ZoneNames[Z], ''), Z);
    { the whole job kept in the zone's group, to reopen in the wizard and
      reprint its submittal (see hsRadiantJob) }
    if (J < FD.Doc.Live) and (FD.Doc[J].Kind = ekPart) then
      FD.Doc.SetPartData(FD.Doc[J].Grp, RadiantJobData(Job, Z, JobId));
    Inc(Loops, Length(R.Loops));
    Ft := Ft + R.TotalFt;
  end;
  { obstacles added in the wizard, once, not once per zone }
  RebuildFlatFaces;
  SeedRegions;
  RenderInk;
  RecomposeAll;
  SelectNone;
  for I := First to FD.Doc.Live - 1 do SelectAdd(I);
  FCmdMsg := Format('Radiant layout built: %d zone(s), %d loop(s), %s.',
    [Length(Zones), Loops, FormatLen(Ft, FD.Units)]);
  if Again > 0 then FCmdMsg := 'Built again - ' + FCmdMsg;
  pbScreen.Invalidate;
  pbCmd.Invalidate;
end;

function TMainForm.RadiantGroupOf(G: Integer; out JobId: string): Integer;
var
  Guard, Z: Integer;
begin
  Result := 0;
  JobId := '';
  Guard := 0;
  while (G > 0) and (Guard < 1000) do
  begin
    if IsRadiantData(FD.Doc.PartData(G), JobId, Z) then Exit(G);
    G := FD.Doc.PartParent(G);
    Inc(Guard);
  end;
  JobId := '';
end;

function TMainForm.RadiantJobGroups(const JobId: string; out Job: TRadiantJob): TIntArrayW;
var
  I, Z: Integer;
  Id: string;
  Datas: array of string;
begin
  Result := nil;
  Datas := nil;
  Job := Default(TRadiantJob);
  for I := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[I].Kind = ekPart) and (FD.Doc[I].Data <> '') and IsRadiantData(FD.Doc[I].Data, Id, Z) and
       (Id = JobId) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := FD.Doc[I].Grp;
      SetLength(Datas, Length(Datas) + 1);
      Datas[High(Datas)] := FD.Doc[I].Data;
    end;
  if (Length(Datas) = 0) or not RadiantJobFromData(Datas, Job) then Result := nil;
end;

procedure TMainForm.StringerSheetOf(G: Integer);
var
  F: TStairFrame;
  S: TStairSpec;
  Use: TStairUse;
begin
  if (G <= 0) or not StairFromJig(FD.Doc.PartJig(G), FD.Units, F, S, Use) then
  begin
    FCmdMsg := 'Those stairs do not say how they were made.';
    pbCmd.Invalidate;
    Exit;
  end;
  dlgStringers.FileName := FD.Doc.PartName(G) + ' - stringer sheet.pdf';
  if not dlgStringers.Execute then Exit;
  try
    StringerSheetPdf(F, S, Use, FD.Units, FD.Doc.PartName(G), dlgStringers.FileName);
    FCmdMsg := 'The stringer sheet: ' + ExtractFileName(dlgStringers.FileName);
    OpenDocument(dlgStringers.FileName);
  except
    on E: Exception do FCmdMsg := 'Could not write it: ' + E.Message;
  end;
  pbCmd.Invalidate;
end;

{ Reprint the submittal of a kept job, as built, from the zone groups, with
  no search and no wizard. }
procedure TMainForm.PrintSubmittalAgain(G: Integer);
var
  JobId: string;
  Job: TRadiantJob;
begin
  if (RadiantGroupOf(G, JobId) = 0) or (Length(RadiantJobGroups(JobId, Job)) = 0) then
  begin
    FCmdMsg := 'That is not a radiant layout the drawing kept the job of.';
    pbCmd.Invalidate;
    Exit;
  end;
  if Job.Title <> '' then dlgSubmittal.FileName := Job.Title + ' - radiant submittal.pdf'
  else dlgSubmittal.FileName := 'radiant submittal ' + FormatDateTime('yyyy-mm-dd', Now) + '.pdf';
  if not dlgSubmittal.Execute then Exit;
  Screen.Cursor := crHourGlass;
  try
    try
      SubmittalExport(Job, dlgSubmittal.FileName);
      FCmdMsg := 'The submittal, printed again: ' + ExtractFileName(dlgSubmittal.FileName);
    except
      on E: Exception do FCmdMsg := 'Could not write it: ' + E.Message;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  pbCmd.Invalidate;
end;

{ Copy, cut and paste.  The clipboard holds a deep copy, not indices, since
  the source sheet may not be in front, or even exist, by paste time.
  Pasting hands over to the move tool, as SketchUp does: it arrives on the
  cursor and a click puts it down. }
procedure TMainForm.CopySelection(Cut: Boolean);
begin
  if Length(FSel) = 0 then
  begin
    FCmdMsg := 'Nothing picked.  Click something first, or drag a box round it.';
    Exit;
  end;
  FClip := FD.Doc.CopyOut(FSel);
  if Cut then
  begin
    FCmdMsg := Format('Cut %d thing%s.  Ctrl+V puts %s down - on this sheet ' +
      'or any other.', [Length(FClip), IfThen(Length(FClip) = 1, '', 's'),
      IfThen(Length(FClip) = 1, 'it', 'them')]);
    DeleteSelection;
  end
  else
    FCmdMsg := Format('Copied %d thing%s.  Ctrl+V puts %s down - on this ' +
      'sheet or any other.', [Length(FClip), IfThen(Length(FClip) = 1, '', 's'),
      IfThen(Length(FClip) = 1, 'it', 'them')]);
  pbCmd.Invalidate;
end;

procedure TMainForm.PasteClip;
var
  N, First, Last, I: Integer;
  Idx: array of Integer;
  Mid: TP3;
begin
  if Length(FClip) = 0 then
  begin
    FCmdMsg := 'Nothing copied yet.  Pick something and press Ctrl+C.';
    Exit;
  end;
  PushUndo;
  N := FD.Doc.PasteIn(FClip, P3(0, 0, 0), First, Last);
  if N = 0 then
  begin
    FCmdMsg := 'Nothing in that worth pasting.';
    Exit;
  end;
  SetLength(Idx, Last - First + 1);
  for I := First to Last do Idx[I - First] := I;
  if not FD.Doc.MiddleOf(Idx, Mid) then Mid := P3(0, 0, 0);
  SeedRegions;
  RenderInk;
  RecomposeAll;
  { into the move tool, held by its middle }
  PlaceBuilt(First, Mid);
  FCmdMsg := Format('%d thing%s on the cursor - click to put %s down, or ' +
    'Esc to leave %s where they came from.',
    [N, IfThen(N = 1, '', 's'), IfThen(N = 1, 'it', 'them'),
     IfThen(N = 1, 'it', 'them')]);
  pbCmd.Invalidate;
end;

{ The wizards build at the origin; this hands the piece to the move tool so
  the next click places it with the usual snaps. }
procedure TMainForm.PlaceBuilt(First: Integer; const Ref: TP3);
var
  I: Integer;
begin
  SetTool(ptMove);
  SelectNone;
  for I := First to FD.Doc.Live - 1 do SelectAdd(I);
  FP1 := Ref;
  FD.Doc.VertsOf(FSel, FMoveVerts);
  FStage := 1;
  FDirLock := -1;
  FMoveCopy := False;
  FMoveRigid := True;
  FInput := '';
  FCmdMsg := 'Built.  Its entry corner is on the cursor - click where it goes, ' +
    'or type a point [x,y,z].';
  pbScreen.Invalidate;
  pbCmd.Invalidate;
end;

{ the release notes, from the help menu or /whatsnew }
procedure TMainForm.ShowWhatsNew;
var
  F: TWhatsNewForm;
begin
  { the dialogs share one palette, the window's }
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  F := TWhatsNewForm.Create(Self);
  try
    F.ShowAll;
  finally
    F.Free;
  end;
end;

{ Fetch the update, verify it, put it in place and restart.  The drawings go
  across in the draft and the handoff. }
procedure TMainForm.DoUpdate;
var
  Info: TUpdateInfo;
  Err, Why, Tmp: string;
  UpdateForm: TUpdateForm;
begin
  Why := WhyNotUpdate;
  if Why <> '' then
  begin
    MessageDlg('Cannot update here', Why + '.' + #13#10#13#10 +
      'Download it yourself from the Releases page instead.',
      mtInformation, [mbOK], 0);
    Exit;
  end;

  FCmdMsg := 'Looking...';
  pbCmd.Invalidate;
  Application.ProcessMessages;
  if not FetchLatest(Info, Err) then
  begin
    FCmdMsg := 'Could not check for an update - ' + Err;
    Exit;
  end;
  if not NewerThan(Info.Tag, CurrentVersion) then
  begin
    FCmdMsg := 'Already up to date - ' + CurrentVersion + '.';
    Exit;
  end;
  if MessageDlg('Update available',
       Format('%s is out, and this is %s.'#13#10#13#10 +
         'It will be fetched, put in place, and the program restarted.  ' +
         'Your drawings are kept just as they are - every sheet, and ' +
         'anything not saved yet stays not saved - and come straight back.',
         [Info.Tag, CurrentVersion]),
       mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
  begin
    FCmdMsg := 'Left alone.';
    Exit;
  end;

  SaveDraft;                          { whatever happens next, this survives }

  { beside the program, not the system temp: a portable copy keeps its
    scratch with it, and the rename must be on the same volume to be atomic }
  Tmp := AppDataDir + 'heckers-sketch-' + Info.Tag + '.download';
  { written before the update runs, since the update starts the new copy and
    it reads this straight away }
  WriteHandoff;
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  UpdateForm := TUpdateForm.Create(Self);
  try
    if UpdateForm.Run(Info, Tmp) then
    begin
      { No save question on the way out: the new copy waits for this one to
        exit and gives up if a question sits unanswered.  Everything is in
        the handoff. }
      FHandingOver := True;
      Close;
    end
    else
    begin
      DeleteFile(HandoffFile);
      FCmdMsg := 'The update was not installed.';
    end;
  finally
    UpdateForm.Free;
  end;
end;

{ The drawings for the copy that replaces this one.  The draft alone would
  restore them like a crash recovery, without file names or unsaved flags;
  this adds those as comment lines the reader skips. }
procedure TMainForm.WriteHandoff;
var
  L: TStringList;
  I: Integer;
begin
  try
    L := TStringList.Create;
    try
      L.Add('// handoff from ' + CurrentVersion);
      L.Add('// tab ' + IntToStr(FTabIdx));
      { each sheet's file and saved state are on it (see BuildSession) }
      BuildSession(L, True, -1, True);
      ForceDirectories(ExtractFilePath(HandoffFile));
      L.SaveToFile(HandoffFile);
    finally
      L.Free;
    end;
  except
    { the draft is already written; the handoff is the better copy, not the
      only one }
    on E: Exception do DeleteFile(HandoffFile);
  end;
end;

{ In the new copy: restore the drawings exactly as left, same files, same
  sheet in front, unsaved work still unsaved so closing asks.  Only after an
  update; one found any other time is stale and is deleted. }
function TMainForm.RestoreHandoff: Boolean;
var
  L: TStringList;
  I, K, Tab, NDirty, First: Integer;
  Path, S: string;
  Dirty: array of Boolean;
  Words: TStringArray;
begin
  Result := False;
  if not FileExists(HandoffFile) then Exit;
  Path := '';
  Tab := 0;
  Dirty := nil;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(HandoffFile);
    except
      Exit;
    end;
    for I := 0 to L.Count - 1 do
    begin
      S := L[I];
      { note lines at the top: "//" in Heck, "#" from older versions }
      if Copy(S, 1, 2) = '//' then S := '#' + Copy(S, 3, MaxInt)
      else if Copy(S, 1, 1) <> '#' then Break;
      if Copy(S, 1, 7) = '# path ' then Path := Copy(S, 8, MaxInt)
      else if Copy(S, 1, 6) = '# tab ' then Tab := StrToIntDef(Trim(Copy(S, 7, MaxInt)), 0)
      else if Copy(S, 1, 7) = '# dirty' then
      begin
        Words := Trim(Copy(S, 8, MaxInt)).Split([' '], TStringSplitOptions.ExcludeEmpty);
        for K := 0 to High(Words) do
          if StrToIntDef(Words[K], -1) >= 0 then
          begin
            if StrToInt(Words[K]) >= Length(Dirty) then
              SetLength(Dirty, StrToInt(Words[K]) + 1);
            Dirty[StrToInt(Words[K])] := True;
          end;
      end;
    end;
  finally
    L.Free;
  end;

  { the same guard the draft has: a handoff that crashes the program on load
    is set aside next time; the draft holds the same work }
  with TIniFile.Create(ConfigFile) do
  try
    WriteBool('startup', 'restoring', True);
  finally
    Free;
  end;
  try
    try
      Result := ReadSheets(HandoffFile, True, First);
      { the empty drawing the program started with gives way }
      if Result and (First > 0) then
      begin
        for I := 0 to First - 1 do FDrawings[I].Free;
        for I := First to High(FDrawings) do FDrawings[I - First] := FDrawings[I];
        SetLength(FDrawings, Length(FDrawings) - First);
        FD := nil;
      end;
    except
      Result := False;
    end;
  finally
    with TIniFile.Create(ConfigFile) do
    try
      WriteBool('startup', 'restoring', False);
    finally
      Free;
    end;
  end;
  DeleteFile(HandoffFile);
  if not Result or FLoadSkipped then Exit(False);

  { an older handoff carries one path for everything and dirty sheets by
    number }
  if (Path <> '') and (FDrawings[0].FilePath = '') then
    for I := 0 to High(FDrawings) do
    begin
      FDrawings[I].FilePath := Path;
      FDrawings[I].DocName := ChangeFileExt(ExtractFileName(Path), '');
    end;
  for I := 0 to High(FDrawings) do
    if (I < Length(Dirty)) and Dirty[I] then FDrawings[I].Dirty := True;
  NDirty := AnyDirty;
  if NDirty > 0 then Inc(FEditSeq);       { so the draft is written again too }
  ShowLoaded(EnsureRange(Tab, 0, High(FDrawings)));
  FRestored := True;
  FCmdMsg := 'Updated from ' + IfThen(FUpdatedFrom = '', 'the last version', FUpdatedFrom) +
    ' - your drawings are back just as you left them' +
    IfThen(NDirty = 0, '.',
      Format(', %d file%s not saved yet.', [NDirty, IfThen(NDirty = 1, '', 's')]));
  Trail(Format('picked up the handoff: %d sheets, %d not saved, from %s',
    [Length(FDrawings), NDirty, IfThen(Path = '', 'no file', ExtractFileName(Path))]));
end;

{ The window as it stands, as a bitmap the caller owns.  A bitmap rather than
  PNG bytes, because it is shown next and would have to be decoded again
  (and TBitmap.LoadFromStream reads BMP, not PNG). }
function TMainForm.WindowShot(out B: TBitmap): Boolean;
var
  DC: HDC;
  Grabbed: Boolean;
  Org: TPoint;

  { Cut the screen down to this program's own windows (main plus any dialog,
    with title bars).  The whole screen would include other monitors and
    other programs. }
  procedure OursOnly;
  const
    FRAME = 8;
    TITLE = 40;
  var
    I: Integer;
    R, F: TRect;
    Cut: TBitmap;
    Any: Boolean;
  begin
    Any := False;
    R := Rect(0, 0, 0, 0);
    for I := 0 to Screen.FormCount - 1 do
    begin
      if not Screen.Forms[I].Visible or (Screen.Forms[I].Parent <> nil) then Continue;
      F := Screen.Forms[I].BoundsRect;
      F := Rect(F.Left - FRAME, F.Top - TITLE, F.Right + FRAME, F.Bottom + FRAME);
      if not Any then R := F
      else R := Rect(Min(R.Left, F.Left), Min(R.Top, F.Top), Max(R.Right, F.Right), Max(R.Bottom, F.Bottom));
      Any := True;
    end;
    if not Any then Exit;
    R := Rect(Max(0, R.Left), Max(0, R.Top), Min(B.Width, R.Right), Min(B.Height, R.Bottom));
    if (R.Right - R.Left < 8) or (R.Bottom - R.Top < 8) then Exit;
    Cut := TBitmap.Create;
    try
      Cut.SetSize(R.Right - R.Left, R.Bottom - R.Top);
      Cut.Canvas.CopyRect(Rect(0, 0, Cut.Width, Cut.Height), B.Canvas, R);
    except
      Cut.Free;
      Exit;
    end;
    B.Free;
    B := Cut;
    Org := R.TopLeft;
  end;

begin
  { From inside a dialog, grab the screen (cut to our windows), since the
    window alone would leave out the dialog being reported. }
  Grabbed := False;
  Org := Point(0, 0);
  if FReportExtra <> '' then
  begin
    B := TBitmap.Create;
    try
      DC := GetDC(0);
      try
        B.LoadFromDevice(DC);
      finally
        ReleaseDC(0, DC);
      end;
      Grabbed := True;
      OursOnly;
    except
      FreeAndNil(B);
    end;
    { the fallback is the window image; DrawPointerOn is told which
      coordinates it has }
    if B = nil then B := GetFormImage;
  end
  else
    B := GetFormImage;
  Result := (B <> nil) and (B.Width >= 8) and (B.Height >= 8);
  if not Result then
  begin
    B.Free;
    B := nil;
  end
  else
    DrawPointerOn(B, Grabbed, Org);
end;

{ Neither a screen grab nor a form image includes the mouse pointer, so draw
  one where the cursor is.  Screen shots use screen coordinates and form
  images window coordinates; that is the thing to get right. }
procedure TMainForm.DrawPointerOn(B: TBitmap; ScreenCoords: Boolean; const Org: TPoint);
var
  P: TPoint;
  Arrow: array[0..6] of TPoint;
  I: Integer;
begin
  if B = nil then Exit;
  try
    P := Mouse.CursorPos;
    { a screen shot cut to our windows starts at Org on the screen }
    if ScreenCoords then P := Point(P.X - Org.X, P.Y - Org.Y)
    else P := ScreenToClient(P);
  except
    Exit;
  end;
  if (P.X < 0) or (P.Y < 0) or (P.X >= B.Width) or (P.Y >= B.Height) then Exit;

  { the ordinary pointer shape, at system size }
  Arrow[0] := Point(0, 0);
  Arrow[1] := Point(0, 17);
  Arrow[2] := Point(4, 13);
  Arrow[3] := Point(7, 20);
  Arrow[4] := Point(10, 18);
  Arrow[5] := Point(7, 12);
  Arrow[6] := Point(12, 12);
  for I := 0 to High(Arrow) do
    Arrow[I] := Point(Arrow[I].X + P.X, Arrow[I].Y + P.Y);

  B.Canvas.Pen.Color := clWhite;
  B.Canvas.Pen.Width := 3;
  B.Canvas.Brush.Style := bsClear;
  B.Canvas.Polygon(Arrow);
  B.Canvas.Pen.Color := clBlack;
  B.Canvas.Pen.Width := 1;
  B.Canvas.Brush.Style := bsSolid;
  B.Canvas.Brush.Color := clBlack;
  B.Canvas.Polygon(Arrow);

  { a ring too: an arrow on a busy drawing is easy to lose }
  B.Canvas.Brush.Style := bsClear;
  B.Canvas.Pen.Color := clRed;
  B.Canvas.Pen.Width := 2;
  B.Canvas.Ellipse(P.X - 13, P.Y - 13, P.X + 14, P.Y + 14);
  B.Canvas.Pen.Width := 1;
end;

{ Count down from Seconds with the program still usable, so the user can set
  the screen up.  Not a dialog: messages are pumped and the number is painted
  on the canvas by the normal paint path. }
procedure TMainForm.ShotCountdown(Seconds: Integer);
var
  Until_: QWord;
begin
  FShotCount := Seconds;
  while FShotCount > 0 do
  begin
    FCmdMsg := Format(
      'Set the screen up the way it went wrong - picture in %d.', [FShotCount]);
    FScreenDirty := True;
    pbScreen.Invalidate;
    pbCmd.Invalidate;
    Until_ := GetTickCount64 + 1000;
    while GetTickCount64 < Until_ do
    begin
      Application.ProcessMessages;
      if Application.Terminated then
      begin
        FShotCount := 0;
        Exit;
      end;
      Sleep(15);
    end;
    Dec(FShotCount);
  end;
end;

{ the countdown number, and the flash }
procedure TMainForm.PaintShotOverlay(C: TCanvas);
var
  R: TRect;
  S: string;
  Sz: TSize;
  Pad: Integer;
begin
  if FShotFlash then
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := clWhite;
    C.FillRect(0, 0, pbScreen.Width, pbScreen.Height);
    Exit;
  end;
  if FShotCount <= 0 then Exit;

  Pad := Round(14 * FUIScale);
  C.Font.Name := 'Sans';
  C.Font.Size := Round(30 * FUIScale);
  C.Font.Style := [fsBold];
  S := IntToStr(FShotCount);
  Sz := C.TextExtent(S);

  R := Rect(pbScreen.Width - Sz.cx - Pad * 3, Pad,
            pbScreen.Width - Pad, Pad * 2 + Sz.cy);
  C.Brush.Style := bsSolid;
  C.Brush.Color := $001A1A1A;
  C.Pen.Color := $0060C0FF;
  C.Pen.Width := Max(1, Round(2 * FUIScale));
  C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Pad, Pad);

  C.Brush.Style := bsClear;
  C.Font.Color := $00FFFFFF;
  C.TextOut(R.Left + (R.Right - R.Left - Sz.cx) div 2,
            R.Top + (R.Bottom - R.Top - Sz.cy) div 2, S);

  C.Font.Size := Round(9 * FUIScale);
  C.Font.Style := [];
  C.Font.Color := $00D0D0D0;
  S := 'set the screen up - picture in';
  Sz := C.TextExtent(S);
  C.Brush.Style := bsSolid;
  C.Brush.Color := $001A1A1A;
  C.TextOut(R.Left - Sz.cx - Pad, R.Top + (R.Bottom - R.Top - Sz.cy) div 2, S);
end;

procedure TMainForm.ReportFromDialog(const Where, Fields: string);
begin
  FReportExtra := Where + LineEnding + Fields;
  try
    ReportBug;
  finally
    FReportExtra := '';
  end;
end;

{ Take the report picture: optional countdown, the shot, then the flash.
  The report form shows the result. }
function TMainForm.CaptureShot(Wait: Boolean; out Bmp: TBitmap): Boolean;
var
  WasMsg: string;
  Until_: QWord;
begin
  Result := False;
  Bmp := nil;
  if FShotBusy then Exit;
  FShotBusy := True;
  WasMsg := FCmdMsg;
  try
    Application.ProcessMessages;
    if Wait then
    begin
      FCmdMsg := 'Setting up the picture - it is taken when this reaches zero.';
      ShotCountdown(10);
      if Application.Terminated then Exit;
    end;

    { Nothing about taking the picture may be in it: the countdown number goes
      and the command bar is restored to what it would have said.  Wait a
      moment so the closed question box is painted over. }
    Until_ := GetTickCount64 + 350;
    while GetTickCount64 < Until_ do
    begin
      Application.ProcessMessages;
      Sleep(15);
    end;
    FShotCount := 0;
    FShotFlash := False;
    FCmdMsg := WasMsg;
    FScreenDirty := True;
    pbScreen.Invalidate;
    pbCmd.Invalidate;
    Application.ProcessMessages;

    if not WindowShot(Bmp) then Exit;

    { and the flash after it, not before }
    FShotFlash := True;
    pbScreen.Invalidate;
    Application.ProcessMessages;
    Sleep(110);
    FShotFlash := False;
    FScreenDirty := True;
    pbScreen.Invalidate;
    Application.ProcessMessages;
    Result := True;
  finally
    FShotBusy := False;
    FShotCount := 0;
    FShotFlash := False;
    FCmdMsg := WasMsg;
    FScreenDirty := True;
    pbScreen.Invalidate;
    pbCmd.Invalidate;
  end;
end;

{ A bug report in the user's own words, with state gathered at the moment
  of sending.  The drawing is offered, not assumed: it is the most useful
  thing for finding a fault, but it is somebody's work. }
function TMainForm.ReportBug(const Preamble, ShotFile, DocFile: string): Boolean;
var
  Sending: TSendForm;
  ShotBmp: TBitmap;
  Png: TPortableNetworkGraphic;
  DocOn: Boolean;
  Res: Integer;
  Body, Name_, Err, Note, ShotErr: string;
  WantShot: Boolean;
  NThings: Integer;
  Shot: TMemoryStream;
  L: TStringList;
  HasDrawing: Boolean;
  SheetName_, MachineIs: string;
  FileRep, FilePic, NSent: Integer;
  Total: Int64;

  { a line of the report by its leading key ("version", "when") }
  function LineOf(const Text, Key: string): string;
  var
    LL: TStringList;
    K: Integer;
  begin
    Result := '';
    LL := TStringList.Create;
    try
      LL.Text := Text;
      for K := 0 to LL.Count - 1 do
        if Copy(LL[K], 1, Length(Key) + 1) = Key + ':' then
        begin
          Result := Trim(Copy(LL[K], Length(Key) + 2, MaxInt));
          Exit;
        end;
    finally
      LL.Free;
    end;
  end;

  { one key=value from the report's state lines ("mode=", "theme=") }
  function Tok(const Key: string): string;
  var
    K: Integer;
  begin
    Result := '';
    K := Pos(Key, Body);
    if K = 0 then Exit('-');
    Inc(K, Length(Key));
    while (K <= Length(Body)) and not (Body[K] in [' ', #10, #13]) do
    begin
      Result := Result + Body[K];
      Inc(K);
    end;
  end;

  function BodyLine(const Key: string): string;
  begin
    Result := LineOf(Body, Key);
  end;

  function MachineLine(const Key: string): string;
  begin
    Result := LineOf(MachineIs, Key);
  end;

  function KB(Bytes: Int64): string;
  begin
    if Bytes < 10 * 1024 then Result := FormatFloat('0.0', Bytes / 1024) + ' KB'
    else Result := FormatFloat('0', Bytes / 1024) + ' KB';
  end;

begin
  Result := False;

  { The picture is taken first, of the window as it is, and the report form
    shows it while the user writes, so words and picture match.  From the
    form it can be retaken now, retaken after a ten second countdown, or
    dropped, without losing what was typed. }
  Application.ProcessMessages;
  ShotBmp := nil;
  if (ShotFile <> '') and FileExists(ShotFile) then
  begin
    { for a crash, the picture saved when it happened; the screen now is
      the restart }
    try
      ShotBmp := TBitmap.Create;
      ShotBmp.LoadFromFile(ShotFile);
    except
      FreeAndNil(ShotBmp);
    end;
  end
  else
    CaptureShot(False, ShotBmp);
  WantShot := ShotBmp <> nil;

  Note := '';
  DocOn := True;
  try
  repeat
  { count the drawing that will actually go: for a crash, the one saved
    when it happened }
  NThings := DocThings(DocFile);
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  if WantShot then
    Res := TReportDialog.Ask(Self, Preamble <> '', NThings, ShotBmp, Note, DocOn)
  else
    Res := TReportDialog.Ask(Self, Preamble <> '', NThings, nil, Note, DocOn);

  if Res in [mrRetry, mrAll] then
  begin
    FreeAndNil(ShotBmp);
    CaptureShot(Res = mrAll, ShotBmp);
    WantShot := ShotBmp <> nil;
  end
  else if Res = mrIgnore then
  begin
    FreeAndNil(ShotBmp);
    WantShot := False;
  end;
  until not (Res in [mrRetry, mrAll, mrIgnore]);

  if Res <> mrOK then
  begin
    FCmdMsg := 'Report canceled.';
    Exit;
  end;

    Body := 'Heckers Sketch report' + LineEnding +
      specialize IfThen<string>(Preamble = '', '',
        'this one followed a crash' + LineEnding) +
      'version: ' + CurrentVersion + '  built ' + BUILD_STAMP + LineEnding +
      'when: ' + DateTimeToStr(Now) + LineEnding + LineEnding +
      'what they said:' + LineEnding +
      specialize IfThen<string>(Note = '', '(nothing written)', Note) +
      LineEnding + LineEnding +
      'state:' + LineEnding + DiagnosticText +
      LineEnding + 'settings and circumstances:' + LineEnding + SettingsText +
      LineEnding + 'machine:' + LineEnding + MachineText;
    if FReportExtra <> '' then
      Body := Body + LineEnding + 'in the dialog:' + LineEnding + FReportExtra;
    if Preamble <> '' then
      Body := Body + LineEnding + 'the crash it left behind:' + LineEnding +
        Preamble;
    if DocOn then
    begin
      L := TStringList.Create;
      try
        { For a crash, send the drawing saved when it happened; by now the
          screen shows an empty sheet or a restored draft, neither of which
          is what went wrong. }
        if (DocFile <> '') and FileExists(DocFile) then
        begin
          try
            L.LoadFromFile(DocFile);
          except
            L.Clear;
            BuildSession(L, False, -1, False, True);
          end;
        end
        else
          BuildSession(L, False, -1, False, True);
        Body := Body + LineEnding + 'the drawing, sent on purpose:' +
          LineEnding + L.Text;
      finally
        L.Free;
      end;
    end;
    Name_ := UniqueReportName('bug', CurrentVersion);

  { the picture is encoded to PNG only now that it is being sent }
  Shot := TMemoryStream.Create;
  try
    if WantShot and (ShotBmp <> nil) then
    begin
      Png := TPortableNetworkGraphic.Create;
      try
        Png.Assign(ShotBmp);
        Png.SaveToStream(Shot);
      finally
        Png.Free;
      end;
    end;
    if Shot.Size = 0 then WantShot := False;
    KeepReportCopy(Name_, Body, Shot);

    FCmdMsg := 'Sending...';
  pbCmd.Invalidate;
  { Shown going out stage by stage, like an update coming in, with a moment
    on each so the user can see what is sent and how big. }
  HasDrawing := Pos('the drawing, sent on purpose', Body) > 0;
  { the machine lines are those after "machine:", so a "machine: Dell..."
    line is not mistaken for the heading }
  MachineIs := Body;
  if Pos(LineEnding + 'machine:' + LineEnding, MachineIs) > 0 then
    Delete(MachineIs, 1, Pos(LineEnding + 'machine:' + LineEnding, MachineIs) +
      Length(LineEnding + 'machine:' + LineEnding) - 1);
  if Pos(LineEnding + 'the drawing, sent on purpose', MachineIs) > 0 then
    SetLength(MachineIs, Pos(LineEnding + 'the drawing, sent on purpose', MachineIs));
  if FD <> nil then SheetName_ := FD.Name else SheetName_ := '-';
  Sending := TSendForm.CreateSending(Self, 'Sending your report');
  try
    { The whole summary is laid out first with files listed as waiting; then
      each file's row changes as it is encrypted, sent and arrives.  The
      facts are read back from the report text, so the summary cannot say
      something the report does not. }
    FileRep := Sending.AddFile(IfThen(HasDrawing, 'Report and drawing', 'Report'),
      Name_, KB(Length(Body)));
    if WantShot then
      FilePic := Sending.AddFile('Picture', ChangeFileExt(Name_, '.png'), KB(Shot.Size))
    else
      FilePic := Sending.AddFile('Picture', 'none', '-', ssNone);

    { machine and program first: on a bench of test machines that is what
      is looked for }
    Sending.Fact('This machine', 'System', MachineLine('os'));
    Sending.Fact('This machine', 'Computer', MachineLine('machine'));
    Sending.Fact('This machine', 'Processor', MachineLine('cpu'));
    Sending.Fact('This machine', 'Memory', MachineLine('ram'));
    Sending.Fact('This machine', 'Graphics', MachineLine('graphics'));
    Sending.Fact('This machine', 'Display', MachineLine('display'));
    Sending.Fact('This machine', 'Locale', MachineLine('locale'));

    Sending.Fact('The program', 'Version', BodyLine('version'));
    Sending.Fact('The program', 'Toolkit', MachineLine('toolkit'));
    Sending.Fact('The program', 'Memory', MachineLine('program memory'));
    Sending.Fact('The program', 'Running', MachineLine('program'));
    Sending.Fact('The program', 'Working in', Tok('mode=') + ' mode, ' +
      Tok('view=') + ' view, ' + Tok('units=') + ', ' + Tok('theme=') + ' theme');
    Sending.Fact('The program', 'Drawing area', Tok('screen=') +
      ' at scaling ' + Tok('scaling='));
    Sending.Fact('The program', 'Network', Tok('net='));

    Sending.Fact('The report', 'Your words', IfThen(Note = '', 'nothing written',
      Format('%d characters', [Length(Note)])));
    Sending.Fact('The report', 'The drawing', IfThen(HasDrawing,
      Format('included - %d things', [NThings]), 'not included'));
    Sending.Fact('The report', 'Sheet', SheetName_);
    Sending.Fact('The report', 'The picture', IfThen(WantShot,
      'the program window, ' + KB(Shot.Size), 'none'));
    Sending.Fact('The report', 'Also in it', 'the tool, the view, the last ' +
      'few dozen things that happened, and this machine.  Nothing about you.');
    Sending.Fact('The report', 'When', BodyLine('when'));

    Sending.Stage('Preparing the report',
      Format('%s of text: what you wrote, the state of the program%s.',
        [KB(Length(Body)),
         IfThen(HasDrawing, ', and the drawing', '')]), 15);
    { the pauses are deliberate (see above); encrypting happens inside
      SendReport and would otherwise be invisible }
    Sending.FileState(FileRep, ssEncrypting);
    Sending.Stage('Encrypting the report',
      Format('Encrypting %s to a key only we hold - nothing in it can be ' +
        'read on the way, whatever happens to the postbox it travels through.',
        [KB(Length(Body))]), 28, 1600);
    Sending.FileState(FileRep, ssSending);
    Sending.Stage('Sending the report', Name_, 40);
    if SendReport(Name_, Body, Err) then
    begin
      Result := True;
      Sending.FileState(FileRep, ssSent, KB(LastSealedBytes));
      Total := LastSealedBytes;
      NSent := 1;
      FCmdMsg := 'Report sent - thank you.  (' + Name_ + ')';
      { The picture goes as its own file with the report's name, so they
        pair up.  If it fails, the report has already gone. }
      if WantShot then
        try
          Sending.FileState(FilePic, ssEncrypting);
          Sending.Stage('Encrypting and sending the picture',
            Format('%s of screenshot, as %s', [KB(Shot.Size),
              ChangeFileExt(Name_, '.png')]), 75);
          Sending.FileState(FilePic, ssSending);
          Shot.Position := 0;
          if not SendBinary(ChangeFileExt(Name_, '.png'), Shot, 'image/png',
               ShotErr) then
          begin
            FCmdMsg := FCmdMsg + '  (the picture did not go: ' + ShotErr + ')';
            Sending.FileState(FilePic, ssFailed, '', ShotErr);
          end
          else
          begin
            Sending.FileState(FilePic, ssSent, KB(LastSealedBytes));
            Total := Total + LastSealedBytes;
            Inc(NSent);
          end;
        except
          on Ex: Exception do
          begin
            FCmdMsg := FCmdMsg + '  (no picture: ' + Ex.ClassName + ')';
            Sending.FileState(FilePic, ssFailed, '', Ex.ClassName);
          end;
        end;
      Sending.Finish('Sent - thank you',
        Format('%d %s, %s, encrypted before leaving this computer.',
          [NSent, IfThen(NSent = 1, 'file', 'files'), KB(Total)]),
        '<h3>How it traveled</h3><ul>' +
        '<li><b>Encrypted on this computer</b>, before anything left it, to ' +
        'a key only the project holds.</li>' +
        '<li>The postbox it passes through sees a name and a size, and ' +
        'nothing that can be read.</li>' +
        '<li><b>A copy of what you sent</b> is kept on this computer, not ' +
        'encrypted, so you can see exactly what went:<br><code>' +
        HtmlEsc(AppDataDir + 'reports-sent') + '</code></li></ul>', True);
    end
    else
    begin
      FCmdMsg := 'The report could not be sent - ' + Err;
      Sending.FileState(FileRep, ssFailed, '', Err);
      if WantShot then Sending.FileState(FilePic, ssFailed, '', 'not tried');
      Sending.Finish('The report did not go', Err,
        '<h3>What happened</h3><ul>' +
        '<li>' + HtmlEsc(Err) + '</li>' +
        '<li><b>Nothing is lost and nothing is broken</b> - it just did not ' +
        'send.</li>' +
        '<li>A copy of the report is kept on this computer:<br><code>' +
        HtmlEsc(AppDataDir + 'reports-sent') + '</code></li>' +
        '<li>The help button has the project page if you would rather say ' +
        'it there.</li></ul>', False);
    end;
  finally
    Sending.Free;
  end;
  finally
    Shot.Free;
  end;
  finally
    ShotBmp.Free;
  end;
  pbCmd.Invalidate;
end;

{ how many things are in the drawing a report would carry }
function TMainForm.DocThings(const DocFile: string): Integer;
var
  L: TStringList;
  I: Integer;
begin
  Result := FD.Doc.Live;
  if (DocFile = '') or not FileExists(DocFile) then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(DocFile);
      Result := 0;
      for I := 0 to L.Count - 1 do
        if (Copy(L[I], 1, 5) = 'LINE ') or (Copy(L[I], 1, 5) = 'FACE ') or
           (Copy(L[I], 1, 4) = 'ARC ') or (Copy(L[I], 1, 5) = 'TEXT ') or
           (Copy(L[I], 1, 4) = 'DIM ') or (Copy(L[I], 1, 6) = 'GUIDE ') then
          Inc(Result);
    except
      Result := FD.Doc.Live;
    end;
  finally
    L.Free;
  end;
end;

{ Lay a piece out flat.  A click picks it, not the selection: click any face
  and the whole solid is used. }
procedure TMainForm.StartUnfold;
begin
  FUnfoldPick := True;
  pbScreen.Cursor := crCross;
  FCmdMsg := 'Click any face of the piece to lay it out flat.  Esc to stop.';
  pbCmd.Invalidate;
end;

procedure TMainForm.UnfoldAt(SX, SY: Integer);
var
  F: Integer;
  Faces: TIntArray;
  Pat: TFlatPattern;
begin
  FUnfoldPick := False;
  F := FD.Doc.HitFace(Proj, SX, SY);
  if F < 0 then
  begin
    FCmdMsg := 'Nothing there to lay out - click a face of the piece.';
    pbCmd.Invalidate;
    Exit;
  end;
  Faces := SolidFaces(FD.Doc, F);
  if Length(Faces) = 0 then
  begin
    FCmdMsg := 'That face is not part of anything to lay out.';
    pbCmd.Invalidate;
    Exit;
  end;
  Pat := Unfold(FD.Doc, Faces);
  if not Pat.Ok then
  begin
    FCmdMsg := 'It could not be laid out - ' + Pat.Why;
    pbCmd.Invalidate;
    Exit;
  end;
  Trail(Format('unfolded %d panels', [Pat.Laid]));
  FCmdMsg := Format('Laid out: %d panels, sheet %s x %s',
    [Pat.Laid, FormatLen(Pat.MaxX - Pat.MinX, FD.Units),
     FormatLen(Pat.MaxY - Pat.MinY, FD.Units)]);
  pbCmd.Invalidate;
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  ShowFlatPattern(Pat, FD.Units, 'Flat pattern');
end;

{ A crash last time leaves a report behind.  Offer to send it, opening it
  for reading first, since it carries file paths. }
procedure TMainForm.OfferCrashReport(JustNow: Boolean);
var
  Fn: string;
  L: TStringList;

  { Move a crash report aside under a timestamped name.  A fixed name fails
    the second time on Windows (the rename target exists) and the report is
    offered again on every start. }
  procedure KeepAside(const Base: string);
  var
    Dst: string;
  begin
    Dst := Base + '.' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.kept';
    if FileExists(Dst) then DeleteFile(Dst);
    if RenameFile(Base, Dst) then
      FCmdMsg := 'Kept it: ' + ExtractFileName(Dst)
    else
    begin
      { cannot even be moved aside: let it go rather than ask forever }
      DeleteFile(Base);
      FCmdMsg := 'That crash report could not be kept, so it was cleared.';
    end;
  end;

begin
  Fn := ExtractFilePath(ExpandFileName(ParamStr(0))) + 'heckers-sketch-crash.txt';
  if not FileExists(Fn) then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(Fn);
    except
      Exit;
    end;
    if L.Count = 0 then Exit;
    { Sent through the same postbox as a hand-written report, so no GitHub
      account is needed.  Offered, not assumed. }
    case MessageDlg(IfThen(JustNow, 'Something went wrong', 'It crashed last time'),
           IfThen(JustNow,
             'Something just went wrong inside the program.  It is still ' +
             'running, and a report has been written.',
             'There is a crash report from a previous run.') + #13#10#13#10 +
           'Send it?  You get to say what you were doing first, and to see ' +
           'what is being sent.  Nothing goes anywhere until you press Send.',
           mtConfirmation, [mbYes, mbNo], 0) of
      mrYes:
        { Delete the local copies only after a successful send, so a failed
          send can be retried.  Renaming onto ".sent" fails on Windows when
          that name already exists. }
        if ReportBug(L.Text, Fn + '.png', Fn + '.hsk') then
        begin
          DeleteFile(Fn);
          DeleteFile(Fn + '.png');
          DeleteFile(Fn + '.hsk');
          FCmdMsg := FCmdMsg + '  It will not ask about this one again.';
        end
        else
          KeepAside(Fn);
    else
      KeepAside(Fn);
    end;
  finally
    L.Free;
  end;
end;

{ Shaking the mouse picks the plane: sideways lays the shape down, up and
  down stands it up.  The plane latches; Esc releases it.  Needs four
  reversals of a dozen pixels or more within 0.75 s, mostly on one axis;
  ordinary drawing never does that. }
procedure TMainForm.ShakeWatch(X, Y: Integer);
const
  JERK_PX  = 12;
  JERK_N   = 4;
  JERK_MS  = 750;
var
  Now64: QWord;
  D, Sg: Integer;
  Was: TPlane;
begin
  { not the dimension tool: its line follows the pointer (see DimOffset3) }
  if not (FTool in [ptLine, ptRect, ptCircle, ptArc]) then Exit;
  if FD.View = vkPlan then Exit;        // only one plane makes sense there

  Now64 := GetTickCount64;
  if Now64 - FShTX > JERK_MS then FShNX := 0;
  if Now64 - FShTY > JERK_MS then FShNY := 0;

  D := X - FShX;
  if Abs(D) >= JERK_PX then
  begin
    if D > 0 then Sg := 1 else Sg := -1;
    if (FShDirX <> 0) and (Sg <> FShDirX) then
    begin
      Inc(FShNX);
      FShTX := Now64;
    end;
    FShDirX := Sg;
    FShX := X;
  end;

  D := Y - FShY;
  if Abs(D) >= JERK_PX then
  begin
    if D > 0 then Sg := 1 else Sg := -1;
    if (FShDirY <> 0) and (Sg <> FShDirY) then
    begin
      Inc(FShNY);
      FShTY := Now64;
    end;
    FShDirY := Sg;
    FShY := Y;
  end;

  if (FShNX < JERK_N) and (FShNY < JERK_N) then Exit;

  Was := FD.Plane;
  if FShNY >= FShNX then
  begin
    { up and down: stand it up, on whichever upright plane a straight-up drag
      would choose, so it agrees with dragging }
    FD.Plane := PlaneByDrag(Proj, FCur, FMouseSX, FMouseSY - 200, plXZ, 1.0);
    if FD.Plane = plXY then FD.Plane := plXZ;
    FCmdMsg := 'Standing it up - ' + PlaneName + '.  Shake sideways to lay ' +
      'it flat, Esc to follow faces again.';
  end
  else
  begin
    FD.Plane := plXY;
    FCmdMsg := 'Laying it flat.  Shake up and down to stand it up, Esc to ' +
      'follow faces again.';
  end;
  FPlaneHeld := True;
  FShNX := 0;
  FShNY := 0;

  if FD.Plane <> Was then
  begin
    RepaintPaper;
    RenderInk;
    RecomposeAll;
  end;
  FScreenDirty := True;
  pbCmd.Invalidate;
end;

{ Everything being drawn, as screen points, so the hold-to-cancel strain is
  laid along the whole shape (a rectangle strains as a rectangle), not along
  one strand from the first corner. }
function TMainForm.StrainOutline(out Pts: TPointFArray): Boolean;
var
  RectPrev: TP3Array;
  K: Integer;
  R: Double;
  Nm: TP3;
  ArcPl: TPlane;
  ArcC: TP3;
  ArcR, ArcA0, ArcSw, ArcBulge: Double;
begin
  Pts := nil;
  Result := False;
  case FTool of
    ptRect:
      if FStage = 1 then
      begin
        RectPrev := RectCorners(FP1, RectTarget, FD.Plane);
        SetLength(Pts, 5);
        for K := 0 to 3 do Pts[K] := ScreenOf(RectPrev[K]);
        Pts[4] := Pts[0];
      end;
    ptCircle:
      if FStage = 1 then
      begin
        R := Dist(FP1, FCur);
        if R > 1E-9 then
        begin
          SetLength(Pts, FSidesCircle + 1);
          for K := 0 to FSidesCircle do
            Pts[K] := ScreenOf(ArcPoint(FP1, R,
              2 * Pi * K / FSidesCircle, FD.Plane));
        end;
      end;
    ptOffset:
      if FStage = 1 then
      begin
        RectPrev := OffsetPreview;
        if Length(RectPrev) >= 3 then
        begin
          SetLength(Pts, Length(RectPrev) + 1);
          for K := 0 to High(RectPrev) do Pts[K] := ScreenOf(RectPrev[K]);
          Pts[High(Pts)] := Pts[0];
        end;
      end;
    ptPush, ptDrill:
      { the face where it would have landed, straining and going back }
      if (FStage = 1) and (FPushFace >= 0) and (FPushFace < FD.Doc.Live) then
      begin
        RectPrev := FD.Doc[FPushFace].Poly;
        if Length(RectPrev) >= 3 then
        begin
          R := PushDistance;
          Nm := FD.Doc.FaceNormal(FPushFace);
          SetLength(Pts, Length(RectPrev) + 1);
          for K := 0 to High(RectPrev) do
            Pts[K] := ScreenOf(P3(RectPrev[K].X + Nm.X * R,
                                  RectPrev[K].Y + Nm.Y * R,
                                  RectPrev[K].Z + Nm.Z * R));
          Pts[High(Pts)] := Pts[0];
        end;
      end;
    ptArc:
      { the curve itself, not the chord under it }
      if FStage = 2 then
      begin
        if ArcPicks(FCur, ArcPl, ArcC, ArcR, ArcA0, ArcSw, ArcBulge) then
        begin
          SetLength(Pts, FSidesArc + 1);
          for K := 0 to FSidesArc do
            Pts[K] := ScreenOf(ArcPoint(ArcC, ArcR,
              ArcA0 + ArcSw * K / FSidesArc, ArcPl));
        end;
      end;
  end;
  { anything else (a line, an arc still being aimed, a move) is one strand }
  if Length(Pts) < 2 then
  begin
    SetLength(Pts, 2);
    Pts[0] := ScreenOf(FP1);
    Pts[1] := PtF(FMouseSX, FMouseSY);
  end;
  Result := True;
end;

{ The whole outline under tension: each side bows away from the middle and
  trembles harder as it nears the break.  One burst and one caption at the
  middle, since it is one gesture destroying one thing. }
procedure TMainForm.PaintStrainPath(C: TCanvas; const Pts: TPointFArray;
  T: Single);
var
  I: Integer;
  CX, CY: Double;
begin
  if Length(Pts) < 2 then Exit;
  CX := 0;
  CY := 0;
  for I := 0 to High(Pts) do
  begin
    CX := CX + Pts[I].X / Length(Pts);
    CY := CY + Pts[I].Y / Length(Pts);
  end;
  for I := 0 to High(Pts) - 1 do
    PaintStrainSeg(C, Pts[I], Pts[I + 1], T, Length(Pts) > 2, CX, CY);
  PaintStrainMark(C, CX, CY, T);
end;

{ One side of it: bows away from CX,CY when the shape has a middle, to one
  side when it is a single strand. }
procedure TMainForm.PaintStrainSeg(C: TCanvas; const A, B: TPointF; T: Single;
  Outward: Boolean; CX, CY: Double);
var
  I, N, W: Integer;
  MX, MY, DX, DY, L, NX, NY, Bow, Sh: Double;
  P0, P1: TPointF;
  Col: TPix;
begin
  T := EnsureRange(T, 0, 1);
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  L := Sqrt(DX * DX + DY * DY);
  if L < 2 then Exit;
  NX := -DY / L;
  NY := DX / L;
  { away from the middle, so the whole shape swells consistently }
  if Outward and
     (NX * ((A.X + B.X) / 2 - CX) + NY * ((A.Y + B.Y) / 2 - CY) < 0) then
  begin
    NX := -NX;
    NY := -NY;
  end;

  { it bows away from the pull and trembles harder the nearer it gets }
  Bow := 8 * FUIScale * Sin(T * Pi) * 0.9;
  Sh := 2.4 * FUIScale * T * T;
  MX := (A.X + B.X) / 2 + NX * Bow + (Random - 0.5) * 2 * Sh;
  MY := (A.Y + B.Y) / 2 + NY * Bow + (Random - 0.5) * 2 * Sh;

  { From ink color to hot red early, as a warning.  It gets bolder, not
    thinner: about to let go looks strained, not frail. }
  Col := MixPix(AnnotColor, Pix(230, 38, 28), Power(T, 0.7));
  C.Pen.Style := psSolid;
  C.Pen.Color := PixToColor(Col);

  N := 12;
  for I := 0 to N - 1 do
  begin
    P0 := QuadAt(A, PtF(MX, MY), B, I / N);
    P1 := QuadAt(A, PtF(MX, MY), B, (I + 1) / N);
    { bold all over; only at the very end does the middle give }
    W := Round((1.6 + 4.2 * T) * FUIScale);
    if T > 0.7 then
      W := Round(W * (1 - 0.75 * ((T - 0.7) / 0.3) * Sin((I + 0.5) / N * Pi)));
    C.Pen.Width := Max(1, W);
    C.MoveTo(Round(P0.X), Round(P0.Y));
    C.LineTo(Round(P1.X), Round(P1.Y));
  end;

  C.Pen.Width := 1;
end;

{ The shards and the warning, once, at the middle of what is being destroyed
  (not once per side). }
procedure TMainForm.PaintStrainMark(C: TCanvas; CX, CY: Double; T: Single);
var
  I: Integer;
  Ang, R: Double;
  Col: TPix;
  Cap: string;
  Sz: TSize;
begin
  T := EnsureRange(T, 0, 1);
  Col := MixPix(AnnotColor, Pix(230, 38, 28), Power(T, 0.7));
  C.Pen.Style := psSolid;
  C.Pen.Color := PixToColor(Col);

  { at the very end it comes apart: shards off the middle }
  if T > 0.78 then
  begin
    C.Pen.Width := Max(1, Round(2 * FUIScale));
    R := (T - 0.78) / 0.22 * 13 * FUIScale;
    for I := 0 to 5 do
    begin
      Ang := I * Pi / 3 + T * 3;
      C.MoveTo(Round(CX + Cos(Ang) * R * 0.35), Round(CY + Sin(Ang) * R * 0.35));
      C.LineTo(Round(CX + Cos(Ang) * R), Round(CY + Sin(Ang) * R));
    end;
  end;

  { announce it: a destructive gesture met by accident looks like a bug }
  if T > 0.12 then
  begin
    { worded for what happens to this tool's work: a push that never
      happened puts the face back rather than throwing anything away }
    if FTool = ptLine then
    begin
      if T > 0.7 then Cap := 'LETTING GO...'
      else Cap := 'keep holding to snap the line off';
    end
    else if FTool in [ptPush, ptDrill, ptOffset] then
    begin
      if T > 0.7 then Cap := 'PUTTING IT BACK...'
      else Cap := 'changed your mind?  keep holding';
    end
    else
    begin
      if T > 0.7 then Cap := 'THROWING IT AWAY...'
      else Cap := 'made a mess?  keep holding';
    end;
    UIFont(C, 9, T > 0.7, Col);
    C.Brush.Style := bsSolid;
    C.Brush.Color := PixToColor(Theme.Screen1);
    Sz := C.TextExtent(Cap);
    C.TextOut(Round(CX - Sz.cx / 2), Round(CY - Sz.cy - 14 * FUIScale), Cap);
    C.Brush.Style := bsClear;
  end;
  C.Pen.Width := 1;
end;

{ The ends recoiling after the break: brief, and the only sign the release
  was a break and not a misclick. }
procedure TMainForm.PaintSnapRecoil(C: TCanvas);
var
  I: Integer;
  T, DX, DY, L, Ang, R: Double;
begin
  if FSnapT <= 0 then Exit;
  T := 1 - FSnapT / SNAP_RECOIL;          // 0 at the break, 1 at the end
  C.Pen.Style := psSolid;
  { Only a line has two ends to recoil; rectangles and circles get just the
    burst, or a stray strand flashes across the shape. }
  if FSnapEnds then
  begin
    DX := FSnapB.X - FSnapA.X;
    DY := FSnapB.Y - FSnapA.Y;
    L := Sqrt(DX * DX + DY * DY);
    if L >= 2 then
    begin
      DX := DX / L;
      DY := DY / L;
      C.Pen.Width := Max(1, Round(2 * FUIScale * (1 - T)));
      C.Pen.Color := PixToColor(MixPix(AnnotColor, Theme.Screen1, T));
      L := L * 0.30 * (1 - T);
      C.MoveTo(Round(FSnapA.X), Round(FSnapA.Y));
      C.LineTo(Round(FSnapA.X + DX * L), Round(FSnapA.Y + DY * L));
      C.MoveTo(Round(FSnapB.X), Round(FSnapB.Y));
      C.LineTo(Round(FSnapB.X - DX * L), Round(FSnapB.Y - DY * L));
    end;
  end;
  C.Pen.Width := Max(1, Round(2 * FUIScale * (1 - T)));
  { the burst where it broke, thrown outward and fading }
  C.Pen.Color := PixToColor(MixPix(Pix(230, 38, 28), Theme.Screen1, T));
  for I := 0 to 5 do
  begin
    Ang := I * Pi / 3 + 0.4;
    R := (10 + 26 * T) * FUIScale;
    C.MoveTo(Round(FSnapM.X + Cos(Ang) * R * 0.5),
             Round(FSnapM.Y + Sin(Ang) * R * 0.5));
    C.LineTo(Round(FSnapM.X + Cos(Ang) * R), Round(FSnapM.Y + Sin(Ang) * R));
  end;
  C.Pen.Width := 1;
end;

{ The points worth aiming at on the face under the cursor: corners, edge
  middles and the face middle (circles are often struck from a panel's
  center).  Small and pale: an offer, not a confirmation. }
procedure TMainForm.PaintFacePoints(C: TCanvas; Face: Integer);
var
  Pts: TPointFArray;
  I, J, N, R: Integer;
  CX, CY: Double;

  procedure Dot(X, Y: Double; Big: Boolean);
  var
    D: Integer;
  begin
    if Big then D := R + 1 else D := R;
    if (X < -20) or (Y < -20) or
       (X > pbScreen.Width + 20) or (Y > pbScreen.Height + 20) then Exit;
    C.Ellipse(Round(X) - D, Round(Y) - D, Round(X) + D + 1, Round(Y) + D + 1);
  end;

begin
  if Face < 0 then Exit;
  Pts := FD.Doc.Outline(Proj, Face);
  N := Length(Pts);
  if N < 3 then Exit;
  { a pulled circle has many sides; dots on all of them would be noise }
  if N > 16 then Exit;

  R := Max(2, Round(2.5 * FUIScale));
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.Pen.Color := PixToColor(Pix(90, 120, 160));
  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(Pix(210, 228, 245));

  CX := 0; CY := 0;
  for I := 0 to N - 1 do
  begin
    J := (I + 1) mod N;
    Dot(Pts[I].X, Pts[I].Y, False);                              // corner
    Dot((Pts[I].X + Pts[J].X) / 2, (Pts[I].Y + Pts[J].Y) / 2, False);  // middle
    CX := CX + Pts[I].X;
    CY := CY + Pts[I].Y;
  end;
  { the face middle, a size up so it reads as the special one }
  C.Brush.Color := PixToColor(Pix(255, 246, 210));
  Dot(CX / N, CY / N, True);

  C.Brush.Style := bsClear;
  C.Pen.Width := 1;
end;

{ The mark that says what the cursor found.  Painted after the cursor
  overlay, which blits a square of artwork back and would wipe it. }
procedure TMainForm.PaintSnapMarker(C: TCanvas; SX, SY: Integer);
var
  MarkPix: TPix;
  MarkD: Integer;
begin
  { One small solid diamond, as in SketchUp, colored by what was found (see
    SnapMarkPix, which the command bar shares). }
  MarkPix := SnapMarkPix;

  C.Pen.Width := 1;
  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(MarkPix);
  if FSnapKind = snGrid then
  begin
    { the grid is everywhere, so it gets a dot, not a diamond }
    C.Pen.Color := PixToColor(MarkPix);
    C.FillRect(SX - 2, SY - 2, SX + 3, SY + 3);
  end
  else if FSnapKind <> snNone then
  begin
    MarkD := Round(5 * FUIScale);
    { a thin dark rim so the diamond reads over pale artwork }
    C.Pen.Color := PixToColor(Pix(24, 24, 28));
    C.Polygon([Point(SX, SY - MarkD), Point(SX + MarkD, SY),
               Point(SX, SY + MarkD), Point(SX - MarkD, SY)]);
    { hollow for a sub-midpoint: the middle of a piece, not the whole line }
    if FSnapKind = snSubMid then
    begin
      C.Brush.Color := PixToColor(Theme.Screen1);
      C.Pen.Color := PixToColor(Theme.Screen1);
      C.Polygon([Point(SX, SY - MarkD + 2), Point(SX + MarkD - 2, SY),
                 Point(SX, SY + MarkD - 2), Point(SX - MarkD + 2, SY)]);
    end;
  end;
  C.Brush.Style := bsClear;
  C.Pen.Width := 1;
end;

{ The eraser's warning across a face: hatching in the face's own plane, in
  short pieces, each drawn only if its middle is inside the face (outside any
  hole) and not hidden per the depth buffer.  Hatching leaves the lines on
  the face readable, and depth keeps it from spilling over things in front. }
procedure TMainForm.WashFace(C: TCanvas; Face: Integer; const Col: TPix);
const
  STEP_PX = 7;      // between hatch lines
  PIECE_PX = 6;     // along each one
var
  Nm, AU, AV, O, P, Look: TP3;
  Poly: TP3Array;
  UV: array of TPointF;
  HUV: array of array of TPointF;
  I, J, H, N, Steps, Pieces: Integer;
  MinU, MaxU, MinV, MaxV, Ppx, StepW, PieceW, Diag, T0, T1, A, B: Double;
  U0, V0, DU, DV, Len: Double;
  SA, SB: TPointF;
  Ink: TArtSurface;
  Zb, Dp: Double;

  function InFace(U, V: Double): Boolean;
  var
    Q, R, W: Integer;
    Inside: Boolean;
  begin
    Inside := False;
    R := N - 1;
    for Q := 0 to N - 1 do
    begin
      if ((UV[Q].Y > V) <> (UV[R].Y > V)) and
         (U < (UV[R].X - UV[Q].X) * (V - UV[Q].Y) / (UV[R].Y - UV[Q].Y) + UV[Q].X) then
        Inside := not Inside;
      R := Q;
    end;
    if Inside then
      for W := 0 to High(HUV) do
      begin
        R := High(HUV[W]);
        for Q := 0 to High(HUV[W]) do
        begin
          if ((HUV[W][Q].Y > V) <> (HUV[W][R].Y > V)) and
             (U < (HUV[W][R].X - HUV[W][Q].X) * (V - HUV[W][Q].Y) /
                  (HUV[W][R].Y - HUV[W][Q].Y) + HUV[W][Q].X) then
            Inside := not Inside;
          R := Q;
        end;
      end;
    Result := Inside;
  end;

  function Seen(const W: TP3): Boolean;
  var
    SP: TPointF;
  begin
    Result := True;
    if (Ink = nil) or not Ink.DepthOn then Exit;
    SP := ScreenOf(W);
    Zb := Ink.DepthAt(Round(SP.X), Round(SP.Y));
    if Zb < -1E29 then Exit;
    Dp := Dot3(W, Look);
    Result := Zb <= Dp + 1E-3 * (1 + Abs(Dp));
  end;

begin
  if (Face < 0) or (Face >= FD.Doc.Live) or (FD.Doc[Face].Kind <> ekFace) then
    Exit;
  Poly := FD.Doc[Face].Poly;
  N := Length(Poly);
  if N < 3 then Exit;
  Ink := FInk;
  Look := ViewDir(Proj);
  Nm := Norm3(FD.Doc.FaceNormal(Face));
  AxesFromNormal(Nm, AU, AV);
  O := Poly[0];

  { the face and its windows in the plane's own coordinates }
  SetLength(UV, N);
  MinU := 1E30; MaxU := -1E30; MinV := 1E30; MaxV := -1E30;
  for I := 0 to N - 1 do
  begin
    P := Sub3(Poly[I], O);
    UV[I] := PtF(Dot3(P, AU), Dot3(P, AV));
    MinU := Min(MinU, UV[I].X); MaxU := Max(MaxU, UV[I].X);
    MinV := Min(MinV, UV[I].Y); MaxV := Max(MaxV, UV[I].Y);
  end;
  SetLength(HUV, Length(FD.Doc[Face].Holes));
  for H := 0 to High(HUV) do
  begin
    SetLength(HUV[H], Length(FD.Doc[Face].Holes[H]));
    for I := 0 to High(HUV[H]) do
    begin
      P := Sub3(FD.Doc[Face].Holes[H][I], O);
      HUV[H][I] := PtF(Dot3(P, AU), Dot3(P, AV));
    end;
  end;

  { the size of a screen pixel in the plane, so hatch density holds at any
    zoom }
  SA := ScreenOf(O);
  SB := ScreenOf(Add3(O, AU));
  Ppx := Sqrt(Sqr(SB.X - SA.X) + Sqr(SB.Y - SA.Y));
  if Ppx < 1E-6 then Exit;
  StepW := STEP_PX * FUIScale / Ppx;
  PieceW := PIECE_PX * FUIScale / Ppx;

  C.Pen.Style := psSolid;
  C.Pen.Color := PixToColor(Col);
  C.Pen.Width := 1;

  { diagonals across the bounding box, each walked in pieces }
  Diag := (MaxU - MinU) + (MaxV - MinV);
  Steps := Ceil(Diag / StepW);
  if Steps > 400 then Exit;          // a face the size of the screen at 1:1
  for I := 0 to Steps do
  begin
    { the line u + v = MinU + MinV + I*StepW, clipped to the box }
    T0 := MinU + MinV + I * StepW;
    U0 := Max(MinU, T0 - MaxV);  V0 := T0 - U0;
    T1 := Min(MaxU, T0 - MinV);
    if T1 <= U0 then Continue;
    DU := 1; DV := -1;
    Len := (T1 - U0) * Sqrt(2);
    Pieces := Max(1, Ceil(Len / PieceW));
    for J := 0 to Pieces - 1 do
    begin
      A := U0 + (T1 - U0) * J / Pieces;
      B := U0 + (T1 - U0) * (J + 1) / Pieces;
      { the middle of the piece decides for the whole piece }
      if not InFace((A + B) / 2, V0 - ((A + B) / 2 - U0)) then Continue;
      P := P3(O.X + AU.X * ((A + B) / 2) + AV.X * (V0 - ((A + B) / 2 - U0)),
              O.Y + AU.Y * ((A + B) / 2) + AV.Y * (V0 - ((A + B) / 2 - U0)),
              O.Z + AU.Z * ((A + B) / 2) + AV.Z * (V0 - ((A + B) / 2 - U0)));
      if not Seen(P) then Continue;
      SA := ScreenOf(P3(O.X + AU.X * A + AV.X * (V0 - (A - U0)),
                        O.Y + AU.Y * A + AV.Y * (V0 - (A - U0)),
                        O.Z + AU.Z * A + AV.Z * (V0 - (A - U0))));
      SB := ScreenOf(P3(O.X + AU.X * B + AV.X * (V0 - (B - U0)),
                        O.Y + AU.Y * B + AV.Y * (V0 - (B - U0)),
                        O.Z + AU.Z * B + AV.Z * (V0 - (B - U0))));
      C.MoveTo(Round(SA.X), Round(SA.Y));
      C.LineTo(Round(SB.X), Round(SB.Y));
    end;
  end;
end;

{ The held plane, drawn where you are working: two short lines along the
  plane's own directions in their axis colors (red and blue is upright, red
  and green flat).  A rubber band cannot show a plane; coloring it by the
  plane's normal would give the one color the line never runs along. }
procedure TMainForm.PaintHeldPlane(C: TCanvas);
const
  ARM = 46;
var
  AU, AV, P: TP3;
  I: Integer;
  D: TP3;
  S0, S1: TPointF;
  Sc: Double;
begin
  if not FPlaneHeld then Exit;
  if FD.Plane = plFree then Exit;
  if FD.View <> vkOrbit then Exit;   { flat views show it by being flat }
  PlaneAxes(FD.Plane, AU, AV);
  if FStage > 0 then P := FP1 else P := FCur;
  { fixed length on screen, so it is the same cue at any zoom }
  Sc := ARM * FUIScale / Max(1E-6, Ppu);
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  for I := 0 to 1 do
  begin
    if I = 0 then D := AU else D := AV;
    C.Pen.Color := PixToColor(AxisPix(AxisAlong(P3(0, 0, 0), D)));
    S0 := ScreenOf(P3(P.X - D.X * Sc, P.Y - D.Y * Sc, P.Z - D.Z * Sc));
    S1 := ScreenOf(P3(P.X + D.X * Sc, P.Y + D.Y * Sc, P.Z + D.Z * Sc));
    C.MoveTo(Round(S0.X), Round(S0.Y));
    C.LineTo(Round(S1.X), Round(S1.Y));
  end;
end;

{ The guide under the cursor in blue: a ring round a guide point, or the
  dashed line clipped to the window for a guide line. }
procedure TMainForm.PaintGuideHover(C: TCanvas; I: Integer);
var
  E: TWorkEnt;
  D: TP3;
  L: Double;
  PA, PB: TPointF;
  R: Integer;
begin
  if (I < 0) or (I >= FD.Doc.Live) or (FD.Doc[I].Kind <> ekGuide) then Exit;
  E := FD.Doc[I];
  C.Brush.Style := bsClear;
  C.Pen.Color := PixToColor(Pix(60, 120, 235));
  C.Pen.Width := Max(1, Round(FUIScale));
  if Dist(E.A, E.B) < 1E-9 then
  begin
    { a guide point: a ring the size it is drawn }
    PA := ScreenOf(E.A);
    if IsNan(PA.X) or IsNan(PA.Y) then Exit;
    R := Max(4, Round(5 * FUIScale));
    C.Pen.Style := psSolid;
    C.Ellipse(Round(PA.X) - R, Round(PA.Y) - R, Round(PA.X) + R, Round(PA.Y) + R);
    Exit;
  end;
  D := Sub3(E.B, E.A);
  L := Sqrt(Sqr(D.X) + Sqr(D.Y) + Sqr(D.Z));
  if L < 1E-9 then Exit;
  PA := ScreenOf(P3(E.A.X - D.X / L * 5000, E.A.Y - D.Y / L * 5000,
                    E.A.Z - D.Z / L * 5000));
  PB := ScreenOf(P3(E.A.X + D.X / L * 5000, E.A.Y + D.Y / L * 5000,
                    E.A.Z + D.Z / L * 5000));
  if IsNan(PA.X) or IsNan(PA.Y) or IsNan(PB.X) or IsNan(PB.Y) or
     IsInfinite(PA.X) or IsInfinite(PA.Y) or IsInfinite(PB.X) or IsInfinite(PB.Y) then Exit;
  { canvas coordinates are integers; a point 5000' away must be clamped }
  PA := PtF(EnsureRange(PA.X, -32000, 32000), EnsureRange(PA.Y, -32000, 32000));
  PB := PtF(EnsureRange(PB.X, -32000, 32000), EnsureRange(PB.Y, -32000, 32000));
  C.Pen.Style := psDash;
  C.MoveTo(Round(PA.X), Round(PA.Y));
  C.LineTo(Round(PB.X), Round(PB.Y));
  C.Pen.Style := psSolid;
end;

{ The same trace as TraceOutlineVisible, into our own surface rather than an
  LCL canvas (see EnsureSelLayer for why that matters so much). }
procedure TMainForm.TraceOutlineInto(S: TArtSurface; Idx: Integer;
  const Col: TPix; PenW: Single);
const
  N = 24;
var
  W: TP3Array;
  I, K, Run0: Integer;
  A, B: TP3;
  PA, PB: TPointF;
  Vis: Boolean;
  T0, T1: Double;

  function Edge(TVis, TCov: Double): Double;
  var
    J: Integer;
    TM: Double;
  begin
    for J := 1 to 5 do
    begin
      TM := (TVis + TCov) / 2;
      if FD.Doc.HiddenAt(Proj, Lerp3(A, B, TM)) then TCov := TM else TVis := TM;
    end;
    Result := (TVis + TCov) / 2;
  end;

begin
  if (Idx < 0) or (Idx >= FD.Doc.Live) then Exit;
  { a guide is drawn to the paper's edges, not as its stored stub, and is
    never hidden }
  if (FD.Doc[Idx].Kind = ekGuide) and
     (Dist(FD.Doc[Idx].A, FD.Doc[Idx].B) > 1E-9) then
  begin
    PA := ScreenOf(FD.Doc[Idx].A);
    PB := ScreenOf(FD.Doc[Idx].B);
    if ClipToBox(PA.X, PA.Y, PB.X - PA.X, PB.Y - PA.Y,
                 S.Width, S.Height, T0, T1) then
      S.Line(PA.X + (PB.X - PA.X) * T0, PA.Y + (PB.Y - PA.Y) * T0,
             PA.X + (PB.X - PA.X) * T1, PA.Y + (PB.Y - PA.Y) * T1,
             PenW, Col, 1.0);
    Exit;
  end;

  W := FD.Doc.OutlineWorld(Idx);
  if Length(W) < 2 then Exit;
  T0 := 0;
  for I := 0 to High(W) - 1 do
  begin
    A := W[I];
    B := W[I + 1];
    Run0 := -1;
    for K := 0 to N do
    begin
      if K < N then Vis := not FD.Doc.HiddenAt(Proj, Lerp3(A, B, (K + 0.5) / N))
      else Vis := False;
      if Vis and (Run0 < 0) then
      begin
        Run0 := K;
        if K = 0 then T0 := 0 else T0 := Edge((K + 0.5) / N, (K - 0.5) / N);
      end;
      if (not Vis) and (Run0 >= 0) then
      begin
        if K = N then T1 := 1 else T1 := Edge((K - 0.5) / N, (K + 0.5) / N);
        PA := ScreenOf(Lerp3(A, B, T0));
        PB := ScreenOf(Lerp3(A, B, T1));
        S.Line(PA.X, PA.Y, PB.X, PB.Y, PenW, Col, 1.0);
        Run0 := -1;
      end;
    end;
  end;
end;

{ An entity's outline traced heavily in one color, only where it can be
  seen: each piece is tested against faces in front, so hover and selection
  do not show through walls (as in SketchUp). }
procedure TMainForm.TraceOutlineVisible(C: TCanvas; Idx: Integer; const Col: TPix;
  PenW: Integer);
const
  N = 24;
var
  W: TP3Array;
  I, K, Run0: Integer;
  A, B: TP3;
  PA, PB: TPointF;
  Vis: Boolean;
  T0, T1: Double;

  function Edge(TVis, TCov: Double): Double;
  var
    J: Integer;
    TM: Double;
  begin
    for J := 1 to 5 do
    begin
      TM := (TVis + TCov) / 2;
      if FD.Doc.HiddenAt(Proj, Lerp3(A, B, TM)) then TCov := TM else TVis := TM;
    end;
    Result := (TVis + TCov) / 2;
  end;

begin
  { A guide is stored as a point plus a unit stub but drawn to the paper's
    edges, so trace it that way or the highlight is a one-foot stub.  No
    hidden test: guides are drawn before faces and never hidden. }
  if (FD.Doc[Idx].Kind = ekGuide) and
     (Dist(FD.Doc[Idx].A, FD.Doc[Idx].B) > 1E-9) then
  begin
    PA := ScreenOf(FD.Doc[Idx].A);
    PB := ScreenOf(FD.Doc[Idx].B);
    if ClipToBox(PA.X, PA.Y, PB.X - PA.X, PB.Y - PA.Y,
                 pbScreen.Width, pbScreen.Height, T0, T1) then
    begin
      C.Pen.Color := PixToColor(Col);
      C.Pen.Width := PenW;
      C.Pen.Style := psSolid;
      C.MoveTo(Round(PA.X + (PB.X - PA.X) * T0),
               Round(PA.Y + (PB.Y - PA.Y) * T0));
      C.LineTo(Round(PA.X + (PB.X - PA.X) * T1),
               Round(PA.Y + (PB.Y - PA.Y) * T1));
      C.Pen.Width := 1;
    end;
    Exit;
  end;

  W := FD.Doc.OutlineWorld(Idx);
  if Length(W) < 2 then Exit;
  C.Pen.Color := PixToColor(Col);
  C.Pen.Width := PenW;
  C.Pen.Style := psSolid;
  T0 := 0;
  for I := 0 to High(W) - 1 do
  begin
    A := W[I];
    B := W[I + 1];
    Run0 := -1;
    for K := 0 to N do
    begin
      if K < N then Vis := not FD.Doc.HiddenAt(Proj, Lerp3(A, B, (K + 0.5) / N))
      else Vis := False;
      if Vis and (Run0 < 0) then
      begin
        Run0 := K;
        if K = 0 then T0 := 0 else T0 := Edge((K + 0.5) / N, (K - 0.5) / N);
      end;
      if (not Vis) and (Run0 >= 0) then
      begin
        if K = N then T1 := 1 else T1 := Edge((K - 0.5) / N, (K + 0.5) / N);
        PA := ScreenOf(Lerp3(A, B, T0));
        PB := ScreenOf(Lerp3(A, B, T1));
        C.MoveTo(Round(PA.X), Round(PA.Y));
        C.LineTo(Round(PB.X), Round(PB.Y));
        Run0 := -1;
      end;
    end;
  end;
  C.Pen.Width := 1;
end;

{ a heavy trace through screen points, for highlights }
procedure TMainForm.TraceOutline(C: TCanvas; const Hi: TPointFArray;
  const Col: TPix);
var
  I: Integer;
begin
  if Length(Hi) < 2 then Exit;
  C.Pen.Color := PixToColor(Col);
  C.Pen.Width := Max(3, Round(3 * FUIScale));
  C.Pen.Style := psSolid;
  C.MoveTo(Round(Hi[0].X), Round(Hi[0].Y));
  for I := 1 to High(Hi) do
    C.LineTo(Round(Hi[I].X), Round(Hi[I].Y));
  C.Pen.Width := 1;
end;

procedure TMainForm.PaintOverlay(C: TCanvas);
var
  DA, DB: TP3;
  DNote: string;
  TX, TY, TL: Double;
  ArcFil: TFillet;
  ArcTyped: Boolean;
  ArcPl: TPlane;
  ArcC, ArcU, ArcV, ArcMid, ArcFoot: TP3;
  ArcR, ArcA0, ArcSw, ArcBulge, U1, V1, U2, V2, Ln: Double;
  PA, PB: TPointF;
  ArcK: Integer;
  HintFace: Integer;
  CircI: Integer;
  CircR: Double;
  P, PPrev: TPointF;
  SX, SY, AX, AY: Integer;
  BarLen, BarPx: Double;
  R: TRect;
  GP: TPointF;
  Hi: TPointFArray;
  RectPrev: TP3Array;
  RectI: Integer;
  S1, S2, S3, S4, HTx: string;
  W1, W2, W3, W4, BoxW, BoxH, LnH, HL, HLn: Integer;
  StrainPts: TPointFArray;
  GrpBoxes: TIntArrayW;
  GI, GrpId: Integer;

  { a small red square on a picked point, SketchUp's mark }
  procedure EndMark(const P: TP3);
  var
    Q: TPointF;
    D: Integer;
  begin
    Q := ScreenOf(P);
    D := Round(3 * FUIScale);
    C.Pen.Width := 1;
    C.Pen.Color := PixToColor(Pix(235, 70, 70));
    C.Brush.Style := bsSolid;
    C.Brush.Color := PixToColor(Pix(255, 150, 150));
    C.Rectangle(Round(Q.X) - D, Round(Q.Y) - D, Round(Q.X) + D + 1, Round(Q.Y) + D + 1);
    C.Brush.Style := bsClear;
  end;

  procedure Rubber(const A, B: TP3);
  var
    PA, PB: TPointF;
    Ax: Integer;
  begin
    PA := ScreenOf(A);
    PB := ScreenOf(B);
    { Solid and heavy: this is the shape about to be committed, not
      something provisional (SketchUp keeps it solid too). }
    C.Pen.Style := psSolid;
    C.Pen.Width := Max(3, Round(3 * FUIScale));
    { A line's color is the direction it runs (a plane's color names its
      normal, the one axis a line in it cannot run along).  Only while axis
      inference is on: the color says "holding you on red", so showing it
      with Alt's axis inference off reads as a flickering snap.  An arrow
      lock holds whatever Alt says. }
    if FAxisLock in [0..2] then Ax := FAxisLock
    else if FInferMode = imAll then Ax := AxisAlong(A, B)
    else Ax := -1;
    { parallel or perpendicular to an edge is SketchUp's magenta, which
      cannot be mistaken for an axis }
    if FParPerp > 0 then
      C.Pen.Color := PixToColor(Pix($C8, $3C, $C8))
    else if Ax >= 0 then
      C.Pen.Color := PixToColor(AxisPix(Ax))
    else
      C.Pen.Color := PixToColor(Theme.Accent);
    C.MoveTo(Round(PA.X), Round(PA.Y));
    C.LineTo(Round(PB.X), Round(PB.Y));
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
  end;

begin
  P := ScreenOf(FCur);
  SX := Round(P.X);
  SY := Round(P.Y);

  { --- live preview ---------------------------------------------------- }

  { Leaning on the button cancels whatever tool is in progress, not only a
    line run.  While straining, the strain replaces the shape's preview. }
  if FHoldOn and (FHoldT > HOLD_STRAIN) and (FStage >= 1) then
  begin
    if StrainOutline(StrainPts) then
      PaintStrainPath(C, StrainPts,
        (FHoldT - HOLD_STRAIN) / (HOLD_BREAK - HOLD_STRAIN));
    PaintSnapRecoil(C);
    Exit;
  end;

  case FTool of
    ptLine:
      begin
        PaintHeldPlane(C);
        if FStage = 1 then Rubber(FP1, PreviewTarget);
      end;
    ptRect:
      begin
        { before the first corner too, so you can see which plane you are
          about to get }
        PaintHeldPlane(C);
        if FStage = 1 then
        begin
          RectPrev := RectCorners(FP1, RectTarget, FD.Plane);
          for RectI := 0 to 3 do
            Rubber(RectPrev[RectI], RectPrev[(RectI + 1) mod 4]);
        end;
      end;
    ptOffset:
      if FStage = 1 then
      begin
        RectPrev := OffsetPreview;
        for RectI := 0 to High(RectPrev) do
          Rubber(RectPrev[RectI], RectPrev[(RectI + 1) mod Length(RectPrev)]);
      end;
    ptArc:
      begin
        { As SketchUp: both ends marked, the chord, the pull from its middle
          in its axis color (blue straight up a wall), and the arc where it
          will land, so the plane is visible before drawing. }
        if FStage = 1 then
        begin
          Rubber(FP1, FCur);
          EndMark(FP1);
        end
        else if (FStage = 2) and ArcFillet(ArcFil, ArcTyped) then
        begin
          { magenta, SketchUp's "tangent to edge", drawn where it really
            lands; the second end moves to match, so it can jump on lock }
          Rubber(ArcFil.Corner, ArcFil.S);
          Rubber(ArcFil.Corner, ArcFil.E);
          C.Pen.Style := psSolid;
          C.Pen.Width := Max(3, Round(3 * FUIScale));
          C.Pen.Color := PixToColor(Pix(225, 40, 225));
          PA := ScreenOf(ArcPoint(ArcFil.ArcC, ArcFil.R, ArcFil.A0,
            ArcFil.Pl, ArcFil.Nm));
          C.MoveTo(Round(PA.X), Round(PA.Y));
          for ArcK := 1 to FSidesArc do
          begin
            PB := ScreenOf(ArcPoint(ArcFil.ArcC, ArcFil.R,
              ArcFil.A0 + ArcFil.Sweep * ArcK / FSidesArc, ArcFil.Pl, ArcFil.Nm));
            C.LineTo(Round(PB.X), Round(PB.Y));
          end;
          C.Pen.Width := 1;
          EndMark(ArcFil.S);
          EndMark(ArcFil.E);
          { the words below right of the pointer, clear of the cursor square
            (which wipes canvas text) and the tool glyph above }
          UIFont(C, 8, True, Pix(225, 40, 225));
          C.Brush.Style := bsClear;
          C.TextOut(FMouseSX + Round(24 * FUIScale), FMouseSY + Round(10 * FUIScale),
            'TANGENT TO EDGE');
        end
        else if FStage = 2 then
        begin
          if ArcPicks(FCur, ArcPl, ArcC, ArcR, ArcA0, ArcSw, ArcBulge) then
          begin
            PlaneAxes(ArcPl, ArcU, ArcV);
            PlaneCoords(ArcPl, FP1, U1, V1);
            PlaneCoords(ArcPl, FP2, U2, V2);
            Ln := Sqrt(Sqr(U2 - U1) + Sqr(V2 - V1));
            { the chord, thin }
            PA := ScreenOf(FP1);
            PB := ScreenOf(FP2);
            C.Pen.Style := psDash;
            C.Pen.Width := 1;
            C.Pen.Color := PixToColor(Theme.Accent);
            C.MoveTo(Round(PA.X), Round(PA.Y));
            C.LineTo(Round(PB.X), Round(PB.Y));
            C.Pen.Style := psSolid;
            { the pull from the chord's middle, in its axis color }
            ArcMid := P3((FP1.X + FP2.X) / 2, (FP1.Y + FP2.Y) / 2, (FP1.Z + FP2.Z) / 2);
            ArcFoot := P3(
              ArcMid.X + (ArcU.X * (-(V2 - V1) / Ln) + ArcV.X * ((U2 - U1) / Ln)) * ArcBulge,
              ArcMid.Y + (ArcU.Y * (-(V2 - V1) / Ln) + ArcV.Y * ((U2 - U1) / Ln)) * ArcBulge,
              ArcMid.Z + (ArcU.Z * (-(V2 - V1) / Ln) + ArcV.Z * ((U2 - U1) / Ln)) * ArcBulge);
            Rubber(ArcMid, ArcFoot);
            { the arc where it will land }
            C.Pen.Width := Max(2, Round(2 * FUIScale));
            C.Pen.Color := PixToColor(Theme.Accent);
            PA := ScreenOf(ArcPoint(ArcC, ArcR, ArcA0, ArcPl));
            C.MoveTo(Round(PA.X), Round(PA.Y));
            for ArcK := 1 to FSidesArc do
            begin
              PB := ScreenOf(ArcPoint(ArcC, ArcR, ArcA0 + ArcSw * ArcK / FSidesArc, ArcPl));
              C.LineTo(Round(PB.X), Round(PB.Y));
            end;
            C.Pen.Width := 1;
          end
          else
            Rubber(FP1, FP2);
          EndMark(FP1);
          EndMark(FP2);
        end;
      end;
    ptCircle:
      begin
        PaintHeldPlane(C);
      if FStage = 1 then
      begin
        { Drawn in the plane it will land in, not a round ring on the glass,
          so a plane change shows.  A circle runs every direction, so it is
          the one shape colored by its plane's normal. }
        C.Pen.Style := psSolid;
        C.Pen.Color := PixToColor(PlanePix(FD.Plane));
        C.Pen.Width := Max(3, Round(3 * FUIScale));
        C.Brush.Style := bsClear;
        CircR := Dist(FP1, FCur);
        if CircR > 1E-9 then
        begin
          PPrev := ScreenOf(ArcPoint(FP1, CircR, 0, FD.Plane));
          for CircI := 1 to FSidesCircle do
          begin
            P := ScreenOf(ArcPoint(FP1, CircR, CircI * 2 * Pi / FSidesCircle, FD.Plane));
            C.MoveTo(Round(PPrev.X), Round(PPrev.Y));
            C.LineTo(Round(P.X), Round(P.Y));
            PPrev := P;
          end;
        end;
        C.Pen.Width := 1;
      end;
      end;
    ptMeasure:
      if FStage = 1 then
      begin
        Rubber(FP1, FCur);
        { the whole reading follows the cursor, angles and all, so a run can be
          checked for level without letting go }
        FCmdMsg := RunReading(FP1, FCur);
        { the running length beside the cursor, readable while dragging }
        S1 := FormatLen(Dist(FP1, FCur), FD.Units);
        UIFont(C, 11, True, AnnotColor);
        C.Brush.Style := bsSolid;
        C.Brush.Color := PixToColor(Theme.Screen1);
        C.TextOut(SX + Round(22 * FUIScale), SY - Round(30 * FUIScale), S1);
        C.Brush.Style := bsClear;
      end;
    ptDim:
      if FStage = 1 then
      begin
        Rubber(FP1, FCur);
        PaintDimEnds(C, FP1, FCur);
        if Dist(FP1, FCur) > 1E-9 then
        begin
          PA := ScreenOf(FP1);
          PB := ScreenOf(FCur);
          PaintDimTag(C, (PA.X + PB.X) / 2, (PA.Y + PB.Y) / 2 - 16 * FUIScale,
            FormatLen(Dist(FP1, FCur), FD.Units));
        end;
      end
      else if FStage = 2 then PaintDimPreview(C);

    ptPush, ptDrill:
      if FStage = 1 then
      begin
        PaintFaceHint(C, FPushFace, HINT_BLUE);
        PaintPushPreview(C);
      end
      else
        PaintFaceHint(C, FHoverFace, HINT_BLUE);
    ptFollow:
      if FStage = 0 then PaintFaceHint(C, FHoverFace, HINT_BLUE)
      else
      begin
        PaintFaceHint(C, FFollowFace, HINT_BLUE);
        if FStage = 2 then PaintRevolvePreview(C);
      end;
    ptMove:
      if FDimMove >= 0 then PaintDimPreview(C) else PaintMoveGhost(C);
    ptRotate, ptProtractor: PaintRotateGhost(C);
    ptSelect, ptText, ptErase, ptOrbit: ;   // nothing to rubber-band
  end;

  PaintSnapRecoil(C);

  { The face a new shape is about to land on, washed with its points marked.
    Only before the first click; after that the plane is settled. }
  if (FStage = 0) and (FTool in [ptLine, ptRect, ptCircle, ptArc]) and
     not FPlaneHeld then
  begin
    { Hit-tested here, not taken from the motion handler's cache, which is a
      tick behind and cleared by unrelated things.  It is cheap at paint time. }
    HintFace := InContextFace(FD.Doc.HitFace(Proj, FMouseSX, FMouseSY));
    if HintFace >= 0 then
    begin
      PaintFaceHint(C, HintFace, HINT_BLUE);
      PaintFacePoints(C, HintFace);
    end;
  end;

  { --- scale bar, bottom left ------------------------------------------ }
  BarLen := NiceBarLength(Ppu, 70 * FUIScale, 190 * FUIScale, FD.Units);
  BarPx := BarLen * Ppu;
  AX := Round(20 * FUIScale);
  AY := pbScreen.Height - Round(24 * FUIScale);
  C.Pen.Color := PixToColor(AnnotColor);
  C.Pen.Width := 2;
  C.MoveTo(AX, AY);
  C.LineTo(AX + Round(BarPx), AY);
  C.MoveTo(AX, AY - Round(5 * FUIScale));
  C.LineTo(AX, AY + Round(5 * FUIScale));
  C.MoveTo(AX + Round(BarPx), AY - Round(5 * FUIScale));
  C.LineTo(AX + Round(BarPx), AY + Round(5 * FUIScale));
  UIFont(C, 10, True, AnnotColor);
  C.TextOut(AX, AY - Round(20 * FUIScale), FormatLen(BarLen, FD.Units));
  S1 := CurScale.Name + IfThen(FD.Units = usImperial, ' = 1''-0"', '');
  C.TextOut(AX + Round(BarPx) + Round(12 * FUIScale), AY - Round(20 * FUIScale),
    Format('%s   (view %s)', [S1, ZoomReading]));

  { --- where a solid is not closed ------------------------------------- }
  { Over everything in warning red, to show where a solid is open (the export
    already says whether).  Dropped the moment the drawing changes. }
  if (Length(FOpenEdges) >= 2) and (FOpenSeq = FEditSeq) then
  begin
    C.Pen.Width := Max(3, Round(3 * FUIScale));
    C.Pen.Color := PixToColor(Pix(235, 60, 60));
    AY := 0;
    while AY + 1 <= High(FOpenEdges) do
    begin
      PA := ScreenOf(FOpenEdges[AY]);
      PB := ScreenOf(FOpenEdges[AY + 1]);
      C.MoveTo(Round(PA.X), Round(PA.Y));
      C.LineTo(Round(PB.X), Round(PB.Y));
      Inc(AY, 2);
    end;
    C.Pen.Width := 1;
  end;

  { --- what is selected ------------------------------------------------ }
  { (the selection is already on screen: pbScreenPaint composited the layer
    EnsureSelLayer drew) }
  { The edge the dimension tool would take.  An arc is lit by its outline,
    anything else as the segment itself (lighting a face outline's entity
    would light the whole face).  It also shows what it will give: radius,
    diameter, or ends and length. }
  if (FTool = ptDim) and (FStage = 0) and (FHoverEnt >= 0) then
  begin
    if FD.Doc[FHoverEnt].Kind = ekArc then
    begin
      Hi := FD.Doc.Outline(Proj, FHoverEnt);
      if Length(Hi) >= 2 then TraceOutline(C, Hi, HINT_BLUE);
      FDimArc := FHoverEnt;
      if DimRadialAt(DA, DB, DNote) then
      begin
        PaintDimEnds(C, DA, DB);
        PA := ScreenOf(FD.Doc[FHoverEnt].C);
        PaintDimTag(C, PA.X, PA.Y - 16 * FUIScale,
          StringReplace(DNote, '<>', FormatLen(Dist(DA, DB), FD.Units), []));
      end;
      FDimArc := -1;
    end
    else if FHoverEdgeOK then
    begin
      SetLength(Hi, 2);
      Hi[0] := ScreenOf(FHoverEdgeA);
      Hi[1] := ScreenOf(FHoverEdgeB);
      TraceOutline(C, Hi, HINT_BLUE);
      PaintDimEnds(C, FHoverEdgeA, FHoverEdgeB);
      { on the side of the edge away from the pointer, which sits on it }
      TX := -(Hi[1].Y - Hi[0].Y);
      TY := Hi[1].X - Hi[0].X;
      TL := Sqrt(TX * TX + TY * TY);
      if TL > 1E-6 then
      begin
        TX := TX / TL; TY := TY / TL;
        if TX * (FMouseSX - (Hi[0].X + Hi[1].X) / 2) + TY * (FMouseSY - (Hi[0].Y + Hi[1].Y) / 2) > 0 then
        begin TX := -TX; TY := -TY; end;
      end;
      PaintDimTag(C, (Hi[0].X + Hi[1].X) / 2 + TX * 18 * FUIScale,
        (Hi[0].Y + Hi[1].Y) / 2 + TY * 18 * FUIScale,
        FormatLen(Dist(FHoverEdgeA, FHoverEdgeB), FD.Units));
    end;
  end;

  { what a click would take, so a pick can be aimed before committing }
  if (FTool in [ptSelect, ptMove, ptRotate]) and (FHoverEnt >= 0) and
     not IsSelected(FHoverEnt) then
  begin
    { a guide just turns blue rather than getting a thick outline; it is
      construction and should stay quiet }
    if FD.Doc[FHoverEnt].Kind = ekGuide then
      PaintGuideHover(C, FHoverEnt)
    else if FD.Doc.TopPartIn(FHoverEnt) > 0 then
    begin
      { a group is its box: red when locked, SketchUp's cue }
      GrpId := FD.Doc.TopPartIn(FHoverEnt);
      if FD.Doc.PartLockedUp(GrpId) then
        PaintPartBox(C, GrpId, Pix(230, 80, 80), False, P3(0, 0, 0))
      else
        PaintPartBox(C, GrpId, Pix(150, 185, 245), False, P3(0, 0, 0));
    end
    else
      TraceOutlineVisible(C, FHoverEnt, Pix(150, 185, 245), Max(2, Round(2 * FUIScale)));
  end;

  { the group under the pointer in the groups panel }
  if (FGrpHotId > 0) and pbGroups.Visible and (FD.Doc.PartEnt(FGrpHotId) >= 0) and
     not GroupPutAway(FGrpHotId) then
    PaintPartBox(C, FGrpHotId, HINT_BLUE, False, P3(0, 0, 0));

  { picked groups as their boxes, and the open group as a dotted box round
    everything you are working inside }
  GrpBoxes := SelectedGroups;
  for GI := 0 to High(GrpBoxes) do
    if FD.Doc.PartLockedUp(GrpBoxes[GI]) then
      PaintPartBox(C, GrpBoxes[GI], Pix(230, 80, 80), False, P3(0, 0, 0))
    else
      PaintPartBox(C, GrpBoxes[GI], Pix(70, 130, 240), False, P3(0, 0, 0));
  if FD.Doc.Context <> 0 then
    PaintPartBox(C, FD.Doc.Context, Pix(130, 130, 140), True, P3(0, 0, 0));
  { every locked group in reach shows its crate faintly: you draw against it,
    and its corners, edge middles and centers are snap points }
  for GI := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[GI].Kind = ekPart) and (FD.Doc[GI].Part = FD.Doc.Context) and
       FD.Doc[GI].Solid and (FD.Doc.TopPartIn(GI) > 0) then
      PaintPartBox(C, FD.Doc[GI].Grp, Pix(240, 190, 190), True, P3(0, 0, 0));

  { the pick box: dashed for crossing, solid for containing, the only cue to
    which rule applies }
  if FBoxing then
  begin
    C.Brush.Style := bsClear;
    C.Pen.Color := PixToColor(Pix(70, 130, 240));
    C.Pen.Width := Max(1, Round(FUIScale));
    if FMouseSX < FBoxX then C.Pen.Style := psDash else C.Pen.Style := psSolid;
    C.Rectangle(Min(FBoxX, FMouseSX), Min(FBoxY, FMouseSY),
                Max(FBoxX, FMouseSX), Max(FBoxY, FMouseSY));
    C.Pen.Style := psSolid;
  end;

  { --- what the eraser is about to remove ------------------------------ }
  { everything gathered so far, in red, so a sweep can be seen and abandoned
    by not letting go over anything }
  for AY := 0 to High(FDoomed) do
  begin
    Hi := FD.Doc.Outline(Proj, FDoomed[AY]);
    if (Length(Hi) >= 3) and (FD.Doc[FDoomed[AY]].Kind = ekFace) then
      WashFace(C, FDoomed[AY], Pix(240, 60, 60));
    if Length(Hi) >= 2 then
    begin
      TraceOutline(C, Hi, Pix(240, 60, 60));
    end;
  end;

  if (FTool = ptErase) and (FHoverEnt >= 0) and not FErasing2 then
  begin
    Hi := FD.Doc.Outline(Proj, FHoverEnt);
    { a whole panel is a lot to lose to a click, so the face is washed too }
    if (Length(Hi) >= 3) and (FD.Doc[FHoverEnt].Kind = ekFace) then
      WashFace(C, FHoverEnt, Pix(230, 70, 70));
    if Length(Hi) >= 2 then
    begin
      TraceOutline(C, Hi, Pix(230, 70, 70));
    end
    else if Length(Hi) = 1 then
    begin
      C.Pen.Color := PixToColor(Pix(230, 70, 70));
      C.Brush.Style := bsClear;
      C.Ellipse(Round(Hi[0].X) - 7, Round(Hi[0].Y) - 7,
                Round(Hi[0].X) + 7, Round(Hi[0].Y) + 7);
    end;
  end;

  { --- parallel or square to an edge, in SketchUp's magenta ---
    Dotted guides are drawn 2 px heavy so they do not get lost, and each goes
    into FTipLines so the chip avoids it. }
  SetLength(FTipLines, 0);
  if FParPerp > 0 then
  begin
    GP := ScreenOf(FAxisFrom);
    C.Pen.Style := psDot;
    C.Pen.Color := PixToColor(Pix($C8, $3C, $C8));
    C.Pen.Width := Max(2, Round(2 * FUIScale));
    C.MoveTo(Round(GP.X), Round(GP.Y));
    C.LineTo(SX + Round((SX - GP.X) * 0.18), SY + Round((SY - GP.Y) * 0.18));
    TipAvoid(Round(GP.X), Round(GP.Y), SX + Round((SX - GP.X) * 0.18), SY + Round((SY - GP.Y) * 0.18));
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
  end;

  { --- the axis you are locked to --------------------------------------- }
  if FAxisLock in [0..2] then
  begin
    GP := ScreenOf(FAxisFrom);
    C.Pen.Style := psDot;
    C.Pen.Color := PixToColor(AxisPix(FAxisLock));
    C.Pen.Width := Max(2, Round(2 * FUIScale));
    { run past the cursor so it reads as a line you are on }
    C.MoveTo(Round(GP.X), Round(GP.Y));
    C.LineTo(SX + Round((SX - GP.X) * 0.18), SY + Round((SY - GP.Y) * 0.18));
    TipAvoid(Round(GP.X), Round(GP.Y), SX + Round((SX - GP.X) * 0.18), SY + Round((SY - GP.Y) * 0.18));
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
  end;

  { --- lined up with a point somewhere else ----------------------------- }
  if FGuide then
  begin
    GP := ScreenOf(FGuideFrom);
    C.Pen.Style := psDot;
    C.Pen.Color := PixToColor(GuideColor);
    C.Pen.Width := Max(2, Round(2 * FUIScale));
    C.MoveTo(Round(GP.X), Round(GP.Y));
    C.LineTo(SX, SY);
    TipAvoid(Round(GP.X), Round(GP.Y), SX, SY);
    C.Pen.Width := 1;
    C.Pen.Style := psSolid;
    C.Brush.Style := bsClear;
    C.Pen.Color := PixToColor(GuideColor);
    C.Rectangle(Round(GP.X) - 3, Round(GP.Y) - 3, Round(GP.X) + 4, Round(GP.Y) + 4);
  end;

  { No ring on the held reference point, as in SketchUp; only the dotted
    guide from it. }
  { --- the view cube ---------------------------------------------------- }
  PaintViewCube(C);
  PaintCompass(C);
  if FStairPick > 0 then PaintStairPick(C, SX, SY);

  { --- the action chip beside the cursor ---
    Not while the pointer is over the cube's patch: the chip would cover the
    cube. }
  if CubeZone(FMouseSX, FMouseSY) then Exit;
  if FErasing then Exit;
  S1 := SnapLabel;
  { picking stairs: the chip says so, and which point the next click is for }
  if FStairPick > 0 then
  begin
    if S1 = '' then S1 := 'FREE';
    S1 := 'STAIRS  ' + S1;
    case FStairPick of
      1: S2 := 'click the TOP - the landing''s edge, at its height';
      2: S2 := 'click the BOTTOM - where the first riser stands - or type the run';
    else S2 := 'click the SIDE - as far out as the stairs are wide - or type the width';
    end;
    S2 := S2 + '.  Esc goes back';
  end
  else if FTextPick and (SourceForm <> nil) then
  begin
    if S1 = '' then S1 := 'FREE';
    S1 := 'PICKING  ' + S1;
    S2 := 'click a point for ' + SourceForm.PickWants +
      '.  Arrows lock red, green, blue for a height; Esc stops';
  end
  else
  if FStage = 0 then
  begin
    if S1 = '' then S1 := 'FREE';
    case FTool of
      ptSelect: S2 := 'pick a tool below, or press L for a line';
      ptLine:
        { in 3D, say the one non-guessable thing: arrows lock the plane
          before you start }
        if (FD.View = vkOrbit) and (FStage = 0) and not FPlaneHeld then
          S2 := 'click to start - arrows lock a flat plane first: left upright, right side-on'
        else
          S2 := 'click to start - then type 12, 12''6 or 6-8-15';
      ptRect:   S2 := 'click a corner - then drag, or type 8x10';
      ptCircle: S2 := Format('click the center - %d sides: + - or type 24s', [FSidesCircle]);
      ptArc:    S2 := Format('click one end - %d segments: + - or type 12s', [FSidesArc]);
      ptPush:   S2 := 'click a face - then type how far, or rest on an edge';
      ptDrill:  S2 := 'click a face - it goes through whatever it crosses; type a depth to stop short';
      ptFollow: S2 := 'click the outline to spin - the half of the shape, seen edge on';
      ptErase:  S2 := 'click an edge to delete it - or hold and drag across ' +
                      'several.  Ctrl softens instead, Ctrl+Shift brings back';
      ptText:   S2 := 'space or click - the note points here';
      ptMove:   S2 := 'grab a point on what you are moving - Ctrl leaves a copy';
      ptOffset: S2 := 'click a face - then type the offset, negative goes inward';
      ptMeasure:
        { short: the line is narrow, and the full mode is said on every Ctrl }
        S2 := 'measure from here - Ctrl says what it leaves behind';
      ptDim:    S2 := 'click a corner, then another - or the body of an edge for all of it';
      ptRotate: S2 := 'click the center - nothing picked turns all that is joined; arrows pick the plane';
      ptProtractor: S2 := 'click the vertex - arrows pick the plane by color';
      ptOrbit:  S2 := 'drag to spin - Shift pans, Ctrl snaps to a view';
    else
      S2 := 'space or click - start here';
    end;
  end
  else
  begin
    if S1 = '' then S1 := 'DRAWING';
    case FTool of
      ptPush, ptDrill: S2 := 'type how far - 2, 6", 1-6 - or rest on an edge or a face';
      ptFollow:
        if FStage = 2 then
          S2 := 'the ring shows what it will sweep - red means the axis cuts the outline'
        else
          S2 := 'click the straight side that is the middle of the shape';
      ptCircle: S2 := Format('type a radius, or click - %d sides: + - or 24s', [FSidesCircle]);
      ptArc:    S2 := Format('pull the middle out, or type the bulge - %d segments: + - or 12s', [FSidesArc]);
      ptText:   S2 := 'type it, move away, then Enter - Shift+Enter for a new line';
      ptDim:
        if FDimArc >= 0 then S2 := 'move round the curve to turn it, then click'
        else S2 := 'move away to place it - it goes the way the pointer goes, flat or standing';
      ptMeasure:
        S2 := 'click the second point, or type a distance - 3, 2''6, 0-8-8';
      ptRect:   S2 := 'drag it, or type 8x10, 8/10 or 2''6x4 - a minus flips a side';
      ptMove:   S2 := 'type a length, [x,y,z] or <x,y,z> - Ctrl copies, then 3x or /3 for an array';
      ptOffset: S2 := 'type the offset - 6", 1-6 - negative goes inward';
      ptRotate, ptProtractor:
        if FStage = 1 then S2 := 'click a point to measure the angle from'
        else S2 := 'swing to the angle and click, or type it - 45, 22.5, or 8:12';
    else
      S2 := 'type a length - 12, 12''6, 6-8-15 - arrows lock an axis';
    end;
  end;

  { the keys that do something, under the two lines: the card is where the
    eye is }
  S3 := ShortKeys;
  { With the source window open, the thing under the pointer shows its line
    of text.  Only then: the text is something to look up, not to be met
    with. }
  S4 := '';
  if (SourceForm <> nil) and SourceForm.Visible and (FTool = ptSelect) then
  begin
    HL := FHoverEnt;
    if (HL < 0) and (FHoverFace >= 0) then HL := FHoverFace;
    if (HL >= 0) and SourceForm.LineOfThing(HL, HLn, HTx) then
    begin
      if Length(HTx) > 60 then HTx := Copy(HTx, 1, 57) + '...';
      S4 := Format('line %d:  %s', [HLn, HTx]);
    end;
  end;
  UIFont(C, 9, True, Theme.Text);
  LnH := C.TextHeight('Xg');
  W1 := C.TextWidth(S1);
  UIFont(C, 9, False, Theme.Text);
  W2 := C.TextWidth(S2);
  W3 := 0;
  if S3 <> '' then
  begin
    UIFont(C, 8, False, Theme.TextDim);
    W3 := C.TextWidth(S3);
  end;
  W4 := 0;
  if S4 <> '' then
  begin
    C.Font.Name := 'Courier New';
    C.Font.Pitch := fpFixed;
    UIFont(C, 8, False, Theme.Accent);
    C.Font.Name := 'Courier New';
    W4 := C.TextWidth(S4);
  end;
  BoxW := Max(Max(W1, W4), Max(W2, W3)) + Round(18 * FUIScale);
  BoxH := 2 * LnH + Round(14 * FUIScale);
  if S3 <> '' then Inc(BoxH, LnH);
  if S4 <> '' then Inc(BoxH, LnH);

  R := TipSpot(SX, SY, BoxW, BoxH);

  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(MixPix(Theme.Panel, Pix(0, 0, 0), 0.15));
  C.Pen.Color := PixToColor(Theme.Accent);
  C.Pen.Width := 1;
  C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Round(8 * FUIScale),
    Round(8 * FUIScale));

  UIFont(C, 9, True, Theme.Accent);
  C.TextOut(R.Left + Round(9 * FUIScale), R.Top + Round(5 * FUIScale), S1);
  UIFont(C, 9, False, Theme.Text);
  C.TextOut(R.Left + Round(9 * FUIScale), R.Top + Round(5 * FUIScale) + LnH, S2);
  if S3 <> '' then
  begin
    UIFont(C, 8, False, Theme.TextDim);
    C.TextOut(R.Left + Round(9 * FUIScale),
      R.Top + Round(5 * FUIScale) + 2 * LnH, S3);
  end;
  if S4 <> '' then
  begin
    UIFont(C, 8, False, Theme.Accent);
    C.Font.Name := 'Courier New';
    C.Font.Pitch := fpFixed;
    HLn := 2;
    if S3 <> '' then HLn := 3;
    C.TextOut(R.Left + Round(9 * FUIScale),
      R.Top + Round(5 * FUIScale) + HLn * LnH, S4);
  end;
end;

{ A tip beside the strip button under the pointer, drawn on the drawing
  canvas in the same card style as the cursor chip.  Two lines: what it is,
  then what it does, since a name alone does not explain Offset. }
procedure TMainForm.PaintChromeTip(C: TCanvas);
var
  W1, W2, BoxW, BoxH, LnH, X, Y: Integer;
  R: TRect;
begin
  if FChromeTip = '' then Exit;
  UIFont(C, 9, True, Theme.Text);
  LnH := C.TextHeight('Xg');
  W1 := C.TextWidth(FChromeTip);
  UIFont(C, 9, False, Theme.Text);
  W2 := C.TextWidth(FChromeTipBody);
  BoxW := Max(W1, W2) + Round(18 * FUIScale);
  BoxH := 2 * LnH + Round(14 * FUIScale);

  { against the strip it came from, level with the button, never off the
    bottom }
  X := EnsureRange(FChromeTipX, 4, Max(4, pbScreen.Width - BoxW - 4));
  Y := EnsureRange(FChromeTipY - BoxH div 2, 4,
                   Max(4, pbScreen.Height - BoxH - 4));
  R := Rect(X, Y, X + BoxW, Y + BoxH);

  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(MixPix(Theme.Panel, Pix(0, 0, 0), 0.15));
  C.Pen.Color := PixToColor(Theme.Accent);
  C.Pen.Width := 1;
  C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Round(8 * FUIScale),
    Round(8 * FUIScale));
  UIFont(C, 9, True, Theme.Accent);
  C.TextOut(R.Left + Round(9 * FUIScale), R.Top + Round(5 * FUIScale), FChromeTip);
  UIFont(C, 9, False, Theme.Text);
  C.TextOut(R.Left + Round(9 * FUIScale), R.Top + Round(5 * FUIScale) + LnH,
    FChromeTipBody);
end;

procedure TMainForm.pbScreenPaint(Sender: TObject);
var
  Shown: TArtSurface;
  HF: Integer;
  HaveSel: Boolean;
  CR, Rad, SX, SY, Arm, Gap, I: Integer;
  Contrast, Halo, CPix: TPix;
  CW, CA: Double;
  CP: TPointF;
  TPaint, TAll: QWord;
begin
  if not FBooted then Exit;
  { a paint before the tick draws the moved camera itself, so a stale view
    is never shown }
  FlushView;
  TPaint := GetTickCount64;
  try
  if FErasing then
  begin
    pbScreen.Canvas.Brush.Style := bsSolid;
    pbScreen.Canvas.Brush.Color := PixToColor(Theme.Bezel2);
    pbScreen.Canvas.FillRect(0, 0, pbScreen.Width, pbScreen.Height);
  end;

  { The picture plus the selection and the face wash, kept from the last
    paint unless one of the three changed; then a paint is just the blit. }
  HF := -1;
  if not FErasing and (FPopup = POP_NONE) then HF := HintFaceNow;
  HaveSel := (Length(FSel) > 0) and not FErasing;
  if HaveSel then EnsureSelLayer;       { may say the shot is stale }
  if FShotOK and (HaveSel = FShotHadSel) and (HF = FHintInShot) then
  begin
    if HaveSel or (FHintInShot >= 0) then Shown := FSelShot else Shown := FArt;
  end
  else if not HaveSel and (HF < 0) then
  begin
    Shown := FArt;
    FHintInShot := -1;
    FShotHadSel := False;
    FShotOK := True;
  end
  else
  begin
    { one surface for both: the selection composited over the picture, and
      the wash drawn into the same copy }
    if FSelShot = nil then FSelShot := TArtSurface.Create(FArt.Width, FArt.Height)
    else FSelShot.SetSize(FArt.Width, FArt.Height);
    if HaveSel then
      { the selection always comes from its cached layer (see
        EnsureSelLayer); drawing it on the canvas was far too slow }
      FSelShot.CompositeOver(FArt, FSelLayer, Rect(0, 0, FArt.Width, FArt.Height))
    else
      FSelShot.CopyRegion(FArt, 0, 0, 0, 0, FArt.Width, FArt.Height);
    if HF >= 0 then PaintFaceHint(nil, HF, HINT_BLUE, FSelShot, 0, 0);
    FHintInShot := HF;
    FShotHadSel := HaveSel;
    FShotOK := True;
    Shown := FSelShot;
  end;
  { The face wash is drawn into the picture in memory, not dot by dot on the
    canvas (a platform call per dot was tens of ms a frame zoomed in). }
  Shown.DrawTo(pbScreen.Canvas, FJitterX, FJitterY);
  if FErasing then Exit;

  CP := ScreenOf(FCur);
  { clamp a cursor that projects somewhere absurd (orbit nearly along an
    axis), or Round wraps and the overlay reads from a wild position }
  if IsNan(CP.X) or IsNan(CP.Y) or IsInfinite(CP.X) or IsInfinite(CP.Y) then
    CP := PtF(FMouseSX, FMouseSY);
  SX := EnsureRange(Round(EnsureRange(CP.X, -1E6, 1E6)),
    -20000, pbScreen.Width + 20000);
  SY := EnsureRange(Round(EnsureRange(CP.Y, -1E6, 1E6)),
    -20000, pbScreen.Height + 20000);
  PaintOverlay(pbScreen.Canvas);

  { While a list is open the drawing's cursor is not drawn: it tracks a
    point the mouse is no longer choosing and reads as a second cursor. }
  if FPopup <> POP_NONE then
  begin
    PaintPopup(pbScreen.Canvas);
    { and what belongs on top of everything, like the shutter countdown }
    PaintShotOverlay(pbScreen.Canvas);
    Exit;
  end;

  { The pen cursor is composited through a scratch surface so it can be
    antialiased on top of the artwork. }
  Rad := Round(9 * FUIScale);
  CR := Rad + Round(8 * FUIScale);
  FOverlay.SetSize(CR * 2, CR * 2);
  { from the picture actually shown, so selection and wash are in the square }
  FOverlay.CopyRegion(Shown, SX - CR, SY - CR, 0, 0, CR * 2, CR * 2);
  { That square lacks the tool preview, so blitting it wipes any preview
    near the pointer.  A fillet sits right under the pointer when it locks,
    so it is drawn into the square first. }
  PaintUnderCursor(FOverlay, SX - CR, SY - CR);

  Contrast := Pix(20, 20, 24);
  FOverlay.BlendMode := bmNormal;

  { A fine target, not a ring: four short arms with a gap and a center dot
    cover almost nothing of what you aim at.  The dark pass under it keeps
    it readable over pale artwork. }
  Arm := Round(7 * FUIScale);
  Gap := Round(2 * FUIScale);
  Halo := MixPix(Contrast, Pix(128, 128, 128), 0.9);
  for I := 0 to 1 do
  begin
    if I = 0 then begin CW := 2.6; CA := 0.30; CPix := Halo; end
    else begin CW := 1.2; CA := 0.95; CPix := Contrast; end;
    FOverlay.Line(CR - Arm, CR, CR - Gap, CR, CW, CPix, CA);
    FOverlay.Line(CR + Gap, CR, CR + Arm, CR, CW, CPix, CA);
    FOverlay.Line(CR, CR - Arm, CR, CR - Gap, CW, CPix, CA);
    FOverlay.Line(CR, CR + Gap, CR, CR + Arm, CW, CPix, CA);
  end;
  FOverlay.Disc(CR, CR, 1.1, Contrast, 0.95);

  FOverlay.DrawTo(pbScreen.Canvas, SX - CR, SY - CR);

  PaintSnapMarker(pbScreen.Canvas, SX, SY);

  { the tool's glyph rides beside the cursor }
  if (FTool <> ptSelect) then
    PaintToolGlyph(pbScreen.Canvas, SX + CR - Round(2 * FUIScale),
      SY - CR - Round(2 * FUIScale));

  PaintPopup(pbScreen.Canvas);
  { over the drawing, under nothing: a tip must be readable over anything }
  PaintChromeTip(pbScreen.Canvas);
  PaintShotOverlay(pbScreen.Canvas);
  finally
    NoteFrame(GetTickCount64 - TPaint);
  end;
end;

{ The frame watchdog.  Paper, ink, composite and screen time are summed
  since the last paint, so a frame rendered three times before showing counts
  all three.  Over 40 ms (where a drag stops feeling attached) logs a line,
  at most one every two seconds; the count and worst case go in reports. }
procedure TMainForm.NoteFrame(PaintMs: QWord);
const
  SLOW_MS = 40;
var
  Total, Now64: QWord;
begin
  Total := FMsPaper + FMsRender + FMsComp + PaintMs;
  if Total >= SLOW_MS then
  begin
    Inc(FSlowN);
    if Total > FSlowWorst then FSlowWorst := Total;
    FSlowLast := Format('%dms (paper %d, ink %d, over %d, screen %d) ' +
      '%s stage=%d sel=%d things=%d zoom=%.0f%%%s',
      [Total, FMsPaper, FMsRender, FMsComp, PaintMs,
       TOOL_NAMES[FTool], FStage, Length(FSel), FD.Doc.Live, FD.Zoom * 100,
       IfThen(FCameraMoving, ' moving', '')]);
    { and to the terminal with /timings on }
    if FTimings then
    begin
      TimingLine('slow frame: ' + FSlowLast);
    end;
    Now64 := GetTickCount64;
    if Now64 - FSlowSaid >= 2000 then
    begin
      FSlowSaid := Now64;
      Trail('slow frame: ' + FSlowLast);
    end;
  end;
  FMsPaper := 0;
  FMsRender := 0;
  FMsComp := 0;
end;

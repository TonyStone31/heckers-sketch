{ hsMainForm - the mouse on the screen.  Part of TMainForm; included by hsMainForm.pas }

{ ======================================================================== }
{ mouse on the screen                                                       }
{ ======================================================================== }

procedure TMainForm.pbScreenMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  I, Which: Integer;
begin
  if FBusy then Exit;
  { a press supersedes motion not yet serviced }
  FMoveX := X;
  FMoveY := Y;
  FMovePending := False;
  FMoveShift := Shift;

  { The cube is drawn over the drawing, so it takes presses first, every
    button: a right or middle press aimed at the cube must not reach the
    model. }
  if CubeMouse(X, Y, Button = mbLeft, False) or CubeZone(X, Y) then
  begin
    pbScreen.Invalidate;
    Exit;
  end;

  { The stair pick and the source window's Pick take a left press as a point
    (the snapped cursor) and nothing else happens on the sheet.  Then an
    open list takes the press before any tool (orbit claims a plain left
    press): any button dismisses it, only a left press on a row picks. }
  if (FStairPick > 0) and (Button = mbLeft) and (FD <> nil) then
  begin
    StairTakePoint(FCur);
    Exit;
  end;
  if FTextPick and (Button = mbLeft) and (SourceForm <> nil) and (FD <> nil) then
  begin
    SourceForm.TakePoint(FCur, FD.Units);
    FCmdMsg := 'Typed in: ' + Place2(FCur, FD.Units, False) + '.  Next point, or Esc.';
    pbCmd.Invalidate;
    Exit;
  end;
  if FPopup <> POP_NONE then
  begin
    Which := FPopup;
    I := -1;
    if Button = mbLeft then I := PopupItemAt(X, Y);
    { close before acting: some rows show a modal panel, and the list would
      stay painted over it }
    ClosePopup;
    if I >= 0 then PopupChoose(Which, I);
    Exit;
  end;

  { laptops without a middle button: the orbit tool makes a left drag orbit }
  if (Button = mbLeft) and (FTool = ptOrbit) then
  begin
    FOrbiting := FD.View = vkOrbit;
    FPanning := not FOrbiting;
    FPanRefX := X;
    FPanRefY := Y;
    FOrbitGain := OrbitGainAt(X, Y);
    FOrbitPivot := PivotAt(X, Y);
    AnchorOrbit(X, Y);
    FMoveShift := Shift;
    pbScreen.Cursor := crSizeAll;
    Exit;
  end;

  if Button in [mbMiddle, mbRight] then
  begin
    { Middle-drag orbits whatever the tool, mid-operation too, as in
      SketchUp.  From PLAN or ISO it enters the free camera first, aimed
      where you were looking. }
    if Button = mbMiddle then
    begin
      EnterFreeCamera;
      FCmdMsg := '3D view - drag to spin.  V goes back.';
    end;
    FOrbiting := (Button = mbMiddle) and (FD.View = vkOrbit);
    FPanning := not FOrbiting;
    FPanRefX := X;
    FPanRefY := Y;
    FRightSX := X;
    FRightSY := Y;
    FOrbitGain := OrbitGainAt(X, Y);
    FOrbitPivot := PivotAt(X, Y);
    AnchorOrbit(X, Y);
    FMoveShift := Shift;
    pbScreen.Cursor := crSizeAll;
    Exit;
  end;
  if Button <> mbLeft then Exit;

  { (an open list was handled above) }
  FMouseSX := X;
  FMouseSY := Y;
  { waiting for the piece to lay out: that click and no other }
  if FUnfoldPick then
  begin
    UnfoldAt(X, Y);
    Exit;
  end;
  { the eraser gathers while held and deletes on release }
  if FTool = ptErase then
  begin
    FErasing2 := True;
    FEraseMode := EraseModeOf(Shift);
    SetLength(FDoomed, 0);
    DoomAt(X, Y);
    FScreenDirty := True;
    Exit;
  end;
  { Ctrl at the press decides a copy for move and rotate }
  if ((FTool = ptMove) and (FStage = 1)) or ((FTool = ptRotate) and (FStage = 2)) then
    FMoveCopy := ssCtrl in Shift;

  if (GetTickCount64 - FClickT < 450) and (Abs(X - FClickX) < 5) and
     (Abs(Y - FClickY) < 5) then
    Inc(FClickN)
  else
    FClickN := 1;
  FClickT := GetTickCount64;
  FClickX := X;
  FClickY := Y;

  if FTool = ptSelect then
  begin
    { a press on a note's box drags the note (its leader target stays put),
      rather than starting a box select }
    FNoteDrag := FD.Doc.HitNote(X, Y);
    if FNoteDrag >= 0 then
    begin
      { the undo step waits for the first real move, so a click leaves
        nothing to undo }
      FNoteMoved := False;
      FNoteFrom := FD.Doc[FNoteDrag].A;
      FNoteGrab := WorldAt(X, Y);
      FCmdMsg := 'Moving the note.  Let go to drop it.';
      pbCmd.Invalidate;
      Exit;
    end;
    FBoxing := True;
    FBoxX := X;
    FBoxY := Y;
    FScreenDirty := True;
    Exit;
  end;
  FCur := ResolveSnapAt(X, Y);
  Trail(Format('press %s stage=%d at %d,%d  world %s,%s,%s  snap=%d',
    [TOOL_NAMES[FTool], FStage, X, Y,
     FormatLen(FCur.X, FD.Units), FormatLen(FCur.Y, FD.Units),
     FormatLen(FCur.Z, FD.Units), Ord(FSnapKind)]));
  Act(Format('press %.6f %.6f %.6f', [FCur.X, FCur.Y, FCur.Z], DotFS));
  { For a line run, and for push/pull, drill and offset, the press does
    not decide: it may be a click, or a hold that strains and cancels.
    Known when the button comes up or the hold breaks. }
  if (FTool in [ptLine, ptRect, ptCircle, ptArc, ptPush, ptDrill,
                ptOffset]) and (FStage >= 1) then
  begin
    FHoldOn := True;
    FHoldT := 0;
    FHoldX := X;
    FHoldY := Y;
    Exit;
  end;
  ToolClick;
end;

{ Note something in the trail ring, for crash reports. }
procedure TMainForm.Trail(const S: string);
begin
  FTrail[FTrailN mod Length(FTrail)] :=
    FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + S;
  Inc(FTrailN);
end;

{ Raw numbers, not feet and inches: this is parsed back, and rounding would
  replay somewhere slightly different. }
procedure TMainForm.Act(const S: string);
begin
  FActs[FActsN mod Length(FActs)] := S;
  Inc(FActsN);
end;

function TMainForm.ActsText: string;
var
  I, First, N: Integer;
begin
  Result := '';
  N := FActsN;
  if N > Length(FActs) then N := Length(FActs);
  First := FActsN - N;
  for I := First to FActsN - 1 do
    Result := Result + '  ' + FActs[I mod Length(FActs)] + LineEnding;
end;

{ Replay a session from a bug report.  The whole report is taken, not a
  trimmed fragment; the section is found by its heading and read to the end
  of the indented block. }
procedure TMainForm.DoReplayFile(const FileName: string);
const
  MARK = 'to replay';
var
  L, Body: TStringList;
  I: Integer;
  Fn: string;
  Inside: Boolean;
begin
  Fn := Trim(FileName);
  if Fn = '' then Fn := 'replay.txt';
  if not FileExists(Fn) then Fn := ExtractFilePath(ParamStr(0)) + Fn;
  if not FileExists(Fn) then
  begin
    FCmdMsg := 'No such file: ' + Trim(FileName) +
      '  - /replay <a report .txt, or a file of session lines>';
    pbCmd.Invalidate;
    Exit;
  end;

  L := TStringList.Create;
  Body := TStringList.Create;
  try
    try
      L.LoadFromFile(Fn);
    except
      on E: Exception do
      begin
        FCmdMsg := 'Could not read it: ' + E.Message;
        pbCmd.Invalidate;
        Exit;
      end;
    end;

    Inside := False;
    for I := 0 to L.Count - 1 do
    begin
      if not Inside then
      begin
        if Pos(MARK, LowerCase(L[I])) > 0 then Inside := True;
        Continue;
      end;
      { the block runs while lines stay indented; the next heading ends it }
      if (Trim(L[I]) <> '') and (Copy(L[I], 1, 1) <> ' ') then Break;
      if Trim(L[I]) <> '' then Body.Add(Trim(L[I]));
    end;

    { a bare file of session lines works too }
    if Body.Count = 0 then
      for I := 0 to L.Count - 1 do
        if Trim(L[I]) <> '' then Body.Add(Trim(L[I]));

    if Body.Count = 0 then
      FCmdMsg := 'Nothing in there that looks like a session.'
    else
      FCmdMsg := Format('replayed %d of %d', [ReplayActs(Body.Text), Body.Count]);
  finally
    Body.Free;
    L.Free;
  end;
  pbCmd.Invalidate;
end;

{ Play a recorded session back by handing the same world points to the
  entry points the mouse feeds, so nothing depends on window size.  Stops
  at the first line it does not understand; a replay that silently diverges
  is worse than one that stops. }
function TMainForm.ReplayActs(const Script: string): Integer;
var
  L: TStringList;
  P: TStringList;
  I: Integer;
  Cmd, Rest: string;
  T: TTool;
  Fired: Boolean;
  SP: TPointF;

  function Num(K: Integer): Double;
  begin
    if not TryStrToFloat(P[K], Result, DotFS) then Result := 0;
  end;

begin
  Result := 0;
  L := TStringList.Create;
  P := TStringList.Create;
  try
    L.Text := Script;
    P.Delimiter := ' ';
    P.StrictDelimiter := True;

    for I := 0 to L.Count - 1 do
    begin
      P.DelimitedText := Trim(L[I]);
      if P.Count = 0 then Continue;
      Cmd := LowerCase(P[0]);
      Rest := Trim(Copy(Trim(L[I]), Length(P[0]) + 1, MaxInt));
      Fired := True;

      if (Cmd = 'press') and (P.Count >= 4) then
      begin
        FCur := P3(Num(1), Num(2), Num(3));
        { and where that lands on screen, for the tools that ask what is under
          the pointer (revolve, push/pull, the eraser) }
        SP := ScreenOf(FCur);
        FMouseSX := Round(SP.X);
        FMouseSY := Round(SP.Y);
        FSnapKind := snGrid;
        { and which face: the one holding the point, found in the model, not
          under the pixel, where another window size finds a different face }
        FReplayFace := FD.Doc.FaceHolding(FCur);
        try
          ToolClick;
        finally
          FReplayFace := -1;
        end;
      end
      else if Cmd = 'tool' then
      begin
        Fired := False;
        for T := Low(TTool) to High(TTool) do
          if SameText(TOOL_NAMES[T], Rest) then
          begin
            SetTool(T);
            Fired := True;
            Break;
          end;
      end
      else if Cmd = 'input' then
        FInput := Rest
      else if (Cmd = 'dir') and (P.Count >= 2) then
        FDirLock := StrToIntDef(P[1], -1)
      else if Cmd = 'enter' then
        CommandEnter
      else if Cmd = 'undo' then
        DoUndo
      else if Cmd = 'redo' then
        DoRedo
      else if Cmd = 'clear' then
        StartErase
      else if Cmd = 'view' then
      begin
        if SameText(Rest, 'PLAN') then SetView(vkPlan)
        else if SameText(Rest, 'ISO') then SetView(vkIso)
        else if SameText(Rest, '3D') then SetView(vkOrbit)
        else Fired := False;
      end
      else if (Cmd = 'scale') and (P.Count >= 2) then
        SetScaleIdx(StrToIntDef(P[1], FD.ScaleIdx))
      else if (Cmd = 'snap') and (P.Count >= 2) then
        FD.SnapIdx := EnsureRange(StrToIntDef(P[1], FD.SnapIdx), 0, SNAP_COUNT - 1)
      else if (Cmd = 'units') and (P.Count >= 2) then
        SetUnits(TUnitSystem(EnsureRange(StrToIntDef(P[1], 0), 0, 1)))
      else
        Fired := False;

      if not Fired then
      begin
        FCmdMsg := Format('replay stopped at line %d: %s', [I + 1, Trim(L[I])]);
        Break;
      end;
      Inc(Result);
    end;
  finally
    P.Free;
    L.Free;
  end;

  { the replay logged its own actions; drop them so the next report does not
    carry the session twice }
  FActsN := 0;
  RenderInk;
  RecomposeAll;
  RefreshChrome;
end;

function TMainForm.TrailText: string;
var
  I, First, N: Integer;
begin
  Result := '';
  N := FTrailN;
  if N > Length(FTrail) then N := Length(FTrail);
  First := FTrailN - N;
  for I := First to FTrailN - 1 do
    Result := Result + '  ' + FTrail[I mod Length(FTrail)] + LineEnding;
end;

function TMainForm.KindCounts: string;
const
  NAMES: array[TEntKind] of string =
    ('lines', 'arcs', 'notes', 'dims', 'faces', 'guides', 'bore', 'groups');
var
  N: array[TEntKind] of Integer;
  K: TEntKind;
  I: Integer;
begin
  for K := Low(TEntKind) to High(TEntKind) do N[K] := 0;
  for I := 0 to FD.Doc.Live - 1 do
    Inc(N[FD.Doc[I].Kind]);
  Result := '';
  for K := Low(TEntKind) to High(TEntKind) do
    if N[K] > 0 then
    begin
      if Result <> '' then Result := Result + ', ';
      Result := Result + IntToStr(N[K]) + ' ' + NAMES[K];
    end;
  if Result = '' then Result := 'empty';
end;

procedure TMainForm.SaveCrashDoc(const ReportPath: string);
var
  L: TStringList;
begin
  try
    L := TStringList.Create;
    try
      BuildSession(L, False, -1, False, True);
      L.SaveToFile(ReportPath + '.hsk');
    finally
      L.Free;
    end;
  except
    { the drawing could not be written out; the report still stands }
  end;
end;

{ Every report sent is also kept beside the program, text and picture under
  the same name, so what was sent can be read back. }
procedure TMainForm.KeepReportCopy(const AName, Body: string; Shot: TStream);
var
  Dir: string;
  L: TStringList;
  F: TFileStream;
begin
  try
    Dir := AppDataDir + 'reports-sent' + PathDelim;
    if not ForceDirectories(Dir) then Exit;
    L := TStringList.Create;
    try
      L.Text := Body;
      L.SaveToFile(Dir + AName);
    finally
      L.Free;
    end;
    if (Shot <> nil) and (Shot.Size > 0) then
    begin
      F := TFileStream.Create(Dir + ChangeFileExt(AName, '.png'), fmCreate);
      try
        Shot.Position := 0;
        F.CopyFrom(Shot, Shot.Size);
      finally
        F.Free;
      end;
    end;
  except
    { a copy that could not be written is no reason to stop the report }
  end;
end;

function TMainForm.MachineText: string;
begin
  try
    Result := SystemFacts +
      'program memory: ' + ProgramMemory + LineEnding +
      Format('program: up %d s, threads=%s, quick frames=%s',
        [(GetTickCount64 - FStartedAt) div 1000, BoolToStr(FThreads, True),
         BoolToStr(FQuickFrames, True)]) + LineEnding;
  except
    on E: Exception do Result := 'machine facts failed: ' + E.ClassName + LineEnding;
  end;
end;

function TMainForm.DiagnosticText: string;
begin
  { names, not numbers, so a report reads without the source open; nothing
    about the person or the machine }
  Result :=
    Format('tool=%s stage=%d view=%s plane=%s', [TOOL_NAMES[FTool],
      FStage, VIEW_NAMES[FD.View], PlaneName]) + LineEnding +
    Format('mouse=%d,%d  cursor=%s,%s,%s  snap=%d axislock=%d held=%d',
      [FMouseSX, FMouseSY, FormatLen(FCur.X, FD.Units),
       FormatLen(FCur.Y, FD.Units), FormatLen(FCur.Z, FD.Units),
       Ord(FSnapKind), FAxisLock, Ord(FPlaneHeld)]) + LineEnding +
    Format('entities=%d (%s)  sheets=%d tab=%d  selected=%d doomed=%d',
      [FD.Doc.Live, KindCounts, Length(FDrawings), FTabIdx,
       Length(FSel), Length(FDoomed)]) + LineEnding +
    Format('pushface=%d offface=%d hoverent=%d hoverface=%d lock=%d ' +
      'holding=%d scale=%s snapstep=%s zoom=%s',
      [FPushFace, FOffFace, FHoverEnt, FHoverFace, Ord(FLockOn),
       Ord(FHoldOn), CurScale.Name, FormatLen(SnapStep, FD.Units),
       FormatFloat('0.00', FD.Zoom)]) + LineEnding +
    Format('units=%s screen=%dx%d scaling=%s portable=%s net=%s',
      [hsDrawing.UnitName(FD.Units), pbScreen.Width, pbScreen.Height,
       FormatFloat('0.00', FUIScale),
       specialize IfThen<string>(IsPortable, 'yes', 'no'),
       NetBackend]) + LineEnding +
    { where the camera stood: many view faults only reproduce at the angle }
    Format('camera az=%.2f el=%.2f zoom=%.3f at %.1f,%.1f',
      [RadToDeg(FD.Az), RadToDeg(FD.El), FD.Zoom, FD.ViewX, FD.ViewY]) +
      LineEnding +
    { the surfaces and whether they agree with each other and the window,
      for compositor crashes }
    Format('art=%dx%d/%d paper=%dx%d/%d ink=%dx%d/%d ' +
      'repairs=%d%s',
      [FArt.Width, FArt.Height, FArt.Stride,
       FPaper.Width, FPaper.Height, FPaper.Stride,
       FInk.Width, FInk.Height, FInk.Stride,
       TArtSurface.Repairs,
       { this document's borrowed depth buffer was freed at some point (an
         export's surface); harmless now, but worth a second look }
       specialize IfThen<string>(FD.Doc.LastSurfDied,
         ' borrowed-depth-was-freed', '')]) + LineEnding +
    { slow frames since start: count, worst, and the last one's breakdown;
      the individual lines are in the log below }
    IfThen(FSlowN = 0, 'frames: none over 40ms',
      Format('frames: %d over 40ms, worst %dms, last was %s',
        [FSlowN, FSlowWorst, FSlowLast])) + LineEnding +
    'what was happening, most recent last:' + LineEnding + TrailText +
    { the same session in world coordinates, to replay against the drawing
      below; recorded only from this window's own handlers }
    LineEnding + 'the same session, to replay - /replay after loading the ' +
    'drawing below:' + LineEnding + ActsText;
end;

{ Everything else about how the program was being used: startup, window and
  screen, view cube, tool settings, open sheets.  Nothing about the person:
  a file on the command line is written as <file>, never its path.  Each
  group is guarded so one bad value costs a line, not the report. }
function TMainForm.SettingsText: string;
const
  FILL_NAMES: array[0..2] of string = ('normal', 'maximized', 'full screen');
  TOUCH_NAMES: array[TTouchMode] of string =
    ('none', 'pending', 'as mouse', 'gesture', 'spent');
  CORNER_NAMES: array[0..3] of string =
    ('top left', 'top right', 'bottom left', 'bottom right');
  ERASE_NAMES: array[0..2] of string = ('delete', 'soften', 'unsoften');
  PLANE_NAMES: array[TPlane] of string = ('XY', 'XZ', 'YZ', 'free');
  TAPE_NAMES: array[0..3] of string =
    ('line and point', 'point', 'line', 'nothing');
  KIND_NAMES: array[TEntKind] of string =
    ('line', 'arc', 'note', 'dim', 'face', 'guide', 'bore', 'group');
var
  R: string;

  procedure Add(const Line: string);
  begin
    R := R + Line + LineEnding;
  end;

  function YN(B: Boolean): string;
  begin
    if B then Result := 'on' else Result := 'off';
  end;

  function Args: string;
  var
    I, Eq: Integer;
    A: string;
  begin
    Result := '';
    for I := 1 to ParamCount do
    begin
      A := ParamStr(I);
      if (A = '') or (A[1] <> '-') then
        A := '<file>'
      else
      begin
        { a switch's value is kept unless it looks like a path }
        Eq := Pos('=', A);
        if (Eq > 0) and ((Pos('/', A) > 0) or (Pos('\', A) > 0) or
           (Pos(':', Copy(A, Eq, MaxInt)) > 0)) then
          A := Copy(A, 1, Eq) + '<file>';
      end;
      Result := Result + ' ' + A;
    end;
    if Result = '' then Result := ' (none)';
  end;

  function SelKinds: string;
  var
    N: array[TEntKind] of Integer;
    K: TEntKind;
    I: Integer;
  begin
    for K := Low(TEntKind) to High(TEntKind) do N[K] := 0;
    for I := 0 to High(FSel) do
      if (FSel[I] >= 0) and (FSel[I] < FD.Doc.Live) then
        Inc(N[FD.Doc[FSel[I]].Kind]);
    Result := '';
    for K := Low(TEntKind) to High(TEntKind) do
      if N[K] > 0 then
        Result := Result + Format(' %s=%d', [KIND_NAMES[K], N[K]]);
    if Result = '' then Result := ' none';
  end;

  function Forms_: string;
  var
    I: Integer;
  begin
    Result := '';
    for I := 0 to Screen.CustomFormCount - 1 do
      if Screen.CustomForms[I].Visible then
        Result := Result + ' ' + Screen.CustomForms[I].ClassName;
    if Screen.ActiveCustomForm <> nil then
      Result := Result + '  (active ' + Screen.ActiveCustomForm.ClassName + ')';
    if Screen.ActiveControl <> nil then
      Result := Result + '  (focus ' + Screen.ActiveControl.ClassName + ')';
  end;

var
  I, J, Groups, G, Grps: Integer;
  Known: Boolean;
  D: TDrawing;
  M: TMonitor;
  Seen: array of Integer;
begin
  R := '';
  try
    Add('started with:' + Args);
    Add(Format('run tag=%s  updated from=%s  whats new shown=%s  ' +
      'draft restored=%s (age %d)  crash offered=%s  offline=%s',
      [FRunTag, specialize IfThen<string>(FUpdatedFrom = '', '-', FUpdatedFrom),
       YN(FWhatsNewShown), YN(FRestored), FDraftAge, YN(FCrashToOffer),
       YN(NetOffline)]));
    Add(Format('update seen=%s  help pages=%s%s  drawing file=%s  ' +
      'threads=%s  timings=%s',
      [specialize IfThen<string>(FUpdateTag = '', '-', FUpdateTag),
       specialize IfThen<string>(LocalHelpVersion = '', 'none', LocalHelpVersion),
       specialize IfThen<string>(HelpFetching <> nil, ' (fetching)', ''),
       specialize IfThen<string>(DocPath = '', 'never saved', 'saved as ' +
         ExtractFileExt(DocPath)),
       YN(FThreads), YN(FTimings)]));
  except
    on E: Exception do Add('start facts failed: ' + E.ClassName);
  end;

  try
    Add(Format('window: %s  %d,%d %dx%d  state=%d  client %dx%d  ' +
      'drawing area %dx%d  tools wide=%s  info panel=%s',
      [FILL_NAMES[Ord(FFill)], Left, Top, Width, Height, Ord(WindowState),
       ClientWidth, ClientHeight, pbScreen.Width, pbScreen.Height,
       YN(FToolsWide), YN(FInfoOn)]));
    M := Monitor;
    if M <> nil then
      Add(Format('on monitor %d of %d: %d,%d %dx%d at %d dpi (screen says %d)' +
        ', primary=%s',
        [M.MonitorNum + 1, Screen.MonitorCount, M.Left, M.Top, M.Width,
         M.Height, M.PixelsPerInch, Screen.PixelsPerInch, YN(M.Primary)]));
    Add('forms showing:' + Forms_);
  except
    on E: Exception do Add('window facts failed: ' + E.ClassName);
  end;

  try
    Add(Format('look: theme=%s grid=%s edge width=%d ink=%s%s ' +
      'rounded to 1/%d  circle sides=%d arc sides=%d',
      [Theme.Name, YN(FShowGrid), FEdgeW, IntToHex(ColorToRGB(FInkColor), 6),
       specialize IfThen<string>(FInkAuto, ' (auto)', ''),
       FLenDenom, FSidesCircle, FSidesArc]));
    Add(Format('view cube=%s corner=%s fit to selection=%s hot=%s ' +
      'dragging=%s  glide=%.2f  orbit snap target=%s  preset=%d',
      [YN(FCubeOn), CORNER_NAMES[FCubeCorner and 3], YN(FCubeFitSel),
       YN(FCubeHasHot), YN(FCubeDrag), FGlideT, YN(FSnapHasHot),
       FViewPreset]));
  except
    on E: Exception do Add('look facts failed: ' + E.ClassName);
  end;

  try
    Add(Format('tool options: tape leaves=%s erase=%s move copy=%s ' +
      'rigid=%s detach=%s dirlock=%d last push=%s last radius=%s ' +
      'fillet pending=%s',
      [TAPE_NAMES[Max(0, Min(3, FTapeDrop))], ERASE_NAMES[Max(0, Min(2, FEraseMode))], YN(FMoveCopy),
       YN(FMoveRigid), YN(FDetachMove), FDirLock,
       FormatLen(FLastPush, FD.Units), FormatLen(FLastFilletR, FD.Units),
       YN(FFilletPending)]));
    Add(Format('going on: typed="%s" popup=%d clicks=%d boxing=%s ' +
      'panning=%s orbiting=%s erasing=%s moving=%s busy=%s ' +
      'loading=%s dim edit=%d cut edit=%d camera moving=%s',
      [FInput, FPopup, FClickN, YN(FBoxing), YN(FPanning), YN(FOrbiting),
       YN(FErasing2), YN(FMovePending), YN(FBusy),
       YN(FLoading), FDimEdit, FSliceEdit, YN(FCameraMoving)]));
    Add(Format('bar said: "%s"', [FCmdMsg]));
    Add(Format('touch: seen=%s mode=%s down=%s points=%d',
      [YN(FTouchOn), TOUCH_NAMES[FTouchMode], YN(FTouchDown), FTouchCount]));
    Add('selected:' + SelKinds);
  except
    on E: Exception do Add('tool facts failed: ' + E.ClassName);
  end;

  try
    Add(Format('sheets open: %d', [Length(FDrawings)]));
    for I := 0 to High(FDrawings) do
    begin
      D := FDrawings[I];
      if D = nil then Continue;
      { solids, counted by their group numbers }
      Groups := 0;
      SetLength(Seen, 0);
      for G := 0 to D.Doc.Live - 1 do
      begin
        Grps := D.Doc[G].Grp;
        if Grps <= 0 then Continue;
        Known := False;
        for J := 0 to High(Seen) do
          if Seen[J] = Grps then Known := True;
        if not Known then
        begin
          SetLength(Seen, Length(Seen) + 1);
          Seen[High(Seen)] := Grps;
          Inc(Groups);
        end;
      end;
      { the name too: it is what the person sees on the tab }
      Add(Format('  sheet %d%s "%s": things=%d solids=%d open group=%d modified=%s view=%s ' +
        'plane=%s units=%s scale=%s snap=%s zoom=%.3f az=%.1f el=%.1f ' +
        'cut=%s (%s to %s) guides=%s undo=%d redo=%d',
        [I + 1, specialize IfThen<string>(I = FTabIdx, ' (showing)', ''),
         D.Name, D.Doc.Live, Groups, D.Doc.Context, YN(D.Dirty), VIEW_NAMES[D.View], PLANE_NAMES[D.Plane],
         hsDrawing.UnitName(D.Units), ScaleTable(D.Units, D.ScaleIdx).Name,
         SnapName(D.Units, D.SnapIdx), D.Zoom, RadToDeg(D.Az),
         RadToDeg(D.El), YN(D.SliceOn), FormatLen(D.SliceLo, D.Units),
         FormatLen(D.SliceHi, D.Units),
         specialize IfThen<string>(D.Doc.GuidesHidden, 'hidden', 'shown'),
         D.UndoTop, D.RedoTop]));
    end;
  except
    on E: Exception do Add('sheet facts failed: ' + E.ClassName);
  end;
  Result := R;
end;

{ Put everything down after an exception: the tool, the run in progress and
  all transient state, but not the drawing.  Leaving that state alone let
  the same code fault again on the next mouse move, forever. }
procedure TMainForm.Quiesce;
begin
  try
    FMovePending := False;
    FOrbiting := False;
    FPanning := False;
    FErasing2 := False;
    FHoldOn := False;
    FHoldT := 0;
    FPushFace := -1;
    FOffFace := -1;
    SetLength(FSel, 0);
    SetLength(FDoomed, 0);
    ResetTool;
    if pbScreen <> nil then pbScreen.Cursor := crCross;
  except
    { it is already having a bad day }
  end;
end;

procedure TMainForm.ReportCrash(Sender: TObject; E: Exception);
var
  F: TextFile;
  Path: string;
  I: Integer;
  Now64: QWord;
begin
  Quiesce;

  { The exception goes into a text file beside the executable, before any
    dialog in case the dialog fails.  More than three in half a minute is a
    state, not an incident: stop writing files and showing boxes so the user
    can get to Ctrl+S.  The count resets after a quiet half minute. }
  Now64 := GetTickCount64;
  if (FWoundCount > 0) and (Now64 - FWoundAt > 30000) then FWoundCount := 0;
  FWoundAt := Now64;
  Inc(FWoundCount);
  if FWoundCount > 3 then
  begin
    FCmdMsg := 'Still failing.  Save with Ctrl+S and restart - the reports ' +
      'are already written.';
    if pbCmd <> nil then pbCmd.Invalidate;
    Exit;
  end;

  Path := ExtractFilePath(ParamStr(0)) + CRASH_LOG;
  try
    AssignFile(F, Path);
    if FileExists(Path) then Append(F) else Rewrite(F);
    try
      WriteLn(F, '---- ', DateTimeToStr(Now), ' ', APP_NAME, ' ',
    CurrentVersion, ' built ', BUILD_STAMP);
      WriteLn(F, E.ClassName, ': ', E.Message);
      Write(F, DiagnosticText);
      Write(F, SettingsText);
      Write(F, MachineText);
      WriteLn(F, BackTraceStrFunc(ExceptAddr));
      if ExceptFrameCount > 0 then
        for I := 0 to ExceptFrameCount - 1 do
          WriteLn(F, BackTraceStrFunc(ExceptFrames[I]));
      WriteLn(F);
    finally
      CloseFile(F);
    end;
    { the drawing beside the report, under its own name, so the next crash
      does not overwrite it }
      SaveCrashDoc(Path);
    { and the drawing area as it was; whether to send it is asked at the next
      start }
    try
      FArt.SaveToPNG(Path + '.png');
    except
    end;
    { Count consecutive crashes: a second after reopening the same drawing
      implicates the drawing, a third says stop.  Cleared on a clean exit. }
    try
      with TIniFile.Create(ConfigFile) do
      try
        WriteInteger('startup', 'crashes',
          ReadInteger('startup', 'crashes', 0) + 1);
      finally
        Free;
      end;
    except
    end;
  except
    { a crash reporter that crashes helps nobody }
  end;
  { most exceptions do not end the program, so offer the report now, from
    the tick, while the user remembers what they were doing }
  if FWoundCount < 3 then FCrashToOffer := True;
  if FWoundCount >= 3 then
    MessageDlg(APP_NAME,
      'That is the third time in a minute.' + LineEnding + LineEnding +
      'Something is wrong that dismissing this will not fix.  Save what you ' +
      'have with Ctrl+S and start the program again - it will offer to send ' +
      'the reports, and they are what gets this mended.' + LineEnding +
      LineEnding +
      'It will stop interrupting you now.  Everything it has been asked to ' +
      'write is already written.',
      mtError, [mbOK], 0)
  else
    MessageDlg(APP_NAME,
      E.ClassName + ': ' + E.Message + LineEnding + LineEnding +
      'Written next to the program:' + LineEnding +
      '  ' + ExtractFileName(Path) + '   - what happened' + LineEnding +
      '  ' + ExtractFileName(Path) + '.hsk   - the drawing it happened to' +
      LineEnding + LineEnding +
      'Both together say exactly where this went wrong.  The drawing is ' +
      'your own work, so have a look before sending it anywhere.',
      mtError, [mbOK], 0);
end;

{ Motion handler: record and return.  Nothing here may paint, allocate,
  hit-test or snap.  See ServiceMotion, which the tick calls. }
procedure TMainForm.pbScreenMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if FBusy then Exit;
  FMoveX := X;
  FMoveY := Y;
  FMoveShift := Shift;
  FMovePending := True;
end;

{ The motion work, at most once per tick, from the newest pointer position.
  Intermediate positions only fed repaints that were immediately overdrawn. }
procedure TMainForm.ServiceMotion;
var
  HeldU, HeldV: TP3;
  SpeedNow: QWord;
  SpeedInst: Double;
  X, Y, HF: Integer;
  HP, HN, HoverP: TP3;
  OP: TPointF;
  NewAz, NewEl: Double;
begin
  if not FMovePending then Exit;
  FMovePending := False;
  X := FMoveX;
  Y := FMoveY;
  { the pointer's speed, for alignment nudges to wait on }
  SpeedNow := GetTickCount64;
  if (FLastMoveTick > 0) and (SpeedNow > FLastMoveTick) then
  begin
    SpeedInst := Sqrt(Sqr(X - FLastMoveX) + Sqr(Y - FLastMoveY)) * 1000 / (SpeedNow - FLastMoveTick);
    FMoveSpeed := FMoveSpeed * 0.5 + SpeedInst * 0.5;
  end
  else if SpeedNow - FLastMoveTick > 150 then
    FMoveSpeed := 0;
  FLastMoveTick := SpeedNow;
  FLastMoveX := X;
  FLastMoveY := Y;

  { The cube first (a list over it would light both), then an open list; the
    drawing underneath gets nothing.  Over the cube the crosshair becomes an
    arrow or hand, since nothing will be drawn there. }
  if CubeMouse(X, Y, False, False) or CubeZone(X, Y) then
  begin
    FMouseSX := X;
    FMouseSY := Y;
    if not FCubeCursor then
    begin
      FCubeCursor := True;
      FCursorWasCube := pbScreen.Cursor;
    end;
    { a hand on the shape, a plain arrow in the margin }
    if FCubeHasHot then pbScreen.Cursor := crHandPoint
    else pbScreen.Cursor := crDefault;
    Exit;
  end;
  if FCubeCursor then
  begin
    FCubeCursor := False;
    pbScreen.Cursor := FCursorWasCube;
  end;

  if FPopup <> POP_NONE then
  begin
    FMouseSX := X;
    FMouseSY := Y;
    HF := PopupItemAt(X, Y);
    { while the command list is being typed at, the pointer leaving it does
      not move the highlight off the row Enter will run }
    if (HF < 0) and (FPopup = POP_CMDS) then HF := FPopupHot;
    if HF <> FPopupHot then
    begin
      FPopupHot := HF;
      FScreenDirty := True;
      pbScreen.Invalidate;
    end;
    Exit;
  end;

  { a held eraser collects whatever it is dragged across }
  if FErasing2 then
  begin
    FMouseSX := X;
    FMouseSY := Y;
    DoomAt(X, Y);
    InvalidateStatus;
    Exit;
  end;

  { Middle drag orbits; Shift pans instead, checked every move so Shift can
    be pressed mid-orbit as in SketchUp. }
  if FOrbiting or FPanning then
  begin
    { where letting go with Ctrl would snap, worked out every move so the cube
      and status line can show it before you commit }
    FSnapHasHot := FOrbiting and (ssCtrl in FMoveShift) and
                   OrbitSnapTarget(FSnapHot);
    if FOrbiting and not (ssShift in FMoveShift) then
    begin
      { Drag right and the model follows the cursor round, like a turntable.
        The rate is a trackball's: fixed at the press by its distance from
        the middle (see OrbitGainAt). }
      { DO NOT fold these into FD.El := EnsureRange(FD.El + ..., -1.45, 1.45).
        FPC 3.3.1 at -O3/-O4 miscompiles that statement and stores the angle
        near address zero, faulting on every orbit.  Computing into locals
        first is the workaround. }
      NewAz := FD.Az - (X - FPanRefX) * ORBIT_RAD_PX * FOrbitGain;
      NewEl := FD.El + (Y - FPanRefY) * ORBIT_RAD_PX * FOrbitGain;
      if NewEl < -1.45 then NewEl := -1.45;
      if NewEl > 1.45 then NewEl := 1.45;
      FD.Az := NewAz;
      FD.El := NewEl;
      FViewPreset := -1;
      { Hold the grabbed point still so the view turns about it.  If the pivot
        projects to nonsense at the new angle, keep the old offset for this
        frame rather than add millions to the view position. }
      if FOrbitAnchored then
      begin
        OP := ScreenOf(FOrbitPivot);
        if (not (IsNan(OP.X) or IsNan(OP.Y) or
                 IsInfinite(OP.X) or IsInfinite(OP.Y))) and
           (Abs(OP.X) < 1E6) and (Abs(OP.Y) < 1E6) then
        begin
          FD.ViewX := FD.ViewX + (FOrbitAnchor.X - OP.X);
          FD.ViewY := FD.ViewY + (FOrbitAnchor.Y - OP.Y);
        end;
      end;
      FCameraMoving := True;
      ViewMoved;
    end
    else
      PanBy(X - FPanRefX, Y - FPanRefY);
    FPanRefX := X;
    FPanRefY := Y;
    Exit;
  end;

  FMouseSX := X;
  FMouseSY := Y;
  { Ctrl partway through a move makes it a copy; the ghost changes color }
  if ((FTool = ptMove) and (FStage = 1)) or ((FTool = ptRotate) and (FStage = 2)) then
    FMoveCopy := ssCtrl in FMoveShift;
  { In 3D a shape started in mid air begins flat every time, and the drag
    lifts it; the plane is not left over from the last shape.  Iso is left
    alone: there the plane is chosen with K or the arrows and kept. }
  ShakeWatch(X, Y);

  { carrying a note by its box }
  if FNoteDrag >= 0 then
  begin
    FMouseSX := X;
    FMouseSY := Y;
    if not FNoteMoved then
    begin
      PushUndo;
      FNoteMoved := True;
    end;
    FD.Doc.MoveNote(FNoteDrag, FNoteFrom, WorldAt(X, Y), FNoteGrab);
    RenderInk;
    RecomposeAll;
    FScreenDirty := True;
    InvalidateStatus;
    Exit;
  end;

  { a hand that has moved lets go of what it was resting on }
  if FNoLockUntilMoved and
     ((Abs(X - FHoldX) > 6) or (Abs(Y - FHoldY) > 6)) then
    FNoLockUntilMoved := False;

  if FStage = 0 then FPlaneFromFace := False;
  if (FStage = 0) and not FPlaneHeld and (FD.View = vkOrbit) then
    FD.Plane := plXY;
  if (FStage = 0) and (FTool in [ptLine, ptRect, ptCircle, ptArc]) then
    FaceTheCamera;
  { an arrow-held plane keeps its direction but still passes through a
    face under the cursor that faces the same way }
  if (FStage = 0) and FPlaneHeld and (FD.Plane <> plFree) and
     (FTool in [ptLine, ptRect, ptCircle, ptArc]) and
     FD.Doc.FaceUnder(Proj, X, Y, HF, HP) then
  begin
    HN := Norm3(FD.Doc.FaceNormal(HF));
    PlaneAxes(FD.Plane, HeldU, HeldV);
    if Abs(Abs(Dot3(Norm3(Cross3(HeldU, HeldV)), HN)) - 1) < 1E-3 then
      FCur := HP;
  end;
  if (FStage = 0) and not FPlaneHeld and
     (FTool in [ptLine, ptRect, ptCircle, ptArc]) and
     FD.Doc.FaceUnder(Proj, X, Y, HF, HP) then
  begin
    HN := FD.Doc.FaceNormal(HF);
    { A face square to an axis gets the matching flat plane (faster, and
      colored); any other face (a roof, a hopper side) gets a plane of its
      own, so shapes can be drawn on slopes. }
    if Abs(HN.Z) > 0.999 then FD.Plane := plXY
    else if Abs(HN.Y) > 0.999 then FD.Plane := plXZ
    else if Abs(HN.X) > 0.999 then FD.Plane := plYZ
    else
    begin
      SetFreePlane(HP, HN);
      FD.Plane := plFree;
    end;
    { the plane passes through where the cursor meets the face }
    FCur := HP;
    FFacePt := HP;
    FFaceNm := Norm3(HN);
    FPlaneFromFace := True;
  end;

  { In mid air with the first point down, the drag direction decides flat
    or upright (as SketchUp appears to), before the snap resolves.  A face
    under the first point or an arrow lock wins, and a drag under about a
    sixth of an inch is a twitch, not a direction. }
  if (FStage >= 1) and not FPlaneHeld and not FPlaneFromFace and
     (FD.View = vkOrbit) and
     (FTool in [ptLine, ptRect, ptCircle, ptArc]) then
  begin
    OP := ScreenOf(FP1);
    if Sqr(X - OP.X) + Sqr(Y - OP.Y) >= Sqr(14 * FUIScale) then
      FD.Plane := PlaneByDrag(Proj, FP1, X, Y, FD.Plane);
  end;

  FCur := ResolveSnapAt(X, Y);

  { a snapped point that belongs to a face adopts that face's plane too,
    or arcs end up behind the box }
  if (FStage = 0) and not FPlaneHeld and
     (FTool in [ptLine, ptRect, ptCircle, ptArc]) and
     (FSnapKind in [snEndpoint, snCross, snMidpoint, snSubMid]) then
  begin
    HF := FD.Doc.FaceThrough(FCur);
    if HF >= 0 then
    begin
      HN := FD.Doc.FaceNormal(HF);
      if Abs(HN.Z) > 0.999 then FD.Plane := plXY
      else if Abs(HN.Y) > 0.999 then FD.Plane := plXZ
      else if Abs(HN.X) > 0.999 then FD.Plane := plYZ
      else
      begin
        SetFreePlane(FCur, HN);
        FD.Plane := plFree;
      end;
      FPlaneFromFace := True;
    end;
  end;

  if FTool = ptErase then
  begin
    { the same order the click uses, so what lights is what goes; no face,
      since the click does not take faces }
    FHoverEnt := FD.Doc.HitNote(X, Y);
    { no guides: the eraser does not take them }
    if FHoverEnt < 0 then
      FHoverEnt := FD.Doc.HitEdge(Proj, X, Y, 9 * FUIScale, HIT_NO_GUIDES);
    if FHoverEnt < 0 then
      FHoverEnt := FD.Doc.HitTest(Proj, X, Y, 9 * FUIScale, False);
  end
  else if (FTool = ptSelect) and not FBoxing then
    FHoverEnt := PickAt(X, Y)
  else if (FTool = ptDim) and (FStage = 0) then
  begin
    { Hover an edge and it lights; one click then dimensions all of it, so
      an edge click can be told from a point-to-point start.  Not when the
      cursor is on a point of it: that click takes the point. }
    FHoverEdgeOK := False;
    { except the corners of a curve's straight pieces, which are everywhere
      along it; quadrants, centers and arc ends are still points }
    if (FSnapKind = snEndpoint) and (CurveThrough(FCur) >= 0) then
      FHoverEnt := CurveThrough(FCur)
    else if FSnapKind in [snEndpoint, snMidpoint, snCenter, snCross, snSubMid, snOrigin] then
      FHoverEnt := -1
    else
    begin
      { EdgeUnder, not HitEdge, so a face outline counts too }
      FHoverEdgeOK := FD.Doc.EdgeUnder(Proj, X, Y, 9 * FUIScale,
        HoverP, FHoverEdgeA, FHoverEdgeB, FHoverEnt);
      if FHoverEdgeOK and (FD.Doc[FHoverEnt].Kind = ekGuide) then
      begin
        { a guide is infinite; "all of it" means nothing }
        FHoverEdgeOK := False;
        FHoverEnt := -1;
      end;
      if not FHoverEdgeOK then FHoverEnt := -1;
    end;
  end
  else
    FHoverEnt := -1;
  { The face push/pull or offset would take, so a hit shows before the
    click.  The drawing tools want it too: which face a shape is about to
    go onto (SketchUp washes it and shows its points). }
  if (FTool in [ptPush, ptDrill, ptOffset, ptFollow]) and (FStage = 0) then
    FHoverFace := FD.Doc.HitFace(Proj, X, Y)
  else if (FTool in [ptLine, ptRect, ptCircle, ptArc]) and (FStage = 0) and
          not FPlaneHeld then
    FHoverFace := FD.Doc.HitFace(Proj, X, Y)
  else
    FHoverFace := -1;
  FScreenDirty := True;
  InvalidateStatus;
end;

{ Note where the pivot is on screen, so the orbit holds it at its own place
  on the glass, not under the cursor.  Held under the cursor, an orbit
  started over empty space dragged the whole model across to meet the
  mouse.  SketchUp keeps the canvas center fixed instead; this differs only
  when panned off center, and was kept on purpose. }
procedure TMainForm.AnchorOrbit(SX, SY: Integer);
var
  P: TPointF;
begin
  P := ScreenOf(FOrbitPivot);
  FOrbitAnchored := not (IsNan(P.X) or IsNan(P.Y) or
                         IsInfinite(P.X) or IsInfinite(P.Y)) and
                    (Abs(P.X) < 1E6) and (Abs(P.Y) < 1E6);
  if FOrbitAnchored then FOrbitAnchor := P
  else FOrbitAnchor := PtF(SX, SY);
end;

{ Orbit rate by where the press went down: slow over the middle third,
  faster toward the rim, growing with distance squared, like a trackball. }
function TMainForm.OrbitGainAt(SX, SY: Integer): Double;
var
  R, RMax, T: Double;
begin
  R := Sqrt(Sqr(SX - pbScreen.Width / 2) + Sqr(SY - pbScreen.Height / 2));
  RMax := Min(pbScreen.Width, pbScreen.Height) / 2;
  if RMax < 1 then Exit(1);
  T := Min(1, R / RMax);
  { a quarter of the rate at the middle to the plain rate at the rim }
  Result := 0.25 + 0.75 * T * T;
end;

{ A plane seen nearly edge-on turns a pixel into tens or hundreds of feet, so
  a shape is never started on one: within 5 degrees of edge-on the axis
  plane that faces the camera takes over, held or not, through the middle
  of the view rather than wherever the cursor last landed. }
procedure TMainForm.FaceTheCamera;
const
  EDGE_ON = 0.087;   { sin 5 degrees }
var
  O, U, V, N, D: TP3;
begin
  if FD.View <> vkOrbit then Exit;
  if FD.Plane = plFree then GetFreePlane(O, U, V, N)
  else
  begin
    PlaneAxes(FD.Plane, U, V);
    N := Norm3(Cross3(U, V));
  end;
  D := ViewDir(Proj);
  if Abs(Dot3(N, D)) >= EDGE_ON then Exit;
  if (Abs(D.Z) >= Abs(D.Y)) and (Abs(D.Z) >= Abs(D.X)) then FD.Plane := plXY
  else if Abs(D.Y) >= Abs(D.X) then FD.Plane := plXZ
  else FD.Plane := plYZ;
  FPlaneHeld := False;
  FCur := PivotAt(0, 0);
  FCmdMsg := 'Looking along that plane - the shape goes on the one facing you.';
end;

{ What the view turns about.  An empty sheet turns about the origin: the
  working-plane crossing can come back a billion feet away when the camera
  swings through level. }
function TMainForm.PivotAt(SX, SY: Integer): TP3;
var
  F: Integer;
  P, Lo, Hi: TP3;
  Pts: TP3Array;

  function Sane(const Q: TP3): Boolean;
  begin
    Result := not (IsNan(Q.X) or IsNan(Q.Y) or IsNan(Q.Z) or
                   IsInfinite(Q.X) or IsInfinite(Q.Y) or IsInfinite(Q.Z)) and
              (Abs(Q.X) < 1E7) and (Abs(Q.Y) < 1E7) and (Abs(Q.Z) < 1E7);
  end;

  { A point that is not absurd is not necessarily one you could grab: it
    must project near the glass.  A working plane nearly edge-on to the
    camera gives crossings millions of feet away; on an empty drawing that
    was the only candidate. }
  function Grabbable(const Q: TP3): Boolean;
  var
    S: TPointF;
  begin
    Result := False;
    if not Sane(Q) then Exit;
    S := ScreenOf(Q);
    if IsNan(S.X) or IsNan(S.Y) or IsInfinite(S.X) or IsInfinite(S.Y) then
      Exit;
    Result := (Abs(S.X) < 8 * pbScreen.Width) and
              (Abs(S.Y) < 8 * pbScreen.Height);
  end;

begin
  { About the middle of the screen, where you are looking, as SketchUp does;
    the point under the pointer felt wrong.  Order: the drawn thing under
    the middle, the nearest drawn thing to it from the depth buffer, the
    selection, the drawing's middle. }
  SX := pbScreen.Width div 2;
  SY := pbScreen.Height div 2;
  if FD.Doc.FaceUnder(Proj, SX, SY, F, P) and Grabbable(P) then
    Exit(P);
  if FD.Doc.DepthPointNear(SX, SY, 4000, P) and Grabbable(P) then
    Exit(P);
  if Length(FSel) > 0 then
  begin
    FD.Doc.VertsOf(FSel, Pts);
    if Length(Pts) > 0 then
    begin
      P := P3(0, 0, 0);
      for F := 0 to High(Pts) do P := Add3(P, Pts[F]);
      P := P3(P.X / Length(Pts), P.Y / Length(Pts), P.Z / Length(Pts));
      if Grabbable(P) then Exit(P);
    end;
  end;
  if FD.Doc.Bounds(Lo, Hi) then
  begin
    Result := P3((Lo.X + Hi.X) / 2, (Lo.Y + Hi.Y) / 2, (Lo.Z + Hi.Z) / 2);
    if Grabbable(Result) then Exit;
  end;
  Result := WorldAt(SX, SY);
  if not Grabbable(Result) then Result := P3(0, 0, 0);
end;

{ --- the settings lists ---
  Scale, snap and the pen each have a button showing their value and a list
  that opens above it, as long as it needs to be. }

function TMainForm.PopupCount(Which: Integer): Integer;
begin
  case Which of
    POP_SCALE: Result := SCALE_COUNT;
    POP_SNAP: Result := SNAP_COUNT;
    { one row past the palette, for any other color }
    POP_COLOR: Result := Length(PALETTE) + 1;
    POP_WIDTH: Result := PEN_STEPS;
    POP_HELP: Result := 7;
    POP_SHOP: Result := 5;
    POP_PREC: Result := Length(PREC_DENOMS);
    POP_MORE: Result := Length(MORE_TOOLS);
    POP_CMDS: Result := Length(CMD_LIST);
  else
    Result := 0;
  end;
end;

function TMainForm.PopupCaption(Which, I: Integer): string;
begin
  case Which of
    POP_SCALE: Result := ScaleTable(FD.Units, I).Name +
      IfThen(FD.Units = usImperial, '  =  1''-0"', '');
    POP_SNAP: Result := IfThen(I = 0, 'No snapping', SnapName(FD.Units, I));
    POP_COLOR:
      if I = Length(PALETTE) then Result := 'Another color...' else Result := '';
    POP_WIDTH: Result := Format('%d px', [PEN_SIZES[I]]);
    POP_SHOP:
      case I of
        0: Result := 'Lay a selection out flat(incomplete)';
        1: Result := 'Build a duct fitting...';
        2: Result := 'Fitter''s ISO spool scratchpad';
        3: Result := 'Radiant heat layout...';
        4: Result := 'Stair calculator...';
      else
        Result := '';
      end;
    POP_PREC:
      if PREC_DENOMS[I] = 100 then Result := 'hundredths of an inch'
      else Result := Format('1/%d"', [PREC_DENOMS[I]]);
    POP_MORE:
      if (I >= 0) and (I <= High(MORE_TOOLS)) then
        Result := TOOL_NAMES[MORE_TOOLS[I]]
      else
        Result := '';
    POP_CMDS:
      if (I >= 0) and (I < Length(FCmdOrder)) then
        Result := '/' + CMD_LIST[FCmdOrder[I]].Name
      else
        Result := '';
    POP_HELP:
      case I of
        0: Result := 'About  (F1)';
        1: Result := 'Check for updates';
        2: Result := 'What''s new';
        3: Result := 'Downloads';
        4: Result := 'The manual';
        5: Result := 'Report a problem';
      else
        Result := 'Project page';
      end;
  else
    Result := '';
  end;
end;

procedure TMainForm.PopupChoose(Which, I: Integer);
begin
  case Which of
    POP_SCALE: SetScaleIdx(I);
    POP_SNAP:
      begin
        FD.SnapIdx := EnsureRange(I, 0, SNAP_COUNT - 1);
        FCmdMsg := 'Snap: ' + SnapName(FD.Units, FD.SnapIdx);
      end;
    POP_COLOR:
      if I = Length(PALETTE) then PickAnyColor
      else SetInk(PALETTE[I], False);
    POP_WIDTH: SetEdgeWidth(PEN_SIZES[I]);
    POP_SHOP:
      case I of
        0: StartUnfold;
        1: BuildTransitionWizard;
        2: BuildSpoolWizard;
        3: BuildRadiantWizard;
        4: BuildStairWizard;
      end;
    POP_PREC: SetLenPrecision(PREC_DENOMS[EnsureRange(I, 0, High(PREC_DENOMS))]);
    POP_MORE:
      if (I >= 0) and (I <= High(MORE_TOOLS)) then SetTool(MORE_TOOLS[I]);
    POP_CMDS:
      if (I >= 0) and (I < Length(FCmdOrder)) then
      begin
        NoteCmdUsed(CMD_LIST[FCmdOrder[I]].Name);
        { one that takes an argument is typed into the box, ready; the rest
          just run }
        if CMD_LIST[FCmdOrder[I]].Arg then
        begin
          FInput := '/' + CMD_LIST[FCmdOrder[I]].Name + ' ';
          FCmdMsg := CMD_LIST[FCmdOrder[I]].Hint;
        end
        else
        begin
          FInput := '';
          RunCommand(CMD_LIST[FCmdOrder[I]].Name);
        end;
        pbCmd.Invalidate;
      end;
    POP_HELP:
      case I of
        0: ShowAbout;
        1: begin CheckForUpdate(True); DoUpdate; end;
        2: ShowWhatsNew;
        3: OpenURL('https://github.com/' + UPDATE_REPO + '/releases/latest');
        4: OpenManual;
        5: ReportBug;
      else
        OpenURL('https://github.com/' + UPDATE_REPO);
      end;
  end;
  RebuildDeck;
  pbDeck.Invalidate;
end;

{ How tall a list may get.  The command list is capped at half the window so
  the model stays visible; the rest scrolls. }
function TMainForm.PopupMaxHeight(Which: Integer): Integer;
begin
  Result := pbScreen.Height - 20;
  if Which = POP_CMDS then
    Result := Min(Result, Max(Round(180 * FUIScale), pbScreen.Height div 2));
end;

procedure TMainForm.OpenPopup(Which: Integer);
var
  N, I, W, H, RowH, LeftX, Bottom, TopY, RightMost: Integer;
  B: TRect;
begin
  N := PopupCount(Which);
  if N <= 0 then Exit;
  FPopup := Which;
  FPopupN := N;
  FPopupHot := -1;
  FPopupTop := 0;
  if Which = POP_CMDS then BuildCmdOrder;
  { an arrow over a menu: the pointer is choosing a row, not a point }
  FCursorWas := pbScreen.Cursor;
  pbScreen.Cursor := crDefault;

  { find the button it belongs to, and hang the list off it }
  LeftX := Round(20 * FUIScale);
  TopY := -1;
  { the strip first: a list from a left-hand button opens beside it }
  for I := 0 to High(FTools) do
    if (FTools[I].Group = GRP_POPUP) and (FTools[I].Value = Which) then
    begin
      B := FTools[I].Bounds;
      LeftX := Round(4 * FUIScale);
      TopY := pbTools.Top + B.Top - pbScreen.Top;
      Break;
    end;
  { the command list hangs off the arrow beside the prompt, at the foot }
  if Which = POP_CMDS then
  begin
    LeftX := Round(14 * FUIScale);
    TopY := -1;
  end
  else
  if TopY < 0 then
    for I := 0 to High(FDeck) do
      if ((FDeck[I].Group = GRP_POPUP) and (FDeck[I].Value = Which)) or
         ((Which = POP_HELP) and (FDeck[I].Group = GRP_ICON) and
          (FDeck[I].Value = ACT_HELP)) then
      begin
        B := FDeck[I].Bounds;
        LeftX := pbDeck.Left + B.Left - pbScreen.Left;
        Break;
      end;

  RowH := Round(22 * FUIScale);
  W := Round(190 * FUIScale);
  if Which = POP_COLOR then W := Round(150 * FUIScale);
  if Which = POP_HELP then W := Round(210 * FUIScale);
  { wide, because each row carries what the command does }
  if Which = POP_CMDS then W := Round(430 * FUIScale);
  H := Min(N * RowH + Round(12 * FUIScale), PopupMaxHeight(Which));
  Bottom := pbScreen.Height - Round(6 * FUIScale);
  { How far right a list may go: the deck's right edge, not the drawing's,
    or with the entity panel open the HELP list lands a panel's width from
    its button.  The part past the drawing is painted onto the panel (see
    PaintPopup and pbInfoPaint). }
  RightMost := pbScreen.Width;
  if pbInfo.Visible or pbGroups.Visible then
    RightMost := Max(RightMost,
      pbDeck.Left + pbDeck.Width - pbScreen.Left - Round(2 * FUIScale));
  LeftX := EnsureRange(LeftX, 4, Max(4, RightMost - W - 4));
  if TopY >= 0 then
  begin
    TopY := EnsureRange(TopY, 4, Max(4, pbScreen.Height - H - 4));
    FPopupR := Rect(LeftX, TopY, LeftX + W, TopY + H);
  end
  else
    FPopupR := Rect(LeftX, Max(4, Bottom - H), LeftX + W, Bottom);
  FScreenDirty := True;
  if pbInfo.Visible then pbInfo.Invalidate;
  if pbGroups.Visible then pbGroups.Invalidate;
end;

procedure TMainForm.ClosePopup;
begin
  if FPopup = POP_NONE then Exit;
  FPopup := POP_NONE;
  FPopupHot := -1;
  pbScreen.Cursor := FCursorWas;
  FScreenDirty := True;
  pbScreen.Invalidate;
  { It may have been over the panels too.  Paint them now, not later: a row
    that opens a modal window would leave the list painted there meanwhile. }
  if pbInfo.Visible then
  begin
    pbInfo.Invalidate;
    pbInfo.Update;
  end;
  if pbGroups.Visible then
  begin
    pbGroups.Invalidate;
    pbGroups.Update;
  end;
  pbScreen.Update;
end;

function TMainForm.PopupItemAt(SX, SY: Integer): Integer;
var
  RowH: Integer;
begin
  Result := -1;
  if FPopup = POP_NONE then Exit;
  if (SX < FPopupR.Left) or (SX > FPopupR.Right) or
     (SY < FPopupR.Top) or (SY > FPopupR.Bottom) then Exit;
  RowH := Round(22 * FUIScale);
  Result := (SY - FPopupR.Top - Round(6 * FUIScale)) div RowH + FPopupTop;
  if (Result < FPopupTop) or (Result >= FPopupN) then Result := -1;
end;

{ The wheel while a list is open belongs to the list, not the zoom behind
  it.  True means the wheel was ours even if nothing scrolled.  The
  highlight stays put (scrolling is looking, not choosing), except for the
  row under the pointer. }
function TMainForm.ScrollPopup(Lines, SX, SY: Integer): Boolean;
var
  RowH, Rows, Was, Hot: Integer;
begin
  Result := FPopup <> POP_NONE;
  if not Result then Exit;
  RowH := Max(1, Round(22 * FUIScale));
  Rows := Max(1, (FPopupR.Bottom - FPopupR.Top - Round(12 * FUIScale)) div RowH);
  if FPopupN <= Rows then Exit;
  Was := FPopupTop;
  FPopupTop := EnsureRange(FPopupTop + Lines, 0, FPopupN - Rows);
  if FPopupTop = Was then Exit;
  Hot := PopupItemAt(SX, SY);
  if Hot >= 0 then FPopupHot := Hot;
  FScreenDirty := True;
  pbScreen.Invalidate;
end;

{ a small badge of the current tool, through a scratch surface for
  antialiasing }
procedure TMainForm.PaintToolGlyph(C: TCanvas; AX, AY: Integer);
var
  Sz: Integer;
  Col: TPix;
begin
  Sz := Round(18 * FUIScale);
  Col := Pix(30, 30, 36);
  FGlyph.SetSize(Sz, Sz);
  FGlyph.ClearTransparent;
  PaintIcon(FGlyph, TOOL_ICONS[FTool], Rect(0, 0, Sz, Sz), Col, 0.95);
  FGlyph.DrawTo(C, AX, AY);
end;

{ A list, drawn wherever it lands.  DX, DY shift it from screen coordinates
  to the canvas being painted: zero for the screen, the offset to the
  entity panel when part of the list hangs over it (see pbInfoPaint). }
procedure TMainForm.PaintPopup(C: TCanvas; DX: Integer = 0; DY: Integer = 0);
var
  I, RowH, Y, Cur: Integer;
  R, PR: TRect;
  Sel: Boolean;
  S: string;
begin
  if FPopup = POP_NONE then Exit;
  RowH := Round(22 * FUIScale);
  PR := FPopupR;
  OffsetRect(PR, DX, DY);

  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(MixPix(Theme.Panel, Pix(0, 0, 0), 0.15));
  C.Pen.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.30));
  C.Pen.Width := Max(1, Round(FUIScale));
  C.Rectangle(PR);

  case FPopup of
    POP_SCALE: Cur := FD.ScaleIdx;
    POP_SNAP: Cur := FD.SnapIdx;
  else
    Cur := -1;
  end;

  for I := FPopupTop to FPopupN - 1 do
  begin
    Y := PR.Top + Round(6 * FUIScale) + (I - FPopupTop) * RowH;
    if Y + RowH > PR.Bottom then Break;
    R := Rect(PR.Left + Round(4 * FUIScale), Y,
      PR.Right - Round(4 * FUIScale), Y + RowH - 1);
    { the current choice is lit }
    Sel := (I = Cur) or
      ((FPopup = POP_COLOR) and (I < Length(PALETTE)) and
       (PALETTE[I] = FInkColor)) or
      ((FPopup = POP_WIDTH) and
       (PEN_SIZES[I] = FEdgeW));
    if Sel then
    begin
      C.Brush.Color := PixToColor(ShadePix(Theme.Accent, 0.95));
      C.FillRect(R);
    end
    else if I = FPopupHot then
    begin
      C.Brush.Color := PixToColor(MixPix(Theme.Panel, Pix(255, 255, 255), 0.12));
      C.FillRect(R);
    end;

    if (FPopup = POP_COLOR) and (I < Length(PALETTE)) then
    begin
      C.Brush.Color := PALETTE[I];
      if Sel then
        C.Pen.Color := PixToColor(Pix(255, 255, 255))
      else
        C.Pen.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.4));
      C.Pen.Width := IfThen(Sel, Max(2, Round(2 * FUIScale)), 1);
      C.Rectangle(R.Left + Round(6 * FUIScale), R.Top + Round(3 * FUIScale),
        R.Right - Round(6 * FUIScale), R.Bottom - Round(3 * FUIScale));
      C.Pen.Width := 1;
      C.Brush.Style := bsSolid;
      Continue;
    end;

    S := PopupCaption(FPopup, I);
    if Sel then UIFont(C, 10, True, OnPix(Theme.Accent))
    else UIFont(C, 10, False, Theme.Text);
    C.TextOut(R.Left + Round(8 * FUIScale),
      R.Top + (RowH - C.TextHeight('X')) div 2, S);

    { What it does, beside its name; on the hovered row, for commands that
      take an argument, an example instead, which is what people open the
      manual to find. }
    if (FPopup = POP_CMDS) and (I < Length(FCmdOrder)) then
    begin
      S := CMD_LIST[FCmdOrder[I]].Hint;
      { found by another of its words: say which }
      if CmdAliasFor(FCmdOrder[I], FCmdWant) <> '' then
        S := '/' + CmdAliasFor(FCmdOrder[I], FCmdWant) + ' - ' + S;
      if (I = FPopupHot) and (CMD_LIST[FCmdOrder[I]].Eg <> '') then
      begin
        S := CMD_LIST[FCmdOrder[I]].Eg;
        { in the typing face, since it is something to type }
        UIFont(C, 10, False, Theme.Accent, True);
      end
      else if Sel then UIFont(C, 10, False, OnPix(Theme.Accent))
      else UIFont(C, 10, False, Theme.TextDim);
      C.TextOut(R.Left + Round(120 * FUIScale),
        R.Top + (RowH - C.TextHeight('X')) div 2, S);
    end;
  end;

  { a scroll bar for a long list }
  if (FPopupN * RowH) > (PR.Bottom - PR.Top - Round(12 * FUIScale)) then
  begin
    I := (PR.Bottom - PR.Top - Round(12 * FUIScale)) div RowH;
    C.Brush.Style := bsSolid;
    C.Brush.Color := PixToColor(MixPix(Theme.Panel, Pix(0, 0, 0), 0.25));
    C.FillRect(Rect(PR.Right - Round(6 * FUIScale), PR.Top + 4,
                    PR.Right - Round(2 * FUIScale), PR.Bottom - 4));
    C.Brush.Color := PixToColor(Theme.Accent);
    Y := PR.Top + 4 +
      Round((PR.Bottom - PR.Top - 8) * FPopupTop / FPopupN);
    C.FillRect(Rect(PR.Right - Round(6 * FUIScale), Y,
                    PR.Right - Round(2 * FUIScale),
                    Y + Max(16, Round((PR.Bottom - PR.Top - 8) *
                                      I / FPopupN))));
  end;
  C.Brush.Style := bsClear;
  C.Pen.Width := 1;
end;

function TMainForm.IsSelected(I: Integer): Boolean;
var
  K: Integer;
begin
  Result := True;
  for K := 0 to High(FSel) do
    if FSel[K] = I then Exit;
  Result := False;
end;

{ The selection outlines drawn once into a transparent layer, kept while the
  drawing, selection, camera and screen size are unchanged. }
procedure TMainForm.EnsureSelLayer;
var
  Key: string;
  AY, K: Integer;
  Hi: TPointFArray;
  W: Single;
  Sum, X: Int64;
  P: TProjector;
begin
  Sum := 0;
  X := 0;
  for K := 0 to High(FSel) do
  begin
    Sum := Sum + FSel[K];
    X := X xor (Int64(FSel[K]) * (K + 1));
  end;
  Key := Format('%p|%d|%d|%d|%d|%.6f|%.6f|%.6f|%.3f|%.3f|%d|%d|%d|%.3f',
    [Pointer(FD.Doc), FD.Doc.FEditSeq, Length(FSel), Sum, X, FD.Az, FD.El, FD.Zoom, FD.ViewX, FD.ViewY,
     Ord(FD.View), FArt.Width, FArt.Height, FUIScale]);
  if (FSelLayer <> nil) and (Key = FSelLayerKey) then Exit;
  FShotOK := False;                { the selection moved: the shot is stale }
  if FSelLayer = nil then FSelLayer := TArtSurface.Create(FArt.Width, FArt.Height)
  else FSelLayer.SetSize(FArt.Width, FArt.Height);
  FSelLayer.ClearTransparent;
  W := Max(3, Round(3 * FUIScale));
  P := Proj;

  { Traced against the depth buffer so back edges are not drawn over the
    front, and traced into the layer with our own rasterizer.  On the LCL
    canvas, thousands of gtk3/cairo calls took seconds per frame on a big
    selection; cached here, a still selection costs nothing after the first
    build. }
  for AY := 0 to High(FSel) do
  begin
    if (FSel[AY] < 0) or (FSel[AY] >= FD.Doc.Live) then Continue;
    { a picked group shows as its box, not every edge lit }
    if FD.Doc.TopPartIn(FSel[AY]) > 0 then Continue;
    if Length(FSel) > SEL_TRACE_MAX then
    begin
      { past SEL_TRACE_MAX, no depth test, just plain outlines: an orbit
        rebuilds this every frame and tracing would be the cost again }
      if FD.Doc[FSel[AY]].Kind in [ekLine, ekArc, ekDim] then
      begin
        Hi := FD.Doc.Outline(P, FSel[AY]);
        for K := 1 to High(Hi) do
          FSelLayer.Line(Hi[K - 1].X, Hi[K - 1].Y, Hi[K].X, Hi[K].Y, W,
            Pix(70, 130, 240), 1.0);
      end;
    end
    { a picked face is dotted and keeps its own edges, so a picked line shows }
    else if FD.Doc[FSel[AY]].Kind = ekFace then
      PaintFaceHint(nil, FSel[AY], Pix(70, 130, 240), FSelLayer, 0, 0, False, 3)
    else
      TraceOutlineInto(FSelLayer, FSel[AY], Pix(70, 130, 240), W);
  end;
  FSelLayerKey := Key;
end;

{ ---- touch ----
  One finger is the mouse, but the press waits until it moves, is held or
  lifts (a tap); a second finger arriving means a gesture.  Two fingers pan
  by their middle and zoom by their spread.  When one of two lifts, the
  other is ignored until it lifts too, so it does not draw. }
procedure TMainForm.OnTouch(Kind: TTouchKind; Seq: Pointer; SX, SY: Double);
var
  P: TPoint;
  I, K, N: Integer;
begin
  if FBusy then Exit;
  Inc(FTouchCount);
  P := pbScreen.ScreenToClient(Point(Round(SX), Round(SY)));
  I := -1;
  for K := 0 to High(FTouches) do
    if FTouches[K].Seq = Seq then I := K;
  if FTimings then
    TimingLine(Format('touch %d at %.0f,%.0f finger %d of %d mode %d',
      [Ord(Kind), P.X, P.Y, I, Length(FTouches), Ord(FTouchMode)]));
  case Kind of
    tkBegin:
      begin
        if I < 0 then
        begin
          SetLength(FTouches, Length(FTouches) + 1);
          I := High(FTouches);
          FTouches[I].Seq := Seq;
          FTouches[I].X0 := P.X;
          FTouches[I].Y0 := P.Y;
          FTouches[I].T0 := GetTickCount64;
        end;
        FTouches[I].X := P.X;
        FTouches[I].Y := P.Y;
        N := Length(FTouches);
        if N = 1 then
        begin
          FTouchMode := tmPending;
          FTouchDown := False;
          { hover first, so the snap and readout are for this spot }
          pbScreenMouseMove(pbScreen, [], P.X, P.Y);
        end
        else if (N = 2) and (FTouchMode in [tmPending, tmMouse]) then
        begin
          if FTouchDown then
          begin
            pbScreenMouseUp(pbScreen, mbLeft, [ssLeft], FTouches[0].X, FTouches[0].Y);
            FTouchDown := False;
          end;
          FTouchMode := tmGesture;
          GestureStart;
        end;
      end;
    tkUpdate:
      if I >= 0 then
      begin
        FTouches[I].X := P.X;
        FTouches[I].Y := P.Y;
        case FTouchMode of
          tmPending:
            if (Abs(P.X - FTouches[0].X0) > 8) or (Abs(P.Y - FTouches[0].Y0) > 8) then
            begin
              TouchSendDown;
              pbScreenMouseMove(pbScreen, [ssLeft], P.X, P.Y);
            end;
          tmMouse:
            if I = 0 then pbScreenMouseMove(pbScreen, [ssLeft], P.X, P.Y);
          tmGesture:
            if Length(FTouches) >= 2 then GestureMove;
        end;
      end;
    tkEnd, tkCancel:
      if I >= 0 then
      begin
        FTouches[I].X := P.X;
        FTouches[I].Y := P.Y;
        case FTouchMode of
          tmPending:
            if (Kind = tkEnd) and (I = 0) then
            begin
              { a tap: press and release here }
              TouchSendDown;
              pbScreenMouseUp(pbScreen, mbLeft, [ssLeft], P.X, P.Y);
              FTouchDown := False;
            end;
          tmMouse:
            if (I = 0) and FTouchDown then
            begin
              pbScreenMouseUp(pbScreen, mbLeft, [ssLeft], P.X, P.Y);
              FTouchDown := False;
            end;
          tmGesture:
            begin
              { the full frame comes when the camera settles }
              FLastWheel := GetTickCount64;
              FTouchMode := tmSpent;
            end;
        end;
        for K := I to High(FTouches) - 1 do FTouches[K] := FTouches[K + 1];
        SetLength(FTouches, Length(FTouches) - 1);
        if Length(FTouches) = 0 then
        begin
          FTouchMode := tmNone;
          FTouchDown := False;
        end;
      end;
  end;
end;

{ the press for the first finger, where it landed }
procedure TMainForm.TouchSendDown;
begin
  if FTouchDown or (Length(FTouches) = 0) then Exit;
  pbScreenMouseDown(pbScreen, mbLeft, [ssLeft], FTouches[0].X0, FTouches[0].Y0);
  FTouchDown := True;
  FTouchMode := tmMouse;
end;

{ from the tick: a finger held still long enough is a press, not a tap }
procedure TMainForm.TouchTick;
begin
  if (FTouchMode = tmPending) and (Length(FTouches) > 0) and
     (GetTickCount64 - FTouches[0].T0 > 180) then
    TouchSendDown;
end;

procedure TMainForm.GestureStart;
begin
  if Length(FTouches) < 2 then Exit;
  FGestMidX := (FTouches[0].X + FTouches[1].X) / 2;
  FGestMidY := (FTouches[0].Y + FTouches[1].Y) / 2;
  FGestDist := Sqrt(Sqr(FTouches[0].X - FTouches[1].X) + Sqr(FTouches[0].Y - FTouches[1].Y));
end;

procedure TMainForm.GestureMove;
var
  MX, MY, D: Double;
begin
  if Length(FTouches) < 2 then Exit;
  MX := (FTouches[0].X + FTouches[1].X) / 2;
  MY := (FTouches[0].Y + FTouches[1].Y) / 2;
  D := Sqrt(Sqr(FTouches[0].X - FTouches[1].X) + Sqr(FTouches[0].Y - FTouches[1].Y));
  if FQuickFrames then FCameraMoving := True;
  FLastWheel := GetTickCount64;
  if (Abs(MX - FGestMidX) >= 1) or (Abs(MY - FGestMidY) >= 1) then
    PanBy(MX - FGestMidX, MY - FGestMidY);
  { a pinch zooms about the middle; fingers very close give a jumpy ratio,
    so they only pan }
  if (FGestDist > 30) and (D > 30) and (Abs(D / FGestDist - 1) > 0.01) then
    ZoomAt(D / FGestDist, MX, MY);
  FGestMidX := MX;
  FGestMidY := MY;
  FGestDist := D;
  Invalidate;
end;

{ Clear everything that points into the sheet being left (selection,
  doomed list, hover): those indices mean nothing in the next sheet. }
procedure TMainForm.LeaveSheet;
begin
  SetLength(FSel, 0);
  SetLength(FDoomed, 0);
  { and the open-edge marks, which are points in this sheet's space }
  SetLength(FOpenEdges, 0);
  FHoverEnt := -1;
  FHoverFace := -1;
  FPushFace := -1;
  FOffFace := -1;
  FSelLayerKey := '';
  FScreenDirty := True;
end;

{ drop anything in the selection that is not in this sheet }
procedure TMainForm.PruneSelection;
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to High(FSel) do
    if (FSel[I] >= 0) and (FSel[I] < FD.Doc.Live) then
    begin
      FSel[N] := FSel[I];
      Inc(N);
    end;
  if N <> Length(FSel) then
  begin
    SetLength(FSel, N);
    FScreenDirty := True;
  end;
end;

procedure TMainForm.BeginBulkSelect;
var
  K: Integer;
begin
  SetLength(FSelBulk, FD.Doc.Live);
  for K := 0 to High(FSelBulk) do FSelBulk[K] := False;
  for K := 0 to High(FSel) do
    if (FSel[K] >= 0) and (FSel[K] < Length(FSelBulk)) then FSelBulk[FSel[K]] := True;
  FSelBulkOn := True;
end;

procedure TMainForm.EndBulkSelect;
begin
  FSelBulkOn := False;
  SetLength(FSelBulk, 0);
end;

procedure TMainForm.SelectAdd(I: Integer);
var
  T, K: Integer;
  M: TIntArrayW;
begin
  if (I < 0) or (I >= FD.Doc.Live) then Exit;
  if FD.Doc[I].Kind = ekPart then Exit;        { a record comes with its group }
  { a guide is never picked by click, box or /all; the measure tool's
    right-click erases one }
  if FD.Doc[I].Kind = ekGuide then Exit;
  T := FD.Doc.TopPartIn(I);
  if T < 0 then Exit;                            { outside the open group }
  if T = 0 then
  begin
    SelectAddOne(I);
    Exit;
  end;
  { the whole group, record included, so move, copy and delete carry it as
    one thing }
  M := FD.Doc.PartMembers(T, True);
  for K := 0 to High(M) do SelectAddOne(M[K]);
end;

procedure TMainForm.SelectAddOne(I: Integer);
begin
  if I < 0 then Exit;
  if FSelBulkOn and (I < Length(FSelBulk)) then
  begin
    if FSelBulk[I] then Exit;
    FSelBulk[I] := True;
  end
  else if IsSelected(I) then Exit;
  SetLength(FSel, Length(FSel) + 1);
  FSel[High(FSel)] := I;
  FScreenDirty := True;
end;

procedure TMainForm.SelectRemove(I: Integer);
var
  T, K: Integer;
  M: TIntArrayW;
begin
  if (I < 0) or (I >= FD.Doc.Live) then Exit;
  T := FD.Doc.TopPartIn(I);
  if T <= 0 then
  begin
    SelectRemoveOne(I);
    Exit;
  end;
  M := FD.Doc.PartMembers(T, True);
  for K := 0 to High(M) do SelectRemoveOne(M[K]);
end;

procedure TMainForm.SelectRemoveOne(I: Integer);
var
  K, J: Integer;
begin
  for K := 0 to High(FSel) do
    if FSel[K] = I then
    begin
      for J := K to High(FSel) - 1 do FSel[J] := FSel[J + 1];
      SetLength(FSel, Length(FSel) - 1);
      FScreenDirty := True;
      Exit;
    end;
end;

procedure TMainForm.SelectToggle(I: Integer);
begin
  if IsSelected(I) then SelectRemove(I) else SelectAdd(I);
end;

procedure TMainForm.SelectOnly(I: Integer);
begin
  SetLength(FSel, 0);
  SelectAdd(I);
end;

procedure TMainForm.ThemeSourceWindow;
begin
  if SourceForm = nil then Exit;
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  SourceForm.ThemeChrome;
  { dark when the theme's chrome is dark: the window is chrome, not sheet }
  with Themes[FThemeIdx] do
    if Panel.R + Panel.G + Panel.B < 3 * 128 then
      SourceForm.UseDark(True, PixToColor(Panel), PixToColor(Text))
    else
      SourceForm.UseDark(False, clWhite, clBlack);
end;

{ the source window: the sheet as its text, picked both ways }
procedure TMainForm.ShowSource;
begin
  if SourceForm = nil then
  begin
    hsDialogSkin.UseTheme(Themes[FThemeIdx]);
    Application.CreateForm(TSourceForm, SourceForm);
    SourceForm.OnAskState := @SourceAskState;
    SourceForm.OnAskSource := @SourceAskSource;
    SourceForm.OnAskPicked := @SourceAskPicked;
    SourceForm.OnPickThings := @SourcePickThings;
    SourceForm.OnApply := @SourceApply;
    SourceForm.OnRunJigs := @RunAllJigs;
    SourceForm.OnRunJig := @RunJigOfThing;
    SourceForm.OnPick := @SourcePick;
    SourceForm.OnCenter := @SourceCenter;
    { owned by the main window, so on Windows it opens in front of it, not
      behind }
    SourceForm.PopupMode := pmExplicit;
    SourceForm.PopupParent := Self;
    { beside the main window if there is room, else over its right half }
    if (FSourceBounds.Right > 200) and (FSourceBounds.Bottom > 150) and
       (FSourceBounds.Left + FSourceBounds.Right > Screen.DesktopLeft + 40) and
       (FSourceBounds.Left < Screen.DesktopLeft + Screen.DesktopWidth - 40) and
       (FSourceBounds.Top < Screen.DesktopTop + Screen.DesktopHeight - 40) then
      { where it was left, if that is still on a screen }
      SourceForm.SetBounds(FSourceBounds.Left, FSourceBounds.Top, FSourceBounds.Right, FSourceBounds.Bottom)
    else
    begin
      SourceForm.Height := Height;
      SourceForm.Top := Top;
      if Left + Width + SourceForm.Width <= Screen.DesktopLeft + Screen.DesktopWidth then
        SourceForm.Left := Left + Width
      else
        SourceForm.Left := Left + Width - SourceForm.Width;
    end;
  end;
  { in the program's theme, with a matching picked-line wash }
  ThemeSourceWindow;
  SourceForm.chkOnTop.Checked := FSourceOnTop;
  SourceForm.SetAutoComplete(FSourceComplete);
  SourceForm.Show;
  SourceForm.Refresh_;
end;

{ Two numbers that change when the drawing or the picking does; cheap, since
  the window asks several times a second.  The hash is meant to wrap, so
  overflow checks are off. }
{$push}{$Q-}{$R-}
procedure TMainForm.SourceAskState(out DocSeq, PickSeq: Int64);
var
  I: Integer;
begin
  DocSeq := 0;
  PickSeq := 0;
  if FD = nil then Exit;
  DocSeq := Int64(PtrUInt(FD)) xor (Int64(FD.Doc.FEditSeq) shl 20) xor
            (Int64(FD.Doc.Live) shl 8) xor (Int64(FD.UndoTop) shl 40) xor
            (Int64(FD.RedoTop) shl 50) xor FD.Doc.Context;
  PickSeq := Length(FSel);
  for I := 0 to High(FSel) do
    PickSeq := (PickSeq * 1000003) xor FSel[I];
end;
{$pop}

procedure TMainForm.SourceAskSource(L, Hints, Names: TStrings;
  out First, Last, LineThing: TIntArrayW; out SheetName: string);
begin
  SetLength(First, 0);
  SetLength(Last, 0);
  SetLength(LineThing, 0);
  SheetName := '';
  if FD = nil then Exit;
  SheetName := FD.Name;
  WriteFormat2(FD.Doc, FD.Name, FD.Units, L, First, Last, LineThing, Hints, Names);
end;

procedure TMainForm.SourceAskPicked(out Picked: TIntArrayW);
var
  I: Integer;
begin
  SetLength(Picked, Length(FSel));
  for I := 0 to High(FSel) do Picked[I] := FSel[I];
end;

{ Lines picked in the source window, through SelectAdd so the sheet's rules
  apply: a thing in a closed group picks the group, one outside the open
  group is not picked. }
procedure TMainForm.SourcePickThings(const Things: TIntArrayW);
var
  I: Integer;
  M: TIntArrayW;
begin
  if FD = nil then Exit;
  SelectNone;
  BeginBulkSelect;
  for I := 0 to High(Things) do
    if FD.Doc[Things[I]].Kind = ekPart then
    begin
      { a GROUP line is the group: any member picks the whole }
      M := FD.Doc.PartMembers(FD.Doc[Things[I]].Grp, False);
      if Length(M) > 0 then SelectAdd(M[0]);
    end
    else
      SelectAdd(Things[I]);
  EndBulkSelect;
  FScreenDirty := True;
  InfoChanged;
  pbScreen.Invalidate;
end;

{ Apply the source window's text to the drawing.  Read into a scratch
  drawing first, so a fault leaves this one untouched. }
function TMainForm.SourceApply(L: TStrings; out ErrLine: Integer; out Err: string): Boolean;
var
  T: TWorkDoc;
begin
  Result := False;
  ErrLine := -1;
  Err := 'there is no sheet open';
  if FD = nil then Exit;
  T := TWorkDoc.Create;
  try
    Result := ReadHeck(L, T, FD.Units, ErrLine, Err);
  finally
    T.Free;
  end;
  if not Result then Exit;
  PushUndo;
  LeaveSheet;        { every held index is about to mean something else }
  ResetTool;
  FD.Doc.Clear;
  ReadHeck(L, FD.Doc, FD.Units, ErrLine, Err);
  FD.Dirty := True;
  RebuildFlatFaces;
  RenderInk;
  RecomposeAll;
  FCmdMsg := Format('Applied: %d things.', [FD.Doc.Live]);
  pbScreen.Invalidate;
  pbCmd.Invalidate;
end;

{ Run a group's jig again.  Its output is read into a scratch drawing
  first; only if that works is the group's content replaced, in one undo
  step. }
function TMainForm.RunJigOf(PartId: Integer): Boolean;
var
  SF: TStairFrame;
  SS: TStairSpec;
  SU: TStairUse;
  Spec, Err: string;
  Out_: TStringList;
  T: TWorkDoc;
  M: TIntArrayW;
  Doomed: array of Boolean;
  I, ErrLine, WasStamp, Rec: Integer;
begin
  Result := False;
  if FD = nil then Exit;
  Spec := FD.Doc.PartJig(PartId);
  if Spec = '' then
  begin
    FCmdMsg := 'That group is not made by a jig.';
    Exit;
  end;
  { the stairs are the program's own: rebuilt from what they remember, where
    the group is now, no script }
  if IsStairJig(Spec) then
  begin
    if not StairFromJig(Spec, FD.Units, SF, SS, SU) then
    begin
      FCmdMsg := 'The stairs'' line in the source does not read: ' + Spec;
      Exit;
    end;
    SF.Bottom := StairWhereNow(PartId, SF, SS);
    if not StairCheck(SF, SS, Err) then
    begin
      FCmdMsg := 'The stairs cannot be built from that: ' + Err;
      Exit;
    end;
    PushUndo;
    StairRebuild(PartId, SF, SS, SU);
    Exit(True);
  end;
  Out_ := TStringList.Create;
  try
    Screen.Cursor := crHourGlass;
    try
      if not RunJig(Spec, FD.Units, Out_, Err) then
      begin
        FCmdMsg := 'The jig did not run - ' + Err;
        Exit;
      end;
    finally
      Screen.Cursor := crDefault;
    end;
    T := TWorkDoc.Create;
    try
      if not ReadHeck(Out_, T, FD.Units, ErrLine, Err) then
      begin
        FCmdMsg := Format('Heck if I know - what the jig printed is not Heck.  Line %d: %s', [ErrLine + 1, Err]);
        Exit;
      end;
    finally
      T.Free;
    end;
    PushUndo;
    LeaveSheet;
    ResetTool;
    M := FD.Doc.PartMembers(PartId, False);
    Rec := FD.Doc.PartEnt(PartId);
    SetLength(Doomed, FD.Doc.Live);
    for I := 0 to High(Doomed) do Doomed[I] := False;
    for I := 0 to High(M) do
      if M[I] <> Rec then Doomed[M[I]] := True;
    FD.Doc.DeleteMarked(Doomed);
    WasStamp := FD.Doc.Stamp;
    FD.Doc.Stamp := PartId;
    try
      ReadHeck(Out_, FD.Doc, FD.Units, ErrLine, Err);
    finally
      FD.Doc.Stamp := WasStamp;
    end;
    FD.Dirty := True;
    Result := True;
  finally
    Out_.Free;
  end;
end;

{ center and fit the selection: a glide in 3D, as a cube click does,
  straight there in plan and iso }
procedure TMainForm.SourceCenter;
var
  FitZ, FitX, FitY: Double;
begin
  if (FD = nil) or (Length(FSel) = 0) then Exit;
  if FitTarget(True, FD.Az, FD.El, FitZ, FitX, FitY) then
    GlideCamera(FD.Az, FD.El, FitZ, FitX, FitY);
end;

procedure TMainForm.SourcePick(On: Boolean);
begin
  FTextPick := On;
  if On then
  begin
    FCmdMsg := 'Picking for the text: click a point on the sheet, and it is typed in.  Esc stops.';
    { the sheet is not raised, so the text being filled stays in view }
    pbScreen.Invalidate;
  end
  else
    FCmdMsg := 'Picking for the text is over.';
  pbCmd.Invalidate;
end;

function TMainForm.RunJigOfThing(Thing: Integer): Boolean;
begin
  Result := False;
  if (FD = nil) or (Thing < 0) or (Thing >= FD.Doc.Live) then Exit;
  if (FD.Doc[Thing].Kind <> ekPart) or (FD.Doc[Thing].Jig = '') then Exit;
  Result := RunJigOf(FD.Doc[Thing].Grp);
  if Result then
  begin
    RebuildFlatFaces;
    RenderInk;
    RecomposeAll;
    pbScreen.Invalidate;
  end;
end;

function TMainForm.RunAllJigs: Integer;
var
  Ids: TIntArrayW;
  I, N: Integer;
begin
  Result := 0;
  if FD = nil then Exit;
  { collect the ids first: running a jig moves everything in the list }
  N := 0;
  SetLength(Ids, FD.Doc.Live);
  for I := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[I].Kind = ekPart) and (FD.Doc[I].Jig <> '') then
    begin
      Ids[N] := FD.Doc[I].Grp;
      Inc(N);
    end;
  for I := 0 to N - 1 do
    if RunJigOf(Ids[I]) then Inc(Result);
  RebuildFlatFaces;
  RenderInk;
  RecomposeAll;
  if Result = N then FCmdMsg := Format('%d jigs run.', [Result]);
  pbScreen.Invalidate;
  pbCmd.Invalidate;
end;

{ The panels read the selection, so they are refreshed wherever it or the
  drawing changes; a panel a frame behind is worse than none. }
procedure TMainForm.InfoChanged;
begin
  GroupsChanged;
  if not FInfoOn then Exit;
  RebuildInfo;
  pbInfo.Invalidate;
end;

procedure TMainForm.SelectNone;
begin
  if Length(FSel) = 0 then Exit;
  SetLength(FSel, 0);
  FScreenDirty := True;
end;

{ does this entity have a corner at that point? }
function TMainForm.EntHasPoint(I: Integer; const P: TP3): Boolean;
const
  TOL = 1E-7;
var
  K: Integer;
begin
  Result := True;
  if Dist(FD.Doc[I].A, P) < TOL then Exit;
  if Dist(FD.Doc[I].B, P) < TOL then Exit;
  for K := 0 to High(FD.Doc[I].Poly) do
    if Dist(FD.Doc[I].Poly[K], P) < TOL then Exit;
  Result := False;
end;

{ Double click: a face takes the edges round it, an edge the faces it
  bounds (SketchUp's rule). }
procedure TMainForm.SelectAttached(I: Integer);
var
  J: Integer;
begin
  SelectOnly(I);
  if I < 0 then Exit;
  if FD.Doc.TopPartIn(I) > 0 then Exit;    { a group is the whole of itself }
  { a guide is not part of the drawing, so nothing is attached to it }
  if FD.Doc[I].Kind = ekGuide then Exit;
  if FD.Doc[I].Kind = ekFace then
  begin
    for J := 0 to FD.Doc.Live - 1 do
      if (J <> I) and (FD.Doc[J].Kind in [ekLine, ekArc]) and
         EntHasPoint(I, FD.Doc[J].A) and EntHasPoint(I, FD.Doc[J].B) then
        SelectAdd(J);
  end
  else
    for J := 0 to FD.Doc.Live - 1 do
      if (J <> I) and (FD.Doc[J].Kind = ekFace) and
         EntHasPoint(J, FD.Doc[I].A) and EntHasPoint(J, FD.Doc[I].B) then
        SelectAdd(J);
end;

{ Triple click: everything joined on, however far it runs.  A flood over
  shared corners, using a hash of every corner and the things that have it
  (testing everything against everything was minutes on a big part).  A
  solid's members come along in one step. }
procedure TMainForm.SelectConnected(I: Integer);
var
  Have: array of Boolean;
  Queue: array of Integer;
  QHead, QTail, J, K, N, E: Integer;
  Pts: TP3Array;
  Map: TFPHashList;
  Key: shortstring;
  Lists: array of TIntArrayW;
  ListIx: Integer;

  function KeyOf(const P: TP3): shortstring;
  var
    Q: array[0..2] of Int64;
  begin
    Q[0] := Round(P.X * 1E7); Q[1] := Round(P.Y * 1E7); Q[2] := Round(P.Z * 1E7);
    SetLength(Result, 24);
    Move(Q[0], Result[1], 24);
  end;

  procedure Take(E: Integer);
  begin
    if (E < 0) or Have[E] then Exit;
    { guides share corners but are not part of the drawing; never flood
      through them }
    if FD.Doc[E].Kind = ekGuide then Exit;
    Have[E] := True;
    if QTail >= Length(Queue) then SetLength(Queue, Max(64, QTail * 2));
    Queue[QTail] := E;
    Inc(QTail);
  end;

begin
  SelectOnly(I);
  if I < 0 then Exit;
  { three clicks on a guide is still just the guide }
  if FD.Doc[I].Kind = ekGuide then Exit;
  N := FD.Doc.Live;
  SetLength(Have, N);
  SetLength(Queue, 64);
  QHead := 0; QTail := 0;
  { every corner once, with the list of things that have it }
  Map := TFPHashList.Create;
  try
    for J := 0 to N - 1 do
    begin
      FD.Doc.VertsOf([J], Pts);
      for K := 0 to High(Pts) do
      begin
        Key := KeyOf(Pts[K]);
        { stored one up: a nil item is an empty slot to TFPHashList }
        ListIx := Map.FindIndexOf(Key);
        if ListIx < 0 then
        begin
          SetLength(Lists, Length(Lists) + 1);
          ListIx := High(Lists);
          Map.Add(Key, Pointer(PtrInt(ListIx + 1)));
        end
        else
          ListIx := PtrInt(Map.Items[ListIx]) - 1;
        if (Length(Lists[ListIx]) = 0) or (Lists[ListIx][High(Lists[ListIx])] <> J) then
        begin
          SetLength(Lists[ListIx], Length(Lists[ListIx]) + 1);
          Lists[ListIx][High(Lists[ListIx])] := J;
        end;
      end;
    end;
    Take(I);
    while QHead < QTail do
    begin
      E := Queue[QHead];
      Inc(QHead);
      { the rest of its solid, in one go }
      if FD.Doc[E].Grp > 0 then
        for J := 0 to N - 1 do
          if (not Have[J]) and (FD.Doc[J].Grp = FD.Doc[E].Grp) then Take(J);
      { and whatever shares a corner with it }
      FD.Doc.VertsOf([E], Pts);
      for K := 0 to High(Pts) do
      begin
        ListIx := Map.FindIndexOf(KeyOf(Pts[K]));
        if ListIx < 0 then Continue;
        ListIx := PtrInt(Map.Items[ListIx]) - 1;
        for J := 0 to High(Lists[ListIx]) do Take(Lists[ListIx][J]);
      end;
    end;
  finally
    Map.Free;
  end;
  SetLength(FSel, QTail);
  for J := 0 to QTail - 1 do FSel[J] := Queue[J];
  FScreenDirty := True;
end;

{ SketchUp's modifiers: Ctrl adds, Shift toggles, both take away, nothing
  held starts over.  Right to left takes anything the box touches; left to
  right only what fits inside. }
procedure TMainForm.FinishSelect(X, Y: Integer; Shift: TShiftState);
var
  I: Integer;
  Mode: TSelMode;
  Before: array of Integer;
begin
  if [ssCtrl, ssShift] <= Shift then Mode := smRemove
  else if ssShift in Shift then Mode := smToggle
  else if ssCtrl in Shift then Mode := smAdd
  else Mode := smOnly;

  if (Abs(X - FBoxX) > 3) or (Abs(Y - FBoxY) > 3) then
    SelectInBox(FBoxX, FBoxY, X, Y, X < FBoxX, Mode)
  else
  begin
    I := PickAt(X, Y);
    if I < 0 then
    begin
      { SketchUp: a click on nothing while a group is open closes it }
      if Mode = smOnly then
        if FD.Doc.Context <> 0 then CloseGroup else SelectNone;
    end
    else if (FD.Doc.TopPartIn(I) > 0) and (FClickN >= 2) then
      { GTK delivers a double-click's second press twice, so the count reads
        one higher; hence >= 2 for double and >= 3 for triple throughout }
      OpenGroup(FD.Doc.TopPartIn(I))
    else if (FD.Doc.TopPartIn(I) = 0) and (FClickN >= 2) then
    begin
      { the first click already did its part; with a key held the rest is
        added, or taken away with both }
      Before := Copy(FSel);
      if FClickN >= 3 then SelectConnected(I) else SelectAttached(I);
      if Mode = smRemove then MergeSel(Before, smRemove)
      else if Mode <> smOnly then MergeSel(Before, smAdd);
    end
    else
      case Mode of
        smRemove: SelectRemove(I);
        smToggle: SelectToggle(I);
        smAdd: SelectAdd(I);
      else
        SelectOnly(I);
      end;
  end;

  if Length(FSel) = 0 then
  begin
    if FCmdMsg = '' then FCmdMsg := 'Nothing selected.';
  end
  else if SoleGroup > 0 then
    FCmdMsg := Format('Group "%s"%s - double-click to work inside it.',
      [FD.Doc.PartName(SoleGroup),
       specialize IfThen<string>(FD.Doc.PartLocked(SoleGroup), ' (locked)', '')])
  { a lone dimension can be told what to say, so the message says so }
  else if SelectedDim >= 0 then
    FCmdMsg := 'Dimension picked - type what it should read and press Enter.'
  else if Length(FSel) = 1 then FCmdMsg := '1 thing selected.'
  else FCmdMsg := Format('%d things selected.', [Length(FSel)]);
  FScreenDirty := True;
  InvalidateStatus;
end;

{ crossing takes anything the box touches, otherwise only what is wholly
  inside }
procedure TMainForm.SelectInBox(X0, Y0, X1, Y1: Integer; Crossing: Boolean; Mode: TSelMode);
var
  I, T: Integer;
  Picked: TIntArrayW;
  Before: array of Integer;
  Tk: QWord;
begin
  if X1 < X0 then begin T := X0; X0 := X1; X1 := T; end;
  if Y1 < Y0 then begin T := Y0; Y0 := Y1; Y1 := T; end;
  Before := Copy(FSel);
  SetLength(FSel, 0);
  Tk := GetTickCount64;
  BeginBulkSelect;
  { what the box takes is BoxPick's question (see it and BoxTakes) }
  Picked := FD.Doc.BoxPick(Proj, X0, Y0, X1, Y1, Crossing);
  for I := 0 to High(Picked) do SelectAdd(Picked[I]);
  EndBulkSelect;
  MergeSel(Before, Mode);
  Took('box select', Tk);
  FScreenDirty := True;
end;

{ FSel holds what was just picked; put it together with what was selected
  before }
procedure TMainForm.MergeSel(const Before: array of Integer; Mode: TSelMode);
var
  InBefore, InGot: array of Boolean;
  Got: array of Integer;
  K, N: Integer;

  procedure Keep(E: Integer);
  begin
    FSel[N] := E;
    Inc(N);
  end;

begin
  if Mode = smOnly then Exit;
  Got := Copy(FSel);
  SetLength(InBefore, FD.Doc.Live);
  SetLength(InGot, FD.Doc.Live);
  for K := 0 to High(Before) do
    if (Before[K] >= 0) and (Before[K] < FD.Doc.Live) then InBefore[Before[K]] := True;
  for K := 0 to High(Got) do InGot[Got[K]] := True;
  SetLength(FSel, Length(Before) + Length(Got));
  N := 0;
  for K := 0 to High(Before) do
    if (Before[K] >= 0) and (Before[K] < FD.Doc.Live) and
       ((Mode = smAdd) or not InGot[Before[K]]) then Keep(Before[K]);
  if Mode <> smRemove then
    for K := 0 to High(Got) do
      if not InBefore[Got[K]] then Keep(Got[K]);
  SetLength(FSel, N);
  FScreenDirty := True;
end;

procedure TMainForm.DeleteSelection;
var
  I, N: Integer;
  Doomed: array of Boolean;
  Held: TIntArrayW;
  Tk: QWord;
begin
  N := Length(FSel);
  if N = 0 then Exit;
  PushUndo;
  Tk := GetTickCount64;
  { marked and removed in one pass; deleting one at a time was quadratic }
  SetLength(Doomed, FD.Doc.Live);
  for I := 0 to High(Doomed) do Doomed[I] := False;
  for I := 0 to N - 1 do
    if (FSel[I] >= 0) and (FSel[I] < Length(Doomed)) and
       not FD.Doc.PartLockedUp(FD.Doc.TopPartIn(FSel[I])) then Doomed[FSel[I]] := True;
  { and the faces those edges were holding up (see FacesOnEdges) }
  FD.Doc.FacesOnEdges(FSel, Held);
  for I := 0 to High(Held) do Doomed[Held[I]] := True;
  FD.Doc.PointsOnGuides(FSel, Held);
  for I := 0 to High(Held) do Doomed[Held[I]] := True;
  FD.Doc.DeleteMarked(Doomed);
  Took('delete selection', Tk);
  SetLength(FSel, 0);
  RebuildFlatFaces;
  FCmdMsg := Format('Deleted %d thing%s.', [N, IfThen(N = 1, '', 's')]);
  RenderInk;
  RecomposeAll;
end;

{ How far the move has traveled.  Typed wins: a bare length runs along the
  current direction, [x,y,z] is a point in the drawing, <x,y,z> an offset
  from the grab. }
function TMainForm.MoveDelta: TP3;
var
  D: TP3;
  L, Len: Double;
  Txt: string;
  Abs_, Rel: Boolean;
  N: Integer;
  V: array[0..2] of Double;
begin
  Result := Sub3(FCur, FP1);

  Txt := Trim(FInput);
  Abs_ := (Length(Txt) >= 2) and (Txt[1] = '[');
  Rel := (Length(Txt) >= 2) and (Txt[1] = '<');
  if Abs_ or Rel then
  begin
    N := ParseTriple(Txt, FD.Units, V[0], V[1], V[2]);
    if N > 0 then
    begin
      if Abs_ then
        Result := P3(V[0] - FP1.X, V[1] - FP1.Y, V[2] - FP1.Z)
      else
        Result := P3(V[0], V[1], V[2]);
    end;
    Exit;
  end;

  if FDirLock >= 0 then
  begin
    D := AxisDir(FDirLock);
    L := Result.X * D.X + Result.Y * D.Y + Result.Z * D.Z;
    if (Txt <> '') and ParseLen(Txt, FD.Units, Len) then
      L := Sign(IfThen(L = 0, 1, L)) * Len;
    Result := Mul3(D, L);
    Exit;
  end;

  { Shift keeps the axis the move has drifted onto, as SketchUp locks the
    showing inference }
  if ssShift in FMoveShift then
  begin
    if (Abs(Result.X) >= Abs(Result.Y)) and (Abs(Result.X) >= Abs(Result.Z)) then
      Result := P3(Result.X, 0, 0)
    else if Abs(Result.Y) >= Abs(Result.Z) then
      Result := P3(0, Result.Y, 0)
    else
      Result := P3(0, 0, Result.Z);
  end;

  if (Txt <> '') and ParseLen(Txt, FD.Units, L) then
  begin
    Len := Sqrt(Sqr(Result.X) + Sqr(Result.Y) + Sqr(Result.Z));
    if Len < 1E-9 then Exit;
    Result := P3(Result.X * L / Len, Result.Y * L / Len, Result.Z * L / Len);
  end;
end;

{ The arc's ends are on the two lines of a corner, so it could round that
  corner: the fillet that keeps the first click where it was. }
function TMainForm.FilletCandidate(out F: TFillet): Boolean;
begin
  Result := (FTool = ptArc) and (FStage = 2) and
            FD.Doc.FilletFromEnds(FP1, FP2, F);
end;

{ Is the arc being placed a fillet, and which?  As SketchUp turns the arc
  magenta when tangent to both lines: the fillet is worked out from the two
  ends, and taken when the pull is within a finger's width of its middle.  A
  number typed while magenta, or with an r suffix, is the radius.  Typed says
  a radius was typed. }
function TMainForm.ArcFillet(out F: TFillet; out Typed: Boolean): Boolean;
const
  LOCK_PX = 16;
var
  Txt: string;
  L: Double;
  RSuffix, Near_: Boolean;
  M: TPointF;
  F2: TFillet;
begin
  Result := False;
  Typed := False;
  if not FilletCandidate(F) then Exit;
  M := ScreenOf(ArcPoint(F.ArcC, F.R, F.A0 + F.Sweep / 2, F.Pl, F.Nm));
  Near_ := Sqrt(Sqr(M.X - FMouseSX) + Sqr(M.Y - FMouseSY)) <= LOCK_PX * FUIScale;
  Txt := Trim(FInput);
  RSuffix := (Length(Txt) > 1) and (Txt[Length(Txt)] in ['r', 'R']);
  if RSuffix then Delete(Txt, Length(Txt), 1);
  if (Txt <> '') and (RSuffix or Near_) then
  begin
    if not ParseLen(Txt, FD.Units, L) then Exit;
    if not FD.Doc.FilletAt(F.Corner, L, F2) then Exit;
    F := F2;
    Typed := True;
    Exit(True);
  end;
  Result := Near_;
end;

{ The face a press is on: the one under the pointer, or during a replay the
  one holding the pressed point (another window or camera can find a
  different face behind the same pixel). }
function TMainForm.FaceAtPress: Integer;
begin
  if FReplayFace >= 0 then Result := FReplayFace
  else Result := FD.Doc.HitFace(Proj, FMouseSX, FMouseSY);
end;

{ the face the overlay is washing blue now, or -1: the same choices
  PaintOverlay makes, for the cursor's square }
function TMainForm.HintFaceNow: Integer;
begin
  Result := -1;
  case FTool of
    ptPush, ptDrill:
      if FStage = 1 then Result := FPushFace else Result := FHoverFace;
    ptFollow:
      if FStage = 0 then Result := FHoverFace else Result := FFollowFace;
    ptLine, ptRect, ptCircle, ptArc:
      if (FStage = 0) and not FPlaneHeld then
        Result := InContextFace(FD.Doc.HitFace(Proj, FMouseSX, FMouseSY));
  end;
end;

{ The part of a tool's preview under the pointer, drawn into the cursor's
  square (see pbScreenPaint).  OX, OY is the square's corner on screen. }
procedure TMainForm.PaintUnderCursor(S: TArtSurface; OX, OY: Integer);
var
  F: TFillet;
  Typed: Boolean;
  K, HF: Integer;
  PA, PB: TPointF;
  RectPts: TP3Array;
begin
  { The square pasted back over the cursor is a patch of the finished
    drawing without the preview, and the preview's nearest corner is always
    right at the cursor, so draw it into the square.  Theme.Accent is close
    enough at this size to the real line's color. }
  if (FTool = ptLine) and (FStage = 1) then
  begin
    PA := ScreenOf(FP1);
    PB := ScreenOf(PreviewTarget);
    S.Line(PA.X - OX, PA.Y - OY, PB.X - OX, PB.Y - OY,
      Max(3, Round(3 * FUIScale)), Theme.Accent, 1);
  end
  else if (FTool = ptRect) and (FStage = 1) then
  begin
    RectPts := RectCorners(FP1, RectTarget, FD.Plane);
    for K := 0 to 3 do
    begin
      PA := ScreenOf(RectPts[K]);
      PB := ScreenOf(RectPts[(K + 1) mod 4]);
      S.Line(PA.X - OX, PA.Y - OY, PB.X - OX, PB.Y - OY,
        Max(3, Round(3 * FUIScale)), Theme.Accent, 1);
    end;
  end
  else if (FTool = ptOffset) and (FStage = 1) then
  begin
    { the offset loop, likewise: its nearest corner is the one being dragged }
    RectPts := OffsetPreview;
    for K := 0 to High(RectPts) do
    begin
      PA := ScreenOf(RectPts[K]);
      PB := ScreenOf(RectPts[(K + 1) mod Length(RectPts)]);
      S.Line(PA.X - OX, PA.Y - OY, PB.X - OX, PB.Y - OY,
        Max(3, Round(3 * FUIScale)), Theme.Accent, 1);
    end;
  end;

  { the blue face wash, drawn into the square too, or the square cuts a hole
    in it right at the pointer }
  HF := HintFaceNow;
  { the square comes from the shown picture, which may already have it }
  if (HF >= 0) and (HF <> FHintInShot) then
    PaintFaceHint(nil, HF, HINT_BLUE, S, OX, OY);
  if not ArcFillet(F, Typed) then Exit;
  S.BlendMode := bmNormal;
  PA := ScreenOf(ArcPoint(F.ArcC, F.R, F.A0, F.Pl, F.Nm));
  for K := 1 to FSidesArc do
  begin
    PB := ScreenOf(ArcPoint(F.ArcC, F.R, F.A0 + F.Sweep * K / FSidesArc,
      F.Pl, F.Nm));
    S.Line(PA.X - OX, PA.Y - OY, PB.X - OX, PB.Y - OY,
      Max(3, Round(3 * FUIScale)), Pix(225, 40, 225), 1);
    PA := PB;
  end;
end;

{ The second click of a double-click with the arc tool.  Right after a
  fillet it trims that corner (SketchUp's double-click); otherwise, near a
  corner, it rounds it with the last radius. }
function TMainForm.ArcDoubleClick(SX, SY: Integer): Boolean;
var
  Corner: TP3;
  F: TFillet;
  N: Integer;
begin
  Result := False;
  if FTool <> ptArc then Exit;
  { only the double-click whose first click made the fillet; a pending trim
    used a minute later would hit the old corner instead of the new one }
  if FFilletPending and (FFilletSeq = FEditSeq) and
     (GetTickCount64 - FFilletTick < 800) then
  begin
    FFilletPending := False;
    N := FD.Doc.TrimFillet(FLastFillet);
    if N > 0 then
    begin
      RebuildFlatFaces;
      RenderInk;
      RecomposeAll;
      FCmdMsg := 'Corner rounded to ' + FormatLen(FLastFillet.R, FD.Units) +
        ' and trimmed.  Double-click another corner for the same again.';
      ResetTool;
      Exit(True);
    end;
  end;
  FFilletPending := False;
  if FLastFilletR <= 0 then Exit;
  if not FD.Doc.NearestCorner(Proj, SX, SY, 18 * FUIScale, Corner) then Exit;
  ResetTool;
  if not FD.Doc.FilletAt(Corner, FLastFilletR, F) then
  begin
    FCmdMsg := 'A ' + FormatLen(FLastFilletR, FD.Units) +
      ' radius does not fit that corner.';
    Exit(True);
  end;
  PushUndo;
  FD.Doc.ApplyFillet(F, FSidesArc, FInkColor, FEdgeW, True);
  RebuildFlatFaces;
  RenderInk;
  RecomposeAll;
  FCmdMsg := 'Same again - corner rounded to ' + FormatLen(F.R, FD.Units) + '.';
  Result := True;
end;

{ Alt's tangent lock: the bulge that runs the arc smoothly out of the edge
  its first point is on (see TangentSagitta in hsDrawing). }
function TMainForm.TangentBulge(Pl: TPlane; out Bulge: Double): Boolean;
begin
  Result := FArcTanHas and
            TangentSagitta(FP1, FP2, FArcTanDir, Pl, Bulge);
end;

function TMainForm.ArcPicks(const B: TP3; out Pl: TPlane; out C: TP3;
  out R, A0, Sweep, Bulge: Double): Boolean;
var
  AU, AV, N, FN: TP3;
  U1, V1, U2, V2, UC, VC, Ln, NU, NV, L, Size, Tol: Double;
  F: Integer;

  function OnPlane(const P, Org, Nm: TP3): Boolean;
  begin
    Result := Abs(Dot3(Nm, Sub3(P, Org))) <= Tol;
  end;

begin
  Result := False;
  Bulge := 0;
  C := FP1; R := 0; A0 := 0; Sweep := 0;
  Pl := FD.Plane;
  Size := Max(Dist(FP2, FP1), Dist(B, FP1));
  if Size < 1E-9 then Exit;
  Tol := 1E-6 * (1 + Size);
  PlaneAxes(Pl, AU, AV);
  N := Norm3(Cross3(AU, AV));
  { A pull off the working plane onto a face holding all three points puts
    the arc on that face (a chord along a wall's base is in both planes).
    Only a face's plane: a pull snapped to some stray point stays projected
    onto the working plane. }
  if not OnPlane(B, FP1, N) then
    for F := 0 to FD.Doc.Live - 1 do
    begin
      if (FD.Doc[F].Kind <> ekFace) or (Length(FD.Doc[F].Poly) < 3) then Continue;
      FN := Norm3(FD.Doc.FaceNormal(F));
      if OnPlane(FP1, FD.Doc[F].Poly[0], FN) and OnPlane(FP2, FD.Doc[F].Poly[0], FN) and
         OnPlane(B, FD.Doc[F].Poly[0], FN) then
      begin
        if Abs(FN.Z) > 0.999 then Pl := plXY
        else if Abs(FN.Y) > 0.999 then Pl := plXZ
        else if Abs(FN.X) > 0.999 then Pl := plYZ
        else
        begin
          SetFreePlane(FP1, FN);
          Pl := plFree;
        end;
        Break;
      end;
    end;
  PlaneCoords(Pl, FP1, U1, V1);
  PlaneCoords(Pl, FP2, U2, V2);
  PlaneCoords(Pl, B, UC, VC);
  Ln := Sqrt(Sqr(U2 - U1) + Sqr(V2 - V1));
  if Ln < 1E-9 then Exit;
  { the bulge is how far the middle is pulled off the chord }
  NU := -(V2 - V1) / Ln;
  NV := (U2 - U1) / Ln;
  Bulge := (UC - (U1 + U2) / 2) * NU + (VC - (V1 + V2) / 2) * NV;
  { with Alt's lock the ends and the edge set the bulge, not the cursor; a
    typed length still wins }
  if FArcTanLock and TangentBulge(Pl, L) then Bulge := L;
  if (FInput <> '') and ParseLen(FInput, FD.Units, L) then
    Bulge := Sign(IfThen(Bulge = 0, 1, Bulge)) * L;
  if Abs(Bulge) < 1E-9 then Bulge := Ln / 8;
  Result := ArcFromChord(FP1, FP2, Bulge, Pl, C, R, A0, Sweep);
end;

{ The selection drawn where it would land, plus the line back to the grab. }
procedure TMainForm.PaintMoveGhost(C: TCanvas);
var
  I, K: Integer;
  D: TP3;
  Hi: TPointFArray;
  Lo, Hi3: TP3;
  Crate: array[0..7] of TP3;
  CS: array[0..7] of TPointF;
  PA, PB, SA, SB: TPointF;
  Lean: TP3Array;
begin
  if (FTool <> ptMove) or (FStage <> 1) then Exit;
  D := MoveDelta;

  { What comes along: corners where moving corners sit move too, so joined
    edges stretch.  Drawn first and thin, so the moved thing still reads as
    the moved thing. }
  if not (FMoveRigid or FMoveCopy or FDetachMove) and (Length(FMoveVerts) > 0) then
  begin
    FD.Doc.StretchPreview(FMoveVerts, D, FSel, Lean);
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
    C.Pen.Color := PixToColor(Pix(150, 185, 245));
    I := 0;
    while I + 1 <= High(Lean) do
    begin
      SA := ScreenOf(Lean[I]);
      SB := ScreenOf(Lean[I + 1]);
      C.MoveTo(Round(SA.X), Round(SA.Y));
      C.LineTo(Round(SB.X), Round(SB.Y));
      Inc(I, 2);
    end;
  end;

  C.Pen.Style := psSolid;
  C.Pen.Width := Max(2, Round(2 * FUIScale));
  if FMoveCopy then C.Pen.Color := PixToColor(Pix(60, 180, 110))
  else if FDetachMove then C.Pen.Color := PixToColor(Pix(235, 150, 40))
  else C.Pen.Color := PixToColor(Pix(70, 130, 240));
  { the projection is affine, so one world offset is one screen offset }
  PA := ScreenOf(P3(D.X, D.Y, D.Z));
  PB := ScreenOf(P3(0, 0, 0));
  for I := 0 to High(FSel) do
  begin
    Hi := FD.Doc.Outline(Proj, FSel[I]);
    if Length(Hi) < 2 then Continue;
    C.MoveTo(Round(Hi[0].X + PA.X - PB.X), Round(Hi[0].Y + PA.Y - PB.Y));
    for K := 1 to High(Hi) do
      C.LineTo(Round(Hi[K].X + PA.X - PB.X), Round(Hi[K].Y + PA.Y - PB.Y));
  end;
  { A built part being placed comes in its crate: its box, the floor's
    diagonals, IN, OUT and TOP, so it is set down the right way round.
    Drawn only. }
  if FMoveRigid and (Length(FMoveVerts) > 0) then
  begin
    Lo := FMoveVerts[0];
    Hi3 := FMoveVerts[0];
    for I := 1 to High(FMoveVerts) do
    begin
      Lo := P3(Min(Lo.X, FMoveVerts[I].X), Min(Lo.Y, FMoveVerts[I].Y), Min(Lo.Z, FMoveVerts[I].Z));
      Hi3 := P3(Max(Hi3.X, FMoveVerts[I].X), Max(Hi3.Y, FMoveVerts[I].Y), Max(Hi3.Z, FMoveVerts[I].Z));
    end;
    Lo := Add3(Lo, D);
    Hi3 := Add3(Hi3, D);
    Crate[0] := P3(Lo.X, Lo.Y, Lo.Z); Crate[1] := P3(Hi3.X, Lo.Y, Lo.Z);
    Crate[2] := P3(Hi3.X, Hi3.Y, Lo.Z); Crate[3] := P3(Lo.X, Hi3.Y, Lo.Z);
    for K := 0 to 3 do Crate[K + 4] := P3(Crate[K].X, Crate[K].Y, Hi3.Z);
    for K := 0 to 7 do CS[K] := ScreenOf(Crate[K]);
    C.Pen.Style := psDash;
    C.Pen.Width := 1;
    C.Pen.Color := PixToColor(Pix(150, 160, 150));
    for K := 0 to 3 do
    begin
      C.MoveTo(Round(CS[K].X), Round(CS[K].Y)); C.LineTo(Round(CS[(K + 1) mod 4].X), Round(CS[(K + 1) mod 4].Y));
      C.MoveTo(Round(CS[K + 4].X), Round(CS[K + 4].Y)); C.LineTo(Round(CS[(K + 1) mod 4 + 4].X), Round(CS[(K + 1) mod 4 + 4].Y));
      C.MoveTo(Round(CS[K].X), Round(CS[K].Y)); C.LineTo(Round(CS[K + 4].X), Round(CS[K + 4].Y));
    end;
    C.MoveTo(Round(CS[0].X), Round(CS[0].Y)); C.LineTo(Round(CS[2].X), Round(CS[2].Y));
    C.MoveTo(Round(CS[1].X), Round(CS[1].Y)); C.LineTo(Round(CS[3].X), Round(CS[3].Y));
    C.Pen.Style := psSolid;
    UIFont(C, 10, True, Pix(80, 110, 80));
    C.Brush.Style := bsClear;
    C.TextOut(Round((CS[0].X + CS[5].X) / 2) - C.TextWidth('IN') div 2, Round((CS[0].Y + CS[5].Y) / 2) - 7, 'IN');
    C.TextOut(Round((CS[3].X + CS[6].X) / 2) - C.TextWidth('OUT') div 2, Round((CS[3].Y + CS[6].Y) / 2) - 7, 'OUT');
    C.TextOut(Round((CS[4].X + CS[6].X) / 2) - C.TextWidth('TOP') div 2, Round((CS[4].Y + CS[6].Y) / 2) - 7, 'TOP');
  end;
  C.Pen.Width := 1;

  { the travel line, in the axis color when one is locked }
  PA := ScreenOf(FP1);
  PB := ScreenOf(Add3(FP1, D));
  C.Pen.Style := psDash;
  { the lock is a direction code, two per axis; the color is per axis }
  if FDirLock >= 0 then
    C.Pen.Color := PixToColor(AxisPix(FDirLock div 2))
  else
    C.Pen.Color := PixToColor(Theme.Accent);
  C.MoveTo(Round(PA.X), Round(PA.Y));
  C.LineTo(Round(PB.X), Round(PB.Y));
  C.Pen.Style := psSolid;
end;

{ The arm the angle is measured from: the reference click, else the plane's
  first axis so a typed angle means something before the second click. }
function TMainForm.RotRefDir: TP3;
var
  AU, AV, D: TP3;
  L: Double;
begin
  AxesFromNormal(FRotAxis, AU, AV);
  if FStage < 2 then Exit(AU);
  D := Sub3(FRotRef, FP1);
  { flattened into the plane, since the click may have been off it }
  L := Dot3(D, FRotAxis);
  D := P3(D.X - FRotAxis.X * L, D.Y - FRotAxis.Y * L, D.Z - FRotAxis.Z * L);
  if Dist(D, P3(0, 0, 0)) < 1E-9 then Exit(AU);
  Result := Norm3(D);
end;

{ How far round, in radians, right-handed about the axis.  Typed wins, taking
  its direction from the swing (like a typed length on a move). }
function TMainForm.RotAngle: Double;
var
  Ref, D: TP3;
  L, Deg, Snap: Double;
begin
  Ref := RotRefDir;
  D := Sub3(FCur, FP1);
  L := Dot3(D, FRotAxis);
  D := P3(D.X - FRotAxis.X * L, D.Y - FRotAxis.Y * L, D.Z - FRotAxis.Z * L);
  if (FStage < 2) or (Dist(D, P3(0, 0, 0)) < 1E-9) then
    Result := 0
  else
    Result := ArcTan2(Dot3(Cross3(Ref, D), FRotAxis), Dot3(Ref, D));
  if ParseAngle(Trim(FInput), Deg) then
  begin
    if Result < 0 then Deg := -Deg;
    Exit(DegToRad(Deg));
  end;
  { near a multiple of 15 degrees, that is what was meant }
  Snap := DegToRad(15) * Round(Result / DegToRad(15));
  if Abs(Result - Snap) < DegToRad(2.5) then Result := Snap;
end;

{ The protractor: a circle in the plane ticked every 15 degrees, the two arms,
  and the selection where it would land. }
procedure TMainForm.PaintRotateGhost(C: TCanvas);
var
  I, K: Integer;
  AU, AV, P, Q, Ref: TP3;
  Rw, Ang, A: Double;
  PA, PB: TPointF;
  W: TP3Array;
  Col: TColor;

  function OnCircle(Th, Rad: Double): TP3;
  begin
    Result := P3(FP1.X + (AU.X * Cos(Th) + AV.X * Sin(Th)) * Rad,
                 FP1.Y + (AU.Y * Cos(Th) + AV.Y * Sin(Th)) * Rad,
                 FP1.Z + (AU.Z * Cos(Th) + AV.Z * Sin(Th)) * Rad);
  end;

  procedure Seg(const A, B: TP3);
  begin
    PA := ScreenOf(A);
    PB := ScreenOf(B);
    C.MoveTo(Round(PA.X), Round(PA.Y));
    C.LineTo(Round(PB.X), Round(PB.Y));
  end;

begin
  if FStage < 1 then Exit;
  if FRotAxisIx >= 0 then Col := PixToColor(AxisPix(FRotAxisIx div 2))
  else Col := PixToColor(Pix(200, 60, 200));
  AxesFromNormal(FRotAxis, AU, AV);
  Ref := RotRefDir;
  Ang := RotAngle;

  { the dial: as big as the reference arm, never smaller than a thumb }
  Rw := 60 * FUIScale / Proj.Ppu;
  if FStage >= 2 then Rw := Max(Rw, Dist(FRotRef, FP1));
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.Pen.Color := Col;
  for K := 0 to 71 do
    Seg(OnCircle(K * Pi / 36, Rw), OnCircle((K + 1) * Pi / 36, Rw));
  { ticks are measured from the reference arm, so the 15s read as 15s }
  A := ArcTan2(Dot3(Ref, AV), Dot3(Ref, AU));
  for K := 0 to 23 do
    if K mod 6 = 0 then Seg(OnCircle(A + K * Pi / 12, Rw * 0.82), OnCircle(A + K * Pi / 12, Rw))
    else Seg(OnCircle(A + K * Pi / 12, Rw * 0.91), OnCircle(A + K * Pi / 12, Rw));

  C.Pen.Width := Max(2, Round(2 * FUIScale));
  { the reference arm, dashed }
  C.Pen.Style := psDash;
  P := P3(FP1.X + Ref.X * Rw, FP1.Y + Ref.Y * Rw, FP1.Z + Ref.Z * Rw);
  Seg(FP1, P);
  { the swung arm, solid, and the arc between them }
  if FStage >= 2 then
  begin
    C.Pen.Style := psSolid;
    Q := RotV(Ref, FRotAxis, Ang);
    Seg(FP1, P3(FP1.X + Q.X * Rw, FP1.Y + Q.Y * Rw, FP1.Z + Q.Z * Rw));
    K := Max(2, Round(Abs(Ang) / (Pi / 36)));
    for I := 0 to K - 1 do
      Seg(OnCircle(A + Ang * I / K, Rw * 0.55), OnCircle(A + Ang * (I + 1) / K, Rw * 0.55));
  end;

  { the selection, where it would come to rest }
  if (FTool = ptRotate) and (FStage >= 2) and (Abs(Ang) > 1E-9) then
  begin
    C.Pen.Style := psSolid;
    if FMoveCopy then C.Pen.Color := PixToColor(Pix(60, 180, 110))
    else if FDetachMove then C.Pen.Color := PixToColor(Pix(235, 150, 40))
    else C.Pen.Color := PixToColor(Pix(70, 130, 240));
    for I := 0 to High(FSel) do
    begin
      W := FD.Doc.OutlineWorld(FSel[I]);
      if Length(W) < 2 then Continue;
      PA := ScreenOf(RotP(W[0], FP1, FRotAxis, Ang));
      C.MoveTo(Round(PA.X), Round(PA.Y));
      for K := 1 to High(W) do
      begin
        PB := ScreenOf(RotP(W[K], FP1, FRotAxis, Ang));
        C.LineTo(Round(PB.X), Round(PB.Y));
      end;
    end;
  end;
  C.Pen.Width := 1;
  C.Pen.Style := psSolid;
end;

function TMainForm.IsDoomed(I: Integer): Boolean;
var
  K: Integer;
begin
  Result := True;
  for K := 0 to High(FDoomed) do
    if FDoomed[K] = I then Exit;
  Result := False;
end;

{ What the right button is asking about.  Edges reach only 4 px here, not 9
  as in PickAt: on a cylinder every point is within 9 px of an edge, so its
  faces could not be reached from the menu. }
function TMainForm.PickForMenu(SX, SY: Integer): Integer;
var
  E, F: Integer;
begin
  Result := FD.Doc.HitNote(SX, SY);
  if Result >= 0 then Exit;
  E := FD.Doc.HitEdge(Proj, SX, SY, 4 * FUIScale, HIT_NO_GUIDES);
  if E >= 0 then Exit(E);
  F := FD.Doc.HitFace(Proj, SX, SY);
  if F >= 0 then Exit(F);
  Result := FD.Doc.HitTest(Proj, SX, SY, 9 * FUIScale, False);
end;

{ --- groups ---
  SketchUp's rules: a click takes the whole
  group; double-click opens it and the rest fades and cannot be picked; a
  click on nothing or Esc leaves; a locked group can be picked and snapped
  to but not moved, edited or exploded. }

{ every distinct group in the selection, by the entity you would click }
function TMainForm.SelectedGroups: TIntArrayW;
var
  K, T, J, N: Integer;
  Known: Boolean;
begin
  Result := nil;
  N := 0;
  for K := 0 to High(FSel) do
  begin
    T := FD.Doc.TopPartIn(FSel[K]);
    if T <= 0 then Continue;
    Known := False;
    for J := 0 to N - 1 do
      if Result[J] = T then Known := True;
    if Known then Continue;
    if N >= Length(Result) then SetLength(Result, Max(4, N * 2));
    Result[N] := T;
    Inc(N);
  end;
  SetLength(Result, N);
end;

{ the one group the selection is, or 0 for several, loose things, or a mix }
function TMainForm.SoleGroup: Integer;
var
  Gs: TIntArrayW;
  K: Integer;
begin
  Result := 0;
  Gs := SelectedGroups;
  if Length(Gs) <> 1 then Exit;
  for K := 0 to High(FSel) do
    if FD.Doc.TopPartIn(FSel[K]) <> Gs[0] then Exit;
  Result := Gs[0];
end;

procedure TMainForm.MakeGroup;
var
  Id, K, T, I, J, First: Integer;
  Sel: TIntArrayW;
begin
  if Length(FSel) = 0 then
  begin
    FCmdMsg := 'Pick something first - a group is made of what is selected.';
    InvalidateStatus;
    Exit;
  end;
  for K := 0 to High(FSel) do
  begin
    T := FD.Doc.TopPartIn(FSel[K]);
    if (T > 0) and FD.Doc.PartLockedUp(T) then
    begin
      FCmdMsg := Format('"%s" is locked - unlock it before grouping it with anything.',
        [FD.Doc.PartName(T)]);
      InvalidateStatus;
      Exit;
    end;
  end;
  PushUndo;
  SetLength(Sel, Length(FSel));
  for K := 0 to High(FSel) do Sel[K] := FSel[K];
  Id := FD.Doc.NewPart('', FD.Doc.Context);
  First := -1;
  for K := 0 to High(Sel) do
  begin
    I := Sel[K];
    if (I < 0) or (I >= FD.Doc.Live) or (FD.Doc[I].Kind = ekPart) then Continue;
    T := FD.Doc.TopPartIn(I);
    { a picked group goes in whole and stays a group inside the new one }
    if T > 0 then FD.Doc.SetPartParent(T, Id)
    else if T = 0 then
    begin
      FD.Doc.SetPart(I, Id);
      { a face is rebuilt from its edges, so its edges come into the group
        too (as SketchUp's Make Group does), or the face is found loose again
        and the group left empty }
      if FD.Doc[I].Kind = ekFace then
        for J := 0 to FD.Doc.Live - 1 do
          if (FD.Doc[J].Kind in [ekLine, ekArc]) and (FD.Doc[J].Part = FD.Doc.Context) and
             EntHasPoint(I, FD.Doc[J].A) and EntHasPoint(I, FD.Doc[J].B) then
            FD.Doc.SetPart(J, Id);
    end;
    if First < 0 then First := I;
  end;
  SetLength(FSel, 0);
  if First >= 0 then SelectAdd(First);
  { rebuild the faces group by group, which separates them from what was
    joined outside }
  RebuildFlatFaces;
  RenderInk;
  RecomposeAll;
  InfoChanged;
  FCmdMsg := Format('Grouped as "%s".  Double-click it to work inside it; ' +
    '/name calls it something.', [FD.Doc.PartName(Id)]);
  InvalidateStatus;
  pbScreen.Invalidate;
end;

procedure TMainForm.ExplodeGroups;
var
  Gs: TIntArrayW;
  Doom: array of Boolean;
  K, G, Up, I, N: Integer;
begin
  Gs := SelectedGroups;
  if Length(Gs) = 0 then
  begin
    FCmdMsg := 'Pick a group first.';
    InvalidateStatus;
    Exit;
  end;
  for K := 0 to High(Gs) do
    if FD.Doc.PartLockedUp(Gs[K]) then
    begin
      FCmdMsg := Format('"%s" is locked - unlock it first.', [FD.Doc.PartName(Gs[K])]);
      InvalidateStatus;
      Exit;
    end;
  PushUndo;
  SetLength(Doom, FD.Doc.Live);
  for I := 0 to High(Doom) do Doom[I] := False;
  N := 0;
  for K := 0 to High(Gs) do
  begin
    G := Gs[K];
    Up := FD.Doc.PartParent(G);
    for I := 0 to FD.Doc.Live - 1 do
    begin
      if (FD.Doc[I].Kind = ekPart) and (FD.Doc[I].Grp = G) then Doom[I] := True
      else if FD.Doc[I].Part = G then
      begin
        { members go up a level; a group inside stays a group }
        if FD.Doc[I].Kind = ekPart then FD.Doc.SetPartParent(FD.Doc[I].Grp, Up)
        else FD.Doc.SetPart(I, Up);
        Inc(N);
      end;
    end;
  end;
  FD.Doc.DeleteMarked(Doom);
  SetLength(FSel, 0);
  RebuildFlatFaces;
  RenderInk;
  RecomposeAll;
  InfoChanged;
  if Length(Gs) = 1 then
    FCmdMsg := Format('Group taken apart - %d things are loose again.', [N])
  else
    FCmdMsg := Format('%d groups taken apart.', [Length(Gs)]);
  InvalidateStatus;
  pbScreen.Invalidate;
end;

procedure TMainForm.OpenGroup(Id: Integer);
begin
  if Id <= 0 then Exit;
  if FD.Doc.PartLockedUp(Id) then
  begin
    FCmdMsg := Format('"%s" is locked - unlock it to work inside it.', [FD.Doc.PartName(Id)]);
    InvalidateStatus;
    Exit;
  end;
  SetLength(FSel, 0);
  FD.Doc.Context := Id;
  FShotOK := False;
  RenderInk;
  RecomposeAll;
  InfoChanged;
  FCmdMsg := Format('Inside "%s".  What you draw now belongs to it; ' +
    'Esc or a click on nothing leaves it.', [FD.Doc.PartName(Id)]);
  InvalidateStatus;
  pbScreen.Invalidate;
end;

procedure TMainForm.CloseGroup;
var
  Was: Integer;
begin
  if FD.Doc.Context = 0 then Exit;
  Was := FD.Doc.Context;
  SetLength(FSel, 0);
  FD.Doc.Context := FD.Doc.PartParent(Was);
  FShotOK := False;
  RenderInk;
  RecomposeAll;
  InfoChanged;
  if FD.Doc.Context = 0 then FCmdMsg := Format('Left "%s".', [FD.Doc.PartName(Was)])
  else FCmdMsg := Format('Left "%s" - inside "%s" now.',
    [FD.Doc.PartName(Was), FD.Doc.PartName(FD.Doc.Context)]);
  InvalidateStatus;
  pbScreen.Invalidate;
end;

procedure TMainForm.LockGroups(Locked: Boolean);
var
  Gs: TIntArrayW;
  K: Integer;
begin
  Gs := SelectedGroups;
  if Length(Gs) = 0 then
  begin
    FCmdMsg := 'Pick a group first.';
    InvalidateStatus;
    Exit;
  end;
  PushUndo;
  for K := 0 to High(Gs) do FD.Doc.SetPartLocked(Gs[K], Locked);
  InfoChanged;
  if Locked then
    FCmdMsg := 'Locked.  It can still be snapped to, and picked - but not moved, ' +
      'changed or opened until it is unlocked.'
  else
    FCmdMsg := 'Unlocked.';
  InvalidateStatus;
  pbScreen.Invalidate;
end;

{ Put groups away or bring them back.  Named: every group whose name
  contains it ("/hide labels").  Unnamed: hide takes the picked groups, show
  brings back everything.  Nothing is lost; only drawing, picking and
  snapping change. }
procedure TMainForm.HideGroups(PutAway: Boolean; const Named: string);
var
  Gs: TIntArrayW;
  I, K, N: Integer;
  Want: string;
begin
  SetLength(Gs, 0);
  Want := LowerCase(Trim(Named));
  for I := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[I].Kind = ekPart) and (FD.Doc[I].Hidden <> PutAway) and
       (((Want <> '') and (Pos(Want, LowerCase(FD.Doc.PartName(FD.Doc[I].Grp))) > 0)) or
        ((Want = '') and not PutAway)) then
    begin
      SetLength(Gs, Length(Gs) + 1); Gs[High(Gs)] := FD.Doc[I].Grp;
    end;
  if (Want = '') and PutAway then Gs := SelectedGroups;
  if Length(Gs) = 0 then
  begin
    if Want <> '' then
      FCmdMsg := Format('No group %s has "%s" in its name.', [IfThen(PutAway, 'showing', 'put away'), Trim(Named)])
    else if PutAway then FCmdMsg := 'Pick a group first - or /hide labels puts away every group named so.'
    else FCmdMsg := 'Nothing is put away.';
    InvalidateStatus;
    Exit;
  end;
  PushUndo;
  N := 0;
  for K := 0 to High(Gs) do
    if FD.Doc.PartHidden(Gs[K]) <> PutAway then
    begin
      FD.Doc.SetPartHidden(Gs[K], PutAway);
      Inc(N);
    end;
  { what is put away cannot stay picked }
  if PutAway then SetLength(FSel, 0);
  RenderInk;
  RecomposeAll;
  InfoChanged;
  if PutAway then
    FCmdMsg := Format('%d group%s put away - /show brings %s back.', [N, IfThen(N = 1, '', 's'),
      IfThen(N = 1, 'it', 'them')])
  else
    FCmdMsg := Format('%d group%s brought back.', [N, IfThen(N = 1, '', 's')]);
  InvalidateStatus;
  pbScreen.Invalidate;
end;

procedure TMainForm.RenameGroup(const NewName: string);
var
  G: Integer;
begin
  G := SoleGroup;
  if G = 0 then
  begin
    FCmdMsg := 'Pick one group, then /name what to call it.';
    InvalidateStatus;
    Exit;
  end;
  if Trim(NewName) = '' then
  begin
    FCmdMsg := Format('It is called "%s".  /name Left knob calls it that.', [FD.Doc.PartName(G)]);
    InvalidateStatus;
    Exit;
  end;
  PushUndo;
  FD.Doc.SetPartName(G, Trim(NewName));
  InfoChanged;
  FCmdMsg := Format('Called "%s".', [FD.Doc.PartName(G)]);
  InvalidateStatus;
end;

{ What a move or turn takes hold of.  Whole groups go rigidly and do not
  stretch loose things touching them; loose picked things move with their
  corners as usual.  A locked group stays put. }
function TMainForm.SplitMoveSelection: Boolean;
var
  Gs, M, Loose: TIntArrayW;
  K, J, I, N, NL, Skipped: Integer;
begin
  Result := True;
  SetLength(FMoveGroupEnts, 0);
  N := 0;
  Skipped := 0;
  Gs := SelectedGroups;
  for K := 0 to High(Gs) do
  begin
    if FD.Doc.PartLockedUp(Gs[K]) then begin Inc(Skipped); Continue; end;
    M := FD.Doc.PartMembers(Gs[K], True);
    SetLength(FMoveGroupEnts, N + Length(M));
    for J := 0 to High(M) do FMoveGroupEnts[N + J] := M[J];
    N := N + Length(M);
  end;
  Loose := nil;
  NL := 0;
  for K := 0 to High(FSel) do
  begin
    I := FSel[K];
    if (I < 0) or (I >= FD.Doc.Live) or (FD.Doc[I].Kind = ekPart) then Continue;
    if FD.Doc.TopPartIn(I) <> 0 then Continue;
    if NL >= Length(Loose) then SetLength(Loose, Max(16, NL * 2));
    Loose[NL] := I;
    Inc(NL);
  end;
  SetLength(Loose, NL);
  FD.Doc.VertsOf(Loose, FMoveVerts);
  { nothing movable at all: say so rather than report a move of nothing }
  if (Skipped > 0) and (N = 0) and (NL = 0) then
  begin
    FCmdMsg := 'That group is locked - unlock it to move it.';
    Result := False;
  end
  else if Skipped > 0 then
    FCmdMsg := 'A locked group stays where it is - unlock it to move it.';
end;

{ A face a tool may act on: one in the open context.  As in SketchUp, a
  closed group's face is not pushed from outside.  Drawing ON it goes
  through FaceUnder, which is not filtered. }
function TMainForm.InContextFace(F: Integer): Integer;
begin
  Result := F;
  if (F >= 0) and (FD.Doc.TopPartIn(F) <> 0) then Result := -1;
end;

{ The box round a group, as SketchUp draws one: the twelve edges of its
  bounds.  Shift offsets it, for a ghost. }
procedure TMainForm.PaintPartBox(C: TCanvas; Id: Integer; const Col: TPix;
  Dashed: Boolean; const Shift: TP3);
const
  E: array[0..11, 0..1] of Integer = ((0, 1), (1, 2), (2, 3), (3, 0),
    (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7));
var
  Lo, Hi: TP3;
  P: array[0..7] of TPointF;
  K: Integer;
begin
  if not FD.Doc.PartBounds(Id, Lo, Hi) then Exit;
  Lo := Add3(Lo, Shift);
  Hi := Add3(Hi, Shift);
  P[0] := ScreenOf(P3(Lo.X, Lo.Y, Lo.Z)); P[1] := ScreenOf(P3(Hi.X, Lo.Y, Lo.Z));
  P[2] := ScreenOf(P3(Hi.X, Hi.Y, Lo.Z)); P[3] := ScreenOf(P3(Lo.X, Hi.Y, Lo.Z));
  P[4] := ScreenOf(P3(Lo.X, Lo.Y, Hi.Z)); P[5] := ScreenOf(P3(Hi.X, Lo.Y, Hi.Z));
  P[6] := ScreenOf(P3(Hi.X, Hi.Y, Hi.Z)); P[7] := ScreenOf(P3(Lo.X, Hi.Y, Hi.Z));
  C.Brush.Style := bsClear;
  if Dashed then C.Pen.Style := psDash else C.Pen.Style := psSolid;
  C.Pen.Width := Max(1, Round(FUIScale));
  C.Pen.Color := PixToColor(Col);
  for K := 0 to 11 do
  begin
    C.MoveTo(Round(P[E[K, 0]].X), Round(P[E[K, 0]].Y));
    C.LineTo(Round(P[E[K, 1]].X), Round(P[E[K, 1]].Y));
  end;
  C.Pen.Style := psSolid;
end;

{ What move and rotate take hold of when nothing is picked: a note, an
  edge, a face, anything else - never a guide (a guide is laid anew, not
  moved). }
function TMainForm.PickToGrab(SX, SY: Integer): Integer;
begin
  Result := FD.Doc.HitNote(SX, SY);
  if Result < 0 then
    Result := FD.Doc.HitEdge(Proj, SX, SY, 9 * FUIScale, HIT_NO_GUIDES);
  if Result < 0 then Result := FD.Doc.HitFace(Proj, SX, SY);
  if Result < 0 then Result := FD.Doc.HitTest(Proj, SX, SY, 9 * FUIScale, False);
  if (Result >= 0) and (FD.Doc.TopPartIn(Result) < 0) then Result := -1;
end;

{ What a click takes, with the group rules on top.  Inside an open group the
  rest of the drawing cannot be picked; that click closes the group (see
  FinishSelect). }
function TMainForm.PickAt(SX, SY: Integer): Integer;
begin
  Result := PickAtRaw(SX, SY);
  if (Result >= 0) and (FD.Doc.TopPartIn(Result) < 0) then Result := -1;
end;

function TMainForm.PickAtRaw(SX, SY: Integer): Integer;
begin
  { a note is drawn on top, so it is picked first }
  Result := FD.Doc.HitNote(SX, SY);
  if Result >= 0 then Exit;
  { Then an edge, then the face behind, then anything else, stopping at the
    first answer (HitFace is the costly one).  Never a guide: guides belong
    to the measure tool, and a guide point usually sits on a line. }
  Result := FD.Doc.HitEdge(Proj, SX, SY, 9 * FUIScale, HIT_NO_GUIDES);
  if Result >= 0 then Exit;
  Result := FD.Doc.HitFace(Proj, SX, SY);
  if Result >= 0 then Exit;
  Result := FD.Doc.HitTest(Proj, SX, SY, 9 * FUIScale, False);
end;

{ add whatever is under the cursor to the eraser's gathered list }
procedure TMainForm.DoomAt(SX, SY: Integer);
var
  I, T, K: Integer;
  M: TIntArrayW;
begin
  { softening is about edges only (a face has no crease), so a soften stroke
    only looks for edges }
  if FEraseMode <> 0 then
  begin
    I := FD.Doc.HitEdge(Proj, SX, SY, 9 * FUIScale);
    if I < 0 then Exit;
    if IsDoomed(I) then Exit;
    if FD.Doc.TopPartIn(I) <> 0 then Exit;    { softening stays in the open group }
    if not (FD.Doc[I].Kind in [ekLine, ekArc]) then Exit;
    SetLength(FDoomed, Length(FDoomed) + 1);
    FDoomed[High(FDoomed)] := I;
    FScreenDirty := True;
    Exit;
  end;
  { The eraser takes edges, and faces only by taking their edges, as in
    SketchUp ("faces are erased when you erase their bounding edges").  A
    click on a bare face says so and points to right-click or Delete. }
  { the note first: it is drawn on top, so it is what the cursor is on }
  I := FD.Doc.HitNote(SX, SY);
  { never a guide: the eraser leaves them to the measure tool }
  if I < 0 then I := FD.Doc.HitEdge(Proj, SX, SY, 9 * FUIScale, HIT_NO_GUIDES);
  if I < 0 then I := FD.Doc.HitTest(Proj, SX, SY, 9 * FUIScale, False);
  if I < 0 then
  begin
    if FD.Doc.HitFace(Proj, SX, SY) >= 0 then
      FCmdMsg := 'The eraser takes edges - rub out the edges round a face ' +
        'and the face goes with them.  For the face on its own: right-click ' +
        'it, or pick it and press Delete.';
    Exit;
  end;
  { a group is erased whole, as SketchUp's eraser takes an object; a locked
    one not at all, and nothing outside the open group }
  T := FD.Doc.TopPartIn(I);
  if T < 0 then Exit;
  if T > 0 then
  begin
    if FD.Doc.PartLockedUp(T) then
    begin
      FCmdMsg := Format('"%s" is locked.', [FD.Doc.PartName(T)]);
      Exit;
    end;
    M := FD.Doc.PartMembers(T, True);
    for K := 0 to High(M) do
      if not IsDoomed(M[K]) then
      begin
        SetLength(FDoomed, Length(FDoomed) + 1);
        FDoomed[High(FDoomed)] := M[K];
      end;
    FScreenDirty := True;
    Exit;
  end;
  if IsDoomed(I) then Exit;
  SetLength(FDoomed, Length(FDoomed) + 1);
  FDoomed[High(FDoomed)] := I;
  FScreenDirty := True;
end;

{ 0 erases, 1 softens (Ctrl), 2 unsoftens (Ctrl+Shift) }
function TMainForm.EraseModeOf(Shift: TShiftState): Integer;
begin
  if not (ssCtrl in Shift) then Result := 0
  else if ssShift in Shift then Result := 2
  else Result := 1;
end;

{ Soften what the eraser gathered instead of erasing it.  Only lines and
  arcs; faces under the stroke are skipped rather than spoiling it. }
procedure TMainForm.SoftenDoomed(On_: Boolean);
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to High(FDoomed) do
    if (FDoomed[I] >= 0) and (FDoomed[I] < FD.Doc.Live) and
       (FD.Doc[FDoomed[I]].Kind in [ekLine, ekArc]) and
       (FD.Doc[FDoomed[I]].Soft <> On_) then
    begin
      if N = 0 then PushUndo;
      FD.Doc.SetSoft(FDoomed[I], On_);
      Inc(N);
    end;
  SetLength(FDoomed, 0);
  if N = 0 then
    FCmdMsg := specialize IfThen<string>(On_,
      'Nothing there to soften.', 'Nothing there was softened.')
  else
  begin
    FCmdMsg := Format('%d %s %s.', [N,
      specialize IfThen<string>(N = 1, 'edge', 'edges'),
      specialize IfThen<string>(On_, 'softened', 'brought back')]);
    RenderInk;
    RecomposeAll;
  end;
  FScreenDirty := True;
end;

{ Delete everything gathered, then let the face rebuild join or drop areas. }
procedure TMainForm.BurnDoomed;
var
  I, J, T, N: Integer;
  EA, EB: array of TP3;
  Kinds: array of TEntKind;
  Held: TIntArrayW;
  Gone: array of Boolean;
begin
  N := Length(FDoomed);
  if N = 0 then Exit;
  for I := 0 to N - 2 do
    for J := 0 to N - 2 - I do
      if FDoomed[J] < FDoomed[J + 1] then
      begin
        T := FDoomed[J];
        FDoomed[J] := FDoomed[J + 1];
        FDoomed[J + 1] := T;
      end;

  SetLength(EA, N);
  SetLength(EB, N);
  SetLength(Kinds, N);
  for I := 0 to N - 1 do
  begin
    EA[I] := FD.Doc[FDoomed[I]].A;
    EB[I] := FD.Doc[FDoomed[I]].B;
    Kinds[I] := FD.Doc[FDoomed[I]].Kind;
  end;

  PushUndo;
  J := FaceCount;
  { The faces these edges held up go too.  Loose faces are rebuilt anyway,
    but a solid's faces are kept as made, so they must be removed here or a
    box keeps its sides with an edge missing. }
  FD.Doc.FacesOnEdges(FDoomed, Held);
  SetLength(Gone, FD.Doc.Live);
  for I := 0 to High(Gone) do Gone[I] := False;
  for I := 0 to N - 1 do Gone[FDoomed[I]] := True;
  for I := 0 to High(Held) do Gone[Held[I]] := True;
  { and a guide line takes the point laid with it }
  FD.Doc.PointsOnGuides(FDoomed, Held);
  for I := 0 to High(Held) do Gone[Held[I]] := True;
  FD.Doc.DeleteMarked(Gone);
  { faces joining where a line went, or vanishing because the outline no
    longer closes, both come out of rebuilding from what is left }
  J := J - RebuildFlatFaces;

  if N = 1 then FCmdMsg := 'Deleted.'
  else FCmdMsg := Format('Deleted %d things.', [N]);
  if J > 0 then
    FCmdMsg := FCmdMsg + Format('  %d face%s gone with them.',
      [J, IfThen(J = 1, '', 's')]);
  SetLength(FDoomed, 0);
  SelectNone;
  RenderInk;
  RecomposeAll;
end;

{ What the tape is set to leave, in words, said after a measurement and in
  the hint line so the mode never has to be remembered. }
function TMainForm.TapeDropSays: string;
begin
  case FTapeDrop of
    1: Result := 'a point where it landed - Ctrl for the dashed line too';
    2: Result := 'a guide across the run - Ctrl for the point too';
    3: Result := 'nothing left behind - Ctrl to leave a guide again';
  else
    Result := 'guide across the run, and a point where it landed - Ctrl changes it';
  end;
end;

{ What the tape leaves behind, chosen by the mode (as in SketchUp) rather
  than by what was under the first click.  A guide line runs parallel to the
  edge the measurement started on (a wall thickness, a row of hangers); from
  no edge it runs across the measured run. }
procedure TMainForm.LayGuide;
var
  D, E, Nm, AU, AV: TP3;
  Have: Boolean;
  Kind: TTapeGuide;
begin
  if Dist(FP1, FP2) < 1E-9 then Exit;
  PushUndo;

  { Default is both: the dashed line says where the offset is, the point
    where along it the measurement landed.  Ctrl cycles the choice (as in
    SketchUp), e.g. for a short mark that should not drag a line across the
    whole drawing. }
  if FTapeDrop = 3 then
  begin
    FCmdMsg := RunReading(FP1, FP2) + '   (nothing left behind)';
    Exit;
  end;

  { what it leaves depends on where it was pulled from (see TapeGuide in
    hsDrawing): off an edge, a line parallel to it; along an edge, a point
    only; anywhere else, a line across the run }
  PlaneAxes(FD.Plane, AU, AV);
  Nm := Cross3(AU, AV);
  Have := (FMeasEdge >= 0) and (FMeasEdge < FD.Doc.Live) and
          (FD.Doc[FMeasEdge].Kind = ekLine);
  if Have then
    E := Sub3(FD.Doc[FMeasEdge].B, FD.Doc[FMeasEdge].A)
  else
    E := P3(0, 0, 0);
  Kind := TapeGuide(Have, E, FP1, FP2, Nm, D);
  { at a corner the click may have found the other edge, so ask every edge
    through the start }
  if (Kind <> tgPointOnly) and FD.Doc.RunsAlongEdge(FP1, FP2) then
    Kind := tgPointOnly;

  { a line unless the run was along its starting edge, except in line-only
    mode }
  if (FTapeDrop <> 1) and ((Kind <> tgPointOnly) or (FTapeDrop = 2)) and
     (Sqr(D.X) + Sqr(D.Y) + Sqr(D.Z) > 1E-18) then
    FD.Doc.AddGuide(FP2, Add3(FP2, D));
  if FTapeDrop <> 2 then FD.Doc.AddGuide(FP2, FP2);

  if (Kind = tgPointOnly) and (FTapeDrop <> 2) then
    FCmdMsg := FormatLen(Dist(FP1, FP2), FD.Units) +
      '   a point where it landed - measured along the edge, so no line with it'
  else if Kind = tgAlongEdge then
    FCmdMsg := FormatLen(Dist(FP1, FP2), FD.Units) +
      '   a guide parallel to the edge it came off  -  ' + TapeDropSays
  else
    FCmdMsg := FormatLen(Dist(FP1, FP2), FD.Units) + '   ' + TapeDropSays;
  RenderInk;
  RecomposeAll;
end;

{ Every drawn edge in group Part as plain segments for the region finder. }
function TMainForm.EdgeSegments(Part: Integer): TSegArray;
var
  I, K, N, Steps: Integer;
  A: TP3;
begin
  N := 0;
  SetLength(Result, 64);
  for I := 0 to FD.Doc.Live - 1 do
  begin
    { one group at a time (see Part in hsDrawing) }
    if FD.Doc[I].Part <> Part then Continue;
    { A solid's own edges go in too: the top of a wall is the fourth side of
      a roof slope drawn on a box.  A region that lands exactly on an
      existing solid face is dropped later as a duplicate. }
    case FD.Doc[I].Kind of
      ekLine:
        { a reference line (a dimension's, a radiant run) closes no face,
          as in hsDrawing's edge passes }
        if not FD.Doc[I].Dim then
        begin
          if N >= Length(Result) then SetLength(Result, N * 2);
          Result[N].A := FD.Doc[I].A;
          Result[N].B := FD.Doc[I].B;
          Inc(N);
        end;
      ekArc:
        begin
          A := ArcPoint(FD.Doc[I].C, FD.Doc[I].R, FD.Doc[I].A0, FD.Doc[I].Plane, FD.Doc[I].Nm);
          Steps := ArcSteps(FD.Doc[I]);
          for K := 1 to Steps do
          begin
            if N >= Length(Result) then SetLength(Result, N * 2);
            Result[N].A := A;
            A := ArcPoint(FD.Doc[I].C, FD.Doc[I].R,
              FD.Doc[I].A0 + FD.Doc[I].Sweep * K / Steps, FD.Doc[I].Plane, FD.Doc[I].Nm);
            Result[N].B := A;
            Inc(N);
          end;
        end;
    end;
  end;
  SetLength(Result, N);
end;

{ flat faces belonging to solids }
function TMainForm.SolidFaceCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[I].Kind = ekFace) and FD.Doc[I].Solid then Inc(Result);
end;

{ Whether the drawing has any face at all, solids included.  FaceCount
  leaves solids out; a drawing that is only a built duct still has faces. }
function TMainForm.AnyFace: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to FD.Doc.Live - 1 do
    if FD.Doc[I].Kind = ekFace then Exit(True);
end;

{ how many loose flat faces there are, for saying what an edit changed }
function TMainForm.FaceCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[I].Kind = ekFace) and not FD.Doc[I].Solid then Inc(Result);
end;

{ a flat area boiled down to something that can be matched next time }
function RegionSig(const R: TRegion): TRegionSig;
var
  K, N: Integer;
begin
  { one of the two normals, chosen the same way every time (see
    hsFaceFinder), so a loop wound the other way matches }
  Result.Nm := CanonicalNormal(R.Normal);
  N := Length(R.Outer);
  Result.Mid := P3(0, 0, 0);
  for K := 0 to N - 1 do
    Result.Mid := Add3(Result.Mid, R.Outer[K]);
  if N > 0 then
    Result.Mid := P3(Result.Mid.X / N, Result.Mid.Y / N, Result.Mid.Z / N);
  Result.D := Dot3(Result.Mid, Result.Nm);
  Result.Area := Abs(LoopArea(R.Outer, R.Normal));
end;

function SameRegion(const A, B: TRegionSig): Boolean;
begin
  Result := (A.Part = B.Part) and (Abs(A.Nm.X - B.Nm.X) < 1E-6) and (Abs(A.Nm.Y - B.Nm.Y) < 1E-6) and
            (Abs(A.Nm.Z - B.Nm.Z) < 1E-6) and (Abs(A.D - B.D) < 1E-4) and
            (Abs(A.Area - B.Area) < 1E-3) and (Dist(A.Mid, B.Mid) < 1E-4);
end;

{ The flat areas as they stand, recorded as seen without acting on them.
  For a file that already carries its faces: nothing counts as newly closed,
  so no face is invented over what was saved or what was erased. }
procedure TMainForm.SeedRegions;
var
  R: TRegionArray;
  Parts: TIntArrayW;
  I, P, Base, CI: Integer;
begin
  SetLength(FD.Seen, 0);
  Parts := AllPartIds;
  for P := 0 to High(Parts) do
  begin
    { the slot first, on its own: taking the element and growing the array
      in one expression let the address be computed before the growth }
    CI := CacheFor(Parts[P]);
    R := BuildRegionsCached(EdgeSegments(Parts[P]), FRegionCaches[CI].Cache);
    Base := Length(FD.Seen);
    SetLength(FD.Seen, Base + Length(R));
    for I := 0 to High(R) do
    begin
      if ((I and 63) = 0) and (Length(R) > 500) then
        if not OnProgress('Working out the faces', I / Length(R)) then Break;
      FD.Seen[Base + I] := RegionSig(R[I]);
      FD.Seen[Base + I].Part := Parts[P];
    end;
  end;
end;

{ Every group's id, with 0 (the drawing itself) first.  Each is rebuilt on
  its own; that is what makes a group a group. }
function TMainForm.AllPartIds: TIntArrayW;
var
  I, N: Integer;
begin
  SetLength(Result, 1);
  Result[0] := 0;
  N := 1;
  for I := 0 to FD.Doc.Live - 1 do
    if FD.Doc[I].Kind = ekPart then
    begin
      if N >= Length(Result) then SetLength(Result, N * 2);
      Result[N] := FD.Doc[I].Grp;
      Inc(N);
    end;
  SetLength(Result, N);
end;

{ this group's region cache slot, made if it has none yet }
function TMainForm.CacheFor(Part: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FRegionCaches) do
    if FRegionCaches[I].Part = Part then Exit(I);
  SetLength(FRegionCaches, Length(FRegionCaches) + 1);
  Result := High(FRegionCaches);
  FRegionCaches[Result].Part := Part;
  FRegionCaches[Result].Cache.Keys := nil;
  FRegionCaches[Result].Cache.Sig := nil;
  FRegionCaches[Result].Cache.Found := nil;
end;

{ Work the loose faces out again from the edges: one question after every
  edit, what areas do these edges enclose, instead of a rule per situation.
  Solid faces are kept (a solid keeps its own topology).  A new face takes
  the color and paint of whichever old face its middle fell inside. }
function TMainForm.RebuildFlatFaces: Integer;
type
  TWas = record
    Mid: TP3;
    Poly: TP3Array;
    Holes: array of TP3Array;
    Nm: TP3;
    Ink: TColor;
    Part: Integer;
    { the paint carries across too, or a rebuild resets painted faces }
    Mat: TColor;
    MatSet: Boolean;
  end;
var
  R: TRegionArray;
  Was: array of TWas;
  WasHit: Integer;
  NWas, I, J, K, M, G, Made, DupAt: Integer;
  RegArea, FArea, PiecesArea: Double;
  FN: TP3;
  Pieces: array of Integer;
  Shares: Boolean;
  Mid, Other: TP3;
  Ink: TColor;
  Dup, HadFace, Known: Boolean;
  Sig: TRegionSig;
  HealGrp: Integer;
  SolidIx: TIntArrayW;
  SolidN, SolidP0, SolidMid, RMid: array of TP3;
  SolidRad: array of Double;
  RMidOK: array of Boolean;
  FE: TWorkEnt;
  FLo, FHi: TP3;
  SolidArea: array of Double;
  SI: Integer;
  LineIx, PlaneIx, RegionIx: TFPHashList;
  LineLists, PlaneLists, RegionLists, WasLists, SeenLists: array of TIntArrayW;
  WasIx, SeenIx: TFPHashList;
  WasOn, SeenOn: TIntArrayW;
  Doomed: array of Boolean;
  Acc: array[0..5] of QWord;
  TL: QWord;
  Cands, RCands: TIntArrayW;
  CI, RC: Integer;
  Tk: QWord;
  { which group each area was found in, side by side with R }
  RPart, Parts: TIntArrayW;
  RP: TRegionArray;
  PP, RBase, CurPart: Integer;

  { is P on the segment AB, within a hair }
  function OnSegment(const P, A, B: TP3): Boolean;
  var
    L, T: Double;
    Q: TP3;
  begin
    L := Dist(A, B);
    if L < 1E-9 then Exit(Dist(P, A) < 1E-6);
    T := ((P.X - A.X) * (B.X - A.X) + (P.Y - A.Y) * (B.Y - A.Y) + (P.Z - A.Z) * (B.Z - A.Z)) / (L * L);
    if (T < -1E-6) or (T > 1 + 1E-6) then Exit(False);
    Q := P3(A.X + (B.X - A.X) * T, A.Y + (B.Y - A.Y) * T, A.Z + (B.Z - A.Z) * T);
    Result := Dist(P, Q) < 1E-6;
  end;

  { an end, and the group it is in: a solid's line in another group is not
    an edge of anything found in this one }
  function EndKey(const P: TP3; Part: Integer): shortstring;
  var
    Q: array[0..3] of Int64;
  begin
    Q[0] := Round(P.X * 1E6); Q[1] := Round(P.Y * 1E6); Q[2] := Round(P.Z * 1E6);
    Q[3] := Part;
    SetLength(Result, 32);
    Move(Q[0], Result[1], 32);
  end;

  procedure NoteLine(const P: TP3; L: Integer);
  var
    Ix: Integer;
  begin
    Ix := LineIx.FindIndexOf(EndKey(P, FD.Doc[L].Part));
    if Ix < 0 then
    begin
      SetLength(LineLists, Length(LineLists) + 1);
      Ix := High(LineLists);
      LineIx.Add(EndKey(P, FD.Doc[L].Part), Pointer(PtrInt(Ix + 1)));
    end
    else
      Ix := PtrInt(LineIx.Items[Ix]) - 1;
    SetLength(LineLists[Ix], Length(LineLists[Ix]) + 1);
    LineLists[Ix][High(LineLists[Ix])] := L;
  end;

  { the solid line, if any, that runs along P-Q, found by either end (an
    opening's edges are whole lines of the solid) }
  function GroupLineAlong(const P, Q: TP3): Integer;
  var
    Pass, Ix, K, L: Integer;
    Key: shortstring;
  begin
    Result := -1;
    for Pass := 0 to 1 do
    begin
      if Pass = 0 then Key := EndKey(P, CurPart) else Key := EndKey(Q, CurPart);
      Ix := LineIx.FindIndexOf(Key);
      if Ix < 0 then Continue;
      Ix := PtrInt(LineIx.Items[Ix]) - 1;
      for K := 0 to High(LineLists[Ix]) do
      begin
        L := LineLists[Ix][K];
        if OnSegment(P, FD.Doc[L].A, FD.Doc[L].B) and OnSegment(Q, FD.Doc[L].A, FD.Doc[L].B) then
          Exit(L);
      end;
    end;
  end;

  { a plane as a key: normal pointed one way, normal and offset rounded
    coarsely so faces on one plane share a key.  The fine test still runs on
    what comes back. }
  function PlaneKey(const N, P: TP3; Part: Integer): shortstring;
  var
    Nm: TP3;
    Q: array[0..4] of Int64;
  begin
    Nm := CanonicalNormal(N);
    Q[0] := Round(Nm.X * 1000); Q[1] := Round(Nm.Y * 1000); Q[2] := Round(Nm.Z * 1000);
    Q[3] := Round(Dot3(Nm, P) * 1000);
    { and the group: the same plane in two groups is two planes here }
    Q[4] := Part;
    SetLength(Result, 40);
    Move(Q[0], Result[1], 40);
  end;

  procedure NotePlane(const Key: shortstring; SI: Integer);
  var
    Ix: Integer;
  begin
    Ix := PlaneIx.FindIndexOf(Key);
    if Ix < 0 then
    begin
      SetLength(PlaneLists, Length(PlaneLists) + 1);
      Ix := High(PlaneLists);
      PlaneIx.Add(Key, Pointer(PtrInt(Ix + 1)));
    end
    else
      Ix := PtrInt(PlaneIx.Items[Ix]) - 1;
    SetLength(PlaneLists[Ix], Length(PlaneLists[Ix]) + 1);
    PlaneLists[Ix][High(PlaneLists[Ix])] := SI;
  end;

  procedure NoteRegion(const Key: shortstring; RI: Integer);
  var
    Ix: Integer;
  begin
    Ix := RegionIx.FindIndexOf(Key);
    if Ix < 0 then
    begin
      SetLength(RegionLists, Length(RegionLists) + 1);
      Ix := High(RegionLists);
      RegionIx.Add(Key, Pointer(PtrInt(Ix + 1)));
    end
    else
      Ix := PtrInt(RegionIx.Items[Ix]) - 1;
    SetLength(RegionLists[Ix], Length(RegionLists[Ix]) + 1);
    RegionLists[Ix][High(RegionLists[Ix])] := RI;
  end;

  { the same index for anything filed by plane: a list per plane key, with
    the three neighboring offsets returned together }
  procedure NoteInto(H: TFPHashList; var Lists: TIntListsW; const Key: shortstring; Ix: Integer);
  var
    At: Integer;
  begin
    At := H.FindIndexOf(Key);
    if At < 0 then
    begin
      SetLength(Lists, Length(Lists) + 1);
      At := High(Lists);
      H.Add(Key, Pointer(PtrInt(At + 1)));
    end
    else
      At := PtrInt(H.Items[At]) - 1;
    SetLength(Lists[At], Length(Lists[At]) + 1);
    Lists[At][High(Lists[At])] := Ix;
  end;

  function OnPlaneIn(H: TFPHashList; const Lists: TIntListsW; const N, P: TP3; Part: Integer): TIntArrayW;
  var
    Nm: TP3;
    Ix, K, D, Have: Integer;
    Key: shortstring;
    Q: array[0..4] of Int64;
  begin
    Result := nil;
    Have := 0;
    Nm := CanonicalNormal(N);
    Q[0] := Round(Nm.X * 1000); Q[1] := Round(Nm.Y * 1000); Q[2] := Round(Nm.Z * 1000);
    Q[4] := Part;
    for D := -1 to 1 do
    begin
      Q[3] := Round(Dot3(Nm, P) * 1000) + D;
      SetLength(Key, 40);
      Move(Q[0], Key[1], 40);
      Ix := H.FindIndexOf(Key);
      if Ix < 0 then Continue;
      Ix := PtrInt(H.Items[Ix]) - 1;
      SetLength(Result, Have + Length(Lists[Ix]));
      for K := 0 to High(Lists[Ix]) do
      begin
        Result[Have] := Lists[Ix][K];
        Inc(Have);
      end;
    end;
  end;

  procedure Lap(K: Integer);
  begin
    Acc[K] := Acc[K] + (GetTickCount64 - TL);
    TL := GetTickCount64;
  end;

  function RegionsOnPlane(const N, P: TP3; Part: Integer): TIntArrayW;
  var
    Nm: TP3;
    Ix, K, D: Integer;
    Key: shortstring;
    Q: array[0..4] of Int64;
  begin
    Result := nil;
    Nm := CanonicalNormal(N);
    Q[0] := Round(Nm.X * 1000); Q[1] := Round(Nm.Y * 1000); Q[2] := Round(Nm.Z * 1000);
    Q[4] := Part;
    for D := -1 to 1 do
    begin
      Q[3] := Round(Dot3(Nm, P) * 1000) + D;
      SetLength(Key, 40);
      Move(Q[0], Key[1], 40);
      Ix := RegionIx.FindIndexOf(Key);
      if Ix < 0 then Continue;
      Ix := PtrInt(RegionIx.Items[Ix]) - 1;
      for K := 0 to High(RegionLists[Ix]) do
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := RegionLists[Ix][K];
      end;
    end;
  end;

  { the solids on the plane through P with normal N; the key is coarse, so
    neighboring offsets are asked too }
  function SolidsOnPlane(const N, P: TP3; Part: Integer): TIntArrayW;
  var
    Nm: TP3;
    Ix, K, D: Integer;
    Key: shortstring;
    Q: array[0..4] of Int64;
  begin
    Result := nil;
    Nm := CanonicalNormal(N);
    Q[0] := Round(Nm.X * 1000); Q[1] := Round(Nm.Y * 1000); Q[2] := Round(Nm.Z * 1000);
    Q[4] := Part;
    for D := -1 to 1 do
    begin
      Q[3] := Round(Dot3(Nm, P) * 1000) + D;
      SetLength(Key, 40);
      Move(Q[0], Key[1], 40);
      Ix := PlaneIx.FindIndexOf(Key);
      if Ix < 0 then Continue;
      Ix := PtrInt(PlaneIx.Items[Ix]) - 1;
      for K := 0 to High(PlaneLists[Ix]) do
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := PlaneLists[Ix][K];
      end;
    end;
  end;

  function OpeningOfSolid(const Rg: TRegion; out Grp: Integer): Boolean;
  var
    E, L: Integer;
    P, Q: TP3;
  begin
    Result := False;
    Grp := 0;
    for E := 0 to High(Rg.Outer) do
    begin
      P := Rg.Outer[E];
      Q := Rg.Outer[(E + 1) mod Length(Rg.Outer)];
      L := GroupLineAlong(P, Q);
      if L < 0 then Exit(False);
      if (Grp > 0) and (FD.Doc[L].Grp <> Grp) then Exit(False);
      Grp := FD.Doc[L].Grp;
    end;
    Result := Grp > 0;
  end;

  { the middle of a built solid, for pointing a face away from it }
  function SolidMidOf(G: Integer): TP3;
  var
    E, K, N: Integer;
  begin
    Result := P3(0, 0, 0);
    N := 0;
    for E := 0 to FD.Doc.Live - 1 do
      if (FD.Doc[E].Kind = ekFace) and (FD.Doc[E].Grp = G) then
        for K := 0 to High(FD.Doc[E].Poly) do
        begin
          Result := Add3(Result, FD.Doc[E].Poly[K]);
          Inc(N);
        end;
    if N > 0 then Result := P3(Result.X / N, Result.Y / N, Result.Z / N);
  end;

  { Has the line just drawn traced one of this region's sides?  That is
    SketchUp's healing gesture, the way back to a deliberately erased face.
    It beats both the erased-area memory and the solid-opening rule. }
  function HealsThis(const Rg: TRegion): Boolean;
  var
    E: Integer;
    P, Q: TP3;
  begin
    Result := False;
    if not FHealOn then Exit;
    for E := 0 to High(Rg.Outer) do
    begin
      P := Rg.Outer[E];
      Q := Rg.Outer[(E + 1) mod Length(Rg.Outer)];
      if SharesRun(P, Q, FHealA, FHealB) then Exit(True);
    end;
  end;

  { whether the old face lies in this region's plane: same normal, and the
    region's middle on it }
  function OnPlaneOf(W: Integer): Boolean;
  begin
    Result := (Abs(Abs(Dot3(Was[W].Nm, R[I].Normal)) - 1) < 1E-6) and
      (Abs(Dot3(Was[W].Nm, Sub3(Mid, Was[W].Poly[0]))) < 1E-4);
  end;

  { Did the old face cover this point: inside its outline and not inside one
    of its holes.  Otherwise a ring with its middle erased got the middle
    back every rebuild. }
  function WasCovering(W: Integer): Boolean;
  var
    H: Integer;
  begin
    Result := OnPlaneOf(W) and PointInLoop(Mid, Was[W].Poly, Was[W].Nm);
    if not Result then Exit;
    for H := 0 to High(Was[W].Holes) do
      if PointInLoop(Mid, Was[W].Holes[H], Was[W].Nm) then Exit(False);
  end;

begin
  Tk := GetTickCount64;
  { One finder pass per group with only its own edges; areas noted with
    their group.  Geometry in one group never closes an area with another. }
  R := nil;
  RPart := nil;
  Parts := AllPartIds;
  for PP := 0 to High(Parts) do
  begin
    CI := CacheFor(Parts[PP]);      { the slot first - see SeedRegions }
    RP := BuildRegionsCached(EdgeSegments(Parts[PP]), FRegionCaches[CI].Cache);
    RBase := Length(R);
    SetLength(R, RBase + Length(RP));
    SetLength(RPart, RBase + Length(RP));
    for I := 0 to High(RP) do
    begin
      R[RBase + I] := RP[I];
      RPart[RBase + I] := Parts[PP];
    end;
  end;
  Took('  regions', Tk);
  Tk := GetTickCount64;
  Made := 0;
  { the regions by plane; faces being deleted does not shift them, so build
    it now }
  RegionIx := TFPHashList.Create;
  SetLength(RegionLists, 0);
  for I := 0 to High(R) do
    if Length(R[I].Outer) >= 3 then
      NoteRegion(PlaneKey(R[I].Normal, R[I].Outer[0], RPart[I]), I);

  { A solid's face divided by what was drawn on it (an arc whose chord is a
    box's top edge splits the top in two).  When the pieces on the face add
    up to it and at least one shares an edge with its outline (a cut, not a
    window), the face is replaced by the pieces, each a face of the same
    solid, so push can lift a piece. }
  SetLength(Doomed, FD.Doc.Live);
  for J := 0 to High(Doomed) do Doomed[J] := False;
  SetLength(RMid, Length(R));
  SetLength(RMidOK, Length(R));
  for J := 0 to High(RMidOK) do RMidOK[J] := False;
  for J := FD.Doc.Live - 1 downto 0 do
  begin
    if (FD.Doc[J].Kind <> ekFace) or not FD.Doc[J].Solid then Continue;
    if Length(FD.Doc[J].Holes) > 0 then Continue;
    { one copy of the face: the indexer returns a whole record copy each time }
    FE := FD.Doc[J];
    FN := FD.Doc.FaceNormal(J);
    FArea := Abs(LoopArea(FE.Poly, FN));
    if FArea < 1E-9 then Continue;
    FLo := FE.Poly[0];
    FHi := FE.Poly[0];
    for K := 1 to High(FE.Poly) do
    begin
      FLo := P3(Min(FLo.X, FE.Poly[K].X), Min(FLo.Y, FE.Poly[K].Y), Min(FLo.Z, FE.Poly[K].Z));
      FHi := P3(Max(FHi.X, FE.Poly[K].X), Max(FHi.Y, FE.Poly[K].Y), Max(FHi.Z, FE.Poly[K].Z));
    end;
    SetLength(Pieces, 0);
    PiecesArea := 0;
    Shares := False;
    RCands := RegionsOnPlane(FN, FE.Poly[0], FE.Part);
    for RC := 0 to High(RCands) do
    begin
      I := RCands[RC];
      if Length(R[I].Holes) > 0 then Continue;
      { a region's middle, computed once; many faces ask about it }
      if not RMidOK[I] then
      begin
        RMid[I] := InnerPoint(R[I].Outer, R[I].Normal);
        RMidOK[I] := True;
      end;
      Mid := RMid[I];
      { outside the face's box is not on it; this keeps the pass cheap }
      if (Mid.X < FLo.X - 1E-4) or (Mid.X > FHi.X + 1E-4) or
         (Mid.Y < FLo.Y - 1E-4) or (Mid.Y > FHi.Y + 1E-4) or
         (Mid.Z < FLo.Z - 1E-4) or (Mid.Z > FHi.Z + 1E-4) then Continue;
      if Abs(Abs(Dot3(Norm3(R[I].Normal), FN)) - 1) > 1E-6 then Continue;
      if Abs(Dot3(FN, Sub3(Mid, FE.Poly[0]))) > 1E-4 then Continue;
      if not PointInLoop(Mid, FE.Poly, FN) then Continue;
      { the whole face as a region is not a division }
      if Abs(Abs(LoopArea(R[I].Outer, R[I].Normal)) - FArea) < 1E-3 then
        Continue;
      SetLength(Pieces, Length(Pieces) + 1);
      Pieces[High(Pieces)] := I;
      PiecesArea := PiecesArea + Abs(LoopArea(R[I].Outer, R[I].Normal));
      { A piece shares the outline when one of its edges lies along one of
        the face's edges (not corner to corner, which fails once something
        else has split the face's edge). }
      if not Shares then
        for K := 0 to High(R[I].Outer) do
          for M := 0 to High(FE.Poly) do
            if OnSegment(R[I].Outer[K], FE.Poly[M],
                         FE.Poly[(M + 1) mod Length(FE.Poly)]) and
               OnSegment(R[I].Outer[(K + 1) mod Length(R[I].Outer)], FE.Poly[M],
                         FE.Poly[(M + 1) mod Length(FE.Poly)]) then
              Shares := True;
    end;
    if (Length(Pieces) < 2) or not Shares then Continue;
    if Abs(PiecesArea - FArea) > 1E-3 * (1 + FArea) then Continue;

    { replace it: the pieces become faces of the same solid }
    G := FD.Doc[J].Grp;
    Ink := FD.Doc[J].Ink;
    Doomed[J] := True;
    FD.Doc.Stamp := FE.Part;       { the pieces are born into the solid's group }
    for I := 0 to High(Pieces) do
    begin
      FD.Doc.AddFaceRaw(R[Pieces[I]].Outer, Ink, True);
      FD.Doc.SetFaceGroup(FD.Doc.Live - 1, G);
      { facing the way the replaced face did; a piece wound the other way
        would show its blue back }
      if Dot3(FD.Doc.FaceNormal(FD.Doc.Live - 1), FN) < 0 then
        FD.Doc.FlipFace(FD.Doc.Live - 1);
    end;
  end;

  FD.Doc.Stamp := FD.Doc.Context;
  { the divided faces go in one pass; one at a time shifted everything after }
  FD.Doc.DeleteMarked(Doomed);
  Took('  tiling', Tk);
  Tk := GetTickCount64;
  { remember what was there, so new faces can take their colors }
  NWas := 0;
  SetLength(Was, FD.Doc.Live);
  for I := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[I].Kind = ekFace) and not FD.Doc[I].Solid and
       (Length(FD.Doc[I].Poly) >= 3) then
    begin
      Was[NWas].Poly := Copy(FD.Doc[I].Poly, 0, Length(FD.Doc[I].Poly));
      SetLength(Was[NWas].Holes, Length(FD.Doc[I].Holes));
      for J := 0 to High(FD.Doc[I].Holes) do
        Was[NWas].Holes[J] := Copy(FD.Doc[I].Holes[J], 0, Length(FD.Doc[I].Holes[J]));
      Was[NWas].Nm := FD.Doc.FaceNormal(I);
      Was[NWas].Ink := FD.Doc[I].Ink;
      Was[NWas].Part := FD.Doc[I].Part;
      Was[NWas].Mat := FD.Doc[I].Mat;
      Was[NWas].MatSet := FD.Doc[I].MatSet;
      Mid := P3(0, 0, 0);
      for K := 0 to High(Was[NWas].Poly) do
        Mid := Add3(Mid, Was[NWas].Poly[K]);
      K := Length(Was[NWas].Poly);
      Was[NWas].Mid := P3(Mid.X / K, Mid.Y / K, Mid.Z / K);
      Inc(NWas);
    end;
  SetLength(Was, NWas);
  { the old faces by plane, so a region only asks those on its own plane }
  WasIx := TFPHashList.Create;
  SetLength(WasLists, 0);
  for J := 0 to NWas - 1 do
    NoteInto(WasIx, WasLists, PlaneKey(Was[J].Nm, Was[J].Mid, Was[J].Part), J);
  { and what the sheet had seen, the same way }
  SeenIx := TFPHashList.Create;
  SetLength(SeenLists, 0);
  for J := 0 to High(FD.Seen) do
    NoteInto(SeenIx, SeenLists, PlaneKey(FD.Seen[J].Nm, FD.Seen[J].Mid, FD.Seen[J].Part), J);

  { out with the old in one pass; one at a time was most of a minute on a
    big drawing }
  SetLength(Doomed, FD.Doc.Live);
  for I := 0 to FD.Doc.Live - 1 do
    Doomed[I] := (FD.Doc[I].Kind = ekFace) and not FD.Doc[I].Solid;
  FD.Doc.DeleteMarked(Doomed);
  Took('  old faces out', Tk);
  Tk := GetTickCount64;

  { The solids' faces, planes, areas and lines by their ends, built once for
    the loop below.  Built after the tiling pass, which deletes and adds
    faces and shifts indices; built earlier, they pointed at the wrong
    things. }
  SetLength(SolidIx, 0);
  for J := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[J].Kind = ekFace) and FD.Doc[J].Solid and (Length(FD.Doc[J].Poly) >= 3) then
    begin
      SetLength(SolidIx, Length(SolidIx) + 1);
      SolidIx[High(SolidIx)] := J;
    end;
  SetLength(SolidN, Length(SolidIx));
  SetLength(SolidP0, Length(SolidIx));
  SetLength(SolidMid, Length(SolidIx));
  SetLength(SolidRad, Length(SolidIx));
  SetLength(SolidArea, Length(SolidIx));
  PlaneIx := TFPHashList.Create;
  SetLength(PlaneLists, 0);
  for J := 0 to High(SolidIx) do
  begin
    SolidN[J] := FD.Doc.FaceNormal(SolidIx[J]);
    FE := FD.Doc[SolidIx[J]];
    SolidP0[J] := FE.Poly[0];
    Mid := P3(0, 0, 0);
    for K := 0 to High(FE.Poly) do
      Mid := Add3(Mid, FE.Poly[K]);
    K := Length(FE.Poly);
    SolidMid[J] := P3(Mid.X / K, Mid.Y / K, Mid.Z / K);
    SolidRad[J] := 0;
    for K := 0 to High(FE.Poly) do
      SolidRad[J] := Max(SolidRad[J], Dist(SolidMid[J], FE.Poly[K]));
    SolidArea[J] := Abs(LoopArea(FD.Doc[SolidIx[J]].Poly, SolidN[J]));
    { by plane, so a region meets only solids in its own plane }
    NotePlane(PlaneKey(SolidN[J], FD.Doc[SolidIx[J]].Poly[0], FD.Doc[SolidIx[J]].Part), J);
  end;
  { and the solids' lines by their ends, for the opening test }
  LineIx := TFPHashList.Create;
  SetLength(LineLists, 0);
  for J := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[J].Kind = ekLine) and (FD.Doc[J].Grp > 0) then
    begin
      NoteLine(FD.Doc[J].A, J);
      NoteLine(FD.Doc[J].B, J);
    end;

  Took('  tables', Tk);
  Tk := GetTickCount64;
  FillChar(Acc, SizeOf(Acc), 0);
  { a region with no outline is nothing to look at }
  for I := 0 to High(R) do
  begin
    if ((I and 63) = 0) and (Length(R) > 500) then
      if not OnProgress('Working out the faces', I / Length(R)) then Break;
    if Length(R[I].Outer) < 3 then Continue;
    TL := GetTickCount64;
    { this area's group: the tables answer for it, and a new face is born
      into it }
    CurPart := RPart[I];
    FD.Doc.Stamp := CurPart;
    Mid := InnerPointOf(R[I].Outer, R[I].Holes, R[I].Normal);
    Lap(0);

    { Is this a face the solid already has?  Same plane, same outline area,
      and a point of one inside the other (not the corner average, which
      moves when an edge is split).  A second face in the same place would
      flicker. }
    Dup := False;
    DupAt := -1;
    RegArea := -1;
    Cands := SolidsOnPlane(R[I].Normal, R[I].Outer[0], RPart[I]);
    for CI := 0 to High(Cands) do
      begin
        SI := Cands[CI];
        J := SolidIx[SI];
        Other := SolidN[SI];
        if Abs(Abs(Dot3(Other, R[I].Normal)) - 1) > 1E-6 then Continue;
        { the same plane, not merely a parallel one }
        if Abs(Dot3(Other, Sub3(SolidP0[SI], R[I].Outer[0]))) > 1E-4
          then Continue;
        { Outline against outline, holes ignored: the outline is what makes
          it the same face, and holes change between rebuilds (so a window
          drawn on a wall still matches and hands the wall its hole below).
          Further from the solid's middle than any corner is not inside it,
          which keeps PointInLoop to plausible candidates. }
        if Dist(Mid, SolidMid[SI]) > SolidRad[SI] + 1E-4 then Continue;
        if RegArea < 0 then RegArea := Abs(LoopArea(R[I].Outer, R[I].Normal));
        if Abs(RegArea - SolidArea[SI]) > 1E-3 then
          Continue;
        if PointInLoop(Mid, FD.Doc[J].Poly, Other) then
        begin
          Dup := True;
          DupAt := J;
          Break;
        end;
      end;
    Lap(1);
    if Dup then
    begin
      { The solid already has this face, but the area may have gained a hole
        (a rectangle drawn inside a column's side): hand the holes to the
        solid's face so the window opens. }
      if DupAt >= 0 then FD.Doc.SetFaceHoles(DupAt, R[I].Holes);
      Continue;
    end;

    { Did this area have a face a moment ago, or has the sheet seen it
      before?  An area seen before with no face now was erased on purpose and
      gets none.  A new area was just closed and does.  Old faces must be in
      the same plane, not just contain the point when projected (a box's far
      end would otherwise answer for its near end). }
    HadFace := False;
    WasOn := OnPlaneIn(WasIx, WasLists, R[I].Normal, Mid, RPart[I]);
    for J := 0 to High(WasOn) do
      if WasCovering(WasOn[J]) then
      begin
        HadFace := True;
        Break;
      end;
    if not HadFace and not HealsThis(R[I]) then
    begin
      { An opening of a built solid (a duct end, a hole) is edged entirely by
        that solid's edges and never gets a face, however it got here.  Draw
        across it and it becomes a new area like any other. }
      Lap(2);
      if OpeningOfSolid(R[I], HealGrp) then begin Lap(3); Continue; end;
      Lap(3);
      Sig := RegionSig(R[I]);
      Sig.Part := RPart[I];
      Known := False;
      SeenOn := OnPlaneIn(SeenIx, SeenLists, Sig.Nm, Sig.Mid, RPart[I]);
      for J := 0 to High(SeenOn) do
        if SameRegion(Sig, FD.Seen[SeenOn[J]]) then
        begin
          Known := True;
          Break;
        end;
      Lap(4);
      if Known then Continue;
    end;

    Ink := FInkColor;
    WasHit := -1;
    for J := 0 to High(WasOn) do
      if WasCovering(WasOn[J]) then
      begin
        Ink := Was[WasOn[J]].Ink;
        WasHit := WasOn[J];
        Break;
      end;
    FD.Doc.AddFace(R[I].Outer, Ink, False);
    { the replaced face's paint and direction carry across, or it may show
      its blue back }
    if WasHit >= 0 then
    begin
      if Was[WasHit].MatSet then
        FD.Doc.SetMaterial(FD.Doc.Live - 1, Was[WasHit].Mat);
      if Dot3(FD.Doc.FaceNormal(FD.Doc.Live - 1), Was[WasHit].Nm) < 0 then
        FD.Doc.FlipFace(FD.Doc.Live - 1);
    end;
    { and whatever is cut out of it }
    if Length(R[I].Holes) > 0 then
      FD.Doc.SetFaceHoles(FD.Doc.Live - 1, R[I].Holes);
    { A side traced back into a box joins the box; left loose it would be
      refused at the next rebuild (a solid's opening gets no loose face). }
    if FHealOn and HealsThis(R[I]) and OpeningOfSolid(R[I], HealGrp) then
    begin
      FD.Doc.SetFaceGroup(FD.Doc.Live - 1, HealGrp);
      { facing out, away from the solid's middle.  The area's middle may not
        have been computed by the tiling pass, so compute it here. }
      if not RMidOK[I] then
      begin
        RMid[I] := InnerPoint(R[I].Outer, R[I].Normal);
        RMidOK[I] := True;
      end;
      Mid := SolidMidOf(HealGrp);
      if Dot3(FD.Doc.FaceNormal(FD.Doc.Live - 1),
              Sub3(RMid[I], Mid)) < 0 then
        FD.Doc.FlipFace(FD.Doc.Live - 1);
    end;
    Inc(Made);
    Lap(5);
  end;
  if FTimings then
    TimingLine(Format('region loop phases ms: inner %d dup %d was %d opening %d seen %d add %d',
      [Acc[0], Acc[1], Acc[2], Acc[3], Acc[4], Acc[5]]));
  LineIx.Free;
  PlaneIx.Free;
  RegionIx.Free;
  WasIx.Free;
  SeenIx.Free;
  if not FLoading then EndBusy;
  FD.Doc.Stamp := FD.Doc.Context;
  Took('  the region loop', Tk);
  Tk := GetTickCount64;
  { what the sheet has seen, for the next rebuild to compare against }
  SetLength(FD.Seen, Length(R));
  for I := 0 to High(R) do
  begin
    FD.Seen[I] := RegionSig(R[I]);
    FD.Seen[I].Part := RPart[I];
  end;
  Took('  seen signatures', Tk);

  { Then make the loose faces agree about which way is out.  OrientFace
    looks at one face at a time and gets roof slopes wrong; a face pointing
    in shows its blue back.  This needs all the neighbors, so it runs after
    the loop. }
  FTurned := 0;
  for PP := 0 to High(Parts) do
    FTurned := FTurned + FD.Doc.OrientLooseShells(Parts[PP]);
  Took('  turning loose faces the right way out', Tk);

  Result := Made;
end;

{ A read-only look at what the region engine makes of the drawing beside the
  faces actually stored, for checking. }
procedure TMainForm.ReportRegions;
var
  R: TRegionArray;
  Segs: TSegArray;
  I, Stored, Holes, CI: Integer;
  Area, StoredArea, T0: Double;
begin
  Segs := EdgeSegments(FD.Doc.Context);
  T0 := Now;
  CI := CacheFor(FD.Doc.Context);
  R := BuildRegionsCached(Segs, FRegionCaches[CI].Cache);
  T0 := (Now - T0) * 24 * 60 * 60 * 1000;

  Stored := 0;
  StoredArea := 0;
  for I := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[I].Kind = ekFace) and not FD.Doc[I].Solid then
    begin
      Inc(Stored);
      StoredArea := StoredArea + FD.Doc.FaceArea(I);
    end;

  Area := 0;
  Holes := 0;
  for I := 0 to High(R) do
  begin
    Area := Area + Abs(LoopArea(R[I].Outer, R[I].Normal));
    Inc(Holes, Length(R[I].Holes));
  end;

  FCmdMsg := Format('%d edges -> %d regions (%s, %d holes) in %.0f ms.  ' +
    'Stored flat faces: %d (%s)',
    [Length(Segs), Length(R), FormatArea(Area, FD.Units), Holes, T0,
     Stored, FormatArea(StoredArea, FD.Units)]);
  pbCmd.Invalidate;
end;

{ Where the dimension being placed goes: DimOffsetAt (hsDrawing), which
  follows the hand on screen.  The planes of faces the edge belongs to are
  offered first, so it can stand up a box's side, even off-axis. }
function TMainForm.DimOffset3: TP3;
var
  Extra: array of TP3;
  I, K, N: Integer;
  D, Nm: TP3;
  L: Double;
begin
  Extra := nil;
  D := Sub3(FP2, FP1);
  for I := 0 to FD.Doc.Live - 1 do
  begin
    if FD.Doc[I].Kind <> ekFace then Continue;
    N := Length(FD.Doc[I].Poly);
    for K := 0 to N - 1 do
      if ((Dist(FD.Doc[I].Poly[K], FP1) < 1E-6) and (Dist(FD.Doc[I].Poly[(K + 1) mod N], FP2) < 1E-6)) or
         ((Dist(FD.Doc[I].Poly[K], FP2) < 1E-6) and (Dist(FD.Doc[I].Poly[(K + 1) mod N], FP1) < 1E-6)) then
      begin
        Nm := FD.Doc.FaceNormal(I);
        SetLength(Extra, Length(Extra) + 1);
        Extra[High(Extra)] := Cross3(Nm, D);
        Break;
      end;
  end;
  Result := DimOffsetAt(Proj, FP1, FP2, FMouseSX, FMouseSY, Extra, FDimPrefer);
  L := Sqrt(Sqr(Result.X) + Sqr(Result.Y) + Sqr(Result.Z));
  if L < 1E-9 then Exit;
  FDimPrefer := P3(Result.X / L, Result.Y / L, Result.Z / L);
  { never let it sit right on top of what it measures }
  if L * Ppu < 8 then
    Result := P3(Result.X / L * 8 / Ppu, Result.Y / L * 8 / Ppu, Result.Z / L * 8 / Ppu);
end;

{ the circle or arc that P is one of the drawn corners of (not an arc's own
  two ends), or -1 }
function TMainForm.CurveThrough(const P: TP3): Integer;
var
  I: Integer;
  E: TWorkEnt;
  Nm: TP3;
begin
  Result := -1;
  for I := 0 to FD.Doc.Live - 1 do
  begin
    E := FD.Doc[I];
    if E.Kind <> ekArc then Continue;
    if Abs(Dist(P, E.C) - E.R) > 1E-6 * Max(1, E.R) then Continue;
    Nm := Cross3(P3(ArcPoint(E.C, 1, 0, E.Plane, E.Nm).X - E.C.X,
                    ArcPoint(E.C, 1, 0, E.Plane, E.Nm).Y - E.C.Y,
                    ArcPoint(E.C, 1, 0, E.Plane, E.Nm).Z - E.C.Z),
                 P3(ArcPoint(E.C, 1, Pi / 2, E.Plane, E.Nm).X - E.C.X,
                    ArcPoint(E.C, 1, Pi / 2, E.Plane, E.Nm).Y - E.C.Y,
                    ArcPoint(E.C, 1, Pi / 2, E.Plane, E.Nm).Z - E.C.Z));
    if Abs(Dot3(Nm, Sub3(P, E.C))) > 1E-6 * Max(1, E.R) then Continue;
    if (Abs(E.Sweep) < 2 * Pi - 1E-9) and
       ((Dist(P, E.A) < 1E-6) or (Dist(P, E.B) < 1E-6)) then Continue;
    Exit(I);
  end;
end;

{ A circle's diameter or an arc's radius, turned to the pointer: the point
  on it nearest the pointer is one end; the other is the opposite point for
  a circle, the center for an arc.  Note is "DIA <>" or "R <>", the length
  going in the <>. }
function TMainForm.DimRadialAt(out A, B: TP3; out Note: string): Boolean;
var
  E: TWorkEnt;
  K, N, BestK: Integer;
  Ang, BestD, D, Sw: Double;
  P: TPointF;
begin
  Result := False;
  if (FDimArc < 0) or (FDimArc >= FD.Doc.Live) or (FD.Doc[FDimArc].Kind <> ekArc) then Exit;
  E := FD.Doc[FDimArc];
  Sw := E.Sweep;
  if Abs(Sw) >= 2 * Pi - 1E-9 then Sw := 2 * Pi;
  N := 360;
  BestD := 1E30; BestK := 0;
  for K := 0 to N do
  begin
    Ang := E.A0 + Sw * K / N;
    P := ScreenOf(ArcPoint(E.C, E.R, Ang, E.Plane, E.Nm));
    D := Sqr(P.X - FMouseSX) + Sqr(P.Y - FMouseSY);
    if D < BestD then begin BestD := D; BestK := K; end;
  end;
  B := ArcPoint(E.C, E.R, E.A0 + Sw * BestK / N, E.Plane, E.Nm);
  if Abs(E.Sweep) >= 2 * Pi - 1E-9 then
  begin
    A := P3(2 * E.C.X - B.X, 2 * E.C.Y - B.Y, 2 * E.C.Z - B.Z);
    Note := 'DIA <>';
  end
  else
  begin
    A := E.C;
    Note := 'R <>';
  end;
  Result := True;
end;

{ Rest on a point for a moment and it is remembered as a reference, so you
  can move away and still line up with it (SketchUp's trick). }
procedure TMainForm.ServiceHover;
var
  Now64: QWord;
begin

  { any real movement restarts the clock }
  if (Abs(FMoveX - FDwellSX) > 3) or (Abs(FMoveY - FDwellSY) > 3) then
  begin
    FDwellSX := FMoveX;
    FDwellSY := FMoveY;
    FDwellSince := GetTickCount64;
    Exit;
  end;

  { only a point worth referencing is worth keeping }
  if not (FSnapKind in [snEndpoint, snMidpoint, snCenter, snCross, snSubMid]) then
    Exit;

  Now64 := GetTickCount64;
  if Now64 - FDwellSince < DWELL_MS then Exit;

  if FNoLockUntilMoved then Exit;         // just snapped off from here
  if FLockOn and (Dist(FLockPt, FCur) < 1E-9) then Exit;   // already this one
  FLockOn := True;
  FLockPt := FCur;
  FScreenDirty := True;
  InvalidateStatus;
end;

{ Alignment guides to another point get their own color, distinct from ink
  and from axis colors, so they never look like something being drawn. }
function TMainForm.GuideColor: TPix;
begin
  Result := Pix($A8, $2A, $BA);
end;

procedure TMainForm.pbScreenMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  NoteI: Integer;
begin
  if FBusy then Exit;
  { the cube, if it had the press }
  if FCubeDrag then
  begin
    CubeMouse(X, Y, False, True);
    pbScreen.Invalidate;
    Exit;
  end;
  { let go of a note being carried }
  if FNoteDrag >= 0 then
  begin
    NoteI := FNoteDrag;
    FNoteDrag := -1;
    if not FNoteMoved then
    begin
      { the press never carried it: that is a click, and a click picks it so
        it can be sized or deleted }
      SelectOnly(NoteI);
      FCmdMsg := '';
      pbCmd.Invalidate;
      FScreenDirty := True;
      Exit;
    end;
    FCmdMsg := 'Note moved.  What it points at has not.';
    pbCmd.Invalidate;
    Exit;
  end;
  { the release position is the last thing the stroke saw }
  FMoveX := X;
  FMoveY := Y;
  FMovePending := True;
  ServiceMotion;

  { A press that never became a hold.  Two clicks in quick succession end
    the run without placing more (the first click's point stays); one click
    carries on as usual. }
  if FHoldOn and (Button = mbLeft) then
  begin
    FHoldOn := False;
    FCur := ResolveSnapAt(X, Y);
    { a double-click ends a run of lines; push/pull handles its own
      double-click.  The arc's double-click is SketchUp's: trim the corner
      just rounded, or round the one under the pointer with the same radius. }
    if (FClickN >= 2) and (FTool = ptArc) and ArcDoubleClick(X, Y) then
    begin
      FScreenDirty := True;
      Exit;
    end;
    if (FClickN >= 2) and (FTool in [ptLine, ptRect, ptCircle, ptArc]) then
    begin
      ResetTool;
      FCmdMsg := 'Line finished.  Hold the button to snap it off instead.';
    end
    else
      ToolClick;
    FScreenDirty := True;
    Exit;
  end;

  if FErasing2 then
  begin
    FErasing2 := False;
    if FEraseMode = 0 then BurnDoomed
    else SoftenDoomed(FEraseMode = 1);
    Exit;
  end;

  if FBoxing then
  begin
    FBoxing := False;
    FinishSelect(X, Y, Shift);
    Exit;
  end;

  if FPanning or FOrbiting then
  begin
    { Ctrl held as the button comes up snaps to the nearest of the cube's 26
      views.  Ctrl because window managers take Alt+drag and Shift is the pan.
      Read at release so it can be pressed partway through the orbit. }
    if FOrbiting and (ssCtrl in Shift) then SnapOrbitToNearest;
    FSnapHasHot := False;
    FPanning := False;
    FOrbiting := False;
    if FTool = ptOrbit then pbScreen.Cursor := crSizeAll
    else pbScreen.Cursor := crCross;
    { the camera has stopped: one full frame after the quick ones }
    if FCameraMoving then
    begin
      FCameraMoving := False;
      RepaintPaper;
      RenderInk;
      RecomposeAll;
      Invalidate;
    end;
    { A right press released in the same place was a click, not a pan: open
      the menu (or edit a dimension).  This has to wait for the release. }
    if (Button = mbRight) and
       (Abs(X - FRightSX) <= 3) and (Abs(Y - FRightSY) <= 3) then
      RightClickAt(X, Y);
  end;
end;

procedure TMainForm.pbScreenMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
const
  WHEEL_ROWS = 3;      { rows per notch, as in most lists }
begin
  if FBusy then Exit;
  { an open list gets the wheel before the drawing does }
  if ScrollPopup(IfThen(WheelDelta > 0, -WHEEL_ROWS, WHEEL_ROWS),
                 MousePos.X, MousePos.Y) then
  begin
    Handled := True;
    Exit;
  end;
  { and so does the cube }
  if OverCube(MousePos.X, MousePos.Y) or CubeZone(MousePos.X, MousePos.Y) then
  begin
    Handled := True;
    Exit;
  end;
  { Ctrl+wheel over a plan moves the whole slice up and down through the
    model, while you watch the plan.  Plain wheel stays zoom; Alt is taken
    (it suspends snapping). }
  if (ssCtrl in Shift) and (FD.View = vkPlan) then
  begin
    if not FD.SliceOn then
      SetSlice(True, FD.SliceLo, FD.SliceHi)
    else if WheelDelta > 0 then NudgeSlice(1, 0)
    else NudgeSlice(-1, 0);
    Handled := True;
    Exit;
  end;
  if WheelDelta > 0 then
    ZoomAt(1.15, MousePos.X, MousePos.Y)
  else
    ZoomAt(1 / 1.15, MousePos.X, MousePos.Y);
  Handled := True;
end;

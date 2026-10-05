{ hsMainForm - painting the window, ink and units, history, clearing, and the heartbeat.  Part of TMainForm; included by hsMainForm.pas }

{ ======================================================================== }
{ window painting                                                           }
{ ======================================================================== }

{ Is the cursor on something a dimension may be anchored to?  SketchUp's list
  (end points, midpoints, on-edge points, intersections, centers), plus the
  origin and points on axes.  Not the grid or open air: a dimension must be
  driven by the drawing to update with it. }
function TMainForm.DimAnchored: Boolean;
begin
  Result := FSnapKind in [snEndpoint, snMidpoint, snCenter, snCross,
                          snSubMid, snQuadrant, snOnEdge, snOnFace,
                          snOnAxis, snOrigin];
end;

{ the zoom, with enough decimals that a tiny zoom never reads "0%" }
function TMainForm.ZoomReading: string;
var
  Z: Double;
begin
  Z := FD.Zoom * 100;
  if Z >= 100 then Result := Format('%.0f%%', [Z])
  else if Z >= 10 then Result := Format('%.1f%%', [Z])
  else if Z >= 1 then Result := Format('%.2f%%', [Z])
  else Result := Format('%.3f%%', [Z]);
end;

function TMainForm.StatusLine: string;
var
  L, A, RW, RH: Double;
  Mv: TP3;
  Ai: Integer;
begin
  if FD.View <> vkPlan then
    Result := Format('X %s   Y %s   Z %s',
      [FormatLen(FCur.X, FD.Units), FormatLen(FCur.Y, FD.Units),
       FormatLen(FCur.Z, FD.Units)])
  else
    Result := Format('X %s   Y %s',
      [FormatLen(FCur.X, FD.Units), FormatLen(FCur.Y, FD.Units)]);

  if (FStage = 1) and (FTool in [ptLine, ptMeasure]) then
    Result := Result + '   LEN ' + FormatLen(Dist(FP1, PreviewTarget), FD.Units);

  { which way the face actually goes: IN or OUT by the sign against the
    loop, which is how the user sees it }
  if (FStage = 1) and (FTool = ptOffset) then
  begin
    L := OffsetDistance;
    if Abs(L) > 1E-9 then
      Result := Result + '   OFFSET ' + FormatLen(Abs(L), FD.Units) +
        specialize IfThen<string>(L < 0, ' IN', ' OUT');
  end;

  if (FStage = 1) and (FTool = ptRect) then
  begin
    RectSides(FP1, RectTarget, FD.Plane, RW, RH);
    Result := Result + Format('   %s x %s   AREA %s',
      [FormatLen(RW, FD.Units), FormatLen(RH, FD.Units),
       FormatArea(RW * RH, FD.Units)]);
  end;

  if (FD.View <> vkPlan) then
  begin
    Result := Result + '   PLANE ' + PlaneName;
    { where the plane came from: held, a face, or the drag; they behave
      differently }
    if FPlaneHeld then Result := Result + ' HELD'
    else if FPlaneFromFace then Result := Result + ' ON FACE'
    else if FStage >= 1 then Result := Result + ' FROM DRAG';

  end;

  { the face push/pull is offered and its size, as SketchUp shows; it tells
    stacked faces apart }
  if (FStage = 0) and (FTool in [ptPush, ptDrill]) and (FHoverFace >= 0) then
    Result := Result + '   FACE ' +
      FormatArea(FD.Doc.FaceArea(FHoverFace), FD.Units);

  if (FStage = 1) and (FTool in [ptPush, ptDrill]) and (FPushFace >= 0) then
  begin
    L := PushDistance;
    if Abs(L) > 1E-9 then
    begin
      Mv := FD.Doc.FaceNormal(FPushFace);
      Mv := Mul3(Mv, L);
      if (Abs(Mv.X) >= Abs(Mv.Y)) and (Abs(Mv.X) >= Abs(Mv.Z)) then
        Ai := 0
      else if Abs(Mv.Y) >= Abs(Mv.Z) then
        Ai := 2
      else
        Ai := 4;
      case Ai of
        0: if Mv.X < 0 then Ai := 1;
        2: if Mv.Y < 0 then Ai := 3;
      else
        if Mv.Z < 0 then Ai := 5;
      end;
      Result := Result + '   PUSH ' + FormatLen(Abs(L), FD.Units) +
        ' ' + AxisName(Ai);
    end;
  end;

  L := FD.Doc.ChainLength;
  if L > 0 then
  begin
    Result := Result + '   RUN ' + FormatLen(L, FD.Units);
    if FD.Doc.ChainClosed(Max(SnapStep, 1E-6)) then
    begin
      A := FD.Doc.ChainArea;
      if A > 0 then
        Result := Result + '   AREA ' + FormatArea(A, FD.Units);
    end;
  end;
end;

procedure TMainForm.FormPaint(Sender: TObject);
var
  VerX: Integer;
  M, Y, TW, RightEdge: Integer;
  S: string;
begin
  if not FBooted then Exit;
  FShell.DrawTo(Canvas, 0, 0);

  M := ChromeMargin;

  { One line.  The file buttons have the left; the reading is right-aligned
    and grows leftward; the version sits between. }
  Y := Round(5 * FUIScale);

  { the reading goes hard against ClientWidth - M, where the VIEW button
    below ends, so the right edges line up }
  RightEdge := ClientWidth - M;
  UIFont(Canvas, 11, True, Theme.Text, True);
  S := StatusLine;
  TW := Canvas.TextWidth(S);
  Canvas.TextOut(RightEdge - TW, Round(6 * FUIScale), S);

  { No program name here: the reading grows leftward into the middle.  The
    version stays (it is the first thing quoted in a bug report), with any
    newer-build notice, against the buttons. }
  VerX := pbQuick.Left + pbQuick.Width + Round(16 * FUIScale);
  UIFont(Canvas, 9, False, Theme.TextDim);
  Canvas.TextOut(VerX, Y + Round(4 * FUIScale), CurrentVersion);
  VerX := VerX + Canvas.TextWidth(CurrentVersion) + Round(14 * FUIScale);
  { a newer build, shown where nothing overwrites it, until it is taken }
  if FUpdateTag <> '' then
  begin
    UIFont(Canvas, 9, True, Pix(90, 190, 255));
    S := '* ' + FUpdateTag + ' available - /update';
    if VerX + Canvas.TextWidth(S) < RightEdge - TW - Round(16 * FUIScale) then
      Canvas.TextOut(VerX, Y + Round(4 * FUIScale), S);
  end;
end;

{ ======================================================================== }
{ ink, precision, units                                                     }
{ ======================================================================== }

procedure TMainForm.SetInk(C: TColor; Auto: Boolean);
begin
  FInkColor := C;
  FInkAuto := Auto;
  dlgColor.Color := C;
  pbDeck.Invalidate;
end;

{ How finely lengths are written and read.  One setting for both, so a typed
  number never displays as a different one.  It never changes what the model
  holds: finer input keeps every digit and is only shown rounded. }
procedure TMainForm.SetLenPrecision(D: Integer);
begin
  SetLenDenom(D);
  FLenDenom := LenDenom;
  if FLenDenom = 100 then
    FCmdMsg := 'Lengths to hundredths of an inch.'
  else
    FCmdMsg := Format('Lengths to the nearest 1/%d of an inch.', [FLenDenom]);
  SaveSettings;
  RebuildDeck;
  pbDeck.Invalidate;
  RenderInk;
  RecomposeAll;
  InvalidateStatus;
  pbCmd.Invalidate;
end;

procedure TMainForm.SetEdgeWidth(V: Integer);
begin
  V := EnsureRange(V, MIN_PEN, MAX_PEN);
  if V = FEdgeW then Exit;
  FEdgeW := V;
  RenderInk;
  RecomposeAll;
  pbDeck.Invalidate;
  pbScreen.Invalidate;
end;

procedure TMainForm.SetUnits(U: TUnitSystem);
begin
  Act('units ' + IntToStr(Ord(U)));
  FD.Units := U;
  RenderInk;
  RecomposeAll;
  RebuildDeck;
  pbDeck.Invalidate;
  pbCmd.Invalidate;
  Invalidate;
end;

{ ======================================================================== }
{ history                                                                   }
{ ======================================================================== }

procedure TMainForm.PushUndo;
var
  I: Integer;
begin
  { the drawing changed, so whatever would not draw may be gone now }
  FRenderBroken := False;
  { every change to the drawing comes through here, so this is where the
    sheet is marked dirty and the draft clock reset }
  Inc(FEditSeq);
  if FD <> nil then FD.Dirty := True;
  FDraftAge := 0;
  if FD.UndoTop >= UNDO_LEVELS then
  begin
    for I := 0 to UNDO_LEVELS - 2 do
      FD.Undo[I] := FD.Undo[I + 1];
    FD.UndoTop := UNDO_LEVELS - 1;
  end;
  FD.Undo[FD.UndoTop] := FD.Doc.Snapshot;
  Inc(FD.UndoTop);
  FD.RedoTop := 0;
  pbDeck.Invalidate;
end;

function TMainForm.CanUndo: Boolean;
begin
  Result := FD.UndoTop > 0;
end;

function TMainForm.CanRedo: Boolean;
begin
  Result := FD.RedoTop > 0;
end;

procedure TMainForm.DoUndo;
begin
  Trail('undo');
  { the drawing is about to become a different one }
  SetLength(FOpenEdges, 0);
  Act('undo');
  SelectNone;   // the indices it held mean something else now
  if not CanUndo then Exit;
  if FD.RedoTop < UNDO_LEVELS then
  begin
    FD.Redo[FD.RedoTop] := FD.Doc.Snapshot;
    Inc(FD.RedoTop);
  end;
  Dec(FD.UndoTop);
  FD.Doc.RestoreSnap(FD.Undo[FD.UndoTop]);
  ResetTool;
  RenderInk;
  RecomposeAll;
  pbDeck.Invalidate;
end;

procedure TMainForm.DoRedo;
begin
  Trail('redo');
  { the drawing is about to become a different one }
  SetLength(FOpenEdges, 0);
  Act('redo');
  SelectNone;
  if not CanRedo then Exit;
  if FD.UndoTop < UNDO_LEVELS then
  begin
    FD.Undo[FD.UndoTop] := FD.Doc.Snapshot;
    Inc(FD.UndoTop);
  end;
  Dec(FD.RedoTop);
  FD.Doc.RestoreSnap(FD.Redo[FD.RedoTop]);
  ResetTool;
  RenderInk;
  RecomposeAll;
  pbDeck.Invalidate;
end;

{ ======================================================================== }
{ clearing the sheet, with a shake                                          }
{ ======================================================================== }

procedure TMainForm.StartErase;
begin
  if FErasing then Exit;
  Act('clear');
  PushUndo;
  FErasing := True;
  FEraseT := 0;
  Invalidate;
end;

procedure TMainForm.StepErase(Dt: Single);
var
  Amp: Single;
begin
  FEraseT := FEraseT + Dt / 0.7;
  if FEraseT >= 1 then
  begin
    FErasing := False;
    FJitterX := 0;
    FJitterY := 0;
    FD.Doc.Clear;
    RenderInk;
    ResetTool;
    RecomposeAll;
    Invalidate;
    pbDeck.Invalidate;
    Exit;
  end;

  Amp := Round(9 * FUIScale) * (1 - FEraseT);
  FJitterX := Round((Random - 0.5) * 2 * Amp);
  FJitterY := Round((Random - 0.5) * 2 * Amp);

  FInk.SmearDown(1 + Round(6 * FEraseT));
  FInk.FadeAlpha(0.06 + 0.14 * FEraseT);
  RecomposeAll;
  FArt.Grain(0.14 * (1 - FEraseT), 0.05);
  pbScreen.Invalidate;
end;

{ ======================================================================== }
{ the heartbeat                                                             }
{ ======================================================================== }

{ A remote display can change size underneath us (KasmVNC follows the
  browser window).  A window told to fill the screen must keep filling it,
  and there is no reliable notification, so it is watched on the tick. }
procedure TMainForm.FollowScreenSize;
var
  W, H: Integer;
begin
  if FFill = flNone then Exit;
  Screen.UpdateMonitors;
  W := Screen.Width;
  H := Screen.Height;
  if (W < 320) or (H < 240) then Exit;
  if (W = FScrW) and (H = FScrH) then Exit;
  FScrW := W;
  FScrH := H;
  if FFill = flFull then
  begin
    WindowState := wsNormal;
    SetBounds(0, 0, W, H);
    WindowState := wsFullScreen;
  end
  else
  begin
    WindowState := wsNormal;
    SetBounds(0, 0, W, H);
    WindowState := wsMaximized;
  end;
end;

procedure TMainForm.tmrTickTimer(Sender: TObject);
var
  Dt: Single;
  InfoSig: Int64;
  WhatsNewForm: TWhatsNewForm;
  BreakPts: TPointFArray;
  BreakI: Integer;
begin
  Dt := TICK_MS / 1000;

  { the splash comes down once loading is done and it has had its few
    seconds; while it is up nothing else here matters }
  if SplashUp then
  begin
    if SplashFinished and (SplashAge >= SPLASH_MIN_MS) then SplashHide
    else Exit;
  end;
  { long work lets messages through to paint progress, and this fires then
    too: stand down, unless the work is long over and forgot }
  if FBusy then
  begin
    if GetTickCount64 - FBusyAt > 600 then EndBusy;
    Exit;
  end;
  { A dialog has the screen: do nothing.  Ticking 60 times a second under a
    dialog made dragging it skip on compositing machines.  ModalLevel counts
    the stock dialogs too.  Everything here catches up on the next tick. }
  if Application.ModalLevel > 0 then Exit;

  { The entity and groups panels are rebuilt on the tick when what they read
    has changed (including the sheet and open group), not at every place the
    selection changes; some of those are bulk loops over huge selections. }
  if GroupsPanelOn then
  begin
    InfoSig := ((Int64(FD.Doc.FEditSeq) * 131 + FEditSeq) * 131 + Length(FSel)) * 131 +
      FD.Doc.Context * 7 + Int64(PtrUInt(FD.Doc) and $FFFFFF);
    if Length(FSel) > 0 then
      InfoSig := InfoSig * 131 + FSel[0] * 17 + FSel[High(FSel)];
    if InfoSig <> FGrpSig then
    begin
      FGrpSig := InfoSig;
      pbGroups.Invalidate;
    end;
  end;
  if FInfoOn then
  begin
    InfoSig := FEditSeq * 131 + Length(FSel);
    if Length(FSel) > 0 then
      InfoSig := InfoSig * 131 + FSel[0] * 17 + FSel[High(FSel)];
    if InfoSig <> FInfoSig then
    begin
      FInfoSig := InfoSig;
      RebuildInfo;
      pbInfo.Invalidate;
    end;
  end;

  { drawings left by a run that went down, offered once the window is up and
    nothing else is asking }
  if FRecoverToOffer and (FPopup = POP_NONE) and not FCrashToOffer and not SplashUp then
  begin
    FRecoverToOffer := False;
    OfferRecovery;
  end;

  if FCrashToOffer and (FPopup = POP_NONE) then
  begin
    FCrashToOffer := False;
    OfferCrashReport(True);
  end;
  TouchTick;

  FollowScreenSize;
  { the wheel has settled: the full frame }
  if FCameraMoving and not (FOrbiting or FPanning) and (GetTickCount64 - FLastWheel > 220) then
  begin
    FCameraMoving := False;
    RepaintPaper;
    RenderInk;
    RecomposeAll;
    Invalidate;
  end;
  ServiceMotion;
  ServiceHover;
  StepGlide(Dt);

  { the guide buttons follow the guide count, watched here since many places
    change it }
  if (FD.Doc.GuideCount <> FDeckGuides) then
  begin
    FDeckGuides := FD.Doc.GuideCount;
    RebuildDeck;
    pbDeck.Invalidate;
  end;

  { Four seconds up counts as a successful start, so a restored draft that
    crashes is not restored again. }
  if not FStartupDone then
  begin
    FUpTime := FUpTime + Dt;
    if (FUpdatedFrom <> '') and not FWhatsNewShown and (FUpTime > 0.5) then
    begin
      FWhatsNewShown := True;
      hsDialogSkin.UseTheme(Themes[FThemeIdx]);
      WhatsNewForm := TWhatsNewForm.Create(Self);
      try
        WhatsNewForm.ShowRelease(FUpdatedFrom, CurrentVersion);
      finally
        WhatsNewForm.Free;
      end;
    end;
    { last time's crash can be offered once there is a window }
    if (FUpTime > 1.5) and not FAskedAboutCrash then
    begin
      FAskedAboutCrash := True;
      OfferCrashReport(False);
      { Only then look for a newer build: asking during startup held the
        window back until the network answered or gave up. }
      CheckForUpdate(False);
      { and keep the manual beside the program in step }
      KeepHelpCurrent;
    end;
    { the postcard (hsPostcard): second start or later, only once, when
      nothing else is up }
    if (FUpTime > 3.0) and not FPostcardOffered and (Application.ModalLevel = 0) then
    begin
      FPostcardOffered := True;
      if PostcardDue then
      begin
        hsDialogSkin.UseTheme(Themes[FThemeIdx]);
        OfferPostcard(Self, CurrentVersion, False);
      end;
    end;
    if FUpTime > 4.0 then
      FStartupDone := True;
  end;

  { The stick under strain: held still it winds up; moved, it goes slack
    (a drag is changing your mind about where the point goes). }
  if FHoldOn then
  begin
    if (Abs(FMouseSX - FHoldX) > 5) or (Abs(FMouseSY - FHoldY) > 5) then
      FHoldT := 0
    else
    begin
      FHoldT := FHoldT + Dt;
      if FHoldT >= HOLD_BREAK then
      begin
        { It broke: let go of the run and place nothing. }
        FWasLine := FTool = ptLine;
        { the burst goes in the middle of what was destroyed; only a line
          gets its ends flying apart }
        FSnapEnds := FTool = ptLine;
        FSnapA := ScreenOf(FP1);
        FSnapB := PtF(FMouseSX, FMouseSY);
        if StrainOutline(BreakPts) and (Length(BreakPts) > 2) then
        begin
          FSnapM := PtF(0, 0);
          for BreakI := 0 to High(BreakPts) do
            FSnapM := PtF(FSnapM.X + BreakPts[BreakI].X / Length(BreakPts),
                          FSnapM.Y + BreakPts[BreakI].Y / Length(BreakPts));
        end
        else
          FSnapM := PtF((FSnapA.X + FSnapB.X) / 2, (FSnapA.Y + FSnapB.Y) / 2);
        FSnapT := SNAP_RECOIL;
        FHoldOn := False;
        ResetTool;
        FLockOn := False;
        FNoLockUntilMoved := True;
        FScreenDirty := True;
        if FWasLine then
          FCmdMsg := 'Snapped off.'
        else if FTool in [ptPush, ptDrill, ptOffset] then
          FCmdMsg := 'Let go - nothing was moved.'
        else
          FCmdMsg := 'Thrown away - nothing was drawn.';
      end;
      FScreenDirty := True;
    end;
  end;
  if FSnapT > 0 then
  begin
    FSnapT := FSnapT - Dt;
    if FSnapT < 0 then FSnapT := 0;
    FScreenDirty := True;
  end;

  { a draft a couple of seconds after the drawing stops changing, so a busy
    hand is never writing files }
  if FEditSeq <> FDraftSeq then
  begin
    Inc(FDraftAge);
    if FDraftAge > (2000 div TICK_MS) then SaveDraft;
  end;
  try

  if FErasing then
  begin
    StepErase(Dt);
    Exit;
  end;

  { keep the command bar caret blinking }
  if (GetTickCount64 div 500) <> ((GetTickCount64 - TICK_MS) div 500) then
    pbCmd.Invalidate;

  finally
    { one repaint per tick at most, and the camera drawn once for whatever
      moved it }
    FlushView;
    if FScreenDirty then
    begin
      FScreenDirty := False;
      pbScreen.Invalidate;
    end;
  end;
end;

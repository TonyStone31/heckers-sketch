{ hsMainForm - creating and closing the window.  Part of TMainForm; included by hsMainForm.pas }

{ ======================================================================== }
{ lifecycle                                                                 }
{ ======================================================================== }

{ Given to hsSurface so a repair lands in the trail beside the tool in hand. }
procedure SurfaceRepaired(const What: string);
begin
  if MainForm <> nil then MainForm.Trail(What);
  { and to stderr for a test-harness run; the trail is only read from a report }
  if GetEnvironmentVariable('HSK_TRACE') <> '' then
  begin
    WriteLn(StdErr, 'TRACE ', What);
    Flush(StdErr);
  end;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  I: Integer;
  A: string;
begin
  Application.OnException := @ReportCrash;
  FDimArc := -1;
  FExportDirs := TStringList.Create;
  Randomize;
  { one more start, for the postcard (see hsPostcard) }
  CountLaunch;
  FRunTag := IntToHex(GetTickCount64 and $FFFFFF, 6) + IntToHex(Random($10000), 4);
  for I := 1 to ParamCount do
  begin
    A := ParamStr(I);
    if Pos('--updated-from=', LowerCase(A)) = 1 then
      FUpdatedFrom := Copy(A, Length('--updated-from=') + 1, MaxInt);
  end;
  FillViewMenu;
  { real hover tooltips on the deck, not just the hint line }
  pbDeck.ShowHint := True;
  Application.ShowHint := True;
  Application.HintPause := 450;
  Application.HintHidePause := 6000;
  Randomize;
  hsSurface.OnSurfaceRepair := @SurfaceRepaired;
  { Before anything can be typed: zero is a valid entity index, so a default
    0 would mean "editing the first thing in the drawing". }
  FDimEdit := -1;
  FLenDenom := LenDenom;
  FNoteDrag := -1;
  FSidesCircle := 24;
  FQuickFrames := True;
  { the program uses workers; the tests and tools, which never render, do not }
  FStartedAt := GetTickCount64;
  FThreads := True;
  DefaultThreads := True;
  hsDrawing.Progress := @OnProgress;
  FSidesArc := 12;
  FCursorWas := crCross;
  Caption := APP_NAME + '  ' + CurrentVersion;
  FUIScale := EnsureRange(Screen.PixelsPerInch / 96, 1.0, 3.0);
  DoubleBuffered := True;

  FHintInShot := -1;
  FPaper := TArtSurface.Create(16, 16);
  FArt := TArtSurface.Create(16, 16);
  FInk := TArtSurface.Create(16, 16);
  FInkHalf := TArtSurface.Create(16, 16);
  FInk.PreserveAlpha := True;
  FShell := TArtSurface.Create(16, 16);
  FDeckSkin := TArtSurface.Create(16, 16);
  FCmdSkin := TArtSurface.Create(16, 16);
  FViewSkin := TArtSurface.Create(16, 16);
  FSliceSkin := TArtSurface.Create(16, 16);
  FToolSkin := TArtSurface.Create(16, 16);
  FInfoSkin := TArtSurface.Create(16, 16);
  FGrpSkin := TArtSurface.Create(16, 16);
  FGrpHot := -1;
  FGrpSig := -1;
  FQuickSkin := TArtSurface.Create(16, 16);
  FHotQuick := -1;
  FHotTool := -1;
  FToolsWide := True;
  FHotSlice := -1;
  FSliceEdit := 0;
  FGlyph := TArtSurface.Create(16, 16);
  FPopup := POP_NONE;
  FOverlay := TArtSurface.Create(16, 16);

  FRecent := TStringList.Create;
  NewDrawing(-1);
  FDimFont := TFont.Create;
  {$IFDEF WINDOWS}
  FDimFont.Name := 'Segoe UI';
  {$ELSE}
  FDimFont.Name := 'Sans';
  {$ENDIF}
  { dimensions carry an isometric drawing, so they are a size up from other
    labels }
  FDimFont.Height := -Round(13 * FUIScale);

  FThemeIdx := THEME_DARK;
  FEdgeW := 1;
  FMeasEdge := -1;
  FHotItem := -1;
  FHotView := -1;
  FHoverEnt := -1;
  FTool := ptSelect;
  FDirLock := -1;
FPushFace := -1;
  FReplayFace := -1;
  FOffFace := -1;
  FHoverFace := -1;

  LoadSettings;
  ApplyCommandLine;
  SetInk(FInkColor, FInkAuto);

  pbScreen.Cursor := crCross;
  pbDeck.Cursor := crHandPoint;

  tmrTick.Interval := TICK_MS;
  tmrTick.Enabled := True;
end;

{ Where the window is, read while the window still exists.  On Windows the
  handle is gone by OnDestroy and RestoredLeft and friends return garbage. }
procedure TMainForm.RememberWindow;
begin
  if not HandleAllocated then Exit;
  FWinMax := WindowState = wsMaximized;
  if WindowState = wsNormal then
  begin
    { A normal window knows where it is.  Restored* lags a beat after a move,
      so it would sometimes save the opening position. }
    FWinL := Left;
    FWinT := Top;
    FWinW := Width;
    FWinH := Height;
  end
  else
  begin
    { Maximized or full screen: ask what it will restore to.  Left and Width
      would be the screen size and it could never be made smaller. }
    FWinL := RestoredLeft;
    FWinT := RestoredTop;
    FWinW := RestoredWidth;
    FWinH := RestoredHeight;
  end;
  FWinSaved := (FWinW > 200) and (FWinH > 200);
end;

{ How many files have unsaved work.  A sheet nobody touched does not count;
  the starting example arrives with hundreds of entities. }
function TMainForm.AnyDirty: Integer;
var
  I, K: Integer;
  Seen: Boolean;
begin
  Result := 0;
  for I := 0 to High(FDrawings) do
  begin
    { each file once }
    Seen := False;
    for K := 0 to I - 1 do
      if FDrawings[K].DocKey = FDrawings[I].DocKey then Seen := True;
    if not Seen and DocDirty(FDrawings[I].DocKey) then Inc(Result);
  end;
end;

{ Closing the window asks about each file with unsaved work: Save, Don't
  save, or Cancel (window stays open).  Once all are answered the window
  closes clean and nothing is restored next time; Don't save means don't. }
procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  I, K: Integer;
  Keys: array of Integer;
  Seen: Boolean;
begin
  CanClose := True;
  { an update is taking over and already has the drawings (see DoUpdate) }
  if FHandingOver then Exit;
  Keys := nil;
  for I := 0 to High(FDrawings) do
  begin
    Seen := False;
    for K := 0 to High(Keys) do
      if Keys[K] = FDrawings[I].DocKey then Seen := True;
    if not Seen then
    begin
      SetLength(Keys, Length(Keys) + 1);
      Keys[High(Keys)] := FDrawings[I].DocKey;
    end;
  end;
  for K := 0 to High(Keys) do
    if not AskToSave(Keys[K], 'Close Heckers Sketch') then
    begin
      CanClose := False;
      Exit;
    end;
  FCleanExit := True;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  RememberWindow;
  { Record the source window now: by FormDestroy, where settings are written,
    every other form is hidden and it would always be saved as closed. }
  if SourceForm <> nil then
  begin
    FSourceWasOpen := SourceForm.Visible;
    FSourceOnTop := SourceForm.chkOnTop.Checked;
    if SourceForm.WindowState = wsNormal then
      FSourceBounds := Rect(SourceForm.Left, SourceForm.Top, SourceForm.Width, SourceForm.Height);
  end;
end;

{ --blank on the command line (see where it is used) }
function AskedForBlank: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if LowerCase(ParamStr(I)) = '--blank' then Result := True;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
var
  I: Integer;
begin
  { A clean exit drops the draft; it is only for a crash or a pulled plug.
    Handing over to an update, or any other exit, writes it so the work can
    be recovered. }
  if FCleanExit and not FHandingOver then DropDraft
  else if FEditSeq <> FDraftSeq then SaveDraft;
  { settings first: they write the recent files and the export folders }
  SaveSettings;
  FRecent.Free;
  FExportDirs.Free;
  FDimFont.Free;
  for I := High(FDrawings) downto 0 do
    FDrawings[I].Free;
  FOverlay.Free;
  FPaperBase.Free;
  FSelShot.Free;
  FViewSkin.Free;
  FSliceSkin.Free;
  FToolSkin.Free;
  FInfoSkin.Free;
  FGrpSkin.Free;
  FQuickSkin.Free;
  FGlyph.Free;
  FCmdSkin.Free;
  FCubeSkin.Free;
  FDeckSkin.Free;
  FShell.Free;
  FInk.Free;
  FInkHalf.Free;
  FArt.Free;
  FPaper.Free;
end;

procedure TMainForm.FormShow(Sender: TObject);
var
  I: Integer;
  Opened: Boolean;
begin
  if FBooted then Exit;
  FBooted := True;
  ApplyTheme;
  Relayout;
  FD.ViewX := Round(FArt.Width * 0.10);
  FD.ViewY := Round(FArt.Height * 0.88);
  FCur := P3(0, 0, 0);
  LayoutTabs;
  FreshScreen;

  { a file on the command line opens straight away; scan for it so a switch
    in front of it does not hide it }
  Opened := False;
  for I := 1 to ParamCount do
    if (Copy(ParamStr(I), 1, 1) <> '-') and FileExists(ParamStr(I)) then
    begin
      Opened := OpenFile(ParamStr(I));
      Break;
    end;
  { --blank: start on an empty sheet and ask nothing about last time (handy
    for tests and scripts).  An existing draft is copied aside first so no
    work is lost. }
  if AskedForBlank then
  begin
    if FileExists(DraftFile) then
      CopyFile(DraftFile, ChangeFileExt(DraftFile, '') + '-before-blank.hsk',
        [cffOverwriteFile]);
    DropDraft;
    Opened := True;
    Trail('started blank (--blank)');
  end;
  { After an update, restore what the old copy handed over.  Any other time
    a leftover handoff is from an update that never started, and the draft
    is at least as new, so it goes. }
  if not Opened and (FUpdatedFrom <> '') then Opened := RestoreHandoff;
  if FileExists(HandoffFile) then DeleteFile(HandoffFile);
  if Opened and (FUpdatedFrom <> '') then DropDraft;
  { A draft means the last run did not close properly.  It is offered on the
    tick once the window is up, not loaded, and no dialog may appear here
    (see below). }
  if not Opened and FileExists(DraftFile) then FRecoverToOffer := True;
  { Otherwise start on an empty drawing: not the example, not the last
    drawing.  The example is on the menu. }
  WriteExamples;
  WriteJigs;
  SplashLoaded(LoadedWords);
  { fingers on the drawing, where the platform gives them to us }
  FTouchOn := HookTouch(Self, @OnTouch);
  Trail('touch hook: ' + BoolToStr(FTouchOn, True));

  { Housekeeping from last time.  No dialogs here: the window has not
    painted yet, so a dialog would sit over a black rectangle, look hung and
    get force-quit, which causes another crash report.  Crash offers wait for
    the tick. }
  ForgetPreviousBuild;
  { reopen the source window now with the main window, not on the later tick }
  if FSourceWasOpen then
  begin
    ShowSource;
    BringToFront;
  end;
end;

{ Command-line window switches.  They override the saved size, since a
  launcher is not a person.  Unknown arguments are ignored, never fatal. }
procedure TMainForm.ApplyCommandLine;
var
  I, X: Integer;
  A, V: string;
  W, H: Integer;
begin
  for I := 1 to ParamCount do
  begin
    A := LowerCase(ParamStr(I));
    if (A = '--maximized') or (A = '--maximised') or (A = '-max') then
    begin
      FFill := flMaximized;
      WindowState := wsMaximized;
    end
    else if (A = '--fullscreen') or (A = '-full') then
    begin
      { Not BorderStyle := bsNone: GTK marks borderless windows not resizable
        and pins the X size hints, so a remote display that changes size (as
        KasmVNC does) cannot resize it.  Ask the window manager for full
        screen and set the bounds too, for when there is no window manager. }
      FFill := flFull;
      WindowState := wsFullScreen;
      SetBounds(Monitor.Left, Monitor.Top, Monitor.Width, Monitor.Height);
    end
    else if Copy(A, 1, 7) = '--size=' then
    begin
      { --size=1600x1000 }
      V := Copy(A, 8, MaxInt);
      X := Pos('x', V);
      if X > 1 then
      begin
        W := StrToIntDef(Copy(V, 1, X - 1), 0);
        H := StrToIntDef(Copy(V, X + 1, MaxInt), 0);
        if (W > 320) and (H > 240) then
        begin
          FFill := flNone;
          WindowState := wsNormal;
          SetBounds(Left, Top, W, H);
          Position := poScreenCenter;
        end;
      end;
    end
    { --help is answered in the program file, before any of this exists }
  end;
end;

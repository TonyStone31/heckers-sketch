{ hsMainForm - settings.  Part of TMainForm; included by hsMainForm.pas }

{ ======================================================================== }
{ settings                                                                  }
{ ======================================================================== }

{ The drawing as a Heck file (see hsHeckFile): the sheets asked for, each
  with its view and camera, and in a session its file and document too.  The
  camera goes along so a drawing (or a report's drawing) opens as it was
  being looked at. }
procedure TMainForm.BuildSession(L: TStrings; Session: Boolean; Key: Integer; Quick: Boolean;
  ShownFirst: Boolean);
var
  I, K: Integer;
  Sheets: THeckSheets;
  S: THeckSheet;
begin
  Sheets := nil;
  for K := 0 to High(FDrawings) do
  begin
    { for a report, the sheet on screen goes first: the collector takes the
      first sheet as the report's drawing }
    I := K;
    if ShownFirst and (FTabIdx >= 0) and (FTabIdx <= High(FDrawings)) then
    begin
      if K = 0 then I := FTabIdx
      else if K <= FTabIdx then I := K - 1;
    end;
    if not Session and (Key >= 0) and (FDrawings[I].DocKey <> Key) then Continue;
    S := Default(THeckSheet);
    S.Name := FDrawings[I].Name;
    S.Doc := FDrawings[I].Doc;       { lent, not copied }
    S.Units := FDrawings[I].Units;
    S.ScaleIdx := FDrawings[I].ScaleIdx;
    S.SnapIdx := FDrawings[I].SnapIdx;
    S.View := FDrawings[I].View;
    S.CamKnown := True;
    S.Az := FDrawings[I].Az; S.El := FDrawings[I].El; S.Zoom := FDrawings[I].Zoom;
    S.ViewX := FDrawings[I].ViewX; S.ViewY := FDrawings[I].ViewY;
    S.SliceOn := FDrawings[I].SliceOn;
    S.SliceLo := FDrawings[I].SliceLo; S.SliceHi := FDrawings[I].SliceHi;
    S.HasSession := Session;
    S.DocKey := FDrawings[I].DocKey;
    S.FilePath := FDrawings[I].FilePath;
    S.DocName := FDrawings[I].DocName;
    S.Dirty := FDrawings[I].Dirty;
    SetLength(Sheets, Length(Sheets) + 1);
    Sheets[High(Sheets)] := S;
  end;
  WriteHeckFile(Sheets, L, Session, Quick);
end;

{ Long work reports progress here: on the splash (with its skip button)
  while that is up, otherwise on the command bar by letting messages through,
  which is why every input handler checks FBusy.  False means the skip was
  pressed. }
function TMainForm.OnProgress(const What: string; Frac: Double): Boolean;
var
  T: QWord;
begin
  Result := True;
  if SplashUp then
  begin
    SplashStatus(What, Frac, FLoading);
    if SplashSkipAsked then
    begin
      FLoadSkipped := True;
      Result := False;
    end;
    Exit;
  end;
  T := GetTickCount64;
  { A full repaint costs 100 ms or more on a big drawing and this is called
    every few dozen regions, so paint at most every quarter second, longer
    when the last paint was slow. }
  if FBusy and (T - FBusyAt < Max(250, 4 * FBusyPaintMs)) then Exit;
  FBusy := True;
  FBusyAt := T;
  FBusyMsg := What;
  FBusyFrac := Frac;
  { Invalidate and ProcessMessages are not enough: GTK3 paints on its frame
    clock, which a busy main thread never reaches.  Repaint on the bar's
    parent forces the paint through (gdk_window_process_updates). }
  Application.ProcessMessages;
  pbCmd.Invalidate;
  if pbCmd.Parent <> nil then pbCmd.Parent.Repaint;
  Application.ProcessMessages;
  FBusyPaintMs := GetTickCount64 - T;
  FBusyAt := GetTickCount64;
end;

{ what the splash says when loading is over }
function TMainForm.LoadedWords: string;
var
  I, N: Integer;
begin
  if FLoadSkipped then Exit('Skipped that drawing - starting with a clean sheet.');
  N := 0;
  for I := 0 to High(FDrawings) do N := N + FDrawings[I].Doc.Live;
  if N = 0 then Exit('Ready.');
  if Length(FDrawings) = 1 then
    Result := Format('Ready.  %d things on one sheet.', [N])
  else
    Result := Format('Ready.  %d things on %d sheets.', [N, Length(FDrawings)]);
end;

procedure TMainForm.EndBusy;
begin
  if not FBusy then Exit;
  FBusy := False;
  pbCmd.Invalidate;
end;

{ Drop the draft.  It is a net under unsaved work, not a record of what the
  user wants back, so finishing with a drawing must clear it too or the next
  launch brings it back. }
procedure TMainForm.DropDraft;
begin
  try
    if FileExists(DraftFile) then DeleteFile(DraftFile);
  except
    on E: Exception do ;
  end;
  FDraftSeq := FEditSeq;
end;

{ Keep a draft of all unsaved work, named or not, so a crash loses nothing.
  Written to a temporary and renamed, so a crash mid-write cannot spoil it. }
procedure TMainForm.SaveDraft;
var
  L: TStringList;
  Tmp: string;
begin
  if Length(FDrawings) = 0 then Exit;
  { nothing unsaved, nothing to recover }
  if AnyDirty = 0 then
  begin
    DropDraft;
    Exit;
  end;
  { All of it is wrapped: a background autosave must never take the program
    down.  Whatever fails, the seq is marked done so it does not retry every
    tick. }
  try
    L := TStringList.Create;
    try
      BuildSession(L, True, -1, True);
      { A temporary unique to this run, so two copies of the program cannot
        interleave writes into one file.  Rename straight over the target
        first (atomic on Unix); only if that fails remove the target first,
        as Windows needs. }
      Tmp := DraftFile + '.' + FRunTag + '.tmp';
      ForceDirectories(ExtractFilePath(DraftFile));
      L.SaveToFile(Tmp);
      if not RenameFile(Tmp, DraftFile) then
      begin
        if FileExists(DraftFile) then DeleteFile(DraftFile);
        if not RenameFile(Tmp, DraftFile) then DeleteFile(Tmp);
      end;
    finally
      L.Free;
    end;
  except
    on E: Exception do
      FCmdMsg := 'Could not keep a draft just now (' + E.ClassName + ')';
  end;
  FDraftSeq := FEditSeq;
end;

{ Drafts left by a run that did not close properly (crash, kill, pulled
  plug), offered back.  A clean close drops the draft, so one found at start
  is unanswered work.  Declined, it is kept aside rather than thrown away. }
procedure TMainForm.OfferRecovery;
var
  Ans: Integer;
  Aside: string;
begin
  if not FileExists(DraftFile) then Exit;
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  Ans := QuestionDlg('Recover your drawings',
    'Heckers Sketch did not close properly last time, and kept a copy of the drawings that had work not ' +
    'saved yet.  Recover them?',
    mtConfirmation,
    [mrYes, 'Recover them', 'IsDefault',
     mrNo, 'Start without them', 'IsCancel'], 0);
  if Ans = mrYes then
  begin
    RestoreDraft;
    RefreshChrome;
    pbCmd.Invalidate;
    Exit;
  end;
  Aside := ChangeFileExt(DraftFile, '') + '-not-recovered.hsk';
  if FileExists(Aside) then DeleteFile(Aside);
  RenameFile(DraftFile, Aside);
  FCmdMsg := 'Not recovered.  A copy is kept beside the settings as ' + ExtractFileName(Aside) +
    ', and can be opened.';
  pbCmd.Invalidate;
end;

{ Read the draft back once OfferRecovery says to: each file with unsaved work
  as the file it was, path and sheets, still unsaved so Save writes it back. }
function TMainForm.RestoreDraft: Boolean;
var
  L: TStringList;
  Aside: string;
  Ini: TIniFile;
  First, I, N: Integer;
  Blank: TDrawing;
begin
  Result := False;
  if not FileExists(DraftFile) then Exit;
  { an empty draft is not worth restoring }
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(DraftFile);
    except
      Exit;
    end;
    if L.Count < 3 then Exit;
  finally
    L.Free;
  end;

  { If the flag is still set, the last run died reading this draft, and
    restoring it again would loop forever.  Set it aside (kept) and start
    clean. }
  Ini := TIniFile.Create(ConfigFile);
  try
    if Ini.ReadBool('startup', 'restoring', False) then
    begin
      { kept under a name the Open dialog can see }
      Aside := ChangeFileExt(DraftFile, '') + '-would-not-open.hsk';
      if FileExists(Aside) then DeleteFile(Aside);
      RenameFile(DraftFile, Aside);
      Ini.WriteBool('startup', 'restoring', False);
      Ini.WriteInteger('startup', 'crashes', 0);
      FCmdMsg := 'The last drawing would not open - it is kept beside the ' +
        'settings as ' + ExtractFileName(Aside) + ' and can be opened.';
      Exit;
    end;

    { Two crashes in a row with this drawing open: it opens fine but kills
      the program later, every time.  Stand it down instead of loading it a
      third time; it is kept and named on screen. }
    if Ini.ReadInteger('startup', 'crashes', 0) >= 2 then
    begin
      Aside := ChangeFileExt(DraftFile, '') + '-crashed.hsk';
      if FileExists(Aside) then DeleteFile(Aside);
      RenameFile(DraftFile, Aside);
      Ini.WriteInteger('startup', 'crashes', 0);
      FCmdMsg := 'It crashed twice with the last drawing open, so this run ' +
        'starts empty.  The drawing is kept as ' + ExtractFileName(Aside) +
        ' - open it when you want it.';
      Exit;
    end;
    Ini.WriteBool('startup', 'restoring', True);
  finally
    Ini.Free;
  end;

  { a draft is read before anything else happens, so a bad one must not
    take the program down on the way up }
  Blank := nil;
  if (Length(FDrawings) = 1) and (FDrawings[0].FilePath = '') and not FDrawings[0].Dirty and
     (FDrawings[0].Doc.Live = 0) then Blank := FDrawings[0];
  try
    try
      if not ReadSheets(DraftFile, True, First) then Exit;
    except
      on E: Exception do
      begin
        FCmdMsg := 'The last draft would not load (' + E.ClassName +
          ') - starting empty.';
        Exit;
      end;
    end;
  finally
    { The flag means "reading a draft", which stops being true the moment the
      read returns, however it went.  Clearing it on a timer instead made a
      quick close look like a crash while reading.  Later failures are the
      crash counter's job. }
    with TIniFile.Create(ConfigFile) do
    try
      WriteBool('startup', 'restoring', False);
    finally
      Free;
    end;
  end;
  if FLoadSkipped then
  begin
    { skipped on the splash: keep it aside under an openable name, or it
      returns next time and is overwritten by the first new line }
    Aside := ChangeFileExt(DraftFile, '') + '-skipped.hsk';
    if FileExists(Aside) then DeleteFile(Aside);
    RenameFile(DraftFile, Aside);
    FCmdMsg := 'Skipped loading the last drawing.  It is kept beside the ' +
      'settings as ' + ExtractFileName(Aside) + ' and can be opened.';
    Exit;
  end;
  { the empty drawing the program started with gives way }
  if Blank <> nil then
  begin
    LeaveSheet;
    for I := 0 to High(FDrawings) - 1 do FDrawings[I] := FDrawings[I + 1];
    SetLength(FDrawings, Length(FDrawings) - 1);
    Blank.Free;
    FD := nil;
    Dec(First);
  end;
  ShowLoaded(First);
  { each comes back as the file it was, its unsaved work still unsaved, so
    Save writes it back and closing asks }
  N := AnyDirty;
  FRestored := True;
  Result := True;
  Inc(FEditSeq);
  Trail(Format('recovered a draft: %d tabs, %d files not saved', [Length(FDrawings), N]));
  FCmdMsg := Format('Recovered %d drawing%s - save %s to keep %s.', [N, IfThen(N = 1, '', 's'),
    IfThen(N = 1, 'it', 'them'), IfThen(N = 1, 'it', 'them')]);
end;

{ The jigs the program carries, put in the jigs folder by the examples' rule:
  one changed there is the user's and is left alone. }
procedure TMainForm.WriteJigs;
var
  Ini: TIniFile;
  L: TStringList;
  I: Integer;
  Rec: string;
begin
  try
    Ini := TIniFile.Create(ConfigFile);
    L := TStringList.Create;
    try
      for I := 0 to JigFileCount - 1 do
      begin
        L.Clear;
        JigFileLines(I, L);
        Rec := Ini.ReadString('jigs', JigFileName(I), '');
        case PutCarried(JigsDir + JigFileName(I), L, Rec) of
          ewWritten, ewUpToDate:
            Ini.WriteString('jigs', JigFileName(I), Rec);
          ewKeptTheirs:
            Trail('jig ' + JigFileName(I) + ' has been changed here - left alone');
        end;
      end;
    finally
      L.Free;
      Ini.Free;
    end;
  except
    on E: Exception do ;
  end;
end;

{ Put the example drawings on disk beside the program, to reopen, share or
  read.  Each is checked against what was written last (see PutExample): one
  saved over since is left alone; an untouched one gets the newer version.
  Delete your copy to get the original back. }
procedure TMainForm.WriteExamples;
var
  Ini: TIniFile;
  I: Integer;
  Rec: string;
begin
  try
    if not ForceDirectories(ExamplesDir) then Exit;
    Ini := TIniFile.Create(ConfigFile);
    try
      for I := 0 to ExampleCount - 1 do
      begin
        Rec := Ini.ReadString('examples', ExampleFile(I), '');
        case PutExample(I, ExamplesDir, Rec) of
          ewWritten, ewUpToDate:
            Ini.WriteString('examples', ExampleFile(I), Rec);
          ewKeptTheirs:
            Trail('example ' + ExampleFile(I) + ' has been changed here - left alone');
        end;
      end;
    finally
      Ini.Free;
    end;
  except
    { a read-only folder, a full disk, a pulled stick: not worth a word }
    on E: Exception do ;
  end;
end;

{ The example drawing (Open the Example on the menu): an etch-a-sketch to
  orbit, push and poke at.  It arrives as an unsaved drawing, not a file, so
  Ctrl+S asks where and the example on disk is never overwritten. }
function TMainForm.LoadExample: Boolean;
var
  L: TStringList;
  Sheets: THeckSheets;
  I, ErrLine: Integer;
  Err: string;
begin
  Result := False;
  Sheets := nil;
  L := TStringList.Create;
  try
    try
      ExampleDrawing(L);
      { carried as Heck, as written out (see hsHeckFile) }
      if not ReadDrawingFile(L, Sheets, ErrLine, Err) or (Length(Sheets) = 0) then Exit;
      FD.Name := Sheets[0].Name;
      FD.Doc.Free;
      FD.Doc := Sheets[0].Doc;
      Sheets[0].Doc := nil;
      for I := 1 to High(Sheets) do Sheets[I].Doc.Free;
    except
      { an example that will not load is not worth crashing for }
      on E: Exception do Exit;
    end;
  finally
    L.Free;
  end;
  if FD.Doc.Live = 0 then Exit;
  FD.View := vkOrbit;
  FD.Az := -0.785398;
  FD.El := 0.700000;
  FD.ScaleIdx := 4;
  FD.SnapIdx := 1;
  { a drawing of its own, not a file: Save asks where it goes }
  FD.DocName := FD.Name;
  { not the user's work until they change it, so not unsaved }
  FD.Dirty := False;
  { as when opening a file: its faces say which areas are filled, so seed
    them as seen or the first rebuild works over faces that were right }
  SeedRegions;
  Result := True;
  FitView(False);
  Trail(Format('opened the example: %d things', [FD.Doc.Live]));
  FCmdMsg := 'This is the example drawing - orbit it, push a face, or ' +
    'press Ctrl+N to start your own.';
end;

{ Is a window at this place reachable?  Every monitor is asked (a monitor
  left of or above the primary has negative coordinates), and enough of the
  window must land on one to grab and drag. }
function TMainForm.OnAScreen(L, T, W, H: Integer): Boolean;
var
  I: Integer;
  R, X: TRect;
begin
  Result := False;
  R := Rect(L, T, L + W, T + H);
  for I := 0 to Screen.MonitorCount - 1 do
    if IntersectRect(X, R, Screen.Monitors[I].WorkareaRect) and
       (X.Right - X.Left >= 160) and (X.Bottom - X.Top >= 80) then
      Exit(True);
end;

{ The drawing settings, from the section older builds called pro when they
  have not been saved under the new name yet. }
function DrawingInt(Ini: TIniFile; const Key: string; Dflt: Integer): Integer;
begin
  Result := Ini.ReadInteger('drawing', Key, Ini.ReadInteger('pro', Key, Dflt));
end;

procedure TMainForm.LoadSettings;
var
  Ini: TIniFile;
  WW, WH, WL, WT, I: Integer;
begin
  FInkColor := PALETTE[0];
  FInkAuto := True;
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      hsRecorder.RecentWalks := Ini.ReadString('export', 'recentwalks', '');
      { commands used lately, so the list offers them first }
      FCmdRecent := Ini.ReadString('cmd', 'recent', '');
      { where things went last time; exports as "ext=folder" lines per kind }
      FSaveDir := Ini.ReadString('paths', 'drawings', '');
      FRecent.Clear;
      for I := 1 to 10 do
        if Ini.ReadString('recent', 'file' + IntToStr(I), '') <> '' then
          FRecent.Add(Ini.ReadString('recent', 'file' + IntToStr(I), ''));
      FOpenDir := Ini.ReadString('paths', 'open', '');
      FExportDirs.Clear;
      Ini.ReadSectionValues('exportpaths', FExportDirs);
      FCubeOn := Ini.ReadBool('look', 'cube', False);
      CameraLamp := Ini.ReadBool('look', 'cameralamp', True);
      FSourceWasOpen := Ini.ReadBool('source', 'open', False);
      FSourceOnTop := Ini.ReadBool('source', 'ontop', False);
      FSourceComplete := Ini.ReadBool('source', 'complete', True);
      FSourceBounds := Rect(Ini.ReadInteger('source', 'left', 0), Ini.ReadInteger('source', 'top', 0),
        Ini.ReadInteger('source', 'width', 0), Ini.ReadInteger('source', 'height', 0));
      FInfoOn := Ini.ReadBool('look', 'info', False);
      FGroupsOn := Ini.ReadBool('look', 'groups', True);
      FCubeCorner := EnsureRange(Ini.ReadInteger('look', 'cubecorner', 1), 0, 3);
      FCubeFitSel := Ini.ReadBool('look', 'cubefit', True);
      { by name, so the list can change; older builds kept an index under
        protheme, 4 for Light and 5 for Dark }
      FThemeIdx := ThemeNamed(Ini.ReadString('look', 'themename', ''));
      if (FThemeIdx < 0) and (Ini.ReadInteger('look', 'protheme', 5) = 4) then
        FThemeIdx := THEME_LIGHT;
      if FThemeIdx < 0 then FThemeIdx := THEME_DARK;
      { the measured grid is off until asked for, like SketchUp; a saved
        setting is kept }
      FShowGrid := Ini.ReadBool('look', 'grid', False);
      FEdgeW := EnsureRange(DrawingInt(Ini, 'linew', 1), MIN_PEN, MAX_PEN);
      FInkColor := TColor(Ini.ReadInteger('pen', 'ink', PALETTE[0]));
      FInkAuto := Ini.ReadBool('pen', 'inkauto', True);
      { tool names on by default, for first-timers }
      FToolsWide := Ini.ReadBool('drawing', 'toolnames',
        Ini.ReadBool('pro', 'toolnames', True));
      FD.ScaleIdx := EnsureRange(DrawingInt(Ini, 'scale', 2), 0, SCALE_COUNT - 1);
      FD.SnapIdx := EnsureRange(DrawingInt(Ini, 'snap', 5), 0, SNAP_COUNT - 1);
      SetLenDenom(DrawingInt(Ini, 'precision', 16));
      FLenDenom := LenDenom;
      FD.Units := TUnitSystem(EnsureRange(DrawingInt(Ini, 'units', 0), 0, 1));
      { the view is deliberately not restored }

      { Where the window was, only if it still lands on a screen (monitors get
        unplugged), and the size clamped to what the screen can show. }
      WW := Ini.ReadInteger('win', 'w', 0);
      WH := Ini.ReadInteger('win', 'h', 0);
      WL := Ini.ReadInteger('win', 'x', MaxInt);
      WT := Ini.ReadInteger('win', 'y', MaxInt);
      if (WW > 200) and (WH > 200) then
      begin
        WW := Min(WW, Screen.DesktopWidth);
        WH := Min(WH, Screen.DesktopHeight);
      end
      else
      begin
        { First run on this machine: the design size is 96 dpi pixels, scaled
          up here once since the chrome scales itself.  Only here: the form's
          Scaled is off, or a saved size would grow by the factor every run. }
        WW := Round(Width * FUIScale);
        WH := Round(Height * FUIScale);
        WW := Min(WW, Screen.DesktopWidth);
        WH := Min(WH, Screen.DesktopHeight);
      end;
      if (WL <> MaxInt) and (WT <> MaxInt) and OnAScreen(WL, WT, WW, WH) then
      begin
        { poDesigned, or the widget set centers the window at first show
          despite SetBounds }
        Position := poDesigned;
        SetBounds(WL, WT, WW, WH);
      end
      else
      begin
        SetBounds(Left, Top, WW, WH);
        Position := poScreenCenter;
      end;
      if Ini.ReadBool('win', 'max', False) then
        WindowState := wsMaximized;
    finally
      Ini.Free;
    end;
  except
    { first run, or a read-only config dir: the defaults are fine }
  end;
end;

procedure TMainForm.SaveSettings;
var
  Ini: TIniFile;
  I: Integer;
begin
  try
    ForceDirectories(ExtractFilePath(ConfigFile));
    Ini := TIniFile.Create(ConfigFile);
    try
      Ini.WriteBool('look', 'cube', FCubeOn);
      Ini.WriteBool('look', 'cameralamp', CameraLamp);
      { the source window: whether it was open, and where }
      Ini.WriteBool('source', 'open', FSourceWasOpen);
      Ini.WriteBool('source', 'ontop', FSourceOnTop);
      Ini.WriteBool('source', 'complete', FSourceComplete);
      if FSourceBounds.Right > 0 then
      begin
        Ini.WriteInteger('source', 'left', FSourceBounds.Left);
        Ini.WriteInteger('source', 'top', FSourceBounds.Top);
        Ini.WriteInteger('source', 'width', FSourceBounds.Right);
        Ini.WriteInteger('source', 'height', FSourceBounds.Bottom);
      end;
      Ini.WriteBool('look', 'info', FInfoOn);
      Ini.WriteBool('look', 'groups', FGroupsOn);
      Ini.WriteInteger('look', 'cubecorner', FCubeCorner);
      Ini.WriteBool('look', 'cubefit', FCubeFitSel);
      Ini.WriteString('look', 'themename', Theme.Name);
      Ini.WriteBool('look', 'grid', FShowGrid);
      Ini.WriteInteger('drawing', 'linew', FEdgeW);
      Ini.WriteInteger('pen', 'ink', FInkColor);
      Ini.WriteBool('pen', 'inkauto', FInkAuto);
      Ini.WriteBool('drawing', 'toolnames', FToolsWide);
      Ini.WriteInteger('drawing', 'scale', FD.ScaleIdx);
      { camera moves used lately, so the list offers them first }
      Ini.WriteString('export', 'recentwalks', hsRecorder.RecentWalks);
      Ini.WriteString('cmd', 'recent', FCmdRecent);
      Ini.WriteString('paths', 'drawings', FSaveDir);
      Ini.EraseSection('recent');
      for I := 0 to FRecent.Count - 1 do
        Ini.WriteString('recent', 'file' + IntToStr(I + 1), FRecent[I]);
      Ini.WriteString('paths', 'open', FOpenDir);
      Ini.EraseSection('exportpaths');
      for I := 0 to FExportDirs.Count - 1 do
        if FExportDirs.Names[I] <> '' then
          Ini.WriteString('exportpaths', FExportDirs.Names[I],
            FExportDirs.ValueFromIndex[I]);
      Ini.WriteInteger('drawing', 'snap', FD.SnapIdx);
      Ini.WriteInteger('drawing', 'precision', FLenDenom);
      Ini.WriteInteger('drawing', 'units', Ord(FD.Units));

      { The window position was taken in OnClose; if the form never closed,
        this is the last chance and may get nothing, in which case the old
        position stays.  Reaching here means no crash, so reset the tally. }
      Ini.WriteInteger('startup', 'crashes', 0);

      if not FWinSaved then RememberWindow;
      if FWinSaved then
      begin
        Ini.WriteBool('win', 'max', FWinMax);
        Ini.WriteInteger('win', 'x', FWinL);
        Ini.WriteInteger('win', 'y', FWinT);
        Ini.WriteInteger('win', 'w', FWinW);
        Ini.WriteInteger('win', 'h', FWinH);
      end;
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  except
    { never let a settings problem stop the program closing }
  end;
end;

{ what /sysinfo shows (see hsFacts) }
procedure TMainForm.ShowFacts(const Title, AText: string);
begin
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  ShowFactsBox(Self, Title, AText);
end;

{ a long report section, to read and copy (see hsLongText) }
procedure TMainForm.ShowLongText(const Title, AText: string);
begin
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  if TLongTextForm.ShowText(Self, Title, AText) then FCmdMsg := 'Copied.';
end;

{ the about box (see hsAbout) }
procedure TMainForm.ShowAbout;
begin
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  ShowAboutBox(Self);
end;

initialization
  OnGetApplicationName := @SketchAppName;

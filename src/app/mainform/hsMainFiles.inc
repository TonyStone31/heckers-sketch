{ hsMainForm - documents: open, save, export.  Part of TMainForm; included by hsMainForm.pas }

{ ======================================================================== }
{ documents: open, save, export                                             }
{ ======================================================================== }

procedure TMainForm.DoOpen;
begin
  dlgOpen.Filter := 'Heckers Sketch drawing|*.hsk|All files|*.*';
  dlgOpen.DefaultExt := '.hsk';
  dlgOpen.InitialDir := OpenDirNow;
  if not dlgOpen.Execute then Exit;
  FOpenDir := ExtractFileDir(dlgOpen.FileName);
  OpenFile(dlgOpen.FileName);
end;

{ Open a file as a document of its own, its sheets in tabs after the others.
  If it is already open its tab comes to the front.  The untouched empty
  starting drawing gives way to it. }
function TMainForm.OpenFile(const FileName: string): Boolean;
var
  Full: string;
  I, First, N: Integer;
  Blank: TDrawing;
begin
  Result := False;
  Full := ExpandFileName(FileName);
  for I := 0 to High(FDrawings) do
    if (FDrawings[I].FilePath <> '') and SameFileName(FDrawings[I].FilePath, Full) then
    begin
      SelectDrawing(I);
      FCmdMsg := ExtractFileName(Full) + ' is open already - here it is.';
      pbCmd.Invalidate;
      Exit(True);
    end;
  Blank := nil;
  if (Length(FDrawings) = 1) and (FDrawings[0].FilePath = '') and not FDrawings[0].Dirty and
     (FDrawings[0].Doc.Live = 0) then Blank := FDrawings[0];
  if not ReadSheets(Full, False, First) then Exit;
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
  RememberRecent(Full);
  N := Length(DocSheets(FDrawings[First].DocKey));
  FCmdMsg := 'Opened ' + ExtractFileName(Full) +
    IfThen(N > 1, Format(' - %d sheets in this file, a tab each', [N]), '');
  Result := True;
end;

{ A file's sheets added after the existing tabs; First is the first new one.
  Session: a draft or handoff carrying every open file, with a comment before
  each sheet naming its document, file and saved state.  Otherwise the file
  is one document whose sheets share its path and name. }
function TMainForm.ReadSheets(const FileName: string; Session: Boolean; out First: Integer): Boolean;
var
  L: TStringList;
  Sheets: THeckSheets;
  I, K, Base, NewKey, ErrLine: Integer;
  Err: string;
  D, Was: TDrawing;
  KeyFrom, KeyTo: array of Integer;
begin
  Result := False;
  First := Length(FDrawings);
  Base := First;
  Was := FD;
  KeyFrom := nil; KeyTo := nil;
  Sheets := nil;
  Inc(FNextDocKey);
  NewKey := FNextDocKey;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(FileName);
    except
      on E: Exception do
      begin
        MessageDlg('Could not open', E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
    FLoading := True;
    FLoadSkipped := False;
    SplashSkipReset;
    OnProgress('Reading ' + ExtractFileName(FileName), 0);
    { Heck only: the old line format is refused with a note on converting it
      (see hsHeckFile) }
    try
      Result := ReadDrawingFile(L, Sheets, ErrLine, Err);
    except
      on E: Exception do
      begin
        Result := False;
        Err := E.Message;
        ErrLine := -1;
      end;
    end;
    if not Result or FLoadSkipped then
    begin
      for I := 0 to High(Sheets) do Sheets[I].Doc.Free;
      FLoading := False;
      EndBusy;
      if FLoadSkipped then
      begin
        Trail('skipped loading ' + FileName);
        FCmdMsg := 'Loading ' + ExtractFileName(FileName) +
          ' was skipped.  The file is untouched, and can be opened.';
      end
      else
        MessageDlg('Could not open', ExtractFileName(FileName) + ' will not read' +
          IfThen(ErrLine >= 0, Format(' - line %d', [ErrLine + 1]), '') + ':' + LineEnding + LineEnding + Err,
          mtError, [mbOK], 0);
      Exit(False);
    end;
    { a drawing with no sheet in it is one empty sheet }
    if Length(Sheets) = 0 then
    begin
      SetLength(Sheets, 1);
      Sheets[0] := NewHeckSheet('Sheet 1');
    end;
    for I := 0 to High(Sheets) do
    begin
      D := TDrawing.Create(Sheets[I].Name);
      D.Doc.Free;
      D.Doc := Sheets[I].Doc;
      D.Units := Sheets[I].Units;
      D.ScaleIdx := Sheets[I].ScaleIdx;
      D.SnapIdx := Sheets[I].SnapIdx;
      D.View := Sheets[I].View;
      D.SliceOn := Sheets[I].SliceOn;
      D.SliceLo := Sheets[I].SliceLo;
      D.SliceHi := Sheets[I].SliceHi;
      if Sheets[I].CamKnown then
      begin
        D.Az := Sheets[I].Az; D.El := Sheets[I].El;
        D.Zoom := EnsureRange(Sheets[I].Zoom, ZOOM_MIN, ZOOM_MAX);
        D.ViewX := Sheets[I].ViewX; D.ViewY := Sheets[I].ViewY;
        D.CamKnown := True;
      end;
      if Session and Sheets[I].HasSession then
      begin
        { the session's document keys are the old run's: one new key each }
        D.DocKey := -1;
        for K := 0 to High(KeyFrom) do
          if KeyFrom[K] = Sheets[I].DocKey then D.DocKey := KeyTo[K];
        if D.DocKey < 0 then
        begin
          Inc(FNextDocKey);
          D.DocKey := FNextDocKey;
          SetLength(KeyFrom, Length(KeyFrom) + 1); KeyFrom[High(KeyFrom)] := Sheets[I].DocKey;
          SetLength(KeyTo, Length(KeyTo) + 1); KeyTo[High(KeyTo)] := D.DocKey;
        end;
        D.FilePath := Sheets[I].FilePath;
        D.DocName := Sheets[I].DocName;
        if D.DocName = '' then
          if D.FilePath <> '' then D.DocName := ChangeFileExt(ExtractFileName(D.FilePath), '')
          else
          begin
            Inc(FUntitled);
            D.DocName := Format('Untitled %d', [FUntitled]);
          end;
        D.Dirty := Sheets[I].Dirty;
      end
      else
      begin
        D.DocKey := NewKey;
        D.FilePath := FileName;
        D.DocName := ChangeFileExt(ExtractFileName(FileName), '');
        D.Dirty := False;
      end;
      SetLength(FDrawings, Length(FDrawings) + 1);
      FDrawings[High(FDrawings)] := D;
    end;
    { Work out each sheet's flat areas.  A file with faces says which areas
      are filled, including ones emptied on purpose, so its areas are taken as
      seen and no face is invented.  A file with no faces gets them computed. }
    for I := Base to High(FDrawings) do
    begin
      if Length(FDrawings) - Base > 1 then
        OnProgress(Format('Working out the faces on sheet %d of %d', [I - Base + 1, Length(FDrawings) - Base]), -1)
      else
        OnProgress('Working out the faces', -1);
      FD := FDrawings[I];
      if AnyFace then SeedRegions else RebuildFlatFaces;
    end;
    FD := Was;
    FLoading := False;
    EndBusy;
    Result := True;
  finally
    L.Free;
  end;
end;

{ Show tab First with its saved camera, or framed when the file had none or
  the camera showed none of the drawing. }
procedure TMainForm.ShowLoaded(First: Integer);
begin
  LeaveSheet;
  FTabIdx := EnsureRange(First, 0, High(FDrawings));
  FD := FDrawings[FTabIdx];
  ResetTool;
  Relayout;
  { frame only when the file could not say where the camera was, or the
    saved camera shows none of the drawing }
  if FD.CamKnown and CameraShowsSomething then
  begin
    FCameraMoving := True;
    RepaintPaper;
    RenderInk;
    RecomposeAll;
    Invalidate;
  end
  else
  begin
    if FD.CamKnown then
      Trail('the saved camera showed none of the drawing - framed instead');
    FitView(False);
  end;
  LayoutTabs;
  RefreshChrome;
  pbCmd.Invalidate;
end;

{ Save As: the file in front, every sheet of it, under a new name. }
procedure TMainForm.DoSaveAs;
begin
  SaveDocument(FD.DocKey, True);
end;

{ Save: the file in front, back to where it came from, asking for a name only
  the first time. }
procedure TMainForm.DoSave;
begin
  SaveDocument(FD.DocKey, False);
end;

procedure TMainForm.DoSaveAll;
var
  I, N: Integer;
begin
  N := 0;
  I := 0;
  while I <= High(FDrawings) do
  begin
    if DocDirty(FDrawings[I].DocKey) then
    begin
      if not SaveDocument(FDrawings[I].DocKey, False) then Break;
      Inc(N);
    end;
    Inc(I);
  end;
  if N = 0 then FCmdMsg := 'Nothing to save - every file is saved.'
  else FCmdMsg := Format('Saved %d file%s.', [N, IfThen(N = 1, '', 's')]);
  pbCmd.Invalidate;
end;

function TMainForm.SaveDocument(Key: Integer; AskName: Boolean): Boolean;
var
  S: TIntArrayW;
  L: TStringList;
  Path, Tmp: string;
  I: Integer;
begin
  Result := False;
  S := DocSheets(Key);
  if Length(S) = 0 then Exit;
  Path := FDrawings[S[0]].FilePath;
  if AskName or (Path = '') then
  begin
    { its drawing in front while its name is asked for }
    if FDrawings[FTabIdx].DocKey <> Key then SelectDrawing(S[0]);
    dlgSave.Filter := 'Heckers Sketch drawing|*.hsk';
    dlgSave.DefaultExt := '.hsk';
    dlgSave.InitialDir := SaveDirNow;
    if Path <> '' then dlgSave.FileName := Path
    else dlgSave.FileName := IncludeTrailingPathDelimiter(dlgSave.InitialDir) +
      FDrawings[S[0]].DocName + '.hsk';
    if not dlgSave.Execute then Exit;
    Path := ExpandFileName(dlgSave.FileName);
    { another tab's file: two documents writing one file lose one of them }
    for I := 0 to High(FDrawings) do
      if (FDrawings[I].DocKey <> Key) and (FDrawings[I].FilePath <> '') and
         SameFileName(FDrawings[I].FilePath, Path) then
      begin
        MessageDlg('Could not save', ExtractFileName(Path) + ' is open in another tab.  Close it there first, ' +
          'or save this under another name.', mtWarning, [mbOK], 0);
        Exit;
      end;
    FSaveDir := ExtractFileDir(Path);
  end;
  L := TStringList.Create;
  try
    BuildSession(L, False, Key);
    { written beside it, then moved into place, so a failed write (full disk,
      pulled stick) leaves the old file whole }
    Tmp := Path + '.saving';
    try
      L.SaveToFile(Tmp);
      { rename over the old one; Windows needs the old one removed first }
      if not RenameFile(Tmp, Path) then
      begin
        if FileExists(Path) and not DeleteFile(Path) then
          raise Exception.Create('The old copy of ' + ExtractFileName(Path) + ' could not be replaced.');
        if not RenameFile(Tmp, Path) then
          raise Exception.Create('The new copy could not be put in place of ' + ExtractFileName(Path) + '.');
      end;
    except
      on E: Exception do
      begin
        if FileExists(Tmp) and not FileExists(Path) then RenameFile(Tmp, Path);
        MessageDlg('Could not save', E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
  finally
    L.Free;
  end;
  for I := 0 to High(S) do
  begin
    FDrawings[S[I]].FilePath := Path;
    FDrawings[S[I]].DocName := ChangeFileExt(ExtractFileName(Path), '');
    FDrawings[S[I]].Dirty := False;
  end;
  { the draft only holds what is unsaved: rewritten, or dropped if nothing is
    left unsaved, on the next tick }
  FDraftSeq := -1;
  RememberRecent(Path);
  FCmdMsg := 'Saved ' + ExtractFileName(Path) +
    IfThen(Length(S) > 1, Format(' - its %d sheets', [Length(S)]), '');
  LayoutTabs;
  Invalidate;
  pbCmd.Invalidate;
  Result := True;
end;

{ ---- the File menu ----
  MENU holds everything to do with files.  Its shortcuts are shown beside
  each row and work whether the menu is open or not. }
const
  FM_NEW = 1; FM_OPEN = 2; FM_SAVE = 3; FM_SAVEAS = 4; FM_SAVEALL = 5;
  FM_ADDSHEET = 6; FM_DELSHEET = 7; FM_EXPORT = 8; FM_PRINT = 9;
  FM_EXAMPLE = 10; FM_CLOSE = 11; FM_EXIT = 12; FM_CLEARRECENT = 13;

procedure TMainForm.ShowFileMenu;
var
  M, Sub: TMenuItem;
  I, N: Integer;
  P: TPoint;

  function Add(Parent: TMenuItem; const Caption: string; Tag: Integer; Key: Word = 0;
    Shift: TShiftState = []; Enabled: Boolean = True): TMenuItem;
  begin
    Result := TMenuItem.Create(pmFile);
    Result.Caption := Caption;
    Result.Tag := Tag;
    Result.Enabled := Enabled;
    if Key <> 0 then Result.ShortCut := Menus.ShortCut(Key, Shift);
    Result.OnClick := @FileMenuClick;
    if Parent = nil then pmFile.Items.Add(Result) else Parent.Add(Result);
  end;

  procedure Line;
  var
    L: TMenuItem;
  begin
    L := TMenuItem.Create(pmFile);
    L.Caption := '-';
    pmFile.Items.Add(L);
  end;

begin
  pmFile.Items.Clear;
  Add(nil, 'New Drawing', FM_NEW, VK_N, [ssCtrl]);
  Add(nil, 'Open...', FM_OPEN, VK_O, [ssCtrl]);
  Sub := TMenuItem.Create(pmFile);
  Sub.Caption := 'Open Recent';
  pmFile.Items.Add(Sub);
  for I := 0 to FRecent.Count - 1 do
  begin
    M := TMenuItem.Create(pmFile);
    M.Caption := Format('%d  %s', [I + 1, ExtractFileName(FRecent[I])]);
    M.Hint := FRecent[I];
    M.Tag := I;
    M.OnClick := @RecentClick;
    Sub.Add(M);
  end;
  if FRecent.Count = 0 then
  begin
    M := TMenuItem.Create(pmFile);
    M.Caption := 'Nothing yet';
    M.Enabled := False;
    Sub.Add(M);
  end
  else
  begin
    M := TMenuItem.Create(pmFile);
    M.Caption := '-';
    Sub.Add(M);
    Add(Sub, 'Clear the List', FM_CLEARRECENT);
  end;
  Line;
  Add(nil, 'Save', FM_SAVE, VK_S, [ssCtrl]);
  Add(nil, 'Save As...', FM_SAVEAS, VK_S, [ssCtrl, ssShift]);
  Add(nil, 'Save All', FM_SAVEALL, 0, [], AnyDirty > 0);
  Line;
  N := Length(DocSheets(FD.DocKey));
  Add(nil, 'Add a Sheet to This File', FM_ADDSHEET);
  Add(nil, 'Delete This Sheet from the File', FM_DELSHEET, 0, [], N > 1);
  Line;
  Add(nil, 'Export...', FM_EXPORT, VK_E, [ssCtrl]);
  Add(nil, 'Print...', FM_PRINT, VK_P, [ssCtrl]);
  Add(nil, 'Open the Example', FM_EXAMPLE);
  Line;
  Add(nil, 'Close This File', FM_CLOSE, VK_W, [ssCtrl]);
  Add(nil, 'Exit', FM_EXIT);
  { under the MENU button }
  P := Point(0, pbQuick.Height);
  for I := 0 to High(FQuick) do
    if FQuick[I].Value = ACT_MENU then P := Point(FQuick[I].Bounds.Left, FQuick[I].Bounds.Bottom);
  P := pbQuick.ClientToScreen(P);
  pmFile.PopUp(P.X, P.Y);
end;

procedure TMainForm.FileMenuClick(Sender: TObject);
begin
  case (Sender as TMenuItem).Tag of
    FM_NEW: NewDrawing(-1);
    FM_OPEN: DoOpen;
    FM_SAVE: DoSave;
    FM_SAVEAS: DoSaveAs;
    FM_SAVEALL: DoSaveAll;
    FM_ADDSHEET: AddSheetHere;
    FM_DELSHEET: DeleteSheetHere;
    FM_EXPORT: DoExport;
    FM_PRINT: DoPrint;
    FM_EXAMPLE:
      begin
        NewDrawing(-1);
        LoadExample;
        LayoutTabs;
        RenderInk;
        RecomposeAll;
      end;
    FM_CLOSE: CloseDrawing(FTabIdx);
    FM_EXIT: Close;
    FM_CLEARRECENT:
      begin
        FRecent.Clear;
        FCmdMsg := 'The recent files list is cleared.';
      end;
  end;
  pbCmd.Invalidate;
  Invalidate;
end;

procedure TMainForm.RecentClick(Sender: TObject);
var
  I: Integer;
  Path: string;
begin
  I := (Sender as TMenuItem).Tag;
  if (I < 0) or (I >= FRecent.Count) then Exit;
  Path := FRecent[I];
  if not FileExists(Path) then
  begin
    FRecent.Delete(I);
    FCmdMsg := Path + ' is not there any more - taken off the list.';
    pbCmd.Invalidate;
    Exit;
  end;
  OpenFile(Path);
end;

{ the files opened and saved lately, newest first, ten of them }
procedure TMainForm.RememberRecent(const Path: string);
var
  I: Integer;
begin
  if Path = '' then Exit;
  for I := FRecent.Count - 1 downto 0 do
    if SameFileName(FRecent[I], Path) then FRecent.Delete(I);
  FRecent.Insert(0, Path);
  while FRecent.Count > 10 do FRecent.Delete(FRecent.Count - 1);
end;

procedure TMainForm.AddSheetHere;
begin
  NewDrawing(FD.DocKey);
  FCmdMsg := Format('%s added to %s - saving the file saves every sheet of it.', [FD.Name, FD.DocName]);
  pbCmd.Invalidate;
end;

{ Delete one sheet from a file of several.  No undo for it, so it asks. }
procedure TMainForm.DeleteSheetHere;
var
  S: TIntArrayW;
  I, Key: Integer;
  DocNm: string;
begin
  Key := FD.DocKey;
  S := DocSheets(Key);
  if Length(S) < 2 then
  begin
    FCmdMsg := 'A file keeps at least one sheet - close the file instead.';
    pbCmd.Invalidate;
    Exit;
  end;
  if QuestionDlg('Delete this sheet',
    Format('Delete "%s" from %s?  Its drawing goes with it, and Undo cannot bring a sheet back.',
      [FD.Name, FD.DocName]),
    mtConfirmation, [mrYes, 'Delete the sheet', mrCancel, 'Keep it', 'IsCancel', 'IsDefault'], 0) <> mrYes then Exit;
  DocNm := FD.Name;
  LeaveSheet;
  I := FTabIdx;
  FDrawings[I].Free;
  for I := FTabIdx to High(FDrawings) - 1 do FDrawings[I] := FDrawings[I + 1];
  SetLength(FDrawings, Length(FDrawings) - 1);
  { what is left of the file has changed }
  S := DocSheets(Key);
  FDrawings[S[0]].Dirty := True;
  FDraftSeq := -1;
  FTabIdx := EnsureRange(FTabIdx, 0, High(FDrawings));
  if FDrawings[FTabIdx].DocKey <> Key then FTabIdx := S[High(S)];
  FD := FDrawings[FTabIdx];
  ResetTool;
  LayoutTabs;
  RepaintPaper;
  RenderInk;
  RecomposeAll;
  RefreshChrome;
  FCmdMsg := Format('%s deleted from %s.', [DocNm, FD.DocName]);
  pbCmd.Invalidate;
end;

{ A color not on the palette, from the platform's own picker (it has the
  eyedropper and recent colors).  The palette stays twelve. }
procedure TMainForm.PickAnyColor;
var
  C: TColor;
begin
  if not AskColor(FInkColor, C) then Exit;
  SetInk(C, False);
  FCmdMsg := 'Pen color set.';
end;

{ the platform's own color picker, started on Was }
function TMainForm.AskColor(Was: TColor; out C: TColor): Boolean;
var
  D: TColorDialog;
begin
  C := Was;
  D := TColorDialog.Create(nil);
  try
    D.Color := Was;
    Result := D.Execute;
    if Result then C := D.Color;
  finally
    D.Free;
  end;
end;

{ The manual, in its own window (see hsHelpView), fetched from the release
  when missing or from another version, so a portable copy keeps its manual. }
procedure TMainForm.OpenManual;
begin
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  OpenHelpWindow('');
  FCmdMsg := 'Opened the manual.';
end;

{ Keep the manual beside the program in step: asked once a few seconds after
  start, it fetches the right pages in the background when missing or from
  another release.  Same switch as the update check (/update never), off with
  --offline, and a failure is not retried for six hours. }
procedure TMainForm.KeepHelpCurrent;
var
  Ini: TIniFile;
  Last: string;
begin
  if NetOffline then Exit;
  if not HelpIsStale(CurrentVersion) then Exit;
  Ini := TIniFile.Create(ConfigFile);
  try
    if not Ini.ReadBool('update', 'check', True) then Exit;
    Last := Ini.ReadString('help', 'tried', '');
    if (Last <> '') and (Now - StrToFloatDef(Last, 0) < 0.25) then Exit;
    Ini.WriteString('help', 'tried', FloatToStr(Now));
  finally
    Ini.Free;
  end;
  Trail('help pages: fetching for ' + CurrentVersion);
  StartHelpFetch(CurrentVersion, @HelpFetchProgress, @HelpFetchDone);
end;

procedure TMainForm.HelpFetchProgress(BytesReceived, TotalBytes: Int64);
begin
  if HelpForm <> nil then HelpForm.FetchProgress(BytesReceived, TotalBytes);
end;

procedure TMainForm.HelpFetchDone(Sender: TObject);
var
  F: THelpFetch;
  Ini: TIniFile;
begin
  F := Sender as THelpFetch;
  if F.OK then
  begin
    Trail('help pages: installed from ' + F.GotTag);
    { a success clears the six-hour wait }
    Ini := TIniFile.Create(ConfigFile);
    try
      Ini.DeleteKey('help', 'tried');
    finally
      Ini.Free;
    end;
  end
  else
    Trail('help pages: not fetched - ' + F.Err);
  if HelpForm <> nil then HelpForm.FetchDone(Sender);
end;

{ Every edge where a solid is not closed, drawn on the model, so you see
  where (the export only says whether).  TWorkDoc.OpenEdges does the work,
  resolving T-junctions as GroupClosed does.  Checks the selected solids, or
  every solid when nothing is selected. }
procedure TMainForm.ShowOpenEdges;
var
  I, J, G, NGrp, NBad: Integer;
  Grps: array of Integer;
  Edges: TP3Array;

  procedure Want(AG: Integer);
  var
    K: Integer;
  begin
    if AG = 0 then Exit;
    for K := 0 to NGrp - 1 do
      if Grps[K] = AG then Exit;
    if NGrp >= Length(Grps) then SetLength(Grps, Max(8, NGrp * 2));
    Grps[NGrp] := AG;
    Inc(NGrp);
  end;

begin
  SetLength(FOpenEdges, 0);
  FOpenSeq := FEditSeq;
  NGrp := 0;
  SetLength(Grps, 8);

  if Length(FSel) > 0 then
    for I := 0 to High(FSel) do
      if (FSel[I] >= 0) and (FSel[I] < FD.Doc.Live) then
        Want(FD.Doc[FSel[I]].Grp);
  if NGrp = 0 then
    for I := 0 to FD.Doc.Live - 1 do
      if (FD.Doc[I].Kind = ekFace) and FD.Doc[I].Solid then
        Want(FD.Doc[I].Grp);

  if NGrp = 0 then
  begin
    FCmdMsg := 'Nothing here is a solid - there is nothing to be open.';
    pbCmd.Invalidate;
    Exit;
  end;

  NBad := 0;
  for I := 0 to NGrp - 1 do
  begin
    G := Grps[I];
    if FD.Doc.GroupClosed(G) then Continue;
    Inc(NBad);
    Edges := FD.Doc.OpenEdges(G);
    for J := 0 to High(Edges) do
    begin
      SetLength(FOpenEdges, Length(FOpenEdges) + 1);
      FOpenEdges[High(FOpenEdges)] := Edges[J];
    end;
  end;

  if NBad = 0 then
    FCmdMsg := Format('%s closed - a slicer will take %s.',
      [specialize IfThen<string>(NGrp = 1, 'That solid is',
        Format('All %d solids are', [NGrp])),
       specialize IfThen<string>(NGrp = 1, 'it', 'them')])
  else if Length(FOpenEdges) = 0 then
    FCmdMsg := Format('%d of %d solids are open, but the edges could not be ' +
      'pinned down - send this drawing in.', [NBad, NGrp])
  else
  begin
    if NGrp = 1 then
      FCmdMsg := 'This solid is open.'
    else if NBad = 1 then
      FCmdMsg := Format('One of the %d solids is open.', [NGrp])
    else
      FCmdMsg := Format('%d of the %d solids are open.', [NBad, NGrp]);
    FCmdMsg := FCmdMsg + Format('  %d edges are drawn in red where nothing ' +
      'meets them - type /holes again once you have mended them.',
      [Length(FOpenEdges) div 2]);
  end;
  pbCmd.Invalidate;
  Invalidate;
end;

{ Where this kind of file was exported last time, or the program's exports
  folder.  Empty if even that cannot be made (a read-only stick); the dialog
  then offers a bare file name. }
function TMainForm.ExportDirFor(const Ext: string): string;
begin
  Result := FExportDirs.Values[Ext];
  if (Result <> '') and DirectoryExists(Result) then Exit;
  Result := ExportsDir;
end;

procedure TMainForm.KeepExportDir(const Ext, Dir: string);
begin
  if (Ext = '') or (Dir = '') then Exit;
  FExportDirs.Values[Ext] := Dir;
end;

{ the same for drawings, which are all one kind }
function TMainForm.SaveDirNow: string;
begin
  Result := FSaveDir;
  if (Result <> '') and DirectoryExists(Result) then Exit;
  Result := DrawingsDir;
  if Result = '' then Result := AppDataDir;
end;

{ where to look when opening: where a drawing was last opened from, or the
  program's own folder (examples and drawings are one click away) }
function TMainForm.OpenDirNow: string;
begin
  Result := FOpenDir;
  if (Result <> '') and DirectoryExists(Result) then Exit;
  Result := AppDataDir;
end;

procedure TMainForm.DoExport;
var
  Msg, Base: string;
  ExpPivot: TP3;
  Holes: Boolean;
begin
  { the export turns about the middle of the selection, or of the drawing }
  if not FD.Doc.MiddleOf(FSel, ExpPivot) then ExpPivot := P3(0, 0, 0);
  { a name only; the dialog asks for the folder per format }
  Base := 'heckers-sketch-' + FormatDateTime('yyyymmdd-hhnnss', Now);
  Msg := '';
  Holes := False;
  if RunExport(FD.Doc, Proj, FD.Units, FDimFont, AnnotColor, FEdgeW,
       FArt.Width, FArt.Height, Base, Themes[FThemeIdx], ExpPivot,
       @ReportFromDialog, @ExportDirFor, @KeepExportDir, Msg, Holes, FD.ScaleIdx) then
  begin
    FCmdMsg := Msg;
    { told the STL is not closed, the open edges are already marked on the
      drawing when the dialog closes }
    if Holes then
    begin
      ShowOpenEdges;
      FCmdMsg := Msg;
    end;
  end
  else if Msg <> '' then
    FCmdMsg := Msg;
  Invalidate;
end;

{ Print full size across as many sheets as it takes, for taping together on
  the metal and scribing round.  Each tile is rendered from geometry at the
  printer's resolution.  Each tile starts LAP short of the last page edge, so
  the right and bottom LAP strip repeats the next sheet: trim on the marked
  line and butt them.  The sheet label sits in that strip. }
procedure TMainForm.DoPrintFull(const PngDir: string);
const
  LAP_IN = 0.5;        // inches of overlap, and the width of the trim strip
  MARGIN_IN = 0.25;    // white left round the drawing before it is tiled
  MAX_SHEETS = 120;    // past this it is a mistake, not a plan
var
  Sheet: TArtSurface;
  V: TProjector;
  Full: TDrawScale;
  Lo, Hi: TP3;
  I, Col, Row, Cols, Rows, SW, SH, PitchW, PitchH, N: Integer;
  BX0, BY0, BX1, BY1, MinX, MinY, MaxX, MaxY: Double;
  PageWIn, PageHIn: Double;
  Any: Boolean;
  Msg: string;
begin
  if FD.Doc.Live = 0 then
  begin
    FCmdMsg := 'Nothing on this sheet to print.';
    Exit;
  end;

  { 1:1: paper inches per foot, so 12; metric paper meters per meter, so 1 }
  if FD.Units = usImperial then
  begin
    Full.Name := 'full size';
    Full.Paper := 12;
  end
  else
  begin
    Full.Name := '1:1';
    Full.Paper := 1;
  end;

  { Where the drawing lands on an unshifted page, in print pixels, through
    the current view.  Full size is exact in PLAN; in 3D it is the picture at
    full size, foreshortening and all (said below before printing). }
  V.Kind := FD.View;
  V.Ppu := PixelsPerUnit(FD.Units, Full, PRINT_DPI);
  V.OX := 0;
  V.OY := 0;
  V.Az := FD.Az;
  V.El := FD.El;

  Any := False;
  MinX := 0; MinY := 0; MaxX := 0; MaxY := 0;
  for I := 0 to FD.Doc.Live - 1 do
  begin
    FD.Doc.ScreenBounds(V, I, BX0, BY0, BX1, BY1);
    if BX1 < BX0 then Continue;
    if not Any then
    begin
      MinX := BX0; MinY := BY0; MaxX := BX1; MaxY := BY1;
      Any := True;
    end
    else
    begin
      MinX := Min(MinX, BX0); MinY := Min(MinY, BY0);
      MaxX := Max(MaxX, BX1); MaxY := Max(MaxY, BY1);
    end;
  end;
  if not Any then
  begin
    { nothing has a screen size: fall back to the model box }
    if not FD.Doc.Bounds(Lo, Hi) then Exit;
    MinX := 0; MinY := 0;
    MaxX := (Hi.X - Lo.X) * V.Ppu;
    MaxY := (Hi.Y - Lo.Y) * V.Ppu;
  end;
  MinX := MinX - MARGIN_IN * PRINT_DPI;
  MinY := MinY - MARGIN_IN * PRINT_DPI;
  MaxX := MaxX + MARGIN_IN * PRINT_DPI;
  MaxY := MaxY + MARGIN_IN * PRINT_DPI;

  { straight to PNG files needs no dialog and no printer (letter size if
    there is none): what a print shop asks for, and a preview }
  if PngDir = '' then
  begin
    if not dlgPrint.Execute then Exit;
    if (Printer.XDPI <= 0) or (Printer.YDPI <= 0) then
    begin
      FCmdMsg := 'The printer did not say what resolution it is.';
      Exit;
    end;
  end;

  if (Printer.XDPI > 0) and (Printer.YDPI > 0) then
  begin
    PageWIn := Printer.PageWidth / Printer.XDPI;
    PageHIn := Printer.PageHeight / Printer.YDPI;
  end
  else
  begin
    PageWIn := 8.5;
    PageHIn := 11;
  end;
  SW := Max(64, Round(PageWIn * PRINT_DPI));
  SH := Max(64, Round(PageHIn * PRINT_DPI));
  PitchW := Max(1, SW - Round(LAP_IN * PRINT_DPI));
  PitchH := Max(1, SH - Round(LAP_IN * PRINT_DPI));

  Cols := Max(1, Ceil((MaxX - MinX) / PitchW));
  Rows := Max(1, Ceil((MaxY - MinY) / PitchH));
  N := Cols * Rows;

  Msg := Format('%s, %d across by %d down = %d sheets of %.1f x %.1f in.',
    [Full.Name, Cols, Rows, N, PageWIn, PageHIn]);
  if FD.View <> vkPlan then
    Msg := Msg + LineEnding + LineEnding +
      'This is the ' + IfThen(FD.View = vkIso, 'ISO', '3D') +
      ' view, so what comes out is the picture at full size, not the part.' +
      LineEnding + 'PLAN is the one to print a pattern from.';
  if (N > MAX_SHEETS) and (PngDir <> '') then
  begin
    FCmdMsg := Format('%d tiles is past the %d limit.', [N, MAX_SHEETS]);
    Exit;
  end;
  if N > MAX_SHEETS then
  begin
    MessageDlg('Too many sheets',
      Msg + LineEnding + LineEnding +
      Format('That is past the %d sheet limit.  Print it at a scale, or ' +
        'print one piece at a time.', [MAX_SHEETS]), mtWarning, [mbOK], 0);
    Exit;
  end;
  if (PngDir = '') and (MessageDlg('Print full size?',
       Msg + LineEnding + LineEnding +
       Format('Every sheet is trimmed on the marked line - the last %.1f in ' +
         'down the right and along the bottom is a repeat of the next ' +
         'sheet.  The sheet number is printed inside that strip.',
         [LAP_IN]),
       mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then Exit;

  try
    if PngDir = '' then Printer.BeginDoc;
    try
      Sheet := TArtSurface.Create(SW, SH);
      try
        for Row := 0 to Rows - 1 do
          for Col := 0 to Cols - 1 do
          begin
            if (PngDir = '') and ((Row > 0) or (Col > 0)) then Printer.NewPage;
            Sheet.Clear(Pix(255, 255, 255));
            V.OX := -MinX - Col * PitchW;
            V.OY := -MinY - Row * PitchH;
            FD.Doc.Render(Sheet, V, FD.Units, FDimFont, Pix(20, 20, 20), FEdgeW);
            if PngDir <> '' then
              Sheet.SaveToPNG(IncludeTrailingPathDelimiter(PngDir) +
                Format('tile-r%dc%d.png', [Row + 1, Col + 1]))
            else
            begin
              Printer.Canvas.StretchDraw(
                Rect(0, 0, Printer.PageWidth, Printer.PageHeight), Sheet.AsBitmap);
              PrintTileMarks(Col, Row, Cols, Rows, PitchW, PitchH, SW, SH,
                             Full.Name);
            end;
          end;
      finally
        Sheet.Free;
      end;
    finally
      if PngDir = '' then Printer.EndDoc;
    end;
    if PngDir <> '' then
      FCmdMsg := Format('Wrote %d tiles at %s into %s', [N, Full.Name, PngDir])
    else
      FCmdMsg := Format('Sent %d sheets at %s.', [N, Full.Name]);
  except
    on E: Exception do
      if PngDir <> '' then FCmdMsg := 'Could not write the tiles: ' + E.Message
      else MessageDlg('Could not print', E.Message, mtError, [mbOK], 0);
  end;
  Invalidate;
end;

{ The trim line and sheet number, drawn straight onto the page at printer
  resolution: they belong to the paper, not the drawing. }
procedure TMainForm.PrintTileMarks(Col, Row, Cols, Rows, PitchW, PitchH,
  SW, SH: Integer; const ScaleName: string);
var
  PX, PY: Integer;
  S: string;

  { print pixels to printer pixels }
  function AtX(V: Integer): Integer;
  begin
    Result := Round(V * (Printer.PageWidth / SW));
  end;

  function AtY(V: Integer): Integer;
  begin
    Result := Round(V * (Printer.PageHeight / SH));
  end;

begin
  Printer.Canvas.Pen.Color := clSilver;
  Printer.Canvas.Pen.Width := Max(1, Printer.XDPI div 300);
  Printer.Canvas.Brush.Style := bsClear;

  PX := AtX(PitchW);
  PY := AtY(PitchH);
  { a sheet with one to its right is trimmed on the line; the last column is
    left whole }
  if Col < Cols - 1 then
  begin
    Printer.Canvas.Line(PX, 0, PX, Printer.PageHeight);
    Printer.Canvas.TextOut(PX + AtX(8), AtY(8), 'trim');
  end;
  if Row < Rows - 1 then
  begin
    Printer.Canvas.Line(0, PY, Printer.PageWidth, PY);
    Printer.Canvas.TextOut(AtX(8), PY + AtY(8), 'trim');
  end;

  Printer.Canvas.Font.Color := clGray;
  Printer.Canvas.Font.Height := -Round(Printer.YDPI / 8);   { about 9 point }
  S := Format('%s  -  sheet %d of %d   (row %d, column %d)   %s',
    [FD.Name, Row * Cols + Col + 1, Cols * Rows, Row + 1, Col + 1, ScaleName]);
  { inside the trim strip, so it is cut away with it }
  Printer.Canvas.TextOut(AtX(12),
    Printer.PageHeight - Round(Printer.YDPI / 5), S);
end;

{ Print the sheet in front at its drawing scale. }
procedure TMainForm.DoPrint;
begin
  DoPrintSheets(False);
end;

{ Print at scale.  The page is rendered from the geometry at the printer's
  resolution, so 1/4" = 1'-0" is a true quarter inch; a printer that gives
  no resolution gets the picture fitted to the page.  All prints every sheet of the file, a page each
  (/print all); that is not the default. }
procedure TMainForm.DoPrintSheets(All: Boolean);
var
  Sheet: TArtSurface;
  V: TProjector;
  Lo, Hi, Mid: TP3;
  PageWIn, PageHIn: Double;
  SW, SH: Integer;
  P: TPointF;
  Scale: Double;
  R: TRect;
  Was, Page, NPages: Integer;
  Pages: TIntArrayW;
begin
  if not dlgPrint.Execute then Exit;
  Was := FTabIdx;
  { every sheet of the file in front, not every tab (others may be other
    files) }
  Pages := DocSheets(FD.DocKey);
  if All then NPages := Length(Pages) else NPages := 1;
  try
    Printer.BeginDoc;
    try
      for Page := 0 to NPages - 1 do
      begin
      if All then
      begin
        { the renderer reads the sheet, scale and units off FD, so the sheet
          being printed is made current while it is drawn }
        if Page > 0 then Printer.NewPage;
        FTabIdx := Pages[Page];
        FD := FDrawings[Pages[Page]];
      end;
      if (Printer.XDPI > 0) and (Printer.YDPI > 0) then
      begin
        PageWIn := Printer.PageWidth / Printer.XDPI;
        PageHIn := Printer.PageHeight / Printer.YDPI;
        SW := Max(64, Round(PageWIn * PRINT_DPI));
        SH := Max(64, Round(PageHIn * PRINT_DPI));

        Sheet := TArtSurface.Create(SW, SH);
        try
          Sheet.Clear(Pix(255, 255, 255));
          V.Kind := FD.View;
          V.Ppu := PixelsPerUnit(FD.Units, CurScale, PRINT_DPI);
          V.OX := 0;
          V.OY := 0;
          if FD.Doc.Bounds(Lo, Hi) then
          begin
            Mid := P3((Lo.X + Hi.X) / 2, (Lo.Y + Hi.Y) / 2, (Lo.Z + Hi.Z) / 2);
            P := Project(V, Mid);
            V.OX := SW / 2 - P.X;
            V.OY := SH / 2 - P.Y;
          end;
          FD.Doc.Render(Sheet, V, FD.Units, FDimFont, Pix(20, 20, 20), FEdgeW);
          Printer.Canvas.StretchDraw(
            Rect(0, 0, Printer.PageWidth, Printer.PageHeight), Sheet.AsBitmap);
        finally
          Sheet.Free;
        end;
        if All then
          FCmdMsg := Format('Printed %d sheets at %s%s.',
            [NPages, CurScale.Name,
             IfThen(FD.Units = usImperial, ' = 1''-0"', '')])
        else
          FCmdMsg := 'Printed at ' + CurScale.Name +
            IfThen(FD.Units = usImperial, ' = 1''-0"', '') +
            '.  /print all does every sheet; /print full lays it out 1:1 ' +
            'across pages.';
      end
      else
      begin
        Scale := Min(Printer.PageWidth / FArt.Width,
                     Printer.PageHeight / FArt.Height) * 0.92;
        R := Bounds(Round((Printer.PageWidth - FArt.Width * Scale) / 2),
                    Round((Printer.PageHeight - FArt.Height * Scale) / 2),
                    Round(FArt.Width * Scale), Round(FArt.Height * Scale));
        Printer.Canvas.StretchDraw(R, FArt.AsBitmap);
      end;
      end;
    finally
      Printer.EndDoc;
    end;
    FCmdMsg := 'Sent to the printer.';
    InvalidateStatus;
  except
    on E: Exception do
      MessageDlg('Could not print', E.Message, mtError, [mbOK], 0);
  end;
  { back to the sheet that was showing }
  FTabIdx := EnsureRange(Was, 0, High(FDrawings));
  FD := FDrawings[FTabIdx];
  Invalidate;
end;

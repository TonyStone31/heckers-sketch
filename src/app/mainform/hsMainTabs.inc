{ hsMainForm - drawings and their tabs.  Part of TMainForm; included by hsMainForm.pas }

{ ======================================================================== }
{ drawings and tabs                                                         }
{ ======================================================================== }

constructor TDrawing.Create(const AName: string);
begin
  inherited Create;
  Doc := TWorkDoc.Create;
  Name := AName;
  Zoom := 1.0;
  ScaleIdx := 2;          // 1/4" = 1'-0"
  SnapIdx := 5;           // one foot
  Units := usImperial;
  { A new sheet opens on the 3D corner view.  PLAN suits a floor plan but
    gives nothing height, and everyone left it first thing. }
  View := vkOrbit;
  Plane := plXY;
  Az := -Pi / 4;
  El := 35.264 * Pi / 180;   // start on the isometric corner
  { Off, meaning the whole model; never hide part of a drawing by default. }
  SliceOn := False;
  SliceLo := 0;
  SliceHi := 8;
  SetLength(Undo, UNDO_LEVELS);
  SetLength(Redo, UNDO_LEVELS);
end;

destructor TDrawing.Destroy;
begin
  Doc.Free;
  inherited Destroy;
end;

{ A new sheet.  Key < 0 makes a new untitled one-sheet document; otherwise
  the sheet is added to document Key after its last tab. }
procedure TMainForm.NewDrawing(Key: Integer);
var
  N, K, Nm, At, Src: Integer;
  Taken: Boolean;
  D: TDrawing;
begin
  N := Length(FDrawings);
  Src := -1;
  if Key >= 0 then
    for K := 0 to N - 1 do
      if FDrawings[K].DocKey = Key then Src := K;
  if Src < 0 then Key := -1;
  { the lowest 'Sheet k' its file does not have already }
  Nm := 1;
  repeat
    Taken := False;
    for K := 0 to N - 1 do
      if (Key >= 0) and (FDrawings[K].DocKey = Key) and (FDrawings[K].Name = Format('Sheet %d', [Nm])) then
        Taken := True;
    if Taken then Inc(Nm);
  until not Taken;
  D := TDrawing.Create(Format('Sheet %d', [Nm]));
  if (N > 0) and (FD <> nil) then
  begin
    { a new sheet inherits how you were working }
    D.ScaleIdx := FD.ScaleIdx;
    D.SnapIdx := FD.SnapIdx;
    D.Units := FD.Units;
    D.View := FD.View;
  end;
  if Key < 0 then
  begin
    { a drawing of its own: a one-sheet file, not saved yet, and blank }
    Inc(FNextDocKey);
    D.DocKey := FNextDocKey;
    Inc(FUntitled);
    D.DocName := Format('Untitled %d', [FUntitled]);
    D.FilePath := '';
    At := N;
  end
  else
  begin
    { a sheet added to a file goes after that file's last tab, and the file
      is now changed }
    D.DocKey := Key;
    D.DocName := FDrawings[Src].DocName;
    D.FilePath := FDrawings[Src].FilePath;
    D.Dirty := True;
    At := Src + 1;
  end;
  SetLength(FDrawings, N + 1);
  for K := N downto At + 1 do FDrawings[K] := FDrawings[K - 1];
  FDrawings[At] := D;
  FTabIdx := At;
  LeaveSheet;
  FD := D;
  FD.ViewX := Round(FArt.Width * 0.10);
  FD.ViewY := Round(FArt.Height * 0.88);
  if FBooted then
  begin
    ResetTool;
    LayoutTabs;
    RepaintPaper;
    RenderInk;
    RecomposeAll;
    RefreshChrome;
  end;
end;

procedure TMainForm.SelectDrawing(I: Integer);
begin
  if (I < 0) or (I > High(FDrawings)) or (I = FTabIdx) then Exit;
  LeaveSheet;
  FTabIdx := I;
  FD := FDrawings[I];
  ResetTool;
  RepaintPaper;
  RenderInk;
  RecomposeAll;
  RebuildDeck;
  pbDeck.Invalidate;
  pbTabs.Invalidate;
  Invalidate;
end;

{ The tab's cross, Ctrl+W, /close: closes the whole file the tab belongs to,
  asking about unsaved work first. }
procedure TMainForm.CloseDrawing(I: Integer);
begin
  if (I < 0) or (I > High(FDrawings)) then Exit;
  CloseDocument(FDrawings[I].DocKey);
end;

function TMainForm.DocPath: string;
begin
  if FD = nil then Result := '' else Result := FD.FilePath;
end;

function TMainForm.DocSheets(Key: Integer): TIntArrayW;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(FDrawings) do
    if FDrawings[I].DocKey = Key then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := I;
    end;
end;

{ A file changed since it was opened or saved has work in it, whatever is
  left on it; an untitled drawing with nothing on it has nothing to lose. }
function TMainForm.DocDirty(Key: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(FDrawings) do
    if (FDrawings[I].DocKey = Key) and FDrawings[I].Dirty and
       ((FDrawings[I].FilePath <> '') or (FDrawings[I].Doc.Live > 0)) then Exit(True);
end;

function TMainForm.TabCaption(I: Integer): string;
begin
  Result := FDrawings[I].DocName;
  if Length(DocSheets(FDrawings[I].DocKey)) > 1 then Result := Result + ': ' + FDrawings[I].Name;
  if DocDirty(FDrawings[I].DocKey) then Result := Result + ' *';
end;

function TMainForm.AskToSave(Key: Integer; const Title: string): Boolean;
var
  S: TIntArrayW;
  Ans: Integer;
  Where: string;
begin
  Result := True;
  if not DocDirty(Key) then Exit;
  S := DocSheets(Key);
  if Length(S) = 0 then Exit;
  { bring its drawing to the front while asking }
  if FDrawings[FTabIdx].DocKey <> Key then SelectDrawing(S[0]);
  if FDrawings[S[0]].FilePath <> '' then Where := FDrawings[S[0]].FilePath
  else Where := 'It has not been saved to a file yet.';
  Ans := QuestionDlg(Title,
    Format('Save the changes to "%s"?', [FDrawings[S[0]].DocName]) + LineEnding + LineEnding + Where,
    mtConfirmation,
    [mrYes, 'Save', 'IsDefault',
     mrNo, 'Don''t save',
     mrCancel, 'Cancel', 'IsCancel'], 0);
  if Ans = mrCancel then Exit(False);
  { Save; a refused name or failed write keeps it open }
  if Ans = mrYes then Result := SaveDocument(Key, False);
end;

function TMainForm.CloseDocument(Key: Integer): Boolean;
var
  K, J: Integer;
  DocNm: string;
begin
  Result := AskToSave(Key, 'Close');
  if not Result then Exit;
  DocNm := '';
  LeaveSheet;
  J := 0;
  for K := 0 to High(FDrawings) do
    if FDrawings[K].DocKey = Key then
    begin
      DocNm := FDrawings[K].DocName;
      FDrawings[K].Free;
    end
    else
    begin
      FDrawings[J] := FDrawings[K];
      Inc(J);
    end;
  SetLength(FDrawings, J);
  FD := nil;
  { closing the last file leaves a new empty drawing, as at startup }
  FDraftSeq := -1;
  if Length(FDrawings) = 0 then
  begin
    NewDrawing(-1);
    FCmdMsg := 'Closed ' + DocNm + '.  A new empty drawing - MENU or Ctrl+O to open one.';
    pbCmd.Invalidate;
    Exit;
  end;
  FTabIdx := EnsureRange(FTabIdx, 0, High(FDrawings));
  FD := FDrawings[FTabIdx];
  FDraftSeq := -1;
  ResetTool;
  LayoutTabs;
  RepaintPaper;
  RenderInk;
  RecomposeAll;
  RefreshChrome;
  FCmdMsg := 'Closed ' + DocNm + '.';
  pbCmd.Invalidate;
end;

procedure TMainForm.LayoutTabs;
begin
  PlaceTabs;
  pbTabs.Invalidate;
end;

{ Where each tab goes.  Recomputed every paint: a tab is as wide as its
  caption, which changes (a star for unsaved work). }
procedure TMainForm.PlaceTabs;
var
  I, X, W, TabH, Pad: Integer;
begin
  SetLength(FTabRects, Length(FDrawings) + 1);   // one extra for the + button
  if not pbTabs.Visible then Exit;
  TabH := pbTabs.Height;
  X := 0;
  { as wide as its caption, within limits; tabs of one file sit close and a
    wider gap separates files }
  UIFont(pbTabs.Canvas, 10, True, Theme.Text);
  for I := 0 to High(FDrawings) do
  begin
    W := EnsureRange(pbTabs.Canvas.TextWidth(TabCaption(I)) + Round(44 * FUIScale),
      Round(110 * FUIScale), Round(300 * FUIScale));
    FTabRects[I] := Rect(X, 0, X + W, TabH);
    if (I < High(FDrawings)) and (FDrawings[I + 1].DocKey = FDrawings[I].DocKey) then
      Pad := Round(1 * FUIScale)
    else
      Pad := Round(8 * FUIScale);
    Inc(X, W + Pad);
  end;
  FTabRects[High(FTabRects)] := Rect(X, 0, X + Round(30 * FUIScale), TabH);
end;

procedure TMainForm.pbTabsPaint(Sender: TObject);
var
  I, TW: Integer;
  R: TRect;
  IsCur, Hot: Boolean;
  C1, C2, Edge: TPix;
  S: string;
begin
  PlaceTabs;

  FCmdSkin.SetSize(pbTabs.Width, pbTabs.Height);
  FCmdSkin.Clear(Pix(0, 0, 0));
  FCmdSkin.CopyRegion(FShell, pbTabs.Left, pbTabs.Top, 0, 0,
    pbTabs.Width, pbTabs.Height);

  for I := 0 to High(FDrawings) do
  begin
    R := FTabRects[I];
    IsCur := I = FTabIdx;
    Hot := I = FHotTab;
    if IsCur then
    begin
      C1 := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.14);
      C2 := Theme.Panel;
      Edge := ShadePix(Theme.Accent, 0.9);
    end
    else if Hot then
    begin
      C1 := MixPix(Theme.Panel, Pix(255, 255, 255), 0.10);
      C2 := MixPix(Theme.Panel, Pix(0, 0, 0), 0.10);
      Edge := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.20);
    end
    else
    begin
      C1 := MixPix(Theme.Panel, Pix(0, 0, 0), 0.15);
      C2 := MixPix(Theme.Panel, Pix(0, 0, 0), 0.30);
      Edge := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.08);
    end;
    { square off the bottom so the active tab reads as joined to the sheet }
    FCmdSkin.RoundRectV(Rect(R.Left, R.Top, R.Right, R.Bottom + Round(10 * FUIScale)),
      Round(9 * FUIScale), C1, C2);
    FCmdSkin.RoundFrame(Rect(R.Left, R.Top, R.Right, R.Bottom + Round(10 * FUIScale)),
      Round(9 * FUIScale), 1.0, Edge, 0.9);
    if IsCur then
      FCmdSkin.RoundRect(Rect(R.Left + Round(10 * FUIScale), R.Top + Round(3 * FUIScale),
        R.Right - Round(10 * FUIScale), R.Top + Round(6 * FUIScale)),
        1.5, Theme.Accent, 0.95);
    { The close cross is on the current tab, even when it is the only one;
      hiding it left no visible way to close the drawing.  Closing the last
      file leaves a new empty one. }
    if IsCur then
    begin
      FCmdSkin.Line(R.Right - Round(20 * FUIScale), R.Top + Round(12 * FUIScale),
        R.Right - Round(12 * FUIScale), R.Top + Round(20 * FUIScale), 1.5, Theme.TextDim, 0.9);
      FCmdSkin.Line(R.Right - Round(12 * FUIScale), R.Top + Round(12 * FUIScale),
        R.Right - Round(20 * FUIScale), R.Top + Round(20 * FUIScale), 1.5, Theme.TextDim, 0.9);
    end;
  end;

  { the + button }
  R := FTabRects[High(FTabRects)];
  Hot := FHotTab = High(FTabRects);
  if Hot then
    FCmdSkin.RoundRect(R, Round(8 * FUIScale),
      MixPix(Theme.Panel, Pix(255, 255, 255), 0.12))
  else
    FCmdSkin.RoundRect(R, Round(8 * FUIScale),
      MixPix(Theme.Panel, Pix(0, 0, 0), 0.20));
  FCmdSkin.Line((R.Left + R.Right) / 2, R.Top + Round(9 * FUIScale),
    (R.Left + R.Right) / 2, R.Bottom - Round(9 * FUIScale), 1.6, Theme.Text, 0.85);
  FCmdSkin.Line(R.Left + Round(9 * FUIScale), (R.Top + R.Bottom) / 2,
    R.Right - Round(9 * FUIScale), (R.Top + R.Bottom) / 2, 1.6, Theme.Text, 0.85);

  FCmdSkin.DrawTo(pbTabs.Canvas, 0, 0);

  for I := 0 to High(FDrawings) do
  begin
    R := FTabRects[I];
    if I = FTabIdx then
      UIFont(pbTabs.Canvas, 10, True, Theme.Text)
    else
      UIFont(pbTabs.Canvas, 10, False, Theme.TextDim);
    S := TabCaption(I);
    { shortened to fit, leaving room for the close cross }
    S := CutToFit(pbTabs.Canvas, S, R.Right - R.Left - Round(36 * FUIScale));
    TW := pbTabs.Canvas.TextWidth(S);
    pbTabs.Canvas.TextOut(R.Left + Round(12 * FUIScale),
      (R.Top + R.Bottom - pbTabs.Canvas.TextHeight(S)) div 2, S);
    if TW = 0 then ;
  end;
end;

procedure TMainForm.pbTabsMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  I, H: Integer;
begin
  H := -1;
  for I := 0 to High(FTabRects) do
    if PtInRect(FTabRects[I], Point(X, Y)) then
    begin
      H := I;
      Break;
    end;
  if H <> FHotTab then
  begin
    FHotTab := H;
    pbTabs.Invalidate;
  end;
end;

procedure TMainForm.pbTabsMouseLeave(Sender: TObject);
begin
  if FHotTab <> -1 then
  begin
    FHotTab := -1;
    pbTabs.Invalidate;
  end;
end;

procedure TMainForm.pbTabsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  R: TRect;
begin
  if Button <> mbLeft then Exit;
  for I := 0 to High(FDrawings) do
  begin
    R := FTabRects[I];
    if not PtInRect(R, Point(X, Y)) then Continue;
    if (I = FTabIdx) and (X > R.Right - Round(26 * FUIScale)) then
      CloseDrawing(I)
    else
      SelectDrawing(I);
    Exit;
  end;
  if PtInRect(FTabRects[High(FTabRects)], Point(X, Y)) then
    NewDrawing;
end;

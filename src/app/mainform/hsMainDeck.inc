{ hsMainForm - the control deck and the command bar.  Part of TMainForm; included by hsMainForm.pas }

{ ======================================================================== }
{ control deck                                                              }
{ ======================================================================== }

procedure TMainForm.RebuildDeck;
var
  W, H, Pad, LabW, RowH, RowGap, IconW: Integer;
  Y0, RowY, X, Avail, SegW: Integer;
  NSet, NamedW: Integer;
  NamedIcons: Boolean;

  procedure Add(K: TDeckKind; const B: TRect; G, V: Integer;
    const Cap, Hnt: string; Ic: TIconKind);
  var
    M: Integer;
  begin
    M := Length(FDeck);
    SetLength(FDeck, M + 1);
    FDeck[M].Kind := K;
    FDeck[M].Bounds := B;
    FDeck[M].Group := G;
    FDeck[M].Value := V;
    FDeck[M].Caption := Cap;
    FDeck[M].Hint := Hnt;
    FDeck[M].Icon := Ic;
  end;

  { The same six, with a word each; a word beats a pictogram for someone who
    has not learned the pictogram yet. }
  procedure AddNamed6(RY: Integer; const A: array of Integer;
    const K: array of TIconKind; const N: array of string;
    const H: array of string);
  var
    IX, J, BW: Integer;
  begin
    BW := NamedW;
    IX := W - Pad - Length(A) * BW - (Length(A) - 1) * RowGap;
    for J := 0 to High(A) do
    begin
      { narrow: picture only, name in the tooltip (see where NamedIcons is
        set) }
      if NamedIcons then
        Add(dkIcon, Rect(IX, RY, IX + BW, RY + RowH), GRP_ICON, A[J], '',
          N[J] + ' - ' + H[J], K[J])
      else
        Add(dkSegment, Rect(IX, RY, IX + BW, RY + RowH), GRP_ICON, A[J], N[J],
          H[J], K[J]);
      Inc(IX, BW + RowGap);
    end;
  end;

begin
  SetLength(FDeck, 0);
  W := FDeckSkin.Width;
  H := FDeckSkin.Height;
  { Do not build into nothing.  The floor is one row plus padding; a higher
    floor once silently emptied the single-row deck. }
  if (W < 40) or (H < 24) then Exit;

  Pad := Round(14 * FUIScale);
  LabW := Round(74 * FUIScale);
  RowH := DeckRowH;
  RowGap := Round(4 * FUIScale);
  IconW := Round(34 * FUIScale);

  Y0 := (H - (DeckRows * RowH + (DeckRows - 1) * RowGap)) div 2;
  X := Pad + LabW;

  { --- the tools are on the strip down the left (see RebuildTools) ---
    What stays here is settings and actions on the program rather than
    the drawing. }
  FGrpDivY0 := 0;
  FGrpDivY1 := 0;
  FGrpDivX[0] := -1;
  FGrpDivX[1] := -1;

  { --- row 1: settings as buttons that open a list ---
    Scale, snap and pen are set once and left alone, so each is one button
    showing its value, with its list opening above. }
  RowY := Y0;
  { Five settings, always, in full words.  The guide buttons live on the
    right-click menu so this row never changes width. }
  NSet := 5;
  { On a narrow window the settings keep the room they need first and the
    six buttons shrink toward a floor that still fits "ORIGIN"; FitCaption
    handles whatever is still short. }
  Avail := W - 2 * Pad - LabW - Round(18 * FUIScale);
  NamedW := (Avail - (NSet * Round(128 * FUIScale) + (NSet - 1) * RowGap)
             - 5 * RowGap) div 6;
  NamedW := EnsureRange(NamedW, Round(60 * FUIScale), Round(88 * FUIScale));
  { Narrower still, the six drop their words and keep their pictures (the
    word stays in the tooltip); a settings button cut to "1/16\"" no
    longer says what it sets. }
  NamedIcons := (Avail - (6 * NamedW + 5 * RowGap) - (NSet - 1) * RowGap)
    div NSet < Round(112 * FUIScale);
  if NamedIcons then NamedW := IconW;
  Avail := Avail - (6 * NamedW + 5 * RowGap);
  SegW := (Avail - (NSet - 1) * RowGap) div NSet;
  Add(dkSegment, Rect(X + 4 * SegW, RowY, X + 5 * SegW - RowGap,
    RowY + RowH), GRP_POPUP, POP_PREC,
    IfThen(FLenDenom = 100,
      'ROUNDED TO  .01"', Format('ROUNDED TO  1/%d"', [FLenDenom])),
    'How finely a length is written down, and what the last field of a ' +
    'dashed entry counts in - 6-8-15 is feet, inches and sixteenths.  ' +
    'It never changes what the drawing holds.', ikDroplet);
  Add(dkSegment, Rect(X, RowY, X + SegW - RowGap, RowY + RowH),
    GRP_POPUP, POP_SCALE,
    'PRINT SCALE  ' + ScaleTable(FD.Units, FD.ScaleIdx).Name,
    'What one foot measures on the paper when this sheet is printed.',
    ikDroplet);
  Add(dkSegment, Rect(X + SegW, RowY, X + 2 * SegW - RowGap, RowY + RowH),
    GRP_POPUP, POP_SNAP, 'SNAP TO  ' + SnapName(FD.Units, FD.SnapIdx),
    'The step the cursor moves in when it is not on a point of the ' +
    'drawing.  It is also what the arrows on the cut fields step by.',
    ikDroplet);
  Add(dkSegment, Rect(X + 2 * SegW, RowY, X + 3 * SegW - RowGap, RowY + RowH),
    GRP_POPUP, POP_COLOR, 'LINE COLOR',
    'The color new lines are drawn in.', ikDroplet);
  Add(dkSegment, Rect(X + 3 * SegW, RowY, X + 4 * SegW - RowGap, RowY + RowH),
    GRP_POPUP, POP_WIDTH, Format('LINE WIDTH  %d px', [FEdgeW]),
    'How thick every edge in this drawing is drawn.  It is one setting for ' +
    'the whole sheet, the way SketchUp does it - not a property of the ' +
    'line you happen to be drawing.', ikDroplet);

  { File actions are at the top left (see RebuildQuick).  These are about
    the view and the program, each with a word. }
  AddNamed6(Y0,
    [ACT_FIT, ACT_ORIGIN, ACT_GRID, ACT_UNITS, ACT_THEME, ACT_HELP],
    [ikFit, ikOrigin, ikGrid, ikUnits, ikTheme, ikHelp],
    ['FIT', 'ORIGIN', 'GRID', 'UNITS', 'THEME', 'HELP'],
    ['Frame the whole drawing  (F)',
     'Put 0,0 under the cursor  (O)',
     'Show or hide the measured grid  (G)',
     'Feet-and-inches or metric  (U)',
     'Light chrome or dark  (T)',
     'Help, downloads and updates  (F1 for about)']);
end;

function TMainForm.DeckHit(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FDeck) do
    if PtInRect(FDeck[I].Bounds, Point(X, Y)) then
      Exit(I);
  Result := -1;
end;

function TMainForm.IconLit(Value: Integer): Boolean;
begin
  case Value of
    ACT_GRID: Result := FShowGrid;
    ACT_UNITS: Result := FD.Units = usMetric;
  else
    Result := False;
  end;
end;

function TMainForm.IconEnabled(Value: Integer): Boolean;
begin
  case Value of
    ACT_UNDO: Result := CanUndo;
    ACT_REDO: Result := CanRedo;
  else
    Result := True;
  end;
end;

{ A button's words, made to fit its width.  In order: the whole caption; the
  label cut to one word ("PRINT SCALE  1\"" to "SCALE  1\""); only the value
  after the double space; then cut with an ellipsis.  Text must never run
  over a neighbor. }
function FitCaption(C: TCanvas; const S: string; Room: Integer): string;
const
  SHORT: array[0..4, 0..1] of string = (
    ('PRINT SCALE', 'SCALE'), ('SNAP TO', 'SNAP'), ('LINE COLOR', 'COLOR'),
    ('LINE WIDTH', 'WIDTH'), ('ROUNDED TO', 'ROUND'));
var
  K, P: Integer;
begin
  Result := S;
  if (Room <= 0) or (C.TextWidth(Result) <= Room) then Exit;
  for K := 0 to High(SHORT) do
    if Pos(SHORT[K, 0], Result) = 1 then
    begin
      Result := SHORT[K, 1] + Copy(Result, Length(SHORT[K, 0]) + 1, MaxInt);
      Break;
    end;
  if C.TextWidth(Result) <= Room then Exit;
  P := Pos('  ', Result);
  if P > 0 then Result := Trim(Copy(Result, P + 2, MaxInt));
  if C.TextWidth(Result) <= Room then Exit;
  Result := CutToFit(C, Result, Room);
end;

procedure TMainForm.pbDeckPaint(Sender: TObject);
var
  Room: Integer;
  I, TW: Integer;
  It: TDeckItem;
  Sel, Hot, Ena: Boolean;
  C1, C2, Edge, Fg: TPix;
  R, IR: TRect;
  Pad, RowH, RowGap, Y0: Integer;

  function Selected(const A: TDeckItem): Boolean;
  begin
    Result := ((A.Group = GRP_TOOL) and (A.Value = Ord(FTool))) or
              ((A.Group = GRP_SCALE) and (A.Value = FD.ScaleIdx)) or
              ((A.Group = GRP_SNAP) and (A.Value = FD.SnapIdx));
  end;

  procedure Section(Row: Integer; const S: string);
  begin
    UIFont(pbDeck.Canvas, 10, True, Theme.TextDim);
    TrackedText(pbDeck.Canvas, Pad,
      Y0 + Row * (RowH + RowGap) + (RowH - pbDeck.Canvas.TextHeight('X')) div 2,
      S, Round(1.5 * FUIScale));
  end;

begin
  PaintPanel(FDeckSkin, Rect(0, 0, FDeckSkin.Width, FDeckSkin.Height), Theme,
    Round(16 * FUIScale));

  { a hairline down each gap, so the tool groups read as groups }
  if (FGrpDivY1 > FGrpDivY0) then
    for I := 0 to 1 do
      FDeckSkin.Line(FGrpDivX[I], FGrpDivY0, FGrpDivX[I], FGrpDivY1,
        Max(1.0, FUIScale), MixPix(Theme.Panel, Theme.TextDim, 0.9), 0.9);

  for I := 0 to High(FDeck) do
  begin
    It := FDeck[I];
    Hot := (I = FHotItem);
    R := It.Bounds;

    case It.Kind of
      dkSegment:
        begin
          Sel := Selected(It);
          if Sel then
          begin
            C1 := ShadePix(Theme.Accent, 1.10);
            C2 := ShadePix(Theme.Accent, 0.80);
            Edge := ShadePix(Theme.Accent, 0.55);
          end
          else if Hot then
          begin
            C1 := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.22);
            C2 := MixPix(Theme.Panel, Pix(255, 255, 255), 0.10);
            Edge := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.35);
          end
          else
          begin
            C1 := MixPix(Theme.PanelHi, Pix(0, 0, 0), 0.20);
            C2 := MixPix(Theme.Panel, Pix(0, 0, 0), 0.25);
            Edge := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.12);
          end;
          PaintPill(FDeckSkin, R, Round(8 * FUIScale), C1, C2, Edge);
          if (It.Group = GRP_TOOL) then
          begin
            if Sel then Fg := OnPix(Theme.Accent) else Fg := Theme.Text;
            IR := Rect(R.Left + Round(5 * FUIScale),
              R.Top + Round(3 * FUIScale),
              R.Left + Round(5 * FUIScale) + (R.Bottom - R.Top) - Round(6 * FUIScale),
              R.Bottom - Round(3 * FUIScale));
            PaintIcon(FDeckSkin, It.Icon, IR, Fg, 0.95);
          end;
          { the color button shows the color }
          if (It.Group = GRP_POPUP) and (It.Value = POP_COLOR) then
            PaintSwatch(FDeckSkin,
              Rect(R.Left + Round(7 * FUIScale), R.Top + Round(4 * FUIScale),
                   R.Left + Round(29 * FUIScale), R.Bottom - Round(4 * FUIScale)),
              ColorToPix(FInkColor), False, False, Theme);

          { a settings button says there is more behind it }
          if It.Group = GRP_POPUP then
          begin
            if Sel then Fg := OnPix(Theme.Accent) else Fg := Theme.TextDim;
            IR := Rect(R.Right - Round(16 * FUIScale), R.Top,
              R.Right - Round(3 * FUIScale), R.Bottom);
            PaintIcon(FDeckSkin, ikChevron, IR, Fg, 0.9);
          end;
        end;

      dkIcon:
        begin
          Ena := IconEnabled(It.Value);
          Sel := IconLit(It.Value);
          if Sel then
          begin
            C1 := ShadePix(Theme.Accent, 1.10);
            C2 := ShadePix(Theme.Accent, 0.80);
            Edge := ShadePix(Theme.Accent, 0.55);
            Fg := Pix(20, 20, 24);
          end
          else
          begin
            if Hot and Ena then
            begin
              C1 := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.22);
              C2 := MixPix(Theme.Panel, Pix(255, 255, 255), 0.10);
            end
            else
            begin
              C1 := MixPix(Theme.PanelHi, Pix(0, 0, 0), 0.20);
              C2 := MixPix(Theme.Panel, Pix(0, 0, 0), 0.25);
            end;
            Edge := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.12);
            Fg := Theme.Text;
          end;
          PaintPill(FDeckSkin, R, Round(8 * FUIScale), C1, C2, Edge);
          IR := R;
          InflateRect(IR, -Round(6 * FUIScale), -Round(6 * FUIScale));
          if Ena then
            PaintIcon(FDeckSkin, It.Icon, IR, Fg, 0.95)
          else
            PaintIcon(FDeckSkin, It.Icon, IR, Theme.TextDim, 0.35);
        end;

      dkNone: ;
    end;
  end;

  FDeckSkin.DrawTo(pbDeck.Canvas, 0, 0);

  Pad := Round(14 * FUIScale);
  RowH := DeckRowH;
  RowGap := Round(4 * FUIScale);
  Y0 := (FDeckSkin.Height - (DeckRows * RowH + (DeckRows - 1) * RowGap)) div 2;

  { tools are down the left; only settings here }
  Section(0, 'SETTINGS');

  for I := 0 to High(FDeck) do
  begin
    It := FDeck[I];
    if It.Kind <> dkSegment then Continue;
    if Selected(It) then
      UIFont(pbDeck.Canvas, 10, True, OnPix(Theme.Accent))
    else
      UIFont(pbDeck.Canvas, 10, False, Theme.Text);
    { room for the words after the swatch, the chevron and a margin }
    Room := It.Bounds.Right - It.Bounds.Left - Round(10 * FUIScale);
    if It.Group = GRP_POPUP then Dec(Room, Round(16 * FUIScale));
    if (It.Group = GRP_POPUP) and (It.Value = POP_COLOR) then
      Dec(Room, Round(24 * FUIScale));
    if (It.Group = GRP_TOOL) then
      Dec(Room, Round(18 * FUIScale));
    It.Caption := FitCaption(pbDeck.Canvas, It.Caption, Room);
    TW := pbDeck.Canvas.TextWidth(It.Caption);
    { a tool shows its glyph, the same one that follows the cursor }
    if (It.Group = GRP_POPUP) and (It.Value = POP_COLOR) then
      pbDeck.Canvas.TextOut(
        It.Bounds.Left + (It.Bounds.Right - It.Bounds.Left - TW +
          Round(24 * FUIScale)) div 2,
        (It.Bounds.Top + It.Bounds.Bottom - pbDeck.Canvas.TextHeight(It.Caption)) div 2,
        It.Caption)
    else if (It.Group = GRP_TOOL) then
      pbDeck.Canvas.TextOut(
        It.Bounds.Left + (It.Bounds.Right - It.Bounds.Left - TW +
          Round(18 * FUIScale)) div 2,
        (It.Bounds.Top + It.Bounds.Bottom - pbDeck.Canvas.TextHeight(It.Caption)) div 2,
        It.Caption)
    else
      pbDeck.Canvas.TextOut(
        (It.Bounds.Left + It.Bounds.Right - TW) div 2,
        (It.Bounds.Top + It.Bounds.Bottom - pbDeck.Canvas.TextHeight(It.Caption)) div 2,
        It.Caption);
  end;
end;

procedure TMainForm.pbDeckMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  H: Integer;
begin
  H := DeckHit(X, Y);
  if H <> FHotItem then
  begin
    FHotItem := H;
    { a real tooltip too, since the icons say nothing about themselves }
    if H >= 0 then pbDeck.Hint := FDeck[H].Hint else pbDeck.Hint := '';
    Application.CancelHint;
    pbDeck.Invalidate;
    Invalidate;
  end;
end;

procedure TMainForm.pbDeckMouseLeave(Sender: TObject);
begin
  if FHotItem <> -1 then
  begin
    FHotItem := -1;
    pbDeck.Hint := '';
    Application.CancelHint;
    pbDeck.Invalidate;
    Invalidate;
  end;
end;

procedure TMainForm.pbDeckMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  H: Integer;
begin
  if Button <> mbLeft then Exit;
  H := DeckHit(X, Y);
  if H >= 0 then DeckActivate(H);
end;

procedure TMainForm.DeckActivate(Index: Integer);
var
  It: TDeckItem;
begin
  if (Index < 0) or (Index > High(FDeck)) then Exit;
  It := FDeck[Index];
  case It.Group of
    GRP_TOOL:
      if TTool(It.Value) = FTool then
        SetTool(ptSelect)          // clicking the lit tool puts it away
      else
        SetTool(TTool(It.Value));
    GRP_POPUP:
      { clicking the open one shuts it, as a menu button does }
      if FPopup = It.Value then ClosePopup else OpenPopup(It.Value);
    GRP_SCALE: SetScaleIdx(It.Value);
    GRP_SNAP:  begin
                 FD.SnapIdx := It.Value;
                 Act('snap ' + IntToStr(It.Value));
                 pbDeck.Invalidate;
                 pbCmd.Invalidate;
               end;
    GRP_ICON: DoAction(It.Value);
  end;
end;

{ One action, whichever button asked for it: the deck and the quick strip
  share this so Save means the same everywhere. }
procedure TMainForm.DoAction(A: Integer);
begin
  case A of
    ACT_UNDO:   DoUndo;
    ACT_REDO:   DoRedo;
    ACT_SAVE:   DoSave;
    ACT_PRINT:  DoPrint;
    ACT_THEME:  CycleTheme(1);
    ACT_GRID:   begin
                  FShowGrid := not FShowGrid;
                  RepaintPaper;
                  RecomposeAll;
                  pbDeck.Invalidate;
                end;
    ACT_HELP:   if FPopup = POP_HELP then ClosePopup else OpenPopup(POP_HELP);
    ACT_UNITS:  SetUnits(TUnitSystem(1 - Ord(FD.Units)));
    ACT_ORIGIN: SetOriginHere;
    ACT_FIT:    FitView;
    ACT_OPEN:   DoOpen;
    ACT_MENU:   ShowFileMenu;
    ACT_EXPORT: DoExport;
    ACT_GUIDES:
      begin
        FD.Doc.GuidesHidden := not FD.Doc.GuidesHidden;
        FCmdMsg := IfThen(FD.Doc.GuidesHidden,
          'Guides put away.  They are still in the drawing.',
          'Guides back.');
        RenderInk;
        RecomposeAll;
      end;
    ACT_NOGUIDE:
      begin
        PushUndo;
        FCmdMsg := Format('Cleared %d guides.', [FD.Doc.ClearGuides]);
        RenderInk;
        RecomposeAll;
      end;
  end;
end;

{ Park on a named camera.  Free orbiting sets FViewPreset to -1, so the next
  press starts again at the corner view. }
procedure TMainForm.ApplyViewPreset(I: Integer);
var
  N: Integer;
  Turn: Boolean;
  FitZ, FitX, FitY: Double;
begin
  N := Length(VIEW_PRESETS);
  Turn := (FD <> nil) and (FD.View = vkOrbit) and
          (VIEW_PRESETS[((I mod N) + N) mod N].View = vkOrbit) and FBooted;
  FViewPreset := ((I mod N) + N) mod N;
  FD.View := VIEW_PRESETS[FViewPreset].View;
  { One 3D view to another glides; a change of view kind (into or out of
    the paper modes) snaps, since one projection cannot turn into another. }
  if Turn then
  begin
    { a preset reframes, so the glide aims at the final framing instead of
      popping into it on arrival }
    if FitTarget(Length(FSel) > 0, VIEW_PRESETS[FViewPreset].Az,
         VIEW_PRESETS[FViewPreset].El, FitZ, FitX, FitY) then
      GlideCamera(VIEW_PRESETS[FViewPreset].Az, VIEW_PRESETS[FViewPreset].El,
        FitZ, FitX, FitY)
    else
      GlideTo(VIEW_PRESETS[FViewPreset].Az, VIEW_PRESETS[FViewPreset].El);
  end
  else
  begin
    FD.Az := VIEW_PRESETS[FViewPreset].Az;
    FD.El := VIEW_PRESETS[FViewPreset].El;
  end;
  if FD.View <> vkOrbit then FD.Plane := plXY;
  { this can reach PLAN, so the cut strip must come and go and the top row
    be laid out again }
  ApplySlice;
  Relayout;
  FCmdMsg := VIEW_PRESETS[FViewPreset].Name + ' view.';
  if FD.View = vkPlan then
    FCmdMsg := FCmdMsg + '  CUT, top right, slices it - Ctrl+wheel travels ' +
      'up and down.';
  { the glide carries the framing; a change of view kind still snaps to fit }
  if FGlideT = 0 then FitView(False);
  RebuildDeck;
  pbDeck.Invalidate;
  pbView.Invalidate;
  pbSlice.Invalidate;
  pbCmd.Invalidate;
end;

procedure TMainForm.CycleViewPreset(Step: Integer);
var
  N, I: Integer;
begin
  { Off the presets (a paper mode or orbited free), either direction goes to
    the first corner; on them, step round the camera presets. }
  N := High(VIEW_PRESETS) - FIRST_CAMERA_PRESET + 1;
  if (FViewPreset < FIRST_CAMERA_PRESET) or (FD.View <> vkOrbit) then
    I := FIRST_CAMERA_PRESET
  else
    I := FIRST_CAMERA_PRESET + (((FViewPreset - FIRST_CAMERA_PRESET + Step) mod N) + N) mod N;
  ApplyViewPreset(I);
end;

{ Push the sheet's slice into the document, or take it away.  A slice only
  applies in PLAN; in 3D it would hide half the model for no visible reason.
  The document uses the same range for drawing and picking.  Called wherever
  the answer could change, so the sheet and document never disagree (that
  makes geometry invisible but still snappable). }
procedure TMainForm.ApplySlice;
begin
  if FD = nil then Exit;
  FD.Doc.SetSlice(FD.SliceOn and (FD.View = vkPlan), FD.SliceLo, FD.SliceHi);
end;

procedure TMainForm.SetSlice(AOn: Boolean; ALo, AHi: Double; const Why: string);
var
  T: Double;
  N: Integer;
begin
  if AHi < ALo then begin T := ALo; ALo := AHi; AHi := T; end;
  FD.SliceOn := AOn;
  FD.SliceLo := ALo;
  FD.SliceHi := AHi;
  ApplySlice;
  RenderInk;
  RecomposeAll;
  if Assigned(pbSlice) then pbSlice.Invalidate;
  Invalidate;
  if Why <> '' then FCmdMsg := Why
  else if not AOn then FCmdMsg := 'Cut off - the whole model is in the drawing.'
  else
  begin
    N := FD.Doc.OutsideSlice;
    { say what is kept out, so a drawing that vanished is explained }
    if N = 0 then
      FCmdMsg := Format('Cut %s to %s - everything is in it.',
        [FormatLen(ALo, FD.Units), FormatLen(AHi, FD.Units)])
    else
      FCmdMsg := Format('Cut %s to %s - %d thing%s outside it.',
        [FormatLen(ALo, FD.Units), FormatLen(AHi, FD.Units), N,
         IfThen(N = 1, '', 's')]);
  end;
  InvalidateStatus;
  pbCmd.Invalidate;
end;

{ Move the slice by whole snap steps.  Which: 0 slides both ends, 1 the
  bottom alone, 2 the top. }
procedure TMainForm.NudgeSlice(Steps: Integer; Which: Integer);
var
  D, Lo, Hi: Double;
begin
  if Steps = 0 then Exit;
  { steps by the snap, so there is no second setting to find }
  D := SnapStep;
  if D <= 0 then D := 1 / 12;
  D := D * Steps;
  Lo := FD.SliceLo;
  Hi := FD.SliceHi;
  case Which of
    1: Lo := Lo + D;
    2: Hi := Hi + D;
  else
    begin Lo := Lo + D; Hi := Hi + D; end;
  end;
  { the bottom cannot pass the top, or the slice turns inside out under the
    wheel }
  if Which = 1 then Lo := Min(Lo, Hi);
  if Which = 2 then Hi := Max(Hi, Lo);
  SetSlice(True, Lo, Hi);
end;

{ "Plan from here": the clicked floor becomes the bottom of the slice and the
  top goes one story above it. }
procedure TMainForm.PlanFromFace(Face: Integer);
var
  Lo, Hi: Double;
  K: Integer;
  Poly: TP3Array;
begin
  if (Face < 0) or (Face >= FD.Doc.Live) then Exit;
  Poly := FD.Doc[Face].Poly;
  if Length(Poly) = 0 then Exit;
  Lo := Poly[0].Z;
  for K := 1 to High(Poly) do Lo := Min(Lo, Poly[K].Z);
  { One story (8' or 2.5 m), not the 4' a real cut plane uses: this is also
    the drawing plane and you want to see the whole floor. }
  if FD.Units = usImperial then Hi := Lo + 8 else Hi := Lo + 2.5;
  if FD.View <> vkPlan then SetView(vkPlan);
  SetSlice(True, Lo, Hi,
    Format('Plan from %s, up to %s.  Ctrl+wheel travels up and down.',
      [FormatLen(Lo, FD.Units), FormatLen(Hi, FD.Units)]));
end;

function TMainForm.SliceText: string;
begin
  if not FD.SliceOn then Result := 'CUT  off'
  else Result := Format('CUT  %s - %s',
    [FormatLen(FD.SliceLo, FD.Units), FormatLen(FD.SliceHi, FD.Units)]);
end;

procedure TMainForm.SetView(V: TViewKind);
begin
  FViewPreset := -1;
  if V = FD.View then Exit;
  Trail('view ' + VIEW_NAMES[V]);
  Act('view ' + VIEW_NAMES[V]);
  FD.View := V;
  if V <> vkOrbit then FD.Plane := plXY;
  { the slice is plan only, so entering or leaving plan turns it on or off }
  ApplySlice;
  { the cut strip comes and goes with the view, so lay out the top row again }
  Relayout;
  { the projection changed, so there is nothing to glide between }
  FitView(False);
  RebuildDeck;
  pbDeck.Invalidate;
  pbView.Invalidate;
  pbSlice.Invalidate;
  case V of
    vkPlan: FCmdMsg := 'Plan view.';
    vkIso: FCmdMsg := 'Isometric view.';
  else
    FCmdMsg := '3D view - middle-drag to orbit.';
  end;
  pbCmd.Invalidate;
end;

{ The view button.  There is one drawing and one camera; the button offers
  where to park it (corners, top, sides) and shows the name of the view it is
  on, or 3D once orbited off it.  The paper modes are reached from the Create
  menu. }
procedure TMainForm.pbViewPaint(Sender: TObject);
var
  W, H: Integer;
  R: TRect;
  S: string;
begin
  W := pbView.Width;
  H := pbView.Height;
  FViewSkin.SetSize(W, H);
  FViewSkin.Clear(Pix(0, 0, 0));
  FViewSkin.CopyRegion(FShell, pbView.Left, pbView.Top, 0, 0, W, H);
  FViewSkin.RoundRectV(Rect(0, 0, W, H), H / 2,
    MixPix(Theme.Panel, Pix(0, 0, 0), 0.20), MixPix(Theme.Panel, Pix(0, 0, 0), 0.42));
  FViewSkin.RoundFrame(Rect(0, 0, W, H), H / 2, 1.0,
    MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.14));
  { the name on the left, the arrow on the right; each lights on hover }
  if FHotView = 0 then
    FViewSkin.RoundRect(Rect(3, 3, W - VIEW_ARROW_W, H - 3), (H - 6) / 2,
      MixPix(Theme.Panel, Pix(255, 255, 255), 0.10))
  else if FHotView = 1 then
    FViewSkin.RoundRect(Rect(W - VIEW_ARROW_W, 3, W - 3, H - 3), (H - 6) / 2,
      MixPix(Theme.Panel, Pix(255, 255, 255), 0.10));
  FViewSkin.Line(W - VIEW_ARROW_W, 6, W - VIEW_ARROW_W, H - 6, 1,
    MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.14), 1.0);
  FViewSkin.DrawTo(pbView.Canvas, 0, 0);

  S := ViewButtonName;
  UIFont(pbView.Canvas, 10, True, Theme.Text);
  pbView.Canvas.TextOut(((W - VIEW_ARROW_W) - pbView.Canvas.TextWidth(S)) div 2,
    (H - pbView.Canvas.TextHeight(S)) div 2, S);
  { the arrow: a small filled triangle }
  pbView.Canvas.Brush.Style := bsSolid;
  pbView.Canvas.Brush.Color := PixToColor(Theme.Text);
  pbView.Canvas.Pen.Color := PixToColor(Theme.Text);
  pbView.Canvas.Polygon([Point(W - VIEW_ARROW_W div 2 - 5, H div 2 - 3),
                         Point(W - VIEW_ARROW_W div 2 + 5, H div 2 - 3),
                         Point(W - VIEW_ARROW_W div 2, H div 2 + 3)]);
  pbView.Canvas.Brush.Style := bsClear;
end;

{ ---------------------------------------------------------------------- }
{ the file buttons, top left                                               }
{ ---------------------------------------------------------------------- }

{ File menu, undo and redo at the top left, where every program keeps them.
  Hover notes are drawn beside what is hovered (see PaintChromeTip). }
const
  { MENU is the file menu: new, open, recent, save, save as, export, print,
    close }
  QUICK_ACTS: array[0..2] of Integer =
    (ACT_MENU, ACT_UNDO, ACT_REDO);
  QUICK_ICONS: array[0..2] of TIconKind =
    (ikOpen, ikUndo, ikRedo);
  QUICK_TIPS: array[0..2] of string = (
    'New, open, open recent, save, save as, export, print, close - the file.  Ctrl+O opens, Ctrl+S saves, ' +
      'Ctrl+E exports, Ctrl+P prints',
    'Undo.  Ctrl+Z',
    'Redo.  Ctrl+Y');
  { a gap before undo and redo: they act on the drawing, the menu on the file }
  QUICK_GAP_BEFORE = 1;
  QUICK_NAMES: array[0..2] of string =
    ('MENU', 'UNDO', 'REDO');

function TMainForm.QuickWidth: Integer;
begin
  Result := Length(QUICK_ACTS) * Round(74 * FUIScale) +
            Round(12 * FUIScale);
end;

procedure TMainForm.RebuildQuick;
var
  I, BW, X, H: Integer;
begin
  SetLength(FQuick, 0);
  BW := Round(74 * FUIScale);
  H := pbQuick.Height;
  X := 0;
  for I := 0 to High(QUICK_ACTS) do
  begin
    if I = QUICK_GAP_BEFORE then Inc(X, Round(12 * FUIScale));
    SetLength(FQuick, Length(FQuick) + 1);
    with FQuick[High(FQuick)] do
    begin
      Kind := dkSegment;
      Bounds := Rect(X + 1, 1, X + BW - 1, H - 1);
      Group := GRP_ICON;
      Value := QUICK_ACTS[I];
      Caption := QUICK_NAMES[I];
      Hint := QUICK_TIPS[I];
      Icon := QUICK_ICONS[I];
    end;
    Inc(X, BW);
  end;
end;

function TMainForm.QuickHit(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FQuick) do
    if PtInRect(FQuick[I].Bounds, Point(X, Y)) then Exit(I);
  Result := -1;
end;

procedure TMainForm.pbQuickPaint(Sender: TObject);
var
  I, W, H, IconSz: Integer;
  R, IR: TRect;
  Fg: TPix;
  Ena: Boolean;
begin
  W := pbQuick.Width;
  H := pbQuick.Height;
  if (W < 8) or (H < 8) then Exit;
  FQuickSkin.SetSize(W, H);
  FQuickSkin.Clear(Pix(0, 0, 0));
  FQuickSkin.CopyRegion(FShell, pbQuick.Left, pbQuick.Top, 0, 0, W, H);

  IconSz := Round(15 * FUIScale);
  for I := 0 to High(FQuick) do
  begin
    R := FQuick[I].Bounds;
    { grayed when it would do nothing, so the row shows the drawing's state }
    Ena := True;
    if FQuick[I].Value = ACT_UNDO then Ena := FD.UndoTop > 0
    else if FQuick[I].Value = ACT_REDO then Ena := FD.RedoTop > 0;
    if I = FHotQuick then
    begin
      FQuickSkin.RoundRect(R, Round(4 * FUIScale),
        MixPix(Theme.Panel, Pix(255, 255, 255), 0.16));
      FQuickSkin.RoundFrame(R, Round(4 * FUIScale), 1.0,
        MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.16));
    end;
    { grayed but still readable on the pale theme }
    if Ena then Fg := Theme.Text
    else Fg := MixPix(Theme.TextDim, Theme.Shell1, 0.30);
    IR := Rect(R.Left + Round(6 * FUIScale),
               (R.Top + R.Bottom - IconSz) div 2,
               R.Left + Round(6 * FUIScale) + IconSz,
               (R.Top + R.Bottom + IconSz) div 2);
    PaintIcon(FQuickSkin, FQuick[I].Icon, IR, Fg);
  end;
  FQuickSkin.DrawTo(pbQuick.Canvas, 0, 0);

  { the word beside the picture; a floppy disk icon means nothing to many }
  for I := 0 to High(FQuick) do
  begin
    R := FQuick[I].Bounds;
    Ena := True;
    if FQuick[I].Value = ACT_UNDO then Ena := FD.UndoTop > 0
    else if FQuick[I].Value = ACT_REDO then Ena := FD.RedoTop > 0;
    if Ena then UIFont(pbQuick.Canvas, 10, True, Theme.Text)
    else UIFont(pbQuick.Canvas, 10, True,
                MixPix(Theme.TextDim, Theme.Shell1, 0.30));
    pbQuick.Canvas.TextOut(R.Left + Round(8 * FUIScale) + IconSz,
      (R.Top + R.Bottom - pbQuick.Canvas.TextHeight('X')) div 2,
      FQuick[I].Caption);
  end;
end;

procedure TMainForm.pbQuickMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  H: Integer;
begin
  H := QuickHit(X, Y);
  if H <> FHotQuick then
  begin
    FHotQuick := H;
    pbQuick.Invalidate;
  end;
  if (H >= 0) and (H <= High(FQuick)) then
  begin
    FChromeTip := QUICK_NAMES[H];
    FChromeTipBody := FQuick[H].Hint;
    FChromeTipX := EnsureRange(pbQuick.Left + FQuick[H].Bounds.Left -
                     pbScreen.Left, 4, Max(4, pbScreen.Width - 40));
    FChromeTipY := Round(24 * FUIScale);
  end
  else
  begin
    FChromeTip := '';
    FChromeTipBody := '';
  end;
  pbScreen.Invalidate;
end;

procedure TMainForm.pbQuickMouseLeave(Sender: TObject);
begin
  if FHotQuick <> -1 then
  begin
    FHotQuick := -1;
    pbQuick.Invalidate;
  end;
  FChromeTip := '';
  FChromeTipBody := '';
  pbScreen.Invalidate;
end;

procedure TMainForm.pbQuickMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  H: Integer;
begin
  if Button <> mbLeft then Exit;
  H := QuickHit(X, Y);
  if (H < 0) or (H > High(FQuick)) then Exit;
  DoAction(FQuick[H].Value);
  pbQuick.Invalidate;
end;

{ ---------------------------------------------------------------------- }
{ the tool strip down the left                                             }
{ ---------------------------------------------------------------------- }

{ Tools stand in a column on the left with their names beside them.  Screens
  are wide and short, so a column costs the plentiful dimension.  Left, as in
  every drawing program; not floating or dockable, so it cannot get lost.
  Names are on by default on purpose: nobody can tell Offset from Drill by
  pictogram.  The arrow at the bottom collapses it, and that is remembered. }
function TMainForm.ToolStripWidth: Integer;
begin
  if FToolsWide then Result := Round(126 * FUIScale)
  else Result := Round(42 * FUIScale);
end;

procedure TMainForm.RebuildTools;
var
  I, K, RowH, Gap, Y, W, Brk, BrkH, Need: Integer;

  procedure Add(AKind: TDeckKind; const R: TRect; AGroup, AValue: Integer;
    const ACap, AHint: string; AIcon: TIconKind);
  begin
    SetLength(FTools, Length(FTools) + 1);
    with FTools[High(FTools)] do
    begin
      Kind := AKind; Bounds := R; Group := AGroup; Value := AValue;
      Caption := ACap; Hint := AHint; Icon := AIcon;
    end;
  end;

begin
  SetLength(FTools, 0);
  W := pbTools.Width;
  if W < 8 then Exit;
  { the shop sits at the very foot; worked out first so the tools stop above
    it }
  FShopTop := pbTools.Height - Round(56 * FUIScale);

  { Rows at full height unless the window is too short, then tighter down to
    a floor, so the list never runs under MORE and SHOP.  Everything scales
    together so it still reads as one list. }
  Brk := 0;
  for I := 0 to High(MAIN_TOOLS) do
    for K := 0 to High(MAIN_BREAKS) do
      if MAIN_BREAKS[K] = I + 1 then Inc(Brk);
  RowH := Round(26 * FUIScale);
  Gap := Round(3 * FUIScale);
  BrkH := Round(8 * FUIScale);
  while RowH > Round(17 * FUIScale) do
  begin
    Need := Round(6 * FUIScale) + Length(MAIN_TOOLS) * (RowH + Gap) +
      Brk * BrkH + Round(4 * FUIScale) + RowH + Round(4 * FUIScale);
    if Need <= FShopTop then Break;
    Dec(RowH);
    if Gap > 1 then Dec(Gap);
    if BrkH > Round(4 * FUIScale) then Dec(BrkH);
  end;
  Y := Round(6 * FUIScale);

  SetLength(FToolRules, 0);
  for I := 0 to High(MAIN_TOOLS) do
  begin
    Add(dkSegment, Rect(Round(4 * FUIScale), Y, W - Round(4 * FUIScale), Y + RowH),
      GRP_TOOL, Ord(MAIN_TOOLS[I]), TOOL_NAMES[MAIN_TOOLS[I]],
      TOOL_HINTS[MAIN_TOOLS[I]], TOOL_ICONS[MAIN_TOOLS[I]]);
    Inc(Y, RowH + Gap);
    for K := 0 to High(MAIN_BREAKS) do
      if MAIN_BREAKS[K] = I + 1 then
      begin
        SetLength(FToolRules, Length(FToolRules) + 1);
        FToolRules[High(FToolRules)] := Y + BrkH div 2 - Round(1 * FUIScale);
        Inc(Y, BrkH);
        Break;
      end;
  end;

  { MORE comes right after the tools and looks like one }
  Inc(Y, Round(4 * FUIScale));
  Add(dkSegment, Rect(Round(4 * FUIScale), Y, W - Round(4 * FUIScale), Y + RowH),
    GRP_POPUP, POP_MORE, 'MORE TOOLS',
    'Rotate, offset and drill.', ikChevron);

  { The shop at the very foot, apart, with a spanner: it is a door into the
    trade wizards, not a drawing tool, and should not look like half of MORE. }
  Add(dkSegment, Rect(Round(4 * FUIScale), FShopTop,
    W - Round(4 * FUIScale), FShopTop + Round(26 * FUIScale)),
    GRP_POPUP, POP_SHOP, 'SHOP',
    'Sheet metal and pipe: laying a piece out flat, duct fittings, spools.',
    ikShop);
end;

function TMainForm.ToolsHit(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FTools) do
    if PtInRect(FTools[I].Bounds, Point(X, Y)) then Exit(I);
  { the bottom strip is the collapse arrow }
  if Y > pbTools.Height - Round(26 * FUIScale) then Exit(-2);
  Result := -1;
end;

{ The groups panel, SketchUp's Outliner: every group as a tree, to pick,
  put away and bring back.  The stairs, radiant layouts and jigs all make
  groups, so this is how to find them.  Painted by hand like the entity
  panel, from rows rebuilt each paint by scanning the ekPart records; a list
  kept up to date from many places would go stale. }
function TMainForm.GroupsPanelOn: Boolean;
begin
  Result := FGroupsOn;
end;

procedure TMainForm.SetGroupsPanel(On_: Boolean);
begin
  FGroupsOn := On_;
  FGrpSig := -1;
  FGrpHot := -1;
  FGrpHotId := 0;
  Relayout;
  if FGroupsOn then
    FCmdMsg := 'The groups are listed on the right.  Click one to pick it, ' +
      'double-click to work inside it, untick to put it away.'
  else
    FCmdMsg := 'Groups panel off.  /groups brings it back.';
  InvalidateStatus;
  Invalidate;
end;

procedure TMainForm.GroupsChanged;
begin
  if pbGroups.Visible then pbGroups.Invalidate;
end;

procedure TMainForm.RebuildGroupRows;
var
  Ids, Par: array of Integer;
  I, N: Integer;

  function Folded(Id: Integer): Boolean;
  var
    K: Integer;
  begin
    Result := False;
    for K := 0 to High(FGrpFold) do
      if FGrpFold[K] = Id then Exit(True);
  end;

  procedure Add(Id, Depth: Integer; Kids: Boolean);
  begin
    SetLength(FGrpRows, Length(FGrpRows) + 1);
    FGrpRows[High(FGrpRows)].Id := Id;
    FGrpRows[High(FGrpRows)].Depth := Depth;
    FGrpRows[High(FGrpRows)].Kids := Kids;
    FGrpRows[High(FGrpRows)].Fold := Rect(0, 0, 0, 0);
    FGrpRows[High(FGrpRows)].Tick := Rect(0, 0, 0, 0);
  end;

  procedure Walk(Parent, Depth: Integer);
  var
    K, J: Integer;
    Kids: Boolean;
  begin
    { a hand-edited file could loop a group into itself; nobody nests 40 deep }
    if Depth > 40 then Exit;
    for K := 0 to N - 1 do
      if Par[K] = Parent then
      begin
        Kids := False;
        for J := 0 to N - 1 do
          if Par[J] = Ids[K] then begin Kids := True; Break; end;
        Add(Ids[K], Depth, Kids);
        if Kids and not Folded(Ids[K]) then Walk(Ids[K], Depth + 1);
      end;
  end;

begin
  FGrpRows := nil;
  Ids := nil;
  Par := nil;
  N := 0;
  for I := 0 to FD.Doc.Live - 1 do
    if FD.Doc[I].Kind = ekPart then
    begin
      SetLength(Ids, N + 1);
      SetLength(Par, N + 1);
      Ids[N] := FD.Doc[I].Grp;
      Par[N] := FD.Doc[I].Part;
      Inc(N);
    end;
  { a group whose parent is gone goes at the top level }
  for I := 0 to N - 1 do
    if (Par[I] <> 0) and (FD.Doc.PartEnt(Par[I]) < 0) then Par[I] := 0;
  Add(0, 0, N > 0);
  Walk(0, 1);
end;

function TMainForm.GroupRowAt(Y: Integer): Integer;
var
  Top_, RowH: Integer;
begin
  Result := -1;
  RowH := Round(20 * FUIScale);
  Top_ := Round(10 * FUIScale) + RowH + Round(4 * FUIScale);
  if Y < Top_ then Exit;
  Result := FGrpScroll + (Y - Top_) div RowH;
  if Result > High(FGrpRows) then Result := -1;
end;

{ put away, itself or by a group it is in }
function TMainForm.GroupPutAway(Id: Integer): Boolean;
var
  Guard: Integer;
begin
  Result := False;
  Guard := 0;
  while (Id > 0) and (Guard < 1000) do
  begin
    if FD.Doc.PartHidden(Id) then Exit(True);
    Id := FD.Doc.PartParent(Id);
    Inc(Guard);
  end;
end;

procedure TMainForm.pbGroupsPaint(Sender: TObject);
var
  I, W, H, Y, X, RowH, Pad, Ind, Box, Shown, Top_, TW: Integer;
  C: TCanvas;
  S, Tag_: string;
  Picked: TIntArrayW;
  Sel, Away: Boolean;
  Tri: array[0..2] of TPoint;
  K: Integer;
begin
  W := pbGroups.Width;
  H := pbGroups.Height;
  if (W < 8) or (H < 8) then Exit;
  RebuildGroupRows;
  FGrpSkin.SetSize(W, H);
  PaintPanel(FGrpSkin, Rect(0, 0, W, H), Theme, FUIScale);
  FGrpSkin.DrawTo(pbGroups.Canvas, 0, 0);
  C := pbGroups.Canvas;
  Pad := Round(10 * FUIScale);
  RowH := Round(20 * FUIScale);
  Ind := Round(13 * FUIScale);
  Box := Round(11 * FUIScale);

  UIFont(C, 8, True, Theme.Accent);
  C.TextOut(Pad, Pad, 'GROUPS');
  UIFont(C, 8, False, Theme.TextDim);
  { count every group, folded or not }
  K := 0;
  for I := 0 to FD.Doc.Live - 1 do
    if FD.Doc[I].Kind = ekPart then Inc(K);
  S := IntToStr(K);
  C.TextOut(W - Pad - C.TextWidth(S), Pad, S);
  Top_ := Pad + RowH + Round(4 * FUIScale);
  C.Pen.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.14));
  C.Pen.Width := 1;
  C.MoveTo(Pad, Top_ - Round(3 * FUIScale));
  C.LineTo(W - Pad, Top_ - Round(3 * FUIScale));

  Shown := Max(1, (H - Top_ - Pad div 2) div RowH);
  FGrpScroll := EnsureRange(FGrpScroll, 0, Max(0, Length(FGrpRows) - Shown));
  Picked := SelectedGroups;

  Y := Top_;
  for I := FGrpScroll to High(FGrpRows) do
  begin
    if Y + RowH > H - Pad div 2 then Break;
    Sel := False;
    for K := 0 to High(Picked) do
      if Picked[K] = FGrpRows[I].Id then Sel := True;
    Away := (FGrpRows[I].Id > 0) and GroupPutAway(FGrpRows[I].Id);

    if Sel or (I = FGrpHot) then
    begin
      C.Brush.Style := bsSolid;
      if Sel then C.Brush.Color := PixToColor(MixPix(Theme.PanelHi, Theme.Accent, 0.35))
      else C.Brush.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.08));
      C.Pen.Style := psClear;
      C.Rectangle(Pad div 2, Y, W - Pad div 2, Y + RowH);
      C.Pen.Style := psSolid;
      C.Brush.Style := bsClear;
    end;

    X := Pad + Max(0, FGrpRows[I].Depth - 1) * Ind;
    { the fold: a small triangle, pointing down when open }
    FGrpRows[I].Fold := Rect(0, 0, 0, 0);
    if (FGrpRows[I].Id > 0) and FGrpRows[I].Kids then
    begin
      FGrpRows[I].Fold := Rect(X - 2, Y, X + Ind, Y + RowH);
      C.Brush.Style := bsSolid;
      C.Brush.Color := PixToColor(Theme.TextDim);
      C.Pen.Color := PixToColor(Theme.TextDim);
      K := Round(4 * FUIScale);
      if (FGrpRows[I + Ord(I < High(FGrpRows))].Depth > FGrpRows[I].Depth) and
         (I < High(FGrpRows)) then
      begin
        Tri[0] := Point(X, Y + RowH div 2 - K div 2);
        Tri[1] := Point(X + 2 * K, Y + RowH div 2 - K div 2);
        Tri[2] := Point(X + K, Y + RowH div 2 + K);
      end
      else
      begin
        Tri[0] := Point(X + K div 2, Y + RowH div 2 - K);
        Tri[1] := Point(X + K div 2, Y + RowH div 2 + K);
        Tri[2] := Point(X + K div 2 + K + 1, Y + RowH div 2);
      end;
      C.Polygon(Tri);
      C.Brush.Style := bsClear;
    end;
    if FGrpRows[I].Id > 0 then Inc(X, Ind);

    { the box: ticked is on the sheet, unticked is put away }
    FGrpRows[I].Tick := Rect(0, 0, 0, 0);
    if FGrpRows[I].Id > 0 then
    begin
      FGrpRows[I].Tick := Rect(X, Y + (RowH - Box) div 2, X + Box, Y + (RowH - Box) div 2 + Box);
      C.Brush.Style := bsSolid;
      C.Brush.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.10));
      C.Pen.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.40));
      C.Pen.Width := 1;
      C.Rectangle(FGrpRows[I].Tick);
      C.Brush.Style := bsClear;
      if not FD.Doc.PartHidden(FGrpRows[I].Id) then
      begin
        C.Pen.Color := PixToColor(Theme.Accent);
        C.Pen.Width := Max(2, Round(2 * FUIScale));
        with FGrpRows[I].Tick do
        begin
          C.MoveTo(Left + 2, Top + Box div 2);
          C.LineTo(Left + Box * 2 div 5, Bottom - 3);
          C.LineTo(Right - 2, Top + 2);
        end;
        C.Pen.Width := 1;
      end;
      Inc(X, Box + Round(6 * FUIScale));
    end;

    { the name, and a tag if it is open or locked }
    if FGrpRows[I].Id = 0 then
    begin
      S := 'The whole sheet';
      if FD.Doc.Context = 0 then UIFont(C, 9, True, Theme.Text)
      else UIFont(C, 9, False, Theme.TextDim);
    end
    else
    begin
      S := FD.Doc.PartName(FGrpRows[I].Id);
      if FD.Doc.Context = FGrpRows[I].Id then UIFont(C, 9, True, Theme.Accent)
      else if Away then UIFont(C, 9, False, Theme.TextDim)
      else UIFont(C, 9, False, Theme.Text);
    end;
    Tag_ := '';
    if FGrpRows[I].Id > 0 then
    begin
      if FD.Doc.Context = FGrpRows[I].Id then Tag_ := 'open'
      else if FD.Doc.PartLocked(FGrpRows[I].Id) then Tag_ := 'locked';
    end;
    TW := 0;
    if Tag_ <> '' then
    begin
      UIFont(C, 8, False, Theme.TextDim);
      TW := C.TextWidth(Tag_) + Round(6 * FUIScale);
      C.TextOut(W - Pad - C.TextWidth(Tag_), Y + (RowH - C.TextHeight('X')) div 2, Tag_);
      if FGrpRows[I].Id = FD.Doc.Context then UIFont(C, 9, True, Theme.Accent)
      else if Away then UIFont(C, 9, False, Theme.TextDim)
      else UIFont(C, 9, False, Theme.Text);
    end;
    S := CutToFit(C, S, W - Pad - TW - X);
    C.TextOut(X, Y + (RowH - C.TextHeight('X')) div 2, S);
    Inc(Y, RowH);
  end;

  if Length(FGrpRows) <= 1 then
  begin
    UIFont(C, 8, False, Theme.TextDim);
    C.TextOut(Pad, Y + Round(6 * FUIScale), 'No groups on this sheet.');
    C.TextOut(Pad, Y + Round(6 * FUIScale) + RowH, 'Pick things, then /group -');
    C.TextOut(Pad, Y + Round(6 * FUIScale) + 2 * RowH, 'the stairs and radiant make');
    C.TextOut(Pad, Y + Round(6 * FUIScale) + 3 * RowH, 'their own.');
  end
  else if FGrpScroll + Shown < Length(FGrpRows) then
  begin
    UIFont(C, 8, False, Theme.TextDim);
    S := Format('%d more - scroll', [Length(FGrpRows) - FGrpScroll - Shown]);
    C.TextOut(W - Pad - C.TextWidth(S), H - Pad div 2 - C.TextHeight('X'), S);
  end;

  { a list opened from the deck may stand over this panel too }
  if FPopup <> POP_NONE then
    PaintPopup(C, pbScreen.Left - pbGroups.Left, pbScreen.Top - pbGroups.Top);
end;

procedure TMainForm.pbGroupsMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  H, Id: Integer;
begin
  if FPopup <> POP_NONE then
  begin
    H := PopupItemAt(X + pbGroups.Left - pbScreen.Left,
                     Y + pbGroups.Top - pbScreen.Top);
    if (H < 0) and (FPopup = POP_CMDS) then H := FPopupHot;
    if H <> FPopupHot then
    begin
      FPopupHot := H;
      FScreenDirty := True;
      pbScreen.Invalidate;
      pbGroups.Invalidate;
    end;
    Exit;
  end;
  H := GroupRowAt(Y);
  if H = FGrpHot then Exit;
  FGrpHot := H;
  { the hovered group shows its box in the drawing }
  if H >= 0 then Id := FGrpRows[H].Id else Id := 0;
  if Id <> FGrpHotId then
  begin
    FGrpHotId := Id;
    FScreenDirty := True;
    pbScreen.Invalidate;
  end;
  pbGroups.Invalidate;
end;

procedure TMainForm.pbGroupsMouseLeave(Sender: TObject);
begin
  if (FGrpHot < 0) and (FGrpHotId = 0) then Exit;
  FGrpHot := -1;
  FGrpHotId := 0;
  FScreenDirty := True;
  pbScreen.Invalidate;
  pbGroups.Invalidate;
end;

procedure TMainForm.pbGroupsMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  if WheelDelta > 0 then FGrpScroll := Max(0, FGrpScroll - 3)
  else FGrpScroll := FGrpScroll + 3;
  FGrpHot := -1;
  pbGroups.Invalidate;
  Handled := True;
end;

procedure TMainForm.pbGroupsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  H, Row, Id, K, Which: Integer;
  P: TPoint;

  procedure Item(const Caption: string; Tag: Integer; Enabled: Boolean);
  var
    It: TMenuItem;
  begin
    It := TMenuItem.Create(pmGroups);
    It.Caption := Caption;
    It.Tag := Tag;
    It.Enabled := Enabled;
    It.OnClick := @GroupsMenuClick;
    pmGroups.Items.Add(It);
  end;

begin
  if FPopup <> POP_NONE then
  begin
    Which := FPopup;
    H := -1;
    if Button = mbLeft then
      H := PopupItemAt(X + pbGroups.Left - pbScreen.Left,
                       Y + pbGroups.Top - pbScreen.Top);
    ClosePopup;
    if H >= 0 then PopupChoose(Which, H);
    Exit;
  end;
  Row := GroupRowAt(Y);
  if Row < 0 then Exit;
  Id := FGrpRows[Row].Id;

  if Button = mbRight then
  begin
    if Id = 0 then Exit;
    FGrpMenuId := Id;
    pmGroups.Items.Clear;
    Item('Pick It', 1, not GroupPutAway(Id));
    Item('Work Inside It', 2, not FD.Doc.PartLockedUp(Id) and not GroupPutAway(Id));
    Item('Rename...', 3, True);
    if FD.Doc.PartLocked(Id) then Item('Unlock', 4, True) else Item('Lock', 4, True);
    if FD.Doc.PartHidden(Id) then Item('Bring It Back', 5, True) else Item('Put It Away', 5, True);
    Item('-', 0, True);
    Item('Explode', 6, not FD.Doc.PartLockedUp(Id) and not GroupPutAway(Id));
    P := pbGroups.ClientToScreen(Point(X, Y));
    pmGroups.PopUp(P.X, P.Y);
    Exit;
  end;
  if Button <> mbLeft then Exit;

  if PtInRect(FGrpRows[Row].Fold, Point(X, Y)) then
  begin
    K := 0;
    while (K <= High(FGrpFold)) and (FGrpFold[K] <> Id) do Inc(K);
    if K <= High(FGrpFold) then
    begin
      FGrpFold[K] := FGrpFold[High(FGrpFold)];
      SetLength(FGrpFold, Length(FGrpFold) - 1);
    end
    else
    begin
      SetLength(FGrpFold, Length(FGrpFold) + 1);
      FGrpFold[High(FGrpFold)] := Id;
    end;
    pbGroups.Invalidate;
    Exit;
  end;
  if PtInRect(FGrpRows[Row].Tick, Point(X, Y)) then
  begin
    ShowGroupFromPanel(Id, FD.Doc.PartHidden(Id));
    Exit;
  end;
  if ssDouble in Shift then
  begin
    if Id = 0 then Exit;
    if GroupPutAway(Id) then Exit;
    OpenGroup(Id);
    pbGroups.Invalidate;
    Exit;
  end;
  PickGroupFromPanel(Id, (ssCtrl in Shift) or (ssShift in Shift));
end;

{ Pick a group from its row.  A nested group is picked as a click would pick
  it from inside its parent, so the context moves there (as SketchUp's
  Outliner does). }
procedure TMainForm.PickGroupFromPanel(Id: Integer; Add: Boolean);
var
  Up, K, First: Integer;
  M: TIntArrayW;
begin
  if Id = 0 then
  begin
    { the sheet itself: leave every group, pick nothing }
    SetLength(FSel, 0);
    if FD.Doc.Context <> 0 then
    begin
      FD.Doc.Context := 0;
      FShotOK := False;
      RenderInk;
      RecomposeAll;
    end;
    FCmdMsg := 'Working on the whole sheet.';
    InfoChanged;
    InvalidateStatus;
    FScreenDirty := True;
    pbScreen.Invalidate;
    Exit;
  end;
  if GroupPutAway(Id) then
  begin
    FCmdMsg := Format('"%s" is put away - tick its box to bring it back.', [FD.Doc.PartName(Id)]);
    InvalidateStatus;
    Exit;
  end;
  Up := FD.Doc.PartParent(Id);
  if FD.Doc.Context <> Up then
  begin
    if (Up > 0) and FD.Doc.PartLockedUp(Up) then
    begin
      FCmdMsg := Format('"%s" is inside "%s", which is locked - unlock it to reach in.',
        [FD.Doc.PartName(Id), FD.Doc.PartName(Up)]);
      InvalidateStatus;
      Exit;
    end;
    SetLength(FSel, 0);
    FD.Doc.Context := Up;
    FShotOK := False;
    RenderInk;
    RecomposeAll;
    Add := False;
  end;
  M := FD.Doc.PartMembers(Id, False);
  First := -1;
  for K := 0 to High(M) do
    if not (FD.Doc[M[K]].Kind in [ekPart, ekGuide]) then
    begin
      First := M[K];
      Break;
    end;
  if First < 0 then
  begin
    FCmdMsg := Format('"%s" has nothing in it.', [FD.Doc.PartName(Id)]);
    InvalidateStatus;
    Exit;
  end;
  if not Add then SetLength(FSel, 0);
  SelectAdd(First);
  FScreenDirty := True;
  pbScreen.Invalidate;
  InfoChanged;
  if FD.Doc.PartLocked(Id) then
    FCmdMsg := Format('"%s" picked - it is locked.', [FD.Doc.PartName(Id)])
  else
    FCmdMsg := Format('"%s" picked.  Double-click its row to work inside it.',
      [FD.Doc.PartName(Id)]);
  InvalidateStatus;
end;

{ Tick or untick: on the sheet, or put away.  Nothing is lost; a put-away
  group is just not drawn, picked or snapped to (see HideGroups). }
procedure TMainForm.ShowGroupFromPanel(Id: Integer; Shown: Boolean);
var
  C_, Guard: Integer;
begin
  if (Id <= 0) or (FD.Doc.PartHidden(Id) = not Shown) then Exit;
  PushUndo;
  FD.Doc.SetPartHidden(Id, not Shown);
  if not Shown then
  begin
    SetLength(FSel, 0);
    { working inside something just put away is working blind: step out }
    C_ := FD.Doc.Context;
    Guard := 0;
    while (C_ > 0) and (Guard < 1000) do
    begin
      if C_ = Id then
      begin
        FD.Doc.Context := FD.Doc.PartParent(Id);
        Break;
      end;
      C_ := FD.Doc.PartParent(C_);
      Inc(Guard);
    end;
  end;
  RenderInk;
  RecomposeAll;
  InfoChanged;
  if Shown then
    FCmdMsg := Format('"%s" is back.', [FD.Doc.PartName(Id)])
  else
    FCmdMsg := Format('"%s" put away - tick it to bring it back.  Ctrl+Z undoes it.',
      [FD.Doc.PartName(Id)]);
  InvalidateStatus;
  FScreenDirty := True;
  pbScreen.Invalidate;
end;

procedure TMainForm.GroupsMenuClick(Sender: TObject);
var
  Id: Integer;
begin
  Id := FGrpMenuId;
  if FD.Doc.PartEnt(Id) < 0 then Exit;
  case (Sender as TMenuItem).Tag of
    1: PickGroupFromPanel(Id, False);
    2: OpenGroup(Id);
    3:
      begin
        { renamed in the command line, prefilled, so Enter keeps it }
        PickGroupFromPanel(Id, False);
        if SoleGroup = Id then
        begin
          FInput := '/name ' + FD.Doc.PartName(Id);
          SyncCmdList;
          pbCmd.Invalidate;
          pbScreen.Invalidate;
        end;
      end;
    4:
      begin
        PushUndo;
        FD.Doc.SetPartLocked(Id, not FD.Doc.PartLocked(Id));
        FCmdMsg := Format('"%s" %s.', [FD.Doc.PartName(Id),
          IfThen(FD.Doc.PartLocked(Id), 'locked', 'unlocked')]);
        InfoChanged;
        InvalidateStatus;
        pbScreen.Invalidate;
      end;
    5: ShowGroupFromPanel(Id, FD.Doc.PartHidden(Id));
    6:
      begin
        PickGroupFromPanel(Id, False);
        if SoleGroup = Id then ExplodeGroups;
      end;
  end;
  GroupsChanged;
end;

function TMainForm.InfoPanelWidth: Integer;
begin
  if not (FInfoOn or FGroupsOn) then Exit(0);
  Result := Round(212 * FUIScale);
end;

{ What the entity panel says about the selection.  Rebuilt when the
  selection or drawing changes, into rows the painter reads and the mouse
  searches, so a stepper never drifts from its row. }
procedure TMainForm.RebuildInfo;
var
  InfoMoveB: Boolean;
  I, K, NL, NA, NF, NT, ND, NG, G: Integer;
  M: TIntArrayW;
  E: TWorkEnt;
  TotL, TotA: Double;
  Lo, Hi: TP3;
  MatCol: TColor;

  procedure Head(const S: string);
  begin
    SetLength(FInfoRows, Length(FInfoRows) + 1);
    with FInfoRows[High(FInfoRows)] do
    begin
      Caption := S; Value := ''; Act := iaNone; Ent := -1; Head := True;
      Minus := Rect(0, 0, 0, 0); Plus := Minus;
    end;
  end;

  procedure Row(const C, V: string; A: TInfoAct = iaNone; AEnt: Integer = -1);
  begin
    SetLength(FInfoRows, Length(FInfoRows) + 1);
    with FInfoRows[High(FInfoRows)] do
    begin
      Caption := C; Value := V; Act := A; Ent := AEnt; Head := False;
      Minus := Rect(0, 0, 0, 0); Plus := Minus;
    end;
  end;

  function PlaneWord(P: TPlane): string;
  begin
    case P of
      plXZ: Result := 'upright, XZ';
      plYZ: Result := 'on the side, YZ';
      plFree: Result := 'on a face';
    else
      Result := 'flat, XY';
    end;
  end;

  function Place(const P: TP3): string;
  begin
    Result := FormatLen(P.X, FD.Units) + ', ' + FormatLen(P.Y, FD.Units) +
      ', ' + FormatLen(P.Z, FD.Units);
  end;

begin
  SetLength(FInfoRows, 0);
  if (FD = nil) then Exit;

  { nothing picked: summarize the sheet }
  if Length(FSel) = 0 then
  begin
    Head('THIS SHEET');
    Row('Things', IntToStr(FD.Doc.Live));
    NL := 0; NA := 0; NF := 0; NT := 0; ND := 0; NG := 0;
    TotL := 0;
    TotA := 0;
    for I := 0 to FD.Doc.Live - 1 do
      case FD.Doc[I].Kind of
        ekLine: if FD.Doc[I].Dim then Inc(ND) else
                begin Inc(NL); TotL := TotL + Dist(FD.Doc[I].A, FD.Doc[I].B); end;
        ekArc: Inc(NA);
        ekFace: begin Inc(NF); TotA := TotA + FD.Doc.FaceArea(I); end;
        ekText: Inc(NT);
        ekDim: Inc(ND);
        ekGuide: Inc(NG);
      end;
    if NL > 0 then Row('Lines', IntToStr(NL) + '   ' + FormatLen(TotL, FD.Units));
    if NA > 0 then Row('Arcs', IntToStr(NA));
    if NF > 0 then Row('Faces', IntToStr(NF) + '   ' + FormatArea(TotA, FD.Units));
    if ND > 0 then Row('Dimensions', IntToStr(ND));
    if NT > 0 then Row('Notes', IntToStr(NT));
    if NG > 0 then Row('Guides', IntToStr(NG));
    Head('');
    Row('Pick something', 'to see and change it');
    Exit;
  end;

  { A group picked: name, contents, and actions.  Before the general count,
    since its members are all selected and would read as loose lines. }
  G := SoleGroup;
  if G > 0 then
  begin
    Head('GROUP');
    Row('Name', FD.Doc.PartName(G), iaPartRename, G);
    M := FD.Doc.PartMembers(G, False);
    Row('Holds', Format('%d thing%s', [Length(M), IfThen(Length(M) = 1, '', 's')]));
    if FD.Doc.PartParent(G) <> 0 then
      Row('Inside', FD.Doc.PartName(FD.Doc.PartParent(G)));
    { its total line length including reference lines (a radiant loop is all
      reference line, and port to port is the number wanted), and its box }
    NL := 0; TotL := 0;
    for K := 0 to High(M) do
      if FD.Doc[M[K]].Kind = ekLine then
      begin
        Inc(NL); TotL := TotL + Dist(FD.Doc[M[K]].A, FD.Doc[M[K]].B);
      end;
    if NL > 0 then Row('Lines', IntToStr(NL) + '   ' + FormatLen(TotL, FD.Units));
    if FD.Doc.PartBounds(G, Lo, Hi) then
      if Abs(Hi.Z - Lo.Z) > 1E-6 then
        Row('Size', FormatLen(Hi.X - Lo.X, FD.Units) + ' x ' + FormatLen(Hi.Y - Lo.Y, FD.Units) +
          ' x ' + FormatLen(Hi.Z - Lo.Z, FD.Units))
      else
        Row('Size', FormatLen(Hi.X - Lo.X, FD.Units) + ' x ' + FormatLen(Hi.Y - Lo.Y, FD.Units));
    Head('');
    Row('Locked', IfThen(FD.Doc.PartLocked(G), 'Unlock', 'Lock'), iaPartLock, G);
    Row('Put away', 'Hide', iaPartHide, G);
    Row('Work inside it', 'Open', iaPartOpen, G);
    Row('Take it apart', 'Explode', iaPartExplode, G);
    Exit;
  end;

  { Several picked: totals, and no steppers; a stepper acting on nine things
    at once is a way to lose nine things. }
  if Length(FSel) > 1 then
  begin
    Head(Format('%d THINGS PICKED', [Length(FSel)]));
    NL := 0; NA := 0; NF := 0; NT := 0; ND := 0; NG := 0;
    TotL := 0;
    TotA := 0;
    for K := 0 to High(FSel) do
    begin
      I := FSel[K];
      if (I < 0) or (I >= FD.Doc.Live) then Continue;
      case FD.Doc[I].Kind of
        ekLine: begin Inc(NL); TotL := TotL + Dist(FD.Doc[I].A, FD.Doc[I].B); end;
        ekArc: Inc(NA);
        ekFace: begin Inc(NF); TotA := TotA + FD.Doc.FaceArea(I); end;
        ekText: Inc(NT);
        ekDim: Inc(ND);
        ekGuide: Inc(NG);
      end;
    end;
    if NL > 0 then Row('Lines', IntToStr(NL));
    if NA > 0 then Row('Arcs', IntToStr(NA));
    if NF > 0 then Row('Faces', IntToStr(NF));
    if ND > 0 then Row('Dimensions', IntToStr(ND));
    if NT > 0 then Row('Notes', IntToStr(NT));
    if NG > 0 then Row('Guides', IntToStr(NG));
    if TotL > 0 then Row('Total length', FormatLen(TotL, FD.Units));
    if TotA > 0 then Row('Total area', FormatArea(TotA, FD.Units));
    { A color is fine for all at once: one decision, the button says how
      many it hits, and undo puts it back (SketchUp does the same). }
    if (NF > 0) or (NL + NA + NT + ND > 0) then Head('');
    if NF > 0 then
    begin
      Row('Material', Format('Paint %d face%s...',
        [NF, specialize IfThen<string>(NF = 1, '', 's')]), iaMaterial, -1);
      Row('', 'Back to default', iaUnpaint, -1);
    end;
    if NL + NA + NT + ND > 0 then
      Row('Color', Format('Change %d...', [NL + NA + NT + ND]), iaColor, -1);
    if NF > 0 then
    begin
      Head('');
      Row('Turn them over', 'Reverse', iaReverse, -1);
    end;
    Exit;
  end;

  I := FSel[0];
  if (I < 0) or (I >= FD.Doc.Live) then Exit;
  E := FD.Doc[I];

  case E.Kind of
    ekLine:
      begin
        Head(IfThen(E.Dim, 'DIMENSION', 'LINE'));
        Row('Length', FormatLen(Dist(E.A, E.B), FD.Units));
        { says in words whether the length can be typed (SketchUp grays the
          field) }
        if not E.Dim then
          if FD.Doc.LineLengthEnd(I, InfoMoveB) then
            Row('', 'type a length, Enter')
          else
            Row('', 'joined at both ends - fixed');
        Row('From', Place(E.A));
        Row('To', Place(E.B));
        Row('Width', Format('%d px', [Round(Max(1, E.Weight))]), iaWidth, I);
        Row('Color', 'Change...', iaColor, I);
        Row('Crease', IfThen(E.Soft, 'Bring back', 'Soften'), iaSoft, I);
        if E.Grp <> 0 then Row('Part of', Format('solid %d', [E.Grp]))
        else Row('Part of', 'nothing - a loose edge');
      end;
    ekArc:
      begin
        if Abs(Abs(E.Sweep) - 2 * Pi) < 1E-9 then Head('CIRCLE') else Head('ARC');
        Row('Radius', FormatLen(E.R, FD.Units));
        Row('Center', Place(E.C));
        if Abs(Abs(E.Sweep) - 2 * Pi) > 1E-9 then
          Row('Sweep', FormatAngle(RadToDeg(Abs(E.Sweep))));
        { sides can be changed after drawing }
        Row('Sides', IntToStr(ArcSteps(E)), iaSides, I);
        Row('Plane', PlaneWord(E.Plane));
        Row('Width', Format('%d px', [Round(Max(1, E.Weight))]), iaWidth, I);
        Row('Color', 'Change...', iaColor, I);
        Row('Crease', IfThen(E.Soft, 'Bring back', 'Soften'), iaSoft, I);
      end;
    ekFace:
      begin
        Head('FACE');
        Row('Area', FormatArea(FD.Doc.FaceArea(I), FD.Units));
        Row('Corners', IntToStr(Length(E.Poly)));
        if Length(E.Holes) > 0 then
          Row('Windows', IntToStr(Length(E.Holes)));
        if E.Solid then Row('Part of', Format('solid %d', [E.Grp]))
        else Row('Part of', 'nothing - a loose face');
        { faces are painted, not inked: the material row says whether it has
          the default or a chosen color }
        if FD.Doc.Material(I, MatCol) then
        begin
          Row('Material', 'Change...', iaMaterial, I);
          Row('', 'Back to default', iaUnpaint, I);
        end
        else
          Row('Material', 'Paint...', iaMaterial, I);
        Head('');
        Row('Turn it over', 'Reverse', iaReverse, I);
      end;
    ekText:
      begin
        Head('NOTE');
        Row('Says', E.Txt);
        Row('At', Place(E.A));
        Row('Size', Format('%d%%', [Round(FD.Doc.NoteSize(I) * 100)]),
          iaNoteSize, I);
        Row('Color', 'Change...', iaColor, I);
      end;
    ekDim:
      begin
        Head('DIMENSION');
        Row('Measures', FormatLen(Dist(E.A, E.B), FD.Units));
        if E.Txt <> '' then Row('Written', E.Txt);
        Row('From', Place(E.A));
        Row('To', Place(E.B));
        Row('Color', 'Change...', iaColor, I);
      end;
    ekGuide:
      begin
        if Dist(E.A, E.B) < 1E-9 then
        begin
          Head('GUIDE POINT');
          Row('At', Place(E.A));
        end
        else
        begin
          Head('GUIDE LINE');
          Row('Through', Place(E.A));
        end;
        Head('');
        Row('Delete takes it', 'or /guides for all');
      end;
  else
    Head('SOMETHING');
  end;
end;

procedure TMainForm.pbInfoPaint(Sender: TObject);
var
  I, W, H, Y, RowH, Pad, StepW, VX: Integer;
  C: TCanvas;
  R: TRect;
  S: string;
  SwatchCol: TColor;
begin
  W := pbInfo.Width;
  H := pbInfo.Height;
  if (W < 8) or (H < 8) then Exit;
  FInfoSkin.SetSize(W, H);
  PaintPanel(FInfoSkin, Rect(0, 0, W, H), Theme, FUIScale);
  FInfoSkin.DrawTo(pbInfo.Canvas, 0, 0);

  C := pbInfo.Canvas;
  Pad := Round(10 * FUIScale);
  RowH := Round(19 * FUIScale);
  StepW := Round(18 * FUIScale);
  Y := Pad;

  for I := 0 to High(FInfoRows) do
  begin
    if Y > H - RowH then Break;
    if FInfoRows[I].Head then
    begin
      { a rule and a small heading }
      if Y > Pad then Inc(Y, Round(6 * FUIScale));
      if FInfoRows[I].Caption <> '' then
      begin
        UIFont(C, 8, True, Theme.Accent);
        C.TextOut(Pad, Y, FInfoRows[I].Caption);
        Inc(Y, RowH);
      end;
      C.Pen.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.14));
      C.Pen.Width := 1;
      C.MoveTo(Pad, Y - Round(3 * FUIScale));
      C.LineTo(W - Pad, Y - Round(3 * FUIScale));
      Inc(Y, Round(4 * FUIScale));
      Continue;
    end;

    R := Rect(Pad, Y, W - Pad, Y + RowH);
    UIFont(C, 9, False, Theme.TextDim);
    C.TextOut(R.Left, Y + (RowH - C.TextHeight('X')) div 2,
      FInfoRows[I].Caption);

    VX := R.Left + Round(84 * FUIScale);
    if FInfoRows[I].Act in [iaSides, iaNoteSize, iaWidth] then
    begin
      { a number: two steppers at the right edge, the figure to their left so
        it does not move as it changes width }
      FInfoRows[I].Plus := Rect(W - Pad - StepW, Y + Round(2 * FUIScale),
        W - Pad, Y + RowH - Round(2 * FUIScale));
      FInfoRows[I].Minus := Rect(FInfoRows[I].Plus.Left - StepW - Round(3 * FUIScale),
        FInfoRows[I].Plus.Top, FInfoRows[I].Plus.Left - Round(3 * FUIScale),
        FInfoRows[I].Plus.Bottom);
      PaintInfoStep(C, FInfoRows[I].Minus, '-', FInfoHot = I * 2);
      PaintInfoStep(C, FInfoRows[I].Plus, '+', FInfoHot = I * 2 + 1);
      UIFont(C, 9, True, Theme.Text);
      S := FInfoRows[I].Value;
      C.TextOut(FInfoRows[I].Minus.Left - Round(8 * FUIScale) - C.TextWidth(S),
        Y + (RowH - C.TextHeight('X')) div 2, S);
    end
    else if FInfoRows[I].Act <> iaNone then
    begin
      { a yes/no or an action: one button naming what pressing it does }
      S := FInfoRows[I].Value;
      UIFont(C, 9, True, Theme.Text);
      FInfoRows[I].Plus := Rect(W - Pad - C.TextWidth(S) - Round(14 * FUIScale),
        Y + Round(2 * FUIScale), W - Pad, Y + RowH - Round(2 * FUIScale));
      FInfoRows[I].Minus := Rect(0, 0, 0, 0);
      PaintInfoStep(C, FInfoRows[I].Plus, S, FInfoHot = I * 2 + 1);
      { the current color as a swatch where the value would go }
      if (FInfoRows[I].Act in [iaColor, iaMaterial]) and
         (FInfoRows[I].Ent >= 0) and (FInfoRows[I].Ent < FD.Doc.Live) then
      begin
        C.Brush.Style := bsSolid;
        if FInfoRows[I].Act = iaMaterial then
        begin
          if not FD.Doc.Material(FInfoRows[I].Ent, SwatchCol) then
            SwatchCol := PixToColor(Pix($FA, $FA, $F6));
          C.Brush.Color := SwatchCol;
        end
        else
          C.Brush.Color := FD.Doc[FInfoRows[I].Ent].Ink;
        C.Pen.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.35));
        C.Pen.Width := 1;
        C.Rectangle(VX, Y + Round(3 * FUIScale),
          Min(VX + Round(36 * FUIScale), FInfoRows[I].Plus.Left - Round(6 * FUIScale)),
          Y + RowH - Round(3 * FUIScale));
        C.Brush.Style := bsClear;
      end;
    end
    else
    begin
      UIFont(C, 9, False, Theme.Text);
      S := FInfoRows[I].Value;
      { a long value is cut rather than run off the panel }
      S := CutToFit(C, S, W - Pad - VX);
      C.TextOut(VX, Y + (RowH - C.TextHeight('X')) div 2, S);
    end;
    Inc(Y, RowH);
  end;

  { A deck list can stand over the panel too, so the part that lands here is
    painted here, shifted from drawing to panel coordinates. }
  if FPopup <> POP_NONE then
    PaintPopup(C, pbScreen.Left - pbInfo.Left, pbScreen.Top - pbInfo.Top);
end;

{ one of the small square buttons beside a changeable value }
procedure TMainForm.PaintInfoStep(C: TCanvas; const R: TRect;
  const S: string; Hot: Boolean);
var
  Bg: TPix;
begin
  if Hot then Bg := MixPix(Theme.PanelHi, Theme.Accent, 0.45)
  else Bg := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.10);
  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(Bg);
  C.Pen.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.25));
  C.Pen.Width := 1;
  C.Rectangle(R);
  C.Brush.Style := bsClear;
  UIFont(C, 10, True, Theme.Text);
  C.TextOut((R.Left + R.Right - C.TextWidth(S)) div 2,
            (R.Top + R.Bottom - C.TextHeight(S)) div 2, S);
end;

{ The stepper under the cursor: row*2 for minus, row*2+1 for plus, or -1.
  The rects come from the painter. }
function TMainForm.InfoHit(X, Y: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FInfoRows) do
    if FInfoRows[I].Act <> iaNone then
    begin
      if PtInRect(FInfoRows[I].Minus, Point(X, Y)) then Exit(I * 2);
      if PtInRect(FInfoRows[I].Plus, Point(X, Y)) then Exit(I * 2 + 1);
    end;
end;

procedure TMainForm.pbInfoMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  H: Integer;
begin
  { an open list over the panel still tracks hover here }
  if FPopup <> POP_NONE then
  begin
    H := PopupItemAt(X + pbInfo.Left - pbScreen.Left,
                     Y + pbInfo.Top - pbScreen.Top);
    if (H < 0) and (FPopup = POP_CMDS) then H := FPopupHot;
    if H <> FPopupHot then
    begin
      FPopupHot := H;
      FScreenDirty := True;
      pbScreen.Invalidate;
      pbInfo.Invalidate;
    end;
    Exit;
  end;
  H := InfoHit(X, Y);
  if H <> FInfoHot then
  begin
    FInfoHot := H;
    pbInfo.Invalidate;
  end;
end;

procedure TMainForm.pbInfoMouseLeave(Sender: TObject);
begin
  if FInfoHot >= 0 then
  begin
    FInfoHot := -1;
    pbInfo.Invalidate;
  end;
end;

procedure TMainForm.pbInfoMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  H, Row, N, K, Which: Integer;
  Up: Boolean;
  Picked: TColor;
begin
  { and a press picks a list row rather than reaching the panel }
  if FPopup <> POP_NONE then
  begin
    Which := FPopup;
    H := -1;
    if Button = mbLeft then
      H := PopupItemAt(X + pbInfo.Left - pbScreen.Left,
                       Y + pbInfo.Top - pbScreen.Top);
    ClosePopup;
    if H >= 0 then PopupChoose(Which, H);
    Exit;
  end;
  if Button <> mbLeft then Exit;
  H := InfoHit(X, Y);
  if H < 0 then Exit;
  Row := H div 2;
  Up := Odd(H);

  case FInfoRows[Row].Act of
    iaSides:
      begin
        if (FInfoRows[Row].Ent < 0) or (FInfoRows[Row].Ent >= FD.Doc.Live) then Exit;
        N := ArcSteps(FD.Doc[FInfoRows[Row].Ent]);
        { same steps and limits as the + and - keys }
        if Up then N := Min(360, N + 1) else N := Max(3, N - 1);
        PushUndo;
        FD.Doc.SetArcSides(FInfoRows[Row].Ent, N);
        RebuildFlatFaces;
        FCmdMsg := Format('%d sides.', [N]);
      end;
    iaSoft:
      begin
        if (FInfoRows[Row].Ent < 0) or (FInfoRows[Row].Ent >= FD.Doc.Live) then Exit;
        PushUndo;
        N := Ord(not FD.Doc[FInfoRows[Row].Ent].Soft);
        FD.Doc.SetSoft(FInfoRows[Row].Ent, N <> 0);
        FCmdMsg := specialize IfThen<string>(N <> 0, 'Edge softened.',
          'Edge brought back.');
      end;
    iaNoteSize:
      begin
        if (FInfoRows[Row].Ent < 0) or (FInfoRows[Row].Ent >= FD.Doc.Live) then Exit;
        PushUndo;
        if Up then
          FD.Doc.SetNoteSize(FInfoRows[Row].Ent,
            FD.Doc.NoteSize(FInfoRows[Row].Ent) * 1.25)
        else
          FD.Doc.SetNoteSize(FInfoRows[Row].Ent,
            FD.Doc.NoteSize(FInfoRows[Row].Ent) / 1.25);
        FCmdMsg := Format('Text at %d%% of normal.',
          [Round(FD.Doc.NoteSize(FInfoRows[Row].Ent) * 100)]);
      end;
    iaWidth:
      begin
        if (FInfoRows[Row].Ent < 0) or (FInfoRows[Row].Ent >= FD.Doc.Live) then Exit;
        { through the widths the LINE WIDTH list offers }
        N := Round(Max(1, FD.Doc[FInfoRows[Row].Ent].Weight));
        K := 0;
        while (K < High(PEN_SIZES)) and (PEN_SIZES[K] < N) do Inc(K);
        if Up then
        begin
          if PEN_SIZES[K] <= N then K := Min(High(PEN_SIZES), K + 1);
        end
        else if K > 0 then
          Dec(K);
        PushUndo;
        FD.Doc.SetWeight(FInfoRows[Row].Ent, PEN_SIZES[K]);
        FCmdMsg := Format('%d px.', [PEN_SIZES[K]]);
      end;
    iaColor:
      begin
        { with several picked there is no one color to start from, so the
          dialog opens on the current pen }
        if FInfoRows[Row].Ent < 0 then
        begin
          if not AskColor(FInkColor, Picked) then Exit;
          PushUndo;
          K := InkSelectedThings(Picked);
          FCmdMsg := Format('%d thing%s recolored.',
            [K, specialize IfThen<string>(K = 1, '', 's')]);
          RenderInk;
          RecomposeAll;
          RebuildInfo;
          pbInfo.Invalidate;
          pbScreen.Invalidate;
          pbCmd.Invalidate;
          Exit;
        end;
        if FInfoRows[Row].Ent >= FD.Doc.Live then Exit;
        if not AskColor(FD.Doc[FInfoRows[Row].Ent].Ink, Picked) then Exit;
        PushUndo;
        FD.Doc.SetInk(FInfoRows[Row].Ent, Picked);
        FCmdMsg := 'Color changed.  The LINE COLOR button still sets what you draw next.';
      end;
    iaMaterial:
      begin
        if FInfoRows[Row].Ent >= FD.Doc.Live then Exit;
        { start from the current material, or the default it looks like
          (always the default with several picked) }
        if (FInfoRows[Row].Ent < 0) or
           not FD.Doc.Material(FInfoRows[Row].Ent, Picked) then
          Picked := PixToColor(Pix($FA, $FA, $F6));
        if not AskColor(Picked, Picked) then Exit;
        PushUndo;
        K := PaintSelectedFaces(FInfoRows[Row].Ent, Picked, True);
        if K > 1 then
          FCmdMsg := Format('%d faces painted.', [K])
        else
          FCmdMsg := 'Face painted.  The LINE COLOR button still sets what you draw next.';
      end;
    iaUnpaint:
      begin
        if FInfoRows[Row].Ent >= FD.Doc.Live then Exit;
        PushUndo;
        K := PaintSelectedFaces(FInfoRows[Row].Ent, clNone, False);
        if K > 1 then
          FCmdMsg := Format('%d faces back to the default material.', [K])
        else
          FCmdMsg := 'Back to the default material.';
      end;
    { group rows carry the group id in Ent, not an entity }
    iaPartOpen: OpenGroup(FInfoRows[Row].Ent);
    iaPartLock:
      begin
        PushUndo;
        FD.Doc.SetPartLocked(FInfoRows[Row].Ent, not FD.Doc.PartLocked(FInfoRows[Row].Ent));
        if FD.Doc.PartLocked(FInfoRows[Row].Ent) then FCmdMsg := 'Locked.' else FCmdMsg := 'Unlocked.';
      end;
    iaPartExplode: ExplodeGroups;
    iaPartHide: HideGroups(True, '');
    iaPartRename:
      begin
        { the command bar, prefilled with the name }
        FInput := '/name ' + FD.Doc.PartName(FInfoRows[Row].Ent);
        SyncCmdList;
        FCmdMsg := 'Type the name and press Enter.';
      end;
    iaReverse:
      begin
        PushUndo;
        K := ReverseSelectedFaces;
        FCmdMsg := Format('%d face%s turned over.',
          [K, specialize IfThen<string>(K = 1, '', 's')]);
      end;
  else
    Exit;
  end;

  RenderInk;
  RecomposeAll;
  RebuildInfo;
  pbInfo.Invalidate;
  pbScreen.Invalidate;
  pbCmd.Invalidate;
end;

procedure TMainForm.pbToolsPaint(Sender: TObject);
var
  I, W, H, IconSz, TxtX, ArrY: Integer;
  It: TDeckItem;
  Sel, Hot: Boolean;
  C1, C2, Edge, Fg: TPix;
  R, IR: TRect;
  S: string;
begin
  W := pbTools.Width;
  H := pbTools.Height;
  if (W < 8) or (H < 8) then Exit;
  FToolSkin.SetSize(W, H);
  PaintPanel(FToolSkin, Rect(0, 0, W, H), Theme, FUIScale);

  IconSz := Round(16 * FUIScale);
  for I := 0 to High(FTools) do
  begin
    It := FTools[I];
    R := It.Bounds;
    Sel := (It.Group = GRP_TOOL) and (It.Value = Ord(FTool));
    Hot := I = FHotTool;
    if Sel then
    begin
      C1 := Theme.Accent;
      C2 := ShadePix(Theme.Accent, 0.86);
      Fg := Pix(12, 16, 22);
      Edge := ShadePix(Theme.Accent, 1.18);
    end
    else
    begin
      C1 := MixPix(Theme.Panel, Pix(255, 255, 255), IfThen(Hot, 0.14, 0.05) / 1.0);
      C2 := MixPix(Theme.Panel, Pix(0, 0, 0), 0.16);
      Fg := Theme.Text;
      Edge := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.10);
    end;
    FToolSkin.RoundRectV(R, Round(4 * FUIScale), C1, C2);
    FToolSkin.RoundFrame(R, Round(4 * FUIScale), 1.0, Edge);
    IR := Rect(R.Left + Round(6 * FUIScale),
               (R.Top + R.Bottom - IconSz) div 2,
               R.Left + Round(6 * FUIScale) + IconSz,
               (R.Top + R.Bottom + IconSz) div 2);
    PaintIcon(FToolSkin, It.Icon, IR, Fg);
  end;

  { the lines between the groups }
  for I := 0 to High(FToolRules) do
    FToolSkin.Line(Round(10 * FUIScale), FToolRules[I],
      W - Round(10 * FUIScale), FToolRules[I], 1,
      MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.16), 1.0);

  { the collapse arrow, at the foot }
  ArrY := H - Round(20 * FUIScale);
  FToolSkin.Line(Round(8 * FUIScale), ArrY - Round(8 * FUIScale),
    W - Round(8 * FUIScale), ArrY - Round(8 * FUIScale), 1,
    MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.10), 1.0);
  FToolSkin.DrawTo(pbTools.Canvas, 0, 0);

  if FToolsWide then
  begin
    TxtX := Round(6 * FUIScale) + IconSz + Round(7 * FUIScale);
    for I := 0 to High(FTools) do
    begin
      It := FTools[I];
      R := It.Bounds;
      if (It.Group = GRP_TOOL) and (It.Value = Ord(FTool)) then
        UIFont(pbTools.Canvas, 9, True, Pix(12, 16, 22))
      else if It.Group = GRP_POPUP then
        UIFont(pbTools.Canvas, 9, True, Theme.TextDim)
      else
        UIFont(pbTools.Canvas, 9, False, Theme.Text);
      S := It.Caption;
      if It.Group = GRP_POPUP then S := S + '  >';
      pbTools.Canvas.TextOut(R.Left + TxtX,
        (R.Top + R.Bottom - pbTools.Canvas.TextHeight(S)) div 2, S);
    end;
  end;

  { says what it does to the strip, not to the names }
  UIFont(pbTools.Canvas, 9, False, Theme.TextDim);
  if FToolsWide then S := '<  COLLAPSE' else S := '>';
  pbTools.Canvas.TextOut(Round(8 * FUIScale),
    ArrY - pbTools.Canvas.TextHeight(S) div 2, S);
end;

procedure TMainForm.pbToolsMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  H: Integer;
begin
  H := ToolsHit(X, Y);
  if H <> FHotTool then
  begin
    FHotTool := H;
    pbTools.Invalidate;
  end;
  { the tip beside the button, level with it }
  FChromeTipX := Round(6 * FUIScale);
  if (H >= 0) and (H <= High(FTools)) then
  begin
    FChromeTip := FTools[H].Caption;
    FChromeTipBody := FTools[H].Hint;
    FChromeTipY := (FTools[H].Bounds.Top + FTools[H].Bounds.Bottom) div 2
                   + pbTools.Top - pbScreen.Top;
  end
  else if H = -2 then
  begin
    FChromeTip := IfThen(FToolsWide, 'COLLAPSE', 'EXPAND');
    FChromeTipBody := IfThen(FToolsWide,
      'Put the names away and give the width to the drawing.',
      'Show the tool names again.');
    FChromeTipY := pbTools.Height - Round(20 * FUIScale)
                   + pbTools.Top - pbScreen.Top;
  end
  else
  begin
    FChromeTip := '';
    FChromeTipBody := '';
  end;
  pbScreen.Invalidate;
end;

procedure TMainForm.pbToolsMouseLeave(Sender: TObject);
begin
  if FHotTool <> -1 then
  begin
    FHotTool := -1;
    pbTools.Invalidate;
  end;
  FChromeTip := '';
  FChromeTipBody := '';
  pbScreen.Invalidate;
end;

procedure TMainForm.pbToolsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  H: Integer;
begin
  if Button <> mbLeft then Exit;
  H := ToolsHit(X, Y);
  if H = -2 then
  begin
    FToolsWide := not FToolsWide;
    SaveSettings;
    Relayout;
    Exit;
  end;
  if (H < 0) or (H > High(FTools)) then
  begin
    { a click on the bare strip still closes an open list }
    if FPopup <> POP_NONE then ClosePopup;
    Exit;
  end;
  if FTools[H].Group = GRP_TOOL then
  begin
    if FPopup <> POP_NONE then ClosePopup;
    SetTool(TTool(FTools[H].Value));
  end
  else if FTools[H].Group = GRP_POPUP then
    { clicking the open one shuts it, as menu buttons do everywhere else }
    if FPopup = FTools[H].Value then ClosePopup
    else OpenPopup(FTools[H].Value);
end;

{ ---------------------------------------------------------------------- }
{ the cut - the slice a plan view is taken out of                          }
{ ---------------------------------------------------------------------- }

{ The cut strip: two length fields, the bottom of the slice and the top.
  Lengths, not a spin edit, so ParseLen reads anything typed and FormatLen
  writes it at the drawing's precision.  The arrows step by the snap.
  Typing goes to the command bar, as everything else typed does
  (see EditDimUnder). }
function TMainForm.SliceFieldRect(Which: Integer): TRect;
var
  LabW, Pad, FW: Integer;
begin
  Pad := Round(4 * FUIScale);
  LabW := Round(34 * FUIScale);
  FW := (pbSlice.Width - LabW - 3 * Pad) div 2;
  if Which = 1 then
    Result := Rect(LabW + Pad, 1, LabW + Pad + FW, pbSlice.Height - 1)
  else
    Result := Rect(LabW + 2 * Pad + FW, 1, LabW + 2 * Pad + 2 * FW,
                   pbSlice.Height - 1);
end;

function TMainForm.SliceZoneAt(X, Y: Integer): Integer;
var
  I, ArrW: Integer;
  R: TRect;
begin
  Result := -1;
  ArrW := Round(13 * FUIScale);
  for I := 1 to 2 do
  begin
    R := SliceFieldRect(I);
    if (X >= R.Left) and (X < R.Right) and (Y >= R.Top) and (Y < R.Bottom) then
    begin
      if X >= R.Right - ArrW then
      begin
        if Y < (R.Top + R.Bottom) div 2 then Exit(2 + I)   // 3 up-lo, 4 up-hi
        else Exit(4 + I);                                   // 5 dn-lo, 6 dn-hi
      end;
      Exit(I);
    end;
  end;
  if X < SliceFieldRect(1).Left then Result := 0;
end;

procedure TMainForm.pbSlicePaint(Sender: TObject);
var
  W, H, I, ArrW, MidY, CX: Integer;
  R: TRect;
  S: string;
  Body, Edge: TPix;
begin
  W := pbSlice.Width;
  H := pbSlice.Height;
  if (W < 8) or (H < 8) then Exit;
  FSliceSkin.SetSize(W, H);
  FSliceSkin.Clear(Pix(0, 0, 0));
  FSliceSkin.CopyRegion(FShell, pbSlice.Left, pbSlice.Top, 0, 0, W, H);
  if LightChrome then
    FSliceSkin.RoundRectV(Rect(0, 0, W, H), H / 2,
      MixPix(Theme.Panel, Pix(0, 0, 0), 0.06), MixPix(Theme.Panel, Pix(0, 0, 0), 0.14))
  else
    FSliceSkin.RoundRectV(Rect(0, 0, W, H), H / 2,
      MixPix(Theme.Panel, Pix(0, 0, 0), 0.20), MixPix(Theme.Panel, Pix(0, 0, 0), 0.42));
  FSliceSkin.RoundFrame(Rect(0, 0, W, H), H / 2, 1.0,
    MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.14));

  ArrW := Round(13 * FUIScale);
  for I := 1 to 2 do
  begin
    R := SliceFieldRect(I);
    Body := FieldPix;
    { the field being typed into is lit }
    if FSliceEdit = I then
    begin
      if LightChrome then Body := MixPix(Pix(255, 255, 255), Theme.Accent, 0.12)
      else Body := MixPix(Theme.Accent, Pix(0, 0, 0), 0.55);
    end
    else if FHotSlice = I then Body := MixPix(Body, Theme.Accent, 0.10);
    FSliceSkin.RoundRect(R, Round(3 * FUIScale), Body);
    Edge := FieldEdgePix;
    if FSliceEdit = I then Edge := Theme.Accent;
    FSliceSkin.RoundFrame(R, Round(3 * FUIScale), 1.0, Edge);
  end;
  FSliceSkin.DrawTo(pbSlice.Canvas, 0, 0);

  UIFont(pbSlice.Canvas, 9, True, Theme.TextDim);
  pbSlice.Canvas.TextOut(Round(8 * FUIScale),
    (H - pbSlice.Canvas.TextHeight('CUT')) div 2, 'CUT');

  for I := 1 to 2 do
  begin
    R := SliceFieldRect(I);
    if I = 1 then S := FormatLen(FD.SliceLo, FD.Units)
    else S := FormatLen(FD.SliceHi, FD.Units);
    if FSliceEdit = I then S := FInput + '_';
    if not FD.SliceOn then
      UIFont(pbSlice.Canvas, 9, False, Theme.TextDim)
    else
      UIFont(pbSlice.Canvas, 9, True, Theme.Text);
    pbSlice.Canvas.TextOut(R.Left + Round(6 * FUIScale),
      (H - pbSlice.Canvas.TextHeight(S)) div 2, S);

    { the two chevrons, a cue that it can be turned }
    MidY := (R.Top + R.Bottom) div 2;
    CX := R.Right - ArrW div 2 - Round(2 * FUIScale);
    pbSlice.Canvas.Brush.Style := bsSolid;
    pbSlice.Canvas.Brush.Color := PixToColor(Theme.TextDim);
    pbSlice.Canvas.Pen.Color := PixToColor(Theme.TextDim);
    pbSlice.Canvas.Polygon([Point(CX - 4, MidY - 2), Point(CX + 4, MidY - 2),
                            Point(CX, MidY - 7)]);
    pbSlice.Canvas.Polygon([Point(CX - 4, MidY + 2), Point(CX + 4, MidY + 2),
                            Point(CX, MidY + 7)]);
    pbSlice.Canvas.Brush.Style := bsClear;
  end;
end;

procedure TMainForm.pbSliceMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  Z: Integer;
begin
  Z := SliceZoneAt(X, Y);
  if Z <> FHotSlice then
  begin
    FHotSlice := Z;
    pbSlice.Invalidate;
  end;
end;

procedure TMainForm.pbSliceMouseLeave(Sender: TObject);
begin
  if FHotSlice <> -1 then
  begin
    FHotSlice := -1;
    pbSlice.Invalidate;
  end;
end;

procedure TMainForm.pbSliceMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Z: Integer;
begin
  if Button <> mbLeft then Exit;
  Z := SliceZoneAt(X, Y);
  case Z of
    3: NudgeSlice(1, 1);
    4: NudgeSlice(1, 2);
    5: NudgeSlice(-1, 1);
    6: NudgeSlice(-1, 2);
    1, 2:
      begin
        { typed in the command bar, like a dimension's text }
        FSliceEdit := Z;
        FInput := '';
        if Z = 1 then
          FCmdMsg := 'Type the bottom of the slice - the height you draw at.  Esc leaves it.'
        else
          FCmdMsg := 'Type the top of the slice.  Esc leaves it.';
        pbSlice.Invalidate;
        pbCmd.Invalidate;
      end;
    0:
      { the label switches the whole feature on or off }
      if FD.SliceOn then SetSlice(False, FD.SliceLo, FD.SliceHi)
      else SetSlice(True, FD.SliceLo, FD.SliceHi);
  end;
end;

procedure TMainForm.pbSliceMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  Z, Steps: Integer;
begin
  Handled := True;
  if WheelDelta > 0 then Steps := 1 else Steps := -1;
  Z := SliceZoneAt(MousePos.X, MousePos.Y);
  case Z of
    1, 3, 5: NudgeSlice(Steps, 1);
    2, 4, 6: NudgeSlice(Steps, 2);
  else
    NudgeSlice(Steps, 0);
  end;
end;

{ take what was typed into one of the two fields }
procedure TMainForm.CommitSliceEdit;
var
  W: Integer;
  V: Double;
begin
  W := FSliceEdit;
  FSliceEdit := 0;
  if W = 0 then Exit;
  if Trim(FInput) = '' then
  begin
    FInput := '';
    FCmdMsg := 'Left as it was.';
    pbSlice.Invalidate;
    Exit;
  end;
  if not ParseLen(FInput, FD.Units, V) then
  begin
    FCmdMsg := 'I could not read "' + FInput + '" as a height.';
    FInput := '';
    pbSlice.Invalidate;
    Exit;
  end;
  FInput := '';
  if W = 1 then SetSlice(True, V, Max(V, FD.SliceHi))
  else SetSlice(True, Min(FD.SliceLo, V), V);
  pbSlice.Invalidate;
end;

{ The view list behind the arrow: the two paper modes, then every camera
  preset.  Built from the same table the button steps through. }
procedure TMainForm.FillViewMenu;
var
  I: Integer;
  M: TMenuItem;
begin
  pmView.Items.Clear;

  { PLAN first: a plan is a slice through the model, and the cut fields live
    there, so it must be reachable by mouse.  TOP is the free camera looking
    nearly straight down, which looks like a plan but has no cut; both
    captions say what they are. }
  M := TMenuItem.Create(pmView);
  M.Caption := 'PLAN - flat, with the cut';
  M.Tag := 0;
  M.OnClick := @ViewMenuClick;
  pmView.Items.Add(M);

  M := TMenuItem.Create(pmView);
  M.Caption := 'ISO - flat, on the paper axes';
  M.Tag := 1;
  M.OnClick := @ViewMenuClick;
  pmView.Items.Add(M);

  M := TMenuItem.Create(pmView);
  M.Caption := '-';
  pmView.Items.Add(M);

  for I := FIRST_CAMERA_PRESET to High(VIEW_PRESETS) do
  begin
    M := TMenuItem.Create(pmView);
    if I = High(VIEW_PRESETS) then M.Caption := 'TOP - 3D, from above'
    else M.Caption := VIEW_PRESETS[I].Name;
    M.Tag := I;
    M.OnClick := @ViewMenuClick;
    pmView.Items.Add(M);
  end;
end;

procedure TMainForm.ViewMenuClick(Sender: TObject);
begin
  ApplyViewPreset((Sender as TMenuItem).Tag);
end;

{ What the button says: the paper mode, the preset the camera is parked on,
  or 3D once orbited elsewhere. }
function TMainForm.ViewButtonName: string;
begin
  if FD.View = vkPlan then Exit('PLAN PAPER');
  if FD.View = vkIso then Exit('ISO PAPER');
  if (FViewPreset >= FIRST_CAMERA_PRESET) and (FViewPreset <= High(VIEW_PRESETS)) then
    Result := 'VIEW: ' + VIEW_PRESETS[FViewPreset].Name
  else
    Result := 'VIEW: 3D';
end;

procedure TMainForm.pbViewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Z: Integer;
begin
  if X >= pbView.Width - VIEW_ARROW_W then Z := 1 else Z := 0;
  if FHotView <> Z then
  begin
    FHotView := Z;
    pbView.Invalidate;
  end;
end;

procedure TMainForm.pbViewMouseLeave(Sender: TObject);
begin
  FHotView := -1;
  pbView.Invalidate;
end;

procedure TMainForm.pbViewMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  { the arrow opens the list; on the name, left steps forward through the
    presets and right steps back }
  if X >= pbView.Width - VIEW_ARROW_W then
  begin
    with pbView.ClientToScreen(Point(pbView.Width - VIEW_ARROW_W, pbView.Height)) do
      pmView.PopUp(X, Y);
    Exit;
  end;
  if Button = mbLeft then CycleViewPreset(1)
  else if Button = mbRight then CycleViewPreset(-1);
end;

{ The slash button: starts a command with the list up; pressing it again
  puts the list away.  Right-click offers to copy the message or input. }
procedure TMainForm.pbCmdMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  It: TMenuItem;
  Pt: TPoint;
begin
  if (Button = mbRight) then
  begin
    pmCmd.Items.Clear;
    It := TMenuItem.Create(pmCmd);
    It.Caption := 'Copy the Message';
    It.Tag := 1;
    It.Enabled := FCmdMsg <> '';
    It.OnClick := @CmdMenuClick;
    pmCmd.Items.Add(It);
    It := TMenuItem.Create(pmCmd);
    It.Caption := 'Copy What Is Typed';
    It.Tag := 2;
    It.Enabled := FInput <> '';
    It.OnClick := @CmdMenuClick;
    pmCmd.Items.Add(It);
    Pt := pbCmd.ClientToScreen(Point(X, Y));
    pmCmd.PopUp(Pt.X, Pt.Y);
    Exit;
  end;
  if Button <> mbLeft then Exit;
  if not PtInRect(FCmdArrow, Point(X, Y)) then Exit;
  if FPopup = POP_CMDS then
  begin
    ClosePopup;
    FInput := '';
  end
  else
  begin
    FInput := '/';
    SyncCmdList;
  end;
  pbCmd.Invalidate;
  pbScreen.Invalidate;
end;

procedure TMainForm.pbCmdMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  Was: Boolean;
begin
  Was := FCmdArrowHot;
  FCmdArrowHot := PtInRect(FCmdArrow, Point(X, Y));
  if FCmdArrowHot <> Was then pbCmd.Invalidate;
end;

procedure TMainForm.pbCmdMouseLeave(Sender: TObject);
begin
  if FCmdArrowHot then
  begin
    FCmdArrowHot := False;
    pbCmd.Invalidate;
  end;
end;

{ The command bar: three rows.  Row one is the tool and the moment:
  what the cursor holds (in its mark's color), the prompt, and the typing in
  its own box.  Rows two and three are the message, drawn by LazInk so it
  wraps and is colored (right-click copies it); the keys that apply now
  follow it and drop out of sight when the message needs both lines. }
procedure TMainForm.CmdRows(out Pad, Row1, Row: Integer);
begin
  Pad := Round(5 * FUIScale);
  Row1 := Round(24 * FUIScale);
  Row := Round(18 * FUIScale);
end;

function TMainForm.CmdBarHeight: Integer;
var
  Pad, Row1, Row: Integer;
begin
  CmdRows(Pad, Row1, Row);
  Result := Pad + Row1 + Round(3 * FUIScale) + 2 * Row + Pad + Round(4 * FUIScale);
end;

{ where the message rows sit: under row one, from past the slash button to
  the right edge, in the bar's coordinates }
procedure TMainForm.PlaceCmdMsg;
var
  Pad, Row1, Row: Integer;
begin
  CmdRows(Pad, Row1, Row);
  { the tool pill sits left of the message rows, in a column as wide as the
    longest tool name, so messages start in one place }
  UIFont(pbCmd.Canvas, 10, True, Theme.Accent);
  FCmdPillW := pbCmd.Canvas.TextWidth('PROTRACTOR') + Round(18 * FUIScale);
  FCmdMsgR := Rect(Round(56 * FUIScale) + FCmdPillW + Round(10 * FUIScale), Pad + Row1 + Round(5 * FUIScale),
    Max(Round(96 * FUIScale), pbCmd.Width - Round(24 * FUIScale)),
    Pad + Row1 + Round(5 * FUIScale) + 2 * Row);
end;

{ Whether the chrome is pale (Light theme), so "sunk" things go lighter
  rather than darker. }
function TMainForm.LightChrome: Boolean;
begin
  Result := (Theme.Panel.R + Theme.Panel.G + Theme.Panel.B) > 3 * 140;
end;

{ A field to type into or read from (cut heights, command bar).  Sunk into a
  dark panel; on a pale one near white with an edge, since a darkened pale
  panel is a gray slab the text sinks into. }
function TMainForm.FieldPix: TPix;
begin
  if LightChrome then Result := MixPix(Theme.Panel, Pix(255, 255, 255), 0.75)
  else Result := MixPix(Theme.Panel, Pix(0, 0, 0), 0.30);
end;

function TMainForm.FieldEdgePix: TPix;
begin
  if LightChrome then Result := MixPix(Theme.Panel, Pix(0, 0, 0), 0.22)
  else Result := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.10);
end;

{ The colors of the bar's text, from the theme.  Bright marks are darkened
  on a light panel. }
function TMainForm.CmdPalette: TCmdPalette;
var
  Light: Boolean;

  function Hex(const C: TPix): string;
  begin
    Result := Format('#%.2x%.2x%.2x', [C.R, C.G, C.B]);
  end;

  function Mark(const C: TPix): string;
  begin
    if Light then Result := Hex(MixPix(C, Pix(0, 0, 0), 0.40))
    else Result := Hex(C);
  end;

begin
  Light := LightChrome;
  Result.Text := Hex(Theme.Text);
  Result.Dim := Hex(Theme.TextDim);
  Result.Name := Hex(Theme.Text);
  Result.Number := Mark(Pix(245, 190, 80));
  Result.Command := Hex(Theme.Accent);
  Result.Key := Hex(Theme.Text);
  Result.KeyBack := Hex(MixPix(Theme.Panel, Pix(255, 255, 255), 0.16));
  { typed text: green units, pink operators, a violet x, all distinct from
    the amber figures }
  Result.Units := Mark(Pix(110, 240, 150));
  Result.Op := Mark(Pix(255, 110, 180));
  Result.Sep := Mark(Pix(190, 150, 255));
end;

{ the color the snap's mark is drawn in (see PaintSnapMarker) }
function TMainForm.SnapMarkPix: TPix;
begin
  case FSnapKind of
    snEndpoint, snCenter: Result := Pix(60, 210, 90);
    snMidpoint, snSubMid: Result := Pix(90, 220, 235);
    snOnEdge:             Result := Pix(235, 70, 70);
    snOnFace:             Result := Pix(70, 130, 240);
    snQuadrant:           Result := Pix(90, 235, 120);
    snOnAxis:             Result := AxisPix(FSnapAxis);
    snOrigin:             Result := Pix(250, 210, 60);
    snCross:              Result := Pix(215, 120, 240);
  else
    Result := Theme.Accent;
  end;
end;

procedure TMainForm.pbCmdPaint(Sender: TObject);
var
  W, H, X, TW, I, Pad, Row1, Row, Y1, IL, IW: Integer;
  S, M, Caret: string;
  SumV, SumW: Double;
  P: TCmdPalette;
  Opt: THTMLOptions;
  Well, SnapCol: TPix;
  Sz: TSize;
  C: TCanvas;
begin
  W := pbCmd.Width;
  H := pbCmd.Height;
  C := pbCmd.Canvas;
  CmdRows(Pad, Row1, Row);
  Y1 := Pad;
  { the wells the typing and messages sit in: one flat color, the memo's, so
    they read as one piece }
  Well := FieldPix;
  FCmdSkin.SetSize(W, H);
  FCmdSkin.Clear(Pix(0, 0, 0));
  FCmdSkin.CopyRegion(FShell, pbCmd.Left, pbCmd.Top, 0, 0, W, H);
  PaintPanel(FCmdSkin, Rect(0, 0, W, H), Theme, Round(10 * FUIScale));
  FCmdSkin.RoundRect(Rect(Round(6 * FUIScale), Round(6 * FUIScale),
    Round(10 * FUIScale), H - Round(6 * FUIScale)), 2, Theme.Accent, 0.9);
  if FCmdMsgR.Right > FCmdMsgR.Left then
    FCmdSkin.RoundRect(Rect(FCmdMsgR.Left - Round(6 * FUIScale), FCmdMsgR.Top - Round(3 * FUIScale),
      FCmdMsgR.Right + Round(6 * FUIScale), FCmdMsgR.Bottom + Round(3 * FUIScale)),
      Round(6 * FUIScale), Well, 1.0);
  { on a pale panel a near-white well needs an edge to be seen }
  if LightChrome and (FCmdMsgR.Right > FCmdMsgR.Left) then
    FCmdSkin.RoundFrame(Rect(FCmdMsgR.Left - Round(6 * FUIScale), FCmdMsgR.Top - Round(3 * FUIScale),
      FCmdMsgR.Right + Round(6 * FUIScale), FCmdMsgR.Bottom + Round(3 * FUIScale)),
      Round(6 * FUIScale), 1.0, FieldEdgePix);
  FCmdSkin.DrawTo(C, 0, 0);
  P := CmdPalette;

  { The slash button: pressing it types the slash and brings up the list,
    just as typing one does.  A way in for anybody not using the keyboard. }
  FCmdArrow := Rect(Round(16 * FUIScale), Y1 + Round(1 * FUIScale),
                    Round(44 * FUIScale), Y1 + Row1 - Round(1 * FUIScale));
  C.Brush.Style := bsSolid;
  if FCmdArrowHot or (FPopup = POP_CMDS) then
    C.Brush.Color := PixToColor(Theme.Accent)
  else
    C.Brush.Color := PixToColor(MixPix(Theme.Panel, Pix(255, 255, 255), 0.10));
  C.Pen.Style := psClear;
  C.RoundRect(FCmdArrow.Left, FCmdArrow.Top, FCmdArrow.Right, FCmdArrow.Bottom,
    Round(7 * FUIScale), Round(7 * FUIScale));
  C.Pen.Style := psSolid;
  C.Brush.Style := bsClear;
  if FCmdArrowHot or (FPopup = POP_CMDS) then
    UIFont(C, 12, True, OnPix(Theme.Accent))
  else
    UIFont(C, 12, True, Theme.TextDim);
  S := '/';
  C.TextOut((FCmdArrow.Left + FCmdArrow.Right - C.TextWidth(S)) div 2,
    (FCmdArrow.Top + FCmdArrow.Bottom - C.TextHeight(S)) div 2, S);

  X := Round(56 * FUIScale);
  if FBusy then
  begin
    { long work on the main thread: what and how far, in place of the prompt }
    UIFont(C, 11, True, Theme.Accent);
    S := 'WORKING';
    C.TextOut(X, Y1 + (Row1 - C.TextHeight(S)) div 2, S);
    Inc(X, C.TextWidth(S) + Round(14 * FUIScale));
    UIFont(C, 11, False, Theme.Text);
    S := FBusyMsg;
    if FBusyFrac >= 0 then S := S + Format('  %d%%', [Round(EnsureRange(FBusyFrac, 0, 1) * 100)]);
    C.TextOut(X, Y1 + (Row1 - C.TextHeight(S)) div 2, S);
    Inc(X, C.TextWidth(S) + Round(18 * FUIScale));
    TW := W - X - Round(24 * FUIScale);
    if TW > Round(80 * FUIScale) then
    begin
      C.Pen.Style := psClear;
      C.Brush.Style := bsSolid;
      C.Brush.Color := PixToColor(Theme.Panel);
      C.RoundRect(X, Y1 + Row1 div 2 - Round(4 * FUIScale), X + TW, Y1 + Row1 div 2 + Round(4 * FUIScale),
        Round(8 * FUIScale), Round(8 * FUIScale));
      C.Brush.Color := PixToColor(Theme.Accent);
      if FBusyFrac >= 0 then
        C.RoundRect(X, Y1 + Row1 div 2 - Round(4 * FUIScale),
          X + Max(Round(8 * FUIScale), Round(TW * EnsureRange(FBusyFrac, 0, 1))), Y1 + Row1 div 2 + Round(4 * FUIScale),
          Round(8 * FUIScale), Round(8 * FUIScale))
      else
      begin
        { unknown progress: a light running along the track }
        I := Round((TW - TW div 5) * (0.5 - 0.5 * Cos(((GetTickCount64 mod 1400) / 1400) * 2 * Pi)));
        C.RoundRect(X + I, Y1 + Row1 div 2 - Round(4 * FUIScale), X + I + TW div 5, Y1 + Row1 div 2 + Round(4 * FUIScale),
          Round(8 * FUIScale), Round(8 * FUIScale));
      end;
      C.Pen.Style := psSolid;
      C.Brush.Style := bsClear;
    end;
    PaintCmdMsg(C, P);
    Exit;
  end;

  { the tool in an accent pill, left of the message rows }
  UIFont(C, 10, True, Theme.Accent);
  S := ToolName(FTool);
  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(MixPix(Theme.Panel, Theme.Accent, 0.20));
  C.Pen.Color := PixToColor(MixPix(Theme.Panel, Theme.Accent, 0.55));
  I := FCmdMsgR.Top - Round(3 * FUIScale);
  C.RoundRect(X, I, X + FCmdPillW, I + Row1 - Round(4 * FUIScale),
    Round(10 * FUIScale), Round(10 * FUIScale));
  C.Brush.Style := bsClear;
  C.TextOut(X + (FCmdPillW - C.TextWidth(S)) div 2,
    I + (Row1 - Round(4 * FUIScale) - C.TextHeight(S)) div 2, S);

  { Like SketchUp's measurements box: while dragging it shows the size being
    pulled, and once you type your figure takes its place.  The number goes
    where the typing goes, because they are the same number. }
  if (GetTickCount64 div 500) mod 2 = 0 then Caret := '|' else Caret := NBSP;
  if FInput <> '' then
  begin
    M := MarkTyped(FInput, P) + Painted(P.Command, '', False) +
      '<font color="' + P.Command + '">' + Caret + '</font>';
    { a typed sum (8' + 8") shows its total as you type (see ParseLen) }
    if ParseLen(FInput, FD.Units, SumV) and
       (not ParseLenPlain(FInput, FD.Units, SumW) or (Abs(SumV - SumW) > 1E-9)) then
      M := M + Painted(P.Dim, '   = ') + Painted(P.Number, FormatLen(SumV, FD.Units), True);
  end
  else
  begin
    S := LiveMeasure;
    { dimmer than typed text: a reading, not a decision }
    if S <> '' then M := Painted(P.Dim, S) + '<font color="' + P.Dim + '">' + Caret + '</font>'
    else M := '<font color="' + P.Command + '">' + Caret + '</font>' +
      Painted(P.Dim, ' type a size, or / for a command');
  end;
  { the typing box next to the slash, as wide as its content, the prompt
    after it }
  IW := EnsureRange(DrawCmdRuns(C, 0, 0, Row1, MaxInt, 12, True, M, True) +
    Round(24 * FUIScale), FCmdPillW + Round(10 * FUIScale) + Round(220 * FUIScale), W * 2 div 5);
  IL := X;
  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(Well);
  if FInput <> '' then C.Pen.Color := PixToColor(Theme.Accent)
  else C.Pen.Color := PixToColor(FieldEdgePix);
  C.RoundRect(IL, Y1 + Round(1 * FUIScale), IL + IW, Y1 + Row1 - Round(1 * FUIScale),
    Round(8 * FUIScale), Round(8 * FUIScale));
  C.Brush.Style := bsClear;
  DrawCmdRuns(C, IL + Round(12 * FUIScale), Y1, Row1, IL + IW - Round(8 * FUIScale), 12, True, M);
  X := IL + IW + Round(14 * FUIScale);
  IL := W - Round(18 * FUIScale);

  { What the cursor is holding, then what to do with it, in the color of the
    cursor's mark (as the cursor chip and SketchUp's status line read). }
  M := '';
  if (FD <> nil) and (FD.Doc.Context <> 0) then
    M := Painted(P.Dim, 'in ') + Painted(P.Name, '"' + FD.Doc.PartName(FD.Doc.Context) + '"', True) +
      Painted(P.Dim, '  ');
  { an axis lock in its axis color, parallel/perpendicular in SketchUp's
    magenta, otherwise the mark's color }
  if FAxisLock in [0..2] then SnapCol := AxisPix(FAxisLock)
  else if FParPerp in [1, 2] then SnapCol := Pix(220, 80, 220)
  else SnapCol := SnapMarkPix;
  if (SnapSays <> '') then
    M := M + '<b><font color="' + Format('#%.2x%.2x%.2x', [SnapCol.R, SnapCol.G, SnapCol.B]) +
      '">' + HtmlEsc(SnapSays) + '</font></b>' + Painted(P.Dim, '  ' + #$E2#$80#$BA + '  ');
  M := M + MarkMessage(PromptForTool, P);
  DrawCmdRuns(C, X, Y1, Row1, IL, 11, False, M);
  PaintCmdMsg(C, P);
end;

{ One line of the bar's markup, ending in an ellipsis at MaxX when it does
  not fit.  Returns the width it took (or would take, with Measure). }
function TMainForm.DrawCmdRuns(C: TCanvas; X, Y, H, MaxX, Size: Integer;
  Mono: Boolean; const M: string; Measure: Boolean): Integer;
var
  Opt: THTMLOptions;
  R: TRect;
begin
  UIFont(C, Size, False, Theme.Text, Mono);
  Opt := DefaultHTMLOptions;
  Opt.NoWrap := True;
  Opt.Ellipsis := True;
  Opt.VertAlign := ivaCenter;
  if Measure then
    Exit(HTMLTextExtentOpt(C, Rect(0, 0, 100000, H), [], M, Opt).cx);
  if MaxX <= X then Exit(0);
  R := Rect(X, Y, MaxX, Y + H);
  HTMLDrawOpt(C, R, [], M, Opt);
  Result := Min(MaxX - X, HTMLTextExtentOpt(C, R, [], M, Opt).cx);
end;

{ The message rows: the message, wrapped to two lines by LazInk, then the
  keys that would do something now (out of sight when the message needs
  both lines). }
procedure TMainForm.PaintCmdMsg(C: TCanvas; const P: TCmdPalette);
var
  M, Tip: string;
  Opt: THTMLOptions;
begin
  if FCmdMsgR.Right <= FCmdMsgR.Left then Exit;
  M := '';
  if FCmdMsg <> '' then M := MarkMessage(FCmdMsg, P);
  Tip := '';
  if (FInput = '') and (ModifierTip <> '') then
  begin
    { dimmer than the message: plain words dim, keys still as keys }
    Tip := StringReplace(MarkMessage(ModifierTip, P), '<font color="' + P.Text + '">',
      '<font color="' + P.Dim + '">', [rfReplaceAll]);
    if M <> '' then M := M + '<br>' + Tip else M := Tip;
  end;
  if M = '' then Exit;
  UIFont(C, 11, False, Theme.Text);
  Opt := DefaultHTMLOptions;
  Opt.VertAlign := ivaTop;
  C.ClipRect := FCmdMsgR;
  C.Clipping := True;
  try
    HTMLDrawOpt(C, FCmdMsgR, [], M, Opt);
  finally
    C.Clipping := False;
  end;
end;

{ the bar's right-click: copy the message or the input, for bug reports }
procedure TMainForm.CmdMenuClick(Sender: TObject);
begin
  case (Sender as TMenuItem).Tag of
    1: if FCmdMsg <> '' then Clipboard.AsText := FCmdMsg;
    2: if FInput <> '' then Clipboard.AsText := FInput;
  end;
end;

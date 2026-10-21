  { hsMainForm - the menu bar and its menus.  Part of TMainForm; included by hsMainForm.pas }

  { ======================================================================== }
  { the menu bar                                                              }
  { ======================================================================== }

{ Five words across the title, as every program has them.  Each opens a
  native menu that is built fresh as it opens, so a check mark can never go
  stale.  The settings that used to sit on a deck across the foot of the
  window live behind SETTINGS now; that strip of screen belongs to the
  drawing again. }
const
  MENU_NAMES: array[0..4] of string =
    ('FILE', 'EDIT', 'VIEW', 'SETTINGS', 'HELP');
  BAR_FILE = 0;
  BAR_EDIT = 1;
  BAR_VIEW = 2;
  BAR_SETTINGS = 3;
  BAR_HELP = 4;

function TMainForm.QuickWidth: integer;
var
  I: integer;
begin
  UIFont(Canvas, 10, True, Theme.Text);
  Result := Round(4 * FUIScale);
  for I := 0 to High(MENU_NAMES) do
    Inc(Result, Canvas.TextWidth(MENU_NAMES[I]) + Round(22 * FUIScale));
end;

procedure TMainForm.RebuildQuick;
var
  I, X, W, H: integer;
begin
  SetLength(FQuick, 0);
  H := pbQuick.Height;
  UIFont(Canvas, 10, True, Theme.Text);
  X := Round(2 * FUIScale);
  for I := 0 to High(MENU_NAMES) do
  begin
    W := Canvas.TextWidth(MENU_NAMES[I]) + Round(20 * FUIScale);
    SetLength(FQuick, Length(FQuick) + 1);
    with FQuick[High(FQuick)] do
    begin
      Kind := dkSegment;
      Bounds := Rect(X, 1, X + W, H - 1);
      Group := 0;
      Value := I;
      Caption := MENU_NAMES[I];
      Hint := '';
      Icon := ikChevron;
    end;
    Inc(X, W + Round(2 * FUIScale));
  end;
end;

function TMainForm.QuickHit(X, Y: integer): integer;
var
  I: integer;
begin
  for I := 0 to High(FQuick) do
    if PtInRect(FQuick[I].Bounds, Point(X, Y)) then Exit(I);
  Result := -1;
end;

procedure TMainForm.pbQuickPaint(Sender: TObject);
var
  I, W, H: integer;
  R: TRect;
begin
  W := pbQuick.Width;
  H := pbQuick.Height;
  if (W < 8) or (H < 8) then Exit;
  FQuickSkin.SetSize(W, H);
  FQuickSkin.Clear(Pix(0, 0, 0));
  FQuickSkin.CopyRegion(FShell, pbQuick.Left, pbQuick.Top, 0, 0, W, H);

  if (FHotQuick >= 0) and (FHotQuick <= High(FQuick)) then
  begin
    R := FQuick[FHotQuick].Bounds;
    FQuickSkin.RoundRect(R, Round(4 * FUIScale),
      MixPix(Theme.Panel, Pix(255, 255, 255), 0.16));
    FQuickSkin.RoundFrame(R, Round(4 * FUIScale), 1.0,
      MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.16));
  end;
  FQuickSkin.DrawTo(pbQuick.Canvas, 0, 0);

  UIFont(pbQuick.Canvas, 10, True, Theme.Text);
  for I := 0 to High(FQuick) do
  begin
    R := FQuick[I].Bounds;
    pbQuick.Canvas.TextOut(
      (R.Left + R.Right - pbQuick.Canvas.TextWidth(FQuick[I].Caption)) div 2,
      (R.Top + R.Bottom - pbQuick.Canvas.TextHeight('X')) div 2,
      FQuick[I].Caption);
  end;
end;

procedure TMainForm.pbQuickMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
var
  H: integer;
begin
  H := QuickHit(X, Y);
  if H <> FHotQuick then
  begin
    FHotQuick := H;
    pbQuick.Invalidate;
  end;
end;

procedure TMainForm.pbQuickMouseLeave(Sender: TObject);
begin
  if FHotQuick <> -1 then
  begin
    FHotQuick := -1;
    pbQuick.Invalidate;
  end;
end;

procedure TMainForm.pbQuickMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  if Button <> mbLeft then Exit;
  OpenBarMenu(QuickHit(X, Y));
end;

{ where a menu hangs: under its own word }
function TMainForm.BarMenuPoint(Index: integer): TPoint;
begin
  Result := Point(0, pbQuick.Height);
  if (Index >= 0) and (Index <= High(FQuick)) then
    Result := Point(FQuick[Index].Bounds.Left, FQuick[Index].Bounds.Bottom);
  Result := pbQuick.ClientToScreen(Result);
end;

function TMainForm.BarPopup(Index: integer): TPopupMenu;
begin
  case Index of
    BAR_FILE: Result := pmFile;
    BAR_EDIT: Result := pmEdit;
    BAR_VIEW: Result := pmView;
    BAR_SETTINGS: Result := pmSettings;
    else
      Result := pmHelp;
  end;
end;

{ TPopupMenu.Close only resets LCL bookkeeping; the native menu must be
  popped down itself, which is what ends PopUp's wait. }
procedure TMainForm.CloseBarMenu;
begin
  if FBarMenu < 0 then Exit;
  {$IFDEF LCLGTK3}
  if BarPopup(FBarMenu).HandleAllocated then
    gtk_menu_popdown(PGtkMenu(TGtk3Menu(BarPopup(FBarMenu).Handle).Widget));
  {$ENDIF}
end;

{ An open menu grabs the mouse, so the bar never hears the click that
  dismisses it - a second menu took two clicks.  While one of our menus is
  up the tick watches the cursor instead: resting on another word closes
  this menu, and OpenBarMenu carries straight on to that one, the sweep a
  real menu bar gives. }
procedure TMainForm.TrackBarMenu;
var
  P: TPoint;
  H: integer;
begin
  if FBarMenu < 0 then Exit;
  P := pbQuick.ScreenToClient(Mouse.CursorPos);
  H := QuickHit(P.X, P.Y);
  if (H >= 0) and (H <> FBarMenu) then
  begin
    FBarSwitch := H;
    CloseBarMenu;
  end;
end;

procedure TMainForm.OpenBarMenu(Index: integer);
var
  P: TPoint;
  H: integer;
begin
  while (Index >= 0) and (Index <= High(FQuick)) do
  begin
    FBarMenu := Index;
    FBarSwitch := -1;
    FHotQuick := Index;
    pbQuick.Invalidate;
    case Index of
      BAR_FILE: ShowFileMenu;
      BAR_EDIT: ShowEditMenu;
      BAR_VIEW: ShowViewMenu;
      BAR_SETTINGS: ShowSettingsMenu;
      BAR_HELP: ShowHelpMenu;
    end;                        { PopUp waits here until the menu closes }
    FBarMenu := -1;
    if FBarSwitch < 0 then
    begin
      { a press on another word can land before the tick saw the hover;
        the menu ate that press, so honor it here }
      P := pbQuick.ScreenToClient(Mouse.CursorPos);
      H := QuickHit(P.X, P.Y);
      if (H >= 0) and (H <> Index) and ((GetKeyState(VK_LBUTTON) and $8000) <> 0) then
        FBarSwitch := H;
    end;
    Index := FBarSwitch;
  end;
  P := pbQuick.ScreenToClient(Mouse.CursorPos);
  FHotQuick := QuickHit(P.X, P.Y);
  pbQuick.Invalidate;
end;

{ ---- the File menu ----
  Everything to do with files.  Its shortcuts are shown beside each row and
  work whether the menu is open or not. }
const
  FM_NEW = 1;
  FM_OPEN = 2;
  FM_SAVE = 3;
  FM_SAVEAS = 4;
  FM_SAVEALL = 5;
  FM_ADDSHEET = 6;
  FM_DELSHEET = 7;
  FM_EXPORT = 8;
  FM_PRINT = 9;
  FM_EXAMPLE = 10;
  FM_CLOSE = 11;
  FM_EXIT = 12;
  FM_CLEARRECENT = 13;

procedure TMainForm.ShowFileMenu;
var
  M, Sub: TMenuItem;
  I, N: integer;
  P: TPoint;

  function Add(Parent: TMenuItem; const Caption: string; Tag: integer; Key: word = 0; Shift: TShiftState = []; Enabled: boolean = True): TMenuItem;
  begin
    Result := TMenuItem.Create(pmFile);
    Result.Caption := Caption;
    Result.Tag := Tag;
    Result.Enabled := Enabled;
    if Key <> 0 then Result.ShortCut := Menus.ShortCut(Key, Shift);
    Result.OnClick := @FileMenuClick;
    if Parent = nil then pmFile.Items.Add(Result)
    else
      Parent.Add(Result);
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
  P := BarMenuPoint(BAR_FILE);
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
  I: integer;
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

{ ---- the Edit menu ----
  Undo and the clipboard.  The keys do the same whether the menu is open or
  not; the rows exist so they can be found. }
const
  EM_UNDO = 1;
  EM_REDO = 2;
  EM_CUT = 3;
  EM_COPY = 4;
  EM_PASTE = 5;
  EM_ALL = 6;
  EM_NONE = 7;

procedure TMainForm.ShowEditMenu;
var
  P: TPoint;

  procedure Add(const Caption: string; Tag: integer; Key: word = 0; Shift: TShiftState = []; Enabled: boolean = True);
  var
    It: TMenuItem;
  begin
    It := TMenuItem.Create(pmEdit);
    It.Caption := Caption;
    It.Tag := Tag;
    It.Enabled := Enabled;
    if Key <> 0 then It.ShortCut := Menus.ShortCut(Key, Shift);
    It.OnClick := @EditMenuClick;
    pmEdit.Items.Add(It);
  end;

  procedure Line;
  var
    L: TMenuItem;
  begin
    L := TMenuItem.Create(pmEdit);
    L.Caption := '-';
    pmEdit.Items.Add(L);
  end;

begin
  pmEdit.Items.Clear;
  Add('Undo', EM_UNDO, VK_Z, [ssCtrl], CanUndo);
  Add('Redo', EM_REDO, VK_Y, [ssCtrl], CanRedo);
  Line;
  Add('Cut', EM_CUT, VK_X, [ssCtrl], Length(FSel) > 0);
  Add('Copy', EM_COPY, VK_C, [ssCtrl], Length(FSel) > 0);
  Add('Paste', EM_PASTE, VK_V, [ssCtrl], Length(FClip) > 0);
  Line;
  Add('Select All  (/all)', EM_ALL, 0, [], FD.Doc.Live > 0);
  Add('Select None  (Esc)', EM_NONE, 0, [], Length(FSel) > 0);
  P := BarMenuPoint(BAR_EDIT);
  pmEdit.PopUp(P.X, P.Y);
end;

procedure TMainForm.EditMenuClick(Sender: TObject);
begin
  case (Sender as TMenuItem).Tag of
    EM_UNDO: DoUndo;
    EM_REDO: DoRedo;
    EM_CUT: CopySelection(True);
    EM_COPY: CopySelection(False);
    EM_PASTE: PasteClip;
    EM_ALL: RunCommand('all');
    EM_NONE:
    begin
      SelectNone;
      FCmdMsg := 'Nothing selected.';
      FScreenDirty := True;
    end;
  end;
  InvalidateStatus;
  pbCmd.Invalidate;
  pbScreen.Invalidate;
end;

{ ---- the View menu ----
  Where to stand (the paper modes and every camera preset, from the same
  table the V key steps through), and what else shows: the grid, the cube
  and the two panels. }
const
  VM_FIT = 100;
  VM_ORIGIN = 101;
  VM_GRID = 102;
  VM_CUBE = 103;
  VM_INFO = 104;
  VM_GROUPS = 105;

procedure TMainForm.ShowViewMenu;
var
  I: integer;
  P: TPoint;

  function Add(const Caption: string; Tag: integer; Checked: boolean = False): TMenuItem;
  begin
    Result := TMenuItem.Create(pmView);
    Result.Caption := Caption;
    Result.Tag := Tag;
    Result.Checked := Checked;
    Result.OnClick := @ViewMenuClick;
    pmView.Items.Add(Result);
  end;

  procedure Line;
  var
    L: TMenuItem;
  begin
    L := TMenuItem.Create(pmView);
    L.Caption := '-';
    pmView.Items.Add(L);
  end;

begin
  pmView.Items.Clear;
  Add('Fit the Drawing  (Shift+F)', VM_FIT);
  Add('Put 0,0 Under the Cursor  (/origin)', VM_ORIGIN);
  Line;

  { PLAN first: a plan is a slice through the model, and the cut fields live
    there, so it must be reachable by mouse.  TOP is the free camera looking
    nearly straight down, which looks like a plan but has no cut; both
    captions say what they are. }
  Add('PLAN - flat, with the cut', 0, FD.View = vkPlan);
  Add('ISO - flat, on the paper axes', 1, FD.View = vkIso);
  Line;
  for I := FIRST_CAMERA_PRESET to High(VIEW_PRESETS) do
    if I = High(VIEW_PRESETS) then
      Add('TOP - 3D, from above', I, (FD.View = vkOrbit) and (FViewPreset = I))
    else
      Add(VIEW_PRESETS[I].Name, I, (FD.View = vkOrbit) and (FViewPreset = I));
  Line;

  Add('Grid  (G)', VM_GRID, FShowGrid);
  Add('View Cube  (/cube)', VM_CUBE, FCubeOn);
  Add('Entity Panel  (/info)', VM_INFO, FInfoOn);
  Add('Groups Panel  (/groups)', VM_GROUPS, FGroupsOn);
  P := BarMenuPoint(BAR_VIEW);
  pmView.PopUp(P.X, P.Y);
end;

procedure TMainForm.ViewMenuClick(Sender: TObject);
begin
  case (Sender as TMenuItem).Tag of
    VM_FIT: FitView;
    VM_ORIGIN: SetOriginHere;
    VM_GRID: RunCommand('grid');
    VM_CUBE: RunCommand('cube');
    VM_INFO: RunCommand('info');
    VM_GROUPS: RunCommand('groups');
    else
      ApplyViewPreset((Sender as TMenuItem).Tag);
  end;
  pbCmd.Invalidate;
end;

{ ---- the Settings menu ----
  What the deck's buttons used to show.  Each submenu's title carries the
  current value, so nothing is lost by folding them away. }

const
  { the palette's colors, named, since a menu row cannot be only a square }
  PALETTE_NAMES: array[0..11] of string = (
    'Black', 'White', 'Gray', 'Red', 'Orange', 'Amber',
    'Lime', 'Green', 'Teal', 'Blue', 'Violet', 'Pink');

procedure TMainForm.ShowSettingsMenu;
var
  Root: TMenuItem;
  I, Sz: integer;
  Sw: TArtSurface;
  P: TPoint;

  function Sub(const Caption: string): TMenuItem;
  begin
    Result := TMenuItem.Create(pmSettings);
    Result.Caption := Caption;
    pmSettings.Items.Add(Result);
  end;

  function Add(Parent: TMenuItem; const Caption: string; Tag: integer; Checked: boolean): TMenuItem;
  begin
    Result := TMenuItem.Create(pmSettings);
    Result.Caption := Caption;
    Result.Tag := Tag;
    Result.Checked := Checked;
    Result.OnClick := @SettingsMenuClick;
    Parent.Add(Result);
  end;

  function Precision: string;
  begin
    if FLenDenom = 100 then Result := '.01"'
    else
      Result := Format('1/%d"', [FLenDenom]);
  end;

begin
  pmSettings.Items.Clear;

  Root := Sub('Print Scale  -  ' + ScaleTable(FD.Units, FD.ScaleIdx).Name);
  for I := 0 to SCALE_COUNT - 1 do
    Add(Root, ScaleTable(FD.Units, I).Name + IfThen(FD.Units = usImperial, '  =  1''-0"', ''), 1000 + I,
      I = FD.ScaleIdx);

  Root := Sub('Snap To  -  ' + SnapName(FD.Units, FD.SnapIdx));
  for I := 0 to SNAP_COUNT - 1 do
    Add(Root, IfThen(I = 0, 'No snapping', SnapName(FD.Units, I)), 2000 + I,
      I = FD.SnapIdx);

  Root := Sub('Line Color');
  Sz := Round(14 * FUIScale);
  Sw := TArtSurface.Create(Sz, Sz);
  try
    for I := 0 to High(PALETTE) do
      with Add(Root, PALETTE_NAMES[I], 3000 + I, PALETTE[I] = FInkColor) do
      begin
        { the swatch is rasterized by our own surface; one drawn with the
          LCL canvas comes out blank under GTK3 }
        Sw.ClearTransparent;
        Sw.RoundRect(Rect(0, 0, Sz, Sz), Sz * 0.22, ColorToPix(PALETTE[I]));
        Sw.RoundFrame(Rect(0, 0, Sz, Sz), Sz * 0.22, 1.0, Pix(128, 128, 128));
        if PALETTE[I] = FInkColor then
          Sw.RoundFrame(Rect(2, 2, Sz - 2, Sz - 2), Sz * 0.15, 2.0,
            OnPix(ColorToPix(PALETTE[I])));
        Bitmap.Assign(Sw.AsBitmap);
      end;
  finally
    Sw.Free;
  end;
  Add(Root, 'Another Color...', 3000 + Length(PALETTE), False);

  Root := Sub(Format('Line Width  -  %d px', [FEdgeW]));
  for I := 0 to PEN_STEPS - 1 do
    Add(Root, Format('%d px', [PEN_SIZES[I]]), 4000 + I, PEN_SIZES[I] = FEdgeW);

  Root := Sub('Rounded To  -  ' + Precision);
  for I := 0 to High(PREC_DENOMS) do
    if PREC_DENOMS[I] = 100 then
      Add(Root, 'hundredths of an inch', 5000 + I, FLenDenom = 100)
    else
      Add(Root, Format('1/%d"', [PREC_DENOMS[I]]), 5000 + I,
        FLenDenom = PREC_DENOMS[I]);

  Root := Sub('Units  (U)');
  Add(Root, 'Feet and Inches', 6000, FD.Units = usImperial);
  Add(Root, 'Millimeters', 6001, FD.Units = usMetric);

  Root := Sub('Chrome  (H)');
  for I := 0 to THEME_COUNT - 1 do
    Add(Root, Themes[I].Name, 7000 + I, FThemeIdx = I);

  Root := Sub('File Associations' + AssocSuffix);
  Add(Root, 'Set Up on This Computer', 8000, False);
  Add(Root, 'Remove from This Computer', 8001, False);
  Add(Root, 'Repair at Start-up', 8002, FAssocRepair);

  P := BarMenuPoint(BAR_SETTINGS);
  pmSettings.PopUp(P.X, P.Y);
end;

procedure TMainForm.SettingsMenuClick(Sender: TObject);
var
  T, I: integer;
begin
  T := (Sender as TMenuItem).Tag;
  I := T mod 1000;
  case T div 1000 of
    1: SetScaleIdx(I);
    2:
    begin
      FD.SnapIdx := EnsureRange(I, 0, SNAP_COUNT - 1);
      Act('snap ' + IntToStr(FD.SnapIdx));
      FCmdMsg := 'Snap: ' + SnapName(FD.Units, FD.SnapIdx);
    end;
    3: if I = Length(PALETTE) then PickAnyColor
      else
        SetInk(PALETTE[I], False);
    4: SetEdgeWidth(PEN_SIZES[EnsureRange(I, 0, High(PEN_SIZES))]);
    5: SetLenPrecision(PREC_DENOMS[EnsureRange(I, 0, High(PREC_DENOMS))]);
    6: SetUnits(TUnitSystem(EnsureRange(I, 0, 1)));
    7: if I <> FThemeIdx then CycleTheme(I - FThemeIdx);
    8: AssociationsPick(I);
  end;
  pbCmd.Invalidate;
end;

{ ---- the Help menu ---- }
const
  HM_ABOUT = 1;
  HM_UPDATE = 2;
  HM_WHATSNEW = 3;
  HM_MANUAL = 4;
  HM_DOWNLOADS = 5;
  HM_PROJECT = 6;
  HM_REPORT = 7;

procedure TMainForm.ShowHelpMenu;
var
  P: TPoint;

  procedure Add(const Caption: string; Tag: integer);
  var
    It: TMenuItem;
  begin
    It := TMenuItem.Create(pmHelp);
    It.Caption := Caption;
    It.Tag := Tag;
    It.OnClick := @HelpMenuClick;
    pmHelp.Items.Add(It);
  end;

  procedure Line;
  var
    L: TMenuItem;
  begin
    L := TMenuItem.Create(pmHelp);
    L.Caption := '-';
    pmHelp.Items.Add(L);
  end;

begin
  pmHelp.Items.Clear;
  Add('About  (F1)', HM_ABOUT);
  Add('What''s New', HM_WHATSNEW);
  Add('Check for Updates', HM_UPDATE);
  Line;
  Add('The Manual', HM_MANUAL);
  Add('Downloads', HM_DOWNLOADS);
  Add('Project Page', HM_PROJECT);
  Line;
  Add('Report a Problem...', HM_REPORT);
  P := BarMenuPoint(BAR_HELP);
  pmHelp.PopUp(P.X, P.Y);
end;

procedure TMainForm.HelpMenuClick(Sender: TObject);
begin
  case (Sender as TMenuItem).Tag of
    HM_ABOUT: ShowAbout;
    HM_UPDATE: begin
      CheckForUpdate(True);
      DoUpdate;
    end;
    HM_WHATSNEW: ShowWhatsNew;
    HM_MANUAL: OpenManual;
    HM_DOWNLOADS: OpenURL('https://github.com/' + UPDATE_REPO + '/releases/latest');
    HM_PROJECT: OpenURL('https://github.com/' + UPDATE_REPO);
    HM_REPORT: ReportBug;
  end;
end;

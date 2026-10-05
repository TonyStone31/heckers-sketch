unit hsRadiantWizard;

{ The radiant heat layout wizard.  Given the floor's outline (the selected
  faces, their holes as obstacles), it asks the usual design questions and
  shows the plan and material list.  It puts a manifold in each zone on
  opening but searches only when asked, since a search takes seconds a
  zone; anything that changes where tube can go clears the zones it touches. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, Graphics,
  ComCtrls, Dialogs, StrUtils, Menus, Spin, BCButton, BGRATheme, BGRAThemeCheckBox, BCPanel, hsDrawing, hsRadiantData, hsRadiant, hsRadiantBusy,
  hsRadiantSubmittal, hsRadiantHeat, hsDialogSkin, BCComboBox, BCTrackbarUpdown, InkListBox, InkEdit, InkMemo;

type

  { TRadiantForm }

  TRadiantForm = class(TForm)
    btnBuild: TBCButton;
    btnCancel: TBCButton;
    btnReport: TBCButton;
    btnSearchAll: TBCButton;
    btnSuggest: TBCButton;
    btnExport: TBCButton;
    btnPreview: TBCButton;
    sdExport: TSaveDialog;
    btnZoneClear: TBCButton;
    btnZoneSearch: TBCButton;
    lblFoundHead: TLabel;
    lblZoneHead: TLabel;
    lblZoneName: TLabel;
    edZoneName: TInkEdit;
    cbPinManifold: TBGRAThemeCheckBox;
    lblZonesHint: TLabel;
    lbSolutions: TInkListBox;
    pnZone: TPanel;
    cbLabels: TBGRAThemeCheckBox;
    lblPinManifold: TLabel;
    lblLabels: TLabel;
    btnHeat: TBCButton;
    btnNotZone: TBCButton;
    miNotZone: TMenuItem;
    miBringBack: TMenuItem;
    cbTube: TBCComboBox;
    edMaxLoop: TInkEdit;
    edSpacing: TInkEdit;
    edTag: TInkEdit;
    edWaste: TBCTrackbarUpdown;
    edMaxPorts: TBCTrackbarUpdown;
    lblManifoldHead: TLabel;
    lblMaxLoop: TLabel;
    lblMaxLoopHint: TLabel;
    lblNeed: TLabel;
    lblProblem: TLabel;
    lblSpacing: TLabel;
    lblSpacingIn: TLabel;
    lblTag: TLabel;
    lblTagHint: TLabel;
    lblTicket: TLabel;
    lblTitle: TLabel;
    lblTube: TLabel;
    lblUnits: TLabel;
    lblWaste: TLabel;
    lblMaxPorts: TLabel;
    lblWastePct: TLabel;
    memTicket: TInkMemo;
    miClearAll: TMenuItem;
    miClearZone: TMenuItem;
    miRotate: TMenuItem;
    miFace: TMenuItem;
    miFaceEW: TMenuItem;
    miFaceNS: TMenuItem;
    miFace45: TMenuItem;
    miFace135: TMenuItem;
    miSearchAll: TMenuItem;
    miSearchZone: TMenuItem;
    miSep: TMenuItem;
    pbCoverage: TPaintBox;
    pbEven: TPaintBox;
    pbPlan: TPaintBox;
    pmZone: TPopupMenu;
    pnSettings: TBCPanel;
    pnPlanArea: TBCPanel;
    pnZoneArea: TBCPanel;
    pnZones: TPanel;
    pbZoneTabs: TPaintBox;
    procedure AnyChange(Sender: TObject);
    procedure btnNotZoneClick(Sender: TObject);
    procedure btnBringBackClick(Sender: TObject);
    procedure btnReportClick(Sender: TObject);
    procedure btnSearchAllClick(Sender: TObject);
    procedure btnSearchZoneClick(Sender: TObject);
    procedure btnSuggestClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnBuildClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure lbSolutionsClick(Sender: TObject);
    procedure tcZonesChange(Sender: TObject);
    procedure edZoneNameChange(Sender: TObject);
    procedure cbPinManifoldChange(Sender: TObject);
    procedure btnHeatClick(Sender: TObject);
    procedure CheckLabelClick(Sender: TObject);
    procedure ShowHeat;
    procedure btnPreviewClick(Sender: TObject);
    procedure pbCoveragePaint(Sender: TObject);
    procedure pbEvenPaint(Sender: TObject);
    procedure pbPlanMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure pbPlanMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbPlanMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure pbPlanPaint(Sender: TObject);
    procedure miClearAllClick(Sender: TObject);
    procedure miClearZoneClick(Sender: TObject);
    procedure miRotateClick(Sender: TObject);
    procedure miFaceClick(Sender: TObject);
    procedure miSearchZoneClick(Sender: TObject);
    procedure pmZonePopup(Sender: TObject);
    procedure RoutingChange(Sender: TObject);
  private
    FZoneTabs: THsTabStrip;
    FUnits: TUnitSystem;
    FZones: TRadiantZones;           { every face selected, with its holes }
    { closed shapes that are not floor to heat (a chase, a column against
      a wall), left out by Not a zone and able to be brought back.
      Obstacles are holes in a face, never zones (see DropHoles). }
    FLeftOut: TRadiantZones;
    FManifolds: TP3Array;            { one per zone }
    { each manifold's heading in the plan's frame, degrees: the way its
      long side, the row of ports, runs }
    FAngles: array of Double;
    FPorts: TIntArray;
    FLayouts: TRadiantResults;
    { zones searched since anything that moves tube last changed; a zone
      not searched shows no tube and cannot be built }
    FSearched: array of Boolean;
    { the search under way: its window, and which zone of how many }
    FBusy: TRadiantBusyForm;
    FBusyIndex, FBusyCount: Integer;
    { solutions the search has kept so far, best first, for the busy
      window's list }
    FLiveFound: TRadiantResults;
    { the goals as the busy window has them, read by the search after
      every layout, and when the current zone's search began }
    FLiveGoals: TRadiantGoals;
    FZoneStart: QWord;
    { when the busy window was last updated - see SearchProgress }
    FShownAt: QWord;
    { layouts laid a second, measured over the last couple of seconds, so
      a big batch does not look stalled }
    FRateAt: QWord;
    FRateLaid: Integer;
    FRate: Double;
    FGiveUpIdx: Integer;
    { the search window's less friendly and hooks choices (see the spec);
      remembered }
    FLessFriendly, FNoHooks: Boolean;
    { the search's goals and whether it tries hooked pairs; set in the search
      window, kept here between searches and saved }
    FGoalCover, FGoalEven: Double;
    FHookPairs: Boolean;
    { the zone the search window's list is about, once the search is done }
    FLastSearched: Integer;
    { the evenness gauge's worst zone: longest loop less shortest, feet }
    FEvenFt: Double;
    { what SearchWork searches, set by Search before the busy window runs it }
    FWorkSpec: TRadiantSpec;
    FWorkZones: TIntArray;
    { the outline of everything, for the plan's frame and the fit }
    FOutline: TP3Array;
    { the plan's projection, worked out at paint time and kept for the
      mouse: the outline's frame and how it maps to pixels }
    FFrame: TRadiantFrame;
    FMinX, FMinY, FSc: Double;
    { what centers the floor in the plan's box }
    FOffX, FOffY: Double;
    FMargin: Integer;
    { the manifold being dragged on the plan, or -1 }
    FDragManifold: Integer;
    FDragOff: T2;
    FDragMoved: Boolean;
    FListing: Boolean;
    { the two gauges from the last Summarize; -1 means nothing to show yet }
    FCoverage, FEvenness: Double;
    { each zone's material list, as Summarize last wrote them }
    FZoneTicket: array of string;
    { each zone's name as typed on its tab; '' means just its number }
    FZoneNames: array of string;
    { each zone's manifold pinned where it was put (see PinManifold);
      remembered with the zone's name }
    FPins: array of Boolean;
    { the heat load, if one is set (see hsRadiantHeatForm); remembered
      with the zones' names }
    FHeat: THeatJob;
    FAllTicket: string;
    { why the zone's search ended early (Stop or the give-up time), for
      its record }
    FStopWhy: string;
    { each zone's solutions from its last search (those that met the
      goals, best first, or the nearest few) and which one it shows and
      will build }
    FSolutions: array of TRadiantResults;
    FSolIdx: TIntArray;
    procedure ShowSolution(Z, Idx: Integer);
    { the zone tabs (one a zone, one for all) and the panel under them }
    procedure ListZones;
    procedure ShowZonePanel;
    procedure SelectZone(Z: Integer);
    procedure Summarize;
    procedure LoadLast;
    procedure SaveLast;
    procedure ClearZone(Z: Integer);
    procedure ClearAll;
    function ZoneSpec(Z: Integer; const Spec: TRadiantSpec): TRadiantSpec;
    function SelectedZone: Integer;
    procedure Dress;
    { the settings key for a zone's name and the job's: the floor's own
      corners, so the same floor opened again finds them }
    function NameKey(Z: Integer): string;
    procedure LoadNames;
    procedure SaveNames;
    function MakeJob(out Job: TRadiantJob): Boolean;
    { put a spec's settings on the form - the other half of Read }
    procedure ShowSpec(const Spec: TRadiantSpec);
    { what Ask and Reopen hand back once the window closes with Build }
    function Finish(out Zones: TRadiantZones; out Spec: TRadiantSpec; out Manifolds: TP3Array;
      out Ports: TIntArray; out Layouts: TRadiantResults; out ZoneNames: TStringArray;
      out Job: TRadiantJob): Boolean;
    { "Zone 2", or "Zone 2 - Kitchen" }
    function ZoneTitle(Z: Integer): string;
    function WallAngle(Z: Integer): Double;
    function NearestWall(Z: Integer; const M: T2; out D, Angle: Double; out Curved: Boolean): Boolean;
    function ManifoldBox(Z: Integer): T2Array;
    function ManifoldAt(X, Y: Integer): Integer;
    procedure Search(const Which: array of Integer);
    procedure SearchWork(Sender: TObject);
    procedure PickFromBusy;
    procedure SearchProgress(Done, Total: Integer; const Best: TRadiantResult; var Stop: Boolean);
    { a kept solution as a line in the busy window's list, and a shorter
      one for the zone tab }
    function FoundLine(const R: TRadiantResult): string;
    function ShortLine(const R: TRadiantResult): string;
    function ResultLine(const R: TRadiantResult; Short: Boolean): string;
    procedure SearchPreview(C: TCanvas; W, H: Integer; const Picked: string);
    procedure PaintCompass(C: TCanvas; CX, CY: Integer);
    function Read(out Spec: TRadiantSpec): Boolean;
    function ZoneHoles(Z: Integer): TRadiantHoles;
    { zone Z's coverage goal beyond what its tube can reach, in words; ''
      when it is within reach (see RadiantReachText) }
    function ReachNote(Z: Integer; const Spec: TRadiantSpec): string;
    function AnyLayout: Boolean;
    procedure ShowLeftOut;
    { take zone Z out of every per-zone list; with Remember it stays out
      when this floor is opened again }
    procedure DropZone(Z: Integer; Remember: Boolean);
    { on opening, drop zones that are holes in another and those left out
      before }
    procedure DropHoles;
    function OutlineKey(const O: TP3Array): string;
    function PlanX(U: Double): Integer;
    function PlanY(V: Double): Integer;
    function PlanU(X: Integer): Double;
    function PlanV(Y: Integer): Double;
  public
    { Layouts come back as searched, so building never searches again.
      Zones come back less any shape that is not a zone (see DropHoles).
      Job is the whole job as the submittal has it, for the drawing to keep
      in the zones' groups (see hsRadiantJob). }
    class function Ask(Units: TUnitSystem; var Zones: TRadiantZones;
      out Spec: TRadiantSpec; out Manifolds: TP3Array; out Ports: TIntArray;
      out Layouts: TRadiantResults; out ZoneNames: TStringArray; out Job: TRadiantJob): Boolean;
    { the same, opened on a job the drawing kept: its zones, manifolds,
      settings and layouts as built, already searched }
    class function Reopen(Units: TUnitSystem; const Was: TRadiantJob; out Zones: TRadiantZones;
      out Spec: TRadiantSpec; out Manifolds: TP3Array; out Ports: TIntArray;
      out Layouts: TRadiantResults; out ZoneNames: TStringArray; out Job: TRadiantJob): Boolean;
  end;

implementation

{$R *.lfm}

uses
  IniFiles, LCLIntf, LCLType, hsPaths, hsMainForm, hsUpdater, hsSurface, hsRadiantHeatForm, hsText;

{ a bare number is inches - the trade says 9, not 9" - and a mark switches
  to the drawing's own notation, as the fitting wizard does }
function InchesOf(const S: string; U: TUnitSystem; out V: Double): Boolean;
var
  T: string;
begin
  T := Trim(S);
  V := 0;
  if T = '' then Exit(False);
  if (Pos('''', T) > 0) or (Pos('"', T) > 0) or (Pos('m', LowerCase(T)) > 0) then
    Result := ParseLen(T, U, V)
  else
    Result := ParseLen(T + '"', usImperial, V);
end;

{ a bare number here is feet - a loop is 300', not 300" }
function FeetOf(const S: string; U: TUnitSystem; out V: Double): Boolean;
var
  T: string;
begin
  T := Trim(S);
  V := 0;
  if T = '' then Exit(False);
  if (Pos('''', T) > 0) or (Pos('"', T) > 0) or (Pos('m', LowerCase(T)) > 0) then
    Result := ParseLen(T, U, V)
  else
    Result := ParseLen(T + '''', usImperial, V);
end;

procedure TRadiantForm.FormCreate(Sender: TObject);
var
  S: TTubeSize;
begin
  for S := Low(TTubeSize) to High(TTubeSize) do cbTube.Items.Add(TUBE_NAMES[S]);
  cbTube.ItemIndex := Ord(tsHalf);
  FDragManifold := -1;
  FCoverage := -1; FEvenness := -1;
  Dress;
  FGoalCover := 97;
  FGoalEven := 10;
  LoadLast;
end;

{ The program's theme on everything; Build it is the loud button and the
  hints are dim (their Tags), the trouble red. }
procedure TRadiantForm.Dress;
begin
  hsDialogSkin.ThemeForm(Self);
  FZoneTabs := THsTabStrip.Create(pbZoneTabs, nil, []);
  FZoneTabs.OnChange := @tcZonesChange;
  lblProblem.Font.Color := $004040E0;
end;

{ Build it, Cancel: drawn buttons carry no modal result of their own }
procedure TRadiantForm.btnBuildClick(Sender: TObject);
begin
  if btnBuild.Enabled then ModalResult := mrOK;
end;

procedure TRadiantForm.btnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TRadiantForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and (FBusy = nil) then
  begin
    ModalResult := mrCancel;
    Key := 0;
  end;
end;

{ Every edit, combo and check box on the form, by name, under [radiant] in
  the settings, so the tube, spacing and goals come back as last left.
  The tag is left out: it names one job. }
procedure TRadiantForm.SaveLast;
var
  Ini: TIniFile;
  I: Integer;
  C: TComponent;
begin
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      for I := 0 to ComponentCount - 1 do
      begin
        C := Components[I];
        if (C = edTag) or (C = edZoneName) or (C = cbPinManifold) then Continue;
        if C is TBCTrackbarUpdown then Ini.WriteString('radiant', C.Name, IntToStr(TBCTrackbarUpdown(C).Value))
        else if C is TInkEdit then Ini.WriteString('radiant', C.Name, TInkEdit(C).Text)
        else if C is TBCComboBox then Ini.WriteInteger('radiant', C.Name, TBCComboBox(C).ItemIndex)
        else if C is TBGRAThemeCheckBox then Ini.WriteBool('radiant', C.Name, TBGRAThemeCheckBox(C).Checked);
      end;
      Ini.WriteInteger('radiant', 'GiveUp', FGiveUpIdx);
      Ini.WriteBool('radiant', 'LessFriendly', FLessFriendly);
      Ini.WriteBool('radiant', 'NoHooks', FNoHooks);
      Ini.WriteString('radiant', 'edGoalCover', FloatToStr(FGoalCover, DotFS));
      Ini.WriteString('radiant', 'edGoalEven', FloatToStr(FGoalEven, DotFS));
      Ini.WriteBool('radiant', 'cbHookPairs', FHookPairs);
    finally
      Ini.Free;
    end;
  except
    { a settings file that will not take it is no reason to stop }
  end;
end;

procedure TRadiantForm.LoadLast;
var
  Ini: TIniFile;
  I: Integer;
  C: TComponent;
begin
  FListing := True;
  try
    try
      Ini := TIniFile.Create(ConfigFile);
      try
        if not Ini.SectionExists('radiant') then Exit;
        FGiveUpIdx := Ini.ReadInteger('radiant', 'GiveUp', 0);
        FLessFriendly := Ini.ReadBool('radiant', 'LessFriendly', False);
        FNoHooks := Ini.ReadBool('radiant', 'NoHooks', False);
        FGoalCover := StrToFloatDef(Ini.ReadString('radiant', 'edGoalCover', ''), FGoalCover, DotFS);
        FGoalEven := StrToFloatDef(Ini.ReadString('radiant', 'edGoalEven', ''), FGoalEven, DotFS);
        FHookPairs := Ini.ReadBool('radiant', 'cbHookPairs', FHookPairs);
        for I := 0 to ComponentCount - 1 do
        begin
          C := Components[I];
          if (C = edTag) or (C = edZoneName) or (C = cbPinManifold) then Continue;
          if not Ini.ValueExists('radiant', C.Name) then Continue;
          { a spin edit's value may have been written as text, with a decimal }
          if C is TBCTrackbarUpdown then
            TBCTrackbarUpdown(C).Value := Round(StrToFloatDef(Ini.ReadString('radiant', C.Name, ''), TBCTrackbarUpdown(C).Value))
          else if C is TInkEdit then TInkEdit(C).Text := Ini.ReadString('radiant', C.Name, TInkEdit(C).Text)
          else if C is TBCComboBox then
            TBCComboBox(C).ItemIndex := EnsureRange(Ini.ReadInteger('radiant', C.Name, 0), 0, TBCComboBox(C).Items.Count - 1)
          else if C is TBGRAThemeCheckBox then TBGRAThemeCheckBox(C).Checked := Ini.ReadBool('radiant', C.Name, TBGRAThemeCheckBox(C).Checked);
        end;
      finally
        Ini.Free;
      end;
    except
    end;
  finally
    FListing := False;
  end;
end;

procedure TRadiantForm.FormShow(Sender: TObject);
begin
  { start with a manifold for each zone, on a wall, to be dragged from
    there and searched }
  if Length(FManifolds) = 0 then btnSuggestClick(nil)
  else Summarize;
end;

{ a search pumps messages for its bar, so the window could be closed out
  from under it: Stop first }
procedure TRadiantForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := FBusy = nil;
end;

function TRadiantForm.ReachNote(Z: Integer; const Spec: TRadiantSpec): string;
begin
  Result := '';
  if (Z < 0) or (Z > High(FZones)) then Exit;
  Result := RadiantReachText(RadiantFloorArea(FZones[Z].Outline, ZoneHoles(Z)), ZoneSpec(Z, Spec), True);
end;

function TRadiantForm.ZoneHoles(Z: Integer): TRadiantHoles;
var
  I, N: Integer;
begin
  N := Length(FZones[Z].Holes);
  SetLength(Result, N);
  for I := 0 to N - 1 do Result[I] := FZones[Z].Holes[I];
end;

function TRadiantForm.AnyLayout: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(FLayouts) do
    if (I <= High(FSearched)) and FSearched[I] and FLayouts[I].Ok then Exit(True);
end;

function TRadiantForm.Read(out Spec: TRadiantSpec): Boolean;
var
  I: Integer;
begin
  Spec := DefaultRadiantSpec;
  Spec.LessFriendly := FLessFriendly; Spec.NoHooks := FNoHooks;
  Spec.HookPairs := FHookPairs;
  Spec.Tube := TTubeSize(Max(0, cbTube.ItemIndex));
  Result := InchesOf(edSpacing.Text, FUnits, Spec.Spacing);
  if Trim(edMaxLoop.Text) = '' then Spec.MaxLoopFt := 0
  else Result := Result and FeetOf(edMaxLoop.Text, FUnits, Spec.MaxLoopFt);
  Result := Result and TryStrToFloat(Trim(edWaste.Text), Spec.WastePct);
  { the most loops a manifold takes; blank is twelve }
  if Trim(edMaxPorts.Text) = '' then Spec.MaxPorts := MANIFOLD_PORTS_MAX
  else Result := Result and TryStrToInt(Trim(edMaxPorts.Text), Spec.MaxPorts) and
    (Spec.MaxPorts >= MANIFOLD_PORTS_MIN) and (Spec.MaxPorts <= 64);
  { the slab is not asked about yet: concrete, default thickness, tube
    centered, R-15 under it }
  { obstacles come from the drawing, as the zones' holes }
  Spec.Extra := nil;
  Spec.Tag := Trim(edTag.Text);
  Spec.Labels := cbLabels.Checked;
  { the goals the search keeps going for; nought is no goal }
  Spec.GoalCoverPct := FGoalCover;
  Spec.GoalEvenPct := FGoalEven;
end;

{ What is known so far without searching: the ticket for each zone
  searched, a line for each one not, the gauges over the searched ones,
  and Build enabled only once every zone has a layout. }
procedure TRadiantForm.Summarize;
var
  Spec, ZS: TRadiantSpec;
  Z: Integer;
  Ticket: string;
  TotalFt, OrderFt, Worst, Lo, Hi, TotalArea, TotalUnfilled, Secs: Double;
  Loops, I, Waiting, Tried: Integer;
  HasEven: Boolean;
begin
  SetLength(FLayouts, Length(FZones));
  SetLength(FSearched, Length(FZones));
  if not Read(Spec) then
  begin
    lblProblem.Caption := 'A size did not read - 9, 9.5, or a foot mark.';
    FAllTicket := ''; FZoneTicket := nil;
    ListZones;
    FCoverage := -1; FEvenness := -1;
    btnBuild.Enabled := False;
    pbPlan.Invalidate; pbCoverage.Invalidate; pbEven.Invalidate;
    Exit;
  end;
  if Length(FZones) = 0 then
  begin
    lblProblem.Caption := 'Nothing is selected to fill - select the floor and run this again.';
    FAllTicket := ''; FZoneTicket := nil;
    ListZones;
    FCoverage := -1; FEvenness := -1;
    btnBuild.Enabled := False;
    pbPlan.Invalidate; pbCoverage.Invalidate; pbEven.Invalidate;
    Exit;
  end;
  lblProblem.Caption := '';
  Ticket := '';
  if Spec.Tag <> '' then Ticket := Spec.Tag + LineEnding + LineEnding;
  SetLength(FZoneTicket, Length(FZones));
  TotalFt := 0; OrderFt := 0; Loops := 0; TotalArea := 0; TotalUnfilled := 0; Waiting := 0;
  for Z := 0 to High(FZones) do
  begin
    ZS := ZoneSpec(Z, Spec);
    if lblProblem.Caption = '' then lblProblem.Caption := RadiantProblem(FZones[Z].Outline, ZS);
    Ticket := Ticket + '===== ' + UpperCase(ZoneTitle(Z)) + ' =====' + LineEnding;
    if not FSearched[Z] then
    begin
      Inc(Waiting);
      Ticket := Ticket + 'not searched yet' + LineEnding + LineEnding;
      FZoneTicket[Z] := 'not searched yet - Search this zone, or right-click its manifold';
      Continue;
    end;
    if not FLayouts[Z].Ok and (lblProblem.Caption = '') then
      lblProblem.Caption := Format('%s: %s', [ZoneTitle(Z), FLayouts[Z].Why]);
    { waste only changes the order, never the layout, so typing it after a
      search does not need another search }
    FLayouts[Z].OrderFt := FLayouts[Z].TotalFt * (1 + ZS.WastePct / 100);
    FZoneTicket[Z] := RadiantTicketText(ZS, FLayouts[Z], FUnits);
    { which of the layouts the search kept this is }
    if (Z <= High(FSolutions)) and (Length(FSolutions[Z]) > 1) then
      FZoneTicket[Z] := FZoneTicket[Z] + Format('layout %d of the %d the search kept', [FSolIdx[Z] + 1,
        Length(FSolutions[Z])]) + LineEnding;
    Ticket := Ticket + FZoneTicket[Z] + LineEnding;
    if FLayouts[Z].Ok then
    begin
      TotalFt := TotalFt + FLayouts[Z].TotalFt;
      OrderFt := OrderFt + FLayouts[Z].OrderFt;
      Loops := Loops + Length(FLayouts[Z].Loops);
      TotalArea := TotalArea + FLayouts[Z].AreaSqFt;
      TotalUnfilled := TotalUnfilled + FLayouts[Z].UnfilledSqFt;
    end;
  end;
  { the two gauges, over the zones searched: how much of the floor the
    layout reaches, and how close each zone's loops come in length }
  if TotalArea > 0 then FCoverage := Max(0, Min(1, 1 - TotalUnfilled / TotalArea))
  else FCoverage := -1;
  Worst := 0; HasEven := False; FEvenFt := 0;
  for Z := 0 to High(FLayouts) do
    if FSearched[Z] and FLayouts[Z].Ok and (Length(FLayouts[Z].Loops) > 0) then
    begin
      HasEven := True;
      if Length(FLayouts[Z].Loops) > 1 then
      begin
        Lo := 1E300; Hi := 0;
        for I := 0 to High(FLayouts[Z].Loops) do
        begin
          Lo := Min(Lo, FLayouts[Z].Loops[I].LenFt); Hi := Max(Hi, FLayouts[Z].Loops[I].LenFt);
        end;
        if (Hi > 0) and ((Hi - Lo) / Hi >= Worst) then
        begin
          Worst := (Hi - Lo) / Hi;
          FEvenFt := Hi - Lo;
        end;
      end;
    end;
  if HasEven then FEvenness := 1 - Worst else FEvenness := -1;
  if Length(FZones) > 1 then
  begin
    Ticket := Ticket + '===== ALL ZONES =====' + LineEnding +
      Format('%d of %d zones searched, %d loops', [Length(FZones) - Waiting, Length(FZones), Loops]) + LineEnding +
      'total tube, no waste: ' + FormatLen(TotalFt, FUnits) + LineEnding +
      'order: ' + FormatLen(OrderFt, FUnits) + LineEnding;
    { the effort, all told }
    Secs := 0; Tried := 0;
    for Z := 0 to High(FLayouts) do
      if FSearched[Z] then
      begin
        Secs := Secs + FLayouts[Z].SearchSecs;
        Tried := Tried + FLayouts[Z].Tries;
      end;
    if Tried > 0 then
      Ticket := Ticket + Format('searching: %d layouts tried in %s', [Tried, RadiantDuration(Secs)]) + LineEnding;
  end;
  if Waiting = Length(FZones) then
    lblNeed.Caption := Format('%d zone%s, none searched yet - place the manifolds, then Search',
      [Length(FZones), IfThen(Length(FZones) = 1, '', 's')])
  else if Waiting > 0 then
    lblNeed.Caption := Format('%d of %d zones searched, %d routed loops - right-click a manifold to search its zone',
      [Length(FZones) - Waiting, Length(FZones), Loops])
  else
    lblNeed.Caption := Format('%d zone%s, %d routed loops - manifold sizes follow the layout',
      [Length(FZones), IfThen(Length(FZones) = 1, '', 's'), Loops]);
  FAllTicket := Ticket;
  btnBuild.Enabled := (Waiting = 0) and AnyLayout and (lblProblem.Caption = '');
  ListZones;
  pbPlan.Invalidate; pbCoverage.Invalidate; pbEven.Invalidate;
end;

function TRadiantForm.ZoneSpec(Z: Integer; const Spec: TRadiantSpec): TRadiantSpec;
var
  ZF: TRadiantFrame;
  Ca, Sa: Double;
  Wv: TP3;
begin
  Result := Spec;
  SetLength(Result.Manifolds, 1); SetLength(Result.Ports, 1);
  Result.Manifolds[0] := FManifolds[Z]; Result.Ports[0] := FPorts[Z];
  Result.PinManifold := (Z <= High(FPins)) and FPins[Z];
  { the plan turns every zone in the first zone's frame; the layout and
    the build read the heading in the zone's own frame }
  SetLength(Result.ManifoldAngles, 1);
  Result.ManifoldAngles[0] := 0;
  if (Z <= High(FAngles)) and (Length(FZones[Z].Outline) >= 3) then
  begin
    ZF := RadiantFrameOf(FZones[Z].Outline);
    Ca := Cos(DegToRad(FAngles[Z])); Sa := Sin(DegToRad(FAngles[Z]));
    Wv := P3(FFrame.U.X * Ca + FFrame.V.X * Sa, FFrame.U.Y * Ca + FFrame.V.Y * Sa,
      FFrame.U.Z * Ca + FFrame.V.Z * Sa);
    Result.ManifoldAngles[0] := RadToDeg(ArcTan2(Dot3(Wv, ZF.V), Dot3(Wv, ZF.U)));
  end;
  Result.Tag := '';
end;

{ zone Z's wall nearest plan point M: how far, its heading in the plan's
  frame (0 up to 180), and whether it is part of a curve.  False when the
  zone has no walls. }
function TRadiantForm.NearestWall(Z: Integer; const M: T2; out D, Angle: Double; out Curved: Boolean): Boolean;
var
  I, J: Integer;
  A, B: T2;
  T, L, E: Double;
begin
  Result := False;
  D := 1E300; Angle := 0; Curved := False;
  if (Z < 0) or (Z > High(FZones)) then Exit;
  for I := 0 to High(FZones[Z].Outline) do
  begin
    J := (I + 1) mod Length(FZones[Z].Outline);
    A := RadiantTo2(FFrame, FZones[Z].Outline[I]);
    B := RadiantTo2(FFrame, FZones[Z].Outline[J]);
    L := Sqr(B.X - A.X) + Sqr(B.Y - A.Y);
    if L < 1E-12 then Continue;
    T := Max(0, Min(1, ((M.X - A.X) * (B.X - A.X) + (M.Y - A.Y) * (B.Y - A.Y)) / L));
    E := Hypot(M.X - A.X - T * (B.X - A.X), M.Y - A.Y - T * (B.Y - A.Y));
    if E < D then
    begin
      D := E; Result := True;
      Angle := RadToDeg(ArcTan2(B.Y - A.Y, B.X - A.X));
      Curved := RadiantEdgeCurved(FZones[Z].Outline, I);
    end;
  end;
  { a heading, not a direction }
  while Angle < 0 do Angle := Angle + 180;
  while Angle >= 180 do Angle := Angle - 180;
end;

{ the heading of zone Z's wall nearest its manifold, in the plan's frame -
  a manifold hangs long side along a wall }
function TRadiantForm.WallAngle(Z: Integer): Double;
var
  D: Double;
  Curved: Boolean;
begin
  Result := 0;
  if (Z < 0) or (Z > High(FManifolds)) then Exit;
  if not NearestWall(Z, RadiantTo2(FFrame, FManifolds[Z]), D, Result, Curved) then Exit;
  { a piece of a curve is no wall to square to - its chord runs at any
    angle - so square to the sheet, whichever way is nearer }
  if Curved then Result := 90 * Round(Result / 90);
  if Result >= 180 then Result := Result - 180;
end;

{ zone Z's manifold as its box (18 by 6 inches, turned to its heading),
  never smaller on the plan than a pointer can grab.  Kept small even so:
  manifolds are suggested a couple of feet apart at the zones' common
  corner, and bigger boxes hid one another. }
function TRadiantForm.ManifoldBox(Z: Integer): T2Array;
var
  Spec: TRadiantSpec;
  C: T2;
  W, H, Ca, Sa: Double;
  K: Integer;
const
  SX: array[0..3] of Integer = (-1, 1, 1, -1);
  SY: array[0..3] of Integer = (-1, -1, 1, 1);
begin
  SetLength(Result, 4);
  C := RadiantTo2(FFrame, FManifolds[Z]);
  Spec := DefaultRadiantSpec;
  W := Spec.ManifoldW; H := Spec.ManifoldH;
  if FSc > 0 then
  begin
    W := Max(W, 14 / FSc); H := Max(H, 7 / FSc);
  end;
  Ca := Cos(DegToRad(FAngles[Z])); Sa := Sin(DegToRad(FAngles[Z]));
  for K := 0 to 3 do
    Result[K] := Point2(C.X + SX[K] * W / 2 * Ca - SY[K] * H / 2 * Sa,
      C.Y + SX[K] * W / 2 * Sa + SY[K] * H / 2 * Ca);
end;

{ the manifold whose box is under the pixel (the nearest where boxes
  crowd together), or -1 }
function TRadiantForm.ManifoldAt(X, Y: Integer): Integer;
var
  Z: Integer;
  M, C: T2;
  U, V, W, H, Ca, Sa, Slack, D, Best: Double;
  Spec: TRadiantSpec;
begin
  Result := -1;
  if FSc <= 0 then Exit;
  M := Point2(PlanU(X), PlanV(Y));
  Spec := DefaultRadiantSpec;
  Slack := 4 / FSc;
  Best := 1E300;
  for Z := 0 to High(FManifolds) do
  begin
    C := RadiantTo2(FFrame, FManifolds[Z]);
    W := Max(Spec.ManifoldW, 14 / FSc); H := Max(Spec.ManifoldH, 7 / FSc);
    Ca := Cos(DegToRad(FAngles[Z])); Sa := Sin(DegToRad(FAngles[Z]));
    { into the box's own axes }
    U := (M.X - C.X) * Ca + (M.Y - C.Y) * Sa;
    V := -(M.X - C.X) * Sa + (M.Y - C.Y) * Ca;
    if (Abs(U) > W / 2 + Slack) or (Abs(V) > H / 2 + Slack) then Continue;
    D := Sqr(M.X - C.X) + Sqr(M.Y - C.Y);
    if D < Best then begin Best := D; Result := Z; end;
  end;
end;

procedure TRadiantForm.miRotateClick(Sender: TObject);
var
  Z: Integer;
begin
  Z := SelectedZone;
  if (Z < 0) or (Z > High(FAngles)) then Exit;
  FAngles[Z] := FAngles[Z] + 90;
  if FAngles[Z] >= 180 then FAngles[Z] := FAngles[Z] - 180;
  ClearZone(Z);
  Summarize;
end;

{ Set the manifold square to the sheet or on a diagonal.  On a round zone
  it otherwise hangs on a chord at whatever angle that runs.  The menu
  item's Tag is the heading in the drawing's plan: 0 is the long side
  east - west. }
procedure TRadiantForm.miFaceClick(Sender: TObject);
var
  Z: Integer;
begin
  Z := SelectedZone;
  if (Z < 0) or (Z > High(FAngles)) or not (Sender is TMenuItem) then Exit;
  FAngles[Z] := TMenuItem(Sender).Tag;
  ClearZone(Z);
  Summarize;
end;

procedure TRadiantForm.ClearZone(Z: Integer);
begin
  if (Z < 0) or (Z > High(FZones)) then Exit;
  SetLength(FLayouts, Length(FZones));
  SetLength(FSearched, Length(FZones));
  FLayouts[Z] := Default(TRadiantResult);
  FSearched[Z] := False;
  SetLength(FSolutions, Length(FZones)); SetLength(FSolIdx, Length(FZones));
  FSolutions[Z] := nil; FSolIdx[Z] := 0;
end;

procedure TRadiantForm.ClearAll;
var
  Z: Integer;
begin
  for Z := 0 to High(FZones) do ClearZone(Z);
end;

{ the zone whose tab is up; -1 on the All zones tab }
function TRadiantForm.SelectedZone: Integer;
begin
  Result := FZoneTabs.TabIndex;
  if (Result < 0) or (Result > High(FZones)) then Result := -1;
end;

procedure TRadiantForm.SelectZone(Z: Integer);
begin
  if (Z < 0) or (Z > High(FZones)) or (Z >= FZoneTabs.Tabs.Count) then Exit;
  if FZoneTabs.TabIndex <> Z then FZoneTabs.TabIndex := Z;
  ShowZonePanel;
  pbPlan.Invalidate;
end;

procedure TRadiantForm.tcZonesChange(Sender: TObject);
begin
  ShowZonePanel;
  pbPlan.Invalidate;
end;

{ a zone's tab title: its number, and its name if it has one }
function TRadiantForm.ZoneTitle(Z: Integer): string;
begin
  Result := Format('Zone %d', [Z + 1]);
  if (Z >= 0) and (Z <= High(FZoneNames)) and (FZoneNames[Z] <> '') then Result := Result + ' - ' + FZoneNames[Z];
end;

{ zone Z's corners (every zone's with -1, for the job) to a hundredth,
  hashed }
function TRadiantForm.NameKey(Z: Integer): string;
var
  S: string;
  I, K: Integer;
  H: Cardinal;
begin
  S := '';
  for K := 0 to High(FZones) do
    if (Z < 0) or (K = Z) then
      for I := 0 to High(FZones[K].Outline) do
        S := S + Format('%.2f,%.2f,%.2f;', [FZones[K].Outline[I].X, FZones[K].Outline[I].Y, FZones[K].Outline[I].Z],
          DefaultFormatSettings);
  { FNV-1a }
  H := 2166136261;
  for I := 1 to Length(S) do H := Cardinal((QWord(H xor Ord(S[I])) * 16777619) and $FFFFFFFF);
  Result := IfThen(Z < 0, 'job-', 'zone-') + IntToHex(H, 8);
end;

{ the names the floor was given last time }
procedure TRadiantForm.LoadNames;
var
  Ini: TIniFile;
  Z: Integer;
begin
  SetLength(FZoneNames, Length(FZones));
  SetLength(FPins, Length(FZones));
  for Z := 0 to High(FZoneNames) do
  begin
    FZoneNames[Z] := '';
    FPins[Z] := False;
  end;
  if Length(FZones) = 0 then Exit;
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      for Z := 0 to High(FZones) do
      begin
        FZoneNames[Z] := Ini.ReadString('radiant-names', NameKey(Z), '');
        FPins[Z] := Ini.ReadBool('radiant-pins', NameKey(Z), False);
      end;
      FHeat := HeatJobFromText(Ini.ReadString('radiant-heat', NameKey(-1), ''));
      SetLength(FHeat.Zones, Length(FZones));
      for Z := 0 to High(FZones) do
        FHeat.Zones[Z] := HeatZoneFromText(Ini.ReadString('radiant-heat', NameKey(Z), ''));
      if Trim(edTag.Text) = '' then
      begin
        FListing := True;
        try
          edTag.Text := Ini.ReadString('radiant-names', NameKey(-1), '');
        finally
          FListing := False;
        end;
      end;
    finally
      Ini.Free;
    end;
  except
  end;
  ShowHeat;
end;

procedure TRadiantForm.SaveNames;
var
  Ini: TIniFile;
  Z: Integer;
begin
  if Length(FZones) = 0 then Exit;
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      for Z := 0 to High(FZoneNames) do
        if FZoneNames[Z] <> '' then Ini.WriteString('radiant-names', NameKey(Z), FZoneNames[Z])
        else Ini.DeleteKey('radiant-names', NameKey(Z));
      for Z := 0 to High(FPins) do
        if FPins[Z] then Ini.WriteBool('radiant-pins', NameKey(Z), True)
        else Ini.DeleteKey('radiant-pins', NameKey(Z));
      Ini.WriteString('radiant-heat', NameKey(-1), HeatJobToText(FHeat));
      for Z := 0 to Min(High(FHeat.Zones), High(FZones)) do
        Ini.WriteString('radiant-heat', NameKey(Z), HeatZoneToText(FHeat.Zones[Z]));
      if Trim(edTag.Text) <> '' then Ini.WriteString('radiant-names', NameKey(-1), Trim(edTag.Text))
      else Ini.DeleteKey('radiant-names', NameKey(-1));
    finally
      Ini.Free;
    end;
  except
  end;
end;

{ a zone named: its tab, its plan, its ticket and the submittal say so }
procedure TRadiantForm.edZoneNameChange(Sender: TObject);
var
  Z: Integer;
begin
  if FListing then Exit;
  Z := SelectedZone;
  if (Z < 0) or (Z > High(FZoneNames)) then Exit;
  FZoneNames[Z] := Trim(edZoneName.Text);
  if Z < FZoneTabs.Tabs.Count then FZoneTabs.Tabs[Z] := ZoneTitle(Z);
  SaveNames;
  Summarize;
end;

{ pinned, the manifold stays where it was put; unpinned, the next search
  may slide it along its wall }
procedure TRadiantForm.cbPinManifoldChange(Sender: TObject);
var
  Z: Integer;
begin
  if FListing then Exit;
  Z := SelectedZone;
  if (Z < 0) or (Z > High(FPins)) then Exit;
  FPins[Z] := cbPinManifold.Checked;
  SaveNames;
end;

{ A check box's words are a separate label, because Windows draws a check
  box's own caption dark on this dark panel.  A click on the label ticks
  the box. }
procedure TRadiantForm.CheckLabelClick(Sender: TObject);
begin
  if (Sender is TLabel) and (TLabel(Sender).FocusControl is TBGRAThemeCheckBox) and TLabel(Sender).FocusControl.Enabled then
    with TBGRAThemeCheckBox(TLabel(Sender).FocusControl) do Checked := not Checked;
end;

{ the heat load: its own dialog; once used it goes in the submittal }
procedure TRadiantForm.btnHeatClick(Sender: TObject);
var
  Spec: TRadiantSpec;
  Specs: array of TRadiantSpec;
  Titles: TStringArray;
  Z: Integer;
begin
  if Length(FZones) = 0 then Exit;
  if Length(FZoneNames) <> Length(FZones) then LoadNames;
  if not Read(Spec) then Spec := DefaultRadiantSpec;
  SetLength(Specs, Length(FZones)); SetLength(Titles, Length(FZones));
  for Z := 0 to High(FZones) do
  begin
    Specs[Z] := ZoneSpec(Z, Spec);
    Titles[Z] := ZoneTitle(Z);
  end;
  if TRadiantHeatForm.Edit(FUnits, FZones, Titles, FLayouts, Specs, FHeat) then SaveNames;
  ShowHeat;
end;

{ the button says whether the submittal will carry a heat load }
procedure TRadiantForm.ShowHeat;
begin
  if FHeat.Enabled then btnHeat.Caption := 'Heat load - in'
  else btnHeat.Caption := 'Heat load...';
end;

procedure TRadiantForm.ListZones;
var
  Z, Was, N: Integer;
begin
  Was := FZoneTabs.TabIndex;
  if Length(FZoneNames) <> Length(FZones) then LoadNames;
  N := Length(FZones);
  if N > 1 then Inc(N);
  if FZoneTabs.Tabs.Count <> N then
  begin
    FZoneTabs.Tabs.BeginUpdate;
    try
      FZoneTabs.Tabs.Clear;
      for Z := 0 to High(FZones) do FZoneTabs.Tabs.Add(ZoneTitle(Z));
      if Length(FZones) > 1 then FZoneTabs.Tabs.Add('All zones');
    finally
      FZoneTabs.Tabs.EndUpdate;
    end;
  end;
  if (Was >= 0) and (Was < FZoneTabs.Tabs.Count) then FZoneTabs.TabIndex := Was
  else if FZoneTabs.Tabs.Count > 0 then FZoneTabs.TabIndex := 0;
  ShowZonePanel;
end;

{ The panel under the tabs: the zone's manifold and how its search went,
  the layouts it kept (click one to use it), and its material list.  On
  All zones, the whole list. }
procedure TRadiantForm.ShowZonePanel;
var
  Z, I: Integer;
  P: T2;
  S: string;
  Spec: TRadiantSpec;
begin
  Z := SelectedZone;
  FListing := True;
  try
    lbSolutions.Items.BeginUpdate;
    try
      lbSolutions.Items.Clear;
      if (Z >= 0) and (Z <= High(FSolutions)) then
        for I := 0 to High(FSolutions[Z]) do lbSolutions.Items.Add(ShortLine(FSolutions[Z][I]));
    finally
      lbSolutions.Items.EndUpdate;
    end;
    if (Z >= 0) and (Z <= High(FSolIdx)) and (FSolIdx[Z] < lbSolutions.Items.Count) then
      lbSolutions.ItemIndex := FSolIdx[Z];
  finally
    FListing := False;
  end;
  FListing := True;
  try
    if (Z >= 0) and (Z <= High(FZoneNames)) then edZoneName.Text := FZoneNames[Z] else edZoneName.Text := '';
    cbPinManifold.Checked := (Z >= 0) and (Z <= High(FPins)) and FPins[Z];
  finally
    FListing := False;
  end;
  edZoneName.Enabled := Z >= 0;
  lblZoneName.Enabled := Z >= 0;
  cbPinManifold.Enabled := Z >= 0;
  lblPinManifold.Enabled := Z >= 0;
  btnNotZone.Enabled := (Z >= 0) and (FBusy = nil) and (Length(FZones) > 1);
  btnZoneSearch.Enabled := (Z >= 0) and (FBusy = nil);
  btnZoneClear.Enabled := (Z >= 0) and (Z <= High(FSearched)) and FSearched[Z];
  lbSolutions.Enabled := Z >= 0;
  lblFoundHead.Enabled := Z >= 0;
  if Z < 0 then
  begin
    lblZoneHead.Caption := Format('Every zone: %d of them.  Pick a zone''s tab, or click it on the plan, to work on it.',
      [Length(FZones)]);
    memTicket.Lines.Text := InkReport(FAllTicket);
    Exit;
  end;
  if Length(FOutline) >= 3 then FFrame := RadiantPlanFrame(FOutline);
  S := '';
  if Z <= High(FManifolds) then
  begin
    P := RadiantTo2(FFrame, FManifolds[Z]);
    S := Format('Manifold at %s along, %s in', [FormatLen(P.X, FUnits), FormatLen(P.Y, FUnits)]);
    if Z <= High(FAngles) then S := S + Format(', long side at %s degrees', [FormatFloat('0', FAngles[Z])]);
  end;
  if (Z > High(FSearched)) or not FSearched[Z] then
  begin
    S := S + ' - not searched yet.';
    { warn before searching when the coverage goal cannot be reached with
      this tube, or the floor needs more loops than one manifold takes -
      one manifold to a zone, so the zone must be split }
    if Read(Spec) and (ReachNote(Z, Spec) <> '') then S := S + '  ' + ReachNote(Z, Spec)
    else if Read(Spec) and (RadiantLoopsNeeded(FZones[Z].Outline, ZoneHoles(Z), Spec) > RadiantMaxPorts(Spec)) then
      S := S + Format('  About %d loops wanted - more than the %d a manifold is set to take: split the zone in two.',
        [RadiantLoopsNeeded(FZones[Z].Outline, ZoneHoles(Z), Spec), RadiantMaxPorts(Spec)]);
  end
  else if FLayouts[Z].Ok then
  begin
    if Length(FLayouts[Z].Manifolds) > 0 then S := S + Format(' - a %d-loop manifold.', [FLayouts[Z].Manifolds[0].Ports]);
    if Read(Spec) and (RadiantOverPorts(FLayouts[Z], Spec) > 0) then
      S := S + Format('  More loops than the %d a manifold is set to take - split the zone in two.',
        [RadiantMaxPorts(Spec)])
    else if Read(Spec) and (ReachNote(Z, Spec) <> '') then S := S + '  ' + ReachNote(Z, Spec);
    S := S + Format('  Searched %d layouts in %s.', [FLayouts[Z].Tries, RadiantDuration(FLayouts[Z].SearchSecs)]);
    if FLayouts[Z].Friendly >= 0 then
      S := S + Format('  Installer friendly %s/100.', [FormatFloat('0', FLayouts[Z].Friendly)]);
  end
  else S := S + ' - no layout.';
  lblZoneHead.Caption := S;
  if Z <= High(FZoneTicket) then memTicket.Lines.Text := InkReport(FZoneTicket[Z]) else memTicket.Lines.Text := '';
end;

procedure TRadiantForm.lbSolutionsClick(Sender: TObject);
var
  Z: Integer;
begin
  if FListing then Exit;
  Z := SelectedZone;
  if (Z >= 0) and (lbSolutions.ItemIndex >= 0) then ShowSolution(Z, lbSolutions.ItemIndex);
end;

{ Search the zones in Which, one after another, under the busy window.
  Everything else is disabled while it runs, so nothing can be dragged or
  typed into a half-worked layout.  A zone stopped part way keeps the best
  it had, and its record says so. }
procedure TRadiantForm.Search(const Which: array of Integer);
var
  K: Integer;
begin
  if FBusy <> nil then Exit;
  if not Read(FWorkSpec) or (Length(FZones) = 0) or (Length(Which) = 0) then begin Summarize; Exit; end;
  SetLength(FLayouts, Length(FZones));
  SetLength(FSearched, Length(FZones));
  SetLength(FWorkZones, Length(Which));
  for K := 0 to High(Which) do FWorkZones[K] := Which[K];
  SaveLast;
  { the search runs inside the busy window, shown modal over this one -
    see hsRadiantBusy for why it cannot be the other way round }
  FBusy := TRadiantBusyForm.CreateBusy(Self);
  try
    FBusy.OnWork := @SearchWork;
    FBusy.OnPreview := @SearchPreview;
    FWorkSpec.LessFriendly := FLessFriendly; FWorkSpec.NoHooks := FNoHooks;
    FLiveGoals.CoverPct := FWorkSpec.GoalCoverPct;
    FLiveGoals.EvenPct := FWorkSpec.GoalEvenPct;
    FLiveGoals.LessFriendly := FLessFriendly; FLiveGoals.NoHooks := FNoHooks;
    FBusy.SetGoals(FLiveGoals.CoverPct, FLiveGoals.EvenPct);
    FBusy.cbGiveUp.ItemIndex := EnsureRange(FGiveUpIdx, 0, FBusy.cbGiveUp.Items.Count - 1);
    FBusy.cbBusyLess.Checked := FLessFriendly;
    FBusy.cbBusyHooks.Checked := not FNoHooks;
    FBusy.cbBusyPairs.Checked := FHookPairs;
    FLastSearched := -1;
    FBusy.ShowModal;
    { a layout picked from the list after the search finished is the one kept }
    PickFromBusy;
    { goals changed while it searched are the goals now }
    FGiveUpIdx := FBusy.cbGiveUp.ItemIndex;
    FLessFriendly := FBusy.cbBusyLess.Checked;
    FNoHooks := not FBusy.cbBusyHooks.Checked;
    FListing := True;
    try
      FGoalCover := FLiveGoals.CoverPct;
      FGoalEven := FLiveGoals.EvenPct;
      FHookPairs := FBusy.cbBusyPairs.Checked;
    finally
      FListing := False;
    end;
    SaveLast;
  finally
    FreeAndNil(FBusy);
  end;
  Summarize;
end;

procedure TRadiantForm.PickFromBusy;
var
  I, Z: Integer;
begin
  Z := FLastSearched;
  if (FBusy = nil) or (FBusy.Picked = '') or (Z < 0) or (Z > High(FSolutions)) then Exit;
  for I := 0 to High(FSolutions[Z]) do
    if FoundLine(FSolutions[Z][I]) = FBusy.Picked then
    begin
      if I <> FSolIdx[Z] then ShowSolution(Z, I);
      Exit;
    end;
end;

{ search the zones asked for, one after another, under the busy window }
procedure TRadiantForm.SearchWork(Sender: TObject);
var
  K, Z, I, Met, Searched: Integer;
  Lines: array of string;
  R: TRadiantResult;
  Picked: string;
  Began: TDateTime;
  Extra: TStringArray;
begin
  FBusyCount := Length(FWorkZones);
  Met := 0;
  Searched := 0;
  for K := 0 to High(FWorkZones) do
  begin
    Z := FWorkZones[K];
    if (Z < 0) or (Z > High(FZones)) then Continue;
    FBusyIndex := K;
    FWorkSpec.HookPairs := FBusy.cbBusyPairs.Checked;
    ClearZone(Z);
    FBusy.Stage(ZoneTitle(Z) + IfThen(FBusyCount > 1, Format(' (%d of %d)', [K + 1, FBusyCount]), ''),
      'Starting the search...',
      Round(100 * K / FBusyCount));
    FLiveFound := nil;
    FZoneStart := GetTickCount64;
    FShownAt := 0;
    FRateAt := GetTickCount64; FRateLaid := 0; FRate := -1;
    FLiveGoals.Laid := 0;
    FStopWhy := '';
    Began := Now;
    R := ComputeRadiantLayout(FZones[Z].Outline, ZoneHoles(Z), ZoneSpec(Z, FWorkSpec),
      False, @SearchProgress, @FLiveFound, @FLiveGoals);
    SetLength(FSolutions, Length(FZones)); SetLength(FSolIdx, Length(FZones));
    FSolutions[Z] := FLiveFound; FSolIdx[Z] := 0;
    FLiveFound := nil;
    { the search returns its best, which is the first one kept }
    if Length(FSolutions[Z]) > 0 then FSolutions[Z][0] := R
    else begin SetLength(FSolutions[Z], 1); FSolutions[Z][0] := R; end;
    { every solution's record: when, and why it ended if it was stopped }
    Extra := nil;
    SetLength(Extra, 1);
    Extra[0] := 'searched ' + FormatDateTime('yyyy-mm-dd hh:nn', Began);
    if FStopWhy <> '' then
    begin
      SetLength(Extra, 2);
      Extra[1] := FStopWhy;
    end;
    { one picked from the busy window's list is the one shown }
    Picked := FBusy.Picked;
    if Picked <> '' then
      for I := 0 to High(FSolutions[Z]) do
        if FoundLine(FSolutions[Z][I]) = Picked then
        begin
          FSolIdx[Z] := I;
          SetLength(Extra, Length(Extra) + 1);
          Extra[High(Extra)] := Format('layout %d of %d picked by hand in the search window', [I + 1, Length(FSolutions[Z])]);
          Break;
        end;
    for I := 0 to High(FSolutions[Z]) do
      FSolutions[Z][I].SearchLog := Concat(Extra, FSolutions[Z][I].SearchLog);
    { the window's list becomes what was kept, so a pick made after the
      search is one that can still be had }
    SetLength(Lines, Length(FSolutions[Z]));
    for I := 0 to High(FSolutions[Z]) do Lines[I] := FoundLine(FSolutions[Z][I]);
    FBusy.ShowFound(Lines);
    R := FSolutions[Z][FSolIdx[Z]];
    { a stopped search hands back the best it had; the ticket says if it
      fell short of the goals }
    FLayouts[Z] := R;
    FSearched[Z] := True;
    if R.Ok and (Length(R.Manifolds) > 0) then
    begin
      FPorts[Z] := R.Manifolds[0].Ports;
      { the search may have slid it along its wall; the plan shows it
        where the layout was laid from }
      FManifolds[Z] := R.Manifolds[0].At;
    end;
    { each zone shows as it finishes, its tab up; one that met the goals gets
      its check before the next starts }
    Summarize;
    SelectZone(Z);
    Inc(Searched);
    FLastSearched := Z;
    if (FStopWhy = '') and RadiantMeetsGoals(R, FWorkSpec) then
    begin
      Inc(Met);
      FBusy.ZoneMet(ZoneTitle(Z));
    end;
    { Stop kept this zone's best; Stop all, and there is no next zone.  The
      last zone's list stays up to look at. }
    if FBusy.StoppingAll or (K = High(FWorkZones)) then Break;
    FBusy.NextZone;
  end;
  FBusy.AllMet := (Searched > 0) and (Met = Searched);
  if Searched = 1 then
    FBusy.lblDetail.Caption := IfThen(Met = 1, 'It meets the goals.',
      'It falls short of the goals - the best it found is kept.')
  else if Met = Searched then
    FBusy.lblDetail.Caption := Format('All %d zones meet the goals.', [Searched])
  else
    FBusy.lblDetail.Caption := Format('%d of %d zones meet the goals; the others keep the best they found.',
      [Met, Searched]);
end;

{ The fixed restarts first, as a fraction; then, with the goals not met,
  random layouts until the goals are met or Stop, the bar showing the best
  coverage so far. }
procedure TRadiantForm.SearchProgress(Done, Total: Integer; const Best: TRadiantResult; var Stop: Boolean);
var
  Cover, Spread: Double;
  Now_, Speed: string;
  Laid: Integer;
  Lines: array of string;
  I: Integer;
begin
  if FBusy = nil then Exit;
  { Update the window a few times a second, not every layout: the threaded
    search weighs a batch at once, and redrawing for each one kept the
    workers waiting.  Stop and the give-up time are checked every time. }
  if GetTickCount64 - FShownAt < SEARCH_SHOW_MS then
  begin
    Stop := FBusy.Stopping;
    if Stop and (FStopWhy = '') then FStopWhy := Format('stopped by hand at layout %d', [Done]);
    if not Stop and (FBusy.GiveUpSecs > 0) and (GetTickCount64 - FZoneStart > QWord(FBusy.GiveUpSecs) * 1000) then
    begin
      Stop := True;
      FStopWhy := Format('gave up after %s, at layout %d', [RadiantDuration(FBusy.GiveUpSecs), Done]);
    end;
    Exit;
  end;
  FShownAt := GetTickCount64;
  { layouts laid so far, and the rate over the last couple of seconds }
  Laid := Max(Done, FLiveGoals.Laid);
  if FShownAt - FRateAt >= SEARCH_RATE_MS then
  begin
    FRate := (Laid - FRateLaid) * 1000 / (FShownAt - FRateAt);
    FRateAt := FShownAt; FRateLaid := Laid;
  end;
  if FRate >= 0 then Speed := Format(' - %s a second', [FormatFloat('0', FRate)]) else Speed := '';
  { the goals as typed in the busy window now; the search reads them back }
  FBusy.ReadGoals(FLiveGoals.CoverPct, FLiveGoals.EvenPct);
  FLiveGoals.LessFriendly := FBusy.cbBusyLess.Checked;
  FLiveGoals.NoHooks := not FBusy.cbBusyHooks.Checked;
  FWorkSpec.GoalCoverPct := FLiveGoals.CoverPct;
  FWorkSpec.GoalEvenPct := FLiveGoals.EvenPct;
  FWorkSpec.LessFriendly := FLiveGoals.LessFriendly;
  FWorkSpec.NoHooks := FLiveGoals.NoHooks;
  { the layouts kept so far, best first, to pick from - set before the
    stage line, which paints the window }
  SetLength(Lines, Length(FLiveFound));
  for I := 0 to High(FLiveFound) do Lines[I] := FoundLine(FLiveFound[I]);
  FBusy.ShowFound(Lines);
  RadiantMeasure(Best, Cover, Spread);
  if Best.Ok then
    Now_ := Format('best so far: %s%% covered, loops within %s%% (%s ft), %d loops',
      [FormatFloat('0.0', Cover * 100), FormatFloat('0', Spread * 100), FormatFloat('0', RadiantSpreadFt(Best)),
       Length(Best.Loops)])
  else Now_ := 'no layout yet';
  if Total > 0 then
    FBusy.Stage(FBusy.lblStage.Caption,
      Format('Restart %d of %d%s - %s', [Done, Total, Speed, Now_]),
      Round(100 * (FBusyIndex + Done / Total) / Max(1, FBusyCount)))
  else
    FBusy.Stage(FBusy.lblStage.Caption,
      Format('Still after the goals - %d layouts laid%s.  %s.  Stop keeps it.', [Laid, Speed, Now_]),
      Round(100 * Cover));
  Stop := FBusy.Stopping;
  if Stop and (FStopWhy = '') then FStopWhy := Format('stopped by hand at layout %d', [Done]);
  if not Stop and (FBusy.GiveUpSecs > 0) and (GetTickCount64 - FZoneStart > QWord(FBusy.GiveUpSecs) * 1000) then
  begin
    Stop := True;
    FStopWhy := Format('gave up after %s, at layout %d', [RadiantDuration(FBusy.GiveUpSecs), Done]);
  end;
end;

{ The zone being searched, with one of its kept layouts (the one Picked in
  the busy window's list, or the best so far), fitted into the preview. }
procedure TRadiantForm.SearchPreview(C: TCanvas; W, H: Integer; const Picked: string);
const
  SX: array[0..3] of Integer = (-1, 1, 1, -1);
  SY: array[0..3] of Integer = (-1, -1, 1, 1);
  MARGIN = 14;
var
  Z, I, J, K: Integer;
  R: TRadiantResult;
  Got: Boolean;
  F: TRadiantFrame;
  P: T2;
  MinX, MinY, MaxX, MaxY, Sc, OX, OY, BW, BH, Ca, Sa: Double;
  Pts: array of TPoint;
  Spec: TRadiantSpec;

  function PX(U: Double): Integer;
  begin
    Result := Round(OX + (U - MinX) * Sc);
  end;

  function PY(V: Double): Integer;
  begin
    Result := Round(OY + (MaxY - V) * Sc);
  end;

  procedure Ring(const Src: TP3Array; Fill: TColor);
  var
    K2: Integer;
    Q: T2;
  begin
    SetLength(Pts, Length(Src));
    for K2 := 0 to High(Src) do
    begin
      Q := RadiantTo2(F, Src[K2]);
      Pts[K2] := Point(PX(Q.X), PY(Q.Y));
    end;
    if Fill = clNone then C.Brush.Style := bsClear
    else begin C.Brush.Style := bsSolid; C.Brush.Color := Fill; end;
    C.Polygon(Pts);
  end;

begin
  if (FBusy = nil) or (FBusyIndex < 0) or (FBusyIndex > High(FWorkZones)) then Exit;
  Z := FWorkZones[FBusyIndex];
  if (Z < 0) or (Z > High(FZones)) or (Length(FOutline) < 3) then Exit;
  Got := False;
  if Picked <> '' then
    for I := 0 to High(FLiveFound) do
      if FoundLine(FLiveFound[I]) = Picked then
      begin
        R := FLiveFound[I]; Got := True;
        Break;
      end;
  if not Got and (Length(FLiveFound) > 0) then begin R := FLiveFound[0]; Got := True; end;
  { the search done, the zone's kept layouts are where the list came from }
  if not Got and (Z <= High(FSolutions)) then
  begin
    for I := 0 to High(FSolutions[Z]) do
      if (Picked = '') or (FoundLine(FSolutions[Z][I]) = Picked) then
      begin
        R := FSolutions[Z][I]; Got := True;
        Break;
      end;
  end;
  { the drawing's own plan, the zone fitted to the box }
  F := RadiantPlanFrame(FOutline);
  MinX := 1E300; MinY := 1E300; MaxX := -1E300; MaxY := -1E300;
  for I := 0 to High(FZones[Z].Outline) do
  begin
    P := RadiantTo2(F, FZones[Z].Outline[I]);
    MinX := Min(MinX, P.X); MaxX := Max(MaxX, P.X);
    MinY := Min(MinY, P.Y); MaxY := Max(MaxY, P.Y);
  end;
  Sc := Min((W - 2 * MARGIN) / Max(MaxX - MinX, 1E-6), (H - 2 * MARGIN) / Max(MaxY - MinY, 1E-6));
  OX := (W - (MaxX - MinX) * Sc) / 2;
  OY := (H - (MaxY - MinY) * Sc) / 2;
  C.Pen.Width := 2; C.Pen.Color := clBlack;
  Ring(FZones[Z].Outline, clNone);
  C.Pen.Width := 1;
  for I := 0 to High(FZones[Z].Holes) do Ring(FZones[Z].Holes[I], $00D0D0D0);
  if not Got then Exit;
  for I := 0 to High(R.Loops) do
  begin
    C.Pen.Color := LoopInk(Z, I);
    C.Pen.Width := 1;
    for J := 1 to High(R.Loops[I].Pts) do
    begin
      P := RadiantTo2(F, R.Loops[I].Pts[J - 1]);
      C.MoveTo(PX(P.X), PY(P.Y));
      P := RadiantTo2(F, R.Loops[I].Pts[J]);
      C.LineTo(PX(P.X), PY(P.Y));
    end;
  end;
  { the manifold where this layout has it, the way it hangs }
  if Length(R.Manifolds) > 0 then
  begin
    P := RadiantTo2(F, R.Manifolds[0].At);
    Spec := DefaultRadiantSpec;
    BW := Max(Spec.ManifoldW, 10 / Sc); BH := Max(Spec.ManifoldH, 5 / Sc);
    if Z <= High(FAngles) then
    begin
      Ca := Cos(DegToRad(FAngles[Z])); Sa := Sin(DegToRad(FAngles[Z]));
    end
    else begin Ca := 1; Sa := 0; end;
    SetLength(Pts, 4);
    for K := 0 to 3 do
      Pts[K] := Point(PX(P.X + SX[K] * BW / 2 * Ca - SY[K] * BH / 2 * Sa),
        PY(P.Y + SX[K] * BW / 2 * Sa + SY[K] * BH / 2 * Ca));
    C.Pen.Color := ZoneInk(Z); C.Pen.Width := 2;
    C.Brush.Style := bsSolid; C.Brush.Color := clYellow;
    C.Polygon(Pts);
    C.Pen.Width := 1;
  end;
end;

{ how friendly to lay, 0..100, or a dash when not worked out }
function EasyWord(const R: TRadiantResult): string;
begin
  if (R.Friendly < 0) or (Length(R.LoopFriendly) = 0) then Result := '-'
  else Result := FormatFloat('0', R.Friendly);
end;

{ a list row in color: a figure green when it meets its goal, red when it
  misses, the words between dim }
function TRadiantForm.ResultLine(const R: TRadiantResult; Short: Boolean): string;
var
  Cover, Spread: Double;
  Goals, Met: Boolean;
  Easy: string;

  { colored against its goal only when there are goals to meet }
  function Fig(const Txt: string; Good: Boolean): string;
  begin
    if Goals then Result := InkSpan(Txt, ToneColor(Good), True) else Result := TextSpan(Txt);
  end;

begin
  RadiantMeasure(R, Cover, Spread);
  Goals := (FWorkSpec.GoalCoverPct > 0) or (FWorkSpec.GoalEvenPct > 0);
  Met := RadiantMeetsGoals(R, FWorkSpec);
  Easy := EasyWord(R);
  Result :=
    Fig(Format('%5s%%', [FormatFloat('0.0', Cover * 100)]),
      (FWorkSpec.GoalCoverPct <= 0) or (Cover * 100 >= FWorkSpec.GoalCoverPct - 1E-9)) +
    DimSpan(IfThen(Short, ' ', ' covered  ')) +
    Fig(Format('%4s%%', [FormatFloat(IfThen(Short, '0', '0.0'), Spread * 100)]),
      (FWorkSpec.GoalEvenPct <= 0) or (Spread * 100 <= FWorkSpec.GoalEvenPct + 1E-9)) +
    DimSpan(Format(IfThen(Short, ' (%3s ft) ', ' apart (%3s ft)  '), [FormatFloat('0', RadiantSpreadFt(R))])) +
    IfThen(RadiantOverPorts(R, FWorkSpec) > 0, InkSpan(Format('%2d', [Length(R.Loops)]), ToneColor(False), True),
      TextSpan(Format('%2d', [Length(R.Loops)]))) +
    DimSpan(IfThen(Short, ' lp ', ' loops  ')) +
    TextSpan(Format(IfThen(Short, '%3d', '%4d'), [R.Bends])) +
    DimSpan(IfThen(Short, ' bd  ', ' bends  '));
  if not Short then
    Result := Result + TextSpan(Format('%5s', [FormatFloat('0', R.TotalFt)])) + DimSpan(' ft  easy ');
  if Easy = '-' then Result := Result + DimSpan(Format('%3s', [Easy]))
  else Result := Result + Fig(Format('%3s', [Easy]), not RadiantUnfriendly(R, FWorkSpec));
  if not R.Ok or (R.Crossings > 0) then
    Result := Result + InkSpan(IfThen(R.Crossings > 0, '  crosses', '  unfinished'), ToneColor(False), True)
  else if Met then
    Result := Result + InkSpan(IfThen(Short, ' ', '  ') + #$E2#$9C#$93, ToneColor(True), True);
end;

function TRadiantForm.FoundLine(const R: TRadiantResult): string;
begin
  Result := ResultLine(R, False);
end;

function TRadiantForm.ShortLine(const R: TRadiantResult): string;
begin
  Result := ResultLine(R, True);
end;

procedure TRadiantForm.btnSearchZoneClick(Sender: TObject);
begin
  if SelectedZone >= 0 then Search([SelectedZone]);
end;

procedure TRadiantForm.btnSearchAllClick(Sender: TObject);
var
  Which: TIntArray;
  Z: Integer;
begin
  SetLength(Which, Length(FZones));
  for Z := 0 to High(FZones) do Which[Z] := Z;
  Search(Which);
end;

procedure TRadiantForm.miSearchZoneClick(Sender: TObject);
begin
  btnSearchZoneClick(Sender);
end;

procedure TRadiantForm.miClearZoneClick(Sender: TObject);
begin
  ClearZone(SelectedZone);
  Summarize;
end;

procedure TRadiantForm.miClearAllClick(Sender: TObject);
begin
  ClearAll;
  Summarize;
end;

{ the menu names the zone it acts on: the one right-clicked, which the
  mouse-down has already selected }
procedure TRadiantForm.pmZonePopup(Sender: TObject);
var
  Z: Integer;
begin
  Z := SelectedZone;
  miSearchZone.Enabled := (Z >= 0) and (FBusy = nil);
  miClearZone.Enabled := Z >= 0;
  miRotate.Enabled := (Z >= 0) and (FBusy = nil);
  miFace.Enabled := (Z >= 0) and (FBusy = nil);
  miSearchAll.Enabled := (Length(FZones) > 0) and (FBusy = nil);
  miNotZone.Enabled := (Z >= 0) and (FBusy = nil) and (Length(FZones) > 1);
  ShowLeftOut;
  if Z >= 0 then
  begin
    miSearchZone.Caption := Format('Search zone %d', [Z + 1]);
    miClearZone.Caption := Format('Clear zone %d', [Z + 1]);
    miNotZone.Caption := Format('Zone %d is not a zone - leave it bare', [Z + 1]);
  end;
end;

{ the tube's own rules changed: every zone's layout is stale }
procedure TRadiantForm.RoutingChange(Sender: TObject);
begin
  if FListing then Exit;
  ClearAll;
  Summarize;
end;

{ the waste or the tag: only the ticket changes }
procedure TRadiantForm.AnyChange(Sender: TObject);
begin
  if FListing then Exit;
  Summarize;
end;

{ ---- manifolds ---- }

procedure TRadiantForm.btnSuggestClick(Sender: TObject);
var
  Spec: TRadiantSpec;
  Z, I, N: Integer;
  Mid: TP3;
begin
  if not Read(Spec) or (Length(FZones) = 0) then begin Summarize; Exit; end;
  { each zone's manifold goes at its corner nearest the middle of
    everything, where the boiler most likely is }
  Mid := P3(0, 0, 0); N := 0;
  for Z := 0 to High(FZones) do
    for I := 0 to High(FZones[Z].Outline) do
    begin
      Mid := Add3(Mid, FZones[Z].Outline[I]);
      Inc(N);
    end;
  if N > 0 then Mid := P3(Mid.X / N, Mid.Y / N, Mid.Z / N);
  SetLength(FManifolds, Length(FZones));
  SetLength(FPorts, Length(FZones));
  for Z := 0 to High(FZones) do
    RadiantSuggestZoneManifold(FZones[Z], Mid, Spec, FManifolds[Z], FPorts[Z]);
  if Length(FOutline) >= 3 then FFrame := RadiantPlanFrame(FOutline);
  SetLength(FAngles, Length(FZones));
  for Z := 0 to High(FZones) do FAngles[Z] := WallAngle(Z);
  ClearAll;
  Summarize;
end;

{ Show (and build) solution Idx of the ones the zone's last search kept,
  wrapping round at either end. }
procedure TRadiantForm.ShowSolution(Z, Idx: Integer);
var
  N: Integer;
begin
  if (Z < 0) or (Z > High(FSolutions)) then Exit;
  N := Length(FSolutions[Z]);
  if N = 0 then Exit;
  Idx := ((Idx mod N) + N) mod N;
  { a reopened job keeps paths only for the layout it built; the others
    are records only (see hsRadiantJob) }
  if (Length(FSolutions[Z][Idx].Loops) > 0) and (Length(FSolutions[Z][Idx].Loops[0].Pts) = 0) then
  begin
    lblProblem.Caption := 'Only the built layout was kept - search again for the rest.';
    ShowZonePanel;
    Exit;
  end;
  FSolIdx[Z] := Idx;
  FLayouts[Z] := FSolutions[Z][Idx];
  if FLayouts[Z].Ok and (Length(FLayouts[Z].Manifolds) > 0) then
  begin
    FPorts[Z] := FLayouts[Z].Manifolds[0].Ports;
    FManifolds[Z] := FLayouts[Z].Manifolds[0].At;
  end;
  Summarize;
end;

{ ---- obstacles, and shapes that are not zones ---- }

{ the key a zone's outline is remembered by - NameKey for one zone }
function TRadiantForm.OutlineKey(const O: TP3Array): string;
var
  S: string;
  I: Integer;
  H: Cardinal;
begin
  S := '';
  for I := 0 to High(O) do
    S := S + Format('%.2f,%.2f,%.2f;', [O[I].X, O[I].Y, O[I].Z], DefaultFormatSettings);
  H := 2166136261;
  for I := 1 to Length(S) do H := Cardinal((QWord(H xor Ord(S[I])) * 16777619) and $FFFFFFFF);
  Result := 'zone-' + IntToHex(H, 8);
end;

{ the right-click menu's Bring back says how many shapes are left out }
procedure TRadiantForm.ShowLeftOut;
begin
  if Length(FLeftOut) = 0 then miBringBack.Caption := 'Bring back the shapes left out'
  else miBringBack.Caption := Format('Bring back the %d shape%s left out', [Length(FLeftOut),
    IfThen(Length(FLeftOut) = 1, '', 's')]);
  miBringBack.Enabled := (Length(FLeftOut) > 0) and (FBusy = nil);
end;

procedure TRadiantForm.DropZone(Z: Integer; Remember: Boolean);
var
  Ini: TIniFile;
begin
  if (Z < 0) or (Z > High(FZones)) then Exit;
  if Remember then
    try
      Ini := TIniFile.Create(ConfigFile);
      try
        Ini.WriteBool('radiant-notzone', OutlineKey(FZones[Z].Outline), True);
      finally
        Ini.Free;
      end;
    except
    end;
  if Remember then
  begin
    SetLength(FLeftOut, Length(FLeftOut) + 1);
    FLeftOut[High(FLeftOut)] := FZones[Z];
  end;
  { out of every per-zone list, however many are filled so far }
  Delete(FZones, Z, 1);
  if Z <= High(FManifolds) then Delete(FManifolds, Z, 1);
  if Z <= High(FAngles) then Delete(FAngles, Z, 1);
  if Z <= High(FPorts) then Delete(FPorts, Z, 1);
  if Z <= High(FLayouts) then Delete(FLayouts, Z, 1);
  if Z <= High(FSearched) then Delete(FSearched, Z, 1);
  if Z <= High(FSolutions) then Delete(FSolutions, Z, 1);
  if Z <= High(FSolIdx) then Delete(FSolIdx, Z, 1);
  if Z <= High(FZoneTicket) then Delete(FZoneTicket, Z, 1);
  if Z <= High(FZoneNames) then Delete(FZoneNames, Z, 1);
  if Z <= High(FPins) then Delete(FPins, Z, 1);
  if Z <= High(FHeat.Zones) then Delete(FHeat.Zones, Z, 1);
end;

{ A face the same shape as a hole in another is an obstacle (a column
  inside the slab), never a zone.  A shape left out on this floor before
  stays out. }
procedure TRadiantForm.DropHoles;
var
  Z, O, H, I, J: Integer;
  Same, Found: Boolean;
  Ini: TIniFile;
begin
  for Z := High(FZones) downto 0 do
  begin
    Found := False;
    for O := 0 to High(FZones) do
    begin
      if O = Z then Continue;
      for H := 0 to High(FZones[O].Holes) do
      begin
        if Length(FZones[O].Holes[H]) <> Length(FZones[Z].Outline) then Continue;
        Same := True;
        for I := 0 to High(FZones[Z].Outline) do
        begin
          J := 0;
          while (J <= High(FZones[O].Holes[H])) and
                (Dist(FZones[O].Holes[H][J], FZones[Z].Outline[I]) > 0.01) do Inc(J);
          if J > High(FZones[O].Holes[H]) then begin Same := False; Break; end;
        end;
        if Same then begin Found := True; Break; end;
      end;
      if Found then Break;
    end;
    if Found then DropZone(Z, False);
  end;
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      for Z := High(FZones) downto 0 do
        if Ini.ReadBool('radiant-notzone', OutlineKey(FZones[Z].Outline), False) then
        begin
          SetLength(FLeftOut, Length(FLeftOut) + 1);
          FLeftOut[High(FLeftOut)] := FZones[Z];
          DropZone(Z, False);
        end;
    finally
      Ini.Free;
    end;
  except
  end;
end;

{ Not a zone: take the selected zone out of the job (a chase, a column
  against a wall), leave it bare, and remember that for this floor. }
procedure TRadiantForm.btnNotZoneClick(Sender: TObject);
var
  Z: Integer;
begin
  Z := SelectedZone;
  if (Z < 0) or (FBusy <> nil) then Exit;
  if Length(FZones) <= 1 then
  begin
    lblProblem.Caption := 'The last zone cannot be left out.';
    Exit;
  end;
  DropZone(Z, True);
  FZoneTabs.Tabs.Clear;
  ListZones;
  ShowLeftOut;
  SaveNames;
  Summarize;
  pbPlan.Invalidate;
end;

{ every shape left out becomes a zone again, at the end, its manifold
  where Suggest puts it }
procedure TRadiantForm.btnBringBackClick(Sender: TObject);
var
  K, Z, Ports: Integer;
  Spec: TRadiantSpec;
  Mid, M: TP3;
  Ini: TIniFile;
begin
  if (Length(FLeftOut) = 0) or (FBusy <> nil) then Exit;
  if not Read(Spec) then Spec := DefaultRadiantSpec;
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      for K := 0 to High(FLeftOut) do Ini.DeleteKey('radiant-notzone', OutlineKey(FLeftOut[K].Outline));
    finally
      Ini.Free;
    end;
  except
  end;
  Mid := P3(0, 0, 0);
  for K := 0 to High(FLeftOut) do
  begin
    SetLength(FZones, Length(FZones) + 1);
    Z := High(FZones);
    FZones[Z] := FLeftOut[K];
    SetLength(FManifolds, Length(FZones)); SetLength(FPorts, Length(FZones)); SetLength(FAngles, Length(FZones));
    RadiantSuggestZoneManifold(FZones[Z], Mid, Spec, M, Ports);
    FManifolds[Z] := M; FPorts[Z] := Ports; FAngles[Z] := WallAngle(Z);
    SetLength(FLayouts, Length(FZones)); FLayouts[Z] := Default(TRadiantResult);
    SetLength(FSearched, Length(FZones)); FSearched[Z] := False;
    SetLength(FSolutions, Length(FZones)); FSolutions[Z] := nil;
    SetLength(FSolIdx, Length(FZones)); FSolIdx[Z] := 0;
    SetLength(FZoneTicket, Length(FZones)); FZoneTicket[Z] := '';
  end;
  FLeftOut := nil;
  { names, pins and heat load read again for the zones as they are now }
  FZoneNames := nil;
  LoadNames;
  FZoneTabs.Tabs.Clear;
  ListZones;
  ShowLeftOut;
  Summarize;
  pbPlan.Invalidate;
end;

{ ---- the plan, and dragging on it ---- }

function TRadiantForm.PlanX(U: Double): Integer;
begin
  Result := Round(FMargin + FOffX + (U - FMinX) * FSc);
end;

function TRadiantForm.PlanY(V: Double): Integer;
begin
  Result := Round(pbPlan.Height - FMargin - FOffY - (V - FMinY) * FSc);
end;

function TRadiantForm.PlanU(X: Integer): Double;
begin
  if FSc <= 0 then Exit(0);
  Result := FMinX + (X - FMargin - FOffX) / FSc;
end;

function TRadiantForm.PlanV(Y: Integer): Double;
begin
  if FSc <= 0 then Exit(0);
  Result := FMinY + (pbPlan.Height - FMargin - FOffY - Y) / FSc;
end;

procedure TRadiantForm.pbPlanMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  P, M: T2;
begin
  if (Length(FOutline) < 3) or (FSc <= 0) or (FBusy <> nil) then Exit;
  M := Point2(PlanU(X), PlanV(Y));
  if Button = mbRight then
  begin
    { the zone the menu acts on: the manifold under the pointer, else the
      zone the pointer is in, else what was selected }
    I := ManifoldAt(X, Y);
    if I < 0 then
      for I := High(FZones) downto 0 do
        if RadiantInside(FZones[I].Outline, RadiantFrom2(FFrame, M.X, M.Y)) then Break;
    if I >= 0 then SelectZone(I);
    pbPlan.Invalidate;
    Exit;
  end;
  if Button <> mbLeft then Exit;
  { a manifold under the pointer }
  FDragManifold := ManifoldAt(X, Y); FDragMoved := False;
  if FDragManifold >= 0 then
  begin
    P := RadiantTo2(FFrame, FManifolds[FDragManifold]);
    FDragOff := Point2(P.X - M.X, P.Y - M.Y);
    SelectZone(FDragManifold);
    Exit;
  end;
  { nothing to drag: bring up the tab of the zone clicked in }
  for I := High(FZones) downto 0 do
    if RadiantInside(FZones[I].Outline, RadiantFrom2(FFrame, M.X, M.Y)) then
    begin
      SelectZone(I);
      Exit;
    end;
end;

procedure TRadiantForm.pbPlanMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  M: T2;
  D, A: Double;
  Curved: Boolean;
begin
  if FDragManifold < 0 then Exit;
  M := Point2(PlanU(X) + FDragOff.X, PlanV(Y) + FDragOff.Y);
  if FDragManifold >= 0 then
  begin
    { a manifold stays in its own zone: a drag out of it is ignored }
    if not RadiantInside(FZones[FDragManifold].Outline, RadiantFrom2(FFrame, M.X, M.Y)) then Exit;
    FManifolds[FDragManifold] := RadiantFrom2(FFrame, M.X, M.Y);
    { Pushed against a flat wall, it turns to lie along it and keeps that
      heading when dragged away again - a quick way to rotate one.  Not on a
      curve, where a chord's heading means nothing. }
    if (FDragManifold <= High(FAngles)) and
       NearestWall(FDragManifold, M, D, A, Curved) and not Curved and
       (D <= Max(MANIFOLD_SNAP_FT, MANIFOLD_SNAP_PX / FSc)) then
      FAngles[FDragManifold] := A;
    { the old layout is gone the moment it moves, but only this zone's;
      an obstacle would clear every zone }
    if not FDragMoved then ClearZone(FDragManifold);
  end;
  FDragMoved := True;
  pbPlan.Invalidate;
end;

procedure TRadiantForm.pbPlanMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDragManifold := -1;
  if FDragMoved then Summarize;
  FDragMoved := False;
end;

{ A gauge, painted the same on both boxes: a bar filled to Frac (0..1) of
  its width, green when good, amber part way, red poor.  Frac < 0 means
  nothing is worked out yet, and the bar says so instead of guessing. }
procedure PaintGauge(PB: TPaintBox; Frac: Double; const Cap: string);
var
  C: TCanvas;
  W, H, FillW, TW: Integer;
begin
  C := PB.Canvas;
  W := PB.Width; H := PB.Height;
  C.Brush.Color := PixToColor(DlgTheme.Shell2);
  C.FillRect(0, 0, W, H);
  if Frac >= 0 then
  begin
    FillW := Round(W * Frac);
    if Frac >= 0.85 then C.Brush.Color := $00308030
    else if Frac >= 0.65 then C.Brush.Color := $000080C0
    else C.Brush.Color := $002020C0;
    C.FillRect(0, 0, FillW, H);
  end;
  C.Brush.Style := bsClear;
  C.Pen.Color := PixToColor(DlgTheme.Bezel1);
  C.Rectangle(0, 0, W, H);
  C.Font.Height := -13;
  { theme text over the empty part, white over the filled - all the fill
    colors are deep enough to take it }
  if Frac >= 0.5 then C.Font.Color := clWhite else C.Font.Color := PixToColor(DlgTheme.Text);
  TW := C.TextWidth(Cap);
  C.TextOut((W - TW) div 2, (H - C.TextHeight(Cap)) div 2, Cap);
  C.Brush.Style := bsSolid;
end;

procedure TRadiantForm.pbCoveragePaint(Sender: TObject);
begin
  if FCoverage < 0 then PaintGauge(pbCoverage, -1, 'Coverage - search a zone to see it')
  else PaintGauge(pbCoverage, FCoverage, Format('Coverage: %d%% of the floor reached', [Round(FCoverage * 100)]));
end;

procedure TRadiantForm.pbEvenPaint(Sender: TObject);
begin
  if FEvenness < 0 then PaintGauge(pbEven, -1, 'Evenness - how close the loop lengths come')
  else PaintGauge(pbEven, FEvenness, Format('Evenness: loops within %d%% (%s ft) of each other',
    [Round((1 - FEvenness) * 100), FormatFloat('0', FEvenFt)]));
end;

{ The plan: the outline with its holes shaded, each loop in its own color
  so a long run is easy to follow, and the manifolds as numbered boxes
  that can be dragged. }
procedure TRadiantForm.pbPlanPaint(Sender: TObject);
type
  TPtArr = array of TPoint;
var
  C: TCanvas;
  W, H, I, J, Z, Loops, Waiting: Integer;
  MaxX, MaxY: Double;
  P: T2;
  S: string;
  Box: T2Array;
  BoxPx: TPtArr;
  Order: TIntArray;
  K, LX, LY: Integer;
  Mid, Q: T2;
  Off: Double;

  function Poly(const Pts: TP3Array): TPtArr;
  var
    K: Integer;
    Q: T2;
  begin
    SetLength(Result, Length(Pts));
    for K := 0 to High(Pts) do
    begin
      Q := RadiantTo2(FFrame, Pts[K]);
      Result[K] := Point(PlanX(Q.X), PlanY(Q.Y));
    end;
  end;

begin
  C := pbPlan.Canvas;
  W := pbPlan.Width; H := pbPlan.Height;
  C.Brush.Color := clWhite;
  C.FillRect(0, 0, W, H);
  C.Pen.Color := clSilver;
  C.Rectangle(0, 0, W, H);
  FSc := 0;
  if Length(FOutline) < 3 then Exit;
  FFrame := RadiantPlanFrame(FOutline);
  FMargin := 30;
  FMinX := 1E30; MaxX := -1E30; FMinY := 1E30; MaxY := -1E30;
  for Z := 0 to High(FZones) do
    for I := 0 to High(FZones[Z].Outline) do
    begin
      P := RadiantTo2(FFrame, FZones[Z].Outline[I]);
      FMinX := Min(FMinX, P.X); MaxX := Max(MaxX, P.X);
      FMinY := Min(FMinY, P.Y); MaxY := Max(MaxY, P.Y);
    end;
  FSc := Min((W - 2 * FMargin) / Max(MaxX - FMinX, 1E-6), (H - 2 * FMargin) / Max(MaxY - FMinY, 1E-6));
  FOffX := Max(0, (W - 2 * FMargin - (MaxX - FMinX) * FSc) / 2);
  FOffY := Max(0, (H - 2 * FMargin - (MaxY - FMinY) * FSc) / 2);

  for Z := 0 to High(FZones) do
  begin
    C.Pen.Color := clBlack; C.Pen.Width := 2; C.Brush.Style := bsClear;
    { the zone whose tab is up, lightly tinted }
    if Z = SelectedZone then begin C.Brush.Style := bsSolid; C.Brush.Color := $00E6F7FF; end;
    C.Polygon(Poly(FZones[Z].Outline));
    C.Brush.Style := bsClear;
    C.Pen.Width := 1;
    C.Brush.Style := bsSolid; C.Brush.Color := $00D0D0D0;
    for I := 0 to High(FZones[Z].Holes) do
      if Length(FZones[Z].Holes[I]) >= 3 then C.Polygon(Poly(FZones[Z].Holes[I]));
  end;
  { the shapes left out - not zones - in gray, bare }
  C.Pen.Color := $00A0A0A0;
  C.Brush.Color := $00E8E8E8;
  for I := 0 to High(FLeftOut) do
    if Length(FLeftOut[I].Outline) >= 3 then C.Polygon(Poly(FLeftOut[I].Outline));
  C.Brush.Style := bsClear;
  for Z := 0 to High(FLayouts) do
    if (Z <= High(FSearched)) and FSearched[Z] and FLayouts[Z].Ok then
      for I := 0 to High(FLayouts[Z].Loops) do
      begin
        { every loop its own color - what the build draws }
        C.Pen.Color := LoopInk(Z, I);
        C.Pen.Width := Round(LoopWeight(I));
        for J := 1 to High(FLayouts[Z].Loops[I].Pts) do
        begin
          P := RadiantTo2(FFrame, FLayouts[Z].Loops[I].Pts[J - 1]);
          C.MoveTo(PlanX(P.X), PlanY(P.Y));
          P := RadiantTo2(FFrame, FLayouts[Z].Loops[I].Pts[J]);
          C.LineTo(PlanX(P.X), PlanY(P.Y));
        end;
      end;
  { manifolds last, on top, each turned the way it hangs, the selected one
    over the rest.  The number is set off toward the middle of its zone so
    four manifolds at one corner still read as four. }
  C.Pen.Width := 1;
  SetLength(FAngles, Length(FManifolds));
  SetLength(Order, 0);
  for I := 0 to High(FManifolds) do
    if I <> SelectedZone then
    begin
      SetLength(Order, Length(Order) + 1); Order[High(Order)] := I;
    end;
  if (SelectedZone >= 0) and (SelectedZone <= High(FManifolds)) then
  begin
    SetLength(Order, Length(Order) + 1); Order[High(Order)] := SelectedZone;
  end;
  for K := 0 to High(Order) do
  begin
    I := Order[K];
    P := RadiantTo2(FFrame, FManifolds[I]);
    if SelectedZone = I then C.Brush.Color := clYellow else C.Brush.Color := clWhite;
    C.Brush.Style := bsSolid;
    C.Pen.Color := ZoneInk(I);
    C.Pen.Width := 2;
    Box := ManifoldBox(I);
    SetLength(BoxPx, 4);
    for J := 0 to 3 do BoxPx[J] := Point(PlanX(Box[J].X), PlanY(Box[J].Y));
    C.Polygon(BoxPx);
    { the number, a little way toward the middle of its zone }
    Mid := Point2(0, 0);
    if I <= High(FZones) then
      for J := 0 to High(FZones[I].Outline) do
      begin
        Q := RadiantTo2(FFrame, FZones[I].Outline[J]);
        Mid.X := Mid.X + Q.X / Length(FZones[I].Outline);
        Mid.Y := Mid.Y + Q.Y / Length(FZones[I].Outline);
      end;
    Off := Hypot(PlanX(Mid.X) - PlanX(P.X), PlanY(Mid.Y) - PlanY(P.Y));
    if Off > 1 then
    begin
      LX := PlanX(P.X) + Round(16 * (PlanX(Mid.X) - PlanX(P.X)) / Off);
      LY := PlanY(P.Y) + Round(16 * (PlanY(Mid.Y) - PlanY(P.Y)) / Off);
    end
    else begin LX := PlanX(P.X); LY := PlanY(P.Y); end;
    { black on white: in the zone's own ink it vanished into its own tube }
    S := IntToStr(I + 1);
    C.Brush.Style := bsSolid; C.Brush.Color := clWhite;
    C.Font.Color := clBlack;
    C.TextOut(LX - C.TextWidth(S) div 2, LY - C.TextHeight(S) div 2, S);
  end;
  C.Brush.Style := bsClear;
  C.Font.Color := clGray;
  Loops := 0; Waiting := 0;
  for Z := 0 to High(FLayouts) do
    if (Z <= High(FSearched)) and FSearched[Z] then
    begin
      if FLayouts[Z].Ok then Loops := Loops + Length(FLayouts[Z].Loops);
    end
    else Inc(Waiting);
  if Waiting > 0 then
    C.TextOut(8, H - 20, Format('%d zone(s) not searched - place the manifolds, then right-click one: Search',
      [Waiting]))
  else if not AnyLayout then C.TextOut(8, H - 20, 'no layout found - move a manifold and search again')
  else C.TextOut(8, H - 20, Format('%d zone(s), %d loop(s) - drag a manifold, right-click to turn it',
    [Length(FZones), Loops]));
  PaintCompass(C, W - 34, 62);
end;

{ Which way north is on the plan, drawn at CX, CY.  North is the drawing's
  green axis and east its red, carried through the plan's own frame, so the
  rose matches what the plan shows even when it is turned or mirrored. }
procedure TRadiantForm.PaintCompass(C: TCanvas; CX, CY: Integer);
const
  R = 16;
  TAGS: array[0..3] of string = ('N', 'E', 'S', 'W');
var
  K: Integer;
  NU, NV, EU, EV, L, DX, DY: Double;
begin
  NU := FFrame.U.Y; NV := FFrame.V.Y;
  EU := FFrame.U.X; EV := FFrame.V.X;
  L := Hypot(NU, NV);
  if L < 0.2 then Exit;
  NU := NU / L; NV := NV / L;
  L := Hypot(EU, EV);
  if L < 0.2 then Exit;
  EU := EU / L; EV := EV / L;
  C.Pen.Width := 1;
  C.Pen.Color := clSilver;
  C.Brush.Style := bsClear;
  C.Ellipse(CX - R, CY - R, CX + R + 1, CY + R + 1);
  { the four points, screen y down; north the heavy one }
  for K := 0 to 3 do
  begin
    case K of
      0: begin DX := NU; DY := -NV; end;
      1: begin DX := EU; DY := -EV; end;
      2: begin DX := -NU; DY := NV; end;
    else begin DX := -EU; DY := EV; end;
    end;
    { north green and east red, as the drawing's own compass has them }
    case K of
      0: begin C.Pen.Color := $0030A030; C.Pen.Width := 2; end;
      1: begin C.Pen.Color := $002030C8; C.Pen.Width := 2; end;
    else begin C.Pen.Color := clGray; C.Pen.Width := 1; end;
    end;
    C.Line(CX, CY, CX + Round(DX * R), CY + Round(DY * R));
    if K <= 1 then C.Font.Style := [fsBold] else C.Font.Style := [];
    if K <= 1 then C.Font.Color := C.Pen.Color else C.Font.Color := clGray;
    C.TextOut(CX + Round(DX * (R + 9)) - C.TextWidth(TAGS[K]) div 2,
      CY + Round(DY * (R + 9)) - C.TextHeight(TAGS[K]) div 2, TAGS[K]);
  end;
  C.Font.Style := [];
  C.Pen.Width := 1;
end;

{ the job as the submittal takes it: the settings, every zone, its layout
  and what its search kept, the names }
function TRadiantForm.MakeJob(out Job: TRadiantJob): Boolean;
var
  Z: Integer;
begin
  Job := Default(TRadiantJob);
  Result := False;
  if not Read(Job.Spec) or (Length(FZones) = 0) then Exit;
  Job.Title := Trim(edTag.Text);
  Job.ZoneNames := Copy(FZoneNames);
  Job.Heat := FHeat;
  Job.When := Now;
  Job.Made := 'Heckers Sketch ' + CurrentVersion;
  Job.Units := FUnits;
  Job.Zones := FZones;
  SetLength(Job.ZoneSpecs, Length(FZones));
  for Z := 0 to High(FZones) do Job.ZoneSpecs[Z] := ZoneSpec(Z, Job.Spec);
  Job.Angles := Copy(FAngles);
  Job.Pins := Copy(FPins);
  Job.LeftOut := Copy(FLeftOut);
  Job.Searched := Copy(FSearched);
  Job.Layouts := Copy(FLayouts);
  SetLength(Job.Solutions, Length(FZones));
  SetLength(Job.Picked, Length(FZones));
  for Z := 0 to High(FZones) do
  begin
    if Z <= High(FSolutions) then Job.Solutions[Z] := FSolutions[Z] else Job.Solutions[Z] := nil;
    if Z <= High(FSolIdx) then Job.Picked[Z] := FSolIdx[Z] else Job.Picked[Z] := 0;
  end;
  Result := True;
end;

{ Export the job as a submittal: a PDF, a zone to a page, or its text
  (see hsRadiantSubmittal). }
procedure TRadiantForm.btnExportClick(Sender: TObject);
var
  Job: TRadiantJob;
begin
  if not MakeJob(Job) then Exit;
  if Job.Title <> '' then sdExport.FileName := Job.Title + ' - radiant submittal.pdf'
  else sdExport.FileName := 'radiant submittal ' + FormatDateTime('yyyy-mm-dd', Now) + '.pdf';
  if not sdExport.Execute then Exit;
  try
    { a PDF on letter, or A4 for a metric drawing; the text if a .txt was asked for }
    SubmittalExport(Job, sdExport.FileName);
    lblProblem.Caption := 'Exported: ' + ExtractFileName(sdExport.FileName);
  except
    on E: Exception do lblProblem.Caption := 'Could not write it: ' + E.Message;
  end;
end;

{ The submittal written to the temp folder and opened in the system's PDF
  reader, to look it over without saving it. }
procedure TRadiantForm.btnPreviewClick(Sender: TObject);
var
  Job: TRadiantJob;
  Path: string;
begin
  if not MakeJob(Job) then Exit;
  Path := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'Heckers Sketch - radiant submittal preview.pdf';
  Screen.Cursor := crHourGlass;
  try
    try
      if FUnits = usImperial then SubmittalToPdf(Job, RadiantSubmittal(Job), Path, 215.9, 279.4)
      else SubmittalToPdf(Job, RadiantSubmittal(Job), Path, 210, 297);
    except
      on E: Exception do
      begin
        lblProblem.Caption := 'Could not make the preview: ' + E.Message;
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  if OpenDocument(Path) then lblProblem.Caption := 'Preview opened - nothing saved; Export the submittal keeps it.'
  else lblProblem.Caption := 'The preview is at ' + Path + ' - no PDF reader would open it.';
end;

procedure TRadiantForm.btnReportClick(Sender: TObject);
begin
  MainForm.ReportFromDialog('Radiant heat layout',
    'floor: concrete slab' + LineEnding +
    'tube: ' + cbTube.Text + ', spacing ' + edSpacing.Text + LineEnding +
    'manifolds: ' + IntToStr(Length(FManifolds)) + ', shapes left out: ' + IntToStr(Length(FLeftOut)) + LineEnding +
    'problem shown: ' + lblProblem.Caption);
end;

procedure TRadiantForm.ShowSpec(const Spec: TRadiantSpec);
var
  Inch: Double;
begin
  Inch := Spec.Inch;
  if Inch <= 0 then Inch := 1 / 12;
  FListing := True;
  try
    cbTube.ItemIndex := Ord(Spec.Tube);
    { as the trade says them: the spacing in inches, a loop in feet }
    edSpacing.Text := FormatFloat('0.###', Spec.Spacing / Inch);
    if Spec.MaxLoopFt > 0 then edMaxLoop.Text := FormatFloat('0.#', Spec.MaxLoopFt / (Inch * 12))
    else edMaxLoop.Text := '';
    edWaste.Text := FormatFloat('0.##', Spec.WastePct);
    if Spec.MaxPorts > 0 then edMaxPorts.Text := IntToStr(Spec.MaxPorts) else edMaxPorts.Text := '';
    cbLabels.Checked := Spec.Labels;
    FHookPairs := Spec.HookPairs;
    FGoalCover := Spec.GoalCoverPct;
    FGoalEven := Spec.GoalEvenPct;
    FLessFriendly := Spec.LessFriendly;
    FNoHooks := Spec.NoHooks;
  finally
    FListing := False;
  end;
end;

function TRadiantForm.Finish(out Zones: TRadiantZones; out Spec: TRadiantSpec; out Manifolds: TP3Array;
  out Ports: TIntArray; out Layouts: TRadiantResults; out ZoneNames: TStringArray;
  out Job: TRadiantJob): Boolean;
begin
  SaveLast;
  Zones := Copy(FZones);
  Result := Read(Spec) and (Length(FManifolds) = Length(Zones)) and MakeJob(Job);
  Manifolds := Copy(FManifolds);
  Ports := Copy(FPorts);
  Layouts := Copy(FLayouts);
  ZoneNames := Copy(FZoneNames);
  SetLength(ZoneNames, Length(Zones));
end;

class function TRadiantForm.Ask(Units: TUnitSystem; var Zones: TRadiantZones;
  out Spec: TRadiantSpec; out Manifolds: TP3Array; out Ports: TIntArray;
  out Layouts: TRadiantResults; out ZoneNames: TStringArray; out Job: TRadiantJob): Boolean;
var
  F: TRadiantForm;
begin
  Result := False;
  Job := Default(TRadiantJob);
  F := TRadiantForm.Create(nil);
  try
    F.FUnits := Units;
    F.FZones := Zones;
    { the plan is drawn in the first zone's frame - any zone will do as
      long as it is the same one every time }
    F.DropHoles;
    if Length(F.FZones) > 0 then F.FOutline := F.FZones[0].Outline;
    F.ShowLeftOut;
    if F.ShowModal <> mrOK then Exit;
    Result := F.Finish(Zones, Spec, Manifolds, Ports, Layouts, ZoneNames, Job);
  finally
    F.Free;
  end;
end;

class function TRadiantForm.Reopen(Units: TUnitSystem; const Was: TRadiantJob; out Zones: TRadiantZones;
  out Spec: TRadiantSpec; out Manifolds: TP3Array; out Ports: TIntArray;
  out Layouts: TRadiantResults; out ZoneNames: TStringArray; out Job: TRadiantJob): Boolean;
var
  F: TRadiantForm;
  Z, N: Integer;
begin
  Result := False;
  Job := Default(TRadiantJob);
  N := Length(Was.Zones);
  if N = 0 then Exit;
  F := TRadiantForm.Create(nil);
  try
    F.FUnits := Units;
    F.FZones := Copy(Was.Zones);
    F.FLeftOut := Copy(Was.LeftOut);
    F.FOutline := F.FZones[0].Outline;
    F.FFrame := RadiantPlanFrame(F.FOutline);
    F.ShowLeftOut;
    F.ShowSpec(Was.Spec);
    F.FListing := True;
    try
      F.edTag.Text := Was.Title;
    finally
      F.FListing := False;
    end;
    SetLength(F.FManifolds, N); SetLength(F.FPorts, N); SetLength(F.FAngles, N);
    SetLength(F.FPins, N); SetLength(F.FZoneNames, N);
    SetLength(F.FSearched, N); SetLength(F.FLayouts, N);
    SetLength(F.FSolutions, N); SetLength(F.FSolIdx, N);
    for Z := 0 to N - 1 do
    begin
      if (Z <= High(Was.ZoneSpecs)) and (Length(Was.ZoneSpecs[Z].Manifolds) > 0) then
      begin
        F.FManifolds[Z] := Was.ZoneSpecs[Z].Manifolds[0];
        if Length(Was.ZoneSpecs[Z].Ports) > 0 then F.FPorts[Z] := Was.ZoneSpecs[Z].Ports[0];
      end
      else
        { a zone that never had one - suggested, as a new job's is }
        RadiantSuggestZoneManifold(F.FZones[Z], F.FZones[Z].Outline[0], Was.Spec, F.FManifolds[Z], F.FPorts[Z]);
      if Z <= High(Was.Angles) then F.FAngles[Z] := Was.Angles[Z] else F.FAngles[Z] := F.WallAngle(Z);
      F.FPins[Z] := (Z <= High(Was.Pins)) and Was.Pins[Z];
      if Z <= High(Was.ZoneNames) then F.FZoneNames[Z] := Was.ZoneNames[Z];
      F.FSearched[Z] := (Z <= High(Was.Searched)) and Was.Searched[Z] and (Z <= High(Was.Layouts));
      if F.FSearched[Z] then F.FLayouts[Z] := Was.Layouts[Z];
      if Z <= High(Was.Solutions) then F.FSolutions[Z] := Copy(Was.Solutions[Z]);
      if Z <= High(Was.Picked) then F.FSolIdx[Z] := Was.Picked[Z];
    end;
    F.FHeat := Was.Heat;
    SetLength(F.FHeat.Zones, N);
    F.ShowHeat;
    F.lblTitle.Caption := 'Radiant heat layout - as it was built';
    if F.ShowModal <> mrOK then Exit;
    Result := F.Finish(Zones, Spec, Manifolds, Ports, Layouts, ZoneNames, Job);
  finally
    F.Free;
  end;
end;

end.

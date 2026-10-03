unit hsRadiantHeatForm;

{ The radiant wizard's heat load window, opened from its "Heat load..."
  button: a few answers about the building, which walls of each zone are
  outside walls (clicked on the plan), and what each zone is. Worked out as
  you type; printed in the submittal when used. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, Graphics, Spin, LCLType,
  BCButton, BCPanel, hsDrawing, hsRadiantData, hsRadiant, hsRadiantHeat;

type

  { TRadiantHeatForm }

  TRadiantHeatForm = class(TForm)
    btnCancel: TBCButton;
    btnClimateHelp: TBCButton;
    btnOff: TBCButton;
    btnOk: TBCButton;
    cbAbove: TComboBox;
    cbClimate: TComboBox;
    cbCover: TComboBox;
    cbDhw: TCheckBox;
    lblDhw: TLabel;
    cbRun: TComboBox;
    cbSlab: TComboBox;
    cbSnow: TComboBox;
    cbTight: TComboBox;
    cbUse: TComboBox;
    cbWalls: TComboBox;
    cbZone: TComboBox;
    edAltitude: TSpinEdit;
    edBaths: TSpinEdit;
    edCeiling: TSpinEdit;
    edDoors: TSpinEdit;
    edGlycol: TSpinEdit;
    edIndoor: TSpinEdit;
    edOutdoor: TSpinEdit;
    edWindows: TSpinEdit;
    lblAbove: TLabel;
    lblAltitude: TLabel;
    lblAltitudeFt: TLabel;
    lblBaths: TLabel;
    lblCeiling: TLabel;
    lblCeilingFt: TLabel;
    lblClimate: TLabel;
    lblCover: TLabel;
    lblDoors: TLabel;
    lblDoorsSq: TLabel;
    lblGlycol: TLabel;
    lblGlycolPct: TLabel;
    lblIndoor: TLabel;
    lblIndoorF: TLabel;
    lblJobHead: TLabel;
    lblJobHint: TLabel;
    lblMethod: TLabel;
    lblOutdoor: TLabel;
    lblOutdoorF: TLabel;
    lblPlanHead: TLabel;
    lblPlanHint: TLabel;
    lblRun: TLabel;
    lblSlab: TLabel;
    lblSnow: TLabel;
    lblTight: TLabel;
    lblUse: TLabel;
    lblWalls: TLabel;
    lblWindows: TLabel;
    lblWindowsSq: TLabel;
    lblZoneHead: TLabel;
    memResult: TMemo;
    pbPlan: TPaintBox;
    pnJob: TBCPanel;
    pnPlan: TBCPanel;
    pnZone: TBCPanel;
    procedure btnCancelClick(Sender: TObject);
    procedure btnClimateHelpClick(Sender: TObject);
    procedure CheckLabelClick(Sender: TObject);
    procedure btnOffClick(Sender: TObject);
    procedure btnOkClick(Sender: TObject);
    procedure FieldChange(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure pbPlanMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure pbPlanPaint(Sender: TObject);
  private
    FJob: THeatJob;
    FZones: TRadiantZones;
    FTitles: TStringArray;
    FLayouts: TRadiantResults;
    FSpecs: array of TRadiantSpec;
    FUnits: TUnitSystem;
    FSel: Integer;
    { set while the fields are filled from the job, so their change events
      are not taken as the user's edits }
    FListing: Boolean;
    { the plan's frame, and how it sits in the paint box }
    FFrame: TRadiantFrame;
    FScale, FX0, FY0, FMinU, FMaxV: Double;
    procedure Dress;
    procedure Fill;
    procedure ShowZone;
    procedure ReadJob;
    procedure ReadZone;
    procedure Report;
    procedure Fit;
    function ToScreen(const P: TP3): TPoint;
  public
    { Edits the heat load for these zones. True and Job changed when kept;
      Job.Enabled off when the user leaves it out. Specs are the zones' own
      (tube, spacing), Layouts their loops. }
    class function Edit(Units: TUnitSystem; const Zones: TRadiantZones; const Titles: TStringArray;
      const Layouts: TRadiantResults; const Specs: array of TRadiantSpec; var Job: THeatJob): Boolean;
  end;

implementation

{$R *.lfm}

uses
  LCLIntf, hsDialogSkin, hsSurface;

const
  { Climate zones go by county (a state can hold three), so the list is just
    the numbers and "?" opens the DOE's county-by-county guide to the 2021
    code. Linked, not copied in: its maps belong to the code council. }
  CLIMATE_GUIDE_URL = 'https://www.osti.gov/biblio/1893981';

procedure TRadiantHeatForm.Dress;
var
  I: Integer;
  C: TComponent;
begin
  hsDialogSkin.SkinForm(Self);
  hsDialogSkin.SkinPanel(pnJob, False, 12);
  hsDialogSkin.SkinPanel(pnPlan, False, 12);
  hsDialogSkin.SkinPanel(pnZone, False, 12);
  hsDialogSkin.SkinButton(btnOk, bkGo);
  hsDialogSkin.SkinButton(btnCancel, bkQuiet);
  hsDialogSkin.SkinButton(btnOff, bkPlain);
  hsDialogSkin.SkinButton(btnClimateHelp, bkPlain);
  for I := 0 to ComponentCount - 1 do
  begin
    C := Components[I];
    if C is TSpinEdit then
    begin
      TSpinEdit(C).Color := PixToColor(DlgTheme.Shell2);
      TSpinEdit(C).Font.Color := PixToColor(DlgTheme.Text);
      TSpinEdit(C).Font.Height := -13;
    end
    else if (C is TMemo) or (C is TComboBox) then
    begin
      TWinControl(C).Color := PixToColor(DlgTheme.Shell2);
      TWinControl(C).Font.Color := PixToColor(DlgTheme.Text);
      if C is TComboBox then TComboBox(C).Font.Height := -13;
    end
    else if C is TCheckBox then hsDialogSkin.SkinCheck(TCheckBox(C))
    else if C is TLabel then
    begin
      TLabel(C).Font.Color := PixToColor(DlgTheme.Text);
      TLabel(C).Font.Height := -13;
      TLabel(C).Transparent := True;
    end;
  end;
  lblJobHint.Font.Color := PixToColor(DlgTheme.TextDim);
  lblMethod.Font.Color := PixToColor(DlgTheme.TextDim);
  lblPlanHint.Font.Color := PixToColor(DlgTheme.TextDim);
  memResult.Font.Height := -11;
end;

{ the lists, from the unit's own names - one place says what each is }
procedure TRadiantHeatForm.Fill;
var
  I: Integer;
  U: THeatUse; A: THeatAbove; W: THeatWalls; S: THeatSlabIns; C: THeatCover; T: THeatTight; N: THeatSnow;
begin
  cbClimate.Items.Clear;
  for I := 1 to 8 do cbClimate.Items.Add('Zone ' + IntToStr(I));
  cbUse.Items.Clear; for U := Low(THeatUse) to High(THeatUse) do cbUse.Items.Add(HEAT_USE_NAMES[U]);
  cbAbove.Items.Clear; for A := Low(THeatAbove) to High(THeatAbove) do cbAbove.Items.Add(HEAT_ABOVE_NAMES[A]);
  cbWalls.Items.Clear; for W := Low(THeatWalls) to High(THeatWalls) do cbWalls.Items.Add(HEAT_WALL_NAMES[W]);
  cbSlab.Items.Clear; for S := Low(THeatSlabIns) to High(THeatSlabIns) do cbSlab.Items.Add(HEAT_SLAB_NAMES[S]);
  cbCover.Items.Clear; for C := Low(THeatCover) to High(THeatCover) do cbCover.Items.Add(HEAT_COVER_NAMES[C]);
  cbTight.Items.Clear; for T := Low(THeatTight) to High(THeatTight) do cbTight.Items.Add(HEAT_TIGHT_NAMES[T]);
  cbSnow.Items.Clear; for N := Low(THeatSnow) to High(THeatSnow) do cbSnow.Items.Add(HEAT_SNOW_NAMES[N]);
  cbRun.Items.Clear; for I := 0 to High(HEAT_RUN_NAMES) do cbRun.Items.Add(HEAT_RUN_NAMES[I]);
  cbZone.Items.Clear;
  for I := 0 to High(FZones) do cbZone.Items.Add(FTitles[I]);
end;

procedure TRadiantHeatForm.ShowZone;
var
  HZ: THeatZone;
begin
  if (FSel < 0) or (FSel > High(FJob.Zones)) then Exit;
  HZ := FJob.Zones[FSel];
  FListing := True;
  try
    lblZoneHead.Caption := FTitles[FSel];
    cbZone.ItemIndex := FSel;
    cbUse.ItemIndex := Ord(HZ.Use);
    cbAbove.ItemIndex := Ord(HZ.Above);
    cbWalls.ItemIndex := Ord(HZ.Walls);
    cbSlab.ItemIndex := Ord(HZ.Slab);
    cbCover.ItemIndex := Ord(HZ.Cover);
    cbTight.ItemIndex := Ord(HZ.Tight);
    cbSnow.ItemIndex := Ord(HZ.Snow);
    cbRun.ItemIndex := EnsureRange(HZ.RunIdx, 0, High(HEAT_RUNS));
    edCeiling.Value := Max(1, Round(HZ.CeilingFt));
    edWindows.Value := Round(HZ.WindowSqFt);
    edDoors.Value := Round(HZ.DoorSqFt);
  finally
    FListing := False;
  end;
  { snow melt has no walls, ceiling or glass; a slab over a heated space
    no insulation under it to ask about }
  cbAbove.Enabled := HZ.Use <> huSnowMelt;
  cbWalls.Enabled := HZ.Use <> huSnowMelt;
  cbCover.Enabled := HZ.Use <> huSnowMelt;
  cbTight.Enabled := HZ.Use <> huSnowMelt;
  edCeiling.Enabled := HZ.Use <> huSnowMelt;
  edWindows.Enabled := HZ.Use <> huSnowMelt;
  edDoors.Enabled := HZ.Use <> huSnowMelt;
  cbSlab.Enabled := HZ.Use = huSlab;
  cbSnow.Enabled := HZ.Use = huSnowMelt;
end;

procedure TRadiantHeatForm.ReadJob;
begin
  FJob.OutdoorF := edOutdoor.Value;
  FJob.IndoorF := edIndoor.Value;
  FJob.Climate := cbClimate.ItemIndex + 1;
  FJob.GlycolPct := edGlycol.Value;
  FJob.AltitudeFt := edAltitude.Value;
  FJob.Dhw := cbDhw.Checked;
  FJob.Baths := edBaths.Value;
  edBaths.Enabled := cbDhw.Checked;
end;

procedure TRadiantHeatForm.ReadZone;
begin
  if (FSel < 0) or (FSel > High(FJob.Zones)) then Exit;
  with FJob.Zones[FSel] do
  begin
    Use := THeatUse(Max(0, cbUse.ItemIndex));
    Above := THeatAbove(Max(0, cbAbove.ItemIndex));
    Walls := THeatWalls(Max(0, cbWalls.ItemIndex));
    Slab := THeatSlabIns(Max(0, cbSlab.ItemIndex));
    Cover := THeatCover(Max(0, cbCover.ItemIndex));
    Tight := THeatTight(Max(0, cbTight.ItemIndex));
    Snow := THeatSnow(Max(0, cbSnow.ItemIndex));
    RunIdx := Max(0, cbRun.ItemIndex);
    CeilingFt := edCeiling.Value;
    WindowSqFt := edWindows.Value;
    DoorSqFt := edDoors.Value;
  end;
end;

{ this zone, worked out, and the boiler for them all }
procedure TRadiantHeatForm.Report;
var
  R: THeatZoneResults;
  B: THeatBoiler;
  Z: Integer;
  L: TStringList;
  Lay: TRadiantResult;
  Sp: TRadiantSpec;
begin
  SetLength(R, Length(FZones));
  for Z := 0 to High(FZones) do
  begin
    if Z <= High(FLayouts) then Lay := FLayouts[Z] else Lay := Default(TRadiantResult);
    if Z <= High(FSpecs) then Sp := FSpecs[Z] else Sp := DefaultRadiantSpec;
    R[Z] := HeatZone(FJob, FZones, Z, Lay, Sp);
  end;
  B := HeatBoiler(FJob, R);
  L := TStringList.Create;
  try
    if (FSel >= 0) and (FSel <= High(R)) then
      HeatZoneLines(FJob, FSel, R[FSel], FUnits, L);
    L.Add('');
    HeatBoilerLines(FJob, B, L);
    memResult.Lines.Assign(L);
  finally
    L.Free;
  end;
end;

procedure TRadiantHeatForm.FieldChange(Sender: TObject);
begin
  if FListing then Exit;
  if Sender = cbZone then
  begin
    if cbZone.ItemIndex >= 0 then FSel := cbZone.ItemIndex;
    ShowZone;
  end
  else
  begin
    ReadJob;
    ReadZone;
    ShowZone;
  end;
  Report;
  pbPlan.Invalidate;
end;

{ the zones fitted to the paint box, north up }
procedure TRadiantHeatForm.Fit;
var
  Z, I: Integer;
  P: T2;
  MinV, MaxU: Double;
begin
  if Length(FZones) = 0 then Exit;
  FFrame := RadiantPlanFrame(FZones[0].Outline);
  FMinU := 1E300; MaxU := -1E300; MinV := 1E300; FMaxV := -1E300;
  for Z := 0 to High(FZones) do
    for I := 0 to High(FZones[Z].Outline) do
    begin
      P := RadiantTo2(FFrame, FZones[Z].Outline[I]);
      FMinU := Min(FMinU, P.X); MaxU := Max(MaxU, P.X);
      MinV := Min(MinV, P.Y); FMaxV := Max(FMaxV, P.Y);
    end;
  FScale := Min((pbPlan.Width - 32) / Max(1E-6, MaxU - FMinU), (pbPlan.Height - 32) / Max(1E-6, FMaxV - MinV));
  FX0 := (pbPlan.Width - (MaxU - FMinU) * FScale) / 2;
  FY0 := (pbPlan.Height - (FMaxV - MinV) * FScale) / 2;
end;

function TRadiantHeatForm.ToScreen(const P: TP3): TPoint;
var
  Q: T2;
begin
  Q := RadiantTo2(FFrame, P);
  Result := Point(Round(FX0 + (Q.X - FMinU) * FScale), Round(FY0 + (FMaxV - Q.Y) * FScale));
end;

procedure TRadiantHeatForm.pbPlanPaint(Sender: TObject);
var
  C: TCanvas;
  Z, E, N: Integer;
  Pts: array of TPoint;
  A, B: TPoint;
  Edge: THeatEdge;
  Cx, Cy: Double;
  S: string;
  Shared: Boolean;
begin
  C := pbPlan.Canvas;
  C.Brush.Color := PixToColor(DlgTheme.Shell2);
  C.FillRect(0, 0, pbPlan.Width, pbPlan.Height);
  Fit;
  for Z := 0 to High(FZones) do
  begin
    N := Length(FZones[Z].Outline);
    SetLength(Pts, N);
    for E := 0 to N - 1 do Pts[E] := ToScreen(FZones[Z].Outline[E]);
    if Z = FSel then C.Brush.Color := Shade(PixToColor(DlgTheme.Shell2), 0.15)
    else C.Brush.Color := PixToColor(DlgTheme.Shell2);
    C.Pen.Color := PixToColor(DlgTheme.TextDim);
    C.Pen.Width := 1;
    C.Polygon(Pts);
  end;
  { the walls over the fills: outside blue, to a space not heated
    orange, inside gray }
  for Z := 0 to High(FZones) do
  begin
    N := Length(FZones[Z].Outline);
    for E := 0 to N - 1 do
    begin
      if (Z <= High(FJob.Zones)) and (E <= High(FJob.Zones[Z].Edges)) then Edge := FJob.Zones[Z].Edges[E]
      else Edge := heInside;
      Shared := HeatSharedFt(FZones, Z, E) >= Dist(FZones[Z].Outline[E], FZones[Z].Outline[(E + 1) mod N]) - 0.5;
      if Shared or (Edge = heInside) then Continue;
      A := ToScreen(FZones[Z].Outline[E]);
      B := ToScreen(FZones[Z].Outline[(E + 1) mod N]);
      if Edge = heOutside then C.Pen.Color := $00E09030 else C.Pen.Color := $002090F0;
      C.Pen.Width := 4;
      C.Line(A, B);
    end;
  end;
  C.Pen.Width := 1;
  C.Brush.Style := bsClear;
  C.Font.Color := PixToColor(DlgTheme.Text);
  C.Font.Height := -13;
  for Z := 0 to High(FZones) do
  begin
    Cx := 0; Cy := 0;
    N := Length(FZones[Z].Outline);
    for E := 0 to N - 1 do
    begin
      A := ToScreen(FZones[Z].Outline[E]);
      Cx := Cx + A.X / N; Cy := Cy + A.Y / N;
    end;
    S := IntToStr(Z + 1);
    C.TextOut(Round(Cx) - C.TextWidth(S) div 2, Round(Cy) - C.TextHeight(S) div 2, S);
  end;
  C.Brush.Style := bsSolid;
end;

{ a click near a wall changes it - outside, to a space not heated,
  inside, round again; a click inside a zone opens it }
procedure TRadiantHeatForm.pbPlanMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Z, E, N, BZ, BE: Integer;
  A, B: TPoint;
  D, BD, T, L2: Double;
  Pts: array of TPoint;

  function Inside(const P: array of TPoint): Boolean;
  var
    I, J: Integer;
  begin
    Result := False;
    J := High(P);
    for I := 0 to High(P) do
    begin
      if ((P[I].Y > Y) <> (P[J].Y > Y)) and (X < (P[J].X - P[I].X) * (Y - P[I].Y) / (P[J].Y - P[I].Y) + P[I].X) then
        Result := not Result;
      J := I;
    end;
  end;

begin
  Fit;
  BZ := -1; BE := -1; BD := 7;
  for Z := 0 to High(FZones) do
  begin
    N := Length(FZones[Z].Outline);
    for E := 0 to N - 1 do
    begin
      if HeatSharedFt(FZones, Z, E) >= Dist(FZones[Z].Outline[E], FZones[Z].Outline[(E + 1) mod N]) - 0.5 then Continue;
      A := ToScreen(FZones[Z].Outline[E]);
      B := ToScreen(FZones[Z].Outline[(E + 1) mod N]);
      L2 := Sqr(B.X - A.X) + Sqr(B.Y - A.Y);
      if L2 < 1 then Continue;
      T := EnsureRange(((X - A.X) * (B.X - A.X) + (Y - A.Y) * (B.Y - A.Y)) / L2, 0, 1);
      D := Hypot(X - (A.X + T * (B.X - A.X)), Y - (A.Y + T * (B.Y - A.Y)));
      { the open zone's own walls first, where two lie close }
      if Z = FSel then D := D - 1;
      if D < BD then begin BD := D; BZ := Z; BE := E; end;
    end;
  end;
  if BZ >= 0 then
  begin
    if BE > High(FJob.Zones[BZ].Edges) then SetLength(FJob.Zones[BZ].Edges, Length(FZones[BZ].Outline));
    case FJob.Zones[BZ].Edges[BE] of
      heInside: FJob.Zones[BZ].Edges[BE] := heOutside;
      heOutside: FJob.Zones[BZ].Edges[BE] := heUnheated;
    else FJob.Zones[BZ].Edges[BE] := heInside;
    end;
    FSel := BZ;
  end
  else
    for Z := 0 to High(FZones) do
    begin
      N := Length(FZones[Z].Outline);
      SetLength(Pts, N);
      for E := 0 to N - 1 do Pts[E] := ToScreen(FZones[Z].Outline[E]);
      if Inside(Pts) then FSel := Z;
    end;
  ShowZone;
  Report;
  pbPlan.Invalidate;
end;

procedure TRadiantHeatForm.btnOkClick(Sender: TObject);
begin
  FJob.Enabled := True;
  ModalResult := mrOK;
end;

procedure TRadiantHeatForm.btnOffClick(Sender: TObject);
begin
  FJob.Enabled := False;
  ModalResult := mrOK;
end;

{ A check box's words are a separate label, because Windows draws a check
  box caption in its own color, dark on this dark panel. Clicking the label
  ticks the box. }
procedure TRadiantHeatForm.CheckLabelClick(Sender: TObject);
begin
  if (Sender is TLabel) and (TLabel(Sender).FocusControl is TCheckBox) and TLabel(Sender).FocusControl.Enabled then
    with TCheckBox(TLabel(Sender).FocusControl) do Checked := not Checked;
end;

procedure TRadiantHeatForm.btnClimateHelpClick(Sender: TObject);
begin
  OpenURL(CLIMATE_GUIDE_URL);
end;

procedure TRadiantHeatForm.btnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TRadiantHeatForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    ModalResult := mrCancel;
  end;
end;

class function TRadiantHeatForm.Edit(Units: TUnitSystem; const Zones: TRadiantZones; const Titles: TStringArray;
  const Layouts: TRadiantResults; const Specs: array of TRadiantSpec; var Job: THeatJob): Boolean;
var
  F: TRadiantHeatForm;
  Z, E: Integer;
  G: TIntArray;
begin
  Result := False;
  F := TRadiantHeatForm.Create(nil);
  try
    F.FUnits := Units;
    F.FZones := Zones;
    F.FTitles := Copy(Titles);
    SetLength(F.FTitles, Length(Zones));
    for Z := 0 to High(F.FTitles) do
      if F.FTitles[Z] = '' then F.FTitles[Z] := 'Zone ' + IntToStr(Z + 1);
    F.FLayouts := Layouts;
    SetLength(F.FSpecs, Length(Specs));
    for Z := 0 to High(Specs) do F.FSpecs[Z] := Specs[Z];
    F.FJob := Job;
    { a zone new to the heat load, or its outline changed: its answers
      from the defaults, its walls guessed - outside where no other zone
      shares them }
    SetLength(F.FJob.Zones, Length(Zones));
    for Z := 0 to High(Zones) do
      if Length(F.FJob.Zones[Z].Edges) <> Length(Zones[Z].Outline) then
      begin
        if Z > High(Job.Zones) then F.FJob.Zones[Z] := HeatDefaultZone;
        G := HeatGuessEdges(Zones, Z);
        SetLength(F.FJob.Zones[Z].Edges, Length(G));
        for E := 0 to High(G) do F.FJob.Zones[Z].Edges[E] := THeatEdge(G[E]);
      end;
    F.Dress;
    F.Fill;
    F.FListing := True;
    try
      F.edOutdoor.Value := Round(F.FJob.OutdoorF);
      F.edIndoor.Value := Round(F.FJob.IndoorF);
      F.cbClimate.ItemIndex := EnsureRange(F.FJob.Climate, 1, 8) - 1;
      F.edGlycol.Value := Round(F.FJob.GlycolPct);
      F.edAltitude.Value := Round(F.FJob.AltitudeFt);
      F.cbDhw.Checked := F.FJob.Dhw;
      F.edBaths.Value := EnsureRange(F.FJob.Baths, 1, 8);
    finally
      F.FListing := False;
    end;
    F.edBaths.Enabled := F.FJob.Dhw;
    F.FSel := 0;
    F.ShowZone;
    F.Report;
    if F.ShowModal <> mrOK then Exit;
    Job := F.FJob;
    Result := True;
  finally
    F.Free;
  end;
end;

end.

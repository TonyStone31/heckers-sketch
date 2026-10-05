unit hsStairWizard;

{ The stair dialog: sizes, use, boards, a side view and the code check.  The
  flight stands on two picked lines, or is typed and placed afterward, or sits
  at a known spot (three picked points, or an existing flight being changed).
  Copyright (c) 2026 Tony Stone - MIT, see LICENSE. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, Graphics, Types, Spin, LCLType,
  Dialogs, BCButton, BGRATheme, BGRAThemeCheckBox, hsDrawing, hsStairs, BCComboBox, BCTrackbarUpdown;

type
  { on two picked lines; typed and placed afterward by a click; or at a
    known spot (picked points, or a flight being changed) }
  TStairMode = (smLines, smFree, smPlaced);
  { why the dialog closed: cancel, build, or to pick points and come back }
  TStairAnswer = (saCancel, saBuild, saPick);
  { the dialog's whole state, in and out, so it survives a trip to the
    sheet to pick points }
  TStairJob = record
    Mode: TStairMode;
    LA, LB, HA, HB: TP3;         { the lines, for smLines }
    Frame: TStairFrame;          { the sizes; and where, for smPlaced }
    Spec: TStairSpec;
    Use: TStairUse;
    HaveSpec: Boolean;           { Spec and Use as they were, to be shown again }
    FromUpper: Boolean;          { on lines: the upper one sets the width }
    Editing: Boolean;            { a flight already built, changed in place }
    Note: string;                { for the hint: how the points came }
  end;

  { TStairForm }

  TStairForm = class(TForm)
    btnBuild: TBCButton;
    btnCancel: TBCButton;
    btnPick: TBCButton;
    btnSource: TBCButton;
    btnStringers: TBCButton;
    btnSuggest: TBCButton;
    cbClosed: TBGRAThemeCheckBox;
    cbFrom: TBCComboBox;
    cbRound: TBGRAThemeCheckBox;
    cbUse: TBCComboBox;
    edCount: TBCTrackbarUpdown;
    edNosing: TEdit;
    edRise: TEdit;
    edRun: TEdit;
    edThickness: TEdit;
    edWidth: TEdit;
    lblClosed: TLabel;
    lblCount: TLabel;
    lblFrom: TLabel;
    lblHint: TLabel;
    lblLimit: TLabel;
    lblNosing: TLabel;
    lblNosingHint: TLabel;
    lblRise: TLabel;
    lblRound: TLabel;
    lblRun: TLabel;
    lblSummary: TLabel;
    lblStatus: TLabel;
    lblProblems: TLabel;
    lblThickHint: TLabel;
    lblThickness: TLabel;
    lblTitle: TLabel;
    lblUse: TLabel;
    lblWidth: TLabel;
    memAdvice: TMemo;
    pbSide: TPaintBox;
    sdStringers: TSaveDialog;
    procedure BuildClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure Changed(Sender: TObject);
    procedure CheckLabelClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PaintSide(Sender: TObject);
    procedure PickClick(Sender: TObject);
    procedure SourceClick(Sender: TObject);
    procedure StringersClick(Sender: TObject);
    procedure SuggestClick(Sender: TObject);
  private
    FFrame: TStairFrame;
    FSpec: TStairSpec;
    FUnits: TUnitSystem;
    FReady: Boolean;
    FJob: TStairJob;
    procedure Dress;
    function ReadFrame(out Why: string): Boolean;
    function ReadSpec(out Why: string): Boolean;
  public
    { saBuild: Job holds what to build.  saPick: Job holds what was typed,
      to reopen with once the points are picked. }
    class function Ask(U: TUnitSystem; var Job: TStairJob): TStairAnswer;
  end;

implementation

{$R *.lfm}

uses
  StrUtils, hsDialogSkin, hsSurface, LCLIntf, hsStringerSheet;

procedure TStairForm.Dress;
var
  I: Integer;
  C: TComponent;
begin
  SkinForm(Self);
  SkinButton(btnBuild, bkGo);
  SkinButton(btnCancel, bkQuiet);
  SkinButton(btnSuggest, bkPlain);
  SkinButton(btnSource, bkPlain);
  SkinButton(btnStringers, bkPlain);
  for I := 0 to ComponentCount - 1 do
  begin
    C := Components[I];
    if C is TEdit then SkinEdit(TEdit(C))
    else if C is TBGRAThemeCheckBox then SkinCheck(TBGRAThemeCheckBox(C))
    else if C is TBCComboBox then SkinCombo(TBCComboBox(C))
    else if C is TBCTrackbarUpdown then SkinSpin(TBCTrackbarUpdown(C))
    else if C is TMemo then
    begin
      TWinControl(C).Color := PixToColor(DlgTheme.Shell2);
      TWinControl(C).Font.Color := PixToColor(DlgTheme.Text);
      TWinControl(C).Font.Height := -13;
    end
    else if C is TLabel then
    begin
      TLabel(C).Font.Color := PixToColor(DlgTheme.Text);
      if C <> lblTitle then TLabel(C).Font.Height := -13;
      TLabel(C).Transparent := True;
    end;
  end;
  lblHint.Font.Color := PixToColor(DlgTheme.TextDim);
  lblLimit.Font.Color := PixToColor(DlgTheme.TextDim);
  lblThickHint.Font.Color := PixToColor(DlgTheme.TextDim);
  lblNosingHint.Font.Color := PixToColor(DlgTheme.TextDim);
  lblStatus.Font.Height := -18;
  lblProblems.Font.Color := $004040E8;
  memAdvice.Font.Height := -12;
end;

{ the frame from the lines (the chosen one sets the width) or the typed sizes }
function TStairForm.ReadFrame(out Why: string): Boolean;
var
  Rise, Run, Wide: Double;
begin
  Why := '';
  if FJob.Mode = smLines then
    Exit(StairFrame(FJob.LA, FJob.LB, FJob.HA, FJob.HB, FFrame, Why, cbFrom.ItemIndex = 1));
  Result := False;
  if not ParseLen(edRise.Text, FUnits, Rise) or (Rise <= 0) then begin Why := 'Type the total rise - floor to landing.'; Exit; end;
  if not ParseLen(edRun.Text, FUnits, Run) or (Run <= 0) then begin Why := 'Type the total run - first riser to the landing edge.'; Exit; end;
  if not ParseLen(edWidth.Text, FUnits, Wide) or (Wide <= 0) then begin Why := 'Type the width.'; Exit; end;
  FFrame := StairFrameFree(Rise, Run, Wide);
  { at a known spot the sizes are typed; position and heading are kept }
  if FJob.Mode = smPlaced then
  begin
    FFrame.Bottom := FJob.Frame.Bottom;
    FFrame.Forward := FJob.Frame.Forward;
    FFrame.Across := FJob.Frame.Across;
  end;
  Result := True;
end;

function TStairForm.ReadSpec(out Why: string): Boolean;
begin
  Result := ReadFrame(Why);
  if not Result then Exit;
  FSpec.Risers := edCount.Value;
  FSpec.ClosedRisers := cbClosed.Checked;
  FSpec.Bullnose := cbRound.Checked;
  if not ParseLen(edThickness.Text, FUnits, FSpec.Thickness) then
    begin Why := 'Type the board thickness.'; Exit(False); end;
  if not ParseLen(edNosing.Text, FUnits, FSpec.Nosing) then
    begin Why := 'Type the nosing - 0 for none.'; Exit(False); end;
  Result := StairCheck(FFrame, FSpec, Why);
end;

procedure TStairForm.Changed(Sender: TObject);
var
  Why: string;
  A: TStairAdvice;
  R, G: Double;
begin
  if not FReady then Exit;
  { with lines, the sizes come from them: shown, not typed }
  if (FJob.Mode = smLines) and ((Sender = cbFrom) or (Sender = nil)) and ReadFrame(Why) then
  begin
    FReady := False;
    try
      edRise.Text := FormatLen(FFrame.Rise, FUnits);
      edRun.Text := FormatLen(FFrame.Run, FUnits);
      edWidth.Text := FormatLen(FFrame.Width, FUnits);
    finally
      FReady := True;
    end;
  end;
  btnBuild.Enabled := ReadSpec(Why);
  btnSuggest.Enabled := btnBuild.Enabled or (FJob.Mode <> smLines) or ReadFrame(Why);
  if btnBuild.Enabled then
  begin
    R := FFrame.Rise / FSpec.Risers;
    G := FFrame.Run / (FSpec.Risers - 1);
    lblSummary.Caption := Format('%d risers of %s, %d treads of %s' + LineEnding +
      'Each tread %s deep with its nosing - %.1f degrees',
      [FSpec.Risers, StairMeasure(R, FUnits), FSpec.Risers - 1, StairMeasure(G, FUnits),
       StairLen(G + FSpec.Nosing, FUnits), RadToDeg(ArcTan2(R, G))]);
    A := RecommendStairs(FFrame, FUnits, TStairUse(Max(0, cbUse.ItemIndex)), FSpec);
    memAdvice.Lines.Text := A.Summary;
    { whether it meets the chosen use, with each miss in red }
    if A.CurrentFits then
    begin
      lblStatus.Caption := 'Meets ' + A.Profile;
      lblStatus.Font.Color := $0050C050;
    end
    else
    begin
      lblStatus.Caption := 'Does not meet ' + A.Profile;
      lblStatus.Font.Color := $004040E8;
    end;
    lblProblems.Caption := string.Join(LineEnding, A.Problems);
    if not A.CurrentFits and A.Fits then
      lblProblems.Caption := lblProblems.Caption + LineEnding + 'Suggest finds a count that fits.'
    else if not A.Fits and (FJob.Mode in [smLines, smPlaced]) then
    begin
      { nothing fits between the points: say so and how much more run it
        needs, but never move the points }
      lblStatus.Caption := 'Does not fit between your ' + IfThen(FJob.Mode = smLines, 'lines', 'points');
      lblStatus.Font.Color := $004040E8;
      if A.IdealRun > FFrame.Run then
        lblProblems.Caption := lblProblems.Caption + LineEnding +
          Format('%d risers want %s of run - %s more than you have.', [A.IdealRisers,
            StairLen(A.IdealRun, FUnits), StairLen(A.IdealRun - FFrame.Run, FUnits)])
      else
        lblProblems.Caption := lblProblems.Caption + LineEnding + 'No count of risers fits this rise and run.';
    end;
  end
  else
  begin
    lblStatus.Caption := '';
    lblProblems.Caption := '';
    lblSummary.Caption := Why;
    memAdvice.Lines.Text := '';
  end;
  pbSide.Invalidate;
end;

{ The best riser count for the use.  When typed, the run is set to suit.
  Between picked lines or points the run is never changed: the nearest
  count is used and the dialog says in red that it does not fit. }
procedure TStairForm.SuggestClick(Sender: TObject);
var
  A: TStairAdvice;
  Why: string;
begin
  if not ReadFrame(Why) then Exit;
  FSpec.Risers := edCount.Value;
  A := RecommendStairs(FFrame, FUnits, TStairUse(Max(0, cbUse.ItemIndex)), FSpec);
  FReady := False;
  try
    if FJob.Mode in [smLines, smPlaced] then edCount.Value := A.SuggestedRisers
    else
    begin
      edCount.Value := A.IdealRisers;
      edRun.Text := FormatLen(A.IdealRun, FUnits);
    end;
  finally
    FReady := True;
  end;
  Changed(nil);
end;

{ Saves the stringer sheet (see hsStringerSheet) and opens it in the
  system's PDF reader. }
procedure TStairForm.StringersClick(Sender: TObject);
var
  Why: string;
begin
  if not ReadSpec(Why) then
  begin
    lblSummary.Caption := Why;
    Exit;
  end;
  sdStringers.FileName := 'stairs - stringer sheet.pdf';
  if not sdStringers.Execute then Exit;
  try
    StringerSheetPdf(FFrame, FSpec, TStairUse(Max(0, cbUse.ItemIndex)), FUnits, 'Stairs', sdStringers.FileName);
    OpenDocument(sdStringers.FileName);
  except
    on E: Exception do lblSummary.Caption := 'Could not write it: ' + E.Message;
  end;
end;

procedure TStairForm.SourceClick(Sender: TObject);
begin
  case TStairUse(Max(0, cbUse.ItemIndex)) of
    suResidential: OpenURL('https://codes.iccsafe.org/content/IRC2021P2/chapter-3-building-planning');
    suService: OpenURL('https://www.osha.gov/laws-regs/regulations/standardnumber/1910/1910.25');
    suGeneral, suEgress: OpenURL('https://codes.iccsafe.org/content/IBC2024V2.0/chapter-10-means-of-egress');
  else OpenURL('https://www.access-board.gov/ada/guides/chapter-5-stairways/');
  end;
end;

procedure TStairForm.PaintSide(Sender: TObject);
var
  C: TCanvas;
  K, R, G, X, Z, Radius, A: Double;
  I, J: Integer;
  Why: string;
  P: array[0..10] of TPoint;

  function SX(V: Double): Integer; begin Result := 24 + Round((V + FSpec.Nosing) * K); end;
  function SY(V: Double): Integer; begin Result := pbSide.Height - 22 - Round(V * K); end;

begin
  C := pbSide.Canvas;
  C.Brush.Color := PixToColor(DlgTheme.Shell2);
  C.FillRect(pbSide.ClientRect);
  if not FReady or not ReadSpec(Why) then Exit;
  K := Min((pbSide.Width - 50) / (FFrame.Run + FSpec.Nosing + FSpec.Thickness), (pbSide.Height - 45) / FFrame.Rise);
  R := FFrame.Rise / FSpec.Risers;
  G := FFrame.Run / (FSpec.Risers - 1);
  C.Pen.Color := PixToColor(DlgTheme.Text);
  C.Brush.Color := PixToColor(DlgTheme.Accent);
  for I := 0 to FSpec.Risers - 2 do
  begin
    X := I * G; Z := (I + 1) * R;
    if not FSpec.Bullnose then
      C.Rectangle(SX(X - FSpec.Nosing), SY(Z), SX(X + G), SY(Z - FSpec.Thickness))
    else
    begin
      Radius := FSpec.Thickness / 2;
      P[0] := Point(SX(X + G), SY(Z - FSpec.Thickness));
      for J := 0 to 8 do
      begin
        A := -Pi / 2 - J * Pi / 8;
        P[J + 1] := Point(SX(X - FSpec.Nosing + Radius + Radius * Cos(A)), SY(Z - Radius + Radius * Sin(A)));
      end;
      P[10] := Point(SX(X + G), SY(Z));
      C.Polygon(P);
    end;
  end;
  if FSpec.ClosedRisers then
    for I := 0 to FSpec.Risers - 1 do
    begin
      Z := (I + 1) * R;
      if I < FSpec.Risers - 1 then Z := Z - FSpec.Thickness;
      C.Rectangle(SX(I * G), SY(Z), SX(I * G + FSpec.Thickness), SY(I * R));
    end;
  { the floor and the landing }
  C.Pen.Width := 2;
  C.MoveTo(SX(FFrame.Run), SY(FFrame.Rise)); C.LineTo(pbSide.Width - 4, SY(FFrame.Rise));
  C.MoveTo(4, SY(0)); C.LineTo(SX(0), SY(0));
  C.Pen.Width := 1;
  C.Brush.Style := bsClear;
  C.Font.Color := PixToColor(DlgTheme.TextDim);
  C.Font.Height := -12;
  C.TextOut(8, 4, 'From the side - the landing at the top right is the last step');
  C.Brush.Style := bsSolid;
end;

{ Pick on the drawing: keep what is typed, go pick three points, and the
  dialog reopens on them }
procedure TStairForm.PickClick(Sender: TObject);
var
  Why: string;
begin
  ReadSpec(Why);
  FJob.Frame := FFrame;
  FJob.Spec := FSpec;
  FJob.Use := TStairUse(Max(0, cbUse.ItemIndex));
  FJob.FromUpper := cbFrom.ItemIndex = 1;
  FJob.HaveSpec := True;
  ModalResult := mrRetry;
end;

{ Check box captions are separate labels because Windows draws the box's own
  caption dark on this dark panel.  A click on the label ticks the box. }
procedure TStairForm.CheckLabelClick(Sender: TObject);
begin
  if (Sender is TLabel) and (TLabel(Sender).FocusControl is TBGRAThemeCheckBox) and TLabel(Sender).FocusControl.Enabled then
    with TBGRAThemeCheckBox(TLabel(Sender).FocusControl) do Checked := not Checked;
end;

procedure TStairForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    ModalResult := mrCancel;
  end;
end;

procedure TStairForm.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

{ drawn buttons carry no ModalResult of their own }
procedure TStairForm.BuildClick(Sender: TObject);
var
  Why: string;
begin
  if ReadSpec(Why) then ModalResult := mrOK else Changed(nil);
end;

class function TStairForm.Ask(U: TUnitSystem; var Job: TStairJob): TStairAnswer;
var
  F: TStairForm;
  Inch: Double;
  Why: string;
  A: TStairAdvice;
  R: TModalResult;
begin
  Result := saCancel;
  F := TStairForm.Create(nil);
  try
    F.FUnits := U;
    F.FJob := Job;
    F.Dress;
    if U = usImperial then Inch := 1 / 12 else Inch := 0.0254;
    if Job.Editing then
    begin
      F.Caption := 'Stairs - changing a flight';
      F.lblTitle.Caption := 'Change the stairs';
      F.btnBuild.Caption := 'Build again';
    end;
    case Job.Mode of
      smLines:
        begin
          { which line sets the width, each with its length }
          F.cbFrom.Items.Clear;
          if (Job.LA.Z + Job.LB.Z) <= (Job.HA.Z + Job.HB.Z) then
          begin
            F.cbFrom.Items.Add('The lower line - ' + FormatLen(Dist(Job.LA, Job.LB), U));
            F.cbFrom.Items.Add('The upper line - ' + FormatLen(Dist(Job.HA, Job.HB), U));
          end
          else
          begin
            F.cbFrom.Items.Add('The lower line - ' + FormatLen(Dist(Job.HA, Job.HB), U));
            F.cbFrom.Items.Add('The upper line - ' + FormatLen(Dist(Job.LA, Job.LB), U));
          end;
          F.cbFrom.ItemIndex := Ord(Job.FromUpper);
          F.lblHint.Caption := 'On the two lines picked: the lower where the first riser stands, the upper at the ' +
            'landing''s edge.  Up from the lower line, or down from the upper.';
          F.edRise.Enabled := False; F.edRun.Enabled := False; F.edWidth.Enabled := False;
          if not F.ReadFrame(Why) then F.FFrame := StairFrameFree(8, 10, 3);
        end;
      smFree, smPlaced:
        begin
          F.cbFrom.Visible := False; F.lblFrom.Visible := False;
          if Job.Mode = smPlaced then
            F.lblHint.Caption := IfThen(Job.Note <> '', Job.Note + '  ', '') +
              'Built where it stands.  Suggest keeps your points and picks the steps that fit them.'
          else
            F.lblHint.Caption := 'Type how high it climbs and how wide it is; Suggest works out the steps and the run.  ' +
              'It is placed on the drawing after, where you click - or Pick on the drawing first.';
          if Job.HaveSpec or (Job.Mode = smPlaced) then
          begin
            F.edRise.Text := FormatLen(Job.Frame.Rise, U);
            F.edWidth.Text := FormatLen(Job.Frame.Width, U);
            F.edRun.Text := FormatLen(Job.Frame.Run, U);
          end
          else
          begin
            F.edRise.Text := FormatLen(96 * Inch, U);
            F.edWidth.Text := FormatLen(36 * Inch, U);
            F.edRun.Text := FormatLen(126 * Inch, U);
          end;
          F.ReadFrame(Why);
        end;
    end;
    if Job.HaveSpec then F.FSpec := Job.Spec
    else F.FSpec := StairDefaults(F.FFrame, U);
    if Job.HaveSpec then F.cbUse.ItemIndex := Ord(Job.Use);
    F.edCount.Value := F.FSpec.Risers;
    F.edThickness.Text := FormatLen(F.FSpec.Thickness, U);
    F.edNosing.Text := FormatLen(F.FSpec.Nosing, U);
    F.cbClosed.Checked := F.FSpec.ClosedRisers;
    F.cbRound.Checked := F.FSpec.Bullnose;
    F.FReady := True;
    { a new typed flight starts with a house's count and run }
    if (Job.Mode = smFree) and not Job.HaveSpec then
    begin
      A := RecommendStairs(F.FFrame, U, suResidential, F.FSpec);
      F.FReady := False;
      F.edCount.Value := A.IdealRisers;
      F.edRun.Text := FormatLen(A.IdealRun, U);
      F.FReady := True;
    end;
    F.Changed(nil);
    R := F.ShowModal;
    { hand back the state as it was left }
    Job := F.FJob;
    if R = mrRetry then Exit(saPick);
    if R <> mrOK then Exit;
    Job.Frame := F.FFrame;
    Job.Spec := F.FSpec;
    Job.Use := TStairUse(Max(0, F.cbUse.ItemIndex));
    Job.FromUpper := F.cbFrom.ItemIndex = 1;
    Result := saBuild;
  finally
    F.Free;
  end;
end;

end.

unit hsRadiantBusy;

{ The window a radiant layout search shows while it works: stage, detail,
  progress bar, the layouts found so far, and Stop.  It is modal over the
  wizard and runs the search from inside (OnWork): on GTK a modal window
  takes every click, so a plain window over the modal wizard could not be
  stopped. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ComCtrls, ExtCtrls, Graphics, Spin,
  LCLType, BCButton, BGRATheme, BGRAThemeCheckBox, hsDialogSkin, BCComboBox;

type
  { draws a layout the search has found into the preview: the one whose
    list line is Picked, or the best so far when that is '' }
  TRadiantPreviewEvent = procedure(C: TCanvas; W, H: Integer; const Picked: string) of object;

  { TRadiantBusyForm }

  TRadiantBusyForm = class(TForm)
    btnStop: TBCButton;
    btnStopAll: TBCButton;
    cbGiveUp: TBCComboBox;
    cbBusyLess: TBGRAThemeCheckBox;
    cbBusyHooks: TBGRAThemeCheckBox;
    lblBusyLess: TLabel;
    lblBusyHooks: TLabel;
    edBusyCover: TSpinEdit;
    edBusyEven: TSpinEdit;
    lblBusyCover: TLabel;
    lblBusyEven: TLabel;
    lblDetail: TLabel;
    lblFound: TLabel;
    lblGiveUp: TLabel;
    lblGoals: TLabel;
    lblPreview: TLabel;
    pbPreview: TPaintBox;
    lblStage: TLabel;
    lbFound: TListBox;
    pbProgress: TProgressBar;
    tmrStart: TTimer;
    procedure btnStopClick(Sender: TObject);
    procedure btnStopAllClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure lbFoundClick(Sender: TObject);
    procedure CheckLabelClick(Sender: TObject);
    procedure lbFoundDblClick(Sender: TObject);
    procedure pbPreviewPaint(Sender: TObject);
    procedure tmrStartTimer(Sender: TObject);
  private
    { the picked line, by its text - the list is rebuilt and reordered every
      time the search finds another, and the pick follows it }
    FPicked: string;
    procedure CaptionPreview;
  public
    { Stop: the current zone keeps its best and the next zone starts. The
      search reads it between tries; the caller clears it for the next zone.
      Stop all: that, and no more zones. }
    Stopping, StoppingAll: Boolean;
    { the search, run once the window is up; the window closes when it returns }
    OnWork: TNotifyEvent;
    { draws the picked layout (or the best so far) live beside the list }
    OnPreview: TRadiantPreviewEvent;
    constructor CreateBusy(AOwner: TCustomForm);
    { ready for the next zone: Stop can be pressed again }
    procedure NextZone;
    procedure Stage(const AStage, ADetail: string; Percent: Integer);
    { the solutions found so far, best first, one line each; the picked line
      stays picked while the list changes under it }
    procedure ShowFound(const Lines: array of string);
    { the picked line, '' for none - the caller matches it to what it kept }
    function Picked: string;
    { the goals, editable during the search, and how long a zone may run.
      A goal box that does not hold a number leaves that goal as it was. }
    procedure SetGoals(CoverPct, EvenPct: Double);
    procedure ReadGoals(var CoverPct, EvenPct: Double);
    { seconds a zone is searched before giving up with its best, 0 for never }
    function GiveUpSecs: Integer;
    { pump messages this long, so what was just put up is painted }
    procedure Settle(Milliseconds: QWord);
  end;

implementation

{$R *.lfm}

constructor TRadiantBusyForm.CreateBusy(AOwner: TCustomForm);
begin
  inherited Create(AOwner);
  Stopping := False; StoppingAll := False;
  FPicked := '';
  PopupMode := pmExplicit;
  PopupParent := AOwner;
end;

{ in the same theme as the wizard behind it }
procedure TRadiantBusyForm.FormCreate(Sender: TObject);
begin
  hsDialogSkin.ThemeForm(Self);
end;

{ A drawn button cannot be the cancel button, so Escape is handled here:
  it stops this zone, keeping the best so far, while there is anything to stop. }
procedure TRadiantBusyForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    if btnStop.Enabled then btnStopClick(btnStop);
    Key := 0;
  end;
end;

procedure TRadiantBusyForm.FormShow(Sender: TObject);
begin
  tmrStart.Enabled := True;
end;

procedure TRadiantBusyForm.tmrStartTimer(Sender: TObject);
begin
  tmrStart.Enabled := False;
  { a new window is mapped and painted over several turns of the message
    loop; pumped only once, the search started over an empty frame }
  Settle(100);
  try
    if Assigned(OnWork) then OnWork(Self);
  finally
    ModalResult := mrOK;
  end;
end;

procedure TRadiantBusyForm.Settle(Milliseconds: QWord);
var
  UntilTick: QWord;
begin
  UntilTick := GetTickCount64 + Milliseconds;
  repeat
    Application.ProcessMessages;
    Sleep(5);
  until GetTickCount64 >= UntilTick;
end;

procedure TRadiantBusyForm.Stage(const AStage, ADetail: string; Percent: Integer);
begin
  lblStage.Caption := AStage;
  lblDetail.Caption := ADetail;
  pbProgress.Position := Percent;
  Repaint;
  Application.ProcessMessages;
end;

procedure TRadiantBusyForm.NextZone;
begin
  Stopping := StoppingAll;
  btnStop.Enabled := not StoppingAll;
  FPicked := '';
  lbFound.Items.Clear;
  lblPreview.Caption := 'The best so far - click a layout in the list to see it';
  pbPreview.Invalidate;
end;

procedure TRadiantBusyForm.CaptionPreview;
begin
  if (FPicked <> '') and (lbFound.ItemIndex >= 0) then
    lblPreview.Caption := Format('The one picked - number %d in the list', [lbFound.ItemIndex + 1])
  else lblPreview.Caption := 'The best so far - click a layout in the list to see it';
end;

procedure TRadiantBusyForm.pbPreviewPaint(Sender: TObject);
begin
  pbPreview.Canvas.Brush.Color := clWhite;
  pbPreview.Canvas.FillRect(0, 0, pbPreview.Width, pbPreview.Height);
  pbPreview.Canvas.Pen.Color := clSilver;
  pbPreview.Canvas.Brush.Style := bsClear;
  pbPreview.Canvas.Rectangle(0, 0, pbPreview.Width, pbPreview.Height);
  if Assigned(OnPreview) then OnPreview(pbPreview.Canvas, pbPreview.Width, pbPreview.Height, FPicked);
end;

procedure TRadiantBusyForm.ShowFound(const Lines: array of string);
var
  I: Integer;
  Same: Boolean;
begin
  Same := lbFound.Items.Count = Length(Lines);
  if Same then
    for I := 0 to High(Lines) do
      if lbFound.Items[I] <> Lines[I] then begin Same := False; Break; end;
  if Same then Exit;
  lbFound.Items.BeginUpdate;
  try
    lbFound.Items.Clear;
    for I := 0 to High(Lines) do lbFound.Items.Add(Lines[I]);
    lbFound.ItemIndex := lbFound.Items.IndexOf(FPicked);
  finally
    lbFound.Items.EndUpdate;
  end;
  { the picked one may have moved or dropped off the list (then the best so
    far shows), and the best so far may have changed }
  if lbFound.ItemIndex < 0 then FPicked := '';
  CaptionPreview;
  pbPreview.Invalidate;
end;

function TRadiantBusyForm.Picked: string;
begin
  Result := FPicked;
end;

procedure TRadiantBusyForm.SetGoals(CoverPct, EvenPct: Double);
begin
  edBusyCover.Value := Round(CoverPct);
  edBusyEven.Value := Round(EvenPct);
end;

procedure TRadiantBusyForm.ReadGoals(var CoverPct, EvenPct: Double);
var
  V: Double;
begin
  V := edBusyCover.Value;
  if (V >= 0) and (V <= 100) then CoverPct := V;
  V := edBusyEven.Value;
  if (V >= 0) and (V <= 100) then EvenPct := V;
end;

{ A check box's words are a separate label, because Windows draws a check
  box caption in its own color, dark on this dark panel. Clicking the label
  ticks the box. }
procedure TRadiantBusyForm.CheckLabelClick(Sender: TObject);
begin
  if (Sender is TLabel) and (TLabel(Sender).FocusControl is TBGRAThemeCheckBox) and TLabel(Sender).FocusControl.Enabled then
    with TBGRAThemeCheckBox(TLabel(Sender).FocusControl) do Checked := not Checked;
end;

function TRadiantBusyForm.GiveUpSecs: Integer;
const
  SECS: array[0..5] of Integer = (0, 60, 300, 900, 1800, 3600);
begin
  if (cbGiveUp.ItemIndex >= 0) and (cbGiveUp.ItemIndex <= High(SECS)) then Result := SECS[cbGiveUp.ItemIndex]
  else Result := 0;
end;

procedure TRadiantBusyForm.lbFoundClick(Sender: TObject);
begin
  if lbFound.ItemIndex >= 0 then FPicked := lbFound.Items[lbFound.ItemIndex]
  else FPicked := '';
  CaptionPreview;
  pbPreview.Invalidate;
end;

{ this one, and no more searching this zone }
procedure TRadiantBusyForm.lbFoundDblClick(Sender: TObject);
begin
  lbFoundClick(Sender);
  if FPicked <> '' then btnStopClick(Sender);
end;

procedure TRadiantBusyForm.btnStopAllClick(Sender: TObject);
begin
  StoppingAll := True;
  btnStopAll.Enabled := False;
  btnStopClick(Sender);
end;

procedure TRadiantBusyForm.btnStopClick(Sender: TObject);
begin
  Stopping := True;
  btnStop.Enabled := False;
  lblDetail.Caption := 'Stopping after the layout it is on - the best so far is kept...';
end;

end.

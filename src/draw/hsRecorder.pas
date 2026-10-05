unit hsRecorder;

{ The recording window for the little film.  It records the camera position
  over time, not pictures; the film is rendered afterwards at any size, with
  no cursor or snap marks in it.  The move is either pointed by hand or one of
  the canned walks in hsFilm, turning about the middle of the selection.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, Graphics, Controls, Forms, ExtCtrls,
  StdCtrls, LCLType, BCPanel, BCLabel, BCButton,
  hsSurface, hsDrawing, hsSkin, hsDialogSkin, hsFilm, BCComboBox;

{ Recently used moves, most recent first, as a comma list of TWalk ordinals.
  The caller saves it between sessions (see LoadSettings). }
var
  RecentWalks: string = '';

{ Open the recording room.  True if a clip was made and kept. }
function RecordMove(Doc: TWorkDoc; const Start: TProjector; U: TUnitSystem;
  AFont: TFont; const LabelCol: TPix; EdgeW: Single; SrcW, SrcH: Integer;
  Axes: Boolean; const Pivot: TP3; out Cam: TCamPath): Boolean;

implementation

{$R *.lfm}

const
  SAMPLE_HZ = 30;         { how often the camera is written down }
  { the preview is redrawn less often, since drawing the model is the slow part }
  PAINT_MS  = 55;
  READY_FOR = 3;          { seconds of counting you in }
  STRIP_N   = 16;         { snapshots along the bottom }
  STRIP_W   = 96;
  STRIP_H   = 72;

type
  { where the camera starts, before any move }
  TStartView = (svHere, svFront, svBack, svLeft, svRight, svTop,
                svIsoFL, svIsoFR, svIsoBL, svIsoBR);

const
  START_NAME: array[TStartView] of string =
    ('Where I am now', 'Front', 'Back', 'Left', 'Right', 'Top',
     'Corner - front left', 'Corner - front right',
     'Corner - back left', 'Corner - back right');
  { azimuth and elevation for each, in radians }
  START_AZ: array[TStartView] of Double =
    (0, 0, Pi, -Pi/2, Pi/2, 0, -Pi/4, Pi/4, -3*Pi/4, 3*Pi/4);
  START_EL: array[TStartView] of Double =
    (0, 0.08, 0.08, 0.08, 0.08, 1.45, 0.62, 0.62, 0.62, 0.62);

type
  TRecordWin = class(TForm)
    { what the move is, along the top }
    pnlBar: TBCPanel;
    lblTitle: TBCLabel;
    lblStartFrom: TBCLabel;
    cbStart: TBCComboBox;
    lblMove: TBCLabel;
    cbWalk: TBCComboBox;
    lblLong: TBCLabel;
    cbLen: TBCComboBox;
    btnGo: TBCButton;
    btnStop: TBCButton;
    lblTell: TBCLabel;
    { the model }
    pbView: TPaintBox;
    { the clip, along the bottom }
    pnlFoot: TBCPanel;
    pbFilm: TPaintBox;
    lblClip: TBCLabel;
    btnPlay: TBCButton;
    btnClear: TBCButton;
    btnTake: TBCButton;
    btnDrop: TBCButton;
    tmrTick: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure PaintView(Sender: TObject);
    procedure PaintFilm(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure Move_(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure Up(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure Wheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    procedure KeyDownH(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure BarDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure BarMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BarUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure StartPicked(Sender: TObject);
    procedure DoGo(Sender: TObject);
    procedure DoStop(Sender: TObject);
    procedure DoPlay(Sender: TObject);
    procedure DoClear(Sender: TObject);
    procedure DoTake(Sender: TObject);
    procedure DoDrop(Sender: TObject);
  private
    FDoc: TWorkDoc;
    FUnits: TUnitSystem;
    FFont: TFont;
    FLabelCol: TPix;
    FEdgeW: Single;
    FSrcW, FSrcH: Integer;
    FAxes: Boolean;
    FPivot: TP3;
    FHome: TProjector;        { what the drawing was showing when we opened }

    FView: TProjector;
    FCam: TCamPath;
    FN: Integer;
    FKept: Boolean;

    { rolling }
    FRolling: Boolean;
    FCount: Double;
    FElapsed: Double;
    { Timing runs off the wall clock, not a tick count.  The timer falls
      behind on a big drawing, and counting ticks then stretches the count-in
      and stamps the wrong times on the recording, so the film comes out jumpy. }
    FClock: QWord;
    FPainted: QWord;
    { one preview surface, kept; a new one per frame churns megabytes a
      second and makes the whole program sluggish }
    FCanvasS: TArtSurface;
    FPlaying: Boolean;
    FPlayT: Double;

    { the strip along the bottom }
    FStrip: array[0..STRIP_N - 1] of TBitmap;
    FStripN: Integer;
    { what each row of the walk list means: -1 free hand, -2 the divider,
      otherwise the ordinal of a TWalk }
    FWalkOf: array of Integer;

    FDrag, FPan: Boolean;
    FDX, FDY: Integer;
    { dragging the window by its top bar, since it draws its own frame }
    FWinDrag: hsDialogSkin.TFormDrag;

    procedure Repaint_;
    procedure FillWalks;
    function ChosenWalk(out K: TWalk): Boolean;
    procedure Remember(K: TWalk);
    procedure Grab;
    procedure Shelve;
    procedure Refresh_;
    function Seconds: Double;
    function FreeHand: Boolean;
    function Frame(W, H: Integer): TProjector;
    { called once the fields are filled in, before the window is shown }
    procedure Setup;
  end;

procedure TRecordWin.FormDestroy(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to STRIP_N - 1 do FreeAndNil(FStrip[I]);
  FreeAndNil(FCanvasS);
end;

function TRecordWin.Seconds: Double;
begin
  case cbLen.ItemIndex of
    0: Result := 3;
    1: Result := 5;
    2: Result := 8;
  else Result := 12;
  end;
end;

function TRecordWin.FreeHand: Boolean;
var
  K: TWalk;
begin
  Result := not ChosenWalk(K);
end;

{ The view fitted to a W by H picture.  The stored view stays in the
  drawing's terms so the window and the film share one camera. }
function TRecordWin.Frame(W, H: Integer): TProjector;
begin
  Result := Fitted(FView, FSrcW, FSrcH, W, H);
end;

procedure TRecordWin.FormCreate(Sender: TObject);
var
  V: TStartView;
  I: Integer;
  Field: TColor;
begin
  hsDialogSkin.ThemeForm(Self);
  hsDialogSkin.SkinPanel(pnlBar, True, 12);
  hsDialogSkin.SkinPanel(pnlFoot, False, 12);
  for V := Low(TStartView) to High(TStartView) do
    cbStart.Items.Add(START_NAME[V]);
  cbStart.ItemIndex := 0;
  tmrTick.Interval := Round(1000 / SAMPLE_HZ);
end;

{ Fills the move list and sets the start view; both need the fields that
  RecordMove sets after the form is created. }
procedure TRecordWin.Setup;
begin
  FillWalks;
  tmrTick.Enabled := True;
  StartPicked(nil);
end;

{ The move list: up to three recent moves, a divider, then every move in
  its usual order. }
procedure TRecordWin.FillWalks;
var
  K: TWalk;
  L: TStringList;
  I, N: Integer;

  procedure Row(const Cap: string; Means: Integer);
  begin
    cbWalk.Items.Add(Cap);
    SetLength(FWalkOf, Length(FWalkOf) + 1);
    FWalkOf[High(FWalkOf)] := Means;
  end;

begin
  cbWalk.Items.Clear;
  SetLength(FWalkOf, 0);
  Row('I will point it myself', -1);

  L := TStringList.Create;
  try
    L.CommaText := RecentWalks;
    N := 0;
    for I := 0 to L.Count - 1 do
    begin
      if N >= 3 then Break;
      if (StrToIntDef(L[I], -1) < 0) or
         (StrToIntDef(L[I], -1) > Ord(High(TWalk))) then Continue;
      Row(WALK_NAME[TWalk(StrToInt(L[I]))], StrToInt(L[I]));
      Inc(N);
    end;
    if N > 0 then Row('- - - - - - - - - - - - -', -2);
  finally
    L.Free;
  end;

  for K := Low(TWalk) to High(TWalk) do Row(WALK_NAME[K], Ord(K));
  { select the first real move, which is the most recent one if any }
  if Length(FWalkOf) > 1 then cbWalk.ItemIndex := 1
  else cbWalk.ItemIndex := 0;
end;

function TRecordWin.ChosenWalk(out K: TWalk): Boolean;
var
  I, M: Integer;
begin
  Result := False;
  I := cbWalk.ItemIndex;
  if (I < 0) or (I > High(FWalkOf)) then Exit;
  M := FWalkOf[I];
  if M < 0 then Exit;
  K := TWalk(M);
  Result := True;
end;

{ Put this one at the front of the recent list, keeping the rest in order and
  dropping any repeat of it. }
procedure TRecordWin.Remember(K: TWalk);
var
  L, Out_: TStringList;
  I: Integer;
begin
  L := TStringList.Create;
  Out_ := TStringList.Create;
  try
    Out_.Add(IntToStr(Ord(K)));
    L.CommaText := RecentWalks;
    for I := 0 to L.Count - 1 do
      if (StrToIntDef(L[I], -1) <> Ord(K)) and (Out_.Count < 6) and
         (StrToIntDef(L[I], -1) >= 0) and
         (StrToIntDef(L[I], -1) <= Ord(High(TWalk))) then
        Out_.Add(L[I]);
    RecentWalks := Out_.CommaText;
  finally
    Out_.Free;
    L.Free;
  end;
end;

{ Put the camera where the start view says, aimed at the middle of what was
  selected and pulled back far enough to hold it. }
procedure TRecordWin.StartPicked(Sender: TObject);
var
  V: TStartView;
begin
  { the line between the recent ones and the rest is not a move }
  if (Sender = cbWalk) and (cbWalk.ItemIndex >= 0) and
     (cbWalk.ItemIndex <= High(FWalkOf)) and
     (FWalkOf[cbWalk.ItemIndex] = -2) then
  begin
    cbWalk.ItemIndex := cbWalk.ItemIndex + 1;
    if cbWalk.ItemIndex > High(FWalkOf) then cbWalk.ItemIndex := 0;
  end;
  V := TStartView(Max(0, Min(Ord(High(TStartView)), cbStart.ItemIndex)));
  if V = svHere then
    FView := FHome
  else
  begin
    FView := FHome;
    FView.Kind := vkOrbit;
    FView.Az := START_AZ[V];
    FView.El := START_EL[V];
  end;
  { whatever the angle, the thing being looked at sits in the middle }
  HoldAt(FView, FPivot, FSrcW / 2, FSrcH / 2);
  Refresh_;
end;

procedure TRecordWin.Refresh_;
begin
  if FreeHand then
    lblTell.Caption := 'Point it yourself'
  else
    lblTell.Caption := Format('%.0f seconds', [Seconds]);
  if FN >= 2 then
    lblClip.Caption := Format('A clip of %.1f seconds.  Play it, or use it.',
      [CamPathLength(FCam)])
  else if FRolling then
    lblClip.Caption := 'Recording...'
  else
    lblClip.Caption := 'No clip yet.  Pick a move and press Record.';
  btnPlay.Visible := FN >= 2;
  btnClear.Visible := FN >= 2;
  btnTake.Visible := FN >= 2;
  pbView.Invalidate;
  pbFilm.Invalidate;
end;

{ Seconds since a mark on the clock. }
function Since(Mark: QWord): Double;
var
  Now_: QWord;
begin
  Now_ := GetTickCount64;
  if Now_ <= Mark then Result := 0
  else Result := (Now_ - Mark) / 1000;
end;

procedure TRecordWin.Grab;
begin
  if FN >= Length(FCam) then SetLength(FCam, Max(64, FN * 2));
  FCam[FN].T := FElapsed;
  FCam[FN].V := FView;
  Inc(FN);
end;

{ A snapshot for the strip along the bottom, so you can see the clip filling. }
procedure TRecordWin.Shelve;
var
  S: TArtSurface;
  Slot: Integer;
begin
  Slot := Min(STRIP_N - 1, Trunc(FElapsed / Max(0.001, Seconds) * STRIP_N));
  if Slot < FStripN then Exit;
  S := ShootFrame(FDoc, Fitted(FView, FSrcW, FSrcH, STRIP_W, STRIP_H),
    STRIP_W, STRIP_H, FUnits, FFont, FLabelCol, FEdgeW, Pix(255, 255, 255),
    True);
  try
    if FStrip[Slot] = nil then FStrip[Slot] := TBitmap.Create;
    FStrip[Slot].Assign(S.AsBitmap);
  finally
    S.Free;
  end;
  FStripN := Slot + 1;
  pbFilm.Invalidate;
end;

procedure TRecordWin.Tick(Sender: TObject);
var
  Step: Double;
  Kind: TWalk;
begin
  if FPlaying then
  begin
    Step := Since(FClock) / Max(0.2, CamPathLength(FCam));
    FPlayT := Step;
    if FPlayT > 1 then
    begin
      FPlayT := 0;
      FClock := GetTickCount64;
    end;
    Repaint_;
    Exit;
  end;

  if FCount > 0 then
  begin
    Step := READY_FOR - Since(FClock);
    FCount := Step;
    if FCount <= 0 then
    begin
      FCount := 0;
      FRolling := True;
      FElapsed := 0;
      FClock := GetTickCount64;
      lblTitle.Caption := 'Recording';
      Grab;
      Shelve;
      Refresh_;
    end;
    Repaint_;
    Exit;
  end;

  if not FRolling then Exit;
  Step := Since(FClock);
  FElapsed := Step;
  { a canned walk drives the camera; a free hand has already moved it }
  if ChosenWalk(Kind) then
    FView := WalkAt(Kind, FHome, FPivot, FSrcW / 2, FSrcH / 2,
      FElapsed / Max(0.2, Seconds));
  Grab;
  Shelve;
  if FElapsed >= Min(Seconds, FILM_MAX_SECONDS) then
  begin
    DoStop(nil);
    Exit;
  end;
  Repaint_;
end;

{ The camera is sampled at SAMPLE_HZ, but the preview is only redrawn every
  PAINT_MS; redrawing a big drawing on every tick stalls the whole program. }
procedure TRecordWin.Repaint_;
begin
  if GetTickCount64 - FPainted < PAINT_MS then Exit;
  FPainted := GetTickCount64;
  pbView.Invalidate;
end;

procedure TRecordWin.PaintView(Sender: TObject);
var
  S: TArtSurface;
  V: TProjector;
  C: TCanvas;
  Txt: string;
begin
  if FPlaying and (FN >= 2) then
    V := Fitted(SampleCamPath(FCam, FPlayT * CamPathLength(FCam)),
      FSrcW, FSrcH, pbView.Width, pbView.Height)
  else
    V := Frame(pbView.Width, pbView.Height);

  { the same surface every time, unless the window has been resized }
  if (FCanvasS <> nil) and ((FCanvasS.Width <> pbView.Width) or
     (FCanvasS.Height <> pbView.Height)) then FreeAndNil(FCanvasS);
  if FCanvasS = nil then
    FCanvasS := TArtSurface.Create(Max(1, pbView.Width), Max(1, pbView.Height));
  S := FCanvasS;
  ShootInto(S, FDoc, V, FUnits, FFont, FLabelCol, FEdgeW,
    Pix(255, 255, 255), FDrag or FPan or FRolling or FPlaying, FAxes);
  pbView.Canvas.Draw(0, 0, S.AsBitmap);

  C := pbView.Canvas;
  C.Brush.Style := bsClear;
  if FCount > 0 then
  begin
    C.Font.Height := -150;
    C.Font.Color := clRed;
    Txt := IntToStr(Max(1, Ceil(FCount)));
    C.TextOut((pbView.Width - C.TextWidth(Txt)) div 2,
      (pbView.Height - 170) div 2, Txt);
    C.Font.Height := -22;
    C.Font.Color := clBlack;
    Txt := 'get ready';
    C.TextOut((pbView.Width - C.TextWidth(Txt)) div 2,
      (pbView.Height + 40) div 2, Txt);
  end
  else if FRolling then
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := clRed;
    C.Pen.Color := clRed;
    C.Ellipse(16, 16, 34, 34);
    C.Brush.Style := bsClear;
    C.Font.Height := -20;
    C.Font.Color := clRed;
    C.TextOut(44, 16, Format('REC   %.1f of %.0f seconds',
      [FElapsed, Seconds]));
  end;
end;

{ The strip of snapshots.  Not an editor on purpose: a clip this short is
  either kept or done again. }
procedure TRecordWin.PaintFilm(Sender: TObject);
var
  I, X: Integer;
  C: TCanvas;
begin
  C := pbFilm.Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := hsSurface.PixToColor(hsDialogSkin.DlgTheme.Shell2);
  C.FillRect(0, 0, pbFilm.Width, pbFilm.Height);
  for I := 0 to STRIP_N - 1 do
  begin
    X := 2 + I * (STRIP_W div 2 + 2);
    if X + STRIP_W div 2 > pbFilm.Width then Break;
    if (FStrip[I] <> nil) and (I < FStripN) then
      C.StretchDraw(Rect(X, 2, X + STRIP_W div 2, 2 + STRIP_H div 2),
        FStrip[I])
    else
    begin
      C.Brush.Color := hsSurface.PixToColor(hsDialogSkin.DlgTheme.Panel);
      C.FillRect(X, 2, X + STRIP_W div 2, 2 + STRIP_H div 2);
      C.Brush.Color := hsSurface.PixToColor(hsDialogSkin.DlgTheme.Shell2);
    end;
  end;
end;

procedure TRecordWin.Down(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FDrag := Button in [mbMiddle, mbRight];
  FPan := Button = mbRight;
  FDX := X;
  FDY := Y;
end;

procedure TRecordWin.Move_(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  K: Double;
begin
  if not FDrag then Exit;
  K := ViewScale(FSrcW, FSrcH, pbView.Width, pbView.Height);
  if FPan or (ssShift in Shift) then
    PanBy(FView, (X - FDX) / K, (Y - FDY) / K)
  else
  begin
    OrbitBy(FView, X - FDX, Y - FDY);
    { turn about the selection, not the world origin }
    HoldAt(FView, FPivot, FSrcW / 2, FSrcH / 2);
  end;
  FDX := X;
  FDY := Y;
  pbView.Invalidate;
end;

procedure TRecordWin.Up(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FDrag := False;
  FPan := False;
  pbView.Invalidate;
end;

procedure TRecordWin.Wheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  P: TPoint;
  K, AX, AY: Double;
begin
  P := pbView.ScreenToClient(MousePos);
  K := ViewScale(FSrcW, FSrcH, pbView.Width, pbView.Height);
  AX := FSrcW / 2 + (P.X - pbView.Width / 2) / K;
  AY := FSrcH / 2 + (P.Y - pbView.Height / 2) / K;
  if WheelDelta > 0 then ZoomAt(FView, 1.15, AX, AY)
  else ZoomAt(FView, 1 / 1.15, AX, AY);
  { the zoom you leave it at is the zoom a canned walk starts from }
  FHome.Ppu := FView.Ppu;
  FHome.OX := FView.OX;
  FHome.OY := FView.OY;
  pbView.Invalidate;
  Handled := True;
end;

procedure TRecordWin.BarDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  { not while recording; a free-hand take needs the mouse on the model }
  if (Button = mbLeft) and not FRolling then
    hsDialogSkin.DragBegin(FWinDrag, Self);
end;

procedure TRecordWin.BarMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  hsDialogSkin.DragTo(FWinDrag, Self);
end;

procedure TRecordWin.BarUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  hsDialogSkin.DragEnd(FWinDrag);
end;

procedure TRecordWin.KeyDownH(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key <> VK_ESCAPE then Exit;
  Key := 0;
  if FRolling or (FCount > 0) then DoStop(nil)
  else if FPlaying then DoPlay(nil)
  else DoDrop(nil);
end;

procedure TRecordWin.DoGo(Sender: TObject);
var
  K: TWalk;
begin
  if ChosenWalk(K) then Remember(K);
  DoClear(nil);
  FHome := FView;
  FCount := READY_FOR;
  FClock := GetTickCount64;
  FRolling := False;
  FPlaying := False;
  btnGo.Visible := False;
  btnStop.Visible := True;
  lblTitle.Caption := 'Get ready';
  Refresh_;
end;

procedure TRecordWin.DoStop(Sender: TObject);
begin
  FCount := 0;
  FRolling := False;
  btnGo.Visible := True;
  btnStop.Visible := False;
  lblTitle.Caption := 'Record a move';
  SetLength(FCam, FN);
  { a recording over in a blink is somebody changing their mind }
  if (FN < 2) or (FElapsed < 0.4) then
  begin
    FN := 0;
    SetLength(FCam, 0);
    FStripN := 0;
  end;
  Refresh_;
end;

procedure TRecordWin.DoPlay(Sender: TObject);
begin
  if FN < 2 then Exit;
  FPlaying := not FPlaying;
  FPlayT := 0;
  FClock := GetTickCount64;
  if FPlaying then btnPlay.Caption := 'Stop' else btnPlay.Caption := 'Play';
  pbView.Invalidate;
end;

procedure TRecordWin.DoClear(Sender: TObject);
var
  I: Integer;
begin
  FN := 0;
  SetLength(FCam, 0);
  FStripN := 0;
  for I := 0 to STRIP_N - 1 do
    if FStrip[I] <> nil then
    begin
      FStrip[I].Free;
      FStrip[I] := nil;
    end;
  FPlaying := False;
  btnPlay.Caption := 'Play';
  FElapsed := 0;
  Refresh_;
end;

procedure TRecordWin.DoTake(Sender: TObject);
begin
  FKept := FN >= 2;
  tmrTick.Enabled := False;
  ModalResult := mrOk;
end;

procedure TRecordWin.DoDrop(Sender: TObject);
begin
  FKept := False;
  tmrTick.Enabled := False;
  ModalResult := mrCancel;
end;

function RecordMove(Doc: TWorkDoc; const Start: TProjector; U: TUnitSystem;
  AFont: TFont; const LabelCol: TPix; EdgeW: Single; SrcW, SrcH: Integer;
  Axes: Boolean; const Pivot: TP3; out Cam: TCamPath): Boolean;
var
  W: TRecordWin;
begin
  Cam := nil;
  W := TRecordWin.Create(nil);
  try
    W.FDoc := Doc;
    W.FUnits := U;
    W.FFont := AFont;
    W.FLabelCol := LabelCol;
    W.FEdgeW := EdgeW;
    W.FSrcW := SrcW;
    W.FSrcH := SrcH;
    W.FAxes := Axes;
    W.FPivot := Pivot;
    W.FHome := Start;
    W.FView := Start;
    W.Setup;
    W.ShowModal;
    Result := W.FKept;
    if Result then Cam := W.FCam;
  finally
    W.Free;
  end;
end;

end.

unit hsDialogSkin;

{ Dresses dialogs in the program's current theme (the same TTheme the main
  window is painted from), so they match the window behind them.  Applied at
  runtime; there is one palette, in hsSkin, and this only reads it.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, StdCtrls, ExtCtrls, ComCtrls, Forms,
  BGRABitmap, BGRABitmapTypes, BCButton, BCPanel, BCLabel, BCTypes,
  BGRATheme, BGRAThemeCheckBox, BGRAThemeRadioButton, BCComboBox, BCTrackbarUpdown, BGRAFlashProgressBar, BCFluentSlider, InkListBox, InkEdit, InkMemo, InkRichEdit, hsSkin, hsSurface;

type
  { How loudly a button is painted.  Only the main action should be bright. }
  TBtnKind = (bkGo, bkPlain, bkQuiet);

  { Dragging a borderless dialog by its drawn title bar.  Anchor on the
    pointer's screen position, not its position in the window: on X11 the
    window has not moved yet when the next motion event arrives, so a
    window-relative delta counts twice and the drag shakes.  Move with one
    SetBounds; Left then Top is two moves and the window visibly steps. }
  TFormDrag = record
    Live: Boolean;
    GrabX, GrabY: Integer;    { the pointer, on the screen, when it went down }
    FormX, FormY: Integer;    { where the window was at that moment }
  end;

{ Begin, continue and end a title-bar drag.  The mouse event's X and Y are
  not used on purpose - see above. }
procedure DragBegin(out D: TFormDrag; F: TForm);
procedure DragTo(const D: TFormDrag; F: TForm);
procedure DragEnd(var D: TFormDrag);

type
  { Check boxes and radio buttons drawn in the dialog colors.  Windows draws
    its own in its own colors whatever the font says, which on a dark dialog
    left their words dark on dark.  ThemeForm gives every BGRA theme control
    this theme. }
  THsBoxTheme = class(TBGRATheme)
  private
    procedure DrawBox(const Caption: string; State: TBGRAThemeButtonState;
      Focused, Checked, Round: Boolean; ARect: TRect; ASurface: TBGRAThemeSurface);
  public
    procedure DrawCheckBox(Caption: string; State: TBGRAThemeButtonState;
      Focused: boolean; Checked: boolean; ARect: TRect;
      ASurface: TBGRAThemeSurface); override;
    procedure DrawRadioButton(Caption: string; State: TBGRAThemeButtonState;
      Focused: boolean; Checked: boolean; ARect: TRect;
      ASurface: TBGRAThemeSurface); override;
  end;

  { Tabs drawn on a paint box in the dialog colors, for the same reason: a
    page control's tabs are the desktop's light ones whatever the dialog.
    Turns Pages, when given.  OnChange fires on a click only. }
  THsTabStrip = class(TComponent)
  private
    FBox: TPaintBox;
    FPages: TNotebook;
    FTabs: TStringList;
    FIndex: Integer;
    FOnChange: TNotifyEvent;
    procedure Paint(Sender: TObject);
    procedure MouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure TabsChanged(Sender: TObject);
    procedure SetIndex(V: Integer);
    function TabRight(I: Integer): Integer;
  public
    constructor Create(ABox: TPaintBox; APages: TNotebook;
      const Names: array of string); reintroduce;
    destructor Destroy; override;
    property Tabs: TStringList read FTabs;
    property TabIndex: Integer read FIndex write SetIndex;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

var
  { the dialogs' current theme, set by UseTheme }
  DlgTheme: TTheme;
  BoxTheme: THsBoxTheme;

{ Call before building a dialog. }
procedure UseTheme(const T: TTheme);

{ A shade of a color - Amount above 0 lightens, below 0 darkens.
  PixToColor, for turning a TPix into an LCL color, comes from hsSurface. }
function Shade(C: TColor; Amount: Double): TColor;

procedure SkinForm(F: TForm);
procedure SkinPanel(P: TBCPanel; Raised: Boolean = False; Rounding: Integer = 10);
procedure SkinButton(B: TBCButton; Kind: TBtnKind; FontH: Integer = 0);
procedure SkinLabel(L: TBCLabel; Dim: Boolean = False; FontH: Integer = 0;
  Bold: Boolean = False);
procedure SkinCheck(C: TBGRAThemeControl);
procedure SkinCombo(C: TBCComboBox);
procedure SkinSpin(C: TBCTrackbarUpdown);
procedure SkinProgress(P: TBGRAFlashProgressBar);
procedure SkinList(L: TInkListBox);
procedure SkinSlider(T: TBCFluentSlider);
{ Themes every control on a form by kind, colors only; sizes and fonts stay
  as laid out.  Button Tag: 1 main action, 2 quiet, 0 plain.  Label or
  panel Tag 1: dim text or raised panel.  Call from OnCreate, after UseTheme. }
procedure ThemeForm(F: TForm);
{ Keep the message loop turning this long, so what was just put up paints
  and the window stays responsive. }
procedure PauseFor(Milliseconds: QWord);
{ fill for a text field: darker than the panel on a dark theme, near white
  on a light one }
function FieldColor: TColor;

{ A radio group is a panel of BGRA radio buttons; they count in the order
  they were laid out.  RadioIndex is -1 when none is checked. }
function RadioIndex(P: TWinControl): Integer;
procedure SetRadioIndex(P: TWinControl; I: Integer);
function RadioText(P: TWinControl; I: Integer): string;
function RadioCount(P: TWinControl): Integer;
function IsRadioPanel(C: TComponent): Boolean;

implementation

procedure DragBegin(out D: TFormDrag; F: TForm);
var
  P: TPoint;
begin
  P := Mouse.CursorPos;
  D.Live := True;
  D.GrabX := P.X;
  D.GrabY := P.Y;
  D.FormX := F.Left;
  D.FormY := F.Top;
end;

procedure DragTo(const D: TFormDrag; F: TForm);
var
  P: TPoint;
  NX, NY: Integer;
begin
  if not D.Live then Exit;
  P := Mouse.CursorPos;
  NX := D.FormX + (P.X - D.GrabX);
  NY := D.FormY + (P.Y - D.GrabY);
  { skip motion inside one pixel rather than ask for a move }
  if (NX = F.Left) and (NY = F.Top) then Exit;
  F.SetBounds(NX, NY, F.Width, F.Height);
end;

procedure DragEnd(var D: TFormDrag);
begin
  D.Live := False;
end;

procedure UseTheme(const T: TTheme);
begin
  DlgTheme := T;
  if BoxTheme <> nil then BoxTheme.InvalidateThemedControls;
end;

function Shade(C: TColor; Amount: Double): TColor;
var
  R, G, B: Integer;

  function Mix(V: Integer): Integer;
  begin
    if Amount >= 0 then Result := Round(V + (255 - V) * Amount)
    else Result := Round(V * (1 + Amount));
    if Result < 0 then Result := 0;
    if Result > 255 then Result := 255;
  end;

begin
  R := C and $FF;
  G := (C shr 8) and $FF;
  B := (C shr 16) and $FF;
  Result := TColor(Mix(R) or (Mix(G) shl 8) or (Mix(B) shl 16));
end;

procedure SkinForm(F: TForm);
begin
  F.Color := PixToColor(DlgTheme.Shell1);
  F.Font.Color := PixToColor(DlgTheme.Text);
  F.Font.Height := -13;
end;

procedure SkinPanel(P: TBCPanel; Raised: Boolean; Rounding: Integer);
var
  Base: TColor;
begin
  if Raised then Base := PixToColor(DlgTheme.PanelHi)
  else Base := PixToColor(DlgTheme.Panel);
  P.Background.Style := bbsColor;
  P.Background.Color := Base;
  { set Color too: a child with ParentColor (a BCLabel by default) reads
    Color, not the painted background, and would draw a gray box }
  P.Color := Base;
  P.Border.Style := bboSolid;
  P.Border.Color := PixToColor(DlgTheme.Bezel1);
  P.Border.Width := 1;
  P.Rounding.RoundX := Rounding;
  P.Rounding.RoundY := Rounding;
  P.FontEx.Color := PixToColor(DlgTheme.Text);
  P.FontEx.Height := -13;
end;

type
  { GTK3 and Windows blend a rounded button's soft corners against white,
    not the parent, which leaves white specks on a dark dialog.  After the
    button renders, every partly transparent pixel is mixed with the
    parent's color and made opaque. }
  TCornerFix = class
    procedure AfterRender(Sender: TObject; const ABGRA: TBGRABitmap;
      AState: TBCButtonState; ARect: TRect);
  end;

var
  CornerFix: TCornerFix = nil;

procedure TCornerFix.AfterRender(Sender: TObject; const ABGRA: TBGRABitmap;
  AState: TBCButtonState; ARect: TRect);
var
  Back: TColor;
  BR, BG, BB, X, Y, A: Integer;
  P: PBGRAPixel;
  Off: Boolean;
begin
  { A disabled button is faded most of the way into the background.  The
    library only grays it, and on a dark theme a plain button is gray
    already. }
  Off := (Sender is TControl) and not TControl(Sender).Enabled;
  Back := clNone;
  if (Sender is TControl) and (TControl(Sender).Parent <> nil) then
    Back := TControl(Sender).Parent.Color;
  if (Back = clNone) or (Back = clDefault) then Back := PixToColor(DlgTheme.Shell1);
  Back := ColorToRGB(Back);
  BR := Back and $FF;
  BG := (Back shr 8) and $FF;
  BB := (Back shr 16) and $FF;
  for Y := 0 to ABGRA.Height - 1 do
  begin
    P := ABGRA.ScanLine[Y];
    for X := 0 to ABGRA.Width - 1 do
    begin
      A := P^.alpha;
      if A < 255 then
      begin
        P^.red := (P^.red * A + BR * (255 - A)) div 255;
        P^.green := (P^.green * A + BG * (255 - A)) div 255;
        P^.blue := (P^.blue * A + BB * (255 - A)) div 255;
        P^.alpha := 255;
      end;
      if Off then
      begin
        P^.red := (P^.red * 2 + BR * 3) div 5;
        P^.green := (P^.green * 2 + BG * 3) div 5;
        P^.blue := (P^.blue * 2 + BB * 3) div 5;
      end;
      Inc(P);
    end;
  end;
  ABGRA.InvalidateBitmap;
end;

{ One state of a button: the fill, the edge and the text. }
procedure OneState(S: TBCButtonState; Fill, Edge, Text: TColor);
begin
  S.Background.Style := bbsColor;
  S.Background.Color := Fill;
  S.Border.Style := bboSolid;
  S.Border.Color := Edge;
  S.Border.Width := 1;
  S.FontEx.Color := Text;
  S.FontEx.Style := [];
end;

procedure SkinButton(B: TBCButton; Kind: TBtnKind; FontH: Integer);
var
  Fill, Edge, Txt: TColor;
begin
  case Kind of
    bkGo:
      begin
        { the accent, with black or white text, whichever reads on it.  Do
          not assume the accent is bright; the light theme's is not. }
        Fill := PixToColor(DlgTheme.Accent);
        Edge := Shade(Fill, -0.25);
        Txt := PixToColor(OnPix(DlgTheme.Accent));
      end;
    bkQuiet:
      begin
        Fill := PixToColor(DlgTheme.Panel);
        Edge := PixToColor(DlgTheme.Panel);
        Txt := PixToColor(DlgTheme.TextDim);
      end;
  else
    Fill := PixToColor(DlgTheme.PanelHi);
    Edge := PixToColor(DlgTheme.Bezel1);
    Txt := PixToColor(DlgTheme.Text);
  end;

  B.Rounding.RoundX := 8;
  B.Rounding.RoundY := 8;
  OneState(B.StateNormal, Fill, Edge, Txt);
  OneState(B.StateHover, Shade(Fill, 0.10), Shade(Edge, 0.15), Txt);
  OneState(B.StateClicked, Shade(Fill, -0.12), Edge, Txt);
  if FontH = 0 then FontH := -13;
  B.StateNormal.FontEx.Height := FontH;
  B.StateHover.FontEx.Height := FontH;
  B.StateClicked.FontEx.Height := FontH;
  B.StateNormal.FontEx.Name := 'default';
  B.StateHover.FontEx.Name := 'default';
  B.StateClicked.FontEx.Name := 'default';
  if CornerFix = nil then CornerFix := TCornerFix.Create;
  B.OnAfterRenderBCButton := @CornerFix.AfterRender;
end;

procedure SkinLabel(L: TBCLabel; Dim: Boolean; FontH: Integer; Bold: Boolean);
begin
  if Dim then L.FontEx.Color := PixToColor(DlgTheme.TextDim)
  else L.FontEx.Color := PixToColor(DlgTheme.Text);
  if FontH = 0 then FontH := -13;
  L.FontEx.Height := FontH;
  if Bold then L.FontEx.Style := [fsBold] else L.FontEx.Style := [];
  L.Background.Style := bbsClear;
  L.Border.Style := bboNone;
end;

function LightTheme: Boolean;
begin
  Result := (DlgTheme.Panel.R + DlgTheme.Panel.G + DlgTheme.Panel.B) > 3 * 140;
end;

function FieldColor: TColor;
begin
  if LightTheme then
    Result := PixToColor(MixPix(DlgTheme.Panel, Pix(255, 255, 255), 0.75))
  else
    Result := PixToColor(MixPix(DlgTheme.Panel, Pix(0, 0, 0), 0.30));
end;

{ A combo box is a drawn button and a list that drops down inside the
  dialog: a separate window can be disabled along with everything else
  while a modal dialog is up. }
procedure SkinCombo(C: TBCComboBox);
var
  Fill, Edge, Txt: TColor;
  St: TBCButtonState;
begin
  Fill := FieldColor;
  Edge := PixToColor(DlgTheme.Bezel1);
  Txt := PixToColor(DlgTheme.Text);
  C.Rounding.RoundX := 6;
  C.Rounding.RoundY := 6;
  OneState(C.StateNormal, Fill, Edge, Txt);
  OneState(C.StateHover, Shade(Fill, 0.08), PixToColor(DlgTheme.Accent), Txt);
  OneState(C.StateClicked, Shade(Fill, -0.08), PixToColor(DlgTheme.Accent), Txt);
  for St in [C.StateNormal, C.StateHover, C.StateClicked] do
  begin
    { a BGRA font height is the glyph's, a little smaller than an LCL
      font's of the same number; this matches the edits beside it }
    St.FontEx.Height := -16;
    St.FontEx.Name := 'default';
    St.FontEx.TextAlignment := bcaLeftCenter;
    St.FontEx.PaddingLeft := 8;
  end;
  C.DropDownOnSameForm := True;
  C.DropDownColor := Fill;
  C.DropDownFontColor := Txt;
  C.DropDownBorderColor := Edge;
  C.DropDownHighlight := PixToColor(DlgTheme.Accent);
  C.DropDownFontHighlight := PixToColor(OnPix(DlgTheme.Accent));
  if CornerFix = nil then CornerFix := TCornerFix.Create;
  C.Button.OnAfterRenderBCButton := @CornerFix.AfterRender;
end;

{ a number box with its up and down buttons, in the field's colors }
procedure SkinSpin(C: TBCTrackbarUpdown);
begin
  C.Background.Style := bbsColor;
  C.Background.Color := FieldColor;
  C.ButtonBackground.Style := bbsColor;
  C.ButtonBackground.Color := PixToColor(DlgTheme.PanelHi);
  C.ButtonDownBackground.Style := bbsColor;
  C.ButtonDownBackground.Color := PixToColor(DlgTheme.Accent);
  C.Border.Style := bboSolid;
  C.Border.Color := PixToColor(MixPix(DlgTheme.Shell1, DlgTheme.TextDim, 0.6));
  C.Border.Width := 1;
  C.Rounding.RoundX := 6;
  C.Rounding.RoundY := 6;
  C.ArrowColor := PixToColor(DlgTheme.Text);
  C.Font.Color := PixToColor(DlgTheme.Text);
  C.Font.Height := -13;
  C.HasTrackBar := False;
end;

{ a plain accent bar on the field color; the library's default is a
  randomized, animated one }
procedure SkinProgress(P: TBGRAFlashProgressBar);
begin
  P.BackgroundRandomize := False;
  P.ShowBarAnimation := False;
  P.ShowDividers := False;
  P.Caption := '';
  P.Color := PixToColor(DlgTheme.Shell1);
  P.BackgroundColor := FieldColor;
  P.BarColor := PixToColor(DlgTheme.Accent);
end;

procedure SkinList(L: TInkListBox);
begin
  L.Color := FieldColor;
  L.Font.Color := PixToColor(DlgTheme.Text);
  L.SelectionColor := PixToColor(DlgTheme.Accent);
  L.SelectionTextColor := PixToColor(OnPix(DlgTheme.Accent));
end;

procedure SkinCheck(C: TBGRAThemeControl);
begin
  C.Theme := BoxTheme;
  { the class does not publish ShowHint, so a hint from the form is shown
    from here }
  if C.Hint <> '' then C.ShowHint := True;
end;
procedure SkinSlider(T: TBCFluentSlider);
begin
  T.LineColor := PixToColor(DlgTheme.Accent);
  T.LineBkgColor := PixToColor(MixPix(DlgTheme.Shell1, DlgTheme.TextDim, 0.5));
end;

type
  { for ParentColor, which is protected; reached through a Pointer since
    the checked build refuses the class cast }
  TWinControlAccess = class(TWinControl);

{ the color behind a control: the nearest parent that has one of its own }
function BackOf(C: TControl): TColor;
begin
  Result := PixToColor(DlgTheme.Shell1);
  if C = nil then Exit;
  C := C.Parent;
  while C <> nil do
  begin
    if C is TBCPanel then Exit(TBCPanel(C).Background.Color);
    if (C.Color <> clDefault) and not ((C is TWinControl) and TWinControlAccess(Pointer(C)).ParentColor) then
      Exit(C.Color);
    C := C.Parent;
  end;
end;

procedure PauseFor(Milliseconds: QWord);
var
  UntilTick: QWord;
begin
  UntilTick := GetTickCount64 + Milliseconds;
  repeat
    Application.ProcessMessages;
    Sleep(10);
  until GetTickCount64 >= UntilTick;
end;

procedure ThemeForm(F: TForm);
var
  I: Integer;
  C: TComponent;
  Kind: TBtnKind;
begin
  SkinForm(F);
  for I := 0 to F.ComponentCount - 1 do
  begin
    C := F.Components[I];
    if C is TBCButton then
    begin
      case C.Tag of
        1: Kind := bkGo;
        2: Kind := bkQuiet;
      else
        Kind := bkPlain;
      end;
      SkinButton(TBCButton(C), Kind, TBCButton(C).StateNormal.FontEx.Height);
      { the rounded corners show the button's own color }
      TBCButton(C).Color := BackOf(TControl(C));
    end
    else if C is TBCPanel then
      SkinPanel(TBCPanel(C), C.Tag = 1)
    else if C is TBCLabel then
      SkinLabel(TBCLabel(C), C.Tag = 1, TBCLabel(C).FontEx.Height,
        fsBold in TBCLabel(C).FontEx.Style)
    else if C is TLabel then
    begin
      if C.Tag = 1 then TLabel(C).Font.Color := PixToColor(DlgTheme.TextDim)
      else TLabel(C).Font.Color := PixToColor(DlgTheme.Text);
      { a label with a font of its own but no size would take the desktop's }
      if TLabel(C).Font.Height = 0 then TLabel(C).Font.Height := -13;
      TLabel(C).Transparent := True;
    end
    else if C is TBCComboBox then
      SkinCombo(TBCComboBox(C))
    else if C is TBCTrackbarUpdown then
      SkinSpin(TBCTrackbarUpdown(C))
    else if C is TBGRAFlashProgressBar then
      SkinProgress(TBGRAFlashProgressBar(C))
    else if C is TInkListBox then
      SkinList(TInkListBox(C))
    else if (C is TInkEdit) or (C is TInkMemo) or (C is TInkRichEdit) then
    begin
      TWinControl(C).Color := FieldColor;
      TWinControl(C).Font.Color := PixToColor(DlgTheme.Text);
      { with no size of its own the control would use the page's larger one }
      if TWinControl(C).Font.Height = 0 then TWinControl(C).Font.Height := -13;
    end
    else if C is TBGRAThemeControl then
      SkinCheck(TBGRAThemeControl(C))
    else if C is TBCFluentSlider then
      SkinSlider(TBCFluentSlider(C))
    else if (C is TCustomPanel) or (C is TNotebook) or (C is TPage) then
    begin
      { the color of whatever it sits on, a drawn panel's included }
      TWinControl(C).Color := BackOf(TControl(C));
      TWinControl(C).Font.Color := PixToColor(DlgTheme.Text);
    end;
  end;
end;


function PixOfColor(C: TColor): TBGRAPixel;
begin
  Result := ColorToBGRA(ColorToRGB(C));
end;

procedure THsBoxTheme.DrawBox(const Caption: string; State: TBGRAThemeButtonState;
  Focused, Checked, Round: Boolean; ARect: TRect; ASurface: TBGRAThemeSurface);
var
  Ctl: TCustomControl;
  C: TCanvas;
  Bmp: TBGRABitmap;
  S, Y, I, Gap: Integer;
  W, Lw: Single;
  Edge, Fill, Mark: TBGRAPixel;
  Txt: TColor;
  St: TTextStyle;
  A: TPix;
begin
  Ctl := nil;
  for I := 0 to ThemedControlCount - 1 do
    if ThemedControl[I].Canvas = ASurface.DestCanvas then Ctl := ThemedControl[I];
  C := ASurface.DestCanvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := BackOf(Ctl);
  C.FillRect(ARect);

  A := DlgTheme.Accent;
  Fill := PixOfColor(FieldColor);
  Txt := PixToColor(DlgTheme.Text);
  if State = btbsDisabled then
  begin
    Edge := PixOfColor(PixToColor(DlgTheme.TextDim));
    Txt := PixToColor(DlgTheme.TextDim);
  end
  else if Focused or (State in [btbsHover, btbsActive]) then
    Edge := BGRA(A.R, A.G, A.B)
  else
    Edge := PixOfColor(PixToColor(DlgTheme.TextDim));
  { a dark mark on a pale accent, a white one on a deep accent }
  if A.R * 3 + A.G * 6 + A.B >= 1400 then Mark := PixOfColor(PixToColor(DlgTheme.Shell1))
  else Mark := BGRAWhite;

  S := ASurface.ScaleForCanvas(16);
  Y := ARect.Top + (ARect.Height - S) div 2;
  ASurface.BitmapRect := Rect(ARect.Left + 1, Y, ARect.Left + 1 + S, Y + S);
  Bmp := ASurface.Bitmap;
  W := Bmp.Width;
  Lw := W / 14;
  if Lw < 1 then Lw := 1;
  if Round then
  begin
    Bmp.EllipseAntialias((W - 1) / 2, (W - 1) / 2, W / 2 - Lw, W / 2 - Lw, Edge, Lw, Fill);
    if Checked then
      Bmp.FillEllipseAntialias((W - 1) / 2, (W - 1) / 2, W / 4.2, W / 4.2,
        BGRA(A.R, A.G, A.B));
  end
  else if Checked and (State <> btbsDisabled) then
  begin
    Bmp.FillRoundRectAntialias(0.5, 0.5, W - 1.5, W - 1.5, W * 0.22, W * 0.22,
      BGRA(A.R, A.G, A.B));
    Bmp.DrawPolyLineAntialias([PointF(W * 0.24, W * 0.52), PointF(W * 0.42, W * 0.70),
      PointF(W * 0.76, W * 0.32)], Mark, W / 8);
  end
  else
  begin
    Bmp.RoundRectAntialias(Lw / 2, Lw / 2, W - 1 - Lw / 2, W - 1 - Lw / 2,
      W * 0.22, W * 0.22, Edge, Lw, Fill);
    if Checked then
      Bmp.DrawPolyLineAntialias([PointF(W * 0.24, W * 0.52), PointF(W * 0.42, W * 0.70),
        PointF(W * 0.76, W * 0.32)], Edge, W / 8);
  end;
  ASurface.DrawBitmap;

  if Caption = '' then Exit;
  if Ctl <> nil then C.Font.Assign(Ctl.Font);
  C.Font.Color := Txt;
  C.Brush.Style := bsClear;
  FillChar(St, SizeOf(St), 0);
  St.Layout := tlCenter;
  St.SingleLine := True;
  St.EndEllipsis := True;
  St.Clipping := True;
  Gap := ASurface.ScaleForCanvas(7);
  C.TextRect(Rect(ARect.Left + S + Gap, ARect.Top, ARect.Right, ARect.Bottom),
    ARect.Left + S + Gap, ARect.Top, Caption, St);
end;

procedure THsBoxTheme.DrawCheckBox(Caption: string; State: TBGRAThemeButtonState;
  Focused: boolean; Checked: boolean; ARect: TRect; ASurface: TBGRAThemeSurface);
begin
  DrawBox(Caption, State, Focused, Checked, False, ARect, ASurface);
end;

procedure THsBoxTheme.DrawRadioButton(Caption: string; State: TBGRAThemeButtonState;
  Focused: boolean; Checked: boolean; ARect: TRect; ASurface: TBGRAThemeSurface);
begin
  DrawBox(Caption, State, Focused, Checked, True, ARect, ASurface);
end;

constructor THsTabStrip.Create(ABox: TPaintBox; APages: TNotebook;
  const Names: array of string);
var
  I: Integer;
begin
  inherited Create(ABox);
  FBox := ABox;
  FPages := APages;
  FTabs := TStringList.Create;
  for I := 0 to High(Names) do FTabs.Add(Names[I]);
  FTabs.OnChange := @TabsChanged;
  FIndex := 0;
  if FPages <> nil then FPages.PageIndex := 0;
  FBox.OnPaint := @Paint;
  FBox.OnMouseDown := @MouseDown;
end;

destructor THsTabStrip.Destroy;
begin
  FTabs.Free;
  inherited Destroy;
end;

procedure THsTabStrip.TabsChanged(Sender: TObject);
begin
  if FIndex >= FTabs.Count then FIndex := FTabs.Count - 1;
  FBox.Invalidate;
end;

procedure THsTabStrip.SetIndex(V: Integer);
begin
  if (V < 0) or (V >= FTabs.Count) or (V = FIndex) then Exit;
  FIndex := V;
  if (FPages <> nil) and (V < FPages.PageCount) then FPages.PageIndex := V;
  FBox.Invalidate;
end;

{ where tab I ends: tabs take their words' width, and share the strip
  evenly when that does not fit }
function THsTabStrip.TabRight(I: Integer): Integer;
var
  K, Pad, Total: Integer;
  Wid: array of Integer;
begin
  FBox.Canvas.Font.Height := FBox.Scale96ToForm(-13);
  Pad := FBox.Scale96ToForm(14);
  SetLength(Wid, FTabs.Count);
  Total := 0;
  for K := 0 to FTabs.Count - 1 do
  begin
    Wid[K] := FBox.Canvas.TextWidth(FTabs[K]) + 2 * Pad;
    Inc(Total, Wid[K]);
  end;
  if Total > FBox.Width then
    for K := 0 to FTabs.Count - 1 do Wid[K] := FBox.Width div FTabs.Count;
  Result := 0;
  for K := 0 to I do Inc(Result, Wid[K]);
end;

procedure THsTabStrip.Paint(Sender: TObject);
var
  C: TCanvas;
  I, X0, X1, H, Bar, R: Integer;
  St: TTextStyle;
begin
  C := FBox.Canvas;
  H := FBox.Height;
  Bar := FBox.Scale96ToForm(3);
  R := FBox.Scale96ToForm(8);
  C.Brush.Style := bsSolid;
  C.Brush.Color := BackOf(FBox);
  C.FillRect(0, 0, FBox.Width, H);
  { a hairline under the strip, so it reads as the top of the pages }
  C.Pen.Color := PixToColor(MixPix(DlgTheme.Shell1, DlgTheme.TextDim, 0.35));
  C.Line(0, H - 1, FBox.Width, H - 1);
  FillChar(St, SizeOf(St), 0);
  St.Alignment := taCenter;
  St.Layout := tlCenter;
  St.SingleLine := True;
  St.EndEllipsis := True;
  St.Clipping := True;
  X0 := 0;
  for I := 0 to FTabs.Count - 1 do
  begin
    X1 := TabRight(I);
    if I = FIndex then
    begin
      C.Brush.Color := PixToColor(DlgTheme.Panel);
      C.Pen.Color := C.Brush.Color;
      C.RoundRect(X0, 0, X1, H + R, R, R);
      C.Brush.Color := PixToColor(DlgTheme.Accent);
      C.FillRect(X0 + R div 2, H - Bar, X1 - R div 2, H);
      C.Font.Color := PixToColor(DlgTheme.Text);
      C.Font.Style := [fsBold];
    end
    else
    begin
      C.Font.Color := PixToColor(DlgTheme.TextDim);
      C.Font.Style := [];
    end;
    C.Brush.Style := bsClear;
    C.TextRect(Rect(X0, 0, X1, H - Bar), X0, 0, FTabs[I], St);
    C.Brush.Style := bsSolid;
    X0 := X1;
  end;
end;

procedure THsTabStrip.MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  I, Was: Integer;
begin
  if Button <> mbLeft then Exit;
  for I := 0 to FTabs.Count - 1 do
    if X < TabRight(I) then
    begin
      Was := FIndex;
      SetIndex(I);
      if (FIndex <> Was) and Assigned(FOnChange) then FOnChange(Self);
      Exit;
    end;
end;

function RadioCount(P: TWinControl): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to P.ControlCount - 1 do
    if P.Controls[I] is TBGRAThemeRadioButton then Inc(Result);
end;

function RadioAt(P: TWinControl; Idx: Integer): TBGRAThemeRadioButton;
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to P.ControlCount - 1 do
    if P.Controls[I] is TBGRAThemeRadioButton then
    begin
      if N = Idx then Exit(TBGRAThemeRadioButton(P.Controls[I]));
      Inc(N);
    end;
  Result := nil;
end;

function RadioIndex(P: TWinControl): Integer;
var
  I: Integer;
begin
  for I := 0 to RadioCount(P) - 1 do
    if RadioAt(P, I).Checked then Exit(I);
  Result := -1;
end;

procedure SetRadioIndex(P: TWinControl; I: Integer);
var
  B: TBGRAThemeRadioButton;
begin
  B := RadioAt(P, I);
  if B <> nil then B.Checked := True;
end;

function RadioText(P: TWinControl; I: Integer): string;
var
  B: TBGRAThemeRadioButton;
begin
  B := RadioAt(P, I);
  if B <> nil then Result := B.Caption else Result := '';
end;

function IsRadioPanel(C: TComponent): Boolean;
begin
  Result := (C is TWinControl) and (RadioCount(TWinControl(C)) > 0);
end;

initialization
  BoxTheme := THsBoxTheme.Create(nil);

finalization
  FreeAndNil(BoxTheme);

end.

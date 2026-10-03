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
  hsSkin, hsSurface;

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

var
  { the dialogs' current theme, set by UseTheme }
  DlgTheme: TTheme;

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
procedure SkinEdit(E: TEdit);
procedure SkinCheck(C: TCheckBox);
procedure SkinTrack(T: TTrackBar);
{ Themes every control on a form by kind, colors only; sizes and fonts stay
  as laid out.  Button Tag: 1 main action, 2 quiet, 0 plain.  Label or
  panel Tag 1: dim text or raised panel.  Call from OnCreate, after UseTheme. }
procedure ThemeForm(F: TForm);
{ fill for a text field: darker than the panel on a dark theme, near white
  on a light one }
function FieldColor: TColor;

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

procedure SkinEdit(E: TEdit);
begin
  E.Color := FieldColor;
  E.Font.Color := PixToColor(DlgTheme.Text);
  E.Font.Height := -13;
  E.BorderStyle := bsSingle;
end;

procedure SkinCheck(C: TCheckBox);
begin
  C.Color := PixToColor(DlgTheme.Panel);
  C.Font.Color := PixToColor(DlgTheme.Text);
  C.Font.Height := -13;
  C.ParentColor := False;
end;

procedure SkinTrack(T: TTrackBar);
begin
  T.Color := PixToColor(DlgTheme.Panel);
  T.ParentColor := False;
  T.ShowSelRange := False;
  T.TickStyle := tsNone;
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
      TLabel(C).Transparent := True;
    end
    { A combo box keeps the system's colors.  Its drop-down list is a system
      window that takes the box's color but not its text color on Windows,
      and GTK draws the box inconsistently. }
    else if C is TCustomComboBox then
    begin
      { and the system's text color, or a dark theme's pale text vanishes }
      TCustomComboBox(C).Color := clWindow;
      TCustomComboBox(C).Font.Color := clWindowText;
    end
    else if C is TCustomEdit then
    begin
      TWinControl(C).Color := FieldColor;
      TWinControl(C).Font.Color := PixToColor(DlgTheme.Text);
    end
    else if (C is TCustomCheckBox) or (C is TRadioButton) then
    begin
      TWinControl(C).Color := PixToColor(DlgTheme.Shell1);
      TWinControl(C).Font.Color := PixToColor(DlgTheme.Text);
    end
    else if C is TTrackBar then
      SkinTrack(TTrackBar(C))
    { page control tabs are always drawn in the desktop's light colors, so
      their text keeps the desktop's color too }
    else if C is TCustomTabControl then
      TCustomTabControl(C).Font.Color := clDefault
    else if (C is TCustomGroupBox) or (C is TCustomPanel) or (C is TTabSheet) then
    begin
      TWinControl(C).Color := PixToColor(DlgTheme.Shell1);
      TWinControl(C).Font.Color := PixToColor(DlgTheme.Text);
    end;
  end;
end;

end.

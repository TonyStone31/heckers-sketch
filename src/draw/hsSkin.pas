unit hsSkin;

{
  hsSkin - the look of Heckers Sketch.

  Color themes plus the chassis parts (panels, buttons, line icons).
  Everything here paints into a TArtSurface so the edges come out smooth;
  text is left to the caller because only the widgetset can render glyphs.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, hsSurface;

type
  TTheme = record
    Name: string;
    Shell1, Shell2: TPix;   // window background, top -> bottom
    Bezel1, Bezel2: TPix;   // frame surrounding the screen
    Panel: TPix;            // control deck panel
    PanelHi: TPix;          // panel top highlight
    Screen1, Screen2: TPix; // the drawing surface itself
    Ink: TPix;              // default pen color on this screen
    Accent: TPix;           // knob markers, active controls
    Text: TPix;
    TextDim: TPix;
    Grid: TPix;
  end;

  TIconKind = (
    ikUndo, ikRedo, ikSave, ikPrint,
    ikTheme, ikGrid, ikHelp, ikDroplet,
    ikUnits, ikDim, ikMeasure, ikOrigin,
    ikOpen, ikFit, ikExport, ikArrow,
    { one per tool, so a button and the cursor can both say which is which }
    ikTPoint, ikTLine, ikTRect, ikTArc, ikTCircle, ikTPush, ikTText,
    ikTErase, ikTMeasure, ikTOrbit, ikChevron, ikTSelect, ikTMove,
    ikTOffset, ikTRotate, ikTProtractor, ikTDrill, ikTFollow,
    { the shop door: a spanner, so it is not mistaken for the plain chevron }
    ikShop
  );

const
  { both with white paper, so the screen matches what prints }
  THEME_COUNT = 2;
  THEME_LIGHT = 0;
  THEME_DARK  = 1;

var
  Themes: array[0..THEME_COUNT - 1] of TTheme;

{ the index of the theme with this name, or -1 }
function ThemeNamed(const AName: string): Integer;

{ Chassis parts. }
procedure PaintShell(S: TArtSurface; const T: TTheme);
procedure PaintBezel(S: TArtSurface; const R: TRect; const T: TTheme;
  Radius: Single = 22);
procedure PaintPanel(S: TArtSurface; const R: TRect; const T: TTheme; Radius: Single = 14);
procedure PaintPill(S: TArtSurface; const R: TRect; Radius: Single;
  const C1, C2, Edge: TPix; Alpha: Single = 1.0);
procedure PaintSwatch(S: TArtSurface; const R: TRect; const C: TPix;
  Selected, Hot: Boolean; const T: TTheme);
procedure PaintIcon(S: TArtSurface; Kind: TIconKind; const R: TRect;
  const C: TPix; Alpha: Single = 1.0);
procedure PaintScreenPaper(S: TArtSurface; const T: TTheme);
procedure PaintScreenWell(S: TArtSurface; const R: TRect; Radius: Single);
procedure PaintMeasuredGrid(S: TArtSurface; const T: TTheme;
  Ppu, OX, OY: Double; MajorEvery: Integer);

{ The model axes, in SketchUp's colors: X red, Y green, Z blue.  Index is
  0 X, 1 Y, 2 Z; anything else comes back gray. }
function AxisPix(Index: Integer): TPix;

implementation

function ThemeNamed(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to THEME_COUNT - 1 do
    if SameText(Themes[I].Name, AName) then Exit(I);
  Result := -1;
end;

function AxisPix(Index: Integer): TPix;
begin
  { Kept far apart and dark enough to read on white: the green has almost no
    blue in it and the blue almost no green, or thin Y and Z lines look alike. }
  case Index of
    0: Result := Pix($D2, $2C, $2C);        // X, red
    1: Result := Pix($0E, $92, $32);        // Y, green, almost no blue
    2: Result := Pix($16, $46, $DC);        // Z, blue, almost no green
  else
    Result := Pix($78, $78, $84);
  end;
end;

procedure InitThemes;
begin
  { Light: SketchUp's own look.  Pale chrome, white paper, black lines. }
  with Themes[THEME_LIGHT] do
  begin
    Name := 'Light';
    Shell1 := Pix($E4, $E6, $E9);
    Shell2 := Pix($CF, $D3, $D8);
    Bezel1 := Pix($BF, $C4, $CA);
    Bezel2 := Pix($9F, $A6, $AE);
    Panel := Pix($EC, $EE, $F1);
    PanelHi := Pix($FF, $FF, $FF);
    Screen1 := Pix($FF, $FF, $FF);
    Screen2 := Pix($F4, $F5, $F6);
    Ink := Pix($1A, $1C, $20);
    { The accent is used for text as well as fills, so it is kept dark enough
      for 4.7:1 contrast on this panel.  Text on top of it is picked by OnPix. }
    Accent := Pix($17, $6B, $BD);
    Text := Pix($22, $26, $2C);
    { dim text kept dark enough to read on this panel too }
    TextDim := Pix($5E, $66, $70);
    { dark enough to show on white paper }
    Grid := Pix($BE, $C6, $D0);
  end;

  { Dark: the same white paper, dark chrome around it. }
  with Themes[THEME_DARK] do
  begin
    Name := 'Dark';
    Shell1 := Pix($23, $26, $2C);
    Shell2 := Pix($15, $17, $1C);
    Bezel1 := Pix($33, $37, $3F);
    Bezel2 := Pix($16, $18, $1E);
    Panel := Pix($1D, $20, $27);
    PanelHi := Pix($33, $38, $43);
    Screen1 := Pix($FF, $FF, $FF);
    Screen2 := Pix($F4, $F5, $F6);
    Ink := Pix($1A, $1C, $20);
    Accent := Pix($4A, $C8, $F0);
    Text := Pix($E8, $EC, $F2);
    TextDim := Pix($8A, $93, $A0);
    { dark enough to show on white paper }
    Grid := Pix($BE, $C6, $D0);
  end;
end;

{ ------------------------------------------------------------------------ }

procedure PaintShell(S: TArtSurface; const T: TTheme);
var
  X, Y: Integer;
  CX, CY, MaxD, D, V: Single;
  P: PPix;
  Row: TPix;
begin
  S.BlendMode := bmNormal;
  CX := S.Width / 2;
  CY := S.Height / 2;
  MaxD := Sqrt(CX * CX + CY * CY);
  if MaxD < 1 then MaxD := 1;

  { Vertical gradient plus a radial vignette, in a single pass. }
  for Y := 0 to S.Height - 1 do
  begin
    Row := MixPix(T.Shell1, T.Shell2, Y / Max(1, S.Height - 1));
    P := S.ScanLine(Y);
    for X := 0 to S.Width - 1 do
    begin
      D := Sqrt(Sqr(X - CX) + Sqr(Y - CY)) / MaxD;
      V := 1 - 0.42 * D * D;
      P^.R := Round(Row.R * V);
      P^.G := Round(Row.G * V);
      P^.B := Round(Row.B * V);
      P^.A := 255;
      Inc(P);
    end;
  end;
  S.Touch;
end;

{ Recessed frame around the drawing screen: outer bevel, inner shadow. }
procedure PaintBezel(S: TArtSurface; const R: TRect; const T: TTheme;
  Radius: Single);
var
  I: Integer;
  Outer: TRect;
begin
  S.BlendMode := bmNormal;
  Outer := R;

  { drop shadow under the whole assembly }
  for I := 6 downto 1 do
    S.RoundRect(Rect(Outer.Left - I, Outer.Top - I + 4, Outer.Right + I,
      Outer.Bottom + I + 6), Radius + I, Pix(0, 0, 0), 0.05);

  S.RoundRectV(Outer, Radius, T.Bezel1, T.Bezel2);
  { top light catch }
  S.RoundFrame(Rect(Outer.Left + 1, Outer.Top + 1, Outer.Right - 1, Outer.Bottom - 1),
    Max(1, Radius - 1), 1.4, Pix(255, 255, 255), 0.16);
  S.RoundFrame(Outer, Radius, 1.2, Pix(0, 0, 0), 0.45);
end;

procedure PaintPanel(S: TArtSurface; const R: TRect; const T: TTheme; Radius: Single);
begin
  S.BlendMode := bmNormal;
  S.RoundRect(Rect(R.Left, R.Top + 3, R.Right, R.Bottom + 4), Radius, Pix(0, 0, 0), 0.25);
  S.RoundRectV(R, Radius, T.PanelHi, T.Panel);
  S.RoundFrame(R, Radius, 1.1, Pix(255, 255, 255), 0.10);
end;

procedure PaintPill(S: TArtSurface; const R: TRect; Radius: Single;
  const C1, C2, Edge: TPix; Alpha: Single);
begin
  S.BlendMode := bmNormal;
  S.RoundRectV(R, Radius, C1, C2, Alpha);
  S.RoundFrame(R, Radius, 1.0, Edge, Alpha * 0.85);
end;

procedure PaintSwatch(S: TArtSurface; const R: TRect; const C: TPix;
  Selected, Hot: Boolean; const T: TTheme);
var
  Rr: TRect;
begin
  S.BlendMode := bmNormal;
  Rr := R;
  if Selected then
  begin
    S.RoundRect(Rect(Rr.Left - 3, Rr.Top - 3, Rr.Right + 3, Rr.Bottom + 3), 8,
      T.Accent, 0.95);
  end
  else if Hot then
    S.RoundRect(Rect(Rr.Left - 2, Rr.Top - 2, Rr.Right + 2, Rr.Bottom + 2), 7,
      Pix(255, 255, 255), 0.40);

  S.RoundRectV(Rr, 5, ShadePix(C, 1.14), ShadePix(C, 0.86));
  S.RoundFrame(Rr, 5, 1.0, Pix(0, 0, 0), 0.35);
  S.Line(Rr.Left + 2, Rr.Top + 2, Rr.Right - 3, Rr.Top + 2, 1.4,
    Pix(255, 255, 255), 0.22);
end;

{ ------------------------------------------------------------------------ }
{ line icons - all stroked, so they scale and stay crisp                    }
{ ------------------------------------------------------------------------ }

procedure PaintIcon(S: TArtSurface; Kind: TIconKind; const R: TRect;
  const C: TPix; Alpha: Single);
var
  X, Y, W, H, U, CX, CY, LW, RR: Single;

  function Px(FX, FY: Single): TPointF;
  begin
    Result := PtF(X + FX * W, Y + FY * H);
  end;

var
  P: TPointF;
  K: Integer;
begin
  S.BlendMode := bmNormal;
  X := R.Left;
  Y := R.Top;
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  U := Min(W, H);
  CX := X + W / 2;
  CY := Y + H / 2;
  LW := Max(1.6, U * 0.11);

  case Kind of
    ikTPoint:
      begin
        S.Ring(CX, CY, U * 0.17, LW, C, Alpha);
        S.Disc(CX, CY, LW * 0.7, C, Alpha);
      end;

    { the usual arrow, pointing up and to the left }
    ikTSelect:
      S.Poly([Px(0.30, 0.16), Px(0.30, 0.80), Px(0.46, 0.64), Px(0.57, 0.86),
              Px(0.67, 0.80), Px(0.56, 0.60), Px(0.74, 0.58)],
        LW, C, True, Alpha);

    { four arrowheads on a cross - move in any direction }
    ikTMove:
      begin
        S.Line(CX, Y + H * 0.18, CX, Y + H * 0.82, LW, C, Alpha);
        S.Line(X + W * 0.18, CY, X + W * 0.82, CY, LW, C, Alpha);
        S.Line(CX, Y + H * 0.18, CX - U * 0.11, Y + H * 0.30, LW, C, Alpha);
        S.Line(CX, Y + H * 0.18, CX + U * 0.11, Y + H * 0.30, LW, C, Alpha);
        S.Line(CX, Y + H * 0.82, CX - U * 0.11, Y + H * 0.70, LW, C, Alpha);
        S.Line(CX, Y + H * 0.82, CX + U * 0.11, Y + H * 0.70, LW, C, Alpha);
        S.Line(X + W * 0.18, CY, X + W * 0.30, CY - U * 0.11, LW, C, Alpha);
        S.Line(X + W * 0.18, CY, X + W * 0.30, CY + U * 0.11, LW, C, Alpha);
        S.Line(X + W * 0.82, CY, X + W * 0.70, CY - U * 0.11, LW, C, Alpha);
        S.Line(X + W * 0.82, CY, X + W * 0.70, CY + U * 0.11, LW, C, Alpha);
      end;

    ikTLine:
      begin
        S.Line(X + W * 0.22, Y + H * 0.74, X + W * 0.78, Y + H * 0.26, LW, C, Alpha);
        S.Disc(X + W * 0.22, Y + H * 0.74, LW * 0.9, C, Alpha);
        S.Disc(X + W * 0.78, Y + H * 0.26, LW * 0.9, C, Alpha);
      end;

    ikTRect:
      S.Poly([Px(0.20, 0.28), Px(0.80, 0.28), Px(0.80, 0.72), Px(0.20, 0.72)],
        LW, C, True, Alpha);


    ikTRotate:
      begin
        { three quarters of a circle with an arrowhead on its end }
        for K := 0 to 17 do
          S.Line(CX + U * 0.30 * Cos(K * Pi / 12), CY + U * 0.30 * Sin(K * Pi / 12),
                 CX + U * 0.30 * Cos((K + 1) * Pi / 12), CY + U * 0.30 * Sin((K + 1) * Pi / 12),
                 LW, C, Alpha);
        S.Line(CX + U * 0.30, CY, CX + U * 0.30 - U * 0.13, CY + U * 0.02, LW, C, Alpha);
        S.Line(CX + U * 0.30, CY, CX + U * 0.30 + U * 0.11, CY + U * 0.09, LW, C, Alpha);
      end;

    ikTProtractor:
      begin
        { a half circle on a baseline, with its ticks }
        for K := 0 to 11 do
          S.Line(CX + U * 0.34 * Cos(Pi + K * Pi / 12), CY + U * 0.14 + U * 0.34 * Sin(Pi + K * Pi / 12),
                 CX + U * 0.34 * Cos(Pi + (K + 1) * Pi / 12), CY + U * 0.14 + U * 0.34 * Sin(Pi + (K + 1) * Pi / 12),
                 LW, C, Alpha);
        S.Line(CX - U * 0.34, CY + U * 0.14, CX + U * 0.34, CY + U * 0.14, LW, C, Alpha);
        for K := 1 to 5 do
          S.Line(CX + U * 0.34 * Cos(Pi + K * Pi / 6), CY + U * 0.14 + U * 0.34 * Sin(Pi + K * Pi / 6),
                 CX + U * 0.26 * Cos(Pi + K * Pi / 6), CY + U * 0.14 + U * 0.26 * Sin(Pi + K * Pi / 6),
                 LW, C, Alpha);
      end;

    ikTFollow:
      begin
        { a profile spun round an axis: the axis, and the belly it sweeps }
        S.Line(CX, Y + H * 0.12, CX, Y + H * 0.88, LW, C, Alpha);
        S.Line(CX, CY - U * 0.30, CX + U * 0.34, CY - U * 0.22, LW, C, Alpha);
        S.Line(CX + U * 0.34, CY - U * 0.22, CX + U * 0.40, CY, LW, C, Alpha);
        S.Line(CX + U * 0.40, CY, CX + U * 0.34, CY + U * 0.22, LW, C, Alpha);
        S.Line(CX + U * 0.34, CY + U * 0.22, CX, CY + U * 0.30, LW, C, Alpha);
        S.Line(CX, CY - U * 0.30, CX - U * 0.34, CY - U * 0.22, LW * 0.6, C, Alpha * 0.55);
        S.Line(CX - U * 0.34, CY - U * 0.22, CX - U * 0.40, CY, LW * 0.6, C, Alpha * 0.55);
        S.Line(CX - U * 0.40, CY, CX - U * 0.34, CY + U * 0.22, LW * 0.6, C, Alpha * 0.55);
        S.Line(CX - U * 0.34, CY + U * 0.22, CX, CY + U * 0.30, LW * 0.6, C, Alpha * 0.55);
      end;

    ikTDrill:
      begin
        { a bit going down through a bar: the bar is what it goes through }
        S.Line(X + W * 0.22, CY + U * 0.02, X + W * 0.78, CY + U * 0.02, LW, C, Alpha);
        S.Line(X + W * 0.22, CY + U * 0.14, X + W * 0.78, CY + U * 0.14, LW, C, Alpha);
        S.Line(CX, Y + H * 0.14, CX, Y + H * 0.86, LW, C, Alpha);
        S.Line(CX - U * 0.10, Y + H * 0.30, CX + U * 0.10, Y + H * 0.42, LW, C, Alpha);
        S.Line(CX - U * 0.10, Y + H * 0.46, CX + U * 0.10, Y + H * 0.58, LW, C, Alpha);
        S.Line(CX - U * 0.08, Y + H * 0.74, CX, Y + H * 0.86, LW, C, Alpha);
        S.Line(CX + U * 0.08, Y + H * 0.74, CX, Y + H * 0.86, LW, C, Alpha);
      end;

    ikTOffset:
      begin
        S.Poly([Px(0.32, 0.38), Px(0.68, 0.38), Px(0.68, 0.62), Px(0.32, 0.62)],
          LW, C, True, Alpha);
        S.Poly([Px(0.18, 0.26), Px(0.82, 0.26), Px(0.82, 0.74), Px(0.18, 0.74)],
          LW * 0.8, C, True, Alpha * 0.55);
      end;

    ikTArc:
      begin
        S.Arc(CX, Y + H * 0.78, U * 0.34, Pi, 2 * Pi, LW, C, Alpha);
        S.Line(X + W * 0.16, Y + H * 0.78, X + W * 0.84, Y + H * 0.78,
          LW * 0.7, C, Alpha * 0.55);
      end;

    ikTCircle:
      S.Ring(CX, CY, U * 0.30, LW, C, Alpha);

    ikTPush:
      begin
        S.Poly([Px(0.24, 0.62), Px(0.52, 0.74), Px(0.80, 0.62), Px(0.52, 0.50)],
          LW * 0.8, C, True, Alpha);
        S.Line(CX, Y + H * 0.50, CX, Y + H * 0.20, LW, C, Alpha);
        S.Poly([PtF(CX - U * 0.11, Y + H * 0.31), PtF(CX, Y + H * 0.18),
                PtF(CX + U * 0.11, Y + H * 0.31)], LW, C, False, Alpha);
      end;

    ikTText:
      begin
        S.Line(X + W * 0.24, Y + H * 0.28, X + W * 0.76, Y + H * 0.28, LW, C, Alpha);
        S.Line(CX, Y + H * 0.28, CX, Y + H * 0.74, LW, C, Alpha);
      end;

    ikTErase:
      begin
        S.Poly([Px(0.20, 0.66), Px(0.52, 0.30), Px(0.80, 0.50), Px(0.48, 0.76)],
          LW, C, True, Alpha);
        S.Line(X + W * 0.30, Y + H * 0.78, X + W * 0.82, Y + H * 0.78,
          LW * 0.8, C, Alpha * 0.6);
      end;

    ikTMeasure:
      begin
        S.Poly([Px(0.16, 0.40), Px(0.84, 0.40), Px(0.84, 0.62), Px(0.16, 0.62)],
          LW * 0.8, C, True, Alpha);
        S.Line(X + W * 0.34, Y + H * 0.40, X + W * 0.34, Y + H * 0.52, LW * 0.7, C, Alpha);
        S.Line(X + W * 0.50, Y + H * 0.40, X + W * 0.50, Y + H * 0.55, LW * 0.7, C, Alpha);
        S.Line(X + W * 0.66, Y + H * 0.40, X + W * 0.66, Y + H * 0.52, LW * 0.7, C, Alpha);
      end;

    ikTOrbit:
      begin
        S.Ring(CX, CY, U * 0.30, LW * 0.9, C, Alpha);
        S.Arc(CX, CY, U * 0.30, Pi * 0.15, Pi * 0.85, LW * 0.5, C, Alpha * 0.5);
        S.Disc(CX + U * 0.30, CY, LW * 1.1, C, Alpha);
      end;

    ikChevron:
      S.Poly([PtF(CX - U * 0.16, CY - U * 0.08), PtF(CX, CY + U * 0.10),
              PtF(CX + U * 0.16, CY - U * 0.08)], LW, C, False, Alpha);

    { A spanner: a ring with a bite out of it at the top left and a shaft
      down to the right.  It only has to read at 16 pixels. }
    ikShop:
      begin
        S.Arc(CX - U * 0.16, CY - U * 0.16, U * 0.15, Pi * 0.15, Pi * 1.75,
              LW, C, Alpha);
        S.Line(CX - U * 0.08, CY - U * 0.06, CX + U * 0.24, CY + U * 0.26,
               LW * 1.6, C, Alpha);
      end;

    ikUndo, ikRedo:
      begin
        if Kind = ikUndo then
        begin
          S.Arc(CX, CY + U * 0.06, U * 0.30, Pi * 1.05, Pi * 2.35, LW, C, Alpha);
          P := PtF(CX - U * 0.30, CY - U * 0.20);
          S.Poly([PtF(P.X - U * 0.13, P.Y + U * 0.02),
                  P,
                  PtF(P.X + U * 0.05, P.Y + U * 0.17)], LW, C, False, Alpha);
        end
        else
        begin
          S.Arc(CX, CY + U * 0.06, U * 0.30, Pi * 0.65, Pi * 1.95, LW, C, Alpha);
          P := PtF(CX + U * 0.30, CY - U * 0.20);
          S.Poly([PtF(P.X + U * 0.13, P.Y + U * 0.02),
                  P,
                  PtF(P.X - U * 0.05, P.Y + U * 0.17)], LW, C, False, Alpha);
        end;
      end;

    ikSave:
      begin
        S.Poly([Px(0.24, 0.60), Px(0.24, 0.78), Px(0.76, 0.78), Px(0.76, 0.60)],
          LW, C, False, Alpha);
        S.Line(CX, Y + H * 0.20, CX, Y + H * 0.58, LW, C, Alpha);
        S.Poly([Px(0.34, 0.44), Px(0.50, 0.60), Px(0.66, 0.44)], LW, C, False, Alpha);
      end;

    ikPrint:
      begin
        S.Poly([Px(0.30, 0.36), Px(0.30, 0.20), Px(0.70, 0.20), Px(0.70, 0.36)],
          LW, C, False, Alpha);
        S.RoundFrame(Rect(Round(X + W * 0.18), Round(Y + H * 0.36),
                          Round(X + W * 0.82), Round(Y + H * 0.66)),
                     U * 0.08, LW, C, Alpha);
        S.RoundFrame(Rect(Round(X + W * 0.32), Round(Y + H * 0.60),
                          Round(X + W * 0.68), Round(Y + H * 0.84)),
                     U * 0.05, LW, C, Alpha);
      end;

    ikTheme:
      begin
        { a contrast disc: outlined circle with one half filled }
        S.Ring(CX, CY, U * 0.32, LW, C, Alpha);
        RR := 0;
        while RR < U * 0.30 do
        begin
          S.Arc(CX, CY, RR, -Pi / 2, Pi / 2, 1.3, C, Alpha);
          RR := RR + 0.6;
        end;
      end;

    ikGrid:
      begin
        S.RoundFrame(Rect(Round(X + W * 0.22), Round(Y + H * 0.22),
                          Round(X + W * 0.78), Round(Y + H * 0.78)),
                     U * 0.06, LW * 0.9, C, Alpha);
        S.Line(CX, Y + H * 0.22, CX, Y + H * 0.78, LW * 0.7, C, Alpha * 0.85);
        S.Line(X + W * 0.22, CY, X + W * 0.78, CY, LW * 0.7, C, Alpha * 0.85);
      end;

    ikHelp:
      begin
        S.Ring(CX, CY, U * 0.34, LW * 0.9, C, Alpha);
        S.Arc(CX, CY - U * 0.10, U * 0.13, Pi * 0.95, Pi * 2.15, LW * 0.9, C, Alpha);
        S.Line(CX + U * 0.005, CY - U * 0.01, CX + U * 0.005, CY + U * 0.10, LW * 0.9, C, Alpha);
        S.Disc(CX, CY + U * 0.21, LW * 0.55, C, Alpha);
      end;

    ikUnits:
      begin
        { a ruler with tick marks }
        S.RoundFrame(Rect(Round(X + W * 0.14), Round(Y + H * 0.36),
                          Round(X + W * 0.86), Round(Y + H * 0.64)),
                     U * 0.05, LW * 0.9, C, Alpha);
        S.Line(X + W * 0.30, Y + H * 0.36, X + W * 0.30, Y + H * 0.52, LW * 0.7, C, Alpha);
        S.Line(X + W * 0.44, Y + H * 0.36, X + W * 0.44, Y + H * 0.46, LW * 0.7, C, Alpha);
        S.Line(X + W * 0.58, Y + H * 0.36, X + W * 0.58, Y + H * 0.52, LW * 0.7, C, Alpha);
        S.Line(X + W * 0.72, Y + H * 0.36, X + W * 0.72, Y + H * 0.46, LW * 0.7, C, Alpha);
      end;

    ikDim:
      begin
        { a dimension line between two extension lines }
        S.Line(X + W * 0.20, Y + H * 0.22, X + W * 0.20, Y + H * 0.72, LW * 0.7, C, Alpha * 0.8);
        S.Line(X + W * 0.80, Y + H * 0.22, X + W * 0.80, Y + H * 0.72, LW * 0.7, C, Alpha * 0.8);
        S.Line(X + W * 0.20, Y + H * 0.60, X + W * 0.80, Y + H * 0.60, LW * 0.9, C, Alpha);
        S.Triangle(PtF(X + W * 0.20, CY + U * 0.10),
                   PtF(X + W * 0.34, CY + U * 0.02),
                   PtF(X + W * 0.34, CY + U * 0.19), C, Alpha);
        S.Triangle(PtF(X + W * 0.80, CY + U * 0.10),
                   PtF(X + W * 0.66, CY + U * 0.02),
                   PtF(X + W * 0.66, CY + U * 0.19), C, Alpha);
      end;

    ikMeasure:
      begin
        { calipers }
        S.Line(X + W * 0.16, Y + H * 0.30, X + W * 0.84, Y + H * 0.30, LW, C, Alpha);
        S.Line(X + W * 0.24, Y + H * 0.30, X + W * 0.24, Y + H * 0.78, LW, C, Alpha);
        S.Line(X + W * 0.66, Y + H * 0.30, X + W * 0.66, Y + H * 0.66, LW, C, Alpha);
        S.Line(X + W * 0.16, Y + H * 0.20, X + W * 0.16, Y + H * 0.40, LW * 0.8, C, Alpha);
        S.Line(X + W * 0.84, Y + H * 0.20, X + W * 0.84, Y + H * 0.40, LW * 0.8, C, Alpha);
      end;

    ikOrigin:
      begin
        S.Ring(CX, CY, U * 0.20, LW * 0.9, C, Alpha);
        S.Line(CX - U * 0.38, CY, CX - U * 0.26, CY, LW * 0.9, C, Alpha);
        S.Line(CX + U * 0.26, CY, CX + U * 0.38, CY, LW * 0.9, C, Alpha);
        S.Line(CX, CY - U * 0.38, CX, CY - U * 0.26, LW * 0.9, C, Alpha);
        S.Line(CX, CY + U * 0.26, CX, CY + U * 0.38, LW * 0.9, C, Alpha);
      end;

    ikOpen:
      begin
        { a folder }
        S.Poly([Px(0.16, 0.74), Px(0.16, 0.30), Px(0.42, 0.30), Px(0.50, 0.40),
                Px(0.84, 0.40), Px(0.84, 0.74)], LW * 0.9, C, True, Alpha);
      end;

    ikFit:
      begin
        S.RoundFrame(Rect(Round(X + W * 0.20), Round(Y + H * 0.24),
                          Round(X + W * 0.80), Round(Y + H * 0.76)),
                     U * 0.06, LW * 0.8, C, Alpha * 0.6);
        S.Line(CX - U * 0.20, CY - U * 0.10, CX - U * 0.20, CY - U * 0.20, LW, C, Alpha);
        S.Line(CX - U * 0.20, CY - U * 0.20, CX - U * 0.10, CY - U * 0.20, LW, C, Alpha);
        S.Line(CX + U * 0.20, CY + U * 0.10, CX + U * 0.20, CY + U * 0.20, LW, C, Alpha);
        S.Line(CX + U * 0.20, CY + U * 0.20, CX + U * 0.10, CY + U * 0.20, LW, C, Alpha);
        S.Line(CX - U * 0.18, CY - U * 0.18, CX + U * 0.18, CY + U * 0.18, LW * 0.8, C, Alpha);
      end;

    ikExport:
      begin
        S.Poly([Px(0.24, 0.62), Px(0.24, 0.80), Px(0.76, 0.80), Px(0.76, 0.62)],
          LW, C, False, Alpha);
        S.Line(CX, Y + H * 0.66, CX, Y + H * 0.24, LW, C, Alpha);
        S.Poly([Px(0.34, 0.40), Px(0.50, 0.24), Px(0.66, 0.40)], LW, C, False, Alpha);
      end;

    ikArrow:
      begin
        S.Poly([Px(0.30, 0.16), Px(0.30, 0.78), Px(0.45, 0.63),
                Px(0.56, 0.84), Px(0.66, 0.79), Px(0.55, 0.59), Px(0.74, 0.55)],
          LW * 0.85, C, True, Alpha);
      end;

    ikDroplet:
      begin
        S.Arc(CX, CY + U * 0.08, U * 0.26, 0, 2 * Pi, LW, C, Alpha);
        S.Poly([PtF(CX - U * 0.185, CY - U * 0.10), PtF(CX, CY - U * 0.36),
                PtF(CX + U * 0.185, CY - U * 0.10)], LW, C, False, Alpha);
      end;
  end;
end;

{ A fresh sheet of paper. }
procedure PaintScreenPaper(S: TArtSurface; const T: TTheme);
var
  X, Y: Integer;
  C: TPix;
  P: PPix;
begin
  S.BlendMode := bmNormal;

  for Y := 0 to S.Height - 1 do
  begin
    C := MixPix(T.Screen1, T.Screen2, Y / Max(1, S.Height - 1));
    P := S.ScanLine(Y);
    for X := 0 to S.Width - 1 do
    begin
      P^ := C;
      P^.A := 255;
      Inc(P);
    end;
  end;
  S.Touch;

  { faint speckle so the screen reads as powder, not paper }
  S.Grain(0.05, 0.16);
  S.Touch;
end;

{ The recess around the screen opening.  This is painted on the chassis, not
  on the sketch, so it never gets baked into the artwork. }
procedure PaintScreenWell(S: TArtSurface; const R: TRect; Radius: Single);
var
  I: Integer;
begin
  S.BlendMode := bmNormal;
  for I := 0 to 9 do
    S.RoundFrame(Rect(R.Left - I, R.Top - I, R.Right + I, R.Bottom + I),
      Radius + I, 1.0, Pix(0, 0, 0), 0.07 * (1 - I / 11));
  S.RoundFrame(Rect(R.Left - 1, R.Top - 1, R.Right + 1, R.Bottom + 1),
    Radius, 1.2, Pix(0, 0, 0), 0.5);
  S.Touch;
end;

{ A grid in real units, anchored to the drawing origin so the lines land on
  whole feet (or meters) no matter where the paper has been panned to. }
procedure PaintMeasuredGrid(S: TArtSurface; const T: TTheme;
  Ppu, OX, OY: Double; MajorEvery: Integer);
var
  I, First, Last: Integer;
  V: Double;
  Major: Boolean;
begin
  if Ppu < 3 then Exit;          // too dense to be anything but noise
  S.BlendMode := bmNormal;

  First := Floor(-OX / Ppu);
  Last := Ceil((S.Width - OX) / Ppu);
  for I := First to Last do
  begin
    V := OX + I * Ppu;
    Major := (MajorEvery > 0) and (I mod MajorEvery = 0);
    if Major then
      S.Line(V, 0, V, S.Height, 1.0, T.Grid, 0.85)
    else if Ppu >= 7 then
      S.Line(V, 0, V, S.Height, 1.0, T.Grid, 0.34);
  end;

  First := Floor((OY - S.Height) / Ppu);
  Last := Ceil(OY / Ppu);
  for I := First to Last do
  begin
    V := OY - I * Ppu;
    Major := (MajorEvery > 0) and (I mod MajorEvery = 0);
    if Major then
      S.Line(0, V, S.Width, V, 1.0, T.Grid, 0.85)
    else if Ppu >= 7 then
      S.Line(0, V, S.Width, V, 1.0, T.Grid, 0.34);
  end;

  { the origin itself gets an axis cross }
  S.Line(OX, 0, OX, S.Height, 1.4, T.Accent, 0.35);
  S.Line(0, OY, S.Width, OY, 1.4, T.Accent, 0.35);
  S.Touch;
end;

initialization
  InitThemes;

end.

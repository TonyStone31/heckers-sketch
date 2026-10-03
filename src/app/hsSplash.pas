unit hsSplash;

{ The start-up screen.  Shows what is loading and how far along, and offers
  to skip a slow drawing.  Stays up at least a few seconds so it does not
  just flash.  Main thread only; the main form uses the procedures below,
  never the form itself. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, Forms, Controls, Graphics, hsSurface, hsSkin;

const
  SPLASH_MIN_MS = 4000;

{ shows the splash with the version on it }
procedure SplashShow;
{ Frac is 0..1, or below 0 when progress is unknown.  Skippable shows the
  skip button. }
procedure SplashStatus(const Msg: string; Frac: Double; Skippable: Boolean);
{ loading is done; shows Msg and removes the skip button }
procedure SplashLoaded(const Msg: string);
{ skip was pressed and not yet reset }
function SplashSkipAsked: Boolean;
procedure SplashSkipReset;
function SplashUp: Boolean;
function SplashFinished: Boolean;
{ milliseconds since it went up }
function SplashAge: QWord;
procedure SplashHide;

implementation

{$R *.lfm}

{$I version.inc}

type
  TSplashForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure SplashPaint(Sender: TObject);
    procedure SplashMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  private
    FSkin: TArtSurface;
    FTheme: TTheme;
    FScale: Single;
    FMsg: string;
    FFrac: Double;
    FSkippable, FSkip, FLoaded: Boolean;
    FShownAt, FPaintedAt: QWord;
    FSkipRect: TRect;
  end;

var
  Splash: TSplashForm = nil;

{ The form is not Scaled and is sized here; the LCL's high-DPI pass would
  scale it a second time.  Not fsSplash either: the LCL hides those as soon
  as the main window shows, and this one must outlast that. }
procedure TSplashForm.FormCreate(Sender: TObject);
begin
  FTheme := Themes[THEME_DARK];
  FScale := Max(1.0, Screen.PixelsPerInch / 96);
  ClientWidth := Round(620 * FScale);
  ClientHeight := Round(330 * FScale);
  Color := PixToColor(FTheme.Shell2);
  FSkin := TArtSurface.Create(ClientWidth, ClientHeight);
  FMsg := 'Starting';
  FFrac := -1;
  FShownAt := GetTickCount64;
end;

procedure TSplashForm.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FSkin);
end;

procedure TSplashForm.SplashPaint(Sender: TObject);
var
  Pad, Y, W, H, BarY, BarH, BarW, X0, K: Integer;
  S: string;
  Ph: Double;
  Cx, Cy, R: Single;

  { a small wire cube in the corner }
  procedure Cube(CX, CY, Sz: Single);
  var
    Dx, Dy: Single;
  begin
    Dx := Sz * 0.866;
    Dy := Sz * 0.5;
    { top }
    FSkin.Line(CX, CY - Sz, CX + Dx, CY - Dy, 1.6, FTheme.Accent, 0.9);
    FSkin.Line(CX + Dx, CY - Dy, CX, CY, 1.6, FTheme.Accent, 0.9);
    FSkin.Line(CX, CY, CX - Dx, CY - Dy, 1.6, FTheme.Accent, 0.9);
    FSkin.Line(CX - Dx, CY - Dy, CX, CY - Sz, 1.6, FTheme.Accent, 0.9);
    { the three uprights and the bottom }
    FSkin.Line(CX, CY, CX, CY + Sz, 1.6, FTheme.Accent, 0.9);
    FSkin.Line(CX + Dx, CY - Dy, CX + Dx, CY + Sz - Dy, 1.6, FTheme.Accent, 0.9);
    FSkin.Line(CX - Dx, CY - Dy, CX - Dx, CY + Sz - Dy, 1.6, FTheme.Accent, 0.9);
    FSkin.Line(CX, CY + Sz, CX + Dx, CY + Sz - Dy, 1.6, FTheme.Accent, 0.9);
    FSkin.Line(CX, CY + Sz, CX - Dx, CY + Sz - Dy, 1.6, FTheme.Accent, 0.9);
    { the hidden edges, faint }
    FSkin.Line(CX, CY - Dy * 2, CX + Dx, CY - Dy * 3, 1.0, FTheme.TextDim, 0.35);
    FSkin.Line(CX, CY - Dy * 2, CX - Dx, CY - Dy * 3, 1.0, FTheme.TextDim, 0.35);
    FSkin.Line(CX, CY - Dy * 2, CX, CY, 1.0, FTheme.TextDim, 0.35);
  end;

begin
  W := ClientWidth;
  H := ClientHeight;

  { fit the window's actual size, which the widgetset or window manager may
    have changed from what was asked for }
  if (FSkin = nil) or (FSkin.Width <> W) or (FSkin.Height <> H) then
  begin
    FSkin.Free;
    FSkin := TArtSurface.Create(Max(1, W), Max(1, H));
  end;
  FScale := Max(0.5, W / 620);

  Pad := Round(36 * FScale);
  PaintShell(FSkin, FTheme);
  FSkin.RoundFrame(Rect(1, 1, W - 1, H - 1), Round(16 * FScale), 2.0, FTheme.Accent, 0.85);
  FSkin.Line(Pad, Round(112 * FScale), W - Pad, Round(112 * FScale), 1.4, FTheme.Accent, 0.6);
  Cube(W - Pad - 58 * FScale, 62 * FScale, 34 * FScale);

  { progress bar: a fill when progress is known, else a moving light }
  BarH := Round(10 * FScale);
  BarY := H - Round(78 * FScale);
  BarW := W - 2 * Pad;
  FSkin.RoundRect(Rect(Pad, BarY, Pad + BarW, BarY + BarH), BarH / 2, FTheme.Panel, 1.0);
  if FFrac >= 0 then
  begin
    K := Round(BarW * EnsureRange(FFrac, 0, 1));
    if K > 0 then
      FSkin.RoundRect(Rect(Pad, BarY, Pad + Max(K, BarH), BarY + BarH), BarH / 2, FTheme.Accent, 1.0);
  end
  else if not FLoaded then
  begin
    Ph := ((GetTickCount64 - FShownAt) mod 1400) / 1400;
    K := Round(BarW * 0.22);
    X0 := Pad + Round((BarW - K) * (0.5 - 0.5 * Cos(Ph * 2 * Pi)));
    FSkin.RoundRect(Rect(X0, BarY, X0 + K, BarY + BarH), BarH / 2, FTheme.Accent, 0.9);
  end
  else
    FSkin.RoundRect(Rect(Pad, BarY, Pad + BarW, BarY + BarH), BarH / 2, FTheme.Accent, 1.0);

  { the skip button }
  FSkipRect := Rect(0, 0, 0, 0);
  if FSkippable and not FLoaded then
  begin
    FSkipRect := Rect(W - Pad - Round(170 * FScale), H - Round(52 * FScale),
                      W - Pad, H - Round(22 * FScale));
    FSkin.RoundRect(FSkipRect, (FSkipRect.Bottom - FSkipRect.Top) / 2, FTheme.Panel, 1.0);
    FSkin.RoundFrame(FSkipRect, (FSkipRect.Bottom - FSkipRect.Top) / 2, 1.2, FTheme.Accent, 0.8);
  end;
  FSkin.DrawTo(Canvas, 0, 0);

  Canvas.Brush.Style := bsClear;
  Canvas.Font.Name := {$IFDEF WINDOWS}'Segoe UI'{$ELSE}'Sans'{$ENDIF};

  Canvas.Font.Height := -Round(30 * FScale);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := PixToColor(FTheme.Text);
  Canvas.TextOut(Pad, Round(38 * FScale), 'HECKERS SKETCH');

  Canvas.Font.Height := -Round(12 * FScale);
  Canvas.Font.Style := [];
  Canvas.Font.Color := PixToColor(FTheme.Accent);
  Canvas.TextOut(Pad, Round(80 * FScale), 'NozelFab Incorporated');
  Canvas.Font.Color := PixToColor(FTheme.TextDim);
  S := APP_VERSION;
  Canvas.TextOut(W - Pad - Canvas.TextWidth(S) - Round(120 * FScale), Round(80 * FScale), S);

  Canvas.Font.Height := -Round(14 * FScale);
  Canvas.Font.Color := PixToColor(FTheme.Text);
  Y := Round(140 * FScale);
  Canvas.TextOut(Pad, Y, FMsg);

  if (FFrac >= 0) and not FLoaded then
  begin
    Canvas.Font.Height := -Round(12 * FScale);
    Canvas.Font.Color := PixToColor(FTheme.TextDim);
    S := Format('%d%%', [Round(EnsureRange(FFrac, 0, 1) * 100)]);
    Canvas.TextOut(W - Pad - Canvas.TextWidth(S), BarY - Round(20 * FScale), S);
  end;

  if FSkipRect.Right > FSkipRect.Left then
  begin
    Canvas.Font.Height := -Round(12 * FScale);
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := PixToColor(FTheme.Accent);
    S := 'Skip this drawing';
    Canvas.TextOut((FSkipRect.Left + FSkipRect.Right - Canvas.TextWidth(S)) div 2,
      (FSkipRect.Top + FSkipRect.Bottom - Canvas.TextHeight(S)) div 2, S);
  end;
  FPaintedAt := GetTickCount64;
end;

procedure TSplashForm.SplashMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (FSkipRect.Right > FSkipRect.Left) and PtInRect(FSkipRect, Point(X, Y)) then
  begin
    FSkip := True;
    FMsg := 'Skipping - one moment';
    FSkippable := False;
    Invalidate;
    Update;
  end
  else if FLoaded then
    SplashHide;
end;

procedure SplashShow;
begin
  if Splash <> nil then Exit;
  Splash := TSplashForm.Create(nil);
  Splash.Show;
  Splash.Update;
  Application.ProcessMessages;
end;

procedure SplashStatus(const Msg: string; Frac: Double; Skippable: Boolean);
var
  Changed: Boolean;
begin
  if Splash = nil then Exit;
  Changed := (Msg <> Splash.FMsg) or (Skippable <> Splash.FSkippable);
  Splash.FMsg := Msg;
  Splash.FFrac := Frac;
  Splash.FSkippable := Skippable;
  { paint at most every 40 ms, whatever the caller's rate }
  if Changed or (GetTickCount64 - Splash.FPaintedAt > 40) then
  begin
    Splash.Invalidate;
    Splash.Update;
    Application.ProcessMessages;
  end;
end;

procedure SplashLoaded(const Msg: string);
begin
  if Splash = nil then Exit;
  Splash.FLoaded := True;
  Splash.FSkippable := False;
  Splash.FMsg := Msg;
  Splash.FFrac := 1;
  Splash.Invalidate;
  Splash.Update;
  Application.ProcessMessages;
end;

function SplashSkipAsked: Boolean;
begin
  Result := (Splash <> nil) and Splash.FSkip;
end;

procedure SplashSkipReset;
begin
  if Splash <> nil then Splash.FSkip := False;
end;

function SplashUp: Boolean;
begin
  Result := Splash <> nil;
end;

function SplashFinished: Boolean;
begin
  Result := (Splash <> nil) and Splash.FLoaded;
end;

function SplashAge: QWord;
begin
  if Splash = nil then Result := High(QWord)
  else Result := GetTickCount64 - Splash.FShownAt;
end;

procedure SplashHide;
var
  F: TSplashForm;
begin
  if Splash = nil then Exit;
  F := Splash;
  Splash := nil;
  F.Hide;
  F.Free;
end;

end.

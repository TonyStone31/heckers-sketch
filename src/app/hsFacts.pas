unit hsFacts;

{ A painted box of "name: value" lines, used by /sysinfo.  Names are drawn
  in the accent color and values lined up beside them.  Sized to its lines;
  any click or key closes it.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics,
  hsSurface, hsSkin, hsDialogSkin;

type
  TFactsBox = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormPaint(Sender: TObject);
    procedure FormClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FSkin: TArtSurface;
    FTheme: TTheme;
    FScale: Single;
    FTitle: string;
    FLines: TStringList;
  end;

{ Shows AText under Title modally, in the current dialog theme. }
procedure ShowFactsBox(AOwner: TComponent; const Title, AText: string);

implementation

{$R *.lfm}

procedure ShowFactsBox(AOwner: TComponent; const Title, AText: string);
var
  Box: TFactsBox;
begin
  Box := TFactsBox.Create(AOwner);
  try
    Box.FTitle := Title;
    Box.FLines.Text := AText;
    while (Box.FLines.Count > 0) and
          (Trim(Box.FLines[Box.FLines.Count - 1]) = '') do
      Box.FLines.Delete(Box.FLines.Count - 1);
    { title, one row per line, and the note along the bottom }
    Box.ClientHeight := Round((124 + 22 * Box.FLines.Count) * Box.FScale);
    Box.ShowModal;
  finally
    Box.Free;
  end;
end;

procedure TFactsBox.FormCreate(Sender: TObject);
begin
  FTheme := hsDialogSkin.DlgTheme;
  FScale := EnsureRange(Screen.PixelsPerInch / 96, 1.0, 3.0);
  FLines := TStringList.Create;
  hsDialogSkin.ThemeForm(Self);
  Color := PixToColor(FTheme.Shell2);
end;

procedure TFactsBox.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FLines);
  FreeAndNil(FSkin);
end;

procedure TFactsBox.FormPaint(Sender: TObject);
var
  I, Y, Pad, Colon: Integer;
  S, K: string;
begin
  if (FSkin = nil) or (FSkin.Width <> ClientWidth) or
     (FSkin.Height <> ClientHeight) then
  begin
    FreeAndNil(FSkin);
    FSkin := TArtSurface.Create(Max(1, ClientWidth), Max(1, ClientHeight));
  end;
  Pad := Round(30 * FScale);
  PaintShell(FSkin, FTheme);
  FSkin.RoundFrame(Rect(1, 1, ClientWidth - 1, ClientHeight - 1),
    Round(14 * FScale), 2.0, FTheme.Accent, 0.85);
  FSkin.Line(Pad, Round(58 * FScale), ClientWidth - Pad, Round(58 * FScale),
    1.4, FTheme.Accent, 0.6);
  FSkin.DrawTo(Canvas, 0, 0);

  Canvas.Brush.Style := bsClear;
  Canvas.Font.Name := {$IFDEF WINDOWS}'Segoe UI'{$ELSE}'Sans'{$ENDIF};
  Canvas.Font.Height := -Round(18 * FScale);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := PixToColor(FTheme.Text);
  Canvas.TextOut(Pad, Round(22 * FScale), FTitle);

  Canvas.Font.Height := -Round(13 * FScale);
  Canvas.Font.Style := [];
  Y := Round(74 * FScale);
  for I := 0 to FLines.Count - 1 do
  begin
    S := FLines[I];
    Colon := Pos(': ', S);
    if Colon > 0 then
    begin
      { the name in the accent, the value in plain text }
      K := Copy(S, 1, Colon);
      Canvas.Font.Color := PixToColor(FTheme.Accent);
      Canvas.TextOut(Pad, Y, K);
      Canvas.Font.Color := PixToColor(FTheme.Text);
      Canvas.TextOut(Pad + Round(150 * FScale), Y, Trim(Copy(S, Colon + 1, MaxInt)));
    end
    else
    begin
      Canvas.Font.Color := PixToColor(FTheme.Text);
      Canvas.TextOut(Pad, Y, S);
    end;
    Inc(Y, Round(22 * FScale));
  end;

  Canvas.Font.Height := -Round(12 * FScale);
  Canvas.Font.Color := PixToColor(FTheme.TextDim);
  S := 'this goes with every report - click anywhere, or press Esc, to close';
  Canvas.TextOut((ClientWidth - Canvas.TextWidth(S)) div 2,
    ClientHeight - Round(28 * FScale), S);
end;

procedure TFactsBox.FormClick(Sender: TObject);
begin
  Close;
end;

procedure TFactsBox.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  Close;
  Key := 0;
end;

end.

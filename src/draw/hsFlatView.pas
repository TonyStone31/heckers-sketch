unit hsFlatView;

{ A window showing a piece laid out flat as a cutting pattern: solid lines
  are cuts, dashed lines are folds, and the sheet size is printed at the top. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, ExtCtrls,
  Dialogs, BCButton, hsDrawing, hsUnfold, hsDialogSkin;

{ Put a pattern on screen.  Returns when the window is closed. }
procedure ShowFlatPattern(const Pat: TFlatPattern; U: TUnitSystem;
  const Caption: string);

implementation

type
  TFlatForm = class(TForm)
    btnSaveDxf: TBCButton;
    procedure FormCreate(Sender: TObject);
    procedure FormPaint(Sender: TObject);
    procedure SaveDxfClick(Sender: TObject);
  public
    Pat: TFlatPattern;
    Units: TUnitSystem;
  end;

{$R *.lfm}

{ The sheet stays white in either theme; only the button takes the skin. }
procedure TFlatForm.FormCreate(Sender: TObject);
begin
  hsDialogSkin.ThemeForm(Self);
  Color := clWhite;
end;

procedure TFlatForm.FormPaint(Sender: TObject);
var
  I, J, K, H, N: Integer;
  Sc, OX, OY, W, HH, NX, NY, NL: Double;
  HeadH, FootH: Integer;
  Pts: array of TPoint;
  S: string;

  function SX(X: Double): Integer; inline;
  begin
    Result := Round(OX + (X - Pat.MinX) * Sc);
  end;

  function SY(Y: Double): Integer; inline;
  begin
    { screen Y runs down, sheet Y runs up }
    Result := Round(OY - (Y - Pat.MinY) * Sc);
  end;

begin
  HeadH := 58;
  FootH := 34;
  Canvas.Brush.Color := clWhite;
  Canvas.FillRect(0, 0, ClientWidth, ClientHeight);

  W := Max(Pat.MaxX - Pat.MinX, 1E-9);
  HH := Max(Pat.MaxY - Pat.MinY, 1E-9);
  Sc := Min((ClientWidth - 80) / W, (ClientHeight - HeadH - FootH - 40) / HH);
  if Sc <= 0 then Sc := 1;
  OX := (ClientWidth - W * Sc) / 2;
  OY := HeadH + (ClientHeight - HeadH - FootH - HH * Sc) / 2 + HH * Sc;

  { the panels, filled faintly so the shape of the sheet reads at a glance }
  Canvas.Pen.Style := psClear;
  for I := 0 to High(Pat.Faces) do
  begin
    Canvas.Brush.Color := $00F4F0EC;
    SetLength(Pts, Length(Pat.Faces[I].P));
    for J := 0 to High(Pat.Faces[I].P) do
      Pts[J] := Point(SX(Pat.Faces[I].P[J].X), SY(Pat.Faces[I].P[J].Y));
    Canvas.Polygon(Pts);
    { openings in the sheet color, so they read as missing metal }
    Canvas.Brush.Color := clWhite;
    for H := 0 to High(Pat.Faces[I].Holes) do
    begin
      SetLength(Pts, Length(Pat.Faces[I].Holes[H]));
      for J := 0 to High(Pat.Faces[I].Holes[H]) do
        Pts[J] := Point(SX(Pat.Faces[I].Holes[H][J].X),
                        SY(Pat.Faces[I].Holes[H][J].Y));
      if Length(Pts) >= 3 then Canvas.Polygon(Pts);
    end;
  end;
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Style := bsClear;

  { folds first, so a cut drawn over one still reads as a cut }
  for K := 0 to 1 do
    for I := 0 to High(Pat.Edges) do
    begin
      if (K = 0) <> (Pat.Edges[I].Kind = fkBend) then Continue;
      if Pat.Edges[I].Kind = fkBend then
      begin
        Canvas.Pen.Color := $00B07030;
        Canvas.Pen.Style := psDash;
        Canvas.Pen.Width := 1;
      end
      else if Pat.Edges[I].Kind = fkNotch then
      begin
        { brake notches are cuts, drawn heavier than the outline so they
          stand out at the end of a fold }
        Canvas.Pen.Color := $00202020;
        Canvas.Pen.Style := psSolid;
        Canvas.Pen.Width := 3;
      end
      else
      begin
        Canvas.Pen.Color := clBlack;
        Canvas.Pen.Style := psSolid;
        Canvas.Pen.Width := 2;
      end;
      if Pat.Edges[I].Kind = fkNotch then
      begin
        { The notch is true size in the pattern, which can be a fraction of
          a pixel on screen, so it is stretched to at least 12 pixels here. }
        NX := SX(Pat.Edges[I].BX) - SX(Pat.Edges[I].AX);
        NY := SY(Pat.Edges[I].BY) - SY(Pat.Edges[I].AY);
        NL := Sqrt(NX * NX + NY * NY);
        { stretch along the leg's own direction so a V notch keeps its shape }
        if (NL > 1E-6) and (NL < 12) then
        begin
          NX := NX * 12 / NL;
          NY := NY * 12 / NL;
        end;
        Canvas.Line(SX(Pat.Edges[I].AX), SY(Pat.Edges[I].AY),
                    SX(Pat.Edges[I].AX) + Round(NX), SY(Pat.Edges[I].AY) + Round(NY));
      end
      else
        Canvas.Line(SX(Pat.Edges[I].AX), SY(Pat.Edges[I].AY),
                    SX(Pat.Edges[I].BX), SY(Pat.Edges[I].BY));
    end;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;

  { what it is and what it needs }
  Canvas.Font.Name := 'Sans';
  Canvas.Font.Size := 11;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := clBlack;
  Canvas.TextOut(16, 12, Caption);

  Canvas.Font.Size := 9;
  Canvas.Font.Style := [];
  S := Format('sheet %s x %s', [FormatLen(W, Units), FormatLen(HH, Units)]);
  Canvas.TextOut(16, 34, S);

  Canvas.Font.Color := $00303030;
  S := Format('%d panels, %d folds', [Length(Pat.Faces), 0]);
  K := 0; N := 0;
  for I := 0 to High(Pat.Edges) do
    if Pat.Edges[I].Kind = fkBend then Inc(K)
    else if Pat.Edges[I].Kind = fkNotch then Inc(N);
  S := Format('%d panels, %d folds, %d brake notches  -  solid is cut, ' +
    'dashed is folded', [Length(Pat.Faces), K, N div 2]);
  Canvas.TextOut(16, ClientHeight - 26, S);

  if Pat.Overlaps then
  begin
    Canvas.Font.Color := $000000C0;
    Canvas.Font.Style := [fsBold];
    Canvas.TextOut(16, ClientHeight - 44,
      'This pattern folds back over itself - the seam wants moving.');
  end
  else if Pat.Laid < Pat.Total then
  begin
    Canvas.Font.Color := $000000C0;
    Canvas.TextOut(16, ClientHeight - 44,
      Format('Only %d of %d panels are joined to the rest.',
        [Pat.Laid, Pat.Total]));
  end;
end;

{ The pattern to a file a table can cut. }
procedure TFlatForm.SaveDxfClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  L: TStringList;
begin
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title := 'Save the flat pattern as DXF';
    Dlg.Filter := 'DXF for a cutting table|*.dxf';
    Dlg.DefaultExt := 'dxf';
    Dlg.FileName := 'flat-pattern-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.dxf';
    if not Dlg.Execute then Exit;
    L := TStringList.Create;
    try
      PatternToDxf(Pat, Units, L);
      L.SaveToFile(Dlg.FileName);
    finally
      L.Free;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure ShowFlatPattern(const Pat: TFlatPattern; U: TUnitSystem;
  const Caption: string);
var
  F: TFlatForm;
begin
  F := TFlatForm.Create(nil);
  try
    F.Pat := Pat;
    F.Units := U;
    F.Caption := Caption;
    F.ShowModal;
  finally
    F.Free;
  end;
end;

end.

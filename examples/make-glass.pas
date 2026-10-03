program makeglass;

{ The wine glass: the example for Revolve.  It draws half the outline and
  calls TWorkDoc.Revolve, the same code the tool uses, so it changes when the
  tool does.  The outline encloses the glass material, so the result is a
  closed solid that could be printed.  Sizes in inches; I_ turns them to feet.

  Run it to write examples/wine-glass.hsk and ../src/examples/hsExGlass.pas:
      cd examples
      fpc -Mobjfpc -Sh -Fu"../src/*" -Fu"../src/vendor/*" -Fi.. make-glass.pas && ./make-glass

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, Types, Graphics, hsSurface, hsDrawing, exwrite;

const
  { The glass, in inches, measured off a real red wine glass. }
  FOOT_R  = 1.60;   FOOT_T  = 0.12;    { the foot, and how thick its edge is }
  STEM_R  = 0.17;   STEM_TOP = 3.45;   { the stem }
  STEM_BOT = 0.95;
  BOWL_BOT = 4.05;  BOWL_R0 = 0.46;    { where the bowl leaves the stem }
  RIM_Z   = 8.50;   RIM_R   = 1.42;    { the rim, outside }
  WALL    = 0.13;   { how thick the glass is }
  BOWL_N  = 8;      { points down each side of the bowl }

  SIDES = 24;              { pieces round - smooth enough, and not a huge file }

  { a typical drawing area, to fit the camera to }
  ART_W = 1280;
  ART_H = 720;

  { TColor is $00BBGGRR }
  GLASS = $00E0D8C8;       { a pale cold gray, which is what glass reads as }

var
  D: TWorkDoc;
  L, U: TStringList;
  Pts: TP3Array;
  NP: Integer;
  I, Face, First, NFace, Grp: Integer;
  BaseP, Diag, CamZoom: Double;
  BLo, BHi, CamMid: TP3;
  CamV: TProjector;
  CamP: TPointF;

{ inches to the drawing's unit }
function I_(V: Double): Double;
begin
  Result := V / 12;
end;

{ Put a point on the end of the outline, in inches.  Revolve softens a
  joint that bends under thirty degrees and leaves a sharper one hard, so the
  bowl needs many points or it comes out banded like a barrel. }
procedure Put(R, Z: Double);
begin
  if NP >= Length(Pts) then SetLength(Pts, Max(16, NP * 2));
  Pts[NP] := P3(I_(R), 0, I_(Z));
  Inc(NP);
end;

{ one point of a cubic Bezier, for both sides of the bowl }
procedure Bez(R0, Z0, R1, Z1, R2, Z2, R3, Z3, T: Double);
var
  U, A, B, C, E: Double;
begin
  U := 1 - T;
  A := U * U * U;
  B := 3 * U * U * T;
  C := 3 * U * T * T;
  E := T * T * T;
  Put(A * R0 + B * R1 + C * R2 + E * R3,
      A * Z0 + B * Z1 + C * Z2 + E * Z3);
end;

begin
  D := TWorkDoc.Create;
  L := TStringList.Create;

  { --- the outline, in the XZ plane, standing on the ground -----------
    Up the outside, over the rim, down the inside to the axis, then down the
    axis to the start.  The bowl comes out hollow and the stem solid. }
  NP := 0;
  SetLength(Pts, 64);

  Put(0.00, 0.00);                        { the middle of the underside }
  Put(FOOT_R - 0.05, 0.00);               { out along the foot }
  Put(FOOT_R, FOOT_T);                    { the edge of it }
  Put(0.34, 0.40);                        { back in, over the top of the foot }
  Put(STEM_R, STEM_BOT);                  { into the stem }
  Put(STEM_R, STEM_TOP);                  { up the stem }

  { the outside of the bowl, leaving the stem and swelling to the rim }
  for I := 0 to BOWL_N do
    Bez(BOWL_R0, BOWL_BOT, 1.66, 4.55, 2.06, 6.95, RIM_R, RIM_Z,
        I / BOWL_N);

  { back down the inside, held in by the thickness of the glass }
  for I := 0 to BOWL_N do
    Bez(RIM_R - WALL, RIM_Z - 0.10, 1.92, 6.90, 1.52, 4.60, 0.33, 4.18,
        I / BOWL_N);

  Put(0.00, 3.92);                        { the bottom of the bowl, on the axis }

  SetLength(Pts, NP);
  D.AddFaceRaw(Pts, GLASS, False);
  Face := D.Live - 1;

  { The axis must not cross the outline, or the glass sweeps into itself.
    Check it the way the tool does and stop rather than write a wreck. }
  if D.AxisSplitsFace(Face, P3(0, 0, 0), P3(0, 0, 1), Diag, CamZoom) then
  begin
    WriteLn('the blue axis splits the outline - the profile is wrong');
    Halt(1);
  end;

  { --- spin it -------------------------------------------------------- }
  First := D.Revolve(Face, P3(0, 0, 0), P3(0, 0, 1), 2 * Pi, SIDES);
  if First < 0 then
  begin
    WriteLn('the revolve was refused');
    Halt(1);
  end;

  NFace := 0;
  Grp := 0;
  for I := 0 to D.Live - 1 do
    if D[I].Kind = ekFace then
    begin
      Inc(NFace);
      if D[I].Grp <> 0 then Grp := D[I].Grp;
    end;

  WriteLn(Format('%d faces, group %d, closed=%s',
    [NFace, Grp, BoolToStr(D.GroupClosed(Grp), True)]));
  if not D.GroupClosed(Grp) then
  begin
    WriteLn('it did not come out closed - that is a model nobody can print');
    Halt(1);
  end;

  { --- and out -------------------------------------------------------- }
  { The camera, worked out the way Fit does it; a zero pan would leave the
    drawing off to one side. }
  BaseP := PixelsPerUnit(usImperial, ScaleTable(usImperial, 4), 96);
  D.Bounds(BLo, BHi);
  CamMid := P3((BLo.X + BHi.X) / 2, (BLo.Y + BHi.Y) / 2, (BLo.Z + BHi.Z) / 2);
  Diag := Sqrt(Sqr(BHi.X - BLo.X) + Sqr(BHi.Y - BLo.Y) + Sqr(BHi.Z - BLo.Z));
  { a little more room than the toy gets, since a tall thin thing fills
    the height }
  CamZoom := Min((ART_W * 0.72) / (Diag * BaseP), (ART_H * 0.72) / (Diag * BaseP));
  CamV.Kind := vkOrbit;
  CamV.Az := -0.785398;
  CamV.El := 0.450000;    { lower than the toy, but high enough to show the
                            foot and rim are round }
  CamV.Ppu := BaseP * CamZoom;
  CamV.OX := 0;
  CamV.OY := 0;
  CamP := Project(CamV, CamMid);
  { scale 4 is 1" = 1'-0", the biggest there is; snap 1 is a sixteenth.
    The notes are for whoever opens the copy the program writes out. }
  ExampleText(D, 'Wine Glass', 4, 1, CamV.Az, CamV.El, CamZoom,
    ART_W / 2 - CamP.X, ART_H / 2 - CamP.Y,
    ['Written out beside Heckers Sketch, and put back whenever it is missing',
     'or untouched.  Draw on it all you like - once you save over it, it is',
     'yours and the program leaves it alone.'], L);
  L.SaveToFile('wine-glass.hsk');

  { and the same thing as a unit, so the program carries it }
  U := TStringList.Create;
  U.Add('unit hsExGlass;');
  U.Add('');
  U.Add('{ The wine glass example.');
  U.Add('');
  U.Add('  Generated by examples/make-glass.pas - do not edit this by hand,');
  U.Add('  edit that and run it again.  It is the same drawing as');
  U.Add('  examples/wine-glass.hsk, carried inside the program so that a');
  U.Add('  portable build is one file and the examples folder can be written');
  U.Add('  out beside it on a machine that has never seen one. }');
  U.Add('');
  U.Add('{$mode objfpc}{$H+}');
  U.Add('');
  U.Add('interface');
  U.Add('');
  U.Add('uses');
  U.Add('  Classes;');
  U.Add('');
  U.Add('{ The wine glass, as the lines of a .hsk file. }');
  U.Add('procedure GlassDrawing(L: TStrings);');
  U.Add('');
  U.Add('implementation');
  Lines2Unit(L, U, 'procedure GlassDrawing(L: TStrings);');
  U.SaveToFile('../src/examples/hsExGlass.pas');
  U.Free;

  WriteLn(Format('%d things -> wine-glass.hsk and hsExGlass.pas (%d lines)',
    [D.Live, L.Count]));
end.

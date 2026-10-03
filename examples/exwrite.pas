unit exwrite;

{ Shared by the make-*.pas generators: writes a drawing as a .hsk file with the
  program's own writer, and the same lines as a unit that carries it inside the
  program.  tests/run.sh checks the two match.
      fpc -Mobjfpc -Sh -Fu"../src/*" -Fu"../src/vendor/*" -Fi.. make-....pas

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, hsDrawing, hsHeckFile;

{ D as a one-sheet Heck file into L, in feet and inches, in the 3D view with the
  camera at Az, El, Zoom and panned by PanX, PanY.  ScaleIdx and SnapIdx index
  ScaleTable and the snap list.  The camera is rounded so an unchanged model
  regenerates to the same bytes.  Notes go first as '//' comment lines. }
procedure ExampleText(D: TWorkDoc; const Name: string; ScaleIdx, SnapIdx: Integer;
  Az, El, Zoom, PanX, PanY: Double; const Notes: array of string; L: TStrings);

{ Adds to U (already holding the unit up to "implementation") a procedure Decl
  that adds L's lines one by one.  The compiler rejects one huge procedure
  ("procedure too complex"), so a big drawing is split into procedures of
  PART_LINES each. }
procedure Lines2Unit(L, U: TStrings; const Decl: string);

{ A carried example's first sheet into D, for a model built from another one.
  False when it will not read. }
function ReadExample(L: TStrings; D: TWorkDoc): Boolean;

const
  PART_LINES = 4000;

implementation

{ Every length and angle in D rounded to a millionth of a foot or radian.
  Heck writes numbers as they are, so without this the sines and cosines give
  unreadable files and every regeneration is a diff of noise. }
procedure RoundDoc(D: TWorkDoc);
var
  A: TWorkEntArray;
  I, K, H: Integer;

  function R6(V: Double): Double;
  begin
    Result := RoundTo(V, -6);
  end;

  procedure P6(var P: TP3);
  begin
    P.X := R6(P.X); P.Y := R6(P.Y); P.Z := R6(P.Z);
  end;

begin
  A := D.Snapshot;
  for I := 0 to High(A) do
  begin
    P6(A[I].A); P6(A[I].B); P6(A[I].C);
    A[I].R := R6(A[I].R);
    A[I].A0 := R6(A[I].A0);
    A[I].Sweep := R6(A[I].Sweep);
    for K := 0 to High(A[I].Poly) do P6(A[I].Poly[K]);
    for H := 0 to High(A[I].Holes) do
      for K := 0 to High(A[I].Holes[H]) do P6(A[I].Holes[H][K]);
  end;
  D.RestoreSnap(A);
end;

procedure ExampleText(D: TWorkDoc; const Name: string; ScaleIdx, SnapIdx: Integer;
  Az, El, Zoom, PanX, PanY: Double; const Notes: array of string; L: TStrings);
var
  S: array of THeckSheet;
  I: Integer;
begin
  RoundDoc(D);
  SetLength(S, 1);
  S[0] := NewHeckSheet(Name);
  { the sheet's own new drawing is not the one being written }
  S[0].Doc.Free;
  S[0].Doc := D;
  S[0].Units := usImperial;
  S[0].ScaleIdx := ScaleIdx;
  S[0].SnapIdx := SnapIdx;
  S[0].View := vkOrbit;
  S[0].CamKnown := True;
  S[0].Az := RoundTo(Az, -6);
  S[0].El := RoundTo(El, -6);
  S[0].Zoom := RoundTo(Zoom, -6);
  S[0].ViewX := RoundTo(PanX, -3);
  S[0].ViewY := RoundTo(PanY, -3);
  L.Clear;
  for I := 0 to High(Notes) do L.Add('// ' + Notes[I]);
  WriteHeckFile(S, L, False, False);
end;

procedure Lines2Unit(L, U: TStrings; const Decl: string);
var
  P, NParts: Integer;

  procedure Adds(From, Upto: Integer);
  var
    K: Integer;
  begin
    for K := From to Upto do
      U.Add('  L.Add(''' + StringReplace(L[K], '''', '''''', [rfReplaceAll]) + ''');');
  end;

begin
  U.Add('');
  NParts := (L.Count + PART_LINES - 1) div PART_LINES;
  if NParts > 1 then
    for P := 0 to NParts - 1 do
    begin
      U.Add(Format('procedure Part%d(L: TStrings);', [P + 1]));
      U.Add('begin');
      Adds(P * PART_LINES, Min(L.Count, (P + 1) * PART_LINES) - 1);
      U.Add('end;');
      U.Add('');
    end;
  U.Add(Decl);
  U.Add('begin');
  if NParts > 1 then
    for P := 0 to NParts - 1 do U.Add(Format('  Part%d(L);', [P + 1]))
  else
    Adds(0, L.Count - 1);
  U.Add('end;');
  U.Add('');
  U.Add('end.');
end;

function ReadExample(L: TStrings; D: TWorkDoc): Boolean;
var
  Sheets: THeckSheets;
  I, ErrLine: Integer;
  Err: string;
begin
  Sheets := nil;
  Result := ReadDrawingFile(L, Sheets, ErrLine, Err) and (Length(Sheets) > 0);
  if Result then D.RestoreSnap(Sheets[0].Doc.Snapshot)
  else WriteLn('the example will not read: ', Err);
  for I := 0 to High(Sheets) do Sheets[I].Doc.Free;
end;

end.

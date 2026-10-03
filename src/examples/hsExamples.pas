unit hsExamples;

{ The example drawings built into the program, and their file names.
  examples/make-*.pas generates each .hsk and a matching hsEx unit; this list
  is the only hand-written part.  They are built in so a first run has them
  without a separate folder.  The first one is what a fresh run opens.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}

interface

uses
  Classes;

{ How many there are, and what each is called on disk. }
function ExampleCount: Integer;
function ExampleFile(I: Integer): string;
{ A short line about it, for anything that lists them. }
function ExampleAbout(I: Integer): string;
{ The drawing itself, as the lines of a .hsk file. }
procedure ExampleLines(I: Integer; L: TStrings);

{ Write one example into Dir unless the user has changed it.  Recorded is
  the checksum of what we wrote last time and comes back as the current one.
  Missing or unchanged since we wrote it: write the new version.  Anything
  else is the user's and is left alone.  No record at all counts as ours:
  that file predates the checksum. }
type
  TExampleWrite = (ewWritten, ewUpToDate, ewKeptTheirs, ewFailed);

function PutExample(I: Integer; const Dir: string;
  var Recorded: string): TExampleWrite;

{ The same rule for any built-in file the program writes out, such as the jigs. }
function PutCarried(const Path: string; L: TStrings;
  var Recorded: string): TExampleWrite;

implementation

uses
  SysUtils, hsExToy, hsExGlass, hsExBroom, hsExRobot, hsExBall, hsExJigs,
  hsExMannequin, hsUpdater;

const
  FILES: array[0..6] of string = ('etch-a-sketch.hsk', 'wine-glass.hsk',
    'broom.hsk', 'robot.hsk', 'ball.hsk', 'jigs.hsk', 'mannequin.hsk');
  ABOUT: array[0..6] of string = (
    'A toy etch-a-sketch, to scale, with a robot on the screen.  Every ' +
    'face of it is something to push.',
    'A wine glass, off the lathe: an outline spun about the blue axis.  ' +
    'Hollow bowl, solid stem, and closed enough to print.',
    'A kitchen broom, banded the way a shop one is: a hundred and seventy ' +
    'bristles, every face painted, and not a pen color anywhere.',
    'A robot six foot two, with the etch-a-sketch set in his chest at the ' +
    'height your hands are - and the toy is the toy, not a copy of it.',
    'A soccer ball: twelve pentagons and twenty hexagons, cut off the corners ' +
    'of an icosahedron the way the real one is.',
    'Four groups, each made by a jig - a little program of your own, in any ' +
    'language, that prints the drawing''s text.  Right-click one and run it again.',
    'A mannequin, six foot and a hundred and fifty pounds, made by the body ' +
    'jig from those two numbers - to be dressed.  Right-click her, change the ' +
    'numbers, run the jig again: another body.');

function ExampleCount: Integer;
begin
  Result := Length(FILES);
end;

function ExampleFile(I: Integer): string;
begin
  if (I < 0) or (I > High(FILES)) then Result := '' else Result := FILES[I];
end;

function ExampleAbout(I: Integer): string;
begin
  if (I < 0) or (I > High(ABOUT)) then Result := '' else Result := ABOUT[I];
end;

procedure ExampleLines(I: Integer; L: TStrings);
begin
  case I of
    0: ExampleDrawing(L);
    1: GlassDrawing(L);
    2: BroomDrawing(L);
    3: RobotDrawing(L);
    4: BallDrawing(L);
    5: JigsDrawing(L);
    6: MannequinDrawing(L);
  end;
end;

function ReadRaw(const Path: string): string;
var
  F: TFileStream;
begin
  Result := '';
  F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

function PutCarried(const Path: string; L: TStrings;
  var Recorded: string): TExampleWrite;
var
  Sum: string;
begin
  Result := ewFailed;
  try
    if L.Count = 0 then Exit;
    if FileExists(Path) then
    begin
      if ReadRaw(Path) = L.Text then
      begin
        Recorded := Sha256Of(Path);
        Exit(ewUpToDate);
      end;
      Sum := Sha256Of(Path);
      if (Recorded <> '') and (Sum <> Recorded) then
        Exit(ewKeptTheirs);
    end;
    L.SaveToFile(Path);
    Recorded := Sha256Of(Path);
    Result := ewWritten;
  except
    Result := ewFailed;
  end;
end;

function PutExample(I: Integer; const Dir: string;
  var Recorded: string): TExampleWrite;
var
  L: TStringList;
begin
  Result := ewFailed;
  if (I < 0) or (I >= ExampleCount) then Exit;
  L := TStringList.Create;
  try
    try
      ExampleLines(I, L);
      Result := PutCarried(IncludeTrailingPathDelimiter(Dir) + ExampleFile(I), L, Recorded);
    except
      Result := ewFailed;
    end;
  finally
    L.Free;
  end;
end;

end.

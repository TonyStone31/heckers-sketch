unit hsHeckSample;

{ A small Heck drawing and the sample jigs that go with it, for trying the
  source window.  A jig already in the jigs folder is left alone, since the
  person may have changed it. }

{$mode objfpc}{$H+}

interface

function SampleHeck: string;
procedure WriteSampleJigs(const Dir: string);

implementation

uses
  Classes, SysUtils, hsJigFiles;

const
  NL = LineEnding;

function SampleHeck: string;
begin
  Result :=
    'HeckersSketch 2' + NL +
    'units = ft in' + NL +
    NL +
    'sheet ''Sample''' + NL +
    '  // A four foot cube: eight corners, and the twelve lines between them.' + NL +
    '  // The faces are not typed - the program works them out.' + NL +
    '  points' + NL +
    '    a = 0 east, 0 north, 0 up' + NL +
    '    b = a + 4'' east' + NL +
    '    c = b + 4'' north' + NL +
    '    d = a + 4'' north' + NL +
    '    e = a + 4'' up' + NL +
    '    f = b + 4'' up' + NL +
    '    g = c + 4'' up' + NL +
    '    h = d + 4'' up' + NL +
    '  end' + NL +
    '  line = a to b' + NL +
    '  line = b to c' + NL +
    '  line = c to d' + NL +
    '  line = d to a' + NL +
    '  line = e to f' + NL +
    '  line = f to g' + NL +
    '  line = g to h' + NL +
    '  line = h to e' + NL +
    '  line = a to e' + NL +
    '  line = b to f' + NL +
    '  line = c to g' + NL +
    '  line = d to h' + NL +
    NL +
    '  // A circle on its top.  Try changing the radius and pressing Apply.' + NL +
    '  circle' + NL +
    '    center = 2'' east, 2'' north, 4'' up' + NL +
    '    radius = 1''' + NL +
    '    facing = up' + NL +
    '  end' + NL +
    NL +
    '  // A few loose lines, the second written as steps from where it starts.' + NL +
    '  line = 6'' east, 0 north, 0 up to 6'' east, 3'' north, 0 up' + NL +
    '  line = 6'' east, 3'' north, 0 up to + 2'' east + 1'' 6" up' + NL +
    '  line Red' + NL +
    '    points = 6'' east, 0 north, 0 up to 8'' east, 3'' north, 1'' 6" up' + NL +
    '    ink    = red' + NL +
    '    width  = 2' + NL +
    '  end' + NL +
    NL +
    '  // Four jigs.  Each group is filled by a little program of yours, in' + NL +
    '  // your jigs folder.  Press "Run jigs", then change a number and run again.' + NL +
    '  // Ctrl+click a jig line to open its program.' + NL +
    '  group ''Star''' + NL +
    '    jig = ''star'' with Points = 5, Radius = 2'', East = 12'', North = 2''' + NL +
    '  end' + NL +
    '  group ''Balloon''' + NL +
    '    jig = ''balloon'' with Radius = 1'' 6", East = 12'', North = 7'', Height = 6''' + NL +
    '  end' + NL +
    '  group ''Fence''' + NL +
    '    jig = ''fence'' with Posts = 6, Spacing = 2'', Height = 3'', North = 11''' + NL +
    '  end' + NL +
    '  group ''Steps''' + NL +
    '    jig = ''steps'' with Steps = 5, Rise = 7 1/2", Run = 10", Width = 3'', East = 6'', North = 5''' + NL +
    '  end' + NL +
    'end' + NL;
end;

procedure WriteOne(const FileName, Text: string);
var
  L: TStringList;
begin
  if FileExists(FileName) then Exit;
  L := TStringList.Create;
  try
    L.Text := Text;
    try
      L.SaveToFile(FileName);
    except
      { a folder that cannot be written to is not worth stopping for }
    end;
  finally
    L.Free;
  end;
end;

procedure WriteSampleJigs(const Dir: string);
var
  I: Integer;
  L: TStringList;
begin
  { The jigs are written at startup too; this covers a folder emptied since. }
  L := TStringList.Create;
  try
    for I := 0 to JigFileCount - 1 do
    begin
      L.Clear;
      JigFileLines(I, L);
      WriteOne(Dir + JigFileName(I), L.Text);
    end;
  finally
    L.Free;
  end;
end;

end.

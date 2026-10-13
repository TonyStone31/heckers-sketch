unit hsPdf;

{ PDF output uses FPC's fcl-pdf: Pascal code linked into the executable,
  with vector geometry. No PDF runtime or external converter.
  Copyright (c) 2026 Tony Stone - MIT, see LICENSE. }
{$mode objfpc}{$H+}

interface

uses Classes, Types, Graphics, fpPDF, fpTTF, hsDrawing;

type
  TPdfSheet = record
    Name: string;
    W, H: double; { millimeters, portrait }
  end;

const
  PDF_MARGIN = 10.0;
  PDF_FOOTER = 15.0;
  PDF_SHEETS: array[0..20] of TPdfSheet = (
    (Name: 'ISO A4 - 210 x 297 mm'; W: 210; H: 297),
    (Name: 'ISO A3 - 297 x 420 mm'; W: 297; H: 420),
    (Name: 'ISO A2 - 420 x 594 mm'; W: 420; H: 594),
    (Name: 'ISO A1 - 594 x 841 mm'; W: 594; H: 841),
    (Name: 'ISO A0 - 841 x 1189 mm'; W: 841; H: 1189),
    (Name: 'ANSI A / Letter - 8.5 x 11 in'; W: 215.9; H: 279.4),
    (Name: 'ANSI B / Tabloid - 11 x 17 in'; W: 279.4; H: 431.8),
    (Name: 'ANSI C - 17 x 22 in'; W: 431.8; H: 558.8),
    (Name: 'ANSI D - 22 x 34 in'; W: 558.8; H: 863.6),
    (Name: 'ANSI E - 34 x 44 in'; W: 863.6; H: 1117.6),
    (Name: 'ARCH A - 9 x 12 in'; W: 228.6; H: 304.8),
    (Name: 'ARCH B - 12 x 18 in'; W: 304.8; H: 457.2),
    (Name: 'ARCH C - 18 x 24 in'; W: 457.2; H: 609.6),
    (Name: 'ARCH D - 24 x 36 in'; W: 609.6; H: 914.4),
    (Name: 'ARCH E - 36 x 48 in'; W: 914.4; H: 1219.2),
    (Name: 'ARCH E1 - 30 x 42 in'; W: 762; H: 1066.8),
    (Name: 'ARCH E2 - 26 x 38 in'; W: 660.4; H: 965.2),
    (Name: 'ARCH E3 - 27 x 39 in'; W: 685.8; H: 990.6),
    (Name: 'Legal - 8.5 x 14 in'; W: 215.9; H: 355.6),
    (Name: 'ISO A5 - 148 x 210 mm'; W: 148; H: 210),
    (Name: 'Engineering F - 28 x 40 in'; W: 711.2; H: 1016));

type
  { A multi-page document for things that are not one drawing on one sheet,
    such as the radiant submittal.  Positions are mm from the top left of the
    page, text sizes in points; fonts are the same embedded system sans the
    drawing export uses. }
  TPdfBook = class
  private
    FPDF: TPDFDocument;
    FPage: TPDFPage;
    { Keep every page in one section: fpPDF cannot write the pages of a
      second section unless outlines are on. }
    FSection: TPDFSection;
    FPages: TList;
    FW, FH: double;
    FFont, FBold: integer;
    FMetrics, FBoldMetrics: TFPFontCacheItem;
    function Y(Y0: double): double;
  public
    constructor Create(const Title: string; PageW, PageH: double);
    destructor Destroy; override;
    { Adds a page and makes it current; returns its number, from 1. }
    function NewPage: integer;
    { Go back to page N (from 1), e.g. to write footers once the count is known. }
    procedure OnPage(N: integer);
    function PageCount: integer;
    { S with its baseline at Y }
    procedure Text(X, Y0: double; const S: string; SizePt: double; Ink: TColor = clBlack; Bold: boolean = False);
    function TextWidth(const S: string; SizePt: double; Bold: boolean = False): double;
    procedure Line(X1, Y1, X2, Y2: double; Ink: TColor; WidthMM: double);
    procedure Poly(const Pts: array of TPointF; Closed: boolean; Ink: TColor; WidthMM: double; Fill: TColor = clNone);
    procedure SaveToFile(const Path: string);
    property Width: double read FW;
    property Height: double read FH;
  end;

procedure PdfSheetSize(Index: integer; Landscape: boolean; out W, H: double);
{ A print scale as the trade says it: 1/4" = 1'-0" for an imperial drawing
  when the scale is one, 1:100 otherwise. }
function PdfScaleWords(Denominator: double; U: TUnitSystem): string;
{ The camera supplies the center and direction, not the printed scale. }
procedure SaveDrawingPDF(Doc: TWorkDoc; const V: TProjector; SrcW, SrcH: integer; U: TUnitSystem; EdgeW: single; const Path: string;
  PageW, PageH, Denominator: double; Axes: boolean);

implementation

uses SysUtils, Math, hsSvg;

{ fcl-pdf in FPC 3.2 keeps the paper in whole points, which puts A4 a tenth
  of a millimeter out.  There the page entry is written here instead. }
  {$if not declared(TPDFFloatObject)}
  {$define WHOLE_POINT_PAPER}
  {$endif}

type
  { A document whose pages are all one size, in mm. }
  TSizedPDF = class(TPDFDocument)
    {$ifdef WHOLE_POINT_PAPER}
  protected
    function CreatePageEntry(Parent, PageNum: integer): integer; override;
  {$endif}
  public
    PageW, PageH: double;
    constructor Create(W, H: double); reintroduce;
    function AddSizedPage: TPDFPage;
  end;

constructor TSizedPDF.Create(W, H: double);
begin
  inherited Create(nil);
  PageW := W;
  PageH := H;
end;

function TSizedPDF.AddSizedPage: TPDFPage;
var
  Paper: TPDFPaper;
begin
  Result := Pages.AddPage;
  Paper := Default(TPDFPaper);
  {$ifdef WHOLE_POINT_PAPER}
  Paper.W := Round(PageW * 72 / 25.4);
  Paper.H := Round(PageH * 72 / 25.4);
  {$else}
  Paper.W := PageW * 72 / 25.4;
  Paper.H := PageH * 72 / 25.4;
  {$endif}
  Result.Paper := Paper;
end;

{$ifdef WHOLE_POINT_PAPER}
type
  TOpenDict = class(TPDFDictionary);
  TOpenArray = class(TPDFArray);

{ The library's own, but for the MediaBox. }
function TSizedPDF.CreatePageEntry(Parent, PageNum: integer): integer;
var
  Entry, Above, Resources: TPDFDictionary;
  Box, ProcSet: TPDFArray;
  Count: TPDFInteger;
  W, H: string;
begin
  Entry := CreateGlobalXRef.Dict;
  Result := GlobalXRefCount - 1;
  TOpenDict(Entry).AddName('Type', 'Page');
  TOpenDict(Entry).AddReference('Parent', Parent);
  Above := GlobalXRefs[Parent].Dict;
  Count := Above.ValueByName('Count') as TPDFInteger;
  Count.Value := Count.Value + 1;
  TOpenArray(Above.ValueByName('Kids')).AddItem(CreateReference(Result));
  Str(PageW * 72 / 25.4: 0: 4, W);
  Str(PageH * 72 / 25.4: 0: 4, H);
  Box := CreateArray;
  TOpenArray(Box).AddFreeFormArrayValues('0 0 ' + W + ' ' + H);
  TOpenDict(Entry).AddElement('MediaBox', Box);
  CreateAnnotEntries(PageNum, Entry);
  Resources := CreateDictionary;
  TOpenDict(Entry).AddElement('Resources', Resources);
  ProcSet := CreateArray;
  TOpenDict(Resources).AddElement('ProcSet', ProcSet);
  TOpenArray(ProcSet).AddItem(CreateName('PDF'));
  TOpenArray(ProcSet).AddItem(CreateName('Text'));
  TOpenArray(ProcSet).AddItem(CreateName('ImageC'));
  if Fonts.Count > 0 then TOpenDict(Resources).AddElement('Font', CreateDictionary);
  if Pages[PageNum].HasImages then TOpenDict(Resources).AddElement('XObject', CreateDictionary);
end;

{$endif}

{ The system sans font file the export embeds, or '' when there is none. }
function SansFontFile(Bold: boolean): string;
begin
  {$ifdef windows}
  if Bold then Result := 'arialbd.ttf' else Result := 'arial.ttf';
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('WINDIR')) + 'Fonts\' + Result;
  if FileExists(Result) then Exit;
  {$else}
  {$ifdef darwin}
  if Bold then Result := '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
  else
    Result := '/System/Library/Fonts/Supplemental/Arial.ttf';
  if FileExists(Result) then Exit;
  {$endif}
  if Bold then Result := '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
  else
    Result := '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
  if FileExists(Result) then Exit;
  if Bold then Result := '/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf'
  else
    Result := '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf';
  if FileExists(Result) then Exit;
  {$endif}
  Result := '';
end;

type
  TPDFVectorWriter = class(TVectorWriter)
  private
    FPage: TPDFPage;
    FTop: double;
    FFont: integer;
    FFontMetrics: TFPFontCacheItem;
    function Coord(const P: TPointF): TPDFCoord;
  public
    constructor Create(PDF: TPDFDocument; Page: TPDFPage; Top: double);
    destructor Destroy; override;
    procedure Path(const Loops: TVectorLoops; Ink: TColor; Width: double; Filled: boolean); override;
    procedure Text(const P: TPointF; const S: string; Ink: TColor; Size: double; Centered: boolean); override;
  end;

function PDFColor(C: TColor): longword;
begin
  C := ColorToRGB(C);
  Result := (longword(byte(C)) shl 16) or (longword(byte(C shr 8)) shl 8) or byte(C shr 16);
end;

constructor TPDFVectorWriter.Create(PDF: TPDFDocument; Page: TPDFPage; Top: double);
var
  FontPath: string;
begin
  inherited Create;
  FPage := Page;
  FTop := Top;
  { Read a system font directly: no fontconfig library, shell or converter.
    Embed its subset so the recipient needs neither the font nor the app. }
  {$ifdef windows}
  FontPath := IncludeTrailingPathDelimiter(GetEnvironmentVariable('WINDIR')) + 'Fonts\arial.ttf';
  {$else}
  FontPath := '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
  if not FileExists(FontPath) then
    FontPath := '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf';
  {$endif}
  if FileExists(FontPath) then
  begin
    FFontMetrics := TFPFontCacheItem.Create(FontPath);
    FFont := PDF.AddFont(FontPath, 'ExportSans');
  end
  else
    { A PDF standard font needs no installed file. Courier has exact,
      fixed metrics for centered labels even on a minimal installation. }
    FFont := PDF.AddFont('Courier');
end;

destructor TPDFVectorWriter.Destroy;
begin
  FFontMetrics.Free;
  inherited Destroy;
end;

function TPDFVectorWriter.Coord(const P: TPointF): TPDFCoord;
begin
  { Geometry uses a fixed 96-unit paper inch; PDF coordinates are mm,
    bottom-up. Fonts and pen widths stay independent of screen zoom. }
  Result.X := PDF_MARGIN + P.X * 25.4 / 96;
  Result.Y := FTop - P.Y * 25.4 / 96;
end;

procedure TPDFVectorWriter.Path(const Loops: TVectorLoops; Ink: TColor; Width: double; Filled: boolean);
var
  I, J: integer;
  A, B: TPDFCoord;
begin
  FPage.SetColor(PDFColor(Ink), True);
  if Filled then FPage.SetColor($D8D8D8, False);
  for I := 0 to High(Loops) do
  begin
    if Length(Loops[I]) < 2 then Continue;
    A := Coord(Loops[I][0]);
    FPage.MoveTo(A);
    for J := 1 to High(Loops[I]) do
    begin
      B := Coord(Loops[I][J]);
      { fpPDF takes line widths in points even when positions use mm. }
      FPage.DrawLine(A, B, Width * 72 / 96, False);
      A := B;
    end;
    if Filled then FPage.ClosePath;
  end;
  if Filled then FPage.FillEvenOddStrokePath
  else
    FPage.StrokePath;
end;

procedure TPDFVectorWriter.Text(const P: TPointF; const S: string; Ink: TColor; Size: double; Centered: boolean);
var
  A: TPDFCoord;
  TextW: double;
begin
  A := Coord(P);
  FPage.SetColor(PDFColor(Ink), False);
  FPage.SetFont(FFont, Size * 72 / 96);
  if Centered then
  begin
    if Assigned(FFontMetrics) then
      TextW := FFontMetrics.TextWidth(S, 0) / FFontMetrics.FontData.Head.UnitsPerEm * Size * 25.4 / 96
    else
      TextW := Length(UTF8Decode(S)) * Size * 0.6 * 25.4 / 96;
    A.X := A.X - TextW / 2;
  end;
  FPage.WriteText(A, S);
end;

function PdfScaleWords(Denominator: double; U: TUnitSystem): string;
var
  Inch, Num: double;
  Den: integer;
begin
  Result := Format('1:%g', [Denominator]);
  if (U <> usImperial) or (Denominator <= 0) then Exit;
  { inches of paper to the foot }
  Inch := 12 / Denominator;
  Den := 1;
  while Den <= 128 do
  begin
    Num := Inch * Den;
    if Abs(Num - Round(Num)) < 1E-9 then
    begin
      if Den = 1 then Result := Format('%d" = 1''-0"', [Round(Num)])
      else
        Result := Format('%d/%d" = 1''-0"', [Round(Num), Den]);
      Exit;
    end;
    Den := Den * 2;
  end;
end;

procedure PdfSheetSize(Index: integer; Landscape: boolean; out W, H: double);
begin
  if (Index < Low(PDF_SHEETS)) or (Index > High(PDF_SHEETS)) then
    raise Exception.Create('Choose a PDF paper size');
  if Landscape then
  begin
    W := PDF_SHEETS[Index].H;
    H := PDF_SHEETS[Index].W;
  end
  else
  begin
    W := PDF_SHEETS[Index].W;
    H := PDF_SHEETS[Index].H;
  end;
end;

procedure SaveDrawingPDF(Doc: TWorkDoc; const V: TProjector; SrcW, SrcH: integer; U: TUnitSystem; EdgeW: single; const Path: string;
  PageW, PageH, Denominator: double; Axes: boolean);
var
  PDF: TSizedPDF;
  Page: TPDFPage;
  Writer: TPDFVectorWriter;
  PV: TProjector;
  W, H, MMUnit, Bar, BarMM, Extent: double;
  Loops: TVectorLoops;
  I: integer;
  A, B: TP3;
  AxisInk: TColor;
begin
  if Doc = nil then raise Exception.Create('No drawing for the PDF');
  if (Denominator <= 0) or IsNan(Denominator) or IsInfinite(Denominator) or (V.Ppu <= 0) then raise Exception.Create('Invalid PDF drawing scale');
  if (PageW <= 2 * PDF_MARGIN) or (PageH <= 2 * PDF_MARGIN + PDF_FOOTER) then
    raise Exception.Create('The PDF paper is too small');
  W := (PageW - 2 * PDF_MARGIN) * 96 / 25.4;
  H := (PageH - 2 * PDF_MARGIN - PDF_FOOTER) * 96 / 25.4;
  if U = usImperial then MMUnit := 304.8
  else
    MMUnit := 1000;
  PV := V;
  PV.Ppu := MMUnit / Denominator * 96 / 25.4;
  PV.OX := W / 2 + (V.OX - SrcW / 2) * PV.Ppu / V.Ppu;
  PV.OY := H / 2 + (V.OY - SrcH / 2) * PV.Ppu / V.Ppu;
  PDF := TSizedPDF.Create(PageW, PageH);
  try
    PDF.Options := [poSubsetFont, poCompressFonts];
    PDF.Infos.Title := ChangeFileExt(ExtractFileName(Path), '');
    PDF.Infos.Producer := 'Heckers Sketch';
    PDF.Infos.CreationDate := Now;
    PDF.DefaultUnitOfMeasure := uomMillimeters;
    PDF.StartDocument;
    Page := PDF.AddSizedPage;
    PDF.Sections.AddSection.AddPage(Page);
    Writer := TPDFVectorWriter.Create(PDF, Page, PageH - PDF_MARGIN);
    try
      { The model is clipped; it is never rescaled to fit. Restore the
        graphics state before the footer so it cannot be clipped away. }
      Page.PushGraphicsStack;
      Page.MoveTo(PDF_MARGIN, PDF_MARGIN + PDF_FOOTER);
      Page.DrawLine(PDF_MARGIN, PDF_MARGIN + PDF_FOOTER,
        PageW - PDF_MARGIN, PDF_MARGIN + PDF_FOOTER, 0, False);
      Page.DrawLine(PageW - PDF_MARGIN, PDF_MARGIN + PDF_FOOTER,
        PageW - PDF_MARGIN, PageH - PDF_MARGIN, 0, False);
      Page.DrawLine(PageW - PDF_MARGIN, PageH - PDF_MARGIN,
        PDF_MARGIN, PageH - PDF_MARGIN, 0, False);
      Page.ClosePath;
      Page.ClipPath;
      if Axes then
      begin
        SetLength(Loops, 1);
        SetLength(Loops[0], 2);
        Extent := (Abs(PV.OX) + Abs(PV.OY) + W + H) / PV.Ppu * 100;
        for I := 0 to 2 do
        begin
          A := P3(0, 0, 0);
          B := A;
          case I of
            0: begin
              A.X := -Extent;
              B.X := Extent;
              AxisInk := $8888CC;
            end;
            1: begin
              A.Y := -Extent;
              B.Y := Extent;
              AxisInk := $88BB88;
            end;
            else
            begin
              A.Z := -Extent;
              B.Z := Extent;
              AxisInk := $CC8888;
            end;
          end;
          Loops[0][0] := Project(PV, A);
          Loops[0][1] := Project(PV, B);
          Writer.Path(Loops, AxisInk, 0.5, False);
        end;
      end;
      Doc.WriteVectors(Writer, PV, U, EdgeW);
      Page.PopGraphicsStack;
      Bar := NiceBarLength(MMUnit / Denominator, 25, 60, U);
      BarMM := Bar * MMUnit / Denominator;
      Page.SetColor(0, True);
      Page.SetColor(0, False);
      Page.DrawLine(PDF_MARGIN, 12, PDF_MARGIN + BarMM, 12, 0.7);
      Page.DrawLine(PDF_MARGIN, 10, PDF_MARGIN, 14, 0.7);
      Page.DrawLine(PDF_MARGIN + BarMM, 10, PDF_MARGIN + BarMM, 14, 0.7);
      Page.SetFont(Writer.FFont, 9);
      Page.WriteText(PDF_MARGIN, 16, FormatLen(Bar, U));
      Page.WriteText(PDF_MARGIN, 5, PdfScaleWords(Denominator, U) + ' (view plane) - print at 100% / Actual size');
      PDF.SaveToFile(Path);
    finally
      Writer.Free;
    end;
  finally
    PDF.Free;
  end;
end;

{ ---- TPdfBook ---- }

constructor TPdfBook.Create(const Title: string; PageW, PageH: double);
var
  F: string;
begin
  inherited Create;
  FW := PageW;
  FH := PageH;
  FPages := TList.Create;
  FPDF := TSizedPDF.Create(PageW, PageH);
  FPDF.Options := [poSubsetFont, poCompressFonts];
  FPDF.Infos.Title := Title;
  FPDF.Infos.Producer := 'Heckers Sketch';
  FPDF.Infos.CreationDate := Now;
  FPDF.DefaultUnitOfMeasure := uomMillimeters;
  FPDF.StartDocument;
  FSection := FPDF.Sections.AddSection;
  F := SansFontFile(False);
  if F <> '' then
  begin
    FMetrics := TFPFontCacheItem.Create(F);
    FFont := FPDF.AddFont(F, 'BookSans');
  end
  else
    FFont := FPDF.AddFont('Helvetica');
  F := SansFontFile(True);
  if (F <> '') and (FMetrics <> nil) then
  begin
    FBoldMetrics := TFPFontCacheItem.Create(F);
    FBold := FPDF.AddFont(F, 'BookSansBold');
  end
  else if FMetrics = nil then FBold := FPDF.AddFont('Helvetica-Bold')
  else
    FBold := FFont;
end;

destructor TPdfBook.Destroy;
begin
  FMetrics.Free;
  FBoldMetrics.Free;
  FPages.Free;
  FPDF.Free;
  inherited Destroy;
end;

function TPdfBook.Y(Y0: double): double;
begin
  Result := FH - Y0;
end;

function TPdfBook.NewPage: integer;
begin
  FPage := TSizedPDF(FPDF).AddSizedPage;
  FSection.AddPage(FPage);
  FPages.Add(FPage);
  Result := FPages.Count;
end;

procedure TPdfBook.OnPage(N: integer);
begin
  if (N >= 1) and (N <= FPages.Count) then FPage := TPDFPage(FPages[N - 1]);
end;

function TPdfBook.PageCount: integer;
begin
  Result := FPages.Count;
end;

procedure TPdfBook.Text(X, Y0: double; const S: string; SizePt: double; Ink: TColor; Bold: boolean);
begin
  if (FPage = nil) or (S = '') then Exit;
  FPage.SetColor(PDFColor(Ink), False);
  if Bold then FPage.SetFont(FBold, SizePt)
  else
    FPage.SetFont(FFont, SizePt);
  FPage.WriteText(X, Y(Y0), S);
end;

function TPdfBook.TextWidth(const S: string; SizePt: double; Bold: boolean): double;
var
  M: TFPFontCacheItem;
begin
  if Bold and (FBoldMetrics <> nil) then M := FBoldMetrics
  else
    M := FMetrics;
  if M <> nil then Result := M.TextWidth(S, 0) / M.FontData.Head.UnitsPerEm * SizePt * 25.4 / 72
  else
    Result := Length(UTF8Decode(S)) * SizePt * 0.55 * 25.4 / 72;
end;

procedure TPdfBook.Line(X1, Y1, X2, Y2: double; Ink: TColor; WidthMM: double);
begin
  if FPage = nil then Exit;
  FPage.SetColor(PDFColor(Ink), True);
  FPage.DrawLine(X1, Y(Y1), X2, Y(Y2), WidthMM * 72 / 25.4, True);
end;

procedure TPdfBook.Poly(const Pts: array of TPointF; Closed: boolean; Ink: TColor; WidthMM: double; Fill: TColor);
var
  I: integer;
begin
  if (FPage = nil) or (Length(Pts) < 2) then Exit;
  FPage.SetColor(PDFColor(Ink), True);
  if Fill <> clNone then FPage.SetColor(PDFColor(Fill), False);
  FPage.MoveTo(Pts[0].X, Y(Pts[0].Y));
  for I := 1 to High(Pts) do
    FPage.DrawLine(Pts[I - 1].X, Y(Pts[I - 1].Y), Pts[I].X, Y(Pts[I].Y), WidthMM * 72 / 25.4, False);
  if Closed then FPage.ClosePath;
  if Fill <> clNone then FPage.FillEvenOddStrokePath
  else
    FPage.StrokePath;
end;

procedure TPdfBook.SaveToFile(const Path: string);
begin
  FPDF.SaveToFile(Path);
end;

end.

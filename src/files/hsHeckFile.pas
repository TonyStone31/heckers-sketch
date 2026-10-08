unit hsHeckFile;

{ Reads and writes a drawing file: a Heck header, then one sheet block per
  sheet carrying its settings (units, scale, snap, view, camera) and its drawing.
  Readers skip settings they do not know (rule 6).  A draft or update handoff
  also stores each tab's file, document, name and saved state.  Heck is the
  only format read; the older line format is refused with advice on converting. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, hsDrawing, hsHeckWriter, hsHeckReader, hsText;

type
  THeckSheet = record
    Name: string;
    Doc: TWorkDoc;               { the caller's to free }
    Units: TUnitSystem;
    ScaleIdx, SnapIdx: Integer;
    View: TViewKind;
    CamKnown: Boolean;
    Az, El, Zoom, ViewX, ViewY: Double;
    SliceOn: Boolean;
    SliceLo, SliceHi: Double;
    { Drafts and handoffs only: the tab's file, document, name and saved state. }
    HasSession: Boolean;
    DocKey: Integer;
    FilePath, DocName: string;
    Dirty: Boolean;
  end;
  THeckSheets = array of THeckSheet;

{ A sheet with the program's defaults and a new, empty drawing. }
function NewHeckSheet(const Name: string): THeckSheet;
{ Judged by the first line that is not blank or a note. }
function IsHeckText(L: TStrings): Boolean;
{ Session adds each tab's file and document (drafts, handoffs).  Quick writes
  every face and skips reading the text back, for drafts saved every few seconds. }
procedure WriteHeckFile(const Sheets: array of THeckSheet; L: TStrings; Session, Quick: Boolean);
{ Appends each sheet to Sheets as a new drawing.  On failure returns False with
  the line and reason, and adds nothing. }
function ReadHeckFile(L: TStrings; var Sheets: THeckSheets; out ErrLine: Integer; out Err: string): Boolean;
{ ReadHeckFile for Heck text; otherwise False with a message saying whether
  it is the old line format or not a drawing at all. }
function ReadDrawingFile(L: TStrings; var Sheets: THeckSheets; out ErrLine: Integer; out Err: string): Boolean;

implementation

const
  VIEW_WORDS: array[TViewKind] of string = ('plan', 'iso', '3d');

function Num(V: Double): string;
begin
  Result := FloatToStrF(V, ffGeneral, 12, 0, DotFS);
end;

function NumOf(const S: string; Def: Double): Double;
begin
  Result := StrToFloatDef(Trim(S), Def, DotFS);
end;

function NewHeckSheet(const Name: string): THeckSheet;
begin
  Result := Default(THeckSheet);
  Result.Name := Name;
  Result.Doc := TWorkDoc.Create;
  Result.Units := usImperial;
  Result.ScaleIdx := 2;
  Result.SnapIdx := 5;
  Result.View := vkPlan;
  Result.Zoom := 1;
  Result.DocKey := -1;
end;

{ the first line that is not blank or a note }
function FirstWord(L: TStrings): string;
var
  I: Integer;
  S: string;
begin
  Result := '';
  for I := 0 to L.Count - 1 do
  begin
    S := Trim(L[I]);
    if (S = '') or (S[1] = '#') or (Copy(S, 1, 2) = '//') or (S[1] = '{') then Continue;
    Exit(S);
  end;
end;

function IsHeckText(L: TStrings): Boolean;
begin
  Result := AnsiStartsText('HeckersSketch', FirstWord(L)) or AnsiStartsText('Heck ', FirstWord(L));
end;

{ ---- writing ---- }

procedure WriteHeckFile(const Sheets: array of THeckSheet; L: TStrings; Session, Quick: Boolean);
var
  I, K, Start: Integer;
  One, Extra: TStringList;
  First, Last, LineThing: TIntArrayW;
  Scale: TDrawScale;
begin
  One := TStringList.Create;
  Extra := TStringList.Create;
  try
    for I := 0 to High(Sheets) do
    begin
      Extra.Clear;
      if Sheets[I].Units = usMetric then Extra.Add('units = mm') else Extra.Add('units = ft in');
      Scale := ScaleTable(Sheets[I].Units, Sheets[I].ScaleIdx);
      Extra.Add('scale = ' + QuotedStr(Scale.Name));
      Extra.Add('snap = ' + QuotedStr(SnapName(Sheets[I].Units, Sheets[I].SnapIdx)));
      Extra.Add('view = ' + VIEW_WORDS[Sheets[I].View]);
      Extra.Add('camera = ' + Num(Sheets[I].Az) + ', ' + Num(Sheets[I].El) + ', ' + Num(Sheets[I].Zoom) +
        ', ' + Num(Sheets[I].ViewX) + ', ' + Num(Sheets[I].ViewY));
      if Sheets[I].SliceOn then
        Extra.Add('cut = ' + Num(Sheets[I].SliceLo) + ', ' + Num(Sheets[I].SliceHi));
      if Session then
      begin
        Extra.Add('document = ' + IntToStr(Sheets[I].DocKey));
        Extra.Add('file = ' + QuotedStr(Sheets[I].FilePath));
        Extra.Add('tab = ' + QuotedStr(Sheets[I].DocName));
        Extra.Add('saved = ' + IfThen(Sheets[I].Dirty, 'false', 'true'));
      end;
      One.Clear;
      WriteFormat2(Sheets[I].Doc, Sheets[I].Name, Sheets[I].Units, One, First, Last, LineThing,
        nil, nil, Extra, Quick);
      { Header from the first sheet only; later sheets start after it, with
        the comments written above their "sheet" line }
      Start := 0;
      if I > 0 then
      begin
        while (Start < One.Count) and (One[Start] <> '') do Inc(Start);
        Inc(Start);
        L.Add('');
      end;
      for K := Start to One.Count - 1 do L.Add(One[K]);
    end;
  finally
    Extra.Free;
    One.Free;
  end;
end;

{ ---- reading ---- }

procedure ApplyProps(var S: THeckSheet; P: TStringList);
var
  V: string;
  K: Integer;
  W: TStringArray;
  U: TUnitSystem;
begin
  V := LowerCase(Trim(P.Values['units']));
  if V <> '' then
    if (Pos('mm', V) > 0) or (V = 'm') then S.Units := usMetric else S.Units := usImperial;
  U := S.Units;
  V := Unquote(P.Values['scale']);
  if V <> '' then
    for K := 0 to SCALE_COUNT - 1 do
      if SameText(ScaleTable(U, K).Name, V) then S.ScaleIdx := K;
  V := Unquote(P.Values['snap']);
  if V <> '' then
    for K := 0 to SNAP_COUNT - 1 do
      if SameText(SnapName(U, K), V) then S.SnapIdx := K;
  V := LowerCase(Trim(P.Values['view']));
  if V = 'plan' then S.View := vkPlan
  else if V = 'iso' then S.View := vkIso
  else if V = '3d' then S.View := vkOrbit;
  W := P.Values['camera'].Split([',']);
  if Length(W) >= 5 then
  begin
    S.Az := NumOf(W[0], 0);
    S.El := EnsureRange(NumOf(W[1], 0), -1.45, 1.45);
    S.Zoom := NumOf(W[2], 1);
    S.ViewX := NumOf(W[3], 0);
    S.ViewY := NumOf(W[4], 0);
    S.CamKnown := True;
  end;
  W := P.Values['cut'].Split([',']);
  if Length(W) >= 2 then
  begin
    S.SliceLo := NumOf(W[0], 0);
    S.SliceHi := NumOf(W[1], 0);
    S.SliceOn := True;
  end;
  if P.IndexOfName('document') >= 0 then
  begin
    S.HasSession := True;
    S.DocKey := StrToIntDef(Trim(P.Values['document']), -1);
    S.FilePath := Unquote(P.Values['file']);
    S.DocName := Unquote(P.Values['tab']);
    S.Dirty := LowerCase(Trim(P.Values['saved'])) = 'false';
  end;
end;

function ReadHeckFile(L: TStrings; var Sheets: THeckSheets; out ErrLine: Integer; out Err: string): Boolean;
var
  Spans: THeckSheetSpans;
  Head, Chunk: TStringList;
  I, K, Base, E: Integer;
  LineOf: array of Integer;    { each line of Chunk in L }
  S: THeckSheet;
  U: TUnitSystem;

  procedure Take(K: Integer);
  begin
    Chunk.Add(L[K]);
    SetLength(LineOf, Chunk.Count);
    LineOf[Chunk.Count - 1] := K;
  end;

  function IsComment(const Line: string): Boolean;
  begin
    Result := (Copy(Trim(Line), 1, 2) = '//') or (Copy(Trim(Line), 1, 1) = '{');
  end;

begin
  Result := False;
  ErrLine := -1;
  Err := '';
  Base := Length(Sheets);
  Spans := HeckSheets(L);
  Head := TStringList.Create;
  Chunk := TStringList.Create;
  try
    { Everything before the first sheet (header, file units) applies to every sheet. }
    if Length(Spans) > 0 then
      for K := 0 to Spans[0].Head - 1 do Head.Add(L[K]);
    U := usImperial;
    for K := 0 to Head.Count - 1 do
      if AnsiStartsText('units', Trim(Head[K])) and (Pos('mm', LowerCase(Head[K])) > 0) then U := usMetric;
    if Length(Spans) = 0 then
    begin
      { Text with no sheet block (typed, or a fragment) is one sheet. }
      S := NewHeckSheet('Sheet 1');
      S.Units := U;
      if not ReadHeck(L, S.Doc, U, ErrLine, Err) then
      begin
        S.Doc.Free;
        Exit;
      end;
      SetLength(Sheets, Base + 1);
      Sheets[Base] := S;
      Exit(True);
    end;
    for I := 0 to High(Spans) do
    begin
      S := NewHeckSheet(Spans[I].Name);
      S.Units := U;
      ApplyProps(S, Spans[I].Props);
      { the header for its units; the comments at the top of the file are
        the first sheet's, and those between two sheets the second's }
      Chunk.Clear;
      SetLength(LineOf, 0);
      for K := 0 to Head.Count - 1 do
        if (I = 0) or not IsComment(Head[K]) then Take(K);
      if I > 0 then
        for K := Spans[I - 1].Tail + 1 to Spans[I].Head - 1 do Take(K);
      for K := Spans[I].Head to Spans[I].Tail do Take(K);
      if not ReadHeck(Chunk, S.Doc, S.Units, E, Err) then
      begin
        S.Doc.Free;
        { Map the error back to the file's own line number. }
        if (E >= 0) and (E < Length(LineOf)) then ErrLine := LineOf[E] else ErrLine := Spans[I].Head;
        for K := Base to High(Sheets) do Sheets[K].Doc.Free;
        SetLength(Sheets, Base);
        Exit;
      end;
      SetLength(Sheets, Length(Sheets) + 1);
      Sheets[High(Sheets)] := S;
    end;
    Result := True;
  finally
    for I := 0 to High(Spans) do Spans[I].Props.Free;
    Chunk.Free;
    Head.Free;
  end;
end;

function ReadDrawingFile(L: TStrings; var Sheets: THeckSheets; out ErrLine: Integer; out Err: string): Boolean;
begin
  ErrLine := -1;
  Err := '';
  if IsHeckText(L) then Exit(ReadHeckFile(L, Sheets, ErrLine, Err));
  { The old line format started with this; recognize it so the message says
    how to convert it instead of "not a drawing". }
  if AnsiStartsStr('HECKERS-SKETCH', FirstWord(L)) then
    Err := 'It is a drawing in the old format, from before Heck.  Open it in ' +
      'v2026.10.02.2 or earlier and save it again - it is saved as Heck - and ' +
      'this version will open it.'
  else
    Err := 'That does not look like a Heckers Sketch drawing.';
  Result := False;
end;

end.

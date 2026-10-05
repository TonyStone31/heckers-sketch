unit hsSourceWindow;

{ The sheet as Heck text, beside the sheet.  Picking works both ways: things
  picked on the sheet light up their lines here, and lines picked here pick
  their things on the sheet.  The text can also be edited and applied.
  It knows nothing of the main form: it talks through the On* events and
  polls OnAskState on a timer, so it can become a docked pane unchanged. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Menus,
  SynEdit, SynEditTypes, SynGutterBase, SynGutter, SynGutterCodeFolding,
  SynGutterLineNumber, SynEditMarkupHighAll, SynEditMarkupWordGroup, SynEditMouseCmds, LCLIntf,
  SynEditMiscProcs, LazSynEditText, SynEditFoldedView,
  BCButton, BGRATheme, BGRAThemeCheckBox, hsDrawing, hsHeckHighlight, hsJigRun, hsHeckSample, hsHeckComplete,
  hsHeckWriter, StrUtils, hsDialogSkin;

type
  TSourceAskState = procedure(out DocSeq, PickSeq: Int64) of object;
  { The sheet's text as saved.  LineThing may come back empty; it is then
    worked out from First and Last. }
  TSourceAskSource = procedure(L, Hints, Names: TStrings;
    out First, Last, LineThing: TIntArrayW; out SheetName: string) of object;
  TSourceAskPicked = procedure(out Picked: TIntArrayW) of object;
  TSourcePickThings = procedure(const Things: TIntArrayW) of object;
  { False with the line and reason when the text cannot become the drawing. }
  TSourceApply = function(L: TStrings; out ErrLine: Integer; out Err: string): Boolean of object;
  TSourceRunJigs = function: Integer of object;
  { Runs the jig of this thing; True if it ran. }
  TSourceRunJig = function(Thing: Integer): Boolean of object;
  { Start or stop the sheet taking a point for the text. }
  TSourcePick = procedure(On: Boolean) of object;
  { Center and fit what is picked on the sheet. }
  TSourceCenter = procedure of object;

  { TSourceForm }

  TJigGutter = class;

  TSourceForm = class(TForm)
    chkOnlyPicked: TBGRAThemeCheckBox;
    chkOnTop: TBGRAThemeCheckBox;
    btnFold: TBCButton;
    btnApply: TBCButton;
    btnRevert: TBCButton;
    btnSample: TBCButton;
    btnJigs: TBCButton;
    btnPick: TBCButton;
    lblApply: TLabel;
    pnlApply: TPanel;
    btnUnfold: TBCButton;
    edtFind: TEdit;
    Editor: TSynEdit;
    pnlTop: TPanel;
    Status: TLabel;
    tmrFollow: TTimer;
    pmEditor: TPopupMenu;
    miCenter: TMenuItem;
    miGoTo: TMenuItem;
    miRunJig: TMenuItem;
    procedure chkOnlyPickedChange(Sender: TObject);
    procedure chkOnTopChange(Sender: TObject);
    procedure btnFoldClick(Sender: TObject);
    procedure btnApplyClick(Sender: TObject);
    procedure btnRevertClick(Sender: TObject);
    procedure btnSampleClick(Sender: TObject);
    procedure btnJigsClick(Sender: TObject);
    procedure btnPickClick(Sender: TObject);
    procedure EditorChange(Sender: TObject);
    procedure btnUnfoldClick(Sender: TObject);
    procedure edtFindKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditorSpecialLineColors(Sender: TObject; Line: integer;
      var Special: boolean; var FG, BG: TColor);
    procedure EditorStatusChange(Sender: TObject; Changes: TSynStatusChanges);
    procedure EditorMouseLink(Sender: TObject; X, Y: Integer;
      var AllowMouseLink: Boolean);
    procedure EditorClickLink(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure FormActivate(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure tmrFollowTimer(Sender: TObject);
    procedure miCenterClick(Sender: TObject);
    procedure miGoToClick(Sender: TObject);
    procedure miRunJigClick(Sender: TObject);
    procedure pmEditorPopup(Sender: TObject);
  private
    FAll: TStringList;          { the whole sheet's text }
    FHints: TStringList;        { where each point written as a step lands }
    FNames: TStringList;        { every named point: "line|name=place" }
    FHintWord: string;
    FWhat: string;
    FEdited: Boolean;           { the text is being edited; it no longer follows the drawing }
    FErrRow: Integer;
    FDark: Boolean;
    FPickBG, FPickFG: TColor;
    FFirst, FLast: TIntArrayW;  { thing -> its lines in FAll }
    FLineThing: TIntArrayW;     { line in FAll -> thing, or -1 }
    FRowLine: TIntArrayW;       { row shown in the editor -> line in FAll }
    FLinePicked: array of Boolean;
    FPicked: TIntArrayW;
    FDocSeq, FPickSeq: Int64;
    FHaveState: Boolean;
    FBusy: Boolean;             { we are moving the caret, not the person }
    FCaretRow, FBlockA, FBlockB: Integer;
    FColors: TSynHsk2Syn;
    FComplete: THeckCompleter;
    FJigGutter: TJigGutter;
    FFoldJigs: Boolean;           { fold the jigs' output on the next tick }
    FPickFirst: TP3;              { the first point picked for the caret line }
    FPickLine: Integer;           { which line that was; -1 for none }
    FPicking: Boolean;
    FCompleteChange: TNotifyEvent;
    FCompleteKey: TKeyEvent;
    procedure SetEdited(On_: Boolean; const Msg: string = '');
    procedure FoldToPicked;
    { The 0-based row that defines Name_, looking back from FromRow:
      "name = ..." in a points block, or "circle name". }
    function DefinedAt(const Name_: string; FromRow: Integer): Integer;
    { Where a named point is, from the nearest points block above. }
    function WhereIs(const Name_: string; FromRow: Integer): string;
    procedure FindNext(Back: Boolean);
    procedure OpenJigOn(const Line: string);
    procedure JumpTo(Row: Integer);
    procedure EditorMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure LoadText;
    procedure ShowRows;
    procedure ShowPicked(Scroll: Boolean);
    procedure TellPicked;
  public
    OnAskState: TSourceAskState;
    OnAskSource: TSourceAskSource;
    OnAskPicked: TSourceAskPicked;
    OnPickThings: TSourcePickThings;
    OnApply: TSourceApply;
    OnRunJigs: TSourceRunJigs;
    OnRunJig: TSourceRunJig;
    OnCenter: TSourceCenter;
    OnPick: TSourcePick;
    { A point picked on the sheet for the caret's line.  The first pick is a
      place; after that a line adds "to" and a place, a box, rect or pull adds
      ";" and the step, a circle adds ";" and the radius. }
    procedure TakePoint(const P: TP3; U: TUnitSystem);
    { The sheet ended the pick. }
    procedure PickEnded;
    { What the next pick is for: the <part> the caret is in, else the first
      left on the line, else "the line". }
    function PickWants: string;
    { Is this 0-based line a "jig = " line? }
    function IsJigLine(Line: Integer): Boolean;
    { The gutter's play button on a jig line was pressed. }
    procedure RunJigAt(Line: Integer);
    { Check now instead of waiting for the next tick. }
    procedure Refresh_;
    { Match the program's theme, including the picked-line wash and axis colors. }
    procedure UseDark(Dark: Boolean; Back, Fore: TColor);
    { The window around the page in the dialog theme (hsDialogSkin); the page
      itself is UseDark's. }
    procedure ThemeChrome;
    { The 1-based line number and text of thing I; False when the text is not current. }
    function LineOfThing(I: Integer; out LineNo: Integer; out Line: string): Boolean;
    { Public so a command or a test can press them. }
    procedure LoadSample;
    procedure ApplyNow;
    { Completion opens by itself, or only on Ctrl+Space. }
    procedure SetAutoComplete(On: Boolean);
    function AutoComplete: Boolean;
  private
    procedure PartToFill(const L: string; out A, B: Integer);
  end;

  { A play mark in the gutter on every "jig = " line; clicking it runs that
    jig alone.  The jig's output folds under the line (see the highlighter). }
  TJigGutter = class(TSynGutterPartBase)
  private
    FForm: TSourceForm;
  public
    procedure Paint(Canvas: TCanvas; AClip: TRect; FirstLine, LastLine: integer); override;
    procedure MouseDown(const AnInfo: TSynEditMouseActionInfo); override;
    { Fold the jig's output under this line.  Done here because a friend of
      the editor can reach the folded view and the form cannot. }
    procedure FoldLine(Line: Integer);
    property Form: TSourceForm read FForm write FForm;
  end;

var
  SourceForm: TSourceForm;

implementation

{$R *.lfm}

const
  PICKED_BG = TColor($FFE2C2);   { a pale blue, under the picked lines }
  PICKED_FG = TColor($401000);

{ TJigGutter }

procedure TJigGutter.Paint(Canvas: TCanvas; AClip: TRect; FirstLine, LastLine: integer);
var
  I, J, H, Cx, Cy: Integer;
  R: TRect;
  Range: TLineRange;
begin
  PaintBackground(Canvas, AClip);
  if FForm = nil then Exit;
  H := SynEdit.LineHeight;
  for I := FirstLine to LastLine do
  begin
    J := ViewedTextBuffer.DisplayView.ViewToTextIndexEx(I + ToIdx(GutterArea.TextArea.TopViewedLine), Range);
    if (J < 0) or (J >= SynEdit.Lines.Count) or not FForm.IsJigLine(J) then Continue;
    R := AClip;
    R.Top := AClip.Top + (I - FirstLine) * H;
    R.Bottom := R.Top + H;
    { a small right-pointing triangle in the gutter's ink }
    Cx := (R.Left + R.Right) div 2;
    Cy := (R.Top + R.Bottom) div 2;
    Canvas.Brush.Color := MarkupInfo.Foreground;
    Canvas.Pen.Color := MarkupInfo.Foreground;
    Canvas.Polygon([Point(Cx - 3, Cy - 4), Point(Cx + 4, Cy), Point(Cx - 3, Cy + 4)]);
  end;
end;

procedure TJigGutter.FoldLine(Line: Integer);
begin
  TSynEditFoldedView(FoldedTextBuffer).FoldAtTextIndex(Line);
end;

procedure TJigGutter.MouseDown(const AnInfo: TSynEditMouseActionInfo);
var
  J: Integer;
begin
  inherited MouseDown(AnInfo);
  if (FForm = nil) or (AnInfo.Button <> mbXLeft) then Exit;
  J := AnInfo.NewCaret.LinePos - 1;
  if FForm.IsJigLine(J) then FForm.RunJigAt(J);
end;

procedure TSourceForm.FormCreate(Sender: TObject);
begin
  FAll := TStringList.Create;
  FHints := TStringList.Create;
  FNames := TStringList.Create;
  FHaveState := False;
  FCaretRow := -1;
  FErrRow := -1;
  FPickBG := PICKED_BG;
  FPickFG := PICKED_FG;
  FColors := TSynHsk2Syn.Create(Self);
  FComplete := THeckCompleter.Create(Editor);
  FCompleteChange := Editor.OnChange;
  FCompleteKey := Editor.OnKeyDown;
  Editor.OnChange := @EditorChange;

  { Editor features as in Lazarus: other uses of the word under the caret
    are outlined, Ctrl+click goes to a name's definition, and hovering shows it. }
  with Editor.MarkupByClass[TSynEditMarkupHighlightAllCaret] as TSynEditMarkupHighlightAllCaret do
  begin
    MarkupInfo.Background := clNone;
    MarkupInfo.FrameColor := TColor($C08040);
    MarkupInfo.FrameStyle := slsSolid;
    FullWord := True;
    WaitTime := 250;
    IgnoreKeywords := False;
    Enabled := True;
  end;
  { Outline the opening word of the caret's block and its "end", like begin/end. }
  with Editor.MarkupByClass[TSynEditMarkupWordGroup] as TSynEditMarkupWordGroup do
  begin
    MarkupInfo.Background := clNone;
    MarkupInfo.Foreground := clNone;
    MarkupInfo.FrameColor := TColor($2060C0);
    MarkupInfo.FrameStyle := slsSolid;
    MarkupInfo.FrameEdges := sfeAround;
    Enabled := True;
  end;
  Editor.MouseOptions := Editor.MouseOptions + [emShowCtrlMouseLinks, emCtrlWheelZoom];
  Editor.OnKeyDown := @EditorKeyDown;   { passes keys on to the completer }
  Editor.OnMouseLink := @EditorMouseLink;
  Editor.OnClickLink := @EditorClickLink;
  Editor.OnMouseMove := @EditorMouseMove;
  Editor.PopupMenu := pmEditor;
  Editor.OnMouseDown := @EditorMouseDown;
  { Leave room after the fold marks so a caret in column one is not lost
    against the gutter. }
  Editor.Gutter.RightOffset := 6;
  Editor.ShowHint := True;
  { the jig play button, after the line numbers }
  FJigGutter := TJigGutter.Create(Editor.Gutter.Parts);
  FJigGutter.Form := Self;
  FJigGutter.Width := 14;
  FJigGutter.AutoSize := False;
  ThemeChrome;
end;

function TSourceForm.IsJigLine(Line: Integer): Boolean;
var
  T: string;
begin
  Result := False;
  if (Line < 0) or (Line >= Editor.Lines.Count) then Exit;
  T := LowerCase(TrimLeft(Editor.Lines[Line]));
  Result := (Copy(T, 1, 3) = 'jig') and (Pos('=', T) > 0) and
            (Trim(Copy(T, 4, Pos('=', T) - 4)) = '');
end;

procedure TSourceForm.RunJigAt(Line: Integer);
var
  T: Integer;
begin
  if FEdited then
  begin
    lblApply.Caption := 'Apply or Revert first - the jig runs on the drawing, not on what is typed here.';
    Exit;
  end;
  { The group the line belongs to, mapped through the row map. }
  T := -1;
  if (Line >= 0) and (Line < Length(FRowLine)) and (FRowLine[Line] >= 0) and
     (FRowLine[Line] < Length(FLineThing)) then T := FLineThing[FRowLine[Line]];
  if T < 0 then Exit;
  if Assigned(OnRunJig) and OnRunJig(T) then Refresh_;
end;

procedure TSourceForm.FormDestroy(Sender: TObject);
begin
  FComplete.Free;
  FAll.Free;
  FHints.Free;
  FNames.Free;
end;

procedure TSourceForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

procedure TSourceForm.LoadSample;
begin
  btnSampleClick(nil);
end;

procedure TSourceForm.ApplyNow;
begin
  if FEdited then btnApplyClick(nil);
end;

procedure TSourceForm.SetAutoComplete(On: Boolean);
begin
  FComplete.Auto := On;
end;

function TSourceForm.AutoComplete: Boolean;
begin
  Result := FComplete.Auto;
end;

procedure TSourceForm.Refresh_;
begin
  FHaveState := False;
  tmrFollowTimer(nil);
end;

{ If the drawing changed, fetch the text again; if only the picking
  changed, relight the same text. }
procedure TSourceForm.tmrFollowTimer(Sender: TObject);
var
  D, P: Int64;
  I: Integer;
begin
  if not Visible then Exit;
  { Fold the jigs now that the highlighter has been over the text; folds
    asked for before that are ignored. }
  if FFoldJigs then
  begin
    FFoldJigs := False;
    for I := 0 to Editor.Lines.Count - 1 do
      if IsJigLine(I) then FJigGutter.FoldLine(I);
  end;
  if not Assigned(OnAskState) then Exit;
  if FEdited then Exit;        { edited text waits for Apply }
  OnAskState(D, P);
  if FHaveState and (D = FDocSeq) and (P = FPickSeq) then Exit;
  if (not FHaveState) or (D <> FDocSeq) then
  begin
    FDocSeq := D;
    FPickSeq := P;
    FHaveState := True;
    LoadText;
    ShowPicked(True);
  end
  else
  begin
    FPickSeq := P;
    ShowPicked(True);
  end;
end;

procedure TSourceForm.LoadText;
var
  I, K: Integer;
  Name_: string;
begin
  FAll.Clear;
  SetLength(FFirst, 0);
  SetLength(FLast, 0);
  Name_ := '';
  SetLength(FLineThing, 0);
  FHints.Clear;
  FNames.Clear;
  if Assigned(OnAskSource) then
    OnAskSource(FAll, FHints, FNames, FFirst, FLast, FLineThing, Name_);
  if Length(FLineThing) <> FAll.Count then
  begin
    SetLength(FLineThing, FAll.Count);
    for I := 0 to High(FLineThing) do FLineThing[I] := -1;
    for I := 0 to High(FFirst) do
      for K := FFirst[I] to FLast[I] do
        if (K >= 0) and (K < FAll.Count) then FLineThing[K] := I;
  end;
  FWhat := 'The sheet as Heck.';
  if Name_ <> '' then Caption := 'Source - ' + Name_ else Caption := 'Source';
end;

{ Put the rows in the editor.  FRowLine maps each row to its sheet line.
  Today every row is its own line, but the map lets a view that leaves lines
  out work without other changes. }
procedure TSourceForm.ShowRows;
var
  I, WasTop: Integer;
  L: TStringList;
begin
  FBusy := True;
  L := TStringList.Create;
  try
    WasTop := Editor.TopLine;
    { Every line, always: "only what is picked" folds the other blocks shut
      instead of removing them (see FoldToPicked). }
    L.Assign(FAll);
    SetLength(FRowLine, FAll.Count);
    for I := 0 to FAll.Count - 1 do FRowLine[I] := I;
    Editor.Highlighter := FColors;
    Editor.ReadOnly := False;
    if Editor.Lines.Text <> L.Text then
    begin
      Editor.Lines.Assign(L);
      { A jig's output starts folded under its line; opened by hand, it stays
        open until the text changes. }
      FFoldJigs := True;
    end;
    if WasTop <= Editor.Lines.Count then Editor.TopLine := WasTop;
  finally
    L.Free;
    FBusy := False;
  end;
end;

procedure TSourceForm.ShowPicked(Scroll: Boolean);
var
  I, K, FirstRow, Rows: Integer;
begin
  SetLength(FPicked, 0);
  if Assigned(OnAskPicked) then OnAskPicked(FPicked);
  SetLength(FLinePicked, FAll.Count);
  for I := 0 to High(FLinePicked) do FLinePicked[I] := False;
  for I := 0 to High(FPicked) do
    if (FPicked[I] >= 0) and (FPicked[I] <= High(FFirst)) then
      for K := FFirst[FPicked[I]] to FLast[FPicked[I]] do
        if (K >= 0) and (K < FAll.Count) then FLinePicked[K] := True;

  ShowRows;
  FoldToPicked;

  { Scroll the first picked line into view only if it is not already
    visible, so the window does not jump around while picking. }
  FirstRow := -1;
  for I := 0 to High(FRowLine) do
    if FLinePicked[FRowLine[I]] then begin FirstRow := I; Break; end;
  if Scroll and (FirstRow >= 0) then
  begin
    Rows := Editor.LinesInWindow;
    if (FirstRow + 1 < Editor.TopLine) or (FirstRow + 1 >= Editor.TopLine + Rows) then
    begin
      FBusy := True;
      try
        if FirstRow + 1 > 3 then Editor.TopLine := FirstRow + 1 - 3
        else Editor.TopLine := 1;
      finally
        FBusy := False;
      end;
    end;
  end;
  Editor.Invalidate;
  TellPicked;
end;

{ "Only what is picked": shut every block, then open the picked things'
  blocks, so the whole drawing is still there a line each. }
procedure TSourceForm.FoldToPicked;
var
  I, N: Integer;
begin
  FBusy := True;
  try
    Editor.UnfoldAll;
    if not (chkOnlyPicked.Checked and (Length(FPicked) > 0)) then Exit;
    Editor.FoldAll(1, False);
    N := 0;
    for I := 0 to High(FPicked) do
    begin
      if (FPicked[I] < 0) or (FPicked[I] > High(FFirst)) then Continue;
      if FFirst[FPicked[I]] > FLast[FPicked[I]] then Continue;
      Editor.CaretXY := Point(1, FLast[FPicked[I]] + 1);
      Editor.EnsureCursorPosVisible;
      Inc(N);
      if N >= 200 then Break;     { opening thousands one by one is slow }
    end;
  finally
    FBusy := False;
  end;
end;

procedure TSourceForm.TellPicked;
begin
  if Length(FPicked) = 0 then
    Status.Caption := Format('  %s  %d lines, %d things.  Click a line to pick it; ' +
      'Ctrl+click a name to go to it.', [FWhat, FAll.Count, Length(FFirst)])
  else
    Status.Caption := Format('  %s  %d lines, %d things.  %d picked.',
      [FWhat, FAll.Count, Length(FFirst), Length(FPicked)]);
end;

procedure TSourceForm.EditorSpecialLineColors(Sender: TObject; Line: integer;
  var Special: boolean; var FG, BG: TColor);
var
  R: Integer;
begin
  R := Line - 1;
  if R = FErrRow then
  begin
    Special := True;
    BG := TColor($D0D0FF);
    FG := TColor($000080);
    Exit;
  end;
  if FEdited then Exit;
  if (R < 0) or (R > High(FRowLine)) then Exit;
  if (FRowLine[R] <= High(FLinePicked)) and FLinePicked[FRowLine[R]] then
  begin
    Special := True;
    BG := FPickBG;
    FG := FPickFG;
  end;
end;

{ The caret moved or a block was dragged: pick those lines' things on the
  sheet.  Skip while rows are being loaded or when nothing moved, since
  SynEdit reports status for many reasons. }
procedure TSourceForm.EditorStatusChange(Sender: TObject; Changes: TSynStatusChanges);
var
  A, B, R, T, N, I: Integer;
  Things: TIntArrayW;
  Dup: Boolean;
begin
  if FBusy or FEdited then Exit;
  if Changes * [scCaretY, scSelection] = [] then Exit;
  A := Editor.CaretY - 1;
  B := A;
  if Editor.SelAvail then
  begin
    A := Editor.BlockBegin.Y - 1;
    B := Editor.BlockEnd.Y - 1;
    { a block that ends at the very start of a line does not include it }
    if (Editor.BlockEnd.X = 1) and (B > A) then Dec(B);
  end;
  if (A = FBlockA) and (B = FBlockB) and (Editor.CaretY - 1 = FCaretRow) then Exit;
  FBlockA := A;
  FBlockB := B;
  FCaretRow := Editor.CaretY - 1;

  N := 0;
  SetLength(Things, B - A + 1);
  for R := A to B do
  begin
    if (R < 0) or (R > High(FRowLine)) then Continue;
    T := FLineThing[FRowLine[R]];
    if T < 0 then Continue;
    Dup := False;
    for I := 0 to N - 1 do
      if Things[I] = T then begin Dup := True; Break; end;
    if Dup then Continue;
    Things[N] := T;
    Inc(N);
  end;
  SetLength(Things, N);
  if Assigned(OnPickThings) then OnPickThings(Things);
  { Read back what the sheet picked (a line inside a group picks the group)
    right away, without scrolling: the person is looking where they clicked. }
  if Assigned(OnAskState) then OnAskState(FDocSeq, FPickSeq);
  { Keep the rows even when only picked ones are shown; removing rows from
    under the pointer would make a second click impossible. }
  SetLength(FPicked, 0);
  if Assigned(OnAskPicked) then OnAskPicked(FPicked);
  SetLength(FLinePicked, FAll.Count);
  for I := 0 to High(FLinePicked) do FLinePicked[I] := False;
  for I := 0 to High(FPicked) do
    if (FPicked[I] >= 0) and (FPicked[I] <= High(FFirst)) then
      for R := FFirst[FPicked[I]] to FLast[FPicked[I]] do
        if (R >= 0) and (R < FAll.Count) then FLinePicked[R] := True;
  Editor.Invalidate;
  TellPicked;
end;

function TSourceForm.DefinedAt(const Name_: string; FromRow: Integer): Integer;
var
  R, P: Integer;
  T, Stem: string;
begin
  Result := -1;
  if (Name_ = '') or (FromRow > Editor.Lines.Count - 1) then Exit;
  Stem := LowerCase(Name_);
  P := Length(Stem);
  while (P > 0) and (Stem[P] in ['0'..'9']) do Dec(P);
  if (P = Length(Stem)) or (P = 0) then Stem := '' else Stem := Copy(Stem, 1, P);
  for R := FromRow downto 0 do
  begin
    T := LowerCase(Trim(Editor.Lines[R]));
    if (Copy(T, 1, Length(Name_) + 1) = LowerCase(Name_) + ' ') and
       (Pos('=', T) > 0) and (Trim(Copy(T, Length(Name_) + 1, Pos('=', T) - Length(Name_) - 1)) = '') then
      Exit(R);
    if T = 'circle ' + LowerCase(Name_) then Exit(R);
    { ra5 is a corner of "ring ra", but floor1 and top1 are their own names }
    if (Stem <> '') and (T = 'ring ' + Stem) then Exit(R);
  end;
  { a circle may be written further down than the face that names it }
  for R := FromRow + 1 to Editor.Lines.Count - 1 do
    if LowerCase(Trim(Editor.Lines[R])) = 'circle ' + LowerCase(Name_) then Exit(R);
end;

function TSourceForm.WhereIs(const Name_: string; FromRow: Integer): string;
var
  I, Bar, Eq, Ln, BestLn, Row: Integer;
  E: string;
begin
  Result := '';
  if (FromRow < 0) or (FromRow > High(FRowLine)) then Exit;
  Row := FRowLine[FromRow];
  BestLn := -1;
  for I := 0 to FNames.Count - 1 do
  begin
    E := FNames[I];
    Bar := Pos('|', E);
    Eq := Pos('=', E);
    if (Bar = 0) or (Eq < Bar) then Continue;
    if Copy(E, Bar + 1, Eq - Bar - 1) <> LowerCase(Name_) then Continue;
    Ln := StrToIntDef(Copy(E, 1, Bar - 1), -1);
    if (Ln <= Row) and (Ln > BestLn) then
    begin
      BestLn := Ln;
      Result := Copy(E, Eq + 1, MaxInt);
    end;
  end;
end;

{ jig = 'star' with ... : open star in whatever this machine opens that
  kind of file with. }
procedure TSourceForm.OpenJigOn(const Line: string);
var
  A, B: Integer;
  F: string;
begin
  A := Pos('''', Line);
  if A = 0 then Exit;
  B := A + 1;
  while (B <= Length(Line)) and (Line[B] <> '''') do Inc(B);
  F := FindJig(Copy(Line, A + 1, B - A - 1));
  if F = '' then
    Status.Caption := '  There is no jig called "' + Copy(Line, A + 1, B - A - 1) + '" in ' + JigsDir
  else
    OpenDocument(F);
end;

procedure TSourceForm.FindNext(Back: Boolean);
var
  Opt: TSynSearchOptions;
begin
  if edtFind.Text = '' then Exit;
  Opt := [];
  if Back then Opt := [ssoBackwards];
  if Editor.SearchReplace(edtFind.Text, '', Opt) = 0 then
  begin
    { wrap around }
    if Back then Editor.CaretXY := Point(1, Editor.Lines.Count)
    else Editor.CaretXY := Point(1, 1);
    if Editor.SearchReplace(edtFind.Text, '', Opt) = 0 then
      Status.Caption := '  "' + edtFind.Text + '" is not in it.';
  end;
end;

procedure TSourceForm.edtFindKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = 13 then
  begin
    FindNext(ssShift in Shift);
    Key := 0;
  end
  else if Key = 27 then
  begin
    Editor.SetFocus;
    Key := 0;
  end;
end;

{ Ctrl+F to the find box, F3 and Shift+F3 for next and previous }
procedure TSourceForm.EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  { Esc ends a pick here as it does on the sheet }
  if (Key = 27) and FPicking then
  begin
    btnPickClick(nil);
    Key := 0;
    Exit;
  end;
  if Assigned(FCompleteKey) then FCompleteKey(Sender, Key, Shift);
  if (Key = Ord('F')) and (ssCtrl in Shift) then
  begin
    if Editor.SelAvail and (Editor.BlockBegin.Y = Editor.BlockEnd.Y) then
      edtFind.Text := Editor.SelText;
    edtFind.SetFocus;
    edtFind.SelectAll;
    Key := 0;
  end
  else if Key = 114 then         { F3 }
  begin
    FindNext(ssShift in Shift);
    Key := 0;
  end;
end;

{ The text has been edited.  Until Apply or Revert the drawing is not
  read again, lines are not picked from it, and the sheet does not change. }
procedure TSourceForm.SetEdited(On_: Boolean; const Msg: string);
begin
  FEdited := On_;
  pnlApply.Visible := On_;
  if Msg <> '' then lblApply.Caption := Msg
  else lblApply.Caption := 'Changed.  Apply makes the drawing match; nothing on the sheet moves until then.';
  if not On_ then FErrRow := -1;
  Editor.Invalidate;
end;

procedure TSourceForm.EditorChange(Sender: TObject);
begin
  if Assigned(FCompleteChange) and not FBusy then FCompleteChange(Sender);
  if FBusy or Editor.ReadOnly then Exit;
  if not FEdited then SetEdited(True)
  else if FErrRow >= 0 then
  begin
    FErrRow := -1;
    Editor.Invalidate;
  end;
end;

procedure TSourceForm.btnApplyClick(Sender: TObject);
var
  ErrLine, WasTop, CY: Integer;
  Err: string;
begin
  if not Assigned(OnApply) then Exit;
  WasTop := Editor.TopLine;
  CY := Editor.CaretY;
  if OnApply(Editor.Lines, ErrLine, Err) then
  begin
    SetEdited(False);
    Refresh_;
    FBusy := True;
    try
      if WasTop <= Editor.Lines.Count then Editor.TopLine := WasTop;
      if CY <= Editor.Lines.Count then Editor.CaretY := CY;
    finally
      FBusy := False;
    end;
    Exit;
  end;
  { the title can have its joke; the message under it stays plain }
  FErrRow := ErrLine;
  SetEdited(True, Format('What the Heck?  Line %d: %s', [ErrLine + 1, Err]));
  FErrRow := ErrLine;
  if (ErrLine >= 0) and (ErrLine < Editor.Lines.Count) then
  begin
    FBusy := True;
    try
      Editor.CaretXY := Point(1, ErrLine + 1);
      Editor.EnsureCursorPosVisible;
    finally
      FBusy := False;
    end;
  end;
  Editor.Invalidate;
end;

procedure TSourceForm.btnRevertClick(Sender: TObject);
begin
  SetEdited(False);
  Refresh_;
end;

{ Load a sample drawing and jigs into the editor as if typed; Apply makes
  it happen. }
procedure TSourceForm.btnSampleClick(Sender: TObject);
begin
  WriteSampleJigs(JigsDir);
  FBusy := True;
  try
    Editor.ReadOnly := False;
    Editor.Lines.Text := SampleHeck;
  finally
    FBusy := False;
  end;
  SetEdited(True, 'A sample, and its jigs are in ' + JigsDir + '.  Press Apply, then Run jigs.');
end;

procedure TSourceForm.btnJigsClick(Sender: TObject);
begin
  if FEdited then
  begin
    lblApply.Caption := 'Apply or Revert first - the jigs run on the drawing, not on what is typed here.';
    Exit;
  end;
  if Assigned(OnRunJigs) then OnRunJigs();
  Refresh_;
end;

procedure TSourceForm.btnFoldClick(Sender: TObject);
begin
  FBusy := True;
  try
    Editor.FoldAll(1, False);
  finally
    FBusy := False;
  end;
end;

procedure TSourceForm.btnUnfoldClick(Sender: TObject);
begin
  FBusy := True;
  try
    Editor.UnfoldAll;
  finally
    FBusy := False;
  end;
end;

procedure TSourceForm.EditorMouseLink(Sender: TObject; X, Y: Integer;
  var AllowMouseLink: Boolean);
var
  W: string;
  At: Integer;
begin
  W := Editor.GetWordAtRowCol(Point(X, Y));
  At := DefinedAt(W, Y - 1);
  AllowMouseLink := ((At >= 0) and (At <> Y - 1)) or
    ((Y >= 1) and (Y <= Editor.Lines.Count) and
     (LowerCase(Copy(Trim(Editor.Lines[Y - 1]), 1, 3)) = 'jig'));
end;

procedure TSourceForm.EditorClickLink(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
  At: Integer;
begin
  P := Editor.PixelsToLogicalPos(Point(X, Y));
  if (P.Y >= 1) and (P.Y <= Editor.Lines.Count) and
     (LowerCase(Copy(Trim(Editor.Lines[P.Y - 1]), 1, 3)) = 'jig') then
  begin
    OpenJigOn(Editor.Lines[P.Y - 1]);
    Exit;
  end;
  At := DefinedAt(Editor.GetWordAtRowCol(P), P.Y - 1);
  if At < 0 then Exit;
  JumpTo(At);
end;

{ Hovering a name shows the line that defines it, and for a point written
  as a step, where it lands. }
procedure TSourceForm.EditorMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
  W, H: string;
  At: Integer;
begin
  P := Editor.PixelsToLogicalPos(Point(X, Y));
  W := Editor.GetWordAtRowCol(P);
  if W = FHintWord then Exit;
  FHintWord := W;
  H := '';
  At := DefinedAt(W, P.Y - 1);
  if (At >= 0) and (At <> P.Y - 1) then
  begin
    H := Trim(Editor.Lines[At]);
    if WhereIs(W, P.Y - 1) <> '' then
      H := H + LineEnding + W + ' is at  ' + WhereIs(W, P.Y - 1);
  end;
  Application.CancelHint;
  Editor.Hint := H;
end;

{ Right-click picks the thing on the caret's line and centers and fits it
  in the view, so the text and the drawing show the same thing. }
{ The right button moves the caret before the menu opens, so Go to
  Definition and Center in View act on what is under the pointer. }
{ Keys go to the text.  Otherwise focus can land on a checkbox, where every
  space toggles "Only picked", and under GTK a click in the editor does not
  always focus it. }
procedure TSourceForm.FormActivate(Sender: TObject);
begin
  if Editor.CanFocus then Editor.SetFocus;
end;

procedure TSourceForm.EditorMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  A, B, R: Integer;
begin
  if Editor.CanFocus and not Editor.Focused then Editor.SetFocus;
  { a double-click on a <part> starts picking for it }
  if (Button = mbLeft) and (ssDouble in Shift) and not FPicking then
  begin
    R := Editor.CaretY - 1;
    if (R >= 0) and (R < Editor.Lines.Count) then
    begin
      PartToFill(Editor.Lines[R], A, B);
      if (A > 0) and (Editor.CaretX > A) and (Editor.CaretX <= B + 1) then btnPickClick(nil);
    end;
  end;
  if Button <> mbRight then Exit;
  FBusy := True;
  try
    Editor.CaretXY := Editor.PixelsToLogicalPos(Point(X, Y));
    if Editor.SelAvail then
    begin
      Editor.BlockBegin := Editor.CaretXY;
      Editor.BlockEnd := Editor.CaretXY;
    end;
  finally
    FBusy := False;
  end;
end;

function TSourceForm.LineOfThing(I: Integer; out LineNo: Integer; out Line: string): Boolean;
begin
  Result := False;
  LineNo := 0;
  Line := '';
  if FEdited or (I < 0) or (I > High(FFirst)) then Exit;
  if (FFirst[I] < 0) or (FFirst[I] >= FAll.Count) then Exit;
  LineNo := FFirst[I] + 1;
  Line := Trim(FAll[FFirst[I]]);
  Result := True;
end;

procedure TSourceForm.miCenterClick(Sender: TObject);
var
  A, B, Depth, R: Integer;
  T: string;
begin
  if FEdited then Exit;
  { On a line that opens a block (solid, group, points), pick the whole
    block, as dragging over it would. }
  A := Editor.CaretY - 1;
  B := A;
  if (A >= 0) and (A < Editor.Lines.Count) then
  begin
    T := LowerCase(Trim(Editor.Lines[A]));
    if (Pos('=', T) = 0) and (T <> 'end') and (T <> '') then
    begin
      Depth := 1;
      R := A + 1;
      while (R < Editor.Lines.Count) and (Depth > 0) do
      begin
        T := LowerCase(Trim(Editor.Lines[R]));
        if T = 'end' then Dec(Depth)
        else if (T <> '') and (Pos('=', T) = 0) and (T <> 'begin') and
                (T[Length(T)] <> ')') then Inc(Depth);
        Inc(R);
      end;
      B := R - 1;
    end;
  end;
  FBusy := True;
  try
    Editor.BlockBegin := Point(1, A + 1);
    Editor.BlockEnd := Point(1, B + 1);
    if B > A then Editor.BlockEnd := Point(Length(Editor.Lines[B]) + 1, B + 1);
  finally
    FBusy := False;
  end;
  FCaretRow := -1;
  FBlockA := -1;
  FBlockB := -1;
  EditorStatusChange(nil, [scSelection]);
  if Assigned(OnCenter) then OnCenter();
end;

procedure TSourceForm.miGoToClick(Sender: TObject);
var
  At: Integer;
  W: string;
begin
  W := Editor.GetWordAtRowCol(Editor.CaretXY);
  At := DefinedAt(W, Editor.CaretY - 1);
  if At < 0 then Exit;
  JumpTo(At);
end;

{ Go to a line as Lazarus goes to a definition: caret on the first word,
  the line shaded as the caret's, scrolled a few lines from the top. }
procedure TSourceForm.JumpTo(Row: Integer);
var
  C: Integer;
  T: string;
begin
  if (Row < 0) or (Row >= Editor.Lines.Count) then Exit;
  T := Editor.Lines[Row];
  C := 1;
  while (C <= Length(T)) and (T[C] = ' ') do Inc(C);
  FBusy := True;
  try
    if Row + 1 > 4 then Editor.TopLine := Row + 1 - 3 else Editor.TopLine := 1;
    Editor.CaretXY := Point(C, Row + 1);
    Editor.BlockBegin := Editor.CaretXY;
    Editor.BlockEnd := Editor.CaretXY;
  finally
    FBusy := False;
  end;
  Editor.EnsureCursorPosVisible;
  Editor.SetFocus;
end;

procedure TSourceForm.btnPickClick(Sender: TObject);
begin
  FPicking := not FPicking;
  FPickLine := -1;
  btnPick.Caption := IfThen(FPicking, 'Picking', 'Pick');
  if FPicking then
    lblApply.Caption := 'Click points on the sheet: they are typed in at the caret.  Esc there, or Picking here, stops.';
  if Assigned(OnPick) then OnPick(FPicking);
end;

procedure TSourceForm.PickEnded;
begin
  FPicking := False;
  btnPick.Caption := 'Pick';
end;

{ The <part> to fill: the one the caret is in, else the first on the line.
  A and B are its "<" and ">" positions, or 0. }
procedure TSourceForm.PartToFill(const L: string; out A, B: Integer);
var
  X, P, Q: Integer;
begin
  A := 0; B := 0;
  X := Editor.CaretX;
  P := Pos('<', L);
  while P > 0 do
  begin
    Q := PosEx('>', L, P + 1);
    if Q = 0 then Break;
    if (X > P) and (X <= Q + 1) then begin A := P; B := Q; Exit; end;
    if A = 0 then begin A := P; B := Q; end;
    P := PosEx('<', L, Q + 1);
  end;
end;

function TSourceForm.PickWants: string;
var
  Y, A, B: Integer;
  L: string;
begin
  Result := 'the line';
  Y := Editor.CaretY - 1;
  if (Y < 0) or (Y >= Editor.Lines.Count) then Exit;
  L := Editor.Lines[Y];
  PartToFill(L, A, B);
  if A > 0 then Result := Copy(L, A, B - A + 1);
end;

procedure TSourceForm.TakePoint(const P: TP3; U: TUnitSystem);
var
  Y, A, B: Integer;
  L, T, Key, Add, Slot: string;
  HasPlace: Boolean;
begin
  Y := Editor.CaretY - 1;
  if (Y < 0) or (Y >= Editor.Lines.Count) then Exit;
  L := Editor.Lines[Y];
  T := LowerCase(Trim(L));
  { Fill a <part> left by the word list: the one the caret is in, else the
    first on the line.  Its name says how: a place, a step from the first
    place, or a radius. }
  PartToFill(L, A, B);
  if (A > 0) and (B > A) then
  begin
    Slot := LowerCase(Copy(L, A + 1, B - A - 1));
    if Y <> FPickLine then FPickLine := -1;
    if (Slot = 'size') or (Slot = 'by') or (Slot = 'step') then
    begin
      if FPickLine = Y then
        Add := Place2(P3(P.X - FPickFirst.X, P.Y - FPickFirst.Y, P.Z - FPickFirst.Z), U, True)
      else Add := Place2(P, U, True);
    end
    else if Slot = 'radius' then
    begin
      if FPickLine = Y then
        Add := Len2(Sqrt(Sqr(P.X - FPickFirst.X) + Sqr(P.Y - FPickFirst.Y) + Sqr(P.Z - FPickFirst.Z)), U)
      else Add := Len2(1, U);
    end
    else
    begin
      Add := Place2(P, U, False);
      if FPickLine <> Y then
      begin
        FPickFirst := P;
        FPickLine := Y;
      end;
    end;
    { through the editor's own edit, so undo and the edited state follow }
    Editor.BeginUpdate(False);
    Editor.BlockBegin := Point(A, Y + 1);
    Editor.BlockEnd := Point(B + 1, Y + 1);
    Editor.SelText := Add;
    Editor.EndUpdate;
    Exit;
  end;
  Key := Copy(T, 1, Pos(' ', T + ' ') - 1);
  if Pos('=', Key) > 0 then Key := Copy(Key, 1, Pos('=', Key) - 1);
  if Y <> FPickLine then FPickLine := -1;
  HasPlace := (FPickLine = Y) or (Pos(' east', T) > 0) or (Pos(' west', T) > 0) or
              (Pos(' north', T) > 0) or (Pos(' south', T) > 0);
  if not HasPlace then
  begin
    Add := Place2(P, U, False);
    FPickFirst := P;
    FPickLine := Y;
  end
  else if (Key = 'line') or (Key = 'guide') then
  begin
    if Pos(' to ', T) > 0 then Add := ' ' + Place2(P, U, False)
    else Add := ' to ' + Place2(P, U, False);
  end
  else if (Key = 'box') or (Key = 'rect') or (Key = 'pull') or (Key = 'size') or (Key = 'by') then
  begin
    if (Pos(';', T) > 0) or (FPickLine <> Y) then Add := ' ' + Place2(P, U, False)
    else Add := '; ' + Place2(P3(P.X - FPickFirst.X, P.Y - FPickFirst.Y, P.Z - FPickFirst.Z), U, True);
  end
  else if Key = 'circle' then
  begin
    if (Pos(';', T) > 0) or (FPickLine <> Y) then Add := ' ' + Place2(P, U, False)
    else Add := '; ' + Len2(Sqrt(Sqr(P.X - FPickFirst.X) + Sqr(P.Y - FPickFirst.Y) + Sqr(P.Z - FPickFirst.Z)), U);
  end
  else Add := ' ' + Place2(P, U, False);
  { Appended at the end of the line, with a space unless the line already
    ends in one or in "= ". }
  if (L <> '') and (L[Length(L)] <> ' ') and (Add <> '') and (Add[1] <> ' ') and
     (Add[1] <> ';') then Add := ' ' + Add;
  Editor.CaretX := Length(L) + 1;
  Editor.InsertTextAtCaret(Add);
end;

procedure TSourceForm.miRunJigClick(Sender: TObject);
begin
  { this jig, not all of them }
  RunJigAt(Editor.CaretY - 1);
end;

procedure TSourceForm.pmEditorPopup(Sender: TObject);
var
  R: Integer;
  T: string;
begin
  R := Editor.CaretY - 1;
  T := '';
  if (R >= 0) and (R < Editor.Lines.Count) then T := LowerCase(Trim(Editor.Lines[R]));
  miCenter.Enabled := (not FEdited) and (R >= 0) and (T <> '') and (T <> 'end');
  miGoTo.Enabled := DefinedAt(Editor.GetWordAtRowCol(Editor.CaretXY), R) >= 0;
  miRunJig.Visible := Copy(T, 1, 3) = 'jig';
end;

procedure TSourceForm.chkOnlyPickedChange(Sender: TObject);
begin
  ShowPicked(True);
end;

procedure TSourceForm.chkOnTopChange(Sender: TObject);
begin
  if chkOnTop.Checked then FormStyle := fsSystemStayOnTop
  else FormStyle := fsNormal;
end;

{ Buttons and boxes in the program's theme, as in every dialog.  UseDark
  then dresses the window, bars and page to match the page. }
procedure TSourceForm.ThemeChrome;
begin
  hsDialogSkin.ThemeForm(Self);
end;

procedure TSourceForm.UseDark(Dark: Boolean; Back, Fore: TColor);
var
  I: Integer;
begin
  FDark := Dark;
  FColors.UseDark(Dark);
  Editor.Color := Back;
  Editor.Font.Color := Fore;
  { Dress every gutter part (numbers, fold marks, separator); each keeps
    its own colors, and a white one is unreadable on a dark page. }
  Editor.Gutter.Color := Back;
  for I := 0 to Editor.Gutter.Parts.Count - 1 do
  begin
    Editor.Gutter.Parts[I].MarkupInfo.Background := Back;
    if Dark then Editor.Gutter.Parts[I].MarkupInfo.Foreground := TColor($A0A0A0)
    else Editor.Gutter.Parts[I].MarkupInfo.Foreground := TColor($606060);
  end;
  Editor.FoldedCodeColor.Foreground := TColor($A0A0A0);
  Editor.FoldedCodeColor.FrameColor := TColor($A0A0A0);
  if Dark then
  begin
    Editor.RightGutter.Color := Back;
    FPickBG := TColor($604020);
    FPickFG := TColor($FFF0E0);
    Editor.SelectedColor.Background := TColor($806040);
    Editor.SelectedColor.Foreground := clWhite;
    { the caret's line a shade lighter, so the eye finds it after a jump }
    Editor.LineHighlightColor.Background := TColor($3A3430);
    Editor.BracketMatchColor.FrameColor := TColor($F0C070);
    (Editor.MarkupByClass[TSynEditMarkupWordGroup] as TSynEditMarkupWordGroup).MarkupInfo.FrameColor := TColor($F0C070);
    (Editor.MarkupByClass[TSynEditMarkupHighlightAllCaret] as TSynEditMarkupHighlightAllCaret).MarkupInfo.FrameColor := TColor($E0A060);
    pnlApply.Color := TColor($405060);
    lblApply.Font.Color := Fore;
  end
  else
  begin
    FPickBG := PICKED_BG;
    FPickFG := PICKED_FG;
    Editor.SelectedColor.Background := clHighlight;
    Editor.SelectedColor.Foreground := clHighlightText;
    Editor.LineHighlightColor.Background := TColor($F4EEE6);
    Editor.BracketMatchColor.FrameColor := clNone;
    (Editor.MarkupByClass[TSynEditMarkupWordGroup] as TSynEditMarkupWordGroup).MarkupInfo.FrameColor := TColor($2060C0);
    (Editor.MarkupByClass[TSynEditMarkupHighlightAllCaret] as TSynEditMarkupHighlightAllCaret).MarkupInfo.FrameColor := TColor($C08040);
    pnlApply.Color := TColor($CCFFFF);
    lblApply.Font.Color := clBlack;
  end;
  Color := Back;
  pnlTop.Color := Back;
  if FComplete <> nil then FComplete.UseDark(Dark, Back, Fore);
  { The buttons and find box use the dialog theme (ThemeChrome); the labels
    beside them follow the page. }
  for I := 0 to pnlTop.ControlCount - 1 do
    if not (pnlTop.Controls[I] is TBCButton) and not (pnlTop.Controls[I] is TEdit) then
      pnlTop.Controls[I].Font.Color := Fore;
  Status.Color := Back;
  Status.Font.Color := Fore;
  Font.Color := Fore;
  Editor.Invalidate;
end;

end.

unit hsExport;

{ The export dialog: formats down the left, a live preview in the middle you
  can turn and zoom to frame the shot, and the format's settings on the right.
  What the preview shows is what comes out, at the size asked for.  It also
  plays back a recorded camera move as an animated WebP.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, Graphics, Controls, Forms, StdCtrls,
  ExtCtrls, ComCtrls, Dialogs, LCLType,
  BCButton, BCPanel, BCLabel,
  hsPdf, hsSurface, hsDrawing, hsSkin, hsDialogSkin, hsFilm, hsRecorder, BCComboBox, BCFluentSlider, BGRATheme, BGRAThemeCheckBox;

type
  TExportKind = (exPng, exJpeg, exWebP, exSvg, exDxfView, exDxfModel, exStl,
    exScad, exPdf);

type
  { The main window sends bug reports, since a report needs a screenshot and
    the whole program state. }
  TReportProc = procedure(const Where, Fields: string) of object;

{ Returns True if something was written; Msg gets a line about it either way. }
{ Where this kind of file went last time, and where to record it this time.
  The program remembers per kind, since people keep STLs in one place and
  pictures in another. }
type
  TDirFor = function(const Ext: string): string of object;
  TDirKeep = procedure(const Ext, Dir: string) of object;

function RunExport(Doc: TWorkDoc; const V: TProjector; U: TUnitSystem;
  AFont: TFont; const LabelCol: TPix; EdgeW: Single; SrcW, SrcH: Integer;
  const Suggest: string; const T: TTheme; const Pivot: TP3;
  OnReport: TReportProc; DirFor: TDirFor; DirKeep: TDirKeep;
  out Msg: string; out ShowHoles: Boolean; PrintScale: Integer = 2): Boolean;

implementation

{$R *.lfm}

{ ------------------------------------------------------------------------ }

type
  TExportDlg = class(TForm)
    { the title bar - the dialog draws its own; see FormCreate }
    pnlHead: TBCPanel;
    lblTitle: TBCLabel;
    btnShut: TBCButton;
    { the formats, down the left }
    pnlRail: TBCPanel;
    btnPng: TBCButton;
    btnJpeg: TBCButton;
    btnWebP: TBCButton;
    { a gap above this one: pictures above it, drawings below }
    btnSvg: TBCButton;
    btnDxfView: TBCButton;
    btnDxfModel: TBCButton;
    btnStl: TBCButton;
    btnScad: TBCButton;
    btnPdf: TBCButton;
    { the model, in the middle }
    pnlMid: TBCPanel;
    pbPrev: TPaintBox;
    lblHint: TLabel;
    { the format's settings, on the right }
    pnlOpt: TBCPanel;
    lblOptTitle: TBCLabel;
    { A wrapping label rather than a caption: the drawn label centers one line
      and clips both ends of a long sentence. }
    lblNote: TLabel;
    lblSize: TBCLabel;
    cbSize: TBCComboBox;
    edW: TEdit;
    lblBy: TBCLabel;
    edH: TEdit;
    cbPaper: TBCComboBox;
    cbOrientation: TBCComboBox;
    cbScale: TBCComboBox;
    cbTransp: TBGRAThemeCheckBox;
    lblQual: TBCLabel;
    tbQual: TBCFluentSlider;
    cbLoop: TBGRAThemeCheckBox;
    cbBounce: TBGRAThemeCheckBox;
    { How long the film runs, which sets its speed. }
    cbSecs: TBCComboBox;
    btnRec: TBCButton;
    { two lines, so the note about a closing clip is never cut off }
    lblClip: TLabel;
    btnPlay: TBCButton;
    cbMid: TBGRAThemeCheckBox;
    cbAxes: TBGRAThemeCheckBox;
    lblShot: TLabel;
    cbDxfWhat: TBCComboBox;
    { where it goes }
    pnlFoot: TBCPanel;
    lblSave: TBCLabel;
    edPath: TEdit;
    lblTellBad: TLabel;
    btnSay: TBCButton;
    btnBrowse: TBCButton;
    btnCancel: TBCButton;
    btnGo: TBCButton;
    { Export progress.  The bar takes the path's place, since the path is
      settled while an export runs. }
    pbBar: TPaintBox;
    tmrPlay: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure PickKind(Sender: TObject);
    procedure PrevPaint(Sender: TObject);
    procedure PrevDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PrevMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PrevUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PrevWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure Tick(Sender: TObject);
    procedure DoPlay(Sender: TObject);
    procedure DoRecord(Sender: TObject);
    procedure HeadDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure HeadMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure HeadUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure BarPaint(Sender: TObject);
    procedure DoSay(Sender: TObject);
    procedure DoCancel(Sender: TObject);
    procedure AskClose(Sender: TObject; var CanClose: Boolean);
    procedure DoBrowse(Sender: TObject);
    procedure DoGo(Sender: TObject);
    procedure SizeChanged(Sender: TObject);
    procedure Ticked(Sender: TObject);
  private
    FDoc: TWorkDoc;
    FUnits: TUnitSystem;
    FFont: TFont;
    FLabelCol: TPix;
    FEdgeW: Single;
    FSrcW, FSrcH: Integer;
    FKind: TExportKind;
    FWrote: Boolean;
    FMsg: string;
    { The step the export was on when it failed, for the error message; an
      access violation alone does not say where it died. }
    FStage: string;
    FOnReport: TReportProc;
    { True when the export was not a closed solid.  The dialog is gone by the
      time the message is read, so the drawing behind it shows the problem. }
    FOpenSolid: Boolean;
    { the name to offer, without folder or extension, and the hooks that know
      where each kind of file belongs }
    FStem: string;
    FDirFor: TDirFor;
    FDirKeep: TDirKeep;

    { the camera in the preview }
    FView: TProjector;
    FPivot: TP3;
    FDragging, FPanning: Boolean;
    FDragX, FDragY: Integer;
    FPlaying: Boolean;
    FPlayT: Double;

    { the format buttons, indexed by format for PickKind and ShowOptions }
    FKindBtn: array[TExportKind] of TBCButton;
    FHeadDrag: hsDialogSkin.TFormDrag;
    FCam: TCamPath;
    FPrevS: TArtSurface;
    FBusy: Boolean;
    FDone, FTotal: Integer;
    FDoing: string;

    function PdfDenominator: Double;
    function PdfPreviewView: TProjector;
    function FilmSeconds: Double;
    procedure ShowOptions;
    procedure FilmSays(const S: string);
    procedure FilmStep(Done, Total: Integer; const What: string);
    procedure Working(On_: Boolean);
    function Ext: string;
    { The full path to offer: the folder this kind went to last time, plus the
      name in the box now. }
    function PathFor(K: TExportKind): string;
    function Weigh(Frames, W, H: Integer): string;
    function OutSize(out W, H: Integer): Boolean;
    function Tween(T: Double): TProjector;
    procedure WriteIt;
  public
    { what is being exported and where things go, set after the form is made }
    procedure Setup(Doc: TWorkDoc; const V: TProjector; U: TUnitSystem;
      AFont: TFont; const LabelCol: TPix; EdgeW: Single;
      SrcW, SrcH: Integer; const Suggest: string; DirFor: TDirFor; DirKeep: TDirKeep);
  end;

type
  TSizePick = record
    Name: string;
    W, H: Integer;      { 0,0 means work it out from the screen }
    Mul: Double;        { used when W and H are 0 }
  end;

const
  { Common picture sizes, offered so nobody has to type 1080 x 1920. }
  SIZES: array[0..10] of TSizePick = (
    (Name: 'As it is on screen';            W: 0;    H: 0;    Mul: 1),
    (Name: 'Twice the size';                W: 0;    H: 0;    Mul: 2),
    (Name: 'Four times the size';           W: 0;    H: 0;    Mul: 4),
    (Name: 'Square - 1080 x 1080';          W: 1080; H: 1080; Mul: 0),
    (Name: 'Tall - 1080 x 1920';            W: 1080; H: 1920; Mul: 0),
    (Name: 'Wide - 1200 x 675';             W: 1200; H: 675;  Mul: 0),
    (Name: 'Link card - 1200 x 630';        W: 1200; H: 630;  Mul: 0),
    (Name: '720p - 1280 x 720';             W: 1280; H: 720;  Mul: 0),
    (Name: '1080p - 1920 x 1080';           W: 1920; H: 1080; Mul: 0),
    (Name: 'Small, for an email - 800 x 600'; W: 800; H: 600; Mul: 0),
    (Name: 'A size of my own';              W: -1;   H: -1;   Mul: 0));
  SIZE_MINE = 10;

  KIND_NAME: array[TExportKind] of string =
    ('PNG', 'JPEG', 'WebP', 'SVG', 'DXF view', 'DXF model', 'STL',
     'OpenSCAD', 'PDF');
  KIND_EXT: array[TExportKind] of string =
    ('.png', '.jpg', '.webp', '.svg', '.dxf', '.dxf', '.stl',
     '.scad', '.pdf');
  KIND_BLURB: array[TExportKind] of string =
    ('A picture, with the paper behind it or nothing at all.',
     'A picture, smaller and slightly softened.  No transparency.',
     'A little film of a move you record yourself - lossless, every line ' +
     'as sharp as it is on screen.',
     'The lines of this view, as vectors, for a drawing program.',
     'This view, flat, as entities somebody can measure in their own CAD.',
     'The model itself, in three dimensions, faces and all.',
     'Triangles in millimeters, which is what a 3D printer wants.',
     'A polyhedron per solid, to cut and union in OpenSCAD.',
     'Paper, orientation, then print scale. Vector geometry; 10 mm margins and a scale bar. Print at 100%.');

{ ------------------------------------------------------------------------ }

{ No stock frame: the dialog draws its own title bar and handles dragging.
  The layout is the form's; this sets the theme and fills the table-driven lists. }
procedure TExportDlg.FormCreate(Sender: TObject);
var
  I: Integer;
  Field: TColor;
begin
  hsDialogSkin.ThemeForm(Self);
  { the head runs edge to edge; the four panels under it are rounded }
  hsDialogSkin.SkinPanel(pnlHead, True, 0);
  hsDialogSkin.SkinPanel(pnlRail, False, 12);
  hsDialogSkin.SkinPanel(pnlMid, False, 12);
  hsDialogSkin.SkinPanel(pnlOpt, False, 12);
  hsDialogSkin.SkinPanel(pnlFoot, False, 12);

  FKindBtn[exPng] := btnPng;
  FKindBtn[exJpeg] := btnJpeg;
  FKindBtn[exWebP] := btnWebP;
  FKindBtn[exSvg] := btnSvg;
  FKindBtn[exDxfView] := btnDxfView;
  FKindBtn[exDxfModel] := btnDxfModel;
  FKindBtn[exStl] := btnStl;
  FKindBtn[exScad] := btnScad;
  FKindBtn[exPdf] := btnPdf;

  for I := 0 to High(SIZES) do cbSize.Items.Add(SIZES[I].Name);
  cbSize.ItemIndex := 0;
  for I := Low(PDF_SHEETS) to High(PDF_SHEETS) do
    cbPaper.Items.Add(PDF_SHEETS[I].Name);
  cbPaper.ItemIndex := 0;

  { The film is whatever was recorded.  A move that does not end where it
    began would jump at each loop, so Bounce walks it back to the start within
    the same running time.  A move that already closes does not get the tick. }
  FKind := exPng;
end;

procedure TExportDlg.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FPrevS);
end;

procedure TExportDlg.Setup(Doc: TWorkDoc; const V: TProjector;
  U: TUnitSystem; AFont: TFont; const LabelCol: TPix; EdgeW: Single;
  SrcW, SrcH: Integer; const Suggest: string;
  DirFor: TDirFor; DirKeep: TDirKeep);
var
  I: Integer;
begin
  FDoc := Doc;
  FUnits := U;
  FFont := AFont;
  FLabelCol := LabelCol;
  FEdgeW := EdgeW;
  FSrcW := SrcW;
  FSrcH := SrcH;
  FView := V;
  FKind := exPng;
  FWrote := False;
  FStem := Suggest;
  FDirFor := DirFor;
  FDirKeep := DirKeep;

  { the print scales depend on the drawing's units, so they wait for them }
  cbScale.Items.Clear;
  for I := 0 to SCALE_COUNT - 1 do
    if FUnits = usImperial then
      cbScale.Items.Add(ScaleTable(FUnits, I).Name + ' = 1 foot')
    else cbScale.Items.Add(ScaleTable(FUnits, I).Name);
  cbScale.Items.Add('1:1');
  cbScale.Items.Add('1:2');
  cbScale.Items.Add('1:5');
  cbScale.Items.Add('1:25');
  cbScale.Items.Add('1:250');
  cbScale.Items.Add('1:500');
  cbScale.Items.Add('1:1000');
  cbScale.Items.Add('1:240 (1 inch = 20 feet)');
  cbScale.Items.Add('1:360 (1 inch = 30 feet)');
  cbScale.Items.Add('1:480 (1 inch = 40 feet)');
  cbScale.Items.Add('1:600 (1 inch = 50 feet)');
  cbScale.Items.Add('1:1200 (1 inch = 100 feet)');
  cbScale.ItemIndex := 2;

  edPath.Text := PathFor(FKind);
  ShowOptions;
end;

{ Export progress, drawn as it goes.  A twelve-second film is three
  hundred renders, and a window that stops answering that long gets force-quit. }
procedure TExportDlg.BarPaint(Sender: TObject);
var
  C: TCanvas;
  T: TTheme;
  W, Y: Integer;
begin
  C := pbBar.Canvas;
  T := hsDialogSkin.DlgTheme;
  C.Brush.Color := hsSurface.PixToColor(T.Panel);
  C.Brush.Style := bsSolid;
  C.FillRect(0, 0, pbBar.Width, pbBar.Height);

  Y := 30;
  C.Brush.Color := hsDialogSkin.Shade(hsSurface.PixToColor(T.Panel), -0.30);
  C.FillRect(0, Y, pbBar.Width, Y + 10);
  if FTotal > 0 then
  begin
    W := Round(pbBar.Width * EnsureRange(FDone / FTotal, 0, 1));
    C.Brush.Color := hsSurface.PixToColor(T.Accent);
    C.FillRect(0, Y, W, Y + 10);
  end;
  C.Brush.Style := bsClear;

  C.Font.Height := -13;
  C.Font.Style := [];
  C.Font.Color := hsSurface.PixToColor(T.Text);
  C.TextOut(0, 6, FDoing);
end;

{ Everything that says an export is running: the cursor, the bar, and
  disabling the buttons that must not be pressed twice. }
procedure TExportDlg.Working(On_: Boolean);
begin
  FBusy := On_;
  pbBar.Visible := On_;
  edPath.Visible := not On_;
  lblSave.Visible := not On_;
  btnBrowse.Enabled := not On_;
  btnGo.Enabled := not On_;
  { Cancel and the close button too.  The message queue drains between
    frames, so a click can arrive mid-export, and closing the window under the
    code writing the file is a crash. }
  btnCancel.Enabled := not On_;
  btnShut.Enabled := not On_;
  if On_ then Screen.Cursor := crHourGlass else Screen.Cursor := crDefault;
  if On_ then
  begin
    FDone := 0;
    FTotal := 0;
    FDoing := 'Working...';
  end;
  pbBar.Invalidate;
  Application.ProcessMessages;
end;

procedure TExportDlg.FilmStep(Done, Total: Integer; const What: string);
begin
  FDone := Done;
  FTotal := Total;
  FDoing := What;
  pbBar.Invalidate;
  { Let it paint: the export runs on the window's thread, so draining the
    queue between frames is what keeps the bar moving. }
  Application.ProcessMessages;
end;

{ Windows paints a themed combo box itself and ignores Font.Color, so on a
  dark dialog the text comes out black on near-black.  Draw the rows ourselves. }
procedure TExportDlg.PickKind(Sender: TObject);
var
  K: TExportKind;
begin
  for K := Low(TExportKind) to High(TExportKind) do
    if FKindBtn[K] = Sender then FKind := K;
  { The name carries over, the folder does not: an STL goes where the last
    STL went, not where the last PNG went. }
  edPath.Text := PathFor(FKind);
  ShowOptions;
end;

{ How long the film should run: what was recorded, or what was asked for
  instead.  Zero when there is no clip. }
function TExportDlg.FilmSeconds: Double;
begin
  Result := CamPathLength(FCam);
  case cbSecs.ItemIndex of
    1: Result := 3;
    2: Result := 5;
    3: Result := 8;
    4: Result := 12;
  end;
  if Length(FCam) < 2 then Result := 0;
end;

procedure TExportDlg.ShowOptions;
var
  K: TExportKind;
  Raster, Anim: Boolean;
  W, H, NF, Rate: Integer;
  Secs, PW, PH, Fit: Double;
begin
  for K := Low(TExportKind) to High(TExportKind) do
    if K = FKind then hsDialogSkin.SkinButton(FKindBtn[K], bkGo)
    else hsDialogSkin.SkinButton(FKindBtn[K], bkPlain);

  lblOptTitle.Caption := KIND_NAME[FKind];
  lblNote.Caption := KIND_BLURB[FKind];

  Raster := FKind in [exPng, exJpeg, exWebP];
  cbPaper.Visible := FKind = exPdf;
  cbOrientation.Visible := FKind = exPdf;
  cbScale.Visible := FKind = exPdf;
  if FKind = exPdf then
    lblHint.Caption := 'Drawing area at the selected print scale. Right-drag to frame; middle-drag to turn. Use PLAN for measured plans.'
  else
    lblHint.Caption := 'Middle-drag turns it, right-drag slides it, wheel zooms - the same as the drawing.';
  Anim := FKind = exWebP;

  lblSize.Visible := Raster or (FKind = exPdf);
  if FKind = exPdf then lblSize.Caption := 'Paper / orientation / scale'
  else lblSize.Caption := 'Size';
  cbSize.Visible := Raster;
  edW.Visible := Raster and (cbSize.ItemIndex = SIZE_MINE);
  edH.Visible := edW.Visible;
  lblBy.Visible := edW.Visible;
  cbTransp.Visible := FKind = exPng;
  lblQual.Visible := FKind = exJpeg;
  tbQual.Visible := FKind = exJpeg;

  cbLoop.Visible := Anim;
  cbSecs.Visible := Anim and (Length(FCam) >= 2);
  { bounce only matters for a clip that does not already close }
  cbBounce.Visible := Anim and (Length(FCam) >= 2) and not CamPathCloses(FCam);
  btnPlay.Visible := Anim and (Length(FCam) >= 2);
  lblShot.Visible := Raster;
  if Anim then
  begin
    if Length(FCam) < 2 then
      lblClip.Caption := 'Nothing recorded yet.'
    else if CamPathCloses(FCam) then
      lblClip.Caption := Format('%.1f seconds, ending where it began.',
        [CamPathLength(FCam)])
    else
      lblClip.Caption := Format('%.1f seconds recorded.',
        [CamPathLength(FCam)]);
  end;
  lblClip.Visible := Anim;
  cbAxes.Visible := Raster or (FKind = exPdf);
  if FKind = exPdf then cbAxes.Top := 224 else cbAxes.Top := 180;
  btnRec.Visible := Anim;
  cbDxfWhat.Visible := FKind in [exDxfView, exDxfModel];
  { The origin matters to anything importing the model (a slicer, a CAD
    program, a Revit family), so offer the tick for every whole-model format. }
  cbMid.Visible := (FKind in [exStl, exScad]) or
                  ((FKind = exDxfModel) and (cbDxfWhat.ItemIndex = 1));

  if not Anim then
  begin
    FPlaying := False;
    tmrPlay.Enabled := False;
    btnPlay.Caption := 'Play it';
  end;

  { show what the settings will come to }
  if Raster and OutSize(W, H) then
  begin
    if Anim then
    begin
      if Length(FCam) >= 2 then
        Secs := Max(0.2, Min(FILM_MAX_SECONDS, FilmSeconds))
      else
        Secs := 0;
      FilmPlan(Secs, FILM_FPS, W, H, NF, Rate);
      { A big picture gets fewer frames, since the whole film is held in memory
        at once.  Say so here instead of letting it come out jerky. }
      { estimate the file size so nobody has to export to find out }
      if Secs <= 0 then
        lblShot.Caption := Format('%d x %d - record a move first', [W, H])
      else if Rate < FILM_FPS then
        lblShot.Caption := Format('%d x %d, %.1fs at %d a second, about %s' +
          '  (a smaller size buys more frames)',
          [W, H, Secs, Rate, Weigh(NF, W, H)])
      else
        lblShot.Caption := Format('%d x %d, %.1fs, %d frames, about %s',
          [W, H, Secs, NF, Weigh(NF, W, H)]);
    end
    else
      lblShot.Caption := Format('%d x %d pixels', [W, H]);
  end
  else if Raster then
    lblShot.Caption := 'that size will not do';

  if FKind = exPdf then
  begin
    PdfSheetSize(cbPaper.ItemIndex, cbOrientation.ItemIndex = 1, PW, PH);
    PW := PW - 2 * PDF_MARGIN;
    PH := PH - 2 * PDF_MARGIN - PDF_FOOTER;
    Fit := Min(420 / PW, 396 / PH);
    pbPrev.SetBounds(10 + Round((420 - PW * Fit) / 2),
      10 + Round((396 - PH * Fit) / 2), Round(PW * Fit), Round(PH * Fit));
  end
  else pbPrev.SetBounds(10, 10, 420, 396);
  pbPrev.Invalidate;
end;

{ Shared by the ticks and the length combo, which only needs the options
  and the preview updated. }
procedure TExportDlg.Ticked(Sender: TObject);
begin
  pbPrev.Invalidate;
  ShowOptions;
end;

procedure TExportDlg.SizeChanged(Sender: TObject);
begin
  if Sender = tbQual then
    lblQual.Caption := Format('Quality %d', [tbQual.Value]);
  ShowOptions;
end;

function TExportDlg.OutSize(out W, H: Integer): Boolean;
var
  I: Integer;
  K: Double;
begin
  I := cbSize.ItemIndex;
  if (I < 0) or (I > High(SIZES)) then I := 0;
  if I = SIZE_MINE then
  begin
    W := StrToIntDef(edW.Text, 0);
    H := StrToIntDef(edH.Text, 0);
  end
  else if SIZES[I].W > 0 then
  begin
    W := SIZES[I].W;
    H := SIZES[I].H;
  end
  else
  begin
    W := Round(FSrcW * SIZES[I].Mul);
    H := Round(FSrcH * SIZES[I].Mul);
  end;

  { Shrink an oversized request to fit instead of refusing it; the size
    buttons can offer sizes past the limit. }
  if (W > 8000) or (H > 8000) then
  begin
    K := Min(8000 / Max(1, W), 8000 / Max(1, H));
    W := Max(16, Round(W * K));
    H := Max(16, Round(H * K));
  end;
  Result := (W >= 16) and (H >= 16);
end;

{ Rough file size of the film, from a rate measured on a busy drawing.
  Rough is enough: what matters is "fine" versus "too big to send". }
function TExportDlg.Weigh(Frames, W, H: Integer): string;
var
  B: Double;
begin
  B := Frames * Double(W) * H * FILM_BYTES_PER_PIXEL;
  if B >= 1024 * 1024 then Result := Format('%.1f MB', [B / 1024 / 1024])
  else Result := Format('%.0f KB', [B / 1024]);
end;

function TExportDlg.Ext: string;
begin
  Result := KIND_EXT[FKind];
end;

function TExportDlg.PathFor(K: TExportKind): string;
var
  Dir, Name_: string;
begin
  Name_ := '';
  if Assigned(edPath) then
    Name_ := ExtractFileName(Trim(edPath.Text));
  if Name_ = '' then Name_ := FStem;
  Name_ := ChangeFileExt(Name_, '');
  if Name_ = '' then Name_ := FStem;

  Dir := '';
  if Assigned(FDirFor) then Dir := FDirFor(KIND_EXT[K]);
  if Dir = '' then Result := Name_ + KIND_EXT[K]
  else Result := IncludeTrailingPathDelimiter(Dir) + Name_ + KIND_EXT[K];
end;

{ Where the camera is, T seconds into the recording. }
function TExportDlg.Tween(T: Double): TProjector;
begin
  Result := SampleCamPath(FCam, T);
end;

function TExportDlg.PdfDenominator: Double;
const
  Extra: array[0..11] of Double = (1, 2, 5, 25, 250, 500, 1000,
    240, 360, 480, 600, 1200);
begin
  if cbScale.ItemIndex >= SCALE_COUNT then
    Exit(Extra[cbScale.ItemIndex - SCALE_COUNT]);
  Result := ScaleTable(FUnits, cbScale.ItemIndex).Paper;
  if FUnits = usImperial then Result := 12 / Result
  else Result := 1 / Result;
end;

function TExportDlg.PdfPreviewView: TProjector;
var
  PW, PH, MMUnit: Double;
begin
  PdfSheetSize(cbPaper.ItemIndex, cbOrientation.ItemIndex = 1, PW, PH);
  if FUnits = usImperial then MMUnit := 304.8 else MMUnit := 1000;
  Result := FView;
  Result.Ppu := MMUnit / PdfDenominator * pbPrev.Width / (PW - 2 * PDF_MARGIN);
  Result.OX := pbPrev.Width / 2 + (FView.OX - FSrcW / 2) * Result.Ppu / FView.Ppu;
  Result.OY := pbPrev.Height / 2 + (FView.OY - FSrcH / 2) * Result.Ppu / FView.Ppu;
end;

procedure TExportDlg.PrevPaint(Sender: TObject);
var
  S: TArtSurface;
  V: TProjector;
  Bg: TPix;
begin
  { With nothing recorded the preview just holds the shot still; it never
    wanders around the model on its own. }
  if FPlaying and (Length(FCam) >= 2) then V := Tween(FPlayT) else V := FView;
  if (FKind = exPng) and cbTransp.Checked then Bg := Pix(255, 255, 255, 0)
  else Bg := Pix(255, 255, 255);
  { Keep one surface instead of making a new one every repaint; during
    playback this runs 25 times a second. }
  if (FPrevS <> nil) and ((FPrevS.Width <> pbPrev.Width) or
     (FPrevS.Height <> pbPrev.Height)) then FreeAndNil(FPrevS);
  if FPrevS = nil then
    FPrevS := TArtSurface.Create(Max(1, pbPrev.Width), Max(1, pbPrev.Height));
  S := FPrevS;
  if FKind = exPdf then V := PdfPreviewView
  else V := Fitted(V, FSrcW, FSrcH, pbPrev.Width, pbPrev.Height);
  ShootInto(S, FDoc, V,
    FUnits, FFont, FLabelCol, FEdgeW, Bg, FDragging or FPlaying, cbAxes.Checked);
  pbPrev.Canvas.Draw(0, 0, S.AsBitmap);
end;

{ Same mouse buttons as the drawing area: middle turns, right slides, and
  left does nothing since there is nothing to pick. }
procedure TExportDlg.PrevDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FDragging := Button in [mbMiddle, mbRight];
  FPanning := Button = mbRight;
  FDragX := X;
  FDragY := Y;
end;

procedure TExportDlg.PrevMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  K: Double;
begin
  if not FDragging then Exit;
  { Test Shift on every move, not only on button down, so you can switch from
    turning to sliding mid-drag, as in the drawing area. }
  K := ViewScale(FSrcW, FSrcH, pbPrev.Width, pbPrev.Height);
  if FKind = exPdf then K := PdfPreviewView.Ppu / FView.Ppu;
  if FPanning or (ssShift in Shift) then
    { The preview and the shot differ in size, so a slide measured here goes
      back through the same single fitting scale Fitted uses, or it moves at the
      wrong speed. }
    PanBy(FView, (X - FDragX) / K, (Y - FDragY) / K)
  else
    OrbitBy(FView, X - FDragX, Y - FDragY);
  FDragX := X;
  FDragY := Y;
  FPlaying := False;
  tmrPlay.Enabled := False;
  btnPlay.Caption := 'Play it';
  pbPrev.Invalidate;
end;

procedure TExportDlg.PrevUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FDragging := False;
  FPanning := False;
  pbPrev.Invalidate;         { the sharp one, now the camera has stopped }
end;

procedure TExportDlg.PrevWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  P: TPoint;
  K, AX, AY: Double;
begin
  { 1.15 per notch, anchored on the cursor, as in the drawing area.  MousePos
    is in screen terms, so map it to the preview and through the fitting scale. }
  if FKind = exPdf then
  begin
    Handled := True;
    Exit;
  end;
  P := pbPrev.ScreenToClient(MousePos);
  K := ViewScale(FSrcW, FSrcH, pbPrev.Width, pbPrev.Height);
  AX := FSrcW / 2 + (P.X - pbPrev.Width / 2) / K;
  AY := FSrcH / 2 + (P.Y - pbPrev.Height / 2) / K;
  if WheelDelta > 0 then ZoomAt(FView, 1.15, AX, AY)
  else ZoomAt(FView, 1 / 1.15, AX, AY);
  pbPrev.Invalidate;
  Handled := True;
end;

procedure TExportDlg.Tick(Sender: TObject);
var
  T, Len: Double;
begin
  Len := CamPathLength(FCam);
  if Len <= 0 then
  begin
    FPlaying := False;
    tmrPlay.Enabled := False;
    Exit;
  end;
  { the clock runs in recording seconds, so playback runs at recorded speed }
  T := FPlayT + tmrPlay.Interval / 1000;   { a local first - see OrbitBy }
  FPlayT := T;
  if FPlayT > Len then FPlayT := 0;
  pbPrev.Invalidate;
end;

procedure TExportDlg.DoPlay(Sender: TObject);
begin
  if Length(FCam) < 2 then Exit;
  FPlaying := not FPlaying;
  FPlayT := 0;
  tmrPlay.Enabled := FPlaying;
  if FPlaying then btnPlay.Caption := 'Stop' else btnPlay.Caption := 'Play it';
  pbPrev.Invalidate;
end;

{ The title bar.  Dragging uses hsDialogSkin.DragBegin/DragTo, which anchor
  on the screen; see TFormDrag for why the obvious way skips about. }
procedure TExportDlg.HeadDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then hsDialogSkin.DragBegin(FHeadDrag, Self);
end;

procedure TExportDlg.HeadMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
begin
  hsDialogSkin.DragTo(FHeadDrag, Self);
end;

procedure TExportDlg.HeadUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  hsDialogSkin.DragEnd(FHeadDrag);
end;

{ Hand the export's whole state to the report, so the settings that caused
  a problem arrive with it. }
procedure TExportDlg.FilmSays(const S: string);
begin
  FStage := S;
end;

procedure TExportDlg.DoSay(Sender: TObject);
var
  W, H: Integer;
  Fields: string;
begin
  if not Assigned(FOnReport) then Exit;
  if not OutSize(W, H) then begin W := 0; H := 0; end;
  Fields := Format(
    'export=%s stage=%s' + LineEnding +
    'asked for=%dx%d from a %dx%d screen, size choice %d' + LineEnding +
    'film=%d a second, loop=%s, recorded=%.1fs, axes=%s' + LineEnding +
    'what it said: %s' + LineEnding +
    'path=%s',
    [KIND_NAME[FKind], FStage, W, H, FSrcW, FSrcH, cbSize.ItemIndex,
     FILM_FPS, BoolToStr(cbLoop.Checked, 'yes', 'no'),
     CamPathLength(FCam), BoolToStr(cbAxes.Checked, 'yes', 'no'),
     FMsg, ExtractFileName(edPath.Text)]);
  ModalResult := mrCancel;
  { The report needs a screenshot and this window is in front, so close it
    first; the main window then raises the report. }
  FOnReport('the export dialog', Fields);
end;

{ Nothing closes this window while it is writing a file. }
procedure TExportDlg.AskClose(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := not FBusy;
end;

procedure TExportDlg.DoCancel(Sender: TObject);
begin
  { Belt and braces: the buttons are disabled during an export, and Escape
    does not close it either. }
  if FBusy then Exit;
  ModalResult := mrCancel;
end;

{ A recording replaces the two framed ends as the shot. }
procedure TExportDlg.DoRecord(Sender: TObject);
var
  Got: TCamPath;
begin
  FPlaying := False;
  tmrPlay.Enabled := False;
  btnPlay.Caption := 'Play it';
  Hide;
  try
    if RecordMove(FDoc, FView, FUnits, FFont, FLabelCol, FEdgeW,
         FSrcW, FSrcH, cbAxes.Checked, FPivot, Got) then
    begin
      FCam := Got;
      FPlayT := 0;
      lblHint.Caption := Format('Recorded %.1f seconds.  That is the shot now - ' +
        'press Play it to watch, or Record again to do it over.',
        [CamPathLength(FCam)]);
    end;
  finally
    Show;
  end;
  ShowOptions;
end;

procedure TExportDlg.DoBrowse(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(nil);
  try
    D.Filter := KIND_NAME[FKind] + '|*' + Ext;
    D.DefaultExt := Ext;
    D.FileName := edPath.Text;
    D.InitialDir := ExtractFileDir(edPath.Text);
    if D.Execute then edPath.Text := ChangeFileExt(D.FileName, Ext);
  finally
    D.Free;
  end;
end;

procedure TExportDlg.DoGo(Sender: TObject);
begin
  FPlaying := False;
  tmrPlay.Enabled := False;
  if Trim(edPath.Text) = '' then
  begin
    lblHint.Caption := 'It needs somewhere to go - pick a file below.';
    Exit;
  end;
  FStage := 'starting';
  hsFilm.OnFilmStage := @FilmSays;
  hsFilm.OnFilmStep := @FilmStep;
  Working(True);
  try
    try
      WriteIt;
      FWrote := True;
      { and that is where this kind of file goes from now on }
      if Assigned(FDirKeep) then
        FDirKeep(Ext, ExtractFileDir(ChangeFileExt(Trim(edPath.Text), Ext)));
    except
      on E: Exception do
      begin
        { Include the class name: an access violation's message says nothing useful. }
        FMsg := Format('Could not export - %s while %s%s',
          [E.ClassName, FStage,
           specialize IfThen<string>(E.Message = '', '', ': ' + E.Message)]);
        lblHint.Caption := FMsg;
        lblTellBad.Caption := FMsg;
        lblTellBad.Visible := True;
        btnSay.Visible := Assigned(FOnReport);
      end;
    end;
  finally
    { Clear busy before asking the window to close, since nothing closes it
      while it is working. }
    Working(False);
    hsFilm.OnFilmStage := nil;
    hsFilm.OnFilmStep := nil;
  end;
  if FWrote then ModalResult := mrOk;
end;

procedure TExportDlg.WriteIt;
var
  PW, PH: Double;
  W, H, N, NTri: Integer;
  Fn: string;
  L: TStringList;
  FS: TFileStream;
  Shut: Boolean;
begin
  FStage := 'working out where to put it';
  Fn := ChangeFileExt(Trim(edPath.Text), Ext);
  { A typed or browsed folder may not exist yet, and a portable program's
    own exports folder will not, the first time. }
  if ExtractFileDir(Fn) <> '' then
    ForceDirectories(ExtractFileDir(Fn));
  case FKind of
    exPdf:
      begin
        FStage := 'working out the size';
        PdfSheetSize(cbPaper.ItemIndex, cbOrientation.ItemIndex = 1, PW, PH);
        FStage := 'writing the vector PDF';
        SaveDrawingPDF(FDoc, FView, FSrcW, FSrcH, FUnits, FEdgeW,
          Fn, PW, PH, PdfDenominator, cbAxes.Checked);
        FMsg := Format('Wrote %s - one vector page, scale 1:%g.',
          [ExtractFileName(Fn), PdfDenominator]);
      end;

    exSvg:
      begin
        FStage := 'writing the SVG';
        L := TStringList.Create;
        try
          FDoc.WriteSVG(L, FView, FUnits, FEdgeW);
          L.SaveToFile(Fn);
        finally
          L.Free;
        end;
        FMsg := 'Wrote ' + ExtractFileName(Fn) + '.';
      end;

    exDxfView, exDxfModel:
      begin
        FStage := 'writing the DXF';
        L := TStringList.Create;
        try
          FDoc.WriteDXF(L, FView, FUnits, cbDxfWhat.ItemIndex = 1, cbMid.Checked);
          L.SaveToFile(Fn);
        finally
          L.Free;
        end;
        FMsg := 'Wrote ' + ExtractFileName(Fn) + '.';
      end;

    exScad:
      begin
        FStage := 'writing the OpenSCAD script';
        L := TStringList.Create;
        try
          N := FDoc.WriteSCAD(L, FUnits, NTri, Shut, cbMid.Checked);
          L.SaveToFile(Fn);
        finally
          L.Free;
        end;
        if N = 0 then
          FMsg := 'Nothing to describe - an OpenSCAD shape is made of faces, ' +
            'and this drawing has none.'
        else if not Shut then
        begin
          FOpenSolid := True;
          FMsg := Format('%d triangles in %d %s, in millimeters - but this ' +
            'is not a closed solid, and a printer will not take it.  The ' +
            'edges where it is open are marked in red on the drawing.',
            [N, NTri, specialize IfThen<string>(NTri = 1, 'piece', 'pieces')]);
        end
        else
          FMsg := Format('%d triangles in %d %s, in millimeters.',
            [N, NTri, specialize IfThen<string>(NTri = 1, 'piece', 'pieces')]);
      end;

    exStl:
      begin
        FStage := 'writing the STL';
        FS := TFileStream.Create(Fn, fmCreate);
        try
          NTri := FDoc.WriteSTL(FS, FUnits, Shut, cbMid.Checked);
        finally
          FS.Free;
        end;
        if NTri = 0 then
          FMsg := 'Nothing to print - an STL is made of faces, and this ' +
            'drawing has none.'
        else if not Shut then
        begin
          FOpenSolid := True;
          FMsg := Format('%d triangles, in millimeters - but this is not a ' +
            'closed solid, so a slicer will have to guess at the inside.  ' +
            'The edges where it is open are marked in red on the drawing.',
            [NTri]);
        end
        else
          FMsg := Format('%d triangles, in millimeters, closed and ready to ' +
            'slice.', [NTri]);
      end;

    exWebP:
      begin
        FStage := 'working out the size';
        if Length(FCam) < 2 then
          raise Exception.Create('there is no clip yet - press Record a move');
        if not OutSize(W, H) then raise Exception.Create('that size will not do');
        FStage := Format('drawing the frames at %dx%d', [W, H]);
        N := SavePathFilm(FDoc, FCam, FSrcW, FSrcH, W, H, FUnits, FFont,
          FLabelCol, FEdgeW, FILM_FPS, cbLoop.Checked, cbAxes.Checked, Fn,
          cbBounce.Checked, FilmSeconds);
        FMsg := Format('Wrote %s - %d frames, %d x %d.',
          [ExtractFileName(Fn), N, W, H]);
      end;

  else   { exPng, exJpeg }
    begin
      FStage := 'working out the size';
      if not OutSize(W, H) then raise Exception.Create('that size will not do');
      FStage := Format('drawing the picture at %dx%d', [W, H]);
      SaveStill(FDoc, FView, FSrcW, FSrcH, W, H, FUnits, FFont, FLabelCol,
        FEdgeW, Fn, FKind = exJpeg, tbQual.Value,
        (FKind = exPng) and cbTransp.Checked, cbAxes.Checked);
      FMsg := Format('Wrote %s - %d x %d.', [ExtractFileName(Fn), W, H]);
    end;
  end;
end;

{ ------------------------------------------------------------------------ }

function RunExport(Doc: TWorkDoc; const V: TProjector; U: TUnitSystem;
  AFont: TFont; const LabelCol: TPix; EdgeW: Single; SrcW, SrcH: Integer;
  const Suggest: string; const T: TTheme; const Pivot: TP3;
  OnReport: TReportProc; DirFor: TDirFor; DirKeep: TDirKeep;
  out Msg: string; out ShowHoles: Boolean; PrintScale: Integer): Boolean;
var
  Dlg: TExportDlg;
begin
  hsDialogSkin.UseTheme(T);
  Dlg := TExportDlg.Create(nil);
  Dlg.Setup(Doc, V, U, AFont, LabelCol, EdgeW, SrcW, SrcH, Suggest, DirFor,
    DirKeep);
  Dlg.cbScale.ItemIndex := EnsureRange(PrintScale, 0, SCALE_COUNT - 1);
  Dlg.FOnReport := OnReport;
  Dlg.FPivot := Pivot;
  try
    Dlg.ShowModal;
    Result := Dlg.FWrote;
    Msg := Dlg.FMsg;
    ShowHoles := Dlg.FOpenSolid;
  finally
    Dlg.Free;
  end;
end;

end.

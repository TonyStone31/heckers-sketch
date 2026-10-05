unit hsMainForm;

{
  Heckers Sketch main window: the drawing board (scale, snap, and lengths
  typed into the command bar).

  Copyright (c) 2021-2026 Tony Stone

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to
  deal in the Software without restriction, including without limitation the
  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
  sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
  IN THE SOFTWARE.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, StrUtils, IniFiles, Forms, Controls, Graphics,
  Dialogs, ExtCtrls, StdCtrls, Menus, LCLType, LCLIntf, Printers, PrintersDlgs, Contnrs,
  hsSurface, hsSkin, hsViewCube, hsDialogSkin, hsFilm, hsRecorder, hsExport, hsExToy, hsExamples, hsDrawing, hsSplash, hsSysInfo, hsTouch, hsFaceFinder, hsUpdater, hsUpdateForm, hsWhatsNew, hsPaths,
  hsBugReport, hsNet, hsUnfold, hsFlatView, hsTunnels, hsSendReport, hsSourceWindow, hsPostcard, hsHeckWriter, hsHeckReader, hsJigRun, hsJigFiles, hsFittings, hsTransitionWizard, hsSpoolWizard, hsPipe,
  hsStairs, hsStairWizard, hsStringerSheet, hsHeckFile, hsRadiantData, hsRadiant, hsRadiantWizard, hsRadiantSubmittal, hsRadiantJob,
  hsCommandText, InkPage, InkDraw;

type
  { What the cursor may infer; Alt cycles through these, as SketchUp's line
    tool does.  Linear inferences are directions (axis, parallel,
    perpendicular); point snaps are never turned off by it. }
  TInferMode = (imAll, imNoLinear, imParPerp);

  TTool = (ptSelect, ptMove, ptLine, ptRect, ptArc, ptCircle, ptPush,
    ptText, ptErase, ptMeasure, ptDim, ptOrbit, ptOffset, ptRotate,
    ptProtractor, ptDrill, ptFollow);

  TIntListsW = array of TIntArrayW;

  { a finger on the screen, in drawing-area coordinates }
  TTouchPt = record
    Seq: Pointer;
    X, Y, X0, Y0: Integer;
    T0: QWord;
  end;
  { none; one finger down, not yet a tap or a drag; one finger as the mouse;
    two fingers panning and pinching; gesture over, remaining finger ignored }
  TTouchMode = (tmNone, tmPending, tmMouse, tmGesture, tmSpent);

  { One line of the entity panel, with its steppers when the value can be
    changed.  The painter reads this and the mouse hit test uses the same rects. }
  TInfoAct = (iaNone, iaSides, iaSoft, iaNoteSize, iaReverse, iaWidth, iaColor,
    iaMaterial, iaUnpaint, iaPartOpen, iaPartLock, iaPartExplode, iaPartRename,
    iaPartHide);
  TInfoRow = record
    Caption: string;
    Value: string;
    Act: TInfoAct;
    Ent: Integer;
    Head: Boolean;          { a section heading rather than a value }
    Minus, Plus: TRect;     { empty unless Act says otherwise }
  end;

  { One line of the groups panel.  Fold and Tick are where they were painted,
    which is where the mouse looks for them. }
  TGrpRow = record
    Id: Integer;            { 0 is the sheet itself, above every group }
    Depth: Integer;
    Kids: Boolean;
    Fold, Tick: TRect;
  end;

  { Enough of a flat area to recognize it at the next rebuild.  Plane and area,
    not corners: corners change when something is stood on an edge.  Mid tells
    two identical windows in one wall apart. }
  TRegionSig = record
    Nm: TP3;
    D: Double;
    Area: Double;
    Mid: TP3;
    Part: Integer;      { the group the area was found in }
  end;

  { the region finder's cache, one per group - a plane shared by two groups
    must not hand one group's areas to the other }
  TPartCache = record
    Part: Integer;
    Cache: TRegionCache;
  end;

  { Everything the paper is a picture of; if none of it moved, neither did
    the paper.  See TMainForm.RepaintPaper. }
  TPaperSig = packed record
    ThemeIdx, W, H: Integer;
    View: TViewKind;
    Units: TUnitSystem;
    Grid: Boolean;
    Ppu, ViewX, ViewY, Az, El, Zoom, Snap, UIScale: Double;
  end;

  { One sheet: everything that belongs to a drawing rather than to
    the program, so tabs are just a list of these. }
  TDrawing = class
    Doc: TWorkDoc;
    Name: string;
    ViewX, ViewY: Double;      // screen position of world 0,0
    Zoom: Double;              // magnification only; the print scale is ScaleIdx
    ScaleIdx: Integer;
    SnapIdx: Integer;
    Units: TUnitSystem;
    View: TViewKind;        // PLAN, ISO or free 3D
    Plane: TPlane;          // which plane new arcs and mouse picks land on
    Az, El: Double;         // 3D camera, radians
    { True when the camera came from a file; such a sheet must not be
      reframed on top of it. }
    CamKnown: Boolean;
    { Edited since this sheet was loaded or saved.  Kept per sheet, not per
      window: a window-wide flag let closing one tab skip the save prompt
      because making a new sheet marked everything saved. }
    Dirty: Boolean;
    { The file this sheet belongs to.  All sheets of one document share
      DocKey, FilePath and DocName, and their tabs sit together.  FilePath is
      '' until saved; DocName is then "Untitled 2" and so on. }
    DocKey: Integer;
    FilePath: string;
    DocName: string;
    { The plan view's section slice; a floor plan is a cut, not a view from
      above.  Only used in PLAN; see TMainForm.ApplySlice. }
    SliceOn: Boolean;
    SliceLo, SliceHi: Double;
    { The flat areas at the last rebuild.  An area that had a face and now
      has none was erased on purpose and must not be given a new face. }
    Seen: array of TRegionSig;
    Undo, Redo: array of TWorkEntArray;
    UndoTop, RedoTop: Integer;
    constructor Create(const AName: string);
    destructor Destroy; override;
  end;

  TDeckKind = (dkNone, dkSegment, dkIcon);

  TDeckItem = record
    Kind: TDeckKind;
    Bounds: TRect;
    Group: Integer;
    Value: Integer;
    Caption: string;
    Hint: string;
    Icon: TIconKind;
  end;

  { TMainForm }

  TMainForm = class(TForm)
    dlgColor: TColorDialog;
    dlgPrint: TPrintDialog;
    dlgOpen: TOpenDialog;
    dlgSave: TSaveDialog;
    dlgSubmittal: TSaveDialog;
    dlgStringers: TSaveDialog;
    pbCmd: TPaintBox;
    pbTabs: TPaintBox;
    pbView: TPaintBox;
    pbSlice: TPaintBox;
    pbTools: TPaintBox;
    pbInfo: TPaintBox;
    pbGroups: TPaintBox;
    pbQuick: TPaintBox;
    pmView: TPopupMenu;
    pmCanvas: TPopupMenu;
    pmFile: TPopupMenu;
    pmGroups: TPopupMenu;
    pmCmd: TPopupMenu;
    pbDeck: TPaintBox;
    pbScreen: TPaintBox;
    tmrTick: TTimer;
    function ExportDirFor(const Ext: string): string;
    procedure KeepExportDir(const Ext, Dir: string);
    function SaveDirNow: string;
    function OpenDirNow: string;
    { the command list's order: used lately first, then alphabetical }
    procedure BuildCmdOrder;
    function CmdIndex(const W: string): Integer;
    procedure TimingLine(const S: string);
    procedure ShowTimingLog;
    function CmdAliasFor(Idx: Integer; const Want: string): string;
    procedure SyncCmdList;
    procedure TakeCmdHighlight;
    procedure MoveCmdHighlight(Key: word);
    { True when what is typed is already the whole name of a command }
    function ExactCmd(const S: string): Boolean;
    procedure NoteCmdUsed(const Cmd: string);
    procedure CornerSelection;
    procedure ShowOpenEdges;
    procedure OpenManual;
    procedure KeepHelpCurrent;
    procedure HelpFetchProgress(BytesReceived, TotalBytes: Int64);
    procedure HelpFetchDone(Sender: TObject);
    { the system color picker, for a pen that is not on the palette }
    procedure PickAnyColor;
    function AskColor(Was: TColor; out C: TColor): Boolean;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    function AnyDirty: Integer;
    procedure FormDestroy(Sender: TObject);
    procedure RememberWindow;
    function OnAScreen(L, T, W, H: Integer): Boolean;
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure FormKeyPress(Sender: TObject; var Key: char);
    procedure FormKeyUp(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure FormPaint(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure pbCmdPaint(Sender: TObject);
    procedure pbCmdMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbCmdMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbCmdMouseLeave(Sender: TObject);
    procedure pbTabsMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbTabsMouseLeave(Sender: TObject);
    procedure pbTabsMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbTabsPaint(Sender: TObject);
    procedure pbQuickPaint(Sender: TObject);
    procedure pbQuickMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbQuickMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbQuickMouseLeave(Sender: TObject);
    procedure RebuildQuick;
    function QuickHit(X, Y: Integer): Integer;
    function QuickWidth: Integer;
    procedure pbToolsPaint(Sender: TObject);
    function InfoPanelWidth: Integer;
    function GroupsPanelOn: Boolean;
    procedure SetGroupsPanel(On_: Boolean);
    procedure RebuildGroupRows;
    function GroupRowAt(Y: Integer): Integer;
    function GroupPutAway(Id: Integer): Boolean;
    procedure PickGroupFromPanel(Id: Integer; Add: Boolean);
    procedure ShowGroupFromPanel(Id: Integer; Shown: Boolean);
    procedure GroupsMenuClick(Sender: TObject);
    procedure GroupsChanged;
    procedure InfoChanged;
    { the source window - see hsSourceWindow.  It asks; these answer. }
    procedure ShowSource;
    { the source window in the program's theme - at opening, and whenever
      the theme changes }
    procedure ThemeSourceWindow;
    procedure SourceAskState(out DocSeq, PickSeq: Int64);
    procedure SourceAskSource(L, Hints, Names: TStrings;
      out First, Last, LineThing: TIntArrayW; out SheetName: string);
    procedure SourceAskPicked(out Picked: TIntArrayW);
    procedure SourcePickThings(const Things: TIntArrayW);
    function SourceApply(L: TStrings; out ErrLine: Integer; out Err: string): Boolean;
    { run the jig that makes this group again; 0 runs every jig on the sheet }
    function RunJigOf(PartId: Integer): Boolean;
    { the same, from the group's record - the source window's play button }
    function RunJigOfThing(Thing: Integer): Boolean;
    { the source window's Pick: clicks on the sheet type places into it }
    procedure SourcePick(On: Boolean);
    function RunAllJigs: Integer;
    procedure SourceCenter;
    procedure RebuildInfo;
    procedure PaintInfoStep(C: TCanvas; const R: TRect; const S: string;
      Hot: Boolean);
    function InfoHit(X, Y: Integer): Integer;
    procedure pbInfoPaint(Sender: TObject);
    procedure pbInfoMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbInfoMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbInfoMouseLeave(Sender: TObject);
    procedure pbGroupsPaint(Sender: TObject);
    procedure pbGroupsMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbGroupsMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbGroupsMouseLeave(Sender: TObject);
    procedure pbGroupsMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure pbToolsMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbToolsMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbToolsMouseLeave(Sender: TObject);
    procedure RebuildTools;
    function ToolsHit(X, Y: Integer): Integer;
    function ToolStripWidth: Integer;
    procedure PaintChromeTip(C: TCanvas);
    procedure pbSlicePaint(Sender: TObject);
    procedure pbSliceMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbSliceMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbSliceMouseLeave(Sender: TObject);
    procedure pbSliceMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    { which part of the cut strip a point is over: -1 none, 0 the label,
      1 the bottom field, 2 the top field, 3/4 its up arrows, 5/6 its downs }
    function SliceZoneAt(X, Y: Integer): Integer;
    function SliceFieldRect(Which: Integer): TRect;
    procedure CommitSliceEdit;
    procedure pbViewMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbViewMouseLeave(Sender: TObject);
    procedure pbViewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbViewPaint(Sender: TObject);
    function ViewButtonName: string;
    procedure ViewMenuClick(Sender: TObject);
    procedure FillViewMenu;
    procedure pbDeckMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbDeckMouseLeave(Sender: TObject);
    procedure pbDeckMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbDeckPaint(Sender: TObject);
    procedure pbScreenMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbScreenMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbScreenMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbScreenMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure pbScreenPaint(Sender: TObject);
    procedure tmrTickTimer(Sender: TObject);
  public
    { A bug report from inside a dialog.  Where names the dialog and Fields
      is what it held; the picture is the whole screen. }
    procedure ReportFromDialog(const Where, Fields: string);
  private
    { --- surfaces ------------------------------------------------------- }
    FPaper: TArtSurface;         // paper, grain, grid
    { what the paper was last drawn for, and whether that is still true }
    FPaperSig: TPaperSig;
    FPaperOK: Boolean;
    FPaperPaints, FPaperSkips: Integer;
    FInk: TArtSurface;        // ink, rendered from the document
    FInkHalf: TArtSurface;       // half its size, for a frame while the camera moves
    FArt: TArtSurface;           // paper + active ink; what you see and save
    FShell: TArtSurface;
    FDeckSkin: TArtSurface;
    FCmdSkin: TArtSurface;
    { the message rows' last content, so they are set only on change, and
      row one's layout kept between caret blinks }
    FCmdRowCache: THTMLLayoutCache;
    FCmdMsgR: TRect;           { where the message rows are, in the bar }
    FCmdPillW: Integer;        { the tool pill's column, left of them }
    FOverlay: TArtSurface;

    { --- look and pen --------------------------------------------------- }
    FUIScale: Single;
    FThemeIdx: Integer;
    { the weight new edges are drawn with }
    FEdgeW: Integer;
    FInkColor: TColor;
    FInkAuto: Boolean;
    FShowGrid: Boolean;
    FBooted: Boolean;
    FLastStatus: QWord;

    { --- sheets --------------------------------------------------------- }
    FDrawings: array of TDrawing;
    FTabIdx: Integer;
    FD: TDrawing;                // the sheet on the active tab
    FTool: TTool;
    FTabRects: array of TRect;
    FHotTab: Integer;
    FCur: TP3;                   // snapped cursor, world units
    FSnapKind: TSnapKind;
    { which of the three the cursor is on, when FSnapKind is snOnAxis }
    FSnapAxis: Integer;
    FStage: Integer;             // where we are in the current tool
    FP1, FP2: TP3;
    FDirLock: Integer;           // -1 none, else an index into AxisDir
    FInput: string;              // what has been typed into the command bar
    FCmdMsg: string;             // last result / error shown in the bar
    { Where things were last saved and opened.  This is a portable program,
      so the first offer is a folder beside it, not the home folder; after
      that it is wherever the user went.  Exports are kept per file type as
      "ext=folder" lines. }
    { The open (unclosed) edges of solids, in pairs, from TWorkDoc.OpenEdges.
      Kept until the drawing changes; a stale answer is worse than none. }
    FOpenEdges: TP3Array;
    FOpenSeq: Int64;
    FSaveDir, FOpenDir: string;
    FExportDirs: TStringList;
    FDimFont: TFont;

    { --- input ---------------------------------------------------------- }
    FPanning: Boolean;
    FOrbiting: Boolean;
    FOrbitGain: Double;           { the trackball's leverage for this drag - see OrbitGainAt }
    FPushFace: Integer;
    FReplayFace: Integer;        { the face a replayed press is on, while it is pressed; -1 otherwise }
    { the face the offset tool is working on, or -1 }
    FOffFace: Integer;
    FHoverFace: Integer;   // the face push/pull would take, before you click

    { Held down, the eraser gathers everything dragged over and shows it red
      before deleting, so a stray hit can be seen first. }
    FErasing2: Boolean;
    { The eraser's mode for this stroke, from the modifiers at press:
      0 erases, 1 softens, 2 unsoftens (SketchUp's Ctrl and Ctrl+Shift).
      Softening hides the creases along a pulled circle. }
    FEraseMode: Integer;
    FDoomed: array of Integer;

    { The selection and the pick box.  Left to right takes only what is
      wholly inside; right to left takes anything it touches, as SketchUp. }
    FSel: array of Integer;
    FBoxing: Boolean;
    FBoxX, FBoxY: Integer;

    { from the command line: keep filling the screen if it changes size }
    FFill: (flNone, flMaximized, flFull);
    FScrW, FScrH: Integer;

    { the two gaps between tool groups, where the deck draws dividers }
    FGrpDivX: array[0..1] of Integer;
    FGrpDivY0, FGrpDivY1: Integer;

    { every corner the current move will carry, gathered once at the grab
      so the drag stays cheap }
    FMoveVerts: TP3Array;
    { nothing was selected, so the move tool took what was under the cursor
      and lets go of it once moved (see ToolCommit) }
    FMoveTook: Boolean;
    { the guide the measure tool's right-click menu is about }
    FGuideMenuEnt: Integer;
    { whole groups being moved or turned: they go rigidly, and loose
      geometry touching them is not stretched along }
    FMoveGroupEnts: TIntArrayW;
    FMoveCopy: Boolean;
    { The entity panel on the right: what is picked and what can be changed
      about it.  Docked, not a dialog, so the figures update as you pick. }
    FInfoOn: Boolean;
    { The groups panel (SketchUp's Outliner): a tree of groups with a box to
      hide each and a click to pick.  Sits under the entity panel. }
    FGroupsOn: Boolean;
    FGrpRows: array of TGrpRow;
    FGrpHot: Integer;         { the row under the pointer, or -1 }
    FGrpHotId: Integer;       { its group, whose box the drawing shows }
    FGrpScroll: Integer;      { rows scrolled off the top }
    FGrpFold: array of Integer;  { groups shown closed }
    FGrpSig: Int64;
    FGrpMenuId: Integer;
    FGrpSkin: TArtSurface;
    FInfoRows: array of TInfoRow;
    FInfoHot: Integer;
    FInfoSig: Int64;
    { The clipboard: a deep copy detached from its document, so it survives
      a sheet switch and pastes into another sheet.  One per window. }
    FClip: TWorkEntArray;
    { Frame watchdog: time spent re-rendering ink, compositing and blitting,
      cleared at the start of each paint.  A frame over 1/40 s writes a line
      to the session log, so bug reports carry the diagnosis. }
    FMsPaper, FMsRender, FMsComp: QWord;
    FSlowN: Integer;
    FSlowWorst: QWord;
    FSlowSaid: QWord;
    FSlowLast: string;
    { What the tape leaves: 0 point and guide line, 1 point only, 2 line
      only, 3 neither.  Ctrl cycles it while measuring.  0 is the default. }
    FTapeDrop: Integer;
    { The tape's last run, kept so /keep can turn it into a dimension (see
      ptMeasure in ToolCommit). }
    FRunOK: Boolean;
    FRunA, FRunB: TP3;
    { An edge just drawn over an existing one: SketchUp's "healing".  An
      erased face's area is remembered as unwanted; tracing one of its edges
      again says it is wanted after all, and this tells the region loop. }
    FHealOn: Boolean;
    FHealA, FHealB: TP3;
    { /detach: a move takes the selection away alone instead of stretching
      what it is joined to.  Stretching is SketchUp's default and stays ours.
      A command, not a key, because Ctrl, Shift, Alt and every letter are taken. }
    FDetachMove: Boolean;
    FLastPush: Double;         // what a double-click repeats
    { The tape lays down a guide by default, like SketchUp's; Ctrl turns that
      off. }
    FMeasEdge: Integer;        // the edge the tape was started on, or -1
    { Planes from the last rebuild are reused only when their segments hash
      the same, so this is safe across sheets. }
    { how many faces the last rebuild had to flip the right way out }
    FTurned: Integer;
    FRegionCaches: array of TPartCache;

    { clicks in the same spot in quick succession: two takes what is
      attached, three everything joined on }
    FClickN: Integer;
    { the corner the last arc rounded, kept for a double-click to trim, and
      the radius a double-click elsewhere repeats (see ArcFillet) }
    FLastFillet: TFillet;
    FFilletPending: Boolean;
    FFilletSeq: Int64;
    FFilletTick: QWord;
    FLastFilletR: Double;
    FClickT: QWord;
    FClickX, FClickY: Integer;

    { The working plane follows the face under the cursor.  Alt cycles the
      three flat planes and latches, for drawing in mid air; Esc or a new
      tool releases it. }
    FPlaneHeld: Boolean;
    { Alt's three stops on the line tool, and the edge parallel and
      perpendicular are measured from: the last segment, or the start edge. }
    FInferMode: TInferMode;
    FParHas: Boolean;
    FParDir: TP3;
    { 0 none, 1 parallel, 2 perpendicular - what the cursor is on now }
    FParPerp: Integer;
    { The arc's tangent lock: the edge its first point is on, and whether Alt
      has pinned the bulge to leave that edge smoothly, as in SketchUp. }
    FArcTanHas, FArcTanLock: Boolean;
    FArcTanDir: TP3;
    { the offset's Alt: keep the overlaps a tight corner makes (SketchUp's;
      off unless asked for) }
    FOffsetRaw: Boolean;
    { the protractor's Alt: stop taking the plane from the face under the
      cursor }
    FRotFree: Boolean;
    { the face the shape is being drawn on, so a point can be held to it }
    FFacePt, FFaceNm: TP3;
    { true while a push is lining itself up with another face }
    FPushFlush: Boolean;
    { waiting for a click to say which piece to lay out }
    FUnfoldPick: Boolean;
    { which side of the cursor the chip sits on, kept so it does not swap
      sides each time the mouse twitches }
    FTipCorner: Integer;
    { the dotted lines the cursor is on this frame, in screen pixels as point
      pairs; the chip keeps off them (see TipSpot) }
    FTipLines: array of TRect;
    { what the precision list is showing as chosen }
    FLenDenom: Integer;
    { The report screenshot: FShotCount is the countdown drawn on the canvas,
      FShotFlash whites the screen as it is taken, FShotBusy stops a second
      capture starting during the countdown (the program stays usable). }
    FShotCount: Integer;
    FShotFlash: Boolean;
    FShotBusy: Boolean;
    { the guide count the settings row was built for, so the guide buttons
      follow it however it changed }
    FDeckGuides: Integer;
    { the note being dragged by its box }
    FNoteDrag: Integer;
    { whether the note being carried has actually gone anywhere yet }
    FNoteMoved: Boolean;
    FNoteFrom, FNoteGrab: TP3;
    { the point the cursor is holding on to, and whether it has one }
    FStickOn: Boolean;
    FStickPt: TP3;
    FStickKind: TSnapKind;
    { recent crash count and when the last one was }
    FWoundCount: Integer;
    FWoundAt: QWord;
    { where the window was, taken while it still existed }
    FWinSaved, FWinMax: Boolean;
    FWinL, FWinT, FWinW, FWinH: Integer;
    { True when the start point is on a face, so that face sets the plane
      and dragging must not overrule it.  In mid air the drag decides. }
    FPlaneFromFace: Boolean;
    { Autosave: every change bumps FEditSeq; a few seconds later the tick
      writes all sheets to a draft beside the settings, and the next launch
      restores it.  FDraftSeq is what was last written, FDraftAge counts ticks
      since the last change. }
    FEditSeq, FDraftSeq: Int64;
    { the edit the named file was last written at; anything later is unsaved }
    FSavedSeq: Int64;
    { unique per run, so two copies cannot write the same temp file }
    FRunTag: string;
    FDraftAge: Integer;
    FRestored: Boolean;
    { closing because an update is taking over - nothing is asked }
    FHandingOver: Boolean;
    { Hold the button still and the rubber band strains, bows and cracks;
      when it breaks the run is released and no point is placed.  FHoldOn is
      a press not yet decided, FHoldT how long it has been held, FSnapT the
      recoil afterwards. }
    FHoldOn: Boolean;
    FHoldT, FSnapT: Single;
    { a line snapping throws its two ends apart; a shape only bursts }
    FSnapEnds: Boolean;
    FHoldX, FHoldY: Integer;
    { Pointer speed in pixels a second, smoothed.  Alignment nudges wait for
      the hand to slow down; otherwise a cursor swept across a cube catches
      every corner it passes and hunts sideways. }
    FMoveSpeed: Double;
    FLastMoveTick: QWord;
    FLastMoveX, FLastMoveY: Integer;
    FSnapA, FSnapB, FSnapM: TPointF;
    { After a run snaps off, the cursor still sits on the point it was joined
      to.  Do not take it up as a reference again until the hand moves. }
    FNoLockUntilMoved: Boolean;
    FWasLine: Boolean;
    { latched when drawing the document threw, so it is not retried every frame }
    FRenderBroken: Boolean;
    { uptime, and whether startup has been declared good }
    FUpTime: Single;
    FStartupDone, FAskedAboutCrash: Boolean;
    { an exception was written up and we are still running: offer to send it
      on the next tick }
    FCrashToOffer: Boolean;
    FUpdatedFrom: string;
    FWhatsNewShown: Boolean;
    FPostcardOffered: Boolean;
    FTextPick: Boolean;           { the sheet is taking points for the source window }
    { the stair dialog picking points on the sheet: which is next (1 to 3,
      or 0), the points, the dialog state to reopen with, and the stair group
      being changed or 0 }
    FStairPick: Integer;
    FStairPts: array[0..2] of TP3;
    FStairJob: TStairJob;
    FStairEdit: Integer;
    FSourceComplete: Boolean;     { the source window's list of words opens by itself }
    { The last few dozen things that happened, for crash reports.  A ring, so
      it never grows. }
    FTrail: array[0..63] of string;
    { The same session for replay: load the report's drawing, run these, and
      the fault happens again.  Recorded from our own handlers, so nothing
      outside the window is seen.  World coordinates, not pixels, so it
      replays on any screen size. }
    FActs: array[0..511] of string;
    FActsN: Integer;
    FTrailN: Integer;
    { The newer version available, if any.  Kept, because a status line gets
      overwritten and never seen again. }
    FUpdateTag: string;
    { Shaking the mouse: direction reversals per screen axis and when they
      happened, so a shake decays if you stop. }
    FShX, FShY: Integer;
    FShDirX, FShDirY, FShNX, FShNY: Integer;
    FShTX, FShTY: QWord;
    { the dimension whose figure is being typed over, or -1; while set, the
      command bar edits that label }
    FDimEdit: Integer;
    { where the right button went down, so a click can be told from a pan }
    FRightSX, FRightSY: Integer;
    FPushSX, FPushSY: Integer;   // where the drag started, on screen
    FPanRefX, FPanRefY: Integer;
    { What the orbit turns about: the thing under the cursor, as in SketchUp.
      Turning about the origin sends what you were looking at off screen. }
    FOrbitPivot: TP3;
    { where the pivot sat on screen when the drag began; the orbit holds it
      there, not under the cursor (see ServiceMotion) }
    FOrbitAnchor: TPointF;
    FOrbitAnchored: Boolean;
    FMouseSX, FMouseSY: Integer;   // raw pointer, before snapping

    { Motion is only recorded here; the work happens once per tick from the
      newest position.  Painting in the handler is slow on a virtual display,
      and GDK holds motion events until the handler returns. }
    FMoveX, FMoveY: Integer;
    FMoveShift: TShiftState;
    { a built part being placed moves whole, on its own; nothing stretches }
    FMoveRigid: Boolean;
    { Follow Me: the face being spun, and the first point of its axis }
    FFollowFace: Integer;
    FAxisA: TP3;
    { what a dialog reported from inside itself, for the report body }
    FReportExtra: string;
    FTimings: Boolean;
    { what /timings has seen since it was turned on; there is no console on
      Windows, so it is kept to be shown }
    FTimingLog: array of string;
    { The camera is moving (orbit, pan, or a recent wheel zoom), so frames are
      drawn quick and one full frame is drawn when it stops.  FQuickFrames
      turns this off. }
    FCameraMoving: Boolean;
    FQuickFrames: Boolean;
    { faces at half resolution while the camera moves; switched on by a slow
      moving frame, off when the camera settles.  See RenderInk and
      TWorkDoc.Render. }
    FMoveHalf: Boolean;
    { Long work on the main thread: what and how far, shown on the command
      bar, and input handlers stand down until it ends.  FBusyAt is the last
      report; the tick clears a stale flag. }
    FBusy: Boolean;
    FBusyMsg: string;
    FBusyFrac: Double;
    FBusyAt, FBusyPaintMs: QWord;
    { a bulk select marks FSel here once, instead of IsSelected walking the
      whole selection for every entity }
    FSelBulk: array of Boolean;
    FSelBulkOn: Boolean;
    { outlines of a large selection drawn once into a layer and composited
      each paint, instead of redrawing thousands of lines on every mouse move }
    FSelLayer, FSelShot: TArtSurface;
    FSelLayerKey: string;
    { touch, from hsTouch's hook: the fingers and what they are doing }
    FTouches: array of TTouchPt;
    FTouchMode: TTouchMode;
    FTouchDown: Boolean;
    FTouchOn: Boolean;
    FTouchCount: Integer;
    FGestMidX, FGestMidY, FGestDist: Double;
    { a document was being read and the splash screen's skip was pressed }
    FLoading, FLoadSkipped: Boolean;
    { worker threads for the caches (docs/render-acceleration.md); /threads }
    FThreads: Boolean;
    FStartedAt: QWord;
    FLastWheel: QWord;
    { the dimension the move tool holds by its line: only the offset changes,
      never what it measures }
    FDimMove: Integer;
    { the circle or arc being dimensioned (diameter or radius), or -1; and the
      last direction, for DimOffsetAt to keep }
    FDimArc: Integer;
    FDimPrefer: TP3;
    { The copy just made, so 3x or /3 typed next makes an array.  Made is
      every copied entity, all at the end of the list so they can be taken
      back and remade at a new count.  Live until any other action. }
    FArray: record
      Live, Rotate: Boolean;
      Src: array of Integer;
      Made: TIntArrayW;
      D, C, Axis: TP3;
      Ang: Double;
    end;
    { Rotate and the protractor.  FP1 is the center; the axis is an arrow
      key's axis, else the face under the cursor, else blue.  The second
      click is the reference arm. }
    FRotAxis: TP3;
    FRotAxisIx: Integer;
    FRotRef: TP3;
    { sides for the next circle and arc: SketchUp's defaults, changed with
      + and - or by typing 24s }
    FSidesCircle, FSidesArc: Integer;
    FMovePending: Boolean;
    FScreenDirty: Boolean;
    { the camera moved and the picture is not redrawn yet (see ViewMoved) }
    FViewDirty: Boolean;
    { the face whose blue wash is already in the shown picture, so the
      overlay does not paint it again (see pbScreenPaint) }
    FHintInShot: Integer;
    { What is on screen: the picture, the selection and the face wash.  They
      only change when something says so; rebuilding every paint cost a
      full-window composite and copy each time. }
    FShotOK: Boolean;
    FShotHadSel: Boolean;
    { the paper's fill, made once per theme and size - see RepaintPaper }
    FPaperBase: TArtSurface;
    FPaperBaseKey: string;
    FHotView: Integer;

    { The view cube.  Off by default: a first drawing is a rectangle in plan
      and does not need it. }
    FCubeOn: Boolean;
    FSourceWasOpen: Boolean;      { the source window was open when the program was last shut }
    FSourceOnTop: Boolean;
    FSourceBounds: TRect;         { Left, Top, and Width and Height in Right and Bottom }
    { its corner: 0 top left, 1 top right, 2 bottom left, 3 bottom right }
    FCubeCorner: Integer;
    { whether a click centers and fits the selection.  With nothing picked it
      never refits, since refitting on every view change loses the user's zoom. }
    FCubeFitSel: Boolean;
    FCubeSkin: TArtSurface;
    FCubeHot: TCubeTarget;
    FCubeHasHot: Boolean;
    { the view an orbit would snap to if released now (see OrbitSnapTarget) }
    FSnapHot: TCubeTarget;
    FSnapHasHot: Boolean;
    FCubeDrag: Boolean;
    FCubeDragX, FCubeDragY: Integer;
    FCubePressX, FCubePressY: Integer;
    FCubeMoved: Boolean;
    FCubeCursor: Boolean;
    FCursorWasCube: TCursor;
    { Progress of a camera move, 0 when still.  Cube clicks animate so you
      can see which way the model turned. }
    FGlideT: Double;
    FGlideAz0, FGlideEl0, FGlideAz1, FGlideEl1: Double;
    { Start time by the clock.  Counting ticks fails because each step redraws
      the model and the timer falls behind on big drawings (hsRecorder's FClock
      has the same note). }
    FGlideAt: QWord;
    { the two camera positions the move interpolates between }
    FGlideD0, FGlideD1: TP3;
    { the turn's pivot and where it was on screen at the start; held there
      for every frame }
    FTurnPivot: TP3;
    FTurnAnchor: TPointF;
    FTurnAnchored: Boolean;
    { and the framing, when the move changes it too }
    FGlideFrame: Boolean;
    FGlideZ0, FGlideZ1, FGlideOX0, FGlideOX1, FGlideOY0, FGlideOY1: Double;
    FHotSlice: Integer;         // which zone of the cut strip is under the pointer
    FTools: array of TDeckItem; // the vertical tool strip down the left
    FToolSkin: TArtSurface;
    FInfoSkin: TArtSurface;
    FHotTool: Integer;
    { The strip item under the pointer, so its tip is drawn beside it.
      FChromeTip is the title, FChromeTipBody the sentence, FChromeTipY the
      button's middle. }
    FChromeTip, FChromeTipBody: string;
    FChromeTipY, FChromeTipX: Integer;
    { the divider positions on the tool strip, and where the shop door sits }
    FToolRules: array of Integer;
    FShopTop: Integer;
    FQuick: array of TDeckItem;   // the file buttons in the title bar
    FQuickSkin: TArtSurface;
    FHotQuick: Integer;
    { Names beside the icons, or icons alone.  Saved in settings; starts True
      on purpose (see pbToolsPaint). }
    FToolsWide: Boolean;
    FSliceSkin: TArtSurface;
    FSliceEdit: Integer;        // 0 none, 1 typing the bottom, 2 the top
    FViewSkin: TArtSurface;
    FGlyph: TArtSurface;    // the tool badge beside the cursor
    FHoverEnt: Integer;          // what the eraser is about to delete
    { The one edge the dimension tool would take, as its two ends.  An index
      is not enough: it may be a side of a face outline, which has no A and B. }
    FHoverEdgeOK: Boolean;
    FHoverEdgeA, FHoverEdgeB: TP3;
    { documents: the next key, the untitled count, recent files, and whether
      closing because every question was answered (see FormCloseQuery) }
    FNextDocKey: Integer;
    FUntitled: Integer;
    FRecent: TStringList;
    FCleanExit: Boolean;
    { a draft from a run that did not close properly, offered once the window
      is up (see RestoreDraft) }
    FRecoverToOffer: Boolean;
    FGuide: Boolean;             // an alignment guide is active
    FGuideFrom: TP3;

    { A 90 degree relation to a chosen point beats other nearby snaps.
      FAxisFrom is that point (the line's start, or one picked up by resting
      on it); FAxisLock is the free axis: 0 X, 1 Y, 2 Z. }
    FAxisLock: Integer;
    FSnapFromPt: Boolean;     { the distance along the axis came from a corner, not the grid }
    FAxisFrom: TP3;

    { which standard view we are parked on, or -1 after a free orbit }
    FViewPreset: Integer;

    { rest the cursor on a point and it is kept as a reference }
    FLockOn: Boolean;
    FLockPt: TP3;
    FLockKind: TSnapKind;
    FDwellSX, FDwellSY: Integer;
    FDwellSince: QWord;

    { --- deck ----------------------------------------------------------- }
    FDeck: array of TDeckItem;
    FHotItem: Integer;
    { The open settings list, drawn on the canvas so it needs no extra
      control and cannot fall behind anything. }
    FPopup: Integer;
    FPopupR: TRect;
    FPopupN: Integer;
    FPopupHot: Integer;
    { the first row showing; only the command list is long enough to scroll }
    FPopupTop: Integer;
    { commands used lately, most recent first, comma separated; saved so the
      list keeps their order }
    FCmdRecent: string;
    FCmdWant: string;           { what the list is filtered by, after the slash }
    { the order the rows are in: recents, then the rest alphabetical }
    FCmdOrder: array of Integer;
    { where the arrow beside the prompt is, for hit testing }
    FCmdArrow: TRect;
    FCmdArrowHot: Boolean;
    FCursorWas: TCursor;

    { --- erase animation ------------------------------------------------ }
    FErasing: Boolean;
    FEraseT: Single;
    FJitterX, FJitterY: Integer;

    { helpers }
    function Theme: TTheme;
    function Ppu: Double;
    function CurScale: TDrawScale;
    function SnapStep: Double;
    function Proj: TProjector;
    function ScreenOf(const P: TP3): TPointF;
    function WorldAt(SX, SY: Double): TP3;
    function SnapToGrid(const P: TP3): TP3;
    function ResolveSnapRaw(SX, SY: Double): TP3;
    function ResolveSnapAt(SX, SY: Double): TP3;
    function HeldToFace(const P: TP3): TP3;
    function AnnotColor: TPix;

    procedure Relayout;
    function TitleHeight: Integer;
    function CursorOnPlane(const N, P0: TP3): TP3;
    function OffsetDistance: Double;
    function OffsetPreview: TP3Array;
    procedure CommitOffset;
    procedure EditDimUnder(X, Y: Integer);
    procedure RightClickAt(X, Y: Integer);
    procedure FillCanvasMenu;
    { the measure tool's right-click: erase the guide under the cursor (see
      RightClickAt) }
    procedure GuideMenuAt(X, Y: Integer);
    procedure CanvasMenuClick(Sender: TObject);
    procedure CenterSelection;
    function ReverseSelectedFaces: Integer;
    { the material on a face, or on every picked face when the shown one is
      among them }
    function PaintSelectedFaces(Shown: Integer; C: TColor;
      Painting: Boolean): Integer;
    { the pen color of every picked line, arc, note and dimension }
    function InkSelectedThings(C: TColor): Integer;
    function SelectedDim: Integer;
    function SelectedLine: Integer;
    function ApplyLineLength(NewLen: Double): Boolean;
    procedure ApplySlice;
    procedure SetSlice(AOn: Boolean; ALo, AHi: Double; const Why: string = '');
    procedure NudgeSlice(Steps: Integer; Which: Integer);
    procedure PlanFromFace(Face: Integer);
    function SliceText: string;
    function ApplyDimResize(NewLen: Double; MoveB: Boolean): Boolean;
    procedure CommitDimNote;
    function DeckRowH: Integer;
    function DeckRows: Integer;
    function DeckHeight: Integer;
    function ChromeMargin: Integer;
    procedure RebuildShell;
    procedure RebuildDeck;
    procedure RefreshChrome;
    procedure NoteFrame(PaintMs: QWord);
    procedure ResizeSurfaces(AW, AH: Integer);
    function PaperSig: TPaperSig;
    procedure RepaintPaper;
    procedure PaintGroundGrid(Pitch: Double);
    procedure PaintAxes;
    procedure PaintPushPreview(C: TCanvas);
    procedure PaintFaceHint(C: TCanvas; Face: Integer; const Col: TPix;
      S: TArtSurface = nil; OX: Integer = 0; OY: Integer = 0);
    function HintFaceNow: Integer;
    { the face a press is on (see the body) }
    function FaceAtPress: Integer;
    procedure CheckForUpdate(Loud: Boolean);
    procedure DoUpdate;
    procedure ShowWhatsNew;
    procedure BuildTransitionWizard;
    procedure BuildSpoolWizard;
    { Again: a radiant job group in the drawing to reopen in the wizard;
      Build replaces it }
    procedure BuildRadiantWizard(Again: Integer = 0);
    { the radiant zone this group is or is inside (0 for none), with its job }
    function RadiantGroupOf(G: Integer; out JobId: string): Integer;
    { every group of that job in the drawing, and the job read from them }
    function RadiantJobGroups(const JobId: string; out Job: TRadiantJob): TIntArrayW;
    procedure PrintSubmittalAgain(G: Integer);
    { the stringer sheet of the stairs group G, from what it remembers }
    procedure StringerSheetOf(G: Integer);
    procedure BuildStairWizard;
    procedure StairDialog;
    procedure StairTakePoint(const P: TP3);
    { the flight from the points so far and the cursor, and the marker
      saying what the next click is }
    function StairPickFrame(const Third: TP3; out F: TStairFrame; out Why: string): Boolean;
    procedure PaintStairPick(C: TCanvas; SX, SY: Integer);
    { a length typed while picking stairs: the run after the top, the width
      after the bottom }
    procedure StairTyped;
    procedure StairResume(Data: PtrInt);
    procedure StairRebuild(G: Integer; const F: TStairFrame; const S: TStairSpec; Use: TStairUse);
    function StairWhereNow(G: Integer; const F: TStairFrame; const S: TStairSpec): TP3;
    function ArcNormal(I: Integer): TP3;
    procedure DoRevolve(const AxisP, AxisDir: TP3; PathArc: Integer = -1);
    function IsProfileEdge(I: Integer): Boolean;
    function AxisSplitsProfile(const AxisP, AxisDir: TP3;
      out RLo, RHi: Double): Boolean;
    procedure PaintRevolvePreview(C: TCanvas);
    { the chain of edges joined end to end through edge I, and whether it
      closes }
    function ChainFrom(I: Integer; out Closed: Boolean): TP3Array;
    procedure DoSweep(const Path: TP3Array; Closed: Boolean);
    { /rendertime: how long a frame takes, for chasing sluggish orbits }
    procedure RenderTiming;
    procedure Took(const What: string; T0: QWord);
    procedure ApplyArray(N: Integer; Divide: Boolean);
    function ArrayCommand(const S: string; out N: Integer; out Divide: Boolean): Boolean;
    procedure CopySelection(Cut: Boolean);
    procedure PasteClip;
    { hand something just built to the move tool, so the next click places it }
    procedure PlaceBuilt(First: Integer; const Ref: TP3);
    procedure StartUnfold;
    procedure UnfoldAt(SX, SY: Integer);
    procedure OfferCrashReport(JustNow: Boolean);
    function DocThings(const DocFile: string): Integer;
    procedure Quiesce;
    function WindowShot(out B: TBitmap): Boolean;
    procedure DrawPointerOn(B: TBitmap; ScreenCoords: Boolean; const Org: TPoint);
    function CaptureShot(Wait: Boolean; out Bmp: TBitmap): Boolean;
    procedure ShotCountdown(Seconds: Integer);
    procedure PaintShotOverlay(C: TCanvas);
    function ReportBug(const Preamble: string = '';
      const ShotFile: string = ''; const DocFile: string = ''): Boolean;
    { note something worth knowing if this run ends badly }
    procedure Trail(const S: string);
    procedure Act(const S: string);
    function ActsText: string;
    function ReplayActs(const Script: string): Integer;
    procedure DoReplayFile(const FileName: string);
    function TrailText: string;
    { counts per kind on the sheet, so a crash tied to one kind shows it }
    function KindCounts: string;
    { the program's state as text; one place, so crash reports and hand
      written reports say the same things }
    function DiagnosticText: string;
    function SettingsText: string;
    { the drawing as it stood, saved beside the report }
    procedure SaveCrashDoc(const ReportPath: string);
    procedure ShakeWatch(X, Y: Integer);
    procedure PaintStrain(C: TCanvas; const A, B: TPointF; T: Single);
    function StrainOutline(out Pts: TPointFArray): Boolean;
    procedure PaintStrainPath(C: TCanvas; const Pts: TPointFArray; T: Single);
    procedure PaintStrainSeg(C: TCanvas; const A, B: TPointF; T: Single;
      Outward: Boolean; CX, CY: Double);
    procedure PaintStrainMark(C: TCanvas; CX, CY: Double; T: Single);
    procedure PaintSnapRecoil(C: TCanvas);
    procedure PaintFacePoints(C: TCanvas; Face: Integer);
    procedure PaintSnapMarker(C: TCanvas; SX, SY: Integer);
    procedure PaintDimPreview(C: TCanvas);
    procedure PaintDimEnds(C: TCanvas; const A, B: TP3);
    procedure PaintDimTag(C: TCanvas; X, Y: Double; const S: string);
    function PushDistance: Double;
    procedure Recompose;
    procedure RecomposeAll;
    procedure FreshScreen;
    procedure RenderInk;
    procedure InvalidateStatus;
    procedure ServiceMotion;
    procedure ServiceHover;
    function DimRadialAt(out A, B: TP3; out Note: string): Boolean;
    function CurveThrough(const P: TP3): Integer;
    function DimOffset3: TP3;
    procedure LayGuide;
    function TapeDropSays: string;
    { Every drawn edge as a plain segment for the region engine.  Guides,
      dimensions and notes are not geometry; solids' faces are their own
      boundary and are not derived. }
    function EdgeSegments(Part: Integer): TSegArray;
    function CacheFor(Part: Integer): Integer;
    function AllPartIds: TIntArrayW;
    procedure ReportRegions;
    { Keeps the drawn faces right; everything that changes an edge ends with
      this. }
    procedure SeedRegions;
    function RebuildFlatFaces: Integer;
    function FaceCount: Integer;
    function AnyFace: Boolean;
    function SolidFaceCount: Integer;
    procedure DoomAt(SX, SY: Integer);
    function PickAt(SX, SY: Integer): Integer;
    function PickForMenu(SX, SY: Integer): Integer;
    function IsSelected(I: Integer): Boolean;
    procedure LeaveSheet;
    procedure OnTouch(Kind: TTouchKind; Seq: Pointer; SX, SY: Double);
    procedure TouchTick;
    procedure TouchSendDown;
    procedure GestureStart;
    procedure GestureMove;
    procedure PruneSelection;
    procedure BeginBulkSelect;
    procedure EndBulkSelect;
    procedure EnsureSelLayer;
    procedure SelectOnly(I: Integer);
    procedure SelectToggle(I: Integer);
    procedure SelectAdd(I: Integer);
    procedure SelectRemove(I: Integer);
    procedure SelectNone;
    procedure FinishSelect(X, Y: Integer; Shift: TShiftState);
    function EntHasPoint(I: Integer; const P: TP3): Boolean;
    procedure SelectAttached(I: Integer);
    { --- groups --- }
    procedure SelectAddOne(I: Integer);
    procedure SelectRemoveOne(I: Integer);
    function PickAtRaw(SX, SY: Integer): Integer;
    function PickToGrab(SX, SY: Integer): Integer;
    function SelectedGroups: TIntArrayW;
    function SoleGroup: Integer;
    procedure MakeGroup;
    procedure ExplodeGroups;
    procedure OpenGroup(Id: Integer);
    procedure CloseGroup;
    procedure LockGroups(Locked: Boolean);
    procedure HideGroups(PutAway: Boolean; const Named: string);
    procedure RenameGroup(const NewName: string);
    function SplitMoveSelection: Boolean;
    function InContextFace(F: Integer): Integer;
    procedure PaintPartBox(C: TCanvas; Id: Integer; const Col: TPix;
      Dashed: Boolean; const Shift: TP3);
    function PromptForTool: string;
    procedure SelectConnected(I: Integer);
    procedure SelectInBox(X0, Y0, X1, Y1: Integer; Crossing, Add: Boolean);
    procedure DeleteSelection;
    function MoveDelta: TP3;
    function RunReading(const A, B: TP3): string;
    procedure PaintMoveGhost(C: TCanvas);
    procedure PaintRotateGhost(C: TCanvas);
    { The arc from FP1 and FP2 (the chord) and B pulling its middle out.  The
      plane is the working plane unless B is off it; then the three points
      make their own, so an arc drawn up the end of a box stands on it. }
    function ArcPicks(const B: TP3; out Pl: TPlane; out C: TP3;
      out R, A0, Sweep, Bulge: Double): Boolean;
    function RotAngle: Double;
    function RotRefDir: TP3;
    function IsDoomed(I: Integer): Boolean;
    procedure BurnDoomed;
    { 0 erases, 1 softens, 2 unsoftens, from the modifiers held }
    function EraseModeOf(Shift: TShiftState): Integer;
    { the gathered edges softened or unsoftened instead of deleted }
    procedure SoftenDoomed(On_: Boolean);
    function PopupMaxHeight(Which: Integer): Integer;
    procedure OpenPopup(Which: Integer);
    procedure ClosePopup;
    function PopupCount(Which: Integer): Integer;
    function PopupCaption(Which, I: Integer): string;
    procedure PopupChoose(Which, I: Integer);
    function PopupItemAt(SX, SY: Integer): Integer;
    function ScrollPopup(Lines, SX, SY: Integer): Boolean;
    procedure PaintPopup(C: TCanvas; DX: Integer = 0; DY: Integer = 0);
    procedure PaintToolGlyph(C: TCanvas; AX, AY: Integer);
    function PivotAt(SX, SY: Integer): TP3;
    function OrbitGainAt(SX, SY: Integer): Double;
    procedure AnchorOrbit(SX, SY: Integer);
    function RectTarget: TP3;
    procedure ReportCrash(Sender: TObject; E: Exception);
    function GuideColor: TPix;

    procedure UIFont(C: TCanvas; Size: Integer; Bold: Boolean; const Col: TPix;
      Mono: Boolean = False);
    { draws S letter by letter with Tracking pixels between; returns the width }
    function TrackedText(C: TCanvas; X, Y: Integer; const S: string;
      Tracking: Integer): Integer;

    { history }
    procedure PushUndo;
    procedure DoUndo;
    procedure DoRedo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;

    { tools and the command bar }
    function ToolName(T: TTool): string;
    function Prompt: string;
    function SnapSays: string;
    function SnapMarkPix: TPix;
    function CmdPalette: TCmdPalette;
    function LightChrome: Boolean;
    function FieldPix: TPix;
    function FieldEdgePix: TPix;
    procedure CmdRows(out Pad, Row1, Row: Integer);
    function CmdBarHeight: Integer;
    procedure PlaceCmdMsg;
    procedure PaintCmdMsg(C: TCanvas; const P: TCmdPalette);
    procedure CmdMenuClick(Sender: TObject);
    function DrawCmdRuns(C: TCanvas; X, Y, H, MaxX, Size: Integer; Mono: Boolean;
      const M: string; Measure: Boolean = False): Integer;
    function ModifierTip: string;
    function ShortKeys: string;
    { the size being pulled, worded as it would be typed, or '' }
    function LiveMeasure: string;
    { a working plane's color is the axis its normal points along, as
      SketchUp names planes: red, green, blue }
    function PlanePix(Pl: TPlane): TPix;
    function AxisAlong(const A, B: TP3): Integer;
    function IsoRunAxis(const From: TP3; out Along: Double): Integer;
    function PreviewTarget: TP3;
    procedure SetTool(T: TTool);
    function PlaneName: string;
    procedure PlaneByArrow(Key: Word);
    procedure ResetTool;
    procedure ToolClick;
    function WhyNotAMeasurement(const S: string): string;
    procedure ToolCommit;
    procedure CommandEnter;
    function RunCommand(const S: string): Boolean;
    procedure JumpSnap(DX, DY: Integer);
    function SnapLabel: string;
    function InkUnder(const R: TRect): Integer;
    function TipSpot(SX, SY, BoxW, BoxH: Integer): TRect;
    procedure TipAvoid(X0, Y0, X1, Y1: Integer);
    function TipOnLine(const R: TRect): Integer;
    procedure SetOriginHere;
    function CameraShowsSomething: Boolean;
    procedure ZoomAt(Factor: Double; AnchorSX, AnchorSY: Double);
    procedure SetScaleIdx(I: Integer);
    procedure PanBy(DX, DY: Double);
    procedure ViewMoved;
    procedure FlushView;
    { Travel is False when there is nothing to keep your bearings by: a
      drawing just loaded, a different sheet, a projection change. }
    procedure FitView(Travel: Boolean = True);
    { a new sheet: Key < 0 for a new untitled one-sheet file, else a sheet
      added to document Key }
    procedure NewDrawing(Key: Integer = -1);
    { the file in front, '' before it is saved }
    function DocPath: string;
    { the tabs of document Key, in order }
    function DocSheets(Key: Integer): TIntArrayW;
    { work in document Key that is not saved }
    function DocDirty(Key: Integer): Boolean;
    { tab I's caption: the file, the sheet when there are several, and a
      star when unsaved }
    function TabCaption(I: Integer): string;
    { Save, Don't save or Cancel about document Key; True when it may go }
    function AskToSave(Key: Integer; const Title: string): Boolean;
    function CloseDocument(Key: Integer): Boolean;
    { document Key to its file, asking for a name when it has none or when
      AskName; True when written }
    function SaveDocument(Key: Integer; AskName: Boolean): Boolean;
    procedure DoSaveAll;
    { a file opened as a document of its own, in tabs after the others }
    function OpenFile(const FileName: string): Boolean;
    { a file's sheets added after the existing tabs (see the body) }
    function ReadSheets(const FileName: string; Session: Boolean; out First: Integer): Boolean;
    { show tab First, framed when its file did not store a camera }
    procedure ShowLoaded(First: Integer);
    procedure RememberRecent(const Path: string);
    { the File menu, under the MENU button }
    procedure ShowFileMenu;
    procedure FileMenuClick(Sender: TObject);
    procedure RecentClick(Sender: TObject);
    procedure AddSheetHere;
    procedure DeleteSheetHere;
    procedure OfferRecovery;
    procedure DropDraft;
    procedure CloseDrawing(I: Integer);
    procedure SelectDrawing(I: Integer);
    procedure LayoutTabs;
    procedure PlaceTabs;

    { commands }
    procedure StartErase;
    procedure StepErase(Dt: Single);
    procedure DoSave;
    procedure DoSaveAs;
    procedure DoOpen;
    procedure DoExport;
    procedure DoPrint;
    { every sheet of the drawing, a page each, rather than only this one }
    procedure DoPrintSheets(All: Boolean);
    procedure DoPrintFull(const PngDir: string);
    procedure PrintTileMarks(Col, Row, Cols, Rows, PitchW, PitchH,
      SW, SH: Integer; const ScaleName: string);
    procedure CycleTheme(Step: Integer);
    procedure ApplyTheme;
    procedure SetLenPrecision(D: Integer);
    procedure SetEdgeWidth(V: Integer);
    procedure SetInk(C: TColor; Auto: Boolean = False);
    procedure SetUnits(U: TUnitSystem);
    procedure SetView(V: TViewKind);
    procedure ApplyViewPreset(I: Integer);
    procedure EnterFreeCamera(AtCorner: Boolean = False);
    procedure CycleViewPreset(Step: Integer);

    { deck }
    function DeckHit(X, Y: Integer): Integer;
    procedure DeckActivate(Index: Integer);
    procedure DoAction(A: Integer);
    function IconLit(Value: Integer): Boolean;
    function IconEnabled(Value: Integer): Boolean;

    { is the cursor on something a dimension may be anchored to? }
    function DimAnchored: Boolean;
    function ZoomReading: string;
    function StatusLine: string;
    procedure WashFace(C: TCanvas; Face: Integer; const Col: TPix);
    procedure TraceOutlineVisible(C: TCanvas; Idx: Integer; const Col: TPix; PenW: Integer);
    procedure TraceOutlineInto(S: TArtSurface; Idx: Integer;
      const Col: TPix; PenW: Single);
    procedure TraceOutline(C: TCanvas; const Hi: TPointFArray;
      const Col: TPix);
    procedure PaintOverlay(C: TCanvas);
    function TangentBulge(Pl: TPlane; out Bulge: Double): Boolean;
    procedure PaintGuideHover(C: TCanvas; I: Integer);
    { the cube: where it sits, what it draws, and the glide it starts }
    function CubeRect: TRect;
    function OverCube(X, Y: Integer): Boolean;
    function CubeZone(X, Y: Integer): Boolean;
    procedure PaintViewCube(C: TCanvas);
    procedure PaintCompass(C: TCanvas);
    function CubeMouse(X, Y: Integer; Down, Up: Boolean): Boolean;
    function TurnPivot: TP3;
    function FitTarget(OnSelection: Boolean; AzT, ElT: Double;
      out NewZoom, NewOX, NewOY: Double): Boolean;
    procedure GlideCamera(Az, El, Zoom, OX, OY: Double);
    procedure HoldTurn;
    procedure GlideTo(Az, El: Double);
    function OrbitSnapTarget(out T: TCubeTarget): Boolean;
    function ArcFillet(out F: TFillet; out Typed: Boolean): Boolean;
    function FilletCandidate(out F: TFillet): Boolean;
    function ArcDoubleClick(SX, SY: Integer): Boolean;
    procedure PaintUnderCursor(S: TArtSurface; OX, OY: Integer);
    procedure SnapOrbitToNearest;
    procedure StepCubeView(Key: Word);
    procedure StepGlide(Dt: Double);
    procedure PaintHeldPlane(C: TCanvas);

    { Session True: every sheet plus the comments a draft or handoff needs
      (document, file, saved or not).  Otherwise only document Key's sheets
      (all when Key < 0), as the file is written. }
    procedure BuildSession(L: TStrings; Session: Boolean = False; Key: Integer = -1; Quick: Boolean = False;
      ShownFirst: Boolean = False);
    procedure SaveDraft;
    function OnProgress(const What: string; Frac: Double): Boolean;
    function MachineText: string;
    procedure KeepReportCopy(const AName, Body: string; Shot: TStream);
    function LoadedWords: string;
    procedure EndBusy;
    function RestoreDraft: Boolean;
    procedure WriteHandoff;
    function RestoreHandoff: Boolean;
    function LoadExample: Boolean;
    procedure WriteExamples;
    procedure WriteJigs;
    procedure LoadSettings;
    procedure ApplyCommandLine;
    procedure FollowScreenSize;
    procedure SaveSettings;
    procedure ShowAbout;
    procedure ShowFacts(const Title, AText: string);
    procedure ShowLongText(const Title, AText: string);
  end;

var
  MainForm: TMainForm;

implementation

uses
  FileUtil, Clipbrd, LazUTF8, hsHelpDocs, hsHelpView, hsReportDialog, hsLongText, hsAbout,
  hsFacts;

{$R *.lfm}

{ S cut to fit Room pixels and ended with '...'.  Cuts whole characters,
  never a byte of one, so a name with accents does not end in a broken
  letter. }
function CutToFit(C: TCanvas; const S: string; Room: Integer): string;
var
  N: Integer;
begin
  Result := S;
  if C.TextWidth(Result) <= Room then Exit;
  N := UTF8Length(S);
  repeat
    Dec(N);
    Result := UTF8Copy(S, 1, N) + '...';
  until (N <= 0) or (C.TextWidth(Result) <= Room);
end;

function SketchAppName: string;
begin
  Result := 'heckers-sketch';
end;

const
  APP_NAME = 'Heckers Sketch';
  VIEW_NAMES: array[TViewKind] of string = ('PLAN', 'ISO', '3D');
  CRASH_LOG = 'heckers-sketch-crash.txt';
  { so a crash report says which build it came from }
  BUILD_STAMP = {$I %DATE%} + ' ' + {$I %TIME%};

  { deck groups }
  GRP_ICON  = 3;
  GRP_SCALE = 5;
  GRP_SNAP  = 6;
  GRP_TOOL  = 7;
  GRP_POPUP = 8;   { a button that opens a list rather than setting a value }
  GRP_TOGGLE = 9;  { a button that is simply on or off, and says which }

  { the lists those buttons open }
  POP_NONE  = -1;
  POP_SCALE = 0;
  POP_SNAP  = 1;
  POP_COLOR = 2;
  POP_WIDTH  = 3;
  { The help button opens a list: the web page, manual, downloads, bug
    reporting and the update check. }
  POP_HELP   = 4;
  { The shop tools: making the thing rather than drawing it (unfold, the
    fitting builders). }
  POP_SHOP   = 5;
  POP_PREC   = 6;
  { the rest of the tools, behind one door; see MAIN_TOOLS }
  POP_MORE   = 7;
  { Every typed command with a word about each: the arrow beside the prompt.
    The only list too long to fit, so it scrolls. }
  POP_CMDS   = 8;

type
  { a typed command, as the list shows it }
  TCmdItem = record
    Name: string;      { what to type, without the slash }
    Hint: string;      { what it does, in a few words }
    Arg: Boolean;      { True when it wants something after it }
    { An example line shown in place of the hint while the row is
      highlighted.  Only commands that take an argument have one.  FPC lets a
      trailing field be left off a record constant, so most rows omit it. }
    Eg: string;
    { Other words that run it, space separated (/e for /erase).  Typing one
      finds the row and counts as using the command.  tests/cmdcheck.pas
      checks every word is handled by the same RunCommand branch. }
    Also: string;
  end;

const
  { Alphabetical, with recently used ones floated to the top.  One row per
    action; the other words for it are in Also. }
  CMD_LIST: array[0..89] of TCmdItem = (
    (Name: 'all';        Hint: 'select everything on this sheet';      Arg: False; Eg: ''; Also: 'selectall'),
    (Name: 'arc';        Hint: 'the arc tool';                          Arg: False; Eg: ''; Also: 'a'),
    (Name: 'back';       Hint: 'look from behind';                      Arg: False),
    (Name: 'center';     Hint: 'center it on the floor at 0,0';         Arg: False; Eg: ''; Also: 'middle'),
    (Name: 'circle';     Hint: 'the circle tool';                       Arg: False; Eg: ''; Also: 'c'),
    (Name: 'clear';      Hint: 'empty this sheet';                      Arg: False),
    (Name: 'close';      Hint: 'close this file - every sheet of it';   Arg: False),
    (Name: 'corner';     Hint: 'look from a corner';                    Arg: False),
    (Name: 'cube';       Hint: 'the view cube: on, off, tl/tr/bl/br';    Arg: False;
                         Eg:   '/cube tr';
                         Also: 'viewcube'),
    (Name: 'cut';        Hint: 'the plan slice: two heights, or "all"'; Arg: True;
                         Eg:   '/cut 0 9''';
                         Also: 'slice'),
    (Name: 'detach';     Hint: 'move a line away on its own: on, off';  Arg: False;
                         Eg:   '/detach on';
                         Also: 'loose'),
    (Name: 'dimension';  Hint: 'the dimension tool';                    Arg: False; Eg: ''; Also: 'dim'),
    (Name: 'drill';      Hint: 'push a shape right through';            Arg: False; Eg: ''; Also: 'bore punch'),
    (Name: 'edit';       Hint: 'work inside the picked group';          Arg: False; Eg: ''; Also: 'opengroup'),
    (Name: 'erase';      Hint: 'the eraser';                            Arg: False; Eg: ''; Also: 'e del'),
    (Name: 'example';    Hint: 'the example drawing, as a new drawing';  Arg: False),
    (Name: 'explode';    Hint: 'take the picked group apart';           Arg: False; Eg: ''; Also: 'ungroup'),
    (Name: 'fit';        Hint: 'zoom until it all shows';               Arg: False; Eg: ''; Also: 'zoom'),
    (Name: 'forget';     Hint: 'forget the areas seen, and work them out again'; Arg: False),
    (Name: 'front';      Hint: 'look from the front';                   Arg: False),
    (Name: 'grid';       Hint: 'the ruled paper, on or off';            Arg: False),
    (Name: 'group';      Hint: 'make what is picked a group';           Arg: False; Eg: ''; Also: 'makegroup'),
    (Name: 'groups';     Hint: 'the groups panel: on, off';             Arg: False;
                         Eg:   '/groups off';
                         Also: 'outliner'),
    (Name: 'guides';     Hint: 'clear the guide lines';                 Arg: False; Eg: ''; Also: 'noguides'),
    (Name: 'help';       Hint: 'about this program';                    Arg: False; Eg: ''; Also: '?'),
    (Name: 'hide';       Hint: 'put away the picked groups, or every group so named';  Arg: True;
                         Eg:   '/hide labels';
                         Also: 'putaway'),
    (Name: 'holes';      Hint: 'draw where a solid is not closed';      Arg: False; Eg: ''; Also: 'openedges notclosed'),
    (Name: 'info';       Hint: 'the entity panel: on, off';            Arg: False;
                         Eg:   '/info on';
                         Also: 'entity properties'),
    (Name: 'iso';        Hint: 'the isometric view';                    Arg: False),
    (Name: 'jig';        Hint: 'run the picked group''s jig again, or every jig';  Arg: False; Eg: ''; Also: 'jigs'),
    (Name: 'keep';       Hint: 'the last tape run, kept as a dimension';   Arg: False; Eg: ''; Also: 'keepdim'),
    (Name: 'leave';      Hint: 'close the open group';                  Arg: False; Eg: ''; Also: 'closegroup'),
    (Name: 'left';       Hint: 'look from the left';                    Arg: False),
    (Name: 'light';      Hint: 'light that follows the camera: on, off';  Arg: False;
                         Eg:   '/light off';
                         Also: 'lamp'),
    (Name: 'line';       Hint: 'the line tool';                         Arg: False; Eg: ''; Also: 'l'),
    (Name: 'lock';       Hint: 'lock the picked group';                 Arg: False),
    (Name: 'manual';     Hint: 'open the manual';                       Arg: False; Eg: ''; Also: 'docs'),
    (Name: 'measure';    Hint: 'the tape measure';                      Arg: False; Eg: ''; Also: 'm tape'),
    (Name: 'move';       Hint: 'the move tool';                         Arg: False; Eg: ''; Also: 'mv'),
    (Name: 'name';       Hint: 'call the picked group something';      Arg: True;
                         Eg:   '/name Left knob';
                         Also: 'rename'),
    (Name: 'new';        Hint: 'a new drawing - a file of its own';      Arg: False; Eg: ''; Also: 'tab'),
    (Name: 'offset';     Hint: 'a parallel copy of a face''s edge';     Arg: False; Eg: ''; Also: 'f'),
    (Name: 'orbit';      Hint: 'the free camera';                       Arg: False; Eg: ''; Also: 'spin'),
    (Name: 'origin';     Hint: 'put the view back on 0,0,0';            Arg: False; Eg: ''; Also: 'o'),
    (Name: 'plan';       Hint: 'look straight down';                    Arg: False; Eg: ''; Also: '2d flat'),
    (Name: 'plane';      Hint: 'the working plane: xy, xz or yz';       Arg: True;
                         Eg:   '/plane xz'),
    (Name: 'postcard';   Hint: 'the once-only note to the authors, to send or read';  Arg: False; Eg: ''; Also: 'hello'),
    (Name: 'print';      Hint: 'this sheet - or "all", or "full"';      Arg: True;
                         Eg:   '/print all'),
    (Name: 'protractor'; Hint: 'lay a guide at an angle';               Arg: False; Eg: ''; Also: 'angle'),
    (Name: 'push';       Hint: 'push or pull a face';                   Arg: False; Eg: ''; Also: 'pull pushpull p'),
    (Name: 'quick';      Hint: 'quick frames while the camera moves';   Arg: False),
    (Name: 'radiant';    Hint: 'lay radiant tube out over the selected floor'; Arg: False; Eg: ''; Also: 'pex hydronic'),
    (Name: 'rebuild';    Hint: 'work the faces out again';              Arg: False),
    (Name: 'rect';       Hint: 'the rectangle tool';                    Arg: False; Eg: ''; Also: 'rectangle r'),
    (Name: 'redo';       Hint: 'put back what was undone';              Arg: False),
    (Name: 'reface';     Hint: 'throw the flat faces away and rebuild'; Arg: False; Eg: ''; Also: 'rebuildfaces'),
    (Name: 'regions';    Hint: 'report the flat areas found';           Arg: False),
    (Name: 'rendertime'; Hint: 'time a whole frame';                    Arg: False),
    (Name: 'replay';     Hint: 'play back a session from a report';     Arg: False;
                         Eg:   '/replay session.txt'),
    (Name: 'report';     Hint: 'send a bug report, with a picture';     Arg: False; Eg: ''; Also: 'bug'),
    (Name: 'resize';     Hint: 'retype a picked dimension';             Arg: True;
                         Eg:   '/resize 4''6"';
                         Also: 'size'),
    (Name: 'reverse';    Hint: 'turn the picked faces over';            Arg: False; Eg: ''; Also: 'rev flip'),
    (Name: 'revolve';    Hint: 'spin or sweep a face into a solid';     Arg: False; Eg: ''; Also: 'followme follow lathe'),
    (Name: 'right';      Hint: 'look from the right';                   Arg: False),
    (Name: 'rotate';     Hint: 'the rotate tool';                       Arg: False; Eg: ''; Also: 'q turn'),
    (Name: 'save';       Hint: 'save this file';                        Arg: False),
    (Name: 'saveall';    Hint: 'save every file with changes';          Arg: False),
    (Name: 'saveas';     Hint: 'save it under a new name';              Arg: False),
    (Name: 'scale';      Hint: 'the print scale: 1/4", 1" and so on';   Arg: True;
                         Eg:   '/scale 1/4"'),
    (Name: 'select';     Hint: 'the select tool';                       Arg: False; Eg: ''; Also: 's'),
    (Name: 'session';    Hint: 'what has happened, most recent last';   Arg: False;
                         Eg:   '/session session.txt';
                         Also: 'acts'),
    (Name: 'sheet';      Hint: 'add a sheet to this file';              Arg: False),
    (Name: 'show';       Hint: 'bring back what was put away - all, or the groups so named';  Arg: True;
                         Eg:   '/show labels';
                         Also: 'unhide'),
    (Name: 'source';     Hint: 'this sheet as its text, picked both ways';  Arg: False;
                         Eg:   '/source complete off';
                         Also: 'src text-view'),
    (Name: 'spool';      Hint: 'the pipe spool scratchpad';             Arg: False; Eg: ''; Also: 'pipe scratchpad'),
    (Name: 'stairs'; Hint: 'a straight stair - on two picked lines, or typed and placed'; Arg: False; Eg: ''; Also: 'stair'),
    (Name: 'state';      Hint: 'what a report says about the program right now'; Arg: False),
    (Name: 'sysinfo';    Hint: 'what a report says about this machine'; Arg: False; Eg: ''; Also: 'machine'),
    (Name: 'text';       Hint: 'a note on the drawing';                 Arg: False; Eg: ''; Also: 'note n'),
    (Name: 'threads';    Hint: 'background work, on or off';            Arg: False),
    (Name: 'timings';    Hint: 'time each step: on, then again to see them'; Arg: False;
                         Eg:   '/timings show'),
    (Name: 'top';        Hint: 'look from above';                       Arg: False; Eg: ''; Also: 'down'),
    (Name: 'tozero';     Hint: 'put its near bottom corner on 0,0,0';   Arg: False; Eg: ''; Also: 'zero tuck'),
    (Name: 'transition'; Hint: 'build a duct fitting';                  Arg: False; Eg: ''; Also: 'trans fitting elbow tee'),
    (Name: 'undo';       Hint: 'undo the last thing';                   Arg: False; Eg: ''; Also: 'u'),
    (Name: 'unfold';     Hint: 'lay a piece out flat';                  Arg: False; Eg: ''; Also: 'layout'),
    (Name: 'units';      Hint: 'feet and inches, or millimeters';       Arg: False),
    (Name: 'unlock';     Hint: 'unlock the picked group';               Arg: False),
    (Name: 'update';     Hint: 'look for a newer build';                Arg: False;
                         Eg:   '/update never';
                         Also: 'upgrade'),
    (Name: 'whatsnew';   Hint: 'the release notes';                     Arg: False; Eg: ''; Also: 'changes'));

const

  { How finely lengths are written, and what the last field of a dashed entry
    counts in.  Sixteenths are the default. }
  PREC_DENOMS: array[0..6] of Integer = (2, 4, 8, 16, 32, 64, 100);

  { pen widths the list offers: a few fixed steps, not a slider }
  PEN_STEPS = 6;
  PEN_SIZES: array[0..PEN_STEPS - 1] of Integer = (1, 2, 4, 6, 10, 16);

  { icon actions }
  ACT_UNDO    = 0;
  ACT_REDO    = 1;
  ACT_SAVE    = 3;
  ACT_PRINT   = 4;
  ACT_THEME   = 6;
  ACT_GRID    = 7;
  ACT_HELP    = 8;
  ACT_UNITS   = 11;
  ACT_ORIGIN  = 13;
  ACT_FIT     = 14;
  ACT_OPEN    = 15;
  ACT_EXPORT  = 16;
  { Past this many picked, the selection overlay skips the depth test and
    just outlines the edges; at that size tracing is the cost on every
    orbit frame. }
  SEL_TRACE_MAX = 3000;

  ACT_GUIDES  = 17;
  ACT_NOGUIDE = 18;
  ACT_MENU    = 19;

  UNDO_LEVELS     = 16;
  { where the cube can sit, in the words the command takes }
  CORNER_NAME: array[0..3] of string =
    ('top left', 'top right', 'bottom left', 'bottom right');

  { Zoom limits.  Wide enough for a site plan at one end and a weld bead at
    the other, but bounded so OX + dot * Ppu stays in a range the rasterizer
    and depth mesh can handle. }
  ZOOM_MIN        = 0.002;
  ZOOM_MAX        = 2000.0;

  TICK_MS         = 16;
  { how long a camera move takes: long enough to follow, short enough that
    nobody waits }
  GLIDE_SECONDS   = 0.34;
  MIN_PEN         = 1;
  MAX_PEN         = 40;
  SNAP_PX         = 16.0;   // pulling onto a point on the drawing
  INFER_PX        = 7.0;    // lining up with one that is somewhere else
  FAST_PX_S       = 600.0;  // moving quicker than this, alignments wait
  KEEP_FACTOR     = 1.7;    // an alignment taken holds this much further out
  HOLD_PX         = 18.0;   // ...or with one you deliberately rested on
  { how long the button is leaned on before the line snaps off, and how long
    the ends recoil }
  HOLD_STRAIN     = 0.20;   // before this it is just a click being made
  HOLD_BREAK      = 0.70;   // and this long to break; longer feels like waiting
  SNAP_RECOIL     = 0.30;
  AXIS_PX         = 8.0;    // how near the axis through a reference counts
  { View turn per pixel of drag, for a press halfway out from the middle.
    OrbitGainAt scales it from half this at the middle to twice at the edge.
    Matched to SketchUp's feel. }
  ORBIT_RAD_PX    = 0.006;
  LOCK_PX         = 7.5;    // this close and the point is what you meant
  { once taken, a point holds until the cursor is this far off it, so a
    small twitch does not drop the snap }
  STICK_PX        = 20.0;
  PIECE_PX        = 5.0;    // ...and this close for the middle of a piece
  EDGE_PX         = 11.0;   // hovering a line means a point on that line
  { the face under the cursor, tinted the way SketchUp tints one }
  HINT_BLUE: TPix = (B: $F2; G: $B4; R: $76; A: 255);
  AXIS_MIN_PX     = 14.0;   // nearer than this an axis lock says nothing
  DWELL_MS        = 450;    // rest on a point this long to keep it
  { SketchUp's default: round enough to read as a circle, few enough that a
    push does not bury the drawing in walls (each segment becomes one). }
  CIRCLE_SEGS     = 24;
  { enough points for an arc in a face outline to read as a curve; each one
    becomes a wall if the face is pulled }
  ARC_SEGS        = 16;

type
  TViewPreset = record
    Name: string;
    View: TViewKind;
    Az, El: Double;
  end;

const
  ISO_EL = 35.264 * Pi / 180;   // the true isometric tilt
  { the first two presets are the paper modes; the button cycles from here }
  FIRST_CAMERA_PRESET = 2;
  VIEW_ARROW_W = 30;    // the drop-down arrow's share of the view button

  { The views one key steps through: the four corners first, since that is
    what you draw from, then elevations and top for reading dimensions. }
  VIEW_PRESETS: array[0..10] of TViewPreset = (
    (Name: 'PLAN';              View: vkPlan;  Az: 0;           El: 0),
    (Name: 'ISO';               View: vkIso;   Az: 0;           El: 0),
    (Name: 'CORNER FRONT-LEFT'; View: vkOrbit; Az: -Pi / 4;     El: ISO_EL),
    (Name: 'CORNER FRONT-RIGHT';View: vkOrbit; Az: Pi / 4;      El: ISO_EL),
    (Name: 'CORNER BACK-RIGHT'; View: vkOrbit; Az: 3 * Pi / 4;  El: ISO_EL),
    (Name: 'CORNER BACK-LEFT';  View: vkOrbit; Az: -3 * Pi / 4; El: ISO_EL),
    (Name: 'FRONT';             View: vkOrbit; Az: 0;           El: 0),
    (Name: 'RIGHT';             View: vkOrbit; Az: Pi / 2;      El: 0),
    (Name: 'BACK';              View: vkOrbit; Az: Pi;          El: 0),
    (Name: 'LEFT';              View: vkOrbit; Az: -Pi / 2;     El: 0),
    (Name: 'TOP';               View: vkOrbit; Az: 0;           El: 1.45));
  PRINT_DPI       = 150;

  { one glyph per tool, for the button and for the cursor }
  TOOL_ICONS: array[TTool] of TIconKind =
    (ikTSelect, ikTMove, ikTLine, ikTRect, ikTArc, ikTCircle, ikTPush,
     ikTText, ikTErase, ikTMeasure, ikDim, ikTOrbit, ikTOffset, ikTRotate,
     ikTProtractor, ikTDrill, ikTFollow);

  TOOL_NAMES: array[TTool] of string =
    ('SELECT', 'MOVE', 'LINE', 'RECT', 'ARC', 'CIRCLE', 'PUSH/PULL', 'TEXT',
     'ERASE', 'MEASURE', 'DIMENSION', 'ORBIT', 'OFFSET', 'ROTATE',
     'PROTRACTOR', 'DRILL', 'REVOLVE');

  { The strip shows the tools a drawing is made of; the rest wait behind
    MORE, one click away.  Fourteen buttons of equal weight scare people off.
    Orbit is here although it draws nothing, because a laptop without a
    middle button has no other way to get round the model. }
  MAIN_TOOLS: array[0..13] of TTool =
    (ptSelect,
     ptLine, ptRect, ptCircle, ptArc,
     ptPush, ptFollow,
     ptMove, ptErase,
     ptMeasure, ptProtractor, ptDim, ptText,
     ptOrbit);
  { where dividers go across the strip, after this many buttons: pick, draw,
    stand up, change, measure and label, get about }
  MAIN_BREAKS: array[0..4] of Integer = (1, 5, 7, 9, 13);
  { the less common tools, behind MORE }
  MORE_TOOLS: array[0..2] of TTool =
    (ptRotate, ptOffset, ptDrill);

  GRP_COLS: array[0..2] of Integer = (3, 3, 3);
  GRP_N:    array[0..2] of Integer = (6, 5, 6);
  TOOL_GROUPS: array[0..2, 0..5] of TTool =
    ((ptSelect, ptMove, ptRotate, ptErase, ptPush, ptDrill),
     (ptLine, ptRect, ptCircle, ptArc, ptFollow, ptSelect),
     (ptMeasure, ptProtractor, ptDim, ptText, ptOffset, ptOrbit));

  TOOL_HINTS: array[TTool] of string = (
    'Select - click to pick, drag a box for several.  Ctrl adds, Shift ' +
      'toggles, Ctrl+Shift takes away.  (Space)',
    'Move - pick a point on what is selected, then click where it goes.  ' +
      'Hold Ctrl to leave a copy behind.  (M)',
    'Line - click a start point, then click the end or just type a length.  In a 3D view the arrows lock the plane first: left or right for upright, up or down for flat, Esc to let go.  A locked plane holds every point of the shape to it.',
    'Rectangle - click two opposite corners, or type 12''x8''.  Makes a face.',
    'Arc - pick two points, then pull the middle out.  Joins two loose ends.',
    'Circle - pick the center, then type or drag the radius.',
    'Push/pull - click a face and type how far to lift it.  Close a loop of ' +
      'lines to make a face.',
    'Text - click where the note goes and type it.',
    'Erase - click an edge to delete it; a face goes when its edges do.',
    'Measure - click two points and read the distance between them.',
    'Dimension - click two points, then drag away to place the line.',
    'Orbit - drag to spin.  Shift pans, Ctrl clicks into the nearest view.  (O)',
    'Offset - click a face, then move in or out and click, or type a wall ' +
      'thickness.  (F)',
    'Rotate - click the center, a point to measure from, then swing to the ' +
      'angle or type it (34.1, or 8:12 for a slope).  Arrows pick the ' +
      'plane, Ctrl leaves a copy.  (Q)',
    'Protractor - click the vertex, a point to measure from, then the ' +
      'angle, or type it.  Lays a guide line at that angle.',
    'Drill - push a shape through everything.  Where the hole crosses a ' +
      'tunnel already there, both are cut open into each other.  (B)',
    'Revolve - spin a face round an axis into a solid.  Draw the outline of ' +
      'half of it, click the face, then click two points on the axis - or a ' +
      'circle to follow round.  Type an angle first for a part turn.  This ' +
      'is SketchUp''s Follow Me, and it will also sweep a face along a line.');

  { how close the cursor must be to a guide to point at it.  Tighter than an
    edge on purpose (see PickAt). }
  GUIDE_PICK_PX = 4;

  { TColor is $00BBGGRR }
  PALETTE: array[0..11] of TColor = (
    $1A1A1A, $FFFFFF, $A8A4A0, $2A2AE2, $1A7AFF, $1AC6FF,
    $3CDC7A, $5AB422, $C8C81E, $F06034, $EB5096, $AA3CEB);

{ ======================================================================== }
{ small helpers                                                             }
{ ======================================================================== }

{ A dot for the decimal point whatever the locale, so the log parses back. }
function ActFS: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
end;

function TMainForm.Theme: TTheme;
begin
  Result := Themes[FThemeIdx];
end;

function TMainForm.CurScale: TDrawScale;
begin
  Result := ScaleTable(FD.Units, FD.ScaleIdx);
end;

{ Pixels per world unit on screen.  The drawing scale sets the true size and
  FD.Zoom only magnifies it, so zooming never changes what prints. }
function TMainForm.Ppu: Double;
begin
  Result := PixelsPerUnit(FD.Units, CurScale, Screen.PixelsPerInch) * FD.Zoom;
end;

function TMainForm.SnapStep: Double;
begin
  Result := SnapValue(FD.Units, FD.SnapIdx);
end;

function TMainForm.Proj: TProjector;
begin
  Result.Kind := FD.View;
  Result.Ppu := Ppu;
  Result.OX := FD.ViewX;
  Result.OY := FD.ViewY;
  Result.Az := FD.Az;
  Result.El := FD.El;
end;

function TMainForm.ScreenOf(const P: TP3): TPointF;
begin
  Result := Project(Proj, P);
end;

function TMainForm.WorldAt(SX, SY: Double): TP3;
var
  Base: TP3;
begin
  Base := FCur;
  { A locked plane is pinned to where the shape started, not to where the
    cursor has wandered.  If it followed the cursor, one inference off the
    plane would move it and the outline would never close into a face. }
  if FPlaneHeld and (FStage > 0) then Base := FP1;
  { In a plan with a cut, the bottom of the slice is the drawing plane: set
    it to 9'-0" and you are drawing on the second story. }
  if (FD.View = vkPlan) and FD.SliceOn then Base.Z := FD.SliceLo;
  Result := Unproject(Proj, SX, SY, FD.Plane, Base);
end;

{ The four corners of the rectangle with A and B at opposite corners, in the
  working plane.  The third coordinate stays at A's, which keeps it flat and
  gives its face a usable normal. }
function RectCorners(const A, B: TP3; Pl: TPlane): TP3Array;
var
  FO, FU, FV, FN, D: TP3;
  Du, Dv: Double;
begin
  Result := nil;
  SetLength(Result, 4);
  if Pl = plFree then
  begin
    { laid out along the plane's own two directions, not world axes, so a
      rectangle can be drawn on a roof }
    GetFreePlane(FO, FU, FV, FN);
    D := P3(B.X - A.X, B.Y - A.Y, B.Z - A.Z);
    Du := D.X * FU.X + D.Y * FU.Y + D.Z * FU.Z;
    Dv := D.X * FV.X + D.Y * FV.Y + D.Z * FV.Z;
    Result[0] := A;
    Result[1] := P3(A.X + FU.X * Du, A.Y + FU.Y * Du, A.Z + FU.Z * Du);
    Result[2] := P3(Result[1].X + FV.X * Dv, Result[1].Y + FV.Y * Dv,
                    Result[1].Z + FV.Z * Dv);
    Result[3] := P3(A.X + FV.X * Dv, A.Y + FV.Y * Dv, A.Z + FV.Z * Dv);
    Exit;
  end;
  case Pl of
    plXZ:
      begin
        Result[0] := P3(A.X, A.Y, A.Z);
        Result[1] := P3(B.X, A.Y, A.Z);
        Result[2] := P3(B.X, A.Y, B.Z);
        Result[3] := P3(A.X, A.Y, B.Z);
      end;
    plYZ:
      begin
        Result[0] := P3(A.X, A.Y, A.Z);
        Result[1] := P3(A.X, B.Y, A.Z);
        Result[2] := P3(A.X, B.Y, B.Z);
        Result[3] := P3(A.X, A.Y, B.Z);
      end;
  else
    begin
      Result[0] := P3(A.X, A.Y, A.Z);
      Result[1] := P3(B.X, A.Y, A.Z);
      Result[2] := P3(B.X, B.Y, A.Z);
      Result[3] := P3(A.X, B.Y, A.Z);
    end;
  end;
end;

{ the two side lengths of that rectangle, in the plane's own order }
procedure RectSides(const A, B: TP3; Pl: TPlane; out W, H: Double);
var
  FO, FU, FV, FN, D: TP3;
begin
  if Pl = plFree then
  begin
    GetFreePlane(FO, FU, FV, FN);
    D := P3(B.X - A.X, B.Y - A.Y, B.Z - A.Z);
    W := Abs(D.X * FU.X + D.Y * FU.Y + D.Z * FU.Z);
    H := Abs(D.X * FV.X + D.Y * FV.Y + D.Z * FV.Z);
    Exit;
  end;
  case Pl of
    plXZ: begin W := Abs(B.X - A.X); H := Abs(B.Z - A.Z); end;
    plYZ: begin W := Abs(B.Y - A.Y); H := Abs(B.Z - A.Z); end;
  else    begin W := Abs(B.X - A.X); H := Abs(B.Y - A.Y); end;
  end;
end;

function TMainForm.SnapToGrid(const P: TP3): TP3;
var
  S: Double;
begin
  S := SnapStep;
  if S <= 0 then
    Result := P
  else
    Result := P3(Round(P.X / S) * S, Round(P.Y / S) * S, Round(P.Z / S) * S);
end;

{ Points on the drawing beat the grid, as in SketchUp.  Failing a direct hit,
  the cursor is pulled into line with a point sharing one of its coordinates,
  and a guide is shown back to it. }
function TMainForm.ResolveSnapRaw(SX, SY: Double): TP3;
var
  Hit: TSnapHit;
  Pts: TP3Array;
  I, BestAxis, Near: Integer;
  Tol, Best, KeepTol: Double;
  PrevGuide: Boolean;
  PrevFrom: TP3;
  W, Wf, AxRef, AxPt, EdgeP, EdgeA, EdgeB, MidP, AxSnapP: TP3;
  SP: TPointF;
  PtOK: Boolean;
  PtPx, AxPx: Double;
  AxIdx, EdgeI, AxSnapK: Integer;

  { An alignment is only shown when the point differs in exactly one
    direction, so the guide is a clean axis-parallel line.  (In plan every
    point shares Z, so allowing two would drag the guide to stray corners.) }
  procedure Consider(const C: TP3);
  var
    DX, DY, DZ, Score: Double;
    Big: Integer;
  begin
    DX := Abs(W.X - C.X);
    DY := Abs(W.Y - C.Y);
    DZ := Abs(W.Z - C.Z);

    Big := 0;
    if DX > Tol then Inc(Big);
    if DY > Tol then Inc(Big);
    if DZ > Tol then Inc(Big);
    if Big <> 1 then Exit;

    { and only when it is far enough away to be a visible guide }
    if Dist(W, C) * Ppu < 18 then Exit;

    Score := DX + DY + DZ;
    if DX > Tol then Score := Score - DX
    else if DY > Tol then Score := Score - DY
    else Score := Score - DZ;

    if Score < Best then
    begin
      Best := Score;
      BestAxis := 1;          // marks "found"; the axes are snapped below
      FGuideFrom := C;
    end;
  end;

  { The second half of a compound inference.  With an axis pinning two
    coordinates, the third can still be pulled level with a held point.
    This is what closes a rectangle square: run along red from the top
    corner and land on the X of the corner you rested on earlier. }
  procedure AlignFree(var Q: TP3; FreeAxis: Integer);
  var
    I: Integer;
    APts: TP3Array;
    Cur, BestOff: Double;
    BestPt: TP3;
    Got: Boolean;

    function Coord(const C: TP3): Double;
    begin
      case FreeAxis of
        0: Result := C.X;
        1: Result := C.Y;
      else Result := C.Z;
      end;
    end;

    function TryLevel(const C: TP3; Tol: Double): Boolean;
    var
      Off: Double;
    begin
      Result := False;
      Off := Abs(Coord(C) - Cur) * Ppu;
      if Off > Tol then Exit;
      { it has to be somewhere else, or the guide is a dot on the cursor }
      if Dist(Q, C) * Ppu < 18 then Exit;
      if Off >= BestOff then Exit;
      BestOff := Off;
      BestPt := C;
      Got := True;
      Result := True;
    end;

  begin
    Cur := Coord(Q);
    BestOff := 1E30;
    Got := False;

    { A point you rested on was asked for, so it goes first and holds from
      much further out than one the engine merely noticed. }
    if not (FLockOn and TryLevel(FLockPt, HOLD_PX)) then
    begin
      { leveling with other points waits for a slow hand }
      if FMoveSpeed <= FAST_PX_S then
      begin
        FD.Doc.SnapPoints(APts);
        for I := 0 to High(APts) do TryLevel(APts[I], INFER_PX);
        if FStage > 0 then TryLevel(FP1, INFER_PX);
      end;
    end;
    if not Got then Exit;

    case FreeAxis of
      0: Q.X := BestPt.X;
      1: Q.Y := BestPt.Y;
    else Q.Z := BestPt.Z;
    end;
    FGuide := True;
    FGuideFrom := BestPt;
  end;

  { One direction offered from a reference point.  Kind 0, 1, 2 for the
    axes, 3 parallel to the reference edge, 4 perpendicular to it.
    Measured on screen against the axis as drawn, not in model space: in
    iso or 3D, unprojecting pins one coordinate to the working plane, so a
    model-space test can never see blue (risers came out as diagonals). }
  procedure DirTry(const R, AD0: TP3; Kind: Integer);
  var
    Off, Along, T, LenSq: Double;
    PR, PA: TPointF;
    AD: TP3;
    UX, UY, VX, VY: Double;
  begin
    AD := Norm3(AD0);
    if Sqr(AD.X) + Sqr(AD.Y) + Sqr(AD.Z) < 0.5 then Exit;
    PR := ScreenOf(R);
    begin
      PA := ScreenOf(P3(R.X + AD.X, R.Y + AD.Y, R.Z + AD.Z));
      UX := PA.X - PR.X;
      UY := PA.Y - PR.Y;
      LenSq := UX * UX + UY * UY;

      { An axis pointing nearly at the camera projects to a stub: every
        cursor position is "on" it, and the distance along it blows up past
        1E12, which crashed the rubber band.  A unit must project to at least
        a fifth of a square-on unit, so axes steeper than about 78 degrees are
        ignored.  Only the free camera can get there. }
      if LenSq < Sqr(0.2 * Ppu) then Exit;

      VX := SX - PR.X;
      VY := SY - PR.Y;
      Along := (VX * UX + VY * UY) / LenSq;      // in axis units
      Off := Abs(VX * UY - VY * UX) / Sqrt(LenSq);

      if Abs(Along) * Sqrt(LenSq) < AXIS_MIN_PX then Exit;
      if Off < AxPx then
      begin
        { reject NaN, infinity, or anything further out than a drawing could be }
        T := Along;
        if IsNan(T) or IsInfinite(T) or (Abs(T) > 1E9) then Exit;
        AxPx := Off;
        AxIdx := Kind;
        AxRef := R;
        { the point on the axis nearest the cursor, in the model }
        AxPt := P3(R.X + AD.X * T, R.Y + AD.Y * T, R.Z + AD.Z * T);
      end;
    end;
  end;

  { where the axis through R crosses the edge A-B, if they actually meet:
    the point on the edge }
  function AxisMeetsEdge(const R: TP3; Axis: Integer; const A, B: TP3;
    out P: TP3): Boolean;
  var
    D, E, W: TP3;
    A2, B2, D2, DD, EE, DE, T, U, Den: Double;
  begin
    Result := False;
    case Axis of
      0: D := P3(1, 0, 0);
      1: D := P3(0, 1, 0);
    else D := P3(0, 0, 1);
    end;
    E := P3(B.X - A.X, B.Y - A.Y, B.Z - A.Z);
    W := P3(A.X - R.X, A.Y - R.Y, A.Z - R.Z);
    DD := Dot3(D, D); EE := Dot3(E, E); DE := Dot3(D, E);
    Den := DD * EE - DE * DE;
    if (EE < 1E-18) or (Abs(Den) < 1E-12 * DD * EE) then Exit;   { parallel }
    A2 := Dot3(D, W); B2 := Dot3(E, W);
    T := (A2 * EE - B2 * DE) / Den;         { along the axis }
    U := (A2 * DE - B2 * DD) / Den;         { along the edge, 0..1 }
    if (U < -1E-9) or (U > 1 + 1E-9) then Exit;
    P := P3(A.X + E.X * U, A.Y + E.Y * U, A.Z + E.Z * U);
    { the two lines have to actually meet, not just pass near }
    D2 := Sqr(R.X + D.X * T - P.X) + Sqr(R.Y + D.Y * T - P.Y) + Sqr(R.Z + D.Z * T - P.Z);
    Result := D2 < 1E-12;
  end;

  procedure AxisTry(const R: TP3);
  begin
    DirTry(R, P3(1, 0, 0), 0);
    DirTry(R, P3(0, 1, 0), 1);
    DirTry(R, P3(0, 0, 1), 2);
  end;

  { parallel to the reference edge, and square to it in the working plane
    (SketchUp's magenta pair) }
  procedure ParPerpTry(const R: TP3);
  var
    AU, AV, Nm, Perp: TP3;
  begin
    if not FParHas then Exit;
    DirTry(R, FParDir, 3);
    PlaneAxes(FD.Plane, AU, AV);
    Nm := Cross3(AU, AV);
    Perp := Cross3(Nm, FParDir);
    if Sqr(Perp.X) + Sqr(Perp.Y) + Sqr(Perp.Z) > 1E-12 then
      DirTry(R, Perp, 4);
  end;

begin
  PrevGuide := FGuide;
  PrevFrom := FGuideFrom;
  FGuide := False;
  FAxisLock := -1;

  { SNAP OFF means off: no grid, no points, no guides. }
  if SnapStep <= 0 then
  begin
    FSnapKind := snNone;
    Exit(WorldAt(SX, SY));
  end;

  Wf := WorldAt(SX, SY);

  { Still holding the last point?  A point is taken from close in and
    released from much further out, so a small slide does not drop it (as in
    SketchUp).  Only real points; a grid intersection has nothing to stick to. }
  if FStickOn and (FStickKind in [snEndpoint, snMidpoint, snCenter, snCross,
                                  snSubMid]) then
  begin
    SP := ScreenOf(FStickPt);
    if Sqr(SX - SP.X) + Sqr(SY - SP.Y) <= Sqr(STICK_PX * FUIScale) then
    begin
      FSnapKind := FStickKind;
      Exit(FStickPt);
    end;
    FStickOn := False;
  end;

  PtOK := FD.Doc.BestSnap(Proj, SX, SY, SNAP_PX, Hit);
  PtPx := 1E30;
  if PtOK then
  begin
    SP := ScreenOf(Hit.P);
    PtPx := Sqrt(Sqr(SX - SP.X) + Sqr(SY - SP.Y));
  end;

  { A definite point right under the cursor wins outright.  Piece midpoints
    do not count: they appear at every quarter point of split lines and would
    steal the cursor. }
  if PtOK and (PtPx <= LOCK_PX) and
     (Hit.Kind in [snEndpoint, snCross, snCenter, snMidpoint, snOrigin]) then
  begin
    FSnapKind := Hit.Kind;
    FStickOn := True;
    FStickPt := Hit.P;
    FStickKind := Hit.Kind;
    Exit(Hit.P);
  end;

  { Piece midpoints get a shorter reach of their own: they should not grab
    from as far as a corner, but they are what you aim at when dividing. }
  if PtOK and (PtPx <= PIECE_PX) and (Hit.Kind = snSubMid) then
  begin
    FSnapKind := Hit.Kind;
    Exit(Hit.P);
  end;

  { A line under the pointer means a point on that line (SketchUp's On
    Edge).  It beats the guides, since real geometry is more definite than
    an alignment to something far off, but it loses to any named point
    within reach, or line middles become nearly impossible to hit. }
  if (not PtOK) and
     FD.Doc.EdgeUnder(Proj, SX, SY, EDGE_PX * FUIScale, EdgeP,
                      EdgeA, EdgeB, EdgeI) then
  begin
    { The edge's middle is worked out here, not cached: face outline sides
      are not in the snap cache (too many to project on every camera move),
      and the edge under the cursor is already known, so it costs nothing. }
    MidP := P3((EdgeA.X + EdgeB.X) / 2, (EdgeA.Y + EdgeB.Y) / 2,
               (EdgeA.Z + EdgeB.Z) / 2);
    SP := ScreenOf(MidP);
    if Sqr(SX - SP.X) + Sqr(SY - SP.Y) <= Sqr(LOCK_PX * FUIScale) then
    begin
      FSnapKind := snMidpoint;
      FStickOn := True;
      FStickPt := MidP;
      FStickKind := snMidpoint;
      Exit(MidP);
    end;
    { On the edge and on an axis through the start: take the crossing point,
      exactly on both.  Otherwise the nearest edge point slides with every
      pixel and the line comes out slightly off square. }
    if (FStage > 0) and (FDirLock < 0) and (FInferMode = imAll) then
    begin
      AxIdx := -1;
      AxPx := AXIS_PX;
      AxPt := Wf;
      AxRef := Wf;
      FParPerp := 0;
      AxisTry(FP1);
      if FLockOn then AxisTry(FLockPt);
      if (AxIdx >= 0) and (AxIdx <= 2) and
         AxisMeetsEdge(AxRef, AxIdx, EdgeA, EdgeB, MidP) then
      begin
        FAxisLock := AxIdx;
        FAxisFrom := AxRef;
        FSnapKind := snOnEdge;
        Exit(MidP);
      end;
    end;
    FSnapKind := snOnEdge;
    Exit(EdgeP);
  end;

  { The three axes, as lines the cursor can be on (SketchUp's On Red Axis
    and friends).  Below real geometry, above alignment guides.  This is all
    an empty sheet has to snap to, and it is what lets Z read a real height:
    otherwise the cursor is pinned to the working plane. }
  if (not PtOK) and (FInferMode = imAll) and
     AxisSnap(Proj, SX, SY, EDGE_PX * FUIScale, AxSnapP, AxSnapK) then
  begin
    FSnapKind := snOnAxis;
    FSnapAxis := AxSnapK;
    Exit(AxSnapP);
  end;

  { Otherwise a 90 degree relation to a chosen point (the line start, or a
    rested-on point) beats other nearby snaps; going straight up from the
    start corner is nearly always what was wanted. }
  AxIdx := -1;
  AxPx := AXIS_PX;
  AxPt := Wf;
  AxRef := Wf;              { only read once AxisTry has set it; quiets the compiler }
  FSnapFromPt := False;
  FParPerp := 0;
  if FDirLock < 0 then
  begin
    { Alt says which of these are on offer - see TInferMode }
    if FInferMode = imAll then
    begin
      if FStage > 0 then AxisTry(FP1);
      if FLockOn then AxisTry(FLockPt);
    end;
    if FInferMode in [imAll, imParPerp] then
    begin
      if FStage > 0 then ParPerpTry(FP1);
      if FLockOn then ParPerpTry(FLockPt);
    end;
  end;

  { A definite point near an axis guide does not take the cursor off the
    guide: it says how far ALONG it.  The result is the point on the axis
    nearest the corner (SketchUp's rule), so square stays square.  A corner
    on the axis projects to itself.  Parallel/perpendicular guides simply
    give way to the point. }
  if PtOK and (AxIdx >= 0) and (AxIdx <= 2) and
     (Hit.Kind in [snEndpoint, snCross, snCenter, snMidpoint, snOrigin]) then
  begin
    AxPt := AxRef;
    case AxIdx of
      0: AxPt.X := Hit.P.X;
      1: AxPt.Y := Hit.P.Y;
    else AxPt.Z := Hit.P.Z;
    end;
    FSnapFromPt := True;
  end
  else if PtOK and (AxIdx >= 3) and
     (Hit.Kind in [snEndpoint, snCross, snCenter, snMidpoint, snOrigin]) then
    AxIdx := -1;

  if AxIdx >= 3 then
  begin
    { Parallel or square to an edge: the point comes straight off the ray,
      since there are no axis coordinates to hold. }
    W := AxPt;
    FParPerp := AxIdx - 2;
    FAxisLock := -1;
    FAxisFrom := AxRef;
    FSnapKind := snGrid;
    Exit(W);
  end;

  if AxIdx >= 0 then
  begin
    { The distance along the axis snaps to the grid, unless a corner set it;
      the other two coordinates come from the reference, which puts it
      exactly on the axis. }
    if FSnapFromPt then W := AxPt else W := SnapToGrid(AxPt);
    case AxIdx of
      0: begin W.Y := AxRef.Y; W.Z := AxRef.Z; end;
      1: begin W.X := AxRef.X; W.Z := AxRef.Z; end;
    else begin W.X := AxRef.X; W.Y := AxRef.Y; end;
    end;
    FAxisLock := AxIdx;
    FAxisFrom := AxRef;
    FSnapKind := snGrid;
    { and the third coordinate can still line up with something }
    AlignFree(W, AxIdx);
    Exit(W);
  end;

  if PtOK then
  begin
    FSnapKind := Hit.Kind;
    Exit(Hit.P);
  end;

  W := SnapToGrid(Wf);
  FSnapKind := snGrid;

  { a locked direction is already a constraint; inferring another on top
    makes the cursor feel glued to the start }
  if FDirLock >= 0 then
    Exit(W);

  Tol := INFER_PX / Max(1E-9, Ppu);
  Best := 1E30;
  BestAxis := -1;
  { A fast hand is going somewhere, not lining up: no nudges until it slows.
    One already taken is kept out to a wider tolerance so it does not
    flicker at the edge. }
  if PrevGuide then
  begin
    KeepTol := Tol * KEEP_FACTOR;
    Near := 0;
    if Abs(W.X - PrevFrom.X) <= KeepTol then Inc(Near);
    if Abs(W.Y - PrevFrom.Y) <= KeepTol then Inc(Near);
    if Abs(W.Z - PrevFrom.Z) <= KeepTol then Inc(Near);
    if (Near = 2) and (Dist(W, PrevFrom) * Ppu >= 18) then
    begin
      if Abs(W.X - PrevFrom.X) <= KeepTol then W.X := PrevFrom.X;
      if Abs(W.Y - PrevFrom.Y) <= KeepTol then W.Y := PrevFrom.Y;
      if Abs(W.Z - PrevFrom.Z) <= KeepTol then W.Z := PrevFrom.Z;
      FGuideFrom := PrevFrom;
      FGuide := True;
      Exit(W);
    end;
  end;
  if FMoveSpeed > FAST_PX_S then Exit(W);

  FD.Doc.SnapPoints(Pts);
  for I := 0 to High(Pts) do
    Consider(Pts[I]);
  if FStage > 0 then
    Consider(FP1);

  if BestAxis >= 0 then
  begin
    { pull the matching axes onto the point; the odd one out is the guide }
    if Abs(W.X - FGuideFrom.X) <= Tol then W.X := FGuideFrom.X;
    if Abs(W.Y - FGuideFrom.Y) <= Tol then W.Y := FGuideFrom.Y;
    if Abs(W.Z - FGuideFrom.Z) <= Tol then W.Z := FGuideFrom.Z;
    FGuide := True;
  end;

  Result := W;
end;

{ A point pulled back onto the face being drawn on.  Some inferences do not
  know about the face: the model axes run along the base of anything on the
  ground and would pull the point sideways off it. }
function TMainForm.HeldToFace(const P: TP3): TP3;
var
  D: Double;
begin
  Result := P;
  if not FPlaneFromFace then Exit;
  D := (P.X - FFacePt.X) * FFaceNm.X + (P.Y - FFacePt.Y) * FFaceNm.Y +
       (P.Z - FFacePt.Z) * FFaceNm.Z;
  Result := P3(P.X - FFaceNm.X * D, P.Y - FFaceNm.Y * D, P.Z - FFaceNm.Z * D);
end;

function TMainForm.ResolveSnapAt(SX, SY: Double): TP3;
var
  HF: Integer;
  HP, N, Raw: TP3;
  RU1, RV1, RU2, RV2: Double;
begin
  Result := ResolveSnapRaw(SX, SY);
  { Held to the face, except when the point came from an axis lock or a named
    point.  Those are more definite than a held plane: standing a gable up
    off the floor follows blue as SketchUp does, and an endpoint aimed at
    must not be flattened onto some other plane. }
  if (FAxisLock < 0) and not (FSnapKind in [snEndpoint, snMidpoint, snCenter,
       snCross, snSubMid, snOrigin, snQuadrant]) then
    Result := HeldToFace(Result);
  { A plane locked with the arrows is deliberate, so even an endpoint off it
    does not win; it would stop the outline closing.  Only an axis lock,
    the same kind of statement made more recently, overrides it. }
  if FPlaneHeld and (FStage > 0) and (FAxisLock < 0) then
    case FD.Plane of
      plXY: Result.Z := FP1.Z;
      plXZ: Result.Y := FP1.Y;
      plYZ: Result.X := FP1.X;
    end;
  { A rectangle may not have a side of zero length.  Alignments are built
    for lines, and leveling a rectangle's corner with its start leaves a
    zero side, which the tool rejects with no visible reason.  If an
    inference flattened a side the bare cursor had, that side goes back; the
    other side keeps its alignment. }
  if (FTool = ptRect) and (FStage = 1) and (FD.Plane <> plFree) then
  begin
    { snapped to the grid, or restoring the bare cursor gives odd fractions.
      If the grid itself flattens it, the message below says so. }
    Raw := SnapToGrid(WorldAt(SX, SY));
    RectSides(FP1, Result, FD.Plane, RU1, RV1);
    RectSides(FP1, Raw, FD.Plane, RU2, RV2);
    if (RU1 <= 1E-9) and (RU2 > 1E-9) then
      case FD.Plane of
        plYZ: Result.Y := Raw.Y;
      else    Result.X := Raw.X;
      end;
    if (RV1 <= 1E-9) and (RV2 > 1E-9) then
      case FD.Plane of
        plXY: Result.Y := Raw.Y;
      else    Result.Z := Raw.Z;
      end;
  end;

  { A free point resting on a face reads On Face, as in SketchUp, but only
    when it really lies on that face's plane. }
  if (FSnapKind = snGrid) and FD.Doc.FaceUnder(Proj, SX, SY, HF, HP) then
  begin
    N := Norm3(FD.Doc.FaceNormal(HF));
    if Abs(Dot3(N, P3(Result.X - HP.X, Result.Y - HP.Y, Result.Z - HP.Z))) < 1E-6 then
      FSnapKind := snOnFace;
  end;
end;

function TMainForm.AnnotColor: TPix;
begin
  Result := Pix($44, $48, $52);
end;

procedure TMainForm.UIFont(C: TCanvas; Size: Integer; Bold: Boolean;
  const Col: TPix; Mono: Boolean);
begin
  {$IFDEF WINDOWS}
  if Mono then C.Font.Name := 'Consolas' else C.Font.Name := 'Segoe UI';
  {$ELSE}
    {$IFDEF DARWIN}
    if Mono then C.Font.Name := 'Menlo' else C.Font.Name := 'Helvetica Neue';
    {$ELSE}
    if Mono then C.Font.Name := 'Monospace' else C.Font.Name := 'Sans';
    {$ENDIF}
  {$ENDIF}
  C.Font.Height := -Round(Size * FUIScale);
  if Bold then C.Font.Style := [fsBold] else C.Font.Style := [];
  C.Font.Color := PixToColor(Col);
  C.Brush.Style := bsClear;
end;

function TMainForm.TrackedText(C: TCanvas; X, Y: Integer; const S: string;
  Tracking: Integer): Integer;
var
  I, X0: Integer;
begin
  X0 := X;
  for I := 1 to Length(S) do
  begin
    C.TextOut(X, Y, S[I]);
    Inc(X, C.TextWidth(S[I]) + Tracking);
  end;
  Result := X - X0;
end;

function TMainForm.ToolName(T: TTool): string;
begin
  Result := TOOL_NAMES[T];
end;

{ ======================================================================== }
{ lifecycle                                                                 }
{ ======================================================================== }

{ Given to hsSurface so a repair lands in the trail beside the tool in hand. }
procedure SurfaceRepaired(const What: string);
begin
  if MainForm <> nil then MainForm.Trail(What);
  { and to stderr for a test-harness run; the trail is only read from a report }
  if GetEnvironmentVariable('HSK_TRACE') <> '' then
  begin
    WriteLn(StdErr, 'TRACE ', What);
    Flush(StdErr);
  end;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  I: Integer;
  A: string;
begin
  Application.OnException := @ReportCrash;
  FDimArc := -1;
  FExportDirs := TStringList.Create;
  Randomize;
  { one more start, for the postcard (see hsPostcard) }
  CountLaunch;
  FRunTag := IntToHex(GetTickCount64 and $FFFFFF, 6) + IntToHex(Random($10000), 4);
  for I := 1 to ParamCount do
  begin
    A := ParamStr(I);
    if Pos('--updated-from=', LowerCase(A)) = 1 then
      FUpdatedFrom := Copy(A, Length('--updated-from=') + 1, MaxInt);
  end;
  FillViewMenu;
  { real hover tooltips on the deck, not just the hint line }
  pbDeck.ShowHint := True;
  Application.ShowHint := True;
  Application.HintPause := 450;
  Application.HintHidePause := 6000;
  Randomize;
  hsSurface.OnSurfaceRepair := @SurfaceRepaired;
  { Before anything can be typed: zero is a valid entity index, so a default
    0 would mean "editing the first thing in the drawing". }
  FDimEdit := -1;
  FLenDenom := LenDenom;
  FNoteDrag := -1;
  FSidesCircle := 24;
  FQuickFrames := True;
  { the program uses workers; the tests and tools, which never render, do not }
  FStartedAt := GetTickCount64;
  FThreads := True;
  DefaultThreads := True;
  hsDrawing.Progress := @OnProgress;
  FSidesArc := 12;
  FCursorWas := crCross;
  Caption := APP_NAME + '  ' + CurrentVersion;
  FUIScale := EnsureRange(Screen.PixelsPerInch / 96, 1.0, 3.0);
  DoubleBuffered := True;

  FHintInShot := -1;
  FPaper := TArtSurface.Create(16, 16);
  FArt := TArtSurface.Create(16, 16);
  FInk := TArtSurface.Create(16, 16);
  FInkHalf := TArtSurface.Create(16, 16);
  FInk.PreserveAlpha := True;
  FShell := TArtSurface.Create(16, 16);
  FDeckSkin := TArtSurface.Create(16, 16);
  FCmdSkin := TArtSurface.Create(16, 16);
  FCmdRowCache := THTMLLayoutCache.Create(8);
  FViewSkin := TArtSurface.Create(16, 16);
  FSliceSkin := TArtSurface.Create(16, 16);
  FToolSkin := TArtSurface.Create(16, 16);
  FInfoSkin := TArtSurface.Create(16, 16);
  FGrpSkin := TArtSurface.Create(16, 16);
  FGrpHot := -1;
  FGrpSig := -1;
  FQuickSkin := TArtSurface.Create(16, 16);
  FHotQuick := -1;
  FHotTool := -1;
  FToolsWide := True;
  FHotSlice := -1;
  FSliceEdit := 0;
  FGlyph := TArtSurface.Create(16, 16);
  FPopup := POP_NONE;
  FOverlay := TArtSurface.Create(16, 16);

  FRecent := TStringList.Create;
  NewDrawing(-1);
  FDimFont := TFont.Create;
  {$IFDEF WINDOWS}
  FDimFont.Name := 'Segoe UI';
  {$ELSE}
  FDimFont.Name := 'Sans';
  {$ENDIF}
  { dimensions carry an isometric drawing, so they are a size up from other
    labels }
  FDimFont.Height := -Round(13 * FUIScale);

  FThemeIdx := THEME_DARK;
  FEdgeW := 1;
  FMeasEdge := -1;
  FHotItem := -1;
  FHotView := -1;
  FHoverEnt := -1;
  FTool := ptSelect;
  FDirLock := -1;
FPushFace := -1;
  FReplayFace := -1;
  FOffFace := -1;
  FHoverFace := -1;

  LoadSettings;
  ApplyCommandLine;
  SetInk(FInkColor, FInkAuto);

  pbScreen.Cursor := crCross;
  pbDeck.Cursor := crHandPoint;

  tmrTick.Interval := TICK_MS;
  tmrTick.Enabled := True;
end;

{ Where the window is, read while the window still exists.  On Windows the
  handle is gone by OnDestroy and RestoredLeft and friends return garbage. }
procedure TMainForm.RememberWindow;
begin
  if not HandleAllocated then Exit;
  FWinMax := WindowState = wsMaximized;
  if WindowState = wsNormal then
  begin
    { A normal window knows where it is.  Restored* lags a beat after a move,
      so it would sometimes save the opening position. }
    FWinL := Left;
    FWinT := Top;
    FWinW := Width;
    FWinH := Height;
  end
  else
  begin
    { Maximized or full screen: ask what it will restore to.  Left and Width
      would be the screen size and it could never be made smaller. }
    FWinL := RestoredLeft;
    FWinT := RestoredTop;
    FWinW := RestoredWidth;
    FWinH := RestoredHeight;
  end;
  FWinSaved := (FWinW > 200) and (FWinH > 200);
end;

{ How many files have unsaved work.  A sheet nobody touched does not count;
  the starting example arrives with hundreds of entities. }
function TMainForm.AnyDirty: Integer;
var
  I, K: Integer;
  Seen: Boolean;
begin
  Result := 0;
  for I := 0 to High(FDrawings) do
  begin
    { each file once }
    Seen := False;
    for K := 0 to I - 1 do
      if FDrawings[K].DocKey = FDrawings[I].DocKey then Seen := True;
    if not Seen and DocDirty(FDrawings[I].DocKey) then Inc(Result);
  end;
end;

{ Closing the window asks about each file with unsaved work: Save, Don't
  save, or Cancel (window stays open).  Once all are answered the window
  closes clean and nothing is restored next time; Don't save means don't. }
procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  I, K: Integer;
  Keys: array of Integer;
  Seen: Boolean;
begin
  CanClose := True;
  { an update is taking over and already has the drawings (see DoUpdate) }
  if FHandingOver then Exit;
  Keys := nil;
  for I := 0 to High(FDrawings) do
  begin
    Seen := False;
    for K := 0 to High(Keys) do
      if Keys[K] = FDrawings[I].DocKey then Seen := True;
    if not Seen then
    begin
      SetLength(Keys, Length(Keys) + 1);
      Keys[High(Keys)] := FDrawings[I].DocKey;
    end;
  end;
  for K := 0 to High(Keys) do
    if not AskToSave(Keys[K], 'Close Heckers Sketch') then
    begin
      CanClose := False;
      Exit;
    end;
  FCleanExit := True;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  RememberWindow;
  { Record the source window now: by FormDestroy, where settings are written,
    every other form is hidden and it would always be saved as closed. }
  if SourceForm <> nil then
  begin
    FSourceWasOpen := SourceForm.Visible;
    FSourceOnTop := SourceForm.chkOnTop.Checked;
    if SourceForm.WindowState = wsNormal then
      FSourceBounds := Rect(SourceForm.Left, SourceForm.Top, SourceForm.Width, SourceForm.Height);
  end;
end;

{ --blank on the command line (see where it is used) }
function AskedForBlank: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if LowerCase(ParamStr(I)) = '--blank' then Result := True;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
var
  I: Integer;
begin
  { A clean exit drops the draft; it is only for a crash or a pulled plug.
    Handing over to an update, or any other exit, writes it so the work can
    be recovered. }
  if FCleanExit and not FHandingOver then DropDraft
  else if FEditSeq <> FDraftSeq then SaveDraft;
  { settings first: they write the recent files and the export folders }
  SaveSettings;
  FRecent.Free;
  FExportDirs.Free;
  FDimFont.Free;
  for I := High(FDrawings) downto 0 do
    FDrawings[I].Free;
  FOverlay.Free;
  FPaperBase.Free;
  FSelShot.Free;
  FViewSkin.Free;
  FSliceSkin.Free;
  FToolSkin.Free;
  FInfoSkin.Free;
  FGrpSkin.Free;
  FQuickSkin.Free;
  FGlyph.Free;
  FCmdSkin.Free;
  FCubeSkin.Free;
  FDeckSkin.Free;
  FShell.Free;
  FInk.Free;
  FInkHalf.Free;
  FArt.Free;
  FPaper.Free;
end;

procedure TMainForm.FormShow(Sender: TObject);
var
  I: Integer;
  Opened: Boolean;
begin
  if FBooted then Exit;
  FBooted := True;
  ApplyTheme;
  Relayout;
  FD.ViewX := Round(FArt.Width * 0.10);
  FD.ViewY := Round(FArt.Height * 0.88);
  FCur := P3(0, 0, 0);
  LayoutTabs;
  FreshScreen;

  { a file on the command line opens straight away; scan for it so a switch
    in front of it does not hide it }
  Opened := False;
  for I := 1 to ParamCount do
    if (Copy(ParamStr(I), 1, 1) <> '-') and FileExists(ParamStr(I)) then
    begin
      Opened := OpenFile(ParamStr(I));
      Break;
    end;
  { --blank: start on an empty sheet and ask nothing about last time (handy
    for tests and scripts).  An existing draft is copied aside first so no
    work is lost. }
  if AskedForBlank then
  begin
    if FileExists(DraftFile) then
      CopyFile(DraftFile, ChangeFileExt(DraftFile, '') + '-before-blank.hsk',
        [cffOverwriteFile]);
    DropDraft;
    Opened := True;
    Trail('started blank (--blank)');
  end;
  { After an update, restore what the old copy handed over.  Any other time
    a leftover handoff is from an update that never started, and the draft
    is at least as new, so it goes. }
  if not Opened and (FUpdatedFrom <> '') then Opened := RestoreHandoff;
  if FileExists(HandoffFile) then DeleteFile(HandoffFile);
  if Opened and (FUpdatedFrom <> '') then DropDraft;
  { A draft means the last run did not close properly.  It is offered on the
    tick once the window is up, not loaded, and no dialog may appear here
    (see below). }
  if not Opened and FileExists(DraftFile) then FRecoverToOffer := True;
  { Otherwise start on an empty drawing: not the example, not the last
    drawing.  The example is on the menu. }
  WriteExamples;
  WriteJigs;
  SplashLoaded(LoadedWords);
  { fingers on the drawing, where the platform gives them to us }
  FTouchOn := HookTouch(Self, @OnTouch);
  Trail('touch hook: ' + BoolToStr(FTouchOn, True));

  { Housekeeping from last time.  No dialogs here: the window has not
    painted yet, so a dialog would sit over a black rectangle, look hung and
    get force-quit, which causes another crash report.  Crash offers wait for
    the tick. }
  ForgetPreviousBuild;
  { reopen the source window now with the main window, not on the later tick }
  if FSourceWasOpen then
  begin
    ShowSource;
    BringToFront;
  end;
end;

{ Command-line window switches.  They override the saved size, since a
  launcher is not a person.  Unknown arguments are ignored, never fatal. }
procedure TMainForm.ApplyCommandLine;
var
  I, X: Integer;
  A, V: string;
  W, H: Integer;
begin
  for I := 1 to ParamCount do
  begin
    A := LowerCase(ParamStr(I));
    if (A = '--maximized') or (A = '--maximised') or (A = '-max') then
    begin
      FFill := flMaximized;
      WindowState := wsMaximized;
    end
    else if (A = '--fullscreen') or (A = '-full') then
    begin
      { Not BorderStyle := bsNone: GTK marks borderless windows not resizable
        and pins the X size hints, so a remote display that changes size (as
        KasmVNC does) cannot resize it.  Ask the window manager for full
        screen and set the bounds too, for when there is no window manager. }
      FFill := flFull;
      WindowState := wsFullScreen;
      SetBounds(Monitor.Left, Monitor.Top, Monitor.Width, Monitor.Height);
    end
    else if Copy(A, 1, 7) = '--size=' then
    begin
      { --size=1600x1000 }
      V := Copy(A, 8, MaxInt);
      X := Pos('x', V);
      if X > 1 then
      begin
        W := StrToIntDef(Copy(V, 1, X - 1), 0);
        H := StrToIntDef(Copy(V, X + 1, MaxInt), 0);
        if (W > 320) and (H > 240) then
        begin
          FFill := flNone;
          WindowState := wsNormal;
          SetBounds(Left, Top, W, H);
          Position := poScreenCenter;
        end;
      end;
    end
    { --help is answered in the program file, before any of this exists }
  end;
end;

{ ======================================================================== }
{ layout                                                                    }
{ ======================================================================== }

{ A drawing board keeps its chrome small.  Relayout, RebuildShell,
  pbDeckPaint and FormPaint all use these, so they must come from here. }
function TMainForm.TitleHeight: Integer;
begin
  Result := Round(34 * FUIScale);
end;

function TMainForm.ChromeMargin: Integer;
begin
  Result := Round(8 * FUIScale);
end;

function TMainForm.DeckRowH: Integer;
begin
  { 20 was too tight: longer tool names clipped }
  Result := Round(24 * FUIScale);
end;

function TMainForm.DeckRows: Integer;
begin
  { one row: settings left and six named buttons right }
  Result := 1;
end;

function TMainForm.DeckHeight: Integer;
begin
  Result := DeckRows * DeckRowH + (DeckRows - 1) * Round(4 * FUIScale) +
    Round(10 * FUIScale);
end;

procedure TMainForm.Relayout;
var
  M, TitleH, DeckH, Bezel, Gap, CmdH, TabsH: Integer;
  ToolW: Integer;
  BezelR, DeckR: TRect;
  InfoW, ColH, GrpH: Integer;
begin
  if not FBooted then Exit;

  M := ChromeMargin;
  TitleH := TitleHeight;
  DeckH := DeckHeight;
  Bezel := Round(16 * FUIScale);
  CmdH := CmdBarHeight;
  TabsH := Round(22 * FUIScale);
  Gap := Round(6 * FUIScale);

  { the file buttons, after the name and the version }
  pbQuick.SetBounds(M + Round(2 * FUIScale), Round(4 * FUIScale),
    QuickWidth, Round(24 * FUIScale));

  DeckR := Rect(M, ClientHeight - M - DeckH, ClientWidth - M, ClientHeight - M);
  ToolW := ToolStripWidth;
  pbTools.Visible := ToolW > 0;

  { The cut only means something in plan, so it only shows there, beside
    the view button since it is a property of the view. }
  pbSlice.Visible := (FD <> nil) and (FD.View = vkPlan);
  pbView.SetBounds(ClientWidth - M - Round(228 * FUIScale), TitleH,
    Round(228 * FUIScale), TabsH);
  if pbSlice.Visible then
  begin
    pbSlice.SetBounds(pbView.Left - Round(6 * FUIScale) - Round(250 * FUIScale),
      TitleH, Round(250 * FUIScale), TabsH);
    pbTabs.SetBounds(M, TitleH,
      Max(120, pbSlice.Left - M - Round(16 * FUIScale)), TabsH);
  end
  else
    pbTabs.SetBounds(M, TitleH,
      Max(120, pbView.Left - M - Round(16 * FUIScale)), TabsH);
  pbCmd.SetBounds(M, DeckR.Top - Gap - CmdH, ClientWidth - 2 * M, CmdH);
  BezelR := Rect(M, TitleH + TabsH + Round(4 * FUIScale), ClientWidth - M,
    pbCmd.Top - Round(10 * FUIScale));
  PlaceCmdMsg;

  { The tool strip takes space from the bezel so it never covers the drawing. }
  if pbTools.Visible then
  begin
    pbTools.SetBounds(BezelR.Left, BezelR.Top, ToolW,
      Max(60, BezelR.Bottom - BezelR.Top));
    BezelR.Left := BezelR.Left + ToolW + Round(6 * FUIScale);
  end;

  { The entity panel takes the right side for the same reason.  The groups
    panel shares that column: all of it alone, or the lower part under the
    entity panel. }
  InfoW := InfoPanelWidth;
  pbInfo.Visible := (InfoW > 0) and FInfoOn;
  pbGroups.Visible := (InfoW > 0) and FGroupsOn;
  if InfoW > 0 then
  begin
    BezelR.Right := BezelR.Right - InfoW - Round(6 * FUIScale);
    ColH := Max(60, BezelR.Bottom - BezelR.Top);
    if pbInfo.Visible and pbGroups.Visible then
    begin
      GrpH := Max(Round(140 * FUIScale), ColH * 42 div 100);
      pbInfo.SetBounds(BezelR.Right + Round(6 * FUIScale), BezelR.Top, InfoW,
        Max(40, ColH - GrpH - Round(6 * FUIScale)));
      pbGroups.SetBounds(BezelR.Right + Round(6 * FUIScale),
        BezelR.Top + ColH - GrpH, InfoW, GrpH);
    end
    else if pbInfo.Visible then
      pbInfo.SetBounds(BezelR.Right + Round(6 * FUIScale), BezelR.Top, InfoW, ColH)
    else
      pbGroups.SetBounds(BezelR.Right + Round(6 * FUIScale), BezelR.Top, InfoW, ColH);
  end;

  pbDeck.SetBounds(DeckR.Left, DeckR.Top, Max(120, DeckR.Right - DeckR.Left), DeckH);

  pbScreen.SetBounds(BezelR.Left + Bezel, BezelR.Top + Bezel,
    Max(32, (BezelR.Right - BezelR.Left) - 2 * Bezel),
    Max(32, (BezelR.Bottom - BezelR.Top) - 2 * Bezel));

  ResizeSurfaces(pbScreen.Width, pbScreen.Height);

  FShell.SetSize(Max(1, ClientWidth), Max(1, ClientHeight));
  RebuildShell;

  FDeckSkin.SetSize(pbDeck.Width, pbDeck.Height);
  RebuildDeck;

  FCmdSkin.SetSize(Max(1, pbCmd.Width), Max(1, pbCmd.Height));
  FViewSkin.SetSize(Max(1, pbView.Width), Max(1, pbView.Height));
  FSliceSkin.SetSize(Max(1, pbSlice.Width), Max(1, pbSlice.Height));
  FToolSkin.SetSize(Max(1, pbTools.Width), Max(1, pbTools.Height));
  RebuildTools;
  FQuickSkin.SetSize(Max(1, pbQuick.Width), Max(1, pbQuick.Height));
  RebuildQuick;
  LayoutTabs;

  Invalidate;
end;

procedure TMainForm.RebuildShell;
var
  M, TitleH, DeckH, Bezel, Gap, CmdH, TabsH: Integer;
  BezelR: TRect;
begin
  M := ChromeMargin;
  TitleH := TitleHeight;
  DeckH := DeckHeight;
  Bezel := Round(16 * FUIScale);
  Gap := Round(6 * FUIScale);
  CmdH := CmdBarHeight;
  TabsH := Round(22 * FUIScale);

  BezelR := Rect(M, TitleH + TabsH + Round(4 * FUIScale), ClientWidth - M,
    ClientHeight - M - DeckH - Gap - CmdH - Round(10 * FUIScale));
  { the same shift Relayout makes, or the frame is drawn in the wrong place }
  if ToolStripWidth > 0 then
    BezelR.Left := BezelR.Left + ToolStripWidth + Round(6 * FUIScale);

  PaintShell(FShell, Theme);
  PaintBezel(FShell, BezelR, Theme, Round(5 * FUIScale));
  PaintScreenWell(FShell, Rect(BezelR.Left + Bezel, BezelR.Top + Bezel,
    BezelR.Right - Bezel, BezelR.Bottom - Bezel), Round(3 * FUIScale));
  FShell.Touch;
end;

procedure TMainForm.ResizeSurfaces(AW, AH: Integer);
begin
  AW := Max(1, AW);
  AH := Max(1, AH);
  { Check every surface, not just FArt: if they ever got out of step, an
    FArt-only check would never put them back. }
  if (FArt.Width = AW) and (FArt.Height = AH) and
     (FPaper.Width = AW) and (FPaper.Height = AH) and
     (FInk.Width = AW) and (FInk.Height = AH) then Exit;

  FPaper.SetSize(AW, AH);
  FArt.SetSize(AW, AH);
  FShotOK := False;
  FInk.SetSize(AW, AH);
  FInk.ClearTransparent;

  RepaintPaper;
  RenderInk;
  RecomposeAll;
end;

{ Stipple the face under the cursor with a bold outline, as SketchUp does.
  Clipped to the face (holes belong to faces inside them) and drawn only
  where the depth buffer says the face is in front; WashFace uses the same
  rules.  With S given, draw into that surface (its corner at OX, OY on
  screen) instead: that is how the wash gets into the cursor square. }
procedure TMainForm.PaintFaceHint(C: TCanvas; Face: Integer; const Col: TPix;
  S: TArtSurface; OX, OY: Integer);
var
  Pts: TPointFArray;
  HPts: array of TPointFArray;
  Ink: TArtSurface;
  Look, Nm, AU, AV, O, W: TP3;
  SO, SU, SV: TPointF;
  Det, DU, DV, D0, PU, PV, Dp, Zb: Double;
  Deep: Boolean;
  I, H, K, N, X, Y, X0, Y0, X1, Y1, Step, NX, XEnd: Integer;
  Inside: Boolean;
  { a row never crosses more loops than this }
  XS: array[0..255] of Double;
  Xt: Double;

  { where this row crosses that loop, added to the list }
  procedure Cross(const P: TPointFArray; PY: Integer;
    var Xs: array of Double; var NX: Integer);
  var
    K, L, M: Integer;
  begin
    M := Length(P);
    if M < 3 then Exit;
    L := M - 1;
    for K := 0 to M - 1 do
    begin
      if ((P[K].Y > PY) <> (P[L].Y > PY)) and (NX <= High(Xs)) then
      begin
        Xs[NX] := (P[L].X - P[K].X) * (PY - P[K].Y) /
                  (P[L].Y - P[K].Y) + P[K].X;
        Inc(NX);
      end;
      L := K;
    end;
  end;

begin
  if Face < 0 then Exit;
  { already in the picture on screen (see pbScreenPaint) }
  if (S = nil) and (Face = FHintInShot) then Exit;
  Pts := FD.Doc.Outline(Proj, Face);
  N := Length(Pts);
  if N < 3 then Exit;

  SetLength(HPts, Length(FD.Doc[Face].Holes));
  for H := 0 to High(HPts) do
  begin
    SetLength(HPts[H], Length(FD.Doc[Face].Holes[H]));
    for I := 0 to High(HPts[H]) do
      HPts[H][I] := ScreenOf(FD.Doc[Face].Holes[H][I]);
  end;

  X0 := MaxInt; Y0 := MaxInt; X1 := -MaxInt; Y1 := -MaxInt;
  for I := 0 to N - 1 do
  begin
    X0 := Min(X0, Round(Pts[I].X)); X1 := Max(X1, Round(Pts[I].X));
    Y0 := Min(Y0, Round(Pts[I].Y)); Y1 := Max(Y1, Round(Pts[I].Y));
  end;
  X0 := Max(X0, 0); Y0 := Max(Y0, 0);
  X1 := Min(X1, pbScreen.Width - 1); Y1 := Min(Y1, pbScreen.Height - 1);
  if S <> nil then
  begin
    X0 := Max(X0, OX); Y0 := Max(Y0, OY);
    X1 := Min(X1, OX + S.Width - 1); Y1 := Min(Y1, OY + S.Height - 1);
  end;
  if (X1 <= X0) or (Y1 <= Y0) then Exit;

  { Depth under any pixel of the face.  The view is orthographic and the face
    flat, so depth is affine in screen coordinates: project two plane
    directions, invert the 2x2, and each dot costs two multiplies. }
  Ink := FInk;
  Deep := (Ink <> nil) and Ink.DepthOn and (Length(FD.Doc[Face].Poly) >= 3);
  Det := 0; D0 := 0; DU := 0; DV := 0;
  SO := PtF(0, 0); SU := PtF(0, 0); SV := PtF(0, 0);
  if Deep then
  begin
    Look := ViewDir(Proj);
    Nm := Norm3(FD.Doc.FaceNormal(Face));
    AxesFromNormal(Nm, AU, AV);
    O := FD.Doc[Face].Poly[0];
    SO := ScreenOf(O);
    W := P3(O.X + AU.X, O.Y + AU.Y, O.Z + AU.Z);
    SU := ScreenOf(W); SU := PtF(SU.X - SO.X, SU.Y - SO.Y);
    W := P3(O.X + AV.X, O.Y + AV.Y, O.Z + AV.Z);
    SV := ScreenOf(W); SV := PtF(SV.X - SO.X, SV.Y - SO.Y);
    Det := SU.X * SV.Y - SU.Y * SV.X;
    Deep := Abs(Det) > 1E-6;
    D0 := Dot3(O, Look);
    DU := Dot3(AU, Look);
    DV := Dot3(AV, Look);
  end;

  { A dither, since the canvas has no alpha; every other pixel reads as a
    solid wash.  Filled by scanline: crossing points per row, sorted, filled
    in pairs.  A per-dot inside test was millions of divides per mouse move on
    a big face.  Hole edges go into the same crossing list, so even-odd
    leaves them empty for free. }
  Step := 2;
  Y := Y0 - (Y0 mod Step);
  while Y <= Y1 do
  begin
    NX := 0;
    Cross(Pts, Y, XS, NX);
    for H := 0 to High(HPts) do Cross(HPts[H], Y, XS, NX);
    { insertion sort: a row only crosses a few edges }
    for I := 1 to NX - 1 do
    begin
      Xt := XS[I];
      K := I - 1;
      while (K >= 0) and (XS[K] > Xt) do
      begin
        XS[K + 1] := XS[K];
        Dec(K);
      end;
      XS[K + 1] := Xt;
    end;

    I := 0;
    while I + 1 < NX do
    begin
      { on the dither's own grid, so the pattern does not crawl as the
        outline moves }
      X := Max(X0, Ceil(XS[I]));
      X := X + ((Step - (X mod Step)) mod Step);
      XEnd := Min(X1, Floor(XS[I + 1]));
      while X <= XEnd do
      begin
        Inside := True;
        if Deep then
        begin
          PU := ((X - SO.X) * SV.Y - (Y - SO.Y) * SV.X) / Det;
          PV := (SU.X * (Y - SO.Y) - SU.Y * (X - SO.X)) / Det;
          Dp := D0 + PU * DU + PV * DV;
          Zb := Ink.DepthAt(X, Y);
          if (Zb > -1E29) and (Zb > Dp + 1E-3 * (1 + Abs(Dp))) then
            Inside := False;
        end;
        if Inside then
          if S <> nil then S.BlendPixel(X - OX, Y - OY, Col, 1)
          else C.Pixels[X, Y] := PixToColor(Col);
        Inc(X, Step);
      end;
      Inc(I, 2);
    end;
    Inc(Y, Step);
  end;

  if S <> nil then
  begin
    { the bold edge, into the square too }
    for I := 0 to N - 1 do
      S.Line(Pts[(I + N - 1) mod N].X - OX, Pts[(I + N - 1) mod N].Y - OY,
        Pts[I].X - OX, Pts[I].Y - OY, Max(2, Round(2 * FUIScale)), Col, 1);
    for H := 0 to High(HPts) do
      for I := 0 to High(HPts[H]) do
        S.Line(HPts[H][(I + Length(HPts[H]) - 1) mod Length(HPts[H])].X - OX,
          HPts[H][(I + Length(HPts[H]) - 1) mod Length(HPts[H])].Y - OY,
          HPts[H][I].X - OX, HPts[H][I].Y - OY,
          Max(2, Round(2 * FUIScale)), Col, 1);
    Exit;
  end;

  C.Pen.Color := PixToColor(Col);
  C.Pen.Width := Max(2, Round(2 * FUIScale));
  C.Pen.Style := psSolid;
  C.MoveTo(Round(Pts[N - 1].X), Round(Pts[N - 1].Y));
  for I := 0 to N - 1 do
    C.LineTo(Round(Pts[I].X), Round(Pts[I].Y));
  { the windows get the same bold edge, so a ring reads as a ring }
  for H := 0 to High(HPts) do
    if Length(HPts[H]) >= 3 then
    begin
      C.MoveTo(Round(HPts[H][High(HPts[H])].X), Round(HPts[H][High(HPts[H])].Y));
      for I := 0 to High(HPts[H]) do
        C.LineTo(Round(HPts[H][I].X), Round(HPts[H][I].Y));
    end;
  C.Pen.Width := 1;
end;

{ Where the cursor lands on a plane other than the working plane, for the
  offset tool's face.  Orthographic, so each pixel is a ray along the view
  direction; this is where it crosses the face's plane. }
function TMainForm.CursorOnPlane(const N, P0: TP3): TP3;
var
  O, Dir: TP3;
  Den, T: Double;
begin
  O := WorldAt(FMouseSX, FMouseSY);
  Result := O;
  Dir := ViewDir(Proj);
  Den := Dot3(N, Dir);
  if Abs(Den) < 1E-9 then Exit;          // looking along the face, edge on
  T := (N.X * (P0.X - O.X) + N.Y * (P0.Y - O.Y) + N.Z * (P0.Z - O.Z)) / Den;
  Result := P3(O.X + Dir.X * T, O.Y + Dir.Y * T, O.Z + Dir.Z * T);
end;

{ How far in or out the cursor is from the face outline, in the face plane.
  Outside is positive (grows); inside is negative (a duct wall).  A typed
  number sets the size; the cursor still says which way. }
function TMainForm.OffsetDistance: Double;
var
  Loop: TP3Array;
  N, P, A, B, W, V: TP3;
  I, J, Cnt: Integer;
  Best, D, T, L2: Double;
  Snapped: Boolean;
begin
  Result := 0;
  if (FOffFace < 0) or (FOffFace >= FD.Doc.Live) then Exit;
  Loop := FD.Doc[FOffFace].Poly;
  Cnt := Length(Loop);
  if Cnt < 3 then Exit;
  N := FD.Doc.FaceNormal(FOffFace);
  { When snapped (a guide, guide point, corner, edge middle) the offset is
    measured exactly to that point dropped onto the face plane, not rounded
    to the snap step.  A guide at 8" must give an 8" offset, as in SketchUp. }
  Snapped := FSnapKind in [snEndpoint, snMidpoint, snCenter, snCross, snSubMid,
    snOnEdge, snOrigin];
  if Snapped then
  begin
    P := FCur;
    D := Dot3(N, P3(P.X - Loop[0].X, P.Y - Loop[0].Y, P.Z - Loop[0].Z));
    P := P3(P.X - N.X * D, P.Y - N.Y * D, P.Z - N.Z * D);
  end
  else
    P := CursorOnPlane(N, Loop[0]);

  Best := 1E30;
  for I := 0 to Cnt - 1 do
  begin
    J := (I + 1) mod Cnt;
    A := Loop[I];
    B := Loop[J];
    V := P3(B.X - A.X, B.Y - A.Y, B.Z - A.Z);
    W := P3(P.X - A.X, P.Y - A.Y, P.Z - A.Z);
    L2 := V.X * V.X + V.Y * V.Y + V.Z * V.Z;
    if L2 < 1E-18 then T := 0
    else T := EnsureRange((W.X * V.X + W.Y * V.Y + W.Z * V.Z) / L2, 0, 1);
    D := Dist(P, P3(A.X + V.X * T, A.Y + V.Y * T, A.Z + V.Z * T));
    if D < Best then Best := D;
  end;

  if PointInLoop(P, Loop, N) then Result := -Best else Result := Best;
  if (not Snapped) and (SnapStep > 0) then Result := Round(Result / SnapStep) * SnapStep;

  { a typed thickness wins on size; the cursor still says in or out }
  if (FInput <> '') and ParseLen(FInput, FD.Units, D) then
  begin
    if Result < 0 then Result := -Abs(D) else Result := Abs(D);
  end;
end;

{ the loop the offset would lay down, for the preview }
function TMainForm.OffsetPreview: TP3Array;
var
  D: Double;
begin
  Result := nil;
  if (FOffFace < 0) or (FOffFace >= FD.Doc.Live) then Exit;
  D := OffsetDistance;
  if Abs(D) < 1E-9 then Exit;
  Result := OffsetLoop(FD.Doc[FOffFace].Poly, FD.Doc.FaceNormal(FOffFace), D,
    not FOffsetRaw);
end;

procedure TMainForm.CommitOffset;
var
  R: TP3Array;
  I, Cnt, Was: Integer;
  D: Double;
begin
  D := OffsetDistance;
  R := OffsetPreview;
  Cnt := Length(R);
  if Cnt < 3 then
  begin
    if Abs(D) > 1E-9 then
      FCmdMsg := 'That takes it in further than it will go - ' +
        FormatLen(Abs(D), FD.Units) + ' turns the face inside out.'
    else
      FCmdMsg := 'Move in or out from the face first, or type a thickness.';
    Exit;
  end;
  PushUndo;
  Was := FaceCount;
  for I := 0 to Cnt - 1 do
    if not FD.Doc.HasLine(R[I], R[(I + 1) mod Cnt]) then
      FD.Doc.AddLine(R[I], R[(I + 1) mod Cnt], FInkColor, FEdgeW, False);
  RebuildFlatFaces;
  RenderInk;
  RecomposeAll;
  FCmdMsg := Format('Offset %s %s   %d face%s now',
    [FormatLen(Abs(D), FD.Units),
     specialize IfThen<string>(D < 0, 'in', 'out'),
     FaceCount, specialize IfThen<string>(FaceCount = 1, '', 's')]);
  if FaceCount = Was then
    FCmdMsg := FCmdMsg + ' - nothing new closed';
  FOffFace := -1;
  ResetTool;
  FInput := '';
end;

{ Right-click a dimension and write over its figure: a nominal size, a cut
  length allowing for a fitting, FIELD VERIFY.  On an isometric the written
  figure is the drawing.  Clearing the box goes back to the measurement. }
procedure TMainForm.EditDimUnder(X, Y: Integer);
var
  I: Integer;
begin
  I := FD.Doc.HitTest(Proj, X, Y, 10 * FUIScale);
  if (I < 0) or (FD.Doc[I].Kind <> ekDim) then Exit;
  { In the command bar, like every other entry; a modal dialog would
    hide the drawing just when you want to see it. }
  FDimEdit := I;
  FInput := FD.Doc[I].Txt;
  FCmdMsg := 'Type what this dimension should say, then Enter.  ' +
    'Empty goes back to the measured length;  Esc leaves it alone.';
  pbCmd.Invalidate;
  pbScreen.Invalidate;
end;

{ Paint the shown face, or every picked face when the shown one is among
  them (as SketchUp's bucket does).  If it is not in the selection, only it
  changes.  Painting False strips back to the default. }
function TMainForm.PaintSelectedFaces(Shown: Integer; C: TColor;
  Painting: Boolean): Integer;
var
  I: Integer;
  InSel: Boolean;

  procedure One(K: Integer);
  begin
    if (K < 0) or (K >= FD.Doc.Live) then Exit;
    if FD.Doc[K].Kind <> ekFace then Exit;
    if Painting then FD.Doc.SetMaterial(K, C) else FD.Doc.ClearMaterial(K);
    Inc(Result);
  end;

begin
  Result := 0;
  { Shown < 0: the panel means the whole selection }
  InSel := Shown < 0;
  for I := 0 to High(FSel) do
    if FSel[I] = Shown then InSel := True;
  if InSel then
    for I := 0 to High(FSel) do One(FSel[I])
  else
    One(Shown);
  if Result = 0 then Exit;
  RenderInk;
  RecomposeAll;
  Invalidate;
end;

{ The pen color of everything picked that is drawn with a pen.  Faces are
  painted (PaintSelectedFaces) and guides are not offered. }
function TMainForm.InkSelectedThings(C: TColor): Integer;
var
  I, K: Integer;
begin
  Result := 0;
  for I := 0 to High(FSel) do
  begin
    K := FSel[I];
    if (K < 0) or (K >= FD.Doc.Live) then Continue;
    if not (FD.Doc[K].Kind in [ekLine, ekArc, ekText, ekDim]) then Continue;
    FD.Doc.SetInk(K, C);
    Inc(Result);
  end;
  if Result = 0 then Exit;
  RenderInk;
  RecomposeAll;
  Invalidate;
end;

{ Turns over every picked face.  The program guesses which way a new face
  faces and cannot always be right (two back-to-back walls); this is the
  user's way to say. }
function TMainForm.ReverseSelectedFaces: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FSel) do
    if FD.Doc[FSel[I]].Kind = ekFace then
      if FD.Doc.ReverseFace(FSel[I]) then Inc(Result);
  if Result = 0 then Exit;
  RenderInk;
  RecomposeAll;
  Invalidate;
end;

{ the one picked dimension, or -1; a length typed at two would have to guess }
function TMainForm.SelectedDim: Integer;
begin
  Result := -1;
  if Length(FSel) <> 1 then Exit;
  if FD.Doc[FSel[0]].Kind <> ekDim then Exit;
  Result := FSel[0];
end;

{ the one picked line (a drawn edge, not a dimension), or -1 }
function TMainForm.SelectedLine: Integer;
begin
  Result := -1;
  if Length(FSel) <> 1 then Exit;
  if (FSel[0] < 0) or (FSel[0] >= FD.Doc.Live) then Exit;
  if (FD.Doc[FSel[0]].Kind <> ekLine) or FD.Doc[FSel[0]].Dim then Exit;
  Result := FSel[0];
end;

{ Pick a line, type a length, Enter (SketchUp's Entity Info length).  Which
  end moves follows SketchUp's rule (TWorkDoc.LineLengthEnd), and the
  message says which. }
function TMainForm.ApplyLineLength(NewLen: Double): Boolean;
var
  I: Integer;
  Was: Double;
  MoveB: Boolean;
begin
  Result := False;
  I := SelectedLine;
  if I < 0 then Exit;
  Was := Dist(FD.Doc[I].A, FD.Doc[I].B);
  if not FD.Doc.LineLengthEnd(I, MoveB) then
  begin
    FCmdMsg := 'That line is joined at both ends, so its length cannot be ' +
      'typed - move one of its ends instead, the way SketchUp does.';
    Result := True;
    Exit;
  end;
  if NewLen <= 0 then
  begin
    FCmdMsg := 'A length has to be more than nothing.';
    Result := True;
    Exit;
  end;
  PushUndo;
  FD.Doc.SetLineLength(I, NewLen);
  RebuildFlatFaces;
  RenderInk;
  RecomposeAll;
  Invalidate;
  InvalidateStatus;
  FCmdMsg := Format('%s -> %s, the free end moved.',
    [FormatLen(Was, FD.Units), FormatLen(NewLen, FD.Units)]);
  Result := True;
end;

{ Pick a dimension, type what it should read, and the drawing moves.  The
  end that gives is the one it was drawn to (the second click); the message
  says so and how to move the other end instead. }
function TMainForm.ApplyDimResize(NewLen: Double; MoveB: Boolean): Boolean;
var
  I: Integer;
  Was: Double;
begin
  Result := False;
  I := SelectedDim;
  if I < 0 then Exit;
  { stretching along a radius would pull the circle out of round }
  if (Pos('<>', FD.Doc[I].Txt) > 0) and
     ((Copy(FD.Doc[I].Txt, 1, 2) = 'R ') or (Copy(FD.Doc[I].Txt, 1, 4) = 'DIA ')) then
  begin
    FCmdMsg := 'A radius or a diameter cannot resize its curve yet - draw ' +
      'the circle again at the size you want.';
    Exit;
  end;
  Was := Dist(FD.Doc[I].A, FD.Doc[I].B);
  if NewLen <= 0 then
  begin
    FCmdMsg := 'A size has to be more than nothing.';
    Exit;
  end;
  if Abs(NewLen - Was) < 1E-9 then
  begin
    FCmdMsg := 'It already reads ' + FormatLen(Was, FD.Units) + '.';
    Exit;
  end;
  { A zero-length dimension has no direction to grow along.  Checked before
    PushUndo so a refusal leaves no empty undo step. }
  if Was < 1E-9 then
  begin
    FCmdMsg := 'That dimension has no length to work from.';
    Exit;
  end;
  PushUndo;
  FD.Doc.ResizeDim(I, NewLen, MoveB);
  RenderInk;
  RecomposeAll;
  Invalidate;
  InvalidateStatus;
  if MoveB then
    FCmdMsg := Format('%s -> %s, from the end it was drawn to.  ' +
      '"/resize %s start" moves the other end instead.',
      [FormatLen(Was, FD.Units), FormatLen(NewLen, FD.Units),
       FormatLen(NewLen, FD.Units)])
  else
    FCmdMsg := Format('%s -> %s, from the end it was drawn from.',
      [FormatLen(Was, FD.Units), FormatLen(NewLen, FD.Units)]);
  Result := True;
end;

{ What the right button offers, built fresh each time. }
procedure TMainForm.FillCanvasMenu;
var
  I, Faces: Integer;
  JobId: string;
  M: TMenuItem;

  procedure Add(const Caption: string; Tag: Integer);
  var
    It: TMenuItem;
  begin
    It := TMenuItem.Create(pmCanvas);
    It.Caption := Caption;
    It.Tag := Tag;
    It.OnClick := @CanvasMenuClick;
    pmCanvas.Items.Add(It);
  end;

begin
  pmCanvas.Items.Clear;
  Faces := 0;
  for I := 0 to High(FSel) do
    if FD.Doc[FSel[I]].Kind = ekFace then Inc(Faces);

  { The same rows every time, in the same order; ones that would do nothing
    are grayed, not removed.  If the shape changed with the selection, a
    destructive row could slide under a hand aiming at a harmless one.
    Erase goes last, under a line. }
  Add('Make Group', 10);
  pmCanvas.Items[pmCanvas.Items.Count - 1].Enabled := Length(FSel) > 0;
  Add('Open Group', 11);
  pmCanvas.Items[pmCanvas.Items.Count - 1].Enabled := SoleGroup > 0;
  Add('Close Group', 12);
  pmCanvas.Items[pmCanvas.Items.Count - 1].Enabled := FD.Doc.Context <> 0;
  if (SoleGroup > 0) and FD.Doc.PartLocked(SoleGroup) then Add('Unlock Group', 13)
  else Add('Lock Group', 13);
  pmCanvas.Items[pmCanvas.Items.Count - 1].Enabled := Length(SelectedGroups) > 0;
  Add('Explode Group', 14);
  pmCanvas.Items[pmCanvas.Items.Count - 1].Enabled := Length(SelectedGroups) > 0;
  Add('Groups Panel', 23);
  pmCanvas.Items[pmCanvas.Items.Count - 1].Checked := FGroupsOn;
  if (SoleGroup > 0) and IsStairJig(FD.Doc.PartJig(SoleGroup)) then
  begin
    { the program's own stairs: changed in their dialog, or rebuilt from
      what they remember }
    Add('Change the Stairs...', 17);
    Add('Print the Stringer Sheet...', 22);
    Add('Build the Stairs Again', 15);
    Add('Show It in the Source', 16);
  end
  else if (SoleGroup > 0) and (FD.Doc.PartJig(SoleGroup) <> '') then
  begin
    Add('Run the Jig Again', 15);
    Add('Show It in the Source', 16);
  end
  else if (SoleGroup > 0) and (RadiantGroupOf(SoleGroup, JobId) > 0) then
  begin
    { a radiant layout that kept its job: reopen it in the wizard, or
      reprint its submittal }
    Add('Open in the Radiant Wizard...', 18);
    Add('Print the Submittal Again...', 19);
  end;
  M := TMenuItem.Create(pmCanvas);
  M.Caption := '-';
  pmCanvas.Items.Add(M);

  if Faces > 1 then Add(Format('Reverse %d Faces', [Faces]), 1)
  else Add('Reverse Face', 1);
  pmCanvas.Items[pmCanvas.Items.Count - 1].Enabled := Faces > 0;

  { one click instead of two numbers: a clicked floor says all the slice
    needs }
  Add('Plan From Here', 4);
  pmCanvas.Items[pmCanvas.Items.Count - 1].Enabled := Faces = 1;

  { centering a selection makes an export arrive where a slicer expects it }
  Add('Center on the Origin', 5);
  pmCanvas.Items[pmCanvas.Items.Count - 1].Enabled := Length(FSel) > 0;

  { the corner instead of the middle, for measuring rather than printing }
  Add('Into the Corner at 0,0,0', 6);
  pmCanvas.Items[pmCanvas.Items.Count - 1].Enabled := Length(FSel) > 0;

  { The guides: always both rows, grayed when there are none (see above). }
  M := TMenuItem.Create(pmCanvas);
  M.Caption := '-';
  pmCanvas.Items.Add(M);

  if FD.Doc.GuidesHidden then
    Add(Format('Show %d Guides', [FD.Doc.GuideCount]), 7)
  else
    Add(Format('Hide %d Guides', [FD.Doc.GuideCount]), 7);
  pmCanvas.Items[pmCanvas.Items.Count - 1].Enabled := FD.Doc.GuideCount > 0;

  Add('Clear Guides', 8);
  pmCanvas.Items[pmCanvas.Items.Count - 1].Enabled := FD.Doc.GuideCount > 0;

  M := TMenuItem.Create(pmCanvas);
  M.Caption := '-';
  pmCanvas.Items.Add(M);

  Add('Select None', 3);
  pmCanvas.Items[pmCanvas.Items.Count - 1].Enabled := Length(FSel) > 0;

  M := TMenuItem.Create(pmCanvas);
  M.Caption := '-';
  pmCanvas.Items.Add(M);

  if Length(FSel) > 1 then Add(Format('Erase %d Things', [Length(FSel)]), 2)
  else Add('Erase', 2);
  pmCanvas.Items[pmCanvas.Items.Count - 1].Enabled := Length(FSel) > 0;
end;

procedure TMainForm.CanvasMenuClick(Sender: TObject);
var
  N: Integer;
begin
  case (Sender as TMenuItem).Tag of
    1:
      begin
        PushUndo;
        N := ReverseSelectedFaces;
        if N = 1 then FCmdMsg := 'Face turned over.'
        else FCmdMsg := Format('%d faces turned over.', [N]);
        InvalidateStatus;
      end;
    2: DeleteSelection;
    10: MakeGroup;
    11: OpenGroup(SoleGroup);
    12: CloseGroup;
    13: LockGroups(not ((SoleGroup > 0) and FD.Doc.PartLocked(SoleGroup)));
    14: ExplodeGroups;
    15:
      begin
        if RunJigOf(SoleGroup) then
        begin
          RebuildFlatFaces;
          if IsStairJig(FD.Doc.PartJig(SoleGroup)) then FCmdMsg := 'The stairs are built again.'
          else FCmdMsg := 'The jig was run again.';
        end;
        RenderInk;
        RecomposeAll;
        pbScreen.Invalidate;
        pbCmd.Invalidate;
      end;
    16: ShowSource;
    17: BuildStairWizard;
    21:
      if (FGuideMenuEnt >= 0) and (FGuideMenuEnt < FD.Doc.Live) and
         (FD.Doc[FGuideMenuEnt].Kind = ekGuide) then
      begin
        PushUndo;
        { only that one: a guide line's points stay, they were laid on their
          own }
        if Dist(FD.Doc[FGuideMenuEnt].A, FD.Doc[FGuideMenuEnt].B) < 1E-9 then
          FCmdMsg := 'Guide point erased.  Ctrl+Z brings it back.'
        else
          FCmdMsg := 'Guide line erased - the points on it stay.  Ctrl+Z brings it back.';
        FD.Doc.Delete(FGuideMenuEnt);
        { selected indices after it shift down one }
        for N := 0 to High(FSel) do
          if FSel[N] > FGuideMenuEnt then Dec(FSel[N]);
        FGuideMenuEnt := -1;
        FHoverEnt := -1;
        RenderInk;
        RecomposeAll;
        pbScreen.Invalidate;
      end;
    18: BuildRadiantWizard(SoleGroup);
    23: SetGroupsPanel(not FGroupsOn);
    22: StringerSheetOf(SoleGroup);
    19: PrintSubmittalAgain(SoleGroup);
    7:
      begin
        FD.Doc.GuidesHidden := not FD.Doc.GuidesHidden;
        FCmdMsg := IfThen(FD.Doc.GuidesHidden,
          'Guides put away.  They are still in the drawing.',
          'Guides back.');
        RenderInk;
        RecomposeAll;
      end;
    8:
      begin
        PushUndo;
        FCmdMsg := Format('Cleared %d guides.', [FD.Doc.ClearGuides]);
        RenderInk;
        RecomposeAll;
      end;
    4:
      for N := 0 to High(FSel) do
        if FD.Doc[FSel[N]].Kind = ekFace then
        begin
          PlanFromFace(FSel[N]);
          Break;
        end;
    3:
      begin
        SelectNone;
        FCmdMsg := 'Nothing selected.';
        FScreenDirty := True;
        InvalidateStatus;
      end;
    5: CenterSelection;
    6: CornerSelection;
  end;
end;

{ Center the selection (or the whole drawing when nothing is picked) on the
  bed: across X and Y, standing on Z = 0, where every slicer expects it.
  /tozero puts the near bottom corner on the origin instead. }
procedure TMainForm.CenterSelection;
var
  Mid, Lo, Hi: TP3;
  Idx: array of Integer;
  I: Integer;
begin
  if not FD.Doc.SpanOf(FSel, Lo, Hi) then
  begin
    FCmdMsg := 'Nothing to center.';
    InvalidateStatus;
    Exit;
  end;
  Mid := P3((Lo.X + Hi.X) / 2, (Lo.Y + Hi.Y) / 2, Lo.Z);
  if (Abs(Mid.X) < 1E-9) and (Abs(Mid.Y) < 1E-9) and (Abs(Mid.Z) < 1E-9) then
  begin
    FCmdMsg := 'Already centered on the floor.';
    InvalidateStatus;
    Exit;
  end;
  PushUndo;
  if Length(FSel) > 0 then
  begin
    SetLength(Idx, Length(FSel));
    for I := 0 to High(FSel) do Idx[I] := FSel[I];
  end
  else
  begin
    SetLength(Idx, FD.Doc.Live);
    for I := 0 to FD.Doc.Live - 1 do Idx[I] := I;
  end;
  FD.Doc.TranslateEnts(Idx, P3(-Mid.X, -Mid.Y, -Mid.Z));
  RenderInk;
  RecomposeAll;
  FScreenDirty := True;
  if Length(FSel) > 0 then
    FCmdMsg := Format('Centered %d things on the floor.', [Length(FSel)])
  else
    FCmdMsg := 'Centered the whole drawing on the floor.';
  InvalidateStatus;
  Invalidate;
end;

{ Keep the command list in step with what is typed: it opens on the slash,
  narrows as letters arrive, and closes when the slash is erased.  The
  highlight sits on the first row, which Enter takes. }
procedure TMainForm.SyncCmdList;
var
  H: Integer;
begin
  if Copy(FInput, 1, 1) <> '/' then
  begin
    if FPopup = POP_CMDS then ClosePopup;
    Exit;
  end;
  if FPopup <> POP_CMDS then OpenPopup(POP_CMDS)
  else
    BuildCmdOrder;
  { only what survived the filter }
  FPopupN := Length(FCmdOrder);
  { and the panel shrinks to fit }
  H := Min(FPopupN * Round(22 * FUIScale) + Round(12 * FUIScale),
           PopupMaxHeight(POP_CMDS));
  FPopupR := Rect(FPopupR.Left, FPopupR.Bottom - H, FPopupR.Right,
                  FPopupR.Bottom);
  if FPopupR.Top < 4 then
    FPopupR := Rect(FPopupR.Left, 4, FPopupR.Right, 4 + H);
  FPopupTop := 0;
  if FPopupN > 0 then FPopupHot := 0 else FPopupHot := -1;
  FScreenDirty := True;
  pbScreen.Invalidate;
end;

{ up and down the list, scrolling to follow the highlight }
procedure TMainForm.MoveCmdHighlight(Key: word);
var
  Rows, Step: Integer;
begin
  if Length(FCmdOrder) = 0 then Exit;
  Rows := Max(1, (FPopupR.Bottom - FPopupR.Top - Round(12 * FUIScale)) div
                 Max(1, Round(22 * FUIScale)));
  case Key of
    VK_UP:    Step := -1;
    VK_DOWN:  Step := 1;
    VK_PRIOR: Step := -Rows;
  else        Step := Rows;
  end;
  FPopupHot := EnsureRange(FPopupHot + Step, 0, High(FCmdOrder));
  if FPopupHot < FPopupTop then FPopupTop := FPopupHot;
  if FPopupHot > FPopupTop + Rows - 1 then FPopupTop := FPopupHot - Rows + 1;
  FPopupTop := EnsureRange(FPopupTop, 0, Max(0, Length(FCmdOrder) - Rows));
  FScreenDirty := True;
  pbScreen.Invalidate;
end;

function TMainForm.ExactCmd(const S: string): Boolean;
var
  W: string;
  I: Integer;
begin
  W := LowerCase(Trim(S));
  if Copy(W, 1, 1) = '/' then W := Copy(W, 2, MaxInt);
  { anything with an argument after it was typed on purpose }
  if Pos(' ', W) > 0 then Exit(True);
  Result := CmdIndex(W) >= 0;
end;

{ the row a word runs, by its name or one of its other words; -1 if none }
function TMainForm.CmdIndex(const W: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(CMD_LIST) do
    if (CMD_LIST[I].Name = W) or
       (Pos(' ' + W + ' ', ' ' + CMD_LIST[I].Also + ' ') > 0) then
      Exit(I);
  Result := -1;
end;

{ When the row was found by one of its other words, that word, so the row
  can say why it is there (/tape finds /measure). }
function TMainForm.CmdAliasFor(Idx: Integer; const Want: string): string;
var
  Words: TStringList;
  K: Integer;
begin
  Result := '';
  if (Want = '') or (Idx < 0) or (Idx > High(CMD_LIST)) then Exit;
  if Pos(Want, CMD_LIST[Idx].Name) > 0 then Exit;
  Words := TStringList.Create;
  try
    Words.Delimiter := ' ';
    Words.StrictDelimiter := True;
    Words.DelimitedText := CMD_LIST[Idx].Also;
    { prefix matches first, as the list is sorted }
    for K := 0 to Words.Count - 1 do
      if Copy(Words[K], 1, Length(Want)) = Want then Exit(Words[K]);
    for K := 0 to Words.Count - 1 do
      if Pos(Want, Words[K]) > 0 then Exit(Words[K]);
  finally
    Words.Free;
  end;
end;

{ Take the highlighted row: complete it into the box, and run it if it takes
  no argument.  This is what a click or Enter on a row does. }
procedure TMainForm.TakeCmdHighlight;
var
  It: TCmdItem;
begin
  if (FPopupHot < 0) or (FPopupHot >= Length(FCmdOrder)) then Exit;
  It := CMD_LIST[FCmdOrder[FPopupHot]];
  NoteCmdUsed(It.Name);
  ClosePopup;
  if It.Arg then
  begin
    { one that takes an argument is completed and left waiting }
    FInput := '/' + It.Name + ' ';
    FCmdMsg := It.Hint;
  end
  else
  begin
    FInput := '';
    RunCommand(It.Name);
  end;
  pbCmd.Invalidate;
  pbScreen.Invalidate;
end;

{ The command list's order, like an editor's autocomplete.  What is typed
  after the slash filters it: prefix matches first, then matches anywhere.
  With nothing typed: recently used first, then alphabetical. }
procedure TMainForm.BuildCmdOrder;
var
  I, N: Integer;
  Used: array of Boolean;
  Parts: TStringList;
  Want: string;

  { How well a word matches: 0 exact, 2 prefix, 4 anywhere, -1 not at all.
    A command's own name ranks a step ahead of its other words (see Rank),
    so "/reb" picks rebuild before reface (alias rebuildfaces).  Recency
    only orders rows within a rank. }
  function RankWord(const Name: string): Integer;
  begin
    if Name = Want then Exit(0);
    if Copy(Name, 1, Length(Want)) = Want then Exit(2);
    if Pos(Want, Name) > 0 then Exit(4);
    Result := -1;
  end;

  { the best of the row's name and, a step behind, its other words; -1 if
    neither matches }
  function Rank(M: Integer): Integer;
  var
    Words: TStringList;
    K, R: Integer;
  begin
    if Want = '' then Exit(0);
    Result := RankWord(CMD_LIST[M].Name);
    if (Result = 0) or (CMD_LIST[M].Also = '') then Exit;
    Words := TStringList.Create;
    try
      Words.Delimiter := ' ';
      Words.StrictDelimiter := True;
      Words.DelimitedText := CMD_LIST[M].Also;
      for K := 0 to Words.Count - 1 do
      begin
        R := RankWord(Words[K]);
        if R >= 0 then Inc(R);
        if (R >= 0) and ((Result < 0) or (R < Result)) then Result := R;
      end;
    finally
      Words.Free;
    end;
  end;

  procedure Sweep(Pass: Integer);
  var
    K, M: Integer;
  begin
    { recently used first, in the order used }
    Parts := TStringList.Create;
    try
      Parts.Delimiter := ',';
      Parts.StrictDelimiter := True;
      Parts.DelimitedText := FCmdRecent;
      for K := 0 to Parts.Count - 1 do
        for M := 0 to High(CMD_LIST) do
          if (not Used[M]) and (CMD_LIST[M].Name = Trim(Parts[K])) and
             (Rank(M) = Pass) then
          begin
            FCmdOrder[N] := M;
            Used[M] := True;
            Inc(N);
            Break;
          end;
    finally
      Parts.Free;
    end;
    { then the rest; CMD_LIST is already alphabetical }
    for M := 0 to High(CMD_LIST) do
      if (not Used[M]) and (Rank(M) = Pass) then
      begin
        FCmdOrder[N] := M;
        Used[M] := True;
        Inc(N);
      end;
  end;

begin
  Want := LowerCase(Trim(FInput));
  if Copy(Want, 1, 1) = '/' then Want := Copy(Want, 2, MaxInt);
  I := Pos(' ', Want);
  if I > 0 then Want := Copy(Want, 1, I - 1);
  FCmdWant := Want;

  SetLength(FCmdOrder, Length(CMD_LIST));
  SetLength(Used, Length(CMD_LIST));
  for I := 0 to High(Used) do Used[I] := False;
  N := 0;
  for I := 0 to 5 do Sweep(I);
  SetLength(FCmdOrder, N);
end;

{ Put Cmd at the front of the recent list and keep it short. }
procedure TMainForm.NoteCmdUsed(const Cmd: string);
const
  KEEP = 8;
var
  Parts: TStringList;
  I: Integer;
begin
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ',';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := FCmdRecent;
    for I := Parts.Count - 1 downto 0 do
      if Trim(Parts[I]) = Cmd then Parts.Delete(I);
    Parts.Insert(0, Cmd);
    while Parts.Count > KEEP do Parts.Delete(Parts.Count - 1);
    FCmdRecent := Parts.DelimitedText;
  finally
    Parts.Free;
  end;
end;

{ Move the selection so the lowest corner of its box sits at 0,0,0, so every
  reading is a distance from zero.  /center is the slicer version. }
procedure TMainForm.CornerSelection;
var
  Lo, Hi: TP3;
  Idx: array of Integer;
  I: Integer;
begin
  if not FD.Doc.SpanOf(FSel, Lo, Hi) then
  begin
    FCmdMsg := 'Nothing to move.';
    InvalidateStatus;
    Exit;
  end;
  if (Abs(Lo.X) < 1E-9) and (Abs(Lo.Y) < 1E-9) and (Abs(Lo.Z) < 1E-9) then
  begin
    FCmdMsg := 'Already in the corner.';
    InvalidateStatus;
    Exit;
  end;
  PushUndo;
  if Length(FSel) > 0 then
  begin
    SetLength(Idx, Length(FSel));
    for I := 0 to High(FSel) do Idx[I] := FSel[I];
  end
  else
  begin
    SetLength(Idx, FD.Doc.Live);
    for I := 0 to FD.Doc.Live - 1 do Idx[I] := I;
  end;
  FD.Doc.TranslateEnts(Idx, P3(-Lo.X, -Lo.Y, -Lo.Z));
  RenderInk;
  RecomposeAll;
  FScreenDirty := True;
  if Length(FSel) > 0 then
    FCmdMsg := Format('Moved %d things into the corner at 0,0,0 - %s by %s ' +
      'by %s from there.', [Length(FSel),
      FormatLen(Hi.X - Lo.X, FD.Units), FormatLen(Hi.Y - Lo.Y, FD.Units),
      FormatLen(Hi.Z - Lo.Z, FD.Units)])
  else
    FCmdMsg := Format('Moved the whole drawing into the corner at 0,0,0 - ' +
      '%s by %s by %s from there.',
      [FormatLen(Hi.X - Lo.X, FD.Units), FormatLen(Hi.Y - Lo.Y, FD.Units),
       FormatLen(Hi.Z - Lo.Z, FD.Units)]);
  InvalidateStatus;
  Invalidate;
end;

{ A right click that did not become a pan.  A dimension takes it first
  whatever the tool (right-click retypes it).  The measure tool offers its
  guide menu.  Otherwise, with the select tool, pick what is under the
  cursor as SketchUp does and offer what can be done to it. }
procedure TMainForm.RightClickAt(X, Y: Integer);
var
  I: Integer;
  P: TPoint;
begin
  I := FD.Doc.HitTest(Proj, X, Y, 10 * FUIScale);
  if (I >= 0) and (FD.Doc[I].Kind = ekDim) then
  begin
    EditDimUnder(X, Y);
    Exit;
  end;
  if FTool = ptMeasure then
  begin
    GuideMenuAt(X, Y);
    Exit;
  end;
  if FTool <> ptSelect then Exit;

  { Clicking something outside the selection makes it the selection.
    Clicking inside leaves the selection alone, so a whole roof can be
    turned over at once. }
  I := PickForMenu(X, Y);
  if I >= 0 then
  begin
    if not IsSelected(I) then
    begin
      SelectOnly(I);
      FScreenDirty := True;
      InvalidateStatus;
      { drawn before the menu covers it, so the target shows highlighted }
      pbScreen.Invalidate;
      Application.ProcessMessages;
    end;
  end
  else if Length(FSel) = 0 then
  begin
    FCmdMsg := 'Nothing there - click something first.';
    InvalidateStatus;
    Exit;
  end;

  FillCanvasMenu;
  if pmCanvas.Items.Count = 0 then Exit;
  P := pbScreen.ClientToScreen(Point(X, Y));
  pmCanvas.PopUp(P.X, P.Y);
end;

{ The measure tool's right-click: erase the guide point or guide line under
  the cursor, the menu saying which first.  The select tool and eraser leave
  guides alone. }
procedure TMainForm.GuideMenuAt(X, Y: Integer);
var
  I: Integer;
  P: TPoint;
  M: TMenuItem;

  procedure Add(const Caption: string; Tag: Integer; Enabled: Boolean = True);
  var
    It: TMenuItem;
  begin
    It := TMenuItem.Create(pmCanvas);
    It.Caption := Caption;
    It.Tag := Tag;
    It.Enabled := Enabled;
    It.OnClick := @CanvasMenuClick;
    pmCanvas.Items.Add(It);
  end;

begin
  { a point before the line it sits on; the point is what was aimed at }
  I := FD.Doc.HitGuidePoint(Proj, X, Y, 10 * FUIScale);
  if I < 0 then I := FD.Doc.HitGuideLine(Proj, X, Y, 6 * FUIScale);
  if (I >= 0) and (FD.Doc.TopPartIn(I) < 0) then I := -1;
  FGuideMenuEnt := I;
  pmCanvas.Items.Clear;
  if I < 0 then Add('No guide here', 0, False)
  else if Dist(FD.Doc[I].A, FD.Doc[I].B) < 1E-9 then Add('Erase This Guide Point', 21)
  else Add('Erase This Guide Line', 21);
  M := TMenuItem.Create(pmCanvas);
  M.Caption := '-';
  pmCanvas.Items.Add(M);
  if FD.Doc.GuidesHidden then Add(Format('Show %d Guides', [FD.Doc.GuideCount]), 7, FD.Doc.GuideCount > 0)
  else Add(Format('Hide %d Guides', [FD.Doc.GuideCount]), 7, FD.Doc.GuideCount > 0);
  M := TMenuItem.Create(pmCanvas);
  M.Caption := '-';
  pmCanvas.Items.Add(M);
  Add('Clear Guides', 8, FD.Doc.GuideCount > 0);
  { highlighted while the menu is read }
  FHoverEnt := I;
  FScreenDirty := True;
  pbScreen.Invalidate;
  Application.ProcessMessages;
  P := pbScreen.ClientToScreen(Point(X, Y));
  pmCanvas.PopUp(P.X, P.Y);
end;

{ Put what was typed on the dimension; called from Enter. }
procedure TMainForm.CommitDimNote;
var
  I: Integer;
  Note: string;
begin
  I := FDimEdit;
  FDimEdit := -1;
  Note := Trim(FInput);
  FInput := '';
  if (I < 0) or (I >= FD.Doc.Live) or (FD.Doc[I].Kind <> ekDim) then Exit;
  if Note = Trim(FD.Doc[I].Txt) then
  begin
    FCmdMsg := 'Left as it was.';
    Exit;
  end;
  PushUndo;
  FD.Doc.SetDimNote(I, Note);
  RenderInk;
  RecomposeAll;
  Invalidate;
  if Note = '' then FCmdMsg := 'Back to the measured length.'
  else FCmdMsg := 'Dimension reads "' + Note + '".';
end;

{ How far the push would go.  The drag says which way along the normal; a
  typed number only says how far. }
function TMainForm.PushDistance: Double;
var
  L, Move, Len2, DirX, DirY, Flush: Double;
  Nm, Other, A, B: TP3;
  PA, PN: TPointF;
  HF: Integer;
begin
  Result := 0;
  if FPushFace < 0 then Exit;
  Nm := FD.Doc.FaceNormal(FPushFace);

  { The cursor is unprojected onto the working plane, so it says nothing
    about Z.  Measure the drag along the normal as drawn on screen: the
    projected normal gives pixels per world unit. }
  PA := ScreenOf(FP1);
  PN := ScreenOf(P3(FP1.X + Nm.X, FP1.Y + Nm.Y, FP1.Z + Nm.Z));
  DirX := PN.X - PA.X;
  DirY := PN.Y - PA.Y;
  Len2 := DirX * DirX + DirY * DirY;
  if Len2 < 1E-9 then
    Move := 0                 // the normal points straight at the camera
  else
  begin
    Move := ((FMouseSX - FPushSX) * DirX + (FMouseSY - FPushSY) * DirY) / Len2;
    if SnapStep > 0 then Move := Round(Move / SnapStep) * SnapStep;
  end;

  if (FInput <> '') and ParseLen(FInput, FD.Units, L) then
  begin
    { the number says how far, the drag still says which way }
    if Move < 0 then Result := -L else Result := L;
    Exit;
  end;

  { Rest on a point or edge and the pull goes exactly to its distance from
    the face along the normal: hover the far side of a box and the push
    stops flush, as in SketchUp.  A point in the face plane is ignored. }
  if FSnapKind in [snEndpoint, snMidpoint, snCenter, snCross, snSubMid,
                   snOnEdge, snOrigin] then
  begin
    Flush := (FCur.X - FP1.X) * Nm.X + (FCur.Y - FP1.Y) * Nm.Y + (FCur.Z - FP1.Z) * Nm.Z;
    if Abs(Flush) > 1E-6 then
    begin
      FPushFlush := True;
      Exit(Flush);
    end;
  end;

  { Rest on another parallel face and the pull lines the two up exactly.
    That is how a row of windows comes out flush with no numbers typed. }
  HF := InContextFace(FaceAtPress);
  if (HF >= 0) and (HF <> FPushFace) and (Length(FD.Doc[HF].Poly) > 0) and
     (Length(FD.Doc[FPushFace].Poly) > 0) then
  begin
    Other := FD.Doc.FaceNormal(HF);
    if Abs(Nm.X * Other.X + Nm.Y * Other.Y + Nm.Z * Other.Z) > 0.9995 then
    begin
      A := FD.Doc[FPushFace].Poly[0];
      B := FD.Doc[HF].Poly[0];
      Flush := (B.X - A.X) * Nm.X + (B.Y - A.Y) * Nm.Y + (B.Z - A.Z) * Nm.Z;
        { Either way along the normal; you often come at the target face from
          the other side.  A face in the same plane is refused: the distance is
          zero and snapping the pull shut is no help. }
      if Abs(Flush) > 1E-6 then
      begin
        FPushFlush := True;
        Exit(Flush);
      end;
    end;
  end;
  FPushFlush := False;
  Result := Move;
end;

{ The push/pull preview: the face where it would land, joined by the walls
  that would be built, so the direction is clear before committing.  The
  walls take the axis color when the normal is on an axis. }
procedure TMainForm.PaintPushPreview(C: TCanvas);
var
  E: TWorkEnt;
  I, N, Ax: Integer;
  R: Double;
  Nm, Q: TP3;
  PA, PB: TPointF;
  Col: TPix;
begin
  if FPushFace < 0 then Exit;
  E := FD.Doc[FPushFace];
  N := Length(E.Poly);
  if N < 3 then Exit;

  R := PushDistance;
  { the drill's preview shows it coming out the far side, since that is what
    it will do }
  if (FTool = ptDrill) and (Abs(R) > 1E-9) then
    R := FD.Doc.ThroughDistance(FPushFace, R);
  if Abs(R) < 1E-9 then Exit;

  Nm := FD.Doc.FaceNormal(FPushFace);
  Ax := -1;
  if Abs(Nm.X) > 0.9 then Ax := 0
  else if Abs(Nm.Y) > 0.9 then Ax := 1
  else if Abs(Nm.Z) > 0.9 then Ax := 2;
  if Ax >= 0 then Col := AxisPix(Ax) else Col := Theme.Accent;

  { the walls that would be built }
  C.Pen.Style := psDot;
  C.Pen.Width := 1;
  C.Pen.Color := PixToColor(Col);
  for I := 0 to N - 1 do
  begin
    PA := ScreenOf(E.Poly[I]);
    PB := ScreenOf(P3(E.Poly[I].X + Nm.X * R, E.Poly[I].Y + Nm.Y * R,
                      E.Poly[I].Z + Nm.Z * R));
    C.MoveTo(Round(PA.X), Round(PA.Y));
    C.LineTo(Round(PB.X), Round(PB.Y));
  end;

  { the face where it would land }
  C.Pen.Style := psSolid;
  C.Pen.Width := Max(2, Round(2 * FUIScale));
  Q := P3(E.Poly[N - 1].X + Nm.X * R, E.Poly[N - 1].Y + Nm.Y * R,
          E.Poly[N - 1].Z + Nm.Z * R);
  PA := ScreenOf(Q);
  C.MoveTo(Round(PA.X), Round(PA.Y));
  for I := 0 to N - 1 do
  begin
    Q := P3(E.Poly[I].X + Nm.X * R, E.Poly[I].Y + Nm.Y * R,
            E.Poly[I].Z + Nm.Z * R);
    PB := ScreenOf(Q);
    C.LineTo(Round(PB.X), Round(PB.Y));
  end;
  C.Pen.Width := 1;
end;

{ A faint lattice on the ground (Z = 0) under a free camera, for a sense of
  floor and distance.  It follows the camera: the window corners are cast
  onto the ground and the lattice is ruled over that.  Pitch matches the
  paper grid so crossings are snap points.  Capped and dropped when the view
  is too flat to be worth it. }
procedure TMainForm.PaintGroundGrid(Pitch: Double);
const
  MAX_LINES = 160;
  { how far apart lattice lines must be on screen to be worth ruling }
  MIN_PX = 12;
var
  I, N, Drawn, Missed: Integer;
  Lo, Hi: TP3;
  C: array[0..3] of TP3;
  Fade, Heavy, A: Double;
  X0, X1, Y0, Y1, V, PitchX, PitchY, Area, LX, LY: Double;
  PA, PB, UX, UY, Org: TPointF;
  Col: TPix;

  { the next step up that keeps the crossings on round numbers: two, five,
    ten, twenty, fifty times the pitch the paper grid picked }
  function Coarser(Cur, Base: Double): Double;
  var
    K: Double;
  begin
    K := Cur / Base;
    if K < 1.5 then Result := Base * 2
    else if K < 3.5 then Result := Base * 5
    else Result := Cur * 2;
  end;

  { Both ends off the same side of the window, so no part of it is visible.
    The ruled box is bigger than the window when the camera is turned, so
    many lines miss the glass. }
  function Offscreen(const A, B: TPointF): Boolean;
  begin
    Result := ((A.X < 0) and (B.X < 0)) or
              ((A.Y < 0) and (B.Y < 0)) or
              ((A.X > FPaper.Width) and (B.X > FPaper.Width)) or
              ((A.Y > FPaper.Height) and (B.Y > FPaper.Height));
  end;

  { the ground point under a screen point, or False when the camera is too
    flat for there to be one worth having }
  function Ground(SX, SY: Double; out P: TP3): Boolean;
  begin
    P := Unproject(Proj, SX, SY, plXY, P3(0, 0, 0));
    Result := not (IsNan(P.X) or IsNan(P.Y) or IsInfinite(P.X) or
                   IsInfinite(P.Y)) and
              (Abs(P.X) < 1E6) and (Abs(P.Y) < 1E6);
  end;

begin
  if Pitch <= 1E-9 then Exit;
  if not Ground(0, 0, C[0]) then Exit;
  if not Ground(FPaper.Width, 0, C[1]) then Exit;
  if not Ground(FPaper.Width, FPaper.Height, C[2]) then Exit;
  if not Ground(0, FPaper.Height, C[3]) then Exit;

  Lo := C[0];
  Hi := C[0];
  for I := 1 to 3 do
  begin
    Lo.X := Min(Lo.X, C[I].X);  Hi.X := Max(Hi.X, C[I].X);
    Lo.Y := Min(Lo.Y, C[I].Y);  Hi.Y := Max(Hi.Y, C[I].Y);
  end;

  { Only the positive quarter, where both axes are drawn solid; nobody draws
    on the dashed side. }
  Lo.X := Max(Lo.X, 0);
  Lo.Y := Max(Lo.Y, 0);
  if (Hi.X <= Lo.X) or (Hi.Y <= Lo.Y) then Exit;

  { a low camera makes the box enormous; give up past the cap }
  if ((Hi.X - Lo.X) / Pitch > MAX_LINES * 40) or
     ((Hi.Y - Lo.Y) / Pitch > MAX_LINES * 40) then Exit;

  { Rule it at a pitch that can be seen.  A tilted orthographic view squashes
    one family of lines by the cosine of the tilt, so the world pitch can
    land a few pixels apart: a gray wash that is slow to draw.  Each family
    is coarsened on its own by 2, 5, 10 (never 3 or 7) so crossings stay on
    round numbers. }
  UX := ScreenOf(P3(1, 0, 0));
  UY := ScreenOf(P3(0, 1, 0));
  Org := ScreenOf(P3(0, 0, 0));
  UX := PtF(UX.X - Org.X, UX.Y - Org.Y);
  UY := PtF(UY.X - Org.X, UY.Y - Org.Y);
  { the area one square of the lattice covers on screen, per world unit }
  Area := Abs(UX.X * UY.Y - UX.Y * UY.X);
  LX := Sqrt(UX.X * UX.X + UX.Y * UX.Y);
  LY := Sqrt(UY.X * UY.X + UY.Y * UY.Y);

  { lines of constant X run along Y, so what separates them is the width of
    the square across the Y direction - and the other way about }
  PitchX := Pitch;
  if LY > 1E-9 then
    while (Area / LY) * PitchX < MIN_PX do PitchX := Coarser(PitchX, Pitch);
  PitchY := Pitch;
  if LX > 1E-9 then
    while (Area / LX) * PitchY < MIN_PX do PitchY := Coarser(PitchY, Pitch);

  { And coarse enough that the whole window gets ruled.  Lines are laid from
    the box's low corner, so a hard line cap left the near half (where the
    drawing usually is) bare.  A wide view gets a wider lattice instead. }
  while (Hi.X - Lo.X) / PitchX > MAX_LINES do PitchX := Coarser(PitchX, Pitch);
  while (Hi.Y - Lo.Y) / PitchY > MAX_LINES do PitchY := Coarser(PitchY, Pitch);

  X0 := Floor(Lo.X / PitchX) * PitchX;
  X1 := Ceil(Hi.X / PitchX) * PitchX;
  Y0 := Floor(Lo.Y / PitchY) * PitchY;
  Y1 := Ceil(Hi.Y / PitchY) * PitchY;

  Col := Theme.Grid;
  { As strong as the plan grid, every fifth line heavier, so the floor reads
    as squared paper and not a haze.  Hairlines, not the general antialiased
    line: that one was most of each orbiting frame on many faint lines. }
  Fade := 0.45;
  Heavy := 1.00;

  Drawn := 0;
  Missed := 0;

  V := X0;
  N := 0;
  { the cap is only a guard; the pitch above keeps the count sane }
  while (V <= X1 + 1E-9) and (N < MAX_LINES * 2) do
  begin
    PA := ScreenOf(P3(V, Y0, 0));
    PB := ScreenOf(P3(V, Y1, 0));
    if Offscreen(PA, PB) then Inc(Missed)
    else
    begin
      if Abs(V / PitchX - Round(V / PitchX / 5) * 5) < 1E-6 then A := Heavy
      else A := Fade;
      FPaper.HairLine(PA.X, PA.Y, PB.X, PB.Y, Col, A);
      Inc(Drawn);
    end;
    V := V + PitchX;
    Inc(N);
  end;

  V := Y0;
  N := 0;
  while (V <= Y1 + 1E-9) and (N < MAX_LINES * 2) do
  begin
    PA := ScreenOf(P3(X0, V, 0));
    PB := ScreenOf(P3(X1, V, 0));
    if Offscreen(PA, PB) then Inc(Missed)
    else
    begin
      if Abs(V / PitchY - Round(V / PitchY / 5) * 5) < 1E-6 then A := Heavy
      else A := Fade;
      FPaper.HairLine(PA.X, PA.Y, PB.X, PB.Y, Col, A);
      Inc(Drawn);
    end;
    V := V + PitchY;
    Inc(N);
  end;
  if FTimings then
  begin
    TimingLine(Format('ground grid: %d ruled, %d missed the window; x %.2f..%.2f pitch %.3f, y %.2f..%.2f pitch %.3f, fade %.2f',
      [Drawn, Missed, X0, X1, PitchX, Y0, Y1, PitchY, Fade]));
  end;
  FPaper.Touch;
end;

{ The three axes as infinite lines: X red, Y green, Z blue, solid toward
  positive and dashed toward negative, as in SketchUp.  Draws whatever
  stretch crosses the paper, whether or not the origin is in view. }
procedure TMainForm.PaintAxes;
const
  { axis names where the three meet, while the grid is on.  Compass
    directions are shown separately (PaintCompass). }
  AXIS_TAGS: array[0..2, 0..1] of string = (('X', '-X'), ('Y', '-Y'), ('Z', '-Z'));
  { how far out from the origin in pixels, and the step outward while a
    label would overlap one already placed }
  AXIS_TAG_OUT = 60;
  AXIS_TAG_STEP = 18;
var
  K, N, NPlaced: Integer;
  Len, T0, T1, Step, A, B2: Double;
  B: TP3;
  PO, PB, D: TPointF;
  Col: TPix;
  Placed: array[0..5] of TRect;

  { A label out along the axis from the origin, centered on the line and
    outlined in black so it reads over line and grid.  When orbiting can
    make two axes point the same way, a label that would overlap another
    moves further out.  Skipped when it would land off the paper. }
  procedure Tag(Sg: Integer; const S: string);
  var
    Sz: TSize;
    X, Y, Out_: Double;
    TX, TY, OX, OY, Try_, J: Integer;
    Box: TRect;
    Clear: Boolean;
  begin
    Sz := FPaper.TextExtent(S, FDimFont);
    Out_ := AXIS_TAG_OUT * FUIScale;
    for Try_ := 0 to 15 do
    begin
      X := PO.X + Sg * D.X * Out_;
      Y := PO.Y + Sg * D.Y * Out_;
      TX := Round(X - Sz.cx / 2); TY := Round(Y - Sz.cy / 2);
      Box := Rect(TX - 4, TY - 2, TX + Sz.cx + 4, TY + Sz.cy + 2);
      Clear := True;
      for J := 0 to NPlaced - 1 do
        if (Box.Left < Placed[J].Right) and (Placed[J].Left < Box.Right) and
           (Box.Top < Placed[J].Bottom) and (Placed[J].Top < Box.Bottom) then Clear := False;
      if Clear then Break;
      Out_ := Out_ + AXIS_TAG_STEP * FUIScale;
    end;
    if (X < Sz.cx) or (Y < Sz.cy) or (X > FPaper.Width - Sz.cx) or (Y > FPaper.Height - Sz.cy) then Exit;
    if NPlaced <= High(Placed) then
    begin
      Placed[NPlaced] := Box;
      Inc(NPlaced);
    end;
    for OX := -1 to 1 do
      for OY := -1 to 1 do
        if (OX <> 0) or (OY <> 0) then
          FPaper.TextOut(TX + OX, TY + OY, S, FDimFont, Pix(0, 0, 0));
    FPaper.TextOut(TX, TY, S, FDimFont, Col);
  end;

begin
  PO := ScreenOf(P3(0, 0, 0));
  if IsNan(PO.X) or IsNan(PO.Y) or IsInfinite(PO.X) or IsInfinite(PO.Y) then
    Exit;
  if (Abs(PO.X) > 1E7) or (Abs(PO.Y) > 1E7) then Exit;
  NPlaced := 0;

  for K := 0 to 2 do
  begin
    Col := AxisPix(K);

    { one world unit along this axis, to read its direction off the glass }
    B := P3(0, 0, 0);
    case K of
      0: B.X := 1;
      1: B.Y := 1;
    else B.Z := 1;
    end;
    PB := ScreenOf(B);
    Len := Sqrt(Sqr(PB.X - PO.X) + Sqr(PB.Y - PO.Y));
    { an axis pointing straight at the camera has no length on screen (PLAN
      looks down Z); skip it rather than draw a dot }
    if Len < 1E-9 then Continue;
    D := PtF((PB.X - PO.X) / Len, (PB.Y - PO.Y) / Len);

    { the piece of the infinite line that is actually on the paper }
    if not ClipToBox(PO.X, PO.Y, D.X, D.Y, FPaper.Width, FPaper.Height,
                     T0, T1) then Continue;

    { forwards from the origin, solid }
    A := Max(T0, 0);
    if T1 > A then
      FPaper.Line(PO.X + D.X * A, PO.Y + D.Y * A,
                  PO.X + D.X * T1, PO.Y + D.Y * T1, 1.8, Col, 0.55);

    { backwards, dashed, measured from the origin so the dashes do not crawl
      as you pan }
    B2 := Min(T1, 0);
    if T0 < B2 then
    begin
      Step := 11;
      N := Max(0, Trunc(-B2 / Step));
      while -N * Step > T0 do
      begin
        A := -N * Step;
        if A <= B2 then
          FPaper.Line(PO.X - D.X * (N * Step), PO.Y - D.Y * (N * Step),
                      PO.X - D.X * (N * Step + 6), PO.Y - D.Y * (N * Step + 6),
                      1.4, Col, 0.42);
        Inc(N);
        { far from the origin that is a lot of unseen dashes; stop }
        if N > 4000 then Break;
      end;
    end;

    if FShowGrid then
    begin
      Tag(1, AXIS_TAGS[K, 0]);
      Tag(-1, AXIS_TAGS[K, 1]);
    end;
  end;
  FPaper.Touch;
end;

{ everything the paper depends on, to compare with what it was last drawn for }
function TMainForm.PaperSig: TPaperSig;
begin
  { zeroed whole, because it is compared whole: padding bytes would make
    equal records compare unequal }
  FillChar(Result, SizeOf(Result), 0);
  Result.ThemeIdx := FThemeIdx;
  Result.W := FPaper.Width;
  Result.H := FPaper.Height;
  Result.View := FD.View;
  Result.Units := FD.Units;
  Result.Grid := FShowGrid;
  Result.Ppu := Ppu;
  Result.ViewX := FD.ViewX;
  Result.ViewY := FD.ViewY;
  Result.Az := FD.Az;
  Result.El := FD.El;
  Result.Zoom := FD.Zoom;
  Result.Snap := SnapStep;
  Result.UIScale := FUIScale;
end;

{ The paper, its grid and the axes.  Redrawn only when something it depends
  on changed (see PaperSig), not on every request.  The signature must name
  everything the picture depends on or the paper goes stale.  Nothing outside
  this and the two procedures it calls draws on FPaper, so one guard here is
  enough. }
procedure TMainForm.RepaintPaper;
var
  Key: string;
  GridPitch: Double;
  T0, TBase, TGrid: QWord;
  Sig: TPaperSig;
begin
  Sig := PaperSig;
  if FPaperOK and CompareMem(@Sig, @FPaperSig, SizeOf(Sig)) then
  begin
    Inc(FPaperSkips);
    Exit;
  end;
  FPaperSig := Sig;
  FPaperOK := True;
  Inc(FPaperPaints);
  T0 := GetTickCount64;
  try
  { The fill does not move with the camera, so it is made once per theme
    and size and copied.  Copying also keeps the grain from crawling. }
  Key := Format('%d %d %d', [FThemeIdx, FPaper.Width, FPaper.Height]);
  if (FPaperBase = nil) or (Key <> FPaperBaseKey) then
  begin
    if FPaperBase = nil then
      FPaperBase := TArtSurface.Create(FPaper.Width, FPaper.Height)
    else
      FPaperBase.SetSize(FPaper.Width, FPaper.Height);
    PaintScreenPaper(FPaperBase, Theme);
    FPaperBaseKey := Key;
  end;
  FPaper.CopyRegion(FPaperBase, 0, 0, 0, 0, FPaper.Width, FPaper.Height);
  TBase := GetTickCount64;
  if FShowGrid then
  begin
    { The pitch steps through the scale bar's round numbers (an inch,
      three, six, a foot, five feet) so the lattice stays a comfortable
      size at any zoom. }
    GridPitch := NiceBarLength(Ppu, 14 * FUIScale, 60 * FUIScale, FD.Units);
    { Never finer than the snap step, or some crossings cannot be landed
      on.  Every snap divides a foot exactly, so any pitch at or above it
      keeps crossings snappable. }
    if GridPitch < SnapStep then GridPitch := SnapStep;
    GridPitch := GridPitch * Ppu;
    case FD.View of
      { Plan is ruled like paper.  Iso and 3D get a floor in the red-green
        plane that turns with the camera; ruling the walls too reads as
        paper, not a floor. }
      vkPlan: PaintMeasuredGrid(FPaper, Theme, GridPitch, FD.ViewX, FD.ViewY, 5);
      vkIso, vkOrbit: PaintGroundGrid(GridPitch / Ppu);
    end;
  end;
  TGrid := GetTickCount64;
  PaintAxes;
  { where the paper's time really goes (numbers in TODO-archive.md) }
  if FTimings then
  begin
    TimingLine(Format('paper: painted %d, skipped %d - base %d, grid %d, axes %d',
      [FPaperPaints, FPaperSkips, TBase - T0, TGrid - TBase,
       GetTickCount64 - TGrid]));
  end;
  finally
    FMsPaper := FMsPaper + (GetTickCount64 - T0);
  end;
end;

procedure TMainForm.Recompose;
var
  R: TRect;
begin
  R := FInk.TakeDirty;
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then Exit;
  InflateRect(R, 1, 1);
  FArt.CompositeOver(FPaper, FInk, R);
  FShotOK := False;
  FScreenDirty := True;
end;

procedure TMainForm.RecomposeAll;
var
  T0: QWord;
begin
  FShotOK := False;
  T0 := GetTickCount64;
  FArt.CompositeOver(FPaper, FInk, Rect(0, 0, FArt.Width, FArt.Height));
  FInk.ResetDirty;
  FScreenDirty := True;
  FMsComp := FMsComp + (GetTickCount64 - T0);
end;

procedure TMainForm.FreshScreen;
begin
  RepaintPaper;
  RecomposeAll;
end;

{ Redraw the whole document.  Everything is stored as geometry, so zoom,
  pan, scale and units all come down to calling this again; nothing is
  resampled. }
procedure TMainForm.RenderInk;
var
  T0: QWord;
  Half: TArtSurface;
begin
  T0 := GetTickCount64;
  try
  FD.Doc.Quick := FCameraMoving and FQuickFrames;
  { Half resolution only pays when fill is the cost (zoomed in on a big
    drawing) and loses a little otherwise.  So the first moving frame is
    full size, and if it was slow the rest of the move is drawn at half.  A
    still frame resets it. }
  if not FD.Doc.Quick then FMoveHalf := False;
  Half := nil;
  if FMoveHalf then Half := FInkHalf;
  FInk.QuickFill := FD.Doc.Quick;
  FInk.ClearTransparent;
  { A fault while drawing would recur every frame and make the program
    impossible to start.  So drawing stops and says so; saving, undo and
    everything else still work. }
  if FRenderBroken then Exit;
  try
    if FD.Doc.Live > 0 then
      FD.Doc.Render(FInk, Proj, FD.Units, FDimFont, AnnotColor, FEdgeW, Half);
      if FD.Doc.Quick and not FMoveHalf and (GetTickCount64 - T0 > 25) then
        FMoveHalf := True;
  except
    on E: Exception do
    begin
      FRenderBroken := True;
      FCmdMsg := 'Something in this drawing will not draw (' + E.ClassName +
        ').  Ctrl+Z, or save it and send it in - nothing is lost.';
    end;
  end;
  FInk.MarkAllDirty;
  finally
    FMsRender := FMsRender + (GetTickCount64 - T0);
  end;
end;

procedure TMainForm.RefreshChrome;
begin
  RebuildShell;
  RebuildDeck;
  Invalidate;
  pbDeck.Invalidate;
  pbCmd.Invalidate;
end;

procedure TMainForm.InvalidateStatus;
var
  R: TRect;
  Now64: QWord;
begin
  Now64 := GetTickCount64;
  if Now64 - FLastStatus < 60 then Exit;
  FLastStatus := Now64;
  { the whole title strip, however high it is }
  R := Rect(ClientWidth div 3, 0, ClientWidth, TitleHeight + Round(2 * FUIScale));
  LCLIntf.InvalidateRect(Handle, @R, False);
  pbCmd.Invalidate;
end;

procedure TMainForm.FormResize(Sender: TObject);
begin
  Relayout;
end;

{ ======================================================================== }
{ view: zoom, pan, origin                                                   }
{ ======================================================================== }

{ Would the current camera show any of the drawing?  Asked of a camera read
  from a file or handoff before trusting it: the projected bounds must land
  near the paper and be more than a few pixels across. }
function TMainForm.CameraShowsSomething: Boolean;
var
  Lo, Hi, C: TP3;
  P: TPointF;
  K: Integer;
  MinX, MinY, MaxX, MaxY, Margin: Double;
begin
  Result := True;
  if FD.Zoom <= ZOOM_MIN * 1.01 then Exit(False);
  if not FD.Doc.Bounds(Lo, Hi) then Exit;
  MinX := 1E30; MinY := 1E30; MaxX := -1E30; MaxY := -1E30;
  for K := 0 to 7 do
  begin
    C := P3(IfThen(K and 1 = 0, Lo.X, Hi.X), IfThen(K and 2 = 0, Lo.Y, Hi.Y),
            IfThen(K and 4 = 0, Lo.Z, Hi.Z));
    P := Project(Proj, C);
    if IsNan(P.X) or IsNan(P.Y) or IsInfinite(P.X) or IsInfinite(P.Y) then Exit(False);
    MinX := Min(MinX, P.X); MaxX := Max(MaxX, P.X);
    MinY := Min(MinY, P.Y); MaxY := Max(MaxY, P.Y);
  end;
  { smaller than a fingertip: zoomed out to nothing }
  if Max(MaxX - MinX, MaxY - MinY) < 6 then Exit(False);
  { or panned off; a few screens away is still findable by hand }
  Margin := 3 * Max(FArt.Width, FArt.Height);
  if (MaxX < -Margin) or (MaxY < -Margin) or
     (MinX > FArt.Width + Margin) or (MinY > FArt.Height + Margin) then Exit(False);
end;

procedure TMainForm.ZoomAt(Factor: Double; AnchorSX, AnchorSY: Double);
var
  W: TP3;
  P: TPointF;
  NewZoom: Double;
begin
  NewZoom := EnsureRange(FD.Zoom * Factor, ZOOM_MIN, ZOOM_MAX);
  if NewZoom = FD.Zoom then Exit;
  { keep what is under the anchor point exactly where it is }
  W := WorldAt(AnchorSX, AnchorSY);
  FD.Zoom := NewZoom;
  P := Project(Proj, W);
  FD.ViewX := FD.ViewX + (AnchorSX - P.X);
  FD.ViewY := FD.ViewY + (AnchorSY - P.Y);
  { a wheel zoom is a moving camera too: quick now, full when it settles }
  if FQuickFrames then
  begin
    FCameraMoving := True;
    FLastWheel := GetTickCount64;
  end;
  ViewMoved;
end;

procedure TMainForm.SetScaleIdx(I: Integer);
var
  CX, CY: Double;
  W: TP3;
  P: TPointF;
begin
  Act('scale ' + IntToStr(I));
  I := EnsureRange(I, 0, SCALE_COUNT - 1);
  if I = FD.ScaleIdx then Exit;
  CX := FArt.Width / 2;
  CY := FArt.Height / 2;
  W := WorldAt(CX, CY);
  FD.ScaleIdx := I;
  P := Project(Proj, W);
  FD.ViewX := FD.ViewX + (CX - P.X);
  FD.ViewY := FD.ViewY + (CY - P.Y);
  RepaintPaper;
  RenderInk;
  RecomposeAll;
  RebuildDeck;
  pbDeck.Invalidate;
  Invalidate;
end;

procedure TMainForm.PanBy(DX, DY: Double);
begin
  FD.ViewX := FD.ViewX + DX;
  FD.ViewY := FD.ViewY + DY;
  ViewMoved;
end;

{ The camera moved: mark the view, and the tick draws it once however many
  changes came in.  A wheel or touchpad sends far more events than frames,
  and redrawing (and invalidating the whole window) per event made zooming
  sluggish.  A paint that arrives first draws it itself. }
procedure TMainForm.ViewMoved;
begin
  FViewDirty := True;
  FScreenDirty := True;
  InvalidateStatus;
end;

procedure TMainForm.FlushView;
begin
  if not FViewDirty then Exit;
  FViewDirty := False;
  RepaintPaper;
  RenderInk;
  RecomposeAll;
end;

{ re-center the coordinate readout on the picked point without moving the
  drawing }
procedure TMainForm.SetOriginHere;
var
  P: TPointF;
begin
  P := ScreenOf(FCur);
  FD.ViewX := P.X;
  FD.ViewY := P.Y;
  FCur := P3(0, 0, 0);
  RepaintPaper;
  RenderInk;
  RecomposeAll;
  FCmdMsg := 'Origin moved.';
  Invalidate;
end;

{ Frame the drawing, or reset to an empty sheet's view.  It glides there
  when there is a window to watch and the change is worth seeing, so you
  keep track of where things are.  Not while loading, not in a paper mode,
  and not for a tiny nudge. }
procedure TMainForm.FitView(Travel: Boolean = True);
var
  Lo, Hi, Mid: TP3;
  P: TPointF;
  BaseP, W, H, Z, NewZoom: Double;
  FitZ, FitX, FitY: Double;
begin
  if Travel and FBooted and (FD <> nil) and
     (FD.View = vkOrbit) and
     (FGlideT = 0) and FitTarget(False, FD.Az, FD.El, FitZ, FitX, FitY) and
     ((Abs(FitZ - FD.Zoom) > 0.02 * Max(1, FD.Zoom)) or
      (Abs(FitX - FD.ViewX) > 4) or (Abs(FitY - FD.ViewY) > 4)) then
  begin
    GlideCamera(FD.Az, FD.El, FitZ, FitX, FitY);
    if FGlideT > 0 then Exit;
  end;

  if not FD.Doc.Bounds(Lo, Hi) then
  begin
    FD.Zoom := 1.0;
    FD.ViewX := Round(FArt.Width * 0.10);
    FD.ViewY := Round(FArt.Height * 0.88);
  end
  else
  begin
    { measure the drawing in projected pixels at zoom 1, then fit }
    BaseP := PixelsPerUnit(FD.Units, CurScale, Screen.PixelsPerInch);
    case FD.View of
      vkIso:
        begin
          W := Max((Abs(Hi.X - Lo.X) + Abs(Hi.Y - Lo.Y)) * ISO_COS, 1E-6);
          H := Max((Hi.X - Lo.X + Hi.Y - Lo.Y) * ISO_SIN + (Hi.Z - Lo.Z), 1E-6);
        end;
      vkOrbit:
        begin
          { the diagonal is a safe bound from any camera angle }
          W := Max(Sqrt(Sqr(Hi.X - Lo.X) + Sqr(Hi.Y - Lo.Y) + Sqr(Hi.Z - Lo.Z)), 1E-6);
          H := W;
        end;
    else
      begin
        W := Max(Hi.X - Lo.X, 1E-6);
        H := Max(Hi.Y - Lo.Y, 1E-6);
      end;
    end;
    Z := Min((FArt.Width * 0.80) / (W * BaseP), (FArt.Height * 0.80) / (H * BaseP));
    { Through a local and clamped by hand, like FD.El (see ServiceMotion):
      assigning a Double field of FD straight from EnsureRange was
      miscompiled at -O3. }
    NewZoom := Z;
    if NewZoom < ZOOM_MIN then NewZoom := ZOOM_MIN;
    if NewZoom > ZOOM_MAX then NewZoom := ZOOM_MAX;
    FD.Zoom := NewZoom;
    Mid := P3((Lo.X + Hi.X) / 2, (Lo.Y + Hi.Y) / 2, (Lo.Z + Hi.Z) / 2);
    FD.ViewX := 0;
    FD.ViewY := 0;
    P := Project(Proj, Mid);
    FD.ViewX := FArt.Width / 2 - P.X;
    FD.ViewY := FArt.Height / 2 - P.Y;
  end;
  RepaintPaper;
  RenderInk;
  RecomposeAll;
  Invalidate;
end;

{ ======================================================================== }
{ drawings and tabs                                                         }
{ ======================================================================== }

constructor TDrawing.Create(const AName: string);
begin
  inherited Create;
  Doc := TWorkDoc.Create;
  Name := AName;
  Zoom := 1.0;
  ScaleIdx := 2;          // 1/4" = 1'-0"
  SnapIdx := 5;           // one foot
  Units := usImperial;
  { A new sheet opens on the 3D corner view.  PLAN suits a floor plan but
    gives nothing height, and everyone left it first thing. }
  View := vkOrbit;
  Plane := plXY;
  Az := -Pi / 4;
  El := 35.264 * Pi / 180;   // start on the isometric corner
  { Off, meaning the whole model; never hide part of a drawing by default. }
  SliceOn := False;
  SliceLo := 0;
  SliceHi := 8;
  SetLength(Undo, UNDO_LEVELS);
  SetLength(Redo, UNDO_LEVELS);
end;

destructor TDrawing.Destroy;
begin
  Doc.Free;
  inherited Destroy;
end;

{ A new sheet.  Key < 0 makes a new untitled one-sheet document; otherwise
  the sheet is added to document Key after its last tab. }
procedure TMainForm.NewDrawing(Key: Integer);
var
  N, K, Nm, At, Src: Integer;
  Taken: Boolean;
  D: TDrawing;
begin
  N := Length(FDrawings);
  Src := -1;
  if Key >= 0 then
    for K := 0 to N - 1 do
      if FDrawings[K].DocKey = Key then Src := K;
  if Src < 0 then Key := -1;
  { the lowest 'Sheet k' its file does not have already }
  Nm := 1;
  repeat
    Taken := False;
    for K := 0 to N - 1 do
      if (Key >= 0) and (FDrawings[K].DocKey = Key) and (FDrawings[K].Name = Format('Sheet %d', [Nm])) then
        Taken := True;
    if Taken then Inc(Nm);
  until not Taken;
  D := TDrawing.Create(Format('Sheet %d', [Nm]));
  if (N > 0) and (FD <> nil) then
  begin
    { a new sheet inherits how you were working }
    D.ScaleIdx := FD.ScaleIdx;
    D.SnapIdx := FD.SnapIdx;
    D.Units := FD.Units;
    D.View := FD.View;
  end;
  if Key < 0 then
  begin
    { a drawing of its own: a one-sheet file, not saved yet, and blank }
    Inc(FNextDocKey);
    D.DocKey := FNextDocKey;
    Inc(FUntitled);
    D.DocName := Format('Untitled %d', [FUntitled]);
    D.FilePath := '';
    At := N;
  end
  else
  begin
    { a sheet added to a file goes after that file's last tab, and the file
      is now changed }
    D.DocKey := Key;
    D.DocName := FDrawings[Src].DocName;
    D.FilePath := FDrawings[Src].FilePath;
    D.Dirty := True;
    At := Src + 1;
  end;
  SetLength(FDrawings, N + 1);
  for K := N downto At + 1 do FDrawings[K] := FDrawings[K - 1];
  FDrawings[At] := D;
  FTabIdx := At;
  LeaveSheet;
  FD := D;
  FD.ViewX := Round(FArt.Width * 0.10);
  FD.ViewY := Round(FArt.Height * 0.88);
  if FBooted then
  begin
    ResetTool;
    LayoutTabs;
    RepaintPaper;
    RenderInk;
    RecomposeAll;
    RefreshChrome;
  end;
end;

procedure TMainForm.SelectDrawing(I: Integer);
begin
  if (I < 0) or (I > High(FDrawings)) or (I = FTabIdx) then Exit;
  LeaveSheet;
  FTabIdx := I;
  FD := FDrawings[I];
  ResetTool;
  RepaintPaper;
  RenderInk;
  RecomposeAll;
  RebuildDeck;
  pbDeck.Invalidate;
  pbTabs.Invalidate;
  Invalidate;
end;

{ The tab's cross, Ctrl+W, /close: closes the whole file the tab belongs to,
  asking about unsaved work first. }
procedure TMainForm.CloseDrawing(I: Integer);
begin
  if (I < 0) or (I > High(FDrawings)) then Exit;
  CloseDocument(FDrawings[I].DocKey);
end;

function TMainForm.DocPath: string;
begin
  if FD = nil then Result := '' else Result := FD.FilePath;
end;

function TMainForm.DocSheets(Key: Integer): TIntArrayW;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(FDrawings) do
    if FDrawings[I].DocKey = Key then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := I;
    end;
end;

{ A file changed since it was opened or saved has work in it, whatever is
  left on it; an untitled drawing with nothing on it has nothing to lose. }
function TMainForm.DocDirty(Key: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(FDrawings) do
    if (FDrawings[I].DocKey = Key) and FDrawings[I].Dirty and
       ((FDrawings[I].FilePath <> '') or (FDrawings[I].Doc.Live > 0)) then Exit(True);
end;

function TMainForm.TabCaption(I: Integer): string;
begin
  Result := FDrawings[I].DocName;
  if Length(DocSheets(FDrawings[I].DocKey)) > 1 then Result := Result + ': ' + FDrawings[I].Name;
  if DocDirty(FDrawings[I].DocKey) then Result := Result + ' *';
end;

function TMainForm.AskToSave(Key: Integer; const Title: string): Boolean;
var
  S: TIntArrayW;
  Ans: Integer;
  Where: string;
begin
  Result := True;
  if not DocDirty(Key) then Exit;
  S := DocSheets(Key);
  if Length(S) = 0 then Exit;
  { bring its drawing to the front while asking }
  if FDrawings[FTabIdx].DocKey <> Key then SelectDrawing(S[0]);
  if FDrawings[S[0]].FilePath <> '' then Where := FDrawings[S[0]].FilePath
  else Where := 'It has not been saved to a file yet.';
  Ans := QuestionDlg(Title,
    Format('Save the changes to "%s"?', [FDrawings[S[0]].DocName]) + LineEnding + LineEnding + Where,
    mtConfirmation,
    [mrYes, 'Save', 'IsDefault',
     mrNo, 'Don''t save',
     mrCancel, 'Cancel', 'IsCancel'], 0);
  if Ans = mrCancel then Exit(False);
  { Save; a refused name or failed write keeps it open }
  if Ans = mrYes then Result := SaveDocument(Key, False);
end;

function TMainForm.CloseDocument(Key: Integer): Boolean;
var
  K, J: Integer;
  DocNm: string;
begin
  Result := AskToSave(Key, 'Close');
  if not Result then Exit;
  DocNm := '';
  LeaveSheet;
  J := 0;
  for K := 0 to High(FDrawings) do
    if FDrawings[K].DocKey = Key then
    begin
      DocNm := FDrawings[K].DocName;
      FDrawings[K].Free;
    end
    else
    begin
      FDrawings[J] := FDrawings[K];
      Inc(J);
    end;
  SetLength(FDrawings, J);
  FD := nil;
  { closing the last file leaves a new empty drawing, as at startup }
  FDraftSeq := -1;
  if Length(FDrawings) = 0 then
  begin
    NewDrawing(-1);
    FCmdMsg := 'Closed ' + DocNm + '.  A new empty drawing - MENU or Ctrl+O to open one.';
    pbCmd.Invalidate;
    Exit;
  end;
  FTabIdx := EnsureRange(FTabIdx, 0, High(FDrawings));
  FD := FDrawings[FTabIdx];
  FDraftSeq := -1;
  ResetTool;
  LayoutTabs;
  RepaintPaper;
  RenderInk;
  RecomposeAll;
  RefreshChrome;
  FCmdMsg := 'Closed ' + DocNm + '.';
  pbCmd.Invalidate;
end;

procedure TMainForm.LayoutTabs;
begin
  PlaceTabs;
  pbTabs.Invalidate;
end;

{ Where each tab goes.  Recomputed every paint: a tab is as wide as its
  caption, which changes (a star for unsaved work). }
procedure TMainForm.PlaceTabs;
var
  I, X, W, TabH, Pad: Integer;
begin
  SetLength(FTabRects, Length(FDrawings) + 1);   // one extra for the + button
  if not pbTabs.Visible then Exit;
  TabH := pbTabs.Height;
  X := 0;
  { as wide as its caption, within limits; tabs of one file sit close and a
    wider gap separates files }
  UIFont(pbTabs.Canvas, 10, True, Theme.Text);
  for I := 0 to High(FDrawings) do
  begin
    W := EnsureRange(pbTabs.Canvas.TextWidth(TabCaption(I)) + Round(44 * FUIScale),
      Round(110 * FUIScale), Round(300 * FUIScale));
    FTabRects[I] := Rect(X, 0, X + W, TabH);
    if (I < High(FDrawings)) and (FDrawings[I + 1].DocKey = FDrawings[I].DocKey) then
      Pad := Round(1 * FUIScale)
    else
      Pad := Round(8 * FUIScale);
    Inc(X, W + Pad);
  end;
  FTabRects[High(FTabRects)] := Rect(X, 0, X + Round(30 * FUIScale), TabH);
end;

procedure TMainForm.pbTabsPaint(Sender: TObject);
var
  I, TW: Integer;
  R: TRect;
  IsCur, Hot: Boolean;
  C1, C2, Edge: TPix;
  S: string;
begin
  PlaceTabs;

  FCmdSkin.SetSize(pbTabs.Width, pbTabs.Height);
  FCmdSkin.Clear(Pix(0, 0, 0));
  FCmdSkin.CopyRegion(FShell, pbTabs.Left, pbTabs.Top, 0, 0,
    pbTabs.Width, pbTabs.Height);

  for I := 0 to High(FDrawings) do
  begin
    R := FTabRects[I];
    IsCur := I = FTabIdx;
    Hot := I = FHotTab;
    if IsCur then
    begin
      C1 := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.14);
      C2 := Theme.Panel;
      Edge := ShadePix(Theme.Accent, 0.9);
    end
    else if Hot then
    begin
      C1 := MixPix(Theme.Panel, Pix(255, 255, 255), 0.10);
      C2 := MixPix(Theme.Panel, Pix(0, 0, 0), 0.10);
      Edge := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.20);
    end
    else
    begin
      C1 := MixPix(Theme.Panel, Pix(0, 0, 0), 0.15);
      C2 := MixPix(Theme.Panel, Pix(0, 0, 0), 0.30);
      Edge := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.08);
    end;
    { square off the bottom so the active tab reads as joined to the sheet }
    FCmdSkin.RoundRectV(Rect(R.Left, R.Top, R.Right, R.Bottom + Round(10 * FUIScale)),
      Round(9 * FUIScale), C1, C2);
    FCmdSkin.RoundFrame(Rect(R.Left, R.Top, R.Right, R.Bottom + Round(10 * FUIScale)),
      Round(9 * FUIScale), 1.0, Edge, 0.9);
    if IsCur then
      FCmdSkin.RoundRect(Rect(R.Left + Round(10 * FUIScale), R.Top + Round(3 * FUIScale),
        R.Right - Round(10 * FUIScale), R.Top + Round(6 * FUIScale)),
        1.5, Theme.Accent, 0.95);
    { The close cross is on the current tab, even when it is the only one;
      hiding it left no visible way to close the drawing.  Closing the last
      file leaves a new empty one. }
    if IsCur then
    begin
      FCmdSkin.Line(R.Right - Round(20 * FUIScale), R.Top + Round(12 * FUIScale),
        R.Right - Round(12 * FUIScale), R.Top + Round(20 * FUIScale), 1.5, Theme.TextDim, 0.9);
      FCmdSkin.Line(R.Right - Round(12 * FUIScale), R.Top + Round(12 * FUIScale),
        R.Right - Round(20 * FUIScale), R.Top + Round(20 * FUIScale), 1.5, Theme.TextDim, 0.9);
    end;
  end;

  { the + button }
  R := FTabRects[High(FTabRects)];
  Hot := FHotTab = High(FTabRects);
  if Hot then
    FCmdSkin.RoundRect(R, Round(8 * FUIScale),
      MixPix(Theme.Panel, Pix(255, 255, 255), 0.12))
  else
    FCmdSkin.RoundRect(R, Round(8 * FUIScale),
      MixPix(Theme.Panel, Pix(0, 0, 0), 0.20));
  FCmdSkin.Line((R.Left + R.Right) / 2, R.Top + Round(9 * FUIScale),
    (R.Left + R.Right) / 2, R.Bottom - Round(9 * FUIScale), 1.6, Theme.Text, 0.85);
  FCmdSkin.Line(R.Left + Round(9 * FUIScale), (R.Top + R.Bottom) / 2,
    R.Right - Round(9 * FUIScale), (R.Top + R.Bottom) / 2, 1.6, Theme.Text, 0.85);

  FCmdSkin.DrawTo(pbTabs.Canvas, 0, 0);

  for I := 0 to High(FDrawings) do
  begin
    R := FTabRects[I];
    if I = FTabIdx then
      UIFont(pbTabs.Canvas, 10, True, Theme.Text)
    else
      UIFont(pbTabs.Canvas, 10, False, Theme.TextDim);
    S := TabCaption(I);
    { shortened to fit, leaving room for the close cross }
    S := CutToFit(pbTabs.Canvas, S, R.Right - R.Left - Round(36 * FUIScale));
    TW := pbTabs.Canvas.TextWidth(S);
    pbTabs.Canvas.TextOut(R.Left + Round(12 * FUIScale),
      (R.Top + R.Bottom - pbTabs.Canvas.TextHeight(S)) div 2, S);
    if TW = 0 then ;
  end;
end;

procedure TMainForm.pbTabsMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  I, H: Integer;
begin
  H := -1;
  for I := 0 to High(FTabRects) do
    if PtInRect(FTabRects[I], Point(X, Y)) then
    begin
      H := I;
      Break;
    end;
  if H <> FHotTab then
  begin
    FHotTab := H;
    pbTabs.Invalidate;
  end;
end;

procedure TMainForm.pbTabsMouseLeave(Sender: TObject);
begin
  if FHotTab <> -1 then
  begin
    FHotTab := -1;
    pbTabs.Invalidate;
  end;
end;

procedure TMainForm.pbTabsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  R: TRect;
begin
  if Button <> mbLeft then Exit;
  for I := 0 to High(FDrawings) do
  begin
    R := FTabRects[I];
    if not PtInRect(R, Point(X, Y)) then Continue;
    if (I = FTabIdx) and (X > R.Right - Round(26 * FUIScale)) then
      CloseDrawing(I)
    else
      SelectDrawing(I);
    Exit;
  end;
  if PtInRect(FTabRects[High(FTabRects)], Point(X, Y)) then
    NewDrawing;
end;

{ ======================================================================== }
{ control deck                                                              }
{ ======================================================================== }

procedure TMainForm.RebuildDeck;
var
  W, H, Pad, LabW, RowH, RowGap, IconW: Integer;
  Y0, RowY, X, Avail, SegW: Integer;
  NSet, NamedW: Integer;
  NamedIcons: Boolean;

  procedure Add(K: TDeckKind; const B: TRect; G, V: Integer;
    const Cap, Hnt: string; Ic: TIconKind);
  var
    M: Integer;
  begin
    M := Length(FDeck);
    SetLength(FDeck, M + 1);
    FDeck[M].Kind := K;
    FDeck[M].Bounds := B;
    FDeck[M].Group := G;
    FDeck[M].Value := V;
    FDeck[M].Caption := Cap;
    FDeck[M].Hint := Hnt;
    FDeck[M].Icon := Ic;
  end;

  { The same six, with a word each; a word beats a pictogram for someone who
    has not learned the pictogram yet. }
  procedure AddNamed6(RY: Integer; const A: array of Integer;
    const K: array of TIconKind; const N: array of string;
    const H: array of string);
  var
    IX, J, BW: Integer;
  begin
    BW := NamedW;
    IX := W - Pad - Length(A) * BW - (Length(A) - 1) * RowGap;
    for J := 0 to High(A) do
    begin
      { narrow: picture only, name in the tooltip (see where NamedIcons is
        set) }
      if NamedIcons then
        Add(dkIcon, Rect(IX, RY, IX + BW, RY + RowH), GRP_ICON, A[J], '',
          N[J] + ' - ' + H[J], K[J])
      else
        Add(dkSegment, Rect(IX, RY, IX + BW, RY + RowH), GRP_ICON, A[J], N[J],
          H[J], K[J]);
      Inc(IX, BW + RowGap);
    end;
  end;

begin
  SetLength(FDeck, 0);
  W := FDeckSkin.Width;
  H := FDeckSkin.Height;
  { Do not build into nothing.  The floor is one row plus padding; a higher
    floor once silently emptied the single-row deck. }
  if (W < 40) or (H < 24) then Exit;

  Pad := Round(14 * FUIScale);
  LabW := Round(74 * FUIScale);
  RowH := DeckRowH;
  RowGap := Round(4 * FUIScale);
  IconW := Round(34 * FUIScale);

  Y0 := (H - (DeckRows * RowH + (DeckRows - 1) * RowGap)) div 2;
  X := Pad + LabW;

  { --- the tools are on the strip down the left (see RebuildTools) ---
    What stays here is settings and actions on the program rather than
    the drawing. }
  FGrpDivY0 := 0;
  FGrpDivY1 := 0;
  FGrpDivX[0] := -1;
  FGrpDivX[1] := -1;

  { --- row 1: settings as buttons that open a list ---
    Scale, snap and pen are set once and left alone, so each is one button
    showing its value, with its list opening above. }
  RowY := Y0;
  { Five settings, always, in full words.  The guide buttons live on the
    right-click menu so this row never changes width. }
  NSet := 5;
  { On a narrow window the settings keep the room they need first and the
    six buttons shrink toward a floor that still fits "ORIGIN"; FitCaption
    handles whatever is still short. }
  Avail := W - 2 * Pad - LabW - Round(18 * FUIScale);
  NamedW := (Avail - (NSet * Round(128 * FUIScale) + (NSet - 1) * RowGap)
             - 5 * RowGap) div 6;
  NamedW := EnsureRange(NamedW, Round(60 * FUIScale), Round(88 * FUIScale));
  { Narrower still, the six drop their words and keep their pictures (the
    word stays in the tooltip); a settings button cut to "1/16\"" no
    longer says what it sets. }
  NamedIcons := (Avail - (6 * NamedW + 5 * RowGap) - (NSet - 1) * RowGap)
    div NSet < Round(112 * FUIScale);
  if NamedIcons then NamedW := IconW;
  Avail := Avail - (6 * NamedW + 5 * RowGap);
  SegW := (Avail - (NSet - 1) * RowGap) div NSet;
  Add(dkSegment, Rect(X + 4 * SegW, RowY, X + 5 * SegW - RowGap,
    RowY + RowH), GRP_POPUP, POP_PREC,
    IfThen(FLenDenom = 100,
      'ROUNDED TO  .01"', Format('ROUNDED TO  1/%d"', [FLenDenom])),
    'How finely a length is written down, and what the last field of a ' +
    'dashed entry counts in - 6-8-15 is feet, inches and sixteenths.  ' +
    'It never changes what the drawing holds.', ikDroplet);
  Add(dkSegment, Rect(X, RowY, X + SegW - RowGap, RowY + RowH),
    GRP_POPUP, POP_SCALE,
    'PRINT SCALE  ' + ScaleTable(FD.Units, FD.ScaleIdx).Name,
    'What one foot measures on the paper when this sheet is printed.',
    ikDroplet);
  Add(dkSegment, Rect(X + SegW, RowY, X + 2 * SegW - RowGap, RowY + RowH),
    GRP_POPUP, POP_SNAP, 'SNAP TO  ' + SnapName(FD.Units, FD.SnapIdx),
    'The step the cursor moves in when it is not on a point of the ' +
    'drawing.  It is also what the arrows on the cut fields step by.',
    ikDroplet);
  Add(dkSegment, Rect(X + 2 * SegW, RowY, X + 3 * SegW - RowGap, RowY + RowH),
    GRP_POPUP, POP_COLOR, 'LINE COLOR',
    'The color new lines are drawn in.', ikDroplet);
  Add(dkSegment, Rect(X + 3 * SegW, RowY, X + 4 * SegW - RowGap, RowY + RowH),
    GRP_POPUP, POP_WIDTH, Format('LINE WIDTH  %d px', [FEdgeW]),
    'How thick every edge in this drawing is drawn.  It is one setting for ' +
    'the whole sheet, the way SketchUp does it - not a property of the ' +
    'line you happen to be drawing.', ikDroplet);

  { File actions are at the top left (see RebuildQuick).  These are about
    the view and the program, each with a word. }
  AddNamed6(Y0,
    [ACT_FIT, ACT_ORIGIN, ACT_GRID, ACT_UNITS, ACT_THEME, ACT_HELP],
    [ikFit, ikOrigin, ikGrid, ikUnits, ikTheme, ikHelp],
    ['FIT', 'ORIGIN', 'GRID', 'UNITS', 'THEME', 'HELP'],
    ['Frame the whole drawing  (F)',
     'Put 0,0 under the cursor  (O)',
     'Show or hide the measured grid  (G)',
     'Feet-and-inches or metric  (U)',
     'Light chrome or dark  (T)',
     'Help, downloads and updates  (F1 for about)']);
end;

function TMainForm.DeckHit(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FDeck) do
    if PtInRect(FDeck[I].Bounds, Point(X, Y)) then
      Exit(I);
  Result := -1;
end;

function TMainForm.IconLit(Value: Integer): Boolean;
begin
  case Value of
    ACT_GRID: Result := FShowGrid;
    ACT_UNITS: Result := FD.Units = usMetric;
  else
    Result := False;
  end;
end;

function TMainForm.IconEnabled(Value: Integer): Boolean;
begin
  case Value of
    ACT_UNDO: Result := CanUndo;
    ACT_REDO: Result := CanRedo;
  else
    Result := True;
  end;
end;

{ A button's words, made to fit its width.  In order: the whole caption; the
  label cut to one word ("PRINT SCALE  1\"" to "SCALE  1\""); only the value
  after the double space; then cut with an ellipsis.  Text must never run
  over a neighbor. }
function FitCaption(C: TCanvas; const S: string; Room: Integer): string;
const
  SHORT: array[0..4, 0..1] of string = (
    ('PRINT SCALE', 'SCALE'), ('SNAP TO', 'SNAP'), ('LINE COLOR', 'COLOR'),
    ('LINE WIDTH', 'WIDTH'), ('ROUNDED TO', 'ROUND'));
var
  K, P: Integer;
begin
  Result := S;
  if (Room <= 0) or (C.TextWidth(Result) <= Room) then Exit;
  for K := 0 to High(SHORT) do
    if Pos(SHORT[K, 0], Result) = 1 then
    begin
      Result := SHORT[K, 1] + Copy(Result, Length(SHORT[K, 0]) + 1, MaxInt);
      Break;
    end;
  if C.TextWidth(Result) <= Room then Exit;
  P := Pos('  ', Result);
  if P > 0 then Result := Trim(Copy(Result, P + 2, MaxInt));
  if C.TextWidth(Result) <= Room then Exit;
  Result := CutToFit(C, Result, Room);
end;

procedure TMainForm.pbDeckPaint(Sender: TObject);
var
  Room: Integer;
  I, TW: Integer;
  It: TDeckItem;
  Sel, Hot, Ena: Boolean;
  C1, C2, Edge, Fg: TPix;
  R, IR: TRect;
  Pad, RowH, RowGap, Y0: Integer;

  function Selected(const A: TDeckItem): Boolean;
  begin
    Result := ((A.Group = GRP_TOOL) and (A.Value = Ord(FTool))) or
              ((A.Group = GRP_SCALE) and (A.Value = FD.ScaleIdx)) or
              ((A.Group = GRP_SNAP) and (A.Value = FD.SnapIdx));
  end;

  procedure Section(Row: Integer; const S: string);
  begin
    UIFont(pbDeck.Canvas, 10, True, Theme.TextDim);
    TrackedText(pbDeck.Canvas, Pad,
      Y0 + Row * (RowH + RowGap) + (RowH - pbDeck.Canvas.TextHeight('X')) div 2,
      S, Round(1.5 * FUIScale));
  end;

begin
  PaintPanel(FDeckSkin, Rect(0, 0, FDeckSkin.Width, FDeckSkin.Height), Theme,
    Round(16 * FUIScale));

  { a hairline down each gap, so the tool groups read as groups }
  if (FGrpDivY1 > FGrpDivY0) then
    for I := 0 to 1 do
      FDeckSkin.Line(FGrpDivX[I], FGrpDivY0, FGrpDivX[I], FGrpDivY1,
        Max(1.0, FUIScale), MixPix(Theme.Panel, Theme.TextDim, 0.9), 0.9);

  for I := 0 to High(FDeck) do
  begin
    It := FDeck[I];
    Hot := (I = FHotItem);
    R := It.Bounds;

    case It.Kind of
      dkSegment:
        begin
          Sel := Selected(It);
          if Sel then
          begin
            C1 := ShadePix(Theme.Accent, 1.10);
            C2 := ShadePix(Theme.Accent, 0.80);
            Edge := ShadePix(Theme.Accent, 0.55);
          end
          else if Hot then
          begin
            C1 := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.22);
            C2 := MixPix(Theme.Panel, Pix(255, 255, 255), 0.10);
            Edge := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.35);
          end
          else
          begin
            C1 := MixPix(Theme.PanelHi, Pix(0, 0, 0), 0.20);
            C2 := MixPix(Theme.Panel, Pix(0, 0, 0), 0.25);
            Edge := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.12);
          end;
          PaintPill(FDeckSkin, R, Round(8 * FUIScale), C1, C2, Edge);
          if (It.Group = GRP_TOOL) then
          begin
            if Sel then Fg := OnPix(Theme.Accent) else Fg := Theme.Text;
            IR := Rect(R.Left + Round(5 * FUIScale),
              R.Top + Round(3 * FUIScale),
              R.Left + Round(5 * FUIScale) + (R.Bottom - R.Top) - Round(6 * FUIScale),
              R.Bottom - Round(3 * FUIScale));
            PaintIcon(FDeckSkin, It.Icon, IR, Fg, 0.95);
          end;
          { the color button shows the color }
          if (It.Group = GRP_POPUP) and (It.Value = POP_COLOR) then
            PaintSwatch(FDeckSkin,
              Rect(R.Left + Round(7 * FUIScale), R.Top + Round(4 * FUIScale),
                   R.Left + Round(29 * FUIScale), R.Bottom - Round(4 * FUIScale)),
              ColorToPix(FInkColor), False, False, Theme);

          { a settings button says there is more behind it }
          if It.Group = GRP_POPUP then
          begin
            if Sel then Fg := OnPix(Theme.Accent) else Fg := Theme.TextDim;
            IR := Rect(R.Right - Round(16 * FUIScale), R.Top,
              R.Right - Round(3 * FUIScale), R.Bottom);
            PaintIcon(FDeckSkin, ikChevron, IR, Fg, 0.9);
          end;
        end;

      dkIcon:
        begin
          Ena := IconEnabled(It.Value);
          Sel := IconLit(It.Value);
          if Sel then
          begin
            C1 := ShadePix(Theme.Accent, 1.10);
            C2 := ShadePix(Theme.Accent, 0.80);
            Edge := ShadePix(Theme.Accent, 0.55);
            Fg := Pix(20, 20, 24);
          end
          else
          begin
            if Hot and Ena then
            begin
              C1 := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.22);
              C2 := MixPix(Theme.Panel, Pix(255, 255, 255), 0.10);
            end
            else
            begin
              C1 := MixPix(Theme.PanelHi, Pix(0, 0, 0), 0.20);
              C2 := MixPix(Theme.Panel, Pix(0, 0, 0), 0.25);
            end;
            Edge := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.12);
            Fg := Theme.Text;
          end;
          PaintPill(FDeckSkin, R, Round(8 * FUIScale), C1, C2, Edge);
          IR := R;
          InflateRect(IR, -Round(6 * FUIScale), -Round(6 * FUIScale));
          if Ena then
            PaintIcon(FDeckSkin, It.Icon, IR, Fg, 0.95)
          else
            PaintIcon(FDeckSkin, It.Icon, IR, Theme.TextDim, 0.35);
        end;

      dkNone: ;
    end;
  end;

  FDeckSkin.DrawTo(pbDeck.Canvas, 0, 0);

  Pad := Round(14 * FUIScale);
  RowH := DeckRowH;
  RowGap := Round(4 * FUIScale);
  Y0 := (FDeckSkin.Height - (DeckRows * RowH + (DeckRows - 1) * RowGap)) div 2;

  { tools are down the left; only settings here }
  Section(0, 'SETTINGS');

  for I := 0 to High(FDeck) do
  begin
    It := FDeck[I];
    if It.Kind <> dkSegment then Continue;
    if Selected(It) then
      UIFont(pbDeck.Canvas, 10, True, OnPix(Theme.Accent))
    else
      UIFont(pbDeck.Canvas, 10, False, Theme.Text);
    { room for the words after the swatch, the chevron and a margin }
    Room := It.Bounds.Right - It.Bounds.Left - Round(10 * FUIScale);
    if It.Group = GRP_POPUP then Dec(Room, Round(16 * FUIScale));
    if (It.Group = GRP_POPUP) and (It.Value = POP_COLOR) then
      Dec(Room, Round(24 * FUIScale));
    if (It.Group = GRP_TOOL) then
      Dec(Room, Round(18 * FUIScale));
    It.Caption := FitCaption(pbDeck.Canvas, It.Caption, Room);
    TW := pbDeck.Canvas.TextWidth(It.Caption);
    { a tool shows its glyph, the same one that follows the cursor }
    if (It.Group = GRP_POPUP) and (It.Value = POP_COLOR) then
      pbDeck.Canvas.TextOut(
        It.Bounds.Left + (It.Bounds.Right - It.Bounds.Left - TW +
          Round(24 * FUIScale)) div 2,
        (It.Bounds.Top + It.Bounds.Bottom - pbDeck.Canvas.TextHeight(It.Caption)) div 2,
        It.Caption)
    else if (It.Group = GRP_TOOL) then
      pbDeck.Canvas.TextOut(
        It.Bounds.Left + (It.Bounds.Right - It.Bounds.Left - TW +
          Round(18 * FUIScale)) div 2,
        (It.Bounds.Top + It.Bounds.Bottom - pbDeck.Canvas.TextHeight(It.Caption)) div 2,
        It.Caption)
    else
      pbDeck.Canvas.TextOut(
        (It.Bounds.Left + It.Bounds.Right - TW) div 2,
        (It.Bounds.Top + It.Bounds.Bottom - pbDeck.Canvas.TextHeight(It.Caption)) div 2,
        It.Caption);
  end;
end;

procedure TMainForm.pbDeckMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  H: Integer;
begin
  H := DeckHit(X, Y);
  if H <> FHotItem then
  begin
    FHotItem := H;
    { a real tooltip too, since the icons say nothing about themselves }
    if H >= 0 then pbDeck.Hint := FDeck[H].Hint else pbDeck.Hint := '';
    Application.CancelHint;
    pbDeck.Invalidate;
    Invalidate;
  end;
end;

procedure TMainForm.pbDeckMouseLeave(Sender: TObject);
begin
  if FHotItem <> -1 then
  begin
    FHotItem := -1;
    pbDeck.Hint := '';
    Application.CancelHint;
    pbDeck.Invalidate;
    Invalidate;
  end;
end;

procedure TMainForm.pbDeckMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  H: Integer;
begin
  if Button <> mbLeft then Exit;
  H := DeckHit(X, Y);
  if H >= 0 then DeckActivate(H);
end;

procedure TMainForm.DeckActivate(Index: Integer);
var
  It: TDeckItem;
begin
  if (Index < 0) or (Index > High(FDeck)) then Exit;
  It := FDeck[Index];
  case It.Group of
    GRP_TOOL:
      if TTool(It.Value) = FTool then
        SetTool(ptSelect)          // clicking the lit tool puts it away
      else
        SetTool(TTool(It.Value));
    GRP_POPUP:
      { clicking the open one shuts it, as a menu button does }
      if FPopup = It.Value then ClosePopup else OpenPopup(It.Value);
    GRP_SCALE: SetScaleIdx(It.Value);
    GRP_SNAP:  begin
                 FD.SnapIdx := It.Value;
                 Act('snap ' + IntToStr(It.Value));
                 pbDeck.Invalidate;
                 pbCmd.Invalidate;
               end;
    GRP_ICON: DoAction(It.Value);
  end;
end;

{ One action, whichever button asked for it: the deck and the quick strip
  share this so Save means the same everywhere. }
procedure TMainForm.DoAction(A: Integer);
begin
  case A of
    ACT_UNDO:   DoUndo;
    ACT_REDO:   DoRedo;
    ACT_SAVE:   DoSave;
    ACT_PRINT:  DoPrint;
    ACT_THEME:  CycleTheme(1);
    ACT_GRID:   begin
                  FShowGrid := not FShowGrid;
                  RepaintPaper;
                  RecomposeAll;
                  pbDeck.Invalidate;
                end;
    ACT_HELP:   if FPopup = POP_HELP then ClosePopup else OpenPopup(POP_HELP);
    ACT_UNITS:  SetUnits(TUnitSystem(1 - Ord(FD.Units)));
    ACT_ORIGIN: SetOriginHere;
    ACT_FIT:    FitView;
    ACT_OPEN:   DoOpen;
    ACT_MENU:   ShowFileMenu;
    ACT_EXPORT: DoExport;
    ACT_GUIDES:
      begin
        FD.Doc.GuidesHidden := not FD.Doc.GuidesHidden;
        FCmdMsg := IfThen(FD.Doc.GuidesHidden,
          'Guides put away.  They are still in the drawing.',
          'Guides back.');
        RenderInk;
        RecomposeAll;
      end;
    ACT_NOGUIDE:
      begin
        PushUndo;
        FCmdMsg := Format('Cleared %d guides.', [FD.Doc.ClearGuides]);
        RenderInk;
        RecomposeAll;
      end;
  end;
end;

{ Park on a named camera.  Free orbiting sets FViewPreset to -1, so the next
  press starts again at the corner view. }
procedure TMainForm.ApplyViewPreset(I: Integer);
var
  N: Integer;
  Turn: Boolean;
  FitZ, FitX, FitY: Double;
begin
  N := Length(VIEW_PRESETS);
  Turn := (FD <> nil) and (FD.View = vkOrbit) and
          (VIEW_PRESETS[((I mod N) + N) mod N].View = vkOrbit) and FBooted;
  FViewPreset := ((I mod N) + N) mod N;
  FD.View := VIEW_PRESETS[FViewPreset].View;
  { One 3D view to another glides; a change of view kind (into or out of
    the paper modes) snaps, since one projection cannot turn into another. }
  if Turn then
  begin
    { a preset reframes, so the glide aims at the final framing instead of
      popping into it on arrival }
    if FitTarget(Length(FSel) > 0, VIEW_PRESETS[FViewPreset].Az,
         VIEW_PRESETS[FViewPreset].El, FitZ, FitX, FitY) then
      GlideCamera(VIEW_PRESETS[FViewPreset].Az, VIEW_PRESETS[FViewPreset].El,
        FitZ, FitX, FitY)
    else
      GlideTo(VIEW_PRESETS[FViewPreset].Az, VIEW_PRESETS[FViewPreset].El);
  end
  else
  begin
    FD.Az := VIEW_PRESETS[FViewPreset].Az;
    FD.El := VIEW_PRESETS[FViewPreset].El;
  end;
  if FD.View <> vkOrbit then FD.Plane := plXY;
  { this can reach PLAN, so the cut strip must come and go and the top row
    be laid out again }
  ApplySlice;
  Relayout;
  FCmdMsg := VIEW_PRESETS[FViewPreset].Name + ' view.';
  if FD.View = vkPlan then
    FCmdMsg := FCmdMsg + '  CUT, top right, slices it - Ctrl+wheel travels ' +
      'up and down.';
  { the glide carries the framing; a change of view kind still snaps to fit }
  if FGlideT = 0 then FitView(False);
  RebuildDeck;
  pbDeck.Invalidate;
  pbView.Invalidate;
  pbSlice.Invalidate;
  pbCmd.Invalidate;
end;

procedure TMainForm.CycleViewPreset(Step: Integer);
var
  N, I: Integer;
begin
  { Off the presets (a paper mode or orbited free), either direction goes to
    the first corner; on them, step round the camera presets. }
  N := High(VIEW_PRESETS) - FIRST_CAMERA_PRESET + 1;
  if (FViewPreset < FIRST_CAMERA_PRESET) or (FD.View <> vkOrbit) then
    I := FIRST_CAMERA_PRESET
  else
    I := FIRST_CAMERA_PRESET + (((FViewPreset - FIRST_CAMERA_PRESET + Step) mod N) + N) mod N;
  ApplyViewPreset(I);
end;

{ Push the sheet's slice into the document, or take it away.  A slice only
  applies in PLAN; in 3D it would hide half the model for no visible reason.
  The document uses the same range for drawing and picking.  Called wherever
  the answer could change, so the sheet and document never disagree (that
  makes geometry invisible but still snappable). }
procedure TMainForm.ApplySlice;
begin
  if FD = nil then Exit;
  FD.Doc.SetSlice(FD.SliceOn and (FD.View = vkPlan), FD.SliceLo, FD.SliceHi);
end;

procedure TMainForm.SetSlice(AOn: Boolean; ALo, AHi: Double; const Why: string);
var
  T: Double;
  N: Integer;
begin
  if AHi < ALo then begin T := ALo; ALo := AHi; AHi := T; end;
  FD.SliceOn := AOn;
  FD.SliceLo := ALo;
  FD.SliceHi := AHi;
  ApplySlice;
  RenderInk;
  RecomposeAll;
  if Assigned(pbSlice) then pbSlice.Invalidate;
  Invalidate;
  if Why <> '' then FCmdMsg := Why
  else if not AOn then FCmdMsg := 'Cut off - the whole model is in the drawing.'
  else
  begin
    N := FD.Doc.OutsideSlice;
    { say what is kept out, so a drawing that vanished is explained }
    if N = 0 then
      FCmdMsg := Format('Cut %s to %s - everything is in it.',
        [FormatLen(ALo, FD.Units), FormatLen(AHi, FD.Units)])
    else
      FCmdMsg := Format('Cut %s to %s - %d thing%s outside it.',
        [FormatLen(ALo, FD.Units), FormatLen(AHi, FD.Units), N,
         IfThen(N = 1, '', 's')]);
  end;
  InvalidateStatus;
  pbCmd.Invalidate;
end;

{ Move the slice by whole snap steps.  Which: 0 slides both ends, 1 the
  bottom alone, 2 the top. }
procedure TMainForm.NudgeSlice(Steps: Integer; Which: Integer);
var
  D, Lo, Hi: Double;
begin
  if Steps = 0 then Exit;
  { steps by the snap, so there is no second setting to find }
  D := SnapStep;
  if D <= 0 then D := 1 / 12;
  D := D * Steps;
  Lo := FD.SliceLo;
  Hi := FD.SliceHi;
  case Which of
    1: Lo := Lo + D;
    2: Hi := Hi + D;
  else
    begin Lo := Lo + D; Hi := Hi + D; end;
  end;
  { the bottom cannot pass the top, or the slice turns inside out under the
    wheel }
  if Which = 1 then Lo := Min(Lo, Hi);
  if Which = 2 then Hi := Max(Hi, Lo);
  SetSlice(True, Lo, Hi);
end;

{ "Plan from here": the clicked floor becomes the bottom of the slice and the
  top goes one story above it. }
procedure TMainForm.PlanFromFace(Face: Integer);
var
  Lo, Hi: Double;
  K: Integer;
  Poly: TP3Array;
begin
  if (Face < 0) or (Face >= FD.Doc.Live) then Exit;
  Poly := FD.Doc[Face].Poly;
  if Length(Poly) = 0 then Exit;
  Lo := Poly[0].Z;
  for K := 1 to High(Poly) do Lo := Min(Lo, Poly[K].Z);
  { One story (8' or 2.5 m), not the 4' a real cut plane uses: this is also
    the drawing plane and you want to see the whole floor. }
  if FD.Units = usImperial then Hi := Lo + 8 else Hi := Lo + 2.5;
  if FD.View <> vkPlan then SetView(vkPlan);
  SetSlice(True, Lo, Hi,
    Format('Plan from %s, up to %s.  Ctrl+wheel travels up and down.',
      [FormatLen(Lo, FD.Units), FormatLen(Hi, FD.Units)]));
end;

function TMainForm.SliceText: string;
begin
  if not FD.SliceOn then Result := 'CUT  off'
  else Result := Format('CUT  %s - %s',
    [FormatLen(FD.SliceLo, FD.Units), FormatLen(FD.SliceHi, FD.Units)]);
end;

procedure TMainForm.SetView(V: TViewKind);
begin
  FViewPreset := -1;
  if V = FD.View then Exit;
  Trail('view ' + VIEW_NAMES[V]);
  Act('view ' + VIEW_NAMES[V]);
  FD.View := V;
  if V <> vkOrbit then FD.Plane := plXY;
  { the slice is plan only, so entering or leaving plan turns it on or off }
  ApplySlice;
  { the cut strip comes and goes with the view, so lay out the top row again }
  Relayout;
  { the projection changed, so there is nothing to glide between }
  FitView(False);
  RebuildDeck;
  pbDeck.Invalidate;
  pbView.Invalidate;
  pbSlice.Invalidate;
  case V of
    vkPlan: FCmdMsg := 'Plan view.';
    vkIso: FCmdMsg := 'Isometric view.';
  else
    FCmdMsg := '3D view - middle-drag to orbit.';
  end;
  pbCmd.Invalidate;
end;

{ The view button.  There is one drawing and one camera; the button offers
  where to park it (corners, top, sides) and shows the name of the view it is
  on, or 3D once orbited off it.  The paper modes are reached from the Create
  menu. }
procedure TMainForm.pbViewPaint(Sender: TObject);
var
  W, H: Integer;
  R: TRect;
  S: string;
begin
  W := pbView.Width;
  H := pbView.Height;
  FViewSkin.SetSize(W, H);
  FViewSkin.Clear(Pix(0, 0, 0));
  FViewSkin.CopyRegion(FShell, pbView.Left, pbView.Top, 0, 0, W, H);
  FViewSkin.RoundRectV(Rect(0, 0, W, H), H / 2,
    MixPix(Theme.Panel, Pix(0, 0, 0), 0.20), MixPix(Theme.Panel, Pix(0, 0, 0), 0.42));
  FViewSkin.RoundFrame(Rect(0, 0, W, H), H / 2, 1.0,
    MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.14));
  { the name on the left, the arrow on the right; each lights on hover }
  if FHotView = 0 then
    FViewSkin.RoundRect(Rect(3, 3, W - VIEW_ARROW_W, H - 3), (H - 6) / 2,
      MixPix(Theme.Panel, Pix(255, 255, 255), 0.10))
  else if FHotView = 1 then
    FViewSkin.RoundRect(Rect(W - VIEW_ARROW_W, 3, W - 3, H - 3), (H - 6) / 2,
      MixPix(Theme.Panel, Pix(255, 255, 255), 0.10));
  FViewSkin.Line(W - VIEW_ARROW_W, 6, W - VIEW_ARROW_W, H - 6, 1,
    MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.14), 1.0);
  FViewSkin.DrawTo(pbView.Canvas, 0, 0);

  S := ViewButtonName;
  UIFont(pbView.Canvas, 10, True, Theme.Text);
  pbView.Canvas.TextOut(((W - VIEW_ARROW_W) - pbView.Canvas.TextWidth(S)) div 2,
    (H - pbView.Canvas.TextHeight(S)) div 2, S);
  { the arrow: a small filled triangle }
  pbView.Canvas.Brush.Style := bsSolid;
  pbView.Canvas.Brush.Color := PixToColor(Theme.Text);
  pbView.Canvas.Pen.Color := PixToColor(Theme.Text);
  pbView.Canvas.Polygon([Point(W - VIEW_ARROW_W div 2 - 5, H div 2 - 3),
                         Point(W - VIEW_ARROW_W div 2 + 5, H div 2 - 3),
                         Point(W - VIEW_ARROW_W div 2, H div 2 + 3)]);
  pbView.Canvas.Brush.Style := bsClear;
end;

{ ---------------------------------------------------------------------- }
{ the file buttons, top left                                               }
{ ---------------------------------------------------------------------- }

{ File menu, undo and redo at the top left, where every program keeps them.
  Hover notes are drawn beside what is hovered (see PaintChromeTip). }
const
  { MENU is the file menu: new, open, recent, save, save as, export, print,
    close }
  QUICK_ACTS: array[0..2] of Integer =
    (ACT_MENU, ACT_UNDO, ACT_REDO);
  QUICK_ICONS: array[0..2] of TIconKind =
    (ikOpen, ikUndo, ikRedo);
  QUICK_TIPS: array[0..2] of string = (
    'New, open, open recent, save, save as, export, print, close - the file.  Ctrl+O opens, Ctrl+S saves, ' +
      'Ctrl+E exports, Ctrl+P prints',
    'Undo.  Ctrl+Z',
    'Redo.  Ctrl+Y');
  { a gap before undo and redo: they act on the drawing, the menu on the file }
  QUICK_GAP_BEFORE = 1;
  QUICK_NAMES: array[0..2] of string =
    ('MENU', 'UNDO', 'REDO');

function TMainForm.QuickWidth: Integer;
begin
  Result := Length(QUICK_ACTS) * Round(74 * FUIScale) +
            Round(12 * FUIScale);
end;

procedure TMainForm.RebuildQuick;
var
  I, BW, X, H: Integer;
begin
  SetLength(FQuick, 0);
  BW := Round(74 * FUIScale);
  H := pbQuick.Height;
  X := 0;
  for I := 0 to High(QUICK_ACTS) do
  begin
    if I = QUICK_GAP_BEFORE then Inc(X, Round(12 * FUIScale));
    SetLength(FQuick, Length(FQuick) + 1);
    with FQuick[High(FQuick)] do
    begin
      Kind := dkSegment;
      Bounds := Rect(X + 1, 1, X + BW - 1, H - 1);
      Group := GRP_ICON;
      Value := QUICK_ACTS[I];
      Caption := QUICK_NAMES[I];
      Hint := QUICK_TIPS[I];
      Icon := QUICK_ICONS[I];
    end;
    Inc(X, BW);
  end;
end;

function TMainForm.QuickHit(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FQuick) do
    if PtInRect(FQuick[I].Bounds, Point(X, Y)) then Exit(I);
  Result := -1;
end;

procedure TMainForm.pbQuickPaint(Sender: TObject);
var
  I, W, H, IconSz: Integer;
  R, IR: TRect;
  Fg: TPix;
  Ena: Boolean;
begin
  W := pbQuick.Width;
  H := pbQuick.Height;
  if (W < 8) or (H < 8) then Exit;
  FQuickSkin.SetSize(W, H);
  FQuickSkin.Clear(Pix(0, 0, 0));
  FQuickSkin.CopyRegion(FShell, pbQuick.Left, pbQuick.Top, 0, 0, W, H);

  IconSz := Round(15 * FUIScale);
  for I := 0 to High(FQuick) do
  begin
    R := FQuick[I].Bounds;
    { grayed when it would do nothing, so the row shows the drawing's state }
    Ena := True;
    if FQuick[I].Value = ACT_UNDO then Ena := FD.UndoTop > 0
    else if FQuick[I].Value = ACT_REDO then Ena := FD.RedoTop > 0;
    if I = FHotQuick then
    begin
      FQuickSkin.RoundRect(R, Round(4 * FUIScale),
        MixPix(Theme.Panel, Pix(255, 255, 255), 0.16));
      FQuickSkin.RoundFrame(R, Round(4 * FUIScale), 1.0,
        MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.16));
    end;
    { grayed but still readable on the pale theme }
    if Ena then Fg := Theme.Text
    else Fg := MixPix(Theme.TextDim, Theme.Shell1, 0.30);
    IR := Rect(R.Left + Round(6 * FUIScale),
               (R.Top + R.Bottom - IconSz) div 2,
               R.Left + Round(6 * FUIScale) + IconSz,
               (R.Top + R.Bottom + IconSz) div 2);
    PaintIcon(FQuickSkin, FQuick[I].Icon, IR, Fg);
  end;
  FQuickSkin.DrawTo(pbQuick.Canvas, 0, 0);

  { the word beside the picture; a floppy disk icon means nothing to many }
  for I := 0 to High(FQuick) do
  begin
    R := FQuick[I].Bounds;
    Ena := True;
    if FQuick[I].Value = ACT_UNDO then Ena := FD.UndoTop > 0
    else if FQuick[I].Value = ACT_REDO then Ena := FD.RedoTop > 0;
    if Ena then UIFont(pbQuick.Canvas, 10, True, Theme.Text)
    else UIFont(pbQuick.Canvas, 10, True,
                MixPix(Theme.TextDim, Theme.Shell1, 0.30));
    pbQuick.Canvas.TextOut(R.Left + Round(8 * FUIScale) + IconSz,
      (R.Top + R.Bottom - pbQuick.Canvas.TextHeight('X')) div 2,
      FQuick[I].Caption);
  end;
end;

procedure TMainForm.pbQuickMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  H: Integer;
begin
  H := QuickHit(X, Y);
  if H <> FHotQuick then
  begin
    FHotQuick := H;
    pbQuick.Invalidate;
  end;
  if (H >= 0) and (H <= High(FQuick)) then
  begin
    FChromeTip := QUICK_NAMES[H];
    FChromeTipBody := FQuick[H].Hint;
    FChromeTipX := EnsureRange(pbQuick.Left + FQuick[H].Bounds.Left -
                     pbScreen.Left, 4, Max(4, pbScreen.Width - 40));
    FChromeTipY := Round(24 * FUIScale);
  end
  else
  begin
    FChromeTip := '';
    FChromeTipBody := '';
  end;
  pbScreen.Invalidate;
end;

procedure TMainForm.pbQuickMouseLeave(Sender: TObject);
begin
  if FHotQuick <> -1 then
  begin
    FHotQuick := -1;
    pbQuick.Invalidate;
  end;
  FChromeTip := '';
  FChromeTipBody := '';
  pbScreen.Invalidate;
end;

procedure TMainForm.pbQuickMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  H: Integer;
begin
  if Button <> mbLeft then Exit;
  H := QuickHit(X, Y);
  if (H < 0) or (H > High(FQuick)) then Exit;
  DoAction(FQuick[H].Value);
  pbQuick.Invalidate;
end;

{ ---------------------------------------------------------------------- }
{ the tool strip down the left                                             }
{ ---------------------------------------------------------------------- }

{ Tools stand in a column on the left with their names beside them.  Screens
  are wide and short, so a column costs the plentiful dimension.  Left, as in
  every drawing program; not floating or dockable, so it cannot get lost.
  Names are on by default on purpose: nobody can tell Offset from Drill by
  pictogram.  The arrow at the bottom collapses it, and that is remembered. }
function TMainForm.ToolStripWidth: Integer;
begin
  if FToolsWide then Result := Round(126 * FUIScale)
  else Result := Round(42 * FUIScale);
end;

procedure TMainForm.RebuildTools;
var
  I, K, RowH, Gap, Y, W, Brk, BrkH, Need: Integer;

  procedure Add(AKind: TDeckKind; const R: TRect; AGroup, AValue: Integer;
    const ACap, AHint: string; AIcon: TIconKind);
  begin
    SetLength(FTools, Length(FTools) + 1);
    with FTools[High(FTools)] do
    begin
      Kind := AKind; Bounds := R; Group := AGroup; Value := AValue;
      Caption := ACap; Hint := AHint; Icon := AIcon;
    end;
  end;

begin
  SetLength(FTools, 0);
  W := pbTools.Width;
  if W < 8 then Exit;
  { the shop sits at the very foot; worked out first so the tools stop above
    it }
  FShopTop := pbTools.Height - Round(56 * FUIScale);

  { Rows at full height unless the window is too short, then tighter down to
    a floor, so the list never runs under MORE and SHOP.  Everything scales
    together so it still reads as one list. }
  Brk := 0;
  for I := 0 to High(MAIN_TOOLS) do
    for K := 0 to High(MAIN_BREAKS) do
      if MAIN_BREAKS[K] = I + 1 then Inc(Brk);
  RowH := Round(26 * FUIScale);
  Gap := Round(3 * FUIScale);
  BrkH := Round(8 * FUIScale);
  while RowH > Round(17 * FUIScale) do
  begin
    Need := Round(6 * FUIScale) + Length(MAIN_TOOLS) * (RowH + Gap) +
      Brk * BrkH + Round(4 * FUIScale) + RowH + Round(4 * FUIScale);
    if Need <= FShopTop then Break;
    Dec(RowH);
    if Gap > 1 then Dec(Gap);
    if BrkH > Round(4 * FUIScale) then Dec(BrkH);
  end;
  Y := Round(6 * FUIScale);

  SetLength(FToolRules, 0);
  for I := 0 to High(MAIN_TOOLS) do
  begin
    Add(dkSegment, Rect(Round(4 * FUIScale), Y, W - Round(4 * FUIScale), Y + RowH),
      GRP_TOOL, Ord(MAIN_TOOLS[I]), TOOL_NAMES[MAIN_TOOLS[I]],
      TOOL_HINTS[MAIN_TOOLS[I]], TOOL_ICONS[MAIN_TOOLS[I]]);
    Inc(Y, RowH + Gap);
    for K := 0 to High(MAIN_BREAKS) do
      if MAIN_BREAKS[K] = I + 1 then
      begin
        SetLength(FToolRules, Length(FToolRules) + 1);
        FToolRules[High(FToolRules)] := Y + BrkH div 2 - Round(1 * FUIScale);
        Inc(Y, BrkH);
        Break;
      end;
  end;

  { MORE comes right after the tools and looks like one }
  Inc(Y, Round(4 * FUIScale));
  Add(dkSegment, Rect(Round(4 * FUIScale), Y, W - Round(4 * FUIScale), Y + RowH),
    GRP_POPUP, POP_MORE, 'MORE TOOLS',
    'Rotate, offset and drill.', ikChevron);

  { The shop at the very foot, apart, with a spanner: it is a door into the
    trade wizards, not a drawing tool, and should not look like half of MORE. }
  Add(dkSegment, Rect(Round(4 * FUIScale), FShopTop,
    W - Round(4 * FUIScale), FShopTop + Round(26 * FUIScale)),
    GRP_POPUP, POP_SHOP, 'SHOP',
    'Sheet metal and pipe: laying a piece out flat, duct fittings, spools.',
    ikShop);
end;

function TMainForm.ToolsHit(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FTools) do
    if PtInRect(FTools[I].Bounds, Point(X, Y)) then Exit(I);
  { the bottom strip is the collapse arrow }
  if Y > pbTools.Height - Round(26 * FUIScale) then Exit(-2);
  Result := -1;
end;

{ The groups panel, SketchUp's Outliner: every group as a tree, to pick,
  put away and bring back.  The stairs, radiant layouts and jigs all make
  groups, so this is how to find them.  Painted by hand like the entity
  panel, from rows rebuilt each paint by scanning the ekPart records; a list
  kept up to date from many places would go stale. }
function TMainForm.GroupsPanelOn: Boolean;
begin
  Result := FGroupsOn;
end;

procedure TMainForm.SetGroupsPanel(On_: Boolean);
begin
  FGroupsOn := On_;
  FGrpSig := -1;
  FGrpHot := -1;
  FGrpHotId := 0;
  Relayout;
  if FGroupsOn then
    FCmdMsg := 'The groups are listed on the right.  Click one to pick it, ' +
      'double-click to work inside it, untick to put it away.'
  else
    FCmdMsg := 'Groups panel off.  /groups brings it back.';
  InvalidateStatus;
  Invalidate;
end;

procedure TMainForm.GroupsChanged;
begin
  if pbGroups.Visible then pbGroups.Invalidate;
end;

procedure TMainForm.RebuildGroupRows;
var
  Ids, Par: array of Integer;
  I, N: Integer;

  function Folded(Id: Integer): Boolean;
  var
    K: Integer;
  begin
    Result := False;
    for K := 0 to High(FGrpFold) do
      if FGrpFold[K] = Id then Exit(True);
  end;

  procedure Add(Id, Depth: Integer; Kids: Boolean);
  begin
    SetLength(FGrpRows, Length(FGrpRows) + 1);
    FGrpRows[High(FGrpRows)].Id := Id;
    FGrpRows[High(FGrpRows)].Depth := Depth;
    FGrpRows[High(FGrpRows)].Kids := Kids;
    FGrpRows[High(FGrpRows)].Fold := Rect(0, 0, 0, 0);
    FGrpRows[High(FGrpRows)].Tick := Rect(0, 0, 0, 0);
  end;

  procedure Walk(Parent, Depth: Integer);
  var
    K, J: Integer;
    Kids: Boolean;
  begin
    { a hand-edited file could loop a group into itself; nobody nests 40 deep }
    if Depth > 40 then Exit;
    for K := 0 to N - 1 do
      if Par[K] = Parent then
      begin
        Kids := False;
        for J := 0 to N - 1 do
          if Par[J] = Ids[K] then begin Kids := True; Break; end;
        Add(Ids[K], Depth, Kids);
        if Kids and not Folded(Ids[K]) then Walk(Ids[K], Depth + 1);
      end;
  end;

begin
  FGrpRows := nil;
  Ids := nil;
  Par := nil;
  N := 0;
  for I := 0 to FD.Doc.Live - 1 do
    if FD.Doc[I].Kind = ekPart then
    begin
      SetLength(Ids, N + 1);
      SetLength(Par, N + 1);
      Ids[N] := FD.Doc[I].Grp;
      Par[N] := FD.Doc[I].Part;
      Inc(N);
    end;
  { a group whose parent is gone goes at the top level }
  for I := 0 to N - 1 do
    if (Par[I] <> 0) and (FD.Doc.PartEnt(Par[I]) < 0) then Par[I] := 0;
  Add(0, 0, N > 0);
  Walk(0, 1);
end;

function TMainForm.GroupRowAt(Y: Integer): Integer;
var
  Top_, RowH: Integer;
begin
  Result := -1;
  RowH := Round(20 * FUIScale);
  Top_ := Round(10 * FUIScale) + RowH + Round(4 * FUIScale);
  if Y < Top_ then Exit;
  Result := FGrpScroll + (Y - Top_) div RowH;
  if Result > High(FGrpRows) then Result := -1;
end;

{ put away, itself or by a group it is in }
function TMainForm.GroupPutAway(Id: Integer): Boolean;
var
  Guard: Integer;
begin
  Result := False;
  Guard := 0;
  while (Id > 0) and (Guard < 1000) do
  begin
    if FD.Doc.PartHidden(Id) then Exit(True);
    Id := FD.Doc.PartParent(Id);
    Inc(Guard);
  end;
end;

procedure TMainForm.pbGroupsPaint(Sender: TObject);
var
  I, W, H, Y, X, RowH, Pad, Ind, Box, Shown, Top_, TW: Integer;
  C: TCanvas;
  S, Tag_: string;
  Picked: TIntArrayW;
  Sel, Away: Boolean;
  Tri: array[0..2] of TPoint;
  K: Integer;
begin
  W := pbGroups.Width;
  H := pbGroups.Height;
  if (W < 8) or (H < 8) then Exit;
  RebuildGroupRows;
  FGrpSkin.SetSize(W, H);
  PaintPanel(FGrpSkin, Rect(0, 0, W, H), Theme, FUIScale);
  FGrpSkin.DrawTo(pbGroups.Canvas, 0, 0);
  C := pbGroups.Canvas;
  Pad := Round(10 * FUIScale);
  RowH := Round(20 * FUIScale);
  Ind := Round(13 * FUIScale);
  Box := Round(11 * FUIScale);

  UIFont(C, 8, True, Theme.Accent);
  C.TextOut(Pad, Pad, 'GROUPS');
  UIFont(C, 8, False, Theme.TextDim);
  { count every group, folded or not }
  K := 0;
  for I := 0 to FD.Doc.Live - 1 do
    if FD.Doc[I].Kind = ekPart then Inc(K);
  S := IntToStr(K);
  C.TextOut(W - Pad - C.TextWidth(S), Pad, S);
  Top_ := Pad + RowH + Round(4 * FUIScale);
  C.Pen.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.14));
  C.Pen.Width := 1;
  C.MoveTo(Pad, Top_ - Round(3 * FUIScale));
  C.LineTo(W - Pad, Top_ - Round(3 * FUIScale));

  Shown := Max(1, (H - Top_ - Pad div 2) div RowH);
  FGrpScroll := EnsureRange(FGrpScroll, 0, Max(0, Length(FGrpRows) - Shown));
  Picked := SelectedGroups;

  Y := Top_;
  for I := FGrpScroll to High(FGrpRows) do
  begin
    if Y + RowH > H - Pad div 2 then Break;
    Sel := False;
    for K := 0 to High(Picked) do
      if Picked[K] = FGrpRows[I].Id then Sel := True;
    Away := (FGrpRows[I].Id > 0) and GroupPutAway(FGrpRows[I].Id);

    if Sel or (I = FGrpHot) then
    begin
      C.Brush.Style := bsSolid;
      if Sel then C.Brush.Color := PixToColor(MixPix(Theme.PanelHi, Theme.Accent, 0.35))
      else C.Brush.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.08));
      C.Pen.Style := psClear;
      C.Rectangle(Pad div 2, Y, W - Pad div 2, Y + RowH);
      C.Pen.Style := psSolid;
      C.Brush.Style := bsClear;
    end;

    X := Pad + Max(0, FGrpRows[I].Depth - 1) * Ind;
    { the fold: a small triangle, pointing down when open }
    FGrpRows[I].Fold := Rect(0, 0, 0, 0);
    if (FGrpRows[I].Id > 0) and FGrpRows[I].Kids then
    begin
      FGrpRows[I].Fold := Rect(X - 2, Y, X + Ind, Y + RowH);
      C.Brush.Style := bsSolid;
      C.Brush.Color := PixToColor(Theme.TextDim);
      C.Pen.Color := PixToColor(Theme.TextDim);
      K := Round(4 * FUIScale);
      if (FGrpRows[I + Ord(I < High(FGrpRows))].Depth > FGrpRows[I].Depth) and
         (I < High(FGrpRows)) then
      begin
        Tri[0] := Point(X, Y + RowH div 2 - K div 2);
        Tri[1] := Point(X + 2 * K, Y + RowH div 2 - K div 2);
        Tri[2] := Point(X + K, Y + RowH div 2 + K);
      end
      else
      begin
        Tri[0] := Point(X + K div 2, Y + RowH div 2 - K);
        Tri[1] := Point(X + K div 2, Y + RowH div 2 + K);
        Tri[2] := Point(X + K div 2 + K + 1, Y + RowH div 2);
      end;
      C.Polygon(Tri);
      C.Brush.Style := bsClear;
    end;
    if FGrpRows[I].Id > 0 then Inc(X, Ind);

    { the box: ticked is on the sheet, unticked is put away }
    FGrpRows[I].Tick := Rect(0, 0, 0, 0);
    if FGrpRows[I].Id > 0 then
    begin
      FGrpRows[I].Tick := Rect(X, Y + (RowH - Box) div 2, X + Box, Y + (RowH - Box) div 2 + Box);
      C.Brush.Style := bsSolid;
      C.Brush.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.10));
      C.Pen.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.40));
      C.Pen.Width := 1;
      C.Rectangle(FGrpRows[I].Tick);
      C.Brush.Style := bsClear;
      if not FD.Doc.PartHidden(FGrpRows[I].Id) then
      begin
        C.Pen.Color := PixToColor(Theme.Accent);
        C.Pen.Width := Max(2, Round(2 * FUIScale));
        with FGrpRows[I].Tick do
        begin
          C.MoveTo(Left + 2, Top + Box div 2);
          C.LineTo(Left + Box * 2 div 5, Bottom - 3);
          C.LineTo(Right - 2, Top + 2);
        end;
        C.Pen.Width := 1;
      end;
      Inc(X, Box + Round(6 * FUIScale));
    end;

    { the name, and a tag if it is open or locked }
    if FGrpRows[I].Id = 0 then
    begin
      S := 'The whole sheet';
      if FD.Doc.Context = 0 then UIFont(C, 9, True, Theme.Text)
      else UIFont(C, 9, False, Theme.TextDim);
    end
    else
    begin
      S := FD.Doc.PartName(FGrpRows[I].Id);
      if FD.Doc.Context = FGrpRows[I].Id then UIFont(C, 9, True, Theme.Accent)
      else if Away then UIFont(C, 9, False, Theme.TextDim)
      else UIFont(C, 9, False, Theme.Text);
    end;
    Tag_ := '';
    if FGrpRows[I].Id > 0 then
    begin
      if FD.Doc.Context = FGrpRows[I].Id then Tag_ := 'open'
      else if FD.Doc.PartLocked(FGrpRows[I].Id) then Tag_ := 'locked';
    end;
    TW := 0;
    if Tag_ <> '' then
    begin
      UIFont(C, 8, False, Theme.TextDim);
      TW := C.TextWidth(Tag_) + Round(6 * FUIScale);
      C.TextOut(W - Pad - C.TextWidth(Tag_), Y + (RowH - C.TextHeight('X')) div 2, Tag_);
      if FGrpRows[I].Id = FD.Doc.Context then UIFont(C, 9, True, Theme.Accent)
      else if Away then UIFont(C, 9, False, Theme.TextDim)
      else UIFont(C, 9, False, Theme.Text);
    end;
    S := CutToFit(C, S, W - Pad - TW - X);
    C.TextOut(X, Y + (RowH - C.TextHeight('X')) div 2, S);
    Inc(Y, RowH);
  end;

  if Length(FGrpRows) <= 1 then
  begin
    UIFont(C, 8, False, Theme.TextDim);
    C.TextOut(Pad, Y + Round(6 * FUIScale), 'No groups on this sheet.');
    C.TextOut(Pad, Y + Round(6 * FUIScale) + RowH, 'Pick things, then /group -');
    C.TextOut(Pad, Y + Round(6 * FUIScale) + 2 * RowH, 'the stairs and radiant make');
    C.TextOut(Pad, Y + Round(6 * FUIScale) + 3 * RowH, 'their own.');
  end
  else if FGrpScroll + Shown < Length(FGrpRows) then
  begin
    UIFont(C, 8, False, Theme.TextDim);
    S := Format('%d more - scroll', [Length(FGrpRows) - FGrpScroll - Shown]);
    C.TextOut(W - Pad - C.TextWidth(S), H - Pad div 2 - C.TextHeight('X'), S);
  end;

  { a list opened from the deck may stand over this panel too }
  if FPopup <> POP_NONE then
    PaintPopup(C, pbScreen.Left - pbGroups.Left, pbScreen.Top - pbGroups.Top);
end;

procedure TMainForm.pbGroupsMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  H, Id: Integer;
begin
  if FPopup <> POP_NONE then
  begin
    H := PopupItemAt(X + pbGroups.Left - pbScreen.Left,
                     Y + pbGroups.Top - pbScreen.Top);
    if (H < 0) and (FPopup = POP_CMDS) then H := FPopupHot;
    if H <> FPopupHot then
    begin
      FPopupHot := H;
      FScreenDirty := True;
      pbScreen.Invalidate;
      pbGroups.Invalidate;
    end;
    Exit;
  end;
  H := GroupRowAt(Y);
  if H = FGrpHot then Exit;
  FGrpHot := H;
  { the hovered group shows its box in the drawing }
  if H >= 0 then Id := FGrpRows[H].Id else Id := 0;
  if Id <> FGrpHotId then
  begin
    FGrpHotId := Id;
    FScreenDirty := True;
    pbScreen.Invalidate;
  end;
  pbGroups.Invalidate;
end;

procedure TMainForm.pbGroupsMouseLeave(Sender: TObject);
begin
  if (FGrpHot < 0) and (FGrpHotId = 0) then Exit;
  FGrpHot := -1;
  FGrpHotId := 0;
  FScreenDirty := True;
  pbScreen.Invalidate;
  pbGroups.Invalidate;
end;

procedure TMainForm.pbGroupsMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  if WheelDelta > 0 then FGrpScroll := Max(0, FGrpScroll - 3)
  else FGrpScroll := FGrpScroll + 3;
  FGrpHot := -1;
  pbGroups.Invalidate;
  Handled := True;
end;

procedure TMainForm.pbGroupsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  H, Row, Id, K, Which: Integer;
  P: TPoint;

  procedure Item(const Caption: string; Tag: Integer; Enabled: Boolean);
  var
    It: TMenuItem;
  begin
    It := TMenuItem.Create(pmGroups);
    It.Caption := Caption;
    It.Tag := Tag;
    It.Enabled := Enabled;
    It.OnClick := @GroupsMenuClick;
    pmGroups.Items.Add(It);
  end;

begin
  if FPopup <> POP_NONE then
  begin
    Which := FPopup;
    H := -1;
    if Button = mbLeft then
      H := PopupItemAt(X + pbGroups.Left - pbScreen.Left,
                       Y + pbGroups.Top - pbScreen.Top);
    ClosePopup;
    if H >= 0 then PopupChoose(Which, H);
    Exit;
  end;
  Row := GroupRowAt(Y);
  if Row < 0 then Exit;
  Id := FGrpRows[Row].Id;

  if Button = mbRight then
  begin
    if Id = 0 then Exit;
    FGrpMenuId := Id;
    pmGroups.Items.Clear;
    Item('Pick It', 1, not GroupPutAway(Id));
    Item('Work Inside It', 2, not FD.Doc.PartLockedUp(Id) and not GroupPutAway(Id));
    Item('Rename...', 3, True);
    if FD.Doc.PartLocked(Id) then Item('Unlock', 4, True) else Item('Lock', 4, True);
    if FD.Doc.PartHidden(Id) then Item('Bring It Back', 5, True) else Item('Put It Away', 5, True);
    Item('-', 0, True);
    Item('Explode', 6, not FD.Doc.PartLockedUp(Id) and not GroupPutAway(Id));
    P := pbGroups.ClientToScreen(Point(X, Y));
    pmGroups.PopUp(P.X, P.Y);
    Exit;
  end;
  if Button <> mbLeft then Exit;

  if PtInRect(FGrpRows[Row].Fold, Point(X, Y)) then
  begin
    K := 0;
    while (K <= High(FGrpFold)) and (FGrpFold[K] <> Id) do Inc(K);
    if K <= High(FGrpFold) then
    begin
      FGrpFold[K] := FGrpFold[High(FGrpFold)];
      SetLength(FGrpFold, Length(FGrpFold) - 1);
    end
    else
    begin
      SetLength(FGrpFold, Length(FGrpFold) + 1);
      FGrpFold[High(FGrpFold)] := Id;
    end;
    pbGroups.Invalidate;
    Exit;
  end;
  if PtInRect(FGrpRows[Row].Tick, Point(X, Y)) then
  begin
    ShowGroupFromPanel(Id, FD.Doc.PartHidden(Id));
    Exit;
  end;
  if ssDouble in Shift then
  begin
    if Id = 0 then Exit;
    if GroupPutAway(Id) then Exit;
    OpenGroup(Id);
    pbGroups.Invalidate;
    Exit;
  end;
  PickGroupFromPanel(Id, (ssCtrl in Shift) or (ssShift in Shift));
end;

{ Pick a group from its row.  A nested group is picked as a click would pick
  it from inside its parent, so the context moves there (as SketchUp's
  Outliner does). }
procedure TMainForm.PickGroupFromPanel(Id: Integer; Add: Boolean);
var
  Up, K, First: Integer;
  M: TIntArrayW;
begin
  if Id = 0 then
  begin
    { the sheet itself: leave every group, pick nothing }
    SetLength(FSel, 0);
    if FD.Doc.Context <> 0 then
    begin
      FD.Doc.Context := 0;
      FShotOK := False;
      RenderInk;
      RecomposeAll;
    end;
    FCmdMsg := 'Working on the whole sheet.';
    InfoChanged;
    InvalidateStatus;
    FScreenDirty := True;
    pbScreen.Invalidate;
    Exit;
  end;
  if GroupPutAway(Id) then
  begin
    FCmdMsg := Format('"%s" is put away - tick its box to bring it back.', [FD.Doc.PartName(Id)]);
    InvalidateStatus;
    Exit;
  end;
  Up := FD.Doc.PartParent(Id);
  if FD.Doc.Context <> Up then
  begin
    if (Up > 0) and FD.Doc.PartLockedUp(Up) then
    begin
      FCmdMsg := Format('"%s" is inside "%s", which is locked - unlock it to reach in.',
        [FD.Doc.PartName(Id), FD.Doc.PartName(Up)]);
      InvalidateStatus;
      Exit;
    end;
    SetLength(FSel, 0);
    FD.Doc.Context := Up;
    FShotOK := False;
    RenderInk;
    RecomposeAll;
    Add := False;
  end;
  M := FD.Doc.PartMembers(Id, False);
  First := -1;
  for K := 0 to High(M) do
    if not (FD.Doc[M[K]].Kind in [ekPart, ekGuide]) then
    begin
      First := M[K];
      Break;
    end;
  if First < 0 then
  begin
    FCmdMsg := Format('"%s" has nothing in it.', [FD.Doc.PartName(Id)]);
    InvalidateStatus;
    Exit;
  end;
  if not Add then SetLength(FSel, 0);
  SelectAdd(First);
  FScreenDirty := True;
  pbScreen.Invalidate;
  InfoChanged;
  if FD.Doc.PartLocked(Id) then
    FCmdMsg := Format('"%s" picked - it is locked.', [FD.Doc.PartName(Id)])
  else
    FCmdMsg := Format('"%s" picked.  Double-click its row to work inside it.',
      [FD.Doc.PartName(Id)]);
  InvalidateStatus;
end;

{ Tick or untick: on the sheet, or put away.  Nothing is lost; a put-away
  group is just not drawn, picked or snapped to (see HideGroups). }
procedure TMainForm.ShowGroupFromPanel(Id: Integer; Shown: Boolean);
var
  C_, Guard: Integer;
begin
  if (Id <= 0) or (FD.Doc.PartHidden(Id) = not Shown) then Exit;
  PushUndo;
  FD.Doc.SetPartHidden(Id, not Shown);
  if not Shown then
  begin
    SetLength(FSel, 0);
    { working inside something just put away is working blind: step out }
    C_ := FD.Doc.Context;
    Guard := 0;
    while (C_ > 0) and (Guard < 1000) do
    begin
      if C_ = Id then
      begin
        FD.Doc.Context := FD.Doc.PartParent(Id);
        Break;
      end;
      C_ := FD.Doc.PartParent(C_);
      Inc(Guard);
    end;
  end;
  RenderInk;
  RecomposeAll;
  InfoChanged;
  if Shown then
    FCmdMsg := Format('"%s" is back.', [FD.Doc.PartName(Id)])
  else
    FCmdMsg := Format('"%s" put away - tick it to bring it back.  Ctrl+Z undoes it.',
      [FD.Doc.PartName(Id)]);
  InvalidateStatus;
  FScreenDirty := True;
  pbScreen.Invalidate;
end;

procedure TMainForm.GroupsMenuClick(Sender: TObject);
var
  Id: Integer;
begin
  Id := FGrpMenuId;
  if FD.Doc.PartEnt(Id) < 0 then Exit;
  case (Sender as TMenuItem).Tag of
    1: PickGroupFromPanel(Id, False);
    2: OpenGroup(Id);
    3:
      begin
        { renamed in the command line, prefilled, so Enter keeps it }
        PickGroupFromPanel(Id, False);
        if SoleGroup = Id then
        begin
          FInput := '/name ' + FD.Doc.PartName(Id);
          SyncCmdList;
          pbCmd.Invalidate;
          pbScreen.Invalidate;
        end;
      end;
    4:
      begin
        PushUndo;
        FD.Doc.SetPartLocked(Id, not FD.Doc.PartLocked(Id));
        FCmdMsg := Format('"%s" %s.', [FD.Doc.PartName(Id),
          IfThen(FD.Doc.PartLocked(Id), 'locked', 'unlocked')]);
        InfoChanged;
        InvalidateStatus;
        pbScreen.Invalidate;
      end;
    5: ShowGroupFromPanel(Id, FD.Doc.PartHidden(Id));
    6:
      begin
        PickGroupFromPanel(Id, False);
        if SoleGroup = Id then ExplodeGroups;
      end;
  end;
  GroupsChanged;
end;

function TMainForm.InfoPanelWidth: Integer;
begin
  if not (FInfoOn or FGroupsOn) then Exit(0);
  Result := Round(212 * FUIScale);
end;

{ What the entity panel says about the selection.  Rebuilt when the
  selection or drawing changes, into rows the painter reads and the mouse
  searches, so a stepper never drifts from its row. }
procedure TMainForm.RebuildInfo;
var
  InfoMoveB: Boolean;
  I, K, NL, NA, NF, NT, ND, NG, G: Integer;
  M: TIntArrayW;
  E: TWorkEnt;
  TotL, TotA: Double;
  Lo, Hi: TP3;
  MatCol: TColor;

  procedure Head(const S: string);
  begin
    SetLength(FInfoRows, Length(FInfoRows) + 1);
    with FInfoRows[High(FInfoRows)] do
    begin
      Caption := S; Value := ''; Act := iaNone; Ent := -1; Head := True;
      Minus := Rect(0, 0, 0, 0); Plus := Minus;
    end;
  end;

  procedure Row(const C, V: string; A: TInfoAct = iaNone; AEnt: Integer = -1);
  begin
    SetLength(FInfoRows, Length(FInfoRows) + 1);
    with FInfoRows[High(FInfoRows)] do
    begin
      Caption := C; Value := V; Act := A; Ent := AEnt; Head := False;
      Minus := Rect(0, 0, 0, 0); Plus := Minus;
    end;
  end;

  function PlaneWord(P: TPlane): string;
  begin
    case P of
      plXZ: Result := 'upright, XZ';
      plYZ: Result := 'on the side, YZ';
      plFree: Result := 'on a face';
    else
      Result := 'flat, XY';
    end;
  end;

  function Place(const P: TP3): string;
  begin
    Result := FormatLen(P.X, FD.Units) + ', ' + FormatLen(P.Y, FD.Units) +
      ', ' + FormatLen(P.Z, FD.Units);
  end;

begin
  SetLength(FInfoRows, 0);
  if (FD = nil) then Exit;

  { nothing picked: summarize the sheet }
  if Length(FSel) = 0 then
  begin
    Head('THIS SHEET');
    Row('Things', IntToStr(FD.Doc.Live));
    NL := 0; NA := 0; NF := 0; NT := 0; ND := 0; NG := 0;
    TotL := 0;
    TotA := 0;
    for I := 0 to FD.Doc.Live - 1 do
      case FD.Doc[I].Kind of
        ekLine: if FD.Doc[I].Dim then Inc(ND) else
                begin Inc(NL); TotL := TotL + Dist(FD.Doc[I].A, FD.Doc[I].B); end;
        ekArc: Inc(NA);
        ekFace: begin Inc(NF); TotA := TotA + FD.Doc.FaceArea(I); end;
        ekText: Inc(NT);
        ekDim: Inc(ND);
        ekGuide: Inc(NG);
      end;
    if NL > 0 then Row('Lines', IntToStr(NL) + '   ' + FormatLen(TotL, FD.Units));
    if NA > 0 then Row('Arcs', IntToStr(NA));
    if NF > 0 then Row('Faces', IntToStr(NF) + '   ' + FormatArea(TotA, FD.Units));
    if ND > 0 then Row('Dimensions', IntToStr(ND));
    if NT > 0 then Row('Notes', IntToStr(NT));
    if NG > 0 then Row('Guides', IntToStr(NG));
    Head('');
    Row('Pick something', 'to see and change it');
    Exit;
  end;

  { A group picked: name, contents, and actions.  Before the general count,
    since its members are all selected and would read as loose lines. }
  G := SoleGroup;
  if G > 0 then
  begin
    Head('GROUP');
    Row('Name', FD.Doc.PartName(G), iaPartRename, G);
    M := FD.Doc.PartMembers(G, False);
    Row('Holds', Format('%d thing%s', [Length(M), IfThen(Length(M) = 1, '', 's')]));
    if FD.Doc.PartParent(G) <> 0 then
      Row('Inside', FD.Doc.PartName(FD.Doc.PartParent(G)));
    { its total line length including reference lines (a radiant loop is all
      reference line, and port to port is the number wanted), and its box }
    NL := 0; TotL := 0;
    for K := 0 to High(M) do
      if FD.Doc[M[K]].Kind = ekLine then
      begin
        Inc(NL); TotL := TotL + Dist(FD.Doc[M[K]].A, FD.Doc[M[K]].B);
      end;
    if NL > 0 then Row('Lines', IntToStr(NL) + '   ' + FormatLen(TotL, FD.Units));
    if FD.Doc.PartBounds(G, Lo, Hi) then
      if Abs(Hi.Z - Lo.Z) > 1E-6 then
        Row('Size', FormatLen(Hi.X - Lo.X, FD.Units) + ' x ' + FormatLen(Hi.Y - Lo.Y, FD.Units) +
          ' x ' + FormatLen(Hi.Z - Lo.Z, FD.Units))
      else
        Row('Size', FormatLen(Hi.X - Lo.X, FD.Units) + ' x ' + FormatLen(Hi.Y - Lo.Y, FD.Units));
    Head('');
    Row('Locked', IfThen(FD.Doc.PartLocked(G), 'Unlock', 'Lock'), iaPartLock, G);
    Row('Put away', 'Hide', iaPartHide, G);
    Row('Work inside it', 'Open', iaPartOpen, G);
    Row('Take it apart', 'Explode', iaPartExplode, G);
    Exit;
  end;

  { Several picked: totals, and no steppers; a stepper acting on nine things
    at once is a way to lose nine things. }
  if Length(FSel) > 1 then
  begin
    Head(Format('%d THINGS PICKED', [Length(FSel)]));
    NL := 0; NA := 0; NF := 0; NT := 0; ND := 0; NG := 0;
    TotL := 0;
    TotA := 0;
    for K := 0 to High(FSel) do
    begin
      I := FSel[K];
      if (I < 0) or (I >= FD.Doc.Live) then Continue;
      case FD.Doc[I].Kind of
        ekLine: begin Inc(NL); TotL := TotL + Dist(FD.Doc[I].A, FD.Doc[I].B); end;
        ekArc: Inc(NA);
        ekFace: begin Inc(NF); TotA := TotA + FD.Doc.FaceArea(I); end;
        ekText: Inc(NT);
        ekDim: Inc(ND);
        ekGuide: Inc(NG);
      end;
    end;
    if NL > 0 then Row('Lines', IntToStr(NL));
    if NA > 0 then Row('Arcs', IntToStr(NA));
    if NF > 0 then Row('Faces', IntToStr(NF));
    if ND > 0 then Row('Dimensions', IntToStr(ND));
    if NT > 0 then Row('Notes', IntToStr(NT));
    if NG > 0 then Row('Guides', IntToStr(NG));
    if TotL > 0 then Row('Total length', FormatLen(TotL, FD.Units));
    if TotA > 0 then Row('Total area', FormatArea(TotA, FD.Units));
    { A color is fine for all at once: one decision, the button says how
      many it hits, and undo puts it back (SketchUp does the same). }
    if (NF > 0) or (NL + NA + NT + ND > 0) then Head('');
    if NF > 0 then
    begin
      Row('Material', Format('Paint %d face%s...',
        [NF, specialize IfThen<string>(NF = 1, '', 's')]), iaMaterial, -1);
      Row('', 'Back to default', iaUnpaint, -1);
    end;
    if NL + NA + NT + ND > 0 then
      Row('Color', Format('Change %d...', [NL + NA + NT + ND]), iaColor, -1);
    if NF > 0 then
    begin
      Head('');
      Row('Turn them over', 'Reverse', iaReverse, -1);
    end;
    Exit;
  end;

  I := FSel[0];
  if (I < 0) or (I >= FD.Doc.Live) then Exit;
  E := FD.Doc[I];

  case E.Kind of
    ekLine:
      begin
        Head(IfThen(E.Dim, 'DIMENSION', 'LINE'));
        Row('Length', FormatLen(Dist(E.A, E.B), FD.Units));
        { says in words whether the length can be typed (SketchUp grays the
          field) }
        if not E.Dim then
          if FD.Doc.LineLengthEnd(I, InfoMoveB) then
            Row('', 'type a length, Enter')
          else
            Row('', 'joined at both ends - fixed');
        Row('From', Place(E.A));
        Row('To', Place(E.B));
        Row('Width', Format('%d px', [Round(Max(1, E.Weight))]), iaWidth, I);
        Row('Color', 'Change...', iaColor, I);
        Row('Crease', IfThen(E.Soft, 'Bring back', 'Soften'), iaSoft, I);
        if E.Grp <> 0 then Row('Part of', Format('solid %d', [E.Grp]))
        else Row('Part of', 'nothing - a loose edge');
      end;
    ekArc:
      begin
        if Abs(Abs(E.Sweep) - 2 * Pi) < 1E-9 then Head('CIRCLE') else Head('ARC');
        Row('Radius', FormatLen(E.R, FD.Units));
        Row('Center', Place(E.C));
        if Abs(Abs(E.Sweep) - 2 * Pi) > 1E-9 then
          Row('Sweep', FormatAngle(RadToDeg(Abs(E.Sweep))));
        { sides can be changed after drawing }
        Row('Sides', IntToStr(ArcSteps(E)), iaSides, I);
        Row('Plane', PlaneWord(E.Plane));
        Row('Width', Format('%d px', [Round(Max(1, E.Weight))]), iaWidth, I);
        Row('Color', 'Change...', iaColor, I);
        Row('Crease', IfThen(E.Soft, 'Bring back', 'Soften'), iaSoft, I);
      end;
    ekFace:
      begin
        Head('FACE');
        Row('Area', FormatArea(FD.Doc.FaceArea(I), FD.Units));
        Row('Corners', IntToStr(Length(E.Poly)));
        if Length(E.Holes) > 0 then
          Row('Windows', IntToStr(Length(E.Holes)));
        if E.Solid then Row('Part of', Format('solid %d', [E.Grp]))
        else Row('Part of', 'nothing - a loose face');
        { faces are painted, not inked: the material row says whether it has
          the default or a chosen color }
        if FD.Doc.Material(I, MatCol) then
        begin
          Row('Material', 'Change...', iaMaterial, I);
          Row('', 'Back to default', iaUnpaint, I);
        end
        else
          Row('Material', 'Paint...', iaMaterial, I);
        Head('');
        Row('Turn it over', 'Reverse', iaReverse, I);
      end;
    ekText:
      begin
        Head('NOTE');
        Row('Says', E.Txt);
        Row('At', Place(E.A));
        Row('Size', Format('%d%%', [Round(FD.Doc.NoteSize(I) * 100)]),
          iaNoteSize, I);
        Row('Color', 'Change...', iaColor, I);
      end;
    ekDim:
      begin
        Head('DIMENSION');
        Row('Measures', FormatLen(Dist(E.A, E.B), FD.Units));
        if E.Txt <> '' then Row('Written', E.Txt);
        Row('From', Place(E.A));
        Row('To', Place(E.B));
        Row('Color', 'Change...', iaColor, I);
      end;
    ekGuide:
      begin
        if Dist(E.A, E.B) < 1E-9 then
        begin
          Head('GUIDE POINT');
          Row('At', Place(E.A));
        end
        else
        begin
          Head('GUIDE LINE');
          Row('Through', Place(E.A));
        end;
        Head('');
        Row('Delete takes it', 'or /guides for all');
      end;
  else
    Head('SOMETHING');
  end;
end;

procedure TMainForm.pbInfoPaint(Sender: TObject);
var
  I, W, H, Y, RowH, Pad, StepW, VX: Integer;
  C: TCanvas;
  R: TRect;
  S: string;
  SwatchCol: TColor;
begin
  W := pbInfo.Width;
  H := pbInfo.Height;
  if (W < 8) or (H < 8) then Exit;
  FInfoSkin.SetSize(W, H);
  PaintPanel(FInfoSkin, Rect(0, 0, W, H), Theme, FUIScale);
  FInfoSkin.DrawTo(pbInfo.Canvas, 0, 0);

  C := pbInfo.Canvas;
  Pad := Round(10 * FUIScale);
  RowH := Round(19 * FUIScale);
  StepW := Round(18 * FUIScale);
  Y := Pad;

  for I := 0 to High(FInfoRows) do
  begin
    if Y > H - RowH then Break;
    if FInfoRows[I].Head then
    begin
      { a rule and a small heading }
      if Y > Pad then Inc(Y, Round(6 * FUIScale));
      if FInfoRows[I].Caption <> '' then
      begin
        UIFont(C, 8, True, Theme.Accent);
        C.TextOut(Pad, Y, FInfoRows[I].Caption);
        Inc(Y, RowH);
      end;
      C.Pen.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.14));
      C.Pen.Width := 1;
      C.MoveTo(Pad, Y - Round(3 * FUIScale));
      C.LineTo(W - Pad, Y - Round(3 * FUIScale));
      Inc(Y, Round(4 * FUIScale));
      Continue;
    end;

    R := Rect(Pad, Y, W - Pad, Y + RowH);
    UIFont(C, 9, False, Theme.TextDim);
    C.TextOut(R.Left, Y + (RowH - C.TextHeight('X')) div 2,
      FInfoRows[I].Caption);

    VX := R.Left + Round(84 * FUIScale);
    if FInfoRows[I].Act in [iaSides, iaNoteSize, iaWidth] then
    begin
      { a number: two steppers at the right edge, the figure to their left so
        it does not move as it changes width }
      FInfoRows[I].Plus := Rect(W - Pad - StepW, Y + Round(2 * FUIScale),
        W - Pad, Y + RowH - Round(2 * FUIScale));
      FInfoRows[I].Minus := Rect(FInfoRows[I].Plus.Left - StepW - Round(3 * FUIScale),
        FInfoRows[I].Plus.Top, FInfoRows[I].Plus.Left - Round(3 * FUIScale),
        FInfoRows[I].Plus.Bottom);
      PaintInfoStep(C, FInfoRows[I].Minus, '-', FInfoHot = I * 2);
      PaintInfoStep(C, FInfoRows[I].Plus, '+', FInfoHot = I * 2 + 1);
      UIFont(C, 9, True, Theme.Text);
      S := FInfoRows[I].Value;
      C.TextOut(FInfoRows[I].Minus.Left - Round(8 * FUIScale) - C.TextWidth(S),
        Y + (RowH - C.TextHeight('X')) div 2, S);
    end
    else if FInfoRows[I].Act <> iaNone then
    begin
      { a yes/no or an action: one button naming what pressing it does }
      S := FInfoRows[I].Value;
      UIFont(C, 9, True, Theme.Text);
      FInfoRows[I].Plus := Rect(W - Pad - C.TextWidth(S) - Round(14 * FUIScale),
        Y + Round(2 * FUIScale), W - Pad, Y + RowH - Round(2 * FUIScale));
      FInfoRows[I].Minus := Rect(0, 0, 0, 0);
      PaintInfoStep(C, FInfoRows[I].Plus, S, FInfoHot = I * 2 + 1);
      { the current color as a swatch where the value would go }
      if (FInfoRows[I].Act in [iaColor, iaMaterial]) and
         (FInfoRows[I].Ent >= 0) and (FInfoRows[I].Ent < FD.Doc.Live) then
      begin
        C.Brush.Style := bsSolid;
        if FInfoRows[I].Act = iaMaterial then
        begin
          if not FD.Doc.Material(FInfoRows[I].Ent, SwatchCol) then
            SwatchCol := PixToColor(Pix($FA, $FA, $F6));
          C.Brush.Color := SwatchCol;
        end
        else
          C.Brush.Color := FD.Doc[FInfoRows[I].Ent].Ink;
        C.Pen.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.35));
        C.Pen.Width := 1;
        C.Rectangle(VX, Y + Round(3 * FUIScale),
          Min(VX + Round(36 * FUIScale), FInfoRows[I].Plus.Left - Round(6 * FUIScale)),
          Y + RowH - Round(3 * FUIScale));
        C.Brush.Style := bsClear;
      end;
    end
    else
    begin
      UIFont(C, 9, False, Theme.Text);
      S := FInfoRows[I].Value;
      { a long value is cut rather than run off the panel }
      S := CutToFit(C, S, W - Pad - VX);
      C.TextOut(VX, Y + (RowH - C.TextHeight('X')) div 2, S);
    end;
    Inc(Y, RowH);
  end;

  { A deck list can stand over the panel too, so the part that lands here is
    painted here, shifted from drawing to panel coordinates. }
  if FPopup <> POP_NONE then
    PaintPopup(C, pbScreen.Left - pbInfo.Left, pbScreen.Top - pbInfo.Top);
end;

{ one of the small square buttons beside a changeable value }
procedure TMainForm.PaintInfoStep(C: TCanvas; const R: TRect;
  const S: string; Hot: Boolean);
var
  Bg: TPix;
begin
  if Hot then Bg := MixPix(Theme.PanelHi, Theme.Accent, 0.45)
  else Bg := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.10);
  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(Bg);
  C.Pen.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.25));
  C.Pen.Width := 1;
  C.Rectangle(R);
  C.Brush.Style := bsClear;
  UIFont(C, 10, True, Theme.Text);
  C.TextOut((R.Left + R.Right - C.TextWidth(S)) div 2,
            (R.Top + R.Bottom - C.TextHeight(S)) div 2, S);
end;

{ The stepper under the cursor: row*2 for minus, row*2+1 for plus, or -1.
  The rects come from the painter. }
function TMainForm.InfoHit(X, Y: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FInfoRows) do
    if FInfoRows[I].Act <> iaNone then
    begin
      if PtInRect(FInfoRows[I].Minus, Point(X, Y)) then Exit(I * 2);
      if PtInRect(FInfoRows[I].Plus, Point(X, Y)) then Exit(I * 2 + 1);
    end;
end;

procedure TMainForm.pbInfoMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  H: Integer;
begin
  { an open list over the panel still tracks hover here }
  if FPopup <> POP_NONE then
  begin
    H := PopupItemAt(X + pbInfo.Left - pbScreen.Left,
                     Y + pbInfo.Top - pbScreen.Top);
    if (H < 0) and (FPopup = POP_CMDS) then H := FPopupHot;
    if H <> FPopupHot then
    begin
      FPopupHot := H;
      FScreenDirty := True;
      pbScreen.Invalidate;
      pbInfo.Invalidate;
    end;
    Exit;
  end;
  H := InfoHit(X, Y);
  if H <> FInfoHot then
  begin
    FInfoHot := H;
    pbInfo.Invalidate;
  end;
end;

procedure TMainForm.pbInfoMouseLeave(Sender: TObject);
begin
  if FInfoHot >= 0 then
  begin
    FInfoHot := -1;
    pbInfo.Invalidate;
  end;
end;

procedure TMainForm.pbInfoMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  H, Row, N, K, Which: Integer;
  Up: Boolean;
  Picked: TColor;
begin
  { and a press picks a list row rather than reaching the panel }
  if FPopup <> POP_NONE then
  begin
    Which := FPopup;
    H := -1;
    if Button = mbLeft then
      H := PopupItemAt(X + pbInfo.Left - pbScreen.Left,
                       Y + pbInfo.Top - pbScreen.Top);
    ClosePopup;
    if H >= 0 then PopupChoose(Which, H);
    Exit;
  end;
  if Button <> mbLeft then Exit;
  H := InfoHit(X, Y);
  if H < 0 then Exit;
  Row := H div 2;
  Up := Odd(H);

  case FInfoRows[Row].Act of
    iaSides:
      begin
        if (FInfoRows[Row].Ent < 0) or (FInfoRows[Row].Ent >= FD.Doc.Live) then Exit;
        N := ArcSteps(FD.Doc[FInfoRows[Row].Ent]);
        { same steps and limits as the + and - keys }
        if Up then N := Min(360, N + 1) else N := Max(3, N - 1);
        PushUndo;
        FD.Doc.SetArcSides(FInfoRows[Row].Ent, N);
        RebuildFlatFaces;
        FCmdMsg := Format('%d sides.', [N]);
      end;
    iaSoft:
      begin
        if (FInfoRows[Row].Ent < 0) or (FInfoRows[Row].Ent >= FD.Doc.Live) then Exit;
        PushUndo;
        N := Ord(not FD.Doc[FInfoRows[Row].Ent].Soft);
        FD.Doc.SetSoft(FInfoRows[Row].Ent, N <> 0);
        FCmdMsg := specialize IfThen<string>(N <> 0, 'Edge softened.',
          'Edge brought back.');
      end;
    iaNoteSize:
      begin
        if (FInfoRows[Row].Ent < 0) or (FInfoRows[Row].Ent >= FD.Doc.Live) then Exit;
        PushUndo;
        if Up then
          FD.Doc.SetNoteSize(FInfoRows[Row].Ent,
            FD.Doc.NoteSize(FInfoRows[Row].Ent) * 1.25)
        else
          FD.Doc.SetNoteSize(FInfoRows[Row].Ent,
            FD.Doc.NoteSize(FInfoRows[Row].Ent) / 1.25);
        FCmdMsg := Format('Text at %d%% of normal.',
          [Round(FD.Doc.NoteSize(FInfoRows[Row].Ent) * 100)]);
      end;
    iaWidth:
      begin
        if (FInfoRows[Row].Ent < 0) or (FInfoRows[Row].Ent >= FD.Doc.Live) then Exit;
        { through the widths the LINE WIDTH list offers }
        N := Round(Max(1, FD.Doc[FInfoRows[Row].Ent].Weight));
        K := 0;
        while (K < High(PEN_SIZES)) and (PEN_SIZES[K] < N) do Inc(K);
        if Up then
        begin
          if PEN_SIZES[K] <= N then K := Min(High(PEN_SIZES), K + 1);
        end
        else if K > 0 then
          Dec(K);
        PushUndo;
        FD.Doc.SetWeight(FInfoRows[Row].Ent, PEN_SIZES[K]);
        FCmdMsg := Format('%d px.', [PEN_SIZES[K]]);
      end;
    iaColor:
      begin
        { with several picked there is no one color to start from, so the
          dialog opens on the current pen }
        if FInfoRows[Row].Ent < 0 then
        begin
          if not AskColor(FInkColor, Picked) then Exit;
          PushUndo;
          K := InkSelectedThings(Picked);
          FCmdMsg := Format('%d thing%s recolored.',
            [K, specialize IfThen<string>(K = 1, '', 's')]);
          RenderInk;
          RecomposeAll;
          RebuildInfo;
          pbInfo.Invalidate;
          pbScreen.Invalidate;
          pbCmd.Invalidate;
          Exit;
        end;
        if FInfoRows[Row].Ent >= FD.Doc.Live then Exit;
        if not AskColor(FD.Doc[FInfoRows[Row].Ent].Ink, Picked) then Exit;
        PushUndo;
        FD.Doc.SetInk(FInfoRows[Row].Ent, Picked);
        FCmdMsg := 'Color changed.  The LINE COLOR button still sets what you draw next.';
      end;
    iaMaterial:
      begin
        if FInfoRows[Row].Ent >= FD.Doc.Live then Exit;
        { start from the current material, or the default it looks like
          (always the default with several picked) }
        if (FInfoRows[Row].Ent < 0) or
           not FD.Doc.Material(FInfoRows[Row].Ent, Picked) then
          Picked := PixToColor(Pix($FA, $FA, $F6));
        if not AskColor(Picked, Picked) then Exit;
        PushUndo;
        K := PaintSelectedFaces(FInfoRows[Row].Ent, Picked, True);
        if K > 1 then
          FCmdMsg := Format('%d faces painted.', [K])
        else
          FCmdMsg := 'Face painted.  The LINE COLOR button still sets what you draw next.';
      end;
    iaUnpaint:
      begin
        if FInfoRows[Row].Ent >= FD.Doc.Live then Exit;
        PushUndo;
        K := PaintSelectedFaces(FInfoRows[Row].Ent, clNone, False);
        if K > 1 then
          FCmdMsg := Format('%d faces back to the default material.', [K])
        else
          FCmdMsg := 'Back to the default material.';
      end;
    { group rows carry the group id in Ent, not an entity }
    iaPartOpen: OpenGroup(FInfoRows[Row].Ent);
    iaPartLock:
      begin
        PushUndo;
        FD.Doc.SetPartLocked(FInfoRows[Row].Ent, not FD.Doc.PartLocked(FInfoRows[Row].Ent));
        if FD.Doc.PartLocked(FInfoRows[Row].Ent) then FCmdMsg := 'Locked.' else FCmdMsg := 'Unlocked.';
      end;
    iaPartExplode: ExplodeGroups;
    iaPartHide: HideGroups(True, '');
    iaPartRename:
      begin
        { the command bar, prefilled with the name }
        FInput := '/name ' + FD.Doc.PartName(FInfoRows[Row].Ent);
        SyncCmdList;
        FCmdMsg := 'Type the name and press Enter.';
      end;
    iaReverse:
      begin
        PushUndo;
        K := ReverseSelectedFaces;
        FCmdMsg := Format('%d face%s turned over.',
          [K, specialize IfThen<string>(K = 1, '', 's')]);
      end;
  else
    Exit;
  end;

  RenderInk;
  RecomposeAll;
  RebuildInfo;
  pbInfo.Invalidate;
  pbScreen.Invalidate;
  pbCmd.Invalidate;
end;

procedure TMainForm.pbToolsPaint(Sender: TObject);
var
  I, W, H, IconSz, TxtX, ArrY: Integer;
  It: TDeckItem;
  Sel, Hot: Boolean;
  C1, C2, Edge, Fg: TPix;
  R, IR: TRect;
  S: string;
begin
  W := pbTools.Width;
  H := pbTools.Height;
  if (W < 8) or (H < 8) then Exit;
  FToolSkin.SetSize(W, H);
  PaintPanel(FToolSkin, Rect(0, 0, W, H), Theme, FUIScale);

  IconSz := Round(16 * FUIScale);
  for I := 0 to High(FTools) do
  begin
    It := FTools[I];
    R := It.Bounds;
    Sel := (It.Group = GRP_TOOL) and (It.Value = Ord(FTool));
    Hot := I = FHotTool;
    if Sel then
    begin
      C1 := Theme.Accent;
      C2 := ShadePix(Theme.Accent, 0.86);
      Fg := Pix(12, 16, 22);
      Edge := ShadePix(Theme.Accent, 1.18);
    end
    else
    begin
      C1 := MixPix(Theme.Panel, Pix(255, 255, 255), IfThen(Hot, 0.14, 0.05) / 1.0);
      C2 := MixPix(Theme.Panel, Pix(0, 0, 0), 0.16);
      Fg := Theme.Text;
      Edge := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.10);
    end;
    FToolSkin.RoundRectV(R, Round(4 * FUIScale), C1, C2);
    FToolSkin.RoundFrame(R, Round(4 * FUIScale), 1.0, Edge);
    IR := Rect(R.Left + Round(6 * FUIScale),
               (R.Top + R.Bottom - IconSz) div 2,
               R.Left + Round(6 * FUIScale) + IconSz,
               (R.Top + R.Bottom + IconSz) div 2);
    PaintIcon(FToolSkin, It.Icon, IR, Fg);
  end;

  { the lines between the groups }
  for I := 0 to High(FToolRules) do
    FToolSkin.Line(Round(10 * FUIScale), FToolRules[I],
      W - Round(10 * FUIScale), FToolRules[I], 1,
      MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.16), 1.0);

  { the collapse arrow, at the foot }
  ArrY := H - Round(20 * FUIScale);
  FToolSkin.Line(Round(8 * FUIScale), ArrY - Round(8 * FUIScale),
    W - Round(8 * FUIScale), ArrY - Round(8 * FUIScale), 1,
    MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.10), 1.0);
  FToolSkin.DrawTo(pbTools.Canvas, 0, 0);

  if FToolsWide then
  begin
    TxtX := Round(6 * FUIScale) + IconSz + Round(7 * FUIScale);
    for I := 0 to High(FTools) do
    begin
      It := FTools[I];
      R := It.Bounds;
      if (It.Group = GRP_TOOL) and (It.Value = Ord(FTool)) then
        UIFont(pbTools.Canvas, 9, True, Pix(12, 16, 22))
      else if It.Group = GRP_POPUP then
        UIFont(pbTools.Canvas, 9, True, Theme.TextDim)
      else
        UIFont(pbTools.Canvas, 9, False, Theme.Text);
      S := It.Caption;
      if It.Group = GRP_POPUP then S := S + '  >';
      pbTools.Canvas.TextOut(R.Left + TxtX,
        (R.Top + R.Bottom - pbTools.Canvas.TextHeight(S)) div 2, S);
    end;
  end;

  { says what it does to the strip, not to the names }
  UIFont(pbTools.Canvas, 9, False, Theme.TextDim);
  if FToolsWide then S := '<  COLLAPSE' else S := '>';
  pbTools.Canvas.TextOut(Round(8 * FUIScale),
    ArrY - pbTools.Canvas.TextHeight(S) div 2, S);
end;

procedure TMainForm.pbToolsMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  H: Integer;
begin
  H := ToolsHit(X, Y);
  if H <> FHotTool then
  begin
    FHotTool := H;
    pbTools.Invalidate;
  end;
  { the tip beside the button, level with it }
  FChromeTipX := Round(6 * FUIScale);
  if (H >= 0) and (H <= High(FTools)) then
  begin
    FChromeTip := FTools[H].Caption;
    FChromeTipBody := FTools[H].Hint;
    FChromeTipY := (FTools[H].Bounds.Top + FTools[H].Bounds.Bottom) div 2
                   + pbTools.Top - pbScreen.Top;
  end
  else if H = -2 then
  begin
    FChromeTip := IfThen(FToolsWide, 'COLLAPSE', 'EXPAND');
    FChromeTipBody := IfThen(FToolsWide,
      'Put the names away and give the width to the drawing.',
      'Show the tool names again.');
    FChromeTipY := pbTools.Height - Round(20 * FUIScale)
                   + pbTools.Top - pbScreen.Top;
  end
  else
  begin
    FChromeTip := '';
    FChromeTipBody := '';
  end;
  pbScreen.Invalidate;
end;

procedure TMainForm.pbToolsMouseLeave(Sender: TObject);
begin
  if FHotTool <> -1 then
  begin
    FHotTool := -1;
    pbTools.Invalidate;
  end;
  FChromeTip := '';
  FChromeTipBody := '';
  pbScreen.Invalidate;
end;

procedure TMainForm.pbToolsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  H: Integer;
begin
  if Button <> mbLeft then Exit;
  H := ToolsHit(X, Y);
  if H = -2 then
  begin
    FToolsWide := not FToolsWide;
    SaveSettings;
    Relayout;
    Exit;
  end;
  if (H < 0) or (H > High(FTools)) then
  begin
    { a click on the bare strip still closes an open list }
    if FPopup <> POP_NONE then ClosePopup;
    Exit;
  end;
  if FTools[H].Group = GRP_TOOL then
  begin
    if FPopup <> POP_NONE then ClosePopup;
    SetTool(TTool(FTools[H].Value));
  end
  else if FTools[H].Group = GRP_POPUP then
    { clicking the open one shuts it, as menu buttons do everywhere else }
    if FPopup = FTools[H].Value then ClosePopup
    else OpenPopup(FTools[H].Value);
end;

{ ---------------------------------------------------------------------- }
{ the cut - the slice a plan view is taken out of                          }
{ ---------------------------------------------------------------------- }

{ The cut strip: two length fields, the bottom of the slice and the top.
  Lengths, not a spin edit, so ParseLen reads anything typed and FormatLen
  writes it at the drawing's precision.  The arrows step by the snap.
  Typing goes to the command bar, as everything else typed does
  (see EditDimUnder). }
function TMainForm.SliceFieldRect(Which: Integer): TRect;
var
  LabW, Pad, FW: Integer;
begin
  Pad := Round(4 * FUIScale);
  LabW := Round(34 * FUIScale);
  FW := (pbSlice.Width - LabW - 3 * Pad) div 2;
  if Which = 1 then
    Result := Rect(LabW + Pad, 1, LabW + Pad + FW, pbSlice.Height - 1)
  else
    Result := Rect(LabW + 2 * Pad + FW, 1, LabW + 2 * Pad + 2 * FW,
                   pbSlice.Height - 1);
end;

function TMainForm.SliceZoneAt(X, Y: Integer): Integer;
var
  I, ArrW: Integer;
  R: TRect;
begin
  Result := -1;
  ArrW := Round(13 * FUIScale);
  for I := 1 to 2 do
  begin
    R := SliceFieldRect(I);
    if (X >= R.Left) and (X < R.Right) and (Y >= R.Top) and (Y < R.Bottom) then
    begin
      if X >= R.Right - ArrW then
      begin
        if Y < (R.Top + R.Bottom) div 2 then Exit(2 + I)   // 3 up-lo, 4 up-hi
        else Exit(4 + I);                                   // 5 dn-lo, 6 dn-hi
      end;
      Exit(I);
    end;
  end;
  if X < SliceFieldRect(1).Left then Result := 0;
end;

procedure TMainForm.pbSlicePaint(Sender: TObject);
var
  W, H, I, ArrW, MidY, CX: Integer;
  R: TRect;
  S: string;
  Body, Edge: TPix;
begin
  W := pbSlice.Width;
  H := pbSlice.Height;
  if (W < 8) or (H < 8) then Exit;
  FSliceSkin.SetSize(W, H);
  FSliceSkin.Clear(Pix(0, 0, 0));
  FSliceSkin.CopyRegion(FShell, pbSlice.Left, pbSlice.Top, 0, 0, W, H);
  if LightChrome then
    FSliceSkin.RoundRectV(Rect(0, 0, W, H), H / 2,
      MixPix(Theme.Panel, Pix(0, 0, 0), 0.06), MixPix(Theme.Panel, Pix(0, 0, 0), 0.14))
  else
    FSliceSkin.RoundRectV(Rect(0, 0, W, H), H / 2,
      MixPix(Theme.Panel, Pix(0, 0, 0), 0.20), MixPix(Theme.Panel, Pix(0, 0, 0), 0.42));
  FSliceSkin.RoundFrame(Rect(0, 0, W, H), H / 2, 1.0,
    MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.14));

  ArrW := Round(13 * FUIScale);
  for I := 1 to 2 do
  begin
    R := SliceFieldRect(I);
    Body := FieldPix;
    { the field being typed into is lit }
    if FSliceEdit = I then
    begin
      if LightChrome then Body := MixPix(Pix(255, 255, 255), Theme.Accent, 0.12)
      else Body := MixPix(Theme.Accent, Pix(0, 0, 0), 0.55);
    end
    else if FHotSlice = I then Body := MixPix(Body, Theme.Accent, 0.10);
    FSliceSkin.RoundRect(R, Round(3 * FUIScale), Body);
    Edge := FieldEdgePix;
    if FSliceEdit = I then Edge := Theme.Accent;
    FSliceSkin.RoundFrame(R, Round(3 * FUIScale), 1.0, Edge);
  end;
  FSliceSkin.DrawTo(pbSlice.Canvas, 0, 0);

  UIFont(pbSlice.Canvas, 9, True, Theme.TextDim);
  pbSlice.Canvas.TextOut(Round(8 * FUIScale),
    (H - pbSlice.Canvas.TextHeight('CUT')) div 2, 'CUT');

  for I := 1 to 2 do
  begin
    R := SliceFieldRect(I);
    if I = 1 then S := FormatLen(FD.SliceLo, FD.Units)
    else S := FormatLen(FD.SliceHi, FD.Units);
    if FSliceEdit = I then S := FInput + '_';
    if not FD.SliceOn then
      UIFont(pbSlice.Canvas, 9, False, Theme.TextDim)
    else
      UIFont(pbSlice.Canvas, 9, True, Theme.Text);
    pbSlice.Canvas.TextOut(R.Left + Round(6 * FUIScale),
      (H - pbSlice.Canvas.TextHeight(S)) div 2, S);

    { the two chevrons, a cue that it can be turned }
    MidY := (R.Top + R.Bottom) div 2;
    CX := R.Right - ArrW div 2 - Round(2 * FUIScale);
    pbSlice.Canvas.Brush.Style := bsSolid;
    pbSlice.Canvas.Brush.Color := PixToColor(Theme.TextDim);
    pbSlice.Canvas.Pen.Color := PixToColor(Theme.TextDim);
    pbSlice.Canvas.Polygon([Point(CX - 4, MidY - 2), Point(CX + 4, MidY - 2),
                            Point(CX, MidY - 7)]);
    pbSlice.Canvas.Polygon([Point(CX - 4, MidY + 2), Point(CX + 4, MidY + 2),
                            Point(CX, MidY + 7)]);
    pbSlice.Canvas.Brush.Style := bsClear;
  end;
end;

procedure TMainForm.pbSliceMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  Z: Integer;
begin
  Z := SliceZoneAt(X, Y);
  if Z <> FHotSlice then
  begin
    FHotSlice := Z;
    pbSlice.Invalidate;
  end;
end;

procedure TMainForm.pbSliceMouseLeave(Sender: TObject);
begin
  if FHotSlice <> -1 then
  begin
    FHotSlice := -1;
    pbSlice.Invalidate;
  end;
end;

procedure TMainForm.pbSliceMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Z: Integer;
begin
  if Button <> mbLeft then Exit;
  Z := SliceZoneAt(X, Y);
  case Z of
    3: NudgeSlice(1, 1);
    4: NudgeSlice(1, 2);
    5: NudgeSlice(-1, 1);
    6: NudgeSlice(-1, 2);
    1, 2:
      begin
        { typed in the command bar, like a dimension's text }
        FSliceEdit := Z;
        FInput := '';
        if Z = 1 then
          FCmdMsg := 'Type the bottom of the slice - the height you draw at.  Esc leaves it.'
        else
          FCmdMsg := 'Type the top of the slice.  Esc leaves it.';
        pbSlice.Invalidate;
        pbCmd.Invalidate;
      end;
    0:
      { the label switches the whole feature on or off }
      if FD.SliceOn then SetSlice(False, FD.SliceLo, FD.SliceHi)
      else SetSlice(True, FD.SliceLo, FD.SliceHi);
  end;
end;

procedure TMainForm.pbSliceMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  Z, Steps: Integer;
begin
  Handled := True;
  if WheelDelta > 0 then Steps := 1 else Steps := -1;
  Z := SliceZoneAt(MousePos.X, MousePos.Y);
  case Z of
    1, 3, 5: NudgeSlice(Steps, 1);
    2, 4, 6: NudgeSlice(Steps, 2);
  else
    NudgeSlice(Steps, 0);
  end;
end;

{ take what was typed into one of the two fields }
procedure TMainForm.CommitSliceEdit;
var
  W: Integer;
  V: Double;
begin
  W := FSliceEdit;
  FSliceEdit := 0;
  if W = 0 then Exit;
  if Trim(FInput) = '' then
  begin
    FInput := '';
    FCmdMsg := 'Left as it was.';
    pbSlice.Invalidate;
    Exit;
  end;
  if not ParseLen(FInput, FD.Units, V) then
  begin
    FCmdMsg := 'I could not read "' + FInput + '" as a height.';
    FInput := '';
    pbSlice.Invalidate;
    Exit;
  end;
  FInput := '';
  if W = 1 then SetSlice(True, V, Max(V, FD.SliceHi))
  else SetSlice(True, Min(FD.SliceLo, V), V);
  pbSlice.Invalidate;
end;

{ The view list behind the arrow: the two paper modes, then every camera
  preset.  Built from the same table the button steps through. }
procedure TMainForm.FillViewMenu;
var
  I: Integer;
  M: TMenuItem;
begin
  pmView.Items.Clear;

  { PLAN first: a plan is a slice through the model, and the cut fields live
    there, so it must be reachable by mouse.  TOP is the free camera looking
    nearly straight down, which looks like a plan but has no cut; both
    captions say what they are. }
  M := TMenuItem.Create(pmView);
  M.Caption := 'PLAN - flat, with the cut';
  M.Tag := 0;
  M.OnClick := @ViewMenuClick;
  pmView.Items.Add(M);

  M := TMenuItem.Create(pmView);
  M.Caption := 'ISO - flat, on the paper axes';
  M.Tag := 1;
  M.OnClick := @ViewMenuClick;
  pmView.Items.Add(M);

  M := TMenuItem.Create(pmView);
  M.Caption := '-';
  pmView.Items.Add(M);

  for I := FIRST_CAMERA_PRESET to High(VIEW_PRESETS) do
  begin
    M := TMenuItem.Create(pmView);
    if I = High(VIEW_PRESETS) then M.Caption := 'TOP - 3D, from above'
    else M.Caption := VIEW_PRESETS[I].Name;
    M.Tag := I;
    M.OnClick := @ViewMenuClick;
    pmView.Items.Add(M);
  end;
end;

procedure TMainForm.ViewMenuClick(Sender: TObject);
begin
  ApplyViewPreset((Sender as TMenuItem).Tag);
end;

{ What the button says: the paper mode, the preset the camera is parked on,
  or 3D once orbited elsewhere. }
function TMainForm.ViewButtonName: string;
begin
  if FD.View = vkPlan then Exit('PLAN PAPER');
  if FD.View = vkIso then Exit('ISO PAPER');
  if (FViewPreset >= FIRST_CAMERA_PRESET) and (FViewPreset <= High(VIEW_PRESETS)) then
    Result := 'VIEW: ' + VIEW_PRESETS[FViewPreset].Name
  else
    Result := 'VIEW: 3D';
end;

procedure TMainForm.pbViewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Z: Integer;
begin
  if X >= pbView.Width - VIEW_ARROW_W then Z := 1 else Z := 0;
  if FHotView <> Z then
  begin
    FHotView := Z;
    pbView.Invalidate;
  end;
end;

procedure TMainForm.pbViewMouseLeave(Sender: TObject);
begin
  FHotView := -1;
  pbView.Invalidate;
end;

procedure TMainForm.pbViewMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  { the arrow opens the list; on the name, left steps forward through the
    presets and right steps back }
  if X >= pbView.Width - VIEW_ARROW_W then
  begin
    with pbView.ClientToScreen(Point(pbView.Width - VIEW_ARROW_W, pbView.Height)) do
      pmView.PopUp(X, Y);
    Exit;
  end;
  if Button = mbLeft then CycleViewPreset(1)
  else if Button = mbRight then CycleViewPreset(-1);
end;

{ The slash button: starts a command with the list up; pressing it again
  puts the list away.  Right-click offers to copy the message or input. }
procedure TMainForm.pbCmdMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  It: TMenuItem;
  Pt: TPoint;
begin
  if (Button = mbRight) then
  begin
    pmCmd.Items.Clear;
    It := TMenuItem.Create(pmCmd);
    It.Caption := 'Copy the Message';
    It.Tag := 1;
    It.Enabled := FCmdMsg <> '';
    It.OnClick := @CmdMenuClick;
    pmCmd.Items.Add(It);
    It := TMenuItem.Create(pmCmd);
    It.Caption := 'Copy What Is Typed';
    It.Tag := 2;
    It.Enabled := FInput <> '';
    It.OnClick := @CmdMenuClick;
    pmCmd.Items.Add(It);
    Pt := pbCmd.ClientToScreen(Point(X, Y));
    pmCmd.PopUp(Pt.X, Pt.Y);
    Exit;
  end;
  if Button <> mbLeft then Exit;
  if not PtInRect(FCmdArrow, Point(X, Y)) then Exit;
  if FPopup = POP_CMDS then
  begin
    ClosePopup;
    FInput := '';
  end
  else
  begin
    FInput := '/';
    SyncCmdList;
  end;
  pbCmd.Invalidate;
  pbScreen.Invalidate;
end;

procedure TMainForm.pbCmdMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  Was: Boolean;
begin
  Was := FCmdArrowHot;
  FCmdArrowHot := PtInRect(FCmdArrow, Point(X, Y));
  if FCmdArrowHot <> Was then pbCmd.Invalidate;
end;

procedure TMainForm.pbCmdMouseLeave(Sender: TObject);
begin
  if FCmdArrowHot then
  begin
    FCmdArrowHot := False;
    pbCmd.Invalidate;
  end;
end;

{ The command bar: three rows.  Row one is the tool and the moment:
  what the cursor holds (in its mark's color), the prompt, and the typing in
  its own box.  Rows two and three are the message, drawn by LazInk so it
  wraps and is colored (right-click copies it); the keys that apply now
  follow it and drop out of sight when the message needs both lines. }
procedure TMainForm.CmdRows(out Pad, Row1, Row: Integer);
begin
  Pad := Round(5 * FUIScale);
  Row1 := Round(24 * FUIScale);
  Row := Round(18 * FUIScale);
end;

function TMainForm.CmdBarHeight: Integer;
var
  Pad, Row1, Row: Integer;
begin
  CmdRows(Pad, Row1, Row);
  Result := Pad + Row1 + Round(3 * FUIScale) + 2 * Row + Pad + Round(4 * FUIScale);
end;

{ where the message rows sit: under row one, from past the slash button to
  the right edge, in the bar's coordinates }
procedure TMainForm.PlaceCmdMsg;
var
  Pad, Row1, Row: Integer;
begin
  CmdRows(Pad, Row1, Row);
  { the tool pill sits left of the message rows, in a column as wide as the
    longest tool name, so messages start in one place }
  UIFont(pbCmd.Canvas, 10, True, Theme.Accent);
  FCmdPillW := pbCmd.Canvas.TextWidth('PROTRACTOR') + Round(18 * FUIScale);
  FCmdMsgR := Rect(Round(56 * FUIScale) + FCmdPillW + Round(10 * FUIScale), Pad + Row1 + Round(5 * FUIScale),
    Max(Round(96 * FUIScale), pbCmd.Width - Round(24 * FUIScale)),
    Pad + Row1 + Round(5 * FUIScale) + 2 * Row);
end;

{ Whether the chrome is pale (Light theme), so "sunk" things go lighter
  rather than darker. }
function TMainForm.LightChrome: Boolean;
begin
  Result := (Theme.Panel.R + Theme.Panel.G + Theme.Panel.B) > 3 * 140;
end;

{ A field to type into or read from (cut heights, command bar).  Sunk into a
  dark panel; on a pale one near white with an edge, since a darkened pale
  panel is a gray slab the text sinks into. }
function TMainForm.FieldPix: TPix;
begin
  if LightChrome then Result := MixPix(Theme.Panel, Pix(255, 255, 255), 0.75)
  else Result := MixPix(Theme.Panel, Pix(0, 0, 0), 0.30);
end;

function TMainForm.FieldEdgePix: TPix;
begin
  if LightChrome then Result := MixPix(Theme.Panel, Pix(0, 0, 0), 0.22)
  else Result := MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.10);
end;

{ The colors of the bar's text, from the theme.  Bright marks are darkened
  on a light panel. }
function TMainForm.CmdPalette: TCmdPalette;
var
  Light: Boolean;

  function Hex(const C: TPix): string;
  begin
    Result := Format('#%.2x%.2x%.2x', [C.R, C.G, C.B]);
  end;

  function Mark(const C: TPix): string;
  begin
    if Light then Result := Hex(MixPix(C, Pix(0, 0, 0), 0.40))
    else Result := Hex(C);
  end;

begin
  Light := LightChrome;
  Result.Text := Hex(Theme.Text);
  Result.Dim := Hex(Theme.TextDim);
  Result.Name := Hex(Theme.Text);
  Result.Number := Mark(Pix(245, 190, 80));
  Result.Command := Hex(Theme.Accent);
  Result.Key := Hex(Theme.Text);
  Result.KeyBack := Hex(MixPix(Theme.Panel, Pix(255, 255, 255), 0.16));
  { typed text: green units, pink operators, a violet x, all distinct from
    the amber figures }
  Result.Units := Mark(Pix(110, 240, 150));
  Result.Op := Mark(Pix(255, 110, 180));
  Result.Sep := Mark(Pix(190, 150, 255));
end;

{ the color the snap's mark is drawn in (see PaintSnapMarker) }
function TMainForm.SnapMarkPix: TPix;
begin
  case FSnapKind of
    snEndpoint, snCenter: Result := Pix(60, 210, 90);
    snMidpoint, snSubMid: Result := Pix(90, 220, 235);
    snOnEdge:             Result := Pix(235, 70, 70);
    snOnFace:             Result := Pix(70, 130, 240);
    snQuadrant:           Result := Pix(90, 235, 120);
    snOnAxis:             Result := AxisPix(FSnapAxis);
    snOrigin:             Result := Pix(250, 210, 60);
    snCross:              Result := Pix(215, 120, 240);
  else
    Result := Theme.Accent;
  end;
end;

procedure TMainForm.pbCmdPaint(Sender: TObject);
var
  W, H, X, TW, I, Pad, Row1, Row, Y1, IL, IW: Integer;
  S, M, Caret: string;
  SumV, SumW: Double;
  P: TCmdPalette;
  Opt: THTMLOptions;
  Well, SnapCol: TPix;
  Sz: TSize;
  C: TCanvas;
begin
  W := pbCmd.Width;
  H := pbCmd.Height;
  C := pbCmd.Canvas;
  CmdRows(Pad, Row1, Row);
  Y1 := Pad;
  { the wells the typing and messages sit in: one flat color, the memo's, so
    they read as one piece }
  Well := FieldPix;
  FCmdSkin.SetSize(W, H);
  FCmdSkin.Clear(Pix(0, 0, 0));
  FCmdSkin.CopyRegion(FShell, pbCmd.Left, pbCmd.Top, 0, 0, W, H);
  PaintPanel(FCmdSkin, Rect(0, 0, W, H), Theme, Round(10 * FUIScale));
  FCmdSkin.RoundRect(Rect(Round(6 * FUIScale), Round(6 * FUIScale),
    Round(10 * FUIScale), H - Round(6 * FUIScale)), 2, Theme.Accent, 0.9);
  if FCmdMsgR.Right > FCmdMsgR.Left then
    FCmdSkin.RoundRect(Rect(FCmdMsgR.Left - Round(6 * FUIScale), FCmdMsgR.Top - Round(3 * FUIScale),
      FCmdMsgR.Right + Round(6 * FUIScale), FCmdMsgR.Bottom + Round(3 * FUIScale)),
      Round(6 * FUIScale), Well, 1.0);
  { on a pale panel a near-white well needs an edge to be seen }
  if LightChrome and (FCmdMsgR.Right > FCmdMsgR.Left) then
    FCmdSkin.RoundFrame(Rect(FCmdMsgR.Left - Round(6 * FUIScale), FCmdMsgR.Top - Round(3 * FUIScale),
      FCmdMsgR.Right + Round(6 * FUIScale), FCmdMsgR.Bottom + Round(3 * FUIScale)),
      Round(6 * FUIScale), 1.0, FieldEdgePix);
  FCmdSkin.DrawTo(C, 0, 0);
  P := CmdPalette;

  { The slash button: pressing it types the slash and brings up the list,
    just as typing one does.  A way in for anybody not using the keyboard. }
  FCmdArrow := Rect(Round(16 * FUIScale), Y1 + Round(1 * FUIScale),
                    Round(44 * FUIScale), Y1 + Row1 - Round(1 * FUIScale));
  C.Brush.Style := bsSolid;
  if FCmdArrowHot or (FPopup = POP_CMDS) then
    C.Brush.Color := PixToColor(Theme.Accent)
  else
    C.Brush.Color := PixToColor(MixPix(Theme.Panel, Pix(255, 255, 255), 0.10));
  C.Pen.Style := psClear;
  C.RoundRect(FCmdArrow.Left, FCmdArrow.Top, FCmdArrow.Right, FCmdArrow.Bottom,
    Round(7 * FUIScale), Round(7 * FUIScale));
  C.Pen.Style := psSolid;
  C.Brush.Style := bsClear;
  if FCmdArrowHot or (FPopup = POP_CMDS) then
    UIFont(C, 12, True, OnPix(Theme.Accent))
  else
    UIFont(C, 12, True, Theme.TextDim);
  S := '/';
  C.TextOut((FCmdArrow.Left + FCmdArrow.Right - C.TextWidth(S)) div 2,
    (FCmdArrow.Top + FCmdArrow.Bottom - C.TextHeight(S)) div 2, S);

  X := Round(56 * FUIScale);
  if FBusy then
  begin
    { long work on the main thread: what and how far, in place of the prompt }
    UIFont(C, 11, True, Theme.Accent);
    S := 'WORKING';
    C.TextOut(X, Y1 + (Row1 - C.TextHeight(S)) div 2, S);
    Inc(X, C.TextWidth(S) + Round(14 * FUIScale));
    UIFont(C, 11, False, Theme.Text);
    S := FBusyMsg;
    if FBusyFrac >= 0 then S := S + Format('  %d%%', [Round(EnsureRange(FBusyFrac, 0, 1) * 100)]);
    C.TextOut(X, Y1 + (Row1 - C.TextHeight(S)) div 2, S);
    Inc(X, C.TextWidth(S) + Round(18 * FUIScale));
    TW := W - X - Round(24 * FUIScale);
    if TW > Round(80 * FUIScale) then
    begin
      C.Pen.Style := psClear;
      C.Brush.Style := bsSolid;
      C.Brush.Color := PixToColor(Theme.Panel);
      C.RoundRect(X, Y1 + Row1 div 2 - Round(4 * FUIScale), X + TW, Y1 + Row1 div 2 + Round(4 * FUIScale),
        Round(8 * FUIScale), Round(8 * FUIScale));
      C.Brush.Color := PixToColor(Theme.Accent);
      if FBusyFrac >= 0 then
        C.RoundRect(X, Y1 + Row1 div 2 - Round(4 * FUIScale),
          X + Max(Round(8 * FUIScale), Round(TW * EnsureRange(FBusyFrac, 0, 1))), Y1 + Row1 div 2 + Round(4 * FUIScale),
          Round(8 * FUIScale), Round(8 * FUIScale))
      else
      begin
        { unknown progress: a light running along the track }
        I := Round((TW - TW div 5) * (0.5 - 0.5 * Cos(((GetTickCount64 mod 1400) / 1400) * 2 * Pi)));
        C.RoundRect(X + I, Y1 + Row1 div 2 - Round(4 * FUIScale), X + I + TW div 5, Y1 + Row1 div 2 + Round(4 * FUIScale),
          Round(8 * FUIScale), Round(8 * FUIScale));
      end;
      C.Pen.Style := psSolid;
      C.Brush.Style := bsClear;
    end;
    PaintCmdMsg(C, P);
    Exit;
  end;

  { the tool in an accent pill, left of the message rows }
  UIFont(C, 10, True, Theme.Accent);
  S := ToolName(FTool);
  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(MixPix(Theme.Panel, Theme.Accent, 0.20));
  C.Pen.Color := PixToColor(MixPix(Theme.Panel, Theme.Accent, 0.55));
  I := FCmdMsgR.Top - Round(3 * FUIScale);
  C.RoundRect(X, I, X + FCmdPillW, I + Row1 - Round(4 * FUIScale),
    Round(10 * FUIScale), Round(10 * FUIScale));
  C.Brush.Style := bsClear;
  C.TextOut(X + (FCmdPillW - C.TextWidth(S)) div 2,
    I + (Row1 - Round(4 * FUIScale) - C.TextHeight(S)) div 2, S);

  { Like SketchUp's measurements box: while dragging it shows the size being
    pulled, and once you type your figure takes its place.  The number goes
    where the typing goes, because they are the same number. }
  if (GetTickCount64 div 500) mod 2 = 0 then Caret := '|' else Caret := NBSP;
  if FInput <> '' then
  begin
    M := MarkTyped(FInput, P) + Painted(P.Command, '', False) +
      '<font color="' + P.Command + '">' + Caret + '</font>';
    { a typed sum (8' + 8") shows its total as you type (see ParseLen) }
    if ParseLen(FInput, FD.Units, SumV) and
       (not ParseLenPlain(FInput, FD.Units, SumW) or (Abs(SumV - SumW) > 1E-9)) then
      M := M + Painted(P.Dim, '   = ') + Painted(P.Number, FormatLen(SumV, FD.Units), True);
  end
  else
  begin
    S := LiveMeasure;
    { dimmer than typed text: a reading, not a decision }
    if S <> '' then M := Painted(P.Dim, S) + '<font color="' + P.Dim + '">' + Caret + '</font>'
    else M := '<font color="' + P.Command + '">' + Caret + '</font>' +
      Painted(P.Dim, ' type a size, or / for a command');
  end;
  { the typing box next to the slash, as wide as its content, the prompt
    after it }
  IW := EnsureRange(DrawCmdRuns(C, 0, 0, Row1, MaxInt, 12, True, M, True) +
    Round(24 * FUIScale), FCmdPillW + Round(10 * FUIScale) + Round(220 * FUIScale), W * 2 div 5);
  IL := X;
  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(Well);
  if FInput <> '' then C.Pen.Color := PixToColor(Theme.Accent)
  else C.Pen.Color := PixToColor(FieldEdgePix);
  C.RoundRect(IL, Y1 + Round(1 * FUIScale), IL + IW, Y1 + Row1 - Round(1 * FUIScale),
    Round(8 * FUIScale), Round(8 * FUIScale));
  C.Brush.Style := bsClear;
  DrawCmdRuns(C, IL + Round(12 * FUIScale), Y1, Row1, IL + IW - Round(8 * FUIScale), 12, True, M);
  X := IL + IW + Round(14 * FUIScale);
  IL := W - Round(18 * FUIScale);

  { What the cursor is holding, then what to do with it, in the color of the
    cursor's mark (as the cursor chip and SketchUp's status line read). }
  M := '';
  if (FD <> nil) and (FD.Doc.Context <> 0) then
    M := Painted(P.Dim, 'in ') + Painted(P.Name, '"' + FD.Doc.PartName(FD.Doc.Context) + '"', True) +
      Painted(P.Dim, '  ');
  { an axis lock in its axis color, parallel/perpendicular in SketchUp's
    magenta, otherwise the mark's color }
  if FAxisLock in [0..2] then SnapCol := AxisPix(FAxisLock)
  else if FParPerp in [1, 2] then SnapCol := Pix(220, 80, 220)
  else SnapCol := SnapMarkPix;
  if (SnapSays <> '') then
    M := M + '<b><font color="' + Format('#%.2x%.2x%.2x', [SnapCol.R, SnapCol.G, SnapCol.B]) +
      '">' + CmdEsc(SnapSays) + '</font></b>' + Painted(P.Dim, '  ' + #$E2#$80#$BA + '  ');
  M := M + MarkMessage(PromptForTool, P);
  DrawCmdRuns(C, X, Y1, Row1, IL, 11, False, M);
  PaintCmdMsg(C, P);
end;

{ One line of the bar's markup, ending in an ellipsis at MaxX when it does
  not fit.  Returns the width it took (or would take, with Measure). }
function TMainForm.DrawCmdRuns(C: TCanvas; X, Y, H, MaxX, Size: Integer;
  Mono: Boolean; const M: string; Measure: Boolean): Integer;
var
  Opt: THTMLOptions;
  R: TRect;
begin
  UIFont(C, Size, False, Theme.Text, Mono);
  Opt := DefaultHTMLOptions;
  Opt.NoWrap := True;
  Opt.Ellipsis := True;
  Opt.VertAlign := ivaCenter;
  if Measure then
    Exit(HTMLTextExtentOpt(C, Rect(0, 0, 100000, H), [], M, Opt).cx);
  if MaxX <= X then Exit(0);
  R := Rect(X, Y, MaxX, Y + H);
  HTMLDrawOpt(C, R, [], M, Opt);
  Result := Min(MaxX - X, HTMLTextExtentOpt(C, R, [], M, Opt).cx);
end;

{ The message rows: the message, wrapped to two lines by LazInk, then the
  keys that would do something now (out of sight when the message needs
  both lines). }
procedure TMainForm.PaintCmdMsg(C: TCanvas; const P: TCmdPalette);
var
  M, Tip: string;
  Opt: THTMLOptions;
begin
  if FCmdMsgR.Right <= FCmdMsgR.Left then Exit;
  M := '';
  if FCmdMsg <> '' then M := MarkMessage(FCmdMsg, P);
  Tip := '';
  if (FInput = '') and (ModifierTip <> '') then
  begin
    { dimmer than the message: plain words dim, keys still as keys }
    Tip := StringReplace(MarkMessage(ModifierTip, P), '<font color="' + P.Text + '">',
      '<font color="' + P.Dim + '">', [rfReplaceAll]);
    if M <> '' then M := M + '<br>' + Tip else M := Tip;
  end;
  if M = '' then Exit;
  UIFont(C, 11, False, Theme.Text);
  Opt := DefaultHTMLOptions;
  Opt.VertAlign := ivaTop;
  C.ClipRect := FCmdMsgR;
  C.Clipping := True;
  try
    HTMLDrawOpt(C, FCmdMsgR, [], M, Opt);
  finally
    C.Clipping := False;
  end;
end;

{ the bar's right-click: copy the message or the input, for bug reports }
procedure TMainForm.CmdMenuClick(Sender: TObject);
begin
  case (Sender as TMenuItem).Tag of
    1: if FCmdMsg <> '' then Clipboard.AsText := FCmdMsg;
    2: if FInput <> '' then Clipboard.AsText := FInput;
  end;
end;


{ ======================================================================== }
{ the screen                                                                }
{ ======================================================================== }

{ How much drawn ink a rectangle would hide, sampled every fourth pixel each
  way since it runs on every mouse move.  The ink surface, not the finished
  picture, so the paper grid does not count. }
function TMainForm.InkUnder(const R: TRect): Integer;
var
  X, Y, X0, X1, Y1: Integer;
  P: PPix;
  Ink: TArtSurface;
begin
  Result := 0;
  Ink := FInk;
  if Ink = nil then Exit;
  X0 := Max(0, R.Left);
  X1 := Min(R.Right, Ink.Width);
  Y1 := Min(R.Bottom, Ink.Height);
  Y := Max(0, R.Top);
  while Y < Y1 do
  begin
    P := Ink.ScanLine(Y);
    X := X0;
    while X < X1 do
    begin
      if (P + X)^.A > 8 then Inc(Result);
      Inc(X, 4);
    end;
    Inc(Y, 4);
  end;
end;

{ a dotted line the cursor is on, for the chip to keep off (see TipOnLine) }
procedure TMainForm.TipAvoid(X0, Y0, X1, Y1: Integer);
begin
  SetLength(FTipLines, Length(FTipLines) + 1);
  FTipLines[High(FTipLines)] := Rect(X0, Y0, X1, Y1);
end;

{ Dotted lines are drawn after the ink, so InkUnder cannot see them; a
  corner one crosses costs more than any amount of drawing. }
function TMainForm.TipOnLine(const R: TRect): Integer;
var
  K, N, I: Integer;
  X, Y: Double;
  Grown: TRect;
begin
  Result := 0;
  Grown := Rect(R.Left - 4, R.Top - 4, R.Right + 4, R.Bottom + 4);
  for K := 0 to High(FTipLines) do
  begin
    { walked a few pixels at a time; a chip is never thinner than that }
    N := Max(1, Max(Abs(FTipLines[K].Right - FTipLines[K].Left), Abs(FTipLines[K].Bottom - FTipLines[K].Top)) div 3);
    for I := 0 to N do
    begin
      X := FTipLines[K].Left + (FTipLines[K].Right - FTipLines[K].Left) * I / N;
      Y := FTipLines[K].Top + (FTipLines[K].Bottom - FTipLines[K].Top) * I / N;
      if (X >= Grown.Left) and (X <= Grown.Right) and (Y >= Grown.Top) and (Y <= Grown.Bottom) then
      begin
        Inc(Result, 100000);
        Break;
      end;
    end;
  end;
end;

{ Where to put the chip beside the cursor: the candidate corner covering
  least of the drawing.  Candidates are clamped inside the canvas before
  judging.  The current corner must be beaten by a clear margin, or it
  flips sides on every pixel when two are close. }
function TMainForm.TipSpot(SX, SY, BoxW, BoxH: Integer): TRect;
var
  K, Gap, AX, AY, Sc, Best, BestK, Cur: Integer;
  Cand: array[0..7] of TRect;
begin
  { Four corners close in, and the same four further out for when every near
    corner is crowded.  Near first and strictly better, so a far corner only
    wins by covering less. }
  for K := 0 to 7 do
  begin
    if K < 4 then Gap := Round(16 * FUIScale)
    else Gap := Round(96 * FUIScale);
    if (K and 1) = 0 then AX := SX + Gap else AX := SX - Gap - BoxW;
    if (K and 2) = 0 then AY := SY + Gap else AY := SY - Gap - BoxH;
    AX := EnsureRange(AX, 4, Max(4, pbScreen.Width - BoxW - 4));
    AY := EnsureRange(AY, 4, Max(4, pbScreen.Height - BoxH - 4));
    Cand[K] := Rect(AX, AY, AX + BoxW, AY + BoxH);
  end;

  FTipCorner := EnsureRange(FTipCorner, 0, 7);
  Cur := InkUnder(Cand[FTipCorner]) + TipOnLine(Cand[FTipCorner]);
  Best := Cur;
  BestK := FTipCorner;
  for K := 0 to 7 do
  begin
    if K = FTipCorner then Continue;
    Sc := InkUnder(Cand[K]) + TipOnLine(Cand[K]);
    if Sc < Best then
    begin
      Best := Sc;
      BestK := K;
    end;
  end;
  { a third less covered, and enough difference to be worth the jump }
  if (BestK <> FTipCorner) and (Best * 3 < Cur * 2) and (Cur - Best > 12) then
    FTipCorner := BestK;
  Result := Cand[FTipCorner];
end;

function TMainForm.SnapLabel: string;
const
  { named by color, like the axis inferences }
  AXIS_LABEL: array[0..2] of string =
    ('LOCKED TO RED', 'LOCKED TO GREEN', 'LOCKED TO BLUE');
begin
  if FAxisLock in [0..2] then Exit(AXIS_LABEL[FAxisLock]);
  { SketchUp's magenta pair, by its names }
  if FParPerp = 1 then Exit('PARALLEL TO EDGE');
  if FParPerp = 2 then Exit('PERPENDICULAR TO EDGE');
  case FSnapKind of
    snEndpoint: Result := 'ENDPOINT';
    snMidpoint: Result := 'MIDPOINT';
    snSubMid:   Result := 'ON SEGMENT';
    snCenter:   Result := 'CENTER';
    snCross:    Result := 'CROSSING';
    snOnEdge:   Result := 'ON EDGE';
    snOnFace:   Result := 'ON FACE';
    snQuadrant: Result := 'QUADRANT';
    snOrigin:   Result := 'ORIGIN';
    snOnAxis:   case FSnapAxis of
                  0: Result := 'ON RED AXIS';
                  1: Result := 'ON GREEN AXIS';
                else Result := 'ON BLUE AXIS';
                end;
    snGrid:     Result := 'GRID';
  else
    Result := '';
  end;
end;

{ The rectangle's far corner.  Typing 12'x8' sets both sides; the cursor
  still says which way each goes. }
function TMainForm.RectTarget: TP3;
var
  I: Integer;
  Txt, LW, LH: string;
  W, H, SX, SY: Double;
begin
  Result := FCur;
  if FStage <> 1 then Exit;

  Txt := LowerCase(Trim(FInput));
  I := Pos('x', Txt);
  if I = 0 then I := Pos(',', Txt);
  if I = 0 then Exit;

  { As SketchUp: "3'," sets the first side and leaves the second to the
    cursor, ",3'" the other way.  A negative side runs the opposite way. }
  LW := Trim(Copy(Txt, 1, I - 1));
  LH := Trim(Copy(Txt, I + 1, MaxInt));
  RectSides(FP1, FCur, FD.Plane, W, H);
  if (LW <> '') and not ParseLen(LW, FD.Units, W) then Exit;
  if (LH <> '') and not ParseLen(LH, FD.Units, H) then Exit;
  if (LW = '') and (LH = '') then Exit;

  { sign from where the cursor is now }
  case FD.Plane of
    plXZ:
      begin
        if FCur.X < FP1.X then SX := -1 else SX := 1;
        if FCur.Z < FP1.Z then SY := -1 else SY := 1;
        if W < 0 then begin SX := -SX; W := -W; end;
        if H < 0 then begin SY := -SY; H := -H; end;
        Result := P3(FP1.X + W * SX, FP1.Y, FP1.Z + H * SY);
      end;
    plYZ:
      begin
        if FCur.Y < FP1.Y then SX := -1 else SX := 1;
        if FCur.Z < FP1.Z then SY := -1 else SY := 1;
        if W < 0 then begin SX := -SX; W := -W; end;
        if H < 0 then begin SY := -SY; H := -H; end;
        Result := P3(FP1.X, FP1.Y + W * SX, FP1.Z + H * SY);
      end;
  else
    begin
      if FCur.X < FP1.X then SX := -1 else SX := 1;
      if FCur.Y < FP1.Y then SY := -1 else SY := 1;
      if W < 0 then begin SX := -SX; W := -W; end;
      if H < 0 then begin SY := -SY; H := -H; end;
      Result := P3(FP1.X + W * SX, FP1.Y + H * SY, FP1.Z);
    end;
  end;
end;

{ Where the rubber band ends: a typed distance wins, then a locked
  direction, then the cursor. }
function TMainForm.PreviewTarget: TP3;
var
  L, Len, CX, CY, CZ: Double;
  Typed: Boolean;
  D: TP3;
  Txt: string;
  K: Integer;
  AlongL: Double;
begin
  Result := FCur;
  if FStage <> 1 then Exit;

  { [x,y,z] is a point in the drawing, <x,y,z> an offset from the start }
  Txt := Trim(FInput);
  if (Length(Txt) >= 2) and (Txt[1] in ['[', '<']) then
  begin
    if ParseTriple(Txt, FD.Units, CX, CY, CZ) > 0 then
    begin
      if Txt[1] = '[' then Result := P3(CX, CY, CZ)
      else Result := P3(FP1.X + CX, FP1.Y + CY, FP1.Z + CZ);
    end;
    Exit;
  end;

  Typed := (FInput <> '') and ParseLen(FInput, FD.Units, L);

  if FDirLock >= 0 then
  begin
    D := AxisDir(FDirLock);
    if not Typed then
      { no number yet: slide along the locked axis under the cursor, either
        direction }
      L := (FCur.X - FP1.X) * D.X + (FCur.Y - FP1.Y) * D.Y + (FCur.Z - FP1.Z) * D.Z;
    Result := P3(FP1.X + D.X * L, FP1.Y + D.Y * L, FP1.Z + D.Z * L);
    Exit;
  end;

  { On the iso paper grid the line is held to the three axes; an off-axis
    leg there is a slip of the hand.  Shift releases it for a 45 or a rolling
    offset.  Not Alt: Alt cycles the working plane. }
  if (FD.View = vkIso) and (FTool = ptLine) and
     not (ssShift in FMoveShift) then
  begin
    K := IsoRunAxis(FP1, AlongL);
    if K >= 0 then
    begin
      D := AxisDir(K);
      if not Typed then L := AlongL;
      Result := P3(FP1.X + D.X * L, FP1.Y + D.Y * L, FP1.Z + D.Z * L);
      Exit;
    end;
  end;

  { Green means green: when the band is drawn in an axis color (within
    AxisAlong's tolerance, about a degree) the point is squared onto that
    axis, keeping its distance along.  Otherwise a line could show green and
    be an eighth out over a foot, and nested rectangles would not close. }
  if FParPerp = 0 then
  begin
    { the axis the band is drawn in, by the same test the painter uses: a
      lock the resolver set, or a run lying along one }
    if FAxisLock in [0..2] then K := FAxisLock
    else if FInferMode = imAll then K := AxisAlong(FP1, Result)
    else K := -1;
    if K >= 0 then
    begin
      { K is an axis (0 X, 1 Y, 2 Z) but AxisDir counts directions, two per
        axis }
      D := AxisDir(K * 2);
      AlongL := (Result.X - FP1.X) * D.X + (Result.Y - FP1.Y) * D.Y + (Result.Z - FP1.Z) * D.Z;
      Result := P3(FP1.X + D.X * AlongL, FP1.Y + D.Y * AlongL, FP1.Z + D.Z * AlongL);
      FAxisLock := K;
      FAxisFrom := FP1;
    end;
  end;

  if Typed then
  begin
    D := P3(FCur.X - FP1.X, FCur.Y - FP1.Y, FCur.Z - FP1.Z);
    Len := Sqrt(D.X * D.X + D.Y * D.Y + D.Z * D.Z);
    if Len < 1E-9 then
    begin
      D := P3(1, 0, 0);
      Len := 1;
    end;
    Result := P3(FP1.X + D.X * L / Len, FP1.Y + D.Y * L / Len, FP1.Z + D.Z * L / Len);
  end;
end;

{ The dimension as it will be (witness lines, slashes, reading), from the
  same routine the renderer uses, so what you drag is what you get. }
procedure TMainForm.PaintDimPreview(C: TCanvas);
var
  G: TDimGeom;
  Sz: TSize;
  TP: TPoint;
  RA, RB: TP3;
  RNote: string;
begin
  if FDimArc >= 0 then
  begin
    if not DimRadialAt(RA, RB, RNote) or
       not DimGeometry(Proj, RA, RB, P3(0, 0, 0), FD.Units, G, RNote) then Exit;
    PaintDimEnds(C, RA, RB);
  end
  else
  begin
    if not DimGeometry(Proj, FP1, FP2, DimOffset3, FD.Units, G) then Exit;
    PaintDimEnds(C, FP1, FP2);
  end;
  C.Pen.Style := psSolid;
  C.Pen.Color := PixToColor(AnnotColor);
  C.Pen.Width := 1;
  C.MoveTo(Round(G.A.X), Round(G.A.Y));   C.LineTo(Round(G.W1.X), Round(G.W1.Y));
  C.MoveTo(Round(G.B.X), Round(G.B.Y));   C.LineTo(Round(G.W2.X), Round(G.W2.Y));
  C.Pen.Width := Max(1, Round(1.5 * FUIScale));
  C.MoveTo(Round(G.LA.X), Round(G.LA.Y));  C.LineTo(Round(G.LB.X), Round(G.LB.Y));
  C.MoveTo(Round(G.S1A.X), Round(G.S1A.Y)); C.LineTo(Round(G.S1B.X), Round(G.S1B.Y));
  C.MoveTo(Round(G.S2A.X), Round(G.S2A.Y)); C.LineTo(Round(G.S2B.X), Round(G.S2B.Y));
  C.Pen.Width := 1;
  C.Brush.Style := bsClear;
  UIFont(C, 9, False, AnnotColor);
  Sz := C.TextExtent(G.Txt);
  TP := DimTextTopLeft(G, Sz.cx, Sz.cy);
  C.TextOut(TP.X, TP.Y, G.Txt);
end;

{ The two points a dimension measures, as dots, so it is clear where it
  starts and stops (a face may be split into pieces). }
procedure TMainForm.PaintDimEnds(C: TCanvas; const A, B: TP3);
var
  P: TPointF;
  R, K: Integer;
begin
  R := Max(3, Round(4 * FUIScale));
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.Pen.Color := PixToColor(Theme.Screen1);
  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(HINT_BLUE);
  for K := 0 to 1 do
  begin
    if K = 0 then P := ScreenOf(A) else P := ScreenOf(B);
    C.Ellipse(Round(P.X) - R, Round(P.Y) - R, Round(P.X) + R + 1, Round(P.Y) + R + 1);
  end;
  C.Brush.Style := bsClear;
end;

{ what it will read, beside what it will measure, before the click }
procedure TMainForm.PaintDimTag(C: TCanvas; X, Y: Double; const S: string);
var
  Sz: TSize;
begin
  UIFont(C, 10, True, HINT_BLUE);
  Sz := C.TextExtent(S);
  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(Theme.Screen1);
  C.TextOut(Round(X - Sz.cx / 2), Round(Y - Sz.cy / 2), S);
  C.Brush.Style := bsClear;
end;

{ A point along a bent stick: the quadratic through A, the bowed middle M,
  and B.  Straight when M is halfway, which is what makes the bow read. }
function QuadAt(const A, M, B: TPointF; T: Double): TPointF;
var
  U: Double;
begin
  U := 1 - T;
  Result.X := U * U * A.X + 2 * U * T * M.X + T * T * B.X;
  Result.Y := U * U * A.Y + 2 * U * T * M.Y + T * T * B.Y;
end;

{ Is there a newer build?  Quiet unless there is, and at most every six
  hours; a drawing program should not ping a server on every launch. }
procedure TMainForm.CheckForUpdate(Loud: Boolean);
var
  Info: TUpdateInfo;
  Err, Last: string;
  Ini: TIniFile;
begin
  if not Loud then
  begin
    Ini := TIniFile.Create(ConfigFile);
    try
      { /update never turns this off for good.  It only asks GitHub for the
        newest release and sends nothing about the machine or the drawing. }
      if not Ini.ReadBool('update', 'check', True) then Exit;
      Last := Ini.ReadString('update', 'checked', '');
    finally
      Ini.Free;
    end;
    { six hours, not a calendar day, so a day of releases is not missed }
    if (Last <> '') and (Now - StrToFloatDef(Last, 0) < 0.25) then Exit;
  end;

  if not FetchLatest(Info, Err) then
  begin
    if Loud then FCmdMsg := 'Could not check for an update - ' + Err;
    Exit;
  end;

  Ini := TIniFile.Create(ConfigFile);
  try
    Ini.WriteString('update', 'checked', FloatToStr(Now));
    Ini.WriteString('update', 'latest', Info.Tag);
  finally
    Ini.Free;
  end;

  if NewerThan(Info.Tag, CurrentVersion) then
  begin
    FUpdateTag := Info.Tag;
    FCmdMsg := Info.Tag + ' is out - you have ' + CurrentVersion +
      '.  Type /update, or use the help button.';
    Invalidate;
    { Found at startup: offer it now, as /update would.  Not where this copy
      cannot update itself, not for a source build, and not twice for a
      declined version (that waits for /update). }
    if (not Loud) and (WhyNotUpdate = '') and (Pos('dev', LowerCase(CurrentVersion)) = 0) then
    begin
      Ini := TIniFile.Create(ConfigFile);
      try
        Last := Ini.ReadString('update', 'declined', '');
        if Last <> Info.Tag then Ini.WriteString('update', 'declined', Info.Tag);
      finally
        Ini.Free;
      end;
      if Last <> Info.Tag then
      begin
        pbCmd.Invalidate;
        DoUpdate;
        Exit;
      end;
    end;
  end
  else
  begin
    FUpdateTag := '';
    if Loud then FCmdMsg := 'Up to date - ' + CurrentVersion + '.';
  end;
  pbCmd.Invalidate;
end;

{ 3x, x3, *3: three copies at the spacing of the one just made.  /3, 3/:
  the run divided into three. }
function TMainForm.ArrayCommand(const S: string; out N: Integer; out Divide: Boolean): Boolean;
var
  T: string;
begin
  Result := False;
  N := 0;
  Divide := False;
  T := LowerCase(Trim(S));
  if Length(T) < 2 then Exit;
  if T[1] in ['x', '*', '/'] then
  begin
    Divide := T[1] = '/';
    Delete(T, 1, 1);
  end
  else if T[Length(T)] in ['x', '*', '/'] then
  begin
    Divide := T[Length(T)] = '/';
    Delete(T, Length(T), 1);
  end
  else
    Exit;
  Result := TryStrToInt(Trim(T), N) and (N >= 2) and (N <= 500);
end;

{ Make the copy just placed into N.  Earlier copies are taken back first so
  a new count replaces the old; they are the last entities, so that means
  deleting from the end. }
procedure TMainForm.ApplyArray(N: Integer; Divide: Boolean);
var
  I: Integer;
begin
  if not FArray.Live then Exit;
  PushUndo;
  for I := High(FArray.Made) downto 0 do
    FD.Doc.Delete(FArray.Made[I]);
  if FArray.Rotate then
    FD.Doc.ArrayRotate(FArray.Src, FArray.C, FArray.Axis, FArray.Ang, N, Divide, FArray.Made)
  else
    FD.Doc.ArrayMove(FArray.Src, FArray.D, N, Divide, FArray.Made);
  SelectNone;
  for I := 0 to High(FArray.Made) do SelectAdd(FArray.Made[I]);
  SeedRegions;
  RenderInk;
  RecomposeAll;
  if Divide then
    FCmdMsg := Format('Divided into %d.  Another count replaces it.', [N])
  else
    FCmdMsg := Format('%d copies.  Another count replaces it.', [N]);
  pbScreen.Invalidate;
  pbCmd.Invalidate;
end;

{ /timings: how long the steps of an edit took }
procedure TMainForm.Took(const What: string; T0: QWord);
begin
  if not FTimings then Exit;
  TimingLine(Format('took %d ms: %s', [GetTickCount64 - T0, What]));
end;

{ One line of /timings: to the console where there is one, and kept for the
  box since Windows has none.  The oldest drop off once it is long. }
procedure TMainForm.TimingLine(const S: string);
const
  KEEP = 400;
var
  N: Integer;
begin
  WriteLn(S);
  Flush(Output);
  N := Length(FTimingLog);
  if N >= KEEP then
  begin
    FTimingLog := Copy(FTimingLog, N - KEEP div 2, MaxInt);
    N := Length(FTimingLog);
  end;
  SetLength(FTimingLog, N + 1);
  FTimingLog[N] := FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + S;
end;

procedure TMainForm.ShowTimingLog;
var
  I: Integer;
  T: string;
begin
  if Length(FTimingLog) = 0 then
  begin
    FCmdMsg := 'No timings collected yet - /timings, do something, then /timings again.';
    Exit;
  end;
  T := '';
  for I := 0 to High(FTimingLog) do T := T + FTimingLog[I] + LineEnding;
  ShowLongText('Step timings, oldest first', T);
end;

procedure TMainForm.RenderTiming;
var
  T0: QWord;
  I, N: Integer;
  Ms, Ov, Qk, Bl, Gd: Double;
  Ph: array[0..5] of Double;
  WasMoving: Boolean;
  Box: string;
begin
  N := 10;
  for I := 0 to 5 do FD.Doc.ProfMs[I] := 0;
  { a whole frame as an orbit makes one: paper, drawing, composite }
  T0 := GetTickCount64;
  for I := 1 to N do
  begin
    FScreenDirty := True;
    RepaintPaper;
    RenderInk;
    RecomposeAll;
  end;
  Ms := (GetTickCount64 - T0) / N;
  for I := 0 to 5 do Ph[I] := FD.Doc.ProfMs[I] / N;
  { the same frame the quick way, as an orbit in progress draws it }
  WasMoving := FCameraMoving;
  FCameraMoving := FQuickFrames;
  T0 := GetTickCount64;
  for I := 1 to N do
  begin
    FScreenDirty := True;
    RepaintPaper;
    RenderInk;
    RecomposeAll;
  end;
  Qk := (GetTickCount64 - T0) / N;
  FCameraMoving := WasMoving;
  RepaintPaper; RenderInk; RecomposeAll;
  { and the overlay on top, the selection outlines above all }
  T0 := GetTickCount64;
  for I := 1 to N do pbScreen.Repaint;
  Ov := (GetTickCount64 - T0) / N;
  { The blit alone, apart from the overlay drawing, to tell which half of
    the paint handler the time belongs to. }
  T0 := GetTickCount64;
  for I := 1 to N do FArt.DrawTo(pbScreen.Canvas, FJitterX, FJitterY);
  Bl := (GetTickCount64 - T0) / N;
  { and the guides, rubber band and readouts on their own }
  Gd := 0;
  T0 := GetTickCount64;
  for I := 1 to N do PaintOverlay(pbScreen.Canvas);
  Gd := (GetTickCount64 - T0) / N;
  FCmdMsg := Format('A frame takes %.0f ms (%d things: %d faces).  index and edges %.0f, faces sorted and painted %.0f, lines on faces %.0f, the rest %.0f',
    [Ms, FD.Doc.Live, FaceCount + SolidFaceCount, Ph[0], Ph[1] + Ph[2], Ph[3], Ph[4]]);
  FCmdMsg := FCmdMsg + Format('; quick frame %.0f ms; overlay %.0f ms (blit %.0f, guides %.0f) with %d selected',
    [Qk, Ov, Bl, Gd, Length(FSel)]);
  { too long for the bar, so the whole thing goes in a copyable box }
  Box := Format(
    'A whole frame (paper, drawing, composite):  %.1f ms' + LineEnding +
    '  things on the sheet:                     %d  (%d faces)' + LineEnding +
    '  index and edges:                         %.1f ms' + LineEnding +
    '  faces sorted and painted:                %.1f ms' + LineEnding +
    '  lines on faces:                          %.1f ms' + LineEnding +
    '  the rest:                                %.1f ms' + LineEnding +
    'A quick frame, as an orbit draws it:       %.1f ms' + LineEnding +
    'The paint on top:                          %.1f ms' + LineEnding +
    '  the picture onto the window:             %.1f ms' + LineEnding +
    '  guides, rubber band and readouts:        %.1f ms' + LineEnding +
    '  with this many picked:                   %d' + LineEnding + LineEnding +
    'Lines-on-faces cache: built %d times, threads %s, last build %.0f ms on %s,' + LineEnding +
    '  taken %.0f ms after it was done; frames that went without it: %d' + LineEnding +
    '  (%.0f ms on the last), discarded %d, failed %d' + LineEnding + LineEnding +
    'Window %dx%d at %.2f scaling, zoom %.3f, view %s.  Each figure is the average of %d.',
    [Ms, FD.Doc.Live, FaceCount + SolidFaceCount, Ph[0], Ph[1] + Ph[2], Ph[3], Ph[4],
     Qk, Ov, Bl, Gd, Length(FSel),
     FD.Doc.OnFaceBuilds, BoolToStr(FD.Doc.Threads, 'on', 'off'),
     FD.Doc.OnFaceWorkerMs, FD.Doc.OnFaceBuiltOn, FD.Doc.OnFaceLagMs,
     FD.Doc.OnFaceFallbacks, FD.Doc.OnFaceFallbackMs,
     FD.Doc.OnFaceDiscarded, FD.Doc.OnFaceFailed,
     pbScreen.Width, pbScreen.Height, FUIScale, FD.Zoom, VIEW_NAMES[FD.View], N]);
  WriteLn('rendertime ', Ms:0:1, ' ms/frame (paper+render+composite), ', FD.Doc.Live, ' things; index+edges ',
    Ph[0]:0:1, ' faces ', (Ph[1] + Ph[2]):0:1, ' lines-on-faces ',
    Ph[3]:0:1, ' rest ', Ph[4]:0:1, '; quick frame ', Qk:0:1, '; overlay ', Ov:0:1, ' ms of which blit ', Bl:0:1, ' guides ', Gd:0:1, ', with ', Length(FSel), ' selected; onface builds so far ', FD.Doc.OnFaceBuilds,
    '; threads ', FD.Doc.Threads, ' last cache build ', FD.Doc.OnFaceWorkerMs:0:0, ' ms on ', FD.Doc.OnFaceBuiltOn, ', taken ', FD.Doc.OnFaceLagMs:0:0, ' ms after done; a frame without the cache spent ', FD.Doc.OnFaceFallbackMs:0:0, ' ms on lines-on-faces; frames without cache ',
    FD.Doc.OnFaceFallbacks, ', discarded ', FD.Doc.OnFaceDiscarded, ', failed ', FD.Doc.OnFaceFailed);
  Flush(Output);
  Trail(FCmdMsg);
  FCmdMsg := Format('A frame takes %.0f ms - the rest is in the box.', [Ms]);
  pbCmd.Invalidate;
  ShowLongText('How long a frame takes', Box);
end;

{ the normal of an arc's plane }
function TMainForm.ArcNormal(I: Integer): TP3;
var
  AU, AV: TP3;
begin
  if FD.Doc[I].Plane = plFree then Result := Norm3(FD.Doc[I].Nm)
  else
  begin
    PlaneAxes(FD.Doc[I].Plane, AU, AV);
    Result := Norm3(Cross3(AU, AV));
  end;
end;

{ Is this line one of the outline's own sides: both ends are corners of the
  outline, next to each other round it? }
function TMainForm.IsProfileEdge(I: Integer): Boolean;
const
  TOL = 1E-6;
var
  K, N, A, B: Integer;
begin
  Result := False;
  if (I < 0) or (I >= FD.Doc.Live) or (FD.Doc[I].Kind <> ekLine) then Exit;
  if (FFollowFace < 0) or (FFollowFace >= FD.Doc.Live) then Exit;
  if FD.Doc[FFollowFace].Kind <> ekFace then Exit;
  N := Length(FD.Doc[FFollowFace].Poly);
  A := -1;
  B := -1;
  for K := 0 to N - 1 do
  begin
    if Dist(FD.Doc[FFollowFace].Poly[K], FD.Doc[I].A) < TOL then A := K;
    if Dist(FD.Doc[FFollowFace].Poly[K], FD.Doc[I].B) < TOL then B := K;
  end;
  if (A < 0) or (B < 0) then Exit;
  Result := (Abs(A - B) = 1) or (Abs(A - B) = N - 1);
end;

function TMainForm.AxisSplitsProfile(const AxisP, AxisDir: TP3;
  out RLo, RHi: Double): Boolean;
begin
  Result := FD.Doc.AxisSplitsFace(FFollowFace, AxisP, AxisDir, RLo, RHi);
end;

procedure TMainForm.PaintRevolvePreview(C: TCanvas);
const
  RING_N = 48;
var
  D, AP, Q: TP3;
  RLo, RHi, L: Double;
  Bad: Boolean;
  K, N: Integer;
  Col: TPix;
  U, W, Nf: TP3;
  PA, PB: TPointF;

  procedure Circle(R: Double);
  var
    J: Integer;
    A: Double;
    P0, P1: TPointF;
  begin
    if R < 1E-9 then Exit;
    P0 := ScreenOf(P3(AP.X + U.X * R, AP.Y + U.Y * R, AP.Z + U.Z * R));
    for J := 1 to RING_N do
    begin
      A := 2 * Pi * J / RING_N;
      P1 := ScreenOf(P3(AP.X + (U.X * Cos(A) + W.X * Sin(A)) * R,
                        AP.Y + (U.Y * Cos(A) + W.Y * Sin(A)) * R,
                        AP.Z + (U.Z * Cos(A) + W.Z * Sin(A)) * R));
      C.Line(Round(P0.X), Round(P0.Y), Round(P1.X), Round(P1.Y));
      P0 := P1;
    end;
  end;

begin
  D := P3(FCur.X - FAxisA.X, FCur.Y - FAxisA.Y, FCur.Z - FAxisA.Z);
  L := Dist(D, P3(0, 0, 0));
  if L < 1E-9 then Exit;
  D := P3(D.X / L, D.Y / L, D.Z / L);
  Bad := AxisSplitsProfile(FAxisA, D, RLo, RHi);

  if Bad then Col := Pix(220, 60, 60) else Col := Theme.Accent;
  C.Pen.Color := PixToColor(Col);
  C.Pen.Width := Max(1, Round(2 * FUIScale));
  C.Brush.Style := bsClear;

  { the axis, run well past both ends: the shape turns about the whole line }
  N := Round(Max(RHi * 3, L * 2));
  PA := ScreenOf(P3(FAxisA.X - D.X * N, FAxisA.Y - D.Y * N, FAxisA.Z - D.Z * N));
  PB := ScreenOf(P3(FAxisA.X + D.X * N, FAxisA.Y + D.Y * N, FAxisA.Z + D.Z * N));
  C.Line(Round(PA.X), Round(PA.Y), Round(PB.X), Round(PB.Y));

  { the rings the outline's nearest and furthest corners sweep, about the
    axis at the outline's middle }
  Nf := Norm3(FD.Doc.FaceNormal(FFollowFace));
  U := Norm3(Cross3(D, Nf));
  W := Norm3(Cross3(D, U));
  Q := P3(0, 0, 0);
  N := Length(FD.Doc[FFollowFace].Poly);
  if N = 0 then Exit;
  for K := 0 to N - 1 do
    Q := P3(Q.X + FD.Doc[FFollowFace].Poly[K].X / N,
            Q.Y + FD.Doc[FFollowFace].Poly[K].Y / N,
            Q.Z + FD.Doc[FFollowFace].Poly[K].Z / N);
  { the middle of the outline, brought onto the axis }
  Q := P3(Q.X - FAxisA.X, Q.Y - FAxisA.Y, Q.Z - FAxisA.Z);
  AP := P3(FAxisA.X + D.X * Dot3(Q, D), FAxisA.Y + D.Y * Dot3(Q, D),
           FAxisA.Z + D.Z * Dot3(Q, D));
  C.Pen.Width := 1;
  Circle(RHi);
  Circle(RLo);
end;

{ Follow Me round an axis: the typed angle in degrees, or a full turn.  The
  gore count scales with the circle side count, so a quarter turn gets a
  quarter of them. }
procedure TMainForm.DoRevolve(const AxisP, AxisDir: TP3; PathArc: Integer);
var
  Deg, Ang: Double;
  Steps, First, Made: Integer;
var
  RLo, RHi: Double;
  Split: Boolean;
begin
  Ang := 2 * Pi;
  if (FInput <> '') and TryStrToFloat(Trim(FInput), Deg) and (Deg <> 0) then
    Ang := DegToRad(Deg);
  Steps := Max(1, Round(FSidesCircle * Abs(Ang) / (2 * Pi)));
  { Checked before acting: an axis through the middle of the outline sweeps
    the two halves into each other, a knot with no outside. }
  Split := AxisSplitsProfile(AxisP, AxisDir, RLo, RHi);
  if Split then
  begin
    FCmdMsg := 'The axis runs through the middle of the outline, so the two ' +
      'halves would sweep into each other.  A glass is spun about a line ' +
      'down one side of its outline, not through it.  Nothing done - move ' +
      'the axis to the edge and click again.';
    Exit;
  end;
  PushUndo;
  Made := FD.Doc.Live;
  First := FD.Doc.Revolve(FFollowFace, AxisP, AxisDir, Ang, Steps);
  if First < 0 then
  begin
    FCmdMsg := 'That could not be spun - it needs a face and an axis of some length.';
    Exit;
  end;
  Made := FD.Doc.Live - Made;
  { the circle that was followed lies on the new surface: make it a soft
    seam of the solid, not a hard ring }
  if (PathArc >= 0) and (PathArc < FD.Doc.Live) and (First < FD.Doc.Live) then
  begin
    FD.Doc.SetSoft(PathArc, True);
    FD.Doc.SetGroup(PathArc, FD.Doc[First].Grp);
  end;
  SeedRegions;
  SelectNone;
  RenderInk;
  RecomposeAll;
  FCmdMsg := Format('Spun %s in %d gores, %s to %s across.',
    [FormatAngle(RadToDeg(Ang)), Steps,
     FormatLen(RLo * 2, FD.Units), FormatLen(RHi * 2, FD.Units)]);
  if Made > 0 then ;
  ResetTool;
  FInput := '';
end;

{ The chain through edge I, followed each way while there is exactly one
  edge to follow.  Points come back in order end to end, or round to the
  start when it closes. }
function TMainForm.ChainFrom(I: Integer; out Closed: Boolean): TP3Array;
var
  Used: array of Boolean;
  Pts, More: TP3Array;
  J, K, Found, Guard: Integer;
  Tail: TP3;
  Fwd: Boolean;

  function Tip(J: Integer; AtA: Boolean): TP3;
  begin
    if AtA then Result := FD.Doc[J].A else Result := FD.Doc[J].B;
  end;

  { the one unused edge with an end at P, or -1 when none or several }
  function NextAt(const P: TP3; out AtA: Boolean): Integer;
  var
    E, Count: Integer;
  begin
    Result := -1;
    Count := 0;
    AtA := True;
    for E := 0 to FD.Doc.Live - 1 do
      if (not Used[E]) and (FD.Doc[E].Kind in [ekLine, ekArc]) then
      begin
        if Dist(FD.Doc[E].A, P) < 1E-6 then begin Inc(Count); Result := E; AtA := True; end
        else if Dist(FD.Doc[E].B, P) < 1E-6 then begin Inc(Count); Result := E; AtA := False; end;
      end;
    if Count <> 1 then Result := -1;
  end;

  procedure Append(var L: TP3Array; const P: TP3Array; Reverse: Boolean);
  var
    Q: Integer;
  begin
    for Q := 0 to High(P) do
    begin
      if Reverse then K := High(P) - Q else K := Q;
      if (Length(L) > 0) and (Dist(L[High(L)], P[K]) < 1E-9) then Continue;
      SetLength(L, Length(L) + 1);
      L[High(L)] := P[K];
    end;
  end;

begin
  Result := nil;
  Closed := False;
  SetLength(Used, FD.Doc.Live);
  Used[I] := True;
  FD.Doc.EdgePoints(I, Pts);
  if Length(Pts) < 2 then Exit;
  { forward from the end of I }
  Guard := 0;
  repeat
    Tail := Pts[High(Pts)];
    if Dist(Tail, Pts[0]) < 1E-6 then
    begin
      Closed := True;
      Break;
    end;
    Found := NextAt(Tail, Fwd);
    if Found < 0 then Break;
    Used[Found] := True;
    FD.Doc.EdgePoints(Found, More);
    Append(Pts, More, not Fwd);
    Inc(Guard);
  until Guard > 10000;
  if not Closed then
  begin
    { and backward from the start of I }
    Guard := 0;
    repeat
      Found := NextAt(Pts[0], Fwd);
      if Found < 0 then Break;
      Used[Found] := True;
      FD.Doc.EdgePoints(Found, More);
      { reverse the chain, append, reverse back }
      for J := 0 to High(Pts) div 2 do
      begin
        Tail := Pts[J]; Pts[J] := Pts[High(Pts) - J]; Pts[High(Pts) - J] := Tail;
      end;
      Append(Pts, More, not Fwd);
      for J := 0 to High(Pts) div 2 do
      begin
        Tail := Pts[J]; Pts[J] := Pts[High(Pts) - J]; Pts[High(Pts) - J] := Tail;
      end;
      if Dist(Pts[0], Pts[High(Pts)]) < 1E-6 then
      begin
        Closed := True;
        Break;
      end;
      Inc(Guard);
    until Guard > 10000;
  end;
  Result := Pts;
end;

{ Follow Me along a path.  The profile rides from whichever end is nearer,
  so the path can be drawn either way. }
procedure TMainForm.DoSweep(const Path: TP3Array; Closed: Boolean);
var
  P: TP3Array;
  Cen: TP3;
  I, First: Integer;
  DA, DB: Double;
begin
  if Length(Path) < 2 then
  begin
    FCmdMsg := 'That path has nothing to follow.';
    Exit;
  end;
  P := Copy(Path);
  if not Closed then
  begin
    Cen := P3(0, 0, 0);
    for I := 0 to High(FD.Doc[FFollowFace].Poly) do
      Cen := P3(Cen.X + FD.Doc[FFollowFace].Poly[I].X / Length(FD.Doc[FFollowFace].Poly),
                Cen.Y + FD.Doc[FFollowFace].Poly[I].Y / Length(FD.Doc[FFollowFace].Poly),
                Cen.Z + FD.Doc[FFollowFace].Poly[I].Z / Length(FD.Doc[FFollowFace].Poly));
    DA := Dist(Cen, P[0]);
    DB := Dist(Cen, P[High(P)]);
    if DB < DA then
      for I := 0 to High(P) div 2 do
      begin
        Cen := P[I]; P[I] := P[High(P) - I]; P[High(P) - I] := Cen;
      end;
  end;
  PushUndo;
  First := FD.Doc.Sweep(FFollowFace, P, Closed);
  if First < 0 then
  begin
    FCmdMsg := 'That could not be followed - it needs a face and a path of some length.';
    Exit;
  end;
  SeedRegions;
  SelectNone;
  RenderInk;
  RecomposeAll;
  if Closed then FCmdMsg := 'Followed the path all the way round.'
  else FCmdMsg := Format('Followed the path, %d legs.', [Length(P) - 1]);
  ResetTool;
  FInput := '';
end;

{ The pipe fitter's iso: the spool as legs with lengths, built as one solid
  and placed like a fitting. }
procedure TMainForm.BuildSpoolWizard;
var
  Spec: TSpoolSpec;
  First: Integer;
begin
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  if not TSpoolForm.Ask(FD.Units, Spec) then Exit;
  if FD.View = vkPlan then EnterFreeCamera(True);
  PushUndo;
  First := BuildSpool(FD.Doc, Spec, FInkColor, FEdgeW);
  if First < 0 then
  begin
    FCmdMsg := 'The spool could not be built.';
    Exit;
  end;
  SeedRegions;
  RenderInk;
  RecomposeAll;
  PlaceBuilt(First, P3(0, 0, 0));
end;

procedure TMainForm.BuildTransitionWizard;
var
  Spec: TTransitionSpec;
  First: Integer;
begin
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  if not TTransitionForm.Ask(FD.Units, Spec) then Exit;
  if FD.View = vkPlan then EnterFreeCamera(True);
  PushUndo;
  First := BuildFitting(FD.Doc, Spec, FInkColor, FEdgeW);
  SeedRegions;
  RenderInk;
  RecomposeAll;
  PlaceBuilt(First, P3(0, 0, 0));
end;

{ Stairs.  Two lines picked: the flight stands on them (lower where the
  first riser stands, upper at the landing edge).  A stair group picked:
  the dialog opens on what it remembers and changes it in place.  Otherwise
  sizes are typed, or three points picked from the dialog, and the flight is
  built in place or follows the pointer to be placed. }
procedure TMainForm.BuildStairWizard;
var
  A, B: TWorkEnt;
  G: Integer;
begin
  FStairJob := Default(TStairJob);
  FStairJob.Mode := smFree;
  FStairEdit := 0;
  G := SoleGroup;
  if (G > 0) and IsStairJig(FD.Doc.PartJig(G)) and
     StairFromJig(FD.Doc.PartJig(G), FD.Units, FStairJob.Frame, FStairJob.Spec, FStairJob.Use) then
  begin
    FStairJob.Frame.Bottom := StairWhereNow(G, FStairJob.Frame, FStairJob.Spec);
    FStairJob.Mode := smPlaced;
    FStairJob.HaveSpec := True;
    FStairJob.Editing := True;
    FStairJob.Note := 'The flight picked, as it was built.';
    FStairEdit := G;
  end
  else if Length(FSel) = 2 then
  begin
    A := FD.Doc[FSel[0]]; B := FD.Doc[FSel[1]];
    if (A.Kind = ekLine) and (B.Kind = ekLine) then
    begin
      FStairJob.Mode := smLines;
      FStairJob.LA := A.A; FStairJob.LB := A.B; FStairJob.HA := B.A; FStairJob.HB := B.B;
    end;
  end;
  StairDialog;
end;

{ Where a stair group's flight stands now: its jig line's position, shifted
  by however far the group's boards have moved since (compared with a fresh
  build's box).  Rotation by hand is not followed. }
function TMainForm.StairWhereNow(G: Integer; const F: TStairFrame; const S: TStairSpec): TP3;
var
  T: TWorkDoc;
  M: TIntArrayW;
  I, J: Integer;
  Lo1, Hi1, Lo2, Hi2: TP3;

  procedure Grow(const P: TP3; var Lo, Hi: TP3);
  begin
    Lo := P3(Min(Lo.X, P.X), Min(Lo.Y, P.Y), Min(Lo.Z, P.Z));
    Hi := P3(Max(Hi.X, P.X), Max(Hi.Y, P.Y), Max(Hi.Z, P.Z));
  end;

begin
  Result := F.Bottom;
  Lo1 := P3(1E300, 1E300, 1E300); Hi1 := P3(-1E300, -1E300, -1E300);
  Lo2 := Lo1; Hi2 := Hi1;
  M := FD.Doc.PartMembers(G, False);
  for I := 0 to High(M) do
    if FD.Doc[M[I]].Kind = ekFace then
      for J := 0 to High(FD.Doc[M[I]].Poly) do Grow(FD.Doc[M[I]].Poly[J], Lo1, Hi1);
  T := TWorkDoc.Create;
  try
    try
      BuildStairs(T, F, S, clBlack, 1);
    except
      Exit;
    end;
    for I := 0 to T.Live - 1 do
      if T[I].Kind = ekFace then
        for J := 0 to High(T[I].Poly) do Grow(T[I].Poly[J], Lo2, Hi2);
  finally
    T.Free;
  end;
  if (Lo1.X > Hi1.X) or (Lo2.X > Hi2.X) then Exit;
  { same flight elsewhere means the same size box }
  if (Abs((Hi1.X - Lo1.X) - (Hi2.X - Lo2.X)) > 1E-4) or (Abs((Hi1.Y - Lo1.Y) - (Hi2.Y - Lo2.Y)) > 1E-4) or
     (Abs((Hi1.Z - Lo1.Z) - (Hi2.Z - Lo2.Z)) > 1E-4) then Exit;
  Result := P3(F.Bottom.X + Lo1.X - Lo2.X, F.Bottom.Y + Lo1.Y - Lo2.Y, F.Bottom.Z + Lo1.Z - Lo2.Z);
end;

{ Empty stair group G (keeping its own record) and rebuild the flight into
  it from F and S, updating its jig line.  The caller owns the undo step. }
procedure TMainForm.StairRebuild(G: Integer; const F: TStairFrame; const S: TStairSpec; Use: TStairUse);
var
  M: TIntArrayW;
  Doomed: array of Boolean;
  I, Rec: Integer;
begin
  LeaveSheet;
  ResetTool;
  M := FD.Doc.PartMembers(G, False);
  Rec := FD.Doc.PartEnt(G);
  SetLength(Doomed, FD.Doc.Live);
  for I := 0 to High(Doomed) do Doomed[I] := False;
  for I := 0 to High(M) do
    if M[I] <> Rec then Doomed[M[I]] := True;
  FD.Doc.DeleteMarked(Doomed);
  BuildStairs(FD.Doc, F, S, FInkColor, FEdgeW, G, StairJig(F, S, Use));
  FD.Dirty := True;
end;

{ the stair dialog on FStairJob, and what it closed for: build, or pick
  points on the sheet }
procedure TMainForm.StairDialog;
var
  First, I: Integer;
begin
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  case TStairForm.Ask(FD.Units, FStairJob) of
    saCancel: Exit;
    saPick:
      begin
        FStairPick := 1;
        ResetTool;
        FCmdMsg := 'Stairs: click the TOP - the landing''s edge, at its height.  Esc goes back to the stairs.';
        pbScreen.Invalidate; pbCmd.Invalidate;
        Exit;
      end;
  end;
  PushUndo;
  with FStairJob do
  begin
    if FStairEdit > 0 then
    begin
      StairRebuild(FStairEdit, Frame, Spec, Use);
      { selected again, as before the change }
      SelectNone;
      for I := 0 to High(FD.Doc.PartMembers(FStairEdit, False)) do
        SelectAdd(FD.Doc.PartMembers(FStairEdit, False)[I]);
      FCmdMsg := 'The stairs are built again.';
    end
    else
    begin
      First := BuildStairs(FD.Doc, Frame, Spec, FInkColor, FEdgeW, 0, StairJig(Frame, Spec, Use));
      FCmdMsg := Format('Built stairs: %d risers of %s, %d treads of %s.',
        [Spec.Risers, StairLen(Frame.Rise / Spec.Risers, FD.Units), Spec.Risers - 1,
         StairLen(Frame.Run / (Spec.Risers - 1), FD.Units)]);
      if Mode = smFree then
      begin
        SeedRegions;
        RenderInk; RecomposeAll;
        { held by the foot of the first riser, to be clicked into place }
        PlaceBuilt(First, P3(0, 0, 0));
        FCmdMsg := FCmdMsg + '  Click to place it.';
        pbScreen.Invalidate; pbCmd.Invalidate;
        Exit;
      end;
      SelectNone;
      for I := First to FD.Doc.Live - 1 do SelectAdd(I);
    end;
  end;
  SeedRegions;
  RebuildFlatFaces;
  RenderInk; RecomposeAll;
  pbScreen.Invalidate; pbCmd.Invalidate;
end;

{ The flight from the two picked points and a third (the side the width
  goes).  The top is picked first, but whichever point is lower is the
  bottom.  Picked level (in plan), the second is the bottom and the rise is
  the typed one. }
function TMainForm.StairPickFrame(const Third: TP3; out F: TStairFrame; out Why: string): Boolean;
var
  Hi, Lo: TP3;
begin
  Hi := FStairPts[0]; Lo := FStairPts[1];
  if Hi.Z < Lo.Z - 1E-6 then begin Hi := FStairPts[1]; Lo := FStairPts[0]; end;
  Result := StairFramePicked(Lo, Hi, Third, F, Why);
  if not Result then Exit;
  if F.Rise <= 1E-6 then F.Rise := FStairJob.Frame.Rise;
  if F.Width <= 1E-6 then F.Width := FStairJob.Frame.Width;
end;

{ A point picked for the stairs (the snapped cursor).  After the third, the
  dialog reopens on them. }
procedure TMainForm.StairTakePoint(const P: TP3);
var
  F: TStairFrame;
  Why: string;
  S: TStairSpec;
begin
  FStairPts[FStairPick - 1] := P;
  Inc(FStairPick);
  case FStairPick of
    2: FCmdMsg := 'Stairs: now the BOTTOM - where the first riser stands - or type the run.  Esc goes back.';
    3: FCmdMsg := 'Stairs: and the SIDE - click as far out as the stairs are wide, or type the width.  Esc goes back.';
  else
    FStairPick := 0;
    if StairPickFrame(FStairPts[2], F, Why) then
    begin
      if Abs(FStairPts[0].Z - FStairPts[1].Z) <= 1E-6 then
        FStairJob.Note := 'At the points picked - level, so the rise is as typed.'
      else
        FStairJob.Note := 'At the points picked.';
      if (F.Rise > 0) and (F.Width > 0) then
      begin
        FStairJob.Frame := F;
        FStairJob.Mode := smPlaced;
        { start with the riser count that fits the points; the points stay
          where they were put }
        if FStairJob.HaveSpec then S := FStairJob.Spec else S := StairDefaults(F, FD.Units);
        S.Risers := RecommendStairs(F, FD.Units, FStairJob.Use, S).SuggestedRisers;
        FStairJob.Spec := S;
        FStairJob.HaveSpec := True;
      end;
    end
    else FStairJob.Note := Why;
    Application.QueueAsyncCall(@StairResume, 0);
  end;
  pbCmd.Invalidate;
  pbScreen.Invalidate;
end;

procedure TMainForm.StairTyped;
var
  L, H: Double;
  D, P: TP3;
  F: TStairFrame;
  Why: string;
begin
  if Trim(FInput) = '' then Exit;
  if not ParseLen(FInput, FD.Units, L) or (L <= 0) then
  begin
    FCmdMsg := 'Stairs: that is not a length - 10'', 12''6", 6-8-15.';
    pbCmd.Invalidate;
    Exit;
  end;
  case FStairPick of
    1:
      begin
        FCmdMsg := 'Stairs: click the top first - then a length typed is the run.';
        FInput := '';
        pbCmd.Invalidate;
        Exit;
      end;
    2:
      begin
        { the run, level from the top toward the cursor; the bottom at the
          cursor's height }
        D := P3(FCur.X - FStairPts[0].X, FCur.Y - FStairPts[0].Y, 0);
        H := Sqrt(Sqr(D.X) + Sqr(D.Y));
        if H < 1E-9 then
        begin
          FCmdMsg := 'Stairs: point the cursor the way the stairs run, then type the run.';
          pbCmd.Invalidate;
          Exit;
        end;
        P := P3(FStairPts[0].X + D.X / H * L, FStairPts[0].Y + D.Y / H * L, FCur.Z);
      end;
  else
    begin
      { the width, across the flight on the cursor's side }
      if not StairPickFrame(FCur, F, Why) then
      begin
        FCmdMsg := 'Stairs: ' + Why;
        pbCmd.Invalidate;
        Exit;
      end;
      P := P3(F.Bottom.X + F.Across.X * L, F.Bottom.Y + F.Across.Y * L, F.Bottom.Z);
    end;
  end;
  FInput := '';
  StairTakePoint(P);
end;

{ The stair pick so far, drawn on the sheet, with a guide beside the cursor
  saying what the next click is.  Picked points are labeled; after the top a
  line runs to the cursor; after the bottom the flight itself follows the
  cursor so the third click is made looking at the result. }
procedure TMainForm.PaintStairPick(C: TCanvas; SX, SY: Integer);
var
  Ink: TColor;
  F: TStairFrame;
  Why, Word_: string;
  K, N, GX, GY, U: Integer;
  A, B: TPointF;
  R, G: Double;

  function At(X, Y, Z: Double): TPointF;
  var
    W: TP3;
  begin
    W := P3(F.Bottom.X + F.Forward.X * X + F.Across.X * Y, F.Bottom.Y + F.Forward.Y * X + F.Across.Y * Y,
      F.Bottom.Z + Z);
    Result := ScreenOf(W);
  end;

  procedure Seg(const P, Q: TPointF);
  begin
    C.MoveTo(Round(P.X), Round(P.Y));
    C.LineTo(Round(Q.X), Round(Q.Y));
  end;

  procedure Mark(const P: TP3; const Name: string);
  var
    Q: TPointF;
    D: Integer;
  begin
    Q := ScreenOf(P);
    D := Round(5 * FUIScale);
    C.Pen.Style := psSolid;
    C.Brush.Style := bsSolid;
    C.Brush.Color := Ink;
    C.Ellipse(Round(Q.X) - D, Round(Q.Y) - D, Round(Q.X) + D + 1, Round(Q.Y) + D + 1);
    C.Brush.Style := bsClear;
    UIFont(C, 9, True, Theme.Text);
    C.Font.Color := Ink;
    C.TextOut(Round(Q.X) + D + 4, Round(Q.Y) - D - C.TextHeight('X'), Name);
  end;

  { a size on the drawing, on a card so it reads over lines }
  procedure Tag_(const At_: TPointF; const Words: string);
  var
    W, H, X, Y, Pad: Integer;
  begin
    UIFont(C, 9, True, Theme.Text);
    W := C.TextWidth(Words);
    H := C.TextHeight('Xg');
    Pad := Round(4 * FUIScale);
    X := Round(At_.X) - W div 2;
    Y := Round(At_.Y) - H div 2;
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
    C.Pen.Color := Ink;
    C.Brush.Style := bsSolid;
    C.Brush.Color := PixToColor(MixPix(Theme.Panel, Pix(0, 0, 0), 0.15));
    C.RoundRect(X - Pad, Y - Pad div 2, X + W + Pad, Y + H + Pad div 2, Pad * 2, Pad * 2);
    C.Brush.Style := bsClear;
    C.Font.Color := PixToColor(Theme.Text);
    C.TextOut(X, Y, Words);
    C.Pen.Width := Max(2, Round(2 * FUIScale));
    C.Pen.Color := Ink;
  end;

begin
  Ink := RGBToColor($F0, $80, $10);
  C.Pen.Color := Ink;
  C.Pen.Width := Max(2, Round(2 * FUIScale));
  if FStairPick >= 2 then Mark(FStairPts[0], 'TOP');
  if FStairPick = 2 then
  begin
    { from the top to where the bottom will go }
    C.Pen.Style := psDash;
    A := ScreenOf(FStairPts[0]);
    Seg(A, PointF(SX, SY));
    TipAvoid(Round(A.X), Round(A.Y), SX, SY);
    C.Pen.Style := psSolid;
    { the run and rise so far, halfway along }
    R := Abs(FStairPts[0].Z - FCur.Z);
    G := Sqrt(Sqr(FCur.X - FStairPts[0].X) + Sqr(FCur.Y - FStairPts[0].Y));
    if R < 1E-6 then
      Tag_(PointF((A.X + SX) / 2, (A.Y + SY) / 2),
        'run ' + FormatLen(G, FD.Units) + '   rise ' + FormatLen(FStairJob.Frame.Rise, FD.Units) + ' as typed')
    else
      Tag_(PointF((A.X + SX) / 2, (A.Y + SY) / 2),
        'run ' + FormatLen(G, FD.Units) + '   rise ' + FormatLen(R, FD.Units));
  end;
  if FStairPick = 3 then
  begin
    Mark(FStairPts[1], 'BOTTOM');
    if StairPickFrame(FCur, F, Why) then
    begin
      C.Pen.Style := psSolid;
      C.Pen.Width := Max(2, Round(2 * FUIScale));
      { the footprint and the landing's edge }
      Seg(At(0, 0, 0), At(0, F.Width, 0));
      Seg(At(0, 0, 0), At(F.Run, 0, 0));
      Seg(At(0, F.Width, 0), At(F.Run, F.Width, 0));
      Seg(At(F.Run, 0, F.Rise), At(F.Run, F.Width, F.Rise));
      { every nosing at its height, using the riser count the dialog will
        open with }
      if FStairJob.HaveSpec then
        N := RecommendStairs(F, FD.Units, FStairJob.Use, FStairJob.Spec).SuggestedRisers
      else
        N := RecommendStairs(F, FD.Units, FStairJob.Use, StairDefaults(F, FD.Units)).SuggestedRisers;
      N := EnsureRange(N, 2, 200);
      R := F.Rise / N; G := F.Run / (N - 1);
      C.Pen.Width := Max(1, Round(FUIScale));
      for K := 0 to N - 2 do
      begin
        Seg(At(K * G, 0, (K + 1) * R), At(K * G, F.Width, (K + 1) * R));
        { the side's sawtooth, both sides }
        Seg(At(K * G, 0, K * R), At(K * G, 0, (K + 1) * R));
        Seg(At(K * G, 0, (K + 1) * R), At((K + 1) * G, 0, (K + 1) * R));
        Seg(At(K * G, F.Width, K * R), At(K * G, F.Width, (K + 1) * R));
        Seg(At(K * G, F.Width, (K + 1) * R), At((K + 1) * G, F.Width, (K + 1) * R));
      end;
      Seg(At(F.Run, 0, (N - 1) * R), At(F.Run, 0, F.Rise));
      Seg(At(F.Run, F.Width, (N - 1) * R), At(F.Run, F.Width, F.Rise));
      A := At(0, 0, 0); B := At(0, F.Width, 0);
      TipAvoid(Round(A.X), Round(A.Y), Round(B.X), Round(B.Y));
      { width across the foot, run along the side, and the steps }
      Tag_(At(0, F.Width / 2, 0), 'width ' + FormatLen(F.Width, FD.Units));
      Tag_(At(F.Run / 2, 0, 0), 'run ' + FormatLen(F.Run, FD.Units));
      Tag_(At(F.Run, F.Width / 2, F.Rise), Format('rise %s - %d risers of %s, treads %s',
        [FormatLen(F.Rise, FD.Units), N, StairLen(R, FD.Units), StairLen(G, FD.Units)]));
    end;
  end;

  { beside the cursor: a three-step icon with the next point lit, and its
    name }
  U := Max(1, Round(FUIScale));
  GX := SX + 14 * U; GY := SY - 34 * U;
  C.Pen.Style := psSolid;
  C.Pen.Width := Max(2, Round(2 * FUIScale));
  C.Pen.Color := Ink;
  C.MoveTo(GX, GY + 24 * U);
  C.LineTo(GX + 8 * U, GY + 24 * U); C.LineTo(GX + 8 * U, GY + 16 * U);
  C.LineTo(GX + 16 * U, GY + 16 * U); C.LineTo(GX + 16 * U, GY + 8 * U);
  C.LineTo(GX + 24 * U, GY + 8 * U); C.LineTo(GX + 24 * U, GY);
  C.LineTo(GX + 34 * U, GY);
  C.Brush.Style := bsSolid;
  C.Brush.Color := Ink;
  C.Pen.Color := Ink;
  { the lit point: bigger than the line, ringed to read on any paper }
  C.Pen.Color := PixToColor(Theme.Text);
  C.Pen.Width := Max(1, Round(FUIScale));
  case FStairPick of
    1: begin C.Ellipse(GX + 19 * U, GY - 6 * U, GX + 31 * U, GY + 6 * U); Word_ := 'TOP'; end;
    2: begin C.Ellipse(GX - 6 * U, GY + 18 * U, GX + 6 * U, GY + 30 * U); Word_ := 'BOTTOM'; end;
  else
    begin
      { the width: an arrow across the flight }
      C.Brush.Style := bsClear;
      C.Pen.Color := Ink;
      C.Pen.Width := Max(2, Round(2 * FUIScale));
      C.MoveTo(GX + 2 * U, GY + 30 * U); C.LineTo(GX + 30 * U, GY + 30 * U);
      C.MoveTo(GX + 30 * U, GY + 30 * U); C.LineTo(GX + 25 * U, GY + 26 * U);
      C.MoveTo(GX + 30 * U, GY + 30 * U); C.LineTo(GX + 25 * U, GY + 34 * U);
      Word_ := 'SIDE';
    end;
  end;
  C.Brush.Style := bsClear;
  UIFont(C, 10, True, Theme.Text);
  C.Font.Color := Ink;
  C.TextOut(GX + 40 * U, GY - 2 * U, IntToStr(FStairPick) + '  ' + Word_);
  C.Pen.Width := 1;
  { and the chip keeps off it }
  TipAvoid(GX, GY + 24 * U, GX + 40 * U + C.TextWidth('3  BOTTOM'), GY);
end;

procedure TMainForm.StairResume(Data: PtrInt);
begin
  StairDialog;
end;

{ The radiant heat layout wizard.  It fills the selected floor where it is,
  so nothing is placed afterward; the new lines are left selected, as a push
  leaves its result selected. }
procedure TMainForm.BuildRadiantWizard(Again: Integer);
var
  Zones: TRadiantZones;
  Holes: TRadiantHoles;
  I, J, First, Z, K: Integer;
  Job, Was: TRadiantJob;
  JobId: string;
  Old, M: TIntArrayW;
  Doomed: array of Boolean;
  Spec: TRadiantSpec;
  Manifolds: TP3Array;
  Ports: TIntArray;
  Layouts: TRadiantResults;
  ZoneNames: TStringArray;
  R: TRadiantResult;
  Loops: Integer;
  Ft: Double;
begin
  { Each selected face is a zone with its own manifold (a floor drawn as one
    rectangle with lines across it is several zones); a face cut out of one
    is a hole and a no-go.  Ctrl+A or a drag both work: lines are ignored. }
  SetLength(Zones, 0);
  { a kept job reopened: its zones are its own, not the selection's }
  if Again > 0 then
  begin
    Old := nil;
    if RadiantGroupOf(Again, JobId) > 0 then Old := RadiantJobGroups(JobId, Was);
    if Length(Old) = 0 then
    begin
      FCmdMsg := 'That is not a radiant layout the drawing kept the job of - one built before 28 September was not kept.';
      pbCmd.Invalidate;
      Exit;
    end;
    hsDialogSkin.UseTheme(Themes[FThemeIdx]);
    if not TRadiantForm.Reopen(FD.Units, Was, Zones, Spec, Manifolds, Ports, Layouts, ZoneNames, Job) then Exit;
    PushUndo;
    { remove the job as built (every zone group and its contents) and put
      the wizard's result in its place, in one undo step }
    LeaveSheet;
    ResetTool;
    FD.Doc.Context := 0;
    SetLength(Doomed, FD.Doc.Live);
    for I := 0 to High(Doomed) do Doomed[I] := False;
    for K := 0 to High(Old) do
    begin
      M := FD.Doc.PartMembers(Old[K], True);
      for I := 0 to High(M) do Doomed[M[I]] := True;
    end;
    FD.Doc.DeleteMarked(Doomed);
  end
  else
  for I := 0 to High(FSel) do
    if (FSel[I] >= 0) and (FSel[I] < FD.Doc.Live) and (FD.Doc[FSel[I]].Kind = ekFace) then
    begin
      SetLength(Zones, Length(Zones) + 1);
      Zones[High(Zones)].Outline := FD.Doc[FSel[I]].Poly;
      SetLength(Zones[High(Zones)].Holes, Length(FD.Doc[FSel[I]].Holes));
      for J := 0 to High(FD.Doc[FSel[I]].Holes) do
        Zones[High(Zones)].Holes[J] := FD.Doc[FSel[I]].Holes[J];
    end;
  if Length(Zones) = 0 then
  begin
    FCmdMsg := 'Select the floor first - a face for each zone, or everything - then Radiant heat layout.';
    pbCmd.Invalidate;
    ShowMessage(FCmdMsg);
    Exit;
  end;
  if Again <= 0 then
  begin
    { the dialogs share one palette, the window's }
    hsDialogSkin.UseTheme(Themes[FThemeIdx]);
    if not TRadiantForm.Ask(FD.Units, Zones, Spec, Manifolds, Ports, Layouts, ZoneNames, Job) then Exit;
    JobId := NewRadiantJobId;
    PushUndo;
  end;
  First := FD.Doc.Live;
  Loops := 0; Ft := 0;
  for Z := 0 to High(Zones) do
  begin
    Holes := Copy(Zones[Z].Holes);
    for I := 0 to High(Spec.Extra) do
    begin
      SetLength(Holes, Length(Holes) + 1);
      Holes[High(Holes)] := Spec.Extra[I];
    end;
    SetLength(Spec.Manifolds, 1); SetLength(Spec.Ports, 1);
    Spec.Manifolds[0] := Manifolds[Z]; Spec.Ports[0] := Ports[Z];
    { use the layout the wizard already searched and showed; searching again
      took as long with nothing on screen }
    if Z > High(Layouts) then Continue;
    R := Layouts[Z];
    if not R.Ok then Continue;
    { the job's name and the zone's own, where given }
    J := BuildRadiant(FD.Doc, Zones[Z].Outline, Zones[Z].Holes, R, Spec, RGBToColor(200, 48, 32),
      IfThen(Spec.Tag <> '', Spec.Tag + ' ', 'Radiant ') + 'zone ' + IntToStr(Z + 1) +
      IfThen((Z <= High(ZoneNames)) and (ZoneNames[Z] <> ''), ' - ' + ZoneNames[Z], ''), Z);
    { the whole job kept in the zone's group, to reopen in the wizard and
      reprint its submittal (see hsRadiantJob) }
    if (J < FD.Doc.Live) and (FD.Doc[J].Kind = ekPart) then
      FD.Doc.SetPartData(FD.Doc[J].Grp, RadiantJobData(Job, Z, JobId));
    Inc(Loops, Length(R.Loops));
    Ft := Ft + R.TotalFt;
  end;
  { obstacles added in the wizard, once, not once per zone }
  RebuildFlatFaces;
  SeedRegions;
  RenderInk;
  RecomposeAll;
  SelectNone;
  for I := First to FD.Doc.Live - 1 do SelectAdd(I);
  FCmdMsg := Format('Radiant layout built: %d zone(s), %d loop(s), %s.',
    [Length(Zones), Loops, FormatLen(Ft, FD.Units)]);
  if Again > 0 then FCmdMsg := 'Built again - ' + FCmdMsg;
  pbScreen.Invalidate;
  pbCmd.Invalidate;
end;

function TMainForm.RadiantGroupOf(G: Integer; out JobId: string): Integer;
var
  Guard, Z: Integer;
begin
  Result := 0;
  JobId := '';
  Guard := 0;
  while (G > 0) and (Guard < 1000) do
  begin
    if IsRadiantData(FD.Doc.PartData(G), JobId, Z) then Exit(G);
    G := FD.Doc.PartParent(G);
    Inc(Guard);
  end;
  JobId := '';
end;

function TMainForm.RadiantJobGroups(const JobId: string; out Job: TRadiantJob): TIntArrayW;
var
  I, Z: Integer;
  Id: string;
  Datas: array of string;
begin
  Result := nil;
  Datas := nil;
  Job := Default(TRadiantJob);
  for I := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[I].Kind = ekPart) and (FD.Doc[I].Data <> '') and IsRadiantData(FD.Doc[I].Data, Id, Z) and
       (Id = JobId) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := FD.Doc[I].Grp;
      SetLength(Datas, Length(Datas) + 1);
      Datas[High(Datas)] := FD.Doc[I].Data;
    end;
  if (Length(Datas) = 0) or not RadiantJobFromData(Datas, Job) then Result := nil;
end;

procedure TMainForm.StringerSheetOf(G: Integer);
var
  F: TStairFrame;
  S: TStairSpec;
  Use: TStairUse;
begin
  if (G <= 0) or not StairFromJig(FD.Doc.PartJig(G), FD.Units, F, S, Use) then
  begin
    FCmdMsg := 'Those stairs do not say how they were made.';
    pbCmd.Invalidate;
    Exit;
  end;
  dlgStringers.FileName := FD.Doc.PartName(G) + ' - stringer sheet.pdf';
  if not dlgStringers.Execute then Exit;
  try
    StringerSheetPdf(F, S, Use, FD.Units, FD.Doc.PartName(G), dlgStringers.FileName);
    FCmdMsg := 'The stringer sheet: ' + ExtractFileName(dlgStringers.FileName);
    OpenDocument(dlgStringers.FileName);
  except
    on E: Exception do FCmdMsg := 'Could not write it: ' + E.Message;
  end;
  pbCmd.Invalidate;
end;

{ Reprint the submittal of a kept job, as built, from the zone groups, with
  no search and no wizard. }
procedure TMainForm.PrintSubmittalAgain(G: Integer);
var
  JobId: string;
  Job: TRadiantJob;
begin
  if (RadiantGroupOf(G, JobId) = 0) or (Length(RadiantJobGroups(JobId, Job)) = 0) then
  begin
    FCmdMsg := 'That is not a radiant layout the drawing kept the job of.';
    pbCmd.Invalidate;
    Exit;
  end;
  if Job.Title <> '' then dlgSubmittal.FileName := Job.Title + ' - radiant submittal.pdf'
  else dlgSubmittal.FileName := 'radiant submittal ' + FormatDateTime('yyyy-mm-dd', Now) + '.pdf';
  if not dlgSubmittal.Execute then Exit;
  Screen.Cursor := crHourGlass;
  try
    try
      SubmittalExport(Job, dlgSubmittal.FileName);
      FCmdMsg := 'The submittal, printed again: ' + ExtractFileName(dlgSubmittal.FileName);
    except
      on E: Exception do FCmdMsg := 'Could not write it: ' + E.Message;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  pbCmd.Invalidate;
end;

{ Copy, cut and paste.  The clipboard holds a deep copy, not indices, since
  the source sheet may not be in front, or even exist, by paste time.
  Pasting hands over to the move tool, as SketchUp does: it arrives on the
  cursor and a click puts it down. }
procedure TMainForm.CopySelection(Cut: Boolean);
begin
  if Length(FSel) = 0 then
  begin
    FCmdMsg := 'Nothing picked.  Click something first, or drag a box round it.';
    Exit;
  end;
  FClip := FD.Doc.CopyOut(FSel);
  if Cut then
  begin
    FCmdMsg := Format('Cut %d thing%s.  Ctrl+V puts %s down - on this sheet ' +
      'or any other.', [Length(FClip), IfThen(Length(FClip) = 1, '', 's'),
      IfThen(Length(FClip) = 1, 'it', 'them')]);
    DeleteSelection;
  end
  else
    FCmdMsg := Format('Copied %d thing%s.  Ctrl+V puts %s down - on this ' +
      'sheet or any other.', [Length(FClip), IfThen(Length(FClip) = 1, '', 's'),
      IfThen(Length(FClip) = 1, 'it', 'them')]);
  pbCmd.Invalidate;
end;

procedure TMainForm.PasteClip;
var
  N, First, Last, I: Integer;
  Idx: array of Integer;
  Mid: TP3;
begin
  if Length(FClip) = 0 then
  begin
    FCmdMsg := 'Nothing copied yet.  Pick something and press Ctrl+C.';
    Exit;
  end;
  PushUndo;
  N := FD.Doc.PasteIn(FClip, P3(0, 0, 0), First, Last);
  if N = 0 then
  begin
    FCmdMsg := 'Nothing in that worth pasting.';
    Exit;
  end;
  SetLength(Idx, Last - First + 1);
  for I := First to Last do Idx[I - First] := I;
  if not FD.Doc.MiddleOf(Idx, Mid) then Mid := P3(0, 0, 0);
  SeedRegions;
  RenderInk;
  RecomposeAll;
  { into the move tool, held by its middle }
  PlaceBuilt(First, Mid);
  FCmdMsg := Format('%d thing%s on the cursor - click to put %s down, or ' +
    'Esc to leave %s where they came from.',
    [N, IfThen(N = 1, '', 's'), IfThen(N = 1, 'it', 'them'),
     IfThen(N = 1, 'it', 'them')]);
  pbCmd.Invalidate;
end;

{ The wizards build at the origin; this hands the piece to the move tool so
  the next click places it with the usual snaps. }
procedure TMainForm.PlaceBuilt(First: Integer; const Ref: TP3);
var
  I: Integer;
begin
  SetTool(ptMove);
  SelectNone;
  for I := First to FD.Doc.Live - 1 do SelectAdd(I);
  FP1 := Ref;
  FD.Doc.VertsOf(FSel, FMoveVerts);
  FStage := 1;
  FDirLock := -1;
  FMoveCopy := False;
  FMoveRigid := True;
  FInput := '';
  FCmdMsg := 'Built.  Its entry corner is on the cursor - click where it goes, ' +
    'or type a point [x,y,z].';
  pbScreen.Invalidate;
  pbCmd.Invalidate;
end;

{ the release notes, from the help menu or /whatsnew }
procedure TMainForm.ShowWhatsNew;
var
  F: TWhatsNewForm;
begin
  { the dialogs share one palette, the window's }
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  F := TWhatsNewForm.Create(Self);
  try
    F.ShowAll;
  finally
    F.Free;
  end;
end;

{ Fetch the update, verify it, put it in place and restart.  The drawings go
  across in the draft and the handoff. }
procedure TMainForm.DoUpdate;
var
  Info: TUpdateInfo;
  Err, Why, Tmp: string;
  UpdateForm: TUpdateForm;
begin
  Why := WhyNotUpdate;
  if Why <> '' then
  begin
    MessageDlg('Cannot update here', Why + '.' + #13#10#13#10 +
      'Download it yourself from the Releases page instead.',
      mtInformation, [mbOK], 0);
    Exit;
  end;

  FCmdMsg := 'Looking...';
  pbCmd.Invalidate;
  Application.ProcessMessages;
  if not FetchLatest(Info, Err) then
  begin
    FCmdMsg := 'Could not check for an update - ' + Err;
    Exit;
  end;
  if not NewerThan(Info.Tag, CurrentVersion) then
  begin
    FCmdMsg := 'Already up to date - ' + CurrentVersion + '.';
    Exit;
  end;
  if MessageDlg('Update available',
       Format('%s is out, and this is %s.'#13#10#13#10 +
         'It will be fetched, put in place, and the program restarted.  ' +
         'Your drawings are kept just as they are - every sheet, and ' +
         'anything not saved yet stays not saved - and come straight back.',
         [Info.Tag, CurrentVersion]),
       mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
  begin
    FCmdMsg := 'Left alone.';
    Exit;
  end;

  SaveDraft;                          { whatever happens next, this survives }

  { beside the program, not the system temp: a portable copy keeps its
    scratch with it, and the rename must be on the same volume to be atomic }
  Tmp := AppDataDir + 'heckers-sketch-' + Info.Tag + '.download';
  { written before the update runs, since the update starts the new copy and
    it reads this straight away }
  WriteHandoff;
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  UpdateForm := TUpdateForm.Create(Self);
  try
    if UpdateForm.Run(Info, Tmp) then
    begin
      { No save question on the way out: the new copy waits for this one to
        exit and gives up if a question sits unanswered.  Everything is in
        the handoff. }
      FHandingOver := True;
      Close;
    end
    else
    begin
      DeleteFile(HandoffFile);
      FCmdMsg := 'The update was not installed.';
    end;
  finally
    UpdateForm.Free;
  end;
end;

{ The drawings for the copy that replaces this one.  The draft alone would
  restore them like a crash recovery, without file names or unsaved flags;
  this adds those as comment lines the reader skips. }
procedure TMainForm.WriteHandoff;
var
  L: TStringList;
  I: Integer;
begin
  try
    L := TStringList.Create;
    try
      L.Add('// handoff from ' + CurrentVersion);
      L.Add('// tab ' + IntToStr(FTabIdx));
      { each sheet's file and saved state are on it (see BuildSession) }
      BuildSession(L, True, -1, True);
      ForceDirectories(ExtractFilePath(HandoffFile));
      L.SaveToFile(HandoffFile);
    finally
      L.Free;
    end;
  except
    { the draft is already written; the handoff is the better copy, not the
      only one }
    on E: Exception do DeleteFile(HandoffFile);
  end;
end;

{ In the new copy: restore the drawings exactly as left, same files, same
  sheet in front, unsaved work still unsaved so closing asks.  Only after an
  update; one found any other time is stale and is deleted. }
function TMainForm.RestoreHandoff: Boolean;
var
  L: TStringList;
  I, K, Tab, NDirty, First: Integer;
  Path, S: string;
  Dirty: array of Boolean;
  Words: TStringArray;
begin
  Result := False;
  if not FileExists(HandoffFile) then Exit;
  Path := '';
  Tab := 0;
  Dirty := nil;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(HandoffFile);
    except
      Exit;
    end;
    for I := 0 to L.Count - 1 do
    begin
      S := L[I];
      { note lines at the top: "//" in Heck, "#" from older versions }
      if Copy(S, 1, 2) = '//' then S := '#' + Copy(S, 3, MaxInt)
      else if Copy(S, 1, 1) <> '#' then Break;
      if Copy(S, 1, 7) = '# path ' then Path := Copy(S, 8, MaxInt)
      else if Copy(S, 1, 6) = '# tab ' then Tab := StrToIntDef(Trim(Copy(S, 7, MaxInt)), 0)
      else if Copy(S, 1, 7) = '# dirty' then
      begin
        Words := Trim(Copy(S, 8, MaxInt)).Split([' '], TStringSplitOptions.ExcludeEmpty);
        for K := 0 to High(Words) do
          if StrToIntDef(Words[K], -1) >= 0 then
          begin
            if StrToInt(Words[K]) >= Length(Dirty) then
              SetLength(Dirty, StrToInt(Words[K]) + 1);
            Dirty[StrToInt(Words[K])] := True;
          end;
      end;
    end;
  finally
    L.Free;
  end;

  { the same guard the draft has: a handoff that crashes the program on load
    is set aside next time; the draft holds the same work }
  with TIniFile.Create(ConfigFile) do
  try
    WriteBool('startup', 'restoring', True);
  finally
    Free;
  end;
  try
    try
      Result := ReadSheets(HandoffFile, True, First);
      { the empty drawing the program started with gives way }
      if Result and (First > 0) then
      begin
        for I := 0 to First - 1 do FDrawings[I].Free;
        for I := First to High(FDrawings) do FDrawings[I - First] := FDrawings[I];
        SetLength(FDrawings, Length(FDrawings) - First);
        FD := nil;
      end;
    except
      Result := False;
    end;
  finally
    with TIniFile.Create(ConfigFile) do
    try
      WriteBool('startup', 'restoring', False);
    finally
      Free;
    end;
  end;
  DeleteFile(HandoffFile);
  if not Result or FLoadSkipped then Exit(False);

  { an older handoff carries one path for everything and dirty sheets by
    number }
  if (Path <> '') and (FDrawings[0].FilePath = '') then
    for I := 0 to High(FDrawings) do
    begin
      FDrawings[I].FilePath := Path;
      FDrawings[I].DocName := ChangeFileExt(ExtractFileName(Path), '');
    end;
  for I := 0 to High(FDrawings) do
    if (I < Length(Dirty)) and Dirty[I] then FDrawings[I].Dirty := True;
  NDirty := AnyDirty;
  if NDirty > 0 then Inc(FEditSeq);       { so the draft is written again too }
  ShowLoaded(EnsureRange(Tab, 0, High(FDrawings)));
  FRestored := True;
  FCmdMsg := 'Updated from ' + IfThen(FUpdatedFrom = '', 'the last version', FUpdatedFrom) +
    ' - your drawings are back just as you left them' +
    IfThen(NDirty = 0, '.',
      Format(', %d file%s not saved yet.', [NDirty, IfThen(NDirty = 1, '', 's')]));
  Trail(Format('picked up the handoff: %d sheets, %d not saved, from %s',
    [Length(FDrawings), NDirty, IfThen(Path = '', 'no file', ExtractFileName(Path))]));
end;

{ The window as it stands, as a bitmap the caller owns.  A bitmap rather than
  PNG bytes, because it is shown next and would have to be decoded again
  (and TBitmap.LoadFromStream reads BMP, not PNG). }
function TMainForm.WindowShot(out B: TBitmap): Boolean;
var
  DC: HDC;
  Grabbed: Boolean;
  Org: TPoint;

  { Cut the screen down to this program's own windows (main plus any dialog,
    with title bars).  The whole screen would include other monitors and
    other programs. }
  procedure OursOnly;
  const
    FRAME = 8;
    TITLE = 40;
  var
    I: Integer;
    R, F: TRect;
    Cut: TBitmap;
    Any: Boolean;
  begin
    Any := False;
    R := Rect(0, 0, 0, 0);
    for I := 0 to Screen.FormCount - 1 do
    begin
      if not Screen.Forms[I].Visible or (Screen.Forms[I].Parent <> nil) then Continue;
      F := Screen.Forms[I].BoundsRect;
      F := Rect(F.Left - FRAME, F.Top - TITLE, F.Right + FRAME, F.Bottom + FRAME);
      if not Any then R := F
      else R := Rect(Min(R.Left, F.Left), Min(R.Top, F.Top), Max(R.Right, F.Right), Max(R.Bottom, F.Bottom));
      Any := True;
    end;
    if not Any then Exit;
    R := Rect(Max(0, R.Left), Max(0, R.Top), Min(B.Width, R.Right), Min(B.Height, R.Bottom));
    if (R.Right - R.Left < 8) or (R.Bottom - R.Top < 8) then Exit;
    Cut := TBitmap.Create;
    try
      Cut.SetSize(R.Right - R.Left, R.Bottom - R.Top);
      Cut.Canvas.CopyRect(Rect(0, 0, Cut.Width, Cut.Height), B.Canvas, R);
    except
      Cut.Free;
      Exit;
    end;
    B.Free;
    B := Cut;
    Org := R.TopLeft;
  end;

begin
  { From inside a dialog, grab the screen (cut to our windows), since the
    window alone would leave out the dialog being reported. }
  Grabbed := False;
  Org := Point(0, 0);
  if FReportExtra <> '' then
  begin
    B := TBitmap.Create;
    try
      DC := GetDC(0);
      try
        B.LoadFromDevice(DC);
      finally
        ReleaseDC(0, DC);
      end;
      Grabbed := True;
      OursOnly;
    except
      FreeAndNil(B);
    end;
    { the fallback is the window image; DrawPointerOn is told which
      coordinates it has }
    if B = nil then B := GetFormImage;
  end
  else
    B := GetFormImage;
  Result := (B <> nil) and (B.Width >= 8) and (B.Height >= 8);
  if not Result then
  begin
    B.Free;
    B := nil;
  end
  else
    DrawPointerOn(B, Grabbed, Org);
end;

{ Neither a screen grab nor a form image includes the mouse pointer, so draw
  one where the cursor is.  Screen shots use screen coordinates and form
  images window coordinates; that is the thing to get right. }
procedure TMainForm.DrawPointerOn(B: TBitmap; ScreenCoords: Boolean; const Org: TPoint);
var
  P: TPoint;
  Arrow: array[0..6] of TPoint;
  I: Integer;
begin
  if B = nil then Exit;
  try
    P := Mouse.CursorPos;
    { a screen shot cut to our windows starts at Org on the screen }
    if ScreenCoords then P := Point(P.X - Org.X, P.Y - Org.Y)
    else P := ScreenToClient(P);
  except
    Exit;
  end;
  if (P.X < 0) or (P.Y < 0) or (P.X >= B.Width) or (P.Y >= B.Height) then Exit;

  { the ordinary pointer shape, at system size }
  Arrow[0] := Point(0, 0);
  Arrow[1] := Point(0, 17);
  Arrow[2] := Point(4, 13);
  Arrow[3] := Point(7, 20);
  Arrow[4] := Point(10, 18);
  Arrow[5] := Point(7, 12);
  Arrow[6] := Point(12, 12);
  for I := 0 to High(Arrow) do
    Arrow[I] := Point(Arrow[I].X + P.X, Arrow[I].Y + P.Y);

  B.Canvas.Pen.Color := clWhite;
  B.Canvas.Pen.Width := 3;
  B.Canvas.Brush.Style := bsClear;
  B.Canvas.Polygon(Arrow);
  B.Canvas.Pen.Color := clBlack;
  B.Canvas.Pen.Width := 1;
  B.Canvas.Brush.Style := bsSolid;
  B.Canvas.Brush.Color := clBlack;
  B.Canvas.Polygon(Arrow);

  { a ring too: an arrow on a busy drawing is easy to lose }
  B.Canvas.Brush.Style := bsClear;
  B.Canvas.Pen.Color := clRed;
  B.Canvas.Pen.Width := 2;
  B.Canvas.Ellipse(P.X - 13, P.Y - 13, P.X + 14, P.Y + 14);
  B.Canvas.Pen.Width := 1;
end;

{ Count down from Seconds with the program still usable, so the user can set
  the screen up.  Not a dialog: messages are pumped and the number is painted
  on the canvas by the normal paint path. }
procedure TMainForm.ShotCountdown(Seconds: Integer);
var
  Until_: QWord;
begin
  FShotCount := Seconds;
  while FShotCount > 0 do
  begin
    FCmdMsg := Format(
      'Set the screen up the way it went wrong - picture in %d.', [FShotCount]);
    FScreenDirty := True;
    pbScreen.Invalidate;
    pbCmd.Invalidate;
    Until_ := GetTickCount64 + 1000;
    while GetTickCount64 < Until_ do
    begin
      Application.ProcessMessages;
      if Application.Terminated then
      begin
        FShotCount := 0;
        Exit;
      end;
      Sleep(15);
    end;
    Dec(FShotCount);
  end;
end;

{ the countdown number, and the flash }
procedure TMainForm.PaintShotOverlay(C: TCanvas);
var
  R: TRect;
  S: string;
  Sz: TSize;
  Pad: Integer;
begin
  if FShotFlash then
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := clWhite;
    C.FillRect(0, 0, pbScreen.Width, pbScreen.Height);
    Exit;
  end;
  if FShotCount <= 0 then Exit;

  Pad := Round(14 * FUIScale);
  C.Font.Name := 'Sans';
  C.Font.Size := Round(30 * FUIScale);
  C.Font.Style := [fsBold];
  S := IntToStr(FShotCount);
  Sz := C.TextExtent(S);

  R := Rect(pbScreen.Width - Sz.cx - Pad * 3, Pad,
            pbScreen.Width - Pad, Pad * 2 + Sz.cy);
  C.Brush.Style := bsSolid;
  C.Brush.Color := $001A1A1A;
  C.Pen.Color := $0060C0FF;
  C.Pen.Width := Max(1, Round(2 * FUIScale));
  C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Pad, Pad);

  C.Brush.Style := bsClear;
  C.Font.Color := $00FFFFFF;
  C.TextOut(R.Left + (R.Right - R.Left - Sz.cx) div 2,
            R.Top + (R.Bottom - R.Top - Sz.cy) div 2, S);

  C.Font.Size := Round(9 * FUIScale);
  C.Font.Style := [];
  C.Font.Color := $00D0D0D0;
  S := 'set the screen up - picture in';
  Sz := C.TextExtent(S);
  C.Brush.Style := bsSolid;
  C.Brush.Color := $001A1A1A;
  C.TextOut(R.Left - Sz.cx - Pad, R.Top + (R.Bottom - R.Top - Sz.cy) div 2, S);
end;

procedure TMainForm.ReportFromDialog(const Where, Fields: string);
begin
  FReportExtra := Where + LineEnding + Fields;
  try
    ReportBug;
  finally
    FReportExtra := '';
  end;
end;

{ Take the report picture: optional countdown, the shot, then the flash.
  The report form shows the result. }
function TMainForm.CaptureShot(Wait: Boolean; out Bmp: TBitmap): Boolean;
var
  WasMsg: string;
  Until_: QWord;
begin
  Result := False;
  Bmp := nil;
  if FShotBusy then Exit;
  FShotBusy := True;
  WasMsg := FCmdMsg;
  try
    Application.ProcessMessages;
    if Wait then
    begin
      FCmdMsg := 'Setting up the picture - it is taken when this reaches zero.';
      ShotCountdown(10);
      if Application.Terminated then Exit;
    end;

    { Nothing about taking the picture may be in it: the countdown number goes
      and the command bar is restored to what it would have said.  Wait a
      moment so the closed question box is painted over. }
    Until_ := GetTickCount64 + 350;
    while GetTickCount64 < Until_ do
    begin
      Application.ProcessMessages;
      Sleep(15);
    end;
    FShotCount := 0;
    FShotFlash := False;
    FCmdMsg := WasMsg;
    FScreenDirty := True;
    pbScreen.Invalidate;
    pbCmd.Invalidate;
    Application.ProcessMessages;

    if not WindowShot(Bmp) then Exit;

    { and the flash after it, not before }
    FShotFlash := True;
    pbScreen.Invalidate;
    Application.ProcessMessages;
    Sleep(110);
    FShotFlash := False;
    FScreenDirty := True;
    pbScreen.Invalidate;
    Application.ProcessMessages;
    Result := True;
  finally
    FShotBusy := False;
    FShotCount := 0;
    FShotFlash := False;
    FCmdMsg := WasMsg;
    FScreenDirty := True;
    pbScreen.Invalidate;
    pbCmd.Invalidate;
  end;
end;

{ A bug report in the user's own words, with state gathered at the moment
  of sending.  The drawing is offered, not assumed: it is the most useful
  thing for finding a fault, but it is somebody's work. }
function TMainForm.ReportBug(const Preamble, ShotFile, DocFile: string): Boolean;
var
  Sending: TSendForm;
  ShotBmp: TBitmap;
  Png: TPortableNetworkGraphic;
  DocOn: Boolean;
  Res: Integer;
  Body, Name_, Err, Note, ShotErr: string;
  WantShot: Boolean;
  NThings: Integer;
  Shot: TMemoryStream;
  L: TStringList;
  HasDrawing: Boolean;
  SheetName_, MachineIs: string;
  FileRep, FilePic, NSent: Integer;
  Total: Int64;

  { a line of the report by its leading key ("version", "when") }
  function LineOf(const Text, Key: string): string;
  var
    LL: TStringList;
    K: Integer;
  begin
    Result := '';
    LL := TStringList.Create;
    try
      LL.Text := Text;
      for K := 0 to LL.Count - 1 do
        if Copy(LL[K], 1, Length(Key) + 1) = Key + ':' then
        begin
          Result := Trim(Copy(LL[K], Length(Key) + 2, MaxInt));
          Exit;
        end;
    finally
      LL.Free;
    end;
  end;

  { one key=value from the report's state lines ("mode=", "theme=") }
  function Tok(const Key: string): string;
  var
    K: Integer;
  begin
    Result := '';
    K := Pos(Key, Body);
    if K = 0 then Exit('-');
    Inc(K, Length(Key));
    while (K <= Length(Body)) and not (Body[K] in [' ', #10, #13]) do
    begin
      Result := Result + Body[K];
      Inc(K);
    end;
  end;

  function BodyLine(const Key: string): string;
  begin
    Result := LineOf(Body, Key);
  end;

  function MachineLine(const Key: string): string;
  begin
    Result := LineOf(MachineIs, Key);
  end;

  function KB(Bytes: Int64): string;
  begin
    if Bytes < 10 * 1024 then Result := FormatFloat('0.0', Bytes / 1024) + ' KB'
    else Result := FormatFloat('0', Bytes / 1024) + ' KB';
  end;

begin
  Result := False;

  { The picture is taken first, of the window as it is, and the report form
    shows it while the user writes, so words and picture match.  From the
    form it can be retaken now, retaken after a ten second countdown, or
    dropped, without losing what was typed. }
  Application.ProcessMessages;
  ShotBmp := nil;
  if (ShotFile <> '') and FileExists(ShotFile) then
  begin
    { for a crash, the picture saved when it happened; the screen now is
      the restart }
    try
      ShotBmp := TBitmap.Create;
      ShotBmp.LoadFromFile(ShotFile);
    except
      FreeAndNil(ShotBmp);
    end;
  end
  else
    CaptureShot(False, ShotBmp);
  WantShot := ShotBmp <> nil;

  Note := '';
  DocOn := True;
  try
  repeat
  { count the drawing that will actually go: for a crash, the one saved
    when it happened }
  NThings := DocThings(DocFile);
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  if WantShot then
    Res := TReportDialog.Ask(Self, Preamble <> '', NThings, ShotBmp, Note, DocOn)
  else
    Res := TReportDialog.Ask(Self, Preamble <> '', NThings, nil, Note, DocOn);

  if Res in [mrRetry, mrAll] then
  begin
    FreeAndNil(ShotBmp);
    CaptureShot(Res = mrAll, ShotBmp);
    WantShot := ShotBmp <> nil;
  end
  else if Res = mrIgnore then
  begin
    FreeAndNil(ShotBmp);
    WantShot := False;
  end;
  until not (Res in [mrRetry, mrAll, mrIgnore]);

  if Res <> mrOK then
  begin
    FCmdMsg := 'Report canceled.';
    Exit;
  end;

    Body := 'Heckers Sketch report' + LineEnding +
      specialize IfThen<string>(Preamble = '', '',
        'this one followed a crash' + LineEnding) +
      'version: ' + CurrentVersion + '  built ' + BUILD_STAMP + LineEnding +
      'when: ' + DateTimeToStr(Now) + LineEnding + LineEnding +
      'what they said:' + LineEnding +
      specialize IfThen<string>(Note = '', '(nothing written)', Note) +
      LineEnding + LineEnding +
      'state:' + LineEnding + DiagnosticText +
      LineEnding + 'settings and circumstances:' + LineEnding + SettingsText +
      LineEnding + 'machine:' + LineEnding + MachineText;
    if FReportExtra <> '' then
      Body := Body + LineEnding + 'in the dialog:' + LineEnding + FReportExtra;
    if Preamble <> '' then
      Body := Body + LineEnding + 'the crash it left behind:' + LineEnding +
        Preamble;
    if DocOn then
    begin
      L := TStringList.Create;
      try
        { For a crash, send the drawing saved when it happened; by now the
          screen shows an empty sheet or a restored draft, neither of which
          is what went wrong. }
        if (DocFile <> '') and FileExists(DocFile) then
        begin
          try
            L.LoadFromFile(DocFile);
          except
            L.Clear;
            BuildSession(L, False, -1, False, True);
          end;
        end
        else
          BuildSession(L, False, -1, False, True);
        Body := Body + LineEnding + 'the drawing, sent on purpose:' +
          LineEnding + L.Text;
      finally
        L.Free;
      end;
    end;
    Name_ := UniqueReportName('bug', CurrentVersion);

  { the picture is encoded to PNG only now that it is being sent }
  Shot := TMemoryStream.Create;
  try
    if WantShot and (ShotBmp <> nil) then
    begin
      Png := TPortableNetworkGraphic.Create;
      try
        Png.Assign(ShotBmp);
        Png.SaveToStream(Shot);
      finally
        Png.Free;
      end;
    end;
    if Shot.Size = 0 then WantShot := False;
    KeepReportCopy(Name_, Body, Shot);

    FCmdMsg := 'Sending...';
  pbCmd.Invalidate;
  { Shown going out stage by stage, like an update coming in, with a moment
    on each so the user can see what is sent and how big. }
  HasDrawing := Pos('the drawing, sent on purpose', Body) > 0;
  { the machine lines are those after "machine:", so a "machine: Dell..."
    line is not mistaken for the heading }
  MachineIs := Body;
  if Pos(LineEnding + 'machine:' + LineEnding, MachineIs) > 0 then
    Delete(MachineIs, 1, Pos(LineEnding + 'machine:' + LineEnding, MachineIs) +
      Length(LineEnding + 'machine:' + LineEnding) - 1);
  if Pos(LineEnding + 'the drawing, sent on purpose', MachineIs) > 0 then
    SetLength(MachineIs, Pos(LineEnding + 'the drawing, sent on purpose', MachineIs));
  if FD <> nil then SheetName_ := FD.Name else SheetName_ := '-';
  Sending := TSendForm.CreateSending(Self, 'Sending your report');
  try
    { The whole summary is laid out first with files listed as waiting; then
      each file's row changes as it is encrypted, sent and arrives.  The
      facts are read back from the report text, so the summary cannot say
      something the report does not. }
    FileRep := Sending.AddFile(IfThen(HasDrawing, 'Report and drawing', 'Report'),
      Name_, KB(Length(Body)));
    if WantShot then
      FilePic := Sending.AddFile('Picture', ChangeFileExt(Name_, '.png'), KB(Shot.Size))
    else
      FilePic := Sending.AddFile('Picture', 'none', '-', ssNone);

    { machine and program first: on a bench of test machines that is what
      is looked for }
    Sending.Fact('This machine', 'System', MachineLine('os'));
    Sending.Fact('This machine', 'Computer', MachineLine('machine'));
    Sending.Fact('This machine', 'Processor', MachineLine('cpu'));
    Sending.Fact('This machine', 'Memory', MachineLine('ram'));
    Sending.Fact('This machine', 'Graphics', MachineLine('graphics'));
    Sending.Fact('This machine', 'Display', MachineLine('display'));
    Sending.Fact('This machine', 'Locale', MachineLine('locale'));

    Sending.Fact('The program', 'Version', BodyLine('version'));
    Sending.Fact('The program', 'Toolkit', MachineLine('toolkit'));
    Sending.Fact('The program', 'Memory', MachineLine('program memory'));
    Sending.Fact('The program', 'Running', MachineLine('program'));
    Sending.Fact('The program', 'Working in', Tok('mode=') + ' mode, ' +
      Tok('view=') + ' view, ' + Tok('units=') + ', ' + Tok('theme=') + ' theme');
    Sending.Fact('The program', 'Drawing area', Tok('screen=') +
      ' at scaling ' + Tok('scaling='));
    Sending.Fact('The program', 'Network', Tok('net='));

    Sending.Fact('The report', 'Your words', IfThen(Note = '', 'nothing written',
      Format('%d characters', [Length(Note)])));
    Sending.Fact('The report', 'The drawing', IfThen(HasDrawing,
      Format('included - %d things', [NThings]), 'not included'));
    Sending.Fact('The report', 'Sheet', SheetName_);
    Sending.Fact('The report', 'The picture', IfThen(WantShot,
      'the program window, ' + KB(Shot.Size), 'none'));
    Sending.Fact('The report', 'Also in it', 'the tool, the view, the last ' +
      'few dozen things that happened, and this machine.  Nothing about you.');
    Sending.Fact('The report', 'When', BodyLine('when'));

    Sending.Stage('Preparing the report',
      Format('%s of text: what you wrote, the state of the program%s.',
        [KB(Length(Body)),
         IfThen(HasDrawing, ', and the drawing', '')]), 15);
    { the pauses are deliberate (see above); encrypting happens inside
      SendReport and would otherwise be invisible }
    Sending.FileState(FileRep, ssEncrypting);
    Sending.Stage('Encrypting the report',
      Format('Encrypting %s to a key only we hold - nothing in it can be ' +
        'read on the way, whatever happens to the postbox it travels through.',
        [KB(Length(Body))]), 28, 1600);
    Sending.FileState(FileRep, ssSending);
    Sending.Stage('Sending the report', Name_, 40);
    if SendReport(Name_, Body, Err) then
    begin
      Result := True;
      Sending.FileState(FileRep, ssSent, KB(LastSealedBytes));
      Total := LastSealedBytes;
      NSent := 1;
      FCmdMsg := 'Report sent - thank you.  (' + Name_ + ')';
      { The picture goes as its own file with the report's name, so they
        pair up.  If it fails, the report has already gone. }
      if WantShot then
        try
          Sending.FileState(FilePic, ssEncrypting);
          Sending.Stage('Encrypting and sending the picture',
            Format('%s of screenshot, as %s', [KB(Shot.Size),
              ChangeFileExt(Name_, '.png')]), 75);
          Sending.FileState(FilePic, ssSending);
          Shot.Position := 0;
          if not SendBinary(ChangeFileExt(Name_, '.png'), Shot, 'image/png',
               ShotErr) then
          begin
            FCmdMsg := FCmdMsg + '  (the picture did not go: ' + ShotErr + ')';
            Sending.FileState(FilePic, ssFailed, '', ShotErr);
          end
          else
          begin
            Sending.FileState(FilePic, ssSent, KB(LastSealedBytes));
            Total := Total + LastSealedBytes;
            Inc(NSent);
          end;
        except
          on Ex: Exception do
          begin
            FCmdMsg := FCmdMsg + '  (no picture: ' + Ex.ClassName + ')';
            Sending.FileState(FilePic, ssFailed, '', Ex.ClassName);
          end;
        end;
      Sending.Finish('Sent - thank you',
        Format('%d %s, %s, encrypted before leaving this computer.',
          [NSent, IfThen(NSent = 1, 'file', 'files'), KB(Total)]),
        '<h3>How it traveled</h3><ul>' +
        '<li><b>Encrypted on this computer</b>, before anything left it, to ' +
        'a key only the project holds.</li>' +
        '<li>The postbox it passes through sees a name and a size, and ' +
        'nothing that can be read.</li>' +
        '<li><b>A copy of what you sent</b> is kept on this computer, not ' +
        'encrypted, so you can see exactly what went:<br><code>' +
        Esc(AppDataDir + 'reports-sent') + '</code></li></ul>', True);
    end
    else
    begin
      FCmdMsg := 'The report could not be sent - ' + Err;
      Sending.FileState(FileRep, ssFailed, '', Err);
      if WantShot then Sending.FileState(FilePic, ssFailed, '', 'not tried');
      Sending.Finish('The report did not go', Err,
        '<h3>What happened</h3><ul>' +
        '<li>' + Esc(Err) + '</li>' +
        '<li><b>Nothing is lost and nothing is broken</b> - it just did not ' +
        'send.</li>' +
        '<li>A copy of the report is kept on this computer:<br><code>' +
        Esc(AppDataDir + 'reports-sent') + '</code></li>' +
        '<li>The help button has the project page if you would rather say ' +
        'it there.</li></ul>', False);
    end;
  finally
    Sending.Free;
  end;
  finally
    Shot.Free;
  end;
  finally
    ShotBmp.Free;
  end;
  pbCmd.Invalidate;
end;

{ how many things are in the drawing a report would carry }
function TMainForm.DocThings(const DocFile: string): Integer;
var
  L: TStringList;
  I: Integer;
begin
  Result := FD.Doc.Live;
  if (DocFile = '') or not FileExists(DocFile) then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(DocFile);
      Result := 0;
      for I := 0 to L.Count - 1 do
        if (Copy(L[I], 1, 5) = 'LINE ') or (Copy(L[I], 1, 5) = 'FACE ') or
           (Copy(L[I], 1, 4) = 'ARC ') or (Copy(L[I], 1, 5) = 'TEXT ') or
           (Copy(L[I], 1, 4) = 'DIM ') or (Copy(L[I], 1, 6) = 'GUIDE ') then
          Inc(Result);
    except
      Result := FD.Doc.Live;
    end;
  finally
    L.Free;
  end;
end;

{ Lay a piece out flat.  A click picks it, not the selection: click any face
  and the whole solid is used. }
procedure TMainForm.StartUnfold;
begin
  FUnfoldPick := True;
  pbScreen.Cursor := crCross;
  FCmdMsg := 'Click any face of the piece to lay it out flat.  Esc to stop.';
  pbCmd.Invalidate;
end;

procedure TMainForm.UnfoldAt(SX, SY: Integer);
var
  F: Integer;
  Faces: TIntArray;
  Pat: TFlatPattern;
begin
  FUnfoldPick := False;
  F := FD.Doc.HitFace(Proj, SX, SY);
  if F < 0 then
  begin
    FCmdMsg := 'Nothing there to lay out - click a face of the piece.';
    pbCmd.Invalidate;
    Exit;
  end;
  Faces := SolidFaces(FD.Doc, F);
  if Length(Faces) = 0 then
  begin
    FCmdMsg := 'That face is not part of anything to lay out.';
    pbCmd.Invalidate;
    Exit;
  end;
  Pat := Unfold(FD.Doc, Faces);
  if not Pat.Ok then
  begin
    FCmdMsg := 'It could not be laid out - ' + Pat.Why;
    pbCmd.Invalidate;
    Exit;
  end;
  Trail(Format('unfolded %d panels', [Pat.Laid]));
  FCmdMsg := Format('Laid out: %d panels, sheet %s x %s',
    [Pat.Laid, FormatLen(Pat.MaxX - Pat.MinX, FD.Units),
     FormatLen(Pat.MaxY - Pat.MinY, FD.Units)]);
  pbCmd.Invalidate;
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  ShowFlatPattern(Pat, FD.Units, 'Flat pattern');
end;

{ A crash last time leaves a report behind.  Offer to send it, opening it
  for reading first, since it carries file paths. }
procedure TMainForm.OfferCrashReport(JustNow: Boolean);
var
  Fn: string;
  L: TStringList;

  { Move a crash report aside under a timestamped name.  A fixed name fails
    the second time on Windows (the rename target exists) and the report is
    offered again on every start. }
  procedure KeepAside(const Base: string);
  var
    Dst: string;
  begin
    Dst := Base + '.' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.kept';
    if FileExists(Dst) then DeleteFile(Dst);
    if RenameFile(Base, Dst) then
      FCmdMsg := 'Kept it: ' + ExtractFileName(Dst)
    else
    begin
      { cannot even be moved aside: let it go rather than ask forever }
      DeleteFile(Base);
      FCmdMsg := 'That crash report could not be kept, so it was cleared.';
    end;
  end;

begin
  Fn := ExtractFilePath(ExpandFileName(ParamStr(0))) + 'heckers-sketch-crash.txt';
  if not FileExists(Fn) then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(Fn);
    except
      Exit;
    end;
    if L.Count = 0 then Exit;
    { Sent through the same postbox as a hand-written report, so no GitHub
      account is needed.  Offered, not assumed. }
    case MessageDlg(IfThen(JustNow, 'Something went wrong', 'It crashed last time'),
           IfThen(JustNow,
             'Something just went wrong inside the program.  It is still ' +
             'running, and a report has been written.',
             'There is a crash report from a previous run.') + #13#10#13#10 +
           'Send it?  You get to say what you were doing first, and to see ' +
           'what is being sent.  Nothing goes anywhere until you press Send.',
           mtConfirmation, [mbYes, mbNo], 0) of
      mrYes:
        { Delete the local copies only after a successful send, so a failed
          send can be retried.  Renaming onto ".sent" fails on Windows when
          that name already exists. }
        if ReportBug(L.Text, Fn + '.png', Fn + '.hsk') then
        begin
          DeleteFile(Fn);
          DeleteFile(Fn + '.png');
          DeleteFile(Fn + '.hsk');
          FCmdMsg := FCmdMsg + '  It will not ask about this one again.';
        end
        else
          KeepAside(Fn);
    else
      KeepAside(Fn);
    end;
  finally
    L.Free;
  end;
end;

{ Shaking the mouse picks the plane: sideways lays the shape down, up and
  down stands it up.  The plane latches; Esc releases it.  Needs four
  reversals of a dozen pixels or more within 0.75 s, mostly on one axis;
  ordinary drawing never does that. }
procedure TMainForm.ShakeWatch(X, Y: Integer);
const
  JERK_PX  = 12;
  JERK_N   = 4;
  JERK_MS  = 750;
var
  Now64: QWord;
  D, Sg: Integer;
  Was: TPlane;
begin
  { not the dimension tool: its line follows the pointer (see DimOffset3) }
  if not (FTool in [ptLine, ptRect, ptCircle, ptArc]) then Exit;
  if FD.View = vkPlan then Exit;        // only one plane makes sense there

  Now64 := GetTickCount64;
  if Now64 - FShTX > JERK_MS then FShNX := 0;
  if Now64 - FShTY > JERK_MS then FShNY := 0;

  D := X - FShX;
  if Abs(D) >= JERK_PX then
  begin
    if D > 0 then Sg := 1 else Sg := -1;
    if (FShDirX <> 0) and (Sg <> FShDirX) then
    begin
      Inc(FShNX);
      FShTX := Now64;
    end;
    FShDirX := Sg;
    FShX := X;
  end;

  D := Y - FShY;
  if Abs(D) >= JERK_PX then
  begin
    if D > 0 then Sg := 1 else Sg := -1;
    if (FShDirY <> 0) and (Sg <> FShDirY) then
    begin
      Inc(FShNY);
      FShTY := Now64;
    end;
    FShDirY := Sg;
    FShY := Y;
  end;

  if (FShNX < JERK_N) and (FShNY < JERK_N) then Exit;

  Was := FD.Plane;
  if FShNY >= FShNX then
  begin
    { up and down: stand it up, on whichever upright plane a straight-up drag
      would choose, so it agrees with dragging }
    FD.Plane := PlaneByDrag(Proj, FCur, FMouseSX, FMouseSY - 200, plXZ, 1.0);
    if FD.Plane = plXY then FD.Plane := plXZ;
    FCmdMsg := 'Standing it up - ' + PlaneName + '.  Shake sideways to lay ' +
      'it flat, Esc to follow faces again.';
  end
  else
  begin
    FD.Plane := plXY;
    FCmdMsg := 'Laying it flat.  Shake up and down to stand it up, Esc to ' +
      'follow faces again.';
  end;
  FPlaneHeld := True;
  FShNX := 0;
  FShNY := 0;

  if FD.Plane <> Was then
  begin
    RepaintPaper;
    RenderInk;
    RecomposeAll;
  end;
  FScreenDirty := True;
  pbCmd.Invalidate;
end;

{ Everything being drawn, as screen points, so the hold-to-cancel strain is
  laid along the whole shape (a rectangle strains as a rectangle), not along
  one strand from the first corner. }
function TMainForm.StrainOutline(out Pts: TPointFArray): Boolean;
var
  RectPrev: TP3Array;
  K: Integer;
  R: Double;
  Nm: TP3;
  ArcPl: TPlane;
  ArcC: TP3;
  ArcR, ArcA0, ArcSw, ArcBulge: Double;
begin
  Pts := nil;
  Result := False;
  case FTool of
    ptRect:
      if FStage = 1 then
      begin
        RectPrev := RectCorners(FP1, RectTarget, FD.Plane);
        SetLength(Pts, 5);
        for K := 0 to 3 do Pts[K] := ScreenOf(RectPrev[K]);
        Pts[4] := Pts[0];
      end;
    ptCircle:
      if FStage = 1 then
      begin
        R := Dist(FP1, FCur);
        if R > 1E-9 then
        begin
          SetLength(Pts, FSidesCircle + 1);
          for K := 0 to FSidesCircle do
            Pts[K] := ScreenOf(ArcPoint(FP1, R,
              2 * Pi * K / FSidesCircle, FD.Plane));
        end;
      end;
    ptOffset:
      if FStage = 1 then
      begin
        RectPrev := OffsetPreview;
        if Length(RectPrev) >= 3 then
        begin
          SetLength(Pts, Length(RectPrev) + 1);
          for K := 0 to High(RectPrev) do Pts[K] := ScreenOf(RectPrev[K]);
          Pts[High(Pts)] := Pts[0];
        end;
      end;
    ptPush, ptDrill:
      { the face where it would have landed, straining and going back }
      if (FStage = 1) and (FPushFace >= 0) and (FPushFace < FD.Doc.Live) then
      begin
        RectPrev := FD.Doc[FPushFace].Poly;
        if Length(RectPrev) >= 3 then
        begin
          R := PushDistance;
          Nm := FD.Doc.FaceNormal(FPushFace);
          SetLength(Pts, Length(RectPrev) + 1);
          for K := 0 to High(RectPrev) do
            Pts[K] := ScreenOf(P3(RectPrev[K].X + Nm.X * R,
                                  RectPrev[K].Y + Nm.Y * R,
                                  RectPrev[K].Z + Nm.Z * R));
          Pts[High(Pts)] := Pts[0];
        end;
      end;
    ptArc:
      { the curve itself, not the chord under it }
      if FStage = 2 then
      begin
        if ArcPicks(FCur, ArcPl, ArcC, ArcR, ArcA0, ArcSw, ArcBulge) then
        begin
          SetLength(Pts, FSidesArc + 1);
          for K := 0 to FSidesArc do
            Pts[K] := ScreenOf(ArcPoint(ArcC, ArcR,
              ArcA0 + ArcSw * K / FSidesArc, ArcPl));
        end;
      end;
  end;
  { anything else (a line, an arc still being aimed, a move) is one strand }
  if Length(Pts) < 2 then
  begin
    SetLength(Pts, 2);
    Pts[0] := ScreenOf(FP1);
    Pts[1] := PtF(FMouseSX, FMouseSY);
  end;
  Result := True;
end;

{ The whole outline under tension: each side bows away from the middle and
  trembles harder as it nears the break.  One burst and one caption at the
  middle, since it is one gesture destroying one thing. }
procedure TMainForm.PaintStrainPath(C: TCanvas; const Pts: TPointFArray;
  T: Single);
var
  I: Integer;
  CX, CY: Double;
begin
  if Length(Pts) < 2 then Exit;
  CX := 0;
  CY := 0;
  for I := 0 to High(Pts) do
  begin
    CX := CX + Pts[I].X / Length(Pts);
    CY := CY + Pts[I].Y / Length(Pts);
  end;
  for I := 0 to High(Pts) - 1 do
    PaintStrainSeg(C, Pts[I], Pts[I + 1], T, Length(Pts) > 2, CX, CY);
  PaintStrainMark(C, CX, CY, T);
end;

{ The rubber band leaned on until it breaks: hold the button still and it
  stiffens, bows, thins and cracks, then the run is released.  T runs 0 to 1
  from when the press stops looking like a click to the break. }
procedure TMainForm.PaintStrain(C: TCanvas; const A, B: TPointF; T: Single);
var
  P: TPointFArray;
begin
  SetLength(P, 2);
  P[0] := A;
  P[1] := B;
  PaintStrainPath(C, P, T);
end;

{ One side of it: bows away from CX,CY when the shape has a middle, to one
  side when it is a single strand. }
procedure TMainForm.PaintStrainSeg(C: TCanvas; const A, B: TPointF; T: Single;
  Outward: Boolean; CX, CY: Double);
var
  I, N, W: Integer;
  MX, MY, DX, DY, L, NX, NY, Bow, Sh: Double;
  P0, P1: TPointF;
  Col: TPix;
begin
  T := EnsureRange(T, 0, 1);
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  L := Sqrt(DX * DX + DY * DY);
  if L < 2 then Exit;
  NX := -DY / L;
  NY := DX / L;
  { away from the middle, so the whole shape swells consistently }
  if Outward and
     (NX * ((A.X + B.X) / 2 - CX) + NY * ((A.Y + B.Y) / 2 - CY) < 0) then
  begin
    NX := -NX;
    NY := -NY;
  end;

  { it bows away from the pull and trembles harder the nearer it gets }
  Bow := 8 * FUIScale * Sin(T * Pi) * 0.9;
  Sh := 2.4 * FUIScale * T * T;
  MX := (A.X + B.X) / 2 + NX * Bow + (Random - 0.5) * 2 * Sh;
  MY := (A.Y + B.Y) / 2 + NY * Bow + (Random - 0.5) * 2 * Sh;

  { From ink color to hot red early, as a warning.  It gets bolder, not
    thinner: about to let go looks strained, not frail. }
  Col := MixPix(AnnotColor, Pix(230, 38, 28), Power(T, 0.7));
  C.Pen.Style := psSolid;
  C.Pen.Color := PixToColor(Col);

  N := 12;
  for I := 0 to N - 1 do
  begin
    P0 := QuadAt(A, PtF(MX, MY), B, I / N);
    P1 := QuadAt(A, PtF(MX, MY), B, (I + 1) / N);
    { bold all over; only at the very end does the middle give }
    W := Round((1.6 + 4.2 * T) * FUIScale);
    if T > 0.7 then
      W := Round(W * (1 - 0.75 * ((T - 0.7) / 0.3) * Sin((I + 0.5) / N * Pi)));
    C.Pen.Width := Max(1, W);
    C.MoveTo(Round(P0.X), Round(P0.Y));
    C.LineTo(Round(P1.X), Round(P1.Y));
  end;

  C.Pen.Width := 1;
end;

{ The shards and the warning, once, at the middle of what is being destroyed
  (not once per side). }
procedure TMainForm.PaintStrainMark(C: TCanvas; CX, CY: Double; T: Single);
var
  I: Integer;
  Ang, R: Double;
  Col: TPix;
  Cap: string;
  Sz: TSize;
begin
  T := EnsureRange(T, 0, 1);
  Col := MixPix(AnnotColor, Pix(230, 38, 28), Power(T, 0.7));
  C.Pen.Style := psSolid;
  C.Pen.Color := PixToColor(Col);

  { at the very end it comes apart: shards off the middle }
  if T > 0.78 then
  begin
    C.Pen.Width := Max(1, Round(2 * FUIScale));
    R := (T - 0.78) / 0.22 * 13 * FUIScale;
    for I := 0 to 5 do
    begin
      Ang := I * Pi / 3 + T * 3;
      C.MoveTo(Round(CX + Cos(Ang) * R * 0.35), Round(CY + Sin(Ang) * R * 0.35));
      C.LineTo(Round(CX + Cos(Ang) * R), Round(CY + Sin(Ang) * R));
    end;
  end;

  { announce it: a destructive gesture met by accident looks like a bug }
  if T > 0.12 then
  begin
    { worded for what happens to this tool's work: a push that never
      happened puts the face back rather than throwing anything away }
    if FTool = ptLine then
    begin
      if T > 0.7 then Cap := 'LETTING GO...'
      else Cap := 'keep holding to snap the line off';
    end
    else if FTool in [ptPush, ptDrill, ptOffset] then
    begin
      if T > 0.7 then Cap := 'PUTTING IT BACK...'
      else Cap := 'changed your mind?  keep holding';
    end
    else
    begin
      if T > 0.7 then Cap := 'THROWING IT AWAY...'
      else Cap := 'made a mess?  keep holding';
    end;
    UIFont(C, 9, T > 0.7, Col);
    C.Brush.Style := bsSolid;
    C.Brush.Color := PixToColor(Theme.Screen1);
    Sz := C.TextExtent(Cap);
    C.TextOut(Round(CX - Sz.cx / 2), Round(CY - Sz.cy - 14 * FUIScale), Cap);
    C.Brush.Style := bsClear;
  end;
  C.Pen.Width := 1;
end;

{ The ends recoiling after the break: brief, and the only sign the release
  was a break and not a misclick. }
procedure TMainForm.PaintSnapRecoil(C: TCanvas);
var
  I: Integer;
  T, DX, DY, L, Ang, R: Double;
begin
  if FSnapT <= 0 then Exit;
  T := 1 - FSnapT / SNAP_RECOIL;          // 0 at the break, 1 at the end
  C.Pen.Style := psSolid;
  { Only a line has two ends to recoil; rectangles and circles get just the
    burst, or a stray strand flashes across the shape. }
  if FSnapEnds then
  begin
    DX := FSnapB.X - FSnapA.X;
    DY := FSnapB.Y - FSnapA.Y;
    L := Sqrt(DX * DX + DY * DY);
    if L >= 2 then
    begin
      DX := DX / L;
      DY := DY / L;
      C.Pen.Width := Max(1, Round(2 * FUIScale * (1 - T)));
      C.Pen.Color := PixToColor(MixPix(AnnotColor, Theme.Screen1, T));
      L := L * 0.30 * (1 - T);
      C.MoveTo(Round(FSnapA.X), Round(FSnapA.Y));
      C.LineTo(Round(FSnapA.X + DX * L), Round(FSnapA.Y + DY * L));
      C.MoveTo(Round(FSnapB.X), Round(FSnapB.Y));
      C.LineTo(Round(FSnapB.X - DX * L), Round(FSnapB.Y - DY * L));
    end;
  end;
  C.Pen.Width := Max(1, Round(2 * FUIScale * (1 - T)));
  { the burst where it broke, thrown outward and fading }
  C.Pen.Color := PixToColor(MixPix(Pix(230, 38, 28), Theme.Screen1, T));
  for I := 0 to 5 do
  begin
    Ang := I * Pi / 3 + 0.4;
    R := (10 + 26 * T) * FUIScale;
    C.MoveTo(Round(FSnapM.X + Cos(Ang) * R * 0.5),
             Round(FSnapM.Y + Sin(Ang) * R * 0.5));
    C.LineTo(Round(FSnapM.X + Cos(Ang) * R), Round(FSnapM.Y + Sin(Ang) * R));
  end;
  C.Pen.Width := 1;
end;

{ The points worth aiming at on the face under the cursor: corners, edge
  middles and the face middle (circles are often struck from a panel's
  center).  Small and pale: an offer, not a confirmation. }
procedure TMainForm.PaintFacePoints(C: TCanvas; Face: Integer);
var
  Pts: TPointFArray;
  I, J, N, R: Integer;
  CX, CY: Double;

  procedure Dot(X, Y: Double; Big: Boolean);
  var
    D: Integer;
  begin
    if Big then D := R + 1 else D := R;
    if (X < -20) or (Y < -20) or
       (X > pbScreen.Width + 20) or (Y > pbScreen.Height + 20) then Exit;
    C.Ellipse(Round(X) - D, Round(Y) - D, Round(X) + D + 1, Round(Y) + D + 1);
  end;

begin
  if Face < 0 then Exit;
  Pts := FD.Doc.Outline(Proj, Face);
  N := Length(Pts);
  if N < 3 then Exit;
  { a pulled circle has many sides; dots on all of them would be noise }
  if N > 16 then Exit;

  R := Max(2, Round(2.5 * FUIScale));
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.Pen.Color := PixToColor(Pix(90, 120, 160));
  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(Pix(210, 228, 245));

  CX := 0; CY := 0;
  for I := 0 to N - 1 do
  begin
    J := (I + 1) mod N;
    Dot(Pts[I].X, Pts[I].Y, False);                              // corner
    Dot((Pts[I].X + Pts[J].X) / 2, (Pts[I].Y + Pts[J].Y) / 2, False);  // middle
    CX := CX + Pts[I].X;
    CY := CY + Pts[I].Y;
  end;
  { the face middle, a size up so it reads as the special one }
  C.Brush.Color := PixToColor(Pix(255, 246, 210));
  Dot(CX / N, CY / N, True);

  C.Brush.Style := bsClear;
  C.Pen.Width := 1;
end;

{ The mark that says what the cursor found.  Painted after the cursor
  overlay, which blits a square of artwork back and would wipe it. }
procedure TMainForm.PaintSnapMarker(C: TCanvas; SX, SY: Integer);
var
  MarkPix: TPix;
  MarkD: Integer;
begin
  { One small solid diamond, as in SketchUp, colored by what was found (see
    SnapMarkPix, which the command bar shares). }
  MarkPix := SnapMarkPix;

  C.Pen.Width := 1;
  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(MarkPix);
  if FSnapKind = snGrid then
  begin
    { the grid is everywhere, so it gets a dot, not a diamond }
    C.Pen.Color := PixToColor(MarkPix);
    C.FillRect(SX - 2, SY - 2, SX + 3, SY + 3);
  end
  else if FSnapKind <> snNone then
  begin
    MarkD := Round(5 * FUIScale);
    { a thin dark rim so the diamond reads over pale artwork }
    C.Pen.Color := PixToColor(Pix(24, 24, 28));
    C.Polygon([Point(SX, SY - MarkD), Point(SX + MarkD, SY),
               Point(SX, SY + MarkD), Point(SX - MarkD, SY)]);
    { hollow for a sub-midpoint: the middle of a piece, not the whole line }
    if FSnapKind = snSubMid then
    begin
      C.Brush.Color := PixToColor(Theme.Screen1);
      C.Pen.Color := PixToColor(Theme.Screen1);
      C.Polygon([Point(SX, SY - MarkD + 2), Point(SX + MarkD - 2, SY),
                 Point(SX, SY + MarkD - 2), Point(SX - MarkD + 2, SY)]);
    end;
  end;
  C.Brush.Style := bsClear;
  C.Pen.Width := 1;
end;

{ The eraser's warning across a face: hatching in the face's own plane, in
  short pieces, each drawn only if its middle is inside the face (outside any
  hole) and not hidden per the depth buffer.  Hatching leaves the lines on
  the face readable, and depth keeps it from spilling over things in front. }
procedure TMainForm.WashFace(C: TCanvas; Face: Integer; const Col: TPix);
const
  STEP_PX = 7;      // between hatch lines
  PIECE_PX = 6;     // along each one
var
  Nm, AU, AV, O, P, Look: TP3;
  Poly: TP3Array;
  UV: array of TPointF;
  HUV: array of array of TPointF;
  I, J, H, N, Steps, Pieces: Integer;
  MinU, MaxU, MinV, MaxV, Ppx, StepW, PieceW, Diag, T0, T1, A, B: Double;
  U0, V0, DU, DV, Len: Double;
  SA, SB: TPointF;
  Ink: TArtSurface;
  Zb, Dp: Double;

  function InFace(U, V: Double): Boolean;
  var
    Q, R, W: Integer;
    Inside: Boolean;
  begin
    Inside := False;
    R := N - 1;
    for Q := 0 to N - 1 do
    begin
      if ((UV[Q].Y > V) <> (UV[R].Y > V)) and
         (U < (UV[R].X - UV[Q].X) * (V - UV[Q].Y) / (UV[R].Y - UV[Q].Y) + UV[Q].X) then
        Inside := not Inside;
      R := Q;
    end;
    if Inside then
      for W := 0 to High(HUV) do
      begin
        R := High(HUV[W]);
        for Q := 0 to High(HUV[W]) do
        begin
          if ((HUV[W][Q].Y > V) <> (HUV[W][R].Y > V)) and
             (U < (HUV[W][R].X - HUV[W][Q].X) * (V - HUV[W][Q].Y) /
                  (HUV[W][R].Y - HUV[W][Q].Y) + HUV[W][Q].X) then
            Inside := not Inside;
          R := Q;
        end;
      end;
    Result := Inside;
  end;

  function Seen(const W: TP3): Boolean;
  var
    SP: TPointF;
  begin
    Result := True;
    if (Ink = nil) or not Ink.DepthOn then Exit;
    SP := ScreenOf(W);
    Zb := Ink.DepthAt(Round(SP.X), Round(SP.Y));
    if Zb < -1E29 then Exit;
    Dp := Dot3(W, Look);
    Result := Zb <= Dp + 1E-3 * (1 + Abs(Dp));
  end;

begin
  if (Face < 0) or (Face >= FD.Doc.Live) or (FD.Doc[Face].Kind <> ekFace) then
    Exit;
  Poly := FD.Doc[Face].Poly;
  N := Length(Poly);
  if N < 3 then Exit;
  Ink := FInk;
  Look := ViewDir(Proj);
  Nm := Norm3(FD.Doc.FaceNormal(Face));
  AxesFromNormal(Nm, AU, AV);
  O := Poly[0];

  { the face and its windows in the plane's own coordinates }
  SetLength(UV, N);
  MinU := 1E30; MaxU := -1E30; MinV := 1E30; MaxV := -1E30;
  for I := 0 to N - 1 do
  begin
    P := P3(Poly[I].X - O.X, Poly[I].Y - O.Y, Poly[I].Z - O.Z);
    UV[I] := PtF(Dot3(P, AU), Dot3(P, AV));
    MinU := Min(MinU, UV[I].X); MaxU := Max(MaxU, UV[I].X);
    MinV := Min(MinV, UV[I].Y); MaxV := Max(MaxV, UV[I].Y);
  end;
  SetLength(HUV, Length(FD.Doc[Face].Holes));
  for H := 0 to High(HUV) do
  begin
    SetLength(HUV[H], Length(FD.Doc[Face].Holes[H]));
    for I := 0 to High(HUV[H]) do
    begin
      P := P3(FD.Doc[Face].Holes[H][I].X - O.X, FD.Doc[Face].Holes[H][I].Y - O.Y,
              FD.Doc[Face].Holes[H][I].Z - O.Z);
      HUV[H][I] := PtF(Dot3(P, AU), Dot3(P, AV));
    end;
  end;

  { the size of a screen pixel in the plane, so hatch density holds at any
    zoom }
  SA := ScreenOf(O);
  SB := ScreenOf(P3(O.X + AU.X, O.Y + AU.Y, O.Z + AU.Z));
  Ppx := Sqrt(Sqr(SB.X - SA.X) + Sqr(SB.Y - SA.Y));
  if Ppx < 1E-6 then Exit;
  StepW := STEP_PX * FUIScale / Ppx;
  PieceW := PIECE_PX * FUIScale / Ppx;

  C.Pen.Style := psSolid;
  C.Pen.Color := PixToColor(Col);
  C.Pen.Width := 1;

  { diagonals across the bounding box, each walked in pieces }
  Diag := (MaxU - MinU) + (MaxV - MinV);
  Steps := Ceil(Diag / StepW);
  if Steps > 400 then Exit;          // a face the size of the screen at 1:1
  for I := 0 to Steps do
  begin
    { the line u + v = MinU + MinV + I*StepW, clipped to the box }
    T0 := MinU + MinV + I * StepW;
    U0 := Max(MinU, T0 - MaxV);  V0 := T0 - U0;
    T1 := Min(MaxU, T0 - MinV);
    if T1 <= U0 then Continue;
    DU := 1; DV := -1;
    Len := (T1 - U0) * Sqrt(2);
    Pieces := Max(1, Ceil(Len / PieceW));
    for J := 0 to Pieces - 1 do
    begin
      A := U0 + (T1 - U0) * J / Pieces;
      B := U0 + (T1 - U0) * (J + 1) / Pieces;
      { the middle of the piece decides for the whole piece }
      if not InFace((A + B) / 2, V0 - ((A + B) / 2 - U0)) then Continue;
      P := P3(O.X + AU.X * ((A + B) / 2) + AV.X * (V0 - ((A + B) / 2 - U0)),
              O.Y + AU.Y * ((A + B) / 2) + AV.Y * (V0 - ((A + B) / 2 - U0)),
              O.Z + AU.Z * ((A + B) / 2) + AV.Z * (V0 - ((A + B) / 2 - U0)));
      if not Seen(P) then Continue;
      SA := ScreenOf(P3(O.X + AU.X * A + AV.X * (V0 - (A - U0)),
                        O.Y + AU.Y * A + AV.Y * (V0 - (A - U0)),
                        O.Z + AU.Z * A + AV.Z * (V0 - (A - U0))));
      SB := ScreenOf(P3(O.X + AU.X * B + AV.X * (V0 - (B - U0)),
                        O.Y + AU.Y * B + AV.Y * (V0 - (B - U0)),
                        O.Z + AU.Z * B + AV.Z * (V0 - (B - U0))));
      C.MoveTo(Round(SA.X), Round(SA.Y));
      C.LineTo(Round(SB.X), Round(SB.Y));
    end;
  end;
end;

{ The held plane, drawn where you are working: two short lines along the
  plane's own directions in their axis colors (red and blue is upright, red
  and green flat).  A rubber band cannot show a plane; coloring it by the
  plane's normal would give the one color the line never runs along. }
procedure TMainForm.PaintHeldPlane(C: TCanvas);
const
  ARM = 46;
var
  AU, AV, P: TP3;
  I: Integer;
  D: TP3;
  S0, S1: TPointF;
  Sc: Double;
begin
  if not FPlaneHeld then Exit;
  if FD.Plane = plFree then Exit;
  if FD.View <> vkOrbit then Exit;   { flat views show it by being flat }
  PlaneAxes(FD.Plane, AU, AV);
  if FStage > 0 then P := FP1 else P := FCur;
  { fixed length on screen, so it is the same cue at any zoom }
  Sc := ARM * FUIScale / Max(1E-6, Ppu);
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  for I := 0 to 1 do
  begin
    if I = 0 then D := AU else D := AV;
    C.Pen.Color := PixToColor(AxisPix(AxisAlong(P3(0, 0, 0), D)));
    S0 := ScreenOf(P3(P.X - D.X * Sc, P.Y - D.Y * Sc, P.Z - D.Z * Sc));
    S1 := ScreenOf(P3(P.X + D.X * Sc, P.Y + D.Y * Sc, P.Z + D.Z * Sc));
    C.MoveTo(Round(S0.X), Round(S0.Y));
    C.LineTo(Round(S1.X), Round(S1.Y));
  end;
end;

{ The guide under the cursor in blue: a ring round a guide point, or the
  dashed line clipped to the window for a guide line. }
procedure TMainForm.PaintGuideHover(C: TCanvas; I: Integer);
var
  E: TWorkEnt;
  D: TP3;
  L: Double;
  PA, PB: TPointF;
  R: Integer;
begin
  if (I < 0) or (I >= FD.Doc.Live) or (FD.Doc[I].Kind <> ekGuide) then Exit;
  E := FD.Doc[I];
  C.Brush.Style := bsClear;
  C.Pen.Color := PixToColor(Pix(60, 120, 235));
  C.Pen.Width := Max(1, Round(FUIScale));
  if Dist(E.A, E.B) < 1E-9 then
  begin
    { a guide point: a ring the size it is drawn }
    PA := ScreenOf(E.A);
    if IsNan(PA.X) or IsNan(PA.Y) then Exit;
    R := Max(4, Round(5 * FUIScale));
    C.Pen.Style := psSolid;
    C.Ellipse(Round(PA.X) - R, Round(PA.Y) - R, Round(PA.X) + R, Round(PA.Y) + R);
    Exit;
  end;
  D := P3(E.B.X - E.A.X, E.B.Y - E.A.Y, E.B.Z - E.A.Z);
  L := Sqrt(Sqr(D.X) + Sqr(D.Y) + Sqr(D.Z));
  if L < 1E-9 then Exit;
  PA := ScreenOf(P3(E.A.X - D.X / L * 5000, E.A.Y - D.Y / L * 5000,
                    E.A.Z - D.Z / L * 5000));
  PB := ScreenOf(P3(E.A.X + D.X / L * 5000, E.A.Y + D.Y / L * 5000,
                    E.A.Z + D.Z / L * 5000));
  if IsNan(PA.X) or IsNan(PA.Y) or IsNan(PB.X) or IsNan(PB.Y) or
     IsInfinite(PA.X) or IsInfinite(PA.Y) or IsInfinite(PB.X) or IsInfinite(PB.Y) then Exit;
  { canvas coordinates are integers; a point 5000' away must be clamped }
  PA := PtF(EnsureRange(PA.X, -32000, 32000), EnsureRange(PA.Y, -32000, 32000));
  PB := PtF(EnsureRange(PB.X, -32000, 32000), EnsureRange(PB.Y, -32000, 32000));
  C.Pen.Style := psDash;
  C.MoveTo(Round(PA.X), Round(PA.Y));
  C.LineTo(Round(PB.X), Round(PB.Y));
  C.Pen.Style := psSolid;
end;

{ The same trace as TraceOutlineVisible, into our own surface rather than an
  LCL canvas (see EnsureSelLayer for why that matters so much). }
procedure TMainForm.TraceOutlineInto(S: TArtSurface; Idx: Integer;
  const Col: TPix; PenW: Single);
const
  N = 24;
var
  W: TP3Array;
  I, K, Run0: Integer;
  A, B: TP3;
  PA, PB: TPointF;
  Vis: Boolean;
  T0, T1: Double;

  function Edge(TVis, TCov: Double): Double;
  var
    J: Integer;
    TM: Double;
  begin
    for J := 1 to 5 do
    begin
      TM := (TVis + TCov) / 2;
      if FD.Doc.HiddenAt(Proj, Lerp3(A, B, TM)) then TCov := TM else TVis := TM;
    end;
    Result := (TVis + TCov) / 2;
  end;

begin
  if (Idx < 0) or (Idx >= FD.Doc.Live) then Exit;
  { a guide is drawn to the paper's edges, not as its stored stub, and is
    never hidden }
  if (FD.Doc[Idx].Kind = ekGuide) and
     (Dist(FD.Doc[Idx].A, FD.Doc[Idx].B) > 1E-9) then
  begin
    PA := ScreenOf(FD.Doc[Idx].A);
    PB := ScreenOf(FD.Doc[Idx].B);
    if ClipToBox(PA.X, PA.Y, PB.X - PA.X, PB.Y - PA.Y,
                 S.Width, S.Height, T0, T1) then
      S.Line(PA.X + (PB.X - PA.X) * T0, PA.Y + (PB.Y - PA.Y) * T0,
             PA.X + (PB.X - PA.X) * T1, PA.Y + (PB.Y - PA.Y) * T1,
             PenW, Col, 1.0);
    Exit;
  end;

  W := FD.Doc.OutlineWorld(Idx);
  if Length(W) < 2 then Exit;
  T0 := 0;
  for I := 0 to High(W) - 1 do
  begin
    A := W[I];
    B := W[I + 1];
    Run0 := -1;
    for K := 0 to N do
    begin
      if K < N then Vis := not FD.Doc.HiddenAt(Proj, Lerp3(A, B, (K + 0.5) / N))
      else Vis := False;
      if Vis and (Run0 < 0) then
      begin
        Run0 := K;
        if K = 0 then T0 := 0 else T0 := Edge((K + 0.5) / N, (K - 0.5) / N);
      end;
      if (not Vis) and (Run0 >= 0) then
      begin
        if K = N then T1 := 1 else T1 := Edge((K - 0.5) / N, (K + 0.5) / N);
        PA := ScreenOf(Lerp3(A, B, T0));
        PB := ScreenOf(Lerp3(A, B, T1));
        S.Line(PA.X, PA.Y, PB.X, PB.Y, PenW, Col, 1.0);
        Run0 := -1;
      end;
    end;
  end;
end;

{ An entity's outline traced heavily in one color, only where it can be
  seen: each piece is tested against faces in front, so hover and selection
  do not show through walls (as in SketchUp). }
procedure TMainForm.TraceOutlineVisible(C: TCanvas; Idx: Integer; const Col: TPix;
  PenW: Integer);
const
  N = 24;
var
  W: TP3Array;
  I, K, Run0: Integer;
  A, B: TP3;
  PA, PB: TPointF;
  Vis: Boolean;
  T0, T1: Double;

  function Edge(TVis, TCov: Double): Double;
  var
    J: Integer;
    TM: Double;
  begin
    for J := 1 to 5 do
    begin
      TM := (TVis + TCov) / 2;
      if FD.Doc.HiddenAt(Proj, Lerp3(A, B, TM)) then TCov := TM else TVis := TM;
    end;
    Result := (TVis + TCov) / 2;
  end;

begin
  { A guide is stored as a point plus a unit stub but drawn to the paper's
    edges, so trace it that way or the highlight is a one-foot stub.  No
    hidden test: guides are drawn before faces and never hidden. }
  if (FD.Doc[Idx].Kind = ekGuide) and
     (Dist(FD.Doc[Idx].A, FD.Doc[Idx].B) > 1E-9) then
  begin
    PA := ScreenOf(FD.Doc[Idx].A);
    PB := ScreenOf(FD.Doc[Idx].B);
    if ClipToBox(PA.X, PA.Y, PB.X - PA.X, PB.Y - PA.Y,
                 pbScreen.Width, pbScreen.Height, T0, T1) then
    begin
      C.Pen.Color := PixToColor(Col);
      C.Pen.Width := PenW;
      C.Pen.Style := psSolid;
      C.MoveTo(Round(PA.X + (PB.X - PA.X) * T0),
               Round(PA.Y + (PB.Y - PA.Y) * T0));
      C.LineTo(Round(PA.X + (PB.X - PA.X) * T1),
               Round(PA.Y + (PB.Y - PA.Y) * T1));
      C.Pen.Width := 1;
    end;
    Exit;
  end;

  W := FD.Doc.OutlineWorld(Idx);
  if Length(W) < 2 then Exit;
  C.Pen.Color := PixToColor(Col);
  C.Pen.Width := PenW;
  C.Pen.Style := psSolid;
  T0 := 0;
  for I := 0 to High(W) - 1 do
  begin
    A := W[I];
    B := W[I + 1];
    Run0 := -1;
    for K := 0 to N do
    begin
      if K < N then Vis := not FD.Doc.HiddenAt(Proj, Lerp3(A, B, (K + 0.5) / N))
      else Vis := False;
      if Vis and (Run0 < 0) then
      begin
        Run0 := K;
        if K = 0 then T0 := 0 else T0 := Edge((K + 0.5) / N, (K - 0.5) / N);
      end;
      if (not Vis) and (Run0 >= 0) then
      begin
        if K = N then T1 := 1 else T1 := Edge((K - 0.5) / N, (K + 0.5) / N);
        PA := ScreenOf(Lerp3(A, B, T0));
        PB := ScreenOf(Lerp3(A, B, T1));
        C.MoveTo(Round(PA.X), Round(PA.Y));
        C.LineTo(Round(PB.X), Round(PB.Y));
        Run0 := -1;
      end;
    end;
  end;
  C.Pen.Width := 1;
end;

{ a heavy trace through screen points, for highlights }
procedure TMainForm.TraceOutline(C: TCanvas; const Hi: TPointFArray;
  const Col: TPix);
var
  I: Integer;
begin
  if Length(Hi) < 2 then Exit;
  C.Pen.Color := PixToColor(Col);
  C.Pen.Width := Max(3, Round(3 * FUIScale));
  C.Pen.Style := psSolid;
  C.MoveTo(Round(Hi[0].X), Round(Hi[0].Y));
  for I := 1 to High(Hi) do
    C.LineTo(Round(Hi[I].X), Round(Hi[I].Y));
  C.Pen.Width := 1;
end;

procedure TMainForm.PaintOverlay(C: TCanvas);
var
  DA, DB: TP3;
  DNote: string;
  TX, TY, TL: Double;
  ArcFil: TFillet;
  ArcTyped: Boolean;
  ArcPl: TPlane;
  ArcC, ArcU, ArcV, ArcMid, ArcFoot: TP3;
  ArcR, ArcA0, ArcSw, ArcBulge, U1, V1, U2, V2, Ln: Double;
  PA, PB: TPointF;
  ArcK: Integer;
  HintFace: Integer;
  CircI: Integer;
  CircR: Double;
  P, PPrev: TPointF;
  SX, SY, AX, AY: Integer;
  BarLen, BarPx: Double;
  R: TRect;
  GP: TPointF;
  Hi: TPointFArray;
  RectPrev: TP3Array;
  RectI: Integer;
  S1, S2, S3, S4, HTx: string;
  W1, W2, W3, W4, BoxW, BoxH, LnH, HL, HLn: Integer;
  StrainPts: TPointFArray;
  GrpBoxes: TIntArrayW;
  GI, GrpId: Integer;

  { a small red square on a picked point, SketchUp's mark }
  procedure EndMark(const P: TP3);
  var
    Q: TPointF;
    D: Integer;
  begin
    Q := ScreenOf(P);
    D := Round(3 * FUIScale);
    C.Pen.Width := 1;
    C.Pen.Color := PixToColor(Pix(235, 70, 70));
    C.Brush.Style := bsSolid;
    C.Brush.Color := PixToColor(Pix(255, 150, 150));
    C.Rectangle(Round(Q.X) - D, Round(Q.Y) - D, Round(Q.X) + D + 1, Round(Q.Y) + D + 1);
    C.Brush.Style := bsClear;
  end;

  procedure Rubber(const A, B: TP3);
  var
    PA, PB: TPointF;
    Ax: Integer;
  begin
    PA := ScreenOf(A);
    PB := ScreenOf(B);
    { Solid and heavy: this is the shape about to be committed, not
      something provisional (SketchUp keeps it solid too). }
    C.Pen.Style := psSolid;
    C.Pen.Width := Max(3, Round(3 * FUIScale));
    { A line's color is the direction it runs (a plane's color names its
      normal, the one axis a line in it cannot run along).  Only while axis
      inference is on: the color says "holding you on red", so showing it
      with Alt's axis inference off reads as a flickering snap.  An arrow
      lock holds whatever Alt says. }
    if FAxisLock in [0..2] then Ax := FAxisLock
    else if FInferMode = imAll then Ax := AxisAlong(A, B)
    else Ax := -1;
    { parallel or perpendicular to an edge is SketchUp's magenta, which
      cannot be mistaken for an axis }
    if FParPerp > 0 then
      C.Pen.Color := PixToColor(Pix($C8, $3C, $C8))
    else if Ax >= 0 then
      C.Pen.Color := PixToColor(AxisPix(Ax))
    else
      C.Pen.Color := PixToColor(Theme.Accent);
    C.MoveTo(Round(PA.X), Round(PA.Y));
    C.LineTo(Round(PB.X), Round(PB.Y));
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
  end;

begin
  P := ScreenOf(FCur);
  SX := Round(P.X);
  SY := Round(P.Y);

  { --- live preview ---------------------------------------------------- }

  { Leaning on the button cancels whatever tool is in progress, not only a
    line run.  While straining, the strain replaces the shape's preview. }
  if FHoldOn and (FHoldT > HOLD_STRAIN) and (FStage >= 1) then
  begin
    if StrainOutline(StrainPts) then
      PaintStrainPath(C, StrainPts,
        (FHoldT - HOLD_STRAIN) / (HOLD_BREAK - HOLD_STRAIN));
    PaintSnapRecoil(C);
    Exit;
  end;

  case FTool of
    ptLine:
      begin
        PaintHeldPlane(C);
        if FStage = 1 then Rubber(FP1, PreviewTarget);
      end;
    ptRect:
      begin
        { before the first corner too, so you can see which plane you are
          about to get }
        PaintHeldPlane(C);
        if FStage = 1 then
        begin
          RectPrev := RectCorners(FP1, RectTarget, FD.Plane);
          for RectI := 0 to 3 do
            Rubber(RectPrev[RectI], RectPrev[(RectI + 1) mod 4]);
        end;
      end;
    ptOffset:
      if FStage = 1 then
      begin
        RectPrev := OffsetPreview;
        for RectI := 0 to High(RectPrev) do
          Rubber(RectPrev[RectI], RectPrev[(RectI + 1) mod Length(RectPrev)]);
      end;
    ptArc:
      begin
        { As SketchUp: both ends marked, the chord, the pull from its middle
          in its axis color (blue straight up a wall), and the arc where it
          will land, so the plane is visible before drawing. }
        if FStage = 1 then
        begin
          Rubber(FP1, FCur);
          EndMark(FP1);
        end
        else if (FStage = 2) and ArcFillet(ArcFil, ArcTyped) then
        begin
          { magenta, SketchUp's "tangent to edge", drawn where it really
            lands; the second end moves to match, so it can jump on lock }
          Rubber(ArcFil.Corner, ArcFil.S);
          Rubber(ArcFil.Corner, ArcFil.E);
          C.Pen.Style := psSolid;
          C.Pen.Width := Max(3, Round(3 * FUIScale));
          C.Pen.Color := PixToColor(Pix(225, 40, 225));
          PA := ScreenOf(ArcPoint(ArcFil.ArcC, ArcFil.R, ArcFil.A0,
            ArcFil.Pl, ArcFil.Nm));
          C.MoveTo(Round(PA.X), Round(PA.Y));
          for ArcK := 1 to FSidesArc do
          begin
            PB := ScreenOf(ArcPoint(ArcFil.ArcC, ArcFil.R,
              ArcFil.A0 + ArcFil.Sweep * ArcK / FSidesArc, ArcFil.Pl, ArcFil.Nm));
            C.LineTo(Round(PB.X), Round(PB.Y));
          end;
          C.Pen.Width := 1;
          EndMark(ArcFil.S);
          EndMark(ArcFil.E);
          { the words below right of the pointer, clear of the cursor square
            (which wipes canvas text) and the tool glyph above }
          UIFont(C, 8, True, Pix(225, 40, 225));
          C.Brush.Style := bsClear;
          C.TextOut(FMouseSX + Round(24 * FUIScale), FMouseSY + Round(10 * FUIScale),
            'TANGENT TO EDGE');
        end
        else if FStage = 2 then
        begin
          if ArcPicks(FCur, ArcPl, ArcC, ArcR, ArcA0, ArcSw, ArcBulge) then
          begin
            PlaneAxes(ArcPl, ArcU, ArcV);
            PlaneCoords(ArcPl, FP1, U1, V1);
            PlaneCoords(ArcPl, FP2, U2, V2);
            Ln := Sqrt(Sqr(U2 - U1) + Sqr(V2 - V1));
            { the chord, thin }
            PA := ScreenOf(FP1);
            PB := ScreenOf(FP2);
            C.Pen.Style := psDash;
            C.Pen.Width := 1;
            C.Pen.Color := PixToColor(Theme.Accent);
            C.MoveTo(Round(PA.X), Round(PA.Y));
            C.LineTo(Round(PB.X), Round(PB.Y));
            C.Pen.Style := psSolid;
            { the pull from the chord's middle, in its axis color }
            ArcMid := P3((FP1.X + FP2.X) / 2, (FP1.Y + FP2.Y) / 2, (FP1.Z + FP2.Z) / 2);
            ArcFoot := P3(
              ArcMid.X + (ArcU.X * (-(V2 - V1) / Ln) + ArcV.X * ((U2 - U1) / Ln)) * ArcBulge,
              ArcMid.Y + (ArcU.Y * (-(V2 - V1) / Ln) + ArcV.Y * ((U2 - U1) / Ln)) * ArcBulge,
              ArcMid.Z + (ArcU.Z * (-(V2 - V1) / Ln) + ArcV.Z * ((U2 - U1) / Ln)) * ArcBulge);
            Rubber(ArcMid, ArcFoot);
            { the arc where it will land }
            C.Pen.Width := Max(2, Round(2 * FUIScale));
            C.Pen.Color := PixToColor(Theme.Accent);
            PA := ScreenOf(ArcPoint(ArcC, ArcR, ArcA0, ArcPl));
            C.MoveTo(Round(PA.X), Round(PA.Y));
            for ArcK := 1 to FSidesArc do
            begin
              PB := ScreenOf(ArcPoint(ArcC, ArcR, ArcA0 + ArcSw * ArcK / FSidesArc, ArcPl));
              C.LineTo(Round(PB.X), Round(PB.Y));
            end;
            C.Pen.Width := 1;
          end
          else
            Rubber(FP1, FP2);
          EndMark(FP1);
          EndMark(FP2);
        end;
      end;
    ptCircle:
      begin
        PaintHeldPlane(C);
      if FStage = 1 then
      begin
        { Drawn in the plane it will land in, not a round ring on the glass,
          so a plane change shows.  A circle runs every direction, so it is
          the one shape colored by its plane's normal. }
        C.Pen.Style := psSolid;
        C.Pen.Color := PixToColor(PlanePix(FD.Plane));
        C.Pen.Width := Max(3, Round(3 * FUIScale));
        C.Brush.Style := bsClear;
        CircR := Dist(FP1, FCur);
        if CircR > 1E-9 then
        begin
          PPrev := ScreenOf(ArcPoint(FP1, CircR, 0, FD.Plane));
          for CircI := 1 to FSidesCircle do
          begin
            P := ScreenOf(ArcPoint(FP1, CircR, CircI * 2 * Pi / FSidesCircle, FD.Plane));
            C.MoveTo(Round(PPrev.X), Round(PPrev.Y));
            C.LineTo(Round(P.X), Round(P.Y));
            PPrev := P;
          end;
        end;
        C.Pen.Width := 1;
      end;
      end;
    ptMeasure:
      if FStage = 1 then
      begin
        Rubber(FP1, FCur);
        { the whole reading follows the cursor, angles and all, so a run can be
          checked for level without letting go }
        FCmdMsg := RunReading(FP1, FCur);
        { the running length beside the cursor, readable while dragging }
        S1 := FormatLen(Dist(FP1, FCur), FD.Units);
        UIFont(C, 11, True, AnnotColor);
        C.Brush.Style := bsSolid;
        C.Brush.Color := PixToColor(Theme.Screen1);
        C.TextOut(SX + Round(22 * FUIScale), SY - Round(30 * FUIScale), S1);
        C.Brush.Style := bsClear;
      end;
    ptDim:
      if FStage = 1 then
      begin
        Rubber(FP1, FCur);
        PaintDimEnds(C, FP1, FCur);
        if Dist(FP1, FCur) > 1E-9 then
        begin
          PA := ScreenOf(FP1);
          PB := ScreenOf(FCur);
          PaintDimTag(C, (PA.X + PB.X) / 2, (PA.Y + PB.Y) / 2 - 16 * FUIScale,
            FormatLen(Dist(FP1, FCur), FD.Units));
        end;
      end
      else if FStage = 2 then PaintDimPreview(C);

    ptPush, ptDrill:
      if FStage = 1 then
      begin
        PaintFaceHint(C, FPushFace, HINT_BLUE);
        PaintPushPreview(C);
      end
      else
        PaintFaceHint(C, FHoverFace, HINT_BLUE);
    ptFollow:
      if FStage = 0 then PaintFaceHint(C, FHoverFace, HINT_BLUE)
      else
      begin
        PaintFaceHint(C, FFollowFace, HINT_BLUE);
        if FStage = 2 then PaintRevolvePreview(C);
      end;
    ptMove:
      if FDimMove >= 0 then PaintDimPreview(C) else PaintMoveGhost(C);
    ptRotate, ptProtractor: PaintRotateGhost(C);
    ptSelect, ptText, ptErase, ptOrbit: ;   // nothing to rubber-band
  end;

  PaintSnapRecoil(C);

  { The face a new shape is about to land on, washed with its points marked.
    Only before the first click; after that the plane is settled. }
  if (FStage = 0) and (FTool in [ptLine, ptRect, ptCircle, ptArc]) and
     not FPlaneHeld then
  begin
    { Hit-tested here, not taken from the motion handler's cache, which is a
      tick behind and cleared by unrelated things.  It is cheap at paint time. }
    HintFace := InContextFace(FD.Doc.HitFace(Proj, FMouseSX, FMouseSY));
    if HintFace >= 0 then
    begin
      PaintFaceHint(C, HintFace, HINT_BLUE);
      PaintFacePoints(C, HintFace);
    end;
  end;

  { --- scale bar, bottom left ------------------------------------------ }
  BarLen := NiceBarLength(Ppu, 70 * FUIScale, 190 * FUIScale, FD.Units);
  BarPx := BarLen * Ppu;
  AX := Round(20 * FUIScale);
  AY := pbScreen.Height - Round(24 * FUIScale);
  C.Pen.Color := PixToColor(AnnotColor);
  C.Pen.Width := 2;
  C.MoveTo(AX, AY);
  C.LineTo(AX + Round(BarPx), AY);
  C.MoveTo(AX, AY - Round(5 * FUIScale));
  C.LineTo(AX, AY + Round(5 * FUIScale));
  C.MoveTo(AX + Round(BarPx), AY - Round(5 * FUIScale));
  C.LineTo(AX + Round(BarPx), AY + Round(5 * FUIScale));
  UIFont(C, 10, True, AnnotColor);
  C.TextOut(AX, AY - Round(20 * FUIScale), FormatLen(BarLen, FD.Units));
  S1 := CurScale.Name + IfThen(FD.Units = usImperial, ' = 1''-0"', '');
  C.TextOut(AX + Round(BarPx) + Round(12 * FUIScale), AY - Round(20 * FUIScale),
    Format('%s   (view %s)', [S1, ZoomReading]));

  { --- where a solid is not closed ------------------------------------- }
  { Over everything in warning red, to show where a solid is open (the export
    already says whether).  Dropped the moment the drawing changes. }
  if (Length(FOpenEdges) >= 2) and (FOpenSeq = FEditSeq) then
  begin
    C.Pen.Width := Max(3, Round(3 * FUIScale));
    C.Pen.Color := PixToColor(Pix(235, 60, 60));
    AY := 0;
    while AY + 1 <= High(FOpenEdges) do
    begin
      PA := ScreenOf(FOpenEdges[AY]);
      PB := ScreenOf(FOpenEdges[AY + 1]);
      C.MoveTo(Round(PA.X), Round(PA.Y));
      C.LineTo(Round(PB.X), Round(PB.Y));
      Inc(AY, 2);
    end;
    C.Pen.Width := 1;
  end;

  { --- what is selected ------------------------------------------------ }
  { (the selection is already on screen: pbScreenPaint composited the layer
    EnsureSelLayer drew) }
  { The edge the dimension tool would take.  An arc is lit by its outline,
    anything else as the segment itself (lighting a face outline's entity
    would light the whole face).  It also shows what it will give: radius,
    diameter, or ends and length. }
  if (FTool = ptDim) and (FStage = 0) and (FHoverEnt >= 0) then
  begin
    if FD.Doc[FHoverEnt].Kind = ekArc then
    begin
      Hi := FD.Doc.Outline(Proj, FHoverEnt);
      if Length(Hi) >= 2 then TraceOutline(C, Hi, HINT_BLUE);
      FDimArc := FHoverEnt;
      if DimRadialAt(DA, DB, DNote) then
      begin
        PaintDimEnds(C, DA, DB);
        PA := ScreenOf(FD.Doc[FHoverEnt].C);
        PaintDimTag(C, PA.X, PA.Y - 16 * FUIScale,
          StringReplace(DNote, '<>', FormatLen(Dist(DA, DB), FD.Units), []));
      end;
      FDimArc := -1;
    end
    else if FHoverEdgeOK then
    begin
      SetLength(Hi, 2);
      Hi[0] := ScreenOf(FHoverEdgeA);
      Hi[1] := ScreenOf(FHoverEdgeB);
      TraceOutline(C, Hi, HINT_BLUE);
      PaintDimEnds(C, FHoverEdgeA, FHoverEdgeB);
      { on the side of the edge away from the pointer, which sits on it }
      TX := -(Hi[1].Y - Hi[0].Y);
      TY := Hi[1].X - Hi[0].X;
      TL := Sqrt(TX * TX + TY * TY);
      if TL > 1E-6 then
      begin
        TX := TX / TL; TY := TY / TL;
        if TX * (FMouseSX - (Hi[0].X + Hi[1].X) / 2) + TY * (FMouseSY - (Hi[0].Y + Hi[1].Y) / 2) > 0 then
        begin TX := -TX; TY := -TY; end;
      end;
      PaintDimTag(C, (Hi[0].X + Hi[1].X) / 2 + TX * 18 * FUIScale,
        (Hi[0].Y + Hi[1].Y) / 2 + TY * 18 * FUIScale,
        FormatLen(Dist(FHoverEdgeA, FHoverEdgeB), FD.Units));
    end;
  end;

  { what a click would take, so a pick can be aimed before committing }
  if (FTool in [ptSelect, ptMove, ptRotate]) and (FHoverEnt >= 0) and
     not IsSelected(FHoverEnt) then
  begin
    { a guide just turns blue rather than getting a thick outline; it is
      construction and should stay quiet }
    if FD.Doc[FHoverEnt].Kind = ekGuide then
      PaintGuideHover(C, FHoverEnt)
    else if FD.Doc.TopPartIn(FHoverEnt) > 0 then
    begin
      { a group is its box: red when locked, SketchUp's cue }
      GrpId := FD.Doc.TopPartIn(FHoverEnt);
      if FD.Doc.PartLockedUp(GrpId) then
        PaintPartBox(C, GrpId, Pix(230, 80, 80), False, P3(0, 0, 0))
      else
        PaintPartBox(C, GrpId, Pix(150, 185, 245), False, P3(0, 0, 0));
    end
    else
      TraceOutlineVisible(C, FHoverEnt, Pix(150, 185, 245), Max(2, Round(2 * FUIScale)));
  end;

  { the group under the pointer in the groups panel }
  if (FGrpHotId > 0) and pbGroups.Visible and (FD.Doc.PartEnt(FGrpHotId) >= 0) and
     not GroupPutAway(FGrpHotId) then
    PaintPartBox(C, FGrpHotId, HINT_BLUE, False, P3(0, 0, 0));

  { picked groups as their boxes, and the open group as a dotted box round
    everything you are working inside }
  GrpBoxes := SelectedGroups;
  for GI := 0 to High(GrpBoxes) do
    if FD.Doc.PartLockedUp(GrpBoxes[GI]) then
      PaintPartBox(C, GrpBoxes[GI], Pix(230, 80, 80), False, P3(0, 0, 0))
    else
      PaintPartBox(C, GrpBoxes[GI], Pix(70, 130, 240), False, P3(0, 0, 0));
  if FD.Doc.Context <> 0 then
    PaintPartBox(C, FD.Doc.Context, Pix(130, 130, 140), True, P3(0, 0, 0));
  { every locked group in reach shows its crate faintly: you draw against it,
    and its corners, edge middles and centers are snap points }
  for GI := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[GI].Kind = ekPart) and (FD.Doc[GI].Part = FD.Doc.Context) and
       FD.Doc[GI].Solid and (FD.Doc.TopPartIn(GI) > 0) then
      PaintPartBox(C, FD.Doc[GI].Grp, Pix(240, 190, 190), True, P3(0, 0, 0));

  { the pick box: dashed for crossing, solid for containing, the only cue to
    which rule applies }
  if FBoxing then
  begin
    C.Brush.Style := bsClear;
    C.Pen.Color := PixToColor(Pix(70, 130, 240));
    C.Pen.Width := Max(1, Round(FUIScale));
    if FMouseSX < FBoxX then C.Pen.Style := psDash else C.Pen.Style := psSolid;
    C.Rectangle(Min(FBoxX, FMouseSX), Min(FBoxY, FMouseSY),
                Max(FBoxX, FMouseSX), Max(FBoxY, FMouseSY));
    C.Pen.Style := psSolid;
  end;

  { --- what the eraser is about to remove ------------------------------ }
  { everything gathered so far, in red, so a sweep can be seen and abandoned
    by not letting go over anything }
  for AY := 0 to High(FDoomed) do
  begin
    Hi := FD.Doc.Outline(Proj, FDoomed[AY]);
    if (Length(Hi) >= 3) and (FD.Doc[FDoomed[AY]].Kind = ekFace) then
      WashFace(C, FDoomed[AY], Pix(240, 60, 60));
    if Length(Hi) >= 2 then
    begin
      TraceOutline(C, Hi, Pix(240, 60, 60));
    end;
  end;

  if (FTool = ptErase) and (FHoverEnt >= 0) and not FErasing2 then
  begin
    Hi := FD.Doc.Outline(Proj, FHoverEnt);
    { a whole panel is a lot to lose to a click, so the face is washed too }
    if (Length(Hi) >= 3) and (FD.Doc[FHoverEnt].Kind = ekFace) then
      WashFace(C, FHoverEnt, Pix(230, 70, 70));
    if Length(Hi) >= 2 then
    begin
      TraceOutline(C, Hi, Pix(230, 70, 70));
    end
    else if Length(Hi) = 1 then
    begin
      C.Pen.Color := PixToColor(Pix(230, 70, 70));
      C.Brush.Style := bsClear;
      C.Ellipse(Round(Hi[0].X) - 7, Round(Hi[0].Y) - 7,
                Round(Hi[0].X) + 7, Round(Hi[0].Y) + 7);
    end;
  end;

  { --- parallel or square to an edge, in SketchUp's magenta ---
    Dotted guides are drawn 2 px heavy so they do not get lost, and each goes
    into FTipLines so the chip avoids it. }
  SetLength(FTipLines, 0);
  if FParPerp > 0 then
  begin
    GP := ScreenOf(FAxisFrom);
    C.Pen.Style := psDot;
    C.Pen.Color := PixToColor(Pix($C8, $3C, $C8));
    C.Pen.Width := Max(2, Round(2 * FUIScale));
    C.MoveTo(Round(GP.X), Round(GP.Y));
    C.LineTo(SX + Round((SX - GP.X) * 0.18), SY + Round((SY - GP.Y) * 0.18));
    TipAvoid(Round(GP.X), Round(GP.Y), SX + Round((SX - GP.X) * 0.18), SY + Round((SY - GP.Y) * 0.18));
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
  end;

  { --- the axis you are locked to --------------------------------------- }
  if FAxisLock in [0..2] then
  begin
    GP := ScreenOf(FAxisFrom);
    C.Pen.Style := psDot;
    C.Pen.Color := PixToColor(AxisPix(FAxisLock));
    C.Pen.Width := Max(2, Round(2 * FUIScale));
    { run past the cursor so it reads as a line you are on }
    C.MoveTo(Round(GP.X), Round(GP.Y));
    C.LineTo(SX + Round((SX - GP.X) * 0.18), SY + Round((SY - GP.Y) * 0.18));
    TipAvoid(Round(GP.X), Round(GP.Y), SX + Round((SX - GP.X) * 0.18), SY + Round((SY - GP.Y) * 0.18));
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
  end;

  { --- lined up with a point somewhere else ----------------------------- }
  if FGuide then
  begin
    GP := ScreenOf(FGuideFrom);
    C.Pen.Style := psDot;
    C.Pen.Color := PixToColor(GuideColor);
    C.Pen.Width := Max(2, Round(2 * FUIScale));
    C.MoveTo(Round(GP.X), Round(GP.Y));
    C.LineTo(SX, SY);
    TipAvoid(Round(GP.X), Round(GP.Y), SX, SY);
    C.Pen.Width := 1;
    C.Pen.Style := psSolid;
    C.Brush.Style := bsClear;
    C.Pen.Color := PixToColor(GuideColor);
    C.Rectangle(Round(GP.X) - 3, Round(GP.Y) - 3, Round(GP.X) + 4, Round(GP.Y) + 4);
  end;

  { No ring on the held reference point, as in SketchUp; only the dotted
    guide from it. }
  { --- the view cube ---------------------------------------------------- }
  PaintViewCube(C);
  PaintCompass(C);
  if FStairPick > 0 then PaintStairPick(C, SX, SY);

  { --- the action chip beside the cursor ---
    Not while the pointer is over the cube's patch: the chip would cover the
    cube. }
  if CubeZone(FMouseSX, FMouseSY) then Exit;
  if FErasing then Exit;
  S1 := SnapLabel;
  { picking stairs: the chip says so, and which point the next click is for }
  if FStairPick > 0 then
  begin
    if S1 = '' then S1 := 'FREE';
    S1 := 'STAIRS  ' + S1;
    case FStairPick of
      1: S2 := 'click the TOP - the landing''s edge, at its height';
      2: S2 := 'click the BOTTOM - where the first riser stands - or type the run';
    else S2 := 'click the SIDE - as far out as the stairs are wide - or type the width';
    end;
    S2 := S2 + '.  Esc goes back';
  end
  else if FTextPick and (SourceForm <> nil) then
  begin
    if S1 = '' then S1 := 'FREE';
    S1 := 'PICKING  ' + S1;
    S2 := 'click a point for ' + SourceForm.PickWants +
      '.  Arrows lock red, green, blue for a height; Esc stops';
  end
  else
  if FStage = 0 then
  begin
    if S1 = '' then S1 := 'FREE';
    case FTool of
      ptSelect: S2 := 'pick a tool below, or press L for a line';
      ptLine:
        { in 3D, say the one non-guessable thing: arrows lock the plane
          before you start }
        if (FD.View = vkOrbit) and (FStage = 0) and not FPlaneHeld then
          S2 := 'click to start - arrows lock a flat plane first: left upright, right side-on'
        else
          S2 := 'click to start - then type 12, 12''6 or 6-8-15';
      ptRect:   S2 := 'click a corner - then drag, or type 8x10';
      ptCircle: S2 := Format('click the center - %d sides: + - or type 24s', [FSidesCircle]);
      ptArc:    S2 := Format('click one end - %d segments: + - or type 12s', [FSidesArc]);
      ptPush:   S2 := 'click a face - then type how far, or rest on an edge';
      ptDrill:  S2 := 'click a face - it goes through whatever it crosses; type a depth to stop short';
      ptFollow: S2 := 'click the outline to spin - the half of the shape, seen edge on';
      ptErase:  S2 := 'click an edge to delete it - or hold and drag across ' +
                      'several.  Ctrl softens instead, Ctrl+Shift brings back';
      ptText:   S2 := 'space or click - the note points here';
      ptMove:   S2 := 'grab a point on what you are moving - Ctrl leaves a copy';
      ptOffset: S2 := 'click a face - then type the offset, negative goes inward';
      ptMeasure:
        { short: the line is narrow, and the full mode is said on every Ctrl }
        S2 := 'measure from here - Ctrl says what it leaves behind';
      ptDim:    S2 := 'click a corner, then another - or the body of an edge for all of it';
      ptRotate: S2 := 'click the center - nothing picked turns all that is joined; arrows pick the plane';
      ptProtractor: S2 := 'click the vertex - arrows pick the plane by color';
      ptOrbit:  S2 := 'drag to spin - Shift pans, Ctrl snaps to a view';
    else
      S2 := 'space or click - start here';
    end;
  end
  else
  begin
    if S1 = '' then S1 := 'DRAWING';
    case FTool of
      ptPush, ptDrill: S2 := 'type how far - 2, 6", 1-6 - or rest on an edge or a face';
      ptFollow:
        if FStage = 2 then
          S2 := 'the ring shows what it will sweep - red means the axis cuts the outline'
        else
          S2 := 'click the straight side that is the middle of the shape';
      ptCircle: S2 := Format('type a radius, or click - %d sides: + - or 24s', [FSidesCircle]);
      ptArc:    S2 := Format('pull the middle out, or type the bulge - %d segments: + - or 12s', [FSidesArc]);
      ptText:   S2 := 'type it, move away, then Enter - Shift+Enter for a new line';
      ptDim:
        if FDimArc >= 0 then S2 := 'move round the curve to turn it, then click'
        else S2 := 'move away to place it - it goes the way the pointer goes, flat or standing';
      ptMeasure:
        S2 := 'click the second point, or type a distance - 3, 2''6, 0-8-8';
      ptRect:   S2 := 'drag it, or type 8x10, 8/10 or 2''6x4 - a minus flips a side';
      ptMove:   S2 := 'type a length, [x,y,z] or <x,y,z> - Ctrl copies, then 3x or /3 for an array';
      ptOffset: S2 := 'type the offset - 6", 1-6 - negative goes inward';
      ptRotate, ptProtractor:
        if FStage = 1 then S2 := 'click a point to measure the angle from'
        else S2 := 'swing to the angle and click, or type it - 45, 22.5, or 8:12';
    else
      S2 := 'type a length - 12, 12''6, 6-8-15 - arrows lock an axis';
    end;
  end;

  { the keys that do something, under the two lines: the card is where the
    eye is }
  S3 := ShortKeys;
  { With the source window open, the thing under the pointer shows its line
    of text.  Only then: the text is something to look up, not to be met
    with. }
  S4 := '';
  if (SourceForm <> nil) and SourceForm.Visible and (FTool = ptSelect) then
  begin
    HL := FHoverEnt;
    if (HL < 0) and (FHoverFace >= 0) then HL := FHoverFace;
    if (HL >= 0) and SourceForm.LineOfThing(HL, HLn, HTx) then
    begin
      if Length(HTx) > 60 then HTx := Copy(HTx, 1, 57) + '...';
      S4 := Format('line %d:  %s', [HLn, HTx]);
    end;
  end;
  UIFont(C, 9, True, Theme.Text);
  LnH := C.TextHeight('Xg');
  W1 := C.TextWidth(S1);
  UIFont(C, 9, False, Theme.Text);
  W2 := C.TextWidth(S2);
  W3 := 0;
  if S3 <> '' then
  begin
    UIFont(C, 8, False, Theme.TextDim);
    W3 := C.TextWidth(S3);
  end;
  W4 := 0;
  if S4 <> '' then
  begin
    C.Font.Name := 'Courier New';
    C.Font.Pitch := fpFixed;
    UIFont(C, 8, False, Theme.Accent);
    C.Font.Name := 'Courier New';
    W4 := C.TextWidth(S4);
  end;
  BoxW := Max(Max(W1, W4), Max(W2, W3)) + Round(18 * FUIScale);
  BoxH := 2 * LnH + Round(14 * FUIScale);
  if S3 <> '' then Inc(BoxH, LnH);
  if S4 <> '' then Inc(BoxH, LnH);

  R := TipSpot(SX, SY, BoxW, BoxH);

  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(MixPix(Theme.Panel, Pix(0, 0, 0), 0.15));
  C.Pen.Color := PixToColor(Theme.Accent);
  C.Pen.Width := 1;
  C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Round(8 * FUIScale),
    Round(8 * FUIScale));

  UIFont(C, 9, True, Theme.Accent);
  C.TextOut(R.Left + Round(9 * FUIScale), R.Top + Round(5 * FUIScale), S1);
  UIFont(C, 9, False, Theme.Text);
  C.TextOut(R.Left + Round(9 * FUIScale), R.Top + Round(5 * FUIScale) + LnH, S2);
  if S3 <> '' then
  begin
    UIFont(C, 8, False, Theme.TextDim);
    C.TextOut(R.Left + Round(9 * FUIScale),
      R.Top + Round(5 * FUIScale) + 2 * LnH, S3);
  end;
  if S4 <> '' then
  begin
    UIFont(C, 8, False, Theme.Accent);
    C.Font.Name := 'Courier New';
    C.Font.Pitch := fpFixed;
    HLn := 2;
    if S3 <> '' then HLn := 3;
    C.TextOut(R.Left + Round(9 * FUIScale),
      R.Top + Round(5 * FUIScale) + HLn * LnH, S4);
  end;
end;

{ A tip beside the strip button under the pointer, drawn on the drawing
  canvas in the same card style as the cursor chip.  Two lines: what it is,
  then what it does, since a name alone does not explain Offset. }
procedure TMainForm.PaintChromeTip(C: TCanvas);
var
  W1, W2, BoxW, BoxH, LnH, X, Y: Integer;
  R: TRect;
begin
  if FChromeTip = '' then Exit;
  UIFont(C, 9, True, Theme.Text);
  LnH := C.TextHeight('Xg');
  W1 := C.TextWidth(FChromeTip);
  UIFont(C, 9, False, Theme.Text);
  W2 := C.TextWidth(FChromeTipBody);
  BoxW := Max(W1, W2) + Round(18 * FUIScale);
  BoxH := 2 * LnH + Round(14 * FUIScale);

  { against the strip it came from, level with the button, never off the
    bottom }
  X := EnsureRange(FChromeTipX, 4, Max(4, pbScreen.Width - BoxW - 4));
  Y := EnsureRange(FChromeTipY - BoxH div 2, 4,
                   Max(4, pbScreen.Height - BoxH - 4));
  R := Rect(X, Y, X + BoxW, Y + BoxH);

  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(MixPix(Theme.Panel, Pix(0, 0, 0), 0.15));
  C.Pen.Color := PixToColor(Theme.Accent);
  C.Pen.Width := 1;
  C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Round(8 * FUIScale),
    Round(8 * FUIScale));
  UIFont(C, 9, True, Theme.Accent);
  C.TextOut(R.Left + Round(9 * FUIScale), R.Top + Round(5 * FUIScale), FChromeTip);
  UIFont(C, 9, False, Theme.Text);
  C.TextOut(R.Left + Round(9 * FUIScale), R.Top + Round(5 * FUIScale) + LnH,
    FChromeTipBody);
end;

procedure TMainForm.pbScreenPaint(Sender: TObject);
var
  Shown: TArtSurface;
  HF: Integer;
  HaveSel: Boolean;
  CR, Rad, SX, SY, Arm, Gap, I: Integer;
  Contrast, Halo, CPix: TPix;
  CW, CA: Double;
  CP: TPointF;
  TPaint, TAll: QWord;
begin
  if not FBooted then Exit;
  { a paint before the tick draws the moved camera itself, so a stale view
    is never shown }
  FlushView;
  TPaint := GetTickCount64;
  try
  if FErasing then
  begin
    pbScreen.Canvas.Brush.Style := bsSolid;
    pbScreen.Canvas.Brush.Color := PixToColor(Theme.Bezel2);
    pbScreen.Canvas.FillRect(0, 0, pbScreen.Width, pbScreen.Height);
  end;

  { The picture plus the selection and the face wash, kept from the last
    paint unless one of the three changed; then a paint is just the blit. }
  HF := -1;
  if not FErasing and (FPopup = POP_NONE) then HF := HintFaceNow;
  HaveSel := (Length(FSel) > 0) and not FErasing;
  if HaveSel then EnsureSelLayer;       { may say the shot is stale }
  if FShotOK and (HaveSel = FShotHadSel) and (HF = FHintInShot) then
  begin
    if HaveSel or (FHintInShot >= 0) then Shown := FSelShot else Shown := FArt;
  end
  else if not HaveSel and (HF < 0) then
  begin
    Shown := FArt;
    FHintInShot := -1;
    FShotHadSel := False;
    FShotOK := True;
  end
  else
  begin
    { one surface for both: the selection composited over the picture, and
      the wash drawn into the same copy }
    if FSelShot = nil then FSelShot := TArtSurface.Create(FArt.Width, FArt.Height)
    else FSelShot.SetSize(FArt.Width, FArt.Height);
    if HaveSel then
      { the selection always comes from its cached layer (see
        EnsureSelLayer); drawing it on the canvas was far too slow }
      FSelShot.CompositeOver(FArt, FSelLayer, Rect(0, 0, FArt.Width, FArt.Height))
    else
      FSelShot.CopyRegion(FArt, 0, 0, 0, 0, FArt.Width, FArt.Height);
    if HF >= 0 then PaintFaceHint(nil, HF, HINT_BLUE, FSelShot, 0, 0);
    FHintInShot := HF;
    FShotHadSel := HaveSel;
    FShotOK := True;
    Shown := FSelShot;
  end;
  { The face wash is drawn into the picture in memory, not dot by dot on the
    canvas (a platform call per dot was tens of ms a frame zoomed in). }
  Shown.DrawTo(pbScreen.Canvas, FJitterX, FJitterY);
  if FErasing then Exit;

  CP := ScreenOf(FCur);
  { clamp a cursor that projects somewhere absurd (orbit nearly along an
    axis), or Round wraps and the overlay reads from a wild position }
  if IsNan(CP.X) or IsNan(CP.Y) or IsInfinite(CP.X) or IsInfinite(CP.Y) then
    CP := PtF(FMouseSX, FMouseSY);
  SX := EnsureRange(Round(EnsureRange(CP.X, -1E6, 1E6)),
    -20000, pbScreen.Width + 20000);
  SY := EnsureRange(Round(EnsureRange(CP.Y, -1E6, 1E6)),
    -20000, pbScreen.Height + 20000);
  PaintOverlay(pbScreen.Canvas);

  { While a list is open the drawing's cursor is not drawn: it tracks a
    point the mouse is no longer choosing and reads as a second cursor. }
  if FPopup <> POP_NONE then
  begin
    PaintPopup(pbScreen.Canvas);
    { and what belongs on top of everything, like the shutter countdown }
    PaintShotOverlay(pbScreen.Canvas);
    Exit;
  end;

  { The pen cursor is composited through a scratch surface so it can be
    antialiased on top of the artwork. }
  Rad := Round(9 * FUIScale);
  CR := Rad + Round(8 * FUIScale);
  FOverlay.SetSize(CR * 2, CR * 2);
  { from the picture actually shown, so selection and wash are in the square }
  FOverlay.CopyRegion(Shown, SX - CR, SY - CR, 0, 0, CR * 2, CR * 2);
  { That square lacks the tool preview, so blitting it wipes any preview
    near the pointer.  A fillet sits right under the pointer when it locks,
    so it is drawn into the square first. }
  PaintUnderCursor(FOverlay, SX - CR, SY - CR);

  Contrast := Pix(20, 20, 24);
  FOverlay.BlendMode := bmNormal;

  { A fine target, not a ring: four short arms with a gap and a center dot
    cover almost nothing of what you aim at.  The dark pass under it keeps
    it readable over pale artwork. }
  Arm := Round(7 * FUIScale);
  Gap := Round(2 * FUIScale);
  Halo := MixPix(Contrast, Pix(128, 128, 128), 0.9);
  for I := 0 to 1 do
  begin
    if I = 0 then begin CW := 2.6; CA := 0.30; CPix := Halo; end
    else begin CW := 1.2; CA := 0.95; CPix := Contrast; end;
    FOverlay.Line(CR - Arm, CR, CR - Gap, CR, CW, CPix, CA);
    FOverlay.Line(CR + Gap, CR, CR + Arm, CR, CW, CPix, CA);
    FOverlay.Line(CR, CR - Arm, CR, CR - Gap, CW, CPix, CA);
    FOverlay.Line(CR, CR + Gap, CR, CR + Arm, CW, CPix, CA);
  end;
  FOverlay.Disc(CR, CR, 1.1, Contrast, 0.95);

  FOverlay.DrawTo(pbScreen.Canvas, SX - CR, SY - CR);

  PaintSnapMarker(pbScreen.Canvas, SX, SY);

  { the tool's glyph rides beside the cursor }
  if (FTool <> ptSelect) then
    PaintToolGlyph(pbScreen.Canvas, SX + CR - Round(2 * FUIScale),
      SY - CR - Round(2 * FUIScale));

  PaintPopup(pbScreen.Canvas);
  { over the drawing, under nothing: a tip must be readable over anything }
  PaintChromeTip(pbScreen.Canvas);
  PaintShotOverlay(pbScreen.Canvas);
  finally
    NoteFrame(GetTickCount64 - TPaint);
  end;
end;

{ The frame watchdog.  Paper, ink, composite and screen time are summed
  since the last paint, so a frame rendered three times before showing counts
  all three.  Over 40 ms (where a drag stops feeling attached) logs a line,
  at most one every two seconds; the count and worst case go in reports. }
procedure TMainForm.NoteFrame(PaintMs: QWord);
const
  SLOW_MS = 40;
var
  Total, Now64: QWord;
begin
  Total := FMsPaper + FMsRender + FMsComp + PaintMs;
  if Total >= SLOW_MS then
  begin
    Inc(FSlowN);
    if Total > FSlowWorst then FSlowWorst := Total;
    FSlowLast := Format('%dms (paper %d, ink %d, over %d, screen %d) ' +
      '%s stage=%d sel=%d things=%d zoom=%.0f%%%s',
      [Total, FMsPaper, FMsRender, FMsComp, PaintMs,
       TOOL_NAMES[FTool], FStage, Length(FSel), FD.Doc.Live, FD.Zoom * 100,
       IfThen(FCameraMoving, ' moving', '')]);
    { and to the terminal with /timings on }
    if FTimings then
    begin
      TimingLine('slow frame: ' + FSlowLast);
    end;
    Now64 := GetTickCount64;
    if Now64 - FSlowSaid >= 2000 then
    begin
      FSlowSaid := Now64;
      Trail('slow frame: ' + FSlowLast);
    end;
  end;
  FMsPaper := 0;
  FMsRender := 0;
  FMsComp := 0;
end;

{ ======================================================================== }
{ the tools                                                                 }
{ ======================================================================== }

function TMainForm.PlaneName: string;
begin
  if FD.Plane = plFree then Exit('on the face');
  Result := Copy('XYXZYZ', Ord(FD.Plane) * 2 + 1, 2);
end;

{ The arrows pick the plane before a shape is started, so drawing in 3D is
  not always flat.  Once a line is under way the arrows lock its direction
  instead. }
procedure TMainForm.PlaneByArrow(Key: Word);
var
  Was: TPlane;
begin
  Was := FD.Plane;
  { As SketchUp, the plane is named by its normal's axis color: right is
    red (YZ), left is green (XZ), up or down is blue (flat).  Esc releases it. }
  case Key of
    VK_RIGHT: FD.Plane := plYZ;     // normal is red, X
    VK_LEFT: FD.Plane := plXZ;      // normal is green, Y
  else
    FD.Plane := plXY;               // up or down: normal is blue, Z
  end;
  FPlaneHeld := True;
  if FD.Plane <> Was then
  begin
    RepaintPaper;
    RenderInk;
    RecomposeAll;
  end;
  case FD.Plane of
    plXZ: FCmdMsg := 'Drawing upright, on the XZ plane.';
    plYZ: FCmdMsg := 'Drawing on the side, the YZ plane.';
  else
    FCmdMsg := 'Drawing flat, on the XY plane.';
  end;
  FCmdMsg := FCmdMsg + '  Esc to follow faces again.';
  pbCmd.Invalidate;
  FScreenDirty := True;
end;

{ Leave a standard view for the free camera, aimed where you were looking.
  Zoom and pan are kept, so picking orbit while zoomed in does not reframe
  the whole drawing. }
procedure TMainForm.EnterFreeCamera(AtCorner: Boolean);
begin
  if FD.View = vkOrbit then Exit;
  if AtCorner then
  begin
    { for push/pull, which cannot see the face it moves from straight above }
    FD.Az := -Pi / 4;
    FD.El := ISO_EL;
  end
  else if FD.View = vkIso then
  begin
    FD.Az := -Pi / 4;
    FD.El := ISO_EL;
  end
  else
  begin
    FD.Az := 0;
    FD.El := 1.45;                  // as near straight down as it tilts
  end;
  FD.View := vkOrbit;
  FViewPreset := -1;
  RebuildDeck;
  pbDeck.Invalidate;
  pbView.Invalidate;
  RepaintPaper;
  RenderInk;
  RecomposeAll;
end;

procedure TMainForm.SetTool(T: TTool);
begin
  { Changing tool while picking stairs releases the pick and brings the stair
    dialog back, as Esc does; the new tool would otherwise start in pick mode. }
  if FStairPick > 0 then
  begin
    FStairPick := 0;
    FInput := '';
    FCmdMsg := 'Stairs: the pick is let go of - back to the stairs.  Finish or cancel them first.';
    pbCmd.Invalidate;
    pbScreen.Invalidate;
    Application.QueueAsyncCall(@StairResume, 0);
    Exit;
  end;
  Trail('tool ' + TOOL_NAMES[T]);
  Act('tool ' + TOOL_NAMES[T]);
  FArray.Live := False;
  { Push/pull along a normal pointing at the camera cannot be seen or judged
    in plan, so switch to a view where it means something. }
  if (T in [ptPush, ptDrill, ptFollow]) and (FD.View = vkPlan) then
  begin
    EnterFreeCamera(True);
    FCmdMsg := 'Push/pull needs to see the face - switched to the corner view.';
  end;
  if (T = ptOrbit) and (FD.View <> vkOrbit) then
  begin
    EnterFreeCamera;
    FCmdMsg := 'Orbit - drag to spin.  Shift pans; hold Ctrl and let go to click into the nearest view.';
  end;
  if T = ptOrbit then pbScreen.Cursor := crSizeAll
  else pbScreen.Cursor := crCross;
  FTool := T;
  ResetTool;
  pbDeck.Invalidate;
  pbCmd.Invalidate;
  Invalidate;
end;

procedure TMainForm.ResetTool;
begin
  FStage := 0;
  FDimArc := -1;
  { Alt's inference cycle is per run, not per session }
  FInferMode := imAll;
  FParHas := False;
  FParPerp := 0;
  FArcTanHas := False;
  FArcTanLock := False;
  FOffsetRaw := False;
  FRotFree := False;
  FFollowFace := -1;
  FUnfoldPick := False;
  FNoteDrag := -1;
  FStickOn := False;
  FSliceEdit := 0;
  { Every sheet change comes through here and each sheet has its own cut, so
    this guarantees the document never slices by the last sheet's numbers. }
  ApplySlice;
  { -1 means no dimension being edited.  Zero is a valid index, and with
    FDimEdit >= 0 every key goes into the command bar instead of being a
    shortcut. }
  FDimEdit := -1;
  FHoverEnt := -1;
  FHoverFace := -1;
  FPlaneHeld := False;
  FGuide := False;
  FAxisLock := -1;
  FLockOn := False;
  FDirLock := -1;
  FRotAxisIx := -1;
  FInput := '';
  FBoxing := False;
  FMoveCopy := False;
  FMoveRigid := False;
  FDimMove := -1;
  SetLength(FMoveVerts, 0);
  SetLength(FMoveGroupEnts, 0);
  pbScreen.Invalidate;
  pbCmd.Invalidate;
end;

function TMainForm.PlanePix(Pl: TPlane): TPix;
begin
  case Pl of
    plXZ: Result := AxisPix(1);      { faces along Y, green }
    plYZ: Result := AxisPix(0);      { faces along X, red }
    { a sloped face points along no axis, so it gets no axis color }
    plFree: Result := Theme.Accent;
  else
    Result := AxisPix(2);            { flat, faces up Z, blue }
  end;
end;

{ Which of the three paper axes an ISO line is meant to run along (an
  AxisDir index), or -1 before the drag shows a direction.  On iso paper
  every leg runs along an axis, so the line is locked to the nearest, not
  nudged.  All three axes, not just the current isoplane, so a run can chain
  across then down without a keystroke.  Measured on screen, like AxisTry. }
function TMainForm.IsoRunAxis(const From: TP3; out Along: Double): Integer;
var
  K: Integer;
  PR, PA: TPointF;
  UX, UY, VX, VY, LenSq, Off, Best, Step: Double;
  AD: TP3;
begin
  Result := -1;
  Along := 0;
  PR := ScreenOf(From);
  VX := FMouseSX - PR.X;
  VY := FMouseSY - PR.Y;
  { under a few pixels the drag has no direction yet }
  if VX * VX + VY * VY < Sqr(6 * FUIScale) then Exit;
  Best := 1E30;
  for K := 0 to 2 do
  begin
    AD := AxisDir(K * 2);
    PA := ScreenOf(P3(From.X + AD.X, From.Y + AD.Y, From.Z + AD.Z));
    UX := PA.X - PR.X;
    UY := PA.Y - PR.Y;
    LenSq := UX * UX + UY * UY;
    if LenSq < Sqr(0.2 * Ppu) then Continue;
    { how far off this axis the cursor is, in pixels }
    Off := Abs(VX * UY - VY * UX) / Sqrt(LenSq);
    if Off < Best then
    begin
      Best := Off;
      Result := K * 2;
      { The distance along it comes from the same screen measurement that
        chose it, not from the snapped cursor, which may sit on a different
        axis.  PA is one world unit away, so this is in world units. }
      Along := (VX * UX + VY * UY) / LenSq;
    end;
  end;
  if Result < 0 then Exit;
  { land on the grid ruling; the length is ours to round }
  Step := SnapStep;
  if Step > 1E-9 then Along := Round(Along / Step) * Step;
end;

{ Which axis a segment runs along, or -1.  Nearly exact: an edge either lies
  on an axis or it does not. }
function TMainForm.AxisAlong(const A, B: TP3): Integer;
var
  DX, DY, DZ, L: Double;
begin
  Result := -1;
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  DZ := B.Z - A.Z;
  L := Sqrt(DX * DX + DY * DY + DZ * DZ);
  if L < 1E-9 then Exit;
  if Abs(DX) / L > 0.9999 then Result := 0
  else if Abs(DY) / L > 0.9999 then Result := 1
  else if Abs(DZ) / L > 0.9999 then Result := 2;
end;

function TMainForm.LiveMeasure: string;
var
  T: TP3;
  W, H, L, LBulge: Double;
  LPl: TPlane;
  LFil: TFillet;
  LTyped: Boolean;
begin
  Result := '';
  case FTool of
    ptLine:
      if FStage = 1 then
        Result := FormatLen(Dist(FP1, PreviewTarget), FD.Units);
    ptRect:
      if FStage = 1 then
      begin
        RectSides(FP1, RectTarget, FD.Plane, W, H);
        { the comma is how SketchUp takes two sides, and so do we }
        Result := FormatLen(W, FD.Units) + ', ' + FormatLen(H, FD.Units);
      end;
    ptCircle:
      if FStage = 1 then
        Result := FormatLen(Dist(FP1, FCur), FD.Units);
    ptArc:
      if FStage = 1 then
        Result := FormatLen(Dist(FP1, FCur), FD.Units)
      else if FStage = 2 then
      begin
        if ArcFillet(LFil, LTyped) then
          Result := 'radius ' + FormatLen(LFil.R, FD.Units)
        else if ArcPicks(FCur, LPl, T, W, H, L, LBulge) then
          Result := 'bulge ' + FormatLen(Abs(LBulge), FD.Units);
      end;
    ptRotate, ptProtractor:
      if FStage >= 1 then
        Result := FormatAngle(RadToDeg(RotAngle));
    ptPush, ptDrill:
      if (FStage = 1) and (FPushFace >= 0) then
      begin
        L := PushDistance;
        if Abs(L) > 1E-9 then Result := FormatLen(Abs(L), FD.Units);
        if FPushFlush then Result := Result + '  flush';
      end;
    ptOffset:
      if FStage = 1 then
      begin
        L := OffsetDistance;
        if Abs(L) > 1E-9 then Result := FormatLen(Abs(L), FD.Units);
      end;
    ptMeasure, ptDim:
      if FStage >= 1 then
      begin
        T := PreviewTarget;
        if Dist(FP1, T) > 1E-9 then Result := FormatLen(Dist(FP1, T), FD.Units);
      end;
  end;
end;

{ What the cursor is holding, in words, for the status sentence (the chip
  says it in capitals). }
function TMainForm.SnapSays: string;
begin
  if FAxisLock in [0..2] then
    Exit('held on the ' + AxisName(FAxisLock) + ' axis');
  if FParPerp = 1 then Exit('parallel to the last edge');
  if FParPerp = 2 then Exit('square to the last edge');
  case FSnapKind of
    snEndpoint: Result := 'on the end of an edge';
    snMidpoint: Result := 'on the middle of an edge';
    snSubMid:   Result := 'on the middle of a piece';
    snCenter:   Result := 'on a center';
    snCross:    Result := 'where two lines cross';
    snOnEdge:   Result := 'on an edge';
    snOnFace:   Result := 'on a face';
    snQuadrant: Result := 'on the quarter of a circle';
    snOrigin:   Result := 'on the origin';
    snOnAxis:
      case FSnapAxis of
        0: Result := 'on the red axis';
        1: Result := 'on the green axis';
      else Result := 'on the blue axis';
      end;
  else
    Result := '';
  end;
end;

{ The keys that do something right now for the tool and its stage, as
  SketchUp's status bar shows.  Only what is true now: a modifier named when
  it does nothing gets tried once and never again. }
function TMainForm.ModifierTip: string;
begin
  Result := '';
  case FTool of
    ptSelect:
      if Length(FSel) = 0 then
        Result := 'Ctrl adds, Shift toggles, double-click takes what is ' +
                  'attached, three clicks take all of it'
      else
        Result := 'Ctrl adds, Shift toggles, Ctrl+Shift takes away';
    ptLine:
      if FStage = 0 then
        Result := 'arrows pick the plane, Alt holds it where it is'
      else
        case FInferMode of
          imNoLinear: Result := 'Alt: back to parallel and square, then to all - ' +
            'points still snap';
          imParPerp: Result := 'parallel and square only - Alt for all of them';
        else
          Result := 'arrows lock red, green or blue, Shift holds the one you ' +
                    'are on, Alt steps through the inferences';
        end;
    ptRect:
      if FStage = 0 then Result := 'arrows pick the plane, Alt holds it'
      else Result := 'type 8x10, or a minus to flip a side';
    ptCircle, ptArc:
      if FStage = 0 then
        Result := '+ and - change the sides, arrows pick the plane'
      else if (FTool = ptArc) and (FStage = 2) and FArcTanHas then
        Result := specialize IfThen<string>(FArcTanLock,
          'tangent to the edge it started on, held - Alt lets go',
          '+ and - change the sides, Alt runs it out of its edge smoothly')
      else
        Result := '+ and - change the sides, or type 24s';
    ptPush:
      if FLastPush <> 0 then
        Result := Format('double-click repeats the last push (%s)',
          [FormatLen(Abs(FLastPush), FD.Units)])
      else
        Result := 'type how far, or rest on an edge to go to it';
    ptOffset:
      if FOffsetRaw then Result := 'overlaps kept - Alt tidies them again'
      else Result := 'type the offset - a minus goes inward, Alt keeps the overlaps';
    ptMove:
      if FStage = 0 then Result := 'Ctrl leaves a copy behind'
      else Result := 'Ctrl copies, Shift holds the axis, then 3x or /3 for an array';
    ptErase: Result := 'Ctrl softens an edge instead, Ctrl+Shift brings it back';
    ptMeasure: Result := 'Ctrl changes what it leaves behind - ' + TapeDropSays;
    ptOrbit: Result := 'Shift pans, Ctrl clicks into the nearest view when you let go';
    ptRotate, ptProtractor:
      if FRotFree then
        Result := 'free of the face under the cursor - arrows pick the plane, ' +
                  'Alt follows faces again'
      else
        Result := 'arrows pick the plane by color, Alt frees it from the face';
    ptDim: Result := 'click the body of an edge for all of it';
    ptText: Result := 'Shift+Enter for a second line';
  end;
end;

{ ModifierTip, short enough for the card beside the pointer }
function TMainForm.ShortKeys: string;
begin
  Result := '';
  case FTool of
    ptSelect:   Result := 'Ctrl adds  Shift toggles  double-click takes more';
    ptLine:     if FStage = 0 then Result := 'arrows: the plane   Alt: hold it'
                else if FInferMode = imNoLinear then Result := 'Alt: inferences back on'
                else if FInferMode = imParPerp then Result := 'parallel and square only   Alt: all'
                else Result := 'arrows: lock an axis   Shift: hold it   Alt: what it infers';
    ptRect:     if FStage = 0 then Result := 'arrows: the plane   Alt: hold it';
    ptCircle, ptArc: Result := '+ and -: sides';
    ptPush:     if FLastPush <> 0 then Result := 'double-click: the last push again';
    ptMove:     Result := 'Ctrl: leave a copy   Shift: hold the axis';
    ptErase:    Result := 'Ctrl: soften   Ctrl+Shift: bring back';
    ptMeasure:  Result := 'Ctrl: what it leaves behind';
    ptOrbit:    Result := 'Shift: pan   Ctrl: click into a view';
    ptRotate, ptProtractor:
      if FRotFree then Result := 'free of the face   Alt: follow faces'
      else Result := 'arrows: the plane   Alt: free of the face';
  end;
end;

{ the tool's prompt, with where you are in front of it when a group is open }
function TMainForm.Prompt: string;
begin
  Result := PromptForTool;
  if (FD <> nil) and (FD.Doc.Context <> 0) then
    Result := 'in "' + FD.Doc.PartName(FD.Doc.Context) + '" (Esc leaves)   ' + Result;
end;

function TMainForm.PromptForTool: string;
var
  PromptAlong: Double;
  PMoveB: Boolean;
  PFil: TFillet;
  PTyped: Boolean;
begin
  case FTool of
    ptLine:
      if FStage = 0 then
      begin
        if (FD.View = vkOrbit) and not FPlaneHeld then
          Result := 'pick a start point   (arrows lock a flat plane: ' +
                    'left or right upright, up or down flat, Esc to let go)'
        else if FPlaneHeld then
          Result := 'pick a start point - locked to the ' + PlaneName +
                    ' plane, and it stays there'
        else
          Result := 'pick a start point';
      end
      else if FPlaneHeld and (FDirLock < 0) then
        Result := 'to the next point - held on the ' + PlaneName +
                  ' plane whatever you point at.  Double-click to finish'
      else if FDirLock >= 0 then
        Result := 'going ' + AxisName(FDirLock) + ' - length?'
      else if (FD.View = vkIso) and (ssShift in FMoveShift) then
        Result := 'off the grid - Shift held.  Let go to snap back to it'
      else if (FD.View = vkIso) and (IsoRunAxis(FP1, PromptAlong) >= 0) then
        Result := 'going ' + AxisName(IsoRunAxis(FP1, PromptAlong)) +
          ' on the grid - length?  Shift to come off it'
      else
        Result := 'to the next point, or type a length  -  double-click to finish';
    ptArc:
      case FStage of
        0:
          if FLastFilletR > 0 then
            Result := 'pick the first end - or double-click a corner to round it ' +
              FormatLen(FLastFilletR, FD.Units)
          else
            Result := 'pick the first end - on an edge near a corner to round it';
        1: Result := 'pick the second end';
      else
        if ArcFillet(PFil, PTyped) then
          Result := 'TANGENT TO EDGE - click, double-click to trim the corner, ' +
            'or type a radius'
        else if FilletCandidate(PFil) then
          Result := 'pull the middle towards the corner until it turns tangent, ' +
            'or type the bulge'
        else
          Result := 'pull the middle out, or type the bulge';
      end;
    ptRect:
      if FStage = 0 then Result := 'pick a corner'
      else Result := 'opposite corner, or type 12''x8''';
    ptCircle:
      if FStage = 0 then Result := 'pick the center' else Result := 'radius?';
    ptText:
      if FStage = 0 then
        Result := 'click what the note is about'
      else
        Result := 'type it - Shift+Enter for another line - then move away and Enter';
    ptPush, ptDrill:
      if FStage = 0 then
        Result := 'click a face'
      else
        Result := 'how far?  type it, or move and click';
    ptFollow:
      case FStage of
        0: Result := 'click the outline to spin - half of the shape, seen edge on';
        1: Result := 'the axis: click the straight side of the outline - ' +
                     'or two points down one side of it';
      else
        Result := 'the axis: a second point straight along it - type 90 ' +
                  'first for a quarter turn';
      end;
    ptDim:
      case FStage of
        0:
          if (FHoverEnt >= 0) and (FD.Doc[FHoverEnt].Kind = ekArc) then
          begin
            if Abs(FD.Doc[FHoverEnt].Sweep) >= 2 * Pi - 1E-9 then
              Result := 'click for the diameter of the lit circle'
            else
              Result := 'click for the radius of the lit arc';
          end
          else if FHoverEnt >= 0 then
            Result := 'click the lit edge to dimension all of it'
          else if DimAnchored then
            Result := 'click an edge, or a first point to measure from'
          else
            { said before the click: nothing here to measure from }
            Result := 'nothing here to measure - find a corner, a midpoint, ' +
                      'a center, or an edge';
        1:
          if DimAnchored then
            Result := 'second point - on a corner, a midpoint, a center or an edge'
          else
            Result := 'the other end has to be on something too';
      else
        Result := 'move away to place the line, then click';
      end;
    ptOrbit:
      { with Ctrl down mid-orbit, say where letting go will snap to (the
        cube shows it too, but is off by default) }
      if FSnapHasHot and (FSnapHot.Name <> '') then
        Result := 'let go to click into ' + FSnapHot.Name
      else
        Result := 'drag to spin the view - Shift pans, Ctrl snaps to a view';
    ptSelect:
      if Length(FSel) = 0 then
        Result := 'click to pick, or drag a box   (Ctrl adds, Shift toggles)'
      else
        if (Length(FSel) = 1) and (FD.Doc[FSel[0]].Kind = ekText) then
          Result := '1 picked - M to move, + and - for the text size, Delete to remove'
        else if SelectedDim >= 0 then
          Result := 'dimension picked - type a size and the drawing follows'
        else if (SelectedLine >= 0) and FD.Doc.LineLengthEnd(SelectedLine, PMoveB) then
          Result := 'line picked - type a length and Enter; the free end moves'
        else
        Result := Format('%d picked - M to move, Delete to remove',
          [Length(FSel)]);
    ptMove:
      if FStage = 0 then
        Result := 'grab a point on what you are moving'
      else if FMoveCopy then
        Result := 'where does the copy go?  a length, [x,y,z] or <x,y,z>'
      else if FDetachMove then
        Result := 'where does it go, on its own?  a length, [x,y,z] or ' +
          '<x,y,z> - /detach off to join it back on'
      else
        Result := 'where does it go?  a length, [x,y,z] or <x,y,z>';
    ptErase:
      Result := 'click an edge to delete it - or hold and drag across ' +
        'several.  Ctrl softens instead, Ctrl+Shift brings it back';
    ptRotate, ptProtractor:
      case FStage of
        0: if FTool = ptRotate then
             Result := 'click the center to turn about   (arrows: red, green or blue plane)'
           else
             Result := 'click the vertex of the angle   (arrows: red, green or blue plane)';
        1: Result := 'click a point to measure the angle from, or type the angle';
      else
        Result := 'swing to the angle and click, or type it - 45, 22.5, or 8:12 ' +
          'for a slope.  Negative goes the other way.';
      end;
  else
    case FStage of
      0: Result := 'measure from...';
      1: Result := 'measure to...';
    else
      Result := 'Enter keeps it as a dimension';
    end;
  end;
end;

{ Shift + arrow hops to the next real point in that direction, for getting
  around by keyboard or touch. }
procedure TMainForm.JumpSnap(DX, DY: Integer);
var
  I: Integer;
  Here, P: TPointF;
  Best, D, Along, Across: Double;
  Target: TP3;
  Found: Boolean;

  procedure Try_(const Q: TP3);
  begin
    P := ScreenOf(Q);
    Along := (P.X - Here.X) * DX + (P.Y - Here.Y) * DY;
    Across := Abs((P.X - Here.X) * DY - (P.Y - Here.Y) * DX);
    if Along < 2 then Exit;
    D := Along + Across * 2.5;
    if D < Best then
    begin
      Best := D;
      Target := Q;
      Found := True;
    end;
  end;

begin
  Here := ScreenOf(FCur);
  Best := 1E30;
  Found := False;
  for I := 0 to FD.Doc.Live - 1 do
  begin
    Try_(FD.Doc[I].A);
    Try_(FD.Doc[I].B);
    if FD.Doc[I].Kind = ekArc then
      Try_(FD.Doc[I].C);
  end;
  if Found then
  begin
    FCur := Target;
    FSnapKind := snEndpoint;
    FCmdMsg := 'Snapped to a point.';
  end
  else
    FCmdMsg := 'Nothing that way.';
  pbScreen.Invalidate;
  InvalidateStatus;
end;

procedure TMainForm.ToolClick;
var
  I, J: Integer;
  P: TPointF;
  T: TP3;
  U1, V1, U2, V2: Double;
  WasLine, Closed: Boolean;
begin
  { any click ends the copy that could have become an array, except the
    copy's own placing click }
  if FStage = 0 then FArray.Live := False;
  case FTool of
    ptOrbit: ;   // the drag does the work

    ptSelect: ;   // the press and release do the work

    { Grab a point, then say where it goes.  With nothing selected it picks
      up whatever is under the cursor first. }
    ptMove:
      if FStage = 0 then
      begin
        { nothing picked and the cursor on a corner: take just that corner
          (SketchUp's stretch), to pull a box out of square }
        if (Length(FSel) = 0) and (FSnapKind = snEndpoint) then
        begin
          SetLength(FMoveVerts, 1);
          FMoveVerts[0] := FCur;
          FP1 := FCur;
          FStage := 1;
          FDirLock := -1;
          FInput := '';
          FCmdMsg := 'Stretching from that corner.  ' +
            'Click where it goes, or type a distance.';
          Exit;
        end;
        PruneSelection;
        FMoveTook := False;
        if Length(FSel) = 0 then
        begin
          I := PickToGrab(FMouseSX, FMouseSY);
          if I < 0 then
          begin
            FCmdMsg := 'Nothing there to move.';
            Exit;
          end;
          SelectOnly(I);
          FMoveTook := True;
        end;
        { a dimension taken by its line is repositioned, not moved: its two
          points stay and the line goes where the cursor puts it, as in
          SketchUp }
        if (Length(FSel) = 1) and (FD.Doc[FSel[0]].Kind = ekDim) and
           ((Copy(FD.Doc[FSel[0]].Txt, 1, 2) = 'R ') or
            (Copy(FD.Doc[FSel[0]].Txt, 1, 4) = 'DIA ')) and
           (Pos('<>', FD.Doc[FSel[0]].Txt) > 0) then
        begin
          { a radius or diameter sits on its curve; it has nowhere to go }
          FCmdMsg := 'A radius or a diameter sits on its curve - erase it and ' +
            'dimension the curve again to turn it.';
          Exit;
        end;
        if (Length(FSel) = 1) and (FD.Doc[FSel[0]].Kind = ekDim) then
        begin
          FDimMove := FSel[0];
          FDimPrefer := P3(0, 0, 0);
          FP1 := FD.Doc[FDimMove].A;
          FP2 := FD.Doc[FDimMove].B;
          FStage := 1;
          FDirLock := -1;
          FInput := '';
          FCmdMsg := 'Moving the dimension line - click where it should sit.  ' +
            'It goes the way the pointer goes, flat or standing up.';
          Exit;
        end;
        FP1 := FCur;
        if not SplitMoveSelection then Exit;
        FStage := 1;
        FDirLock := -1;
        FInput := '';
        FCmdMsg := 'Click where it goes, or type a distance.  ' +
          'Arrows lock an axis, Ctrl leaves a copy.';
      end
      else
        ToolCommit;

    ptRotate, ptProtractor:
      case FStage of
        0:
          begin
            if FTool = ptRotate then
            begin
              if Length(FSel) = 0 then
              begin
                I := PickToGrab(FMouseSX, FMouseSY);
                if I < 0 then
                begin
                  FCmdMsg := 'Nothing there to rotate - pick something first.';
                  Exit;
                end;
                { With nothing picked, take everything joined to it, not one
                  face; turning one face of a box twists the box.  Pick first
                  to turn a part alone. }
                if FD.Doc.TopPartIn(I) > 0 then SelectOnly(I) else SelectConnected(I);
              end;
              if not SplitMoveSelection then Exit;
            end;
            FP1 := FCur;
            { the plane: an arrow key's, else the face under the cursor's,
              else flat (what a duct run turns in) }
            if FRotAxisIx >= 0 then
              FRotAxis := AxisDir(FRotAxisIx)
            else if (not FRotFree) and
                    FD.Doc.FaceUnder(Proj, FMouseSX, FMouseSY, I, T) then
              FRotAxis := Norm3(FD.Doc.FaceNormal(I))
            else
              { Alt freed it from the face: flat unless an arrow says
                otherwise }
              FRotAxis := P3(0, 0, 1);
            FStage := 1;
            FDirLock := -1;
            FInput := '';
            FCmdMsg := '';
          end;
        1:
          begin
            if Dist(FCur, FP1) < 1E-6 then
            begin
              FCmdMsg := 'Pick a point away from the center to measure from.';
              Exit;
            end;
            FRotRef := FCur;
            FStage := 2;
            FInput := '';
            FCmdMsg := '';
          end;
      else
        ToolCommit;
      end;

    ptErase:
      begin
        { hit test the raw pointer; a snap to a nearby endpoint would miss
          the thing clicked }
        P := PtF(FMouseSX, FMouseSY);
        I := FD.Doc.HitEdge(Proj, P.X, P.Y, 9 * FUIScale);
        if I < 0 then I := FD.Doc.HitTest(Proj, P.X, P.Y, 9 * FUIScale);
        { Ctrl softens rather than deletes, Ctrl+Shift brings it back }
        if (I >= 0) and (FEraseMode <> 0) then
        begin
          SetLength(FDoomed, 1);
          FDoomed[0] := I;
          SoftenDoomed(FEraseMode = 1);
        end
        else if I >= 0 then
        begin
          PushUndo;
          { a line between two regions held them apart; removing it should
            leave one region }
          WasLine := FD.Doc[I].Kind in [ekLine, ekArc];
          FD.Doc.Delete(I);
          { merging areas or opening a shape both fall out of rebuilding the
            faces, so neither needs its own rule }
          J := FaceCount;
          if WasLine and (RebuildFlatFaces < J) then
            FCmdMsg := 'Deleted - the faces either side are one now.'
          else
            FCmdMsg := 'Deleted.';
          SelectNone;
          RenderInk;
          RecomposeAll;
        end
        else
          FCmdMsg := 'Nothing under the cursor.';
      end;

    ptLine:
      if FStage = 0 then
      begin
        FP1 := FCur;
        FStage := 1;
        FDirLock := -1;
        { parallel and perpendicular start from the edge this line starts on
          (SketchUp's magenta pair); once a piece is drawn it takes over (see
          ToolCommit) }
        FInferMode := imAll;
        FParHas := False;
        I := FD.Doc.HitEdge(Proj, FMouseSX, FMouseSY, 9 * FUIScale,
          GUIDE_PICK_PX * FUIScale);
        if (I >= 0) and (FD.Doc[I].Kind = ekLine) and not FD.Doc[I].Dim then
        begin
          FParDir := P3(FD.Doc[I].B.X - FD.Doc[I].A.X,
                        FD.Doc[I].B.Y - FD.Doc[I].A.Y,
                        FD.Doc[I].B.Z - FD.Doc[I].A.Z);
          FParHas := Sqr(FParDir.X) + Sqr(FParDir.Y) + Sqr(FParDir.Z) > 1E-12;
        end;
      end
      else if FClickN >= 2 then
      begin
        { Double-click ends the run.  SketchUp does not do this, but a way to
          finish with the mouse was wanted.  The second click must not place
          a point too: it would leave a zero-length line, an invisible stray
          snap point. }
        ResetTool;
        FCmdMsg := 'Line finished.  Esc does the same.';
      end
      else
        ToolCommit;

    ptRect:
      if FStage = 0 then
      begin
        FP1 := FCur;
        FStage := 1;
        FInput := '';
      end
      else
        ToolCommit;

    ptArc:
      if FStage = 0 then
      begin
        FP1 := FCur;
        FStage := 1;
        { the edge this arc starts on, for Alt's tangent lock (see
          TangentBulge) }
        FArcTanHas := False;
        FArcTanLock := False;
        I := FD.Doc.HitEdge(Proj, FMouseSX, FMouseSY, 9 * FUIScale,
          GUIDE_PICK_PX * FUIScale);
        if (I >= 0) and (FD.Doc[I].Kind = ekLine) and not FD.Doc[I].Dim then
        begin
          FArcTanDir := P3(FD.Doc[I].B.X - FD.Doc[I].A.X,
                           FD.Doc[I].B.Y - FD.Doc[I].A.Y,
                           FD.Doc[I].B.Z - FD.Doc[I].A.Z);
          FArcTanHas := Sqr(FArcTanDir.X) + Sqr(FArcTanDir.Y) +
                        Sqr(FArcTanDir.Z) > 1E-12;
        end;
      end
      else if FStage = 1 then
      begin
        FP2 := FCur;
        FStage := 2;
      end
      else
        ToolCommit;

    ptCircle:
      if FStage = 0 then
      begin
        FP1 := FCur;
        FStage := 1;
      end
      else
        ToolCommit;

    ptText:
      if FStage = 0 then
      begin
        { SketchUp: double-click a face with the Text tool to label its area }
        if FClickN >= 2 then
        begin
          I := InContextFace(FaceAtPress);
          if I >= 0 then
          begin
            PushUndo;
            FD.Doc.AddText(FCur,
              FormatArea(FD.Doc.FaceArea(I), FD.Units), FInkColor);
            RenderInk;
            RecomposeAll;
            FCmdMsg := 'Area ' + FormatArea(FD.Doc.FaceArea(I), FD.Units);
            Exit;
          end;
        end;
        FP1 := FCur;
        FStage := 1;
        FInput := '';
      end
      else
        ToolCommit;

    ptFollow:
      case FStage of
        0:
          begin
            I := InContextFace(FaceAtPress);
            if I < 0 then
            begin
              FCmdMsg := 'Click the face to follow - that is the profile.';
              Exit;
            end;
            FFollowFace := I;
            FStage := 1;
            FInput := '';
            { edges picked beforehand are the path, SketchUp's first way of
              using the tool }
            for J := 0 to High(FSel) do
              if FD.Doc[FSel[J]].Kind in [ekLine, ekArc] then
              begin
                DoSweep(ChainFrom(FSel[J], Closed), Closed);
                Exit;
              end;
            FCmdMsg := 'Now the path: click a line or arc to follow along, a circle to ' +
              'follow round, or two points for an axis to spin on.';
          end;
        1:
          begin
            { a circle under the cursor means turning about its center; a
              line or open arc starts a path }
            I := FD.Doc.HitEdge(Proj, FMouseSX, FMouseSY, 9 * FUIScale);
            if (I >= 0) and (FD.Doc[I].Kind = ekArc) and (I <> FFollowFace) and
               (Abs(FD.Doc[I].Sweep) >= 2 * Pi - 1E-9) then
            begin
              DoRevolve(FD.Doc[I].C, ArcNormal(I), I);
              Exit;
            end;
            { An edge of the outline itself is the axis: a glass outline has
              one straight side down its middle, and clicking it is what
              anyone does.  Sweeping a face along its own edge means nothing.
              Any other line is still a sweep path. }
            if (I >= 0) and (FD.Doc[I].Kind = ekLine) and IsProfileEdge(I) then
            begin
              DoRevolve(FD.Doc[I].A,
                P3(FD.Doc[I].B.X - FD.Doc[I].A.X, FD.Doc[I].B.Y - FD.Doc[I].A.Y,
                   FD.Doc[I].B.Z - FD.Doc[I].A.Z));
              Exit;
            end;
            if (I >= 0) and (FD.Doc[I].Kind in [ekLine, ekArc]) then
            begin
              DoSweep(ChainFrom(I, Closed), Closed);
              Exit;
            end;
            FAxisA := FCur;
            FStage := 2;
            FCmdMsg := 'Second point on the axis.  Type 90 first for a quarter turn, or just click for all the way round.';
          end;
      else
        begin
          if Dist(FCur, FAxisA) < 1E-9 then
          begin
            FCmdMsg := 'The second point has to be somewhere else along the axis.';
            Exit;
          end;
          DoRevolve(FAxisA, P3(FCur.X - FAxisA.X, FCur.Y - FAxisA.Y, FCur.Z - FAxisA.Z));
        end;
      end;

    ptPush, ptDrill:
      if FStage = 0 then
      begin
        { double-click another face to repeat the last pull, as SketchUp
          does for a row of identical extrusions }
        if (FClickN >= 2) and (Abs(FLastPush) > 1E-9) then
        begin
          I := InContextFace(FaceAtPress);
          if I >= 0 then
          begin
            PushUndo;
            if FD.Doc.PushPull(I, FLastPush) then
            begin
              RenderInk;
              RecomposeAll;
              FCmdMsg := 'Same again - ' + FormatLen(Abs(FLastPush), FD.Units);
            end;
            Exit;
          end;
        end;
        FPushFace := InContextFace(FaceAtPress);
        { a face too small or crowded to click can be picked first, then
          pushed }
        if (FPushFace < 0) and (Length(FSel) = 1) and
           (FD.Doc[FSel[0]].Kind = ekFace) then
          FPushFace := FSel[0];
        if FPushFace < 0 then
          FCmdMsg := 'No face there.  Close a loop of lines to make one.'
        else
        begin
          FP1 := FCur;
          FPushSX := FMouseSX;
          FPushSY := FMouseSY;
          FStage := 1;
          if Abs(Dot3(FD.Doc.FaceNormal(FPushFace), ViewDir(Proj))) > 0.98 then
            FCmdMsg := 'Type a distance, or move and click.  ' +
              'Press V for a 3D view to watch it move.'
          else
            FCmdMsg := 'Type a distance, or move and click.';
        end;
      end
      else
        ToolCommit;

    ptOffset:
      if FStage = 0 then
      begin
        FOffFace := InContextFace(FaceAtPress);
        { as with push/pull, a crowded face can be selected first }
        if (FOffFace < 0) and (Length(FSel) = 1) and
           (FD.Doc[FSel[0]].Kind = ekFace) then
          FOffFace := FSel[0];
        if FOffFace < 0 then
          FCmdMsg := 'No face there.  Close a loop of lines to make one.'
        else
        begin
          { Hold the cursor to this face's plane until done; otherwise the
            infinite model axes can pull it far off the face being offset. }
          FFacePt := FD.Doc[FOffFace].Poly[0];
          FFaceNm := Norm3(FD.Doc.FaceNormal(FOffFace));
          FPlaneFromFace := True;
          FStage := 1;
          FInput := '';
          FCmdMsg := 'Move in or out, or type a wall thickness.';
        end;
      end
      else
        CommitOffset;

    ptDim:
      case FStage of
        0:
          begin
            { Click the body of a line and move away to dimension the whole
              line (from SketchUp's docs).  A snapped point (corner, midpoint,
              center) is a point-to-point start; only a free cursor on an
              edge takes the edge.  What the hover lit is what the click
              takes, so the two cannot disagree. }
            FDimPrefer := P3(0, 0, 0);
            if (FHoverEnt >= 0) and (FD.Doc[FHoverEnt].Kind = ekArc) then
            begin
              { a curve is not measured by one of its straight pieces: a
                circle gives its diameter, an arc its radius (SketchUp's
                rule), and the end on the curve follows the pointer }
              FDimArc := FHoverEnt;
              FStage := 2;
              if Abs(FD.Doc[FHoverEnt].Sweep) >= 2 * Pi - 1E-9 then
                FCmdMsg := 'The diameter - move round the circle to turn it, click to place.'
              else
                FCmdMsg := 'The radius - move along the arc to turn it, click to place.';
            end
            else if FHoverEdgeOK and (Dist(FHoverEdgeA, FHoverEdgeB) > 1E-9) then
            begin
              FP1 := FHoverEdgeA;
              FP2 := FHoverEdgeB;
              FStage := 2;
              FCmdMsg := 'The whole edge, ' +
                FormatLen(Dist(FP1, FP2), FD.Units) +
                ' - move away to place the line.';
            end
            else if not DimAnchored then
            begin
              { Nothing to anchor to.  A dimension must hang off real
                geometry (end, midpoint, on-edge, intersection, center) so it
                updates with the model; a floating number goes stale. }
              FCmdMsg := 'A dimension has to measure something - a corner, ' +
                         'a midpoint, a center, or a point on an edge.';
              InvalidateStatus;
            end
            else
            begin
              FP1 := FCur;
              FStage := 1;
            end;
          end;
        1:
          { the far end must be anchored too }
          if DimAnchored then
          begin
            FP2 := FCur;
            FStage := 2;
          end
          else
          begin
            FCmdMsg := 'The other end has to be on something too - a corner, ' +
                       'a midpoint, a center, or a point on an edge.';
            InvalidateStatus;
          end;
      else
        ToolCommit;
      end;

    ptMeasure:
      if FStage = 0 then
      begin
        FP1 := FCur;
        { what the tape starts from decides the guide: an edge gives a
          parallel guide line, anything else a point (SketchUp's rule) }
        FMeasEdge := FD.Doc.HitEdge(Proj, FMouseSX, FMouseSY, 9 * FUIScale);
        if (FMeasEdge >= 0) and
           not (FD.Doc[FMeasEdge].Kind in [ekLine, ekArc]) then
          FMeasEdge := -1;
        FStage := 1;
      end
      else if FStage = 1 then
      begin
        FP2 := FCur;
        LayGuide;
        FRunOK := True;
        FRunA := FP1;
        FRunB := FP2;
        FCmdMsg := RunReading(FP1, FP2) + '   /keep makes it a dimension';
        ResetTool;
      end
      else
      begin
        FP1 := FCur;
        FStage := 1;
      end;
  end;
  pbScreen.Invalidate;
  pbCmd.Invalidate;
  FLastStatus := 0;
  InvalidateStatus;
end;

{ Why a typed measurement was not taken, in useful words, or '' if it is
  fine. }
function TMainForm.WhyNotAMeasurement(const S: string): string;
var
  T, LW, LH: string;
  P, NDash, Ix: Integer;
  D, CX, CY, CZ: Double;
  Fields: array[0..2] of string;
begin
  Result := '';
  T := Trim(S);
  if T = '' then Exit;

  { a place or an offset, which move and line read }
  if (T[1] = '[') or (T[1] = '<') then
  begin
    if ParseTriple(T, FD.Units, CX, CY, CZ) > 0 then Exit;
    Result := 'That is not a place.  [4,0,8] is a point in the drawing, ' +
      '<4,0,8> is that far from here.';
    Exit;
  end;

  { two sides at once, which only the rectangle asks for }
  P := Pos('x', LowerCase(T));
  if P = 0 then P := Pos(',', T);
  if (P > 0) and (FTool = ptRect) then
  begin
    LW := Trim(Copy(T, 1, P - 1));
    LH := Trim(Copy(T, P + 1, MaxInt));
    if ((LW = '') or ParseLen(LW, FD.Units, D)) and
       ((LH = '') or ParseLen(LH, FD.Units, D)) and
       ((LW <> '') or (LH <> '')) then Exit;
    Result := 'Two sides, like 8x10 - or 8/10 from the number pad.';
    Exit;
  end;

  { One length where the rectangle wants two: it parses as a length, so
    without this RectTarget gives up silently and the corner comes from the
    cursor.  6-8-15x4-0-0 is the form that works. }
  if (FTool = ptRect) and (P = 0) and ParseLen(T, FD.Units, D) then
  begin
    Result := Format('%s reads fine - a rectangle wants both sides.  ' +
      'Type %s x 4-0-0, or %s/4-0-0 from the number pad.  A comma on the ' +
      'end instead sets that side and leaves the other on the cursor.',
      [T, T, T]);
    Exit;
  end;

  if ParseLen(T, FD.Units, D) then Exit;

  { The dashed form's usual mistake: a field out of range for the drawing's
    precision.  Say which number and what the drawing counts in. }
  NDash := 0;
  Fields[0] := '';
  Fields[1] := '';
  Fields[2] := '';
  for Ix := 1 + Ord(T[1] = '-') to Length(T) do
    if T[Ix] = '-' then
    begin
      Inc(NDash);
      if NDash > 2 then Break;
    end
    else
      Fields[NDash] := Fields[NDash] + T[Ix];

  if (NDash = 2) and (Fields[2] <> '') and TryStrToFloat(Fields[2], D) and
     (D >= LenDenom) then
  begin
    Result := Format('The last number counts in 1/%d of an inch, so it has ' +
      'to be under %d - you typed %s.  Change PREC if this drawing is in ' +
      'something else.', [LenDenom, LenDenom, Fields[2]]);
    Exit;
  end;
  if (NDash = 2) and (Fields[1] <> '') and TryStrToFloat(Fields[1], D) and
     (D >= 12) then
  begin
    Result := 'The middle number is inches, so it has to be under 12.';
    Exit;
  end;

  Result := Format('I cannot read "%s" as a length.  Try 12, or 12''6", or ' +
    '3 1/2 - or feet-inches-1/%d like 6-8-15, which is six foot eight and ' +
    'fifteen %dths.', [T, LenDenom, LenDenom]);
end;

procedure TMainForm.ToolCommit;
var
  Fil: TFillet;
  FilTyped: Boolean;
  I, NPieces, NWas, NBroke: Integer;
  T, C: TP3;
  Loop: TP3Array;
  L, R, A0, Sweep, Bulge, U1, V1, U2, V2, UC, VC, NU, NV, Ln: Double;
  K: Integer;
  Ok: Boolean;
  Ang: Double;
  RA, RB: TP3;
  RNote: string;
  Base: Integer;
  Copies: array of Integer;
  ArcPl: TPlane;
  Stopped, DrillTyped: Boolean;
  Tk: QWord;
  WasRigid: Boolean;
begin
  Trail('commit ' + TOOL_NAMES[FTool] + ' stage=' + IntToStr(FStage));
  case FTool of
    ptRotate:
      begin
        if FStage < 1 then Exit;
        Ang := RotAngle;
        if Abs(Ang) < 1E-9 then
        begin
          FCmdMsg := 'Nothing turned - the angle was nought.';
          ResetTool;
          Exit;
        end;
        PushUndo;
        if FMoveCopy then
        begin
          { the copy stands alone and turns whole; the original and what
            hangs off it stay put }
          FArray.Live := True;
          FArray.Rotate := True;
          FArray.C := FP1;
          FArray.Axis := FRotAxis;
          FArray.Ang := Ang;
          SetLength(FArray.Src, Length(FSel));
          for I := 0 to High(FSel) do FArray.Src[I] := FSel[I];
          FD.Doc.ArrayRotate(FArray.Src, FP1, FRotAxis, Ang, 1, False, FArray.Made);
          SetLength(Copies, Length(FArray.Made));
          for I := 0 to High(Copies) do Copies[I] := FArray.Made[I];
          SelectNone;
          for I := 0 to High(Copies) do SelectAdd(Copies[I]);
          FCmdMsg := 'Copied, turned ' + FormatAngle(RadToDeg(Ang)) +
            '.  Type 6x for six round, or /6 to divide the turn.';
        end
        else
        begin
          FD.Doc.RotateEnts(FMoveGroupEnts, FP1, FRotAxis, Ang);
          FD.Doc.RotateVerts(FMoveVerts, FP1, FRotAxis, Ang);
          FCmdMsg := 'Turned ' + FormatAngle(RadToDeg(Ang));
        end;
        RebuildFlatFaces;
        RenderInk;
        RecomposeAll;
        SetLength(FMoveVerts, 0);
        FMoveCopy := False;
              ResetTool;
        FInput := '';
      end;

    ptProtractor:
      begin
        if FStage < 1 then Exit;
        Ang := RotAngle;
        T := RotV(RotRefDir, FRotAxis, Ang);
        PushUndo;
        FD.Doc.AddGuide(FP1, P3(FP1.X + T.X, FP1.Y + T.Y, FP1.Z + T.Z));
        RenderInk;
        RecomposeAll;
        FCmdMsg := 'Guide laid at ' + FormatAngle(RadToDeg(Ang)) + '.';
        ResetTool;
        FInput := '';
      end;

    ptOffset:
      begin
        CommitOffset;
        Exit;
      end;
    ptFollow:
      begin
        if FStage = 2 then
          DoRevolve(FAxisA, P3(FCur.X - FAxisA.X, FCur.Y - FAxisA.Y, FCur.Z - FAxisA.Z));
        Exit;
      end;

    ptLine:
      begin
        T := PreviewTarget;
        if Dist(FP1, T) > 1E-9 then
        begin
          PushUndo;
          { This line says the areas it bounds are wanted, even drawn over an
            existing edge; that is how an erased face comes back (SketchUp's
            healing, see FHealOn). }
          FHealOn := True;
          FHealA := FP1;
          FHealB := T;
          if FD.Doc.HasLine(FP1, T) then
            FCmdMsg := FormatLen(Dist(FP1, T), FD.Units) + '   (already an edge)'
          else
          begin
            { drawn along an existing edge, the overlap is split into one
              edge rather than two stacked; otherwise a plain add }
            NPieces := FD.Doc.AddLineSplit(FP1, T, FInkColor, FEdgeW);
            if NPieces > 1 then
              FCmdMsg := FormatLen(Dist(FP1, T), FD.Units) +
                Format('   (split along an edge - %d pieces)', [NPieces])
            else
              FCmdMsg := FormatLen(Dist(FP1, T), FD.Units);
            { and both are cut where it crosses something.  Count from the
              end: AddLineSplit deletes what it overlapped and appends the
              pieces, shifting indices above them. }
            NWas := FD.Doc.Live - Max(1, NPieces);
            NBroke := FD.Doc.SplitCrossings(NWas);
            if NBroke > 0 then
              FCmdMsg := FCmdMsg + Format('   (broke %d edge%s at the crossings)',
                [NBroke, IfThen(NBroke = 1, '', 's')]);
          end;
          { whatever this did to the flat areas is worked out by asking what
            the edges enclose, not by a rule per case }
          { parallel and perpendicular are now measured from the piece just
            drawn (see TInferMode) }
          FParDir := P3(T.X - FP1.X, T.Y - FP1.Y, T.Z - FP1.Z);
          FParHas := Sqr(FParDir.X) + Sqr(FParDir.Y) + Sqr(FParDir.Z) > 1E-12;
          I := FaceCount;
          K := RebuildFlatFaces;
          FHealOn := False;
          if K > I then
            FCmdMsg := FCmdMsg + Format('   %d face%s now',
              [K, IfThen(K = 1, '', 's')]);
          RenderInk;
          RecomposeAll;
          FP1 := T;
          FCur := T;
        end;
        FInput := '';
        FDirLock := -1;
      end;

    ptRect:
      begin
        T := RectTarget;
        RectSides(FP1, T, FD.Plane, U1, V1);
        if (U1 > 1E-9) and (V1 > 1E-9) then
        begin
          PushUndo;
          NWas := FD.Doc.Live;
          Loop := RectCorners(FP1, T, FD.Plane);
          { An edge exactly on an existing one is the same edge; adding it
            again stacks lines and labels.  And a side drawn over an edge
            says the area it bounds is wanted (healing, see FHealOn), so a
            rectangle traced round an opening brings the face back.  One
            side is enough. }
          for I := 0 to 3 do
            if not FD.Doc.HasLine(Loop[I], Loop[(I + 1) mod 4]) then
              FD.Doc.AddLine(Loop[I], Loop[(I + 1) mod 4],
                FInkColor, FEdgeW, False)
            else if not FHealOn then
            begin
              FHealOn := True;
              FHealA := Loop[I];
              FHealB := Loop[(I + 1) mod 4];
            end;
          FD.Doc.SplitCrossings(NWas);
          RebuildFlatFaces;
          FHealOn := False;
          RenderInk;
          RecomposeAll;
          Trail('rect made, ' + IntToStr(FaceCount) + ' faces now');
          FCmdMsg := Format('%s x %s   area %s',
            [FormatLen(U1, FD.Units), FormatLen(V1, FD.Units),
             FormatArea(U1 * V1, FD.Units)]);
        end
        else
        begin
          { Say why: usually one side was within half a snap step of zero
            (on a 1' snap, anything within 6" of straight), rounded away. }
          RectSides(FP1, WorldAt(FMouseSX, FMouseSY), FD.Plane, U2, V2);
          FCmdMsg := Format('A rectangle needs two sides - that one is %s by %s.',
            [FormatLen(U2, FD.Units), FormatLen(V2, FD.Units)]);
          if (SnapStep > 0) and (Min(U2, V2) > 1E-9) and
             (Min(U2, V2) < SnapStep / 2) then
            FCmdMsg := FCmdMsg + Format('  The snap is %s, so the short side ' +
              'rounded away to nothing - a finer snap, or pull it further out.',
              [FormatLen(SnapStep, FD.Units)]);
        end;
        ResetTool;
        FInput := '';
      end;

    ptArc:
      begin
        { Rounding a corner: the arc goes in and the two lines are cut at the
          touch points, leaving the square corner pieces to erase or keep, as
          SketchUp does.  Only the second click of a double-click trims them. }
        if ArcFillet(Fil, FilTyped) then
        begin
          PushUndo;
          FD.Doc.ApplyFillet(Fil, FSidesArc, FInkColor, FEdgeW, False);
          FLastFilletR := Fil.R;
          RebuildFlatFaces;
          RenderInk;
          RecomposeAll;
          FCmdMsg := 'Arc tangent to both edges, radius ' +
            FormatLen(Fil.R, FD.Units) +
            '.  The corner is still there - erase it, or double-click to trim it.';
          FLastFillet := Fil;
          FFilletPending := True;
          FFilletSeq := FEditSeq;
          FFilletTick := GetTickCount64;
          ResetTool;
          Exit;
        end;
        Ok := ArcPicks(FCur, ArcPl, C, R, A0, Sweep, Bulge);
        if not Ok and (Dist(FP1, FP2) < 1E-9) then
        begin
          ResetTool;
          Exit;
        end;
        if Ok then
        begin
          PushUndo;
          NWas := FD.Doc.Live;
          FD.Doc.AddArc(C, R, A0, Sweep, ArcPl, FInkColor, FEdgeW);
          FD.Doc.SetArcSides(FD.Doc.Live - 1, FSidesArc);
          FCmdMsg := 'Arc radius ' + FormatLen(R, FD.Units);
          NBroke := FD.Doc.SplitCrossings(NWas);
          if NBroke > 0 then
            FCmdMsg := FCmdMsg + Format('   (broke %d edge%s at the crossings)',
              [NBroke, IfThen(NBroke = 1, '', 's')]);
          I := FaceCount;
          if RebuildFlatFaces > I then
            FCmdMsg := FCmdMsg + '   closed a face';
          RenderInk;
          RecomposeAll;
        end;
        ResetTool;
      end;

    ptCircle:
      begin
        if (FInput <> '') and ParseLen(FInput, FD.Units, L) then
          R := L
        else
          R := Dist(FP1, FCur);
        if R > 1E-9 then
        begin
          PushUndo;
          NWas := FD.Doc.Live;
          FD.Doc.AddArc(FP1, R, 0, 2 * Pi, FD.Plane, FInkColor, FEdgeW);
          FD.Doc.SetArcSides(FD.Doc.Live - 1, FSidesCircle);
          NBroke := FD.Doc.SplitCrossings(NWas);
          RebuildFlatFaces;
          RenderInk;
          RecomposeAll;
          FCmdMsg := Format('Circle radius %s   area %s',
            [FormatLen(R, FD.Units), FormatArea(Pi * R * R, FD.Units)]);
          if NBroke > 0 then
            FCmdMsg := FCmdMsg + Format('   (broke %d edge%s at the crossings)',
              [NBroke, IfThen(NBroke = 1, '', 's')]);
        end;
        ResetTool;
      end;

    ptMove:
      begin
        if FDimMove >= 0 then
        begin
          PushUndo;
          FD.Doc.SetDimOffset(FDimMove, DimOffset3);
          RenderInk;
          RecomposeAll;
          FCmdMsg := 'Dimension moved.';
          ResetTool;
          Exit;
        end;
        T := MoveDelta;
        if (Abs(T.X) > 1E-9) or (Abs(T.Y) > 1E-9) or (Abs(T.Z) > 1E-9) then
        begin
          PushUndo;
          if FMoveCopy then
          begin
            { a copy stands on its own, so nothing stretches to reach it }
            FArray.Live := True;
            FArray.Rotate := False;
            FArray.D := T;
            SetLength(FArray.Src, Length(FSel));
            for I := 0 to High(FSel) do FArray.Src[I] := FSel[I];
            FD.Doc.ArrayMove(FArray.Src, T, 1, False, FArray.Made);
            FCmdMsg := 'Copied ' + FormatLen(
              Sqrt(Sqr(T.X) + Sqr(T.Y) + Sqr(T.Z)), FD.Units) +
              '.  Type 3x for three that far apart, or /3 to divide the run.';
          end
          else if FMoveRigid then
          begin
            { a part just built goes as one piece; nothing comes along,
              whatever corners it shared where it was made }
            FD.Doc.TranslateEnts(FSel, T);
            FCmdMsg := 'Placed.';
          end
          else if FDetachMove then
          begin
            { /detach: take it away alone, leaving what it was joined to.
              SketchUp always stretches, but a guide-like line should not
              drag other geometry along. }
            FD.Doc.TranslateEnts(FSel, T);
            FCmdMsg := 'Moved ' + FormatLen(
              Sqrt(Sqr(T.X) + Sqr(T.Y) + Sqr(T.Z)), FD.Units) +
              '   (on its own - nothing stretched to follow)';
          end
          else
          begin
            { every corner where a moving one sat travels too, so joined
              geometry stretches to follow }
            Tk := GetTickCount64;
            { whole groups first, each as one piece; then the loose corners }
            FD.Doc.TranslateEnts(FMoveGroupEnts, T);
            FD.Doc.MoveVerts(FMoveVerts, T);
            Took('move the corners', Tk);
            FCmdMsg := 'Moved ' + FormatLen(
              Sqrt(Sqr(T.X) + Sqr(T.Y) + Sqr(T.Z)), FD.Units);
          end;
          { Moving an edge changes what the edges enclose, so faces are rebuilt
            (which also stretches them).  A built part placed whole is the
            exception: rebuilding would cap its open duct ends, so its
            openings are seeded as seen instead. }
          Tk := GetTickCount64;
          if FMoveRigid then SeedRegions else RebuildFlatFaces;
          Took('work the faces out', Tk);
          Tk := GetTickCount64;
          RenderInk;
          Took('render', Tk);
          Tk := GetTickCount64;
          RecomposeAll;
          Took('recompose', Tk);
        end;
        SetLength(FMoveVerts, 0);
        FMoveCopy := False;
              WasRigid := FMoveRigid;
        ResetTool;
        FInput := '';
        { A placed built part is let go and the select tool comes back;
          left selected, the next click would pick it up again. }
        if WasRigid then
        begin
          SelectNone;
          SetTool(ptSelect);
          FCmdMsg := 'Placed.';
        end
        { what the move tool picked up by itself is released once moved; a
          selection the user made stays }
        else if FMoveTook and not FArray.Live then SelectNone;
        FMoveTook := False;
      end;

    ptPush, ptDrill:
      begin
        R := PushDistance;
        Stopped := False;
        FCmdMsg := '';
        { A drill goes through: the far end must land exactly on the far
          wall's plane or there is no tunnel (see TWorkDoc.ThroughDistance).
          With a typed depth it is a blind hole that deep, through any
          passages on the way (push/pull stops at the first).  Passages a
          blind hole crosses are not cut open into it yet. }
        DrillTyped := (FTool = ptDrill) and (FInput <> '') and ParseLen(FInput, FD.Units, L);
        if (FTool = ptDrill) and (Abs(R) > 1E-9) and not DrillTyped then
          R := FD.Doc.ThroughDistance(FPushFace, R);
        { a drill goes in, never out, whichever way the mouse drifted: the
          block's far wall says which way is in }
        if DrillTyped and (Abs(R) > 1E-9) then
        begin
          if Abs(FD.Doc.ThroughDistance(FPushFace, -1E-3) + 1E-3) > 1E-9 then R := -Abs(R)
          else if Abs(FD.Doc.ThroughDistance(FPushFace, 1E-3) - 1E-3) > 1E-9 then R := Abs(R);
        end;
        { push/pull stops at a tunnel already through the solid, as
          SketchUp's does; drill goes on, and crossing holes are cut open
          into each other }
        if (FTool = ptPush) and (Abs(R) > 1E-9) then
        begin
          L := BoreLimit(FD.Doc, FPushFace, R);
          if Abs(L) < Abs(R) - 1E-9 then
          begin
            R := L;
            Stopped := True;
          end;
        end;
        if Abs(R) > 1E-9 then
        begin
          PushUndo;
          if FD.Doc.PushPull(FPushFace, R) then
          begin
            FLastPush := R;      // so a double-click can repeat it
            { the click that finished this push is not the first half of a
              double-click; a quick second click would repeat the push }
            FClickT := 0;
            if (FTool = ptDrill) and (FD.Doc.LastBore >= 0) then
              if CutCrossingBores(FD.Doc, FD.Doc.LastBore) > 0 then
                FCmdMsg := 'Drilled through - the tunnels cut into each other.';
            { Every area the push made is known now (above all a tunnel's far
              end, an opening that must not be capped by the next rebuild).
              Pressed flat, the solid is a loose face again and whatever it
              stood on must be cut round it, or the two share a plane. }
            if FD.Doc.LastFlattened then RebuildFlatFaces;
            SeedRegions;
            SelectNone;
            RenderInk;
            RecomposeAll;
            if Stopped then
              FCmdMsg := 'Stopped at the tunnel, ' + FormatLen(Abs(R), FD.Units) +
                ' in.  Drill (B) goes on through.'
            else if FCmdMsg = '' then
            begin
              if (FTool = ptDrill) and DrillTyped then
                FCmdMsg := 'Drilled ' + FormatLen(Abs(R), FD.Units) +
                  ' in, and stopped there.'
              else if FTool = ptDrill then
                FCmdMsg := 'Drilled through, ' + FormatLen(Abs(R), FD.Units)
              else
                FCmdMsg := 'Pulled ' + FormatLen(Abs(R), FD.Units);
            end;
          end;
        end;
        FPushFace := -1;
        ResetTool;
      end;

    ptText:
      begin
        { Nothing typed is no note, but not a reason to put the tool away
          either: resetting would turn every following letter back into a
          tool shortcut. }
        if Trim(FInput) = '' then
        begin
          FCmdMsg := 'Type the note first, then move away and press Enter.';
          Exit;
        end;
        begin
          PushUndo;
          { FP1 is what the note is about; the cursor is where it goes.  The
            same point gives a plain label; moving away first adds a leader. }
          FD.Doc.AddNote(FCur, FP1, Trim(FInput), FInkColor);
          RenderInk;
          RecomposeAll;
          if Dist(FCur, FP1) > 1E-9 then
            FCmdMsg := 'Note added, pointing at where you started.'
          else
            FCmdMsg := 'Note added.  Next time, move away before Enter for ' +
              'a leader line.';
        end;
        ResetTool;
      end;

    ptDim:
      begin
        if (FDimArc >= 0) and DimRadialAt(RA, RB, RNote) then
        begin
          { a diameter or radius: on the circle, no offset }
          PushUndo;
          FD.Doc.AddDim(RA, RB, FInkColor, P3(0, 0, 0), RNote);
          RenderInk;
          RecomposeAll;
          FCmdMsg := IfThen(Copy(RNote, 1, 1) = 'R', 'Radius ', 'Diameter ') + FormatLen(Dist(RA, RB), FD.Units);
        end
        else if Dist(FP1, FP2) > 1E-9 then
        begin
          PushUndo;
          FD.Doc.AddDim(FP1, FP2, FInkColor, DimOffset3);
          RenderInk;
          RecomposeAll;
          FCmdMsg := 'Dimension ' + FormatLen(Dist(FP1, FP2), FD.Units);
        end;
        ResetTool;
      end;

    ptMeasure:
      begin
        if FStage = 1 then
        begin
          { A typed distance is the second click: the point lands that far
            along the run's direction and the guide goes down as a click
            leaves it. }
          FP2 := PreviewTarget;
          if Dist(FP1, FP2) < 1E-9 then
          begin
            FCmdMsg := 'Type how far, or click the second point.';
            Exit;
          end;
          FInput := '';
          LayGuide;
          FRunOK := True;
          FRunA := FP1;
          FRunB := FP2;
          FCmdMsg := RunReading(FP1, FP2) + '   /keep makes it a dimension';
          RenderInk;
          RecomposeAll;
        end;
        { That is the whole tape.  No third stage waits for Enter: one would
          leave a phantom rubber band and drop a dimension much later.  /keep
          makes a dimension of the run. }
        ResetTool;
      end;
    ptSelect, ptErase, ptOrbit: ;   // these act on the drag; nothing to commit
  end;
  pbScreen.Invalidate;
  pbCmd.Invalidate;
  pbDeck.Invalidate;
  FLastStatus := 0;
  InvalidateStatus;
end;

{ What a run measures, in trade terms: length and components, plus the fall
  (degrees off level; 0 level, 90 a riser) and the swing (heading in plan
  from the red axis), which together describe a rolling offset.  Two
  decimals, since 44.98 vs 45 is the error worth seeing. }
function TMainForm.RunReading(const A, B: TP3): string;
var
  DX, DY, DZ, Flat, Fall, Swing: Double;
begin
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  DZ := B.Z - A.Z;
  Result := Format('%s   (dX %s  dY %s  dZ %s)',
    [FormatLen(Dist(A, B), FD.Units), FormatLen(Abs(DX), FD.Units),
     FormatLen(Abs(DY), FD.Units), FormatLen(Abs(DZ), FD.Units)]);

  Flat := Sqrt(DX * DX + DY * DY);
  if (Flat < 1E-9) and (Abs(DZ) < 1E-9) then Exit;

  if Flat < 1E-9 then
    Result := Result + '   straight up'
  else
  begin
    Fall := RadToDeg(ArcTan2(DZ, Flat));
    Swing := RadToDeg(ArcTan2(DY, DX));
    if Swing < 0 then Swing := Swing + 360;
    if Abs(Fall) < 1E-4 then
      Result := Result + '   level'
    else
      Result := Result + Format('   %.2f' + #176 + ' off level',
        [Abs(Fall)]);
    Result := Result + Format(',  %.2f' + #176 + ' round', [Swing]);
  end;
end;

{ everything after the first word, exactly as typed, for path arguments }
function RawTail(const S: string): string;
var
  P: Integer;
begin
  P := Pos(' ', Trim(S));
  if P <= 0 then Result := ''
  else Result := Trim(Copy(Trim(S), P + 1, MaxInt));
end;

{ The typed commands. }
function TMainForm.RunCommand(const S: string): Boolean;
var
  ReDoomed: array of Boolean;
  W, Rest: string;
  P, I, N, J, K: Integer;
  RL, RL2: Double;
begin
  Result := True;
  W := LowerCase(Trim(S));
  Rest := '';
  P := Pos(' ', W);
  if P > 0 then
  begin
    Rest := Trim(Copy(W, P + 1, MaxInt));
    W := Copy(W, 1, P - 1);
  end;

  { however it arrived (typed, picked, menu), it counts as used }
  { by its canonical name, so /e and /erase are one entry }
  I := CmdIndex(W);
  if I >= 0 then NoteCmdUsed(CMD_LIST[I].Name);

  if (W = 'line') or (W = 'l') then SetTool(ptLine)
  else if (W = 'select') or (W = 's') then SetTool(ptSelect)
  else if (W = 'move') or (W = 'mv') then SetTool(ptMove)
  else if (W = 'arc') or (W = 'a') then SetTool(ptArc)
  else if (W = 'circle') or (W = 'c') then SetTool(ptCircle)
  else if (W = 'text') or (W = 'note') or (W = 'n') then SetTool(ptText)
  else if (W = 'erase') or (W = 'e') or (W = 'del') then SetTool(ptErase)
  else if (W = 'orbit') or (W = 'spin') then SetTool(ptOrbit)
  { a size for the picked dimension; a bare length does this too, the
    command is for the other end and for scripts }
  else if (W = 'resize') or (W = 'size') then
  begin
    if SelectedDim < 0 then
      FCmdMsg := 'Pick one dimension first, then say what it should read.'
    else
    begin
      { "14' start" or "14' other" moves the end it was drawn from }
      W := Trim(Rest);
      I := LastDelimiter(' ', W);
      N := 1;                            { 1 = the end it was drawn to }
      if I > 0 then
      begin
        Rest := Trim(Copy(W, I + 1, MaxInt));
        if (Rest = 'start') or (Rest = 'first') or (Rest = 'other') or
           (Rest = 'a') or (Rest = 'from') then
        begin
          N := 0;
          W := Trim(Copy(W, 1, I - 1));
        end;
      end;
      if not ParseLen(W, FD.Units, RL) then
        FCmdMsg := 'I could not read "' + W + '" as a size.'
      else
        ApplyDimResize(RL, N = 1);
    end;
  end
  { the same as the right-click menu, for keyboard and scripts }
  else if (W = 'reverse') or (W = 'rev') or (W = 'flip') then
  begin
    N := 0;
    for I := 0 to High(FSel) do
      if FD.Doc[FSel[I]].Kind = ekFace then Inc(N);
    if N = 0 then
      FCmdMsg := 'Pick a face first - reverse turns over the faces you have selected.'
    else
    begin
      PushUndo;
      N := ReverseSelectedFaces;
      if N = 1 then FCmdMsg := 'Face turned over.'
      else FCmdMsg := Format('%d faces turned over.', [N]);
    end;
  end
  else if (W = 'group') or (W = 'makegroup') then MakeGroup
  else if (W = 'explode') or (W = 'ungroup') then ExplodeGroups
  else if (W = 'edit') or (W = 'opengroup') then
  begin
    if SoleGroup > 0 then OpenGroup(SoleGroup)
    else FCmdMsg := 'Pick one group first - or double-click it.';
  end
  else if (W = 'leave') or (W = 'closegroup') then
  begin
    if FD.Doc.Context <> 0 then CloseGroup
    else FCmdMsg := 'No group is open.';
  end
  else if (W = 'hide') or (W = 'putaway') then
    { the name as typed; groups match it whatever the case }
    if Rest = '' then HideGroups(True, '')
    else HideGroups(True, Copy(Trim(S), Pos(' ', Trim(S)) + 1, MaxInt))
  else if (W = 'show') or (W = 'unhide') then
    if Rest = '' then HideGroups(False, '')
    else HideGroups(False, Copy(Trim(S), Pos(' ', Trim(S)) + 1, MaxInt))
  else if W = 'lock' then LockGroups(True)
  else if W = 'unlock' then LockGroups(False)
  else if (W = 'name') or (W = 'rename') then
    { the name as typed, not lowercased with the command }
    if Rest = '' then RenameGroup('')
    else RenameGroup(Copy(Trim(S), Pos(' ', Trim(S)) + 1, MaxInt))
  else if (W = 'rect') or (W = 'rectangle') or (W = 'r') then SetTool(ptRect)
  else if (W = 'measure') or (W = 'm') or (W = 'tape') then SetTool(ptMeasure)
  else if (W = 'dimension') or (W = 'dim') then SetTool(ptDim)
  else if (W = 'offset') or (W = 'f') then SetTool(ptOffset)
  else if (W = 'rotate') or (W = 'q') or (W = 'turn') then SetTool(ptRotate)
  else if (W = 'protractor') or (W = 'angle') then SetTool(ptProtractor)
  else if (W = 'drill') or (W = 'bore') or (W = 'punch') then SetTool(ptDrill)
  { the tool is REVOLVE; Follow Me (SketchUp's name) still works }
  else if (W = 'revolve') or (W = 'followme') or (W = 'follow') or
          (W = 'lathe') then SetTool(ptFollow)
  { not /new here: that is a new sheet further down, and the first match
    wins }
  else if (W = 'whatsnew') or (W = 'changes') then ShowWhatsNew
  else if (W = 'transition') or (W = 'trans') or (W = 'fitting') or (W = 'elbow') or (W = 'tee') then BuildTransitionWizard
  else if (W = 'spool') or (W = 'pipe') or (W = 'scratchpad') then BuildSpoolWizard
  else if (W = 'stairs') or (W = 'stair') then BuildStairWizard
  else if (W = 'radiant') or (W = 'pex') or (W = 'hydronic') then BuildRadiantWizard
  else if W = 'rendertime' then RenderTiming
  else if W = 'quick' then
  begin
    FQuickFrames := not FQuickFrames;
    FCameraMoving := False;
    RepaintPaper; RenderInk; RecomposeAll; Invalidate;
    if FQuickFrames then FCmdMsg := 'Quick frames while the camera moves: on.'
    else FCmdMsg := 'Quick frames while the camera moves: off - every frame at full quality.';
  end
  else if W = 'threads' then
  begin
    FThreads := not FThreads;
    DefaultThreads := FThreads;
    for I := 0 to High(FDrawings) do FDrawings[I].Doc.Threads := FThreads;
    RenderInk; RecomposeAll; Invalidate;
    if FThreads then FCmdMsg := 'Worker threads: on - the lines-on-faces cache is built off the main thread.'
    else FCmdMsg := 'Worker threads: off - everything on the main thread.';
  end
  else if (W = 'report') or (W = 'bug') then ReportBug('', '', '')
  else if W = 'touch' then
    FCmdMsg := Format('Touch: hook %s, %d events so far, %d fingers down.',
      [BoolToStr(FTouchOn, True), FTouchCount, Length(FTouches)])
  else if (W = 'sysinfo') or (W = 'machine') then
  begin
    { what a report would say about this machine, to see before sending }
    FCmdMsg := 'That is what goes with a report about this machine.';
    WriteLn(MachineText);
    Flush(Output);
    Trail('machine:' + LineEnding + MachineText);
    ShowFacts('This machine, as a report says it', MachineText);
  end
  { for testing: what an update does at the end, without the update.  Start
    again with --updated to see the drawings come back. }
  else if W = 'handoff' then
  begin
    SaveDraft;
    WriteHandoff;
    FHandingOver := True;
    Close;
  end
  else if W = 'state' then
  begin
    { the rest of a report: what the program is doing and how it is set }
    FCmdMsg := 'That is what goes with a report about the program right now.';
    WriteLn(DiagnosticText);
    WriteLn(SettingsText);
    Flush(Output);
    ShowLongText('The program, as a report says it',
      DiagnosticText + LineEnding + SettingsText);
  end
  else if W = 'timings' then
  begin
    { on, do the slow thing, off: turning it off shows what it saw.
      "/timings show" looks without stopping. }
    if Rest = 'show' then
      ShowTimingLog
    else
    begin
      FTimings := not FTimings;
      if FTimings then
      begin
        FTimingLog := nil;
        FCmdMsg := 'Step timings on.  Do the slow thing, then /timings again to see them.';
      end
      else
      begin
        FCmdMsg := 'Step timings off.';
        ShowTimingLog;
      end;
    end;
  end
  else if (W = 'all') or (W = 'selectall') then
  begin
    SelectNone;
    BeginBulkSelect;
    for I := 0 to FD.Doc.Live - 1 do
      if FD.Doc[I].Kind in [ekLine, ekArc, ekFace, ekDim, ekText] then SelectAdd(I);
    EndBulkSelect;
    FCmdMsg := Format('%d things selected.', [Length(FSel)]);
    pbScreen.Invalidate;
  end
  else if (W = 'update') or (W = 'upgrade') then
  begin
    if Rest = 'never' then
    begin
      with TIniFile.Create(ConfigFile) do
      try
        WriteBool('update', 'check', False);
      finally
        Free;
      end;
      FCmdMsg := 'It will not look for updates again.  /update still works ' +
        'when you ask it to.';
    end
    else if Rest = 'always' then
    begin
      with TIniFile.Create(ConfigFile) do
      try
        WriteBool('update', 'check', True);
      finally
        Free;
      end;
      FCmdMsg := 'It will look once a day again.';
    end
    else
      DoUpdate;
  end
  else if W = 'version' then FCmdMsg := 'Heckers Sketch ' + CurrentVersion
  else if (W = 'push') or (W = 'pull') or (W = 'pushpull') or (W = 'p') then
    SetTool(ptPush)
  else if (W = 'undo') or (W = 'u') then DoUndo
  else if W = 'redo' then DoRedo
  { the shop tool by name; the SHOP list is the discoverable way in }
  else if (W = 'unfold') or (W = 'layout') then StartUnfold
  else if (W = 'fit') or (W = 'zoom') then FitView
  else if W = 'view' then CycleViewPreset(1)
  else if (W = 'top') or (W = 'down') then ApplyViewPreset(10)
  else if W = 'front' then ApplyViewPreset(6)
  else if W = 'right' then ApplyViewPreset(7)
  else if W = 'back' then ApplyViewPreset(8)
  else if W = 'left' then ApplyViewPreset(9)
  else if W = 'corner' then ApplyViewPreset(2)
  else if W = 'iso' then SetView(vkIso)
  { /orbit is the orbit tool, above; this is only reached by /3d }
  else if W = '3d' then SetView(vkOrbit)
  else if (W = 'plan') or (W = '2d') or (W = 'flat') then SetView(vkPlan)
  { the slice: "/cut off", "/cut all", or "/cut 0 9'" for bottom and top }
  else if (W = 'cut') or (W = 'slice') then
  begin
    if (Rest = 'off') or (Rest = 'none') then
      SetSlice(False, FD.SliceLo, FD.SliceHi)
    else if (Rest = 'all') or (Rest = 'whole') then
    begin
      if FD.Doc.ZRange(RL, RL2) then SetSlice(True, RL, RL2)
      else FCmdMsg := 'Nothing on this sheet to measure.';
    end
    else if Rest = '' then
      FCmdMsg := SliceText + '.  "/cut 0 9''" sets it, "/cut all" opens it ' +
                 'right up, "/cut off" turns it off.'
    else
    begin
      P := Pos(' ', Rest);
      if P <= 0 then
        FCmdMsg := 'Two heights, a bottom and a top - "/cut 0 9''".'
      else if not ParseLen(Trim(Copy(Rest, 1, P - 1)), FD.Units, RL) then
        FCmdMsg := 'I could not read "' + Trim(Copy(Rest, 1, P - 1)) + '" as a height.'
      else if not ParseLen(Trim(Copy(Rest, P + 1, MaxInt)), FD.Units, RL2) then
        FCmdMsg := 'I could not read "' + Trim(Copy(Rest, P + 1, MaxInt)) + '" as a height.'
      else
      begin
        if FD.View <> vkPlan then SetView(vkPlan);
        SetSlice(True, RL, RL2);
      end;
    end;
  end
  else if W = 'plane' then
  begin
    if Rest = 'xz' then FD.Plane := plXZ
    else if Rest = 'yz' then FD.Plane := plYZ
    else if Rest = 'xy' then FD.Plane := plXY
    else FD.Plane := TPlane((Ord(FD.Plane) + 1) mod 3);
    FCmdMsg := 'Working plane: ' + Copy('XYXZYZ', Ord(FD.Plane) * 2 + 1, 2);
  end
  else if (W = 'origin') or (W = 'o') then SetOriginHere
  else if W = 'grid' then
  begin
    FShowGrid := not FShowGrid;
    RepaintPaper;
    RecomposeAll;
    pbDeck.Invalidate;
  end
  else if W = 'regions' then ReportRegions
  else if W = 'forget' then
  begin
    { for testing: forget every area ever seen, then rebuild the faces }
    PushUndo;
    SetLength(FD.Seen, 0);
    I := RebuildFlatFaces;
    RenderInk;
    RecomposeAll;
    FCmdMsg := Format('Forgot what was seen and worked the faces out again: %d.', [I]);
  end
  else if (W = 'center') or (W = 'middle') then
    CenterSelection
  { the near bottom corner on the origin.  Not /corner, which is a view. }
  else if (W = 'tozero') or (W = 'zero') or (W = 'tuck') then
    CornerSelection
  { /keep: the tape's last run as a dimension.  A command so it cannot
    happen by accident. }
  else if (W = 'keep') or (W = 'keepdim') then
  begin
    if not FRunOK then
      FCmdMsg := 'Nothing measured yet.  Take the tape across something ' +
        'first, then /keep writes that run on the drawing.'
    else if Dist(FRunA, FRunB) < 1E-9 then
      FCmdMsg := 'That run was no length at all.'
    else
    begin
      PushUndo;
      FD.Doc.AddDim(FRunA, FRunB, FInkColor, DimOffset3);
      RenderInk;
      RecomposeAll;
      FCmdMsg := 'Kept as a dimension: ' + FormatLen(Dist(FRunA, FRunB), FD.Units) + '.';
    end;
  end
  { the groups and entity panels; commands, since the bottom row is full }
  else if (W = 'groups') or (W = 'outliner') then
  begin
    if Rest = 'on' then SetGroupsPanel(True)
    else if Rest = 'off' then SetGroupsPanel(False)
    else SetGroupsPanel(not FGroupsOn);
  end
  else if (W = 'info') or (W = 'entity') or (W = 'properties') then
  begin
    if Rest = 'on' then FInfoOn := True
    else if Rest = 'off' then FInfoOn := False
    else FInfoOn := not FInfoOn;
    FInfoSig := -1;
    Relayout;
    if FInfoOn then
    begin
      RebuildInfo;
      pbInfo.Invalidate;
      FCmdMsg := 'The entity panel is on the right.  Pick something to see ' +
        'what it is; a few of the figures can be changed from there.';
    end
    else
      FCmdMsg := 'Entity panel off.  /info brings it back.';
    Invalidate;
  end
  else if (W = 'detach') or (W = 'loose') then
  begin
    if Rest = 'on' then FDetachMove := True
    else if Rest = 'off' then FDetachMove := False
    else FDetachMove := not FDetachMove;
    if FDetachMove then
      FCmdMsg := 'A move takes what is picked away on its own now.  ' +
        'Nothing it is joined to will stretch to follow.  /detach off puts ' +
        'that back.'
    else
      FCmdMsg := 'A move stretches what it is joined to again, which is how ' +
        'SketchUp does it.';
  end
  else if (W = 'postcard') or (W = 'hello') then
  begin
    hsDialogSkin.UseTheme(Themes[FThemeIdx]);
    OfferPostcard(Self, CurrentVersion, True);
  end
  else if (W = 'light') or (W = 'lamp') then
  begin
    if (Rest = 'on') or (Rest = 'off') then CameraLamp := Rest = 'on'
    else if Rest = '' then CameraLamp := not CameraLamp
    else FCmdMsg := 'The light takes on or off.';
    if FCmdMsg = '' then
    begin
      if CameraLamp then
        FCmdMsg := 'The light follows the camera: the face turned towards ' +
                   'you is the bright one.  /light off for the old fixed lamp.'
      else
        FCmdMsg := 'The light is fixed, as it used to be: the same grays ' +
                   'from every angle.  /light on has it follow the camera.';
    end;
    RenderInk;
    RecomposeAll;
    FScreenDirty := True;
    pbScreen.Invalidate;
  end
  else if (W = 'source') or (W = 'src') or (W = 'text-view') then
  begin
    ShowSource;
    { "/source sample" loads the sample, "/source apply" presses Apply }
    if Rest = 'sample' then SourceForm.LoadSample
    else if Rest = 'apply' then SourceForm.ApplyNow
    { "/source complete off": the word list only on Ctrl+Space; remembered }
    else if (Rest = 'complete off') or (Rest = 'complete on') then
    begin
      FSourceComplete := Rest = 'complete on';
      SourceForm.SetAutoComplete(FSourceComplete);
      if FSourceComplete then
        FCmdMsg := 'The source window offers words as you type.  /source complete off stops it.'
      else
        FCmdMsg := 'The source window offers words only on Ctrl+Space.  /source complete on brings them back.';
    end
    else if Rest <> '' then FCmdMsg := '/source takes sample, apply, complete on or complete off.';
  end
  else if (W = 'jig') or (W = 'jigs') then
  begin
    if SoleGroup > 0 then
    begin
      if RunJigOf(SoleGroup) then
      begin
        RebuildFlatFaces;
        FCmdMsg := 'The jig was run again.';
      end;
      RenderInk;
      RecomposeAll;
    end
    else
      RunAllJigs;
    pbScreen.Invalidate;
  end
  else if (W = 'cube') or (W = 'viewcube') then
  begin
    FCubeHasHot := False;
    if (Rest = 'on') or (Rest = 'off') then
      FCubeOn := Rest = 'on'
    else if (Rest = 'tl') or (Rest = 'tr') or (Rest = 'bl') or (Rest = 'br') then
    begin
      if Rest = 'tl' then FCubeCorner := 0
      else if Rest = 'tr' then FCubeCorner := 1
      else if Rest = 'bl' then FCubeCorner := 2
      else FCubeCorner := 3;
      FCubeOn := True;
      FCmdMsg := 'The cube is ' + CORNER_NAME[FCubeCorner] + '.';
    end
    else if Copy(Rest, 1, 12) = 'fitselection' then
    begin
      N := Pos(' ', Rest);
      if N > 0 then Rest := Trim(Copy(Rest, N + 1, MaxInt)) else Rest := '';
      if Rest = 'off' then FCubeFitSel := False
      else if Rest = 'on' then FCubeFitSel := True
      else FCubeFitSel := not FCubeFitSel;
      if FCubeFitSel then
        FCmdMsg := 'A cube click brings what is picked into the middle and ' +
                   'sizes it.  With nothing picked it just goes to the view.'
      else
        FCmdMsg := 'A cube click goes to the view and leaves the framing alone.';
    end
    else if Rest <> '' then
      FCmdMsg := 'The cube takes on, off, tl, tr, bl, br, or ' +
                 'fitselection on/off.'
    else
      FCubeOn := not FCubeOn;

    if FCmdMsg = '' then
    begin
      if FCubeOn and (FD <> nil) and (FD.View <> vkOrbit) then
        FCmdMsg := 'The cube is on - it shows in a 3D view, and this is not ' +
                   'one.  /3d, or the VIEW button.'
      else if FCubeOn then
        FCmdMsg := 'The cube is on, ' + CORNER_NAME[FCubeCorner] +
                   '.  Click a face, an edge or a corner to look from there; ' +
                   'drag it to turn.'
      else
        FCmdMsg := 'The cube is off.';
    end;
    FScreenDirty := True;
    Relayout;
    pbScreen.Invalidate;
  end
  else if (W = 'holes') or (W = 'openedges') or (W = 'notclosed') then
  begin
    ShowOpenEdges;
  end
  else if W = 'rebuild' then
  begin
    PushUndo;
    I := RebuildFlatFaces;
    RenderInk;
    RecomposeAll;
    if FTurned > 0 then
      FCmdMsg := Format('Worked the faces out again: %d, and turned %d of ' +
        'them the right way out.', [I, FTurned])
    else
      FCmdMsg := Format('Worked the faces out again: %d.', [I]);
  end
  else if (W = 'rebuildfaces') or (W = 'reface') then
  begin
    { Throw the flat faces away and rebuild them from the lines, for files
      whose faces no longer match their lines.  Solid faces are kept: they
      were pulled out of a face and have no lines under them to rebuild
      from, so deleting them would lose them for good. }
    PushUndo;
    SetLength(ReDoomed, FD.Doc.Live);
    J := 0;
    K := 0;
    for I := 0 to FD.Doc.Live - 1 do
    begin
      ReDoomed[I] := (FD.Doc[I].Kind = ekFace) and not FD.Doc[I].Solid;
      if ReDoomed[I] then Inc(J)
      else if FD.Doc[I].Kind = ekFace then Inc(K);
    end;
    FD.Doc.DeleteMarked(ReDoomed);
    SetLength(FD.Seen, 0);
    I := RebuildFlatFaces;
    RenderInk;
    RecomposeAll;
    if K > 0 then
      FCmdMsg := Format('Threw %d flat faces away and worked out %d from the ' +
        'lines.  Left %d alone that belong to a solid - there are no lines ' +
        'under those to work them out from.', [J, I, K])
    else
      FCmdMsg := Format('Threw the faces away and worked them out from the ' +
        'lines: %d.', [I]);
  end
  else if (W = 'guides') or (W = 'noguides') then
  begin
    { SketchUp's Edit > Delete Guides }
    I := FD.Doc.GuideCount;
    if I = 0 then
      FCmdMsg := 'No guides to clear.'
    else
    begin
      PushUndo;
      FD.Doc.ClearGuides;
      RenderInk;
      RecomposeAll;
      FCmdMsg := Format('Cleared %d guide%s.', [I, IfThen(I = 1, '', 's')]);
    end;
  end
  else if W = 'units' then SetUnits(TUnitSystem(1 - Ord(FD.Units)))
  else if (W = 'new') or (W = 'tab') then NewDrawing(-1)
  else if W = 'sheet' then AddSheetHere
  else if W = 'saveall' then DoSaveAll
  else if W = 'example' then
  begin
    NewDrawing(-1);
    LoadExample;
  end
  else if W = 'close' then CloseDrawing(FTabIdx)
  else if W = 'clear' then StartErase
  else if W = 'save' then DoSave
  else if (W = 'saveas') or (W = 'save-as') then DoSaveAs
  else if W = 'print' then
  begin
    if (Rest = 'full') or (Rest = '1:1') or (Rest = 'fullsize') or
       (Rest = 'full size') then DoPrintFull('')
    else if (Rest = 'all') or (Rest = 'sheets') then DoPrintSheets(True)
    else DoPrint;
  end
  { the same tiles as pictures, for a print shop or a preview }
  else if (W = 'tiles') and (Rest <> '') then DoPrintFull(RawTail(S))
  else if W = 'scale' then
  begin
    for I := 0 to SCALE_COUNT - 1 do
      if LowerCase(ScaleTable(FD.Units, I).Name) = Rest then
      begin
        SetScaleIdx(I);
        Exit;
      end;
    FCmdMsg := 'Scales: 1/16" 1/8" 1/4" 1/2" 1"';
  end
  { A path keeps its case: the command is lowercased, so take the tail from
    the line as typed. }
  else if W = 'replay' then
    DoReplayFile(RawTail(S))
  else if (W = 'session') or (W = 'acts') then
  begin
    { What has been recorded so far, the same lines a report carries, ready
      for /replay.  The path keeps its case, as for /replay. }
    Rest := RawTail(S);
    if Rest = '' then Rest := 'session.txt';
    try
      with TStringList.Create do
      try
        Text := ActsText;
        SaveToFile(Rest);
        FCmdMsg := Format('%d actions written to %s', [Count, Rest]);
      finally
        Free;
      end;
    except
      on E: Exception do FCmdMsg := 'Could not write it: ' + E.Message;
    end;
  end
  else if (W = 'manual') or (W = 'docs') then OpenManual
  else if (W = 'help') or (W = '?') then ShowAbout
  else
    Result := False;
end;

procedure TMainForm.CommandEnter;
var
  L: Double;
  Why: string;
  SidesN, ArrN: Integer;
  ArrDiv: Boolean;
begin
  { Record the typing and the Enter, which turn a direction into a measured
    run.  A /command is not recorded: its setter records what it changes,
    and /session and /replay must not run again inside a replay. }
  if Copy(FInput, 1, 1) <> '/' then
  begin
    if FInput <> '' then Act('input ' + FInput);
    Act('enter');
  end;
  if FDimEdit >= 0 then
  begin
    CommitDimNote;
    pbCmd.Invalidate;
    Exit;
  end;
  { a cut field is open, so what was typed is a height for it }
  if FSliceEdit <> 0 then
  begin
    CommitSliceEdit;
    pbCmd.Invalidate;
    Exit;
  end;

  if (FTool = ptText) and (FStage = 1) then
  begin
    ToolCommit;
    Exit;
  end;

  { picking the stairs: a length typed is the run, then the width }
  if (FStairPick > 0) and (Copy(FInput, 1, 1) <> '/') then
  begin
    StairTyped;
    Exit;
  end;

  if FInput = '' then
  begin
    if FStage > 0 then ToolCommit else ToolClick;
    Exit;
  end;

  if FArray.Live and ArrayCommand(FInput, ArrN, ArrDiv) then
  begin
    FInput := '';
    ApplyArray(ArrN, ArrDiv);
    Exit;
  end;

  if Copy(FInput, 1, 1) = '/' then
  begin
    if not RunCommand(Copy(FInput, 2, MaxInt)) then
      FCmdMsg := 'I do not know "' + Copy(FInput, 2, MaxInt) + '"';
    FInput := '';
    pbCmd.Invalidate;
    Exit;
  end;

  { 24s or s24 on the circle or arc tool: how many sides, not how big }
  if (FTool in [ptCircle, ptArc]) and ParseSides(FInput, SidesN) then
  begin
    if FTool = ptCircle then FSidesCircle := SidesN else FSidesArc := SidesN;
    FCmdMsg := Format('%d sides from now on.', [SidesN]);
    FInput := '';
    pbCmd.Invalidate;
    pbScreen.Invalidate;
    Exit;
  end;

  { Not every entry is a plain length (8',20' for a rectangle, [x,y,z] and
    <x,y,z> for move and line).  Anything that starts like a measurement goes
    to the tool; bare words fall through to the command list. }
  if (FStage > 0) and (FInput <> '') and
     (FInput[1] in ['0'..'9', '-', '.', '[', '<', ',', 'x', 'X']) then
  begin
    { An unreadable number must not silently commit at the cursor.  This is
      also where the dashed notation (6-8-15) can explain itself. }
    Why := WhyNotAMeasurement(FInput);
    if Why <> '' then
    begin
      FCmdMsg := Why;
      pbCmd.Invalidate;
      pbScreen.Invalidate;
      Exit;
    end;
    ToolCommit;
    FInput := '';
    pbCmd.Invalidate;
    Exit;
  end;

  if ParseLen(FInput, FD.Units, L) then
  begin
    if FStage > 0 then
      ToolCommit
    { a dimension picked and a length typed: what it should read.  Typing a
      length and Enter is how every size is given here. }
    else if (SelectedDim >= 0) and ApplyDimResize(L, True) then
      { already reported }
    else if SelectedDim >= 0 then
      { refused, and said why }
    else if (SelectedLine >= 0) and ApplyLineLength(L) then
      { a picked line: its length, SketchUp's Entity Info way }
    else
      FCmdMsg := FInput + ' = ' + FormatLen(L, FD.Units) + ' (pick a start point first)';
    FInput := '';
    pbCmd.Invalidate;
    Exit;
  end;

  if RunCommand(FInput) then
    FInput := ''
  else
    FCmdMsg := 'I do not know "' + FInput + '"';
  pbCmd.Invalidate;
end;

{ ======================================================================== }
{ mouse on the screen                                                       }
{ ======================================================================== }

procedure TMainForm.pbScreenMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  I, Which: Integer;
begin
  if FBusy then Exit;
  { a press supersedes motion not yet serviced }
  FMoveX := X;
  FMoveY := Y;
  FMovePending := False;
  FMoveShift := Shift;

  { The cube is drawn over the drawing, so it takes presses first, every
    button: a right or middle press aimed at the cube must not reach the
    model. }
  if CubeMouse(X, Y, Button = mbLeft, False) or CubeZone(X, Y) then
  begin
    pbScreen.Invalidate;
    Exit;
  end;

  { The stair pick and the source window's Pick take a left press as a point
    (the snapped cursor) and nothing else happens on the sheet.  Then an
    open list takes the press before any tool (orbit claims a plain left
    press): any button dismisses it, only a left press on a row picks. }
  if (FStairPick > 0) and (Button = mbLeft) and (FD <> nil) then
  begin
    StairTakePoint(FCur);
    Exit;
  end;
  if FTextPick and (Button = mbLeft) and (SourceForm <> nil) and (FD <> nil) then
  begin
    SourceForm.TakePoint(FCur, FD.Units);
    FCmdMsg := 'Typed in: ' + Place2(FCur, FD.Units, False) + '.  Next point, or Esc.';
    pbCmd.Invalidate;
    Exit;
  end;
  if FPopup <> POP_NONE then
  begin
    Which := FPopup;
    I := -1;
    if Button = mbLeft then I := PopupItemAt(X, Y);
    { close before acting: some rows show a modal panel, and the list would
      stay painted over it }
    ClosePopup;
    if I >= 0 then PopupChoose(Which, I);
    Exit;
  end;

  { laptops without a middle button: the orbit tool makes a left drag orbit }
  if (Button = mbLeft) and (FTool = ptOrbit) then
  begin
    FOrbiting := FD.View = vkOrbit;
    FPanning := not FOrbiting;
    FPanRefX := X;
    FPanRefY := Y;
    FOrbitGain := OrbitGainAt(X, Y);
    FOrbitPivot := PivotAt(X, Y);
    AnchorOrbit(X, Y);
    FMoveShift := Shift;
    pbScreen.Cursor := crSizeAll;
    Exit;
  end;

  if Button in [mbMiddle, mbRight] then
  begin
    { Middle-drag orbits whatever the tool, mid-operation too, as in
      SketchUp.  From PLAN or ISO it enters the free camera first, aimed
      where you were looking. }
    if Button = mbMiddle then
    begin
      EnterFreeCamera;
      FCmdMsg := '3D view - drag to spin.  V goes back.';
    end;
    FOrbiting := (Button = mbMiddle) and (FD.View = vkOrbit);
    FPanning := not FOrbiting;
    FPanRefX := X;
    FPanRefY := Y;
    FRightSX := X;
    FRightSY := Y;
    FOrbitGain := OrbitGainAt(X, Y);
    FOrbitPivot := PivotAt(X, Y);
    AnchorOrbit(X, Y);
    FMoveShift := Shift;
    pbScreen.Cursor := crSizeAll;
    Exit;
  end;
  if Button <> mbLeft then Exit;

  { (an open list was handled above) }
  FMouseSX := X;
  FMouseSY := Y;
  { waiting for the piece to lay out: that click and no other }
  if FUnfoldPick then
  begin
    UnfoldAt(X, Y);
    Exit;
  end;
  { the eraser gathers while held and deletes on release }
  if FTool = ptErase then
  begin
    FErasing2 := True;
    FEraseMode := EraseModeOf(Shift);
    SetLength(FDoomed, 0);
    DoomAt(X, Y);
    FScreenDirty := True;
    Exit;
  end;
  { Ctrl at the press decides a copy for move and rotate }
  if ((FTool = ptMove) and (FStage = 1)) or ((FTool = ptRotate) and (FStage = 2)) then
    FMoveCopy := ssCtrl in Shift;

  if (GetTickCount64 - FClickT < 450) and (Abs(X - FClickX) < 5) and
     (Abs(Y - FClickY) < 5) then
    Inc(FClickN)
  else
    FClickN := 1;
  FClickT := GetTickCount64;
  FClickX := X;
  FClickY := Y;

  if FTool = ptSelect then
  begin
    { a press on a note's box drags the note (its leader target stays put),
      rather than starting a box select }
    FNoteDrag := FD.Doc.HitNote(X, Y);
    if FNoteDrag >= 0 then
    begin
      { the undo step waits for the first real move, so a click leaves
        nothing to undo }
      FNoteMoved := False;
      FNoteFrom := FD.Doc[FNoteDrag].A;
      FNoteGrab := WorldAt(X, Y);
      FCmdMsg := 'Moving the note.  Let go to drop it.';
      pbCmd.Invalidate;
      Exit;
    end;
    FBoxing := True;
    FBoxX := X;
    FBoxY := Y;
    FScreenDirty := True;
    Exit;
  end;
  FCur := ResolveSnapAt(X, Y);
  Trail(Format('press %s stage=%d at %d,%d  world %s,%s,%s  snap=%d',
    [TOOL_NAMES[FTool], FStage, X, Y,
     FormatLen(FCur.X, FD.Units), FormatLen(FCur.Y, FD.Units),
     FormatLen(FCur.Z, FD.Units), Ord(FSnapKind)]));
  Act(Format('press %.6f %.6f %.6f', [FCur.X, FCur.Y, FCur.Z], ActFS));
  { For a line run, and for push/pull, drill and offset, the press does
    not decide: it may be a click, or a hold that strains and cancels.
    Known when the button comes up or the hold breaks. }
  if (FTool in [ptLine, ptRect, ptCircle, ptArc, ptPush, ptDrill,
                ptOffset]) and (FStage >= 1) then
  begin
    FHoldOn := True;
    FHoldT := 0;
    FHoldX := X;
    FHoldY := Y;
    Exit;
  end;
  ToolClick;
end;

{ Note something in the trail ring, for crash reports. }
procedure TMainForm.Trail(const S: string);
begin
  FTrail[FTrailN mod Length(FTrail)] :=
    FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + S;
  Inc(FTrailN);
end;

{ Raw numbers, not feet and inches: this is parsed back, and rounding would
  replay somewhere slightly different. }
procedure TMainForm.Act(const S: string);
begin
  FActs[FActsN mod Length(FActs)] := S;
  Inc(FActsN);
end;

function TMainForm.ActsText: string;
var
  I, First, N: Integer;
begin
  Result := '';
  N := FActsN;
  if N > Length(FActs) then N := Length(FActs);
  First := FActsN - N;
  for I := First to FActsN - 1 do
    Result := Result + '  ' + FActs[I mod Length(FActs)] + LineEnding;
end;

{ Replay a session from a bug report.  The whole report is taken, not a
  trimmed fragment; the section is found by its heading and read to the end
  of the indented block. }
procedure TMainForm.DoReplayFile(const FileName: string);
const
  MARK = 'to replay';
var
  L, Body: TStringList;
  I: Integer;
  Fn: string;
  Inside: Boolean;
begin
  Fn := Trim(FileName);
  if Fn = '' then Fn := 'replay.txt';
  if not FileExists(Fn) then Fn := ExtractFilePath(ParamStr(0)) + Fn;
  if not FileExists(Fn) then
  begin
    FCmdMsg := 'No such file: ' + Trim(FileName) +
      '  - /replay <a report .txt, or a file of session lines>';
    pbCmd.Invalidate;
    Exit;
  end;

  L := TStringList.Create;
  Body := TStringList.Create;
  try
    try
      L.LoadFromFile(Fn);
    except
      on E: Exception do
      begin
        FCmdMsg := 'Could not read it: ' + E.Message;
        pbCmd.Invalidate;
        Exit;
      end;
    end;

    Inside := False;
    for I := 0 to L.Count - 1 do
    begin
      if not Inside then
      begin
        if Pos(MARK, LowerCase(L[I])) > 0 then Inside := True;
        Continue;
      end;
      { the block runs while lines stay indented; the next heading ends it }
      if (Trim(L[I]) <> '') and (Copy(L[I], 1, 1) <> ' ') then Break;
      if Trim(L[I]) <> '' then Body.Add(Trim(L[I]));
    end;

    { a bare file of session lines works too }
    if Body.Count = 0 then
      for I := 0 to L.Count - 1 do
        if Trim(L[I]) <> '' then Body.Add(Trim(L[I]));

    if Body.Count = 0 then
      FCmdMsg := 'Nothing in there that looks like a session.'
    else
      FCmdMsg := Format('replayed %d of %d', [ReplayActs(Body.Text), Body.Count]);
  finally
    Body.Free;
    L.Free;
  end;
  pbCmd.Invalidate;
end;

{ Play a recorded session back by handing the same world points to the
  entry points the mouse feeds, so nothing depends on window size.  Stops
  at the first line it does not understand; a replay that silently diverges
  is worse than one that stops. }
function TMainForm.ReplayActs(const Script: string): Integer;
var
  L: TStringList;
  P: TStringList;
  I: Integer;
  Cmd, Rest: string;
  T: TTool;
  Fired: Boolean;
  SP: TPointF;

  function Num(K: Integer): Double;
  begin
    if not TryStrToFloat(P[K], Result, ActFS) then Result := 0;
  end;

begin
  Result := 0;
  L := TStringList.Create;
  P := TStringList.Create;
  try
    L.Text := Script;
    P.Delimiter := ' ';
    P.StrictDelimiter := True;

    for I := 0 to L.Count - 1 do
    begin
      P.DelimitedText := Trim(L[I]);
      if P.Count = 0 then Continue;
      Cmd := LowerCase(P[0]);
      Rest := Trim(Copy(Trim(L[I]), Length(P[0]) + 1, MaxInt));
      Fired := True;

      if (Cmd = 'press') and (P.Count >= 4) then
      begin
        FCur := P3(Num(1), Num(2), Num(3));
        { and where that lands on screen, for the tools that ask what is under
          the pointer (revolve, push/pull, the eraser) }
        SP := ScreenOf(FCur);
        FMouseSX := Round(SP.X);
        FMouseSY := Round(SP.Y);
        FSnapKind := snGrid;
        { and which face: the one holding the point, found in the model, not
          under the pixel, where another window size finds a different face }
        FReplayFace := FD.Doc.FaceHolding(FCur);
        try
          ToolClick;
        finally
          FReplayFace := -1;
        end;
      end
      else if Cmd = 'tool' then
      begin
        Fired := False;
        for T := Low(TTool) to High(TTool) do
          if SameText(TOOL_NAMES[T], Rest) then
          begin
            SetTool(T);
            Fired := True;
            Break;
          end;
      end
      else if Cmd = 'input' then
        FInput := Rest
      else if (Cmd = 'dir') and (P.Count >= 2) then
        FDirLock := StrToIntDef(P[1], -1)
      else if Cmd = 'enter' then
        CommandEnter
      else if Cmd = 'undo' then
        DoUndo
      else if Cmd = 'redo' then
        DoRedo
      else if Cmd = 'clear' then
        StartErase
      else if Cmd = 'view' then
      begin
        if SameText(Rest, 'PLAN') then SetView(vkPlan)
        else if SameText(Rest, 'ISO') then SetView(vkIso)
        else if SameText(Rest, '3D') then SetView(vkOrbit)
        else Fired := False;
      end
      else if (Cmd = 'scale') and (P.Count >= 2) then
        SetScaleIdx(StrToIntDef(P[1], FD.ScaleIdx))
      else if (Cmd = 'snap') and (P.Count >= 2) then
        FD.SnapIdx := EnsureRange(StrToIntDef(P[1], FD.SnapIdx), 0, SNAP_COUNT - 1)
      else if (Cmd = 'units') and (P.Count >= 2) then
        SetUnits(TUnitSystem(EnsureRange(StrToIntDef(P[1], 0), 0, 1)))
      else
        Fired := False;

      if not Fired then
      begin
        FCmdMsg := Format('replay stopped at line %d: %s', [I + 1, Trim(L[I])]);
        Break;
      end;
      Inc(Result);
    end;
  finally
    P.Free;
    L.Free;
  end;

  { the replay logged its own actions; drop them so the next report does not
    carry the session twice }
  FActsN := 0;
  RenderInk;
  RecomposeAll;
  RefreshChrome;
end;

function TMainForm.TrailText: string;
var
  I, First, N: Integer;
begin
  Result := '';
  N := FTrailN;
  if N > Length(FTrail) then N := Length(FTrail);
  First := FTrailN - N;
  for I := First to FTrailN - 1 do
    Result := Result + '  ' + FTrail[I mod Length(FTrail)] + LineEnding;
end;

function TMainForm.KindCounts: string;
const
  NAMES: array[TEntKind] of string =
    ('lines', 'arcs', 'notes', 'dims', 'faces', 'guides', 'bore', 'groups');
var
  N: array[TEntKind] of Integer;
  K: TEntKind;
  I: Integer;
begin
  for K := Low(TEntKind) to High(TEntKind) do N[K] := 0;
  for I := 0 to FD.Doc.Live - 1 do
    Inc(N[FD.Doc[I].Kind]);
  Result := '';
  for K := Low(TEntKind) to High(TEntKind) do
    if N[K] > 0 then
    begin
      if Result <> '' then Result := Result + ', ';
      Result := Result + IntToStr(N[K]) + ' ' + NAMES[K];
    end;
  if Result = '' then Result := 'empty';
end;

procedure TMainForm.SaveCrashDoc(const ReportPath: string);
var
  L: TStringList;
begin
  try
    L := TStringList.Create;
    try
      BuildSession(L, False, -1, False, True);
      L.SaveToFile(ReportPath + '.hsk');
    finally
      L.Free;
    end;
  except
    { the drawing could not be written out; the report still stands }
  end;
end;

{ Every report sent is also kept beside the program, text and picture under
  the same name, so what was sent can be read back. }
procedure TMainForm.KeepReportCopy(const AName, Body: string; Shot: TStream);
var
  Dir: string;
  L: TStringList;
  F: TFileStream;
begin
  try
    Dir := AppDataDir + 'reports-sent' + PathDelim;
    if not ForceDirectories(Dir) then Exit;
    L := TStringList.Create;
    try
      L.Text := Body;
      L.SaveToFile(Dir + AName);
    finally
      L.Free;
    end;
    if (Shot <> nil) and (Shot.Size > 0) then
    begin
      F := TFileStream.Create(Dir + ChangeFileExt(AName, '.png'), fmCreate);
      try
        Shot.Position := 0;
        F.CopyFrom(Shot, Shot.Size);
      finally
        F.Free;
      end;
    end;
  except
    { a copy that could not be written is no reason to stop the report }
  end;
end;

function TMainForm.MachineText: string;
begin
  try
    Result := SystemFacts +
      'program memory: ' + ProgramMemory + LineEnding +
      Format('program: up %d s, threads=%s, quick frames=%s',
        [(GetTickCount64 - FStartedAt) div 1000, BoolToStr(FThreads, True),
         BoolToStr(FQuickFrames, True)]) + LineEnding;
  except
    on E: Exception do Result := 'machine facts failed: ' + E.ClassName + LineEnding;
  end;
end;

function TMainForm.DiagnosticText: string;
begin
  { names, not numbers, so a report reads without the source open; nothing
    about the person or the machine }
  Result :=
    Format('tool=%s stage=%d view=%s plane=%s', [TOOL_NAMES[FTool],
      FStage, VIEW_NAMES[FD.View], PlaneName]) + LineEnding +
    Format('mouse=%d,%d  cursor=%s,%s,%s  snap=%d axislock=%d held=%d',
      [FMouseSX, FMouseSY, FormatLen(FCur.X, FD.Units),
       FormatLen(FCur.Y, FD.Units), FormatLen(FCur.Z, FD.Units),
       Ord(FSnapKind), FAxisLock, Ord(FPlaneHeld)]) + LineEnding +
    Format('entities=%d (%s)  sheets=%d tab=%d  selected=%d doomed=%d',
      [FD.Doc.Live, KindCounts, Length(FDrawings), FTabIdx,
       Length(FSel), Length(FDoomed)]) + LineEnding +
    Format('pushface=%d offface=%d hoverent=%d hoverface=%d lock=%d ' +
      'holding=%d scale=%s snapstep=%s zoom=%s',
      [FPushFace, FOffFace, FHoverEnt, FHoverFace, Ord(FLockOn),
       Ord(FHoldOn), CurScale.Name, FormatLen(SnapStep, FD.Units),
       FormatFloat('0.00', FD.Zoom)]) + LineEnding +
    Format('units=%s screen=%dx%d scaling=%s portable=%s net=%s',
      [hsDrawing.UnitName(FD.Units), pbScreen.Width, pbScreen.Height,
       FormatFloat('0.00', FUIScale),
       specialize IfThen<string>(IsPortable, 'yes', 'no'),
       NetBackend]) + LineEnding +
    { where the camera stood: many view faults only reproduce at the angle }
    Format('camera az=%.2f el=%.2f zoom=%.3f at %.1f,%.1f',
      [RadToDeg(FD.Az), RadToDeg(FD.El), FD.Zoom, FD.ViewX, FD.ViewY]) +
      LineEnding +
    { the surfaces and whether they agree with each other and the window,
      for compositor crashes }
    Format('art=%dx%d/%d paper=%dx%d/%d ink=%dx%d/%d ' +
      'repairs=%d%s',
      [FArt.Width, FArt.Height, FArt.Stride,
       FPaper.Width, FPaper.Height, FPaper.Stride,
       FInk.Width, FInk.Height, FInk.Stride,
       TArtSurface.Repairs,
       { this document's borrowed depth buffer was freed at some point (an
         export's surface); harmless now, but worth a second look }
       specialize IfThen<string>(FD.Doc.LastSurfDied,
         ' borrowed-depth-was-freed', '')]) + LineEnding +
    { slow frames since start: count, worst, and the last one's breakdown;
      the individual lines are in the log below }
    IfThen(FSlowN = 0, 'frames: none over 40ms',
      Format('frames: %d over 40ms, worst %dms, last was %s',
        [FSlowN, FSlowWorst, FSlowLast])) + LineEnding +
    'what was happening, most recent last:' + LineEnding + TrailText +
    { the same session in world coordinates, to replay against the drawing
      below; recorded only from this window's own handlers }
    LineEnding + 'the same session, to replay - /replay after loading the ' +
    'drawing below:' + LineEnding + ActsText;
end;

{ Everything else about how the program was being used: startup, window and
  screen, view cube, tool settings, open sheets.  Nothing about the person:
  a file on the command line is written as <file>, never its path.  Each
  group is guarded so one bad value costs a line, not the report. }
function TMainForm.SettingsText: string;
const
  FILL_NAMES: array[0..2] of string = ('normal', 'maximized', 'full screen');
  TOUCH_NAMES: array[TTouchMode] of string =
    ('none', 'pending', 'as mouse', 'gesture', 'spent');
  CORNER_NAMES: array[0..3] of string =
    ('top left', 'top right', 'bottom left', 'bottom right');
  ERASE_NAMES: array[0..2] of string = ('delete', 'soften', 'unsoften');
  PLANE_NAMES: array[TPlane] of string = ('XY', 'XZ', 'YZ', 'free');
  TAPE_NAMES: array[0..3] of string =
    ('line and point', 'point', 'line', 'nothing');
  KIND_NAMES: array[TEntKind] of string =
    ('line', 'arc', 'note', 'dim', 'face', 'guide', 'bore', 'group');
var
  R: string;

  procedure Add(const Line: string);
  begin
    R := R + Line + LineEnding;
  end;

  function YN(B: Boolean): string;
  begin
    if B then Result := 'on' else Result := 'off';
  end;

  function Args: string;
  var
    I, Eq: Integer;
    A: string;
  begin
    Result := '';
    for I := 1 to ParamCount do
    begin
      A := ParamStr(I);
      if (A = '') or (A[1] <> '-') then
        A := '<file>'
      else
      begin
        { a switch's value is kept unless it looks like a path }
        Eq := Pos('=', A);
        if (Eq > 0) and ((Pos('/', A) > 0) or (Pos('\', A) > 0) or
           (Pos(':', Copy(A, Eq, MaxInt)) > 0)) then
          A := Copy(A, 1, Eq) + '<file>';
      end;
      Result := Result + ' ' + A;
    end;
    if Result = '' then Result := ' (none)';
  end;

  function SelKinds: string;
  var
    N: array[TEntKind] of Integer;
    K: TEntKind;
    I: Integer;
  begin
    for K := Low(TEntKind) to High(TEntKind) do N[K] := 0;
    for I := 0 to High(FSel) do
      if (FSel[I] >= 0) and (FSel[I] < FD.Doc.Live) then
        Inc(N[FD.Doc[FSel[I]].Kind]);
    Result := '';
    for K := Low(TEntKind) to High(TEntKind) do
      if N[K] > 0 then
        Result := Result + Format(' %s=%d', [KIND_NAMES[K], N[K]]);
    if Result = '' then Result := ' none';
  end;

  function Forms_: string;
  var
    I: Integer;
  begin
    Result := '';
    for I := 0 to Screen.CustomFormCount - 1 do
      if Screen.CustomForms[I].Visible then
        Result := Result + ' ' + Screen.CustomForms[I].ClassName;
    if Screen.ActiveCustomForm <> nil then
      Result := Result + '  (active ' + Screen.ActiveCustomForm.ClassName + ')';
    if Screen.ActiveControl <> nil then
      Result := Result + '  (focus ' + Screen.ActiveControl.ClassName + ')';
  end;

var
  I, J, Groups, G, Grps: Integer;
  Known: Boolean;
  D: TDrawing;
  M: TMonitor;
  Seen: array of Integer;
begin
  R := '';
  try
    Add('started with:' + Args);
    Add(Format('run tag=%s  updated from=%s  whats new shown=%s  ' +
      'draft restored=%s (age %d)  crash offered=%s  offline=%s',
      [FRunTag, specialize IfThen<string>(FUpdatedFrom = '', '-', FUpdatedFrom),
       YN(FWhatsNewShown), YN(FRestored), FDraftAge, YN(FCrashToOffer),
       YN(NetOffline)]));
    Add(Format('update seen=%s  help pages=%s%s  drawing file=%s  ' +
      'threads=%s  timings=%s',
      [specialize IfThen<string>(FUpdateTag = '', '-', FUpdateTag),
       specialize IfThen<string>(LocalHelpVersion = '', 'none', LocalHelpVersion),
       specialize IfThen<string>(HelpFetching <> nil, ' (fetching)', ''),
       specialize IfThen<string>(DocPath = '', 'never saved', 'saved as ' +
         ExtractFileExt(DocPath)),
       YN(FThreads), YN(FTimings)]));
  except
    on E: Exception do Add('start facts failed: ' + E.ClassName);
  end;

  try
    Add(Format('window: %s  %d,%d %dx%d  state=%d  client %dx%d  ' +
      'drawing area %dx%d  tools wide=%s  info panel=%s',
      [FILL_NAMES[Ord(FFill)], Left, Top, Width, Height, Ord(WindowState),
       ClientWidth, ClientHeight, pbScreen.Width, pbScreen.Height,
       YN(FToolsWide), YN(FInfoOn)]));
    M := Monitor;
    if M <> nil then
      Add(Format('on monitor %d of %d: %d,%d %dx%d at %d dpi (screen says %d)' +
        ', primary=%s',
        [M.MonitorNum + 1, Screen.MonitorCount, M.Left, M.Top, M.Width,
         M.Height, M.PixelsPerInch, Screen.PixelsPerInch, YN(M.Primary)]));
    Add('forms showing:' + Forms_);
  except
    on E: Exception do Add('window facts failed: ' + E.ClassName);
  end;

  try
    Add(Format('look: theme=%s grid=%s edge width=%d ink=%s%s ' +
      'rounded to 1/%d  circle sides=%d arc sides=%d',
      [Theme.Name, YN(FShowGrid), FEdgeW, IntToHex(ColorToRGB(FInkColor), 6),
       specialize IfThen<string>(FInkAuto, ' (auto)', ''),
       FLenDenom, FSidesCircle, FSidesArc]));
    Add(Format('view cube=%s corner=%s fit to selection=%s hot=%s ' +
      'dragging=%s  glide=%.2f  orbit snap target=%s  preset=%d',
      [YN(FCubeOn), CORNER_NAMES[FCubeCorner and 3], YN(FCubeFitSel),
       YN(FCubeHasHot), YN(FCubeDrag), FGlideT, YN(FSnapHasHot),
       FViewPreset]));
  except
    on E: Exception do Add('look facts failed: ' + E.ClassName);
  end;

  try
    Add(Format('tool options: tape leaves=%s erase=%s move copy=%s ' +
      'rigid=%s detach=%s dirlock=%d last push=%s last radius=%s ' +
      'fillet pending=%s',
      [TAPE_NAMES[Max(0, Min(3, FTapeDrop))], ERASE_NAMES[Max(0, Min(2, FEraseMode))], YN(FMoveCopy),
       YN(FMoveRigid), YN(FDetachMove), FDirLock,
       FormatLen(FLastPush, FD.Units), FormatLen(FLastFilletR, FD.Units),
       YN(FFilletPending)]));
    Add(Format('going on: typed="%s" popup=%d clicks=%d boxing=%s ' +
      'panning=%s orbiting=%s erasing=%s moving=%s busy=%s ' +
      'loading=%s dim edit=%d cut edit=%d camera moving=%s',
      [FInput, FPopup, FClickN, YN(FBoxing), YN(FPanning), YN(FOrbiting),
       YN(FErasing2), YN(FMovePending), YN(FBusy),
       YN(FLoading), FDimEdit, FSliceEdit, YN(FCameraMoving)]));
    Add(Format('bar said: "%s"', [FCmdMsg]));
    Add(Format('touch: seen=%s mode=%s down=%s points=%d',
      [YN(FTouchOn), TOUCH_NAMES[FTouchMode], YN(FTouchDown), FTouchCount]));
    Add('selected:' + SelKinds);
  except
    on E: Exception do Add('tool facts failed: ' + E.ClassName);
  end;

  try
    Add(Format('sheets open: %d', [Length(FDrawings)]));
    for I := 0 to High(FDrawings) do
    begin
      D := FDrawings[I];
      if D = nil then Continue;
      { solids, counted by their group numbers }
      Groups := 0;
      SetLength(Seen, 0);
      for G := 0 to D.Doc.Live - 1 do
      begin
        Grps := D.Doc[G].Grp;
        if Grps <= 0 then Continue;
        Known := False;
        for J := 0 to High(Seen) do
          if Seen[J] = Grps then Known := True;
        if not Known then
        begin
          SetLength(Seen, Length(Seen) + 1);
          Seen[High(Seen)] := Grps;
          Inc(Groups);
        end;
      end;
      { the name too: it is what the person sees on the tab }
      Add(Format('  sheet %d%s "%s": things=%d solids=%d open group=%d modified=%s view=%s ' +
        'plane=%s units=%s scale=%s snap=%s zoom=%.3f az=%.1f el=%.1f ' +
        'cut=%s (%s to %s) guides=%s undo=%d redo=%d',
        [I + 1, specialize IfThen<string>(I = FTabIdx, ' (showing)', ''),
         D.Name, D.Doc.Live, Groups, D.Doc.Context, YN(D.Dirty), VIEW_NAMES[D.View], PLANE_NAMES[D.Plane],
         hsDrawing.UnitName(D.Units), ScaleTable(D.Units, D.ScaleIdx).Name,
         SnapName(D.Units, D.SnapIdx), D.Zoom, RadToDeg(D.Az),
         RadToDeg(D.El), YN(D.SliceOn), FormatLen(D.SliceLo, D.Units),
         FormatLen(D.SliceHi, D.Units),
         specialize IfThen<string>(D.Doc.GuidesHidden, 'hidden', 'shown'),
         D.UndoTop, D.RedoTop]));
    end;
  except
    on E: Exception do Add('sheet facts failed: ' + E.ClassName);
  end;
  Result := R;
end;

{ Put everything down after an exception: the tool, the run in progress and
  all transient state, but not the drawing.  Leaving that state alone let
  the same code fault again on the next mouse move, forever. }
procedure TMainForm.Quiesce;
begin
  try
    FMovePending := False;
    FOrbiting := False;
    FPanning := False;
    FErasing2 := False;
    FHoldOn := False;
    FHoldT := 0;
    FPushFace := -1;
    FOffFace := -1;
    SetLength(FSel, 0);
    SetLength(FDoomed, 0);
    ResetTool;
    if pbScreen <> nil then pbScreen.Cursor := crCross;
  except
    { it is already having a bad day }
  end;
end;

procedure TMainForm.ReportCrash(Sender: TObject; E: Exception);
var
  F: TextFile;
  Path: string;
  I: Integer;
  Now64: QWord;
begin
  Quiesce;

  { The exception goes into a text file beside the executable, before any
    dialog in case the dialog fails.  More than three in half a minute is a
    state, not an incident: stop writing files and showing boxes so the user
    can get to Ctrl+S.  The count resets after a quiet half minute. }
  Now64 := GetTickCount64;
  if (FWoundCount > 0) and (Now64 - FWoundAt > 30000) then FWoundCount := 0;
  FWoundAt := Now64;
  Inc(FWoundCount);
  if FWoundCount > 3 then
  begin
    FCmdMsg := 'Still failing.  Save with Ctrl+S and restart - the reports ' +
      'are already written.';
    if pbCmd <> nil then pbCmd.Invalidate;
    Exit;
  end;

  Path := ExtractFilePath(ParamStr(0)) + CRASH_LOG;
  try
    AssignFile(F, Path);
    if FileExists(Path) then Append(F) else Rewrite(F);
    try
      WriteLn(F, '---- ', DateTimeToStr(Now), ' ', APP_NAME, ' ',
    CurrentVersion, ' built ', BUILD_STAMP);
      WriteLn(F, E.ClassName, ': ', E.Message);
      Write(F, DiagnosticText);
      Write(F, SettingsText);
      Write(F, MachineText);
      WriteLn(F, BackTraceStrFunc(ExceptAddr));
      if ExceptFrameCount > 0 then
        for I := 0 to ExceptFrameCount - 1 do
          WriteLn(F, BackTraceStrFunc(ExceptFrames[I]));
      WriteLn(F);
    finally
      CloseFile(F);
    end;
    { the drawing beside the report, under its own name, so the next crash
      does not overwrite it }
      SaveCrashDoc(Path);
    { and the drawing area as it was; whether to send it is asked at the next
      start }
    try
      FArt.SaveToPNG(Path + '.png');
    except
    end;
    { Count consecutive crashes: a second after reopening the same drawing
      implicates the drawing, a third says stop.  Cleared on a clean exit. }
    try
      with TIniFile.Create(ConfigFile) do
      try
        WriteInteger('startup', 'crashes',
          ReadInteger('startup', 'crashes', 0) + 1);
      finally
        Free;
      end;
    except
    end;
  except
    { a crash reporter that crashes helps nobody }
  end;
  { most exceptions do not end the program, so offer the report now, from
    the tick, while the user remembers what they were doing }
  if FWoundCount < 3 then FCrashToOffer := True;
  if FWoundCount >= 3 then
    MessageDlg(APP_NAME,
      'That is the third time in a minute.' + LineEnding + LineEnding +
      'Something is wrong that dismissing this will not fix.  Save what you ' +
      'have with Ctrl+S and start the program again - it will offer to send ' +
      'the reports, and they are what gets this mended.' + LineEnding +
      LineEnding +
      'It will stop interrupting you now.  Everything it has been asked to ' +
      'write is already written.',
      mtError, [mbOK], 0)
  else
    MessageDlg(APP_NAME,
      E.ClassName + ': ' + E.Message + LineEnding + LineEnding +
      'Written next to the program:' + LineEnding +
      '  ' + ExtractFileName(Path) + '   - what happened' + LineEnding +
      '  ' + ExtractFileName(Path) + '.hsk   - the drawing it happened to' +
      LineEnding + LineEnding +
      'Both together say exactly where this went wrong.  The drawing is ' +
      'your own work, so have a look before sending it anywhere.',
      mtError, [mbOK], 0);
end;

{ Motion handler: record and return.  Nothing here may paint, allocate,
  hit-test or snap.  See ServiceMotion, which the tick calls. }
procedure TMainForm.pbScreenMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if FBusy then Exit;
  FMoveX := X;
  FMoveY := Y;
  FMoveShift := Shift;
  FMovePending := True;
end;

{ The motion work, at most once per tick, from the newest pointer position.
  Intermediate positions only fed repaints that were immediately overdrawn. }
procedure TMainForm.ServiceMotion;
var
  HeldU, HeldV: TP3;
  SpeedNow: QWord;
  SpeedInst: Double;
  X, Y, HF: Integer;
  HP, HN, HoverP: TP3;
  OP: TPointF;
  NewAz, NewEl: Double;
begin
  if not FMovePending then Exit;
  FMovePending := False;
  X := FMoveX;
  Y := FMoveY;
  { the pointer's speed, for alignment nudges to wait on }
  SpeedNow := GetTickCount64;
  if (FLastMoveTick > 0) and (SpeedNow > FLastMoveTick) then
  begin
    SpeedInst := Sqrt(Sqr(X - FLastMoveX) + Sqr(Y - FLastMoveY)) * 1000 / (SpeedNow - FLastMoveTick);
    FMoveSpeed := FMoveSpeed * 0.5 + SpeedInst * 0.5;
  end
  else if SpeedNow - FLastMoveTick > 150 then
    FMoveSpeed := 0;
  FLastMoveTick := SpeedNow;
  FLastMoveX := X;
  FLastMoveY := Y;

  { The cube first (a list over it would light both), then an open list; the
    drawing underneath gets nothing.  Over the cube the crosshair becomes an
    arrow or hand, since nothing will be drawn there. }
  if CubeMouse(X, Y, False, False) or CubeZone(X, Y) then
  begin
    FMouseSX := X;
    FMouseSY := Y;
    if not FCubeCursor then
    begin
      FCubeCursor := True;
      FCursorWasCube := pbScreen.Cursor;
    end;
    { a hand on the shape, a plain arrow in the margin }
    if FCubeHasHot then pbScreen.Cursor := crHandPoint
    else pbScreen.Cursor := crDefault;
    Exit;
  end;
  if FCubeCursor then
  begin
    FCubeCursor := False;
    pbScreen.Cursor := FCursorWasCube;
  end;

  if FPopup <> POP_NONE then
  begin
    FMouseSX := X;
    FMouseSY := Y;
    HF := PopupItemAt(X, Y);
    { while the command list is being typed at, the pointer leaving it does
      not move the highlight off the row Enter will run }
    if (HF < 0) and (FPopup = POP_CMDS) then HF := FPopupHot;
    if HF <> FPopupHot then
    begin
      FPopupHot := HF;
      FScreenDirty := True;
      pbScreen.Invalidate;
    end;
    Exit;
  end;

  { a held eraser collects whatever it is dragged across }
  if FErasing2 then
  begin
    FMouseSX := X;
    FMouseSY := Y;
    DoomAt(X, Y);
    InvalidateStatus;
    Exit;
  end;

  { Middle drag orbits; Shift pans instead, checked every move so Shift can
    be pressed mid-orbit as in SketchUp. }
  if FOrbiting or FPanning then
  begin
    { where letting go with Ctrl would snap, worked out every move so the cube
      and status line can show it before you commit }
    FSnapHasHot := FOrbiting and (ssCtrl in FMoveShift) and
                   OrbitSnapTarget(FSnapHot);
    if FOrbiting and not (ssShift in FMoveShift) then
    begin
      { Drag right and the model follows the cursor round, like a turntable.
        The rate is a trackball's: fixed at the press by its distance from
        the middle (see OrbitGainAt). }
      { DO NOT fold these into FD.El := EnsureRange(FD.El + ..., -1.45, 1.45).
        FPC 3.3.1 at -O3/-O4 miscompiles that statement and stores the angle
        near address zero, faulting on every orbit.  Computing into locals
        first is the workaround. }
      NewAz := FD.Az - (X - FPanRefX) * ORBIT_RAD_PX * FOrbitGain;
      NewEl := FD.El + (Y - FPanRefY) * ORBIT_RAD_PX * FOrbitGain;
      if NewEl < -1.45 then NewEl := -1.45;
      if NewEl > 1.45 then NewEl := 1.45;
      FD.Az := NewAz;
      FD.El := NewEl;
      FViewPreset := -1;
      { Hold the grabbed point still so the view turns about it.  If the pivot
        projects to nonsense at the new angle, keep the old offset for this
        frame rather than add millions to the view position. }
      if FOrbitAnchored then
      begin
        OP := ScreenOf(FOrbitPivot);
        if (not (IsNan(OP.X) or IsNan(OP.Y) or
                 IsInfinite(OP.X) or IsInfinite(OP.Y))) and
           (Abs(OP.X) < 1E6) and (Abs(OP.Y) < 1E6) then
        begin
          FD.ViewX := FD.ViewX + (FOrbitAnchor.X - OP.X);
          FD.ViewY := FD.ViewY + (FOrbitAnchor.Y - OP.Y);
        end;
      end;
      FCameraMoving := True;
      ViewMoved;
    end
    else
      PanBy(X - FPanRefX, Y - FPanRefY);
    FPanRefX := X;
    FPanRefY := Y;
    Exit;
  end;

  FMouseSX := X;
  FMouseSY := Y;
  { Ctrl partway through a move makes it a copy; the ghost changes color }
  if ((FTool = ptMove) and (FStage = 1)) or ((FTool = ptRotate) and (FStage = 2)) then
    FMoveCopy := ssCtrl in FMoveShift;
  { In 3D a shape started in mid air begins flat every time, and the drag
    lifts it; the plane is not left over from the last shape.  Iso is left
    alone: there the plane is chosen with K or the arrows and kept. }
  ShakeWatch(X, Y);

  { carrying a note by its box }
  if FNoteDrag >= 0 then
  begin
    FMouseSX := X;
    FMouseSY := Y;
    if not FNoteMoved then
    begin
      PushUndo;
      FNoteMoved := True;
    end;
    FD.Doc.MoveNote(FNoteDrag, FNoteFrom, WorldAt(X, Y), FNoteGrab);
    RenderInk;
    RecomposeAll;
    FScreenDirty := True;
    InvalidateStatus;
    Exit;
  end;

  { a hand that has moved lets go of what it was resting on }
  if FNoLockUntilMoved and
     ((Abs(X - FHoldX) > 6) or (Abs(Y - FHoldY) > 6)) then
    FNoLockUntilMoved := False;

  if FStage = 0 then FPlaneFromFace := False;
  if (FStage = 0) and not FPlaneHeld and (FD.View = vkOrbit) then
    FD.Plane := plXY;
  { an arrow-held plane keeps its direction but still passes through a
    face under the cursor that faces the same way }
  if (FStage = 0) and FPlaneHeld and (FD.Plane <> plFree) and
     (FTool in [ptLine, ptRect, ptCircle, ptArc]) and
     FD.Doc.FaceUnder(Proj, X, Y, HF, HP) then
  begin
    HN := Norm3(FD.Doc.FaceNormal(HF));
    PlaneAxes(FD.Plane, HeldU, HeldV);
    if Abs(Abs(Dot3(Norm3(Cross3(HeldU, HeldV)), HN)) - 1) < 1E-3 then
      FCur := HP;
  end;
  if (FStage = 0) and not FPlaneHeld and
     (FTool in [ptLine, ptRect, ptCircle, ptArc]) and
     FD.Doc.FaceUnder(Proj, X, Y, HF, HP) then
  begin
    HN := FD.Doc.FaceNormal(HF);
    { A face square to an axis gets the matching flat plane (faster, and
      colored); any other face (a roof, a hopper side) gets a plane of its
      own, so shapes can be drawn on slopes. }
    if Abs(HN.Z) > 0.999 then FD.Plane := plXY
    else if Abs(HN.Y) > 0.999 then FD.Plane := plXZ
    else if Abs(HN.X) > 0.999 then FD.Plane := plYZ
    else
    begin
      SetFreePlane(HP, HN);
      FD.Plane := plFree;
    end;
    { the plane passes through where the cursor meets the face }
    FCur := HP;
    FFacePt := HP;
    FFaceNm := Norm3(HN);
    FPlaneFromFace := True;
  end;

  { In mid air with the first point down, the drag direction decides flat
    or upright (as SketchUp appears to), before the snap resolves.  A face
    under the first point or an arrow lock wins, and a drag under about a
    sixth of an inch is a twitch, not a direction. }
  if (FStage >= 1) and not FPlaneHeld and not FPlaneFromFace and
     (FD.View = vkOrbit) and
     (FTool in [ptLine, ptRect, ptCircle, ptArc]) then
  begin
    OP := ScreenOf(FP1);
    if Sqr(X - OP.X) + Sqr(Y - OP.Y) >= Sqr(14 * FUIScale) then
      FD.Plane := PlaneByDrag(Proj, FP1, X, Y, FD.Plane);
  end;

  FCur := ResolveSnapAt(X, Y);

  { a snapped point that belongs to a face adopts that face's plane too,
    or arcs end up behind the box }
  if (FStage = 0) and not FPlaneHeld and
     (FTool in [ptLine, ptRect, ptCircle, ptArc]) and
     (FSnapKind in [snEndpoint, snCross, snMidpoint, snSubMid]) then
  begin
    HF := FD.Doc.FaceThrough(FCur);
    if HF >= 0 then
    begin
      HN := FD.Doc.FaceNormal(HF);
      if Abs(HN.Z) > 0.999 then FD.Plane := plXY
      else if Abs(HN.Y) > 0.999 then FD.Plane := plXZ
      else if Abs(HN.X) > 0.999 then FD.Plane := plYZ
      else
      begin
        SetFreePlane(FCur, HN);
        FD.Plane := plFree;
      end;
      FPlaneFromFace := True;
    end;
  end;

  if FTool = ptErase then
  begin
    { the same order the click uses, so what lights is what goes; no face,
      since the click does not take faces }
    FHoverEnt := FD.Doc.HitNote(X, Y);
    { no guides: the eraser does not take them }
    if FHoverEnt < 0 then
      FHoverEnt := FD.Doc.HitEdge(Proj, X, Y, 9 * FUIScale, HIT_NO_GUIDES);
    if FHoverEnt < 0 then
      FHoverEnt := FD.Doc.HitTest(Proj, X, Y, 9 * FUIScale, False);
  end
  else if (FTool = ptSelect) and not FBoxing then
    FHoverEnt := PickAt(X, Y)
  else if (FTool = ptDim) and (FStage = 0) then
  begin
    { Hover an edge and it lights; one click then dimensions all of it, so
      an edge click can be told from a point-to-point start.  Not when the
      cursor is on a point of it: that click takes the point. }
    FHoverEdgeOK := False;
    { except the corners of a curve's straight pieces, which are everywhere
      along it; quadrants, centers and arc ends are still points }
    if (FSnapKind = snEndpoint) and (CurveThrough(FCur) >= 0) then
      FHoverEnt := CurveThrough(FCur)
    else if FSnapKind in [snEndpoint, snMidpoint, snCenter, snCross, snSubMid, snOrigin] then
      FHoverEnt := -1
    else
    begin
      { EdgeUnder, not HitEdge, so a face outline counts too }
      FHoverEdgeOK := FD.Doc.EdgeUnder(Proj, X, Y, 9 * FUIScale,
        HoverP, FHoverEdgeA, FHoverEdgeB, FHoverEnt);
      if FHoverEdgeOK and (FD.Doc[FHoverEnt].Kind = ekGuide) then
      begin
        { a guide is infinite; "all of it" means nothing }
        FHoverEdgeOK := False;
        FHoverEnt := -1;
      end;
      if not FHoverEdgeOK then FHoverEnt := -1;
    end;
  end
  else
    FHoverEnt := -1;
  { The face push/pull or offset would take, so a hit shows before the
    click.  The drawing tools want it too: which face a shape is about to
    go onto (SketchUp washes it and shows its points). }
  if (FTool in [ptPush, ptDrill, ptOffset, ptFollow]) and (FStage = 0) then
    FHoverFace := FD.Doc.HitFace(Proj, X, Y)
  else if (FTool in [ptLine, ptRect, ptCircle, ptArc]) and (FStage = 0) and
          not FPlaneHeld then
    FHoverFace := FD.Doc.HitFace(Proj, X, Y)
  else
    FHoverFace := -1;
  FScreenDirty := True;
  InvalidateStatus;
end;

{ Note where the pivot is on screen, so the orbit holds it at its own place
  on the glass, not under the cursor.  Held under the cursor, an orbit
  started over empty space dragged the whole model across to meet the
  mouse.  SketchUp keeps the canvas center fixed instead; this differs only
  when panned off center, and was kept on purpose. }
procedure TMainForm.AnchorOrbit(SX, SY: Integer);
var
  P: TPointF;
begin
  P := ScreenOf(FOrbitPivot);
  FOrbitAnchored := not (IsNan(P.X) or IsNan(P.Y) or
                         IsInfinite(P.X) or IsInfinite(P.Y)) and
                    (Abs(P.X) < 1E6) and (Abs(P.Y) < 1E6);
  if FOrbitAnchored then FOrbitAnchor := P
  else FOrbitAnchor := PtF(SX, SY);
end;

{ Orbit rate by where the press went down: slow over the middle third,
  faster toward the rim, growing with distance squared, like a trackball. }
function TMainForm.OrbitGainAt(SX, SY: Integer): Double;
var
  R, RMax, T: Double;
begin
  R := Sqrt(Sqr(SX - pbScreen.Width / 2) + Sqr(SY - pbScreen.Height / 2));
  RMax := Min(pbScreen.Width, pbScreen.Height) / 2;
  if RMax < 1 then Exit(1);
  T := Min(1, R / RMax);
  { a quarter of the rate at the middle to the plain rate at the rim }
  Result := 0.25 + 0.75 * T * T;
end;

{ What the view turns about.  An empty sheet turns about the origin: the
  working-plane crossing can come back a billion feet away when the camera
  swings through level. }
function TMainForm.PivotAt(SX, SY: Integer): TP3;
var
  F: Integer;
  P, Lo, Hi: TP3;
  Pts: TP3Array;

  function Sane(const Q: TP3): Boolean;
  begin
    Result := not (IsNan(Q.X) or IsNan(Q.Y) or IsNan(Q.Z) or
                   IsInfinite(Q.X) or IsInfinite(Q.Y) or IsInfinite(Q.Z)) and
              (Abs(Q.X) < 1E7) and (Abs(Q.Y) < 1E7) and (Abs(Q.Z) < 1E7);
  end;

  { A point that is not absurd is not necessarily one you could grab: it
    must project near the glass.  A working plane nearly edge-on to the
    camera gives crossings millions of feet away; on an empty drawing that
    was the only candidate. }
  function Grabbable(const Q: TP3): Boolean;
  var
    S: TPointF;
  begin
    Result := False;
    if not Sane(Q) then Exit;
    S := ScreenOf(Q);
    if IsNan(S.X) or IsNan(S.Y) or IsInfinite(S.X) or IsInfinite(S.Y) then
      Exit;
    Result := (Abs(S.X) < 8 * pbScreen.Width) and
              (Abs(S.Y) < 8 * pbScreen.Height);
  end;

begin
  { About the middle of the screen, where you are looking, as SketchUp does;
    the point under the pointer felt wrong.  Order: the drawn thing under
    the middle, the nearest drawn thing to it from the depth buffer, the
    selection, the drawing's middle. }
  SX := pbScreen.Width div 2;
  SY := pbScreen.Height div 2;
  if FD.Doc.FaceUnder(Proj, SX, SY, F, P) and Grabbable(P) then
    Exit(P);
  if FD.Doc.DepthPointNear(SX, SY, 4000, P) and Grabbable(P) then
    Exit(P);
  if Length(FSel) > 0 then
  begin
    FD.Doc.VertsOf(FSel, Pts);
    if Length(Pts) > 0 then
    begin
      P := P3(0, 0, 0);
      for F := 0 to High(Pts) do P := P3(P.X + Pts[F].X, P.Y + Pts[F].Y, P.Z + Pts[F].Z);
      P := P3(P.X / Length(Pts), P.Y / Length(Pts), P.Z / Length(Pts));
      if Grabbable(P) then Exit(P);
    end;
  end;
  if FD.Doc.Bounds(Lo, Hi) then
  begin
    Result := P3((Lo.X + Hi.X) / 2, (Lo.Y + Hi.Y) / 2, (Lo.Z + Hi.Z) / 2);
    if Grabbable(Result) then Exit;
  end;
  Result := WorldAt(SX, SY);
  if not Grabbable(Result) then Result := P3(0, 0, 0);
end;

{ --- the settings lists ---
  Scale, snap and the pen each have a button showing their value and a list
  that opens above it, as long as it needs to be. }

function TMainForm.PopupCount(Which: Integer): Integer;
begin
  case Which of
    POP_SCALE: Result := SCALE_COUNT;
    POP_SNAP: Result := SNAP_COUNT;
    { one row past the palette, for any other color }
    POP_COLOR: Result := Length(PALETTE) + 1;
    POP_WIDTH: Result := PEN_STEPS;
    POP_HELP: Result := 7;
    POP_SHOP: Result := 5;
    POP_PREC: Result := Length(PREC_DENOMS);
    POP_MORE: Result := Length(MORE_TOOLS);
    POP_CMDS: Result := Length(CMD_LIST);
  else
    Result := 0;
  end;
end;

function TMainForm.PopupCaption(Which, I: Integer): string;
begin
  case Which of
    POP_SCALE: Result := ScaleTable(FD.Units, I).Name +
      IfThen(FD.Units = usImperial, '  =  1''-0"', '');
    POP_SNAP: Result := IfThen(I = 0, 'No snapping', SnapName(FD.Units, I));
    POP_COLOR:
      if I = Length(PALETTE) then Result := 'Another color...' else Result := '';
    POP_WIDTH: Result := Format('%d px', [PEN_SIZES[I]]);
    POP_SHOP:
      case I of
        0: Result := 'Lay a selection out flat(incomplete)';
        1: Result := 'Build a duct fitting...';
        2: Result := 'Fitter''s ISO spool scratchpad';
        3: Result := 'Radiant heat layout...';
        4: Result := 'Stair calculator...';
      else
        Result := '';
      end;
    POP_PREC:
      if PREC_DENOMS[I] = 100 then Result := 'hundredths of an inch'
      else Result := Format('1/%d"', [PREC_DENOMS[I]]);
    POP_MORE:
      if (I >= 0) and (I <= High(MORE_TOOLS)) then
        Result := TOOL_NAMES[MORE_TOOLS[I]]
      else
        Result := '';
    POP_CMDS:
      if (I >= 0) and (I < Length(FCmdOrder)) then
        Result := '/' + CMD_LIST[FCmdOrder[I]].Name
      else
        Result := '';
    POP_HELP:
      case I of
        0: Result := 'About  (F1)';
        1: Result := 'Check for updates';
        2: Result := 'What''s new';
        3: Result := 'Downloads';
        4: Result := 'The manual';
        5: Result := 'Report a problem';
      else
        Result := 'Project page';
      end;
  else
    Result := '';
  end;
end;

procedure TMainForm.PopupChoose(Which, I: Integer);
begin
  case Which of
    POP_SCALE: SetScaleIdx(I);
    POP_SNAP:
      begin
        FD.SnapIdx := EnsureRange(I, 0, SNAP_COUNT - 1);
        FCmdMsg := 'Snap: ' + SnapName(FD.Units, FD.SnapIdx);
      end;
    POP_COLOR:
      if I = Length(PALETTE) then PickAnyColor
      else SetInk(PALETTE[I], False);
    POP_WIDTH: SetEdgeWidth(PEN_SIZES[I]);
    POP_SHOP:
      case I of
        0: StartUnfold;
        1: BuildTransitionWizard;
        2: BuildSpoolWizard;
        3: BuildRadiantWizard;
        4: BuildStairWizard;
      end;
    POP_PREC: SetLenPrecision(PREC_DENOMS[EnsureRange(I, 0, High(PREC_DENOMS))]);
    POP_MORE:
      if (I >= 0) and (I <= High(MORE_TOOLS)) then SetTool(MORE_TOOLS[I]);
    POP_CMDS:
      if (I >= 0) and (I < Length(FCmdOrder)) then
      begin
        NoteCmdUsed(CMD_LIST[FCmdOrder[I]].Name);
        { one that takes an argument is typed into the box, ready; the rest
          just run }
        if CMD_LIST[FCmdOrder[I]].Arg then
        begin
          FInput := '/' + CMD_LIST[FCmdOrder[I]].Name + ' ';
          FCmdMsg := CMD_LIST[FCmdOrder[I]].Hint;
        end
        else
        begin
          FInput := '';
          RunCommand(CMD_LIST[FCmdOrder[I]].Name);
        end;
        pbCmd.Invalidate;
      end;
    POP_HELP:
      case I of
        0: ShowAbout;
        1: begin CheckForUpdate(True); DoUpdate; end;
        2: ShowWhatsNew;
        3: OpenInBrowser('https://github.com/' + UPDATE_REPO + '/releases/latest');
        4: OpenManual;
        5: ReportBug;
      else
        OpenInBrowser('https://github.com/' + UPDATE_REPO);
      end;
  end;
  RebuildDeck;
  pbDeck.Invalidate;
end;

{ How tall a list may get.  The command list is capped at half the window so
  the model stays visible; the rest scrolls. }
function TMainForm.PopupMaxHeight(Which: Integer): Integer;
begin
  Result := pbScreen.Height - 20;
  if Which = POP_CMDS then
    Result := Min(Result, Max(Round(180 * FUIScale), pbScreen.Height div 2));
end;

procedure TMainForm.OpenPopup(Which: Integer);
var
  N, I, W, H, RowH, LeftX, Bottom, TopY, RightMost: Integer;
  B: TRect;
begin
  N := PopupCount(Which);
  if N <= 0 then Exit;
  FPopup := Which;
  FPopupN := N;
  FPopupHot := -1;
  FPopupTop := 0;
  if Which = POP_CMDS then BuildCmdOrder;
  { an arrow over a menu: the pointer is choosing a row, not a point }
  FCursorWas := pbScreen.Cursor;
  pbScreen.Cursor := crDefault;

  { find the button it belongs to, and hang the list off it }
  LeftX := Round(20 * FUIScale);
  TopY := -1;
  { the strip first: a list from a left-hand button opens beside it }
  for I := 0 to High(FTools) do
    if (FTools[I].Group = GRP_POPUP) and (FTools[I].Value = Which) then
    begin
      B := FTools[I].Bounds;
      LeftX := Round(4 * FUIScale);
      TopY := pbTools.Top + B.Top - pbScreen.Top;
      Break;
    end;
  { the command list hangs off the arrow beside the prompt, at the foot }
  if Which = POP_CMDS then
  begin
    LeftX := Round(14 * FUIScale);
    TopY := -1;
  end
  else
  if TopY < 0 then
    for I := 0 to High(FDeck) do
      if ((FDeck[I].Group = GRP_POPUP) and (FDeck[I].Value = Which)) or
         ((Which = POP_HELP) and (FDeck[I].Group = GRP_ICON) and
          (FDeck[I].Value = ACT_HELP)) then
      begin
        B := FDeck[I].Bounds;
        LeftX := pbDeck.Left + B.Left - pbScreen.Left;
        Break;
      end;

  RowH := Round(22 * FUIScale);
  W := Round(190 * FUIScale);
  if Which = POP_COLOR then W := Round(150 * FUIScale);
  if Which = POP_HELP then W := Round(210 * FUIScale);
  { wide, because each row carries what the command does }
  if Which = POP_CMDS then W := Round(430 * FUIScale);
  H := Min(N * RowH + Round(12 * FUIScale), PopupMaxHeight(Which));
  Bottom := pbScreen.Height - Round(6 * FUIScale);
  { How far right a list may go: the deck's right edge, not the drawing's,
    or with the entity panel open the HELP list lands a panel's width from
    its button.  The part past the drawing is painted onto the panel (see
    PaintPopup and pbInfoPaint). }
  RightMost := pbScreen.Width;
  if pbInfo.Visible or pbGroups.Visible then
    RightMost := Max(RightMost,
      pbDeck.Left + pbDeck.Width - pbScreen.Left - Round(2 * FUIScale));
  LeftX := EnsureRange(LeftX, 4, Max(4, RightMost - W - 4));
  if TopY >= 0 then
  begin
    TopY := EnsureRange(TopY, 4, Max(4, pbScreen.Height - H - 4));
    FPopupR := Rect(LeftX, TopY, LeftX + W, TopY + H);
  end
  else
    FPopupR := Rect(LeftX, Max(4, Bottom - H), LeftX + W, Bottom);
  FScreenDirty := True;
  if pbInfo.Visible then pbInfo.Invalidate;
  if pbGroups.Visible then pbGroups.Invalidate;
end;

procedure TMainForm.ClosePopup;
begin
  if FPopup = POP_NONE then Exit;
  FPopup := POP_NONE;
  FPopupHot := -1;
  pbScreen.Cursor := FCursorWas;
  FScreenDirty := True;
  pbScreen.Invalidate;
  { It may have been over the panels too.  Paint them now, not later: a row
    that opens a modal window would leave the list painted there meanwhile. }
  if pbInfo.Visible then
  begin
    pbInfo.Invalidate;
    pbInfo.Update;
  end;
  if pbGroups.Visible then
  begin
    pbGroups.Invalidate;
    pbGroups.Update;
  end;
  pbScreen.Update;
end;

function TMainForm.PopupItemAt(SX, SY: Integer): Integer;
var
  RowH: Integer;
begin
  Result := -1;
  if FPopup = POP_NONE then Exit;
  if (SX < FPopupR.Left) or (SX > FPopupR.Right) or
     (SY < FPopupR.Top) or (SY > FPopupR.Bottom) then Exit;
  RowH := Round(22 * FUIScale);
  Result := (SY - FPopupR.Top - Round(6 * FUIScale)) div RowH + FPopupTop;
  if (Result < FPopupTop) or (Result >= FPopupN) then Result := -1;
end;

{ The wheel while a list is open belongs to the list, not the zoom behind
  it.  True means the wheel was ours even if nothing scrolled.  The
  highlight stays put (scrolling is looking, not choosing), except for the
  row under the pointer. }
function TMainForm.ScrollPopup(Lines, SX, SY: Integer): Boolean;
var
  RowH, Rows, Was, Hot: Integer;
begin
  Result := FPopup <> POP_NONE;
  if not Result then Exit;
  RowH := Max(1, Round(22 * FUIScale));
  Rows := Max(1, (FPopupR.Bottom - FPopupR.Top - Round(12 * FUIScale)) div RowH);
  if FPopupN <= Rows then Exit;
  Was := FPopupTop;
  FPopupTop := EnsureRange(FPopupTop + Lines, 0, FPopupN - Rows);
  if FPopupTop = Was then Exit;
  Hot := PopupItemAt(SX, SY);
  if Hot >= 0 then FPopupHot := Hot;
  FScreenDirty := True;
  pbScreen.Invalidate;
end;

{ a small badge of the current tool, through a scratch surface for
  antialiasing }
procedure TMainForm.PaintToolGlyph(C: TCanvas; AX, AY: Integer);
var
  Sz: Integer;
  Col: TPix;
begin
  Sz := Round(18 * FUIScale);
  Col := Pix(30, 30, 36);
  FGlyph.SetSize(Sz, Sz);
  FGlyph.ClearTransparent;
  PaintIcon(FGlyph, TOOL_ICONS[FTool], Rect(0, 0, Sz, Sz), Col, 0.95);
  FGlyph.DrawTo(C, AX, AY);
end;

{ A list, drawn wherever it lands.  DX, DY shift it from screen coordinates
  to the canvas being painted: zero for the screen, the offset to the
  entity panel when part of the list hangs over it (see pbInfoPaint). }
procedure TMainForm.PaintPopup(C: TCanvas; DX: Integer = 0; DY: Integer = 0);
var
  I, RowH, Y, Cur: Integer;
  R, PR: TRect;
  Sel: Boolean;
  S: string;
begin
  if FPopup = POP_NONE then Exit;
  RowH := Round(22 * FUIScale);
  PR := FPopupR;
  OffsetRect(PR, DX, DY);

  C.Brush.Style := bsSolid;
  C.Brush.Color := PixToColor(MixPix(Theme.Panel, Pix(0, 0, 0), 0.15));
  C.Pen.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.30));
  C.Pen.Width := Max(1, Round(FUIScale));
  C.Rectangle(PR);

  case FPopup of
    POP_SCALE: Cur := FD.ScaleIdx;
    POP_SNAP: Cur := FD.SnapIdx;
  else
    Cur := -1;
  end;

  for I := FPopupTop to FPopupN - 1 do
  begin
    Y := PR.Top + Round(6 * FUIScale) + (I - FPopupTop) * RowH;
    if Y + RowH > PR.Bottom then Break;
    R := Rect(PR.Left + Round(4 * FUIScale), Y,
      PR.Right - Round(4 * FUIScale), Y + RowH - 1);
    { the current choice is lit }
    Sel := (I = Cur) or
      ((FPopup = POP_COLOR) and (I < Length(PALETTE)) and
       (PALETTE[I] = FInkColor)) or
      ((FPopup = POP_WIDTH) and
       (PEN_SIZES[I] = FEdgeW));
    if Sel then
    begin
      C.Brush.Color := PixToColor(ShadePix(Theme.Accent, 0.95));
      C.FillRect(R);
    end
    else if I = FPopupHot then
    begin
      C.Brush.Color := PixToColor(MixPix(Theme.Panel, Pix(255, 255, 255), 0.12));
      C.FillRect(R);
    end;

    if (FPopup = POP_COLOR) and (I < Length(PALETTE)) then
    begin
      C.Brush.Color := PALETTE[I];
      if Sel then
        C.Pen.Color := PixToColor(Pix(255, 255, 255))
      else
        C.Pen.Color := PixToColor(MixPix(Theme.PanelHi, Pix(255, 255, 255), 0.4));
      C.Pen.Width := IfThen(Sel, Max(2, Round(2 * FUIScale)), 1);
      C.Rectangle(R.Left + Round(6 * FUIScale), R.Top + Round(3 * FUIScale),
        R.Right - Round(6 * FUIScale), R.Bottom - Round(3 * FUIScale));
      C.Pen.Width := 1;
      C.Brush.Style := bsSolid;
      Continue;
    end;

    S := PopupCaption(FPopup, I);
    if Sel then UIFont(C, 10, True, OnPix(Theme.Accent))
    else UIFont(C, 10, False, Theme.Text);
    C.TextOut(R.Left + Round(8 * FUIScale),
      R.Top + (RowH - C.TextHeight('X')) div 2, S);

    { What it does, beside its name; on the hovered row, for commands that
      take an argument, an example instead, which is what people open the
      manual to find. }
    if (FPopup = POP_CMDS) and (I < Length(FCmdOrder)) then
    begin
      S := CMD_LIST[FCmdOrder[I]].Hint;
      { found by another of its words: say which }
      if CmdAliasFor(FCmdOrder[I], FCmdWant) <> '' then
        S := '/' + CmdAliasFor(FCmdOrder[I], FCmdWant) + ' - ' + S;
      if (I = FPopupHot) and (CMD_LIST[FCmdOrder[I]].Eg <> '') then
      begin
        S := CMD_LIST[FCmdOrder[I]].Eg;
        { in the typing face, since it is something to type }
        UIFont(C, 10, False, Theme.Accent, True);
      end
      else if Sel then UIFont(C, 10, False, OnPix(Theme.Accent))
      else UIFont(C, 10, False, Theme.TextDim);
      C.TextOut(R.Left + Round(120 * FUIScale),
        R.Top + (RowH - C.TextHeight('X')) div 2, S);
    end;
  end;

  { a scroll bar for a long list }
  if (FPopupN * RowH) > (PR.Bottom - PR.Top - Round(12 * FUIScale)) then
  begin
    I := (PR.Bottom - PR.Top - Round(12 * FUIScale)) div RowH;
    C.Brush.Style := bsSolid;
    C.Brush.Color := PixToColor(MixPix(Theme.Panel, Pix(0, 0, 0), 0.25));
    C.FillRect(Rect(PR.Right - Round(6 * FUIScale), PR.Top + 4,
                    PR.Right - Round(2 * FUIScale), PR.Bottom - 4));
    C.Brush.Color := PixToColor(Theme.Accent);
    Y := PR.Top + 4 +
      Round((PR.Bottom - PR.Top - 8) * FPopupTop / FPopupN);
    C.FillRect(Rect(PR.Right - Round(6 * FUIScale), Y,
                    PR.Right - Round(2 * FUIScale),
                    Y + Max(16, Round((PR.Bottom - PR.Top - 8) *
                                      I / FPopupN))));
  end;
  C.Brush.Style := bsClear;
  C.Pen.Width := 1;
end;

function TMainForm.IsSelected(I: Integer): Boolean;
var
  K: Integer;
begin
  Result := True;
  for K := 0 to High(FSel) do
    if FSel[K] = I then Exit;
  Result := False;
end;

{ The selection outlines drawn once into a transparent layer, kept while the
  drawing, selection, camera and screen size are unchanged. }
procedure TMainForm.EnsureSelLayer;
var
  Key: string;
  AY, K: Integer;
  Hi: TPointFArray;
  W: Single;
  Sum, X: Int64;
  P: TProjector;
begin
  Sum := 0;
  X := 0;
  for K := 0 to High(FSel) do
  begin
    Sum := Sum + FSel[K];
    X := X xor (Int64(FSel[K]) * (K + 1));
  end;
  Key := Format('%p|%d|%d|%d|%d|%.6f|%.6f|%.6f|%.3f|%.3f|%d|%d|%d|%.3f',
    [Pointer(FD.Doc), FD.Doc.FEditSeq, Length(FSel), Sum, X, FD.Az, FD.El, FD.Zoom, FD.ViewX, FD.ViewY,
     Ord(FD.View), FArt.Width, FArt.Height, FUIScale]);
  if (FSelLayer <> nil) and (Key = FSelLayerKey) then Exit;
  FShotOK := False;                { the selection moved: the shot is stale }
  if FSelLayer = nil then FSelLayer := TArtSurface.Create(FArt.Width, FArt.Height)
  else FSelLayer.SetSize(FArt.Width, FArt.Height);
  FSelLayer.ClearTransparent;
  W := Max(3, Round(3 * FUIScale));
  P := Proj;

  { Traced against the depth buffer so back edges are not drawn over the
    front, and traced into the layer with our own rasterizer.  On the LCL
    canvas, thousands of gtk3/cairo calls took seconds per frame on a big
    selection; cached here, a still selection costs nothing after the first
    build. }
  for AY := 0 to High(FSel) do
  begin
    if (FSel[AY] < 0) or (FSel[AY] >= FD.Doc.Live) then Continue;
    { a picked group shows as its box, not every edge lit }
    if FD.Doc.TopPartIn(FSel[AY]) > 0 then Continue;
    if Length(FSel) > SEL_TRACE_MAX then
    begin
      { past SEL_TRACE_MAX, no depth test, just plain outlines: an orbit
        rebuilds this every frame and tracing would be the cost again }
      if FD.Doc[FSel[AY]].Kind in [ekLine, ekArc, ekDim] then
      begin
        Hi := FD.Doc.Outline(P, FSel[AY]);
        for K := 1 to High(Hi) do
          FSelLayer.Line(Hi[K - 1].X, Hi[K - 1].Y, Hi[K].X, Hi[K].Y, W,
            Pix(70, 130, 240), 1.0);
      end;
    end
    else
      TraceOutlineInto(FSelLayer, FSel[AY], Pix(70, 130, 240), W);
  end;
  FSelLayerKey := Key;
end;

{ ---- touch ----
  One finger is the mouse, but the press waits until it moves, is held or
  lifts (a tap); a second finger arriving means a gesture.  Two fingers pan
  by their middle and zoom by their spread.  When one of two lifts, the
  other is ignored until it lifts too, so it does not draw. }
procedure TMainForm.OnTouch(Kind: TTouchKind; Seq: Pointer; SX, SY: Double);
var
  P: TPoint;
  I, K, N: Integer;
begin
  if FBusy then Exit;
  Inc(FTouchCount);
  P := pbScreen.ScreenToClient(Point(Round(SX), Round(SY)));
  I := -1;
  for K := 0 to High(FTouches) do
    if FTouches[K].Seq = Seq then I := K;
  if FTimings then
    TimingLine(Format('touch %d at %.0f,%.0f finger %d of %d mode %d',
      [Ord(Kind), P.X, P.Y, I, Length(FTouches), Ord(FTouchMode)]));
  case Kind of
    tkBegin:
      begin
        if I < 0 then
        begin
          SetLength(FTouches, Length(FTouches) + 1);
          I := High(FTouches);
          FTouches[I].Seq := Seq;
          FTouches[I].X0 := P.X;
          FTouches[I].Y0 := P.Y;
          FTouches[I].T0 := GetTickCount64;
        end;
        FTouches[I].X := P.X;
        FTouches[I].Y := P.Y;
        N := Length(FTouches);
        if N = 1 then
        begin
          FTouchMode := tmPending;
          FTouchDown := False;
          { hover first, so the snap and readout are for this spot }
          pbScreenMouseMove(pbScreen, [], P.X, P.Y);
        end
        else if (N = 2) and (FTouchMode in [tmPending, tmMouse]) then
        begin
          if FTouchDown then
          begin
            pbScreenMouseUp(pbScreen, mbLeft, [ssLeft], FTouches[0].X, FTouches[0].Y);
            FTouchDown := False;
          end;
          FTouchMode := tmGesture;
          GestureStart;
        end;
      end;
    tkUpdate:
      if I >= 0 then
      begin
        FTouches[I].X := P.X;
        FTouches[I].Y := P.Y;
        case FTouchMode of
          tmPending:
            if (Abs(P.X - FTouches[0].X0) > 8) or (Abs(P.Y - FTouches[0].Y0) > 8) then
            begin
              TouchSendDown;
              pbScreenMouseMove(pbScreen, [ssLeft], P.X, P.Y);
            end;
          tmMouse:
            if I = 0 then pbScreenMouseMove(pbScreen, [ssLeft], P.X, P.Y);
          tmGesture:
            if Length(FTouches) >= 2 then GestureMove;
        end;
      end;
    tkEnd, tkCancel:
      if I >= 0 then
      begin
        FTouches[I].X := P.X;
        FTouches[I].Y := P.Y;
        case FTouchMode of
          tmPending:
            if (Kind = tkEnd) and (I = 0) then
            begin
              { a tap: press and release here }
              TouchSendDown;
              pbScreenMouseUp(pbScreen, mbLeft, [ssLeft], P.X, P.Y);
              FTouchDown := False;
            end;
          tmMouse:
            if (I = 0) and FTouchDown then
            begin
              pbScreenMouseUp(pbScreen, mbLeft, [ssLeft], P.X, P.Y);
              FTouchDown := False;
            end;
          tmGesture:
            begin
              { the full frame comes when the camera settles }
              FLastWheel := GetTickCount64;
              FTouchMode := tmSpent;
            end;
        end;
        for K := I to High(FTouches) - 1 do FTouches[K] := FTouches[K + 1];
        SetLength(FTouches, Length(FTouches) - 1);
        if Length(FTouches) = 0 then
        begin
          FTouchMode := tmNone;
          FTouchDown := False;
        end;
      end;
  end;
end;

{ the press for the first finger, where it landed }
procedure TMainForm.TouchSendDown;
begin
  if FTouchDown or (Length(FTouches) = 0) then Exit;
  pbScreenMouseDown(pbScreen, mbLeft, [ssLeft], FTouches[0].X0, FTouches[0].Y0);
  FTouchDown := True;
  FTouchMode := tmMouse;
end;

{ from the tick: a finger held still long enough is a press, not a tap }
procedure TMainForm.TouchTick;
begin
  if (FTouchMode = tmPending) and (Length(FTouches) > 0) and
     (GetTickCount64 - FTouches[0].T0 > 180) then
    TouchSendDown;
end;

procedure TMainForm.GestureStart;
begin
  if Length(FTouches) < 2 then Exit;
  FGestMidX := (FTouches[0].X + FTouches[1].X) / 2;
  FGestMidY := (FTouches[0].Y + FTouches[1].Y) / 2;
  FGestDist := Sqrt(Sqr(FTouches[0].X - FTouches[1].X) + Sqr(FTouches[0].Y - FTouches[1].Y));
end;

procedure TMainForm.GestureMove;
var
  MX, MY, D: Double;
begin
  if Length(FTouches) < 2 then Exit;
  MX := (FTouches[0].X + FTouches[1].X) / 2;
  MY := (FTouches[0].Y + FTouches[1].Y) / 2;
  D := Sqrt(Sqr(FTouches[0].X - FTouches[1].X) + Sqr(FTouches[0].Y - FTouches[1].Y));
  if FQuickFrames then FCameraMoving := True;
  FLastWheel := GetTickCount64;
  if (Abs(MX - FGestMidX) >= 1) or (Abs(MY - FGestMidY) >= 1) then
    PanBy(MX - FGestMidX, MY - FGestMidY);
  { a pinch zooms about the middle; fingers very close give a jumpy ratio,
    so they only pan }
  if (FGestDist > 30) and (D > 30) and (Abs(D / FGestDist - 1) > 0.01) then
    ZoomAt(D / FGestDist, MX, MY);
  FGestMidX := MX;
  FGestMidY := MY;
  FGestDist := D;
  Invalidate;
end;

{ Clear everything that points into the sheet being left (selection,
  doomed list, hover): those indices mean nothing in the next sheet. }
procedure TMainForm.LeaveSheet;
begin
  SetLength(FSel, 0);
  SetLength(FDoomed, 0);
  { and the open-edge marks, which are points in this sheet's space }
  SetLength(FOpenEdges, 0);
  FHoverEnt := -1;
  FHoverFace := -1;
  FPushFace := -1;
  FOffFace := -1;
  FSelLayerKey := '';
  FScreenDirty := True;
end;

{ drop anything in the selection that is not in this sheet }
procedure TMainForm.PruneSelection;
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to High(FSel) do
    if (FSel[I] >= 0) and (FSel[I] < FD.Doc.Live) then
    begin
      FSel[N] := FSel[I];
      Inc(N);
    end;
  if N <> Length(FSel) then
  begin
    SetLength(FSel, N);
    FScreenDirty := True;
  end;
end;

procedure TMainForm.BeginBulkSelect;
var
  K: Integer;
begin
  SetLength(FSelBulk, FD.Doc.Live);
  for K := 0 to High(FSelBulk) do FSelBulk[K] := False;
  for K := 0 to High(FSel) do
    if (FSel[K] >= 0) and (FSel[K] < Length(FSelBulk)) then FSelBulk[FSel[K]] := True;
  FSelBulkOn := True;
end;

procedure TMainForm.EndBulkSelect;
begin
  FSelBulkOn := False;
  SetLength(FSelBulk, 0);
end;

procedure TMainForm.SelectAdd(I: Integer);
var
  T, K: Integer;
  M: TIntArrayW;
begin
  if (I < 0) or (I >= FD.Doc.Live) then Exit;
  if FD.Doc[I].Kind = ekPart then Exit;        { a record comes with its group }
  { a guide is never picked by click, box or /all; the measure tool's
    right-click erases one }
  if FD.Doc[I].Kind = ekGuide then Exit;
  T := FD.Doc.TopPartIn(I);
  if T < 0 then Exit;                            { outside the open group }
  if T = 0 then
  begin
    SelectAddOne(I);
    Exit;
  end;
  { the whole group, record included, so move, copy and delete carry it as
    one thing }
  M := FD.Doc.PartMembers(T, True);
  for K := 0 to High(M) do SelectAddOne(M[K]);
end;

procedure TMainForm.SelectAddOne(I: Integer);
begin
  if I < 0 then Exit;
  if FSelBulkOn and (I < Length(FSelBulk)) then
  begin
    if FSelBulk[I] then Exit;
    FSelBulk[I] := True;
  end
  else if IsSelected(I) then Exit;
  SetLength(FSel, Length(FSel) + 1);
  FSel[High(FSel)] := I;
  FScreenDirty := True;
end;

procedure TMainForm.SelectRemove(I: Integer);
var
  T, K: Integer;
  M: TIntArrayW;
begin
  if (I < 0) or (I >= FD.Doc.Live) then Exit;
  T := FD.Doc.TopPartIn(I);
  if T <= 0 then
  begin
    SelectRemoveOne(I);
    Exit;
  end;
  M := FD.Doc.PartMembers(T, True);
  for K := 0 to High(M) do SelectRemoveOne(M[K]);
end;

procedure TMainForm.SelectRemoveOne(I: Integer);
var
  K, J: Integer;
begin
  for K := 0 to High(FSel) do
    if FSel[K] = I then
    begin
      for J := K to High(FSel) - 1 do FSel[J] := FSel[J + 1];
      SetLength(FSel, Length(FSel) - 1);
      FScreenDirty := True;
      Exit;
    end;
end;

procedure TMainForm.SelectToggle(I: Integer);
begin
  if IsSelected(I) then SelectRemove(I) else SelectAdd(I);
end;

procedure TMainForm.SelectOnly(I: Integer);
begin
  SetLength(FSel, 0);
  SelectAdd(I);
end;

procedure TMainForm.ThemeSourceWindow;
begin
  if SourceForm = nil then Exit;
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  SourceForm.ThemeChrome;
  { dark when the theme's chrome is dark: the window is chrome, not sheet }
  with Themes[FThemeIdx] do
    if Panel.R + Panel.G + Panel.B < 3 * 128 then
      SourceForm.UseDark(True, PixToColor(Panel), PixToColor(Text))
    else
      SourceForm.UseDark(False, clWhite, clBlack);
end;

{ the source window: the sheet as its text, picked both ways }
procedure TMainForm.ShowSource;
begin
  if SourceForm = nil then
  begin
    hsDialogSkin.UseTheme(Themes[FThemeIdx]);
    Application.CreateForm(TSourceForm, SourceForm);
    SourceForm.OnAskState := @SourceAskState;
    SourceForm.OnAskSource := @SourceAskSource;
    SourceForm.OnAskPicked := @SourceAskPicked;
    SourceForm.OnPickThings := @SourcePickThings;
    SourceForm.OnApply := @SourceApply;
    SourceForm.OnRunJigs := @RunAllJigs;
    SourceForm.OnRunJig := @RunJigOfThing;
    SourceForm.OnPick := @SourcePick;
    SourceForm.OnCenter := @SourceCenter;
    { owned by the main window, so on Windows it opens in front of it, not
      behind }
    SourceForm.PopupMode := pmExplicit;
    SourceForm.PopupParent := Self;
    { beside the main window if there is room, else over its right half }
    if (FSourceBounds.Right > 200) and (FSourceBounds.Bottom > 150) and
       (FSourceBounds.Left + FSourceBounds.Right > Screen.DesktopLeft + 40) and
       (FSourceBounds.Left < Screen.DesktopLeft + Screen.DesktopWidth - 40) and
       (FSourceBounds.Top < Screen.DesktopTop + Screen.DesktopHeight - 40) then
      { where it was left, if that is still on a screen }
      SourceForm.SetBounds(FSourceBounds.Left, FSourceBounds.Top, FSourceBounds.Right, FSourceBounds.Bottom)
    else
    begin
      SourceForm.Height := Height;
      SourceForm.Top := Top;
      if Left + Width + SourceForm.Width <= Screen.DesktopLeft + Screen.DesktopWidth then
        SourceForm.Left := Left + Width
      else
        SourceForm.Left := Left + Width - SourceForm.Width;
    end;
  end;
  { in the program's theme, with a matching picked-line wash }
  ThemeSourceWindow;
  SourceForm.chkOnTop.Checked := FSourceOnTop;
  SourceForm.SetAutoComplete(FSourceComplete);
  SourceForm.Show;
  SourceForm.Refresh_;
end;

{ Two numbers that change when the drawing or the picking does; cheap, since
  the window asks several times a second.  The hash is meant to wrap, so
  overflow checks are off. }
{$push}{$Q-}{$R-}
procedure TMainForm.SourceAskState(out DocSeq, PickSeq: Int64);
var
  I: Integer;
begin
  DocSeq := 0;
  PickSeq := 0;
  if FD = nil then Exit;
  DocSeq := Int64(PtrUInt(FD)) xor (Int64(FD.Doc.FEditSeq) shl 20) xor
            (Int64(FD.Doc.Live) shl 8) xor (Int64(FD.UndoTop) shl 40) xor
            (Int64(FD.RedoTop) shl 50) xor FD.Doc.Context;
  PickSeq := Length(FSel);
  for I := 0 to High(FSel) do
    PickSeq := (PickSeq * 1000003) xor FSel[I];
end;
{$pop}

procedure TMainForm.SourceAskSource(L, Hints, Names: TStrings;
  out First, Last, LineThing: TIntArrayW; out SheetName: string);
begin
  SetLength(First, 0);
  SetLength(Last, 0);
  SetLength(LineThing, 0);
  SheetName := '';
  if FD = nil then Exit;
  SheetName := FD.Name;
  WriteFormat2(FD.Doc, FD.Name, FD.Units, L, First, Last, LineThing, Hints, Names);
end;

procedure TMainForm.SourceAskPicked(out Picked: TIntArrayW);
var
  I: Integer;
begin
  SetLength(Picked, Length(FSel));
  for I := 0 to High(FSel) do Picked[I] := FSel[I];
end;

{ Lines picked in the source window, through SelectAdd so the sheet's rules
  apply: a thing in a closed group picks the group, one outside the open
  group is not picked. }
procedure TMainForm.SourcePickThings(const Things: TIntArrayW);
var
  I: Integer;
  M: TIntArrayW;
begin
  if FD = nil then Exit;
  SelectNone;
  BeginBulkSelect;
  for I := 0 to High(Things) do
    if FD.Doc[Things[I]].Kind = ekPart then
    begin
      { a GROUP line is the group: any member picks the whole }
      M := FD.Doc.PartMembers(FD.Doc[Things[I]].Grp, False);
      if Length(M) > 0 then SelectAdd(M[0]);
    end
    else
      SelectAdd(Things[I]);
  EndBulkSelect;
  FScreenDirty := True;
  InfoChanged;
  pbScreen.Invalidate;
end;

{ Apply the source window's text to the drawing.  Read into a scratch
  drawing first, so a fault leaves this one untouched. }
function TMainForm.SourceApply(L: TStrings; out ErrLine: Integer; out Err: string): Boolean;
var
  T: TWorkDoc;
begin
  Result := False;
  ErrLine := -1;
  Err := 'there is no sheet open';
  if FD = nil then Exit;
  T := TWorkDoc.Create;
  try
    Result := ReadHeck(L, T, FD.Units, ErrLine, Err);
  finally
    T.Free;
  end;
  if not Result then Exit;
  PushUndo;
  LeaveSheet;        { every held index is about to mean something else }
  ResetTool;
  FD.Doc.Clear;
  ReadHeck(L, FD.Doc, FD.Units, ErrLine, Err);
  FD.Dirty := True;
  RebuildFlatFaces;
  RenderInk;
  RecomposeAll;
  FCmdMsg := Format('Applied: %d things.', [FD.Doc.Live]);
  pbScreen.Invalidate;
  pbCmd.Invalidate;
end;

{ Run a group's jig again.  Its output is read into a scratch drawing
  first; only if that works is the group's content replaced, in one undo
  step. }
function TMainForm.RunJigOf(PartId: Integer): Boolean;
var
  SF: TStairFrame;
  SS: TStairSpec;
  SU: TStairUse;
  Spec, Err: string;
  Out_: TStringList;
  T: TWorkDoc;
  M: TIntArrayW;
  Doomed: array of Boolean;
  I, ErrLine, WasStamp, Rec: Integer;
begin
  Result := False;
  if FD = nil then Exit;
  Spec := FD.Doc.PartJig(PartId);
  if Spec = '' then
  begin
    FCmdMsg := 'That group is not made by a jig.';
    Exit;
  end;
  { the stairs are the program's own: rebuilt from what they remember, where
    the group is now, no script }
  if IsStairJig(Spec) then
  begin
    if not StairFromJig(Spec, FD.Units, SF, SS, SU) then
    begin
      FCmdMsg := 'The stairs'' line in the source does not read: ' + Spec;
      Exit;
    end;
    SF.Bottom := StairWhereNow(PartId, SF, SS);
    if not StairCheck(SF, SS, Err) then
    begin
      FCmdMsg := 'The stairs cannot be built from that: ' + Err;
      Exit;
    end;
    PushUndo;
    StairRebuild(PartId, SF, SS, SU);
    Exit(True);
  end;
  Out_ := TStringList.Create;
  try
    Screen.Cursor := crHourGlass;
    try
      if not RunJig(Spec, FD.Units, Out_, Err) then
      begin
        FCmdMsg := 'The jig did not run - ' + Err;
        Exit;
      end;
    finally
      Screen.Cursor := crDefault;
    end;
    T := TWorkDoc.Create;
    try
      if not ReadHeck(Out_, T, FD.Units, ErrLine, Err) then
      begin
        FCmdMsg := Format('Heck if I know - what the jig printed is not Heck.  Line %d: %s', [ErrLine + 1, Err]);
        Exit;
      end;
    finally
      T.Free;
    end;
    PushUndo;
    LeaveSheet;
    ResetTool;
    M := FD.Doc.PartMembers(PartId, False);
    Rec := FD.Doc.PartEnt(PartId);
    SetLength(Doomed, FD.Doc.Live);
    for I := 0 to High(Doomed) do Doomed[I] := False;
    for I := 0 to High(M) do
      if M[I] <> Rec then Doomed[M[I]] := True;
    FD.Doc.DeleteMarked(Doomed);
    WasStamp := FD.Doc.Stamp;
    FD.Doc.Stamp := PartId;
    try
      ReadHeck(Out_, FD.Doc, FD.Units, ErrLine, Err);
    finally
      FD.Doc.Stamp := WasStamp;
    end;
    FD.Dirty := True;
    Result := True;
  finally
    Out_.Free;
  end;
end;

{ center and fit the selection: a glide in 3D, as a cube click does,
  straight there in plan and iso }
procedure TMainForm.SourceCenter;
var
  FitZ, FitX, FitY: Double;
begin
  if (FD = nil) or (Length(FSel) = 0) then Exit;
  if FitTarget(True, FD.Az, FD.El, FitZ, FitX, FitY) then
    GlideCamera(FD.Az, FD.El, FitZ, FitX, FitY);
end;

procedure TMainForm.SourcePick(On: Boolean);
begin
  FTextPick := On;
  if On then
  begin
    FCmdMsg := 'Picking for the text: click a point on the sheet, and it is typed in.  Esc stops.';
    { the sheet is not raised, so the text being filled stays in view }
    pbScreen.Invalidate;
  end
  else
    FCmdMsg := 'Picking for the text is over.';
  pbCmd.Invalidate;
end;

function TMainForm.RunJigOfThing(Thing: Integer): Boolean;
begin
  Result := False;
  if (FD = nil) or (Thing < 0) or (Thing >= FD.Doc.Live) then Exit;
  if (FD.Doc[Thing].Kind <> ekPart) or (FD.Doc[Thing].Jig = '') then Exit;
  Result := RunJigOf(FD.Doc[Thing].Grp);
  if Result then
  begin
    RebuildFlatFaces;
    RenderInk;
    RecomposeAll;
    pbScreen.Invalidate;
  end;
end;

function TMainForm.RunAllJigs: Integer;
var
  Ids: TIntArrayW;
  I, N: Integer;
begin
  Result := 0;
  if FD = nil then Exit;
  { collect the ids first: running a jig moves everything in the list }
  N := 0;
  SetLength(Ids, FD.Doc.Live);
  for I := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[I].Kind = ekPart) and (FD.Doc[I].Jig <> '') then
    begin
      Ids[N] := FD.Doc[I].Grp;
      Inc(N);
    end;
  for I := 0 to N - 1 do
    if RunJigOf(Ids[I]) then Inc(Result);
  RebuildFlatFaces;
  RenderInk;
  RecomposeAll;
  if Result = N then FCmdMsg := Format('%d jigs run.', [Result]);
  pbScreen.Invalidate;
  pbCmd.Invalidate;
end;

{ The panels read the selection, so they are refreshed wherever it or the
  drawing changes; a panel a frame behind is worse than none. }
procedure TMainForm.InfoChanged;
begin
  GroupsChanged;
  if not FInfoOn then Exit;
  RebuildInfo;
  pbInfo.Invalidate;
end;

procedure TMainForm.SelectNone;
begin
  if Length(FSel) = 0 then Exit;
  SetLength(FSel, 0);
  FScreenDirty := True;
end;

{ does this entity have a corner at that point? }
function TMainForm.EntHasPoint(I: Integer; const P: TP3): Boolean;
const
  TOL = 1E-7;
var
  K: Integer;
begin
  Result := True;
  if Dist(FD.Doc[I].A, P) < TOL then Exit;
  if Dist(FD.Doc[I].B, P) < TOL then Exit;
  for K := 0 to High(FD.Doc[I].Poly) do
    if Dist(FD.Doc[I].Poly[K], P) < TOL then Exit;
  Result := False;
end;

{ Double click: a face takes the edges round it, an edge the faces it
  bounds (SketchUp's rule). }
procedure TMainForm.SelectAttached(I: Integer);
var
  J: Integer;
begin
  SelectOnly(I);
  if I < 0 then Exit;
  if FD.Doc.TopPartIn(I) > 0 then Exit;    { a group is the whole of itself }
  { a guide is not part of the drawing, so nothing is attached to it }
  if FD.Doc[I].Kind = ekGuide then Exit;
  if FD.Doc[I].Kind = ekFace then
  begin
    for J := 0 to FD.Doc.Live - 1 do
      if (J <> I) and (FD.Doc[J].Kind in [ekLine, ekArc]) and
         EntHasPoint(I, FD.Doc[J].A) and EntHasPoint(I, FD.Doc[J].B) then
        SelectAdd(J);
  end
  else
    for J := 0 to FD.Doc.Live - 1 do
      if (J <> I) and (FD.Doc[J].Kind = ekFace) and
         EntHasPoint(J, FD.Doc[I].A) and EntHasPoint(J, FD.Doc[I].B) then
        SelectAdd(J);
end;

{ Triple click: everything joined on, however far it runs.  A flood over
  shared corners, using a hash of every corner and the things that have it
  (testing everything against everything was minutes on a big part).  A
  solid's members come along in one step. }
procedure TMainForm.SelectConnected(I: Integer);
var
  Have: array of Boolean;
  Queue: array of Integer;
  QHead, QTail, J, K, N, E: Integer;
  Pts: TP3Array;
  Map: TFPHashList;
  Key: shortstring;
  Lists: array of TIntArrayW;
  ListIx: Integer;

  function KeyOf(const P: TP3): shortstring;
  var
    Q: array[0..2] of Int64;
  begin
    Q[0] := Round(P.X * 1E7); Q[1] := Round(P.Y * 1E7); Q[2] := Round(P.Z * 1E7);
    SetLength(Result, 24);
    Move(Q[0], Result[1], 24);
  end;

  procedure Take(E: Integer);
  begin
    if (E < 0) or Have[E] then Exit;
    { guides share corners but are not part of the drawing; never flood
      through them }
    if FD.Doc[E].Kind = ekGuide then Exit;
    Have[E] := True;
    if QTail >= Length(Queue) then SetLength(Queue, Max(64, QTail * 2));
    Queue[QTail] := E;
    Inc(QTail);
  end;

begin
  SelectOnly(I);
  if I < 0 then Exit;
  { three clicks on a guide is still just the guide }
  if FD.Doc[I].Kind = ekGuide then Exit;
  N := FD.Doc.Live;
  SetLength(Have, N);
  SetLength(Queue, 64);
  QHead := 0; QTail := 0;
  { every corner once, with the list of things that have it }
  Map := TFPHashList.Create;
  try
    for J := 0 to N - 1 do
    begin
      FD.Doc.VertsOf([J], Pts);
      for K := 0 to High(Pts) do
      begin
        Key := KeyOf(Pts[K]);
        { stored one up: a nil item is an empty slot to TFPHashList }
        ListIx := Map.FindIndexOf(Key);
        if ListIx < 0 then
        begin
          SetLength(Lists, Length(Lists) + 1);
          ListIx := High(Lists);
          Map.Add(Key, Pointer(PtrInt(ListIx + 1)));
        end
        else
          ListIx := PtrInt(Map.Items[ListIx]) - 1;
        if (Length(Lists[ListIx]) = 0) or (Lists[ListIx][High(Lists[ListIx])] <> J) then
        begin
          SetLength(Lists[ListIx], Length(Lists[ListIx]) + 1);
          Lists[ListIx][High(Lists[ListIx])] := J;
        end;
      end;
    end;
    Take(I);
    while QHead < QTail do
    begin
      E := Queue[QHead];
      Inc(QHead);
      { the rest of its solid, in one go }
      if FD.Doc[E].Grp > 0 then
        for J := 0 to N - 1 do
          if (not Have[J]) and (FD.Doc[J].Grp = FD.Doc[E].Grp) then Take(J);
      { and whatever shares a corner with it }
      FD.Doc.VertsOf([E], Pts);
      for K := 0 to High(Pts) do
      begin
        ListIx := Map.FindIndexOf(KeyOf(Pts[K]));
        if ListIx < 0 then Continue;
        ListIx := PtrInt(Map.Items[ListIx]) - 1;
        for J := 0 to High(Lists[ListIx]) do Take(Lists[ListIx][J]);
      end;
    end;
  finally
    Map.Free;
  end;
  SetLength(FSel, QTail);
  for J := 0 to QTail - 1 do FSel[J] := Queue[J];
  FScreenDirty := True;
end;

{ SketchUp's modifiers: Ctrl adds, Shift toggles, both take away, nothing
  held starts over.  Right to left takes anything the box touches; left to
  right only what fits inside. }
procedure TMainForm.FinishSelect(X, Y: Integer; Shift: TShiftState);
var
  I: Integer;
  Add, Sub, Tog: Boolean;
begin
  Add := ssCtrl in Shift;
  Tog := ssShift in Shift;
  Sub := Add and Tog;

  if (Abs(X - FBoxX) > 3) or (Abs(Y - FBoxY) > 3) then
  begin
    SelectInBox(FBoxX, FBoxY, X, Y, X < FBoxX, Add or Tog);
  end
  else
  begin
    I := PickAt(X, Y);
    if I < 0 then
    begin
      { SketchUp: a click on nothing while a group is open closes it }
      if not (Add or Tog) then
        if FD.Doc.Context <> 0 then CloseGroup else SelectNone;
    end
    else if FD.Doc.TopPartIn(I) > 0 then
    begin
      { a group: double-click opens it, otherwise the whole group is taken.
        GTK delivers a double-click's second press twice, so the count reads
        one higher; hence >= 2 for double and >= 3 for triple throughout. }
      if FClickN >= 2 then OpenGroup(FD.Doc.TopPartIn(I))
      else if Sub then SelectRemove(I)
      else if Tog then SelectToggle(I)
      else if Add then SelectAdd(I)
      else SelectOnly(I);
    end
    else if FClickN >= 3 then SelectConnected(I)
    else if FClickN = 2 then SelectAttached(I)
    else if Sub then SelectRemove(I)
    else if Tog then SelectToggle(I)
    else if Add then SelectAdd(I)
    else SelectOnly(I);
  end;

  if Length(FSel) = 0 then
  begin
    if FCmdMsg = '' then FCmdMsg := 'Nothing selected.';
  end
  else if SoleGroup > 0 then
    FCmdMsg := Format('Group "%s"%s - double-click to work inside it.',
      [FD.Doc.PartName(SoleGroup),
       specialize IfThen<string>(FD.Doc.PartLocked(SoleGroup), ' (locked)', '')])
  { a lone dimension can be told what to say, so the message says so }
  else if SelectedDim >= 0 then
    FCmdMsg := 'Dimension picked - type what it should read and press Enter.'
  else if Length(FSel) = 1 then FCmdMsg := '1 thing selected.'
  else FCmdMsg := Format('%d things selected.', [Length(FSel)]);
  FScreenDirty := True;
  InvalidateStatus;
end;

{ crossing takes anything the box touches, otherwise only what is wholly
  inside }
procedure TMainForm.SelectInBox(X0, Y0, X1, Y1: Integer; Crossing, Add: Boolean);
var
  I, T: Integer;
  Picked: TIntArrayW;
  Tk: QWord;
  BX0, BY0, BX1, BY1: Double;
begin
  if X1 < X0 then begin T := X0; X0 := X1; X1 := T; end;
  if Y1 < Y0 then begin T := Y0; Y0 := Y1; Y1 := T; end;
  if not Add then SetLength(FSel, 0);
  Tk := GetTickCount64;
  BeginBulkSelect;
  { what the box takes is BoxPick's question (see it and BoxTakes) }
  Picked := FD.Doc.BoxPick(Proj, X0, Y0, X1, Y1, Crossing);
  for I := 0 to High(Picked) do SelectAdd(Picked[I]);
  EndBulkSelect;
  Took('box select', Tk);
  FScreenDirty := True;
end;

procedure TMainForm.DeleteSelection;
var
  I, N: Integer;
  Doomed: array of Boolean;
  Held: TIntArrayW;
  Tk: QWord;
begin
  N := Length(FSel);
  if N = 0 then Exit;
  PushUndo;
  Tk := GetTickCount64;
  { marked and removed in one pass; deleting one at a time was quadratic }
  SetLength(Doomed, FD.Doc.Live);
  for I := 0 to High(Doomed) do Doomed[I] := False;
  for I := 0 to N - 1 do
    if (FSel[I] >= 0) and (FSel[I] < Length(Doomed)) and
       not FD.Doc.PartLockedUp(FD.Doc.TopPartIn(FSel[I])) then Doomed[FSel[I]] := True;
  { and the faces those edges were holding up (see FacesOnEdges) }
  FD.Doc.FacesOnEdges(FSel, Held);
  for I := 0 to High(Held) do Doomed[Held[I]] := True;
  FD.Doc.PointsOnGuides(FSel, Held);
  for I := 0 to High(Held) do Doomed[Held[I]] := True;
  FD.Doc.DeleteMarked(Doomed);
  Took('delete selection', Tk);
  SetLength(FSel, 0);
  RebuildFlatFaces;
  FCmdMsg := Format('Deleted %d thing%s.', [N, IfThen(N = 1, '', 's')]);
  RenderInk;
  RecomposeAll;
end;

{ How far the move has traveled.  Typed wins: a bare length runs along the
  current direction, [x,y,z] is a point in the drawing, <x,y,z> an offset
  from the grab. }
function TMainForm.MoveDelta: TP3;
var
  D: TP3;
  L, Len: Double;
  Txt: string;
  Abs_, Rel: Boolean;
  N: Integer;
  V: array[0..2] of Double;
begin
  Result := P3(FCur.X - FP1.X, FCur.Y - FP1.Y, FCur.Z - FP1.Z);

  Txt := Trim(FInput);
  Abs_ := (Length(Txt) >= 2) and (Txt[1] = '[');
  Rel := (Length(Txt) >= 2) and (Txt[1] = '<');
  if Abs_ or Rel then
  begin
    N := ParseTriple(Txt, FD.Units, V[0], V[1], V[2]);
    if N > 0 then
    begin
      if Abs_ then
        Result := P3(V[0] - FP1.X, V[1] - FP1.Y, V[2] - FP1.Z)
      else
        Result := P3(V[0], V[1], V[2]);
    end;
    Exit;
  end;

  if FDirLock >= 0 then
  begin
    D := AxisDir(FDirLock);
    L := Result.X * D.X + Result.Y * D.Y + Result.Z * D.Z;
    if (Txt <> '') and ParseLen(Txt, FD.Units, Len) then
      L := Sign(IfThen(L = 0, 1, L)) * Len;
    Result := P3(D.X * L, D.Y * L, D.Z * L);
    Exit;
  end;

  { Shift keeps the axis the move has drifted onto, as SketchUp locks the
    showing inference }
  if ssShift in FMoveShift then
  begin
    if (Abs(Result.X) >= Abs(Result.Y)) and (Abs(Result.X) >= Abs(Result.Z)) then
      Result := P3(Result.X, 0, 0)
    else if Abs(Result.Y) >= Abs(Result.Z) then
      Result := P3(0, Result.Y, 0)
    else
      Result := P3(0, 0, Result.Z);
  end;

  if (Txt <> '') and ParseLen(Txt, FD.Units, L) then
  begin
    Len := Sqrt(Sqr(Result.X) + Sqr(Result.Y) + Sqr(Result.Z));
    if Len < 1E-9 then Exit;
    Result := P3(Result.X * L / Len, Result.Y * L / Len, Result.Z * L / Len);
  end;
end;

{ The arc's ends are on the two lines of a corner, so it could round that
  corner: the fillet that keeps the first click where it was. }
function TMainForm.FilletCandidate(out F: TFillet): Boolean;
begin
  Result := (FTool = ptArc) and (FStage = 2) and
            FD.Doc.FilletFromEnds(FP1, FP2, F);
end;

{ Is the arc being placed a fillet, and which?  As SketchUp turns the arc
  magenta when tangent to both lines: the fillet is worked out from the two
  ends, and taken when the pull is within a finger's width of its middle.  A
  number typed while magenta, or with an r suffix, is the radius.  Typed says
  a radius was typed. }
function TMainForm.ArcFillet(out F: TFillet; out Typed: Boolean): Boolean;
const
  LOCK_PX = 16;
var
  Txt: string;
  L: Double;
  RSuffix, Near_: Boolean;
  M: TPointF;
  F2: TFillet;
begin
  Result := False;
  Typed := False;
  if not FilletCandidate(F) then Exit;
  M := ScreenOf(ArcPoint(F.ArcC, F.R, F.A0 + F.Sweep / 2, F.Pl, F.Nm));
  Near_ := Sqrt(Sqr(M.X - FMouseSX) + Sqr(M.Y - FMouseSY)) <= LOCK_PX * FUIScale;
  Txt := Trim(FInput);
  RSuffix := (Length(Txt) > 1) and (Txt[Length(Txt)] in ['r', 'R']);
  if RSuffix then Delete(Txt, Length(Txt), 1);
  if (Txt <> '') and (RSuffix or Near_) then
  begin
    if not ParseLen(Txt, FD.Units, L) then Exit;
    if not FD.Doc.FilletAt(F.Corner, L, F2) then Exit;
    F := F2;
    Typed := True;
    Exit(True);
  end;
  Result := Near_;
end;

{ The face a press is on: the one under the pointer, or during a replay the
  one holding the pressed point (another window or camera can find a
  different face behind the same pixel). }
function TMainForm.FaceAtPress: Integer;
begin
  if FReplayFace >= 0 then Result := FReplayFace
  else Result := FD.Doc.HitFace(Proj, FMouseSX, FMouseSY);
end;

{ the face the overlay is washing blue now, or -1: the same choices
  PaintOverlay makes, for the cursor's square }
function TMainForm.HintFaceNow: Integer;
begin
  Result := -1;
  case FTool of
    ptPush, ptDrill:
      if FStage = 1 then Result := FPushFace else Result := FHoverFace;
    ptFollow:
      if FStage = 0 then Result := FHoverFace else Result := FFollowFace;
    ptLine, ptRect, ptCircle, ptArc:
      if (FStage = 0) and not FPlaneHeld then
        Result := InContextFace(FD.Doc.HitFace(Proj, FMouseSX, FMouseSY));
  end;
end;

{ The part of a tool's preview under the pointer, drawn into the cursor's
  square (see pbScreenPaint).  OX, OY is the square's corner on screen. }
procedure TMainForm.PaintUnderCursor(S: TArtSurface; OX, OY: Integer);
var
  F: TFillet;
  Typed: Boolean;
  K, HF: Integer;
  PA, PB: TPointF;
  RectPts: TP3Array;
begin
  { The square pasted back over the cursor is a patch of the finished
    drawing without the preview, and the preview's nearest corner is always
    right at the cursor, so draw it into the square.  Theme.Accent is close
    enough at this size to the real line's color. }
  if (FTool = ptLine) and (FStage = 1) then
  begin
    PA := ScreenOf(FP1);
    PB := ScreenOf(PreviewTarget);
    S.Line(PA.X - OX, PA.Y - OY, PB.X - OX, PB.Y - OY,
      Max(3, Round(3 * FUIScale)), Theme.Accent, 1);
  end
  else if (FTool = ptRect) and (FStage = 1) then
  begin
    RectPts := RectCorners(FP1, RectTarget, FD.Plane);
    for K := 0 to 3 do
    begin
      PA := ScreenOf(RectPts[K]);
      PB := ScreenOf(RectPts[(K + 1) mod 4]);
      S.Line(PA.X - OX, PA.Y - OY, PB.X - OX, PB.Y - OY,
        Max(3, Round(3 * FUIScale)), Theme.Accent, 1);
    end;
  end
  else if (FTool = ptOffset) and (FStage = 1) then
  begin
    { the offset loop, likewise: its nearest corner is the one being dragged }
    RectPts := OffsetPreview;
    for K := 0 to High(RectPts) do
    begin
      PA := ScreenOf(RectPts[K]);
      PB := ScreenOf(RectPts[(K + 1) mod Length(RectPts)]);
      S.Line(PA.X - OX, PA.Y - OY, PB.X - OX, PB.Y - OY,
        Max(3, Round(3 * FUIScale)), Theme.Accent, 1);
    end;
  end;

  { the blue face wash, drawn into the square too, or the square cuts a hole
    in it right at the pointer }
  HF := HintFaceNow;
  { the square comes from the shown picture, which may already have it }
  if (HF >= 0) and (HF <> FHintInShot) then
    PaintFaceHint(nil, HF, HINT_BLUE, S, OX, OY);
  if not ArcFillet(F, Typed) then Exit;
  S.BlendMode := bmNormal;
  PA := ScreenOf(ArcPoint(F.ArcC, F.R, F.A0, F.Pl, F.Nm));
  for K := 1 to FSidesArc do
  begin
    PB := ScreenOf(ArcPoint(F.ArcC, F.R, F.A0 + F.Sweep * K / FSidesArc,
      F.Pl, F.Nm));
    S.Line(PA.X - OX, PA.Y - OY, PB.X - OX, PB.Y - OY,
      Max(3, Round(3 * FUIScale)), Pix(225, 40, 225), 1);
    PA := PB;
  end;
end;

{ The second click of a double-click with the arc tool.  Right after a
  fillet it trims that corner (SketchUp's double-click); otherwise, near a
  corner, it rounds it with the last radius. }
function TMainForm.ArcDoubleClick(SX, SY: Integer): Boolean;
var
  Corner: TP3;
  F: TFillet;
  N: Integer;
begin
  Result := False;
  if FTool <> ptArc then Exit;
  { only the double-click whose first click made the fillet; a pending trim
    used a minute later would hit the old corner instead of the new one }
  if FFilletPending and (FFilletSeq = FEditSeq) and
     (GetTickCount64 - FFilletTick < 800) then
  begin
    FFilletPending := False;
    N := FD.Doc.TrimFillet(FLastFillet);
    if N > 0 then
    begin
      RebuildFlatFaces;
      RenderInk;
      RecomposeAll;
      FCmdMsg := 'Corner rounded to ' + FormatLen(FLastFillet.R, FD.Units) +
        ' and trimmed.  Double-click another corner for the same again.';
      ResetTool;
      Exit(True);
    end;
  end;
  FFilletPending := False;
  if FLastFilletR <= 0 then Exit;
  if not FD.Doc.NearestCorner(Proj, SX, SY, 18 * FUIScale, Corner) then Exit;
  ResetTool;
  if not FD.Doc.FilletAt(Corner, FLastFilletR, F) then
  begin
    FCmdMsg := 'A ' + FormatLen(FLastFilletR, FD.Units) +
      ' radius does not fit that corner.';
    Exit(True);
  end;
  PushUndo;
  FD.Doc.ApplyFillet(F, FSidesArc, FInkColor, FEdgeW, True);
  RebuildFlatFaces;
  RenderInk;
  RecomposeAll;
  FCmdMsg := 'Same again - corner rounded to ' + FormatLen(F.R, FD.Units) + '.';
  Result := True;
end;

{ Alt's tangent lock: the bulge that runs the arc smoothly out of the edge
  its first point is on (see TangentSagitta in hsDrawing). }
function TMainForm.TangentBulge(Pl: TPlane; out Bulge: Double): Boolean;
begin
  Result := FArcTanHas and
            TangentSagitta(FP1, FP2, FArcTanDir, Pl, Bulge);
end;

function TMainForm.ArcPicks(const B: TP3; out Pl: TPlane; out C: TP3;
  out R, A0, Sweep, Bulge: Double): Boolean;
var
  AU, AV, N, FN: TP3;
  U1, V1, U2, V2, UC, VC, Ln, NU, NV, L, Size, Tol: Double;
  F: Integer;

  function OnPlane(const P, Org, Nm: TP3): Boolean;
  begin
    Result := Abs(Dot3(Nm, P3(P.X - Org.X, P.Y - Org.Y, P.Z - Org.Z))) <= Tol;
  end;

begin
  Result := False;
  Bulge := 0;
  C := FP1; R := 0; A0 := 0; Sweep := 0;
  Pl := FD.Plane;
  Size := Max(Dist(FP2, FP1), Dist(B, FP1));
  if Size < 1E-9 then Exit;
  Tol := 1E-6 * (1 + Size);
  PlaneAxes(Pl, AU, AV);
  N := Norm3(Cross3(AU, AV));
  { A pull off the working plane onto a face holding all three points puts
    the arc on that face (a chord along a wall's base is in both planes).
    Only a face's plane: a pull snapped to some stray point stays projected
    onto the working plane. }
  if not OnPlane(B, FP1, N) then
    for F := 0 to FD.Doc.Live - 1 do
    begin
      if (FD.Doc[F].Kind <> ekFace) or (Length(FD.Doc[F].Poly) < 3) then Continue;
      FN := Norm3(FD.Doc.FaceNormal(F));
      if OnPlane(FP1, FD.Doc[F].Poly[0], FN) and OnPlane(FP2, FD.Doc[F].Poly[0], FN) and
         OnPlane(B, FD.Doc[F].Poly[0], FN) then
      begin
        if Abs(FN.Z) > 0.999 then Pl := plXY
        else if Abs(FN.Y) > 0.999 then Pl := plXZ
        else if Abs(FN.X) > 0.999 then Pl := plYZ
        else
        begin
          SetFreePlane(FP1, FN);
          Pl := plFree;
        end;
        Break;
      end;
    end;
  PlaneCoords(Pl, FP1, U1, V1);
  PlaneCoords(Pl, FP2, U2, V2);
  PlaneCoords(Pl, B, UC, VC);
  Ln := Sqrt(Sqr(U2 - U1) + Sqr(V2 - V1));
  if Ln < 1E-9 then Exit;
  { the bulge is how far the middle is pulled off the chord }
  NU := -(V2 - V1) / Ln;
  NV := (U2 - U1) / Ln;
  Bulge := (UC - (U1 + U2) / 2) * NU + (VC - (V1 + V2) / 2) * NV;
  { with Alt's lock the ends and the edge set the bulge, not the cursor; a
    typed length still wins }
  if FArcTanLock and TangentBulge(Pl, L) then Bulge := L;
  if (FInput <> '') and ParseLen(FInput, FD.Units, L) then
    Bulge := Sign(IfThen(Bulge = 0, 1, Bulge)) * L;
  if Abs(Bulge) < 1E-9 then Bulge := Ln / 8;
  Result := ArcFromChord(FP1, FP2, Bulge, Pl, C, R, A0, Sweep);
end;

{ The selection drawn where it would land, plus the line back to the grab. }
procedure TMainForm.PaintMoveGhost(C: TCanvas);
var
  I, K: Integer;
  D: TP3;
  Hi: TPointFArray;
  Lo, Hi3: TP3;
  Crate: array[0..7] of TP3;
  CS: array[0..7] of TPointF;
  PA, PB, SA, SB: TPointF;
  Lean: TP3Array;
begin
  if (FTool <> ptMove) or (FStage <> 1) then Exit;
  D := MoveDelta;

  { What comes along: corners where moving corners sit move too, so joined
    edges stretch.  Drawn first and thin, so the moved thing still reads as
    the moved thing. }
  if not (FMoveRigid or FMoveCopy or FDetachMove) and (Length(FMoveVerts) > 0) then
  begin
    FD.Doc.StretchPreview(FMoveVerts, D, FSel, Lean);
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
    C.Pen.Color := PixToColor(Pix(150, 185, 245));
    I := 0;
    while I + 1 <= High(Lean) do
    begin
      SA := ScreenOf(Lean[I]);
      SB := ScreenOf(Lean[I + 1]);
      C.MoveTo(Round(SA.X), Round(SA.Y));
      C.LineTo(Round(SB.X), Round(SB.Y));
      Inc(I, 2);
    end;
  end;

  C.Pen.Style := psSolid;
  C.Pen.Width := Max(2, Round(2 * FUIScale));
  if FMoveCopy then C.Pen.Color := PixToColor(Pix(60, 180, 110))
  else if FDetachMove then C.Pen.Color := PixToColor(Pix(235, 150, 40))
  else C.Pen.Color := PixToColor(Pix(70, 130, 240));
  { the projection is affine, so one world offset is one screen offset }
  PA := ScreenOf(P3(D.X, D.Y, D.Z));
  PB := ScreenOf(P3(0, 0, 0));
  for I := 0 to High(FSel) do
  begin
    Hi := FD.Doc.Outline(Proj, FSel[I]);
    if Length(Hi) < 2 then Continue;
    C.MoveTo(Round(Hi[0].X + PA.X - PB.X), Round(Hi[0].Y + PA.Y - PB.Y));
    for K := 1 to High(Hi) do
      C.LineTo(Round(Hi[K].X + PA.X - PB.X), Round(Hi[K].Y + PA.Y - PB.Y));
  end;
  { A built part being placed comes in its crate: its box, the floor's
    diagonals, IN, OUT and TOP, so it is set down the right way round.
    Drawn only. }
  if FMoveRigid and (Length(FMoveVerts) > 0) then
  begin
    Lo := FMoveVerts[0];
    Hi3 := FMoveVerts[0];
    for I := 1 to High(FMoveVerts) do
    begin
      Lo := P3(Min(Lo.X, FMoveVerts[I].X), Min(Lo.Y, FMoveVerts[I].Y), Min(Lo.Z, FMoveVerts[I].Z));
      Hi3 := P3(Max(Hi3.X, FMoveVerts[I].X), Max(Hi3.Y, FMoveVerts[I].Y), Max(Hi3.Z, FMoveVerts[I].Z));
    end;
    Lo := P3(Lo.X + D.X, Lo.Y + D.Y, Lo.Z + D.Z);
    Hi3 := P3(Hi3.X + D.X, Hi3.Y + D.Y, Hi3.Z + D.Z);
    Crate[0] := P3(Lo.X, Lo.Y, Lo.Z); Crate[1] := P3(Hi3.X, Lo.Y, Lo.Z);
    Crate[2] := P3(Hi3.X, Hi3.Y, Lo.Z); Crate[3] := P3(Lo.X, Hi3.Y, Lo.Z);
    for K := 0 to 3 do Crate[K + 4] := P3(Crate[K].X, Crate[K].Y, Hi3.Z);
    for K := 0 to 7 do CS[K] := ScreenOf(Crate[K]);
    C.Pen.Style := psDash;
    C.Pen.Width := 1;
    C.Pen.Color := PixToColor(Pix(150, 160, 150));
    for K := 0 to 3 do
    begin
      C.MoveTo(Round(CS[K].X), Round(CS[K].Y)); C.LineTo(Round(CS[(K + 1) mod 4].X), Round(CS[(K + 1) mod 4].Y));
      C.MoveTo(Round(CS[K + 4].X), Round(CS[K + 4].Y)); C.LineTo(Round(CS[(K + 1) mod 4 + 4].X), Round(CS[(K + 1) mod 4 + 4].Y));
      C.MoveTo(Round(CS[K].X), Round(CS[K].Y)); C.LineTo(Round(CS[K + 4].X), Round(CS[K + 4].Y));
    end;
    C.MoveTo(Round(CS[0].X), Round(CS[0].Y)); C.LineTo(Round(CS[2].X), Round(CS[2].Y));
    C.MoveTo(Round(CS[1].X), Round(CS[1].Y)); C.LineTo(Round(CS[3].X), Round(CS[3].Y));
    C.Pen.Style := psSolid;
    UIFont(C, 10, True, Pix(80, 110, 80));
    C.Brush.Style := bsClear;
    C.TextOut(Round((CS[0].X + CS[5].X) / 2) - C.TextWidth('IN') div 2, Round((CS[0].Y + CS[5].Y) / 2) - 7, 'IN');
    C.TextOut(Round((CS[3].X + CS[6].X) / 2) - C.TextWidth('OUT') div 2, Round((CS[3].Y + CS[6].Y) / 2) - 7, 'OUT');
    C.TextOut(Round((CS[4].X + CS[6].X) / 2) - C.TextWidth('TOP') div 2, Round((CS[4].Y + CS[6].Y) / 2) - 7, 'TOP');
  end;
  C.Pen.Width := 1;

  { the travel line, in the axis color when one is locked }
  PA := ScreenOf(FP1);
  PB := ScreenOf(P3(FP1.X + D.X, FP1.Y + D.Y, FP1.Z + D.Z));
  C.Pen.Style := psDash;
  { the lock is a direction code, two per axis; the color is per axis }
  if FDirLock >= 0 then
    C.Pen.Color := PixToColor(AxisPix(FDirLock div 2))
  else
    C.Pen.Color := PixToColor(Theme.Accent);
  C.MoveTo(Round(PA.X), Round(PA.Y));
  C.LineTo(Round(PB.X), Round(PB.Y));
  C.Pen.Style := psSolid;
end;

{ The arm the angle is measured from: the reference click, else the plane's
  first axis so a typed angle means something before the second click. }
function TMainForm.RotRefDir: TP3;
var
  AU, AV, D: TP3;
  L: Double;
begin
  AxesFromNormal(FRotAxis, AU, AV);
  if FStage < 2 then Exit(AU);
  D := P3(FRotRef.X - FP1.X, FRotRef.Y - FP1.Y, FRotRef.Z - FP1.Z);
  { flattened into the plane, since the click may have been off it }
  L := Dot3(D, FRotAxis);
  D := P3(D.X - FRotAxis.X * L, D.Y - FRotAxis.Y * L, D.Z - FRotAxis.Z * L);
  if Dist(D, P3(0, 0, 0)) < 1E-9 then Exit(AU);
  Result := Norm3(D);
end;

{ How far round, in radians, right-handed about the axis.  Typed wins, taking
  its direction from the swing (like a typed length on a move). }
function TMainForm.RotAngle: Double;
var
  Ref, D: TP3;
  L, Deg, Snap: Double;
begin
  Ref := RotRefDir;
  D := P3(FCur.X - FP1.X, FCur.Y - FP1.Y, FCur.Z - FP1.Z);
  L := Dot3(D, FRotAxis);
  D := P3(D.X - FRotAxis.X * L, D.Y - FRotAxis.Y * L, D.Z - FRotAxis.Z * L);
  if (FStage < 2) or (Dist(D, P3(0, 0, 0)) < 1E-9) then
    Result := 0
  else
    Result := ArcTan2(Dot3(Cross3(Ref, D), FRotAxis), Dot3(Ref, D));
  if ParseAngle(Trim(FInput), Deg) then
  begin
    if Result < 0 then Deg := -Deg;
    Exit(DegToRad(Deg));
  end;
  { near a multiple of 15 degrees, that is what was meant }
  Snap := DegToRad(15) * Round(Result / DegToRad(15));
  if Abs(Result - Snap) < DegToRad(2.5) then Result := Snap;
end;

{ The protractor: a circle in the plane ticked every 15 degrees, the two arms,
  and the selection where it would land. }
procedure TMainForm.PaintRotateGhost(C: TCanvas);
var
  I, K: Integer;
  AU, AV, P, Q, Ref: TP3;
  Rw, Ang, A: Double;
  PA, PB: TPointF;
  W: TP3Array;
  Col: TColor;

  function OnCircle(Th, Rad: Double): TP3;
  begin
    Result := P3(FP1.X + (AU.X * Cos(Th) + AV.X * Sin(Th)) * Rad,
                 FP1.Y + (AU.Y * Cos(Th) + AV.Y * Sin(Th)) * Rad,
                 FP1.Z + (AU.Z * Cos(Th) + AV.Z * Sin(Th)) * Rad);
  end;

  procedure Seg(const A, B: TP3);
  begin
    PA := ScreenOf(A);
    PB := ScreenOf(B);
    C.MoveTo(Round(PA.X), Round(PA.Y));
    C.LineTo(Round(PB.X), Round(PB.Y));
  end;

begin
  if FStage < 1 then Exit;
  if FRotAxisIx >= 0 then Col := PixToColor(AxisPix(FRotAxisIx div 2))
  else Col := PixToColor(Pix(200, 60, 200));
  AxesFromNormal(FRotAxis, AU, AV);
  Ref := RotRefDir;
  Ang := RotAngle;

  { the dial: as big as the reference arm, never smaller than a thumb }
  Rw := 60 * FUIScale / Proj.Ppu;
  if FStage >= 2 then Rw := Max(Rw, Dist(FRotRef, FP1));
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.Pen.Color := Col;
  for K := 0 to 71 do
    Seg(OnCircle(K * Pi / 36, Rw), OnCircle((K + 1) * Pi / 36, Rw));
  { ticks are measured from the reference arm, so the 15s read as 15s }
  A := ArcTan2(Dot3(Ref, AV), Dot3(Ref, AU));
  for K := 0 to 23 do
    if K mod 6 = 0 then Seg(OnCircle(A + K * Pi / 12, Rw * 0.82), OnCircle(A + K * Pi / 12, Rw))
    else Seg(OnCircle(A + K * Pi / 12, Rw * 0.91), OnCircle(A + K * Pi / 12, Rw));

  C.Pen.Width := Max(2, Round(2 * FUIScale));
  { the reference arm, dashed }
  C.Pen.Style := psDash;
  P := P3(FP1.X + Ref.X * Rw, FP1.Y + Ref.Y * Rw, FP1.Z + Ref.Z * Rw);
  Seg(FP1, P);
  { the swung arm, solid, and the arc between them }
  if FStage >= 2 then
  begin
    C.Pen.Style := psSolid;
    Q := RotV(Ref, FRotAxis, Ang);
    Seg(FP1, P3(FP1.X + Q.X * Rw, FP1.Y + Q.Y * Rw, FP1.Z + Q.Z * Rw));
    K := Max(2, Round(Abs(Ang) / (Pi / 36)));
    for I := 0 to K - 1 do
      Seg(OnCircle(A + Ang * I / K, Rw * 0.55), OnCircle(A + Ang * (I + 1) / K, Rw * 0.55));
  end;

  { the selection, where it would come to rest }
  if (FTool = ptRotate) and (FStage >= 2) and (Abs(Ang) > 1E-9) then
  begin
    C.Pen.Style := psSolid;
    if FMoveCopy then C.Pen.Color := PixToColor(Pix(60, 180, 110))
    else if FDetachMove then C.Pen.Color := PixToColor(Pix(235, 150, 40))
    else C.Pen.Color := PixToColor(Pix(70, 130, 240));
    for I := 0 to High(FSel) do
    begin
      W := FD.Doc.OutlineWorld(FSel[I]);
      if Length(W) < 2 then Continue;
      PA := ScreenOf(RotP(W[0], FP1, FRotAxis, Ang));
      C.MoveTo(Round(PA.X), Round(PA.Y));
      for K := 1 to High(W) do
      begin
        PB := ScreenOf(RotP(W[K], FP1, FRotAxis, Ang));
        C.LineTo(Round(PB.X), Round(PB.Y));
      end;
    end;
  end;
  C.Pen.Width := 1;
  C.Pen.Style := psSolid;
end;

function TMainForm.IsDoomed(I: Integer): Boolean;
var
  K: Integer;
begin
  Result := True;
  for K := 0 to High(FDoomed) do
    if FDoomed[K] = I then Exit;
  Result := False;
end;

{ What the right button is asking about.  Edges reach only 4 px here, not 9
  as in PickAt: on a cylinder every point is within 9 px of an edge, so its
  faces could not be reached from the menu. }
function TMainForm.PickForMenu(SX, SY: Integer): Integer;
var
  E, F: Integer;
begin
  Result := FD.Doc.HitNote(SX, SY);
  if Result >= 0 then Exit;
  E := FD.Doc.HitEdge(Proj, SX, SY, 4 * FUIScale, HIT_NO_GUIDES);
  if E >= 0 then Exit(E);
  F := FD.Doc.HitFace(Proj, SX, SY);
  if F >= 0 then Exit(F);
  Result := FD.Doc.HitTest(Proj, SX, SY, 9 * FUIScale, False);
end;

{ --- groups ---
  SketchUp's rules: a click takes the whole
  group; double-click opens it and the rest fades and cannot be picked; a
  click on nothing or Esc leaves; a locked group can be picked and snapped
  to but not moved, edited or exploded. }

{ every distinct group in the selection, by the entity you would click }
function TMainForm.SelectedGroups: TIntArrayW;
var
  K, T, J, N: Integer;
  Known: Boolean;
begin
  Result := nil;
  N := 0;
  for K := 0 to High(FSel) do
  begin
    T := FD.Doc.TopPartIn(FSel[K]);
    if T <= 0 then Continue;
    Known := False;
    for J := 0 to N - 1 do
      if Result[J] = T then Known := True;
    if Known then Continue;
    if N >= Length(Result) then SetLength(Result, Max(4, N * 2));
    Result[N] := T;
    Inc(N);
  end;
  SetLength(Result, N);
end;

{ the one group the selection is, or 0 for several, loose things, or a mix }
function TMainForm.SoleGroup: Integer;
var
  Gs: TIntArrayW;
  K: Integer;
begin
  Result := 0;
  Gs := SelectedGroups;
  if Length(Gs) <> 1 then Exit;
  for K := 0 to High(FSel) do
    if FD.Doc.TopPartIn(FSel[K]) <> Gs[0] then Exit;
  Result := Gs[0];
end;

procedure TMainForm.MakeGroup;
var
  Id, K, T, I, J, First: Integer;
  Sel: TIntArrayW;
begin
  if Length(FSel) = 0 then
  begin
    FCmdMsg := 'Pick something first - a group is made of what is selected.';
    InvalidateStatus;
    Exit;
  end;
  for K := 0 to High(FSel) do
  begin
    T := FD.Doc.TopPartIn(FSel[K]);
    if (T > 0) and FD.Doc.PartLockedUp(T) then
    begin
      FCmdMsg := Format('"%s" is locked - unlock it before grouping it with anything.',
        [FD.Doc.PartName(T)]);
      InvalidateStatus;
      Exit;
    end;
  end;
  PushUndo;
  SetLength(Sel, Length(FSel));
  for K := 0 to High(FSel) do Sel[K] := FSel[K];
  Id := FD.Doc.NewPart('', FD.Doc.Context);
  First := -1;
  for K := 0 to High(Sel) do
  begin
    I := Sel[K];
    if (I < 0) or (I >= FD.Doc.Live) or (FD.Doc[I].Kind = ekPart) then Continue;
    T := FD.Doc.TopPartIn(I);
    { a picked group goes in whole and stays a group inside the new one }
    if T > 0 then FD.Doc.SetPartParent(T, Id)
    else if T = 0 then
    begin
      FD.Doc.SetPart(I, Id);
      { a face is rebuilt from its edges, so its edges come into the group
        too (as SketchUp's Make Group does), or the face is found loose again
        and the group left empty }
      if FD.Doc[I].Kind = ekFace then
        for J := 0 to FD.Doc.Live - 1 do
          if (FD.Doc[J].Kind in [ekLine, ekArc]) and (FD.Doc[J].Part = FD.Doc.Context) and
             EntHasPoint(I, FD.Doc[J].A) and EntHasPoint(I, FD.Doc[J].B) then
            FD.Doc.SetPart(J, Id);
    end;
    if First < 0 then First := I;
  end;
  SetLength(FSel, 0);
  if First >= 0 then SelectAdd(First);
  { rebuild the faces group by group, which separates them from what was
    joined outside }
  RebuildFlatFaces;
  RenderInk;
  RecomposeAll;
  InfoChanged;
  FCmdMsg := Format('Grouped as "%s".  Double-click it to work inside it; ' +
    '/name calls it something.', [FD.Doc.PartName(Id)]);
  InvalidateStatus;
  pbScreen.Invalidate;
end;

procedure TMainForm.ExplodeGroups;
var
  Gs: TIntArrayW;
  Doom: array of Boolean;
  K, G, Up, I, N: Integer;
begin
  Gs := SelectedGroups;
  if Length(Gs) = 0 then
  begin
    FCmdMsg := 'Pick a group first.';
    InvalidateStatus;
    Exit;
  end;
  for K := 0 to High(Gs) do
    if FD.Doc.PartLockedUp(Gs[K]) then
    begin
      FCmdMsg := Format('"%s" is locked - unlock it first.', [FD.Doc.PartName(Gs[K])]);
      InvalidateStatus;
      Exit;
    end;
  PushUndo;
  SetLength(Doom, FD.Doc.Live);
  for I := 0 to High(Doom) do Doom[I] := False;
  N := 0;
  for K := 0 to High(Gs) do
  begin
    G := Gs[K];
    Up := FD.Doc.PartParent(G);
    for I := 0 to FD.Doc.Live - 1 do
    begin
      if (FD.Doc[I].Kind = ekPart) and (FD.Doc[I].Grp = G) then Doom[I] := True
      else if FD.Doc[I].Part = G then
      begin
        { members go up a level; a group inside stays a group }
        if FD.Doc[I].Kind = ekPart then FD.Doc.SetPartParent(FD.Doc[I].Grp, Up)
        else FD.Doc.SetPart(I, Up);
        Inc(N);
      end;
    end;
  end;
  FD.Doc.DeleteMarked(Doom);
  SetLength(FSel, 0);
  RebuildFlatFaces;
  RenderInk;
  RecomposeAll;
  InfoChanged;
  if Length(Gs) = 1 then
    FCmdMsg := Format('Group taken apart - %d things are loose again.', [N])
  else
    FCmdMsg := Format('%d groups taken apart.', [Length(Gs)]);
  InvalidateStatus;
  pbScreen.Invalidate;
end;

procedure TMainForm.OpenGroup(Id: Integer);
begin
  if Id <= 0 then Exit;
  if FD.Doc.PartLockedUp(Id) then
  begin
    FCmdMsg := Format('"%s" is locked - unlock it to work inside it.', [FD.Doc.PartName(Id)]);
    InvalidateStatus;
    Exit;
  end;
  SetLength(FSel, 0);
  FD.Doc.Context := Id;
  FShotOK := False;
  RenderInk;
  RecomposeAll;
  InfoChanged;
  FCmdMsg := Format('Inside "%s".  What you draw now belongs to it; ' +
    'Esc or a click on nothing leaves it.', [FD.Doc.PartName(Id)]);
  InvalidateStatus;
  pbScreen.Invalidate;
end;

procedure TMainForm.CloseGroup;
var
  Was: Integer;
begin
  if FD.Doc.Context = 0 then Exit;
  Was := FD.Doc.Context;
  SetLength(FSel, 0);
  FD.Doc.Context := FD.Doc.PartParent(Was);
  FShotOK := False;
  RenderInk;
  RecomposeAll;
  InfoChanged;
  if FD.Doc.Context = 0 then FCmdMsg := Format('Left "%s".', [FD.Doc.PartName(Was)])
  else FCmdMsg := Format('Left "%s" - inside "%s" now.',
    [FD.Doc.PartName(Was), FD.Doc.PartName(FD.Doc.Context)]);
  InvalidateStatus;
  pbScreen.Invalidate;
end;

procedure TMainForm.LockGroups(Locked: Boolean);
var
  Gs: TIntArrayW;
  K: Integer;
begin
  Gs := SelectedGroups;
  if Length(Gs) = 0 then
  begin
    FCmdMsg := 'Pick a group first.';
    InvalidateStatus;
    Exit;
  end;
  PushUndo;
  for K := 0 to High(Gs) do FD.Doc.SetPartLocked(Gs[K], Locked);
  InfoChanged;
  if Locked then
    FCmdMsg := 'Locked.  It can still be snapped to, and picked - but not moved, ' +
      'changed or opened until it is unlocked.'
  else
    FCmdMsg := 'Unlocked.';
  InvalidateStatus;
  pbScreen.Invalidate;
end;

{ Put groups away or bring them back.  Named: every group whose name
  contains it ("/hide labels").  Unnamed: hide takes the picked groups, show
  brings back everything.  Nothing is lost; only drawing, picking and
  snapping change. }
procedure TMainForm.HideGroups(PutAway: Boolean; const Named: string);
var
  Gs: TIntArrayW;
  I, K, N: Integer;
  Want: string;
begin
  SetLength(Gs, 0);
  Want := LowerCase(Trim(Named));
  for I := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[I].Kind = ekPart) and (FD.Doc[I].Hidden <> PutAway) and
       (((Want <> '') and (Pos(Want, LowerCase(FD.Doc.PartName(FD.Doc[I].Grp))) > 0)) or
        ((Want = '') and not PutAway)) then
    begin
      SetLength(Gs, Length(Gs) + 1); Gs[High(Gs)] := FD.Doc[I].Grp;
    end;
  if (Want = '') and PutAway then Gs := SelectedGroups;
  if Length(Gs) = 0 then
  begin
    if Want <> '' then
      FCmdMsg := Format('No group %s has "%s" in its name.', [IfThen(PutAway, 'showing', 'put away'), Trim(Named)])
    else if PutAway then FCmdMsg := 'Pick a group first - or /hide labels puts away every group named so.'
    else FCmdMsg := 'Nothing is put away.';
    InvalidateStatus;
    Exit;
  end;
  PushUndo;
  N := 0;
  for K := 0 to High(Gs) do
    if FD.Doc.PartHidden(Gs[K]) <> PutAway then
    begin
      FD.Doc.SetPartHidden(Gs[K], PutAway);
      Inc(N);
    end;
  { what is put away cannot stay picked }
  if PutAway then SetLength(FSel, 0);
  RenderInk;
  RecomposeAll;
  InfoChanged;
  if PutAway then
    FCmdMsg := Format('%d group%s put away - /show brings %s back.', [N, IfThen(N = 1, '', 's'),
      IfThen(N = 1, 'it', 'them')])
  else
    FCmdMsg := Format('%d group%s brought back.', [N, IfThen(N = 1, '', 's')]);
  InvalidateStatus;
  pbScreen.Invalidate;
end;

procedure TMainForm.RenameGroup(const NewName: string);
var
  G: Integer;
begin
  G := SoleGroup;
  if G = 0 then
  begin
    FCmdMsg := 'Pick one group, then /name what to call it.';
    InvalidateStatus;
    Exit;
  end;
  if Trim(NewName) = '' then
  begin
    FCmdMsg := Format('It is called "%s".  /name Left knob calls it that.', [FD.Doc.PartName(G)]);
    InvalidateStatus;
    Exit;
  end;
  PushUndo;
  FD.Doc.SetPartName(G, Trim(NewName));
  InfoChanged;
  FCmdMsg := Format('Called "%s".', [FD.Doc.PartName(G)]);
  InvalidateStatus;
end;

{ What a move or turn takes hold of.  Whole groups go rigidly and do not
  stretch loose things touching them; loose picked things move with their
  corners as usual.  A locked group stays put. }
function TMainForm.SplitMoveSelection: Boolean;
var
  Gs, M, Loose: TIntArrayW;
  K, J, I, N, NL, Skipped: Integer;
begin
  Result := True;
  SetLength(FMoveGroupEnts, 0);
  N := 0;
  Skipped := 0;
  Gs := SelectedGroups;
  for K := 0 to High(Gs) do
  begin
    if FD.Doc.PartLockedUp(Gs[K]) then begin Inc(Skipped); Continue; end;
    M := FD.Doc.PartMembers(Gs[K], True);
    SetLength(FMoveGroupEnts, N + Length(M));
    for J := 0 to High(M) do FMoveGroupEnts[N + J] := M[J];
    N := N + Length(M);
  end;
  Loose := nil;
  NL := 0;
  for K := 0 to High(FSel) do
  begin
    I := FSel[K];
    if (I < 0) or (I >= FD.Doc.Live) or (FD.Doc[I].Kind = ekPart) then Continue;
    if FD.Doc.TopPartIn(I) <> 0 then Continue;
    if NL >= Length(Loose) then SetLength(Loose, Max(16, NL * 2));
    Loose[NL] := I;
    Inc(NL);
  end;
  SetLength(Loose, NL);
  FD.Doc.VertsOf(Loose, FMoveVerts);
  { nothing movable at all: say so rather than report a move of nothing }
  if (Skipped > 0) and (N = 0) and (NL = 0) then
  begin
    FCmdMsg := 'That group is locked - unlock it to move it.';
    Result := False;
  end
  else if Skipped > 0 then
    FCmdMsg := 'A locked group stays where it is - unlock it to move it.';
end;

{ A face a tool may act on: one in the open context.  As in SketchUp, a
  closed group's face is not pushed from outside.  Drawing ON it goes
  through FaceUnder, which is not filtered. }
function TMainForm.InContextFace(F: Integer): Integer;
begin
  Result := F;
  if (F >= 0) and (FD.Doc.TopPartIn(F) <> 0) then Result := -1;
end;

{ The box round a group, as SketchUp draws one: the twelve edges of its
  bounds.  Shift offsets it, for a ghost. }
procedure TMainForm.PaintPartBox(C: TCanvas; Id: Integer; const Col: TPix;
  Dashed: Boolean; const Shift: TP3);
const
  E: array[0..11, 0..1] of Integer = ((0, 1), (1, 2), (2, 3), (3, 0),
    (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7));
var
  Lo, Hi: TP3;
  P: array[0..7] of TPointF;
  K: Integer;
begin
  if not FD.Doc.PartBounds(Id, Lo, Hi) then Exit;
  Lo := P3(Lo.X + Shift.X, Lo.Y + Shift.Y, Lo.Z + Shift.Z);
  Hi := P3(Hi.X + Shift.X, Hi.Y + Shift.Y, Hi.Z + Shift.Z);
  P[0] := ScreenOf(P3(Lo.X, Lo.Y, Lo.Z)); P[1] := ScreenOf(P3(Hi.X, Lo.Y, Lo.Z));
  P[2] := ScreenOf(P3(Hi.X, Hi.Y, Lo.Z)); P[3] := ScreenOf(P3(Lo.X, Hi.Y, Lo.Z));
  P[4] := ScreenOf(P3(Lo.X, Lo.Y, Hi.Z)); P[5] := ScreenOf(P3(Hi.X, Lo.Y, Hi.Z));
  P[6] := ScreenOf(P3(Hi.X, Hi.Y, Hi.Z)); P[7] := ScreenOf(P3(Lo.X, Hi.Y, Hi.Z));
  C.Brush.Style := bsClear;
  if Dashed then C.Pen.Style := psDash else C.Pen.Style := psSolid;
  C.Pen.Width := Max(1, Round(FUIScale));
  C.Pen.Color := PixToColor(Col);
  for K := 0 to 11 do
  begin
    C.MoveTo(Round(P[E[K, 0]].X), Round(P[E[K, 0]].Y));
    C.LineTo(Round(P[E[K, 1]].X), Round(P[E[K, 1]].Y));
  end;
  C.Pen.Style := psSolid;
end;

{ What move and rotate take hold of when nothing is picked: a note, an
  edge, a face, anything else - never a guide (a guide is laid anew, not
  moved). }
function TMainForm.PickToGrab(SX, SY: Integer): Integer;
begin
  Result := FD.Doc.HitNote(SX, SY);
  if Result < 0 then
    Result := FD.Doc.HitEdge(Proj, SX, SY, 9 * FUIScale, HIT_NO_GUIDES);
  if Result < 0 then Result := FD.Doc.HitFace(Proj, SX, SY);
  if Result < 0 then Result := FD.Doc.HitTest(Proj, SX, SY, 9 * FUIScale, False);
  if (Result >= 0) and (FD.Doc.TopPartIn(Result) < 0) then Result := -1;
end;

{ What a click takes, with the group rules on top.  Inside an open group the
  rest of the drawing cannot be picked; that click closes the group (see
  FinishSelect). }
function TMainForm.PickAt(SX, SY: Integer): Integer;
begin
  Result := PickAtRaw(SX, SY);
  if (Result >= 0) and (FD.Doc.TopPartIn(Result) < 0) then Result := -1;
end;

function TMainForm.PickAtRaw(SX, SY: Integer): Integer;
begin
  { a note is drawn on top, so it is picked first }
  Result := FD.Doc.HitNote(SX, SY);
  if Result >= 0 then Exit;
  { Then an edge, then the face behind, then anything else, stopping at the
    first answer (HitFace is the costly one).  Never a guide: guides belong
    to the measure tool, and a guide point usually sits on a line. }
  Result := FD.Doc.HitEdge(Proj, SX, SY, 9 * FUIScale, HIT_NO_GUIDES);
  if Result >= 0 then Exit;
  Result := FD.Doc.HitFace(Proj, SX, SY);
  if Result >= 0 then Exit;
  Result := FD.Doc.HitTest(Proj, SX, SY, 9 * FUIScale, False);
end;

{ add whatever is under the cursor to the eraser's gathered list }
procedure TMainForm.DoomAt(SX, SY: Integer);
var
  I, T, K: Integer;
  M: TIntArrayW;
begin
  { softening is about edges only (a face has no crease), so a soften stroke
    only looks for edges }
  if FEraseMode <> 0 then
  begin
    I := FD.Doc.HitEdge(Proj, SX, SY, 9 * FUIScale);
    if I < 0 then Exit;
    if IsDoomed(I) then Exit;
    if FD.Doc.TopPartIn(I) <> 0 then Exit;    { softening stays in the open group }
    if not (FD.Doc[I].Kind in [ekLine, ekArc]) then Exit;
    SetLength(FDoomed, Length(FDoomed) + 1);
    FDoomed[High(FDoomed)] := I;
    FScreenDirty := True;
    Exit;
  end;
  { The eraser takes edges, and faces only by taking their edges, as in
    SketchUp ("faces are erased when you erase their bounding edges").  A
    click on a bare face says so and points to right-click or Delete. }
  { the note first: it is drawn on top, so it is what the cursor is on }
  I := FD.Doc.HitNote(SX, SY);
  { never a guide: the eraser leaves them to the measure tool }
  if I < 0 then I := FD.Doc.HitEdge(Proj, SX, SY, 9 * FUIScale, HIT_NO_GUIDES);
  if I < 0 then I := FD.Doc.HitTest(Proj, SX, SY, 9 * FUIScale, False);
  if I < 0 then
  begin
    if FD.Doc.HitFace(Proj, SX, SY) >= 0 then
      FCmdMsg := 'The eraser takes edges - rub out the edges round a face ' +
        'and the face goes with them.  For the face on its own: right-click ' +
        'it, or pick it and press Delete.';
    Exit;
  end;
  { a group is erased whole, as SketchUp's eraser takes an object; a locked
    one not at all, and nothing outside the open group }
  T := FD.Doc.TopPartIn(I);
  if T < 0 then Exit;
  if T > 0 then
  begin
    if FD.Doc.PartLockedUp(T) then
    begin
      FCmdMsg := Format('"%s" is locked.', [FD.Doc.PartName(T)]);
      Exit;
    end;
    M := FD.Doc.PartMembers(T, True);
    for K := 0 to High(M) do
      if not IsDoomed(M[K]) then
      begin
        SetLength(FDoomed, Length(FDoomed) + 1);
        FDoomed[High(FDoomed)] := M[K];
      end;
    FScreenDirty := True;
    Exit;
  end;
  if IsDoomed(I) then Exit;
  SetLength(FDoomed, Length(FDoomed) + 1);
  FDoomed[High(FDoomed)] := I;
  FScreenDirty := True;
end;

{ 0 erases, 1 softens (Ctrl), 2 unsoftens (Ctrl+Shift) }
function TMainForm.EraseModeOf(Shift: TShiftState): Integer;
begin
  if not (ssCtrl in Shift) then Result := 0
  else if ssShift in Shift then Result := 2
  else Result := 1;
end;

{ Soften what the eraser gathered instead of erasing it.  Only lines and
  arcs; faces under the stroke are skipped rather than spoiling it. }
procedure TMainForm.SoftenDoomed(On_: Boolean);
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to High(FDoomed) do
    if (FDoomed[I] >= 0) and (FDoomed[I] < FD.Doc.Live) and
       (FD.Doc[FDoomed[I]].Kind in [ekLine, ekArc]) and
       (FD.Doc[FDoomed[I]].Soft <> On_) then
    begin
      if N = 0 then PushUndo;
      FD.Doc.SetSoft(FDoomed[I], On_);
      Inc(N);
    end;
  SetLength(FDoomed, 0);
  if N = 0 then
    FCmdMsg := specialize IfThen<string>(On_,
      'Nothing there to soften.', 'Nothing there was softened.')
  else
  begin
    FCmdMsg := Format('%d %s %s.', [N,
      specialize IfThen<string>(N = 1, 'edge', 'edges'),
      specialize IfThen<string>(On_, 'softened', 'brought back')]);
    RenderInk;
    RecomposeAll;
  end;
  FScreenDirty := True;
end;

{ Delete everything gathered, then let the face rebuild join or drop areas. }
procedure TMainForm.BurnDoomed;
var
  I, J, T, N: Integer;
  EA, EB: array of TP3;
  Kinds: array of TEntKind;
  Held: TIntArrayW;
  Gone: array of Boolean;
begin
  N := Length(FDoomed);
  if N = 0 then Exit;
  for I := 0 to N - 2 do
    for J := 0 to N - 2 - I do
      if FDoomed[J] < FDoomed[J + 1] then
      begin
        T := FDoomed[J];
        FDoomed[J] := FDoomed[J + 1];
        FDoomed[J + 1] := T;
      end;

  SetLength(EA, N);
  SetLength(EB, N);
  SetLength(Kinds, N);
  for I := 0 to N - 1 do
  begin
    EA[I] := FD.Doc[FDoomed[I]].A;
    EB[I] := FD.Doc[FDoomed[I]].B;
    Kinds[I] := FD.Doc[FDoomed[I]].Kind;
  end;

  PushUndo;
  J := FaceCount;
  { The faces these edges held up go too.  Loose faces are rebuilt anyway,
    but a solid's faces are kept as made, so they must be removed here or a
    box keeps its sides with an edge missing. }
  FD.Doc.FacesOnEdges(FDoomed, Held);
  SetLength(Gone, FD.Doc.Live);
  for I := 0 to High(Gone) do Gone[I] := False;
  for I := 0 to N - 1 do Gone[FDoomed[I]] := True;
  for I := 0 to High(Held) do Gone[Held[I]] := True;
  { and a guide line takes the point laid with it }
  FD.Doc.PointsOnGuides(FDoomed, Held);
  for I := 0 to High(Held) do Gone[Held[I]] := True;
  FD.Doc.DeleteMarked(Gone);
  { faces joining where a line went, or vanishing because the outline no
    longer closes, both come out of rebuilding from what is left }
  J := J - RebuildFlatFaces;

  if N = 1 then FCmdMsg := 'Deleted.'
  else FCmdMsg := Format('Deleted %d things.', [N]);
  if J > 0 then
    FCmdMsg := FCmdMsg + Format('  %d face%s gone with them.',
      [J, IfThen(J = 1, '', 's')]);
  SetLength(FDoomed, 0);
  SelectNone;
  RenderInk;
  RecomposeAll;
end;

{ What the tape is set to leave, in words, said after a measurement and in
  the hint line so the mode never has to be remembered. }
function TMainForm.TapeDropSays: string;
begin
  case FTapeDrop of
    1: Result := 'a point where it landed - Ctrl for the dashed line too';
    2: Result := 'a guide across the run - Ctrl for the point too';
    3: Result := 'nothing left behind - Ctrl to leave a guide again';
  else
    Result := 'guide across the run, and a point where it landed - Ctrl changes it';
  end;
end;

{ What the tape leaves behind, chosen by the mode (as in SketchUp) rather
  than by what was under the first click.  A guide line runs parallel to the
  edge the measurement started on (a wall thickness, a row of hangers); from
  no edge it runs across the measured run. }
procedure TMainForm.LayGuide;
var
  D, E, Nm, AU, AV: TP3;
  Have: Boolean;
  Kind: TTapeGuide;
begin
  if Dist(FP1, FP2) < 1E-9 then Exit;
  PushUndo;

  { Default is both: the dashed line says where the offset is, the point
    where along it the measurement landed.  Ctrl cycles the choice (as in
    SketchUp), e.g. for a short mark that should not drag a line across the
    whole drawing. }
  if FTapeDrop = 3 then
  begin
    FCmdMsg := RunReading(FP1, FP2) + '   (nothing left behind)';
    Exit;
  end;

  { what it leaves depends on where it was pulled from (see TapeGuide in
    hsDrawing): off an edge, a line parallel to it; along an edge, a point
    only; anywhere else, a line across the run }
  PlaneAxes(FD.Plane, AU, AV);
  Nm := Cross3(AU, AV);
  Have := (FMeasEdge >= 0) and (FMeasEdge < FD.Doc.Live) and
          (FD.Doc[FMeasEdge].Kind = ekLine);
  if Have then
    E := P3(FD.Doc[FMeasEdge].B.X - FD.Doc[FMeasEdge].A.X,
            FD.Doc[FMeasEdge].B.Y - FD.Doc[FMeasEdge].A.Y,
            FD.Doc[FMeasEdge].B.Z - FD.Doc[FMeasEdge].A.Z)
  else
    E := P3(0, 0, 0);
  Kind := TapeGuide(Have, E, FP1, FP2, Nm, D);
  { at a corner the click may have found the other edge, so ask every edge
    through the start }
  if (Kind <> tgPointOnly) and FD.Doc.RunsAlongEdge(FP1, FP2) then
    Kind := tgPointOnly;

  { a line unless the run was along its starting edge, except in line-only
    mode }
  if (FTapeDrop <> 1) and ((Kind <> tgPointOnly) or (FTapeDrop = 2)) and
     (Sqr(D.X) + Sqr(D.Y) + Sqr(D.Z) > 1E-18) then
    FD.Doc.AddGuide(FP2, P3(FP2.X + D.X, FP2.Y + D.Y, FP2.Z + D.Z));
  if FTapeDrop <> 2 then FD.Doc.AddGuide(FP2, FP2);

  if (Kind = tgPointOnly) and (FTapeDrop <> 2) then
    FCmdMsg := FormatLen(Dist(FP1, FP2), FD.Units) +
      '   a point where it landed - measured along the edge, so no line with it'
  else if Kind = tgAlongEdge then
    FCmdMsg := FormatLen(Dist(FP1, FP2), FD.Units) +
      '   a guide parallel to the edge it came off  -  ' + TapeDropSays
  else
    FCmdMsg := FormatLen(Dist(FP1, FP2), FD.Units) + '   ' + TapeDropSays;
  RenderInk;
  RecomposeAll;
end;

{ Every drawn edge in group Part as plain segments for the region finder. }
function TMainForm.EdgeSegments(Part: Integer): TSegArray;
var
  I, K, N, Steps: Integer;
  A: TP3;
begin
  N := 0;
  SetLength(Result, 64);
  for I := 0 to FD.Doc.Live - 1 do
  begin
    { one group at a time (see Part in hsDrawing) }
    if FD.Doc[I].Part <> Part then Continue;
    { A solid's own edges go in too: the top of a wall is the fourth side of
      a roof slope drawn on a box.  A region that lands exactly on an
      existing solid face is dropped later as a duplicate. }
    case FD.Doc[I].Kind of
      ekLine:
        { a reference line (a dimension's, a radiant run) closes no face,
          as in hsDrawing's edge passes }
        if not FD.Doc[I].Dim then
        begin
          if N >= Length(Result) then SetLength(Result, N * 2);
          Result[N].A := FD.Doc[I].A;
          Result[N].B := FD.Doc[I].B;
          Inc(N);
        end;
      ekArc:
        begin
          A := ArcPoint(FD.Doc[I].C, FD.Doc[I].R, FD.Doc[I].A0, FD.Doc[I].Plane, FD.Doc[I].Nm);
          Steps := ArcSteps(FD.Doc[I]);
          for K := 1 to Steps do
          begin
            if N >= Length(Result) then SetLength(Result, N * 2);
            Result[N].A := A;
            A := ArcPoint(FD.Doc[I].C, FD.Doc[I].R,
              FD.Doc[I].A0 + FD.Doc[I].Sweep * K / Steps, FD.Doc[I].Plane, FD.Doc[I].Nm);
            Result[N].B := A;
            Inc(N);
          end;
        end;
    end;
  end;
  SetLength(Result, N);
end;

{ flat faces belonging to solids }
function TMainForm.SolidFaceCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[I].Kind = ekFace) and FD.Doc[I].Solid then Inc(Result);
end;

{ Whether the drawing has any face at all, solids included.  FaceCount
  leaves solids out; a drawing that is only a built duct still has faces. }
function TMainForm.AnyFace: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to FD.Doc.Live - 1 do
    if FD.Doc[I].Kind = ekFace then Exit(True);
end;

{ how many loose flat faces there are, for saying what an edit changed }
function TMainForm.FaceCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[I].Kind = ekFace) and not FD.Doc[I].Solid then Inc(Result);
end;

{ a flat area boiled down to something that can be matched next time }
function RegionSig(const R: TRegion): TRegionSig;
var
  K, N: Integer;
begin
  { one of the two normals, chosen the same way every time (see
    hsFaceFinder), so a loop wound the other way matches }
  Result.Nm := CanonicalNormal(R.Normal);
  N := Length(R.Outer);
  Result.Mid := P3(0, 0, 0);
  for K := 0 to N - 1 do
    Result.Mid := P3(Result.Mid.X + R.Outer[K].X, Result.Mid.Y + R.Outer[K].Y,
                     Result.Mid.Z + R.Outer[K].Z);
  if N > 0 then
    Result.Mid := P3(Result.Mid.X / N, Result.Mid.Y / N, Result.Mid.Z / N);
  Result.D := Dot3(Result.Mid, Result.Nm);
  Result.Area := Abs(LoopArea(R.Outer, R.Normal));
end;

function SameRegion(const A, B: TRegionSig): Boolean;
begin
  Result := (A.Part = B.Part) and (Abs(A.Nm.X - B.Nm.X) < 1E-6) and (Abs(A.Nm.Y - B.Nm.Y) < 1E-6) and
            (Abs(A.Nm.Z - B.Nm.Z) < 1E-6) and (Abs(A.D - B.D) < 1E-4) and
            (Abs(A.Area - B.Area) < 1E-3) and (Dist(A.Mid, B.Mid) < 1E-4);
end;

{ The flat areas as they stand, recorded as seen without acting on them.
  For a file that already carries its faces: nothing counts as newly closed,
  so no face is invented over what was saved or what was erased. }
procedure TMainForm.SeedRegions;
var
  R: TRegionArray;
  Parts: TIntArrayW;
  I, P, Base, CI: Integer;
begin
  SetLength(FD.Seen, 0);
  Parts := AllPartIds;
  for P := 0 to High(Parts) do
  begin
    { the slot first, on its own: taking the element and growing the array
      in one expression let the address be computed before the growth }
    CI := CacheFor(Parts[P]);
    R := BuildRegionsCached(EdgeSegments(Parts[P]), FRegionCaches[CI].Cache);
    Base := Length(FD.Seen);
    SetLength(FD.Seen, Base + Length(R));
    for I := 0 to High(R) do
    begin
      if ((I and 63) = 0) and (Length(R) > 500) then
        if not OnProgress('Working out the faces', I / Length(R)) then Break;
      FD.Seen[Base + I] := RegionSig(R[I]);
      FD.Seen[Base + I].Part := Parts[P];
    end;
  end;
end;

{ Every group's id, with 0 (the drawing itself) first.  Each is rebuilt on
  its own; that is what makes a group a group. }
function TMainForm.AllPartIds: TIntArrayW;
var
  I, N: Integer;
begin
  SetLength(Result, 1);
  Result[0] := 0;
  N := 1;
  for I := 0 to FD.Doc.Live - 1 do
    if FD.Doc[I].Kind = ekPart then
    begin
      if N >= Length(Result) then SetLength(Result, N * 2);
      Result[N] := FD.Doc[I].Grp;
      Inc(N);
    end;
  SetLength(Result, N);
end;

{ this group's region cache slot, made if it has none yet }
function TMainForm.CacheFor(Part: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FRegionCaches) do
    if FRegionCaches[I].Part = Part then Exit(I);
  SetLength(FRegionCaches, Length(FRegionCaches) + 1);
  Result := High(FRegionCaches);
  FRegionCaches[Result].Part := Part;
  FRegionCaches[Result].Cache.Keys := nil;
  FRegionCaches[Result].Cache.Sig := nil;
  FRegionCaches[Result].Cache.Found := nil;
end;

{ Work the loose faces out again from the edges: one question after every
  edit, what areas do these edges enclose, instead of a rule per situation.
  Solid faces are kept (a solid keeps its own topology).  A new face takes
  the color and paint of whichever old face its middle fell inside. }
function TMainForm.RebuildFlatFaces: Integer;
type
  TWas = record
    Mid: TP3;
    Poly: TP3Array;
    Holes: array of TP3Array;
    Nm: TP3;
    Ink: TColor;
    Part: Integer;
    { the paint carries across too, or a rebuild resets painted faces }
    Mat: TColor;
    MatSet: Boolean;
  end;
var
  R: TRegionArray;
  Was: array of TWas;
  WasHit: Integer;
  NWas, I, J, K, M, G, Made, DupAt: Integer;
  RegArea, FArea, PiecesArea: Double;
  FN: TP3;
  Pieces: array of Integer;
  Shares: Boolean;
  Mid, Other: TP3;
  Ink: TColor;
  Dup, HadFace, Known: Boolean;
  Sig: TRegionSig;
  HealGrp: Integer;
  SolidIx: TIntArrayW;
  SolidN, SolidP0, SolidMid, RMid: array of TP3;
  SolidRad: array of Double;
  RMidOK: array of Boolean;
  FE: TWorkEnt;
  FLo, FHi: TP3;
  SolidArea: array of Double;
  SI: Integer;
  LineIx, PlaneIx, RegionIx: TFPHashList;
  LineLists, PlaneLists, RegionLists, WasLists, SeenLists: array of TIntArrayW;
  WasIx, SeenIx: TFPHashList;
  WasOn, SeenOn: TIntArrayW;
  Doomed: array of Boolean;
  Acc: array[0..5] of QWord;
  TL: QWord;
  Cands, RCands: TIntArrayW;
  CI, RC: Integer;
  Tk: QWord;
  { which group each area was found in, side by side with R }
  RPart, Parts: TIntArrayW;
  RP: TRegionArray;
  PP, RBase, CurPart: Integer;

  { is P on the segment AB, within a hair }
  function OnSegment(const P, A, B: TP3): Boolean;
  var
    L, T: Double;
    Q: TP3;
  begin
    L := Dist(A, B);
    if L < 1E-9 then Exit(Dist(P, A) < 1E-6);
    T := ((P.X - A.X) * (B.X - A.X) + (P.Y - A.Y) * (B.Y - A.Y) + (P.Z - A.Z) * (B.Z - A.Z)) / (L * L);
    if (T < -1E-6) or (T > 1 + 1E-6) then Exit(False);
    Q := P3(A.X + (B.X - A.X) * T, A.Y + (B.Y - A.Y) * T, A.Z + (B.Z - A.Z) * T);
    Result := Dist(P, Q) < 1E-6;
  end;

  { an end, and the group it is in: a solid's line in another group is not
    an edge of anything found in this one }
  function EndKey(const P: TP3; Part: Integer): shortstring;
  var
    Q: array[0..3] of Int64;
  begin
    Q[0] := Round(P.X * 1E6); Q[1] := Round(P.Y * 1E6); Q[2] := Round(P.Z * 1E6);
    Q[3] := Part;
    SetLength(Result, 32);
    Move(Q[0], Result[1], 32);
  end;

  procedure NoteLine(const P: TP3; L: Integer);
  var
    Ix: Integer;
  begin
    Ix := LineIx.FindIndexOf(EndKey(P, FD.Doc[L].Part));
    if Ix < 0 then
    begin
      SetLength(LineLists, Length(LineLists) + 1);
      Ix := High(LineLists);
      LineIx.Add(EndKey(P, FD.Doc[L].Part), Pointer(PtrInt(Ix + 1)));
    end
    else
      Ix := PtrInt(LineIx.Items[Ix]) - 1;
    SetLength(LineLists[Ix], Length(LineLists[Ix]) + 1);
    LineLists[Ix][High(LineLists[Ix])] := L;
  end;

  { the solid line, if any, that runs along P-Q, found by either end (an
    opening's edges are whole lines of the solid) }
  function GroupLineAlong(const P, Q: TP3): Integer;
  var
    Pass, Ix, K, L: Integer;
    Key: shortstring;
  begin
    Result := -1;
    for Pass := 0 to 1 do
    begin
      if Pass = 0 then Key := EndKey(P, CurPart) else Key := EndKey(Q, CurPart);
      Ix := LineIx.FindIndexOf(Key);
      if Ix < 0 then Continue;
      Ix := PtrInt(LineIx.Items[Ix]) - 1;
      for K := 0 to High(LineLists[Ix]) do
      begin
        L := LineLists[Ix][K];
        if OnSegment(P, FD.Doc[L].A, FD.Doc[L].B) and OnSegment(Q, FD.Doc[L].A, FD.Doc[L].B) then
          Exit(L);
      end;
    end;
  end;

  { a plane as a key: normal pointed one way, normal and offset rounded
    coarsely so faces on one plane share a key.  The fine test still runs on
    what comes back. }
  function PlaneKey(const N, P: TP3; Part: Integer): shortstring;
  var
    Nm: TP3;
    Q: array[0..4] of Int64;
  begin
    Nm := CanonicalNormal(N);
    Q[0] := Round(Nm.X * 1000); Q[1] := Round(Nm.Y * 1000); Q[2] := Round(Nm.Z * 1000);
    Q[3] := Round(Dot3(Nm, P) * 1000);
    { and the group: the same plane in two groups is two planes here }
    Q[4] := Part;
    SetLength(Result, 40);
    Move(Q[0], Result[1], 40);
  end;

  procedure NotePlane(const Key: shortstring; SI: Integer);
  var
    Ix: Integer;
  begin
    Ix := PlaneIx.FindIndexOf(Key);
    if Ix < 0 then
    begin
      SetLength(PlaneLists, Length(PlaneLists) + 1);
      Ix := High(PlaneLists);
      PlaneIx.Add(Key, Pointer(PtrInt(Ix + 1)));
    end
    else
      Ix := PtrInt(PlaneIx.Items[Ix]) - 1;
    SetLength(PlaneLists[Ix], Length(PlaneLists[Ix]) + 1);
    PlaneLists[Ix][High(PlaneLists[Ix])] := SI;
  end;

  procedure NoteRegion(const Key: shortstring; RI: Integer);
  var
    Ix: Integer;
  begin
    Ix := RegionIx.FindIndexOf(Key);
    if Ix < 0 then
    begin
      SetLength(RegionLists, Length(RegionLists) + 1);
      Ix := High(RegionLists);
      RegionIx.Add(Key, Pointer(PtrInt(Ix + 1)));
    end
    else
      Ix := PtrInt(RegionIx.Items[Ix]) - 1;
    SetLength(RegionLists[Ix], Length(RegionLists[Ix]) + 1);
    RegionLists[Ix][High(RegionLists[Ix])] := RI;
  end;

  { the same index for anything filed by plane: a list per plane key, with
    the three neighboring offsets returned together }
  procedure NoteInto(H: TFPHashList; var Lists: TIntListsW; const Key: shortstring; Ix: Integer);
  var
    At: Integer;
  begin
    At := H.FindIndexOf(Key);
    if At < 0 then
    begin
      SetLength(Lists, Length(Lists) + 1);
      At := High(Lists);
      H.Add(Key, Pointer(PtrInt(At + 1)));
    end
    else
      At := PtrInt(H.Items[At]) - 1;
    SetLength(Lists[At], Length(Lists[At]) + 1);
    Lists[At][High(Lists[At])] := Ix;
  end;

  function OnPlaneIn(H: TFPHashList; const Lists: TIntListsW; const N, P: TP3; Part: Integer): TIntArrayW;
  var
    Nm: TP3;
    Ix, K, D, Have: Integer;
    Key: shortstring;
    Q: array[0..4] of Int64;
  begin
    Result := nil;
    Have := 0;
    Nm := CanonicalNormal(N);
    Q[0] := Round(Nm.X * 1000); Q[1] := Round(Nm.Y * 1000); Q[2] := Round(Nm.Z * 1000);
    Q[4] := Part;
    for D := -1 to 1 do
    begin
      Q[3] := Round(Dot3(Nm, P) * 1000) + D;
      SetLength(Key, 40);
      Move(Q[0], Key[1], 40);
      Ix := H.FindIndexOf(Key);
      if Ix < 0 then Continue;
      Ix := PtrInt(H.Items[Ix]) - 1;
      SetLength(Result, Have + Length(Lists[Ix]));
      for K := 0 to High(Lists[Ix]) do
      begin
        Result[Have] := Lists[Ix][K];
        Inc(Have);
      end;
    end;
  end;

  procedure Lap(K: Integer);
  begin
    Acc[K] := Acc[K] + (GetTickCount64 - TL);
    TL := GetTickCount64;
  end;

  function RegionsOnPlane(const N, P: TP3; Part: Integer): TIntArrayW;
  var
    Nm: TP3;
    Ix, K, D: Integer;
    Key: shortstring;
    Q: array[0..4] of Int64;
  begin
    Result := nil;
    Nm := CanonicalNormal(N);
    Q[0] := Round(Nm.X * 1000); Q[1] := Round(Nm.Y * 1000); Q[2] := Round(Nm.Z * 1000);
    Q[4] := Part;
    for D := -1 to 1 do
    begin
      Q[3] := Round(Dot3(Nm, P) * 1000) + D;
      SetLength(Key, 40);
      Move(Q[0], Key[1], 40);
      Ix := RegionIx.FindIndexOf(Key);
      if Ix < 0 then Continue;
      Ix := PtrInt(RegionIx.Items[Ix]) - 1;
      for K := 0 to High(RegionLists[Ix]) do
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := RegionLists[Ix][K];
      end;
    end;
  end;

  { the solids on the plane through P with normal N; the key is coarse, so
    neighboring offsets are asked too }
  function SolidsOnPlane(const N, P: TP3; Part: Integer): TIntArrayW;
  var
    Nm: TP3;
    Ix, K, D: Integer;
    Key: shortstring;
    Q: array[0..4] of Int64;
  begin
    Result := nil;
    Nm := CanonicalNormal(N);
    Q[0] := Round(Nm.X * 1000); Q[1] := Round(Nm.Y * 1000); Q[2] := Round(Nm.Z * 1000);
    Q[4] := Part;
    for D := -1 to 1 do
    begin
      Q[3] := Round(Dot3(Nm, P) * 1000) + D;
      SetLength(Key, 40);
      Move(Q[0], Key[1], 40);
      Ix := PlaneIx.FindIndexOf(Key);
      if Ix < 0 then Continue;
      Ix := PtrInt(PlaneIx.Items[Ix]) - 1;
      for K := 0 to High(PlaneLists[Ix]) do
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := PlaneLists[Ix][K];
      end;
    end;
  end;

  function OpeningOfSolid(const Rg: TRegion; out Grp: Integer): Boolean;
  var
    E, L: Integer;
    P, Q: TP3;
  begin
    Result := False;
    Grp := 0;
    for E := 0 to High(Rg.Outer) do
    begin
      P := Rg.Outer[E];
      Q := Rg.Outer[(E + 1) mod Length(Rg.Outer)];
      L := GroupLineAlong(P, Q);
      if L < 0 then Exit(False);
      if (Grp > 0) and (FD.Doc[L].Grp <> Grp) then Exit(False);
      Grp := FD.Doc[L].Grp;
    end;
    Result := Grp > 0;
  end;

  { the middle of a built solid, for pointing a face away from it }
  function SolidMidOf(G: Integer): TP3;
  var
    E, K, N: Integer;
  begin
    Result := P3(0, 0, 0);
    N := 0;
    for E := 0 to FD.Doc.Live - 1 do
      if (FD.Doc[E].Kind = ekFace) and (FD.Doc[E].Grp = G) then
        for K := 0 to High(FD.Doc[E].Poly) do
        begin
          Result := P3(Result.X + FD.Doc[E].Poly[K].X,
                       Result.Y + FD.Doc[E].Poly[K].Y,
                       Result.Z + FD.Doc[E].Poly[K].Z);
          Inc(N);
        end;
    if N > 0 then Result := P3(Result.X / N, Result.Y / N, Result.Z / N);
  end;

  { Has the line just drawn traced one of this region's sides?  That is
    SketchUp's healing gesture, the way back to a deliberately erased face.
    It beats both the erased-area memory and the solid-opening rule. }
  function HealsThis(const Rg: TRegion): Boolean;
  var
    E: Integer;
    P, Q: TP3;
  begin
    Result := False;
    if not FHealOn then Exit;
    for E := 0 to High(Rg.Outer) do
    begin
      P := Rg.Outer[E];
      Q := Rg.Outer[(E + 1) mod Length(Rg.Outer)];
      if SharesRun(P, Q, FHealA, FHealB) then Exit(True);
    end;
  end;

  { whether the old face lies in this region's plane: same normal, and the
    region's middle on it }
  function OnPlaneOf(W: Integer): Boolean;
  begin
    Result := (Abs(Abs(Dot3(Was[W].Nm, R[I].Normal)) - 1) < 1E-6) and
      (Abs(Dot3(Was[W].Nm, P3(Mid.X - Was[W].Poly[0].X, Mid.Y - Was[W].Poly[0].Y,
                              Mid.Z - Was[W].Poly[0].Z))) < 1E-4);
  end;

  { Did the old face cover this point: inside its outline and not inside one
    of its holes.  Otherwise a ring with its middle erased got the middle
    back every rebuild. }
  function WasCovering(W: Integer): Boolean;
  var
    H: Integer;
  begin
    Result := OnPlaneOf(W) and PointInLoop(Mid, Was[W].Poly, Was[W].Nm);
    if not Result then Exit;
    for H := 0 to High(Was[W].Holes) do
      if PointInLoop(Mid, Was[W].Holes[H], Was[W].Nm) then Exit(False);
  end;

begin
  Tk := GetTickCount64;
  { One finder pass per group with only its own edges; areas noted with
    their group.  Geometry in one group never closes an area with another. }
  R := nil;
  RPart := nil;
  Parts := AllPartIds;
  for PP := 0 to High(Parts) do
  begin
    CI := CacheFor(Parts[PP]);      { the slot first - see SeedRegions }
    RP := BuildRegionsCached(EdgeSegments(Parts[PP]), FRegionCaches[CI].Cache);
    RBase := Length(R);
    SetLength(R, RBase + Length(RP));
    SetLength(RPart, RBase + Length(RP));
    for I := 0 to High(RP) do
    begin
      R[RBase + I] := RP[I];
      RPart[RBase + I] := Parts[PP];
    end;
  end;
  Took('  regions', Tk);
  Tk := GetTickCount64;
  Made := 0;
  { the regions by plane; faces being deleted does not shift them, so build
    it now }
  RegionIx := TFPHashList.Create;
  SetLength(RegionLists, 0);
  for I := 0 to High(R) do
    if Length(R[I].Outer) >= 3 then
      NoteRegion(PlaneKey(R[I].Normal, R[I].Outer[0], RPart[I]), I);

  { A solid's face divided by what was drawn on it (an arc whose chord is a
    box's top edge splits the top in two).  When the pieces on the face add
    up to it and at least one shares an edge with its outline (a cut, not a
    window), the face is replaced by the pieces, each a face of the same
    solid, so push can lift a piece. }
  SetLength(Doomed, FD.Doc.Live);
  for J := 0 to High(Doomed) do Doomed[J] := False;
  SetLength(RMid, Length(R));
  SetLength(RMidOK, Length(R));
  for J := 0 to High(RMidOK) do RMidOK[J] := False;
  for J := FD.Doc.Live - 1 downto 0 do
  begin
    if (FD.Doc[J].Kind <> ekFace) or not FD.Doc[J].Solid then Continue;
    if Length(FD.Doc[J].Holes) > 0 then Continue;
    { one copy of the face: the indexer returns a whole record copy each time }
    FE := FD.Doc[J];
    FN := FD.Doc.FaceNormal(J);
    FArea := Abs(LoopArea(FE.Poly, FN));
    if FArea < 1E-9 then Continue;
    FLo := FE.Poly[0];
    FHi := FE.Poly[0];
    for K := 1 to High(FE.Poly) do
    begin
      FLo := P3(Min(FLo.X, FE.Poly[K].X), Min(FLo.Y, FE.Poly[K].Y), Min(FLo.Z, FE.Poly[K].Z));
      FHi := P3(Max(FHi.X, FE.Poly[K].X), Max(FHi.Y, FE.Poly[K].Y), Max(FHi.Z, FE.Poly[K].Z));
    end;
    SetLength(Pieces, 0);
    PiecesArea := 0;
    Shares := False;
    RCands := RegionsOnPlane(FN, FE.Poly[0], FE.Part);
    for RC := 0 to High(RCands) do
    begin
      I := RCands[RC];
      if Length(R[I].Holes) > 0 then Continue;
      { a region's middle, computed once; many faces ask about it }
      if not RMidOK[I] then
      begin
        RMid[I] := InnerPoint(R[I].Outer, R[I].Normal);
        RMidOK[I] := True;
      end;
      Mid := RMid[I];
      { outside the face's box is not on it; this keeps the pass cheap }
      if (Mid.X < FLo.X - 1E-4) or (Mid.X > FHi.X + 1E-4) or
         (Mid.Y < FLo.Y - 1E-4) or (Mid.Y > FHi.Y + 1E-4) or
         (Mid.Z < FLo.Z - 1E-4) or (Mid.Z > FHi.Z + 1E-4) then Continue;
      if Abs(Abs(Dot3(Norm3(R[I].Normal), FN)) - 1) > 1E-6 then Continue;
      if Abs(Dot3(FN, P3(Mid.X - FE.Poly[0].X,
                          Mid.Y - FE.Poly[0].Y,
                          Mid.Z - FE.Poly[0].Z))) > 1E-4 then Continue;
      if not PointInLoop(Mid, FE.Poly, FN) then Continue;
      { the whole face as a region is not a division }
      if Abs(Abs(LoopArea(R[I].Outer, R[I].Normal)) - FArea) < 1E-3 then
        Continue;
      SetLength(Pieces, Length(Pieces) + 1);
      Pieces[High(Pieces)] := I;
      PiecesArea := PiecesArea + Abs(LoopArea(R[I].Outer, R[I].Normal));
      { A piece shares the outline when one of its edges lies along one of
        the face's edges (not corner to corner, which fails once something
        else has split the face's edge). }
      if not Shares then
        for K := 0 to High(R[I].Outer) do
          for M := 0 to High(FE.Poly) do
            if OnSegment(R[I].Outer[K], FE.Poly[M],
                         FE.Poly[(M + 1) mod Length(FE.Poly)]) and
               OnSegment(R[I].Outer[(K + 1) mod Length(R[I].Outer)], FE.Poly[M],
                         FE.Poly[(M + 1) mod Length(FE.Poly)]) then
              Shares := True;
    end;
    if (Length(Pieces) < 2) or not Shares then Continue;
    if Abs(PiecesArea - FArea) > 1E-3 * (1 + FArea) then Continue;

    { replace it: the pieces become faces of the same solid }
    G := FD.Doc[J].Grp;
    Ink := FD.Doc[J].Ink;
    Doomed[J] := True;
    FD.Doc.Stamp := FE.Part;       { the pieces are born into the solid's group }
    for I := 0 to High(Pieces) do
    begin
      FD.Doc.AddFaceRaw(R[Pieces[I]].Outer, Ink, True);
      FD.Doc.SetFaceGroup(FD.Doc.Live - 1, G);
      { facing the way the replaced face did; a piece wound the other way
        would show its blue back }
      if Dot3(FD.Doc.FaceNormal(FD.Doc.Live - 1), FN) < 0 then
        FD.Doc.FlipFace(FD.Doc.Live - 1);
    end;
  end;

  FD.Doc.Stamp := FD.Doc.Context;
  { the divided faces go in one pass; one at a time shifted everything after }
  FD.Doc.DeleteMarked(Doomed);
  Took('  tiling', Tk);
  Tk := GetTickCount64;
  { remember what was there, so new faces can take their colors }
  NWas := 0;
  SetLength(Was, FD.Doc.Live);
  for I := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[I].Kind = ekFace) and not FD.Doc[I].Solid and
       (Length(FD.Doc[I].Poly) >= 3) then
    begin
      Was[NWas].Poly := Copy(FD.Doc[I].Poly, 0, Length(FD.Doc[I].Poly));
      SetLength(Was[NWas].Holes, Length(FD.Doc[I].Holes));
      for J := 0 to High(FD.Doc[I].Holes) do
        Was[NWas].Holes[J] := Copy(FD.Doc[I].Holes[J], 0, Length(FD.Doc[I].Holes[J]));
      Was[NWas].Nm := FD.Doc.FaceNormal(I);
      Was[NWas].Ink := FD.Doc[I].Ink;
      Was[NWas].Part := FD.Doc[I].Part;
      Was[NWas].Mat := FD.Doc[I].Mat;
      Was[NWas].MatSet := FD.Doc[I].MatSet;
      Mid := P3(0, 0, 0);
      for K := 0 to High(Was[NWas].Poly) do
        Mid := P3(Mid.X + Was[NWas].Poly[K].X, Mid.Y + Was[NWas].Poly[K].Y,
                  Mid.Z + Was[NWas].Poly[K].Z);
      K := Length(Was[NWas].Poly);
      Was[NWas].Mid := P3(Mid.X / K, Mid.Y / K, Mid.Z / K);
      Inc(NWas);
    end;
  SetLength(Was, NWas);
  { the old faces by plane, so a region only asks those on its own plane }
  WasIx := TFPHashList.Create;
  SetLength(WasLists, 0);
  for J := 0 to NWas - 1 do
    NoteInto(WasIx, WasLists, PlaneKey(Was[J].Nm, Was[J].Mid, Was[J].Part), J);
  { and what the sheet had seen, the same way }
  SeenIx := TFPHashList.Create;
  SetLength(SeenLists, 0);
  for J := 0 to High(FD.Seen) do
    NoteInto(SeenIx, SeenLists, PlaneKey(FD.Seen[J].Nm, FD.Seen[J].Mid, FD.Seen[J].Part), J);

  { out with the old in one pass; one at a time was most of a minute on a
    big drawing }
  SetLength(Doomed, FD.Doc.Live);
  for I := 0 to FD.Doc.Live - 1 do
    Doomed[I] := (FD.Doc[I].Kind = ekFace) and not FD.Doc[I].Solid;
  FD.Doc.DeleteMarked(Doomed);
  Took('  old faces out', Tk);
  Tk := GetTickCount64;

  { The solids' faces, planes, areas and lines by their ends, built once for
    the loop below.  Built after the tiling pass, which deletes and adds
    faces and shifts indices; built earlier, they pointed at the wrong
    things. }
  SetLength(SolidIx, 0);
  for J := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[J].Kind = ekFace) and FD.Doc[J].Solid and (Length(FD.Doc[J].Poly) >= 3) then
    begin
      SetLength(SolidIx, Length(SolidIx) + 1);
      SolidIx[High(SolidIx)] := J;
    end;
  SetLength(SolidN, Length(SolidIx));
  SetLength(SolidP0, Length(SolidIx));
  SetLength(SolidMid, Length(SolidIx));
  SetLength(SolidRad, Length(SolidIx));
  SetLength(SolidArea, Length(SolidIx));
  PlaneIx := TFPHashList.Create;
  SetLength(PlaneLists, 0);
  for J := 0 to High(SolidIx) do
  begin
    SolidN[J] := FD.Doc.FaceNormal(SolidIx[J]);
    FE := FD.Doc[SolidIx[J]];
    SolidP0[J] := FE.Poly[0];
    Mid := P3(0, 0, 0);
    for K := 0 to High(FE.Poly) do
      Mid := P3(Mid.X + FE.Poly[K].X, Mid.Y + FE.Poly[K].Y, Mid.Z + FE.Poly[K].Z);
    K := Length(FE.Poly);
    SolidMid[J] := P3(Mid.X / K, Mid.Y / K, Mid.Z / K);
    SolidRad[J] := 0;
    for K := 0 to High(FE.Poly) do
      SolidRad[J] := Max(SolidRad[J], Dist(SolidMid[J], FE.Poly[K]));
    SolidArea[J] := Abs(LoopArea(FD.Doc[SolidIx[J]].Poly, SolidN[J]));
    { by plane, so a region meets only solids in its own plane }
    NotePlane(PlaneKey(SolidN[J], FD.Doc[SolidIx[J]].Poly[0], FD.Doc[SolidIx[J]].Part), J);
  end;
  { and the solids' lines by their ends, for the opening test }
  LineIx := TFPHashList.Create;
  SetLength(LineLists, 0);
  for J := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[J].Kind = ekLine) and (FD.Doc[J].Grp > 0) then
    begin
      NoteLine(FD.Doc[J].A, J);
      NoteLine(FD.Doc[J].B, J);
    end;

  Took('  tables', Tk);
  Tk := GetTickCount64;
  FillChar(Acc, SizeOf(Acc), 0);
  { a region with no outline is nothing to look at }
  for I := 0 to High(R) do
  begin
    if ((I and 63) = 0) and (Length(R) > 500) then
      if not OnProgress('Working out the faces', I / Length(R)) then Break;
    if Length(R[I].Outer) < 3 then Continue;
    TL := GetTickCount64;
    { this area's group: the tables answer for it, and a new face is born
      into it }
    CurPart := RPart[I];
    FD.Doc.Stamp := CurPart;
    Mid := InnerPointOf(R[I].Outer, R[I].Holes, R[I].Normal);
    Lap(0);

    { Is this a face the solid already has?  Same plane, same outline area,
      and a point of one inside the other (not the corner average, which
      moves when an edge is split).  A second face in the same place would
      flicker. }
    Dup := False;
    DupAt := -1;
    RegArea := -1;
    Cands := SolidsOnPlane(R[I].Normal, R[I].Outer[0], RPart[I]);
    for CI := 0 to High(Cands) do
      begin
        SI := Cands[CI];
        J := SolidIx[SI];
        Other := SolidN[SI];
        if Abs(Abs(Dot3(Other, R[I].Normal)) - 1) > 1E-6 then Continue;
        { the same plane, not merely a parallel one }
        if Abs(Dot3(Other, P3(SolidP0[SI].X - R[I].Outer[0].X,
                              SolidP0[SI].Y - R[I].Outer[0].Y,
                              SolidP0[SI].Z - R[I].Outer[0].Z))) > 1E-4
          then Continue;
        { Outline against outline, holes ignored: the outline is what makes
          it the same face, and holes change between rebuilds (so a window
          drawn on a wall still matches and hands the wall its hole below).
          Further from the solid's middle than any corner is not inside it,
          which keeps PointInLoop to plausible candidates. }
        if Dist(Mid, SolidMid[SI]) > SolidRad[SI] + 1E-4 then Continue;
        if RegArea < 0 then RegArea := Abs(LoopArea(R[I].Outer, R[I].Normal));
        if Abs(RegArea - SolidArea[SI]) > 1E-3 then
          Continue;
        if PointInLoop(Mid, FD.Doc[J].Poly, Other) then
        begin
          Dup := True;
          DupAt := J;
          Break;
        end;
      end;
    Lap(1);
    if Dup then
    begin
      { The solid already has this face, but the area may have gained a hole
        (a rectangle drawn inside a column's side): hand the holes to the
        solid's face so the window opens. }
      if DupAt >= 0 then FD.Doc.SetFaceHoles(DupAt, R[I].Holes);
      Continue;
    end;

    { Did this area have a face a moment ago, or has the sheet seen it
      before?  An area seen before with no face now was erased on purpose and
      gets none.  A new area was just closed and does.  Old faces must be in
      the same plane, not just contain the point when projected (a box's far
      end would otherwise answer for its near end). }
    HadFace := False;
    WasOn := OnPlaneIn(WasIx, WasLists, R[I].Normal, Mid, RPart[I]);
    for J := 0 to High(WasOn) do
      if WasCovering(WasOn[J]) then
      begin
        HadFace := True;
        Break;
      end;
    if not HadFace and not HealsThis(R[I]) then
    begin
      { An opening of a built solid (a duct end, a hole) is edged entirely by
        that solid's edges and never gets a face, however it got here.  Draw
        across it and it becomes a new area like any other. }
      Lap(2);
      if OpeningOfSolid(R[I], HealGrp) then begin Lap(3); Continue; end;
      Lap(3);
      Sig := RegionSig(R[I]);
      Sig.Part := RPart[I];
      Known := False;
      SeenOn := OnPlaneIn(SeenIx, SeenLists, Sig.Nm, Sig.Mid, RPart[I]);
      for J := 0 to High(SeenOn) do
        if SameRegion(Sig, FD.Seen[SeenOn[J]]) then
        begin
          Known := True;
          Break;
        end;
      Lap(4);
      if Known then Continue;
    end;

    Ink := FInkColor;
    WasHit := -1;
    for J := 0 to High(WasOn) do
      if WasCovering(WasOn[J]) then
      begin
        Ink := Was[WasOn[J]].Ink;
        WasHit := WasOn[J];
        Break;
      end;
    FD.Doc.AddFace(R[I].Outer, Ink, False);
    { the replaced face's paint and direction carry across, or it may show
      its blue back }
    if WasHit >= 0 then
    begin
      if Was[WasHit].MatSet then
        FD.Doc.SetMaterial(FD.Doc.Live - 1, Was[WasHit].Mat);
      if Dot3(FD.Doc.FaceNormal(FD.Doc.Live - 1), Was[WasHit].Nm) < 0 then
        FD.Doc.FlipFace(FD.Doc.Live - 1);
    end;
    { and whatever is cut out of it }
    if Length(R[I].Holes) > 0 then
      FD.Doc.SetFaceHoles(FD.Doc.Live - 1, R[I].Holes);
    { A side traced back into a box joins the box; left loose it would be
      refused at the next rebuild (a solid's opening gets no loose face). }
    if FHealOn and HealsThis(R[I]) and OpeningOfSolid(R[I], HealGrp) then
    begin
      FD.Doc.SetFaceGroup(FD.Doc.Live - 1, HealGrp);
      { facing out, away from the solid's middle.  The area's middle may not
        have been computed by the tiling pass, so compute it here. }
      if not RMidOK[I] then
      begin
        RMid[I] := InnerPoint(R[I].Outer, R[I].Normal);
        RMidOK[I] := True;
      end;
      Mid := SolidMidOf(HealGrp);
      if Dot3(FD.Doc.FaceNormal(FD.Doc.Live - 1),
              P3(RMid[I].X - Mid.X, RMid[I].Y - Mid.Y, RMid[I].Z - Mid.Z)) < 0 then
        FD.Doc.FlipFace(FD.Doc.Live - 1);
    end;
    Inc(Made);
    Lap(5);
  end;
  if FTimings then
    TimingLine(Format('region loop phases ms: inner %d dup %d was %d opening %d seen %d add %d',
      [Acc[0], Acc[1], Acc[2], Acc[3], Acc[4], Acc[5]]));
  LineIx.Free;
  PlaneIx.Free;
  RegionIx.Free;
  WasIx.Free;
  SeenIx.Free;
  if not FLoading then EndBusy;
  FD.Doc.Stamp := FD.Doc.Context;
  Took('  the region loop', Tk);
  Tk := GetTickCount64;
  { what the sheet has seen, for the next rebuild to compare against }
  SetLength(FD.Seen, Length(R));
  for I := 0 to High(R) do
  begin
    FD.Seen[I] := RegionSig(R[I]);
    FD.Seen[I].Part := RPart[I];
  end;
  Took('  seen signatures', Tk);

  { Then make the loose faces agree about which way is out.  OrientFace
    looks at one face at a time and gets roof slopes wrong; a face pointing
    in shows its blue back.  This needs all the neighbors, so it runs after
    the loop. }
  FTurned := 0;
  for PP := 0 to High(Parts) do
    FTurned := FTurned + FD.Doc.OrientLooseShells(Parts[PP]);
  Took('  turning loose faces the right way out', Tk);

  Result := Made;
end;

{ A read-only look at what the region engine makes of the drawing beside the
  faces actually stored, for checking. }
procedure TMainForm.ReportRegions;
var
  R: TRegionArray;
  Segs: TSegArray;
  I, Stored, Holes, CI: Integer;
  Area, StoredArea, T0: Double;
begin
  Segs := EdgeSegments(FD.Doc.Context);
  T0 := Now;
  CI := CacheFor(FD.Doc.Context);
  R := BuildRegionsCached(Segs, FRegionCaches[CI].Cache);
  T0 := (Now - T0) * 24 * 60 * 60 * 1000;

  Stored := 0;
  StoredArea := 0;
  for I := 0 to FD.Doc.Live - 1 do
    if (FD.Doc[I].Kind = ekFace) and not FD.Doc[I].Solid then
    begin
      Inc(Stored);
      StoredArea := StoredArea + FD.Doc.FaceArea(I);
    end;

  Area := 0;
  Holes := 0;
  for I := 0 to High(R) do
  begin
    Area := Area + Abs(LoopArea(R[I].Outer, R[I].Normal));
    Inc(Holes, Length(R[I].Holes));
  end;

  FCmdMsg := Format('%d edges -> %d regions (%s, %d holes) in %.0f ms.  ' +
    'Stored flat faces: %d (%s)',
    [Length(Segs), Length(R), FormatArea(Area, FD.Units), Holes, T0,
     Stored, FormatArea(StoredArea, FD.Units)]);
  pbCmd.Invalidate;
end;

{ Where the dimension being placed goes: DimOffsetAt (hsDrawing), which
  follows the hand on screen.  The planes of faces the edge belongs to are
  offered first, so it can stand up a box's side, even off-axis. }
function TMainForm.DimOffset3: TP3;
var
  Extra: array of TP3;
  I, K, N: Integer;
  D, Nm: TP3;
  L: Double;
begin
  Extra := nil;
  D := P3(FP2.X - FP1.X, FP2.Y - FP1.Y, FP2.Z - FP1.Z);
  for I := 0 to FD.Doc.Live - 1 do
  begin
    if FD.Doc[I].Kind <> ekFace then Continue;
    N := Length(FD.Doc[I].Poly);
    for K := 0 to N - 1 do
      if ((Dist(FD.Doc[I].Poly[K], FP1) < 1E-6) and (Dist(FD.Doc[I].Poly[(K + 1) mod N], FP2) < 1E-6)) or
         ((Dist(FD.Doc[I].Poly[K], FP2) < 1E-6) and (Dist(FD.Doc[I].Poly[(K + 1) mod N], FP1) < 1E-6)) then
      begin
        Nm := FD.Doc.FaceNormal(I);
        SetLength(Extra, Length(Extra) + 1);
        Extra[High(Extra)] := Cross3(Nm, D);
        Break;
      end;
  end;
  Result := DimOffsetAt(Proj, FP1, FP2, FMouseSX, FMouseSY, Extra, FDimPrefer);
  L := Sqrt(Sqr(Result.X) + Sqr(Result.Y) + Sqr(Result.Z));
  if L < 1E-9 then Exit;
  FDimPrefer := P3(Result.X / L, Result.Y / L, Result.Z / L);
  { never let it sit right on top of what it measures }
  if L * Ppu < 8 then
    Result := P3(Result.X / L * 8 / Ppu, Result.Y / L * 8 / Ppu, Result.Z / L * 8 / Ppu);
end;

{ the circle or arc that P is one of the drawn corners of (not an arc's own
  two ends), or -1 }
function TMainForm.CurveThrough(const P: TP3): Integer;
var
  I: Integer;
  E: TWorkEnt;
  Nm: TP3;
begin
  Result := -1;
  for I := 0 to FD.Doc.Live - 1 do
  begin
    E := FD.Doc[I];
    if E.Kind <> ekArc then Continue;
    if Abs(Dist(P, E.C) - E.R) > 1E-6 * Max(1, E.R) then Continue;
    Nm := Cross3(P3(ArcPoint(E.C, 1, 0, E.Plane, E.Nm).X - E.C.X,
                    ArcPoint(E.C, 1, 0, E.Plane, E.Nm).Y - E.C.Y,
                    ArcPoint(E.C, 1, 0, E.Plane, E.Nm).Z - E.C.Z),
                 P3(ArcPoint(E.C, 1, Pi / 2, E.Plane, E.Nm).X - E.C.X,
                    ArcPoint(E.C, 1, Pi / 2, E.Plane, E.Nm).Y - E.C.Y,
                    ArcPoint(E.C, 1, Pi / 2, E.Plane, E.Nm).Z - E.C.Z));
    if Abs(Dot3(Nm, P3(P.X - E.C.X, P.Y - E.C.Y, P.Z - E.C.Z))) > 1E-6 * Max(1, E.R) then Continue;
    if (Abs(E.Sweep) < 2 * Pi - 1E-9) and
       ((Dist(P, E.A) < 1E-6) or (Dist(P, E.B) < 1E-6)) then Continue;
    Exit(I);
  end;
end;

{ A circle's diameter or an arc's radius, turned to the pointer: the point
  on it nearest the pointer is one end; the other is the opposite point for
  a circle, the center for an arc.  Note is "DIA <>" or "R <>", the length
  going in the <>. }
function TMainForm.DimRadialAt(out A, B: TP3; out Note: string): Boolean;
var
  E: TWorkEnt;
  K, N, BestK: Integer;
  Ang, BestD, D, Sw: Double;
  P: TPointF;
begin
  Result := False;
  if (FDimArc < 0) or (FDimArc >= FD.Doc.Live) or (FD.Doc[FDimArc].Kind <> ekArc) then Exit;
  E := FD.Doc[FDimArc];
  Sw := E.Sweep;
  if Abs(Sw) >= 2 * Pi - 1E-9 then Sw := 2 * Pi;
  N := 360;
  BestD := 1E30; BestK := 0;
  for K := 0 to N do
  begin
    Ang := E.A0 + Sw * K / N;
    P := ScreenOf(ArcPoint(E.C, E.R, Ang, E.Plane, E.Nm));
    D := Sqr(P.X - FMouseSX) + Sqr(P.Y - FMouseSY);
    if D < BestD then begin BestD := D; BestK := K; end;
  end;
  B := ArcPoint(E.C, E.R, E.A0 + Sw * BestK / N, E.Plane, E.Nm);
  if Abs(E.Sweep) >= 2 * Pi - 1E-9 then
  begin
    A := P3(2 * E.C.X - B.X, 2 * E.C.Y - B.Y, 2 * E.C.Z - B.Z);
    Note := 'DIA <>';
  end
  else
  begin
    A := E.C;
    Note := 'R <>';
  end;
  Result := True;
end;

{ Rest on a point for a moment and it is remembered as a reference, so you
  can move away and still line up with it (SketchUp's trick). }
procedure TMainForm.ServiceHover;
var
  Now64: QWord;
begin

  { any real movement restarts the clock }
  if (Abs(FMoveX - FDwellSX) > 3) or (Abs(FMoveY - FDwellSY) > 3) then
  begin
    FDwellSX := FMoveX;
    FDwellSY := FMoveY;
    FDwellSince := GetTickCount64;
    Exit;
  end;

  { only a point worth referencing is worth keeping }
  if not (FSnapKind in [snEndpoint, snMidpoint, snCenter, snCross, snSubMid]) then
    Exit;

  Now64 := GetTickCount64;
  if Now64 - FDwellSince < DWELL_MS then Exit;

  if FNoLockUntilMoved then Exit;         // just snapped off from here
  if FLockOn and (Dist(FLockPt, FCur) < 1E-9) then Exit;   // already this one
  FLockOn := True;
  FLockPt := FCur;
  FLockKind := FSnapKind;
  FScreenDirty := True;
  InvalidateStatus;
end;

{ Alignment guides to another point get their own color, distinct from ink
  and from axis colors, so they never look like something being drawn. }
function TMainForm.GuideColor: TPix;
begin
  Result := Pix($A8, $2A, $BA);
end;

procedure TMainForm.pbScreenMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  NoteI: Integer;
begin
  if FBusy then Exit;
  { the cube, if it had the press }
  if FCubeDrag then
  begin
    CubeMouse(X, Y, False, True);
    pbScreen.Invalidate;
    Exit;
  end;
  { let go of a note being carried }
  if FNoteDrag >= 0 then
  begin
    NoteI := FNoteDrag;
    FNoteDrag := -1;
    if not FNoteMoved then
    begin
      { the press never carried it: that is a click, and a click picks it so
        it can be sized or deleted }
      SelectOnly(NoteI);
      FCmdMsg := '';
      pbCmd.Invalidate;
      FScreenDirty := True;
      Exit;
    end;
    FCmdMsg := 'Note moved.  What it points at has not.';
    pbCmd.Invalidate;
    Exit;
  end;
  { the release position is the last thing the stroke saw }
  FMoveX := X;
  FMoveY := Y;
  FMovePending := True;
  ServiceMotion;

  { A press that never became a hold.  Two clicks in quick succession end
    the run without placing more (the first click's point stays); one click
    carries on as usual. }
  if FHoldOn and (Button = mbLeft) then
  begin
    FHoldOn := False;
    FCur := ResolveSnapAt(X, Y);
    { a double-click ends a run of lines; push/pull handles its own
      double-click.  The arc's double-click is SketchUp's: trim the corner
      just rounded, or round the one under the pointer with the same radius. }
    if (FClickN >= 2) and (FTool = ptArc) and ArcDoubleClick(X, Y) then
    begin
      FScreenDirty := True;
      Exit;
    end;
    if (FClickN >= 2) and (FTool in [ptLine, ptRect, ptCircle, ptArc]) then
    begin
      ResetTool;
      FCmdMsg := 'Line finished.  Hold the button to snap it off instead.';
    end
    else
      ToolClick;
    FScreenDirty := True;
    Exit;
  end;

  if FErasing2 then
  begin
    FErasing2 := False;
    if FEraseMode = 0 then BurnDoomed
    else SoftenDoomed(FEraseMode = 1);
    Exit;
  end;

  if FBoxing then
  begin
    FBoxing := False;
    FinishSelect(X, Y, Shift);
    Exit;
  end;

  if FPanning or FOrbiting then
  begin
    { Ctrl held as the button comes up snaps to the nearest of the cube's 26
      views.  Ctrl because window managers take Alt+drag and Shift is the pan.
      Read at release so it can be pressed partway through the orbit. }
    if FOrbiting and (ssCtrl in Shift) then SnapOrbitToNearest;
    FSnapHasHot := False;
    FPanning := False;
    FOrbiting := False;
    if FTool = ptOrbit then pbScreen.Cursor := crSizeAll
    else pbScreen.Cursor := crCross;
    { the camera has stopped: one full frame after the quick ones }
    if FCameraMoving then
    begin
      FCameraMoving := False;
      RepaintPaper;
      RenderInk;
      RecomposeAll;
      Invalidate;
    end;
    { A right press released in the same place was a click, not a pan: open
      the menu (or edit a dimension).  This has to wait for the release. }
    if (Button = mbRight) and
       (Abs(X - FRightSX) <= 3) and (Abs(Y - FRightSY) <= 3) then
      RightClickAt(X, Y);
  end;
end;

procedure TMainForm.pbScreenMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
const
  WHEEL_ROWS = 3;      { rows per notch, as in most lists }
begin
  if FBusy then Exit;
  { an open list gets the wheel before the drawing does }
  if ScrollPopup(IfThen(WheelDelta > 0, -WHEEL_ROWS, WHEEL_ROWS),
                 MousePos.X, MousePos.Y) then
  begin
    Handled := True;
    Exit;
  end;
  { and so does the cube }
  if OverCube(MousePos.X, MousePos.Y) or CubeZone(MousePos.X, MousePos.Y) then
  begin
    Handled := True;
    Exit;
  end;
  { Ctrl+wheel over a plan moves the whole slice up and down through the
    model, while you watch the plan.  Plain wheel stays zoom; Alt is taken
    (it suspends snapping). }
  if (ssCtrl in Shift) and (FD.View = vkPlan) then
  begin
    if not FD.SliceOn then
      SetSlice(True, FD.SliceLo, FD.SliceHi)
    else if WheelDelta > 0 then NudgeSlice(1, 0)
    else NudgeSlice(-1, 0);
    Handled := True;
    Exit;
  end;
  if WheelDelta > 0 then
    ZoomAt(1.15, MousePos.X, MousePos.Y)
  else
    ZoomAt(1 / 1.15, MousePos.X, MousePos.Y);
  Handled := True;
end;

{ ======================================================================== }
{ window painting                                                           }
{ ======================================================================== }

{ Is the cursor on something a dimension may be anchored to?  SketchUp's list
  (end points, midpoints, on-edge points, intersections, centers), plus the
  origin and points on axes.  Not the grid or open air: a dimension must be
  driven by the drawing to update with it. }
function TMainForm.DimAnchored: Boolean;
begin
  Result := FSnapKind in [snEndpoint, snMidpoint, snCenter, snCross,
                          snSubMid, snQuadrant, snOnEdge, snOnFace,
                          snOnAxis, snOrigin];
end;

{ the zoom, with enough decimals that a tiny zoom never reads "0%" }
function TMainForm.ZoomReading: string;
var
  Z: Double;
begin
  Z := FD.Zoom * 100;
  if Z >= 100 then Result := Format('%.0f%%', [Z])
  else if Z >= 10 then Result := Format('%.1f%%', [Z])
  else if Z >= 1 then Result := Format('%.2f%%', [Z])
  else Result := Format('%.3f%%', [Z]);
end;

function TMainForm.StatusLine: string;
var
  L, A, RW, RH: Double;
  Mv: TP3;
  Ai: Integer;
begin
  if FD.View <> vkPlan then
    Result := Format('X %s   Y %s   Z %s',
      [FormatLen(FCur.X, FD.Units), FormatLen(FCur.Y, FD.Units),
       FormatLen(FCur.Z, FD.Units)])
  else
    Result := Format('X %s   Y %s',
      [FormatLen(FCur.X, FD.Units), FormatLen(FCur.Y, FD.Units)]);

  if (FStage = 1) and (FTool in [ptLine, ptMeasure]) then
    Result := Result + '   LEN ' + FormatLen(Dist(FP1, PreviewTarget), FD.Units);

  { which way the face actually goes: IN or OUT by the sign against the
    loop, which is how the user sees it }
  if (FStage = 1) and (FTool = ptOffset) then
  begin
    L := OffsetDistance;
    if Abs(L) > 1E-9 then
      Result := Result + '   OFFSET ' + FormatLen(Abs(L), FD.Units) +
        specialize IfThen<string>(L < 0, ' IN', ' OUT');
  end;

  if (FStage = 1) and (FTool = ptRect) then
  begin
    RectSides(FP1, RectTarget, FD.Plane, RW, RH);
    Result := Result + Format('   %s x %s   AREA %s',
      [FormatLen(RW, FD.Units), FormatLen(RH, FD.Units),
       FormatArea(RW * RH, FD.Units)]);
  end;

  if (FD.View <> vkPlan) then
  begin
    Result := Result + '   PLANE ' + PlaneName;
    { where the plane came from: held, a face, or the drag; they behave
      differently }
    if FPlaneHeld then Result := Result + ' HELD'
    else if FPlaneFromFace then Result := Result + ' ON FACE'
    else if FStage >= 1 then Result := Result + ' FROM DRAG';

  end;

  { the face push/pull is offered and its size, as SketchUp shows; it tells
    stacked faces apart }
  if (FStage = 0) and (FTool in [ptPush, ptDrill]) and (FHoverFace >= 0) then
    Result := Result + '   FACE ' +
      FormatArea(FD.Doc.FaceArea(FHoverFace), FD.Units);

  if (FStage = 1) and (FTool in [ptPush, ptDrill]) and (FPushFace >= 0) then
  begin
    L := PushDistance;
    if Abs(L) > 1E-9 then
    begin
      Mv := FD.Doc.FaceNormal(FPushFace);
      Mv := P3(Mv.X * L, Mv.Y * L, Mv.Z * L);
      if (Abs(Mv.X) >= Abs(Mv.Y)) and (Abs(Mv.X) >= Abs(Mv.Z)) then
        Ai := 0
      else if Abs(Mv.Y) >= Abs(Mv.Z) then
        Ai := 2
      else
        Ai := 4;
      case Ai of
        0: if Mv.X < 0 then Ai := 1;
        2: if Mv.Y < 0 then Ai := 3;
      else
        if Mv.Z < 0 then Ai := 5;
      end;
      Result := Result + '   PUSH ' + FormatLen(Abs(L), FD.Units) +
        ' ' + AxisName(Ai);
    end;
  end;

  L := FD.Doc.ChainLength;
  if L > 0 then
  begin
    Result := Result + '   RUN ' + FormatLen(L, FD.Units);
    if FD.Doc.ChainClosed(Max(SnapStep, 1E-6)) then
    begin
      A := FD.Doc.ChainArea;
      if A > 0 then
        Result := Result + '   AREA ' + FormatArea(A, FD.Units);
    end;
  end;
end;

procedure TMainForm.FormPaint(Sender: TObject);
var
  VerX: Integer;
  M, Y, TW, RightEdge: Integer;
  S: string;
begin
  if not FBooted then Exit;
  FShell.DrawTo(Canvas, 0, 0);

  M := ChromeMargin;

  { One line.  The file buttons have the left; the reading is right-aligned
    and grows leftward; the version sits between. }
  Y := Round(5 * FUIScale);

  { the reading goes hard against ClientWidth - M, where the VIEW button
    below ends, so the right edges line up }
  RightEdge := ClientWidth - M;
  UIFont(Canvas, 11, True, Theme.Text, True);
  S := StatusLine;
  TW := Canvas.TextWidth(S);
  Canvas.TextOut(RightEdge - TW, Round(6 * FUIScale), S);

  { No program name here: the reading grows leftward into the middle.  The
    version stays (it is the first thing quoted in a bug report), with any
    newer-build notice, against the buttons. }
  VerX := pbQuick.Left + pbQuick.Width + Round(16 * FUIScale);
  UIFont(Canvas, 9, False, Theme.TextDim);
  Canvas.TextOut(VerX, Y + Round(4 * FUIScale), CurrentVersion);
  VerX := VerX + Canvas.TextWidth(CurrentVersion) + Round(14 * FUIScale);
  { a newer build, shown where nothing overwrites it, until it is taken }
  if FUpdateTag <> '' then
  begin
    UIFont(Canvas, 9, True, Pix(90, 190, 255));
    S := '* ' + FUpdateTag + ' available - /update';
    if VerX + Canvas.TextWidth(S) < RightEdge - TW - Round(16 * FUIScale) then
      Canvas.TextOut(VerX, Y + Round(4 * FUIScale), S);
  end;
end;

{ ======================================================================== }
{ ink, precision, units                                                     }
{ ======================================================================== }

procedure TMainForm.SetInk(C: TColor; Auto: Boolean);
begin
  FInkColor := C;
  FInkAuto := Auto;
  dlgColor.Color := C;
  pbDeck.Invalidate;
end;

{ How finely lengths are written and read.  One setting for both, so a typed
  number never displays as a different one.  It never changes what the model
  holds: finer input keeps every digit and is only shown rounded. }
procedure TMainForm.SetLenPrecision(D: Integer);
begin
  SetLenDenom(D);
  FLenDenom := LenDenom;
  if FLenDenom = 100 then
    FCmdMsg := 'Lengths to hundredths of an inch.'
  else
    FCmdMsg := Format('Lengths to the nearest 1/%d of an inch.', [FLenDenom]);
  SaveSettings;
  RebuildDeck;
  pbDeck.Invalidate;
  RenderInk;
  RecomposeAll;
  InvalidateStatus;
  pbCmd.Invalidate;
end;

procedure TMainForm.SetEdgeWidth(V: Integer);
begin
  V := EnsureRange(V, MIN_PEN, MAX_PEN);
  if V = FEdgeW then Exit;
  FEdgeW := V;
  RenderInk;
  RecomposeAll;
  pbDeck.Invalidate;
  pbScreen.Invalidate;
end;

procedure TMainForm.SetUnits(U: TUnitSystem);
begin
  Act('units ' + IntToStr(Ord(U)));
  FD.Units := U;
  RenderInk;
  RecomposeAll;
  RebuildDeck;
  pbDeck.Invalidate;
  pbCmd.Invalidate;
  Invalidate;
end;

{ ======================================================================== }
{ history                                                                   }
{ ======================================================================== }

procedure TMainForm.PushUndo;
var
  I: Integer;
begin
  { the drawing changed, so whatever would not draw may be gone now }
  FRenderBroken := False;
  { every change to the drawing comes through here, so this is where the
    sheet is marked dirty and the draft clock reset }
  Inc(FEditSeq);
  if FD <> nil then FD.Dirty := True;
  FDraftAge := 0;
  if FD.UndoTop >= UNDO_LEVELS then
  begin
    for I := 0 to UNDO_LEVELS - 2 do
      FD.Undo[I] := FD.Undo[I + 1];
    FD.UndoTop := UNDO_LEVELS - 1;
  end;
  FD.Undo[FD.UndoTop] := FD.Doc.Snapshot;
  Inc(FD.UndoTop);
  FD.RedoTop := 0;
  pbDeck.Invalidate;
end;

function TMainForm.CanUndo: Boolean;
begin
  Result := FD.UndoTop > 0;
end;

function TMainForm.CanRedo: Boolean;
begin
  Result := FD.RedoTop > 0;
end;

procedure TMainForm.DoUndo;
begin
  Trail('undo');
  { the drawing is about to become a different one }
  SetLength(FOpenEdges, 0);
  Act('undo');
  SelectNone;   // the indices it held mean something else now
  if not CanUndo then Exit;
  if FD.RedoTop < UNDO_LEVELS then
  begin
    FD.Redo[FD.RedoTop] := FD.Doc.Snapshot;
    Inc(FD.RedoTop);
  end;
  Dec(FD.UndoTop);
  FD.Doc.RestoreSnap(FD.Undo[FD.UndoTop]);
  ResetTool;
  RenderInk;
  RecomposeAll;
  pbDeck.Invalidate;
end;

procedure TMainForm.DoRedo;
begin
  Trail('redo');
  { the drawing is about to become a different one }
  SetLength(FOpenEdges, 0);
  Act('redo');
  SelectNone;
  if not CanRedo then Exit;
  if FD.UndoTop < UNDO_LEVELS then
  begin
    FD.Undo[FD.UndoTop] := FD.Doc.Snapshot;
    Inc(FD.UndoTop);
  end;
  Dec(FD.RedoTop);
  FD.Doc.RestoreSnap(FD.Redo[FD.RedoTop]);
  ResetTool;
  RenderInk;
  RecomposeAll;
  pbDeck.Invalidate;
end;

{ ======================================================================== }
{ clearing the sheet, with a shake                                          }
{ ======================================================================== }

procedure TMainForm.StartErase;
begin
  if FErasing then Exit;
  Act('clear');
  PushUndo;
  FErasing := True;
  FEraseT := 0;
  Invalidate;
end;

procedure TMainForm.StepErase(Dt: Single);
var
  Amp: Single;
begin
  FEraseT := FEraseT + Dt / 0.7;
  if FEraseT >= 1 then
  begin
    FErasing := False;
    FJitterX := 0;
    FJitterY := 0;
    FD.Doc.Clear;
    RenderInk;
    ResetTool;
    RecomposeAll;
    Invalidate;
    pbDeck.Invalidate;
    Exit;
  end;

  Amp := Round(9 * FUIScale) * (1 - FEraseT);
  FJitterX := Round((Random - 0.5) * 2 * Amp);
  FJitterY := Round((Random - 0.5) * 2 * Amp);

  FInk.SmearDown(1 + Round(6 * FEraseT));
  FInk.FadeAlpha(0.06 + 0.14 * FEraseT);
  RecomposeAll;
  FArt.Grain(0.14 * (1 - FEraseT), 0.05);
  pbScreen.Invalidate;
end;

{ ======================================================================== }
{ the heartbeat                                                             }
{ ======================================================================== }

{ A remote display can change size underneath us (KasmVNC follows the
  browser window).  A window told to fill the screen must keep filling it,
  and there is no reliable notification, so it is watched on the tick. }
procedure TMainForm.FollowScreenSize;
var
  W, H: Integer;
begin
  if FFill = flNone then Exit;
  Screen.UpdateMonitors;
  W := Screen.Width;
  H := Screen.Height;
  if (W < 320) or (H < 240) then Exit;
  if (W = FScrW) and (H = FScrH) then Exit;
  FScrW := W;
  FScrH := H;
  if FFill = flFull then
  begin
    WindowState := wsNormal;
    SetBounds(0, 0, W, H);
    WindowState := wsFullScreen;
  end
  else
  begin
    WindowState := wsNormal;
    SetBounds(0, 0, W, H);
    WindowState := wsMaximized;
  end;
end;

procedure TMainForm.tmrTickTimer(Sender: TObject);
var
  Dt: Single;
  InfoSig: Int64;
  WhatsNewForm: TWhatsNewForm;
  BreakPts: TPointFArray;
  BreakI: Integer;
begin
  Dt := TICK_MS / 1000;

  { the splash comes down once loading is done and it has had its few
    seconds; while it is up nothing else here matters }
  if SplashUp then
  begin
    if SplashFinished and (SplashAge >= SPLASH_MIN_MS) then SplashHide
    else Exit;
  end;
  { long work lets messages through to paint progress, and this fires then
    too: stand down, unless the work is long over and forgot }
  if FBusy then
  begin
    if GetTickCount64 - FBusyAt > 600 then EndBusy;
    Exit;
  end;
  { A dialog has the screen: do nothing.  Ticking 60 times a second under a
    dialog made dragging it skip on compositing machines.  ModalLevel counts
    the stock dialogs too.  Everything here catches up on the next tick. }
  if Application.ModalLevel > 0 then Exit;

  { The entity and groups panels are rebuilt on the tick when what they read
    has changed (including the sheet and open group), not at every place the
    selection changes; some of those are bulk loops over huge selections. }
  if GroupsPanelOn then
  begin
    InfoSig := ((Int64(FD.Doc.FEditSeq) * 131 + FEditSeq) * 131 + Length(FSel)) * 131 +
      FD.Doc.Context * 7 + Int64(PtrUInt(FD.Doc) and $FFFFFF);
    if Length(FSel) > 0 then
      InfoSig := InfoSig * 131 + FSel[0] * 17 + FSel[High(FSel)];
    if InfoSig <> FGrpSig then
    begin
      FGrpSig := InfoSig;
      pbGroups.Invalidate;
    end;
  end;
  if FInfoOn then
  begin
    InfoSig := FEditSeq * 131 + Length(FSel);
    if Length(FSel) > 0 then
      InfoSig := InfoSig * 131 + FSel[0] * 17 + FSel[High(FSel)];
    if InfoSig <> FInfoSig then
    begin
      FInfoSig := InfoSig;
      RebuildInfo;
      pbInfo.Invalidate;
    end;
  end;

  { drawings left by a run that went down, offered once the window is up and
    nothing else is asking }
  if FRecoverToOffer and (FPopup = POP_NONE) and not FCrashToOffer and not SplashUp then
  begin
    FRecoverToOffer := False;
    OfferRecovery;
  end;

  if FCrashToOffer and (FPopup = POP_NONE) then
  begin
    FCrashToOffer := False;
    OfferCrashReport(True);
  end;
  TouchTick;

  FollowScreenSize;
  { the wheel has settled: the full frame }
  if FCameraMoving and not (FOrbiting or FPanning) and (GetTickCount64 - FLastWheel > 220) then
  begin
    FCameraMoving := False;
    RepaintPaper;
    RenderInk;
    RecomposeAll;
    Invalidate;
  end;
  ServiceMotion;
  ServiceHover;
  StepGlide(Dt);

  { the guide buttons follow the guide count, watched here since many places
    change it }
  if (FD.Doc.GuideCount <> FDeckGuides) then
  begin
    FDeckGuides := FD.Doc.GuideCount;
    RebuildDeck;
    pbDeck.Invalidate;
  end;

  { Four seconds up counts as a successful start, so a restored draft that
    crashes is not restored again. }
  if not FStartupDone then
  begin
    FUpTime := FUpTime + Dt;
    if (FUpdatedFrom <> '') and not FWhatsNewShown and (FUpTime > 0.5) then
    begin
      FWhatsNewShown := True;
      hsDialogSkin.UseTheme(Themes[FThemeIdx]);
      WhatsNewForm := TWhatsNewForm.Create(Self);
      try
        WhatsNewForm.ShowRelease(FUpdatedFrom, CurrentVersion);
      finally
        WhatsNewForm.Free;
      end;
    end;
    { last time's crash can be offered once there is a window }
    if (FUpTime > 1.5) and not FAskedAboutCrash then
    begin
      FAskedAboutCrash := True;
      OfferCrashReport(False);
      { Only then look for a newer build: asking during startup held the
        window back until the network answered or gave up. }
      CheckForUpdate(False);
      { and keep the manual beside the program in step }
      KeepHelpCurrent;
    end;
    { the postcard (hsPostcard): second start or later, only once, when
      nothing else is up }
    if (FUpTime > 3.0) and not FPostcardOffered and (Application.ModalLevel = 0) then
    begin
      FPostcardOffered := True;
      if PostcardDue then
      begin
        hsDialogSkin.UseTheme(Themes[FThemeIdx]);
        OfferPostcard(Self, CurrentVersion, False);
      end;
    end;
    if FUpTime > 4.0 then
      FStartupDone := True;
  end;

  { The stick under strain: held still it winds up; moved, it goes slack
    (a drag is changing your mind about where the point goes). }
  if FHoldOn then
  begin
    if (Abs(FMouseSX - FHoldX) > 5) or (Abs(FMouseSY - FHoldY) > 5) then
      FHoldT := 0
    else
    begin
      FHoldT := FHoldT + Dt;
      if FHoldT >= HOLD_BREAK then
      begin
        { It broke: let go of the run and place nothing. }
        FWasLine := FTool = ptLine;
        { the burst goes in the middle of what was destroyed; only a line
          gets its ends flying apart }
        FSnapEnds := FTool = ptLine;
        FSnapA := ScreenOf(FP1);
        FSnapB := PtF(FMouseSX, FMouseSY);
        if StrainOutline(BreakPts) and (Length(BreakPts) > 2) then
        begin
          FSnapM := PtF(0, 0);
          for BreakI := 0 to High(BreakPts) do
            FSnapM := PtF(FSnapM.X + BreakPts[BreakI].X / Length(BreakPts),
                          FSnapM.Y + BreakPts[BreakI].Y / Length(BreakPts));
        end
        else
          FSnapM := PtF((FSnapA.X + FSnapB.X) / 2, (FSnapA.Y + FSnapB.Y) / 2);
        FSnapT := SNAP_RECOIL;
        FHoldOn := False;
        ResetTool;
        FLockOn := False;
        FNoLockUntilMoved := True;
        FScreenDirty := True;
        if FWasLine then
          FCmdMsg := 'Snapped off.'
        else if FTool in [ptPush, ptDrill, ptOffset] then
          FCmdMsg := 'Let go - nothing was moved.'
        else
          FCmdMsg := 'Thrown away - nothing was drawn.';
      end;
      FScreenDirty := True;
    end;
  end;
  if FSnapT > 0 then
  begin
    FSnapT := FSnapT - Dt;
    if FSnapT < 0 then FSnapT := 0;
    FScreenDirty := True;
  end;

  { a draft a couple of seconds after the drawing stops changing, so a busy
    hand is never writing files }
  if FEditSeq <> FDraftSeq then
  begin
    Inc(FDraftAge);
    if FDraftAge > (2000 div TICK_MS) then SaveDraft;
  end;
  try

  if FErasing then
  begin
    StepErase(Dt);
    Exit;
  end;

  { keep the command bar caret blinking }
  if (GetTickCount64 div 500) <> ((GetTickCount64 - TICK_MS) div 500) then
    pbCmd.Invalidate;

  finally
    { one repaint per tick at most, and the camera drawn once for whatever
      moved it }
    FlushView;
    if FScreenDirty then
    begin
      FScreenDirty := False;
      pbScreen.Invalidate;
    end;
  end;
end;

{ ======================================================================== }
{ the view cube                                                             }
{ ======================================================================== }

{ The cube's square, in the chosen corner of the drawing area (top right by
  default, under the VIEW button, as Revit places its own). }
function TMainForm.CubeRect: TRect;
var
  Sz, M, L, T: Integer;
begin
  Sz := CubeSize(FUIScale);
  M := Round(14 * FUIScale);
  { the bottom corners leave room for the scale bar along the foot }
  if FCubeCorner in [0, 2] then L := M else L := pbScreen.Width - M - Sz;
  if FCubeCorner in [0, 1] then T := M
  else T := pbScreen.Height - Round(46 * FUIScale) - Sz;
  Result := Rect(L, T, L + Sz, T + Sz);
end;

{ The cube's patch: its square plus a margin.  The hexagon sits in a square,
  so aiming at its edge puts the pointer off the shape; the crosshair, snap
  mark and chip must not draw over it while someone is trying to click it. }
function TMainForm.CubeZone(X, Y: Integer): Boolean;
var
  R: TRect;
  M: Integer;
begin
  Result := False;
  if (not FCubeOn) or (FD = nil) or (FD.View <> vkOrbit) then
    Exit;
  R := CubeRect;
  M := Round(10 * FUIScale);
  { the hot target's name is written under it, so the zone covers that too }
  Result := (X >= R.Left - M) and (X <= R.Right + M) and
            (Y >= R.Top - M) and (Y <= R.Bottom + M + Round(16 * FUIScale));
end;

{ Is the pointer on the cube itself?  For things that only need to stand
  aside (the wheel, the cursor). }
function TMainForm.OverCube(X, Y: Integer): Boolean;
var
  R: TRect;
  T: TCubeTarget;
begin
  Result := False;
  if (not FCubeOn) or (FD = nil) or (FD.View <> vkOrbit) then
    Exit;
  if FCubeDrag then Exit(True);
  R := CubeRect;
  Result := CubeAt(Proj, (R.Left + R.Right) / 2, (R.Top + R.Bottom) / 2,
    (R.Right - R.Left) / 2 / 1.75, X, Y, T);
end;

procedure TMainForm.PaintViewCube(C: TCanvas);
var
  R: TRect;
  Half: Double;
  Labels: TCubeLabels;
  I, TW: Integer;
  Col: TPix;
begin
  if not FCubeOn then Exit;
  { only in the free 3D view: the paper modes are fixed conventions }
  if (FD = nil) or (FD.View <> vkOrbit) then Exit;

  R := CubeRect;
  if FCubeSkin = nil then FCubeSkin := TArtSurface.Create(16, 16);
  FCubeSkin.SetSize(R.Right - R.Left, R.Bottom - R.Top);
  FCubeSkin.ClearTransparent;
  FCubeSkin.PreserveAlpha := True;

  { room to turn without corners leaving the surface (a cube's long
    diagonal is root three) }
  Half := (R.Right - R.Left) / 2 / 1.75;
  { the pointer's target, or while an orbit is snapping, the one it will
    snap to }
  if FSnapHasHot then
    PaintCube(FCubeSkin, Proj, Half, Theme, True, FSnapHot.Dir)
  else
    PaintCube(FCubeSkin, Proj, Half, Theme, FCubeHasHot, FCubeHot.Dir);
  FCubeSkin.DrawTo(C, R.Left, R.Top);

  { the names, on the canvas because they want a font }
  Labels := CubeLabels(Proj, Half);
  for I := 0 to High(Labels) do
  begin
    Col := OnPix(MixPix(Theme.Panel, Pix(255, 255, 255), 0.30));
    UIFont(C, 8, True, Col);
    TW := C.TextWidth(Labels[I].Name);
    { a face seen nearly edge-on has no room for a word }
    if Labels[I].Facing < 0.26 then Continue;
    C.TextOut(R.Left + Round((R.Right - R.Left) / 2 + Labels[I].X - TW / 2),
      R.Top + Round((R.Bottom - R.Top) / 2 + Labels[I].Y - C.TextHeight('X') / 2),
      Labels[I].Name);
  end;

  { what is under the pointer, in words under the cube }
  if FSnapHasHot and (FSnapHot.Name <> '') then
  begin
    C.Font.Color := PixToColor(Theme.Accent);
    TW := C.TextWidth(FSnapHot.Name);
    C.TextOut(R.Left + (R.Right - R.Left - TW) div 2,
      R.Bottom + Round(2 * FUIScale), FSnapHot.Name);
  end
  else if FCubeHasHot and (FCubeHot.Name <> '') then
  begin
    UIFont(C, 9, True, Theme.Accent);
    TW := C.TextWidth(FCubeHot.Name);
    C.TextOut(R.Left + ((R.Right - R.Left) - TW) div 2,
      R.Bottom + Round(2 * FUIScale), FCubeHot.Name);
  end;
end;

{ A compass in a top corner the cube is not in, while the grid is on: north
  is the green axis, east red, up blue, each drawn as the view shows it
  (flat in plan, turning in iso and orbit) in its axis color. }
procedure TMainForm.PaintCompass(C: TCanvas);
const
  TAGS: array[0..4] of string = ('E', 'W', 'N', 'S', 'U');
var
  R, M, Pad, CX, CY, K, TX, TY, OX, OY: Integer;
  Rt, Up, Dir: TP3;
  DX, DY, L: Double;
  Col: TPix;
begin
  if not FShowGrid or (FD = nil) then Exit;
  R := Round(20 * FUIScale);
  M := Round(14 * FUIScale);
  Pad := Round(12 * FUIScale);
  { top right; top left when the cube is there }
  if FCubeOn and (FD.View = vkOrbit) and (FCubeCorner = 1) then CX := M + Pad + R
  else CX := pbScreen.Width - M - Pad - R;
  CY := M + Pad + R;
  Rt := ViewRight(Proj);
  Up := ViewUp(Proj);
  C.Brush.Style := bsClear;
  C.Pen.Width := 1;
  C.Pen.Color := PixToColor(Theme.Grid);
  C.Ellipse(CX - R, CY - R, CX + R + 1, CY + R + 1);
  UIFont(C, 9, True, Pix(0, 0, 0));
  for K := 0 to High(TAGS) do
  begin
    case K of
      0: Dir := P3(1, 0, 0);
      1: Dir := P3(-1, 0, 0);
      2: Dir := P3(0, 1, 0);
      3: Dir := P3(0, -1, 0);
    else Dir := P3(0, 0, 1);
    end;
    DX := Dot3(Dir, Rt); DY := -Dot3(Dir, Up);
    L := Hypot(DX, DY);
    { pointing at the eye (up, in plan): nothing to draw }
    if L < 0.2 then Continue;
    Col := AxisPix(K div 2);
    C.Pen.Color := PixToColor(Col);
    if K mod 2 = 0 then C.Pen.Width := Max(2, Round(2 * FUIScale)) else C.Pen.Width := 1;
    C.Line(CX, CY, CX + Round(DX * R), CY + Round(DY * R));
    { the letter just past the point, outlined in black like the axes' }
    TX := CX + Round(DX / L * (R * L + Pad * 0.75)) - C.TextWidth(TAGS[K]) div 2;
    TY := CY + Round(DY / L * (R * L + Pad * 0.75)) - C.TextHeight(TAGS[K]) div 2;
    C.Font.Color := clBlack;
    for OX := -1 to 1 do
      for OY := -1 to 1 do
        if (OX <> 0) or (OY <> 0) then C.TextOut(TX + OX, TY + OY, TAGS[K]);
    C.Font.Color := PixToColor(Col);
    C.TextOut(TX, TY, TAGS[K]);
  end;
  C.Pen.Width := 1;
end;

{ The pointer over the cube; True when the cube took it.  Down starts a
  click or a drag; Up decides.  A press that travels orbits, one that does
  not goes to the target under it. }
function TMainForm.CubeMouse(X, Y: Integer; Down, Up: Boolean): Boolean;
var
  R: TRect;
  Half, Az, El, NewAz, NewEl, FitZ, FitX, FitY, Near_: Double;
  T: TCubeTarget;
  Was: Boolean;
begin
  Result := False;
  if (not FCubeOn) or (FD = nil) or (FD.View <> vkOrbit) then
  begin
    FCubeHasHot := False;
    Exit;
  end;

  R := CubeRect;
  Half := (R.Right - R.Left) / 2 / 1.75;

  { a drag that started on the cube keeps it until release, even off it }
  if FCubeDrag and not Down then
  begin
    Result := True;
    if Up then
    begin
      FCubeDrag := False;
      { a drag released within 8 degrees of one of the 26 views snaps to it;
        Ctrl snaps to the nearest from anywhere, as on the orbit tool }
      if FCubeMoved then
      begin
        T := CubeNearest(ViewDir(Proj), Near_);
        if (ssCtrl in GetKeyShiftState) or (Near_ >= Cos(DegToRad(8))) then
        begin
          Az := FD.Az;
          CubeAzEl(T.Dir, Az, El);
          FViewPreset := -1;
          GlideTo(Az, El);
          FCmdMsg := T.Name + '.';
        end;
        Exit;
      end;
      { it never traveled, so it was a click }
      if not FCubeMoved and
         CubeAt(Proj, (R.Left + R.Right) / 2, (R.Top + R.Bottom) / 2,
                Half, X, Y, T) then
      begin
        Az := FD.Az;
        CubeAzEl(T.Dir, Az, El);
        FViewPreset := -1;
        { with something picked (and fit-selection on) it glides to center
          and size it in one movement; otherwise it turns and keeps the
          user's zoom }
        if FCubeFitSel and (Length(FSel) > 0) and
           FitTarget(True, Az, El, FitZ, FitX, FitY) then
          GlideCamera(Az, El, FitZ, FitX, FitY)
        else
          GlideTo(Az, El);
        FCmdMsg := T.Name + '.';
      end;
      Exit;
    end;
    { a press becomes a drag only after it travels more than 4 px; counting
      one pixel made clicks randomly read as drags }
    if (Abs(X - FCubePressX) > 4) or (Abs(Y - FCubePressY) > 4) then
      FCubeMoved := True;
    if FCubeMoved and ((X <> FCubeDragX) or (Y <> FCubeDragY)) then
    begin
      FGlideT := 0;                 { the hand wins over any glide }
      { locals first: see the -O3 note in ServiceMotion }
      NewAz := FD.Az - (X - FCubeDragX) * 0.010;
      NewEl := FD.El + (Y - FCubeDragY) * 0.010;
      if NewEl < -1.45 then NewEl := -1.45;
      if NewEl > 1.45 then NewEl := 1.45;
      FD.Az := NewAz;
      FD.El := NewEl;
      FViewPreset := -1;
      HoldTurn;
      FCubeDragX := X;
      FCubeDragY := Y;
      FCameraMoving := True;
      FLastWheel := GetTickCount64;
      { the paper too: the axes and ground grid are ruled on it }
      RepaintPaper;
      RenderInk;
      RecomposeAll;
      Invalidate;
    end;
    Exit;
  end;

  Was := FCubeHasHot;
  FCubeHasHot := CubeAt(Proj, (R.Left + R.Right) / 2,
    (R.Top + R.Bottom) / 2, Half, X, Y, T);
  if FCubeHasHot then FCubeHot := T;
  if FCubeHasHot <> Was then FScreenDirty := True
  else if FCubeHasHot then FScreenDirty := True;

  if not FCubeHasHot then Exit;
  Result := True;
  if Down then
  begin
    FCubeDrag := True;
    FCubeMoved := False;
    FCubeDragX := X;
    FCubeDragY := Y;
    FCubePressX := X;
    FCubePressY := Y;
    { a cube drag turns about the same point a click glides about }
    FTurnPivot := TurnPivot;
    FTurnAnchor := ScreenOf(FTurnPivot);
    FTurnAnchored := not (IsNan(FTurnAnchor.X) or IsNan(FTurnAnchor.Y) or
                          IsInfinite(FTurnAnchor.X) or IsInfinite(FTurnAnchor.Y)) and
                     (Abs(FTurnAnchor.X) < 1E6) and (Abs(FTurnAnchor.Y) < 1E6);
  end;
end;

{ What a turn turns about: the middle of the selection, or of the whole
  drawing when nothing is picked (Revit's rule).  Never the world origin,
  which would swing a drawing far from zero out of the window. }
function TMainForm.TurnPivot: TP3;
begin
  if (FD = nil) or not FD.Doc.MiddleOf(FSel, Result) then Result := P3(0, 0, 0);
end;

{ Put the pivot back where it was on screen after the angles moved.  A
  TProjector turns about the world origin, so every turn gets its pivot this
  way.  A pivot that projects to nonsense is ignored rather than adding
  millions to the view position. }
procedure TMainForm.HoldTurn;
var
  OP: TPointF;
begin
  if not FTurnAnchored then Exit;
  OP := ScreenOf(FTurnPivot);
  if IsNan(OP.X) or IsNan(OP.Y) or IsInfinite(OP.X) or IsInfinite(OP.Y) then Exit;
  if (Abs(OP.X) > 1E6) or (Abs(OP.Y) > 1E6) then Exit;
  FD.ViewX := FD.ViewX + (FTurnAnchor.X - OP.X);
  FD.ViewY := FD.ViewY + (FTurnAnchor.Y - OP.Y);
end;

{ What a fit would come out as, without doing it, so a glide can aim at its
  final framing.  Computed at the destination angles, which decide where the
  middle lands. }
function TMainForm.FitTarget(OnSelection: Boolean; AzT, ElT: Double;
  out NewZoom, NewOX, NewOY: Double): Boolean;
var
  Lo, Hi, Mid: TP3;
  V: TProjector;
  P: TPointF;
  BaseP, W, H, Z: Double;
begin
  NewZoom := FD.Zoom;
  NewOX := FD.ViewX;
  NewOY := FD.ViewY;
  if OnSelection and (Length(FSel) > 0) then
    Result := FD.Doc.SpanOf(FSel, Lo, Hi)
  else
    Result := FD.Doc.Bounds(Lo, Hi);
  if not Result then Exit;

  BaseP := PixelsPerUnit(FD.Units, CurScale, Screen.PixelsPerInch);
  case FD.View of
    vkIso:
      begin
        W := Max((Abs(Hi.X - Lo.X) + Abs(Hi.Y - Lo.Y)) * ISO_COS, 1E-6);
        H := Max((Hi.X - Lo.X + Hi.Y - Lo.Y) * ISO_SIN + (Hi.Z - Lo.Z), 1E-6);
      end;
    vkOrbit:
      begin
        { the diagonal is a safe bound from any camera angle }
        W := Max(Sqrt(Sqr(Hi.X - Lo.X) + Sqr(Hi.Y - Lo.Y) + Sqr(Hi.Z - Lo.Z)), 1E-6);
        H := W;
      end;
  else
    begin
      W := Max(Hi.X - Lo.X, 1E-6);
      H := Max(Hi.Y - Lo.Y, 1E-6);
    end;
  end;
  Z := Min((FArt.Width * 0.80) / (W * BaseP), (FArt.Height * 0.80) / (H * BaseP));
  if Z < ZOOM_MIN then Z := ZOOM_MIN;
  if Z > ZOOM_MAX then Z := ZOOM_MAX;
  NewZoom := Z;

  { where the middle would land, at that zoom and those angles }
  Mid := P3((Lo.X + Hi.X) / 2, (Lo.Y + Hi.Y) / 2, (Lo.Z + Hi.Z) / 2);
  V.Kind := FD.View;
  V.Ppu := BaseP * Z;
  V.OX := 0;
  V.OY := 0;
  V.Az := AzT;
  V.El := ElT;
  P := Project(V, Mid);
  NewOX := FArt.Width / 2 - P.X;
  NewOY := FArt.Height / 2 - P.Y;
end;

{ A glide that carries the framing too: turns, slides and zooms at once, so
  the target arrives centered and sized without a jump at either end. }
procedure TMainForm.GlideCamera(Az, El, Zoom, OX, OY: Double);
begin
  if FD = nil then Exit;
  GlideTo(Az, El);
  FGlideZ0 := FD.Zoom;
  FGlideZ1 := Zoom;
  FGlideOX0 := FD.ViewX;
  FGlideOX1 := OX;
  FGlideOY0 := FD.ViewY;
  FGlideOY1 := OY;
  { worth moving for the framing alone (the FIT button) }
  if (FGlideT = 0) and
     ((Abs(FGlideZ1 - FGlideZ0) > 1E-4 * Max(1, FGlideZ0)) or
      (Abs(FGlideOX1 - FGlideOX0) > 0.5) or (Abs(FGlideOY1 - FGlideOY0) > 0.5)) then
  begin
    FGlideD0 := FGlideD1;
    FGlideT := 1E-6;
    FGlideAt := GetTickCount64;
    FCameraMoving := True;
  end;
  FGlideFrame := FGlideT > 0;
end;

{ The view an orbit would snap to if released now: the nearest of the cube's
  26 (6 faces, 12 edges, 8 corners).  Free 3D view only. }
function TMainForm.OrbitSnapTarget(out T: TCubeTarget): Boolean;
var
  Near_: Double;
begin
  Result := False;
  if (FD = nil) or (FD.View <> vkOrbit) then Exit;
  T := CubeNearest(ViewDir(Proj), Near_);
  { Every direction has a nearest of the 26, worst case 27.4 degrees away
    (TestOrbitSnapFindsTheNearestView), so there is no distance limit; a
    limit would make the key silently do nothing. }
  Result := Near_ > -1;
end;

{ Let go and glide into it, so you do not lose track of the model. }
procedure TMainForm.SnapOrbitToNearest;
var
  T: TCubeTarget;
  Az, El: Double;
begin
  if not OrbitSnapTarget(T) then Exit;
  Az := FD.Az;
  { straight up or down says nothing about which way round, so CubeAzEl
    keeps the current turn }
  CubeAzEl(T.Dir, Az, El);
  GlideTo(Az, El);
  FCmdMsg := 'Snapped to ' + T.Name + '.';
  Trail('orbit snapped to ' + T.Name);
end;

{ Ctrl+arrow: one step round the 26, gliding as a cube click does.  3D view
  only. }
procedure TMainForm.StepCubeView(Key: Word);
var
  T: TCubeTarget;
  Near_, Az, El: Double;
  Dir: TP3;
  Step: TCubeStep;
begin
  if (FD = nil) or (FD.View <> vkOrbit) then Exit;
  case Key of
    VK_LEFT:  Step := csLeft;
    VK_RIGHT: Step := csRight;
    VK_UP:    Step := csUp;
  else
    Step := csDown;
  end;
  { from where a running glide is going, so a quick second press carries on }
  if FGlideT > 0 then
    Az := FGlideAz1
  else
    Az := FD.Az;
  if FGlideT > 0 then
    T := CubeNearest(P3(Cos(FGlideEl1) * Cos(FGlideAz1),
      Cos(FGlideEl1) * Sin(FGlideAz1), Sin(FGlideEl1)), Near_)
  else
    T := CubeNearest(ViewDir(Proj), Near_);
  Dir := CubeStep(T.Dir, Az, Step);
  if (Dir.X = 0) and (Dir.Y = 0) and (Step in [csLeft, csRight]) then
  begin
    { looking straight down or up: turn the drawing a side's worth }
    if Step = csRight then Az := Az + Pi / 4 else Az := Az - Pi / 4;
    El := FD.El;
    if FGlideT > 0 then El := FGlideEl1;
  end
  else
    CubeAzEl(Dir, Az, El);
  T := CubeNearest(Dir, Near_);
  FViewPreset := -1;
  GlideTo(Az, El);
  FCmdMsg := T.Name + '  - Ctrl and the arrows walk round the view cube.';
  Trail('cube step to ' + T.Name);
end;

procedure TMainForm.GlideTo(Az, El: Double);
var
  D: Double;

  { where the camera stands, as a direction }
  function DirOf(A, E: Double): TP3;
  begin
    Result := P3(Cos(E) * Cos(A), Cos(E) * Sin(A), Sin(E));
  end;

begin
  if FD = nil then Exit;
  FGlideAz0 := FD.Az;
  FGlideEl0 := FD.El;
  { start a camera move, the short way round; none if already there }
  D := Az - FD.Az;
  while D > Pi do D := D - 2 * Pi;
  while D < -Pi do D := D + 2 * Pi;
  FGlideAz1 := FD.Az + D;
  FGlideEl1 := El;
  if (Abs(D) < 1E-4) and (Abs(El - FD.El) < 1E-4) then
  begin
    FGlideT := 0;
    Exit;
  end;
  { the two camera directions, which StepGlide interpolates }
  FGlideD0 := DirOf(FGlideAz0, FGlideEl0);
  FGlideD1 := DirOf(FGlideAz1, FGlideEl1);
  { what it turns about, and where that is on screen now }
  FTurnPivot := TurnPivot;
  FTurnAnchor := ScreenOf(FTurnPivot);
  FTurnAnchored := not (IsNan(FTurnAnchor.X) or IsNan(FTurnAnchor.Y) or
                        IsInfinite(FTurnAnchor.X) or IsInfinite(FTurnAnchor.Y)) and
                   (Abs(FTurnAnchor.X) < 1E6) and (Abs(FTurnAnchor.Y) < 1E6);
  FGlideT := 1E-6;
  FGlideAt := GetTickCount64;
  FGlideFrame := False;
  FCameraMoving := True;
end;

{ Dt is unused: this runs on the clock, not on how often the timer fired. }
procedure TMainForm.StepGlide(Dt: Double);
var
  K, NewAz, NewEl, Dot, Ang, S0, S1, Flat: Double;
  NewZ, NewOX, NewOY: Double;
  D: TP3;
begin
  if FGlideT <= 0 then Exit;
  if FD = nil then
  begin
    FGlideT := 0;
    Exit;
  end;
  FGlideT := (GetTickCount64 - FGlideAt) / (GLIDE_SECONDS * 1000);
  if FGlideT >= 1 then FGlideT := 1;
  { ease in and out, so it reads as the model turning }
  K := FGlideT * FGlideT * (3 - 2 * FGlideT);

  { The camera rolls along the great circle between the two directions at a
    constant rate, rather than interpolating azimuth and elevation, which
    swings it sideways on the way from corner to far corner. }
  Dot := FGlideD0.X * FGlideD1.X + FGlideD0.Y * FGlideD1.Y +
         FGlideD0.Z * FGlideD1.Z;
  if Dot > 1 then Dot := 1;
  if Dot < -1 then Dot := -1;
  Ang := ArcCos(Dot);
  if Ang < 1E-6 then
    D := FGlideD1
  else
  begin
    S0 := Sin((1 - K) * Ang) / Sin(Ang);
    S1 := Sin(K * Ang) / Sin(Ang);
    D := P3(FGlideD0.X * S0 + FGlideD1.X * S1,
            FGlideD0.Y * S0 + FGlideD1.Y * S1,
            FGlideD0.Z * S0 + FGlideD1.Z * S1);
  end;

  { and back into turn and tilt }
  Flat := Sqrt(D.X * D.X + D.Y * D.Y);
  if Flat > 1E-9 then NewAz := ArcTan2(D.Y, D.X) else NewAz := FD.Az;
  NewEl := ArcTan2(D.Z, Flat);
  if NewEl < -1.45 then NewEl := -1.45;
  if NewEl > 1.45 then NewEl := 1.45;
  { the arc is the short way round the sphere, but the azimuth can come out
    the long way round; keep it near where it was }
  while NewAz - FD.Az > Pi do NewAz := NewAz - 2 * Pi;
  while NewAz - FD.Az < -Pi do NewAz := NewAz + 2 * Pi;
  { land exactly where aimed }
  if FGlideT >= 1 then
  begin
    NewAz := FGlideAz1;
    NewEl := FGlideEl1;
  end;
  FD.Az := NewAz;
  FD.El := NewEl;
  if FGlideFrame then
  begin
    { zoom interpolates geometrically: halfway from 1x to 4x is 2x }
    NewZ := FGlideZ0 * Exp(Ln(Max(1E-9, FGlideZ1 / Max(1E-9, FGlideZ0))) * K);
    NewOX := FGlideOX0 + (FGlideOX1 - FGlideOX0) * K;
    NewOY := FGlideOY0 + (FGlideOY1 - FGlideOY0) * K;
    if FGlideT >= 1 then
    begin
      NewZ := FGlideZ1;
      NewOX := FGlideOX1;
      NewOY := FGlideOY1;
    end;
    { through a local and clamped by hand (see FitView and ServiceMotion on
      -O3) }
    if NewZ < ZOOM_MIN then NewZ := ZOOM_MIN;
    if NewZ > ZOOM_MAX then NewZ := ZOOM_MAX;
    FD.Zoom := NewZ;
    FD.ViewX := NewOX;
    FD.ViewY := NewOY;
  end
  else
    HoldTurn;
  if FGlideT >= 1 then
  begin
    FGlideT := 0;
    FCameraMoving := False;
    { the framing came with the glide, so nothing more on arrival }
    RepaintPaper;
  end
  else
    FCameraMoving := True;
  { the axes and grid live on the paper and must turn too (see CubeMouse) }
  RepaintPaper;
  RenderInk;
  RecomposeAll;

  { Paint now with Update, not just Invalidate: the tick-driven glide keeps
    the message loop too busy to paint between steps, so without this the
    move appears to teleport. }
  pbScreen.Invalidate;
  pbScreen.Update;
end;

{ ======================================================================== }
{ keyboard                                                                  }
{ ======================================================================== }

procedure TMainForm.FormKeyPress(Sender: TObject; var Key: char);
begin
  if FBusy then Exit;

  { while a note or a dimension's label is being typed, everything is text }
  if ((FTool = ptText) and (FStage = 1)) or (FDimEdit >= 0) then
  begin
    if Key >= ' ' then
    begin
      FInput := FInput + Key;
      pbCmd.Invalidate;
      Key := #0;
    end;
    Exit;
  end;

  { one note picked and nothing typed: + and - change its text size by a
    quarter, between half and four times (the box follows, as in SketchUp) }
  if (FInput = '') and (FStage = 0) and (Length(FSel) = 1) and
     (FD.Doc[FSel[0]].Kind = ekText) and (Key in ['+', '=', '-']) then
  begin
    PushUndo;
    if Key = '-' then
      FD.Doc.SetNoteSize(FSel[0], FD.Doc.NoteSize(FSel[0]) / 1.25)
    else
      FD.Doc.SetNoteSize(FSel[0], FD.Doc.NoteSize(FSel[0]) * 1.25);
    FCmdMsg := Format('Text at %d%% of normal.  + and - change it.',
      [Round(FD.Doc.NoteSize(FSel[0]) * 100)]);
    RenderInk;
    RecomposeAll;
    pbCmd.Invalidate;
    Key := #0;
    Exit;
  end;

  { right after a copy, 3x or /3 makes an array: x, * and / go in with the
    digits, and Enter does the rest }
  if FArray.Live and (Key in ['x', 'X', '*', '/']) and
     ((FInput = '') or (FInput[1] in ['0'..'9'])) and
     (Pos('x', FInput) = 0) and (Pos('*', FInput) = 0) and (Pos('/', FInput) = 0) then
  begin
    if Key = 'X' then Key := 'x';
    FInput := FInput + Key;
    pbCmd.Invalidate;
    Key := #0;
    Exit;
  end;
  if FArray.Live and (Key in ['0'..'9']) and (FInput <> '') and (FInput[1] in ['x', '*', '/']) then
  begin
    FInput := FInput + Key;
    pbCmd.Invalidate;
    Key := #0;
    Exit;
  end;

  { circle and arc sides: + and - step the count, and s goes into the input
    for SketchUp's 24s (or s24) }
  if (FTool in [ptCircle, ptArc]) and (FInput = '') and (Key in ['+', '=', '-']) then
  begin
    if FTool = ptCircle then
    begin
      if Key = '-' then FSidesCircle := Max(3, FSidesCircle - 1)
      else FSidesCircle := Min(360, FSidesCircle + 1);
      FCmdMsg := Format('%d sides.  + and - change it, or type 24s.', [FSidesCircle]);
    end
    else
    begin
      if Key = '-' then FSidesArc := Max(2, FSidesArc - 1)
      else FSidesArc := Min(360, FSidesArc + 1);
      FCmdMsg := Format('%d segments.  + and - change it, or type 12s.', [FSidesArc]);
    end;
    pbScreen.Invalidate;
    pbCmd.Invalidate;
    Key := #0;
    Exit;
  end;
  if (FTool in [ptCircle, ptArc]) and (Key in ['s', 'S']) and
     ((FInput = '') or (FInput[1] in ['0'..'9'])) and (Pos('s', FInput) = 0) then
  begin
    FInput := FInput + 's';
    pbCmd.Invalidate;
    Key := #0;
    Exit;
  end;

  { a leading '/' starts a typed command; after that every character is text,
    otherwise letters are tool shortcuts }
  if (Copy(FInput, 1, 1) = '/') and (Key >= ' ') then
  begin
    FInput := FInput + Key;
    { and the list narrows with it }
    SyncCmdList;
    pbCmd.Invalidate;
    Key := #0;
    Exit;
  end;

  { x, comma or semicolon separate a rectangle's sides while it waits for its
    size; elsewhere letters stay shortcuts.  The first slash works too, for
    the number pad (2/2 is a two foot square); a later slash is a fraction
    (2/2 1/2).  Only once a number is typed: a bare slash starts a command. }
  if ((Key in ['x', 'X', ',', ';']) or
      ((Key = '/') and (FInput <> '') and (FInput[1] in ['0'..'9']) and
       (Pos('x', FInput) = 0))) and
     (FTool = ptRect) and (FStage = 1) then
  begin
    FInput := FInput + 'x';
    FCmdMsg := '';
    pbCmd.Invalidate;
    pbScreen.Invalidate;
    Key := #0;
    Exit;
  end;

  { a sum in a length (8' + 8", 8'17" / 2; see ParseLen): plus and times once
    something is typed, brackets any time }
  if ((Key in ['+', '*', ')']) and (FInput <> '')) or (Key = '(') then
  begin
    FInput := FInput + Key;
    FCmdMsg := '';
    pbCmd.Invalidate;
    pbScreen.Invalidate;
    Key := #0;
    Exit;
  end;

  { brackets and commas for coordinates: [x,y,z] a point, <x,y,z> an offset }
  if Key in ['0'..'9', '.', '/', '''', '"', ' ', '-', ',', ';',
             '[', ']', '<', '>', ':'] then
  begin
    FInput := FInput + Key;
    FCmdMsg := '';
    { a slash with nothing before it starts a command: bring up the list }
    if FInput = '/' then SyncCmdList;
    pbCmd.Invalidate;
    pbScreen.Invalidate;
    Key := #0;
  end;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
var
  Handled: Boolean;
  Step: Double;

  { SketchUp's arrows name an axis by color in every view: right red, left
    green, up blue.  A lock is on the axis, not a direction along it. }
  function ArrowAxis(K: word): Integer;
  begin
    case K of
      VK_RIGHT: Result := 0;      // red, X
      VK_LEFT: Result := 2;       // green, Y
      VK_UP: Result := 4;         // blue, Z
      VK_PRIOR: Result := 4;
      VK_NEXT: Result := 5;
    else
      Result := -1;               // down lets go
    end;
  end;

  { nudging the cursor with arrows wants a screen direction instead }
  function ArrowStep(K: word): Integer;
  begin
    if FD.View = vkIso then
      case K of
        VK_RIGHT: Result := 0;
        VK_LEFT: Result := 1;
        VK_PRIOR: Result := 2;
        VK_NEXT: Result := 3;
        VK_UP: Result := 4;
      else
        Result := 5;
      end
    else
      case K of
        VK_RIGHT: Result := 0;
        VK_LEFT: Result := 1;
        VK_UP: Result := 2;
      else
        Result := 3;
      end;
  end;

  procedure Arrow(K: word);
  var
    D: TP3;
  begin
    if (FTool in [ptLine, ptMove]) and (FStage = 1) then
    begin
      FDirLock := ArrowAxis(K);
      { recorded for replay: the length alone does not say which way }
      Act('dir ' + IntToStr(FDirLock));
      if FDirLock < 0 then FCmdMsg := 'Free again.'
      else FCmdMsg := 'Locked to ' + AxisName(FDirLock) + '.';
    end
    else if FTool in [ptRotate, ptProtractor] then
    begin
      { the arrow names the axis the protractor turns about }
      FRotAxisIx := ArrowAxis(K);
      if FRotAxisIx < 0 then
        FCmdMsg := 'Plane from whatever is under the cursor again.'
      else
      begin
        FRotAxis := AxisDir(FRotAxisIx);
        FCmdMsg := 'Turning about ' + AxisName(FRotAxisIx) + '.';
      end;
      pbScreen.Invalidate;
      pbCmd.Invalidate;
      Exit;
    end
    else
    begin
      D := AxisDir(ArrowStep(K));
      Step := SnapStep;
      if Step <= 0 then Step := 1 / 12;
      if ssShift in Shift then
      begin
        JumpSnap(Round(Sign(ScreenOf(P3(FCur.X + D.X, FCur.Y + D.Y, FCur.Z + D.Z)).X
                             - ScreenOf(FCur).X)),
                 Round(Sign(ScreenOf(P3(FCur.X + D.X, FCur.Y + D.Y, FCur.Z + D.Z)).Y
                             - ScreenOf(FCur).Y)));
        Exit;
      end;
      if ssCtrl in Shift then Step := Step / 4;
      FCur := P3(FCur.X + D.X * Step, FCur.Y + D.Y * Step, FCur.Z + D.Z * Step);
      FSnapKind := snNone;
      FMouseSX := Round(ScreenOf(FCur).X);
      FMouseSY := Round(ScreenOf(FCur).Y);
    end;
    pbScreen.Invalidate;
    pbCmd.Invalidate;
    InvalidateStatus;
  end;

begin
  { picking for the stairs: Esc goes back to the dialog as it was }
  if (FStairPick > 0) and (Key = VK_ESCAPE) then
  begin
    FStairPick := 0;
    FCmdMsg := '';
    Key := 0;
    Application.QueueAsyncCall(@StairResume, 0);
    Exit;
  end;
  { the source window's Pick ends on Esc, before anything else sees it }
  if FTextPick and (Key = VK_ESCAPE) then
  begin
    SourcePick(False);
    if SourceForm <> nil then SourceForm.PickEnded;
    Key := 0;
    Exit;
  end;
  if FBusy then Exit;
  Handled := True;

  if ssCtrl in Shift then
  begin
    case Key of
      VK_Z: DoUndo;
      VK_Y: DoRedo;
      VK_G: MakeGroup;     { SketchUp's Ctrl+G }
      { what is typed, when something is; otherwise the drawing }
      VK_C:
        if FInput <> '' then
        begin
          Clipboard.AsText := FInput;
          FCmdMsg := 'Copied what is typed.';
        end
        else CopySelection(False);
      VK_X: CopySelection(True);
      { clipboard text goes into the typing when there is typing already or
        it is a command; otherwise it is the drawing's paste }
      VK_V:
        if Clipboard.HasFormat(CF_TEXT) and
           ((FInput <> '') or (Copy(TrimLeft(Clipboard.AsText), 1, 1) = '/')) then
        begin
          if FInput = '' then FInput := TrimLeft(Clipboard.AsText)
          else FInput := FInput + Clipboard.AsText;
          { one line only }
          if Pos(#10, FInput) > 0 then FInput := Copy(FInput, 1, Pos(#10, FInput) - 1);
          FInput := StringReplace(FInput, #13, '', [rfReplaceAll]);
          if Copy(FInput, 1, 1) = '/' then SyncCmdList;
          pbCmd.Invalidate;
        end
        else PasteClip;
      VK_S: if ssShift in Shift then DoSaveAs else DoSave;
      VK_O: DoOpen;
      VK_M: ShowFileMenu;
      VK_E: DoExport;
      VK_P: DoPrint;
      VK_N: NewDrawing(-1);
      VK_T: NewDrawing(-1);
      VK_W: CloseDrawing(FTabIdx);
      VK_TAB: SelectDrawing((FTabIdx + 1) mod Length(FDrawings));
    else
      Handled := False;
    end;
    if Handled then
    begin
      Key := 0;
      Exit;
    end;
  end;

  case Key of
    VK_F1: begin ShowAbout; Key := 0; Exit; end;
    VK_DELETE:
      begin
        { Delete takes the selection; with nothing selected, clearing the
          sheet asks first (it is easy to hit). }
        if Length(FSel) > 0 then
          DeleteSelection
        else if FD.Doc.Live = 0 then
          FCmdMsg := 'Nothing selected, and nothing to clear.'
        else if MessageDlg('Clear the sheet?',
             Format('Throw away all %d things on "%s"?'#13#10#13#10 +
               'Ctrl+Z will bring them back.',
               [FD.Doc.Live, FD.Name]),
             mtConfirmation, [mbYes, mbNo], 0) = mrYes then
        begin
          PushUndo;
          StartErase;          { the shake, as the discard }
        end
        else
          FCmdMsg := 'Left alone.';
        Key := 0;
        Exit;
      end;
  end;

  { With the tape in hand, Ctrl cycles what it leaves (SketchUp's key for
    it), and says the mode each time. }
  if (Key = VK_CONTROL) and (FTool = ptMeasure) then
  begin
    FTapeDrop := (FTapeDrop + 1) mod 4;
    FCmdMsg := 'The tape leaves ' + TapeDropSays + '.';
    pbCmd.Invalidate;
    Key := 0;
    Exit;
  end;

  if Key = VK_MENU then
  begin
    { Mid-line, Alt steps through the inferences (SketchUp's, see
      TInferMode); before the first click it holds the working plane.
      For the arc it is the tangent lock; we already know the edge the
      first click landed on. }
    if (FTool = ptArc) and (FStage = 2) then
    begin
      if not FArcTanHas then
        FCmdMsg := 'Nothing to be tangent to - start an arc on an edge and ' +
          'Alt runs it out of that edge smoothly.'
      else
      begin
        FArcTanLock := not FArcTanLock;
        if FArcTanLock then
          FCmdMsg := 'Tangent to the edge it starts on, held.  Alt again to ' +
            'pull the bulge by hand.'
        else
          FCmdMsg := 'The bulge follows the cursor again.';
      end;
      FCur := ResolveSnapAt(FMouseSX, FMouseSY);
      InvalidateStatus;
      pbCmd.Invalidate;
      pbScreen.Invalidate;
      Key := 0;
      Exit;
    end;

    { the protractor's Alt: stop taking the plane from the face under the
      cursor }
    if (FTool in [ptRotate, ptProtractor]) and (FStage = 0) then
    begin
      FRotFree := not FRotFree;
      if FRotFree then
        FCmdMsg := 'Free of the face under the cursor: it turns flat unless ' +
          'an arrow picks a plane.  Alt again to follow faces.'
      else
        FCmdMsg := 'Following the face under the cursor again.';
      pbCmd.Invalidate;
      pbScreen.Invalidate;
      Key := 0;
      Exit;
    end;

    { the offset's Alt: keep a tight corner's overlaps instead of tidying
      them (see OffsetLoop) }
    if (FTool = ptOffset) and (FStage >= 1) then
    begin
      FOffsetRaw := not FOffsetRaw;
      if FOffsetRaw then
        FCmdMsg := 'Overlaps kept: a corner taken in further than it is ' +
          'round comes back as it falls, loops and all.  Alt again to tidy them.'
      else
        FCmdMsg := 'Overlaps tidied, which is the usual way.';
      pbCmd.Invalidate;
      pbScreen.Invalidate;
      Key := 0;
      Exit;
    end;

    if (FTool = ptLine) and (FStage >= 1) then
    begin
      if FInferMode = High(TInferMode) then FInferMode := Low(TInferMode)
      else Inc(FInferMode);
      case FInferMode of
        imNoLinear: FCmdMsg := 'Inferences: the points only - no axis, ' +
          'nothing parallel.  Alt again for parallel and square.';
        imParPerp: FCmdMsg := 'Inferences: parallel and square to the last ' +
          'edge only.  Alt again for all of them.';
      else
        FCmdMsg := 'Inferences: all of them.  Alt steps through them.';
      end;
      { resolve the cursor again now, or the key seems to do nothing until
        the mouse twitches }
      FCur := ResolveSnapAt(FMouseSX, FMouseSY);
      InvalidateStatus;
      pbCmd.Invalidate;
      pbScreen.Invalidate;
      Key := 0;
      Exit;
    end;
    { otherwise Alt steps through the flat planes and latches, for drawing
      in mid air }
    if FD.View = vkPlan then
    begin
      { in plan the upright planes are edge-on and nothing drawn in them
        could be seen, so plan stays on the ground and says so }
      FD.Plane := plXY;
      FPlaneHeld := False;
      FCmdMsg := 'Plan draws flat on the ground.  ISO or 3D to work upright.';
      pbCmd.Invalidate;
      Key := 0;
      Exit;
    end;
    FD.Plane := TPlane((Ord(FD.Plane) + 1) mod 3);
    FPlaneHeld := True;
    case FD.Plane of
      plXZ: FCmdMsg := 'Plane held upright, XZ.  Alt again to change, Esc to follow faces.';
      plYZ: FCmdMsg := 'Plane held on the side, YZ.  Alt again to change, Esc to follow faces.';
    else
      FCmdMsg := 'Plane held flat, XY.  Alt again to change, Esc to follow faces.';
    end;
    RepaintPaper;
    RenderInk;
    RecomposeAll;
    pbCmd.Invalidate;
    Key := 0;
    Exit;
  end;

  { while a note, label or /command is typed, letters are letters; only
    keys that finish or edit it are handled }
  if ((FTool = ptText) and (FStage = 1)) or (Copy(FInput, 1, 1) = '/') or
     (FDimEdit >= 0) then
  begin
    case Key of
      { up and down walk the open command list; Tab completes to the row
        without running it }
      VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT:
        if FPopup = POP_CMDS then MoveCmdHighlight(Key) else Exit;
      VK_TAB:
        if (FPopup = POP_CMDS) and (FPopupHot >= 0) then
        begin
          FInput := '/' + CMD_LIST[FCmdOrder[FPopupHot]].Name;
          SyncCmdList;
          pbCmd.Invalidate;
        end
        else
          Exit;
      VK_RETURN:
        { Shift+Enter is another line of the note; Enter finishes it }
        if (ssShift in Shift) and (FTool = ptText) and (FStage = 1) then
        begin
          FInput := FInput + #10;
          pbCmd.Invalidate;
        end
        { Enter takes the highlighted row, unless what is typed is already
          a whole command (/line runs /line) }
        else if (FPopup = POP_CMDS) and (FPopupHot >= 0) and
                not ExactCmd(FInput) then
          TakeCmdHighlight
        else
        begin
          if FPopup = POP_CMDS then ClosePopup;
          CommandEnter;
        end;
      VK_ESCAPE:
        if FDimEdit >= 0 then
        begin
          FDimEdit := -1;
          FInput := '';
          FCmdMsg := 'Left as it was.';
          pbCmd.Invalidate;
          pbScreen.Invalidate;
        end
        { the list first, then the typing, then the tool: one press each }
        else if FPopup = POP_CMDS then
        begin
          ClosePopup;
          FInput := '';
          pbCmd.Invalidate;
        end
        else
          ResetTool;
      VK_BACK:
        begin
          if FInput <> '' then SetLength(FInput, Length(FInput) - 1);
          { erasing letters widens the list; erasing the slash puts it away }
          SyncCmdList;
          pbCmd.Invalidate;
          pbScreen.Invalidate;
        end;
    else
      Exit;      // let OnKeyPress see it
    end;
    Key := 0;
    Exit;
  end;

  case Key of
    VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT:
      { the command list takes up and down while it is open }
      if (FPopup = POP_CMDS) and (Key in [VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT]) then
        MoveCmdHighlight(Key)
      { Ctrl turns the view a cube step instead, in 3D and only between
        shapes, so a mid-line arrow lock is never taken away }
      else if (ssCtrl in Shift) and (FD.View = vkOrbit) and
         (FStage = 0) and (Key in [VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN]) then
        StepCubeView(Key)
      { before a shape is under way the arrows pick the plane; after, they
        lock a direction, which only means something for a line }
      else if (FTool in [ptRect, ptCircle, ptArc]) or
         ((FTool = ptLine) and (FStage = 0)) then
        PlaneByArrow(Key)
      else
        Arrow(Key);
    { Enter takes the highlighted row unless what is typed is already a
      whole command }
    VK_RETURN:
      if (FPopup = POP_CMDS) and (FPopupHot >= 0) and
         not ExactCmd(FInput) then TakeCmdHighlight
      else
      begin
        if FPopup = POP_CMDS then ClosePopup;
        CommandEnter;
      end;
    { and Tab completes without running }
    VK_TAB: if (FPopup = POP_CMDS) and (FPopupHot >= 0) then
            begin
              FInput := '/' + CMD_LIST[FCmdOrder[FPopupHot]].Name;
              SyncCmdList;
              pbCmd.Invalidate;
            end
            else
              SetTool(TTool((Ord(FTool) + 1) mod (Ord(High(TTool)) + 1)));
    { Space is SketchUp's select; mid-shape it still finishes the shape.
      Once something is typed a space is a space (sums like 8' + 8"). }
    VK_SPACE:
      if (FStage = 0) and (FInput = '') then SetTool(ptSelect)
      else if FInput <> '' then Handled := False
      else CommandEnter;
    VK_ESCAPE:
      begin
        if FSliceEdit <> 0 then
        begin
          FSliceEdit := 0;
          FInput := '';
          FCmdMsg := 'Left as it was.';
          pbSlice.Invalidate;
        end
        else if FPopup <> POP_NONE then
          ClosePopup
        { One press per thing: the typing, then the shape in progress with
          all its locks (ResetTool), then a held plane, the selection, the
          open group.  The shape comes before the held plane, or ending a
          line took several presses. }
        else if FInput <> '' then
          FInput := ''
        else if FStage > 0 then
          ResetTool
        else if FPlaneHeld then
        begin
          FPlaneHeld := False;
          FCmdMsg := 'Following the face under the cursor again.';
        end
        else if Length(FSel) > 0 then
          SelectNone
        else if FD.Doc.Context <> 0 then
          CloseGroup
        else
          SetTool(ptSelect);
        FCmdMsg := '';
        pbCmd.Invalidate;
        pbScreen.Invalidate;
      end;
    VK_BACK:
      begin
        if FInput <> '' then SetLength(FInput, Length(FInput) - 1);
        { erasing letters widens the list; erasing the slash puts it away }
        SyncCmdList;
        pbCmd.Invalidate;
        pbScreen.Invalidate;
      end;
    VK_Q: SetTool(ptRotate);      // SketchUp's key; Space is select
    VK_L: SetTool(ptLine);
    VK_R: SetTool(ptRect);
    VK_A: SetTool(ptArc);
    VK_C: SetTool(ptCircle);
    VK_P: SetTool(ptPush);
    VK_B: SetTool(ptDrill);       // bore
    VK_N: SetTool(ptText);
    VK_E: SetTool(ptErase);
    VK_M: SetTool(ptMove);
    VK_T: SetTool(ptMeasure);
    VK_D: SetTool(ptDim);
    VK_V:
      if ssShift in Shift then CycleViewPreset(-1) else CycleViewPreset(1);
    VK_I: RunCommand(IfThen(FD.View = vkIso, 'plan', 'iso'));
    VK_K: RunCommand('plane');
    { SketchUp puts Offset on F; zoom-to-fit is Shift+F and /fit }
    VK_F:
      if ssShift in Shift then FitView else SetTool(ptOffset);
    VK_O: SetTool(ptOrbit);
    VK_G: RunCommand('grid');
    VK_U: RunCommand('units');
    VK_H: CycleTheme(1);
    VK_OEM_4: SetEdgeWidth(FEdgeW - 1);
    VK_OEM_6: SetEdgeWidth(FEdgeW + 1);
  else
    Handled := False;
  end;
  if Handled then Key := 0;
end;

procedure TMainForm.FormKeyUp(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  { Alt steps the inferences (see FormKeyDown), so its release is kept too }
  if Key = VK_MENU then Key := 0;
end;

{ ======================================================================== }
{ commands                                                                  }
{ ======================================================================== }

{ An index from a settings file or an older build may be out of range; the
  dark theme is the default. }
procedure TMainForm.ApplyTheme;
begin
  if (FThemeIdx < 0) or (FThemeIdx > THEME_COUNT - 1) then
    FThemeIdx := THEME_DARK;
  if FInkAuto then SetInk(PixToColor(Theme.Ink), True);
end;

procedure TMainForm.CycleTheme(Step: Integer);
begin
  { two looks differing only in chrome; the paper stays white }
  FThemeIdx := (FThemeIdx + Step + THEME_COUNT) mod THEME_COUNT;
  { only ink not deliberately chosen follows the theme }
  if FInkAuto then
    SetInk(PixToColor(Theme.Ink), True);
  { the ink is its own layer, so a theme change only repapers underneath }
  RepaintPaper;
  RenderInk;
  RecomposeAll;
  RefreshChrome;
  ThemeSourceWindow;
end;

{ ======================================================================== }
{ documents: open, save, export                                             }
{ ======================================================================== }

procedure TMainForm.DoOpen;
begin
  dlgOpen.Filter := 'Heckers Sketch drawing|*.hsk|All files|*.*';
  dlgOpen.DefaultExt := '.hsk';
  dlgOpen.InitialDir := OpenDirNow;
  if not dlgOpen.Execute then Exit;
  FOpenDir := ExtractFileDir(dlgOpen.FileName);
  OpenFile(dlgOpen.FileName);
end;

{ Open a file as a document of its own, its sheets in tabs after the others.
  If it is already open its tab comes to the front.  The untouched empty
  starting drawing gives way to it. }
function TMainForm.OpenFile(const FileName: string): Boolean;
var
  Full: string;
  I, First, N: Integer;
  Blank: TDrawing;
begin
  Result := False;
  Full := ExpandFileName(FileName);
  for I := 0 to High(FDrawings) do
    if (FDrawings[I].FilePath <> '') and SameFileName(FDrawings[I].FilePath, Full) then
    begin
      SelectDrawing(I);
      FCmdMsg := ExtractFileName(Full) + ' is open already - here it is.';
      pbCmd.Invalidate;
      Exit(True);
    end;
  Blank := nil;
  if (Length(FDrawings) = 1) and (FDrawings[0].FilePath = '') and not FDrawings[0].Dirty and
     (FDrawings[0].Doc.Live = 0) then Blank := FDrawings[0];
  if not ReadSheets(Full, False, First) then Exit;
  if Blank <> nil then
  begin
    LeaveSheet;
    for I := 0 to High(FDrawings) - 1 do FDrawings[I] := FDrawings[I + 1];
    SetLength(FDrawings, Length(FDrawings) - 1);
    Blank.Free;
    FD := nil;
    Dec(First);
  end;
  ShowLoaded(First);
  RememberRecent(Full);
  N := Length(DocSheets(FDrawings[First].DocKey));
  FCmdMsg := 'Opened ' + ExtractFileName(Full) +
    IfThen(N > 1, Format(' - %d sheets in this file, a tab each', [N]), '');
  Result := True;
end;

{ A file's sheets added after the existing tabs; First is the first new one.
  Session: a draft or handoff carrying every open file, with a comment before
  each sheet naming its document, file and saved state.  Otherwise the file
  is one document whose sheets share its path and name. }
function TMainForm.ReadSheets(const FileName: string; Session: Boolean; out First: Integer): Boolean;
var
  L: TStringList;
  Sheets: THeckSheets;
  I, K, Base, NewKey, ErrLine: Integer;
  Err: string;
  D, Was: TDrawing;
  KeyFrom, KeyTo: array of Integer;
begin
  Result := False;
  First := Length(FDrawings);
  Base := First;
  Was := FD;
  KeyFrom := nil; KeyTo := nil;
  Sheets := nil;
  Inc(FNextDocKey);
  NewKey := FNextDocKey;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(FileName);
    except
      on E: Exception do
      begin
        MessageDlg('Could not open', E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
    FLoading := True;
    FLoadSkipped := False;
    SplashSkipReset;
    OnProgress('Reading ' + ExtractFileName(FileName), 0);
    { Heck only: the old line format is refused with a note on converting it
      (see hsHeckFile) }
    try
      Result := ReadDrawingFile(L, Sheets, ErrLine, Err);
    except
      on E: Exception do
      begin
        Result := False;
        Err := E.Message;
        ErrLine := -1;
      end;
    end;
    if not Result or FLoadSkipped then
    begin
      for I := 0 to High(Sheets) do Sheets[I].Doc.Free;
      FLoading := False;
      EndBusy;
      if FLoadSkipped then
      begin
        Trail('skipped loading ' + FileName);
        FCmdMsg := 'Loading ' + ExtractFileName(FileName) +
          ' was skipped.  The file is untouched, and can be opened.';
      end
      else
        MessageDlg('Could not open', ExtractFileName(FileName) + ' will not read' +
          IfThen(ErrLine >= 0, Format(' - line %d', [ErrLine + 1]), '') + ':' + LineEnding + LineEnding + Err,
          mtError, [mbOK], 0);
      Exit(False);
    end;
    { a drawing with no sheet in it is one empty sheet }
    if Length(Sheets) = 0 then
    begin
      SetLength(Sheets, 1);
      Sheets[0] := NewHeckSheet('Sheet 1');
    end;
    for I := 0 to High(Sheets) do
    begin
      D := TDrawing.Create(Sheets[I].Name);
      D.Doc.Free;
      D.Doc := Sheets[I].Doc;
      D.Units := Sheets[I].Units;
      D.ScaleIdx := Sheets[I].ScaleIdx;
      D.SnapIdx := Sheets[I].SnapIdx;
      D.View := Sheets[I].View;
      D.SliceOn := Sheets[I].SliceOn;
      D.SliceLo := Sheets[I].SliceLo;
      D.SliceHi := Sheets[I].SliceHi;
      if Sheets[I].CamKnown then
      begin
        D.Az := Sheets[I].Az; D.El := Sheets[I].El;
        D.Zoom := EnsureRange(Sheets[I].Zoom, ZOOM_MIN, ZOOM_MAX);
        D.ViewX := Sheets[I].ViewX; D.ViewY := Sheets[I].ViewY;
        D.CamKnown := True;
      end;
      if Session and Sheets[I].HasSession then
      begin
        { the session's document keys are the old run's: one new key each }
        D.DocKey := -1;
        for K := 0 to High(KeyFrom) do
          if KeyFrom[K] = Sheets[I].DocKey then D.DocKey := KeyTo[K];
        if D.DocKey < 0 then
        begin
          Inc(FNextDocKey);
          D.DocKey := FNextDocKey;
          SetLength(KeyFrom, Length(KeyFrom) + 1); KeyFrom[High(KeyFrom)] := Sheets[I].DocKey;
          SetLength(KeyTo, Length(KeyTo) + 1); KeyTo[High(KeyTo)] := D.DocKey;
        end;
        D.FilePath := Sheets[I].FilePath;
        D.DocName := Sheets[I].DocName;
        if D.DocName = '' then
          if D.FilePath <> '' then D.DocName := ChangeFileExt(ExtractFileName(D.FilePath), '')
          else
          begin
            Inc(FUntitled);
            D.DocName := Format('Untitled %d', [FUntitled]);
          end;
        D.Dirty := Sheets[I].Dirty;
      end
      else
      begin
        D.DocKey := NewKey;
        D.FilePath := FileName;
        D.DocName := ChangeFileExt(ExtractFileName(FileName), '');
        D.Dirty := False;
      end;
      SetLength(FDrawings, Length(FDrawings) + 1);
      FDrawings[High(FDrawings)] := D;
    end;
    { Work out each sheet's flat areas.  A file with faces says which areas
      are filled, including ones emptied on purpose, so its areas are taken as
      seen and no face is invented.  A file with no faces gets them computed. }
    for I := Base to High(FDrawings) do
    begin
      if Length(FDrawings) - Base > 1 then
        OnProgress(Format('Working out the faces on sheet %d of %d', [I - Base + 1, Length(FDrawings) - Base]), -1)
      else
        OnProgress('Working out the faces', -1);
      FD := FDrawings[I];
      if AnyFace then SeedRegions else RebuildFlatFaces;
    end;
    FD := Was;
    FLoading := False;
    EndBusy;
    Result := True;
  finally
    L.Free;
  end;
end;

{ Show tab First with its saved camera, or framed when the file had none or
  the camera showed none of the drawing. }
procedure TMainForm.ShowLoaded(First: Integer);
begin
  LeaveSheet;
  FTabIdx := EnsureRange(First, 0, High(FDrawings));
  FD := FDrawings[FTabIdx];
  ResetTool;
  Relayout;
  { frame only when the file could not say where the camera was, or the
    saved camera shows none of the drawing }
  if FD.CamKnown and CameraShowsSomething then
  begin
    FCameraMoving := True;
    RepaintPaper;
    RenderInk;
    RecomposeAll;
    Invalidate;
  end
  else
  begin
    if FD.CamKnown then
      Trail('the saved camera showed none of the drawing - framed instead');
    FitView(False);
  end;
  LayoutTabs;
  RefreshChrome;
  pbCmd.Invalidate;
end;

{ Save As: the file in front, every sheet of it, under a new name. }
procedure TMainForm.DoSaveAs;
begin
  SaveDocument(FD.DocKey, True);
end;

{ Save: the file in front, back to where it came from, asking for a name only
  the first time. }
procedure TMainForm.DoSave;
begin
  SaveDocument(FD.DocKey, False);
end;

procedure TMainForm.DoSaveAll;
var
  I, N: Integer;
begin
  N := 0;
  I := 0;
  while I <= High(FDrawings) do
  begin
    if DocDirty(FDrawings[I].DocKey) then
    begin
      if not SaveDocument(FDrawings[I].DocKey, False) then Break;
      Inc(N);
    end;
    Inc(I);
  end;
  if N = 0 then FCmdMsg := 'Nothing to save - every file is saved.'
  else FCmdMsg := Format('Saved %d file%s.', [N, IfThen(N = 1, '', 's')]);
  pbCmd.Invalidate;
end;

function TMainForm.SaveDocument(Key: Integer; AskName: Boolean): Boolean;
var
  S: TIntArrayW;
  L: TStringList;
  Path, Tmp: string;
  I: Integer;
begin
  Result := False;
  S := DocSheets(Key);
  if Length(S) = 0 then Exit;
  Path := FDrawings[S[0]].FilePath;
  if AskName or (Path = '') then
  begin
    { its drawing in front while its name is asked for }
    if FDrawings[FTabIdx].DocKey <> Key then SelectDrawing(S[0]);
    dlgSave.Filter := 'Heckers Sketch drawing|*.hsk';
    dlgSave.DefaultExt := '.hsk';
    dlgSave.InitialDir := SaveDirNow;
    if Path <> '' then dlgSave.FileName := Path
    else dlgSave.FileName := IncludeTrailingPathDelimiter(dlgSave.InitialDir) +
      FDrawings[S[0]].DocName + '.hsk';
    if not dlgSave.Execute then Exit;
    Path := ExpandFileName(dlgSave.FileName);
    { another tab's file: two documents writing one file lose one of them }
    for I := 0 to High(FDrawings) do
      if (FDrawings[I].DocKey <> Key) and (FDrawings[I].FilePath <> '') and
         SameFileName(FDrawings[I].FilePath, Path) then
      begin
        MessageDlg('Could not save', ExtractFileName(Path) + ' is open in another tab.  Close it there first, ' +
          'or save this under another name.', mtWarning, [mbOK], 0);
        Exit;
      end;
    FSaveDir := ExtractFileDir(Path);
  end;
  L := TStringList.Create;
  try
    BuildSession(L, False, Key);
    { written beside it, then moved into place, so a failed write (full disk,
      pulled stick) leaves the old file whole }
    Tmp := Path + '.saving';
    try
      L.SaveToFile(Tmp);
      { rename over the old one; Windows needs the old one removed first }
      if not RenameFile(Tmp, Path) then
      begin
        if FileExists(Path) and not DeleteFile(Path) then
          raise Exception.Create('The old copy of ' + ExtractFileName(Path) + ' could not be replaced.');
        if not RenameFile(Tmp, Path) then
          raise Exception.Create('The new copy could not be put in place of ' + ExtractFileName(Path) + '.');
      end;
    except
      on E: Exception do
      begin
        if FileExists(Tmp) and not FileExists(Path) then RenameFile(Tmp, Path);
        MessageDlg('Could not save', E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
  finally
    L.Free;
  end;
  for I := 0 to High(S) do
  begin
    FDrawings[S[I]].FilePath := Path;
    FDrawings[S[I]].DocName := ChangeFileExt(ExtractFileName(Path), '');
    FDrawings[S[I]].Dirty := False;
  end;
  FSavedSeq := FEditSeq;
  { the draft only holds what is unsaved: rewritten, or dropped if nothing is
    left unsaved, on the next tick }
  FDraftSeq := -1;
  RememberRecent(Path);
  FCmdMsg := 'Saved ' + ExtractFileName(Path) +
    IfThen(Length(S) > 1, Format(' - its %d sheets', [Length(S)]), '');
  LayoutTabs;
  Invalidate;
  pbCmd.Invalidate;
  Result := True;
end;

{ ---- the File menu ----
  MENU holds everything to do with files.  Its shortcuts are shown beside
  each row and work whether the menu is open or not. }
const
  FM_NEW = 1; FM_OPEN = 2; FM_SAVE = 3; FM_SAVEAS = 4; FM_SAVEALL = 5;
  FM_ADDSHEET = 6; FM_DELSHEET = 7; FM_EXPORT = 8; FM_PRINT = 9;
  FM_EXAMPLE = 10; FM_CLOSE = 11; FM_EXIT = 12; FM_CLEARRECENT = 13;

procedure TMainForm.ShowFileMenu;
var
  M, Sub: TMenuItem;
  I, N: Integer;
  P: TPoint;

  function Add(Parent: TMenuItem; const Caption: string; Tag: Integer; Key: Word = 0;
    Shift: TShiftState = []; Enabled: Boolean = True): TMenuItem;
  begin
    Result := TMenuItem.Create(pmFile);
    Result.Caption := Caption;
    Result.Tag := Tag;
    Result.Enabled := Enabled;
    if Key <> 0 then Result.ShortCut := Menus.ShortCut(Key, Shift);
    Result.OnClick := @FileMenuClick;
    if Parent = nil then pmFile.Items.Add(Result) else Parent.Add(Result);
  end;

  procedure Line;
  var
    L: TMenuItem;
  begin
    L := TMenuItem.Create(pmFile);
    L.Caption := '-';
    pmFile.Items.Add(L);
  end;

begin
  pmFile.Items.Clear;
  Add(nil, 'New Drawing', FM_NEW, VK_N, [ssCtrl]);
  Add(nil, 'Open...', FM_OPEN, VK_O, [ssCtrl]);
  Sub := TMenuItem.Create(pmFile);
  Sub.Caption := 'Open Recent';
  pmFile.Items.Add(Sub);
  for I := 0 to FRecent.Count - 1 do
  begin
    M := TMenuItem.Create(pmFile);
    M.Caption := Format('%d  %s', [I + 1, ExtractFileName(FRecent[I])]);
    M.Hint := FRecent[I];
    M.Tag := I;
    M.OnClick := @RecentClick;
    Sub.Add(M);
  end;
  if FRecent.Count = 0 then
  begin
    M := TMenuItem.Create(pmFile);
    M.Caption := 'Nothing yet';
    M.Enabled := False;
    Sub.Add(M);
  end
  else
  begin
    M := TMenuItem.Create(pmFile);
    M.Caption := '-';
    Sub.Add(M);
    Add(Sub, 'Clear the List', FM_CLEARRECENT);
  end;
  Line;
  Add(nil, 'Save', FM_SAVE, VK_S, [ssCtrl]);
  Add(nil, 'Save As...', FM_SAVEAS, VK_S, [ssCtrl, ssShift]);
  Add(nil, 'Save All', FM_SAVEALL, 0, [], AnyDirty > 0);
  Line;
  N := Length(DocSheets(FD.DocKey));
  Add(nil, 'Add a Sheet to This File', FM_ADDSHEET);
  Add(nil, 'Delete This Sheet from the File', FM_DELSHEET, 0, [], N > 1);
  Line;
  Add(nil, 'Export...', FM_EXPORT, VK_E, [ssCtrl]);
  Add(nil, 'Print...', FM_PRINT, VK_P, [ssCtrl]);
  Add(nil, 'Open the Example', FM_EXAMPLE);
  Line;
  Add(nil, 'Close This File', FM_CLOSE, VK_W, [ssCtrl]);
  Add(nil, 'Exit', FM_EXIT);
  { under the MENU button }
  P := Point(0, pbQuick.Height);
  for I := 0 to High(FQuick) do
    if FQuick[I].Value = ACT_MENU then P := Point(FQuick[I].Bounds.Left, FQuick[I].Bounds.Bottom);
  P := pbQuick.ClientToScreen(P);
  pmFile.PopUp(P.X, P.Y);
end;

procedure TMainForm.FileMenuClick(Sender: TObject);
begin
  case (Sender as TMenuItem).Tag of
    FM_NEW: NewDrawing(-1);
    FM_OPEN: DoOpen;
    FM_SAVE: DoSave;
    FM_SAVEAS: DoSaveAs;
    FM_SAVEALL: DoSaveAll;
    FM_ADDSHEET: AddSheetHere;
    FM_DELSHEET: DeleteSheetHere;
    FM_EXPORT: DoExport;
    FM_PRINT: DoPrint;
    FM_EXAMPLE:
      begin
        NewDrawing(-1);
        LoadExample;
        LayoutTabs;
        RenderInk;
        RecomposeAll;
      end;
    FM_CLOSE: CloseDrawing(FTabIdx);
    FM_EXIT: Close;
    FM_CLEARRECENT:
      begin
        FRecent.Clear;
        FCmdMsg := 'The recent files list is cleared.';
      end;
  end;
  pbCmd.Invalidate;
  Invalidate;
end;

procedure TMainForm.RecentClick(Sender: TObject);
var
  I: Integer;
  Path: string;
begin
  I := (Sender as TMenuItem).Tag;
  if (I < 0) or (I >= FRecent.Count) then Exit;
  Path := FRecent[I];
  if not FileExists(Path) then
  begin
    FRecent.Delete(I);
    FCmdMsg := Path + ' is not there any more - taken off the list.';
    pbCmd.Invalidate;
    Exit;
  end;
  OpenFile(Path);
end;

{ the files opened and saved lately, newest first, ten of them }
procedure TMainForm.RememberRecent(const Path: string);
var
  I: Integer;
begin
  if Path = '' then Exit;
  for I := FRecent.Count - 1 downto 0 do
    if SameFileName(FRecent[I], Path) then FRecent.Delete(I);
  FRecent.Insert(0, Path);
  while FRecent.Count > 10 do FRecent.Delete(FRecent.Count - 1);
end;

procedure TMainForm.AddSheetHere;
begin
  NewDrawing(FD.DocKey);
  FCmdMsg := Format('%s added to %s - saving the file saves every sheet of it.', [FD.Name, FD.DocName]);
  pbCmd.Invalidate;
end;

{ Delete one sheet from a file of several.  No undo for it, so it asks. }
procedure TMainForm.DeleteSheetHere;
var
  S: TIntArrayW;
  I, Key: Integer;
  DocNm: string;
begin
  Key := FD.DocKey;
  S := DocSheets(Key);
  if Length(S) < 2 then
  begin
    FCmdMsg := 'A file keeps at least one sheet - close the file instead.';
    pbCmd.Invalidate;
    Exit;
  end;
  if QuestionDlg('Delete this sheet',
    Format('Delete "%s" from %s?  Its drawing goes with it, and Undo cannot bring a sheet back.',
      [FD.Name, FD.DocName]),
    mtConfirmation, [mrYes, 'Delete the sheet', mrCancel, 'Keep it', 'IsCancel', 'IsDefault'], 0) <> mrYes then Exit;
  DocNm := FD.Name;
  LeaveSheet;
  I := FTabIdx;
  FDrawings[I].Free;
  for I := FTabIdx to High(FDrawings) - 1 do FDrawings[I] := FDrawings[I + 1];
  SetLength(FDrawings, Length(FDrawings) - 1);
  { what is left of the file has changed }
  S := DocSheets(Key);
  FDrawings[S[0]].Dirty := True;
  FDraftSeq := -1;
  FTabIdx := EnsureRange(FTabIdx, 0, High(FDrawings));
  if FDrawings[FTabIdx].DocKey <> Key then FTabIdx := S[High(S)];
  FD := FDrawings[FTabIdx];
  ResetTool;
  LayoutTabs;
  RepaintPaper;
  RenderInk;
  RecomposeAll;
  RefreshChrome;
  FCmdMsg := Format('%s deleted from %s.', [DocNm, FD.DocName]);
  pbCmd.Invalidate;
end;

{ A color not on the palette, from the platform's own picker (it has the
  eyedropper and recent colors).  The palette stays twelve. }
procedure TMainForm.PickAnyColor;
var
  C: TColor;
begin
  if not AskColor(FInkColor, C) then Exit;
  SetInk(C, False);
  FCmdMsg := 'Pen color set.';
end;

{ the platform's own color picker, started on Was }
function TMainForm.AskColor(Was: TColor; out C: TColor): Boolean;
var
  D: TColorDialog;
begin
  C := Was;
  D := TColorDialog.Create(nil);
  try
    D.Color := Was;
    Result := D.Execute;
    if Result then C := D.Color;
  finally
    D.Free;
  end;
end;

{ The manual, in its own window (see hsHelpView), fetched from the release
  when missing or from another version, so a portable copy keeps its manual. }
procedure TMainForm.OpenManual;
begin
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  OpenHelpWindow('');
  FCmdMsg := 'Opened the manual.';
end;

{ Keep the manual beside the program in step: asked once a few seconds after
  start, it fetches the right pages in the background when missing or from
  another release.  Same switch as the update check (/update never), off with
  --offline, and a failure is not retried for six hours. }
procedure TMainForm.KeepHelpCurrent;
var
  Ini: TIniFile;
  Last: string;
begin
  if NetOffline then Exit;
  if not HelpIsStale(CurrentVersion) then Exit;
  Ini := TIniFile.Create(ConfigFile);
  try
    if not Ini.ReadBool('update', 'check', True) then Exit;
    Last := Ini.ReadString('help', 'tried', '');
    if (Last <> '') and (Now - StrToFloatDef(Last, 0) < 0.25) then Exit;
    Ini.WriteString('help', 'tried', FloatToStr(Now));
  finally
    Ini.Free;
  end;
  Trail('help pages: fetching for ' + CurrentVersion);
  StartHelpFetch(CurrentVersion, @HelpFetchProgress, @HelpFetchDone);
end;

procedure TMainForm.HelpFetchProgress(BytesReceived, TotalBytes: Int64);
begin
  if HelpForm <> nil then HelpForm.FetchProgress(BytesReceived, TotalBytes);
end;

procedure TMainForm.HelpFetchDone(Sender: TObject);
var
  F: THelpFetch;
  Ini: TIniFile;
begin
  F := Sender as THelpFetch;
  if F.OK then
  begin
    Trail('help pages: installed from ' + F.GotTag);
    { a success clears the six-hour wait }
    Ini := TIniFile.Create(ConfigFile);
    try
      Ini.DeleteKey('help', 'tried');
    finally
      Ini.Free;
    end;
  end
  else
    Trail('help pages: not fetched - ' + F.Err);
  if HelpForm <> nil then HelpForm.FetchDone(Sender);
end;

{ Every edge where a solid is not closed, drawn on the model, so you see
  where (the export only says whether).  TWorkDoc.OpenEdges does the work,
  resolving T-junctions as GroupClosed does.  Checks the selected solids, or
  every solid when nothing is selected. }
procedure TMainForm.ShowOpenEdges;
var
  I, J, G, NGrp, NBad: Integer;
  Grps: array of Integer;
  Edges: TP3Array;

  procedure Want(AG: Integer);
  var
    K: Integer;
  begin
    if AG = 0 then Exit;
    for K := 0 to NGrp - 1 do
      if Grps[K] = AG then Exit;
    if NGrp >= Length(Grps) then SetLength(Grps, Max(8, NGrp * 2));
    Grps[NGrp] := AG;
    Inc(NGrp);
  end;

begin
  SetLength(FOpenEdges, 0);
  FOpenSeq := FEditSeq;
  NGrp := 0;
  SetLength(Grps, 8);

  if Length(FSel) > 0 then
    for I := 0 to High(FSel) do
      if (FSel[I] >= 0) and (FSel[I] < FD.Doc.Live) then
        Want(FD.Doc[FSel[I]].Grp);
  if NGrp = 0 then
    for I := 0 to FD.Doc.Live - 1 do
      if (FD.Doc[I].Kind = ekFace) and FD.Doc[I].Solid then
        Want(FD.Doc[I].Grp);

  if NGrp = 0 then
  begin
    FCmdMsg := 'Nothing here is a solid - there is nothing to be open.';
    pbCmd.Invalidate;
    Exit;
  end;

  NBad := 0;
  for I := 0 to NGrp - 1 do
  begin
    G := Grps[I];
    if FD.Doc.GroupClosed(G) then Continue;
    Inc(NBad);
    Edges := FD.Doc.OpenEdges(G);
    for J := 0 to High(Edges) do
    begin
      SetLength(FOpenEdges, Length(FOpenEdges) + 1);
      FOpenEdges[High(FOpenEdges)] := Edges[J];
    end;
  end;

  if NBad = 0 then
    FCmdMsg := Format('%s closed - a slicer will take %s.',
      [specialize IfThen<string>(NGrp = 1, 'That solid is',
        Format('All %d solids are', [NGrp])),
       specialize IfThen<string>(NGrp = 1, 'it', 'them')])
  else if Length(FOpenEdges) = 0 then
    FCmdMsg := Format('%d of %d solids are open, but the edges could not be ' +
      'pinned down - send this drawing in.', [NBad, NGrp])
  else
  begin
    if NGrp = 1 then
      FCmdMsg := 'This solid is open.'
    else if NBad = 1 then
      FCmdMsg := Format('One of the %d solids is open.', [NGrp])
    else
      FCmdMsg := Format('%d of the %d solids are open.', [NBad, NGrp]);
    FCmdMsg := FCmdMsg + Format('  %d edges are drawn in red where nothing ' +
      'meets them - type /holes again once you have mended them.',
      [Length(FOpenEdges) div 2]);
  end;
  pbCmd.Invalidate;
  Invalidate;
end;

{ Where this kind of file was exported last time, or the program's exports
  folder.  Empty if even that cannot be made (a read-only stick); the dialog
  then offers a bare file name. }
function TMainForm.ExportDirFor(const Ext: string): string;
begin
  Result := FExportDirs.Values[Ext];
  if (Result <> '') and DirectoryExists(Result) then Exit;
  Result := ExportsDir;
end;

procedure TMainForm.KeepExportDir(const Ext, Dir: string);
begin
  if (Ext = '') or (Dir = '') then Exit;
  FExportDirs.Values[Ext] := Dir;
end;

{ the same for drawings, which are all one kind }
function TMainForm.SaveDirNow: string;
begin
  Result := FSaveDir;
  if (Result <> '') and DirectoryExists(Result) then Exit;
  Result := DrawingsDir;
  if Result = '' then Result := AppDataDir;
end;

{ where to look when opening: where a drawing was last opened from, or the
  program's own folder (examples and drawings are one click away) }
function TMainForm.OpenDirNow: string;
begin
  Result := FOpenDir;
  if (Result <> '') and DirectoryExists(Result) then Exit;
  Result := AppDataDir;
end;

procedure TMainForm.DoExport;
var
  Msg, Base: string;
  ExpPivot: TP3;
  Holes: Boolean;
begin
  { the export turns about the middle of the selection, or of the drawing }
  if not FD.Doc.MiddleOf(FSel, ExpPivot) then ExpPivot := P3(0, 0, 0);
  { a name only; the dialog asks for the folder per format }
  Base := 'heckers-sketch-' + FormatDateTime('yyyymmdd-hhnnss', Now);
  Msg := '';
  Holes := False;
  if RunExport(FD.Doc, Proj, FD.Units, FDimFont, AnnotColor, FEdgeW,
       FArt.Width, FArt.Height, Base, Themes[FThemeIdx], ExpPivot,
       @ReportFromDialog, @ExportDirFor, @KeepExportDir, Msg, Holes, FD.ScaleIdx) then
  begin
    FCmdMsg := Msg;
    { told the STL is not closed, the open edges are already marked on the
      drawing when the dialog closes }
    if Holes then
    begin
      ShowOpenEdges;
      FCmdMsg := Msg;
    end;
  end
  else if Msg <> '' then
    FCmdMsg := Msg;
  Invalidate;
end;

{ Print full size across as many sheets as it takes, for taping together on
  the metal and scribing round.  Each tile is rendered from geometry at the
  printer's resolution.  Each tile starts LAP short of the last page edge, so
  the right and bottom LAP strip repeats the next sheet: trim on the marked
  line and butt them.  The sheet label sits in that strip. }
procedure TMainForm.DoPrintFull(const PngDir: string);
const
  LAP_IN = 0.5;        // inches of overlap, and the width of the trim strip
  MARGIN_IN = 0.25;    // white left round the drawing before it is tiled
  MAX_SHEETS = 120;    // past this it is a mistake, not a plan
var
  Sheet: TArtSurface;
  V: TProjector;
  Full: TDrawScale;
  Lo, Hi: TP3;
  I, Col, Row, Cols, Rows, SW, SH, PitchW, PitchH, N: Integer;
  BX0, BY0, BX1, BY1, MinX, MinY, MaxX, MaxY: Double;
  PageWIn, PageHIn: Double;
  Any: Boolean;
  Msg: string;
begin
  if FD.Doc.Live = 0 then
  begin
    FCmdMsg := 'Nothing on this sheet to print.';
    Exit;
  end;

  { 1:1: paper inches per foot, so 12; metric paper meters per meter, so 1 }
  if FD.Units = usImperial then
  begin
    Full.Name := 'full size';
    Full.Paper := 12;
  end
  else
  begin
    Full.Name := '1:1';
    Full.Paper := 1;
  end;

  { Where the drawing lands on an unshifted page, in print pixels, through
    the current view.  Full size is exact in PLAN; in 3D it is the picture at
    full size, foreshortening and all (said below before printing). }
  V.Kind := FD.View;
  V.Ppu := PixelsPerUnit(FD.Units, Full, PRINT_DPI);
  V.OX := 0;
  V.OY := 0;
  V.Az := FD.Az;
  V.El := FD.El;

  Any := False;
  MinX := 0; MinY := 0; MaxX := 0; MaxY := 0;
  for I := 0 to FD.Doc.Live - 1 do
  begin
    FD.Doc.ScreenBounds(V, I, BX0, BY0, BX1, BY1);
    if BX1 < BX0 then Continue;
    if not Any then
    begin
      MinX := BX0; MinY := BY0; MaxX := BX1; MaxY := BY1;
      Any := True;
    end
    else
    begin
      MinX := Min(MinX, BX0); MinY := Min(MinY, BY0);
      MaxX := Max(MaxX, BX1); MaxY := Max(MaxY, BY1);
    end;
  end;
  if not Any then
  begin
    { nothing has a screen size: fall back to the model box }
    if not FD.Doc.Bounds(Lo, Hi) then Exit;
    MinX := 0; MinY := 0;
    MaxX := (Hi.X - Lo.X) * V.Ppu;
    MaxY := (Hi.Y - Lo.Y) * V.Ppu;
  end;
  MinX := MinX - MARGIN_IN * PRINT_DPI;
  MinY := MinY - MARGIN_IN * PRINT_DPI;
  MaxX := MaxX + MARGIN_IN * PRINT_DPI;
  MaxY := MaxY + MARGIN_IN * PRINT_DPI;

  { straight to PNG files needs no dialog and no printer (letter size if
    there is none): what a print shop asks for, and a preview }
  if PngDir = '' then
  begin
    if not dlgPrint.Execute then Exit;
    if (Printer.XDPI <= 0) or (Printer.YDPI <= 0) then
    begin
      FCmdMsg := 'The printer did not say what resolution it is.';
      Exit;
    end;
  end;

  if (Printer.XDPI > 0) and (Printer.YDPI > 0) then
  begin
    PageWIn := Printer.PageWidth / Printer.XDPI;
    PageHIn := Printer.PageHeight / Printer.YDPI;
  end
  else
  begin
    PageWIn := 8.5;
    PageHIn := 11;
  end;
  SW := Max(64, Round(PageWIn * PRINT_DPI));
  SH := Max(64, Round(PageHIn * PRINT_DPI));
  PitchW := Max(1, SW - Round(LAP_IN * PRINT_DPI));
  PitchH := Max(1, SH - Round(LAP_IN * PRINT_DPI));

  Cols := Max(1, Ceil((MaxX - MinX) / PitchW));
  Rows := Max(1, Ceil((MaxY - MinY) / PitchH));
  N := Cols * Rows;

  Msg := Format('%s, %d across by %d down = %d sheets of %.1f x %.1f in.',
    [Full.Name, Cols, Rows, N, PageWIn, PageHIn]);
  if FD.View <> vkPlan then
    Msg := Msg + LineEnding + LineEnding +
      'This is the ' + IfThen(FD.View = vkIso, 'ISO', '3D') +
      ' view, so what comes out is the picture at full size, not the part.' +
      LineEnding + 'PLAN is the one to print a pattern from.';
  if (N > MAX_SHEETS) and (PngDir <> '') then
  begin
    FCmdMsg := Format('%d tiles is past the %d limit.', [N, MAX_SHEETS]);
    Exit;
  end;
  if N > MAX_SHEETS then
  begin
    MessageDlg('Too many sheets',
      Msg + LineEnding + LineEnding +
      Format('That is past the %d sheet limit.  Print it at a scale, or ' +
        'print one piece at a time.', [MAX_SHEETS]), mtWarning, [mbOK], 0);
    Exit;
  end;
  if (PngDir = '') and (MessageDlg('Print full size?',
       Msg + LineEnding + LineEnding +
       Format('Every sheet is trimmed on the marked line - the last %.1f in ' +
         'down the right and along the bottom is a repeat of the next ' +
         'sheet.  The sheet number is printed inside that strip.',
         [LAP_IN]),
       mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then Exit;

  try
    if PngDir = '' then Printer.BeginDoc;
    try
      Sheet := TArtSurface.Create(SW, SH);
      try
        for Row := 0 to Rows - 1 do
          for Col := 0 to Cols - 1 do
          begin
            if (PngDir = '') and ((Row > 0) or (Col > 0)) then Printer.NewPage;
            Sheet.Clear(Pix(255, 255, 255));
            V.OX := -MinX - Col * PitchW;
            V.OY := -MinY - Row * PitchH;
            FD.Doc.Render(Sheet, V, FD.Units, FDimFont, Pix(20, 20, 20), FEdgeW);
            if PngDir <> '' then
              Sheet.SaveToPNG(IncludeTrailingPathDelimiter(PngDir) +
                Format('tile-r%dc%d.png', [Row + 1, Col + 1]))
            else
            begin
              Printer.Canvas.StretchDraw(
                Rect(0, 0, Printer.PageWidth, Printer.PageHeight), Sheet.AsBitmap);
              PrintTileMarks(Col, Row, Cols, Rows, PitchW, PitchH, SW, SH,
                             Full.Name);
            end;
          end;
      finally
        Sheet.Free;
      end;
    finally
      if PngDir = '' then Printer.EndDoc;
    end;
    if PngDir <> '' then
      FCmdMsg := Format('Wrote %d tiles at %s into %s', [N, Full.Name, PngDir])
    else
      FCmdMsg := Format('Sent %d sheets at %s.', [N, Full.Name]);
  except
    on E: Exception do
      if PngDir <> '' then FCmdMsg := 'Could not write the tiles: ' + E.Message
      else MessageDlg('Could not print', E.Message, mtError, [mbOK], 0);
  end;
  Invalidate;
end;

{ The trim line and sheet number, drawn straight onto the page at printer
  resolution: they belong to the paper, not the drawing. }
procedure TMainForm.PrintTileMarks(Col, Row, Cols, Rows, PitchW, PitchH,
  SW, SH: Integer; const ScaleName: string);
var
  PX, PY: Integer;
  S: string;

  { print pixels to printer pixels }
  function AtX(V: Integer): Integer;
  begin
    Result := Round(V * (Printer.PageWidth / SW));
  end;

  function AtY(V: Integer): Integer;
  begin
    Result := Round(V * (Printer.PageHeight / SH));
  end;

begin
  Printer.Canvas.Pen.Color := clSilver;
  Printer.Canvas.Pen.Width := Max(1, Printer.XDPI div 300);
  Printer.Canvas.Brush.Style := bsClear;

  PX := AtX(PitchW);
  PY := AtY(PitchH);
  { a sheet with one to its right is trimmed on the line; the last column is
    left whole }
  if Col < Cols - 1 then
  begin
    Printer.Canvas.Line(PX, 0, PX, Printer.PageHeight);
    Printer.Canvas.TextOut(PX + AtX(8), AtY(8), 'trim');
  end;
  if Row < Rows - 1 then
  begin
    Printer.Canvas.Line(0, PY, Printer.PageWidth, PY);
    Printer.Canvas.TextOut(AtX(8), PY + AtY(8), 'trim');
  end;

  Printer.Canvas.Font.Color := clGray;
  Printer.Canvas.Font.Height := -Round(Printer.YDPI / 8);   { about 9 point }
  S := Format('%s  -  sheet %d of %d   (row %d, column %d)   %s',
    [FD.Name, Row * Cols + Col + 1, Cols * Rows, Row + 1, Col + 1, ScaleName]);
  { inside the trim strip, so it is cut away with it }
  Printer.Canvas.TextOut(AtX(12),
    Printer.PageHeight - Round(Printer.YDPI / 5), S);
end;

{ Print the sheet in front at its drawing scale. }
procedure TMainForm.DoPrint;
begin
  DoPrintSheets(False);
end;

{ Print at scale.  The page is rendered from the geometry at the printer's
  resolution, so 1/4" = 1'-0" is a true quarter inch; a printer that gives
  no resolution gets the picture fitted to the page.  All prints every sheet of the file, a page each
  (/print all); that is not the default. }
procedure TMainForm.DoPrintSheets(All: Boolean);
var
  Sheet: TArtSurface;
  V: TProjector;
  Lo, Hi, Mid: TP3;
  PageWIn, PageHIn: Double;
  SW, SH: Integer;
  P: TPointF;
  Scale: Double;
  R: TRect;
  Was, Page, NPages: Integer;
  Pages: TIntArrayW;
begin
  if not dlgPrint.Execute then Exit;
  Was := FTabIdx;
  { every sheet of the file in front, not every tab (others may be other
    files) }
  Pages := DocSheets(FD.DocKey);
  if All then NPages := Length(Pages) else NPages := 1;
  try
    Printer.BeginDoc;
    try
      for Page := 0 to NPages - 1 do
      begin
      if All then
      begin
        { the renderer reads the sheet, scale and units off FD, so the sheet
          being printed is made current while it is drawn }
        if Page > 0 then Printer.NewPage;
        FTabIdx := Pages[Page];
        FD := FDrawings[Pages[Page]];
      end;
      if (Printer.XDPI > 0) and (Printer.YDPI > 0) then
      begin
        PageWIn := Printer.PageWidth / Printer.XDPI;
        PageHIn := Printer.PageHeight / Printer.YDPI;
        SW := Max(64, Round(PageWIn * PRINT_DPI));
        SH := Max(64, Round(PageHIn * PRINT_DPI));

        Sheet := TArtSurface.Create(SW, SH);
        try
          Sheet.Clear(Pix(255, 255, 255));
          V.Kind := FD.View;
          V.Ppu := PixelsPerUnit(FD.Units, CurScale, PRINT_DPI);
          V.OX := 0;
          V.OY := 0;
          if FD.Doc.Bounds(Lo, Hi) then
          begin
            Mid := P3((Lo.X + Hi.X) / 2, (Lo.Y + Hi.Y) / 2, (Lo.Z + Hi.Z) / 2);
            P := Project(V, Mid);
            V.OX := SW / 2 - P.X;
            V.OY := SH / 2 - P.Y;
          end;
          FD.Doc.Render(Sheet, V, FD.Units, FDimFont, Pix(20, 20, 20), FEdgeW);
          Printer.Canvas.StretchDraw(
            Rect(0, 0, Printer.PageWidth, Printer.PageHeight), Sheet.AsBitmap);
        finally
          Sheet.Free;
        end;
        if All then
          FCmdMsg := Format('Printed %d sheets at %s%s.',
            [NPages, CurScale.Name,
             IfThen(FD.Units = usImperial, ' = 1''-0"', '')])
        else
          FCmdMsg := 'Printed at ' + CurScale.Name +
            IfThen(FD.Units = usImperial, ' = 1''-0"', '') +
            '.  /print all does every sheet; /print full lays it out 1:1 ' +
            'across pages.';
      end
      else
      begin
        Scale := Min(Printer.PageWidth / FArt.Width,
                     Printer.PageHeight / FArt.Height) * 0.92;
        R := Bounds(Round((Printer.PageWidth - FArt.Width * Scale) / 2),
                    Round((Printer.PageHeight - FArt.Height * Scale) / 2),
                    Round(FArt.Width * Scale), Round(FArt.Height * Scale));
        Printer.Canvas.StretchDraw(R, FArt.AsBitmap);
      end;
      end;
    finally
      Printer.EndDoc;
    end;
    FCmdMsg := 'Sent to the printer.';
    InvalidateStatus;
  except
    on E: Exception do
      MessageDlg('Could not print', E.Message, mtError, [mbOK], 0);
  end;
  { back to the sheet that was showing }
  FTabIdx := EnsureRange(Was, 0, High(FDrawings));
  FD := FDrawings[FTabIdx];
  Invalidate;
end;

{ ======================================================================== }
{ settings                                                                  }
{ ======================================================================== }

{ The drawing as a Heck file (see hsHeckFile): the sheets asked for, each
  with its view and camera, and in a session its file and document too.  The
  camera goes along so a drawing (or a report's drawing) opens as it was
  being looked at. }
procedure TMainForm.BuildSession(L: TStrings; Session: Boolean; Key: Integer; Quick: Boolean;
  ShownFirst: Boolean);
var
  I, K: Integer;
  Sheets: THeckSheets;
  S: THeckSheet;
begin
  Sheets := nil;
  for K := 0 to High(FDrawings) do
  begin
    { for a report, the sheet on screen goes first: the collector takes the
      first sheet as the report's drawing }
    I := K;
    if ShownFirst and (FTabIdx >= 0) and (FTabIdx <= High(FDrawings)) then
    begin
      if K = 0 then I := FTabIdx
      else if K <= FTabIdx then I := K - 1;
    end;
    if not Session and (Key >= 0) and (FDrawings[I].DocKey <> Key) then Continue;
    S := Default(THeckSheet);
    S.Name := FDrawings[I].Name;
    S.Doc := FDrawings[I].Doc;       { lent, not copied }
    S.Units := FDrawings[I].Units;
    S.ScaleIdx := FDrawings[I].ScaleIdx;
    S.SnapIdx := FDrawings[I].SnapIdx;
    S.View := FDrawings[I].View;
    S.CamKnown := True;
    S.Az := FDrawings[I].Az; S.El := FDrawings[I].El; S.Zoom := FDrawings[I].Zoom;
    S.ViewX := FDrawings[I].ViewX; S.ViewY := FDrawings[I].ViewY;
    S.SliceOn := FDrawings[I].SliceOn;
    S.SliceLo := FDrawings[I].SliceLo; S.SliceHi := FDrawings[I].SliceHi;
    S.HasSession := Session;
    S.DocKey := FDrawings[I].DocKey;
    S.FilePath := FDrawings[I].FilePath;
    S.DocName := FDrawings[I].DocName;
    S.Dirty := FDrawings[I].Dirty;
    SetLength(Sheets, Length(Sheets) + 1);
    Sheets[High(Sheets)] := S;
  end;
  WriteHeckFile(Sheets, L, Session, Quick);
end;

{ Long work reports progress here: on the splash (with its skip button)
  while that is up, otherwise on the command bar by letting messages through,
  which is why every input handler checks FBusy.  False means the skip was
  pressed. }
function TMainForm.OnProgress(const What: string; Frac: Double): Boolean;
var
  T: QWord;
begin
  Result := True;
  if SplashUp then
  begin
    SplashStatus(What, Frac, FLoading);
    if SplashSkipAsked then
    begin
      FLoadSkipped := True;
      Result := False;
    end;
    Exit;
  end;
  T := GetTickCount64;
  { A full repaint costs 100 ms or more on a big drawing and this is called
    every few dozen regions, so paint at most every quarter second, longer
    when the last paint was slow. }
  if FBusy and (T - FBusyAt < Max(250, 4 * FBusyPaintMs)) then Exit;
  FBusy := True;
  FBusyAt := T;
  FBusyMsg := What;
  FBusyFrac := Frac;
  { Invalidate and ProcessMessages are not enough: GTK3 paints on its frame
    clock, which a busy main thread never reaches.  Repaint on the bar's
    parent forces the paint through (gdk_window_process_updates). }
  Application.ProcessMessages;
  pbCmd.Invalidate;
  if pbCmd.Parent <> nil then pbCmd.Parent.Repaint;
  Application.ProcessMessages;
  FBusyPaintMs := GetTickCount64 - T;
  FBusyAt := GetTickCount64;
end;

{ what the splash says when loading is over }
function TMainForm.LoadedWords: string;
var
  I, N: Integer;
begin
  if FLoadSkipped then Exit('Skipped that drawing - starting with a clean sheet.');
  N := 0;
  for I := 0 to High(FDrawings) do N := N + FDrawings[I].Doc.Live;
  if N = 0 then Exit('Ready.');
  if Length(FDrawings) = 1 then
    Result := Format('Ready.  %d things on one sheet.', [N])
  else
    Result := Format('Ready.  %d things on %d sheets.', [N, Length(FDrawings)]);
end;

procedure TMainForm.EndBusy;
begin
  if not FBusy then Exit;
  FBusy := False;
  pbCmd.Invalidate;
end;

{ Drop the draft.  It is a net under unsaved work, not a record of what the
  user wants back, so finishing with a drawing must clear it too or the next
  launch brings it back. }
procedure TMainForm.DropDraft;
begin
  try
    if FileExists(DraftFile) then DeleteFile(DraftFile);
  except
    on E: Exception do ;
  end;
  FDraftSeq := FEditSeq;
end;

{ Keep a draft of all unsaved work, named or not, so a crash loses nothing.
  Written to a temporary and renamed, so a crash mid-write cannot spoil it. }
procedure TMainForm.SaveDraft;
var
  L: TStringList;
  Tmp: string;
begin
  if Length(FDrawings) = 0 then Exit;
  { nothing unsaved, nothing to recover }
  if AnyDirty = 0 then
  begin
    DropDraft;
    Exit;
  end;
  { All of it is wrapped: a background autosave must never take the program
    down.  Whatever fails, the seq is marked done so it does not retry every
    tick. }
  try
    L := TStringList.Create;
    try
      BuildSession(L, True, -1, True);
      { A temporary unique to this run, so two copies of the program cannot
        interleave writes into one file.  Rename straight over the target
        first (atomic on Unix); only if that fails remove the target first,
        as Windows needs. }
      Tmp := DraftFile + '.' + FRunTag + '.tmp';
      ForceDirectories(ExtractFilePath(DraftFile));
      L.SaveToFile(Tmp);
      if not RenameFile(Tmp, DraftFile) then
      begin
        if FileExists(DraftFile) then DeleteFile(DraftFile);
        if not RenameFile(Tmp, DraftFile) then DeleteFile(Tmp);
      end;
    finally
      L.Free;
    end;
  except
    on E: Exception do
      FCmdMsg := 'Could not keep a draft just now (' + E.ClassName + ')';
  end;
  FDraftSeq := FEditSeq;
end;

{ Drafts left by a run that did not close properly (crash, kill, pulled
  plug), offered back.  A clean close drops the draft, so one found at start
  is unanswered work.  Declined, it is kept aside rather than thrown away. }
procedure TMainForm.OfferRecovery;
var
  Ans: Integer;
  Aside: string;
begin
  if not FileExists(DraftFile) then Exit;
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  Ans := QuestionDlg('Recover your drawings',
    'Heckers Sketch did not close properly last time, and kept a copy of the drawings that had work not ' +
    'saved yet.  Recover them?',
    mtConfirmation,
    [mrYes, 'Recover them', 'IsDefault',
     mrNo, 'Start without them', 'IsCancel'], 0);
  if Ans = mrYes then
  begin
    RestoreDraft;
    RefreshChrome;
    pbCmd.Invalidate;
    Exit;
  end;
  Aside := ChangeFileExt(DraftFile, '') + '-not-recovered.hsk';
  if FileExists(Aside) then DeleteFile(Aside);
  RenameFile(DraftFile, Aside);
  FCmdMsg := 'Not recovered.  A copy is kept beside the settings as ' + ExtractFileName(Aside) +
    ', and can be opened.';
  pbCmd.Invalidate;
end;

{ Read the draft back once OfferRecovery says to: each file with unsaved work
  as the file it was, path and sheets, still unsaved so Save writes it back. }
function TMainForm.RestoreDraft: Boolean;
var
  L: TStringList;
  Aside: string;
  Ini: TIniFile;
  First, I, N: Integer;
  Blank: TDrawing;
begin
  Result := False;
  if not FileExists(DraftFile) then Exit;
  { an empty draft is not worth restoring }
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(DraftFile);
    except
      Exit;
    end;
    if L.Count < 3 then Exit;
  finally
    L.Free;
  end;

  { If the flag is still set, the last run died reading this draft, and
    restoring it again would loop forever.  Set it aside (kept) and start
    clean. }
  Ini := TIniFile.Create(ConfigFile);
  try
    if Ini.ReadBool('startup', 'restoring', False) then
    begin
      { kept under a name the Open dialog can see }
      Aside := ChangeFileExt(DraftFile, '') + '-would-not-open.hsk';
      if FileExists(Aside) then DeleteFile(Aside);
      RenameFile(DraftFile, Aside);
      Ini.WriteBool('startup', 'restoring', False);
      Ini.WriteInteger('startup', 'crashes', 0);
      FCmdMsg := 'The last drawing would not open - it is kept beside the ' +
        'settings as ' + ExtractFileName(Aside) + ' and can be opened.';
      Exit;
    end;

    { Two crashes in a row with this drawing open: it opens fine but kills
      the program later, every time.  Stand it down instead of loading it a
      third time; it is kept and named on screen. }
    if Ini.ReadInteger('startup', 'crashes', 0) >= 2 then
    begin
      Aside := ChangeFileExt(DraftFile, '') + '-crashed.hsk';
      if FileExists(Aside) then DeleteFile(Aside);
      RenameFile(DraftFile, Aside);
      Ini.WriteInteger('startup', 'crashes', 0);
      FCmdMsg := 'It crashed twice with the last drawing open, so this run ' +
        'starts empty.  The drawing is kept as ' + ExtractFileName(Aside) +
        ' - open it when you want it.';
      Exit;
    end;
    Ini.WriteBool('startup', 'restoring', True);
  finally
    Ini.Free;
  end;

  { a draft is read before anything else happens, so a bad one must not
    take the program down on the way up }
  Blank := nil;
  if (Length(FDrawings) = 1) and (FDrawings[0].FilePath = '') and not FDrawings[0].Dirty and
     (FDrawings[0].Doc.Live = 0) then Blank := FDrawings[0];
  try
    try
      if not ReadSheets(DraftFile, True, First) then Exit;
    except
      on E: Exception do
      begin
        FCmdMsg := 'The last draft would not load (' + E.ClassName +
          ') - starting empty.';
        Exit;
      end;
    end;
  finally
    { The flag means "reading a draft", which stops being true the moment the
      read returns, however it went.  Clearing it on a timer instead made a
      quick close look like a crash while reading.  Later failures are the
      crash counter's job. }
    with TIniFile.Create(ConfigFile) do
    try
      WriteBool('startup', 'restoring', False);
    finally
      Free;
    end;
  end;
  if FLoadSkipped then
  begin
    { skipped on the splash: keep it aside under an openable name, or it
      returns next time and is overwritten by the first new line }
    Aside := ChangeFileExt(DraftFile, '') + '-skipped.hsk';
    if FileExists(Aside) then DeleteFile(Aside);
    RenameFile(DraftFile, Aside);
    FCmdMsg := 'Skipped loading the last drawing.  It is kept beside the ' +
      'settings as ' + ExtractFileName(Aside) + ' and can be opened.';
    Exit;
  end;
  { the empty drawing the program started with gives way }
  if Blank <> nil then
  begin
    LeaveSheet;
    for I := 0 to High(FDrawings) - 1 do FDrawings[I] := FDrawings[I + 1];
    SetLength(FDrawings, Length(FDrawings) - 1);
    Blank.Free;
    FD := nil;
    Dec(First);
  end;
  ShowLoaded(First);
  { each comes back as the file it was, its unsaved work still unsaved, so
    Save writes it back and closing asks }
  N := AnyDirty;
  FRestored := True;
  Result := True;
  Inc(FEditSeq);
  Trail(Format('recovered a draft: %d tabs, %d files not saved', [Length(FDrawings), N]));
  FCmdMsg := Format('Recovered %d drawing%s - save %s to keep %s.', [N, IfThen(N = 1, '', 's'),
    IfThen(N = 1, 'it', 'them'), IfThen(N = 1, 'it', 'them')]);
end;

{ The jigs the program carries, put in the jigs folder by the examples' rule:
  one changed there is the user's and is left alone. }
procedure TMainForm.WriteJigs;
var
  Ini: TIniFile;
  L: TStringList;
  I: Integer;
  Rec: string;
begin
  try
    Ini := TIniFile.Create(ConfigFile);
    L := TStringList.Create;
    try
      for I := 0 to JigFileCount - 1 do
      begin
        L.Clear;
        JigFileLines(I, L);
        Rec := Ini.ReadString('jigs', JigFileName(I), '');
        case PutCarried(JigsDir + JigFileName(I), L, Rec) of
          ewWritten, ewUpToDate:
            Ini.WriteString('jigs', JigFileName(I), Rec);
          ewKeptTheirs:
            Trail('jig ' + JigFileName(I) + ' has been changed here - left alone');
        end;
      end;
    finally
      L.Free;
      Ini.Free;
    end;
  except
    on E: Exception do ;
  end;
end;

{ Put the example drawings on disk beside the program, to reopen, share or
  read.  Each is checked against what was written last (see PutExample): one
  saved over since is left alone; an untouched one gets the newer version.
  Delete your copy to get the original back. }
procedure TMainForm.WriteExamples;
var
  Ini: TIniFile;
  I: Integer;
  Rec: string;
begin
  try
    if not ForceDirectories(ExamplesDir) then Exit;
    Ini := TIniFile.Create(ConfigFile);
    try
      for I := 0 to ExampleCount - 1 do
      begin
        Rec := Ini.ReadString('examples', ExampleFile(I), '');
        case PutExample(I, ExamplesDir, Rec) of
          ewWritten, ewUpToDate:
            Ini.WriteString('examples', ExampleFile(I), Rec);
          ewKeptTheirs:
            Trail('example ' + ExampleFile(I) + ' has been changed here - left alone');
        end;
      end;
    finally
      Ini.Free;
    end;
  except
    { a read-only folder, a full disk, a pulled stick: not worth a word }
    on E: Exception do ;
  end;
end;

{ The example drawing (Open the Example on the menu): an etch-a-sketch to
  orbit, push and poke at.  It arrives as an unsaved drawing, not a file, so
  Ctrl+S asks where and the example on disk is never overwritten. }
function TMainForm.LoadExample: Boolean;
var
  L: TStringList;
  Sheets: THeckSheets;
  I, ErrLine: Integer;
  Err: string;
begin
  Result := False;
  Sheets := nil;
  L := TStringList.Create;
  try
    try
      ExampleDrawing(L);
      { carried as Heck, as written out (see hsHeckFile) }
      if not ReadDrawingFile(L, Sheets, ErrLine, Err) or (Length(Sheets) = 0) then Exit;
      FD.Name := Sheets[0].Name;
      FD.Doc.Free;
      FD.Doc := Sheets[0].Doc;
      Sheets[0].Doc := nil;
      for I := 1 to High(Sheets) do Sheets[I].Doc.Free;
    except
      { an example that will not load is not worth crashing for }
      on E: Exception do Exit;
    end;
  finally
    L.Free;
  end;
  if FD.Doc.Live = 0 then Exit;
  FD.View := vkOrbit;
  FD.Az := -0.785398;
  FD.El := 0.700000;
  FD.ScaleIdx := 4;
  FD.SnapIdx := 1;
  { a drawing of its own, not a file: Save asks where it goes }
  FD.DocName := FD.Name;
  { Not the user's work until they change it, so it is not unsaved.  Only
    this sheet: setting the window-wide FSavedSeq marked every sheet saved
    (see TDrawing.Dirty). }
  FSavedSeq := FEditSeq;
  FD.Dirty := False;
  { as when opening a file: its faces say which areas are filled, so seed
    them as seen or the first rebuild works over faces that were right }
  SeedRegions;
  Result := True;
  FitView(False);
  Trail(Format('opened the example: %d things', [FD.Doc.Live]));
  FCmdMsg := 'This is the example drawing - orbit it, push a face, or ' +
    'press Ctrl+N to start your own.';
end;

{ Is a window at this place reachable?  Every monitor is asked (a monitor
  left of or above the primary has negative coordinates), and enough of the
  window must land on one to grab and drag. }
function TMainForm.OnAScreen(L, T, W, H: Integer): Boolean;
var
  I: Integer;
  R, X: TRect;
begin
  Result := False;
  R := Rect(L, T, L + W, T + H);
  for I := 0 to Screen.MonitorCount - 1 do
    if IntersectRect(X, R, Screen.Monitors[I].WorkareaRect) and
       (X.Right - X.Left >= 160) and (X.Bottom - X.Top >= 80) then
      Exit(True);
end;

{ The drawing settings, from the section older builds called pro when they
  have not been saved under the new name yet. }
function DrawingInt(Ini: TIniFile; const Key: string; Dflt: Integer): Integer;
begin
  Result := Ini.ReadInteger('drawing', Key, Ini.ReadInteger('pro', Key, Dflt));
end;

procedure TMainForm.LoadSettings;
var
  Ini: TIniFile;
  WW, WH, WL, WT, I: Integer;
begin
  FInkColor := PALETTE[0];
  FInkAuto := True;
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      hsRecorder.RecentWalks := Ini.ReadString('export', 'recentwalks', '');
      { commands used lately, so the list offers them first }
      FCmdRecent := Ini.ReadString('cmd', 'recent', '');
      { where things went last time; exports as "ext=folder" lines per kind }
      FSaveDir := Ini.ReadString('paths', 'drawings', '');
      FRecent.Clear;
      for I := 1 to 10 do
        if Ini.ReadString('recent', 'file' + IntToStr(I), '') <> '' then
          FRecent.Add(Ini.ReadString('recent', 'file' + IntToStr(I), ''));
      FOpenDir := Ini.ReadString('paths', 'open', '');
      FExportDirs.Clear;
      Ini.ReadSectionValues('exportpaths', FExportDirs);
      FCubeOn := Ini.ReadBool('look', 'cube', False);
      CameraLamp := Ini.ReadBool('look', 'cameralamp', True);
      FSourceWasOpen := Ini.ReadBool('source', 'open', False);
      FSourceOnTop := Ini.ReadBool('source', 'ontop', False);
      FSourceComplete := Ini.ReadBool('source', 'complete', True);
      FSourceBounds := Rect(Ini.ReadInteger('source', 'left', 0), Ini.ReadInteger('source', 'top', 0),
        Ini.ReadInteger('source', 'width', 0), Ini.ReadInteger('source', 'height', 0));
      FInfoOn := Ini.ReadBool('look', 'info', False);
      FGroupsOn := Ini.ReadBool('look', 'groups', True);
      FCubeCorner := EnsureRange(Ini.ReadInteger('look', 'cubecorner', 1), 0, 3);
      FCubeFitSel := Ini.ReadBool('look', 'cubefit', True);
      { by name, so the list can change; older builds kept an index under
        protheme, 4 for Light and 5 for Dark }
      FThemeIdx := ThemeNamed(Ini.ReadString('look', 'themename', ''));
      if (FThemeIdx < 0) and (Ini.ReadInteger('look', 'protheme', 5) = 4) then
        FThemeIdx := THEME_LIGHT;
      if FThemeIdx < 0 then FThemeIdx := THEME_DARK;
      { the measured grid is off until asked for, like SketchUp; a saved
        setting is kept }
      FShowGrid := Ini.ReadBool('look', 'grid', False);
      FEdgeW := EnsureRange(DrawingInt(Ini, 'linew', 1), MIN_PEN, MAX_PEN);
      FInkColor := TColor(Ini.ReadInteger('pen', 'ink', PALETTE[0]));
      FInkAuto := Ini.ReadBool('pen', 'inkauto', True);
      { tool names on by default, for first-timers }
      FToolsWide := Ini.ReadBool('drawing', 'toolnames',
        Ini.ReadBool('pro', 'toolnames', True));
      FD.ScaleIdx := EnsureRange(DrawingInt(Ini, 'scale', 2), 0, SCALE_COUNT - 1);
      FD.SnapIdx := EnsureRange(DrawingInt(Ini, 'snap', 5), 0, SNAP_COUNT - 1);
      SetLenDenom(DrawingInt(Ini, 'precision', 16));
      FLenDenom := LenDenom;
      FD.Units := TUnitSystem(EnsureRange(DrawingInt(Ini, 'units', 0), 0, 1));
      { the view is deliberately not restored }

      { Where the window was, only if it still lands on a screen (monitors get
        unplugged), and the size clamped to what the screen can show. }
      WW := Ini.ReadInteger('win', 'w', 0);
      WH := Ini.ReadInteger('win', 'h', 0);
      WL := Ini.ReadInteger('win', 'x', MaxInt);
      WT := Ini.ReadInteger('win', 'y', MaxInt);
      if (WW > 200) and (WH > 200) then
      begin
        WW := Min(WW, Screen.DesktopWidth);
        WH := Min(WH, Screen.DesktopHeight);
      end
      else
      begin
        { First run on this machine: the design size is 96 dpi pixels, scaled
          up here once since the chrome scales itself.  Only here: the form's
          Scaled is off, or a saved size would grow by the factor every run. }
        WW := Round(Width * FUIScale);
        WH := Round(Height * FUIScale);
        WW := Min(WW, Screen.DesktopWidth);
        WH := Min(WH, Screen.DesktopHeight);
      end;
      if (WL <> MaxInt) and (WT <> MaxInt) and OnAScreen(WL, WT, WW, WH) then
      begin
        { poDesigned, or the widget set centers the window at first show
          despite SetBounds }
        Position := poDesigned;
        SetBounds(WL, WT, WW, WH);
      end
      else
      begin
        SetBounds(Left, Top, WW, WH);
        Position := poScreenCenter;
      end;
      if Ini.ReadBool('win', 'max', False) then
        WindowState := wsMaximized;
    finally
      Ini.Free;
    end;
  except
    { first run, or a read-only config dir: the defaults are fine }
  end;
end;

procedure TMainForm.SaveSettings;
var
  Ini: TIniFile;
  I: Integer;
begin
  try
    ForceDirectories(ExtractFilePath(ConfigFile));
    Ini := TIniFile.Create(ConfigFile);
    try
      Ini.WriteBool('look', 'cube', FCubeOn);
      Ini.WriteBool('look', 'cameralamp', CameraLamp);
      { the source window: whether it was open, and where }
      Ini.WriteBool('source', 'open', FSourceWasOpen);
      Ini.WriteBool('source', 'ontop', FSourceOnTop);
      Ini.WriteBool('source', 'complete', FSourceComplete);
      if FSourceBounds.Right > 0 then
      begin
        Ini.WriteInteger('source', 'left', FSourceBounds.Left);
        Ini.WriteInteger('source', 'top', FSourceBounds.Top);
        Ini.WriteInteger('source', 'width', FSourceBounds.Right);
        Ini.WriteInteger('source', 'height', FSourceBounds.Bottom);
      end;
      Ini.WriteBool('look', 'info', FInfoOn);
      Ini.WriteBool('look', 'groups', FGroupsOn);
      Ini.WriteInteger('look', 'cubecorner', FCubeCorner);
      Ini.WriteBool('look', 'cubefit', FCubeFitSel);
      Ini.WriteString('look', 'themename', Theme.Name);
      Ini.WriteBool('look', 'grid', FShowGrid);
      Ini.WriteInteger('drawing', 'linew', FEdgeW);
      Ini.WriteInteger('pen', 'ink', FInkColor);
      Ini.WriteBool('pen', 'inkauto', FInkAuto);
      Ini.WriteBool('drawing', 'toolnames', FToolsWide);
      Ini.WriteInteger('drawing', 'scale', FD.ScaleIdx);
      { camera moves used lately, so the list offers them first }
      Ini.WriteString('export', 'recentwalks', hsRecorder.RecentWalks);
      Ini.WriteString('cmd', 'recent', FCmdRecent);
      Ini.WriteString('paths', 'drawings', FSaveDir);
      Ini.EraseSection('recent');
      for I := 0 to FRecent.Count - 1 do
        Ini.WriteString('recent', 'file' + IntToStr(I + 1), FRecent[I]);
      Ini.WriteString('paths', 'open', FOpenDir);
      Ini.EraseSection('exportpaths');
      for I := 0 to FExportDirs.Count - 1 do
        if FExportDirs.Names[I] <> '' then
          Ini.WriteString('exportpaths', FExportDirs.Names[I],
            FExportDirs.ValueFromIndex[I]);
      Ini.WriteInteger('drawing', 'snap', FD.SnapIdx);
      Ini.WriteInteger('drawing', 'precision', FLenDenom);
      Ini.WriteInteger('drawing', 'units', Ord(FD.Units));

      { The window position was taken in OnClose; if the form never closed,
        this is the last chance and may get nothing, in which case the old
        position stays.  Reaching here means no crash, so reset the tally. }
      Ini.WriteInteger('startup', 'crashes', 0);

      if not FWinSaved then RememberWindow;
      if FWinSaved then
      begin
        Ini.WriteBool('win', 'max', FWinMax);
        Ini.WriteInteger('win', 'x', FWinL);
        Ini.WriteInteger('win', 'y', FWinT);
        Ini.WriteInteger('win', 'w', FWinW);
        Ini.WriteInteger('win', 'h', FWinH);
      end;
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  except
    { never let a settings problem stop the program closing }
  end;
end;

{ what /sysinfo shows (see hsFacts) }
procedure TMainForm.ShowFacts(const Title, AText: string);
begin
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  ShowFactsBox(Self, Title, AText);
end;

{ a long report section, to read and copy (see hsLongText) }
procedure TMainForm.ShowLongText(const Title, AText: string);
begin
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  if TLongTextForm.ShowText(Self, Title, AText) then FCmdMsg := 'Copied.';
end;

{ the about box (see hsAbout) }
procedure TMainForm.ShowAbout;
begin
  hsDialogSkin.UseTheme(Themes[FThemeIdx]);
  ShowAboutBox(Self);
end;

initialization
  OnGetApplicationName := @SketchAppName;

end.

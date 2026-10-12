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
  hsSurface, hsSkin, hsViewCube, hsDialogSkin, hsFilm, hsRecorder, hsExport, hsExToy, hsExamples, hsDrawing, hsSplash, hsSysInfo, hsTouch,
  hsFaceFinder, hsUpdater, hsUpdateForm, hsWhatsNew, hsPaths,
  hsBugReport, hsNet, hsUnfold, hsFlatView, hsTunnels, hsSendReport, hsSourceWindow, hsAssistant, hsPostcard, hsHeckWriter, hsHeckReader,
  hsJigRun, hsJigFiles, hsFittings, hsTransitionWizard, hsSpoolWizard, hsPipe,
  hsStairs, hsStairWizard, hsStringerSheet, hsHeckFile, hsRadiantData, hsRadiant, hsRadiantWizard, hsRadiantSubmittal, hsRadiantJob,
  hsCommandText, InkPage, InkDraw, FileAssMan, FATypes;

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
    X, Y, X0, Y0: integer;
    T0: QWord;
  end;
  { none; one finger down, not yet a tap or a drag; one finger as the mouse;
    two fingers panning and pinching; gesture over, remaining finger ignored }
  TTouchMode = (tmNone, tmPending, tmMouse, tmGesture, tmSpent);
  { what a click or box does to what is already selected }
  TSelMode = (smOnly, smAdd, smToggle, smRemove);

  { One line of the entity panel, with its steppers when the value can be
    changed.  The painter reads this and the mouse hit test uses the same rects. }
  TInfoAct = (iaNone, iaSides, iaSoft, iaNoteSize, iaReverse, iaWidth, iaColor,
    iaMaterial, iaUnpaint, iaPartOpen, iaPartLock, iaPartExplode, iaPartRename,
    iaPartHide);

  TInfoRow = record
    Caption: string;
    Value: string;
    Act: TInfoAct;
    Ent: integer;
    Head: boolean;          { a section heading rather than a value }
    Minus, Plus: TRect;     { empty unless Act says otherwise }
  end;

  { One line of the groups panel.  Fold and Tick are where they were painted,
    which is where the mouse looks for them. }
  TGrpRow = record
    Id: integer;            { 0 is the sheet itself, above every group }
    Depth: integer;
    Kids: boolean;
    Fold, Tick: TRect;
  end;

  { Enough of a flat area to recognize it at the next rebuild.  Plane and area,
    not corners: corners change when something is stood on an edge.  Mid tells
    two identical windows in one wall apart. }
  TRegionSig = record
    Nm: TP3;
    D: double;
    Area: double;
    Mid: TP3;
    Part: integer;      { the group the area was found in }
  end;

  { the region finder's cache, one per group - a plane shared by two groups
    must not hand one group's areas to the other }
  TPartCache = record
    Part: integer;
    Cache: TRegionCache;
  end;

  { Everything the paper is a picture of; if none of it moved, neither did
    the paper.  See TMainForm.RepaintPaper. }
  TPaperSig = packed record
    ThemeIdx, W, H: integer;
    View: TViewKind;
    Units: TUnitSystem;
    Grid: boolean;
    Ppu, ViewX, ViewY, Az, El, Zoom, Snap, UIScale: double;
  end;

  { One sheet: everything that belongs to a drawing rather than to
    the program, so tabs are just a list of these. }
  TDrawing = class
    Doc: TWorkDoc;
    Name: string;
    ViewX, ViewY: double;      // screen position of world 0,0
    Zoom: double;              // magnification only; the print scale is ScaleIdx
    ScaleIdx: integer;
    SnapIdx: integer;
    Units: TUnitSystem;
    View: TViewKind;        // PLAN, ISO or free 3D
    Plane: TPlane;          // which plane new arcs and mouse picks land on
    Az, El: double;         // 3D camera, radians
    { True when the camera came from a file; such a sheet must not be
      reframed on top of it. }
    CamKnown: boolean;
    { Edited since this sheet was loaded or saved.  Kept per sheet, not per
      window: a window-wide flag let closing one tab skip the save prompt
      because making a new sheet marked everything saved. }
    Dirty: boolean;
    { The file this sheet belongs to.  All sheets of one document share
      DocKey, FilePath and DocName, and their tabs sit together.  FilePath is
      '' until saved; DocName is then "Untitled 2" and so on. }
    DocKey: integer;
    FilePath: string;
    DocName: string;
    { The plan view's section slice; a floor plan is a cut, not a view from
      above.  Only used in PLAN; see TMainForm.ApplySlice. }
    SliceOn: boolean;
    SliceLo, SliceHi: double;
    { The flat areas at the last rebuild.  An area that had a face and now
      has none was erased on purpose and must not be given a new face. }
    Seen: array of TRegionSig;
    Undo, Redo: array of TWorkEntArray;
    UndoTop, RedoTop: integer;
    constructor Create(const AName: string);
    destructor Destroy; override;
  end;

  TDeckKind = (dkNone, dkSegment, dkIcon);

  TDeckItem = record
    Kind: TDeckKind;
    Bounds: TRect;
    Group: integer;
    Value: integer;
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
    FileAss: TFileAssMan;
    pbCmd: TPaintBox;
    pbTabs: TPaintBox;
    pbSlice: TPaintBox;
    pbTools: TPaintBox;
    pbInfo: TPaintBox;
    pbGroups: TPaintBox;
    pbQuick: TPaintBox;
    pmView: TPopupMenu;
    pmCanvas: TPopupMenu;
    pmFile: TPopupMenu;
    pmEdit: TPopupMenu;
    pmSettings: TPopupMenu;
    pmHelp: TPopupMenu;
    pmGroups: TPopupMenu;
    pmCmd: TPopupMenu;
    pbScreen: TPaintBox;
    tmrTick: TTimer;
    function ExportDirFor(const Ext: string): string;
    procedure KeepExportDir(const Ext, Dir: string);
    function SaveDirNow: string;
    function OpenDirNow: string;
    { the command list's order: used lately first, then alphabetical }
    procedure BuildCmdOrder;
    function CmdIndex(const W: string): integer;
    procedure TimingLine(const S: string);
    procedure ShowTimingLog;
    function CmdAliasFor(Idx: integer; const Want: string): string;
    procedure SyncCmdList;
    procedure TakeCmdHighlight;
    procedure MoveCmdHighlight(Key: word);
    { True when what is typed is already the whole name of a command }
    function ExactCmd(const S: string): boolean;
    procedure NoteCmdUsed(const Cmd: string);
    procedure CornerSelection;
    procedure ShowOpenEdges;
    procedure OpenManual;
    procedure KeepHelpCurrent;
    procedure HelpFetchProgress(BytesReceived, TotalBytes: int64);
    procedure HelpFetchDone(Sender: TObject);
    { the system color picker, for a pen that is not on the palette }
    procedure PickAnyColor;
    function AskColor(Was: TColor; out C: TColor): boolean;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: boolean);
    function AnyDirty: integer;
    procedure FormDestroy(Sender: TObject);
    procedure RememberWindow;
    function OnAScreen(L, T, W, H: integer): boolean;
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure FormKeyPress(Sender: TObject; var Key: char);
    procedure FormKeyUp(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure FormPaint(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure pbCmdPaint(Sender: TObject);
    procedure pbCmdMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure pbCmdMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure pbCmdMouseLeave(Sender: TObject);
    procedure pbTabsMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure pbTabsMouseLeave(Sender: TObject);
    procedure pbTabsMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure pbTabsPaint(Sender: TObject);
    procedure pbQuickPaint(Sender: TObject);
    procedure pbQuickMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure pbQuickMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure pbQuickMouseLeave(Sender: TObject);
    procedure RebuildQuick;
    function QuickHit(X, Y: integer): integer;
    function QuickWidth: integer;
    { the menus those buttons open; each is filled fresh as it opens }
    procedure OpenBarMenu(Index: integer);
    function BarPopup(Index: integer): TPopupMenu;
    procedure CloseBarMenu;
    procedure TrackBarMenu;
    function BarMenuPoint(Index: integer): TPoint;
    procedure ShowEditMenu;
    procedure EditMenuClick(Sender: TObject);
    procedure ShowViewMenu;
    procedure ShowSettingsMenu;
    procedure SettingsMenuClick(Sender: TObject);
    procedure ShowHelpMenu;
    procedure HelpMenuClick(Sender: TObject);
    procedure pbToolsPaint(Sender: TObject);
    function InfoPanelWidth: integer;
    function GroupsPanelOn: boolean;
    procedure SetGroupsPanel(On_: boolean);
    procedure RebuildGroupRows;
    function GroupRowAt(Y: integer): integer;
    function GroupPutAway(Id: integer): boolean;
    procedure PickGroupFromPanel(Id: integer; Add: boolean);
    procedure ShowGroupFromPanel(Id: integer; Shown: boolean);
    procedure GroupsMenuClick(Sender: TObject);
    procedure GroupsChanged;
    procedure InfoChanged;
    { the source window - see hsSourceWindow.  It asks; these answer. }
    procedure ShowSource;
    { the source window in the program's theme - at opening, and whenever
      the theme changes }
    procedure ThemeSourceWindow;
    procedure SourceAskState(out DocSeq, PickSeq: int64);
    procedure SourceAskSource(L, Hints, Names: TStrings; out First, Last, LineThing: TIntArrayW; out SheetName: string);
    procedure SourceAskPicked(out Picked: TIntArrayW);
    procedure SourcePickThings(const Things: TIntArrayW);
    function SourceApply(L: TStrings; out ErrLine: integer; out Err: string): boolean;
    function SourceCheck(L: TStrings; out ErrLine: integer; out Err: string): boolean;
    procedure AssistantUseHeck(const Code: string);
    procedure ShowNotes(On: boolean);
    { run the jig that makes this group again; 0 runs every jig on the sheet }
    function RunJigOf(PartId: integer): boolean;
    { the same, from the group's record - the source window's play button }
    function RunJigOfThing(Thing: integer): boolean;
    { the source window's Pick: clicks on the sheet type places into it }
    procedure SourcePick(On: boolean);
    function RunAllJigs: integer;
    procedure SourceCenter;
    procedure RebuildInfo;
    procedure PaintInfoStep(C: TCanvas; const R: TRect; const S: string; Hot: boolean);
    function InfoHit(X, Y: integer): integer;
    procedure pbInfoPaint(Sender: TObject);
    procedure pbInfoMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure pbInfoMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure pbInfoMouseLeave(Sender: TObject);
    procedure pbGroupsPaint(Sender: TObject);
    procedure pbGroupsMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure pbGroupsMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure pbGroupsMouseLeave(Sender: TObject);
    procedure pbGroupsMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
    procedure pbToolsMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure pbToolsMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure pbToolsMouseLeave(Sender: TObject);
    procedure RebuildTools;
    function ToolsHit(X, Y: integer): integer;
    function ToolStripWidth: integer;
    procedure PaintChromeTip(C: TCanvas);
    procedure pbSlicePaint(Sender: TObject);
    procedure pbSliceMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure pbSliceMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure pbSliceMouseLeave(Sender: TObject);
    procedure pbSliceMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
    { which part of the cut strip a point is over: -1 none, 0 the label,
      1 the bottom field, 2 the top field, 3/4 its up arrows, 5/6 its downs }
    function SliceZoneAt(X, Y: integer): integer;
    function SliceFieldRect(Which: integer): TRect;
    procedure CommitSliceEdit;
    procedure ViewMenuClick(Sender: TObject);
    procedure pbScreenMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure pbScreenMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure pbScreenMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure pbScreenMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
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
    FPaperOK: boolean;
    FPaperPaints, FPaperSkips: integer;
    FInk: TArtSurface;        // ink, rendered from the document
    FInkHalf: TArtSurface;       // half its size, for a frame while the camera moves
    FArt: TArtSurface;           // paper + active ink; what you see and save
    FShell: TArtSurface;
    FCmdSkin: TArtSurface;
    { the message rows' last content, so they are set only on change, and
      row one's layout kept between caret blinks }
    FCmdMsgR: TRect;           { where the message rows are, in the bar }
    FCmdPillW: integer;        { the tool pill's column, left of them }
    FOverlay: TArtSurface;

    { --- look and pen --------------------------------------------------- }
    FUIScale: single;
    FThemeIdx: integer;
    { the weight new edges are drawn with }
    FEdgeW: integer;
    FInkColor: TColor;
    FInkAuto: boolean;
    FShowGrid: boolean;
    FBooted: boolean;
    FLastStatus: QWord;

    { --- sheets --------------------------------------------------------- }
    FDrawings: array of TDrawing;
    FTabIdx: integer;
    FD: TDrawing;                // the sheet on the active tab
    FTool: TTool;
    FTabRects: array of TRect;
    FHotTab: integer;
    FCur: TP3;                   // snapped cursor, world units
    FSnapKind: TSnapKind;
    { which of the three the cursor is on, when FSnapKind is snOnAxis }
    FSnapAxis: integer;
    FStage: integer;             // where we are in the current tool
    FP1, FP2: TP3;
    FDirLock: integer;           // -1 none, else an index into AxisDir
    FInput: string;              // what has been typed into the command bar
    FCmdMsg: string;             // last result / error shown in the bar
    { Where things were last saved and opened.  This is a portable program,
      so the first offer is a folder beside it, not the home folder; after
      that it is wherever the user went.  Exports are kept per file type as
      "ext=folder" lines. }
    { The open (unclosed) edges of solids, in pairs, from TWorkDoc.OpenEdges.
      Kept until the drawing changes; a stale answer is worse than none. }
    FOpenEdges: TP3Array;
    FOpenSeq: int64;
    FSaveDir, FOpenDir: string;
    FExportDirs: TStringList;
    FDimFont: TFont;

    { --- input ---------------------------------------------------------- }
    FPanning: boolean;
    FOrbiting: boolean;
    FOrbitGain: double;           { the trackball's leverage for this drag - see OrbitGainAt }
    FPushFace: integer;
    FReplayFace: integer;        { the face a replayed press is on, while it is pressed; -1 otherwise }
    { the face the offset tool is working on, or -1 }
    FOffFace: integer;
    FHoverFace: integer;   // the face push/pull would take, before you click

    { Held down, the eraser gathers everything dragged over and shows it red
      before deleting, so a stray hit can be seen first. }
    FErasing2: boolean;
    { The eraser's mode for this stroke, from the modifiers at press:
      0 erases, 1 softens, 2 unsoftens (SketchUp's Ctrl and Ctrl+Shift).
      Softening hides the creases along a pulled circle. }
    FEraseMode: integer;
    FDoomed: array of integer;

    { The selection and the pick box.  Left to right takes only what is
      wholly inside; right to left takes anything it touches, as SketchUp. }
    FSel: array of integer;
    FBoxing: boolean;
    FBoxX, FBoxY: integer;

    { from the command line: keep filling the screen if it changes size }
    FFill: (flNone, flMaximized, flFull);
    FScrW, FScrH: integer;

    { every corner the current move will carry, gathered once at the grab
      so the drag stays cheap }
    FMoveVerts: TP3Array;
    { nothing was selected, so the move tool took what was under the cursor
      and lets go of it once moved (see ToolCommit) }
    FMoveTook: boolean;
    { the guide the measure tool's right-click menu is about }
    FGuideMenuEnt: integer;
    { whole groups being moved or turned: they go rigidly, and loose
      geometry touching them is not stretched along }
    FMoveGroupEnts: TIntArrayW;
    FMoveCopy: boolean;
    { The entity panel on the right: what is picked and what can be changed
      about it.  Docked, not a dialog, so the figures update as you pick. }
    FInfoOn: boolean;
    { The groups panel (SketchUp's Outliner): a tree of groups with a box to
      hide each and a click to pick.  Sits under the entity panel. }
    FGroupsOn: boolean;
    FGrpRows: array of TGrpRow;
    FGrpHot: integer;         { the row under the pointer, or -1 }
    FGrpHotId: integer;       { its group, whose box the drawing shows }
    FGrpScroll: integer;      { rows scrolled off the top }
    FGrpFold: array of integer;  { groups shown closed }
    FGrpSig: int64;
    FGrpMenuId: integer;
    FGrpSkin: TArtSurface;
    FInfoRows: array of TInfoRow;
    FInfoHot: integer;
    FInfoSig: int64;
    { The clipboard: a deep copy detached from its document, so it survives
      a sheet switch and pastes into another sheet.  One per window. }
    FClip: TWorkEntArray;
    { Frame watchdog: time spent re-rendering ink, compositing and blitting,
      cleared at the start of each paint.  A frame over 1/40 s writes a line
      to the session log, so bug reports carry the diagnosis. }
    FMsPaper, FMsRender, FMsComp: QWord;
    FSlowN: integer;
    FSlowWorst: QWord;
    FSlowSaid: QWord;
    FSlowLast: string;
    { What the tape leaves: 0 point and guide line, 1 point only, 2 line
      only, 3 neither.  Ctrl cycles it while measuring.  0 is the default. }
    FTapeDrop: integer;
    { The tape's last run, kept so /keep can turn it into a dimension (see
      ptMeasure in ToolCommit). }
    FRunOK: boolean;
    FRunA, FRunB: TP3;
    { An edge just drawn over an existing one: SketchUp's "healing".  An
      erased face's area is remembered as unwanted; tracing one of its edges
      again says it is wanted after all, and this tells the region loop. }
    FHealOn: boolean;
    FHealA, FHealB: TP3;
    { /detach: a move takes the selection away alone instead of stretching
      what it is joined to.  Stretching is SketchUp's default and stays ours.
      A command, not a key, because Ctrl, Shift, Alt and every letter are taken. }
    FDetachMove: boolean;
    FLastPush: double;         // what a double-click repeats
    { The tape lays down a guide by default, like SketchUp's; Ctrl turns that
      off. }
    FMeasEdge: integer;        // the edge the tape was started on, or -1
    { Planes from the last rebuild are reused only when their segments hash
      the same, so this is safe across sheets. }
    { how many faces the last rebuild had to flip the right way out }
    FTurned: integer;
    FRegionCaches: array of TPartCache;

    { clicks in the same spot in quick succession: two takes what is
      attached, three everything joined on }
    FClickN: integer;
    { the corner the last arc rounded, kept for a double-click to trim, and
      the radius a double-click elsewhere repeats (see ArcFillet) }
    FLastFillet: TFillet;
    FFilletPending: boolean;
    FFilletSeq: int64;
    FFilletTick: QWord;
    FLastFilletR: double;
    FClickT: QWord;
    FClickX, FClickY: integer;

    { The working plane follows the face under the cursor.  Alt cycles the
      three flat planes and latches, for drawing in mid air; Esc or a new
      tool releases it. }
    FPlaneHeld: boolean;
    { Alt's three stops on the line tool, and the edge parallel and
      perpendicular are measured from: the last segment, or the start edge. }
    FInferMode: TInferMode;
    FParHas: boolean;
    FParDir: TP3;
    { 0 none, 1 parallel, 2 perpendicular - what the cursor is on now }
    FParPerp: integer;
    { The arc's tangent lock: the edge its first point is on, and whether Alt
      has pinned the bulge to leave that edge smoothly, as in SketchUp. }
    FArcTanHas, FArcTanLock: boolean;
    FArcTanDir: TP3;
    { the offset's Alt: keep the overlaps a tight corner makes (SketchUp's;
      off unless asked for) }
    FOffsetRaw: boolean;
    { the protractor's Alt: stop taking the plane from the face under the
      cursor }
    FRotFree: boolean;
    { the face the shape is being drawn on, so a point can be held to it }
    FFacePt, FFaceNm: TP3;
    { true while a push is lining itself up with another face }
    FPushFlush: boolean;
    { waiting for a click to say which piece to lay out }
    FUnfoldPick: boolean;
    { which side of the cursor the chip sits on, kept so it does not swap
      sides each time the mouse twitches }
    FTipCorner: integer;
    { the dotted lines the cursor is on this frame, in screen pixels as point
      pairs; the chip keeps off them (see TipSpot) }
    FTipLines: array of TRect;
    { what the precision list is showing as chosen }
    FLenDenom: integer;
    { The report screenshot: FShotCount is the countdown drawn on the canvas,
      FShotFlash whites the screen as it is taken, FShotBusy stops a second
      capture starting during the countdown (the program stays usable). }
    FShotCount: integer;
    FShotFlash: boolean;
    FShotBusy: boolean;
    { the note being dragged by its box }
    FNoteDrag: integer;
    { whether the note being carried has actually gone anywhere yet }
    FNoteMoved: boolean;
    FNoteFrom, FNoteGrab: TP3;
    { the point the cursor is holding on to, and whether it has one }
    FStickOn: boolean;
    FStickPt: TP3;
    FStickKind: TSnapKind;
    { recent crash count and when the last one was }
    FWoundCount: integer;
    FWoundAt: QWord;
    { where the window was, taken while it still existed }
    FWinSaved, FWinMax: boolean;
    FWinL, FWinT, FWinW, FWinH: integer;
    { True when the start point is on a face, so that face sets the plane
      and dragging must not overrule it.  In mid air the drag decides. }
    FPlaneFromFace: boolean;
    { Autosave: every change bumps FEditSeq; a few seconds later the tick
      writes all sheets to a draft beside the settings, and the next launch
      restores it.  FDraftSeq is what was last written, FDraftAge counts ticks
      since the last change. }
    FEditSeq, FDraftSeq: int64;
    { the edit the named file was last written at; anything later is unsaved }
    { unique per run, so two copies cannot write the same temp file }
    FRunTag: string;
    FDraftAge: integer;
    FRestored: boolean;
    { closing because an update is taking over - nothing is asked }
    FHandingOver: boolean;
    { Hold the button still and the rubber band strains, bows and cracks;
      when it breaks the run is released and no point is placed.  FHoldOn is
      a press not yet decided, FHoldT how long it has been held, FSnapT the
      recoil afterwards. }
    FHoldOn: boolean;
    FHoldT, FSnapT: single;
    { a line snapping throws its two ends apart; a shape only bursts }
    FSnapEnds: boolean;
    FHoldX, FHoldY: integer;
    { Pointer speed in pixels a second, smoothed.  Alignment nudges wait for
      the hand to slow down; otherwise a cursor swept across a cube catches
      every corner it passes and hunts sideways. }
    FMoveSpeed: double;
    FLastMoveTick: QWord;
    FLastMoveX, FLastMoveY: integer;
    FSnapA, FSnapB, FSnapM: TPointF;
    { After a run snaps off, the cursor still sits on the point it was joined
      to.  Do not take it up as a reference again until the hand moves. }
    FNoLockUntilMoved: boolean;
    FWasLine: boolean;
    { latched when drawing the document threw, so it is not retried every frame }
    FRenderBroken: boolean;
    { uptime, and whether startup has been declared good }
    FUpTime: single;
    FStartupDone, FAskedAboutCrash: boolean;
    { an exception was written up and we are still running: offer to send it
      on the next tick }
    FCrashToOffer: boolean;
    FUpdatedFrom: string;
    FWhatsNewShown: boolean;
    FPostcardOffered: boolean;
    FTextPick: boolean;           { the sheet is taking points for the source window }
    { the stair dialog picking points on the sheet: which is next (1 to 3,
      or 0), the points, the dialog state to reopen with, and the stair group
      being changed or 0 }
    FStairPick: integer;
    FStairPts: array[0..2] of TP3;
    FStairJob: TStairJob;
    FStairEdit: integer;
    FSourceComplete: boolean;     { the source window's list of words opens by itself }
    { The last few dozen things that happened, for crash reports.  A ring, so
      it never grows. }
    FTrail: array[0..63] of string;
    { The same session for replay: load the report's drawing, run these, and
      the fault happens again.  Recorded from our own handlers, so nothing
      outside the window is seen.  World coordinates, not pixels, so it
      replays on any screen size. }
    FActs: array[0..511] of string;
    FActsN: integer;
    FTrailN: integer;
    { The newer version available, if any.  Kept, because a status line gets
      overwritten and never seen again. }
    FUpdateTag: string;
    { Shaking the mouse: direction reversals per screen axis and when they
      happened, so a shake decays if you stop. }
    FShX, FShY: integer;
    FShDirX, FShDirY, FShNX, FShNY: integer;
    FShTX, FShTY: QWord;
    { the dimension whose figure is being typed over, or -1; while set, the
      command bar edits that label }
    FDimEdit: integer;
    { where the right button went down, so a click can be told from a pan }
    FRightSX, FRightSY: integer;
    FPushSX, FPushSY: integer;   // where the drag started, on screen
    FPanRefX, FPanRefY: integer;
    { What the orbit turns about: the thing under the cursor, as in SketchUp.
      Turning about the origin sends what you were looking at off screen. }
    FOrbitPivot: TP3;
    { where the pivot sat on screen when the drag began; the orbit holds it
      there, not under the cursor (see ServiceMotion) }
    FOrbitAnchor: TPointF;
    FOrbitAnchored: boolean;
    FMouseSX, FMouseSY: integer;   // raw pointer, before snapping

    { Motion is only recorded here; the work happens once per tick from the
      newest position.  Painting in the handler is slow on a virtual display,
      and GDK holds motion events until the handler returns. }
    FMoveX, FMoveY: integer;
    FMoveShift: TShiftState;
    { a built part being placed moves whole, on its own; nothing stretches }
    FMoveRigid: boolean;
    { Follow Me: the face being spun, and the first point of its axis }
    FFollowFace: integer;
    FAxisA: TP3;
    { what a dialog reported from inside itself, for the report body }
    FReportExtra: string;
    FTimings: boolean;
    { what /timings has seen since it was turned on; there is no console on
      Windows, so it is kept to be shown }
    FTimingLog: array of string;
    { The camera is moving (orbit, pan, or a recent wheel zoom), so frames are
      drawn quick and one full frame is drawn when it stops.  FQuickFrames
      turns this off. }
    FCameraMoving: boolean;
    FQuickFrames: boolean;
    { faces at half resolution while the camera moves; switched on by a slow
      moving frame, off when the camera settles.  See RenderInk and
      TWorkDoc.Render. }
    FMoveHalf: boolean;
    { Long work on the main thread: what and how far, shown on the command
      bar, and input handlers stand down until it ends.  FBusyAt is the last
      report; the tick clears a stale flag. }
    FBusy: boolean;
    FBusyMsg: string;
    FBusyFrac: double;
    FBusyAt, FBusyPaintMs: QWord;
    { a bulk select marks FSel here once, instead of IsSelected walking the
      whole selection for every entity }
    FSelBulk: array of boolean;
    FSelBulkOn: boolean;
    { outlines of a large selection drawn once into a layer and composited
      each paint, instead of redrawing thousands of lines on every mouse move }
    FSelLayer, FSelShot: TArtSurface;
    FSelLayerKey: string;
    { touch, from hsTouch's hook: the fingers and what they are doing }
    FTouches: array of TTouchPt;
    FTouchMode: TTouchMode;
    FTouchDown: boolean;
    FTouchOn: boolean;
    FTouchCount: integer;
    FGestMidX, FGestMidY, FGestDist: double;
    { a document was being read and the splash screen's skip was pressed }
    FLoading, FLoadSkipped: boolean;
    { worker threads for the caches (docs/render-acceleration.md); /threads }
    FThreads: boolean;
    FStartedAt: QWord;
    FLastWheel: QWord;
    { the dimension the move tool holds by its line: only the offset changes,
      never what it measures }
    FDimMove: integer;
    { the circle or arc being dimensioned (diameter or radius), or -1; and the
      last direction, for DimOffsetAt to keep }
    FDimArc: integer;
    FDimPrefer: TP3;
    { The copy just made, so 3x or /3 typed next makes an array.  Made is
      every copied entity, all at the end of the list so they can be taken
      back and remade at a new count.  Live until any other action. }
    FArray: record
      Live, Rotate: boolean;
      Src: array of integer;
      Made: TIntArrayW;
      D, C, Axis: TP3;
      Ang: double;
      end;
    { Rotate and the protractor.  FP1 is the center; the axis is an arrow
      key's axis, else the face under the cursor, else blue.  The second
      click is the reference arm. }
    FRotAxis: TP3;
    FRotAxisIx: integer;
    FRotRef: TP3;
    { sides for the next circle and arc: SketchUp's defaults, changed with
      + and - or by typing 24s }
    FSidesCircle, FSidesArc: integer;
    FMovePending: boolean;
    FScreenDirty: boolean;
    { the camera moved and the picture is not redrawn yet (see ViewMoved) }
    FViewDirty: boolean;
    { the face whose blue wash is already in the shown picture, so the
      overlay does not paint it again (see pbScreenPaint) }
    FHintInShot: integer;
    { What is on screen: the picture, the selection and the face wash.  They
      only change when something says so; rebuilding every paint cost a
      full-window composite and copy each time. }
    FShotOK: boolean;
    FShotHadSel: boolean;
    { the paper's fill, made once per theme and size - see RepaintPaper }
    FPaperBase: TArtSurface;
    FPaperBaseKey: string;

    { The view cube.  Off by default: a first drawing is a rectangle in plan
      and does not need it. }
    FCubeOn: boolean;
    FSourceWasOpen: boolean;      { the source window was open when the program was last shut }
    FSourceOnTop: boolean;
    FSourceBounds: TRect;         { Left, Top, and Width and Height in Right and Bottom }
    { its corner: 0 top left, 1 top right, 2 bottom left, 3 bottom right }
    FCubeCorner: integer;
    { whether a click centers and fits the selection.  With nothing picked it
      never refits, since refitting on every view change loses the user's zoom. }
    FCubeFitSel: boolean;
    FCubeSkin: TArtSurface;
    FCubeHot: TCubeTarget;
    FCubeHasHot: boolean;
    { the view an orbit would snap to if released now (see OrbitSnapTarget) }
    FSnapHot: TCubeTarget;
    FSnapHasHot: boolean;
    FCubeDrag: boolean;
    FCubeDragX, FCubeDragY: integer;
    FCubePressX, FCubePressY: integer;
    FCubeMoved: boolean;
    FCubeCursor: boolean;
    FCursorWasCube: TCursor;
    { Progress of a camera move, 0 when still.  Cube clicks animate so you
      can see which way the model turned. }
    FGlideT: double;
    FGlideAz0, FGlideEl0, FGlideAz1, FGlideEl1: double;
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
    FTurnAnchored: boolean;
    { and the framing, when the move changes it too }
    FGlideFrame: boolean;
    FGlideZ0, FGlideZ1, FGlideOX0, FGlideOX1, FGlideOY0, FGlideOY1: double;
    FHotSlice: integer;         // which zone of the cut strip is under the pointer
    FTools: array of TDeckItem; // the vertical tool strip down the left
    FToolSkin: TArtSurface;
    FInfoSkin: TArtSurface;
    FHotTool: integer;
    { The strip item under the pointer, so its tip is drawn beside it.
      FChromeTip is the title, FChromeTipBody the sentence, FChromeTipY the
      button's middle. }
    FChromeTip, FChromeTipBody: string;
    FChromeTipY, FChromeTipX: integer;
    { the divider positions on the tool strip, and where the shop door sits }
    FToolRules: array of integer;
    FShopTop: integer;
    FQuick: array of TDeckItem;   // the menu bar across the title
    FQuickSkin: TArtSurface;
    FHotQuick: integer;
    FBarMenu: integer;          { the bar menu that is open, or -1 }
    FBarSwitch: integer;        { the word to go on to when it closes }
    { Names beside the icons, or icons alone.  Saved in settings; starts True
      on purpose (see pbToolsPaint). }
    FToolsWide: boolean;
    FSliceSkin: TArtSurface;
    FSliceEdit: integer;        // 0 none, 1 typing the bottom, 2 the top
    FGlyph: TArtSurface;    // the tool badge beside the cursor
    FHoverEnt: integer;          // what the eraser is about to delete
    { The one edge the dimension tool would take, as its two ends.  An index
      is not enough: it may be a side of a face outline, which has no A and B. }
    FHoverEdgeOK: boolean;
    FHoverEdgeA, FHoverEdgeB: TP3;
    { documents: the next key, the untitled count, recent files, and whether
      closing because every question was answered (see FormCloseQuery) }
    FNextDocKey: integer;
    FUntitled: integer;
    FRecent: TStringList;
    FCleanExit: boolean;
    { a draft from a run that did not close properly, offered once the window
      is up (see RestoreDraft) }
    FRecoverToOffer: boolean;
    { when to next look for a second copy's open-request notes }
    FReqPollAt: QWord;
    { mend the file associations at start-up (SETTINGS > File Associations) }
    FAssocRepair: boolean;
    FGuide: boolean;             // an alignment guide is active
    FGuideFrom: TP3;

    { A 90 degree relation to a chosen point beats other nearby snaps.
      FAxisFrom is that point (the line's start, or one picked up by resting
      on it); FAxisLock is the free axis: 0 X, 1 Y, 2 Z. }
    FAxisLock: integer;
    FSnapFromPt: boolean;     { the distance along the axis came from a corner, not the grid }
    FAxisFrom: TP3;

    { which standard view we are parked on, or -1 after a free orbit }
    FViewPreset: integer;

    { rest the cursor on a point and it is kept as a reference }
    FLockOn: boolean;
    FLockPt: TP3;
    FDwellSX, FDwellSY: integer;
    FDwellSince: QWord;

    { --- the lists drawn on the canvas ----------------------------------- }
    { The open list, drawn on the canvas so it needs no extra
      control and cannot fall behind anything. }
    FPopup: integer;
    FPopupR: TRect;
    FPopupN: integer;
    FPopupHot: integer;
    { the first row showing; only the command list is long enough to scroll }
    FPopupTop: integer;
    { commands used lately, most recent first, comma separated; saved so the
      list keeps their order }
    FCmdRecent: string;
    FCmdWant: string;           { what the list is filtered by, after the slash }
    { the order the rows are in: recents, then the rest alphabetical }
    FCmdOrder: array of integer;
    { where the arrow beside the prompt is, for hit testing }
    FCmdArrow: TRect;
    FCmdArrowHot: boolean;
    FCursorWas: TCursor;

    { --- erase animation ------------------------------------------------ }
    FErasing: boolean;
    FEraseT: single;
    FJitterX, FJitterY: integer;

    { helpers }
    function Theme: TTheme;
    function Ppu: double;
    function CurScale: TDrawScale;
    function SnapStep: double;
    function Proj: TProjector;
    function ScreenOf(const P: TP3): TPointF;
    function WorldAt(SX, SY: double): TP3;
    function SnapToGrid(const P: TP3): TP3;
    function ResolveSnapRaw(SX, SY: double): TP3;
    function ResolveSnapAt(SX, SY: double): TP3;
    function HeldToFace(const P: TP3): TP3;
    function AnnotColor: TPix;

    procedure Relayout;
    function TitleHeight: integer;
    function CursorOnPlane(const N, P0: TP3): TP3;
    function OffsetDistance: double;
    function OffsetPreview: TP3Array;
    procedure CommitOffset;
    procedure EditDimUnder(X, Y: integer);
    procedure RightClickAt(X, Y: integer);
    procedure FillCanvasMenu;
    { the measure tool's right-click: erase the guide under the cursor (see
      RightClickAt) }
    procedure GuideMenuAt(X, Y: integer);
    procedure CanvasMenuClick(Sender: TObject);
    procedure CenterSelection;
    function ReverseSelectedFaces: integer;
    { the material on a face, or on every picked face when the shown one is
      among them }
    function PaintSelectedFaces(Shown: integer; C: TColor; Painting: boolean): integer;
    { the pen color of every picked line, arc, note and dimension }
    function InkSelectedThings(C: TColor): integer;
    function SelectedDim: integer;
    function SelectedLine: integer;
    function ApplyLineLength(NewLen: double): boolean;
    procedure ApplySlice;
    procedure SetSlice(AOn: boolean; ALo, AHi: double; const Why: string = '');
    procedure NudgeSlice(Steps: integer; Which: integer);
    procedure PlanFromFace(Face: integer);
    function SliceText: string;
    function ApplyDimResize(NewLen: double; MoveB: boolean): boolean;
    procedure CommitDimNote;
    function ChromeMargin: integer;
    procedure RebuildShell;
    procedure RefreshChrome;
    procedure NoteFrame(PaintMs: QWord);
    procedure ResizeSurfaces(AW, AH: integer);
    function PaperSig: TPaperSig;
    procedure RepaintPaper;
    procedure PaintGroundGrid(Pitch: double);
    procedure PaintAxes;
    procedure PaintPushPreview(C: TCanvas);
    procedure PaintFaceHint(C: TCanvas; Face: integer; const Col: TPix; S: TArtSurface = nil; OX: integer = 0; OY: integer = 0;
      Edge: boolean = True; Every: integer = 2);
    function HintFaceNow: integer;
    { the face a press is on (see the body) }
    function FaceAtPress: integer;
    procedure CheckForUpdate(Loud: boolean);
    procedure DoUpdate;
    procedure ShowWhatsNew;
    procedure BuildTransitionWizard;
    procedure BuildSpoolWizard;
    { Again: a radiant job group in the drawing to reopen in the wizard;
      Build replaces it }
    procedure BuildRadiantWizard(Again: integer = 0);
    { the radiant zone this group is or is inside (0 for none), with its job }
    function RadiantGroupOf(G: integer; out JobId: string): integer;
    { every group of that job in the drawing, and the job read from them }
    function RadiantJobGroups(const JobId: string; out Job: TRadiantJob): TIntArrayW;
    procedure PrintSubmittalAgain(G: integer);
    { the stringer sheet of the stairs group G, from what it remembers }
    procedure StringerSheetOf(G: integer);
    procedure BuildStairWizard;
    procedure StairDialog;
    procedure StairTakePoint(const P: TP3);
    { the flight from the points so far and the cursor, and the marker
      saying what the next click is }
    function StairPickFrame(const Third: TP3; out F: TStairFrame; out Why: string): boolean;
    procedure PaintStairPick(C: TCanvas; SX, SY: integer);
    { a length typed while picking stairs: the run after the top, the width
      after the bottom }
    procedure StairTyped;
    procedure StairResume(Data: PtrInt);
    procedure StairRebuild(G: integer; const F: TStairFrame; const S: TStairSpec; Use: TStairUse);
    function StairWhereNow(G: integer; const F: TStairFrame; const S: TStairSpec): TP3;
    function ArcNormal(I: integer): TP3;
    procedure DoRevolve(const AxisP, AxisDir: TP3; PathArc: integer = -1);
    function IsProfileEdge(I: integer): boolean;
    function AxisSplitsProfile(const AxisP, AxisDir: TP3; out RLo, RHi: double): boolean;
    procedure PaintRevolvePreview(C: TCanvas);
    { the chain of edges joined end to end through edge I, and whether it
      closes }
    function ChainFrom(I: integer; out Closed: boolean): TP3Array;
    procedure DoSweep(const Path: TP3Array; Closed: boolean);
    { /rendertime: how long a frame takes, for chasing sluggish orbits }
    procedure RenderTiming;
    procedure Took(const What: string; T0: QWord);
    procedure ApplyArray(N: integer; Divide: boolean);
    function ArrayCommand(const S: string; out N: integer; out Divide: boolean): boolean;
    procedure CopySelection(Cut: boolean);
    procedure PasteClip;
    { hand something just built to the move tool, so the next click places it }
    procedure PlaceBuilt(First: integer; const Ref: TP3);
    procedure StartUnfold;
    procedure UnfoldAt(SX, SY: integer);
    procedure OfferCrashReport(JustNow: boolean);
    function DocThings(const DocFile: string): integer;
    procedure Quiesce;
    function WindowShot(out B: TBitmap): boolean;
    procedure DrawPointerOn(B: TBitmap; ScreenCoords: boolean; const Org: TPoint);
    function CaptureShot(Wait: boolean; out Bmp: TBitmap): boolean;
    procedure ShotCountdown(Seconds: integer);
    procedure PaintShotOverlay(C: TCanvas);
    function ReportBug(const Preamble: string = ''; const ShotFile: string = ''; const DocFile: string = ''): boolean;
    { note something worth knowing if this run ends badly }
    procedure Trail(const S: string);
    procedure Act(const S: string);
    function ActsText: string;
    function ReplayActs(const Script: string): integer;
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
    procedure ShakeWatch(X, Y: integer);
    function StrainOutline(out Pts: TPointFArray): boolean;
    procedure PaintStrainPath(C: TCanvas; const Pts: TPointFArray; T: single);
    procedure PaintStrainSeg(C: TCanvas; const A, B: TPointF; T: single; Outward: boolean; CX, CY: double);
    procedure PaintStrainMark(C: TCanvas; CX, CY: double; T: single);
    procedure PaintSnapRecoil(C: TCanvas);
    procedure PaintFacePoints(C: TCanvas; Face: integer);
    procedure PaintSnapMarker(C: TCanvas; SX, SY: integer);
    procedure PaintDimPreview(C: TCanvas);
    procedure PaintDimEnds(C: TCanvas; const A, B: TP3);
    procedure PaintDimTag(C: TCanvas; X, Y: double; const S: string);
    function PushDistance: double;
    procedure RecomposeAll;
    procedure FreshScreen;
    procedure RenderInk;
    procedure InvalidateStatus;
    procedure ServiceMotion;
    procedure ServiceHover;
    function DimRadialAt(out A, B: TP3; out Note: string): boolean;
    function CurveThrough(const P: TP3): integer;
    function DimOffset3: TP3;
    procedure LayGuide;
    function TapeDropSays: string;
    { Every drawn edge as a plain segment for the region engine.  Guides,
      dimensions and notes are not geometry; solids' faces are their own
      boundary and are not derived. }
    function EdgeSegments(Part: integer): TSegArray;
    function CacheFor(Part: integer): integer;
    function AllPartIds: TIntArrayW;
    procedure ReportRegions;
    { Keeps the drawn faces right; everything that changes an edge ends with
      this. }
    procedure SeedRegions;
    function RebuildFlatFaces: integer;
    function FaceCount: integer;
    function AnyFace: boolean;
    function SolidFaceCount: integer;
    procedure DoomAt(SX, SY: integer);
    function PickAt(SX, SY: integer): integer;
    function PickForMenu(SX, SY: integer): integer;
    function IsSelected(I: integer): boolean;
    procedure LeaveSheet;
    procedure OnTouch(Kind: TTouchKind; Seq: Pointer; SX, SY: double);
    procedure TouchTick;
    procedure TouchSendDown;
    procedure GestureStart;
    procedure GestureMove;
    procedure PruneSelection;
    procedure BeginBulkSelect;
    procedure EndBulkSelect;
    procedure EnsureSelLayer;
    procedure SelectOnly(I: integer);
    procedure SelectToggle(I: integer);
    procedure SelectAdd(I: integer);
    procedure SelectRemove(I: integer);
    procedure SelectNone;
    procedure FinishSelect(X, Y: integer; Shift: TShiftState);
    function EntHasPoint(I: integer; const P: TP3): boolean;
    procedure SelectAttached(I: integer);
    { --- groups --- }
    procedure SelectAddOne(I: integer);
    procedure SelectRemoveOne(I: integer);
    function PickAtRaw(SX, SY: integer): integer;
    function PickToGrab(SX, SY: integer): integer;
    function SelectedGroups: TIntArrayW;
    function SoleGroup: integer;
    procedure MakeGroup;
    procedure ExplodeGroups;
    procedure OpenGroup(Id: integer);
    procedure CloseGroup;
    procedure LockGroups(Locked: boolean);
    procedure HideGroups(PutAway: boolean; const Named: string);
    procedure RenameGroup(const NewName: string);
    function SplitMoveSelection: boolean;
    function InContextFace(F: integer): integer;
    procedure PaintPartBox(C: TCanvas; Id: integer; const Col: TPix; Dashed: boolean; const Shift: TP3);
    function PromptForTool: string;
    procedure SelectConnected(I: integer);
    procedure SelectInBox(X0, Y0, X1, Y1: integer; Crossing: boolean; Mode: TSelMode);
    procedure MergeSel(const Before: array of integer; Mode: TSelMode);
    procedure DeleteSelection;
    function MoveDelta: TP3;
    function RunReading(const A, B: TP3): string;
    procedure PaintMoveGhost(C: TCanvas);
    procedure PaintRotateGhost(C: TCanvas);
    { The arc from FP1 and FP2 (the chord) and B pulling its middle out.  The
      plane is the working plane unless B is off it; then the three points
      make their own, so an arc drawn up the end of a box stands on it. }
    function ArcPicks(const B: TP3; out Pl: TPlane; out C: TP3; out R, A0, Sweep, Bulge: double): boolean;
    function RotAngle: double;
    function RotRefDir: TP3;
    function IsDoomed(I: integer): boolean;
    procedure BurnDoomed;
    { 0 erases, 1 softens, 2 unsoftens, from the modifiers held }
    function EraseModeOf(Shift: TShiftState): integer;
    { the gathered edges softened or unsoftened instead of deleted }
    procedure SoftenDoomed(On_: boolean);
    function PopupMaxHeight(Which: integer): integer;
    procedure OpenPopup(Which: integer);
    procedure ClosePopup;
    function PopupCount(Which: integer): integer;
    function PopupCaption(Which, I: integer): string;
    procedure PopupChoose(Which, I: integer);
    function PopupItemAt(SX, SY: integer): integer;
    function ScrollPopup(Lines, SX, SY: integer): boolean;
    procedure PaintPopup(C: TCanvas; DX: integer = 0; DY: integer = 0);
    procedure PaintToolGlyph(C: TCanvas; AX, AY: integer);
    function PivotAt(SX, SY: integer): TP3;
    procedure FaceTheCamera;
    function OrbitGainAt(SX, SY: integer): double;
    procedure AnchorOrbit(SX, SY: integer);
    function RectTarget: TP3;
    procedure ReportCrash(Sender: TObject; E: Exception);
    function GuideColor: TPix;

    procedure UIFont(C: TCanvas; Size: integer; Bold: boolean; const Col: TPix; Mono: boolean = False);
    { draws S letter by letter with Tracking pixels between; returns the width }
    function TrackedText(C: TCanvas; X, Y: integer; const S: string; Tracking: integer): integer;

    { history }
    procedure PushUndo;
    procedure DoUndo;
    procedure DoRedo;
    function CanUndo: boolean;
    function CanRedo: boolean;

    { tools and the command bar }
    function ToolName(T: TTool): string;
    function SnapSays: string;
    function SnapMarkPix: TPix;
    function CmdPalette: TCmdPalette;
    function LightChrome: boolean;
    function FieldPix: TPix;
    function FieldEdgePix: TPix;
    procedure CmdRows(out Pad, Row1, Row: integer);
    function CmdBarHeight: integer;
    procedure PlaceCmdMsg;
    procedure PaintCmdMsg(C: TCanvas; const P: TCmdPalette);
    procedure CmdMenuClick(Sender: TObject);
    function DrawCmdRuns(C: TCanvas; X, Y, H, MaxX, Size: integer; Mono: boolean; const M: string; Measure: boolean = False): integer;
    function ModifierTip: string;
    function ShortKeys: string;
    { the size being pulled, worded as it would be typed, or '' }
    function LiveMeasure: string;
    { a working plane's color is the axis its normal points along, as
      SketchUp names planes: red, green, blue }
    function PlanePix(Pl: TPlane): TPix;
    function AxisAlong(const A, B: TP3): integer;
    function IsoRunAxis(const From: TP3; out Along: double): integer;
    function PreviewTarget: TP3;
    procedure SetTool(T: TTool);
    function PlaneName: string;
    procedure PlaneByArrow(Key: word);
    procedure ResetTool;
    procedure ToolClick;
    function WhyNotAMeasurement(const S: string): string;
    procedure ToolCommit;
    procedure CommandEnter;
    function RunCommand(const S: string): boolean;
    procedure JumpSnap(DX, DY: integer);
    function SnapLabel: string;
    function InkUnder(const R: TRect): integer;
    function TipSpot(SX, SY, BoxW, BoxH: integer): TRect;
    procedure TipAvoid(X0, Y0, X1, Y1: integer);
    function TipOnLine(const R: TRect): integer;
    procedure SetOriginHere;
    function CameraShowsSomething: boolean;
    procedure ZoomAt(Factor: double; AnchorSX, AnchorSY: double);
    procedure SetScaleIdx(I: integer);
    procedure PanBy(DX, DY: double);
    procedure ViewMoved;
    procedure FlushView;
    { Travel is False when there is nothing to keep your bearings by: a
      drawing just loaded, a different sheet, a projection change. }
    procedure FitView(Travel: boolean = True);
    { a new sheet: Key < 0 for a new untitled one-sheet file, else a sheet
      added to document Key }
    procedure NewDrawing(Key: integer = -1);
    { the file in front, '' before it is saved }
    function DocPath: string;
    { the tabs of document Key, in order }
    function DocSheets(Key: integer): TIntArrayW;
    { work in document Key that is not saved }
    function DocDirty(Key: integer): boolean;
    { tab I's caption: the file, the sheet when there are several, and a
      star when unsaved }
    function TabCaption(I: integer): string;
    { Save, Don't save or Cancel about document Key; True when it may go }
    function AskToSave(Key: integer; const Title: string): boolean;
    function CloseDocument(Key: integer): boolean;
    { document Key to its file, asking for a name when it has none or when
      AskName; True when written }
    function SaveDocument(Key: integer; AskName: boolean): boolean;
    procedure DoSaveAll;
    { a file opened as a document of its own, in tabs after the others }
    function OpenFile(const FileName: string): boolean;
    procedure CheckOpenRequests;
    procedure DropStaleOpenRequests;
    { a file's sheets added after the existing tabs (see the body) }
    function ReadSheets(const FileName: string; Session: boolean; out First: integer): boolean;
    { show tab First, framed when its file did not store a camera }
    procedure ShowLoaded(First: integer);
    procedure RememberRecent(const Path: string);
    { the File menu, under the MENU button }
    procedure ShowFileMenu;
    procedure FileMenuClick(Sender: TObject);
    procedure RecentClick(Sender: TObject);
    procedure AddSheetHere;
    procedure DeleteSheetHere;
    procedure OfferRecovery;
    procedure DropDraft;
    procedure CloseDrawing(I: integer);
    procedure SelectDrawing(I: integer);
    procedure LayoutTabs;
    procedure PlaceTabs;

    { commands }
    procedure StartErase;
    procedure StepErase(Dt: single);
    procedure DoSave;
    procedure DoSaveAs;
    procedure DoOpen;
    procedure DoExport;
    procedure DoPrint;
    { every sheet of the drawing, a page each, rather than only this one }
    procedure DoPrintSheets(All: boolean);
    procedure DoPrintFull(const PngDir: string);
    procedure PrintTileMarks(Col, Row, Cols, Rows, PitchW, PitchH, SW, SH: integer; const ScaleName: string);
    procedure CycleTheme(Step: integer);
    procedure ApplyTheme;
    procedure SetLenPrecision(D: integer);
    procedure SetEdgeWidth(V: integer);
    procedure SetInk(C: TColor; Auto: boolean = False);
    procedure SetUnits(U: TUnitSystem);
    procedure SetView(V: TViewKind);
    procedure ApplyViewPreset(I: integer);
    procedure EnterFreeCamera(AtCorner: boolean = False);
    procedure CycleViewPreset(Step: integer);

    { is the cursor on something a dimension may be anchored to? }
    function DimAnchored: boolean;
    function ZoomReading: string;
    function StatusLine: string;
    procedure WashFace(C: TCanvas; Face: integer; const Col: TPix);
    procedure TraceOutlineVisible(C: TCanvas; Idx: integer; const Col: TPix; PenW: integer);
    procedure TraceOutlineInto(S: TArtSurface; Idx: integer; const Col: TPix; PenW: single);
    procedure TraceOutline(C: TCanvas; const Hi: TPointFArray; const Col: TPix);
    procedure PaintOverlay(C: TCanvas);
    function TangentBulge(Pl: TPlane; out Bulge: double): boolean;
    procedure PaintGuideHover(C: TCanvas; I: integer);
    { the cube: where it sits, what it draws, and the glide it starts }
    function CubeRect: TRect;
    function OverCube(X, Y: integer): boolean;
    function CubeZone(X, Y: integer): boolean;
    procedure PaintViewCube(C: TCanvas);
    procedure PaintCompass(C: TCanvas);
    function CubeMouse(X, Y: integer; Down, Up: boolean): boolean;
    function TurnPivot: TP3;
    function FitTarget(OnSelection: boolean; AzT, ElT: double; out NewZoom, NewOX, NewOY: double): boolean;
    procedure GlideCamera(Az, El, Zoom, OX, OY: double);
    procedure HoldTurn;
    procedure GlideTo(Az, El: double);
    function OrbitSnapTarget(out T: TCubeTarget): boolean;
    function ArcFillet(out F: TFillet; out Typed: boolean): boolean;
    function FilletCandidate(out F: TFillet): boolean;
    function ArcDoubleClick(SX, SY: integer): boolean;
    procedure PaintUnderCursor(S: TArtSurface; OX, OY: integer);
    procedure SnapOrbitToNearest;
    procedure StepCubeView(Key: word);
    procedure StepGlide(Dt: double);
    procedure PaintHeldPlane(C: TCanvas);

    { Session True: every sheet plus the comments a draft or handoff needs
      (document, file, saved or not).  Otherwise only document Key's sheets
      (all when Key < 0), as the file is written. }
    procedure BuildSession(L: TStrings; Session: boolean = False; Key: integer = -1; Quick: boolean = False; ShownFirst: boolean = False);
    procedure SaveDraft;
    function OnProgress(const What: string; Frac: double): boolean;
    function MachineText: string;
    procedure KeepReportCopy(const AName, Body: string; Shot: TStream);
    function LoadedWords: string;
    procedure EndBusy;
    function RestoreDraft: boolean;
    procedure WriteHandoff;
    function RestoreHandoff: boolean;
    function LoadExample: boolean;
    procedure WriteExamples;
    procedure WriteJigs;
    procedure LoadSettings;
    procedure ApplyCommandLine;
    procedure FollowScreenSize;
    procedure SaveSettings;
    procedure ShowAbout;
    { file associations: the FileAss component, SETTINGS > File Associations }
    function AssocSuffix: string;
    procedure TellAssocTrouble(const R: TFileAssResult);
    procedure AssociationsPick(What: integer);
    procedure RepairAssociations;
    procedure PrepareDocIcons;
    procedure ShowFacts(const Title, AText: string);
    procedure ShowLongText(const Title, AText: string);
  end;

var
  MainForm: TMainForm;

implementation

uses
  {$IFDEF LCLGTK3} LazGtk3, gtk3widgets, {$ENDIF}
  FileUtil, Clipbrd, LazUTF8, hsHelpDocs, hsHelpView, hsReportDialog, hsLongText, hsAbout,
  hsFacts, hsText, hsImpliedFaces;

  {$R *.lfm}

{ S cut to fit Room pixels and ended with '...'.  Cuts whole characters,
  never a byte of one, so a name with accents does not end in a broken
  letter. }
function CutToFit(C: TCanvas; const S: string; Room: integer): string;
var
  N: integer;
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

  { tool strip groups: a tool button, or a button that opens a list }
  GRP_TOOL = 7;
  GRP_POPUP = 8;

  { The lists drawn on the canvas.  The settings that used to open lists from
    the deck live on the SETTINGS menu now; these are what is left. }
  POP_NONE = -1;
  { The shop tools: making the thing rather than drawing it (unfold, the
    fitting builders). }
  POP_SHOP = 5;
  { the rest of the tools, behind one door; see MAIN_TOOLS }
  POP_MORE = 7;
  { Every typed command with a word about each: the arrow beside the prompt.
    The only list too long to fit, so it scrolls. }
  POP_CMDS = 8;

type
  { a typed command, as the list shows it }
  TCmdItem = record
    Name: string;      { what to type, without the slash }
    Hint: string;      { what it does, in a few words }
    Arg: boolean;      { True when it wants something after it }
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
  CMD_LIST: array[0..90] of TCmdItem = (
    (Name: 'all'; Hint: 'select everything on this sheet'; Arg: False; Eg: ''; Also: 'selectall'),
    (Name: 'arc'; Hint: 'the arc tool'; Arg: False; Eg: ''; Also: 'a'),
    (Name: 'assistant'; Hint: 'ask about the sheet - not connected yet'; Arg: False; Eg: ''; Also: 'ai chat'),
    (Name: 'back'; Hint: 'look from behind'; Arg: False),
    (Name: 'center'; Hint: 'center it on the floor at 0,0'; Arg: False; Eg: ''; Also: 'middle'),
    (Name: 'circle'; Hint: 'the circle tool'; Arg: False; Eg: ''; Also: 'c'),
    (Name: 'clear'; Hint: 'empty this sheet'; Arg: False),
    (Name: 'close'; Hint: 'close this file - every sheet of it'; Arg: False),
    (Name: 'corner'; Hint: 'look from a corner'; Arg: False),
    (Name: 'cube'; Hint: 'the view cube: on, off, tl/tr/bl/br'; Arg: False;
    Eg: '/cube tr';
    Also: 'viewcube'),
    (Name: 'cut'; Hint: 'the plan slice: two heights, or "all"'; Arg: True;
    Eg: '/cut 0 9''';
    Also: 'slice'),
    (Name: 'detach'; Hint: 'move a line away on its own: on, off'; Arg: False;
    Eg: '/detach on';
    Also: 'loose'),
    (Name: 'dimension'; Hint: 'the dimension tool'; Arg: False; Eg: ''; Also: 'dim'),
    (Name: 'drill'; Hint: 'push a shape right through'; Arg: False; Eg: ''; Also: 'bore punch'),
    (Name: 'edit'; Hint: 'work inside the picked group'; Arg: False; Eg: ''; Also: 'opengroup'),
    (Name: 'erase'; Hint: 'the eraser'; Arg: False; Eg: ''; Also: 'e del'),
    (Name: 'example'; Hint: 'the example drawing, as a new drawing'; Arg: False),
    (Name: 'explode'; Hint: 'take the picked group apart'; Arg: False; Eg: ''; Also: 'ungroup'),
    (Name: 'fit'; Hint: 'zoom until it all shows'; Arg: False; Eg: ''; Also: 'zoom'),
    (Name: 'forget'; Hint: 'forget the areas seen, and work them out again'; Arg: False),
    (Name: 'front'; Hint: 'look from the front'; Arg: False),
    (Name: 'grid'; Hint: 'the ruled paper, on or off'; Arg: False),
    (Name: 'group'; Hint: 'make what is picked a group'; Arg: False; Eg: ''; Also: 'makegroup'),
    (Name: 'groups'; Hint: 'the groups panel: on, off'; Arg: False;
    Eg: '/groups off';
    Also: 'outliner'),
    (Name: 'guides'; Hint: 'clear the guide lines'; Arg: False; Eg: ''; Also: 'noguides'),
    (Name: 'help'; Hint: 'about this program'; Arg: False; Eg: ''; Also: '?'),
    (Name: 'hide'; Hint: 'put away the picked groups, every group so named, or the notes'; Arg: True;
    Eg: '/hide labels';
    Also: 'putaway'),
    (Name: 'holes'; Hint: 'draw where a solid is not closed'; Arg: False; Eg: ''; Also: 'openedges notclosed'),
    (Name: 'info'; Hint: 'the entity panel: on, off'; Arg: False;
    Eg: '/info on';
    Also: 'entity properties'),
    (Name: 'iso'; Hint: 'the isometric view'; Arg: False),
    (Name: 'jig'; Hint: 'run the picked group''s jig again, or every jig'; Arg: False; Eg: ''; Also: 'jigs'),
    (Name: 'keep'; Hint: 'the last tape run, kept as a dimension'; Arg: False; Eg: ''; Also: 'keepdim'),
    (Name: 'leave'; Hint: 'close the open group'; Arg: False; Eg: ''; Also: 'closegroup'),
    (Name: 'left'; Hint: 'look from the left'; Arg: False),
    (Name: 'light'; Hint: 'light that follows the camera: on, off'; Arg: False;
    Eg: '/light off';
    Also: 'lamp'),
    (Name: 'line'; Hint: 'the line tool'; Arg: False; Eg: ''; Also: 'l'),
    (Name: 'lock'; Hint: 'lock the picked group'; Arg: False),
    (Name: 'manual'; Hint: 'open the manual'; Arg: False; Eg: ''; Also: 'docs'),
    (Name: 'measure'; Hint: 'the tape measure'; Arg: False; Eg: ''; Also: 'm tape'),
    (Name: 'move'; Hint: 'the move tool'; Arg: False; Eg: ''; Also: 'mv'),
    (Name: 'name'; Hint: 'call the picked group something'; Arg: True;
    Eg: '/name Left knob';
    Also: 'rename'),
    (Name: 'new'; Hint: 'a new drawing - a file of its own'; Arg: False; Eg: ''; Also: 'tab'),
    (Name: 'offset'; Hint: 'a parallel copy of a face''s edge'; Arg: False; Eg: ''; Also: 'f'),
    (Name: 'orbit'; Hint: 'the free camera'; Arg: False; Eg: ''; Also: 'spin'),
    (Name: 'origin'; Hint: 'put the view back on 0,0,0'; Arg: False; Eg: ''; Also: 'o'),
    (Name: 'plan'; Hint: 'look straight down'; Arg: False; Eg: ''; Also: '2d flat'),
    (Name: 'plane'; Hint: 'the working plane: xy, xz or yz'; Arg: True;
    Eg: '/plane xz'),
    (Name: 'postcard'; Hint: 'the once-only note to the authors, to send or read'; Arg: False; Eg: ''; Also: 'hello'),
    (Name: 'print'; Hint: 'this sheet - or "all", or "full"'; Arg: True;
    Eg: '/print all'),
    (Name: 'protractor'; Hint: 'lay a guide at an angle'; Arg: False; Eg: ''; Also: 'angle'),
    (Name: 'push'; Hint: 'push or pull a face'; Arg: False; Eg: ''; Also: 'pull pushpull p'),
    (Name: 'quick'; Hint: 'quick frames while the camera moves'; Arg: False),
    (Name: 'radiant'; Hint: 'lay radiant tube out over the selected floor'; Arg: False; Eg: ''; Also: 'pex hydronic'),
    (Name: 'rebuild'; Hint: 'work the faces out again'; Arg: False),
    (Name: 'rect'; Hint: 'the rectangle tool'; Arg: False; Eg: ''; Also: 'rectangle r'),
    (Name: 'redo'; Hint: 'put back what was undone'; Arg: False),
    (Name: 'reface'; Hint: 'throw the flat faces away and rebuild'; Arg: False; Eg: ''; Also: 'rebuildfaces'),
    (Name: 'regions'; Hint: 'report the flat areas found'; Arg: False),
    (Name: 'rendertime'; Hint: 'time a whole frame'; Arg: False),
    (Name: 'replay'; Hint: 'play back a session from a report'; Arg: False;
    Eg: '/replay session.txt'),
    (Name: 'report'; Hint: 'send a bug report, with a picture'; Arg: False; Eg: ''; Also: 'bug'),
    (Name: 'resize'; Hint: 'retype a picked dimension'; Arg: True;
    Eg: '/resize 4''6"';
    Also: 'size'),
    (Name: 'reverse'; Hint: 'turn the picked faces over'; Arg: False; Eg: ''; Also: 'rev flip'),
    (Name: 'revolve'; Hint: 'spin or sweep a face into a solid'; Arg: False; Eg: ''; Also: 'followme follow lathe'),
    (Name: 'right'; Hint: 'look from the right'; Arg: False),
    (Name: 'rotate'; Hint: 'the rotate tool'; Arg: False; Eg: ''; Also: 'q turn'),
    (Name: 'save'; Hint: 'save this file'; Arg: False),
    (Name: 'saveall'; Hint: 'save every file with changes'; Arg: False),
    (Name: 'saveas'; Hint: 'save it under a new name'; Arg: False),
    (Name: 'scale'; Hint: 'the print scale: 1/4", 1" and so on'; Arg: True;
    Eg: '/scale 1/4"'),
    (Name: 'select'; Hint: 'the select tool'; Arg: False; Eg: ''; Also: 's'),
    (Name: 'session'; Hint: 'what has happened, most recent last'; Arg: False;
    Eg: '/session session.txt';
    Also: 'acts'),
    (Name: 'sheet'; Hint: 'add a sheet to this file'; Arg: False),
    (Name: 'show'; Hint: 'bring back what was put away - all, or the groups so named'; Arg: True;
    Eg: '/show labels';
    Also: 'unhide'),
    (Name: 'source'; Hint: 'this sheet as its text, picked both ways'; Arg: False;
    Eg: '/source complete off';
    Also: 'src text-view'),
    (Name: 'spool'; Hint: 'the pipe spool scratchpad'; Arg: False; Eg: ''; Also: 'pipe scratchpad'),
    (Name: 'stairs'; Hint: 'a straight stair - on two picked lines, or typed and placed'; Arg: False; Eg: ''; Also: 'stair'),
    (Name: 'state'; Hint: 'what a report says about the program right now'; Arg: False),
    (Name: 'sysinfo'; Hint: 'what a report says about this machine'; Arg: False; Eg: ''; Also: 'machine'),
    (Name: 'text'; Hint: 'a note on the drawing'; Arg: False; Eg: ''; Also: 'note n'),
    (Name: 'threads'; Hint: 'background work, on or off'; Arg: False),
    (Name: 'timings'; Hint: 'time each step: on, then again to see them'; Arg: False;
    Eg: '/timings show'),
    (Name: 'top'; Hint: 'look from above'; Arg: False; Eg: ''; Also: 'down'),
    (Name: 'tozero'; Hint: 'put its near bottom corner on 0,0,0'; Arg: False; Eg: ''; Also: 'zero tuck'),
    (Name: 'transition'; Hint: 'build a duct fitting'; Arg: False; Eg: ''; Also: 'trans fitting elbow tee'),
    (Name: 'undo'; Hint: 'undo the last thing'; Arg: False; Eg: ''; Also: 'u'),
    (Name: 'unfold'; Hint: 'lay a piece out flat'; Arg: False; Eg: ''; Also: 'layout'),
    (Name: 'units'; Hint: 'feet and inches, or millimeters'; Arg: False),
    (Name: 'unlock'; Hint: 'unlock the picked group'; Arg: False),
    (Name: 'update'; Hint: 'look for a newer build'; Arg: False;
    Eg: '/update never';
    Also: 'upgrade'),
    (Name: 'whatsnew'; Hint: 'the release notes'; Arg: False; Eg: ''; Also: 'changes'));

const

  { How finely lengths are written, and what the last field of a dashed entry
    counts in.  Sixteenths are the default. }
  PREC_DENOMS: array[0..6] of integer = (2, 4, 8, 16, 32, 64, 100);

  { pen widths the list offers: a few fixed steps, not a slider }
  PEN_STEPS = 6;
  PEN_SIZES: array[0..PEN_STEPS - 1] of integer = (1, 2, 4, 6, 10, 16);

  { Past this many picked, the selection overlay skips the depth test and
    just outlines the edges; at that size tracing is the cost on every
    orbit frame. }
  SEL_TRACE_MAX = 3000;

  UNDO_LEVELS = 16;
  { where the cube can sit, in the words the command takes }
  CORNER_NAME: array[0..3] of string =
    ('top left', 'top right', 'bottom left', 'bottom right');

  { Zoom limits.  Wide enough for a site plan at one end and a weld bead at
    the other, but bounded so OX + dot * Ppu stays in a range the rasterizer
    and depth mesh can handle. }
  ZOOM_MIN = 0.002;
  ZOOM_MAX = 2000.0;

  TICK_MS = 16;
  { how long a camera move takes: long enough to follow, short enough that
    nobody waits }
  GLIDE_SECONDS = 0.34;
  MIN_PEN = 1;
  MAX_PEN = 40;
  SNAP_PX = 16.0;   // pulling onto a point on the drawing
  INFER_PX = 7.0;    // lining up with one that is somewhere else
  FAST_PX_S = 600.0;  // moving quicker than this, alignments wait
  KEEP_FACTOR = 1.7;    // an alignment taken holds this much further out
  HOLD_PX = 18.0;   // ...or with one you deliberately rested on
  { how long the button is leaned on before the line snaps off, and how long
    the ends recoil }
  HOLD_STRAIN = 0.20;   // before this it is just a click being made
  HOLD_BREAK = 0.70;   // and this long to break; longer feels like waiting
  SNAP_RECOIL = 0.30;
  AXIS_PX = 8.0;    // how near the axis through a reference counts
  { View turn per pixel of drag at the rim; OrbitGainAt makes it a quarter
    of this at the middle. }
  ORBIT_RAD_PX = 0.0045;
  LOCK_PX = 7.5;    // this close and the point is what you meant
  { once taken, a point holds until the cursor is this far off it, so a
    small twitch does not drop the snap }
  STICK_PX = 20.0;
  PIECE_PX = 5.0;    // ...and this close for the middle of a piece
  EDGE_PX = 11.0;   // hovering a line means a point on that line
  { the face under the cursor, tinted the way SketchUp tints one }
  HINT_BLUE: TPix = (B: $F2; G: $B4; R: $76; A: 255);
  AXIS_MIN_PX = 14.0;   // nearer than this an axis lock says nothing
  DWELL_MS = 450;    // rest on a point this long to keep it

type
  TViewPreset = record
    Name: string;
    View: TViewKind;
    Az, El: double;
  end;

const
  ISO_EL = 35.264 * Pi / 180;   // the true isometric tilt
  { the first two presets are the paper modes; the V key cycles from here }
  FIRST_CAMERA_PRESET = 2;

  { The views one key steps through: the four corners first, since that is
    what you draw from, then elevations and top for reading dimensions. }
  VIEW_PRESETS: array[0..10] of TViewPreset = (
    (Name: 'PLAN'; View: vkPlan; Az: 0; El: 0),
    (Name: 'ISO'; View: vkIso; Az: 0; El: 0),
    (Name: 'CORNER FRONT-LEFT'; View: vkOrbit; Az: -Pi / 4; El: ISO_EL),
    (Name: 'CORNER FRONT-RIGHT'; View: vkOrbit; Az: Pi / 4; El: ISO_EL),
    (Name: 'CORNER BACK-RIGHT'; View: vkOrbit; Az: 3 * Pi / 4; El: ISO_EL),
    (Name: 'CORNER BACK-LEFT'; View: vkOrbit; Az: -3 * Pi / 4; El: ISO_EL),
    (Name: 'FRONT'; View: vkOrbit; Az: 0; El: 0),
    (Name: 'RIGHT'; View: vkOrbit; Az: Pi / 2; El: 0),
    (Name: 'BACK'; View: vkOrbit; Az: Pi; El: 0),
    (Name: 'LEFT'; View: vkOrbit; Az: -Pi / 2; El: 0),
    (Name: 'TOP'; View: vkOrbit; Az: 0; El: 1.45));
  PRINT_DPI = 150;

  { one glyph per tool, for the button and for the cursor }
  TOOL_ICONS: array[TTool] of TIconKind =
    (ikTSelect, ikTMove, ikTLine, ikTRect, ikTArc, ikTCircle, ikTPush, ikTText, ikTErase, ikTMeasure, ikDim, ikTOrbit, ikTOffset,
    ikTRotate, ikTProtractor, ikTDrill, ikTFollow);

  TOOL_NAMES: array[TTool] of string =
    ('SELECT', 'MOVE', 'LINE', 'RECT', 'ARC', 'CIRCLE', 'PUSH/PULL', 'TEXT', 'ERASE', 'MEASURE', 'DIMENSION', 'ORBIT', 'OFFSET',
    'ROTATE', 'PROTRACTOR', 'DRILL', 'REVOLVE');

  { The strip shows the tools a drawing is made of; the rest wait behind
    MORE, one click away.  Fourteen buttons of equal weight scare people off.
    Orbit is here although it draws nothing, because a laptop without a
    middle button has no other way to get round the model. }
  MAIN_TOOLS: array[0..13] of TTool =
    (ptSelect, ptLine, ptRect, ptCircle, ptArc, ptPush, ptFollow, ptMove, ptErase, ptMeasure, ptProtractor, ptDim, ptText, ptOrbit);
  { where dividers go across the strip, after this many buttons: pick, draw,
    stand up, change, measure and label, get about }
  MAIN_BREAKS: array[0..4] of integer = (1, 5, 7, 9, 13);
  { the less common tools, behind MORE }
  MORE_TOOLS: array[0..2] of TTool =
    (ptRotate, ptOffset, ptDrill);

  TOOL_HINTS: array[TTool] of string = (
    'Select - click to pick, drag a box for several.  Ctrl adds, Shift ' + 'toggles, Ctrl+Shift takes away.  (Space)',
    'Move - pick a point on what is selected, then click where it goes.  ' + 'Hold Ctrl to leave a copy behind.  (M)',
    'Line - click a start point, then click the end or just type a length.  In a 3D view the arrows lock the plane first: left or right for upright, up or down for flat, Esc to let go.  A locked plane holds every point of the shape to it.',
    'Rectangle - click two opposite corners, or type 12''x8''.  Makes a face.',
    'Arc - pick two points, then pull the middle out.  Joins two loose ends.',
    'Circle - pick the center, then type or drag the radius.',
    'Push/pull - click a face and type how far to lift it.  Close a loop of ' + 'lines to make a face.',
    'Text - click where the note goes and type it.',
    'Erase - click an edge to delete it; a face goes when its edges do.',
    'Measure - click two points and read the distance between them.',
    'Dimension - click two points, then drag away to place the line.',
    'Orbit - drag to spin.  Shift pans, Ctrl clicks into the nearest view.  (O)',
    'Offset - click a face, then move in or out and click, or type a wall ' + 'thickness.  (F)',
    'Rotate - click the center, a point to measure from, then swing to the ' + 'angle or type it (34.1, or 8:12 for a slope).  Arrows pick the ' +
    'plane, Ctrl leaves a copy.  (Q)',
    'Protractor - click the vertex, a point to measure from, then the ' + 'angle, or type it.  Lays a guide line at that angle.',
    'Drill - push a shape through everything.  Where the hole crosses a ' + 'tunnel already there, both are cut open into each other.  (B)',
    'Revolve - spin a face round an axis into a solid.  Draw the outline of ' + 'half of it, click the face, then click two points on the axis - or a ' +
    'circle to follow round.  Type an angle first for a part turn.  This ' + 'is SketchUp''s Follow Me, and it will also sweep a face along a line.');

  { how close the cursor must be to a guide to point at it.  Tighter than an
    edge on purpose (see PickAt). }
  GUIDE_PICK_PX = 4;

  { TColor is $00BBGGRR }
  PALETTE: array[0..11] of TColor = (
    $1A1A1A, $FFFFFF, $A8A4A0, $2A2AE2, $1A7AFF, $1AC6FF,
    $3CDC7A, $5AB422, $C8C81E, $F06034, $EB5096, $AA3CEB);

  { The window is long; its parts are in mainform/, in this order. }
  {$I mainform/hsMainHelpers.inc}
  {$I mainform/hsMainLifecycle.inc}
  {$I mainform/hsMainLayout.inc}
  {$I mainform/hsMainView.inc}
  {$I mainform/hsMainMenus.inc}
  {$I mainform/hsMainTabs.inc}
  {$I mainform/hsMainPanels.inc}
  {$I mainform/hsMainScreen.inc}
  {$I mainform/hsMainTools.inc}
  {$I mainform/hsMainMouse.inc}
  {$I mainform/hsMainWindow.inc}
  {$I mainform/hsMainCube.inc}
  {$I mainform/hsMainKeys.inc}
  {$I mainform/hsMainFiles.inc}
  {$I mainform/hsMainSettings.inc}

end.

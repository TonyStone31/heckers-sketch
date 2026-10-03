unit hsRadiant;

{ The radiant heat layout tool: given a floor outline and a manifold point,
  fill it with tube.  Rows run at the spacing out from the manifold, cut
  around holes (obstacles).  Each loop is built a row-pair at a time and
  checked against the tube's length limit (hsRadiantData) and against
  every run already laid.  A bounded heuristic, not a guarantee.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, Graphics, hsDrawing, hsRadiantData;

type
  { a point in the floor's plane, in Double: a barn's worth of floor at
    sub-inch accuracy needs more than Single }
  T2 = record X, Y: Double; end;
  T2Array = array of T2;
  TIntArray = array of Integer;
  TRadiantHoles = array of TP3Array;

  { the frame the layout is worked in: the outline's first corner, U
    along its longest edge, V across, N out of it }
  TRadiantFrame = record
    Origin: TP3;
    U, V, N: TP3;
  end;

  TRadiantSpec = record
    Tube: TTubeSize;
    Spacing: Double;          { world units (feet) - on center }
    MaxLoopFt: Double;        { 0 = the tube's own table maximum }
    WastePct: Double;
    { the manifolds, where they stand; a loop goes to the nearest.  Extra
      is obstacles the wizard added beyond the face's own holes. }
    Manifolds: TP3Array;
    Ports: TIntArray;             { legacy hint only; routing sizes the manifold afterward }
    Extra: TRadiantHoles;
    ManifoldW, ManifoldH: Double;   { the little box drawn for each }
    { each manifold's heading in its zone's frame (RadiantFrameOf), degrees:
      the way its long side and row of ports run.  Set by the wizard. }
    ManifoldAngles: array of Double;
    { the slab }
    SlabThick: Double;
    TubeDepth: Double;        { 0 = centered in the slab }
    UnderR: Double;
    Tag: string;
    Labels: Boolean;          { loop and manifold notes on the drawing; off
                                to inspect the paths, which they cover }
    Inch: Double;             { the drawing's own inch, as TTransitionSpec keeps it }
    { the goals: this much of the floor covered, and every loop of a
      manifold within this much of its longest, percent.  0 is no goal.
      A search watched in the wizard keeps going until both are met or it
      is stopped. }
    GoalCoverPct, GoalEvenPct: Double;
    { where the seeds of the random layouts start; 0 takes one from the
      clock so a floor searched again goes other ways.  The engine has its
      own generator, so a seed means the same on every machine and the
      same seed searches the same again. }
    SearchSeed: Cardinal;
    { the most loops one manifold takes; a zone that needs more is for the
      user to split, not for the layout to put on another header.
      0 = MANIFOLD_PORTS_MAX. }
    MaxPorts: Integer;
    { the manifold stays where it was put: the search never slides it along
      its wall }
    PinManifold: Boolean;
    { allow layouts under FRIENDLY_MIN to meet the goals.  Off, a search
      with goals tries friendly layouts first: an unfriendly one meets no
      goal and ranks after every friendly one. }
    LessFriendly: Boolean;
    { no hooks at the far wall (see HookLoops) tried at all }
    NoHooks: Boolean;
    { loops may be laid in hooked pairs - see Pairs on ComputeRadiantOriented }
    HookPairs: Boolean;
  end;

  TRadiantLoop = record
    Pts: TP3Array;             { the centerline, manifold to manifold }
    LenFt: Double;
    Manifold: Integer;         { which one it runs from }
    { laid as one of a hooked pair: +1 the first (its partner is the next
      loop), -1 the second, 0 neither - see Pairs }
    Couple: Integer;
  end;
  TRadiantLoopArray = array of TRadiantLoop;

  { one lane the search tried, in order, for watching it work.  Kept only
    when asked for (WantTrace), since it costs a second search's worth of
    geometry. }
  TRadiantTraceStep = record
    Pts: TP3Array;             { the candidate loop, exactly as it would be kept }
    Accepted: Boolean;         { kept, or turned back for crossing tube already down }
  end;
  TRadiantTrace = array of TRadiantTraceStep;

  { how easy one loop is to set out with a tape - see RadiantFriendliness }
  TLoopFriendly = record
    Measures: Integer;     { reference measurements it takes to set out }
    ExtraBends: Integer;   { bends past a plain serpentine's }
    Compact: Double;       { how fully its rows fill their own rectangle, 0..1 }
    Score: Double;         { 0..100 }
  end;
  TLoopFriendlyArray = array of TLoopFriendly;

  TManifoldResult = record
    At: TP3;
    Ports: Integer;            { as chosen }
    LoopCount: Integer;        { as laid }
    Ft: Double;
    { which way it hangs, degrees in the zone's frame (RadiantFrameOf);
      Spec.ManifoldAngles, or 0 }
    Heading: Double;
  end;

  TRadiantResult = record
    Loops: TRadiantLoopArray;
    Manifolds: array of TManifoldResult;
    AreaSqFt: Double;
    RowCount: Integer;
    ObstacleCount: Integer;
    TotalFt: Double;           { every loop, no waste }
    OrderFt: Double;           { with waste, rounded up }
    { the turn the layout asks of the tube at each row end (the spacing, in
      inches) against what the tube can do: 8x its OD for PEX-B and PEX-C,
      6x for PEX-A.  Laid at the asked spacing either way; the ticket says
      which tube can make it. }
    TurnActualIn, TurnMinIn, TurnMinPexAIn: Double;
    { how many joins between spans, or leads, run straight through an
      obstacle.  Those need routing by hand; the ticket says so. }
    Crossings: Integer;
    CellCount: Integer;
    { how far out from the manifold its tubes run before they are all on the
      grid, feet: MANIFOLD_BREAKOUT_FT, or more when the floor needed it }
    BreakoutFt: Double;
    { how many layouts the search tried, and whether it stopped short of its
      goals }
    Tries: Integer;
    ShortOfGoals: Boolean;
    { for the installer: every change of direction, and the percent of tube
      in straights of STRAIGHT_RUN_SPACINGS spacings or more }
    Bends: Integer;
    StraightPct: Double;
    { floor no loop could take: a lone row with no partner, or the far side
      of an obstacle - said on the ticket }
    UnfilledSqFt: Double;
    { a side whose rows came out odd at the spacing (what EvenRows changes,
      see RowPlan), and the closest two rows came where they were evened;
      the spacing when not }
    OddRows: Boolean;
    TightestGap: Double;
    { a side whose loops came out with a runt as first laid - what Fold
      changes (see LaySideSettled); a strip behind a manifold with a runt
      loop or none - what Strip changes (see LayManifold's Behind) }
    Runts, Strips: Boolean;
    { how far the search slid the manifold along its wall, feet; 0 if not
      moved - see ComputeRadiantLayout }
    ManifoldShiftFt: Double;
    { the search's record for the ticket: how long it ran, and a line for
      each thing that happened (goals changed, met or not, loops forced,
      and the wizard's own: stopped, gave up) }
    SearchSecs: Double;
    SearchLog: TStringArray;
    { how friendly to lay, 0..100, the mean of its loops'; -1 when not
      worked out - see RadiantFriendliness }
    Friendly: Double;
    LoopFriendly: TLoopFriendlyArray;
    Ok: Boolean;
    Why: string;
    { every lane tried - empty unless WantTrace }
    Trace: TRadiantTrace;
  end;

  { a zone: one face of the drawing and the holes cut into it }
  TRadiantZone = record
    Outline: TP3Array;
    Holes: TRadiantHoles;
  end;
  TRadiantZones = array of TRadiantZone;
  TRadiantResults = array of TRadiantResult;
  PRadiantResults = ^TRadiantResults;

  { called between tries with progress - Done of Total, Total 0 once past
    the fixed restarts and into the random layouts - and the best so far.
    Setting Stop ends the search, keeping that best. }
  TRadiantProgress = procedure(Done, Total: Integer; const Best: TRadiantResult;
    var Stop: Boolean) of object;

  { goals a watcher can change while the search runs, read after every
    layout tried; see LiveGoals on ComputeRadiantLayout }
  TRadiantGoals = record
    CoverPct, EvenPct: Double;
    { out, while the search runs: layouts laid so far, including ones not
      yet weighed (they are weighed a batch at a time) }
    Laid: Integer;
    { less friendly layouts allowed, hooks not - see the spec }
    LessFriendly, NoHooks: Boolean;
  end;
  PRadiantGoals = ^TRadiantGoals;

var
  { Whether the search may use threads.  Set by the program that links a
    thread driver (etchasketch.lpr, beside cthreads), never guessed: without
    one the RTL's no-thread stubs fail silently (nil events, waits that
    return at once) and the search would weigh layouts nobody laid.  The
    layouts are the same either way. }
  RadiantThreads: Boolean = False;

function DefaultRadiantSpec: TRadiantSpec;
function Point2(X, Y: Double): T2;
function SegsMeet(const P0, P1, Q0, Q1: T2): Boolean;
function RadiantInside(const Outline: TP3Array; const P: TP3): Boolean;

{ Is edge I of the outline a piece of a curve rather than a wall?  It
  turns only a little into a neighbor about as long as itself
  (SUGGEST_ARC_TURN, SUGGEST_ARC_RATIO).  A flat cabinet does not hang on one. }
function RadiantEdgeCurved(const Outline: TP3Array; I: Integer): Boolean;

{ Where a zone's manifold goes when nothing better is known: a foot in from
  a flat wall, at the middle or a quarter point that heats the most floor,
  nearest Toward among near ties - so a building's manifolds end up toward
  the boiler.  Not a corner: a corner has half the edge to let tubes out.
  Also returns how many loops it takes, with one to spare. }
procedure RadiantSuggestZoneManifold(const Zone: TRadiantZone; const Toward: TP3;
  const Spec: TRadiantSpec; out At: TP3; out Ports: Integer);

const
  { a color for each manifold (its zone), for its box and note }
  ZONE_INKS: array[0..7] of TColor = ($002030C8, $00C86020, $0030A030, $008020A0,
    $0020A0A0, $00A0A020, $00C03080, $00606060);

function ZoneInk(Manifold: Integer): TColor;
function LoopWeight(LoopOfManifold: Integer): Single;
{ Every loop its own color, so one run can be followed by eye among dozens.
  Neighbors never share one, and each zone starts at a different place in
  the list. }
function LoopInk(Zone, Loop: Integer): TColor;

{ The frame and the way in and out of it - shared by the layout and the
  dialog's plan, so a point dragged on the plan lands where the layout
  thinks it is. }
function RadiantFrameOf(const Outline: TP3Array): TRadiantFrame;
{ The frame the wizard draws its plan in: the drawing's own plan (east
  right, north up) for a flat floor, whichever way its outline was drawn.
  RadiantFrameOf turns with the longest wall and the winding, which would
  show a clockwise floor mirrored.  A floor that is not flat keeps its
  longest wall along, seen from above. }
function RadiantPlanFrame(const Outline: TP3Array): TRadiantFrame;
function RadiantTo2(const F: TRadiantFrame; const P: TP3): T2;
function RadiantFrom2(const F: TRadiantFrame; U, V: Double): TP3;

{ How many loops this floor wants at this tube and spacing, before any
  manifold is placed: its area over what one loop covers. }
function RadiantLoopsNeeded(const Outline: TP3Array; const Holes: array of TP3Array;
  const Spec: TRadiantSpec): Integer;

{ Where to put the manifolds and how many loops each: enough manifolds for
  the loop count, spaced evenly along the longest wall a foot in from it.
  A starting point to drag from, not an answer. }
procedure RadiantSuggestManifolds(const Outline: TP3Array; const Holes: array of TP3Array;
  const Spec: TRadiantSpec; out At: TP3Array; out Ports: TIntArray);

{ What is wrong with the spec for this outline, or '' when it is fit to
  build - so a bad number is reported in words, not as an empty floor. }
function RadiantProblem(const Outline: TP3Array; const Spec: TRadiantSpec): string;

{ The layout itself - pure geometry, so the preview and the real build never
  disagree.  Holes are the face's own plus the dialog's temporary ones.
  WantTrace records every lane tried.  Progress runs after every layout and
  may stop the search; Found gets the distinct solutions, best first;
  LiveGoals is re-read after every layout, and changed goals apply from then. }
function ComputeRadiantLayout(const Outline: TP3Array; const Holes: array of TP3Array;
  const Spec: TRadiantSpec; WantTrace: Boolean = False;
  Progress: TRadiantProgress = nil; Found: PRadiantResults = nil;
  LiveGoals: PRadiantGoals = nil): TRadiantResult;

{ How much of its floor a layout covers and how far its shortest loop
  falls short of its longest (the worst manifold), as fractions; and
  whether that meets the spec's goals. }
procedure RadiantMeasure(const R: TRadiantResult; out Cover, Spread: Double);
{ the same spread as a length: how much shorter the shortest loop is than
  the longest, feet, on the worst manifold }
function RadiantSpreadFt(const R: TRadiantResult): Double;
{ How friendly a layout is to the installer, loop by loop: measures (places
  rows stop short of a wall, or a lead leaves the manifold, that need a
  tape; each past two costs 15), extra bends past a plain serpentine (2
  each), and how fully its rows fill their rectangle (under 85% costs up to
  50).  The layout's score is the mean of its loops'.  Filled into R. }
procedure RadiantFriendliness(var R: TRadiantResult; const Outline: TP3Array;
  const Holes: array of TP3Array; const Spec: TRadiantSpec);
{ it in words: "installer friendly: 89/100 - 10 of 11 loops set out from
  two measurements or fewer; loop 6 takes 5" }
function RadiantFriendlyText(const R: TRadiantResult): string;
function RadiantMeetsGoals(const R: TRadiantResult; const Spec: TRadiantSpec): Boolean;
{ a layout under FRIENDLY_MIN where the spec wants friendly ones
  (LessFriendly off, goals set); one whose friendliness was never worked
  out is not held against it }
function RadiantUnfriendly(const R: TRadiantResult; const Spec: TRadiantSpec): Boolean;
{ the most loops a manifold takes, by the spec - see MaxPorts }
function RadiantMaxPorts(const Spec: TRadiantSpec): Integer;
{ The most of a floor of AreaSqFt, percent, the spec's tube can reach:
  every manifold's most loops, each at full tube length, at the spacing.
  An upper bound (leads and walls ignored); 100 when it is not the limit.
  A goal past it can never be met. }
function RadiantReachPct(AreaSqFt: Double; const Spec: TRadiantSpec): Double;
{ that in words for the ticket, or Short for the wizard's zone; '' when the
  goal is within reach }
function RadiantReachText(AreaSqFt: Double; const Spec: TRadiantSpec; Short: Boolean = False): string;
{ a floor's area less its obstacles, square feet }
function RadiantFloorArea(const Outline: TP3Array; const Holes: array of TP3Array): Double;
{ how many loops the layout's fullest manifold has past that; 0 within it }
function RadiantOverPorts(const R: TRadiantResult; const Spec: TRadiantSpec): Integer;

{ Writes the result into the drawing as one part: the runs as reference
  lines in the tube's ink, a box and a note for the manifold, and a note
  on every hole that was routed around.  Returns the first entity added. }
function BuildRadiant(D: TWorkDoc; const Outline: TP3Array; const Holes: array of TP3Array;
  const R: TRadiantResult; const Spec: TRadiantSpec; Ink: TColor; PartName: string;
  Zone: Integer = 0): Integer;

{ Seconds as a person says them: 42 s, 3 min 05 s, 1 h 02 min. }
function RadiantDuration(Secs: Double): string;

{ About how much wall a manifold of this many loops needs, inches: supply
  and return side by side a port pitch apart, plus the ends (MANIFOLD_ENDS_IN). }
function RadiantManifoldWallIn(Ports: Integer): Double;

{ The material list and the numbers behind it, as words - the ticket. }
function RadiantTicketText(const Spec: TRadiantSpec; const R: TRadiantResult;
  U: TUnitSystem): string;

implementation

type
  TSpan = record Lo, Hi: Double; end;
  TSpanArray = array of TSpan;
  TDoubleArray = array of Double;

  { everything a layout is laid from - enough to lay it again exactly }
  TTry = record
    Turn: Boolean;
    Budget, BreakFt: Double;
    Ranks: Integer;
    Seed: Cardinal;
    { the row grid slid this fraction of a spacing off the wall }
    RowOff: Double;
    { no fingers grown, only turns pushed out }
    NoFingers: Boolean;
    { every side's rows evened up at the far wall - see RowPlan }
    EvenRows: Boolean;
    { the manifold slid this far along its wall, feet - see Slid }
    Shift: Double;
    { this many loops more or fewer than the layout would choose - see
      LoopDelta }
    LoopDelta: Integer;
    { fingers as short as FINGER_SHORT_SPACINGS - see ShortFingers }
    ShortFingers: Boolean;
    { a runt's side laid again with its tube shared out; the strip behind
      the manifold taken by the loop in front - see Fold and Strip }
    Fold, Strip: Boolean;
    { a loop cut short, the loops grown in no order - see Wild }
    Wild: Boolean;
    { loops evened by hooks at the far wall - see Hook }
    Hook: Boolean;
    { loops laid in hooked pairs - see Pairs }
    Pairs: Boolean;
  end;

  { a layout laid ahead (see Prefetch): the try and its result }
  TRadiantJob = record
    T: TTry;
    R: TRadiantResult;
    Fail: string;              { '' - or why it could not be laid at all }
  end;

  { Some of the limits one layout is laid under, laid on another thread for
    the calling layout to weigh (see TryLimits).  In: each limit and its
    target length.  Out: the loops and bare floor, and what the laying saw
    (see OddRows, TightestGap, Runts and Strips on the result). }
  TSweepItem = record
    T, Target: Double;
    Trial: TRadiantLoopArray;
    Unf: Double;
  end;
  TRadiantSweep = record
    Items: array of TSweepItem;
    Odd, Runts, Strips: Boolean;
    Tightest: Double;
  end;
  PRadiantSweep = ^TRadiantSweep;

  TRadiantPool = class;
  TRadiantGroup = class;
  TRadiantTask = class;
  TRadiantTaskArray = array of TRadiantTask;

  { A piece of work for the pool, run on whichever thread takes it. }
  TRadiantTask = class
  private
    FGroup: TRadiantGroup;
  public
    { Never waits on other tasks: a thread waiting on its own tasks may run
      this one meanwhile (see TRadiantPool.Wait), so no deadlock. }
    Leaf: Boolean;
    { '' - or why it could not be done at all; Run itself never raises }
    Fail: string;
    procedure Run; virtual; abstract;
  end;

  { tasks waited for together }
  TRadiantGroup = class
  private
    FLeft: LongInt;
    FDone: PRTLEvent;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  { one layout: the try and the spec, the manifold already slid }
  TLayTask = class(TRadiantTask)
  public
    Outline: TP3Array;
    Holes: TRadiantHoles;
    T: TTry;
    Spec: TRadiantSpec;
    R: TRadiantResult;
    procedure Run; override;
  end;

  { some of one layout's limits (see TRadiantSweep), with everything the
    layout is laid from, to lay them exactly as it would }
  TSweepTask = class(TRadiantTask)
  public
    Outline: TP3Array;
    Holes: TRadiantHoles;
    Spec: TRadiantSpec;
    Turn, Fingers, EvenRows, ShortFingers, Fold, Strip, Wild, Pairs: Boolean;
    FirstBudget, BreakFt, RowOff: Double;
    ExtraRanks, LoopDelta: Integer;
    Seed: Cardinal;
    Sweep: TRadiantSweep;
    procedure Run; override;
  end;

  { one worker thread of the pool }
  TRadiantWorker = class(TThread)
  private
    FPool: TRadiantPool;
    FGo: PRTLEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(APool: TRadiantPool);
    destructor Destroy; override;
  end;

  { One pool for the program (see ThePool): RADIANT_JOBS threads, or every
    core but one.  Leaves (limits of layouts under way) go before new
    layouts, so started work finishes first.  Tasks only call
    ComputeRadiantOriented, which uses its own locals, so the results are
    the same on one thread or thirty-two. }
  TRadiantPool = class
  private
    FWorkers: array of TRadiantWorker;
    { the FPU state of the thread that made the pool.  A new FPC thread
      starts from RTL defaults, but GTK masks exceptions on the main thread,
      so geometry that quietly made an infinity there would raise here. }
    FMask: TFPUExceptionMask;
    FRound: TFPURoundingMode;
    FLock: TRTLCriticalSection;
    FLeaves, FTasks: array of TRadiantTask;
    FLeafHead, FTaskHead: Integer;
    { tasks queued and not yet taken }
    FQueued: LongInt;
    FQuit: Boolean;
    function Pop(LeavesOnly: Boolean): TRadiantTask;
    procedure RunTask(T: TRadiantTask);
  public
    constructor Create;
    destructor Destroy; override;
    function Threads: Integer;
    { Ts set going as group G }
    procedure Submit(G: TRadiantGroup; const Ts: array of TRadiantTask);
    { up to Ms for group G to finish; returns whether it has.  Help: lay
      leaves meanwhile and wait until done }
    function Wait(G: TRadiantGroup; Ms: Integer; Help: Boolean): Boolean;
    { a worker with nothing queued for it, so a layout may share out its limits }
    function Spare: Boolean;
  end;

var
  { searches begun, mixed into a clock seed so two begun in the same
    millisecond still differ - see SearchSeed }
  SearchesStarted: Cardinal = 0;

function Point2(X, Y: Double): T2;
begin
  Result.X := X; Result.Y := Y;
end;

{ ---------------------------------------------------------------------- }
{ the plane the outline lies in, and a 2D frame inside it                }
{ ---------------------------------------------------------------------- }

function Newell(const L: TP3Array): TP3;
var
  I, J, N: Integer;
begin
  Result := P3(0, 0, 0);
  N := Length(L);
  for I := 0 to N - 1 do
  begin
    J := (I + 1) mod N;
    Result.X := Result.X + (L[I].Y - L[J].Y) * (L[I].Z + L[J].Z);
    Result.Y := Result.Y + (L[I].Z - L[J].Z) * (L[I].X + L[J].X);
    Result.Z := Result.Z + (L[I].X - L[J].X) * (L[I].Y + L[J].Y);
  end;
end;

function VNorm(const P: TP3): TP3;
var
  L: Double;
begin
  L := Sqrt(P.X * P.X + P.Y * P.Y + P.Z * P.Z);
  if L < 1E-12 then Exit(P3(0, 0, 0));
  Result := P3(P.X / L, P.Y / L, P.Z / L);
end;

{ the outline's own plane: origin at its first corner, U along its longest
  edge so tube runs parallel to the long wall, V and N square to it }
function RadiantFrameOf(const Outline: TP3Array): TRadiantFrame;
var
  I, J, Best: Integer;
  L, BestL: Double;
begin
  Result.Origin := Outline[0];
  Result.N := VNorm(Newell(Outline));
  BestL := -1; Best := 0;
  for I := 0 to High(Outline) do
  begin
    J := (I + 1) mod Length(Outline);
    L := Dist(Outline[I], Outline[J]);
    if L > BestL then begin BestL := L; Best := I; end;
  end;
  J := (Best + 1) mod Length(Outline);
  Result.U := VNorm(P3(Outline[J].X - Outline[Best].X, Outline[J].Y - Outline[Best].Y,
    Outline[J].Z - Outline[Best].Z));
  Result.V := VNorm(Cross3(Result.N, Result.U));
end;

function RadiantPlanFrame(const Outline: TP3Array): TRadiantFrame;
begin
  Result := RadiantFrameOf(Outline);
  if Abs(Result.N.Z) > 0.99 then
  begin
    Result.N := P3(0, 0, 1);
    Result.U := P3(1, 0, 0);
    Result.V := P3(0, 1, 0);
  end
  else if Result.N.Z < 0 then
  begin
    Result.N := P3(-Result.N.X, -Result.N.Y, -Result.N.Z);
    Result.V := VNorm(Cross3(Result.N, Result.U));
  end;
end;

function RadiantTo2(const F: TRadiantFrame; const P: TP3): T2;
var
  D: TP3;
begin
  D := P3(P.X - F.Origin.X, P.Y - F.Origin.Y, P.Z - F.Origin.Z);
  Result.X := Dot3(D, F.U);
  Result.Y := Dot3(D, F.V);
end;

function RadiantFrom2(const F: TRadiantFrame; U, V: Double): TP3;
begin
  Result := P3(F.Origin.X + F.U.X * U + F.V.X * V,
               F.Origin.Y + F.U.Y * U + F.V.Y * V,
               F.Origin.Z + F.U.Z * U + F.V.Z * V);
end;

{ ---------------------------------------------------------------------- }
{ one row: the spans a horizontal line at V crosses inside a 2D polygon  }
{ ---------------------------------------------------------------------- }

function RowSpans(const Poly: array of T2; V: Double): TSpanArray;
var
  I, J, N, K, M: Integer;
  Xs: array of Double;
  A, B, T: Double;
begin
  SetLength(Result, 0);
  N := Length(Poly);
  if N < 3 then Exit;
  SetLength(Xs, 0);
  for I := 0 to N - 1 do
  begin
    J := (I + 1) mod N;
    { half-open on the low end so a corner sitting exactly on the row is
      never counted by both the edge above it and the edge below }
    if ((Poly[I].Y <= V) and (Poly[J].Y > V)) or ((Poly[J].Y <= V) and (Poly[I].Y > V)) then
    begin
      T := (V - Poly[I].Y) / (Poly[J].Y - Poly[I].Y);
      SetLength(Xs, Length(Xs) + 1);
      Xs[High(Xs)] := Poly[I].X + T * (Poly[J].X - Poly[I].X);
    end;
  end;
  { insertion sort - a row rarely crosses more than a handful of edges }
  for I := 1 to High(Xs) do
  begin
    T := Xs[I]; K := I;
    while (K > 0) and (Xs[K - 1] > T) do begin Xs[K] := Xs[K - 1]; Dec(K); end;
    Xs[K] := T;
  end;
  M := (Length(Xs) div 2) * 2;
  SetLength(Result, M div 2);
  for I := 0 to M div 2 - 1 do
  begin
    A := Xs[I * 2]; B := Xs[I * 2 + 1];
    Result[I].Lo := A; Result[I].Hi := B;
  end;
end;

{ Outer spans, less whatever the hole spans cover - interval subtraction.
  Both arrays are sorted low to high and do not overlap themselves, which
  RowSpans already guarantees. }
function Subtract(const Outer: TSpanArray; const Cuts: TSpanArray): TSpanArray;
var
  I, J, N: Integer;
  Lo: Double;
  Piece: TSpan;
begin
  SetLength(Result, 0);
  N := 0;
  for I := 0 to High(Outer) do
  begin
    Lo := Outer[I].Lo;
    for J := 0 to High(Cuts) do
    begin
      if (Cuts[J].Hi <= Lo) or (Cuts[J].Lo >= Outer[I].Hi) then Continue;
      if Cuts[J].Lo > Lo then
      begin
        Piece.Lo := Lo; Piece.Hi := Cuts[J].Lo;
        SetLength(Result, N + 1); Result[N] := Piece; Inc(N);
      end;
      Lo := Max(Lo, Cuts[J].Hi);
    end;
    if Lo < Outer[I].Hi then
    begin
      Piece.Lo := Lo; Piece.Hi := Outer[I].Hi;
      SetLength(Result, N + 1); Result[N] := Piece; Inc(N);
    end;
  end;
end;

{ Is the point inside the outline, seen square to the floor's own plane,
  not the world's?  A sloped floor would break a plain X/Y test. }
function RadiantInside(const Outline: TP3Array; const P: TP3): Boolean;
var
  F: TRadiantFrame;
  Poly: T2Array;
  Pt: T2;
  I, J, N: Integer;
begin
  Result := False;
  N := Length(Outline);
  if N < 3 then Exit;
  F := RadiantFrameOf(Outline);
  SetLength(Poly, N);
  for I := 0 to N - 1 do Poly[I] := RadiantTo2(F, Outline[I]);
  Pt := RadiantTo2(F, P);
  J := N - 1;
  for I := 0 to N - 1 do
  begin
    if ((Poly[I].Y > Pt.Y) <> (Poly[J].Y > Pt.Y)) and
       (Pt.X < (Poly[J].X - Poly[I].X) * (Pt.Y - Poly[I].Y) / (Poly[J].Y - Poly[I].Y) + Poly[I].X) then
      Result := not Result;
    J := I;
  end;
end;

{ Do the closed segments P0-P1 and Q0-Q1 share any point - a crossing, a
  touch, or a length run together?  Two runs of tube in a slab may do
  none of them. }
function SegsMeet(const P0, P1, Q0, Q1: T2): Boolean;
const
  E = 1E-7;

  function Orient(const P, Q, R: T2): Double;
  begin
    Result := (Q.X - P.X) * (R.Y - P.Y) - (Q.Y - P.Y) * (R.X - P.X);
  end;

  function OnSeg(const P, Q, R: T2): Boolean;   { R on P-Q, given collinear }
  begin
    Result := (R.X >= Min(P.X, Q.X) - E) and (R.X <= Max(P.X, Q.X) + E) and
              (R.Y >= Min(P.Y, Q.Y) - E) and (R.Y <= Max(P.Y, Q.Y) + E);
  end;

var
  D1, D2, D3, D4: Double;
begin
  D1 := Orient(Q0, Q1, P0); D2 := Orient(Q0, Q1, P1);
  D3 := Orient(P0, P1, Q0); D4 := Orient(P0, P1, Q1);
  if (((D1 > E) and (D2 < -E)) or ((D1 < -E) and (D2 > E))) and
     (((D3 > E) and (D4 < -E)) or ((D3 < -E) and (D4 > E))) then Exit(True);
  if (Abs(D1) <= E) and OnSeg(Q0, Q1, P0) then Exit(True);
  if (Abs(D2) <= E) and OnSeg(Q0, Q1, P1) then Exit(True);
  if (Abs(D3) <= E) and OnSeg(P0, P1, Q0) then Exit(True);
  if (Abs(D4) <= E) and OnSeg(P0, P1, Q1) then Exit(True);
  Result := False;
end;

{ ---------------------------------------------------------------------- }

function ZoneInk(Manifold: Integer): TColor;
begin
  Result := ZONE_INKS[Manifold mod Length(ZONE_INKS)];
end;

const
  { twelve strong colors that stay apart on white and on the dark theme,
    none of them gray - $00BBGGRR }
  LOOP_INKS: array[0..11] of TColor = ($00B4771F, $000E7FFF, $002CA02C, $002827D6,
    $00BD6794, $004B568C, $00C277E3, $0022BDBC, $00CFBE17, $00793B39, $00397963, $00393C84);

function LoopInk(Zone, Loop: Integer): TColor;
begin
  Result := LOOP_INKS[(Zone * 5 + Loop) mod Length(LOOP_INKS)];
end;

function LoopWeight(LoopOfManifold: Integer): Single;
begin
  { one weight: thick and thin by turns reads as doubled tube on the plan }
  Result := 2;
end;

function DefaultRadiantSpec: TRadiantSpec;
begin
  Result := Default(TRadiantSpec);
  Result.Tube := tsHalf;
  Result.Inch := 1 / 12;
  Result.GoalCoverPct := 97;
  Result.GoalEvenPct := 10;
  Result.Spacing := SPACING_DEFAULT_IN * Result.Inch;
  Result.MaxLoopFt := 0;
  Result.WastePct := WASTE_PCT_DEFAULT;
  Result.ManifoldW := 18 * Result.Inch;
  Result.ManifoldH := 6 * Result.Inch;
  Result.SlabThick := SLAB_THICK_DEFAULT_IN * Result.Inch;
  Result.TubeDepth := 0;
  Result.UnderR := SLAB_UNDER_R_DEFAULT;
  Result.MaxPorts := MANIFOLD_PORTS_MAX;
end;

{ the area of a 2D polygon, whichever way round it goes }
function PolyArea2(const P: array of T2): Double;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 0 to High(P) do
  begin
    J := (I + 1) mod Length(P);
    Result := Result + P[I].X * P[J].Y - P[J].X * P[I].Y;
  end;
  Result := Abs(Result) / 2;
end;

function FloorArea(const Outline: TP3Array; const Holes: array of TP3Array;
  const F: TRadiantFrame): Double;
var
  P: T2Array;
  I, J: Integer;
begin
  SetLength(P, Length(Outline));
  for I := 0 to High(Outline) do P[I] := RadiantTo2(F, Outline[I]);
  Result := PolyArea2(P);
  for I := 0 to High(Holes) do
  begin
    SetLength(P, Length(Holes[I]));
    for J := 0 to High(Holes[I]) do P[J] := RadiantTo2(F, Holes[I][J]);
    Result := Result - PolyArea2(P);
  end;
end;

function RadiantLoopsNeeded(const Outline: TP3Array; const Holes: array of TP3Array;
  const Spec: TRadiantSpec): Integer;
var
  MaxFt, Each: Double;
begin
  if (Length(Outline) < 3) or (Spec.Spacing <= 0) then Exit(0);
  MaxFt := Spec.MaxLoopFt;
  if MaxFt <= 0 then MaxFt := TubeOf(Spec.Tube).MaxLoopFt;
  Each := MaxFt * Spec.Spacing * LOOP_AREA_FACTOR;
  if Each <= 0 then Exit(0);
  Result := Max(1, Ceil(FloorArea(Outline, Holes, RadiantFrameOf(Outline)) / Each));
end;

procedure RadiantSuggestManifolds(const Outline: TP3Array; const Holes: array of TP3Array;
  const Spec: TRadiantSpec; out At: TP3Array; out Ports: TIntArray);
var
  F: TRadiantFrame;
  Loops, N, I, Each: Integer;
  Umin, Umax, Vmin, Vmax, U, V: Double;
  P: T2;
begin
  SetLength(At, 0); SetLength(Ports, 0);
  if Length(Outline) < 3 then Exit;
  Loops := RadiantLoopsNeeded(Outline, Holes, Spec);
  if Loops <= 0 then Exit;
  N := Max(1, Ceil(Loops / RadiantMaxPorts(Spec)));
  { a port to spare each: the count is a guess, and a manifold short a port
    means a second manifold }
  Each := Min(RadiantMaxPorts(Spec), Max(MANIFOLD_PORTS_MIN, Ceil(Loops / N) + 1));
  F := RadiantFrameOf(Outline);
  Umin := 1E30; Umax := -1E30; Vmin := 1E30; Vmax := -1E30;
  for I := 0 to High(Outline) do
  begin
    P := RadiantTo2(F, Outline[I]);
    Umin := Min(Umin, P.X); Umax := Max(Umax, P.X);
    Vmin := Min(Vmin, P.Y); Vmax := Max(Vmax, P.Y);
  end;
  { along the long wall (U is the longest edge), a foot in, each at the
    middle of its share of the length }
  SetLength(At, N); SetLength(Ports, N);
  V := Vmin + 1;
  for I := 0 to N - 1 do
  begin
    U := Umin + (Umax - Umin) * (I + 0.5) / N;
    At[I] := RadiantFrom2(F, U, V);
    Ports[I] := Each;
  end;
end;

function ComputeRadiantOriented(const Outline: TP3Array; const Holes: array of TP3Array;
  const Spec: TRadiantSpec; WantTrace, Turn: Boolean; FirstBudget: Double; ExtraRanks: Integer;
  BreakFt: Double; Seed: Cardinal; RowOff: Double = 0; Fingers: Boolean = True;
  Quick: Boolean = False; EvenRows: Boolean = False; LoopDelta: Integer = 0;
  ShortFingers: Boolean = False; Fold: Boolean = False; Strip: Boolean = False;
  Wild: Boolean = False; Sweep: PRadiantSweep = nil; Hook: Boolean = False;
  Pairs: Boolean = False): TRadiantResult; forward;
function ThePool: TRadiantPool; forward;

function RadiantEdgeCurved(const Outline: TP3Array; I: Integer): Boolean;
var
  N: Integer;

  function Len(K: Integer): Double;
  begin
    K := (K + N) mod N;
    Result := Dist(Outline[K], Outline[(K + 1) mod N]);
  end;

  { the turn at corner K, from edge K-1 into edge K, degrees }
  function TurnAt(K: Integer): Double;
  var
    A, B, C: TP3;
  begin
    A := Outline[(K + N - 1) mod N]; B := Outline[K mod N]; C := Outline[(K + 1) mod N];
    Result := Abs(RadToDeg(ArcTan2((B.X - A.X) * (C.Y - B.Y) - (B.Y - A.Y) * (C.X - B.X),
      (B.X - A.X) * (C.X - B.X) + (B.Y - A.Y) * (C.Y - B.Y))));
  end;

  function Gentle(T: Double): Boolean;
  begin
    Result := (T >= 1) and (T < SUGGEST_ARC_TURN);
  end;

  function Alike(A, B: Double): Boolean;
  begin
    Result := (A <= SUGGEST_ARC_RATIO * B) and (B <= SUGGEST_ARC_RATIO * A);
  end;

begin
  N := Length(Outline);
  Result := False;
  if (N < 3) or (I < 0) or (I >= N) then Exit;
  Result := (Gentle(TurnAt(I)) and Alike(Len(I), Len(I - 1))) or
    (Gentle(TurnAt(I + 1)) and Alike(Len(I), Len(I + 1)));
end;

procedure RadiantSuggestZoneManifold(const Zone: TRadiantZone; const Toward: TP3;
  const Spec: TRadiantSpec; out At: TP3; out Ports: Integer);
type
  { A wall: the run of outline edges that go straight on (where a line from
    the next zone meets a wall is no corner), and whether it is a piece of
    a curve.  A manifold is a flat cabinet for a flat wall; on a curve the
    tubes fan off at a slant and leave floor bare.  A curve piece turns only
    a little into a neighbor about as long as itself. }
  TWall = record
    First, Count: Integer;
    Len: Double;
    Curved: Boolean;
  end;
  { a spot a manifold might go, and how it weighs }
  TCand = record
    At_: TP3;
    { Cov_ is what Reach makes of it; Quick_ what one quick layout does
      (rows one way, breakout at 8 ft), which weighs the walls' middles }
    WallLen, Dst_, Cov_, Quick_: Double;
    Middle: Boolean;
  end;
var
  I, J, K, N, Best, Start: Integer;
  BestD, BestL, BestCover: Double;
  EdgeLen: array of Double;
  Cands: array of TCand;
  BestMid: Double;
  Quarters: Boolean;
  Walls: array of TWall;
  Trial: TRadiantSpec;
  R: TRadiantResult;

  { the turn at corner I, from edge I-1 into edge I, degrees, 0 to 180 }
  function TurnAt(I: Integer): Double;
  var
    A, B, C: TP3;
  begin
    A := Zone.Outline[(I + N - 1) mod N]; B := Zone.Outline[I]; C := Zone.Outline[(I + 1) mod N];
    Result := Abs(RadToDeg(ArcTan2((B.X - A.X) * (C.Y - B.Y) - (B.Y - A.Y) * (C.X - B.X),
      (B.X - A.X) * (C.X - B.X) + (B.Y - A.Y) * (C.Y - B.Y))));
  end;

  { a foot in from the point T of the way along edge I, square to it, on the
    floor's side }
  function OffWall(I: Integer; T: Double): TP3;
  var
    A, B, M, Nrm: TP3;
    Len: Double;
  begin
    A := Zone.Outline[I]; B := Zone.Outline[(I + 1) mod N];
    M := P3(A.X + T * (B.X - A.X), A.Y + T * (B.Y - A.Y), A.Z + T * (B.Z - A.Z));
    Len := Max(1E-9, Hypot(B.X - A.X, B.Y - A.Y));
    Nrm := P3(-(B.Y - A.Y) / Len, (B.X - A.X) / Len, 0);
    Result := P3(M.X + Nrm.X, M.Y + Nrm.Y, M.Z);
    if not RadiantInside(Zone.Outline, Result) then Result := P3(M.X - Nrm.X, M.Y - Nrm.Y, M.Z);
  end;

  { a foot in from the point Frac of the way along wall W }
  function AlongWall(const W: TWall; Frac: Double): TP3;
  var
    K, E: Integer;
    Along: Double;
  begin
    Along := W.Len * Frac;
    for K := 0 to W.Count - 1 do
    begin
      E := (W.First + K) mod N;
      if (Along <= EdgeLen[E] + 1E-9) or (K = W.Count - 1) then
        Exit(OffWall(E, Min(1, Along / Max(1E-9, EdgeLen[E]))));
      Along := Along - EdgeLen[E];
    end;
    Result := OffWall(W.First, 0.5);
  end;

  function MidWall(const W: TWall): TP3;
  begin
    Result := AlongWall(W, 0.5);
  end;

  { How much floor a manifold at P can reach, roughly: the best of four quick
    layouts, rows either way round, breakout at 6 and 10 ft.  A single quick
    layout can pick a much worse wall. }
  { one quick layout from P: rows one way, breakout at 8 ft }
  function Quick(const P: TP3): Double;
  var
    Sp: Double;
  begin
    Trial := Spec;
    SetLength(Trial.Manifolds, 1); Trial.Manifolds[0] := P;
    Trial.ManifoldAngles := nil; Trial.Ports := nil;
    R := ComputeRadiantOriented(Zone.Outline, Zone.Holes, Trial, False, False, 1, 0, 8, 0, 0, False, True, True);
    if not R.Ok then Exit(-1);
    RadiantMeasure(R, Result, Sp);
  end;

  function Reach(const P: TP3): Double;
  var
    Tn, Bk: Integer;
    C, Sp: Double;
  begin
    Result := -1;
    Trial := Spec;
    SetLength(Trial.Manifolds, 1); Trial.Manifolds[0] := P;
    Trial.ManifoldAngles := nil; Trial.Ports := nil;
    for Tn := 0 to 1 do
      for Bk := 0 to 1 do
      begin
        { rows evened at the far wall: the most the search can make of the
          wall, not just the plain grid }
        R := ComputeRadiantOriented(Zone.Outline, Zone.Holes, Trial, False, Tn = 1, 1, 0, 6 + 4 * Bk, 0, 0,
          False, True, True);
        if not R.Ok then Continue;
        RadiantMeasure(R, C, Sp);
        Result := Max(Result, C);
      end;
  end;

  { an obstacle inside the breakout round P leaves the tubes nowhere to go }
  function Crowded(const P: TP3): Boolean;
  var
    H, K: Integer;
    A, B: TP3;
    T, Lh: Double;
  begin
    Result := False;
    for H := 0 to High(Zone.Holes) do
    begin
      if RadiantInside(Zone.Holes[H], P) then Exit(True);
      for K := 0 to High(Zone.Holes[H]) do
      begin
        A := Zone.Holes[H][K]; B := Zone.Holes[H][(K + 1) mod Length(Zone.Holes[H])];
        Lh := Sqr(B.X - A.X) + Sqr(B.Y - A.Y);
        if Lh < 1E-12 then T := 0
        else T := Max(0, Min(1, ((P.X - A.X) * (B.X - A.X) + (P.Y - A.Y) * (B.Y - A.Y)) / Lh));
        if Hypot(P.X - A.X - T * (B.X - A.X), P.Y - A.Y - T * (B.Y - A.Y)) < MANIFOLD_BREAKOUT_FT then
          Exit(True);
      end;
    end;
  end;

  { two walls about as long as one another }
  function Alike(A, B: Double): Boolean;
  begin
    Result := (A <= SUGGEST_ARC_RATIO * B) and (B <= SUGGEST_ARC_RATIO * A);
  end;

begin
  At := P3(0, 0, 0); Ports := MANIFOLD_PORTS_MIN;
  N := Length(Zone.Outline);
  if N < 3 then Exit;
  SetLength(EdgeLen, N);
  for I := 0 to N - 1 do EdgeLen[I] := Dist(Zone.Outline[I], Zone.Outline[(I + 1) mod N]);
  { the walls, from a real corner round: an edge that goes straight on
    joins its wall }
  Start := 0;
  for I := 0 to N - 1 do
    if TurnAt(I) >= 1 then begin Start := I; Break; end;
  Walls := nil;
  for K := 0 to N - 1 do
  begin
    I := (Start + K) mod N;
    if EdgeLen[I] < 1E-9 then Continue;
    if (Length(Walls) = 0) or (TurnAt(I) >= 1) then
    begin
      SetLength(Walls, Length(Walls) + 1);
      Walls[High(Walls)].First := I; Walls[High(Walls)].Count := 0; Walls[High(Walls)].Len := 0;
    end;
    Inc(Walls[High(Walls)].Count);
    Walls[High(Walls)].Len := Walls[High(Walls)].Len + EdgeLen[I];
  end;
  if Length(Walls) = 0 then Exit;
  { a piece of a curve: a gentle turn at either end into a wall about as
    long.  If every wall looks curved, treat none as curved. }
  J := 0;
  for I := 0 to High(Walls) do
  begin
    K := (Walls[I].First + Walls[I].Count) mod N;
    Walls[I].Curved := (Length(Walls) > 1) and
      (((TurnAt(Walls[I].First) < SUGGEST_ARC_TURN) and
        Alike(Walls[I].Len, Walls[(I + Length(Walls) - 1) mod Length(Walls)].Len)) or
       ((TurnAt(K) < SUGGEST_ARC_TURN) and Alike(Walls[I].Len, Walls[(I + 1) mod Length(Walls)].Len)));
    if not Walls[I].Curved then Inc(J);
  end;
  if J = 0 then
    for I := 0 to High(Walls) do Walls[I].Curved := False;
  { Every flat wall's middle, plus a long wall's quarter points, weighed by
    Reach; the one that heats most floor wins, and of any within a point of
    it, the nearest Toward.  An obstacle in front of a manifold can block
    most of its lanes, which the outline alone cannot show.  A spot with an
    obstacle inside the breakout is passed over while any other will do. }
  Best := -1; BestCover := -1;
  Cands := nil;
  Quarters := False;
  for I := 0 to High(Walls) do
  begin
    if Walls[I].Curved then Continue;
    for K := 0 to 2 do
    begin
      { the middle; the quarters on a wall long enough to have them }
      if (K > 0) and (Walls[I].Len < SUGGEST_QUARTER_FT) then Continue;
      SetLength(Cands, Length(Cands) + 1);
      with Cands[High(Cands)] do
      begin
        case K of
          0: At_ := AlongWall(Walls[I], 0.5);
          1: At_ := AlongWall(Walls[I], 0.25);
        else At_ := AlongWall(Walls[I], 0.75);
        end;
        WallLen := Walls[I].Len;
        Middle := K = 0;
        Dst_ := Dist(At_, Toward);
        Cov_ := Reach(At_);
        Quick_ := Quick(At_);
        if Crowded(At_) then
        begin
          if Cov_ >= 0 then Cov_ := Cov_ - 0.5;
          if Quick_ >= 0 then Quick_ := Quick_ - 0.5;
        end;
        BestCover := Max(BestCover, Cov_);
      end;
    end;
  end;
  { A wall's middle, unless no middle reaches enough of the floor and a
    quarter point reaches clearly more.  A spot near a corner lets its loops
    out unevenly, so middles win when they are good enough. }
  BestMid := -1;
  for I := 0 to High(Cands) do
    if Cands[I].Middle then BestMid := Max(BestMid, Cands[I].Cov_);
  Quarters := (BestMid < SUGGEST_MIDDLE_ENOUGH) and (BestCover > BestMid + SUGGEST_QUARTER_GAIN);
  { the middles only, weighed by the quick layout }
  if not Quarters then
  begin
    BestCover := -1;
    for I := 0 to High(Cands) do
      if Cands[I].Middle then
      begin
        Cands[I].Cov_ := Cands[I].Quick_;
        BestCover := Max(BestCover, Cands[I].Quick_);
      end;
  end;
  BestD := 1E300; BestL := 0;
  for I := 0 to High(Cands) do
  begin
    if (Cands[I].Cov_ < 0) or (Cands[I].Cov_ < BestCover - 0.01) then Continue;
    if not Cands[I].Middle and not Quarters then Continue;
    if (Cands[I].Dst_ < BestD - 1E-6) or ((Abs(Cands[I].Dst_ - BestD) <= 1E-6) and (Cands[I].WallLen > BestL)) then
    begin
      BestD := Cands[I].Dst_; Best := I; BestL := Cands[I].WallLen;
    end;
  end;
  { nothing laid anywhere: the nearest flat spot }
  if Best < 0 then
    for I := 0 to High(Cands) do
      if (Best < 0) or (Cands[I].Dst_ < Cands[Best].Dst_) then Best := I;
  if Best >= 0 then At := Cands[Best].At_
  else
  begin
    { no flat wall at all: the nearest wall's middle }
    for I := 0 to High(Walls) do
      if (Best < 0) or (Dist(MidWall(Walls[I]), Toward) < Dist(MidWall(Walls[Best]), Toward)) then Best := I;
    if Best < 0 then Exit;
    At := MidWall(Walls[Best]);
  end;
  Ports := Min(RadiantMaxPorts(Spec), Max(MANIFOLD_PORTS_MIN,
    RadiantLoopsNeeded(Zone.Outline, Zone.Holes, Spec) + 1));
end;

function RadiantProblem(const Outline: TP3Array; const Spec: TRadiantSpec): string;
var
  MaxFt: Double;
begin
  Result := '';
  if Length(Outline) < 3 then Exit('The selection has no outline to fill.');
  if Spec.Spacing <= 0 then Exit('The spacing has to read as a size.');
  if (Spec.Spacing < SPACING_MIN_IN * Spec.Inch * 0.5) then
    Exit('That spacing is tighter than any tube can run.');
  if Length(Spec.Manifolds) = 0 then Exit('Place a manifold - or press Suggest.');
  MaxFt := Spec.MaxLoopFt;
  if MaxFt <= 0 then MaxFt := TubeOf(Spec.Tube).MaxLoopFt;
  if MaxFt < 20 then Exit('The maximum loop length has to read as a size.');
  if Spec.SlabThick <= 0 then Exit('The slab thickness has to read as a size.');
end;

{ The frame for one manifold: U along the wall it is nearest, V away from
  that wall into the floor, so the rows run parallel to the manifold's wall. }
function FrameAt(const Outline: TP3Array; const M: TP3): TRadiantFrame;
var
  I, J, Best: Integer;
  D, BestD, BestL, T, L: Double;
  A, B, Q: TP3;
begin
  Result := RadiantFrameOf(Outline);
  BestD := 1E300; Best := 0; BestL := 1E300;
  for I := 0 to High(Outline) do
  begin
    J := (I + 1) mod Length(Outline);
    A := Outline[I]; B := Outline[J];
    L := Sqr(B.X - A.X) + Sqr(B.Y - A.Y) + Sqr(B.Z - A.Z);
    if L < 1E-12 then Continue;
    T := ((M.X - A.X) * (B.X - A.X) + (M.Y - A.Y) * (B.Y - A.Y) + (M.Z - A.Z) * (B.Z - A.Z)) / L;
    T := Max(0, Min(1, T));
    Q := P3(A.X + (B.X - A.X) * T, A.Y + (B.Y - A.Y) * T, A.Z + (B.Z - A.Z) * T);
    D := Dist(M, Q);
    { A manifold in a corner hangs on the SHORTER wall, so the runs go the
      zone's long way: fewer, longer loops, and half the leads along the wall. }
    if (D < BestD - 1E-6) or ((Abs(D - BestD) <= 1E-6) and (L < BestL)) then
    begin
      BestD := D; Best := I; BestL := L;
    end;
  end;
  J := (Best + 1) mod Length(Outline);
  Result.Origin := Outline[Best];
  Result.U := VNorm(P3(Outline[J].X - Outline[Best].X, Outline[J].Y - Outline[Best].Y,
    Outline[J].Z - Outline[Best].Z));
  Result.V := VNorm(Cross3(Result.N, Result.U));
  { V into the floor: the outline's middle is on the positive side }
  A := P3(0, 0, 0);
  for I := 0 to High(Outline) do A := P3(A.X + Outline[I].X / Length(Outline),
    A.Y + Outline[I].Y / Length(Outline), A.Z + Outline[I].Z / Length(Outline));
  if Dot3(P3(A.X - Result.Origin.X, A.Y - Result.Origin.Y, A.Z - Result.Origin.Z), Result.V) < 0 then
  begin
    Result.V := P3(-Result.V.X, -Result.V.Y, -Result.V.Z);
    Result.N := P3(-Result.N.X, -Result.N.Y, -Result.N.Z);
  end;
end;

{ The bends in these loops (points where the tube changes direction), and
  the percent of tube in straights of at least LongFt feet. }
function RadiantBends(const Lps: TRadiantLoopArray; out StraightPct: Double;
  LongFt: Double = 6): Integer;
var
  I, J: Integer;
  A, B, C: TP3;
  Cr, Tot, Long, Run: Double;
begin
  Result := 0; Tot := 0; Long := 0;
  for I := 0 to High(Lps) do
  begin
    Run := 0;
    for J := 1 to High(Lps[I].Pts) do
    begin
      A := Lps[I].Pts[J - 1]; B := Lps[I].Pts[J];
      Run := Run + Dist(A, B);
      Tot := Tot + Dist(A, B);
      { a bend at B when the next segment turns off this one's line }
      if J < High(Lps[I].Pts) then
      begin
        C := Lps[I].Pts[J + 1];
        Cr := Abs((B.X - A.X) * (C.Y - B.Y) - (B.Y - A.Y) * (C.X - B.X)) +
              Abs((B.Y - A.Y) * (C.Z - B.Z) - (B.Z - A.Z) * (C.Y - B.Y)) +
              Abs((B.Z - A.Z) * (C.X - B.X) - (B.X - A.X) * (C.Z - B.Z));
        if Cr > 1E-9 * Max(1, Dist(A, B) * Dist(B, C)) then
        begin
          Inc(Result);
          if Run >= LongFt - 1E-9 then Long := Long + Run;
          Run := 0;
        end;
      end;
    end;
    if Run >= LongFt - 1E-9 then Long := Long + Run;
  end;
  if Tot > 0 then StraightPct := 100 * Long / Tot else StraightPct := 0;
end;

function ComputeRadiantOriented(const Outline: TP3Array; const Holes: array of TP3Array;
  const Spec: TRadiantSpec; WantTrace, Turn: Boolean; FirstBudget: Double; ExtraRanks: Integer;
  BreakFt: Double; Seed: Cardinal; RowOff: Double = 0; Fingers: Boolean = True;
  Quick: Boolean = False; EvenRows: Boolean = False; LoopDelta: Integer = 0;
  ShortFingers: Boolean = False; Fold: Boolean = False; Strip: Boolean = False;
  Wild: Boolean = False; Sweep: PRadiantSweep = nil; Hook: Boolean = False;
  Pairs: Boolean = False): TRadiantResult;
type
  TRun = record A, B: T2; end;
  TRuns = array of TRun;
var
  { with a seed, every loop gets its own share of the limit and a nudged
    first lane guess; the same seed lays the same layout, so the winner can
    be replayed.  Seed 0 is the plain search. }
  RankBudget: array[0..63] of Double;
  RankJit: array[0..63] of Integer;
  RandState: Cardinal;
  { the length every loop is laid toward, 0 for none - see LayManifold }
  TargetFt: Double;
  { the floor left bare, on FloorBare's fixed grid }
  FloorUnf: Double;
  { what RowPlan found: a side's rows odd, and the tightest gap evening them
    brought - see OddRows }
  OddSeen: Boolean;
  Tightest: Double;
  { a side laid with a runt, a strip behind a manifold - see Runts, Strips }
  RuntSeen, StripSeen: Boolean;
  F: TRadiantFrame;
  SwapAxis: TP3;
  Poly2: T2Array;
  HolePoly: array of T2Array;
  I, J, K, MI, NM: Integer;
  Vmin, Vmax, Umin, Umax, Inset, MaxFt, LimLo, LimHi, HLo, HHi, HV0, HV1: Double;
  M2, O2: T2;
  Loops: TRadiantLoopArray;
  { each obstacle's box, an inset bigger all round }
  HoleB: array of T2Array;
  Unfilled: Double;
  Pts: T2Array;
  NPts: Integer;
  { every lane tried for the current manifold, in order; LayManifold resets
    it for each T and keeps a copy for the winner.  Trace is what survives,
    across every manifold this call lays. }
  CurTrace, Trace: TRadiantTrace;
  { the floor's edges and the obstacles', in this manifold's frame, filed
    by the cells of a coarse grid - see EdgeMet }
  EdgA, EdgB: array of T2;
  EdgHead, EdgEnt, EdgNext, EdgSeen: array of Integer;
  EdgN, EdgW, EdgH, EdgStamp: Integer;
  EdgX0, EdgY0, EdgCell: Double;

  function World(const P: T2): TP3;
  begin
    Result := RadiantFrom2(F, P.X, P.Y);
  end;

  function InsidePoly(const Poly: T2Array; const P: T2): Boolean;
  var
    A, B: Integer;
  begin
    Result := False;
    B := High(Poly);
    for A := 0 to High(Poly) do
    begin
      { on the edge counts as in; box test first, since this runs for every
        point of every loop tried }
      if (P.X >= Min(Poly[A].X, Poly[B].X) - 1E-6) and (P.X <= Max(Poly[A].X, Poly[B].X) + 1E-6) and
         (P.Y >= Min(Poly[A].Y, Poly[B].Y) - 1E-6) and (P.Y <= Max(Poly[A].Y, Poly[B].Y) + 1E-6) and
         SegsMeet(P, P, Poly[A], Poly[B]) then Exit(True);
      if ((Poly[A].Y > P.Y) <> (Poly[B].Y > P.Y)) and
        (P.X < (Poly[B].X - Poly[A].X) * (P.Y - Poly[A].Y) /
          (Poly[B].Y - Poly[A].Y) + Poly[A].X) then Result := not Result;
      B := A;
    end;
  end;

  { the cells the box round P-Q covers, clamped to the grid - written out,
    since it runs tens of millions of times a search }
  procedure EdgeCells(const P, Q: T2; out X0, Y0, X1, Y1: Integer);
  var
    A, B: Double;
  begin
    if P.X < Q.X then begin A := P.X; B := Q.X; end else begin A := Q.X; B := P.X; end;
    X0 := Trunc((A - 1E-6 - EdgX0) / EdgCell); X1 := Trunc((B + 1E-6 - EdgX0) / EdgCell);
    if P.Y < Q.Y then begin A := P.Y; B := Q.Y; end else begin A := Q.Y; B := P.Y; end;
    Y0 := Trunc((A - 1E-6 - EdgY0) / EdgCell); Y1 := Trunc((B + 1E-6 - EdgY0) / EdgCell);
    if X0 < 0 then X0 := 0 else if X0 > EdgW - 1 then X0 := EdgW - 1;
    if X1 < 0 then X1 := 0 else if X1 > EdgW - 1 then X1 := EdgW - 1;
    if Y0 < 0 then Y0 := 0 else if Y0 > EdgH - 1 then Y0 := EdgH - 1;
    if Y1 < 0 then Y1 := 0 else if Y1 > EdgH - 1 then Y1 := EdgH - 1;
  end;

  { Every edge of the floor and the obstacles, filed once per manifold so a
    candidate loop is tested only against the edges near it. }
  procedure FileEdges;
  var
    P, K, N_, X, Y, X0, X1, Y0, Y1, E: Integer;

    procedure Add(const A, B: T2);
    begin
      EdgA[N_] := A; EdgB[N_] := B; Inc(N_);
    end;

  begin
    N_ := Length(Poly2);
    for P := 0 to High(HolePoly) do Inc(N_, Length(HolePoly[P]));
    SetLength(EdgA, N_); SetLength(EdgB, N_);
    N_ := 0;
    for K := 0 to High(Poly2) do Add(Poly2[K], Poly2[(K + 1) mod Length(Poly2)]);
    for P := 0 to High(HolePoly) do
      for K := 0 to High(HolePoly[P]) do Add(HolePoly[P][K], HolePoly[P][(K + 1) mod Length(HolePoly[P])]);
    EdgN := N_;
    EdgCell := Max(Spec.Spacing * 2, Max(Umax - Umin, Vmax - Vmin) / 48);
    EdgX0 := Umin - EdgCell; EdgY0 := Vmin - EdgCell;
    EdgW := Trunc((Umax - Umin) / EdgCell) + 3; EdgH := Trunc((Vmax - Vmin) / EdgCell) + 3;
    SetLength(EdgHead, EdgW * EdgH);
    for K := 0 to High(EdgHead) do EdgHead[K] := -1;
    SetLength(EdgEnt, 0); SetLength(EdgNext, 0);
    E := 0;
    for K := 0 to EdgN - 1 do
    begin
      EdgeCells(EdgA[K], EdgB[K], X0, Y0, X1, Y1);
      for Y := Y0 to Y1 do
        for X := X0 to X1 do
        begin
          if E >= Length(EdgEnt) then
          begin
            SetLength(EdgEnt, E * 2 + 64); SetLength(EdgNext, E * 2 + 64);
          end;
          EdgEnt[E] := K;
          EdgNext[E] := EdgHead[Y * EdgW + X];
          EdgHead[Y * EdgW + X] := E;
          Inc(E);
        end;
    end;
    SetLength(EdgSeen, EdgN);
    for K := 0 to EdgN - 1 do EdgSeen[K] := 0;
    EdgStamp := 0;
  end;

  { does P0-P1 cross or touch an edge of the floor or of an obstacle? }
  function EdgeMet(const P0, P1: T2): Boolean;
  var
    X, Y, X0, X1, Y0, Y1, E, K: Integer;
    Q0, Q1: T2;
  begin
    Result := False;
    Inc(EdgStamp);
    EdgeCells(P0, P1, X0, Y0, X1, Y1);
    for Y := Y0 to Y1 do
      for X := X0 to X1 do
      begin
        E := EdgHead[Y * EdgW + X];
        while E >= 0 do
        begin
          K := EdgEnt[E];
          E := EdgNext[E];
          if EdgSeen[K] = EdgStamp then Continue;
          EdgSeen[K] := EdgStamp;
          Q0 := EdgA[K]; Q1 := EdgB[K];
          if (Max(P0.X, P1.X) < Min(Q0.X, Q1.X) - 1E-6) or (Min(P0.X, P1.X) > Max(Q0.X, Q1.X) + 1E-6) or
             (Max(P0.Y, P1.Y) < Min(Q0.Y, Q1.Y) - 1E-6) or (Min(P0.Y, P1.Y) > Max(Q0.Y, Q1.Y) + 1E-6) then Continue;
          if SegsMeet(P0, P1, Q0, Q1) then Exit(True);
        end;
      end;
  end;

  procedure Put(X, Y: Double);
  begin
    if (NPts > 0) and (Abs(Pts[NPts - 1].X - X) < 1E-9) and (Abs(Pts[NPts - 1].Y - Y) < 1E-9) then Exit;
    if NPts >= Length(Pts) then SetLength(Pts, NPts * 2 + 16);
    Pts[NPts] := Point2(X, Y); Inc(NPts);
  end;

  { A row's pieces on this side: the near piece, from the manifold to the
    far end or the first obstacle, and the far piece, from the last
    obstacle to the far end.  In D (distance from the manifold) so both
    sides read the same.  Floor spans are pulled in an inset at their ends;
    obstacle boxes are already that much bigger. }
  procedure RowBounds(V: Double; out Outer, Cuts: TSpanArray);
  var
    P, Q, K, K0: Integer;
    HoleRow: TSpanArray;
    T: TSpan;
  begin
    { an obstacle cuts the row where its outline does, an inset wider each
      way, and where it does within an inset above or below - sampled, so a
      round one stays round, not its box }
    Cuts := nil;
    for P := 0 to High(HolePoly) do
      for K := -2 to 2 do
      begin
        HoleRow := RowSpans(HolePoly[P], V + K * Inset / 2);
        K0 := Length(Cuts);
        SetLength(Cuts, K0 + Length(HoleRow));
        for Q := 0 to High(HoleRow) do
        begin
          Cuts[K0 + Q].Lo := HoleRow[Q].Lo - Inset;
          Cuts[K0 + Q].Hi := HoleRow[Q].Hi + Inset;
        end;
      end;
    for P := 1 to High(Cuts) do
    begin
      T := Cuts[P]; K := P;
      while (K > 0) and (Cuts[K - 1].Lo > T.Lo) do begin Cuts[K] := Cuts[K - 1]; Dec(K); end;
      Cuts[K] := T;
    end;
    { and overlapping cuts made one, so a piece's edge is a real edge }
    K := 0;
    for P := 1 to High(Cuts) do
      if Cuts[P].Lo <= Cuts[K].Hi + 1E-9 then Cuts[K].Hi := Max(Cuts[K].Hi, Cuts[P].Hi)
      else begin Inc(K); Cuts[K] := Cuts[P]; end;
    if Length(Cuts) > 0 then SetLength(Cuts, K + 1);
    Outer := RowSpans(Poly2, V);
    for P := 0 to High(Outer) do
    begin
      Outer[P].Lo := Outer[P].Lo + Inset; Outer[P].Hi := Outer[P].Hi - Inset;
    end;
  end;

  procedure RowPieces(V: Double; Sign: Integer; out EdgeD, NearLo, NearHi, FarLo, FarHi: Double;
    out HasNear, HasFar: Boolean);
  var
    Pieces, Cuts, Outer: TSpanArray;
    P, Q, K: Integer;
    Lo, Hi, StartU: Double;
    CutEdge, First: Boolean;
  begin
    HasNear := False; HasFar := False;
    NearLo := 0; NearHi := 0; FarLo := 0; FarHi := 0; EdgeD := 1E300;
    RowBounds(V, Outer, Cuts);
    { where the floor's own edge is on this side, obstacles or not: the
      first outer span on this side, or the one the manifold is in }
    for P := 0 to High(Outer) do
    begin
      if Sign > 0 then begin Lo := Outer[P].Lo - M2.X; Hi := Outer[P].Hi - M2.X; end
      else begin Lo := M2.X - Outer[P].Hi; Hi := M2.X - Outer[P].Lo; end;
      if Hi <= 0 then Continue;
      EdgeD := Min(EdgeD, Max(0, Lo));
    end;
    Pieces := Subtract(Outer, Cuts);
    { in D: the near piece is the first on this side when it starts at the
      floor's edge (a slanting wall can put that a way out), not past an
      obstacle; the far piece is the last one, when it starts past an
      obstacle }
    First := True;
    for K := 0 to High(Pieces) do
    begin
      { in order of distance from the manifold, which is backwards along U on
        the far side }
      if Sign > 0 then P := K else P := High(Pieces) - K;
      if Sign > 0 then begin Lo := Pieces[P].Lo - M2.X; Hi := Pieces[P].Hi - M2.X; StartU := Pieces[P].Lo; end
      else begin Lo := M2.X - Pieces[P].Hi; Hi := M2.X - Pieces[P].Lo; StartU := Pieces[P].Hi; end;
      if Hi <= Spec.Spacing then Continue;
      CutEdge := False;
      for Q := 0 to High(Cuts) do
        if (Abs(Cuts[Q].Hi - StartU) < 1E-6) or (Abs(Cuts[Q].Lo - StartU) < 1E-6) then CutEdge := True;
      if First and not CutEdge then
      begin
        NearLo := Max(0, Lo); NearHi := Hi;
        HasNear := True;
      end
      else if CutEdge then
      begin
        FarLo := Lo; FarHi := Hi;
        HasFar := FarHi - FarLo > Spec.Spacing;
      end;
      First := False;
    end;
  end;

  { the runs of some loops in this frame, for RowBareRuns - worked out once
    for all the rows asked about }
  function RunsOf(const Lps: TRadiantLoopArray): TRuns;
  var
    Li, Si, N_: Integer;
  begin
    N_ := 0;
    for Li := 0 to High(Lps) do Inc(N_, Max(0, Length(Lps[Li].Pts) - 1));
    SetLength(Result, N_);
    N_ := 0;
    for Li := 0 to High(Lps) do
      for Si := 1 to High(Lps[Li].Pts) do
      begin
        Result[N_].A := RadiantTo2(F, Lps[Li].Pts[Si - 1]);
        Result[N_].B := RadiantTo2(F, Lps[Li].Pts[Si]);
        Inc(N_);
      end;
  end;

  { How much of row V between ULo and UHi no tube in Runs heats: the floor's
    pieces on that row, less half a spacing either side of every run along
    or across it.  Measures what was laid, so a short pass does not claim
    the rest of its row. }
  function RowBareRuns(V, ULo, UHi: Double; const Runs: TRuns): Double;
  var
    Si, Pn: Integer;
    A, B: T2;
    Available, Covered, Left, Outer, Cuts: TSpanArray;
    X0, X1, T0, T1, Dy, HalfPitch: Double;
  begin
    Result := 0;
    HalfPitch := Spec.Spacing / 2;
    RowBounds(V, Outer, Cuts);
    Available := Subtract(Outer, Cuts);
    Left := nil;
    for Pn := 0 to High(Available) do
    begin
      X0 := Max(Available[Pn].Lo, ULo); X1 := Min(Available[Pn].Hi, UHi);
      if X1 <= X0 then Continue;
      Si := Length(Left); SetLength(Left, Si + 1);
      Left[Si].Lo := X0; Left[Si].Hi := X1;
    end;
    SetLength(Covered, 1);
    for Si := 0 to High(Runs) do
    begin
      if Length(Left) = 0 then Break;
      A := Runs[Si].A;
      B := Runs[Si].B;
      Dy := B.Y - A.Y;
      if Abs(Dy) < 1E-9 then
      begin
        if Abs(A.Y - V) > HalfPitch + 1E-6 then Continue;
        X0 := A.X; X1 := B.X;
      end
      else
      begin
        T0 := (V - HalfPitch - A.Y) / Dy;
        T1 := (V + HalfPitch - A.Y) / Dy;
        if T0 > T1 then begin X0 := T0; T0 := T1; T1 := X0; end;
        T0 := Max(0, T0); T1 := Min(1, T1);
        if T0 > T1 then Continue;
        X0 := A.X + T0 * (B.X - A.X);
        X1 := A.X + T1 * (B.X - A.X);
      end;
      Covered[0].Lo := Min(X0, X1) - HalfPitch;
      Covered[0].Hi := Max(X0, X1) + HalfPitch;
      Left := Subtract(Left, Covered);
    end;
    for Pn := 0 to High(Left) do
      Result := Result + (Left[Pn].Hi - Left[Pn].Lo) * Spec.Spacing;
  end;

  { The rows of one direction, as distances from the manifold's row: a
    spacing apart, an inset off each end.  An odd count leaves a bare strip
    at the far wall, so with EvenRows add a row as cheaply as possible:
    EVEN_EDGE_IN off the far wall, then the far gaps (EVEN_GAP_SHARE each),
    at most half a spacing a gap.  The first gap stays: breakout tracks run there. }
  function RowPlan(VDir: Integer): TDoubleArray;
  var
    A, B, L, Short, Cut: Double;
    N, K, Gaps, Squeezed: Integer;
  begin
    Result := nil;
    A := Inset + RowOff * Spec.Spacing;
    if VDir > 0 then B := Vmax - Inset - M2.Y else B := M2.Y - (Vmin + Inset);
    L := B - A;
    if L < -1E-9 then Exit;
    N := Trunc(L / Spec.Spacing + 1E-9) + 1;
    Squeezed := -1;
    if N mod 2 = 1 then OddSeen := True;
    if EvenRows and (N mod 2 = 1) then
    begin
      { N rows and one more make N gaps: Short is what the band lacks at the
        spacing, less what the far wall gives up }
      Short := Max(0, N * Spec.Spacing - L - EVEN_EDGE_IN * Spec.Inch);
      { the far gaps give up the rest - never the first, when there is
        another }
      Gaps := Max(1, N - 1);
      Squeezed := 0;
      if Short > 1E-9 then Squeezed := Min(Gaps, Ceil(Short / (EVEN_GAP_SHARE * Spec.Spacing) - 1E-9));
      Cut := 0;
      if Squeezed > 0 then Cut := Short / Squeezed;
      if Cut > Spec.Spacing / 2 + 1E-9 then Squeezed := -1;
    end;
    if Squeezed < 0 then
    begin
      SetLength(Result, N);
      for K := 0 to N - 1 do Result[K] := A + K * Spec.Spacing;
      Exit;
    end;
    SetLength(Result, N + 1);
    Result[0] := A;
    for K := 1 to N do
      if K > N - Squeezed then Result[K] := Result[K - 1] + Spec.Spacing - Cut
      else Result[K] := Result[K - 1] + Spec.Spacing;
    Tightest := Min(Tightest, Spec.Spacing - Cut);
  end;

  { Lay one side of the manifold: the game of snake.  VDir is +1 the usual
    way, -1 back toward the wall for a manifold off it.  A loop leaves its
    port, runs out its first row, turns into the next and back, as many
    pairs as Limit allows, and comes home.  Each lane is grown and checked
    against tube already down, never assumed. }
  { Behind, when not 0, is that many (odd) of the other direction's nearest
    rows, taken into this side first, farthest first: a strip behind the
    manifold too small for its own loop. }
  procedure LaySide(SideK, VDir: Integer; PortOff: Double; Limit: Double; Behind: Integer;
    var Got: TRadiantLoopArray; var Unf: Double; out NLOut: Integer);
  type
    TPlan = record
      Rows: array of Integer;      { the rows, in walking order }
      Far: array of Boolean;       { the far piece of that row, not the near }
      Cut: array of Double;        { a near piece stopped short, here; 0 for the whole }
      LaneD: Double;               { where its lane was found - CurD when it was kept }
    end;
  var
    C, N, Q, EstGuess: Integer;
    Plan, BackPlan: TDoubleArray;
    V, PortPitch, BreakD, EdgeD, CurD, AvgReach: Double;
    RowV, NLo, NHi, FLo, FHi, EdgeMax: array of Double;
    HasN, HasF, UsedN, UsedF, DeadN: array of Boolean;
    Plans: array of TPlan;
    GotFrom: Integer;
    { while Compact re-lays: the tube's maximum is the limit, and no lane
      tried goes into the replay }
    Compacting: Boolean;
    Sign: Integer;
    { the index of tube already down - see BuildIndex }
    IdxA, IdxB: array of T2;
    IdxN, NEnt, GW, GH, SeenStamp: Integer;
    { how many of Got's loops the index holds; -1 for none yet }
    IdxGot: Integer;
    { LayPts' rows' ends, kept from one loop tried to the next }
    Lo, Hi: array of Double;
    { the lanes LaneClear worked out lately, and for each the first of this
      side's rows with no floor there; -1 for an empty slot }
    ClearD: array[0..7] of Double;
    ClearAt: array[0..7] of Integer;
    ClearNext: Integer;
    CellHead, EntSeg, EntNext, SegSeen: array of Integer;
    GX0, GY0, GCell: Double;

    { where the loop of rank R (0 nearest the manifold's row) leaves and comes
      home, as distance along this side: the home port inside, the out port
      beside it.  PortOff moves the set past the ports the other direction
      already used. }
    function PortHome(R: Integer): Double;
    begin
      { ports must fall the same way and pace as the lanes' starting guess:
        a port counting up while its lane counts down crosses the fans in a
        way no lane position can fix.  A wrong count leaves a rank unplaced,
        never sharing a port. }
      Result := (2 * Max(0, EstGuess - 1 - R) + 1) * PortPitch + PortOff;
    end;

    function PortOut(R: Integer): Double;
    begin
      Result := PortHome(R) + PortPitch;
    end;

    { the lane the loop being tried takes up to its rows: whatever the search
      is currently trying (CurD) }
    function LaneHome(R: Integer): Double;
    begin
      Result := CurD - Spec.Spacing;
    end;

    function LaneOut(R: Integer): Double;
    begin
      Result := CurD;
    end;

    function AtD(D: Double): Double;   { back to U }
    begin
      Result := M2.X + Sign * D;
    end;

    { The breakout, square: out of the port, along the manifold to the lane,
      up the lane - no diagonal fan.  Each tube has its own track a port
      pitch apart, the farthest lane on the lowest, so no track crosses a
      lane or port: rank R's out tube below its home tube, rank R below
      R + 1.  Signed by the direction this side runs. }
    function JogHt(R, Home: Integer): Double;
    begin
      Result := VDir * (2 * R + Home + 1) * PortPitch;
    end;

    { the loop as laid, in this frame, into Pts: out of its port to its first
      row, the rows, home down its other port, every turn leveled }
    procedure LayPts(const Pl: TPlan; R: Integer);
    var
      J, Rr: Integer;
      D0, D1: Double;
      Back: Boolean;
    begin
      NPts := 0;
      { out of the port square, along its track to the lane, up the lane }
      Put(AtD(PortOut(R)), M2.Y);
      Put(AtD(PortOut(R)), M2.Y + JogHt(R, 0));
      Put(AtD(LaneOut(R)), M2.Y + JogHt(R, 0));
      { each row's near and far end, then every turn leveled: going out, two
        rows turn at the nearer of their far ends, coming back at the farther
        of their near ends.  A near piece starts at the out lane (the last at
        the home lane); a far piece past its obstacle, or at the out lane if
        the obstacle is nearer the manifold than that. }
      if Length(Lo) < Length(Pl.Rows) then begin SetLength(Lo, Length(Pl.Rows) * 2); SetLength(Hi, Length(Pl.Rows) * 2); end;
      for J := 0 to High(Pl.Rows) do
      begin
        Rr := Pl.Rows[J];
        if Pl.Far[J] then begin Lo[J] := Max(FLo[Rr], LaneOut(R)); Hi[J] := FHi[Rr]; end
        else begin Lo[J] := Max(LaneOut(R), NLo[Rr]); Hi[J] := NHi[Rr]; end;
        { a row from behind the manifold that the out lane crosses on its
          way up to the farthest begins a spacing past it }
        if (Rr < Behind) and (Rr > Pl.Rows[0]) then Lo[J] := Max(Lo[J], LaneOut(R) + Spec.Spacing);
        if Pl.Cut[J] > 0 then Hi[J] := Min(Hi[J], Pl.Cut[J]);
      end;
      Lo[High(Pl.Rows)] := Max(LaneHome(R), NLo[Pl.Rows[High(Pl.Rows)]]);
      Back := False;
      for J := 0 to High(Pl.Rows) - 1 do
      begin
        if not Back then begin Hi[J] := Min(Hi[J], Hi[J + 1]); Hi[J + 1] := Hi[J]; end
        else begin Lo[J] := Max(Lo[J], Lo[J + 1]); Lo[J + 1] := Lo[J]; end;
        Back := not Back;
      end;
      Back := False;   { the first row is walked out, away from the manifold }
      for J := 0 to High(Pl.Rows) do
      begin
        Rr := Pl.Rows[J];
        if Back then begin D0 := Hi[J]; D1 := Lo[J]; end else begin D0 := Lo[J]; D1 := Hi[J]; end;
        Put(AtD(D0), RowV[Rr]);
        Put(AtD(D1), RowV[Rr]);
        Back := not Back;
      end;
      Put(AtD(LaneHome(R)), M2.Y + JogHt(R, 1));
      Put(AtD(PortHome(R)), M2.Y + JogHt(R, 1));
      Put(AtD(PortHome(R)), M2.Y);
    end;

    { the loop's length: every run is square to the frame, so it is the sum
      of the steps.  Cheaper than laying it out in the world each time. }
    function PlanLen(const Pl: TPlan; R: Integer): Double;
    var
      J: Integer;
    begin
      LayPts(Pl, R);
      Result := 0;
      for J := 1 to NPts - 1 do
        Result := Result + Abs(Pts[J].X - Pts[J - 1].X) + Abs(Pts[J].Y - Pts[J - 1].Y);
    end;

    { the loop as laid, in the world; its length the result }
    function LayPlan(const Pl: TPlan; R: Integer; out L: TRadiantLoop): Double;
    var
      J: Integer;
    begin
      LayPts(Pl, R);
      L.Couple := 0;
      SetLength(L.Pts, NPts);
      for J := 0 to NPts - 1 do L.Pts[J] := World(Pts[J]);
      L.LenFt := 0;
      for J := 1 to High(L.Pts) do L.LenFt := L.LenFt + Dist(L.Pts[J - 1], L.Pts[J]);
      Result := L.LenFt;
    end;

    { does row Rr have a piece of floor at D? }
    function RowHas(Rr: Integer; D: Double): Boolean;
    begin
      Result := (HasN[Rr] and (D >= NLo[Rr] - 1E-6) and (D <= NHi[Rr] + 1E-6)) or
                (HasF[Rr] and (D >= FLo[Rr] - 1E-6) and (D <= FHi[Rr] + 1E-6));
    end;

    function LaneClear(D: Double; UpTo: Integer): Boolean;
    var
      Rr, K: Integer;
    begin
      Result := True;
      { rows from behind the manifold are laid farthest first, so the ones
        after it are below it }
      if UpTo < Behind then
      begin
        for Rr := UpTo + 1 to Behind - 1 do
          if not RowHas(Rr, D) then Exit(False);
        Exit;
      end;
      { this side's own rows: clear below UpTo when the first row without
        floor at D is not below it.  The rows don't change while the side
        is laid, so this is cached per lane. }
      for K := 0 to High(ClearD) do
        if (ClearAt[K] >= 0) and (ClearD[K] = D) then Exit(ClearAt[K] >= UpTo);
      Rr := Behind;
      while (Rr < Length(RowV)) and RowHas(Rr, D) do Inc(Rr);
      K := ClearNext;
      ClearNext := (ClearNext + 1) mod Length(ClearD);
      ClearD[K] := D; ClearAt[K] := Rr;
      Result := Rr >= UpTo;
    end;

    { the breakout runs below the first row, so no row check covers it:
      both legs (out of the port, along to the lane) are tested against
      every obstacle's box directly }
    function JogClear(DPort, DLane, H: Double): Boolean;
    var
      A, B, C3: T2;
      I3, K3: Integer;
    begin
      A := Point2(AtD(DPort), M2.Y); B := Point2(AtD(DPort), M2.Y + H);
      C3 := Point2(AtD(DLane), M2.Y + H);
      Result := True;
      for I3 := 0 to High(HoleB) do
        for K3 := 0 to 3 do
          if SegsMeet(A, B, HoleB[I3][K3], HoleB[I3][(K3 + 1) mod 4]) or
             SegsMeet(B, C3, HoleB[I3][K3], HoleB[I3][(K3 + 1) mod 4]) then Exit(False);
    end;

    { under the limit, both lanes inside the floor and clear of obstacles
      up to their rows, both breakouts clear of obstacles, and both lanes
      starting inside the breakout }
    function Fits(const Pl: TPlan; R: Integer): Boolean;
    begin
      Result := (LaneOut(R) <= BreakD + 1E-6) and
                (EdgeMax[Pl.Rows[0]] <= LaneOut(R) + 1E-6) and
                (EdgeMax[Pl.Rows[High(Pl.Rows)]] <= LaneHome(R) + 1E-6) and
                LaneClear(LaneOut(R), Pl.Rows[0]) and LaneClear(LaneHome(R), Pl.Rows[High(Pl.Rows)]) and
                JogClear(PortOut(R), LaneOut(R), JogHt(R, 0)) and
                JogClear(PortHome(R), LaneHome(R), JogHt(R, 1)) and
                (PlanLen(Pl, R) <= IfThen(Compacting, MaxFt,
                  IfThen(R = 0, Limit * FirstBudget, Limit) * RankBudget[Min(R, 63)]));
    end;

    { is there a run's worth of this piece beyond the loop's port? }
    function NearOk(C, R: Integer): Boolean;
    begin
      Result := (C >= 0) and (C <= High(RowV)) and HasN[C] and not UsedN[C] and not DeadN[C] and
        (NHi[C] - Max(LaneOut(R), NLo[C]) >= Spec.Spacing - 1E-6);
    end;

    function FarOk(C, R: Integer): Boolean;
    begin
      Result := (C >= 0) and (C <= High(RowV)) and HasF[C] and not UsedF[C] and
        (FHi[C] - Max(FLo[C], LaneOut(R)) >= Spec.Spacing - 1E-6);
    end;

    function Clear(C: Integer): Boolean;   { a near piece to the far end }
    begin
      Result := (C >= 0) and (C <= High(RowV)) and HasN[C] and not HasF[C];
    end;

    procedure Add(var Pl: TPlan; C: Integer; IsFar: Boolean; CutAt: Double = 0);
    begin
      SetLength(Pl.Rows, Length(Pl.Rows) + 1); SetLength(Pl.Far, Length(Pl.Far) + 1);
      SetLength(Pl.Cut, Length(Pl.Cut) + 1);
      Pl.Rows[High(Pl.Rows)] := C; Pl.Far[High(Pl.Far)] := IsFar; Pl.Cut[High(Pl.Cut)] := CutAt;
    end;

    procedure Trim(var Pl: TPlan; N: Integer);
    begin
      SetLength(Pl.Rows, N); SetLength(Pl.Far, N); SetLength(Pl.Cut, N);
    end;

    { a clear row with an obstacle's far side just past it is the way
      out to those far pieces: no loop may end on it }
    function Reserved(C: Integer): Boolean;
    begin
      Result := Clear(C) and (C + 1 <= High(RowV)) and HasF[C + 1] and not UsedF[C + 1];
    end;

    { The excursion round an obstacle from row Cc (last in Pl, walked out):
      the far pieces beside it, then home on the clear row past them (or the
      next, when an odd count leaves that row walked out), with an even
      number of near pieces under the obstacle.  Too long, and far pieces
      come off from the near end, with the near pieces under them. }
    function Excursion(Cc, R: Integer; var Pl: TPlan): Boolean;
    var
      First, Home, M, J, Q, NearN, Was: Integer;
      Trial: TPlan;
    begin
      Result := False;
      First := Cc + 1;
      M := 0;
      while FarOk(First + M, R) do Inc(M);
      if M < 1 then Exit;
      Home := First + M;
      if not NearOk(Home, R) or not Clear(Home) then Exit;
      J := M;
      while J >= 1 do
      begin
        Trial := Pl;
        for Q := Home - J to Home - 1 do Add(Trial, Q, True);
        Add(Trial, Home, False);
        NearN := J;
        Was := Length(Trial.Rows);
        if J mod 2 = 1 then
        begin
          { the home row was walked out from the obstacle: home on the one
            after, and the home row's near part (up to the obstacle) joins
            the near pieces, making their count even }
          if not NearOk(Home + 1, R) or not Clear(Home + 1) then Exit;
          Add(Trial, Home + 1, False);
          Was := Length(Trial.Rows);
          Add(Trial, Home, False, FLo[Home - 1]);
          NearN := J + 1;
        end;
        { the near pieces under the far pieces taken: all or none, since an
          odd few could not come home }
        for Q := Home - 1 downto Home - J do
          if NearOk(Q, R) then Add(Trial, Q, False) else Break;
        if Length(Trial.Rows) - Was < NearN then Trim(Trial, Was);
        if Fits(Trial, R) then
        begin
          Pl := Trial;
          for Q := First to Home - 1 do
            if HasN[Q] and not UsedN[Q] then
            begin
              Was := 0;
              for NearN := 0 to High(Trial.Rows) do
                if (Trial.Rows[NearN] = Q) and not Trial.Far[NearN] then Was := 1;
              if Was = 0 then DeadN[Q] := True;
            end;
          Exit(True);
        end;
        Dec(J);
      end;
    end;

    { Laid to a length, not a limit (see LayManifold): a pair of rows that
      would take the loop further past the target than it now falls short
      is not taken, so the loop stops nearest the target.  To a limit,
      every loop but the last is as long as it can be. }
    function PastTarget(const Now_, Next: TPlan; R: Integer): Boolean;
    var
      A, B, Tg: Double;
    begin
      Result := False;
      if TargetFt <= 0 then Exit;
      { Laid in hooked pairs (Pairs), the second loop of a pair aims at what
        brings the two to twice the length; the hook between them
        (HookLoops) evens out the fraction whole pairs of rows cannot.  The
        first of the pair is the loop laid just before. }
      Tg := TargetFt;
      if Pairs and (R mod 2 = 1) and (R = Length(Plans)) and (Length(Got) > GotFrom) then
        Tg := Max(TargetFt / 2, 2 * TargetFt - Got[High(Got)].LenFt);
      A := PlanLen(Now_, R);
      B := PlanLen(Next, R);
      Result := (B > Tg) and (B - Tg > Tg - A);
    end;

    { the plan of the loop of rank R from row C: out on C; then the
      excursion round an obstacle, or pairs of near pieces, as many as
      fit under Limit }
    function PlanFrom(C, R: Integer; out Pl: TPlan): Boolean;
    var
      Cc: Integer;
      Trial: TPlan;
    begin
      Result := False;
      Trim(Pl, 0);
      if not NearOk(C, R) then
      begin
        { nothing here to walk out from: an obstacle right at the
          manifold's column blocks every near piece for a run of rows.  Its
          far piece is reached the way an excursion reaches one met partway
          out a row - starting there instead of arriving there. }
        if FarOk(C, R) then Result := Excursion(C - 1, R, Pl);
        Exit;
      end;
      Add(Pl, C, False);
      Cc := C;
      repeat
        if Cc + 1 > High(RowV) then Break;
        if Length(Pl.Rows) mod 2 = 1 then
        begin
          { on a row walked out: round an obstacle, or the next row back }
          if Clear(Cc) and Excursion(Cc, R, Pl) then begin Result := True; Break; end;
          if NearOk(Cc + 1, R) and not Reserved(Cc + 1) then
          begin
            Trial := Pl;
            Add(Trial, Cc + 1, False);
            if Fits(Trial, R) then
            begin
              Pl := Trial; Cc := Cc + 1; Result := True;
              Continue;
            end;
          end;
          Break;
        end
        else
        begin
          { on a row walked back: out again on the next, if it is the
            way out round an obstacle or the pair after it fits }
          if Reserved(Cc + 1) and NearOk(Cc + 1, R) then
          begin
            Trial := Pl;
            Add(Trial, Cc + 1, False);
            if Excursion(Cc + 1, R, Trial) then begin Pl := Trial; Result := True; end;
            Break;
          end;
          if NearOk(Cc + 1, R) and NearOk(Cc + 2, R) and not Reserved(Cc + 2) then
          begin
            Trial := Pl;
            Add(Trial, Cc + 1, False);
            Add(Trial, Cc + 2, False);
            if Fits(Trial, R) and not PastTarget(Pl, Trial, R) then
            begin
              Pl := Trial; Cc := Cc + 2;
              Continue;
            end;
          end;
          Break;
        end;
      until False;
      { an odd number of rows cannot come home: drop the last }
      if Result and (Length(Pl.Rows) mod 2 = 1) then
      begin
        Trim(Pl, Length(Pl.Rows) - 1);
        Result := Length(Pl.Rows) >= 2;
      end;
    end;

    { the cells the box round P-Q covers, clamped to the grid }
    procedure CellsOf(const P, Q: T2; out X0, Y0, X1, Y1: Integer);
    var
      A, B: Double;
    begin
      if P.X < Q.X then begin A := P.X; B := Q.X; end else begin A := Q.X; B := P.X; end;
      X0 := Trunc((A - 1E-6 - GX0) / GCell); X1 := Trunc((B + 1E-6 - GX0) / GCell);
      if P.Y < Q.Y then begin A := P.Y; B := Q.Y; end else begin A := Q.Y; B := P.Y; end;
      Y0 := Trunc((A - 1E-6 - GY0) / GCell); Y1 := Trunc((B + 1E-6 - GY0) / GCell);
      if X0 < 0 then X0 := 0 else if X0 > GW - 1 then X0 := GW - 1;
      if X1 < 0 then X1 := 0 else if X1 > GW - 1 then X1 := GW - 1;
      if Y0 < 0 then Y0 := 0 else if Y0 > GH - 1 then Y0 := GH - 1;
      if Y1 < 0 then Y1 := 0 else if Y1 > GH - 1 then Y1 := GH - 1;
    end;

    { Every run of tube already down, this side's and earlier manifolds',
      in this frame and filed by the cells of a coarse grid, so a candidate
      is tested only against runs near it.  Built once per loop placed,
      since nothing is laid while its lanes are tried.  Only loops added to
      Got since last time are filed, while Got has only grown. }
    procedure BuildIndex;
    var
      A4, I4, N4, X, Y, X0, X1, Y0, Y1, From: Integer;
      P: TP3Array;
    begin
      if (IdxGot < 0) or (IdxGot > Length(Got)) then
      begin
        IdxN := 0;
        GCell := Max(Spec.Spacing * 2, Max(Umax - Umin, Vmax - Vmin) / 48);
        GX0 := Umin - GCell; GY0 := Vmin - GCell;
        GW := Trunc((Umax - Umin) / GCell) + 3; GH := Trunc((Vmax - Vmin) / GCell) + 3;
        SetLength(CellHead, GW * GH);
        for I4 := 0 to High(CellHead) do CellHead[I4] := -1;
        NEnt := 0;
        SeenStamp := 0;
        { the earlier manifolds' tube first, then all of this one's }
        From := IdxN;
        N4 := 0;
        for A4 := 0 to High(Loops) do Inc(N4, Length(Loops[A4].Pts));
        for A4 := 0 to High(Got) do Inc(N4, Length(Got[A4].Pts));
        SetLength(IdxA, N4); SetLength(IdxB, N4);
        for A4 := 0 to High(Loops) do
        begin
          P := Loops[A4].Pts;
          for I4 := 1 to High(P) do
          begin
            IdxA[IdxN] := RadiantTo2(F, P[I4 - 1]);
            IdxB[IdxN] := RadiantTo2(F, P[I4]);
            Inc(IdxN);
          end;
        end;
        A4 := 0;
      end
      else
      begin
        From := IdxN;
        A4 := IdxGot;
      end;
      N4 := IdxN;
      for I4 := A4 to High(Got) do Inc(N4, Length(Got[I4].Pts));
      if N4 > Length(IdxA) then begin SetLength(IdxA, N4); SetLength(IdxB, N4); end;
      for A4 := A4 to High(Got) do
      begin
        P := Got[A4].Pts;
        for I4 := 1 to High(P) do
        begin
          IdxA[IdxN] := RadiantTo2(F, P[I4 - 1]);
          IdxB[IdxN] := RadiantTo2(F, P[I4]);
          Inc(IdxN);
        end;
      end;
      IdxGot := Length(Got);
      if Length(SegSeen) < IdxN then SetLength(SegSeen, IdxN);
      for I4 := From to IdxN - 1 do
      begin
        SegSeen[I4] := 0;
        CellsOf(IdxA[I4], IdxB[I4], X0, Y0, X1, Y1);
        for Y := Y0 to Y1 do
          for X := X0 to X1 do
          begin
            if NEnt >= Length(EntSeg) then
            begin
              SetLength(EntSeg, NEnt * 2 + 64); SetLength(EntNext, NEnt * 2 + 64);
            end;
            EntSeg[NEnt] := I4;
            EntNext[NEnt] := CellHead[Y * GW + X];
            CellHead[Y * GW + X] := NEnt;
            Inc(NEnt);
          end;
      end;
    end;

    { does P-Q meet any run of tube in the index? }
    function MeetsIndexed(const P0, P1: T2): Boolean;
    var
      X, Y, X0, X1, Y0, Y1, E, G4: Integer;
      Q0, Q1: T2;
    begin
      Result := False;
      Inc(SeenStamp);
      CellsOf(P0, P1, X0, Y0, X1, Y1);
      for Y := Y0 to Y1 do
        for X := X0 to X1 do
        begin
          E := CellHead[Y * GW + X];
          while E >= 0 do
          begin
            G4 := EntSeg[E];
            E := EntNext[E];
            if SegSeen[G4] = SeenStamp then Continue;
            SegSeen[G4] := SeenStamp;
            Q0 := IdxA[G4]; Q1 := IdxB[G4];
            if (Max(P0.X, P1.X) < Min(Q0.X, Q1.X) - 1E-6) or (Min(P0.X, P1.X) > Max(Q0.X, Q1.X) + 1E-6) or
               (Max(P0.Y, P1.Y) < Min(Q0.Y, Q1.Y) - 1E-6) or (Min(P0.Y, P1.Y) > Max(Q0.Y, Q1.Y) + 1E-6) then Continue;
            if SegsMeet(P0, P1, Q0, Q1) then Exit(True);
          end;
        end;
    end;

    { does the plan, laid at the lane being tried, meet anything already
      laid for this manifold?  Checked before a candidate is kept. }
    function PlanCrosses(const Pl: TPlan; R: Integer): Boolean;
    var
      Lt: TRadiantLoop;
      SA: array of T2;

      { the boxes of P0-P1 and Q0-Q1 apart: they cannot meet }
      function Apart(const P0, P1, Q0, Q1: T2): Boolean;
      begin
        Result := (Max(P0.X, P1.X) < Min(Q0.X, Q1.X) - 1E-6) or (Min(P0.X, P1.X) > Max(Q0.X, Q1.X) + 1E-6) or
          (Max(P0.Y, P1.Y) < Min(Q0.Y, Q1.Y) - 1E-6) or (Min(P0.Y, P1.Y) > Max(Q0.Y, Q1.Y) + 1E-6);
      end;

      { The candidate leaves the floor, enters an obstacle, crosses itself or
        crosses tube already down - true at the first found.  Every test is
        boxed first: this runs for every lane and limit tried, and on a floor
        of many edges (an arc is a dozen) the raw tests dominate. }
      function Crosses: Boolean;
      var
        I4, J4, A4, K4, N4, Tmp: Integer;
        YLo, YHi: array of Double;
        Ord_: array of Integer;
      begin
        Result := True;
        { the floor's edges and the obstacles' - a lane test samples
          rows, so the finished segments are tested as well, and a
          connector cannot jump through a hole between those samples }
        for I4 := 1 to High(SA) do
          if EdgeMet(SA[I4 - 1], SA[I4]) then Exit;
        { Touching no edge, the whole candidate is on one side of each
          outline: its first point says which.  Every point was asked, and
          on a floor of many edges that was a tenth of a search. }
        if (Length(SA) > 0) and not InsidePoly(Poly2, SA[0]) then Exit;
        for A4 := 0 to High(HolePoly) do
          if (Length(SA) > 0) and InsidePoly(HolePoly[A4], SA[0]) then Exit;
        { Non-adjacent segments of this candidate must not meet either -
          asked only of those whose spans up V overlap, found by sorting
          them up V: every pair was asked, and a loop of a hundred runs
          is five thousand pairs for every lane tried. }
        N4 := High(SA);
        SetLength(YLo, N4 + 1); SetLength(YHi, N4 + 1); SetLength(Ord_, N4);
        for I4 := 1 to N4 do
        begin
          YLo[I4] := Min(SA[I4 - 1].Y, SA[I4].Y); YHi[I4] := Max(SA[I4 - 1].Y, SA[I4].Y);
          { a serpentine comes nearly in order already }
          K4 := I4 - 1;
          while (K4 > 0) and (YLo[Ord_[K4 - 1]] > YLo[I4]) do
          begin
            Ord_[K4] := Ord_[K4 - 1]; Dec(K4);
          end;
          Ord_[K4] := I4;
        end;
        for K4 := 0 to N4 - 1 do
        begin
          I4 := Ord_[K4];
          for Tmp := K4 + 1 to N4 - 1 do
          begin
            J4 := Ord_[Tmp];
            if YLo[J4] > YHi[I4] + 1E-6 then Break;
            if Abs(I4 - J4) < 2 then Continue;
            if not Apart(SA[I4 - 1], SA[I4], SA[J4 - 1], SA[J4]) and
               SegsMeet(SA[I4 - 1], SA[I4], SA[J4 - 1], SA[J4]) then Exit;
          end;
        end;
        for I4 := 1 to High(SA) do
          if MeetsIndexed(SA[I4 - 1], SA[I4]) then Exit;
        Result := False;
      end;

    begin
      LayPts(Pl, R);
      SA := Copy(Pts, 0, NPts);
      Result := Crosses;
      if WantTrace and not Compacting then
      begin
        LayPlan(Pl, R, Lt);
        SetLength(CurTrace, Length(CurTrace) + 1);
        CurTrace[High(CurTrace)].Pts := Lt.Pts;
        CurTrace[High(CurTrace)].Accepted := not Result;
      end;
    end;

    { this side's rows' bare floor, as laid so far }
    function BareRows: Double;
    var
      Rr: Integer;
      Runs: TRuns;
    begin
      Result := 0;
      Runs := RunsOf(Got);
      for Rr := 0 to High(RowV) do
        if Sign > 0 then Result := Result + RowBareRuns(RowV[Rr], Max(M2.X, LimLo), LimHi, Runs)
        else Result := Result + RowBareRuns(RowV[Rr], LimLo, Min(M2.X, LimHi), Runs);
    end;

    { The loop of rank R grown from row C: try the widest lane the row
      offers, then one spacing further in each time it does not fit or runs
      into tube already down, until one works or the row runs out.  Nothing
      here changes an earlier rank, so placed ranks are never revisited. }
    function TryRowFrom(C, R: Integer; out Pl: TPlan): Boolean;
    var
      Start, Ceiling: Double;
      Tries: Integer;
      SavedDead: array of Boolean;

      function Candidate: Boolean;
      begin
        DeadN := Copy(SavedDead);
        Result := PlanFrom(C, R, Pl) and not PlanCrosses(Pl, R);
      end;
    begin
      SavedDead := Copy(DeadN);
      BuildIndex;
      Result := False;
      if HasN[C] then Ceiling := NHi[C] - Spec.Spacing
      else if HasF[C] then Ceiling := FHi[C] - Spec.Spacing
      else Exit;
      { on the lanes' own lattice, half a spacing plus whole spacings out;
        off it, one rank's lane lands a fraction of a spacing from the next }
      Ceiling := Spec.Spacing / 2 + Floor((Ceiling - Spec.Spacing / 2) / Spec.Spacing + 1E-9) * Spec.Spacing;
      { the innermost loop's lanes at 1.5 and 0.5 spacings out: its home
        lane just clear of the manifold.  Any closer puts it on the far side
        of the manifold, the innermost slot goes unused, and a strip two
        lanes wide lies bare to the far wall. }
      Start := Min(Ceiling, 3 * Spec.Spacing / 2 +
        Max(0, 2 * Max(0, EstGuess - 1 - R) + RankJit[Min(R, 63)]) * Spec.Spacing);
      CurD := Start;
      Tries := 0;
      while (CurD >= -1E-6) and (Tries <= 4000) do
      begin
        if Candidate then Exit(True);
        CurD := CurD - Spec.Spacing;
        Inc(Tries);
      end;
      { the guess was too shy, not too bold: an obstacle can swallow every
        reach tried, with real room only further out }
      CurD := Start + Spec.Spacing;
      Tries := 0;
      while (CurD <= Ceiling + 1E-6) and (Tries <= 4000) do
      begin
        if Candidate then Exit(True);
        CurD := CurD + Spec.Spacing;
        Inc(Tries);
      end;
      DeadN := SavedDead;
      Result := False;
    end;

    { the plans, from the wall outward, each taking what it can.  Each loop
      goes into Got the moment it is accepted, so the next loop's crossing
      check sees all tube down so far, this side's included. }
    procedure PlaceAll;
    var
      C, Q: Integer;
      P: TPlan;
      L: TRadiantLoop;
    begin
      SetLength(Plans, 0);
      C := 0;
      while C <= High(RowV) do
      begin
        if TryRowFrom(C, Length(Plans), P) then
        begin
          for Q := 0 to High(P.Rows) do
            if P.Far[Q] then UsedF[P.Rows[Q]] := True else UsedN[P.Rows[Q]] := True;
          SetLength(Plans, Length(Plans) + 1);
          P.LaneD := CurD;
          Plans[High(Plans)] := P;
          LayPlan(P, High(Plans), L);
          L.Manifold := MI;
          SetLength(Got, Length(Got) + 1);
          Got[High(Got)] := L;
          { the next row with a piece still unused: a near one, or a far one
            on its own when nothing nearer reaches it }
          Inc(C);
          while (C <= High(RowV)) and ((not HasN[C]) or UsedN[C]) and
                ((not HasF[C]) or UsedF[C]) do Inc(C);
        end
        else Inc(C);
      end;
    end;

  { Slide every lane of this side in by the same whole number of spacings
    when the innermost is not beside the manifold - a loop count guessed one
    too many leaves a bare strip from the manifold to the far wall.  Each
    loop laid again passes the same checks under the tube's maximum; if any
    fails try a spacing less, and at none leave the side as it was. }
    procedure Compact;
    var
      I: Integer;
      MinD, Shift: Double;
      Old: TRadiantLoopArray;
      Lt: TRadiantLoop;
      Ok: Boolean;
    begin
      if Length(Plans) = 0 then Exit;
      MinD := 1E300;
      for I := 0 to High(Plans) do MinD := Min(MinD, Plans[I].LaneD);
      Shift := Floor((MinD - 3 * Spec.Spacing / 2) / Spec.Spacing + 1E-9) * Spec.Spacing;
      Old := Copy(Got, GotFrom, Length(Got) - GotFrom);
      Compacting := True;
      try
        while Shift >= Spec.Spacing - 1E-9 do
        begin
          SetLength(Got, GotFrom);
          Ok := True;
          for I := 0 to High(Plans) do
          begin
            CurD := Plans[I].LaneD - Shift;
            { the crossing index holds the tube down now: this side's loops
              laid again so far, not the ones they replace }
            BuildIndex;
            if not Fits(Plans[I], I) or PlanCrosses(Plans[I], I) then begin Ok := False; Break; end;
            LayPlan(Plans[I], I, Lt);
            Lt.Manifold := MI;
            SetLength(Got, Length(Got) + 1);
            Got[High(Got)] := Lt;
          end;
          if Ok then
          begin
            for I := 0 to High(Plans) do Plans[I].LaneD := Plans[I].LaneD - Shift;
            Exit;
          end;
          Shift := Shift - Spec.Spacing;
        end;
        { no slide would do: as it was }
        SetLength(Got, GotFrom);
        for I := 0 to High(Old) do
        begin
          SetLength(Got, Length(Got) + 1);
          Got[High(Got)] := Old[I];
        end;
      finally
        Compacting := False;
      end;
    end;

  begin
    NLOut := 0;
    Compacting := False;
    IdxGot := -1; IdxN := 0;
    for C := 0 to High(ClearD) do begin ClearD[C] := 0; ClearAt[C] := -1; end;
    ClearNext := 0;
    if SideK = 0 then Sign := -1 else Sign := 1;
    PortPitch := MANIFOLD_PORT_PITCH_IN * Spec.Inch;
    { how far out along the manifold a lane may start: the breakout, the
      tubes' only way off the grid }
    BreakD := BreakFt * 12 * Spec.Inch;
    SetLength(RowV, 0);
    { the rows from behind, farthest first, then this side's own }
    Plan := RowPlan(VDir);
    BackPlan := nil;
    if Behind > 0 then BackPlan := RowPlan(-VDir);
    Behind := Min(Behind, Length(BackPlan));
    if Behind mod 2 = 0 then Behind := Max(0, Behind - 1);
    SetLength(Plan, Length(Plan) + Behind);
    for C := High(Plan) downto Behind do Plan[C] := Plan[C - Behind];
    for C := 0 to Behind - 1 do Plan[C] := -BackPlan[Behind - 1 - C];
    for C := 0 to High(Plan) do
    begin
      V := M2.Y + VDir * Plan[C];
      SetLength(RowV, C + 1); SetLength(NLo, C + 1); SetLength(NHi, C + 1); SetLength(EdgeMax, C + 1);
      SetLength(FLo, C + 1); SetLength(FHi, C + 1); SetLength(HasN, C + 1); SetLength(HasF, C + 1);
      RowV[C] := V;
      RowPieces(V, Sign, EdgeD, NLo[C], NHi[C], FLo[C], FHi[C], HasN[C], HasF[C]);
      { how far out the floor's edge has come by this row: a lane up to a row
        must stay inside the floor the whole way (for rows behind, across
        all of them) }
      if C < Behind then
      begin
        EdgeMax[C] := EdgeD;
        for Q := 0 to C - 1 do
        begin
          EdgeMax[C] := Max(EdgeMax[C], EdgeMax[Q]);
          EdgeMax[Q] := EdgeMax[C];
        end;
      end
      else if C = Behind then EdgeMax[C] := EdgeD
      else EdgeMax[C] := Max(EdgeMax[C - 1], EdgeD);
      { this side stops halfway to the next manifold along the wall }
      if Sign > 0 then NHi[C] := Min(NHi[C], LimHi - M2.X) else NHi[C] := Min(NHi[C], M2.X - LimLo);
      if HasN[C] and (NHi[C] <= Spec.Spacing) then HasN[C] := False;
    end;
    N := Length(RowV);
    if N < 2 then
    begin
      Unf := Unf + BareRows;
      Exit;
    end;
    SetLength(UsedN, N); SetLength(UsedF, N); SetLength(DeadN, N);
    { where the search below starts looking - only a guess, since every lane
      is checked against tube already down, so a bad guess costs coverage,
      never a crossing.  A full-width loop holds about Limit / (4 x reach)
      rows; the first rank starts from the loop count that covers this
      side, leaving room for later ranks to nest inside it. }
    AvgReach := Spec.Spacing;
    for C := 0 to N - 1 do
      if HasN[C] then AvgReach := Max(AvgReach, NHi[C]);
    EstGuess := Max(1, Ceil(N / Max(2, Limit / AvgReach))) + ExtraRanks;

    GotFrom := Length(Got);
    PlaceAll;
    Compact;
    { the pairs, as laid: this side's loops two by two, from the first }
    if Pairs then
      for C := GotFrom + 1 to High(Got) do
        if (C - GotFrom) mod 2 = 1 then
        begin
          Got[C - 1].Couple := 1; Got[C].Couple := -1;
        end;
    Unf := Unf + BareRows;
    NLOut := Length(Plans);
  end;

  { One side, laid once.  NLFinal is how many loops this direction used, so
    the other direction can offset its ports past them.  A side whose
    shortest loop is under RUNT_SHARE of its longest has a runt (Runts);
    when Fold asks, it is laid again with its tube shared over one loop
    fewer and over as many, kept only if cheaper with no more floor bare. }
  procedure LaySideSettled(SideK, VDir: Integer; PortOff, Limit: Double; Behind: Integer;
    var Got: TRadiantLoopArray; var Unf: Double; out NLFinal: Integer);
  var
    K0, NLOut, N, I, Share, T0, KeepT: Integer;
    Unf0, Sum, Lo, Hi, BestC, C, WasTarget, KeepUnf, FirstUnf: Double;
    Keep: TRadiantLoopArray;
    KeepTrace: TRadiantTrace;

    { loops, spread and bare floor, as LayManifold weighs a layout }
    function SideCost: Double;
    var
      J: Integer;
      L, H: Double;
    begin
      L := 1E300; H := 0;
      for J := 0 to High(Got) do
      begin
        L := Min(L, Got[J].LenFt); H := Max(H, Got[J].LenFt);
      end;
      Result := (Length(Got) - K0) + (Unf - Unf0) / (Spec.Spacing * UNFILLED_LOOP_FT);
      if H > 0 then Result := Result + (H - L) / LOOP_EVEN_FT;
    end;

  begin
    K0 := Length(Got);
    Unf0 := Unf;
    T0 := Length(CurTrace);
    LaySide(SideK, VDir, PortOff, Limit, Behind, Got, Unf, NLOut);
    N := Length(Got) - K0;
    if not Quick and (N >= 2) then
    begin
      Sum := 0; Lo := 1E300; Hi := 0;
      for I := K0 to High(Got) do
      begin
        Sum := Sum + Got[I].LenFt;
        Lo := Min(Lo, Got[I].LenFt); Hi := Max(Hi, Got[I].LenFt);
      end;
      if Lo < RUNT_SHARE * Hi then RuntSeen := True;
      if Fold and (Lo < RUNT_SHARE * Hi) then
      begin
        BestC := SideCost;
        Keep := Copy(Got, K0, N); KeepUnf := Unf;
        FirstUnf := Unf;
        KeepTrace := Copy(CurTrace, T0, Length(CurTrace) - T0);
        WasTarget := TargetFt;
        for Share := N - 1 to N do
        begin
          if Sum / Share > MaxFt then Continue;
          SetLength(Got, K0); Unf := Unf0;
          SetLength(CurTrace, T0);
          TargetFt := Sum / Share;
          LaySide(SideK, VDir, PortOff, MaxFt, Behind, Got, Unf, NLOut);
          C := SideCost;
          if (C < BestC - 1E-6) and (Unf <= FirstUnf + Spec.Spacing * Spec.Spacing) then
          begin
            BestC := C;
            Keep := Copy(Got, K0, Length(Got) - K0); KeepUnf := Unf;
            KeepTrace := Copy(CurTrace, T0, Length(CurTrace) - T0);
          end;
        end;
        TargetFt := WasTarget;
        SetLength(Got, K0);
        for I := 0 to High(Keep) do
        begin
          SetLength(Got, Length(Got) + 1);
          Got[High(Got)] := Keep[I];
        end;
        Unf := KeepUnf;
        SetLength(CurTrace, T0);
        for KeepT := 0 to High(KeepTrace) do
        begin
          SetLength(CurTrace, Length(CurTrace) + 1);
          CurTrace[High(CurTrace)] := KeepTrace[KeepT];
        end;
      end;
    end;
    NLFinal := Length(Got) - K0;
  end;

  { Both sides under one limit per loop.  Filling every loop to the maximum
    leaves the last one scraps, so limits are tried from the maximum down
    and the cheapest kept: a loop costs the same as LOOP_EVEN_FT of spread
    or UNFILLED_LOOP_FT of unfilled row.  Rows come in pairs, so the spread
    cannot always close; the cost finds the middle ground. }
  procedure LayManifold;
  var
    Trial, Best, Saved: TRadiantLoopArray;
    BestTrace, SavedTrace: TRadiantTrace;
    Unf, BestUnf, T, BestT, Lo, Hi, Spread, Cost, BestCost, PPitch, Total: Double;
    SavedUnf, SavedCost, SavedT: Double;
    I, NBest: Integer;
    { the limit TryLimit is laying under, for Behind }
    TryT: Double;
    { a round of limits and the lengths they are laid toward - see TryLimits }
    Lims, Tgts: TDoubleArray;

    { how many rows behind the manifold on side SideK a loop from the other
      direction could take: nearest first, while each is one clear piece at
      least two spacings long }
    function BackRows(SideK: Integer): Integer;
    var
      BP: TDoubleArray;
      C, Sg: Integer;
      E, NL, NH, FL, FH: Double;
      HN, HF: Boolean;
    begin
      Result := 0;
      if SideK = 0 then Sg := -1 else Sg := 1;
      BP := RowPlan(-1);
      for C := 0 to High(BP) do
      begin
        RowPieces(M2.Y - BP[C], Sg, E, NL, NH, FL, FH, HN, HF);
        if not HN or HF or (NH - NL < 2 * Spec.Spacing) then Break;
        Inc(Result);
      end;
    end;

    { The strip behind the manifold: its rows taken by the first loop of the
      side in front (LaySide's Behind) where its own loop came out a runt or
      there was none.  Trial[K0..K1-1] is the side in front, the rest the
      side behind.  Laid when Strip asks, kept when it costs less and leaves
      no more floor bare. }
    procedure Behind(SideK, K0, K1: Integer; U0: Double; T0: Integer);
    var
      I, M, NP: Integer;
      Front, CostWas, Cost2, UnfWas: Double;
      Was: TRadiantLoopArray;
      WasTrace: TRadiantTrace;

      function SideCost: Double;
      var
        J: Integer;
        L, H: Double;
      begin
        L := 1E300; H := 0;
        for J := 0 to High(Trial) do
        begin
          L := Min(L, Trial[J].LenFt); H := Max(H, Trial[J].LenFt);
        end;
        Result := (Length(Trial) - K0) + (Unf - U0) / (Spec.Spacing * UNFILLED_LOOP_FT);
        if H > 0 then Result := Result + (H - L) / LOOP_EVEN_FT;
      end;

    begin
      if (K1 = K0) or (Length(Trial) - K1 > 1) then Exit;
      Front := 0;
      for I := 0 to K1 - 1 do Front := Max(Front, Trial[I].LenFt);
      if (Length(Trial) - K1 = 1) and (Trial[K1].LenFt >= RUNT_SHARE * Front) then Exit;
      M := Min(BackRows(SideK), BEHIND_ROWS_MAX);
      if M mod 2 = 0 then Dec(M);
      if M < 1 then Exit;
      StripSeen := True;
      if not Strip then Exit;
      CostWas := SideCost; UnfWas := Unf;
      Was := Copy(Trial, K0, Length(Trial) - K0);
      WasTrace := Copy(CurTrace, T0, Length(CurTrace) - T0);
      SetLength(Trial, K0); Unf := U0; SetLength(CurTrace, T0);
      LaySideSettled(SideK, 1, 0, TryT, M, Trial, Unf, NP);
      Cost2 := SideCost;
      if (Cost2 < CostWas - 1E-6) and (Unf <= UnfWas + Spec.Spacing * Spec.Spacing) then Exit;
      SetLength(Trial, K0); Unf := UnfWas;
      for I := 0 to High(Was) do
      begin
        SetLength(Trial, Length(Trial) + 1);
        Trial[High(Trial)] := Was[I];
      end;
      SetLength(CurTrace, T0);
      for I := 0 to High(WasTrace) do
      begin
        SetLength(CurTrace, Length(CurTrace) + 1);
        CurTrace[High(CurTrace)] := WasTrace[I];
      end;
    end;

    { the whole manifold laid under one limit (or toward one length, Target,
      under the tube's own) into Trial and Unf }
    procedure LayLimit(T: Double; Target: Double);
    var
      SideK, NP, K0, K1, T0: Integer;
      U0: Double;
    begin
      TryT := T;
      Trial := nil; Unf := 0;
      TargetFt := Target;
      if WantTrace then CurTrace := nil;
      for SideK := 0 to 1 do
      begin
        { away from the manifold's own row first; then, when the manifold
          is off its wall with floor the other way too, back toward the wall,
          past every port the first direction used so the two never share a
          connection.  The lanes need no offset: the two directions never
          share a row, and the crossing check catches anything else. }
        K0 := Length(Trial); U0 := Unf; T0 := Length(CurTrace);
        LaySideSettled(SideK, 1, 0, T, 0, Trial, Unf, NP);
        K1 := Length(Trial);
        LaySideSettled(SideK, -1, 2 * NP * PPitch, T, 0, Trial, Unf, NP);
        if not Quick then Behind(SideK, K0, K1, U0, T0);
      end;
      TargetFt := 0;
    end;

    { Trial and Unf, laid under limit T, kept if they cost less }
    procedure KeepLimit(T: Double);
    var
      I: Integer;
      L: Double;
    begin
      Lo := 1E300; Hi := 0;
      if Length(Trial) = 0 then Lo := 0;
      for I := 0 to High(Trial) do
      begin
        { a hooked pair weighed as its hook will leave it: the two evened }
        L := Trial[I].LenFt;
        if (Trial[I].Couple = 1) and (I < High(Trial)) then L := (L + Trial[I + 1].LenFt) / 2
        else if (Trial[I].Couple = -1) and (I > 0) then L := (L + Trial[I - 1].LenFt) / 2;
        Lo := Min(Lo, L); Hi := Max(Hi, L);
      end;
      Spread := Hi - Lo;
      Cost := Length(Trial) + Spread / LOOP_EVEN_FT + Unf / (Spec.Spacing * UNFILLED_LOOP_FT) +
        { more loops than the manifold takes: any layout within it first }
        OVER_PORTS_COST * Max(0, Length(Trial) - RadiantMaxPorts(Spec));
      if Cost < BestCost - 1E-6 then
      begin
        Best := Trial; BestUnf := Unf; BestCost := Cost; BestT := T;
        if WantTrace then BestTrace := CurTrace;
      end;
    end;

    procedure TryLimit(T: Double; Target: Double = 0);
    begin
      LayLimit(T, Target);
      KeepLimit(T);
    end;

    { Every limit in Ts, toward the lengths in Targets, laid and kept in
      order.  Each limit lays the manifold afresh, so with spare workers they
      run as leaves (see TSweepTask) and are kept here in the same order -
      the result matches one at a time.  Not for a trace, a quick look, or
      more than one manifold, where each depends on the one before. }
    procedure TryLimits(const Ts, Targets: array of Double);
    var
      Pool: TRadiantPool;
      G: TRadiantGroup;
      Tasks: array of TSweepTask;
      Each, K, J, N: Integer;
    begin
      Pool := nil;
      if (Sweep = nil) and not WantTrace and not Quick and (NM = 1) and (Length(Ts) >= 2) then
      begin
        Pool := ThePool;
        if (Pool <> nil) and not Pool.Spare then Pool := nil;
      end;
      if Pool = nil then
      begin
        for K := 0 to High(Ts) do TryLimit(Ts[K], Targets[K]);
        Exit;
      end;
      Each := Max(1, Ceil(Length(Ts) / Pool.Threads));
      SetLength(Tasks, Ceil(Length(Ts) / Each));
      G := TRadiantGroup.Create;
      try
        for K := 0 to High(Tasks) do
        begin
          Tasks[K] := TSweepTask.Create;
          Tasks[K].Leaf := True;
          Tasks[K].Outline := Outline;
          SetLength(Tasks[K].Holes, Length(Holes));
          for J := 0 to High(Holes) do Tasks[K].Holes[J] := Holes[J];
          Tasks[K].Spec := Spec;
          Tasks[K].Turn := Turn; Tasks[K].Fingers := Fingers; Tasks[K].EvenRows := EvenRows;
          Tasks[K].ShortFingers := ShortFingers; Tasks[K].Fold := Fold; Tasks[K].Strip := Strip;
          Tasks[K].Wild := Wild; Tasks[K].Pairs := Pairs; Tasks[K].FirstBudget := FirstBudget; Tasks[K].BreakFt := BreakFt;
          Tasks[K].RowOff := RowOff; Tasks[K].ExtraRanks := ExtraRanks; Tasks[K].LoopDelta := LoopDelta;
          Tasks[K].Seed := Seed;
          N := Min(Each, Length(Ts) - K * Each);
          SetLength(Tasks[K].Sweep.Items, N);
          for J := 0 to N - 1 do
          begin
            Tasks[K].Sweep.Items[J].T := Ts[K * Each + J];
            Tasks[K].Sweep.Items[J].Target := Targets[K * Each + J];
          end;
        end;
        Pool.Submit(G, TRadiantTaskArray(Tasks));
        Pool.Wait(G, 0, True);
        { kept in order; a share that failed on the pool is laid again here,
          where it fails the usual way }
        for K := 0 to High(Tasks) do
          if Tasks[K].Fail <> '' then
            for J := 0 to High(Tasks[K].Sweep.Items) do TryLimit(Tasks[K].Sweep.Items[J].T, Tasks[K].Sweep.Items[J].Target)
          else
          begin
            OddSeen := OddSeen or Tasks[K].Sweep.Odd;
            RuntSeen := RuntSeen or Tasks[K].Sweep.Runts;
            StripSeen := StripSeen or Tasks[K].Sweep.Strips;
            Tightest := Min(Tightest, Tasks[K].Sweep.Tightest);
            for J := 0 to High(Tasks[K].Sweep.Items) do
            begin
              Trial := Tasks[K].Sweep.Items[J].Trial;
              Unf := Tasks[K].Sweep.Items[J].Unf;
              KeepLimit(Tasks[K].Sweep.Items[J].T);
            end;
          end;
      finally
        for K := 0 to High(Tasks) do Tasks[K].Free;
        G.Free;
      end;
    end;

  begin
    PPitch := MANIFOLD_PORT_PITCH_IN * Spec.Inch;
    Best := nil; BestUnf := 1E300; BestCost := 1E300; BestTrace := nil; BestT := MaxFt;
    { laying another call's share of its limits: those, and no more }
    if Sweep <> nil then
    begin
      for I := 0 to High(Sweep^.Items) do
      begin
        LayLimit(Sweep^.Items[I].T, Sweep^.Items[I].Target);
        Sweep^.Items[I].Trial := Trial;
        Sweep^.Items[I].Unf := Unf;
      end;
      Exit;
    end;
    { Every 12 ft from the maximum down to half of it, then every 2 ft
      either side of the best of those - nearly always the same answer as
      every 2 ft, at a quarter of the layouts.  Only the first restart
      refines. }
    { a quick look (Suggest weighing one wall against another) lays the
      tube's maximum and nothing more }
    if Quick then
    begin
      TryLimit(MaxFt);
      T := 0;
    end
    else T := MaxFt;
    Lims := nil;
    while T >= MaxFt / 2 do
    begin
      SetLength(Lims, Length(Lims) + 1);
      Lims[High(Lims)] := T;
      T := T - 12;
    end;
    SetLength(Tgts, Length(Lims));
    for I := 0 to High(Tgts) do Tgts[I] := 0;
    TryLimits(Lims, Tgts);
    if (FirstBudget = 1) and (ExtraRanks = 0) and not Quick then
    begin
      Lims := nil;
      T := Min(MaxFt, BestT + 10);
      while T >= Max(MaxFt / 2, BestT - 10) do
      begin
        if Abs(Frac((MaxFt - T) / 12)) > 1E-9 then
        begin
          SetLength(Lims, Length(Lims) + 1);
          Lims[High(Lims)] := T;
        end;
        T := T - 2;
      end;
      SetLength(Tgts, Length(Lims));
      for I := 0 to High(Tgts) do Tgts[I] := 0;
      TryLimits(Lims, Tgts);
    end;
    { Then balanced: the best has N loops and S feet of tube, so lay again
      toward S/N a loop, and S/(N-1) and S/(N+1) in case one fewer or more
      evens them.  Every loop stops nearest that length instead of at the
      limit.  Weighed by the same cost, so it can only help. }
    NBest := Length(Best);
    if (NBest > 0) and not Quick then
    begin
      Total := 0;
      for I := 0 to High(Best) do Total := Total + Best[I].LenFt;
      Lims := nil; Tgts := nil;
      for I := -1 to 1 do
        if (NBest + I >= 1) and (Total / (NBest + I) <= MaxFt) then
        begin
          SetLength(Lims, Length(Lims) + 1); SetLength(Tgts, Length(Lims));
          Lims[High(Lims)] := MaxFt; Tgts[High(Tgts)] := Total / (NBest + I);
        end;
      TryLimits(Lims, Tgts);
      { And forced: LoopDelta loops more or fewer than the best, laid toward
        that share of the tube and kept whatever the cost says, since the
        cost alone never leaves the loop count it started with.  Fewer loops
        still stop at the tube's maximum.  If nothing lays, the best stands. }
      if (LoopDelta <> 0) and (NBest + LoopDelta >= 1) then
      begin
        Saved := Best; SavedUnf := BestUnf; SavedCost := BestCost; SavedT := BestT;
        if WantTrace then SavedTrace := BestTrace;
        BestCost := 1E300;
        TryLimit(MaxFt, Min(MaxFt, Total / (NBest + LoopDelta)));
        if Length(Best) = 0 then
        begin
          Best := Saved; BestUnf := SavedUnf; BestCost := SavedCost; BestT := SavedT;
          if WantTrace then BestTrace := SavedTrace;
        end;
      end;
    end;
    for I := 0 to High(Best) do
    begin
      SetLength(Loops, Length(Loops) + 1);
      Loops[High(Loops)] := Best[I];
    end;
    Unfilled := Unfilled + BestUnf;
    if WantTrace then
      for I := 0 to High(BestTrace) do
      begin
        SetLength(Trace, Length(Trace) + 1);
        Trace[High(Trace)] := BestTrace[I];
      end;
  end;

  { where any two runs of tube meet - a crossing or a touch, equally bad in
    a slab.  In the manifold's frame; a loop's consecutive segments share a
    corner and are not counted. }
  function Meetings(FromLoop: Integer): Integer;
  var
    A, B, I, J: Integer;
    P0, P1, Q0, Q1: T2;
    SA, SB: array of T2;
  begin
    Result := 0;
    for A := FromLoop to High(Loops) do
    begin
      SetLength(SA, Length(Loops[A].Pts));
      for I := 0 to High(SA) do SA[I] := RadiantTo2(F, Loops[A].Pts[I]);
      for B := 0 to High(Loops) do
      begin
        if (B < A) and (B >= FromLoop) then Continue;
        SetLength(SB, Length(Loops[B].Pts));
        for I := 0 to High(SB) do SB[I] := RadiantTo2(F, Loops[B].Pts[I]);
        for I := 1 to High(SA) do
          for J := 1 to High(SB) do
          begin
            if (A = B) and (J <= I + 1) then Continue;
            P0 := SA[I - 1]; P1 := SA[I]; Q0 := SB[J - 1]; Q1 := SB[J];
            if (Max(P0.X, P1.X) < Min(Q0.X, Q1.X) - 1E-6) or (Min(P0.X, P1.X) > Max(Q0.X, Q1.X) + 1E-6) or
               (Max(P0.Y, P1.Y) < Min(Q0.Y, Q1.Y) - 1E-6) or (Min(P0.Y, P1.Y) > Max(Q0.Y, Q1.Y) + 1E-6) then Continue;
            if SegsMeet(P0, P1, Q0, Q1) then Inc(Result);
          end;
      end;
    end;
  end;

  { the floor of this manifold as the loops in Lps leave it: every row both
    ways from the manifold, out to the halfway lines }
  function RegionBare(const Lps: TRadiantLoopArray): Double;
  var
    VDir, C: Integer;
    Plan: TDoubleArray;
    Runs: TRuns;
  begin
    Result := 0;
    Runs := RunsOf(Lps);
    for VDir := -1 to 1 do
    begin
      if VDir = 0 then Continue;
      Plan := RowPlan(VDir);
      for C := 0 to High(Plan) do
        Result := Result + RowBareRuns(M2.Y + VDir * Plan[C], LimLo, LimHi, Runs);
    end;
  end;

  { The floor of this manifold as the loops leave it, sampled every half
    spacing from the wall's inset rather than at the rows, so layouts with
    shifted rows are measured on the same floor and the strip at the far
    wall is counted.  This is the bare floor reported; the search itself
    measures at the rows, which is cheaper. }
  function FloorBare(const Lps: TRadiantLoopArray): Double;
  var
    K: Integer;
    V: Double;
    Runs: TRuns;
  begin
    Result := 0;
    K := 0;
    Runs := RunsOf(Lps);
    repeat
      V := Vmin + Inset + K * Spec.Spacing / 2;
      if V > Vmax - Inset + 1E-9 then Break;
      Result := Result + RowBareRuns(V, LimLo, LimHi, Runs) / 2;
      Inc(K);
    until K > 20000;
  end;

  { Loops evened by hooks at the far wall.  Rows come a pair at a time, so
    loops come out a pair's worth apart.  A hook moves length to a neighbor:
    the short loop runs on across its neighbor's first two rows in a small S
    and back, and the neighbor's rows turn short to match.  Kept only when
    more even and nothing crosses; random tries jitter it (see DrawTry). }
  procedure HookLoops(FromLoop: Integer);
  var
    Q: array of T2Array;
    Len: array of Double;
    Nb: array of TIntArray;
    Chain: TIntArray;
    Seen: array of Boolean;
    Saved: TRadiantLoopArray;
    S, Mean, Need, Tau, D, Room, Sp0, Sp1, Fx, Y0, U, G: Double;
    I, J, K, A, B, Tk, Gv, Prev, Cur, Nxt, Hooks, Pp: Integer;
    Rev, Found, Jitter: Boolean;
    { one hook a loop: loops already hooked, and the best found so far }
    Used: array of Boolean;
    Gain, BestGain, DHi, BFx, BY0, BU, BG, BD, Orig: Double;
    MaxHooks, BTk, BK, BGv, BJ: Integer;
    BRev: Boolean;

    { sum of squared distances from the mean with loops A2 and B2 at these
      lengths (a hook keeps the tube, so the mean stays).  Not the spread:
      that only sees the two ends, so a hook evening two middle loops would
      never count. }
    function DevWith(A2: Integer; LA: Double; B2: Integer; LB: Double): Double;
    var
      M: Integer;
      Mn, L2: Double;
    begin
      Mn := 0;
      for M := FromLoop to High(Len) do Mn := Mn + Len[M];
      Mn := Mn / Max(1, Length(Len) - FromLoop);
      Result := 0;
      for M := FromLoop to High(Len) do
      begin
        if M = A2 then L2 := LA else if M = B2 then L2 := LB else L2 := Len[M];
        Result := Result + Sqr(L2 - Mn);
      end;
    end;

    function Rnd: Double;
    begin
      RandState := Cardinal((QWord(RandState) * 1664525 + 1013904223) and $FFFFFFFF);
      Result := ((RandState shr 8) and $FFFFFF) / 16777216;
    end;

    function PathLen(const P: T2Array): Double;
    var
      M: Integer;
    begin
      Result := 0;
      for M := 1 to High(P) do Result := Result + Hypot(P[M].X - P[M - 1].X, P[M].Y - P[M - 1].Y);
    end;

    function SpreadNow: Double;
    var
      M: Integer;
      Lo, Hi: Double;
    begin
      Lo := 1E300; Hi := 0;
      for M := FromLoop to High(Len) do
      begin
        Lo := Min(Lo, Len[M]); Hi := Max(Hi, Len[M]);
      end;
      if Hi <= 0 then Result := 0 else Result := (Hi - Lo) / Hi;
    end;

    { loop Li's turn at points K, K + 1 (walked back if Rev) if it is a far
      turn: out along a row away from the manifold, a spacing across, back
      along the next.  Fx is where it turns, Y0 the row it came out on, U
      the step to the next row, G the outward direction. }
    function FarTurn(Li, K: Integer; Rev: Boolean; out Fx, Y0, U, G: Double): Boolean;
    var
      P, Qq, Pv, Nx: T2;
    begin
      Result := False;
      Fx := 0; Y0 := 0; U := 0; G := 0;
      if (K < 1) or (K + 2 > High(Q[Li])) then Exit;
      if Rev then
      begin
        P := Q[Li][K + 1]; Qq := Q[Li][K]; Pv := Q[Li][K + 2]; Nx := Q[Li][K - 1];
      end
      else
      begin
        P := Q[Li][K]; Qq := Q[Li][K + 1]; Pv := Q[Li][K - 1]; Nx := Q[Li][K + 2];
      end;
      if Abs(P.X - Qq.X) > 1E-6 then Exit;
      if Abs(Abs(Qq.Y - P.Y) - S) > 1E-6 then Exit;
      if (Abs(Pv.Y - P.Y) > 1E-6) or (Abs(Nx.Y - Qq.Y) > 1E-6) then Exit;
      G := Sign(P.X - Pv.X);
      if (G = 0) or (Sign(Qq.X - Nx.X) <> G) then Exit;
      if (Abs(P.X - M2.X) <= Abs(Pv.X - M2.X)) or (Abs(Qq.X - M2.X) <= Abs(Nx.X - M2.X)) then Exit;
      Fx := P.X; Y0 := P.Y; U := Qq.Y - P.Y;
      Result := True;
    end;

    { the loop a far turn could hook into: another loop's far turn at the
      same place, on rows Y0 + 2U and Y0 + 3U.  J is its first point, Room
      how far the shorter of its two rows runs back from the wall. }
    function Giver(Li: Integer; Fx, Y0, U, G: Double; out Lj, J: Integer; out Room: Double): Boolean;
    var
      L, K: Integer;
      A0, A1: Double;
    begin
      Result := False; Lj := -1; J := -1; Room := 0;
      for L := FromLoop to High(Q) do
      begin
        if L = Li then Continue;
        for K := 1 to High(Q[L]) - 2 do
        begin
          if (Abs(Q[L][K].X - Fx) > 1E-6) or (Abs(Q[L][K + 1].X - Fx) > 1E-6) then Continue;
          A0 := Q[L][K].Y; A1 := Q[L][K + 1].Y;
          if not (((Abs(A0 - (Y0 + 2 * U)) < 1E-6) and (Abs(A1 - (Y0 + 3 * U)) < 1E-6)) or
                  ((Abs(A0 - (Y0 + 3 * U)) < 1E-6) and (Abs(A1 - (Y0 + 2 * U)) < 1E-6))) then Continue;
          if (Abs(Q[L][K - 1].Y - A0) > 1E-6) or (Abs(Q[L][K + 2].Y - A1) > 1E-6) then Continue;
          if (Sign(Fx - Q[L][K - 1].X) <> G) or (Sign(Fx - Q[L][K + 2].X) <> G) then Continue;
          Lj := L; J := K;
          Room := Min(Abs(Fx - Q[L][K - 1].X), Abs(Fx - Q[L][K + 2].X));
          Exit(True);
        end;
      end;
    end;

    { a hook from loop Tk into loop Gv as the loops stand; any giver when Gv
      is -1 }
    function FindHook(Tk, Gv: Integer; out K: Integer; out Rev: Boolean;
      out Fx, Y0, U, G: Double; out Lj, J: Integer; out Room: Double): Boolean;
    var
      R2, K2: Integer;
    begin
      Result := False;
      Lj := -1; J := -1; Room := 0; Rev := False; K := -1;
      for K2 := 1 to High(Q[Tk]) - 2 do
        for R2 := 0 to 1 do
          if FarTurn(Tk, K2, R2 = 1, Fx, Y0, U, G) and Giver(Tk, Fx, Y0, U, G, Lj, J, Room) and
             ((Gv < 0) or (Lj = Gv)) then
          begin
            K := K2; Rev := R2 = 1;
            Exit(True);
          end;
    end;

    { lay the hook: D is how far back from the wall the taker runs along the
      giver's outer row }
    procedure Lay(Tk, K: Integer; Rev: Boolean; Fx, Y0, U, G: Double; Lj, J: Integer; D: Double);
    var
      Hk: array[0..4] of T2;
      X: Double;
      Old: T2Array;
      P: Integer;
    begin
      X := Fx - G * D;
      Hk[0] := Point2(Fx, Y0 + 3 * U);
      Hk[1] := Point2(X, Y0 + 3 * U);
      Hk[2] := Point2(X, Y0 + 2 * U);
      Hk[3] := Point2(Fx - G * S, Y0 + 2 * U);
      Hk[4] := Point2(Fx - G * S, Y0 + U);
      Old := Copy(Q[Tk]);
      SetLength(Q[Tk], Length(Old) + 4);
      if not Rev then
      begin
        for P := 0 to K do Q[Tk][P] := Old[P];
        for P := 0 to 4 do Q[Tk][K + 1 + P] := Hk[P];
        for P := K + 2 to High(Old) do Q[Tk][P + 4] := Old[P];
      end
      else
      begin
        for P := 0 to K - 1 do Q[Tk][P] := Old[P];
        for P := 0 to 4 do Q[Tk][K + P] := Hk[4 - P];
        for P := K + 1 to High(Old) do Q[Tk][P + 4] := Old[P];
      end;
      Q[Lj][J].X := X - G * S; Q[Lj][J + 1].X := X - G * S;
      Len[Tk] := PathLen(Q[Tk]); Len[Lj] := PathLen(Q[Lj]);
    end;

    procedure Link(A, B: Integer);
    var
      M: Integer;
    begin
      for M := 0 to High(Nb[A]) do
        if Nb[A][M] = B then Exit;
      SetLength(Nb[A], Length(Nb[A]) + 1); Nb[A][High(Nb[A])] := B;
      SetLength(Nb[B], Length(Nb[B]) + 1); Nb[B][High(Nb[B])] := A;
    end;

  begin
    if Length(Loops) - FromLoop < 2 then Exit;
    S := Spec.Spacing;
    SetLength(Q, Length(Loops)); SetLength(Len, Length(Loops));
    for I := 0 to High(Loops) do
    begin
      SetLength(Q[I], Length(Loops[I].Pts));
      for J := 0 to High(Loops[I].Pts) do Q[I][J] := RadiantTo2(F, Loops[I].Pts[J]);
      Len[I] := Loops[I].LenFt;
    end;
    Sp0 := SpreadNow;
    Orig := Sp0;
    { a random try: half the time the hooks exactly as they even the loops,
      half the time jittered }
    Jitter := (Seed <> 0) and (Rnd < 0.5);
    Hooks := 0;
    SetLength(Used, Length(Loops));
    { Hooked pairs first, where loops were laid as pairs (Pairs): each pair
      evened by one hook between them, the shorter running on over the
      longer's rows at the far wall.  The pair was laid to twice the length
      (see PastTarget), so each comes out near it. }
    if Pairs then
      for I := FromLoop to High(Loops) - 1 do
      begin
        if (Loops[I].Couple <> 1) or (Loops[I + 1].Couple <> -1) then Continue;
        if Len[I] <= Len[I + 1] then begin Tk := I; Gv := I + 1; end
        else begin Tk := I + 1; Gv := I; end;
        Tau := (Len[Gv] - Len[Tk]) / 2;
        if not FindHook(Tk, Gv, K, Rev, Fx, Y0, U, G, Pp, Cur, Room) then Continue;
        D := Tau / 2 - S;
        D := Min(D, Room - 3 * S);
        D := Min(D, (MaxFt - Len[Tk]) / 2 - S);
        D := Round(D / Spec.Inch) * Spec.Inch;
        if D < 2 * S - 1E-9 then Continue;
        Lay(Tk, K, Rev, Fx, Y0, U, G, Pp, Cur, D);
        Used[Tk] := True; Used[Gv] := True;
        Inc(Hooks);
      end;
    { One hook a loop, never a chain - a chain leaves a turn back mid-floor
      on every loop of the side.  Take the hook that brings the loops
      nearest their mean (DevWith), then others only between loops not yet
      hooked.  The chain is used only with less friendly layouts allowed,
      on half of those tries. }
    if not Hook then
    else if not (Spec.LessFriendly and (Seed <> 0) and not Pairs and (Rnd < 0.5)) then
    begin
      MaxHooks := MaxInt;
      if Jitter then MaxHooks := 1 + Trunc(Rnd * 2);
      repeat
        Sp0 := DevWith(-1, 0, -1, 0);
        BestGain := 1E-6; BTk := -1;
        BK := 0; BGv := 0; BJ := 0; BRev := False; BFx := 0; BY0 := 0; BU := 0; BG := 0; BD := 0;
        for Tk := FromLoop to High(Loops) do
        begin
          if Used[Tk] then Continue;
          for K := 1 to High(Q[Tk]) - 2 do
            for Pp := 0 to 1 do
            begin
              if not FarTurn(Tk, K, Pp = 1, Fx, Y0, U, G) then Continue;
              if not Giver(Tk, Fx, Y0, U, G, A, J, Room) or Used[A] then Continue;
              { D at least two spacings, the giver's rows left two
                spacings long, the taker within the tube; tried three
                inches at a time }
              DHi := Min(Room - 3 * S, (MaxFt - Len[Tk]) / 2 - S);
              D := 2 * S;
              while D <= DHi + 1E-9 do
              begin
                Gain := Sp0 - DevWith(Tk, Len[Tk] + 2 * D + 2 * S, A, Len[A] - 2 * D - 2 * S);
                if Jitter then Gain := Gain * (1 - HOOK_JITTER + 2 * HOOK_JITTER * Rnd);
                if Gain > BestGain then
                begin
                  BestGain := Gain; BTk := Tk; BK := K; BRev := Pp = 1; BGv := A; BJ := J;
                  BFx := Fx; BY0 := Y0; BU := U; BG := G; BD := D;
                end;
                D := D + 3 * Spec.Inch;
              end;
            end;
        end;
        if BTk < 0 then Break;
        Lay(BTk, BK, BRev, BFx, BY0, BU, BG, BGv, BJ, Round(BD / Spec.Inch) * Spec.Inch);
        Used[BTk] := True; Used[BGv] := True;
        Inc(Hooks);
      until Hooks >= MaxHooks;
    end
    else
    begin
    { who can hook whom }
    SetLength(Nb, Length(Loops));
    for I := FromLoop to High(Loops) do
      for K := 1 to High(Q[I]) - 2 do
        for Pp := 0 to 1 do
          if FarTurn(I, K, Pp = 1, Fx, Y0, U, G) and Giver(I, Fx, Y0, U, G, A, J, Room) then Link(I, A);
    { each row of neighbors, from an end, evened along it }
    SetLength(Seen, Length(Loops));
    Hooks := 0;
    for I := FromLoop to High(Loops) do
    begin
      if Seen[I] or (Length(Nb[I]) <> 1) then Continue;
      Chain := nil;
      Prev := -1; Cur := I;
      repeat
        SetLength(Chain, Length(Chain) + 1); Chain[High(Chain)] := Cur;
        Seen[Cur] := True;
        Nxt := -1;
        if Length(Nb[Cur]) <= 2 then
          for J := 0 to High(Nb[Cur]) do
            if (Nb[Cur][J] <> Prev) and not Seen[Nb[Cur][J]] then Nxt := Nb[Cur][J];
        Prev := Cur; Cur := Nxt;
      until Cur < 0;
      if Length(Chain) < 2 then Continue;
      Mean := 0;
      for J := 0 to High(Chain) do Mean := Mean + Len[Chain[J]];
      Mean := Mean / Length(Chain);
      for J := 0 to High(Chain) - 1 do
      begin
        A := Chain[J]; B := Chain[J + 1];
        Need := Mean - Len[A];
        if Jitter then
        begin
          if Rnd < HOOK_SKIP then Continue;
          Need := Need * (1 - HOOK_JITTER + 2 * HOOK_JITTER * Rnd);
        end;
        if Need > 0 then begin Tk := A; Gv := B; Tau := Need; end
        else begin Tk := B; Gv := A; Tau := -Need; end;
        Found := FindHook(Tk, Gv, K, Rev, Fx, Y0, U, G, Pp, Cur, Room);
        if not Found then Continue;
        { the hook moves 2D + 2 spacings; D at least two spacings, the
          giver's rows left two spacings long, the taker within the tube }
        D := Tau / 2 - S;
        D := Min(D, Room - 3 * S);
        D := Min(D, (MaxFt - Len[Tk]) / 2 - S);
        { whole inches, for a tape }
        D := Round(D / Spec.Inch) * Spec.Inch;
        if D < 2 * S - 1E-9 then Continue;
        Lay(Tk, K, Rev, Fx, Y0, U, G, Pp, Cur, D);
        Inc(Hooks);
      end;
    end;
    end;
    if Hooks = 0 then Exit;
    Sp1 := SpreadNow;
    if Sp1 >= Orig - 1E-6 then Exit;
    Saved := Copy(Loops);
    for I := FromLoop to High(Loops) do
      if Length(Q[I]) <> Length(Loops[I].Pts) then
      begin
        SetLength(Loops[I].Pts, Length(Q[I]));
        for J := 0 to High(Q[I]) do Loops[I].Pts[J] := World(Q[I][J]);
        Loops[I].LenFt := Len[I];
      end
      else
      begin
        { a giver: its points moved, not its count }
        Loops[I].Pts := Copy(Loops[I].Pts);
        for J := 0 to High(Q[I]) do Loops[I].Pts[J] := World(Q[I][J]);
        Loops[I].LenFt := Len[I];
      end;
    { anything crossed: undo all of it }
    if Meetings(FromLoop) > 0 then
    begin
      Loops := Saved;
      Exit;
    end;
    { the replay shows the loops as laid }
    if WantTrace then
      for I := FromLoop to High(Loops) do
        for K := High(Trace) downto 0 do
          if Trace[K].Accepted and (Length(Trace[K].Pts) = Length(Saved[I].Pts)) then
          begin
            Found := True;
            for J := 0 to High(Saved[I].Pts) do
              if Dist(Trace[K].Pts[J], Saved[I].Pts[J]) > 1E-9 then begin Found := False; Break; end;
            if Found then begin Trace[K].Pts := Loops[I].Pts; Break; end;
          end;
  end;

  { The repair pass: grow loops laid short of the maximum into bare floor
    beside them, by fingers - hairpins one spacing wide pushed out square
    from a straight run, at least two spacings deep, a spacing off all tube
    and an inset off walls and obstacles, within the tube's maximum.  Kept
    only when it costs less by the search's own measure. }
  procedure GrowLoops(FromLoop: Integer);
  var
    Q, BestQ: array of T2Array;
    Len, BestLen: array of Double;
    Moved, BestMoved: array of Boolean;
    Order: TIntArray;
    Bare0, BestBare, BestCost, Cap, Hi, MinFinger: Double;
    I, J, CapTry, Tmp: Integer;
    Changed: Boolean;

    function Cost(const Lens: array of Double; Bare: Double): Double;
    var
      Li: Integer;
      Lo, Hi: Double;
    begin
      Lo := 1E300; Hi := 0;
      for Li := FromLoop to High(Lens) do
      begin
        Lo := Min(Lo, Lens[Li]); Hi := Max(Hi, Lens[Li]);
      end;
      if Hi = 0 then Lo := 0;
      Result := (Hi - Lo) / LOOP_EVEN_FT + Bare / (Spec.Spacing * UNFILLED_LOOP_FT);
    end;

    function Along(const P: T2; Ax: Integer): Double;
    begin
      if Ax = 0 then Result := P.X else Result := P.Y;
    end;

    function Across(const P: T2; Ax: Integer): Double;
    begin
      if Ax = 0 then Result := P.Y else Result := P.X;
    end;

    { how high above the base line, rising Sg, segment P-Q comes while within
      W of the base's stretch A0..B0: 1E300 if never, 0 if it reaches the line }
    function Rise(const P, Qp: T2; Ax, Sg: Integer; A0, B0, C0, W: Double): Double;
    var
      Pa, Qa, Pc, Qc, Lo, Hi, T0, T1, S0, S1: Double;
    begin
      Result := 1E300;
      Pa := Along(P, Ax); Qa := Along(Qp, Ax);
      Lo := A0 - W + 1E-6; Hi := B0 + W - 1E-6;
      if (Max(Pa, Qa) <= Lo) or (Min(Pa, Qa) >= Hi) then Exit;
      Pc := Sg * (Across(P, Ax) - C0); Qc := Sg * (Across(Qp, Ax) - C0);
      if Abs(Qa - Pa) < 1E-12 then begin T0 := 0; T1 := 1; end
      else
      begin
        T0 := (Lo - Pa) / (Qa - Pa); T1 := (Hi - Pa) / (Qa - Pa);
        if T0 > T1 then begin S0 := T0; T0 := T1; T1 := S0; end;
        T0 := Max(0, T0); T1 := Min(1, T1);
      end;
      S0 := Pc + T0 * (Qc - Pc); S1 := Pc + T1 * (Qc - Pc);
      if Max(S0, S1) < -1E-6 then Exit;
      if Min(S0, S1) <= 1E-6 then Exit(0);
      Result := Min(S0, S1);
    end;

    { how far a finger on loop Li's segment Seg, over A0..B0, can rise Sg
      before it comes within a spacing of tube or an inset of a wall or
      obstacle.  Skips this loop's segments SkipLo..SkipHi (the one it grows
      from and, for a pushed turn, the runs either side).  Returns early once
      the room is less than Enough. }
    function Room(Li, SkipLo, SkipHi, Ax, Sg: Integer; A0, B0, C0, Enough: Double): Double;
    var
      Lj, K, H2: Integer;
    begin
      Result := 1E300;
      for Lj := 0 to High(Q) do
        for K := 1 to High(Q[Lj]) do
        begin
          if (Lj = Li) and (K - 1 >= SkipLo) and (K - 1 <= SkipHi) then Continue;
          Result := Min(Result, Rise(Q[Lj][K - 1], Q[Lj][K], Ax, Sg, A0, B0, C0, Spec.Spacing) - Spec.Spacing);
          { stop only when short by more than the callers' own 1E-9
            tolerance.  On a floor turned off the square, rows land a
            rounding error under whole spacings, and stopping a hair under
            Enough let a finger through rows of tube unchecked. }
          if Result < Enough - 1E-6 then Exit;
        end;
      for K := 0 to High(Poly2) do
        Result := Min(Result, Rise(Poly2[K], Poly2[(K + 1) mod Length(Poly2)], Ax, Sg, A0, B0, C0, Inset) - Inset);
      for H2 := 0 to High(HolePoly) do
        for K := 0 to High(HolePoly[H2]) do
          Result := Min(Result, Rise(HolePoly[H2][K], HolePoly[H2][(K + 1) mod Length(HolePoly[H2])],
            Ax, Sg, A0, B0, C0, Inset) - Inset);
      { and not past the halfway line to the next manifold }
      if Ax = 1 then
      begin
        if Sg > 0 then Result := Min(Result, LimHi - C0) else Result := Min(Result, C0 - LimLo);
      end
      else if (A0 < LimLo) or (B0 > LimHi) then Result := 0;
    end;

    { One pass over loop Li: every turn pushed out as far as the floor in
      front of it is bare.  A turn (the end of a serpentine's pair of rows)
      moved outward lengthens those two runs without adding a bend, so it is
      tried before any finger. }
    function PushOne(Li: Integer): Boolean;
    var
      Seg, Ax, Sg, SPrev, SNext: Integer;
      P0, P1, Pp, Pn: T2;
      A0, B0, C0, H: Double;
    begin
      Result := False;
      for Seg := 1 to High(Q[Li]) - 2 do
      begin
        if Cap - Len[Li] < 2 * PUSH_MIN * Spec.Spacing then Exit;
        P0 := Q[Li][Seg]; P1 := Q[Li][Seg + 1];
        Pp := Q[Li][Seg - 1]; Pn := Q[Li][Seg + 2];
        if Abs(P1.Y - P0.Y) < 1E-9 then Ax := 0
        else if Abs(P1.X - P0.X) < 1E-9 then Ax := 1
        else Continue;
        { both neighbors square to it: straight in the other axis }
        if Abs(Along(Pp, Ax) - Along(P0, Ax)) > 1E-9 then Continue;
        if Abs(Along(Pn, Ax) - Along(P1, Ax)) > 1E-9 then Continue;
        C0 := Across(P0, Ax);
        SPrev := Sign(Across(Pp, Ax) - C0); SNext := Sign(Across(Pn, Ax) - C0);
        if (SPrev = 0) or (SPrev <> SNext) then Continue;
        Sg := -SPrev;
        A0 := Min(Along(P0, Ax), Along(P1, Ax)); B0 := Max(Along(P0, Ax), Along(P1, Ax));
        H := Min(Room(Li, Seg - 1, Seg + 1, Ax, Sg, A0, B0, C0, PUSH_MIN * Spec.Spacing),
          (Cap - Len[Li]) / 2 - 1E-6);
        if H < PUSH_MIN * Spec.Spacing - 1E-9 then Continue;
        if Ax = 0 then
        begin
          Q[Li][Seg].Y := C0 + Sg * H; Q[Li][Seg + 1].Y := C0 + Sg * H;
        end
        else
        begin
          Q[Li][Seg].X := C0 + Sg * H; Q[Li][Seg + 1].X := C0 + Sg * H;
        end;
        Len[Li] := Len[Li] + 2 * H;
        Moved[Li] := True;
        Result := True;
      end;
    end;

    { one pass over loop Li: a finger wherever a straight run has room }
    function GrowOne(Li: Integer): Boolean;
    var
      Seg, Ax, Dir, Sg, N: Integer;
      P0, P1: T2;
      SegLen, T, A0, B0, C0, H: Double;
      Placed: Boolean;
    begin
      Result := False;
      Seg := 0;
      while Seg < High(Q[Li]) do
      begin
        if Cap - Len[Li] < 2 * MinFinger then Exit;
        P0 := Q[Li][Seg]; P1 := Q[Li][Seg + 1];
        if Abs(P1.Y - P0.Y) < 1E-9 then Ax := 0
        else if Abs(P1.X - P0.X) < 1E-9 then Ax := 1
        else begin Inc(Seg); Continue; end;
        SegLen := Abs(Along(P1, Ax) - Along(P0, Ax));
        if Along(P1, Ax) > Along(P0, Ax) then Dir := 1 else Dir := -1;
        C0 := Across(P0, Ax);
        Placed := False;
        T := Spec.Spacing;
        while (T + 2 * Spec.Spacing <= SegLen + 1E-9) and not Placed do
        begin
          A0 := Along(P0, Ax) + Dir * T;
          B0 := A0 + Dir * Spec.Spacing;
          for Sg := 1 downto -1 do
          begin
            if Sg = 0 then Continue;
            H := Min(Room(Li, Seg, Seg, Ax, Sg, Min(A0, B0), Max(A0, B0), C0, MinFinger),
              (Cap - Len[Li]) / 2 - 1E-6);
            if H < MinFinger - 1E-9 then Continue;
            { out, across, back - after P0, before P1 }
            N := Length(Q[Li]);
            SetLength(Q[Li], N + 4);
            Move(Q[Li][Seg + 1], Q[Li][Seg + 5], (N - Seg - 1) * SizeOf(T2));
            if Ax = 0 then
            begin
              Q[Li][Seg + 1] := Point2(A0, C0);
              Q[Li][Seg + 2] := Point2(A0, C0 + Sg * H);
              Q[Li][Seg + 3] := Point2(B0, C0 + Sg * H);
              Q[Li][Seg + 4] := Point2(B0, C0);
            end
            else
            begin
              Q[Li][Seg + 1] := Point2(C0, A0);
              Q[Li][Seg + 2] := Point2(C0 + Sg * H, A0);
              Q[Li][Seg + 3] := Point2(C0 + Sg * H, B0);
              Q[Li][Seg + 4] := Point2(C0, B0);
            end;
            Len[Li] := Len[Li] + 2 * H;
            Moved[Li] := True;
            Result := True; Placed := True;
            Break;
          end;
          T := T + Spec.Spacing;
        end;
        { the rest of this run, from the finger on, is the next segment }
        if Placed then Seg := Seg + 4 else Inc(Seg);
      end;
    end;

    { a loop grown here is the one kept, so the replay shows it as finally laid }
    procedure Retrace(const Was: TP3Array; const Now: TP3Array);
    var
      S, P: Integer;
      Same: Boolean;
    begin
      for S := High(Trace) downto 0 do
      begin
        if not Trace[S].Accepted or (Length(Trace[S].Pts) <> Length(Was)) then Continue;
        Same := True;
        for P := 0 to High(Was) do
          if Dist(Trace[S].Pts[P], Was[P]) > 1E-9 then begin Same := False; Break; end;
        if Same then begin Trace[S].Pts := Now; Exit; end;
      end;
    end;

    procedure Keep(const From: array of T2Array; const Lens: array of Double;
      const FromMoved: array of Boolean);
    var
      Li, P: Integer;
      Was: TP3Array;
    begin
      for Li := FromLoop to High(Loops) do
      begin
        if not FromMoved[Li] then Continue;
        Was := Loops[Li].Pts;
        SetLength(Loops[Li].Pts, Length(From[Li]));
        for P := 0 to High(From[Li]) do Loops[Li].Pts[P] := World(From[Li][P]);
        Loops[Li].LenFt := 0;
        for P := 1 to High(Loops[Li].Pts) do
          Loops[Li].LenFt := Loops[Li].LenFt + Dist(Loops[Li].Pts[P - 1], Loops[Li].Pts[P]);
        if WantTrace then Retrace(Was, Loops[Li].Pts);
      end;
    end;

    function Snapshot: TRadiantLoopArray;
    var
      Li, P: Integer;
    begin
      Result := Copy(Loops);
      for Li := FromLoop to High(Loops) do
        if Moved[Li] then
        begin
          SetLength(Result[Li].Pts, Length(Q[Li]));
          for P := 0 to High(Q[Li]) do Result[Li].Pts[P] := World(Q[Li][P]);
        end;
    end;

  begin
    if FromLoop > High(Loops) then Exit;
    { a finger is a hairpin out of a straight run and back: four bends, so
      only a long one earns them - short teeth heat little floor and are
      hard to lay }
    MinFinger := FINGER_MIN_SPACINGS * Spec.Spacing;
    { asked for (ShortFingers), fingers as short as two spacings, for round
      rooms and narrow runs where long ones find nowhere to go.  The ranking
      still weighs their bends. }
    if ShortFingers then MinFinger := FINGER_SHORT_SPACINGS * Spec.Spacing;
    SetLength(Len, Length(Loops));
    Hi := 0;
    for I := 0 to High(Loops) do
    begin
      Len[I] := Loops[I].LenFt;
      if I >= FromLoop then Hi := Max(Hi, Len[I]);
    end;
    Bare0 := RegionBare(Loops);
    BestCost := Cost(Len, Bare0); BestBare := Bare0;
    BestQ := nil; BestLen := nil;
    { shortest loops grow first, since they have the most to give and that
      closes the spread; Wild grows them in random order }
    SetLength(Order, Length(Loops) - FromLoop);
    for I := 0 to High(Order) do Order[I] := FromLoop + I;
    if Wild and (Seed <> 0) then
      for I := High(Order) downto 1 do
      begin
        RandState := Cardinal((QWord(RandState) * 1664525 + 1013904223) and $FFFFFFFF);
        J := Integer((RandState shr 8) mod Cardinal(I + 1));
        Tmp := Order[J]; Order[J] := Order[I]; Order[I] := Tmp;
      end
    else
      for I := 1 to High(Order) do
      begin
        J := I;
        while (J > 0) and (Len[Order[J - 1]] > Len[Order[J]]) do
        begin
          Tmp := Order[J]; Order[J] := Order[J - 1]; Order[J - 1] := Tmp; Dec(J);
        end;
      end;
    { grown first no longer than the longest loop, so the spread can only
      close; then to the tube's maximum, which heats more floor but can
      widen it.  Whichever costs less wins. }
    for CapTry := 0 to 1 do
    begin
      if CapTry = 0 then Cap := Hi else Cap := MaxFt;
      if (CapTry = 1) and (MaxFt <= Hi + 1E-6) then Break;
      SetLength(Q, Length(Loops));
      SetLength(Moved, Length(Loops));
      for I := 0 to High(Loops) do
      begin
        SetLength(Q[I], Length(Loops[I].Pts));
        for J := 0 to High(Loops[I].Pts) do Q[I][J] := RadiantTo2(F, Loops[I].Pts[J]);
        Len[I] := Loops[I].LenFt;
        Moved[I] := False;
      end;
      { turns pushed out first (longer straights, no new bend), then fingers,
        long ones only }
      J := 0;
      repeat
        Changed := False;
        for I := 0 to High(Order) do
          if PushOne(Order[I]) then Changed := True;
        Inc(J);
      until not Changed or (J >= 8);
      J := 0;
      if Fingers then
        repeat
          Changed := False;
          for I := 0 to High(Order) do
            if GrowOne(Order[I]) then Changed := True;
          Inc(J);
        until not Changed or (J >= 8);
      Bare0 := RegionBare(Snapshot);
      if Cost(Len, Bare0) < BestCost - 1E-6 then
      begin
        BestCost := Cost(Len, Bare0);
        BestQ := Copy(Q); BestLen := Copy(Len); BestMoved := Copy(Moved);
        for I := 0 to High(Q) do BestQ[I] := Copy(Q[I]);
        Unfilled := Unfilled - (BestBare - Bare0);
        BestBare := Bare0;
      end;
    end;
    if BestQ <> nil then Keep(BestQ, BestLen, BestMoved);
  end;


begin
  TargetFt := 0; FloorUnf := 0;
  OddSeen := False; Tightest := Spec.Spacing; RuntSeen := False; StripSeen := False;
  RandState := Seed;
  for I := 0 to 63 do
    if Seed = 0 then begin RankBudget[I] := 1; RankJit[I] := 0; end
    else
    begin
      { our own generator, so a seed means the same on every machine and build }
      RandState := Cardinal((QWord(RandState) * 1664525 + 1013904223) and $FFFFFFFF);
      RankBudget[I] := 0.9 + 0.1 * ((RandState shr 8) and $FFFF) / 65535;
      RandState := Cardinal((QWord(RandState) * 1664525 + 1013904223) and $FFFFFFFF);
      RankJit[I] := Integer((RandState shr 8) mod 5) - 2;
    end;
  { Wild: one loop of the first few cut well short to see if the next loops
    can fill in, and the loops grown into bare floor in random order (see
    GrowLoops) }
  if Wild and (Seed <> 0) then
  begin
    RandState := Cardinal((QWord(RandState) * 1664525 + 1013904223) and $FFFFFFFF);
    I := Integer((RandState shr 8) mod WILD_PINCH_RANKS);
    RandState := Cardinal((QWord(RandState) * 1664525 + 1013904223) and $FFFFFFFF);
    RankBudget[I] := WILD_PINCH_LO + (1 - WILD_PINCH_LO) * 0.5 * ((RandState shr 8) and $FFFF) / 65535;
  end;
  Result := Default(TRadiantResult);
  Result.Crossings := 0;
  { not worked out - see RadiantFriendliness }
  Result.Friendly := -1;
  Result.Why := RadiantProblem(Outline, Spec);
  Result.Ok := Result.Why = '';
  if not Result.Ok then Exit;
  MaxFt := Spec.MaxLoopFt;
  if MaxFt <= 0 then MaxFt := TubeOf(Spec.Tube).MaxLoopFt;
  Inset := EDGE_INSET_IN * Spec.Inch;

  Result.TurnActualIn := Spec.Spacing / Spec.Inch;
  Result.TurnMinIn := 2 * TubeOf(Spec.Tube).MinBendIn;
  Result.TurnMinPexAIn := 2 * TubeOf(Spec.Tube).OdIn * 6;
  Result.ObstacleCount := Length(Holes);
  NM := Length(Spec.Manifolds);
  SetLength(Result.Manifolds, NM);
  SetLength(Loops, 0);
  Unfilled := 0;
  SetLength(Pts, 64);

  for MI := 0 to NM - 1 do
  begin
    Result.Manifolds[MI].At := Spec.Manifolds[MI];
    if MI <= High(Spec.ManifoldAngles) then Result.Manifolds[MI].Heading := Spec.ManifoldAngles[MI];
    F := FrameAt(Outline, Spec.Manifolds[MI]);
    if Turn then
    begin
      SwapAxis := F.U; F.U := F.V;
      F.V := P3(-SwapAxis.X, -SwapAxis.Y, -SwapAxis.Z);
    end;
    SetLength(Poly2, Length(Outline));
    Vmin := 1E30; Vmax := -1E30; Umin := 1E30; Umax := -1E30;
    for I := 0 to High(Outline) do
    begin
      Poly2[I] := RadiantTo2(F, Outline[I]);
      Vmin := Min(Vmin, Poly2[I].Y); Vmax := Max(Vmax, Poly2[I].Y);
      Umin := Min(Umin, Poly2[I].X); Umax := Max(Umax, Poly2[I].X);
    end;
    SetLength(HolePoly, Length(Holes));
    for I := 0 to High(Holes) do
    begin
      SetLength(HolePoly[I], Length(Holes[I]));
      for J := 0 to High(Holes[I]) do HolePoly[I][J] := RadiantTo2(F, Holes[I][J]);
    end;
    FileEdges;
    if MI = 0 then
    begin
      Result.AreaSqFt := PolyArea2(Poly2);
      for I := 0 to High(HolePoly) do Result.AreaSqFt := Result.AreaSqFt - PolyArea2(HolePoly[I]);
    end;
    M2 := RadiantTo2(F, Spec.Manifolds[MI]);
    M2.Y := Max(Vmin + Inset / 2, Min(Vmax - Inset / 2, M2.Y));
    { this manifold's rows stop at the halfway lines to the others on its wall }
    LimLo := -1E300; LimHi := 1E300;
    for I := 0 to NM - 1 do
      if I <> MI then
      begin
        O2 := RadiantTo2(F, Spec.Manifolds[I]);
        if O2.X < M2.X then LimLo := Max(LimLo, (O2.X + M2.X) / 2 + Spec.Spacing / 2)
        else if O2.X > M2.X then LimHi := Min(LimHi, (O2.X + M2.X) / 2 - Spec.Spacing / 2);
      end;

    { each obstacle as its box, an inset bigger all round, so a row keeps
      off it at its end and beside it alike }
    SetLength(HoleB, Length(HolePoly));
    for I := 0 to High(HolePoly) do
    begin
      HLo := 1E300; HHi := -1E300; HV0 := 1E300; HV1 := -1E300;
      for J := 0 to High(HolePoly[I]) do
      begin
        HLo := Min(HLo, HolePoly[I][J].X); HHi := Max(HHi, HolePoly[I][J].X);
        HV0 := Min(HV0, HolePoly[I][J].Y); HV1 := Max(HV1, HolePoly[I][J].Y);
      end;
      SetLength(HoleB[I], 4);
      HoleB[I][0] := Point2(HLo - Inset, HV0 - Inset);
      HoleB[I][1] := Point2(HHi + Inset, HV0 - Inset);
      HoleB[I][2] := Point2(HHi + Inset, HV1 + Inset);
      HoleB[I][3] := Point2(HLo - Inset, HV1 + Inset);
    end;
    { the manifold need not hang on the wall it was framed from: M2.Y stays
      where it was dragged (clamped inside the floor), and LayManifold lays
      rows both ways when there is floor both ways }
    Result.RowCount := Max(1, Floor(((Vmax - Vmin) - 2 * Inset) / Spec.Spacing));
    K := Length(Loops);
    LayManifold;
    { a sweep call (Sweep <> nil) only wants what the laying saw: hand it
      back and go home }
    if Sweep <> nil then
    begin
      Sweep^.Odd := OddSeen; Sweep^.Runts := RuntSeen; Sweep^.Strips := StripSeen;
      Sweep^.Tightest := Tightest;
      Exit;
    end;
    if not Quick then
    begin
      if Hook or Pairs then HookLoops(K);
      GrowLoops(K);
    end;
    FloorUnf := FloorUnf + FloorBare(Loops);
    Inc(Result.Crossings, Meetings(K));
    Result.Manifolds[MI].LoopCount := Length(Loops) - K;
    Result.Manifolds[MI].Ports := Max(MANIFOLD_PORTS_MIN, Length(Loops) - K);
    Result.Manifolds[MI].Ft := 0;
    for I := K to High(Loops) do Result.Manifolds[MI].Ft := Result.Manifolds[MI].Ft + Loops[I].LenFt;
  end;

  Result.Loops := Loops;
  Result.Trace := Trace;
  Result.CellCount := 0;
  { reported on the fixed grid, not the rows' own - see FloorBare }
  Result.UnfilledSqFt := FloorUnf;
  Result.OddRows := OddSeen;
  Result.Runts := RuntSeen;
  Result.Strips := StripSeen;
  Result.TightestGap := Tightest;
  Result.Bends := RadiantBends(Loops, Result.StraightPct, STRAIGHT_RUN_SPACINGS * Spec.Spacing);
  Result.TotalFt := 0;
  for I := 0 to High(Loops) do Result.TotalFt := Result.TotalFt + Loops[I].LenFt;
  Result.OrderFt := Result.TotalFt * (1 + Spec.WastePct / 100);
  if Length(Loops) = 0 then
  begin
    Result.Ok := False;
    Result.Why := 'No loop fits - the floor is narrower than a run and back, or the maximum is too short.';
  end;
end;

{ how much of its floor R covers, and how far its shortest loop falls short
  of its longest on the worst manifold, both as fractions }
procedure RadiantMeasure(const R: TRadiantResult; out Cover, Spread: Double);
var
  M, L: Integer;
  Lo, Hi: Double;
begin
  if R.AreaSqFt > 0 then Cover := Max(0, 1 - R.UnfilledSqFt / R.AreaSqFt) else Cover := 0;
  Spread := 0;
  for M := 0 to High(R.Manifolds) do
  begin
    Lo := 1E300; Hi := 0;
    for L := 0 to High(R.Loops) do
      if R.Loops[L].Manifold = M then
      begin
        Lo := Min(Lo, R.Loops[L].LenFt); Hi := Max(Hi, R.Loops[L].LenFt);
      end;
    if Hi > 0 then Spread := Max(Spread, (Hi - Lo) / Hi);
  end;
end;

function RadiantSpreadFt(const R: TRadiantResult): Double;
var
  M, L: Integer;
  Lo, Hi, Worst: Double;
begin
  Result := 0; Worst := -1;
  for M := 0 to High(R.Manifolds) do
  begin
    Lo := 1E300; Hi := 0;
    for L := 0 to High(R.Loops) do
      if R.Loops[L].Manifold = M then
      begin
        Lo := Min(Lo, R.Loops[L].LenFt); Hi := Max(Hi, R.Loops[L].LenFt);
      end;
    if (Hi > 0) and ((Hi - Lo) / Hi > Worst) then
    begin
      Worst := (Hi - Lo) / Hi;
      Result := Hi - Lo;
    end;
  end;
end;

procedure RadiantFriendliness(var R: TRadiantResult; const Outline: TP3Array;
  const Holes: array of TP3Array; const Spec: TRadiantSpec);
var
  L, I, J, Rows, Bends, K: Integer;
  F: TRadiantFrame;
  U, V, D: TP3;
  Len, Best, du, dv, Near, Tol, SegU, UMin, UMax, VMin, VMax, Covered, Area, Sum: Double;
  P: T2Array;

  { the frame's own coordinates of a point: along U, along V }
  function Along(const Q: TP3): T2;
  begin
    Result.X := Dot3(P3(Q.X - F.Origin.X, Q.Y - F.Origin.Y, Q.Z - F.Origin.Z), U);
    Result.Y := Dot3(P3(Q.X - F.Origin.X, Q.Y - F.Origin.Y, Q.Z - F.Origin.Z), V);
  end;

  { the distance from Q to the nearest wall or obstacle edge }
  function ToWall(const Q: TP3): Double;
  var
    H, E: Integer;

    procedure Edge(const A, B: TP3);
    var
      T, LL: Double;
    begin
      LL := Sqr(B.X - A.X) + Sqr(B.Y - A.Y) + Sqr(B.Z - A.Z);
      if LL < 1E-12 then T := 0
      else T := Max(0, Min(1, ((Q.X - A.X) * (B.X - A.X) + (Q.Y - A.Y) * (B.Y - A.Y) + (Q.Z - A.Z) * (B.Z - A.Z)) / LL));
      Result := Min(Result, Dist(Q, P3(A.X + T * (B.X - A.X), A.Y + T * (B.Y - A.Y), A.Z + T * (B.Z - A.Z))));
    end;

  begin
    Result := 1E300;
    for E := 0 to High(Outline) do Edge(Outline[E], Outline[(E + 1) mod Length(Outline)]);
    for H := 0 to High(Holes) do
      for E := 0 to High(Holes[H]) do Edge(Holes[H][E], Holes[H][(E + 1) mod Length(Holes[H])]);
  end;

  { V into a list of distinct values, Tol apart }
  procedure Note(var List: array of Double; var N: Integer; Value: Double);
  var
    K2: Integer;
  begin
    for K2 := 0 to N - 1 do
      if Abs(List[K2] - Value) <= Tol then Exit;
    if N <= High(List) then begin List[N] := Value; Inc(N); end;
  end;

var
  NT, NL: Integer;
  TurnList, LaneList: array of Double;
  Man: TP3;
  Reach: Double;
begin
  R.Friendly := -1;
  R.LoopFriendly := nil;
  if (Length(R.Loops) = 0) or (Length(Outline) < 3) then Exit;
  F := RadiantFrameOf(Outline);
  SetLength(R.LoopFriendly, Length(R.Loops));
  { a run ending this close to a wall ran to it - or to a spacing further
    in, where the tube at the wall turns it - and needs no tape }
  Near := (EDGE_INSET_IN + 6) * Spec.Inch + Spec.Spacing;
  Sum := 0;
  for L := 0 to High(R.Loops) do
  begin
    R.LoopFriendly[L] := Default(TLoopFriendly);
    R.LoopFriendly[L].Compact := 1;
    if Length(R.Loops[L].Pts) < 2 then Continue;
    { its two directions come from its longest run; the rows' direction is
      the one with more long runs, since the longest run is often a lead }
    Best := -1; U := P3(1, 0, 0);
    for I := 1 to High(R.Loops[L].Pts) do
    begin
      Len := Dist(R.Loops[L].Pts[I - 1], R.Loops[L].Pts[I]);
      if Len > Best then
      begin
        Best := Len;
        D := R.Loops[L].Pts[I];
        U := VNorm(P3(D.X - R.Loops[L].Pts[I - 1].X, D.Y - R.Loops[L].Pts[I - 1].Y, D.Z - R.Loops[L].Pts[I - 1].Z));
      end;
    end;
    V := VNorm(Cross3(F.N, U));
    NT := 0; NL := 0;
    for I := 1 to High(R.Loops[L].Pts) do
    begin
      D := P3(R.Loops[L].Pts[I].X - R.Loops[L].Pts[I - 1].X, R.Loops[L].Pts[I].Y - R.Loops[L].Pts[I - 1].Y,
        R.Loops[L].Pts[I].Z - R.Loops[L].Pts[I - 1].Z);
      if Abs(Dot3(D, U)) >= 1.5 * Spec.Spacing then Inc(NT);
      if Abs(Dot3(D, V)) >= 1.5 * Spec.Spacing then Inc(NL);
    end;
    if NL > NT then
    begin
      D := U; U := V; V := VNorm(Cross3(F.N, U));
    end;
    SetLength(P, Length(R.Loops[L].Pts));
    for I := 0 to High(P) do P[I] := Along(R.Loops[L].Pts[I]);
    { the manifold it runs from, and how far out its breakout goes }
    if R.Loops[L].Manifold <= High(R.Manifolds) then Man := R.Manifolds[R.Loops[L].Manifold].At
    else Man := R.Loops[L].Pts[0];
    Reach := Max(R.BreakoutFt, MANIFOLD_BREAKOUT_FT) + Spec.Spacing;
    SetLength(TurnList, Length(P) * 2 + 2); SetLength(LaneList, Length(P) + 2);
    NT := 0; NL := 0;
    Rows := 0; Covered := 0;
    UMin := 1E300; UMax := -1E300; VMin := 1E300; VMax := -1E300;
    { lanes first: a lead's out and home, a spacing apart, are one measurement }
    Tol := Spec.Spacing * 1.5;
    for I := 1 to High(P) do
    begin
      du := Abs(P[I].X - P[I - 1].X); dv := Abs(P[I].Y - P[I - 1].Y);
      { a run along a wall, at the wall (a lead up the manifold's wall, a
        hook across its neighbor's rows) is laid to it and takes no tape }
      if (du < 1E-3) and (dv >= 2 * Spec.Spacing) and
         ((ToWall(R.Loops[L].Pts[I]) > Near) or (ToWall(R.Loops[L].Pts[I - 1]) > Near)) then
        Note(LaneList, NL, P[I].X);
    end;
    { then where its rows stop short of a wall }
    Tol := Spec.Spacing * 0.25;
    for I := 1 to High(P) do
    begin
      du := Abs(P[I].X - P[I - 1].X); dv := Abs(P[I].Y - P[I - 1].Y);
      { the stubs where the tubes jog out of their ports are no rows }
      if (dv < 1E-3) and (du >= 1.5 * Spec.Spacing) and
         not ((Dist(R.Loops[L].Pts[I - 1], Man) <= Reach) and (Dist(R.Loops[L].Pts[I], Man) <= Reach)) then
      begin
        Inc(Rows);
        Covered := Covered + du * Spec.Spacing;
        UMin := Min(UMin, Min(P[I].X, P[I - 1].X)); UMax := Max(UMax, Max(P[I].X, P[I - 1].X));
        VMin := Min(VMin, P[I].Y); VMax := Max(VMax, P[I].Y);
        for K := I - 1 to I do
          if ToWall(R.Loops[L].Pts[K]) > Near then
          begin
            { a row starting at its own lead is where the lead is }
            SegU := P[K].X;
            J := 0;
            while (J < NL) and (Abs(LaneList[J] - SegU) > Spec.Spacing * 1.5) do Inc(J);
            if J >= NL then Note(TurnList, NT, SegU);
          end;
      end;
    end;
    Bends := Max(0, Length(P) - 2);
    R.LoopFriendly[L].Measures := NT + NL;
    R.LoopFriendly[L].ExtraBends := Max(0, Bends - (2 * Rows + 4));
    if Rows > 0 then
    begin
      Area := (UMax - UMin) * (VMax - VMin + Spec.Spacing);
      if Area > 1E-9 then R.LoopFriendly[L].Compact := Min(1, Covered / Area);
    end;
    R.LoopFriendly[L].Score := EnsureRange(100
      - 15 * Max(0, R.LoopFriendly[L].Measures - 2)
      - 2 * R.LoopFriendly[L].ExtraBends
      - 100 * Max(0, 0.85 - R.LoopFriendly[L].Compact), 0, 100);
    Sum := Sum + R.LoopFriendly[L].Score;
  end;
  R.Friendly := Sum / Length(R.Loops);
end;

function RadiantFriendlyText(const R: TRadiantResult): string;
var
  L, Easy, Extra: Integer;
  Hard: string;
begin
  Result := '';
  if (R.Friendly < 0) or (Length(R.LoopFriendly) = 0) then Exit;
  Easy := 0; Extra := 0; Hard := '';
  for L := 0 to High(R.LoopFriendly) do
  begin
    if R.LoopFriendly[L].Measures <= 2 then Inc(Easy)
    else
    begin
      if Hard <> '' then Hard := Hard + ', ';
      Hard := Hard + Format('loop %d takes %d', [L + 1, R.LoopFriendly[L].Measures]);
    end;
    Inc(Extra, R.LoopFriendly[L].ExtraBends);
  end;
  Result := Format('installer friendly: %s/100 - %d of %d loops set out from two measurements or fewer',
    [FormatFloat('0', R.Friendly), Easy, Length(R.LoopFriendly)]);
  if Hard <> '' then Result := Result + '; ' + Hard;
  if Extra > 0 then Result := Result + Format('; %d bends past plain serpentines', [Extra]);
end;

function RadiantMaxPorts(const Spec: TRadiantSpec): Integer;
begin
  if Spec.MaxPorts >= MANIFOLD_PORTS_MIN then Result := Spec.MaxPorts else Result := MANIFOLD_PORTS_MAX;
end;

function RadiantReachPct(AreaSqFt: Double; const Spec: TRadiantSpec): Double;
var
  MaxFt: Double;
begin
  Result := 100;
  if (AreaSqFt <= 0) or (Spec.Spacing <= 0) then Exit;
  MaxFt := Spec.MaxLoopFt;
  if MaxFt <= 0 then MaxFt := TubeOf(Spec.Tube).MaxLoopFt;
  Result := Min(100, 100 * RadiantMaxPorts(Spec) * Max(1, Length(Spec.Manifolds)) * MaxFt * Spec.Spacing / AreaSqFt);
end;

function RadiantFloorArea(const Outline: TP3Array; const Holes: array of TP3Array): Double;
begin
  if Length(Outline) < 3 then Exit(0);
  Result := FloorArea(Outline, Holes, RadiantFrameOf(Outline));
end;

function RadiantReachText(AreaSqFt: Double; const Spec: TRadiantSpec; Short: Boolean = False): string;
var
  Reach, MaxFt: Double;
  Want: Integer;
begin
  Result := '';
  Reach := RadiantReachPct(AreaSqFt, Spec);
  if (Reach >= 100 - 1E-9) or (Spec.GoalCoverPct <= 0) or (Spec.GoalCoverPct <= Reach * REACH_SHARE + 1E-9) then Exit;
  MaxFt := Spec.MaxLoopFt;
  if MaxFt <= 0 then MaxFt := TubeOf(Spec.Tube).MaxLoopFt;
  Want := Ceil(AreaSqFt / Spec.Spacing / MaxFt - 1E-9);
  if Short then
    Exit(Format('Out of reach: %d loops of %s ft at %s" cover about %s%% of this floor, not %s%% - ' +
      'widen the spacing, lengthen the loop, raise the loops a manifold, or split the zone.',
      [RadiantMaxPorts(Spec) * Max(1, Length(Spec.Manifolds)), FormatFloat('0', MaxFt),
       FormatFloat('0.#', Spec.Spacing / Spec.Inch), FormatFloat('0', Reach), FormatFloat('0', Spec.GoalCoverPct)]));
  Result := Format('OUT OF REACH: %d loops of %s ft at %s" cover about %s%% of this %s sq ft floor, and the goal is %s%% - ' +
    'the whole floor wants about %d loops.  A wider spacing, a longer loop or bigger tube, more loops a manifold, ' +
    'or the zone split in two.',
    [RadiantMaxPorts(Spec) * Max(1, Length(Spec.Manifolds)), FormatFloat('0', MaxFt),
     FormatFloat('0.#', Spec.Spacing / Spec.Inch), FormatFloat('0', Reach), FormatFloat('0', AreaSqFt),
     FormatFloat('0', Spec.GoalCoverPct), Want]);
end;

function RadiantOverPorts(const R: TRadiantResult; const Spec: TRadiantSpec): Integer;
var
  M: Integer;
begin
  Result := 0;
  for M := 0 to High(R.Manifolds) do
    Result := Max(Result, R.Manifolds[M].LoopCount - RadiantMaxPorts(Spec));
end;

{ the goals met, and within the manifold: more loops than it takes is no
  layout to build, however it covers }
function RadiantMeetsGoals(const R: TRadiantResult; const Spec: TRadiantSpec): Boolean;
var
  Cover, Spread: Double;
begin
  RadiantMeasure(R, Cover, Spread);
  Result := R.Ok and (R.Crossings = 0) and (RadiantOverPorts(R, Spec) = 0) and
    ((Spec.GoalCoverPct <= 0) or (Cover * 100 >= Spec.GoalCoverPct - 1E-9)) and
    ((Spec.GoalEvenPct <= 0) or (Spread * 100 <= Spec.GoalEvenPct + 1E-9)) and
    not RadiantUnfriendly(R, Spec);
end;

function RadiantUnfriendly(const R: TRadiantResult; const Spec: TRadiantSpec): Boolean;
begin
  Result := not Spec.LessFriendly and ((Spec.GoalCoverPct > 0) or (Spec.GoalEvenPct > 0)) and
    (R.Friendly >= 0) and (Length(R.LoopFriendly) = Length(R.Loops)) and (Length(R.Loops) > 0) and
    (R.Friendly < FRIENDLY_MIN - 1E-9);
end;

{ ---------------------------------------------------------------------- }
{ the pool: layouts and their limits, laid on every core at once        }
{ ---------------------------------------------------------------------- }

constructor TRadiantGroup.Create;
begin
  inherited Create;
  FDone := RTLEventCreate;
end;

destructor TRadiantGroup.Destroy;
begin
  if FDone <> nil then RTLEventDestroy(FDone);
  inherited Destroy;
end;

procedure TLayTask.Run;
begin
  try
    Fail := '';
    R := ComputeRadiantOriented(Outline, Holes, Spec, False, T.Turn, T.Budget, T.Ranks, T.BreakFt,
      T.Seed, T.RowOff, not T.NoFingers, False, T.EvenRows, T.LoopDelta, T.ShortFingers,
      T.Fold, T.Strip, T.Wild, nil, T.Hook, T.Pairs);
    { worked out here for the ranking (see Weigh), with the try's breakout
      set first or the stubs out of the ports count as rows }
    R.BreakoutFt := T.BreakFt;
    if R.Ok then RadiantFriendliness(R, Outline, Holes, Spec);
  except
    on E: TObject do
    begin
      R := Default(TRadiantResult);
      if E is Exception then Fail := Exception(E).Message else Fail := E.ClassName;
      R.Why := Fail;
    end;
  end;
end;

procedure TSweepTask.Run;
begin
  try
    Fail := '';
    ComputeRadiantOriented(Outline, Holes, Spec, False, Turn, FirstBudget, ExtraRanks, BreakFt,
      Seed, RowOff, Fingers, False, EvenRows, LoopDelta, ShortFingers, Fold, Strip, Wild, @Sweep, False, Pairs);
  except
    on E: TObject do
      if E is Exception then Fail := Exception(E).Message else Fail := E.ClassName;
  end;
end;

constructor TRadiantWorker.Create(APool: TRadiantPool);
begin
  FPool := APool;
  FGo := RTLEventCreate;
  inherited Create(False);
end;

destructor TRadiantWorker.Destroy;
begin
  if FGo <> nil then RTLEventDestroy(FGo);
  inherited Destroy;
end;

procedure TRadiantWorker.Execute;
var
  T: TRadiantTask;
begin
  { the pool maker's FPU state, not the RTL's defaults - see FMask }
  SetExceptionMask(FPool.FMask);
  SetRoundMode(FPool.FRound);
  repeat
    T := FPool.Pop(False);
    if T <> nil then FPool.RunTask(T)
    else
    begin
      if FPool.FQuit then Break;
      { woken by Submit, and every little while anyway, so a wake that
        crossed the reset below costs a moment, never the work }
      RTLEventWaitFor(FGo, 20);
      RTLEventResetEvent(FGo);
    end;
  until FPool.FQuit;
end;

{ True when the RTL's own memory manager is in charge.  Under heaptrc (the
  Debug build) every allocation on every thread queues on one lock, and a
  big pool runs slower than one thread, so search serially there. }
function OwnHeap: Boolean;
var
  MM: TMemoryManager;
begin
  GetMemoryManager(MM);
  Result := MM.GetMem = @SysGetMem;
end;

constructor TRadiantPool.Create;
var
  Want, K: Integer;
begin
  inherited Create;
  FMask := GetExceptionMask;
  FRound := GetRoundMode;
  InitCriticalSection(FLock);
  Want := StrToIntDef(GetEnvironmentVariable('RADIANT_JOBS'), 0);
  { every core but one, left for the window and the desktop }
  if Want <= 0 then Want := TThread.ProcessorCount - 1;
  if Want < 2 then Exit;
  try
    for K := 1 to Want do
    begin
      SetLength(FWorkers, Length(FWorkers) + 1);
      FWorkers[High(FWorkers)] := TRadiantWorker.Create(Self);
    end;
  except
    { a thread that could not be made stops making more; those made are the pool }
    SetLength(FWorkers, Length(FWorkers) - 1);
  end;
end;

destructor TRadiantPool.Destroy;
var
  K: Integer;
begin
  FQuit := True;
  for K := 0 to High(FWorkers) do RTLEventSetEvent(FWorkers[K].FGo);
  for K := 0 to High(FWorkers) do
  begin
    FWorkers[K].WaitFor;
    FWorkers[K].Free;
  end;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

function TRadiantPool.Threads: Integer;
begin
  Result := Max(1, Length(FWorkers));
end;

function TRadiantPool.Pop(LeavesOnly: Boolean): TRadiantTask;
begin
  Result := nil;
  if InterLockedCompareExchange(FQueued, 0, 0) <= 0 then Exit;
  EnterCriticalSection(FLock);
  try
    if FLeafHead < Length(FLeaves) then
    begin
      Result := FLeaves[FLeafHead];
      Inc(FLeafHead);
      if FLeafHead = Length(FLeaves) then begin SetLength(FLeaves, 0); FLeafHead := 0; end;
    end
    else if not LeavesOnly and (FTaskHead < Length(FTasks)) then
    begin
      Result := FTasks[FTaskHead];
      Inc(FTaskHead);
      if FTaskHead = Length(FTasks) then begin SetLength(FTasks, 0); FTaskHead := 0; end;
    end;
    if Result <> nil then InterLockedDecrement(FQueued);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TRadiantPool.RunTask(T: TRadiantTask);
var
  G: TRadiantGroup;
begin
  G := T.FGroup;
  T.Run;
  { T's owner may free it the moment its group is done: G read first }
  if InterLockedDecrement(G.FLeft) = 0 then RTLEventSetEvent(G.FDone);
end;

procedure TRadiantPool.Submit(G: TRadiantGroup; const Ts: array of TRadiantTask);
var
  K: Integer;
begin
  if Length(Ts) = 0 then Exit;
  InterLockedExchangeAdd(G.FLeft, Length(Ts));
  EnterCriticalSection(FLock);
  try
    for K := 0 to High(Ts) do
    begin
      Ts[K].FGroup := G;
      if Ts[K].Leaf then
      begin
        SetLength(FLeaves, Length(FLeaves) + 1);
        FLeaves[High(FLeaves)] := Ts[K];
      end
      else
      begin
        SetLength(FTasks, Length(FTasks) + 1);
        FTasks[High(FTasks)] := Ts[K];
      end;
    end;
    InterLockedExchangeAdd(FQueued, Length(Ts));
  finally
    LeaveCriticalSection(FLock);
  end;
  for K := 0 to High(FWorkers) do RTLEventSetEvent(FWorkers[K].FGo);
end;

function TRadiantPool.Wait(G: TRadiantGroup; Ms: Integer; Help: Boolean): Boolean;
var
  T: TRadiantTask;
begin
  if Help then
  begin
    while InterLockedCompareExchange(G.FLeft, 0, 0) > 0 do
    begin
      T := Pop(True);
      if T <> nil then RunTask(T) else RTLEventWaitFor(G.FDone, 2);
    end;
    Exit(True);
  end;
  if InterLockedCompareExchange(G.FLeft, 0, 0) > 0 then RTLEventWaitFor(G.FDone, Ms);
  Result := InterLockedCompareExchange(G.FLeft, 0, 0) <= 0;
end;

function TRadiantPool.Spare: Boolean;
begin
  Result := InterLockedCompareExchange(FQueued, 0, 0) < Length(FWorkers);
end;

var
  { the one pool, made when a search first wants it and kept until the
    program ends (idle workers cost nothing); nil with no threads }
  SharedPool: TRadiantPool = nil;
  PoolTried: Boolean = False;

{ The program's pool, or nil - no threads in this build (RadiantThreads, the
  console tests), a heap that cannot take them (OwnHeap), or a single core.
  Nil means everything is laid on the caller's thread. }
function ThePool: TRadiantPool;
begin
  if not PoolTried then
  begin
    PoolTried := True;
    if RadiantThreads and OwnHeap then
    begin
      SharedPool := TRadiantPool.Create;
      if Length(SharedPool.FWorkers) = 0 then FreeAndNil(SharedPool);
    end;
  end;
  Result := SharedPool;
end;

function ComputeRadiantLayout(const Outline: TP3Array; const Holes: array of TP3Array;
  const Spec: TRadiantSpec; WantTrace: Boolean = False;
  Progress: TRadiantProgress = nil; Found: PRadiantResults = nil;
  LiveGoals: PRadiantGoals = nil): TRadiantResult;
var
  TurnIndex, TurnLo, TurnHi, BudgetIndex, RankTry, Done, Total, Level: Integer;
  { how many breakouts the ladder climbs - see the fixed restarts }
  Levels: Integer;
  BestRank, Cover, Spread, BreakFt, MostCover, FirstCover, LastCover: Double;
  { the program's pool (see ThePool), or nil to lay on this thread }
  Pool: TRadiantPool;
  { the layouts of a batch, or of a round laid ahead, as the pool's tasks }
  Jobs: array of TLayTask;
  BatchN, K: Integer;
  { layouts laid ahead on the pool, waiting to be asked for - see Prefetch }
  Ahead: array of TRadiantJob;
  Tries: array of TTry;
  { a way of turning the rows given up on at this breakout }
  Weak: array[0..1] of Boolean;
  { the solutions kept for the wizard (see Offer) and the tries that laid them }
  Kept: TRadiantResults;
  KeptRank: array of Double;
  KeptTry: array of TTry;
  KeptMeet: Boolean;
  Stop, Met, Probe, Goals: Boolean;
  { the random tries under way: they draw a fold rather than twin one }
  Randomly: Boolean;
  { the breakout ladder went one wider than covered the floor, for the goals }
  Wider: Boolean;
  RF, WF: TRadiantFrame;
  H: TP3;
  Best, R: TRadiantResult;
  BestTry, T: TTry;
  Seed, RandState: Cardinal;
  { the spec searched with: Spec with LiveGoals' latest goals and the cover
    goal capped at the tube's reach (see Reachable); Asked holds the goals
    as asked, which the result is judged against }
  Work, Asked: TRadiantSpec;
  { the floor's area, and the most of it the tube can cover, percent }
  AreaSq, ReachPct: Double;
  { the record: start time, what happened, and the layout that first met
    the goals }
  StartTick: QWord;
  Log: TStringArray;
  MetAt: Integer;
  { the try that last bettered the best, and how far the manifold can
    slide along its wall either way - see Slid }
  BetterAt: Integer;
  RoomBack, RoomOn: Double;
  WallDir: TP3;

  function Score(const R: TRadiantResult): Double;
  var
    M, L: Integer;
    Lo, Hi: Double;
  begin
    Result := R.UnfilledSqFt / (Work.Spacing * UNFILLED_LOOP_FT) + Length(R.Loops);
    for M := 0 to High(R.Manifolds) do
    begin
      Lo := 1E300; Hi := 0;
      for L := 0 to High(R.Loops) do
        if R.Loops[L].Manifold = M then
        begin
          Lo := Min(Lo, R.Loops[L].LenFt); Hi := Max(Hi, R.Loops[L].LenFt);
        end;
      if Hi > 0 then Result := Result + (Hi - Lo) / LOOP_EVEN_FT;
    end;
  end;

  { Lower is better.  Each goal's shortfall counts first, measured against
    that goal's own allowance so the two weigh equally; past one allowance
    floor counts 3x and spread 2x (SHORT_PAST_COVER, SHORT_PAST_EVEN) so
    neither is traded for the other.  No evenness goal: coverage counts 10x.
    Then the old cost, then a little per foot of breakout past 4 ft. }
  { a point of floor short of its goal, in points of spread - see RankOf }
  function CoverWeight: Double;
  begin
    if Work.GoalEvenPct <= 0 then Exit(10);
    Result := Work.GoalEvenPct / Max(1, 100 - Work.GoalCoverPct);
  end;

  { Over, points past a goal whose allowance is Allow: as many, and past
    the allowance Past times as many }
  function Escalated(Over, Allow, Past: Double): Double;
  begin
    Result := Min(Over, Allow) + Past * Max(0, Over - Allow);
  end;

  function RankOf(const R: TRadiantResult; BreakFt: Double): Double;
  var
    Cv, Sp, Short: Double;
  begin
    if not R.Ok or (R.Crossings > 0) then Exit(1E300);
    RadiantMeasure(R, Cv, Sp);
    Short := 0;
    if Work.GoalCoverPct > 0 then
      Short := Short + CoverWeight * Escalated(Max(0, Work.GoalCoverPct - Cv * 100),
          Max(1, 100 - Work.GoalCoverPct), IfThen(Work.GoalEvenPct > 0, SHORT_PAST_COVER, 1))
        { past the goal, bare floor still counts twice a point of evenness:
          a strip left bare along a wall is worse than loops a bit less even }
        + 2 * Min(100 - Cv * 100, 100 - Work.GoalCoverPct)
    { with no coverage goal, coverage still leads }
    else Short := Short + 10 * (100 - Cv * 100);
    if Work.GoalEvenPct > 0 then
      Short := Short + Escalated(Max(0, Sp * 100 - Work.GoalEvenPct), Work.GoalEvenPct, SHORT_PAST_EVEN);
    Result := 5 * Short + Score(R) + 0.25 * (BreakFt - MANIFOLD_BREAKOUT_FT) + BEND_WEIGHT * R.Bends;
    { and a layout that meets the goals before any that does not; the bare
      floor counted above can otherwise rank a near miss over a layout that
      meets them }
    if Goals and not RadiantMeetsGoals(R, Work) then Result := Result + GOAL_MISS;
    { more loops than the manifold takes ranks after every layout within it,
      goals or none - fewer over first }
    Result := Result + GOAL_MISS * RadiantOverPorts(R, Work);
    { and the manifold where it was put, of two otherwise alike }
    Result := Result + SHIFT_RANK_FT * Abs(R.ManifoldShiftFt);
    { and after the goals, the installer: of two alike the friendlier, and
      one under FRIENDLY_MIN after every one over it unless LessFriendly.
      Only in a watched search; Weigh works friendliness out only there. }
    if Goals and Assigned(Progress) and (R.Friendly >= 0) and (Length(R.LoopFriendly) = Length(R.Loops)) then
    begin
      Result := Result + FRIENDLY_RANK * (100 - R.Friendly);
      if RadiantUnfriendly(R, Work) then Result := Result + UNFRIENDLY_COST;
    end;
  end;

  { the goals met, however friendly: the solutions list keeps a harder
    layout that meets them, ranked after the friendly ones, so the user
    can pick it knowingly }
  function ListMeets(const R: TRadiantResult): Boolean;
  var
    Any: TRadiantSpec;
  begin
    Any := Work;
    Any.LessFriendly := True;
    Result := RadiantMeetsGoals(R, Any);
  end;

  { Keep a try among the solutions the wizard's arrows step through: every
    distinct one that meets the goals, best first, or while none has, the
    few nearest.  Two tries that lay the same layout are one solution. }
  procedure Offer(const R: TRadiantResult; Rk: Double; const T: TTry);
  var
    I, J: Integer;
    Cv, Sp, Cv2, Sp2: Double;
    Meets: Boolean;
    RF: TRadiantResult;
  begin
    if (Found = nil) or (Rk >= 1E299) then Exit;
    Meets := ListMeets(R);
    { the first to meet the goals clears out the near misses kept so far }
    if Meets and (Length(Kept) > 0) and not KeptMeet then
    begin
      SetLength(Kept, 0); SetLength(KeptRank, 0); SetLength(KeptTry, 0);
    end;
    if not Meets and KeptMeet then Exit;
    KeptMeet := KeptMeet or Meets;
    RadiantMeasure(R, Cv, Sp);
    for I := 0 to High(Kept) do
    begin
      RadiantMeasure(Kept[I], Cv2, Sp2);
      if (Length(Kept[I].Loops) = Length(R.Loops)) and (Abs(Kept[I].TotalFt - R.TotalFt) < 0.5) and
         (Abs(Cv2 - Cv) < 1E-4) then Exit;
    end;
    I := Length(Kept);
    while (I > 0) and (KeptRank[I - 1] > Rk) do Dec(I);
    if I >= SOLUTIONS_KEPT then Exit;
    SetLength(Kept, Length(Kept) + 1); SetLength(KeptRank, Length(Kept)); SetLength(KeptTry, Length(Kept));
    for J := High(Kept) downto I + 1 do
    begin
      Kept[J] := Kept[J - 1]; KeptRank[J] := KeptRank[J - 1]; KeptTry[J] := KeptTry[J - 1];
    end;
    { how friendly it is to lay, for whoever watches the list }
    RF := R;
    RadiantFriendliness(RF, Outline, Holes, Work);
    Kept[I] := RF; KeptRank[I] := Rk; KeptTry[I] := T;
    if Length(Kept) > SOLUTIONS_KEPT then
    begin
      SetLength(Kept, SOLUTIONS_KEPT); SetLength(KeptRank, SOLUTIONS_KEPT); SetLength(KeptTry, SOLUTIONS_KEPT);
    end;
  end;

  { The manifold's wall and how far it can slide either way and stay on it,
    a foot short of the ends - worked out once.  A curve is not a wall. }
  procedure FindWall;
  var
    I, J, Best_: Integer;
    D, BestD, L, Tp: Double;
    A, B, M: TP3;

    { P to Q runs on the wall's own line, the same way }
    function OnWall(const P, Q: TP3): Boolean;
    var
      Lq, Along, Across: Double;
    begin
      Lq := Dist(P, Q);
      if Lq < 1E-9 then Exit(True);
      Along := ((Q.X - P.X) * WallDir.X + (Q.Y - P.Y) * WallDir.Y + (Q.Z - P.Z) * WallDir.Z) / Lq;
      Across := Sqrt(Max(0, 1 - Sqr(Along)));
      Result := (Along > 0) and (Across * Lq < 1E-3);
    end;

  begin
    RoomBack := 0; RoomOn := 0; WallDir := P3(0, 0, 0);
    if (Length(Work.Manifolds) = 0) or Work.PinManifold then Exit;
    M := Work.Manifolds[0];
    Best_ := -1; BestD := 1E300;
    for I := 0 to High(Outline) do
    begin
      J := (I + 1) mod Length(Outline);
      A := Outline[I]; B := Outline[J];
      L := Sqr(B.X - A.X) + Sqr(B.Y - A.Y) + Sqr(B.Z - A.Z);
      if L < 1E-12 then Continue;
      Tp := Max(0, Min(1, ((M.X - A.X) * (B.X - A.X) + (M.Y - A.Y) * (B.Y - A.Y) + (M.Z - A.Z) * (B.Z - A.Z)) / L));
      D := Dist(M, P3(A.X + Tp * (B.X - A.X), A.Y + Tp * (B.Y - A.Y), A.Z + Tp * (B.Z - A.Z)));
      if D < BestD then begin BestD := D; Best_ := I; end;
    end;
    { off every wall by more than the breakout: out in the room, nothing to
      slide along }
    if (Best_ < 0) or (BestD > MANIFOLD_BREAKOUT_FT) or RadiantEdgeCurved(Outline, Best_) then Exit;
    A := Outline[Best_]; B := Outline[(Best_ + 1) mod Length(Outline)];
    L := Dist(A, B);
    WallDir := P3((B.X - A.X) / L, (B.Y - A.Y) / L, (B.Z - A.Z) / L);
    { the wall runs on through a point that is no corner, as where a line
      drawn across the floor meets it }
    I := Best_;
    for J := 1 to Length(Outline) - 2 do
    begin
      I := (I + Length(Outline) - 1) mod Length(Outline);
      if not OnWall(Outline[I], A) or RadiantEdgeCurved(Outline, I) then Break;
      A := Outline[I];
    end;
    I := (Best_ + 1) mod Length(Outline);
    for J := 1 to Length(Outline) - 2 do
    begin
      if not OnWall(B, Outline[(I + 1) mod Length(Outline)]) or RadiantEdgeCurved(Outline, I) then Break;
      I := (I + 1) mod Length(Outline);
      B := Outline[I];
    end;
    L := Dist(A, B);
    Tp := (M.X - A.X) * WallDir.X + (M.Y - A.Y) * WallDir.Y + (M.Z - A.Z) * WallDir.Z;
    RoomBack := Max(0, Tp - 1);
    RoomOn := Max(0, L - Tp - 1);
  end;

  { Where the manifold stands slid Shift feet along its wall; False when that
    would leave the floor or land in an obstacle.  A manifold sitting right
    on the wall's line may still slide: FindWall's room keeps it on the wall,
    so it is not refused as outside the floor. }
  function SlidTo(Shift: Double; out M: TP3): Boolean;
  var
    H2: Integer;
  begin
    Result := False;
    M := P3(0, 0, 0);
    if (Abs(Shift) < 1E-9) or (Length(Work.Manifolds) = 0) then Exit;
    M := Work.Manifolds[0];
    M := P3(M.X + WallDir.X * Shift, M.Y + WallDir.Y * Shift, M.Z + WallDir.Z * Shift);
    if not RadiantInside(Outline, M) and RadiantInside(Outline, Work.Manifolds[0]) then Exit;
    for H2 := 0 to High(Holes) do
      if RadiantInside(Holes[H2], M) then Exit;
    Result := True;
  end;

  { the spec with the manifold slid Shift feet along its wall, or unchanged
    where it cannot be (SlidTo) }
  function Slid(Shift: Double): TRadiantSpec;
  var
    M: TP3;
  begin
    Result := Work;
    if not SlidTo(Shift, M) then Exit;
    Result.Manifolds := Copy(Work.Manifolds);
    Result.Manifolds[0] := M;
  end;

  { how far the manifold really moved for a try slid Shift; 0 where it could
    not be }
  function Moved(Shift: Double): Double;
  var
    M: TP3;
  begin
    if SlidTo(Shift, M) then Result := Shift else Result := 0;
  end;

  procedure Note(const S: string);
  begin
    SetLength(Log, Length(Log) + 1);
    Log[High(Log)] := S;
  end;

  { The watcher changed the goals: everything kept is ranked again - the
    best, and the solutions, which keep only those that meet them once any
    does. }
  { A coverage goal past what the tube can reach is never met, so the search
    would run until stopped.  It searches for a little short of the reach
    (REACH_SHARE) instead; the result is still weighed against the goal
    asked for, and the record and ticket say why it falls short. }
  procedure Reachable;
  begin
    Asked.GoalCoverPct := Work.GoalCoverPct; Asked.GoalEvenPct := Work.GoalEvenPct;
    Asked.LessFriendly := Work.LessFriendly; Asked.NoHooks := Work.NoHooks;
    { a tube that reaches the whole floor is no limit }
    if (ReachPct < 100 - 1E-9) and (Work.GoalCoverPct > ReachPct * REACH_SHARE + 1E-9) then
    begin
      Note(Format('the coverage goal of %s%% is out of reach: the most loops a manifold, at the tube''s length ' +
        'and this spacing, cover about %s%% - searched for %s%%',
        [FormatFloat('0.#', Work.GoalCoverPct), FormatFloat('0', ReachPct),
         FormatFloat('0.#', Floor(ReachPct * REACH_SHARE))]));
      Work.GoalCoverPct := Floor(ReachPct * REACH_SHARE);
    end;
  end;

  { the watcher's goals changed since they were last read }
  function GoalsMoved: Boolean;
  begin
    Result := (LiveGoals <> nil) and ((Abs(LiveGoals^.CoverPct - Asked.GoalCoverPct) > 1E-9) or
       (Abs(LiveGoals^.EvenPct - Asked.GoalEvenPct) > 1E-9) or (LiveGoals^.LessFriendly <> Asked.LessFriendly) or
       (LiveGoals^.NoHooks <> Asked.NoHooks));
  end;

  procedure Regoal;
  var
    I, J: Integer;
    TmpR: TRadiantResult;
    TmpK: Double;
    TmpT: TTry;
  begin
    Note(Format('goals changed at layout %d: %s%% covered, loops within %s%%, was %s%% and %s%%%s',
      [Done, FormatFloat('0.#', LiveGoals^.CoverPct), FormatFloat('0.#', LiveGoals^.EvenPct),
       FormatFloat('0.#', Asked.GoalCoverPct), FormatFloat('0.#', Asked.GoalEvenPct),
       IfThen(LiveGoals^.LessFriendly <> Asked.LessFriendly,
         IfThen(LiveGoals^.LessFriendly, ' - less friendly layouts allowed', ' - friendly layouts only'), '')]));
    Work.GoalCoverPct := LiveGoals^.CoverPct;
    Work.GoalEvenPct := LiveGoals^.EvenPct;
    Work.LessFriendly := LiveGoals^.LessFriendly;
    Work.NoHooks := LiveGoals^.NoHooks;
    Reachable;
    Goals := (Work.GoalCoverPct > 0) or (Work.GoalEvenPct > 0);
    if Best.Ok then
    begin
      BestRank := RankOf(Best, BestTry.BreakFt);
      if BestTry.EvenRows and (BestRank < 1E299) then BestRank := BestRank + 1;
    end;
    for I := 0 to High(Kept) do
    begin
      KeptRank[I] := RankOf(Kept[I], Kept[I].BreakoutFt);
      if KeptTry[I].EvenRows and (KeptRank[I] < 1E299) then KeptRank[I] := KeptRank[I] + 1;
    end;
    for I := 1 to High(Kept) do
    begin
      J := I;
      while (J > 0) and (KeptRank[J - 1] > KeptRank[J]) do
      begin
        TmpR := Kept[J]; Kept[J] := Kept[J - 1]; Kept[J - 1] := TmpR;
        TmpK := KeptRank[J]; KeptRank[J] := KeptRank[J - 1]; KeptRank[J - 1] := TmpK;
        TmpT := KeptTry[J]; KeptTry[J] := KeptTry[J - 1]; KeptTry[J - 1] := TmpT;
        Dec(J);
      end;
    end;
    { one of those kept may be the best there is by the new goals }
    if (Length(Kept) > 0) and (KeptRank[0] < BestRank - 1E-6) then
    begin
      Best := Kept[0]; BestRank := KeptRank[0]; BestTry := KeptTry[0];
    end;
    KeptMeet := False;
    for I := 0 to High(Kept) do
      if ListMeets(Kept[I]) then KeptMeet := True;
    if KeptMeet then
    begin
      J := 0;
      for I := 0 to High(Kept) do
        if ListMeets(Kept[I]) then
        begin
          Kept[J] := Kept[I]; KeptRank[J] := KeptRank[I]; KeptTry[J] := KeptTry[I]; Inc(J);
        end;
      SetLength(Kept, J); SetLength(KeptRank, J); SetLength(KeptTry, J);
    end;
    if Found <> nil then Found^ := Copy(Kept);
  end;

  { look after the watcher while the pool lays: answer its window, read Stop
    and the give-up time, take up changed goals }
  procedure Pump;
  var
    S: Boolean;
  begin
    if not Assigned(Progress) then Exit;
    S := False;
    Progress(Done, Total, Best, S);
    if S then Stop := True;
    if GoalsMoved then Regoal;
  end;

  { Lay jobs 0..N-1 on the pool, waiting a short turn at a time.  With no
    workers, lay them here one by one, still a batch at a time, so a seed
    finds the same layouts either way.  Stopped part way, the rest are not
    laid and the caller weighs none of them. }
  procedure RunPool(N: Integer);
  var
    J: Integer;
    G: TRadiantGroup;
  begin
    if Pool = nil then
    begin
      for J := 0 to N - 1 do
      begin
        Jobs[J].Run;
        if LiveGoals <> nil then LiveGoals^.Laid := Done + J + 1;
        Pump;
        if Stop then Break;
      end;
      Exit;
    end;
    G := TRadiantGroup.Create;
    try
      Pool.Submit(G, TRadiantTaskArray(Copy(Jobs, 0, N)));
      while not Pool.Wait(G, POOL_WAIT_MS, False) do
      begin
        if LiveGoals <> nil then LiveGoals^.Laid := Done + N - InterLockedCompareExchange(G.FLeft, 0, 0);
        Pump;
      end;
      if LiveGoals <> nil then LiveGoals^.Laid := Done + N;
    finally
      { wait it out whatever happened - the workers write into these tasks
        until then }
      while not Pool.Wait(G, POOL_WAIT_MS, False) do ;
      G.Free;
    end;
  end;

  { A layout laid ahead for this try, if one is waiting - but not one that
    failed: the caller lays it again and it fails the usual way.  Tries are
    compared whole, and all start from Default(TTry), so padding matches. }
  function TakeAhead(const T: TTry; out R: TRadiantResult): Boolean;
  var
    I: Integer;
  begin
    Result := False;
    for I := 0 to High(Ahead) do
      if CompareMem(@Ahead[I].T, @T, SizeOf(TTry)) then
      begin
        Result := Ahead[I].Fail = '';
        if Result then R := Ahead[I].R;
        Ahead[I] := Ahead[High(Ahead)];
        SetLength(Ahead, Length(Ahead) - 1);
        Exit;
      end;
  end;

  { Laid ahead on the pool all at once: Ts, then what they could lead the
    search to ask for next (evened rows, see Twin; fold and strip, see
    FoldTwin), PREFETCH_WAVES deep.  The search still asks in its own
    order; a layout laid ahead is taken from here, one never asked for is
    dropped.  A try's layout depends only on the try, so results match. }
  procedure Prefetch(const Ts: array of TTry);
  var
    Wave, Next: array of TTry;
    W, I, J, N, From: Integer;
    T2: TTry;

    procedure Want(var List: array of TTry; var Count: Integer; const T: TTry);
    var
      K2: Integer;
    begin
      for K2 := 0 to High(Ahead) do
        if CompareMem(@Ahead[K2].T, @T, SizeOf(TTry)) then Exit;
      for K2 := 0 to Count - 1 do
        if CompareMem(@List[K2], @T, SizeOf(TTry)) then Exit;
      List[Count] := T;
      Inc(Count);
    end;

  begin
    if (Pool = nil) or Stop then Exit;
    SetLength(Wave, Length(Ts));
    N := 0;
    for I := 0 to High(Ts) do Want(Wave, N, Ts[I]);
    SetLength(Wave, N);
    for W := 0 to PREFETCH_WAVES do
    begin
      if (Length(Wave) = 0) or Stop then Break;
      From := Length(Ahead);
      I := 0;
      while I < Length(Wave) do
      begin
        N := Min(RANDOM_BATCH, Length(Wave) - I);
        for J := 0 to N - 1 do
        begin
          Jobs[J].T := Wave[I + J];
          Jobs[J].Spec := Slid(Wave[I + J].Shift);
        end;
        RunPool(N);
        SetLength(Ahead, Length(Ahead) + N);
        for J := 0 to N - 1 do
        begin
          Ahead[Length(Ahead) - N + J].T := Jobs[J].T;
          Ahead[Length(Ahead) - N + J].R := Jobs[J].R;
          Ahead[Length(Ahead) - N + J].Fail := Jobs[J].Fail;
        end;
        Inc(I, N);
      end;
      { what those could lead to }
      SetLength(Next, 4 * (Length(Ahead) - From));
      N := 0;
      for I := From to High(Ahead) do
        with Ahead[I] do
        begin
          if (Fail <> '') or not R.Ok then Continue;
          if not T.EvenRows and R.OddRows then
          begin
            T2 := T; T2.EvenRows := True; Want(Next, N, T2);
          end;
          if not (T.Fold or T.Strip or T.EvenRows or Randomly) then
          begin
            T2 := T; T2.Fold := True;
            if R.Runts then Want(Next, N, T2);
            T2 := T; T2.Strip := True;
            if R.Strips then Want(Next, N, T2);
            T2 := T; T2.Fold := True; T2.Strip := True;
            if R.Runts and R.Strips then Want(Next, N, T2);
          end;
        end;
      SetLength(Next, N);
      Wave := Next;
    end;
  end;

  function Consider(const T: TTry; out R: TRadiantResult): Boolean; forward;
  procedure Twin(const T: TTry; const R: TRadiantResult); forward;

  { A layout with a runt on a side (see Runts) laid again with that side's
    tube shared out (Fold), and both weighed: the fold changes the floor
    left for later loops, so it is a twin, not a rule.  Asked of the side as
    first laid, since growing the loops later can hide a runt.  Skipped for
    random tries and loops already within the evenness goal. }
  function FoldTwin(const T: TTry; const R: TRadiantResult): Boolean;
  var
    Cv, Sp: Double;

    procedure Lay(Fold, Strip: Boolean);
    var
      T2: TTry;
      R2: TRadiantResult;
    begin
      if Stop then Exit;
      Inc(Total);
      T2 := T;
      T2.Fold := Fold; T2.Strip := Strip;
      if Consider(T2, R2) then Twin(T2, R2);
    end;

  begin
    { a try with evened rows is a twin already, and its original's fold has
      been evened }
    if T.Fold or T.Strip or T.EvenRows or Randomly or not R.Ok or not (R.Runts or R.Strips) then Exit(not Stop);
    RadiantMeasure(R, Cv, Sp);
    if (Work.GoalEvenPct > 0) and (Sp * 100 <= Work.GoalEvenPct) then Exit(not Stop);
    { nor for a try so far short of the most floor covered that sharing out
      its loops will not bring it near }
    if Cv < MostCover - FOLD_TWIN_WITHIN then Exit(not Stop);
    { a strip behind the manifold, taken or not, is a second twin, weighed
      alone and with the fold: taking it changes every loop in front }
    if R.Runts then Lay(True, False);
    if R.Strips then Lay(False, True);
    if R.Runts and R.Strips then Lay(True, True);
    Result := not Stop;
  end;

  { one layout already laid (by Consider or the pool), kept if it is the
    best yet; returns whether to go on }
  function Weigh(const T: TTry; var R: TRadiantResult): Boolean;
  var
    Rk, Cv, Sp, Cv2, Sp2: Double;
  begin
    R.ManifoldShiftFt := Moved(T.Shift);
    R.BreakoutFt := T.BreakFt;
    { friendliness, for the ranking and the list; a worker may have worked
      it out already }
    if Goals and Assigned(Progress) and R.Ok and (Length(R.LoopFriendly) <> Length(R.Loops)) then
      RadiantFriendliness(R, Outline, Holes, Work);
    Rk := RankOf(R, T.BreakFt);
    { rows closed up at a wall are a cheat: of two as good, take the true grid }
    if T.EvenRows and (Rk < 1E299) then Rk := Rk + 1;
    { the first answer stands until a better one, so a floor with no layout
      still says why }
    if Done = 0 then Best := R;
    { A layout covering more than two points less than the most seen is not
      better, whatever else it does - measured against the most seen, so
      coverage cannot walk down two points at a time.  Unless it covers as
      much as the one kept. }
    if R.Ok and (R.Crossings = 0) then
    begin
      RadiantMeasure(R, Cv, Sp);
      RadiantMeasure(Best, Cv2, Sp2);
      if (Cv < MostCover - 0.02) and not (Best.Ok and (Cv >= Cv2 - 1E-9)) then Rk := 1E300;
      MostCover := Max(MostCover, Cv);
    end;
    R.Tries := Done + 1;
    Offer(R, Rk, T);
    { kept up to date as it goes, for a watcher to list }
    if Found <> nil then Found^ := Copy(Kept);
    if Rk < BestRank - 1E-6 then
    begin
      Best := R; BestRank := Rk; BestTry := T;
      BetterAt := Done;
      if (MetAt < 0) and Goals and RadiantMeetsGoals(Best, Work) then MetAt := Done + 1;
    end;
    Inc(Done);
    Stop := False;
    if Assigned(Progress) then Progress(Done, Total, Best, Stop);
    if GoalsMoved then Regoal;
    Result := not Stop;
    if Result then Result := FoldTwin(T, R);
  end;

  { one layout tried, kept if it is the best yet; returns whether to go on }
  function Consider(const T: TTry; out R: TRadiantResult): Boolean;
  begin
    if not TakeAhead(T, R) then
      R := ComputeRadiantOriented(Outline, Holes, Slid(T.Shift), False, T.Turn, T.Budget, T.Ranks,
        T.BreakFt, T.Seed, T.RowOff, not T.NoFingers, False, T.EvenRows, T.LoopDelta, T.ShortFingers, T.Fold, T.Strip,
        T.Wild, nil, T.Hook, T.Pairs);
    Result := Weigh(T, R);
  end;

  { A try whose rows came out odd, laid again with them evened at the far
    wall (see RowPlan) when it is short of the goals or leaves floor bare.
    Done as a twin of every try, not just the best: tried on the best alone
    it came too late, after the ladder had already gone a breakout wider. }
  procedure Twin(const T: TTry; const R: TRadiantResult);
  var
    T2: TTry;
    R2: TRadiantResult;
    Cv, Sp: Double;
  begin
    { refused for covering too little is no reason to skip: evened up, it
      covers more }
    if Stop or T.EvenRows or not R.Ok or (R.Crossings > 0) or not R.OddRows then Exit;
    RadiantMeasure(R, Cv, Sp);
    if RadiantMeetsGoals(R, Work) and (Cv >= EVEN_TRY_BELOW) then Exit;
    { nor one so far short of the best seen that a row more will not help }
    if Cv < MostCover - EVEN_TWIN_WITHIN then Exit;
    Inc(Total);
    T2 := T;
    T2.EvenRows := True;
    Consider(T2, R2);
  end;

  function Rnd: Double;
  begin
    RandState := Cardinal((QWord(RandState) * 1664525 + 1013904223) and $FFFFFFFF);
    Result := ((RandState shr 8) and $FFFFFF) / 16777216;
  end;

  { The next random try from the seed stream; each try is its seed, so the
    one kept can be laid again.  Stuck is layouts gone by without a better
    one, counted from the batch start, so a better layout mid-batch shows up
    a batch late - the same on every machine. }
  function DrawTry(Stuck: Integer): TTry;
  var
    T: TTry;
    Reach: Double;
  begin
    { seeds wrap past $FFFFFFFF (Inc would trip a debug range check), and
      seed 0 is the plain layout, not a random one }
    Seed := Cardinal((QWord(Seed) + 1) and $FFFFFFFF);
    if Seed = 0 then Seed := 1;
    RandState := Cardinal((QWord(Seed) * 2654435761) and $FFFFFFFF);
    T := Default(TTry);
    T.Turn := (TurnLo = 1) or ((TurnHi = 1) and (Rnd < 0.5));
    { a loop cut well short of the limit means one more loop and a wide
      spread, always worse, so the shares stay near the whole }
    T.Budget := 0.85 + 0.15 * Rnd;
    T.Ranks := 2 * Trunc(Rnd * 5);
    T.BreakFt := MANIFOLD_BREAKOUT_FT + 2 * Trunc(Rnd * Levels);
    T.RowOff := Trunc(Rnd * 4) * 0.25;
    T.NoFingers := Rnd < 0.25;
    T.EvenRows := Rnd < 0.5;
    { The longer nothing beats the best, the more often and further the
      manifold slides along its wall: a few feet at first, a foot more
      every SHIFT_GROW tries, never off the wall's ends. }
    if Stuck > SHIFT_AFTER then
    begin
      Reach := SHIFT_FT + Max(0, Stuck - SHIFT_AFTER) / SHIFT_GROW;
      if Rnd < 0.5 then T.Shift := -Min(RoomBack, Reach) * Rnd
      else T.Shift := Min(RoomOn, Reach) * Rnd;
      { whole inches, so a layout is laid again the same }
      T.Shift := Round(T.Shift * 12) / 12;
    end;
    { and, stuck, one or two loops more or fewer - see LoopDelta }
    if (Stuck > SHIFT_AFTER) and (Rnd < 0.4) then
    begin
      T.LoopDelta := 1 + Trunc(Rnd * 2);
      if Rnd < 0.5 then T.LoopDelta := -T.LoopDelta;
    end;
    { and, stuck, short fingers allowed - see ShortFingers }
    if (Stuck > SHIFT_AFTER) and not T.NoFingers and (Rnd < 0.4) then T.ShortFingers := True;
    { a runt's side shared out, a strip behind the manifold taken, half the
      time each - see FoldTwin }
    T.Fold := Rnd < 0.5;
    T.Strip := Rnd < 0.5;
    { and now and then something wild - see Wild }
    T.Wild := Rnd < WILD_SHARE;
    { and, stuck, the loops evened by hooks at the far wall (see HookLoops),
      tried before the manifold is moved }
    T.Hook := (Stuck > HOOK_AFTER) and (Rnd < HOOK_SHARE) and not Work.NoHooks;
    { and, where allowed, the loops laid in hooked pairs }
    T.Pairs := Work.HookPairs and (Rnd < PAIRS_SHARE);
    T.Seed := Seed;
    Result := T;
  end;

begin
  StartTick := GetTickCount64;
  Log := nil;
  MetAt := -1;
  Work := Spec;
  if LiveGoals <> nil then
  begin
    Work.GoalCoverPct := LiveGoals^.CoverPct;
    Work.GoalEvenPct := LiveGoals^.EvenPct;
    Work.LessFriendly := LiveGoals^.LessFriendly;
    Work.NoHooks := LiveGoals^.NoHooks;
  end;
  Result := Default(TRadiantResult);
  Result.Why := RadiantProblem(Outline, Work);
  if Result.Why <> '' then Exit;
  AreaSq := FloorArea(Outline, Holes, RadiantFrameOf(Outline));
  ReachPct := RadiantReachPct(AreaSq, Work);
  Asked := Work;
  Reachable;
  Ahead := nil;
  Pool := ThePool;
  SetLength(Jobs, RANDOM_BATCH);
  for K := 0 to High(Jobs) do
  begin
    Jobs[K] := TLayTask.Create;
    Jobs[K].Outline := Outline;
    SetLength(Jobs[K].Holes, Length(Holes));
    for BatchN := 0 to High(Holes) do Jobs[K].Holes[BatchN] := Holes[BatchN];
  end;
  try
  Goals := (Work.GoalCoverPct > 0) or (Work.GoalEvenPct > 0);
  { Which way the ports run.  A manifold with a heading is laid the way it
    faces; with no heading both ways are tried. }
  TurnLo := 0; TurnHi := 1;
  if (Length(Work.ManifoldAngles) > 0) and (Length(Work.Manifolds) > 0) then
  begin
    RF := RadiantFrameOf(Outline);
    WF := FrameAt(Outline, Work.Manifolds[0]);
    H := P3(RF.U.X * Cos(DegToRad(Work.ManifoldAngles[0])) + RF.V.X * Sin(DegToRad(Work.ManifoldAngles[0])),
            RF.U.Y * Cos(DegToRad(Work.ManifoldAngles[0])) + RF.V.Y * Sin(DegToRad(Work.ManifoldAngles[0])),
            RF.U.Z * Cos(DegToRad(Work.ManifoldAngles[0])) + RF.V.Z * Sin(DegToRad(Work.ManifoldAngles[0])));
    if Abs(Dot3(H, WF.U)) >= Abs(Dot3(H, WF.V)) then TurnHi := 0 else TurnLo := 1;
  end;
  Best := Default(TRadiantResult); BestRank := 1E300; MostCover := 0; BetterAt := 0;
  RoomBack := 0; RoomOn := 0; WallDir := P3(0, 0, 0);
  Kept := nil; KeptRank := nil; KeptTry := nil; KeptMeet := False;
  BestTry := Default(TTry); BestTry.Budget := 1; BestTry.BreakFt := MANIFOLD_BREAKOUT_FT;
  { How wide the breakout may go.  Tubes leave on lanes a spacing apart, two
    lanes a loop, so a breakout of B feet lets out about B / spacing loops.
    The ladder climbs as far as the manifold's most loops needs, never
    lower than BREAKOUT_LEVELS. }
  Levels := Max(BREAKOUT_LEVELS,
    Ceil((RadiantMaxPorts(Work) * Work.Spacing - MANIFOLD_BREAKOUT_FT) / 2 - 1E-9) + 1);
  Done := 0; Total := Levels * (TurnHi - TurnLo + 1) * (3 + 4); Stop := False;
  Randomly := False;

  { The fixed restarts, the breakout starting at 4 ft: every tube out on the
    grid within 4 ft of the manifold.  Where 4 ft cannot meet the goals,
    try 6, 8, on up - a floor wanting more loops than the breakout lets out
    is better closed in further out than left bare.  A first try far short
    of the floor moves straight on to the next breakout. }
  Wider := False;
  for Level := 0 to Levels - 1 do
  begin
    if Stop then Break;
    BreakFt := MANIFOLD_BREAKOUT_FT + 2 * Level;
    Probe := True;
    Weak[0] := False; Weak[1] := False; FirstCover := 0;
    { all this breakout's tries laid ahead together, budgets and ranks,
      though the ranks are used only if the first budget covers enough.
      Each pool round waits for its slowest layout, so a separate round for
      the ranks costs time (see Prefetch). }
    Ahead := nil;
    Tries := nil;
    for TurnIndex := TurnLo to TurnHi do
    begin
      for BudgetIndex := 0 to 2 do
      begin
        SetLength(Tries, Length(Tries) + 1);
        Tries[High(Tries)] := Default(TTry);
        Tries[High(Tries)].Turn := TurnIndex = 1;
        Tries[High(Tries)].Budget := 1 - BudgetIndex * 0.25;
        Tries[High(Tries)].BreakFt := BreakFt;
      end;
      for RankTry := 1 to 4 do
      begin
        SetLength(Tries, Length(Tries) + 1);
        Tries[High(Tries)] := Default(TTry);
        Tries[High(Tries)].Turn := TurnIndex = 1;
        Tries[High(Tries)].Budget := 1;
        Tries[High(Tries)].Ranks := RankTry * 2;
        Tries[High(Tries)].BreakFt := BreakFt;
      end;
    end;
    Prefetch(Tries);
    for TurnIndex := TurnLo to TurnHi do
      for BudgetIndex := 0 to 2 do
      begin
        if Stop or not Probe or Weak[TurnIndex] then Continue;
        T := Default(TTry);
        T.Turn := TurnIndex = 1; T.Budget := 1 - BudgetIndex * 0.25; T.BreakFt := BreakFt;
        if not Consider(T, R) then Break;
        if BudgetIndex = 0 then
        begin
          RadiantMeasure(R, Cover, Spread);
          if not R.Ok then Cover := 0;
          if (TurnIndex = TurnLo) and (Level < Levels - 1) and
             (Cover < Max(BREAKOUT_COVER, Work.GoalCoverPct / 100) - 0.1) then Probe := False;
          { the turned rows far behind the first way on their first try:
            skip their other tries at this breakout }
          if TurnIndex = TurnLo then FirstCover := Cover
          else if Cover < FirstCover - TURN_WEAK then Weak[TurnIndex] := True;
        end;
        if Probe then Twin(T, R);
      end;
    { A length-based estimate is only a starting point.  Shortened circuits
      and detours may need more connections, so retry with more lane ranks. }
    if Probe then
      for TurnIndex := TurnLo to TurnHi do
      begin
        if Weak[TurnIndex] then Continue;
        LastCover := -1;
        for RankTry := 1 to 4 do
        begin
          if Stop then Break;
          T := Default(TTry);
          T.Turn := TurnIndex = 1; T.Budget := 1; T.Ranks := RankTry * 2; T.BreakFt := BreakFt;
          if not Consider(T, R) then Break;
          Twin(T, R);
          if R.Ok and (R.UnfilledSqFt < R.AreaSqFt * 0.03) then Break;
          { more ranks covering less than fewer did: more will not help }
          RadiantMeasure(R, Cover, Spread);
          if not R.Ok then Cover := 0;
          if Cover < LastCover - 0.02 then Break;
          LastCover := Cover;
        end;
      end;
    { Covered from this close in: go no wider.  Coverage alone decides it;
      evenness is sought at this breakout by the tries below.  Covered but
      short of the goals, one breakout wider is still tried - the ranking
      charges for the wider breakout, so it is kept only where it does better. }
    if Best.Ok then
    begin
      RadiantMeasure(Best, Cover, Spread);
      if Cover >= IfThen(Work.GoalCoverPct > 0, Work.GoalCoverPct / 100, BREAKOUT_COVER) - 1E-9 then
      begin
        if Wider or not Goals or RadiantMeetsGoals(Best, Work) then Break;
        Wider := True;
      end;
    end;
  end;

  { The best so far laid again with the rows slid 1/4, 1/2 and 3/4 of a
    spacing.  Against a slanting wall or an obstacle that changes what is
    left bare. }
  if not Stop and Best.Ok and not RadiantMeetsGoals(Best, Work) then
  begin
    Inc(Total, 3);
    T := BestTry;
    Ahead := nil;
    SetLength(Tries, 3);
    for Level := 1 to 3 do
    begin
      Tries[Level - 1] := BestTry;
      Tries[Level - 1].RowOff := Level * 0.25;
    end;
    Prefetch(Tries);
    for Level := 1 to 3 do
    begin
      T.RowOff := Level * 0.25;
      if not Consider(T, R) then Break;
      Twin(T, R);
    end;
  end;
  { and the best laid again without fingers; where it meets the goals
    without them the ranking keeps the plainer layout }
  if not Stop and Best.Ok and not BestTry.NoFingers then
  begin
    Inc(Total);
    T := BestTry;
    T.NoFingers := True;
    Consider(T, R);
  end;
  { where hooked pairs are allowed, the best laid again as pairs, a hook
    between each two; weighed like any other }
  if not Stop and Best.Ok and Work.HookPairs and not BestTry.Pairs then
  begin
    Inc(Total);
    T := BestTry;
    T.Pairs := True;
    Consider(T, R);
  end;

  { Then, with somebody watching, random layouts until the goals are met or
    they say stop: each loop a random share of the limit (some short ones
    first), its lane nudged, breakout and row turn random.  Each layout is
    its own seed, so the one kept can be laid again exactly. }
  Met := RadiantMeetsGoals(Best, Work);
  if Assigned(Progress) and Goals and not Stop and not Met then
  begin
    Total := 0;
    { the seeds from the spec's, or from the clock - see SearchSeed }
    Seed := Work.SearchSeed;
    if Seed = 0 then
    begin
      Inc(SearchesStarted);
      { the clock's low bits and the count, mixed in 32 bits; anything wider
        trips a debug build's range check }
      Seed := Cardinal(GetTickCount64 and $FFFFFFFF) xor
        Cardinal((QWord(SearchesStarted) * 2654435761) and $FFFFFFFF);
    end;
    { widened: a Cardinal past 2^31 goes into an array of const as a
      LongInt and trips a debug build's range check }
    Note(Format('random layouts from seed %d', [Int64(Seed)]));
    FindWall;
    Randomly := True;
    { Laid RANDOM_BATCH at a time across every core (see TRadiantPool).  The
      tries are drawn from the seed in order, laid in parallel, then weighed
      here in seed order, so the result matches a one-at-a-time search.
      ComputeRadiantOriented uses only its own locals. }
    Ahead := nil;
    if Pool <> nil then
      Note(Format('%d layouts at a time across %d threads', [RANDOM_BATCH, Pool.Threads]));
    { on until the goals are met or the watcher says stop (its give-up time,
      or never) - no cap on how many layouts }
    while not Stop and not Met do
    begin
      BatchN := RANDOM_BATCH;
      for K := 0 to BatchN - 1 do
      begin
        Jobs[K].T := DrawTry(Done + K - BetterAt);
        Jobs[K].Spec := Slid(Jobs[K].T.Shift);
      end;
      RunPool(BatchN);
      { stopped while they were laid: kept as it stood }
      if Stop then Break;
      for K := 0 to BatchN - 1 do
      begin
        { a failed try loses its layout, never the search: logged and weighed
          as a layout that laid nothing.  Seed widened to Int64 - a Cardinal
          past 2^31 goes into an array of const as a LongInt and trips a
          debug build's range check. }
        if Jobs[K].Fail <> '' then
          Note(Format('layout %d (seed %d) failed: %s',
            [Done + 1, Int64(Jobs[K].T.Seed), Jobs[K].Fail]));
        if not Weigh(Jobs[K].T, Jobs[K].R) then Break;
        Met := RadiantMeetsGoals(Best, Work);
        if Met then Break;
      end;
    end;
  end;

  Result := Best;
  { Replay only the winner, so discarded tries never show as loops in the
    animation.  A normal preview allocates no trace. }
  if WantTrace and Result.Ok then
  begin
    Result := ComputeRadiantOriented(Outline, Holes, Slid(BestTry.Shift), True,
      BestTry.Turn, BestTry.Budget, BestTry.Ranks, BestTry.BreakFt, BestTry.Seed, BestTry.RowOff,
      not BestTry.NoFingers, False, BestTry.EvenRows, BestTry.LoopDelta, BestTry.ShortFingers, BestTry.Fold, BestTry.Strip,
      BestTry.Wild, nil, BestTry.Hook, BestTry.Pairs);
    Result.BreakoutFt := BestTry.BreakFt;
    Result.ManifoldShiftFt := Moved(BestTry.Shift);
  end;
  Result.Tries := Done;
  Result.ShortOfGoals := Goals and not RadiantMeetsGoals(Result, Asked);
  { the record: the goals met, and where, or not; loops forced }
  if Goals then
  begin
    if RadiantMeetsGoals(Result, Asked) and (MetAt > 0) then
      Note(Format('met the goals at layout %d', [MetAt]))
    else if RadiantMeetsGoals(Result, Work) and (MetAt > 0) then
      Note(Format('met the goals the tube can reach at layout %d', [MetAt]))
    else if not RadiantMeetsGoals(Result, Work) then
      Note(Format('short of the goals after %d layouts', [Done]));
  end;
  if BestTry.Fold then Note('a side whose last loop came out short laid again with its tube shared out');
  if BestTry.Strip then Note('the strip behind the manifold laid by the first loop in front of it');
  if BestTry.Wild then Note('a wild one: a loop cut short, the loops grown in no order');
  if BestTry.Pairs then Note('loops laid in hooked pairs: two neighbors share their rows, a hook at the far wall between them');
  if BestTry.Hook then Note('loops evened by hooks at the far wall: a loop runs on over its neighbor''s first rows, which turn short');
  if BestTry.LoopDelta <> 0 then
    Note(Format('laid with %d loop%s %s than the layout would have taken',
      [Abs(BestTry.LoopDelta), IfThen(Abs(BestTry.LoopDelta) = 1, '', 's'), IfThen(BestTry.LoopDelta > 0, 'more', 'fewer')]));
  Result.SearchSecs := (GetTickCount64 - StartTick) / 1000;
  Result.SearchLog := Copy(Log);
  RadiantFriendliness(Result, Outline, Holes, Work);
  if Found <> nil then
  begin
    for Level := 0 to High(Kept) do
    begin
      Kept[Level].Tries := Done;
      Kept[Level].ShortOfGoals := Goals and not RadiantMeetsGoals(Kept[Level], Asked);
      Kept[Level].SearchSecs := Result.SearchSecs;
      Kept[Level].SearchLog := Copy(Log);
      RadiantFriendliness(Kept[Level], Outline, Holes, Work);
    end;
    Found^ := Kept;
  end;
  finally
    { RunPool waits out every batch, so no worker is still writing into these }
    Ahead := nil;
    for K := 0 to High(Jobs) do Jobs[K].Free;
  end;
end;

function BuildRadiant(D: TWorkDoc; const Outline: TP3Array; const Holes: array of TP3Array;
  const R: TRadiantResult; const Spec: TRadiantSpec; Ink: TColor; PartName: string;
  Zone: Integer = 0): Integer;
var
  I, J, G, M, LoopG, LabelG, ManG, K: Integer;
  Mid, C, Ax, Ay: TP3;
  F: TRadiantFrame;
  Nth: TIntArray;
  Box: array[0..3] of TP3;
  Ca, Sa, W, H: Double;
  Summary: string;
const
  SX: array[0..3] of Integer = (-1, 1, 1, -1);
  SY: array[0..3] of Integer = (-1, -1, 1, 1);
begin
  Result := D.Live;
  { A zone is a group named for its system (tube, spacing, loops, footage).
    Inside it each loop is its own group, so a click takes the whole run;
    the manifold is a group, and all labels share one more group so
    "/hide labels" and "/show labels" work on them. }
  { the spacing as the trade says it - 9", not 0'-9" }
  Summary := Format('%s at %s" o.c. - %d loop%s, %s', [StringReplace(TUBE_NAMES[Spec.Tube], '  ', ' ', [rfReplaceAll]),
    FormatFloat('0.##', Spec.Spacing / Spec.Inch), Length(R.Loops), IfThen(Length(R.Loops) = 1, '', 's'),
    FormatLen(R.TotalFt, usImperial)]);
  G := D.NewPart(PartName + ' - ' + Summary, 0);
  LabelG := D.NewPart(PartName + ' labels', G);
  { unticked, the labels are there all the same, put away }
  if not Spec.Labels then D.SetPartHidden(LabelG, True);
  { The runs are reference lines (Heck "ref = true").  They draw in full but
    the region finder ignores them: a hard line would close faces with the
    floor's edges, and a soft line on a flat floor is hidden everywhere. }
  { each loop its own color (LoopInk), labeled with its number and length -
    the footage is what a fitter wants on the plan }
  SetLength(Nth, Length(R.Manifolds));
  for I := 0 to High(R.Loops) do
  begin
    M := R.Loops[I].Manifold;
    LoopG := D.NewPart(Format('Z%d L%d  %s', [Zone + M + 1, Nth[M] + 1,
      FormatLen(R.Loops[I].LenFt, usImperial)]), G);
    D.Stamp := LoopG;
    for J := 1 to High(R.Loops[I].Pts) do
      D.AddLine(R.Loops[I].Pts[J - 1], R.Loops[I].Pts[J], LoopInk(Zone + M, Nth[M]), LoopWeight(Nth[M]), True);
    if Length(R.Loops[I].Pts) > 3 then
    begin
      D.Stamp := LabelG;
      Mid := R.Loops[I].Pts[Length(R.Loops[I].Pts) div 2];
      D.AddNote(Mid, Mid, Format('Z%d L%d  %s', [Zone + M + 1, Nth[M] + 1,
        FormatLen(R.Loops[I].LenFt, usImperial)]), LoopInk(Zone + M, Nth[M]));
    end;
    Inc(Nth[M]);
  end;
  D.Stamp := LabelG;
  for I := 0 to High(Holes) do
    if Length(Holes[I]) > 0 then
    begin
      Mid := P3(0, 0, 0);
      for J := 0 to High(Holes[I]) do
        Mid := P3(Mid.X + Holes[I][J].X / Length(Holes[I]), Mid.Y + Holes[I][J].Y / Length(Holes[I]),
          Mid.Z + Holes[I][J].Z / Length(Holes[I]));
      D.AddNote(P3(Mid.X, Mid.Y, Mid.Z), Mid, 'no tube - obstacle', Ink);
    end;
  { the manifold: its box, turned the way it hangs, in its own group, with
    the zone's summary on a note beside it }
  F := RadiantFrameOf(Outline);
  for M := 0 to High(R.Manifolds) do
  begin
    ManG := D.NewPart(Format('Z%d manifold - %d loop%s', [Zone + M + 1, R.Manifolds[M].LoopCount,
      IfThen(R.Manifolds[M].LoopCount = 1, '', 's')]), G);
    D.Stamp := ManG;
    C := R.Manifolds[M].At;
    Ca := Cos(DegToRad(R.Manifolds[M].Heading)); Sa := Sin(DegToRad(R.Manifolds[M].Heading));
    Ax := P3(F.U.X * Ca + F.V.X * Sa, F.U.Y * Ca + F.V.Y * Sa, F.U.Z * Ca + F.V.Z * Sa);
    Ay := P3(-F.U.X * Sa + F.V.X * Ca, -F.U.Y * Sa + F.V.Y * Ca, -F.U.Z * Sa + F.V.Z * Ca);
    W := Spec.ManifoldW / 2; H := Spec.ManifoldH / 2;
    for K := 0 to 3 do
      Box[K] := P3(C.X + SX[K] * W * Ax.X + SY[K] * H * Ay.X,
        C.Y + SX[K] * W * Ax.Y + SY[K] * H * Ay.Y,
        C.Z + SX[K] * W * Ax.Z + SY[K] * H * Ay.Z);
    for K := 0 to 3 do
      D.AddLine(Box[K], Box[(K + 1) mod 4], ZoneInk(Zone + M), 2, True);
    D.Stamp := LabelG;
    D.AddNote(P3(C.X + F.V.X * 2, C.Y + F.V.Y * 2, C.Z + F.V.Z * 2), C,
      Format('Zone %d manifold - %s', [Zone + M + 1, Summary]),
      ZoneInk(Zone + M));
  end;
  { a wizard obstacle goes on the floor as a ring of plain lines; lying flat
    inside the face, it becomes a hole like one drawn by hand }
  D.Stamp := G;
  if Zone = 0 then
    for I := 0 to High(Spec.Extra) do
      for J := 0 to High(Spec.Extra[I]) do
        D.AddLine(Spec.Extra[I][J], Spec.Extra[I][(J + 1) mod Length(Spec.Extra[I])], Ink, 1, False);
  D.Stamp := 0;
end;

function RadiantDuration(Secs: Double): string;
var
  S: Int64;
begin
  S := Round(Max(0, Secs));
  if S < 60 then Result := Format('%d s', [S])
  else if S < 3600 then Result := Format('%d min %.2d s', [S div 60, S mod 60])
  else Result := Format('%d h %.2d min', [S div 3600, (S mod 3600) div 60]);
end;

function RadiantManifoldWallIn(Ports: Integer): Double;
begin
  Result := Ceil(2 * Max(Ports, MANIFOLD_PORTS_MIN) * MANIFOLD_PORT_PITCH_IN + MANIFOLD_ENDS_IN);
end;

function RadiantTicketText(const Spec: TRadiantSpec; const R: TRadiantResult;
  U: TUnitSystem): string;
var
  I, M: Integer;
  T: TTubeFacts;
  Ties: Integer;
  MaxFt, Cover, Spread: Double;
begin
  { World units are feet, so LenFt, TotalFt, OrderFt and MaxLoopFt need no
    converting.  Only numbers the trade says in inches (spacing, slab
    thickness) are divided by Spec.Inch. }
  T := TubeOf(Spec.Tube);
  MaxFt := Spec.MaxLoopFt;
  if MaxFt <= 0 then MaxFt := T.MaxLoopFt;
  Result := '';
  if Spec.Tag <> '' then Result := Result + Spec.Tag + LineEnding + LineEnding;
  Result := Result + 'RADIANT HEAT LAYOUT' + LineEnding;
  Result := Result + 'floor: concrete slab' + LineEnding;
  Result := Result + 'tube: ' + T.Name + ' PEX, ' + FormatFloat('0.#', Spec.Spacing / Spec.Inch) +
    '" on center' + LineEnding;
  Result := Result + 'floor area: ' + FormatArea(R.AreaSqFt, U) + LineEnding;
  Result := Result + 'loops: ' + IntToStr(Length(R.Loops)) + ', ' + FormatFloat('0', MaxFt) +
    ' ft maximum each, on ' + IntToStr(Length(R.Manifolds)) + ' manifold(s)' + LineEnding;
  for M := 0 to High(R.Manifolds) do
  begin
    Result := Result + Format('manifold %d: a %d-loop%s', [M + 1, R.Manifolds[M].Ports,
      IfThen(R.Manifolds[M].LoopCount > RadiantMaxPorts(Spec), ' - MORE LOOPS THAN THE ' +
        IntToStr(RadiantMaxPorts(Spec)) + ' A MANIFOLD IS SET TO TAKE: split the zone in two, a manifold each',
      IfThen(R.Manifolds[M].LoopCount = 0, '  - nothing near it', ''))]) + LineEnding;
    Result := Result + Format('  wall space: about %s along the wall - supply and return side by side %s" apart, ' +
      'and %s" for the valves and end caps', [FormatLen(RadiantManifoldWallIn(R.Manifolds[M].Ports) * Spec.Inch, U),
      FormatFloat('0.#', MANIFOLD_PORT_PITCH_IN), FormatFloat('0', MANIFOLD_ENDS_IN)]) + LineEnding;
    for I := 0 to High(R.Loops) do
      if R.Loops[I].Manifold = M then
        Result := Result + Format('  loop %d: %s%s', [I + 1, FormatLen(R.Loops[I].LenFt, U),
          IfThen(R.Loops[I].LenFt > MaxFt, '  - OVER the maximum for this tube', '')]) + LineEnding;
  end;
  if R.BreakoutFt > 0 then
    Result := Result + Format('breakout: every tube on the %s" grid within %s ft of its manifold%s',
      [FormatFloat('0.#', Spec.Spacing / Spec.Inch), FormatFloat('0', R.BreakoutFt),
       IfThen(R.BreakoutFt > MANIFOLD_BREAKOUT_FT + 1E-6,
         Format(' - wider than %s ft to cover the floor', [FormatFloat('0', MANIFOLD_BREAKOUT_FT)]), '')]) + LineEnding;
  { the manifold is not where it was put, so say so }
  if (Length(R.Loops) > 0) and (Abs(R.ManifoldShiftFt) > 1E-6) then
    Result := Result + Format('manifold moved %s along its wall from where it was placed, for a better layout',
      [FormatLen(Abs(R.ManifoldShiftFt), U)]) + LineEnding;
  { said, since a fitter chalking rows at the spacing would come up a row short }
  if (Length(R.Loops) > 0) and (R.TightestGap < Spec.Spacing - 1E-6) then
    Result := Result + Format('rows at the far wall closed up to %s" (from %s") so every row pairs with another',
      [FormatFloat('0.#', R.TightestGap / Spec.Inch), FormatFloat('0.#', Spec.Spacing / Spec.Inch)]) + LineEnding;
  if R.ShortOfGoals then
  begin
    RadiantMeasure(R, Cover, Spread);
    Result := Result + Format('SHORT OF THE GOALS: %s%% covered (goal %s%%), loops within %s%% (%s) (goal %s%%) - ' +
      'the best of %d layouts tried', [FormatFloat('0.0', Cover * 100), FormatFloat('0', Spec.GoalCoverPct),
      FormatFloat('0', Spread * 100), FormatLen(RadiantSpreadFt(R), U), FormatFloat('0', Spec.GoalEvenPct),
      R.Tries]) + LineEnding;
  end;
  { friendly wanted and the goals not met: say how to let it try harder }
  if R.ShortOfGoals and RadiantUnfriendly(R, Spec) then
    Result := Result + Format('LESS FRIENDLY: installer friendly %s, under the %s the search keeps to - ' +
      'tick "less friendly layouts too" in the search window to let it lay harder loops to meet the goals',
      [FormatFloat('0', R.Friendly), FormatFloat('0', FRIENDLY_MIN)]) + LineEnding;
  { a goal the tube cannot reach, said with what to change }
  if R.ShortOfGoals and (RadiantReachText(R.AreaSqFt, Spec) <> '') then
    Result := Result + RadiantReachText(R.AreaSqFt, Spec) + LineEnding;
  { the breakout lets out only so many tubes at the spacing; more loops
    than that leaves floor bare, and the fix is not here }
  if (R.BreakoutFt > 0) and (R.AreaSqFt > 0) and (R.UnfilledSqFt > R.AreaSqFt * (1 - BREAKOUT_COVER)) then
    Result := Result + Format('NOT COVERED: %s of the floor is bare - more loops than one manifold can let out ' +
      'at this spacing.  A second manifold, a bigger tube or a wider spacing.',
      [FormatArea(R.UnfilledSqFt, U)]) + LineEnding;
  if Length(R.Loops) > 0 then
    Result := Result + Format('to lay: %d bends, %s%% of the tube in straights of %s or more',
      [R.Bends, FormatFloat('0', R.StraightPct), FormatLen(STRAIGHT_RUN_SPACINGS * Spec.Spacing, U)]) + LineEnding;
  Result := Result + 'total tube, no waste: ' + FormatLen(R.TotalFt, U) + LineEnding;
  Result := Result + 'order (with ' + FormatFloat('0', Spec.WastePct) + '% waste): ' +
    FormatLen(R.OrderFt, U) + LineEnding;
  { feet x 12 = inches of run, over the tie spacing in inches }
  Ties := Round(R.TotalFt * 12 / TIE_SPACING_IN);
  Result := Result + 'ties or staples (estimate, every ' + FormatFloat('0', TIE_SPACING_IN) +
    '"): about ' + IntToStr(Ties) + LineEnding;
  Result := Result + 'manifold ports needed, all told: ' + IntToStr(Length(R.Loops)) + LineEnding;
  { The turn at a row's end is the spacing.  PEX-B and PEX-C bend to 8x
    their outside diameter, PEX-A to 6x. }
  if R.TurnActualIn < R.TurnMinPexAIn then
    Result := Result + Format('note: the %s" turn at the end of each row is tighter than ' +
      'this tube bends - PEX-A needs %s", PEX-B and PEX-C %s".  Double back (two ' +
      'interleaved passes, turning at %s") or widen the spacing.',
      [FormatFloat('0.#', R.TurnActualIn), FormatFloat('0.#', R.TurnMinPexAIn),
       FormatFloat('0.#', R.TurnMinIn), FormatFloat('0.#', 2 * R.TurnActualIn)]) + LineEnding
  else if R.TurnActualIn < R.TurnMinIn then
    Result := Result + Format('note: the %s" turn at the end of each row is fine for PEX-A ' +
      '(%s" minimum) but tighter than PEX-B or PEX-C bend (%s").',
      [FormatFloat('0.#', R.TurnActualIn), FormatFloat('0.#', R.TurnMinPexAIn),
       FormatFloat('0.#', R.TurnMinIn)]) + LineEnding;
  if R.Crossings > 0 then
    Result := Result + Format('WARNING: %d join(s) between runs, or leads, pass straight ' +
      'through an obstacle - route those by hand.', [R.Crossings]) + LineEnding;
  Result := Result + LineEnding + 'SLAB' + LineEnding;
  Result := Result + 'thickness: ' + FormatFloat('0.##', Spec.SlabThick / Spec.Inch) + '"' + LineEnding;
  Result := Result + 'tube depth: ' + IfThen(Spec.TubeDepth <= 0, 'centered in the pour',
    FormatFloat('0.##', Spec.TubeDepth / Spec.Inch) + '"') + LineEnding;
  Result := Result + 'insulation under the slab: R-' + FormatFloat('0', Spec.UnderR) + ' minimum' + LineEnding;
  if R.ObstacleCount > 0 then
    Result := Result + LineEnding + IntToStr(R.ObstacleCount) + ' obstacle(s) routed around.' + LineEnding;
  if R.UnfilledSqFt > 1 then
    Result := Result + Format('not reached: about %s - a lone row, or the far side of an obstacle', [FormatArea(R.UnfilledSqFt, U)]) + LineEnding;
  Result := Result + LineEnding + 'Flow rate and pump sizing are not worked out here - they ' +
    'come from a room-by-room heat loss, not from the tube size alone.' + LineEnding;
  { how friendly to lay }
  if (Length(R.Loops) > 0) and (Length(R.LoopFriendly) = Length(R.Loops)) then
    Result := Result + RadiantFriendlyText(R) + LineEnding;
  { the search's record, last - how long, how many, what happened }
  if R.Tries > 0 then
  begin
    Result := Result + Format('search: %d layouts tried in %s', [R.Tries, RadiantDuration(R.SearchSecs)]) + LineEnding;
    for I := 0 to High(R.SearchLog) do
      Result := Result + '  - ' + R.SearchLog[I] + LineEnding;
  end;
end;


finalization
  { the pool's workers ended with the program }
  FreeAndNil(SharedPool);

end.

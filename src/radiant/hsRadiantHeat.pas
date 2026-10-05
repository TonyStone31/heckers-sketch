unit hsRadiantHeat;

{ Heat load per radiant zone, the water flow to carry it, and the boiler to
  make it. A simplified Manual J / ASHRAE room-by-room heat loss, using what
  a slab job knows: floor and outside walls from the drawing, a few answers
  about the building, and IECC 2021 code U-factors for "up to code".
  An estimate for choosing a boiler, not a signed Manual J. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, hsDrawing, hsRadiantData, hsRadiant, hsText;

type
  { what the zone's tube is in }
  THeatUse = (huSlab, huSlabOverHeated, huJoists, huSnowMelt);
  { what is over the zone }
  THeatAbove = (haAttic, haRoof, haHeated, haBareMetal);
  { its outside walls }
  THeatWalls = (hwCode, hwOlder, hwBareMetal);
  { insulation under and round a slab }
  THeatSlabIns = (hsCode, hsEdge, hsNone);
  { what covers the floor }
  THeatCover = (hcBare, hcTile, hcVinyl, hcWood, hcCarpet);
  { how tight the building is }
  THeatTight = (htTight, htAverage, htLeaky);
  { snow melting, ASHRAE's classes }
  THeatSnow = (hsnResidential, hsnCommercial, hsnCritical);

  { an edge of a zone's outline, for its heat loss }
  THeatEdge = (heInside, heOutside, heUnheated);

  THeatZone = record
    Use: THeatUse;
    CeilingFt: Double;              { floor to ceiling }
    Above: THeatAbove;
    Walls: THeatWalls;
    Slab: THeatSlabIns;
    Cover: THeatCover;
    WindowSqFt: Double;             { glass in its outside walls, all told }
    DoorSqFt: Double;               { overhead doors in them }
    Tight: THeatTight;
    Snow: THeatSnow;
    RunIdx: Integer;                { header to boiler, one of HEAT_RUNS }
    { each edge of the zone's outline, in order - an edge another zone
      shares is inside whatever it says }
    Edges: array of THeatEdge;
  end;

  THeatJob = record
    Enabled: Boolean;               { worked out and printed at all }
    OutdoorF, IndoorF: Double;      { design temperatures }
    Climate: Integer;               { IECC climate zone, 1 to 8 }
    GlycolPct: Double;              { propylene glycol in the water }
    Dhw: Boolean;                   { the boiler makes the hot water too }
    Baths: Integer;
    AltitudeFt: Double;
    Zones: array of THeatZone;
  end;

  { what one zone needs }
  THeatZoneResult = record
    Ok: Boolean;
    AreaSqFt, OutsideFt, UnheatedFt: Double;
    { the loss, BTU an hour, by where it goes }
    Walls, Windows, Doors, Ceiling, Edge, Down, Air, Total: Double;
    PerSqFt: Double;                { the floor's output it asks for, BTU/hr sq ft }
    FloorF: Double;                 { the floor's surface at design }
    FloorMaxPerSqFt: Double;        { the most the floor gives at FLOOR_MAX_F }
    Short: Double;                  { BTU an hour the floor cannot give - supplemental heat }
    SupplyF, ReturnF, DeltaF: Double;
    Gpm: Double;                    { the zone }
    LoopGpm, LoopHeadFt: Double;    { the loop that needs the most head }
    LoopWorst: Integer;
    PipeName: string;               { header to boiler, copper }
    PipeHeadFt, RunFt: Double;
    PumpGpm, PumpHeadFt: Double;
  end;
  THeatZoneResults = array of THeatZoneResult;

  { the boiler for the lot }
  THeatBoiler = record
    Comfort, Snow, Dhw: Double;     { BTU an hour }
    DhwGpm: Double;
    Piping: Double;                 { the comfort load's share for the pipes }
    Derate: Double;                 { the altitude's, a fraction }
    Output: Double;                 { the boiler's rated output, at the least }
    OutputWithSnow: Double;         { one boiler doing the snow melt as well }
    MinFire: Double;                { the smallest comfort zone - modulate to it }
    Input: Double;                  { Output as input, at a condensing boiler's efficiency }
  end;

const
  HEAT_USE_NAMES: array[THeatUse] of string = ('Slab on grade', 'Slab over a heated space',
    'Joists with plates, over a crawlspace', 'Snow melt');
  HEAT_ABOVE_NAMES: array[THeatAbove] of string = ('Attic, insulated to code', 'Roof, insulated to code',
    'Heated space', 'Bare metal roof');
  HEAT_WALL_NAMES: array[THeatWalls] of string = ('Up to code', 'Older - R-11', 'Bare metal');
  HEAT_SLAB_NAMES: array[THeatSlabIns] of string = ('Under it all, to code', 'R-10 at the edge only', 'None');
  HEAT_COVER_NAMES: array[THeatCover] of string = ('Bare concrete', 'Tile or stone', 'Vinyl or laminate',
    'Wood', 'Carpet and pad');
  HEAT_TIGHT_NAMES: array[THeatTight] of string = ('Tight - new, sealed', 'Average', 'Leaky - old, drafty');
  HEAT_SNOW_NAMES: array[THeatSnow] of string = ('Residential walks and drives', 'Commercial',
    'Must stay clear - ramps, hospitals');
  { header to boiler, one way; the far end of each range is what gets figured }
  HEAT_RUN_NAMES: array[0..4] of string = ('Up to 20 ft', '20 to 50 ft', '50 to 75 ft', '75 to 100 ft',
    '100 to 150 ft');
  HEAT_RUNS: array[0..4] of Double = (20, 50, 75, 100, 150);

  { IECC 2021 prescriptive U-factors (Table R402.1.2) by climate zone 1..8 -
    frame walls, ceilings, fenestration, floors over unheated space }
  CODE_WALL_U: array[1..8] of Double = (0.084, 0.084, 0.060, 0.045, 0.045, 0.045, 0.045, 0.045);
  CODE_CEIL_U: array[1..8] of Double = (0.035, 0.026, 0.026, 0.024, 0.024, 0.024, 0.024, 0.024);
  CODE_WINDOW_U: array[1..8] of Double = (0.50, 0.40, 0.30, 0.30, 0.30, 0.30, 0.30, 0.30);
  CODE_FLOOR_U: array[1..8] of Double = (0.064, 0.064, 0.047, 0.047, 0.033, 0.033, 0.028, 0.028);
  { older walls, R-11 in a stud wall; a bare metal building's walls and
    roof; an insulated overhead door }
  OLDER_WALL_U = 0.090;
  BARE_METAL_U = 1.0;
  DOOR_U = 0.15;
  { air an overhead door lets by at design, cubic feet a minute a square
    foot of door }
  DOOR_LEAK_CFM = 0.5;
  { heated slab-on-grade F-factors, BTU/hr per foot of edge per degree -
    ASHRAE 90.1 appendix A, heated slabs, rounded: insulated under the
    whole of it (code, R-10 to R-15), R-10 two feet at the edge, none }
  SLAB_F_CODE = 0.45;
  SLAB_F_CODE_COLD = 0.39;          { climate zones 4 and colder: R-15 }
  SLAB_F_EDGE = 0.75;
  SLAB_F_NONE = 1.02;
  { air changes per hour, by how tight }
  TIGHT_ACH: array[THeatTight] of Double = (0.30, 0.50, 1.00);
  { floor coverings, R }
  COVER_R: array[THeatCover] of Double = (0.0, 0.05, 0.2, 0.7, 1.5);
  { snow melting, BTU/hr sq ft of surface, edges and back included }
  SNOW_RATE: array[THeatSnow] of Double = (150, 200, 300);

  { a warm floor gives the room about this much, BTU/hr sq ft for every
    degree it is warmer (EN 1264's 11 W/m2K, radiant and convective) }
  FLOOR_COEFF = 2.0;
  { the warmest a floor people stand on should be at design }
  FLOOR_MAX_F = 85.0;
  { between the water and the floor's surface, R, before the covering: a
    slab by its tube spacing, joists through their plates and subfloor }
  SLAB_R_BASE = 0.28;
  SLAB_R_PER_FT = 0.30;
  JOIST_R = 2.0;
  { the water's drop across a loop, degrees }
  DELTA_SLAB = 10.0;
  DELTA_JOIST = 20.0;
  DELTA_SNOW = 25.0;
  { the comfort load's share lost from the pipes between boiler and
    manifolds }
  PIPING_SHARE = 0.05;
  { head through a manifold, its valves and flow meters, feet }
  MANIFOLD_HEAD_FT = 3.0;
  { fittings and valves on the header run, as a share of its pipe }
  FITTINGS_SHARE = 0.5;
  { copper type L, nominal sizes, inside diameters and the most GPM each
    carries quietly - the common hydronic sizing chart, about 2 ft/s in
    the small pipe to 4 in the large }
  COPPER_NAMES: array[0..7] of string = ('1/2"', '3/4"', '1"', '1-1/4"', '1-1/2"', '2"', '2-1/2"', '3"');
  COPPER_ID_IN: array[0..7] of Double = (0.545, 0.785, 1.025, 1.265, 1.505, 1.985, 2.465, 2.945);
  COPPER_MAX_GPM: array[0..7] of Double = (1.5, 4, 8, 14, 22, 45, 75, 130);
  { a condensing boiler at radiant water temperatures }
  BOILER_EFFICIENCY = 0.95;
  { hot water for a combination boiler: gallons a minute by bathrooms,
    heated from 50 to 120 degrees }
  DHW_GPM: array[1..4] of Double = (2.5, 3.5, 4.5, 5.5);
  DHW_RISE_F = 70.0;

{ a job's first answers: the dialog's defaults }
function HeatDefaultJob: THeatJob;
function HeatDefaultZone: THeatZone;
{ feet of zone Z's edge E that another zone shares - an inside wall,
  whatever the edge says }
function HeatSharedFt(const Zones: TRadiantZones; Z, E: Integer): Double;
{ a first guess at a zone's edges: outside where another zone does not
  share it }
function HeatGuessEdges(const Zones: TRadiantZones; Z: Integer): TIntArray;
{ what zone Z needs - its layout, when it has one, for the loops' flow
  and head; Spec the zone's radiant spec }
function HeatZone(const Job: THeatJob; const Zones: TRadiantZones; Z: Integer;
  const Layout: TRadiantResult; const Spec: TRadiantSpec): THeatZoneResult;
{ the boiler for all of it }
function HeatBoiler(const Job: THeatJob; const R: THeatZoneResults): THeatBoiler;
{ the gallons a minute that carry BTU an hour at a drop of DeltaF, glycol
  counted }
function HeatGpm(Btu, DeltaF, GlycolPct: Double): Double;
{ feet of head per 100 ft of pipe of inside diameter IdIn at Gpm - Hazen
  and Williams, C for the pipe, glycol counted }
function HeatHeadPer100(Gpm, IdIn, C, GlycolPct: Double): Double;
{ a PEX tube's inside diameter, inches (ASTM F876, SDR 9) }
function HeatPexIdIn(T: TTubeSize): Double;
{ BTU an hour as the trade writes it: 21,700 }
function HeatBtu(V: Double): string;
{ zone Z's result in lines, for the dialog }
procedure HeatZoneLines(const Job: THeatJob; Z: Integer; const R: THeatZoneResult; Units: TUnitSystem;
  L: TStrings);
{ the boiler in lines }
procedure HeatBoilerLines(const Job: THeatJob; const B: THeatBoiler; L: TStrings);
{ the job and a zone as text for the settings file, and back }
function HeatJobToText(const J: THeatJob): string;
function HeatJobFromText(const S: string): THeatJob;
function HeatZoneToText(const Z: THeatZone): string;
function HeatZoneFromText(const S: string): THeatZone;

implementation

const
  PEX_ID_IN: array[TTubeSize] of Double = (0.360, 0.475, 0.574, 0.671);

function HeatDefaultJob: THeatJob;
begin
  Result := Default(THeatJob);
  Result.OutdoorF := 0;
  Result.IndoorF := 68;
  Result.Climate := 5;
  Result.GlycolPct := 0;
  Result.Baths := 2;
end;

function HeatDefaultZone: THeatZone;
begin
  Result := Default(THeatZone);
  Result.Use := huSlab;
  Result.CeilingFt := 9;
  Result.Above := haAttic;
  Result.Walls := hwCode;
  Result.Slab := hsCode;
  Result.Cover := hcBare;
  Result.Tight := htAverage;
  Result.Snow := hsnResidential;
  Result.RunIdx := 1;
end;

function HeatPexIdIn(T: TTubeSize): Double;
begin
  Result := PEX_ID_IN[T];
end;

function HeatGpm(Btu, DeltaF, GlycolPct: Double): Double;
begin
  { 500 is water's weight times its heat times sixty minutes; glycol
    carries less - about 474 at 30%, 434 at 50% }
  if DeltaF <= 0 then Exit(0);
  Result := Btu / ((500 - 1.3 * EnsureRange(GlycolPct, 0, 60)) * DeltaF);
end;

function HeatHeadPer100(Gpm, IdIn, C, GlycolPct: Double): Double;
begin
  if (Gpm <= 0) or (IdIn <= 0) then Exit(0);
  Result := 0.2083 * Power(100 / C, 1.852) * Power(Gpm, 1.852) / Power(IdIn, 4.8655);
  { thicker with glycol: half again at 50% }
  Result := Result * (1 + 0.01 * EnsureRange(GlycolPct, 0, 60));
end;

function HeatSharedFt(const Zones: TRadiantZones; Z, E: Integer): Double;
var
  A, B, C, D: TP3;
  L, T0, T1, Lo, Hi: Double;
  Dir: TP3;
  O, K: Integer;

  function Off(const P: TP3): Double;
  begin
    { how far P is from the line A-B }
    Result := Dist(P3(0, 0, 0), Cross3(Sub3(P, A), Dir));
  end;

begin
  Result := 0;
  if (Z < 0) or (Z > High(Zones)) or (Length(Zones[Z].Outline) < 3) then Exit;
  A := Zones[Z].Outline[E];
  B := Zones[Z].Outline[(E + 1) mod Length(Zones[Z].Outline)];
  L := Dist(A, B);
  if L < 1E-6 then Exit;
  Dir := P3((B.X - A.X) / L, (B.Y - A.Y) / L, (B.Z - A.Z) / L);
  for O := 0 to High(Zones) do
  begin
    if O = Z then Continue;
    for K := 0 to High(Zones[O].Outline) do
    begin
      C := Zones[O].Outline[K];
      D := Zones[O].Outline[(K + 1) mod Length(Zones[O].Outline)];
      if (Off(C) > 0.05) or (Off(D) > 0.05) then Continue;
      T0 := Dot3(Sub3(C, A), Dir);
      T1 := Dot3(Sub3(D, A), Dir);
      Lo := Max(0, Min(T0, T1)); Hi := Min(L, Max(T0, T1));
      if Hi > Lo then Result := Result + (Hi - Lo);
    end;
  end;
  Result := Min(Result, L);
end;

function HeatGuessEdges(const Zones: TRadiantZones; Z: Integer): TIntArray;
var
  E, N: Integer;
  L: Double;
begin
  Result := nil;
  if (Z < 0) or (Z > High(Zones)) then Exit;
  N := Length(Zones[Z].Outline);
  SetLength(Result, N);
  for E := 0 to N - 1 do
  begin
    L := Dist(Zones[Z].Outline[E], Zones[Z].Outline[(E + 1) mod N]);
    if L - HeatSharedFt(Zones, Z, E) > 1 then Result[E] := Ord(heOutside) else Result[E] := Ord(heInside);
  end;
end;

function HeatZone(const Job: THeatJob; const Zones: TRadiantZones; Z: Integer;
  const Layout: TRadiantResult; const Spec: TRadiantSpec): THeatZoneResult;
var
  HZ: THeatZone;
  CZ, E, N, I: Integer;
  DT, L, Free, WallU, CeilU, F, WallArea, Up, Rsys, AvgF, Ft, LoopG, H, Run, Pipe: Double;
  Edge: THeatEdge;
begin
  Result := Default(THeatZoneResult);
  Result.LoopWorst := -1;
  if (Z < 0) or (Z > High(Zones)) or (Z > High(Job.Zones)) or (Length(Zones[Z].Outline) < 3) then Exit;
  HZ := Job.Zones[Z];
  CZ := EnsureRange(Job.Climate, 1, 8);
  DT := Max(0, Job.IndoorF - Job.OutdoorF);
  if Layout.Ok and (Layout.AreaSqFt > 0) then Result.AreaSqFt := Layout.AreaSqFt
  else Result.AreaSqFt := RadiantFloorArea(Zones[Z].Outline, Zones[Z].Holes);
  if Result.AreaSqFt <= 0 then Exit;
  Result.Ok := True;

  { the outside walls, and those to a space not heated, less what
    another zone shares }
  N := Length(Zones[Z].Outline);
  for E := 0 to N - 1 do
  begin
    if E <= High(HZ.Edges) then Edge := HZ.Edges[E] else Edge := heInside;
    if Edge = heInside then Continue;
    L := Dist(Zones[Z].Outline[E], Zones[Z].Outline[(E + 1) mod N]);
    Free := Max(0, L - HeatSharedFt(Zones, Z, E));
    if Edge = heOutside then Result.OutsideFt := Result.OutsideFt + Free
    else Result.UnheatedFt := Result.UnheatedFt + Free;
  end;

  if HZ.Use = huSnowMelt then
  begin
    { a rate over the surface, not a loss: the class's, edges and the
      back of the slab in it }
    Result.Total := SNOW_RATE[HZ.Snow] * Result.AreaSqFt;
    Result.PerSqFt := SNOW_RATE[HZ.Snow];
    Result.DeltaF := DELTA_SNOW;
    { a slab melting snow runs its water near 32 + half a degree for
      every BTU/hr sq ft, then the drop's half above that }
    AvgF := 32 + 0.5 * Result.PerSqFt;
    Result.SupplyF := Min(140, AvgF + Result.DeltaF / 2);
    Result.ReturnF := Result.SupplyF - Result.DeltaF;
    Result.FloorF := 33;
  end
  else
  begin
    case HZ.Walls of
      hwCode: WallU := CODE_WALL_U[CZ];
      hwOlder: WallU := OLDER_WALL_U;
    else WallU := BARE_METAL_U;
    end;
    case HZ.Above of
      haAttic, haRoof: CeilU := CODE_CEIL_U[CZ];
      haHeated: CeilU := 0;
    else CeilU := BARE_METAL_U;
    end;
    { windows and doors come out of the outside walls first }
    WallArea := Max(0, Result.OutsideFt * HZ.CeilingFt - HZ.WindowSqFt - HZ.DoorSqFt);
    Result.Walls := WallU * WallArea * DT + WallU * Result.UnheatedFt * HZ.CeilingFt * DT / 2;
    Result.Windows := CODE_WINDOW_U[CZ] * HZ.WindowSqFt * DT;
    Result.Doors := DOOR_U * HZ.DoorSqFt * DT + 1.08 * DOOR_LEAK_CFM * HZ.DoorSqFt * DT;
    Result.Ceiling := CeilU * Result.AreaSqFt * DT;
    Result.Air := 0.018 * TIGHT_ACH[HZ.Tight] * Result.AreaSqFt * HZ.CeilingFt * DT;
    if HZ.Use = huSlab then
    begin
      case HZ.Slab of
        hsCode: if CZ >= 4 then F := SLAB_F_CODE_COLD else F := SLAB_F_CODE;
        hsEdge: F := SLAB_F_EDGE;
      else F := SLAB_F_NONE;
      end;
      Result.Edge := F * (Result.OutsideFt + Result.UnheatedFt) * DT;
    end
    else if HZ.Use = huJoists then
      { joists over a basement or crawlspace not heated: its floor
        insulated to code, the space half way between in and out }
      Result.Down := CODE_FLOOR_U[CZ] * Result.AreaSqFt * DT / 2;
    Result.Total := Result.Walls + Result.Windows + Result.Doors + Result.Ceiling + Result.Air +
      Result.Edge + Result.Down;
    { what the floor has to give the room - the edge and down go to the
      ground, not the room, but the water carries them all }
    Up := (Result.Total - Result.Edge - Result.Down) / Result.AreaSqFt;
    Result.PerSqFt := Up;
    Result.FloorMaxPerSqFt := FLOOR_COEFF * (FLOOR_MAX_F - Job.IndoorF);
    Result.Short := Max(0, Up - Result.FloorMaxPerSqFt) * Result.AreaSqFt;
    Result.FloorF := Job.IndoorF + Min(Up, Result.FloorMaxPerSqFt) / FLOOR_COEFF;
    if HZ.Use = huJoists then
    begin
      Rsys := JOIST_R;
      Result.DeltaF := DELTA_JOIST;
    end
    else
    begin
      Rsys := SLAB_R_BASE + SLAB_R_PER_FT * Spec.Spacing;
      Result.DeltaF := DELTA_SLAB;
    end;
    AvgF := Result.FloorF + Min(Up, Result.FloorMaxPerSqFt) * (Rsys + COVER_R[HZ.Cover]);
    Result.SupplyF := AvgF + Result.DeltaF / 2;
    Result.ReturnF := AvgF - Result.DeltaF / 2;
  end;

  { the water: the zone's flow, shared out over its loops by their
    length - each heats the floor it covers - and the head of the one
    that needs the most }
  Result.Gpm := HeatGpm(Result.Total, Result.DeltaF, Job.GlycolPct);
  Ft := 0;
  if Layout.Ok then
    for I := 0 to High(Layout.Loops) do Ft := Ft + Layout.Loops[I].LenFt;
  if Ft > 0 then
    for I := 0 to High(Layout.Loops) do
    begin
      LoopG := Result.Gpm * Layout.Loops[I].LenFt / Ft;
      H := HeatHeadPer100(LoopG, HeatPexIdIn(Spec.Tube), 150, Job.GlycolPct) * Layout.Loops[I].LenFt / 100;
      if H > Result.LoopHeadFt then
      begin
        Result.LoopHeadFt := H; Result.LoopGpm := LoopG; Result.LoopWorst := I;
      end;
    end;
  { the header's supply and return to the boiler: the smallest copper that
    carries the flow quietly (COPPER_MAX_GPM), and its head there and back
    with its fittings }
  Run := HEAT_RUNS[EnsureRange(HZ.RunIdx, 0, High(HEAT_RUNS))];
  Result.RunFt := Run;
  Result.PipeName := COPPER_NAMES[High(COPPER_NAMES)];
  Pipe := COPPER_ID_IN[High(COPPER_ID_IN)];
  for I := 0 to High(COPPER_ID_IN) do
  begin
    if Result.Gpm <= COPPER_MAX_GPM[I] then
    begin
      Result.PipeName := COPPER_NAMES[I];
      Pipe := COPPER_ID_IN[I];
      Break;
    end;
  end;
  Result.PipeHeadFt := HeatHeadPer100(Result.Gpm, Pipe, 140, Job.GlycolPct) * 2 * Run / 100 * (1 + FITTINGS_SHARE);
  Result.PumpGpm := Result.Gpm;
  Result.PumpHeadFt := Result.LoopHeadFt + Result.PipeHeadFt + MANIFOLD_HEAD_FT;
end;

function HeatBoiler(const Job: THeatJob; const R: THeatZoneResults): THeatBoiler;
var
  Z: Integer;
begin
  Result := Default(THeatBoiler);
  Result.MinFire := 0;
  for Z := 0 to High(R) do
  begin
    if not R[Z].Ok then Continue;
    if (Z <= High(Job.Zones)) and (Job.Zones[Z].Use = huSnowMelt) then
      Result.Snow := Result.Snow + R[Z].Total
    else
    begin
      Result.Comfort := Result.Comfort + R[Z].Total;
      if (Result.MinFire = 0) or (R[Z].Total < Result.MinFire) then Result.MinFire := R[Z].Total;
    end;
  end;
  Result.Piping := Result.Comfort * PIPING_SHARE;
  if Job.Dhw then
  begin
    Result.DhwGpm := DHW_GPM[EnsureRange(Job.Baths, 1, 4)];
    Result.Dhw := 500 * Result.DhwGpm * DHW_RISE_F;
  end;
  { past 2,000 ft a gas boiler gives about 4% less for every 1,000 }
  Result.Derate := Max(0, (Job.AltitudeFt - 2000) / 1000 * 0.04);
  Result.Output := Max(Result.Comfort + Result.Piping, Result.Dhw) / (1 - Min(0.5, Result.Derate));
  Result.OutputWithSnow := Max(Result.Comfort + Result.Piping + Result.Snow, Result.Dhw) /
    (1 - Min(0.5, Result.Derate));
  Result.Input := Result.Output / BOILER_EFFICIENCY;
end;

function HeatBtu(V: Double): string;
begin
  Result := FormatFloat('#,##0', Round(V / 10) * 10);
end;

procedure HeatZoneLines(const Job: THeatJob; Z: Integer; const R: THeatZoneResult; Units: TUnitSystem;
  L: TStrings);
var
  Snow: Boolean;
begin
  if not R.Ok then begin L.Add('No floor to work out.'); Exit; end;
  Snow := (Z <= High(Job.Zones)) and (Job.Zones[Z].Use = huSnowMelt);
  if Snow then
  begin
    L.Add(Format('Snow melt, %s', [FormatArea(R.AreaSqFt, Units)]));
    L.Add(Format('  %s BTU/hr sq ft', [FormatFloat('0', R.PerSqFt)]));
    L.Add(Format('  Load       %9s BTU/hr', [HeatBtu(R.Total)]));
  end
  else
  begin
    L.Add(Format('Heat loss at %s F outside', [FormatFloat('0', Job.OutdoorF)]));
    L.Add(Format('  Floor %s, outside walls %s', [FormatArea(R.AreaSqFt, Units), FormatLen(R.OutsideFt, Units)]));
    if R.UnheatedFt > 0 then L.Add(Format('  to unheated space %s', [FormatLen(R.UnheatedFt, Units)]));
    L.Add(Format('  Walls      %9s', [HeatBtu(R.Walls)]));
    L.Add(Format('  Windows    %9s', [HeatBtu(R.Windows)]));
    if R.Doors > 0 then L.Add(Format('  Doors      %9s', [HeatBtu(R.Doors)]));
    L.Add(Format('  Ceiling    %9s', [HeatBtu(R.Ceiling)]));
    if R.Edge > 0 then L.Add(Format('  Slab edge  %9s', [HeatBtu(R.Edge)]));
    if R.Down > 0 then L.Add(Format('  Floor down %9s', [HeatBtu(R.Down)]));
    L.Add(Format('  Air        %9s', [HeatBtu(R.Air)]));
    L.Add(Format('  Total      %9s BTU/hr', [HeatBtu(R.Total)]));
    L.Add(Format('  Floor gives %s BTU/hr sq ft at %s F', [FormatFloat('0.0', R.PerSqFt), FormatFloat('0', R.FloorF)]));
    if R.Short > 0 then
      L.Add(Format('  SHORT %s BTU/hr - past %s BTU/hr sq ft the floor cannot give; supplemental heat',
        [HeatBtu(R.Short), FormatFloat('0', R.FloorMaxPerSqFt)]));
  end;
  L.Add(Format('Water %s F out, %s F back', [FormatFloat('0', R.SupplyF), FormatFloat('0', R.ReturnF)]));
  L.Add(Format('  %s GPM', [FormatFloat('0.0', R.Gpm)]));
  if R.LoopWorst >= 0 then
    L.Add(Format('  Loop %d: %s GPM, %s ft head', [R.LoopWorst + 1, FormatFloat('0.00', R.LoopGpm),
      FormatFloat('0.0', R.LoopHeadFt)]))
  else L.Add('  (no layout yet - search the zone for the loops'' head)');
  L.Add(Format('To the boiler: %s copper, %s ft', [R.PipeName, FormatFloat('0', R.RunFt)]));
  L.Add(Format('Pump: %s GPM at %s ft', [FormatFloat('0.0', R.PumpGpm), FormatFloat('0.0', R.PumpHeadFt)]));
end;

procedure HeatBoilerLines(const Job: THeatJob; const B: THeatBoiler; L: TStrings);
begin
  L.Add('The boiler, all zones');
  L.Add(Format('  Heating    %9s', [HeatBtu(B.Comfort)]));
  L.Add(Format('  Piping     %9s', [HeatBtu(B.Piping)]));
  if Job.Dhw then L.Add(Format('  Hot water  %9s (%s GPM)', [HeatBtu(B.Dhw), FormatFloat('0.0', B.DhwGpm)]));
  if B.Derate > 0 then L.Add(Format('  Altitude   -%s%%', [FormatFloat('0', B.Derate * 100)]));
  L.Add(Format('  Output at least %s BTU/hr', [HeatBtu(B.Output)]));
  L.Add(Format('  Input about %s BTU/hr', [HeatBtu(B.Input)]));
  if B.MinFire > 0 then L.Add(Format('  Modulating down to %s or less', [HeatBtu(B.MinFire)]));
  if B.Snow > 0 then
  begin
    L.Add(Format('  Snow melt  %9s', [HeatBtu(B.Snow)]));
    L.Add(Format('  One boiler for both: %s', [HeatBtu(B.OutputWithSnow)]));
  end;
end;

{ text: key=value pairs, ';' between; a zone's edges as digits }

function KeyNum(const S, Key: string; Def: Double): Double;
var
  Parts: TStringArray;
  I: Integer;
begin
  Result := Def;
  Parts := S.Split([';']);
  for I := 0 to High(Parts) do
    if AnsiStartsStr(Key + '=', Parts[I]) then
      Exit(StrToFloatDef(Copy(Parts[I], Length(Key) + 2, MaxInt), Def, DotFS));
end;

function Str_(const S, Key: string): string;
var
  Parts: TStringArray;
  I: Integer;
begin
  Result := '';
  Parts := S.Split([';']);
  for I := 0 to High(Parts) do
    if AnsiStartsStr(Key + '=', Parts[I]) then Exit(Copy(Parts[I], Length(Key) + 2, MaxInt));
end;

function Num(V: Double): string;
begin
  Result := FloatToStr(V, DotFS);
end;

function HeatJobToText(const J: THeatJob): string;
begin
  Result := Format('on=%d;out=%s;in=%s;cz=%d;gly=%s;dhw=%d;baths=%d;alt=%s',
    [Ord(J.Enabled), Num(J.OutdoorF), Num(J.IndoorF), J.Climate, Num(J.GlycolPct), Ord(J.Dhw), J.Baths,
     Num(J.AltitudeFt)]);
end;

function HeatJobFromText(const S: string): THeatJob;
begin
  Result := HeatDefaultJob;
  if S = '' then Exit;
  Result.Enabled := KeyNum(S, 'on', 0) <> 0;
  Result.OutdoorF := KeyNum(S, 'out', Result.OutdoorF);
  Result.IndoorF := KeyNum(S, 'in', Result.IndoorF);
  Result.Climate := EnsureRange(Round(KeyNum(S, 'cz', Result.Climate)), 1, 8);
  Result.GlycolPct := EnsureRange(KeyNum(S, 'gly', 0), 0, 60);
  Result.Dhw := KeyNum(S, 'dhw', 0) <> 0;
  Result.Baths := EnsureRange(Round(KeyNum(S, 'baths', Result.Baths)), 1, 8);
  Result.AltitudeFt := Max(0, KeyNum(S, 'alt', 0));
end;

function HeatZoneToText(const Z: THeatZone): string;
var
  E: string;
  I: Integer;
begin
  E := '';
  for I := 0 to High(Z.Edges) do E := E + IntToStr(Ord(Z.Edges[I]));
  Result := Format('use=%d;ceil=%s;above=%d;walls=%d;slab=%d;cover=%d;win=%s;door=%s;tight=%d;snow=%d;run=%d;edges=%s',
    [Ord(Z.Use), Num(Z.CeilingFt), Ord(Z.Above), Ord(Z.Walls), Ord(Z.Slab), Ord(Z.Cover), Num(Z.WindowSqFt),
     Num(Z.DoorSqFt), Ord(Z.Tight), Ord(Z.Snow), Z.RunIdx, E]);
end;

function HeatZoneFromText(const S: string): THeatZone;
var
  E: string;
  I: Integer;
begin
  Result := HeatDefaultZone;
  if S = '' then Exit;
  Result.Use := THeatUse(EnsureRange(Round(KeyNum(S, 'use', 0)), 0, Ord(High(THeatUse))));
  Result.CeilingFt := EnsureRange(KeyNum(S, 'ceil', Result.CeilingFt), 0, 100);
  Result.Above := THeatAbove(EnsureRange(Round(KeyNum(S, 'above', 0)), 0, Ord(High(THeatAbove))));
  Result.Walls := THeatWalls(EnsureRange(Round(KeyNum(S, 'walls', 0)), 0, Ord(High(THeatWalls))));
  Result.Slab := THeatSlabIns(EnsureRange(Round(KeyNum(S, 'slab', 0)), 0, Ord(High(THeatSlabIns))));
  Result.Cover := THeatCover(EnsureRange(Round(KeyNum(S, 'cover', 0)), 0, Ord(High(THeatCover))));
  Result.WindowSqFt := Max(0, KeyNum(S, 'win', 0));
  Result.DoorSqFt := Max(0, KeyNum(S, 'door', 0));
  Result.Tight := THeatTight(EnsureRange(Round(KeyNum(S, 'tight', 1)), 0, Ord(High(THeatTight))));
  Result.Snow := THeatSnow(EnsureRange(Round(KeyNum(S, 'snow', 0)), 0, Ord(High(THeatSnow))));
  Result.RunIdx := EnsureRange(Round(KeyNum(S, 'run', 1)), 0, High(HEAT_RUNS));
  E := Str_(S, 'edges');
  SetLength(Result.Edges, Length(E));
  for I := 1 to Length(E) do
    Result.Edges[I - 1] := THeatEdge(EnsureRange(Ord(E[I]) - Ord('0'), 0, Ord(High(THeatEdge))));
end;

end.

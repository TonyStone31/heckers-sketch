unit hsRadiantSubmittal;

{ A radiant layout as a submittal, for whoever approves the job and whoever
  lays the tube: system summary, zone and loop schedules, material list,
  plans, and each zone's search record.  Content only, in blocks, so each
  writer lays it out for its own page.  Plans are in feet, east along X,
  north along Y. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, Types, Graphics, hsDrawing, hsRadiantData, hsRadiant, hsRadiantHeat;

type
  { everything the wizard knows about the job }
  TRadiantJob = record
    Title: string;                     { the tag, or none }
    When: TDateTime;
    Made: string;                      { the program and its version }
    Units: TUnitSystem;
    Spec: TRadiantSpec;                { as searched, its goals included }
    ZoneSpecs: array of TRadiantSpec;  { each zone's own: its manifold, heading }
    Zones: TRadiantZones;
    Searched: array of Boolean;
    Layouts: TRadiantResults;          { the layout each zone will build }
    Solutions: array of TRadiantResults; { what each zone's search kept }
    Picked: TIntArray;                 { which of those is the layout }
    ZoneNames: TStringArray;           { each zone's name, '' for none }
    { the heat load, when one is set (Heat.Enabled); with none, the
      submittal says nothing about heat }
    Heat: THeatJob;
    { what the wizard needs to reopen the job that the submittal does not:
      each manifold's angle in the wizard's plan (ZoneSpecs has it in the
      zone's own frame), which manifolds are pinned, and shapes left out }
    Angles: array of Double;
    Pins: array of Boolean;
    LeftOut: TRadiantZones;
  end;

  { skLoopPlans: zone Zone's loops, one drawing to a page }
  TSubmittalKind = (skTitle, skHeading, skPara, skTable, skPlan, skPageBreak, skLoopPlans);
  TSubmittalBlock = record
    Kind: TSubmittalKind;
    Text: string;                      { title, heading, paragraph, a plan's caption }
    Cols: TStringArray;                { a table's column heads }
    Rows: array of TStringArray;
    Zone: Integer;                     { a plan's zone, -1 for all of them }
    { a half-page table: two in a row sit side by side }
    Half: Boolean;
  end;
  TSubmittalBlocks = array of TSubmittalBlock;

  TPlanStrokeKind = (psWall, psHole, psLoop, psManifold);
  TPlanStroke = record
    Kind: TPlanStrokeKind;
    Pts: T2Array;                      { feet, east along X, north along Y }
    Closed: Boolean;
    Color: TColor;
    WeightMM: Double;                  { how heavy on paper }
    { another zone's, drawn faint around the one shown: not counted in
      the plan's extent, and clipped at the plan's box }
    Context: Boolean;
  end;
  TPlanStrokes = array of TPlanStroke;
  { A dimension in plan feet from A to B with its words. With Ext, the line
    is drawn clear of what it measures, with extension lines from FromA to A
    and FromB to B. }
  TPlanDim = record
    A, B: T2;
    Text: string;
    Ext: Boolean;
    FromA, FromB: T2;
  end;
  TPlanDims = array of TPlanDim;
  TPlanLabel = record
    At: T2;
    Text: string;
    Color: TColor;
    { a loop's tag, drawn off the plan with a leader to the loop rather
      than at At; Loop is the loop's points, to find where }
    Tag: Boolean;
    Loop: T2Array;
  end;
  TPlanLabels = array of TPlanLabel;

function RadiantSubmittal(const Job: TRadiantJob): TSubmittalBlocks;
{ "Zone 2", or "Zone 2 - Kitchen" }
function ZoneTitleOf(const Job: TRadiantJob; Z: Integer): string;
{ The plan of zone Zone, or every zone with -1: walls, obstacles, each loop
  in its own ink, the manifold as a box, and where the zone and manifold
  names go. }
procedure RadiantPlanStrokes(const Job: TRadiantJob; Zone: Integer;
  out Strokes: TPlanStrokes; out Labels: TPlanLabels);
{ Loop Loop of zone Zone alone: the zone's walls and obstacles, its other
  loops faint, this one heavier in its ink, the manifold, and the other
  zones faint around it. }
procedure RadiantLoopStrokes(const Job: TRadiantJob; Zone, Loop: Integer;
  out Strokes: TPlanStrokes; out Labels: TPlanLabels);
{ The dimensions an installer needs to set out loop Loop of zone Zone from
  nearby walls. Across the rows: wall to first row, the rows, last row to
  far wall. Along them: wall to the lead-end turn, to the far-end turn, to
  the far wall. Plus any row that stops elsewhere, and each lead lane.
  Words says the same in plain lines. }
function RadiantLoopDims(const Job: TRadiantJob; Zone, Loop: Integer; out Words: TStringArray): TPlanDims;
{ the manifold of zone Zone: its middle to the walls around it }
function RadiantManifoldDims(const Job: TRadiantJob; Zone: Integer; out Words: TStringArray): TPlanDims;
{ the blocks as plain text - a title underlined, tables in columns }
function SubmittalAsText(const Blocks: TSubmittalBlocks): string;
{ #RRGGBB, for a table that names an ink }
function InkHex(C: TColor): string;
{ The submittal as a PDF, PageW x PageH mm: blocks in order, text wrapped,
  tables shrunk to fit, a zone to a page, each plan at the largest standard
  scale that fits with a north arrow and scale bar, and a title block on
  every sheet (job, date, sheet N of M). }
procedure SubmittalToPdf(const Job: TRadiantJob; const Blocks: TSubmittalBlocks;
  const Path: string; PageW, PageH: Double);
{ Writes the job's submittal to Path: plain text when Path ends in .txt,
  otherwise PDF on letter paper, or A4 for a metric drawing. }
procedure SubmittalExport(const Job: TRadiantJob; const Path: string);

implementation

uses hsPdf;

function InkHex(C: TColor): string;
begin
  C := ColorToRGB(C);
  Result := Format('#%.2X%.2X%.2X', [Red(C), Green(C), Blue(C)]);
end;

function ZoneTitleOf(const Job: TRadiantJob; Z: Integer): string;
begin
  Result := Format('Zone %d', [Z + 1]);
  if (Z >= 0) and (Z <= High(Job.ZoneNames)) and (Trim(Job.ZoneNames[Z]) <> '') then
    Result := Result + ' - ' + Trim(Job.ZoneNames[Z]);
end;

function Pct(F: Double): string;
begin
  Result := FormatFloat('0.0', F * 100) + '%';
end;

function RadiantSubmittal(const Job: TRadiantJob): TSubmittalBlocks;
var
  Z, I, J, N, Zones, Loops, Tried, Ports: Integer;
  Said: TStringArray;
  Area, Bare, TubeFt, OrderFt, Secs, Cover, Spread: Double;
  R: TRadiantResult;
  ZS: TRadiantSpec;
  T: TTubeFacts;
  MaxFt, Easy: Double;
  EasyN: Integer;
  Line: string;
  { the heat load, when there is one }
  HR: THeatZoneResults;
  HB: THeatBoiler;
  CZ: Integer;

  function EasyOf(const R: TRadiantResult): string;
  begin
    if R.Friendly < 0 then Result := '' else Result := FormatFloat('0', R.Friendly);
  end;

  procedure Add(Kind: TSubmittalKind; const Text: string; Zone: Integer = -1);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Default(TSubmittalBlock);
    Result[High(Result)].Kind := Kind;
    Result[High(Result)].Text := Text;
    Result[High(Result)].Zone := Zone;
  end;

  procedure Table(const Cols: array of string; Half: Boolean = False);
  var
    K: Integer;
  begin
    Add(skTable, '');
    Result[High(Result)].Half := Half;
    SetLength(Result[High(Result)].Cols, Length(Cols));
    for K := 0 to High(Cols) do Result[High(Result)].Cols[K] := Cols[K];
  end;

  procedure Row(const Cells: array of string);
  var
    K, N: Integer;
  begin
    N := Length(Result[High(Result)].Rows);
    SetLength(Result[High(Result)].Rows, N + 1);
    SetLength(Result[High(Result)].Rows[N], Length(Cells));
    for K := 0 to High(Cells) do Result[High(Result)].Rows[N][K] := Cells[K];
  end;

  function Done(Z: Integer): Boolean;
  begin
    Result := (Z <= High(Job.Searched)) and Job.Searched[Z] and (Z <= High(Job.Layouts)) and Job.Layouts[Z].Ok;
  end;

  function ZoneSpecOf(Z: Integer): TRadiantSpec;
  begin
    if Z <= High(Job.ZoneSpecs) then Result := Job.ZoneSpecs[Z] else Result := Job.Spec;
  end;

  function F0(V: Double): string; begin Result := FormatFloat('0', V); end;
  function F1(V: Double): string; begin Result := FormatFloat('0.0', V); end;
  function F2(V: Double): string; begin Result := FormatFloat('0.00', V); end;
  function F3(V: Double): string; begin Result := FormatFloat('0.000', V); end;

  function HeatUsed: Boolean;
  begin
    Result := Job.Heat.Enabled and (Length(Job.Heat.Zones) = Length(Job.Zones));
  end;

  function AnyUse(U: THeatUse): Boolean;
  var
    K: Integer;
  begin
    Result := False;
    for K := 0 to High(Job.Heat.Zones) do
      if Job.Heat.Zones[K].Use = U then Exit(True);
  end;

  { The heat load pages: conditions, each zone's loss and water, the
    boiler, warnings, then every formula and table value used and its
    source. }
  procedure HeatPages;
  var
    K: Integer;
    HZ: THeatZone;
    Lay: TRadiantResult;
    Warned: Boolean;
  begin
    SetLength(HR, Zones);
    for K := 0 to Zones - 1 do
    begin
      if Done(K) then Lay := Job.Layouts[K] else Lay := Default(TRadiantResult);
      HR[K] := HeatZone(Job.Heat, Job.Zones, K, Lay, ZoneSpecOf(K));
    end;
    HB := HeatBoiler(Job.Heat, HR);
    CZ := EnsureRange(Job.Heat.Climate, 1, 8);
    Add(skPageBreak, '');
    Add(skHeading, 'Heat load, water and the boiler');
    Add(skPara, 'A simplified heat loss at the design conditions below - walls, glass, doors, ceiling, the slab''s ' +
      'edge and the air that leaks in - the building taken as built to the IECC 2021 prescriptive code for its ' +
      'climate zone wherever it is said to be to code.  An estimate for choosing the boiler, the pumps and the ' +
      'pipe, not a Manual J: where a permit asks for a room-by-room load calculation, this does not stand in for ' +
      'one.  How every number was worked out, and the tables used, follow at the end of this section.');
    Table(['Design conditions', ''], True);
    Row(['Outdoor design', F0(Job.Heat.OutdoorF) + ' F']);
    Row(['Indoor', F0(Job.Heat.IndoorF) + ' F']);
    Row(['Difference', F0(Max(0, Job.Heat.IndoorF - Job.Heat.OutdoorF)) + ' F']);
    Row(['Climate zone (IECC)', IntToStr(CZ)]);
    Row(['Glycol', F0(Job.Heat.GlycolPct) + '%']);
    if Job.Heat.AltitudeFt > 0 then Row(['Altitude', F0(Job.Heat.AltitudeFt) + ' ft']);
    Row(['Hot water from the boiler', IfThen(Job.Heat.Dhw, Format('yes, %d bathroom%s', [Job.Heat.Baths,
      IfThen(Job.Heat.Baths = 1, '', 's')]), 'no')]);
    Table(['The boiler', ''], True);
    Row(['Heating, all zones', HeatBtu(HB.Comfort) + ' BTU/hr']);
    Row(['Piping loss', HeatBtu(HB.Piping) + ' BTU/hr']);
    if Job.Heat.Dhw then Row(['Hot water', Format('%s BTU/hr (%s GPM)', [HeatBtu(HB.Dhw), F1(HB.DhwGpm)])]);
    if HB.Derate > 0 then Row(['Altitude derate', F0(HB.Derate * 100) + '%']);
    Row(['Rated output, at least', HeatBtu(HB.Output) + ' BTU/hr']);
    Row(['Input, about', HeatBtu(HB.Input) + ' BTU/hr']);
    if HB.MinFire > 0 then Row(['Modulating down to', HeatBtu(HB.MinFire) + ' BTU/hr or less']);
    if HB.Snow > 0 then
    begin
      Row(['Snow melt', HeatBtu(HB.Snow) + ' BTU/hr']);
      Row(['One boiler for both', HeatBtu(HB.OutputWithSnow) + ' BTU/hr']);
    end;
    Add(skPara, Format('Choose a boiler whose rated output (AHRI net, or DOE heating capacity) is at least %s BTU/hr%s.  ' +
      'At radiant water temperatures a modulating condensing boiler (mod-con) runs at its best; one that turns down ' +
      'to the smallest zone''s load keeps from short-cycling when only that zone calls.',
      [HeatBtu(HB.Output), IfThen(Job.Heat.Dhw, ' - the hot water sets it where it is larger than the heating', '')]));
    Table(['Zone', 'Is', 'Floor', 'Heat', 'BTU/hr sq ft', 'Floor', 'Water out / back', 'GPM', 'Pump', 'To boiler']);
    for K := 0 to Zones - 1 do
    begin
      HZ := Job.Heat.Zones[K];
      if not HR[K].Ok then Continue;
      Row([ZoneTitleOf(Job, K).Replace('Zone ', ''), HEAT_USE_NAMES[HZ.Use], FormatArea(HR[K].AreaSqFt, Job.Units),
        HeatBtu(HR[K].Total), F1(HR[K].PerSqFt), F0(HR[K].FloorF) + ' F',
        F0(HR[K].SupplyF) + ' / ' + F0(HR[K].ReturnF) + ' F', F1(HR[K].Gpm),
        F1(HR[K].PumpGpm) + ' GPM at ' + F1(HR[K].PumpHeadFt) + ' ft', HR[K].PipeName + ' copper, ' + F0(HR[K].RunFt) + ' ft']);
    end;
    Table(['Zone', 'Walls', 'Windows', 'Doors', 'Ceiling', 'Slab edge', 'Floor down', 'Air', 'Total BTU/hr']);
    for K := 0 to Zones - 1 do
      if HR[K].Ok and (Job.Heat.Zones[K].Use <> huSnowMelt) then
        Row([ZoneTitleOf(Job, K).Replace('Zone ', ''), HeatBtu(HR[K].Walls), HeatBtu(HR[K].Windows),
          HeatBtu(HR[K].Doors), HeatBtu(HR[K].Ceiling), HeatBtu(HR[K].Edge), HeatBtu(HR[K].Down), HeatBtu(HR[K].Air),
          HeatBtu(HR[K].Total)]);
    Table(['Zone', 'Ceiling', 'Above', 'Walls', 'Slab', 'Floor', 'Glass', 'Doors', 'Air', 'Outside', 'Unheated']);
    for K := 0 to Zones - 1 do
      if HR[K].Ok then
      begin
        HZ := Job.Heat.Zones[K];
        if HZ.Use = huSnowMelt then
          Row([ZoneTitleOf(Job, K).Replace('Zone ', ''), '', '', '', '', HEAT_SNOW_NAMES[HZ.Snow], '', '', '', '', ''])
        else
          Row([ZoneTitleOf(Job, K).Replace('Zone ', ''), FormatLen(HZ.CeilingFt, Job.Units), HEAT_ABOVE_NAMES[HZ.Above],
            HEAT_WALL_NAMES[HZ.Walls], IfThen(HZ.Use = huSlab, HEAT_SLAB_NAMES[HZ.Slab], '-'), HEAT_COVER_NAMES[HZ.Cover],
            FormatArea(HZ.WindowSqFt, Job.Units), FormatArea(HZ.DoorSqFt, Job.Units), HEAT_TIGHT_NAMES[HZ.Tight],
            FormatLen(HR[K].OutsideFt, Job.Units), FormatLen(HR[K].UnheatedFt, Job.Units)]);
      end;
    { what to watch }
    Warned := False;
    for K := 0 to Zones - 1 do
    begin
      if not HR[K].Ok then Continue;
      HZ := Job.Heat.Zones[K];
      if HR[K].Short > 0 then
      begin
        Add(skPara, Format('%s needs %s BTU/hr sq ft from its floor - more than the %s a floor gives at %s F. ' +
          'About %s BTU/hr more has to come from other heat, or the building tightened.',
          [ZoneTitleOf(Job, K), F1(HR[K].PerSqFt), F0(HR[K].FloorMaxPerSqFt), F0(FLOOR_MAX_F), HeatBtu(HR[K].Short)]));
        Warned := True;
      end;
      if (HZ.Use in [huSlab, huSlabOverHeated]) and (HR[K].SupplyF > 120) then
      begin
        Add(skPara, Format('%s wants water at %s F - hot for a slab; a closer spacing or a thinner covering brings it down.',
          [ZoneTitleOf(Job, K), F0(HR[K].SupplyF)]));
        Warned := True;
      end;
      if HR[K].PumpHeadFt > 25 then
      begin
        Add(skPara, Format('%s''s pump works against %s ft of head - past what a small circulator gives; shorter loops ' +
          'or a larger tube bring it down.', [ZoneTitleOf(Job, K), F1(HR[K].PumpHeadFt)]));
        Warned := True;
      end;
    end;
    if AnyUse(huSnowMelt) then
    begin
      Add(skPara, 'Snow melt runs glycol, and usually through a heat exchanger from its own boiler or the heating ' +
        'boiler''s - it is shown apart from the heating load, and added to it only where one boiler does both.');
      if Job.Heat.GlycolPct <= 0 then
        Add(skPara, 'No glycol is entered - a snow melt slab needs it; its flow and head here are for water.');
      Warned := True;
    end;
    if not Warned then Add(skPara, 'Every zone''s floor gives what it needs at a comfortable surface temperature.');

    { the method and the tables }
    Add(skHeading, 'How the heat load was worked out');
    Add(skPara, 'Each zone''s loss at the design conditions, BTU an hour, is the sum of:');
    Add(skPara, '  Walls: U x (outside wall length x ceiling height - windows - doors) x difference; a wall to a space ' +
      'not heated at half the difference.  Windows and doors: U x area x difference, and each square foot of ' +
      'overhead door lets by air at 1.08 x CFM x difference.  Ceiling: U x floor area x difference, none under a ' +
      'heated space.  Slab edge: F x the length of outside and unheated walls x difference.  A joisted floor over a ' +
      'space not heated: U x floor area x half the difference.  Air: 0.018 x air changes an hour x floor area x ' +
      'ceiling height x difference.');
    Add(skPara, '  A wall two zones share is inside and loses nothing.  The outside walls were picked on the plan.');
    Add(skPara, Format('  The floor gives the room %s BTU/hr sq ft for every degree its surface is above the room, its ' +
      'surface at most %s F; the water''s average temperature is the surface''s plus the floor''s output times the ' +
      'resistance from the water to the surface (below) and the covering''s.  Flow: GPM = BTU/hr / (500 x the ' +
      'water''s drop), 500 falling 1.3 for every percent of glycol.  Each loop''s flow is the zone''s shared by ' +
      'loop length; its head by Hazen-Williams.  The pump''s head is the worst loop''s, plus the supply and return ' +
      'to the boiler with half again for fittings, plus %s ft for the manifold, its valves and flow meters.',
      [F1(FLOOR_COEFF), F0(FLOOR_MAX_F), F0(MANIFOLD_HEAD_FT)]));
    Table(['Table value used', 'Value', 'Source']);
    Row([Format('Outside wall U, to code, climate zone %d', [CZ]), F3(CODE_WALL_U[CZ]), 'IECC 2021 Table R402.1.2']);
    Row([Format('Ceiling U, to code, climate zone %d', [CZ]), F3(CODE_CEIL_U[CZ]), 'IECC 2021 Table R402.1.2']);
    Row([Format('Window U, to code, climate zone %d', [CZ]), F2(CODE_WINDOW_U[CZ]), 'IECC 2021 Table R402.1.2']);
    Row([Format('Floor over unheated space U, to code, zone %d', [CZ]), F3(CODE_FLOOR_U[CZ]), 'IECC 2021 Table R402.1.2']);
    Row(['Outside wall U, older (R-11 stud wall)', F3(OLDER_WALL_U), 'ASHRAE Fundamentals, typical assembly']);
    Row(['Wall or roof U, bare metal', F2(BARE_METAL_U), 'ASHRAE Fundamentals, typical assembly']);
    Row(['Overhead door U, insulated steel', F2(DOOR_U), 'typical manufacturer rating']);
    Row(['Overhead door air, CFM a sq ft at design', F1(DOOR_LEAK_CFM), 'estimate']);
    Row(['Heated slab edge F, insulated under it all, zones 1-3', F2(SLAB_F_CODE), 'ASHRAE 90.1 App. A (approx.)']);
    Row(['Heated slab edge F, insulated under it all, zones 4-8', F2(SLAB_F_CODE_COLD), 'ASHRAE 90.1 App. A (approx.)']);
    Row(['Heated slab edge F, R-10 at the edge only', F2(SLAB_F_EDGE), 'ASHRAE 90.1 App. A (approx.)']);
    Row(['Heated slab edge F, no insulation', F2(SLAB_F_NONE), 'ASHRAE 90.1 App. A']);
    Row(['Air changes an hour: tight, average, leaky', Format('%s, %s, %s', [F2(TIGHT_ACH[htTight]),
      F2(TIGHT_ACH[htAverage]), F2(TIGHT_ACH[htLeaky])]), 'ASHRAE Fundamentals, residential']);
    Row(['Air''s heat, BTU per cubic foot per degree', '0.018', 'ASHRAE Fundamentals']);
    Row(['Floor output, BTU/hr sq ft per degree', F1(FLOOR_COEFF), 'EN 1264 (11 W/m2K)']);
    Row(['Warmest floor surface', F0(FLOOR_MAX_F) + ' F', 'EN 1264, occupied area (29 C)']);
    Row(['Water to surface R, slab', Format('%s + %s x spacing (ft) = %s at %s"', [F2(SLAB_R_BASE), F2(SLAB_R_PER_FT),
      F2(SLAB_R_BASE + SLAB_R_PER_FT * Job.Spec.Spacing), F0(Job.Spec.Spacing / Job.Spec.Inch)]),
      'fitted to manufacturers'' design charts']);
    Row(['Water to surface R, joists with plates', F1(JOIST_R), 'fitted to manufacturers'' design charts']);
    Row(['Covering R: bare, tile, vinyl, wood, carpet', Format('%s, %s, %s, %s, %s', [F2(COVER_R[hcBare]),
      F2(COVER_R[hcTile]), F2(COVER_R[hcVinyl]), F2(COVER_R[hcWood]), F2(COVER_R[hcCarpet])]),
      'ASHRAE Fundamentals, typical']);
    Row(['Water''s drop: slab, joists, snow melt', Format('%s, %s, %s F', [F0(DELTA_SLAB), F0(DELTA_JOIST),
      F0(DELTA_SNOW)]), 'common design practice']);
    Row(['PEX inside diameter', Format('%s"', [F3(HeatPexIdIn(Job.Spec.Tube))]), 'ASTM F876, SDR 9']);
    Row(['Hazen-Williams C: PEX, copper', '150, 140', 'common design values']);
    Row(['Supply pipe to the boiler, most GPM: 1/2", 3/4", 1", 1-1/4", 1-1/2", 2"', Format('%s, %s, %s, %s, %s, %s',
      [F1(COPPER_MAX_GPM[0]), F0(COPPER_MAX_GPM[1]), F0(COPPER_MAX_GPM[2]), F0(COPPER_MAX_GPM[3]),
       F0(COPPER_MAX_GPM[4]), F0(COPPER_MAX_GPM[5])]), 'common hydronic sizing chart, copper type L']);
    Row(['Piping loss', F0(PIPING_SHARE * 100) + '% of the heating', 'estimate']);
    if Job.Heat.Dhw then
      Row(['Hot water, GPM for 1, 2, 3, 4+ bathrooms', Format('%s, %s, %s, %s, at a %s F rise', [F1(DHW_GPM[1]),
        F1(DHW_GPM[2]), F1(DHW_GPM[3]), F1(DHW_GPM[4]), F0(DHW_RISE_F)]), 'common sizing practice']);
    if Job.Heat.AltitudeFt > 2000 then Row(['Altitude derate', '4% a 1,000 ft past 2,000 ft', 'boiler makers'' practice']);
    Row(['Boiler efficiency, output to input', F0(BOILER_EFFICIENCY * 100) + '%', 'condensing, at radiant temperatures']);
    if AnyUse(huSnowMelt) then
      Row(['Snow melt, BTU/hr sq ft: residential, commercial, must stay clear', Format('%s, %s, %s',
        [F0(SNOW_RATE[hsnResidential]), F0(SNOW_RATE[hsnCommercial]), F0(SNOW_RATE[hsnCritical])]),
        'ASHRAE HVAC Applications, Snow Melting (classes I-III)']);
    Add(skPara, 'Sources: International Energy Conservation Code 2021 (IECC); ASHRAE Handbook - Fundamentals ' +
      '(residential heating load, air leakage, thermal resistances); ASHRAE Standard 90.1 Appendix A (slab-on-grade ' +
      'F-factors); ASHRAE Handbook - HVAC Applications (snow melting and freeze protection); EN 1264 (radiant floor ' +
      'output and surface temperature); ASTM F876 (PEX tube dimensions); the Hazen-Williams formula for pipe ' +
      'friction.  Values marked approximate or estimate are rounded or typical where a table gives a range.');
  end;

begin
  Result := nil;
  T := TubeOf(Job.Spec.Tube);
  MaxFt := Job.Spec.MaxLoopFt;
  if MaxFt <= 0 then MaxFt := T.MaxLoopFt;
  Zones := Length(Job.Zones);

  { totals first }
  Area := 0; Bare := 0; TubeFt := 0; OrderFt := 0; Loops := 0; Tried := 0; Secs := 0;
  for Z := 0 to Zones - 1 do
    if Done(Z) then
    begin
      R := Job.Layouts[Z];
      Area := Area + R.AreaSqFt; Bare := Bare + R.UnfilledSqFt;
      TubeFt := TubeFt + R.TotalFt; OrderFt := OrderFt + R.TotalFt * (1 + Job.Spec.WastePct / 100);
      Loops := Loops + Length(R.Loops);
      Tried := Tried + R.Tries; Secs := Secs + R.SearchSecs;
    end;
  if Job.Title <> '' then Add(skTitle, Job.Title) else Add(skTitle, 'Radiant heat layout');
  Add(skPara, Format('Radiant floor heating - a tube layout for %d zone%s, prepared %s with %s.',
    [Zones, IfThen(Zones = 1, '', 's'), FormatDateTime('yyyy-mm-dd hh:nn', Job.When), Job.Made]));

  Add(skHeading, 'System');
  Table(['', '']);
  Row(['Floor', 'concrete slab']);
  Row(['Tube', T.Name + ' PEX, ' + FormatFloat('0.#', Job.Spec.Spacing / Job.Spec.Inch) + '" on center']);
  Row(['Longest loop allowed', FormatLen(MaxFt, Job.Units)]);
  Row(['Zones and manifolds', Format('%d, one manifold each, %d loops at most', [Zones, RadiantMaxPorts(Job.Spec)])]);
  Row(['Loops', IntToStr(Loops)]);
  Row(['Floor to heat', FormatArea(Area, Job.Units)]);
  if Area > 0 then Row(['Reached by the tube', Pct(1 - Bare / Area)]);
  Row(['Tube, no waste', FormatLen(TubeFt, Job.Units)]);
  Row(['To order', FormatLen(OrderFt, Job.Units) + Format(' (%s%% waste)', [FormatFloat('0', Job.Spec.WastePct)])]);
  Row(['Ties or staples', Format('about %d, one every %s"', [Round(TubeFt * 12 / TIE_SPACING_IN),
    FormatFloat('0', TIE_SPACING_IN)])]);
  Row(['Goals', Format('%s%% of the floor, loops within %s%% of each other',
    [FormatFloat('0.#', Job.Spec.GoalCoverPct), FormatFloat('0.#', Job.Spec.GoalEvenPct)])]);
  if Tried > 0 then Row(['Design effort', Format('%d layouts tried, %s of searching', [Tried, RadiantDuration(Secs)])]);
  { installer friendly, over every loop }
  Easy := 0; EasyN := 0;
  for Z := 0 to Zones - 1 do
    if Done(Z) then
      for I := 0 to High(Job.Layouts[Z].LoopFriendly) do
      begin
        Easy := Easy + Job.Layouts[Z].LoopFriendly[I].Score;
        Inc(EasyN);
      end;
  if EasyN > 0 then
    Row(['Installer friendly', Format('%s of 100 - how easily each loop is set out and laid', [FormatFloat('0', Easy / EasyN)])]);

  Row(['Slab', Format('%s" thick, tube %s, R-%s under it', [FormatFloat('0.#', Job.Spec.SlabThick / Job.Spec.Inch),
    IfThen(Job.Spec.TubeDepth > 0, FormatFloat('0.#', Job.Spec.TubeDepth / Job.Spec.Inch) + '" deep', 'centered'),
    FormatFloat('0', Job.Spec.UnderR)])]);

  { what to buy }
  Add(skHeading, 'Material list');
  Table(['Item', 'Quantity', '']);
  Row([T.Name + ' PEX tube', FormatLen(OrderFt, Job.Units), Format('%s laid, and %s%% for waste',
    [FormatLen(TubeFt, Job.Units), FormatFloat('0', Job.Spec.WastePct)])]);
  { manifolds by size }
  for Ports := MANIFOLD_PORTS_MIN to 64 do
  begin
    I := 0;
    for Z := 0 to Zones - 1 do
      if Done(Z) and (Length(Job.Layouts[Z].Manifolds) > 0) and (Job.Layouts[Z].Manifolds[0].Ports = Ports) then Inc(I);
    if I > 0 then
      Row([Format('Manifold, %d-loop', [Ports]), IntToStr(I), Format('about %s of wall each',
        [FormatLen(RadiantManifoldWallIn(Ports) * Job.Spec.Inch, Job.Units)])]);
  end;
  Row(['Ties or staples', Format('about %d', [Round(TubeFt * 12 / TIE_SPACING_IN)]),
    Format('one every %s" of tube', [FormatFloat('0', TIE_SPACING_IN)])]);
  Row(['Insulation under the slab', Format('R-%s', [FormatFloat('0', Job.Spec.UnderR)]), FormatArea(Area, Job.Units)]);

  Add(skHeading, 'Zones');
  Table(['Zone', 'Floor', 'Loops', 'Manifold', 'Wall space', 'Tube', 'Reached', 'Loops within', 'Bends', 'Easy', 'Goals']);
  for Z := 0 to Zones - 1 do
    if Done(Z) then
    begin
      R := Job.Layouts[Z];
      RadiantMeasure(R, Cover, Spread);
      if Length(R.Manifolds) > 0 then Ports := R.Manifolds[0].Ports else Ports := 0;
      Row([ZoneTitleOf(Job, Z).Replace('Zone ', ''), FormatArea(R.AreaSqFt, Job.Units), IntToStr(Length(R.Loops)),
        Format('%d-loop', [Ports]), FormatLen(RadiantManifoldWallIn(Ports) * Job.Spec.Inch, Job.Units),
        FormatLen(R.TotalFt, Job.Units), Pct(Cover),
        Pct(Spread) + ' (' + FormatLen(RadiantSpreadFt(R), Job.Units) + ')', IntToStr(R.Bends), EasyOf(R),
        IfThen(R.ShortOfGoals, 'short', 'met')]);
    end
    else Row([ZoneTitleOf(Job, Z).Replace('Zone ', ''), '', '', '', '', '', '', '', '', '', 'not laid out']);

  Add(skPlan, 'Plan - every zone, north up', -1);

  { A page per zone: its plan, loops, what it takes, anything unusual, and
    a line on the search - the full record is at the back. }
  for Z := 0 to Zones - 1 do
  begin
    Add(skPageBreak, '');
    Add(skHeading, ZoneTitleOf(Job, Z));
    if not Done(Z) then
    begin
      Add(skPara, 'This zone has no layout - it was not searched, or nothing could be laid.');
      Continue;
    end;
    R := Job.Layouts[Z];
    ZS := ZoneSpecOf(Z);
    RadiantMeasure(R, Cover, Spread);
    if Length(R.Manifolds) > 0 then Ports := R.Manifolds[0].Ports else Ports := 0;
    Add(skPlan, ZoneTitleOf(Job, Z) + ' - north up', Z);
    Table(['Loop', 'Length', 'Measures', 'Color'], True);
    for I := 0 to High(R.Loops) do
      if I <= High(R.LoopFriendly) then
        Row([Format('Z%d L%d', [Z + 1, I + 1]), FormatLen(R.Loops[I].LenFt, Job.Units),
          IntToStr(R.LoopFriendly[I].Measures), InkHex(LoopInk(Z, I))])
      else
        Row([Format('Z%d L%d', [Z + 1, I + 1]), FormatLen(R.Loops[I].LenFt, Job.Units), '', InkHex(LoopInk(Z, I))]);
    Table(['Zone ' + IntToStr(Z + 1), ''], True);
    Row(['Floor', FormatArea(R.AreaSqFt, Job.Units)]);
    Row(['Manifold', Format('%d-loop, about %s of wall', [Ports,
      FormatLen(RadiantManifoldWallIn(Ports) * Job.Spec.Inch, Job.Units)])]);
    Row(['Tube', FormatLen(R.TotalFt, Job.Units) + ', order ' +
      FormatLen(R.TotalFt * (1 + Job.Spec.WastePct / 100), Job.Units)]);
    Row(['Ties or staples', Format('about %d', [Round(R.TotalFt * 12 / TIE_SPACING_IN)])]);
    Row(['Reached', Pct(Cover) + IfThen(R.UnfilledSqFt > 0.5, ', ' + FormatArea(R.UnfilledSqFt, Job.Units) + ' bare', '')]);
    Row(['Loops within', Pct(Spread) + ' (' + FormatLen(RadiantSpreadFt(R), Job.Units) + ')']);
    Row(['Breakout', Format('on the grid within %s ft of the manifold', [FormatFloat('0', R.BreakoutFt)])]);
    Row(['To lay', Format('%d bends, %s%% in straights of %s or more', [R.Bends, FormatFloat('0', R.StraightPct),
      FormatLen(STRAIGHT_RUN_SPACINGS * Job.Spec.Spacing, Job.Units)])]);
    if R.Friendly >= 0 then Row(['Installer friendly', EasyOf(R) + ' of 100']);
    if HeatUsed then
    begin
      HR := nil;
      SetLength(HR, 1);
      HR[0] := HeatZone(Job.Heat, Job.Zones, Z, R, ZS);
      if HR[0].Ok then
      begin
        Row(['Heat', Format('%s BTU/hr, %s a sq ft', [HeatBtu(HR[0].Total), F1(HR[0].PerSqFt)])]);
        Row(['Water', Format('%s F out, %s back, %s GPM', [F0(HR[0].SupplyF), F0(HR[0].ReturnF), F1(HR[0].Gpm)])]);
        Row(['Pump', Format('%s GPM at %s ft; %s copper to the boiler', [F1(HR[0].PumpGpm), F1(HR[0].PumpHeadFt),
          HR[0].PipeName])]);
      end;
    end;
    { anything out of the ordinary }
    if R.BreakoutFt > MANIFOLD_BREAKOUT_FT + 1E-6 then
      Add(skPara, Format('The breakout is wider than %s ft to cover the floor.', [FormatFloat('0', MANIFOLD_BREAKOUT_FT)]));
    if Abs(R.ManifoldShiftFt) > 1E-6 then
      Add(skPara, Format('The manifold was moved %s along its wall from where it was placed, for a better layout.',
        [FormatLen(Abs(R.ManifoldShiftFt), Job.Units)]));
    if R.TightestGap < ZS.Spacing - 1E-6 then
      Add(skPara, Format('Rows at the far wall close up to %s" (from %s") so every row pairs with another.',
        [FormatFloat('0.#', R.TightestGap / ZS.Inch), FormatFloat('0.#', ZS.Spacing / ZS.Inch)]));
    if R.TurnActualIn < R.TurnMinPexAIn then
      Add(skPara, Format('The %s" turn at the end of each row is tighter than this tube bends - PEX-A needs %s".',
        [FormatFloat('0.#', R.TurnActualIn), FormatFloat('0.#', R.TurnMinPexAIn)]))
    else if R.TurnActualIn < R.TurnMinIn then
      Add(skPara, Format('The %s" turn at the end of each row suits PEX-A (%s" at least); PEX-B and PEX-C want %s".',
        [FormatFloat('0.#', R.TurnActualIn), FormatFloat('0.#', R.TurnMinPexAIn), FormatFloat('0.#', R.TurnMinIn)]));
    if R.ShortOfGoals then
      Add(skPara, 'Short of the goals - the nearest the search came.');
    if RadiantOverPorts(R, Job.Spec) > 0 then
      Add(skPara, Format('This zone takes more loops than the %d a manifold is set to take - split it into two ' +
        'zones, a manifold each.', [RadiantMaxPorts(Job.Spec)]));
    { a loop needing more than two measurements says so on its own
      setting-out sheet, not here }
    Line := Format('Found in %d layouts, %s of searching', [R.Tries, RadiantDuration(R.SearchSecs)]);
    if (Z <= High(Job.Solutions)) and (Length(Job.Solutions[Z]) > 1) and (Z <= High(Job.Picked)) then
      Line := Line + Format('; layout %d of the %d it kept', [Job.Picked[Z] + 1, Length(Job.Solutions[Z])]);
    Add(skPara, Line + ' - see the design record.');
    { where the manifold goes, then every loop, drawn and dimensioned to be
      set out from the walls }
    Said := nil;
    RadiantManifoldDims(Job, Z, Said);
    if Length(Said) > 0 then Add(skPara, 'Setting out: the ' + string.Join(', the ', Said) + '.');
    Add(skLoopPlans, ZoneTitleOf(Job, Z) + ' - setting out, loop by loop', Z);
    for I := 0 to High(R.Loops) do
    begin
      RadiantLoopDims(Job, Z, I, Said);
      if (I <= High(R.LoopFriendly)) and (R.LoopFriendly[I].Measures > 2) then
      begin
        SetLength(Said, Length(Said) + 1);
        Said[High(Said)] := Format('takes %d measurements to set out', [R.LoopFriendly[I].Measures]);
      end;
      N := Length(Result[High(Result)].Rows);
      SetLength(Result[High(Result)].Rows, N + 1);
      SetLength(Result[High(Result)].Rows[N], Length(Said) + 1);
      Result[High(Result)].Rows[N][0] := Format('Z%d L%d - %s', [Z + 1, I + 1, FormatLen(R.Loops[I].LenFt, Job.Units)]);
      for J := 0 to High(Said) do Result[High(Result)].Rows[N][J + 1] := Said[J];
    end;
  end;

  if HeatUsed then HeatPages;

  { the search's record, zone by zone }
  Add(skPageBreak, '');
  Add(skHeading, 'Design record');
  Add(skPara, Format('Each zone was searched for a layout that heats at least %s%% of its floor with its loops ' +
    'within %s%% of each other in length: set layouts first, then others tried at random until the goals ' +
    'were met or the search was stopped.  What each search did, and the layouts it kept, best first - the one ' +
    'marked is the zone''s.', [FormatFloat('0.#', Job.Spec.GoalCoverPct), FormatFloat('0.#', Job.Spec.GoalEvenPct)]));
  for Z := 0 to Zones - 1 do
  begin
    if not Done(Z) then Continue;
    R := Job.Layouts[Z];
    Add(skHeading, ZoneTitleOf(Job, Z));
    Add(skPara, Format('%d layouts tried in %s.', [R.Tries, RadiantDuration(R.SearchSecs)]));
    for I := 0 to High(R.SearchLog) do Add(skPara, R.SearchLog[I]);
    if (Z <= High(Job.Solutions)) and (Length(Job.Solutions[Z]) > 1) then
    begin
      Table(['', 'Reached', 'Loops within', 'Loops', 'Bends', 'Tube', 'Easy', 'Goals']);
      for I := 0 to High(Job.Solutions[Z]) do
      begin
        RadiantMeasure(Job.Solutions[Z][I], Cover, Spread);
        Row([IfThen((Z <= High(Job.Picked)) and (Job.Picked[Z] = I), '>', '') + IntToStr(I + 1),
          Pct(Cover), Pct(Spread) + ' (' + FormatLen(RadiantSpreadFt(Job.Solutions[Z][I]), Job.Units) + ')',
          IntToStr(Length(Job.Solutions[Z][I].Loops)), IntToStr(Job.Solutions[Z][I].Bends),
          FormatLen(Job.Solutions[Z][I].TotalFt, Job.Units), EasyOf(Job.Solutions[Z][I]),
          IfThen(RadiantMeetsGoals(Job.Solutions[Z][I], Job.Spec), 'met', 'short')]);
      end;
    end;
  end;

  Add(skHeading, 'How this layout was made');
  Add(skPara, 'Each zone''s tube runs in rows parallel to the wall its manifold hangs on, a spacing apart, in loops ' +
    'that go out and come back on neighboring rows.  Every tube leaves its manifold square to it and is on the ' +
    'grid within the breakout given for the zone; the tube keeps ' + FormatFloat('0', EDGE_INSET_IN) +
    '" off every wall and obstacle.  Where a zone''s rows did not pair up, the rows at its far wall may have been ' +
    'closed up a little so every row has a partner - the zone''s page says so where it was done.');
  Add(skPara, 'Loop lengths run from the manifold and back, both leads included.  The order adds the waste given.');
  Add(skPara, 'Installer friendly, of 100: each loop is marked down for every reference measurement past two ' +
    'it takes to set out (where its rows stop short of a wall, and where its lead runs - the rows themselves are ' +
    'on the spacing), for turns past a plain serpentine''s, and for reaching past its own block of floor; a ' +
    'zone''s is the mean of its loops''.');
  if HeatUsed then
    Add(skPara, 'The spacing, the tube and the zones are as entered.  The heat load, water, pumps and boiler are the ' +
      'simplified estimate described with them, from the answers given for the building.')
  else
    Add(skPara, 'The spacing, the tube and the zones are as entered.  Heat loss, water temperature, flow and pump ' +
      'sizing were not worked out here and are not implied by this layout - they come from a room-by-room heat loss.');
end;

{ ---------------------------------------------------------------------- }
{ the loops on their own, and the dimensions to set them out             }
{ ---------------------------------------------------------------------- }

function FlatIn(const F: TRadiantFrame; const Src: TP3Array): T2Array;
var
  K: Integer;
begin
  SetLength(Result, Length(Src));
  for K := 0 to High(Src) do Result[K] := RadiantTo2(F, Src[K]);
end;

function ZoneLaid(const Job: TRadiantJob; Z: Integer): Boolean;
begin
  Result := (Z >= 0) and (Z <= High(Job.Zones)) and (Z <= High(Job.Searched)) and Job.Searched[Z] and
    (Z <= High(Job.Layouts)) and Job.Layouts[Z].Ok;
end;

const
  { a loop's setting-out sheet: the zone's other loops, neighboring zones'
    loops, and their walls - see RadiantLoopStrokes }
  LOOP_SHEET_OTHER = $00B4B4B4;
  LOOP_SHEET_NEIGHBOR = $00D0D0D0;
  LOOP_SHEET_NEIGHBOR_WALL = $00909090;

{ every zone but Zone, faint: its walls, its loops fainter }
procedure ContextZones(const Job: TRadiantJob; const F: TRadiantFrame; Zone: Integer; var Strokes: TPlanStrokes);

  procedure Add(const P: T2Array; Closed: Boolean; Color: TColor; WeightMM: Double);
  begin
    SetLength(Strokes, Length(Strokes) + 1);
    Strokes[High(Strokes)].Kind := psWall;
    Strokes[High(Strokes)].Pts := P;
    Strokes[High(Strokes)].Closed := Closed;
    Strokes[High(Strokes)].Color := Color;
    Strokes[High(Strokes)].WeightMM := WeightMM;
    Strokes[High(Strokes)].Context := True;
  end;

var
  Z, I: Integer;
begin
  for Z := 0 to High(Job.Zones) do
  begin
    if Z = Zone then Continue;
    if ZoneLaid(Job, Z) then
      for I := 0 to High(Job.Layouts[Z].Loops) do Add(FlatIn(F, Job.Layouts[Z].Loops[I].Pts), False, $00E4E4E4, 0.12);
    Add(FlatIn(F, Job.Zones[Z].Outline), True, $00B8B8B8, 0.3);
  end;
end;

procedure RadiantLoopStrokes(const Job: TRadiantJob; Zone, Loop: Integer;
  out Strokes: TPlanStrokes; out Labels: TPlanLabels);
var
  F: TRadiantFrame;
  All: TPlanStrokes;
  AllLabels: TPlanLabels;
  I, N: Integer;
begin
  Strokes := nil;
  Labels := nil;
  if not ZoneLaid(Job, Zone) or (Loop < 0) or (Loop > High(Job.Layouts[Zone].Loops)) then Exit;
  F := RadiantPlanFrame(Job.Zones[0].Outline);
  { The zone's plan with its other loops in gray and this one in its ink,
    so the sheet still reads as the floor. The gray must be dark enough to
    print - near white at 0.12 mm vanishes on paper. Dimensions sit outside
    the floor, so the gray does not hide them. }
  RadiantPlanStrokes(Job, Zone, All, AllLabels);
  N := 0;
  for I := 0 to High(All) do
    if All[I].Kind = psLoop then
    begin
      if N <> Loop then
      begin
        All[I].Color := LOOP_SHEET_OTHER;
        All[I].WeightMM := 0.2;
      end
      else All[I].WeightMM := 0.4;
      Inc(N);
    end
    else if All[I].Context then
    begin
      { a neighbor zone: its loops thin, and its walls }
      if All[I].WeightMM < 0.2 then
      begin
        All[I].Color := LOOP_SHEET_NEIGHBOR;
        All[I].WeightMM := 0.15;
      end
      else All[I].Color := LOOP_SHEET_NEIGHBOR_WALL;
    end;
  { this loop drawn last, over the faint ones }
  N := 0;
  for I := 0 to High(All) do
    if (All[I].Kind <> psLoop) or (All[I].WeightMM < 0.3) then
    begin
      SetLength(Strokes, Length(Strokes) + 1);
      Strokes[High(Strokes)] := All[I];
    end;
  for I := 0 to High(All) do
    if (All[I].Kind = psLoop) and (All[I].WeightMM >= 0.3) then
    begin
      SetLength(Strokes, Length(Strokes) + 1);
      Strokes[High(Strokes)] := All[I];
    end;
  { the manifold's name only - the zone's is in the heading and the loop's
    tag is the drawing's title }
  for I := 0 to High(AllLabels) do
    if not AllLabels[I].Tag and (Pos('Zone ', AllLabels[I].Text) <> 1) then
    begin
      SetLength(Labels, Length(Labels) + 1);
      Labels[High(Labels)] := AllLabels[I];
    end;
end;

{ the direction a loop's rows run, as a plan angle: the way its runs go
  furthest in total }
function RowAngle(const Pts: T2Array): Double;
var
  Buckets: array[0..359] of Double;
  I, K, Best: Integer;
  Len, Ang, BestLen: Double;
begin
  for I := 0 to 359 do Buckets[I] := 0;
  for I := 1 to High(Pts) do
  begin
    Len := Hypot(Pts[I].X - Pts[I - 1].X, Pts[I].Y - Pts[I - 1].Y);
    if Len < 1E-9 then Continue;
    Ang := ArcTan2(Pts[I].Y - Pts[I - 1].Y, Pts[I].X - Pts[I - 1].X);
    if Ang < 0 then Ang := Ang + Pi;
    if Ang >= Pi then Ang := Ang - Pi;
    K := Round(Ang / Pi * 360) mod 360;
    Buckets[K] := Buckets[K] + Len;
  end;
  Best := 0; BestLen := -1;
  for I := 0 to 359 do if Buckets[I] > BestLen then begin BestLen := Buckets[I]; Best := I; end;
  Result := Best / 360 * Pi;
end;

{ where the ray from P along D first meets the outline Poly }
function RayWall(const Poly: T2Array; const P, D: T2; out Hit: T2): Boolean;
var
  K: Integer;
  A, B: T2;
  Den, T, S, Best: Double;
begin
  Result := False;
  Best := 1E300;
  for K := 0 to High(Poly) do
  begin
    A := Poly[K]; B := Poly[(K + 1) mod Length(Poly)];
    Den := D.X * (B.Y - A.Y) - D.Y * (B.X - A.X);
    if Abs(Den) < 1E-12 then Continue;
    T := ((A.X - P.X) * (B.Y - A.Y) - (A.Y - P.Y) * (B.X - A.X)) / Den;
    S := ((A.X - P.X) * D.Y - (A.Y - P.Y) * D.X) / Den;
    if (T > 1E-6) and (S >= -1E-9) and (S <= 1 + 1E-9) and (T < Best) then
    begin
      Best := T;
      Hit.X := P.X + T * D.X; Hit.Y := P.Y + T * D.Y;
      Result := True;
    end;
  end;
end;

{ the wall a ray along D meets, named by the way it faces }
function WallWord(const D: T2): string;
begin
  if Abs(D.X) >= Abs(D.Y) then
  begin
    if D.X > 0 then Result := 'east wall' else Result := 'west wall';
  end
  else if D.Y > 0 then Result := 'north wall' else Result := 'south wall';
end;

function Pt2(X, Y: Double): T2;
begin
  Result.X := X; Result.Y := Y;
end;

procedure AddDim(var Dims: TPlanDims; const A, B: T2; const Text: string);
begin
  SetLength(Dims, Length(Dims) + 1);
  Dims[High(Dims)] := Default(TPlanDim);
  Dims[High(Dims)].A := A; Dims[High(Dims)].B := B;
  Dims[High(Dims)].Text := Text;
  Dims[High(Dims)].FromA := A; Dims[High(Dims)].FromB := B;
end;

function RadiantLoopDims(const Job: TRadiantJob; Zone, Loop: Integer; out Words: TStringArray): TPlanDims;
type
  TRow = record
    V, Lo, Hi, Near, Far: Double;
  end;
var
  F: TRadiantFrame;
  Poly, Pts: T2Array;
  R: TRadiantResult;
  Sp, Reach, Ang, Len, MaxAlong, U0, U1, Mu, Mv, V1, V2, Un, Uf, ULine, VLine, VEdge, G, D: Double;
  Ua, Va, Mp, Hit, Hit2, P, Q: T2;
  Rows: array of TRow;
  I, J, FarDir, Extras: Integer;
  Found: Boolean;
  LoSide, HiSide: string;
  Nears_: array of Double;
  Seen: array of Double;

  function U(const X: T2): Double; begin Result := X.X * Ua.X + X.Y * Ua.Y; end;
  function V(const X: T2): Double; begin Result := X.X * Va.X + X.Y * Va.Y; end;
  function At(UU, VV: Double): T2; begin Result := Pt2(UU * Ua.X + VV * Va.X, UU * Ua.Y + VV * Va.Y); end;
  function Dir(SU, SV: Double): T2; begin Result := Pt2(SU * Ua.X + SV * Va.X, SU * Ua.Y + SV * Va.Y); end;
  function Len_(Ft: Double): string; begin Result := FormatLen(Ft, Job.Units); end;

  procedure Say(const S: string);
  begin
    SetLength(Words, Length(Words) + 1);
    Words[High(Words)] := S;
  end;

  { the most common of Vals, to a sixteenth of an inch }
  function Mode(const Vals: array of Double): Double;
  var
    A, B2, N2, BestN: Integer;
  begin
    Result := Vals[0]; BestN := 0;
    for A := 0 to High(Vals) do
    begin
      N2 := 0;
      for B2 := 0 to High(Vals) do if Abs(Vals[A] - Vals[B2]) < 1 / 192 then Inc(N2);
      if N2 > BestN then begin BestN := N2; Result := Vals[A]; end;
    end;
  end;

  { a row named by position: a side row by its side, any other by its
    distance from the first side row }
  function RowName(VV: Double): string;
  begin
    if Abs(VV - V1) < 1E-3 then Result := Format('the %s row', [LoSide])
    else if Abs(VV - V2) < 1E-3 then Result := Format('the %s row', [HiSide])
    else Result := Format('the row %s %s of the %s row', [Len_(Abs(VV - V1)), HiSide, LoSide]);
  end;

  function Already(X: Double): Boolean;
  var
    A: Integer;
  begin
    for A := 0 to High(Seen) do if Abs(Seen[A] - X) < Sp / 4 then Exit(True);
    SetLength(Seen, Length(Seen) + 1); Seen[High(Seen)] := X;
    Result := False;
  end;

var
  Fars, Nears: array of Double;
begin
  Result := nil;
  Words := nil;
  if not ZoneLaid(Job, Zone) or (Loop < 0) or (Loop > High(Job.Layouts[Zone].Loops)) then Exit;
  R := Job.Layouts[Zone];
  F := RadiantPlanFrame(Job.Zones[0].Outline);
  Poly := FlatIn(F, Job.Zones[Zone].Outline);
  Pts := FlatIn(F, R.Loops[Loop].Pts);
  if Zone <= High(Job.ZoneSpecs) then Sp := Job.ZoneSpecs[Zone].Spacing else Sp := Job.Spec.Spacing;
  if Length(Pts) < 2 then Exit;
  { rows run the way the loop runs furthest }
  Ang := RowAngle(Pts);
  Ua := Pt2(Cos(Ang), Sin(Ang));
  Va := Pt2(-Sin(Ang), Cos(Ang));
  { measure across the rows west to east, or south to north, so rows are
    named by their sides }
  if (Va.X < -1E-9) or ((Abs(Va.X) <= 1E-9) and (Va.Y < 0)) then Va := Pt2(-Va.X, -Va.Y);
  if Length(R.Manifolds) > 0 then Mp := RadiantTo2(F, R.Manifolds[0].At) else Mp := Pts[0];
  Mu := U(Mp); Mv := V(Mp);
  Reach := Max(R.BreakoutFt, MANIFOLD_BREAKOUT_FT) + Sp;
  { rows are the long runs along the rows' way, not the leads by the
    manifold; a row cut into pieces by fingers counts as one }
  MaxAlong := 0;
  for I := 1 to High(Pts) do
    if Abs(V(Pts[I]) - V(Pts[I - 1])) < 1E-4 then MaxAlong := Max(MaxAlong, Abs(U(Pts[I]) - U(Pts[I - 1])));
  Rows := nil;
  for I := 1 to High(Pts) do
  begin
    if Abs(V(Pts[I]) - V(Pts[I - 1])) >= 1E-4 then Continue;
    Len := Abs(U(Pts[I]) - U(Pts[I - 1]));
    if Len < Max(2 * Sp, 0.3 * MaxAlong) then Continue;
    if (Hypot(Pts[I].X - Mp.X, Pts[I].Y - Mp.Y) <= Reach) and
       (Hypot(Pts[I - 1].X - Mp.X, Pts[I - 1].Y - Mp.Y) <= Reach) then Continue;
    U0 := Min(U(Pts[I]), U(Pts[I - 1])); U1 := Max(U(Pts[I]), U(Pts[I - 1]));
    Found := False;
    for J := 0 to High(Rows) do
      if Abs(Rows[J].V - V(Pts[I])) < 1E-3 then
      begin
        Rows[J].Lo := Min(Rows[J].Lo, U0); Rows[J].Hi := Max(Rows[J].Hi, U1);
        Found := True;
      end;
    if not Found then
    begin
      SetLength(Rows, Length(Rows) + 1);
      Rows[High(Rows)].V := V(Pts[I]); Rows[High(Rows)].Lo := U0; Rows[High(Rows)].Hi := U1;
    end;
  end;
  if Length(Rows) = 0 then
  begin
    Say('no rows to set out from the walls');
    Exit;
  end;
  { which end of the rows is the lead (manifold) end, and which way the
    far end lies }
  SetLength(Fars, Length(Rows)); SetLength(Nears, Length(Rows));
  V1 := 1E300; V2 := -1E300;
  for J := 0 to High(Rows) do
  begin
    if Abs(Rows[J].Lo - Mu) <= Abs(Rows[J].Hi - Mu) then
    begin
      Rows[J].Near := Rows[J].Lo; Rows[J].Far := Rows[J].Hi;
    end
    else
    begin
      Rows[J].Near := Rows[J].Hi; Rows[J].Far := Rows[J].Lo;
    end;
    Fars[J] := Rows[J].Far; Nears[J] := Rows[J].Near;
    V1 := Min(V1, Rows[J].V); V2 := Max(V2, Rows[J].V);
  end;
  Uf := Mode(Fars); Un := Mode(Nears);
  if Uf >= Un then FarDir := 1 else FarDir := -1;
  LoSide := WallWord(Dir(0, -1)).Replace(' wall', '');
  HiSide := WallWord(Dir(0, 1)).Replace(' wall', '');
  Say(Format('%d rows at %s" on center, running %s-%s', [Length(Rows), FormatFloat('0.##', Sp * 12),
    WallWord(Dir(-FarDir, 0)).Replace(' wall', ''), WallWord(Dir(FarDir, 0)).Replace(' wall', '')]));

  { Across the rows: wall, side row, other side row, wall. Drawn in the
    strip past the rows' far ends when it is wide enough, otherwise a third
    of the way back along the rows, with extension lines from the row ends. }
  ULine := Uf + (Un - Uf) / 3;
  if RayWall(Poly, At(Uf, (V1 + V2) / 2), Dir(FarDir, 0), Hit) then
  begin
    G := Abs(U(Hit) - Uf);
    if G > DIM_STRIP_FT then ULine := Uf + FarDir * G / 2;
  end;
  P := At(ULine, V1); Q := At(ULine, V2);
  if RayWall(Poly, P, Dir(0, -1), Hit) then
  begin
    AddDim(Result, Hit, P, Len_(V1 - V(Hit)));
    Result[High(Result)].FromB := At(Uf, V1); Result[High(Result)].Ext := True;
    Say(Format('the %s row %s from the %s wall', [LoSide, Len_(V1 - V(Hit)), LoSide]));
  end;
  if Length(Rows) > 1 then
  begin
    AddDim(Result, P, Q, Len_(V2 - V1));
    Result[High(Result)].FromA := At(Uf, V1); Result[High(Result)].FromB := At(Uf, V2); Result[High(Result)].Ext := True;
  end;
  if RayWall(Poly, Q, Dir(0, 1), Hit2) then
  begin
    AddDim(Result, Q, Hit2, Len_(V(Hit2) - V2));
    Result[High(Result)].FromA := At(Uf, V2); Result[High(Result)].Ext := True;
    Say(Format('the %s row %s from the %s wall%s', [HiSide, Len_(V(Hit2) - V2), HiSide,
      IfThen(Length(Rows) > 1, Format(' - %s between them', [Len_(V2 - V1)]), '')]));
  end;

  { Along the rows: wall, lead-end turn, far-end turn, wall - beside an
    outside row, inside the floor. Use the side row that turns where the
    rest do; a row turning elsewhere gets its own dimension, and the two
    would sit half a spacing apart. }
  VEdge := V2; VLine := V2 + Sp / 2;
  for J := 0 to High(Rows) do
    if (Abs(Rows[J].V - V2) < 1E-3) and ((Abs(Rows[J].Near - Un) > Sp / 4) or (Abs(Rows[J].Far - Uf) > Sp / 4)) then
    begin
      VEdge := V1; VLine := V1 - Sp / 2;
    end;
  if not RadiantInside(Job.Zones[Zone].Outline, RadiantFrom2(F, At(Un, VLine).X, At(Un, VLine).Y)) then
    if VEdge = V2 then begin VEdge := V1; VLine := V1 - Sp / 2; end
    else begin VEdge := V2; VLine := V2 + Sp / 2; end;
  P := At(Un, VLine); Q := At(Uf, VLine);
  if RayWall(Poly, P, Dir(-FarDir, 0), Hit) then
  begin
    AddDim(Result, Hit, P, Len_(Abs(Un - U(Hit))));
    Result[High(Result)].FromB := At(Un, VEdge); Result[High(Result)].Ext := True;
    Say(Format('the rows turn %s from the %s at the lead end', [Len_(Abs(Un - U(Hit))), WallWord(Dir(-FarDir, 0))]));
  end;
  AddDim(Result, P, Q, Len_(Abs(Uf - Un)));
  Result[High(Result)].FromA := At(Un, VEdge); Result[High(Result)].FromB := At(Uf, VEdge); Result[High(Result)].Ext := True;
  if RayWall(Poly, Q, Dir(FarDir, 0), Hit2) then
  begin
    AddDim(Result, Q, Hit2, Len_(Abs(U(Hit2) - Uf)));
    Result[High(Result)].FromA := At(Uf, VEdge); Result[High(Result)].Ext := True;
    Say(Format('and %s from the %s at the far end - %s long', [Len_(Abs(U(Hit2) - Uf)), WallWord(Dir(FarDir, 0)),
      Len_(Abs(Uf - Un))]));
  end;

  { each row that stops somewhere else, at either end, dimensioned to its
    wall }
  Extras := 0; Seen := nil;
  for J := 0 to High(Rows) do
  begin
    if Extras >= 8 then Break;
    if (Abs(Rows[J].Far - Uf) > Sp / 4) and not Already(Rows[J].Far) and
       RayWall(Poly, At(Rows[J].Far, Rows[J].V), Dir(FarDir, 0), Hit) then
    begin
      D := Abs(U(Hit) - Rows[J].Far);
      AddDim(Result, At(Rows[J].Far, Rows[J].V), Hit, Len_(D));
      Say(Format('%s stops %s from the %s', [RowName(Rows[J].V), Len_(D), WallWord(Dir(FarDir, 0))]));
      Inc(Extras);
    end;
  end;
  Seen := nil;
  Already(Un);
  for J := 0 to High(Rows) do
  begin
    if Extras >= 8 then Break;
    if (Abs(Rows[J].Near - Un) > Sp / 4) and not Already(Rows[J].Near) and
       RayWall(Poly, At(Rows[J].Near, Rows[J].V), Dir(-FarDir, 0), Hit) then
    begin
      D := Abs(U(Hit) - Rows[J].Near);
      AddDim(Result, Hit, At(Rows[J].Near, Rows[J].V), Len_(D));
      Say(Format('%s turns %s from the %s', [RowName(Rows[J].V), Len_(D), WallWord(Dir(-FarDir, 0))]));
      Inc(Extras);
    end;
  end;
  Nears_ := Copy(Seen);

  { the lead's lanes (runs across the rows near the manifold), each from
    its nearest wall along the rows - skipping any at a turn already
    dimensioned, since a lane always meets one }
  Seen := Nears_;
  for I := 1 to High(Pts) do
  begin
    if Abs(U(Pts[I]) - U(Pts[I - 1])) >= 1E-4 then Continue;
    if Abs(V(Pts[I]) - V(Pts[I - 1])) < 1.5 * Sp then Continue;
    if (Hypot(Pts[I].X - Mp.X, Pts[I].Y - Mp.Y) > Reach) and
       (Hypot(Pts[I - 1].X - Mp.X, Pts[I - 1].Y - Mp.Y) > Reach) then Continue;
    if Already(U(Pts[I])) then Continue;
    P := At(U(Pts[I]), (V(Pts[I]) + V(Pts[I - 1])) / 2);
    Found := RayWall(Poly, P, Dir(-1, 0), Hit);
    if RayWall(Poly, P, Dir(1, 0), Hit2) and (not Found or (Abs(U(Hit2) - U(P)) < Abs(U(Hit) - U(P)))) then
    begin
      Hit := Hit2; Found := True;
    end;
    if not Found then Continue;
    AddDim(Result, Hit, P, Len_(Abs(U(P) - U(Hit))));
    Say(Format('the lead runs %s from the %s', [Len_(Abs(U(P) - U(Hit))), WallWord(Pt2(Hit.X - P.X, Hit.Y - P.Y))]));
  end;
end;

function RadiantManifoldDims(const Job: TRadiantJob; Zone: Integer; out Words: TStringArray): TPlanDims;
var
  F: TRadiantFrame;
  Poly: T2Array;
  Mp, Hit, D: T2;
  R: TRadiantResult;
  Ang: Double;
  K: Integer;
begin
  Result := nil;
  Words := nil;
  if not ZoneLaid(Job, Zone) or (Length(Job.Layouts[Zone].Manifolds) = 0) then Exit;
  R := Job.Layouts[Zone];
  F := RadiantPlanFrame(Job.Zones[0].Outline);
  Poly := FlatIn(F, Job.Zones[Zone].Outline);
  Mp := RadiantTo2(F, R.Manifolds[0].At);
  { along and across the zone's rows (the first loop's way), or north
    and east }
  Ang := 0;
  if Length(R.Loops) > 0 then Ang := RowAngle(FlatIn(F, R.Loops[0].Pts));
  for K := 0 to 3 do
  begin
    D := Pt2(Cos(Ang + K * Pi / 2), Sin(Ang + K * Pi / 2));
    if RayWall(Poly, Mp, D, Hit) then
    begin
      AddDim(Result, Mp, Hit, FormatLen(Hypot(Hit.X - Mp.X, Hit.Y - Mp.Y), Job.Units));
      SetLength(Words, Length(Words) + 1);
      Words[High(Words)] := Format('manifold middle %s from the %s', [FormatLen(Hypot(Hit.X - Mp.X, Hit.Y - Mp.Y),
        Job.Units), WallWord(D)]);
    end;
  end;
end;

procedure RadiantPlanStrokes(const Job: TRadiantJob; Zone: Integer;
  out Strokes: TPlanStrokes; out Labels: TPlanLabels);
const
  SX: array[0..3] of Integer = (-1, 1, 1, -1);
  SY: array[0..3] of Integer = (-1, -1, 1, 1);
var
  F, ZF: TRadiantFrame;
  Z, I, J, K: Integer;
  C, Mid: T2;
  W, H, A: Double;
  Dir: TP3;
  Pts: T2Array;

  procedure Stroke(Kind: TPlanStrokeKind; const P: T2Array; Closed: Boolean; Color: TColor; WeightMM: Double);
  begin
    SetLength(Strokes, Length(Strokes) + 1);
    Strokes[High(Strokes)].Kind := Kind;
    Strokes[High(Strokes)].Pts := P;
    Strokes[High(Strokes)].Closed := Closed;
    Strokes[High(Strokes)].Color := Color;
    Strokes[High(Strokes)].WeightMM := WeightMM;
    Strokes[High(Strokes)].Context := False;
  end;

  procedure LabelAt(const P: T2; const Text: string; Color: TColor);
  begin
    SetLength(Labels, Length(Labels) + 1);
    Labels[High(Labels)].At := P;
    Labels[High(Labels)].Text := Text;
    Labels[High(Labels)].Color := Color;
    Labels[High(Labels)].Tag := False;
    Labels[High(Labels)].Loop := nil;
  end;

  function Flat(const Src: TP3Array): T2Array;
  var
    K: Integer;
  begin
    SetLength(Result, Length(Src));
    for K := 0 to High(Src) do Result[K] := RadiantTo2(F, Src[K]);
  end;

begin
  Strokes := nil;
  Labels := nil;
  if Length(Job.Zones) = 0 then Exit;
  { the drawing's own plan, the frame the wizard draws in }
  F := RadiantPlanFrame(Job.Zones[0].Outline);
  { a zone's own plan shows the other zones faint around it }
  if Zone >= 0 then
  begin
    ContextZones(Job, F, Zone, Strokes);
  end;
  for Z := 0 to High(Job.Zones) do
  begin
    if (Zone >= 0) and (Z <> Zone) then Continue;
    Stroke(psWall, Flat(Job.Zones[Z].Outline), True, clBlack, 0.5);
    for I := 0 to High(Job.Zones[Z].Holes) do
      Stroke(psHole, Flat(Job.Zones[Z].Holes[I]), True, clGray, 0.35);
    { the zone's number at the middle of its corners }
    Mid.X := 0; Mid.Y := 0;
    Pts := Flat(Job.Zones[Z].Outline);
    for I := 0 to High(Pts) do
    begin
      Mid.X := Mid.X + Pts[I].X / Length(Pts); Mid.Y := Mid.Y + Pts[I].Y / Length(Pts);
    end;
    LabelAt(Mid, ZoneTitleOf(Job, Z), clBlack);
    if (Z > High(Job.Searched)) or not Job.Searched[Z] or (Z > High(Job.Layouts)) or not Job.Layouts[Z].Ok then
      Continue;
    for I := 0 to High(Job.Layouts[Z].Loops) do
    begin
      Pts := Flat(Job.Layouts[Z].Loops[I].Pts);
      Stroke(psLoop, Copy(Pts), False, LoopInk(Z, I), 0.18 + 0.08 * Ord(LoopWeight(I) > 1));
      { The tag (name and length, in the loop's ink) goes on the run farthest
        from the manifold among those at least half as long as the longest.
        Near the manifold every loop's leads run side by side and the tags
        pile up. }
      A := 0;
      for J := 1 to High(Pts) do A := Max(A, Hypot(Pts[J].X - Pts[J - 1].X, Pts[J].Y - Pts[J - 1].Y));
      if Length(Job.Layouts[Z].Manifolds) > 0 then C := RadiantTo2(F, Job.Layouts[Z].Manifolds[0].At)
      else C := Pts[0];
      K := 0; W := -1;
      for J := 1 to High(Pts) do
        if (Hypot(Pts[J].X - Pts[J - 1].X, Pts[J].Y - Pts[J - 1].Y) >= A / 2) and
           (Hypot((Pts[J].X + Pts[J - 1].X) / 2 - C.X, (Pts[J].Y + Pts[J - 1].Y) / 2 - C.Y) > W) then
        begin
          W := Hypot((Pts[J].X + Pts[J - 1].X) / 2 - C.X, (Pts[J].Y + Pts[J - 1].Y) / 2 - C.Y);
          K := J;
        end;
      { Tags only on a zone's own plan, drawn off the floor where they read
        (see SubmittalToPdf's Plan). The all-zones plan leaves them out. }
      if (K > 0) and (Zone >= 0) then
      begin
        Mid.X := (Pts[K].X + Pts[K - 1].X) / 2; Mid.Y := (Pts[K].Y + Pts[K - 1].Y) / 2;
        LabelAt(Mid, Format('Z%d L%d  %s', [Z + 1, I + 1, FormatLen(Job.Layouts[Z].Loops[I].LenFt, Job.Units)]),
          LoopInk(Z, I));
        Labels[High(Labels)].Tag := True;
        Labels[High(Labels)].Loop := Copy(Pts);
      end;
    end;
    { the manifold: its box, turned the way it hangs }
    for J := 0 to High(Job.Layouts[Z].Manifolds) do
    begin
      C := RadiantTo2(F, Job.Layouts[Z].Manifolds[J].At);
      if (Z <= High(Job.ZoneSpecs)) and (J <= High(Job.ZoneSpecs[Z].ManifoldAngles)) then
      begin
        { the angle is in the zone's own frame: out to the world, then into
          the plan's }
        A := DegToRad(Job.ZoneSpecs[Z].ManifoldAngles[J]);
        ZF := RadiantFrameOf(Job.Zones[Z].Outline);
        Dir := P3(ZF.U.X * Cos(A) + ZF.V.X * Sin(A), ZF.U.Y * Cos(A) + ZF.V.Y * Sin(A),
          ZF.U.Z * Cos(A) + ZF.V.Z * Sin(A));
        A := ArcTan2(Dot3(Dir, F.V), Dot3(Dir, F.U));
      end
      else A := 0;
      W := Job.Spec.ManifoldW; H := Job.Spec.ManifoldH;
      SetLength(Pts, 4);
      for K := 0 to 3 do
      begin
        Pts[K].X := C.X + SX[K] * W / 2 * Cos(A) - SY[K] * H / 2 * Sin(A);
        Pts[K].Y := C.Y + SX[K] * W / 2 * Sin(A) + SY[K] * H / 2 * Cos(A);
      end;
      Stroke(psManifold, Copy(Pts), True, ZoneInk(Z), 0.5);
      LabelAt(C, Format('M%d', [Z + 1]), ZoneInk(Z));
    end;
  end;
end;


function SubmittalAsText(const Blocks: TSubmittalBlocks): string;
var
  B, I, J, N: Integer;
  Widths: array of Integer;
  S, Line: string;
  Out_: TStringList;
begin
  Out_ := TStringList.Create;
  try
    for B := 0 to High(Blocks) do
      case Blocks[B].Kind of
        skTitle:
          begin
            Out_.Add(Blocks[B].Text);
            Out_.Add(StringOfChar('=', Length(Blocks[B].Text)));
            Out_.Add('');
          end;
        skHeading:
          begin
            Out_.Add('');
            Out_.Add(Blocks[B].Text);
            Out_.Add(StringOfChar('-', Length(Blocks[B].Text)));
          end;
        skPara: Out_.Add(Blocks[B].Text);
        skPlan: Out_.Add('[' + Blocks[B].Text + ']');
        skLoopPlans:
          begin
            Out_.Add('');
            Out_.Add(Blocks[B].Text);
            for I := 0 to High(Blocks[B].Rows) do
              if Length(Blocks[B].Rows[I]) > 0 then
              begin
                Out_.Add('  ' + Blocks[B].Rows[I][0]);
                for J := 1 to High(Blocks[B].Rows[I]) do Out_.Add('    ' + Blocks[B].Rows[I][J]);
              end;
          end;
        skPageBreak: Out_.Add('');
        skTable:
          begin
            N := Length(Blocks[B].Cols);
            for I := 0 to High(Blocks[B].Rows) do N := Max(N, Length(Blocks[B].Rows[I]));
            SetLength(Widths, N);
            for J := 0 to N - 1 do Widths[J] := 0;
            for J := 0 to High(Blocks[B].Cols) do Widths[J] := Max(Widths[J], Length(Blocks[B].Cols[J]));
            for I := 0 to High(Blocks[B].Rows) do
              for J := 0 to High(Blocks[B].Rows[I]) do Widths[J] := Max(Widths[J], Length(Blocks[B].Rows[I][J]));
            Line := '';
            for J := 0 to High(Blocks[B].Cols) do Line := Line + Format('%-*s  ', [Widths[J], Blocks[B].Cols[J]]);
            if Trim(Line) <> '' then
            begin
              Out_.Add(TrimRight(Line));
              S := '';
              for J := 0 to N - 1 do S := S + StringOfChar('-', Widths[J]) + '  ';
              Out_.Add(TrimRight(S));
            end;
            for I := 0 to High(Blocks[B].Rows) do
            begin
              Line := '';
              for J := 0 to High(Blocks[B].Rows[I]) do Line := Line + Format('%-*s  ', [Widths[J], Blocks[B].Rows[I][J]]);
              Out_.Add(TrimRight(Line));
            end;
          end;
      end;
    Result := Out_.Text;
  finally
    Out_.Free;
  end;
end;

procedure SubmittalToPdf(const Job: TRadiantJob; const Blocks: TSubmittalBlocks;
  const Path: string; PageW, PageH: Double);
const
  MARGIN = 12.7;
  FOOT = 12.0;
  PT = 25.4 / 72;
var
  Book: TPdfBook;
  Top, Bottom, Left, Right, Wide, Yc: Double;
  B, I, N: Integer;
  Title, Stamp: string;
  Paired: Boolean;

  procedure NewPage;
  begin
    Book.NewPage;
    Yc := Top;
  end;

  procedure Need(H: Double);
  begin
    if Yc + H > Bottom then NewPage;
  end;

  { S cut into lines no wider than W at Size }
  function Wrap(const S: string; Size, W: Double; Bold: Boolean = False): TStringArray;
  var
    Words: TStringArray;
    K: Integer;
    Cur: string;
  begin
    Result := nil;
    Words := S.Split([' '], TStringSplitOptions.ExcludeEmpty);
    { leading spaces are kept - the ticket indents }
    Cur := Copy(S, 1, Length(S) - Length(TrimLeft(S)));
    for K := 0 to High(Words) do
    begin
      if (Trim(Cur) <> '') and (Book.TextWidth(Cur + ' ' + Words[K], Size, Bold) > W) then
      begin
        SetLength(Result, Length(Result) + 1); Result[High(Result)] := Cur;
        Cur := '    ' + Words[K];
      end
      else if Trim(Cur) = '' then Cur := Cur + Words[K]
      else Cur := Cur + ' ' + Words[K];
    end;
    if Trim(Cur) <> '' then begin SetLength(Result, Length(Result) + 1); Result[High(Result)] := Cur; end;
  end;

  procedure Para(const S: string; Size: Double; Ink: TColor = clBlack; Bold: Boolean = False);
  var
    Lines: TStringArray;
    K: Integer;
    LH: Double;
  begin
    LH := Size * PT * 1.35;
    Lines := Wrap(S, Size, Wide, Bold);
    for K := 0 to High(Lines) do
    begin
      Need(LH);
      Book.Text(Left, Yc + LH * 0.8, Lines[K], Size, Ink, Bold);
      Yc := Yc + LH;
    end;
  end;

  { A table at X0 in WAvail, type size and column widths shrunk to fit.
    Drawn from the cursor; runs onto a new page (headings repeated) unless
    Keep. Leaves the cursor under it. }
  procedure Table(const Blk: TSubmittalBlock; X0, WAvail: Double; Keep: Boolean = False);
  var
    Cols, R, C, Ink: Integer;
    W: array of Double;
    Sum, Size, RH, X: Double;
    HasHead: Boolean;

    procedure Head;
    var
      C2: Integer;
      X2: Double;
    begin
      if not HasHead then Exit;
      if not Keep then Need(RH * 2);
      X2 := X0;
      for C2 := 0 to High(Blk.Cols) do
      begin
        Book.Text(X2, Yc + RH * 0.75, Blk.Cols[C2], Size, clBlack, True);
        X2 := X2 + W[C2];
      end;
      Yc := Yc + RH;
      Book.Line(X0, Yc - RH * 0.1, X0 + Sum, Yc - RH * 0.1, clBlack, 0.2);
    end;

  begin
    Cols := Length(Blk.Cols);
    for R := 0 to High(Blk.Rows) do Cols := Max(Cols, Length(Blk.Rows[R]));
    if Cols = 0 then Exit;
    HasHead := False;
    for C := 0 to High(Blk.Cols) do if Blk.Cols[C] <> '' then HasHead := True;
    Size := 8;
    repeat
      SetLength(W, Cols);
      for C := 0 to Cols - 1 do W[C] := 0;
      for C := 0 to High(Blk.Cols) do W[C] := Max(W[C], Book.TextWidth(Blk.Cols[C], Size, True));
      for R := 0 to High(Blk.Rows) do
        for C := 0 to High(Blk.Rows[R]) do
          if Copy(Blk.Rows[R][C], 1, 1) = '#' then W[C] := Max(W[C], 8)
          else W[C] := Max(W[C], Book.TextWidth(Blk.Rows[R][C], Size));
      Sum := 0;
      for C := 0 to Cols - 1 do
      begin
        W[C] := W[C] + 3;
        Sum := Sum + W[C];
      end;
      if (Sum <= WAvail) or (Size <= 5.5) then Break;
      Size := Max(5.5, Size * WAvail / Sum - 0.05);
    until False;
    RH := Size * PT * 1.45;
    Yc := Yc + 1;
    Head;
    for R := 0 to High(Blk.Rows) do
    begin
      if not Keep and (Yc + RH > Bottom) then begin NewPage; Head; end;
      X := X0;
      for C := 0 to High(Blk.Rows[R]) do
      begin
        { an ink, #RRGGBB, is drawn as a swatch - the hex code means
          nothing on a job site }
        if (Length(Blk.Rows[R][C]) = 7) and (Blk.Rows[R][C][1] = '#') and
           TryStrToInt('$' + Copy(Blk.Rows[R][C], 2, 6), Ink) then
          Book.Poly([PointF(X, Yc + RH * 0.2), PointF(X + 7, Yc + RH * 0.2), PointF(X + 7, Yc + RH * 0.85),
            PointF(X, Yc + RH * 0.85)], True, clBlack, 0.1, RGBToColor((Ink shr 16) and $FF, (Ink shr 8) and $FF, Ink and $FF))
        else Book.Text(X, Yc + RH * 0.75, Blk.Rows[R][C], Size);
        X := X + W[C];
      end;
      Yc := Yc + RH;
    end;
    Yc := Yc + 2;
  end;

  { how tall a table comes out, laid in WAvail }
  function TableHeight(const Blk: TSubmittalBlock; WAvail: Double): Double;
  var
    Y0: Double;
    Was: Integer;
  begin
    { estimated from 8 pt rows, the header and the gaps; laying it out on
      a scratch page would cost a page }
    Was := Length(Blk.Rows) + Ord(Length(Blk.Cols) > 0);
    Y0 := 8 * PT * 1.45;
    Result := Was * Y0 + 3;
  end;

  { two half-width tables side by side }
  procedure TablePair(const A, B2: TSubmittalBlock);
  var
    Y0, Ya, H: Double;
  begin
    H := Max(TableHeight(A, Wide / 2 - 3), TableHeight(B2, Wide / 2 - 3));
    Need(H);
    Y0 := Yc;
    Table(A, Left, Wide / 2 - 3, True);
    Ya := Yc;
    Yc := Y0;
    Table(B2, Left + Wide / 2 + 3, Wide / 2 - 3, True);
    Yc := Max(Ya, Yc);
  end;

  { A dimension: the line from A to B with a slash at each end, the words
    in the middle on white, and extension lines out from FA and FB when Ext. }
  procedure Dimension(const A, B, FA, FB: TPointF; Ext: Boolean; const Text: string);
  const
    INK = $00303030;
    SIZE = 5.5;
  var
    L, DX, DY, TW, MX, MY: Double;
  begin
    L := Hypot(B.X - A.X, B.Y - A.Y);
    if L < 0.3 then Exit;
    DX := (B.X - A.X) / L; DY := (B.Y - A.Y) / L;
    if Ext then
    begin
      { darker than the gray loops they cross on a setting-out sheet }
      if Hypot(A.X - FA.X, A.Y - FA.Y) > 0.2 then Book.Line(FA.X, FA.Y, A.X, A.Y, $00505050, 0.12);
      if Hypot(B.X - FB.X, B.Y - FB.Y) > 0.2 then Book.Line(FB.X, FB.Y, B.X, B.Y, $00505050, 0.12);
    end;
    Book.Line(A.X, A.Y, B.X, B.Y, INK, 0.15);
    { the slashes, at 45 degrees to the line }
    Book.Line(A.X - 0.7 * (DX - DY), A.Y - 0.7 * (DY + DX), A.X + 0.7 * (DX - DY), A.Y + 0.7 * (DY + DX), INK, 0.25);
    Book.Line(B.X - 0.7 * (DX - DY), B.Y - 0.7 * (DY + DX), B.X + 0.7 * (DX - DY), B.Y + 0.7 * (DY + DX), INK, 0.25);
    { the words at the middle, or beside the line where it is too short to
      hold them }
    TW := Book.TextWidth(Text, SIZE, True);
    MX := (A.X + B.X) / 2; MY := (A.Y + B.Y) / 2;
    if L < TW + 1 then
    begin
      MX := MX - DY * (TW / 2 + 1.5);
      MY := MY + DX * 2.2;
    end;
    Book.Poly([PointF(MX - TW / 2 - 0.5, MY - 1.2), PointF(MX + TW / 2 + 0.5, MY - 1.2),
      PointF(MX + TW / 2 + 0.5, MY + 1.2), PointF(MX - TW / 2 - 0.5, MY + 1.2)], True, clWhite, 0.01, clWhite);
    Book.Text(MX - TW / 2, MY + 0.8, Text, SIZE, INK, True);
  end;

  { the part of P-Q inside the box X0,Y0 - X1,Y1, drawn }
  procedure ClipLine(const P, Q: TPointF; X0, Y0, X1, Y1: Double; Ink: TColor; W: Double);
  var
    T0, T1, DX, DY: Double;

    function Edge(Pp, Qq: Double): Boolean;
    var
      R: Double;
    begin
      Result := True;
      if Abs(Pp) < 1E-12 then Exit(Qq >= 0);
      R := Qq / Pp;
      if Pp < 0 then
      begin
        if R > T1 then Exit(False);
        if R > T0 then T0 := R;
      end
      else
      begin
        if R < T0 then Exit(False);
        if R < T1 then T1 := R;
      end;
    end;

  begin
    T0 := 0; T1 := 1;
    DX := Q.X - P.X; DY := Q.Y - P.Y;
    if Edge(-DX, P.X - X0) and Edge(DX, X1 - P.X) and Edge(-DY, P.Y - Y0) and Edge(DY, Y1 - P.Y) then
      Book.Line(P.X + T0 * DX, P.Y + T0 * DY, P.X + T1 * DX, P.Y + T1 * DY, Ink, W);
  end;

  { Draws strokes St, labels Lb and dimensions Dm in the box X0,Y0 W0 x H0 mm,
    at the largest standard scale that fits (fitted and marked when none
    does), with loop tags off the floor and a north arrow when North. Returns
    the scale in mm per foot. ForceSc sets the scale (so all loops of a zone
    match); DryRun only works it out. UsedH is the height used, Words the scale. }
  function DrawPlan(const St: TPlanStrokes; const Lb: TPlanLabels; const Dm: TPlanDims;
    X0, Y0, W0, H0: Double; North: Boolean; out UsedH: Double; out Words: string; Fit: Boolean = False;
    ForceSc: Double = 0; DryRun: Boolean = False): Double;
  const
    { inches of paper to the foot, largest first }
    SCALES: array[0..9] of Double = (0.5, 0.375, 0.25, 0.1875, 0.125, 0.09375, 0.0625, 0.046875, 0.03125,
      0.015625);
    SCALE_NAMES: array[0..9] of string = ('1/2"', '3/8"', '1/4"', '3/16"', '1/8"', '3/32"', '1/16"', '3/64"',
      '1/32"', '1/64"');
    { a loop's tag: type size, then mm - height, gap between tags, offset
      from the floor's edge }
    TAG_PT = 6;
    TAG_H = 3.6;
    TAG_GAP = 1;
    TAG_OFF = 4;
    { dimension lanes beside the floor: the first this far off, each
      further one this much more, mm }
    DIM_FIRST = 3;
    DIM_LANE = 5;
  type
    TTagAt = record
      Lb: Integer;
      Side: Integer;                 { 0 left, 1 right, 2 above, 3 below }
      Pt: Integer;                   { the loop's point nearest that side }
      AX, AY, W, P: Double;          { the anchor on the loop, the tag's width, its place along the side }
    end;
  var
    K, J, Pick, NTag, S2: Integer;
    MinX, MinY, MaxX, MaxY, BoxH, BoxW, Sc, OX, OY, AX, AY, PX0, PX1, PY0, PY1, Gap, D, Lum,
      TX, TY: Double;
    { room kept for tags left, right, above and below the floor, mm }
    Room: array[0..3] of Double;
    Pts: array of TPointF;
    Tags: array of TTagAt;
    Tmp: TTagAt;
    Ink: TColor;
    { Dimensions along the floor's axes are drawn outside it, in a lane on
      the nearest side with extension lines in, so their words never land on
      the tube. DimSide/DimLane per dimension (-1 when off-axis and drawn in
      place), DimRoom the room the lanes take on each side, mm. }
    DimSide, DimLane: array of Integer;
    DimRoom: array[0..3] of Double;
    LaneEnd: array[0..3] of array of Double;
    Order: array of Integer;
    Lo, Hi, GapFt, Sc0: Double;
    N, Ln: Integer;
    DA, DB: TPointF;

    function Shown(const D: TPlanDim): Boolean;
    begin
      { skip the tube's six inches off a wall; the caption says it }
      Result := Abs(Hypot(D.B.X - D.A.X, D.B.Y - D.A.Y) - EDGE_INSET_IN / 12) > 1 / 96;
    end;

  begin
    UsedH := 0; Words := '';
    Result := 0;
    if Length(St) = 0 then Exit;
    MinX := 1E300; MinY := 1E300; MaxX := -1E300; MaxY := -1E300;
    for K := 0 to High(St) do
      if not St[K].Context then
      for J := 0 to High(St[K].Pts) do
      begin
        MinX := Min(MinX, St[K].Pts[J].X); MaxX := Max(MaxX, St[K].Pts[J].X);
        MinY := Min(MinY, St[K].Pts[J].Y); MaxY := Max(MaxY, St[K].Pts[J].Y);
      end;
    { Each tag goes on the side its loop comes nearest. That does not depend
      on the scale, so it is found in feet first, and room is kept only on
      those sides: a column as wide as the widest tag, or a row one tag tall. }
    NTag := 0;
    for S2 := 0 to 3 do Room[S2] := 0;
    SetLength(Tags, Length(Lb));
    for K := 0 to High(Lb) do
      if Lb[K].Tag and (Length(Lb[K].Loop) > 0) then
      begin
        Tags[NTag].Lb := K;
        Tags[NTag].W := Book.TextWidth(Lb[K].Text, TAG_PT, True) + 2.4;
        Gap := 1E300;
        for J := 0 to High(Lb[K].Loop) do
          for S2 := 0 to 3 do
          begin
            case S2 of
              0: D := Lb[K].Loop[J].X - MinX;
              1: D := MaxX - Lb[K].Loop[J].X;
              2: D := MaxY - Lb[K].Loop[J].Y;
            else D := Lb[K].Loop[J].Y - MinY;
            end;
            if D < Gap - 1E-6 then begin Gap := D; Tags[NTag].Side := S2; Tags[NTag].Pt := J; end;
          end;
        if Tags[NTag].Side <= 1 then Room[Tags[NTag].Side] := Max(Room[Tags[NTag].Side], Tags[NTag].W + TAG_OFF + 1)
        else Room[Tags[NTag].Side] := TAG_H + TAG_OFF + 1;
        Inc(NTag);
      end;
    SetLength(Tags, NTag);
    { sides and lanes for the dimensions, packed in feet: two share a lane
      where their spans and words keep apart. Word width in feet uses the
      scale the floor would have with no lanes. }
    for S2 := 0 to 3 do begin DimRoom[S2] := 0; LaneEnd[S2] := nil; end;
    SetLength(DimSide, Length(Dm)); SetLength(DimLane, Length(Dm));
    Sc0 := Min((W0 - Room[0] - Room[1]) / Max(MaxX - MinX, 1E-6), (H0 - Room[2] - Room[3]) / Max(MaxY - MinY, 1E-6));
    SetLength(Order, 0);
    for K := 0 to High(Dm) do
    begin
      DimSide[K] := -1; DimLane[K] := -1;
      if not Shown(Dm[K]) then Continue;
      if Abs(Dm[K].A.Y - Dm[K].B.Y) < 1E-6 then
      begin
        if Dm[K].A.Y - MinY < MaxY - Dm[K].A.Y then DimSide[K] := 3 else DimSide[K] := 2;
      end
      else if Abs(Dm[K].A.X - Dm[K].B.X) < 1E-6 then
      begin
        if Dm[K].A.X - MinX < MaxX - Dm[K].A.X then DimSide[K] := 0 else DimSide[K] := 1;
      end;
      if DimSide[K] >= 0 then
      begin
        SetLength(Order, Length(Order) + 1);
        Order[High(Order)] := K;
      end;
    end;
    { sort by where each starts along its side }
    for K := 1 to High(Order) do
    begin
      N := Order[K]; J := K;
      while (J > 0) and (Min(IfThen(DimSide[Order[J - 1]] >= 2, Dm[Order[J - 1]].A.X, Dm[Order[J - 1]].A.Y),
        IfThen(DimSide[Order[J - 1]] >= 2, Dm[Order[J - 1]].B.X, Dm[Order[J - 1]].B.Y)) >
        Min(IfThen(DimSide[N] >= 2, Dm[N].A.X, Dm[N].A.Y), IfThen(DimSide[N] >= 2, Dm[N].B.X, Dm[N].B.Y))) do
      begin
        Order[J] := Order[J - 1]; Dec(J);
      end;
      Order[J] := N;
    end;
    for J := 0 to High(Order) do
    begin
      K := Order[J]; S2 := DimSide[K];
      if S2 >= 2 then begin Lo := Min(Dm[K].A.X, Dm[K].B.X); Hi := Max(Dm[K].A.X, Dm[K].B.X); end
      else begin Lo := Min(Dm[K].A.Y, Dm[K].B.Y); Hi := Max(Dm[K].A.Y, Dm[K].B.Y); end;
      GapFt := (Book.TextWidth(Dm[K].Text, 5.5, True) + 3) / Max(Sc0, 1E-6);
      { a label too long for a short span sits beside it, so the span grows }
      if Hi - Lo < GapFt then begin Lo := Lo - GapFt; Hi := Hi + GapFt; end;
      Ln := 0;
      while (Ln <= High(LaneEnd[S2])) and (LaneEnd[S2][Ln] > Lo - 1E-6) do Inc(Ln);
      if Ln > High(LaneEnd[S2]) then SetLength(LaneEnd[S2], Ln + 1);
      LaneEnd[S2][Ln] := Hi + 1 / Max(Sc0, 1E-6);
      DimLane[K] := Ln;
    end;
    for S2 := 0 to 3 do
      if Length(LaneEnd[S2]) > 0 then
      begin
        DimRoom[S2] := DIM_FIRST + Length(LaneEnd[S2]) * DIM_LANE;
        Room[S2] := Room[S2] + DimRoom[S2];
      end;
    BoxW := W0 - Room[0] - Room[1];
    BoxH := H0 - Room[2] - Room[3];
    { the largest standard scale it fits at; a metric drawing, or a floor
      too big for any, is fitted and marked not to scale }
    Pick := -1;
    if (Job.Units = usImperial) and not Fit then
      for K := 0 to High(SCALES) do
        if ((MaxX - MinX) * SCALES[K] * 25.4 <= BoxW) and ((MaxY - MinY) * SCALES[K] * 25.4 <= BoxH) then
        begin
          Pick := K;
          Break;
        end;
    if Pick >= 0 then
    begin
      Sc := SCALES[Pick] * 25.4;
      Words := 'scale ' + SCALE_NAMES[Pick] + ' = 1''-0"';
    end
    else
    begin
      Sc := Min(BoxW / Max(MaxX - MinX, 1E-6), BoxH / Max(MaxY - MinY, 1E-6));
      Words := 'not to scale';
    end;
    if ForceSc > 0 then
    begin
      Sc := ForceSc;
      Words := 'not to scale';
      for K := 0 to High(SCALES) do
        if Abs(SCALES[K] * 25.4 - Sc) < 1E-6 then Words := 'scale ' + SCALE_NAMES[K] + ' = 1''-0"';
    end;
    Result := Sc;
    if DryRun then Exit;
    OX := X0 + Room[0] + (BoxW - (MaxX - MinX) * Sc) / 2;
    OY := Y0 + Room[2];
    PX0 := OX; PX1 := OX + (MaxX - MinX) * Sc; PY0 := OY; PY1 := OY + (MaxY - MinY) * Sc;
    for K := 0 to High(St) do
    begin
      SetLength(Pts, Length(St[K].Pts));
      for J := 0 to High(St[K].Pts) do
        Pts[J] := PointF(OX + (St[K].Pts[J].X - MinX) * Sc, OY + (MaxY - St[K].Pts[J].Y) * Sc);
      { another zone: faint, clipped at the box }
      if St[K].Context then
      begin
        for J := 1 to High(Pts) + Ord(St[K].Closed) do
          ClipLine(Pts[J - 1], Pts[J mod Length(Pts)], X0, Y0, X0 + W0, Y0 + H0, St[K].Color, St[K].WeightMM);
        Continue;
      end;
      case St[K].Kind of
        psHole: Book.Poly(Pts, True, St[K].Color, St[K].WeightMM, $00D8D8D8);
        psManifold: Book.Poly(Pts, True, St[K].Color, St[K].WeightMM, clWhite);
      else Book.Poly(Pts, St[K].Closed, St[K].Color, St[K].WeightMM);
      end;
    end;
    { dimensions go over the strokes and under the names; the tube's
      six inches off a wall is in the caption instead }
    for K := 0 to High(Dm) do
    begin
      if not Shown(Dm[K]) then Continue;
      DA := PointF(OX + (Dm[K].A.X - MinX) * Sc, OY + (MaxY - Dm[K].A.Y) * Sc);
      DB := PointF(OX + (Dm[K].B.X - MinX) * Sc, OY + (MaxY - Dm[K].B.Y) * Sc);
      { what it measures from: its own ends, or what it was extended from }
      if Dm[K].Ext then
      begin
        Pts := [PointF(OX + (Dm[K].FromA.X - MinX) * Sc, OY + (MaxY - Dm[K].FromA.Y) * Sc),
          PointF(OX + (Dm[K].FromB.X - MinX) * Sc, OY + (MaxY - Dm[K].FromB.Y) * Sc)];
      end
      else Pts := [DA, DB];
      case DimSide[K] of
        0: begin D := PX0 - DIM_FIRST - DimLane[K] * DIM_LANE; DA.X := D; DB.X := D; end;
        1: begin D := PX1 + DIM_FIRST + DimLane[K] * DIM_LANE; DA.X := D; DB.X := D; end;
        2: begin D := PY0 - DIM_FIRST - DimLane[K] * DIM_LANE; DA.Y := D; DB.Y := D; end;
        3: begin D := PY1 + DIM_FIRST + DimLane[K] * DIM_LANE; DA.Y := D; DB.Y := D; end;
      end;
      Dimension(DA, DB, Pts[0], Pts[1], Dm[K].Ext or (DimSide[K] >= 0), Dm[K].Text);
    end;
    for K := 0 to High(Lb) do
    begin
      if Lb[K].Tag then Continue;
      AX := OX + (Lb[K].At.X - MinX) * Sc; AY := OY + (MaxY - Lb[K].At.Y) * Sc;
      if Pos('Zone ', Lb[K].Text) = 1 then
        Book.Text(AX - Book.TextWidth(Lb[K].Text, 9, True) / 2, AY, Lb[K].Text, 9, $00606060, True)
      else Book.Text(AX - Book.TextWidth(Lb[K].Text, 5) / 2, AY - 0.6, Lb[K].Text, 5, Lb[K].Color);
    end;
    { Each loop's tag sits off the floor on the side the loop comes nearest,
      with a leader to the loop's nearest point. Tags run along each side in
      loop order, pushed apart where they would touch. }
    for K := 0 to NTag - 1 do
    begin
      Tags[K].AX := OX + (Lb[Tags[K].Lb].Loop[Tags[K].Pt].X - MinX) * Sc;
      Tags[K].AY := OY + (MaxY - Lb[Tags[K].Lb].Loop[Tags[K].Pt].Y) * Sc;
      if Tags[K].Side <= 1 then Tags[K].P := Tags[K].AY - TAG_H / 2 else Tags[K].P := Tags[K].AX - Tags[K].W / 2;
    end;
    for K := 1 to NTag - 1 do
    begin
      Tmp := Tags[K]; J := K;
      while (J > 0) and ((Tags[J - 1].Side > Tmp.Side) or
            ((Tags[J - 1].Side = Tmp.Side) and (Tags[J - 1].P > Tmp.P))) do
      begin
        Tags[J] := Tags[J - 1]; Dec(J);
      end;
      Tags[J] := Tmp;
    end;
    for S2 := 0 to 3 do
    begin
      { push each tag past the one before, then pull back from the end
        where they ran out of room }
      for K := 1 to NTag - 1 do
        if (Tags[K].Side = S2) and (Tags[K - 1].Side = S2) then
          if S2 <= 1 then Tags[K].P := Max(Tags[K].P, Tags[K - 1].P + TAG_H + TAG_GAP)
          else Tags[K].P := Max(Tags[K].P, Tags[K - 1].P + Tags[K - 1].W + TAG_GAP);
      for K := NTag - 1 downto 0 do
        if Tags[K].Side = S2 then
        begin
          if S2 <= 1 then D := PY1 + Room[3] - TAG_H else D := X0 + W0 - Tags[K].W;
          if (K < NTag - 1) and (Tags[K + 1].Side = S2) then
            if S2 <= 1 then D := Min(D, Tags[K + 1].P - TAG_H - TAG_GAP)
            else D := Min(D, Tags[K + 1].P - Tags[K].W - TAG_GAP);
          Tags[K].P := Min(Tags[K].P, D);
        end;
    end;
    for K := 0 to NTag - 1 do
    begin
      case Tags[K].Side of
        0: begin TX := PX0 - DimRoom[0] - TAG_OFF - Tags[K].W; TY := Tags[K].P; end;
        1: begin TX := PX1 + DimRoom[1] + TAG_OFF; TY := Tags[K].P; end;
        2: begin TX := Tags[K].P; TY := PY0 - DimRoom[2] - TAG_OFF - TAG_H; end;
      else begin TX := Tags[K].P; TY := PY1 + DimRoom[3] + TAG_OFF; end;
      end;
      Ink := Lb[Tags[K].Lb].Color;
      { the leader, from the tag's side toward the floor to the loop }
      case Tags[K].Side of
        0: Book.Line(TX + Tags[K].W, TY + TAG_H / 2, Tags[K].AX, Tags[K].AY, Ink, 0.25);
        1: Book.Line(TX, TY + TAG_H / 2, Tags[K].AX, Tags[K].AY, Ink, 0.25);
        2: Book.Line(TX + Tags[K].W / 2, TY + TAG_H, Tags[K].AX, Tags[K].AY, Ink, 0.25);
      else Book.Line(TX + Tags[K].W / 2, TY, Tags[K].AX, Tags[K].AY, Ink, 0.25);
      end;
      { filled with the loop's ink, the words in black or white,
        whichever reads on it }
      SetLength(Pts, 4);
      Pts[0] := PointF(TX, TY); Pts[1] := PointF(TX + Tags[K].W, TY);
      Pts[2] := PointF(TX + Tags[K].W, TY + TAG_H); Pts[3] := PointF(TX, TY + TAG_H);
      Book.Poly(Pts, True, $00404040, 0.2, Ink);
      Lum := 0.299 * (Ink and $FF) + 0.587 * ((Ink shr 8) and $FF) + 0.114 * ((Ink shr 16) and $FF);
      Book.Text(TX + 1.2, TY + TAG_H - 1.0, Lb[Tags[K].Lb].Text, TAG_PT, IfThen(Lum < 140, clWhite, clBlack), True);
    end;
    { north, at the box's top right }
    if North then
    begin
      AX := X0 + W0 - 6; AY := OY - Room[2] + 2;
      Book.Line(AX, AY + 8, AX, AY, clBlack, 0.35);
      Book.Line(AX, AY, AX - 1.5, AY + 3, clBlack, 0.35);
      Book.Line(AX, AY, AX + 1.5, AY + 3, clBlack, 0.35);
      Book.Text(AX - Book.TextWidth('N', 8, True) / 2, AY - 1, 'N', 8, clBlack, True);
    end;
    UsedH := PY1 + Room[3] - Y0;
  end;

  { A scale bar with its right end at XR and its foot at Y: a round length
    in feet (meters in a metric drawing), in four black and white parts, up
    to MaxW mm long. Printed "fit to page", a stated scale is wrong but the
    bar shrinks with the drawing, so the installer can still scale off it. }
  procedure ScaleBar(XR, Y, Sc, MaxW: Double);
  const
    { lengths whose half is a whole number, so it reads off a tape }
    FT_STEPS: array[0..6] of Double = (2, 4, 10, 20, 40, 100, 200);
    M_STEPS: array[0..5] of Double = (1, 2, 4, 10, 20, 40);
  var
    Per, Len, W, X0, SegW: Double;
    K: Integer;
    Metric: Boolean;
    U, S0: string;
  begin
    if Sc <= 0 then Exit;
    Metric := Job.Units <> usImperial;
    { mm of paper to one of the bar's units }
    if Metric then Per := Sc * 3.28084 else Per := Sc;
    Len := 0;
    if Metric then
    begin
      for K := 0 to High(M_STEPS) do if M_STEPS[K] * Per <= MaxW then Len := M_STEPS[K];
      U := ' m';
    end
    else
    begin
      for K := 0 to High(FT_STEPS) do if FT_STEPS[K] * Per <= MaxW then Len := FT_STEPS[K];
      U := ' ft';
    end;
    if Len <= 0 then Exit;
    W := Len * Per;
    X0 := XR - W;
    SegW := W / 4;
    for K := 0 to 3 do
      Book.Poly([PointF(X0 + K * SegW, Y - 1.6), PointF(X0 + (K + 1) * SegW, Y - 1.6),
        PointF(X0 + (K + 1) * SegW, Y), PointF(X0 + K * SegW, Y)], True, clBlack, 0.15,
        IfThen(K mod 2 = 0, clBlack, clWhite));
    Book.Text(X0 - Book.TextWidth('0', 6.5) / 2, Y - 2.4, '0', 6.5, clBlack);
    S0 := FormatFloat('0.##', Len / 2);
    Book.Text(X0 + W / 2 - Book.TextWidth(S0, 6.5) / 2, Y - 2.4, S0, 6.5, clBlack);
    S0 := FormatFloat('0.##', Len) + U;
    Book.Text(XR - Book.TextWidth(FormatFloat('0.##', Len), 6.5) / 2, Y - 2.4, S0, 6.5, clBlack);
  end;

  { a plan block: every zone, or one zone with its manifold's dimensions }
  procedure Plan(const Blk: TSubmittalBlock);
  var
    J, K: Integer;
    St: TPlanStrokes;
    Lb: TPlanLabels;
    Dm: TPlanDims;
    Said: TStringArray;
    Used, Sc: Double;
    Words: string;
  begin
    RadiantPlanStrokes(Job, Blk.Zone, St, Lb);
    if Length(St) = 0 then Exit;
    Dm := nil;
    if Blk.Zone >= 0 then
    begin
      Dm := RadiantManifoldDims(Job, Blk.Zone, Said);
      { the zone's name is in the page heading, not in the middle of the
        plan where the manifold's dimensions cross }
      K := 0;
      for J := 0 to High(Lb) do
        if Pos('Zone ', Lb[J].Text) <> 1 then begin Lb[K] := Lb[J]; Inc(K); end;
      SetLength(Lb, K);
    end;
    { the rest of the page, or a new one when less than a third is left }
    if Bottom - Yc < (Bottom - Top) / 3 then NewPage;
    Sc := DrawPlan(St, Lb, Dm, Left, Yc + 2, Wide,
      Min(Bottom - Yc - 10, IfThen(Blk.Zone < 0, Bottom - Top - 10, (Bottom - Top) * 0.62)), True, Used, Words);
    Yc := Yc + 2 + Used + 4;
    Book.Text(Left, Yc + 3, Blk.Text + ' - ' + Words, 8, $00404040);
    ScaleBar(Right - 3, Yc + 3, Sc, 50);
    Yc := Yc + 7;
  end;

  { One drawing per loop of zone Blk.Zone: the zone with this loop in its
    ink and the others faint, plus the set-out dimensions outside the floor. }
  procedure LoopPlans(const Blk: TSubmittalBlock);
  const
    { page parts, mm: the heading, a checklist row, the caption line }
    HEAD_H = 30;
    CHECK_ROW = 6.5;
    CAPTION_H = 7;
    { the checklist as a right-hand column for a tall zone: its width and
      the gap to the drawing }
    SIDE_W = 66;
    SIDE_GAP = 6;
  var
    Z, L, K, J, NCheck: Integer;
    Used, Sc, ScMin, ScSide, DrawTop, DrawH, DrawW, CheckTop, CheckX, Y, Gpm, TotalFt: Double;
    Side: Boolean;
    St: TPlanStrokes;
    Lb: TPlanLabels;
    Dm: TPlanDims;
    Said, ManSaid, Lines: TStringArray;
    Words, S: string;
    ZS: TRadiantSpec;
    HR: THeatZoneResult;
    Checks: array of string;

    procedure Box(X, Y0: Double);
    begin
      Book.Poly([PointF(X, Y0), PointF(X + 3.4, Y0), PointF(X + 3.4, Y0 + 3.4), PointF(X, Y0 + 3.4)], True,
        clBlack, 0.25);
    end;

  begin
    Z := Blk.Zone;
    if not ZoneLaid(Job, Z) then Exit;
    if Z <= High(Job.ZoneSpecs) then ZS := Job.ZoneSpecs[Z] else ZS := Job.Spec;
    { One loop per page, printed large for the fitter's binder, with a
      checklist at the foot. }
    RadiantManifoldDims(Job, Z, ManSaid);
    { design flow, where a heat load is set: each loop gets its share of
      the zone's by length }
    Gpm := 0; TotalFt := 0;
    if Job.Heat.Enabled and (Length(Job.Heat.Zones) = Length(Job.Zones)) then
    begin
      HR := HeatZone(Job.Heat, Job.Zones, Z, Job.Layouts[Z], ZS);
      if HR.Ok then Gpm := HR.Gpm;
      for L := 0 to High(Job.Layouts[Z].Loops) do TotalFt := TotalFt + Job.Layouts[Z].Loops[L].LenFt;
    end;
    { checklist goes under the drawing, or beside it for a tall zone -
      whichever draws the loops larger }
    NCheck := 6;
    DrawTop := Top + HEAD_H;
    { One scale for every loop in the zone, the largest they all fit at, so
      the sheets of a zone line up. Worked out both with the checklist under
      and beside. }
    ScMin := 0; ScSide := 0;
    for L := 0 to High(Job.Layouts[Z].Loops) do
    begin
      RadiantLoopStrokes(Job, Z, L, St, Lb);
      Dm := RadiantLoopDims(Job, Z, L, Said);
      Sc := DrawPlan(St, Lb, Dm, Left, DrawTop, Wide, Bottom - (NCheck + 2.5) * CHECK_ROW - CAPTION_H - DrawTop,
        False, Used, Words, False, 0, True);
      if (Sc > 0) and ((ScMin = 0) or (Sc < ScMin)) then ScMin := Sc;
      Sc := DrawPlan(St, Lb, Dm, Left, DrawTop, Wide - SIDE_W - SIDE_GAP, Bottom - CAPTION_H - DrawTop,
        False, Used, Words, False, 0, True);
      if (Sc > 0) and ((ScSide = 0) or (Sc < ScSide)) then ScSide := Sc;
    end;
    Side := ScSide > ScMin * 1.05;
    if Side then
    begin
      ScMin := ScSide;
      DrawW := Wide - SIDE_W - SIDE_GAP;
      DrawH := Bottom - CAPTION_H - DrawTop;
      CheckTop := DrawTop;
      CheckX := Right - SIDE_W;
    end
    else
    begin
      DrawW := Wide;
      CheckTop := Bottom - (NCheck + 2.5) * CHECK_ROW;
      DrawH := CheckTop - CAPTION_H - DrawTop;
      CheckX := Left;
    end;
    for L := 0 to High(Job.Layouts[Z].Loops) do
    begin
      NewPage;
      { heading: name, ink, length, tube }
      Book.Text(Left, Yc + 5, ZoneTitleOf(Job, Z) + Format(' - loop %d of %d', [L + 1, Length(Job.Layouts[Z].Loops)]),
        13, clBlack, True);
      S := Format('Z%d L%d  %s of %s PEX', [Z + 1, L + 1, FormatLen(Job.Layouts[Z].Loops[L].LenFt, Job.Units),
        TubeOf(ZS.Tube).Name]);
      Book.Poly([PointF(Right - Book.TextWidth(S, 10, True) - 8, Yc + 1), PointF(Right - Book.TextWidth(S, 10, True) - 2.5, Yc + 1),
        PointF(Right - Book.TextWidth(S, 10, True) - 2.5, Yc + 6), PointF(Right - Book.TextWidth(S, 10, True) - 8, Yc + 6)],
        True, clBlack, 0.15, LoopInk(Z, L));
      Book.Text(Right - Book.TextWidth(S, 10, True), Yc + 5, S, 10, clBlack, True);
      Yc := Yc + 8;
      Book.Line(Left, Yc, Right, Yc, $00A0A0A0, 0.2);
      Yc := Yc + 4;
      RadiantLoopStrokes(Job, Z, L, St, Lb);
      Dm := RadiantLoopDims(Job, Z, L, Said);
      if Length(Said) > 0 then
      begin
        Book.Text(Left, Yc, Said[0], 8, $00303030);
        Yc := Yc + 4.5;
      end;
      if Length(ManSaid) > 0 then
      begin
        Lines := Wrap('The manifold: ' + string.Join(', ', ManSaid) + '.', 7.5, Wide);
        for K := 0 to Min(2, High(Lines)) do
        begin
          Book.Text(Left, Yc, Lines[K], 7.5, $00404040);
          Yc := Yc + 3.6;
        end;
      end;
      if (L <= High(Job.Layouts[Z].LoopFriendly)) and (Job.Layouts[Z].LoopFriendly[L].Measures > 2) then
        Book.Text(Left, Yc, Format('Takes %d measurements to set out - mark them all before laying.',
          [Job.Layouts[Z].LoopFriendly[L].Measures]), 7.5, $000030A0);
      { a standard scale where one fits, the same for every loop of the
        zone, so a rule laid on it reads true }
      DrawPlan(St, Lb, Dm, Left, DrawTop, DrawW, DrawH, False, Used, Words, False, ScMin);
      { under the box, not under the zone - the faint neighbors can reach
        the box's foot }
      Book.Text(Left, DrawTop + DrawH + 3.5, Format('north up - %s - dimensions to the walls govern; tube %s" off ' +
        'the walls unless dimensioned', [Words, FormatFloat('0', EDGE_INSET_IN)]), 7, $00606060);
      ScaleBar(Left + DrawW - 3, DrawTop + DrawH + 3.5, ScMin, 45);
      { the checklist }
      Y := CheckTop;
      if Side then Book.Line(CheckX, Y, Right, Y, $00808080, 0.2)
      else Book.Line(Left, Y, Right, Y, $00808080, 0.2);
      Book.Text(CheckX, Y + 5, 'Installer checklist', 10, clBlack, True);
      Y := Y + 8;
      SetLength(Checks, NCheck);
      Checks[0] := 'Rows marked on the floor from the dimensions above';
      Checks[1] := Format('Tube laid - %s, tied every %s"', [FormatLen(Job.Layouts[Z].Loops[L].LenFt, Job.Units),
        FormatFloat('0', TIE_SPACING_IN)]);
      Checks[2] := Format('Both ends tagged Z%d L%d at the manifold', [Z + 1, L + 1]);
      Checks[3] := 'Supply and return connected to the manifold';
      Checks[4] := 'Pressure tested at ________ psi, held ________ hours';
      if (Gpm > 0) and (TotalFt > 0) then
        Checks[5] := Format('Flow set to %s GPM on its meter (design)', [FormatFloat('0.00',
          Gpm * Job.Layouts[Z].Loops[L].LenFt / TotalFt)])
      else Checks[5] := 'Flow set to ________ GPM on its meter';
      for K := 0 to NCheck - 1 do
      begin
        Box(CheckX, Y);
        if Side then
        begin
          { a column: each item wrapped to fit }
          Lines := Wrap(Checks[K], 8.5, SIDE_W - 7);
          for J := 0 to High(Lines) do
            Book.Text(CheckX + 6, Y + 3 + J * 4, Lines[J], 8.5, clBlack);
          Y := Y + Max(1, Length(Lines)) * 4 + 3.5;
        end
        else
        begin
          Book.Text(CheckX + 6, Y + 3, Checks[K], 9, clBlack);
          Y := Y + CHECK_ROW;
        end;
      end;
      if Side then
      begin
        Book.Text(CheckX, Y + 6, 'Laid by ______________________', 9, clBlack);
        Book.Text(CheckX, Y + 13, 'Date __________', 9, clBlack);
        Book.Text(CheckX, Y + 20, 'Checked by ___________________', 9, clBlack);
      end
      else
        Book.Text(Left, Y + 4, 'Laid by ____________________   Date __________   Checked by ____________________', 9, clBlack);
      Yc := Bottom;
    end;
  end;

begin
  Left := MARGIN; Right := PageW - MARGIN; Wide := Right - Left;
  Top := MARGIN; Bottom := PageH - MARGIN - FOOT;
  if Job.Title <> '' then Title := Job.Title else Title := 'Radiant heat layout';
  Book := TPdfBook.Create(Title + ' - radiant submittal', PageW, PageH);
  try
    NewPage;
    Paired := False;
    for B := 0 to High(Blocks) do
    begin
      { the second of a pair is laid with the first }
      if Paired then begin Paired := False; Continue; end;
      case Blocks[B].Kind of
        skTitle:
          begin
            Need(14);
            Book.Text(Left, Yc + 7, Blocks[B].Text, 16, clBlack, True);
            Yc := Yc + 11;
          end;
        skHeading:
          begin
            Need(14);
            Yc := Yc + 2;
            Book.Text(Left, Yc + 4.5, Blocks[B].Text, 11, clBlack, True);
            Yc := Yc + 6;
            Book.Line(Left, Yc, Right, Yc, $00A0A0A0, 0.2);
            Yc := Yc + 2;
          end;
        skPara: Para(Blocks[B].Text, 9);
        skTable:
          if Blocks[B].Half and (B < High(Blocks)) and (Blocks[B + 1].Kind = skTable) and Blocks[B + 1].Half then
          begin
            TablePair(Blocks[B], Blocks[B + 1]);
            Paired := True;
          end
          else Table(Blocks[B], Left, Wide);
        skPlan: Plan(Blocks[B]);
        skLoopPlans: LoopPlans(Blocks[B]);
        skPageBreak: if Yc > Top + 1 then NewPage;
      end;
    end;
    { the title block on every sheet, now the page count is known }
    N := Book.PageCount;
    Stamp := FormatDateTime('yyyy-mm-dd', Job.When);
    for I := 1 to N do
    begin
      Book.OnPage(I);
      Book.Line(Left, PageH - MARGIN - FOOT + 3, Right, PageH - MARGIN - FOOT + 3, clBlack, 0.3);
      Book.Text(Left, PageH - MARGIN - FOOT + 8, Title, 9, clBlack, True);
      Book.Text(Left, PageH - MARGIN - FOOT + 12, 'Radiant floor heating - submittal', 7, $00404040);
      Book.Text(Left + Wide / 2 - Book.TextWidth(Stamp, 8) / 2, PageH - MARGIN - FOOT + 8, Stamp, 8);
      Book.Text(Left + Wide / 2 - Book.TextWidth(Job.Made, 6) / 2, PageH - MARGIN - FOOT + 12, Job.Made, 6, $00606060);
      Book.Text(Right - Book.TextWidth(Format('sheet %d of %d', [I, N]), 9, True), PageH - MARGIN - FOOT + 8,
        Format('sheet %d of %d', [I, N]), 9, clBlack, True);
    end;
    Book.SaveToFile(Path);
  finally
    Book.Free;
  end;
end;

procedure SubmittalExport(const Job: TRadiantJob; const Path: string);
var
  L: TStringList;
begin
  if LowerCase(ExtractFileExt(Path)) = '.txt' then
  begin
    L := TStringList.Create;
    try
      L.Text := SubmittalAsText(RadiantSubmittal(Job));
      L.SaveToFile(Path);
    finally
      L.Free;
    end;
  end
  else if Job.Units = usImperial then SubmittalToPdf(Job, RadiantSubmittal(Job), Path, 215.9, 279.4)
  else SubmittalToPdf(Job, RadiantSubmittal(Job), Path, 210, 297);
end;

end.

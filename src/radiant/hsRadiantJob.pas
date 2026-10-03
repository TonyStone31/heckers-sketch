unit hsRadiantJob;

{ A radiant job stored in the data of the groups it built (see hsGroupData),
  so a zone can be reopened in the wizard and its submittal reprinted from
  the drawing alone. Every zone's group carries the whole job's settings,
  heat load, floors and manifolds, plus its own layout (full paths) and its
  search's other layouts (records only, no paths, to keep the file small). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, DateUtils, hsDrawing, hsRadiantData, hsRadiant, hsRadiantHeat, hsRadiantSubmittal, hsGroupData;

const
  { the first line of a zone's data, and the version of what follows }
  RADIANT_DATA_VERSION = 1;

{ a name for a new job, unlikely to be any other's }
function NewRadiantJobId: string;
{ zone Z's group's data }
function RadiantJobData(const Job: TRadiantJob; Z: Integer; const JobId: string): string;
{ Is this a radiant zone's data - and which job, which zone? }
function IsRadiantData(const Data: string; out JobId: string; out Zone: Integer): Boolean;
{ the job rebuilt from its zones' group data, in any order, any missing
  (those come back unsearched). False when none of it reads as a radiant job. }
function RadiantJobFromData(const Datas: array of string; out Job: TRadiantJob): Boolean;

implementation

function NewRadiantJobId: string;
begin
  Result := FormatDateTime('yyyymmdd"-"hhnnss', Now) + '-' + IntToHex(Random($10000), 4);
end;

{ ---- writing ---- }

procedure PutHoles(W: TDataWriter; const Holes: TRadiantHoles);
var
  I: Integer;
begin
  for I := 0 to High(Holes) do W.Pts('hole', Holes[I]);
end;

function HolesOf(N: TDataNode): TRadiantHoles;
var
  I: Integer;
  One: TDataNode;
begin
  SetLength(Result, 0);
  for I := 0 to N.Count - 1 do
    if not N.Kid(I).Block and (N.Kid(I).Key = 'hole') then
    begin
      One := TDataNode.Create;
      try
        One.Add('p', N.Kid(I).Value, False);
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := One.Pts('p');
      finally
        One.Free;
      end;
    end;
end;

procedure PutSpec(W: TDataWriter; const Name: string; const S: TRadiantSpec);
var
  I: Integer;
  Ports: array of Double;
begin
  W.Open(Name);
  W.Int('tube', Ord(S.Tube));
  W.Num('spacing', S.Spacing);
  W.Num('maxloop', S.MaxLoopFt);
  W.Num('waste', S.WastePct);
  W.Pts('manifolds', S.Manifolds);
  SetLength(Ports, Length(S.Ports));
  for I := 0 to High(S.Ports) do Ports[I] := S.Ports[I];
  W.Nums('ports', Ports);
  W.Nums('angles', S.ManifoldAngles);
  W.Open('extra');
  PutHoles(W, S.Extra);
  W.Close;
  W.Num('manifoldw', S.ManifoldW);
  W.Num('manifoldh', S.ManifoldH);
  W.Num('slab', S.SlabThick);
  W.Num('depth', S.TubeDepth);
  W.Num('under', S.UnderR);
  W.Text('tag', S.Tag);
  W.Bool('labels', S.Labels);
  W.Num('inch', S.Inch);
  W.Num('goalcover', S.GoalCoverPct);
  W.Num('goaleven', S.GoalEvenPct);
  W.Num('seed', S.SearchSeed);
  W.Int('maxports', S.MaxPorts);
  W.Bool('pin', S.PinManifold);
  W.Bool('lessfriendly', S.LessFriendly);
  W.Bool('nohooks', S.NoHooks);
  W.Bool('hookpairs', S.HookPairs);
  W.Close;
end;

function SpecOf(N: TDataNode): TRadiantSpec;
var
  V: TDataNums;
  I: Integer;
  E: TDataNode;
begin
  Result := DefaultRadiantSpec;
  if N = nil then Exit;
  Result.Tube := TTubeSize(EnsureRange(N.Int('tube', Ord(Result.Tube)), 0, Ord(High(TTubeSize))));
  Result.Spacing := N.Num('spacing', Result.Spacing);
  Result.MaxLoopFt := N.Num('maxloop', 0);
  Result.WastePct := N.Num('waste', Result.WastePct);
  Result.Manifolds := N.Pts('manifolds');
  V := N.Nums('ports');
  SetLength(Result.Ports, Length(V));
  for I := 0 to High(V) do Result.Ports[I] := Round(V[I]);
  Result.ManifoldAngles := N.Nums('angles');
  E := N.Find('extra');
  if E <> nil then Result.Extra := HolesOf(E);
  Result.ManifoldW := N.Num('manifoldw', Result.ManifoldW);
  Result.ManifoldH := N.Num('manifoldh', Result.ManifoldH);
  Result.SlabThick := N.Num('slab', Result.SlabThick);
  Result.TubeDepth := N.Num('depth', 0);
  Result.UnderR := N.Num('under', Result.UnderR);
  Result.Tag := N.Text('tag');
  Result.Labels := N.Bool('labels', False);
  Result.Inch := N.Num('inch', Result.Inch);
  Result.GoalCoverPct := N.Num('goalcover', 0);
  Result.GoalEvenPct := N.Num('goaleven', 0);
  Result.SearchSeed := Cardinal(Round(EnsureRange(N.Num('seed', 0), 0, High(Cardinal))));
  Result.MaxPorts := N.Int('maxports', Result.MaxPorts);
  Result.PinManifold := N.Bool('pin');
  Result.LessFriendly := N.Bool('lessfriendly');
  Result.NoHooks := N.Bool('nohooks');
  Result.HookPairs := N.Bool('hookpairs');
end;

{ a layout - WithPaths, every loop's path as well as its record }
procedure PutResult(W: TDataWriter; const Name: string; const R: TRadiantResult; WithPaths: Boolean);
var
  I: Integer;
begin
  W.Open(Name);
  W.Bool('ok', R.Ok);
  if R.Why <> '' then W.Text('why', R.Why);
  W.Num('area', R.AreaSqFt);
  W.Int('rows', R.RowCount);
  W.Int('obstacles', R.ObstacleCount);
  W.Num('total', R.TotalFt);
  W.Num('order', R.OrderFt);
  W.Nums('turn', [R.TurnActualIn, R.TurnMinIn, R.TurnMinPexAIn]);
  W.Int('crossings', R.Crossings);
  W.Int('cells', R.CellCount);
  W.Num('breakout', R.BreakoutFt);
  W.Int('tries', R.Tries);
  W.Bool('short', R.ShortOfGoals);
  W.Int('bends', R.Bends);
  W.Num('straight', R.StraightPct);
  W.Num('unfilled', R.UnfilledSqFt);
  W.Bool('oddrows', R.OddRows);
  W.Num('tightest', R.TightestGap);
  W.Bool('runts', R.Runts);
  W.Bool('strips', R.Strips);
  W.Num('shift', R.ManifoldShiftFt);
  W.Num('secs', R.SearchSecs);
  W.Num('friendly', R.Friendly);
  if Length(R.SearchLog) > 0 then
  begin
    W.Open('log');
    for I := 0 to High(R.SearchLog) do W.Text('line', R.SearchLog[I]);
    W.Close;
  end;
  for I := 0 to High(R.Manifolds) do
  begin
    W.Open('manifold');
    W.Pts('at', [R.Manifolds[I].At]);
    W.Int('ports', R.Manifolds[I].Ports);
    W.Int('loops', R.Manifolds[I].LoopCount);
    W.Num('ft', R.Manifolds[I].Ft);
    W.Num('heading', R.Manifolds[I].Heading);
    W.Close;
  end;
  for I := 0 to High(R.Loops) do
  begin
    W.Open('loop');
    W.Num('ft', R.Loops[I].LenFt);
    W.Int('manifold', R.Loops[I].Manifold);
    if R.Loops[I].Couple <> 0 then W.Int('couple', R.Loops[I].Couple);
    if (Length(R.LoopFriendly) = Length(R.Loops)) then
      W.Nums('friendly', [R.LoopFriendly[I].Measures, R.LoopFriendly[I].ExtraBends,
        R.LoopFriendly[I].Compact, R.LoopFriendly[I].Score]);
    if WithPaths then W.Pts('path', R.Loops[I].Pts);
    W.Close;
  end;
  W.Close;
end;

function ResultOf(N: TDataNode): TRadiantResult;
var
  I, M, L: Integer;
  K, Log: TDataNode;
  V: TDataNums;
  At: TP3Array;
  AllFriendly: Boolean;
begin
  Result := Default(TRadiantResult);
  Result.Friendly := -1;
  if N = nil then Exit;
  Result.Ok := N.Bool('ok');
  Result.Why := N.Text('why');
  Result.AreaSqFt := N.Num('area');
  Result.RowCount := N.Int('rows');
  Result.ObstacleCount := N.Int('obstacles');
  Result.TotalFt := N.Num('total');
  Result.OrderFt := N.Num('order');
  V := N.Nums('turn');
  if Length(V) >= 3 then
  begin
    Result.TurnActualIn := V[0]; Result.TurnMinIn := V[1]; Result.TurnMinPexAIn := V[2];
  end;
  Result.Crossings := N.Int('crossings');
  Result.CellCount := N.Int('cells');
  Result.BreakoutFt := N.Num('breakout');
  Result.Tries := N.Int('tries');
  Result.ShortOfGoals := N.Bool('short');
  Result.Bends := N.Int('bends');
  Result.StraightPct := N.Num('straight');
  Result.UnfilledSqFt := N.Num('unfilled');
  Result.OddRows := N.Bool('oddrows');
  Result.TightestGap := N.Num('tightest');
  Result.Runts := N.Bool('runts');
  Result.Strips := N.Bool('strips');
  Result.ManifoldShiftFt := N.Num('shift');
  Result.SearchSecs := N.Num('secs');
  Result.Friendly := N.Num('friendly', -1);
  Log := N.Find('log');
  if (Log <> nil) and Log.Block then
    for I := 0 to Log.Count - 1 do
      if Log.Kid(I).Key = 'line' then
      begin
        SetLength(Result.SearchLog, Length(Result.SearchLog) + 1);
        Result.SearchLog[High(Result.SearchLog)] := DataUnquote(Log.Kid(I).Value);
      end;
  AllFriendly := True;
  M := 0; L := 0;
  for I := 0 to N.Count - 1 do
  begin
    K := N.Kid(I);
    if not K.Block then Continue;
    if K.Key = 'manifold' then
    begin
      SetLength(Result.Manifolds, M + 1);
      At := K.Pts('at');
      if Length(At) > 0 then Result.Manifolds[M].At := At[0];
      Result.Manifolds[M].Ports := K.Int('ports');
      Result.Manifolds[M].LoopCount := K.Int('loops');
      Result.Manifolds[M].Ft := K.Num('ft');
      Result.Manifolds[M].Heading := K.Num('heading');
      Inc(M);
    end
    else if K.Key = 'loop' then
    begin
      SetLength(Result.Loops, L + 1);
      SetLength(Result.LoopFriendly, L + 1);
      Result.Loops[L].LenFt := K.Num('ft');
      Result.Loops[L].Manifold := K.Int('manifold');
      Result.Loops[L].Couple := K.Int('couple');
      Result.Loops[L].Pts := K.Pts('path');
      V := K.Nums('friendly');
      if Length(V) >= 4 then
      begin
        Result.LoopFriendly[L].Measures := Round(V[0]);
        Result.LoopFriendly[L].ExtraBends := Round(V[1]);
        Result.LoopFriendly[L].Compact := V[2];
        Result.LoopFriendly[L].Score := V[3];
      end
      else AllFriendly := False;
      Inc(L);
    end;
  end;
  if not AllFriendly then SetLength(Result.LoopFriendly, 0);
end;

procedure PutZone(W: TDataWriter; const Zone: TRadiantZone);
begin
  W.Pts('outline', Zone.Outline);
  PutHoles(W, Zone.Holes);
end;

function ZoneOf(N: TDataNode): TRadiantZone;
begin
  Result := Default(TRadiantZone);
  Result.Outline := N.Pts('outline');
  Result.Holes := HolesOf(N);
end;

function RadiantJobData(const Job: TRadiantJob; Z: Integer; const JobId: string): string;
var
  W: TDataWriter;
  K, I: Integer;
begin
  W := TDataWriter.Create;
  try
    W.Int('radiant', RADIANT_DATA_VERSION);
    W.Text('job', JobId);
    W.Int('zone', Z + 1);
    W.Text('title', Job.Title);
    W.Text('when', FormatDateTime('yyyy-mm-dd hh:nn:ss', Job.When));
    W.Text('made', Job.Made);
    if Job.Units = usMetric then W.Text('units', 'metric') else W.Text('units', 'imperial');
    PutSpec(W, 'spec', Job.Spec);
    W.Open('heat');
    W.Text('job', HeatJobToText(Job.Heat));
    for K := 0 to High(Job.Heat.Zones) do W.Text('zone', HeatZoneToText(Job.Heat.Zones[K]));
    W.Close;
    { every zone's floor, manifold and name - small, and the job needs
      them all }
    for K := 0 to High(Job.Zones) do
    begin
      W.Open('floor');
      if (K <= High(Job.ZoneNames)) and (Job.ZoneNames[K] <> '') then W.Text('name', Job.ZoneNames[K]);
      PutZone(W, Job.Zones[K]);
      if K <= High(Job.Angles) then W.Num('angle', Job.Angles[K]);
      if (K <= High(Job.Pins)) and Job.Pins[K] then W.Bool('pinned', True);
      if K <= High(Job.ZoneSpecs) then PutSpec(W, 'spec', Job.ZoneSpecs[K]);
      W.Close;
    end;
    for K := 0 to High(Job.LeftOut) do
    begin
      W.Open('leftout');
      PutZone(W, Job.LeftOut[K]);
      W.Close;
    end;
    { and this zone's own layout, and what its search kept }
    W.Bool('searched', (Z <= High(Job.Searched)) and Job.Searched[Z]);
    if Z <= High(Job.Layouts) then PutResult(W, 'layout', Job.Layouts[Z], True);
    if (Z <= High(Job.Solutions)) and (Length(Job.Solutions[Z]) > 0) then
    begin
      if Z <= High(Job.Picked) then W.Int('picked', Job.Picked[Z] + 1);
      W.Open('solutions');
      for I := 0 to High(Job.Solutions[Z]) do PutResult(W, 'solution', Job.Solutions[Z][I], False);
      W.Close;
    end;
    Result := W.Done;
  finally
    W.Free;
  end;
end;

function IsRadiantData(const Data: string; out JobId: string; out Zone: Integer): Boolean;
var
  N: TDataNode;
begin
  JobId := '';
  Zone := -1;
  { the first line says so - no need to read the rest to know }
  if Copy(Data, 1, 10) <> 'radiant = ' then Exit(False);
  N := ReadData(Data);
  try
    JobId := N.Text('job');
    Zone := N.Int('zone', 0) - 1;
    Result := (JobId <> '') and (Zone >= 0);
  finally
    N.Free;
  end;
end;

function RadiantJobFromData(const Datas: array of string; out Job: TRadiantJob): Boolean;
var
  Nodes: array of TDataNode;
  I, K, Z, NZ, First: Integer;
  N, H, Sols: TDataNode;
  Dt: TDateTime;
  Hz: TStringArray;
begin
  Job := Default(TRadiantJob);
  Result := False;
  SetLength(Nodes, Length(Datas));
  for I := 0 to High(Datas) do Nodes[I] := ReadData(Datas[I]);
  try
    { the job's own settings from the lowest-numbered zone found }
    First := -1;
    for I := 0 to High(Nodes) do
      if Nodes[I].Has('radiant') and Nodes[I].Has('job') then
      begin
        if (First < 0) or (Nodes[I].Int('zone') < Nodes[First].Int('zone')) then First := I;
      end;
    if First < 0 then Exit;
    N := Nodes[First];
    Job.Title := N.Text('title');
    try
      Dt := ScanDateTime('yyyy-mm-dd hh:nn:ss', N.Text('when'));
    except
      Dt := Now;
    end;
    Job.When := Dt;
    Job.Made := N.Text('made');
    if N.Text('units') = 'metric' then Job.Units := usMetric else Job.Units := usImperial;
    Job.Spec := SpecOf(N.Find('spec'));
    Job.Heat := HeatDefaultJob;
    H := N.Find('heat');
    if (H <> nil) and H.Block then
    begin
      Job.Heat := HeatJobFromText(H.Text('job'));
      SetLength(Hz, 0);
      for I := 0 to H.Count - 1 do
        if H.Kid(I).Key = 'zone' then
        begin
          SetLength(Hz, Length(Hz) + 1);
          Hz[High(Hz)] := DataUnquote(H.Kid(I).Value);
        end;
      SetLength(Job.Heat.Zones, Length(Hz));
      for I := 0 to High(Hz) do Job.Heat.Zones[I] := HeatZoneFromText(Hz[I]);
    end;
    NZ := 0;
    for I := 0 to N.Count - 1 do
      if N.Kid(I).Block and (N.Kid(I).Key = 'floor') then Inc(NZ);
    SetLength(Job.Zones, NZ); SetLength(Job.ZoneSpecs, NZ); SetLength(Job.ZoneNames, NZ);
    SetLength(Job.Angles, NZ); SetLength(Job.Pins, NZ);
    SetLength(Job.Searched, NZ); SetLength(Job.Layouts, NZ);
    SetLength(Job.Solutions, NZ); SetLength(Job.Picked, NZ);
    Z := 0;
    for I := 0 to N.Count - 1 do
      if N.Kid(I).Block and (N.Kid(I).Key = 'floor') then
      begin
        Job.Zones[Z] := ZoneOf(N.Kid(I));
        Job.ZoneNames[Z] := N.Kid(I).Text('name');
        Job.Angles[Z] := N.Kid(I).Num('angle');
        Job.Pins[Z] := N.Kid(I).Bool('pinned');
        Job.ZoneSpecs[Z] := SpecOf(N.Kid(I).Find('spec'));
        Job.Layouts[Z] := Default(TRadiantResult);
        Job.Layouts[Z].Friendly := -1;
        Inc(Z);
      end;
    for I := 0 to N.Count - 1 do
      if N.Kid(I).Block and (N.Kid(I).Key = 'leftout') then
      begin
        SetLength(Job.LeftOut, Length(Job.LeftOut) + 1);
        Job.LeftOut[High(Job.LeftOut)] := ZoneOf(N.Kid(I));
      end;
    { each zone's own, from its own group }
    for I := 0 to High(Nodes) do
    begin
      Z := Nodes[I].Int('zone') - 1;
      if (Z < 0) or (Z >= NZ) or (Nodes[I].Text('job') <> N.Text('job')) then Continue;
      Job.Searched[Z] := Nodes[I].Bool('searched');
      Job.Layouts[Z] := ResultOf(Nodes[I].Find('layout'));
      Sols := Nodes[I].Find('solutions');
      if (Sols <> nil) and Sols.Block then
      begin
        SetLength(Job.Solutions[Z], 0);
        for K := 0 to Sols.Count - 1 do
          if Sols.Kid(K).Block and (Sols.Kid(K).Key = 'solution') then
          begin
            SetLength(Job.Solutions[Z], Length(Job.Solutions[Z]) + 1);
            Job.Solutions[Z][High(Job.Solutions[Z])] := ResultOf(Sols.Kid(K));
          end;
        Job.Picked[Z] := EnsureRange(Nodes[I].Int('picked', 1) - 1, 0, Max(0, High(Job.Solutions[Z])));
        { the one it built is the layout, paths and all }
        if Length(Job.Solutions[Z]) > 0 then Job.Solutions[Z][Job.Picked[Z]] := Job.Layouts[Z];
      end;
    end;
    Result := True;
  finally
    for I := 0 to High(Nodes) do Nodes[I].Free;
  end;
end;

end.

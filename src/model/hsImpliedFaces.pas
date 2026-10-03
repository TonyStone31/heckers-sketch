unit hsImpliedFaces;

{ Faces implied by their edges: the one rule the Heck reader and writer
  share, so they agree.  A face is written only when it is not what the
  lines would give anyway (painted, turned the other way, borrowed edges,
  or "noface").  Regions come from BuildRegions over a scope's lines and
  arcs, the same as RebuildFlatFaces.  A scope is one solid, or the loose
  things of one group; scopes never close loops with each other here. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, hsDrawing, hsFaceFinder;

{ every line, and every arc in pieces, of the things from First on that
  have this Part and this Grp }
function ScopeSegments(D: TWorkDoc; First, Part, Grp: Integer): TSegArray;

{ the middle of a scope, for turning a solid's faces outward: the mean of
  its segments' middles }
function ScopeMid(const Segs: TSegArray): TP3;

{ Is this region exactly this face - the same corners round the outside,
  whichever way round and wherever it starts, and the same holes? }
function RegionIsFace(const R: TRegion; D: TWorkDoc; F: Integer): Boolean;

{ Is this loop the region's outline, as RegionIsFace would see it? }
function SameLoop(const A, B: TP3Array): Boolean;
{ the same, to a tolerance of one's own: the rounding of the text }
function SameLoopTol(const A, B: TP3Array; Tol: Double): Boolean;

{ the loop's normal, unnormalized - Newell's }
function LoopNormal(const L: TP3Array): TP3;

{ The outline as an implied face would carry it, turned the way the tool
  would turn it.  Holes come back turned with it. }
procedure ImpliedLoop(const R: TRegion; InSolid: Boolean; const Mid: TP3;
  out Outer: TP3Array; out Holes: TLoopArray);

type
  { Finds faces by outline without walking every face, which matters on big
    drawings.  A loop is filed by its middle to 0.01 ft plus its corner
    count; a lookup also tries the neighboring cells for rounding. }
  TLoopIndex = class
  private
    FKeys: TStringList;
    FBins: array of TIntArrayW;
    function KeyOf(const L: TP3Array; DX, DY, DZ: Integer): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const L: TP3Array; Id: Integer);
    { the ids filed near this loop - candidates, to be checked }
    function Near(const L: TP3Array): TIntArrayW;
  end;

implementation

constructor TLoopIndex.Create;
begin
  inherited Create;
  FKeys := TStringList.Create;
  FKeys.Sorted := True;
  FKeys.Duplicates := dupIgnore;
end;

destructor TLoopIndex.Destroy;
begin
  FKeys.Free;
  inherited Destroy;
end;

function TLoopIndex.KeyOf(const L: TP3Array; DX, DY, DZ: Integer): string;
var
  C: TP3;
  K: Integer;
begin
  C := P3(0, 0, 0);
  for K := 0 to High(L) do C := P3(C.X + L[K].X, C.Y + L[K].Y, C.Z + L[K].Z);
  K := Length(L);
  if K = 0 then Exit('-');
  Result := Format('%d %d %d %d', [Round(C.X / K * 100) + DX, Round(C.Y / K * 100) + DY,
    Round(C.Z / K * 100) + DZ, K]);
end;

procedure TLoopIndex.Add(const L: TP3Array; Id: Integer);
var
  B: Integer;
  Key: string;
begin
  Key := KeyOf(L, 0, 0, 0);
  B := FKeys.IndexOf(Key);
  if B < 0 then
  begin
    SetLength(FBins, Length(FBins) + 1);
    FKeys.AddObject(Key, TObject(PtrInt(High(FBins))));
    B := High(FBins);
  end
  else B := PtrInt(FKeys.Objects[B]);
  SetLength(FBins[B], Length(FBins[B]) + 1);
  FBins[B][High(FBins[B])] := Id;
end;

function TLoopIndex.Near(const L: TP3Array): TIntArrayW;
var
  DX, DY, DZ, B, K, N: Integer;
begin
  N := 0;
  SetLength(Result, 0);
  for DX := -1 to 1 do
    for DY := -1 to 1 do
      for DZ := -1 to 1 do
      begin
        B := FKeys.IndexOf(KeyOf(L, DX, DY, DZ));
        if B < 0 then Continue;
        B := PtrInt(FKeys.Objects[B]);
        for K := 0 to High(FBins[B]) do
        begin
          SetLength(Result, N + 1);
          Result[N] := FBins[B][K];
          Inc(N);
        end;
      end;
end;

function ScopeSegments(D: TWorkDoc; First, Part, Grp: Integer): TSegArray;
var
  I, K, N, Steps: Integer;
  A: TP3;
begin
  N := 0;
  SetLength(Result, 64);
  for I := First to D.Live - 1 do
  begin
    if (D[I].Part <> Part) or (D[I].Grp <> Grp) then Continue;
    case D[I].Kind of
      ekLine:
        begin
          if N >= Length(Result) then SetLength(Result, N * 2);
          Result[N].A := D[I].A;
          Result[N].B := D[I].B;
          Inc(N);
        end;
      ekArc:
        begin
          A := ArcPoint(D[I].C, D[I].R, D[I].A0, D[I].Plane, D[I].Nm);
          Steps := ArcSteps(D[I]);
          for K := 1 to Steps do
          begin
            if N >= Length(Result) then SetLength(Result, N * 2);
            Result[N].A := A;
            A := ArcPoint(D[I].C, D[I].R, D[I].A0 + D[I].Sweep * K / Steps,
              D[I].Plane, D[I].Nm);
            Result[N].B := A;
            Inc(N);
          end;
        end;
    end;
  end;
  SetLength(Result, N);
end;

function ScopeMid(const Segs: TSegArray): TP3;
var
  I: Integer;
begin
  Result := P3(0, 0, 0);
  if Length(Segs) = 0 then Exit;
  for I := 0 to High(Segs) do
    Result := P3(Result.X + (Segs[I].A.X + Segs[I].B.X) / 2,
                 Result.Y + (Segs[I].A.Y + Segs[I].B.Y) / 2,
                 Result.Z + (Segs[I].A.Z + Segs[I].B.Z) / 2);
  Result := P3(Result.X / Length(Segs), Result.Y / Length(Segs), Result.Z / Length(Segs));
end;

function SameLoopTol(const A, B: TP3Array; Tol: Double): Boolean;
var
  I, J: Integer;
  Hit: Boolean;
begin
  Result := False;
  if Length(A) <> Length(B) then Exit;
  for I := 0 to High(A) do
  begin
    Hit := False;
    for J := 0 to High(B) do
      if SamePt(A[I], B[J], Tol) then begin Hit := True; Break; end;
    if not Hit then Exit;
  end;
  Result := True;
end;

function SameLoop(const A, B: TP3Array): Boolean;
begin
  Result := SameLoopTol(A, B, 1E-6);
end;

function RegionIsFace(const R: TRegion; D: TWorkDoc; F: Integer): Boolean;
var
  H, K: Integer;
  Hit: Boolean;
begin
  Result := False;
  if D[F].Kind <> ekFace then Exit;
  if not SameLoop(R.Outer, D[F].Poly) then Exit;
  if Length(R.Holes) <> Length(D[F].Holes) then Exit;
  for H := 0 to High(R.Holes) do
  begin
    Hit := False;
    for K := 0 to High(D[F].Holes) do
      if SameLoop(R.Holes[H], D[F].Holes[K]) then begin Hit := True; Break; end;
    if not Hit then Exit;
  end;
  Result := True;
end;

procedure Reverse(var L: TP3Array);
var
  I, N: Integer;
  T: TP3;
begin
  N := Length(L);
  for I := 0 to N div 2 - 1 do
  begin
    T := L[I];
    L[I] := L[N - 1 - I];
    L[N - 1 - I] := T;
  end;
end;

function LoopNormal(const L: TP3Array): TP3;
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

procedure ImpliedLoop(const R: TRegion; InSolid: Boolean; const Mid: TP3;
  out Outer: TP3Array; out Holes: TLoopArray);
var
  I: Integer;
  Nm, Inner: TP3;
  Flip: Boolean;
begin
  Outer := Copy(R.Outer);
  SetLength(Holes, Length(R.Holes));
  for I := 0 to High(R.Holes) do Holes[I] := Copy(R.Holes[I]);
  Nm := LoopNormal(Outer);
  if InSolid then
  begin
    Inner := InnerPoint(R.Outer, R.Normal);
    Flip := Dot3(Nm, P3(Inner.X - Mid.X, Inner.Y - Mid.Y, Inner.Z - Mid.Z)) < 0;
  end
  else
  begin
    { OrientFace's rule: the biggest component of the normal is positive }
    if (Abs(Nm.Z) >= Abs(Nm.X)) and (Abs(Nm.Z) >= Abs(Nm.Y)) then Flip := Nm.Z < 0
    else if Abs(Nm.Y) >= Abs(Nm.X) then Flip := Nm.Y < 0
    else Flip := Nm.X < 0;
  end;
  if Flip then
  begin
    Reverse(Outer);
    for I := 0 to High(Holes) do Reverse(Holes[I]);
  end;
end;

end.

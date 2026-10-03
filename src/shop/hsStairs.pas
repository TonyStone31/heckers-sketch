unit hsStairs;

{ A straight flight between two width lines. All lengths are drawing units.
  Copyright (c) 2026 Tony Stone - MIT, see LICENSE. }
{$mode objfpc}{$H+}
interface
uses SysUtils, Math, Types, Graphics, hsDrawing;
type
  TStairFrame = record
    Bottom, Across, Forward: TP3;
    Width, Rise, Run: Double;
  end;
  TStairSpec = record
    Risers: Integer;
    Thickness, Nosing: Double;
    ClosedRisers, Bullnose: Boolean;
  end;
type
  TStairUse = (suResidential, suGeneral, suComfort, suCarrying, suADA, suEgress, suService);
  TStairAdvice = record
    SuggestedRisers, IdealRisers, FitCount: Integer;
    IdealRun, TargetRise, TargetGoing, PreferredWidth: Double;
    Fits, CurrentFits: Boolean;
    { a few short notes; Problems has one line per setting out of range }
    Summary: string;
    Problems: TStringArray;
    { whose rules: "the IRC", "OSHA" }
    Profile: string;
  end;
function StairMeasure(Value: Double; U: TUnitSystem): string;
function StairLen(Value: Double; U: TUnitSystem): string;
function RecommendStairs(const F: TStairFrame; U: TUnitSystem;
  Use: TStairUse; const S: TStairSpec): TStairAdvice;
{ the flight between two lines (see the body); FromUpper means the upper line
  sets the width and position, else the lower }
function StairFrame(const A, B, C, D: TP3; out F: TStairFrame;
  out Why: string; FromUpper: Boolean = False): Boolean;
function StairCheck(const F: TStairFrame; const S: TStairSpec; out Why: string): Boolean;
{ a flight from typed sizes at the origin, running along X with its width
  along Y, placed afterward when no lines were picked }
function StairFrameFree(Rise, Run, Width: Double): TStairFrame;
function StairDefaults(const F: TStairFrame; U: TUnitSystem): TStairSpec;
{ Builds the flight as its own group, or into IntoPart (an existing stair
  group the caller has emptied).  Jig, if given, records what made it.
  Returns the first new entity's index. }
function BuildStairs(Doc: TWorkDoc; const F: TStairFrame;
  const S: TStairSpec; Ink: TColor; Weight: Single; IntoPart: Integer = 0;
  const Jig: string = ''): Integer;
{ the jig line for the stairs' group; see the note in the implementation }
function StairJig(const F: TStairFrame; const S: TStairSpec; Use: TStairUse): string;
{ whether a jig line is a stairs line, and what it says }
function IsStairJig(const Spec: string): Boolean;
function StairFromJig(const Spec: string; U: TUnitSystem; out F: TStairFrame; out S: TStairSpec;
  out Use: TStairUse): Boolean;
{ the flight from three picked points: the bottom where the first riser
  stands, the top at the landing edge, and a point out to the side at the
  full width }
function StairFramePicked(const Bottom, Top, SidePt: TP3; out F: TStairFrame; out Why: string): Boolean;
implementation
{ a length as the trade says it on a stair: inches alone under a foot -
  7 3/8", not 0'-7 3/8" }
function StairLen(Value: Double; U: TUnitSystem): string;
begin
  Result:=FormatLen(Value,U);
  if (U=usImperial) and (Copy(Result,1,3)='0''-') then Delete(Result,1,3);
end;

{ a stair measure in sixteenths (6 7/8") with the exact figure beside, since
  a divided-out rise rarely lands on a sixteenth }
function StairMeasure(Value: Double; U: TUnitSystem): string;
begin
  { inches alone under a foot - 7 3/8", not 0'-7 3/8" }
  if U=usImperial then
  begin
    Result:=StairLen(Value,U)+Format(' (%.3f in)',[Value*12]);
  end
  else Result:=Format('%.1f mm',[Value*1000]);
end;

{ Checks the flight against US reference dimensions and comfort preferences
  (sources in docs/help/stairs.html).  Not a full code check: occupancy,
  clear width, rails and landings are not covered.  Problems are one line
  each, shown in red; Summary is a few short notes.  Keep both brief. }
function RecommendStairs(const F: TStairFrame; U: TUnitSystem;
  Use: TStairUse; const S: TStairSpec): TStairAdvice;
var
  Inch, TargetR, TargetG, MaxR, MinR, MinG, MaxG, R, G, Pitch, Score, Best, Extra: Double;
  N, BestN: Integer;
  Who: string;

  function Len(Inches: Double): string;
  begin Result := StairLen(Inches * Inch, U); end;

  procedure Note(const Text: string);
  begin
    if Result.Summary <> '' then Result.Summary := Result.Summary + LineEnding;
    Result.Summary := Result.Summary + Text;
  end;

  procedure Problem(const Text: string);
  begin
    SetLength(Result.Problems, Length(Result.Problems) + 1);
    Result.Problems[High(Result.Problems)] := Text;
  end;

begin
  Result := Default(TStairAdvice);
  if U = usImperial then Inch := 1/12 else Inch := 0.0254;
  MinR:=4; MaxG:=1E30;
  case Use of
    suComfort: begin MaxG:=16; TargetR:=6; TargetG:=12; MaxR:=6.5; MinG:=12; Result.PreferredWidth:=42*Inch; Who:='a gentler stair'; end;
    suCarrying: begin MaxG:=16; TargetR:=6; TargetG:=13; MaxR:=6.5; MinG:=12.5; Result.PreferredWidth:=48*Inch; Who:='carrying things'; end;
    suService: begin MinR:=0; TargetR:=8; TargetG:=10; MaxR:=9.5; MinG:=9.5; Result.PreferredWidth:=22*Inch; Who:='OSHA'; end;
    { a house: IRC R311.7 - 7 3/4" rise at most, 10" tread at least, 36" wide }
    suResidential: begin TargetR:=7.25; TargetG:=10.5; MaxR:=7.75; MinG:=10; Result.PreferredWidth:=36*Inch; Who:='the IRC'; end;
    suADA: begin TargetR:=6.5; TargetG:=11.5; MaxR:=7; MinG:=11; Result.PreferredWidth:=44*Inch; Who:='the ADA'; end;
  else begin TargetR:=6.5; TargetG:=11.5; MaxR:=7; MinG:=11; Result.PreferredWidth:=44*Inch; Who:='the IBC'; end;
  end;
  Result.Profile := Who;
  Result.TargetRise := TargetR*Inch; Result.TargetGoing := TargetG*Inch;
  Result.IdealRisers := EnsureRange(Round(F.Rise / Result.TargetRise),2,200);
  while (Result.IdealRisers < 200) and
    (F.Rise / Result.IdealRisers > MaxR*Inch) do Inc(Result.IdealRisers);
  Result.IdealRun := (Result.IdealRisers-1)*Result.TargetGoing;
  { every riser count that fits the rise, the going and (for OSHA) the
    pitch, ranked by how close it is to the preferred proportions }
  Best := 1E30; BestN := 0;
  for N := 2 to 200 do
  begin
    R:=F.Rise/N/Inch; G:=F.Run/(N-1)/Inch;
    Pitch:=RadToDeg(ArcTan2(R,G));
    if (R<MinR-1E-8) or (R>MaxR+1E-8) or (G<MinG-1E-8) or (G>MaxG+1E-8) then Continue;
    if (Use=suService) and ((Pitch<30-1E-8) or (Pitch>50+1E-8)) then Continue;
    Inc(Result.FitCount);
    Score:=Sqr((R-TargetR)/0.5)+Sqr(G-TargetG);
    if Score<Best then begin Best:=Score; BestN:=N; end;
  end;
  Result.Fits:=BestN<>0;
  if Result.Fits then Result.SuggestedRisers:=BestN
  else Result.SuggestedRisers:=Result.IdealRisers;

  { the notes: the reference in a line, the best fit, the run it wants }
  case Use of
    suResidential: Note('IRC R311.7: rise 7 3/4" at most, tread 10" at least, 36" wide.');
    suService: Note('OSHA 1910.25: 30 to 50 degrees, rise 9 1/2" at most, tread 9 1/2" at least.');
    suADA: Note('ADA 504: rise 4" to 7", tread 11" at least, closed risers.');
    suComfort: Note('A gentler stair: about 6" rise and 12" tread (a preference, not a code).');
    suCarrying: Note('For carrying: about 6" rise and 13" tread (a preference, not a code).');
  else Note('IBC 1011.5: rise 4" to 7", tread 11" at least, 44" wide.');
  end;
  if Result.Fits then
    Note(Format('Best fit here: %d risers - %s rise, %s tread.',
      [BestN, StairLen(F.Rise/BestN,U), StairLen(F.Run/(BestN-1),U)]))
  else
    Note('No riser count fits in this run.');
  Extra:=Result.IdealRun-F.Run;
  if Extra>Inch/64 then
    Note(Format('%d risers want %s of run - %s more; move the bottom farther out, or turn at a landing.',
      [Result.IdealRisers, StairLen(Result.IdealRun,U), StairLen(Extra,U)]));
  if (Use=suResidential) and not S.ClosedRisers then
    Note('Open risers: no gap between treads may pass a 4" ball.');

  { the problems: the settings as they are, a line each }
  if (S.Risers>=2) and (S.Risers<=200) then
  begin
    R:=F.Rise/S.Risers/Inch; G:=F.Run/(S.Risers-1)/Inch;
    Pitch:=RadToDeg(ArcTan2(R,G));
    if R>MaxR+1E-8 then Problem(Format('Rise %s - %s allows %s at most', [Len(R), Who, Len(MaxR)]));
    if (MinR>0) and (R<MinR-1E-8) then Problem(Format('Rise %s - %s wants %s at least', [Len(R), Who, Len(MinR)]));
    if G<MinG-1E-8 then Problem(Format('Tread %s - %s wants %s at least', [Len(G), Who, Len(MinG)]));
    if G>MaxG+1E-8 then Problem(Format('Tread %s - %s at most', [Len(G), Len(MaxG)]));
    if (Use=suService) and ((Pitch<30-1E-8) or (Pitch>50+1E-8)) then
      Problem(Format('%.0f degrees - OSHA wants 30 to 50', [Pitch]));
    if (Use=suResidential) and (G<11-1E-8) and ((S.Nosing<0.75*Inch-1E-8) or (S.Nosing>1.25*Inch+1E-8)) then
      Problem(Format('Nosing %s - with a tread under 11", the IRC wants 3/4" to 1 1/4"', [StairLen(S.Nosing,U)]));
  end;
  if (Use in [suGeneral,suADA,suEgress]) and not S.ClosedRisers then Problem('Open risers - '+Who+' wants them closed');
  if not (Use in [suService,suResidential]) and (S.Nosing>1.5*Inch+1E-8) then
    Problem(Format('Nosing %s - 1 1/2" at most', [StairLen(S.Nosing,U)]));
  if (Use in [suGeneral,suADA,suEgress]) and S.Bullnose and (S.Thickness/2>0.5*Inch+1E-8) then
    Problem('Rounded nose wider than 1/2" radius - '+Who+' wants 1/2" at most');
  if (Use in [suResidential,suGeneral,suEgress]) and (F.Width<Result.PreferredWidth-1E-8) then
    Problem(Format('Width %s - %s wants %s at least', [StairLen(F.Width,U), Who, StairLen(Result.PreferredWidth,U)]))
  else if F.Width<Result.PreferredWidth-1E-8 then
    Note(Format('Narrower than the %s preferred for %s.', [StairLen(Result.PreferredWidth,U), Who]));
  Result.CurrentFits:=Length(Result.Problems)=0;
end;

function Plus(const A, B: TP3): TP3;
begin Result := P3(A.X+B.X,A.Y+B.Y,A.Z+B.Z); end;
function Minus(const A, B: TP3): TP3;
begin Result := P3(A.X-B.X,A.Y-B.Y,A.Z-B.Z); end;
function Times(const A: TP3; K: Double): TP3;
begin Result := P3(A.X*K,A.Y*K,A.Z*K); end;
{ The flight between two level, parallel lines: the lower at the floor, the
  upper at the landing.  The height between them is the rise, the plan
  distance the run.  The lines need not match or line up: FromUpper picks
  which one sets the width and position, and the flight runs square from it.
  Lines can be picked in either order and either direction. }
function StairFrame(const A, B, C, D: TP3; out F: TStairFrame;
  out Why: string; FromUpper: Boolean = False): Boolean;
var L0,L1,H0,H1,T,AB,CD,Delta,Side: TP3; LenL,LenH,Tol,Off: Double;
begin
  Result := False; F := Default(TStairFrame); Why := '';
  L0:=A; L1:=B; H0:=C; H1:=D;
  if (A.Z+B.Z) > (C.Z+D.Z) then begin L0:=C; L1:=D; H0:=A; H1:=B; end;
  LenL:=Dist(L0,L1); LenH:=Dist(H0,H1);
  Tol:=Max(1E-7,Max(LenL,LenH)*1E-6);
  if (LenL<=Tol) or (LenH<=Tol) then begin Why:='Both lines must have length.'; Exit; end;
  if (Abs(L0.Z-L1.Z)>Tol) or (Abs(H0.Z-H1.Z)>Tol) then
    begin Why:='Each line must be level - drawn flat, at one height.'; Exit; end;
  AB:=Minus(L1,L0); CD:=Minus(H1,H0);
  if Dot3(AB,CD)<0 then begin T:=H0; H0:=H1; H1:=T; CD:=Minus(H1,H0); end;
  { parallel, to a hair in a thousand }
  if Dist(Times(AB,1/LenL),Times(CD,1/LenH))>1E-3 then
    begin Why:='The two lines must be parallel - the stairs run square to them.'; Exit; end;
  F.Rise:=((H0.Z+H1.Z)-(L0.Z+L1.Z))/2;
  if F.Rise<=Tol then begin Why:='One line must be above the other: the lower at the floor, the upper at the landing.'; Exit; end;
  { the width line and the square run from it, in plan }
  if FromUpper then begin F.Width:=LenH; F.Across:=Times(CD,1/LenH); end
  else begin F.Width:=LenL; F.Across:=Times(AB,1/LenL); end;
  Delta:=Minus(H0,L0); Delta.Z:=0;
  Off:=Dot3(Delta,F.Across);
  Side:=Minus(Delta,Times(F.Across,Off));
  F.Run:=Dist(Side,P3(0,0,0));
  if F.Run<=Tol then begin Why:='The lines are one above the other - move the lower line out from the landing to give the stairs a run.'; Exit; end;
  F.Forward:=Times(Side,1/F.Run);
  { the corner the flight is built from, at floor level: the lower line's
    start, or the upper line's brought down and back by the run }
  if FromUpper then begin F.Bottom:=Minus(H0,Times(F.Forward,F.Run)); F.Bottom.Z:=L0.Z; end
  else F.Bottom:=L0;
  Result:=True;
end;
function StairDefaults(const F: TStairFrame; U: TUnitSystem): TStairSpec;
var Inch: Double;
begin
  if U=usImperial then Inch:=1/12 else Inch:=0.0254;
  Result.Risers:=EnsureRange(Ceil(F.Rise/(7*Inch)),2,200);
  Result.Thickness:=Min(Inch,F.Rise/Result.Risers/4);
  { one inch fits the IRC's 3/4 to 1 1/4 (treads under 11") and the ADA's
    1 1/2 maximum }
  Result.Nosing:=Inch;
  Result.ClosedRisers:=True; Result.Bullnose:=False;
end;
function StairFrameFree(Rise, Run, Width: Double): TStairFrame;
begin
  Result := Default(TStairFrame);
  Result.Rise := Rise; Result.Run := Run; Result.Width := Width;
  Result.Bottom := P3(0, 0, 0);
  Result.Forward := P3(1, 0, 0);
  Result.Across := P3(0, 1, 0);
end;

function StairCheck(const F: TStairFrame; const S: TStairSpec; out Why: string): Boolean;
var R,G: Double;
begin
  Result:=False; Why:='';
  if (F.Width<=0) or (F.Rise<=0) or (F.Run<=0) then
    begin Why:='Width, rise and run must be positive.'; Exit; end;
  if (S.Risers<2) or (S.Risers>200) then
    begin Why:='Choose between 2 and 200 risers.'; Exit; end;
  R:=F.Rise/S.Risers; G:=F.Run/(S.Risers-1);
  if (S.Thickness<=0) or (S.Thickness>=R) or (S.Thickness>=G) then
    begin Why:='Board thickness must be positive and smaller than rise and going.'; Exit; end;
  if (S.Nosing<0) or (S.Nosing>=G) then
    begin Why:='Nosing must be zero or positive, and smaller than the going.'; Exit; end;
  Result:=True;
end;
function BuildStairs(Doc: TWorkDoc; const F: TStairFrame;
  const S: TStairSpec; Ink: TColor; Weight: Single; IntoPart: Integer = 0;
  const Jig: string = ''): Integer;
var
  Why:string; Part,I,J,G,First:Integer; R,Going,X,Z,Radius,Angle:Double;
  Profile:array of TPointF;
  LeftSide,RightSide,Cap:TP3Array;
  function World(X,Y,Z:Double):TP3;
  begin Result:=Plus(F.Bottom,Plus(Times(F.Forward,X),Times(F.Across,Y))); Result.Z:=Result.Z+Z; end;
  procedure Prism;
  var K,N:Integer;
  begin
    N:=Length(Profile); G:=Doc.NewGroup;
    SetLength(LeftSide,N); SetLength(RightSide,N); SetLength(Cap,N);
    for K:=0 to N-1 do begin
      LeftSide[K]:=World(Profile[K].X,0,Profile[K].Y);
      RightSide[K]:=World(Profile[K].X,F.Width,Profile[K].Y);
      Cap[N-1-K]:=LeftSide[K];
    end;
    First:=Doc.Live;
    Doc.AddFaceRaw(Cap,Ink,True); Doc.AddFaceRaw(RightSide,Ink,True);
    for K:=0 to N-1 do
      Doc.AddFaceRaw([LeftSide[K],LeftSide[(K+1) mod N],RightSide[(K+1) mod N],RightSide[K]],Ink,True);
    for K:=First to Doc.Live-1 do begin Doc.SetGroup(K,G); Doc.SetPart(K,Part);
      if Dot3(Cross3(F.Forward,P3(0,0,1)),F.Across)<0 then Doc.FlipFace(K); end;
    for K:=0 to N-1 do begin
      Doc.AddLine(LeftSide[K],LeftSide[(K+1) mod N],Ink,Weight,False); Doc.SetGroup(Doc.Live-1,G); Doc.SetPart(Doc.Live-1,Part);
      Doc.AddLine(RightSide[K],RightSide[(K+1) mod N],Ink,Weight,False); Doc.SetGroup(Doc.Live-1,G); Doc.SetPart(Doc.Live-1,Part);
      Doc.AddLine(LeftSide[K],RightSide[K],Ink,Weight,False); Doc.SetGroup(Doc.Live-1,G); Doc.SetPart(Doc.Live-1,Part);
    end;
  end;
  procedure Box(X0,Z0,X1,Z1:Double);
  begin
    SetLength(Profile,4);
    Profile[0]:=PointF(X0,Z0); Profile[1]:=PointF(X1,Z0);
    Profile[2]:=PointF(X1,Z1); Profile[3]:=PointF(X0,Z1); Prism;
  end;
begin
  if not StairCheck(F,S,Why) then raise Exception.Create(Why);
  if Doc=nil then raise Exception.Create('No drawing for the stairs.');
  Result:=Doc.Live;
  if IntoPart>0 then Part:=IntoPart
  else Part:=Doc.NewPart('Stairs',Doc.Context);
  if Jig<>'' then Doc.SetPartJig(Part,Jig);
  R:=F.Rise/S.Risers; Going:=F.Run/(S.Risers-1);
  for I:=0 to S.Risers-2 do begin
    X:=I*Going; Z:=(I+1)*R;
    if not S.Bullnose then Box(X-S.Nosing,Z-S.Thickness,X+Going,Z)
    else begin
      Radius:=Min(S.Thickness/2,(Going+S.Nosing)/2);
      SetLength(Profile,11);
      Profile[0]:=PointF(X+Going,Z-S.Thickness);
      for J:=0 to 8 do begin
        Angle:=-Pi/2-J*Pi/8;
        Profile[J+1]:=PointF(X-S.Nosing+Radius+Radius*Cos(Angle),Z-Radius+Radius*Sin(Angle));
      end;
      Profile[10]:=PointF(X+Going,Z);
      { Reverse the rounded profile to the same winding as Box. }
      for J:=0 to 4 do begin
        X:=Profile[J].X; Z:=Profile[J].Y;
        Profile[J]:=Profile[10-J]; Profile[10-J]:=PointF(X,Z);
      end;
      Prism;
    end;
  end;
  if S.ClosedRisers then
    for I:=0 to S.Risers-1 do begin
      X:=I*Going; Z:=(I+1)*R;
      if I<S.Risers-1 then Z:=Z-S.Thickness;
      Box(X,I*R,X+S.Thickness,Z);
    end;
end;
{ ---- a flight that remembers how it was made ----

  The stairs' group carries a 'stairs' jig line with every dialog value, so
  the dialog can reopen it for changes.  Nothing runs on open.  'stairs' is
  built in, never a script in the jigs folder.  Lengths are in drawing units
  (feet or meters) at full precision; 8'1 1/4" also reads.  Points are three
  values and directions an angle, since jig values are comma separated. }

const
  STAIR_JIG = 'stairs';
  USE_WORDS: array[TStairUse] of string = ('house', 'public', 'gentler', 'carrying', 'ada', 'exit', 'service');

function Num(V: Double): string;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  Result := FloatToStrF(V, ffGeneral, 15, 0, FS);
end;

function StairJig(const F: TStairFrame; const S: TStairSpec; Use: TStairUse): string;
var
  Heading, Side: Double;
begin
  Heading := RadToDeg(ArcTan2(F.Forward.Y, F.Forward.X));
  { the width to the left of the way up, or the right }
  if F.Forward.X * F.Across.Y - F.Forward.Y * F.Across.X >= 0 then Side := 1 else Side := -1;
  Result := Format('''%s'' with Rise = %s, Run = %s, Width = %s, Risers = %d, Board = %s, Nosing = %s, ' +
    'Closed = %d, Round = %d, For = ''%s'', X = %s, Y = %s, Z = %s, Heading = %s, Side = %s',
    [STAIR_JIG, Num(F.Rise), Num(F.Run), Num(F.Width), S.Risers, Num(S.Thickness), Num(S.Nosing),
     Ord(S.ClosedRisers), Ord(S.Bullnose), USE_WORDS[Use], Num(F.Bottom.X), Num(F.Bottom.Y), Num(F.Bottom.Z),
     Num(Heading), Num(Side)]);
end;

function IsStairJig(const Spec: string): Boolean;
begin
  Result := Copy(Trim(Spec), 1, Length(STAIR_JIG) + 2) = '''' + STAIR_JIG + '''';
end;

function StairFromJig(const Spec: string; U: TUnitSystem; out F: TStairFrame; out S: TStairSpec;
  out Use: TStairUse): Boolean;
var
  Rest, Item, Key, Val: string;
  P: Integer;
  V, Heading, Side: Double;
  Got: Integer;
  FS: TFormatSettings;
  K: TStairUse;

  function Number(const T: string; out X: Double): Boolean;
  begin
    Result := TryStrToFloat(T, X, FS) or ParseLen(T, U, X);
  end;

begin
  Result := False;
  F := Default(TStairFrame); S := Default(TStairSpec); Use := suResidential;
  if not IsStairJig(Spec) then Exit;
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  Rest := Trim(Copy(Trim(Spec), Length(STAIR_JIG) + 3, MaxInt));
  if LowerCase(Copy(Rest, 1, 5)) <> 'with ' then Exit;
  Rest := Copy(Rest, 6, MaxInt) + ',';
  Heading := 0; Side := 1; Got := 0;
  while Rest <> '' do
  begin
    P := Pos(',', Rest);
    Item := Trim(Copy(Rest, 1, P - 1));
    Delete(Rest, 1, P);
    P := Pos('=', Item);
    if P = 0 then Continue;
    Key := LowerCase(Trim(Copy(Item, 1, P - 1)));
    Val := Trim(Copy(Item, P + 1, MaxInt));
    if Key = 'for' then
    begin
      Val := LowerCase(StringReplace(Val, '''', '', [rfReplaceAll]));
      for K := Low(TStairUse) to High(TStairUse) do
        if USE_WORDS[K] = Val then Use := K;
      Continue;
    end;
    if not Number(Val, V) then Continue;
    if Key = 'rise' then begin F.Rise := V; Inc(Got); end
    else if Key = 'run' then begin F.Run := V; Inc(Got); end
    else if Key = 'width' then begin F.Width := V; Inc(Got); end
    else if Key = 'risers' then S.Risers := Round(V)
    else if Key = 'board' then S.Thickness := V
    else if Key = 'nosing' then S.Nosing := V
    else if Key = 'closed' then S.ClosedRisers := V <> 0
    else if Key = 'round' then S.Bullnose := V <> 0
    else if Key = 'x' then F.Bottom.X := V
    else if Key = 'y' then F.Bottom.Y := V
    else if Key = 'z' then F.Bottom.Z := V
    else if Key = 'heading' then Heading := V
    else if Key = 'side' then Side := V;
  end;
  if Got < 3 then Exit;
  F.Forward := P3(Cos(DegToRad(Heading)), Sin(DegToRad(Heading)), 0);
  if Side >= 0 then F.Across := P3(-F.Forward.Y, F.Forward.X, 0)
  else F.Across := P3(F.Forward.Y, -F.Forward.X, 0);
  Result := (F.Rise > 0) and (F.Run > 0) and (F.Width > 0);
end;

function StairFramePicked(const Bottom, Top, SidePt: TP3; out F: TStairFrame; out Why: string): Boolean;
var
  D, A0: TP3;
  S: Double;
begin
  Result := False; Why := '';
  F := Default(TStairFrame);
  F.Rise := Top.Z - Bottom.Z;
  D := P3(Top.X - Bottom.X, Top.Y - Bottom.Y, 0);
  F.Run := Dist(D, P3(0, 0, 0));
  if F.Run < 1E-6 then begin Why := 'The top is right above the bottom - the stairs need a run.'; Exit; end;
  F.Forward := P3(D.X / F.Run, D.Y / F.Run, 0);
  A0 := P3(-F.Forward.Y, F.Forward.X, 0);
  S := (SidePt.X - Bottom.X) * A0.X + (SidePt.Y - Bottom.Y) * A0.Y;
  if S < 0 then begin F.Across := P3(-A0.X, -A0.Y, 0); F.Width := -S; end
  else begin F.Across := A0; F.Width := S; end;
  F.Bottom := Bottom;
  Result := True;
end;

end.

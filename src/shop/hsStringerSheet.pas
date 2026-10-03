unit hsStringerSheet;

{ The stringer sheet: lumber to buy and how to mark and cut a stringer, for
  both a notched stringer and a solid one with cleats.  Every cut corner is a
  dot given as distance along the board from its squared bottom end and
  distance in from the top edge; join the dots and that is the cut.  Seats sit
  a tread board below the tread tops, so the bottom step is short by that
  (the drop), and closed risers set the plumb cuts back a board. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, Types, Graphics, hsDrawing, hsStairs;

type
  { a corner of the cut: along from the squared bottom end, in from the top
    edge; OnEdge and OnBack mark dots already on an edge }
  TStringerDot = record
    Along, Inn: Double;
    OnEdge, OnBack: Boolean;
    What: string;
  end;
  TStringerDots = array of TStringerDot;

  TStringerPlan = record
    Risers, Treads: Integer;
    UnitRise, Going: Double;     { per step, as the stringer is cut }
    Drop: Double;                { taken off the bottom step: the tread's thickness }
    Setback: Double;             { plumb cuts behind the riser faces: a riser board, or 0 }
    Diagonal: Double;            { a step along the pitch - the dots on the edge are this apart }
    Pitch: Double;               { degrees }
    Depth: Double;               { the board's width - a 2x12's 11 1/4" }
    EdgeIn: Double;              { the nose line's distance in from the top edge - 0 for a cut stringer }
    ChalkIn: Double;             { the inside corners' line, in from the top edge }
    Throat: Double;              { wood left under the deepest corner }
    BoardLen: Double;            { the least board that holds it }
    StockFt: Integer;            { the stock length to buy, feet - 0 when longer than any }
    Count: Integer;              { stringers across the width }
    Spacing: Double;             { their spacing at most, on center }
    Dots: TStringerDots;         { the layout, in order - for a cut stringer, the cut }
    { the outline left after cutting, closed by the back edge: the dots for
      a cut stringer, just the two ends for a solid one }
    Cut: TStringerDots;
  end;

const
  { a 2x12's actual depth, and the throat AWC DCA 6 asks a cut stringer to
    keep (a common benchmark, not code everywhere) }
  STRINGER_DEPTH_IN = 11.25;
  STRINGER_THICK_IN = 1.5;
  THROAT_MIN_IN = 5.0;
  { solid stringer's nose line in from its top edge, so it stands a little
    proud of the treads }
  CLEATED_EDGE_IN = 1.5;

{ the stringer for this flight; Cleated means the solid one with cleats }
function StringerPlan(const F: TStairFrame; const S: TStairSpec; U: TUnitSystem; Cleated: Boolean): TStringerPlan;
{ the sheet as a PDF of letter pages, or A4 for a metric drawing }
procedure StringerSheetPdf(const F: TStairFrame; const S: TStairSpec; Use: TStairUse; U: TUnitSystem;
  const Title, Path: string);

implementation

uses hsPdf;

type
  { Double, not Single: stringer numbers are read to a sixteenth and Single
    adds error }
  TXZ = record X, Z: Double; end;

function XZ(X, Z: Double): TXZ;
begin
  Result.X := X; Result.Z := Z;
end;

function StringerPlan(const F: TStairFrame; const S: TStairSpec; U: TUnitSystem; Cleated: Boolean): TStringerPlan;
var
  Inch, R, G, T, D, Cs, Sn, X0, Z0, UMin, UMax, Dx, EdgeIn: Double;
  FrontTop, TopTop: TXZ;
  I, N: Integer;
  Pts: array of TXZ;         { elevation: x along the flight, z up }
  Kinds: array of Integer;   { 0 cut corner, 1 on the top edge, 2 on the back edge }
  Names: TStringArray;

  procedure Add(X, Z: Double; Kind: Integer; const What: string);
  begin
    SetLength(Pts, Length(Pts) + 1); Pts[High(Pts)] := XZ(X, Z);
    SetLength(Kinds, Length(Kinds) + 1); Kinds[High(Kinds)] := Kind;
    SetLength(Names, Length(Names) + 1); Names[High(Names)] := What;
  end;

  function AlongOf(const P: TXZ): Double;
  begin
    Result := (P.X - X0) * Cs + (P.Z - Z0) * Sn;
  end;

  function InOf(const P: TXZ): Double;
  begin
    Result := (P.X - X0) * Sn - (P.Z - Z0) * Cs + EdgeIn;
  end;

  function DotOf(const P: TXZ; Kind: Integer; const What: string): TStringerDot;
  begin
    Result.Along := AlongOf(P) - UMin + Inch;
    Result.Inn := InOf(P);
    Result.OnEdge := ((Kind = 1) and (EdgeIn = 0)) or (Kind = 3);
    Result.OnBack := Kind = 2;
    if Kind = 2 then Result.Inn := D;
    if Kind = 3 then Result.Inn := 0;
    { snap tiny values to zero so it never prints "-0'-0"" }
    if Abs(Result.Inn) < 1E-9 then Result.Inn := 0;
    Result.What := What;
  end;

begin
  Result := Default(TStringerPlan);
  if U = usImperial then Inch := 1 / 12 else Inch := 0.0254;
  N := Max(2, S.Risers);
  Result.Risers := N;
  Result.Treads := N - 1;
  R := F.Rise / N;
  G := F.Run / (N - 1);
  T := S.Thickness;
  Result.UnitRise := R;
  Result.Going := G;
  Result.Drop := T;
  if S.ClosedRisers then Result.Setback := T else Result.Setback := 0;
  Result.Diagonal := Hypot(R, G);
  Result.Pitch := RadToDeg(ArcTan2(R, G));
  D := STRINGER_DEPTH_IN * Inch;
  Result.Depth := D;
  if Cleated then Result.EdgeIn := CLEATED_EDGE_IN * Inch else Result.EdgeIn := 0;
  EdgeIn := Result.EdgeIn;
  Cs := G / Result.Diagonal; Sn := R / Result.Diagonal;
  Result.ChalkIn := Result.EdgeIn + R * G / Result.Diagonal;
  Result.Throat := D - Result.ChalkIn;

  { the cut in elevation: floor cut, bottom plumb, steps, top plumb.  The
    board's edge line is measured from the first nose. }
  X0 := Result.Setback; Z0 := R - T;
  { where the back edge meets the floor, measured from the first nose }
  Dx := ((D - Result.EdgeIn) * Result.Diagonal - (R - T) * G) / R;
  Add(X0 + Dx, 0, 2, 'floor cut, on the back edge');
  Add(X0, 0, 0, 'foot of the first riser');
  for I := 0 to N - 2 do
  begin
    Add(X0 + I * G, (I + 1) * R - T, 1, Format('nose %d', [I + 1]));
    Add(X0 + (I + 1) * G, (I + 1) * R - T, 0, Format('corner %d', [I + 1]));
  end;
  Add(X0 + (N - 1) * G, N * R - T, 1, 'top nose - under the landing''s floor');
  { the top plumb, down to the back edge }
  Add(X0 + (N - 1) * G, N * R - T - (D - Result.EdgeIn) * Result.Diagonal / G, 2, 'top plumb cut, on the back edge');

  { a solid stringer is cut plumb at both ends up to its top edge, EdgeIn
    beyond the nose line }
  FrontTop := XZ(X0, R - T + EdgeIn / Cs);
  TopTop := XZ(X0 + (N - 1) * G, N * R - T + EdgeIn / Cs);
  { along the board from its bottom end, with an inch spare at each end }
  UMin := 1E30; UMax := -1E30;
  for I := 0 to High(Pts) do
  begin
    UMin := Min(UMin, AlongOf(Pts[I]));
    UMax := Max(UMax, AlongOf(Pts[I]));
  end;
  if Cleated then
  begin
    UMin := Min(UMin, AlongOf(FrontTop)); UMax := Max(UMax, AlongOf(TopTop));
  end;
  { where the stringer stands proud, the top edge runs past the nose line;
    that counts in the board length, not the cut }
  Result.BoardLen := UMax - UMin + 2 * Inch;
  SetLength(Result.Dots, Length(Pts));
  for I := 0 to High(Pts) do Result.Dots[I] := DotOf(Pts[I], Kinds[I], Names[I]);
  if not Cleated then Result.Cut := Copy(Result.Dots)
  else
  begin
    SetLength(Result.Cut, 5);
    Result.Cut[0] := Result.Dots[0];
    Result.Cut[1] := Result.Dots[1];
    Result.Cut[2] := DotOf(FrontTop, 3, 'front end, on the top edge');
    Result.Cut[3] := DotOf(TopTop, 3, 'top end, on the top edge');
    Result.Cut[4] := Result.Dots[High(Result.Dots)];
  end;
  { what to buy: the stock lengths a yard carries }
  Result.StockFt := 0;
  for I := 4 to 12 do
    if Result.BoardLen <= I * 2 * 12 * Inch + 1E-9 then begin Result.StockFt := I * 2; Break; end;
  { at most 16" apart under treads thinner than two-by, 24" under two-by,
    and one at each side }
  if S.Thickness >= 1.5 * Inch - 1E-9 then Result.Spacing := 24 * Inch else Result.Spacing := 16 * Inch;
  Result.Count := Max(2, Ceil((F.Width - STRINGER_THICK_IN * Inch) / Result.Spacing - 1E-9) + 1);
  if Cleated then Result.Count := Max(2, Result.Count);
end;

{ ---- the sheet ---- }

type
  TSheet = class
    Book: TPdfBook;
    U: TUnitSystem;
    Inch: Double;
    Y, L, W: Double;           { where the next line goes, the left margin, the width }
    Title: string;
    procedure Page;
    procedure Head(const S: string);
    procedure Para(const S: string; Size: Double = 10; Ink: TColor = clBlack; Bold: Boolean = False);
    procedure Bullet(const S: string);
    procedure Numbered(N: Integer; const S: string);
    procedure Row(const A, B: string);
    function Len(V: Double): string;
    procedure Board(const P: TStringerPlan);
    procedure DotTable(const P: TStringerPlan);
  end;

function TSheet.Len(V: Double): string;
begin
  Result := StairLen(V, U);
end;

procedure TSheet.Page;
begin
  Book.NewPage;
  Y := 16;
  Book.Text(L, Y, Title, 9, $00707070);
  Y := Y + 8;
end;

procedure TSheet.Head(const S: string);
begin
  if Y > Book.Height - 40 then Page;
  Y := Y + 3;
  Book.Text(L, Y, S, 13, clBlack, True);
  Y := Y + 2;
  Book.Line(L, Y, L + W, Y, $00B0B0B0, 0.3);
  Y := Y + 5;
end;

{ words wrapped to the width }
procedure TSheet.Para(const S: string; Size: Double; Ink: TColor; Bold: Boolean);
var
  Words: TStringArray;
  Line_, Try_: string;
  I: Integer;
  Lh: Double;
begin
  Lh := Size * 0.3528 * 1.35;
  Words := S.Split([' ']);
  Line_ := '';
  for I := 0 to High(Words) do
  begin
    if Line_ = '' then Try_ := Words[I] else Try_ := Line_ + ' ' + Words[I];
    if (Line_ <> '') and (Book.TextWidth(Try_, Size, Bold) > W) then
    begin
      if Y > Book.Height - 18 then Page;
      Book.Text(L, Y, Line_, Size, Ink, Bold);
      Y := Y + Lh;
      Line_ := Words[I];
    end
    else Line_ := Try_;
  end;
  if Line_ <> '' then
  begin
    if Y > Book.Height - 18 then Page;
    Book.Text(L, Y, Line_, Size, Ink, Bold);
    Y := Y + Lh;
  end;
  Y := Y + 1.2;
end;

procedure TSheet.Bullet(const S: string);
var
  WasL, WasW: Double;
begin
  if Y > Book.Height - 18 then Page;
  Book.Text(L + 1, Y, '-', 10);
  WasL := L; WasW := W;
  L := L + 5; W := W - 5;
  Para(S);
  L := WasL; W := WasW;
end;

procedure TSheet.Numbered(N: Integer; const S: string);
var
  WasL, WasW: Double;
begin
  if Y > Book.Height - 18 then Page;
  Book.Text(L, Y, IntToStr(N) + '.', 10, clBlack, True);
  WasL := L; WasW := W;
  L := L + 7; W := W - 7;
  Para(S);
  L := WasL; W := WasW;
end;

procedure TSheet.Row(const A, B: string);
begin
  if Y > Book.Height - 18 then Page;
  Book.Text(L, Y, A, 10);
  Book.Text(L + 80, Y, B, 10, clBlack, True);
  Y := Y + 5;
end;

{ The board with its dots, joining lines and dashed cut, bottom end left and
  top edge up.  Drawn in rows, a piece of board per row, because a full
  stair length across one page is too thin to read. }
procedure TSheet.Board(const P: TStringerPlan);
const
  CUT = $002020D0;
  ROW_MM = 34;
var
  Sc, RowLen, A0, B0, Top, RowH: Double;
  Rows, R, I: Integer;
  Clip, Piece: array of TPointF;

  function At(Along, Inn: Double): TPointF;
  begin
    Result := PointF(L + (Along - A0) * Sc, Top + Inn * Sc);
  end;

  { the part of the segment within the row, or false }
  function InRow(U1, V1, U2, V2: Double; out P1, P2: TPointF): Boolean;
  var
    T0, T1, D: Double;
  begin
    T0 := 0; T1 := 1; D := U2 - U1;
    if Abs(D) < 1E-12 then
    begin
      Result := (U1 >= A0 - 1E-9) and (U1 <= B0 + 1E-9);
    end
    else
    begin
      T0 := Max(T0, Min((A0 - U1) / D, (B0 - U1) / D));
      T1 := Min(T1, Max((A0 - U1) / D, (B0 - U1) / D));
      Result := T0 <= T1;
    end;
    if not Result then Exit;
    P1 := At(U1 + (U2 - U1) * T0, V1 + (V2 - V1) * T0);
    P2 := At(U1 + (U2 - U1) * T1, V1 + (V2 - V1) * T1);
  end;

  { the outline cut to the row: Sutherland-Hodgman against its two ends }
  procedure ClipTo(const Src: TStringerDots);
  var
    Pass, K, J: Integer;
    Bound: Double;
    Inp: array of TPointF;
    CurIn, PrevIn: Boolean;
    Cur, Prev: TPointF;
    function Inside(const Q: TPointF): Boolean;
    begin
      if Pass = 0 then Result := Q.X >= Bound - 1E-9 else Result := Q.X <= Bound + 1E-9;
    end;
    function Cross(const Q1, Q2: TPointF): TPointF;
    var
      T: Double;
    begin
      T := (Bound - Q1.X) / (Q2.X - Q1.X);
      Result := PointF(Bound, Q1.Y + (Q2.Y - Q1.Y) * T);
    end;
  begin
    SetLength(Clip, Length(Src));
    for K := 0 to High(Src) do Clip[K] := PointF(Src[K].Along, Src[K].Inn);
    for Pass := 0 to 1 do
    begin
      if Pass = 0 then Bound := A0 else Bound := B0;
      Inp := Copy(Clip);
      SetLength(Clip, 0);
      if Length(Inp) = 0 then Exit;
      Prev := Inp[High(Inp)];
      PrevIn := Inside(Prev);
      for J := 0 to High(Inp) do
      begin
        Cur := Inp[J];
        CurIn := Inside(Cur);
        if CurIn then
        begin
          if not PrevIn then begin SetLength(Clip, Length(Clip) + 1); Clip[High(Clip)] := Cross(Prev, Cur); end;
          SetLength(Clip, Length(Clip) + 1); Clip[High(Clip)] := Cur;
        end
        else if PrevIn then
        begin
          SetLength(Clip, Length(Clip) + 1); Clip[High(Clip)] := Cross(Prev, Cur);
        end;
        Prev := Cur; PrevIn := CurIn;
      end;
    end;
  end;

  procedure Dashed(const P1, P2: TPointF);
  var
    K, N: Integer;
    Len_: Double;
  begin
    Len_ := Hypot(P2.X - P1.X, P2.Y - P1.Y);
    N := Max(1, Round(Len_ / 3.2));
    for K := 0 to N - 1 do
      Book.Line(P1.X + (P2.X - P1.X) * K / N, P1.Y + (P2.Y - P1.Y) * K / N,
        P1.X + (P2.X - P1.X) * (K + 0.55) / N, P1.Y + (P2.Y - P1.Y) * (K + 0.55) / N, CUT, 0.5);
  end;

var
  Q1, Q2: TPointF;
  Q: TPointF;
begin
  { rows of equal length, as few as keep the board ROW_MM deep or more }
  Sc := ROW_MM / P.Depth;
  Rows := Max(1, Ceil(P.BoardLen * Sc / W - 1E-9));
  RowLen := P.BoardLen / Rows;
  Sc := Min(ROW_MM / P.Depth, W / RowLen);
  RowH := P.Depth * Sc + 13;
  for R := 0 to Rows - 1 do
  begin
    A0 := R * RowLen; B0 := A0 + RowLen;
    if Y + RowH > Book.Height - 18 then Page;
    Top := Y + 5;
    { the board gray, what is left after cutting white }
    Book.Poly([At(A0, 0), At(B0, 0), At(B0, P.Depth), At(A0, P.Depth)], True, $00E4E4E4, 0.01, $00E4E4E4);
    ClipTo(P.Cut);
    if Length(Clip) >= 3 then
    begin
      SetLength(Piece, Length(Clip));
      for I := 0 to High(Clip) do Piece[I] := At(Clip[I].X, Clip[I].Y);
      Book.Poly(Piece, True, clWhite, 0.01, clWhite);
    end;
    { the long edges only; a row's ends are not the board's ends }
    Book.Line(At(A0, 0).X, At(A0, 0).Y, At(B0, 0).X, At(B0, 0).Y, clBlack, 0.35);
    Book.Line(At(A0, P.Depth).X, At(A0, P.Depth).Y, At(B0, P.Depth).X, At(B0, P.Depth).Y, clBlack, 0.35);
    if R = 0 then Book.Line(At(A0, 0).X, At(A0, 0).Y, At(A0, P.Depth).X, At(A0, P.Depth).Y, clBlack, 0.35)
    else Book.Line(At(A0, 0).X, At(A0, 0).Y, At(A0, P.Depth).X, At(A0, P.Depth).Y, $00A0A0A0, 0.15);
    if R = Rows - 1 then Book.Line(At(B0, 0).X, At(B0, 0).Y, At(B0, P.Depth).X, At(B0, P.Depth).Y, clBlack, 0.35)
    else Book.Line(At(B0, 0).X, At(B0, 0).Y, At(B0, P.Depth).X, At(B0, P.Depth).Y, $00A0A0A0, 0.15);
    { the chalk line, and a solid stringer's nose line }
    Book.Line(At(A0, P.ChalkIn).X, At(A0, P.ChalkIn).Y, At(B0, P.ChalkIn).X, At(B0, P.ChalkIn).Y, $005096C8, 0.25);
    if P.EdgeIn > 0 then
      Book.Line(At(A0, P.EdgeIn).X, At(A0, P.EdgeIn).Y, At(B0, P.EdgeIn).X, At(B0, P.EdgeIn).Y, $005096C8, 0.25);
    { the layout, dot to dot }
    for I := 0 to High(P.Dots) - 1 do
      if InRow(P.Dots[I].Along, P.Dots[I].Inn, P.Dots[I + 1].Along, P.Dots[I + 1].Inn, Q1, Q2) then
        Book.Line(Q1.X, Q1.Y, Q2.X, Q2.Y, $00404040, 0.2);
    { the cut, dashed: every side of the outline except those along a board
      edge }
    for I := 0 to High(P.Cut) - 1 do
    begin
      if (P.Cut[I].OnEdge and P.Cut[I + 1].OnEdge and (P.Cut[I].Inn = 0) and (P.Cut[I + 1].Inn = 0)) or
         (P.Cut[I].OnBack and P.Cut[I + 1].OnBack) then Continue;
      if InRow(P.Cut[I].Along, P.Cut[I].Inn, P.Cut[I + 1].Along, P.Cut[I + 1].Inn, Q1, Q2) then Dashed(Q1, Q2);
    end;
    { the dots, numbered above the top edge or below the back edge }
    for I := 0 to High(P.Dots) do
    begin
      if (P.Dots[I].Along < A0 - 1E-9) or (P.Dots[I].Along > B0 + 1E-9) then Continue;
      Q := At(P.Dots[I].Along, P.Dots[I].Inn);
      Book.Poly([PointF(Q.X - 0.8, Q.Y - 0.8), PointF(Q.X + 0.8, Q.Y - 0.8), PointF(Q.X + 0.8, Q.Y + 0.8),
        PointF(Q.X - 0.8, Q.Y + 0.8)], True, clBlack, 0.1, clBlack);
      if P.Dots[I].OnBack then Book.Text(Q.X - 1.2, Q.Y + 4, IntToStr(I + 1), 7, clBlack, True)
      else if P.Dots[I].Inn < P.ChalkIn - P.Depth * 0.02 then Book.Text(Q.X - 1.2, Top - 1.5, IntToStr(I + 1), 7, clBlack, True)
      else Book.Text(Q.X + 1.2, Q.Y + 3.2, IntToStr(I + 1), 7, $00505050, True);
    end;
    if R = 0 then Book.Text(At(A0, 0).X, Top - 4.5, 'bottom end', 6.5, $00707070);
    if R = Rows - 1 then
      Book.Text(At(B0, 0).X - Book.TextWidth('top end', 6.5), Top - 4.5, 'top end', 6.5, $00707070);
    if Rows > 1 then
      Book.Text(At(A0, 0).X + W / 2 - 12, Top - 4.5, Format('row %d of %d', [R + 1, Rows]), 6.5, $00909090);
    Y := Top + P.Depth * Sc + 8;
  end;
  Book.Text(L, Y - 2, 'Top edge up, crown up.  Gray is waste; the red dashes are the cuts; the tan line is the ' +
    'chalk line.  Each row goes on where the one above stops.', 7, $00707070);
  Y := Y + 4;
end;

procedure TSheet.DotTable(const P: TStringerPlan);
var
  I: Integer;
  Inn: string;
begin
  if Y > Book.Height - 40 then Page;
  Book.Text(L, Y, 'Dot', 9, clBlack, True);
  Book.Text(L + 12, Y, 'Along from the bottom end', 9, clBlack, True);
  Book.Text(L + 62, Y, 'In from the top edge', 9, clBlack, True);
  Book.Text(L + 104, Y, 'What it is', 9, clBlack, True);
  Y := Y + 4.8;
  for I := 0 to High(P.Dots) do
  begin
    if Y > Book.Height - 18 then Page;
    if P.Dots[I].OnEdge then Inn := 'on the edge'
    else if P.Dots[I].OnBack then Inn := 'on the back edge'
    else Inn := Len(P.Dots[I].Inn);
    Book.Text(L, Y, IntToStr(I + 1), 9);
    Book.Text(L + 12, Y, Len(P.Dots[I].Along), 9, clBlack, True);
    Book.Text(L + 62, Y, Inn, 9, clBlack, True);
    Book.Text(L + 104, Y, P.Dots[I].What, 9, $00505050);
    Y := Y + 4.4;
  end;
  Y := Y + 2;
end;

procedure StringerSheetPdf(const F: TStairFrame; const S: TStairSpec; Use: TStairUse; U: TUnitSystem;
  const Title, Path: string);
var
  Sh: TSheet;
  P, C: TStringerPlan;
  Inch: Double;
  Buy, Lumber, Treated: string;
  N: Integer;
begin
  if U = usImperial then Inch := 1 / 12 else Inch := 0.0254;
  P := StringerPlan(F, S, U, False);
  C := StringerPlan(F, S, U, True);
  Sh := TSheet.Create;
  try
    if U = usImperial then Sh.Book := TPdfBook.Create(Title, 215.9, 279.4)
    else Sh.Book := TPdfBook.Create(Title, 210, 297);
    Sh.U := U; Sh.Inch := Inch;
    Sh.L := 16; Sh.W := Sh.Book.Width - 32;
    Sh.Title := Title + ' - stringers';
    Sh.Page;
    Sh.Book.Text(Sh.L, Sh.Y + 4, 'Cutting the stringers', 20, clBlack, True);
    Sh.Y := Sh.Y + 12;
    Sh.Para(Format('For a straight flight %s high, %s long and %s wide: %d risers of %s, %d treads of %s - %.1f degrees.',
      [Sh.Len(F.Rise), Sh.Len(F.Run), Sh.Len(F.Width), P.Risers, StairMeasure(P.UnitRise, U), P.Treads,
       StairMeasure(P.Going, U), P.Pitch]), 11);

    Sh.Head('The numbers');
    Sh.Row('Unit rise (each riser)', StairMeasure(P.UnitRise, U));
    Sh.Row('Unit run (each tread, riser to riser)', StairMeasure(P.Going, U));
    Sh.Row('Along the pitch, step to step', Sh.Len(P.Diagonal));
    Sh.Row('Bottom step cut short by', Sh.Len(P.Drop) + ' - the tread''s thickness');
    if P.Setback > 0 then
      Sh.Row('Stringers stand back of the riser faces', Sh.Len(P.Setback) + ' - the riser board');
    Sh.Row('Tread boards', Format('%s thick, %s nosing', [Sh.Len(S.Thickness), Sh.Len(S.Nosing)]));

    Sh.Head('What to buy');
    if P.StockFt > 0 then Buy := Format('%d ft', [P.StockFt]) else Buy := 'longer than stock';
    if U = usImperial then Lumber := '2x12 (1 1/2" x 11 1/4")' else Lumber := '2x12 (38 x 286 mm)';
    Treated := 'pressure-treated where it is outdoors or stands on concrete';
    Sh.Bullet(Format('Stringers: %s, No. 2 or better - southern pine or Douglas fir; %s.  Each stringer needs a board ' +
      'at least %s long: buy %s.  %d of them across the %s width, no more than %s apart on center.',
      [Lumber, Treated, Sh.Len(P.BoardLen), Buy, P.Count, Sh.Len(F.Width), Sh.Len(P.Spacing)]));
    if P.StockFt = 0 then
      Sh.Para('No stock board is that long: break the flight with a landing, or use engineered (LVL) stringers ' +
        'sized by a supplier.', 10, $002020C0, True);
    Sh.Bullet(Format('Cut stringers keep %s of wood under the deepest notch - the throat.  %s', [Sh.Len(P.Throat),
      IfThen(P.Throat >= THROAT_MIN_IN * Inch - 1E-9,
        Format('That is at least the %s the AWC''s deck-stair guide (DCA 6) asks for.', [Sh.Len(THROAT_MIN_IN * Inch)]),
        Format('That is less than the %s the AWC''s deck-stair guide (DCA 6) asks for - use solid stringers with ' +
          'cleats (the second way, below) or a deeper board.', [Sh.Len(THROAT_MIN_IN * Inch)]))]));
    Sh.Bullet('At the bottom, a 2x4 kicker (treated) fastened to the floor, the stringers notched over it or ' +
      'nailed to it; at the top, joist hangers sized for a 2x12, or a hanger board, on the landing''s header.');
    N := C.Treads * 2;
    Sh.Bullet(Format('For solid stringers with cleats: two 2x12 stringers as above, uncut; %d tread cleats of 2x4, ' +
      'each %s long; %d riser cleats of 1x2 or 2x2, each %s long; construction adhesive; 18 gauge brads to pin; ' +
      '3" structural screws or 10d nails.', [N, Sh.Len(P.Going + S.Nosing - 0.5 * Inch), N,
       Sh.Len(Max(P.UnitRise - S.Thickness - 0.5 * Inch, Inch))]));
    Sh.Para('Check the stringer span, the fastening and the rails against the code where the stairs are built - ' +
      'this sheet lays out the cut; it is not an engineered design.', 8.5, $00606060);

    { each way on a page of its own, to be carried to the saw }
    Sh.Page;
    Sh.Head('The first way: cut (notched) stringers');
    Sh.Board(P);
    Sh.DotTable(P);
    Sh.Numbered(1, Format('Pick the straightest board, at least %s long.  Sight down it: the edge that bows up - the ' +
      'crown - is the top edge.  Square the bottom end.', [Sh.Len(P.BoardLen)]));
    Sh.Numbered(2, 'Up the top edge, measure every dot marked "on the edge" from the bottom end and tick it.  Hook the ' +
      'tape once and read every mark off it - moving the tape each time adds the errors up.');
    Sh.Numbered(3, Format('Snap a chalk line %s in from the top edge, the full length.  Every inside corner sits on it: ' +
      'measure those dots along it from the bottom end.', [Sh.Len(P.ChalkIn)]));
    Sh.Numbered(4, 'Mark the last dots, the ones on the back edge and the foot of the first riser, square in from ' +
      'their distances along.');
    Sh.Numbered(5, 'Connect the dots in order with a straightedge.  Check a few with a framing square: every tread line ' +
      'level and every riser line plumb when the stringer stands, each tread line the unit run long and each riser ' +
      'line the unit rise - the bottom one short by the drop.');
    Sh.Numbered(6, 'Cut on the red lines.  A circular saw to the corners and no further - an overcut weakens the ' +
      'stringer where it is thinnest - then finish each corner with a hand saw or a jigsaw.');
    Sh.Numbered(7, 'Stand it in place and check it with a level before cutting the rest.  Then trace it onto the other ' +
      'boards - the first one is the pattern.');
    Sh.Numbered(8, 'Fasten the top to the header, the bottom to the kicker; treads on with construction adhesive and ' +
      'screws or ring-shank nails, riser boards before the treads that sit on them.');
    Sh.Para('With a framing square instead: stair gauges (or clamps) at the unit rise on the tongue and the unit run on ' +
      'the blade, the square slid up the edge one step at a time, marking round it - the same lines, laid out the ' +
      'older way.  The dots are easier to check.', 9, $00404040);

    { each way on a page of its own, to be carried to the saw }
    Sh.Page;
    Sh.Head('The second way: solid stringers with cleats');
    Sh.Para(Format('The outside stringers are not notched.  The same layout, %s lower on the board so the stringer ' +
      'stands proud of the treads, marks where the cleats go: the tread lines are the tops of the tread cleats and ' +
      'the riser lines the faces of the riser cleats.  Only the two ends are cut.  With nothing cut away, a solid ' +
      'stringer keeps its strength - the way to go when the throat is thin, or the stairs are finished on both ' +
      'sides.', [Sh.Len(C.EdgeIn)]), 10);
    Sh.Board(C);
    Sh.DotTable(C);
    Sh.Numbered(1, Format('Board at least %s long, crowned up, bottom end squared.', [Sh.Len(C.BoardLen)]));
    Sh.Numbered(2, Format('Snap the nose line %s in from the top edge and the corner line %s in.  Mark the dots along ' +
      'them from the bottom end, and connect them - on the inside face of each stringer, one the mirror of the other.',
      [Sh.Len(C.EdgeIn), Sh.Len(C.ChalkIn)]));
    Sh.Numbered(3, Format('Cut only the two ends, on the red lines: the floor cut from dot 2 to dot 1; the front end ' +
      'plumb from dot 2 up to the top edge; the top end plumb from the top edge down through dot %d to dot %d.',
      [Length(C.Dots) - 1, Length(C.Dots)]));
    Sh.Numbered(4, 'Tread cleats: a 2x4 under every tread line, its top edge on the line, its front end the nosing ' +
      'short of the nose.  Glue it, pin it with brads to hold it while the glue grabs, then three 3" screws or 10d ' +
      'nails.');
    Sh.Numbered(5, 'Riser cleats: a 1x2 or 2x2 behind every riser line, glued and pinned, then nailed or screwed.');
    Sh.Numbered(6, 'Stand the stringers, fasten top and bottom, and check they are the same height and parallel.  ' +
      'The treads and riser boards fit between the stringers - cut them the width less the two stringers - ' +
      'glued and pinned to the cleats, then nailed.');
    Sh.Numbered(7, Format('A flight wider than %s wants a cut stringer down the middle as well, laid out the first way.',
      [Sh.Len(C.Spacing)]));

    for N := 1 to Sh.Book.PageCount do
    begin
      Sh.Book.OnPage(N);
      Sh.Book.Text(Sh.L, Sh.Book.Height - 8, Format('%s    sheet %d of %d    Heckers Sketch', [Title, N,
        Sh.Book.PageCount]), 7.5, $00808080);
    end;
    Sh.Book.SaveToFile(Path);
  finally
    Sh.Book.Free;
    Sh.Free;
  end;
end;

end.

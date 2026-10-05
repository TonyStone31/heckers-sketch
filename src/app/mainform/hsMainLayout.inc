{ hsMainForm - laying out the window.  Part of TMainForm; included by hsMainForm.pas }

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
  S: TArtSurface; OX, OY: Integer; Edge: Boolean; Every: Integer);
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
    W := Add3(O, AU);
    SU := ScreenOf(W); SU := PtF(SU.X - SO.X, SU.Y - SO.Y);
    W := Add3(O, AV);
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
  Step := Max(1, Every);
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

  if not Edge then Exit;
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
    D := Dot3(N, Sub3(P, Loop[0]));
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
    V := Sub3(B, A);
    W := Sub3(P, A);
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
  PN := ScreenOf(Add3(FP1, Nm));
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

procedure TMainForm.RecomposeAll;
var
  T0: QWord;
begin
  FShotOK := False;
  T0 := GetTickCount64;
  FArt.CompositeOver(FPaper, FInk, Rect(0, 0, FArt.Width, FArt.Height));
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

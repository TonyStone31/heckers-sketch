{ hsMainForm - zoom, pan and the origin.  Part of TMainForm; included by hsMainForm.pas }

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

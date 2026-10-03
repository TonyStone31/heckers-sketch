unit hsFilm;

{ Pictures and films of the model, written to files.  No windows here, so
  tests and other callers can save a picture without linking BGRAControls
  or needing a screen.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}{$modeswitch nestedprocvars}

interface

uses
  Classes, SysUtils, Math, Types, Graphics, FPImage, FPWriteJPEG,
  BGRABitmap, BGRABitmapTypes,
  hsSurface, hsDrawing, hsSkin, hsWebPAnim;

const
  { Films get big and slow fast, so length is capped. }
  FILM_MAX_SECONDS = 20;
  FILM_MAX_FRAMES  = 300;
  { The frame rate asked for; FilmPlan lowers it to fit the budget. }
  FILM_FPS = 20;
  { A cap on total pixels across all frames, to keep the wait and the file
    size sensible.  When it bites, the frame rate drops; the film keeps its
    full length. }
  FILM_MAX_PIXELS = 50000000;
  { Rough bytes per pixel per frame, for the "about" size estimate.  Only
    good to an order of magnitude; real size depends on the model. }
  FILM_BYTES_PER_PIXEL = 0.03;

type
  { Where the camera was, and when.  A recording is a list of these, not
    pixels, so the film is rendered afterwards at any size. }
  TCamKey = record
    T: Double;          { seconds from the start }
    V: TProjector;
  end;
  TCamPath = array of TCamKey;

{ The camera at time T, interpolated between the recorded keys. }
function SampleCamPath(const P: TCamPath; T: Double): TProjector;
{ How long the recording runs. }
function CamPathLength(const P: TCamPath): Double;

{ True when the clip ends where it began, judged from the clip itself.  A
  looping film needs to know: see TFilmLoop. }
function CamPathCloses(const P: TCamPath): Boolean;

{ The three axes, as the drawing area draws them: solid one way from the
  origin, dashed the other. }
procedure PaintAxesOn(S: TArtSurface; const V: TProjector);

{ Draw the model into an existing surface, so a film reuses one surface
  instead of a new bitmap per frame.  Axes go UNDER the model, as on screen,
  so solids hide them. }
procedure ShootInto(S: TArtSurface; Doc: TWorkDoc; const V: TProjector;
  U: TUnitSystem; AFont: TFont; const LabelCol: TPix; EdgeW: Single;
  const Bg: TPix; Quick: Boolean; Axes: Boolean = False);

{ One frame of the model at any size, with the screen's view.  Also used by
  printing and the bug report picture. }
function ShootFrame(Doc: TWorkDoc; const V: TProjector; W, H: Integer;
  U: TUnitSystem; AFont: TFont; const LabelCol: TPix; EdgeW: Single;
  const Bg: TPix; Quick: Boolean; Axes: Boolean = False): TArtSurface;

{ --- moving the camera ------------------------------------------------

  Drag turns, shift-drag or right button slides, wheel zooms, the same as the
  drawing area.  WARNING: each one computes into a local before storing.
  At -O3 (release builds) the compiler can miscompile
  Field := Field + (Y - Ref) * K into a store near address zero. }
procedure OrbitBy(var V: TProjector; DX, DY: Double);
procedure PanBy(var V: TProjector; DX, DY: Double);
procedure ZoomBy(var V: TProjector; Factor: Double);

{ Zoom keeping the point under AX, AY fixed.  A screen position is
  O + Ppu * f(point), so scaling Ppu by k gives O' = A - k * (A - O). }
procedure ZoomAt(var V: TProjector; Factor, AX, AY: Double);

{ Keep a model point at a fixed screen position.  A TProjector turns about
  the world origin, so every camera move ends with this to act as a pivot;
  otherwise a model far from the origin swings out of frame. }
procedure HoldAt(var V: TProjector; const P: TP3; SX, SY: Double);

{ The canned camera moves for showing off a model. }
type
  TWalk = (wkTurntable, wkRise, wkUnderOver, wkNod, wkHalfBack, wkCorners,
           wkLookAll, wkPushIn);

const
  WALK_NAME: array[TWalk] of string =
    ('Turntable - one turn on the spot',
     'Rise - a turn, climbing as it goes',
     'Underneath to over the top',
     'Nod - down to up and back, no turn',
     'Half a turn, and back again',
     'Corner to corner, over the top',
     'The full look - round, over and under',
     'Push in - closing, drifting round');

{ The view for a canned walk at T, 0 to 1, starting from V0.  C is the point
  it turns about, held at screen point FrameX, FrameY. }
function WalkAt(Kind: TWalk; const V0: TProjector; const C: TP3;
  FrameX, FrameY, T: Double): TProjector;

{ The scale Fitted uses for a W by H picture, for turning preview mouse
  moves back into the stored view's terms. }
function ViewScale(SrcW, SrcH, W, H: Integer): Double;

{ The same view, framed for a different size of picture. }
function Fitted(const V: TProjector; SrcW, SrcH, W, H: Integer): TProjector;

{ Eased from view A to B, T 0 to 1.  Zoom is interpolated geometrically so
  it looks even; added linearly it seems to slow down. }
function TweenView(const A, B: TProjector; T: Double): TProjector;

{ A still, written as PNG or JPEG.  Quality is for the JPEG only. }
procedure SaveStill(Doc: TWorkDoc; const V: TProjector; SrcW, SrcH, W, H: Integer;
  U: TUnitSystem; AFont: TFont; const LabelCol: TPix; EdgeW: Single;
  const Path: string; Jpeg: Boolean; Quality: Integer; Transparent, Axes: Boolean);

type
  { where a film says what it is up to }
  TStageSay = procedure(const S: string) of object;
  { progress, since a long film takes a while to render }
  TFilmStep = procedure(Done, Total: Integer; const What: string) of object;

var
  OnFilmStage: TStageSay = nil;
  OnFilmStep: TFilmStep = nil;

{ How many frames a film of this length and size will get, and the frame
  rate that works out to, so the dialog can show it up front. }
procedure FilmPlan(Seconds: Double; Fps, W, H: Integer;
  out Frames, RealFps: Integer);

{ How a film loops.
  flAsIs      first frame to last, once.
  flSeamless  drops the last frame of a clip that closes, since it repeats
              the first and would stutter.
  flBounce    forward then backward, to loop a clip that does not close.
  Only Bounce is a user choice; the other two follow CamPathCloses. }
type
  TFilmLoop = (flAsIs, flSeamless, flBounce);

{ Write the recording to Path as an animated WebP; returns the frame count.
  WantSeconds sets the film's length (and so its speed); 0 keeps the
  recorded length. }
function SavePathFilm(Doc: TWorkDoc; const Cam: TCamPath;
  SrcW, SrcH, W, H: Integer; U: TUnitSystem; AFont: TFont;
  const LabelCol: TPix; EdgeW: Single; Fps: Integer;
  Loop, Axes: Boolean; const Path: string;
  Bounce: Boolean = False; WantSeconds: Double = 0): Integer;

implementation

type
  { the view for frame I of Count }
  TViewAt = function(I, Count: Integer): TProjector is nested;

{ Reports what the film is doing, so a failure names the frame it died on. }
procedure Say(const S: string);
begin
  if Assigned(OnFilmStage) then OnFilmStage(S);
end;

procedure Step(Done, Total: Integer; const What: string);
begin
  if Assigned(OnFilmStep) then OnFilmStep(Done, Total, What);
end;

procedure FilmPlan(Seconds: Double; Fps, W, H: Integer;
  out Frames, RealFps: Integer);
var
  Room: Int64;
begin
  Seconds := Max(0.2, Min(FILM_MAX_SECONDS, Seconds));
  Fps := Max(2, Min(50, Fps));
  Frames := Max(2, Round(Seconds * Fps));
  if Frames > FILM_MAX_FRAMES then Frames := FILM_MAX_FRAMES;
  Room := FILM_MAX_PIXELS div Max(Int64(1), Int64(W) * H);
  if Room < 2 then Room := 2;
  if Frames > Room then Frames := Room;
  RealFps := Max(1, Round(Frames / Seconds));
end;

function CamPathLength(const P: TCamPath): Double;
begin
  if Length(P) = 0 then Result := 0 else Result := P[High(P)].T;
end;

function CamPathCloses(const P: TCamPath): Boolean;
var
  A, B: TProjector;

  { an angle brought back into -Pi..Pi, so 2*Pi reads as nothing }
  function WrapPi(X: Double): Double;
  begin
    Result := X - 2 * Pi * Round(X / (2 * Pi));
  end;

begin
  Result := False;
  if Length(P) < 2 then Exit;
  A := P[0].V;
  B := P[High(P)].V;
  { Azimuth is compared modulo 2*Pi, since a turntable ends at Az + 2*Pi.
    0.01 radian is under a pixel of movement at any size. }
  Result := (Abs(WrapPi(A.Az - B.Az)) < 0.01) and (Abs(A.El - B.El) < 0.01) and
            (Abs(A.Ppu - B.Ppu) < 0.001 * Max(1E-9, Abs(A.Ppu))) and
            (Abs(A.OX - B.OX) < 1.0) and (Abs(A.OY - B.OY) < 1.0);
end;

{ Linear between two views, no easing; a recording already has the easing
  of the hand that made it. }
function TweenLinear(const A, B: TProjector; T: Double): TProjector;
begin
  T := Max(0, Min(1, T));
  Result := A;
  Result.Az := A.Az + (B.Az - A.Az) * T;
  Result.El := A.El + (B.El - A.El) * T;
  Result.OX := A.OX + (B.OX - A.OX) * T;
  Result.OY := A.OY + (B.OY - A.OY) * T;
  if (A.Ppu > 1E-9) and (B.Ppu > 1E-9) then
    Result.Ppu := A.Ppu * Exp(Ln(B.Ppu / A.Ppu) * T)
  else
    Result.Ppu := A.Ppu;
end;

function SampleCamPath(const P: TCamPath; T: Double): TProjector;
var
  Lo, Hi, M: Integer;
  Span: Double;
begin
  if Length(P) = 0 then
  begin
    FillChar(Result, SizeOf(Result), 0);
    Exit;
  end;
  if T <= P[0].T then Exit(P[0].V);
  if T >= P[High(P)].T then Exit(P[High(P)].V);
  Lo := 0;
  Hi := High(P);
  while Hi - Lo > 1 do
  begin
    M := (Lo + Hi) div 2;
    if P[M].T <= T then Lo := M else Hi := M;
  end;
  Span := P[Hi].T - P[Lo].T;
  if Span <= 1E-9 then Exit(P[Lo].V);
  Result := TweenLinear(P[Lo].V, P[Hi].V, (T - P[Lo].T) / Span);
end;

procedure PaintAxesOn(S: TArtSurface; const V: TProjector);
var
  K, N: Integer;
  L, Len, DX, DY: Double;
  B: TP3;
  PO, PB: TPointF;
  Col: TPix;
begin
  if V.Ppu <= 1E-9 then Exit;
  L := (S.Width + S.Height) / V.Ppu;
  PO := Project(V, P3(0, 0, 0));
  if IsNan(PO.X) or IsNan(PO.Y) or IsInfinite(PO.X) or IsInfinite(PO.Y) then Exit;
  for K := 0 to 2 do
  begin
    Col := AxisPix(K);
    B := P3(0, 0, 0);
    case K of
      0: B.X := L;
      1: B.Y := L;
    else B.Z := L;
    end;
    PB := Project(V, B);
    Len := Sqrt(Sqr(PB.X - PO.X) + Sqr(PB.Y - PO.Y));
    { skip an axis pointing straight at the camera; it would be a stray dot }
    if Len < 1 then Continue;
    S.Line(PO.X, PO.Y, PB.X, PB.Y, 1.8, Col, 0.55);
    DX := (PO.X - PB.X) / Len;
    DY := (PO.Y - PB.Y) / Len;
    N := 0;
    while N * 11 < Len do
    begin
      S.Line(PO.X + DX * (N * 11), PO.Y + DY * (N * 11),
             PO.X + DX * (N * 11 + 6), PO.Y + DY * (N * 11 + 6),
             1.4, Col, 0.42);
      Inc(N);
    end;
  end;
  S.Touch;
end;

procedure OrbitBy(var V: TProjector; DX, DY: Double);
var
  A, E: Double;
begin
  { drag right and the model turns with the cursor, so azimuth goes down }
  A := V.Az - DX * 0.01;
  E := V.El + DY * 0.01;
  if E < -1.45 then E := -1.45;
  if E > 1.45 then E := 1.45;
  V.Az := A;
  V.El := E;
end;

procedure PanBy(var V: TProjector; DX, DY: Double);
var
  X, Y: Double;
begin
  X := V.OX + DX;
  Y := V.OY + DY;
  V.OX := X;
  V.OY := Y;
end;

procedure ZoomBy(var V: TProjector; Factor: Double);
var
  P: Double;
begin
  if Factor <= 0 then Exit;
  P := V.Ppu * Factor;
  if P < 1E-4 then P := 1E-4;
  if P > 1E6 then P := 1E6;
  V.Ppu := P;
end;

procedure HoldAt(var V: TProjector; const P: TP3; SX, SY: Double);
var
  Q: TPointF;
  X, Y: Double;
begin
  Q := Project(V, P);
  if IsNan(Q.X) or IsNan(Q.Y) then Exit;
  X := V.OX + (SX - Q.X);
  Y := V.OY + (SY - Q.Y);
  V.OX := X;
  V.OY := Y;
end;

function WalkAt(Kind: TWalk; const V0: TProjector; const C: TP3;
  FrameX, FrameY, T: Double): TProjector;
var
  Turn: Double;

  { in and out again, 0 at both ends and 1 in the middle }
  function Hump(U: Double): Double;
  begin
    Result := Sin(Max(0, Min(1, U)) * Pi);
  end;

begin
  Result := V0;
  T := Max(0, Min(1, T));
  case Kind of
    wkTurntable:
      Result.Az := V0.Az + 2 * Pi * T;

    wkRise:
      begin
        { one turn, climbing from near the horizon to well above }
        Result.Az := V0.Az + 2 * Pi * T;
        Result.El := 0.18 + (1.15 - 0.18) * T;
      end;

    wkUnderOver:
      begin
        { from below to above, with a quarter turn, for parts whose
          underside matters }
        Result.Az := V0.Az + 0.5 * Pi * T;
        Result.El := -1.15 + (1.15 - -1.15) * T;
      end;

    wkNod:
      begin
        { no turn, just tilt down and up, for something with a front }
        Result.El := V0.El - 1.0 + 2.0 * Hump(T);
      end;

    wkHalfBack:
      begin
        { half a turn and back, like picking a thing up to look at it }
        Turn := Hump(T);
        Result.Az := V0.Az + Pi * Turn;
        Result.El := V0.El + 0.35 * Turn;
      end;

    wkCorners:
      begin
        { one corner low to the opposite corner high, showing three faces }
        Result.Az := V0.Az - Pi / 4 + (3 * Pi / 2) * T;
        Result.El := 0.15 + 1.05 * T;
      end;

    wkLookAll:
      begin
        { one turn round while the elevation goes over the top, under, then
          back up, so every face comes past the camera }
        Result.Az := V0.Az + 2 * Pi * T;
        if T < 0.25 then
          Result.El := 0.45 + 0.85 * Hump(T / 0.25)        { over the top }
        else if T < 0.5 then
          Result.El := 0.45 - 1.20 * Hump((T - 0.25) / 0.25)  { and under }
        else
          Result.El := 0.45 + 0.55 * Hump((T - 0.5) / 0.5);   { level, then a lean }
      end;

    wkPushIn:
      begin
        { a slow zoom in with a little drift, so you keep your bearings }
        Result.Az := V0.Az + 0.7 * Pi * T;
        Result.El := V0.El + 0.25 * T;
        Result.Ppu := V0.Ppu * Exp(Ln(2.4) * T);
      end;
  end;
  if Result.El < -1.45 then Result.El := -1.45;
  if Result.El > 1.45 then Result.El := 1.45;
  { keep the pivot fixed on screen }
  HoldAt(Result, C, FrameX, FrameY);
end;

function ViewScale(SrcW, SrcH, W, H: Integer): Double;
begin
  Result := 1;
  if (SrcW <= 0) or (SrcH <= 0) or (W <= 0) or (H <= 0) then Exit;
  Result := Min(W / SrcW, H / SrcH);
  if Result < 1E-9 then Result := 1E-9;
end;

procedure ZoomAt(var V: TProjector; Factor, AX, AY: Double);
var
  P, X, Y: Double;
begin
  if Factor <= 0 then Exit;
  P := V.Ppu * Factor;
  if P < 1E-4 then P := 1E-4;
  if P > 1E6 then P := 1E6;
  { the factor that actually got applied, after the clamp }
  Factor := P / V.Ppu;
  X := AX - Factor * (AX - V.OX);
  Y := AY - Factor * (AY - V.OY);
  V.Ppu := P;
  V.OX := X;
  V.OY := Y;
end;

function Fitted(const V: TProjector; SrcW, SrcH, W, H: Integer): TProjector;
var
  K: Double;
begin
  Result := V;
  if (SrcW <= 0) or (SrcH <= 0) or (W <= 0) or (H <= 0) then Exit;
  { same framing at any size: a bigger picture is the same picture scaled }
  K := Min(W / SrcW, H / SrcH);
  Result.Ppu := V.Ppu * K;
  Result.OX := W / 2 + (V.OX - SrcW / 2) * K;
  Result.OY := H / 2 + (V.OY - SrcH / 2) * K;
end;

procedure ShootInto(S: TArtSurface; Doc: TWorkDoc; const V: TProjector;
  U: TUnitSystem; AFont: TFont; const LabelCol: TPix; EdgeW: Single;
  const Bg: TPix; Quick: Boolean; Axes: Boolean = False);
var
  WasQuick: Boolean;
begin
  if S = nil then Exit;
  if Bg.A < 255 then
  begin
    S.PreserveAlpha := True;
    S.ClearTransparent;
  end
  else
  begin
    S.PreserveAlpha := False;
    S.Clear(Bg);
  end;
  { on the background, before the model goes over it }
  if Axes then PaintAxesOn(S, V);
  if Doc = nil then Exit;
  WasQuick := Doc.Quick;
  Doc.Quick := Quick;
  S.QuickFill := Quick;
  try
    if Doc.Live > 0 then
      Doc.Render(S, V, U, AFont, LabelCol, EdgeW);
  finally
    Doc.Quick := WasQuick;
  end;
end;

function ShootFrame(Doc: TWorkDoc; const V: TProjector; W, H: Integer;
  U: TUnitSystem; AFont: TFont; const LabelCol: TPix; EdgeW: Single;
  const Bg: TPix; Quick: Boolean; Axes: Boolean = False): TArtSurface;
begin
  Result := TArtSurface.Create(Max(1, W), Max(1, H));
  { a surface smaller than asked for must not be written into }
  if (Result.Width < Max(1, W)) or (Result.Height < Max(1, H)) then
  begin
    Result.Free;
    raise Exception.CreateFmt('could not make a picture %d by %d', [W, H]);
  end;
  ShootInto(Result, Doc, V, U, AFont, LabelCol, EdgeW, Bg, Quick, Axes);
end;

{ A straight copy: TPix and TBGRAPixel share the B, G, R, A layout. }
function ToBGRA(S: TArtSurface): TBGRABitmap;
var
  Y: Integer;
begin
  Result := TBGRABitmap.Create(S.Width, S.Height);
  for Y := 0 to S.Height - 1 do
    Move(S.ScanLine(Y)^, Result.ScanLine[Y]^, S.Width * SizeOf(TBGRAPixel));
  Result.InvalidateBitmap;
end;

function TweenView(const A, B: TProjector; T: Double): TProjector;
var
  E: Double;
begin
  E := Max(0, Min(1, T));
  E := E * E * (3 - 2 * E);        { ease in and out }
  Result := A;
  Result.Az := A.Az + (B.Az - A.Az) * E;
  Result.El := A.El + (B.El - A.El) * E;
  Result.OX := A.OX + (B.OX - A.OX) * E;
  Result.OY := A.OY + (B.OY - A.OY) * E;
  if (A.Ppu > 1E-9) and (B.Ppu > 1E-9) then
    Result.Ppu := A.Ppu * Exp(Ln(B.Ppu / A.Ppu) * E)
  else
    Result.Ppu := A.Ppu;
end;

procedure SaveStill(Doc: TWorkDoc; const V: TProjector; SrcW, SrcH, W, H: Integer;
  U: TUnitSystem; AFont: TFont; const LabelCol: TPix; EdgeW: Single;
  const Path: string; Jpeg: Boolean; Quality: Integer; Transparent, Axes: Boolean);
var
  S: TArtSurface;
  Bmp: TBGRABitmap;
  Wr: TFPWriterJPEG;
  Img: TFPMemoryImage;
  Bg: TPix;
begin
  if Transparent and not Jpeg then Bg := Pix(255, 255, 255, 0)
  else Bg := Pix(255, 255, 255);
  S := ShootFrame(Doc, Fitted(V, SrcW, SrcH, W, H), W, H, U, AFont, LabelCol,
    EdgeW, Bg, False, Axes);
  try
    Bmp := ToBGRA(S);
    try
      if not Jpeg then
        Bmp.SaveToFile(Path)
      else
      begin
        { JPEG has no transparency to keep and its own idea of quality }
        Img := TFPMemoryImage.Create(0, 0);
        Wr := TFPWriterJPEG.Create;
        try
          Img.Assign(Bmp);
          Wr.CompressionQuality := Max(20, Min(100, Quality));
          Img.SaveToFile(Path, Wr);
        finally
          Wr.Free;
          Img.Free;
        end;
      end;
    finally
      Bmp.Free;
    end;
  finally
    S.Free;
  end;
end;

{ Renders every frame of a film; ViewAt supplies the camera.  Each frame is
  encoded to lossless WebP as it is drawn and only the bytes are kept, so
  memory does not grow with length.  Keep it lossless: lossy WebP is grainy
  when you zoom in on line work. }
function WriteFilm(Doc: TWorkDoc; SrcW, SrcH, W, H: Integer;
  U: TUnitSystem; AFont: TFont; const LabelCol: TPix; EdgeW: Single;
  Frames: Integer; Seconds: Double; Loop, Axes: Boolean; const Path: string;
  const ViewAt: TViewAt): Integer;
var
  I, Delay: Integer;
  S: TArtSurface;
  V: TProjector;
  Web: TWebPAnimWriter;
begin
  Result := Frames;
  { delay from length and count, so a lower rate makes it choppier, not shorter }
  Delay := Max(20, Round(Seconds * 1000 / Max(1, Frames)));
  Web := nil;
  { one surface for the whole film, drawn over and over }
  S := TArtSurface.Create(Max(1, W), Max(1, H));
  try
    if (S.Width < W) or (S.Height < H) then
      raise Exception.CreateFmt('could not make a picture %d by %d', [W, H]);
    Web := TWebPAnimWriter.Create(W, H, True, 100, IfThen(Loop, 0, 1));
    for I := 0 to Frames - 1 do
    begin
      Say(Format('drawing frame %d of %d at %dx%d', [I + 1, Frames, W, H]));
      Step(I, Frames, Format('Drawing frame %d of %d', [I + 1, Frames]));
      V := Fitted(ViewAt(I, Frames), SrcW, SrcH, W, H);
      ShootInto(S, Doc, V, U, AFont, LabelCol, EdgeW, Pix(255, 255, 255),
        False, Axes);
      { straight off the surface: TPix is B, G, R, A, what the encoder reads }
      Say(Format('encoding frame %d of %d', [I + 1, Frames]));
      if not Web.AddFrame(PByte(S.ScanLine(0)), Delay, S.Stride) then
        raise Exception.CreateFmt('frame %d would not encode', [I + 1]);
    end;
    Say(Format('writing %s', [ExtractFileName(Path)]));
    Step(Frames, Frames, 'Writing ' + ExtractFileName(Path) + '...');
    if not Web.SaveToFile(Path) then
      raise Exception.Create('the film would not write');
  finally
    Web.Free;
    S.Free;
  end;
end;

function SavePathFilm(Doc: TWorkDoc; const Cam: TCamPath;
  SrcW, SrcH, W, H: Integer; U: TUnitSystem; AFont: TFont;
  const LabelCol: TPix; EdgeW: Single; Fps: Integer;
  Loop, Axes: Boolean; const Path: string;
  Bounce: Boolean = False; WantSeconds: Double = 0): Integer;
var
  Secs, Clip: Double;
  N, Rate: Integer;
  Rec: TCamPath;
  How: TFilmLoop;

  function At(I, Count: Integer): TProjector;
  var
    U01: Double;
  begin
    if Count < 2 then Exit(SampleCamPath(Rec, 0));
    case How of
      flBounce:
        begin
          { first half forward, second half back; the far end gets one frame
            and the film stops one step short of the start so it joins up }
          U01 := 2 * I / Count;
          if U01 > 1 then U01 := 2 - U01;
        end;
      flSeamless:
        { one step short of the end, because the end is the beginning }
        U01 := I / Count;
    else
      U01 := I / (Count - 1);
    end;
    Result := SampleCamPath(Rec, Clip * U01);
  end;

begin
  Rec := Cam;
  Clip := Max(0.2, CamPathLength(Cam));
  if WantSeconds > 0 then Secs := WantSeconds else Secs := Clip;
  Secs := Max(0.2, Min(FILM_MAX_SECONDS, Secs));

  if CamPathCloses(Cam) then How := flSeamless
  else if Bounce then How := flBounce
  else How := flAsIs;

  FilmPlan(Secs, Fps, W, H, N, Rate);
  Result := WriteFilm(Doc, SrcW, SrcH, W, H, U, AFont, LabelCol, EdgeW,
    N, Secs, Loop, Axes, Path, @At);
end;

end.

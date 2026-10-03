unit hsSurface;

{
  hsSurface - a small software rasterizer.  Everything the program draws is
  rendered into a 32 bit BGRA buffer with anti-aliasing and blitted to a
  canvas in a paint handler.  The LCL canvas has no anti-aliasing or alpha,
  and drawing on TImage.Canvas outside a paint event does not work on GTK3.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}
{$inline on}

interface

uses
  Classes, SysUtils, Types, Math, StrUtils, FPImage, Graphics, GraphType,
  IntfGraphics;

type
  { one closed loop in screen coordinates - an outline, or something cut out
    of one }
  TPtFLoop = array of TPointF;

  { One screen triangle and the exact depth plane it lies in.  A face that
    is not flat has no single plane; cut into triangles it has an exact
    depth everywhere.  See DepthMesh. }
  TDepthTri = record
    AX, AY, BX, BY, CX, CY: Single;
    ZA, ZB, ZC: Double;
    { the lowest and highest depth of its three corners.  Depth is clamped
      to these, since a long thin triangle's plane runs far out of range
      with half a pixel of rounding. }
    ZLo, ZHi: Double;
  end;
  TDepthTris = array of TDepthTri;

type
  { One pixel, laid out exactly as Init_BPP32_B8G8R8A8_BIO_TTB stores it. }
  TPix = packed record
    B, G, R, A: Byte;
  end;
  PPix = ^TPix;

  { How a source color is combined with what is already on the surface. }
  TBlendMode = (
    bmNormal,    // ordinary source-over alpha blend
    bmLighten,   // keep the brighter channel - additive-ish
    bmMaxAlpha,  // keep whichever is more opaque; glow halos that do not
                 // accumulate where strokes overlap
    bmReplace    // overwrite, alpha included
  );

  { TArtSurface }

  TArtSurface = class
  private
    FImage: TLazIntfImage;
    FBitmap: TBitmap;
    FBitmapValid: Boolean;
    FWidth, FHeight: Integer;
    { A decoy at offset 40, where a stray 8 byte store (a double that looks
      like a TDrawing's Zoom, also at offset 40) has landed.  Nothing reads
      it; if it stops holding GUARD_WORD the crash report says so. }
    FGuard: PtrInt;
    FStride: PtrInt;
    FBits: PByte;
    FMode: TBlendMode;
    FKeepAlpha: Boolean;
    { A depth per pixel.  Sorting shapes back to front fails when two shapes
      have no correct order, such as a wide panel and a small object beside it. }
    FZ: array of Single;
    FZOn: Boolean;
    { Lines read the depth buffer but never write it, or a line would hide
      the face it is drawn on. }
    FZTest: Boolean;
    { draw only what the depth test REJECTS, dashed; see DepthBehind }
    FZBehind: Boolean;
    FZa, FZb, FZc: Double;
    { exact depth triangles from DepthMesh, used by the next FillLoops only }
    FZTris: TDepthTris;
    FZTriY0, FZTriY1: array of Integer;
    FDirty: TRect;
    procedure Allocate(AWidth, AHeight: Integer);
    procedure Verify;
    procedure Invalidate; inline;
  public
    constructor Create(AWidth, AHeight: Integer);
    destructor Destroy; override;

    procedure SetSize(AWidth, AHeight: Integer; APreserve: Boolean = False);
    function ScanLine(Y: Integer): PPix; inline;

    { --- damage tracking, so compositing only touches what changed ------- }
    procedure ResetDirty;
    procedure MarkAllDirty;
    function TakeDirty: TRect;

    { --- primitives ------------------------------------------------------ }
    procedure BlendPixel(X, Y: Integer; const C: TPix; Cover: Single); inline;
    procedure Clear(const C: TPix);
    procedure FillRect(const R: TRect; const C: TPix; Alpha: Single = 1.0);
    procedure RoundRect(const R: TRect; Radius: Single; const C: TPix; Alpha: Single = 1.0);
    procedure RoundRectV(const R: TRect; Radius: Single; const C1, C2: TPix; Alpha: Single = 1.0);
    procedure RoundFrame(const R: TRect; Radius, LineW: Single; const C: TPix; Alpha: Single = 1.0);
    procedure Disc(CX, CY, Radius: Single; const C: TPix; Alpha: Single = 1.0);
    procedure DiscV(CX, CY, Radius: Single; const C1, C2: TPix; Alpha: Single = 1.0);
    procedure Ring(CX, CY, Radius, LineW: Single; const C: TPix; Alpha: Single = 1.0);
    { A cheap one pixel antialiased line for faint things drawn in bulk, like
      the ground grid.  Clipped to the surface first.  No depth test. }
    procedure HairLine(X0, Y0, X1, Y1: Single; const C: TPix; Alpha: Single);
    procedure Line(X0, Y0, X1, Y1, LineW: Single; const C: TPix; Alpha: Single = 1.0);
    procedure Arc(CX, CY, Radius, A0, A1, LineW: Single; const C: TPix; Alpha: Single = 1.0);
    procedure Poly(const Pts: array of TPointF; LineW: Single; const C: TPix;
      Closed: Boolean = False; Alpha: Single = 1.0);
    procedure Triangle(const P1, P2, P3: TPointF; const C: TPix; Alpha: Single = 1.0);
    procedure FillLoops(const Loops: array of TPtFLoop; const C: TPix;
      Alpha: Single);

    { Depth: start a pass, say what plane the next shape lies in, ask what
      depth a pixel ended up at.  Depth counts up towards the eye. }
  public
    { one coverage sample a row instead of four, for quick frames while the
      camera moves }
    QuickFill: Boolean;
  public
    procedure DepthBegin;
    procedure DepthPlane(A, B, C: Double);
    function DepthAt(X, Y: Integer): Single;
    function DepthOn: Boolean;
    procedure DepthTest(B: Boolean);
    { Draw only what the depth test rejects, dashed.  Hidden lines in a
      drawing are dashed, not dropped (a footing under a wall still shows).
      Run as a second pass over the lines after the faces; turn it off after. }
    procedure DepthBehind(B: Boolean);
    procedure DepthAlong(X0, Y0, Z0, X1, Y1, Z1: Double);
    { Give the NEXT FillLoops an exact depth per pixel from the face cut into
      triangles.  Use it for faces that are not flat (a revolve makes warped
      quads); a fitted plane can be badly wrong and let the back show through.
      The fill stays one call, since filling per triangle leaves seams.
      Pixels no triangle claims fall back to DepthPlane. }
    procedure DepthMesh(const Tris: TDepthTris);

    { --- whole-surface effects ------------------------------------------- }
    procedure ClearTransparent;
    procedure FadeAlpha(Amount: Single);
    procedure CompositeOver(Base, Ink: TArtSurface; const R: TRect);
    procedure Grain(Amount, Density: Single);
    procedure SmearDown(Rows: Integer);

    { --- transfer -------------------------------------------------------- }
    procedure CopyFrom(Src: TArtSurface; DX, DY: Integer);
    procedure CopyRegion(Src: TArtSurface; SrcX, SrcY, DX, DY, W, H: Integer);
    { fill this surface from one half its size, each pixel of H becoming
      four, depth buffer included.  See TWorkDoc.Render. }
    procedure ScaleUp2From(H: TArtSurface);
    procedure Snapshot(out Buf: TBytes);
    procedure Restore(const Buf: TBytes);
    procedure DrawTo(ACanvas: TCanvas; X, Y: Integer);
    procedure SaveToPNG(const AFileName: string);
    function TextExtent(const S: string; AFont: TFont): TSize;
    procedure TextOut(X, Y: Integer; const S: string; AFont: TFont; const C: TPix;
      Alpha: Single = 1.0);
    function AsBitmap: TBitmap;
    procedure Touch; inline;

    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property BlendMode: TBlendMode read FMode write FMode;
    property Stride: PtrInt read FStride;
    class function Repairs: Integer;
    { An ink layer keeps its own alpha so it can be composited over any
      background; a background surface stays fully opaque. }
    property PreserveAlpha: Boolean read FKeepAlpha write FKeepAlpha;
    property DirtyRect: TRect read FDirty;
  end;

{ --- color helpers ----------------------------------------------------- }
function Pix(R, G, B: Byte; A: Byte = 255): TPix; inline;
function ColorToPix(C: TColor): TPix; inline;
function PixToColor(const P: TPix): TColor; inline;
function MixPix(const A, B: TPix; T: Single): TPix;
{ Near-black or near-white, whichever reads on this color. }
function OnPix(const C: TPix): TPix;
function ShadePix(const C: TPix; F: Single): TPix;
function HSVPix(H, S, V: Single): TPix;
function PtF(X, Y: Single): TPointF; inline;

{ Called when a surface finds its buffer details changed under it, so the
  crash report trail shows which action was in progress. }
var
  OnSurfaceRepair: procedure(const What: string) = nil;

type
  { Told when a surface is about to be freed, so anybody holding a borrowed
    pointer to it can let go.  See WatchSurfaceGone. }
  TSurfaceGoneEvent = procedure(S: TArtSurface);

procedure WatchSurfaceGone(P: TSurfaceGoneEvent);

implementation

var
  { registered by WatchSurfaceGone }
  GGoneWatchers: array of TSurfaceGoneEvent;

const
  { An unlikely thing to be written by accident, and unmistakable in a report. }
  GUARD_WORD = PtrInt($5AFE5AFE5AFE5AFE);

const
  DEG = Pi / 180;

{ ------------------------------------------------------------------------ }
{ color helpers                                                            }
{ ------------------------------------------------------------------------ }

function Pix(R, G, B: Byte; A: Byte): TPix;
begin
  Result.R := R;
  Result.G := G;
  Result.B := B;
  Result.A := A;
end;

function ColorToPix(C: TColor): TPix;
var
  V: LongInt;
begin
  V := ColorToRGB(C);
  Result.R := Byte(V);
  Result.G := Byte(V shr 8);
  Result.B := Byte(V shr 16);
  Result.A := 255;
end;

function PixToColor(const P: TPix): TColor;
begin
  Result := TColor(P.R or (P.G shl 8) or (P.B shl 16));
end;

function MixPix(const A, B: TPix; T: Single): TPix;
begin
  T := EnsureRange(T, 0, 1);
  Result.R := Round(A.R + (B.R - A.R) * T);
  Result.G := Round(A.G + (B.G - A.G) * T);
  Result.B := Round(A.B + (B.B - A.B) * T);
  Result.A := Round(A.A + (B.A - A.A) * T);
end;

{ Near-black or near-white, whichever reads on this color.  Use it for text
  on an accent instead of assuming the accent is bright.  Uses sRGB relative
  luminance, with the threshold where the two contrasts are equal. }
function OnPix(const C: TPix): TPix;
var
  L: Single;

  function Chan(V: Byte): Single;
  var
    F: Single;
  begin
    F := V / 255;
    if F <= 0.03928 then Result := F / 12.92
    else Result := Power((F + 0.055) / 1.055, 2.4);
  end;

begin
  L := 0.2126 * Chan(C.R) + 0.7152 * Chan(C.G) + 0.0722 * Chan(C.B);
  if L > 0.183 then Result := Pix(22, 22, 26)
  else Result := Pix(246, 248, 252);
  Result.A := 255;
end;

function ShadePix(const C: TPix; F: Single): TPix;
begin
  Result.R := EnsureRange(Round(C.R * F), 0, 255);
  Result.G := EnsureRange(Round(C.G * F), 0, 255);
  Result.B := EnsureRange(Round(C.B * F), 0, 255);
  Result.A := C.A;
end;

function HSVPix(H, S, V: Single): TPix;
var
  I: Integer;
  F, P, Q, T, R, G, B: Single;
begin
  H := H - Floor(H / 360) * 360;
  S := EnsureRange(S, 0, 1);
  V := EnsureRange(V, 0, 1);
  if S <= 0 then
  begin
    R := V; G := V; B := V;
  end
  else
  begin
    H := H / 60;
    I := Trunc(H);
    F := H - I;
    P := V * (1 - S);
    Q := V * (1 - S * F);
    T := V * (1 - S * (1 - F));
    case I of
      0: begin R := V; G := T; B := P; end;
      1: begin R := Q; G := V; B := P; end;
      2: begin R := P; G := V; B := T; end;
      3: begin R := P; G := Q; B := V; end;
      4: begin R := T; G := P; B := V; end;
    else
      begin R := V; G := P; B := Q; end;
    end;
  end;
  Result := Pix(Round(R * 255), Round(G * 255), Round(B * 255));
end;

function PtF(X, Y: Single): TPointF;
begin
  Result.X := X;
  Result.Y := Y;
end;

{ ------------------------------------------------------------------------ }
{ signed distance fields                                                    }
{ ------------------------------------------------------------------------ }

{ Distance from (PX,PY) to a rounded box centered on (CX,CY) with half-extents
  (HX,HY) and corner radius Rad.  Negative inside, positive outside. }
function SdRoundBox(PX, PY, CX, CY, HX, HY, Rad: Single): Single; inline;
var
  QX, QY: Single;
begin
  Rad := Min(Rad, Min(HX, HY));
  QX := Abs(PX - CX) - (HX - Rad);
  QY := Abs(PY - CY) - (HY - Rad);
  Result := Sqrt(Sqr(Max(QX, 0)) + Sqr(Max(QY, 0))) + Min(Max(QX, QY), 0) - Rad;
end;

{ Distance from (PX,PY) to the segment (AX,AY)-(BX,BY). }
function SdSegment(PX, PY, AX, AY, BX, BY: Single): Single; inline;
var
  PAX, PAY, BAX, BAY, H, D: Single;
begin
  PAX := PX - AX;
  PAY := PY - AY;
  BAX := BX - AX;
  BAY := BY - AY;
  D := BAX * BAX + BAY * BAY;
  if D < 1E-9 then
    H := 0
  else
    H := EnsureRange((PAX * BAX + PAY * BAY) / D, 0, 1);
  Result := Sqrt(Sqr(PAX - BAX * H) + Sqr(PAY - BAY * H));
end;

{ Convert a signed distance to pixel coverage (1px wide analytic edge). }
function Coverage(D: Single): Single; inline;
begin
  Result := EnsureRange(0.5 - D, 0, 1);
end;

{ ------------------------------------------------------------------------ }
{ TArtSurface                                                               }
{ ------------------------------------------------------------------------ }

constructor TArtSurface.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  FImage := TLazIntfImage.Create(0, 0);
  FBitmap := TBitmap.Create;
  FMode := bmNormal;
  FGuard := GUARD_WORD;
  Allocate(Max(1, AWidth), Max(1, AHeight));
end;

{ Watchers are told before the memory goes.  See WatchSurfaceGone. }
destructor TArtSurface.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(GGoneWatchers) do
    if Assigned(GGoneWatchers[I]) then GGoneWatchers[I](Self);
  FBitmap.Free;
  FImage.Free;
  inherited Destroy;
end;

{ TWorkDoc borrows the last surface it rendered into, for depth lookups.
  Exports make and free their own surfaces, so every surface tells its
  watchers when it is freed and no borrowed pointer is left dangling. }
procedure WatchSurfaceGone(P: TSurfaceGoneEvent);
begin
  SetLength(GGoneWatchers, Length(GGoneWatchers) + 1);
  GGoneWatchers[High(GGoneWatchers)] := P;
end;

var
  GRepairs: Integer = 0;

{ A corrupt stride has turned out to be a double before, so the crash report
  shows the value read as one too. }
function AsDouble(V: PtrInt): string;
var
  D: Double;
begin
  Move(V, D, SizeOf(D));
  if IsNan(D) or IsInfinite(D) then Exit('not a number');
  Result := Format('as a double %.6g', [D]);
end;

class function TArtSurface.Repairs: Integer;
begin
  Result := GRepairs;
end;

{ Re-read the buffer and stride from the image.  Both are set once in
  Allocate, so a change means something outside wrote over them, and a bad
  stride is a wild pointer.  The repair count goes into the crash report. }
procedure TArtSurface.Verify;
var
  P: PByte;
  St: PtrInt;
begin
  if (FWidth <= 0) or (FHeight <= 0) then Exit;
  P := PByte(FImage.GetDataLineStart(0));
  if P = nil then Exit;
  if FHeight > 1 then
    St := PByte(FImage.GetDataLineStart(1)) - P
  else
    St := FWidth * 4;
  if St < FWidth * 4 then Exit;      { the image is talking nonsense too }
  if FGuard <> GUARD_WORD then
  begin
    Inc(GRepairs);
    if Assigned(OnSurfaceRepair) then
      OnSurfaceRepair(Format('surface guard hit: %d (%s), stride %s',
        [FGuard, AsDouble(FGuard),
         specialize IfThen<string>(St = FStride, 'untouched', 'also wrong')]));
    FGuard := GUARD_WORD;
  end;
  if (P <> FBits) or (St <> FStride) then
  begin
    Inc(GRepairs);
    if Assigned(OnSurfaceRepair) then
      OnSurfaceRepair(Format('surface repaired: stride %d (%s) -> %d, bits %s',
        [FStride, AsDouble(FStride), St,
         specialize IfThen<string>(P = FBits, 'same', 'moved')]));
    FBits := P;
    FStride := St;
  end;
end;

procedure TArtSurface.Allocate(AWidth, AHeight: Integer);
var
  Desc: TRawImageDescription;
  RI: TRawImage;
  Room: PtrUInt;
  St: PtrInt;
begin
  { Zeroed first: the image compares it byte for byte to decide whether to
    reallocate, and stack garbage would spoil the comparison. }
  FillChar(Desc, SizeOf(Desc), 0);
  Desc.Init_BPP32_B8G8R8A8_BIO_TTB(AWidth, AHeight);
  FImage.DataDescription := Desc;
  FBits := PByte(FImage.GetDataLineStart(0));
  { Width and height come from what the image actually gave, set after the
    allocation.  Every clip in this unit trusts them; a surface with no
    memory behind it reports itself as one pixel. }
  if FBits = nil then
  begin
    FWidth := 0;
    FHeight := 0;
    FStride := 0;
    FBitmapValid := False;
    ResetDirty;
    Exit;
  end;
  { The row stride, measured since a backing store may pad rows.  The
    measurement can be garbage if the image is not realized yet, so anything
    not plausibly a padded row falls back to the packed width. }
  FStride := AWidth * 4;
  if AHeight > 1 then
  begin
    St := PByte(FImage.GetDataLineStart(1)) - FBits;
    if (St >= AWidth * 4) and (St <= PtrInt(AWidth) * 4 + 4096) then
      FStride := St;
  end;

  { Trim the height to the rows the buffer can actually hold; the image can
    hand back less than asked, and every clip here trusts FHeight. }
  Room := 0;
  try
    FImage.GetRawImage(RI, False);
    Room := RI.DataSize;
  except
    Room := 0;
  end;
  if (Room > 0) and (FStride > 0) and
     (Room div PtrUInt(FStride) < PtrUInt(AHeight)) then
    AHeight := Integer(Room div PtrUInt(FStride));
  if AHeight < 1 then
  begin
    FWidth := 0;
    FHeight := 0;
    FStride := 0;
    FBitmapValid := False;
    ResetDirty;
    Exit;
  end;

  FWidth := AWidth;
  FHeight := AHeight;
  { the allocation is not zeroed, and anything that only partly covers the
    surface afterwards would otherwise show whatever was in that memory }
  FillChar(FBits^, PtrUInt(FStride) * PtrUInt(AHeight), 0);
  FBitmapValid := False;
  ResetDirty;
end;

procedure TArtSurface.Invalidate;
begin
  FBitmapValid := False;
end;

procedure TArtSurface.Touch;
begin
  FBitmapValid := False;
end;

procedure TArtSurface.SetSize(AWidth, AHeight: Integer; APreserve: Boolean);
var
  Keep: TBytes;
  OldW, OldH: Integer;
  Old: TArtSurface;
begin
  AWidth := Max(1, AWidth);
  AHeight := Max(1, AHeight);
  if (AWidth = FWidth) and (AHeight = FHeight) then
    Exit;

  if not APreserve then
  begin
    Allocate(AWidth, AHeight);
    Exit;
  end;

  { keep the old contents anchored top-left so a resize does not wipe them }
  OldW := FWidth;
  OldH := FHeight;
  Snapshot(Keep);
  Old := TArtSurface.Create(OldW, OldH);
  try
    Old.Restore(Keep);
    Allocate(AWidth, AHeight);
    FillRect(Rect(0, 0, FWidth, FHeight), Pix(255, 255, 255));
    CopyFrom(Old, 0, 0);
  finally
    Old.Free;
  end;
end;

{ Refuses a stride that cannot be real and uses the packed width instead:
  a sheared picture beats writing through a wild pointer. }
function TArtSurface.ScanLine(Y: Integer): PPix;
var
  St: PtrInt;
begin
  St := FStride;
  if (St < FWidth * 4) or (St > PtrInt(FWidth) * 4 + 4096) then
    St := PtrInt(FWidth) * 4;
  Result := PPix(FBits + St * Y);
end;

procedure TArtSurface.BlendPixel(X, Y: Integer; const C: TPix; Cover: Single);
var
  P: PPix;
  A, DA, OA: Integer;
begin
  if (X < 0) or (Y < 0) or (X >= FWidth) or (Y >= FHeight) then Exit;
  { written as "not > 0" so a NaN coverage - a degenerate shape upstream -
    leaves rather than reaching Round below }
  if not (Cover > 0) then Exit;
  if Cover > 1 then Cover := 1;

  P := ScanLine(Y);
  Inc(P, X);
  A := Round(Cover * C.A);

  case FMode of
    bmReplace:
      begin
        P^ := C;
        P^.A := Byte(A);
      end;

    bmLighten:
      begin
        P^.R := Max(P^.R, Byte((C.R * A) div 255));
        P^.G := Max(P^.G, Byte((C.G * A) div 255));
        P^.B := Max(P^.B, Byte((C.B * A) div 255));
        if FKeepAlpha then P^.A := Max(P^.A, Byte(A)) else P^.A := 255;
      end;

    bmMaxAlpha:
      begin
        if A > P^.A then
        begin
          P^.R := C.R;
          P^.G := C.G;
          P^.B := C.B;
          P^.A := Byte(A);
        end;
      end;

  else
    if FKeepAlpha then
    begin
      { source-over onto a surface that carries its own alpha }
      DA := P^.A;
      OA := A + (DA * (255 - A)) div 255;
      if OA <= 0 then
      begin
        P^.R := 0; P^.G := 0; P^.B := 0; P^.A := 0;
      end
      else
      begin
        { out = (src*sa + dst*da*(1-sa)) / oa in 0..255 integers.  OA is
          truncated, so the result can exceed 255 (509 at A=1 over DA=1);
          the clamp prevents a range check error. }
        P^.R := Min(255, (C.R * A * 255 + P^.R * DA * (255 - A)) div (255 * OA));
        P^.G := Min(255, (C.G * A * 255 + P^.G * DA * (255 - A)) div (255 * OA));
        P^.B := Min(255, (C.B * A * 255 + P^.B * DA * (255 - A)) div (255 * OA));
        P^.A := Byte(OA);
      end;
    end
    else
    begin
      if A >= 255 then
      begin
        P^.R := C.R; P^.G := C.G; P^.B := C.B;
      end
      else
      begin
        P^.R := P^.R + ((C.R - P^.R) * A) div 255;
        P^.G := P^.G + ((C.G - P^.G) * A) div 255;
        P^.B := P^.B + ((C.B - P^.B) * A) div 255;
      end;
      P^.A := 255;
    end;
  end;

  if X < FDirty.Left then FDirty.Left := X;
  if Y < FDirty.Top then FDirty.Top := Y;
  if X >= FDirty.Right then FDirty.Right := X + 1;
  if Y >= FDirty.Bottom then FDirty.Bottom := Y + 1;
  FBitmapValid := False;
end;

procedure TArtSurface.ResetDirty;
begin
  FDirty := Rect(FWidth, FHeight, 0, 0);
end;

procedure TArtSurface.MarkAllDirty;
begin
  FDirty := Rect(0, 0, FWidth, FHeight);
end;

{ Returns the damaged area and clears it.  An empty rect means nothing moved. }
function TArtSurface.TakeDirty: TRect;
begin
  Result := FDirty;
  if (Result.Right <= Result.Left) or (Result.Bottom <= Result.Top) then
    Result := Rect(0, 0, 0, 0);
  ResetDirty;
end;

procedure TArtSurface.ClearTransparent;
var
  Y: Integer;
begin
  for Y := 0 to FHeight - 1 do
    FillChar(ScanLine(Y)^, FWidth * SizeOf(TPix), 0);
  MarkAllDirty;
  Invalidate;
end;

{ Wind the whole layer toward transparent - how the shake dissolves ink
  without touching the paper underneath. }
procedure TArtSurface.FadeAlpha(Amount: Single);
var
  X, Y, K: Integer;
  P: PPix;
begin
  K := EnsureRange(Round((1 - Amount) * 255), 0, 255);
  for Y := 0 to FHeight - 1 do
  begin
    P := ScanLine(Y);
    for X := 0 to FWidth - 1 do
    begin
      P^.A := (P^.A * K) div 255;
      Inc(P);
    end;
  end;
  MarkAllDirty;
  Invalidate;
end;

{ Self := Base with Ink composited on top, over the rectangle R only. }
procedure TArtSurface.CompositeOver(Base, Ink: TArtSurface; const R: TRect);
var
  X, Y, A: Integer;
  Cl: TRect;
  B, S, D: PPix;
begin
  if (Base = nil) or (Ink = nil) then Exit;
  Verify;
  Base.Verify;
  Ink.Verify;
  { Clipped to all three surfaces, not just this one; if one is a row short
    the loop would otherwise run off its end. }
  Cl := Rect(Max(0, R.Left), Max(0, R.Top),
             Min(FWidth,  Min(Base.Width,  Ink.Width)),
             Min(FHeight, Min(Base.Height, Ink.Height)));
  if R.Right < Cl.Right then Cl.Right := R.Right;
  if R.Bottom < Cl.Bottom then Cl.Bottom := R.Bottom;
  if (Cl.Right <= Cl.Left) or (Cl.Bottom <= Cl.Top) then Exit;

  for Y := Cl.Top to Cl.Bottom - 1 do
  begin
    B := Base.ScanLine(Y); Inc(B, Cl.Left);
    S := Ink.ScanLine(Y);  Inc(S, Cl.Left);
    D := ScanLine(Y);      Inc(D, Cl.Left);
    for X := Cl.Left to Cl.Right - 1 do
    begin
      A := S^.A;
      if A = 0 then
        D^ := B^
      else if A = 255 then
        D^ := S^
      else
      begin
        D^.R := B^.R + ((S^.R - B^.R) * A) div 255;
        D^.G := B^.G + ((S^.G - B^.G) * A) div 255;
        D^.B := B^.B + ((S^.B - B^.B) * A) div 255;
      end;
      D^.A := 255;
      Inc(B); Inc(S); Inc(D);
    end;
  end;
  Invalidate;
end;

procedure TArtSurface.Clear(const C: TPix);
var
  X, Y: Integer;
  P: PPix;
begin
  for Y := 0 to FHeight - 1 do
  begin
    P := ScanLine(Y);
    for X := 0 to FWidth - 1 do
    begin
      P^ := C;
      P^.A := 255;
      Inc(P);
    end;
  end;
  MarkAllDirty;
  Invalidate;
end;

procedure TArtSurface.FillRect(const R: TRect; const C: TPix; Alpha: Single);
var
  X, Y: Integer;
  P: PPix;
  Cl: TRect;
begin
  Cl := Rect(Max(0, R.Left), Max(0, R.Top), Min(FWidth, R.Right), Min(FHeight, R.Bottom));
  if (Cl.Right <= Cl.Left) or (Cl.Bottom <= Cl.Top) then Exit;
  for Y := Cl.Top to Cl.Bottom - 1 do
  begin
    P := ScanLine(Y);
    Inc(P, Cl.Left);
    for X := Cl.Left to Cl.Right - 1 do
    begin
      BlendPixel(X, Y, C, Alpha);
      Inc(P);
    end;
  end;
  Invalidate;
end;


procedure TArtSurface.RoundRectV(const R: TRect; Radius: Single; const C1, C2: TPix;
  Alpha: Single);
var
  X, Y, H: Integer;
  CX, CY, HX, HY: Single;
  C: TPix;
  Cl: TRect;
begin
  CX := (R.Left + R.Right) / 2;
  CY := (R.Top + R.Bottom) / 2;
  HX := (R.Right - R.Left) / 2;
  HY := (R.Bottom - R.Top) / 2;
  H := R.Bottom - R.Top;
  if (HX <= 0) or (HY <= 0) then Exit;

  Cl := Rect(Max(0, R.Left - 1), Max(0, R.Top - 1),
             Min(FWidth, R.Right + 1), Min(FHeight, R.Bottom + 1));
  for Y := Cl.Top to Cl.Bottom - 1 do
  begin
    C := MixPix(C1, C2, (Y - R.Top) / H);
    for X := Cl.Left to Cl.Right - 1 do
      BlendPixel(X, Y, C,
        Coverage(SdRoundBox(X + 0.5, Y + 0.5, CX, CY, HX, HY, Radius)) * Alpha);
  end;
  Invalidate;
end;

procedure TArtSurface.RoundRect(const R: TRect; Radius: Single; const C: TPix; Alpha: Single);
begin
  RoundRectV(R, Radius, C, C, Alpha);
end;

procedure TArtSurface.RoundFrame(const R: TRect; Radius, LineW: Single; const C: TPix;
  Alpha: Single);
var
  Y, Pad, Band: Integer;
  CX, CY, HX, HY: Single;
  Cl: TRect;

  procedure Row(AY, AX0, AX1: Integer);
  var
    IX: Integer;
  begin
    if (AY < 0) or (AY >= FHeight) then Exit;
    for IX := Max(0, AX0) to Min(FWidth - 1, AX1) do
      BlendPixel(IX, AY, C,
        Coverage(Abs(SdRoundBox(IX + 0.5, AY + 0.5, CX, CY, HX, HY, Radius)) - LineW / 2) * Alpha);
  end;

begin
  CX := (R.Left + R.Right) / 2;
  CY := (R.Top + R.Bottom) / 2;
  HX := (R.Right - R.Left) / 2;
  HY := (R.Bottom - R.Top) / 2;
  if (HX <= 0) or (HY <= 0) then Exit;
  Pad := Ceil(LineW) + 2;
  Band := Ceil(Radius) + Pad;

  Cl := Rect(R.Left - Pad, R.Top - Pad, R.Right + Pad, R.Bottom + Pad);

  { Only the border band can be covered, so walk the perimeter rather than the
    whole rectangle - this keeps big frames (the bezel, the vignette) cheap. }
  for Y := Cl.Top to Min(Cl.Bottom, Cl.Top + 2 * Band) - 1 do
    Row(Y, Cl.Left, Cl.Right - 1);
  for Y := Max(Cl.Top + 2 * Band, Cl.Bottom - 2 * Band) to Cl.Bottom - 1 do
    Row(Y, Cl.Left, Cl.Right - 1);
  for Y := Cl.Top + 2 * Band to Cl.Bottom - 2 * Band - 1 do
  begin
    Row(Y, Cl.Left, Cl.Left + 2 * Band - 1);
    Row(Y, Cl.Right - 2 * Band, Cl.Right - 1);
  end;
  Invalidate;
end;

{ Float to integer bounds, clamped before converting.  At high zoom a shape
  can project millions of pixels off the surface, which would be a range
  check error; clamped, it just makes an empty loop. }

function LoBound(V: Double; Limit: Integer): Integer;
begin
  if IsNan(V) or (V <= 0) then Exit(0);
  if V >= Limit then Exit(Limit);        // Lo > Hi: nothing to walk
  Result := Floor(V);
end;

function HiBound(V: Double; Limit: Integer): Integer;
begin
  if IsNan(V) or (V < 0) then Exit(-1);  // Hi < Lo: nothing to walk
  if V >= Limit - 1 then Exit(Limit - 1);
  Result := Ceil(V);
end;

procedure TArtSurface.Disc(CX, CY, Radius: Single; const C: TPix; Alpha: Single);
var
  X, Y, X0, Y0, X1, Y1: Integer;
begin
  if Radius <= 0 then Exit;
  X0 := LoBound(CX - Radius - 1, FWidth);
  Y0 := LoBound(CY - Radius - 1, FHeight);
  X1 := HiBound(CX + Radius + 1, FWidth);
  Y1 := HiBound(CY + Radius + 1, FHeight);
  for Y := Y0 to Y1 do
    for X := X0 to X1 do
      BlendPixel(X, Y, C,
        Coverage(Sqrt(Sqr(X + 0.5 - CX) + Sqr(Y + 0.5 - CY)) - Radius) * Alpha);
  Invalidate;
end;

procedure TArtSurface.DiscV(CX, CY, Radius: Single; const C1, C2: TPix; Alpha: Single);
var
  X, Y, X0, Y0, X1, Y1: Integer;
  C: TPix;
begin
  if Radius <= 0 then Exit;
  X0 := LoBound(CX - Radius - 1, FWidth);
  Y0 := LoBound(CY - Radius - 1, FHeight);
  X1 := HiBound(CX + Radius + 1, FWidth);
  Y1 := HiBound(CY + Radius + 1, FHeight);
  for Y := Y0 to Y1 do
  begin
    C := MixPix(C1, C2, EnsureRange((Y - (CY - Radius)) / (2 * Radius), 0, 1));
    for X := X0 to X1 do
      BlendPixel(X, Y, C,
        Coverage(Sqrt(Sqr(X + 0.5 - CX) + Sqr(Y + 0.5 - CY)) - Radius) * Alpha);
  end;
  Invalidate;
end;

procedure TArtSurface.Ring(CX, CY, Radius, LineW: Single; const C: TPix; Alpha: Single);
var
  X, Y, X0, Y0, X1, Y1: Integer;
  Pad: Double;
begin
  Pad := Radius + LineW + 2;
  X0 := LoBound(CX - Pad, FWidth);
  Y0 := LoBound(CY - Pad, FHeight);
  X1 := HiBound(CX + Pad, FWidth);
  Y1 := HiBound(CY + Pad, FHeight);
  for Y := Y0 to Y1 do
    for X := X0 to X1 do
      BlendPixel(X, Y, C,
        Coverage(Abs(Sqrt(Sqr(X + 0.5 - CX) + Sqr(Y + 0.5 - CY)) - Radius) - LineW / 2) * Alpha);
  Invalidate;
end;

{ Xiaolin Wu's line.  The ends are cut to the surface (Liang and Barsky)
  before anything is walked, then the long axis is stepped a pixel at a time
  and the two pixels either side of the line share its coverage. }
procedure TArtSurface.HairLine(X0, Y0, X1, Y1: Single; const C: TPix; Alpha: Single);
var
  T0, T1, DX, DY, Grad, Inter, F: Double;
  Steep: Boolean;
  I, IA, IB, Y: Integer;
  Tmp: Double;

  function Clip(P, Q: Double): Boolean;
  var
    R: Double;
  begin
    Result := True;
    if Abs(P) < 1E-12 then
    begin
      if Q < 0 then Result := False;
      Exit;
    end;
    R := Q / P;
    if P < 0 then
    begin
      if R > T1 then Result := False
      else if R > T0 then T0 := R;
    end
    else
    begin
      if R < T0 then Result := False
      else if R < T1 then T1 := R;
    end;
  end;

  procedure Plot(A, B: Integer; Cover: Double);
  begin
    if Steep then BlendPixel(B, A, C, Cover * Alpha)
    else BlendPixel(A, B, C, Cover * Alpha);
  end;

begin
  if (FWidth <= 0) or (FHeight <= 0) or not (Alpha > 0) then Exit;
  if IsNan(X0) or IsNan(Y0) or IsNan(X1) or IsNan(Y1) then Exit;
  DX := X1 - X0;
  DY := Y1 - Y0;
  T0 := 0;
  T1 := 1;
  { a pixel of margin all round, so a line along the very edge still lands }
  if not Clip(-DX, X0 + 1) then Exit;
  if not Clip(DX, FWidth - X0) then Exit;
  if not Clip(-DY, Y0 + 1) then Exit;
  if not Clip(DY, FHeight - Y0) then Exit;
  if T1 < T0 then Exit;
  X1 := X0 + DX * T1;  Y1 := Y0 + DY * T1;
  X0 := X0 + DX * T0;  Y0 := Y0 + DY * T0;

  Steep := Abs(Y1 - Y0) > Abs(X1 - X0);
  if Steep then
  begin
    Tmp := X0; X0 := Y0; Y0 := Tmp;
    Tmp := X1; X1 := Y1; Y1 := Tmp;
  end;
  if X0 > X1 then
  begin
    Tmp := X0; X0 := X1; X1 := Tmp;
    Tmp := Y0; Y0 := Y1; Y1 := Tmp;
  end;
  DX := X1 - X0;
  DY := Y1 - Y0;
  if DX < 1E-9 then Grad := 0 else Grad := DY / DX;

  { pixel centers sit at .5; step every whole column the line spans }
  IA := Round(X0);
  IB := Round(X1);
  Inter := Y0 + Grad * (IA + 0.5 - X0) - 0.5;
  for I := IA to IB do
  begin
    Y := Floor(Inter);
    F := Inter - Y;
    Plot(I, Y, 1 - F);
    Plot(I, Y + 1, F);
    Inter := Inter + Grad;
  end;
  Invalidate;
end;

{ Walks only the span each row of the segment can reach, not its bounding
  box; a long diagonal's box is the whole surface. }
procedure TArtSurface.Line(X0, Y0, X1, Y1, LineW: Single; const C: TPix; Alpha: Single);
var
  X, Y, IX0, IY0, IX1, IY1, RX0, RX1: Integer;
  HW, Pad, DY, Lo, Hi, XA, XB, T, Len, DX, DYc: Single;
begin
  HW := Max(LineW, 0.35) / 2;
  { A line is a capsule, so its round caps poke half a width past each end.
    On thick lines that bleeds past corners, so lines wider than 1.5 pixels
    are pulled in by half their width at each end. }
  if LineW > 1.5 then
  begin
    Len := Sqrt(Sqr(X1 - X0) + Sqr(Y1 - Y0));
    if Len > 2 * HW + 0.5 then
    begin
      DX := (X1 - X0) / Len * HW;
      DYc := (Y1 - Y0) / Len * HW;
      X0 := X0 + DX; Y0 := Y0 + DYc;
      X1 := X1 - DX; Y1 := Y1 - DYc;
    end;
  end;
  { How far from the line a pixel can still be touched: coverage ends half
    a pixel past the edge, plus half a pixel to the pixel's corner.  A wider
    pad costs a lot on the ground grid. }
  Pad := HW + 1;
  IX0 := LoBound(Min(X0, X1) - Pad, FWidth);
  IY0 := LoBound(Min(Y0, Y1) - Pad, FHeight);
  IX1 := HiBound(Max(X0, X1) + Pad, FWidth);
  IY1 := HiBound(Max(Y0, Y1) + Pad, FHeight);

  DY := Y1 - Y0;
  for Y := IY0 to IY1 do
  begin
    if Abs(DY) < 1E-6 then
    begin
      { horizontal: the whole span is in this row anyway }
      RX0 := IX0;
      RX1 := IX1;
    end
    else
    begin
      { where the segment enters and leaves this row, padded by the width }
      Lo := (Y - Pad - Y0) / DY;
      Hi := (Y + 1 + Pad - Y0) / DY;
      if Lo > Hi then begin T := Lo; Lo := Hi; Hi := T; end;
      if Lo < 0 then Lo := 0;
      if Hi > 1 then Hi := 1;
      if Lo > Hi then Continue;               // the row is past an end
      XA := X0 + (X1 - X0) * Lo;
      XB := X0 + (X1 - X0) * Hi;
      if XA > XB then begin T := XA; XA := XB; XB := T; end;
      RX0 := Max(IX0, LoBound(XA - Pad, FWidth));
      RX1 := Min(IX1, HiBound(XB + Pad, FWidth));
    end;
    if FZOn and FZTest and FZBehind then
      for X := RX0 to RX1 do
      begin
        { hidden pass: only what is behind, dashed.  The dash is measured
          along the line so it is the same length in any direction. }
        if FZa * X + FZb * Y + FZc >= FZ[Y * FWidth + X] - 1E-4 then Continue;
        { Manhattan distance is close enough for a dash and skips a square root. }
        if ((Round(Abs(X - X0) + Abs(Y - Y0))) mod 13) >= 7 then Continue;
        BlendPixel(X, Y, C,
          Coverage(SdSegment(X + 0.5, Y + 0.5, X0, Y0, X1, Y1) - HW) * Alpha);
      end
    else if FZOn and FZTest then
      for X := RX0 to RX1 do
      begin
        { behind a face, so not seen.  The slack is a hair wider than the
          fill's, so rounding does not bury a line drawn on a face. }
        if FZa * X + FZb * Y + FZc < FZ[Y * FWidth + X] - 1E-4 then Continue;
        BlendPixel(X, Y, C,
          Coverage(SdSegment(X + 0.5, Y + 0.5, X0, Y0, X1, Y1) - HW) * Alpha);
      end
    else
      for X := RX0 to RX1 do
        BlendPixel(X, Y, C,
          Coverage(SdSegment(X + 0.5, Y + 0.5, X0, Y0, X1, Y1) - HW) * Alpha);
  end;
  Invalidate;
end;

procedure TArtSurface.Arc(CX, CY, Radius, A0, A1, LineW: Single; const C: TPix; Alpha: Single);
var
  Steps, I: Integer;
  A, Step, PX, PY, NX, NY: Single;
begin
  Steps := Max(6, Round(Abs(A1 - A0) * Radius / 30));
  Step := (A1 - A0) / Steps;
  PX := CX + Cos(A0) * Radius;
  PY := CY + Sin(A0) * Radius;
  for I := 1 to Steps do
  begin
    A := A0 + Step * I;
    NX := CX + Cos(A) * Radius;
    NY := CY + Sin(A) * Radius;
    Line(PX, PY, NX, NY, LineW, C, Alpha);
    PX := NX;
    PY := NY;
  end;
end;

procedure TArtSurface.Poly(const Pts: array of TPointF; LineW: Single; const C: TPix;
  Closed: Boolean; Alpha: Single);
var
  I: Integer;
begin
  if Length(Pts) < 2 then Exit;
  for I := 0 to High(Pts) - 1 do
    Line(Pts[I].X, Pts[I].Y, Pts[I + 1].X, Pts[I + 1].Y, LineW, C, Alpha);
  if Closed then
    Line(Pts[High(Pts)].X, Pts[High(Pts)].Y, Pts[0].X, Pts[0].Y, LineW, C, Alpha);
end;

procedure TArtSurface.Triangle(const P1, P2, P3: TPointF; const C: TPix; Alpha: Single);

  function Edge(const A, B: TPointF; PX, PY: Single): Single; inline;
  begin
    Result := (PX - A.X) * (B.Y - A.Y) - (PY - A.Y) * (B.X - A.X);
  end;

var
  X, Y, X0, Y0, X1, Y1: Integer;
  E1, E2, E3, Sign: Single;
begin
  X0 := LoBound(Min(P1.X, Min(P2.X, P3.X)) - 1, FWidth);
  Y0 := LoBound(Min(P1.Y, Min(P2.Y, P3.Y)) - 1, FHeight);
  X1 := HiBound(Max(P1.X, Max(P2.X, P3.X)) + 1, FWidth);
  Y1 := HiBound(Max(P1.Y, Max(P2.Y, P3.Y)) + 1, FHeight);
  Sign := Edge(P1, P2, P3.X, P3.Y);
  if Sign = 0 then Exit;
  Sign := Math.Sign(Sign);
  for Y := Y0 to Y1 do
    for X := X0 to X1 do
    begin
      E1 := Edge(P1, P2, X + 0.5, Y + 0.5) * Sign;
      E2 := Edge(P2, P3, X + 0.5, Y + 0.5) * Sign;
      E3 := Edge(P3, P1, X + 0.5, Y + 0.5) * Sign;
      if (E1 >= 0) and (E2 >= 0) and (E3 >= 0) then
        BlendPixel(X, Y, C, Alpha);
    end;
  Invalidate;
end;

procedure TArtSurface.DepthBegin;
var
  I: Integer;
begin
  if (FWidth <= 0) or (FHeight <= 0) then Exit;
  if Length(FZ) <> FWidth * FHeight then SetLength(FZ, FWidth * FHeight);
  for I := 0 to High(FZ) do FZ[I] := -1E30;
  FZOn := True;
  FZTest := False;
  FZBehind := False;
  FZa := 0; FZb := 0; FZc := -1E30;
end;


function TArtSurface.DepthOn: Boolean;
begin
  Result := FZOn;
end;

procedure TArtSurface.DepthTest(B: Boolean);
begin
  FZTest := B;
end;

procedure TArtSurface.DepthBehind(B: Boolean);
begin
  FZBehind := B;
end;

{ A line's depth as a plane in screen space, sloped along the line and flat
  across it, so a line lying on a face stays at the face's depth. }
procedure TArtSurface.DepthAlong(X0, Y0, Z0, X1, Y1, Z1: Double);
var
  DX, DY, L2: Double;
begin
  DX := X1 - X0;
  DY := Y1 - Y0;
  L2 := DX * DX + DY * DY;
  if L2 < 1E-12 then
  begin
    FZa := 0;
    FZb := 0;
    FZc := Z0;
    Exit;
  end;
  FZa := (Z1 - Z0) * DX / L2;
  FZb := (Z1 - Z0) * DY / L2;
  FZc := Z0 - FZa * X0 - FZb * Y0;
end;

procedure TArtSurface.DepthMesh(const Tris: TDepthTris);
var
  I: Integer;
  Lo, Hi: Single;
begin
  FZTris := Tris;
  SetLength(FZTriY0, Length(Tris));
  SetLength(FZTriY1, Length(Tris));
  { the rows each triangle can touch, worked out once for the row loop }
  for I := 0 to High(Tris) do
  begin
    Lo := Min(Tris[I].AY, Min(Tris[I].BY, Tris[I].CY));
    Hi := Max(Tris[I].AY, Max(Tris[I].BY, Tris[I].CY));
    FZTriY0[I] := Floor(Lo) - 1;
    FZTriY1[I] := Ceil(Hi) + 1;
  end;
end;

procedure TArtSurface.DepthPlane(A, B, C: Double);
begin
  { a new plane means a new shape, so drop any leftover mesh }
  FZTris := nil;
  FZTriY0 := nil;
  FZTriY1 := nil;
  FZa := A;
  FZb := B;
  FZc := C;
end;

function TArtSurface.DepthAt(X, Y: Integer): Single;
begin
  Result := -1E30;
  if Length(FZ) <> FWidth * FHeight then Exit;
  if (X < 0) or (Y < 0) or (X >= FWidth) or (Y >= FHeight) then Exit;
  Result := FZ[Y * FWidth + X];
end;

{ Scanline fill of one shape: an outline plus any holes, filled even-odd so
  holes need no special case.  Four vertical samples per row plus exact span
  ends make edges smooth enough to sit beside the anti-aliased strokes. }
procedure TArtSurface.FillLoops(const Loops: array of TPtFLoop; const C: TPix;
  Alpha: Single);
const
  SAMPLES = 4;
var
  N, I, J, Y, X, K, L, Cnt, X0, X1, Y0, Y1, Total: Integer;
  MinX, MaxX, MinY, MaxY, SY, XA, XB: Single;
  Xs: array of Single;
  Cov: array of Single;
  T: Single;
  Z: Double;
  Any: Boolean;
  Smp: Integer;
  { the exact depth for this row, where DepthMesh supplied triangles }
  Mesh: TDepthTris;
  MeshY0, MeshY1: array of Integer;
  { The edges of every loop, flattened and sorted, so each row only tests
    the few edges that can cross it instead of the whole outline. }
  EAX, EAY, EBX, EBY, ELo, EHi: array of Single;
  EOrder, EAct: array of Integer;
  NE, NAct, NextE, AI, AJ: Integer;
  { The part of the coverage row written last time, so only that is
    cleared; clearing the full width is slow for long thin diagonal faces. }
  ClrLo, ClrHi, CurLo, CurHi: Integer;
  { and the same idea for the depth triangles }
  RowZ: array of Double;
  RowHas: array of Boolean;
  TI, TC, TXLo, TXHi: Integer;
  TxA, TxB: Single;

  { grow the stretch of the row to take in one more x }
  procedure Take(V: Single; var N: Integer; var Lo, Hi: Single); inline;
  begin
    if N = 0 then begin Lo := V; Hi := V; end
    else begin if V < Lo then Lo := V; if V > Hi then Hi := V; end;
    Inc(N);
  end;

  { a corner of the triangle, if it falls inside the row's band }
  procedure Span(VX, VY: Single; Row: Integer; var N: Integer;
    var Lo, Hi: Single); inline;
  begin
    if (VY >= Row) and (VY <= Row + 1) then Take(VX, N, Lo, Hi);
  end;

  { where an edge of it crosses the top or the bottom of the band }
  procedure Cross(X1s, Y1s, X2s, Y2s: Single; Row: Integer; var N: Integer;
    var Lo, Hi: Single);
  var
    B: Integer;
    YB: Single;
  begin
    if Y1s = Y2s then Exit;
    for B := 0 to 1 do
    begin
      YB := Row + B;
      if (Y1s <= YB) = (Y2s <= YB) then Continue;
      Take(X1s + (X2s - X1s) * (YB - Y1s) / (Y2s - Y1s), N, Lo, Hi);
    end;
  end;

begin
  { the mesh is for this call only; every exit must leave it cleared }
  Mesh := FZTris;
  MeshY0 := FZTriY0;
  MeshY1 := FZTriY1;
  FZTris := nil;
  FZTriY0 := nil;
  FZTriY1 := nil;
  if not FZOn then Mesh := nil;
  if QuickFill then Smp := 1 else Smp := SAMPLES;
  Any := False;
  Total := 0;
  MinY := 0; MaxY := 0; MinX := 0; MaxX := 0;
  for L := 0 to High(Loops) do
  begin
    N := Length(Loops[L]);
    if N < 3 then Continue;
    Inc(Total, N);
    for I := 0 to N - 1 do
    begin
      if not Any then
      begin
        MinY := Loops[L][I].Y; MaxY := MinY;
        MinX := Loops[L][I].X; MaxX := MinX;
        Any := True;
      end
      else
      begin
        MinY := Min(MinY, Loops[L][I].Y);
        MaxY := Max(MaxY, Loops[L][I].Y);
        MinX := Min(MinX, Loops[L][I].X);
        MaxX := Max(MaxX, Loops[L][I].X);
      end;
    end;
  end;
  if not Any then Exit;

  Y0 := LoBound(MinY, FHeight);
  Y1 := HiBound(MaxY, FHeight);
  X0 := LoBound(MinX - 1, FWidth);
  X1 := HiBound(MaxX + 1, FWidth);
  if (Y1 < Y0) or (X1 < X0) then Exit;

  SetLength(Xs, Total + 2);
  SetLength(Cov, X1 - X0 + 2);

  { --- the edges, once ------------------------------------------------
        Level edges are left out; they can never cross a sample row. }
  SetLength(EAX, Total); SetLength(EAY, Total);
  SetLength(EBX, Total); SetLength(EBY, Total);
  SetLength(ELo, Total); SetLength(EHi, Total);
  SetLength(EOrder, Total); SetLength(EAct, Total);
  NE := 0;
  for L := 0 to High(Loops) do
  begin
    N := Length(Loops[L]);
    if N < 3 then Continue;
    for I := 0 to N - 1 do
    begin
      J := (I + 1) mod N;
      if Loops[L][I].Y = Loops[L][J].Y then Continue;
      EAX[NE] := Loops[L][I].X; EAY[NE] := Loops[L][I].Y;
      EBX[NE] := Loops[L][J].X; EBY[NE] := Loops[L][J].Y;
      if EAY[NE] < EBY[NE] then
      begin ELo[NE] := EAY[NE]; EHi[NE] := EBY[NE]; end
      else
      begin ELo[NE] := EBY[NE]; EHi[NE] := EAY[NE]; end;
      EOrder[NE] := NE;
      Inc(NE);
    end;
  end;
  if NE = 0 then Exit;
  { sorted by top Y so the row loop can take them in as it reaches them;
    insertion sort, since outlines come nearly sorted }
  for I := 1 to NE - 1 do
  begin
    AI := EOrder[I];
    J := I - 1;
    while (J >= 0) and (ELo[EOrder[J]] > ELo[AI]) do
    begin
      EOrder[J + 1] := EOrder[J];
      Dec(J);
    end;
    EOrder[J + 1] := AI;
  end;
  NAct := 0;
  NextE := 0;
  if Length(Mesh) > 0 then
  begin
    SetLength(RowZ, X1 - X0 + 2);
    SetLength(RowHas, X1 - X0 + 2);
  end;

  ClrLo := 0;
  ClrHi := High(Cov);
  for Y := Y0 to Y1 do
  begin
    for X := ClrLo to ClrHi do
      Cov[X] := 0;
    CurLo := High(Cov) + 1;
    CurHi := -1;

    { --- which edges this row can possibly be crossed by ---------------
          Bounds are a whole row generous on purpose: an extra edge costs
          nothing, a wrongly dropped one is a hole in a face. }
    while (NextE < NE) and (ELo[EOrder[NextE]] <= Y + 1) do
    begin
      EAct[NAct] := EOrder[NextE];
      Inc(NAct);
      Inc(NextE);
    end;
    AJ := 0;
    for AI := 0 to NAct - 1 do
      if EHi[EAct[AI]] >= Y then
      begin
        EAct[AJ] := EAct[AI];
        Inc(AJ);
      end;
    NAct := AJ;
    if NAct = 0 then Continue;

    { --- the exact depth along this row, one triangle at a time --------
          Each triangle is clipped to the row's whole band, not its center
          line, or thin triangles inside one row get missed.  Do not widen
          the stretches: the triangles already tile the face, and widening
          writes depth outside them.  Depth is clamped to the corner depths. }
    if Length(Mesh) > 0 then
    begin
      for X := 0 to High(RowHas) do
        RowHas[X] := False;
      for TI := 0 to High(Mesh) do
      begin
        if (Y < MeshY0[TI]) or (Y > MeshY1[TI]) then Continue;
        TC := 0;
        TxA := 0; TxB := 0;
        { corners of it that are in the band }
        Span(Mesh[TI].AX, Mesh[TI].AY, Y, TC, TxA, TxB);
        Span(Mesh[TI].BX, Mesh[TI].BY, Y, TC, TxA, TxB);
        Span(Mesh[TI].CX, Mesh[TI].CY, Y, TC, TxA, TxB);
        { and where its edges cross the top and the bottom of the band }
        Cross(Mesh[TI].AX, Mesh[TI].AY, Mesh[TI].BX, Mesh[TI].BY, Y, TC, TxA, TxB);
        Cross(Mesh[TI].BX, Mesh[TI].BY, Mesh[TI].CX, Mesh[TI].CY, Y, TC, TxA, TxB);
        Cross(Mesh[TI].CX, Mesh[TI].CY, Mesh[TI].AX, Mesh[TI].AY, Y, TC, TxA, TxB);
        if TC = 0 then Continue;
        TXLo := Max(X0, Floor(TxA));
        TXHi := Min(X1, Ceil(TxB));
        for X := TXLo to TXHi do
        begin
          RowZ[X - X0] := Min(Mesh[TI].ZHi, Max(Mesh[TI].ZLo,
            Mesh[TI].ZA * X + Mesh[TI].ZB * Y + Mesh[TI].ZC));
          RowHas[X - X0] := True;
        end;
      end;
    end;

    for K := 0 to Smp - 1 do
    begin
      SY := Y + (K + 0.5) / Smp;
      Cnt := 0;
      for AI := 0 to NAct - 1 do
      begin
        J := EAct[AI];
        if (EAY[J] <= SY) = (EBY[J] <= SY) then Continue;
        T := (SY - EAY[J]) / (EBY[J] - EAY[J]);
        Xs[Cnt] := EAX[J] + (EBX[J] - EAX[J]) * T;
        Inc(Cnt);
      end;
      if Cnt < 2 then Continue;

      { insertion sort - a handful of crossings at most }
      for I := 1 to Cnt - 1 do
      begin
        T := Xs[I];
        J := I - 1;
        while (J >= 0) and (Xs[J] > T) do
        begin
          Xs[J + 1] := Xs[J];
          Dec(J);
        end;
        Xs[J + 1] := T;
      end;

      I := 0;
      while I + 1 < Cnt do
      begin
        XA := Xs[I];
        XB := Xs[I + 1];
        Inc(I, 2);
        if IsNan(XA) or IsNan(XB) then Continue;
        if XB <= X0 then Continue;
        if XA >= X1 + 1 then Continue;
        XA := Max(XA, X0);
        XB := Min(XB, X1 + 1);
        for X := Floor(XA) to Ceil(XB) - 1 do
        begin
          if (X < X0) or (X > X1) then Continue;
          { how much of this pixel the span covers horizontally }
          T := Min(XB, X + 1.0) - Max(XA, X * 1.0);
          if T > 0 then
          begin
            Cov[X - X0] := Cov[X - X0] + T / Smp;
            if X - X0 < CurLo then CurLo := X - X0;
            if X - X0 > CurHi then CurHi := X - X0;
          end;
        end;
      end;
    end;

    ClrLo := CurLo;
    ClrHi := CurHi;
    for X := Max(X0, X0 + CurLo) to Min(X1, X0 + CurHi) do
      if Cov[X - X0] > 0.002 then
      begin
        if FZOn then
        begin
          if (Length(Mesh) > 0) and RowHas[X - X0] then
            Z := RowZ[X - X0]
          else
            Z := FZa * X + FZb * Y + FZc;
          { behind what is already there, so it does not get drawn }
          if Z < FZ[Y * FWidth + X] - 1E-6 then Continue;
          { only a pixel more than half covered claims the depth }
          if Cov[X - X0] > 0.5 then FZ[Y * FWidth + X] := Z;
        end;
        BlendPixel(X, Y, C, Cov[X - X0] * Alpha);
      end;
  end;
  Invalidate;
end;



{ Sprinkle bright/dark specks - the aluminum powder look while erasing. }
procedure TArtSurface.Grain(Amount, Density: Single);
var
  I, N, X, Y, D: Integer;
  P: PPix;
begin
  N := Round(FWidth * FHeight * EnsureRange(Density, 0, 1));
  for I := 1 to N do
  begin
    X := Random(FWidth);
    Y := Random(FHeight);
    D := Round((Random - 0.5) * 2 * Amount * 255);
    P := ScanLine(Y);
    Inc(P, X);
    P^.R := EnsureRange(P^.R + D, 0, 255);
    P^.G := EnsureRange(P^.G + D, 0, 255);
    P^.B := EnsureRange(P^.B + D, 0, 255);
  end;
  MarkAllDirty;
  Invalidate;
end;

{ Shift the image down by a few rows with a ragged edge, so the drawing
  looks like it is sliding off the screen. }
procedure TArtSurface.SmearDown(Rows: Integer);
var
  X, Y, Src: Integer;
  Dst, S: PPix;
begin
  if Rows <= 0 then Exit;
  for Y := FHeight - 1 downto 0 do
  begin
    Dst := ScanLine(Y);
    for X := 0 to FWidth - 1 do
    begin
      Src := Y - Rows - Random(2);
      if Src >= 0 then
      begin
        S := ScanLine(Src);
        Inc(S, X);
        Dst^ := S^;
      end;
      Inc(Dst);
    end;
  end;
  MarkAllDirty;
  Invalidate;
end;

procedure TArtSurface.CopyFrom(Src: TArtSurface; DX, DY: Integer);
var
  X, Y, W, H: Integer;
  S, D: PPix;
begin
  if Src = nil then Exit;
  W := Min(Src.Width, FWidth - DX);
  H := Min(Src.Height, FHeight - DY);
  for Y := 0 to H - 1 do
  begin
    S := Src.ScanLine(Y);
    D := ScanLine(Y + DY);
    Inc(D, DX);
    for X := 0 to W - 1 do
    begin
      D^ := S^;
      Inc(S);
      Inc(D);
    end;
  end;
  MarkAllDirty;
  Invalidate;
end;

procedure TArtSurface.ScaleUp2From(H: TArtSurface);
var
  X, Y, HW, HH: Integer;
  Src, Dst: PPix;
  ZRow: Integer;
begin
  if H = nil then Exit;
  Verify;
  H.Verify;
  HW := H.Width;
  HH := H.Height;
  if (HW <= 0) or (HH <= 0) or (FWidth <= 0) or (FHeight <= 0) then Exit;
  { two pixels a step, the odd last column on its own; a row of the small
    picture serves two rows here }
  for Y := 0 to FHeight - 1 do
  begin
    Src := H.ScanLine(Min(HH - 1, Y div 2));
    Dst := ScanLine(Y);
    for X := 0 to HW - 2 do
    begin
      Dst[2 * X] := Src[X];
      Dst[2 * X + 1] := Src[X];
    end;
    for X := 2 * (HW - 1) to FWidth - 1 do Dst[X] := Src[HW - 1];
  end;
  { the depth with it, so what is drawn on top can still ask what is in
    front: a pixel's depth is its quarter's }
  if Length(H.FZ) = HW * HH then
  begin
    if Length(FZ) <> FWidth * FHeight then SetLength(FZ, FWidth * FHeight);
    for Y := 0 to FHeight - 1 do
    begin
      ZRow := Min(HH - 1, Y div 2) * HW;
      for X := 0 to HW - 2 do
      begin
        FZ[Y * FWidth + 2 * X] := H.FZ[ZRow + X];
        FZ[Y * FWidth + 2 * X + 1] := H.FZ[ZRow + X];
      end;
      for X := 2 * (HW - 1) to FWidth - 1 do FZ[Y * FWidth + X] := H.FZ[ZRow + HW - 1];
    end;
    FZOn := True;
    FZTest := False;
    FZBehind := False;
    FZa := 0; FZb := 0; FZc := -1E30;
  end;
  MarkAllDirty;
  Invalidate;
end;

procedure TArtSurface.CopyRegion(Src: TArtSurface; SrcX, SrcY, DX, DY, W, H: Integer);
var
  X, Y, X0, Y0, X1, Y1: Integer;
  S, D: PPix;
begin
  if Src = nil then Exit;
  Verify;
  Src.Verify;
  if (W <= 0) or (H <= 0) then Exit;
  if (FWidth <= 0) or (FHeight <= 0) then Exit;
  if (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  { A copy from far outside either surface copies nothing, but the
    arithmetic would overflow first, so it is refused up front.  The cursor
    overlay can ask for one from a bad projected coordinate. }
  if (Abs(SrcX) > 1000000) or (Abs(SrcY) > 1000000) or
     (Abs(DX) > 1000000) or (Abs(DY) > 1000000) then Exit;
  X0 := Max(0, Max(-SrcX, -DX));
  Y0 := Max(0, Max(-SrcY, -DY));
  X1 := Min(W, Min(Src.Width - SrcX, FWidth - DX));
  Y1 := Min(H, Min(Src.Height - SrcY, FHeight - DY));
  if (X1 <= X0) or (Y1 <= Y0) then Exit;
  for Y := Y0 to Y1 - 1 do
  begin
    S := Src.ScanLine(SrcY + Y);
    Inc(S, SrcX + X0);
    D := ScanLine(DY + Y);
    Inc(D, DX + X0);
    { a row at a time - this copies a whole window of paper every frame }
    Move(S^, D^, (X1 - X0) * SizeOf(TPix));
  end;
  MarkAllDirty;
  Invalidate;
end;

procedure TArtSurface.Snapshot(out Buf: TBytes);
var
  Y: Integer;
begin
  SetLength(Buf, FWidth * FHeight * 4);
  for Y := 0 to FHeight - 1 do
    Move(ScanLine(Y)^, Buf[Y * FWidth * 4], FWidth * 4);
end;

procedure TArtSurface.Restore(const Buf: TBytes);
var
  Y: Integer;
begin
  if Length(Buf) <> FWidth * FHeight * 4 then Exit;
  for Y := 0 to FHeight - 1 do
    Move(Buf[Y * FWidth * 4], ScanLine(Y)^, FWidth * 4);
  MarkAllDirty;
  Invalidate;
end;

function TArtSurface.AsBitmap: TBitmap;
begin
  if not FBitmapValid then
  begin
    FBitmap.LoadFromIntfImage(FImage);
    { Re-read where the pixels are after handing the image to the
      widgetset; nothing says the buffer cannot move, and it costs one call. }
    FBits := PByte(FImage.GetDataLineStart(0));
    FBitmapValid := True;
  end;
  Result := FBitmap;
end;

procedure TArtSurface.DrawTo(ACanvas: TCanvas; X, Y: Integer);
begin
  ACanvas.Draw(X, Y, AsBitmap);
end;

{ ---------------------------------------------------------------------- }
{ text                                                                     }
{ ---------------------------------------------------------------------- }

{ Glyphs have to come from the widgetset, so text is rendered white-on-black
  into a scratch bitmap and then blended in using its luminance as coverage.
  That keeps dimension labels as crisp as the rest of the surface. }
var
  FScratch: TBitmap = nil;
  FScratchImg: TLazIntfImage = nil;

procedure EnsureScratch;
begin
  if FScratch = nil then
  begin
    FScratch := TBitmap.Create;
    FScratch.PixelFormat := pf32bit;
    FScratch.SetSize(8, 8);
  end;
end;

function TArtSurface.TextExtent(const S: string; AFont: TFont): TSize;
begin
  EnsureScratch;
  FScratch.Canvas.Font.Assign(AFont);
  Result := FScratch.Canvas.TextExtent(S);
end;

procedure TArtSurface.TextOut(X, Y: Integer; const S: string; AFont: TFont;
  const C: TPix; Alpha: Single);
var
  Sz: TSize;
  IX, IY: Integer;
  Col: TFPColor;
  Cov: Single;
begin
  if S = '' then Exit;
  EnsureScratch;
  FScratch.Canvas.Font.Assign(AFont);
  Sz := FScratch.Canvas.TextExtent(S);
  if (Sz.cx <= 0) or (Sz.cy <= 0) then Exit;

  FScratch.SetSize(Sz.cx + 2, Sz.cy + 2);
  FScratch.Canvas.Font.Assign(AFont);
  FScratch.Canvas.Brush.Style := bsSolid;
  FScratch.Canvas.Brush.Color := clBlack;
  FScratch.Canvas.FillRect(0, 0, FScratch.Width, FScratch.Height);
  FScratch.Canvas.Brush.Style := bsClear;
  FScratch.Canvas.Font.Color := clWhite;
  FScratch.Canvas.TextOut(1, 1, S);

  if FScratchImg = nil then
    FScratchImg := TLazIntfImage.Create(0, 0);
  FScratchImg.LoadFromBitmap(FScratch.Handle, 0);

  for IY := 0 to FScratchImg.Height - 1 do
    for IX := 0 to FScratchImg.Width - 1 do
    begin
      Col := FScratchImg.Colors[IX, IY];
      Cov := ((Col.red shr 8) * 0.30 + (Col.green shr 8) * 0.59 +
              (Col.blue shr 8) * 0.11) / 255;
      if Cov > 0.004 then
        BlendPixel(X + IX - 1, Y + IY - 1, C, Cov * Alpha);
    end;
end;


procedure TArtSurface.SaveToPNG(const AFileName: string);
var
  Png: TPortableNetworkGraphic;
begin
  Png := TPortableNetworkGraphic.Create;
  try
    Png.Assign(AsBitmap);
    Png.SaveToFile(AFileName);
  finally
    Png.Free;
  end;
end;

finalization
  FScratchImg.Free;
  FScratch.Free;

end.

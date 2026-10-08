unit hsDrawing;

{
  hsDrawing - the drafting side of Poopin Heckers Sketch.  A document of lines,
  arcs, faces, notes and dimensions kept as real geometry in feet or meters,
  plus length parsing and formatting, scales, snaps, hit testing and rendering.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}

interface

uses
  Contnrs,
  Classes, SysUtils, Types, Math, StrUtils, Graphics, hsSurface, hsTriangulate, hsDxf, hsSvg, hsText;

type
  TUnitSystem = (usImperial, usMetric);

  { A point in the model.  Everything is 3D, so a new view is only a new projection. }
  TP3 = record
    X, Y, Z: Double;
  end;

  { How the model is mapped onto the screen: vkPlan looks straight down Z,
    vkIso is drafting isometric with the axes at true length, vkOrbit is a
    free orthographic view you can spin. }
  TViewKind = (vkPlan, vkIso, vkOrbit);

  { The plane an arc or circle lies in.  plFree is whatever face you point
    at, so a circle can go on a sloped roof. }
  TPlane = (plXY, plXZ, plYZ, plFree);

  TProjector = record
    Kind: TViewKind;
    Ppu: Double;          // pixels per world unit
    OX, OY: Double;       // screen position of world 0,0,0
    Az, El: Double;       // vkOrbit only: turntable and tilt, in radians
  end;

  { A drawing scale.  Paper is the fraction of a paper unit that one world
    unit occupies - for 1/4" = 1'-0" that is 0.25 paper inches per foot. }
  TDrawScale = record
    Name: string;
    Paper: Double;
  end;

  { ekGuide: an infinite construction line that snaps but never makes a face;
    both points the same makes a guide point.  ekBore: a tunnel through solid
    Grp, Poly the opening, B where Poly[0] comes out.  ekPart: a group record -
    Grp its id, Txt its name, Solid locked, Part its parent.  Bores and groups
    are entities so undo, save, load and copy carry them for free. }
  TEntKind = (ekLine, ekArc, ekText, ekDim, ekFace, ekGuide, ekBore, ekPart);

  TIntArrayW = array of Integer;
  TIntArrayWArray = array of TIntArrayW;

  { Long work reports progress through this and stops if told to.  Nil in
    the tests and tools. }
  TProgressHook = function(const What: string; Frac: Double): Boolean of object;

var
  Progress: TProgressHook = nil;
  { Off so the tests and command line tools never start a thread; the
    program turns it on. }
  DefaultThreads: Boolean = False;
  { The lamp rides on the camera; off fixes it in the world with a narrow
    spread.  /light toggles it. }
  CameraLamp: Boolean = True;

type

  { One thing on the drawing, in world coordinates (feet or meters, Z up).
    ekLine uses A and B.  ekArc uses C (center), R, A0 (start angle) and
    Sweep - a circle is a sweep of 2*pi - and keeps A and B as its endpoints
    for snapping.  ekText uses A and Txt.  ekDim uses A and B. }
  TWorkEnt = record
    Kind: TEntKind;
    A, B, C: TP3;
    R, A0, Sweep: Double;
    Plane: TPlane;
    { Where the note's box last landed on screen, so a click can find it.
      Not saved. }
    BoxL, BoxT, BoxR, BoxB: Single;
    { For an arc in plFree, its plane's normal.  The arc carries its own so
      it does not drop back flat when the cursor moves on. }
    Nm: TP3;
    { straight pieces an arc is drawn and cut in; 0 means the default 48 }
    Sides: Integer;
    Poly: array of TP3;   // ekFace: the closed outline, in order
    { Loops cut out of a face: a window, a duct opening, the inside of a
      ring.  Empty for most faces. }
    Holes: array of array of TP3;
    Solid: Boolean;       // ekFace: part of a solid, so its back is hidden
    { The solid this belongs to, or 0 for loose drawing.  Push/pull drags
      only geometry in the same solid, so a box does not deform its neighbor. }
    Grp: Integer;
    { The group this belongs to, or 0.  Not the same as Grp: a group can hold
      several solids.  Geometry in different groups does not join, split or
      stretch each other. }
    Part: Integer;
    Txt: string;
    Ink: TColor;
    { ekFace: the material on its front.  MatSet says whether there is one,
      since a zeroed entity would otherwise come out painted black.  Kept
      apart from Ink: an edge has a color, a face has a material. }
    MatSet: Boolean;
    Mat: TColor;
    Weight: Single;
    { ekText: text size as a multiple of the normal note size; 0 means normal. }
    Size: Single;
    { ekPart: the jig that makes this group - "'star' with Points = 5" -
      or nothing.  See the manual's Heck page. }
    Jig: string;
    { ekPart: data the tool that made the group needs later (the radiant
      wizard reopens its zone from it).  "name = value" lines and blocks to
      "end" (see hsGroupData), kept whole even when not understood. }
    Data: string;
    Dim: Boolean;
    { A soft edge is one of the creases that stand in for a curved surface.
      Hidden except where it forms the outline, so a cylinder looks round. }
    Soft: Boolean;
    { ekPart: the group is put away - not drawn, picked or snapped to, along
      with every group inside it.  Kept on the group so its members hide as
      one; see EntHidden. }
    Hidden: Boolean;
    { What the text said about it, kept for when it is written again: the
      name it was given and the comments around it, as written.  A comment
      line starting with a tab went at the end of its first line.  SName and
      SNote are its solid's, carried by every member.  A group's name is Txt. }
    Name, Note, SName, SNote: string;
  end;

  TWorkEntArray = array of TWorkEnt;
  TP3Array = array of TP3;
  TPointFArray = array of TPointF;

  { Which part of a frame Render draws: rpAll is a whole frame, the other
    two are the halves of a half-resolution frame. }
  TRenderPhase = (rpAll, rpFaces, rpLines);

  { snSubMid: the middle of a piece of a crossed line; they multiply fast and
    rank below real points.  snOnEdge: any point along a line or arc.
    snOnAxis and snOrigin: the model axes and where they meet, so an empty
    sheet still has something to snap to. }
  TSnapKind = (snNone, snGrid, snEndpoint, snMidpoint, snCenter, snCross,
    snSubMid, snOnEdge, snOnAxis, snOrigin, snOnFace, snQuadrant);

  { Everything a dimension is drawn from, in screen coordinates.  One routine
    fills it so the preview and the result cannot drift apart. }
  TDimGeom = record
    A, B: TPointF;          { the two points being measured }
    W1, W2: TPointF;        { where each witness line ends }
    LA, LB: TPointF;        { the dimension line itself }
    S1A, S1B, S2A, S2B: TPointF;   { the slashes at each end }
    Mid: TPointF;           { the middle of the dimension line itself }
    Nrm: TPointF;           { unit vector pointing away from the geometry }
    Txt: string;
  end;

  TSnapHit = record
    P: TP3;
    Kind: TSnapKind;
  end;

  { TWorkDoc }

  { A corner rounded off: the two loose lines that met there, where the arc
    touches each of them, and the arc itself.  See TWorkDoc.FilletAt. }
  TFillet = record
    Corner, S, E: TP3;       { the corner, and the two tangent points }
    LineA, LineB: Integer;   { S lies on LineA, E on LineB }
    R, T: Double;            { radius; corner to each tangent point }
    Pl: TPlane;
    Nm: TP3;                 { the plane's facing, for a free one }
    ArcC: TP3;
    A0, Sweep, Bulge: Double;
  end;

  TWorkDoc = class
  private
    FEnts: array of TWorkEnt;
    FLive: Integer;      // entities in play; anything past this is redo space
    FSnapCache: array of TSnapHit;
    FSnapScreen: array of TPointF;
    FSnapScreenV: TProjector;
    FSnapScreenOK: Boolean;
    FSnapDirty: Boolean;
    { FaceUnder's last answer and everything that could change it.  One mouse
      move asks it two or three times, and each call ray-casts every face. }
    FFaceMemoOK: Boolean;
    FFaceMemoSeq: Int64;
    FFaceMemoX, FFaceMemoY: Double;
    FFaceMemoV: TProjector;
    FFaceMemoFace: Integer;
    FFaceMemoPt: TP3;
    FFaceMemoSlice: Boolean;
    FFaceMemoLo, FFaceMemoHi: Double;
    FGuidesHidden: Boolean;
    FNextGrp: Integer;
    { Groups: FNextPart numbers them, FContext is the group open for editing
      (0 the drawing), FStamp the group new geometry is born into. }
    FNextPart: Integer;
    FContext: Integer;
    FStamp: Integer;
    { The slice a plan view is cut out of - see SetSlice. }
    FSliceOn: Boolean;
    { which solids are closed, and the edit it was worked out at }
    FClosedSeq: Integer;
    FClosedGrp: array of Boolean;
    { every face cut into triangles, and the edit each cut was made at - see
      FaceCut }
    FCut: array of record
      Seq: Integer;
      Tris: TTriList;
    end;
    FSliceLo, FSliceHi: Double;
    FLastBore: Integer;
    function GetEnt(I: Integer): TWorkEnt;
    procedure RebuildSnapCache;
    procedure ArcSnaps(var N: Integer);
  public
    { the comments above the sheet's first thing and after its last }
    HeadNote, TailNote: string;
    procedure AddLine(const A, B: TP3; Ink: TColor; Weight: Single; Dim: Boolean);
    { True when a line with these ends is already there, either way round. }
    function HasLine(const A, B: TP3): Boolean;
    { Add a line, splitting it and any loose line it overlaps so the shared
      run is one edge.  Lines of a solid are not cut.  Returns how many pieces,
      or 0 when nothing overlapped. }
    function AddLineSplit(const A, B: TP3; Ink: TColor; Weight: Single): Integer;
    { Cut every loose edge that something drawn since FirstNew crosses, and
      the new edge where it is crossed, so each piece can be erased alone.
      Returns how many edges were broken. }
    function SplitCrossings(FirstNew: Integer): Integer;
    { Rounding a corner, SketchUp's way - see the bodies. }
    function FarEnd(I: Integer; const P: TP3): TP3;
    function ArcFromChordFor(var F: TFillet): Boolean;
    function CornerLines(const Corner: TP3; out LA, LB: Integer): Boolean;
    function FilletAt(const Corner: TP3; R: Double; out F: TFillet): Boolean;
    function FilletFromEnds(const S, E: TP3; out F: TFillet): Boolean;
    function NearestCorner(const V: TProjector; SX, SY, TolPx: Double;
      out Corner: TP3): Boolean;
    function ApplyFillet(const F: TFillet; Sides: Integer; Ink: TColor;
      Weight: Single; Trim: Boolean): Boolean;
    function TrimFillet(const F: TFillet): Integer;
    { A line's length, typed.  See the body for which end gives. }
    function LineEndJoined(I: Integer; AtB: Boolean): Boolean;
    function LineLengthEnd(I: Integer; out MoveB: Boolean): Boolean;
    function SetLineLength(I: Integer; NewLen: Double): Boolean;
    procedure AddArc(const C: TP3; R, A0, Sweep: Double; Pl: TPlane;
      Ink: TColor; Weight: Single);
    procedure SetArcSides(Index, N: Integer);
    { Follow Me, the turning half: spin the face Face about the axis through
      AxisP along AxisDir by Angle, in Steps gores, into one solid.  Returns
      the index of the first thing made, or -1.  A full turn consumes the
      profile face; a part turn keeps it as one cap and makes the other. }
    function Revolve(Face: Integer; const AxisP, AxisDir: TP3; Angle: Double;
      Steps: Integer): Integer;
    { Follow Me, the path half: push face Face along Path, mitred at every
      corner, into one solid.  A closed path has no caps and uses up the
      profile.  Returns the index of the first thing made, or -1. }
    function Sweep(Face: Integer; const Path: TP3Array; Closed: Boolean;
      Caps: Boolean = True): Integer;
    { the points of an arc or a line, in order, for building a path }
    procedure EdgePoints(I: Integer; out Pts: TP3Array);
    procedure MarkProfileArcs(const Poly: TP3Array; G: Integer);
    { where a dimension's line sits: the offset from what it measures }
    procedure SetDimOffset(Index: Integer; const Off: TP3);
    procedure AddText(const A: TP3; const S: string; Ink: TColor);
    { A note with a leader out to Target.  Target = A means no leader, which
      is a plain label. }
    procedure AddNote(const A, Target: TP3; const S: string; Ink: TColor);
    { Off is the vector from what is measured to where the dimension line
      sits - a real displacement in the model, not a number of pixels. }
    procedure AddDim(const A, B: TP3; Ink: TColor; const Off: TP3;
      const Note: string = '');
    { Write over a dimension's figure, or hand it back to the measurement by
      passing an empty string.  False when that entity is not a dimension. }
    function SetDimNote(Index: Integer; const Note: string): Boolean;
    { A construction line through A running towards B, or - when the two are
      the same point - a construction point at A. }
    procedure AddGuide(const A, B: TP3);
    function GuideCount: Integer;
    { Hiding guides must reach the snap cache, or the cursor jumps to guide
      points that are not shown. }
    procedure SetGuidesHidden(On_: Boolean);
    { Guides can be hidden without deleting them.  Stored as "hidden" so a
      new document shows them. }
    property GuidesHidden: Boolean read FGuidesHidden write SetGuidesHidden;
    { The horizontal section a plan view is cut from: only what lies between
      Lo and Hi is drawn, snapped to or picked.  Off means the whole model.
      What is visible and what can be touched must always be the same set. }
    procedure SetSlice(AOn: Boolean; ALo, AHi: Double);
    property SliceOn: Boolean read FSliceOn;
    property SliceLo: Double read FSliceLo;
    property SliceHi: Double read FSliceHi;
    { Is this entity in the slice?  True for everything when it is off. }
    function InSlice(Index: Integer): Boolean;
    { How many things the slice keeps out, so the program can say so. }
    function OutsideSlice: Integer;
    { Is this solid closed - every edge of it shared by exactly two faces,
      run opposite ways?  On one that is, a face turned away from the camera
      can never be seen, so it need not be drawn at all. }
    function GroupClosed(G: Integer): Boolean;
    { Where a group is not closed: edges not shared by exactly two faces
      running opposite ways, as pairs of points.  T-junctions are resolved
      first, as in GroupClosed.  Nothing draws these yet. }
    function OpenEdges(G: Integer): TP3Array;

    { This face cut into triangles, as index triples into FaceCorners.  Cut in
      the face's own plane so it does not depend on the camera and can be
      cached per edit; that also keeps a bent face from projecting to an
      outline that crosses itself.  Empty if degenerate. }
    function FaceCut(Index: Integer): TTriList;
    { The corners FaceCut indexes: the outline, then each hole in order. }
    function FaceCorners(Index: Integer): TP3Array;
    { The Z range of everything, for setting a slice that holds the lot. }
    function ZRange(out Lo, Hi: Double): Boolean;
    function ClearGuides: Integer;
    procedure AddFace(const Pts: array of TP3; Ink: TColor; Solid: Boolean = False);
    procedure AddFaceRaw(const Pts: array of TP3; Ink: TColor; Solid: Boolean);
    { Turns a face over; the last word when the winding rule guessed wrong. }
    function ReverseFace(Index: Integer): Boolean;
    { Make the loose faces of one group agree about which way is out.
      OrientFace winds each face alone and gets roof slopes and gable ends
      backwards; faces sharing an edge must run opposite ways along it, which
      settles a whole sheet.  Only across edges with exactly two faces;
      solids are left alone.  Returns how many faces it turned. }
    function OrientLooseShells(Part: Integer = 0): Integer;
    { The record of a tunnel: its opening, where the first corner of that
      opening comes out, and whose solid it is. }
    procedure AddBore(const Loop: TP3Array; const FarOfFirst: TP3; G: Integer);
    { Give a face the loops cut out of it - a window in a wall, the middle of
      a ring left by an offset. }
    procedure SetFaceHoles(Index: Integer; const H: array of TP3Array);
    { Make a face part of a solid - the one whose face it was cut from. }
    procedure SetFaceGroup(Index, G: Integer);
    { a line belongs to a solid: the Heck reader puts a solid's edges back }
    procedure SetLineGroup(Index, G: Integer);
    { turn an arc to face any way: the plane becomes a free one with this
      normal, and A0 is then measured in AxesFromNormal's terms }
    procedure SetArcFacing(Index: Integer; const Nm: TP3; A0: Double);
    { the same for anything - a line that belongs to a solid, say }
    procedure SetGroup(Index, G: Integer);
    { what the text named it and said about it; see TWorkEnt.Name }
    procedure SetNaming(Index: Integer; const AName, ANote: string);
    procedure SetSolidNaming(Index: Integer; const AName, ANote: string);
    { a fresh solid identity, for something built rather than pulled }
    function NewGroup: Integer;
    procedure SetSoft(Index: Integer; Soft: Boolean);
    { What an entity is drawn with, changed after the fact - the entity
      panel's color and width rows. }
    procedure SetInk(Index: Integer; Ink: TColor);
    procedure SetWeight(Index: Integer; Weight: Single);
    { The material on a face's front.  Material returns False for a face
      never painted. }
    procedure SetMaterial(Index: Integer; C: TColor);
    procedure ClearMaterial(Index: Integer);
    function Material(Index: Integer; out C: TColor): Boolean;
    { Turn a face over: its outline and its openings run the other way round,
      so its normal points the other way. }
    procedure FlipFace(Index: Integer);
    { A note's text size as a multiple of normal; 1 when never set. }
    function NoteSize(Index: Integer): Single;
    procedure SetNoteSize(Index: Integer; Factor: Single);

    { Hand the edges round a face to a solid's group, so they stop counting
      as loose lines. }
    procedure ClaimOutline(Face, G: Integer);
    { push/pull: lift the face along its own normal and wall in the sides }
    function PushPull(Index: Integer; Dist: Double): Boolean;
    { How far this face has to travel along its own normal to come out the
      far side of the solid it is on.  Want gives the direction, and comes
      back unchanged when there is nothing to come out of. }
    function ThroughDistance(Face: Integer; Want: Double): Double;
    { Slide a face along a vector, dragging everything joined to it. }
    procedure MoveFaceWith(Index: Integer; const D: TP3);
    { after a face of a solid has been moved: if that pressed the solid
      flat, take away what is left of it and leave the one face }
    function FlattenedAway(Index: Integer): Boolean;
    { A pushed patch whose far end lands on another face of the same solid
      that contains it.  Opens that face, walls the tunnel, removes the patch
      and its edges' claim.  False when the push lands anywhere else. }
    function TunnelThrough(Index: Integer; const Top: TP3Array;
      const Nm: TP3; Dist: Double): Boolean;
    { Every corner of these entities, for moving or for stretching. }
    procedure VertsOf(const Idx: array of Integer; out Pts: TP3Array);
    { The faces these edges hold up, as outline or opening.  Erasing an edge
      takes them with it. }
    function FacesOnEdges(const Idx: array of Integer;
      out Faces: TIntArrayW): Integer;
    { The guide points on these guide lines, which go when the line is erased. }
    function PointsOnGuides(const Idx: array of Integer;
      out Pts: TIntArrayW): Integer;
    { Shift every vertex sitting on one of these points; joined geometry
      stretches along. }
    procedure MoveVerts(const Pts: TP3Array; const D: TP3);
    { For every edge not itself moving but with an end at one of these
      corners, the two points it will run between after a move of D - so the
      preview can show the stretch. }
    procedure StretchPreview(const Pts: TP3Array; const D: TP3;
      const Skip: array of Integer; out Segs: TP3Array);
    { Every stored point at or past the plane through Base facing Dir.  What
      a dimension pushes when it is given a new length. }
    procedure VertsBeyond(const Base, Dir: TP3; out Pts: TP3Array);
    { Give a dimension a new length and let the drawing follow.  MoveB moves
      the end it was drawn to; False moves the end it was drawn from. }
    function ResizeDim(Index: Integer; NewLen: Double; MoveB: Boolean): Boolean;
    { What an axis will do to an outline, before it does it.  True when the
      axis runs through the outline rather than beside it; RLo and RHi are
      the inside and outside radius of what would come off the lathe. }
    function AxisSplitsFace(Face: Integer; const AxisP, AxisDir: TP3;
      out RLo, RHi: Double): Boolean;
    procedure RotateEnt(I: Integer; const Pts: TP3Array; const C, Axis: TP3;
      Ang: Double; All: Boolean);
    { Every corner on the set turns about the axis; whatever shares a corner
      stretches to follow, the same rule as MoveVerts.  An arc turns whole. }
    procedure RotateVerts(const Pts: TP3Array; const C, Axis: TP3; Ang: Double);
    { These entities turn whole, whatever they touch - for a copy. }
    procedure RotateEnts(const Idx: array of Integer; const C, Axis: TP3; Ang: Double);
    { These entities shift whole, whatever they touch - a built part being
      put down, which must not drag the corner it happened to be built on. }
    procedure TranslateEnts(const Idx: array of Integer; const D: TP3);
    { The middle of these things, or of everything if none are named. }
    function MiddleOf(const Idx: array of Integer; out Mid: TP3): Boolean;
    { The box these things sit in. }
    function SpanOf(const Idx: array of Integer; out Lo, Hi: TP3): Boolean;
    { SketchUp's arrays: N copies of Src at D, 2D, 3D... (3x), or at D/N,
      2D/N ... D when Divide is on (/3); ArrayRotate likewise by Ang.  Made
      is every new entity, in order, appended at the end. }
    procedure ArrayMove(const Src: array of Integer; const D: TP3; N: Integer;
      Divide: Boolean; out Made: TIntArrayW);
    procedure ArrayRotate(const Src: array of Integer; const C, Axis: TP3;
      Ang: Double; N: Integer; Divide: Boolean; out Made: TIntArrayW);
    { The points Outline projects, before projection - for drawing a ghost
      of the thing somewhere other than where it is. }
    function OutlineWorld(I: Integer): TP3Array;
    { --- groups -----------------------------------------------------------
      A group is an ekPart entity; its members are the entities whose Part is
      its id.  Context is the group open for editing (0: the drawing), and
      everything drawn while it is open belongs to it. }
    function NewPart(const Name: string; Parent: Integer): Integer;
    { the ekPart entity carrying this id, or -1 }
    function PartEnt(Id: Integer): Integer;
    function PartName(Id: Integer): string;
    function PartLocked(Id: Integer): Boolean;
    function PartParent(Id: Integer): Integer;
    procedure SetPartName(Id: Integer; const Name: string);
    procedure SetPartLocked(Id: Integer; Locked: Boolean);
    function PartJig(Id: Integer): string;
    procedure SetPartJig(Id: Integer; const Spec: string);
    function PartData(Id: Integer): string;
    procedure SetPartData(Id: Integer; const Data: string);
    procedure SetPartParent(Id, Parent: Integer);
    { a group put away, or brought back - see TWorkEnt.Hidden }
    function PartHidden(Id: Integer): Boolean;
    procedure SetPartHidden(Id: Integer; Hidden: Boolean);
    { Is this entity in a hidden group, however deep?  A group's own record
      counts as inside itself. }
    function EntHidden(I: Integer): Boolean;
    procedure WorkOutHidden;
    { which group an entity is in, and putting it in one }
    procedure SetPart(Index, Id: Integer);
    { Is this entity inside the open context - in it, or in a group inside
      it, however deep?  With nothing open, everything is. }
    function InsideContext(I: Integer): Boolean;
    { The group you would take hold of by clicking this entity: the outermost
      group between it and the open context.  0 when the entity lies loose
      in the context; -1 when it is outside the context altogether. }
    function TopPartIn(I: Integer): Integer;
    { Is that group, or any group between it and the context, locked? }
    function PartLockedUp(Id: Integer): Boolean;
    { every entity in the group, groups inside it and all, and its own
      record last if asked for }
    function PartMembers(Id: Integer; WithRecord: Boolean): TIntArrayW;
    function PartBounds(Id: Integer; out Lo, Hi: TP3): Boolean;
    { walk the ids again after a load or an undo, so the next one is new }
    procedure RecountParts;
    { the group's box as snap points - see the body }
    procedure CrateSnaps(var N: Integer);
    procedure SetContext(Id: Integer);
    function DimIf(I: Integer; const C: TPix): TPix;
    function InkPix(I: Integer): TPix;
    property Context: Integer read FContext write SetContext;
    property Stamp: Integer read FStamp write FStamp;
    property NextPart: Integer read FNextPart;
    { Copy these entities, offset.  A copy stretches nothing. }
    procedure Duplicate(const Idx: array of Integer; const D: TP3);
    { A deep copy of a selection that survives a switch to another sheet.
      PasteIn puts it back, here or in another document, offset by D, with
      group ids remapped. }
    function CopyOut(const Idx: array of Integer): TWorkEntArray;
    function PasteIn(const Ents: TWorkEntArray; const D: TP3;
      out First, Last: Integer): Integer;
    { Does a box dragged over the screen take this?  The geometry is tested,
      not its bounding box. }
    function BoxTakes(const V: TProjector; I: Integer;
      X0, Y0, X1, Y1: Double; Crossing: Boolean): Boolean;
    { everything a box takes, with guides only if it caught nothing else }
    function BoxPick(const V: TProjector; X0, Y0, X1, Y1: Double;
      Crossing: Boolean): TIntArrayW;
    { where an entity lands on screen }
    procedure ScreenBounds(const V: TProjector; I: Integer;
      out X0, Y0, X1, Y1: Double);
    { Cut every flat face this segment crosses in two.  Returns how many were
      split.  This is what makes a line drawn across a shape divide it. }
    function SplitFacesWith(const A, B: TP3): Integer;
    { The smallest face this point lies on, inside its outline and not in a
      hole; -1 for none.  For a replayed press, which knows the point but not
      the camera. }
    function FaceHolding(const P: TP3): Integer;
    { Is this face a piece of a larger flat area - another face in its plane
      running along one of its edges?  Push slides a whole side but lifts a
      patch out. }
    function IsPatch(Index: Integer): Boolean;
    { Can this face slide along its normal without bending anything?  Only
      when every neighboring face of its solid stands square to it; otherwise
      it is lifted out as a new block. }
    function WallsSquareTo(Index: Integer): Boolean;
    { The face a point lies on, or -1.  Used to work out which plane a new
      shape belongs in when the cursor has snapped to a corner. }
    function FaceThrough(const P: TP3): Integer;
    function SplitFace(Index: Integer; const A, B: TP3): Boolean;
    function HitFace(const V: TProjector; SX, SY: Double): Integer;
    { The same search, but also handing back the point on that face where the
      cursor meets it - which is where a new shape drawn there should sit. }
    function FaceUnder(const V: TProjector; SX, SY: Double;
      out Face: Integer; out Pt: TP3): Boolean;
    function FaceNormal(Index: Integer): TP3;
    function FaceArea(Index: Integer): Double;
    procedure Delete(I: Integer);
    { every entity marked True goes, in one pass; the rest keep their order }
    procedure DeleteMarked(const Doomed: array of Boolean);
    procedure Room;
    procedure Clear;
    function Snapshot: TWorkEntArray;
    procedure RestoreSnap(const A: TWorkEntArray);
    function Stored: Integer;

    { the run of chained lines ending at the last entity }
    function FirstOfChain: Integer;
    function ChainLength: Double;
    function ChainClosed(Tol: Double): Boolean;
    function ChainArea: Double;

    { Hit testing and snapping work in screen space so every view behaves the
      same.  Guides False leaves guides out; only the measure tool takes them. }
    function HitTest(const V: TProjector; SX, SY, TolPx: Double; Guides: Boolean = True): Integer;
    { Is this point of the model hidden behind a face, from where we look? }
    function HiddenAt(const V: TProjector; const P: TP3): Boolean;
    { The note whose box is under this point, or -1, from where the box was
      last drawn. }
    function HitNote(SX, SY: Double): Integer;
    { Carry a note's box to a new place.  Only the box - what it points at is
      left where it is. }
    procedure MoveNote(Index: Integer; const From, ToPt, Grab: TP3);
    { Like HitTest but edges only.  GuideTolPx is how close the cursor must be
      to a guide, kept tight so a guide is not picked by accident; left out it
      is TolPx, and HIT_NO_GUIDES leaves guides out. }
    function HitEdge(const V: TProjector; SX, SY, TolPx: Double;
      GuideTolPx: Double = -1): Integer;
    { the guide line under the cursor - guides alone, for the measure tool }
    function HitGuideLine(const V: TProjector; SX, SY, TolPx: Double): Integer;
    { Does the run from A to B lie along any edge through A?  At a corner
      every edge is asked, not only the one the click found. }
    function RunsAlongEdge(const A, B: TP3): Boolean;
    { The guide point nearest the cursor, or -1.  Asked first, because a guide
      point usually sits on the line it was measured along. }
    function HitGuidePoint(const V: TProjector; SX, SY, TolPx: Double): Integer;
    { The pen weight of the line between these two points, or 0.  New solid
      edges copy it. }
    function EdgeWeight(const A, B: TP3): Single;
    { The color of the pen that drew this face's outline, or Default when no
      edge of it can be found.  A solid's new edges are drawn with it. }
    function OutlineInk(Face: Integer; Default: TColor): TColor;
    { how many points the cursor is choosing between - for measuring with }
    function SnapCacheCount: Integer;
    { The nearest point on a line or arc within TolPx - SketchUp's On Edge,
      as opposed to the nearest corner. }
    function EdgeSnap(const V: TProjector; SX, SY, TolPx: Double;
      out P: TP3; out Ent: Integer): Boolean;
    { Like EdgeSnap, but hands back the segment under the cursor, A to B.  For
      a line or arc that is the whole entity; for a face it is the one side of
      the outline pointed at, which HitEdge cannot see. }
    function EdgeUnder(const V: TProjector; SX, SY, TolPx: Double;
      out P, A, B: TP3; out Ent: Integer): Boolean;

    { Marks the snap cache dirty so a new drawing builds it, origin included. }
    constructor Create;
    destructor Destroy; override;

    { Every point worth snapping or aligning to, including the places lines
      cross each other and the midpoints those crossings create. }
    procedure SnapPoints(out Pts: TP3Array);

    { An entity's outline in screen coordinates, for highlighting it. }
    function Outline(const V: TProjector; I: Integer): TPointFArray;
    function BestSnap(const V: TProjector; SX, SY, TolPx: Double;
      out Hit: TSnapHit): Boolean;
    function Bounds(out Lo, Hi: TP3): Boolean;

    { EdgeW is one weight for every edge, a style setting as in SketchUp, so
      push/pull never has to guess what pen an outline was drawn with. }
    procedure Render(S: TArtSurface; const V: TProjector;
      U: TUnitSystem; AFont: TFont; const LabelCol: TPix; EdgeW: Single;
      Half: TArtSurface = nil; Phase: TRenderPhase = rpAll);

    { Pull every arc end that falls a hair short of a line's or arc's end
      exactly onto it, moving the center as little as possible.  Rounded file
      values leave big arcs just off their corners and the region finder then
      loses the faces.  Called after every load. }
    procedure HealArcEnds;
    { The drawing as DXF.  ThreeD writes the model in its own coordinates,
      faces and all; otherwise this view, flat, as snappable entities.
      AtOrigin centers the model on 0,0,0 so it does not land far off in
      someone else's CAD. }
    procedure WriteDXF(L: TStrings; const V: TProjector; U: TUnitSystem;
      ThreeD: Boolean; AtOrigin: Boolean = False);
    { The model as binary STL for a slicer: FaceCut's triangles in millimeters
      (304.8 per foot, 1000 per meter), since STL has no units.  Returns the
      triangle count; Closed says whether every solid was closed.  AtOrigin
      centers the model on 0,0,0. }
    function WriteSTL(St: TStream; U: TUnitSystem; out Closed: Boolean;
      AtOrigin: Boolean = True): Integer;
    { The model as an OpenSCAD polyhedron - the surface, not a parametric
      build.  One module per closed solid plus a union, in millimeters.
      OpenSCAD wants each face CLOCKWISE seen from outside, the opposite of
      STL; backwards looks right in preview and fails on subtraction.
      Returns the triangle count, and the solid count through Solids. }
    function WriteSCAD(L: TStrings; U: TUnitSystem; out Solids: Integer;
      out Closed: Boolean; AtOrigin: Boolean = True): Integer;
    procedure WriteVectors(Writer: TVectorWriter; const V: TProjector;
      U: TUnitSystem; EdgeW: Single);
    procedure WriteSVG(L: TStrings; const V: TProjector; U: TUnitSystem;
      EdgeW: Single);

  public
    { Where a frame's time went, ms, summed until cleared: 0 setup and whole
      edges, 1 faces gathered and depths taken, 2 sorted and painted, 3 lines
      on faces, 4 guide points and tidying. }
    ProfMs: array[0..5] of Double;
    { The surface and projector of the last render.  Its depth buffer answers
      "is this point hidden" in one lookup for the same projector. }
    LastSurf: TArtSurface;
    LastV: TProjector;
    { True once a borrowed surface was freed under us; only for reports. }
    LastSurfDied: Boolean;
    { For each line, arc, dimension or note, the faces it lies on.  Depends
      only on geometry, so it is built once per change. }
    FOnFace: array of TIntArrayW;
    FOnFaceOK: Boolean;
    OnFaceBuilds: Integer;
    { With Threads on, the on-face cache is built on a worker from a copy and
      taken only if the drawing has not changed since.  Until then the
      renderer searches every face, so a late or dropped result is harmless.
      See docs/render-acceleration.md. }
    Threads: Boolean;
    FEditSeq: Integer;
    { EntHidden's answers, worked out once per edit: FHideOf[I] for each
      entity, good while FHideSeq is FEditSeq and the list is as long }
    FHideOf: array of Boolean;
    FHideSeq: Integer;
    FAnyHidden: Boolean;
    FOnFaceWorker: TThread;
    { the last build of the cache: how long, and where it ran }
    OnFaceWorkerMs: Double;
    OnFaceBuiltOn: string;
    { how long the result waited in the queue, and what a frame without the
      cache spent on lines on faces - whether the worker is worth it }
    OnFaceLagMs: Double;
    OnFaceFallbackMs: Double;
    OnFaceDiscarded, OnFaceFailed, OnFaceFallbacks: Integer;
    { The quick frame, while the camera is moving: coarser lines on faces.
      The full frame comes when it stops. }
    Quick: Boolean;
    { the last push pressed a solid flat; the caller works out the flat areas
      again so the face under it is cut round it }
    LastFlattened: Boolean;
    { samples per line and halvings per run end in a quick frame; coarser
      lets lines bleed through face edges while orbiting.  tools/inkprof
      sweeps the choices. }
    QuickSteps: Integer;
    QuickBisect: Integer;
    procedure EnsureOnFace;
    procedure OnFaceArrived;
    { the cache is there and current }
    function OnFaceReady: Boolean;
    { the one-lookup form of HiddenAt; only valid straight after a render
      with the same projector }
    function DepthHidden(const P: TP3): Boolean;
    { the nearest drawn thing within Radius pixels of a screen point, as a
      world point, from the last frame's depth buffer - what the eye is
      looking at, whether or not a face is exactly under the cursor }
    function DepthPointNear(SX, SY, Radius: Integer; out P: TP3): Boolean;
  public
    property Live: Integer read FLive;
    { the bore the last PushPull made, or -1 - so the caller can cut it
      against the others }
    property LastBore: Integer read FLastBore;
    property Ent[I: Integer]: TWorkEnt read GetEnt; default;
  end;

const
  { HitEdge's GuideTolPx for no guides at all }
  HIT_NO_GUIDES = -2;

  SCALE_COUNT = 5;

  IMPERIAL_SCALES: array[0..SCALE_COUNT - 1] of TDrawScale = (
    (Name: '1/16"'; Paper: 0.0625),
    (Name: '1/8"';  Paper: 0.125),
    (Name: '1/4"';  Paper: 0.25),
    (Name: '1/2"';  Paper: 0.5),
    (Name: '1"';    Paper: 1.0));

  METRIC_SCALES: array[0..SCALE_COUNT - 1] of TDrawScale = (
    (Name: '1:200'; Paper: 0.005),
    (Name: '1:100'; Paper: 0.01),
    (Name: '1:50';  Paper: 0.02),
    (Name: '1:20';  Paper: 0.05),
    (Name: '1:10';  Paper: 0.1));

  SNAP_COUNT = 10;

  { snap increments in feet or meters; 0 means none.  A sixteenth of an inch
    is 1/192 ft. }
  IMPERIAL_SNAPS: array[0..SNAP_COUNT - 1] of Double =
    (0, 1 / 192, 1 / 96, 1 / 48, 1 / 24, 1 / 12, 1 / 6, 0.25, 0.5, 1.0);
  IMPERIAL_SNAP_NAMES: array[0..SNAP_COUNT - 1] of string =
    ('OFF', '1/16"', '1/8"', '1/4"', '1/2"', '1"', '2"', '3"', '6"', '1''-0"');

  METRIC_SNAPS: array[0..SNAP_COUNT - 1] of Double =
    (0, 0.001, 0.002, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 1.0);
  METRIC_SNAP_NAMES: array[0..SNAP_COUNT - 1] of string =
    ('OFF', '1mm', '2mm', '5mm', '10mm', '25mm', '50mm', '100mm', '250mm', '1m');

function UnitName(U: TUnitSystem): string;
function ScaleTable(U: TUnitSystem; I: Integer): TDrawScale;
function SnapValue(U: TUnitSystem; I: Integer): Double;
function SnapName(U: TUnitSystem; I: Integer): string;

{ Pixels per world unit for a scale, given the display resolution in pixels
  per paper inch. }
function PixelsPerUnit(U: TUnitSystem; const Sc: TDrawScale; DPI: Double): Double;

{ How finely an imperial length is written, and what the last field of a
  dashed entry counts in.  A sixteenth unless the drawing says otherwise. }
procedure SetLenDenom(D: Integer);
function LenDenom: Integer;

function FormatLen(V: Double; U: TUnitSystem): string;
function FormatArea(V: Double; U: TUnitSystem): string;
{ A typed length - and a little arithmetic of them: 8' + 8", 8'17" / 2,
  10' - 3'4", (8' + 4") * 2 (see its body) }
function ParseLen(const S: string; U: TUnitSystem; out V: Double): Boolean;
{ one length alone, no arithmetic }
function ParseLenPlain(const S: string; U: TUnitSystem; out V: Double): Boolean;

{ An angle as typed for the rotate tool and the protractor: decimal degrees
  (34.1, -45, 90d), or a slope as rise:run (8:12).  Negative is the other way. }
function ParseAngle(const S: string; out Deg: Double): Boolean;
function FormatAngle(Deg: Double): string;

{ The number of straight pieces this arc is walked in, everywhere it is
  walked: drawn, picked, cut into regions, laid flat. }
function ArcSteps(const E: TWorkEnt): Integer;

{ SketchUp's way of saying how many sides: 24s, or s24.  Nothing else. }
function ParseSides(const S: string; out N: Integer): Boolean;

{ P turned about the line through C along the unit vector Axis, by Ang
  radians, right-handed.  RotV does the same to a direction. }
function RotP(const P, C, Axis: TP3; Ang: Double): TP3;
function RotV(const V, Axis: TP3; Ang: Double): TP3;
{ Reads "[3', 4', 5']" or "<3', 4', 5'>" - a point in the drawing, or an
  offset from where you are.  Returns how many of the three were given;
  any left out come back as zero. }
function ParseTriple(const S: string; U: TUnitSystem;
  out X, Y, Z: Double): Integer;

{ A "nice" round bar length that lands between MinPx and MaxPx on screen. }
function NiceBarLength(Ppu: Double; MinPx, MaxPx: Double; U: TUnitSystem): Double;

{ Build an arc through A and B that bulges Bulge units away from the chord -
  how two loose line ends get joined by a curve. }
function ArcFromChord(const A, B: TP3; Bulge: Double; Pl: TPlane;
  out C: TP3; out R, A0, Sweep: Double): Boolean;

function P3(X, Y, Z: Double): TP3; inline;
function Dist(const A, B: TP3): Double; inline;
{ the point T of the way from A to B }
function Lerp3(const A, B: TP3; T: Double): TP3;
function SamePt(const A, B: TP3; Tol: Double): Boolean; inline;
{ Do these two segments overlap over a run, not just touch or cross?  Decides
  whether an edge holds up a face and whether a line traces over another. }
function SharesRun(const P1, Q1, P2, Q2: TP3): Boolean;

{ --- projection ---------------------------------------------------------- }
function SameProjector(const A, B: TProjector): Boolean;
function Project(const V: TProjector; const P: TP3): TPointF;

{ The same projection with the camera worked out once.  Project redoes the
  trigonometry on every call, which dominates a snap search; ProjectAt is the
  same arithmetic with the constants lifted out of the loop. }
type
  TProjCache = record
    Kind: TViewKind;
    Ppu, OX, OY: Double;
    R, U: TP3;
  end;

procedure BeginProject(const V: TProjector; out C: TProjCache);
function ProjectAt(const C: TProjCache; const P: TP3): TPointF; inline;

{ Screen point back to the model, on the working plane through Base.  In PLAN
  that is simply the XY plane; in ISO the plane is picked by Pl. }
function Unproject(const V: TProjector; SX, SY: Double; Pl: TPlane;
  const Base: TP3): TP3;

{ Which plane is the mouse moving across?  The one that explains the drag
  with the least travel in the model, so dragging up in iso stands a rectangle
  up and dragging across lays it flat.  Keep, the plane in force now, wins
  ties and anything closer than Bias, so a shape does not flip while the hand
  shakes. }
function PlaneByDrag(const V: TProjector; const Anchor: TP3;
  SX, SY: Double; Keep: TPlane; Bias: Double = 0.8): TPlane;

{ A point on one of the three model axes near the cursor - EdgeSnap without
  the ends.  Axis is 0, 1 or 2 for X, Y or Z. }
function AxisSnap(const V: TProjector; SX, SY, TolPx: Double;
  out P: TP3; out Axis: Integer): Boolean;

{ The six axis directions, and how they read on screen in the given view. }
function AxisDir(Index: Integer): TP3;
function AxisName(Index: Integer): string;

{ Lay out a dimension.  Off is a vector in the model, not pixels, so the
  dimension keeps its distance as you zoom and stays put as you orbit.  False
  when the two points are too close together on screen. }
function DimGeometry(const V: TProjector; const A, B, Off: TP3;
  U: TUnitSystem; out G: TDimGeom; const Note: string = ''): Boolean;

{ The offset, square to AB, that puts a dimension's line under the pointer at
  (MX, MY).  Its direction is whichever allowed one (axes square to AB, level
  and upright, or Extra, the faces on the edge) points most nearly from AB's
  middle to the pointer.  Prefer, the last choice, is kept unless another is
  clearly better so it does not flicker.  Zero when AB has no screen length. }
function DimOffsetAt(const V: TProjector; const A, B: TP3; MX, MY: Double;
  const Extra: array of TP3; const Prefer: TP3): TP3;

{ Where the top-left of a dimension's TW x TH text goes.  The whole box is
  cleared along the normal, or half the figure sits on the line in iso.  From
  the middle of a W x H box to its edge along (nx, ny) is (|nx|W + |ny|H) / 2. }
function DimTextTopLeft(const G: TDimGeom; TW, TH: Integer;
  Gap: Double = 8): TPoint;

{ Where plFree lies: a point on it and the way it faces.  Set from the face
  under the cursor, read back by everything that draws in a plane. }
procedure SetFreePlane(const Org, Normal: TP3);
procedure GetFreePlane(out Org, U, V, N: TP3);
{ The two directions of a plane facing Nm, chosen the same way every time. }
procedure AxesFromNormal(const Nm: TP3; out AU, AV: TP3);
{ The two directions of one of the working planes. }
procedure PlaneAxes(Pl: TPlane; out AU, AV: TP3);

{ A point on a circle of radius R about C, at Ang radians, in plane Pl.  The
  second form is for a stored shape, which carries its own normal. }
function ArcPoint(const C: TP3; R, Ang: Double; Pl: TPlane): TP3;
function ArcPoint(const C: TP3; R, Ang: Double; Pl: TPlane;
  const Nm: TP3): TP3;

{ Unit vectors of the view: screen right, screen up, and the direction the
  camera looks along (used to sort faces back to front). }
function ViewRight(const V: TProjector): TP3;
function ViewUp(const V: TProjector): TP3;
function ViewDir(const V: TProjector): TP3;

{ point and vector arithmetic }
function Add3(const A, B: TP3): TP3; inline;
function Sub3(const A, B: TP3): TP3; inline;
function Mul3(const A: TP3; K: Double): TP3; inline;
function Len3(const A: TP3): Double; inline;
function Cross3(const A, B: TP3): TP3;
function Dot3(const A, B: TP3): Double; inline;
function Norm3(const A: TP3): TP3;

{ What the tape leaves behind, by where it was pulled from: off an edge, a
  guide parallel to it through the landing point; along an edge, a point
  only; from a corner or mid air, a line across the run. }
type
  TTapeGuide = (tgPointOnly, tgAlongEdge, tgAcrossRun);

function TapeGuide(HaveEdge: Boolean; const EdgeDir, A, B, PlaneNm: TP3;
  out Dir: TP3): TTapeGuide;

{ The sagitta (bulge) of the arc that leaves A along Dir and ends at B -
  SketchUp's tangent arc.  The chord-to-tangent angle is half the arc's angle,
  so it is (chord / 2) * tan(angle / 2); the sign says which side.  False when
  the tangent runs along the chord or out of the plane. }
function TangentSagitta(const A, B, Dir: TP3; Pl: TPlane;
  out Bulge: Double): Boolean;


{ An equidistant copy of a closed loop in its own plane - a duct wall, a
  flange.  Each edge shifts sideways by D and the shifted edges are extended
  to meet, which keeps the corners sharp.  D is positive outward, judged from
  how the loop winds about Normal.  A loop that eats itself is left for the
  region engine to split. }
function OffsetLoop(const Loop: TP3Array; const Normal: TP3; D: Double;
  Tidy: Boolean = True): TP3Array;

{ The two in-plane coordinates of a model point. }
procedure PlaneCoords(Pl: TPlane; const P: TP3; out U, W: Double);

{ The stretch of an infinite line that crosses a W x H box: the parameters
  where it enters and leaves, False if it misses.  Lets the axes run off the
  window wherever you pan. }
function ClipToBox(PX, PY, DX, DY, W, H: Double; out T0, T1: Double): Boolean;

const
  ISO_COS = 0.86602540378443865;   // cos 30
  ISO_SIN = 0.5;                   // sin 30

implementation

const
  { SketchUp's default front material, near enough. }
  FACE_MATERIAL: TPix = (B: $F6; G: $FA; R: $FA; A: 255);
  { The back of a face, in SketchUp's pale blue, so a solid built inside out
    is caught on sight. }
  FACE_BACK: TPix = (B: $DC; G: $C4; R: $A8; A: 255);
  { The lamp.  Ambient and diffuse are SketchUp's default dark and light
    settings, 45 and 80; a face turned well away comes out near 72 percent. }
  LAMP_AMBIENT = 0.45;
  LAMP_DIFFUSE = 0.80;
  LAMP_UP      = 0.25;
  LAMP_LEFT    = 0.20;
  { A guide point, in amber.  Deliberately placed and deliberately findable. }
  GUIDE_POINT: TPix = (B: $10; G: $B0; R: $F0; A: 255);
  { how finely a line lying on a face is chopped up when working out which
    stretches of it are hidden }
  LINE_STEPS = 32;

function UnitName(U: TUnitSystem): string;
begin
  if U = usImperial then Result := 'FEET' else Result := 'METRIC';
end;

function ScaleTable(U: TUnitSystem; I: Integer): TDrawScale;
begin
  I := EnsureRange(I, 0, SCALE_COUNT - 1);
  if U = usImperial then
    Result := IMPERIAL_SCALES[I]
  else
    Result := METRIC_SCALES[I];
end;

function SnapValue(U: TUnitSystem; I: Integer): Double;
begin
  I := EnsureRange(I, 0, SNAP_COUNT - 1);
  if U = usImperial then Result := IMPERIAL_SNAPS[I] else Result := METRIC_SNAPS[I];
end;

function SnapName(U: TUnitSystem; I: Integer): string;
begin
  I := EnsureRange(I, 0, SNAP_COUNT - 1);
  if U = usImperial then
    Result := IMPERIAL_SNAP_NAMES[I]
  else
    Result := METRIC_SNAP_NAMES[I];
end;

function PixelsPerUnit(U: TUnitSystem; const Sc: TDrawScale; DPI: Double): Double;
begin
  if U = usImperial then
    { Sc.Paper is paper inches per foot, DPI is pixels per paper inch }
    Result := Sc.Paper * DPI
  else
    { Sc.Paper is paper meters per meter }
    Result := Sc.Paper * (DPI / 0.0254);
  if Result < 0.5 then Result := 0.5;
end;

{ ---------------------------------------------------------------------- }
{ formatting                                                              }
{ ---------------------------------------------------------------------- }

{ How finely an imperial length is written, and what the last field of a
  dashed entry counts in.  One setting for both so a typed number never shows
  up as a different one.  It governs display only; the model keeps the exact
  value. }
var
  GLenDenom: Integer = 16;

procedure SetLenDenom(D: Integer);
begin
  { powers of two up to a sixty-fourth, or hundredths for the shops that
    work that way }
  if D in [2, 4, 8, 16, 32, 64, 100] then GLenDenom := D;
end;

function LenDenom: Integer;
begin
  Result := GLenDenom;
end;

{ Reduce PARTS/LenDenom to the tidiest fraction, e.g. 8/16 -> 1/2. }
function FractionText(Parts: Integer): string;
var
  N, D: Integer;
begin
  N := Parts;
  D := GLenDenom;
  while (N > 0) and (N mod 2 = 0) and (D mod 2 = 0) do
  begin
    N := N div 2;
    D := D div 2;
  end;
  if N = 0 then
    Result := ''
  else
    Result := Format('%d/%d', [N, D]);
end;

function FormatLen(V: Double; U: TUnitSystem): string;
var
  Neg: Boolean;
  TotalSix, Ft, Inch, Six: Int64;
  Frac: string;
begin
  Neg := V < 0;
  V := Abs(V);

  if U = usMetric then
  begin
    if V < 1 then
      Result := Format('%.0f mm', [V * 1000])
    else
      Result := Format('%.3f m', [V]);
  end
  else
  begin
    { Rounded to the drawing's precision for display only; the model keeps
      the exact number. }
    TotalSix := Round(V * 12 * GLenDenom);
    Ft := TotalSix div (12 * GLenDenom);
    TotalSix := TotalSix - Ft * 12 * GLenDenom;
    Inch := TotalSix div GLenDenom;
    Six := TotalSix - Inch * GLenDenom;
    Frac := FractionText(Six);

    if Frac <> '' then
      Result := Format('%d''-%d %s"', [Ft, Inch, Frac])
    else
      Result := Format('%d''-%d"', [Ft, Inch]);
  end;

  if Neg then
    Result := '-' + Result;
end;

function FormatArea(V: Double; U: TUnitSystem): string;
begin
  if U = usMetric then
    Result := Format('%.2f m2', [V])
  else
    Result := Format('%.1f sq ft', [V]);
end;

{ ---------------------------------------------------------------------- }
{ parsing                                                                 }
{ ---------------------------------------------------------------------- }

{ Accepts a plain number, or a number with a fraction: 6, 6.5, 6 1/2, 6-1/2 }
function ParseMixed(S: string; out V: Double): Boolean;
var
  P, Q: Integer;
  Whole, Num, Den: Double;
  FracPart: string;
begin
  Result := False;
  V := 0;
  S := Trim(S);
  if S = '' then Exit;

  { split off a trailing fraction }
  FracPart := '';
  P := Pos('/', S);
  if P > 0 then
  begin
    Q := P - 1;
    while (Q > 0) and (S[Q] in ['0'..'9']) do Dec(Q);
    FracPart := Copy(S, Q + 1, MaxInt);
    S := Trim(Copy(S, 1, Q));
    while (S <> '') and (S[Length(S)] in [' ', '-']) do
      SetLength(S, Length(S) - 1);
  end;

  Whole := 0;
  if S <> '' then
    if not TryStrToFloat(S, Whole, DotFS) then Exit;

  if FracPart <> '' then
  begin
    P := Pos('/', FracPart);
    if not TryStrToFloat(Copy(FracPart, 1, P - 1), Num, DotFS) then Exit;
    if not TryStrToFloat(Copy(FracPart, P + 1, MaxInt), Den, DotFS) then Exit;
    if Den = 0 then Exit;
    Whole := Whole + Num / Den;
  end;

  V := Whole;
  Result := True;
end;

{ Turn what the user typed into one length in world units; ParseLen, below,
  reads sums of them.
  Imperial:  12'6"   12' 6   12-6   12'   6"   150"   12   6 1/2"
             a bare number is feet; anything after a ' or ending in " is inches
  Metric:    3.5   3.5m   350cm   3500mm   (bare number is meters) }
function ParseLenPlain(const S: string; U: TUnitSystem; out V: Double): Boolean;
var
  T, FtPart, InPart: string;
  Parts: array[0..2] of string;
  P, NDash: Integer;
  Neg: Boolean;
  A, B, C: Double;
begin
  Result := False;
  V := 0;
  T := Trim(S);
  if T = '' then Exit;

  if U = usMetric then
  begin
    T := LowerCase(T);
    if (Length(T) > 2) and (Copy(T, Length(T) - 1, 2) = 'mm') then
    begin
      if not ParseMixed(Copy(T, 1, Length(T) - 2), A) then Exit;
      V := A / 1000;
    end
    else if (Length(T) > 2) and (Copy(T, Length(T) - 1, 2) = 'cm') then
    begin
      if not ParseMixed(Copy(T, 1, Length(T) - 2), A) then Exit;
      V := A / 100;
    end
    else if (Length(T) > 1) and (T[Length(T)] = 'm') then
    begin
      if not ParseMixed(Copy(T, 1, Length(T) - 1), A) then Exit;
      V := A;
    end
    else
    begin
      if not ParseMixed(T, A) then Exit;
      V := A;
    end;
    Result := True;
    Exit;
  end;

  { imperial }
  if (T <> '') and (T[Length(T)] = '"') then
    SetLength(T, Length(T) - 1);
  T := Trim(T);
  if T = '' then Exit;

  P := Pos('''', T);
  if P > 0 then
  begin
    FtPart := Trim(Copy(T, 1, P - 1));
    InPart := Trim(Copy(T, P + 1, MaxInt));
    while (InPart <> '') and (InPart[1] = '-') do
      Delete(InPart, 1, 1);
    A := 0;
    B := 0;
    if (FtPart <> '') and not ParseMixed(FtPart, A) then Exit;
    if (InPart <> '') and not ParseMixed(InPart, B) then Exit;
    V := A + B / 12;
    Result := True;
    Exit;
  end;

  { it ended with a double-quote, so it was inches all along }
  if (Length(S) > 0) and (Trim(S)[Length(Trim(S))] = '"') then
  begin
    if not ParseMixed(T, A) then Exit;
    V := A / 12;
    Result := True;
    Exit;
  end;

  { Truss notation: feet, inches and sixteenths, all whole numbers, typed from
    the number pad.  6-8-15 is six foot eight and fifteen sixteenths; 0-8-8 is
    eight and a half inches.  The last field counts in the drawing's
    precision, and a field at or above the denominator is refused rather than
    guessed at. }
  if (Pos('/', T) = 0) and (Pos('''', T) = 0) then
  begin
    NDash := 0;
    Parts[0] := '';
    Parts[1] := '';
    Parts[2] := '';
    Neg := (T[1] = '-');
    for P := 1 + Ord(Neg) to Length(T) do
      if T[P] = '-' then
      begin
        Inc(NDash);
        if NDash > 2 then Break;
      end
      else
        Parts[NDash] := Parts[NDash] + T[P];

    if (NDash = 2) and (Parts[0] <> '') and (Parts[1] <> '') and
       (Parts[2] <> '') and ParseMixed(Parts[0], A) and
       ParseMixed(Parts[1], B) and ParseMixed(Parts[2], C) and
       (B >= 0) and (B < 12) and (C >= 0) and (C < GLenDenom) then
    begin
      V := Abs(A) + B / 12 + C / (GLenDenom * 12);
      if Neg then V := -V;
      Result := True;
      Exit;
    end;
  end;

  { "12-6" and "12 6" mean twelve foot six.  A dash may carry a fraction after
    it (6-8 1/2), but a space cannot: "3 1/2" is three and a half feet. }
  P := Pos('-', T);
  if P > 1 then
  begin
    if not ParseMixed(Copy(T, 1, P - 1), A) then Exit;
    if not ParseMixed(Copy(T, P + 1, MaxInt), B) then Exit;
    V := A + B / 12;
    Result := True;
    Exit;
  end;

  P := Pos(' ', T);
  if (P > 1) and (Pos('/', T) = 0) then
  begin
    if not ParseMixed(Copy(T, 1, P - 1), A) then Exit;
    if not ParseMixed(Copy(T, P + 1, MaxInt), B) then Exit;
    V := A + B / 12;
    Result := True;
    Exit;
  end;

  if not ParseMixed(T, A) then Exit;
  V := A;
  Result := True;
end;

{ A little arithmetic in a typed length: 8' + 8", 8'17" / 2, 10' - 3'4",
  (8' + 4") * 2.  A minus is two dashes, a dash with spaces, or one no length
  could hold (after an inch mark, or between feet and feet); a slash between
  digits is a fraction.  A length times or over a number is a length; a bare
  number in a sum is feet.  Without operators it reads as a plain length. }

const
  QUOTE1 = #39;

type
  TLenVal = record
    V: Double;
    Len: Boolean;     { a length, not a plain number }
  end;

function ParseLen(const S: string; U: TUnitSystem; out V: Double): Boolean;
var
  T: string;
  Pos_: Integer;
  Bad: Boolean;

  { is the slash at I division, not a fraction's? }
  function DivSlash(I: Integer): Boolean;
  begin
    Result := not ((I > 1) and (I < Length(T)) and (T[I - 1] in ['0'..'9']) and (T[I + 1] in ['0'..'9']));
  end;

  { A spaced dash between a foot mark and inches alone - 6' - 8" - is six foot
    eight, not a subtraction.  To take inches off write 10' - 0'8" or
    10' - (8"). }
  function WrittenFeetInches(I: Integer): Boolean;
  var
    J: Integer;
    W: string;
  begin
    Result := False;
    J := I - 1;
    while (J > 0) and (T[J] = ' ') do Dec(J);
    if (J < 1) or (T[J] <> QUOTE1) then Exit;
    W := '';
    J := I + 1;
    while (J <= Length(T)) and not (T[J] in ['+', '*', '(', ')']) and
          not ((T[J] = '-') and (J > 1) and (T[J - 1] = ' ')) do
    begin
      W := W + T[J];
      Inc(J);
    end;
    W := Trim(W);
    Result := (W <> '') and (Pos(QUOTE1, W) = 0) and (W[Length(W)] = '"');
  end;

  { after the dash at I, up to the next sign: a foot mark? }
  function FeetAfter(I: Integer): Boolean;
  var
    J: Integer;
  begin
    J := I + 1;
    while (J <= Length(T)) and not (T[J] in ['+', '*', '(', ')', '-']) do
    begin
      if T[J] = QUOTE1 then Exit(True);
      Inc(J);
    end;
    Result := False;
  end;

  { A dash is a minus with a space either side (except 6' - 8"), or unspaced
    straight after an inch mark (8'6"-3") or after a foot mark with feet on
    the other side (10'-3'4").  6'-8" and 6-8-15 stay lengths. }
  function IsOperator(I: Integer): Boolean;
  begin
    case T[I] of
      '+', '*', '(', ')': Result := True;
      '/': Result := DivSlash(I);
      { two dashes are always a minus - truss notation never has two in
        a row, and both are on the number pad: 6-8-0--2-4-0 }
      '-': Result := (I > 1) and (I < Length(T)) and
             ((T[I + 1] = '-') or
              ((T[I - 1] = ' ') and (T[I + 1] = ' ') and not WrittenFeetInches(I)) or
              (T[I - 1] = '"') or
              ((T[I - 1] = QUOTE1) and FeetAfter(I)));
    else Result := False;
    end;
  end;

  procedure Skip;
  begin
    while (Pos_ <= Length(T)) and (T[Pos_] = ' ') do Inc(Pos_);
  end;

  function Expr: TLenVal; forward;

  { a length or a plain number as typed, up to the next operator }
  function Atom: TLenVal;
  var
    Start: Integer;
    W: string;
  begin
    Result.V := 0; Result.Len := False;
    Skip;
    if Pos_ > Length(T) then begin Bad := True; Exit; end;
    if T[Pos_] = '(' then
    begin
      Inc(Pos_);
      Result := Expr;
      Skip;
      if (Pos_ > Length(T)) or (T[Pos_] <> ')') then begin Bad := True; Exit; end;
      Inc(Pos_);
      Exit;
    end;
    Start := Pos_;
    while (Pos_ <= Length(T)) and not IsOperator(Pos_) do Inc(Pos_);
    W := Trim(Copy(T, Start, Pos_ - Start));
    if W = '' then begin Bad := True; Exit; end;
    { a plain number - no mark, no dash, no space between feet and
      inches - is a number; anything else a length }
    if (Pos('''', W) = 0) and (Pos('"', W) = 0) and ((Pos('-', W) = 0) or (W[1] = '-')) and
       ((Pos(' ', W) = 0) or (Pos('/', W) > 0)) and ParseMixed(W, Result.V) then
      Exit;
    Result.Len := True;
    if not ParseLenPlain(W, U, Result.V) then Bad := True;
  end;

  function Term: TLenVal;
  var
    B: TLenVal;
    Op: Char;
  begin
    Result := Atom;
    repeat
      Skip;
      if Bad or (Pos_ > Length(T)) or not (T[Pos_] in ['*', '/']) then Exit;
      Op := T[Pos_];
      Inc(Pos_);
      B := Atom;
      if Bad then Exit;
      if Op = '*' then
      begin
        { a length times a length is an area, not a length }
        if Result.Len and B.Len then begin Bad := True; Exit; end;
        Result.V := Result.V * B.V;
        Result.Len := Result.Len or B.Len;
      end
      else
      begin
        if B.Len or (Abs(B.V) < 1E-12) then begin Bad := True; Exit; end;
        Result.V := Result.V / B.V;
      end;
    until False;
  end;

  function Expr: TLenVal;
  var
    B: TLenVal;
    Op: Char;
  begin
    Result := Term;
    repeat
      Skip;
      if Bad or (Pos_ > Length(T)) or not ((T[Pos_] = '+') or ((T[Pos_] = '-') and IsOperator(Pos_))) then Exit;
      Op := T[Pos_];
      Inc(Pos_);
      { the second dash of a double one }
      if (Op = '-') and (Pos_ <= Length(T)) and (T[Pos_] = '-') then Inc(Pos_);
      B := Term;
      if Bad then Exit;
      { a plain number in a sum is a bare length: feet, or meters }
      if Op = '+' then Result.V := Result.V + B.V else Result.V := Result.V - B.V;
      Result.Len := True;
    until False;
  end;

var
  I: Integer;
  Any: Boolean;
  R: TLenVal;
begin
  T := Trim(S);
  Any := False;
  for I := 1 to Length(T) do
    if IsOperator(I) then begin Any := True; Break; end;
  if not Any then Exit(ParseLenPlain(S, U, V));
  V := 0;
  Pos_ := 1; Bad := False;
  R := Expr;
  Skip;
  Result := not Bad and (Pos_ > Length(T));
  if Result then V := R.V;
end;

function ParseTriple(const S: string; U: TUnitSystem;
  out X, Y, Z: Double): Integer;
var
  Body, Part: string;
  I, N: Integer;
  V: array[0..2] of Double;
begin
  X := 0; Y := 0; Z := 0;
  Result := 0;
  Body := Trim(S);
  if Length(Body) < 2 then Exit;
  if Body[1] in ['[', '<'] then Delete(Body, 1, 1);
  if (Body <> '') and (Body[Length(Body)] in [']', '>']) then
    Delete(Body, Length(Body), 1);

  N := 0;
  V[0] := 0; V[1] := 0; V[2] := 0;
  while (Body <> '') and (N < 3) do
  begin
    I := Pos(',', Body);
    if I = 0 then I := Pos(';', Body);
    if I = 0 then
    begin
      Part := Body;
      Body := '';
    end
    else
    begin
      Part := Copy(Body, 1, I - 1);
      Delete(Body, 1, I);
    end;
    Part := Trim(Part);
    if Part = '' then
      Inc(N)                           // an empty field leaves that axis alone
    else if ParseLen(Part, U, V[N]) then
      Inc(N)
    else
      Exit;                            // a field we cannot read spoils the lot
  end;
  X := V[0]; Y := V[1]; Z := V[2];
  Result := N;
end;

{ A round length that comes out between MinPx and MaxPx on screen.  The
  tables cover the whole zoom range, in steps that land on inch fractions,
  inches and feet. }
function NiceBarLength(Ppu: Double; MinPx, MaxPx: Double; U: TUnitSystem): Double;
const
  N_STEP = 16;
  { Feet, with exact inch fractions at the short end so the label never reads
    0'-0". }
  IMP: array[0..N_STEP] of Double =
    (1/192, 1/96, 1/48, 1/24, 1/12, 0.25, 0.5,
     1, 2, 5, 10, 20, 50, 100, 200, 500, 1000);
  MET: array[0..N_STEP] of Double =
    (0.0005, 0.001, 0.0025, 0.005, 0.01, 0.025, 0.05,
     0.1, 0.25, 0.5, 1, 2, 5, 10, 20, 50, 100);
var
  I: Integer;
  V: Double;
begin
  Result := 1;
  for I := 0 to N_STEP do
  begin
    if U = usImperial then V := IMP[I] else V := MET[I];
    Result := V;
    if V * Ppu >= MinPx then Exit;
  end;
end;

{ ---------------------------------------------------------------------- }
{ geometry and projection                                                  }
{ ---------------------------------------------------------------------- }

function P3(X, Y, Z: Double): TP3;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Z := Z;
end;

function Dist(const A, B: TP3): Double;
begin
  Result := Sqrt(Sqr(B.X - A.X) + Sqr(B.Y - A.Y) + Sqr(B.Z - A.Z));
end;

function SamePt(const A, B: TP3; Tol: Double): Boolean;
begin
  Result := Dist(A, B) <= Tol;
end;

function Add3(const A, B: TP3): TP3;
begin
  Result := P3(A.X + B.X, A.Y + B.Y, A.Z + B.Z);
end;

function Sub3(const A, B: TP3): TP3;
begin
  Result := P3(A.X - B.X, A.Y - B.Y, A.Z - B.Z);
end;

function Mul3(const A: TP3; K: Double): TP3;
begin
  Result := P3(A.X * K, A.Y * K, A.Z * K);
end;

function Len3(const A: TP3): Double;
begin
  Result := Sqrt(A.X * A.X + A.Y * A.Y + A.Z * A.Z);
end;

function Cross3(const A, B: TP3): TP3;
begin
  Result.X := A.Y * B.Z - A.Z * B.Y;
  Result.Y := A.Z * B.X - A.X * B.Z;
  Result.Z := A.X * B.Y - A.Y * B.X;
end;

function Dot3(const A, B: TP3): Double;
begin
  Result := A.X * B.X + A.Y * B.Y + A.Z * B.Z;
end;

function Norm3(const A: TP3): TP3;
var
  L: Double;
begin
  L := Sqrt(A.X * A.X + A.Y * A.Y + A.Z * A.Z);
  if L < 1E-12 then
    Result := P3(0, 0, 1)
  else
    Result := P3(A.X / L, A.Y / L, A.Z / L);
end;

function ClipToBox(PX, PY, DX, DY, W, H: Double; out T0, T1: Double): Boolean;

  { Liang-Barsky, one edge at a time: the line runs P + T*D, and each edge
    says either "no T at all" or trims one end of the range. }
  function Edge(Num, Den: Double): Boolean;
  var
    T: Double;
  begin
    Result := True;
    if Abs(Den) < 1E-12 then
    begin
      { Parallel to this edge.  Num is how far inside it the line sits, so
        it is on the paper when that is not negative. }
      Result := Num >= 0;
      Exit;
    end;
    T := Num / Den;
    if Den < 0 then
    begin
      if T > T1 then Exit(False);
      if T > T0 then T0 := T;
    end
    else
    begin
      if T < T0 then Exit(False);
      if T < T1 then T1 := T;
    end;
  end;

begin
  T0 := -1E30;
  T1 := 1E30;
  { Num is the distance inside the edge, Den the rate the line crosses it:
    negative coming in, positive going out.  Swapping them clips every line
    to nothing. }
  Result := Edge(PX, -DX) and Edge(W - PX, DX) and
            Edge(PY, -DY) and Edge(H - PY, DY) and (T0 <= T1);
end;

{ A turntable camera: Az spins about the world Z axis, El tilts up from the
  horizon.  Z is up in the model, which is what push/pull assumes. }
function ViewRight(const V: TProjector): TP3;
begin
  case V.Kind of
    vkOrbit: Result := P3(-Sin(V.Az), Cos(V.Az), 0);
    vkIso:   Result := P3(ISO_COS, ISO_COS, 0);
  else
    Result := P3(1, 0, 0);
  end;
end;

function ViewUp(const V: TProjector): TP3;
begin
  case V.Kind of
    vkOrbit: Result := P3(-Sin(V.El) * Cos(V.Az), -Sin(V.El) * Sin(V.Az), Cos(V.El));
    vkIso:   Result := P3(-ISO_SIN, ISO_SIN, 1);
  else
    Result := P3(0, 1, 0);
  end;
end;

{ The direction out of the screen, toward the viewer.  For iso that is
  (1,-1,1), the corner the free camera and SketchUp both start on. }
function ViewDir(const V: TProjector): TP3;
begin
  case V.Kind of
    vkOrbit: Result := P3(Cos(V.El) * Cos(V.Az), Cos(V.El) * Sin(V.Az), Sin(V.El));
    vkIso:   Result := Norm3(P3(1, -1, 1));
  else
    Result := P3(0, 0, 1);
  end;
end;

function SameProjector(const A, B: TProjector): Boolean;
begin
  Result := (A.Kind = B.Kind) and (A.Ppu = B.Ppu) and (A.OX = B.OX) and
            (A.OY = B.OY) and (A.Az = B.Az) and (A.El = B.El);
end;

procedure BeginProject(const V: TProjector; out C: TProjCache);
begin
  C.Kind := V.Kind;
  C.Ppu := V.Ppu;
  C.OX := V.OX;
  C.OY := V.OY;
  C.R := ViewRight(V);
  C.U := ViewUp(V);
end;

function ProjectAt(const C: TProjCache; const P: TP3): TPointF;
begin
  if C.Kind = vkOrbit then
  begin
    Result.X := C.OX + (P.X * C.R.X + P.Y * C.R.Y + P.Z * C.R.Z) * C.Ppu;
    Result.Y := C.OY - (P.X * C.U.X + P.Y * C.U.Y + P.Z * C.U.Z) * C.Ppu;
    Exit;
  end;
  if C.Kind = vkIso then
  begin
    Result.X := C.OX + (P.X + P.Y) * ISO_COS * C.Ppu;
    Result.Y := C.OY - ((P.Y - P.X) * ISO_SIN + P.Z) * C.Ppu;
  end
  else
  begin
    Result.X := C.OX + P.X * C.Ppu;
    Result.Y := C.OY - P.Y * C.Ppu;
  end;
end;

{ PLAN looks straight down Z.  ISO is the 30 degree isometric from the same
  corner as the free camera: +X runs down-right toward you, +Y up-right away,
  +Z straight up.  ISO and 3D must agree on which way each axis runs. }
function Project(const V: TProjector; const P: TP3): TPointF;
var
  R, U: TP3;
begin
  if V.Kind = vkOrbit then
  begin
    R := ViewRight(V);
    U := ViewUp(V);
    Result.X := V.OX + Dot3(P, R) * V.Ppu;
    Result.Y := V.OY - Dot3(P, U) * V.Ppu;
    Exit;
  end;
  if V.Kind = vkIso then
  begin
    Result.X := V.OX + (P.X + P.Y) * ISO_COS * V.Ppu;
    Result.Y := V.OY - ((P.Y - P.X) * ISO_SIN + P.Z) * V.Ppu;
  end
  else
  begin
    Result.X := V.OX + P.X * V.Ppu;
    Result.Y := V.OY - P.Y * V.Ppu;
  end;
end;

{ Two screen equations, three unknowns, so the working plane pins one of
  them; the remaining 2x2 system is solved directly. }
procedure UnprojectOrbit(const V: TProjector; SX, SY: Double; Pl: TPlane;
  const Base: TP3; out Res: TP3);
var
  R, U: TP3;
  A11, A12, A21, A22, B1, B2, Det, S, T, Scale: Double;
begin
  Res := Base;
  R := ViewRight(V);
  U := ViewUp(V);
  B1 := (SX - V.OX) / V.Ppu;
  B2 := (V.OY - SY) / V.Ppu;

  case Pl of
    plXY:
      begin
        A11 := R.X; A12 := R.Y; B1 := B1 - R.Z * Base.Z;
        A21 := U.X; A22 := U.Y; B2 := B2 - U.Z * Base.Z;
      end;
    plXZ:
      begin
        A11 := R.X; A12 := R.Z; B1 := B1 - R.Y * Base.Y;
        A21 := U.X; A22 := U.Z; B2 := B2 - U.Y * Base.Y;
      end;
  else
    begin
      A11 := R.Y; A12 := R.Z; B1 := B1 - R.X * Base.X;
      A21 := U.Y; A22 := U.Z; B2 := B2 - U.X * Base.X;
    end;
  end;

  { Too nearly edge-on gives an answer miles away that looks like a real one.
    The determinant is judged against the size of the matrix; below a
    thousandth of it, Base stands. }
  Det := A11 * A22 - A12 * A21;
  Scale := Max(Abs(A11), Max(Abs(A12), Max(Abs(A21), Abs(A22))));
  if Abs(Det) < 1E-3 * Max(Scale * Scale, 1E-12) then Exit;
  S := (B1 * A22 - A12 * B2) / Det;
  T := (A11 * B2 - B1 * A21) / Det;

  case Pl of
    plXY: begin Res.X := S; Res.Y := T; end;
    plXZ: begin Res.X := S; Res.Z := T; end;
  else
    begin Res.Y := S; Res.Z := T; end;
  end;
end;

{ The free plane.  Held here because there is only ever one, and TPlane is
  passed by value through a dozen calls. }
var
  GFreeOrg: TP3 = (X: 0; Y: 0; Z: 0);
  GFreeN: TP3 = (X: 0; Y: 0; Z: 1);
  GFreeU: TP3 = (X: 1; Y: 0; Z: 0);
  GFreeV: TP3 = (X: 0; Y: 1; Z: 0);

{ Where the cursor meets an arbitrary plane, in any view.  The projection is
  linear, so where the origin and unit vectors land gives two equations and
  the plane is the third. }
function UnprojectPlane(const V: TProjector; SX, SY: Double;
  const Org, N: TP3; const Base: TP3): TP3;
var
  P0, PX, PY, PZ: TPointF;
  A: array[0..2, 0..2] of Double;
  B: array[0..2] of Double;
  Det, D0, D1, D2, Scale, R0, R1, R2: Double;
begin
  Result := Base;
  P0 := Project(V, P3(0, 0, 0));
  PX := Project(V, P3(1, 0, 0));
  PY := Project(V, P3(0, 1, 0));
  PZ := Project(V, P3(0, 0, 1));

  A[0, 0] := PX.X - P0.X;  A[0, 1] := PY.X - P0.X;  A[0, 2] := PZ.X - P0.X;
  A[1, 0] := PX.Y - P0.Y;  A[1, 1] := PY.Y - P0.Y;  A[1, 2] := PZ.Y - P0.Y;
  A[2, 0] := N.X;          A[2, 1] := N.Y;          A[2, 2] := N.Z;

  B[0] := SX - P0.X;
  B[1] := SY - P0.Y;
  B[2] := N.X * Org.X + N.Y * Org.Y + N.Z * Org.Z;

  Det := A[0,0] * (A[1,1] * A[2,2] - A[1,2] * A[2,1])
       - A[0,1] * (A[1,0] * A[2,2] - A[1,2] * A[2,0])
       + A[0,2] * (A[1,0] * A[2,1] - A[1,1] * A[2,0]);

  { Edge-on there is no crossing worth having.  Judge against all three rows:
    the first two are pixels per foot and the third a unit normal, so the
    first row alone lets a hopeless solve through and a circle on a leaning
    roof leaps to an absurd size. }
  R0 := Sqrt(Sqr(A[0,0]) + Sqr(A[0,1]) + Sqr(A[0,2]));
  R1 := Sqrt(Sqr(A[1,0]) + Sqr(A[1,1]) + Sqr(A[1,2]));
  R2 := Sqrt(Sqr(A[2,0]) + Sqr(A[2,1]) + Sqr(A[2,2]));
  Scale := R0 * R1 * R2;
  if (Scale < 1E-12) or (Abs(Det) < 1E-3 * Scale) then Exit;

  D0 := B[0]    * (A[1,1] * A[2,2] - A[1,2] * A[2,1])
      - A[0,1]  * (B[1]   * A[2,2] - A[1,2] * B[2])
      + A[0,2]  * (B[1]   * A[2,1] - A[1,1] * B[2]);
  D1 := A[0,0]  * (B[1]   * A[2,2] - A[1,2] * B[2])
      - B[0]    * (A[1,0] * A[2,2] - A[1,2] * A[2,0])
      + A[0,2]  * (A[1,0] * B[2]   - B[1]   * A[2,0]);
  D2 := A[0,0]  * (A[1,1] * B[2]   - B[1]   * A[2,1])
      - A[0,1]  * (A[1,0] * B[2]   - B[1]   * A[2,0])
      + B[0]    * (A[1,0] * A[2,1] - A[1,1] * A[2,0]);

  Result := P3(D0 / Det, D1 / Det, D2 / Det);
end;

function Unproject(const V: TProjector; SX, SY: Double; Pl: TPlane;
  const Base: TP3): TP3;
var
  U, W: Double;
begin
  Result := Base;
  if Pl = plFree then
    Exit(UnprojectPlane(V, SX, SY, GFreeOrg, GFreeN, Base));
  if V.Kind = vkPlan then
  begin
    Result.X := (SX - V.OX) / V.Ppu;
    Result.Y := (V.OY - SY) / V.Ppu;
    Exit;
  end;

  if V.Kind = vkOrbit then
  begin
    UnprojectOrbit(V, SX, SY, Pl, Base, Result);
    Exit;
  end;

  { ISO.  Two screen equations, so one of the three model axes has to be
    pinned - that is what the working plane is for. }
  U := (SX - V.OX) / (V.Ppu * ISO_COS);          // = X + Y
  W := (V.OY - SY) / V.Ppu;                      // = (Y-X)*sin + Z

  case Pl of
    plXY:
      begin
        Result.Z := Base.Z;
        Result.Y := (U + (W - Base.Z) / ISO_SIN) / 2;
        Result.X := (U - (W - Base.Z) / ISO_SIN) / 2;
      end;
    plXZ:
      begin
        Result.Y := Base.Y;
        Result.X := U - Base.Y;
        Result.Z := W - (Base.Y - Result.X) * ISO_SIN;
      end;
  else
    begin
      Result.X := Base.X;
      Result.Y := U - Base.X;
      Result.Z := W - (Result.Y - Base.X) * ISO_SIN;
    end;
  end;
end;

function PlaneByDrag(const V: TProjector; const Anchor: TP3;
  SX, SY: Double; Keep: TPlane; Bias: Double): TPlane;
var
  Pl: TPlane;
  D, Best: Double;
begin
  Result := Keep;
  Best := Dist(Anchor, Unproject(V, SX, SY, Keep, Anchor));
  { A plan view pins Z on its own and ignores the plane entirely, so every
    candidate answers the same and Keep stands - which is right there. }
  if not (Best > 0) or (Best > 1E12) then Exit;
  for Pl := Low(TPlane) to High(TPlane) do
  begin
    if Pl = Keep then Continue;
    D := Dist(Anchor, Unproject(V, SX, SY, Pl, Anchor));
    if not (D > 0) or (D > 1E12) then Continue;   // edge-on: no opinion
    if D < Best * Bias then
    begin
      Best := D;
      Result := Pl;
    end;
  end;
end;

function AxisDir(Index: Integer): TP3;
begin
  case Index of
    0: Result := P3(1, 0, 0);
    1: Result := P3(-1, 0, 0);
    2: Result := P3(0, 1, 0);
    3: Result := P3(0, -1, 0);
    4: Result := P3(0, 0, 1);
  else
    Result := P3(0, 0, -1);
  end;
end;

function DimGeometry(const V: TProjector; const A, B, Off: TP3;
  U: TUnitSystem; out G: TDimGeom; const Note: string): Boolean;
var
  PA, PB: TPointF;
  L, UX, UY, NX, NY, OL: Double;
begin
  Result := False;
  FillChar(G, SizeOf(G), 0);
  PA := Project(V, A);
  PB := Project(V, B);
  L := Sqrt(Sqr(PB.X - PA.X) + Sqr(PB.Y - PA.Y));
  if L < 14 then Exit;
  UX := (PB.X - PA.X) / L;
  UY := (PB.Y - PA.Y) / L;

  { the line, shifted bodily by the offset - everything else hangs off it }
  G.LA := Project(V, Add3(A, Off));
  G.LB := Project(V, Add3(B, Off));

  { which way the offset went on screen, so the ticks and the text can lean
    away from the geometry rather than into it }
  NX := G.LA.X - PA.X;
  NY := G.LA.Y - PA.Y;
  OL := Sqrt(NX * NX + NY * NY);
  if OL < 1E-6 then
  begin
    NX := -UY;
    NY := UX;
  end
  else
  begin
    NX := NX / OL;
    NY := NY / OL;
  end;

  { the witness lines stand off the geometry a little and run just past the
    dimension line, which is what makes a drawing readable }
  G.A := PtF(PA.X + NX * 4, PA.Y + NY * 4);
  G.B := PtF(PB.X + NX * 4, PB.Y + NY * 4);
  G.W1 := PtF(G.LA.X + NX * 5, G.LA.Y + NY * 5);
  G.W2 := PtF(G.LB.X + NX * 5, G.LB.Y + NY * 5);
  G.S1A := PtF(G.LA.X - UX * 4 - NX * 4, G.LA.Y - UY * 4 - NY * 4);
  G.S1B := PtF(G.LA.X + UX * 4 + NX * 4, G.LA.Y + UY * 4 + NY * 4);
  G.S2A := PtF(G.LB.X - UX * 4 - NX * 4, G.LB.Y - UY * 4 - NY * 4);
  G.S2B := PtF(G.LB.X + UX * 4 + NX * 4, G.LB.Y + UY * 4 + NY * 4);
  { on the thing it measures - a radius, a diameter - there is nothing for
    witness lines to reach across }
  if OL < 1E-6 then
  begin
    G.A := G.W1;
    G.B := G.W2;
  end;
  G.Mid := PtF((G.LA.X + G.LB.X) / 2, (G.LA.Y + G.LB.Y) / 2);
  G.Nrm := PtF(NX, NY);
  { A written-over label wins: a nominal size, "FIELD VERIFY", or the figure
    on an iso that is not drawn to scale.  "<>" in it is the measured length,
    as in SketchUp, so "R <>" stays true when the circle changes. }
  if Note <> '' then G.Txt := StringReplace(Note, '<>', FormatLen(Dist(A, B), U), [rfReplaceAll])
  else G.Txt := FormatLen(Dist(A, B), U);
  { a radius has one end on the arc and the other at the center: the mark
    goes at the arc only }
  if (Copy(Note, 1, 2) = 'R ') and (Pos('<>', Note) > 0) then
  begin
    G.S1A := G.LA;
    G.S1B := G.LA;
  end;
  Result := True;
end;

function DimOffsetAt(const V: TProjector; const A, B: TP3; MX, MY: Double;
  const Extra: array of TP3; const Prefer: TP3): TP3;
var
  Cands: array of TP3;
  D, Mid: TP3;
  PA, PB, PM, S: TPointF;
  L, EX, EY, VX, VY, VL, SL, Cr, Score, Best, T, BestT: Double;
  K, BestK: Integer;

  procedure AddC(C: TP3);
  var
    Q: Double;
    J: Integer;
  begin
    { square to AB, and a unit long }
    Q := Dot3(C, D);
    C := P3(C.X - D.X * Q, C.Y - D.Y * Q, C.Z - D.Z * Q);
    Q := Sqrt(Sqr(C.X) + Sqr(C.Y) + Sqr(C.Z));
    if Q < 1E-6 then Exit;
    C := P3(C.X / Q, C.Y / Q, C.Z / Q);
    for J := 0 to High(Cands) do
      if Abs(Dot3(Cands[J], C)) > 0.999 then Exit;
    SetLength(Cands, Length(Cands) + 1);
    Cands[High(Cands)] := C;
  end;

begin
  Result := P3(0, 0, 0);
  D := Sub3(B, A);
  L := Sqrt(Sqr(D.X) + Sqr(D.Y) + Sqr(D.Z));
  if L < 1E-9 then Exit;
  D := P3(D.X / L, D.Y / L, D.Z / L);
  PA := Project(V, A);
  PB := Project(V, B);
  EX := PB.X - PA.X; EY := PB.Y - PA.Y;
  L := Sqrt(EX * EX + EY * EY);
  if L < 1E-6 then Exit;
  EX := EX / L; EY := EY / L;
  Cands := nil;
  { the planes of the faces on it first: they are what the edge is part of }
  for K := 0 to High(Extra) do AddC(Extra[K]);
  AddC(P3(1, 0, 0)); AddC(P3(0, 1, 0)); AddC(P3(0, 0, 1));
  { a line along no axis: the level square to it, and the upright }
  AddC(Cross3(P3(0, 0, 1), D));
  AddC(P3(0, 0, 1));
  Mid := P3((A.X + B.X) / 2, (A.Y + B.Y) / 2, (A.Z + B.Z) / 2);
  PM := Project(V, Mid);
  VX := MX - PM.X; VY := MY - PM.Y;
  VL := Sqrt(VX * VX + VY * VY);
  Best := -1; BestK := -1; BestT := 0;
  for K := 0 to High(Cands) do
  begin
    S := Project(V, Add3(Mid, Cands[K]));
    S := PtF(S.X - PM.X, S.Y - PM.Y);
    SL := Sqrt(S.X * S.X + S.Y * S.Y);
    { a direction straight at the camera, or along AB on screen, cannot be
      told from anything the hand does }
    Cr := S.X * EY - S.Y * EX;
    if (SL < 1E-9) or (Abs(Cr) < 0.05 * SL) then Continue;
    if VL < 1E-9 then Score := 0
    else Score := Abs(VX * S.X + VY * S.Y) / (VL * SL);
    { and one that runs nearly along the edge on screen throws the line a
      long way for a small move - worth less }
    Score := Score * (0.6 + 0.4 * Abs(Cr) / SL);
    if Abs(Dot3(Cands[K], Prefer)) > 0.999 then Score := Score + 0.1;
    { the pointer is Mid + T along it, and some way along AB - the T that
      puts the dimension line under the pointer }
    T := (VX * EY - VY * EX) / Cr;
    if Score > Best then
    begin
      Best := Score;
      BestK := K;
      BestT := T;
    end;
  end;
  if BestK < 0 then Exit;
  Result := Mul3(Cands[BestK], BestT);
end;

function DimTextTopLeft(const G: TDimGeom; TW, TH: Integer;
  Gap: Double): TPoint;
var
  Reach, CX, CY: Double;
begin
  Reach := (Abs(G.Nrm.X) * TW + Abs(G.Nrm.Y) * TH) / 2;
  CX := G.Mid.X + G.Nrm.X * (Gap + Reach);
  CY := G.Mid.Y + G.Nrm.Y * (Gap + Reach);
  Result.X := Round(CX - TW / 2);
  Result.Y := Round(CY - TH / 2);
end;

{ Axes are named by color, as SketchUp does on screen.  A lock runs both ways
  along its axis. }
function AxisName(Index: Integer): string;
begin
  case Index of
    0, 1: Result := 'red X';
    2, 3: Result := 'green Y';
  else
    Result := 'blue Z';
  end;
end;

{ The two directions of a plane that faces Nm, chosen the same way every
  time so a shape does not twist as the cursor moves. }
procedure AxesFromNormal(const Nm: TP3; out AU, AV: TP3);
var
  N, T: TP3;
  L: Double;
begin
  L := Sqrt(Sqr(Nm.X) + Sqr(Nm.Y) + Sqr(Nm.Z));
  if L < 1E-12 then
  begin
    AU := P3(1, 0, 0);
    AV := P3(0, 1, 0);
    Exit;
  end;
  N := P3(Nm.X / L, Nm.Y / L, Nm.Z / L);
  if (Abs(N.Z) <= Abs(N.X)) and (Abs(N.Z) <= Abs(N.Y)) then T := P3(0, 0, 1)
  else if Abs(N.Y) <= Abs(N.X) then T := P3(0, 1, 0)
  else T := P3(1, 0, 0);
  AU := Norm3(Cross3(T, N));
  AV := Norm3(Cross3(N, AU));
end;

procedure SetFreePlane(const Org, Normal: TP3);
var
  L: Double;
begin
  L := Sqrt(Sqr(Normal.X) + Sqr(Normal.Y) + Sqr(Normal.Z));
  if L < 1E-12 then Exit;
  GFreeOrg := Org;
  GFreeN := P3(Normal.X / L, Normal.Y / L, Normal.Z / L);
  { The in-plane directions must not wander as the cursor moves, or a
    rectangle twists while it is dragged. }
  AxesFromNormal(GFreeN, GFreeU, GFreeV);
end;

procedure GetFreePlane(out Org, U, V, N: TP3);
begin
  Org := GFreeOrg;
  U := GFreeU;
  V := GFreeV;
  N := GFreeN;
end;

{ In-plane coordinates for an arc: (u, v) are the two axes of Pl. }
procedure PlaneAxes(Pl: TPlane; out AU, AV: TP3);
begin
  case Pl of
    plXY: begin AU := P3(1, 0, 0); AV := P3(0, 1, 0); end;
    plXZ: begin AU := P3(1, 0, 0); AV := P3(0, 0, 1); end;
    plFree: begin AU := GFreeU; AV := GFreeV; end;
  else
    begin AU := P3(0, 1, 0); AV := P3(0, 0, 1); end;
  end;
end;

function TangentSagitta(const A, B, Dir: TP3; Pl: TPlane;
  out Bulge: Double): Boolean;
var
  U1, V1, U2, V2, DU, DV, Ln, TU, TV, TL, Cs, Sn, Ang: Double;
  AU, AV: TP3;
begin
  Result := False;
  Bulge := 0;
  PlaneCoords(Pl, A, U1, V1);
  PlaneCoords(Pl, B, U2, V2);
  DU := U2 - U1;
  DV := V2 - V1;
  Ln := Sqrt(Sqr(DU) + Sqr(DV));
  if Ln < 1E-9 then Exit;
  PlaneAxes(Pl, AU, AV);
  TU := Dot3(Dir, AU);
  TV := Dot3(Dir, AV);
  TL := Sqrt(Sqr(TU) + Sqr(TV));
  if TL < 1E-9 then Exit;              { the edge stands out of the plane }
  TU := TU / TL;
  TV := TV / TL;
  DU := DU / Ln;
  DV := DV / Ln;
  { the tangent runs both ways along the edge; take the way that leaves A
    heading towards B }
  if TU * DU + TV * DV < 0 then
  begin
    TU := -TU;
    TV := -TV;
  end;
  Cs := TU * DU + TV * DV;
  Sn := TU * DV - TV * DU;             { signed: which side it leans }
  Ang := ArcTan2(Sn, Cs);
  if Abs(Ang) < 1E-6 then Exit;        { straight on: no arc, no tangent }
  if Abs(Abs(Ang) - Pi) < 1E-6 then Exit;
  Bulge := -(Ln / 2) * Tan(Ang / 2);
  Result := True;
end;

function TapeGuide(HaveEdge: Boolean; const EdgeDir, A, B, PlaneNm: TP3;
  out Dir: TP3): TTapeGuide;
var
  Run, E, X: TP3;
  L: Double;
begin
  Dir := P3(0, 0, 0);
  Run := Sub3(B, A);
  L := Sqrt(Sqr(Run.X) + Sqr(Run.Y) + Sqr(Run.Z));
  if L < 1E-9 then Exit(tgPointOnly);
  Run := P3(Run.X / L, Run.Y / L, Run.Z / L);

  if HaveEdge then
  begin
    L := Sqrt(Sqr(EdgeDir.X) + Sqr(EdgeDir.Y) + Sqr(EdgeDir.Z));
    if L > 1E-9 then
    begin
      E := P3(EdgeDir.X / L, EdgeDir.Y / L, EdgeDir.Z / L);
      X := Cross3(E, Run);
      { measured along the edge it started on: a point, nothing else }
      if Sqrt(Sqr(X.X) + Sqr(X.Y) + Sqr(X.Z)) < 1E-6 then Exit(tgPointOnly);
      Dir := E;
      Exit(tgAlongEdge);
    end;
  end;

  { across the run, in the working plane }
  X := Cross3(PlaneNm, Run);
  L := Sqrt(Sqr(X.X) + Sqr(X.Y) + Sqr(X.Z));
  if L < 1E-9 then
  begin
    { measured straight out of the working plane, so there is no crosswise
      direction in it - fall back to the run itself rather than to nothing }
    Dir := Run;
    Exit(tgAcrossRun);
  end;
  Dir := P3(X.X / L, X.Y / L, X.Z / L);
  Result := tgAcrossRun;
end;

function OffsetLoop(const Loop: TP3Array; const Normal: TP3; D: Double;
  Tidy: Boolean = True): TP3Array;
const
  EPS = 1E-9;
var
  N, Ax, Bx: TP3;
  Cnt, I, J, K: Integer;
  PU, PV: array of Double;         // the loop, in plane coordinates
  DU, DV: array of Double;         // each edge's unit direction
  NU, NV: array of Double;         // each edge's outward normal
  RU, RV: array of Double;         // the answer, in plane coordinates
  Act: array of Integer;           // the edges still in it
  Keep: array of Boolean;
  M, Q, Turned: Integer;
  Area, L, Cr, T, Sgn, AU, AV, Lift: Double;
begin
  Result := nil;
  Cnt := Length(Loop);
  if Cnt < 3 then Exit;

  N := Norm3(Normal);
  Lift := Dot3(Loop[0], N);

  { Any two perpendicular directions in the plane will do.  Start from
    whichever axis the normal leans on least, so the cross product is never
    taken between two nearly parallel vectors. }
  if (Abs(N.X) <= Abs(N.Y)) and (Abs(N.X) <= Abs(N.Z)) then
    Ax := P3(1, 0, 0)
  else if Abs(N.Y) <= Abs(N.Z) then
    Ax := P3(0, 1, 0)
  else
    Ax := P3(0, 0, 1);
  Ax := Norm3(Cross3(N, Ax));
  Bx := Norm3(Cross3(N, Ax));

  SetLength(PU, Cnt); SetLength(PV, Cnt);
  for I := 0 to Cnt - 1 do
  begin
    PU[I] := Dot3(Loop[I], Ax);
    PV[I] := Dot3(Loop[I], Bx);
  end;

  { Which way round does it go?  The shoelace area in plane coordinates says
    so, and that is what fixes the meaning of "outward". }
  Area := 0;
  for I := 0 to Cnt - 1 do
  begin
    J := (I + 1) mod Cnt;
    Area := Area + (PU[I] * PV[J] - PU[J] * PV[I]);
  end;
  if Abs(Area) < EPS then Exit;
  if Area > 0 then Sgn := 1 else Sgn := -1;

  SetLength(DU, Cnt); SetLength(DV, Cnt);
  SetLength(NU, Cnt); SetLength(NV, Cnt);
  for I := 0 to Cnt - 1 do
  begin
    J := (I + 1) mod Cnt;
    DU[I] := PU[J] - PU[I];
    DV[I] := PV[J] - PV[I];
    L := Sqrt(DU[I] * DU[I] + DV[I] * DV[I]);
    if L < EPS then
    begin
      { a repeated point: the edge has no direction, so leave it flat and let
        its neighbors span the gap }
      DU[I] := 0; DV[I] := 0; NU[I] := 0; NV[I] := 0;
      Continue;
    end;
    DU[I] := DU[I] / L;
    DV[I] := DV[I] / L;
    { to the right of the way it is going, for a loop wound the positive way }
    NU[I] := DV[I] * Sgn;
    NV[I] := -DU[I] * Sgn;
  end;

  { Edges still in the answer.  One with no length is left out and its
    neighbors meet across it. }
  SetLength(Act, Cnt);
  M := 0;
  for I := 0 to Cnt - 1 do
    if (DU[I] <> 0) or (DV[I] <> 0) then
    begin
      Act[M] := I;
      Inc(M);
    end;

  { Corners, then drop the edges that came out backwards, and again.  An edge
    shorter than the offset turns round - every piece of a rounded corner
    taken in past its radius does - and SketchUp's answer is a sharp corner.
    Dropping one moves its neighbors' corners, so repeat until none turns. }
  SetLength(RU, Cnt); SetLength(RV, Cnt);
  repeat
    if M < 3 then Exit(nil);
    for Q := 0 to M - 1 do
    begin
      I := Act[Q];
      K := Act[(Q + M - 1) mod M];
      { corner Q is where the offset of the edge before meets this one's }
      Cr := DU[K] * DV[I] - DV[K] * DU[I];
      if Abs(Cr) < 1E-7 then
      begin
        { the two edges run the same way, so there is no corner to sharpen -
          step straight out along the normal }
        AU := PU[I] + NU[I] * D;
        AV := PV[I] + NV[I] * D;
      end
      else
      begin
        AU := (PU[I] + NU[I] * D) - (PU[K] + NU[K] * D);
        AV := (PV[I] + NV[I] * D) - (PV[K] + NV[K] * D);
        T := (AU * DV[I] - AV * DU[I]) / Cr;
        AU := PU[K] + NU[K] * D + DU[K] * T;
        AV := PV[K] + NV[K] * D + DV[K] * T;
      end;
      RU[Q] := AU;
      RV[Q] := AV;
    end;
    { which of them now run backwards along their own edge }
    Turned := 0;
    SetLength(Keep, M);
    for Q := 0 to M - 1 do
    begin
      I := Act[Q];
      J := (Q + 1) mod M;
      Keep[Q] := (RU[J] - RU[Q]) * DU[I] + (RV[J] - RV[Q]) * DV[I] > EPS;
      if not Keep[Q] then Inc(Turned);
    end;
    if Turned = 0 then Break;
    if Turned = M then Exit(nil);          { the whole thing turned inside out }
    { Alt on the offset tool keeps the overlaps, as SketchUp does. }
    if not Tidy then Break;
    J := 0;
    for Q := 0 to M - 1 do
      if Keep[Q] then
      begin
        Act[J] := Act[Q];
        Inc(J);
      end;
    M := J;
  until False;

  SetLength(Result, M);
  for Q := 0 to M - 1 do
    { Back into the model, lifted along the normal to the loop's own plane.
      Ax and Bx alone land on the parallel plane through the origin. }
    Result[Q] := P3(Ax.X * RU[Q] + Bx.X * RV[Q] + N.X * Lift,
                    Ax.Y * RU[Q] + Bx.Y * RV[Q] + N.Y * Lift,
                    Ax.Z * RU[Q] + Bx.Z * RV[Q] + N.Z * Lift);

  { An inward offset further than the shape can take turns it inside out.
    Return nothing rather than a sliver that measures wrong. }
  T := 0;
  for Q := 0 to M - 1 do
  begin
    J := (Q + 1) mod M;
    T := T + (RU[Q] * RV[J] - RU[J] * RV[Q]);
  end;
  if (T * Area <= 0) or (Abs(T) < Abs(Area) * 1E-6) then Result := nil;
end;

procedure PlaneCoords(Pl: TPlane; const P: TP3; out U, W: Double);
var
  AU, AV: TP3;
begin
  PlaneAxes(Pl, AU, AV);
  U := P.X * AU.X + P.Y * AU.Y + P.Z * AU.Z;
  W := P.X * AV.X + P.Y * AV.Y + P.Z * AV.Z;
end;

function ArcPoint(const C: TP3; R, Ang: Double; Pl: TPlane;
  const Nm: TP3): TP3;
var
  AU, AV: TP3;
begin
  if Pl = plFree then
    AxesFromNormal(Nm, AU, AV)
  else
    PlaneAxes(Pl, AU, AV);
  Result := P3(C.X + (AU.X * Cos(Ang) + AV.X * Sin(Ang)) * R,
               C.Y + (AU.Y * Cos(Ang) + AV.Y * Sin(Ang)) * R,
               C.Z + (AU.Z * Cos(Ang) + AV.Z * Sin(Ang)) * R);
end;

function ArcPoint(const C: TP3; R, Ang: Double; Pl: TPlane): TP3;
var
  AU, AV: TP3;
  Cs, Sn: Double;
begin
  PlaneAxes(Pl, AU, AV);
  Cs := Cos(Ang) * R;
  Sn := Sin(Ang) * R;
  Result.X := C.X + AU.X * Cs + AV.X * Sn;
  Result.Y := C.Y + AU.Y * Cs + AV.Y * Sn;
  Result.Z := C.Z + AU.Z * Cs + AV.Z * Sn;
end;

function ArcSteps(const E: TWorkEnt): Integer;
begin
  if E.Sides >= 3 then Result := E.Sides else Result := 48;
end;

function ParseSides(const S: string; out N: Integer): Boolean;
var
  T: string;
begin
  Result := False;
  N := 0;
  T := LowerCase(Trim(S));
  if Length(T) < 2 then Exit;
  if T[Length(T)] = 's' then Delete(T, Length(T), 1)
  else if T[1] = 's' then Delete(T, 1, 1)
  else Exit;
  if (T = '') or not TryStrToInt(T, N) then Exit;
  Result := (N >= 3) and (N <= 360);
end;

function ParseAngle(const S: string; out Deg: Double): Boolean;
var
  T: string;
  P: Integer;
  Rise, Run: Double;
begin
  Result := False;
  Deg := 0;
  T := Trim(S);
  if T = '' then Exit;
  { 8:12 - a slope, rise over run, which is how a roof pitch or a duct
    offset is written on the job }
  P := Pos(':', T);
  if P > 0 then
  begin
    if not TryStrToFloat(Trim(Copy(T, 1, P - 1)), Rise, DotFS) then Exit;
    if not TryStrToFloat(Trim(Copy(T, P + 1, MaxInt)), Run, DotFS) then Exit;
    if Abs(Run) < 1E-12 then Exit;
    Deg := RadToDeg(ArcTan2(Rise, Abs(Run)));
    if Run < 0 then Deg := -Deg;
    Exit(True);
  end;
  { a degree sign or a d after the number is allowed and ignored }
  if (Length(T) >= 2) and (Copy(T, Length(T) - 1, 2) = #$C2#$B0) then
    T := Trim(Copy(T, 1, Length(T) - 2))
  else if (T <> '') and (T[Length(T)] in ['d', 'D']) then
    T := Trim(Copy(T, 1, Length(T) - 1));
  Result := TryStrToFloat(T, Deg, DotFS);
end;

function FormatAngle(Deg: Double): string;
begin
  if Abs(Deg - Round(Deg)) < 0.005 then
    Result := IntToStr(Round(Deg)) + #$C2#$B0
  else
    Result := FormatFloat('0.0', Deg, DotFS) + #$C2#$B0;
end;

function RotV(const V, Axis: TP3; Ang: Double): TP3;
var
  K: TP3;
  Cs, Sn, D: Double;
begin
  { Rodrigues: V cos + (K x V) sin + K (K.V)(1 - cos) }
  K := Norm3(Axis);
  Cs := Cos(Ang);
  Sn := Sin(Ang);
  D := Dot3(K, V) * (1 - Cs);
  Result := P3(V.X * Cs + (K.Y * V.Z - K.Z * V.Y) * Sn + K.X * D,
               V.Y * Cs + (K.Z * V.X - K.X * V.Z) * Sn + K.Y * D,
               V.Z * Cs + (K.X * V.Y - K.Y * V.X) * Sn + K.Z * D);
end;

function RotP(const P, C, Axis: TP3; Ang: Double): TP3;
var
  V: TP3;
begin
  V := RotV(Sub3(P, C), Axis, Ang);
  Result := Add3(C, V);
end;

function ArcFromChord(const A, B: TP3; Bulge: Double; Pl: TPlane;
  out C: TP3; out R, A0, Sweep: Double): Boolean;
var
  AU, AV, Nm: TP3;
  AUx, AUy, BUx, BUy, Ch, H, NX, NY, MX, MY, D, AngA, AngB: Double;

  procedure ToPlane(const P: TP3; out U, W: Double);
  begin
    U := P.X * AU.X + P.Y * AU.Y + P.Z * AU.Z;
    W := P.X * AV.X + P.Y * AV.Y + P.Z * AV.Z;
  end;

begin
  Result := False;
  C := A;
  R := 0;
  A0 := 0;
  Sweep := 0;
  PlaneAxes(Pl, AU, AV);
  ToPlane(A, AUx, AUy);
  ToPlane(B, BUx, BUy);

  Ch := Sqrt(Sqr(BUx - AUx) + Sqr(BUy - AUy));
  H := Bulge;
  if (Ch < 1E-9) or (Abs(H) < 1E-9) then Exit;

  NX := -(BUy - AUy) / Ch;
  NY := (BUx - AUx) / Ch;
  MX := (AUx + BUx) / 2;
  MY := (AUy + BUy) / 2;

  R := (Sqr(Ch / 2) + Sqr(H)) / (2 * Abs(H));
  D := R - Abs(H);
  if H >= 0 then
  begin
    MX := MX - NX * D;
    MY := MY - NY * D;
  end
  else
  begin
    MX := MX + NX * D;
    MY := MY + NY * D;
  end;

  { Back into model space.  The in-plane axes put the center on a plane
    through the origin, so slide it along the normal to the chord's own
    plane - one rule for the three flat planes and a free one. }
  Nm := Norm3(Cross3(AU, AV));
  D := Dot3(A, Nm);
  C.X := AU.X * MX + AV.X * MY + Nm.X * D;
  C.Y := AU.Y * MX + AV.Y * MY + Nm.Y * D;
  C.Z := AU.Z * MX + AV.Z * MY + Nm.Z * D;

  AngA := ArcTan2(AUy - MY, AUx - MX);
  AngB := ArcTan2(BUy - MY, BUx - MX);
  A0 := AngA;
  Sweep := AngB - AngA;
  while Sweep <= -Pi do Sweep := Sweep + 2 * Pi;
  while Sweep > Pi do Sweep := Sweep - 2 * Pi;
  if Abs(H) > Ch / 2 then
    if Sweep > 0 then Sweep := Sweep - 2 * Pi else Sweep := Sweep + 2 * Pi;
  if ((H > 0) and (Sweep > 0)) or ((H < 0) and (Sweep < 0)) then
    if Sweep > 0 then Sweep := Sweep - 2 * Pi else Sweep := Sweep + 2 * Pi;

  Result := True;
end;

{ How far along a segment its nearest point to P lies, 0 at A and 1 at B.
  The pick wants the place as well as the distance. }
function SegParam(PX, PY, AX, AY, BX, BY: Double): Double;
var
  DX, DY, L2: Double;
begin
  DX := BX - AX;
  DY := BY - AY;
  L2 := DX * DX + DY * DY;
  if L2 < 1E-12 then Exit(0);
  Result := EnsureRange(((PX - AX) * DX + (PY - AY) * DY) / L2, 0, 1);
end;

{ Straight-line distance from a point to a segment - not squared. }
function DistToSeg(PX, PY, AX, AY, BX, BY: Double): Double;
var
  DX, DY, T, L2: Double;
begin
  DX := BX - AX;
  DY := BY - AY;
  L2 := DX * DX + DY * DY;
  if L2 < 1E-12 then
    Exit(Sqrt(Sqr(PX - AX) + Sqr(PY - AY)));
  T := EnsureRange(((PX - AX) * DX + (PY - AY) * DY) / L2, 0, 1);
  Result := Sqrt(Sqr(PX - (AX + DX * T)) + Sqr(PY - (AY + DY * T)));
end;

{ ---------------------------------------------------------------------- }
{ TWorkDoc                                                                }
{ ---------------------------------------------------------------------- }

function TWorkDoc.GetEnt(I: Integer): TWorkEnt;
begin
  Result := FEnts[I];
end;

function TWorkDoc.Stored: Integer;
begin
  Result := FLive;
end;

function TWorkDoc.HasLine(const A, B: TP3): Boolean;
const
  TOL = 1E-7;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to FLive - 1 do
    if FEnts[I].Kind = ekLine then
      if ((Dist(FEnts[I].A, A) < TOL) and (Dist(FEnts[I].B, B) < TOL)) or
         ((Dist(FEnts[I].A, B) < TOL) and (Dist(FEnts[I].B, A) < TOL)) then
        Exit;
  Result := False;
end;

function TWorkDoc.AddLineSplit(const A, B: TP3; Ink: TColor;
  Weight: Single): Integer;
const
  TOL = 1E-7;
var
  U: TP3;
  L, T0, T1, Mid: Double;
  I, J, N, NC: Integer;
  Hits: array of Integer;
  HA, HB: array of Double;    { each hit's run, as a distance along U }
  { and the pen each was drawn with, read before anything is deleted:
    deleting moves every index above it down }
  HInk: array of TColor;
  HW: array of Single;
  Cuts: array of Double;
  Doom: array of Boolean;
  Src: Integer;
  PieceA, PieceB: TP3;

  { how far along the line from A this point is, and how far off it }
  function Along(const Q: TP3; out Off: Double): Double;
  var
    W, F: TP3;
  begin
    W := Sub3(Q, A);
    Result := Dot3(W, U);
    F := P3(W.X - U.X * Result, W.Y - U.Y * Result, W.Z - U.Z * Result);
    Off := Sqrt(F.X * F.X + F.Y * F.Y + F.Z * F.Z);
  end;

  procedure Cut(T: Double);
  var
    K: Integer;
  begin
    for K := 0 to NC - 1 do
      if Abs(Cuts[K] - T) < TOL then Exit;
    if NC >= Length(Cuts) then SetLength(Cuts, Max(16, NC * 2));
    Cuts[NC] := T;
    Inc(NC);
  end;

  { which hit covers the middle of this piece, or -1 for the new line only }
  function Owner(M: Double): Integer;
  var
    K: Integer;
  begin
    Result := -1;
    for K := 0 to High(Hits) do
      if (M > Min(HA[K], HB[K]) + TOL) and (M < Max(HA[K], HB[K]) - TOL) then
        Exit(K);
  end;

begin
  Result := 0;
  L := Dist(A, B);
  if L < TOL then Exit;
  U := P3((B.X - A.X) / L, (B.Y - A.Y) / L, (B.Z - A.Z) / L);

  { everything loose that lies along this line and shares more than a point }
  SetLength(Hits, 0);
  SetLength(HA, 0);
  SetLength(HB, 0);
  for I := 0 to FLive - 1 do
  begin
    if FEnts[I].Kind <> ekLine then Continue;
    if FEnts[I].Dim or (FEnts[I].Grp <> 0) or (FEnts[I].Part <> FStamp) then Continue;
    T0 := Along(FEnts[I].A, Mid);
    if Mid > TOL then Continue;
    T1 := Along(FEnts[I].B, Mid);
    if Mid > TOL then Continue;
    { sharing a run, not merely a corner }
    if Min(T0, T1) > L - TOL then Continue;
    if Max(T0, T1) < TOL then Continue;
    N := Length(Hits);
    SetLength(Hits, N + 1); Hits[N] := I;
    SetLength(HA, N + 1);   HA[N] := T0;
    SetLength(HB, N + 1);   HB[N] := T1;
    SetLength(HInk, N + 1); HInk[N] := FEnts[I].Ink;
    SetLength(HW, N + 1);   HW[N] := FEnts[I].Weight;
  end;

  if Length(Hits) = 0 then
  begin
    AddLine(A, B, Ink, Weight, False);
    Exit;
  end;

  { every end anybody has, as a distance along the line }
  NC := 0;
  SetLength(Cuts, 16);
  Cut(0);
  Cut(L);
  for I := 0 to High(Hits) do
  begin
    Cut(HA[I]);
    Cut(HB[I]);
  end;
  for I := 0 to NC - 2 do
    for J := 0 to NC - 2 - I do
      if Cuts[J] > Cuts[J + 1] then
      begin
        Mid := Cuts[J]; Cuts[J] := Cuts[J + 1]; Cuts[J + 1] := Mid;
      end;

  { the old ones go; the run is laid again in pieces }
  SetLength(Doom, FLive);
  for I := 0 to FLive - 1 do Doom[I] := False;
  for I := 0 to High(Hits) do Doom[Hits[I]] := True;

  SetLength(Cuts, NC);
  DeleteMarked(Doom);

  for I := 0 to NC - 2 do
  begin
    T0 := Cuts[I];
    T1 := Cuts[I + 1];
    if T1 - T0 < TOL then Continue;
    Mid := (T0 + T1) / 2;
    Src := Owner(Mid);
    if (Src < 0) and ((Mid < TOL) or (Mid > L - TOL)) then Continue;
    PieceA := P3(A.X + U.X * T0, A.Y + U.Y * T0, A.Z + U.Z * T0);
    PieceB := P3(A.X + U.X * T1, A.Y + U.Y * T1, A.Z + U.Z * T1);
    { a piece that was already drawn keeps the pen it was drawn with }
    if Src >= 0 then
      AddLine(PieceA, PieceB, HInk[Src], HW[Src], False)
    else
      AddLine(PieceA, PieceB, Ink, Weight, False);
    Inc(Result);
  end;
end;

{ Anything in redo space is dropped the moment you draw again. }
procedure TWorkDoc.AddLine(const A, B: TP3; Ink: TColor; Weight: Single;
  Dim: Boolean);
begin
  Room;
  Finalize(FEnts[FLive]);
  FillChar(FEnts[FLive], SizeOf(TWorkEnt), 0);
  FEnts[FLive].Kind := ekLine;
  FEnts[FLive].Part := FStamp;
  FEnts[FLive].A := A;
  FEnts[FLive].B := B;
  FEnts[FLive].Ink := Ink;
  FEnts[FLive].Weight := Weight;
  FEnts[FLive].Dim := Dim;
  Inc(FLive);
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

procedure TWorkDoc.AddArc(const C: TP3; R, A0, Sweep: Double; Pl: TPlane;
  Ink: TColor; Weight: Single);
var
  FreeO, FreeU, FreeV: TP3;
begin
  Room;
  Finalize(FEnts[FLive]);
  FillChar(FEnts[FLive], SizeOf(TWorkEnt), 0);
  FEnts[FLive].Kind := ekArc;
  FEnts[FLive].Part := FStamp;
  FEnts[FLive].C := C;
  FEnts[FLive].R := R;
  FEnts[FLive].A0 := A0;
  FEnts[FLive].Sweep := Sweep;
  FEnts[FLive].Plane := Pl;
  { A free plane is only a name, so the arc takes its normal now, while the
    plane it was drawn in is still the current one. }
  if Pl = plFree then GetFreePlane(FreeO, FreeU, FreeV, FEnts[FLive].Nm);
  FEnts[FLive].A := ArcPoint(C, R, A0, Pl, FEnts[FLive].Nm);
  FEnts[FLive].B := ArcPoint(C, R, A0 + Sweep, Pl, FEnts[FLive].Nm);
  FEnts[FLive].Ink := Ink;
  FEnts[FLive].Weight := Weight;
  Inc(FLive);
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

procedure TWorkDoc.AddText(const A: TP3; const S: string; Ink: TColor);
begin
  AddNote(A, A, S, Ink);
end;

procedure TWorkDoc.AddNote(const A, Target: TP3; const S: string; Ink: TColor);
begin
  Room;
  Finalize(FEnts[FLive]);
  FillChar(FEnts[FLive], SizeOf(TWorkEnt), 0);
  FEnts[FLive].Kind := ekText;
  FEnts[FLive].Part := FStamp;
  FEnts[FLive].A := A;
  FEnts[FLive].B := Target;
  FEnts[FLive].Txt := S;
  FEnts[FLive].Ink := Ink;
  FEnts[FLive].Weight := 1;
  Inc(FLive);
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

procedure TWorkDoc.AddBore(const Loop: TP3Array; const FarOfFirst: TP3; G: Integer);
var
  Own: TP3Array;
  Far: TP3;
begin
  if Length(Loop) < 3 then Exit;
  { Loop may be a face's own polygon inside FEnts, and growing FEnts moves
    it - so it is copied before anything else happens }
  Own := Copy(Loop, 0, Length(Loop));
  Far := FarOfFirst;
  Room;
  Finalize(FEnts[FLive]);
  FillChar(FEnts[FLive], SizeOf(TWorkEnt), 0);
  FEnts[FLive].Kind := ekBore;
  FEnts[FLive].Part := FStamp;
  FEnts[FLive].Poly := Own;
  FEnts[FLive].A := Own[0];
  FEnts[FLive].B := Far;
  FEnts[FLive].Grp := G;
  FEnts[FLive].Solid := True;
  Inc(FLive);
end;

procedure TWorkDoc.AddGuide(const A, B: TP3);
begin
  Room;
  Finalize(FEnts[FLive]);
  FillChar(FEnts[FLive], SizeOf(TWorkEnt), 0);
  FEnts[FLive].Kind := ekGuide;
  FEnts[FLive].Part := FStamp;
  FEnts[FLive].A := A;
  FEnts[FLive].B := B;
  FEnts[FLive].Weight := 1;
  Inc(FLive);
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

{ Hiding guides must reach every picker, not just the drawing.  A setter
  because the snap cache is kept until an edit, and a guide point left in it
  stays snappable. }
procedure TWorkDoc.SetGuidesHidden(On_: Boolean);
begin
  if On_ = FGuidesHidden then Exit;
  FGuidesHidden := On_;
  FSnapDirty := True;
  FSnapScreenOK := False;
end;

function TWorkDoc.GuideCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FLive - 1 do
    if FEnts[I].Kind = ekGuide then Inc(Result);
end;

function TWorkDoc.ClearGuides: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := FLive - 1 downto 0 do
    if FEnts[I].Kind = ekGuide then
    begin
      Delete(I);
      Inc(Result);
    end;
end;

function TWorkDoc.SetDimNote(Index: Integer; const Note: string): Boolean;
begin
  Result := (Index >= 0) and (Index < FLive) and (FEnts[Index].Kind = ekDim);
  if Result then FEnts[Index].Txt := Trim(Note);
end;

procedure TWorkDoc.AddDim(const A, B: TP3; Ink: TColor; const Off: TP3;
  const Note: string);
begin
  Room;
  Finalize(FEnts[FLive]);
  FillChar(FEnts[FLive], SizeOf(TWorkEnt), 0);
  FEnts[FLive].Kind := ekDim;
  FEnts[FLive].Part := FStamp;
  FEnts[FLive].A := A;
  FEnts[FLive].B := B;
  FEnts[FLive].C := Off;
  FEnts[FLive].Ink := Ink;
  FEnts[FLive].Weight := 1;
  FEnts[FLive].Dim := True;
  FEnts[FLive].Txt := Note;
  Inc(FLive);
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

{ FEnts is capacity and FLive the count, so adding one does not reallocate
  the whole array each time. }
procedure TWorkDoc.Room;
begin
  if FLive >= Length(FEnts) then SetLength(FEnts, Max(16, Length(FEnts) * 2));
end;

procedure TWorkDoc.Delete(I: Integer);
var
  K: Integer;
begin
  if (I < 0) or (I >= FLive) then Exit;
  for K := I to FLive - 2 do
    FEnts[K] := FEnts[K + 1];
  Dec(FLive);
  Finalize(FEnts[FLive]);
  FillChar(FEnts[FLive], SizeOf(TWorkEnt), 0);
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

procedure TWorkDoc.DeleteMarked(const Doomed: array of Boolean);
var
  K, W: Integer;
begin
  W := 0;
  for K := 0 to FLive - 1 do
    if (K > High(Doomed)) or not Doomed[K] then
    begin
      if W <> K then FEnts[W] := FEnts[K];
      Inc(W);
    end;
  for K := W to FLive - 1 do
  begin
    Finalize(FEnts[K]);
    FillChar(FEnts[K], SizeOf(TWorkEnt), 0);
  end;
  FLive := W;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

procedure TWorkDoc.Clear;
begin
  HeadNote := '';
  TailNote := '';
  SetLength(FEnts, 0);
  FLive := 0;
  FNextPart := 0;
  FContext := 0;
  FStamp := 0;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;


{ A face's outline is a dynamic array and plain record assignment only shares
  the reference, so a push/pull rewriting points in place would corrupt the
  undo snapshot.  Every copy must be deep. }
function CopyEnt(const Src: TWorkEnt): TWorkEnt;
var
  I, H: Integer;
begin
  Result := Src;
  Result.Poly := nil;
  SetLength(Result.Poly, Length(Src.Poly));
  for I := 0 to High(Src.Poly) do
    Result.Poly[I] := Src.Poly[I];
  { The openings too, outer array and every loop, or moving a face with a
    window writes through the undo snapshot and undo leaves the window
    behind. }
  Result.Holes := nil;
  SetLength(Result.Holes, Length(Src.Holes));
  for H := 0 to High(Src.Holes) do
  begin
    SetLength(Result.Holes[H], Length(Src.Holes[H]));
    for I := 0 to High(Src.Holes[H]) do
      Result.Holes[H][I] := Src.Holes[H][I];
  end;
end;

{ Undo copies the whole document; simpler and safer than replaying edits. }
function TWorkDoc.Snapshot: TWorkEntArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, FLive);
  for I := 0 to FLive - 1 do
    Result[I] := CopyEnt(FEnts[I]);
end;

procedure TWorkDoc.RestoreSnap(const A: TWorkEntArray);
var
  I: Integer;
begin
  SetLength(FEnts, Length(A));
  for I := 0 to High(A) do
    FEnts[I] := CopyEnt(A[I]);
  FLive := Length(A);
  { the groups came back with the entities; the numbering has to catch up,
    and a context that was undone out of existence is nobody's to keep }
  RecountParts;
  if (FContext <> 0) and (PartEnt(FContext) < 0) then SetContext(0);
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

function TWorkDoc.FirstOfChain: Integer;
var
  I: Integer;
begin
  Result := FLive;
  for I := FLive - 1 downto 0 do
  begin
    if FEnts[I].Kind <> ekLine then Break;
    if (I < FLive - 1) and not SamePt(FEnts[I].B, FEnts[I + 1].A, 1E-6) then Break;
    Result := I;
  end;
end;

function TWorkDoc.ChainLength: Double;
var
  I: Integer;
begin
  Result := 0;
  for I := FirstOfChain to FLive - 1 do
    if FEnts[I].Kind = ekLine then
      Result := Result + Dist(FEnts[I].A, FEnts[I].B);
end;

function TWorkDoc.ChainClosed(Tol: Double): Boolean;
var
  First: Integer;
begin
  First := FirstOfChain;
  Result := (FLive - First >= 3) and
            SamePt(FEnts[FLive - 1].B, FEnts[First].A, Tol);
end;

{ Shoelace in the XY plane - only meaningful for a flat closed run. }
function TWorkDoc.ChainArea: Double;
var
  I: Integer;
  Acc: Double;
begin
  Acc := 0;
  for I := FirstOfChain to FLive - 1 do
    if FEnts[I].Kind = ekLine then
      Acc := Acc + (FEnts[I].A.X * FEnts[I].B.Y - FEnts[I].B.X * FEnts[I].A.Y);
  Result := Abs(Acc) / 2;
end;

{ ---------------------------------------------------------------------- }
{ faces and push/pull                                                      }
{ ---------------------------------------------------------------------- }

procedure TWorkDoc.SetSlice(AOn: Boolean; ALo, AHi: Double);
var
  T: Double;
begin
  if AHi < ALo then begin T := ALo; ALo := AHi; AHi := T; end;
  if (FSliceOn = AOn) and (FSliceLo = ALo) and (FSliceHi = AHi) then Exit;
  FSliceOn := AOn;
  FSliceLo := ALo;
  FSliceHi := AHi;
  { The slice decides which points can be snapped to, so the snap cache has
    to follow it or the cursor sticks to things you cannot see. }
  FSnapDirty := True;
  FSnapScreenOK := False;
  FOnFaceOK := False;
end;

function TWorkDoc.InSlice(Index: Integer): Boolean;
const
  EPS = 1E-7;
var
  Lo, Hi: Double;
  K: Integer;

  procedure Grow(V: Double);
  begin
    if V < Lo then Lo := V;
    if V > Hi then Hi := V;
  end;

begin
  { a group put away is out of the drawing the same way, and every pass
    that asks this leaves it out without asking anything else }
  if EntHidden(Index) then Exit(False);
  Result := True;
  if not FSliceOn then Exit;
  if (Index < 0) or (Index >= FLive) then Exit;
  Lo := 1E300;
  Hi := -1E300;
  case FEnts[Index].Kind of
    ekFace:
      begin
        for K := 0 to High(FEnts[Index].Poly) do Grow(FEnts[Index].Poly[K].Z);
        if Length(FEnts[Index].Poly) = 0 then Grow(FEnts[Index].A.Z);
      end;
    ekArc:
      begin
        { the whole circle it is cut from, because a tilted arc reaches above
          and below its own ends }
        Grow(FEnts[Index].C.Z - FEnts[Index].R);
        Grow(FEnts[Index].C.Z + FEnts[Index].R);
      end;
    ekText:
      Grow(FEnts[Index].A.Z);
  else
    begin
      Grow(FEnts[Index].A.Z);
      Grow(FEnts[Index].B.Z);
    end;
  end;
  { any overlap at all counts.  A wall that starts below the slice and
    carries on above it is in the drawing - that is what a cut is. }
  Result := (Hi >= FSliceLo - EPS) and (Lo <= FSliceHi + EPS);
end;

function TWorkDoc.OutsideSlice: Integer;
var
  I: Integer;
begin
  Result := 0;
  if not FSliceOn then Exit;
  for I := 0 to FLive - 1 do
    if not EntHidden(I) and not InSlice(I) then Inc(Result);
end;

function TWorkDoc.FaceCorners(Index: Integer): TP3Array;
var
  I, J, N: Integer;
begin
  Result := nil;
  if (Index < 0) or (Index >= FLive) then Exit;
  if FEnts[Index].Kind <> ekFace then Exit;
  N := Length(FEnts[Index].Poly);
  for I := 0 to High(FEnts[Index].Holes) do
    Inc(N, Length(FEnts[Index].Holes[I]));
  SetLength(Result, N);
  N := 0;
  for I := 0 to High(FEnts[Index].Poly) do
  begin
    Result[N] := FEnts[Index].Poly[I];
    Inc(N);
  end;
  for I := 0 to High(FEnts[Index].Holes) do
    for J := 0 to High(FEnts[Index].Holes[I]) do
    begin
      Result[N] := FEnts[Index].Holes[I][J];
      Inc(N);
    end;
end;

function TWorkDoc.FaceCut(Index: Integer): TTriList;
var
  Nm, U, W: TP3;
  Corners: TP3Array;
  Flat2: array of TPointF;
  Ring: TIndexRing;
  Holes: TIndexRings;
  I, J, N, Base, Was, Fresh: Integer;
begin
  Result := nil;
  if (Index < 0) or (Index >= FLive) then Exit;
  if FEnts[Index].Kind <> ekFace then Exit;
  if Length(FEnts[Index].Poly) < 3 then Exit;

  if Length(FCut) < FLive then
  begin
    Was := Length(FCut);
    SetLength(FCut, FLive);
    { the edit sequence starts at zero, so zero cannot also be how a fresh
      entry says it has never been cut }
    for Fresh := Was to FLive - 1 do FCut[Fresh].Seq := -1;
  end;
  { the edit sequence is bumped by every change to the drawing, so an entry
    left over from before one - at an index that may now hold something else
    entirely - can never be mistaken for a current answer }
  if FCut[Index].Seq = FEditSeq then
  begin
    Result := FCut[Index].Tris;
    Exit;
  end;

  Corners := FaceCorners(Index);
  Nm := FaceNormal(Index);

  { Two axes across the face to flatten it.  Any perpendicular pair will do;
    the cutting does not care which way the outline winds. }
  U := P3(1, 0, 0);
  if Abs(Nm.X) > 0.9 then U := P3(0, 1, 0);
  U := Norm3(Cross3(Nm, U));
  W := Norm3(Cross3(Nm, U));

  SetLength(Flat2, Length(Corners));
  for I := 0 to High(Corners) do
  begin
    Flat2[I].X := Dot3(Corners[I], U);
    Flat2[I].Y := Dot3(Corners[I], W);
  end;

  N := Length(FEnts[Index].Poly);
  SetLength(Ring, N);
  for I := 0 to N - 1 do Ring[I] := I;
  SetLength(Holes, Length(FEnts[Index].Holes));
  Base := N;
  for I := 0 to High(FEnts[Index].Holes) do
  begin
    SetLength(Holes[I], Length(FEnts[Index].Holes[I]));
    for J := 0 to High(FEnts[Index].Holes[I]) do
    begin
      Holes[I][J] := Base;
      Inc(Base);
    end;
  end;

  if not Triangulate(Flat2, Ring, Holes, Result) then Result := nil;
  FCut[Index].Seq := FEditSeq;
  FCut[Index].Tris := Result;
end;

{ defined further down, beside OrientFace, and wanted up here }
function EdgeKeyOf(const A, B: TP3; out Way: PtrInt): string; forward;
function PointKeyOf(const P: TP3): string; forward;

function TWorkDoc.OpenEdges(G: Integer): TP3Array;
var
  Ix, Jx: TFPHashList;
  I, J, N, NV, NOut, C1, C2, NCut: Integer;
  Key: string;
  Way: PtrInt;
  PA, PB, CutA, CutB: TP3;
  Verts: array of TP3;
  Loops: array of TP3Array;
  LI: Integer;
  Cuts: array of Double;
  T, TSwap: Double;
  Ends: array of TP3;

  { the same test GroupClosed uses - a corner lying along an edge, strictly
    between its ends }
  function Between(const A, B, P: TP3; out U: Double): Boolean;
  var
    DX, DY, DZ, L2, CX, CY, CZ: Double;
  begin
    Result := False;
    DX := B.X - A.X; DY := B.Y - A.Y; DZ := B.Z - A.Z;
    L2 := DX * DX + DY * DY + DZ * DZ;
    if L2 < 1E-18 then Exit;
    U := ((P.X - A.X) * DX + (P.Y - A.Y) * DY + (P.Z - A.Z) * DZ) / L2;
    if (U <= 1E-9) or (U >= 1 - 1E-9) then Exit;
    CX := (P.Y - A.Y) * DZ - (P.Z - A.Z) * DY;
    CY := (P.Z - A.Z) * DX - (P.X - A.X) * DZ;
    CZ := (P.X - A.X) * DY - (P.Y - A.Y) * DX;
    Result := (CX * CX + CY * CY + CZ * CZ) <= 1E-10 * L2;
  end;

begin
  Result := nil;
  if G <= 0 then Exit;

  { the group's own corners, which is what an edge can be interrupted at }
  NV := 0;
  Jx := TFPHashList.Create;
  try
    for I := 0 to FLive - 1 do
    begin
      if (FEnts[I].Kind <> ekFace) or not FEnts[I].Solid then Continue;
      if FEnts[I].Grp <> G then Continue;
      SetLength(Loops, 1 + Length(FEnts[I].Holes));
      Loops[0] := FEnts[I].Poly;
      for J := 0 to High(FEnts[I].Holes) do Loops[J + 1] := FEnts[I].Holes[J];
      for LI := 0 to High(Loops) do
        for J := 0 to High(Loops[LI]) do
        begin
          Key := Format('%d,%d,%d', [Round(Loops[LI][J].X * 1E6),
            Round(Loops[LI][J].Y * 1E6), Round(Loops[LI][J].Z * 1E6)]);
          if Jx.FindIndexOf(Key) >= 0 then Continue;
          Jx.Add(Key, Pointer(1));
          if NV >= Length(Verts) then SetLength(Verts, Max(64, NV * 2));
          Verts[NV] := Loops[LI][J];
          Inc(NV);
        end;
    end;
  finally
    Jx.Free;
  end;
  if NV = 0 then Exit;

  { every edge, cut at any corner lying along it, tallied by direction }
  Ix := TFPHashList.Create;
  SetLength(Ends, 0);
  try
    for I := 0 to FLive - 1 do
    begin
      if (FEnts[I].Kind <> ekFace) or not FEnts[I].Solid then Continue;
      if FEnts[I].Grp <> G then Continue;
      SetLength(Loops, 1 + Length(FEnts[I].Holes));
      Loops[0] := FEnts[I].Poly;
      for J := 0 to High(FEnts[I].Holes) do Loops[J + 1] := FEnts[I].Holes[J];
      for LI := 0 to High(Loops) do
      begin
      N := Length(Loops[LI]);
      if N < 3 then Continue;
      for J := 0 to N - 1 do
      begin
        PA := Loops[LI][J];
        PB := Loops[LI][(J + 1) mod N];
        NCut := 0;
        for C2 := 0 to NV - 1 do
          if Between(PA, PB, Verts[C2], T) then
          begin
            if NCut >= Length(Cuts) then SetLength(Cuts, Max(8, NCut * 2));
            Cuts[NCut] := T;
            Inc(NCut);
          end;
        for C1 := 1 to NCut - 1 do
        begin
          TSwap := Cuts[C1];
          C2 := C1 - 1;
          while (C2 >= 0) and (Cuts[C2] > TSwap) do
          begin
            Cuts[C2 + 1] := Cuts[C2];
            Dec(C2);
          end;
          Cuts[C2 + 1] := TSwap;
        end;
        CutA := PA;
        for C1 := 0 to NCut do
        begin
          if C1 = NCut then CutB := PB
          else
          begin
            T := Cuts[C1];
            CutB := P3(PA.X + (PB.X - PA.X) * T, PA.Y + (PB.Y - PA.Y) * T,
                       PA.Z + (PB.Z - PA.Z) * T);
          end;
          Key := EdgeKeyOf(CutA, CutB, Way);
          C2 := Ix.FindIndexOf(Key);
          if C2 < 0 then
          begin
            Ix.Add(Key, Pointer(Way + 8));
            SetLength(Ends, Ix.Count * 2);
            Ends[(Ix.Count - 1) * 2] := CutA;
            Ends[(Ix.Count - 1) * 2 + 1] := CutB;
          end
          else
            Ix.Items[C2] := Pointer(PtrInt(Ix.Items[C2]) + Way);
          CutA := CutB;
        end;
      end;
      end;
    end;

    { an edge used once each way leaves its tally back at eight }
    NOut := 0;
    for I := 0 to Ix.Count - 1 do
      if PtrInt(Ix.Items[I]) <> 8 then
      begin
        SetLength(Result, NOut + 2);
        Result[NOut] := Ends[I * 2];
        Result[NOut + 1] := Ends[I * 2 + 1];
        Inc(NOut, 2);
      end;
  finally
    Ix.Free;
  end;
end;

{ Is this solid closed - every edge used by exactly two of its faces, run
  opposite ways?  Then a back face can never be seen and is culled; an open
  shell such as a duct transition keeps its backs, since they can be looked
  at.  Worked out once per edit. }
function TWorkDoc.GroupClosed(G: Integer): Boolean;

  { the two ends to a millionth, smaller end first so either way round makes
    the same key, and a sign saying which way round this use ran }
  function EKey(const A, B: TP3; out Way: PtrInt): string;
  var
    P, Q: array[0..2] of Int64;
    I: Integer;
    Swap: Boolean;
  begin
    P[0] := Round(A.X * 1E6); P[1] := Round(A.Y * 1E6); P[2] := Round(A.Z * 1E6);
    Q[0] := Round(B.X * 1E6); Q[1] := Round(B.Y * 1E6); Q[2] := Round(B.Z * 1E6);
    Swap := False;
    for I := 0 to 2 do
      if P[I] <> Q[I] then
      begin
        Swap := P[I] > Q[I];
        Break;
      end;
    if Swap then Way := -1 else Way := 1;
    if Swap then
      Result := Format('%d,%d,%d|%d,%d,%d', [Q[0], Q[1], Q[2], P[0], P[1], P[2]])
    else
      Result := Format('%d,%d,%d|%d,%d,%d', [P[0], P[1], P[2], Q[0], Q[1], Q[2]]);
  end;

  { Is P on segment A-B, strictly between the ends?  The tolerance is finer
    than anything drawn but coarser than the millionths edge keys round to,
    so a point keyed onto the line is never rejected here. }
  function Between(const A, B, P: TP3; out T: Double): Boolean;
  var
    DX, DY, DZ, L2, CX, CY, CZ: Double;
  begin
    Result := False;
    DX := B.X - A.X; DY := B.Y - A.Y; DZ := B.Z - A.Z;
    L2 := DX * DX + DY * DY + DZ * DZ;
    if L2 < 1E-18 then Exit;
    T := ((P.X - A.X) * DX + (P.Y - A.Y) * DY + (P.Z - A.Z) * DZ) / L2;
    if (T <= 1E-9) or (T >= 1 - 1E-9) then Exit;
    CX := (P.Y - A.Y) * DZ - (P.Z - A.Z) * DY;
    CY := (P.Z - A.Z) * DX - (P.X - A.X) * DZ;
    CZ := (P.X - A.X) * DY - (P.Y - A.Y) * DX;
    Result := (CX * CX + CY * CY + CZ * CZ) <= 1E-10 * L2;
  end;

var
  I, J, N, K, Top: Integer;
  Ix: TFPHashList;
  Key: string;
  Way: PtrInt;
  Seen: array of Integer;
  { the endpoints behind each entry in the hash, so an edge that did not
    match can be looked at again rather than only counted }
  EdgeA, EdgeB: array of TP3;
  EdgeG: array of Integer;
  { the second chance, for groups the plain count says are open }
  Suspect: array of Boolean;
  Loops: array of TP3Array;
  LI: Integer;
  Verts: array of TP3;
  NV, NU, Budget: Integer;
  Cuts: array of Double;
  NCut, C1, C2: Integer;
  T, TSwap: Double;
  PA, PB, CutA, CutB: TP3;
  Jx: TFPHashList;
  Shut: Boolean;
begin
  Result := False;
  if G <= 0 then Exit;
  if FClosedSeq <> FEditSeq then
  begin
    FClosedSeq := FEditSeq;
    Top := 0;
    for I := 0 to FLive - 1 do
      if (FEnts[I].Kind = ekFace) and FEnts[I].Solid and (FEnts[I].Grp > Top) then
        Top := FEnts[I].Grp;
    SetLength(FClosedGrp, Top + 1);
    for I := 0 to High(FClosedGrp) do FClosedGrp[I] := (I > 0);

    { One pass over every solid's faces with the group in the key, not one
      pass per solid - thousands of boxes would otherwise cost seconds a
      frame. }
    Ix := TFPHashList.Create;
    try
      for I := 0 to FLive - 1 do
      begin
        if (FEnts[I].Kind <> ekFace) or not FEnts[I].Solid then Continue;
        if FEnts[I].Grp <= 0 then Continue;
        N := Length(FEnts[I].Poly);
        if N < 3 then Continue;
        { The outline AND every hole: a hole's edge bounds the solid as much
          as the outline does, or a picture frame reads as open. }
        SetLength(Loops, 1 + Length(FEnts[I].Holes));
        Loops[0] := FEnts[I].Poly;
        for J := 0 to High(FEnts[I].Holes) do Loops[J + 1] := FEnts[I].Holes[J];
        for LI := 0 to High(Loops) do
        begin
        N := Length(Loops[LI]);
        if N < 3 then Continue;
        for J := 0 to N - 1 do
        begin
          Key := IntToStr(FEnts[I].Grp) + '@' +
                 EKey(Loops[LI][J], Loops[LI][(J + 1) mod N], Way);
          K := Ix.FindIndexOf(Key);
          if K < 0 then
          begin
            Ix.Add(Key, Pointer(Way + 8));
            { in step with the hash, which appends, so entry n of one is
              entry n of the other }
            if Length(EdgeA) < Ix.Count then
            begin
              SetLength(EdgeA, Ix.Count * 2);
              SetLength(EdgeB, Ix.Count * 2);
              SetLength(EdgeG, Ix.Count * 2);
            end;
            EdgeA[Ix.Count - 1] := Loops[LI][J];
            EdgeB[Ix.Count - 1] := Loops[LI][(J + 1) mod N];
            EdgeG[Ix.Count - 1] := FEnts[I].Grp;
          end
          else Ix.Items[K] := Pointer(PtrInt(Ix.Items[K]) + Way);
        end;
        end;
      end;
      { an edge used once each way leaves its tally back at eight; anything
        else - used once, used twice the same way round, used three times -
        belongs to a shape that is not closed }
      SetLength(Suspect, Top + 1);
      for I := 0 to Top do Suspect[I] := False;
      for I := 0 to Ix.Count - 1 do
        if PtrInt(Ix.Items[I]) <> 8 then
        begin
          K := EdgeG[I];
          if (K > 0) and (K <= Top) then
          begin
            FClosedGrp[K] := False;
            Suspect[K] := True;
          end;
        end;

      { --- second chance: the same edge, cut into different lengths ------
        Once a roof face is divided, its side of a wall-roof seam is several
        short edges against the wall's one long one - a T-junction, still
        watertight.  For a group that failed, cut its edges at its own
        corners and count again.  Groups that passed never come here. }
      for K := 1 to Top do
      begin
        if not Suspect[K] then Continue;

        { the group's own corners }
        NV := 0;
        Jx := TFPHashList.Create;
        try
          for I := 0 to FLive - 1 do
          begin
            if (FEnts[I].Kind <> ekFace) or not FEnts[I].Solid then Continue;
            if FEnts[I].Grp <> K then Continue;
            SetLength(Loops, 1 + Length(FEnts[I].Holes));
            Loops[0] := FEnts[I].Poly;
            for J := 0 to High(FEnts[I].Holes) do Loops[J + 1] := FEnts[I].Holes[J];
            for LI := 0 to High(Loops) do
              for J := 0 to High(Loops[LI]) do
              begin
                Key := Format('%d,%d,%d', [Round(Loops[LI][J].X * 1E6),
                  Round(Loops[LI][J].Y * 1E6), Round(Loops[LI][J].Z * 1E6)]);
                if Jx.FindIndexOf(Key) >= 0 then Continue;
                Jx.Add(Key, Pointer(1));
                if NV >= Length(Verts) then SetLength(Verts, Max(64, NV * 2));
                Verts[NV] := Loops[LI][J];
                Inc(NV);
              end;
          end;
        finally
          Jx.Free;
        end;

        { how much work a second look would be: every edge of the group
          against every corner of it }
        NU := 0;
        for I := 0 to FLive - 1 do
          if (FEnts[I].Kind = ekFace) and FEnts[I].Solid and (FEnts[I].Grp = K) then
            Inc(NU, Length(FEnts[I].Poly));

        { a ceiling on it, so a big genuinely-broken shape cannot turn a
          frame into a minute proving what the first count already said }
        Budget := 4000000;
        if (NU = 0) or (NV = 0) or (Int64(NU) * NV > Budget) then Continue;

        { Count the group again from scratch with every edge cut at its
          corners; each piece is counted exactly as a whole edge would be. }
        Jx := TFPHashList.Create;
        try
          for I := 0 to FLive - 1 do
          begin
            if (FEnts[I].Kind <> ekFace) or not FEnts[I].Solid then Continue;
            if FEnts[I].Grp <> K then Continue;
            SetLength(Loops, 1 + Length(FEnts[I].Holes));
            Loops[0] := FEnts[I].Poly;
            for J := 0 to High(FEnts[I].Holes) do Loops[J + 1] := FEnts[I].Holes[J];
            for LI := 0 to High(Loops) do
            begin
            N := Length(Loops[LI]);
            if N < 3 then Continue;
            for J := 0 to N - 1 do
            begin
              PA := Loops[LI][J];
              PB := Loops[LI][(J + 1) mod N];
              NCut := 0;
              for C2 := 0 to NV - 1 do
                if Between(PA, PB, Verts[C2], T) then
                begin
                  if NCut >= Length(Cuts) then SetLength(Cuts, Max(8, NCut * 2));
                  Cuts[NCut] := T;
                  Inc(NCut);
                end;
              for C1 := 1 to NCut - 1 do
              begin
                TSwap := Cuts[C1];
                C2 := C1 - 1;
                while (C2 >= 0) and (Cuts[C2] > TSwap) do
                begin
                  Cuts[C2 + 1] := Cuts[C2];
                  Dec(C2);
                end;
                Cuts[C2 + 1] := TSwap;
              end;

              CutA := PA;
              for C1 := 0 to NCut do
              begin
                if C1 = NCut then CutB := PB
                else
                begin
                  T := Cuts[C1];
                  CutB := P3(PA.X + (PB.X - PA.X) * T,
                             PA.Y + (PB.Y - PA.Y) * T,
                             PA.Z + (PB.Z - PA.Z) * T);
                end;
                Key := EKey(CutA, CutB, Way);
                C2 := Jx.FindIndexOf(Key);
                if C2 < 0 then Jx.Add(Key, Pointer(Way + 8))
                else Jx.Items[C2] := Pointer(PtrInt(Jx.Items[C2]) + Way);
                CutA := CutB;
              end;
            end;
            end;
          end;

          Shut := Jx.Count > 0;
          for I := 0 to Jx.Count - 1 do
            if PtrInt(Jx.Items[I]) <> 8 then
            begin
              Shut := False;
              Break;
            end;
          if Shut then FClosedGrp[K] := True;
        finally
          Jx.Free;
        end;
      end;
    finally
      Ix.Free;
    end;
    { a group with no faces at all is not a closed solid either }
    SetLength(Seen, Top + 1);
    for I := 0 to High(Seen) do Seen[I] := 0;
    for I := 0 to FLive - 1 do
      if (FEnts[I].Kind = ekFace) and FEnts[I].Solid and (FEnts[I].Grp > 0) then
        Seen[FEnts[I].Grp] := 1;
    for I := 1 to Top do
      if Seen[I] = 0 then FClosedGrp[I] := False;
  end;
    Result := (G > 0) and (G < Length(FClosedGrp)) and FClosedGrp[G];
end;

function TWorkDoc.ZRange(out Lo, Hi: Double): Boolean;
var
  A, B: TP3;
begin
  Result := Bounds(A, B);
  if Result then
  begin
    Lo := A.Z;
    Hi := B.Z;
  end
  else
  begin
    Lo := 0;
    Hi := 0;
  end;
end;

{ One point as a key, on the same millionth grid as EdgeKeyOf, so corners
  reached by different arithmetic key alike. }
function PointKeyOf(const P: TP3): string;
begin
  Result := Format('%d|%d|%d', [Round(P.X * 1E6), Round(P.Y * 1E6),
                                Round(P.Z * 1E6)]);
end;

{ A key for the edge between two points, the same from either end, rounded
  to a millionth; Way says which way round this use ran. }
function EdgeKeyOf(const A, B: TP3; out Way: PtrInt): string;
var
  P, Q: array[0..2] of Int64;
  I: Integer;
  Swap: Boolean;
begin
  P[0] := Round(A.X * 1E6); P[1] := Round(A.Y * 1E6); P[2] := Round(A.Z * 1E6);
  Q[0] := Round(B.X * 1E6); Q[1] := Round(B.Y * 1E6); Q[2] := Round(B.Z * 1E6);
  Swap := False;
  for I := 0 to 2 do
    if P[I] <> Q[I] then
    begin
      Swap := P[I] > Q[I];
      Break;
    end;
  if Swap then Way := -1 else Way := 1;
  if Swap then
    Result := Format('%d,%d,%d|%d,%d,%d', [Q[0], Q[1], Q[2], P[0], P[1], P[2]])
  else
    Result := Format('%d,%d,%d|%d,%d,%d', [P[0], P[1], P[2], Q[0], Q[1], Q[2]]);
end;

{ Wind a loose face to point positively along whichever axis it is squarest
  to, so a dragged rectangle never faces down and gets culled after
  push/pull.  It needs no neighbors, so it copes where three faces meet an
  edge; roof slopes steeper than 45 degrees still come out mixed (see
  OrientLooseShells).  Solids are left alone. }
procedure OrientFace(var Pts: TP3Array);
var
  I, N: Integer;
  Acc, Nm: TP3;
  Tmp: TP3;
  D: Double;
begin
  N := Length(Pts);
  if N < 3 then Exit;
  Acc := P3(0, 0, 0);
  for I := 0 to N - 1 do
  begin
    Nm := Pts[(I + 1) mod N];
    Acc.X := Acc.X + (Pts[I].Y - Nm.Y) * (Pts[I].Z + Nm.Z);
    Acc.Y := Acc.Y + (Pts[I].Z - Nm.Z) * (Pts[I].X + Nm.X);
    Acc.Z := Acc.Z + (Pts[I].X - Nm.X) * (Pts[I].Y + Nm.Y);
  end;
  if (Abs(Acc.Z) >= Abs(Acc.X)) and (Abs(Acc.Z) >= Abs(Acc.Y)) then D := Acc.Z
  else if Abs(Acc.Y) >= Abs(Acc.X) then D := Acc.Y
  else D := Acc.X;
  if D >= 0 then Exit;
  for I := 0 to N div 2 - 1 do
  begin
    Tmp := Pts[I];
    Pts[I] := Pts[N - 1 - I];
    Pts[N - 1 - I] := Tmp;
  end;
end;

function TWorkDoc.OrientLooseShells(Part: Integer): Integer;
type
  TUse = record
    Face: Integer;   { slot in Cand, not an entity index }
    Dir: PtrInt;     { +1 if it ran the way the key is written, -1 if not }
  end;
var
  Cand: array of Integer;         { entity index of each slot }
  Slot: array of Integer;         { slot of each entity, -1 if not a candidate }
  Flip: array of Boolean;
  Comp: array of Integer;
  UseA, UseB: array of TUse;      { the one or two faces on each edge }
  NUse: array of Integer;
  Ix: TFPHashList;
  Queue: array of Integer;
  Members: array of Integer;
  I, J, K, N, NC, E, Head, Tail, NComp, NMem, Other: Integer;
  Key: string;
  Way: PtrInt;
  Nm, Cen, Acc, Mid: TP3;
  Vol, Sgn, Ar, W: Double;

  { twice the vector area, by Newell - the same sum OrientFace uses, which
    points along the face's normal and is as long as twice its area }
  function Newell(const Pts: TP3Array): TP3;
  var
    M, Cnt: Integer;
    Q: TP3;
  begin
    Result := P3(0, 0, 0);
    Cnt := Length(Pts);
    for M := 0 to Cnt - 1 do
    begin
      Q := Pts[(M + 1) mod Cnt];
      Result.X := Result.X + (Pts[M].Y - Q.Y) * (Pts[M].Z + Q.Z);
      Result.Y := Result.Y + (Pts[M].Z - Q.Z) * (Pts[M].X + Q.X);
      Result.Z := Result.Z + (Pts[M].X - Q.X) * (Pts[M].Y + Q.Y);
    end;
  end;

  function Middle(const Pts: TP3Array): TP3;
  var
    M, Cnt: Integer;
  begin
    Result := P3(0, 0, 0);
    Cnt := Length(Pts);
    if Cnt = 0 then Exit;
    for M := 0 to Cnt - 1 do
    begin
      Result.X := Result.X + Pts[M].X;
      Result.Y := Result.Y + Pts[M].Y;
      Result.Z := Result.Z + Pts[M].Z;
    end;
    Result.X := Result.X / Cnt;
    Result.Y := Result.Y / Cnt;
    Result.Z := Result.Z / Cnt;
  end;

  { which way this face runs along that edge, allowing for a pending turn }
  function DirOf(const U: TUse): Integer;
  begin
    if Flip[U.Face] then Result := -U.Dir else Result := U.Dir;
  end;

begin
  Result := 0;
  SetLength(Slot, FLive);
  for I := 0 to FLive - 1 do Slot[I] := -1;
  NC := 0;
  for I := 0 to FLive - 1 do
  begin
    if FEnts[I].Kind <> ekFace then Continue;
    if FEnts[I].Solid then Continue;          { a made solid winds itself }
    if FEnts[I].Part <> Part then Continue;   { another group's faces are not neighbors }
    if Length(FEnts[I].Poly) < 3 then Continue;
    if NC >= Length(Cand) then SetLength(Cand, Max(32, NC * 2));
    Cand[NC] := I;
    Slot[I] := NC;
    Inc(NC);
  end;
  if NC < 2 then Exit;
  SetLength(Cand, NC);
  SetLength(Flip, NC);
  SetLength(Comp, NC);
  for I := 0 to NC - 1 do
  begin
    Flip[I] := False;
    Comp[I] := -1;
  end;

  { every edge, and the one or two candidate faces along it }
  Ix := TFPHashList.Create;
  try
    SetLength(UseA, 0);
    for I := 0 to NC - 1 do
    begin
      N := Length(FEnts[Cand[I]].Poly);
      for J := 0 to N - 1 do
      begin
        Key := EdgeKeyOf(FEnts[Cand[I]].Poly[J],
                         FEnts[Cand[I]].Poly[(J + 1) mod N], Way);
        K := Ix.FindIndexOf(Key);
        if K < 0 then
        begin
          Ix.Add(Key, Pointer(PtrInt(Ix.Count) + 1));
          E := Ix.Count - 1;
          if E >= Length(UseA) then
          begin
            SetLength(UseA, Max(64, (E + 1) * 2));
            SetLength(UseB, Length(UseA));
            SetLength(NUse, Length(UseA));
          end;
          NUse[E] := 1;
          UseA[E].Face := I;
          UseA[E].Dir := Way;
        end
        else
        begin
          E := PtrInt(Ix.Items[K]) - 1;
          if NUse[E] = 1 then
          begin
            UseB[E].Face := I;
            UseB[E].Dir := Way;
          end;
          Inc(NUse[E]);
        end;
      end;
    end;

    { settle each connected sheet from one face outwards }
    SetLength(Queue, NC);
    SetLength(Members, NC);
    NComp := 0;
    for I := 0 to NC - 1 do
    begin
      if Comp[I] >= 0 then Continue;
      Inc(NComp);
      Head := 0; Tail := 0;
      Queue[Tail] := I; Inc(Tail);
      Comp[I] := NComp;
      NMem := 0;
      while Head < Tail do
      begin
        K := Queue[Head]; Inc(Head);
        Members[NMem] := K; Inc(NMem);
        N := Length(FEnts[Cand[K]].Poly);
        for J := 0 to N - 1 do
        begin
          Key := EdgeKeyOf(FEnts[Cand[K]].Poly[J],
                           FEnts[Cand[K]].Poly[(J + 1) mod N], Way);
          E := Ix.FindIndexOf(Key);
          if E < 0 then Continue;
          E := PtrInt(Ix.Items[E]) - 1;
          { only where exactly two faces meet - three has no answer }
          if NUse[E] <> 2 then Continue;
          if UseA[E].Face = K then Other := UseB[E].Face
          else Other := UseA[E].Face;
          if Other = K then Continue;
          if Comp[Other] >= 0 then Continue;
          { neighbors agree about out when they run the shared edge
            opposite ways }
          if UseA[E].Face = K then
            Flip[Other] := (DirOf(UseA[E]) = UseB[E].Dir)
          else
            Flip[Other] := (DirOf(UseB[E]) = UseA[E].Dir);
          Comp[Other] := NComp;
          Queue[Tail] := Other; Inc(Tail);
        end;
      end;

      if NMem < 2 then Continue;

      { and which way round the settled sheet goes.  If it holds a volume,
        that decides it; if it does not - a roof with no underside - point
        its faces away from the middle of it, weighted by how big they are so
        a scrap of a face cannot outvote a wall. }
      Cen := P3(0, 0, 0);
      for J := 0 to NMem - 1 do
      begin
        Mid := Middle(FEnts[Cand[Members[J]]].Poly);
        Cen.X := Cen.X + Mid.X / NMem;
        Cen.Y := Cen.Y + Mid.Y / NMem;
        Cen.Z := Cen.Z + Mid.Z / NMem;
      end;
      Vol := 0;
      W := 0;
      for J := 0 to NMem - 1 do
      begin
        K := Members[J];
        Acc := Newell(FEnts[Cand[K]].Poly);
        if Flip[K] then Acc := P3(-Acc.X, -Acc.Y, -Acc.Z);
        Mid := Middle(FEnts[Cand[K]].Poly);
        Vol := Vol + (Mid.X * Acc.X + Mid.Y * Acc.Y + Mid.Z * Acc.Z) / 6;
        Ar := Sqrt(Acc.X * Acc.X + Acc.Y * Acc.Y + Acc.Z * Acc.Z) / 2;
        Nm := Sub3(Mid, Cen);
        W := W + Ar * (Nm.X * Acc.X + Nm.Y * Acc.Y + Nm.Z * Acc.Z);
      end;
      if Abs(Vol) > 1E-6 then Sgn := Vol else Sgn := W;
      if Sgn < 0 then
        for J := 0 to NMem - 1 do
          Flip[Members[J]] := not Flip[Members[J]];
    end;
  finally
    Ix.Free;
  end;

  for I := 0 to NC - 1 do
    if Flip[I] then
    begin
      ReverseFace(Cand[I]);
      Inc(Result);
    end;
end;

{ Turns a face over, holes and all.  The winding rules are guesses - the two
  ends of a barn are back to back - so the person looking at it gets the
  last word, as in SketchUp. }
function TWorkDoc.ReverseFace(Index: Integer): Boolean;

  procedure Flip(var Loop: array of TP3);
  var
    I, N: Integer;
    T: TP3;
  begin
    N := Length(Loop);
    for I := 0 to N div 2 - 1 do
    begin
      T := Loop[I];
      Loop[I] := Loop[N - 1 - I];
      Loop[N - 1 - I] := T;
    end;
  end;

var
  K: Integer;
begin
  Result := False;
  if (Index < 0) or (Index >= FLive) then Exit;
  if FEnts[Index].Kind <> ekFace then Exit;
  if Length(FEnts[Index].Poly) < 3 then Exit;
  Flip(FEnts[Index].Poly);
  for K := 0 to High(FEnts[Index].Holes) do
    Flip(FEnts[Index].Holes[K]);
  FEnts[Index].A := FEnts[Index].Poly[0];
  FEnts[Index].B := FEnts[Index].Poly[High(FEnts[Index].Poly)];
  FOnFaceOK := False;
  Inc(FEditSeq);
  Result := True;
end;

{ Adds the polygon exactly as given.  Solids build their windings on purpose,
  so they come this way round. }
procedure TWorkDoc.AddFaceRaw(const Pts: array of TP3; Ink: TColor; Solid: Boolean);
var
  I: Integer;
begin
  if Length(Pts) < 3 then Exit;
  Room;
  Finalize(FEnts[FLive]);
  FillChar(FEnts[FLive], SizeOf(TWorkEnt), 0);
  FEnts[FLive].Kind := ekFace;
  FEnts[FLive].Part := FStamp;
  SetLength(FEnts[FLive].Poly, Length(Pts));
  for I := 0 to High(Pts) do
    FEnts[FLive].Poly[I] := Pts[I];
  FEnts[FLive].A := Pts[0];
  FEnts[FLive].B := Pts[High(Pts)];
  FEnts[FLive].Ink := Ink;
  FEnts[FLive].Weight := 1;
  FEnts[FLive].Solid := Solid;
  Inc(FLive);
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

procedure TWorkDoc.AddFace(const Pts: array of TP3; Ink: TColor; Solid: Boolean);
var
  I: Integer;
  Fixed: TP3Array;
begin
  if Length(Pts) < 3 then Exit;
  if Solid then
  begin
    AddFaceRaw(Pts, Ink, Solid);
    Exit;
  end;
  SetLength(Fixed, Length(Pts));
  for I := 0 to High(Pts) do Fixed[I] := Pts[I];
  OrientFace(Fixed);
  AddFaceRaw(Fixed, Ink, Solid);
end;

function TWorkDoc.NoteSize(Index: Integer): Single;
begin
  Result := 1;
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekText) then Exit;
  if FEnts[Index].Size > 0 then Result := FEnts[Index].Size;
end;

procedure TWorkDoc.SetNoteSize(Index: Integer; Factor: Single);
begin
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekText) then Exit;
  { half normal to four times it - smaller cannot be read and bigger is a
    poster, not a note }
  if Factor < 0.5 then Factor := 0.5;
  if Factor > 4 then Factor := 4;
  FEnts[Index].Size := Factor;
end;

procedure TWorkDoc.FlipFace(Index: Integer);
var
  I, H, N: Integer;
  T: TP3Array;
begin
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekFace) then Exit;
  N := Length(FEnts[Index].Poly);
  SetLength(T, N);
  for I := 0 to N - 1 do T[I] := FEnts[Index].Poly[N - 1 - I];
  FEnts[Index].Poly := T;
  for H := 0 to High(FEnts[Index].Holes) do
  begin
    N := Length(FEnts[Index].Holes[H]);
    SetLength(T, N);
    for I := 0 to N - 1 do T[I] := FEnts[Index].Holes[H][N - 1 - I];
    FEnts[Index].Holes[H] := T;
  end;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

procedure TWorkDoc.SetSoft(Index: Integer; Soft: Boolean);
begin
  if (Index < 0) or (Index >= FLive) then Exit;
  FEnts[Index].Soft := Soft;
end;

procedure TWorkDoc.SetInk(Index: Integer; Ink: TColor);
begin
  if (Index < 0) or (Index >= FLive) then Exit;
  FEnts[Index].Ink := Ink;
end;

procedure TWorkDoc.SetWeight(Index: Integer; Weight: Single);
begin
  if (Index < 0) or (Index >= FLive) then Exit;
  FEnts[Index].Weight := Weight;
end;

procedure TWorkDoc.SetMaterial(Index: Integer; C: TColor);
begin
  if (Index < 0) or (Index >= FLive) then Exit;
  if FEnts[Index].Kind <> ekFace then Exit;
  FEnts[Index].MatSet := True;
  FEnts[Index].Mat := C;
end;

procedure TWorkDoc.ClearMaterial(Index: Integer);
begin
  if (Index < 0) or (Index >= FLive) then Exit;
  FEnts[Index].MatSet := False;
  FEnts[Index].Mat := 0;
end;

function TWorkDoc.Material(Index: Integer; out C: TColor): Boolean;
begin
  C := 0;
  Result := (Index >= 0) and (Index < FLive) and (FEnts[Index].Kind = ekFace)
    and FEnts[Index].MatSet;
  if Result then C := FEnts[Index].Mat;
end;

procedure TWorkDoc.SetDimOffset(Index: Integer; const Off: TP3);
begin
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekDim) then Exit;
  FEnts[Index].C := Off;
end;

{ A point set that answers "is P one of these, within a hair" in one hash
  lookup.  Hashed on a coarse grid, with the neighboring cells checked too so
  a point just over a cell edge is found.  Moving and turning ask this for
  every corner against every moving corner. }
type
  TPointSet = class
  private
    FMap: TFPHashList;
    FLists: array of TP3Array;
    function KeyAt(X, Y, Z: Int64): shortstring;
  public
    constructor Create(const Pts: TP3Array);
    destructor Destroy; override;
    function Has(const P: TP3; Tol: Double): Boolean;
  end;

const
  PSET_CELL = 1E-5;

function TPointSet.KeyAt(X, Y, Z: Int64): shortstring;
var
  Q: array[0..2] of Int64;
begin
  Q[0] := X; Q[1] := Y; Q[2] := Z;
  SetLength(Result, 24);
  Move(Q[0], Result[1], 24);
end;

constructor TPointSet.Create(const Pts: TP3Array);
var
  I, Ix: Integer;
  K: shortstring;
begin
  FMap := TFPHashList.Create;
  for I := 0 to High(Pts) do
  begin
    K := KeyAt(Floor(Pts[I].X / PSET_CELL), Floor(Pts[I].Y / PSET_CELL), Floor(Pts[I].Z / PSET_CELL));
    { the item is the list's index plus one: TFPHashList takes a nil item
      for an empty slot and will not find it again }
    Ix := FMap.FindIndexOf(K);
    if Ix < 0 then
    begin
      SetLength(FLists, Length(FLists) + 1);
      Ix := High(FLists);
      FMap.Add(K, Pointer(PtrInt(Ix + 1)));
    end
    else
      Ix := PtrInt(FMap.Items[Ix]) - 1;
    SetLength(FLists[Ix], Length(FLists[Ix]) + 1);
    FLists[Ix][High(FLists[Ix])] := Pts[I];
  end;
end;

destructor TPointSet.Destroy;
begin
  FMap.Free;
  inherited;
end;

function TPointSet.Has(const P: TP3; Tol: Double): Boolean;
var
  X, Y, Z, DX, DY, DZ: Int64;
  Ix, J: Integer;
begin
  Result := False;
  X := Floor(P.X / PSET_CELL); Y := Floor(P.Y / PSET_CELL); Z := Floor(P.Z / PSET_CELL);
  for DX := -1 to 1 do
    for DY := -1 to 1 do
      for DZ := -1 to 1 do
      begin
        Ix := FMap.FindIndexOf(KeyAt(X + DX, Y + DY, Z + DZ));
        if Ix < 0 then Continue;
        Ix := PtrInt(FMap.Items[Ix]) - 1;
        for J := 0 to High(FLists[Ix]) do
          if Dist(P, FLists[Ix][J]) < Tol then Exit(True);
      end;
end;

{ Arcs whose points are all corners of the profile are its own edges: when
  the face is consumed they become soft seams of the solid, or they would
  stay drawn as a hard ring across it. }
procedure TWorkDoc.MarkProfileArcs(const Poly: TP3Array; G: Integer);
var
  I, K: Integer;
  Pts: TP3Array;
  Corners: TPointSet;
  All: Boolean;
begin
  Corners := TPointSet.Create(Poly);
  try
    for I := 0 to FLive - 1 do
      if FEnts[I].Kind = ekArc then
      begin
        EdgePoints(I, Pts);
        if Length(Pts) < 2 then Continue;
        All := True;
        for K := 0 to High(Pts) do
          if not Corners.Has(Pts[K], 1E-6) then
          begin
            All := False;
            Break;
          end;
        if All then
        begin
          SetSoft(I, True);
          SetGroup(I, G);
        end;
      end;
  finally
    Corners.Free;
  end;
end;

function TWorkDoc.Revolve(Face: Integer; const AxisP, AxisDir: TP3; Angle: Double;
  Steps: Integer): Integer;
const
  { the turn in the profile at a vertex below which the ring it sweeps is a
    soft edge - the creases of a curve rather than a corner }
  SOFT_TURN = 30 * Pi / 180;
var
  Poly: TP3Array;
  N, S, K, K2, G, I, First: Integer;
  Full: Boolean;
  Ax, Nf, Cen, Side, E, Mid, Out, Tang, PrevE: TP3;
  Rings: array of array of TP3;
  Quad: array of TP3;
  OnAxis: array of Boolean;
  Turn: Double;
  Q: array[0..3] of TP3;

  function Rot(const P: TP3; S: Integer): TP3;
  begin
    Result := RotP(P, AxisP, Ax, Angle * S / Steps);
  end;

  function Near(const A, B: TP3): Boolean;
  begin
    Result := Dist(A, B) < 1E-9;
  end;

  procedure FaceOut(const Pts: array of TP3; const Want: TP3);
  begin
    AddFaceRaw(Pts, FEnts[Face].Ink, True);
    { the sweep is made of the profile, so it is made of what the profile is
      painted with - the pen came across already }
    if FEnts[Face].MatSet then SetMaterial(FLive - 1, FEnts[Face].Mat);
    SetFaceGroup(FLive - 1, G);
    if Dot3(FaceNormal(FLive - 1), Want) < 0 then FlipFace(FLive - 1);
  end;

  procedure Edge(const A, B: TP3; Soft: Boolean);
  begin
    if Near(A, B) then Exit;
    AddLine(A, B, FEnts[Face].Ink, FEnts[Face].Weight, False);
    SetGroup(FLive - 1, G);
    SetSoft(FLive - 1, Soft);
  end;

  { the line already in the drawing between two points, if there is one }
  function LineAt(const A, B: TP3): Integer;
  var
    J: Integer;
  begin
    Result := -1;
    for J := 0 to FLive - 1 do
      if (FEnts[J].Kind = ekLine) and
         ((Near(FEnts[J].A, A) and Near(FEnts[J].B, B)) or
          (Near(FEnts[J].A, B) and Near(FEnts[J].B, A))) then Exit(J);
  end;

begin
  Result := -1;
  if (Face < 0) or (Face >= FLive) or (FEnts[Face].Kind <> ekFace) then Exit;
  if (Steps < 1) or (Abs(Angle) < 1E-9) then Exit;
  Ax := Norm3(AxisDir);
  if Dist(Ax, P3(0, 0, 0)) < 1E-9 then Exit;
  Poly := Copy(FEnts[Face].Poly);
  N := Length(Poly);
  if N < 3 then Exit;
  Full := Abs(Angle) >= 2 * Pi - 1E-9;
  Nf := FaceNormal(Face);
  Cen := P3(0, 0, 0);
  for K := 0 to N - 1 do Cen := P3(Cen.X + Poly[K].X / N, Cen.Y + Poly[K].Y / N, Cen.Z + Poly[K].Z / N);
  { which way the sweep moves off the profile: along the tangent of the
    turn at the profile's middle }
  Tang := Cross3(Ax, Sub3(Cen, AxisP));
  if Angle < 0 then Tang := P3(-Tang.X, -Tang.Y, -Tang.Z);
  First := FLive;
  G := NewGroup;
  { every profile point at every step }
  SetLength(Rings, Steps + 1);
  SetLength(OnAxis, N);
  for K := 0 to N - 1 do
  begin
    E := Sub3(Poly[K], AxisP);
    E := P3(E.X - Ax.X * Dot3(E, Ax), E.Y - Ax.Y * Dot3(E, Ax), E.Z - Ax.Z * Dot3(E, Ax));
    OnAxis[K] := Dist(E, P3(0, 0, 0)) < 1E-9;
  end;
  for S := 0 to Steps do
  begin
    SetLength(Rings[S], N);
    for K := 0 to N - 1 do Rings[S][K] := Rot(Poly[K], S);
  end;
  { the surface: one strip of gores per profile edge, wound to face the way
    the profile's edge faces - away from the inside of the profile }
  for K := 0 to N - 1 do
  begin
    K2 := (K + 1) mod N;
    if OnAxis[K] and OnAxis[K2] then Continue;
    E := Sub3(Poly[K2], Poly[K]);
    { Which way is out of the profile at this edge: the edge crossed into the
      Newell normal.  That holds for a concave profile too, where pointing
      away from the middle fails - a thin C like a wine glass. }
    Side := Norm3(Cross3(E, Nf));
    for S := 0 to Steps - 1 do
    begin
      Q[0] := Rings[S][K]; Q[1] := Rings[S][K2]; Q[2] := Rings[S + 1][K2]; Q[3] := Rings[S + 1][K];
      { a point on the axis stays put, so the gore there is a triangle }
      SetLength(Quad, 0);
      for I := 0 to 3 do
        if (Length(Quad) = 0) or not Near(Quad[High(Quad)], Q[I]) then
        begin
          SetLength(Quad, Length(Quad) + 1);
          Quad[High(Quad)] := Q[I];
        end;
      if (Length(Quad) > 1) and Near(Quad[0], Quad[High(Quad)]) then SetLength(Quad, Length(Quad) - 1);
      if Length(Quad) < 3 then Continue;
      Out := RotV(Side, Ax, Angle * (S + 0.5) / Steps);
      FaceOut(Quad, Out);
      { the seam between this gore and the next, soft: a crease of the curve }
      if (S > 0) or Full then
        Edge(Rings[S][K], Rings[S][K2], True);
    end;
  end;
  { the rings each profile point sweeps: hard where the profile has a corner
    there, soft where it only bends a little }
  for K := 0 to N - 1 do
  begin
    if OnAxis[K] then Continue;
    K2 := (K + 1) mod N;
    PrevE := Norm3(P3(Poly[K].X - Poly[(K + N - 1) mod N].X, Poly[K].Y - Poly[(K + N - 1) mod N].Y,
                      Poly[K].Z - Poly[(K + N - 1) mod N].Z));
    E := Norm3(Sub3(Poly[K2], Poly[K]));
    Turn := ArcCos(EnsureRange(Dot3(PrevE, E), -1.0, 1.0));
    for S := 0 to Steps - 1 do
      Edge(Rings[S][K], Rings[S + 1][K], Turn < SOFT_TURN);
  end;
  if Full then
  begin
    { the profile's own edges are now a seam of the surface }
    for K := 0 to N - 1 do
    begin
      I := LineAt(Poly[K], Poly[(K + 1) mod N]);
      if I >= 0 then
      begin
        SetGroup(I, G);
        SetSoft(I, True);
      end;
    end;
    MarkProfileArcs(Poly, G);
    Delete(Face);
    if Face < First then Dec(First);
  end
  else
  begin
    { the profile is one cap, facing back against the sweep; the far end is
      the other, facing on }
    FEnts[Face].Solid := True;
    SetFaceGroup(Face, G);
    if Dot3(FaceNormal(Face), Tang) > 0 then FlipFace(Face);
    FaceOut(Rings[Steps], RotV(Tang, Ax, Angle));
    for K := 0 to N - 1 do
      Edge(Rings[Steps][K], Rings[Steps][(K + 1) mod N], False);
    for K := 0 to N - 1 do
    begin
      I := LineAt(Poly[K], Poly[(K + 1) mod N]);
      if I >= 0 then SetGroup(I, G);
    end;
  end;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
  Result := First;
end;

procedure TWorkDoc.EdgePoints(I: Integer; out Pts: TP3Array);
var
  K, N: Integer;
begin
  Pts := nil;
  if (I < 0) or (I >= FLive) then Exit;
  case FEnts[I].Kind of
    ekLine:
      begin
        SetLength(Pts, 2);
        Pts[0] := FEnts[I].A;
        Pts[1] := FEnts[I].B;
      end;
    ekArc:
      begin
        N := ArcSteps(FEnts[I]);
        SetLength(Pts, N + 1);
        for K := 0 to N do
          if FEnts[I].Plane = plFree then
            Pts[K] := ArcPoint(FEnts[I].C, FEnts[I].R, FEnts[I].A0 + FEnts[I].Sweep * K / N,
              FEnts[I].Plane, FEnts[I].Nm)
          else
            Pts[K] := ArcPoint(FEnts[I].C, FEnts[I].R, FEnts[I].A0 + FEnts[I].Sweep * K / N,
              FEnts[I].Plane);
      end;
  end;
end;

function TWorkDoc.Sweep(Face: Integer; const Path: TP3Array; Closed: Boolean;
  Caps: Boolean): Integer;
const
  SOFT_TURN = 30 * Pi / 180;
var
  Poly: TP3Array;
  Pts: TP3Array;
  N, M, S, K, K2, G, I, First: Integer;
  Rings: array of array of TP3;
  DirIn, DirOut, B, Q, Cen, E, PrevE, Out, RingCen: TP3;
  T, Turn: Double;
  Hard: array of Boolean;

  function Near(const A, C: TP3): Boolean;
  begin
    Result := Dist(A, C) < 1E-9;
  end;


  procedure FaceOut(const P: array of TP3; const Want: TP3);
  begin
    AddFaceRaw(P, FEnts[Face].Ink, True);
    if FEnts[Face].MatSet then SetMaterial(FLive - 1, FEnts[Face].Mat);
    SetFaceGroup(FLive - 1, G);
    if Dot3(FaceNormal(FLive - 1), Want) < 0 then FlipFace(FLive - 1);
  end;

  procedure Edge(const A, C: TP3; Soft: Boolean);
  begin
    if Near(A, C) then Exit;
    AddLine(A, C, FEnts[Face].Ink, FEnts[Face].Weight, False);
    SetGroup(FLive - 1, G);
    SetSoft(FLive - 1, Soft);
  end;

  function LineAt(const A, C: TP3): Integer;
  var
    J: Integer;
  begin
    Result := -1;
    for J := 0 to FLive - 1 do
      if (FEnts[J].Kind = ekLine) and
         ((Near(FEnts[J].A, A) and Near(FEnts[J].B, C)) or
          (Near(FEnts[J].A, C) and Near(FEnts[J].B, A))) then Exit(J);
  end;

  { where the line through P along D meets the plane through O with normal Nm }
  function Meet(const P, D, O, Nm: TP3): TP3;
  var
    Den: Double;
  begin
    Den := Dot3(D, Nm);
    if Abs(Den) < 1E-12 then Exit(P);
    T := Dot3(Sub3(O, P), Nm) / Den;
    Result := P3(P.X + D.X * T, P.Y + D.Y * T, P.Z + D.Z * T);
  end;

begin
  Result := -1;
  if (Face < 0) or (Face >= FLive) or (FEnts[Face].Kind <> ekFace) then Exit;
  { the path without repeated points }
  Pts := nil;
  for I := 0 to High(Path) do
    if (Length(Pts) = 0) or not Near(Pts[High(Pts)], Path[I]) then
    begin
      SetLength(Pts, Length(Pts) + 1);
      Pts[High(Pts)] := Path[I];
    end;
  M := Length(Pts);
  if Closed and (M > 1) and Near(Pts[0], Pts[M - 1]) then
  begin
    SetLength(Pts, M - 1);
    M := M - 1;
  end;
  if (M < 2) or (Closed and (M < 3)) then Exit;
  Poly := Copy(FEnts[Face].Poly);
  N := Length(Poly);
  if N < 3 then Exit;
  First := FLive;
  G := NewGroup;
  { The profile at every path point.  Along each leg the points travel with
    the leg; at a corner they are cut off on the plane that halves the
    corner, which is the mitre - so the ring there is the same ring seen
    from either leg.  A closed path has a mitre at its start too. }
  if Closed then SetLength(Rings, M + 1) else SetLength(Rings, M);
  SetLength(Hard, Length(Rings));
  Rings[0] := Copy(Poly);
  Hard[0] := True;
  for S := 1 to High(Rings) do
  begin
    SetLength(Rings[S], N);
    DirIn := Norm3(Sub3(Pts[S mod M], Pts[(S - 1) mod M]));
    if Closed or (S < M - 1) then
    begin
      DirOut := Norm3(Sub3(Pts[(S + 1) mod M], Pts[S mod M]));
      B := Add3(DirIn, DirOut);
      if Dist(B, P3(0, 0, 0)) < 1E-9 then B := DirIn else B := Norm3(B);
      Turn := ArcCos(EnsureRange(Dot3(DirIn, DirOut), -1.0, 1.0));
    end
    else
    begin
      B := DirIn;
      Turn := Pi;
    end;
    Hard[S] := Turn >= SOFT_TURN;
    for K := 0 to N - 1 do
      Rings[S][K] := Meet(Rings[S - 1][K], DirIn, Pts[S mod M], B);
  end;
  if Closed then
  begin
    { the ring at the start, mitred like the rest, replaces the profile as
      drawn - which sat square to nothing in particular }
    Rings[0] := Copy(Rings[M]);
    Hard[0] := Hard[M];
  end;
  { the surface: a strip of quads per profile edge, each facing away from
    the middle of its own ring }
  for S := 0 to High(Rings) - 1 do
  begin
    RingCen := P3(0, 0, 0);
    for K := 0 to N - 1 do
      RingCen := P3(RingCen.X + (Rings[S][K].X + Rings[S + 1][K].X) / (2 * N),
                    RingCen.Y + (Rings[S][K].Y + Rings[S + 1][K].Y) / (2 * N),
                    RingCen.Z + (Rings[S][K].Z + Rings[S + 1][K].Z) / (2 * N));
    for K := 0 to N - 1 do
    begin
      K2 := (K + 1) mod N;
      Q := P3((Rings[S][K].X + Rings[S][K2].X + Rings[S + 1][K2].X + Rings[S + 1][K].X) / 4,
              (Rings[S][K].Y + Rings[S][K2].Y + Rings[S + 1][K2].Y + Rings[S + 1][K].Y) / 4,
              (Rings[S][K].Z + Rings[S][K2].Z + Rings[S + 1][K2].Z + Rings[S + 1][K].Z) / 4);
      Out := Sub3(Q, RingCen);
      FaceOut([Rings[S][K], Rings[S][K2], Rings[S + 1][K2], Rings[S + 1][K]], Out);
    end;
    { the seam at the far ring: hard at a corner, soft along a curve }
    if (S + 1 <= High(Rings)) and (Closed or (S + 1 < High(Rings))) then
      for K := 0 to N - 1 do
        Edge(Rings[S + 1][K], Rings[S + 1][(K + 1) mod N], not Hard[S + 1]);
  end;
  { the lines each profile corner draws along the path: hard where the
    profile has a corner, soft where it only bends }
  for K := 0 to N - 1 do
  begin
    K2 := (K + 1) mod N;
    PrevE := Norm3(Sub3(Poly[K], Poly[(K + N - 1) mod N]));
    E := Norm3(Sub3(Poly[K2], Poly[K]));
    Turn := ArcCos(EnsureRange(Dot3(PrevE, E), -1.0, 1.0));
    for S := 0 to High(Rings) - 1 do
      Edge(Rings[S][K], Rings[S + 1][K], Turn < SOFT_TURN);
  end;
  if Closed then
  begin
    for K := 0 to N - 1 do
    begin
      I := LineAt(Poly[K], Poly[(K + 1) mod N]);
      if I >= 0 then Delete(I);
    end;
    { the profile's own edges and face are gone; the start ring, mitred, is
      drawn in their place }
    for K := 0 to N - 1 do
      Edge(Rings[0][K], Rings[0][(K + 1) mod N], not Hard[0]);
    MarkProfileArcs(Poly, G);
    for I := FLive - 1 downto 0 do
      if (FEnts[I].Kind = ekFace) and (I = Face) then Delete(I);
    First := -1;
    for I := 0 to FLive - 1 do
      if (FEnts[I].Kind = ekFace) and FEnts[I].Solid and (FEnts[I].Grp = G) then
      begin
        First := I;
        Break;
      end;
  end
  else if Caps then
  begin
    { the profile is the near cap; the far cap is the last ring }
    FEnts[Face].Solid := True;
    SetFaceGroup(Face, G);
    DirIn := Norm3(Sub3(Pts[1], Pts[0]));
    if Dot3(FaceNormal(Face), DirIn) > 0 then FlipFace(Face);
    FaceOut(Rings[High(Rings)], Norm3(Sub3(Pts[M - 1], Pts[M - 2])));
    for K := 0 to N - 1 do
      Edge(Rings[High(Rings)][K], Rings[High(Rings)][(K + 1) mod N], False);
    for K := 0 to N - 1 do
    begin
      I := LineAt(Poly[K], Poly[(K + 1) mod N]);
      if I >= 0 then SetGroup(I, G);
    end;
  end
  else
  begin
    { open at both ends, like a pipe: the rings at the ends are hard edges
      and the profile face goes, its edges staying as the near ring }
    for K := 0 to N - 1 do
      Edge(Rings[High(Rings)][K], Rings[High(Rings)][(K + 1) mod N], False);
    for K := 0 to N - 1 do
    begin
      I := LineAt(Poly[K], Poly[(K + 1) mod N]);
      if I >= 0 then SetGroup(I, G)
      else Edge(Poly[K], Poly[(K + 1) mod N], False);
    end;
    MarkProfileArcs(Poly, G);
    Delete(Face);
    if Face < First then Dec(First);
  end;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
  Result := First;
end;

procedure TWorkDoc.SetArcSides(Index, N: Integer);
begin
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekArc) then Exit;
  if (N < 3) or (N > 360) then N := 0;
  FEnts[Index].Sides := N;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

{ --- groups ------------------------------------------------------------- }

procedure TWorkDoc.SetContext(Id: Integer);
begin
  if (Id <> 0) and (PartEnt(Id) < 0) then Id := 0;
  FContext := Id;
  FStamp := Id;
  { which crates are offered to snap to depends on where you are }
  FSnapDirty := True;
  FOnFaceOK := False;
  Inc(FEditSeq);
end;

function TWorkDoc.NewPart(const Name: string; Parent: Integer): Integer;
begin
  Inc(FNextPart);
  Result := FNextPart;
  Room;
  Finalize(FEnts[FLive]);
  FillChar(FEnts[FLive], SizeOf(TWorkEnt), 0);
  FEnts[FLive].Kind := ekPart;
  FEnts[FLive].Grp := Result;
  FEnts[FLive].Txt := Name;
  FEnts[FLive].Solid := False;
  FEnts[FLive].Part := Parent;
  Inc(FLive);
  Inc(FEditSeq);
end;

function TWorkDoc.PartEnt(Id: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  if Id <= 0 then Exit;
  for I := 0 to FLive - 1 do
    if (FEnts[I].Kind = ekPart) and (FEnts[I].Grp = Id) then Exit(I);
end;

function TWorkDoc.PartName(Id: Integer): string;
var
  E: Integer;
begin
  E := PartEnt(Id);
  if E < 0 then Result := '' else Result := FEnts[E].Txt;
  if Result = '' then Result := 'Group ' + IntToStr(Id);
end;

function TWorkDoc.PartLocked(Id: Integer): Boolean;
var
  E: Integer;
begin
  E := PartEnt(Id);
  Result := (E >= 0) and FEnts[E].Solid;
end;

function TWorkDoc.PartParent(Id: Integer): Integer;
var
  E: Integer;
begin
  E := PartEnt(Id);
  if E < 0 then Result := 0 else Result := FEnts[E].Part;
end;

procedure TWorkDoc.SetPartName(Id: Integer; const Name: string);
var
  E: Integer;
begin
  E := PartEnt(Id);
  if E < 0 then Exit;
  FEnts[E].Txt := Name;
  Inc(FEditSeq);
end;

procedure TWorkDoc.SetPartLocked(Id: Integer; Locked: Boolean);
var
  E: Integer;
begin
  E := PartEnt(Id);
  if E < 0 then Exit;
  FEnts[E].Solid := Locked;
  Inc(FEditSeq);
end;

procedure TWorkDoc.SetPartParent(Id, Parent: Integer);
var
  E: Integer;
begin
  E := PartEnt(Id);
  if (E < 0) or (Id = Parent) then Exit;
  FEnts[E].Part := Parent;
  Inc(FEditSeq);
end;

function TWorkDoc.PartHidden(Id: Integer): Boolean;
var
  E: Integer;
begin
  E := PartEnt(Id);
  Result := (E >= 0) and FEnts[E].Hidden;
end;

procedure TWorkDoc.SetPartHidden(Id: Integer; Hidden: Boolean);
var
  E: Integer;
begin
  E := PartEnt(Id);
  if (E < 0) or (FEnts[E].Hidden = Hidden) then Exit;
  FEnts[E].Hidden := Hidden;
  FSnapDirty := True;
  Inc(FEditSeq);
end;

function TWorkDoc.EntHidden(I: Integer): Boolean;
begin
  if (FHideSeq <> FEditSeq) or (Length(FHideOf) <> FLive) then WorkOutHidden;
  Result := FAnyHidden and (I >= 0) and (I < FLive) and FHideOf[I];
end;

{ Every group's answer from the groups above it, then every entity's from
  its group.  With nothing hidden it costs one walk of the list. }
procedure TWorkDoc.WorkOutHidden;
var
  I, Id, Up, Guard: Integer;
  Self_, Parent_: array of Integer;
  Down: array of ShortInt;       { 0 not known yet, 1 put away, 2 not }

  function Away(G: Integer): Boolean;
  begin
    Result := False;
    Guard := 0;
    Up := G;
    { up until an answer is known, a group put away, or the top - and a
      loop of parents, which a damaged file could hold, ends it }
    while (Up > 0) and (Up <= High(Down)) and (Guard < 1000) do
    begin
      if Down[Up] <> 0 then Exit(Down[Up] = 1);
      if (Self_[Up] >= 0) and FEnts[Self_[Up]].Hidden then Exit(True);
      Up := Parent_[Up];
      Inc(Guard);
    end;
  end;

begin
  FHideSeq := FEditSeq;
  SetLength(FHideOf, FLive);
  FAnyHidden := False;
  for I := 0 to FLive - 1 do
    if (FEnts[I].Kind = ekPart) and FEnts[I].Hidden then begin FAnyHidden := True; Break; end;
  if not FAnyHidden then Exit;
  SetLength(Self_, FNextPart + 1);
  SetLength(Parent_, FNextPart + 1);
  SetLength(Down, FNextPart + 1);
  for Id := 0 to FNextPart do begin Self_[Id] := -1; Parent_[Id] := 0; Down[Id] := 0; end;
  for I := 0 to FLive - 1 do
    if (FEnts[I].Kind = ekPart) and (FEnts[I].Grp > 0) and (FEnts[I].Grp <= FNextPart) then
    begin
      Self_[FEnts[I].Grp] := I;
      Parent_[FEnts[I].Grp] := FEnts[I].Part;
    end;
  for Id := 1 to FNextPart do
    if Away(Id) then Down[Id] := 1 else Down[Id] := 2;
  for I := 0 to FLive - 1 do
  begin
    if FEnts[I].Kind = ekPart then Id := FEnts[I].Grp else Id := FEnts[I].Part;
    FHideOf[I] := (Id > 0) and (Id <= FNextPart) and (Down[Id] = 1);
  end;
end;

procedure TWorkDoc.SetPart(Index, Id: Integer);
begin
  if (Index < 0) or (Index >= FLive) then Exit;
  if FEnts[Index].Kind = ekPart then Exit;      { a record moves by SetPartParent }
  FEnts[Index].Part := Id;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

function TWorkDoc.InsideContext(I: Integer): Boolean;
var
  P, Guard: Integer;
begin
  Result := True;
  if FContext = 0 then Exit;
  if (I < 0) or (I >= FLive) then Exit(False);
  { a group's own record stands for the group }
  if FEnts[I].Kind = ekPart then P := FEnts[I].Grp else P := FEnts[I].Part;
  Guard := 0;
  while (P <> 0) and (Guard < 1000) do
  begin
    if P = FContext then Exit(True);
    P := PartParent(P);
    Inc(Guard);
  end;
  Result := False;
end;

function TWorkDoc.TopPartIn(I: Integer): Integer;
var
  P, Up, Guard: Integer;
begin
  if (I < 0) or (I >= FLive) then Exit(-1);
  { a group's own record stands for the group, so a selection holding the
    record and every member reads as one group and not as one thing more }
  if FEnts[I].Kind = ekPart then P := FEnts[I].Grp else P := FEnts[I].Part;
  if P = FContext then Exit(0);
  Guard := 0;
  while (P <> 0) and (Guard < 1000) do
  begin
    Up := PartParent(P);
    if Up = FContext then Exit(P);
    P := Up;
    Inc(Guard);
  end;
  Result := -1;
end;

function TWorkDoc.PartLockedUp(Id: Integer): Boolean;
var
  Guard: Integer;
begin
  Result := False;
  Guard := 0;
  while (Id <> 0) and (Id <> FContext) and (Guard < 1000) do
  begin
    if PartLocked(Id) then Exit(True);
    Id := PartParent(Id);
    Inc(Guard);
  end;
end;

function TWorkDoc.PartMembers(Id: Integer; WithRecord: Boolean): TIntArrayW;
var
  I, N, P, Guard: Integer;
  In_: Boolean;
begin
  Result := nil;
  N := 0;
  if Id <= 0 then Exit;
  for I := 0 to FLive - 1 do
  begin
    if (FEnts[I].Kind = ekPart) and (FEnts[I].Grp = Id) then Continue;
    { in it, or in a group inside it }
    P := FEnts[I].Part;
    In_ := False;
    Guard := 0;
    while (P <> 0) and (Guard < 1000) do
    begin
      if P = Id then begin In_ := True; Break; end;
      P := PartParent(P);
      Inc(Guard);
    end;
    if not In_ then Continue;
    if N >= Length(Result) then SetLength(Result, Max(16, N * 2));
    Result[N] := I;
    Inc(N);
  end;
  if WithRecord then
  begin
    I := PartEnt(Id);
    if I >= 0 then
    begin
      if N >= Length(Result) then SetLength(Result, Max(16, N * 2));
      Result[N] := I;
      Inc(N);
    end;
  end;
  SetLength(Result, N);
end;

function TWorkDoc.PartBounds(Id: Integer; out Lo, Hi: TP3): Boolean;
var
  M: TIntArrayW;
  J, I, K, H: Integer;
  Steps: Integer;
  P: TP3;

  procedure Take(const Q: TP3);
  begin
    if not Result then
    begin
      Lo := Q; Hi := Q; Result := True;
      Exit;
    end;
    Lo := P3(Min(Lo.X, Q.X), Min(Lo.Y, Q.Y), Min(Lo.Z, Q.Z));
    Hi := P3(Max(Hi.X, Q.X), Max(Hi.Y, Q.Y), Max(Hi.Z, Q.Z));
  end;

begin
  Result := False;
  Lo := P3(0, 0, 0);
  Hi := Lo;
  M := PartMembers(Id, False);
  for J := 0 to High(M) do
  begin
    I := M[J];
    case FEnts[I].Kind of
      ekLine, ekGuide:
        begin
          Take(FEnts[I].A);
          Take(FEnts[I].B);
        end;
      ekArc:
        begin
          Steps := ArcSteps(FEnts[I]);
          for K := 0 to Steps do
          begin
            P := ArcPoint(FEnts[I].C, FEnts[I].R,
              FEnts[I].A0 + FEnts[I].Sweep * K / Steps, FEnts[I].Plane, FEnts[I].Nm);
            Take(P);
          end;
        end;
      ekFace:
        begin
          for K := 0 to High(FEnts[I].Poly) do Take(FEnts[I].Poly[K]);
          for H := 0 to High(FEnts[I].Holes) do
            for K := 0 to High(FEnts[I].Holes[H]) do Take(FEnts[I].Holes[H][K]);
        end;
      ekText, ekDim:
        begin
          Take(FEnts[I].A);
          if FEnts[I].Kind = ekDim then Take(FEnts[I].B);
        end;
    end;
  end;
end;

procedure TWorkDoc.RecountParts;
var
  I: Integer;
begin
  FNextPart := 0;
  for I := 0 to FLive - 1 do
    if (FEnts[I].Kind = ekPart) and (FEnts[I].Grp > FNextPart) then
      FNextPart := FEnts[I].Grp;
end;

{ A pen or fill, faded when it lies outside the open group, as SketchUp
  grays the rest of the model while you are inside one. }
function TWorkDoc.DimIf(I: Integer; const C: TPix): TPix;
begin
  if (FContext <> 0) and not InsideContext(I) then
    Result := MixPix(C, Pix(255, 255, 255), 0.62)
  else
    Result := C;
end;

function TWorkDoc.InkPix(I: Integer): TPix;
begin
  Result := DimIf(I, ColorToPix(FEnts[I].Ink));
end;

function TWorkDoc.NewGroup: Integer;
begin
  Inc(FNextGrp);
  Result := FNextGrp;
end;

procedure TWorkDoc.SetNaming(Index: Integer; const AName, ANote: string);
begin
  if (Index < 0) or (Index >= FLive) then Exit;
  FEnts[Index].Name := AName;
  FEnts[Index].Note := ANote;
end;

procedure TWorkDoc.SetSolidNaming(Index: Integer; const AName, ANote: string);
begin
  if (Index < 0) or (Index >= FLive) then Exit;
  FEnts[Index].SName := AName;
  FEnts[Index].SNote := ANote;
end;

procedure TWorkDoc.SetGroup(Index, G: Integer);
begin
  if (Index < 0) or (Index >= FLive) then Exit;
  FEnts[Index].Grp := G;
end;

function TWorkDoc.PartJig(Id: Integer): string;
var
  E: Integer;
begin
  E := PartEnt(Id);
  if E < 0 then Result := '' else Result := FEnts[E].Jig;
end;

procedure TWorkDoc.SetPartJig(Id: Integer; const Spec: string);
var
  E: Integer;
begin
  E := PartEnt(Id);
  if E < 0 then Exit;
  FEnts[E].Jig := Spec;
  Inc(FEditSeq);
end;

function TWorkDoc.PartData(Id: Integer): string;
var
  E: Integer;
begin
  E := PartEnt(Id);
  if E < 0 then Result := '' else Result := FEnts[E].Data;
end;

procedure TWorkDoc.SetPartData(Id: Integer; const Data: string);
var
  E: Integer;
begin
  E := PartEnt(Id);
  if E < 0 then Exit;
  FEnts[E].Data := Data;
  Inc(FEditSeq);
end;

procedure TWorkDoc.SetLineGroup(Index, G: Integer);
begin
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekLine) then Exit;
  FEnts[Index].Grp := G;
end;

procedure TWorkDoc.SetArcFacing(Index: Integer; const Nm: TP3; A0: Double);
begin
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekArc) then Exit;
  FEnts[Index].Plane := plFree;
  FEnts[Index].Nm := Nm;
  FEnts[Index].A0 := A0;
  FEnts[Index].A := ArcPoint(FEnts[Index].C, FEnts[Index].R, A0, plFree, Nm);
  FEnts[Index].B := ArcPoint(FEnts[Index].C, FEnts[Index].R, A0 + FEnts[Index].Sweep, plFree, Nm);
  FSnapDirty := True; Inc(FEditSeq);
end;

procedure TWorkDoc.SetFaceGroup(Index, G: Integer);
begin
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekFace) then Exit;
  FEnts[Index].Grp := G;
  FEnts[Index].Solid := True;
end;

{ Give the face just added the loops cut out of it. }
procedure TWorkDoc.SetFaceHoles(Index: Integer; const H: array of TP3Array);
var
  I, K: Integer;
begin
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekFace) then Exit;
  SetLength(FEnts[Index].Holes, Length(H));
  for I := 0 to High(H) do
  begin
    SetLength(FEnts[Index].Holes[I], Length(H[I]));
    for K := 0 to High(H[I]) do
      FEnts[Index].Holes[I][K] := H[I][K];
  end;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

{ Newell's method, which copes with slightly non-planar loops. }
function TWorkDoc.FaceNormal(Index: Integer): TP3;
var
  I, J, N: Integer;
  Acc: TP3;
begin
  Result := P3(0, 0, 1);
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekFace) then Exit;
  N := Length(FEnts[Index].Poly);
  if N < 3 then Exit;
  Acc := P3(0, 0, 0);
  for I := 0 to N - 1 do
  begin
    J := (I + 1) mod N;
    Acc.X := Acc.X + (FEnts[Index].Poly[I].Y - FEnts[Index].Poly[J].Y) *
                     (FEnts[Index].Poly[I].Z + FEnts[Index].Poly[J].Z);
    Acc.Y := Acc.Y + (FEnts[Index].Poly[I].Z - FEnts[Index].Poly[J].Z) *
                     (FEnts[Index].Poly[I].X + FEnts[Index].Poly[J].X);
    Acc.Z := Acc.Z + (FEnts[Index].Poly[I].X - FEnts[Index].Poly[J].X) *
                     (FEnts[Index].Poly[I].Y + FEnts[Index].Poly[J].Y);
  end;
  Result := Norm3(Acc);
end;

function TWorkDoc.FaceArea(Index: Integer): Double;
var
  I, J, N, H: Integer;
  Acc: TP3;
begin
  Result := 0;
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekFace) then Exit;
  N := Length(FEnts[Index].Poly);
  if N < 3 then Exit;
  Acc := P3(0, 0, 0);
  for I := 0 to N - 1 do
  begin
    J := (I + 1) mod N;
    Acc.X := Acc.X + FEnts[Index].Poly[I].Y * FEnts[Index].Poly[J].Z -
                     FEnts[Index].Poly[I].Z * FEnts[Index].Poly[J].Y;
    Acc.Y := Acc.Y + FEnts[Index].Poly[I].Z * FEnts[Index].Poly[J].X -
                     FEnts[Index].Poly[I].X * FEnts[Index].Poly[J].Z;
    Acc.Z := Acc.Z + FEnts[Index].Poly[I].X * FEnts[Index].Poly[J].Y -
                     FEnts[Index].Poly[I].Y * FEnts[Index].Poly[J].X;
  end;
  Result := Sqrt(Acc.X * Acc.X + Acc.Y * Acc.Y + Acc.Z * Acc.Z) / 2;

  { less the holes: a ring's area is the ring, and this is the number shown
    when it is clicked }
  for H := 0 to High(FEnts[Index].Holes) do
  begin
    N := Length(FEnts[Index].Holes[H]);
    if N < 3 then Continue;
    Acc := P3(0, 0, 0);
    for I := 0 to N - 1 do
    begin
      J := (I + 1) mod N;
      Acc.X := Acc.X + FEnts[Index].Holes[H][I].Y * FEnts[Index].Holes[H][J].Z -
                       FEnts[Index].Holes[H][I].Z * FEnts[Index].Holes[H][J].Y;
      Acc.Y := Acc.Y + FEnts[Index].Holes[H][I].Z * FEnts[Index].Holes[H][J].X -
                       FEnts[Index].Holes[H][I].X * FEnts[Index].Holes[H][J].Z;
      Acc.Z := Acc.Z + FEnts[Index].Holes[H][I].X * FEnts[Index].Holes[H][J].Y -
                       FEnts[Index].Holes[H][I].Y * FEnts[Index].Holes[H][J].X;
    end;
    Result := Result - Sqrt(Acc.X * Acc.X + Acc.Y * Acc.Y + Acc.Z * Acc.Z) / 2;
  end;
  if Result < 0 then Result := 0;
end;

{ Which face is under that pixel, and where on it.  Nearest by depth taken
  at the cursor, so coplanar faces tie exactly and the smaller one - the one
  on top - wins.  Memoized for the pixel, since one mouse move asks two or
  three times and each call ray-casts every face; any edit, camera or slice
  change clears it. }
function TWorkDoc.FaceUnder(const V: TProjector; SX, SY: Double;
  out Face: Integer; out Pt: TP3): Boolean;
var
  I, J, K, N, M, HK: Integer;
  Inside: Boolean;
  P, HP: array of TPointF;
  Look, Org, U, W, Hit: TP3;
  P0, P1, P2: TPointF;
  AX, AY, BX, BY, Det, SS, TT, D, Best, Eps: Double;
  PC: TProjCache;
begin
  if FFaceMemoOK and (FFaceMemoSeq = FEditSeq) and
     (FFaceMemoX = SX) and (FFaceMemoY = SY) and
     SameProjector(V, FFaceMemoV) and
     (FFaceMemoSlice = FSliceOn) and (FFaceMemoLo = FSliceLo) and
     (FFaceMemoHi = FSliceHi) then
  begin
    Face := FFaceMemoFace;
    Pt := FFaceMemoPt;
    Exit(Face >= 0);
  end;

  Result := False;
  Face := -1;
  Pt := P3(0, 0, 0);
  Best := -1E300;
  Look := ViewDir(V);
  { the camera once for the whole walk - this projects every corner of every
    face in the drawing, and Project rebuilds the view basis each time }
  BeginProject(V, PC);

  for I := 0 to FLive - 1 do
  begin
    if FEnts[I].Kind <> ekFace then Continue;
    if not InSlice(I) then Continue;
    N := Length(FEnts[I].Poly);
    if N < 3 then Continue;
    { A face is pickable from either side; the depth comparison below lets
      the near face win.  Skipping back faces made one end of a duct
      transition unreachable. }

    SetLength(P, N);
    for K := 0 to N - 1 do
      P[K] := ProjectAt(PC, FEnts[I].Poly[K]);

    Inside := False;
    J := N - 1;
    for K := 0 to N - 1 do
    begin
      if ((P[K].Y > SY) <> (P[J].Y > SY)) and
         (SX < (P[J].X - P[K].X) * (SY - P[K].Y) / (P[J].Y - P[K].Y) + P[K].X) then
        Inside := not Inside;
      J := K;
    end;
    { and out again through any hole, so the cursor in a window reaches
      what is behind it }
    if Inside then
      for HK := 0 to High(FEnts[I].Holes) do
      begin
        M := Length(FEnts[I].Holes[HK]);
        if M < 3 then Continue;
        SetLength(HP, M);
        for K := 0 to M - 1 do HP[K] := ProjectAt(PC, FEnts[I].Holes[HK][K]);
        J := M - 1;
        for K := 0 to M - 1 do
        begin
          if ((HP[K].Y > SY) <> (HP[J].Y > SY)) and
             (SX < (HP[J].X - HP[K].X) * (SY - HP[K].Y) /
                   (HP[J].Y - HP[K].Y) + HP[K].X) then
            Inside := not Inside;
          J := K;
        end;
      end;
    if not Inside then Continue;

    { Where the cursor meets this face's plane.  The basis is normalized
      first so the short sides of a circle's polygon do not cost accuracy. }
    Org := FEnts[I].Poly[0];
    U := Norm3(Sub3(FEnts[I].Poly[1], Org));
    W := Norm3(Cross3(FaceNormal(I), U));
    P0 := ProjectAt(PC, Org);
    P1 := ProjectAt(PC, Add3(Org, U));
    P2 := ProjectAt(PC, Add3(Org, W));
    AX := P1.X - P0.X; AY := P1.Y - P0.Y;
    BX := P2.X - P0.X; BY := P2.Y - P0.Y;
    Det := AX * BY - AY * BX;
    if Abs(Det) < 1E-12 then Continue;      // edge-on: nothing to click
    SS := ((SX - P0.X) * BY - (SY - P0.Y) * BX) / Det;
    TT := (AX * (SY - P0.Y) - AY * (SX - P0.X)) / Det;
    Hit := P3(Org.X + U.X * SS + W.X * TT,
              Org.Y + U.Y * SS + W.Y * TT,
              Org.Z + U.Z * SS + W.Z * TT);
    { Coplanar faces differ in depth only by rounding, so compare with a
      tolerance and within it let the smaller face win - it is the one on
      top, and the one you aimed at. }
    D := Dot3(Hit, Look);
    Eps := 1E-4 * (1 + Abs(D));
    if (Face < 0) or (D > Best + Eps) or
       ((D > Best - Eps) and (FaceArea(I) < FaceArea(Face))) then
    begin
      Best := D;
      Face := I;
      Pt := Hit;
      Result := True;
    end;
  end;
  FFaceMemoOK := True;
  FFaceMemoSeq := FEditSeq;
  FFaceMemoX := SX;
  FFaceMemoY := SY;
  FFaceMemoV := V;
  FFaceMemoFace := Face;
  FFaceMemoPt := Pt;
  FFaceMemoSlice := FSliceOn;
  FFaceMemoLo := FSliceLo;
  FFaceMemoHi := FSliceHi;
end;

function TWorkDoc.HitFace(const V: TProjector; SX, SY: Double): Integer;
var
  Pt: TP3;
begin
  if not FaceUnder(V, SX, SY, Result, Pt) then Result := -1;
end;

{ ---------------------------------------------------------------------- }
{ rounding a corner                                                       }
{ ---------------------------------------------------------------------- }

{ SketchUp's two-point arc: pick a point on each edge near a corner and pull
  the bulge out; it turns magenta when tangent to both, a typed radius sets
  the size, and a double-click trims the square corner and repeats at any
  other corner.  A plain click leaves the corner, cut at the touching points.
  Only loose lines take part; rounding a solid's corner would tear it. }

{ The two loose lines that meet at Corner - exactly two, not parallel.  A
  corner with three lines into it has no single fillet, and saying no is
  better than guessing which pair was meant. }
function TWorkDoc.CornerLines(const Corner: TP3; out LA, LB: Integer): Boolean;
const
  TOL = 1E-6;
var
  I, N: Integer;
  DA, DB: TP3;
begin
  Result := False;
  LA := -1;
  LB := -1;
  N := 0;
  for I := 0 to FLive - 1 do
  begin
    if FEnts[I].Kind <> ekLine then Continue;
    if FEnts[I].Dim or (FEnts[I].Grp <> 0) or (FEnts[I].Part <> FStamp) then Continue;
    if not (SamePt(FEnts[I].A, Corner, TOL) or SamePt(FEnts[I].B, Corner, TOL)) then
      Continue;
    if Dist(FEnts[I].A, FEnts[I].B) < TOL then Continue;
    Inc(N);
    if N = 1 then LA := I
    else if N = 2 then LB := I;
  end;
  if N <> 2 then Exit;
  DA := Norm3(P3(FarEnd(LA, Corner).X - Corner.X, FarEnd(LA, Corner).Y - Corner.Y,
                 FarEnd(LA, Corner).Z - Corner.Z));
  DB := Norm3(P3(FarEnd(LB, Corner).X - Corner.X, FarEnd(LB, Corner).Y - Corner.Y,
                 FarEnd(LB, Corner).Z - Corner.Z));
  { straight on through, or doubled back: no corner to round }
  Result := Abs(Dot3(DA, DB)) < 1 - 1E-6;
end;

{ The other end of a line from P. }
function TWorkDoc.FarEnd(I: Integer; const P: TP3): TP3;
begin
  if Dist(FEnts[I].A, P) < Dist(FEnts[I].B, P) then Result := FEnts[I].B
  else Result := FEnts[I].A;
end;

{ Everything about a fillet of radius R at Corner, without doing it.  The
  tangent points sit R / tan(half the corner angle) from the corner.  A
  radius too big for the shorter line is refused rather than eating the next
  corner. }
function TWorkDoc.FilletAt(const Corner: TP3; R: Double; out F: TFillet): Boolean;
const
  TOL = 1E-6;
var
  UA, UB, N, Mid, Dir: TP3;
  Th, LenA, LenB, U1, V1, U2, V2, UC, VC, Ln, NU, NV, Sag: Double;
  FO, FU, FV: TP3;
begin
  Result := False;
  FillChar(F, SizeOf(F), 0);
  if R <= TOL then Exit;
  if not CornerLines(Corner, F.LineA, F.LineB) then Exit;
  F.Corner := Corner;
  UA := FarEnd(F.LineA, Corner);
  UB := FarEnd(F.LineB, Corner);
  LenA := Dist(UA, Corner);
  LenB := Dist(UB, Corner);
  UA := Norm3(Sub3(UA, Corner));
  UB := Norm3(Sub3(UB, Corner));
  Th := ArcCos(EnsureRange(Dot3(UA, UB), -1, 1));
  if (Th < 1E-6) or (Th > Pi - 1E-6) then Exit;
  F.R := R;
  F.T := R / Tan(Th / 2);
  if (F.T > LenA + TOL) or (F.T > LenB + TOL) then Exit;
  F.S := P3(Corner.X + UA.X * F.T, Corner.Y + UA.Y * F.T, Corner.Z + UA.Z * F.T);
  F.E := P3(Corner.X + UB.X * F.T, Corner.Y + UB.Y * F.T, Corner.Z + UB.Z * F.T);

  { the plane the two lines lie in, named when it is one of the three }
  N := Norm3(Cross3(UA, UB));
  F.Nm := N;
  if Abs(N.Z) > 1 - 1E-9 then F.Pl := plXY
  else if Abs(N.Y) > 1 - 1E-9 then F.Pl := plXZ
  else if Abs(N.X) > 1 - 1E-9 then F.Pl := plYZ
  else
  begin
    { keep whatever free plane the window had, and put it back after -
      this is a question, not a change of working plane }
    GetFreePlane(FO, FU, FV, Dir);
    SetFreePlane(Corner, N);
    F.Pl := plFree;
  end;

  { The bulge, signed the way ArcFromChord reads it: towards the corner.
    The arc turns through the outside angle, pi less the corner's, so its
    middle stands R(1 - cos(half of that)) off the chord. }
  PlaneCoords(F.Pl, F.S, U1, V1);
  PlaneCoords(F.Pl, F.E, U2, V2);
  PlaneCoords(F.Pl, Corner, UC, VC);
  Ln := Sqrt(Sqr(U2 - U1) + Sqr(V2 - V1));
  if Ln < TOL then
  begin
    if F.Pl = plFree then SetFreePlane(FO, Dir);
    Exit;
  end;
  NU := -(V2 - V1) / Ln;
  NV := (U2 - U1) / Ln;
  Sag := R * (1 - Cos((Pi - Th) / 2));
  Mid := P3((U1 + U2) / 2, (V1 + V2) / 2, 0);
  if (UC - Mid.X) * NU + (VC - Mid.Y) * NV >= 0 then F.Bulge := Sag
  else F.Bulge := -Sag;
  Result := ArcFromChord(F.S, F.E, F.Bulge, F.Pl, F.ArcC, R, F.A0, F.Sweep);
  if F.Pl = plFree then
  begin
    { AddArc reads the free plane when it is called, so ApplyFillet sets it
      again from F.Nm; the window's own is put back here }
    SetFreePlane(FO, Dir);
  end;
end;

{ The fillet a pair of picks aims at: S on one line near a corner, E on the
  other.  The radius comes from S's distance to the corner and E is moved to
  match, since a tangent arc touches both lines at the same distance - the
  magenta state. }
function TWorkDoc.FilletFromEnds(const S, E: TP3; out F: TFillet): Boolean;
const
  TOL = 1E-6;
var
  I, J, Swap, LA, LB, Other: Integer;
  Ends: array[0..1] of TP3;
  Corner, UA, UB: TP3;
  T, Th: Double;

  function OnLine(K: Integer; const P: TP3): Boolean;
  var
    L, D1, D2: Double;
  begin
    L := Dist(FEnts[K].A, FEnts[K].B);
    D1 := Dist(FEnts[K].A, P);
    D2 := Dist(FEnts[K].B, P);
    { strictly inside it: a pick on the corner itself is no fillet }
    Result := (D1 > TOL) and (D2 > TOL) and (Abs(D1 + D2 - L) < 1E-6 * (1 + L));
  end;

begin
  Result := False;
  FillChar(F, SizeOf(F), 0);
  for I := 0 to FLive - 1 do
  begin
    if (FEnts[I].Kind <> ekLine) or FEnts[I].Dim or (FEnts[I].Grp <> 0) or (FEnts[I].Part <> FStamp) then
      Continue;
    if not OnLine(I, S) then Continue;
    Ends[0] := FEnts[I].A;
    Ends[1] := FEnts[I].B;
    for J := 0 to 1 do
    begin
      Corner := Ends[J];
      T := Dist(S, Corner);
      { the line E sits on has to be the other line at this corner }
      if not CornerLines(Corner, LA, LB) then Continue;
      if LA = I then Other := LB
      else if LB = I then Other := LA
      else Continue;
      if not OnLine(Other, E) then Continue;
      { the radius whose tangent points are T from the corner }
      UA := Norm3(P3(FarEnd(LA, Corner).X - Corner.X,
                     FarEnd(LA, Corner).Y - Corner.Y,
                     FarEnd(LA, Corner).Z - Corner.Z));
      UB := Norm3(P3(FarEnd(LB, Corner).X - Corner.X,
                     FarEnd(LB, Corner).Y - Corner.Y,
                     FarEnd(LB, Corner).Z - Corner.Z));
      Th := ArcCos(EnsureRange(Dot3(UA, UB), -1, 1));
      if not FilletAt(Corner, T * Tan(Th / 2), F) then Continue;
      { S should come back as the S that was clicked, on whichever side }
      if Dist(F.E, S) < Dist(F.S, S) then
      begin
        F.E := F.S;
        F.S := S;
        Swap := F.LineA; F.LineA := F.LineB; F.LineB := Swap;
        { the arc was built S to E; built the other way round the bulge
          changes side }
        F.Bulge := -F.Bulge;
        Exit(ArcFromChordFor(F));
      end;
      Exit(True);
    end;
  end;
end;

{ Is anything else joined to this end of line I - another line or an arc
  with an end in the same place? }
function TWorkDoc.LineEndJoined(I: Integer; AtB: Boolean): Boolean;
const
  TOL = 1E-6;
var
  K: Integer;
  P: TP3;
begin
  Result := False;
  if AtB then P := FEnts[I].B else P := FEnts[I].A;
  for K := 0 to FLive - 1 do
  begin
    if K = I then Continue;
    if not (FEnts[K].Kind in [ekLine, ekArc]) then Continue;
    if FEnts[K].Dim then Continue;
    if SamePt(FEnts[K].A, P, TOL) or SamePt(FEnts[K].B, P, TOL) then Exit(True);
  end;
end;

{ Which end of a line gives when its length is typed - SketchUp's rule: a
  loose edge moves its last endpoint, one joined at one end moves its free
  end, and one joined at both ends cannot be changed (False). }
function TWorkDoc.LineLengthEnd(I: Integer; out MoveB: Boolean): Boolean;
var
  JA, JB: Boolean;
begin
  Result := False;
  MoveB := True;
  if (I < 0) or (I >= FLive) or (FEnts[I].Kind <> ekLine) or FEnts[I].Dim then
    Exit;
  JA := LineEndJoined(I, False);
  JB := LineEndJoined(I, True);
  if JA and JB then Exit;
  { loose, or held at A: the end it was drawn to moves.  Held at B: A does. }
  MoveB := not JB;
  Result := True;
end;

{ Make line I NewLen long, moving the end LineLengthEnd names along the line's
  own direction. }
function TWorkDoc.SetLineLength(I: Integer; NewLen: Double): Boolean;
var
  MoveB: Boolean;
  L: Double;
  D: TP3;
begin
  Result := False;
  if NewLen <= 1E-9 then Exit;
  if not LineLengthEnd(I, MoveB) then Exit;
  L := Dist(FEnts[I].A, FEnts[I].B);
  if L < 1E-9 then Exit;
  if MoveB then
  begin
    D := P3((FEnts[I].B.X - FEnts[I].A.X) / L, (FEnts[I].B.Y - FEnts[I].A.Y) / L,
            (FEnts[I].B.Z - FEnts[I].A.Z) / L);
    FEnts[I].B := P3(FEnts[I].A.X + D.X * NewLen, FEnts[I].A.Y + D.Y * NewLen,
                     FEnts[I].A.Z + D.Z * NewLen);
  end
  else
  begin
    D := P3((FEnts[I].A.X - FEnts[I].B.X) / L, (FEnts[I].A.Y - FEnts[I].B.Y) / L,
            (FEnts[I].A.Z - FEnts[I].B.Z) / L);
    FEnts[I].A := P3(FEnts[I].B.X + D.X * NewLen, FEnts[I].B.Y + D.Y * NewLen,
                     FEnts[I].B.Z + D.Z * NewLen);
  end;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
  Result := True;
end;

{ Take the square corner off a fillet already in: every loose line between
  the corner and a touching point.  Separate because SketchUp's double-click
  is two clicks - the first adds the arc, the second trims.  Returns how many
  went. }
function TWorkDoc.TrimFillet(const F: TFillet): Integer;
const
  TOL = 1E-6;
var
  Doomed: array of Boolean;
  K: Integer;
begin
  Result := 0;
  SetLength(Doomed, FLive);
  for K := 0 to FLive - 1 do
  begin
    Doomed[K] := False;
    if (FEnts[K].Kind <> ekLine) or FEnts[K].Dim or (FEnts[K].Grp <> 0) or (FEnts[K].Part <> FStamp) then
      Continue;
    if (SamePt(FEnts[K].A, F.Corner, TOL) and
        (SamePt(FEnts[K].B, F.S, TOL) or SamePt(FEnts[K].B, F.E, TOL))) or
       (SamePt(FEnts[K].B, F.Corner, TOL) and
        (SamePt(FEnts[K].A, F.S, TOL) or SamePt(FEnts[K].A, F.E, TOL))) then
    begin
      Doomed[K] := True;
      Inc(Result);
    end;
  end;
  if Result > 0 then DeleteMarked(Doomed);
end;

{ ArcFromChord for a fillet whose ends have been swapped, in its own plane. }
function TWorkDoc.ArcFromChordFor(var F: TFillet): Boolean;
var
  FO, FU, FV, Dir: TP3;
  R: Double;
begin
  if F.Pl = plFree then
  begin
    GetFreePlane(FO, FU, FV, Dir);
    SetFreePlane(F.Corner, F.Nm);
  end;
  Result := ArcFromChord(F.S, F.E, F.Bulge, F.Pl, F.ArcC, R, F.A0, F.Sweep);
  if F.Pl = plFree then SetFreePlane(FO, Dir);
end;

{ The roundable corner nearest a screen point, where exactly two loose lines
  meet at an angle - what a double-click reaches for to repeat the last
  fillet. }
function TWorkDoc.NearestCorner(const V: TProjector; SX, SY, TolPx: Double;
  out Corner: TP3): Boolean;
var
  I, K, LA, LB: Integer;
  P: TP3;
  Q: TPointF;
  D, Best: Double;
  PC: TProjCache;
begin
  Result := False;
  Corner := P3(0, 0, 0);
  Best := TolPx;
  BeginProject(V, PC);
  for I := 0 to FLive - 1 do
  begin
    if (FEnts[I].Kind <> ekLine) or FEnts[I].Dim or (FEnts[I].Grp <> 0) or (FEnts[I].Part <> FStamp) then
      Continue;
    if not InSlice(I) then Continue;
    for K := 0 to 1 do
    begin
      if K = 0 then P := FEnts[I].A else P := FEnts[I].B;
      Q := ProjectAt(PC, P);
      D := Sqrt(Sqr(SX - Q.X) + Sqr(SY - Q.Y));
      if D >= Best then Continue;
      if HiddenAt(V, P) then Continue;
      if not CornerLines(P, LA, LB) then Continue;
      Best := D;
      Corner := P;
      Result := True;
    end;
  end;
end;

{ Round the corner: add the arc and cut each line at its tangent point.  With
  Trim the two corner pieces go too (SketchUp's double-click) and the next
  rebuild draws the rounded face.  Without it the pieces stay, to be erased
  one at a time. }
function TWorkDoc.ApplyFillet(const F: TFillet; Sides: Integer; Ink: TColor;
  Weight: Single; Trim: Boolean): Boolean;
const
  TOL = 1E-6;
var
  FO, FU, FV, Dir, FarA, FarB: TP3;
  LA, LB, Arc, K: Integer;
  R: Double;

  { cut line K at P, keeping the piece away from the corner in place and
    adding the corner piece; true when a corner piece was made }
  function Cut(K: Integer; const P, FarP: TP3): Boolean;
  begin
    Result := False;
    if Dist(P, FarP) < TOL then
    begin
      { the fillet takes the whole of this line }
      FEnts[K].A := F.Corner;
      FEnts[K].B := P;
      Exit(True);
    end;
    FEnts[K].A := FarP;
    FEnts[K].B := P;
    AddLine(P, F.Corner, FEnts[K].Ink, FEnts[K].Weight, False);
    Result := True;
  end;

begin
  Result := False;
  LA := F.LineA;
  LB := F.LineB;
  if (LA < 0) or (LB < 0) or (LA >= FLive) or (LB >= FLive) then Exit;
  R := Dist(F.ArcC, F.S);
  if R <= TOL then Exit;
  FarA := FarEnd(LA, F.Corner);
  FarB := FarEnd(LB, F.Corner);

  { A corner already rounded with a plain click still has its square corner,
    so a double-click there means trim it, not add a second arc. }
  for K := 0 to FLive - 1 do
    if (FEnts[K].Kind = ekArc) and
       ((SamePt(FEnts[K].A, F.S, 1E-6) and SamePt(FEnts[K].B, F.E, 1E-6)) or
        (SamePt(FEnts[K].A, F.E, 1E-6) and SamePt(FEnts[K].B, F.S, 1E-6))) then
    begin
      if Trim then TrimFillet(F);
      Exit(True);
    end;

  { the corner pieces, cut off each line }
  Cut(LA, F.S, FarA);
  Cut(LB, F.E, FarB);

  if F.Pl = plFree then
  begin
    GetFreePlane(FO, FU, FV, Dir);
    SetFreePlane(F.Corner, F.Nm);
  end;
  AddArc(F.ArcC, R, F.A0, F.Sweep, F.Pl, Ink, Weight);
  Arc := FLive - 1;
  if F.Pl = plFree then SetFreePlane(FO, Dir);
  if Sides > 0 then SetArcSides(Arc, Sides);

  if Trim then TrimFillet(F);
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
  Result := True;
end;


{ Where two edges cross, both should end there, so a circle drawn over a
  corner can be partly rubbed out to leave a fillet.  Only loose lines and
  arcs take part, and only pairs where one was drawn since FirstNew.  An arc
  is walked as its drawn segments, and a piece keeps its share of the sides. }
function TWorkDoc.SplitCrossings(FirstNew: Integer): Integer;
const
  TOL = 1E-6;      { how close two edges pass before they count as meeting }
type
  TWalk = record
    Ent: Integer;
    Fresh: Boolean;
    Len: Double;
    Pts: TP3Array;
    Cut: array of Double;
  end;
var
  W: array of TWalk;
  Made: array of TWorkEnt;
  Doom: array of Boolean;
  NW, NMade: Integer;
  I, J, K, A, B, Steps: Integer;
  S, T, D, Tmp, LA, LB: Double;

  { The nearest approach of two segments, and where along each.  Near-parallel
    is left alone: overlapping runs are AddLineSplit's business. }
  procedure Nearest(const P1, P2, Q1, Q2: TP3; out SS, TT, DD: Double);
  var
    D1, D2, R, C1, C2: TP3;
    Aa, Bb, Cc, Ee, Ff, Den: Double;
  begin
    SS := 0; TT := 0; DD := 1E30;
    D1 := Sub3(P2, P1);
    D2 := Sub3(Q2, Q1);
    R := Sub3(P1, Q1);
    Aa := Dot3(D1, D1);
    Ee := Dot3(D2, D2);
    if (Aa < 1E-24) or (Ee < 1E-24) then Exit;
    Bb := Dot3(D1, D2);
    Cc := Dot3(D1, R);
    Ff := Dot3(D2, R);
    Den := Aa * Ee - Bb * Bb;
    if Den <= 1E-12 * Aa * Ee then Exit;
    SS := (Bb * Ff - Cc * Ee) / Den;
    if SS < 0 then SS := 0 else if SS > 1 then SS := 1;
    TT := (Bb * SS + Ff) / Ee;
    if TT < 0 then
    begin
      TT := 0;
      SS := -Cc / Aa;
    end
    else if TT > 1 then
    begin
      TT := 1;
      SS := (Bb - Cc) / Aa;
    end;
    if SS < 0 then SS := 0 else if SS > 1 then SS := 1;
    C1 := P3(P1.X + D1.X * SS, P1.Y + D1.Y * SS, P1.Z + D1.Z * SS);
    C2 := P3(Q1.X + D2.X * TT, Q1.Y + D2.Y * TT, Q1.Z + D2.Z * TT);
    DD := Dist(C1, C2);
  end;

  { A cut at either end is no cut.  Measured along the edge, not in its
    parameter, so a hair of an edge is never left behind. }
  procedure Note(Which: Integer; U: Double);
  var
    Q, N: Integer;
    L: Double;
  begin
    L := W[Which].Len;
    if L < TOL then Exit;
    if (U * L < TOL) or ((1 - U) * L < TOL) then Exit;
    for Q := 0 to High(W[Which].Cut) do
      if Abs(W[Which].Cut[Q] - U) * L < TOL then Exit;
    N := Length(W[Which].Cut);
    SetLength(W[Which].Cut, N + 1);
    W[Which].Cut[N] := U;
  end;

  procedure Piece(const E: TWorkEnt; U0, U1: Double);
  var
    N: TWorkEnt;
    Sd: Integer;
  begin
    if U1 <= U0 then Exit;
    N := E;
    if E.Kind = ekLine then
    begin
      N.A := P3(E.A.X + (E.B.X - E.A.X) * U0,
                E.A.Y + (E.B.Y - E.A.Y) * U0,
                E.A.Z + (E.B.Z - E.A.Z) * U0);
      N.B := P3(E.A.X + (E.B.X - E.A.X) * U1,
                E.A.Y + (E.B.Y - E.A.Y) * U1,
                E.A.Z + (E.B.Z - E.A.Z) * U1);
      if Dist(N.A, N.B) < TOL then Exit;
    end
    else
    begin
      N.A0 := E.A0 + E.Sweep * U0;
      N.Sweep := E.Sweep * (U1 - U0);
      if Abs(N.Sweep) < 1E-9 then Exit;
      Sd := Round(ArcSteps(E) * (U1 - U0));
      if Sd < 3 then Sd := 3;
      N.Sides := Sd;
      N.A := ArcPoint(N.C, N.R, N.A0, N.Plane, N.Nm);
      N.B := ArcPoint(N.C, N.R, N.A0 + N.Sweep, N.Plane, N.Nm);
    end;
    if NMade >= Length(Made) then SetLength(Made, Max(8, NMade * 2));
    Made[NMade] := N;
    Inc(NMade);
  end;

begin
  Result := 0;
  NMade := 0;
  NW := 0;
  SetLength(W, FLive);
  for I := 0 to FLive - 1 do
  begin
    if not (FEnts[I].Kind in [ekLine, ekArc]) then Continue;
    if FEnts[I].Dim or (FEnts[I].Grp <> 0) or (FEnts[I].Part <> FStamp) then Continue;
    W[NW].Ent := I;
    W[NW].Fresh := I >= FirstNew;
    W[NW].Cut := nil;
    if FEnts[I].Kind = ekArc then
    begin
      Steps := ArcSteps(FEnts[I]);
      SetLength(W[NW].Pts, Steps + 1);
      for K := 0 to Steps do
        W[NW].Pts[K] := ArcPoint(FEnts[I].C, FEnts[I].R,
          FEnts[I].A0 + FEnts[I].Sweep * K / Steps,
          FEnts[I].Plane, FEnts[I].Nm);
    end
    else
    begin
      SetLength(W[NW].Pts, 2);
      W[NW].Pts[0] := FEnts[I].A;
      W[NW].Pts[1] := FEnts[I].B;
    end;
    W[NW].Len := 0;
    for K := 0 to High(W[NW].Pts) - 1 do
      W[NW].Len := W[NW].Len + Dist(W[NW].Pts[K], W[NW].Pts[K + 1]);
    Inc(NW);
  end;

  for I := 0 to NW - 1 do
    for J := I + 1 to NW - 1 do
    begin
      if not (W[I].Fresh or W[J].Fresh) then Continue;
      for A := 0 to High(W[I].Pts) - 1 do
        for B := 0 to High(W[J].Pts) - 1 do
        begin
          Nearest(W[I].Pts[A], W[I].Pts[A + 1],
                  W[J].Pts[B], W[J].Pts[B + 1], S, T, D);
          if D > TOL then Continue;
          { A tangent hit lands a whisker off an arc corner; snap it onto the
            corner so the pieces sit on the whole arc and a second pass finds
            nothing to do. }
          LA := Dist(W[I].Pts[A], W[I].Pts[A + 1]);
          LB := Dist(W[J].Pts[B], W[J].Pts[B + 1]);
          if S * LA < TOL then S := 0
          else if (1 - S) * LA < TOL then S := 1;
          if T * LB < TOL then T := 0
          else if (1 - T) * LB < TOL then T := 1;
          Note(I, (A + S) / High(W[I].Pts));
          Note(J, (B + T) / High(W[J].Pts));
        end;
    end;

  SetLength(Doom, FLive);
  for I := 0 to FLive - 1 do Doom[I] := False;

  for I := 0 to NW - 1 do
  begin
    if Length(W[I].Cut) = 0 then Continue;
    for J := 1 to High(W[I].Cut) do
    begin
      Tmp := W[I].Cut[J];
      K := J - 1;
      while (K >= 0) and (W[I].Cut[K] > Tmp) do
      begin
        W[I].Cut[K + 1] := W[I].Cut[K];
        Dec(K);
      end;
      W[I].Cut[K + 1] := Tmp;
    end;
    Piece(FEnts[W[I].Ent], 0, W[I].Cut[0]);
    for J := 0 to High(W[I].Cut) - 1 do
      Piece(FEnts[W[I].Ent], W[I].Cut[J], W[I].Cut[J + 1]);
    Piece(FEnts[W[I].Ent], W[I].Cut[High(W[I].Cut)], 1);
    Doom[W[I].Ent] := True;
    Inc(Result);
  end;

  if Result = 0 then Exit;

  DeleteMarked(Doom);
  for I := 0 to NMade - 1 do
  begin
    Room;
    Finalize(FEnts[FLive]);
    FillChar(FEnts[FLive], SizeOf(TWorkEnt), 0);
    FEnts[FLive] := CopyEnt(Made[I]);
    Inc(FLive);
  end;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

{ Cut one face along a segment that crosses it.  If the segment enters and
  leaves exactly once, the boundary is walked each way between the crossings
  for the two halves.  Anything else is left alone - half a cut is worse than
  none. }
function TWorkDoc.SplitFace(Index: Integer; const A, B: TP3): Boolean;
const
  EPS = 1E-9;
var
  N, I, J, K, NHit, C1, C2: Integer;
  Nm, U, V, Org, W: TP3;
  PX, PY: array of Double;
  AX, AY, BX, BY: Double;
  EX, EY, RX, RY, Den, T, Q: Double;
  CutEdge: array[0..1] of Integer;
  HitP: array[0..1] of TP3;
  Src, H1, H2: TP3Array;
  Ink: TColor;
  WasSolid: Boolean;
  WasGrp: Integer;

  function Same(const P, R: TP3): Boolean;
  begin
    Result := Dist(P, R) < 1E-7;
  end;

begin
  Result := False;
  if (Index < 0) or (Index >= FLive) then Exit;
  if FEnts[Index].Kind <> ekFace then Exit;
  N := Length(FEnts[Index].Poly);
  if N < 3 then Exit;

  { work from a copy - the original is overwritten with one of the halves }
  SetLength(Src, N);
  for I := 0 to N - 1 do
    Src[I] := FEnts[Index].Poly[I];

  Nm := FaceNormal(Index);
  Org := Src[0];

  { the cut has to lie in the face's plane }
  W := Sub3(A, Org);
  if Abs(Dot3(W, Nm)) > 1E-6 then Exit;
  W := Sub3(B, Org);
  if Abs(Dot3(W, Nm)) > 1E-6 then Exit;

  { a basis in that plane }
  U := Norm3(Sub3(Src[1], Org));
  V := Cross3(Nm, U);

  SetLength(PX, N);
  SetLength(PY, N);
  for I := 0 to N - 1 do
  begin
    W := Sub3(Src[I], Org);
    PX[I] := Dot3(W, U);
    PY[I] := Dot3(W, V);
  end;
  W := Sub3(A, Org);
  AX := Dot3(W, U); AY := Dot3(W, V);
  W := Sub3(B, Org);
  BX := Dot3(W, U); BY := Dot3(W, V);

  RX := BX - AX;
  RY := BY - AY;
  if Sqrt(RX * RX + RY * RY) < 1E-9 then Exit;

  NHit := 0;
  for I := 0 to N - 1 do
  begin
    J := (I + 1) mod N;
    EX := PX[J] - PX[I];
    EY := PY[J] - PY[I];
    Den := RX * EY - RY * EX;
    if Abs(Den) < EPS then Continue;        // parallel, including along an edge
    T := ((PX[I] - AX) * EY - (PY[I] - AY) * EX) / Den;   // along the cut
    Q := ((PX[I] - AX) * RY - (PY[I] - AY) * RX) / Den;   // along this edge
    if (T < -1E-9) or (T > 1 + 1E-9) then Continue;
    { a crossing exactly on a vertex would be reported by both edges that
      meet there, so each edge owns its start and leaves its end to the next }
    if (Q < -1E-9) or (Q > 1 - 1E-9) then Continue;
    if NHit >= 2 then Exit;                 // more than a clean pair
    CutEdge[NHit] := I;
    HitP[NHit] := P3(Src[I].X + (Src[J].X - Src[I].X) * Q,
                     Src[I].Y + (Src[J].Y - Src[I].Y) * Q,
                     Src[I].Z + (Src[J].Z - Src[I].Z) * Q);
    Inc(NHit);
  end;

  if NHit <> 2 then Exit;
  if CutEdge[0] = CutEdge[1] then Exit;     // in and out through one edge
  if Same(HitP[0], HitP[1]) then Exit;

  Ink := FEnts[Index].Ink;

  { one half: crossing 0, round the boundary, crossing 1 }
  SetLength(H1, N + 4);
  C1 := 0;
  H1[C1] := HitP[0]; Inc(C1);
  I := CutEdge[0];
  repeat
    I := (I + 1) mod N;
    if not Same(Src[I], HitP[0]) and not Same(Src[I], HitP[1]) then
    begin
      H1[C1] := Src[I]; Inc(C1);
    end;
  until I = CutEdge[1];
  H1[C1] := HitP[1]; Inc(C1);
  SetLength(H1, C1);

  { the other half: crossing 1, round the rest, crossing 0 }
  SetLength(H2, N + 4);
  C2 := 0;
  H2[C2] := HitP[1]; Inc(C2);
  K := CutEdge[1];
  repeat
    K := (K + 1) mod N;
    if not Same(Src[K], HitP[0]) and not Same(Src[K], HitP[1]) then
    begin
      H2[C2] := Src[K]; Inc(C2);
    end;
  until K = CutEdge[0];
  H2[C2] := HitP[0]; Inc(C2);
  SetLength(H2, C2);

  if (C1 < 3) or (C2 < 3) then Exit;

  { both halves keep whatever the whole was - a side of a solid stays part of
    that solid, and both pieces answer to the same group }
  WasSolid := FEnts[Index].Solid;
  WasGrp := FEnts[Index].Grp;

  SetLength(FEnts[Index].Poly, C1);
  for I := 0 to C1 - 1 do
    FEnts[Index].Poly[I] := H1[I];
  FEnts[Index].A := H1[0];
  FEnts[Index].B := H1[C1 - 1];

  if WasSolid then
  begin
    { raw, because both halves were walked round in the original's order and
      already face the way it did - orienting them would turn one inside out }
    AddFaceRaw(H2, Ink, True);
    FEnts[FLive - 1].Grp := WasGrp;
  end
  else
    AddFace(H2, Ink, False);
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
  Result := True;
end;

function TWorkDoc.IsPatch(Index: Integer): Boolean;
const
  TOL = 1E-6;
var
  I, Q, K, N, M, RB: Integer;
  Nm: TP3;
  PlaneD: Double;
  A, B: TP3Array;
begin
  Result := False;
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekFace) then Exit;
  if Length(FEnts[Index].Poly) < 3 then Exit;
  Nm := FaceNormal(Index);
  PlaneD := Dot3(Nm, FEnts[Index].Poly[0]);

  for I := 0 to FLive - 1 do
  begin
    if I = Index then Continue;
    if FEnts[I].Kind <> ekFace then Continue;
    if Length(FEnts[I].Poly) < 3 then Continue;
    { in the same plane?  the normals may point opposite ways }
    if Abs(Abs(Dot3(FaceNormal(I), Nm)) - 1) > TOL then Continue;
    if Abs(Dot3(Nm, FEnts[I].Poly[0]) - PlaneD) > TOL then Continue;
    { Sharing an edge with it?  The neighbor's holes count - a letter in a
      hole touches its panel only along the hole.  This face's own holes do
      not: the plugs filling them are its tenants, not its neighbors. }
    A := FEnts[Index].Poly;
    N := Length(A);
    for RB := 0 to Length(FEnts[I].Holes) do
    begin
      if RB = 0 then B := FEnts[I].Poly else B := FEnts[I].Holes[RB - 1];
      M := Length(B);
      if M < 3 then Continue;
      for Q := 0 to N - 1 do
        for K := 0 to M - 1 do
          if ((Dist(A[Q], B[K]) < TOL) and
              (Dist(A[(Q + 1) mod N], B[(K + 1) mod M]) < TOL)) or
             ((Dist(A[Q], B[(K + 1) mod M]) < TOL) and
              (Dist(A[(Q + 1) mod N], B[K]) < TOL)) then
            Exit(True);
    end;
  end;
end;


function TWorkDoc.WallsSquareTo(Index: Integer): Boolean;
const
  TOL = 1E-6;
var
  I, Q, K, N, M: Integer;
  Nm, ONm: TP3;
  A, B: TP3Array;
  Shares: Boolean;
begin
  Result := True;
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekFace) then Exit;
  Nm := FaceNormal(Index);
  A := FEnts[Index].Poly;
  N := Length(A);
  for I := 0 to FLive - 1 do
  begin
    if (I = Index) or (FEnts[I].Kind <> ekFace) then Continue;
    if FEnts[I].Grp <> FEnts[Index].Grp then Continue;
    B := FEnts[I].Poly;
    M := Length(B);
    if M < 3 then Continue;
    { does it share an edge with the face? }
    Shares := False;
    for Q := 0 to N - 1 do
    begin
      for K := 0 to M - 1 do
        if ((Dist(A[Q], B[K]) < TOL) and (Dist(A[(Q + 1) mod N], B[(K + 1) mod M]) < TOL)) or
           ((Dist(A[Q], B[(K + 1) mod M]) < TOL) and (Dist(A[(Q + 1) mod N], B[K]) < TOL)) then
        begin
          Shares := True;
          Break;
        end;
      if Shares then Break;
    end;
    if not Shares then Continue;
    ONm := FaceNormal(I);
    { square to the push: the wall's normal is at right angles to ours }
    if Abs(Dot3(Nm, ONm)) > 1E-6 then Exit(False);
    { and the wall lies behind the face, back into the solid.  A wall
      running out along the normal belongs to a taller neighbor, and sliding
      the face would shear it. }
    for K := 0 to M - 1 do
      if Dot3(Nm, Sub3(B[K], A[0])) > TOL then
        Exit(False);
  end;
end;

function LoopContains(const P: TP3; const Loop: TP3Array; const N: TP3): Boolean; forward;

function TWorkDoc.FaceHolding(const P: TP3): Integer;
const
  TOL = 1E-6;
var
  I, H: Integer;
  Nm, W: TP3;
  A, Best: Double;
  InHole: Boolean;
begin
  Result := -1;
  Best := 0;
  for I := 0 to FLive - 1 do
  begin
    if (FEnts[I].Kind <> ekFace) or (Length(FEnts[I].Poly) < 3) then Continue;
    Nm := FaceNormal(I);
    W := Sub3(P, FEnts[I].Poly[0]);
    if Abs(Dot3(W, Nm)) > TOL then Continue;
    if not LoopContains(P, FEnts[I].Poly, Nm) then Continue;
    InHole := False;
    for H := 0 to High(FEnts[I].Holes) do
      if LoopContains(P, FEnts[I].Holes[H], Nm) then begin InHole := True; Break; end;
    if InHole then Continue;
    A := FaceArea(I);
    if (Result < 0) or (A < Best) then
    begin
      Result := I;
      Best := A;
    end;
  end;
end;

{ Which flat face a point sits on.  A box corner belongs to three; the first
  found will do, since any of them is a plane a new shape could be drawn in. }
function TWorkDoc.FaceThrough(const P: TP3): Integer;
const
  TOL = 1E-6;
var
  I, K: Integer;
  Nm, W: TP3;
begin
  Result := -1;
  for I := FLive - 1 downto 0 do
  begin
    if FEnts[I].Kind <> ekFace then Continue;
    if Length(FEnts[I].Poly) < 3 then Continue;
    Nm := FaceNormal(I);
    W := Sub3(P, FEnts[I].Poly[0]);
    if Abs(Dot3(W, Nm)) > TOL then Continue;
    for K := 0 to High(FEnts[I].Poly) do
      if Dist(P, FEnts[I].Poly[K]) < 1E-5 then Exit(I);
  end;
end;

function TWorkDoc.SplitFacesWith(const A, B: TP3): Integer;
var
  I, Was: Integer;
begin
  Result := 0;
  Was := FLive;                { only faces that were there before the cut }
  for I := Was - 1 downto 0 do
    if SplitFace(I, A, B) then Inc(Result);
end;

{ Move a face and take the geometry attached to it, so pushing a face of a
  solid resizes it.  Vertices are matched against where the face was before
  the move, so nothing moves twice. }
procedure TWorkDoc.MoveFaceWith(Index: Integer; const D: TP3);
const
  TOL = 1E-6;
var
  Was: TP3Array;
  I, J, K, N, G: Integer;
  Nm, BU, BV: TP3;
  PlaneD: Double;

  { Does this point sit anywhere on the face, edges included - not only at
    its corners? }
  function OnFace(const P: TP3): Boolean;
  var
    J, M: Integer;
    Inside: Boolean;
    PU, PV, AU, AV, BU2, BV2, DU, DV, L2, T: Double;

    procedure Flat(const R: TP3; out CU, CV: Double);
    var
      W: TP3;
    begin
      W := Sub3(R, Was[0]);
      CU := Dot3(W, BU);
      CV := Dot3(W, BV);
    end;

  begin
    Result := False;
    { in the face's plane at all? }
    if Abs(Dot3(Nm, P) - PlaneD) > TOL then Exit;

    Flat(P, PU, PV);
    M := Length(Was);

    { on the outline counts, and has to be tested for on its own - a ray cast
      is unreliable exactly on a boundary }
    for J := 0 to M - 1 do
    begin
      Flat(Was[J], AU, AV);
      Flat(Was[(J + 1) mod M], BU2, BV2);
      DU := BU2 - AU;
      DV := BV2 - AV;
      L2 := DU * DU + DV * DV;
      if L2 < 1E-18 then Continue;
      T := EnsureRange(((PU - AU) * DU + (PV - AV) * DV) / L2, 0, 1);
      if Sqrt(Sqr(PU - (AU + DU * T)) + Sqr(PV - (AV + DV * T))) < TOL then
        Exit(True);
    end;

    { otherwise, inside the outline }
    Inside := False;
    Flat(Was[M - 1], AU, AV);
    for J := 0 to M - 1 do
    begin
      Flat(Was[J], BU2, BV2);
      if ((BV2 > PV) <> (AV > PV)) and
         (PU < (AU - BU2) * (PV - BV2) / (AV - BV2) + BU2) then
        Inside := not Inside;
      AU := BU2;
      AV := BV2;
    end;
    Result := Inside;
  end;

  procedure Shift(var P: TP3);
  begin
    if OnFace(P) then
      P := Add3(P, D);
  end;

begin
  N := Length(FEnts[Index].Poly);
  if N < 3 then Exit;
  SetLength(Was, N);
  for I := 0 to N - 1 do
    Was[I] := FEnts[Index].Poly[I];
  G := FEnts[Index].Grp;

  Nm := FaceNormal(Index);
  PlaneD := Dot3(Nm, Was[0]);
  BU := Norm3(Sub3(Was[1], Was[0]));
  BV := Cross3(Nm, BU);

  for I := 0 to FLive - 1 do
  begin
    { This solid, and anything loose lying on it.  Another solid has its own
      group and is left alone, even where it shares corners. }
    if (I <> Index) and (FEnts[I].Grp <> G) and (FEnts[I].Grp <> 0) then Continue;
    Shift(FEnts[I].A);
    Shift(FEnts[I].B);
    if FEnts[I].Kind = ekArc then Shift(FEnts[I].C);
    for K := 0 to High(FEnts[I].Poly) do
      Shift(FEnts[I].Poly[K]);
    { Holes travel with the face, or sliding it tears the solid open along
      every opening. }
    for J := 0 to High(FEnts[I].Holes) do
      for K := 0 to High(FEnts[I].Holes[J]) do
        Shift(FEnts[I].Holes[J][K]);
  end;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

function SharesRun(const P1, Q1, P2, Q2: TP3): Boolean;
const
  TOL = 1E-6;
var
  U, W, F: TP3;
  L, TA, TB, Off, Lo, Hi: Double;
begin
  Result := False;
  L := Dist(P1, Q1);
  if L < TOL then Exit;
  U := P3((Q1.X - P1.X) / L, (Q1.Y - P1.Y) / L, (Q1.Z - P1.Z) / L);

  W := Sub3(P2, P1);
  TA := Dot3(W, U);
  F := P3(W.X - U.X * TA, W.Y - U.Y * TA, W.Z - U.Z * TA);
  Off := Sqrt(F.X * F.X + F.Y * F.Y + F.Z * F.Z);
  if Off > TOL then Exit;

  W := Sub3(Q2, P1);
  TB := Dot3(W, U);
  F := P3(W.X - U.X * TB, W.Y - U.Y * TB, W.Z - U.Z * TB);
  Off := Sqrt(F.X * F.X + F.Y * F.Y + F.Z * F.Z);
  if Off > TOL then Exit;

  Lo := Max(0, Min(TA, TB));
  Hi := Min(L, Max(TA, TB));
  Result := Hi - Lo > TOL;
end;

{ A guide point goes with the guide line it lies on - the tape lays them
  together.  Worked out from position, so it works on old drawings too; a
  point on two lines goes with whichever is erased first. }
function TWorkDoc.PointsOnGuides(const Idx: array of Integer;
  out Pts: TIntArrayW): Integer;
const
  TOL = 1E-6;
var
  I, J, K, N: Integer;
  Marked: array of Boolean;
  Lines: array of Integer;

  function OnOne(const P: TP3): Boolean;
  var
    M: Integer;
    A, B, W, U, F: TP3;
    L, T, Off: Double;
  begin
    Result := True;
    for M := 0 to N - 1 do
    begin
      A := FEnts[Lines[M]].A;
      B := FEnts[Lines[M]].B;
      L := Dist(A, B);
      if L < TOL then Continue;
      U := P3((B.X - A.X) / L, (B.Y - A.Y) / L, (B.Z - A.Z) / L);
      W := Sub3(P, A);
      T := Dot3(W, U);
      if (T < -TOL) or (T > L + TOL) then Continue;
      F := P3(W.X - U.X * T, W.Y - U.Y * T, W.Z - U.Z * T);
      Off := Sqrt(F.X * F.X + F.Y * F.Y + F.Z * F.Z);
      if Off <= TOL then Exit;
    end;
    Result := False;
  end;

begin
  Pts := nil;
  Result := 0;
  N := 0;
  SetLength(Lines, Length(Idx));
  for I := 0 to High(Idx) do
  begin
    J := Idx[I];
    if (J < 0) or (J >= FLive) then Continue;
    if (FEnts[J].Kind = ekGuide) and (Dist(FEnts[J].A, FEnts[J].B) > TOL) then
    begin
      Lines[N] := J;
      Inc(N);
    end;
  end;
  if N = 0 then Exit;

  SetLength(Marked, FLive);
  for I := 0 to FLive - 1 do Marked[I] := False;
  for I := 0 to High(Idx) do
    if (Idx[I] >= 0) and (Idx[I] < FLive) then Marked[Idx[I]] := True;

  for K := 0 to FLive - 1 do
  begin
    if Marked[K] or (FEnts[K].Kind <> ekGuide) then Continue;
    if Dist(FEnts[K].A, FEnts[K].B) > TOL then Continue;
    if not OnOne(FEnts[K].A) then Continue;
    SetLength(Pts, Result + 1);
    Pts[Result] := K;
    Inc(Result);
  end;
end;

{ Which faces these edges hold up.  SketchUp's rule: a face is what a closed
  run of edges encloses, so erasing an edge takes its faces - a solid's too,
  which are kept as made.  Only the edges being erased are asked about;
  auditing the whole drawing would take faces that never had edges. }
function TWorkDoc.FacesOnEdges(const Idx: array of Integer;
  out Faces: TIntArrayW): Integer;
const
  TOL = 1E-6;
type
  TRun = record A, B: TP3; Part: Integer; end;
var
  Runs: array of TRun;
  NR, I, J, K, H, Steps: Integer;
  Ang: Double;
  P, Q: TP3;
  Marked: array of Boolean;

  procedure PutRun(const A, B: TP3; Part: Integer);
  begin
    if Dist(A, B) < TOL then Exit;
    if NR >= Length(Runs) then SetLength(Runs, Max(16, NR * 2));
    Runs[NR].A := A; Runs[NR].B := B; Runs[NR].Part := Part;
    Inc(NR);
  end;

  { An edge holds up the faces of its own group only, so erasing stairs does
    not take the wall whose top their board lies along. }
  function UsesARun(const A, B: TP3; Part: Integer): Boolean;
  var
    M: Integer;
  begin
    Result := True;
    for M := 0 to NR - 1 do
      if (Runs[M].Part = Part) and SharesRun(A, B, Runs[M].A, Runs[M].B) then Exit;
    Result := False;
  end;

begin
  Faces := nil;
  Result := 0;
  NR := 0;

  { every run that is about to go, arcs walked as they are drawn }
  for I := 0 to High(Idx) do
  begin
    J := Idx[I];
    if (J < 0) or (J >= FLive) then Continue;
    case FEnts[J].Kind of
      ekLine: if not FEnts[J].Dim then PutRun(FEnts[J].A, FEnts[J].B, FEnts[J].Part);
      ekArc:
        begin
          Steps := ArcSteps(FEnts[J]);
          for K := 0 to Steps - 1 do
          begin
            Ang := FEnts[J].A0 + FEnts[J].Sweep * K / Steps;
            P := ArcPoint(FEnts[J].C, FEnts[J].R, Ang, FEnts[J].Plane, FEnts[J].Nm);
            Ang := FEnts[J].A0 + FEnts[J].Sweep * (K + 1) / Steps;
            Q := ArcPoint(FEnts[J].C, FEnts[J].R, Ang, FEnts[J].Plane, FEnts[J].Nm);
            PutRun(P, Q, FEnts[J].Part);
          end;
        end;
    end;
  end;
  if NR = 0 then Exit;

  SetLength(Marked, FLive);
  for I := 0 to FLive - 1 do Marked[I] := False;
  for I := 0 to High(Idx) do
    if (Idx[I] >= 0) and (Idx[I] < FLive) then Marked[Idx[I]] := True;

  for I := 0 to FLive - 1 do
  begin
    if Marked[I] or (FEnts[I].Kind <> ekFace) then Continue;
    if Length(FEnts[I].Poly) < 3 then Continue;
    for K := 0 to High(FEnts[I].Poly) do
    begin
      P := FEnts[I].Poly[K];
      Q := FEnts[I].Poly[(K + 1) mod Length(FEnts[I].Poly)];
      if UsesARun(P, Q, FEnts[I].Part) then
      begin
        Marked[I] := True;
        Break;
      end;
    end;
    { an opening's edge holds the face up as much as the outline's }
    if not Marked[I] then
      for H := 0 to High(FEnts[I].Holes) do
      begin
        for K := 0 to High(FEnts[I].Holes[H]) do
        begin
          P := FEnts[I].Holes[H][K];
          Q := FEnts[I].Holes[H][(K + 1) mod Length(FEnts[I].Holes[H])];
          if UsesARun(P, Q, FEnts[I].Part) then
          begin
            Marked[I] := True;
            Break;
          end;
        end;
        if Marked[I] then Break;
      end;
    if Marked[I] then
    begin
      SetLength(Faces, Result + 1);
      Faces[Result] := I;
      Inc(Result);
    end;
  end;
end;

procedure TWorkDoc.VertsOf(const Idx: array of Integer; out Pts: TP3Array);
var
  I, J, K, N: Integer;

  procedure Put(const P: TP3);
  begin
    if N >= Length(Pts) then SetLength(Pts, Max(16, N * 2));
    Pts[N] := P;
    Inc(N);
  end;

begin
  Pts := nil;
  N := 0;
  SetLength(Pts, 16);
  for J := 0 to High(Idx) do
  begin
    I := Idx[J];
    if (I < 0) or (I >= FLive) then Continue;
    Put(FEnts[I].A);
    Put(FEnts[I].B);
    if FEnts[I].Kind = ekArc then Put(FEnts[I].C);
    for K := 0 to High(FEnts[I].Poly) do
      Put(FEnts[I].Poly[K]);
  end;
  SetLength(Pts, N);
end;

{ The edges that lean over to follow a move, matched the same way the move
  matches them, so the preview shows the sides that stretch along instead of
  one side flying off alone. }
procedure TWorkDoc.StretchPreview(const Pts: TP3Array; const D: TP3;
  const Skip: array of Integer; out Segs: TP3Array);
const
  TOL = 1E-7;
var
  Moving: TPointSet;
  I, J, N: Integer;
  Held, MA, MB: Boolean;
  A, B: TP3;

  function Shifted(const P: TP3; out Moved: Boolean): TP3;
  begin
    Moved := Moving.Has(P, TOL);
    if Moved then
      Result := Add3(P, D)
    else
      Result := P;
  end;

begin
  Segs := nil;
  N := 0;
  if Length(Pts) = 0 then Exit;
  Moving := TPointSet.Create(Pts);
  try
    for I := 0 to FLive - 1 do
    begin
      if not (FEnts[I].Kind in [ekLine, ekGuide]) then Continue;
      if FEnts[I].Dim then Continue;
      Held := False;
      for J := 0 to High(Skip) do
        if Skip[J] = I then
        begin
          Held := True;
          Break;
        end;
      if Held then Continue;
      A := Shifted(FEnts[I].A, MA);
      B := Shifted(FEnts[I].B, MB);
      { one end moving and one staying is a stretch; both moving is already
        drawn by the selection's ghost }
      if MA = MB then Continue;
      if N + 2 > Length(Segs) then SetLength(Segs, Max(16, (N + 2) * 2));
      Segs[N] := A; Segs[N + 1] := B;
      Inc(N, 2);
    end;
  finally
    Moving.Free;
  end;
  SetLength(Segs, N);
end;

procedure TWorkDoc.MoveVerts(const Pts: TP3Array; const D: TP3);
const
  TOL = 1E-7;
var
  I, J, K, H, NR: Integer;
  Moving: TPointSet;
  Ride: array of Integer;
  RideA: array of Boolean;

  procedure Shift(var P: TP3);
  begin
    if Moving.Has(P, TOL) then P := Add3(P, D);
  end;

  procedure Bump(var P: TP3);
  begin
    P := Add3(P, D);
  end;

  { is Q on the segment from E to F, within a hair }
  function OnSeg(const Q, E, F: TP3): Boolean;
  var
    L2, T: Double;
    R: TP3;
  begin
    L2 := Sqr(F.X - E.X) + Sqr(F.Y - E.Y) + Sqr(F.Z - E.Z);
    if L2 < 1E-18 then Exit(Dist(Q, E) < 1E-6);
    T := ((Q.X - E.X) * (F.X - E.X) + (Q.Y - E.Y) * (F.Y - E.Y) +
          (Q.Z - E.Z) * (F.Z - E.Z)) / L2;
    if (T < -1E-6) or (T > 1 + 1E-6) then Exit(False);
    R := P3(E.X + (F.X - E.X) * T, E.Y + (F.Y - E.Y) * T,
            E.Z + (F.Z - E.Z) * T);
    Result := Dist(Q, R) < 1E-6;
  end;

begin
  if Length(Pts) = 0 then Exit;
  Moving := TPointSet.Create(Pts);
  try
  { A note's leader points at a place, not a thing.  If the whole line it
    points at is moving, the note comes too.  Worked out before anything
    shifts, since afterwards there is no telling what was on what. }
  NR := 0;
  SetLength(Ride, 0);
  SetLength(RideA, 0);
  for I := 0 to FLive - 1 do
  begin
    if FEnts[I].Part <> FContext then Continue;
    if FEnts[I].Kind <> ekText then Continue;
    if Moving.Has(FEnts[I].B, TOL) then Continue;      { going anyway }
    if Dist(FEnts[I].A, FEnts[I].B) < 1E-9 then Continue;  { no leader }
    for J := 0 to FLive - 1 do
    begin
      if not (FEnts[J].Kind in [ekLine, ekArc]) then Continue;
      if FEnts[J].Part <> FContext then Continue;
      if not (Moving.Has(FEnts[J].A, TOL) and
              Moving.Has(FEnts[J].B, TOL)) then Continue;
      if OnSeg(FEnts[I].B, FEnts[J].A, FEnts[J].B) then
      begin
        SetLength(Ride, NR + 1);
        SetLength(RideA, NR + 1);
        Ride[NR] := I;
        { the words travel with the arrow unless they are already on
          something that is moving, which would carry them twice }
        RideA[NR] := not Moving.Has(FEnts[I].A, TOL);
        Inc(NR);
        Break;
      end;
    end;
  end;

  for I := 0 to FLive - 1 do
  begin
    if FEnts[I].Part <> FContext then Continue;
    Shift(FEnts[I].A);
    Shift(FEnts[I].B);
    if FEnts[I].Kind = ekArc then Shift(FEnts[I].C);
    for K := 0 to High(FEnts[I].Poly) do
      Shift(FEnts[I].Poly[K]);
    for H := 0 to High(FEnts[I].Holes) do
      for K := 0 to High(FEnts[I].Holes[H]) do
        Shift(FEnts[I].Holes[H][K]);
  end;

  for I := 0 to NR - 1 do
  begin
    Bump(FEnts[Ride[I]].B);
    if RideA[I] then Bump(FEnts[Ride[I]].A);
  end;
  finally
    Moving.Free;
  end;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

procedure TWorkDoc.VertsBeyond(const Base, Dir: TP3; out Pts: TP3Array);
const
  TOL = 1E-7;
var
  I, K, H, N: Integer;

  procedure Put(const P: TP3);
  begin
    if Dot3(Sub3(P, Base), Dir) < -TOL then Exit;
    if N >= Length(Pts) then SetLength(Pts, Max(16, N * 2));
    Pts[N] := P;
    Inc(N);
  end;

begin
  Pts := nil;
  N := 0;
  for I := 0 to FLive - 1 do
  begin
    Put(FEnts[I].A);
    Put(FEnts[I].B);
    if FEnts[I].Kind = ekArc then Put(FEnts[I].C);
    for K := 0 to High(FEnts[I].Poly) do Put(FEnts[I].Poly[K]);
    for H := 0 to High(FEnts[I].Holes) do
      for K := 0 to High(FEnts[I].Holes[H]) do Put(FEnts[I].Holes[H][K]);
  end;
  SetLength(Pts, N);
end;

{ What an axis will do to an outline, before it does it.  A lathe spins an
  outline about a line beside it; an axis through the middle sweeps the
  halves into each other.  Corners on both sides of the axis, in the
  outline's plane, mean it splits it; corners on the axis count for neither. }
function TWorkDoc.AxisSplitsFace(Face: Integer; const AxisP, AxisDir: TP3;
  out RLo, RHi: Double): Boolean;
var
  K: Integer;
  Nf, D, E, Perp: TP3;
  S, R: Double;
  Pos, Neg: Boolean;
begin
  Result := False;
  RLo := 0;
  RHi := 0;
  if (Face < 0) or (Face >= FLive) or (FEnts[Face].Kind <> ekFace) then Exit;
  if Length(FEnts[Face].Poly) < 3 then Exit;
  D := Norm3(AxisDir);
  if Dist(D, P3(0, 0, 0)) < 1E-9 then Exit;
  Nf := Norm3(FaceNormal(Face));
  Pos := False;
  Neg := False;
  RLo := 1E30;
  RHi := 0;
  for K := 0 to High(FEnts[Face].Poly) do
  begin
    E := Sub3(FEnts[Face].Poly[K], AxisP);
    { how far off the axis, square to it - the radius this corner sweeps }
    Perp := P3(E.X - D.X * Dot3(E, D), E.Y - D.Y * Dot3(E, D),
               E.Z - D.Z * Dot3(E, D));
    R := Dist(Perp, P3(0, 0, 0));
    if R < RLo then RLo := R;
    if R > RHi then RHi := R;
    { and which side of it, in the plane the outline lies in }
    S := Dot3(Cross3(D, E), Nf);
    if S > 1E-6 then Pos := True
    else if S < -1E-6 then Neg := True;
  end;
  if RLo > RHi then RLo := RHi;
  Result := Pos and Neg;
end;

{ Give a dimension a new length and move the drawing to suit.  Not a
  constraint - a one-off edit, so nothing is stored to go stale.  Every point
  at or past the plane through the moving end, square to the run, moves: a
  rectangle stays a rectangle and anything between the ends stays put.  An
  arc only partly past the plane comes out wrong, as with the move tool. }
function TWorkDoc.ResizeDim(Index: Integer; NewLen: Double;
  MoveB: Boolean): Boolean;
var
  A, B, D, Delta: TP3;
  L, Grow: Double;
  Pts: TP3Array;
begin
  Result := False;
  if (Index < 0) or (Index >= FLive) then Exit;
  if FEnts[Index].Kind <> ekDim then Exit;
  if NewLen <= 0 then Exit;
  A := FEnts[Index].A;
  B := FEnts[Index].B;
  L := Dist(A, B);
  { a dimension of no length has no direction to grow along }
  if L < 1E-9 then Exit;
  Grow := NewLen - L;
  if Abs(Grow) < 1E-9 then Exit;
  D := P3((B.X - A.X) / L, (B.Y - A.Y) / L, (B.Z - A.Z) / L);

  if MoveB then
  begin
    VertsBeyond(B, D, Pts);
    Delta := Mul3(D, Grow);
  end
  else
  begin
    VertsBeyond(A, P3(-D.X, -D.Y, -D.Z), Pts);
    Delta := P3(-D.X * Grow, -D.Y * Grow, -D.Z * Grow);
  end;
  if Length(Pts) = 0 then Exit;
  MoveVerts(Pts, Delta);
  Result := True;
end;

{ Rotation has to know what an arc is: it turns whole onto a free plane whose
  normal is the old one turned, and the start angle is measured again in the
  new plane's basis. }
procedure TWorkDoc.RotateEnt(I: Integer; const Pts: TP3Array;
  const C, Axis: TP3; Ang: Double; All: Boolean);
const
  TOL = 1E-7;
var
  K, H: Integer;
  AU, AV, N, D: TP3;

  function OnSet(const P: TP3): Boolean;
  var
    J: Integer;
  begin
    if All then Exit(True);
    Result := True;
    for J := 0 to High(Pts) do
      if Dist(P, Pts[J]) < TOL then Exit;
    Result := False;
  end;

  procedure Turn(var P: TP3);
  begin
    if OnSet(P) then P := RotP(P, C, Axis, Ang);
  end;

begin
  if FEnts[I].Kind = ekArc then
  begin
    if not (OnSet(FEnts[I].A) or OnSet(FEnts[I].B) or OnSet(FEnts[I].C)) then Exit;
    if FEnts[I].Plane = plFree then
      N := Norm3(FEnts[I].Nm)
    else
    begin
      PlaneAxes(FEnts[I].Plane, AU, AV);
      N := Norm3(Cross3(AU, AV));
    end;
    FEnts[I].A := RotP(FEnts[I].A, C, Axis, Ang);
    FEnts[I].B := RotP(FEnts[I].B, C, Axis, Ang);
    FEnts[I].C := RotP(FEnts[I].C, C, Axis, Ang);
    N := RotV(N, Axis, Ang);
    FEnts[I].Plane := plFree;
    FEnts[I].Nm := N;
    AxesFromNormal(N, AU, AV);
    D := Sub3(FEnts[I].A, FEnts[I].C);
    FEnts[I].A0 := ArcTan2(Dot3(D, AV), Dot3(D, AU));
    Exit;
  end;
  { a dimension's C is the offset from what it measures to where its line
    sits - a direction, not a place - so it turns with the dimension but is
    not swung round the center }
  if (FEnts[I].Kind = ekDim) and (OnSet(FEnts[I].A) or OnSet(FEnts[I].B)) then
    FEnts[I].C := RotV(FEnts[I].C, Axis, Ang);
  Turn(FEnts[I].A);
  Turn(FEnts[I].B);
  for K := 0 to High(FEnts[I].Poly) do
    Turn(FEnts[I].Poly[K]);
  for H := 0 to High(FEnts[I].Holes) do
    for K := 0 to High(FEnts[I].Holes[H]) do
      Turn(FEnts[I].Holes[H][K]);
end;

procedure TWorkDoc.RotateVerts(const Pts: TP3Array; const C, Axis: TP3; Ang: Double);
var
  I: Integer;
begin
  if (Length(Pts) = 0) or (Abs(Ang) < 1E-12) then Exit;
  for I := 0 to FLive - 1 do
    if FEnts[I].Part = FContext then       { another group's corners stay put }
      RotateEnt(I, Pts, C, Axis, Ang, False);
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

procedure TWorkDoc.ArrayMove(const Src: array of Integer; const D: TP3; N: Integer;
  Divide: Boolean; out Made: TIntArrayW);
var
  K, I, Base, M: Integer;
  F: Double;
begin
  Made := nil;
  if (N < 1) or (Length(Src) = 0) then Exit;
  for K := 1 to N do
  begin
    if Divide then F := K / N else F := K;
    Base := FLive;
    Duplicate(Src, Mul3(D, F));
    M := Length(Made);
    SetLength(Made, M + (FLive - Base));
    for I := Base to FLive - 1 do Made[M + I - Base] := I;
  end;
end;

procedure TWorkDoc.ArrayRotate(const Src: array of Integer; const C, Axis: TP3;
  Ang: Double; N: Integer; Divide: Boolean; out Made: TIntArrayW);
var
  K, I, Base, M: Integer;
  F: Double;
  Fresh: TIntArrayW;
begin
  Made := nil;
  if (N < 1) or (Length(Src) = 0) then Exit;
  for K := 1 to N do
  begin
    if Divide then F := K / N else F := K;
    Base := FLive;
    Duplicate(Src, P3(0, 0, 0));
    SetLength(Fresh, FLive - Base);
    for I := 0 to High(Fresh) do Fresh[I] := Base + I;
    RotateEnts(Fresh, C, Axis, Ang * F);
    M := Length(Made);
    SetLength(Made, M + Length(Fresh));
    for I := 0 to High(Fresh) do Made[M + I] := Fresh[I];
  end;
end;

function TWorkDoc.MiddleOf(const Idx: array of Integer; out Mid: TP3): Boolean;
var
  Lo, Hi: TP3;
begin
  Result := SpanOf(Idx, Lo, Hi);
  if Result then
    Mid := P3((Lo.X + Hi.X) / 2, (Lo.Y + Hi.Y) / 2, (Lo.Z + Hi.Z) / 2)
  else
    Mid := P3(0, 0, 0);
end;

function TWorkDoc.SpanOf(const Idx: array of Integer; out Lo, Hi: TP3): Boolean;
var
  I, J, K: Integer;
  Any: Boolean;

  procedure Grow(const P: TP3);
  begin
    if not Any then
    begin
      Lo := P;
      Hi := P;
      Any := True;
      Exit;
    end;
    Lo.X := Min(Lo.X, P.X); Lo.Y := Min(Lo.Y, P.Y); Lo.Z := Min(Lo.Z, P.Z);
    Hi.X := Max(Hi.X, P.X); Hi.Y := Max(Hi.Y, P.Y); Hi.Z := Max(Hi.Z, P.Z);
  end;

  procedure Take(I: Integer);
  var
    M: Integer;
  begin
    if (I < 0) or (I >= FLive) then Exit;
    case FEnts[I].Kind of
      ekArc:
        begin
          Grow(P3(FEnts[I].C.X - FEnts[I].R, FEnts[I].C.Y - FEnts[I].R,
                  FEnts[I].C.Z - FEnts[I].R));
          Grow(P3(FEnts[I].C.X + FEnts[I].R, FEnts[I].C.Y + FEnts[I].R,
                  FEnts[I].C.Z + FEnts[I].R));
        end;
      ekFace:
        for M := 0 to High(FEnts[I].Poly) do Grow(FEnts[I].Poly[M]);
    else
      Grow(FEnts[I].A);
      Grow(FEnts[I].B);
    end;
  end;

begin
  Any := False;
  Lo := P3(0, 0, 0);
  Hi := P3(0, 0, 0);
  if Length(Idx) > 0 then
    for J := 0 to High(Idx) do Take(Idx[J])
  else
    for K := 0 to FLive - 1 do Take(K);
  Result := Any;
end;

procedure TWorkDoc.TranslateEnts(const Idx: array of Integer; const D: TP3);
var
  J, I, K, H: Integer;

  function Sh(const P: TP3): TP3;
  begin
    Result := Add3(P, D);
  end;

begin
  for J := 0 to High(Idx) do
  begin
    I := Idx[J];
    if (I < 0) or (I >= FLive) then Continue;
    FEnts[I].A := Sh(FEnts[I].A);
    FEnts[I].B := Sh(FEnts[I].B);
    { an arc's C is its center, a point; a dimension's C is the offset from
      what it measures to where its line sits, a vector, which a move must
      leave alone or the line runs off by the whole distance moved }
    if FEnts[I].Kind = ekArc then FEnts[I].C := Sh(FEnts[I].C);
    for K := 0 to High(FEnts[I].Poly) do FEnts[I].Poly[K] := Sh(FEnts[I].Poly[K]);
    for H := 0 to High(FEnts[I].Holes) do
      for K := 0 to High(FEnts[I].Holes[H]) do FEnts[I].Holes[H][K] := Sh(FEnts[I].Holes[H][K]);
  end;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

procedure TWorkDoc.RotateEnts(const Idx: array of Integer; const C, Axis: TP3; Ang: Double);
var
  J: Integer;
begin
  for J := 0 to High(Idx) do
    if (Idx[J] >= 0) and (Idx[J] < FLive) then
      RotateEnt(Idx[J], nil, C, Axis, Ang, True);
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

function TWorkDoc.OutlineWorld(I: Integer): TP3Array;
var
  K, Steps: Integer;
begin
  Result := nil;
  if (I < 0) or (I >= FLive) then Exit;
  case FEnts[I].Kind of
    ekArc:
      begin
        Steps := ArcSteps(FEnts[I]);
        SetLength(Result, Steps + 1);
        for K := 0 to Steps do
          Result[K] := ArcPoint(FEnts[I].C, FEnts[I].R,
            FEnts[I].A0 + FEnts[I].Sweep * K / Steps, FEnts[I].Plane, FEnts[I].Nm);
      end;
    ekFace:
      begin
        SetLength(Result, Length(FEnts[I].Poly) + 1);
        for K := 0 to High(FEnts[I].Poly) do
          Result[K] := FEnts[I].Poly[K];
        if Length(FEnts[I].Poly) > 0 then
          Result[High(Result)] := Result[0];
      end;
    ekText:
      begin
        SetLength(Result, 1);
        Result[0] := FEnts[I].A;
      end;
    ekBore: ;
  else
    SetLength(Result, 2);
    Result[0] := FEnts[I].A;
    Result[1] := FEnts[I].B;
  end;
end;

procedure TWorkDoc.Duplicate(const Idx: array of Integer; const D: TP3);
var
  J, I, K, H, Base, G: Integer;
  Src, Dst: array of Integer;    { old group id -> the new one it becomes }
  PSrc, PDst, Copied: array of Integer;   { the same for groups }

  { Solids are told apart by group id, so a copy needs a new one or push/pull
    on one deforms the other. }
  function Remap(Old: Integer): Integer;
  var
    N: Integer;
  begin
    if Old = 0 then Exit(0);
    for N := 0 to High(Src) do
      if Src[N] = Old then Exit(Dst[N]);
    Inc(FNextGrp);
    SetLength(Src, Length(Src) + 1);
    SetLength(Dst, Length(Dst) + 1);
    Src[High(Src)] := Old;
    Dst[High(Dst)] := FNextGrp;
    Result := FNextGrp;
  end;

  { Groups likewise, but only those whose record is being copied; a member
    copied without its record stays in its group. }
  function RemapPart(Old: Integer): Integer;
  var
    N: Integer;
    Known: Boolean;
  begin
    if Old = 0 then Exit(0);
    for N := 0 to High(PSrc) do
      if PSrc[N] = Old then Exit(PDst[N]);
    Known := False;
    for N := 0 to High(Copied) do
      if Copied[N] = Old then Known := True;
    if not Known then Exit(Old);
    Inc(FNextPart);
    SetLength(PSrc, Length(PSrc) + 1);
    SetLength(PDst, Length(PDst) + 1);
    PSrc[High(PSrc)] := Old;
    PDst[High(PDst)] := FNextPart;
    Result := FNextPart;
  end;

begin
  Src := nil;
  Dst := nil;
  PSrc := nil;
  PDst := nil;
  Copied := nil;
  Base := FLive;
  for J := 0 to High(Idx) do
    if (Idx[J] >= 0) and (Idx[J] < Base) and (FEnts[Idx[J]].Kind = ekPart) then
    begin
      SetLength(Copied, Length(Copied) + 1);
      Copied[High(Copied)] := FEnts[Idx[J]].Grp;
    end;
  for J := 0 to High(Idx) do
  begin
    I := Idx[J];
    if (I < 0) or (I >= Base) then Continue;
    Room;
    Finalize(FEnts[FLive]);
    FillChar(FEnts[FLive], SizeOf(TWorkEnt), 0);
    FEnts[FLive] := FEnts[I];
    SetLength(FEnts[FLive].Poly, Length(FEnts[I].Poly));
    for K := 0 to High(FEnts[I].Poly) do
      FEnts[FLive].Poly[K] := Add3(FEnts[I].Poly[K], D);
    { The holes, deep and shifted, or the copy shares the original's window. }
    FEnts[FLive].Holes := nil;
    SetLength(FEnts[FLive].Holes, Length(FEnts[I].Holes));
    for H := 0 to High(FEnts[I].Holes) do
    begin
      SetLength(FEnts[FLive].Holes[H], Length(FEnts[I].Holes[H]));
      for K := 0 to High(FEnts[I].Holes[H]) do
        FEnts[FLive].Holes[H][K] := Add3(FEnts[I].Holes[H][K], D);
    end;
    FEnts[FLive].A := Add3(FEnts[I].A, D);
    FEnts[FLive].B := Add3(FEnts[I].B, D);
    FEnts[FLive].C := Add3(FEnts[I].C, D);
    { a record's Grp is its group id, not a solid's }
    if FEnts[I].Kind = ekPart then G := RemapPart(FEnts[I].Grp)
    else G := Remap(FEnts[I].Grp);
    FEnts[FLive].Grp := G;
    FEnts[FLive].Part := RemapPart(FEnts[I].Part);
    Inc(FLive);
  end;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

{ A deep copy of these entities with nothing pointing back at the document,
  so it survives a switch to another sheet. }
function TWorkDoc.CopyOut(const Idx: array of Integer): TWorkEntArray;
var
  J, I, N: Integer;
begin
  Result := nil;
  SetLength(Result, Length(Idx));
  N := 0;
  for J := 0 to High(Idx) do
  begin
    I := Idx[J];
    if (I < 0) or (I >= FLive) then Continue;
    Result[N] := CopyEnt(FEnts[I]);
    Inc(N);
  end;
  SetLength(Result, N);
end;

{ Put a copy back in, offset by D, and say which ones went in.  Group ids are
  remapped as in Duplicate, which another sheet needs anyway since each sheet
  numbers its own.  Bores are dropped; they mean nothing beside a copy. }
function TWorkDoc.PasteIn(const Ents: TWorkEntArray; const D: TP3;
  out First, Last: Integer): Integer;
var
  J, K, H: Integer;
  Src, Dst: array of Integer;
  PSrc, PDst, Copied: array of Integer;   { the same for groups - see Duplicate }

  function Remap(Old: Integer): Integer;
  var
    N: Integer;
  begin
    if Old = 0 then Exit(0);
    for N := 0 to High(Src) do
      if Src[N] = Old then Exit(Dst[N]);
    Inc(FNextGrp);
    SetLength(Src, Length(Src) + 1);
    SetLength(Dst, Length(Dst) + 1);
    Src[High(Src)] := Old;
    Dst[High(Dst)] := FNextGrp;
    Result := FNextGrp;
  end;

  function RemapPart(Old: Integer): Integer;
  var
    N: Integer;
    Known: Boolean;
  begin
    if Old = 0 then Exit(0);
    for N := 0 to High(PSrc) do
      if PSrc[N] = Old then Exit(PDst[N]);
    Known := False;
    for N := 0 to High(Copied) do
      if Copied[N] = Old then Known := True;
    { pasted into a sheet that has no such group, a member goes in loose }
    if not Known then
      if PartEnt(Old) >= 0 then Exit(Old) else Exit(0);
    Inc(FNextPart);
    SetLength(PSrc, Length(PSrc) + 1);
    SetLength(PDst, Length(PDst) + 1);
    PSrc[High(PSrc)] := Old;
    PDst[High(PDst)] := FNextPart;
    Result := FNextPart;
  end;

  procedure Shift(var P: TP3);
  begin
    P := Add3(P, D);
  end;

begin
  Result := 0;
  First := FLive;
  Last := FLive - 1;
  Src := nil;
  Dst := nil;
  PSrc := nil;
  PDst := nil;
  Copied := nil;
  for J := 0 to High(Ents) do
    if Ents[J].Kind = ekPart then
    begin
      SetLength(Copied, Length(Copied) + 1);
      Copied[High(Copied)] := Ents[J].Grp;
    end;
  for J := 0 to High(Ents) do
  begin
    if Ents[J].Kind = ekBore then Continue;
    Room;
    Finalize(FEnts[FLive]);
    FillChar(FEnts[FLive], SizeOf(TWorkEnt), 0);
    FEnts[FLive] := CopyEnt(Ents[J]);
    Shift(FEnts[FLive].A);
    Shift(FEnts[FLive].B);
    Shift(FEnts[FLive].C);
    for K := 0 to High(FEnts[FLive].Poly) do Shift(FEnts[FLive].Poly[K]);
    for H := 0 to High(FEnts[FLive].Holes) do
      for K := 0 to High(FEnts[FLive].Holes[H]) do Shift(FEnts[FLive].Holes[H][K]);
    if Ents[J].Kind = ekPart then FEnts[FLive].Grp := RemapPart(Ents[J].Grp)
    else FEnts[FLive].Grp := Remap(Ents[J].Grp);
    { into the open group here, unless it came with a group of its own }
    if Ents[J].Part = 0 then FEnts[FLive].Part := FStamp
    else FEnts[FLive].Part := RemapPart(Ents[J].Part);
    Last := FLive;
    Inc(FLive);
    Inc(Result);
  end;
  if Result > 0 then
  begin
    FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
  end;
end;

{ Two screen segments, do they cross?  Used by the selection box. }
function SegsCross(AX, AY, BX, BY, CX, CY, DX_, DY_: Double): Boolean;
var
  R1, R2, R3, R4: Double;

  function Side(PX, PY, QX, QY, RX, RY: Double): Double;
  begin
    Result := (QX - PX) * (RY - PY) - (QY - PY) * (RX - PX);
  end;

begin
  R1 := Side(AX, AY, BX, BY, CX, CY);
  R2 := Side(AX, AY, BX, BY, DX_, DY_);
  R3 := Side(CX, CY, DX_, DY_, AX, AY);
  R4 := Side(CX, CY, DX_, DY_, BX, BY);
  Result := (((R1 > 0) <> (R2 > 0)) and ((R3 > 0) <> (R4 > 0)));
end;

{ Does this screen segment meet the box at all? }
function SegHitsRect(AX, AY, BX, BY, X0, Y0, X1, Y1: Double): Boolean;
begin
  { an end inside is the common case and answers without any arithmetic }
  if ((AX >= X0) and (AX <= X1) and (AY >= Y0) and (AY <= Y1)) or
     ((BX >= X0) and (BX <= X1) and (BY >= Y0) and (BY <= Y1)) then
    Exit(True);
  { wholly off one side }
  if (Max(AX, BX) < X0) or (Min(AX, BX) > X1) or
     (Max(AY, BY) < Y0) or (Min(AY, BY) > Y1) then
    Exit(False);
  Result := SegsCross(AX, AY, BX, BY, X0, Y0, X1, Y0) or
            SegsCross(AX, AY, BX, BY, X1, Y0, X1, Y1) or
            SegsCross(AX, AY, BX, BY, X1, Y1, X0, Y1) or
            SegsCross(AX, AY, BX, BY, X0, Y1, X0, Y0);
end;

{ Is this screen point inside the projected loop?  Even-odd, the same rule
  the face fill uses. }
function LoopHasPt(const Pts: array of TPointF; SX, SY: Double): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  J := High(Pts);
  for I := 0 to High(Pts) do
  begin
    if ((Pts[I].Y > SY) <> (Pts[J].Y > SY)) and
       (SX < (Pts[J].X - Pts[I].X) * (SY - Pts[I].Y) /
             (Pts[J].Y - Pts[I].Y) + Pts[I].X) then
      Result := not Result;
    J := I;
  end;
end;

{ Guides come along only when the box caught nothing else - one runs through
  almost any box, and a guide is not part of the drawing. }
function TWorkDoc.BoxPick(const V: TProjector; X0, Y0, X1, Y1: Double;
  Crossing: Boolean): TIntArrayW;
var
  I, N, G: Integer;
  Guides: TIntArrayW;
begin
  Result := nil;
  Guides := nil;
  N := 0;
  G := 0;
  for I := 0 to FLive - 1 do
    if BoxTakes(V, I, X0, Y0, X1, Y1, Crossing) then
    begin
      if FEnts[I].Kind = ekGuide then
      begin
        if G >= Length(Guides) then SetLength(Guides, Max(16, G * 2));
        Guides[G] := I;
        Inc(G);
      end
      else
      begin
        if N >= Length(Result) then SetLength(Result, Max(64, N * 2));
        Result[N] := I;
        Inc(N);
      end;
    end;
  if N > 0 then
    SetLength(Result, N)
  else
  begin
    SetLength(Guides, G);
    Result := Guides;
  end;
end;

{ Does a box dragged over the screen take this thing?  A containing box
  (left to right) takes what lies wholly inside, so the bounds will do.  A
  crossing box (right to left) takes what it touches - the drawn segments,
  and a face's inside.  Guides answer the crossing question either way, bores
  are never taken, and hidden faces are taken too: a box sweeps an area. }
function TWorkDoc.BoxTakes(const V: TProjector; I: Integer;
  X0, Y0, X1, Y1: Double; Crossing: Boolean): Boolean;
var
  K, H, N: Integer;
  T: Double;
  BX0, BY0, BX1, BY1: Double;
  PA, PB: TPointF;
  QA, QB: TP3;
  Scr: array of TPointF;
  DG: TDimGeom;

  function Hits(const MA, MB: TP3): Boolean;
  var
    SA, SB: TPointF;
  begin
    SA := Project(V, MA);
    SB := Project(V, MB);
    Result := SegHitsRect(SA.X, SA.Y, SB.X, SB.Y, X0, Y0, X1, Y1);
  end;

begin
  Result := False;
  if (I < 0) or (I >= FLive) then Exit;
  if X1 < X0 then begin T := X0; X0 := X1; X1 := T; end;
  if Y1 < Y0 then begin T := Y0; Y0 := Y1; Y1 := T; end;
  if FEnts[I].Kind = ekBore then Exit;
  if not InSlice(I) then Exit;
  if (FEnts[I].Kind = ekGuide) and FGuidesHidden then Exit;

  { a guide line has no ends to be inside anything, so it answers the
    crossing question whichever way the box was dragged }
  if (FEnts[I].Kind = ekGuide) and (Dist(FEnts[I].A, FEnts[I].B) > 1E-9) then
  begin
    PA := Project(V, FEnts[I].A);
    PB := Project(V, FEnts[I].B);
    { out along its own direction, far enough to cross any view of it }
    QA := P3(FEnts[I].A.X + (FEnts[I].A.X - FEnts[I].B.X) * 5000,
             FEnts[I].A.Y + (FEnts[I].A.Y - FEnts[I].B.Y) * 5000,
             FEnts[I].A.Z + (FEnts[I].A.Z - FEnts[I].B.Z) * 5000);
    QB := P3(FEnts[I].B.X + (FEnts[I].B.X - FEnts[I].A.X) * 5000,
             FEnts[I].B.Y + (FEnts[I].B.Y - FEnts[I].A.Y) * 5000,
             FEnts[I].B.Z + (FEnts[I].B.Z - FEnts[I].A.Z) * 5000);
    Exit(Hits(QA, QB));
  end;

  ScreenBounds(V, I, BX0, BY0, BX1, BY1);
  if BX1 < BX0 then Exit;

  if not Crossing then
    Exit((BX0 >= X0) and (BX1 <= X1) and (BY0 >= Y0) and (BY1 <= Y1));

  { nowhere near, and none of the rest is worth doing }
  if (BX1 < X0) or (BX0 > X1) or (BY1 < Y0) or (BY0 > Y1) then Exit;

  case FEnts[I].Kind of
    ekArc:
      begin
        QA := ArcPoint(FEnts[I].C, FEnts[I].R, FEnts[I].A0,
                       FEnts[I].Plane, FEnts[I].Nm);
        for K := 1 to 24 do
        begin
          QB := ArcPoint(FEnts[I].C, FEnts[I].R,
                  FEnts[I].A0 + FEnts[I].Sweep * K / 24,
                  FEnts[I].Plane, FEnts[I].Nm);
          if Hits(QA, QB) then Exit(True);
          QA := QB;
        end;
      end;
    ekFace:
      begin
        N := Length(FEnts[I].Poly);
        if N < 3 then Exit;
        for K := 0 to N - 1 do
          if Hits(FEnts[I].Poly[K], FEnts[I].Poly[(K + 1) mod N]) then Exit(True);
        for H := 0 to High(FEnts[I].Holes) do
          if Length(FEnts[I].Holes[H]) >= 3 then
            for K := 0 to High(FEnts[I].Holes[H]) do
              if Hits(FEnts[I].Holes[H][K],
                      FEnts[I].Holes[H][(K + 1) mod Length(FEnts[I].Holes[H])]) then
                Exit(True);
        { a box wholly inside the face is on the face, which is as much a
          touch as crossing its edge }
        SetLength(Scr, N);
        for K := 0 to N - 1 do Scr[K] := Project(V, FEnts[I].Poly[K]);
        Result := LoopHasPt(Scr, (X0 + X1) / 2, (Y0 + Y1) / 2);
      end;
    ekText:
      { the words are the note - the same box the cursor is tested against }
      if FEnts[I].BoxR > FEnts[I].BoxL then
        Result := (FEnts[I].BoxR >= X0) and (FEnts[I].BoxL <= X1) and
                  (FEnts[I].BoxB >= Y0) and (FEnts[I].BoxT <= Y1)
      else
      begin
        PA := Project(V, FEnts[I].A);
        Result := (PA.X >= X0) and (PA.X <= X1) and (PA.Y >= Y0) and (PA.Y <= Y1);
      end;
    ekDim:
      { the drawn line and its witness lines, which is what a dimension looks
        like - not the chord through the geometry it measures }
      if DimGeometry(V, FEnts[I].A, FEnts[I].B, FEnts[I].C, usImperial, DG,
           FEnts[I].Txt) then
        Result := SegHitsRect(DG.LA.X, DG.LA.Y, DG.LB.X, DG.LB.Y, X0, Y0, X1, Y1) or
                  SegHitsRect(DG.A.X, DG.A.Y, DG.W1.X, DG.W1.Y, X0, Y0, X1, Y1) or
                  SegHitsRect(DG.B.X, DG.B.Y, DG.W2.X, DG.W2.Y, X0, Y0, X1, Y1);
  else
    { a line, and a guide point, which is a guide with no length }
    Result := Hits(FEnts[I].A, FEnts[I].B);
  end;
end;

procedure TWorkDoc.ScreenBounds(const V: TProjector; I: Integer;
  out X0, Y0, X1, Y1: Double);
var
  K: Integer;
  P: TPointF;

  procedure Grow(const Q: TP3);
  var
    S: TPointF;
  begin
    S := Project(V, Q);
    X0 := Min(X0, S.X); X1 := Max(X1, S.X);
    Y0 := Min(Y0, S.Y); Y1 := Max(Y1, S.Y);
  end;

begin
  X0 := 1E30; Y0 := 1E30; X1 := -1E30; Y1 := -1E30;
  if (I < 0) or (I >= FLive) then Exit;
  Grow(FEnts[I].A);
  Grow(FEnts[I].B);
  if FEnts[I].Kind = ekArc then
  begin
    P := Project(V, FEnts[I].C);
    X0 := Min(X0, P.X - FEnts[I].R * V.Ppu);
    X1 := Max(X1, P.X + FEnts[I].R * V.Ppu);
    Y0 := Min(Y0, P.Y - FEnts[I].R * V.Ppu);
    Y1 := Max(Y1, P.Y + FEnts[I].R * V.Ppu);
  end;
  for K := 0 to High(FEnts[I].Poly) do
    Grow(FEnts[I].Poly[K]);
end;

function TWorkDoc.EdgeWeight(const A, B: TP3): Single;
const
  TOL = 1E-7;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FLive - 1 do
    if FEnts[I].Kind = ekLine then
      if (SamePt(FEnts[I].A, A, TOL) and SamePt(FEnts[I].B, B, TOL)) or
         (SamePt(FEnts[I].A, B, TOL) and SamePt(FEnts[I].B, A, TOL)) then
        Exit(FEnts[I].Weight);
end;

{ The ink of the edges round this face, so a raised letter's new edges match
  the outline's pen and not the face's color.  An exact outline piece first,
  then any line or arc ending on a corner, since a side cut by a crossing no
  longer runs corner to corner. }
function TWorkDoc.OutlineInk(Face: Integer; Default: TColor): TColor;
const
  TOL = 1E-7;
var
  I, K, N: Integer;
  A, B: TP3;
begin
  Result := Default;
  if (Face < 0) or (Face >= FLive) then Exit;
  N := Length(FEnts[Face].Poly);
  for K := 0 to N - 1 do
  begin
    A := FEnts[Face].Poly[K];
    B := FEnts[Face].Poly[(K + 1) mod N];
    for I := 0 to FLive - 1 do
      if FEnts[I].Kind = ekLine then
        if (SamePt(FEnts[I].A, A, TOL) and SamePt(FEnts[I].B, B, TOL)) or
           (SamePt(FEnts[I].A, B, TOL) and SamePt(FEnts[I].B, A, TOL)) then
          Exit(FEnts[I].Ink);
  end;
  for K := 0 to N - 1 do
  begin
    A := FEnts[Face].Poly[K];
    for I := 0 to FLive - 1 do
      if FEnts[I].Kind in [ekLine, ekArc] then
        if SamePt(FEnts[I].A, A, TOL) or SamePt(FEnts[I].B, A, TOL) then
          Exit(FEnts[I].Ink);
  end;
end;

{ Hand every edge lying along this face's outline to the given group.  An
  edge counts when every point that defines it sits on the outline - both
  ends of a line, or a handful of samples round an arc. }
procedure TWorkDoc.ClaimOutline(Face, G: Integer);
const
  TOL = 1E-6;
  ARC_SAMPLES = 12;
var
  I, K, N, J: Integer;
  Poly: TP3Array;

  function OnOutline(const P: TP3): Boolean;
  var
    Q: Integer;
    T, Off: Double;
    A, B, D: TP3;
    L2: Double;
  begin
    Result := True;
    for Q := 0 to N - 1 do
    begin
      A := Poly[Q];
      B := Poly[(Q + 1) mod N];
      D := Sub3(B, A);
      L2 := D.X * D.X + D.Y * D.Y + D.Z * D.Z;
      if L2 < 1E-18 then Continue;
      T := ((P.X - A.X) * D.X + (P.Y - A.Y) * D.Y + (P.Z - A.Z) * D.Z) / L2;
      T := EnsureRange(T, 0, 1);
      Off := Dist(P, P3(A.X + D.X * T, A.Y + D.Y * T, A.Z + D.Z * T));
      if Off < TOL then Exit;
    end;
    Result := False;
  end;

begin
  Poly := FEnts[Face].Poly;
  N := Length(Poly);
  if N < 3 then Exit;
  for I := 0 to FLive - 1 do
  begin
    if FEnts[I].Grp <> 0 then Continue;
    case FEnts[I].Kind of
      ekLine:
        if OnOutline(FEnts[I].A) and OnOutline(FEnts[I].B) then
          FEnts[I].Grp := G;
      ekArc:
        begin
          J := 0;
          for K := 0 to ARC_SAMPLES do
            if OnOutline(ArcPoint(FEnts[I].C, FEnts[I].R,
                 FEnts[I].A0 + FEnts[I].Sweep * K / ARC_SAMPLES,
                 FEnts[I].Plane, FEnts[I].Nm)) then Inc(J);
          if J = ARC_SAMPLES + 1 then FEnts[I].Grp := G;
        end;
    end;
  end;
end;

{ Is P inside the flat loop, both taken in the loop's plane?  Even-odd, on
  the loop's own two axes.  hsFaceFinder has the general one; this unit cannot
  use hsFaceFinder, which uses it. }
function LoopContains(const P: TP3; const Loop: TP3Array; const N: TP3): Boolean;
var
  AU, AV: TP3;
  I, J: Integer;
  PX, PY, AX, AY, BX, BY: Double;
begin
  Result := False;
  AxesFromNormal(N, AU, AV);
  PX := Dot3(P, AU);
  PY := Dot3(P, AV);
  J := High(Loop);
  for I := 0 to High(Loop) do
  begin
    AX := Dot3(Loop[I], AU); AY := Dot3(Loop[I], AV);
    BX := Dot3(Loop[J], AU); BY := Dot3(Loop[J], AV);
    if ((AY > PY) <> (BY > PY)) and
       (PX < (BX - AX) * (PY - AY) / (BY - AY) + AX) then
      Result := not Result;
    J := I;
  end;
end;

function TWorkDoc.TunnelThrough(Index: Integer; const Top: TP3Array;
  const Nm: TP3; Dist: Double): Boolean;
var
  F, I, J, K, N, G, Far: Integer;
  FN, Mid: TP3;
  Size, Tol: Double;
  Quad: array[0..3] of TP3;
  Ink, LineInk: TColor;
  Wt: Single;
  Holes: array of TP3Array;
  Near: Integer;
  Opened, Pocket: Boolean;
begin
  Result := False;
  Near := -1;
  N := Length(Top);
  if N < 3 then Exit;
  { Whose solid is being pushed through?  A piece cut out of a wall carries
    the wall's group.  A window drawn in the middle of a wall is a loose face
    lying in the wall's opening, so the wall it lies on says. }
  G := 0;
  if FEnts[Index].Solid then G := FEnts[Index].Grp;
  if G = 0 then
  begin
    Mid := P3(0, 0, 0);
    for I := 0 to High(FEnts[Index].Poly) do
      Mid := Add3(Mid, FEnts[Index].Poly[I]);
    I := Length(FEnts[Index].Poly);
    Mid := P3(Mid.X / I, Mid.Y / I, Mid.Z / I);
    for F := 0 to FLive - 1 do
    begin
      if (F = Index) or (FEnts[F].Kind <> ekFace) or not FEnts[F].Solid or
         (FEnts[F].Grp = 0) or (Length(FEnts[F].Poly) < 3) then Continue;
      FN := FaceNormal(F);
      if Abs(Abs(Dot3(FN, Nm)) - 1) > 1E-6 then Continue;
      if Abs(Dot3(FN, Sub3(Mid, FEnts[F].Poly[0]))) > 1E-6 then Continue;
      if LoopContains(Mid, FEnts[F].Poly, FN) then
      begin
        G := FEnts[F].Grp;
        Near := F;
        Break;
      end;
    end;
  end;
  if G = 0 then Exit;
  Size := 0;
  { Dist is the push here, so the spread is worked out by hand }
  for I := 0 to N - 1 do
    Size := Max(Size, Sqrt(Sqr(Top[I].X - Top[0].X) + Sqr(Top[I].Y - Top[0].Y) +
                           Sqr(Top[I].Z - Top[0].Z)));
  Tol := 1E-6 * (1 + Size + Abs(Dist));

  { the face the push lands on: same solid, parallel, in the plane the far
    end has reached, and big enough to hold the whole opening }
  Mid := P3(0, 0, 0);
  for I := 0 to N - 1 do Mid := Add3(Mid, Top[I]);
  Mid := P3(Mid.X / N, Mid.Y / N, Mid.Z / N);
  Far := -1;
  for F := 0 to FLive - 1 do
  begin
    if (F = Index) or (FEnts[F].Kind <> ekFace) or (FEnts[F].Grp <> G) then Continue;
    if Length(FEnts[F].Poly) < 3 then Continue;
    FN := FaceNormal(F);
    if Abs(Abs(Dot3(FN, Nm)) - 1) > 1E-6 then Continue;
    if Abs(Dot3(FN, Sub3(Top[0], FEnts[F].Poly[0]))) > Tol then Continue;
    K := 0;
    for I := 0 to N - 1 do
      if LoopContains(Top[I], FEnts[F].Poly, FN) then Inc(K);
    if (K = N) and LoopContains(Mid, FEnts[F].Poly, FN) then
    begin
      Far := F;
      Break;
    end;
  end;
  { No far face: the push stops inside the solid.  Pushed inward, a plug
    makes a pocket - a tunnel with a floor where the opening would have
    been.  Pushed outward, or not a plug, it is an extrusion for the caller. }
  Pocket := (Far < 0) and (Dist < 0) and FEnts[Index].Solid and
            (IsPatch(Index) or not WallsSquareTo(Index));
  if (Far < 0) and not Pocket then Exit;

  Ink := FEnts[Index].Ink;
  LineInk := OutlineInk(Index, Ink);
  Wt := EdgeWeight(FEnts[Index].Poly[0], FEnts[Index].Poly[1]);
  if Wt <= 0 then Wt := FEnts[Index].Weight;
  if Wt <= 0 then Wt := 1;

  { The near wall has to be open too: a window drawn touching an edge may not
    have cut it yet. }
  if Near >= 0 then
  begin
    Opened := False;
    Mid := P3(0, 0, 0);
    for I := 0 to High(FEnts[Index].Poly) do
      Mid := Add3(Mid, FEnts[Index].Poly[I]);
    I := Length(FEnts[Index].Poly);
    Mid := P3(Mid.X / I, Mid.Y / I, Mid.Z / I);
    FN := FaceNormal(Near);
    for I := 0 to High(FEnts[Near].Holes) do
      if LoopContains(Mid, FEnts[Near].Holes[I], FN) then Opened := True;
    if not Opened then
    begin
      SetLength(Holes, Length(FEnts[Near].Holes) + 1);
      for I := 0 to High(FEnts[Near].Holes) do Holes[I] := FEnts[Near].Holes[I];
      Holes[High(Holes)] := Copy(FEnts[Index].Poly, 0, Length(FEnts[Index].Poly));
      SetFaceHoles(Near, Holes);
    end;
  end;

  if Pocket then
  begin
    { the floor of the pocket: the face itself, moved down, still facing
      the way it did - out of the solid, up the pocket }
    AddFaceRaw(Top, Ink, True);
    FEnts[FLive - 1].Grp := G;
    if FEnts[Index].MatSet then SetMaterial(FLive - 1, FEnts[Index].Mat);
    if Dot3(FaceNormal(FLive - 1), Nm) < 0 then FlipFace(FLive - 1);
  end
  else
  begin
    { the far face gets the opening }
    SetLength(Holes, Length(FEnts[Far].Holes) + 1);
    for I := 0 to High(FEnts[Far].Holes) do Holes[I] := FEnts[Far].Holes[I];
    Holes[High(Holes)] := Copy(Top, 0, N);
    SetFaceHoles(Far, Holes);
  end;

  { the walls line the tunnel, facing inward, and a curved opening has its
    creases softened as an extrusion's are.  Mid is the opening's middle, for
    turning each wall to face it. }
  Mid := P3(0, 0, 0);
  for I := 0 to N - 1 do
    Mid := Add3(Mid, FEnts[Index].Poly[I]);
  Mid := P3(Mid.X / N, Mid.Y / N, Mid.Z / N);
  for I := 0 to N - 1 do
  begin
    J := (I + 1) mod N;
    Quad[0] := FEnts[Index].Poly[I]; Quad[1] := FEnts[Index].Poly[J];
    Quad[2] := Top[J];              Quad[3] := Top[I];
    { wound to look into the tunnel, whichever way the push went and the
      opening was drawn }
    FN := Cross3(Sub3(Quad[1], Quad[0]),
                 Sub3(Quad[3], Quad[0]));
    if Dot3(FN, Sub3(Mid, Quad[0])) < 0 then
    begin
      Quad[1] := FEnts[Index].Poly[I]; Quad[0] := FEnts[Index].Poly[J];
      Quad[3] := Top[J];              Quad[2] := Top[I];
    end;
    AddFaceRaw(Quad, Ink, True);
    FEnts[FLive - 1].Grp := G;
    AddLine(FEnts[Index].Poly[I], Top[I], LineInk, Wt, False);
    FEnts[FLive - 1].Grp := G;
    FEnts[FLive - 1].Soft := N >= 9;
    AddLine(Top[I], Top[J], LineInk, Wt, False);
    FEnts[FLive - 1].Grp := G;
  end;

  if not Pocket then
  begin
    { and the record of the tunnel, for the next one through this solid }
    AddBore(FEnts[Index].Poly, Top[0], G);
    FLastBore := FLive - 1;
  end;
  { and the pushed face is the hole now }
  Delete(Index);
  if not Pocket then Dec(FLastBore);
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
  Result := True;
end;

{ How far to the far side of the solid.  A drill must land exactly on the
  plane of the face it comes out of, or TunnelThrough finds no far face and
  builds a plug instead.  Nobody can drag to a millionth, so this works it
  out by the same rule TunnelThrough uses. }
function TWorkDoc.ThroughDistance(Face: Integer; Want: Double): Double;
var
  F, I, N, G: Integer;
  Nm, FN, Mid, Q: TP3;
  D, Best, Sgn, Size, Tol: Double;
  All: Boolean;
begin
  Result := Want;
  if (Face < 0) or (Face >= FLive) or (FEnts[Face].Kind <> ekFace) then Exit;
  N := Length(FEnts[Face].Poly);
  if (N < 3) or (Abs(Want) < 1E-9) then Exit;
  Nm := FaceNormal(Face);
  if Want < 0 then Sgn := -1 else Sgn := 1;

  { which solid - the face's own group, or the one whose wall it sits on }
  G := FEnts[Face].Grp;
  Mid := P3(0, 0, 0);
  for I := 0 to N - 1 do
    Mid := P3(Mid.X + FEnts[Face].Poly[I].X / N,
              Mid.Y + FEnts[Face].Poly[I].Y / N,
              Mid.Z + FEnts[Face].Poly[I].Z / N);
  if G = 0 then
    for F := 0 to FLive - 1 do
    begin
      if (F = Face) or (FEnts[F].Kind <> ekFace) or not FEnts[F].Solid or
         (FEnts[F].Grp = 0) or (Length(FEnts[F].Poly) < 3) then Continue;
      FN := FaceNormal(F);
      if Abs(Abs(Dot3(FN, Nm)) - 1) > 1E-6 then Continue;
      if Abs(Dot3(FN, Sub3(Mid, FEnts[F].Poly[0]))) > 1E-6 then Continue;
      if LoopContains(Mid, FEnts[F].Poly, FN) then
      begin
        G := FEnts[F].Grp;
        Break;
      end;
    end;
  if G = 0 then Exit;

  Size := 0;
  for I := 0 to N - 1 do
    Size := Max(Size, Dist(FEnts[Face].Poly[I], FEnts[Face].Poly[0]));
  Tol := 1E-6 * (1 + Size);

  Best := 0;
  for F := 0 to FLive - 1 do
  begin
    if (F = Face) or (FEnts[F].Kind <> ekFace) or (FEnts[F].Grp <> G) then Continue;
    if Length(FEnts[F].Poly) < 3 then Continue;
    FN := FaceNormal(F);
    if Abs(Abs(Dot3(FN, Nm)) - 1) > 1E-6 then Continue;
    { how far along the push this face's plane is - it has to be ahead of
      us, in the direction we are going }
    D := Dot3(Nm, Sub3(FEnts[F].Poly[0], FEnts[Face].Poly[0]));
    if D * Sgn <= Tol then Continue;
    { and big enough to take the whole opening, which TunnelThrough asks }
    All := True;
    for I := 0 to N - 1 do
    begin
      Q := P3(FEnts[Face].Poly[I].X + Nm.X * D, FEnts[Face].Poly[I].Y + Nm.Y * D,
              FEnts[Face].Poly[I].Z + Nm.Z * D);
      if not LoopContains(Q, FEnts[F].Poly, FN) then
      begin
        All := False;
        Break;
      end;
    end;
    if not All then Continue;
    Q := P3(Mid.X + Nm.X * D, Mid.Y + Nm.Y * D, Mid.Z + Nm.Z * D);
    if not LoopContains(Q, FEnts[F].Poly, FN) then Continue;
    { the nearest one wins - the first wall it comes out of }
    if (Best = 0) or (Abs(D) < Abs(Best)) then Best := D;
  end;
  if Best <> 0 then Result := Best;
end;

{ A face pushed back onto the one opposite presses its solid flat: two faces
  back to back, walls with no area, every edge twice.  When every other face
  of the solid is flat or in the moved face's plane, the extrusion goes and
  the pushed face stays loose with its paint, as in SketchUp.  Otherwise only
  the zero-area walls and doubled edges go. }
function TWorkDoc.FlattenedAway(Index: Integer): Boolean;
const
  TOL = 1E-6;
var
  Doomed: array of Boolean;
  I, J, K, G, Part_, NOther: Integer;
  Nm: TP3;
  D: Double;
  AllFlat, InPlane: Boolean;

  function SameP(const P, Q: TP3): Boolean;
  begin
    Result := (Abs(P.X - Q.X) < TOL) and (Abs(P.Y - Q.Y) < TOL) and
              (Abs(P.Z - Q.Z) < TOL);
  end;

begin
  Result := False;
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekFace) then Exit;
  G := FEnts[Index].Grp;
  if G = 0 then Exit;
  Part_ := FEnts[Index].Part;
  Nm := FaceNormal(Index);
  D := Dot3(Nm, FEnts[Index].Poly[0]);
  SetLength(Doomed, FLive);
  for I := 0 to FLive - 1 do Doomed[I] := False;

  { the faces: which have no area left, which lie under the moved one, and
    whether that is all of them }
  AllFlat := True;
  NOther := 0;
  for I := 0 to FLive - 1 do
    if (I <> Index) and (FEnts[I].Kind = ekFace) and (FEnts[I].Grp = G) and
       (FEnts[I].Part = Part_) then
    begin
      Inc(NOther);
      if FaceArea(I) < TOL * TOL then
        Doomed[I] := True
      else
      begin
        InPlane := True;
        for J := 0 to High(FEnts[I].Poly) do
          if Abs(Dot3(Nm, FEnts[I].Poly[J]) - D) > TOL then InPlane := False;
        if not InPlane then AllFlat := False;
      end;
    end;
  if NOther = 0 then Exit;
  { pressed flat: what lies in the moved face's plane is the cap that was
    under it, and it goes too }
  if AllFlat then
    for I := 0 to FLive - 1 do
      if (I <> Index) and (FEnts[I].Kind = ekFace) and (FEnts[I].Grp = G) and
         (FEnts[I].Part = Part_) then
        Doomed[I] := True;

  { the edges: one with no length was a wall's upright, and of two that lie
    on top of each other the later one is the ring that came down to meet
    the first }
  for I := 0 to FLive - 1 do
    if (FEnts[I].Kind = ekLine) and (FEnts[I].Grp = G) and
       (FEnts[I].Part = Part_) and not FEnts[I].Dim then
    begin
      if SameP(FEnts[I].A, FEnts[I].B) then
      begin
        Doomed[I] := True;
        Continue;
      end;
      for K := 0 to I - 1 do
        if (FEnts[K].Kind = ekLine) and (FEnts[K].Grp = G) and
           (FEnts[K].Part = Part_) and not Doomed[K] and
           ((SameP(FEnts[K].A, FEnts[I].A) and SameP(FEnts[K].B, FEnts[I].B)) or
            (SameP(FEnts[K].A, FEnts[I].B) and SameP(FEnts[K].B, FEnts[I].A))) then
        begin
          Doomed[I] := True;
          Break;
        end;
    end;

  K := 0;
  for I := 0 to FLive - 1 do
    if Doomed[I] then Inc(K);
  if K = 0 then Exit;

  { what is left of a solid pressed flat is loose drawing again }
  if AllFlat then
    for I := 0 to FLive - 1 do
      if (FEnts[I].Kind in [ekFace, ekLine, ekArc]) and (FEnts[I].Grp = G) and
         (FEnts[I].Part = Part_) and not Doomed[I] then
      begin
        FEnts[I].Grp := 0;
        if FEnts[I].Kind = ekFace then FEnts[I].Solid := False;
        if FEnts[I].Kind = ekLine then FEnts[I].Soft := False;
      end;
  DeleteMarked(Doomed);
  Result := AllFlat;
end;

function TWorkDoc.PushPull(Index: Integer; Dist: Double): Boolean;
var
  I, J, N, G: Integer;
  Nm: TP3;
  Base, Top, Rev: TP3Array;
  HBase, HTop, RevH: array of TP3Array;
  H, M: Integer;
  Quad: array[0..3] of TP3;
  Ink, LineInk: TColor;
  Wt: Single;
  Plug, Same: Boolean;
  Turn, Far_: Double;
begin
  Result := False;
  FLastBore := -1;
  if (Index < 0) or (Index >= FLive) or (FEnts[Index].Kind <> ekFace) then Exit;
  if Abs(Dist) < 1E-9 then Exit;

  N := Length(FEnts[Index].Poly);
  if N < 3 then Exit;
  Nm := FaceNormal(Index);
  Ink := FEnts[Index].Ink;
  LineInk := OutlineInk(Index, Ink);

  { The sides and top use the same pen as the outline they grew from. }
  Wt := EdgeWeight(FEnts[Index].Poly[0], FEnts[Index].Poly[1]);
  if Wt <= 0 then Wt := FEnts[Index].Weight;
  if Wt <= 0 then Wt := 1;

  { A face slides when it is the whole flat side of a solid; a patch, or a
    face whose walls are not square to it, has a block extruded instead. }
  LastFlattened := False;
  Plug := FEnts[Index].Solid and (IsPatch(Index) or not WallsSquareTo(Index));
  if FEnts[Index].Solid and not Plug then
  begin
    MoveFaceWith(Index, Mul3(Nm, Dist));
    LastFlattened := FlattenedAway(Index);
    Exit(True);
  end;

  { A plug pushed into its solid stops at the far wall; a push that reaches
    or passes it is taken to it and comes out a tunnel. }
  if Plug and (Dist < 0) then
  begin
    Far_ := ThroughDistance(Index, Dist);
    if (Far_ <> Dist) and (Abs(Far_) < Abs(Dist) + 1E-9) then Dist := Far_;
  end;

  SetLength(Base, N);
  SetLength(Top, N);
  for I := 0 to N - 1 do
  begin
    Base[I] := FEnts[Index].Poly[I];
    Top[I] := P3(Base[I].X + Nm.X * Dist,
                 Base[I].Y + Nm.Y * Dist,
                 Base[I].Z + Nm.Z * Dist);
  end;

  { Pushed clean through its own solid, the shape is a hole: the far face
    gets the opening, the walls line the tunnel and the pushed face goes, as
    in SketchUp. }
  if TunnelThrough(Index, Top, Nm, Dist) then Exit(True);

  { Holes travel with the face and get walls of their own, so pushing up an
    offset border makes a foundation wall, not a filled block. }
  SetLength(HBase, Length(FEnts[Index].Holes));
  SetLength(HTop, Length(FEnts[Index].Holes));
  for H := 0 to High(FEnts[Index].Holes) do
  begin
    M := Length(FEnts[Index].Holes[H]);
    SetLength(HBase[H], M);
    SetLength(HTop[H], M);
    { which way round the opening turns, seen along the face's normal - the
      outline turns positively by definition, so an opening should not }
    Turn := 0;
    for I := 0 to M - 1 do
      Turn := Turn + Dot3(Nm, Cross3(FEnts[Index].Holes[H][I],
        FEnts[Index].Holes[H][(I + 1) mod M]));
    Same := Turn > 0;
    for I := 0 to M - 1 do
    begin
      if Same then
        HBase[H][I] := FEnts[Index].Holes[H][M - 1 - I]
      else
        HBase[H][I] := FEnts[Index].Holes[H][I];
      HTop[H][I] := P3(HBase[H][I].X + Nm.X * Dist,
                       HBase[H][I].Y + Nm.Y * Dist,
                       HBase[H][I].Z + Nm.Z * Dist);
    end;
  end;

  { The picked face travels and a reversed copy stays behind as the base, so
    the result is closed.  One group id for everything this push makes, so a
    later push moves this solid and nothing that merely touches it. }
  if FEnts[Index].Grp = 0 then
  begin
    Inc(FNextGrp);
    FEnts[Index].Grp := FNextGrp;
  end;
  G := FEnts[Index].Grp;

  { The base edges belong to the solid now, or the region finder would find
    the base again as a loose face inside the box. }
  ClaimOutline(Index, G);

  SetLength(Rev, N);
  if Dist >= 0 then
  begin
    { traveling along the face's own normal: the moved face already faces
      out of the new solid, and the copy left behind is reversed }
    for I := 0 to N - 1 do FEnts[Index].Poly[I] := Top[I];
    for I := 0 to N - 1 do Rev[I] := Base[N - 1 - I];
  end
  else
  begin
    { traveling against it, so the two swap round }
    for I := 0 to N - 1 do FEnts[Index].Poly[I] := Top[N - 1 - I];
    for I := 0 to N - 1 do Rev[I] := Base[I];
  end;
  FEnts[Index].Solid := True;
  { the face that traveled takes its openings with it }
  for H := 0 to High(HTop) do
  begin
    M := Length(HTop[H]);
    SetLength(FEnts[Index].Holes[H], M);
    if Dist >= 0 then
      for I := 0 to M - 1 do FEnts[Index].Holes[H][I] := HTop[H][I]
    else
      for I := 0 to M - 1 do FEnts[Index].Holes[H][I] := HTop[H][M - 1 - I];
  end;

  { A plug - a face in a solid's surface, like a letter in its panel - has
    material under it already.  A cap there would use every edge round it
    three times and read as open, so only a face with air below gets one. }
  if not Plug then
  begin
    AddFaceRaw(Rev, Ink, True);
    { a push takes the pushed face's paint, as revolve and sweep do }
    if FEnts[Index].MatSet then SetMaterial(FLive - 1, FEnts[Index].Mat);
    FEnts[FLive - 1].Grp := G;
    { and so does the one left behind, wound to match its own outline }
    if Length(HBase) > 0 then
    begin
      SetLength(RevH, Length(HBase));
      for H := 0 to High(HBase) do
      begin
        M := Length(HBase[H]);
        SetLength(RevH[H], M);
        if Dist >= 0 then
          for I := 0 to M - 1 do RevH[H][I] := HBase[H][M - 1 - I]
        else
          for I := 0 to M - 1 do RevH[H][I] := HBase[H][I];
      end;
      SetFaceHoles(FLive - 1, RevH);
    end;
  end;

  { walls, plus the edges so it reads as a solid in wireframe too }
  for I := 0 to N - 1 do
  begin
    J := (I + 1) mod N;
    { the walls turn the same way round as the caps }
    if Dist >= 0 then
    begin
      Quad[0] := Base[I]; Quad[1] := Base[J];
      Quad[2] := Top[J];  Quad[3] := Top[I];
    end
    else
    begin
      Quad[0] := Base[J]; Quad[1] := Base[I];
      Quad[2] := Top[I];  Quad[3] := Top[J];
    end;
    AddFaceRaw(Quad, Ink, True);
    if FEnts[Index].MatSet then SetMaterial(FLive - 1, FEnts[Index].Mat);
    FEnts[FLive - 1].Grp := G;
    AddLine(Base[I], Top[I], LineInk, Wt, False);
    FEnts[FLive - 1].Grp := G;
    { Nine or more sides means the outline was a curve, so the creases down
      the extrusion are softened. }
    FEnts[FLive - 1].Soft := N >= 9;
    AddLine(Top[I], Top[J], LineInk, Wt, False);
    FEnts[FLive - 1].Grp := G;
  end;

  { The lining of each opening, wound the same way as the outside walls.  An
    opening is stored turning opposite to its outline, so walking it the same
    way already faces the lining into the hole.  HBase was turned round above
    if the opening was wound like the outline, so the top, the cap and the
    lining all agree. }
  for H := 0 to High(HBase) do
  begin
    M := Length(HBase[H]);
    for I := 0 to M - 1 do
    begin
      J := (I + 1) mod M;
      if Dist >= 0 then
      begin
        Quad[0] := HBase[H][I]; Quad[1] := HBase[H][J];
        Quad[2] := HTop[H][J];  Quad[3] := HTop[H][I];
      end
      else
      begin
        Quad[0] := HBase[H][J]; Quad[1] := HBase[H][I];
        Quad[2] := HTop[H][I];  Quad[3] := HTop[H][J];
      end;
      AddFaceRaw(Quad, Ink, True);
      if FEnts[Index].MatSet then SetMaterial(FLive - 1, FEnts[Index].Mat);
      FEnts[FLive - 1].Grp := G;
      AddLine(HBase[H][I], HTop[H][I], LineInk, Wt, False);
      FEnts[FLive - 1].Grp := G;
      FEnts[FLive - 1].Soft := M >= 9;
      AddLine(HTop[H][I], HTop[H][J], LineInk, Wt, False);
      FEnts[FLive - 1].Grp := G;
    end;
  end;

  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
  Result := True;
end;

function Lerp3(const A, B: TP3; T: Double): TP3;
begin
  Result := P3(A.X + (B.X - A.X) * T, A.Y + (B.Y - A.Y) * T,
               A.Z + (B.Z - A.Z) * T);
end;

{ Where a point sits along a segment, when strictly inside it.  A line drawn
  from the middle of another makes a T, not a cross, but still cuts it in
  two, and each half wants its own middle. }
function PointOnSeg(const P, A, B: TP3; out T: Double): Boolean;
var
  DX, DY, DZ, L2: Double;
  Q: TP3;
begin
  Result := False;
  T := 0;
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  DZ := B.Z - A.Z;
  L2 := DX * DX + DY * DY + DZ * DZ;
  if L2 < 1E-12 then Exit;
  T := ((P.X - A.X) * DX + (P.Y - A.Y) * DY + (P.Z - A.Z) * DZ) / L2;
  if (T <= 0.001) or (T >= 0.999) then Exit;
  Q := P3(A.X + DX * T, A.Y + DY * T, A.Z + DZ * T);
  Result := Dist(P, Q) <= Sqrt(L2) * 1E-6 + 1E-9;
end;

{ Where two segments come closest; a crossing only if the gap is negligible
  and the point is properly inside both. }
function SegCross(const A1, A2, B1, B2: TP3; out P: TP3;
  out TA, TB: Double): Boolean;
var
  UX, UY, UZ, VX, VY, VZ, WX, WY, WZ: Double;
  A, B, C, D, E, Den, Scale: Double;
  PA, PB: TP3;
begin
  Result := False;
  TA := 0;
  TB := 0;
  P := A1;

  UX := A2.X - A1.X; UY := A2.Y - A1.Y; UZ := A2.Z - A1.Z;
  VX := B2.X - B1.X; VY := B2.Y - B1.Y; VZ := B2.Z - B1.Z;
  WX := A1.X - B1.X; WY := A1.Y - B1.Y; WZ := A1.Z - B1.Z;

  A := UX * UX + UY * UY + UZ * UZ;
  B := UX * VX + UY * VY + UZ * VZ;
  C := VX * VX + VY * VY + VZ * VZ;
  D := UX * WX + UY * WY + UZ * WZ;
  E := VX * VX * 0 + VX * WX + VY * WY + VZ * WZ;

  Den := A * C - B * B;
  if (Den < 1E-12) or (A < 1E-12) or (C < 1E-12) then Exit;   // parallel

  TA := (B * E - C * D) / Den;
  TB := (A * E - B * D) / Den;
  { strictly inside, so touching endpoints do not count - those are already
    endpoint snaps }
  if (TA <= 0.001) or (TA >= 0.999) or (TB <= 0.001) or (TB >= 0.999) then Exit;

  PA := P3(A1.X + UX * TA, A1.Y + UY * TA, A1.Z + UZ * TA);
  PB := P3(B1.X + VX * TB, B1.Y + VY * TB, B1.Z + VZ * TB);
  Scale := Sqrt(A) + Sqrt(C);
  if Dist(PA, PB) > Scale * 1E-6 + 1E-9 then Exit;            // skew, not crossing

  P := PA;
  Result := True;
end;

{ Rebuilt only when the document changes, because it is quadratic in the
  number of lines and the cursor asks for it on every mouse move. }
procedure TWorkDoc.RebuildSnapCache;
const
  MAX_LINES = 500;
var
  GLo, GHi: array of TP3;
  BLo, BHi, GDir: TP3;
  Reach: Double;
  I, J, N, LineCount, NGuide: Integer;
  P: TP3;
  TA, TB: Double;
  Cuts: array of array of Double;
  Idx, GIdx: array of Integer;
  Tmp: Double;
  K, M, H: Integer;
  MidKind: TSnapKind;
  Seen: TFPHashList;
  Key: string;

  procedure Put(const Q: TP3; Kind: TSnapKind);
  begin
    { A point outside the slice is not in the drawing.  Tested per point, not
      per entity: a wall from floor to roof is in a ground-floor plan, but its
      top corner is not. }
    if FSliceOn and ((Q.Z < FSliceLo - 1E-7) or (Q.Z > FSliceHi + 1E-7)) then
      Exit;
    if N >= Length(FSnapCache) then SetLength(FSnapCache, Max(32, N * 2));
    FSnapCache[N].P := Q;
    FSnapCache[N].Kind := Kind;
    Inc(N);
  end;

  { Note that something crosses line Which at parameter T, once. }
  procedure AddCut(Which: Integer; T: Double);
  var
    Q: Integer;
  begin
    for Q := 0 to High(Cuts[Which]) do
      if Abs(Cuts[Which][Q] - T) < 1E-9 then Exit;
    SetLength(Cuts[Which], Length(Cuts[Which]) + 1);
    Cuts[Which][High(Cuts[Which])] := T;
  end;

begin
  N := 0;
  SetLength(FSnapCache, 128);
  FSnapScreenOK := False;

  { The origin is always there, and competes by the same rules as any other
    definite point. }
  Put(P3(0, 0, 0), snOrigin);

  for I := 0 to FLive - 1 do
    if not EntHidden(I) then
    case FEnts[I].Kind of
      ekLine:
        begin
          Put(FEnts[I].A, snEndpoint);
          Put(FEnts[I].B, snEndpoint);
        end;
      ekArc:
        begin
          Put(FEnts[I].A, snEndpoint);
          Put(FEnts[I].B, snEndpoint);
          Put(FEnts[I].C, snCenter);
        end;
      { The middle of a face, for drawing a circle from the center of a
        square.  One per face, so it is not noise. }
      ekFace:
        if Length(FEnts[I].Poly) >= 3 then
        begin
          P := P3(0, 0, 0);
          for K := 0 to High(FEnts[I].Poly) do
          begin
            P.X := P.X + FEnts[I].Poly[K].X;
            P.Y := P.Y + FEnts[I].Poly[K].Y;
            P.Z := P.Z + FEnts[I].Poly[K].Z;
          end;
          K := Length(FEnts[I].Poly);
          Put(P3(P.X / K, P.Y / K, P.Z / K), snCenter);
        end;

      { a guide point is meant to be aimed at - unless guides are hidden }
      ekGuide:
        if (not FGuidesHidden) and (Dist(FEnts[I].A, FEnts[I].B) < 1E-9) then
          Put(FEnts[I].A, snEndpoint);

      { annotation is never snapped to; it is only in the way }
      ekDim, ekText: ;
    end;

  { The corners of a face, where no line already put one.  A face from a
    revolve, an import or a generator has no lines, and would otherwise offer
    nothing to land on.  Deduplicated, since most faces do have their lines
    and BestSnap walks this list on every mouse move. }
  Seen := TFPHashList.Create;
  try
    for I := 0 to N - 1 do
    begin
      Key := PointKeyOf(FSnapCache[I].P);
      if Seen.Find(Key) = nil then Seen.Add(Key, Pointer(1));
    end;
    for I := 0 to FLive - 1 do
      if (FEnts[I].Kind = ekFace) and not EntHidden(I) then
      begin
        for K := 0 to High(FEnts[I].Poly) do
        begin
          Key := PointKeyOf(FEnts[I].Poly[K]);
          if Seen.Find(Key) <> nil then Continue;
          Seen.Add(Key, Pointer(1));
          Put(FEnts[I].Poly[K], snEndpoint);
        end;
        for H := 0 to High(FEnts[I].Holes) do
          for K := 0 to High(FEnts[I].Holes[H]) do
          begin
            Key := PointKeyOf(FEnts[I].Holes[H][K]);
            if Seen.Find(Key) <> nil then Continue;
            Seen.Add(Key, Pointer(1));
            Put(FEnts[I].Holes[H][K], snEndpoint);
          end;
      end;
  finally
    Seen.Free;
  end;

  { every line gets a list of the parameters where something crosses it }
  SetLength(Idx, FLive);
  LineCount := 0;
  for I := 0 to FLive - 1 do
    if (FEnts[I].Kind = ekLine) and not EntHidden(I) then
    begin
      Idx[LineCount] := I;
      Inc(LineCount);
    end;

  SetLength(Cuts, LineCount);
  if LineCount <= MAX_LINES then
    for I := 0 to LineCount - 2 do
      for J := I + 1 to LineCount - 1 do
        if SegCross(FEnts[Idx[I]].A, FEnts[Idx[I]].B,
                    FEnts[Idx[J]].A, FEnts[Idx[J]].B, P, TA, TB) then
        begin
          Put(P, snCross);
          AddCut(I, TA);
          AddCut(J, TB);
        end
        else
        begin
          { A T-junction cuts too, so each half of a divided side gets its
            own middle to aim at. }
          if PointOnSeg(FEnts[Idx[J]].A, FEnts[Idx[I]].A, FEnts[Idx[I]].B, TA) then
            AddCut(I, TA);
          if PointOnSeg(FEnts[Idx[J]].B, FEnts[Idx[I]].A, FEnts[Idx[I]].B, TA) then
            AddCut(I, TA);
          if PointOnSeg(FEnts[Idx[I]].A, FEnts[Idx[J]].A, FEnts[Idx[J]].B, TB) then
            AddCut(J, TB);
          if PointOnSeg(FEnts[Idx[I]].B, FEnts[Idx[J]].A, FEnts[Idx[J]].B, TB) then
            AddCut(J, TB);
        end;

  { Where a guide crosses something - the point the guide was laid to create.
    Crossings only, no cuts: a guide does not divide the edge it crosses.  A
    guide's own ends are left out; a guide point is already in above. }
  SetLength(GIdx, FLive);
  NGuide := 0;
  if not FGuidesHidden then
    for I := 0 to FLive - 1 do
      if (FEnts[I].Kind = ekGuide) and
         (Dist(FEnts[I].A, FEnts[I].B) > 1E-9) then
      begin
        GIdx[NGuide] := I;
        Inc(NGuide);
      end;
  { A guide is stored as a short stub but stands for an infinite line, so
    run each one out past the whole drawing both ways first. }
  if (NGuide > 0) and (LineCount + NGuide <= MAX_LINES) then
  begin
    SetLength(GLo, NGuide);
    SetLength(GHi, NGuide);
    if not Bounds(BLo, BHi) then
    begin
      BLo := P3(0, 0, 0);
      BHi := P3(0, 0, 0);
    end;
    Reach := Dist(BLo, BHi) + 1;
    for I := 0 to NGuide - 1 do
    begin
      GDir := Norm3(Sub3(FEnts[GIdx[I]].B, FEnts[GIdx[I]].A));
      GLo[I] := P3(FEnts[GIdx[I]].A.X - GDir.X * Reach,
                   FEnts[GIdx[I]].A.Y - GDir.Y * Reach,
                   FEnts[GIdx[I]].A.Z - GDir.Z * Reach);
      GHi[I] := P3(FEnts[GIdx[I]].A.X + GDir.X * Reach,
                   FEnts[GIdx[I]].A.Y + GDir.Y * Reach,
                   FEnts[GIdx[I]].A.Z + GDir.Z * Reach);
    end;
    for I := 0 to NGuide - 1 do
    begin
      for J := 0 to LineCount - 1 do
        if SegCross(GLo[I], GHi[I],
                    FEnts[Idx[J]].A, FEnts[Idx[J]].B, P, TA, TB) then
          Put(P, snCross);
      for J := I + 1 to NGuide - 1 do
        if SegCross(GLo[I], GHi[I], GLo[J], GHi[J], P, TA, TB) then
          Put(P, snCross);
    end;
  end;

  { a crossed line is really several sub-segments, so give each of them a
    midpoint of its own }
  for I := 0 to LineCount - 1 do
  begin
    SetLength(Cuts[I], Length(Cuts[I]) + 2);
    Cuts[I][High(Cuts[I]) - 1] := 0;
    Cuts[I][High(Cuts[I])] := 1;
    for K := 1 to High(Cuts[I]) do
    begin
      Tmp := Cuts[I][K];
      M := K - 1;
      while (M >= 0) and (Cuts[I][M] > Tmp) do
      begin
        Cuts[I][M + 1] := Cuts[I][M];
        Dec(M);
      end;
      Cuts[I][M + 1] := Tmp;
    end;
    { an uncrossed line has one piece, and its middle is the real midpoint;
      anything else is a piece of a line and ranks well below it }
    if Length(Cuts[I]) > 2 then MidKind := snSubMid else MidKind := snMidpoint;
    for K := 0 to High(Cuts[I]) - 1 do
    begin
      Tmp := (Cuts[I][K] + Cuts[I][K + 1]) / 2;
      if Cuts[I][K + 1] - Cuts[I][K] < 1E-6 then Continue;
      Put(P3(FEnts[Idx[I]].A.X + (FEnts[Idx[I]].B.X - FEnts[Idx[I]].A.X) * Tmp,
             FEnts[Idx[I]].A.Y + (FEnts[Idx[I]].B.Y - FEnts[Idx[I]].A.Y) * Tmp,
             FEnts[Idx[I]].A.Z + (FEnts[Idx[I]].B.Z - FEnts[Idx[I]].A.Z) * Tmp),
          MidKind);
    end;
  end;

  { Circles and arcs: quadrant points to start the next circle from,
    crossings between arcs with middles for the pieces, and the middle of an
    uncrossed open arc. }
  ArcSnaps(N);
  CrateSnaps(N);
  SetLength(FSnapCache, N);
  FSnapDirty := False;
end;

{ A group's crate - the box round it - as snap points: eight corners, edge
  middles, side centers and the center, like SketchUp's inference grips.
  Only groups sitting directly in the open context. }
procedure TWorkDoc.CrateSnaps(var N: Integer);
var
  I: Integer;
  Lo, Hi, C: TP3;
  X: array[0..2] of Double;
  Y: array[0..2] of Double;
  Z: array[0..2] of Double;
  IX, IY, IZ, NX, NY, NZ, Odd: Integer;

  procedure Put(const Q: TP3; Kind: TSnapKind);
  begin
    if FSliceOn and ((Q.Z < FSliceLo - 1E-7) or (Q.Z > FSliceHi + 1E-7)) then
      Exit;
    if N >= Length(FSnapCache) then SetLength(FSnapCache, Max(32, N * 2));
    FSnapCache[N].P := Q;
    FSnapCache[N].Kind := Kind;
    Inc(N);
  end;

begin
  for I := 0 to FLive - 1 do
  begin
    if FEnts[I].Kind <> ekPart then Continue;
    if FEnts[I].Part <> FContext then Continue;
    if EntHidden(I) then Continue;
    if not PartBounds(FEnts[I].Grp, Lo, Hi) then Continue;
    X[0] := Lo.X; X[1] := (Lo.X + Hi.X) / 2; X[2] := Hi.X;
    Y[0] := Lo.Y; Y[1] := (Lo.Y + Hi.Y) / 2; Y[2] := Hi.Y;
    Z[0] := Lo.Z; Z[1] := (Lo.Z + Hi.Z) / 2; Z[2] := Hi.Z;
    { an axis the box has no extent along - a flat group - has one
      coordinate, not three: walked once, and its middle is not a middle }
    NX := 2; NY := 2; NZ := 2;
    if Hi.X - Lo.X < 1E-7 then NX := 0;
    if Hi.Y - Lo.Y < 1E-7 then NY := 0;
    if Hi.Z - Lo.Z < 1E-7 then NZ := 0;
    { the 27 lattice points of the box: how many middle coordinates a point
      has says what it is - none is a corner, one an edge's middle, two a
      side's center, three the center }
    for IX := 0 to NX do
      for IY := 0 to NY do
        for IZ := 0 to NZ do
        begin
          Odd := Ord(IX = 1) + Ord(IY = 1) + Ord(IZ = 1);
          C := P3(X[IX], Y[IY], Z[IZ]);
          case Odd of
            0: Put(C, snEndpoint);
            1: Put(C, snMidpoint);
          else
            Put(C, snCenter);
          end;
        end;
  end;
end;

{ An arc's own snap points: quadrants, crossings with other arcs, and the
  middles of the pieces those leave.  Angles run from A0 along the sweep, so
  either direction reads the same. }
procedure TWorkDoc.ArcSnaps(var N: Integer);
const
  MAX_ARCS = 300;
var
  I, J, K, Q, G, ArcCount: Integer;
  Idx: array of Integer;
  Cuts: array of array of Double;
  AU, AV, Nm, P, U, Wv, GDir: TP3;
  Ang, Tmp: Double;

  procedure Put(const Pt: TP3; Kind: TSnapKind);
  begin
    if N >= Length(FSnapCache) then SetLength(FSnapCache, Max(32, N * 2));
    FSnapCache[N].P := Pt;
    FSnapCache[N].Kind := Kind;
    Inc(N);
  end;

  procedure Axes(const E: TWorkEnt; out U, V, Nrm: TP3);
  begin
    if E.Plane = plFree then
    begin
      Nrm := Norm3(E.Nm);
      AxesFromNormal(Nrm, U, V);
    end
    else
    begin
      PlaneAxes(E.Plane, U, V);
      Nrm := Norm3(Cross3(U, V));
    end;
  end;

  { the point at absolute angle A on the arc's circle }
  function At(const E: TWorkEnt; A: Double): TP3;
  begin
    if E.Plane = plFree then Result := ArcPoint(E.C, E.R, A, E.Plane, E.Nm)
    else Result := ArcPoint(E.C, E.R, A, E.Plane);
  end;

  { how far along the arc, from A0 in the direction of the sweep, an
    absolute angle sits: 0 .. 2pi }
  function Along(const E: TWorkEnt; A: Double): Double;
  begin
    if E.Sweep >= 0 then Result := A - E.A0 else Result := E.A0 - A;
    Result := Result - 2 * Pi * Floor(Result / (2 * Pi));
  end;

  function OnArc(const E: TWorkEnt; A: Double): Boolean;
  var
    L: Double;
  begin
    if Abs(E.Sweep) >= 2 * Pi - 1E-9 then Exit(True);
    L := Along(E, A);
    Result := (L <= Abs(E.Sweep) + 1E-7) or (L >= 2 * Pi - 1E-7);
  end;

  { the absolute angle of a point on (or near) the arc's circle }
  function AngleOf(const E: TWorkEnt; const Pt: TP3): Double;
  var
    U, V, Nrm, D: TP3;
  begin
    Axes(E, U, V, Nrm);
    D := Sub3(Pt, E.C);
    Result := ArcTan2(Dot3(D, V), Dot3(D, U));
  end;

  procedure AddCut(Which: Integer; Rel: Double);
  var
    M: Integer;
  begin
    for M := 0 to High(Cuts[Which]) do
      if Abs(Cuts[Which][M] - Rel) < 1E-7 then Exit;
    SetLength(Cuts[Which], Length(Cuts[Which]) + 1);
    Cuts[Which][High(Cuts[Which])] := Rel;
  end;

  { a point that is on both arcs is a crossing: noted once, cut into both }
  procedure Crossing(const Pt: TP3; AI, AJ: Integer);
  var
    A1, A2: Double;
  begin
    A1 := AngleOf(FEnts[Idx[AI]], Pt);
    A2 := AngleOf(FEnts[Idx[AJ]], Pt);
    if not (OnArc(FEnts[Idx[AI]], A1) and OnArc(FEnts[Idx[AJ]], A2)) then Exit;
    Put(Pt, snCross);
    AddCut(AI, Along(FEnts[Idx[AI]], A1));
    AddCut(AJ, Along(FEnts[Idx[AJ]], A2));
  end;

  { where the circle of arc J meets the plane of arc I: solve for the angles
    on J where the point lies in I's plane, then keep those on I's circle }
  procedure CrossPlane(AI, AJ: Integer);
  var
    UI, VI, NI, UJ, VJ, NJ, Pt: TP3;
    A, B, Cc, Rr, Phi, Th: Double;
    S: Integer;
  begin
    Axes(FEnts[Idx[AI]], UI, VI, NI);
    Axes(FEnts[Idx[AJ]], UJ, VJ, NJ);
    A := FEnts[Idx[AJ]].R * Dot3(NI, UJ);
    B := FEnts[Idx[AJ]].R * Dot3(NI, VJ);
    Cc := Dot3(NI, Sub3(FEnts[Idx[AI]].C, FEnts[Idx[AJ]].C));
    Rr := Sqrt(A * A + B * B);
    if (Rr < 1E-12) or (Abs(Cc) > Rr) then Exit;
    Phi := ArcTan2(B, A);
    for S := -1 to 1 do
    begin
      if S = 0 then Continue;
      Th := Phi + S * ArcCos(EnsureRange(Cc / Rr, -1.0, 1.0));
      Pt := At(FEnts[Idx[AJ]], Th);
      if Abs(Dist(Pt, FEnts[Idx[AI]].C) - FEnts[Idx[AI]].R) > 1E-6 then Continue;
      Crossing(Pt, AI, AJ);
    end;
  end;

  { two arcs in one plane: the two points where their circles meet }
  procedure CrossCoplanar(AI, AJ: Integer);
  var
    UI, VI, NI, Pt: TP3;
    D, A, H, RI, RJ: Double;
    S: Integer;
  begin
    Axes(FEnts[Idx[AI]], UI, VI, NI);
    RI := FEnts[Idx[AI]].R; RJ := FEnts[Idx[AJ]].R;
    D := Dist(FEnts[Idx[AI]].C, FEnts[Idx[AJ]].C);
    if (D < 1E-9) or (D > RI + RJ + 1E-9) or (D < Abs(RI - RJ) - 1E-9) then Exit;
    U := Norm3(Sub3(FEnts[Idx[AJ]].C, FEnts[Idx[AI]].C));
    Wv := Norm3(Cross3(NI, U));
    A := (RI * RI - RJ * RJ + D * D) / (2 * D);
    H := Sqrt(Max(0, RI * RI - A * A));
    for S := -1 to 1 do
    begin
      if (S = 0) and (H > 1E-9) then Continue;
      if (S <> 0) and (H <= 1E-9) then Continue;
      Pt := P3(FEnts[Idx[AI]].C.X + U.X * A + Wv.X * H * S,
               FEnts[Idx[AI]].C.Y + U.Y * A + Wv.Y * H * S,
               FEnts[Idx[AI]].C.Z + U.Z * A + Wv.Z * H * S);
      Crossing(Pt, AI, AJ);
    end;
  end;

  { an infinite line through LA along LD, against arc AI }
  procedure GuideMeetsArc(const LA, LD: TP3; AI: Integer);
  var
    U, V, Nrm, W, Pt: TP3;
    E: TWorkEnt;
    Dn, Off, Bq, Cq, Disc, T, Tol: Double;
    S: Integer;

    procedure Offer(const Q: TP3);
    begin
      if OnArc(E, AngleOf(E, Q)) then Put(Q, snCross);
    end;

  begin
    E := FEnts[Idx[AI]];
    Axes(E, U, V, Nrm);
    Tol := 1E-6 * (1 + E.R);
    W := Sub3(LA, E.C);
    Dn := Dot3(LD, Nrm);
    Off := Dot3(W, Nrm);
    if Abs(Dn) < 1E-9 then
    begin
      { along the arc's plane: in it, or nowhere }
      if Abs(Off) > Tol then Exit;
      Bq := Dot3(W, LD);
      Cq := Dot3(W, W) - E.R * E.R;
      Disc := Bq * Bq - Cq;
      if Disc < -Tol then Exit;
      Disc := Sqrt(Max(0, Disc));
      for S := -1 to 1 do
      begin
        if S = 0 then Continue;
        if (S = 1) and (Disc < 1E-12) then Continue;   { a tangent, once }
        T := -Bq + S * Disc;
        Offer(P3(LA.X + LD.X * T, LA.Y + LD.Y * T, LA.Z + LD.Z * T));
      end;
    end
    else
    begin
      { through the plane at one point, which has to be on the circle }
      T := -Off / Dn;
      Pt := P3(LA.X + LD.X * T, LA.Y + LD.Y * T, LA.Z + LD.Z * T);
      if Abs(Dist(Pt, E.C) - E.R) <= Tol then Offer(Pt);
    end;
  end;

  function Coplanar(AI, AJ: Integer): Boolean;
  var
    UI, VI, NI, UJ, VJ, NJ: TP3;
  begin
    Axes(FEnts[Idx[AI]], UI, VI, NI);
    Axes(FEnts[Idx[AJ]], UJ, VJ, NJ);
    Result := (Abs(Abs(Dot3(NI, NJ)) - 1) < 1E-9) and
      (Abs(Dot3(NI, Sub3(FEnts[Idx[AJ]].C, FEnts[Idx[AI]].C))) < 1E-9);
  end;

begin
  SetLength(Idx, FLive);
  ArcCount := 0;
  for I := 0 to FLive - 1 do
    if (FEnts[I].Kind = ekArc) and (FEnts[I].R > 1E-9) and not EntHidden(I) then
    begin
      Idx[ArcCount] := I;
      Inc(ArcCount);
    end;
  if ArcCount = 0 then Exit;
  SetLength(Cuts, ArcCount);
  { the quadrant points }
  for I := 0 to ArcCount - 1 do
    for Q := 0 to 3 do
    begin
      Ang := Q * Pi / 2;
      if OnArc(FEnts[Idx[I]], Ang) then Put(At(FEnts[Idx[I]], Ang), snQuadrant);
    end;
  { the crossings }
  if ArcCount <= MAX_ARCS then
    for I := 0 to ArcCount - 2 do
      for J := I + 1 to ArcCount - 1 do
        if Coplanar(I, J) then CrossCoplanar(I, J)
        else
        begin
          CrossPlane(I, J);
          CrossPlane(J, I);
        end;
  { Where a guide crosses an arc, say a rounded corner.  A guide offers the
    point but does not cut the arc. }
  if (not FGuidesHidden) and (ArcCount <= MAX_ARCS) then
    for G := 0 to FLive - 1 do
    begin
      if (FEnts[G].Kind <> ekGuide) or
         (Dist(FEnts[G].A, FEnts[G].B) < 1E-9) then Continue;
      GDir := Norm3(Sub3(FEnts[G].B, FEnts[G].A));
      for I := 0 to ArcCount - 1 do
        GuideMeetsArc(FEnts[G].A, GDir, I);
    end;

  { the middles of the pieces }
  for I := 0 to ArcCount - 1 do
  begin
    if Length(Cuts[I]) = 0 then
    begin
      { an open arc nothing crosses still has a middle; a whole circle does
        not have one anywhere in particular }
      if Abs(FEnts[Idx[I]].Sweep) < 2 * Pi - 1E-9 then
        Put(At(FEnts[Idx[I]], FEnts[Idx[I]].A0 + FEnts[Idx[I]].Sweep / 2), snMidpoint);
      Continue;
    end;
    { the ends are cuts too, unless it is a whole circle, where the pieces
      run round from the last cut to the first }
    if Abs(FEnts[Idx[I]].Sweep) < 2 * Pi - 1E-9 then
    begin
      AddCut(I, 0);
      AddCut(I, Abs(FEnts[Idx[I]].Sweep));
    end;
    for K := 0 to High(Cuts[I]) - 1 do
      for Q := 0 to High(Cuts[I]) - 1 - K do
        if Cuts[I][Q] > Cuts[I][Q + 1] then
        begin
          Tmp := Cuts[I][Q]; Cuts[I][Q] := Cuts[I][Q + 1]; Cuts[I][Q + 1] := Tmp;
        end;
    for K := 0 to High(Cuts[I]) do
    begin
      if K < High(Cuts[I]) then Tmp := (Cuts[I][K] + Cuts[I][K + 1]) / 2
      else if Abs(FEnts[Idx[I]].Sweep) >= 2 * Pi - 1E-9 then
        Tmp := (Cuts[I][K] + Cuts[I][0] + 2 * Pi) / 2
      else
        Continue;
      if Tmp >= 2 * Pi then Tmp := Tmp - 2 * Pi;
      if FEnts[Idx[I]].Sweep >= 0 then Ang := FEnts[Idx[I]].A0 + Tmp
      else Ang := FEnts[Idx[I]].A0 - Tmp;
      Put(At(FEnts[Idx[I]], Ang), snSubMid);
    end;
  end;
end;

{ Every live document, so that a surface being freed can find the ones that
  borrowed it.  There are never more than a handful - one per sheet. }
var
  GDocs: array of TWorkDoc;

procedure NoteDoc(D: TWorkDoc);
begin
  SetLength(GDocs, Length(GDocs) + 1);
  GDocs[High(GDocs)] := D;
end;

procedure ForgetDoc(D: TWorkDoc);
var
  I, J: Integer;
begin
  for I := 0 to High(GDocs) do
    if GDocs[I] = D then
    begin
      for J := I to High(GDocs) - 1 do GDocs[J] := GDocs[J + 1];
      SetLength(GDocs, Length(GDocs) - 1);
      Exit;
    end;
end;

{ A surface is going: any document still holding it as LastSurf must let
  go, or the next "is this hidden" reads freed memory.  Done here rather than
  in each exporter that makes its own surface. }
procedure SurfaceGone(S: TArtSurface);
var
  I: Integer;
begin
  for I := 0 to High(GDocs) do
    if GDocs[I].LastSurf = S then
    begin
      GDocs[I].LastSurf := nil;
      GDocs[I].LastSurfDied := True;
    end;
end;

constructor TWorkDoc.Create;
begin
  inherited Create;
  Threads := DefaultThreads;
  { a quick frame keeps the lines-on-faces pass at full quality: +3 ms on
    712 faces, and coarser let lines bleed through face edges while orbiting }
  QuickSteps := LINE_STEPS;
  QuickBisect := 6;
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
  NoteDoc(Self);
end;

destructor TWorkDoc.Destroy;
begin
  ForgetDoc(Self);
  { a worker still running would queue a call into a freed object }
  if FOnFaceWorker <> nil then
  begin
    FOnFaceWorker.WaitFor;
    TThread.RemoveQueuedEvents(FOnFaceWorker);
    FOnFaceWorker.Free;
    FOnFaceWorker := nil;
  end;
  inherited Destroy;
end;

procedure TWorkDoc.SnapPoints(out Pts: TP3Array);
var
  I: Integer;
begin
  if FSnapDirty then RebuildSnapCache;
  SetLength(Pts, Length(FSnapCache));
  for I := 0 to High(FSnapCache) do
    Pts[I] := FSnapCache[I].P;
end;

function TWorkDoc.Outline(const V: TProjector; I: Integer): TPointFArray;
var
  K, Steps: Integer;
  Ang: Double;
  DG: TDimGeom;
begin
  Result := nil;
  if (I < 0) or (I >= FLive) then Exit;
  case FEnts[I].Kind of
    ekArc:
      begin
        Steps := ArcSteps(FEnts[I]);
        SetLength(Result, Steps + 1);
        for K := 0 to Steps do
        begin
          Ang := FEnts[I].A0 + FEnts[I].Sweep * K / Steps;
          Result[K] := Project(V, ArcPoint(FEnts[I].C, FEnts[I].R, Ang, FEnts[I].Plane, FEnts[I].Nm));
        end;
      end;
    ekFace:
      begin
        SetLength(Result, Length(FEnts[I].Poly) + 1);
        for K := 0 to High(FEnts[I].Poly) do
          Result[K] := Project(V, FEnts[I].Poly[K]);
        if Length(FEnts[I].Poly) > 0 then
          Result[High(Result)] := Result[0];
      end;
    ekBore: ;
    ekGuide:
      begin
        SetLength(Result, 2);
        if Dist(FEnts[I].A, FEnts[I].B) < 1E-9 then
        begin
          Result[0] := Project(V, FEnts[I].A);
          Result[1] := Result[0];
        end
        else
        begin
          DG.A := Project(V, FEnts[I].A);
          Result[0] := DG.A;
          Result[1] := Project(V, FEnts[I].B);
        end;
      end;
    ekDim:
      begin
        { the drawn line and its two witness lines, so highlighting a
          dimension marks where it actually is }
        if not DimGeometry(V, FEnts[I].A, FEnts[I].B, FEnts[I].C,
             usImperial, DG, FEnts[I].Txt) then Exit;
        SetLength(Result, 6);
        Result[0] := DG.A;   Result[1] := DG.W1;
        Result[2] := DG.LA;  Result[3] := DG.LB;
        Result[4] := DG.W2;  Result[5] := DG.B;
      end;
    ekText:
      begin
        SetLength(Result, 1);
        Result[0] := Project(V, FEnts[I].A);
      end;
  else
    begin
      SetLength(Result, 2);
      Result[0] := Project(V, FEnts[I].A);
      Result[1] := Project(V, FEnts[I].B);
    end;
  end;
end;

{ How far the cursor is from an arc as drawn - its chords, not the circle.
  The bounding circle is checked first (a projected point is never further
  from the center than R * Ppu), which drops every circle but the one pointed
  at before any chords are walked. }
function ArcNearestAt(const PC: TProjCache; const E: TWorkEnt;
  SX, SY: Double; out P: TP3; TolPx: Double = 1E30): Double;
var
  STEPS: Integer;
  K: Integer;
  Ang, RPx, D: Double;
  PA, PB, PCen: TPointF;
  A3, B3: TP3;
begin
  Result := 1E30;
  P := E.C;
  PCen := ProjectAt(PC, E.C);
  RPx := E.R * PC.Ppu;
  if (Abs(SX - PCen.X) > RPx + TolPx) or (Abs(SY - PCen.Y) > RPx + TolPx) then
    Exit;
  STEPS := ArcSteps(E);
  A3 := ArcPoint(E.C, E.R, E.A0, E.Plane, E.Nm);
  PA := ProjectAt(PC, A3);
  for K := 1 to STEPS do
  begin
    Ang := E.A0 + E.Sweep * K / STEPS;
    B3 := ArcPoint(E.C, E.R, Ang, E.Plane, E.Nm);
    PB := ProjectAt(PC, B3);
    D := DistToSeg(SX, SY, PA.X, PA.Y, PB.X, PB.Y);
    if D < Result then
    begin
      Result := D;
      P := Lerp3(A3, B3, SegParam(SX, SY, PA.X, PA.Y, PB.X, PB.Y));
    end;
    PA := PB;
    A3 := B3;
  end;
end;

function ArcScreenDistAt(const PC: TProjCache; const E: TWorkEnt;
  SX, SY: Double; TolPx: Double = 1E30): Double;
var
  Ignored: TP3;
begin
  Result := ArcNearestAt(PC, E, SX, SY, Ignored, TolPx);
end;

function AxisSnap(const V: TProjector; SX, SY, TolPx: Double;
  out P: TP3; out Axis: Integer): Boolean;
var
  K: Integer;
  O, U: TPointF;
  D, T, Len, Best: Double;
  Dir, Q: TP3;
begin
  Result := False;
  Axis := -1;
  P := P3(0, 0, 0);
  O := Project(V, P3(0, 0, 0));
  if IsNan(O.X) or IsNan(O.Y) or IsInfinite(O.X) or IsInfinite(O.Y) then Exit;
  Best := TolPx;

  for K := 0 to 2 do
  begin
    case K of
      0: Dir := P3(1, 0, 0);
      1: Dir := P3(0, 1, 0);
    else Dir := P3(0, 0, 1);
    end;
    U := Project(V, Dir);
    U := PtF(U.X - O.X, U.Y - O.Y);
    Len := Sqrt(U.X * U.X + U.Y * U.Y);
    { An axis pointing at the camera is a dot on screen with no one point
      under the cursor, so it is not offered. }
    if Len < 1E-6 then Continue;

    { how far along it the cursor is, and how far off it - the projection is
      parallel, so one world unit is Len pixels wherever you are on the line }
    T := ((SX - O.X) * U.X + (SY - O.Y) * U.Y) / (Len * Len);
    D := Abs((SX - O.X) * U.Y - (SY - O.Y) * U.X) / Len;
    if D >= Best then Continue;

    Q := Mul3(Dir, T);
    Best := D;
    Axis := K;
    P := Q;
    Result := True;
  end;
end;

function TWorkDoc.SnapCacheCount: Integer;
begin
  if FSnapDirty then RebuildSnapCache;
  Result := Length(FSnapCache);
end;

function TWorkDoc.EdgeSnap(const V: TProjector; SX, SY, TolPx: Double;
  out P: TP3; out Ent: Integer): Boolean;
var
  A, B: TP3;
begin
  Result := EdgeUnder(V, SX, SY, TolPx, P, A, B, Ent);
end;

function TWorkDoc.EdgeUnder(const V: TProjector; SX, SY, TolPx: Double;
  out P, A, B: TP3; out Ent: Integer): Boolean;
const
  { how close on screen counts as "the same place", for preferring the one
    nearer the eye }
  TIE_PX = 1.0;
var
  I, K, H: Integer;
  Best, BestZ: Double;
  QA, QB, Look: TP3;
  PC: TProjCache;

  { Project the segment, find the nearest point along it on screen, then read
    the same fraction back off the model segment.  The projection is affine,
    so the two fractions are the same number. }
  procedure Try_(const MA, MB: TP3);
  var
    PA, PB: TPointF;
    DX, DY, L2, T, D, QZ: Double;
    Q: TP3;
  begin
    PA := ProjectAt(PC, MA);
    PB := ProjectAt(PC, MB);
    DX := PB.X - PA.X;
    DY := PB.Y - PA.Y;
    L2 := DX * DX + DY * DY;
    if L2 < 1E-12 then Exit;
    T := EnsureRange(((SX - PA.X) * DX + (SY - PA.Y) * DY) / L2, 0, 1);
    D := Sqrt(Sqr(SX - (PA.X + DX * T)) + Sqr(SY - (PA.Y + DY * T)));
    Q := P3(MA.X + (MB.X - MA.X) * T, MA.Y + (MB.Y - MA.Y) * T,
            MA.Z + (MB.Z - MA.Z) * T);
    QZ := Dot3(Q, Look);

    { Within reach, nearer on screen wins; a tie inside a pixel goes to
      whatever is nearer the eye, so edges a hair apart in depth do not flip
      by drawing order.  The reach is checked on its own so the first
      candidate is not held to a pixel short of TolPx. }
    if D > TolPx then Exit;
    if (Ent < 0) or (D < Best - TIE_PX) or
       ((D < Best + TIE_PX) and (QZ > BestZ + 1E-9)) then
    begin
      { An edge behind a solid is not being aimed at, or measuring along a
        box's front edge jumps to the back one.  An edge on the face it
        bounds is not hidden by it (see HiddenAt).  Only a would-be winner is
        asked, so it costs nothing in a clear view. }
      if HiddenAt(V, Q) then Exit;
      if D < Best then Best := D;
      BestZ := QZ;
      P := Q;
      A := MA;
      B := MB;
      Ent := I;
    end;
  end;

  { Is this loop nowhere near the cursor?  The projected bounding box
    contains the projected loop, so eight corners can rule out every side.
    Only worth it with seven or more sides. }
  function LoopFar(const Pts: TP3Array): Boolean;
  var
    J: Integer;
    Lo, Hi: TP3;
    Q: TPointF;
    MnX, MnY, MxX, MxY: Double;
    CX, CY, CZ: Integer;
  begin
    Result := False;
    if Length(Pts) < 7 then Exit;
    Lo := Pts[0];
    Hi := Pts[0];
    for J := 1 to High(Pts) do
    begin
      Lo.X := Min(Lo.X, Pts[J].X); Hi.X := Max(Hi.X, Pts[J].X);
      Lo.Y := Min(Lo.Y, Pts[J].Y); Hi.Y := Max(Hi.Y, Pts[J].Y);
      Lo.Z := Min(Lo.Z, Pts[J].Z); Hi.Z := Max(Hi.Z, Pts[J].Z);
    end;
    MnX := 1E30; MnY := 1E30; MxX := -1E30; MxY := -1E30;
    for CX := 0 to 1 do
      for CY := 0 to 1 do
        for CZ := 0 to 1 do
        begin
          Q := ProjectAt(PC, P3(specialize IfThen<Double>(CX = 0, Lo.X, Hi.X),
                                specialize IfThen<Double>(CY = 0, Lo.Y, Hi.Y),
                                specialize IfThen<Double>(CZ = 0, Lo.Z, Hi.Z)));
          MnX := Min(MnX, Q.X); MxX := Max(MxX, Q.X);
          MnY := Min(MnY, Q.Y); MxY := Max(MxY, Q.Y);
        end;
    Result := (SX < MnX - TolPx) or (SX > MxX + TolPx) or
              (SY < MnY - TolPx) or (SY > MxY + TolPx);
  end;

begin
  P := P3(0, 0, 0);
  A := P3(0, 0, 0);
  B := P3(0, 0, 0);
  Ent := -1;
  Best := 1E30;
  BestZ := -1E30;
  { the camera, once, instead of once per projected point - see BeginProject }
  BeginProject(V, PC);
  { points from the drawing towards the camera, so a bigger dot is nearer }
  Look := ViewDir(V);
  for I := 0 to FLive - 1 do
  begin
    if not InSlice(I) then Continue;
    case FEnts[I].Kind of
      ekLine: Try_(FEnts[I].A, FEnts[I].B);
      { a point on a guide line counts - that is what guides are for, until
        they are put away, and then it does not }
      ekGuide:
        if (not FGuidesHidden) and (Dist(FEnts[I].A, FEnts[I].B) > 1E-9) then
          Try_(P3(FEnts[I].A.X + (FEnts[I].A.X - FEnts[I].B.X) * 2000,
                  FEnts[I].A.Y + (FEnts[I].A.Y - FEnts[I].B.Y) * 2000,
                  FEnts[I].A.Z + (FEnts[I].A.Z - FEnts[I].B.Z) * 2000),
               P3(FEnts[I].B.X + (FEnts[I].B.X - FEnts[I].A.X) * 2000,
                  FEnts[I].B.Y + (FEnts[I].B.Y - FEnts[I].A.Y) * 2000,
                  FEnts[I].B.Z + (FEnts[I].B.Z - FEnts[I].A.Z) * 2000));
      { The outline of a face is visible geometry, so the cursor can run
        along it - faces from a revolve or an import have no lines.  A face
        that does gets found twice, for the same answer. }
      ekFace:
        begin
          if not LoopFar(FEnts[I].Poly) then
            for K := 0 to High(FEnts[I].Poly) do
              Try_(FEnts[I].Poly[K],
                   FEnts[I].Poly[(K + 1) mod Length(FEnts[I].Poly)]);
          { and what is cut out of it, which is just as much an edge }
          for H := 0 to High(FEnts[I].Holes) do
            if (Length(FEnts[I].Holes[H]) >= 3) and
               not LoopFar(FEnts[I].Holes[H]) then
              for K := 0 to High(FEnts[I].Holes[H]) do
                Try_(FEnts[I].Holes[H][K],
                     FEnts[I].Holes[H][(K + 1) mod Length(FEnts[I].Holes[H])]);
        end;
      ekArc:
        begin
          QA := ArcPoint(FEnts[I].C, FEnts[I].R, FEnts[I].A0, FEnts[I].Plane, FEnts[I].Nm);
          for K := 1 to 24 do
          begin
            QB := ArcPoint(FEnts[I].C, FEnts[I].R,
                    FEnts[I].A0 + FEnts[I].Sweep * K / 24, FEnts[I].Plane, FEnts[I].Nm);
            Try_(QA, QB);
            QA := QB;
          end;
        end;
    end;
  end;
  { A line or arc reports its own two ends, so "all of it" means the whole
    entity, not the chord under the cursor.  A face reports the side pointed
    at. }
  if (Ent >= 0) and (FEnts[Ent].Kind in [ekLine, ekArc]) then
  begin
    A := FEnts[Ent].A;
    B := FEnts[Ent].B;
  end;
  Result := Ent >= 0;
end;

{ How far the pointer is from a guide as it is drawn - the whole infinite
  line, not the one-unit stub that records its direction. }
function GuideScreenDist(const V: TProjector; const E: TWorkEnt;
  SX, SY: Double): Double;
var
  PA, PB: TPointF;
  D: TP3;
  L: Double;
begin
  PA := Project(V, E.A);
  if Dist(E.A, E.B) < 1E-9 then
  begin
    Result := Sqrt(Sqr(SX - PA.X) + Sqr(SY - PA.Y));
    Exit;
  end;
  D := Sub3(E.B, E.A);
  L := Sqrt(Sqr(D.X) + Sqr(D.Y) + Sqr(D.Z));
  if L < 1E-9 then Exit(1E30);
  PA := Project(V, P3(E.A.X - D.X / L * 5000, E.A.Y - D.Y / L * 5000,
                      E.A.Z - D.Z / L * 5000));
  PB := Project(V, P3(E.A.X + D.X / L * 5000, E.A.Y + D.Y / L * 5000,
                      E.A.Z + D.Z / L * 5000));
  Result := DistToSeg(SX, SY, PA.X, PA.Y, PB.X, PB.Y);
end;

{ A guide point has to be easy to grab again.  It usually sits on the line
  it was measured along, which would win a pixel off, so it is asked first,
  with a reach that matches the size it is drawn. }
function TWorkDoc.HitGuidePoint(const V: TProjector; SX, SY,
  TolPx: Double): Integer;
var
  I: Integer;
  D, Best: Double;
  PA: TPointF;
begin
  Result := -1;
  if FGuidesHidden then Exit;
  Best := TolPx;
  for I := FLive - 1 downto 0 do
  begin
    if FEnts[I].Kind <> ekGuide then Continue;
    if Dist(FEnts[I].A, FEnts[I].B) > 1E-9 then Continue;
    if not InSlice(I) then Continue;
    PA := Project(V, FEnts[I].A);
    D := Sqrt(Sqr(SX - PA.X) + Sqr(SY - PA.Y));
    if D <= Best then
    begin
      Best := D;
      Result := I;
    end;
  end;
end;

function TWorkDoc.RunsAlongEdge(const A, B: TP3): Boolean;
const
  TOL = 1E-6;
var
  I: Integer;
  Run, E, X: TP3;
  L, T: Double;

  { A is on this line, at an end or along it }
  function Touches(const P, Q: TP3): Boolean;
  var
    D: TP3;
    LL: Double;
  begin
    if (Dist(A, P) < TOL) or (Dist(A, Q) < TOL) then Exit(True);
    D := Sub3(Q, P);
    LL := Sqr(D.X) + Sqr(D.Y) + Sqr(D.Z);
    if LL < 1E-18 then Exit(False);
    T := ((A.X - P.X) * D.X + (A.Y - P.Y) * D.Y + (A.Z - P.Z) * D.Z) / LL;
    if (T < -TOL) or (T > 1 + TOL) then Exit(False);
    Result := Dist(A, P3(P.X + D.X * T, P.Y + D.Y * T, P.Z + D.Z * T)) < TOL;
  end;

begin
  Result := False;
  Run := Sub3(B, A);
  L := Sqrt(Sqr(Run.X) + Sqr(Run.Y) + Sqr(Run.Z));
  if L < 1E-9 then Exit;
  Run := P3(Run.X / L, Run.Y / L, Run.Z / L);
  for I := 0 to FLive - 1 do
  begin
    if FEnts[I].Kind <> ekLine then Continue;
    if FEnts[I].Dim then Continue;
    if not Touches(FEnts[I].A, FEnts[I].B) then Continue;
    E := Sub3(FEnts[I].B, FEnts[I].A);
    L := Sqrt(Sqr(E.X) + Sqr(E.Y) + Sqr(E.Z));
    if L < 1E-9 then Continue;
    E := P3(E.X / L, E.Y / L, E.Z / L);
    X := Cross3(E, Run);
    if Sqrt(Sqr(X.X) + Sqr(X.Y) + Sqr(X.Z)) < 1E-6 then Exit(True);
  end;
end;

function TWorkDoc.HitGuideLine(const V: TProjector; SX, SY, TolPx: Double): Integer;
var
  I: Integer;
  D, Best: Double;
begin
  Result := -1;
  if FGuidesHidden then Exit;
  Best := TolPx;
  for I := FLive - 1 downto 0 do
  begin
    if FEnts[I].Kind <> ekGuide then Continue;
    { a guide point is a guide with no length - HitGuidePoint's }
    if Dist(FEnts[I].A, FEnts[I].B) < 1E-9 then Continue;
    if not InSlice(I) then Continue;
    D := GuideScreenDist(V, FEnts[I], SX, SY);
    if D < Best then
    begin
      Best := D;
      Result := I;
    end;
  end;
end;

function TWorkDoc.HitEdge(const V: TProjector; SX, SY, TolPx: Double;
  GuideTolPx: Double): Integer;
var
  I: Integer;
  D, Best: Double;
  PA, PB: TPointF;
  DG: TDimGeom;
  PC: TProjCache;
  NearPt: TP3;
  VisHere, BestVis, Take: Boolean;
begin
  Result := -1;
  Best := TolPx;
  BestVis := False;
  NearPt := P3(0, 0, 0);
  { the camera once for the whole walk - see BeginProject }
  BeginProject(V, PC);
  for I := FLive - 1 downto 0 do
  begin
    if not (FEnts[I].Kind in [ekLine, ekArc, ekDim, ekGuide]) then Continue;
    if not InSlice(I) then Continue;
    { a hidden guide is not under the cursor either }
    if (FEnts[I].Kind = ekGuide) and (FGuidesHidden or (GuideTolPx < -1.5)) then Continue;
    if FEnts[I].Kind = ekGuide then
    begin
      D := GuideScreenDist(V, FEnts[I], SX, SY);
      { a guide answers on its own reach, which may be shorter than an
        edge's - see the note on GuideTolPx }
      if (GuideTolPx >= 0) and (D > GuideTolPx) then Continue;
    end
    else if FEnts[I].Kind = ekArc then
      { a tilted circle is an ellipse on screen, so measure against the
        drawn segments }
      D := ArcNearestAt(PC, FEnts[I], SX, SY, NearPt, TolPx)
    else if FEnts[I].Kind = ekDim then
    begin
      { A dimension is drawn off to the side of what it measures, so test
        the drawn lines, not the measured points. }
      if not DimGeometry(V, FEnts[I].A, FEnts[I].B, FEnts[I].C, usImperial, DG,
           FEnts[I].Txt) then Continue;
      D := Min(DistToSeg(SX, SY, DG.LA.X, DG.LA.Y, DG.LB.X, DG.LB.Y),
           Min(DistToSeg(SX, SY, DG.A.X, DG.A.Y, DG.W1.X, DG.W1.Y),
               DistToSeg(SX, SY, DG.B.X, DG.B.Y, DG.W2.X, DG.W2.Y)));
    end
    else
    begin
      PA := ProjectAt(PC, FEnts[I].A);
      PB := ProjectAt(PC, FEnts[I].B);
      D := DistToSeg(SX, SY, PA.X, PA.Y, PB.X, PB.Y);
      NearPt := Lerp3(FEnts[I].A, FEnts[I].B,
        SegParam(SX, SY, PA.X, PA.Y, PB.X, PB.Y));
    end;
    if not (D < TolPx) then Continue;

    { --- what is in front, where you are pointing ----------------------
      An edge visible at the point nearest the cursor beats one hidden there,
      however close; among equals the nearest wins, so a knob's rim beats the
      wall below it.  An edge hidden at all three samples along it is not
      pickable at all; that is only asked once it is hidden here. }
    VisHere := True;
    if FEnts[I].Kind in [ekLine, ekArc] then
    begin
      VisHere := not HiddenAt(V, NearPt);
      if (not VisHere) and
         HiddenAt(V, Lerp3(FEnts[I].A, FEnts[I].B, 0.5)) and
         HiddenAt(V, Lerp3(FEnts[I].A, FEnts[I].B, 0.2)) and
         HiddenAt(V, Lerp3(FEnts[I].A, FEnts[I].B, 0.8)) then Continue;
    end;

    Take := Result < 0;
    if not Take then
      if VisHere and not BestVis then Take := True
      else if (VisHere = BestVis) and (D < Best) then Take := True;
    if Take then
    begin
      Best := D;
      BestVis := VisHere;
      Result := I;
    end;
  end;
end;

{ Which faces each line, arc, dimension or note lies on, within the face's
  extent.  Pure - reads the entities given and writes the lists - so it can
  run on a worker. }
procedure ComputeOnFace(const Ents: array of TWorkEnt; Count: Integer; out Lists: TIntArrayWArray);
const
  SLACK = 1E-3;
var
  F, I, K: Integer;
  N, P0, Lo, Hi, A, B: TP3;
  D: Double;
  ELo, EHi: array of TP3;

  procedure Grow(var L, H: TP3; const P: TP3);
  begin
    if P.X < L.X then L.X := P.X; if P.Y < L.Y then L.Y := P.Y; if P.Z < L.Z then L.Z := P.Z;
    if P.X > H.X then H.X := P.X; if P.Y > H.Y then H.Y := P.Y; if P.Z > H.Z then H.Z := P.Z;
  end;

  function OnPlane(const P: TP3): Boolean;
  begin
    Result := Abs(Dot3(N, P) - D) < 1E-6;
  end;

  { Newell's normal of the outline; the same reading FaceNormal gives }
  function NormalOf(const E: TWorkEnt): TP3;
  var
    I, J, M: Integer;
    Acc: TP3;
  begin
    M := Length(E.Poly);
    Acc := P3(0, 0, 0);
    for I := 0 to M - 1 do
    begin
      J := (I + 1) mod M;
      Acc.X := Acc.X + (E.Poly[I].Y - E.Poly[J].Y) * (E.Poly[I].Z + E.Poly[J].Z);
      Acc.Y := Acc.Y + (E.Poly[I].Z - E.Poly[J].Z) * (E.Poly[I].X + E.Poly[J].X);
      Acc.Z := Acc.Z + (E.Poly[I].X - E.Poly[J].X) * (E.Poly[I].Y + E.Poly[J].Y);
    end;
    Result := Norm3(Acc);
  end;

begin
  SetLength(Lists, Count);
  SetLength(ELo, Count);
  SetLength(EHi, Count);
  for I := 0 to Count - 1 do
  begin
    SetLength(Lists[I], 0);
    { the extent of each thing that could lie on a face }
    case Ents[I].Kind of
      ekLine, ekDim, ekText:
        begin
          ELo[I] := Ents[I].A; EHi[I] := Ents[I].A;
          Grow(ELo[I], EHi[I], Ents[I].B);
        end;
      ekArc:
        begin
          ELo[I] := P3(Ents[I].C.X - Ents[I].R, Ents[I].C.Y - Ents[I].R, Ents[I].C.Z - Ents[I].R);
          EHi[I] := P3(Ents[I].C.X + Ents[I].R, Ents[I].C.Y + Ents[I].R, Ents[I].C.Z + Ents[I].R);
        end;
    end;
  end;
  for F := 0 to Count - 1 do
  begin
    if (Ents[F].Kind <> ekFace) or (Length(Ents[F].Poly) < 3) then Continue;
    N := NormalOf(Ents[F]);
    P0 := Ents[F].Poly[0];
    D := Dot3(N, P0);
    Lo := P0; Hi := P0;
    for K := 1 to High(Ents[F].Poly) do Grow(Lo, Hi, Ents[F].Poly[K]);
    Lo := P3(Lo.X - SLACK, Lo.Y - SLACK, Lo.Z - SLACK);
    Hi := P3(Hi.X + SLACK, Hi.Y + SLACK, Hi.Z + SLACK);
    for I := 0 to Count - 1 do
    begin
      if not (Ents[I].Kind in [ekLine, ekArc, ekDim, ekText]) then Continue;
      { only what reaches over the face at all }
      if (EHi[I].X < Lo.X) or (ELo[I].X > Hi.X) or (EHi[I].Y < Lo.Y) or (ELo[I].Y > Hi.Y) or
         (EHi[I].Z < Lo.Z) or (ELo[I].Z > Hi.Z) then Continue;
      if Ents[I].Kind = ekArc then
      begin
        A := Ents[I].C;
        B := ArcPoint(Ents[I].C, Ents[I].R, Ents[I].A0, Ents[I].Plane, Ents[I].Nm);
      end
      else
      begin
        A := Ents[I].A;
        B := Ents[I].B;
      end;
      if OnPlane(A) and OnPlane(B) then
      begin
        SetLength(Lists[I], Length(Lists[I]) + 1);
        Lists[I][High(Lists[I])] := F;
      end;
    end;
  end;
end;

type
  { The worker owns a deep copy of the entities, since the main thread edits
    polygons in place, computes on it and queues one method back.  It touches
    nothing else and reports errors through Failed; a worker never shows a
    dialog. }
  TOnFaceWorker = class(TThread)
  public
    Doc: TWorkDoc;
    Seq: Integer;
    Ents: array of TWorkEnt;
    Lists: TIntArrayWArray;
    Ms: Double;
    DoneAt: QWord;
    Failed: Boolean;
    procedure Execute; override;
  end;

procedure TOnFaceWorker.Execute;
var
  T0: QWord;
begin
  try
    T0 := GetTickCount64;
    ComputeOnFace(Ents, Length(Ents), Lists);
    Ms := GetTickCount64 - T0;
  except
    Failed := True;
  end;
  DoneAt := GetTickCount64;
  { back on the main thread, when it next looks at its messages }
  Queue(@Doc.OnFaceArrived);
end;

{ Main thread only: the worker's result, taken if the drawing is still the
  one it was made from. }
procedure TWorkDoc.OnFaceArrived;
var
  W: TOnFaceWorker;
begin
  W := TOnFaceWorker(FOnFaceWorker);
  if W = nil then Exit;
  W.WaitFor;
  if W.Failed then Inc(OnFaceFailed)
  else if W.Seq <> FEditSeq then Inc(OnFaceDiscarded)
  else
  begin
    FOnFace := W.Lists;
    FOnFaceOK := True;
    OnFaceWorkerMs := W.Ms;
    OnFaceBuiltOn := 'a worker';
    OnFaceLagMs := GetTickCount64 - W.DoneAt;
    Inc(OnFaceBuilds);
  end;
  FOnFaceWorker := nil;
  W.Free;
end;

function TWorkDoc.OnFaceReady: Boolean;
begin
  Result := FOnFaceOK and (Length(FOnFace) = FLive);
end;

procedure TWorkDoc.EnsureOnFace;
var
  W: TOnFaceWorker;
  I: Integer;
  T0: QWord;
begin
  if OnFaceReady then Exit;
  if not Threads then
  begin
    Inc(OnFaceBuilds);
    T0 := GetTickCount64;
    ComputeOnFace(FEnts, FLive, FOnFace);
    OnFaceWorkerMs := GetTickCount64 - T0;
    OnFaceBuiltOn := 'the main thread';
    FOnFaceOK := True;
    Exit;
  end;
  { A queued result is delivered only when the main loop is idle, and a main
    thread painting frame after frame never is, so check the queue here
    before deciding there is no cache. }
  if FOnFaceWorker <> nil then
  begin
    CheckSynchronize(0);
    if OnFaceReady then Exit;
  end;
  { one worker at a time; a change while it runs is caught by the sequence
    and the next call starts another }
  if FOnFaceWorker <> nil then Exit;
  W := TOnFaceWorker.Create(True);
  W.Doc := Self;
  W.Seq := FEditSeq;
  W.FreeOnTerminate := False;
  SetLength(W.Ents, FLive);
  for I := 0 to FLive - 1 do
  begin
    W.Ents[I] := FEnts[I];
    W.Ents[I].Poly := Copy(FEnts[I].Poly);
    W.Ents[I].Holes := nil;
    W.Ents[I].Txt := '';
  end;
  FOnFaceWorker := W;
  W.Start;
end;

function TWorkDoc.DepthPointNear(SX, SY, Radius: Integer; out P: TP3): Boolean;
var
  R, DX, DY, BX, BY: Integer;
  Z, Best, D2: Double;
  Q0, Look: TP3;
begin
  Result := False;
  P := P3(0, 0, 0);
  if (LastSurf = nil) or not LastSurf.DepthOn then Exit;
  Best := 1E30;
  BX := 0; BY := 0;
  { the nearest drawn pixel to the point, within Radius - a straight scan
    of the frame, a few milliseconds, once per press }
  for DY := Max(0, SY - Radius) to Min(LastSurf.Height - 1, SY + Radius) do
    for DX := Max(0, SX - Radius) to Min(LastSurf.Width - 1, SX + Radius) do
    begin
      D2 := Sqr(DX - SX) + Sqr(DY - SY);
      if D2 >= Best then Continue;
      Z := LastSurf.DepthAt(DX, DY);
      if Z < -1E29 then Continue;
      Best := D2; BX := DX; BY := DY;
    end;
  if Best >= 1E29 then Exit;
  R := 0;
  Z := LastSurf.DepthAt(BX, BY);
  { the depth is the distance along the view direction; a point on the
    ray through that pixel, slid to that depth, is the surface }
  Look := ViewDir(LastV);
  Q0 := Unproject(LastV, BX, BY, plXY, P3(0, 0, 0));
  if IsNan(Q0.X) or IsNan(Q0.Y) or IsNan(Q0.Z) then Exit;
  P := P3(Q0.X + Look.X * (Z - Dot3(Q0, Look)),
          Q0.Y + Look.Y * (Z - Dot3(Q0, Look)),
          Q0.Z + Look.Z * (Z - Dot3(Q0, Look)));
  Result := True;
end;

function TWorkDoc.DepthHidden(const P: TP3): Boolean;
var
  SP: TPointF;
  D, Zb, Zx, Zy, Zn, Grad: Double;
  DX, DY: Integer;
  Look: TP3;
begin
  Result := False;
  if (LastSurf = nil) or not LastSurf.DepthOn then Exit;
  SP := Project(LastV, P);
  Zb := LastSurf.DepthAt(Round(SP.X), Round(SP.Y));
  if Zb < -1E29 then Exit;
  Look := ViewDir(LastV);
  D := Dot3(P, Look);
  { the same reading as the renderer's own Covered: half the local slope of
    depth either way, capped, plus a little for the precision of the buffer }
  Zx := LastSurf.DepthAt(Round(SP.X) + 1, Round(SP.Y));
  if Zx < -1E29 then Zx := LastSurf.DepthAt(Round(SP.X) - 1, Round(SP.Y));
  Zy := LastSurf.DepthAt(Round(SP.X), Round(SP.Y) + 1);
  if Zy < -1E29 then Zy := LastSurf.DepthAt(Round(SP.X), Round(SP.Y) - 1);
  Grad := 0;
  if Zx > -1E29 then Grad := Grad + 0.5 * Abs(Zx - Zb) else Grad := Grad + 0.5 / Max(1E-9, LastV.Ppu);
  if Zy > -1E29 then Grad := Grad + 0.5 * Abs(Zy - Zb) else Grad := Grad + 0.5 / Max(1E-9, LastV.Ppu);
  Grad := Min(Grad, 6 / Max(1E-9, LastV.Ppu));
  Result := Zb > D + Grad + 2E-4 * (1 + Abs(D)) + 0.02 / Max(1E-9, LastV.Ppu);
  if not Result then Exit;
  { Hidden only if the pixels round it are covered too.  The one pixel under
    an edge belongs to whichever face the rasterizer gave it, so a visible
    edge can read as hidden; something truly behind a face is behind it a
    pixel either way. }
  for DX := -1 to 1 do
    for DY := -1 to 1 do
    begin
      if (DX = 0) and (DY = 0) then Continue;
      Zn := LastSurf.DepthAt(Round(SP.X) + DX, Round(SP.Y) + DY);
      if (Zn < -1E29) or
         (Zn <= D + Grad + 2E-4 * (1 + Abs(D)) + 0.02 / Max(1E-9, LastV.Ppu)) then
        Exit(False);
    end;
end;

{ Is this point hidden behind a face?  A filled face is opaque, so what is
  behind it cannot be picked through it. }
function TWorkDoc.HiddenAt(const V: TProjector; const P: TP3): Boolean;
var
  I, A, B, N, H, M: Integer;
  SP: TPointF;
  Inside: Boolean;
  Nm, Look: TP3;
  Den, T: Double;
  Poly, HP: array of TPointF;
begin
  Result := False;
  { The last render's depth buffer answers in one lookup when asked with the
    same projector; otherwise walk the faces.  SameProjector compares field
    by field, since a byte compare trips on record padding. }
  if (LastSurf <> nil) and LastSurf.DepthOn and SameProjector(V, LastV) then
    Exit(DepthHidden(P));
  SP := Project(V, P);
  Look := ViewDir(V);
  for I := 0 to FLive - 1 do
  begin
    if FEnts[I].Kind <> ekFace then Continue;
    N := Length(FEnts[I].Poly);
    if N < 3 then Continue;
    Nm := FaceNormal(I);
    { A face the point lies in cannot hide it.  Every edge of a solid lies in
      the plane of the faces either side of it, and without this each one
      would hide itself. }
    if Abs(Dot3(Nm, P) - Dot3(Nm, FEnts[I].Poly[0])) < 1E-6 then Continue;
    Den := Dot3(Nm, Look);
    if Abs(Den) < 1E-12 then Continue;      { edge-on, hides nothing }
    { Where the line of sight through P meets this face's plane.  ViewDir
      points toward the camera, so a face in front of P is at a positive
      step. }
    T := (Dot3(Nm, FEnts[I].Poly[0]) - Dot3(Nm, P)) / Den;
    if T <= 1E-9 then Continue;
    SetLength(Poly, N);
    for A := 0 to N - 1 do Poly[A] := Project(V, FEnts[I].Poly[A]);
    Inside := False;
    B := N - 1;
    for A := 0 to N - 1 do
    begin
      if ((Poly[A].Y > SP.Y) <> (Poly[B].Y > SP.Y)) and
         (SP.X < (Poly[B].X - Poly[A].X) * (SP.Y - Poly[A].Y) /
                 (Poly[B].Y - Poly[A].Y) + Poly[A].X) then
        Inside := not Inside;
      B := A;
    end;
    { and out again through anything cut from it: a wall does not hide what
      is seen through its window }
    if Inside then
      for H := 0 to High(FEnts[I].Holes) do
      begin
        M := Length(FEnts[I].Holes[H]);
        if M < 3 then Continue;
        SetLength(HP, M);
        for A := 0 to M - 1 do HP[A] := Project(V, FEnts[I].Holes[H][A]);
        B := M - 1;
        for A := 0 to M - 1 do
        begin
          if ((HP[A].Y > SP.Y) <> (HP[B].Y > SP.Y)) and
             (SP.X < (HP[B].X - HP[A].X) * (SP.Y - HP[A].Y) /
                     (HP[B].Y - HP[A].Y) + HP[A].X) then
            Inside := not Inside;
          B := A;
        end;
      end;
    if Inside then Exit(True);
  end;
end;

procedure TWorkDoc.MoveNote(Index: Integer; const From, ToPt, Grab: TP3);
begin
  if (Index < 0) or (Index >= FLive) then Exit;
  if FEnts[Index].Kind <> ekText then Exit;
  FEnts[Index].A := P3(From.X + (ToPt.X - Grab.X),
                       From.Y + (ToPt.Y - Grab.Y),
                       From.Z + (ToPt.Z - Grab.Z));
  FSnapDirty := True; FOnFaceOK := False; Inc(FEditSeq);
end;

function TWorkDoc.HitNote(SX, SY: Double): Integer;
var
  I: Integer;
begin
  { Last drawn wins, which is the one on top. }
  for I := FLive - 1 downto 0 do
    if (FEnts[I].Kind = ekText) and not EntHidden(I) and (FEnts[I].BoxR > FEnts[I].BoxL) and
       (SX >= FEnts[I].BoxL) and (SX <= FEnts[I].BoxR) and
       (SY >= FEnts[I].BoxT) and (SY <= FEnts[I].BoxB) then
      Exit(I);
  Result := -1;
end;

{ What is under the cursor when it was not an edge or a face.  The nearest
  wins, not the newest; a tie within a pixel goes to the one nearer the eye,
  as in EdgeUnder.  The full walk is affordable because PickAt asks only
  after HitEdge and HitFace found nothing. }
function TWorkDoc.HitTest(const V: TProjector; SX, SY, TolPx: Double; Guides: Boolean): Integer;
const
  TIE_PX = 1.0;
var
  I: Integer;
  D, Best, Z, BestZ: Double;
  PA, PB: TPointF;
  DG: TDimGeom;
  Look, Mid: TP3;
  PC: TProjCache;
begin
  Result := -1;
  Best := 1E30;
  BestZ := -1E30;
  Look := ViewDir(V);
  { see HitEdge: the camera once for the walk, not once for every point }
  BeginProject(V, PC);
  for I := FLive - 1 downto 0 do
  begin
    if not InSlice(I) then Continue;
    { a hidden guide is not under the cursor, as in HitEdge }
    if (FEnts[I].Kind = ekGuide) and (FGuidesHidden or not Guides) then Continue;
    case FEnts[I].Kind of
      ekArc:
        D := ArcScreenDistAt(PC, FEnts[I], SX, SY, TolPx);
      ekText:
        begin
          { The words are the note: inside the box counts as on it.  Outside,
            the anchor still counts, for a note whose box is not drawn yet. }
          if (SX >= FEnts[I].BoxL) and (SX <= FEnts[I].BoxR) and
             (SY >= FEnts[I].BoxT) and (SY <= FEnts[I].BoxB) and
             (FEnts[I].BoxR > FEnts[I].BoxL) then
            D := 0
          else
          begin
            PA := ProjectAt(PC, FEnts[I].A);
            D := Sqrt(Sqr(SX - PA.X) + Sqr(SY - PA.Y));
          end;
        end;
      ekGuide:
        D := GuideScreenDist(V, FEnts[I], SX, SY);
      ekBore, ekFace:
        D := 1E30;   { not things to pick by their line }
      ekDim:
        { the drawn line and its witness lines, not the invisible chord
          through the geometry - that is where the eraser is aimed }
        if DimGeometry(V, FEnts[I].A, FEnts[I].B, FEnts[I].C, usImperial, DG,
             FEnts[I].Txt) then
          D := Min(DistToSeg(SX, SY, DG.LA.X, DG.LA.Y, DG.LB.X, DG.LB.Y),
               Min(DistToSeg(SX, SY, DG.A.X, DG.A.Y, DG.W1.X, DG.W1.Y),
                   DistToSeg(SX, SY, DG.B.X, DG.B.Y, DG.W2.X, DG.W2.Y)))
        else
          D := 1E30;
    else
      begin
        PA := ProjectAt(PC, FEnts[I].A);
        PB := ProjectAt(PC, FEnts[I].B);
        D := DistToSeg(SX, SY, PA.X, PA.Y, PB.X, PB.Y);
      end;
    end;
    { Within reach, the nearest wins; a tie inside a pixel goes to whatever
      is nearer the eye.  Faces and bores set D out of reach above. }
    if D > TolPx then Continue;
    Mid := Lerp3(FEnts[I].A, FEnts[I].B, 0.5);
    Z := Dot3(Mid, Look);
    if (Result < 0) or (D < Best - TIE_PX) or
       ((D < Best + TIE_PX) and (Z > BestZ + 1E-9)) then
    begin
      { An edge behind a panel is not what was meant; notes and dimensions
        are drawn on top and stay pickable.  Only a would-be winner is asked. }
      if FEnts[I].Kind in [ekLine, ekArc] then
      begin
        if HiddenAt(V, Mid) and
           HiddenAt(V, Lerp3(FEnts[I].A, FEnts[I].B, 0.25)) and
           HiddenAt(V, Lerp3(FEnts[I].A, FEnts[I].B, 0.75)) then
          Continue;
      end;
      if D < Best then Best := D;
      BestZ := Z;
      Result := I;
    end;
  end;
end;

{ One list feeds both snapping and inference, so a crossing and the
  midpoints it creates are just as snappable as an original endpoint.  A
  small bias keeps the more definite kinds winning a close contest. }
function TWorkDoc.BestSnap(const V: TProjector; SX, SY, TolPx: Double;
  out Hit: TSnapHit): Boolean;
const
  { snOnEdge and snOnFace are found separately; their entries only keep the
    array the right length.  The origin sits just under an endpoint: a
    landmark, but a drawn corner near it is more likely the target. }
  BIAS: array[TSnapKind] of Double =
    (0, 0, 3.5, 1.0, 2.0, 1.5, 0.25, 0, 0, 3.0, 0, 2.0);   { snOnFace: found separately too }
var
  I: Integer;
  P: TPointF;
  D, Best: Double;
  PC: TProjCache;
begin
  if FSnapDirty then RebuildSnapCache;

  if (not FSnapScreenOK) or (Length(FSnapScreen) <> Length(FSnapCache)) or
     (not SameProjector(V, FSnapScreenV)) then
  begin
    SetLength(FSnapScreen, Length(FSnapCache));
    { thousands of points, and the camera worked out once for the lot }
    BeginProject(V, PC);
    for I := 0 to High(FSnapCache) do
      FSnapScreen[I] := ProjectAt(PC, FSnapCache[I].P);
    FSnapScreenV := V;
    FSnapScreenOK := True;
  end;

  Best := 1E30;
  Hit.Kind := snNone;
  Hit.P := P3(0, 0, 0);

  for I := 0 to High(FSnapCache) do
  begin
    P := FSnapScreen[I];
    if (Abs(SX - P.X) > TolPx) or (Abs(SY - P.Y) > TolPx) then Continue;
    D := Sqrt(Sqr(SX - P.X) + Sqr(SY - P.Y));
    if D > TolPx then Continue;
    D := D - BIAS[FSnapCache[I].Kind];
    if D < Best then
    begin
      { A point behind a panel is not being aimed at; snapping to a tunnel
        corner through the wall put the click inside the block.  Only
        would-be winners are asked. }
      if HiddenAt(V, FSnapCache[I].P) then Continue;
      Best := D;
      Hit := FSnapCache[I];
    end;
  end;

  Result := Hit.Kind <> snNone;
end;

function TWorkDoc.Bounds(out Lo, Hi: TP3): Boolean;
var
  I, K: Integer;

  procedure Grow(const P: TP3);
  begin
    Lo.X := Min(Lo.X, P.X); Lo.Y := Min(Lo.Y, P.Y); Lo.Z := Min(Lo.Z, P.Z);
    Hi.X := Max(Hi.X, P.X); Hi.Y := Max(Hi.Y, P.Y); Hi.Z := Max(Hi.Z, P.Z);
  end;

begin
  Result := FLive > 0;
  Lo := P3(1E30, 1E30, 1E30);
  Hi := P3(-1E30, -1E30, -1E30);
  for I := 0 to FLive - 1 do
    case FEnts[I].Kind of
      ekArc:
        begin
          Grow(P3(FEnts[I].C.X - FEnts[I].R, FEnts[I].C.Y - FEnts[I].R,
                  FEnts[I].C.Z - FEnts[I].R));
          Grow(P3(FEnts[I].C.X + FEnts[I].R, FEnts[I].C.Y + FEnts[I].R,
                  FEnts[I].C.Z + FEnts[I].R));
        end;
      ekFace:
        for K := 0 to High(FEnts[I].Poly) do
          Grow(FEnts[I].Poly[K]);
    else
      begin
        Grow(FEnts[I].A);
        Grow(FEnts[I].B);
      end;
    end;
end;

{ ---------------------------------------------------------------------- }
{ persistence                                                              }
{ ---------------------------------------------------------------------- }

procedure TWorkDoc.HealArcEnds;
const
  { a hundredth of an inch or so, in feet: far more than any rounding,
    far less than any gap anybody drew }
  HEAL_TOL = 1E-3;
type
  TEnd = record X: Double; P: TP3; Ent: Integer; end;
var
  Ends: array of TEnd;
  NE, I, Pass: Integer;
  AU, AV, Ps, Pe, Ts, Te, C2: TP3;
  SU, SV, EU, EV, MU, MV, DU, DV, NU, NV, L, T, CU, CV, R2, A0, A1, Sw: Double;
  Moved: Boolean;

  procedure AddEnd(const P: TP3; Ent: Integer);
  begin
    if NE >= Length(Ends) then SetLength(Ends, Max(64, NE * 2));
    Ends[NE].X := P.X; Ends[NE].P := P; Ends[NE].Ent := Ent;
    Inc(NE);
  end;

  procedure SortEnds(Lo, Hi: Integer);
  var
    A, B: Integer;
    Piv: Double;
    Tmp: TEnd;
  begin
    while Lo < Hi do
    begin
      A := Lo; B := Hi; Piv := Ends[(Lo + Hi) div 2].X;
      repeat
        while Ends[A].X < Piv do Inc(A);
        while Ends[B].X > Piv do Dec(B);
        if A <= B then
        begin
          Tmp := Ends[A]; Ends[A] := Ends[B]; Ends[B] := Tmp;
          Inc(A); Dec(B);
        end;
      until A > B;
      if B - Lo < Hi - A then begin SortEnds(Lo, B); Lo := A; end
      else begin SortEnds(A, Hi); Hi := B; end;
    end;
  end;

  { the nearest end of something else within the tolerance, or P itself }
  function Nearest(const P: TP3; Self_: Integer): TP3;
  var
    Lo, Hi, Mid, K: Integer;
    D, Best: Double;
  begin
    Result := P;
    Best := HEAL_TOL;
    Lo := 0; Hi := NE;
    while Lo < Hi do
    begin
      Mid := (Lo + Hi) div 2;
      if Ends[Mid].X < P.X - HEAL_TOL then Lo := Mid + 1 else Hi := Mid;
    end;
    K := Lo;
    while (K < NE) and (Ends[K].X <= P.X + HEAL_TOL) do
    begin
      if Ends[K].Ent <> Self_ then
      begin
        D := Dist(P, Ends[K].P);
        if D < Best then begin Best := D; Result := Ends[K].P; end;
      end;
      Inc(K);
    end;
  end;

begin
  { twice: an arc meeting an arc meets it where the first pass left it }
  for Pass := 1 to 2 do
  begin
    NE := 0;
    Ends := nil;
    for I := 0 to FLive - 1 do
      case FEnts[I].Kind of
        ekLine:
          if not FEnts[I].Dim then
          begin
            AddEnd(FEnts[I].A, I); AddEnd(FEnts[I].B, I);
          end;
        ekArc:
          begin
            AddEnd(ArcPoint(FEnts[I].C, FEnts[I].R, FEnts[I].A0, FEnts[I].Plane, FEnts[I].Nm), I);
            AddEnd(ArcPoint(FEnts[I].C, FEnts[I].R, FEnts[I].A0 + FEnts[I].Sweep, FEnts[I].Plane, FEnts[I].Nm), I);
          end;
      end;
    if NE = 0 then Exit;
    SortEnds(0, NE - 1);
    Moved := False;
    for I := 0 to FLive - 1 do
    begin
      if FEnts[I].Kind <> ekArc then Continue;
      { a whole circle has no ends to bring anywhere }
      if Abs(Abs(FEnts[I].Sweep) - 2 * Pi) < 1E-6 then Continue;
      Ps := ArcPoint(FEnts[I].C, FEnts[I].R, FEnts[I].A0, FEnts[I].Plane, FEnts[I].Nm);
      Pe := ArcPoint(FEnts[I].C, FEnts[I].R, FEnts[I].A0 + FEnts[I].Sweep, FEnts[I].Plane, FEnts[I].Nm);
      Ts := Nearest(Ps, I); Te := Nearest(Pe, I);
      if (Dist(Ts, Ps) < 1E-12) and (Dist(Te, Pe) < 1E-12) then Continue;
      if FEnts[I].Plane = plFree then AxesFromNormal(FEnts[I].Nm, AU, AV)
      else PlaneAxes(FEnts[I].Plane, AU, AV);
      { in the arc's own plane, from its old center }
      SU := Dot3(Sub3(Ts, FEnts[I].C), AU);
      SV := Dot3(Sub3(Ts, FEnts[I].C), AV);
      EU := Dot3(Sub3(Te, FEnts[I].C), AU);
      EV := Dot3(Sub3(Te, FEnts[I].C), AV);
      { the circle through both ends whose center is nearest the old one:
        on the line halfway between them, square to the chord }
      MU := (SU + EU) / 2; MV := (SV + EV) / 2;
      DU := EU - SU; DV := EV - SV;
      L := Hypot(DU, DV);
      if L < 1E-9 then Continue;
      NU := -DV / L; NV := DU / L;
      T := -(MU * NU + MV * NV);
      CU := MU + NU * T; CV := MV + NV * T;
      R2 := Hypot(SU - CU, SV - CV);
      { nothing but rounding to put right, or leave it be }
      if (Hypot(CU, CV) > HEAL_TOL) or (Abs(R2 - FEnts[I].R) > HEAL_TOL) then Continue;
      A0 := ArcTan2(SV - CV, SU - CU);
      A1 := ArcTan2(EV - CV, EU - CU);
      Sw := A1 - A0;
      while Sw - FEnts[I].Sweep > Pi do Sw := Sw - 2 * Pi;
      while FEnts[I].Sweep - Sw > Pi do Sw := Sw + 2 * Pi;
      C2 := P3(FEnts[I].C.X + AU.X * CU + AV.X * CV, FEnts[I].C.Y + AU.Y * CU + AV.Y * CV,
        FEnts[I].C.Z + AU.Z * CU + AV.Z * CV);
      FEnts[I].C := C2;
      FEnts[I].R := R2;
      FEnts[I].A0 := A0;
      FEnts[I].Sweep := Sw;
      FEnts[I].A := ArcPoint(C2, R2, A0, FEnts[I].Plane, FEnts[I].Nm);
      FEnts[I].B := ArcPoint(C2, R2, A0 + Sw, FEnts[I].Plane, FEnts[I].Nm);
      Moved := True;
    end;
    if not Moved then Break;
  end;
end;

function TWorkDoc.WriteSCAD(L: TStrings; U: TUnitSystem;
  out Solids: Integer; out Closed: Boolean; AtOrigin: Boolean): Integer;
var
  Scale: Double;
  Mid, BLo, BHi: TP3;
  Grp, Top, I, J, K, NPt, NTri, Slot: Integer;
  Tris: TTriList;
  Corners: TP3Array;
  Nm, A, B, C, Cr, E1, E2: TP3;
  Ix: TFPHashList;
  Key: string;
  Pts: TP3Array;
  Names: TStringList;
  Row: string;
  Open_: Boolean;
  Made: Boolean;

  { A point's slot in this solid's list, added if new.  A polyhedron shares
    corners between faces, and a duplicate leaves a seam CGAL will not close. }
  function SlotOf(const P: TP3): Integer;
  begin
    Key := Format('%d,%d,%d', [Round(P.X * 1E6), Round(P.Y * 1E6),
                               Round(P.Z * 1E6)]);
    Result := Ix.FindIndexOf(Key);
    if Result >= 0 then
    begin
      Result := PtrInt(Ix.Items[Result]) - 1;
      Exit;
    end;
    if NPt >= Length(Pts) then SetLength(Pts, Max(64, NPt * 2));
    Pts[NPt] := P;
    Ix.Add(Key, Pointer(PtrInt(NPt) + 1));
    Result := NPt;
    Inc(NPt);
  end;

begin
  Result := 0;
  Solids := 0;
  { OpenSCAD renders an open surface but a printer will not print it, so say
    whether it is closed, as the STL does }
  Closed := True;
  for I := 0 to FLive - 1 do
  begin
    if FEnts[I].Kind <> ekFace then Continue;
    if Length(FEnts[I].Poly) < 3 then Continue;
    if FEnts[I].Solid and (FEnts[I].Grp > 0) and
       not GroupClosed(FEnts[I].Grp) then Closed := False;
    if not FEnts[I].Solid then Closed := False;
  end;
  if U = usMetric then Scale := 1000 else Scale := 304.8;
  { Centered across the bed and standing on it, as in WriteSTL. }
  Mid := P3(0, 0, 0);
  if AtOrigin and Bounds(BLo, BHi) then
    Mid := P3((BLo.X + BHi.X) / 2, (BLo.Y + BHi.Y) / 2, BLo.Z);

  Top := 0;
  for I := 0 to FLive - 1 do
    if (FEnts[I].Kind = ekFace) and (FEnts[I].Grp > Top) then Top := FEnts[I].Grp;

  Names := TStringList.Create;
  try
    L.Add('// Heckers Sketch - ' + FormatDateTime('yyyy-mm-dd hh:nn', Now));
    if AtOrigin then
      L.Add('// Millimeters, centered on the bed and standing on it.  A surface, not a')
    else
      L.Add('// Millimeters, where the drawing put it.  A surface, not a');
    L.Add('// construction - see the notes at');
    L.Add('// the bottom.');
    L.Add('');

    { Group 0 is everything loose, and it goes out too, in its own module, so
      nothing is silently dropped - but it is named for what it is. }
    for Grp := 0 to Top do
    begin
      Made := False;
      NPt := 0;
      NTri := 0;
      SetLength(Pts, 0);
      Ix := TFPHashList.Create;
      try
        Row := '';
        for I := 0 to FLive - 1 do
        begin
          if FEnts[I].Kind <> ekFace then Continue;
          if FEnts[I].Grp <> Grp then Continue;
          Tris := FaceCut(I);
          if Length(Tris) < 3 then Continue;
          Corners := FaceCorners(I);
          Nm := FaceNormal(I);
          for J := 0 to (Length(Tris) div 3) - 1 do
          begin
            if (Tris[J*3] >= Length(Corners)) or (Tris[J*3+1] >= Length(Corners))
              or (Tris[J*3+2] >= Length(Corners)) then Continue;
            A := Corners[Tris[J*3]];
            B := Corners[Tris[J*3+1]];
            C := Corners[Tris[J*3+2]];
            E1 := Sub3(B, A);
            E2 := Sub3(C, A);
            Cr := Cross3(E1, E2);
            if Sqrt(Sqr(Cr.X) + Sqr(Cr.Y) + Sqr(Cr.Z)) < 1E-12 then Continue;
            { turn it so the three run anticlockwise seen from outside, the
              same as STL does, and then write them out backwards, because
              that is what OpenSCAD asks for }
            if Dot3(Cr, Nm) < 0 then
            begin
              Cr := B;
              B := C;
              C := Cr;
            end;
            if Row <> '' then Row := Row + ', ';
            Row := Row + Format('[%d,%d,%d]',
              [SlotOf(C), SlotOf(B), SlotOf(A)]);
            Inc(NTri);
            if Length(Row) > 1200 then
            begin
              Names.Add('    ' + Row);
              Row := '';
            end;
          end;
        end;
        if Row <> '' then Names.Add('    ' + Row);
        Made := NTri > 0;

        if Made then
        begin
          Open_ := (Grp = 0) or not GroupClosed(Grp);
          if Grp = 0 then Key := 'hs_loose'
          else Key := Format('hs_solid_%d', [Grp]);
          if Open_ then
            L.Add(Format('// %s - %d triangles.  NOT a closed solid; OpenSCAD',
              [Key, NTri]))
          else
            L.Add(Format('// %s - %d triangles, closed.', [Key, NTri]));
          if Open_ then
            L.Add('// will render it but may refuse to cut with it.');
          L.Add('module ' + Key + '() {');
          L.Add('  polyhedron(');
          L.Add('    points=[');
          Row := '';
          for K := 0 to NPt - 1 do
          begin
            if Row <> '' then Row := Row + ', ';
            Row := Row + Format('[%.4f,%.4f,%.4f]',
              [(Pts[K].X - Mid.X) * Scale, (Pts[K].Y - Mid.Y) * Scale,
               (Pts[K].Z - Mid.Z) * Scale], DotFS);
            if Length(Row) > 1200 then
            begin
              L.Add('      ' + Row + ',');
              Row := '';
            end;
          end;
          if Row <> '' then L.Add('      ' + Row);
          L.Add('    ],');
          L.Add('    faces=[');
          for K := 0 to Names.Count - 1 do
            if K < Names.Count - 1 then L.Add('  ' + Names[K] + ',')
            else L.Add('  ' + Names[K]);
          L.Add('    ],');
          { convexity is a hint of how many times a ray can cross the
            surface; the preview draws concave shapes wrong without it }
          L.Add('    convexity=10);');
          L.Add('}');
          L.Add('');
          Names.Clear;
          Inc(Solids);
          Inc(Result, NTri);
          if Grp = 0 then Slot := 0 else Slot := Grp;
          if Slot >= 0 then ;
        end
        else
          Names.Clear;
      finally
        Ix.Free;
      end;
    end;

    if Solids = 0 then
    begin
      L.Add('// This drawing has no faces, so there is no shape to describe.');
      Exit;
    end;

    L.Add('module heckers_sketch() {');
    L.Add('  union() {');
    for Grp := 0 to Top do
    begin
      Made := False;
      for I := 0 to FLive - 1 do
        if (FEnts[I].Kind = ekFace) and (FEnts[I].Grp = Grp) and
           (Length(FaceCut(I)) >= 3) then
        begin
          Made := True;
          Break;
        end;
      if not Made then Continue;
      if Grp = 0 then L.Add('    hs_loose();')
      else L.Add(Format('    hs_solid_%d();', [Grp]));
    end;
    L.Add('  }');
    L.Add('}');
    L.Add('');
    L.Add('heckers_sketch();');
    L.Add('');
    L.Add('// Notes.');
    L.Add('// This is the surface of the drawing, written as points and');
    L.Add('// faces.  It is not built out of cubes and cylinders and cannot');
    L.Add('// be taken apart into them, so the sizes here are not parameters');
    L.Add('// to change - to change the shape, change it in Heckers Sketch');
    L.Add('// and export it again.');
    L.Add('// What it is good for is everything around it: cut holes in it,');
    L.Add('// union it onto something, fit it to a part you are describing.');
  finally
    Names.Free;
  end;
end;

function TWorkDoc.WriteSTL(St: TStream; U: TUnitSystem;
  out Closed: Boolean; AtOrigin: Boolean): Integer;
var
  I, J, N: Integer;
  Mid, BLo, BHi: TP3;
  Tris: TTriList;
  Corners: TP3Array;
  Nm, A, B, C, E1, E2, Cr, Tmp: TP3;
  Scale, L2: Double;
  Head: array[0..79] of Byte;
  Cnt: LongWord;
  Attr: Word;
  Lbl: AnsiString;

  { a corner, in millimeters, measured from the middle of the model }
  procedure PutP(const P: TP3);
  var
    F: array[0..2] of Single;
  begin
    F[0] := (P.X - Mid.X) * Scale;
    F[1] := (P.Y - Mid.Y) * Scale;
    F[2] := (P.Z - Mid.Z) * Scale;
    St.WriteBuffer(F, SizeOf(F));
  end;

  { a direction, which has no units and must NOT be scaled - a normal 304.8
    long is not a normal }
  procedure PutN(const P: TP3);
  var
    F: array[0..2] of Single;
  begin
    F[0] := P.X;
    F[1] := P.Y;
    F[2] := P.Z;
    St.WriteBuffer(F, SizeOf(F));
  end;

begin
  Result := 0;
  Closed := True;
  if U = usMetric then Scale := 1000 else Scale := 304.8;
  { Centered across the bed and standing ON it.  Centering Z too puts half
    the model under the build plate. }
  Mid := P3(0, 0, 0);
  if AtOrigin and Bounds(BLo, BHi) then
    Mid := P3((BLo.X + BHi.X) / 2, (BLo.Y + BHi.Y) / 2, BLo.Z);

  { The header is 80 bytes of anything at all, except that it must not begin
    with the word "solid" - a reader that sees that decides the file is the
    ASCII kind and makes nothing of what follows. }
  FillChar(Head, SizeOf(Head), 0);
  Lbl := 'Heckers Sketch - millimeters';
  if Length(Lbl) > 79 then SetLength(Lbl, 79);
  Move(Lbl[1], Head[0], Length(Lbl));
  St.WriteBuffer(Head, SizeOf(Head));

  { the count goes in now as a placeholder and is written again at the end,
    when it is known }
  Cnt := 0;
  St.WriteBuffer(Cnt, SizeOf(Cnt));

  Attr := 0;
  for I := 0 to FLive - 1 do
  begin
    if FEnts[I].Kind <> ekFace then Continue;
    if Length(FEnts[I].Poly) < 3 then Continue;
    if FEnts[I].Solid and (FEnts[I].Grp > 0) and not GroupClosed(FEnts[I].Grp) then
      Closed := False;
    if not FEnts[I].Solid then Closed := False;

    Tris := FaceCut(I);
    if Length(Tris) < 3 then Continue;
    Corners := FaceCorners(I);
    Nm := FaceNormal(I);
    N := Length(Corners);

    for J := 0 to (Length(Tris) div 3) - 1 do
    begin
      if (Tris[J*3] >= N) or (Tris[J*3+1] >= N) or (Tris[J*3+2] >= N) then Continue;
      A := Corners[Tris[J*3]];
      B := Corners[Tris[J*3+1]];
      C := Corners[Tris[J*3+2]];
      E1 := Sub3(B, A);
      E2 := Sub3(C, A);
      Cr := Cross3(E1, E2);
      L2 := Sqrt(Sqr(Cr.X) + Sqr(Cr.Y) + Sqr(Cr.Z));
      if L2 < 1E-12 then Continue;   { no area, nothing to print }

      { STL wants corners anticlockwise seen from outside, so turn any
        triangle whose normal disagrees with the face's. }
      if Dot3(Cr, Nm) < 0 then
      begin
        Tmp := B;
        B := C;
        C := Tmp;
        E1 := Sub3(B, A);
        E2 := Sub3(C, A);
        Cr := Cross3(E1, E2);
        L2 := Sqrt(Sqr(Cr.X) + Sqr(Cr.Y) + Sqr(Cr.Z));
        if L2 < 1E-12 then Continue;
      end;

      PutN(P3(Cr.X / L2, Cr.Y / L2, Cr.Z / L2));
      PutP(A);
      PutP(B);
      PutP(C);
      St.WriteBuffer(Attr, SizeOf(Attr));
      Inc(Result);
    end;
  end;

  { a drawing with no faces is not a closed solid }
  if Result = 0 then Closed := False;

  { back over the placeholder with the real count }
  St.Position := 80;
  Cnt := Result;
  St.WriteBuffer(Cnt, SizeOf(Cnt));
  St.Position := St.Size;
end;

procedure TWorkDoc.WriteDXF(L: TStrings; const V: TProjector; U: TUnitSystem;
  ThreeD: Boolean; AtOrigin: Boolean = False);
var
  W: TDxfWriter;
  I, K, Steps, N: Integer;
  Sc, TX, TY, TZ, AX1, AY1, BX1, BY1: Double;
  XS, YS, ZS: array of Double;
  G: TDimGeom;
  Mid, BLo, BHi: TP3;

  { one point, in the file's units, flat or not }
  procedure At(const P: TP3; out X, Y, Z: Double);
  var
    S: TPointF;
  begin
    if ThreeD then
    begin
      X := (P.X - Mid.X) * Sc;
      Y := (P.Y - Mid.Y) * Sc;
      Z := (P.Z - Mid.Z) * Sc;
    end
    else
    begin
      { the view is in screen pixels with Y downwards; a DXF has Y up and is
        in drawing units, so the picture is put back to true size and turned
        the right way over }
      S := Project(V, P);
      X := (S.X - V.OX) / V.Ppu * Sc;
      Y := -(S.Y - V.OY) / V.Ppu * Sc;
      Z := 0;
    end;
  end;

  procedure Seg(const Lay: string; const A, B: TP3);
  var
    X1, Y1, Z1, X2, Y2, Z2: Double;
  begin
    At(A, X1, Y1, Z1);
    At(B, X2, Y2, Z2);
    W.Line(Lay, X1, Y1, Z1, X2, Y2, Z2);
  end;

  { a screen point of a dimension, in the file's units }
  procedure Flat(const S: TPointF; out X, Y: Double);
  begin
    X := (S.X - V.OX) / V.Ppu * Sc;
    Y := -(S.Y - V.OY) / V.Ppu * Sc;
  end;

begin
  if U = usImperial then Sc := 12 else Sc := 1000;
  { only in three dimensions: a flat view is already framed on its own
    middle by the projection it came through }
  Mid := P3(0, 0, 0);
  if ThreeD and AtOrigin and Bounds(BLo, BHi) then
    Mid := P3((BLo.X + BHi.X) / 2, (BLo.Y + BHi.Y) / 2, (BLo.Z + BHi.Z) / 2);
  W := TDxfWriter.Create;
  try
    W.Layer('GEOMETRY', 7);
    W.Layer('FACES', 8);
    W.Layer('DIMENSIONS', 3);
    W.Layer('NOTES', 2);
    W.Layer('GUIDES', 9, True);

    for I := 0 to FLive - 1 do
      case FEnts[I].Kind of
        ekLine:
          Seg('GEOMETRY', FEnts[I].A, FEnts[I].B);
        ekArc:
          begin
            { An arc goes out as short lines: a DXF ARC needs its own
              extrusion direction, and every CAD reads a chain of lines the
              same way. }
            if FEnts[I].Sides >= 3 then Steps := FEnts[I].Sides
            else Steps := Max(12, Round(Abs(FEnts[I].Sweep) * FEnts[I].R * 24));
            Steps := Min(Steps, 360);
            for K := 0 to Steps - 1 do
              Seg('GEOMETRY',
                ArcPoint(FEnts[I].C, FEnts[I].R,
                  FEnts[I].A0 + FEnts[I].Sweep * K / Steps, FEnts[I].Plane, FEnts[I].Nm),
                ArcPoint(FEnts[I].C, FEnts[I].R,
                  FEnts[I].A0 + FEnts[I].Sweep * (K + 1) / Steps, FEnts[I].Plane, FEnts[I].Nm));
          end;
        ekFace:
          if ThreeD then
          begin
            { the model's faces, for handing over the thing itself; flat, the
              outline is already there as lines }
            N := Length(FEnts[I].Poly);
            SetLength(XS, N); SetLength(YS, N); SetLength(ZS, N);
            for K := 0 to N - 1 do At(FEnts[I].Poly[K], XS[K], YS[K], ZS[K]);
            W.Face3D('FACES', XS, YS, ZS);
          end;
        ekGuide:
          if Dist(FEnts[I].A, FEnts[I].B) > 1E-9 then
            Seg('GUIDES', FEnts[I].A, FEnts[I].B);
        ekText:
          begin
            At(FEnts[I].A, TX, TY, TZ);
            W.Text('NOTES', TX, TY, TZ, 0.25 * Sc * NoteSize(I), FEnts[I].Txt);
          end;
        ekDim:
          if not ThreeD then
            if DimGeometry(V, FEnts[I].A, FEnts[I].B, FEnts[I].C, U, G, FEnts[I].Txt) then
            begin
              { the drawn dimension - line, witness lines and figure - as it
                sits on this view }
              Flat(G.A, AX1, AY1);  Flat(G.W1, BX1, BY1);
              W.Line('DIMENSIONS', AX1, AY1, 0, BX1, BY1, 0);
              Flat(G.B, AX1, AY1);  Flat(G.W2, BX1, BY1);
              W.Line('DIMENSIONS', AX1, AY1, 0, BX1, BY1, 0);
              Flat(G.LA, AX1, AY1); Flat(G.LB, BX1, BY1);
              W.Line('DIMENSIONS', AX1, AY1, 0, BX1, BY1, 0);
              Flat(G.Mid, AX1, AY1);
              W.Text('DIMENSIONS', AX1, AY1 + 0.1 * Sc, 0, 0.25 * Sc, G.Txt);
            end;
      end;
    W.SaveTo(L, U = usImperial);
  finally
    W.Free;
  end;
end;

{ Both formats consume these same projected entities, in the same order.
  Like SVG, this exports geometry rather than the screen's hidden-line pass. }
procedure TWorkDoc.WriteVectors(Writer: TVectorWriter; const V: TProjector;
  U: TUnitSystem; EdgeW: Single);
var
  I, K, H, Steps: Integer;
  Loops: TVectorLoops;
  PA, PB: TPointF;
  Ang: Double;
  LabelText: string;
begin
  for I := 0 to FLive - 1 do
  begin
    Loops := nil;
    case FEnts[I].Kind of
      ekFace:
        begin
          SetLength(Loops, 1 + Length(FEnts[I].Holes));
          SetLength(Loops[0], Length(FEnts[I].Poly));
          for K := 0 to High(FEnts[I].Poly) do
            Loops[0][K] := Project(V, FEnts[I].Poly[K]);
          for H := 0 to High(FEnts[I].Holes) do
          begin
            SetLength(Loops[H + 1], Length(FEnts[I].Holes[H]));
            for K := 0 to High(FEnts[I].Holes[H]) do
              Loops[H + 1][K] := Project(V, FEnts[I].Holes[H][K]);
          end;
          Writer.Path(Loops, FEnts[I].Ink, 1, True);
        end;
      ekArc:
        begin
          if FEnts[I].Sides >= 3 then Steps := FEnts[I].Sides else Steps := 64;
          SetLength(Loops, 1);
          SetLength(Loops[0], Steps + 1);
          for K := 0 to Steps do
          begin
            Ang := FEnts[I].A0 + FEnts[I].Sweep * K / Steps;
            Loops[0][K] := Project(V, ArcPoint(FEnts[I].C, FEnts[I].R,
              Ang, FEnts[I].Plane, FEnts[I].Nm));
          end;
          Writer.Path(Loops, FEnts[I].Ink, EdgeW, False);
        end;
      ekText:
        begin
          PA := Project(V, FEnts[I].A);
          PA.X := PA.X + 5; PA.Y := PA.Y - 4;
          Writer.Text(PA, FEnts[I].Txt, FEnts[I].Ink, 12, False);
        end;
      ekLine, ekDim:
        begin
          PA := Project(V, FEnts[I].A);
          PB := Project(V, FEnts[I].B);
          SetLength(Loops, 1);
          SetLength(Loops[0], 2);
          Loops[0][0] := PA; Loops[0][1] := PB;
          Writer.Path(Loops, FEnts[I].Ink, EdgeW, False);
          if FEnts[I].Dim then
          begin
            LabelText := FEnts[I].Txt;
            if LabelText = '' then LabelText := FormatLen(Dist(FEnts[I].A, FEnts[I].B), U);
            PA.X := (PA.X + PB.X) / 2;
            PA.Y := (PA.Y + PB.Y) / 2 - 6;
            Writer.Text(PA, LabelText, FEnts[I].Ink, 11, True);
          end;
        end;
    end;
  end;
end;

{ SVG export - real vectors, so it opens in Inkscape or CAD at the size it
  prints. }
procedure TWorkDoc.WriteSVG(L: TStrings; const V: TProjector; U: TUnitSystem;
  EdgeW: Single);
var
  I, K: Integer;
  Writer: TSVGWriter;
  MinX, MinY, MaxX, MaxY: Double;
  PW, PH, WUnit: Double;
  Un: string;

  procedure Grow(const P: TPointF);
  begin
    MinX := Min(MinX, P.X); MinY := Min(MinY, P.Y);
    MaxX := Max(MaxX, P.X); MaxY := Max(MaxY, P.Y);
  end;


begin
  MinX := 1E30; MinY := 1E30; MaxX := -1E30; MaxY := -1E30;
  for I := 0 to FLive - 1 do
    for K := 0 to 1 do
      if K = 0 then Grow(Project(V, FEnts[I].A)) else Grow(Project(V, FEnts[I].B));
  if MinX > MaxX then
  begin
    MinX := 0; MinY := 0; MaxX := 100; MaxY := 100;
  end;
  MinX := MinX - 30; MinY := MinY - 30; MaxX := MaxX + 30; MaxY := MaxY + 30;

  { The real size, written down.  The viewBox stays in screen pixels and
    width and height give the size in real units: Ppu is pixels per foot, so
    the picture is (MaxX - MinX) / Ppu feet across.  That is the size of this
    view - of the thing itself when seen square-on. }
  if V.Ppu > 1E-9 then WUnit := V.Ppu else WUnit := 1;
  if U = usImperial then
  begin
    PW := (MaxX - MinX) / WUnit * 12;      { feet to inches }
    PH := (MaxY - MinY) / WUnit * 12;
    Un := 'in';
  end
  else
  begin
    PW := (MaxX - MinX) / WUnit * 304.8;   { feet to millimeters }
    PH := (MaxY - MinY) / WUnit * 304.8;
    Un := 'mm';
  end;

  L.Add('<?xml version="1.0" encoding="UTF-8"?>');
  L.Add(Format('<svg xmlns="http://www.w3.org/2000/svg" ' +
    'width="%.3f%s" height="%.3f%s" viewBox="%.2f %.2f %.2f %.2f">',
    [PW, Un, PH, Un, MinX, MinY, MaxX - MinX, MaxY - MinY], DotFS));

  Writer := TSVGWriter.Create(L);
  try
    WriteVectors(Writer, V, U, EdgeW);
  finally
    Writer.Free;
  end;
  L.Add('</svg>');
end;

{ A key for an edge that both ends agree on: each end rounded to a millionth
  and packed as six whole numbers, smaller end first, so an edge walked
  either way is the same key.  Raw bytes, because Format here cost a quarter
  of a frame. }
function EdgeKey(const A, B: TP3): string;
var
  P, Q: array[0..2] of Int64;
  Swap: Boolean;
  I: Integer;
begin
  P[0] := Round(A.X * 1E6); P[1] := Round(A.Y * 1E6); P[2] := Round(A.Z * 1E6);
  Q[0] := Round(B.X * 1E6); Q[1] := Round(B.Y * 1E6); Q[2] := Round(B.Z * 1E6);
  Swap := False;
  for I := 0 to 2 do
    if P[I] <> Q[I] then
    begin
      Swap := P[I] > Q[I];
      Break;
    end;
  SetLength(Result, 48);
  if Swap then
  begin
    Move(Q[0], Result[1], 24);
    Move(P[0], Result[25], 24);
  end
  else
  begin
    Move(P[0], Result[1], 24);
    Move(Q[0], Result[25], 24);
  end;
end;

{ Faces farthest first by depth, with faces level to within rounding
  ordered bigger first, so a small face on a big one lands on top of it. }
procedure SortFaces(var Order: array of Integer; var Depth, Area: array of Double; N: Integer);
var
  TmpO: array of Integer;
  TmpD, TmpA: array of Double;
  I, J, K, RunEnd: Integer;
  Sh: Double;

  procedure Merge(Lo, Mid, Hi: Integer);
  var
    A, B, C: Integer;
  begin
    A := Lo; B := Mid; C := Lo;
    while (A < Mid) and (B < Hi) do
    begin
      if Depth[B] > Depth[A] then
      begin
        TmpO[C] := Order[B]; TmpD[C] := Depth[B]; TmpA[C] := Area[B]; Inc(B);
      end
      else
      begin
        TmpO[C] := Order[A]; TmpD[C] := Depth[A]; TmpA[C] := Area[A]; Inc(A);
      end;
      Inc(C);
    end;
    while A < Mid do begin TmpO[C] := Order[A]; TmpD[C] := Depth[A]; TmpA[C] := Area[A]; Inc(A); Inc(C); end;
    while B < Hi do begin TmpO[C] := Order[B]; TmpD[C] := Depth[B]; TmpA[C] := Area[B]; Inc(B); Inc(C); end;
    for C := Lo to Hi - 1 do
    begin
      Order[C] := TmpO[C]; Depth[C] := TmpD[C]; Area[C] := TmpA[C];
    end;
  end;

  procedure Sort(Lo, Hi: Integer);
  var
    Mid: Integer;
  begin
    if Hi - Lo < 2 then Exit;
    Mid := (Lo + Hi) div 2;
    Sort(Lo, Mid);
    Sort(Mid, Hi);
    Merge(Lo, Mid, Hi);
  end;

begin
  if N < 2 then Exit;
  SetLength(TmpO, N); SetLength(TmpD, N); SetLength(TmpA, N);
  Sort(0, N);
  { within a run of level faces, bigger first: the runs are short, so an
    insertion sort inside each is the right tool }
  I := 0;
  while I < N do
  begin
    RunEnd := I;
    while (RunEnd + 1 < N) and (Abs(Depth[RunEnd + 1] - Depth[I]) <= 1E-4 * (1 + Abs(Depth[I]))) do
      Inc(RunEnd);
    for J := I + 1 to RunEnd do
    begin
      K := Order[J]; Sh := Depth[J];
      { area is the key; depth rides along }
      TmpD[0] := Area[J];
      TmpO[0] := J - 1;
      while (TmpO[0] >= I) and (Area[TmpO[0]] < TmpD[0]) do
      begin
        Order[TmpO[0] + 1] := Order[TmpO[0]]; Depth[TmpO[0] + 1] := Depth[TmpO[0]]; Area[TmpO[0] + 1] := Area[TmpO[0]];
        Dec(TmpO[0]);
      end;
      Order[TmpO[0] + 1] := K; Depth[TmpO[0] + 1] := Sh; Area[TmpO[0] + 1] := TmpD[0];
    end;
    I := RunEnd + 1;
  end;
end;

procedure TWorkDoc.Render(S: TArtSurface; const V: TProjector;
  U: TUnitSystem; AFont: TFont; const LabelCol: TPix; EdgeW: Single;
  Half: TArtSurface; Phase: TRenderPhase);
var
  VH: TProjector;
  LSteps, Bisect: Integer;
  DG: TDimGeom;
  DA, DB: TP3;
  DSz: TSize;
  DTP: TPoint;
  Cand, AllFaces: TIntArrayW;
  OnFaceOK: Boolean;
  SlotOf: array of Integer;
  JJ: Integer;
  PlaneN: array of TP3;
  PlaneD: array of Double;
  PT: QWord;
  ZA, ZB, ZC, ZD1, ZD2, ZD3, ZDet, ZD, ZBest, ZDen: Double;
  Sxx, Sxy, Syy, Sx, Sy, Sn, Sdx, Sdy, Sd: Double;
  ZI2, ZI3, ZJ: Integer;
  { cutting a face that is not flat into triangles, so its depth is exact }
  TriPts: array of TPointF;
  TriZ: array of Double;
  Tris: TTriList;
  TriRing: TIndexRing;
  TriHoles: TIndexRings;
  Mesh: TDepthTris;
  TriDev, TriSize, TriDet, TDx, TDy: Double;
  MN, MI: Integer;
  ZOK, Drew: Boolean;  I, J, K, N, Steps, NFace: Integer;
  PA, PB: TPointF;
  Ang, Sh: Double;
  Col, Face: TPix;
  Look, Lamp, Cen, Nm: TP3;
  Order: array of Integer;
  Depth, Area: array of Double;
  Ar: Double;
  Flat: array of TPointF;
  Loops: array of TPtFLoop;
  EdgeIx: TFPHashList;
  EK: string;
  HK, HJ: Integer;
  GuideCol: TPix;
  M, Run0: Integer;
  T0, T1: Double;

  { the stretch being tested for cover: a line's two ends, or an arc }
  CurA, CurB: TP3;
  CurArc: Integer;
  RunT0, RunT1: Double;
  Vis: Boolean;

  { Is this point hidden behind something?  One lookup in the depth buffer
    the faces have already written.  A point on its own surface reads its own
    depth back, so the tolerance must be loose enough to call that visible. }
  function Covered(const P: TP3; Slot: Integer): Boolean;
  var
    SP: TPointF;
    D, Zb, Zx, Zy, Grad: Double;
  begin
    Result := False;
    if not S.DepthOn then Exit;
    SP := Project(V, P);
    Zb := S.DepthAt(Round(SP.X), Round(SP.Y));
    if Zb < -1E29 then Exit;             { nothing was drawn there }
    D := Dot3(P, Look);

    { How much depth changes across one pixel here.  The buffer is sampled at
      pixel centers, so a line on its own face seen edge-on can lose to it by
      a hair; the tolerance follows the local slope.  A neighbor off the face
      is swapped for the other side, and failing both a 45 degree slope is
      assumed rather than none. }
    Zx := S.DepthAt(Round(SP.X) + 1, Round(SP.Y));
    if Zx < -1E29 then Zx := S.DepthAt(Round(SP.X) - 1, Round(SP.Y));
    Zy := S.DepthAt(Round(SP.X), Round(SP.Y) + 1);
    if Zy < -1E29 then Zy := S.DepthAt(Round(SP.X), Round(SP.Y) - 1);
    { half a step in each direction, since the point can be half a pixel
      from the center both ways at once }
    Grad := 0;
    if Zx > -1E29 then Grad := Grad + 0.5 * Abs(Zx - Zb) else Grad := Grad + 0.5 / Max(1E-9, V.Ppu);
    if Zy > -1E29 then Grad := Grad + 0.5 * Abs(Zy - Zb) else Grad := Grad + 0.5 / Max(1E-9, V.Ppu);

    { Half a step, not a whole one: a whole step let a line behind a nearly
      edge-on face bleed past its edge.  Capped at about an eighty degree
      tilt; steeper, the face is its own silhouette. }

    Grad := Min(Grad, 6 / Max(1E-9, V.Ppu));

    { The last terms cover the single-precision buffer, which far from the
      origin is only good to a few ten-thousandths.  Kept small, or a crease
      behind a wall shows past its corner. }
    Result := Zb > D + Grad + 2E-4 * (1 + Abs(D)) + 0.02 / Max(1E-9, V.Ppu);
  end;

  { the point at T along the stretch being tested }
  function PtAt(T: Double): TP3;
  begin
    if CurArc >= 0 then
      Result := ArcPoint(FEnts[CurArc].C, FEnts[CurArc].R,
        FEnts[CurArc].A0 + FEnts[CurArc].Sweep * T, FEnts[CurArc].Plane, FEnts[CurArc].Nm)
    else
      Result := Lerp3(CurA, CurB, T);
  end;

  { Where along a stretch the cover begins: TVis is seen and TCov is not, as
    fractions of the stretch.  Bisected, so a visible run does not end a
    whole sample past the face that hides it. }
  function Boundary(TVis, TCov: Double; Slot: Integer): Double;
  var
    N: Integer;
    TM: Double;
  begin
    for N := 1 to Bisect do
    begin
      TM := (TVis + TCov) / 2;
      if Covered(PtAt(TM), Slot) then TCov := TM else TVis := TM;
    end;
    Result := (TVis + TCov) / 2;
  end;

  { A note: a box of text up and to the right of its anchor, with a leader
    out to Target.  Target = At means no leader - a plain label. }
  procedure Note(Which: Integer; const At, Target: TP3; const Txt: string;
    const Col: TPix);
  const
    PADX = 5;
    PADY = 3;
  var
    Lines: TStringList;
    PA, PB: TPointF;
    LH, W, H, BX, BY, K, WasH: Integer;
    AX, AY: Double;
    Sz: TSize;
  begin
    if Txt = '' then Exit;
    PA := Project(V, At);
    PB := Project(V, Target);

    { the font is shared with every other label on the drawing, so its size
      is changed for this note and put back afterwards }
    WasH := AFont.Height;
    if (Which >= 0) and (Which < FLive) and (FEnts[Which].Size > 0) and
       (Abs(FEnts[Which].Size - 1) > 1E-6) then
      AFont.Height := Round(WasH * FEnts[Which].Size);

    Lines := TStringList.Create;
    try
      Lines.Text := Txt;
      if Lines.Count = 0 then Lines.Add(Txt);
      LH := S.TextExtent('Xg', AFont).cy;
      W := 0;
      for K := 0 to Lines.Count - 1 do
      begin
        Sz := S.TextExtent(Lines[K], AFont);
        if Sz.cx > W then W := Sz.cx;
      end;
      H := Lines.Count * LH;

      { the box sits up and to the right of its anchor, the way a note
        written on a drawing sits beside the thing it is about }
      BX := Round(PA.X) + 5;
      BY := Round(PA.Y) - H - 2 * PADY - 3;

      if (Which >= 0) and (Which < FLive) then
      begin
        FEnts[Which].BoxL := BX;
        FEnts[Which].BoxT := BY;
        FEnts[Which].BoxR := BX + W + 2 * PADX;
        FEnts[Which].BoxB := BY + H + 2 * PADY;
      end;
      S.FillRect(Rect(BX, BY, BX + W + 2 * PADX, BY + H + 2 * PADY),
        Pix(255, 255, 255), 0.82);
      S.Poly([PtF(BX, BY), PtF(BX + W + 2 * PADX, BY),
              PtF(BX + W + 2 * PADX, BY + H + 2 * PADY),
              PtF(BX, BY + H + 2 * PADY)], 1.0, Col, True, 0.75);
      for K := 0 to Lines.Count - 1 do
        S.TextOut(BX + PADX, BY + PADY + K * LH, Lines[K], AFont, Col);

      { the leader, from the corner of the box nearest the target }
      if Dist(At, Target) > 1E-9 then
      begin
        AX := BX;
        if PB.X > BX + W then AX := BX + W + 2 * PADX;
        AY := BY + H + 2 * PADY;
        if PB.Y < BY then AY := BY;
        S.Line(AX, AY, PA.X, PA.Y, 1.0, Col, 0.8);
        S.Line(PA.X, PA.Y, PB.X, PB.Y, 1.0, Col, 0.8);
        S.Disc(PB.X, PB.Y, 2.4, Col, 0.95);
      end
      else
        S.Disc(PA.X, PA.Y, 2.2, Col, 0.9);
    finally
      Lines.Free;
      AFont.Height := WasH;
    end;
  end;

  { A dimension line parallel to the projected segment, always labeled with
    the true 3D length - which is what makes an isometric readable. }
  procedure Dimension(const A, B, Off: TP3; const Note: string);
  var
    G: TDimGeom;
    Sz: TSize;
    TP: TPoint;
  begin
    if not DimGeometry(V, A, B, Off, U, G, Note) then Exit;
    S.Line(G.A.X, G.A.Y, G.W1.X, G.W1.Y, 1.0, LabelCol, 0.5);
    S.Line(G.B.X, G.B.Y, G.W2.X, G.W2.Y, 1.0, LabelCol, 0.5);
    S.Line(G.LA.X, G.LA.Y, G.LB.X, G.LB.Y, 1.2, LabelCol, 0.85);
    S.Line(G.S1A.X, G.S1A.Y, G.S1B.X, G.S1B.Y, 1.4, LabelCol, 0.9);
    S.Line(G.S2A.X, G.S2A.Y, G.S2B.X, G.S2B.Y, 1.4, LabelCol, 0.9);
    Sz := S.TextExtent(G.Txt, AFont);
    TP := DimTextTopLeft(G, Sz.cx, Sz.cy);
    S.TextOut(TP.X, TP.Y, G.Txt, AFont, LabelCol);
  end;

  { SketchUp's Profiles: an edge is on the outline, and drawn heavier, when
    only one visible face runs along it.  The count comes from an index built
    once per render; counting per line against every face made orbiting
    sluggish.  A face turned away does not count. }
  function EdgeFaces(const A, B: TP3): Integer;
  var
    Ix: Integer;
  begin
    Ix := EdgeIx.FindIndexOf(EdgeKey(A, B));
    if Ix < 0 then Result := 0 else Result := PtrInt(EdgeIx.Items[Ix]);
  end;

  { A soft crease shows only where it is the outline of the surface; anywhere
    else it is hidden, and the shading alone says the surface is curved. }
  function Hidden(Ent: Integer): Boolean;
  begin
    Result := FEnts[Ent].Soft and
      (EdgeFaces(FEnts[Ent].A, FEnts[Ent].B) <> 1);
  end;

  function LineW(Ent: Integer): Single;
  begin
    Result := EdgeW;
    { SketchUp draws profiles one pixel heavier than edges, not twice as
      heavy. }
    if EdgeFaces(FEnts[Ent].A, FEnts[Ent].B) = 1 then
      Result := EdgeW + Max(1, EdgeW * 0.35);
  end;

  { Wholly off screen, by a margin covering line width and anti-aliasing, so
    it is left out of the frame. }
  function OffScreen(const PA, PB: TPointF): Boolean;
  const
    M = 8;
  begin
    Result := ((PA.X < -M) and (PB.X < -M)) or ((PA.X > S.Width + M) and (PB.X > S.Width + M)) or
              ((PA.Y < -M) and (PB.Y < -M)) or ((PA.Y > S.Height + M) and (PB.Y > S.Height + M));
  end;

  function PolyOffScreen(const Poly: TP3Array): Boolean;
  const
    M = 8;
  var
    K: Integer;
    Q: TPointF;
    MinX, MaxX, MinY, MaxY: Double;
  begin
    MinX := 1E30; MaxX := -1E30; MinY := 1E30; MaxY := -1E30;
    for K := 0 to High(Poly) do
    begin
      Q := Project(V, Poly[K]);
      if Q.X < MinX then MinX := Q.X; if Q.X > MaxX then MaxX := Q.X;
      if Q.Y < MinY then MinY := Q.Y; if Q.Y > MaxY then MaxY := Q.Y;
    end;
    Result := (MaxX < -M) or (MinX > S.Width + M) or (MaxY < -M) or (MinY > S.Height + M);
  end;

  { The visible stretches of any world segment against face Slot, sampled
    like a line in the runs pass.  A dimension's three lines use it so the
    parts behind a wall do not show through. }
  procedure RunSeg(const WA, WB: TP3; W, Alpha: Single; const Col: TPix; Slot: Integer);
  var
    M, Run0: Integer;
    Vis: Boolean;
    RunT0, RunT1: Double;
    PA, PB: TPointF;
  begin
    Run0 := -1;
    RunT0 := 0;
    CurA := WA;
    CurB := WB;
    CurArc := -1;
    for M := 0 to LSteps do
    begin
      if M < LSteps then
        Vis := not Covered(Lerp3(WA, WB, (M + 0.5) / LSteps), Slot)
      else
        Vis := False;
      if Vis and (Run0 < 0) then
      begin
        Run0 := M;
        if M = 0 then RunT0 := 0
        else RunT0 := Boundary((M + 0.5) / LSteps, (M - 0.5) / LSteps, Slot);
      end;
      if (not Vis) and (Run0 >= 0) then
      begin
        if M = LSteps then RunT1 := 1
        else RunT1 := Boundary((M - 0.5) / LSteps, (M + 0.5) / LSteps, Slot);
        PA := Project(V, Lerp3(WA, WB, RunT0));
        PB := Project(V, Lerp3(WA, WB, RunT1));
        S.Line(PA.X, PA.Y, PB.X, PB.Y, W, Col, Alpha);
        Run0 := -1;
      end;
    end;
  end;

  procedure Mark(K: Integer);
  begin
    ProfMs[K] := ProfMs[K] + (GetTickCount64 - PT);
    PT := GetTickCount64;
  end;

begin
  { A half-resolution frame, while the camera moves.  The fill costs by the
    pixel and the lines do not, so edges and faces go into a half-size
    surface, are blown up two to one with their depth, and the lines on
    faces, guides and notes are drawn on top at full size.  Faces go soft
    while moving; lines stay crisp.  tools/inkprof measures it. }
  if (Half <> nil) and Quick and (Phase = rpAll) then
  begin
    Half.SetSize((S.Width + 1) div 2, (S.Height + 1) div 2);
    Half.ClearTransparent;
    Half.QuickFill := S.QuickFill;
    VH := V;
    VH.Ppu := V.Ppu / 2;
    VH.OX := V.OX / 2;
    VH.OY := V.OY / 2;
    Render(Half, VH, U, AFont, LabelCol, EdgeW, nil, rpFaces);
    S.ScaleUp2From(Half);
    Phase := rpLines;
  end;

  S.BlendMode := bmNormal;
  GuideCol := MixPix(LabelCol, Pix(120, 90, 190), 0.55);

  if Quick then
  begin
    LSteps := QuickSteps; if LSteps < 2 then LSteps := 8;
    Bisect := QuickBisect; if Bisect < 0 then Bisect := 1;
  end
  else begin LSteps := LINE_STEPS; Bisect := 6; end;
  PT := GetTickCount64;
  { the edge index, once, before anything asks it a question: a hash of edge
    keys to how many visible faces run along each }
  EdgeIx := TFPHashList.Create;
  try
    Look := ViewDir(V);
    for I := 0 to FLive - 1 do
    begin
      if FEnts[I].Kind <> ekFace then Continue;
      if not InSlice(I) then Continue;
      if FEnts[I].Solid and (Dot3(FaceNormal(I), Look) <= 0) then Continue;
      N := Length(FEnts[I].Poly);
      for J := 0 to N - 1 do
      begin
        EK := EdgeKey(FEnts[I].Poly[J], FEnts[I].Poly[(J + 1) mod N]);
        K := EdgeIx.FindIndexOf(EK);
        if K < 0 then EdgeIx.Add(EK, Pointer(PtrInt(1)))
        else EdgeIx.Items[K] := Pointer(PtrInt(EdgeIx.Items[K]) + 1);
      end;
    end;

  { the second half of a half-resolution frame has the edges already, blown
    up from the first half; it draws only what lies on faces }
  if Phase <> rpLines then
  for I := 0 to FLive - 1 do
  begin
    { out of the slice is out of the drawing, in every pass }
    if not InSlice(I) then Continue;
    Col := InkPix(I);
    case FEnts[I].Kind of
      ekFace: ;   // already painted
      ekLine:
        begin
          if Hidden(I) then Continue;
          PA := Project(V, FEnts[I].A);
          PB := Project(V, FEnts[I].B);
          if OffScreen(PA, PB) then Continue;
          S.Line(PA.X, PA.Y, PB.X, PB.Y, LineW(I), Col);
        end;

      ekArc:
        begin
          if FEnts[I].Soft then Continue;   { a seam of a spun or swept surface }
          if FEnts[I].Sides >= 3 then Steps := FEnts[I].Sides
          else Steps := Max(10, Round(Abs(FEnts[I].Sweep) * FEnts[I].R * V.Ppu / 4));
          Steps := Min(Steps, 1500);
          PA := Project(V, ArcPoint(FEnts[I].C, FEnts[I].R, FEnts[I].A0, FEnts[I].Plane, FEnts[I].Nm));
          for K := 1 to Steps do
          begin
            Ang := FEnts[I].A0 + FEnts[I].Sweep * K / Steps;
            PB := Project(V, ArcPoint(FEnts[I].C, FEnts[I].R, Ang, FEnts[I].Plane, FEnts[I].Nm));
            S.Line(PA.X, PA.Y, PB.X, PB.Y, EdgeW, Col);
            PA := PB;
          end;
        end;

      { Labels and dimensions go before the faces, so a solid in front hides
        them as in SketchUp.  Those lying on a face that faces us are put
        back after the face pass. }
      ekText:
        Note(I, FEnts[I].A, FEnts[I].B, FEnts[I].Txt, Col);
      ekDim:
        Dimension(FEnts[I].A, FEnts[I].B, FEnts[I].C, FEnts[I].Txt);

      { Dashed, and run out far enough each way to cross any view.  Drawn
        with the other annotation, so a solid in front hides it. }
      ekGuide:
        if not FGuidesHidden then
        begin
          PA := Project(V, FEnts[I].A);
          if Dist(FEnts[I].A, FEnts[I].B) < 1E-9 then
          begin
            { A guide point is drawn last, on top, amber and larger than the
              snap marks - see the last pass. }
          end
          else
          begin
            PB := Project(V, FEnts[I].B);
            Ang := Sqrt(Sqr(PB.X - PA.X) + Sqr(PB.Y - PA.Y));
            if Ang > 1E-6 then
            begin
              Sh := (S.Width + S.Height) * 1.5;
              PB := PtF((PB.X - PA.X) / Ang, (PB.Y - PA.Y) / Ang);
              K := 0;
              while K * 12 < Sh do
              begin
                S.Line(PA.X + PB.X * (K * 12 - Sh / 2),
                       PA.Y + PB.Y * (K * 12 - Sh / 2),
                       PA.X + PB.X * (K * 12 + 6 - Sh / 2),
                       PA.Y + PB.Y * (K * 12 + 6 - Sh / 2),
                       1.0, GuideCol, 0.85);
                Inc(K);
              end;
            end;
          end;
        end;
    end;
  end;


  Mark(0);
  { --- solid faces, drawn after the edges so they hide what is behind --- }
  NFace := 0;
  SetLength(Order, FLive);
  SetLength(Depth, FLive);
  SetLength(Area, FLive);
  Look := ViewDir(V);
  { The lamp rides on the camera, a little above it and to its left, so the
    face being looked at is the lit one and turning the model shows its
    shape.  The offset keeps the three faces of a box in iso from coming out
    the same tone. }
  if not CameraLamp then
    Lamp := Norm3(P3(0.35, -0.55, 0.75))
  else
  Lamp := Norm3(P3(
    Look.X + ViewUp(V).X * LAMP_UP - ViewRight(V).X * LAMP_LEFT,
    Look.Y + ViewUp(V).Y * LAMP_UP - ViewRight(V).Y * LAMP_LEFT,
    Look.Z + ViewUp(V).Z * LAMP_UP - ViewRight(V).Z * LAMP_LEFT));
  for I := 0 to FLive - 1 do
    if (FEnts[I].Kind = ekFace) and (Length(FEnts[I].Poly) >= 3) and
       InSlice(I) and
       not (FEnts[I].Solid and GroupClosed(FEnts[I].Grp) and
            (Dot3(FaceNormal(I), Look) <= 0)) then
    begin
      { Every face is drawn and the depth buffer decides what shows, so a
        window in a box shows the inside of the far wall.  The exception is
        the back of a closed solid: it can never be seen, and a warped face's
        fitted depth can let it paint over the near side in pale blue.  An
        open shell keeps its backs. }

      Cen := P3(0, 0, 0);
      for K := 0 to High(FEnts[I].Poly) do
      begin
        Cen.X := Cen.X + FEnts[I].Poly[K].X;
        Cen.Y := Cen.Y + FEnts[I].Poly[K].Y;
        Cen.Z := Cen.Z + FEnts[I].Poly[K].Z;
      end;
      K := Length(FEnts[I].Poly);
      Cen := P3(Cen.X / K, Cen.Y / K, Cen.Z / K);
      if PolyOffScreen(FEnts[I].Poly) then Continue;
      Order[NFace] := I;
      Depth[NFace] := Dot3(Cen, Look);
      Area[NFace] := FaceArea(I);
      Inc(NFace);
    end;

  Mark(1);
  { Farthest first; faces level to within rounding go bigger first, so a
    circle on a slab lands on top.  A merge sort, since insertion sort was
    most of a frame at five thousand faces. }
  SortFaces(Order, Depth, Area, NFace);

  { every face's plane, once, for the lines-on-faces pass }
  SetLength(PlaneN, NFace);
  SetLength(PlaneD, NFace);
  SetLength(SlotOf, FLive);
  for I := 0 to FLive - 1 do SlotOf[I] := -1;
  for I := 0 to NFace - 1 do
  begin
    PlaneN[I] := FaceNormal(Order[I]);
    PlaneD[I] := Dot3(PlaneN[I], FEnts[Order[I]].Poly[0]);
    SlotOf[Order[I]] := I;
  end;
  EnsureOnFace;
  OnFaceOK := OnFaceReady;
  if not OnFaceOK then
  begin
    SetLength(AllFaces, NFace);
    for I := 0 to NFace - 1 do AllFaces[I] := Order[I];
    Inc(OnFaceFallbacks);
  end;
  { and the faces likewise: painted in the first half, their depth blown
    up with them, so the second half must not begin a fresh depth pass }
  if Phase <> rpLines then S.DepthBegin;
  if Phase <> rpLines then
  for I := 0 to NFace - 1 do
  begin
    K := Order[I];
    SetLength(Flat, Length(FEnts[K].Poly));
    for J := 0 to High(FEnts[K].Poly) do
      Flat[J] := Project(V, FEnts[K].Poly[J]);
    Nm := FaceNormal(K);
    Col := InkPix(K);
    { A painted face shows its material at full strength; an unpainted one is
      the near-white default with a hint of the pen. }
    if FEnts[K].MatSet then
      Face := ColorToPix(FEnts[K].Mat)
    else
      Face := MixPix(Col, FACE_MATERIAL, 0.92);
    { The plane this face lies in, in screen terms: depth as a linear function
      of x and y, which is all a parallel projection gives. }
    ZOK := False;
    if Length(Flat) >= 3 then
    begin
      { Three corners that make a well-shaped triangle on screen: the one
        furthest from the first, then the one furthest from the line between
        them.  The first three of a long thin gore are nearly in line, and
        dividing by their area gives a nonsense depth plane. }
      ZI2 := 0;
      ZBest := 0;
      for ZJ := 1 to High(Flat) do
      begin
        ZD := Sqr(Flat[ZJ].X - Flat[0].X) + Sqr(Flat[ZJ].Y - Flat[0].Y);
        if ZD > ZBest then begin ZBest := ZD; ZI2 := ZJ; end;
      end;
      ZI3 := 0;
      ZBest := 0;
      if ZI2 > 0 then
        for ZJ := 1 to High(Flat) do
          if ZJ <> ZI2 then
          begin
            ZD := Abs((Flat[ZI2].X - Flat[0].X) * (Flat[ZJ].Y - Flat[0].Y) -
                      (Flat[ZJ].X - Flat[0].X) * (Flat[ZI2].Y - Flat[0].Y));
            if ZD > ZBest then begin ZBest := ZD; ZI3 := ZJ; end;
          end;
      { Then fit the plane through ALL the corners by least squares.  A warped
        quad from a revolve has no true plane, and three corners left the
        fourth hundreds of feet out in depth.  The three corners above are the
        fallback.  Kept alongside triangle cutting: it is exact for flat faces
        and covers slivers no triangle reaches. }
      if (ZI2 > 0) and (ZI3 > 0) then
      begin
        ZDet := (Flat[ZI2].X - Flat[0].X) * (Flat[ZI3].Y - Flat[0].Y) -
                (Flat[ZI3].X - Flat[0].X) * (Flat[ZI2].Y - Flat[0].Y);
        { a hundredth of a square pixel: below that the face really is
          edge-on and has no depth of its own worth solving }
        if Abs(ZDet) > 1E-2 then
        begin
          { the normal equations for depth = A*x + B*y + C }
          Sxx := 0; Sxy := 0; Syy := 0; Sx := 0; Sy := 0; Sn := 0;
          Sdx := 0; Sdy := 0; Sd := 0;
          for ZJ := 0 to High(Flat) do
          begin
            ZD := Dot3(FEnts[K].Poly[ZJ], Look);
            Sxx := Sxx + Flat[ZJ].X * Flat[ZJ].X;
            Sxy := Sxy + Flat[ZJ].X * Flat[ZJ].Y;
            Syy := Syy + Flat[ZJ].Y * Flat[ZJ].Y;
            Sx  := Sx  + Flat[ZJ].X;
            Sy  := Sy  + Flat[ZJ].Y;
            Sdx := Sdx + ZD * Flat[ZJ].X;
            Sdy := Sdy + ZD * Flat[ZJ].Y;
            Sd  := Sd  + ZD;
            Sn  := Sn  + 1;
          end;
          ZDen := Sxx * (Syy * Sn - Sy * Sy) - Sxy * (Sxy * Sn - Sy * Sx) +
                  Sx * (Sxy * Sy - Syy * Sx);
          if Abs(ZDen) > 1E-9 * (1 + Abs(Sxx) + Abs(Syy)) then
          begin
            ZA := (Sdx * (Syy * Sn - Sy * Sy) - Sxy * (Sdy * Sn - Sy * Sd) +
                   Sx * (Sdy * Sy - Syy * Sd)) / ZDen;
            ZB := (Sxx * (Sdy * Sn - Sd * Sy) - Sdx * (Sxy * Sn - Sy * Sx) +
                   Sx * (Sxy * Sd - Sdy * Sx)) / ZDen;
            ZC := (Sxx * (Syy * Sd - Sy * Sdy) - Sxy * (Sxy * Sd - Sdy * Sx) +
                   Sdx * (Sxy * Sy - Syy * Sx)) / ZDen;
            ZOK := True;
          end;
          if not ZOK then
          begin
            { three corners, the well-conditioned ones, as before }
            ZD1 := Dot3(FEnts[K].Poly[0], Look);
            ZD2 := Dot3(FEnts[K].Poly[ZI2], Look);
            ZD3 := Dot3(FEnts[K].Poly[ZI3], Look);
            ZA := ((ZD2 - ZD1) * (Flat[ZI3].Y - Flat[0].Y) -
                   (ZD3 - ZD1) * (Flat[ZI2].Y - Flat[0].Y)) / ZDet;
            ZB := ((ZD3 - ZD1) * (Flat[ZI2].X - Flat[0].X) -
                   (ZD2 - ZD1) * (Flat[ZI3].X - Flat[0].X)) / ZDet;
            ZC := ZD1 - ZA * Flat[0].X - ZB * Flat[0].Y;
            ZOK := True;
          end;
        end;
      end;
    end;
    if ZOK then S.DepthPlane(ZA, ZB, ZC)
    else S.DepthPlane(0, 0, -1E30);

    { Ambient plus lamp comes to more than one on purpose: a face square to
      the lamp burns out to the full material and ShadePix clips it.  The
      normal is taken on the eye's side, so a face seen from behind is lit as
      the surface being looked at. }
    if not CameraLamp then
      Sh := Min(1, 0.62 + 0.50 * Abs(Dot3(Nm, Lamp)))
    else if Dot3(Nm, Look) < 0 then
      Sh := LAMP_AMBIENT + LAMP_DIFFUSE * Max(0, -Dot3(Nm, Lamp))
    else
      Sh := LAMP_AMBIENT + LAMP_DIFFUSE * Max(0, Dot3(Nm, Lamp));
    { A plan is a drawing, not a photograph: no shading, so the lines carry
      the information. }
    if V.Kind = vkPlan then Sh := 1;
    { The outline and its holes go to the fill together, so a window is where
      the wall is not, and you can see through it. }
    SetLength(Loops, 1 + Length(FEnts[K].Holes));
    SetLength(Loops[0], Length(Flat));
    for HJ := 0 to High(Flat) do Loops[0][HJ] := Flat[HJ];
    for HK := 0 to High(FEnts[K].Holes) do
    begin
      SetLength(Loops[HK + 1], Length(FEnts[K].Holes[HK]));
      for HJ := 0 to High(FEnts[K].Holes[HK]) do
        Loops[HK + 1][HJ] := Project(V, FEnts[K].Holes[HK][HJ]);
    end;
    { --- an exact depth for a face that is not flat --------------------
          One plane is only a guess for a warped face, so cut it into
          triangles, each with exactly one plane.  The fill is still one call
          (see DepthMesh); this only sets each pixel's depth.  Flat faces
          skip it. }
    if ZOK and (Length(FEnts[K].Poly) > 3) then
    begin
      TriDev := 0;
      TriSize := 1;
      for ZJ := 1 to High(FEnts[K].Poly) do
      begin
        TDx := Abs(Nm.X * (FEnts[K].Poly[ZJ].X - FEnts[K].Poly[0].X) +
                   Nm.Y * (FEnts[K].Poly[ZJ].Y - FEnts[K].Poly[0].Y) +
                   Nm.Z * (FEnts[K].Poly[ZJ].Z - FEnts[K].Poly[0].Z));
        if TDx > TriDev then TriDev := TDx;
        TDy := Sqrt(Sqr(FEnts[K].Poly[ZJ].X - FEnts[K].Poly[0].X) +
                    Sqr(FEnts[K].Poly[ZJ].Y - FEnts[K].Poly[0].Y) +
                    Sqr(FEnts[K].Poly[ZJ].Z - FEnts[K].Poly[0].Z));
        if TDy > TriSize then TriSize := TDy;
      end;
      { a millionth of the face's own size out of flat is rounding, not warp }
      if TriDev > 1E-6 * TriSize then
      begin
        { Cut against what the camera shows, every frame.  Keeping a cut made
          in the face's own plane saved about one percent, and for a warped
          face it folded over a quarter of the time once projected.  FaceCut
          stays for STL, which is model-space by nature. }
        SetLength(TriRing, Length(Loops[0]));
        for HJ := 0 to High(Loops[0]) do TriRing[HJ] := HJ;
        SetLength(TriHoles, Length(Loops) - 1);
        MN := Length(Loops[0]);
        for HK := 0 to High(FEnts[K].Holes) do
        begin
          SetLength(TriHoles[HK], Length(FEnts[K].Holes[HK]));
          for HJ := 0 to High(FEnts[K].Holes[HK]) do
          begin
            TriHoles[HK][HJ] := MN;
            Inc(MN);
          end;
        end;

        SetLength(TriPts, MN);
        SetLength(TriZ, MN);
        MN := 0;
        for HJ := 0 to High(Loops[0]) do
        begin
          TriPts[MN] := Loops[0][HJ];
          TriZ[MN] := Dot3(FEnts[K].Poly[HJ], Look);
          Inc(MN);
        end;
        for HK := 0 to High(FEnts[K].Holes) do
          for HJ := 0 to High(FEnts[K].Holes[HK]) do
          begin
            TriPts[MN] := Loops[HK + 1][HJ];
            TriZ[MN] := Dot3(FEnts[K].Holes[HK][HJ], Look);
            Inc(MN);
          end;

        if Triangulate(TriPts, TriRing, TriHoles, Tris) then
        begin
          SetLength(Mesh, Length(Tris) div 3);
          MN := 0;
          for MI := 0 to (Length(Tris) div 3) - 1 do
          begin
            ZI2 := Tris[MI * 3];
            ZI3 := Tris[MI * 3 + 1];
            ZJ := Tris[MI * 3 + 2];
            if (ZI2 >= Length(TriPts)) or (ZI3 >= Length(TriPts)) or
               (ZJ >= Length(TriPts)) then Continue;
            TriDet := (Double(TriPts[ZI3].X) - TriPts[ZI2].X) *
                        (Double(TriPts[ZJ].Y) - TriPts[ZI2].Y) -
                      (Double(TriPts[ZJ].X) - TriPts[ZI2].X) *
                        (Double(TriPts[ZI3].Y) - TriPts[ZI2].Y);
            { a hundredth of a square pixel: below that it is an edge-on
              sliver with no depth of its own to give, and the fitted plane
              is left to cover the pixel or two it might have owned }
            if Abs(TriDet) < 1E-2 then Continue;
            Mesh[MN].AX := TriPts[ZI2].X;  Mesh[MN].AY := TriPts[ZI2].Y;
            Mesh[MN].BX := TriPts[ZI3].X;  Mesh[MN].BY := TriPts[ZI3].Y;
            Mesh[MN].CX := TriPts[ZJ].X;   Mesh[MN].CY := TriPts[ZJ].Y;
            Mesh[MN].ZA :=
              ((TriZ[ZI3] - TriZ[ZI2]) * (Double(TriPts[ZJ].Y) - TriPts[ZI2].Y) -
               (TriZ[ZJ] - TriZ[ZI2]) * (Double(TriPts[ZI3].Y) - TriPts[ZI2].Y)) / TriDet;
            Mesh[MN].ZB :=
              ((TriZ[ZJ] - TriZ[ZI2]) * (Double(TriPts[ZI3].X) - TriPts[ZI2].X) -
               (TriZ[ZI3] - TriZ[ZI2]) * (Double(TriPts[ZJ].X) - TriPts[ZI2].X)) / TriDet;
            Mesh[MN].ZC := TriZ[ZI2] - Mesh[MN].ZA * TriPts[ZI2].X -
                                       Mesh[MN].ZB * TriPts[ZI2].Y;
            Mesh[MN].ZLo := Min(TriZ[ZI2], Min(TriZ[ZI3], TriZ[ZJ]));
            Mesh[MN].ZHi := Max(TriZ[ZI2], Max(TriZ[ZI3], TriZ[ZJ]));
            Inc(MN);
          end;
          SetLength(Mesh, MN);
          if MN > 0 then S.DepthMesh(Mesh);
        end;
      end;
    end;

    { The back of a face gets its own color.  A closed solid never shows one,
      so this only appears on loose geometry, where being inside out
      matters. }
    if (Dot3(Nm, ViewDir(V)) < 0) and (V.Kind <> vkPlan) then
      S.FillLoops(Loops, DimIf(K, ShadePix(FACE_BACK, Sh)), 1.0)
    else if V.Kind = vkPlan then
      { Paler in plan so the fill does not compete with the lines, front and
        back alike.  A painted face still shows its paint. }
      if FEnts[K].MatSet then
        S.FillLoops(Loops, DimIf(K, Face), 1.0)
      else
        S.FillLoops(Loops, DimIf(K, MixPix(Face, Pix(255, 255, 255), 0.55)), 1.0)
    else
      S.FillLoops(Loops, DimIf(K, ShadePix(Face, Sh)), 1.0);
    { No outline: every boundary is a real edge and drawn as one, and
      stroking the polygon too doubled it. }
  end;

  { the first half of a half-resolution frame stops here; the rest is
    drawn at full size on the other surface }
  if Phase = rpFaces then Exit;

  Mark(2);
  { --- lines that live on a visible face -------------------------------
        The faces bury lines drawn ON them, so those are put back here: a
        line counts if both ends lie in the plane of a face that was drawn. }
  for I := 0 to FLive - 1 do
  begin
    if not (FEnts[I].Kind in [ekLine, ekArc, ekDim, ekText]) then Continue;
    if not InSlice(I) then Continue;
    { a softened crease that is not an outline stays hidden whatever face
      it lies on - said once here, not once per face }
    if (FEnts[I].Kind = ekLine) and Hidden(I) then Continue;
    if (FEnts[I].Kind in [ekLine, ekDim]) and
       OffScreen(Project(V, FEnts[I].A), Project(V, FEnts[I].B)) then Continue;
    { the faces this thing lies on, from the cache; every face while the
      cache is still being built on its worker }
    Drew := False;
    if OnFaceOK then Cand := FOnFace[I] else Cand := AllFaces;
    for JJ := 0 to High(Cand) do
    begin
      K := Cand[JJ];
      J := SlotOf[K];
      if J < 0 then Continue;
      Nm := PlaneN[J];
      Sh := PlaneD[J];
      if FEnts[I].Kind = ekArc then
      begin
        { an arc lies in a face when its middle and its rim do }
        if Abs(Dot3(Nm, FEnts[I].C) - Sh) >= 1E-6 then Continue;
        if Abs(Dot3(Nm, ArcPoint(FEnts[I].C, FEnts[I].R, FEnts[I].A0,
             FEnts[I].Plane, FEnts[I].Nm)) - Sh) >= 1E-6 then Continue;
      end
      else if (Abs(Dot3(Nm, FEnts[I].A) - Sh) >= 1E-6) or
              (Abs(Dot3(Nm, FEnts[I].B) - Sh) >= 1E-6) then Continue;
      Col := InkPix(I);
      case FEnts[I].Kind of
        ekLine:
          if Hidden(I) then
            { a softened crease stays hidden here too }
          else
          { Only the stretches nothing stands in front of, so a grid's lines
            do not run through towers pushed up out of it.  Consecutive
            visible pieces are drawn as one line, or the joins show as notches
            at heavy weights. }
          begin
          Run0 := -1;
          CurA := FEnts[I].A;
          CurB := FEnts[I].B;
          CurArc := -1;
          for M := 0 to LSteps do
          begin
            if M < LSteps then
            begin
              T0 := M / LSteps;
              T1 := (M + 1) / LSteps;
              Vis := not Covered(Lerp3(FEnts[I].A, FEnts[I].B,
                (T0 + T1) / 2), J);
            end
            else
              Vis := False;
            if Vis and (Run0 < 0) then
            begin
              Run0 := M;
              { the run starts where the cover ends, not at the sample }
              if M = 0 then RunT0 := 0
              else RunT0 := Boundary((M + 0.5) / LSteps, (M - 0.5) / LSteps, J);
            end;
            if (not Vis) and (Run0 >= 0) then
            begin
              if M = LSteps then RunT1 := 1
              else RunT1 := Boundary((M - 0.5) / LSteps, (M + 0.5) / LSteps, J);
              PA := Project(V, Lerp3(FEnts[I].A, FEnts[I].B, RunT0));
              PB := Project(V, Lerp3(FEnts[I].A, FEnts[I].B, RunT1));
              S.Line(PA.X, PA.Y, PB.X, PB.Y, LineW(I), Col);
              Run0 := -1;
            end;
          end;
          end;
        ekArc:
          { the same, walked round the curve, so a circle on the side of a
            box is not painted over by the box }
          begin
          if FEnts[I].Soft then Continue;   { a seam of a spun or swept surface }
            if FEnts[I].Sides >= 3 then Steps := FEnts[I].Sides
            else Steps := Max(24, Min(180, Round(Abs(FEnts[I].Sweep) * FEnts[I].R * V.Ppu / 6)));
            Run0 := -1;
            CurArc := I;
            for M := 0 to Steps do
            begin
              if M < Steps then
              begin
                Ang := FEnts[I].A0 + FEnts[I].Sweep * (M + 0.5) / Steps;
                Vis := not Covered(ArcPoint(FEnts[I].C, FEnts[I].R, Ang,
                  FEnts[I].Plane, FEnts[I].Nm), J);
              end
              else
                Vis := False;
              if Vis and (Run0 < 0) then
              begin
                Run0 := M;
                if M = 0 then RunT0 := 0
                else RunT0 := Boundary((M + 0.5) / Steps, (M - 0.5) / Steps, J);
              end;
              if (not Vis) and (Run0 >= 0) then
              begin
                if M = Steps then RunT1 := 1
                else RunT1 := Boundary((M - 0.5) / Steps, (M + 0.5) / Steps, J);
                { from the refined start, through the corners between, to
                  the refined end - a faceted circle keeps its corners }
                PA := Project(V, PtAt(RunT0));
                for K := 1 to Steps - 1 do
                  if (K / Steps > RunT0 + 1E-9) and (K / Steps < RunT1 - 1E-9) then
                  begin
                    PB := Project(V, PtAt(K / Steps));
                    S.Line(PA.X, PA.Y, PB.X, PB.Y, LineW(I), Col);
                    PA := PB;
                  end;
                PB := Project(V, PtAt(RunT1));
                S.Line(PA.X, PA.Y, PB.X, PB.Y, LineW(I), Col);
                Run0 := -1;
              end;
            end;
          end;
        ekDim:
          { like a line: the stretches of its three lines that nothing
            stands in front of, the ticks and the figure where their place
            is clear }
          if DimGeometry(V, FEnts[I].A, FEnts[I].B, FEnts[I].C, U, DG, FEnts[I].Txt) then
          begin
            DA := Add3(FEnts[I].A, FEnts[I].C);
            DB := Add3(FEnts[I].B, FEnts[I].C);
            RunSeg(FEnts[I].A, DA, 1.0, 0.5, LabelCol, J);
            RunSeg(FEnts[I].B, DB, 1.0, 0.5, LabelCol, J);
            RunSeg(DA, DB, 1.2, 0.85, LabelCol, J);
            if not Covered(DA, J) then
              S.Line(DG.S1A.X, DG.S1A.Y, DG.S1B.X, DG.S1B.Y, 1.4, LabelCol, 0.9);
            if not Covered(DB, J) then
              S.Line(DG.S2A.X, DG.S2A.Y, DG.S2B.X, DG.S2B.Y, 1.4, LabelCol, 0.9);
            if not Covered(Lerp3(DA, DB, 0.5), J) then
            begin
              DSz := S.TextExtent(DG.Txt, AFont);
              DTP := DimTextTopLeft(DG, DSz.cx, DSz.cy);
              S.TextOut(DTP.X, DTP.Y, DG.Txt, AFont, LabelCol);
            end;
          end;
        ekText:
          if not Covered(FEnts[I].A, J) then
            Note(I, FEnts[I].A, FEnts[I].B, FEnts[I].Txt, Col);
      end;
      Drew := True;
      Break;
    end;

    { --- and the ones that lie on no face at all ----------------------
      A line in mid air - a roof ridge - lies in no face's plane, so the
      faces painted over it.  Draw it through the depth buffer, which knows
      per pixel which parts are really behind something. }
    if not Drew then
    begin
      S.DepthTest(True);
      case FEnts[I].Kind of
        ekLine:
          begin
            PA := Project(V, FEnts[I].A);
            PB := Project(V, FEnts[I].B);
            S.DepthAlong(PA.X, PA.Y, Dot3(FEnts[I].A, Look),
                         PB.X, PB.Y, Dot3(FEnts[I].B, Look));
            S.Line(PA.X, PA.Y, PB.X, PB.Y, LineW(I), InkPix(I));
          end;
        ekArc:
          if not FEnts[I].Soft then
          begin
            if FEnts[I].Sides >= 3 then Steps := FEnts[I].Sides
            else Steps := Max(24, Min(180,
              Round(Abs(FEnts[I].Sweep) * FEnts[I].R * V.Ppu / 6)));
            DA := ArcPoint(FEnts[I].C, FEnts[I].R, FEnts[I].A0,
                           FEnts[I].Plane, FEnts[I].Nm);
            PA := Project(V, DA);
            for K := 1 to Steps do
            begin
              DB := ArcPoint(FEnts[I].C, FEnts[I].R,
                FEnts[I].A0 + FEnts[I].Sweep * K / Steps,
                FEnts[I].Plane, FEnts[I].Nm);
              PB := Project(V, DB);
              S.DepthAlong(PA.X, PA.Y, Dot3(DA, Look),
                           PB.X, PB.Y, Dot3(DB, Look));
              S.Line(PA.X, PA.Y, PB.X, PB.Y, LineW(I), InkPix(I));
              PA := PB;
              DA := DB;
            end;
          end;
      end;
      S.DepthTest(False);
    end;
  end;

  { --- and what a plan cannot see, dashed ------------------------------
    A drawing shows what is underneath: a beam over a door, a footing under
    a wall.  Plan only - in 3D it would lay the far side of every box over
    the near side.  The depth test is turned round so only the hidden
    stretches are drawn, faint. }
  if (V.Kind = vkPlan) and S.DepthOn then
  begin
    S.DepthTest(True);
    S.DepthBehind(True);
    for I := 0 to FLive - 1 do
    begin
      if not InSlice(I) then Continue;
      case FEnts[I].Kind of
        ekLine:
          begin
            if Hidden(I) then Continue;
            PA := Project(V, FEnts[I].A);
            PB := Project(V, FEnts[I].B);
            if OffScreen(PA, PB) then Continue;
            S.DepthAlong(PA.X, PA.Y, Dot3(FEnts[I].A, Look),
                         PB.X, PB.Y, Dot3(FEnts[I].B, Look));
            S.Line(PA.X, PA.Y, PB.X, PB.Y, LineW(I),
                   MixPix(InkPix(I), Pix(255, 255, 255), 0.45));
          end;
        ekArc:
          begin
            if FEnts[I].Soft then Continue;
            if FEnts[I].Sides >= 3 then Steps := FEnts[I].Sides
            else Steps := Max(24, Min(180,
              Round(Abs(FEnts[I].Sweep) * FEnts[I].R * V.Ppu / 6)));
            DA := ArcPoint(FEnts[I].C, FEnts[I].R, FEnts[I].A0,
                           FEnts[I].Plane, FEnts[I].Nm);
            PA := Project(V, DA);
            for K := 1 to Steps do
            begin
              DB := ArcPoint(FEnts[I].C, FEnts[I].R,
                FEnts[I].A0 + FEnts[I].Sweep * K / Steps,
                FEnts[I].Plane, FEnts[I].Nm);
              PB := Project(V, DB);
              S.DepthAlong(PA.X, PA.Y, Dot3(DA, Look),
                           PB.X, PB.Y, Dot3(DB, Look));
              S.Line(PA.X, PA.Y, PB.X, PB.Y, LineW(I),
                     MixPix(InkPix(I), Pix(255, 255, 255), 0.45));
              PA := PB;
              DA := DB;
            end;
          end;
      end;
    end;
    S.DepthBehind(False);
    S.DepthTest(False);
  end;

  if not OnFaceOK then OnFaceFallbackMs := GetTickCount64 - PT;
  Mark(3);
  { --- guide points, last of all ---------------------------------------
    A guide point is no use buried under the panel it was placed on, so it
    is drawn on top - unless something really is in front of it. }
  for I := 0 to FLive - 1 do
    if (FEnts[I].Kind = ekGuide) and not FGuidesHidden and
       (Dist(FEnts[I].A, FEnts[I].B) < 1E-9) then
    begin
      if Covered(FEnts[I].A, -1) then Continue;
      PA := Project(V, FEnts[I].A);
      S.Disc(PA.X, PA.Y, 4.5, Pix(20, 20, 24), 0.55);
      S.Disc(PA.X, PA.Y, 3.4, GUIDE_POINT, 1.0);
      S.Line(PA.X - 8, PA.Y, PA.X + 8, PA.Y, 1.4, GUIDE_POINT, 0.95);
      S.Line(PA.X, PA.Y - 8, PA.X, PA.Y + 8, 1.4, GUIDE_POINT, 0.95);
    end;
  finally
    EdgeIx.Free;
  end;
  Mark(4);
  LastSurf := S;
  LastV := V;
end;


initialization
  { see SurfaceGone: a borrowed depth buffer must not outlive the surface it
    belongs to }
  WatchSurfaceGone(@SurfaceGone);

end.

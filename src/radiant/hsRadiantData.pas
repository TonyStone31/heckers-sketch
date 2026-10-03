unit hsRadiantData;

{ What a hydronic radiant floor is built from, and the trade's numbers for it,
  from the tubing makers' install manuals and Radiant Professionals Alliance
  guidance. A starting point only; this unit does no heat loss calculation.

  Sourced figures:
  * Max loop length: 3/8" 200-250 ft, 1/2" 250-350 ft (300 is typical),
    5/8" 400-450 ft, 3/4" 500-600 ft. We use the low end of each band.
  * Min bend radius: 8x OD for PEX-B and PEX-C (PEX-A goes to 6x; we use 8x).
    3/8" (1/2" OD) 4", 1/2" (5/8" OD) 5", 5/8" (3/4" OD) 6", 3/4" (7/8" OD) 7".
  * On-center spacing: 6" to 12" for most residential slabs, 9" default.
  * Slab tube centered in the pour, about 2" deep at most. R-15 under a heated
    slab at least (R-10 to R-20 by climate), edges at twice the field R-value.

  Estimates, and the ticket says so: coil waste (10%) and tie/staple spacing.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE. }

{$mode objfpc}{$H+}

interface

type
  TTubeSize = (tsThreeEighth, tsHalf, tsFiveEighth, tsThreeQuarter);

  TTubeFacts = record
    Name: string;         { what the trade calls it - the nominal size }
    OdIn: Double;          { outer diameter, inches }
    MinBendIn: Double;     { the tightest a run can turn, inches - 8x OD }
    MaxLoopFt: Double;     { a safe everyday maximum circuit length, feet }
  end;

const
  TUBE_NAMES: array[TTubeSize] of string = ('3/8"  PEX', '1/2"  PEX', '5/8"  PEX', '3/4"  PEX');

  TUBE: array[TTubeSize] of TTubeFacts = (
    (Name: '3/8"'; OdIn: 0.500; MinBendIn: 4.0; MaxLoopFt: 200),
    (Name: '1/2"'; OdIn: 0.625; MinBendIn: 5.0; MaxLoopFt: 300),
    (Name: '5/8"'; OdIn: 0.750; MinBendIn: 6.0; MaxLoopFt: 400),
    (Name: '3/4"'; OdIn: 0.875; MinBendIn: 7.0; MaxLoopFt: 500)
  );

  { default spacing and the range outside of which we warn, inches }
  SPACING_DEFAULT_IN = 9.0;
  SPACING_MIN_IN = 4.0;
  SPACING_MAX_IN = 18.0;

  { how far runs stay off a wall or obstacle - a hand's width, so the tube
    never ends up under a sill plate or a column base }
  EDGE_INSET_IN = 6.0;

  { Evens a side's rows up at the far wall when the search is struggling
    (see RowPlan): the last row this much closer to the wall than the inset,
    then each far gap closed up by this share of the spacing. }
  EVEN_EDGE_IN = 1.0;
  EVEN_GAP_SHARE = 1 / 12;
  { the search also tries it on a layout that meets its goals, while this
    much of the floor or less is covered }
  EVEN_TRY_BELOW = 0.99;
  { but not on a try covering this much less than the best seen }
  EVEN_TWIN_WITHIN = 0.1;

  { coil waste: cutting losses and the spool end too short for one more run.
    A trade rule, not measured. }
  WASTE_PCT_DEFAULT = 10.0;

  { slab defaults }
  SLAB_THICK_DEFAULT_IN = 4.0;
  SLAB_UNDER_R_DEFAULT = 15.0;

  { tie/staple spacing along a run - trade practice, not a printed spec }
  TIE_SPACING_IN = 15.0;

  { Manifolds are sold with 2 to 12 ports (MrPEX, Uponor, SharkBite, PEXworx
    all stop at 12). The job's own limit is TRadiantSpec.MaxPorts.
    LOOP_AREA_FACTOR is the share of a loop's max length left to cover floor
    after turns and leads. 0.7 comes within one loop of what gets laid;
    0.85 guessed four where six were needed. }
  MANIFOLD_PORTS_MIN = 2;
  MANIFOLD_PORTS_MAX = 12;
  { cost of each loop over the manifold's port limit, in loops (hsRadiant,
    LayManifold) - big enough that any layout within the limit wins }
  OVER_PORTS_COST = 100.0;
  { spacing of the connections along a manifold. The first foot out of the
    manifold is the only place tube may leave the grid, so each stub can
    take its own height and be followed by eye. }
  MANIFOLD_PORT_PITCH_IN = 2.0;
  { wall space a manifold needs past its connections for the ball valves,
    end caps and air vent. A rule of thumb for the ticket, not a maker's figure. }
  MANIFOLD_ENDS_IN = 12.0;
  { how far out from the manifold tube may run closer than the spacing -
    the fan from the ports onto the grid. About a foot. }
  MANIFOLD_FAN_IN = 13.0;
  { how far around a manifold tubes may run closer than the spacing (down to
    the port pitch) before they all have to be out on the grid }
  MANIFOLD_BREAKOUT_FT = 4.0;
  { a manifold dragged this close to a flat wall on the wizard's plan turns
    to lie along it - feet, or pixels when the plan is drawn small }
  MANIFOLD_SNAP_FT = 1.5;
  MANIFOLD_SNAP_PX = 10;
  { how much of the floor a breakout must cover to be kept; short of it, the
    next one two feet wider is tried. Set just under what a 6 ft breakout
    covers on a typical floor, since a closer breakout and a smaller
    manifold are worth a couple of percent. }
  BREAKOUT_COVER = 0.93;
  { how many breakouts the search climbs through, 2 ft apart starting at
    MANIFOLD_BREAKOUT_FT. Each is tried only when the one before fell short. }
  BREAKOUT_LEVELS = 5;
  LOOP_AREA_FACTOR = 0.7;
  { how far apart in length the loops on one manifold may be before the
    layout is tried again. Loops within 10-15 ft of each other balance; a
    300 ft loop next to a 50 ft one never will. }
  LOOP_EVEN_FT = 15.0;
  { a manifold side whose shortest loop is less than this share of its
    longest gets its tube shared out evenly again, with one loop fewer and
    with as many (hsRadiant, LaySideSettled). Otherwise the last loop on a
    side just gets whatever the others left. }
  RUNT_SHARE = 0.75;
  { the most rows of a strip behind a manifold the first loop in front takes
    on (hsRadiant, LayManifold's Behind). Deeper strips get loops of their own. }
  BEHIND_ROWS_MAX = 5;
  { how far short of the best coverage a layout may be and still be laid
    again folded (hsRadiant, FoldTwin) }
  FOLD_TWIN_WITHIN = 0.15;
  { how much more a point short of a goal counts once it is past the goal's
    allowance - bare floor, then spread (hsRadiant, RankOf) }
  SHORT_PAST_COVER = 3.0;
  SHORT_PAST_EVEN = 2.0;
  { wild random layouts (hsRadiant, ComputeRadiantOriented's Wild): this
    share of them; one of the first few loops cut to between this share of
    its length and halfway back up to the whole }
  WILD_SHARE = 0.25;
  WILD_PINCH_RANKS = 4;
  WILD_PINCH_LO = 0.5;
  { Growing a loop into bare floor (hsRadiant, GrowLoops). A turn is pushed
    out at least this part of a spacing at a time; a nudge is not worth the
    fitter's trouble. A finger (a hairpin off a straight run) is at least this
    many spacings long, since each one is four bends. }
  PUSH_MIN = 0.25;
  FINGER_MIN_SPACINGS = 6;
  { allowed this short where a search stuck short of its goals needs it -
    a round room, a corridor; see ShortFingers }
  FINGER_SHORT_SPACINGS = 2;
  { What a bend costs in the search's ranking (hsRadiant, RankOf). A point
    short of the coverage goal costs 50, a point of evenness 5, a bend 0.2.
    Under the coverage goal the floor wins; over it, a finger has to be about
    8 ft long to earn its four bends. Mostly straight runs, as few zigzags as
    the floor allows. }
  BEND_WEIGHT = 0.2;
  { a straight this many spacings or longer counts as a long run on the
    ticket's installer line }
  STRAIGHT_RUN_SPACINGS = 6;
  { how many solutions a search keeps for the wizard to step through }
  SOLUTIONS_KEPT = 24;

  { a breakout gives up on the rows turned the other way when their first try
    covers this much less than the first way did }
  TURN_WEAK = 0.05;

  { Sliding the manifold along its wall is the search's last resort (see
    ComputeRadiantLayout): it starts once this many tries go by without a
    better layout, this far either way at first, a foot further every
    SHIFT_GROW tries. Every other way of laying the floor comes first. }
  SHIFT_AFTER = 500;
  SHIFT_FT = 3.0;
  SHIFT_GROW = 20;
  { of two layouts otherwise alike, the one whose manifold moved less wins
    by this much a foot }
  SHIFT_RANK_FT = 0.1;
  { hooks at the far wall to even the loops (see HookLoops) start once this
    many tries go by without a better layout, on this share of the tries.
    Four bends a hook, so plainer layouts get their turn first. }
  HOOK_AFTER = 100;
  HOOK_SHARE = 0.5;
  { Installer friendliness (RadiantFriendliness, out of 100). While less
    friendly layouts are not allowed (LessFriendly), a layout under
    FRIENDLY_MIN meets no goal and ranks UNFRIENDLY_COST behind every
    friendly one. Above it, FRIENDLY_RANK per point breaks ties. A plain
    serpentine is 100; a loop turning its rows at three places no wall gives, 85. }
  FRIENDLY_MIN = 85;
  FRIENDLY_RANK = 0.2;
  UNFRIENDLY_COST = 1500.0;

  { a coverage goal beyond what the tube can reach (RadiantReachPct) is
    searched for at this share of the reach, since leaders and walls use some }
  REACH_SHARE = 0.97;
  { share of random tries laid in hooked pairs, where allowed
    (TRadiantSpec.HookPairs) }
  PAIRS_SHARE = 0.5;

  { a random try's hooks: a pair of neighbors left unhooked on this share,
    and each hook's length jittered this share either way }
  HOOK_SKIP = 0.1;
  HOOK_JITTER = 0.2;

  { How many random layouts are laid at once (hsRadiant, TRadiantPool). Fixed,
    never the core count: tries are drawn from the seed stream a batch at a
    time and weighed in seed order, so the same seed finds the same layout on
    every machine. It also caps how many threads can help. Kept at two or
    more per worker, since a batch waits on its slowest layout. }
  RANDOM_BATCH = 64;
  { how long the search waits on the pool before tending its window, ms }
  POOL_WAIT_MS = 50;
  { how often the wizard's busy window is updated during a search, ms }
  SEARCH_SHOW_MS = 100;
  { the window over which layouts per second are counted, ms }
  SEARCH_RATE_MS = 2000;
  { a loop's dimensions across its rows go in the strip between their far
    ends and the far wall when it is at least this many feet wide
    (hsRadiantSubmittal, RadiantLoopDims) }
  DIM_STRIP_FT = 2.0;
  { rounds of layouts a try could lead to, laid ahead with it (hsRadiant, Prefetch) }
  PREFETCH_WAVES = 2;

  { what missing the goals adds to a layout's rank, so any layout that
    meets them ranks before every one that does not }
  GOAL_MISS = 1000.0;

  { manifold suggestion (RadiantSuggestZoneManifold): a wall turning less
    than this many degrees into a neighbor no more than this many times its
    length is part of a curve, no place for a flat cabinet }
  SUGGEST_ARC_TURN = 40.0;
  SUGGEST_ARC_RATIO = 2.0;
  { a wall this long or longer is tried at its quarter points as well as
    its middle }
  SUGGEST_QUARTER_FT = 16.0;
  { a quarter point beats the middles only when it reaches this much more floor }
  SUGGEST_QUARTER_GAIN = 0.03;
  { and only where no wall's middle reaches this much }
  SUGGEST_MIDDLE_ENOUGH = 0.92;
  { feet of bare row that weigh the same as one more loop when scoring - a guess }
  UNFILLED_LOOP_FT = 20.0;

function TubeOf(S: TTubeSize): TTubeFacts;

implementation

function TubeOf(S: TTubeSize): TTubeFacts;
begin
  Result := TUBE[S];
end;

end.

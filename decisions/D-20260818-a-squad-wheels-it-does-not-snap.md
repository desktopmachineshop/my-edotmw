# D-20260818 · A squad wheels; it does not snap

**Status:** Accepted

**Supersedes:** nothing. Refines D-006 (derived soldier positions) and
D-003 (curve sync) without changing a clause of either.

**Issue:** #101, raised by the owner during playtest P06 (#34):

> Squad formations jump around as corners are turned. Units must not
> exceed their individual speeds — therefore for a squad to make a turn,
> the inside units must go slower to maintain formation.

## Decision

Three changes, and none of them works without the other two.

1. **Facing is a chord of fixed ARC LENGTH along the path ahead**, not an
   instantaneous difference and not a fixed span of time.
   `Formation.HEADING_ARC`, 0.4 in continuous axial units.

2. **A flow-field path is smoothed before it is written into the curve** —
   binomially, four passes, both endpoints pinned, and any smoothed point
   that would round onto impassable ground left where the field put it.
   Where a bend is still packed tighter than the chord can span, the path
   is split finer and smoothed again, up to `PATH_REFINEMENTS` times.

3. **A squad's pace on each segment is `move_speed / (1 + lever ×
   curvature)`**, where `lever` is `Formation.turn_lever` — how far the
   outermost slot stands from the point the formation rotates about. That
   is the whole of the owner's rule in one line: the outermost soldier
   walks `1 + lever × curvature` times as far as the centre, so dividing
   the centre's speed by exactly that puts *him* on `move_speed`. The men
   on the inside of the turn cover less ground in the same time, which is
   the other half of what was asked for, falling out of the arithmetic
   rather than being enforced anywhere.

## Measured, on the shipped `legion_militia`

`tests/test_squad_turning.gd` prints all of these. Before/after are the
same fixtures with the constants above neutralised, which is also how
each check was watched fail:

| | before | after |
|---|---|---|
| peak soldier speed, tight corner | **266.71** (81× his `move_speed` of 3.30) | **3.31** (1.003×) |
| peak soldier speed, open march | 3.59 (1.09×) | 3.30 (1.000×) |
| facing step per 20 ms at a corner | **90.00°** | 0.57° |
| that corner journey, line / column | 9.6 s / 9.6 s | 15.2 s / 17.2 s |
| keyframes, open march | 7 | 7 |
| keyframes, round the obstacle | 7 | 25 |

The 9.6/9.6 tie is the "before" column saying what it should: a turn cost
nothing, so the formation made no difference to how long one took.

## What it costs a real match — measured, A/B, same host

Docker was down on this machine for the whole session, so these are
**native** runs (`EDOTMW_RUNTIME=native`, a real server and real bots over
the real socket, this worktree's own port per D-095) rather than
`just test-load`. Same host, same seed 1337, same 168x194 default map,
4 bots. Absolute numbers are therefore not comparable to the docker
figures in `docs/status/`; the A/B between the two columns is the result.

`4 300`:

| | `main` | this branch |
|---|---|---|
| verdict | **ok** | **failed** — fog gates, see below |
| desyncs | 0 of 1,200 checks | 0 of 1,172 checks |
| dropped ticks | 0 | 0 |
| µs/squad **at 48 squads** | 385.95 | 413.48 |
| vision / combat µs | 24.71 / 56.01 | 27.32 / 61.44 |
| bytes sent over the run | 124,368 | 232,748 |
| curves rebuilt | 1,236 | 1,373 |

**The µs/squad column is host noise, not this change, and the run says so
itself:** `vision` and `combat` rose by the same ~10% and this change
touches neither. A third run of the branch on a quieter host — the other
agents on this machine had finished — measured **370.68 µs/squad at 48
squads at the same tick 3000, against `main`'s 385.95**. Quote none of
these without the squad count, and none of them as a delta without an
interleaved pair.

**Bandwidth is the real cost, and it is affordable.** 232,748 B over
312 s across 4 clients is **186 B/client/s**, against `main`'s 101 and
against M4's measured 595 B/client/s at 20 players. Roughly 1.9x for
paths that bend, nothing for paths that do not.

**The fog gates failed at 300 s and that is a duration, not a defect.**
`conceal_events` went 6 -> 1 and `reveal_events` 5 -> 0, because squads
wheeling round bends cross vision boundaries fewer times inside a fixed
window — CLAUDE.md's standing "when the opening changes, every timing
tuned against the old one is stale" rule, applied to how fast armies
walk. Re-run at **`4 480` the branch is clean**: `VERDICT ok`, 0 desyncs
over 1,920 checks, 0 dropped ticks, `casualties_applied=60
conceal_events=20 reveal_events=5 ghosts_peak=16 nodes_felled=254`, and
392.95 µs/squad at 48 squads.

## Rationale

### The snap had two causes, and only one of them was a turn

The issue attributes the jump to a 60° step in a rigidly-rotated
formation, which is right. What it does not say is that **most of those
steps are not turns at all** — they are the lattice. A hex flow field can
only step in six directions, so any route off those six is walked as a
run of one direction and then a run of another, and facing derived from
an instantaneous difference reads every junction as a real turn.

(#101 predicts the field alternates cell by cell. It does not — it goes
in runs, so the flips are rarer than the issue assumed and exactly as
violent. That matters for testing: a two-second window sampled out of the
middle of a march lands inside a run and reports nothing wrong, which the
first version of these tests duly did.)

Smoothing is aimed at that. A binomial `[1,2,1]` pass has **zero gain at
the Nyquist frequency** of the path, so a cell-by-cell alternation is
removed outright; a run junction is a lower frequency and survives as a
corner, merely rounded.

### Why the facing chord looks FORWARD

Forced, not preferred. `_rebuild_curve` starts a squad's curve at its
CURRENT cell, so the server keeps no history to look back into either;
and the client's copy is clipped to `[now, now + horizon]` (D-003), which
has none by construction. Looking ahead is the only direction with curve
in it — and it is also how a formation really wheels, beginning the turn
before the corner rather than at it.

### Why the chord is measured in PATH and not in TIME — the trap

This is the part worth carrying forward, because a time-based chord is
the obvious implementation and it **fights its own fix**.

A chord that spans a fixed number of seconds spans less *path* when the
squad walks slower. So slowing a squad down to wheel it safely shortens
its chord, and a shorter chord swings faster through the same bend. The
correction and the defect feed each other: the first working version
measured a peak of 8.62 (2.6×) after slowing, against 6.76 (2.0×) before
slowing, and tuning the margin made it *non-monotonic* — 1.6 → 3.68,
1.8 → 3.37, 2.0 → 4.12, 2.4 → 5.45. A constant tuned on that curve would
have been fitted to a fixture, not to a rule.

Measured in path, the facing turns at `curvature × speed` whatever the
speed is — which is exactly what the pace arithmetic assumes, so the two
halves agree by construction instead of by tuning. With that change the
same sweep goes monotone (1.15 → 3.94, 1.5 → 3.54, 2.0 → 3.31) and the
remaining margin is one honest constant.

**The general shape: when a correction's own effect changes the quantity
it is computed from, the fix is to re-express it in something the
correction does not move.**

### What bounds `HEADING_ARC` above

How much curve a client actually holds. Its copy is clipped to
`[now, now + horizon_seconds]`, and at the slowest pace `SquadSim` will
ever set — `MIN_TURNING_SPEED`, on the slowest shipped unit — that window
is only 0.45 cells long. Reaching past it would derive one facing on the
server and another on the client, which is M1's desync surface reopened.
`test_the_facing_chord_fits_in_what_a_client_holds` pins the three
constants together; they were otherwise in two files with nothing
relating them.

That cap is also why the turn could **not** be fixed in the derivation
alone: no window that fits inside the horizon can wheel a 36-strong line
through 60° at its own `move_speed`. The time has to exist in the curve,
which is a simulation change — exactly the split #101 predicted.

## What this does NOT do

- **No per-soldier state anywhere.** D-006 clause 1 is untouched:
  position is still a pure function of (curve, shape, slot, terrain), and
  `Formation` is still all-static with nowhere to keep a turn rate. The
  turn lives in the curve's keyframe TIMES, replicated like every other
  number in it.
- **No new wire format and no new field.** A straight march buys no extra
  keyframes at all — refinement only fires on a segment that actually
  bends — so D-003's bandwidth claim holds where squads spend most of
  their time. A path round an obstacle costs 25 keyframes where it cost
  7, bounded at `PATH_REFINEMENTS` halvings, and two tests hold both ends
  of that.
- **Nothing for a re-ORDER.** A player turning a squad on the spot still
  gets a fresh curve from its current cell, and the block comes round as
  fast as the client's easing (D-059) allows. That is a different
  question from following a path and is deliberately left alone.
- **Nothing about where individual soldiers stand** (#97) or how squads
  share ground (#104).

## Rejected alternatives

- **Smoothing the facing and leaving the simulation alone** (#101's
  option A on its own). Ruled out by the horizon cap above: it stops the
  motion being instantaneous and still lets the outer file travel at
  multiples of `move_speed`.
- **Rounding corners with extra keyframes everywhere.** Pays bandwidth on
  every march for a problem only bends have. Refinement does the same
  thing where it is needed and nowhere else.
- **Storing a facing on the squad and replicating it.** A new wire field
  and a new thing to keep in step, to carry a value both sides can
  already derive.
- **A per-soldier turn-rate limiter.** Integration state in a cosmetic
  disguise — the exact thing D-006 clause 1 and CLAUDE.md's
  animation-phase note forbid.
- **Charging the turn as a dwell at the corner.** The squad would stop
  dead, and a stationary chord has no direction in it, so facing would
  snap at the end of the dwell instead of at the start.

## Consequences

- **Journeys with bends in them take longer**, in proportion to how far
  the formation reaches from the point it rotates about. That is
  wire-visible and moves arrival times. It is also the property that
  gives the formation buttons tactical weight, per CLAUDE.md's stated
  Rome-ish inspiration.
- **Which formation is slowest to turn is not the obvious one.** A squad
  rotates about its curve point, which sits at the FRONT rank, so a deep
  column swings its rear further than a wide line swings its flank —
  7.33 against 5.27 on the shipped militia. The lever is measured, never
  assumed, and the test reads it rather than hard-coding which shape
  wins.
- **`MIN_TURNING_SPEED` is where the rule is approximate.** A bend tight
  enough to need less than 30% of `move_speed` gets 30% anyway, and its
  outermost soldier goes over. The floor is not a comfort setting — it is
  what keeps the client's chord inside the curve it was sent.
- **A squad's curve now leaves the cell centres.** Its authoritative cell
  is still `curve.sample_cell()`, and the smoothing guard means that cell
  is always one the flow field itself walked.
- **`Formation.turn_lever` shares `footprint`'s cache and its loop**, so
  the scan it needs is one already being made.

## Revisit trigger

- Anything that gives a soldier positional freedom of its own — local
  avoidance, jostling, per-man passability (#97) — because then the block
  is no longer rigid and the lever is no longer the whole story.
- `CurveReplicator.horizon_seconds` or `MIN_TURNING_SPEED` changing:
  `HEADING_ARC` is bounded by both, and the test that pins them together
  is the place to start.
- Turn cost showing up as a balance problem — armies arriving late enough
  to matter to D-054's ladder or D-056's match-length work.

## Amendment, 2026-08-18 — rebased onto `main`, and what that cost

This branch sat while three things landed, and it conflicts with all
three on purpose: each of them is about where a squad or a soldier may
be, and this change is the first one that ever moves a squad off the
lattice.

- `D-20260818-a-soldier-stands-where-his-squad-could-walk` (#135)
- `D-20260818-squads-separate-by-their-footprint` (#146)
- `D-20260818-pathing-knows-only-what-the-player-knows` (#133)

The three structural claims above survive unchanged — the arc-length
chord, the smoothing, and `move_speed / (1 + lever x curvature)`. What
did not survive was a sentence in the Consequences list, and the guard it
described.

### The claim that was false: "that cell is always one the flow field itself walked"

It said so above, and it was not true, and nothing in the suite could
see it. `_smooth_path` tested the smoothed POINT for passability. A
squad's authoritative cell is `curve.sample_cell()` at any time at all —
between two keyframes far more often than on one — so two vertices could
each sit on open ground with the straight line between them clipping the
corner of a rock. That is the D-058/D-065 family again: **a decision
entry asserting an invariant is not evidence the invariant holds.**

On the rebased tree it was not subtle. `test_a_blind_squad_still_never_
stands_in_a_wall` (#133's own check, which did not exist when this branch
was written) went red, and so did this branch's own
`test_smoothing_never_puts_a_squad_on_impassable_ground` — the tick-rate
version of the same question, which passes or fails on where the flow
field happens to put a corner.

Three things now hold it:

1. **`_smooth_path` keeps a move only if the squad could WALK both
   segments it leaves behind**, not merely stand on the point. That also
   removes a failure the point test created: refusing one point while its
   neighbours move puts a SPIKE in the path, measured at **82.9 degrees**
   on a lattice whose sharpest genuine corner is 60. Testing segments
   makes a refused point hold its neighbours back with it.
2. **`_pushed_clear` gives the smoothing room** before it runs. A route
   that rounds an obstacle runs along the obstacle's edge, so every point
   of the interesting stretch has the blockage on the inside of its own
   bend — exactly where a binomial pass wants to pull it. Refusing all of
   them leaves the lattice's 60 degree vertices with nothing to spread
   them into, and a turn concentrated at one vertex is one **no pace can
   wheel through**: the whole rotation has to happen while the squad
   crosses a single point, so `MIN_TURNING_SPEED` floors the crawl long
   before the outermost soldier is inside his own `move_speed`.
3. **`_walkable_line` is the backstop**, reverting a vertex to the field's
   own line and, failing that, taking the field's line whole. A squad
   snapping round a corner is a worse picture than one wheeling; a squad
   standing inside a mountain is not a picture problem at all.

### And underneath all of it, one wrong line in `state_curve.gd`

The first working version of the repair above still measured **21.23**
against a `move_speed` of 3.30, and the reason was not the repair.
`StateCurve.sample_cell` rounded each axial component with `roundi`,
which partitions the plane into rhombi rather than hexagons, so it
disagreed with `TorusSpace.round_axial` — the project's one definition,
and `world_to_cell`'s — over about a quarter of every cell. Asked that
way, the flow field's OWN line is unwalkable at a subdivided midpoint,
the repair reverted a run of points, and the spike above is what came
out. `D-20260818-a-curve-samples-the-hex-not-the-rhombus` has the whole
of it. With the two agreeing, this fixture reverts nothing.

### The numbers, re-measured on the rebased tree

Same fixtures, same shipped `legion_militia`, printed by
`tests/test_squad_turning.gd`:

| | before | this branch, pre-rebase | rebased |
|---|---|---|---|
| peak soldier speed, tight corner | 266.71 (81x) | 3.31 (1.003x) | **3.30 (1.000x)** |
| peak soldier speed, open march | 3.59 (1.09x) | 3.30 | **3.30** |
| facing step per 20 ms at a corner | 90.00 deg | 0.57 deg | **0.27 deg** |
| that corner journey, line / column | 9.6 / 9.6 s | 15.2 / 17.2 s | 14.4 / 15.6 s |
| keyframes, open march | 7 | 7 | **7** |
| keyframes, round the obstacle | 7 | 25 | **25** |

The middle column is quoted for the record and should not be trusted as
a measurement of anything: it was taken with a path that cut the corner
of the obstacle, which is the defect this amendment exists to fix. **The
headline 1.003x was bought partly by walking through the rock.**

### The other two, and why neither needed code

- **#135 (a soldier stands where his squad could walk).** This entry's
  own revisit trigger named "#97, per-man passability" and #97 has since
  landed, so the trigger has fired and the answer is that the pace stands.
  `Formation.turn_lever` measures the UNCLAMPED slot, so where the clamp
  bites, the man it moves walks a shorter arc than the pace was budgeted
  for — the allowance is conservative, never short. The clamp's own step
  is #135's accepted cost and is not a rotation.
  The dependency that does matter runs the other way: that clamp's
  guaranteed fallback is "the squad's own cell, which is passable by
  construction", and smoothing is the one thing that could have made that
  sentence false. It cannot now.
- **#146 (squads separate by their footprint).** `turn_lever` reads the
  same `Formation.footprint` dictionary and the same cached loop that
  `SquadSim.footprint_cells` reads for separation; it adds a key and
  changes no existing one. Separation runs on ARRIVAL and pace is set
  when a curve is built, so the two never touch.
- **#133 (pathing knows only what the player knows).** The cell walk is
  unchanged: discovery-by-touch and the `stale` re-route happen exactly
  where they did, and `_path_curve` is handed the cells that survive
  them. The one deliberate asymmetry is that `_smooth_path`,
  `_pushed_clear` and `_segment_clear` all ask `is_passable` — GROUND
  TRUTH — rather than the mover's belief. That is right and it is not a
  leak: none of them chooses a route or refuses an order, they only
  decline to cut a corner, which is the same standing the entry already
  gives `_approachable`. Asking belief instead would let a smoothed line
  run through a mountain nobody has scouted, which is the one thing
  #133's discovery-by-touch net exists to prevent.

### What the room-making is worth, measured

`PATH_CLEARANCE` is not a tidiness constant. Set to 0 — smoothing still
constrained by segment clearance, everything else unchanged — the same
corner fixture measures **25.82** against a `move_speed` of 3.30, and the
facing steps 4.33 degrees per 20 ms. At 0.45 it is 3.30 and 0.27. The
whole of the difference is whether the smoothing has anywhere to spread a
60 degree lattice vertex into.

### The one thing this rebase could NOT resolve: a shipped balance rule moved

`test_buildings.gd`'s `test_two_squads_of_any_line_troop_but_light_
skirmishers_can_take_a_tower` — D-067's shipped rule — **fails on this
branch for exactly one pairing**, northmen_spearmen against a tower.
Measured on the same fixture, same seed:

| | `main` | this branch |
|---|---|---|
| outcome | razed at 52.6 s, 31 men left | **wiped**, tower on 86 of 1700 HP |
| squad-ticks within 2 cells of the tower | 74% | 59% |
| squad-ticks routed | 8% | 14% |

Every other troop and both buildings still pass, and a LONE squad of
spearmen is bit-for-bit unaffected (wiped at 42.1 s with the tower on
1220 HP either way), so this is not a change to how hard anything hits.

**The mechanism is the mechanic.** A straight march costs nothing — a
10-cell march measures 4.80 s on both trees — while a two-cell
reposition with a bend in it goes **1.30 s -> 2.00 s**. A siege where two
squads are ordered onto the same cell is nothing but bent repositions,
under fire, with routs and returns; 50% more time on each of them is
where the 5% went. That is #101's rule being charged, not a defect: a
36-strong line pivoting takes time now, and static defences are the thing
that does not have to pay it.

**It is also a knife-edge, and must not be tuned away.** Sweeping
`TURN_SWEEP` — a constant that has nothing to do with towers — flips the
outcome without a trend: 1.0 razes, 1.2 does not, 1.5 razes, 2.0 does
not. A constant chosen to make that fixture pass would be fitted to the
fixture, which is the trap this entry already documents from the other
direction. `TURN_SWEEP` stays at 2.0, which is what puts the outermost
soldier at 1.000x his own speed; at 1.5 he runs at 1.10x.

Two candidate resolutions, both DESIGN calls and neither taken here:

1. **Accept it** and record spearmen-against-a-tower as a second measured
   exception beside northmen_skirmishers, the way D-067 already carries
   one.
2. **Restore the margin in the tower's data**, which is the lever D-067
   itself swept — but the tower is `neutral` and shared, so it moves the
   AI ladder and every playtest with it.

Ruled out, and worth saying: **exempting a ROUTED squad from the turn
pacing does not fix it** (measured: byte-identical outcome, tower still on
86 HP), so "routers should not have to hold formation" is not the missing
rule here.

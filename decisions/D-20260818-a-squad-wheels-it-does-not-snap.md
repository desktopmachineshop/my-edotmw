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

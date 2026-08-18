# D-20260818 · A curve samples the hex, not the rhombus

**Status:** Accepted

**Supersedes:** nothing. Corrects one line of `state_curve.gd` that has
been wrong, and unobservable, since D-003.

**Found by:** rebasing #101's wheeling change onto a `main` that had
gained `D-20260818-pathing-knows-only-what-the-player-knows` (#133) and
`D-20260818-a-soldier-stands-where-his-squad-could-walk` (#135). Both of
those turn "which cell is this squad in" into a load-bearing question,
and #101 is the first change that ever puts a squad anywhere but on a
lattice line.

## Decision

`StateCurve.sample_cell` resolves a fractional axial coordinate through
**`TorusSpace.round_axial`**, the project's one definition of which hex a
point is in and the one `world_to_cell` has always used. It used to round
each component independently with `roundi`.

## The defect

`roundi(q), roundi(r)` partitions axial space into **rhombi**.
`round_axial` converts to cube coordinates, rounds, and repairs the
component with the largest error, which partitions it into **hexagons**.
Those are different sets. They agree over most of a cell and disagree
over two triangular slivers at the rhombus's acute corners — roughly a
quarter of a cell's area, on the side where three hexes meet.

**Nothing had ever sampled there.** A `StateCurve` for a squad held one
keyframe per cell the flow field walked, so every point of it was either
a cell centre or on the straight line between two ADJACENT cell centres —
along one of the six lattice directions, where the two roundings agree
everywhere except the exact midpoint. A set of measure zero, sampled by a
10 Hz tick. So the wrong answer existed for six milestones and could not
be reached.

Smoothing a path (#101) takes a squad off those lines. The disagreement
stops being a point and becomes a region, and the region is exactly the
one that matters: the corner where three cells meet, which is where a
route rounding an obstacle passes. A squad walking a clear cell away from
a rock read as **standing inside the rock** — `_cell[squad]` is
`space.index(curve.sample_cell(time, space))`, so this was the
simulation's own opinion, not a rendering artefact.

## Why it had to be fixed here rather than filed

#101's path work needs one answer to "may a squad cross this point", and
it was getting two. Asked the naive way, the flow field's OWN line was
illegal: the midpoint of a step along the `(1,-1)` lattice direction is a
pair of exact halves, `roundi` rounds both away from zero, and the answer
is a cell that neighbours both the cells the step runs between. Path
refinement manufactures precisely those coordinates, because it inserts
midpoints. So the clearance repair reverted a run of points beside an
already-smoothed neighbour and put a **78.4 degree spike** into a path
whose sharpest genuine corner is 60 — a worse turn than the one the
smoothing was called to soften, produced entirely by asking the wrong
question.

With the two agreeing, the same fixture reverts nothing at all and the
peak soldier speed at a tight corner goes **21.23 -> 3.30** against a
`move_speed` of 3.30.

## Consequences

- **A squad's cell can differ by one from what it was**, for the ticks it
  spends between two cell centres. Nothing else changes: keyframes are
  still cell centres, and a squad at rest is where it always was.
- **Client and server still agree**, because both sides call this same
  function. There is no new wire field and nothing to keep in step —
  which is why this is safe to change under D-022's audit rules.
- **`append_cell` keeps its `roundi`** on the previous point. That call
  reads a point the function itself wrote as a cell centre, so the two
  roundings cannot disagree there, and reaching for `round_axial` would
  imply a generality the chain does not have.

## Rejected alternatives

- **Teaching the path code to ask the naive question.** That is what was
  tried first, and it makes the flow field's own line unwalkable (see
  above). A rule that condemns the route it is protecting is not a rule.
- **Leaving `sample_cell` alone and keeping squads on lattice lines.**
  That is #101 abandoned, for a bug that is one line.
- **Filing it and shipping around it.** The two roundings disagreeing is
  not a latent tidiness problem once anything samples between lines; it
  is the simulation holding two opinions about where a squad is.

## Revisit trigger

- Anything else that samples a curve between keyframes and rounds it by
  hand. `TorusSpace.round_axial` is the answer; a `Vector2i(roundi(...),
  roundi(...))` on a fractional axial pair is the defect.

**Pathing knows only what the player knows
(D-20260818-pathing-knows-only-what-the-player-knows, 2026-08-18).** Flow
fields were solved against the sim's single ground-truth passability
array, so a squad ordered across the map rounded lakes, mountain ranges
and walled-off pockets nobody had ever seen, and an order into an
unexplored pocket that happened to be sealed was refused **on the tick it
was given**. Fog hid the terrain visually while movement acted on the
whole map. Found by the owner playing (#96, playtest P06), not by any
check — every field was optimal and every refusal accurate, which is
precisely why nothing failed.

The standing rule, which is the part worth carrying:

> **The simulation may never route a squad around, or refuse to move a
> squad because of, terrain its owner has not discovered.** Anything that
> plans a route, or decides a route is impossible, reads
> `terrain_knowledge.gd`. `SquadSim._passable` is ground truth and answers
> exactly one question: may a squad physically STAND here, right now.

Four things to know before touching movement:

- **Belief is OPTIMISTIC — unknown ground reads passable.** That gives
  `believed-passable ⊇ truly-passable`, so belief-unreachable implies
  truly-unreachable and a side can only be refused an order that was
  genuinely impossible. The asymmetry is deliberate: being wrongly
  refused is far more noticeable than marching somewhere and finding a
  dead end, which is a mistake a player understands making.
- **Fields are keyed on (destination, SIDE), and D-007's sharing
  survives** — because the sharing that was ever load-bearing is between
  squads of one side. Fifty squads sent to one place still solve one
  field; allies share it too (D-050). Only two *different* sides ordering
  to the same cell pay twice.
- **Discovery has two sources and the second is the safety net.** Sight
  folds `Vision`'s own coverage into belief on vision's cadence; TOUCH
  checks every step before it is written, so a squad with `vision_range`
  0 still learns, and optimism can plan a route into a mountain but can
  never put soldiers inside one.
- **A re-route DROPS the field rather than patching it**, and the give-up
  rule is held off for that one tick. Invalidating a side's fields on
  every discovered blocked cell was rejected as the expensive version:
  a squad marching a coast discovers blocked cells constantly and almost
  none of them are on anybody's route.

`SquadSim.route_discoveries` counts planned steps that ran into ground the
mover's side did not know was blocked. **Zero of those in a match with
terrain means the mechanism is dead**, which is this project's
most-repeated defect wearing a green verdict.

Deliberately still omniscient, and scoped out: `_approachable` (which
answers "can a squad STAND here", corrects a destination rather than
choosing a route, and can never refuse an order). Deliberately not
fogged: the wall-top tier (D-076), whose network is made of buildings a
side put there itself.

**And a squad's cell was being rounded to the wrong SHAPE
(`D-20260818-a-curve-samples-the-hex-not-the-rhombus`, 2026-08-18).**
`StateCurve.sample_cell` rounded each axial component with `roundi`, which
partitions the plane into rhombi; `TorusSpace.round_axial` — the project's
one definition, and `world_to_cell`'s — partitions it into hexagons. The
two disagree over roughly a quarter of every cell, at the corner where
three cells meet.

It survived six milestones because **nothing was ever between cells
anywhere but on a lattice line**: a squad's curve held one keyframe per
cell the flow field walked, and along one of the six lattice directions
the two roundings agree everywhere except the exact midpoint — a set of
measure zero, sampled by a 10 Hz tick. #101's path smoothing is the first
thing that ever moves a squad off those lines, and the disagreement
immediately became a region rather than a point: a squad rounding an
obstacle read as standing INSIDE it while its own line was a clear cell
away. `_cell[squad]` is `space.index(curve.sample_cell(time, space))`, so
that was the simulation's own opinion, not a rendering artefact — and it
is what `route_discoveries`, vision, combat and separation all read.

Two things to carry:

- **The rule this file already states got a second reader.** Anything
  that plans a route reads `terrain_knowledge.gd`; anything that asks
  "which cell is this fractional axial coordinate in" reads
  `TorusSpace.round_axial`. A `Vector2i(roundi(q), roundi(r))` on a
  fractional pair is the defect, and it is worth grepping for.
- **A wrong answer nothing can reach is still a wrong answer waiting for
  a caller.** This is the declared-and-unread family with the roles
  swapped: the code was read constantly and simply never asked the
  question at a coordinate where it mattered.

**And a squad can be told to go and find out on its own
(`D-20260828-explore-is-an-order-and-the-frontier-is-knowledge`, #120,
2026-08-28).** A sixth squad order: explore. Issued once, the squad picks
a destination, walks, reveals, and repicks until it is given another
order, routs, or dies. `ExploreTarget` is the pure, all-static picker —
one definition, so a future AI scouting behaviour cannot come to disagree
with the player's verb about what exploring means (D-051).

Four things to know before touching it, and most are not about scouting:

- **The frontier is a new datum, and it had to be.** `Vision` answers
  "can this side see it NOW"; a scout needs "has this side EVER been
  shown it". `TerrainKnowledge.Belief.believed` cannot serve — it starts
  all-1 because unknown ground reads passable, so it cannot separate
  "never seen" from "seen, and open". `Belief.explored` is that set,
  accumulated **in the pass that already folds sight into knowledge**,
  keyed by SIDE because allies share sight (D-050). Not a second fog
  query: D-004 forbids a second data-hiding path, and this is one byte
  per cell written inside a loop that was already running.
- **The trap in it fired.** `observe()` skips cells whose passability it
  already agreed with — which on open ground is most of the map. With
  the explored write after that skip, a scout is told everything is
  unexplored forever and sent to the cell it is standing on. The write
  goes FIRST, and the guard was watched to fail with it moved.
  Separately, `absorb` used to return early when there was no terrain
  array; passability is unknowable without truth but **what a side has
  seen is not**, and three tests failed on that one cause.
- **Targets are REGIONS** (`explore_quantum` 4), snapped exactly as a
  rout's destination is and for the same D-007/D-038 reason: nobody chose
  the exact cell, and N scouts each demanding a unique frontier cell is
  the pathological case for shared fields. 4 rather than the rout's 8 so
  the worst snap error stays inside every unit's vision radius — the
  scout can SEE what it was aimed at.
- **The omniscience question is the sharp one**, and it is #96's in a
  more dangerous form: here the SIMULATION picks the destination rather
  than a player clicking one. The picker is handed the side's own
  explored and believed arrays and nothing else — there is no argument
  through which truth could arrive. The one honest edge is
  `_approachable`, which reads truth to snap a destination onto standable
  ground; that is pre-existing, identical for every order, and explicitly
  scoped out by the entry above — but its influence is larger here, and
  the decision says so rather than claiming purity.

**Deliberately left open:** what an exploring squad does when it meets
something (#120 point 3) — today it fights if engaged and the rout ends
the mode, and making a scout flee on contact wants its own decision. And
**the AI does not use the verb yet**: the picker is pure so that it can,
but `bot_patrol.gd`'s legs are what `test-load`'s fog gates depend on, so
changing scouting behaviour in the branch that adds the order would make
any gate movement unattributable.

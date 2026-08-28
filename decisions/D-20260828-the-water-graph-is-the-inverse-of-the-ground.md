# D-20260828 · 2026-08-28 · Accepted — the water graph is the inverse of the ground

**Decision:** stage 1 of the naval plan (`docs/plans/naval.md` §2.1, §4.1,
§7). Water gets its own field, its own shore predicate and no new
component walk. Four clauses:

1. **`TerrainGen.navigability(space)` is a SEPARATE `PackedByteArray`**,
   `navigable[i] = 1 iff elevation(i) < sea_level`, derived from the
   replicated `MapSettings` numbers both sides already hold (D-049). Not
   a third value in `passability`.
2. **`TerrainGen.is_shore(space, passable, navigable, i)` is static and
   takes BOTH fields as arguments.** A shore is passable land with at
   least one navigable neighbour.
3. **Water components come from `MapConfig.walkable_components`.** No
   second flood fill.
4. **Nothing in the simulation changes.** The stage is a field, a
   predicate and tests.

## Rationale

**Why a separate array (clause 1).** D-076 kept its wall-top field cache
separate and the reasoning carries over exactly: `_passable` has many
readers and every one of them means LAND. A tri-state array would be
read by all of them, and the ones that never learned the third value
would not fail — they would quietly treat open water as walkable ground.
That is the declared-and-misread shape this project keeps paying for,
and it would arrive as an army standing on the sea.

**Why both fields are arguments (clause 2).** Which passability a caller
means is a real question with two answers: `TerrainGen.passability` is
the GROUND, `SquadSim._passable` has living buildings stamped out of it.
A dock placement asks the first; a squad asking where it may stand asks
the second. Handing the choice to the caller is the discipline
`terrain_knowledge.gd` imposed on flow fields after they were solved
against ground truth for six milestones.

**Why no new component walk (clause 3).** `MapConfig.walkable_components`
is a function of a boolean field, and water is a boolean field. Writing
a second flood fill for it would be a duplicate definition of "what is
connected to what", and the two would come to disagree about the seam
first.

## The done-condition needed correcting, and that is the substance here

The cut-list says stage 1 is done when *"navigability + passability are
disjoint and cover the map"*. The first half is true and now asserted.
**The second half is not true in general**, and shipping a test that
claimed it would have been worse than shipping none:

- **Disjoint: yes.** `_slope_passable` returns false below `sea_level`
  and `_carve_ramps` never carves water — an island is not a plateau
  (D-20260826). Asserted on every shipped preset, *after* carving, and
  observed to fail: with the below-sea-level guard removed, `continents`
  reports 173 cells in both fields and `islands` 885.
- **Cover: preset-dependent.** Land too steep to walk is in NEITHER
  field. Measured across the ladder at 48x24, seed 1337:

  | preset | union covers the map? |
  |---|---|
  | `plains`, `highlands`, `islands` | yes — no unwalkable land at all |
  | `continents` | **no** — 91 of 1152 cells (7.9%) |

  `highlands` was the natural preset to demonstrate the gap with and has
  none, because D-20260826 opened it up completely ("44.1% dead space …
  fully open now"). `continents` gained real walls in the same change
  (2.0% → 7.0% blocked), which is where the 7.9% comes from.

**What actually partitions the map is the DOMAIN.** `navigable` is
exactly the water half and its complement is exactly the land half;
passability is a rule WITHIN land about which of it you may stand on. A
ship is refused a steep hill because it is land, not because it is
unnavigable water.

This matters downstream rather than pedantically: stage 2 dispatches on
domain and stage 9 places spawns over these fields. A reader who believed
the slogan would write `if not navigable then walkable` and put an army
on a cliff.

## Rejected alternatives

- **A tri-state `passability`.** Clause 1's rationale.
- **Shallow versus deep navigability.** `DEEP_WATER` is a biome and an
  appearance, not a draft rule. All water is navigable in v1; a draft
  distinction doubles the field count and the transition surface to buy
  a mechanic nothing else asks for yet. Named as the water domain's
  revisit trigger by the plan, and left there.
- **`is_shore` reading the fields from somewhere.** It would have to
  pick one passability and be wrong for the other caller.
- **Renaming `MapConfig.walkable_components`.** It is domain-agnostic and
  its name is not — calling it with a navigability field reads oddly, and
  every naval stage will do so. Left alone because it belongs to an
  unmerged PR (#216) and churning another branch's file to improve a
  name is how a merge train stops; **flagged there instead.**
- **Subtracting buildings from `navigability`.** A dock's own cell is
  land (§4), so nothing occupies water in v1. The moment something does
  — a sea wall, a floating platform — it must be stamped out exactly as
  `occupied_cells()` is stamped out of `_passable`. Stated so it is not
  rediscovered.

## Consequences

- **Sixteen tests, every one observed to fail.** Including the two that
  matter most for later stages: disjointness after ramp carving, and the
  seam (`is_shore` made non-wrapping reports no shore across the seam,
  which would have refused docks along one column of every map with
  nothing failing).
- **`is_shore` explicitly refuses a navigable cell**, which is redundant
  given disjointness and is not defensive: it is handed two arrays of
  the same shape and opposite meaning, and `is_shore(space, navigable,
  navigable, …)` would otherwise offer the open sea as dock sites.
  Observed to fail.
- **Measured facts later stages can use:** `continents` at 64x32 has 164
  shore cells, so stage 3's dock has somewhere to stand; `islands` at
  64x32 has a largest connected sea of 1,565 cells, which is what stage 9
  will reason about when it decides whether two starts can reach each
  other.

## Revisit trigger

The first naval stage that needs a water cell to be occupied by
something, or that needs draft. Either reopens clause 1's "one array,
all water" — as a decision, not as a field edit.

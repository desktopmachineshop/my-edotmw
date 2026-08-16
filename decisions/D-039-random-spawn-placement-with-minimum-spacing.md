### D-039 · 2026-08-01 · Accepted — random spawn placement with minimum spacing
**Decision:** Starting positions are scattered randomly across the map,
subject to a minimum toroidal spacing (`min_spawn_spacing`, 12 cells on
the shipped 128x64 map) and to standing on passable ground. They are no
longer laid out on a grid. The shipped map offers 20 slots, matching
D-018's target concurrency.

Placement is rejection sampling seeded from `spawn_seed`, so it is
deterministic: the same map gives the same layout every run, which
D-016's replays require.

**Rationale:** A grid gave every match the same neighbours at the same
distances. The opening was therefore the same conversation every time,
and the map's own features — where the wood is, which valley is
defensible — never changed who had to fight whom. Random placement makes
adjacency a property of the match rather than of the layout, so hotspots
and the clashes around them emerge instead of being designed.

Fairness is deliberately split into two mechanisms that do not overlap.
`min_spawn_spacing` bounds how close anyone can be placed; it is the only
thing spacing guarantees. Resource fairness stays where D-036 put it, in
`Economy.balance_for_spawns`, which tops up each start to a minimum of
every resource within reach. Neither tries to do the other's job, and
neither silently compensates for the other failing.

**What random placement needs that a grid did not:**

1. **Terrain awareness.** A grid could be authored onto known-good
   ground. Sampling cannot, so `spawn_points()` takes a passability array
   and the caller holding the terrain supplies it. A start inside a lake
   is a live failure mode now, not a hypothetical one.
2. **An admission of failure.** Rejection sampling answers "these
   constraints are unsatisfiable" by quietly returning fewer points.
   `validate_spawns()` turns that into a message; `validate()` catches the
   arithmetically impossible cases up front with a packing bound. Silent
   short seating is exactly the failure that produced the 20-player
   anomaly, where twenty players wrapped onto four grid seats.

**Rejected alternatives:** Keeping the grid and simply adding more seats
(rejected — fixes the seating count and none of the sameness). Poisson-disc
sampling proper (rejected — rejection sampling is a dozen lines and the
constraint is loose enough that it terminates immediately; the fancier
algorithm would buy nothing measurable). Rejecting seeds by scoring
layouts for balance (rejected — an implicit fairness model nobody could
state, on top of an explicit one that already exists).

**Consequences:** `spawn_grid` and `spawn_offset` are gone from
`MapConfig`. `bot_client.gd` no longer mirrors server spawn arithmetic to
guess where a neighbour starts — a duplication that was documented as
fragile and is now simply impossible — and reads the spawn table the
welcome message has carried since D-036. Player capacity is a map field
rather than a function of terrain symmetry.

**Revisit trigger:** If matches show a systematic advantage correlated
with spawn position — someone consistently isolated, or a pair
consistently forced into an opening fight neither chose — the answer is a
fairness post-pass on the sampled layout, not a return to the grid.

---

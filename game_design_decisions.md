# Game Design Decisions

Living decision log for my-edotmw. `CLAUDE.md` is the condensed ground-rules
summary of this file — if the two ever disagree, this file wins and
`CLAUDE.md` needs updating.

Format per entry: **ID · Date · Status · Decision · Rationale · Rejected
alternatives · Consequences · Revisit trigger**.

Status is one of:
- **Accepted** — settled, build against it
- **Provisional** — best current call, but explicitly cheap to overturn;
  has a revisit trigger
- **Superseded by D-0xx** — kept for history, no longer in force

New entries go at the top of section 1. Never edit history in place —
supersede instead, so the rationale trail survives.

---

## 1. Decisions

### D-099 · 2026-08-16 · Accepted — a lobby rolls its map; a pinned seed reproduces the whole match

**Numbering note.** D-099 was a GAP, not the top of the list: D-100 is in
force (ground cover) while no entry or citation ever used 099. Filling it
deliberately, because parallel worktrees all allocate from the highest
number and a fifth collision after D-081's and D-098's would cost more
than a non-monotonic date.

**Decision:** the map seed is **rolled when a LOBBY opens, and again on
the way back to one**, unless somebody pinned it. Everything else keeps
the fixed default. Five clauses:

1. **`MapSettings.roll_seed()` is the one non-deterministic line in the
   map pipeline.** It draws into `[0, MapSettings.SEED_MAX]` — the same
   ceiling the lobby's spinner offers, so a rolled map is always a number
   the host can read off the screen and type back in.
2. **Only a lobby rolls.** `server.gd` rolls when `--lobby=1` and no
   `--seed` was given; a no-lobby start is a test harness or a dev launch
   and keeps `MapSettings.DEFAULT_SEED` (1337). Bots, scenarios,
   `test-load`, `test-client`, `ai-ladder` and `profile` are therefore
   as reproducible as they were.
3. **Choosing a seed PINS it** (`pin_seed`, set by `--seed` and by the
   spinner), and a pinned seed survives the return to the lobby. That is
   what makes "that was a good map, play it again" work, and it is the
   only way to hold a map still.
4. **A `Reroll` button beside the spinner asks the SERVER for a new
   seed** (`MatchState.REROLL_OPTION`) and leaves it unpinned. The client
   does not draw the number: the host would otherwise choose everyone's
   map, and a client-sent seed would arrive through the pinning path and
   silently stop the lobby rolling.
5. **The civ draw follows the map seed.** `MatchState.civ_rng` is seeded
   `civ_seed_base + map_settings.seed`, where the base is
   `hash(MapConfig.id)`, and re-seeded whenever the seed can have changed.
   So a pinned seed reproduces the whole match SETUP — terrain, spawns,
   combat rolls and who is playing whom — not merely the ground.

**Rationale.** `MapSettings.seed` has carried the doc comment "Rolled per
match unless someone pins it, so two matches on the same settings are
still different places" since D-049, and **nothing anywhere rolled it**.
Every lobby-started match, which is every match a human plays, generated
the identical world from seed 1337. Found in the #29 lobby playtest, by a
tester trying to work out whether they had typed the seed themselves.

One line away sat the same defect in a second dress: `civ_rng` was seeded
`hash(_config.id) + int(args.get("seed", 0))` — the **same absent
argument, defaulted to 0 here and 1337 twenty-five lines above**. A seat
set to Random resolved to a real civ, so the visible half worked; it
resolved to the same civ every match.

Both are this project's declared-and-unread family (D-055, D-061, D-065,
D-066), in the variant where the mechanism is not merely uncalled but
**documented as working**. Nothing fails. The game runs and quietly lacks
a rule, and the only instrument that can see it is a person playing twice
and recognising the coastline.

**Which way to resolve it — code or comment?** The issue flagged both as
defensible: "reproducible by default" is a real choice for a strategy
game. Rolling wins for three reasons. The written intent has stood for a
milestone and the ONLY thing contradicting it is an omission. A fixed
default makes #29's own pass criterion vacuous — "restart with the same
seed gives the same map" cannot fail when the seed never changes, which
is exactly the check-never-seen-red trap. And a map that is the same
place every time is a worse game, while a pin costs one number typed.

**Rejected alternatives:**
- **Correct the comment, keep 1337.** Cheapest, and it is what the code
  already does. Rejected: it ships "every match is the same map" as a
  deliberate design, which nobody has ever argued for, and it leaves the
  #29 criterion untestable.
- **Roll for every server, including headless ones.** Consistent, and it
  would have caught this sooner. Rejected: `test-load`, `ai-ladder` and
  `profile` compare runs against each other, and a map that changed under
  them would turn every performance regression into an argument about
  which map it was measured on. The reproducible default is load-bearing
  for the whole test estate.
- **Roll on the CLIENT and send the seed up.** The lobby already sends
  settings up, so it would have been a one-line button. Rejected under
  D-002: the host is not trusted with the world everyone plays on, and
  the same message would have to double as "pin this seed", so a lobby
  that had ever rerolled would stop rolling between matches.
- **Draw civs from their own wall-clock RNG.** Makes Random random
  without touching the map. Rejected: it breaks D-016's replay
  obligation, which is exactly why `civ_rng` was seeded in the first
  place. Following the map seed keeps the replay and makes the pin mean
  more.
- **Re-roll on `return_to_lobby` only when the host asks.** Fewer
  surprises. Rejected: it reintroduces the reported bug for the most
  common path there is — press "play again" and get the map just played
  — and the host can pin in one click if they want the rematch.

**Consequences:**
- The seed the lobby shows on arrival is now a different number every
  time, and the map preview beside it a different place. That IS the
  fix's visible surface, and the thing to look at when judging it.
- `just lobby-shot` is the headless way to see it. The server prints
  `lobby rolled map seed <n>` at startup and names the next map's seed on
  every return to the lobby, so a run can be traced without a GPU.
- #29's seed criterion is now testable the three-way way its issue asks
  for: note the map, change the seed and see it differ, set it back and
  see it return.
- Rolling costs one `RandomNumberGenerator` per lobby and nothing per
  tick. Measured after: `test-load 4 120` clean, 47.71 µs/squad at 48
  squads (quoted with the count, per the standing rule).

**Revisit trigger:** if a ranked or matchmade mode arrives (D-091 gates
ranked on dedicated servers), map selection stops being the host's to
roll at all and becomes the queue's — at which point clause 2's "only a
lobby rolls" needs a third case rather than an edit.
---

### D-098 · 2026-08-11 (renumbered 2026-08-16) · Accepted — tests start mid-game, from a scenario
**Decision:** A **scenario** is a mid-game world described as data
(`/scenarios/*.tres`), applied through the game's own calls, and usable
two ways: in-process by a GUT test, and by the real server via
`--scenario=<id>`.

1. **`ScenarioDef`** holds a per-player loadout — buildings, squads,
   wallet — plus `separation`, how far apart to place neighbouring
   players. `ScenarioBuilding` and `ScenarioSquad` are its entries.
2. **Placement is RELATIVE.** Entries carry an offset from the player's
   home cell, never an absolute cell, so one loadout drops onto any map.
   `placement_slack` bounds how far the applier may nudge an offset that
   lands in water or on another building.
3. **Squads name an ARCHETYPE, never a unit and never a civ**, resolved
   per player through `UnitRoster.for_civ_archetype` — so one scenario
   plays for every civ.
4. **`Scenario` is all-static**, like `Formation`: a scenario is an
   opening position, not a participant, and there is nowhere for it to
   keep state.
5. **One applier for both worlds.** `Scenario.apply_player` is called by
   `ScenarioWorld.build` (tests) and by `server.gd:_spawn_squads_for`
   (live). A scenario cannot mean one thing in a unit test and another on
   a server.
6. **Nothing is dropped in silence.** Unplaceable entries land in
   `Placement.skipped`, which the server prints as `SCENARIO_SKIPPED` and
   `test-scenario` fails on.
7. **A scenario run is identifiable in its log** — `server: SCENARIO
   id=… seats=… separation=…` — and `test-scenario` greps for exactly
   that.
8. **`just test-load 4 120` keeps playing the real opening and stays the
   gate.** A scenario is for iterating.

**Rationale:** The opening is slow on purpose and the cost compounds. A
player starts with one founding party and no base, a town hall takes 40 s
and consumes the founders (D-031), production follows, and spawns are
scattered far apart (D-039). So the cheapest honest integration test of
anything downstream cost ~150 s of waiting before the thing under test
existed. Measured, before and after, on the same machine:

| loop | before | after |
|---|---|---|
| full unit suite | 39 s | 29 s |
| one unit test file | 39 s | **11 s** |
| integration with combat, fog and buildings | ~150 s | **31 s** (at DURATION=15; ~50 s at the default 30) |

The unit suite was already spawning directly into `SquadSim`; what it
lacked was a shared fixture (32 files, each re-inventing its own
scaffolding — `test_buildings.gd` alone had 48 `.new()` calls) and any
way to run less than all 491 tests.

**Rejected alternatives:**
- **A parallel lightweight simulation for tests.** The fast path would
  then be a different program from the shipped one. This is the exact
  shape of M4's `profile` sweep reporting 29 ms for code that spent
  866 ms live, because the sweep resolved its UnitDefs once at setup and
  the server did not. Where a harness and a live run disagree, believe
  the live run — so do not build a harness that CAN disagree.
- **Scenarios as GDScript builders only.** More expressive, but "unit
  stats, civ configs, terrain-gen parameters: plain text, not hardcoded"
  is a standing rule, and a scenario is exactly that kind of data. The
  builder path remains available by constructing a `ScenarioDef` inline.
- **Letting scenarios replace the slow run.** Rejected with the user:
  nothing would then exercise founding, production timing or the opening
  end to end, which is the class of gap this log keeps recording.
- **Sizing scenario homes on `players_expected`.** Tried, and wrong: it
  defaults to 1 and `just up` does not raise it, so four bots all indexed
  into one home and four armies spawned in a pile. It looked healthy —
  bots connected, casualties were HIGHER — because they started on top of
  each other. Homes are sized on the map's own seat count instead, making
  the number of joiners irrelevant rather than load-bearing.

**Consequences:**
- `just test-unit FILTER [TEST]` maps to GUT's own `-gselect` /
  `-gunit_test_name`; `_import` is skipped when no source is newer than a
  stamp taken BEFORE the previous import, printed when skipped and
  overridable with `EDOTMW_FORCE_IMPORT=1`. That cache is the one piece
  here that could produce a confidently wrong answer, which is why it is
  conservative, loud, and was tested by editing a file and confirming the
  edit is seen.
- A scenario cannot catch a bug in founding, production or spawn
  placement — it skips them. That is stated in the file header, in
  `just scenarios`, and in CLAUDE.md, because a fixture whose blind spot
  is undocumented eventually gets trusted for what it cannot see.
- Three scenarios ship: `clash` (armies in reach, no buildings),
  `siege` (a defended base plus an attacker, for D-067's razing rule),
  `developed` (a working base and a full wallet — the default start for
  feature work).

**Revisit trigger:** a scenario is needed that varies DURING a match
rather than at t=0 (scripted events, timed reinforcements) — clause 4's
all-static applier is what to re-examine first; or `test-scenario`
becomes the thing people quote instead of `test-load`, which is clause 8
failing in practice rather than in principle.

**Amendment, 2026-08-16 (merge):** this entry was written as D-076 and is
renumbered to **D-098** here. It was authored in parallel with the work
that became main's D-075 (lobby return) and D-076 (walls and gates), on a
branch that had forked before either existed, so both numbers were spent
by the time it merged. **Two agents working the same log will collide on
the next free number, and neither can see the other** — so a number is
only really claimed once it is on main, and reconciling that is a merge
step, not a mistake. Nothing but the heading changed.

**It then happened again, in the hour between the two merges.** This
entry was renumbered to D-096, and by the time the branch was pushed
main had spent D-096 *and* D-097 — so it moved again, to D-098. Which is
the rule stated above being demonstrated rather than merely written down:
**picking "the next free number" from your own checkout is a guess, and
it goes stale while you work.** The right moment to fix a number is the
merge, against a freshly fetched main, and not before.

**Main currently carries three duplicate pairs** — two D-087s (M8 scope
vs. forests), two D-096s (continuous ground vs. continuous wall
placement) and two D-097s (cliffs vs. contestable build sites) — each
pair authored on a different branch and merged without either side
seeing the other. They are recorded here rather than renumbered in
passing: this log's whole workflow rests on an ID naming exactly one
decision, and every cross-reference elsewhere in the repo resolves
through that ID. Reconciling them is its own task, and a deliberate one.

The same fork produced a **second, independent implementation of instance
isolation** — checkout-derived names, a `$HOME` port registry with atomic
claims, `dev` pinned to 4433 and protected from an implicit `just down`,
and a `just instances` listing. D-095 landed first and is the one in
force; that implementation was dropped whole at merge rather than
half-merged, because two derivations of one identity is precisely the
failure D-095 exists to prevent. **What it had and D-095 does not is
recorded here so it can be reconsidered on its own merits, not
rediscovered a third time:** a registry makes a port collision impossible
rather than merely unlikely (D-095 hashes into 10,000 ports and does not
check), and refusing an implicit teardown of the human's instance is a
guard D-095 has no equivalent of.
### D-097 · 2026-08-15 · Accepted — a cliff is the passability boundary, drawn

**Decision:** the rendered surface **steps** where `passability` changes,
and a vertical rock skirt fills the step. The step is generated from the
same predicate the flow field routes around — never from a second,
prettier notion of steepness — and lives entirely on the rendering side:
`elevation_at` stays discrete per cell, `passability` still thresholds
it, and nothing new goes on the wire.

Four pieces:

1. **`TerrainGen.CliffClass`** — `passability` split by WHICH of its two
   reasons applies: WATER, LAND, HIGH. `passable[i] == 1` exactly when
   the class is LAND, asserted cell by cell on the shipped map. Water and
   mountain need separate classes even though both are impassable, or a
   corner where a lake meets a peak averages sea level with rock and
   hangs the surface halfway up the mountainside.
2. **Corner heights average within a class** (`TerrainGen.corner_heights`),
   so a corner where classes meet resolves to two or three heights
   instead of one. Groups whose means differ by less than
   `cliff_min_step` MERGE, which is what gives beaches and sea cliffs
   from one mechanism: a shore that rises gently keeps D-084's smooth
   blend, a shore that rises sharply steps.
3. **A skirt per stepped edge**, emitted into the chunk's own ArrayMesh
   as a second surface — so it inherits D-035's nine-copy tiling, adds no
   draw-call structure, and needs no material plumbing (it wears the same
   shader, with all three of D-096's tile slots pointing at MOUNTAIN, so
   the face gets the atlas's rock strata). Each cell emits for three of
   its six directions, so every shared edge is drawn exactly once.
4. **`cliff_rise`** — the impassable HIGH class is DRAWN 2.0 world units
   above its own elevation.

**Why (4) exists, which the plan did not anticipate.** The plan assumed a
truthful drawing of the class boundary would produce a visible wall. It
does not, and the measurement says so plainly. On the shipped map the
natural height step where two classes meet has a **median of 0.20 world
units along the coast (p90 0.65) and 0.66 at a mountain foot** — under
half a hex's width. The reason is structural rather than a matter of
tuning: elevation is smooth noise and `passability` is a level set on it,
so the boundary can never fall anywhere the ground is already steep. The
first implementation drew **87 rock faces on the whole 8,064-cell map**,
which is the "mechanism correct, shipped numbers do nothing" failure this
project has hit repeatedly — and it looked like success in every other
line of output.

So mountains are lifted onto their own tier. The wall still stands
exactly where `passability` changes, which is the part that is not
negotiable; the lift only makes it tall enough to see. With
`cliff_rise` 2.0 and `cliff_min_step` 0.4 the shipped map draws **363
rock faces**: every land/mountain edge, and roughly a quarter of the
coastline, with the rest of the coast keeping its beach.

**Rejected alternatives:** slope-based rock shading alone (tracks slope,
not passability, so it lies exactly at the boundary — kept as a possible
complement, not as the mechanism); authored cliff prop models along the
boundary (many instances, hard to keep watertight, placement fiddly);
marking cliff-adjacent cells impassable so the sim and picture agree
trivially (deletes visibly flat walkable ground); a `shore_drop` that
pushes the sea below the land (an extra knob, when the land's own height
above sea level already varies the drop naturally and gives the
beach-versus-sea-cliff split for free).

**Consequences and the risk this buys:**

- **`height_at` now has a discontinuity**, and soldiers spill slightly
  outside their squad's cell. The mitigation is structural: the passable
  side's corner heights stay flat and the wall sits exactly on the shared
  edge, so a sampler call near the edge lands on the passable plateau.
  Bounded by a test — for every passable cell, `height_at` at the centre
  and at all six edge midpoints stays inside that cell's own drawn range,
  and never within half a `cliff_rise` of the mountain tier beside it.
  The first version of that test used the cell's CENTRE height as the
  datum and failed on ordinary hillsides, because a hex edge is already
  half a world unit off its centre on a slope; it was measuring the
  terrain, not the hazard.
- **Colour steps with the height.** A corner blends only over the owners
  on its own side of the step. Without that, a mountain plateau is
  painted in the colours of the valley it towers over — rock walls with
  grassland on top, which is what the first render actually showed.
- **The rock face's normal is tilted ~27 degrees up** (`SKIRT_NORMAL_LIFT`)
  while the geometry stays vertical. D-086's rig is one directional sun
  with sky ambient and no shadows, so a truly vertical normal catches
  almost nothing: the first render drew mountain walls at sRGB 0.09, dark
  enough to read as holes cut in the world. This is the same class of
  choice as D-045's "distant squads draw thinner, never smaller" — the
  shading is adjusted so a player can read the picture, and nothing moves.
- **The shipped default map has almost no mountains.** 21.7% of its cells
  are impassable and 20.9% are water, which leaves roughly 66 mountain
  cells and 80 land/mountain edges on an 8,064-cell map. Cliffs are
  therefore mostly a coastal feature there. That is a terrain-generation
  fact, not a rendering one: the lever is `mountain_level` and the
  `/terrain` presets, and it is worth the owner's attention separately.
- Geometry cost is perimeter-sized, as predicted: **57,900 vertices and
  49,110 triangles against 56,448 and 48,384** on the standard map,
  +2.6% and +1.5%. Frame cost on Intel(R) Iris(R) Xe Graphics, terrain
  only: **3.97 ms before all three slices, 4.05 ms after** — against the
  0.5 ms this slice was budgeted.
- **The 1,000-squad absolutes from this session are not usable, and that
  is a host problem rather than a code one.** Four interleaved A/B pairs
  put the difference between −9 and +10 ms, inside a band where the SAME
  code varied by 30 ms run to run; and the unchanged slice-2 build
  measured 52.1 ms early in the session and 181.1 ms three hours later,
  after continuous GPU benchmarking. The delta is therefore reported as
  unresolvable rather than as zero, and the terrain-only row above is the
  figure that means anything. CLAUDE.md's M6 note about worst ticks
  measured while the host was building containers is the same lesson.

**Revisit trigger:** elevation acquiring tactical meaning. D-084 noted
that the rendering/simulation split "stops being free the moment
elevation acquires tactical meaning", and per-edge blocking (the plan's
slice 4, its own decision) is exactly that moment — at which point
`cliff_rise` becomes a thing the simulation can see and this entry needs
re-reading. Also revisit if a terrain preset ever makes mountains common
enough that 2.0 units reads as a mesa rather than a cliff.

---

### D-096 · 2026-08-15 · Accepted — the ground is continuous

**Decision:** the ground stops being a honeycomb of flat hexes. Three
separate causes, all fixed, none of which any number could see:

1. **Vertex colour is per VERTEX.** A shared corner takes the mean of the
   three cells meeting there — exactly the trick D-084 already used for
   heights — and a centre keeps its own. `TerrainGen.biome_color()`
   remains the single source of truth (D-083): the blend is DERIVED from
   it, and the minimap and the terrain preview PNG still read it per
   cell. The preview PNG is byte-identical before and after, which is the
   check that the small picture and the big one cannot have drifted.
2. **The pillow is a tunable**, `TerrainGen.pillow`, shipping at 0.15
   against the old implicit 1.0. The centre vertex now sits at
   `lerp(mean of its own six corners, own elevation, pillow)`. The
   comment that used to live in `surface_field` called the resulting dome
   a feature — "keeps the hex grid faintly readable" — and that
   readability is precisely what the owner asked to be rid of.
   `height_at` reads the same array, so the ground sampler follows and
   cannot disagree with the mesh.
3. **UVs are continuous across cells**, and still derived from the CELL
   rather than from world position — the D-035 rule that makes the nine
   lattice copies agree. Each hex used to be inscribed in its biome's
   atlas tile with a 6% inset and a hashed rotation, so the texture
   restarted at every edge.

**`shaders/terrain.gdshader` is the project's first terrain shader**, and
(3) is why one was needed: a continuous coordinate over an eight-tile
atlas walks out of one biome's tile into its neighbour's, and wrapping it
back into the right tile is a per-fragment decision with no
fixed-function expression. Each cell carries three tile indices, constant
over the cell so interpolation is a no-op — an interpolated INDEX would
ask for tile 4.7 — and each vertex carries its weights over them, which
do interpolate. The fragment samples three times with **explicit
gradients**, because `fract` tears the derivative once per repeat and an
implicit-derivative sample draws a bright seam every few hexes in a
ruler-straight line.

**Two arithmetic details are load-bearing, not fussiness:**

- **`TerrainGen.corner_cells` returns the three owners SORTED.** Float
  addition is not associative, so three owners summing the same triple in
  three different orders can differ in the last bit. Sorting makes
  watertightness a property of the arithmetic rather than of a tolerance.
- **`TerrainChunk.uv_scale` is arithmetic, not a constant.** The texture
  meets itself across the seam only if `scale.x * width`,
  `scale.x * height/2` AND `scale.y * height` are all whole numbers of
  repeats — the middle one because stepping `height` in r moves world x
  as well as z. A scale that only divides the width tears along the
  diagonal seams, which is a defect that looks like a noise bug.
  `vertex_uv` evaluates the coordinate as an integer numerator over a
  fixed denominator so two cells reaching a corner by different
  arithmetic land on the same UV exactly.

**The measurement that chose route B.** The plan offered a single neutral
detail texture (free) against per-biome tiles blended three ways, and
said the decision would be made with a `bench-render` number rather than
an opinion. On **Intel(R) Iris(R) Xe Graphics**, 84x96 map, 200 measured
frames, before and after in one session:

| | terrain only | 1,000 squads / 27,300 soldiers |
|---|---|---|
| before | 4.15 ms | 52.07 ms |
| after (3 taps) | 4.26 ms | 51.98 ms |

**+0.11 ms** on the terrain-only row and a difference at 1,000 squads
that is inside run-to-run noise, against a 2 ms budget. The frame is CPU
bound on soldier derivation — 48 ms of 52 — so two more ground taps are
very nearly free, and the fallback was not needed.

**Rejected alternatives:** bigger or denser atlas tiles (the island seam
is the problem, not the tile size); per-vertex tile indices with `flat`
interpolation (the provoking vertex's biomes would paint the whole
triangle); eight per-biome weights so no index needs interpolating
(eight taps per fragment); de-indexing the fan so each triangle can carry
its own four-biome set (exact, and 2.5x the vertex count for a
difference measured at 0.09% of corners).

**Consequences:**

- **Three tile slots per cell is not always enough**, and the test
  MEASURES that rather than assuming it: a cell whose six neighbours span
  more than three biomes drops the least demanded, and its neighbour may
  drop a different one, so the texture DETAIL can differ across that one
  edge. On the shipped map it is **45 of 48,384 corners, 0.09%**. Colour
  is exact everywhere and carried separately.
- `TerrainGen.build_fields` and `TerrainFields` replace three separate
  O(cells) walks over the same noise. Heights, colours, biomes and
  passability are built together because they are indexed identically and
  share one corner-sharing rule — passing them separately lets a caller
  pair this build's surface with that build's colours, which nothing
  would report.
- Terrain meshing for the standard map costs more at client start:
  **~600 ms to ~1,100 ms** for all 36 chunks, once per match. Two extra
  four-float vertex channels and the per-corner class resolution account
  for it. A fast path for the 99% of corners whose three owners share a
  class is in `corner_heights` and pays for itself; an equivalent fast
  path in `cell_tiles` measured no gain and was removed rather than kept
  on the strength of the argument for it.

**Amendment, 2026-08-15 (same day), on the owner's report that the
transitions were still hard hex-shaped edges.** D-096 as written above
fixes the low-contrast boundaries and does not fix the high-contrast
one, and the distinction is the whole content of this amendment.

**What was wrong.** A mean-of-three corner blend makes every transition
exactly ONE CELL wide. Where the two colours are close — grass to dry
grass, sand to grass — that reads as soft. At sand against water, the
highest contrast on the map, one cell is one HEX: the 50% contour runs
along the hex edges, because that is precisely where the three weights
are equal, and the eye reads the resulting chain of arcs as a scalloped
lattice. An isolated sand cell in open water rendered as a clean
six-pointed STAR, which is the same fact stated at its most obvious.

Feathering harder does not help. A wider soft band centred on the same
contour is still centred on the lattice.

**Two changes, and both were needed — the first alone was measured and
found insufficient.**

1. **The contour moves off the lattice.** Each corner's three weights
   are skewed by a low-frequency periodic noise field sampled at the
   corner's own position (`blend_warp`, `blend_warp_frequency`). The
   boundary meanders across cells instead of along them. Unwarped it
   returns exact thirds, so D-096's original blend is recovered rather
   than approximated.
2. **The band widens past one cell.** A cell's CENTRE takes some of its
   own six (already blended) corners (`centre_bleed`, 0.45). Because a
   corner already carries a third of each of its three owners, averaging
   the six of them reaches the neighbours' neighbours — a roughly
   two-cell transition for three lines of arithmetic and no extra
   sampling.

**The invariant that changed, stated plainly.** D-096 said the centre
vertex carries `biome_color` EXACTLY. That now holds for every cell
whose six neighbours share its biome — most of any map — and is
deliberately relaxed at boundaries, where the point is that the colour
is on its way to being the neighbour's. `biome_color` is still the only
source of colour and the minimap still reads it per cell; the test
asserts the interior case exactly rather than loosening to a tolerance
everywhere, so what survives is a real invariant and not a weaker one
wearing the same name.

**Three things the pictures found that no count could.**

- **The warp alone changed almost nothing.** Its first version moved the
  blend by at most 19/255 — the rendered coastline was pixel-for-pixel
  the same scallop. `FastNoiseLite` rarely approaches ±1, so an
  amplitude that reads as "most of a hex" displaces about a third of
  that. Shipped at 2.0 for that reason, and there is now a test that
  asserts the mean skew on the SHIPPED map rather than that the
  mechanism exists.
- **Pushed harder, black blots appeared along the coast.** Where the
  warp clamps every weight in a cliff group to zero, the blend divided
  near-nothing by near-nothing. It falls back to the unweighted mean of
  the group now.
- **The per-corner sampling was untested and a perturbation proved it.**
  Sampling the warp at the calling CELL instead — which skews every
  corner of a cell the same way and gives a corner's three owners three
  different answers — left the entire suite green, because
  `build_fields` computes each corner once and hands the same cached
  triple to all three owners. The cache made the mesh watertight however
  wrong the arithmetic was. Only calling the function from each of the
  three sides can see it, and a test now does.

**Cost:** ~0.25 s of terrain build at client start on the standard map
(1.47–1.65 s to 1.70–2.20 s, three paired runs), and nothing per frame —
the weights are baked into vertex colours and the shader's existing tile
channel. Every hex corner is computed once and looked up twice more
(a hex lattice has two corners per cell), which is the same
compute-once-index-after shape as `TorusSpace.disk_offsets` and
`elevation_field`; without it the warp's two noise samples per corner
cost a second of build on their own. `TorusSpace.delta` was in the first
draft of the weight function and cost five seconds — the
`distance()`-per-candidate defect in its sixth outfit, and caught by
watching the build time rather than by reading the code.

**What this does NOT fix, deliberately.** The cliff skirts are still
hard-edged and hexagonal in plan, because a cliff IS the passability
boundary and that boundary is per-cell (D-097). Feathering a cliff would
be drawing something the simulation does not have.

**Revisit trigger:** a map whose width and height/2 are coprime, where
`uv_scale`'s granularity forces the repeat count to the full map width
and the texture stretches; or a biome roster large enough that corner
truncation rises out of the tenths of a percent.

---

### D-095 · 2026-08-14 · Accepted — parallel dev instances are isolated by construction

**Decision:** every checkout of this repo — the owner's main clone and
each Claude Code agent worktree — is its own **dev instance**, and an
instance can only ever start, see, and stop its own servers and
clients. The identity has ONE definition, `instance-id.sh` at the repo
root, which derives:

- **instance name** from the git branch (agent worktrees:
  `claude-<session>`; the main clone: `main`), sanitised into a docker
  project fragment;
- **UDP port** as a stable hash of that name into 20000–29999 —
  deliberately far from the historical shared 4433, so a hardcoded 4433
  that sneaks back in fails to connect rather than connecting to the
  *wrong* server;
- **compose project** `edotmw-<instance>`.

The justfile evaluates the script for its `instance`/`port` variables
and threads them everywhere the old shared literals were: every
`docker compose -p`, every `--name`d container, the `down` recipe's
stray-container label sweep, and every client/bot `--port`. The compose
file publishes `${EDOTMW_HOST_PORT}:4433/udp` — **in-container the
server still listens on 4433**, so the bots and `client-test` services
(in-network, reaching `server:4433`) needed no change, and per-project
compose networks keep them scoped for free. The GUI client accepts
`--instance` and puts it in its **title bar** with the endpoint
(`eDotMW — claude-foo  [127.0.0.1:24817]`), so several clients on one
desktop are tellable apart before clicking anything. `just instance`
prints a worktree's identity. `just quick-test` resolves a new
`SANDBOX=auto` parameter to **on** for agent instances (`claude-*`) —
an agent going straight into quick launch is always dev-testing, so it
gets D-077's sandbox by default — and off for the main clone.

**Why:** parallel agents kept killing each other's test sessions. Both
halves were structural: `just down` (and every recipe's teardown trap)
removed containers in the one pinned `edotmw` project regardless of who
started them, and with one shared port a client connected to whichever
instance's server held 4433 — CLAUDE.md already records a load-test
failure mis-diagnosed for a session because of exactly that stray-server
shape. Fixing it by convention ("agents, be careful") is the
declared-but-unenforced pattern this project keeps paying for, so the
isolation is derived, not remembered, and
`tests/test_multi_agent_isolation.gd` fails if a shared literal
(`-p edotmw`, a fixed `--name`, a hardcoded host port or `--port=4433`)
reappears in the justfile or compose file.

**Sharing is explicit, never accidental:** `EDOTMW_INSTANCE` /
`EDOTMW_PORT` override the derivation when the owner deliberately wants
two checkouts talking to one server; nothing else crosses instances.

**Rejected alternatives:** a lock file or registry of running instances
(state to leak, and D-014's teardown discipline says nothing may
outlive its recipe); letting agents share one server with per-agent
match ids (the server is authoritative per-process — one agent's
restart still kills everyone); random free-port allocation at launch
(a client started later could no longer find its server — the port must
be a pure function of the identity).

> **D-087 through D-094 are the M8 planning session, 2026-08-14.** Run
> the way the M9 session (D-068–D-074) was: everything in them is design,
> no code was written, and the owner made the four calls that shape the
> rest in the same session (scope, hosting, whether 20 players is a
> design target, saves). They close Q3, Q5, Q10, Q11, Q13 and Q14 — the
> entire "Blocking M7 / product-level" block of section 2, which dates
> from when Steam was numbered M7. IDs were checked free against `main`
> at fd4ee6e immediately before writing, per the renumbering lesson in
> the editorial note below.

### D-087 · 2026-08-14 · Accepted — M8 is Steam-ready, not launched; and "seamless" closed by inspection

**Decision:** M8's definition of done is **the game is a real Steam
build, proven by private playtests that reach a match entirely through
Steam** — install from a private depot branch, host, invite, play,
disconnect, rejoin. **Public launch is not M8.** Launch (store page,
pricing, marketing) waits on M9's content, because shipping a game whose
matches decide in three minutes (D-056) would earn exactly the reviews it
deserves. M8 and M9 can proceed in either order or in parallel; the
launch gate is both complete.

In scope, each with its own entry below: hosting model (D-088), what a
20-player design target obliges (D-089), reconnection (D-090), anti-cheat
posture (D-091), saves — out (D-092), the platform boundary (D-093), and
the export/upload pipeline plus exit criteria (D-094).

**Q14 is closed here, by inspection.** "Seamless" means one contiguous
wrapped map with no loading screens — and that has been true by
construction since D-008: the torus is a single simulated space, terrain
is one meshed domain drawn nine times (M3 slice 3), and nothing streams.
No streaming work exists in any milestone because none is needed. The
question only stayed open because the word was never pinned down;
recording the definition is the whole decision.

**Rejected alternatives:** *Early Access on current content* — faster
feedback, but the 3–4 minute match problem is structural (D-056 says so
explicitly) and first impressions on Steam are not revisable. *Making M8
the 1.0 launch* — that just reorders the ladder to M9-then-M8 and makes
M8 unplannable until M9's content questions settle; splitting
"Steam-ready" from "launched" keeps M8 executable now.

**Consequences:** M8 produces no public artifact — its output is a
private depot branch and a repeatable playtest loop. The discrete-GPU
bench trigger (Q15, sharpened in section 2) finally becomes reachable
through playtesters' hardware and is folded into D-094's criteria.

**Revisit trigger:** if M9 slips badly enough that an Early Access
launch on partial content starts looking better than silence, that is a
new decision against this one, not an amendment.

---

### D-088 · 2026-08-14 · Accepted — Q3: player-hosted first, official dedicated later

**Decision (the owner's call, 2026-08-14):** at first ship, matches are
**player-hosted**: the host player's machine runs the authoritative
simulation, and remote players connect over **Steam's networking with
relay** (SteamNetworkingSockets / SDR via D-093's boundary), so NAT and
port-forwarding never reach a user. **Official dedicated servers are a
later rung**, not M8 — they are also the eventual fix for the two
limitations this decision knowingly accepts (host-quit and host-trust,
below).

**The measured basis that makes hosting-while-playing viable.** This
question was written when "who pays for servers" looked expensive.
M4/M6 made it small: bandwidth is ~1 KB/s per client (D-042's 933 B/s at
20 players) — 19 remote clients cost a host about **20 KB/s of upload**;
the server is roughly **half a core and ~42.5 MB** at full scale
(D-038/D-040). A machine that can run the client (the expensive half —
D-041) hosts the simulation without noticing.

**Process shape: in-process host, and `loopback_peer.gd` already built
the seam.** The host's game runs the server *in-process* — the same
`SquadSim`/`server.gd` machinery, ticked by D-023's accumulator — with
the host's own client connected through the loopback peer that D-051's
AI clients already use, and remote clients arriving through Steam
sockets. This is not a new architecture: `bot_client.gd` proves N
clients in one process, and `loopback_peer.gd` exists precisely because
a peer is duck-typed to `ENetPacketPeer.send`'s shape. A Steam peer
wrapper implements the same shape behind D-093's boundary. D-002's
authority split (clients send input, server decides) is a protocol
property, not a process property, and is unchanged.

**D-042's contract is a hard requirement on the new transport.** Curve
packets carry no sequence number; in-order reliable delivery is
load-bearing. Steam sockets must run reliable-ordered, and the ordering
test D-042 named
(`test_curve_application_is_last_write_wins_so_order_is_load_bearing`)
applies to the Steam path exactly as to ENet. **ENet stays** for
LAN/direct-IP, docker, bots and the whole test estate — containers have
no Steam and never will, so every existing recipe keeps running without
it (see D-093's fallback rule).

**Two consequences accepted with eyes open:**
- **Host-quit kills the match** for everyone in it. No host migration —
  authoritative-state handoff is a milestone of its own and a fresh
  cheating surface (whoever inherits the server inherits omniscience).
  Dedicated-later is the real fix; until then it is a documented
  property of unranked play.
- **The host is trusted** — they hold the whole truth and the authority.
  D-091 owns this consequence.

**Rejected alternatives:** *Official dedicated first* (recommended by
the analysis for keeping ENet untouched, declined by the owner — player-
hosted reaches playtesters without standing infrastructure or monthly
cost, and the Steamworks integration it forces is needed for D-089's
lobbies anyway). *Player-run headless server as a separate process* —
splits the Steam context across processes (the listen socket needs the
game's Steam session) and buys nothing the in-process shape doesn't.
*Host migration* — see above.

**Revisit trigger:** ranked/competitive play (requires dedicated — see
D-091); playtests showing the host's 0-RTT advantage is felt in play; or
a measured case of host upload/CPU being the binding constraint at real
player counts.

---

### D-089 · 2026-08-14 · Accepted — Q5: 20 players is a design target, and what M8 owes it

**Decision (the owner's call, 2026-08-14):** 20 concurrent players is a
**design target** — the product's headline match, not merely the ceiling
the architecture was sized against. What that obliges, scoped honestly:

- **Discovery:** Steam lobby browser plus friend invites, mapped onto
  the existing lobby (D-048/D-050 — seats, teams, civs, AI). **No
  skill-based matchmaking service** — discovery is lobbies, not MMR
  queues; a matchmaker is a standing service with a population
  prerequisite this game does not have and M8 must not pretend it does.
- **Fill:** a 20-seat match must start without 20 humans. AI players
  (D-051) fill empty seats — already real (`just run-server AI=3`), the
  lobby already seats them.
- **Resilience:** drop-OUT hands the army to an AI (D-090); drop-IN is
  D-090's repossession — a returning human reclaims their own seat, and
  a NEW human may take over an AI-held seat mid-match through the same
  machinery. That last is what makes a 20-player match fillable in
  practice rather than only at the lobby screen.

**Rationale:** the alternative reading (engineering ceiling, design for
2–8) was recommended and declined. Taking 20 seriously as design means
the fill/resilience machinery above is core product, not tooling — a
20-human lobby that dissolves on its third disconnect is not a 20-player
game. Note the architecture side owes nothing new: D-018/D-020's budgets
were always sized at 20, and D-042 measured transport at 20.

**Rejected alternatives:** matchmaking service (above); spectator-slot
drop-in (observers are cheap under D-003 — a spectator is a client with
maximum vision — but it is scope, and nothing in the 20-player claim
needs it; noted for later, not built in M8).

**Consequences:** M8's headline verification (D-094 criterion 8) is a
20-seat match through Steam networking with real remote humans in it.
The per-connection-ownership defect family (D-038's amendment) becomes
seat-identity work in D-090 — binding by SteamID, not connection.

**Revisit trigger:** if real playtests show the fun ceiling is well
below 20 (coordination, readability, pacing), the design target moves
and this entry is superseded — the engineering ceiling stays where
D-018 put it either way.

---

### D-090 · 2026-08-14 · Accepted — Q10: reconnection is repossession; AI holds the seat; rejoin is also the desync repair

**Decision:** a human's mid-match disconnect no longer wipes their army
(superseding D-033's wipe-on-disconnect for humans; explicit leave via
D-075 also hands off rather than wiping). Instead:

1. **The seat passes to an AI immediately.** D-051 built exactly the
   right object: an AI player is a client without a socket, held to
   every rule a human is. Takeover is seating one on the abandoned
   army's curves — no grace-period limbo where 19 players fight a
   statue.
2. **Reconnection is repossession.** A returning player (identified by
   **SteamID, not connection** — the per-connection ownership cache was
   already this project's bug once, D-038's amendment) reclaims the
   seat from the AI at any point while the match runs. There is no
   timeout after which return is refused: the AI holding the seat IS
   the grace mechanism, indefinitely.
3. **Rejoin is architecturally cheap, and that is not luck.** A
   rejoining client is a fresh join: D-025's reveal semantics already
   define how any client learns current state — horizon-clipped curves,
   sent fresh, no synthetic catch-up. The one non-obvious obligation:
   persistent-explored building fog must be replayed as the
   **ever-revealed set** on rejoin, exactly the distinction its hash
   rule already warns about.
4. **Desync recovery is the same door.** Q10's second half gets the
   same answer: the client already computes state hashes continuously;
   on mismatch, the recovery policy is **drop and rejoin through the
   repossession path** — fresh curves rebuild the world from truth.
   No incremental repair protocol; rejoin *is* the repair, and it is
   cheap for the same D-025 reasons. (Server-side, a desync report is
   logged with the replay per D-016 — forensics first, the M1 lesson.)

**Rationale:** every alternative builds new machinery; this composes
three things that exist (AI clients, reveal semantics, state hashes)
and one thing M8 needs anyway (SteamID identity). For D-056's eventual
1–2 hour matches, wipe-on-disconnect would be brutal to the
disconnected player's *team* (D-050 shared vision makes armies
interdependent) — the AI holding the line is what keeps one dropped
connection from deciding a team match.

**Rejected alternatives:** *grace-period pause* (PA-style — freezes 19
players for one); *wipe after a timeout* (punishes the team, and the
timeout constant has no defensible value); *incremental desync repair*
(a diff protocol against curve state — large, and rejoin already
achieves the same end).

**Consequences:** the join handshake carries SteamID → seat binding
(wire change, D-094 criterion 3's version handshake is the natural
place); `match_state.gd`'s elimination definition needs one amendment —
a seat is abandoned only if its AI is also dead; D-051's AI must cope
with inheriting any mid-match position, which `ai-ladder` cannot fully
exercise (it never inherits) — a scripted takeover scenario is D-094
criterion 6's job.

**Revisit trigger:** if AI-holds-indefinitely is abused in practice
(a losing player "AFKs behind a competent AI"), add a forfeit vote or
an idle-seat rule — a social-rules patch, not a rewrite of this shape.

---

### D-091 · 2026-08-14 · Accepted — Q11: the server IS the anti-cheat, and the host is trusted, stated plainly

**Decision:** no kernel anti-cheat, no third-party client-side
anti-cheat, VAC at Steam's defaults only. The posture is the
architecture, which was built for this from D-002 on:

- **A client cannot assert state** — it sends orders; the server
  validates every one through the shared helper (M3), and refuses what
  the player doesn't own.
- **A client cannot know what its player shouldn't** — fog is curve
  *gating* (D-003/D-004/D-025): concealed state never reaches the wire.
  A maphack reads memory that isn't there.
- **A modified client changes only its own picture** — soldier
  positions are client-derived cosmetics (D-006, one-way by
  construction).

The two residual surfaces, named so nobody rediscovers them: what a
horizon-clipped curve still leaks (D-003's own note — intent within the
horizon), and **the host under D-088** — whoever hosts holds the whole
truth and the authority, so a modified host is omniscient and
unaccountable. **Accepted for unranked/friends play and documented as
such; ranked or competitive play requires official dedicated servers
and is explicitly gated on D-088's later rung.** Replays (D-016) are
the accountability tool that exists today: byte-identical to the wire,
they make an accusation checkable after the fact.

**Rejected alternatives:** kernel/client anti-cheat (an arms race this
project cannot staff, aimed at the one surface — the client — the
architecture already made low-value to cheat); trusting no host and
shipping dedicated-only (rejected by D-088's owner call, and unranked
friends-lobby play doesn't warrant it).

**Consequences:** none in code for M8 beyond what D-088/D-090 already
require. The word "ranked" appearing anywhere in a future milestone is
this entry's tripwire.

**Revisit trigger:** ranked play; or evidence of host cheating being a
practical problem in unranked lobbies rather than a theoretical one.

---

### D-092 · 2026-08-14 · Accepted — Q13: no mid-match saves; reconnection and replays are what the need decomposes into

**Decision (the owner's call, 2026-08-14):** M8 ships no save/resume.
The realistic failure a long multiplayer match faces is *a player
dropping* — D-090 covers that with AI takeover and repossession. The
other thing "saves" usually means — reviewing a finished match — has
been free since M1: replays are the curve log (D-016). What remains is
genuinely "suspend a live multiplayer session and resurrect it later",
which requires state serialization with versioning plus a resume
ceremony every participant must attend, for an event (all N players
agree to stop and all N return later) that lobby-discovered matches
essentially never produce.

**Rejected alternatives:** server-side session snapshot (feasible —
packed arrays serialize cleanly — but the cost is the ceremony and the
versioning, not the bytes); client-side saves (meaningless in an
authoritative-server game).

**Revisit trigger:** two named. (1) M9's real 1–2 hour matches showing
abandonment pain that repossession doesn't cover — measured by
playtest, not assumed. (2) A single-player or skirmish-vs-AI mode
becoming a product surface — there the ceremony collapses (one human,
server in-process per D-088) and saves become cheap enough to justify
themselves.

---

### D-093 · 2026-08-14 · Accepted — the platform boundary: GodotSteam, and D-021 amended by exactly one category

**Decision:** Steamworks reaches this project through the **GodotSteam
GDExtension**, and D-021 gains a second sanctioned GDExtension
category: **platform integration**. D-021's original category
(performance kernels, on measured evidence only) is untouched and still
has zero members. Three constraints keep the amendment from becoming a
hole:

1. **One script names Steam.** Every Steamworks call lives behind a
   single boundary script (`steam_platform.gd` or equivalent); no other
   `.gd` file mentions Steam at all, and **a test enforces it** — the
   same falsifiable-by-grep pattern as D-046 criterion 3 (no script
   names a civ) and D-086's lighting-rig guard. This is the project's
   proven mechanism for keeping a rule true after everyone stops
   looking.
2. **Absent Steam costs Steam, never the game.** No Steam context —
   docker, CI, bots, LAN, a clone that never installed the extension —
   means the boundary reports unavailable and everything else works
   over ENet exactly as today. The precedent is D-081's empty
   `model_id`: a failed integration degrades fidelity (here: no
   relay, no lobbies, no invites), not function. The entire existing
   test estate runs Steam-less by construction, which is also why the
   Steam path needs its own verification story (D-094).
3. **Still no C#** (D-021's yes/no answer stands): GodotSteam's
   GDExtension build, not the .NET binding; no `.csproj` appears.

**Rationale:** D-088 (relay) and D-089 (lobbies, invites) are
impossible without Steamworks, and Steamworks has no GDScript-native
path. The alternative reading — that D-021 forbids this — would make
D-021 decide product scope, which was never its job; it was a toolchain
cost/reversibility decision, and a pinned prebuilt extension behind one
script is toolchain-cheap and reversible.

**Rejected alternatives:** shipping with no Steamworks at all (steamcmd
upload needs none — but D-088/D-089 die with it); the C# Steamworks
bindings (D-021); hand-rolled GDExtension against the Steamworks SDK
(GodotSteam exists, is maintained, and is the community-standard
binding).

**Consequences:** the extension binary is a pinned dependency fetched
by bootstrap (the `tools/` pattern), never committed; `.godot-version`
gains a sibling pin. `just doctor` learns to report Steam availability.
The boundary script is the natural home for the SteamID identity D-090
needs and the lobby mapping D-089 needs.

**Revisit trigger:** GodotSteam abandonment or a Godot upgrade it lags
badly (the standing risk of any binding); at that point the fallback
ladder is: pin harder, then hand-roll the minimal surface actually used
(sockets, lobbies, identity — small by then, since the boundary script
documents exactly what is used).

---

### D-094 · 2026-08-14 · Accepted — M8's exit criteria, written before the code

**Decision:** M8 is complete when all of the following hold. Written
before any M8 code exists, per the standing rule (D-022, D-026, D-046,
D-074 — and D-085's reconstruction is the cautionary tale for skipping
it). Every new check below is subject to the observed-to-fail rule.

1. **Export:** `just export` produces a runnable Windows client build
   and a Linux headless server build from a clean clone (the latter is
   what docker already proves possible, and is the dedicated-later
   seed). Build version is stamped from one source of truth.
2. **Upload:** a `just` recipe pushes a build to a Steam depot via
   steamcmd, to a **private** branch; a fresh machine installs and runs
   it from Steam. (No store page, no public visibility — D-087.)
3. **Version handshake:** the join flow carries a protocol version and
   the SteamID seat identity (D-090); a mismatched client is refused
   loudly at join with a message a player can act on. Verified by
   connecting a deliberately version-bumped client and watching the
   refusal — this criterion exists because Steam's rolling updates make
   mixed versions routine, and today's protocol has no version field
   at all.
4. **Host flow:** a host starts a match from inside the game (server
   in-process per D-088), a second machine joins via Steam invite and
   via the lobby browser, and no participant touches an IP address or
   a router. LAN/direct-IP still works with Steam absent (D-093).
5. **Transport contract:** a real match runs over Steam sockets with
   reliable-ordered delivery, the state-hash machinery reports zero
   desyncs on it, and D-042's ordering test is extended to cover the
   Steam peer wrapper. The bots/test estate continue to run entirely
   over ENet/loopback, Steam-less.
6. **Reconnection (D-090), each leg observed to fail first:** kill a
   client mid-match → its AI takes over within a tick and plays on;
   the same human rejoins → repossesses the seat, and post-rejoin
   state hashes are clean (including the ever-revealed building-fog
   set — the known trap); a second human takes over a different
   AI-held seat mid-match (D-089's drop-in). A scripted takeover
   scenario covers the part `ai-ladder` structurally cannot (an AI
   inheriting a mid-match position it didn't build).
7. **Platform boundary (D-093):** the no-script-names-Steam test
   exists and has been observed to fail; the full unit suite passes in
   docker with no Steam present (automatic, but assert it — that is
   the fallback rule proven, not assumed).
8. **The 20-seat match (D-089):** one match, 20 seats filled — at
   least 3 remote humans over the real internet (not loopback, not
   LAN), the rest AI — through Steam networking, completing with a
   decided result or a clean cap. Bandwidth, worst tick and µs/squad
   quoted **with their counts**, per the standing rule, against
   D-020's budget and D-042's measured baseline.
9. **The discrete-GPU number (Q15's armed trigger):** `just
   bench-render` run on at least one discrete GPU — playtesters'
   machines finally make this reachable — at ship map size and squad
   count, adapter name in the output. This settles D-085 criterion
   11's caveat as a side effect.
10. **A human plays a full match end-to-end through the Steam-installed
    build** — install, lobby, match, disconnect/rejoin, finish. The
    criterion-14 lesson (D-085), applied from day one this time: this
    is the criterion nothing automated substitutes for, and M8 is
    "landed, not complete" until it is checked.

**Consequences:** criteria 3, 5 and 6 are wire-protocol work and should
land early — they are the part every other criterion sits on.
Criterion 8 is the milestone's headline and its long pole: it needs
real humans on real networks, which means the private-branch loop
(criteria 1–2) is the first thing to build, not the last.

**Revisit trigger:** any criterion found unverifiable as written gets
amended here in the open, not quietly reinterpreted — the D-043
retroactive-audit lesson.

---

> **Editorial note on D-081 through D-085, added 2026-08-11.** M7's art
> work landed under decision IDs D-063 through D-067 — but by the time it
> shipped, those IDs had already been taken by real, unrelated entries
> (D-063 is the HUD/camera-yaw decision below; D-065 is formation shape;
> D-066 is building damage scale; D-067 is squad shoving). `CLAUDE.md`
> cites the art work at the collided IDs anyway, and the only trace of
> the actual art decisions in this file was a two-line Q12 closure
> pointing at a `D-064` that was never written. A grep for style keywords
> (`vertex animation texture`, `VAT`, `gdshader`, `silhouette`, `low-poly`,
> `toon`, `atlas`) across the whole file before this note returned exactly
> two hits, both in that closure.
>
> D-081 through D-085 below reconstruct those decisions from the shipped
> code and from `CLAUDE.md`'s own M7 narrative, at fresh unused IDs, so
> this file has something to check before the next art decision is made.
> They are dated to when the work is understood to have landed (D-081's
> 2026-08-09 matches the Q12 closure's own date), not to today — but they
> were **written today**, after the fact, which is the opposite of this
> project's own rule that exit criteria (D-022, D-026) are written down
> *before* the code. D-085 in particular is reconstructed without ever
> having seen an original numbered list; where `CLAUDE.md` cites a
> specific criterion number (4, 11, 14) that number is preserved, and
> everything else is inferred from what the same section of `CLAUDE.md`
> says landed. Treat D-085 as lower-confidence than the others for that
> reason.
>
> **Renumbered again on merge, same day.** This block was first drafted
> as D-075 through D-080. Before it merged, `main` independently gained
> its own real D-075 — "leaving a match returns to the lobby, and no
> humans means no server" (below) — landing the same day this block was
> written. Rather than let a second, unrelated decision collide onto an
> ID this block had already claimed, everything here was shifted up by
> six (D-075→D-081 … D-080→D-086) at merge time. The lesson is the same
> one the rest of this note describes at one remove: picking a fresh ID
> only prevents a collision with what exists at the moment you pick it,
> not with a decision landing on `main` from a different branch in
> parallel. Check `main` immediately before merging, not only before
> writing.

### D-097 · 2026-08-15 · Accepted — build sites are contestable shared state

**Decision:** A pending foundation stops being a private note the server
keeps for one squad and becomes a **build site**: authoritative, replicated
to its owner, and contestable by everyone else.

1. **Shared.** Any squad of the owner's that may build that def can work an
   existing site. Progress **pools** — two gatherers on one foundation build
   it in half the time, three in a third.
2. **Persistent and owner-visible.** A site is replicated to its owner (only)
   and drawn on the ground until it is built or destroyed. No timeout.
3. **Contestable.** A site does **not** reserve ground against enemies. If an
   enemy completes a building overlapping it, the site is destroyed, and
   whatever was spent on it is gone.
4. **Demolishable.** An owner may destroy their own completed building
   outright. **No refund**, matching D-055's razing — a building is a sunk
   cost whichever way it comes down.

**Rationale:** The immediate cause was a smaller thing — a build order was
silent until the builder arrived, so a distant site was indistinguishable
from a misclick for many seconds. The first fix was a client-side marker
that faded after nine seconds. Playing with it made the real shape obvious:
a mark that only YOU can see, that no other builder can act on, and that
vanishes on a timer is a *notification*, when what the player wants is a
**plan** — something they lay down, come back to, and reinforce.

Pooling rather than merely surviving one builder's death (the alternative
considered) is what makes helping a real decision: sending a second crew has
a visible payoff, so "finish this wall NOW" becomes a thing you can spend
squads on.

Not reserving ground is the deliberately harsh half, and it is what stops
sites being free territory. A site costs nothing to place and would
otherwise be a way to claim a map by spamming foundations nobody can build
over. Making it losable turns forward-building into a genuine race, which is
the interesting version.

**This crosses a boundary on purpose, and the boundary is worth naming.**
The marker as originally built was cosmetic and one-way in the spirit of
D-006 — the simulation could never read it. A build site is the opposite:
authoritative state that happens to be drawn on the ground. The mark is now
the *rendering of* the site, not the thing itself, and the D-006 discipline
continues to apply to the rendering only. Anything the player can contest,
lose, or spend squads on is simulation state and lives server-side.

**Rejected alternatives:**

- *Keep it a client-only marker* (rejected — cannot be worked by another
  squad, cannot be contested, and cannot survive a reconnect. Every property
  asked for here requires the server to own it.)
- *Sites reserve ground against enemies* (rejected — a free, instant,
  uncontestable land claim. `_footprint_conflict` already counts pending
  intents this way, which is fine among your OWN builds and has to be
  relaxed for enemies.)
- *Redundancy without pooling* (rejected — a second builder that changes
  nothing visible is not a decision the player can feel.)
- *Partial refund on demolish* (rejected — D-055 gives nothing back for
  razing, and two different answers for "this building came down" is the
  kind of inconsistency that gets discovered as a exploit rather than as a
  rule.)

**Consequences:**

- `_pending_builds` moves from a per-squad dictionary to a site list with its
  own ids, and gains a wire message gated to the owner (fog rules apply —
  D-004 — but a site is only ever sent to its owner anyway).
- Construction rate becomes "sum of the crews present", not a fixed rate.
- A new order opcode for demolition, validated for ownership server-side
  (D-002) like every other order.
- `_footprint_conflict` distinguishes own-pending (blocks) from
  enemy-pending (does not).
- **Careful with the completion path:** destroying a site when an enemy
  building lands on it has to go through the same dirty-flag and passability
  refresh a real destruction does, rather than a second implementation built
  to match it by hand — the trap D-076's upgrade path already documents.

**Revisit trigger:** If sites become the dominant way players deny ground
(the opposite failure to the one clause 3 prevents), or if pooled
construction makes early rushes decide matches faster than D-056's 1-2 hour
target allows.

---

### D-096 · 2026-08-14 · Accepted — continuous wall placement, rasterised occupancy

**Decision:** A wall-family structure (`footprint_radius == 0` — wall, gate,
garrison wall, garrison gate, access tower) stops being "one building that
owns one hex cell". It gains a continuous world position and a continuous
rotation, and the cells it blocks — and the cells that carry its tier-1
walkway — are **derived by rasterising its swept rectangle**, rather than
being the one cell it was placed on.

Concretely:

- `BuildingSim` keeps `_cell` as the **anchor** (the cell the structure's
  centre falls in). Everything that buckets by cell — combat targeting,
  vision stamping, the minimap, selection — keeps working untouched.
- It gains `_offset`, a sub-cell continuous displacement in world units, and
  `_facing` becomes a continuous angle for the wall family instead of one of
  six directions. True position is `space.to_world(cell) + offset`.
- `occupied_cells()` / `blocking_cells()` rasterise the rotated
  `mesh_size.x × mesh_size.z` rectangle centred on that true position.
- A placement drag lays segments **end to end along the true dragged line**
  at exact `WALL_LENGTH` spacing, each rotated to the line's real angle —
  not one segment per hex cell.

**Rationale:** Grid-locked walls were the most-reported visual problem in
playtesting, and every symptom traced to the same root. Segments snapped to
cell centres and to one of six angles cannot follow a shoreline, a ridge, or
any line a player actually wants to hold. A bend left a gap that had to be
plugged with a cylindrical post. A gatehouse drawn wider than one cell was
overlapped by the very walls meant to meet it, because it occupied one cell
while spanning two.

The insight is that the hex grid was never load-bearing for a wall's
*appearance* — only for its *effect*. **D-008 is untouched**: cells remain
the simulation's spatial index, and flow fields, vision and combat all still
work on them. What changes is only how a wall's occupancy is *computed*.

**The failure mode this must not have** is a wall that looks solid and has a
pathing hole units walk through. Deriving blocked cells from a segment's true
swept span, rather than from its centre cell, is precisely what prevents it:
a segment that visually crosses three cells blocks three cells. This is the
"looks fine, quietly wrong" class this project keeps getting bitten by, so it
gets an explicit test — a run dragged at an arbitrary angle must leave **no**
unblocked cell along its length, and that test must be observed to fail
before it is trusted.

**Rejected alternatives:**

- *Keep cell placement, render continuously* (rejected — the picture and the
  simulation would disagree about where a wall stands. A player would aim at
  a wall that blocked somewhere else, which is worse than an ugly wall.)
- *Drop the hex grid for a square one* (rejected — costed at the same time.
  `TorusSpace` is load-bearing under ~15 files, and hex's isotropy is what
  makes vision and combat disks clean, per the standing `disk_offsets` rule.
  The grid was never the problem; the one-cell-per-wall model was.)
- *One cell per segment, tolerating duplicates and skips* (rejected —
  `WALL_LENGTH` (~1.77) and hex spacing (~1.73) are close but NOT equal, so a
  run at an arbitrary angle silently skips cells. That is exactly the
  walk-through-a-solid-wall bug above, arrived at by accident.)

**Consequences:**

- The wire carries a continuous offset and rotation per building.
- `_footprint_conflict` becomes a span-overlap test for the wall family
  rather than a cell-equality test.
- The cylindrical joint post is **replaced by an authored round bastion**,
  generated per wall style in `art/buildings/` so a stake fence gets a
  palisade roundel and a stone wall gets a stone drum. Its radius comes from
  the incoming segments' real angles, so one shape serves a corner, a T and a
  four-way junction alike. The post it replaces was a `StandardMaterial3D`
  tinted with `mesh_color` — the *primitive fallback* colour, which the
  authored wall never renders — which is why it read as a differently
  coloured spike rather than part of the wall.
- The garrison gate becomes an exact multiple of `WALL_LENGTH`, and a wall
  run snaps to its true edge instead of into its middle.
- This is **not** a step toward continuous-space simulation. Squads still
  move on flow fields over cells, elevation still does not occlude, and the
  tick still advances on cells. Any proposal to make combat or pathing
  continuous is a separate decision and does not inherit this one's rationale.

**Revisit trigger:** If per-segment rasterisation shows up in tick profiling
at D-018's full scale, or if any system starts needing a wall's continuous
position for a *simulation* answer rather than a rendering one — the latter
would mean the discrete/continuous split this decision depends on has leaked.

---
### D-087 · 2026-08-14 · Accepted — forests are made of trees: biome-density nodes, 1-minute trees, authored variants, fellings on the wire

**Decision:** Resource nodes stop being a uniform sprinkle of rich markers
and become terrain-shaped vegetation, with everything downstream of that
adjusted to match. Six coupled parts:

1. **Placement is a density field, not a stride.** `Economy.generate`
   rolls each cell against per-biome densities shaped by the SAME
   moisture field `biome_at` classifies with (`TerrainGen.MOISTURE_DRY` /
   `MOISTURE_FOREST` are constants now so the two cannot drift): forest
   cells are 65–98% trees riding moisture, grassland carries groves that
   thicken toward the forest line plus orchards in the mid-moisture band,
   dry grassland gets sparse hardy trees and its old gold cadence, and
   beaches grow the odd palm. The per-cell roll is an FNV hash of the
   quadrant-local index and the terrain seed (Combat's `_roll_unit`
   idiom), so placement stays deterministic and inherits map symmetry by
   construction. Measured on the Standard 84×96 map: **1,920 natural
   nodes vs ~134 before — 14x** (the goal said "target 15x"), one tree
   per ~4 cells, total map stock 334k vs ~322k before.

2. **Trees are small and quick; ore stays rich and held.** Per-kind
   stock: `TREE_STOCK` 105 for wood/food — sized so one shipped gatherer
   squad (5 × 0.35/s) works a tree out in **~60 s**, pinned against the
   shipped def by a test (D-066's lesson) — and `RICH_STOCK` 2400 for
   gold/stone, which keep the "place worth holding" economics (D-039).

3. **Stone moved to the mountain FOOT.** The old generator put stone ON
   mountain/peak cells, which `passability()` marks unwalkable — every
   naturally placed stone node was unreachable scenery, and the AI's
   whole give-up-on-unreachable-nodes mechanism (D-034's amendment) was
   built against exactly these. A foot cell (walkable, bordering
   mountain) is reachable by construction; a test now asserts every
   natural stone node sits on passable ground.

4. **A worked-out tree retargets its crew.** With trees a minute deep a
   crew retires one per haul cycle; making the player re-issue the order
   per tree would be micro tax, so `Economy._retarget` walks
   `TorusSpace.disk_offsets(RETARGET_RADIUS=8)` (nearest-first since
   D-067) for the closest surviving node of the SAME kind — never
   substituting kinds, which was the AI's own old bug — and releases the
   crew if none stands. Deterministic, server-side, replay-safe.

5. **Fellings are a wire event** (`S2C_NODES_DEPLETED`), fog-gated per
   client exactly as reveals are (D-025's shape): sent when a client that
   KNOWS the node can SEE the cell — immediately for whoever is standing
   there, on next sight for a player behind the fog, never for one who
   never returns, whose client keeps drawing the tree (a building
   ghost's staleness, D-030). The fresh-node scan skips already-dry
   nodes, so a late scout is never told a stump is a resource. The
   client erases the node on receipt (AI targeting and the minimap read
   `nodes`) and queues the felling for the renderer.

6. **The client draws forests, not markers.** 50 authored tree models —
   10 species × 5 variants, split from the hand-authored
   `tree-variants.glb` by the same `split_markers.gd` pipeline (groups
   discovered, not listed) — are picked per cell by `ResourceVisuals`,
   a new all-static pure class (the RenderCull/SelectionPick split):
   species pools follow biome and moisture (wet forest swaps toward
   willow/cypress), boundary cells borrow a neighbour's pool 35% of the
   time so treelines fray instead of snapping along the noise threshold,
   and yaw/scale jitter comes from per-cell hashes. Trees batch into one
   MultiMesh per (16-cell chunk, model) — thousands of trees cannot be
   thousands of Node3Ds — with the torus tax paid per CHUNK per frame
   (D-035). A felled tree leaves its chunk and becomes a short-lived
   individual instance playing `fall_pose`: an accelerating tip about
   its base, then a sink; ore sinks without tipping. Trees stand at
   0.60–0.92 of authored size because the source canopies (~2.5 world
   units) are wider than a cell and full-size dense forest merged into
   a single blob on screen.

**Rationale:** The goal was visual (forests that look like forests,
aligned to the ground, with variety and a felling animation) but the
honest version demanded economy changes: many small nodes is a different
resource model from few rich ones, and a felling animation needs the
client to LEARN of depletion, which nothing on the wire carried — stock
was deliberately never replicated (D-028). Fog-gating the new event per
client rather than broadcasting keeps D-025's "you learn what you can
see" intact for the map itself.

**Rejected alternatives:** Replicating remaining stock per node
(constantly changing state on the wire for a number the client only needs
one bit of); client-side depletion inference from gather traffic (bots
and fog make it unknowable); one MeshInstance3D per tree (the M4 `by_id`
shape: thousands of scene nodes for things that never individually move);
per-tree lattice-offset updates (torus tax per tree per frame — paid per
chunk instead); trees as passability obstacles (a forest you cannot walk
through changes flow fields and D-007's sharing claim — explicitly out of
scope); gating the load-test verdict on `nodes_felled > 0` (a felling
needs hall + crew + 60 s of gathering, so the gate would pin every run to
~3 minutes — the exact stale-timing trap D-031 set for `test-load 4 40`;
it is a printed metric instead, asserted by running long and reading it).

**Consequences:** Bots now put produced gatherers to work (they had
produced and never ORDERED them for two milestones, so the whole haul
cycle ran under the load test for the first time) and report
`nodes_felled` in the verdict line. Total map resource dropped ~0% on
Standard but the map's WOOD is now ~1,438 trees × 105 rather than ~30
nodes × 2400 — armies chew through a forest front visibly. The
`_explored` client-side gate on node drawing was removed: the server has
fog-gated node knowledge since D-061, and double-gating hid nodes
revealed by an ally's shared vision (D-050). `test_economy`'s density
guards inverted for trees only (dense woods asserted, scarce ore still
asserted).

**Revisit trigger:** If gatherer stats change, `TREE_STOCK` must move
with them (a test pins the ~60 s relationship). If tree counts grow past
~8k (Huge maps) and chunk rebuilds or the per-node placement pass show up
in a frame profile, promote placement to a bulk pass. If forests ever
gain gameplay meaning (concealment, passability), that is a new decision
— this one is explicitly cosmetic-plus-economy.

### D-086 · 2026-08-11 · Accepted — polished low poly: the lighting layer the game never had

**Decision:** The art style question ("low poly vs cartoon vs the current
method") had a false premise — `art/lib/geom.py` exposes exactly two
primitives (`box`, `prism`), every shipped model runs 72-256 triangles
against a 300/460/400 budget (D-081), and the shading is already flat
Lambert with no specular. The game is already low poly, at the extreme
end. Nothing about it is geometry-limited.

What separated "low poly", "cartoon" and "the current method" turned out
to be the lighting layer, and the project had almost none: one
`DirectionalLight3D`, a flat `BG_COLOR` navy void, a constant blue-grey
ambient, no shadows, no sky, no tonemap, no fog, no post-processing —
duplicated by hand across `client.gd`, `bench_render.gd` and
`model_preview.gd`. The chosen direction is **polished low poly**
(Northgard / Bad North) over cartoon/toon, because the entire cost is in
that lighting layer plus a palette re-tune — it needs no change to the
asset pipeline, unlike toon's outline pass (see Rejected alternatives).

**What shipped:**

1. **`world_look.gd`** (`class_name WorldLook`, all-static, the same
   convention as `render_cull.gd`/`formation.gd`/`hud_layout.gd`) — the
   one definition of the rig, replacing three hand-copies. Guarded by
   `tests/test_world_look_is_the_only_light.gd`, which scans every script
   outside `world_look.gd` for a direct `DirectionalLight3D.new()` or
   `Environment.new()`. Observed failing before trusting it, per this
   project's standing rule: a stray construction was added to
   `hud_layout.gd`, the test caught it, then it was removed and the test
   passed again.
2. **Sky, sky-sourced ambient, ACES tonemap, depth fog** — `BG_SKY` with
   a `ProceduralSkyMaterial` replaces the navy void; ambient now samples
   the sky (`AMBIENT_SOURCE_SKY`) instead of a constant colour, which is
   the change that does most of the work, because flat-shaded geometry
   lit by a single hard light plus a flat ambient term reads as
   cardboard; `TONE_MAPPER_ACES` replaces no tonemap at all; depth fog
   ties its colour to the sky horizon for aerial perspective at RTS zoom
   (camera height 8-31 on the shipped map). Measured cost: negligible —
   54.26 ms mean at 1,000 squads against 53.93 ms before, on the same
   hardware, same run shape.
3. **Terrain palette re-tuned** (`terrain_gen.gd:biome_color`) — ACES
   compresses highlights and desaturates midtones, and sky ambient pushes
   everything cooler, so the pre-existing 8 biome colours read muddier
   than authored. The two darkest biomes (deep water, forest) were lifted
   the most since they were closest to crushing toward black; land biomes
   were warmed slightly to offset the sky tint. Relative ordering
   (deep water darker than water, forest darker than grassland) was kept
   on purpose — that hierarchy is what a player reads at a glance.
   `biome_at()`, which actually gates passability, is untouched.
4. **Shadows were evaluated and explicitly deferred**, not shipped — see
   Rejected alternatives.

**Measurement, taken before spending anything (Step 0 of this work):**
`just bench-render` on Intel Iris Xe, native, Forward+, through the same
cull+LOD path `client.gd` uses (`bench_render.gd` mirrors
`RenderCull`/`_detail_for`):

| squads | soldiers | ms mean | ms worst | fps mean | squads drawn |
|---|---|---|---|---|---|
| 0 | 0 | 2.09 | 3.22 | 477.8 | 0 |
| 100 | 2,730 | 5.48 | 7.85 | 182.5 | 64 |
| 250 | 6,825 | 13.06 | 14.29 | 76.6 | 183 |
| 500 | 13,650 | 26.97 | 36.34 | 37.1 | 363 |
| 1,000 | 27,300 | 53.93 | 54.55 | **18.5** | 741 |

This discharges D-085 criterion 11 (partially — see Rejected
alternatives on the discrete-GPU point) and answers M7's open question
about the real cost of VAT-animated authored models: **M5's 35.66 ms /
28 fps at 1,000 squads on this same Iris Xe was measured with primitive
capsules, before authored models landed.** The authored-model number is
53.93-54.26 ms / 18.4-18.5 fps — **51% slower at full scale**, not the
several-fold-*under*-stated figure CLAUDE.md's M4 section warns about for
the unrelated 0.72 µs/soldier derivation figure. The animated-vertex cost
is real, and it was unmeasured until this decision.

**Rationale:** A presentation pass is style-neutral and is a prerequisite
for either "polished low poly" or "cartoon" to look intentional rather
than unfinished — building it first, then judging the two options with a
picture in hand, is cheaper than judging them in the abstract and
possibly re-doing the judgement. Once built, the picture matched
"polished low poly" well enough (see `artifacts/client-frame.png`,
D-086) that committing further to toon was not worth its cost (below).

**Rejected alternatives:**
- **Cartoon / toon shading** (`diffuse_toon` + rim light + outline).
  Rejected for now, not permanently. The diffuse/rim half is nearly free
  — a token change in three shaders and some parameters in
  `SoldierParams`. The outline half is not: an inverted-hull outline
  doubles the vertex shader over every soldier, **including the VAT's
  three `texelFetch`es per vertex**, and a screen-space edge pass needs a
  Forward+ `CompositorEffect` that `test-client`'s Mesa software
  rasteriser (`gl_compatibility`) cannot run at all — the automated
  visual check would go blind to it. Given Step 0's number, spending
  that on top of an already over-budget frame at full scale was not
  justified without a stronger reason to prefer it over polished low
  poly.
- **Shadows.** Evaluated against Step 0's own stated gate ("if the
  current frame is already at or over budget on this hardware, shadows
  come out of scope... decide this from the number, not in advance"). At
  1,000 squads the frame was already 53.93-54.26 ms — 3.2x a 60 fps
  budget and under 20 fps outright — before spending anything on a
  second render pass per shadow cascade. Deferred, not rejected outright:
  250 squads (76.6 fps) has real headroom, so a squad-count-gated shadow
  pass is a reasonable future revisit, not ruled out here.
- **Full re-author of the unit/terrain palette from scratch.** Rejected
  in favour of re-tuning the existing 8 terrain colours and leaving
  `SoldierParams` colours alone. A `SoldierParams` change requires
  `just build-assets` and a re-commit of the hash-gated `generated/`
  tree (D-081); the lighting change alone got most of the visual delta,
  so that cost was not spent.

**Consequences:** `client.gd`, `bench_render.gd` and `model_preview.gd`
no longer construct their own lighting; both the shipping rig and the
benchmark rig are now structurally guaranteed to match, closing the gap
`bench_render.gd`'s own header warns about ("a benchmark camera that is
merely similar measures a similar game"). `terrain_gen.gd:biome_color`
carries a comment explaining why its 8 colours no longer match their
pre-D-086 values. D-085 criterion 14 (a human plays a match with the new
art) is **still open** — nothing in this decision involved a human
playing, only automated headless-ish verification
(`bench-render`, `test-unit`, `test-client`, `gen-terrain-preview`,
`test-load`), consistent with the standing rule against launching the
game unprompted.

**Revisit trigger:** shadows, if a squad-count-gated version is ever
built, or if a discrete GPU becomes available to re-measure Step 0's
number and shadows fit inside it at full scale. SSAO, if it ships despite
being invisible to the `gl_compatibility` verification path — that gap
would need to be stated wherever SSAO is decided, the same way it is
flagged here as a reason it was not attempted. Toon/outline, if
playtesting after D-085 criterion 14 is finally discharged says
readability at zoom is the binding problem polished low poly did not
solve.

---

### D-085 · 2026-08-08 (reconstructed 2026-08-11) · Accepted — M7's exit criteria, written after the fact

**This entry is a reconstruction — see the editorial note above.** No
original numbered criteria list survived; `CLAUDE.md`'s M7 section cites
criteria 4, 11 and 14 by number without ever printing the full list. The
positions of those three are preserved below; the rest are inferred from
what `CLAUDE.md`'s M7 section states landed or remained open in that same
paragraph, and should be read as lower-confidence than a criteria list
this project would normally write before the code, per D-022 and D-026's
own precedent.

**Decision:** M7 ("real models and textures") is complete when:

1. At least one authored model exists per roster archetype and per
   building, generated by committed Python (D-081), not hand-modelled.
2. Every model is under its triangle budget (`TRIANGLE_BUDGET`,
   `MOUNTED_TRIANGLE_BUDGET`, `BUILDING_TRIANGLE_BUDGET` — D-081).
3. Two runs of `just build-assets` are byte-identical, and a test fails
   if `generated/` is stale against `art/`'s source hash (D-081).
4. **`just gen-model-preview` renders every authored model, animated, and
   the screenshot is looked at, not just asserted about** — the actual
   text of the criterion `model_preview.gd`'s header cites by number.
5. Soldiers render through the shipping `MultiMesh` + VAT path, not a
   per-soldier node (D-082), and carry the owning player's colour
   (D-052) despite `MultiMesh` overriding vertex `COLOR`.
6. `gen-model-preview` renders twice, 1.7s apart, and fails if the two
   frames are byte-identical — proof the VAT is actually advancing, not
   frozen at a plausible-looking still.
7. Terrain is textured by a per-biome atlas that modulates vertex colour
   (D-083), and the atlas, the minimap and the 3D mesh all agree because
   all three read `TerrainGen.biome_color()`.
8. Import settings for VAT and atlas textures are generated data
   (`godot_import.py`), not hand-set in the editor — `detect_3d/compress_to`
   in particular, since Godot's default silently corrupts a VAT with VRAM
   block compression.
9. The MultiMesh-overrides-`COLOR` defect (every soldier rendering
   black) is fixed and does not regress.
10. Every `box()` in `art/lib/geom.py` winds outward, not inside-out —
    the defect that cost nothing visually until a building was large
    enough to see through its far wall.
11. **`just bench-render` is re-run on real hardware since authored
    models landed, and the cost of animated vertices at D-018's full
    scale is measured, not extrapolated from the pre-authored-model
    number.** The actual text of the criterion `CLAUDE.md`'s M7 section
    cites by number.
12. The hex-gap and inverted-normal terrain defects (D-084) are fixed
    once textured ground made them the most visible thing on screen.
13. `just test-unit` is green with the art-pipeline tests included
    (`test_art_assets.gd` and neighbours).
14. **A human plays a match with the new art.** The actual text of the
    criterion `CLAUDE.md`'s M7 section cites by number, and the one this
    project's own M2/M6 history says not to skip: numbers passing is not
    evidence the picture is right, and playing is the check nothing else
    substitutes for.

**Rationale:** Written the way D-022 and D-026 were, so "the art landed"
and "the art meets M7's exit criteria" stay distinguishable claims — the
same distinction M2 and M6 both had to learn the hard way before this
project started writing exit criteria down at all.

**Consequences:** As of D-086, criterion 11 is discharged **with a
caveat**: measured on Intel Iris Xe integrated graphics, the same
hardware M5 used, not a discrete GPU — no discrete GPU was available in
the environment that ran it. That satisfies M5's own precedent (M5 also
used integrated graphics throughout) and answers the real question this
criterion exists for — the cost of VAT-animated authored models at full
scale — but is not literally "discrete" if that word in `CLAUDE.md`'s
phrasing was chosen deliberately rather than loosely. Criterion 14
remains open after D-086: nothing in D-086 involved a human playing,
only automated verification. **M7 is landed, not complete**, which is
consistent with what `CLAUDE.md` already said before this entry existed.

**Revisit trigger:** re-run criterion 11 if a discrete GPU becomes
available, to settle the caveat above. Close criterion 14 the next time
a human plays a match — at that point M7's completeness can be asserted
rather than argued from a reconstructed criteria list.

**Amendment, 2026-08-14 — criterion 14 discharged; M7 is complete.**
Human playtests happened on 2026-08-12 and 2026-08-13 — the live sessions
D-076's own 2026-08-12 amendment documents ("native client, human player"),
plus the follow-up rounds that produced its fix lists — all with the
authored models (D-081/D-082) and the D-086 lighting rig active. The owner
confirmed on 2026-08-14 that these count as "a human plays a match with the
new art", which is the criterion's actual text. So criterion 14 is closed
by play, the way this entry's revisit trigger asked for, and **M7 moves
from landed to complete**.

Two things this amendment does NOT change. Criterion 11's caveat stands:
every `bench-render` number is still from Intel Iris Xe integrated
graphics, and the discrete-GPU re-run trigger above stays armed.
And closing criterion 14 arms D-086's own toon/outline revisit trigger —
"if playtesting after criterion 14 is discharged says readability at zoom
is the binding problem" — which is now a live question for future
playtests rather than a hypothetical. Worth noting the sessions that
closed this criterion spent their findings on interface and geometry
defects (see D-076's amendments), not on readability complaints, which is
weak evidence in polished-low-poly's favour but was not a question anyone
was asking at the time.

---

### D-084 · 2026-08-10 (reconstructed 2026-08-11) · Accepted — a watertight hex surface, and the simulation untouched

**This entry is a reconstruction — see the editorial note above.**
`CLAUDE.md` cites this work at `D-067`, which collides with the real
D-067 below (squad shoving / one-squad-cannot-raze-a-base). This entry
gives the terrain-surface work its own ID.

**Decision:** Gaps between hexes — pre-existing, but invisible until
textured ground made them the most obvious thing on screen — are closed
by making each hex corner take the mean elevation of the three cells
meeting there, so neighbouring hexes agree on their shared corner and the
surface is watertight. The centre vertex keeps its own cell's elevation,
which leaves each hex a shallow pillow rather than a flat tile. Normals
are derived from the resulting surface instead of hardcoded
`Vector3.UP`, so slopes finally shade instead of lighting flat regardless
of grade.

`TerrainGen.surface_field` is one array of 7 heights per cell (6 corners
+ centre), read by BOTH the mesher (`terrain_chunk.gd`) and the client's
ground sampler (`TerrainChunk.height_at`) — deliberately the same file,
because a sampler that only matched the mesh by being written correctly
twice would eventually drift, and the symptom of that drift is an army
floating with every other number green.

**Rationale — the simulation must not change, and does not.**
`TerrainGen.elevation_at` stays discrete per cell and `passability` still
thresholds it; only the picture interpolates between corners. That split
is what makes this a rendering-only change with no desync surface: the
server's notion of a cell's elevation and passability is byte-identical
before and after. It stops being free the moment elevation acquires
tactical meaning (terrain-occluded line of sight is still an open
question, not decided here).

**Consequences:** `TerrainChunk.height_at` is a hot path — called once
per soldier per frame by the client's ground sampler, no longer a single
array index. Its cost on real hardware was, at the time this landed,
unmeasured; D-086's `bench-render` numbers are the first real measurement
of the full render path including this sampler, since `bench_render.gd`
explicitly samples through the same `TerrainChunk.height_at` the client
uses rather than deriving at a fixed height.

**Revisit trigger:** if terrain elevation is ever given tactical meaning
(occlusion, high ground combat bonuses), the discrete-vs-interpolated
split this entry relies on needs to be revisited explicitly — the
simulation's answer and the picture's answer would need to agree again,
the same way they were kept apart on purpose here.

---

### D-083 · 2026-08-09 (reconstructed 2026-08-11) · Accepted — terrain texturing: the atlas modulates, biome_color decides

**This entry is a reconstruction — see the editorial note above.**
`CLAUDE.md` cites this work at `D-066`, which collides with the real
D-066 below (building damage scale). This entry gives terrain texturing
its own ID.

**Decision:** Terrain is textured by a per-biome atlas
(`art/terrain/atlas.py`) that **modulates** vertex colour rather than
replacing it. `TerrainGen.biome_color()` stays the single source of
truth for what a biome looks like, read by the 3D mesh, the minimap and
the offline preview PNG alike — the property that keeps all three from
drifting apart without any of them being touched, and the reason
`biome_color()` and the mesher live where they do.

The atlas is `2048x1024` (4 columns x 2 rows of 512px tiles), generated
by periodic (seam-continuous) value noise so every tile wraps exactly —
required because the world tiles nine times (D-035) and a non-periodic
texture would show a seam at every join. Each biome's noise recipe is
its own RNG stream (`SEED + biome_index * 977`), so adding a ninth biome
cannot perturb the existing eight. Every tile is normalised to average
**`NEUTRAL_MEAN = 0.92`** — deliberately short of full white — so that
multiplying it against `biome_color()`'s value darkens the surface only
slightly instead of tinting it; the atlas may add texture, never colour.
Per-cell UV rotation is hashed from the wrapped cell coordinate, so the
hex lattice does not read as an obviously repeating tile.

UVs are derived from the **cell**, never from world position — the same
reason terrain elevation is cell-keyed (D-084) — so all nine torus
copies of a hex agree on their texture by construction rather than by
each copy computing its own answer and hoping they match.

**Rationale:** A single source of truth for colour is what let D-086
re-tune the palette for the new lighting rig by editing eight `Color`
literals in one function, with the minimap and preview PNG updating for
free. Had the atlas carried its own colour independent of
`biome_color()`, that re-tune would have needed a `just build-assets`
rebuild and a `generated/` re-commit on top of the code change, and the
three views (3D, minimap, preview) could have drifted from each other in
the process.

**Rejected alternatives:** Letting the atlas tint the terrain directly
(rejected — see above: it would make the atlas a second source of truth
for colour, defeating the reason `biome_color()` exists as a single
function everything reads).

**Consequences:** Any future palette change touches only
`terrain_gen.gd:biome_color` — confirmed directly by D-086, which did
exactly that and needed no atlas rebuild.

**Revisit trigger:** if a biome ever needs texture variation that
`biome_color()`'s flat per-biome colour cannot express (e.g. patchy dead
grass within GRASSLAND), the "atlas never carries colour" rule would need
an explicit, deliberate exception — not a silent one.

---

### D-082 · 2026-08-09 (reconstructed 2026-08-11) · Accepted — animation: a vertex animation texture, and a phase that is derived, never accumulated

**This entry is a reconstruction — see the editorial note above.**
`CLAUDE.md` cites this work at `D-065`, which collides with the real
D-065 below (formation shape, replicated state). This entry gives VAT
animation its own ID.

**Decision:** Soldiers animate via a vertex animation texture (VAT),
sampled per-vertex in `shaders/unit_anim.gdshader` /
`unit_anim_ghost.gdshader` through the shared `unit_vat.gdshaderinc`.
The VAT layout is `width = vertex count`, `height = total_frames*2 + 1`:
rows `[0, 64)` are per-frame position OFFSETS from the rest pose, rows
`[64, 128)` are animated normals, row 128 carries the part's `rgb` colour
and an owner-tint `alpha` mask. Baked as half-float RGBA EXR with the
view transform forced to `Raw` so no colour management touches the
numeric payload.

**The phase is derived from `TIME` in the shader every frame —
`phase = fract(t*rate + hash(slot))` — never accumulated.** This is the
clause that makes animation legal under D-006's ban on per-soldier
integration state: there is nowhere for a phase counter to live, because
`animation_state.gd` is all-static for the same structural reason
`formation.gd` and `cosmetic_offset.gd` are. A phase counter advanced by
delta time, or a blend weight carried between frames, would be
integration state in a cosmetic disguise and would violate D-006 clause 1
exactly as an emergent per-soldier movement system would.

**Rationale — why a MultiMesh needs this instead of a normal
`AnimationPlayer`.** Soldiers render one `MultiMeshInstance3D` per squad
(D-009), not one node per soldier — an `AnimationPlayer` has no notion of
"this instance is at a different phase than that one" within a single
mesh. A VAT sampled with a per-soldier phase hash is what lets thousands
of soldiers in one draw call each look like they are not marching in
lockstep, at the cost of three `texelFetch`es per vertex instead of a
skeletal skin.

**Consequences — the defect this shape doesn't prevent, and did
happen.** A `MultiMeshInstance3D` overrides the shader's `COLOR` with its
own per-instance colour, so a mesh's vertex `COLOR_0` never reaches the
fragment stage on this render path — the reason every soldier rendered
black before this was diagnosed, and the reason unit colour lives in the
VAT's own colour row (fetched with the same column index as position and
normal) rather than in vertex colour the way building colour does
(buildings render as individual `MeshInstance3D`s, so `COLOR` reaches
them fine). Column index is carried in `UV2.x` rather than `VERTEX_ID`,
so it survives glTF re-ordering and works under the GL Compatibility
renderer `test-client` and `gen-model-preview` both depend on.

**Revisit trigger:** none identified; VAT sampling cost at full scale is
now measured by D-086's `bench-render` run, which folds this shader's
cost into the same number that includes culling and LOD.

---

### D-081 · 2026-08-09 (reconstructed 2026-08-11) · Accepted — art direction and pipeline: stylised low poly, generated, not hand-modelled

**This entry is a reconstruction — see the editorial note above, and
supersedes D-011.** `CLAUDE.md` cites this work at `D-064`, an ID never
actually written in this file — the only trace of it was a two-line Q12
closure. This entry gives the art pipeline its real ID and content, and
corrects that closure below.

**Decision:** Closes Q12 ("art direction for mesh tiers 2 and 3, and who
produces it"). Style: stylised low poly with strong silhouettes, ~300
triangles per soldier. Produced by **committed Python scripts driving
Blender headless as a library** (`bpy`, a PyPI wheel — no GUI, no system
Blender, no GPU needed for generation), not by hand in the Godot editor
or a DCC tool. D-011's tier 2 (parametric composition) is absorbed rather
than skipped: parametric composition is *how* the generators are
written, not a separate stop on the way to tier 3.

**Geometry is exactly two primitives** (`art/lib/geom.py`): `box()`
(axis-aligned, `taper`/`taper_z` for wedges and gable ridges) and
`prism()` (N-sided about Y, for helmets/shields/spearheads/spires). No
spheres, no bevels, no UV unwrap. Every soldier and building is composed
from these via an ordered list of named, coloured `Part`s
(`art/lib/soldier.py`, `art/buildings/__init__.py`).

**Vertex colour carries two channels**, not one: a part's own `rgb`, and
a `mask` (carried in alpha) for how much of that part takes the owning
player's colour (D-052) — 1.0 on cloaks/banners, 0.9 on shields, 0.85 on
tunics, 0.0 on skin and steel.

**Triangle budgets are enforced, not advisory** — `art/build.py` raises
`SystemExit` over `TRIANGLE_BUDGET = 300` (`MOUNTED_TRIANGLE_BUDGET =
460`, `BUILDING_TRIANGLE_BUDGET = 400`). The heaviest shipped foot unit
(founders, 172 tris) is still well under budget — nothing shipped is
geometry-limited, which is the fact D-086 leans on to justify spending
the art budget on lighting instead of more geometric detail.

**Both the generators and their output are committed.** `art/` is the
source of truth; `generated/` (`.glb`, VAT `.exr`, the terrain atlas) is
a committed build product anyway, so a fresh clone plays without
installing Blender. Two runs of `just build-assets` must be
byte-identical — fixed seeds, sorted iteration, no timestamps — and a
test fails if `generated/`'s manifest hash is stale against `art/`'s
source. Import settings (`detect_3d/compress_to=0` above all — Godot's
default silently VRAM-compresses a VAT, which is corruption, not
compression, on a texture where neighbouring texels are unrelated
vertices) are generated data via `art/lib/godot_import.py`, not
hand-set in the editor.

**Rationale:** Matches D-011's original tiering philosophy (zero art
dependency validates the architecture before art investment) while
finally spending the art budget D-011 deferred — the trigger D-011
itself named ("M3 complete, and playtesting suggests visual fidelity is
limiting engagement, or tiers 2/3 explicitly prioritized") had fired by
the time this was written: M3 had completed three milestones earlier and
the owner had explicitly prioritised tiers 2/3.

**Rejected alternatives:** Hand-authored final meshes in a DCC tool
(rejected — the project's whole premise, stated in `CLAUDE.md`'s "What
this project is", is that plain-text/scriptable assets keep the project
editable by Claude Code; a hand-sculpted `.blend` is the one thing this
project's own rules flag as an exception rather than the default path).
Jumping straight to tier 3 fidelity without the parametric layer
(rejected — every archetype needing its own bespoke script would multiply
the ~90-130 unit count D-070 already accepts for M9's roster growth).

**Consequences:** Nothing shipped is geometry-limited (see triangle
budget numbers above), which is the load-bearing fact behind D-086's
choice to spend on lighting rather than more detailed models. Adding an
archetype is a data change in `art/units/__init__.py`'s `ROSTER` dict,
not a new script.

**Revisit trigger:** none identified since D-011's trigger fired and
this decision was made in response to it.

---

### D-077 · 2026-08-12 · Accepted — a sandbox mode for dev testing, kept structurally unable to leak into a real match
**Decision:** `MatchState` gains three independent flags — `sandbox`,
`instant_build`, `ai_economy_only` — settable from a `--sandbox=1` server
launch arg or, live, by the lobby admin via the existing `LOBBY_SET_OPTION`
channel (a "key=value" pair, the same one a map slider already uses,
rather than three new opcodes). Unlike map settings, none of the three
are locked to the LOBBY phase: the whole point is iterating on a running
match without restarting the server.

With `sandbox` on, three new C2S opcodes are accepted, each gated behind
`MatchState.sandbox` at the top of its handler (`_validated_cheat`, mirroring
`_validated_squad`'s shape): `CHEAT_ADD_RESOURCES` (a flat grant to the
sender), `CHEAT_SPAWN_UNIT` (full-strength squads at a cell, bypassing
cost and the squad cap), `CHEAT_SPAWN_BUILDING` (a complete building at a
cell, bypassing cost/footprint/claim but still refusing water/mountain —
a spawned building should never look broken even with every game-balance
rule around it skipped). `instant_build` and `ai_economy_only` are match-
wide settings rather than one-shot actions, so they ride the lobby channel
instead: `instant_build` makes `_finish_build`/`_handle_order_produce`
raise things already complete (`BuildingSim.add_building`'s existing
`complete` param, `BuildingSim.enqueue`'s new `instant` param queuing at
~0s remaining) rather than adding a second completion code path;
`ai_economy_only` sets `AiPlayer.economy_only`, which skips `_fight`
entirely and holds `_train`'s `wanted` archetype at `"gatherers"` so an
economy-only AI doesn't quietly stockpile an unused army either.

**Rationale:** three flags, not one "sandbox" bit that does everything —
someone may want instant construction without also wanting free resources
and unit-spawning, and a host running an AI-only economy stress test
doesn't need the other two at all. Admin-gating and the launch-flag path
both matter for the same reason: a client cannot turn sandbox mode on for
itself (D-002), and a production server never started with `--sandbox=1`
has no code path that ever sets `MatchState.sandbox` true, so the cheats
are unreachable by construction, not merely unreachable by convention.

**Rejected alternatives:**
- *A single "cheats enabled" bool covering everything* — rejected per the
  three-independent-flags reasoning above.
- *New opcodes for `instant_build`/`ai_economy_only`* — rejected: they are
  admin-gated MATCH settings, the exact shape `LOBBY_SET_OPTION` already
  exists for, and a fourth near-identical opcode would be the copy this
  project's own `_validated_squad` header warns eventually drifts.
- *A debug console (type a command)* — considered; an on-screen panel was
  chosen instead (user's explicit choice) since a discoverable button beats
  remembering command syntax for a tool used occasionally, not daily.

**Consequences:** `just test-unit` is green at **545 tests** across 35
scripts (13 new — `test_lobby.gd` gained flag-independence/admin-gating
cases, `test_sandbox.gd` is a new file for the cheats/instant-build/
economy-only behaviour itself, including a paired test proving the
economy-only scenario WOULD have attacked without the flag, not merely
that nothing happened either way). `test-load 4 120` stays clean with
sandbox off (the default) — 57.46 µs/squad at 52 squads, no regression.
The in-match debug panel and cheat-arm-and-click flow are client-only UX,
unverified by the automated suite for the same reason D-076's placement
tools are — look at them before trusting the geometry.

**Revisit trigger:** none anticipated — this is dev tooling, not a game
mechanic with a balance surface to re-derive. If `ai_economy_only` ever
grows per-seat granularity (some AI fighting, some not, in the same
match) rather than the current match-wide toggle, that is a new decision,
not an amendment to this one, since it would need seat-scoped wire state
`encode_lobby`'s per-seat fields do not currently carry.

---

### D-076 · 2026-08-12 · Accepted — walls, gates, and a wall-top tier reached through one door
**Decision:** D-069 named this exact feature and fenced it out of M9:
*"no wall system... A real wall system is a substantial piece of
pathfinding and rendering work and needs its own decision."* This is that
decision. Two structures and two grades of each:

- **`wall` / `gate`** — single-cell segments, chained by placing several
  adjacent (the existing per-cell `ORDER_BUILD` path, unchanged). Pure
  ground blockers: `damage=0`, no wall-top presence. A gate additionally
  supports **manual open/close** and **auto-open when the owner's own
  squads are near**, mode switchable per-building from its selection HUD
  panel. `footprint_radius=0` on all four defs, so adjacent segments do
  not reject each other under `server._footprint_conflict`.
- **`garrison_wall` / `garrison_gate`** — pricier, `walkable_top=true`:
  their cell joins a real second passable layer (tier 1). Still
  `damage=0` — the structure itself never attacks; whatever squad is
  standing on it does, with its own stats plus a height bonus.
- **`wall_tower`** — the only access point. `is_access_tower=true` and a
  **per-INSTANCE** `access_direction` (chosen at placement, stored on
  `BuildingSim`, not on the shared `BuildingDef` — a def is one resource
  per archetype, so a door facing can't live there without every tower
  sharing one facing). Climbing/descending is legal **only** through the
  ground cell on that one side. **Not ownership-gated**: the check is
  pure geometry (which cell a squad occupies, which tower's door that
  is), so an enemy that fights through to the door climbs exactly like
  the owner would. A wall's tier-1 top is therefore a contestable
  objective, not an automatically safe one.

**Geometry: chained single cells, not edges.** `TorusSpace` has no edge
primitive and none was added. A wall is however many `wall`/`garrison_wall`
buildings a player places adjacent to each other — it reuses the entire
existing placement/passability/combat/replication pipeline, which is what
keeps this from being the "substantial" rewrite D-069 was worried about.

**The wall-top tier is a second `FlowField` layer, the class itself
unmodified, but NOT sharing the ground layer's cache or budget.**
`SquadSim._fields_top`/`_pending_fields_top`/`top_field_cells_per_tick` are
wholly separate from `_fields`/`_pending_fields`/`field_cells_per_tick`
(D-040's shared counter). Sharing it would let a wall-top solve silently
halve ground-pathing throughput on any tick both are active — confirmed by
reading `_field_for`'s budget accounting before writing the second copy,
not assumed. A squad's tier (`SquadSim._tier`, 0 or 1) is real per-squad
state; its POSITION within a tier is still a pure function of
`(curve, formation, slot, terrain sample)` exactly as D-006 requires —
climbing/descending is one explicit teleporting hop
(`SquadSim._teleport_curve`), never a curve-interpolated walk, which is
what keeps it legal under D-006 clause 1: there is nowhere for a
partial-climb value to live. `order_move`/`order_attack_move` infer the
target tier from whether the destination cell is itself on the wall-top
network (`BuildingSim.is_walkable_top_cell`) — **no wire change to
movement orders was needed**; a cross-tier order decomposes server-side
into "walk to the nearest reachable tower's door, hop, continue," the same
two-leg shape `server.gd`'s `_pending_builds` already uses for
out-of-reach construction.

**Combat gains exactly one new rule.** A tier-1 squad fights with its OWN
`UnitDef` stats — `Combat._resolve_attack` is untouched — from an
effective range of `base_range + BuildingDef.top_range_bonus`
(`Combat._attacker_range_cells`). Targeting eligibility
(`Combat._can_reach_tier`): a tier-1 defender can be hit by another
tier-1 attacker, or by anything **ranged** (`armour_class == "missile"`,
including every building — a tower's fire already "arcs up" thematically)
— never by a tier-0 melee squad. This is the whole reason climbing is a
real defensive choice and not a coat of paint.

**Destruction evicts, it does not kill.** `SquadSim._evict_stranded_tier1_squads`
runs whenever `resolve_squads_vs_buildings` reports a destruction this
tick, and drops any squad whose tier-1 cell no longer has a living
`walkable_top` structure under it to the nearest passable ground cell,
alive. An invisible instant-kill on top of losing the structure would be
a second, worse punishment nobody asked for.

**Rejected alternatives:**
- *An abstract garrison-capacity slot* (an early draft of this decision):
  a fixed-capacity "station a squad in the wall" order, protected but
  otherwise decorative. Rejected once the user asked to literally see
  units fighting from the wall — replaced by ordinary squad movement
  extended to a second tier, which is simpler and delivers the visual
  directly instead of needing a HUD counter to stand in for it.
- *Any adjacent cell as a climb point*: the first cut of the walkable tier
  let a squad climb from any ground cell next to any `walkable_top`
  segment. Caught before it shipped: it makes a wall's LINE pointless,
  since an attacker could climb up from outside anywhere along it. Access
  is now the tower's one door, full stop.
- *Ownership-gated climbing*: considered and explicitly rejected by the
  user — a wall an enemy could never contest from the top would make
  "storming the wall" impossible even after a real breakthrough.
- *A unified multi-tier BFS graph*: rejected for cost/complexity —
  `FlowField.expand()` is untouched; two independently-solved layers plus
  an explicit hop is far cheaper to reason about and to budget.

**Consequences:** `just test-unit` is green at **527 tests** across 34
scripts — `test_buildings.gd` gained 13 ground-level cases and
`test_wall_top.gd` is a new 12-case file for the tier itself.
`just test-load 4 120` reports a clean verdict at both phases — **63.62
µs/squad at 52 squads** after Phase A landed, **53.45 µs/squad at 52
squads** after Phase B (the difference is ordinary run-to-run variance per
the standing caveat, not a regression: no bot in that load test builds a
wall, so neither run exercises the new combat/vision branches under load —
they are only proven correct by `test_wall_top.gd`, not yet by a live
multi-client match). Worst tick stayed inside D-020's 100 ms budget in
both runs (22.8 ms, then 28.6 ms).

One dead end recorded rather than silently fixed: the first version of
the range-bonus tests ran 150 ticks and let `Combat.assign_idle_engagements`
chase-and-close the gap it was trying to hold open, which also produced
enough flow-field churn to OOM-kill the test container at its existing 1 GB
limit. Fixed by checking on tick 1 — provably before any chase order can
have moved anything — rather than by raising the container's memory limit,
which would have hidden a real test design fault instead of removing it.

**Revisit trigger:** the gate-toggle/flow-field-flush interaction is
flagged, not measured — `SquadSim.set_passable`'s full-cache flush runs on
every gate state change, and auto-mode is bounded to a check every 3 ticks
(`server.AUTO_GATE_CHECK_TICKS`) as a precaution, not because a spike was
observed. If a live match with several auto-mode gates shows the flow-field
spike M4 already found once, that is this entry's own revisit, the same
way D-040 was D-038's. Separately: no AI behavior for building or
using walls/gates exists yet — `just ai-ladder` cannot exercise any of this
feature until an AI player is taught to want one, which is future work.

**Amendment, 2026-08-12 — a real playtest immediately found three more
things.** The first live session (native client, human player) surfaced
one genuine defect and two placement-UX gaps, all fixed the same day:

1. **`_finish_build` consumed ANY builder unconditionally, not just
   founders.** It is shared by every building type, and the D-031
   consume-on-completion call had no check on who was building what — so
   a gatherer sent to raise a barracks, a tower, or a wall segment has
   apparently been vanishing the moment it finished for as long as this
   function has existed. Nothing failed loudly (the building still gets
   built), which is exactly this project's recurring declared-and-unread
   shape, just on the OTHER side of the call: not an unread field, an
   over-read one. Walls and gates, built in the numbers a real session
   produces, is what finally made it something a player noticed. Fixed by
   gating consumption on `UnitDef.archetype == &"founders"`.
2. **Facing generalised from the access tower's door to every building.**
   `BuildingSim._facing` (renamed from `_access_direction`) is now set on
   every instance, not just towers; `access_direction_of` keeps its
   original tower-only "does this door exist" contract unchanged, and a
   new `facing_of` answers the general rendering question. The rotate key
   works while ANY building is armed for placement, not only a
   `wall_tower`.
3. **Placement gained snapping and a drag-to-build-a-line tool**, both
   scoped to `footprint_radius == 0` defs (the existing wall-family
   signal, reused rather than adding a new one): the ghost snaps to the
   nearest cell adjacent to an existing wall-family building and
   auto-orients to face it; dragging computes the hex line between press
   and release (`_hex_line`, standard cube-coordinate rounding) and
   round-robins it across every eligible selected squad. That needed
   `_pending_builds` to become a QUEUE per squad rather than one site —
   `C2S_ORDER_BUILD` still replaces it (the original single-click
   behaviour), a new `C2S_ORDER_BUILD_QUEUE` appends. One squad alone
   still builds a whole line, just sequentially, `_advance_pending_builds`
   starting it toward each queued site as the previous one finishes.

None of the placement-UX pieces are reachable from a GUT test — they live
in `client.gd`, which needs a GPU the same way rendering does (D-014).
Verified by wire round-trip (`facing` on both `ORDER_BUILD` and
`BUILDING_INFO`, the new queue opcode) and by `BuildingSim` behaviour
(facing stored/wrapped for any building) — 532 tests green, `test-load`
still clean at 57.88 µs/squad — but the rotation math, the snap radius,
and the line tool itself are only proven by looking at them, the same
category `just test-client`'s casualty gate exists for elsewhere. Play
it before trusting the geometry.

**Amendment, 2026-08-13 — authored models for all five defs (D-064's
pipeline), plus two things the art pass exposed.** All five had been
rendering as primitives (`mesh_size`-overridden boxes/cylinder) since
launch; `art/buildings/__init__.py` gained a `shape` field (`block` |
`wall` | `tower_access`) that branches `build()` entirely rather than
stretching the existing gable/flat/spire roof cases, since a long low
segment and a squat access tower are different silhouettes from every
`block`-shape building that came before. `wall`/`gate` are a row of
tapered timber stakes (the cheap tier — no walkway, pure blocker);
`garrison_wall` is a crenellated stone rampart; `garrison_gate` is the
same walkway/parapet silhouette built from vertical timber slats instead
— **material marks the gate, not a gap in the wall**, since the user's
own spec put both garrison pieces in the "stone, crenellated" family and
only the gate in wood; `wall_tower` is a crenellated stone tower with a
door on local +X, the same axis `client.gd` rotates by `facing` that
`wall`/`gate` segments already used for their length — so the modelled
door always ends up pointing at the one ground cell D-076's climb check
actually permits, with no per-instance mesh logic. All five comfortably
inside the 400-tri building budget (108–192 tris; the existing four run
72–144).

1. **The gate open/closed colour cue only worked for `StandardMaterial3D`
   — the primitive path.** An authored model gets a `ShaderMaterial`
   (`UnitMesh.static_material_for`), which has no `albedo_color` to lerp,
   so `gate`/`garrison_gate` getting real models would have silently gone
   back to always reading "closed" the moment they shipped — caught
   before it shipped rather than after, this time. Fixed with a
   `gate_open` uniform on `building_static.gdshader` (lightens ALBEDO the
   same amount the primitive path already did) and a branch in
   `client.gd`'s per-frame gate-colour block that sets whichever the
   instance actually has.
2. **`model_preview.gd`'s camera was tuned for 4 buildings and silently
   clipped the ends of a row of 9** rather than failing — the same
   "numbers all pass while the picture is wrong" shape this project keeps
   finding (M1's empty first frame, M6's missing terrain, D-067's
   inside-out winding). Widened camera distance/FOV and a new
   `BUILDING_SPACING` constant so the whole roster fits one frame; the
   fix is the tool, not the models — nothing about the buildings
   themselves required it.

Also found and fixed, not a modelling issue: `just bootstrap-art` assumed
a POSIX venv layout (`bin/python`, `bin/pip`) and a pip that can
overwrite its own running executable — both true on Linux, neither true
on Windows, where `python -m venv` lays out `Scripts/` and pip refuses to
self-upgrade via its own shim. `blender_python`/`blender_pip` now branch
on `os_family()`, and the self-upgrade goes through `python -m pip`
instead of `pip.exe` directly — this project's tooling had simply never
been run through this recipe on native Windows before. Separately: the
docker-backed `_import` and native-backed `gen-model-preview` write to
two different cache directories (`.godot-container/` vs `.godot/`) —
`gen-model-preview`'s own `_import` dependency inherits `EDOTMW_RUNTIME`'s
docker default, so on a machine that has only ever run docker-backed
recipes, the native render step was reading an import cache that had
never heard of these files. Not a bug in either recipe alone, just an
untested combination; resolved here by running with
`EDOTMW_RUNTIME=native`, not by changing the recipes' default.

`just test-unit` green at 545 tests across 35 scripts (`test_art_assets.gd`'s
manifest-hash check among them); `just gen-model-preview` inspected
visually — every new building distinguishable by silhouette and material,
`wall_tower`'s crenellations and `garrison_gate`'s slats both read clearly,
`garrison_wall` partly buried by an unlucky hill in the small preview
terrain but its own merlons visible through the gap. No simulation code
changed, so `test-load` was not re-run.

---

### D-075 · 2026-08-11 · Accepted — leaving a match returns to the lobby, and no humans means no server
**Decision:** Two rules, both about the end of a session rather than the
end of a match.

**1. "Leave match" returns to the lobby.** It sends a new
`C2S_LEAVE_MATCH` and stays connected. The server ends the match, drops
the world, and re-broadcasts the seats; `MatchState` gains
`return_to_lobby()`, the one backwards edge in a phase machine that had
run `LOBBY → RUNNING → FINISHED` only. Seats survive so the next match is
one click away; everything a match *wrote* on them does not.

**2. No humans, no server.** When the last socket client disconnects, the
server shuts down and exits. AI seats explicitly do not count — they have
no socket (D-051), and a match of nothing but computers would otherwise
hold the port forever.

**Rationale:** the old "leave" was a disconnect, and its doc comment
already claimed it went "back to the lobby screen". It could not: a
disconnect tears the seat down, so there was nothing to return TO and the
player sat looking at a dead match until they closed the window. This is
D-061's shape again — a rule fully written, with a caller, whose
destination did not exist — and again only *using it* found it.

Rule 2 is not hypothetical. This session opened by clearing a server that
had been ticking an empty world **for six hours** with `clients=0`,
launched by `just run-server AI=1` — which `just` parses positionally
into `--ai=AI=1`, so `int()` read 0 and it never had an opponent either.
`_on_disconnect` already printed a summary when the last client left and
then went right on ticking.

Putting the return in `MatchState` rather than the client is what makes
the client change almost nothing: `ClientState.in_lobby()` already reads
the phase off the wire, so the lobby screen comes back on its own. A
client that could end a match locally would be a client deciding for
everybody (D-002).

**What a match writes on the lobby, and must be undone.** Each of these
is silent when wrong — a second match with the first one's civs looks
entirely normal:

- **A `Random` seat is resolved IN PLACE at start** (D-048). Without
  restoring the choice, "Random" would mean "random once, ever".
- **Registration carries an `eliminated` flag.** Kept, whoever lost match
  one would begin match two already defeated, and the victory rule would
  end it before anyone moved. It is cleared, and `_on_match_started` now
  registers every seat — humans as well as AI, which it had not done,
  because `_on_connect` was the only human registration path.
- **`_build_world` guards on `_sim != null`** and would otherwise return
  without building, leaving match two running on match one's terrain,
  spawn points, resource nodes and combat seed.
- **Entity ids restart.** Both sims mint from an array length, so match
  two's squad 0 would find match one's MultiMesh under its id.
- **The replay is the match's** (D-016), so it is closed and the next one
  opens its own file rather than truncating it.

**Rejected alternatives:**
- *Client-side only — show a disconnected lobby* (rejected: the lobby is
  server-driven, so seats, chat and settings would be inert and nothing
  could start a second match).
- *Tear down and relaunch from the `just` recipe* (rejected: a visible
  relaunch pause, and it only works for sessions started that way, not a
  client connected to a remote server).
- *Ending the server the moment the match is left* (rejected: it makes
  "return to the lobby" a dead screen in exactly the solo-versus-AI
  session this exists to serve).

**Consequences:** one human leaving returns the **whole match** to the
lobby, evicting everyone. That is right for solo-versus-AI and wrong for
several humans, and it is the known limit of "for now" — a per-player
leave needs a spectator-or-seated state that does not exist.

`just lobby` and `quick-test` dropped `--rm`, because a server that exits
by itself would take its own log with it; the trap's `just down` still
removes the container by project label.

Two adjacent defects fixed in passing, both on the path being changed:
`_on_disconnect` called `_sim.replicator` unconditionally and would have
crashed on a lobby disconnect, which was survivable only while leaving
always meant leaving a RUNNING match; and `remove_human_seat` had no
caller outside its own test — the **fifth** declared-and-unread member
after `UnitDef.cost`, `BuildingDef.cost`, `BuildingSim.damage()` and the
three `CivDef` knobs — so a human who dropped from a lobby kept their
seat forever and the admin role never passed on.

**Revisit trigger:** the first match with two humans in it. At that point
"leave" has to become per-player and this entry is reopened, not patched.

---

### D-063 · 2026-08-06 · Accepted — the HUD a player actually reads, and a view that turns
**Decision:** The HUD's contents are chosen for what a player can ACT on,
and the camera gains a yaw.

1. **Top bar:** resources, then `12/40 squads`, then the match clock, then
   a **Menu** button at the right edge.
2. **The ghost count is gone from the HUD.** It measured fog of war
   working — a diagnostic, kept in the capture verdict where measurements
   belong, not in the one line a player reads at a glance.
3. **The view rotates.** Q/E in 15-degree steps, Ctrl+wheel in 7.5-degree
   steps, plain wheel still zooms. A **compass** under the top-right
   snaps back to north on click.
4. **The selection panel handles a mixed force**: named for what it
   contains, strength summed per squad, and only actions EVERY selected
   squad can perform.
5. **An in-game menu that does not pause**, with Resume, Settings, Save
   (disabled — see below), Leave match and Exit.
6. **Settings** covers only what there is a real system for: fullscreen,
   camera pan speed, HUD scale (with an automatic default), persisted to
   `user://settings.cfg`.

**Why the clock and the cap come from the SERVER.** The cap is MapConfig
data the client has no copy of, and a client that read a local `.tres`
could print a ceiling different from the one the server enforces. The
clock is worse: a timer each client ran for itself would show every
player a different match length and drift further apart the longer the
game ran — and this project is aiming at 1–2 hour matches (D-056), which
is long enough for that to become visible. So `WELCOME` carries the cap
and the server's tick, and the client re-anchors on the tick already
present in every `STATE_HASH`. At a fixed 10 Hz (D-020) the tick count IS
the elapsed time, so the clock cannot disagree with the simulation and
costs no bandwidth of its own — D-003's derive-between-messages pattern,
the same one construction progress and the production countdown use.

**Why the squad count is not `curves.size()`.** That is every squad on
screen, including other players' — a number with nothing to do with the
ceiling printed beside it. It is counted the way
`MatchState.has_squad_capacity` counts: this player's own living squads,
gatherers included. Nor is it `squads.size()`, which only ever grows
(nothing removes a dead squad from the list of ids this client was told
it owns) and would produce "41/40".

**Rotation was cheap because nothing ever assumed a fixed heading.**
Cell-picking goes through `project_ray_*`, selection and culling through
`unproject_position`, and terrain tiling through lattice offsets around
the camera target — so all three follow the camera without being told.
The only thing that had to change was WASD, which now pans relative to
where the camera looks: after a 90-degree turn the world axis that used
to mean "up the screen" means "right", and panning in world space is the
standard complaint about RTS cameras that get this wrong.

**The compass turns its dial, not its needle.** A compass answers "which
way am I facing", so the world's north moves around the ring while the
direction you are looking stays fixed at the top. A spinning needle over
fixed letters is a magnetic compass — a different instrument answering a
different question, and an easy thing to build by accident because it
looks almost right.

**Why the menu does not pause, and why that is not a shortcut.** The
server is the authority and runs its own clock (D-002/D-020). A client
cannot pause a match any more than it can move a squad, and in
multiplayer it must not: "pause" would either stop everyone else's game
or — worse — stop only this player's view while their army carried on
being attacked. So the menu is an overlay on a running match and says so
on its face. One consequence is load-bearing: the backdrop must not
swallow input, or a player could not react to what they can see happening
behind it.

**Save is a disabled button, deliberately.** There is no save system:
the authority is the server, so a save is a snapshot of ITS state —
`SquadSim`, `BuildingSim`, `Economy`, `MatchState`, the RNG position and
the tick — and none of that is serialised anywhere. The button is present
and disabled with a tooltip saying why, rather than absent (which hides
the gap) or present-and-silent (which would be the
declared-and-unread shape of D-061 and D-055, built on purpose). Owner's
call, 2026-08-06: saves get their own milestone.

**Rejected alternatives:**
- *A settings screen with graphics quality, resolution and keybind
  remapping* (rejected — there is no LOD toggle to bind, no resolution
  list, and no keybind indirection: `_handle_key` reads keycodes straight
  off the event. Every one of those would be a control that appears to do
  something and does not).
- *Plain wheel to rotate* (rejected — zoom is the constant gesture and
  keeps the bare wheel; rotation is occasional and can afford Ctrl).
- *Pausing the match from the menu* (rejected — see above; not
  implementable in a client-server game with an authoritative server).
- *A "spectate" state on leaving a match* (rejected — leaving disconnects,
  and D-033's ordinary rule then wipes the abandoned army, exactly as a
  dropped connection does. Inventing a half-way state would be a rule
  nobody asked for).

**Consequences:** Q and E are now taken. `BUILD_KEYS`/`TRAIN_KEYS` are
driven by `OS.get_keycode_string`, so a future building or unit given the
letter Q or E would silently steal it — the rotation check runs first,
which keeps that a deliberate choice rather than a race between two
lookups. Rotation also means the minimap's view-bounds box is drawn from
a rotated frustum; it is derived from the camera, so it follows, but it
is now a quadrilateral rather than an axis-aligned box.

**An intermittent `test-load` failure was seen while verifying this, and
it is NOT this change.** One run in several reported `known_squads_max=4
buildings_known=0` — every bot still holding only its founding party and
nobody having built anything — on a run that otherwise ticked its full
137 s with 0 desyncs. The same numbers reproduce with these changes
stashed, and the immediately following run was clean (`known_squads_max=35
buildings_known=7`, 522,600 bytes, 65.2 µs/squad at 52 squads, 0 dropped
ticks).

The likely amplifier is worth writing down: `bot_client.gd` attempts to
found a town hall EXACTLY ONCE, at `_orders_issued == 0`. Nothing retries
and nothing checks whether it worked, so any single refusal or lost
opening order leaves that bot with no base for the whole run — and since
every bot opens identically, a condition that hits one tends to hit all
four. That makes the harness's most important precondition a single point
of failure. Not fixed here (it is the load-test harness, not the game),
but it is the first thing to look at if this recurs.

**Revisit trigger:** if the camera ever gains PITCH as well as yaw,
`_cell_under`'s flat-plane assumption (`distance := -from.y /
direction.y`) still holds, but the fixed `height * 0.6` offset stops
being a sensible framing and the camera model needs rethinking rather
than extending.

---

### D-067 · 2026-08-04 · Accepted — a shoved squad steps aside, and one squad cannot take a base
**Decision:** Two things, found together because the second could not be
delivered without the first.

1. **`TorusSpace.disk_offsets` is sorted nearest-first.** It enumerated
   dq-major from `-radius`, so its first entries are the FAR edge of the
   disk. Three callers walk it looking for "the nearest free cell" and
   each silently took one up to `radius` away, always in the same
   direction.
2. **The anti-rush rule the owner asked for**, now that the first fix
   makes it expressible: **one squad of any starting troop must fail
   against a defended building; two must succeed.** Town centre damage
   **45 → 60**; tower **80 → 85** and **1400 → 1700 HP**.

**How the ordering defect showed itself.** Two militia squads ordered
onto one town centre dealt 1560 damage in 30 s against a single squad's
1461 — the second squad was displaced four cells by `_separate_arrivals`,
which is outside a 1.9-range unit's one-cell reach, so it stood there for
the rest of the match doing nothing. Ranged units never showed it: they
were displaced within their own range and kept firing, which is why the
symptom read as "buildings feel weak" rather than "half my army is idle".

`_free_cell_near`'s doc comment said "the nearest cell"; `_approachable`
said "walks outward"; `_spawn_cell_near` said "prefers to stand a new
squad right at the door". All three were describing an order the table
did not have. Sorting it (cached per radius, ties broken by (dq, dr) so
it stays a total order for replays) made all three true at once, and the
two-squad damage went to ~2x on the first run.

**The rule, and what it cost to find.** Measured across every unit in the
roster, both buildings, one squad and two, 600 s cap:

| | result |
|---|---|
| town centre 60 | no unit takes it solo; every line troop takes it with two |
| tower 85 / 1700 HP | no unit takes it solo; every line troop but one takes it with two |

**Two exceptions, both deliberate and both tested.** *Founders* are
excluded from the two-squad rule: a player has exactly one founding party
and spends it raising the town hall (D-031), so two of them is not a
situation the game can produce. *northmen_skirmishers* cannot take a
tower with two squads — they are the cheapest, flimsiest unit (30 food,
42 HP a man, 1260 to a squad), the tower outranges them 5 cells to 3, and
each shell kills two of them at once, so they rout (threshold 36) and
spend the fight cycling. **No tower HP/damage pair exists that stops a
lone militia squad and still loses to two skirmisher squads** — swept
across (1400–2400 HP) x (75–140 damage). The roster spans 1260 to 3360
effective squad HP; one flat number cannot separate those two cases.
Wanting it needs a mechanic (siege equipment, a damage type), not another
number. A test asserts skirmishers still do real damage to a tower, so
the carve-out cannot quietly become "harmless".

**Rejected alternatives:**
- *Tuning damage without fixing the ordering* (rejected — impossible: two
  melee squads were not twice one squad, so no value could satisfy both
  halves of the rule).
- *Giving `disk_offsets` a second, sorted table* (rejected — two tables
  and a choice at every call site, when no caller wants the unsorted one).
- *Stopping a lone squad by raising building HP alone* (rejected — HP
  lengthens the fight for attacker and defender alike; it moves both
  halves of the rule the same direction).

**Consequences:** every "nearest cell" search in the sim changed
behaviour — production spawns, approach cells, arrival separation — all
in the direction their comments already claimed. Sieges are now
manpower-limited by the contact ring, which is realistic and which nobody
has designed: a building can only be surrounded by so many squads, and
the rest queue behind. Ladder decidability is the thing to watch (D-055).

**Decidability held** (`just ai-ladder 3 600`): **2 of 3 decided, 1 draw
at the cap**, one win each civ, first attack ~195 s — the same 2-of-3
D-055 reports for the pre-change baseline. An earlier 3-of-3-draw reading
was taken at a **420 s** cap and was not comparable: stronger defence
lengthens matches, so a cap that used to be generous now truncates them.
**When a change makes matches longer, the cap is part of the measurement**
— re-read a ladder result against the cap it was taken at before
concluding anything from it.

**Measured after, through the wire** (`just test-load 4 120`): clean
verdict, 0 desyncs over 476 hash checks, `buildings_known=7`, and
**59.60 µs/squad at 52 squads** against 60.72 for the same scenario
before — the sort is per radius and cached, so it costs nothing per call.
Worst tick 76.6 ms, 0 dropped ticks.

**A note on how nearly this was misattributed.** Two load runs failed
first, both reporting `buildings_known=0` with byte-identical numbers,
and the obvious suspect was this change. It reproduced with the change
reverted, and server-side instrumentation printed nothing at all —
because a second server container held port 4433 and the bots were
reaching it, not the one under test. The rule from D-038's amendment
applies to the harness as well as the code: **read the log before
theorising, and if the instrumentation is silent, doubt the setup before
the diagnosis.**

**Revisit trigger:** if a later unit lands outside the measured band —
tankier than legion_heavy or flimsier than skirmishers — the single flat
`BuildingDef.damage` stops expressing this rule and needs to become
something that scales.

---

### D-066 · 2026-08-04 · Provisional — building damage is on its own scale, and was authored on the wrong one
**Decision:** `BuildingDef.damage` raised on both shipped shooters. First
pass, on evidence that the defence was invisible: town centre **12 → 45**,
watch tower **20 → 80**. **Superseded within the day by D-067**, which
raised them again (60, and 85 at 1700 HP) to meet an explicit anti-rush
rule — read D-067 for the shipped values. No code change in either: the
mechanism was never broken.

**The report was "the town hall was meant to have some ranged defensive
ability but doesn't seem to".** It has one, and it fires: measured, a
shipped town centre engages at 4 cells, on schedule, every 2 s. It simply
did almost nothing.

**The cause is a scale mismatch between two fields with the same name.**
A squad's volley is `UnitDef.damage x alive` — 36 militia at 9.5 is
**342 per second**. A building fires one flat `BuildingDef.damage`,
multiplied by nothing: a town centre was **6 per second**, or 1.8% of one
squad. The numbers look comparable in the `.tres` files; they are a
factor of ~40 apart. Measured, one militia squad against each shipped
defence, no support on either side (the "after" column is this pass's
45/80, not the shipped values — see D-067):

| | before | this pass |
|---|---|---|
| town centre razed in | 63 s, costing **4 of 36** | 82 s, costing **20 of 36** |
| tower razed in | 30 s, costing **4 of 36** | 44 s, costing **26 of 36** |

**Why not higher.** At 65 the town centre wipes a lone militia squad and
survives on 408 of 3000 — which matches the code comment's intent ("an
early rush cannot simply walk into a base"), and is deliberately NOT what
shipped. D-055 is the reason: this project has already had every ladder
match end in a draw because buildings could not be destroyed, and read it
as an AI weakness for several rounds. Defence that is *felt* is the goal;
defence that *repels* trades a real risk to decidability for it. 45 keeps
a lone squad able to take a town centre while losing over half its men.
Raising it further is a live option and a one-line data change.

**Why the tower is 80.** It is bought with 120 stone and is the only
building whose purpose is fighting, so attacking it must be decisively
worse than attacking the town centre you start with — otherwise nobody
builds one. It still falls to a single squad in ~44 s, which keeps a
tower a delay rather than a wall.

**The test gap this went through, which is the part worth keeping.** The
buildings-shoot tests all used a synthetic def — damage 40, a 0.1 s
interval, 20 HP defenders — chosen so a five-tick test can observe a
casualty. They prove the MECHANISM and are silent about the shipped
numbers, and the only test that touched the real `.tres` asserted
`damage > 0`. So: mechanism correct, data nonzero, feature invisible,
everything green. Two tests now run a whole encounter with shipped defs
and assert what it COSTS an attacker, as a floor (a third of the squad
for a town centre, half for a tower) rather than an exact number, so
ordinary tuning does not thrash them.

**Rejected alternatives:**
- *Scaling building damage by something, so the two fields read alike*
  (rejected — a building has no `alive`; the honest fix is to document
  the scale, which `building_def.gd` now does at the field).
- *Leaving it and calling it balance* (rejected — the owner reported it
  as a missing feature, which is what a 1.8%-of-a-squad defence is).
- *Raising building damage generally* (rejected — barracks and storehouse
  are targets by design, and that is D-032's data-driven point).

**Consequences:** attacking into a base is now a real cost, so matches
lengthen — the direction D-056 wants, though nowhere near its 1–2 hours,
and for D-056's own reason: there is still no progression to spend the
time on. AI ladder behaviour is affected and was checked for
decidability, not tuned for.

**Revisit trigger:** if ladder matches start drawing at the time cap
again, this is the first number to look at — and D-055's lesson says
check whether anything can still die before concluding the AI is weak.

---

### D-065 · 2026-08-04 · Accepted — shape travels, and a player's choice latches
**Decision:** Two fixes to D-058, which shipped its server half only.

1. **`SQUAD_INFO` carries `shape`.** It never did. The client resolved
   shape from `UnitDef.formation_shape`, which was correct before D-058
   made shape mutable and was never revisited.
2. **A player order latches.** `SquadSim.set_shape` (the player's entry
   point, via `ORDER_FORMATION`) marks the squad chosen; the simulation's
   own switching goes through the new `SquadSim.suggest_shape`, which
   ignores a chosen squad. The economy now suggests rather than sets.

**Rationale:** the reported symptom was "the formation buttons don't
change the formation of the workers". There were two independent causes
and the second one hid behind the first.

*Workers specifically:* `Economy._tick_hauls` asserted `ring`/`sparse` on
every gathering crew every tick, so a player's choice was undone within
100 ms — one tick. The button worked perfectly and its effect lasted less
than a frame.

*Everybody, invisibly:* shape was not on the wire at all, so no client
ever learned about any shape change. D-058's own text says the server
"resends ordinary `SQUAD_INFO` — the message that already carries shape".
It did not carry shape. The server-side plumbing it describes
(`take_shape_dirty`, per-client visibility filtering, the no-op guard) is
all real, correct, and was sending a message with the field missing.

**This was also a live desync**, not only a cosmetic bug. Shape is in
`composition_hash`: the server hashed the real shape, the client hashed
the UnitDef's. Every gathering crew that reached a node — which is every
gathering crew — put its owner into permanent disagreement with the
server. A test now reproduces it (`test_client_state.gd`), and it fails
by exactly one desync before the fix.

**Why latch rather than let the sim keep switching:** the automatic
ring-while-working switch is a convenience for crews nobody has an
opinion about. A player who presses a button has an opinion, and a rule
that silently reverts a direct order is worse than no rule. The cost is
stated plainly: a crew you have shaped by hand stops auto-switching for
the rest of the match. That is the deal the button makes.

**Rejected alternatives:**
- *Clearing the latch on the next gather order* (rejected — "sometimes
  your order sticks" is harder to learn than "it sticks").
- *Hiding the formation buttons for gatherers* (rejected — it makes the
  symptom go away by removing the feature, and leaves the wire bug).
- *Sending shape in the curve stream* (rejected — that is D-058's own
  revisit trigger, and it fires on bandwidth evidence, which does not
  exist. `SQUAD_INFO` per change is still the cheap answer).
- *Deriving shape on the client from replicated haul phase* (rejected —
  D-058 already rejected replicating the phase, and this bug is not a
  reason to reopen it).

**Consequences:** `SQUAD_INFO` grew a length-prefixed string per squad —
a handful of bytes on a message sent per change, not per tick. Replays
are the wire format byte-for-byte (D-016), so **replay files recorded
before this change no longer decode**. `D-059`'s "ring means working"
client-side inference is now defeatable: a player who parks workers in
`ring` on the road gets the working animation while they walk. Cosmetic,
one-way, and left alone.

**Revisit trigger:** if any future system wants to change a squad's shape
automatically (a shield wall on contact, skirmishers spreading under
fire), it must use `suggest_shape` — and if such a rule is important
enough that it should override a player, that is a real design decision
and belongs here, not in a call site.

---

### D-061 · 2026-08-04 · Accepted — four interface defects, and the one shape three of them share
**Decision:** Four faults reported from real play are fixed, and two of
them establish rules rather than just changing a number.

1. **The HUD is laid out against the window** (`hud_layout.gd`), by two
   separate mechanisms: a CanvasLayer **scale** so it is the same physical
   size on any monitor, and **anchoring** so it fits any window *shape*.
2. **Surviving damage replicates.** `BuildingSim.damage` marks the
   building dirty on any change of health, not only on the killing blow —
   quantised to `HEALTH_REPLICATION_STEPS` (32) so a siege costs a bounded
   number of messages. The client draws a health bar over the building
   itself, not only in the selection panel.
3. **Right-click sets a rally point again.** The building branch of
   `_order_selected` now runs *before* the empty-selection guard.
4. **A building covered in units is selectable** (`selection_pick.gd`):
   squads and buildings are ranked on one scale instead of two.

**The shape three of these share:** each was a rule that was fully
written, correct in isolation, and never reached. Rally orders were
encoded, sent-ready, validated server-side and drawn on the ground — and
the client returned two lines before the branch that sends them, because
selecting a building clears `_selected` and the guard against ordering an
empty selection fired first. `health_fraction` was in the wire format, in
`ClientState`, and drawn by the panel — and only ever carried the value
1.0, because nothing marked a damaged building dirty. Buildings competed
for clicks against a score that was negative by construction, so a
comparison that reads correctly (`if distance < best`) could not be true.

That is the same class as the uncalled `BuildingSim.damage()` of D-055,
`UnitDef.cost`, and `BuildingDef.cost` — but a step harder to find,
because the member here *does* have a caller. The caller is simply
unreachable, or reachable only with an argument that cannot occur. **Grep
for uncalled public members catches the first kind and not this one.** The
only thing that found these was playing the game and noticing that a
thing which plainly ought to work did not.

**Why the HUD needs both scale and anchoring:** either alone looks like it
is enough and is not. On a 16:9 monitor scaling by itself is sufficient,
which is exactly the trap — every common desktop is 16:9, so an anchoring
bug hides until someone runs at 21:9 or drags the window. Anchoring by
itself leaves a 4K HUD the size of a postage stamp. The reference window
is 1280x720 and the scale is `min(w/1280, h/720)`, so any 16:9 window
comes back to a design space of exactly 1280x720 and reproduces the
hand-tuned layout pixel for pixel; other shapes deviate only in where the
edges are.

**Why building health is quantised rather than streamed:** a besieged
building takes damage every attack cooldown, and marking each hit dirty
would resend its whole entry several times a second per attacker — D-003's
per-tick snapshot wearing a health bar. 32 steps is finer than the drawn
bar resolves and bounds a building's whole life to at most 32 health
messages. Note the first scratch always crosses a step, because full
health sits on a boundary: "this building has been touched at all" is
worth a packet.

**Why selection compares two different metrics:** *which squad* is decided
by distance normalised by each candidate's own footprint, so a small squad
clicked squarely beats a huge one merely grazed. *Squad or building* is
decided by raw distance to centre. Normalising both was tried first and
fails: a formation filling the screen scores near zero almost everywhere
and still swallows the town centre standing in the middle of it. Which
centre the cursor is nearer does not care how big either thing is.

**Rejected alternatives:**
- *Godot's `canvas_items` stretch mode for the HUD* (rejected — it pins
  the root viewport to the base resolution, so the 3D world would render
  at 1280x720 on a 4K monitor. The whole point of a big screen here is
  seeing more soldiers).
- *Streaming building health every tick* (rejected — D-003).
- *"A building always wins an overlapping click"* (rejected — clicking a
  soldier standing beside a barracks has to select the soldier; the fix
  must not become the mirror of the bug).
- *Scaling the HUD by adjusting font sizes and widths individually*
  (rejected — one transform carries borders, padding and bar thicknesses
  together, and none of them can be forgotten).

**Measured, not asserted.** `just test-load 4 120`, the same run with and
without the change (stashed), 52 squads:

| | bytes | µs/squad | worst tick |
|---|---|---|---|
| before | 523,544 | 73.07 | 58.3 ms |
| after | 522,880 | 75.52 | 67.3 ms |

Bandwidth is **unchanged** — the after figure is 664 bytes *lower*, which
is run-to-run noise, and so is the µs/squad difference (D-020's caveat:
the order of magnitude is the result, not the third digit). Both runs:
`VERDICT ok`, 0 desyncs, 0 building desyncs, 0 dropped ticks. So health
replication at 32 steps costs nothing detectable at this scale, which is
what quantising was for. It has NOT been measured under a long siege of
many buildings at once, which is where it would show if anywhere.

**Consequences:** the HUD's scale is clamped to [0.75, 2.0], so a very
large monitor gets a HUD that stops growing rather than one that keeps
pace — deliberate, since the reason to own one is seeing more map. Mouse
positions arrive in real pixels and HUD geometry is in design units, so
anything doing its own pixel arithmetic against the HUD must convert
(`Client._to_hud`); Godot handles Controls itself, so this is only the
minimap hit-test and the drag box. Both are converted; a third such site
added later and left unconverted would fail silently and look like a
mis-aimed click rather than a scaling bug.

**What is NOT verified, and should be said plainly:** the health bar's
DRAWING has not been photographed. The HUD was rendered and looked at at
1280x720, 1920x1080 and 2560x1080 (the last is the case scale alone
cannot fix), and the replication fix has a test that was watched failing.
But getting a building damaged *on camera* under the software rasteriser
did not happen: `test-client`'s capture scenario never had its base
attacked, and a ladder match with AI opponents killed the client
container every time — llvmpipe at 200s+ with four players' armies is
past what it will carry on this host. One real defect in the drawing was
found by reading rather than seeing (the bar of a destroyed building was
never hidden, because `_refresh_buildings` skips past the update on the
`destroyed` branch — it would have hung over the rubble EVERY time a
building died). Treat the rest of that path as reviewed, not proven, and
look at it the next time a real match is played.

**Revisit trigger:** if the HUD grows a piece that must stay a fixed
number of REAL pixels regardless of scale — a crosshair, a
pixel-art-aligned element — the single-transform approach stops being
sufficient and the layer split has to be reconsidered.
---

> **D-068 through D-074 are one argument and read in ascending order**,
> against this file's usual newest-first convention. They are the output
> of the age/tech planning milestone Q15 reserved, all dated 2026-08-04.
> D-068 is the derivation base: every number in the six that follow is
> supposed to trace back to a line in it. Read it first or the rest look
> arbitrary.
>
> **Numbering note, and a near miss worth recording.** This block was
> first written as D-063…D-069 against a worktree that was 14 commits
> behind `origin/main`. Main had meanwhile allocated **D-063 through
> D-067** for the HUD, formation-on-the-wire, building damage and the
> anti-rush rule — so the block was renumbered to D-068…D-074 before the
> merge, while every occurrence was still unambiguously local.
>
> **The check that missed it was run against un-fetched refs**, which is
> the same shape as trusting a stale sweep over a live run (D-043).
> Allocating a decision number requires `git fetch` first, then a scan of
> **both** this file's headings and the code citations — D-048, D-049,
> D-050, D-053, D-054, D-057 and D-062 are all cited by code with no
> entry here, so the highest heading has never been the highest number
> in force. That doc debt is unfixed and is its own job.
>
> **Milestone numbering moved too:** main's ladder is M7 = real models
> and textures, M8 = Steam. The epoch work is therefore **M9**.

### D-068 · 2026-08-04 · Provisional — what a 1–2 hour match is made of
**Decision:** The design centre is a **90-minute match**, with 60 and 120
as the band edges (D-056 set 1–2 hours). Six phases, and for each one the
question the player is actually answering. **This table is the derivation
base for D-069's epoch timings and D-072's costs. A number in either that
cannot be traced to a row here is unjustified and should be challenged.**

| Phase | Minutes | Epoch | The decision being made |
|---|---|---|---|
| Opening | 0–8 | 1 | **Where**, not what. Site quality versus site safety. |
| Expansion | 8–22 | 1→2 | The first real fork: bank toward the next epoch, or field levy troops now. |
| First contact | 22–35 | 2 | Contest the middle or concede it. Which archetype to commit to. |
| Consolidation | 35–55 | 3 | Where your ground actually *is*, and what you are willing to lose. |
| Mid-war | 55–75 | 3→4 | Commit to a breakthrough, or grind. Siege is an investment that does not defend you. |
| Decision | 75–95 | 4→5 | The decisive battle, or bleed them. Signature troops arrive and are scarce. |

**Rationale — the gap this has to close is 4×, and it is in the opening.**
Measured: first contact at ~326 s (5.4 min) and `ai-ladder` deciding at
~325 s. This account puts first contact at ~22 min and the decision after
75. **The entire current match fits inside the row labelled "Opening."**
That is the honest size of the problem, and it is why D-056's tuning
could not reach the target and said so.

**Both figures predate D-066/D-067**, which raised building damage
sharply and imposed "one squad must fail, two must succeed" — a change
that pushes decidedly toward longer matches and was made for its own
reasons, not for this table. **Re-measure before treating the 4× as
current.** The direction of the gap is not in doubt; its size is, and a
number that has been overtaken is exactly what this project's own rules
say not to quote.

The stretch is not achieved by slowing anything down. It is achieved by
epoch 1 having no standing army in it at all (D-069): the opening is
genuinely economic because there is nothing else to spend on yet. D-056's
2026-08-04 amendment already established that the owner wants the slower
ramp — this extends the same direction on purpose rather than as a
side effect of gatherer crew size.

**Time in epoch, derived from the table:** E1 0–15, E2 15–33, E3 33–55,
E4 55–75, E5 75+. That is 15–22 minutes a rung, against a genre norm of
8–20. Deliberately at the top of the band: five rungs at genre-typical
pace produces a 50-minute match, not a 90-minute one.

**This entry also answers Q15's "is an army a ratchet or a running cost?"
— it is a running cost.** The phase-by-phase account is what the owner
said should decide it, and the account cannot support its own last three
rows without it:

- **Rows 4–6 need losing an army to hurt.** Without upkeep a defeat costs
  only the rebuild time, so there is no such thing as a decisive battle —
  which is the entire content of the "Decision" row.
- **Raiding must be strategy, not flavour.** The Northmen identity
  (D-071) is raiding economy; with no upkeep, killing workers slows an
  opponent's *rate* of buying and never the *size* of what they hold.
- **It is already measured.** D-056 found Legion banking a peak stockpile
  of **2,480 while pinned at the squad cap**. Accumulation with nowhere
  to go is exactly the endgame texture rows 5–6 need to not have.

**Shape:** a per-soldier food drain per second (`UnitDef.upkeep_food`,
scaled by `CivDef.upkeep_modifier`). When the wallet cannot pay, **morale
decays** rather than soldiers vanishing — this reuses D-019's existing
morale and routing machinery instead of inventing a second failure mode,
and a starving army breaking is the historically apt outcome.

**Upkeep replaces `squad_cap` as the binding constraint, and that resolves
Q15's "one mechanism too many" worry.** Both stay, with different jobs:
`squad_cap` reverts to being the **engineering ceiling** protecting
D-018's ~50 squads/player and D-020's tick budget, and should be set high
enough that it is not what a player feels. Upkeep is the **design**
constraint and is what actually bites. Q15 was right that two caps is one
too many — the fix is that only one of them is a cap you play against.

**Rejected alternatives:**
- *No upkeep, reach 90 minutes on epoch costs alone.* Rejected — it
  produces the D-056 endgame verbatim: two maxed armies and a stockpile
  nobody can spend.
- *Upkeep as a hard population cost (AoE-style houses).* Rejected — that
  is a second hard cap, which is the thing Q15 warned against, and it
  makes losing an army *free* again.
- *Unpaid upkeep kills soldiers.* Rejected — a death spiral with no
  player agency, and it fights D-024's casualty model for ownership of
  `alive`.

**Consequences:** the AI must learn to value an army it has to keep
paying for, which is a real change to `ai_player.gd` and not a tuning
pass. The HUD needs a net-income figure or upkeep is invisible until it
hurts. And every cost in D-072 is now a *rate* decision as well as a
price.

**Revisit trigger:** if telemetry (D-074) shows matches landing outside
60–120 minutes in the majority, this table is wrong and D-069's and
D-072's numbers must be re-derived from a corrected one — not patched
individually, which is precisely the failure D-056 recorded.

---

### D-069 · 2026-08-04 · Provisional — the epoch ladder: five rungs, antiquity to high medieval
**Decision:** **Five epochs**, spanning antiquity to the high medieval
period. The ladder is **shared by every civ** — same count, same gate
shape — and civs differ in what each rung *contains*, never in its
structure.

**The filter every rung had to pass: it must name a new verb, not a
bigger number.** A rung whose honest one-line justification is "the
stats go up" was cut rather than rewritten.

| # | The epoch is when… | Verb | Player time |
|---|---|---|---|
| 1 | …a **place** becomes possible. Founding party, first town hall, gatherers, levy foot. | settle | 0–15 |
| 2 | …a **standing army** becomes possible. Barracks-line specialists; the counter triangle arrives whole. | field | 15–33 |
| 3 | …**combined arms and holding ground** become possible. Cavalry, missile specialists, towers and claimed ground. | hold | 33–55 |
| 4 | …**siege** becomes possible. Fortified ground becomes attackable again; heavy horse. | break | 55–75 |
| 5 | …**elite and scarce** troops become possible. Knights, per-civ signature units, the castle tier. | decide | 75+ |

**Epochs 3 and 4 are a matched pair and must ship together.** Epoch 3
makes ground holdable; epoch 4 makes it breakable again. Shipping 3
without 4 produces the *turtle-to-last-epoch* failure in its purest form
— a game where the correct move is always to fortify and wait.

**The advance gate is data, not code:** a new `/epochs/*.tres`
(`EpochDef`) carrying index, display name, `cost_*`, `research_time` and
prerequisite building ids. Researched at a town centre, occupying it for
the duration. Same reasoning as D-010 — the pacing lever most likely to
need a hundred tuning passes must be editable as text, and **no script
may name an epoch** any more than it may name a civ (D-047).

**The gate's job is to create the bank-versus-army fork in D-068's row 2**,
so it has to cost enough that paying it visibly means not fielding troops
for a stretch. Provisional, and explicitly to be replaced by telemetry:

| Advance | food | wood | gold | stone | research |
|---|---|---|---|---|---|
| 1→2 | 500 | 300 | — | — | 90 s |
| 2→3 | 800 | 500 | 200 | — | 120 s |
| 3→4 | 1200 | 800 | 500 | — | 150 s |
| 4→5 | 1800 | 1200 | 900 | 400 | 180 s |

Sanity check against measurement rather than feel: Legion banked a peak
of 2,480 with no epochs to spend it on (D-056). The 4→5 advance is
deliberately priced above that peak, because a stockpile that can absorb
an advance without a decision is not a gate.

**Scope fences — what this milestone does NOT add**, so that the ladder
is not read as licence: no naval, no heroes or unique-hero mechanics, no
campaign layer, no per-civ *mechanics* beyond knobs every civ has (D-047),
and **no wall system**. Epoch 3's "hold" is delivered by towers,
`no_build_radius` claimed ground (D-062) and building health, all of which
exist. A real wall system is a substantial piece of pathfinding and
rendering work and needs its own decision; if epoch 3 proves hollow
without it, that is the trigger to open one.

**Rejected alternatives:**
- *Four epochs (AoE2's count).* Rejected — historically produces 25–45
  minute matches; reaching 90 would need each rung stretched well past
  the point where its content stays interesting.
- *Six.* Rejected — a sixth rung could not pass the new-verb filter
  without either splitting siege in two or reaching into gunpowder, which
  the chosen span excludes.
- *Per-civ epoch counts or asymmetric ladders.* Rejected — a balance
  problem of a different order, and it breaks the shared advance gate
  that makes "who is ahead" legible to both players and the AI.

**Consequences:** the archetype vocabulary grows from 8 to roughly 25–30.
D-047 binds the client's train keybinds to *archetype*, so that table
stops fitting on a keyboard — the UI must become epoch-scoped. This is
the *unlock overload* failure mode and D-074 owns detecting it.

**Revisit trigger:** any rung that telemetry shows is entered and left
without the player's behaviour changing is not an epoch, it is a stat
bump, and should be merged into its neighbour.

---

### D-070 · 2026-08-04 · Accepted — rosters grow by replacement, and what that costs
**Decision:** Each epoch unlocks **genuinely new archetypes alongside the
old ones** (owner's call, 2026-08-04), rather than upgrading an existing
`UnitDef` in place. `spearmen` (E1) and `pikemen` (E3) are different
archetypes with different `.tres` files, not two versions of one.

**Rationale:** consistent with D-047, which rejected shared UnitDefs plus
per-civ multipliers because "it hides a unit's real numbers behind
arithmetic in another file, and this project optimises for stats being
directly readable and editable as text." The same argument applies across
epochs exactly as it did across civs. It also needs **no new lookup
machinery**: `UnitRoster.for_civ_archetype()` still returns one def per
(civ, archetype) pair, and epoch gating is a filter on top.

**The content bill, accepted up front rather than discovered in epoch 3.**
At 6 civs × 5 epochs with each civ fielding a subset per rung, the
endpoint is roughly **90–130 unit `.tres`**, against ~40 for
upgrade-in-place. That is the price of readable stats and it is being paid
knowingly. Epoch 1 alone is ~20 files, which is why it is the vertical
slice (D-072).

**Obsolescence is replacement's known failure mode, and upkeep is the
answer.** Under a hard squad cap, an epoch-1 levy squad at epoch 5 is
*strictly* bad: the cap makes power-per-squad the only currency, so cheap
units are worthless and the player is punished for owning them. Under
D-068's upkeep, power-per-*resource* matters again, and cheap old units
have a real job — screening, map presence, garrison, escorting builders —
because they cost less to keep. **This is the load-bearing connection
between D-068 and this entry: without upkeep, replacement rosters
manufacture trash.** If upkeep is ever dropped, this decision has to be
reopened with it.

**Rejected alternatives:**
- *Upgrade in place* (militia → man-at-arms). Rejected by the owner —
  ~40 files instead of ~130 and no obsolescence problem at all, but every
  unit's real numbers become a chain of edits across epochs.
- *Hybrid — core lines upgrade, each epoch adds one new archetype.*
  Rejected as the most design work to keep coherent for a benefit that
  upkeep already delivers.

**Proposed schema, logged against D-010 — NOT IMPLEMENTED.** This
milestone is documents only; nothing below exists in code yet, and this
list is the specification for M9, not a description of the repo:

| Field | Type | Default | Purpose |
|---|---|---|---|
| `UnitDef.epoch` | `int` | `1` | earliest epoch this unit may be produced |
| `UnitDef.upkeep_food` | `float` | `0.0` | per soldier per second (D-068) |
| `BuildingDef.epoch` | `int` | `1` | earliest epoch this building may be founded |
| `CivDef.upkeep_modifier` | `float` | `1.0` | D-068 |
| `CivDef.epoch_advance_speed` | `float` | `1.0` | who climbs faster |
| `CivDef.epoch_names` | `Array[String]` | `[]` | five display strings, flavour only |

Gating is one added clause in the existing chain: a def is producible when
`def.epoch <= player_epoch`, checked beside the `for_civ_archetype()` null
test at `server.gd:1115`. Defaults are all chosen so an unaware `.tres`
is epoch-1 and free to keep — the same safe-default reasoning D-056 used
for `damage_vs_buildings`.

**Revisit trigger:** if the unit count passes ~130, or if two civs'
versions of the same rung stop differing by more than numbers, the
upgrade-in-place model should be re-costed honestly rather than defended.

---

### D-071 · 2026-08-04 · Provisional — the civ design frame, and six civilizations
**Decision:** Six civs at launch, each filling the **same seven-column
frame** so that distinctness is structural rather than a matter of taste.
Governing rule: **no two civs may match on more than one column.**

| | Legion | Northmen | Magyars | Byzantines | Carthaginians | Chinese |
|---|---|---|---|---|---|---|
| **Axis** | quality | quantity | mobility | fortification & siege | economy & flexibility | ranged attrition |
| **Basis** | Rome, Republic → Late Empire | Norse, 790–1100 | Magyar confederation → Kingdom of Hungary | Eastern Rome, 330–1200 | Phoenician-Punic world, 800–146 BC | Warring States → Tang |
| **Economy** | steady; strong from few well-held sites | raid-supplemented; profits from wrecking yours | low infrastructure early, settles late | slow, secure, stone-heavy | highest gather and the broadest use of gold | infrastructure-heavy, food-led |
| **Military** | heavy foot + disciplined missile; no light horse | cheap fast foot + skirmishers; no heavy foot | horse archers and light horse; poor foot, no siege | defensive foot, towers, engines | the broadest roster, most of it costing gold | massed crossbow; adequate foot, weak horse |
| **Best at** | winning even fights; holding a line | early tempo; raiding economy | map control; punishing overextension | holding ground *and* cracking it | out-scaling; adapting late | grinding down at distance |
| **Bad at** | reacting; map control | pitched battles; sieges | taking fortified ground | open field; early tempo | any specific fight before it is rich | being closed on |
| **Signature (epoch)** | *comitatenses* — highest morale in the game (E4) | Great Heathen Army — cap and tempo bonus (E2) | mounted missile at reach (E3) | the siege train (E4) | mercenaries — most archetypes, gold-priced (E3) | crossbow volley — earliest strong missile (E2) |

**Frame audit.** The two closest pairs, checked rather than assumed:
*Byzantines and Chinese* both defend prepared positions, but one holds
with structures and also **cracks** them, the other holds with fire and
cannot crack anything — one shared column. *Northmen and Magyars* both
raid, but one raids on foot with tempo and the other cannot be caught at
all — one shared column. Rule holds.

**Rationale for the specific factions — the arc test.** With five epochs
and replacement rosters (D-070), a faction needs **five believable
development stages**, not one iconic army. That constraint, not
recognisability, selected this set:

| Civ | settle → field → hold → break → decide |
|---|---|
| Legion | village → manipular Republic → Marian legion → Imperial → Late Roman *comitatenses* |
| Northmen | steading → raiding parties → Great Heathen Army → jarldoms and burhs → Norman-influenced heavy horse |
| Magyars | nomad clans → horse-archer confederation → raids on Europe → settled Kingdom → knights *and* horse archers |
| Byzantines | late Roman town → Justinianic reconquest → *thematic* system → Macedonian dynasty → Komnenian |
| Carthaginians | Phoenician colony → trading city → Punic mercantile empire → mercenary armies → Barcid Spain |
| Chinese | Warring States → Qin/Han crossbow volley → Three Kingdoms → Sui/Tang → Song-era massed missile |

**Scythians fail this outright** and were rejected for it despite being
the purest horse-archer culture available: nomadic throughout, with no
fortification phase to grow into, so epochs 3–5 would have to be invented
wholesale. Magyars genuinely settle, and that transition **is** their
epoch 4.

**The dates do not line up, and this entry does not pretend they do.**
Rome and the Northmen never met. Carthage is destroyed in 146 BC and has
no historical epoch 4 or 5 at all; its late rungs run through mercenary
armies and Barcid Spain. **The ladder is a game progression, not a shared
calendar** — each civ's five rungs are flavoured from that culture's own
arc, independent of absolute date. This is the AoE convention, adopted
deliberately and stated so nobody has to rediscover it in review.

**Known flavour redundancy, accepted with eyes open: Byzantines are
Rome.** Mechanically they are cleanly distinct from Legion — defensive
doctrine and engineering versus manipular quality — but two Roman civs in
a six-civ launch roster is something a reviewer will notice.
**Sassanids** are the alternate and avoid it entirely while giving Legion
a natural rival; the cost is that they pull hard toward cataphracts and
start colliding with the Magyars' cavalry column. Also verified clean:
Huns and Scythians (mobility), Assyrians (fortification), Kushites
(ranged).

**All six ids verified against `tests/test_civs.gd:43`** — a raw
substring match of each civ id against every non-test, non-addon `.gd`
file, comments included. `grep -ril <id> --include=*.gd .` returns
nothing for all six. This was checked *before* the names were chosen, not
after, because a late collision means renaming a civ everywhere.

**Rejected alternatives:** *English longbowmen for the ranged slot*
(rejected — the longbow is a 1300s+ weapon, past the chosen span, and
cannot carry epochs 1–3). *Venetians or Genoese for the mercantile slot*
(rejected — no antiquity end; they do not exist before ~700 AD).

**Consequences:** `tests/test_civs.gd:170` draws 4000 random civs and
expects an even split; at six civs the expectation moves to ~667 with a
±15% band. Tests that index `CivRoster.ids()[0]`/`[1]` compare a
different pair once the roster is sorted with six names in it. Both need
updating with the roster, and both are test-only changes.

**Revisit trigger:** the first civ whose identity cannot be expressed
through a knob every civ has (D-073). That is D-047's revisit trigger
inherited, and it is the line between six civs and six special cases.

---

### D-072 · 2026-08-04 · Provisional — epoch 1 in full, and the budget its numbers come from
**Decision:** Epoch 1 is specified to shipping depth as the vertical
slice. Every civ fields **four archetypes**: `founders` and `gatherers`
(neutral pool, unchanged), one shared `levy`, and **exactly one exclusive
unit that is the civ's thesis in miniature**.

**The power budget, and why it exists.** Costs are derived from a stated
exchange rate, not authored per unit, because otherwise every unit ends up
independently slightly too good:

- **DPS** = `squad_size × damage / attack_interval`
- **EHP** = `squad_size × health`
- **V** (squad power) = `sqrt(DPS × EHP)` — geometric so it stays roughly
  linear in squad size rather than quadratic
- **RP** (resource points) = `food + wood + 1.5 × (gold + stone)`

**What V does not price, stated up front so it is not misread as a
verdict:** `attack_range`, `move_speed`, `vision_range`, `bonus_vs`,
`morale`. It is a first-pass screen for line infantry and it
systematically **undervalues missile and scouting units**.

**The screen was run against the shipped roster first, and it found a
real defect.** Computed from the `.tres` as they stand:

| unit | V | RP | V/RP |
|---|---|---|---|
| legion_militia | 1064 | 75 | **14.2** |
| legion_spearmen | 802 | 100 | 8.0 |
| legion_archers | 682 | 105 | 6.5 |
| legion_heavy | **930** | **190** | 4.9 |
| northmen_militia | 883 | 40 | **22.1** |
| northmen_spearmen | 666 | 53 | 12.6 |
| northmen_skirmishers | 556 | 55 | 10.1 |
| northmen_cavalry | 656 | 98 | 6.7 |

Two things fall out, and both are arithmetic on shipped data rather than
opinion:

1. **Militia leads on both V and V/RP for both civs.** Massing militia is
   correct play, and only `bonus_vs` argues against it — which militia
   dodges by being a generalist with `bonus_vs = {}`, so it is never hard
   countered, merely un-bonused.
2. **`legion_heavy` has lower DPS than `legion_militia` (257 vs 342) and
   near-identical EHP (3360 vs 3312), at 2.5× the cost.** What it buys is
   `bonus_vs {cavalry: 1.5}` and better morale — against a Legion mirror,
   nothing; against Northmen, one of four archetypes. It is very likely
   overpriced. *Not proven*: range, morale and counters are outside the
   metric. Recorded as a finding to verify in play, not a fixed defect.

**Two rules follow, and epoch 1 is built to satisfy them:**

- **Price buys power.** Within a role, a more expensive unit must have
  higher **V**. `legion_heavy` fails this today.
- **No free lunch.** Within a civ, epoch and role, no unit may lead on
  both **V** and **V/RP**. (Largely an epoch-2+ rule; at epoch 1 only
  Legion fields two line units, and it is the test case.)

**Band for epoch-1 line units: V 550–780, V/RP 11–21.** Where a civ sits
*within* the V/RP range is its quality-versus-quantity axis — that is the
axis, expressed as one number.

| Unit | role | sz | hp | dmg | int | rng | spd | cost | V | V/RP |
|---|---|---|---|---|---|---|---|---|---|---|
| `legion_levy` | line | 30 | 78 | 7.5 | 1.0 | 1.9 | 3.3 | 55f | 726 | 13.2 |
| `legion_veterans` ★ | line | 20 | 130 | 13.0 | 1.05 | 1.8 | 3.2 | 55f 20w | **802** | 10.7 |
| `northmen_levy` | line | 40 | 55 | 5.5 | 1.0 | 1.9 | 3.8 | 34f | 696 | **20.5** |
| `northmen_raiders` ★ | spec | 24 | 50 | 7.0 | 1.0 | 1.9 | **5.2** | 30f 10w | 449 | 11.2 |
| `magyar_levy` | line | 30 | 62 | 6.0 | 1.0 | 1.9 | 3.6 | 38f | 579 | 15.2 |
| `magyar_outriders` ★ | spec | 16 | 58 | 7.0 | 1.1 | 2.0 | **6.4** | 30f 10g | 307 | 6.8 |
| `byzantine_levy` | line | 32 | 82 | 6.0 | 1.1 | 1.9 | 3.1 | 50f | 677 | 13.5 |
| `byzantine_watchmen` ★ | spec | 28 | 105 | 5.5 | 1.2 | 2.0 | 2.6 | 45f 25w | 614 | 8.8 |
| `carthaginian_levy` | line | 30 | 62 | 6.2 | 1.0 | 1.9 | 3.4 | 30f 20w | 588 | 11.8 |
| `carthaginian_tradesmen` ★ | econ | 6 | 40 | 1.0 | 2.5 | 2.0 | 3.4 | 22f | *exempt* | — |
| `chinese_levy` | line | 34 | 64 | 6.0 | 1.0 | 1.9 | 3.4 | 42f | 666 | 15.9 |
| `chinese_bowmen` ★ | spec | 26 | 52 | 8.5 | 1.6 | **6.8** | 3.0 | 35f 35w | 432 | 6.2 |

★ = the civ's exclusive archetype. All six levies sit in band; Legion's
veterans beat its levy on V (802 > 726) at lower V/RP (10.7 < 13.2), so
both rules hold.

**Specialists are exempt from the band, and each one's non-V property is
named** — this is the metric's blind spot being handled honestly rather
than by tuning numbers until they hit a target:

- `northmen_raiders` — speed 5.2 and vision 16. Buys tempo and the
  ability to reach an undefended economy.
- `magyar_outriders` — speed 6.4, vision 22, `armour_class = cavalry`.
  Buys information. The clearest case of V being the wrong lens; it is
  6.8 V/RP and still correct.
- `byzantine_watchmen` — **105 EHP per soldier, the highest in epoch 1.**
  Under per-soldier upkeep (D-068) that is durability you do not pay a
  crowd for, which is precisely what holding ground means.
- `chinese_bowmen` — range 6.8, the only ranged unit in epoch 1. V cannot
  price not being hit back.
- `carthaginian_tradesmen` — economic; exempt entirely, like `gatherers`
  (V/RP 1.2). Higher `carry_capacity` and gold-weighted gathering.

**Horse archers take `armour_class = cavalry`, not `missile`.** They are
mounted, so spears must counter them, and D-032's triangle only works if
the class describes what beats the unit rather than what it carries.
Reach is expressed by `attack_range`, which is where it belongs.

**Per-soldier upkeep automatically taxes the quantity civs, and that is
why D-068 made it per soldier rather than per squad.** `northmen_levy`
carries 40 soldiers to Legion's 30 for comparable squad power, so it pays
33% more upkeep for the same V. Quantity's advantage is bought back over
time instead of being free — no extra knob, no special case.

**Test constraints, checked on paper before any file is written:**
`tests/test_civs.gd:93` requires each civ to field more than two
archetypes with at least one exclusive — every civ has four and exactly
one exclusive. `tests/test_civs.gd:113` requires a shared archetype to
differ across civs in `damage`, `health` and `cost_food` — `levy` differs
on all three across all six.

**Epochs 2–5, one paragraph each, deliberately no more.** E2 completes the
counter triangle per civ and lands the Northmen and Chinese signatures.
E3 adds cavalry, missile specialists and the tower/claimed-ground game,
plus Carthage's mercenary breadth. E4 adds siege and heavy horse, and the
Legion and Byzantine signatures. E5 adds scarce elite troops and the
castle tier. Numbers for these are **not** set here: they should be
derived from D-068's table after epoch 1 has been played, exactly as
epoch 1's were derived before it.

**Revisit trigger:** the first time a levy is still the correct
front-line purchase at epoch 3, the ladder is not delivering new verbs
and D-069 is wrong, not this table.

---

### D-073 · 2026-08-04 · Accepted — the knob inventory, and what blocks implementation
**Decision:** Every mechanical claim in D-071 is mapped here to the
parameter that expresses it. A claim with no knob is either **given a knob
every civ has, or cut** — settled on paper, before any code, because
`tests/test_civs.gd:43` makes "no script may name a civ" a test rather
than a guideline.

| Claim (D-071) | Knob | Status |
|---|---|---|
| Legion quality; wins even fights | `UnitDef` `health`/`damage`/`squad_size`/`cost_*` | exists |
| Legion *comitatenses*: never breaks | `UnitDef` `morale`, `rout_threshold`, `rout_rally_margin`, `morale_recovery_per_second` | exists |
| Legion bad at reacting | low `move_speed`; no fast archetype in its subset | exists (structural) |
| Northmen quantity | `squad_size` against `cost_*` | exists |
| Northmen Great Heathen Army | `CivDef.squad_cap_bonus`, `CivDef.production_speed` | **declared, INERT** |
| Northmen raiding | `move_speed`, `vision_range` | exists |
| Northmen no heavy foot | roster subset — which `.tres` name the civ | exists (structural) |
| Magyar mobility, map control | `move_speed`, `vision_range` | exists |
| Magyar poor siege | `UnitDef.damage_vs_buildings` (default 0.15) | exists |
| Magyar low infrastructure early | per-civ building availability | **blocked — defect 3** |
| Who climbs the ladder faster | `CivDef.epoch_advance_speed` | **new** |
| Byzantine fortification | `BuildingDef` `max_health`, `no_build_radius`, `attack_range`, `damage` | exists |
| Byzantine siege train | high `UnitDef.damage_vs_buildings` | exists |
| Byzantine bad early tempo | `BuildingDef.build_time`/`cost_*`; low `move_speed` | exists |
| Carthage highest gather | `CivDef.gather_speed` | **declared, INERT** |
| Carthage broad gold-priced roster | subset size + `cost_gold` | exists (structural) |
| Chinese reach, earliest missile | `attack_range` + `UnitDef.epoch` | exists + **new** |
| Chinese infrastructure-heavy | per-civ buildings | **blocked — defect 3** |
| Army as a running cost (D-068) | `UnitDef.upkeep_food`, `CivDef.upkeep_modifier` | **new** |
| Epoch gating (D-070) | `UnitDef.epoch`, `BuildingDef.epoch` | **new** |
| Civ-flavoured epoch names | `CivDef.epoch_names: Array[String]` | **new** |

**Three claims were cut here for having no knob.** Recording them is the
point of the exercise — each would have become a branch:

1. *"Legion squads do not rout while a friendly squad is adjacent."*
   Needs adjacency-aware morale that only one civ has. **Cut**, and
   re-expressed as simply the highest `morale` and `rout_rally_margin` in
   the game. The fantasy survives; the branch does not.
2. *"Byzantine builders raise fortifications faster."* **There is no
   build-speed knob at all** — `building_sim.gd:359` is
   `_progress += dt / build_time` with no multiplier, and
   `advance_production` at `:229` is the same. Rather than cut this,
   **add `CivDef.build_speed: float = 1.0`**, the obvious sibling of the
   two inert knobs beside it. This is the correct outcome of a
   parameterisation pass: the claim named a gap that every civ should
   have access to.
3. *"Carthage can hire another civ's units."* Would require a script to
   know another civ exists — the exact failure D-047 exists to prevent.
   **Cut**, and re-expressed as a broader *own* roster carrying gold
   costs.

**Four defects that block implementation.** None is caused by this
milestone; all sit directly under it:

1. **Three `CivDef` knobs are declared, shipped with non-default values,
   and read by nothing.** `squad_cap_bonus = 4` and
   `production_speed = 1.3` on northmen are inert —
   `match_state.gd:420`, `building_sim.gd:229` and `economy.gd:382` apply
   no multiplier anywhere. Two of D-071's six civ identities depend on
   them. This is the **fourth** instance of the declared-and-unread class
   (`UnitDef.cost`, `BuildingDef.cost`, `BuildingSim.damage` per D-055),
   and it is the defect class this project's testing discipline is blind
   to by construction: nothing fails, the game simply lacks a rule.
2. **`built_by` is keyed two ways.** `server.gd:993` passes the builder's
   **archetype**; `client.gd:1850` and `:1951` pass its **UnitDef id**;
   `building_def.gd:59` documents the field as ids. It works today only
   because both builders are neutral units where the two strings
   coincide. Epoch 3+ adds civ-specific builders and it breaks — the
   client will offer a build the server refuses.
3. **`BuildingDef.civ` is dead weight** — declared, always `neutral`,
   never filtered on anywhere. There is no `BuildingRoster.for_civ()`.
   Two civ identities above are blocked on it.
4. **`produces` is documented as UnitDef ids and actually holds
   archetypes** (`building_def.gd:55` versus `building_sim.gd:182`).
   Harmless today, actively misleading once epoch-gated production is
   written against the comment.

**Consequences:** defects 1 and 3 are prerequisites, not cleanup — two of
six civs cannot be expressed until they are fixed. Per D-022's standing
rule, each of the three inert knobs must be proved by a test **observed
to fail before it is trusted**: turn the knob, watch the test go red,
revert.

**Revisit trigger:** any future civ claim that reaches this table with no
knob and no general knob worth adding. That is the D-047 boundary, and
the honest response is to amend D-047, not to quietly add a branch.

---

### D-074 · 2026-08-04 · Accepted — M9's exit criteria, its failure modes, and the telemetry that catches them
**Decision:** M9 is **"the ladder is real, and a match is worth an
hour."** Written before the code, per the standing rule that produced
D-022, D-026, D-027, D-044 and D-046.

**Exit criteria.** Every one asserts something *happened*, not that
nothing complained — D-022's first rule, bought with M1's vacuous log
grep:

1. `just ai-ladder` decides a **majority of matches in 60–120 minutes**.
2. **Every epoch is entered** in a majority of decided matches. An epoch
   never reached is content nobody has played.
3. **Time-in-epoch** lands within D-068's bands ±50%. Outside that,
   D-068's table is wrong and its numbers get re-derived together — not
   patched one at a time, which is the failure D-056 recorded.
4. `tests/test_civs.gd:43` still green **at six civs**; no script names a
   civ.
5. A sibling test: **no script names an epoch.** The ladder lives in
   `/epochs/*.tres` and nothing may hardcode a rung.
6. Each of `squad_cap_bonus`, `production_speed`, `gather_speed` and the
   new `build_speed` has an **observable effect**, each proved by a test
   watched to fail first.
7. **Upkeep demonstrably happens**: a match reports non-zero upkeep paid,
   and at least one squad routs from starvation. A criterion that could
   pass with upkeep switched off is worthless.
8. **Obsolescence check**: epoch-1 units are still being produced after
   epoch 3 in a measurable fraction of matches. This is the criterion
   that decides whether D-070's replacement model worked.
9. **Tick budget holds**: a 20-player match that reaches epoch 5 reports
   **0 over-budget ticks**, and per-squad cost is re-quoted **with its
   squad count** (CLAUDE.md's standing rule — the figure is meaningless
   without one).

**A prerequisite, and M9 should not start without it.** M6 left the rise
from M4's **40.8 µs/squad at 120 squads** to **~77** unattributed, and
worst-tick figures from that session are known unreliable (a run with
strictly less work reported 146 ms where a fuller run reported 52 ms,
because the host was building containers). **M9 adds load on top of an
unexplained regression.** Attribute it first, or criterion 9's numbers
cannot be interpreted. Where the sweep and a live run disagree, believe
the live run (D-043).

**Failure modes, each paired with the measurement that detects it.**
Naming the detector is the point; a failure mode with no detector is a
worry, not a criterion:

| Failure | What it looks like | Detector |
|---|---|---|
| *Boom-is-always-right* | advancing dominates; nobody fights early | attacks before epoch 3 ≈ 0; advance timestamps near-identical across civs |
| *Turtle-to-last-epoch* | fortify and wait is correct | buildings destroyed ≈ 0 before epoch 4; time-in-epoch-5 > 50% of match |
| *Obsolescence* | epoch-1 units become trash | criterion 8 |
| *Unlock overload* | the UI collapses under ~30 archetypes | count of simultaneously producible archetypes per building at epoch 5; > ~12 means the train UI must become epoch-scoped |

**Telemetry to add to `AI_STATS` / `ai-ladder`**, extending what D-056
already proved the value of — `peak_stockpile`, `afford_refusals` and
`cap_refusals` turned a balance argument into a number:

- `epoch_advance_ticks[]` per player, and `time_in_epoch[5]`
- `army_value_over_time` — summed **V** per D-072's metric
- `resource_idle_time` — stockpile sitting unspent
- `upkeep_paid`, `upkeep_unpaid_ticks`, `routs_from_starvation`
- `produced_by_epoch` histogram, which is criterion 8's evidence

**Also fix, because M9 depends on it:** `test-client`'s casualty gate is
already known to pass without any fighting — founding a town hall reports
through the casualty path (recorded in D-045). M9 changes the opening
again, so a gate that cannot see combat will hide exactly the regressions
this milestone is most likely to cause.

**Revisit trigger:** if criteria 1–3 pass but the match is not *enjoyable*
for an hour, the numbers are right and D-068's phase table is describing
the wrong game. That is a design failure telemetry cannot detect, and the
only instrument for it is playing it.

---

### D-060 · 2026-08-04 · Accepted — squads take up room, at squad granularity
**Decision:** Squads that have ARRIVED do not share a cell: the
higher-id one settles onto the nearest free cell
(`SquadSim._separate_arrivals`). Movement in transit is unchanged, and
there is no per-soldier collision.

**Rationale:** twenty squads could occupy one cell and render as a single
heap, so an army had no physical extent.

**Why not per-soldier collision, which is what was asked for:** D-006
names it specifically — "local avoidance, collision push-back, jostling"
each give a soldier integration state and fire the revisit trigger. That
purity is what lets client and server agree on 40,000 soldier positions
without sending any of them; it is not a small thing to trade for
spacing. The GOAL — armies taking up room rather than heaping — is a
squad-level property, and squads are the atomic unit (D-005), so it is
achievable without touching the keystone.

**The first attempt was wrong and an existing test caught it.** Spreading
DESTINATIONS at order time gave twenty squads twenty different goals, so
they built twenty flow fields instead of sharing one — destroying D-007's
per-destination sharing, which is the entire scaling claim, and undoing
what `_quantise` (D-038) exists to enforce. Separation therefore happens
on ARRIVAL: travel keeps one destination and one field, and the pile-up
is resolved only where it shows.

**Rejected alternatives:**
- *Per-tick separation of overlapping squads* (rejected for now — needs
  per-squad integration state and a curve rebuild every time two units
  brush, which is a real cost against D-020's tick budget and a real
  design decision, not something to slip in under a rendering fix).
- *Per-soldier collision* (rejected — D-006's explicit revisit trigger).

**Consequences:** squads still walk THROUGH each other in transit, and
two already-overlapping squads are not pushed apart. Both are visible and
neither is fixed here.

**Revisit trigger:** if formations need to hold a line against each other
— a shield wall that genuinely blocks — squad-level separation is not
enough and D-006 has to be reopened deliberately.

---

### D-059 · 2026-08-04 · Accepted — soldiers ease and act, on the render path only
**Decision:** The client eases each soldier toward his authoritative slot
rather than snapping (`soldier_motion.gd`), and displaces soldiers toward
what their squad is doing — a resource being worked, an enemy being
fought (`CosmeticOffset.decorate_activity`). Both are client-only,
one-way, and never read back.

**Rationale:** two complaints with one cause. A soldier's position is a
pure function of the squad curve and formation (D-006 clause 1), so when
a squad turns every slot rotates in the same instant and the block snaps
round. And a squad standing perfectly still while a resource drains or an
enemy dies looks broken.

**Why this is allowed:** clause 2 permits client-side visual offsets
never read back by simulation, and `cosmetic_offset.gd`'s own header
already named this case — "the authoritative slot snaps, and the render
layer is free to ease toward it."

**Where the line sits, precisely.** `SoldierMotion` holds per-soldier
state, which clause 1 forbids in the SIMULATION and clause 2 permits on
the render path. Three properties keep it legitimate, and a test guards
each: the authoritative transform is unmodified; it is client-only, so
two clients may disagree and nothing notices; nothing reads back out.

It lives in its own file rather than in `CosmeticOffset` because that
class is deliberately pure and static — it has nowhere to put state, and
that is what makes its boundary structural rather than a comment.

**No new protocol.** Activity is inferred from what the client already
has: `shape == "ring"` means a crew is working (D-058 replicates shape),
and enemy squads in vision mean fighting.

**Rejected alternatives:**
- *Easing in the simulation* (rejected — clause 1, and it would put
  soldier positions out of step between client and server).
- *Replicating an activity flag* (rejected — more wire traffic for a
  picture the client can already derive).

**Consequences:** the client now carries per-soldier render state, which
is new. A seam-sized jump snaps rather than easing, or a wrapped squad
would send soldiers streaming across the world (D-035).

**Revisit trigger:** if easing is ever consulted by selection, combat or
the composition hash, the state has stopped being cosmetic and D-006's
trigger has fired.

---

### D-058 · 2026-08-04 · Accepted — formation is a player's choice, and replicated state
**Decision:** A squad's formation is chosen by the player from three
options offered for every unit — **sparse**, **tight**, **ring** — and is
mutable, replicated squad state rather than a fixed property of its
UnitDef. Gatherers switch themselves: **ring while working a node,
sparse while walking**, decided by the SIMULATION.

`line`, `column` and `wedge` remain implemented for .tres defaults; they
are simply not offered in the UI.

**Rationale:** shape was set once at spawn from `UnitDef.formation_shape`
and never changed, so a gathering crew stood in the same order whether it
was marching or working — it looked like a squad that happened to be near
a resource rather than one working it.

**The part that made this more than a UI change:** shape is an input to
`Formation.slot_offset`, so it decides where every soldier in the squad
stands, and it is part of `composition_hash`. A client that missed a
change would draw the squad in the wrong shape AND report a desync on a
perfectly healthy system. So changing it needs the same treatment
`alive` gets: `SquadSim.take_shape_dirty()` mirrors
`BuildingSim.take_dirty()`, and the server resends ordinary `SQUAD_INFO`
— the message that already carries shape — for changed squads only,
filtered per client by visibility.

`set_shape` ignores a no-op deliberately. That is what lets the economy
assert the right shape every tick without generating wire traffic; without
it a gathering crew would resend its composition ten times a second to
every client that can see it, and D-003's zero-cost-when-idle claim would
be false for the whole economy.

**Why the sim decides the gatherer switch, not the client:** the haul
phase is not replicated, so a client physically cannot infer it. The
alternative — replicating the phase so the client could switch shape
cosmetically — is strictly more wire traffic for the same picture, and
would put a second copy of the rule on the untrusted side.

**Rejected alternatives:**
- *Client-side cosmetic shape override* (rejected — D-006 clause 2 allows
  cosmetic offsets that are never read back, but shape is hashed, so a
  local override would desync).
- *A new wire message for formation* (rejected — `SQUAD_INFO` already
  carries shape; a second message would be a second thing to keep in step
  with the hash).
- *Formation as a UnitDef property only* (rejected — that is what it was).

**Consequences:** any future system that wants a squad to change shape —
a shield wall on contact, skirmishers spreading under fire — now has the
plumbing, and needs no new protocol. Note the cost is per CHANGE, so a
mechanic that toggles shape every tick would be expensive; that is a
reason to make such a rule hysteretic, not a reason to avoid it.

**Revisit trigger:** if formation changes ever become frequent enough
that `SQUAD_INFO` resends show up in the bandwidth figures (D-041's
595 B/client/s), move shape into the curve stream instead of the discrete
one.

---

### D-056 · 2026-08-02 · Provisional — match pacing, and what it is NOT solved by
**Decision:** Target match length is **1–2 hours** (stated by the project
owner, 2026-08-02). Two changes toward it, both data:

1. **`UnitDef.damage_vs_buildings`** (schema addition against D-010),
   default **0.15**. A squad's siege output is its ordinary damage scaled
   by this. Soldiers are not siege engines.
2. **Building health roughly tripled** — town centre 900 → 3000, barracks
   600 → 1600, tower 450 → 1400, storehouse 300 → 700 — and **`squad_cap`
   15 → 40** on both shipped maps.

**Rationale:** matches were deciding at ~200–230 s. Measured cause, one
squad against a 900 HP town centre with no modifier:

| | time to raze |
|---|---|
| legion_militia (36 × 9.5) | **2.1 s** |
| legion_heavy (24 × 15.0) | 2.9 s |
| northmen_militia (44 × 6.5) | 3.1 s |

A base evaporated the instant any army reached it. **That number was
introduced by D-055 the same day**: siege damage was written as
`damage * alive`, mirroring squad-vs-squad, because there was no prior
building balance to mirror — buildings had never been damageable at all.

`squad_cap` was 15 against D-018's target of **~50 squads/player**. About
9 go to gatherers, so an "army" was ~6 squads. The architecture is built
for 3× more army than the maps permitted, and M4 already showed the sim
carrying 120 squads at 20 players inside D-020's tick budget — this was a
data ceiling, never a performance one.

**A separate field rather than an entry in `bonus_vs`.** `bonus_vs` reads
1.0 for a missing key, which is right for a counter table (no entry =
generalist) and exactly wrong here: forgetting it on a new unit would
silently restore the three-second base. `damage_vs_buildings` defaults to
the SAFE end, so an unaware .tres is conservative rather than
catastrophic. It is also the hook a future siege archetype hangs on, with
no code change.

**Rejected alternatives:**
- *Tune building HP alone.* Would need absurd numbers (a 6-squad army at
  full damage is ~1,800 HP/second) and would make towers unkillable in
  the same stroke.
- *A constant in `combat.gd`.* Violates D-010, and forecloses siege units.

**Consequences and the honest limit:** this does **not** reach 1–2 hours,
and is not expected to. It stops bases evaporating and lets armies be
armies. **The structural reason an hour is unreachable is that there is
no progression at all** — four buildings and four units per civ, no ages,
no tech, no upgrades — so after roughly three minutes there is nothing to
do but fight. *Empires: DotMW* and *AoE* both stretch matches with epochs
to climb, and that machinery does not exist here.

**That is deliberately deferred to its own planning milestone** (project
owner's call, 2026-08-02): get the basics working first, plan age/tech
progression in a separate session. See Q15 in the open questions.

**Amended 2026-08-04 — the slower opening is WANTED, not a regression.**

Shrinking gatherer crews 16 → 5 tripled the time to staff an economy,
because `AiPlayer.TRAIN_COOLDOWN` gates production ORDERS rather than
labour: the same ~110 workers take 22 productions instead of 7. First
contact moved from 121–160 s to ~326 s.

I raised that as a bug to fix. **The owner's call is that the old ramp was
far too quick and the longer one should stay.** It pulls the same
direction as this decision's 1–2 hour target: an opening you can be
attacked out of in two minutes is a race, not a strategy game.

Recorded because the cooldown looks like a scaling defect to anyone
reading it cold — the comment on the constant now says so too. The thing
to re-derive when pacing changes is `ai-ladder`'s SECONDS default, which
has already been stale once for precisely this reason: it ran 300 s while
first contact landed at 326 s, reported `attacks=0`, and was read as a
broken AI for a whole session.

**Measured after the change** (`ai-ladder 2 900`), and two corrections
worth keeping because both were confident and wrong:

- Match length **~215 s → ~325 s decided**. Longer, still not the target.
- **The economy was never the constraint.** I predicted the raised cap
  would hit an economy wall on the reasoning that 7 gatherers could not
  fund 33 squads. There is no upkeep, so a worker count caps the RATE of
  buying and never the SIZE of an army. Legion banked a peak stockpile of
  **2,480 while pinned at the squad cap**; northmen sat on 985 and
  fielded eight squads. `AI_STATS` now reports `peak_stockpile`,
  `afford_refusals` and `cap_refusals` so this is a number rather than an
  argument.
- **The cap of 15 WAS binding — for the AI.** I said it was not, which
  was true of `test-load`'s bots (6 squads of 15) and false for the AI,
  pinned at exactly 15–16 and reaching 41 once the cap moved. Generalised
  from the bots without checking.

**Still open, and an AI defect rather than a mechanic one:** legion held
41 squads against northmen's 8, knew all three of its buildings, attacked
93 times over 900 s and never finished the match.

**Revisit trigger:** the age/tech milestone landing, which will re-derive
these numbers from a phase-by-phase account of what a 1–2 hour match is
made of, rather than from stopping the worst behaviour.

**Trigger FIRED, 2026-08-04 — see D-068 through D-074.** The
phase-by-phase account this entry asked for is D-068. What it means for
the numbers here:

- **`damage_vs_buildings` (0.15) stands**, and gains a second job: it is
  the knob Byzantine siege and Magyar non-siege are both expressed
  through (D-073).
- **The tripled building health is superseded by D-066/D-067**, which
  landed on main the same day from the other direction: tower **1400 →
  1700 HP**, town centre damage **12 → 60**, tower damage **20 → 85**,
  against an explicit rule that **one squad must fail and two must
  succeed**. Whatever the values, they are now *epoch-1* figures rather
  than global ones — buildings gain `BuildingDef.epoch` (D-070) and later
  rungs get their own.
- **`squad_cap` 40 is superseded in ROLE, not in value.** D-068 makes
  upkeep the binding constraint and returns `squad_cap` to being the
  engineering ceiling protecting D-018 and D-020. It should end up set
  high enough that a player never feels it.
- **The "still open" AI defect stands** — Legion holding 41 squads
  against 8, attacking 93 times over 900 s and never finishing. Upkeep
  makes an unfinished match expensive rather than free, which pressures
  the symptom but is not a fix for it.

This entry stays **Provisional**: its numbers were tuned to stop the worst
behaviour, and D-072 is the beginning of replacing them with derived ones,
not the end.

---

### D-055 · 2026-08-02 · Accepted — squads besiege buildings, and the game became winnable
**Decision:** Squads damage enemy buildings, via
`Combat.resolve_squads_vs_buildings` — the mirror of the
`resolve_buildings` pass that already existed. Defenders come first: a
squad with an enemy SQUAD in range never spends its attack on a
structure. A building under construction is a legitimate target. Damage
is continuous rather than a casualty roll, and skips `bonus_vs`.

**Rationale:** `BuildingSim.damage()` was fully written — it even marked
the building dirty so destruction would replicate through the path the
server already used — and was called by nothing outside its own tests
for two milestones. Buildings were indestructible.

The consequence was larger than the omission sounds. D-033 ends a match
by elimination; a town centre that survives everything keeps producing
replacements; so **no match could be won by anybody**, human or AI. Every
`ai-ladder` run drew at the time cap, and that was read as an AI weakness
through several rounds of AI work on massing, target choice and scouting.
None of it could have mattered.

**How it was found, because the method is the transferable part:** making
enemy buildings the AI's attack objective produced a ladder result
*identical to the previous one in every statistic to three significant
figures*. That is not a small effect, it is no effect — so the new branch
could not be executing. Instrumenting the AI with `enemy_buildings_seen`
settled it in one run: legion finds all three of its opponent's
buildings, attacks 18–21 times, and destroys none.

**This is the third declared-and-unread mechanic this project has
shipped,** after `UnitDef.cost` and `BuildingDef.cost`. The shape is
always a field or method with no caller, and it survives because nothing
fails: the game runs and quietly lacks a rule. A test suite cannot see it
— the code under test is correct. **A grep for uncalled public members is
worth more here than another assertion.**

**Rejected alternatives:**
- *Reuse `_resolve_attack`.* It is steeped in squad assumptions —
  fractional casualty carry, morale, rout, `armour_class`. A building has
  none of those. Duck-typing `BuildingSim` through squad-shaped functions
  is the subtle-bug factory `resolve_buildings` already declined.
- *Carry a fractional accumulator.* D-024's accumulator exists because
  casualties must be whole soldiers. `max_health` is a float, so the
  problem does not arise.
- *Apply `bonus_vs`.* `BuildingDef` has no `armour_class`, so D-032's
  counter triangle has nothing to key on and the lookup would silently
  read 1.0 while looking meaningful.

**Consequences:** the ladder went from **0 of 3 decided** to **2 of 3**
with no AI change whatsoever — same code, same seeds. A defended base is
now a real objective, and a garrison now matters, because an attacker
cannot ignore it.

Cost, measured by `test-load 20 120`, all at 120 squads:

| | µs/squad | combat |
|---|---|---|
| pass off | 77.02 | 5.99 |
| pass on, `distance()` per pair | 92.10 | 24.24 |
| pass on, bucketed | 76.50 | 7.33 |

The first version scanned every building for every squad — ~7,700
`distance()` calls a tick — on the reasoning that buildings are rare
enough for a scan to beat a bucket rebuild. Measurement said otherwise.
**That is the fourth appearance of one defect**, after `distance()` per
candidate cell in vision (232 → 15 µs/squad, M2), `UnitRoster.by_id`
walking the filesystem per produced squad (858 ms in one tick, M4), and
terrain noise sampled per soldier per frame (M5). A hex disk is
translation-invariant on a torus: reach for `TorusSpace.disk_offsets`
before reaching for `distance()`.

Two things left open and deliberately not dressed up:

- **The 40.8 → 77 µs/squad rise against M4's figure at the same squad
  count is not this change** — it was measured with the siege pass
  disabled, so it belongs to M6's civs/teams/economy work and is still
  unattributed.
- **Worst-tick figures from this session are untrustworthy.** A run with
  strictly *less* work reported 146 ms while the fuller run reported
  52 ms, because the host was building containers throughout. Both runs
  dropped zero ticks.

**Revisit trigger:** anything wanting a different attack rate against
buildings than against squads. Defenders-first is currently enforced
twice — by `_engaged` and, implicitly, by both passes sharing one
`_last_attack_tick` clock — and the test only goes red when *both* are
removed. Splitting that clock silently removes one of the two.

---

### D-038 · 2026-08-01 · Accepted — M4's first measurements
**Decision:** Record what the scale sweep actually measured, and what it
settles. Three things were being taken on faith and are now numbers:
whether simulation cost is linear in squad count, where the flow-field
solver breaks (Q8), and whether any kernel needs GDExtension (D-021).

Measured by `just profile` — the simulation driven directly at chosen
counts rather than played, because squad count in a real match is
whatever production produces and D-018 targets ~1,000.

**1. Cost is linear in squad count.** 128x64 map, 200 ticks:

| squads | µs/squad | vision | combat | ms/tick |
|---|---|---|---|---|
| 100 | 74.8 | 13.3 | 59.8 | 7.5 |
| 250 | 79.7 | 11.3 | 66.9 | 19.9 |
| 500 | 80.5 | 10.4 | 68.5 | 40.3 |
| 1000 | 74.1 | 9.6 | 62.9 | 74.1 |

Tenfold more squads, no per-squad growth. **At D-018's full scale that
is 74 ms inside a 100 ms tick** — it fits, with ~26% headroom, and
D-020's revisit trigger is not tripped. Vision cost per squad *falls* as
count rises (13.3 → 9.6) because the per-player coverage field is stamped
once and shared however many squads read it, which is D-025 part 1's
argument paying off. Combat is ~85% of the tick.

**2. Q8 — ship map size. The flow-field solver is linear in cells, and
that is not the problem.** 250 squads, varying map:

| cells | µs per field build | µs/squad |
|---|---|---|
| 2,048 | 4,146 | 31.7 |
| 8,192 | 16,818 | 81.6 |
| 18,432 | 37,169 | 103.7 |
| 32,768 | 67,434 | 156.4 |

Almost exactly 2 µs per cell at every size — no cliff, no bend. D-021
guessed at a threshold "over 10,000+ cells"; there isn't one, because
nothing about the algorithm degrades.

**The real constraint is spike size against the tick.** ONE field build
at 32,768 cells costs 67 ms — two thirds of an entire 100 ms tick, for a
single squad choosing a new destination. At the current 8,192 it is
16.8 ms, or 17% of a tick, and D-003 already warns that a large
engagement re-paths many squads at once. That is an invalidation storm
with a hard number attached.

**Q8's answer: keep the ship map at or below ~8,192 cells** unless field
building is amortised. This is a budget bounded by latency spikes, not by
average throughput — average tick cost at 32,768 cells is a comfortable
39 ms, which is exactly why measuring only the average would have missed
it.

**3. D-021 — no kernel needs GDExtension yet, and the cheap fix comes
first.** The flow-field solver is the named candidate and it *is* the
thing exceeding budget, but not because GDScript is too slow per cell:
2 µs/cell over 32,768 cells would be a big number in any language. The
problem is doing it all inside one tick.

The GDScript-level fixes are untried and obvious: amortise a build across
several ticks (a squad already tolerates a tick of latency before its
curve is extended), or widen destination sharing so fewer distinct fields
are built at all — the sweep shows 1,112 builds for 250 squads, which is
far more re-pathing than D-007's per-destination sharing should require.
Per M4's fix policy, those come before the native escape hatch.

**Rationale:** All three were assumptions load-bearing enough to appear
in other decisions. D-018's target assumed linearity, Q8 assumed a
threshold existed, and D-021 assumed the flow field would be the kernel
that broke. Two of three survived contact; the third was right about
*which* kernel and wrong about *why*.

**Rejected alternatives:** Measuring only at 1,000 squads (rejected — a
single point gives pass/fail without saying whether anything is
accidentally quadratic, which is the defect class already found twice
here). Measuring average tick cost alone (rejected — it hides exactly the
spike that bounds map size).

**Consequences:** Q8 is answered pending the amortisation work. D-021
stays unexercised, deliberately. D-012's LOD tiers gain their first
evidence: combat dominates at every scale, so combat resolution is where
LOD has something to save.

**Revisit trigger:** If amortising field builds does not bring the spike
under a tick at the chosen map size, revisit GDExtension for that kernel
specifically — and only that kernel.

**Corrected 2026-08-01, same day.** The map sweep above used a workload
that defeated the thing it was measuring, and the correction makes the
finding worse rather than better. Recorded in full because the mistake is
instructive.

**The flawed workload.** Every squad was ordered to its own random
destination. D-007's entire scaling claim is that ONE field serves every
squad heading to the same place — so giving 250 squads 250 destinations
measured a case the design explicitly does not optimise for, and the
"1,112 builds for 250 squads" figure was an artifact of the harness, not
a finding about the game. Players order groups.

**Re-measured with group ordering** (250 squads, 8 shared rally points):

| cells | µs per field | fields built | ms avg tick | **ms WORST tick** |
|---|---|---|---|---|
| 2,048 | 4,323 | 215 | 8.6 | **127.5** |
| 8,192 | 18,492 | 186 | 20.1 | **437.0** |
| 18,432 | 37,653 | 142 | 26.6 | **393.1** |
| 32,768 | 70,595 | 125 | 155.5 | **905.5** |

Sharing works — builds fall by more than half. **And the worst tick is
catastrophic anyway**: 437 ms at the current map size, against a 100 ms
budget. An order wave creates several NEW destinations at once, so
several full BFS solves land in the same tick. This is D-003's
invalidation storm, and it is 4.4x over budget on the map being shipped.

The average hid it completely — 20 ms — which is the second time in this
milestone that measuring the average alone would have produced a
comfortable and wrong conclusion.

**A budget on builds-per-tick was tried and made things worse.** Capped
at 2, deferred squads retried on every following tick: 31,413 deferrals
and a worst tick that went UP. A throttle that costs more than the work
it throttles. It survives as `SquadSim.fields_per_tick`, defaulting to 0
(unlimited), because it is the right shape for a genuine storm and the
wrong default.

**So D-021's trigger is now armed with evidence, and the flow-field
solver is the kernel.** But the fix to try first is still algorithmic
rather than native: a single build is ~2 µs/cell in GDScript, and no
language makes 32,768 cells free — the problem is doing a whole solve
inside one tick. Incremental solving (spread one BFS over several ticks,
serve squads the partial field) attacks the actual shape of the problem.
GDExtension would buy a constant factor against a cost that is
structurally too large in one slice.

**Consequently Q8's answer stands but for a sharper reason:** map size is
bounded by how much BFS lands in one tick, and at every size measured
that already exceeds the budget under a realistic order wave. Map size
is not the dial that fixes this — amortisation is.

**Routing was the hidden source of field builds, and fixing it is the
first real win.** Quantising player orders bought only 18% and cost exact
arrival, so it was backed out — but the build count barely moving was the
clue. The sweep issues 8 destinations per wave over 5 waves: at most 40
distinct fields, and 186 were built.

`Combat._check_rout` sent every broken squad fleeing to its own computed
cell, so **a rout produced one full BFS solve per squad** — during
precisely the large engagements that are already re-pathing everyone.
D-007's sharing cannot help a destination nobody else shares.

The fix is that a rout has no exact destination worth preserving. A squad
is running away; where it stops is a detail nobody chose. Snapping flee
destinations coarsely (`rout_quantum`, 8 cells) makes a whole routing
army share a handful of fields:

| cells | fields before | after | µs/squad before | after | worst tick |
|---|---|---|---|---|---|
| 2,048 | 215 | **57** | 33.5 | **22.1** | 130 → **88 ms** |
| 8,192 | 186 | **123** | 80.5 | **53.5** | 457 → **323 ms** |
| 32,768 | 125 | **110** | 151.9 | **135.7** | 903 → **844 ms** |

A third off per-squad cost at the shipped map size, and a third off the
worst tick, from one line about where cowards run to.

**It is not enough on its own.** 323 ms is still 3.2x over a 100 ms
budget, and the remaining spike is what it always was: several whole BFS
solves landing in one tick. Amortisation remains the next move; this
simply removed a large multiplier in front of it.

The general lesson is worth keeping: the expensive pattern was not the
one anybody designed. Player orders were carefully shared; the cost came
from an emergency behaviour written for correctness with no thought about
how many destinations it minted.

**Amended 2026-08-01 — the 20-player live measurements.** The sweep above
drives the simulation directly. This is the same scale played through the
real server, the real protocol and the real client code: 20 bots, 120
seconds, `just test-load 20 120`, verdict green.

| measurement | result | against |
|---|---|---|
| bandwidth | **595 B/client/s** | budget_overruns=0 |
| server memory | **42.5 MB** at 120 squads | — |
| client memory | **28.4 MB** for 20 virtual clients (~1.4 MB each) | D-018's N-in-one-process budget |
| per-squad cost | **40.8 µs** at 120 squads | D-020's ~50 µs |

Bandwidth is the headline and it is not close: 0.6 KB/s per client, from
curve-based sync doing what D-003 said it would. Nothing about this
number is at risk at 20 players.

**The per-squad figure needs its caveat read.** 40.8 µs at 120 squads is
under budget, and CLAUDE.md's standing warning applies in the flattering
direction here — per-tick fixed overhead is divided across more squads
than M2's 48, so this is not directly comparable to the 53.5 µs above.
The sweep, not the match, remains the authority on scaling; a live match
cannot reach 1,000 squads.

**None of it was measurable until a two-line ownership bug was found**,
and the way it hid is the part worth keeping. The first 20-player run
reported "zero movement" — a symptom that invited theories about spawn
stacking and vision. The actual cause was in the server log: 2,700
refusals of the form "player N tried to order squad M it does not own",
because per-connection ownership was cached at join and every *produced*
squad was rejected. The measurement was not wrong, it was measuring a
match in which nothing happened.

Then fixing it exposed two more bugs stacked behind it, one of which had
been *cancelling* another: the client never dropped dead squads from its
owned list, which kept a bot's "do I have squads?" guard true, which was
the only reason its production code was still being reached after its
founding party was consumed. Making the client honest broke the bots. Two
defects whose symptoms had been hiding each other for the whole of M3.

The lesson generalises past this instance: **an anomalous measurement is
a bug report about the harness first and the system second.** Three
sessions of theorising about spawn placement would not have found this;
reading the server's own error log did, immediately.

---

### D-052 · 2026-08-02 · Accepted — one colour per player
**Decision:** Every player gets a colour from a twenty-entry palette,
keyed by SEAT INDEX, and their units and buildings wear it. `PlayerColours`
owns the palette; `ClientState.colour_of` maps a player to it.

**Rationale:** colour used to come from `UnitDef.mesh_color`, which
describes the unit TYPE — every spearman on the map was the same grey
whoever owned him. That is fine in a screenshot and useless in a battle.
The first thing a player needs to read off the screen is whose units
those are; which kind they are is second, and shape still carries it. The
unit colour survives as a 25% tint over the owner colour, so two unit
types stay distinguishable within one army without muddying whose army it
is.

**Twenty entries, and no wrap.** D-018 targets 20 concurrent players, so
the palette is exactly that long and out-of-range CLAMPS rather than
wrapping — wrapping would hand a twenty-first player an existing
player's colour in precisely the largest, most confusing match. A test
asserts the count, that every entry is distinct, and that no two are
within a small distance of each other, because "distinct" and
"distinguishable" are not the same claim.

**Keyed by seat, not player id.** Ids are not contiguous: AI seats are
numbered from 1000 (D-051), so any modulo of a player id would give
AI 1000 the same entry as player 1. There is a test for exactly that
collision.

**Derived, not sent.** The client already holds the seat list, so colour
needs no message of its own and every client agrees by construction.

**Consequences, and both were caught by looking at a picture rather than
by a check:** sending the seat list to every client made
`ClientState.in_lobby()` true forever, because it inferred "in a lobby"
from HAVING seats — the client drew the lobby over a live match while the
verdict reported terrain built, 96 soldiers and zero desyncs. The lobby
packet now carries the match phase. Separately, the same commit that
surfaced this had already been shipping a frame with no terrain at all
for three commits (D-046's audit).

---

### D-051 · 2026-08-02 · Accepted — AI players are clients without a socket
**Decision:** An AI player holds a real `ClientState` and is fed by the
server's ordinary `_replicate()` loop through a `LoopbackPeer` — an
object whose only job is to expose `send(channel, packet, flags)` and
hand the bytes to that ClientState. Its decisions become real
`NetProtocol` packets, handed to the server's own dispatcher.

**Rationale: fog has to be a property, not a promise.** D-046 criterion 9
requires an AI to see only what a human in its seat would. The obvious
implementation — let the AI read `SquadSim` and be careful — makes that a
convention one refactor can quietly break, and the failure mode is
invisible: **an AI that sees through fog does not look like a bug, it
looks like a good AI.** Nobody finds that by playing.

Feeding it the same packets makes the guarantee structural. There is no
code path by which an AI can learn about a squad the server did not send
it, because the only thing it has is a ClientState and the only thing
that writes to it is `handle_packet`. This is the same reasoning that
made `bot_client.gd` drive the real ClientState rather than an imitation
(D-018), applied where the stakes are higher.

**Orders take the same road.** An AI's decisions go through
`_dispatch()`, the same function a socket's packets go through, so
ownership read from the sim, the squad cap, affordability and "is the
match running" all apply unchanged. An AI calling into the simulation
directly could do things no human could, and nobody would notice until
they wondered why it never ran out of food.

**Consequences:** the replication loop needed a two-line change — merge
`_ai_clients` into the recipients — rather than a branch, which is the
whole point of the loopback shape. Several `peer` parameters became
untyped, and GDScript's type checker found every one of them
immediately, which is the right kind of failure. `LoopbackPeer` is
deliberately NOT a subclass of `ENetPacketPeer` and deliberately kept out
of `_clients`: real sockets are legitimately treated as sockets there
(ENet statistics, the lobby broadcast), and an impostor in that
dictionary would be a null cast waiting to happen.

`bot_client.gd`'s role is now distinct: it stays the LOAD-TEST harness,
driving N virtual clients over a real socket. The in-game AI is a
different job, and conflating them would give the load test a stake in AI
quality.

**What this AI is not:** good. It founds a town, gathers, trains, and
attacks the nearest enemy it can see. D-046 makes AI a shipped feature,
so this is the floor to build on rather than a scripted demo — and
because it plays through the client interface, improving it cannot
accidentally grant it privileges.

**Rejected alternatives:** Privileged access to SquadSim with a
"don't cheat" convention (rejected — see above). Running AI as separate
processes connecting over ENet (rejected — a real socket per AI seat
costs a connection and a scheduler slot to buy nothing; the loopback is
the same guarantee without the transport). Putting AI in `_clients`
(rejected — null casts, above).

**Revisit trigger:** If an AI seat's ClientState becomes a measurable
share of server memory or tick time at D-018's scale, the answer is a
narrower view object with the same gating, not privileged access.

---

### D-047 · 2026-08-02 · Accepted — civilizations as data: archetypes, subsets, and per-civ tuning
**Decision:** A **unit archetype** is the shared idea of a troop type —
spearmen, archers, cavalry. A **UnitDef is one civ's version of an
archetype**. Each civ fields a *subset* of the archetypes, and tunes the
ones it has differently, so the same type is not the same troops in two
armies.

The worked example that set this: one civ's spearmen may be cheap and
weak, fielded in numbers quickly, and lose to a smaller body of another
civ's stronger spearmen. Same archetype, different answer to it.

**Schema (logged against D-010):** `UnitDef` gains `archetype`. It
already has `civ`, and it already has per-unit `cost_*`, stats and
`bonus_vs`, so "cheap and weak" versus "expensive and strong" is
expressible today with no new machinery.

**A civ's roster is DERIVED, not listed.** A unit declares its `civ`;
which archetypes a civ fields is simply which unit files name it. Adding
a `.tres` gives that civ a type — no register to update, and no second
place for the roster to disagree with itself. `CivDef` therefore carries
only what is genuinely civ-level: display name, starting stockpile,
buildings, and declarative modifiers.

**Why `archetype` is not just `armour_class`.** `bonus_vs` already keys
on `armour_class` (infantry/cavalry/missile), which is why the counter
triangle survives new civs untouched — a civ added tomorrow is countered
correctly by every civ written before it, with no edits anywhere. That
was a genuinely lucky call in D-032. But `armour_class` has three values
and exists to answer "what beats this". `archetype` answers "what IS
this", and there are more archetypes than armour classes.

**What archetype buys, and it is the point of the whole design:** every
script can stay civ-agnostic. The client's train keybinds bind to
*archetype*, so one key trains your civ's spearmen whatever that civ
names them; production, UI grouping and AI all reason about archetypes.
Nothing needs to know a civ id — which is exactly what D-046 criterion 3
tests for.

**Mechanical asymmetry stays declarative**, per D-046's governing
constraint: a civ that wants a new mechanic adds a knob every civ has and
turns it. `CivDef`'s modifiers are that surface.

**Rejected alternatives:** One shared UnitDef per archetype plus per-civ
stat multipliers in `CivDef` (rejected — less duplication, but it hides
a unit's real numbers behind arithmetic in another file, and this project
optimises for stats being directly readable and editable as text; balance
work wants to see the number, not derive it). Per-civ unit ids referenced
directly in `bonus_vs` (rejected — every new civ would then require
editing every existing civ's counter lists, which is precisely the
"adding a civ is an engineering project" failure D-046 exists to
prevent).

**Consequences:** The existing four units become one civ's roster and
gain an `archetype`. The client's keybind table stops naming units and
starts naming archetypes. `UnitRoster` gains civ- and archetype-aware
lookups; `UnitRoster.first()` — currently "the default unit" — has to
become civ-relative or its callers do.

**Revisit trigger:** If two civs want the same archetype to differ
structurally rather than numerically — different formation behaviour, a
different number of attacks — that is the moment to check whether it is
still a parameter or has become a branch, and to amend D-046 honestly if
it has.

**Amended 2026-08-04 — this decision extends to epochs unchanged, and it
held under pressure.**

D-070 grows rosters by replacement, so an epoch unlocks new *archetypes*
rather than new versions of existing ones. That needs **no change here**:
`for_civ_archetype()` still returns one def per (civ, archetype) pair,
and epoch gating is one filter on top. A civ's roster stays DERIVED — a
`.tres` declares its `civ` and now its `epoch`, and nothing registers
anything.

Two consequences worth naming:

- **The archetype vocabulary grows from 8 to roughly 25–30.** This clause
  — "the client's train keybinds bind to *archetype*, so one key trains
  your civ's spearmen whatever that civ names them" — stops fitting on a
  keyboard. The binding stays archetype-based; the UI has to become
  epoch-scoped. Tracked as *unlock overload* in D-074.
- **The revisit trigger above did not fire, and was tested.** D-073's
  parameterisation pass put six civs' identities through it and found
  three claims with no knob. Two were cut and re-expressed numerically;
  one — "Byzantine builders raise fortifications faster" — named a
  genuine gap and became `CivDef.build_speed`, a knob every civ has.
  That is this decision working as designed rather than being defended.

The trigger stands unchanged for the future.

---

### D-046 · 2026-08-02 · Accepted — M6's exit criteria
**Decision:** M6 is **"a civilization is data"** — proved by a second
civ, a lobby that lets people choose one, and AI players an admin can
seat. Written before the code, per D-043's standing rule.

**The governing constraint, because two of the answers pull against each
other.** M6 wants asymmetry that is *real* — unique units, different
stats, and different mechanics — and it wants adding a civ to need no
new code. Mechanical asymmetry is exactly the thing that normally becomes
`if civ == "romans"`, and the third civ then needs a programmer.

So the rule for this milestone: **mechanical asymmetry is expressed as
declarative parameters the engine already interprets, never as a per-civ
branch.** A civ that wants a genuinely new *mechanic* is a schema
addition (logged against D-010) implemented generically for every civ —
one more knob everybody has, which one civ happens to turn. That is what
keeps "a mix of all three" and "data, not code" from being contradictory,
and criterion 3 below is what makes it falsifiable rather than an
intention.

**The criteria:**

*Civilizations as data (D-047)*

1. A `CivDef` resource in `/civs/*.tres` defines a civ: display name,
   which units and buildings it may field, starting stockpile, and its
   declarative modifiers. Server, client and tests discover civs through
   one loader, the way `UnitRoster` does for units.
2. A **second civ exists and is genuinely different**: at least one
   exclusive unit the other cannot build, different stat tuning on the
   shared core, and at least one mechanical difference expressed purely
   as `CivDef` data.
3. **The falsifiable one.** A test asserts that **no `.gd` file mentions
   any civ id**. Adding a third civ must require only `.tres` files. This
   is the criterion the whole milestone turns on, and it is trivially
   observed to fail by hardcoding one civ id anywhere.
4. Production, construction and the roster all filter by the acting
   player's civ, server-side. A player cannot build another civ's units,
   and a test proves the server refuses it rather than the UI merely
   hiding it (D-002 — the client is not trusted).

*Lobby, admin and AI players (D-048)*

5. A lobby phase with **seats**: each seat has an occupant (human, AI, or
   empty) and a civ choice. The match starts when the admin starts it,
   not when a connection count is reached.
6. **One admin**, the first human to connect. If they leave, it passes to
   the next human deterministically. Only the admin may add or remove AI
   players, set an AI's civ, or start the match.
7. **Each human picks their own civ**, and the server enforces that: a
   client changing another seat's civ is refused, and a test proves it.
8. **"Random" is always an option**, resolved at match start, **uniform
   across civs** — no weighting toward any civ for now. Resolution is
   seeded so a replay reproduces the same draw (D-016). A test asserts
   the distribution is flat over many draws, and that the same seed
   yields the same civ.
9. **AI players are server-side and see only what a human in their seat
   would see.** They read the world through the same `visible_to(player)`
   gate that gates replication (D-025), so an AI cannot read through fog.
   A test proves an AI's knowledge is a subset of its vision — the same
   shape as D-026 criterion 6's fog check, and for the same reason: an AI
   that cheats is not a test of the game.

*It has to work*

10. `just test-load` runs a match with **both civs present**, and the
    verdict fails if either civ never fielded a unit — a run where
    everyone happened to be one civ proves nothing about the second.
11. Replays reconstruct a match including civ assignment (D-016).
12. `just test-unit` green; `just test-client` green and the PNG
    inspected; `just test-load 20 120` still clean with zero ticks over
    D-020's budget.
13. Every new check **observed to fail** before it is trusted (D-022).

*The question M3 left open*

14. **A human session against AI players of the other civ**, judged on
    whether the asymmetry reads as interesting rather than merely
    different. This closes D-027's last criterion, which has been
    outstanding since M3 and which no automated check can answer.

**Rejected alternatives:** Stat-tuning-only asymmetry (rejected — it
would prove the data pipeline while telling us nothing about whether the
architecture supports asymmetry anyone would notice). Per-civ code
branches (rejected — it makes civ 3 a programming task and quietly
converts D-015's "4-6 civilizations at launch" into six engineering
projects). Assigning civs by slot with no lobby (rejected — the lobby is
also where AI players get seated, and AI opponents are a shipped feature
of this game rather than test scaffolding).

**Consequences:** `bot_client.gd`'s role splits. It stays the load-test
harness; the *in-game* AI is a separate, server-side thing that occupies
a seat. Those are different jobs and conflating them would give the load
test a stake in AI quality.

**Revisit trigger:** If criterion 3 cannot be met without contorting the
data model — if some mechanic genuinely resists being a parameter — that
is worth knowing early. Record the mechanic, take the code branch
deliberately, and amend this entry rather than pretending the rule held.

---

**Audited 2026-08-02 — 13 of 14 met; the last one needs a human.**

| # | Verdict | Evidence |
|---|---|---|
| 1 | Met | `CivDef` in `/civs/*.tres`, `CivRoster` loads them |
| 2 | Met | Northmen field skirmishers and no heavy foot; Legion field heavy foot and no cavalry; shared archetypes tuned apart |
| 3 | **Met** | no `.gd` outside `tests/` names a civ; observed failing by putting one id in a comment |
| 4 | Met, and structurally | the wire carries an ARCHETYPE, so a client cannot name another civ's unit at all |
| 5 | Met | seats with kind, civ, team |
| 6 | Met | first human is admin, passes to the lowest remaining |
| 7 | Met | server-side; a player changing another seat's civ is refused |
| 8 | Met | uniform over 4,000 draws, seeded, resolved at start |
| 9 | **Met, and structurally** | AI is a client without a socket (D-051) |
| 10 | Met | `CIVS_FIELDED 2 of 2 — legion=50, northmen=70` at 20 players; observed failing when forced to one civ |
| 11 | Met | `replay-info` reports `Player 1 = legion, Player 2 = northmen…` |
| 12 | Met | 339 tests; `test-load 20 120` clean, 0 of 1,323 ticks over budget; `test-client` clean **and the PNG opened** |
| 13 | Met | every new check perturbed and watched to fail |
| 14 | **Outstanding** | needs a human at the wheel |

**Criterion 12 is the one worth reading twice, because it nearly passed
while broken.** The capture reported `ok` — 96 soldiers, 97 distinct
colours, zero desyncs — over a frame containing **no terrain at all**.
D-049 made the client wait for map settings before generating the world,
and those were only sent when an admin started a lobby; a server without
a lobby never sent them. Every number was identical to a healthy run,
because the HUD and the soldiers were genuinely fine. Only the world was
missing.

Two things came out of it. The settings are now sent from
`_admit_player`, which both ways of starting a match go through. And the
capture's verdict asserts the terrain was actually built — a check whose
failing state was not simulated but *observed*, since the previous run
produced exactly it.

The lesson is one this project keeps paying for and had written down
already: **"a green run is not the same as a run that happened", and a
green verdict is not the same as a correct picture.** The recipe's own
docstring says the PNG "is meant to be looked at, not just asserted
about" — and it was not looked at for three commits, which is precisely
how long the regression survived.

**Two things deliberately not done**, recorded so they are choices rather
than oversights: seats cannot be opened or closed (a slot is a human who
joined or an AI the host added), and the AI is not good — it founds,
gathers, trains and attacks the nearest enemy it can see, with no
scouting, no expansion and no use of the counter triangle it is subject
to.

---

### D-045 · 2026-08-02 · Accepted — client render architecture, and the LOD the numbers actually asked for
**Decision:** The client culls before deriving, samples terrain from a
precomputed field, and thins distant squads with a camera-keyed,
cosmetic-only render LOD. **Batching squads by unit type is rejected on
measurement**, and D-012's simulation half is closed as not needed.

**The baseline, taken before touching anything** (`just bench-render`,
Intel Iris Xe integrated, 128x64, terrain on, client's own camera
framing):

| squads | soldiers | ms | fps | draw calls | of which CPU |
|---|---|---|---|---|---|
| 0 | 0 | 2.35 | 425 | 32 | 0.02 |
| 100 | 2,644 | 10.00 | 100 | 40 | 9.31 |
| 250 | 6,644 | 23.43 | 42.7 | 62 | 22.76 |
| 500 | 13,336 | 46.58 | 21.5 | 89 | 45.04 |
| 1,000 | 26,644 | 94.50 | **10.6** | **154** | **91.78** |

**This overturned D-044 criterion 4 before a line of it was written**,
which is what taking the baseline first is for. The criterion assumed
~1,000 draw calls at 1,000 squads, one per squad's
`MultiMeshInstance3D`. The real number is **154**: Godot already
frustum-culls those instances at the RenderingServer level. Batching by
unit type would have been a careful solution to a problem that does not
exist. **97% of the frame was our own CPU, all of it derivation** — so
the work went where the measurement pointed.

**What was actually done, each measured:**

| change | ms at 1,000 squads | fps |
|---|---|---|
| baseline | 94.50 | 10.6 |
| + elevation sampled from a precomputed field | 66.70 | 15.0 |
| + cull before derive (wrap-aware) | 56.06 | 17.8 |
| + render LOD | 35.92 | 27.8 |
| + viewport lookup hoisted out of the cull | 35.66 | **28.0** |

2.6x overall. **500 squads / 13,336 soldiers now runs at ~57 fps on
integrated graphics**, where it was 21.5.

**1. Terrain sampled from a field, not from noise per soldier.**
`TerrainGen.elevation_at` evaluates 3D simplex noise on every call, and
the client's terrain sampler — D-006's fourth input — calls it **once per
soldier per frame**, ~26,600 times a frame at full scale.
`elevation_field()` computes it once per cell. Memoisation, not
approximation: same generator, same cells, identical values. This is the
third time the same shape of defect has cost this project real
performance, after `TorusSpace.distance()` per cell in vision (232
µs/squad) and `UnitRoster.by_id` per produced squad (858 ms in one tick).

**2. Cull before deriving, wrap-aware.** The engine was discarding
squads *after* the client had paid to derive every soldier in them. The
cull has to know about the seam: the world tiles nine times (D-035), so a
squad just past the seam is on screen at a wrapped position while its
canonical coordinates are a map away. `RenderCull.nearest_offset` picks
the lattice copy nearest the camera, and `TorusSpace.lattice_steps` now
holds the one definition of that geometry, shared with terrain tiling and
the camera wrap (D-044 criterion 6).

This **also fixed a visual bug nobody had reported**: squads were never
drawn on the tiled copies at all, so terrain wrapped across the seam and
armies did not. Placing a squad at its visible copy is the same operation
as culling on it.

**3. Render LOD, cosmetic only.** Beyond 55 world units a squad is drawn
with at most 12 soldiers, beyond 110 with 5. `alive` is untouched and
`slot_offset` is still asked for the squad's real size, so a distant
formation is drawn **thinner, never smaller** — unit size is tactical
information a player is entitled to read correctly off the screen. The
slots are sampled as `i * alive / n` rather than the first n, so the
formation keeps its frontage instead of bunching at one end.

Camera-keyed, which **D-012 explicitly permits for render and forbids for
simulation**. `Formation.soldier_transforms_sampled` is a separate entry
point from `soldier_transforms`, so every existing caller keeps full
detail by construction, and a test proves the reduced path never changes
`alive` or `composition_hash()` — D-006 clause 2's one-way boundary.

**A live rendering bug found on the way.** `PrimitiveUnit` allocated one
MultiMesh instance per soldier at full strength and never set
`visible_instance_count`, so instances past the number written kept
rendering at their last transform. **A squad that lost half its men went
on displaying them, frozen, for the rest of the match.** Nothing numeric
could notice — `alive` correct, hash correct, no desync — only the
picture was wrong, which is the same class as the frame that once derived
every soldier at y=0 and rendered them inside the terrain.

**Rejected alternatives:** Batching by unit type (rejected on the
baseline above — Godot already culls per-squad instances, and the frame
was CPU-bound anyway). Deriving at a lower rate than the frame rate and
interpolating (rejected — soldiers move continuously along the curve, so
this needs per-soldier interpolation state, which D-006 clause 1
forbids). Frustum-plane tests instead of screen-space projection
(rejected — `Camera3D.get_frustum()`'s normal orientation is easy to get
backwards, and both mistakes it produces, cull-everything and
cull-nothing, look like "the culling does not work" while being opposite
bugs).

**Consequences:** `test-client` needed two fixes that D-031 had quietly
broken and nothing had caught (see the amendment below). The benchmark
duplicates the client's LOD tiers knowingly and narrowly — if the tiers
are retuned, both move.

**Revisit trigger:** All 1,000 squads visible at once is still 28 fps.
That case is prevented by fog (D-004/D-025) and by the zoom cap, and a
realistic client in a 20-player match knows ~54 squads. If a real match
ever puts more than ~500 squads on one screen, the next lever is a
distance tier that stops deriving individual soldiers entirely and draws
a single marker per squad — which is where render LOD stops being
cosmetic detail and starts being a different representation, and deserves
its own decision.

---

**Amendment — `test-client`'s scenario had been broken since D-031, and
one of its gates is vacuous.**

Two defects, both surfaced by making client-side ownership honest, and
neither caused by M5:

1. **The capture scenario went silent the moment it did its job.**
   Founding a town hall consumes the founding party the instant the order
   is given (D-031), and `_drive_m2_scenario` returned early on
   `squads.is_empty()` — so a client that made the correct opening move
   owned nothing and stopped scripting. This is the **identical** defect,
   in the identical shape, as the one M4 fixed in `bot_client.gd`: work
   that needs a BUILDING sitting below a guard about SQUADS. It was
   masked the same way too — the client kept dead squads in its owned
   list, so the guard stayed false while every order it protected was
   refused.
2. **Its phase timings were absolute.** Rally at 1 s, withdraw at 30 s,
   re-rally at 40 s were written when a player started with twelve
   squads. Under D-031 the hall takes 40 s and the first trained unit
   arrives later still, so every deadline had passed before the client
   owned a soldier and all three phases fired in one frame. The scouts
   never marched, nothing was ever concealed, and the verdict correctly
   said so. Phases are timed from when the client first has an army now.

**And the gate that still needs work:** `casualties_applied > 0` is
supposed to prove combat happened. It is now satisfied by **founding a
town hall**, because consuming the founding party is reported through the
casualty path. The check passes without any fighting — precisely the
vacuous-check failure D-022's audit exists to prevent. It is recorded
here rather than fixed because the fix belongs with whoever next touches
the capture scenario: the gate needs to distinguish casualties inflicted
by combat from soldiers spent on construction.

---

### D-043 · 2026-08-02 · Accepted — M4's exit criteria, written retroactively, and the audit against them
**Decision:** M4 shipped without written exit criteria, unlike M1
(D-022), M2 (D-026) and M3 (D-027). This entry writes them down and
audits M4 against them.

Writing criteria *after* the work is exactly the failure mode D-022
records — criteria that drift to fit what was produced. The defence used
here is that **every criterion below is derived from a decision that
predates M4**, and each names the decision it comes from. Nothing is
derived from what M4 happened to produce.

**The criteria M4 should have been given:**

1. Per-squad update cost measured at D-018's full scale (~1,000 squads),
   against D-020's ~50 µs budget and its 100 ms tick.
2. Cost measured across a **range** of squad counts, not one point, so
   accidental non-linearity is visible rather than inferred (D-018's
   target assumes linearity).
3. **Worst** tick measured, not only the mean (D-003 warns a large
   engagement re-paths many squads at once; an average cannot see that).
4. Bandwidth per client per second at D-018's 20 players, with a
   budget-overrun count, against D-003's zero-cost-when-idle claim.
5. Memory measured: the server at scale, and per virtual client, against
   D-018's N-clients-in-one-process analysis.
6. Q8 (ship map size) answered **from the measured curve** rather than
   assumed.
7. An explicit verdict on **D-021's GDExtension trigger**: the named
   candidate kernel measured, and a yes/no with evidence attached.
8. Data that **sizes D-012's LOD tiers** — which phase dominates, and at
   what scale, on both the simulation and the rendering side.
9. Client-side derivation cost measured (D-006 trades bandwidth for
   client CPU; only one half of that trade had ever been quantified).
10. The transport question answered — reliable versus
    unreliable-with-resend, which D-026 explicitly listed as "an M4
    measurement".
11. Measurements taken through the **real system** — server, protocol and
    the actual client path — not only synthetic harnesses.
12. Every measurement reproducible from a named `just` recipe.
13. What M4 deliberately does **not** measure stated explicitly at
    completion, not left implied.

**The audit:**

| # | Verdict | Evidence |
|---|---|---|
| 1 | **Met** | 33 µs/squad, 73.4 ms worst tick at 1,000 squads (D-040) |
| 2 | **Met** | count sweep at 100 / 250 / 500 / 1,000 |
| 3 | **Met, with a scar** | see below |
| 4 | **Met** | 595 B/client/s, 0 overruns (D-038) |
| 5 | **Met** | server 42.5 MB; ~1.4 MB per virtual client |
| 6 | **Met, then re-answered** | see below |
| 7 | **Met** | hatch stays shut, candidate retired (D-040) |
| 8 | **Met for simulation, MISSED for rendering** | see below |
| 9 | **Met** | 0.72 µs/soldier (D-041) |
| 10 | **Met** | reliable-ordered kept, on measured loss (D-042) |
| 11 | **Met, and it was the milestone's most valuable finding** | see below |
| 12 | **Met** | `just profile`, `just test-load`, `just test-client` |
| 13 | **Missed** | see below |

**Criterion 3 — met with a scar.** The worst tick was *not* measured at
first. D-038's original pass reported a comfortable 20 ms average while
the real spike was 323 ms, and the correction is recorded in D-038
because the mistake is instructive. It ended up met, but only after the
average had already produced one confident wrong conclusion.

**Criterion 6 — met, then re-answered inside the same milestone.** D-038
answered Q8 as "keep the ship map at or below ~8,192 cells unless field
building is amortised". D-040 then amortised it, and the answer changed
completely: worst tick is now flat in map size, so the solver no longer
bounds it at all. Both answers were correct when taken. Worth recording
that a milestone's own later work invalidated its earlier conclusion —
that is what a conditional answer is *for*.

**Criterion 8 — the real gap, and it was a knowing one.** Simulation-side
sizing data exists and is good: combat dominates at every scale, which is
where simulation LOD would have something to save. **Rendering-side
sizing data does not exist at all.** Nothing has ever been drawn at
scale.

This is not a discovery — Q15 predicted it precisely, saying M4 leaves
"D-012's LOD tiers only partly served: simulation LOD is measurable, but
rendering LOD is not, and M5 must not design that half blind." So the
gap is real, accepted deliberately, and its trigger is now due. **It is
why M5 opens by measuring the client rather than by building LOD**
(D-044).

**Criterion 11 — met, and the most valuable thing M4 produced.** The
sweep and a live 20-player run disagreed by an order of magnitude (~29 ms
against 866 ms), and the sweep was the one that could not see the truth:
`UnitRoster.by_id` re-scanned `/units` from disk on every call, which a
harness resolving its defs once at setup structurally cannot reproduce.
Had M4 been judged on synthetic profiling alone it would have passed
while the live server spent eight tick budgets in a filesystem walk.

**Criterion 13 — missed.** M4's scope boundary lives in Q15's deferral
note, but was never restated when the milestone was called complete.
That is the documentation gap this entry closes, and D-044 criterion 3
makes the same omission impossible for M5 by requiring Q15 to be either
closed or explicitly re-armed.

**Verdict: M4 is complete on the simulation and network side.** One
criterion (8) is half-missed by prior agreement rather than by oversight,
and one (13) is a documentation gap now closed. Neither blocks M5;
criterion 8's missing half *is* M5's first slice.

**Consequences:** The milestone ladder gains a standing rule —
**exit criteria are written before the milestone, not after.** M4 is the
only milestone that broke it, and this audit is the cost of that. The
practice exists because M1's first "complete" was wrong in two ways
(D-022) and M2's and M3's reviews each found real failures a green suite
could not see.

**Revisit trigger:** None — M4 is closed. If criterion 8's rendering half
turns out to change any conclusion M4 drew about the simulation, that is
a D-038/D-040 amendment, not a reopening of this entry.

---

### D-044 · 2026-08-02 · Accepted — M5's exit criteria
**Decision:** M5 is **"draw it at scale"**, not "LOD". D-015's ladder
named it LOD; M4's measurements make that name wrong in both directions,
so the milestone is reshaped to match what was measured rather than what
was guessed in July.

**Why the rename.** The simulation does not need LOD: D-040 brought the
worst tick to 73.4 ms at D-018's full 1,000 squads, inside D-020's 100 ms
with ~27% headroom, and D-012's own wording is that LOD is built "only
for the tiers M4's profiling shows are actually necessary" — on the
simulation side, currently none. Meanwhile the client has never been
measured at all (D-043 criterion 8), and Q15's deferral trigger —
*"client-render scale must be measured before M5 commits to any rendering
LOD tier"* — is now due.

Two structural facts make the render path the suspect before any LOD
tier: `client.gd` builds **one `MultiMeshInstance3D` per squad**, so
1,000 squads is ~1,000 draw calls; and `_refresh_squads` derives **every
known squad every frame**, including squads nowhere near the camera —
which is the frustum-culling lever D-041 already named as coming *ahead*
of any fidelity reduction.

So: **measure the client, take the cheap structural wins, then build only
the LOD the numbers demand.** LOD is an outcome of this milestone, not
its premise.

**Hardware caveat, stated before the work rather than after.** The
available GPU is integrated/modest, so M5 will **not** definitively
answer "can a client draw 40,000 soldiers". It will produce the shape of
the curve, the draw-call and derivation costs, and an honest
extrapolation — and it will re-arm Q15 with a sharper trigger naming the
hardware still needed rather than letting it lapse.

**The criteria.** Each derived from an accepted decision, each
observable-to-fail, numbered so a review can go line by line as D-026's
and D-027's did.

*Measurement — closes or sharpens Q15*

1. `just bench-render` exists: a **native** recipe (D-014 — the GUI
   client needs a GPU, and `test-client`'s Mesa software rasteriser
   cannot answer a performance question), running without a server, that
   sweeps squad counts to D-018's ~1,000 and reports per count: mean
   frame time, **worst** frame time, draw calls per frame, and soldiers
   drawn.
2. Every reported figure names **the GPU adapter it was taken on**, and
   the recipe prints it. Same discipline as CLAUDE.md's rule that
   µs/squad is never quoted without a squad count: a frame time with no
   hardware attached is not a number anyone can use.
3. Results recorded here, and **Q15 either closed or re-armed with a
   sharper trigger** naming the hardware still required. It must not
   silently lapse — D-043 criterion 13 exists because that already
   happened once.

*Structural wins, measured before and after*

4. Squads are drawn in batches keyed by **unit type** (and live/ghost),
   not one `MultiMeshInstance3D` per squad. Draw calls per frame at 1,000
   squads fall by at least an order of magnitude, with before/after
   numbers from criterion 1's harness.
5. Squads outside the camera are **not derived**. The cull is
   **wrap-aware**: a squad visible only through a seam copy must still be
   derived and drawn, and a test proves a squad across the seam is not
   culled. Getting this wrong makes armies vanish near the seam — D-008's
   recurring torus tax.
6. The lattice step vectors are defined **once**, promoted out of
   `client.gd`'s terrain builder into `TorusSpace`. Terrain tiling,
   camera wrap and the new cull must not become three copies of the same
   arithmetic — M3 deleted a duplicated spawn formula for exactly this
   reason (D-036).
7. Per-frame derivation cost at full scale re-measured against D-041's
   29 ms / 174%-of-a-frame baseline.

*LOD, only if the numbers demand it*

8. **If** frame time at target scale still misses a 60 fps budget after
   4–7, a **render** LOD tier is implemented: camera-keyed (D-012
   explicitly permits this for render), **cosmetic only**, with a test
   proving it never feeds back into simulation, into
   `composition_hash()`, or into anything the server reads — D-006 clause
   2's one-way boundary.
9. **If not**, D-012's render half is resolved with the evidence and an
   explicit revisit trigger — the same standard as the simulation half,
   not an unstated assumption that it is fine.
10. D-012's **simulation** half is resolved as *not needed yet*, citing
    D-040's 73.4 ms at 1,000 squads, with a written revisit trigger.
11. **Q9's remainder is answered** rather than deferred a third time:
    whether tick rate varies by LOD tier.

*The picture, not just the counters*

12. `just test-client` green **and the PNG inspected**. Batching and
    culling are precisely the class of change where every counter passes
    and the image is wrong — this project has already shipped a frame
    with 12 squads drawn, 384 soldiers derived, zero desyncs and no
    visible soldiers at all (D-022's audit).
13. A human `run-client` session confirms squads look right while panning
    across both seams, at minimum and maximum zoom.

*Process*

14. Every new check **observed to fail** before it is trusted (D-022's
    standing rule), with perturbation and revert applied atomically.
15. `just test-unit` green; `just test-load 20 120` still green — the
    client changes touch `ClientState`, so the server path must be shown
    unaffected rather than assumed to be.
16. CLAUDE.md's status section and this log updated to match.

**Rejected alternatives:** Building LOD as D-015's ladder names it
(rejected — D-012's rationale is explicitly against building a complex,
fairness-sensitive system against guessed numbers, and the simulation
budget is already met). Making M5 about playability instead (rejected for
now — D-027's "is it any good" question is real and still open, but Q15's
trigger is *due* and gates M7; playability has no such deadline).
Deferring the client measurement again (rejected — that is how Q15 nearly
lapsed once already).

**Revisit trigger:** If criterion 1's baseline shows the client already
meets 60 fps at target scale untouched, criteria 4–7 become optimisations
without a problem to solve, and M5 should shrink to the measurement plus
resolving D-012 — not proceed out of momentum.

---

### D-042 · 2026-08-01 · Accepted — transport stays reliable-ordered
**Decision:** Keep ENet reliable, ordered delivery for everything.
**Unreliable-with-resend is rejected**, and the M4 measurement it was
waiting on is taken.

**Measured** (20 players, 120 s, docker):

| | |
|---|---|
| peak RTT | 14.0 ms |
| peak packet loss | 0.978% |
| min ENet throttle | 0.69 of 1.00 |
| desyncs | 0 of 2,380 state-hash checks |
| bandwidth | 933 B/client/s, 0 budget overruns |

The loss figure is the interesting one: it is **not** zero even locally,
and ENet's congestion throttle backed off to 69%, so reliable delivery is
genuinely working rather than idling on a perfect link. It absorbed that
loss with zero desyncs. There is no measured problem to re-engineer.

**Rationale, and the part that actually decides it:** curve packets carry
**no sequence number**. `ClientState._handle_curve` installs whichever
curve arrived most recently, and curves are sent ONLY on change (D-003),
so there is no later message to correct a mistake. If two curves for one
squad arrive reversed, the client permanently installs the older one and
nothing detects it — the composition hash covers strength, not position.

So "unreliable with resend" is not a transport swap; it is a protocol
change requiring a version field on every curve, plus the ack/resend
machinery, to arrive at what ENet already does correctly. That is
reimplementing TCP's hard parts to save retransmissions on a link
carrying under 1 KB/s per client.

`test_curve_application_is_last_write_wins_so_order_is_load_bearing`
pins this dependency down so it is explicit rather than implicit, and
says in its own failure message that if it ever stops failing under
reordering, a sequence number has appeared and this decision can be
revisited.

**Rejected alternatives:** Unreliable curves with periodic full
resync (rejected — a periodic refresh is exactly the per-tick snapshot
D-003 exists to avoid; an idle squad must cost zero bandwidth). Splitting
curves onto their own ENet channel to avoid head-of-line blocking
(rejected *for now*, and noted as the cheap first move if loss ever
matters: it costs one constant, needs no protocol change, and ENet's
channels are already allocated — `CHANNELS := 2`, with channel 1 unused.
It was not done because doing it now would be an untested change
answering a problem no measurement shows).

**Consequences:** The wire protocol may continue to rely on ordering.
Anyone adding a message type may assume in-order delivery relative to
every other message, which is a real simplification and should be
understood as a deliberate commitment rather than an accident.

**Revisit trigger:** Real-network testing (not loopback, not docker)
showing loss high enough that ENet's throttle materially reduces
throughput, or a measured curve-delivery latency that hurts play. The
first response is channel separation, not a custom resend layer.

---

### D-041 · 2026-08-01 · Accepted — client derivation cost, and what bounds soldiers on screen
**Decision:** Record what D-006's trade actually costs on the client, and
name the constraint it creates. D-006 sends squad curves and never
soldier positions; the bandwidth saving has been measured since M4's
first day, and the CPU it was traded for never had been.

**Measured** — a real `ClientState` fed by a real `CurveReplicator`, so
the figure includes the dictionary walk and composition lookups a client
actually pays, not just the formation maths:

| squads | soldiers | µs/soldier | ms/frame | of a 60 fps frame |
|---|---|---|---|---|
| 100 | 4,000 | 0.63 | 2.5 | 15% |
| 250 | 10,000 | 0.64 | 6.4 | 38% |
| 500 | 20,000 | 0.70 | 14.1 | 84% |
| 1,000 | 40,000 | 0.72 | 29.0 | **174%** |

Live, 20 players: **1.49 µs/soldier** over 25.9M derivations, worst
single pass **0.52 ms**. The live figure is worse per soldier because
twenty virtual clients share one process and contend; the sweep is the
better estimate of what one real client pays.

**The budget here is a FRAME, not a tick**, and unlike the server's tick
there is nothing to amortise: every soldier must be somewhere every
frame.

**This was 3.7x worse when first measured** — 2.66 µs/soldier, 106 ms and
639% of a frame at full scale. `Formation.soldier_transform` re-sampled
the squad curve twice (position and heading) and rebuilt the rotation
basis *per soldier*, so a 40-man squad took 40 identical curve samples
every frame. Only the slot offset varies per soldier. Hoisting the
squad-wide work out of the loop is not a shortcut around D-006's purity
clause — it is the same pure function with its loop invariants lifted —
and `test_bulk_derivation_matches_the_single_soldier_path` asserts the
bulk and single paths stay bit-identical, because a divergence there is a
client and a server disagreeing about where a man is standing.

**Conclusion: derivation is comfortable for realistic on-screen counts
and is what bounds the pathological one.** A player's own 2,000-soldier
army (D-018) costs ~1.4 ms, under 9% of a frame. 20,000 visible soldiers
fit at 60 fps. All 40,000 visible at once does not — but that is a case
fog of war (D-004/D-025) already prevents and D-012's LOD exists to
handle, and it now has a number attached instead of an intuition.

**Consequences:** D-012's LOD gains its first hard trigger on the CLIENT
side, alongside the server-side one D-038 gave it. The obvious first
lever is not LOD at all: the client currently derives every squad it
knows about, including squads outside the camera frustum. Culling before
deriving is a rendering-layer change with no bearing on D-006, and should
come before any fidelity reduction.

**Rejected alternatives:** Deriving at a lower rate than the frame rate
and interpolating (rejected for now — soldier positions move continuously
along the curve, so this trades a real CPU saving for interpolation state
per soldier, and per-soldier state is precisely what D-006 clause 1
forbids). Sending soldier positions after all (rejected — that is D-006's
40x bandwidth multiplier, and the measurement shows the CPU side is not
the binding constraint at realistic counts).

**Revisit trigger:** If frustum culling lands and a realistic engagement
still exceeds ~30% of a frame in derivation, that is the point to bring
D-012's LOD to the client rather than tune this further.

**Corrected 2026-08-02 (M5): 0.72 µs/soldier understated the real cost,
because the sweep passed no terrain sampler.**

D-006's input tuple is (curve, formation shape, slot index, **terrain
sample**), and the real client always supplies that fourth input — it is
what stands soldiers on the ground instead of at y=0. The sweep behind
the table above passed `Callable()`, so it skipped the sampler entirely
and measured a client that does not exist.

Measured with the sampler attached, as the client actually runs:
**~3.4 µs/soldier**, not 0.72 — nearly five times more, because
`TerrainGen.elevation_at` evaluates 3D simplex noise per call and the
sampler is called once per soldier per frame. Memoising elevation into a
per-cell field (D-045) took it back down, and that single change was
worth 29% of the whole frame at full scale.

The conclusions this entry drew survive — derivation is comfortable at
realistic on-screen counts and binds only the pathological one — but the
margin was much thinner than the number said.

**This is the same failure as D-043 criterion 11's**, one milestone
later and in the opposite direction: there, a harness resolved UnitDefs
once at setup while the live server resolved them per tick; here, a
harness omitted an input the live client always provides. Both are a
measurement of something adjacent to the thing being measured. The rule
worth keeping: **when a harness stands in for the client, list what the
client feeds it and check the harness feeds the same.**

---

### D-040 · 2026-08-01 · Accepted — amortised flow-field builds, and the tick budget met
**Decision:** A flow-field BFS is spread across ticks under a shared
per-tick cell budget (`SquadSim.field_cells_per_tick`, 4,096) instead of
being solved in one slice. Fields still build one-per-destination and are
still shared by every squad heading there (D-007 unchanged) — only *when*
the work happens changes.

Three parts:

1. **`FlowField` splits `build()` into `begin()` + `expand(budget)`.** The
   property this rests on is that **a partially expanded field is correct
   wherever it is defined**: BFS assigns a cell its final distance the
   first time it reaches it, so a partial field is not an approximation to
   be corrected later, it is a complete answer over a smaller region.
2. **Squads wait rather than path on incomplete data.** A squad the
   wavefront has not reached keeps moving on the curve it already had and
   retries next tick. The one thing a caller must not do is read
   UNREACHABLE as "no path" while the field is unfinished — mid-build it
   means "not reached yet", and those are opposite instructions. Getting
   that check in the wrong order would silently cancel every order in a
   wave, which is what `test_an_order_wave_under_a_tight_budget_still_arrives`
   exists to catch.
3. **The queue is FIFO**, so the first group ordered moves first and the
   worst wait is bounded.

**Measured, A/B in the same process** (250 squads, group ordering, worst
tick in ms):

| cells | amortised | not |
|---|---|---|
| 2,048 | 29.1 | 92.7 |
| 8,192 | **28.6** | **344.1** |
| 18,432 | 28.6 | 412.7 |
| 32,768 | 28.9 | 853.4 |

And by squad count on the ship map:

| squads | amortised | not |
|---|---|---|
| 100 | 20.8 | 196.0 |
| 250 | 34.5 | 345.0 |
| 500 | 42.6 | 617.4 |
| 1,000 | **73.4** | **1,210.7** |

**The worst tick is now flat in map size** — ~29 ms whether the map is
2,048 cells or 32,768 — which is the signature of a budget that actually
binds. It costs about 9% on average tick time, which is the right way
round: what blew the budget was always a latency spike, never throughput.

**Consequences, and they are large:**

- **D-020's tick budget is met at D-018's full scale.** 73.4 ms at 1,000
  squads inside 100 ms, with ~27% headroom.
- **D-021's GDExtension hatch stays shut, and its named candidate is
  retired.** The flow-field solver was the one kernel D-021 nominated.
  It did not need native code; it needed to stop doing a whole solve in
  one slice. A constant factor would not have fixed a structural problem.
- **Q8 is answered differently than D-038 answered it.** Map size is no
  longer bounded by the flow-field spike at all — 32,768 cells now has
  the same worst tick as 2,048. The remaining bound on map size is
  per-squad cost, which is a throughput question and a different
  conversation. D-038's "keep the ship map at or below ~8,192 cells
  unless field building is amortised" had its condition met.
- `destination_quantum` and `fields_per_tick` both remain, disabled. The
  profiling sweep no longer re-runs the quantisation A/B every time,
  because D-038 already settled it and paying for a written-down answer
  every run is waste.

**Rejected alternatives:** Letting a squad path greedily toward its
destination on an unfinished field (rejected — BFS expands from the
destination outward, so a distant squad is reached last and the fallback
would become the primary behaviour, not an edge case; and it would walk
squads into terrain the field exists to route around). Building fields on
a worker thread (rejected — the sim is deliberately single-threaded and
deterministic for D-016's replays; a completion racing the tick boundary
would make replays non-reproducible). GDExtension (rejected on evidence,
above). A cap on *builds* per tick rather than cells — this was actually
tried in D-038 and made things worse, because a deferred squad retries
every tick and the throttle cost more than the work it throttled;
budgeting **cells** works where budgeting **builds** failed, because
partial progress is kept rather than discarded.

**Revisit trigger:** If `field_waits` climbs to where squads visibly
hesitate after an order, lower the ambition rather than the budget —
raise `field_cells_per_tick` and accept a larger spike, since the
headroom now exists.

---

**Amendment, same day — the profile sweep was measuring the wrong thing
twice, and both were found only by disagreeing with a live run.**

Two defects came out of taking a 20-player match seriously after the
sweep said everything was fine. Both are the same shape: **a workload
that never exercises what production does.**

**1. The count sweep still used the discredited workload.** D-038's
correction established that giving every squad its own random destination
defeats D-007's sharing and measures a case the design explicitly does
not optimise for. That correction was applied to the map sweep and *not*
to the count sweep, so the published per-squad table kept measuring the
flawed case for another milestone. Numbers from before this are not
comparable to numbers after it. The lesson: a correction applied to one
call site is not a correction.

**2. The unit roster was re-scanned from disk on every lookup.**
`UnitRoster.by_id` called `load_all`, which opened `/units` and re-loaded
every `.tres`, every call — and `SquadSim.tick` calls it once per squad a
building finishes. A tick in which twenty players each completed a unit
spent **858 ms inside a filesystem walk**, more than eight whole tick
budgets, with combat at 0.0 ms and hauling at 0.0 ms.

`just profile` reported a healthy ~29 ms worst tick for that same code,
because a sweep resolves its UnitDefs once at setup. **Only a live server
ever calls `by_id` at 10 Hz.** The sweep was not wrong about what it
measured; it simply could not see this, and a green sweep read as "the
simulation is fine".

It was found by instrumenting rather than theorising: the live server now
reports its worst tick, when it happened, and a per-phase breakdown on
any tick over budget. Three rounds of that narrowed 866 ms → the
buildings block → production → `by_id`. Every hypothesis formed before
the instrumentation was wrong, including two of mine.

Live 20-player result after the fix: **0 ticks over budget out of 1,304,
worst tick 38.1 ms**, verdict green, 0 desyncs.

The general rule this earns, alongside D-038's "read the server log":
**a profiling harness is a workload, and a workload has blind spots.**
Where the sweep and a live run disagree, the live run is the one
describing the game.

---

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

### D-027 · 2026-07-30 · Accepted
**Decision:** M3's exit criteria, written down before the code, in the
shape D-022 established and D-026 confirmed — each criterion names the
decision it discharges. M3 is D-015's **launchable MVP**.

M3 is complete when all of the following hold, `just test-unit` is green,
`just test-load` and `just test-client` report clean **with the PNG
actually looked at**, and a 4-player LAN match can be played start to
finish without restarting the server.

*The match*

1. **Match lifecycle exists** (D-033): lobby → start at the configured
   player count → play → elimination → victory → results. A disconnect
   eliminates that player and removes their army, rather than leaving it
   standing in the simulation as it does today.
2. **Victory by elimination is proven by a headless test** that plays a
   match to completion and asserts exactly one winner — not merely that
   the server did not crash.

*The client*

3. **Selection exists** (D-034): click-select, box drag-select, control
   groups. Right-click no longer means "order everything I own".
4. **A real command vocabulary** (D-034) — move, attack-move, stop,
   gather, build, produce, set-formation — each a distinct C2S opcode,
   each validated server-side per D-002. A client may not command what it
   does not own, and the server enforces that rather than trusting it.
5. **A HUD exists** (D-034): `client.tscn` gains a `CanvasLayer` carrying
   four resource readouts, a selected-squad panel (type, strength,
   morale, routing state), a production queue, match state, and a
   **wrap-aware minimap** — D-008's torus tax landing on the minimap
   exactly as CLAUDE.md predicts it will.

*The economy*

6. **Gatherer squads gather** (D-028): a worker squad assigned to a node
   collects, hauls to a drop-off, unloads and returns, in a loop. Output
   scales with `alive`. No per-soldier state anywhere (D-006 clause 1)
   and no per-unit pathfinding (D-005).
7. **Four resources, data-driven** (D-010): food/wood/gold/stone ledgers;
   `UnitDef.cost` becomes a per-resource cost table and building costs
   live in a new `BuildingDef`. Schema change recorded in D-010's log the
   way `formation_spacing` was.
8. **Hauling's re-pathing cost is measured** (D-003). Round trips
   invalidate curves continuously, which is precisely the
   invalidation-storm risk D-003 flags; the replicator's budget must
   absorb it and `test-load` must report it rather than leaving it
   assumed.

*Buildings — the second entity class*

9. **Buildings replicate without colliding with squads** (D-029). A
   sibling `BuildingSim` with its own packed arrays (D-009), its own id
   space and its own replicator. `CurveReplicator` and `ReplayLog` are
   already entity-agnostic and need no change; what must change is every
   call site assuming *object id == squad index*. **A test must construct
   a squad and a building at the same local index and prove neither leaks
   into the other's wire bytes, hash, or replay output.** This is the
   highest-risk item in the milestone.
10. **Construction progress is a curve** (D-003, which already names
    "build progress" as curve state) — two keyframes, costing nothing
    further until interrupted. Health replicates as **sparse events**
    like casualties, because health is event-shaped, not continuous.
11. **Player-placed construction works** (D-031): placement validated
    against terrain passability on the hex torus, progress visible to the
    owner, buildings destructible.
12. **Building fog is persistent-explored, not ghosting** (D-030). A
    building never moves, so there is no positional staleness; once seen
    it stays known with its state frozen at last-known. **The consequence
    is the trap:** its hash must be computed over a per-client
    *ever-revealed* set, never `visible_to()`'s current-tick answer, or
    the two sides hash differently-shaped sets and the desync check fires
    on a healthy system — the same failure D-025 part 3 and
    `composition_hash`'s header were written against, recurring in a new
    shape. Proven by a test that drives a building out of vision and back
    with the hash checked throughout.

*Combat*

13. **Four unit types with working counters** (D-032): armour class and
    bonus-vs-class multipliers in `.tres`, consumed by `combat.gd`. A
    test must prove the counter changes the outcome — a counter system
    nothing verifies is decoration.
14. **Combat resolves simultaneously** (D-024 amendment). Resolution
    reads round-start strengths, so squad id no longer confers a first
    strike, and a mirror matchup is symmetric by test.

*The world*

15. **The torus looks like a torus** (D-035): the camera wraps rather
    than panning into void, terrain renders continuously across the seam,
    and no entity is drawn outside the meshed world. Verified in the
    `test-client` PNG by looking at it.
16. **Spawns and nodes are map data** (D-036). `server.gd`'s hardcoded
    spawn formula and `client.gd`'s duplicate of it are both deleted.

*Standing obligations*

17. **Cost re-measured and quoted with counts** (D-020, D-012): µs per
    squad-update *and* per building/production update, with vision,
    combat and economy identifiable as components. M2 ended at 70.8
    µs/squad at 48 squads with combat as the hot spot — that is the
    baseline, and economy work must not quietly consume the headroom.
18. **Replays cover a whole match** (D-016): new record kinds for
    buildings and economy, reconstructed under their own top-level key
    rather than sharing a numeric keyspace with squads. `replay-info`
    reports buildings, final resources and the winner.
19. **Every new check observed to fail before it is trusted** (D-022's
    standing rule), with perturbations **applied and reverted atomically**
    — see D-026's completion block for why that wording is now explicit.
20. **Docs match the code**: `CLAUDE.md` and section 2 updated.

**Explicitly NOT in M3**, so scope creep stays visible: LOD (D-012, M5);
a second civilization (M6); any AI opponent (D-015); matchmaking or
internet play — LAN and direct-IP only, so Q3 stays open; reconnection
and desync recovery (Q10); persistence or saves (Q13); mesh tiers 2 and 3
(D-011); terrain-occluded line of sight (deferred by D-025).

**Rationale:** Written before the code for the third milestone running,
because it has now twice caught things a green suite could not — see
D-022's audit and D-026's completion block. Criteria 9 and 12 exist
because the review that produced them identified id collision and
hash-set mismatch as the two failure modes most likely to be invisible
until a live multi-client run.

**Rejected alternatives:** Deferring exit criteria until the work is done
(rejected twice already, for the reasons D-022 records). Treating "it
looks like a game" as the bar (rejected — that would pass without
criteria 9, 12 and 14, which are exactly the ones no playtest surfaces).

**Consequences:** M3 needs ten new decision entries (D-028 … D-036 plus
this one) and two amendments to D-024. It is by a wide margin the largest
milestone so far, adding a second networked entity class, a four-resource
economy, construction, a UI that does not exist at all today, and a match
loop. Implementation is sliced so a playable 4-player battle exists after
slice 1, before buildings or economy land: (1) playable skirmish, (2)
torus presentation, (3) buildings, (4) economy.

**Revisit trigger:** If M4 needs something M3 was assumed to have proven,
add it here rather than quietly widening the milestone.

**Reviewed against these criteria, 2026-07-31.** Written after the work,
by the same agent that did it — the arrangement D-022's audit warns
about — so it is stated as a checklist with evidence rather than a
verdict, and the gaps are listed as plainly as the passes.

*Met, with the evidence:*

1–2. Match lifecycle and elimination — `match_state.gd`, lobby →
running → finished, elimination read from `living_squad_count` so
"defeated" has one definition. Disconnect wipes the army and the ordinary
rule notices. Tested in `test_match.gd`, including the cases a smoke run
cannot distinguish: a match that never starts, one that declares a winner
instantly, one that never ends.
3–5. Selection, the command vocabulary, and a HUD — click, shift-extend,
box drag, Ctrl+1-9 groups; move, stop, attack-move, build, produce, each
a distinct opcode validated server-side through one shared helper; a
CanvasLayer with status, selection, controls and a wrap-aware minimap.
6–8. The economy — gatherer SQUADS (D-005 affirmed, not excepted),
four resources, biome-derived depleting nodes, round-trip hauling.
`test_economy.gd`.
9–12. Buildings — sibling `BuildingSim`, the id-collision test that
landed before any other building code, construction, and
persistent-explored fog whose hash is computed over the ever-revealed
set. A test hashes the *visible* set instead and asserts it desyncs, so
the trap is demonstrated rather than described.
13–14. Four unit types with a working counter triangle, and simultaneous
combat resolution. Perturbing the latter back to sequential makes mirror
matchups differ by exactly one soldier.
15–16. The torus renders as one — terrain tiled across both seams, the
camera wrapping in continuous lattice coordinates — and spawns are map
data with the duplicated formula deleted from both files that held it.
18. Replays carry buildings under their own top-level key, and
`replay-info` reports what was founded.
19. Every new check was perturbed, observed red, and reverted, with the
perturbations applied and reverted atomically after M2's review found two
left behind.

*Not met, and recorded rather than glossed:*

- **Criterion 17 is only half met.** Cost is measured and its components
  are identified, but the milestone changed the game's shape underneath
  the metric: an opening of one founding party means a run reaches a
  useful squad count only after production has been going for a while,
  and the per-squad figure is dominated by fixed overhead below ~20
  squads.

  The best M3 measurement, from `just test-load 4 180`: **100.95 µs per
  squad-update at 24 squads — vision 42.2, combat 54.6**, with four town
  halls standing. That is **not** comparable to the 65.2 µs measured at
  48 squads before the opening changed, and saying so is the point:
  CLAUDE.md's rule is that the figure is meaningless without its squad
  count, and here the counts differ. What IS comparable is the absolute
  work per tick — about **2.4 ms against a 100 ms budget** — which is the
  number that actually answers "does it keep up", and it does, with
  `dropped_ticks=0` throughout.

  Two things this milestone added that the metric now folds in: buildings
  contribute vision at a larger radius than squads, and their cost lands
  on whatever squad count happens to exist. A per-squad figure comparable
  to M2's needs a run that reaches ~48 squads, which needs production
  running longer than any current recipe does. That is M4's job, and M4's
  tiered sweep (D-027's own reference point) is exactly the shape of
  measurement this needs.
- **Criterion 20 is partly done.** `CLAUDE.md` describes slices 1–2; the
  economy and buildings are not yet in it.
- **Not attempted at all: the human 4-player LAN session** D-027's
  verification section calls the one criterion no automated check
  substitutes for. Everything above is machine-verified. Whether this is
  *fun* — whether founding, gathering and fighting hang together as a
  game — is untested, and that is the whole point of a "launchable MVP".

**M3 is therefore not declared complete.** The systems are built and
green; the milestone's own bar includes a thing no test can stand in for.
M1 and M2 were both declared done and then found incomplete, and the
honest reading of this checklist is that M3 is one playtest and one doc
pass away rather than finished.

**A playtest did happen, 2026-07-31/08-01 — one human against three
bots.** Recorded because it is the only part of that criterion which has
been discharged, and because what it found is the argument for the
criterion existing at all.

It produced four defects in about twenty minutes, none of which 260
passing tests had caught:

1. **The minimap hit-test swallowed every click.** Hit-testing asked the
   `TextureRect` for its own rectangle; when that reported larger than
   intended, every click on screen counted as a minimap jump — so
   selection AND ordering died together. A guard had silently expanded to
   cover everything it was meant to exclude.
2. **A player with a standing base was declared defeated.** Elimination
   tested squads only, and founders are consumed by the hall they found,
   so making the *correct opening move* ended your match — after which
   the server refused every order you sent.
3. **Founders were consumed on completion rather than on order**, leaving
   a 40-second window in which one founding party could found unlimited
   town halls. The playtest founded three in about five seconds.
4. **Refused orders were silent.** A build nine cells from its founders,
   against a three-cell reach, did nothing and said nothing — a refused
   order was indistinguishable from a broken key.

Each is fixed with a regression test. The pattern across all four:
**bots do each thing once, in the expected order, and never press the
same key three times in five seconds.** Every automated run exercised
only the path on which the defect is invisible. That is not a gap in the
suite's thoroughness — it is the difference between verifying a system
and using one, and it is exactly why D-027's verification section named a
human session as the criterion no automated check substitutes for.

**What remains undischarged is narrower than "a playtest": it is the
judgement.** Whether founding somewhere feels like a decision, whether
losing the founders lands as a fair price at the moment it happens,
whether fog at 128x64 hides too much, whether the counter triangle reads
at the speed a fight actually happens. Four human players, and an
opinion. Nothing in this repository can produce that, and a milestone
named "launchable MVP" should not be closed without it.

**Amended 2026-08-01, by Dave's call: the session criterion is ONE human
against three bots, plus a written judgement.** Four humans on four
machines is a logistics problem rather than an engineering one, and it
would leave M3 unclosable on any timescale a solo developer controls. One
human against three bots is the strongest verification this project's
actual team can produce — and it has already demonstrated its worth by
finding four defects in twenty minutes that 260 tests had not.

This is a deliberate lowering of the bar, recorded as such. The risk it
accepts: three bots are not three people, and the things four humans
would surface — collusion, unexpected build orders, someone doing the
thing nobody designed for — stay untested until M7's Steam work brings
real opponents.

**And a scope reversal that makes it defensible: BOTS ARE NOW A SHIPPED
FEATURE.** D-015 scoped M3 with "no AI opponent", so bots existed purely
as a load-test fixture. Dave's call reverses that — they ship, which
means effort spent making them cleverer and more genuinely competitive is
product work rather than test scaffolding.

The reason this matters beyond the feature list: it removes the tension
that has quietly shaped every load test so far. Bot behaviour was written
to *exercise code paths* — converge here, raid there, found once — and
that is exactly why every defect the human playtest found was invisible
to them: bots did each thing once, in the expected order. Making them
play to win instead of play to cover makes them better opponents AND
better tests at the same time, with no conflict between the two goals.
The reverse held before: every hour spent on smarter bots was an hour
spent on scaffolding.

Consequences: D-015's "no AI opponent" cut line no longer holds and
should be treated as superseded for M3 onward. Bot quality becomes a
product concern with its own budget, and D-018's scale targets now have
to accommodate whatever an AI opponent costs per player at full scale —
worth measuring at M4 rather than assuming it is free.

**M3 CLOSED 2026-08-01 by Dave's call.** Every systems criterion is met
with evidence above. The amended session criterion is partly discharged:
the human-versus-bots sessions happened and produced five defects, all
fixed and regression-tested. The **written judgement was not produced** —
recorded plainly rather than glossed, because that is the part D-027
argued no automated check substitutes for, and skipping it is a choice
rather than an oversight.

What that leaves genuinely unknown, and worth revisiting whenever the
game is next played: whether founding somewhere feels like a decision,
whether losing the founders reads as a fair price at the moment it
happens, whether fog at 128x64 hides too much, and whether the counter
triangle is legible at the speed a fight resolves. None of those are
bugs, so none will surface as a failing test; they will surface as a
game that is correct and not much fun, which is the failure mode this
criterion existed to catch.

**Amended 2026-07-30, when the seven open items closed** (see section 2).
Four resolved as recommended and change nothing here. Three did not, and
these criteria change with them:

- **Criterion 1 gains a squad cap.** A per-player cap is enforced
  server-side at production time, and a test proves production is
  *refused* at the cap — not merely that the cap exists as a number.
  **One shared cap covers military and gatherer squads alike**, so the
  test must show *both* production paths — barracks and town centre —
  refusing against the same ceiling, and a gatherer squad consuming a
  slot a military squad could have used. A cap that only one path
  respects is worse than none, because the player would discover it by
  being unable to explain their own economy.
- **Criterion 6 gains private wallets.** Wallets replicate to their owner
  only, proven byte-level in the shape D-026 criterion 6 used for fog: an
  opponent's client receives zero wallet bytes. Nodes are biome-derived,
  deplete, and their remaining stock replicates under criterion 12's
  persistent-explored rules — a reuse of that mechanism, never a second
  one.
- **Criterion 9 covers four building types, one of which shoots.** The
  tower makes buildings attackers rather than only targets. Buildings
  resolve attacks in a pass **separate** from the squad path, and a test
  proves a tower damages a squad without any squad-only code becoming
  reachable for a building — `_check_rout` calls `force_move`, and a
  building has neither morale nor the ability to move.
- **Criterion 14 also closes D-024's last open item**: rout resolves as
  rally-with-hysteresis, the behaviour already implemented.
- **Criterion 16 becomes map generation, not just map data.** The map is
  128×64; generation is quadrant-symmetric; spawns sit at identical
  relative offsets per quadrant. **A test asserts `elevation_at(x, y) ==
  elevation_at(x + width/2, y) == elevation_at(x, y + height/2)` for
  every cell** — exact, cheap, and trivially observed to fail by
  perturbing the symmetry factor. Three constraints ride along:
  `elevation_frequency` halves to preserve apparent feature size, width
  and height must divide by the symmetry factor with height still even
  (D-008), and **the symmetry order is tied to the player count** —
  changing from 4 players is a generation change, not a config tweak.
- **Criterion 17 gains flow-field build cost**, reported separately now
  the map is 4x larger, against the pre-change baseline of 70.8 µs/squad
  at 48 squads.

**Consequence for sequencing:** the map change moves to slice 1, ahead of
everything else, so every later measurement is taken against the real map
rather than needing to be re-based. Slices are now: (1) map foundations,
(2) playable skirmish, (3) torus presentation, (4) buildings, (5)
economy. D-036 and D-037 are added to the entries this milestone needs.

---

### D-026 · 2026-07-30 · Accepted
**Decision:** M2's exit criteria, written down before the code, in the
same shape D-022 established for M1 — each criterion names the decision it
discharges. M2 is "combat + fog of war" and nothing else.

M2 is complete when all of the following hold, `just test-unit` is green,
`just test-load N DURATION` reports clean, and `just test-client` reports
clean **with its PNG actually looked at**:

1. **Combat is D-024's model, at squad granularity** (Q7, D-005, D-006).
   Resolution is squad-level and stochastic; the server is the only side
   that resolves it. No per-soldier state exists anywhere in the
   simulation — `Formation` remains all-static with no instance fields,
   and nothing stores a soldier's health, target, or position.
2. **Combat is deterministic given a seed** (D-016). The RNG is seeded
   from map configuration and advanced in squad-id order, never from
   wall-clock time, so the same inputs produce the same battle twice.
   Proven by a test that runs an engagement twice and compares outcomes.
3. **Casualties replicate as sparse reliable events** (D-006's "combat
   outcomes replicate as sparse reliable events, not continuous
   per-soldier state"), sent only when a squad's strength actually
   changes. A tick in which nobody dies sends zero casualty bytes, and a
   squad that is idle and not fighting still costs zero bandwidth
   (D-003). Proven by a byte-count test, not by inspection.
4. **Morale and routing exist at squad level** (D-019). Morale falls with
   casualties, a squad below its `rout_threshold` routs, a routed squad
   flees and does not obey player orders while routed, and there is a
   defined path back (rally or permanent). Tested at the sim level.
5. **Fog of war is curve gating and nothing else** (D-004). `SquadSim.
   visible_to()` returns a real per-player set computed from D-025's
   vision field. No second data-hiding mechanism is introduced, and
   D-022's "known stub: `visible_to()` returns every squad" note is
   closed rather than restated.
6. **Fog is proven to hide, from the wire** (D-004, and the audit rule
   that a check must observe the thing it claims). A test shows a client
   receives **zero curve bytes** for an enemy squad outside its vision —
   byte-level, not "the client chose not to draw it" — and that horizon
   clipping still applies to a squad the moment it is revealed, so
   D-003's intent-leakage property survives reveal.
7. **Reveal and conceal follow D-025**: true-position pop-in on reveal,
   stale flagged ghost on conceal, conceal delivered as an explicit event
   so both sides agree which squads are live. No synthetic catch-up
   curves anywhere.
8. **The desync check stays meaningful under fog** (D-006's protocol
   obligation). Client and server hash the same set — ghosts excluded by
   construction — `state_hash_checks > 0` remains a verdict condition,
   and composition now changes during a run (casualties), so the check is
   exercised against moving state rather than a constant.
9. **Every new check is observed to fail before it is trusted** (D-022's
   audit rule, standing). The load test's verdict gains conditions that
   combat rounds were resolved, casualties were applied, and both a
   reveal and a conceal occurred — because a fog test in which nothing
   was ever hidden, or a combat test in which nobody died, proves
   nothing. Each new condition is perturbed, watched go red, and
   reverted, and that is reported.
10. **Cost re-measured and quoted with a squad count** (D-020, D-012).
    `test-load` still prints µs per squad-update, with vision and combat
    identifiable as components, compared against D-020's ~50 µs budget
    and extrapolated to D-018's counts. Per CLAUDE.md the number is
    meaningless without its squad count.
11. **Replays can explain a battle** (D-016). Casualty and rout events
    are in the curve log, and `just replay-info` reconstructs final squad
    strengths. The server's replay is deliberately unclipped ground truth
    — it contains what fog hid from every client — and that is written
    down so nobody "fixes" it into per-client logs.
12. **New stats are data, and the schema change is recorded** (D-010).
    Vision range, combat, and morale tuning live in `UnitDef` fields and
    `/units/*.tres`, not as constants in scripts, and the schema addition
    is logged against D-010 the way `formation_spacing` was.
13. **The docs match the code**: `CLAUDE.md`'s status section, section 2's
    Q7 entry (struck through), and D-004's status (Provisional →
    Accepted, semantics closed by D-025).

**Explicitly NOT in M2**, so scope creep is visible if it happens:
economy or production of any kind; LOD (D-012, M5); terrain-blocked
line of sight — vision is radius-only over the torus and elevation does
not occlude, stated rather than assumed; buildings; additional civs
(D-015); unreliable-with-resend transport (an M4 measurement); and any
per-soldier combat resolution (D-024's rejected alternative).

**Rationale:** M1's first "complete" was declared against criteria the
same agent wrote while building, and it drifted to fit what was produced
(see D-022's audit). Writing M2's criteria before any M2 code exists, and
deriving each from an already-accepted decision, is the cheapest available
defence against that recurring. Criteria 3, 6, and 9 exist specifically
because M1's equivalents were satisfiable vacuously.

**Rejected alternatives:** Deferring exit criteria until the work is
done (rejected — that is precisely the failure D-022 documented).
Reusing M1's criteria with combat appended (rejected — fog changes what
"client and server agree" even means, because they now agree about
different sets; that needs its own criterion, which is 8).

**Consequences:** Criterion 9 makes the perturbation evidence a
deliverable, not a private step. Criterion 11 extends the replay format,
which is a wire-format change under D-016 — the log stays byte-identical
to what is sent, so the casualty event has one definition in
`NetProtocol` used by server, client, and replay alike.

**Revisit trigger:** If M3 needs something M2 was assumed to have proven,
add it here rather than quietly widening the milestone.

**M2 was declared complete 2026-07-30, after a review that first found it
incomplete.** Recorded here because the pattern is now twice-confirmed:
writing the criteria before the code (this entry) worked, and reviewing
against them still caught three failures that every test suite passed.

What the review caught, all three invisible to `just test-unit`:

1. **Criterion 10 — cost was 5.6x over budget.** 282 µs per squad-update
   at 48 squads (vision 232, combat 47), against M1's 1.5–2.7 µs for the
   same 48. Both `Vision._stamp_squad` and `Combat._find_target` called
   `TorusSpace.distance()` once per candidate cell of a hex disk, and
   `distance()` → `delta()` evaluates nine ghost-copy candidates and
   allocated two array literals per call. The fix is geometric, not
   architectural: **a hex disk is translation-invariant on a torus**, so
   the offsets within a radius are computed once, cached
   (`TorusSpace.disk_offsets`), and reused for every squad and every
   rebuild — zero distance calls while stamping. Now **70.8 µs/squad at
   48 squads (vision 15.3, combat 45.5)**, ~71 ms inside a 100 ms tick at
   D-018's counts. D-020 was never in question; the implementation was.
2. **Criterion 11 — replays were silently truncated.** `just replay-info`
   on a real run reported "final strengths (0 squads known)" from a file
   exactly 512 bytes long — a buffer boundary. Nothing in the codebase
   ever called `flush()`, and `docker compose stop` sends SIGTERM, which
   Godot headless does not run `_exit_tree` for, so `close()` never ran.
   This predates M2 and was harmless while replays held only curves; M2
   made it matter, because composition and casualty records are written
   *after* the curves and so were exactly what got cut. `ReplayLog` now
   flushes per record.
3. **Criterion 11's visual half proved M1, not M2.** `test-client` ran a
   single client against a server with no opponent — `ghosts=0`, every
   squad at full strength — so the frame could not contain a casualty or
   a ghost however carefully anyone looked at it. It now runs bots
   alongside the client, and the verdict requires casualties, conceals
   and reveals to have happened. A worker also found, while fixing this,
   that `GeometryInstance3D.transparency` renders nothing under the
   `gl_compatibility` rasteriser `test-client` is forced to use, so the
   ghost fade was invisible — replaced with material-level alpha.

**And a process failure worth more than any of them.** Two workers were
interrupted mid-perturbation and each left a live perturbation in the
tree: a counter increment replaced with `pass`, and `_max_known_squads()`
hardcoded to `return 999999`. Either would have shipped a check that
could never fail — the precise defect D-022's audit exists to prevent,
reintroduced *by the discipline meant to prevent it*. Both were caught by
grepping the tree during review rather than by any test, because a
permanently-passing check is invisible to a green suite by definition.
**Apply and revert a perturbation within a single atomic step**, and
grep for leftovers before trusting a suite. Added to the standing rule in
D-022 rather than replacing it.

Not everything found was fixed. Two items were logged to section 2
instead, both out of D-026's scope: combat's sequential resolution order,
and a seam-crossing rendering artifact visible in the M2 frame.

---

### D-025 · 2026-07-30 · Accepted — closes D-004's Provisional semantics
**Decision:** Three parts, all riding on D-003/D-004's curve gating.

1. **Vision is a per-player field over cells, not a per-pair test.** Each
   tick (or each vision-recompute interval, which may be lower), each
   player's vision coverage is stamped once from its own squads'
   positions and `vision_range`, and a squad's visibility is then a
   single O(1) lookup into the owning player's coverage. Vision is
   radius-only on the torus via `TorusSpace.distance` — elevation does
   not occlude in M2.
2. **Reveal is a truthful pop-in.** A squad entering vision has its
   current curve replicated clipped to `[now, now + horizon]` exactly as
   any other squad would be. The client therefore sees it at its true
   present position with no history and no future beyond the horizon. No
   synthetic curve is ever manufactured.
3. **Conceal leaves a stale ghost, announced explicitly.** When a squad
   leaves vision the server sends a conceal event; the client keeps its
   last-known curve and composition, marked stale, and stops treating it
   as live. It receives no further updates until revealed again, at which
   point the resend replaces the ghost wholesale.

**Rationale:** Part 1 is a cost decision. The obvious implementation —
for each player, for each squad, is any of my squads within range — is
~50,000 distance tests per player per tick at D-018's counts, so about a
million per tick across 20 players, against a 100 ms budget that has to
cover the simulation as well. Stamping coverage per player and looking up
per squad replaces that with tens of thousands of cheap operations, and it
is also the structure that terrain-occluded LOS would later extend rather
than replace.

Part 2 falls out of D-003 already being mandatory: clipping to the horizon
is what a reveal *is*, so pop-in requires no new machinery, and it cannot
leak — the keyframes describing where the squad has been were never in the
packet. A synthetic catch-up curve was tempting for smoothness and is
rejected below.

Part 3's explicit conceal event is not a convenience. Without it the
client cannot distinguish "this squad is out of vision" from "its update
is late", and D-006's composition hash then compares different sets on the
two sides: the server hashes what a client can see, while a client
carrying ghosts hashes more than that. The desync check would fire
constantly on a system working exactly as designed — and a check that
cries wolf gets muted, which is the failure mode `NetProtocol.
composition_hash` was written to avoid. Announcing conceal keeps the
hashed set agreed by construction and makes the ghost a deliberate,
inspectable state instead of an inference from silence.

**Rejected alternatives:** *Synthetic catch-up curve on reveal* (rejected
— it draws motion that never happened, and worse, it leaks: a unit
sliding in from its last-known position tells the player it moved while
unseen, which is exactly the class of information D-003's clipping
exists to withhold). *Hard removal on conceal* (rejected — simplest and
genuinely tempting for testability, but it discards the tactical memory
the genre is built on, and D-019's Total War half assumes the player
reasons about where an enemy was last seen). *Per-pair visibility tests*
(rejected on the cost math above). *Terrain-occluded LOS in M2* (deferred
— it needs a height field the sim does not yet carry, and radius-only
vision is enough to prove the gating).

**Consequences:** `SquadSim.visible_to()` becomes real and D-022's stub
note closes. The protocol gains a conceal event and must send squad
composition on reveal, not only at join — a client cannot derive soldiers
for a squad it was never described (D-006's protocol obligation). Client
state grows an explicit live/ghost distinction, and `composition_hash`
covers live squads only. Ghost curves are stale by design: anything that
samples them must know it is reading history, and the client's own
accounting must not count a ghost as a live squad.

**Revisit trigger:** Terrain-occluded or unit-blocking LOS, stealth
units, or shared vision between allied players. Any of those changes part
1's field computation; none of them change parts 2 or 3.

---

### D-024 · 2026-07-30 · Accepted — resolves Q7's shape
**Decision:** Combat resolves **at squad level, stochastically**, on the
server only.

- A squad engages an enemy squad when it is within its `attack_range`
  (converted to cells over the torus). Engagement is squad-vs-squad;
  soldiers do not pick individual targets.
- Damage output per round is a function of aggregate squad state —
  strength (`alive`), per-soldier `damage`, and `attack_interval` — and
  the roll is stochastic, drawn from a seeded RNG.
- Casualties are applied as **integer decrements to `alive`**, with
  fractional damage carried in a per-squad accumulator.
- Morale is a per-squad value that falls with casualties taken; a squad
  below its `rout_threshold` routs, flees as a squad, and ignores player
  orders until it rallies (D-019).
- Rounds are a whole multiple of the 10 Hz tick, per D-020's 100 ms
  minimum granularity.

**Rationale:** D-006's confirmation block already narrowed Q7 to answers
expressible within the purity clause, and this one satisfies it trivially
rather than delicately: nothing in combat reads or writes a soldier
position at all.

The decisive detail is that **`alive` is the only formation input a death
changes.** `Formation.slot_offset` takes `(shape, slot, alive, spacing)`,
so with `alive = N` the occupied slots are exactly `0..N-1` and the
formation restamps. D-006 clause 3 asks for casualty reassignment to be
deterministic and derived from the ordered death-event log — under this
model that is satisfied by construction and needs no per-soldier
identity, because *which* soldier died is not an input to anything. The
ordered log is simply the sequence of strength decrements, which is what
already replicates.

Squad-level state that combat does need — the damage accumulator, an
attack-interval accumulator, current morale — is per-*squad*, which
D-009's packed arrays are exactly for. D-006 forbids per-*soldier*
integration state; it says nothing against squads having state, and
squads already have position, destination, and strength.

It is also the only one of the three candidate shapes that stays cheap at
D-018's counts (aggregate arithmetic per engaged pair, not 40,000
per-soldier resolutions per round) and that LOD can later aggregate
without building a second combat model (D-012).

**Rejected alternatives:** *Deterministic per-soldier resolution,
read-only* (rejected — it satisfies D-006 clause 1 only in the strict
read-only form, costs ~40,000 position derivations per round at full
scale, and makes D-012's LOD aggregation a second implementation of
combat rather than a coarsening of this one. Per-soldier resolution that
*moves* soldiers as a result of combat is rejected outright: it trips
D-006's corrected revisit trigger). *Hybrid LOD-gated resolution*
(rejected for M2 — it pulls M5's LOD work forward and obliges proving two
models agree in aggregate; revisit at M5 if the squad-level model reads
as too coarse near the camera). *Continuous per-tick damage without
stochastic rolls* (rejected — deterministic attrition makes even fights
decide on stat ties alone, and D-019's morale model wants the variance).

**Consequences:** `UnitDef` gains combat/vision tuning fields, recorded
against D-010's schema log. The RNG must be seeded from map configuration
and advanced in a fixed order (squad id) so replays reproduce battles
(D-016) — a wall-clock or unordered RNG would silently break replay
forensics, which is the one tool for diagnosing a desync. Casualties make
squad composition change *during* a run for the first time, so
composition must replicate as events and the desync check finally runs
against moving state. Combat resolution is server-only: clients receive
outcomes and never roll, so there is no client-side RNG to diverge.

**Revisit trigger:** Combat that reads as too coarse at the camera —
specifically, a player being unable to tell *why* a fight was lost —
argues for the hybrid alternative at M5 alongside D-012. Any wish for
soldiers to physically react to being hit is a D-006 revisit first, not a
combat tuning change.

---

### D-023 · 2026-07-29 · Accepted
**Decision:** The authoritative simulation is driven by an **explicit
fixed-timestep accumulator owned by the sim**, not by Godot's
`_physics_process`. `physics/common/physics_ticks_per_second` in
`project.godot` is left at 10 only so the engine's own stepping doesn't
run wildly out of proportion to the sim; nothing reads it as the tick
rate. D-020 remains the single source of truth for 10 Hz.

**Rationale:** Three reasons, in order of weight. (1) D-009 keeps
simulation state in packed arrays outside the scene tree, so binding the
sim to a scene-tree callback is a coupling the design explicitly does not
need. (2) It makes the sim tickable without a `SceneTree` at all — unit
tests and replay playback drive `tick()` directly in a loop, which is
what lets the M1 suite test the simulation rather than only its parts.
(3) It keeps tick rate a property of the simulation (D-020) rather than a
project setting, so changing it can't happen by editing an engine config
field and silently invalidating D-018's budget math.

**Rejected alternatives:** `_physics_process` as the driver (rejected —
couples sim to the scene tree and to an engine setting, and makes
headless replay/test stepping awkward); `_process` with variable delta
(rejected outright — a variable-rate authoritative sim is not
reproducible, which breaks replays under D-016).

**Consequences:** The server node calls into the sim from `_process` with
an accumulator, consuming whole ticks and carrying the remainder. Tests
call `tick()` directly. `project.godot`'s physics tick setting is now
decorative with respect to the sim — noted in that file so nobody
"fixes" it into load-bearing status.

**Revisit trigger:** None currently.

---

### D-022 · 2026-07-29 · Accepted
**Decision:** M1's exit criteria, written down. D-015 named the milestone
ladder but deferred per-milestone exit criteria to "the 2026-07-28
planning session," which is not in the repo — so "M1 complete" was not a
checkable claim. These are derived from the already-accepted decisions
rather than newly invented, and each criterion names the decision it
discharges.

M1 ("movement + netcode proof") is complete when all of the following
hold and `just test-unit` is green:

1. **Torus is a type, not a convention** (D-008). A wrap-aware hex
   coordinate type exists; neighbor, distance, and interpolation all go
   through it. GUT tests cover seam-crossing cases explicitly — D-008
   requires this from M1 onward.
2. **Flow-field pathfinding** (D-007) computes a field per squad
   destination over the torus, CPU-side only, and a squad on the far side
   of a seam takes the short way around.
3. **Curve-based sync** (D-003) with all three properties demonstrated by
   test, not by inspection: an idle object costs zero bandwidth; curves
   are clipped to a visibility horizon so a client cannot read an enemy's
   future path (intent leakage); re-pathing goes through a budgeted
   scheduler rather than naive immediate replication.
4. **Derived soldier positions** (D-006) — a pure formation function
   drives `PrimitiveUnit`'s MultiMesh, with tests proving purity (same
   inputs → same outputs, no carried state) and deterministic casualty
   restamp.
5. **10 Hz authoritative sim** (D-020, D-009) with squad state in packed
   arrays outside the scene tree, and per-squad update cost measurable —
   D-012 requires the cost be measurable and swappable from M1 even
   though LOD isn't built until M5.
6. **Replay capture** (D-016): the curve log lands in `artifacts/` in a
   replayable format.
7. **Every M1-gated recipe is real**: `run-server`, `run-client`,
   `test-load`, `gen-terrain-preview` no longer exit with "NOT
   IMPLEMENTED UNTIL M1", and `just test-load N DURATION` runs clean.

**Explicitly NOT in M1** (so scope creep is visible if it happens):
combat resolution of any kind (Q7, M2), fog of war (D-004, M2), economy
or production, terrain generation beyond what `gen-terrain-preview`
needs to exercise chunking (D-017), and any LOD (D-012, M5).

**Rationale:** The project's workflow depends on decisions being written
down (CLAUDE.md). An unwritten definition of done for the milestone that
proves the whole architecture is the highest-leverage instance of that
gap. Writing the criteria as discharges of existing decisions also
surfaces whether the decisions actually cover M1 — they do, with no gaps
found while deriving this.

**Rejected alternatives:** Treating M1 as done when "movement works
visually" (rejected — that would pass without the three D-003 properties,
which are the entire point of the netcode proof). Reconstructing the
original planning session's criteria (rejected — not recoverable from the
repo; deriving from accepted decisions is both possible and more
authoritative).

**Consequences:** `CLAUDE.md`'s pointer to "M1's exit criteria in
`game_design_decisions.md` section 2" was wrong — section 2 is Open
Questions. Updated to point here.

**Revisit trigger:** If M2/M3 turn out to need something M1 was assumed
to have proven, add it here rather than quietly widening the milestone.

**M1 was declared complete 2026-07-29, then audited and found incomplete
the same day.** See the audit block after the criteria list. The
completion notes below are accurate about what was built; they were
wrong that it was done.

**M1 complete (revised) 2026-07-29.** All seven criteria met after the
audit fixes; `just test-unit` is green at 141 tests / 10 scripts, and
`just test-load 4 12` runs clean end to end. Criterion by criterion:

1. `torus_space.gd` — wrap enforced by every method normalising its own
   inputs, so a call site that forgets to wrap cannot get a different
   answer than one that remembers. Seam cases are tested exhaustively
   (every cell pair for distance symmetry and the wrapped bound).
2. `flow_field.gd` — BFS from the destination through
   `TorusSpace.neighbor_index`, one field per destination shared by all
   squads heading there. Verified as exactly the analytic wrapped hex
   distance at every cell, which is the check a non-wrapping expansion
   fails.
3. `state_curve.gd` + `curve_replicator.gd` — all three D-003 properties
   proven by test: 500 idle objects cost literally zero bytes; a client
   decoding the raw wire bytes cannot recover an enemy position 10s
   ahead; a 1,000-squad simultaneous re-path stays inside the byte
   budget and drains without starvation.
4. `formation.gd` — all-static, no instance state. Purity is tested by
   evaluation order, by time-travel (sample late, then early, then late
   again), and by two independent evaluators standing in for client and
   server. Cosmetic offsets live in a separate file (`cosmetic_offset.gd`)
   so clause 2's one-way boundary is structural rather than a comment.
5. `squad_sim.gd` — packed arrays, no Nodes, explicit 10 Hz tick
   (D-023). **Measured 1.5–2.7 µs per squad-update** at 48 squads against
   D-020's ~50 µs budget — a few percent of budget, which is direct
   evidence for D-021's judgement that GDScript would fit. The figure
   varies run to run with host load; treat the order of magnitude as the
   result, not the third digit.

   **The figure is only comparable at equal squad counts.** It is total
   tick time over (ticks × squads), so per-tick fixed overhead is charged
   to the per-squad number and inflates it when squads are few — a real
   play session at 12 squads measured ~3.9 µs where 48 squads measured
   ~2 µs on identical code. Quote the squad count alongside it, or a
   smaller test will look like a regression. The bias runs in the safe
   direction for D-018's extrapolation: it overstates per-squad cost at
   low counts, so real headroom at ~1,000 squads is better, not worse.
6. `replay_log.gd` — the curve log, byte-identical to the wire format.
   `just replay-info` reads a real load-test replay back and
   reconstructs all 48 squads.
7. All recipes real; `run-client`, `gen-terrain-preview` and
   `replay-info` added.

**Defects found and fixed while building M1**, recorded because each was
silent rather than loud:

- `StateCurve.clipped()` dropped the keyframe sitting exactly on the
  window start — the common case, since the sim emits keyframes on the
  same tick boundary the replicator clips at.
- `just test-load` reported "clean" for a run in which every bot exited
  non-zero. Grepping for the absence of bad news cannot distinguish
  "nothing went wrong" from "nothing happened"; it now also checks exit
  status and an explicit verdict.
- `docker compose` `depends_on: server` under `run --rm` left a running
  server container behind after every bot run — a stray-container leak
  directly against D-014.
- `NetProtocol.decode_welcome` appended to `out["squads"]`, and
  `PackedInt32Array` is a value type in GDScript, so it appended to a
  copy. Clients silently believed they owned no squads.
- Terrain noise was sampled at ~1 feature per cell, producing per-cell
  static that still passed every aggregate check (plausible water
  fraction, plausible biome spread) while having no landmasses at all.
- Bot teardown ran twice (once from the run loop, once from
  `_finalize`), calling `peer_disconnect_now` on a peer whose host was
  already destroyed. Three ERROR lines per successful run.
- The container lacked `libfontconfig1`, so Godot logged ten fontconfig
  ERRORs on every invocation. Harmless individually, but a log where
  routine ERRORs are normal is a log where a real one goes unnoticed —
  and `test-load`'s scan reads exactly those logs. Both logs are now
  clean at zero ERROR lines on a passing run, which is what makes the
  scan worth anything.

**Deliberately still open, not silently assumed:** fog of war (D-004's
reveal semantics), combat (Q7), casualties (M1 has no combat, so
`alive` is only ever the full squad size), and per-squad selection in
the client (M3 UI work). Replication uses reliable ENet delivery
throughout; unreliable-with-resend is a refinement M4 can measure.

**Known stub:** `SquadSim.visible_to()` returns every squad. That is
correct for M1 — fog is D-004/M2 — but it means the replicator's
per-client gating is exercised only by unit tests and never by the
running system. Recorded here so the criterion above does not read as
more proven than it is.

**Stub closed, 2026-07-30 (M2).** `SquadSim.visible_to()` is real now:
it returns the player's own squads plus any other squad sitting in a
cell the player's `Vision` field currently covers (`vision.gd`, D-025
part 1) — an O(1) lookup per squad against a per-player coverage stamped
once per recompute, never a per-pair scan. `server.gd`'s `_replicate()`
feeds this into `CurveReplicator.collect_for_client()` every tick, so the
replicator's per-client gating is now exercised by the running system,
not only by unit tests, closing exactly the gap this note flagged.

---

### Audit of this entry, 2026-07-29 — and why it was needed

D-022 was written by the same agent, in the same session, that then built
the code against it. That is exactly the arrangement in which a
definition of done drifts to fit whatever was produced, so it was
re-examined rather than restated. It had drifted, in two specific ways,
and both let real bugs through:

**Criterion 4 asked for the wrong thing.** It required "tests proving
purity and client/server agreement". The tests proved agreement *given
identical inputs* — they passed `def.squad_size` to both sides — and
therefore could not notice that the live client fed `Formation` a
nominal 40-strong "line" while the server used 32-strong "loose". Every
soldier on every client was in the wrong place, and the suite was green.
The criterion should have demanded agreement **in the running system,
with the test taking its inputs from the wire**. See D-006's "necessary
but not sufficient" note.

**Criterion 7 could be satisfied vacuously.** "`test-load` runs clean"
was true while one of its three checks — a grep for the word `desync` —
matched nothing any code path ever printed. A check that cannot fail is
indistinguishable from one that passes. It hid the bug above through
every green run of M1.

Both are now closed. The protocol carries squad composition
(`S2C_SQUAD_INFO`), the server publishes a composition hash
(`S2C_STATE_HASH`) that clients check themselves against, and the bot
verdict fails if that verification did not *happen*, not merely if it
did not complain.

**A further live bug the new check caught on its first run:** squad
composition was sent only to the joining client, so every
already-connected client received curves for the newcomer's squads
without ever being told what they were. The desync check flagged it
immediately — bot 0 knew 12 squads, bot 1 knew 24, bot 2 knew 36 — which
is the clearest possible demonstration that the previous check had been
dead rather than passing.

**Standing rule this produces:** every check added to a test recipe must
be *observed to fail* before it is trusted. Both new checks were
verified by deliberate perturbation, and the log scan itself was fixed
after it failed a good run by matching its own success line ("0
desyncs") — a check that fires on its own good news is no better than
one that never fires.

**Also fixed in the audit:** the sim now rejects a
`curve_lookahead_seconds` that does not exceed the replicator's
`horizon_seconds` (previously a comment, enforced by nothing), and the
server counts and reports simulation ticks discarded by its catch-up
bound instead of silently falling behind wall-clock.

**The GUI client gap is closed too — see D-014's 2026-07-29 amendment.**
`just test-client` renders the real client against a real server using a
software rasteriser, so criterion 4 is now verified visually and not
merely numerically. That distinction earned its keep immediately: the
first frame ever rendered showed **no soldiers at all**, while every
numeric assertion passed — 12 squads drawn, 384 soldiers derived, zero
desyncs. `ClientState` was calling `Formation.soldier_transforms` with no
terrain sampler, so every soldier derived at y=0 and rendered *inside*
the terrain.

That is a D-006 gap, not a cosmetic one: "terrain sample" is the fourth
element of clause 1's input tuple, and it was simply never supplied. It
is now, from the same `TerrainGen` instance that builds the mesh, so the
ground a soldier stands on is the ground that was drawn. When the server
begins deriving soldier positions for combat in M2 it must use an
identical sampler, or the two sides will disagree about who is standing
where.

---

### D-021 · 2026-07-29 · Accepted
**Decision:** **No C# in the shipping build.** GDScript for all gameplay
and simulation code. Where profiling shows a specific kernel exceeding
budget, the escape hatch is **GDExtension (C++/Rust) scoped to that
kernel** — not a project-wide .NET conversion. This narrows D-009's
looser "C# only where profiling shows a specific need" clause; see the
note appended to D-009.

**Rationale:** Q6 framed this as a question about export matrix and
platform support. For this project it largely isn't: shipping is Steam
desktop (D-015 → M7), Godot's .NET builds export to Windows/Linux/macOS,
and there is no web target — the usual platform argument against C# does
not apply here. Dedicated servers (Q3, open) are Linux either way. The
decision therefore rests on toolchain cost and reversibility.

*Toolchain cost is permanent.* The current image is debian-slim plus one
Godot zip. .NET means the Mono/.NET Godot artifact, the .NET SDK in the
image, a NuGet restore, and a compile step gating `test-unit` on top of
the headless-import step D-015 already requires. That is paid on every
container operation from M1 onward, against D-014's explicit premise of
a small footprint and clean teardown.

*Reversibility is asymmetric.* Deciding no now and reversing at M4 costs
the container/export rework — which is the same work whether done now or
then, since existing GDScript keeps working alongside a later `.csproj`.
Deciding yes now pays the toolchain tax continuously across M1–M3 for a
bottleneck that is speculative.

*D-006's confirmation is what makes this tenable.* The strongest argument
for C# is that D-009's packed-array-outside-the-scene-tree design is
ergonomic in C# (structs, spans, generics) and ugly in GDScript (parallel
`PackedFloat32Array`s with hand-rolled index math). That argument was
substantially weakened on 2026-07-28: because soldier positions are
derived rather than stored, the hot data set is ~1,000 squads of state,
not ~40,000 soldiers — a 40x reduction. Manual index math over a thousand
entities is unpleasant but tractable. **Had D-006 been rejected, this
entry would likely have gone the other way.**

**Rejected alternatives:** C# permitted project-wide from the start
(rejected — continuous cost for speculative benefit; the hiring-pool and
static-typing arguments are real but don't outweigh it at this stage).
Leaving D-009's vague "C# if profiling shows a need" as the answer
(rejected — that phrasing can't be acted on when sizing the container or
export matrix, which is precisely why Q6 demanded a yes/no). GPU compute
shader as the general escape hatch for the flow-field solver (rejected as
*unsafe*: the authoritative server is headless and, depending on Q3, may
be CPU-only in a cloud VM — GPU acceleration is available to the client
renderer, not to the server-side solver).

**Explicitly not a reason:** .NET GC pauses. At D-020's 100 ms tick,
gen0 collections are noise and a gen2 pause is poolable. Recorded here so
the argument doesn't get re-raised as though it were load-bearing.

**Consequences:** Container and export stay single-toolchain. D-009's C#
clause is narrowed (note appended there); `CLAUDE.md`'s Conventions
section updated to match. Accept the ergonomic cost of parallel packed
arrays in GDScript for D-009's simulation state. Note that GDExtension is
deferred cost, not free: it brings its own native build matrix
(`.dll`/`.so`/`.dylib` per target), so the escape hatch should be reached
for once, deliberately, on measured evidence.

**Revisit trigger:** M4 profiling identifies a kernel exceeding budget
that GDScript-level optimization cannot close. The flow-field solver
(D-007) under D-003's invalidation-storm conditions is the prime
candidate — a wrap-aware pass over 10,000+ cells (Q8) recomputed for many
squads at once. Reverse to GDExtension for that kernel first; revisit
project-wide C# only if several kernels qualify.

---

### D-020 · 2026-07-28 · Accepted, per-LOD variation Open
**Decision:** Server simulation tick rate is **10 Hz** (100 ms). This is
the rate at which authoritative game state advances. It is explicitly
*not* the same number as either the curve keyframe emission rate (D-003)
or the flow-field recompute rate (D-007), both of which are lower and
independently tunable.

**Rationale:** 10 Hz was already load-bearing in D-018's accepted math
("1,000 squads at a 10 Hz tick is 10,000 squad-updates/second") while
remaining formally undecided — this entry closes that gap rather than
introducing a new number. The rate is defensible on its own terms: at
full scale it leaves ~50 µs per squad-update to consume half of one core,
which is a workable GDScript budget under D-009's packed-array design.

Crucially, D-003 decouples tick rate from *visual* smoothness. Under
snapshot replication 10 Hz would look choppy; under curve-based sync
clients interpolate continuously along a received curve, so tick rate
governs decision and combat-resolution latency, not motion fidelity. The
cost that remains is up to 100 ms of command quantization on top of
network RTT — well inside genre norms, where classic lockstep RTS
deliberately ran 200–500 ms command latency.

**Rejected alternatives:** 20–30 Hz (rejected — doubles or triples the
squad-update budget for latency the genre doesn't need and that D-003
already hides visually); 5 Hz (rejected — halves the cost but pushes
worst-case command quantization to 200 ms and coarsens combat resolution
to 200 ms rounds, which starts to constrain Q7's design space).

**Consequences:** Per-squad update cost should be measured against a
100 ms tick budget from M1 onward, per D-012's "keep it measurable and
swappable." Combat resolution (Q7) has a 100 ms minimum round
granularity. Do not conflate this number with network send rate — an
idle squad still costs zero bandwidth per D-003 regardless of tick rate,
and that property must survive M1's implementation.

**Revisit trigger:** M1/M4 profiling showing squad-update cost exceeding
the 100 ms budget at D-018's counts — per D-018's own revisit trigger,
tick rate is the dial to consider before the architecture. Whether the
tick rate itself varies by LOD tier remains **open** and is deferred to
M5 with the rest of D-012.

---

### D-018 · 2026-07-28 · Accepted
**Decision:** Full-scale target is 20 players × 2,000 individual soldiers
each (40,000 soldiers total), organized into ~50 squads/player (~1,000
squads total at full scale), implying an average squad size of ~40
soldiers.

**Rationale:** Dave's explicit call, replacing the ambiguous "500 units"
figure in the original brief (see former Q1, now resolved). This reading
(soldiers, not Total-War-style multi-soldier "units") keeps the
squad-atomic architecture's math tractable: 1,000 squads at a 10 Hz tick
is 10,000 squad-updates/second, roughly 4x the number modeled in the
original MVP planning pass but still within GDScript's budget assuming
D-006 holds.

**Rejected alternatives:** 500 soldiers/player (original brief, too
small to be interesting per Dave); 500 Total-War-style units/player
(~20,000 soldiers/player, ~400,000 total — an order of magnitude beyond
what's viable for this project's team size and hardware).

**Consequences:** Every downstream budget in `CLAUDE.md` and this file
(bandwidth, tick cost, MultiMesh instance counts, load-test bot shape)
should be sized against 1,000 squads / 40,000 soldiers at full scale, not
the original 250/10,000. MVP (M3) squad count per player stays modest
(~12-15) — full-scale squad density is a v1.0 target, not an MVP one.

**Revisit trigger:** If M1/M4 profiling shows squad-update cost exceeding
budget at this count, revisit either the squad-count target or the tick
rate before touching the architecture.

---

### D-019 · 2026-07-28 · Accepted
**Decision:** The "Rome Total War" half of the hybrid means **formations
and morale/routing only** — units fight and break in formation, morale
determines when a squad routs. No separate turn-based or persistent
campaign layer wrapping the RTS battles.

**Rationale:** Dave's explicit call (former Q2, now resolved). This
confirms squads are the right atomic simulation unit for a reason beyond
performance: formations and morale are inherently squad-level concepts,
not per-soldier ones.

**Rejected alternatives:** Campaign layer wrapping battles (Total War's
actual structure) — rejected as out of scope entirely, not just deferred;
"Total War" as aesthetic/scale reference only, no formal
formation/morale system — rejected, Dave wants the mechanics, not just
the vibe.

**Consequences:** Combat model (former Q7, still open) must define
formation shapes per squad, a morale stat and rout trigger/threshold, and
how routing interacts with flow-field movement (a routed squad presumably
gets a new, player-uncontrolled flow-field target). This also firms up
`unit_def.gd`'s schema: it needs formation-shape and morale-stat fields
from the start, not bolted on later.

**Revisit trigger:** None — this is a firm scope boundary, not a
provisional call.

---

### D-006 · 2026-07-28 · Accepted (confirmed 2026-07-28 — see confirmation block below)
**Decision:** Individual soldier positions are a pure client-side
function of (squad curve, formation shape, slot index, terrain sample)
and are never networked. Only squads are networked entities. Combat
outcomes (damage, death, routing) replicate as sparse reliable events,
not continuous per-soldier state.

**Rationale:** This is the keystone that makes D-018's 1,000-squad
full-scale target tractable at all — it's what keeps the networking and
simulation cost at "squads" (~1,000) rather than "soldiers" (~40,000), a
40x difference. It also composes cleanly with D-019: formation shape is
exactly the function that would derive soldier slot positions.

**Rejected alternatives:** Per-soldier authoritative networked
positions — rejected provisionally, as it multiplies the netcode budget
by ~40x and wasn't shown to be necessary for anything in scope.

**Consequences:** Combat resolution cannot depend on true per-soldier
positions being known to the server at high precision — it has to work
off squad-level state plus a formation model. This needs explicit
confirmation before M1's flow-field/curve-sync proof is built, because
M1's exit criteria assume it.

**Revisit trigger:** If the combat model (informed by D-019) turns out to
require server-authoritative per-soldier positions — e.g., for precise
morale/rout triggers based on individual soldier deaths in specific
formation slots — revisit before M2.

**Confirmed 2026-07-28.** Promoted Provisional → Accepted, with the scope
sharpened. The original entry bundled two separable claims: that soldier
positions are never *networked* (a bandwidth claim) and that they are
never *server-authoritative state* (a simulation-cost claim). Only the
first is load-bearing, and it does not depend on the second — if a
soldier's position is a pure function of replicated squad state, the
server may compute it whenever combat needs it and still send nothing.
Server and client agree by construction rather than by synchronization.

Three clauses, now binding:

1. **Purity.** A soldier's position is a pure function of (squad curve,
   formation shape, slot index, terrain sample). No per-soldier
   integration state — no velocity, no accumulated offset, no history
   carried across ticks.
2. **Cosmetic offsets are one-way.** Client-side visual offsets (idle
   sway, footfall jitter, terrain settling) are permitted and are never
   read back by simulation. This is where visual life comes from without
   touching the keystone.
3. **Casualty slot reassignment is deterministic**, derived from the
   ordered death-event log — which is already replicated as sparse
   reliable events, so reassignment stays inside the purity boundary.
   The formation restamps; soldiers do not walk to fill a dead man's
   slot.

**Clause 1 is necessary but not sufficient — added 2026-07-29.** Purity
guarantees client and server agree *given identical inputs*. It says
nothing about whether the system actually hands them identical inputs,
and that turned out to be the gap that mattered.

M1 shipped with the server spawning the roster's default unit (32-strong
archers in "loose" order) while every client assumed a nominal 40-strong
"line". Because `Formation.slot_offset` takes `alive` as an input, this
did not merely draw eight phantom soldiers — it put *every* soldier
somewhere the server had not. The formation function was flawlessly pure
throughout. The tests proved that purity and passed, because they handed
both sides `def.squad_size` themselves.

So: **supplying both sides identical inputs is a protocol obligation**,
and it belongs to whatever message carries squad composition (see
`NetProtocol.encode_squad_info`). A test that supplies the inputs itself
verifies the function, not the system. Any future test claiming
client/server agreement must take its inputs from the wire.

**Corrected revisit trigger** (replaces the original above, which was
miswritten): the trigger is *not* "combat needs server-authoritative
per-soldier positions" — under clause 1 that is free. The trigger is
**emergent per-soldier movement**: local avoidance, collision push-back,
soldiers physically jostling, neighbors pathing into a vacated slot. Any
of those gives a soldier its own integration state and breaks clause 1,
at which point the only options are networking ~40,000 entities or
accepting divergence. Revisit before M2 if the combat model wants one.

**Consequence for Q7.** This constrains the still-open combat model
rather than waiting on it. Q7 must resolve to something expressible
within clause 1: squad-level stochastic resolution satisfies it
trivially; deterministic per-soldier resolution satisfies it only if
resolution *reads* derived positions without perturbing them; per-soldier
resolution that physically moves soldiers as a result of combat does not
satisfy it and trips the corrected trigger above.

---

### D-001 · 2026-07-28 · Accepted
**Decision:** Godot 4.7.1 (stable), pinned via `.godot-version`.

**Rationale:** Latest stable release as of 2026-07-28 (released
2026-07-14). Chosen for plain-text asset formats (`.tscn`/`.tres`) that
make the project directly editable by Claude Code.

**Rejected alternatives:** Godot 4.6.3 (prior stable branch) — no
compelling reason to pin behind latest stable for a greenfield project.

**Consequences:** Container image and portable native binary must both
resolve to this exact version. Bump this entry (don't silently update)
if a newer stable release becomes worth adopting.

**Revisit trigger:** A newer stable release ships with a fix or feature
this project specifically needs (e.g. `MultiMesh` improvements relevant
to D-009).

---

### D-002 · 2026-07-28 · Accepted
**Decision:** Client-server, authoritative server. Not lockstep.

**Rationale:** Lockstep desync debugging cost, 20-player join/rejoin
handling, and cheat resistance all favor authoritative server + client
interpolation over lockstep, despite lockstep being the historical RTS
default.

**Rejected alternatives:** Lockstep simulation (classic RTS netcode).

**Consequences:** Server needs enough CPU to simulate the full match
(see former Q3, still open — server hosting model). Clients send input,
receive curve-based state (D-003), interpolate locally.

**Revisit trigger:** None currently.

---

### D-003 · 2026-07-28 · Accepted
**Decision:** Object state (position, build progress, etc.) syncs as
keyframed curves, not per-tick snapshots. Curves are mandatorily clipped
to each client's visibility horizon and a bounded time window before
transmission.

**Rationale:** Near-zero bandwidth for idle objects. The clipping
requirement prevents two specific failure modes: intent leakage (a raw
curve reveals an enemy squad's future path before it happens) and
unbounded lookahead cost.

**Rejected alternatives:** Per-tick snapshot replication (simpler, but
scales linearly with object count and tick rate — incompatible with the
zero-cost-when-idle goal).

**Consequences:** Curve invalidation (re-pathing, especially many squads
at once, e.g. a large engagement) is a bandwidth spike risk and needs a
budgeted/prioritized update scheduler, not naive immediate replication.
This should be measured explicitly in M1's exit criteria.

**Revisit trigger:** If M1 profiling shows invalidation-storm bandwidth
exceeding budget, revisit the scheduler design (not the curve-based
approach itself).

---

### D-004 · 2026-07-28 · Accepted (semantics closed 2026-07-30 by D-025)
**Decision:** Fog of war is implemented as curve gating on top of D-003
— a client simply doesn't receive curves for objects outside its
vision — not a separate data-hiding system.

**Rationale:** Avoids building and maintaining two parallel
visibility-gating mechanisms.

**Rejected alternatives:** Separate fog-of-war system layered on top of
full replication with client-side hiding (rejected — leaks true state to
a modified client, defeats the purpose of fog of war).

**Consequences:** Reveal/conceal semantics are not yet decided: does a
unit entering vision pop in at its true position, receive a short
synthetic catch-up curve, or does the client keep a stale "ghost" at
last-known position after it leaves vision? All three are legitimate;
needs an explicit pick before M2 (fog of war milestone).

**Revisit trigger:** Pick reveal/conceal semantics before M2 begins;
this entry stays Provisional until then.

**Semantics picked 2026-07-30 — see D-025.** True-position pop-in on
reveal, stale announced ghost on conceal, and vision computed as a
per-player field rather than per-pair tests. This entry is no longer
Provisional. The one part of D-025 that is not merely a choice among the
three options listed above: conceal has to be an **explicit event**, or
the composition hash compares different sets on the two sides and the
desync check fires on a healthy system.

---

### D-005 · 2026-07-28 · Accepted
**Decision:** Squads, not individual soldiers, are the atomic unit for
movement, pathfinding, production, and networking.

**Rationale:** Matches D-019's formation/morale mechanics (which are
inherently squad-level) and is what makes D-018's full-scale target
tractable via D-006.

**Rejected alternatives:** Per-soldier pathfinding/production (rejected —
doesn't scale to 40,000 soldiers and fights D-019's formation model).

**Consequences:** Don't reintroduce per-unit pathfinding or per-unit
production queues anywhere in the codebase.

**Revisit trigger:** None currently.

---

### D-007 · 2026-07-28 · Accepted
**Decision:** Flow-field pathfinding, computed per squad destination, not
per-soldier A*.

**Rationale:** Well-trodden technique (Supreme Commander 2, Planetary
Annihilation) that composes with squad-atomic movement (D-005) and scales
far better than per-agent A* at this unit count.

**Rejected alternatives:** Per-soldier A* (rejected — doesn't scale;
also redundant given D-006's derived soldier positions).

**Consequences:** None beyond standard flow-field implementation cost.

**Revisit trigger:** None currently.

---

### D-008 · 2026-07-28 · Accepted
**Decision:** Wrapped hex grid on a torus, using axial coordinates on a
parallelogram domain with row-parity constraints on map dimensions.
Wrap-awareness is enforced via a `HexCoord`/`TorusSpace` type rather than
left as a convention every call site has to remember.

**Rationale:** A true geodesic sphere is unnecessary complexity for the
stated design; a naive offset-coordinate rectangular grid does not wrap
cleanly without careful row-parity handling. Making wrap a type-level
concern prevents the "twentieth call site forgets ghost-copy distance"
class of bug.

**Rejected alternatives:** True geodesic sphere (rejected — much more
complex, not needed); offset-coordinate grid with wrap handled by
convention (rejected — proven bug-prone pattern, error-prone at scale).

**Consequences:** Every distance/neighbor/noise calculation
(pathfinding, vision, minimap, camera, drag-select, formation math, AI
targeting, terrain noise) must go through the wrap-aware type. Seam-
crossing cases must be in GUT tests from M1 onward.

**Revisit trigger:** None currently.

---

### D-009 · 2026-07-28 · Accepted
**Decision:** GDScript for gameplay logic at squad granularity. Rendering
via `MultiMesh`, with simulation state kept in packed arrays outside the
Godot scene tree — not one `Node` per soldier or per squad. C# only where
profiling shows a specific need.

**Rationale:** Godot's `Node`/scene-tree model is not designed for tens
of thousands of dynamic actors; the idiomatic "one scene instance per
unit" approach fails well before D-018's target. `MultiMesh` + packed
arrays is the path that actually scales, but it cuts against Godot's
default idiom and needs to be an explicit decision so early
implementation doesn't default to per-soldier scene instances.

**Rejected alternatives:** One `Node`/scene instance per soldier
(rejected — doesn't scale); one `Node` per squad (reconsider only if
squad count, not soldier count, turns out to be the bottleneck).

**Consequences:** Unit rendering code should be written against
`MultiMesh` from `primitive_unit.gd` onward, not retrofitted later.

**Revisit trigger:** If profiling shows packed-array simulation state is
itself the bottleneck (unlikely before M4).

**Narrowed 2026-07-29 by D-021.** The "C# only where profiling shows a
specific need" clause above is superseded: C# is **not** permitted in the
shipping build at all. The escape hatch for a kernel that exceeds budget
is GDExtension (C++/Rust) scoped to that kernel. The rest of this entry —
GDScript at squad granularity, `MultiMesh` rendering, packed arrays
outside the scene tree — stands unchanged. See D-021 for the reasoning,
including why D-006's confirmation is what makes GDScript tenable for the
packed-array design.

---

### D-010 · 2026-07-28 · Accepted
**Decision:** Unit stats live in `/units/*.tres` against the `UnitDef`
schema (`unit_def.gd`). Schema changes are versioned and recorded here,
not just in the code.

**Rationale:** Data-driven units are what makes the project directly
editable via Claude Code rather than requiring the Godot editor GUI, per
`CLAUDE.md`'s core premise. `UnitDef` now needs formation-shape and
morale-stat fields per D-019 from the start.

**Rejected alternatives:** Hardcoded per-unit-type script subclasses
(rejected — defeats the data-driven goal).

**Consequences:** New units are added by adding a `.tres` file, not by
writing new unit classes. Squad size (~40 soldiers per D-018) is a
`UnitDef` field, not a global constant, so it can vary per unit type if
needed later.

**Revisit trigger:** None currently.

**Schema log** (this entry requires schema changes be recorded here, not
just in code):

- **2026-07-29, M1 — added `formation_spacing: float = 1.0`.** Formation
  geometry (D-006/D-019) needs a per-unit centre-to-centre spacing;
  cavalry and skirmishers do not occupy the footprint of line infantry.
  Existing `.tres` files pick up the default, so this is backward
  compatible.

- **2026-07-30, M2 — added `vision_range: float = 12.0`,
  `morale_recovery_per_second: float = 2.0`, `rout_rally_margin: float =
  15.0`, `morale_loss_per_casualty: float = 4.0`, `damage_variance: float
  = 0.25`.** D-024's combat model and D-019's morale/routing need these
  as per-unit tuning rather than script constants; `vision_range` is
  D-025's vision-field radius, added here (combat's file) rather than by
  the fog worker so `unit_def.gd` only gets one schema-touching editor
  per unit. All five are additive with defaults; existing `.tres` files
  pick them up unchanged.

- **2026-07-30, M3 — added `armour_class: String = "infantry"` and
  `bonus_vs: Dictionary = {}`.** D-032's counters. `armour_class` is what
  a unit *is* for targeting; `bonus_vs` maps an opponent's armour class
  to a damage multiplier, so the counter table is data and adding a
  counter never means editing `combat.gd`. A missing entry means 1.0, so
  a generalist unit needs no special-casing and both existing `.tres`
  files stayed valid. Shipped alongside two new units — `spearmen.tres`
  and `cavalry.tres` — completing D-015's 3-4 unit cut line with a real
  triangle: spears counter cavalry, cavalry counter missile, missile
  counters infantry.

- **2026-08-02, M6 — added `damage_vs_buildings: float = 0.15`.**
  *Logged retroactively on 2026-08-04.* D-056 introduced this field and
  called it "a schema addition against D-010", but never recorded it
  here, which is the omission this log exists to prevent. Defaults to the
  SAFE end deliberately: an unaware `.tres` is conservative rather than
  catastrophic, unlike `bonus_vs`, whose missing-key default of 1.0 is
  right for a counter table and would have been exactly wrong here. See
  D-056 for the full reasoning.

- **PROPOSED, not implemented — the M9 epoch schema (D-070).** Recorded
  here so the specification has one home, and marked clearly because
  **none of it exists in code**. The age/tech planning milestone was
  documents-only; anything reading this log as a description of the repo
  would be misled.

  | Field | Type | Default | Purpose |
  |---|---|---|---|
  | `UnitDef.epoch` | `int` | `1` | earliest epoch this unit may be produced |
  | `UnitDef.upkeep_food` | `float` | `0.0` | per soldier per second (D-068) |
  | `BuildingDef.epoch` | `int` | `1` | earliest epoch this building may be founded |
  | `CivDef.upkeep_modifier` | `float` | `1.0` | D-068 |
  | `CivDef.epoch_advance_speed` | `float` | `1.0` | who climbs faster |
  | `CivDef.build_speed` | `float` | `1.0` | D-073's parameterisation pass found no build-speed knob exists at all |
  | `CivDef.epoch_names` | `Array[String]` | `[]` | five display strings, flavour only |

  Plus a new resource type, `EpochDef`, in `/epochs/*.tres` — index,
  display name, `cost_*`, `research_time`, prerequisite building ids —
  so the ladder itself is editable text and no script names a rung.

  Every default is chosen so an unaware `.tres` is epoch-1, upkeep-free
  and valid, following the same safe-default reasoning as
  `damage_vs_buildings` above.

---

### D-011 · 2026-07-28 · Superseded by D-081 (2026-08-09)
**Decision:** Mesh generation stays at the primitive tier (capsules,
boxes, cylinders composed from `UnitDef` data) through M3. Modular/
parametric (tier 2) and Blender/`bpy` final-fidelity (tier 3) are
unscheduled.

**Rationale:** Zero art dependency lets the architecture and gameplay
loop get validated before any art investment. Matches `CLAUDE.md`'s
existing tiering.

**Rejected alternatives:** Jumping to higher mesh fidelity early
(rejected — art investment before the architecture is proven is the
highest-waste failure mode for a project this size).

**Consequences:** `primitive_unit.gd` is the only mesh-generation code
needed through M3.

**Revisit trigger:** Revisit once M3 is complete and playtesting
suggests visual fidelity is limiting engagement, or once tiers 2/3 are
explicitly prioritized.

**Trigger fired 2026-08-09, on both halves** — M3 completed three
milestones ago and the owner prioritised tiers 2/3 explicitly. Superseded
by D-081 (first recorded here as `D-064`, then briefly as `D-075` — both
IDs collided with unrelated real entries; corrected 2026-08-11, see
D-081's editorial note), which sets the art direction and makes the
generator, rather than the mesh, the thing that is committed.

---

### D-012 · 2026-07-28 · Provisional
**Decision:** LOD is deferred to M5, implemented only for the tiers M4's
profiling shows are actually necessary. When built: **simulation** LOD is
keyed to server-computed game-state salience (in combat / near enemy /
near contested objective) and is identical for all observers — never
keyed to any individual client's camera. **Render** LOD may be keyed to
camera freely.

**Rationale:** Building LOD before M4 means building a complex,
fairness-sensitive system against guessed numbers instead of measured
ones. Keying simulation fidelity to an individual client's camera would
make combat outcomes depend on spectator behavior — a competitive-
fairness bug, not just a technical one. `CLAUDE.md`'s "LOD is planned,
not a fallback" is about keeping per-squad update cost measurable and
swappable from the start, not a mandate to build LOD first.

**Rejected alternatives:** Camera-keyed simulation LOD (rejected —
fairness bug); building full LOD before M4 (rejected — no measured data
to size it against).

**Consequences:** Per-squad update cost should be kept measurable and
swappable from M1 onward even though LOD itself isn't built until M5.

**Revisit trigger:** M4's profiling data determines which LOD tiers (if
any) are actually needed.

**Resolved 2026-08-02 (M5), both halves, on measurement.**

**Simulation LOD: not needed, and not built.** D-040 brought the worst
tick to 73.4 ms at D-018's full 1,000 squads, inside D-020's 100 ms with
~27% headroom, and the average to 33 ms. This entry's own rule is that
LOD is implemented "only for the tiers M4's profiling shows are actually
necessary"; on the simulation side that is none. Building it anyway would
have meant a complex, fairness-sensitive system — the one whose failure
mode is combat outcomes depending on where somebody was looking — against
a budget already met.

*Revisit trigger:* the tick budget being exceeded at full scale, or
D-018's player/squad counts being revised upward. Not "it feels slow" —
`just profile` reports the worst tick, and that is the number.

**Render LOD: needed, built, and camera-keyed** — see D-045. The client
was at 10.6 fps drawing 1,000 squads and is at 28.0 after culling,
memoising terrain and thinning distant squads, with 500 squads at ~57
fps. The camera-keying that would be a fairness bug in simulation is
safe here for the reason this entry gives: it cannot affect an outcome,
and a test proves the reduced path never changes `alive` or the
composition hash.

**Q9's remainder is answered: tick rate does NOT vary by LOD tier.**
There are no simulation LOD tiers for it to vary across. If simulation
LOD is ever built, per-tier tick rate becomes a live question again and
must be answered then rather than assumed — but it is no longer an open
item hanging over the ladder.

---

### D-013 · 2026-07-28 · Accepted
**Decision:** Global time dilation (PA-style slowdown) is an emergency
safety valve only, with a written trigger threshold once defined — never
the primary mechanism for handling scale.

**Rationale:** Matches `CLAUDE.md`'s existing non-negotiable. LOD (D-012)
and curve-based sync (D-003) are the primary scale mechanisms; time
dilation is a last-resort fallback for when those aren't enough in a
specific match.

**Rejected alternatives:** Time dilation as a routine scale-management
tool (rejected — degrades the play experience broadly instead of
targeting the actual cost).

**Consequences:** None yet — unscheduled until M5 or later.

**Revisit trigger:** Define the exact trigger threshold when this is
first implemented, not before.

---

### D-014 · 2026-07-28 · Accepted
*(Amended 2026-08-11 by **D-075**: the teardown scoping below is now
per INSTANCE rather than per the single pinned `edotmw` project. That
tightens this decision — `just down` could previously remove containers
started by a different checkout of this same project, which is teardown
reaching further than its own work.)*

**Decision:** Headless dev tooling (server, bots, GUT tests, terrain
preview) is containerized. The GUI Godot editor and the GUI game client
run natively via a portable, gitignored install — flagged as `CLAUDE.md`
exceptions, not eliminated. `EDOTMW_RUNTIME=native|docker` lets the
`justfile` recipes run against either backend, since WSL2 is currently
broken on the dev machine and Docker Desktop depends on it.

**Rationale:** Dave wants easy, complete teardown — no stray processes,
containers, or installed toolchains left on the machine. GPU-accelerated
GUI Godot in a container on Windows (via WSLg/X-forwarding) is slow and
fragile, and pointless given the dev machine's integrated Iris Xe GPU
anyway. The native-fallback runtime abstraction means M0 isn't blocked on
fixing WSL2.

**Rejected alternatives:** Containerizing the GUI client (rejected —
fragile, no GPU benefit on this hardware); requiring WSL2 fixed before
any dev work starts (rejected — unnecessarily blocks M0).

**Consequences:** `justfile` recipes are the stable interface; only the
backend invocation differs by `EDOTMW_RUNTIME`. Teardown for the native
path is `rm -rf tools/` (portable binaries) plus clearing
`%APPDATA%\Godot` if needed; for the docker path it's `just nuke`
(remove containers, image, `tools/`, `artifacts/`).

**Revisit trigger:** Once WSL2 is repaired and the docker path is
verified working, `EDOTMW_RUNTIME=docker` can become the default; native
stays as the fallback either way for the GUI pieces.

**Amended 2026-07-29 — automated GUI testing, without a GPU.** This entry
rejected containerising the GUI client, and that judgement stands *for
interactive development*: GPU passthrough into a container on this
hardware is fragile and buys nothing. `just run-client` is still native.

But the rejection was overly broad, and it left M1's client with no
automated verification at all — it had never rendered a frame anywhere.
The gap was never really about GPUs: **rendering does not require a GPU,
it requires a rasteriser.** Mesa's llvmpipe renders Godot's Compatibility
(OpenGL) backend entirely in software, under a virtual X server, in a
plain container. Verified here at OpenGL 4.5 core against Godot's 3.3
requirement.

So `just test-client` renders the real client scene against a real
server, screenshots it, and asserts on the result. Nothing is installed
on the host and no GPU is involved. Teardown is unchanged: the X server
dies with its container, and `just nuke` removes the image.

Software rendering is a feature here rather than a compromise — output
does not vary by driver vendor or version, so frames are comparable run
to run. What it deliberately does **not** cover is real-GPU appearance
and performance, which stay a human judgement made via `just run-client`.

Two traps this laid, both worth knowing:

1. The `gui` stage extends `base` and is therefore *last*, and Docker
   builds the last stage by default — so a bare `build: .` silently gave
   the **server** an X server and an OpenGL context instead of running it
   headless. Every headless service now pins `target: base` explicitly.
   Caught by the tightened log scan on its first run after the change.
2. Godot defaults to Forward+/Vulkan. The image ships software *OpenGL*,
   not software Vulkan, so the client hung at startup emitting no
   diagnostic whatsoever until `--rendering-method gl_compatibility` was
   passed.

**And it exposed a pre-existing hole in this entry's own guarantee.**
`docker compose down` removes what `compose up` created; it does **not**
reliably remove a still-running one-off `compose run` container, and
`--remove-orphans` does not either. A client-test container that hung at
startup survived a full `just nuke` and was still running half an hour
later — the exact stray-container failure this decision exists to
prevent, sitting undetected because nothing ever checked. `just down`
now also sweeps by `com.docker.compose.project=edotmw` label, which is
scoped to this project exactly as the pinned `-p edotmw` is and cannot
touch anything else. Verified: run `test-client`, then `nuke`, then
confirm zero containers and zero images remain.

The lesson generalises past Docker: **the teardown guarantee needs its
own check.** It was asserted in this entry from M0 onward and was, for
some paths, simply not true.

**Update 2026-07-28:** WSL2 repaired (firmware virtualization was
disabled — fixed in BIOS) and Docker Desktop installed. Docker path
verified end-to-end: `docker compose build server` succeeds (fetches
pinned Godot 4.7.1 inside the image per D-001), and
`docker compose run --rm bots -- --clients=3` runs `bot_client.gd`
through the full bind-mount + entrypoint chain correctly.
`docker compose down --remove-orphans` tears down cleanly. Trigger met
— `EDOTMW_RUNTIME` default switched to `docker` in the justfile; native
remains the fallback for the GUI editor/client (unaffected by this
change).

---

### D-015 · 2026-07-28 · Accepted (pending Dave's review of concrete M3 file output)
**Decision:** Milestone ladder M0 (skeleton) → M1 (movement + netcode
proof) → M2 (combat + fog) → M3 (launchable MVP) → M4 (scale-out
profiling) → M5 (LOD) → M6 (second civ) → M7 (Steam). M3's cut lines: 4
players, ~120-150 soldiers/player at ~12-15 squads/player (squad count
per player stays a small fraction of D-018's full-scale ~50/player — see
D-018 consequences), 1 civilization, fixed torus map, 3-4 unit types,
primitive meshes only, no simulation LOD, LAN/direct-IP only, no AI
opponent, replays included (near-free given D-003).

**Rationale:** Full derivation and per-milestone exit criteria are in the
2026-07-28 planning session (see project history / commit that adds
this file). Deliberately shrinks nearly every dial except squads/player,
since squad count is the axis the architecture is actually sensitive to.

**Rejected alternatives:** Scaling every dial down proportionally
(rejected — would hollow out the validation of the squad-atomic
architecture, the thing M1-M3 exist to prove).

**Consequences:** M0 deliverables (this commit and the files alongside
it) should make `CLAUDE.md` actually true: real `justfile` recipes,
real directory layout, this decision log, and container/native
scaffolding.

**Revisit trigger:** Re-derive squad/soldier counts if D-018 changes.

**Update 2026-07-28:** M0 exit criteria verified and met: `just
test-unit` runs GUT 9.6.1 headless via `docker compose run --rm test`
(2/2 smoke tests pass, including a `UnitDef` default-value check), and
`just nuke` confirmed to remove all containers/images plus
`tools/`/`artifacts/`/`.godot`/`.godot-container`, leaving the repo as
pure source. One operational note for M1: Godot's headless import step
(`godot --headless --path . --import`) must run before `gut_cmdln.gd`
can resolve GUT's and the project's own global `class_name`s (`UnitDef`,
`PrimitiveUnit`) — baked into the `test-unit` recipe now, keep this in
mind for any other headless recipe (`run-server`, `gen-terrain-preview`)
implemented in M1.

**Post-M0 review 2026-07-28.** A review pass over the M0 deliverables
found and fixed four real defects, all of which would have surfaced as
confusing failures during M1:

1. `bootstrap` only printed instructions, so the stated exit criterion
   ("fresh clone + bootstrap + `just test-unit` works") did not actually
   hold — and could not, since a fresh clone has no `just` to run
   `just bootstrap` with. Resolved by adding `bootstrap.ps1` (fetches
   pinned `just` into `tools/`) and making `just bootstrap` really fetch
   portable Godot for the native runtime.
2. Recipes invoked each other as a bare `just`, which is never on PATH
   (it lives in `tools/`). Broke `default` and every step of
   `test-load`. Now `{{just_executable()}}` — **and it must be quoted**:
   unquoted, bash eats the Windows path's backslashes and the command
   silently becomes `C:Usersdmaso...`. Worth remembering for any future
   recipe that interpolates a path on Windows.
3. `test-load` ran the bots in the foreground and only then slept, so
   `DURATION` measured nothing. Bots now run in the background for the
   requested duration, and teardown is trapped on `EXIT INT TERM` so an
   interrupted load test cannot leave containers running.
4. Nothing exercised the `.tres` files or `primitive_unit.gd` — the
   suite would have stayed green with a completely broken unit roster,
   despite D-010 being the premise the project rests on. `test_unit_defs.gd`
   now loads and schema-checks every `.tres` in `/units/` and asserts a
   squad renders as exactly one `MultiMesh` child (D-009). Verified to
   fail correctly by introducing a deliberately malformed unit.

Also noted, deliberately left as-is: `just nuke` deletes `tools/`
including the running `just` binary. That is correct behavior for
D-014's teardown guarantee; it's now documented rather than surprising.

---

### D-016 · 2026-07-28 · Accepted
**Decision:** Replays are the curve log from D-003 — adopted from M1
onward as the primary desync-forensics tool.

**Rationale:** D-003 makes curve logging nearly free, and replay capture
is valuable for debugging netcode/desync issues from the very first
milestone rather than being bolted on later.

**Rejected alternatives:** Building a separate replay-recording system
(rejected — redundant given D-003).

**Consequences:** None beyond ensuring curve logs are written to
`artifacts/` in a replayable format from M1.

**Revisit trigger:** None currently.

---

### D-017 · 2026-07-28 · Accepted, chunk size Open
**Decision:** Terrain uses a chunked hex mesh (not one mesh per cell) with
biome coloring and elevation vertex offset. Chunk size is determined by
profiling, not chosen upfront.

**Rationale:** One-mesh-per-cell is a known performance problem at
10,000+ cell map sizes (per `CLAUDE.md`); chunking is a hard requirement,
not a style choice. Chunk size has real tradeoffs (rebuild cost on
elevation edits vs. draw-call count) that are better measured than
guessed.

**Rejected alternatives:** One mesh per cell (rejected — doesn't scale);
picking a chunk size upfront without profiling (rejected — premature).

**Consequences:** `gen-terrain-preview` tooling should make chunk-size
experimentation fast.

**Revisit trigger:** Pick a concrete chunk size once M1's terrain work
starts and can be profiled.

**Amended 2026-08-10 by D-067.** Chunking is unchanged — still one mesh per
chunk, still 7 vertices and 6 triangles per cell, and the count tests here
still hold. What changed is only what those vertices DO: a cell's corners now
take the mean height of the three cells meeting at each one, so the ground is a
continuous surface rather than a field of plateaus. Chunk size remains open.

---

## 2. Open Questions / Not Yet Decided

Ordered by how much they block. ~~Struck through~~ entries are resolved
and now live as decisions above.

**Resolved this session:**
- ~~Q1 — What does "500 units" mean?~~ → D-018 (2,000 soldiers/player,
  ~50 squads/player, ~40 soldiers/squad)
- ~~Q2 — What is the Rome Total War half of the hybrid?~~ → D-019
  (formations & morale/routing only, no campaign layer)
- ~~Q9 — Simulation tick rate?~~ → D-020 (10 Hz; per-LOD-tier variation
  still open, deferred to M5 with D-012)
- ~~Q6 — C# in the shipping build?~~ → D-021 (no; GDExtension per-kernel
  is the escape hatch, and D-009's C# clause is narrowed accordingly)

**Blocking M1:**
- ~~D-006 confirmation~~ → confirmed 2026-07-28. The
  derived-soldier-positions keystone is Accepted, scoped by the purity /
  one-way-cosmetic-offset / deterministic-reassignment clauses in D-006's
  confirmation block. No longer blocks M1.
- ~~Q6 — C# in the shipping build?~~ → D-021 (no). Note for the record
  that the premise of this question — that it turns on export matrix and
  platform support — did not survive examination; it turned on toolchain
  cost and reversibility instead. **Nothing now blocks M1 on the
  decision side.**

**Blocking M2:**
- ~~Q7 — Combat model~~ → D-024 (2026-07-30): squad-level stochastic
  resolution, server-only, casualties as integer decrements to `alive`.
  The shape question is closed; per-unit tuning *values* are ordinary
  data work under D-010, not an open decision. Note what settled it —
  `alive` is the only formation input a death changes, so D-006 clause
  3's deterministic reassignment holds by construction and no
  per-soldier identity is needed anywhere.
- ~~Q9 — Simulation tick rate~~ → D-020 (10 Hz). The remainder — whether
  the tick rate **varies by LOD tier** — is still open and deferred to
  M5 with D-012, so it no longer blocks M2.
- ~~Fog reveal/conceal semantics~~ → D-025 (2026-07-30): true-position
  pop-in, announced stale ghost, per-player vision field. D-004 is no
  longer Provisional. **Nothing now blocks M2 on the decision side**;
  M2's exit criteria are D-026.

**Still open within M2's scope, deliberately deferred:**
- **Terrain-occluded line of sight.** D-025 makes vision radius-only;
  elevation does not occlude. Deferred rather than forgotten — it needs a
  height field the simulation does not carry yet, and it extends D-025's
  vision field rather than replacing it.
- ~~**Rally vs. permanent rout.**~~ → resolved 2026-07-30 as **rally with
  hysteresis**, which is what M2 already implements. D-024 said this call
  was best made against something playable; M3 is that thing, so the
  decision is to keep the implemented behaviour and revisit after the
  first real playtest rather than change it unplayed. D-024 no longer
  carries an open item.

**Raised by M2's review, 2026-07-30 — logged rather than fixed:**
- ~~**Simultaneous vs. sequential combat resolution.**~~ → **resolved
  2026-07-30 (M3): the round is now simultaneous.** Every attack reads
  strength and rout state from a snapshot taken at the start of the
  round, so squad id no longer decides mirror engagements. Two tests
  guard it, and perturbing the change back to live state makes them fail
  by exactly one soldier (13 vs 12) — the first-strike advantage, made
  visible. Original finding follows, kept for the trail. `Combat.resolve()`
  iterates attackers in squad-id order and applies damage immediately, so
  a lower-id squad kills part of its enemy *before* that enemy fires, and
  the enemy then attacks at reduced strength. It is deterministic, so
  replays are unaffected — but it is not neutral: identical unit types
  share an `attack_interval` and both start at `_last_attack_tick = -1`,
  so they fire on the same ticks indefinitely and the bias never averages
  out. Squads are spawned in join order, so **player 1 systematically
  wins mirror engagements.** Resolving from the round-start snapshot
  (`before_alive`, already taken) would make the round simultaneous. Left
  open because simultaneous-vs-sequential changes battle outcomes and
  therefore wants a D-024 amendment, not a silent patch.
- **Squads render off the map at the seam.** M2's `test-client` frame
  shows a squad drawn below the terrain's bottom edge, outside the
  meshed domain. `StateCurve` stores continuous *unwrapped* axial space
  by design (read its header), so a squad mid-seam-crossing samples to a
  position outside `[0, width) × [0, height)` while the terrain is meshed
  once. Client-side rendering only — the simulation wraps correctly, and
  no D-026 criterion covers it. Invisible until M2 because M1's frame had
  12 squads in one lane and none crossed a seam.

~~**Blocking M3**~~ — **all seven closed 2026-07-30.** D-027 is the
milestone's definition of done. Its shape: full gathering economy,
gatherer *squads* not individual workers, round-trip hauling, four
resources, player-placed construction, elimination victory, four unit
types with counters, and a visually wrapping torus. The seven remaining
items resolved as:

- ~~Are resource wallets private?~~ → **Private to owner.** Showing an
  opponent your stockpiles leaks information of the same family as
  D-003's intent leakage, and fog exists to withhold exactly that.
- ~~Which buildings exist?~~ → **Four**: town centre (gatherer squads,
  doubles as drop-off), barracks (military squads), storehouse (cheap
  forward drop-off), **defensive tower**. The tower is the consequential
  one — it makes buildings *attackers*, not merely destructible targets,
  which is a larger change to `combat.gd` than being a target. See D-029.
- ~~Do resource nodes deplete?~~ → **Finite, generous yields.**
  Depletion is what makes armies contest new ground as a match runs.
- ~~Where do nodes come from?~~ → **Derived from terrain biomes.** This
  invalidates `terrain_gen.gd`'s standing comment that it exposes
  `biome_color` "rather than a biome enum for now: M1 has no gameplay
  that reads biome" — biome becomes first-class simulation data. See
  D-037.
- ~~4-player fairness, given generated nodes?~~ → **Quadrant-symmetric
  generation.** `_sample` already embeds the map on a 3D torus with
  angular `u`/`v`, so doubling both makes the noise repeat twice per axis
  and the four quadrants come out bit-identical *by construction* — no
  scoring heuristic, no seed rejection. Fairness becomes a property of
  the generator. See D-036. **Superseded twice since:** D-036 revised
  dropped symmetric generation (it made every map the same map four
  times) in favour of free terrain plus a resource-fairness post-pass,
  and D-039 replaced the grid of spawn points with random placement at a
  minimum spacing. Fairness now lives entirely in
  `Economy.balance_for_spawns`, and spacing is the only thing placement
  guarantees.
- ~~Population cap?~~ → **Hard per-player squad cap**, sized to D-015's
  12–15 squads, bounding the match on the axis the architecture is
  actually sensitive to. **Gatherer squads count against the same cap**
  (decided 2026-07-30) — one shared ceiling covering military and
  economy alike, so every villager crew is an army slot not spent. That
  is the economy-versus-army tension made structural rather than a
  balance number, and it means the cap bounds *total* squad count, which
  is what keeps M2's measured per-squad budget valid at 4 players.
- ~~Is 64×32 big enough?~~ → **No. The map becomes 128×64 (8,192
  cells).** Evidence: M2's load test gated only 5 of 48 squads, and one
  squad's vision covers ~169 cells, so twelve squads nearly blanket the
  old map. Watch item: `FlowField.build` is a BFS per destination, and
  D-021 names that solver over 10,000+ cells as the prime GDExtension
  candidate — 8,192 sits just under it, so flow-field cost is measured
  rather than assumed.

**Blocking M4/M5:**
- ~~**Q8 — Map size in cells at ship**~~ → **answered by M4's profiling,
  not before it** (2026-07-30). Flow-field build is a BFS per destination
  over every cell, and D-021 already names that solver over 10,000+ cells
  as the prime GDExtension candidate — so map size is an *output* of
  profiling rather than an input to it. M4 sweeps cell counts through and
  past that threshold, finds where the solver breaks, and the ship size
  is chosen from that curve. Torus parity constraints from D-008 still
  bound whatever is chosen.
- ~~**Q15 — Scale validation hardware**~~ → **accept late validation of
  client rendering** (2026-07-30). Note precisely what this defers: Q15
  is about the *client* drawing 40,000 soldiers, which is GPU-bound and
  which the dev laptop cannot do. It is not about the simulation — D-009
  keeps squad state in packed arrays outside the scene tree, so a
  headless server at ~1,000 squads is pure CPU and runs locally, and
  `bot_client.gd` already runs N virtual clients in one process (D-018's
  memory analysis) deriving soldier transforms without rendering them.

  So M4 proceeds as **simulation and network scale-out, measured
  headless**, and the consequences for the two decisions that wait on it
  are unequal: **D-021's GDExtension trigger is fully served** (its named
  candidate, the flow-field solver, is server-side), while **D-012's LOD
  tiers are only partly served** — simulation LOD is measurable, but
  rendering LOD is not, and M5 must not design that half blind.

  **Deferral trigger:** client-render scale must be measured before M5
  commits to any *rendering* LOD tier, and in any case before M7 (Steam).
  Shipping without ever having drawn the target soldier count is the risk
  this decision knowingly accepts; the trigger is what keeps it accepted
  rather than forgotten.

  **Trigger met 2026-08-02 (M5), and RE-ARMED rather than closed.**
  `just bench-render` now draws the real client path at 100/250/500/1,000
  squads and reports frame time, worst frame, draw calls and the GPU it
  ran on (D-045). So rendering LOD is no longer designed blind — that
  half of the deferral is discharged.

  What is **not** discharged: this was measured on **Intel Iris Xe
  integrated graphics**, and 1,000 squads / 26,644 soldiers renders at
  28 fps there. Whether the target holds on the hardware players will
  actually use is still unmeasured, and an integrated GPU cannot answer
  it — favourably or unfavourably.

  **Sharpened trigger:** before M7, run `just bench-render` on a discrete
  GPU (the numbers are meaningless without the adapter name, which the
  recipe prints for exactly this reason) at the map size and squad count
  the ship configuration uses. The specific unknown is whether the
  remaining cost is CPU-bound — it is 90% CPU on integrated, which
  predicts a discrete GPU changes little and makes *derivation*, not
  fill rate, the thing to watch.

**Blocking M7 / product-level** *(header kept for history — "M7" here
is the old numbering, when Steam was M7; it is M8 now. All six product
questions in this block were closed by the M8 planning session,
2026-08-14, D-087 through D-094)*:
- ~~**Q3 — Who runs the server?**~~ → **D-088** (2026-08-14):
  player-hosted first — the host's machine runs the authoritative sim
  in-process, remote players arrive over Steam relay; official
  dedicated servers are a later rung and the eventual fix for
  host-quit and host-trust. The question's premise aged: hosting
  turned out measured-cheap (~half a core, ~20 KB/s up at 20 players).
- ~~**Q5 — Is 20 players a design target or an engineering
  ceiling?**~~ → **D-089** (2026-08-14): a **design target**, by the
  owner's call. What it obliges: Steam lobby browser + invites (no
  matchmaking service), AI seat-fill, and drop-in/drop-out via D-090's
  repossession. The engineering ceiling stays where D-018 put it.
- ~~**Q10 — Reconnection and desync recovery policy.**~~ → **D-090**
  (2026-08-14): disconnect hands the seat to an AI immediately (D-051
  built the right object); reconnection is repossession by SteamID,
  with no timeout — the AI *is* the grace mechanism; a client-detected
  desync recovers by drop-and-rejoin through the same path, because
  D-025's reveal semantics make a fresh join cheap. Supersedes
  D-033's wipe-on-disconnect for humans.
- ~~**Q11 — Anti-cheat posture.**~~ → **D-091** (2026-08-14): the
  architecture is the anti-cheat — server authority plus curve gating;
  no kernel AC, VAC defaults only. The host under D-088 is trusted,
  stated plainly; ranked play is explicitly gated on official
  dedicated servers.
- ~~Q12 — Art direction for mesh tiers 2 and 3 (D-011), and who
  produces it.~~ → **D-081** (2026-08-09; corrected 2026-08-11 — first
  recorded here as `D-064`, then briefly as `D-075`; both IDs collided
  with unrelated real entries; see D-081's own entry and its editorial
  note): stylised low-poly with strong
  silhouettes, ~300 tris/soldier; produced by committed Python scripts
  driving Blender headless as a library, not by hand in the GUI. Tier 2
  is absorbed rather than skipped — parametric composition is how the
  generators are written.
- ~~**Q13 — Persistence/saves** for long matches on a seamless map.~~
  → **D-092** (2026-08-14): out of M8, by the owner's call. The need
  decomposes into reconnection (D-090) and replays (D-016), both of
  which exist or are specified; true suspend/resume of a multiplayer
  session waits on a measured reason. Two revisit triggers named in
  the entry.
- ~~**Q14 — Terminology: what does "seamless" mean here?**~~ →
  **D-087** (2026-08-14): one contiguous wrapped map with no loading
  screens — true by construction since D-008, no streaming work exists
  anywhere in the plan because none is needed. Closed by writing the
  definition down.
- **Q15 — Age/tech progression, and what a 1–2 hour match is made of.**
  **DISCHARGED 2026-08-04 by D-068 through D-074.** The planning
  milestone the owner reserved on 2026-08-02 ran; the text below is kept
  as the brief it set, and every bullet in it is answered:

  | Q15 asked | Answered by |
  |---|---|
  | Ages: how many, what gates advancing, what each unlocks | **D-069** — five rungs, an `EpochDef` gate in `/epochs/*.tres`, one new verb per rung |
  | Whether progression is per-civ, declaratively | **D-069/D-070** — the ladder is shared; civs differ in contents only. **D-073** maps every civ claim to a knob and cut three that had none |
  | The phase-by-phase account of a 1–2 hour match | **D-068** — six phases, and every later number traces to it |
  | Economy scale, and whether the map is exhausted | **partially — see the correction below** |
  | Is an army a ratchet or a running cost? | **D-068** — a running cost. Per-soldier food upkeep; unpaid upkeep decays morale via D-019 rather than killing soldiers |
  | Interaction with D-018's scale and D-020's tick budget | **D-074 criterion 9**, plus a prerequisite: M6's unattributed 40.8 → ~77 µs/squad rise must be explained before M9 adds load on top of it |

  **One correction to the brief below, and one thing left genuinely
  open.** The economy figures quoted are stale: it says `NODE_STOCK` is
  900 with a node every 11 cells; `economy.gd:41` and `:50` now read
  `NODE_EVERY := 60` and `NODE_STOCK := 2400`. **The question the bullet
  was really asking — whether an hour-long match exhausts the map — was
  not answered and needs recomputing against the real constants once
  D-068's phase table has a consumption rate attached to it.** It is the
  one part of this brief that D-068–D-074 did not close.

  *Original brief, 2026-08-02:*

  The target is 1–2 hours (D-056). Matches currently decide in about
  three minutes, and D-056's tuning addresses only the worst of that.
  **The structural cause is that there is no progression to climb**: four
  buildings and four units per civ, no ages, no tech, no upgrades, so
  after roughly three minutes there is nothing to do but fight. No amount
  of health or squad-cap tuning reaches an hour from there.

  What the planning session has to settle, at minimum:
  - Ages/epochs: how many, what gates advancing, what each unlocks.
  - Whether progression is per-civ (D-047 says civs are data and no
    script may name one, so a tech tree must be declarative too).
  - What a 1–2 hour match is made of, phase by phase — opening,
    expansion, mid-war, late — because D-056's numbers should be DERIVED
    from that account rather than tuned until the symptom stops.
  - Economy scale: `NODE_STOCK` is 900 per node with a node every 11
    cells; an hour-long match at 40 squads/player may exhaust the map,
    which is either a designed pressure or a bug depending on the answer.
  - **Is an army a ratchet or a running cost?** *(raised by the owner,
    2026-08-02.)* There is **no upkeep** today — a unit costs a one-time
    price and nothing drains per tick — so army size only ever grows and
    losing one costs nothing but the rebuild. Upkeep would convert it to
    a steady state you keep paying for, which is what makes losing an
    army hurt, makes raiding workers a real strategy, and stops the
    endgame being two maxed doomstacks with nowhere to go. It is also the
    difference between a late game with economic texture and one where
    everybody accumulates until the map is bare.

    Deliberately NOT bolted on now: it touches economy, AI, UI and every
    balance number, and the phase-by-phase account of a 1–2 hour match is
    exactly what should decide it. Note it interacts with the squad cap —
    upkeep is a *soft* cap, and having both may be one mechanism too many.
  - Interaction with D-018's scale target and D-020's tick budget: more
    ages means more squads alive later, and the 1,000-squad figure is
    already the ceiling the architecture was sized for.

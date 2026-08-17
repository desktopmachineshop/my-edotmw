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

**Amendment — 2026-08-16 — culling a thing that has SIZE, and what a
cull miss is allowed to mean (issue #62).**

Reported from playtest P12 as *"the field of view doesn't gradually fade
out, it snaps large chunks of resources and units in and out of view"* —
two screenshots seconds apart at almost the same camera position, a
forest filling the middle of one and simply gone from the other.

Two faults, both in the same three lines. Neither is new; this is the
**third** appearance of the first and the second has been sitting under
it the whole time.

1. **A 16x16-cell forest chunk was culled as a single POINT.** Trees
   batch into one MultiMesh per (chunk, model), and the chunk root was
   placed or not placed on where its centre projected, with a flat
   `CULL_MARGIN_PIXELS`. The block is ~48 world units across, so its
   trees reach ~24 units past the point deciding for all of them. Squads
   were fixed this way in an earlier playtest, and `_select_nearest`
   before that ("a forty-man line... clicking a soldier you could plainly
   see selected nothing"). The chunks — far bigger than any formation —
   got neither half.
2. **A cull miss RELOCATED the chunk instead of hiding it.** It fell
   through to `RenderCull.nearest_offset`, which answers "which lattice
   copy is nearest the look-at point" — a different question from "which
   copy is on screen". When the two rules disagree the block jumps a
   whole map period in one frame. That is what made it read as *snapping*
   rather than as the honest disappearance it was standing in for.

`RenderCull.visible_offset_of_extent` is now the one definition of both
halves, shared by squads and forests, and `null` from it means **draw
nowhere**. `nearest_offset` keeps its own callers — a rally marker, a
placement ghost, a build preview must always be drawn *somewhere*, and
for those it is still the right rule. The distinction is the point:
**always-visible and being-culled are different jobs and no longer share
a helper.**

**The projected radius is computed from the projection matrix and the
depth, not by projecting an edge point.** Projecting an edge is the
obvious version and was written first; it is wrong twice, and both only
show at the screen edge, which is the one place the number is consulted.
It depends on which axis the edge was taken along — and the camera turns
(D-063), so the same chunk was two widths depending on which way the
player faced — and an edge taken *toward* the camera climbs the
perspective curve, so a chunk 24 units across at 23 units' distance
projected a margin of **two full screens**. A margin wider than the
screen culls nothing, which is D-045's entire saving silently undone. The
margin is also worked out **per lattice copy**: it falls off as 1/depth,
so one borrowed from a copy near the camera is enormous by the time it
reaches a copy near the horizon, and a test caught exactly that pulling
an invisible copy into view.

**The bound is drawn round the STAND, not round the cell centres**
(added on rebase, after D-108 landed in parallel). A node cell grows
several trees on their own offsets inside it now, rather than one tree on
the lattice point, so a chunk's outermost trees hang up to
`ResourceVisuals.MAX_OFFSET` of a hex past the block of cell centres.
The chunk radius is `RenderCull.block_radius(...) + MAX_OFFSET *
hex_size` for that reason. It is a small number — 0.78 against 24 on the
shipped map — and that is exactly why it is worth writing down: a bound
taken round the centres alone would clip the outer row of every forest a
fraction early, which is a quieter instance of the very defect this
amendment exists to fix, and no counter anywhere would move. **When a
thing's contents change shape, every bound drawn round it is stale** —
the same rule D-031's timings taught about the opening.

**And the fault one level up, found in review: the chunk's own centre was
in a different lattice copy from its trees.** A chunk's nominal centre is
`key * NODE_CHUNK + NODE_CHUNK / 2`, which is only on the map when the
map is a whole number of chunks wide — the shipped default is 84 and the
chunk is 16, so the last column owns cells 80-83 and took centre 88.
`TorusSpace.to_world` normalizes, so that came back at q = 4: **145.49
world units away, one exact x period.** Culling then chose the offset
that put *the centre* on screen and the *trees* were drawn at it, so
those six chunks were placed off screen whatever the camera did — the
reported bug still reproducing on about 5% of the map after the fix
above. It is not a regression (the old `_lattice_offset_for` path had the
same fault) but this change is what made the centre load-bearing for
visibility, which is what turned a harmless inaccuracy into the bug.

`RenderCull.block_centre` is the fix and it lives in `render_cull.gd`
precisely so a test can reach it. Two things at once:
`axial_offset_to_world` is the linear map WITHOUT the wrap — identical to
`to_world` whenever the centre is in range, and in the same copy as the
contents when it is not — and the centre is taken from the cells the
block ACTUALLY OWNS, because that last column owns four cells rather than
sixteen and the nominal centre sat 6.5 cells (~11.3 units) outside them,
spending nearly half the radius on the side away from every tree.

**`maps/ladder.tres` escapes it** — 42/16 leaves its last block centred
at 40, still on the map — so a test on the ladder map would have proved
nothing. This is the general shape worth carrying: **an edge case that
one shipped map happens to dodge is not tested by that map.**

**What was NOT fixed, and why.** The report also mentions units popping.
The squad path already had the radius margin and already hid rather than
relocated, so this mechanism does not explain it; the likelier cause is
the trade-off `render_cull.gd` documents in `max_camera_height` —
terrain is drawn nine times and every entity once, so near maximum zoom
a band of the screen can legitimately be bare ground. That is accepted
behaviour, not a defect, and it needs confirming at a fixed camera
height rather than fixing blind.

**Testability, stated honestly.** The decision half lives in
`render_cull.gd` and has eight new tests, each observed red against the
pre-fix behaviour before being trusted (CLAUDE.md's standing rule): the
chunk radius, the extent margin as a projected size, a forest culled by
its trees rather than its middle, a forest with no visible copy
reporting nowhere, the two stand-geometry ones above, and the two
block-centre ones below. **The client-side plumbing that acts on `null`
by setting `root.visible = false` cannot be tested** — `client.gd` needs
a GPU (D-014) — and was verified by looking at `just test-client`'s
frame.
Note the first of those tests had to be strengthened after its first
perturbation run: it asserted only the returned offset, which the old
fallback also produced, at the same value, for the opposite reason. Same
answer, different meaning — a vacuous check of exactly the kind D-022's
audit exists to catch, and it was caught only by watching the
perturbation NOT go red.

Measured on this branch, 2026-08-17: `just test-unit` green at 795 tests
across 51 scripts, and `just test-load 4 120` clean with 0 desyncs at
83.41 µs/squad — **quoted with its squad count, 28**, which is low
enough that per-tick fixed overhead inflates it and makes it
incomparable to any figure taken at 48 or 120. That load figure predates
the last three rebases; nothing since touched the server path, so it was
not re-taken. Recorded here rather than in `CLAUDE.md` per this
directory's rule 5 — a global count in a shared file is stale by
construction on a merged tree, and the one I was maintaining conflicted
on every single rebase of this branch, which is that rule earning itself
in miniature.

**A finding this change does NOT fix, measured while chasing a playtest
report that forests still snap in and out.** A sweep of a realistic
camera over the shipped map found **0 wrongly-culled chunks in 36,288
tests** at six camera heights — so culling is not the cause any more.
What the same sweep did find is that `max_camera_height` no longer
delivers what its own header promises:

| camera height | poses spanning >1 lattice copy | worst |
|---|---|---|
| 20 | 223 of 340 | 4 copies |
| 30 | 304 of 340 | 4 |
| 40 (the default) | 340 of 340 | 4 |
| 47.5 (the cap) | 340 of 340 | 5 |

Terrain draws nine times and every entity ONCE, so every copy past the
first is real ground with no trees, no buildings and no units on it. The
cap's "on-screen z span is ~2.6h" derivation was measured on the old
**128x64** map at 1280x720; the maps were later reshaped to roughly
square (84x96) and the factor never followed. The sweep does not model
depth fog, which will hide the most distant copies, so the visible
severity is lower than 340/340 suggests — but this is the leading
explanation for the report and it needs its own decision, not an
amendment here.

---

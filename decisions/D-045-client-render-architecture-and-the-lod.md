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

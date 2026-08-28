**What the DERIVE phase is made of, and the two levers left in it**
(`D-20260828-inside-the-derive-phase`). Measured by ablation on the
shipped function — only its inputs vary — 96 squads of 36 men drawn at
LOD tier 2, real terrain, native, **Intel Iris Xe**:

| part | cost | share of a 12-man squad |
|---|---|---|
| ground sample, per man | **7.2 µs** | **51%** |
| formation math + transform write, per man | 3.2 µs | 23% |
| per-SQUAD setup | 26 µs | 16% |
| passability clamp, per man | 1.4 µs | 10% |

- **There is no hot spot.** The `atan2` in the ground sampler — the
  obvious suspect — costs **0.02 µs**, a fortieth of the `round_axial`
  beside it. What the phase is made of is **GDScript calls**: a trivial
  method call costs **0.174 µs** here, against 0.095 µs for the two
  `posmod`s inside `TorusSpace.normalize`.
- **Taken, both bit-identical**: `_offset_for`'s squad invariants (a
  `maxf` and a `clampi`/`sqrt` recomputed per man) hoisted out of the
  loop, and two delegations collapsed (`index` writes its own wrap,
  `round_axial` took its body back from `_axial_round`). **D-008 is
  untouched** — the wrap rule still lives in one FILE and every caller
  still comes through `TorusSpace`; what is gone is a stack frame, and a
  test now holds `index` and `normalize` to the same answer. Worth
  **10-18% of the phase** over interleaved pairs (5.592 → 4.714 µs/man
  headless; 54.31 → 44.57 and 52.35 → 47.40 ms in `bench-render`).
- **Filed rather than shipped**, because each is visible to a player or
  changes what the project builds: **#315** (derive a distant squad at a
  lower cadence — the sim is 10 Hz, so a distant squad at 20 Hz shows the
  same curve, but it is per-soldier state surviving frames) and **#316**
  (D-021's GDExtension hatch, whose "measured, not suspected" trigger
  this attribution meets). Drawing fewer men is refused outright: D-045's
  rule is thinner, never smaller.
- **A `bench-check` taken during another agent's `test-load` reported
  every phase 44-302% slower — including phases this did not touch — with
  NO COUNT lines.** The baseline mechanism behaving exactly as designed,
  and the reason every number above comes from an interleaved pair.

---

**The quadratic in the client's frame is gone**
(`D-20260828-the-jostle-looks-where-the-men-are`, #262). The cross-squad
jostle walked every squad the match had ever drawn, for every STANDING
squad — so the frame got worse exactly when the armies arrived.
`DrawnIndex` is a uniform grid over the men each squad was drawn at;
same predicate, same men, pruned every frame.

Shipped map, native, **Intel Iris Xe**, 90 frames per row:

| squads | drawn squads | jostle before | after | frame cpu before | after |
|---|---|---|---|---|---|
| 100 | 63 | 1.75 ms | **0.29 ms** | 27.98 | 12.26 |
| 250 | 155 | 8.99 ms | **0.91 ms** | 65.92 | 29.75 |
| 500 | 321 | 30.22 ms | **2.33 ms** | 126.72 | 62.65 |
| 1000 | 630 | 152.43 ms | **6.10 ms** | 387.51 | 118.65 |

**25x at 630 drawn squads; 2.3 fps to 8.3.**

- **Read the ratio, not the absolutes.** Those ladders are hours apart on
  a shared host and `derive` — which this did not touch — fell 71.3 to
  30.3 ms on its own. Against that phase the jostle went **2.14 → 0.201
  (10.6x)**, and the SHAPE is the result: before, jostle/derive *doubled*
  every rung (0.21 → 0.51 → 1.00 → 2.14); after it is nearly flat (0.088
  → 0.201), drifting up only because a fixed camera holding more squads
  genuinely puts more men near each other.
- **Same men, proved by the mechanism from the PR before it**:
  `just bench-check` reports `STALE render_path` and **no COUNT lines**.
  Every gated count is identical; only how neighbours are found changed.
- **Not `disk_offsets`, and that is deliberate.** These are DRAWN
  positions, which since D-20260818 are lattice copies: normalising them
  onto the torus would merge what the renderer keeps separate. The grid
  indexes the space the predicate is written in.
- **Not `combat.gd`'s bucket map either** — checked first. That is
  `cell -> squad ids` over a `SquadSim`, server-only (D-024). Same shape,
  no shared data, no shared coordinate system.
- **Two deliberate behaviour changes**: stale squads are dropped (the old
  dictionary was never pruned, so a culled squad went on shoving its
  neighbours), and neighbour order is now ascending squad id rather than
  whatever order squads were first drawn in — one fewer way for two
  clients to differ.
- **The mistake in the middle is the interesting one.** Sizing buckets
  lazily at first query re-bucketed every record on every query — the
  quadratic rebuilt inside its own fix, measured at 152 → **188** ms
  before the flag came out. The ladder is what caught it.

---

**Render cost has a recorded baseline now, and nothing has to remember to
re-measure** (`D-20260828-render-cost-has-a-recorded-baseline`, #286).
#229 was a 3x regression found months late by a human playing; #240 then
found the benchmark had not measured the client at all since the RTW
programme. Both are one absence — no recorded number to compare against,
and nothing saying a measurement was owed when the map ladder moved.

```
just bench-stale          # seconds, headless, ANY machine: is the
                          # recorded number about THIS tree?
just bench-check          # a real GPU: run it and compare. Exit 1 if a
                          # deterministic COUNT moved.
just bench-record         # a deliberate human act; names its adapter
```

- **Counts gate, milliseconds report.** Given the same map, roster,
  viewport and render path a run draws the same men at the same LOD in
  the same draw calls every time. **Three independent recordings gave
  identical counts while the wall clock moved 13% between two of them**,
  on the same build and the same machine — which is the whole argument,
  and the gap assessment's rule for CI in as many words.
- **A FINGERPRINT decides whether a difference is a regression at all**:
  the map, the roster, `generated/manifest.json`, Godot's version and the
  SOURCE of the render path. A count that moved because a unit was added
  reads as **STALE — re-record**, not as a fault. Without that the first
  roster change reports a fault and the second teaches everyone to ignore
  the check.
- **`bench-stale` is the per-PR half and needs no GPU.** It cannot tell
  you the client got slower; it can tell you nobody has measured since
  the render path last moved, which is exactly what #229 lacked.
- **A headless baseline is refused**: Godot's dummy display makes the
  cull pass everything and reports zero draw calls (250 squads draws 155
  with a GPU, 250 headless). The committed file carries `headless: false`
  and a test asserts it.
- First baseline: **Intel(R) Iris(R) Xe Graphics**, 1600x900, 250 and
  1,000 squads, 90 frames, shipped map. Integrated graphics — D-085's
  discrete-GPU trigger is still armed.

---

**The benchmark is the client now, and the client is four times what the
benchmark said** (`D-20260828-the-benchmark-runs-the-clients-own-render-pipeline`,
#240). `bench_render.gd` claimed to do "exactly what client.gd's
`_refresh_squads` does" and had not since the RTW battle programme
landed: the duels, the corpse layer, the survivor easing, the cross-squad
jostle and the building/tree push-outs are all per drawn man, all
shipped, and none of them were measured. The pipeline is ONE function
now — `SquadRender.frame` — and both files call it.

At 1,000 squads on the shipped map (Intel Iris Xe, 4,385 men drawn per
frame, two interleaved pairs):

| | cpu ms | derive | decorate | wall ms | fps |
|---|---|---|---|---|---|
| what the benchmark used to measure | 90.1 / 85.9 | 62.5 / 59.8 | — | 105.7 / 88.8 | 9.5 / 11.3 |
| **what the client runs** | **369.2 / 342.2** | 68.8 / 63.6 | **263.2 / 243.8** | 414.1 / 411.5 | **2.4** |

- **#229's 168-185 ms was a floor**, as it suspected. The shipped client
  at D-018's scale is nearer **2.4 fps**, and D-086's 18.5 is not
  comparable to either — it was taken on an instrument measuring a third
  thing.
- **`--decorate=0` reproduces the old measurement**, so every historical
  number stays readable in the terms it was taken in rather than merely
  remembered.
- **A frame time now carries its MIX** (fighting / working / marching,
  plus the buildings and node cells dressed near the camera). The
  decoration passes cost what the world gives them: a frame with nothing
  fighting prices no duels. Same rule as µs/squad with a squad count.
- **The biggest single cost is quadratic and is not derivation** (#262):
  the cross-squad jostle gather is 9.97 ms at 155 drawn squads and
  **142.71 ms at 630** — 4.06x the squads for 14.3x the time, 39% of the
  whole frame — and it fires when squads STAND, which is when the battle
  starts. D-20260821 bounded it "at 72-squad scale".
**The ladder, with the client's own pipeline** (same host and session,
90 measured frames each, one run per row — the SHAPE is the result, not
the third digit):

| squads | drawn squads | drawn men | cpu ms | derive | decorate (gather / jostle / pipeline) | wall ms | fps |
|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0.06 | — | — | 6.78 | 147.5 |
| 100 | 63 | 487 | 27.98 | 8.33 | 15.58 (9.15 / 1.75 / 6.44) | 30.21 | 33.1 |
| 250 | 155 | 1,067 | 65.92 | 17.81 | 38.77 (25.30 / 8.99 / 13.47) | 66.38 | 15.1 |
| 500 | 321 | 2,297 | 126.72 | 30.20 | 80.96 (57.19 / 30.22 / 23.78) | 127.94 | 7.8 |
| 1000 | 630 | 4,385 | 387.51 | 71.33 | 277.30 (217.08 / **152.43** / 60.22) | 432.77 | **2.3** |

Read the jostle column down: 1.75 -> 8.99 -> 30.22 -> 152.43 while drawn
squads go 63 -> 155 -> 321 -> 630. Everything else on the row is linear
in drawn men; that one is not.

- **The client's render pipeline is testable now** — no GPU, no camera,
  no scene tree (`tests/test_squad_render.gd`). "client.gd cannot be
  tested" was always too wide a reading; this is the rest of the
  correction D-075 started.
- **Not verified by a rendered frame.** `just test-client` is docker-only
  and its import step is being OOM-killed on this host (#223 plus four
  other agents resident). Owed.

---

**The client's frame has PHASES now, and the 1,000-squad cost is
attributed** (`D-20260828-every-microsecond-of-a-frame-has-a-phase`,
#229). `just bench-render` reported one number per squad count, so when
the frame tripled between D-086 (53.93 ms) and a playtest measurement
(168-185 ms) there was nothing to attribute it to. It reports cull /
derive / upload / **residual** now, beside a census of what the frame was
working on, and takes knobs that turn each suspect off — all defaulting
to what the client ships, so a bare `just bench-render` measures what it
always did.

Measured 2026-08-28 on **Intel Iris Xe** (integrated; D-085's
discrete-GPU trigger is still armed and still unfired), 1,000 squads /
15,756 soldiers, shipped 168x194 map, two interleaved passes. **Quote a
frame time with its DRAWN-soldier count** — the same rule as µs/squad
with a squad count:

| | cpu ms | cull | derive | upload | drawn/frame | µs per drawn man |
|---|---|---|---|---|---|---|
| as shipped | 112.5 / 106.9 | 18.6 / 17.6 | **82.5 / 78.5** | 8.0 / 7.6 | 4,385 | 18.8 / 17.9 |
| clamp off (#97) | 88.2 / 80.9 | | 57.9 / 53.1 | | 4,385 | 13.2 / 12.1 |
| sampler off | 96.3 / 83.4 | | 64.5 / 55.8 | | 4,385 | 14.7 / 12.7 |
| one lattice copy | 104.0 / 104.4 | | 75.9 / 76.6 | | 4,385 | 17.3 / 17.5 |
| old 84x96 map | 202.1 / 199.1 | 21.3 / 21.1 | 161.8 / 159.4 | 14.5 / 14.2 | 9,402 | 17.2 / 17.0 |

Six things to carry, and most of them are not about frame rate:

- **The frame is derivation** — 73-75% of the client's own per-frame work.
  Culling is 16-17%, the MultiMesh write 7%, the residual 3%.
- **The soldier clamp (#97) is 30-32% of it** and the **terrain sampler
  22-29%**, ~5.7 and ~4.5 µs per drawn man. Both were owed a clean A/B:
  #97's entry says one "is still owed" in as many words, and `CLAUDE.md`
  has called the sampler unmeasured since M5.
- **The four-times-bigger map is NOT the cause, and it was the likeliest
  suspect.** Cost per drawn man is the same on the old 84x96 map
  (17.0-17.2 µs) as on the shipped one (17.9-18.8). What the big map
  changes is how many squads a fixed camera sees — 630 of 1,000 against
  1,000 of 1,000 — so at the same squad count the bigger map is
  **cheaper** (110 ms against 200). Terrain alone is 7.5-8.1 ms at
  ~130 fps.
- **Drawing every lattice copy is as cheap as its entry claimed**: 4-8 ms
  of CPU, inside the run-to-run spread, and 228 draw calls either way.
- **The number is a FLOOR, because the benchmark stopped being the
  client** (#240). `bench_render.gd` still says it does "exactly what
  client.gd's `_refresh_squads` does"; since the RTW programme the client
  also runs duels, corpses, `SoldierMotion.ease`, the jostle gather and
  the building/tree push-outs, all per drawn man, and none of them are in
  the benchmark. That also means #229's third candidate cannot be
  measured by the instrument #229 came from.
- **`soldiers` in the CSV is the ARMY, not the frame's work.** 15,756
  alive against 4,385 derived after LOD — a factor of 3.6. Dividing a
  frame time by the first is how a per-soldier cost gets quoted four
  times too cheap.

**And one optimisation the measurement killed, which is worth more than
the ones it kept.** `StateCurve.sample_axial` walks keyframes from the
first one and `Formation._chord` scanned the array twice more — the exact
shape of this project's most-repeated defect (vision's `distance()` per
cell, `UnitRoster.by_id` per produced squad, terrain noise per soldier,
the per-squad building scan, the flow-field neighbour lookup). It was
written, held to bit-identity against the scan, measured — and reverted:
**a client's curves are 1.3 keyframes long** (16 worst), and a server's
6.5 (33 worst), because D-003 clips to a horizon and the server emits
keyframes incrementally. A bisection over 1.3 elements is a bigger
constant plus a float32-versus-double hazard. `keys_mean` is printed now
so the next person to have the same good idea can check it in one run.

What DID land is three bit-identical hoists out of the per-soldier loop:
the `FormationDef` resolved once per squad rather than once per man (the
roster lookup, and a `String`->`StringName` conversion, ran per SOLDIER
inside a function whose own header explains why everything squad-invariant
is hoisted), the slot rotated by the basis the function already built, and
one `normalize` in the passability test instead of two. Timed headless,
alternating seconds apart because adjacent `bench-render` runs of the same
build measured 130.61 and 220.83 ms while the host filled up: **11.94 ->
10.23, 12.08 -> 10.20 and 14.44 -> 12.77 µs per man, -12% to -16%** — about
1.7 µs off every drawn man, ~7 ms of an 80 ms derivation phase.

**#245 is done**: the clamp and the ground sampler were deriving the same
hex from the same point one line apart, per drawn man, per frame. One
derivation now — `TerrainChunk.height_in_cell` is the interpolation split
out of `height_at`, and `Formation` takes the surface field and finds the
cell once. Measured over three interleaved pairs at 1,000 squads:
derivation **81.3 -> 61.9 ms, -24%**, about 3.2 µs off every drawn man.
Bit-identical, pinned by comparing 21,096 men against the path it
replaces with the clamp firing on 3,134 of them — and the FIRST version
was not, because it packed `(height, passable)` into a `Vector2`, which
is float32. A packed return value is a silent cast.

**#244 is answered, and the answer is NO** (`D-20260828-the-clamp-stays-per-man`).
The per-squad footprint test #97 named is not taken, because #245 moved
the premise: re-measured after it, the clamp is **15.6% of derivation
(74.4 → 62.8 ms), about 3% of the client's real frame**, against the 30%
of a phase it was filed as. Most of what #244 measured was never the
clamp — it was the clamp and the sampler each finding the same hex. What
is left is the men actually over water or rock: on the shipped map
**23.1% of cells are blocked and 9.0% of drawn men are clamped**, and
that ratio is the assumption the decision rests on. Alternatives were
weighed and refused in the entry, including one that would have made a
drawn man's POSITION depend on the camera. The one change taken is
exactly equivalent, could not be measured above this host's noise, and
says so.

**The trade to look at instead is #262**: the quadratic jostle gather is
152 ms of a 387 ms frame — 39% against the clamp's 3%.

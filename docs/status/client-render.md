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

**Left as a decision rather than patched**: the clamp's own per-soldier
cost (#244 — #97's entry names the per-squad footprint alternative, and
it moves where men stand).

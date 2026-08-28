### D-20260828 · 2026-08-28 · Accepted — every microsecond of a FRAME has a phase

**Decision:** the client render benchmark reports its frame as PHASES
with a computed residual — cull, derive, upload, other — beside a census
of what it was working on (soldiers drawn, keyframes per curve) and the
phase split of the WORST frame. It also takes attribution knobs
(`--clamp=`, `--sampler=`, `--copies=`, `--cells_wide=`/`--cells_high=`),
all defaulting to what the client ships, so a bare `just bench-render`
measures exactly what it measured yesterday.

This is `D-20260818-every-microsecond-of-a-tick-has-a-phase` pointed at
the other side of the wire, and it is here for the same reason: the frame
reported ONE number, so a cost that moved into it could not be attributed
to anything, and "the client got three times slower" stayed a sentence
rather than a finding (#229).

## What the attribution says

Measured 2026-08-28, native, **Intel(R) Iris(R) Xe Graphics** (integrated;
no discrete GPU on this machine), Godot 4.7.1, Vulkan 1.3.286 Forward+,
map 168x194 = 32,592 cells, **1,000 squads / 15,756 soldiers**, camera
height 40, 120 measured frames per run, **two interleaved passes** of five
configurations. Both passes are quoted, per this project's rule that one
run is not a measurement.

| configuration | cpu ms/frame | cull | derive | upload | other | soldiers drawn/frame | us per drawn man |
|---|---|---|---|---|---|---|---|
| **as shipped** | 112.48 / 106.91 | 18.57 / 17.63 | **82.53 / 78.51** | 8.02 / 7.60 | 3.35 / 3.17 | 4,385 | 18.82 / 17.90 |
| passability clamp off | 88.15 / 80.86 | 18.67 / 17.04 | 57.87 / 53.09 | 8.23 / 7.62 | 3.37 / 3.11 | 4,385 | 13.20 / 12.11 |
| terrain sampler off | 96.30 / 83.40 | 19.71 / 17.06 | 64.47 / 55.79 | 8.60 / 7.47 | 3.53 / 3.06 | 4,385 | 14.70 / 12.72 |
| one lattice copy | 104.00 / 104.40 | 17.61 / 17.67 | 75.92 / 76.58 | 7.37 / 7.15 | 3.10 / 3.00 | 4,385 | 17.31 / 17.46 |
| old 84x96 map | 202.09 / 199.12 | 21.27 / 21.13 | 161.84 / 159.37 | 14.51 / 14.22 | 4.48 / 4.40 | 9,402 | 17.21 / 16.95 |

Five findings, in the order they matter:

1. **The frame is derivation.** 73-75% of the client's own per-frame work
   is `soldier_transforms_lod`; culling is 16-17%, the MultiMesh write 7%,
   and the residual 3%. M5's "~96% derivation" was measured before
   culling, LOD, the clamp and the copies existed; the shape holds, the
   share has moved.

2. **The passability clamp (#97) costs 24.7 / 25.4 ms — 30-32% of
   derivation**, about 5.7 us per drawn man.
   `D-20260818-a-soldier-stands-where-his-squad-could-walk` measured
   itself at +47% and +81% on a loaded host and its own entry says *"a
   clean `bench-render` A/B on an idle machine is still owed."* This is
   that A/B, interleaved, and it lands at the bottom of that range.

3. **The terrain height sampler costs 18.1 / 22.7 ms — 22-29%**, about
   4.5 us per drawn man. `CLAUDE.md` has flagged this as unmeasured since
   M5 ("its cost on real hardware is unmeasured"). It is measured now.

4. **Lattice copies are as cheap as their entry claimed.** Drawing every
   visible copy instead of one costs 4-8 ms of CPU — inside the
   run-to-run spread, and the two passes disagree on the sign of part of
   it — with **228 draw calls either way** at this camera.
   `D-20260818-entities-are-drawn-at-every-visible-copy` argued it was
   "nearly free because the expensive part was already shared"; that
   claim survives its first measurement at scale.

5. **The map is NOT the cause, and it is the candidate that looked most
   likely.** Per drawn man, the old 84x96 map costs **17.0-17.2 us
   against the shipped map's 17.9-18.8** — the same within noise. What
   the four-times-bigger map changes is how many squads are ON SCREEN at
   a fixed camera: 630 of 1,000 against 1,000 of 1,000, because the same
   thousand squads are spread over four times the ground. At the same
   squad count the bigger map is therefore **cheaper** (110 ms against
   200), and the terrain-only row is 7.5-8.1 ms at 130 fps. The map
   ladder did not break the renderer.

**What this attribution deliberately does NOT claim.** It does not
explain D-086's 53.93 ms becoming today's ~110, and it must not be read
as doing so. D-086 reported no per-frame census — no drawn-soldier count,
no phase split — so there is no way to know how many men that frame
derived, and any decomposition of the gap would be invented. This is the
same refusal `D-20260818-every-microsecond-of-a-tick-has-a-phase` made
about M6's older 40.8 -> ~77 us/squad rise: **unexplained numbers do not
explain themselves later, and they do not explain themselves backwards
either.** What is now true is that the next such gap is decomposable,
because the phases and the census are printed.

**And the number itself is a FLOOR.** `bench_render.gd` says it does
"exactly what client.gd's `_refresh_squads` does, minus the ghost pass",
and since the RTW battle programme it does not: the duels, the corpse
layer, `SoldierMotion.ease`, the jostle gather and the building/tree
push-outs are all per drawn man in the client and absent from the
benchmark. Filed as #240 rather than fixed here, because adding them
changes what every previously recorded `bench-render` number means and
wants a decision of its own. It also means candidate 3 of #229 — the RTW
passes — **cannot be measured by the instrument #229 was filed from.**

## What was fixed here, and what it bought

Three changes, all inside the per-soldier loop of
`Formation.soldier_transforms_sampled`, all **bit identical** by
construction:

- **The `FormationDef` is resolved once per squad, not once per man.**
  `slot_offset` looked it up in the roster — converting a `String` to a
  `StringName` and hashing it to do so — for every soldier, inside a
  function whose own header explains that everything squad-invariant is
  hoisted out of that loop precisely because "calling `soldier_transform()`
  in the loop re-sampled the curve twice ... 40 identical curve samples
  for a 40-man squad, every frame". The def lookup was simply missed when
  that hoist was done.
- **A slot is rotated by the basis this function already built**, rather
  than by `Vector3.rotated(UP, angle)` — which constructs the same
  `Basis(UP, angle)` again for every man. `Vector3.rotated` IS
  `Basis(axis, angle).xform(v)`, so the two are the same arithmetic and
  `test_bulk_derivation_matches_the_single_soldier_path` holds them to
  it.
- **`_stands_on_passable` normalises once**, not twice: `world_to_cell`
  wraps its answer and `index` wraps it again, four `posmod`s where two
  do, once per drawn man per frame.

**What they bought, measured.** A three-per-cent arithmetic change
cannot be resolved through a three-minute GPU run on a host four other
agents are using — adjacent `bench-render` runs of the SAME build
measured 130.61 and 220.83 ms of CPU while this was being taken, which is
this project's own "a wall clock here is a statement about the HOST"
warning arriving again. So the derivation path was timed directly,
headless, alternating the two versions of `formation.gd` seconds apart
rather than minutes, 92,160 men derived per run through the real
`soldier_transforms_sampled` with the real sampler and the real
passability array:

| pass | before | after | |
|---|---|---|---|
| 1 | 11.943 us/man | 10.227 us/man | **-14.4%** |
| 2 | 12.082 us/man | 10.199 us/man | **-15.6%** |
| 3 | 14.440 us/man | 12.766 us/man | **-11.6%** |

About **1.7 us off every drawn man**, which at the 4,385 men a
1,000-squad frame derives is roughly **7 ms of an 80 ms derivation
phase**. The one adjacent `bench-render` pair taken before the host got
noisy agrees in direction and size: derivation 94.43 -> 89.09 ms.

Modest, and worth taking because it is free: nothing moves, nothing new
is stored, and the two existing equality tests (`test_formation.gd`'s 49
assertions, `test_bulk_derivation_matches_the_single_soldier_path` in
particular) are what hold the bulk path to the single path it must equal.


## The optimisation this measurement KILLED

`StateCurve.sample_axial` walks the keyframes from the first one, and
`Formation._chord` scanned the whole array twice more; all three run
several times per squad per frame. That is the shape of this project's
most-repeated defect — vision's `distance()` per cell (M2),
`UnitRoster.by_id` per produced squad (M4), terrain noise per soldier per
frame (M5), the per-squad building scan (M6), the flow-field neighbour
lookup (D-20260818) — so it was written, tested for bit-identity against
the scan, and then **measured, and reverted**.

**A client's curves are 1.3 keyframes long.** The benchmark's own census
(`keys_mean`, added here for exactly this question) reports **1.3 mean and
16 worst per drawn squad** at 1,000 squads on the shipped map. The server
is barely longer: a `SquadSim` on the shipped map with 60 squads ordered
across it and ticked 120 times holds **6.5 keys mean, 33 worst**. D-003's
horizon clip is why on the client, and incremental keyframe emission is
why on the server — the curve holds where a squad is going *next*, never
its whole journey.

A bisection over 1.3 elements is not an optimisation, it is a bigger
constant plus a hazard: `PackedFloat32Array.bsearch` compares in the
array's own float32 precision while the scan compared each element
against a double, so a probe within a float32 epsilon of a keyframe
landed one index out. That is four parts in ten million along one leg —
invisible in any picture, and a real difference in a function both
machines derive from. Correcting it needed a bounded fix-up loop, which
is complexity bought for nothing.

**So the finding is the census, not the code**, and it is worth more than
the change would have been: the scan LOOKS like the defect the whole
history above trained everyone here to see, and the instrument says it is
not. Recorded rather than quietly dropped, because the next person to
read `sample_axial` will have the same idea — the number to check first
is `keys_mean`, and it is printed now.

**The two big costs were left alone on purpose**, and both are design
calls rather than optimisations:

- **The clamp** is `grounded_offset` per drawn man, and #97's own entry
  already names the lever — *"a per-SQUAD footprint test off
  `TorusSpace.disk_offsets`, not a faster per-soldier one"*. That changes
  where men stand near a shoreline, which is a rule a player can see, so
  it is a decision and not a patch. Filed as #244.
- **The sampler and the clamp compute the same cell twice.** *(Taken —
  see the amendment below.)*
  `TerrainChunk.height_at` derives the containing cell from (x, z), and
  `_stands_on_passable` derives it again from the same point one line
  earlier. Merging them would take roughly the smaller of the two costs
  off every drawn man — but `ClientState.terrain_sampler` is a
  `Callable(x, z)` read by the client, the benchmark, the previews and
  the wall-tier bump lambda, so it is an interface change. Filed as #245.

Neither is attempted here because #229 asks for an attribution first, and
because a change that moves soldiers is not a change to make in the same
breath as a change that cannot.

## Rejected alternatives

- **Guessing from the four candidates in #229.** Two of them (the map,
  the copies) are measurably not it, and the one that reads as most
  likely to a person — the four-times-bigger map — is the one that
  actually makes each frame *cheaper* at a fixed squad count. That is
  exactly why the knobs exist.
- **A wall-clock A/B without the phase split.** It would have shown the
  clamp and the sampler as one blob and said nothing about culling or the
  upload, and it could not have shown that the residual is 3%.
- **Timing the phases with `Engine.get_frames_per_second` or the frame
  delta alone.** The delta includes the GPU, which at 1,000 squads is 20%
  of the frame and not what is being attributed.
- **Removing the clamp because it is expensive.** It exists because
  soldiers stood on ground their squad could not walk on and popped 2.0
  world units onto a drawn cliff (#97). The cost is real; so is the
  defect it fixes.

## Consequences

- `just bench-render` takes a fifth positional argument, `ARGS`, empty by
  default. The CSV line is unchanged, so every historical quote stays
  comparable; the phases, the curve census and the worst-frame split are
  additional lines.
- **A frame time is now quoted with its drawn-soldier count**, the same
  way a per-squad cost is quoted with its squad count and a memory figure
  with its player/squad/cell counts. `soldiers` in the CSV is the army's
  total strength and is NOT what the frame derived — 15,756 against 4,385
  here, a factor of 3.6 — and reading the first as the second is how a
  per-soldier cost gets quoted four times too cheap.
- The four fixes are in code every client frame runs and both sides of
  the wire derive with, so they are held to bit-identity rather than to
  "close enough": `tests/test_curve_search.gd` compares the bisection
  against the scan it replaces over ~9,600 assertions, and
  `test_bulk_derivation_matches_the_single_soldier_path` already pins the
  formation path.
- **The bisection was NOT bit identical at first, and the test is what
  said so.** `PackedFloat32Array.bsearch` compares in the array's own
  float32 precision while the scan compared each element against a
  double, so a probe within a float32 epsilon of a keyframe landed one
  index out. Numerically that is four parts in ten million along one leg
  — invisible in any picture, and a real difference in a function both
  machines derive from. It is corrected with a bounded fix-up, and
  removing that fix-up turns the test red.

## Revisit trigger

A discrete GPU (D-085's re-run trigger, still armed and still unfired —
every number in this family is integrated graphics). #240 landing, which
would make the benchmark's frame the client's frame and move all of these
numbers up. Or either of #244/#245 being taken, both of which move the
two largest phases and both of which must re-take this table rather than
argue from it.

---

**Amendment, 2026-08-28 — #245 is taken, and it is worth 24% of the
derivation phase.**

A man's footing and his height are answers about the SAME hex, and each
was finding that hex separately: `Formation._stands_on_passable` and then
`TerrainChunk.height_at`, from the same world position, one line apart,
for every drawn man every frame. `world_to_axial` + `round_axial` +
`index` is the expensive part of both and the part they share.

`TerrainChunk.height_in_cell` is the interpolation split out from
`height_at`, so a caller that has already found the cell can ask for the
rest without finding it again; `Formation.soldier_transforms_sampled`
takes the SURFACE FIELD (and the wall-tier bump) and derives the cell
once. On open ground — where almost every man is, almost always — that is
now the only conversion he costs. A man over water or rock still pays for
his pull-back probes, which is the rare path and the one the loop is
allowed to be slow in.

Measured at 1,000 squads / 4,385 drawn men, `--decorate=0` to isolate the
phase, native, Intel Iris Xe, three interleaved pairs seconds apart:

| pass | two derivations | one derivation | |
|---|---|---|---|
| 1 | 83.14 ms (18.99 us/man) | 65.88 ms (15.05) | **-20.8%** |
| 2 | 88.81 ms (20.28) | 58.99 ms (13.48) | **-33.6%** |
| 3 | 71.88 ms (16.42) | 60.96 ms (13.93) | **-15.2%** |

Mean **81.3 -> 61.9 ms, -24%** of the derivation phase: about 3.2 us off
every drawn man.

Three things came with it, none of them about arithmetic:

- **The Callable path is kept**, and taken by every caller that has only
  a sampler — the previews, the tests, anything with a synthetic ground.
  Nothing had to change to keep working, which is what made this safe to
  do at all.
- **A second closure per squad per frame is gone.**
  `ClientState._sampler_for` wrapped the sampler in a NEW lambda for
  every tier-1 squad every frame, purely to add the wall-tier bump
  (D-076). The bump is an argument now.
- **The first version returned `(height, passable)` in a `Vector2` and
  was NOT bit-identical**, because `Vector2` holds float32 and
  `height_at` returns a float64. It made no difference to a drawn man
  (`Transform3D.origin` is float32 anyway) and the equivalence test
  caught it regardless — 21,096 men compared over real generated terrain,
  the clamp firing on 3,134 of them. **A packed return value is a silent
  cast**; the shipped shape returns the height as a float and lets the
  caller keep the index it already has.

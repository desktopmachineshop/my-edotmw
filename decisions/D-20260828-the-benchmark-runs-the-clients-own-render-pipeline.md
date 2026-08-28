### D-20260828 · 2026-08-28 · Accepted — the benchmark runs the client's own render pipeline

**Decision:** the per-squad render pipeline — the duel pass, the
static-target deal, the building and tree push-outs, the survivor easing,
the cosmetic decoration and the clip — is **one function**,
`SquadRender.frame`, and `client.gd` and `bench_render.gd` both call it.
The benchmark runs it BY DEFAULT, because it is what the client runs;
`--decorate=0` reproduces the bare pipeline every earlier number was
taken with.

From #240. `bench_render.gd`'s own comment said it did "exactly what
client.gd's `_refresh_squads` does, minus the ghost pass". That was true
when it was written and stopped being true the moment the RTW battle
programme landed, and nothing failed — the benchmark went on printing
confident, reproducible, wrong numbers.

## What it was hiding

Measured 2026-08-28, native, **Intel(R) Iris(R) Xe Graphics**
(integrated), Godot 4.7.1 / Vulkan 1.3.286 Forward+, shipped 168x194 map,
1,000 squads / 15,756 alive / **4,385 drawn per frame**, camera height 40,
two interleaved pairs:

| | cpu ms/frame | cull | derive | decorate | upload | wall ms | fps |
|---|---|---|---|---|---|---|---|
| what the benchmark measured (`--decorate=0`) | 90.06 / 85.86 | 16.3 / 15.3 | 62.5 / 59.8 | — | 7.1 / 6.9 | 105.7 / 88.8 | 9.5 / 11.3 |
| **what the client runs** | **369.17 / 342.23** | 18.3 / 17.1 | 68.8 / 63.6 | **263.2 / 243.8** | 14.1 / 13.3 | 414.1 / 411.5 | **2.4** |

**The instrument was measuring under a quarter of the client's per-frame
CPU work.** #229's 168-185 ms was a floor, as its own entry suspected;
the shipped client at D-018's 1,000 squads is nearer **2.4 fps** than the
5.4-5.9 recorded there, and D-086's 18.5 fps is not comparable to either
because it was taken on an instrument that measured a third thing.

That is M4's lesson exactly — `just profile` reported ~29 ms for code
that spent 866 ms in a live server (D-043 criterion 11) — arriving on the
render side, where the rule "**where the harness and the live thing
disagree, believe the live thing**" could not even be applied, because
the harness never ran the code.

**And the decoration phase is not uniform work.** Split out, it is
`gather` (what is this squad doing, which enemy men, which boxes, which
discs, which foreign men) and `pipeline` (`SquadRender.frame` itself),
and the gather is dominated by one pass that is **quadratic in drawn
squads**: the cross-squad jostle gather costs 9.97 ms at 155 drawn squads
and **142.71 ms at 630** — 4.06x the squads for 14.3x the time, against
16.5x for a perfect square and ~3.4x/3.8x for the linear passes beside
it. Filed as **#262**; it is 39% of the whole frame at 1,000 squads and
it fires when squads STAND, which is to say when the battle starts.

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

## Why extraction rather than a second copy

The obvious repair is to write the passes into the benchmark and guard
the pair with a scan. That is what created this defect: two spellings of
one pipeline, one of which was maintained. D-096 (terrain UVs), D-102 (a
player's colour) and D-20260823 (the drag preview computing its own
positions) all landed on the same answer — **one definition, called by
both** — and each of them says a preview or a harness with its own
arithmetic is one that eventually lies.

So the expensive half is now literally shared code: a benchmark cannot
drift from a client whose function it is calling.

**What is NOT shared, and is the honest limit of this change.** The
GATHER stays per-caller: `client.gd` resolves activity, boxes, discs and
neighbours out of `ClientState` and its own per-frame caches, and the
benchmark builds an equivalent from a world it dresses on purpose. Those
two can still drift. They are held together by
`test_squad_render.gd`'s caller-exists scan — which carries D-106's own
caveat, that it covers the caller it names — and by the gather being the
cheap half in shape if not in size.

## Consequences

- **A frame time now carries its MIX.** The decoration passes cost what
  the world gives them: a frame with nothing fighting prices no duels.
  The benchmark prints `fighting/working/marching` and the count of
  buildings and node cells it dressed the ground with, and a number
  quoted without them is a number about a different battle. This is the
  same rule as quoting µs/squad with a squad count and a memory figure
  with its cells.
- **Every `bench-render` number recorded before today is a
  `--decorate=0` number.** They are not wrong, they are answers to a
  narrower question, and the flag is kept so they stay reproducible
  rather than merely remembered.
- **`SquadRender` is all-static and pure over its inputs**, except that
  the caller passes in the `SoldierMotion` it owns — D-006's amended
  clause 2 puts the eased per-soldier positions there and nowhere else,
  and a pipeline that constructed its own would be per-soldier state
  with two homes.
- **The client's render pipeline is testable for the first time.**
  `tests/test_squad_render.gd` drives the real duel pass, the real deal
  cache, the real push-outs, the real easing and the real clip choice
  headless: no GPU, no camera, no scene tree. "client.gd cannot be
  tested" was always too wide a reading (D-075's 2026-08-16 amendment
  made the same correction about node lifetime); this is the rest of it.
- **The benchmark's `--decorate=0` path is not dead code**: it is how the
  A/B above is taken, and how a historical number is read in the terms it
  was recorded in.

## Verification, stated plainly

The moved code is exercised by `tests/test_squad_render.gd` (11 tests)
and the full suite is unchanged apart from it. **It was NOT verified by a
rendered frame**: `just test-client` is docker-only by design (D-014's
2026-07-29 amendment) and its `_import` step is being OOM-killed on this
host while four other agents' jobs are resident (exit 137) — the same
host pressure `docs/status/host-load.md` exists for, plus #223. A
rendered check is owed the moment the host allows one, and this entry
says so rather than letting the gap be discovered.

## Revisit trigger

The gather being extracted too, which is the remaining half of the drift
surface — worth doing the moment either caller's gather changes shape.
And #262: fixing the quadratic changes the biggest number in the table
above, so that fix must re-take it rather than argue from it.

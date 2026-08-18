# D-20260818 · Terrain builds a slice at a time, behind a loading bar

**Date:** 2026-08-18
**Status:** Accepted
**Issue:** #106 (M10 workstream 2 of 8, exit criterion 1)
**Supersedes nothing.** Amends how `client.gd` calls the terrain code; the
terrain code itself (D-017, D-084, D-096, D-097, D-106) is unchanged, and this
is checked byte for byte rather than argued.

## Decision

The client no longer builds the ground in one blocking pass before a match's
first frame. `TerrainBuild` (`terrain_build.gd`) advances the build in slices
budgeted in **cells**, driven from `_process`, and the player watches a
**loading bar** until every chunk is in the tree.

`TerrainGen.build_fields` is split into `fields_begin` + `fields_step(work,
cell_budget)`, with `build_fields` kept as the whole-map case of that pair, so
there is exactly one copy of the arithmetic and every headless caller (the
sweep, the previews, the tests) is untouched.

**Up to 30 seconds behind a bar is the accepted budget** (owner's call,
2026-08-18), replacing #106's originally stated "interactive within 1.5 s with
the ground streaming in around the player". `client.gd` measures each build
against `LOADING_BUDGET_SECONDS` and warns when it goes over, so the number is
checked rather than quoted.

## Rationale

### The defect

A five-second frozen window at the start of every match on the shipped
168x194 map, found by a human closing it and asking whether the server was
down. Every number was healthy — the server reported 0 dropped ticks and a
3.1 ms worst tick throughout — because none of this is a simulation cost. A
frozen window is indistinguishable from a dead one, which is the whole of the
player-facing defect.

### Why slices, and why cells

This is D-040's fix pointed at the other side of the wire. Budgeting whole
flow-field BUILDS failed there and budgeting CELLS worked, because partial
progress is kept rather than discarded; the same is true here, and it is what
lets a slice resume mid-map. Budgeting cells rather than milliseconds is also
what makes the guarantee testable: `docs/status/ground-fog.md` already records
one timing gate in this repo that went red on a loaded host with nothing
wrong, so the tests assert **cells advanced per slice** and the milliseconds
are printed, never gated.

### Why a bar rather than a playable half-built world

#106 proposed streaming into a live match, and that was built first. The
owner's call was a loading bar and up to 30 seconds instead, and it is the
better trade:

- **Nothing is ever drawn standing on ground that does not exist.** A
  soldier's y comes from `fields.surface` (D-006's fourth input), so a match
  that started on the fields alone would derive the founding party at sea level
  and bury it in hills that were about to exist — the picture D-045 spent a
  milestone getting rid of.
- **Every phase timing in the test estate stays valid.** `_drive_m2_scenario`,
  the load-test bot phases and the capture verdict were all tuned against a
  client whose ground existed before its first frame. Streaming would have
  restaged all of them to fix a freeze nobody in those harnesses is sitting
  through — this project's own "when the opening changes, every timing tuned
  against the old one is stale" rule, pointed at itself.
- **The slices are still needed.** A bar with nothing to report is a spinner,
  and a window that does not return to its event loop is one the desktop greys
  out. So the machinery is identical; only the gate moved.

Capture mode (`just test-client`) therefore keeps the one blocking pass, via
`_build_terrain()`, which is `_advance_terrain()` driven to the last chunk.

## Measurements (2026-08-18)

Taken on a host shared with several parallel agent worktrees, so **absolutes
here are inflated and only the A/B is sound** — the same lesson as
`docs/status/terrain.md`'s benchmarking-session warning and M6's worst-tick
figures. On the quiet end of the same session the default map measured
~2.1 s of fields and ~5.7 s of meshing; at the loaded end, 10.9 s and 30.5 s.

**Slicing costs nothing.** Streamed against one pass, in the same process, on
the same host state: fields 9.77 s streamed vs 10.85 s in one pass; total
41.4 s streamed vs ~41.0 s in one pass. The work is identical and the
per-slice overhead is inside the run-to-run noise.

**D-017's chunk size survives its own re-measurement.** #106 asks for it to be
re-taken, since D-017 was decided by measurement and every map-size change
since invalidated it. On the shipped map, total meshing cost is **flat** in
chunk size:

| chunk size | chunks | total meshing | worst chunk |
|---|---|---|---|
| 8 | 525 | 6.9 s | 32 ms |
| 12 | 238 | 4.9 s | 105 ms |
| **16** | **143** | **5.7 s** | **88 ms** |
| 24 | 63 | 5.3 s | 120 ms |
| 32 | 42 | 5.9 s | 266 ms |
| 48 | 20 | 4.7 s | 374 ms |

The spread is run-to-run noise, not a trend. What the knob really controls is
**granularity** (the worst single chunk, which is a slice's floor) and the
instance count the nine lattice copies multiply — 525 chunks would be 4,725
`MeshInstance3D`. 16 keeps the worst chunk well inside a slice at 1,287
instances, so it stays.

**One redundant pass removed.** The minimap base image was painted by calling
`biome_color` per cell, which re-evaluates the elevation noise 32,592 times —
a ~200 ms pass over a field already in hand. It reads `fields.biome` now.
Identical by construction: `biome_color` is `color_of(biome_at(...))`, and
`fields.biome` is what `biome_at` would answer.

## Rejected alternatives

- **A smaller chunk size** (#106's first lever) — measured above, buys nothing
  on the total and costs instances.
- **A worker thread** (#106's third lever) — the real remaining lever, and the
  only one that reduces total wall clock rather than spreading it. Rejected
  *for now*, not on principle: the fields' corner pass shares a memo across
  cells, so a parallel version needs either per-worker caches or a different
  decomposition, and that is a bigger change than a freeze fix should carry
  into a merge train. Named as the follow-up if the 30 s ceiling is ever
  breached.
- **Binding the fields as soon as they were ready** (the first implementation)
  — see "why a bar" above.
- **A `ProgressBar` and a layout module** — the bar is expressed in ANCHORS,
  shares of the window, so there is no pixel arithmetic to go stale at a
  resolution nobody tested. That is
  `D-20260817-lobby-fits-the-window`'s lesson honoured without a second layout
  module to keep in step with `hud_layout.gd`.

## Consequences

- `TerrainGen.fields_begin`/`fields_step` are the sliceable path;
  `build_fields` is unchanged for every existing caller and is now implemented
  in terms of them. A partial fields build is **not** safe to read — unlike a
  partial flow field, an unreached cell holds zeroes, which is flat ground at
  sea level rather than "not known yet". Hence the return value.
- The corner-weight memo is written by whichever cell reaches a corner first,
  so a different budget visits it in a different order. That order must not
  change the answer, or the map would depend on the frame rate; a test builds
  the same map at two budgets and compares.
- `_terrain_built` still means "the world is ready", and now that includes the
  meshes. `_terrain_stream` is the thing that says whether a build is running.
- The client prints its build as a measurement: chunks, slices, worst slice,
  fields time, total. Two things that fail silently and identically — an
  unfogged and an untextured ground — are still reported on the same line.

## Revisit trigger

A build that exceeds `LOADING_BUDGET_SECONDS` on the shipped default map on
ordinary hardware — the client warns when it does. The lever at that point is
the worker thread above, or cutting the mesher's per-cell cost (it recomputes
corner geometry that `build_fields` already resolved), not a smaller slice.

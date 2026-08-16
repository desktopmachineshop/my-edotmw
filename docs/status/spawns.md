**A start is a PLACE, not a legal cell (D-104, 2026-08-16).** From a
playtest of the `islands` preset: a founding party apparently standing in
open sea. Nothing was placed in water — `spawn_points` returned 20 of 20,
none impassable, and no node sat on an impassable cell. Three defects
under that, all the same shape, all invisible to every number:

- **`spawn_points` tested ONE cell.** Passable, and nothing about what
  surrounds it. `islands` is ~71% water, so one player in twenty started
  on a **six-cell rock** — legal ground, and dead on arrival, since a town
  hall plus resources do not fit and D-031 makes the founding party the
  whole opening. `validate_spawns` could not see it: it compares COUNTS,
  and twenty of twenty were found. `MapConfig.min_spawn_landmass` (96) is
  the fix — a flood fill capped at the minimum, so it costs O(min) per
  candidate and answers only "does this clear the bar". **96 was swept,
  not guessed** (4 presets x 4 sizes x 3 seeds): it rejects every stranded
  start found while still seating 20 of 20 from Standard up. It runs LAST
  of the three candidate tests — the three are an AND so order cannot
  change the answer, and on the over-packed Skirmish maps it measured
  **1.0–3.5 s with the fill first against 0.2–0.4 s with it last**.
  Sampling costs 12–33 ms at 20 slots from Standard up, against
  1.0–4.5 ms before.
- **The fairness pass picked cells by passability alone**, so stone
  outcrops landed on sand and grass — flatly against D-087, which moved
  stone to the mountain foot so a node reads as belonging to its ground.
  It prefers ground that GROWS the thing now, falls back to any walkable
  cell, ranks beach last (a beach cell borders water by definition, and
  the authored models overhang the cell), and **says how many it had to
  compromise**. Measured: beach top-ups 9 → 0 on the reported world,
  16 → 0 on `islands` Standard. The band table the generator rolls
  against is now ONE table both read (`Economy._bands`) — verified
  identical to what it replaced across **63,359 nodes on 16 worlds, 0
  mismatches**.
- **The lobby's spawn preview drew twenty markers, none of them real.**
  Both sides called `MapConfig.spawn_points` — the client under a comment
  saying "this is the SHARED implementation the server uses (D-039), so
  this is the same answer" — and fed it different seeds. **Sharing an
  implementation is not sharing its arguments**, and the comment
  asserting otherwise is why it survived (the D-065 family again).
  `MapSettings.to_spawn_config()` is the one derivation now, its inputs
  travel on the wire like every other terrain number, and a
  source-scanning test fails if any other script assigns `spawn_seed`.

**Rejected while fixing it, with the measurement:** caching the per-cell
ground rank in the fairness pass measured SLOWER than recomputing it, so
it is not there — the cache ranks every reachable cell where the plain
loop ranks only free ones.

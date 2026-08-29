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

**How MANY starts there are is the seat count now, not a setting
(D-20260817-starting-positions-follow-the-seats, #103).**
`MapSettings.player_slots` is derived by `MatchState._seats_changed()` at
every site that adds or removes a seat, clamped to [2, 24] and reverted if
the result is a map the generator refuses. The lobby's "Starting
positions" spinner is gone with it, and so is the "Seed" row — the seed
NUMBER is a dev handle (`--seed`, D-100); Reroll, which is what a player
actually wants from it, stays.

Two things worth carrying:

- **The default was wrong, not just the control.** `player_slots`
  defaulted to 8 (20 on the shipped map), so a lobby of three generated
  twenty starts — and because `spawn_points` scatters at
  `min_spawn_spacing`, three players were flung as far apart as twenty
  would have been. The number was the seat count all along, written down
  twice and allowed to disagree.
- **This changes spawn placement in every match, tests included.** A
  4-bot `test-load` generates 4 starts where it generated 20, so spawns
  are closer and armies meet sooner. Any timing tuned against the old
  spread — bot phases, the load test's fog gates — is measuring a
  different opening than it was; that is CLAUDE.md's standing
  "when the opening changes, every timing tuned against the old one is
  stale" rule applying to the MAP rather than to the build order.
  Measured at `4 150` (once on `main`, twice on the branch, same host):
  **`conceal_events` 2 → 16 and 15, `ghosts_peak` 2 → 15**, and the
  per-squad cost 47.25 → 58.04/62.25 µs at the same 34 squads with the
  whole delta in vision and combat — armies in contact, not slower code.
  **`reveal_events` was 1 then 0 against `main`'s 0, so this does NOT
  fix #69** and one clean verdict out of two is not a measurement; the
  decision entry has the table and the reasoning.

**And "the settings are valid" did not mean "the map is playable"
(D-20260818-a-slider-and-its-constraint-are-one-thing, #125,
2026-08-18).** Found by the owner playing the lobby: nudging sea level
past its preset value produced a configuration the server refused, with
nothing on screen saying which way was safe. Three sources of truth — a
literal range table in `client.gd`, a second copy of the same four ranges
as `clampf` calls in `MatchState.set_map_option`, and the coupled
thresholds in `MapSettings.validate` — each correct alone and meaningless
as a set. What made it bite was `beach_level`, set by the preset and
exposed by nothing, which pinned the sea-level slider's real ceiling at
0.27 on `plains` against a slider drawn to 0.90: **74% of that slider's
travel produced a map the server would not generate.** The beach is a
BAND above the waterline now (derived, so it cannot be the thing that
refuses), and `MapSettings.slider_bounds` is the one definition both
sides read — sea and mountain bound each other, so the ends move.

Three things worth carrying:

- **The open question that came with it is answered, and the answer is
  yes.** A combination could pass every threshold check and still produce
  an unplayable world: on the shipped Standard map, sea level 0.85 with
  the mountain line at 0.98 is **0.0% walkable with 0 of 8 starting
  positions**, and `validate()` returned "". So `validate` samples the
  world now — `walkable_fraction`, a fixed 32-per-axis lattice (~4 ms,
  within 0.012 of the full generation on 16 worlds), refusing anything
  with less land than the two starts the same function already demands.
  It reuses `min_spawn_landmass` rather than inventing a fraction, which
  is D-104's own definition of how much ground a start needs.
- **A dead end that depends on the seed cannot be drawn as a range.**
  Bounding the sliders to what the presets use was the obvious fix and is
  the wrong one: sea level 0.6 is a good map, and where the ground runs
  out moves with the seed and the other two sliders. The honest fix is to
  test the world and say so in the panel as the handle moves.
- **`validate()` is no longer free** (~4 ms). It runs on slider ticks and
  seat changes; nothing calls it inside a match tick, and nothing should.

**And `islands` was retired from the lobby
(`D-20260828-a-map-a-player-can-pick-is-a-map-an-army-can-cross`, #280,
2026-08-28).** The preset generates good terrain and cannot host a match:
over 48 worlds it is **29-35% walkable across 12-268 disconnected
components**, and there is no naval movement, no transport and no bridge
anywhere in the game, so most of what it draws is scenery.

**It fails at TWO seats** — across twelve Standard worlds, a 1v1's two
starts landed on the same landmass in **three**. That is the number that
made this a retirement rather than a seat cap: the failure is not
crowding, it is water, so there is no seat count to cap at.

`TerrainPreset.playable` is the mechanism and it hides the preset from
`TerrainPresetRoster.ids()` — the one list both the lobby picker and the
server's option channel cycle — and from nothing else. `--preset=islands`
still generates one, every tuned number survives, and `all_ids()` is what
tooling means by "every preset". The day armies can cross water it is one
bool.

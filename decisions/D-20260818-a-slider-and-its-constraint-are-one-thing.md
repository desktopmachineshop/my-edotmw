# D-20260818 · 2026-08-18 · Accepted — a map slider and the rule that judges it are one definition, and "valid" means the world has ground on it

**Decision:** four clauses, all in `map_settings.gd` (#125).

1. **The beach is a BAND above the waterline, not a free parameter.**
   `MapSettings.beach_band` is stored; `beach_level` is derived and
   clamped as it is read. `apply_preset` takes the preset's own width, so
   every shipped preset generates exactly the world it generated before.
   The wire still carries the absolute level, because concrete numbers
   travel (D-049); `from_dict` recovers the band.
2. **`MapSettings.SLIDER_LIMITS` / `slider_bounds` / `set_slider` is the
   ONE definition of how far a map slider may travel.** `client.gd` asks
   it for a slider's extent and `MatchState.set_map_option` clamps
   through it. Sea level and the mountain line bound each other, so the
   ends MOVE as the other handle does.
3. **`MapSettings.validate` checks the world has ground on it**, not only
   that the thresholds are ordered — sampled on a fixed lattice
   (`walkable_fraction`), and refusing anything with less land than the
   two starting positions the same function already demands.
4. **The lobby says why a move was refused, at the moment it is
   refused.** The client judges the candidate settings with the same
   `MapSettings.validate` the server will; the server still validates
   again, because a slider is a suggestion from an untrusted client
   (D-002).

## Rationale

Reported by the owner from playing the lobby: moving sea level a little
past its preset value produced a configuration the server rejected, and
nothing on screen said which way was safe.

**Three sources of truth, each correct alone.** The ranges were a literal
table in `client.gd`, the clamps were a second copy of the same four
ranges in `MatchState.set_map_option`, and the constraints were a third
set of rules in `MapSettings.validate`. Nothing could fail until somebody
moved a handle, because every one of the three was a perfectly good
number on its own — the same shape as `UnitDef.damage` against
`BuildingDef.damage` (D-066), where the pair was meaningless and neither
half was wrong.

**What made the incoherence bite was a value no control showed.**
`validate` demanded `sea_level <= beach_level <= mountain_level`, and
`beach_level` was set by the preset and exposed by nothing. So the real
ceiling of the sea-level slider was the preset's hidden beach line:

| preset | beach_level | sea slider valid up to | invalid share of a 0.05–0.90 slider |
|---|---|---|---|
| `continents` | 0.44 | 0.44 | 54% |
| `highlands` | 0.36 | 0.36 | 64% |
| `islands` | 0.60 | 0.60 | 35% |
| `plains` | 0.27 | 0.27 | **74%** |

A beach is a strip along the shore. Storing where its far edge happened
to fall made it a free parameter that every other control had to work
around; storing its WIDTH makes it follow the water, which is the one
behaviour the word predicts. It is legal to derive it because the beach
is **biome only** — passability is decided by sea and mountain alone
(`TerrainGen.passability`) — so this moves colours and never moves where
a squad may walk. Same split as D-084's between the picture and the
simulation.

## The open question in #125, answered: yes

*"Does any slider combination pass `validate()` and still produce an
unplayable map?"* Measured before the check existed, on the shipped
Standard map (168 x 194) at seed 1337, with the beach placed legally so
that every threshold check passes:

| sea | mountain | walkable | spawn points found | old `validate()` |
|---|---|---|---|---|
| 0.05 | 0.98 | 100% | 8 of 8 | accepted |
| 0.50 | 0.98 | 43.4% | 8 of 8 | accepted |
| 0.70 | 0.98 | 1.9% | **2 of 8** | accepted |
| 0.80 | 0.98 | 0.4% | **0 of 8** | accepted |
| 0.85 | 0.98 | **0.0%** | **0 of 8** | accepted |
| 0.05 | 0.20 | **0.0%** | **0 of 8** | accepted |

(The 84 x 96 sweep behind the middle rows is in the same family; the
mountain-line end is symmetrical, because a walkable band pushed off
either end of the elevation distribution is empty for the same reason.)

Both dead ends are inside every slider's drawn travel, and the sliders
cannot be bounded away from them: whether a band leaves ground depends on
the seed and on the other two sliders, so it is not a range that can be
drawn. It is a property of the world, and the only honest place to test
it is against the world.

**Why a sampled estimate and not the real thing.** `TerrainGen.
passability` is O(cells) — ~130 ms on the shipped map, and `validate`
runs on every slider tick and every seat change. `walkable_fraction`
samples a `GROUND_SAMPLES_PER_AXIS` (32) lattice instead: ~4 ms, and a
fixed COUNT rather than a stride so it costs the same on an 8,064-cell
map and a 130,368-cell one — D-106's rule that a check which must not
scale with the map is written so that it cannot. Measured against the
full generation on 16 worlds (4 presets x 4 sizes) it agrees to within
0.012, and to within 0.001 in the thin cases it exists to catch. It runs
LAST of `validate`'s checks, the same order D-104's three spawn tests run
in and for the same reason.

**Why the threshold is two starts' worth of land.** `2 *
min_spawn_landmass` reuses D-104's own definition of how much ground a
start needs, and two starting positions is what `validate` already
demands one line above. It is necessary rather than sufficient — the land
could be scattered as islets — and deliberately no stricter: a shortfall
of starts on a map that HAS ground is already tolerated (the server warns
and the seated players share), and refusing a map for being *poor* rather
than *impossible* would be the server taking a decision that is the
player's.

## Rejected alternatives

- **Bound the sliders to what the shipped presets use, plus headroom**
  (#125's third suggested direction). It would have shrunk sea level to
  0.22–0.56 and landmass size to 1.6–4.5, and measurement says sea level
  0.6 is a perfectly good map — this would refuse worlds the generator
  makes well in order to avoid worlds it makes badly, and it still could
  not see the dead ends, which are not at fixed values.
- **A wire message carrying the server's refusal back to the lobby.** The
  client holds the same `MapSettings` class and can ask it directly, so a
  new packet would be a second implementation of a question already
  answerable locally. The server's own check stays, unchanged in
  authority.
- **Leaving `beach_level` free and adding a beach slider.** A fifth
  control to work around a coupling, rather than the coupling going away
  — and it would still have to be clamped against two neighbours.
- **Refactoring the walkable predicate into `TerrainGen`** so the sampler
  and `passability` share one line. Both O(cells) sites inline it for
  speed, and terrain meshing is already 5,071 ms at client start (#110) —
  not a file to add a per-cell call to for tidiness. The predicate is
  duplicated knowingly, and `test_map_slider_ranges.gd` compares the
  estimate against the real `passability` on four worlds so a drift in
  either fails loudly instead of quietly moving where the check bites.

## Consequences

- The sea-level slider is usable across its whole travel on every preset,
  up to the point where the world genuinely runs out of ground — and at
  that point the lobby says so, in the panel, as the handle moves.
- `validate()` now costs ~4 ms rather than microseconds. It is called on
  slider ticks and seat changes, never inside a match tick.
- **`beach_level` is no longer assignable.** Anything that used to set it
  sets `beach_band`; `from_dict` is the one place the wire's absolute
  level is turned back into a width.
- Every shipped preset is unchanged, at every map size, which is asserted
  rather than argued (`test_a_shipped_preset_keeps_its_beach_exactly_
  where_it_put_it`).
- The lobby's map panel gained a warning line. It is rebuilt with the
  rows, which is also what clears it: a refused change is one the server
  never echoes, so the message survives exactly as long as the settings
  that caused it.

## Revisit trigger

- A terrain preset that wants a beach somewhere other than a fixed band
  above its own waterline — at which point the band is the wrong model
  and the beach needs its own control, not its old freedom.
- `validate()` being called from anywhere per-tick, or the ~4 ms showing
  up anywhere it matters.
- A report of the ground check refusing a map somebody wanted. The
  threshold is two starts' worth of land and is deliberately the
  weakest defensible one; if it is ever wrong it will be wrong by being
  too strict on a legitimately watery map, and the number to look at is
  `min_spawn_landmass` rather than the multiplier.

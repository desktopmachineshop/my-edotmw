# D-20260828 · A map a player can pick is a map an army can cross

**Date:** 2026-08-28
**Status:** Accepted
**Issue:** #280, from the gap assessment (`docs/plans/gap-assessment.md` §1.5)

## Decision

**The lobby offers only presets a match can actually be played on, and
`islands` is not one of them.** `TerrainPreset.playable` is a new schema
field defaulting `true`; `islands.tres` sets it `false`;
`TerrainPresetRoster.ids()` — the one list both the lobby picker and the
server's `preset` option channel cycle — is filtered by it.

**Retired, not deleted.** `load_all()` and `by_id()` are deliberately
unfiltered, so `--preset=islands` still generates one for terrain work,
every tuned number in the file survives, and a saved setting naming it
still loads. `all_ids()` is the unfiltered list, for tooling and for
tests that mean "every terrain this generator can make".

**The naval decision is NOT taken here.** #280 offered two exits — retire
the preset, or write the naval decision — and this takes the first
because it is the one that can be taken on evidence. Naval movement is a
large design that touches pathing, formations, combat, the AI and the
economy, and nothing in the game today asks for it. The revisit trigger
below is what reopens `islands`.

## Rationale

### The measurement

Four presets × four sizes × three seeds (48 worlds), on `main` at
`cc2f4c6`. "Mainland" is the largest walkable component. "On main" is how
many of the sampled starts landed on it.

| preset | walkable | components | mainland share | 2 seats → on mainland | 8 seats | 20 seats |
|---|---|---|---|---|---|---|
| `plains` | 98.7–100% | **1** | 100% | 2 of 2 | 8 of 8 | 20 of 20 |
| `highlands` | 93.1–96.1% | 1–4 | 99.9–100% | 2 of 2 | 8 of 8 | 20 of 20 |
| `continents` | 72.3–77.5% | 3–58 | 99.3–99.9% | 2 of 2 | 8 of 8 | 20 of 20 |
| **`islands`** | **29.3–34.5%** | **12–268** | **7.8–67.4%** | **0–1 of 2** | **0–5 of 8** | **0–14 of 20** |

Two rows of that table decide it.

**`islands` is a third of a map.** 29–35% of its cells are walkable at
all, against 72–100% for every other preset. The rest is water, and there
is **no naval movement, no transport and no bridge anywhere in this
game** — so it is not "hard to cross", it is scenery.

**`islands` fails at TWO seats.** Across twelve Standard-size worlds, the
two starts of a 1v1 landed on the same landmass in **three**. The other
nine are a match in which neither player can reach the other, which under
D-033 cannot be decided by elimination and runs to the time cap — and the
game has no time cap in a real match, so it runs until somebody quits.

That last number is the whole argument, and it is why this is a
retirement rather than a seat cap.

### Why not gate it behind a seat count

That was the option the gap assessment itself floated, and the
measurement kills it: **the failure is not crowding, it is water.** A
seat cap fixes a map that runs out of room; `islands` does not run out of
room, it runs out of connected ground, and it does so at the smallest
seat count that exists. There is no number to cap at.

### Why not fix it in the generator

Raising `sea_level` down until the archipelago joins up produces
`continents`, which already ships. The preset's own summary — *"who
reaches whom is decided by the coastline"* — describes a game about naval
approach, and that game is the naval decision, not a tuning pass.

### Why this was invisible

Worth recording, because it is this project's most-repeated shape. Every
number `islands` produces is healthy: `spawn_points` returns 17–19 of 20,
`validate_spawns` passed (it compared counts — D-104), no start is on
water, and `gen-terrain-preview` draws a perfectly good archipelago. The
preset has shipped in the lobby since terrain presets existed and nothing
failed. What made it visible was
`D-20260827-every-start-shares-one-landmass` asking a question nobody had
asked — *does the component holding spawn A also hold spawn B* — and this
entry is that question pointed at the map list instead of at one map.

## Rejected alternatives

- **Delete `terrain/islands.tres`.** Throws away tuned numbers and a
  generator configuration that is genuinely useful for terrain work
  (`gen-terrain-shot`, coastline and beach-band checks), to save one
  bool. Retirement is reversible; deletion is a merge conflict away from
  being permanent.
- **Gate on seat count.** Rejected on the measurement above — it fails at
  two.
- **Gate on a computed playability score at lobby time.** Attractive, and
  the machinery nearly exists (`MapSettings.validate` already samples the
  world since #125, and D-20260827 already labels components). Rejected
  for now because it prices every slider tick at a full component walk —
  measured at 61.5 ms on the Huge map in D-20260827 — to answer a
  question that is a property of the PRESET rather than of the settings.
  If a fifth preset ever needs judging, this becomes the right shape.
- **Write the naval decision now.** Out of proportion. It is a
  multi-workstream design (transports, embark/disembark, naval combat,
  shore pathing, AI, an economy reason to want the sea) in service of one
  retired preset, and D-056's own lesson is that content is added because
  the match needs it, not because a map file exists.

## Consequences

- **The lobby offers three presets, not four.** `plains`, `highlands`,
  `continents` — all of which seat 20 of 20 on one landmass at every size
  and seed sampled. Map variety is unchanged in kind: the three that
  remain are the three anybody could actually play.
- **Nothing else changes.** `islands` still generates, still loads by
  name, still renders; no test that reasons about terrain loses its
  fixture, because `all_ids()` is the unfiltered list.
- **The lobby and the server cycle one list**, and a test forbids either
  side reaching past the filter with `all_ids()` — two lists is how a
  lobby comes to draw a choice the server refuses, which is #125 one
  field over.
- **`TerrainPreset` gains a field**, so this is a schema change under
  D-010; recorded here rather than in a comment.
- **A saved or scripted `--preset=islands` still works**, deliberately.
  Retiring a preset is a statement about what a player is OFFERED, not
  about what the generator can make.

## Revisit trigger

**Naval movement, transports, or any way for an army to cross water.**
That is the single condition under which `islands` becomes a map rather
than a picture of one, and flipping `playable` back is the whole of the
change. Note the same trigger already sits on
`D-20260827-every-start-shares-one-landmass`, which confines starts to
the mainland for the same underlying reason — if one fires, both should
be re-read together.

**And a smaller one:** if a future preset is added whose mainland is a
minority of its walkable ground, this entry's *reason* applies to it and
its `playable` value should be argued, not defaulted.

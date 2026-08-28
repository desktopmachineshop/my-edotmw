**Buildings research techs, and completing an epoch's defining line IS
the age-up** (`D-20260828-the-epoch-ladder` — THE ladder;
`D-20260827-the-tree-is-the-ladder` — the tech mechanism;
`D-20260827-a-research-site-is-a-building` — the sites; issues #206,
#278, #281).
There is no age-up button. The full tree — 65 techs, five rungs, every
name — is `docs/plans/tech-tree.md`; this page is what it means for
anything you are about to touch.

This is D-056's answer. That entry found the structural cause of
three-minute matches — *"there is no progression at all … so after
roughly three minutes there is nothing to do but fight"* — and said
explicitly not to reach an hour by tuning health. This is the
progression. **It does not claim to reach 90 minutes on its own**:
D-068's upkeep is still not built, and D-070's replacement rosters are
still not authored.

```
just test-unit tech          # 51 tests: 22 tree invariants, 29 effects
```

Eight things to know before touching any of it, and most are not about
techs:

- **An effect never reaches a call site.** A tech resolves a **per-player
  `UnitDef`**, and `SquadSim.add_squad` — the one place any path creates
  a squad — applies it. So the ~40 sites in `combat.gd`, `vision.gd`,
  `economy.gd` and `squad_sim.gd` that read `def.damage` off
  `_defs[squad]` are already correct, **not one of them changed**, and
  there is no forty-first that could be added having forgotten. The
  alternative — an `effective_damage(player, def)` helper called at each
  site — is the D-038 ownership cache with a new name: a rule that must
  be remembered everywhere.
- **`reapply_research` is what makes research retroactive**, and it
  re-computes `_speed` as well as re-pointing `_defs`. Speed is CACHED
  per squad, so a movement tech that moved the def and not the cache
  would be the declared-and-unread defect in its purest form: the def
  says the squad is faster and the squad walks at the old speed.
- **The effect vocabulary is CLOSED, and an unknown field is a LOAD
  ERROR.** A tech whose effect is a typo would cost resources, fill a bar
  and do nothing — the sixth instance of this project's most-repeated
  defect, and the first that would ship wearing a green verdict.
  `TechEffect.validate` probes the schema itself
  (`UnitDef.new().get(field)` answers null for a property that does not
  exist), so the permitted list cannot drift from the resource it
  describes without a test going red.
- **`squad_size`, `formation_shape`, `formation_spacing` and the model
  fields are fenced OUT, and that fence is the desync story.**
  `composition_hash` reads shape, spacing and files; `squad_size` is not
  replicated at all. A tech that moved any of them would put every client
  of the researching player in a different place with nothing able to
  notice — the M1 defect from D-022's audit block, rebuilt from parts. A
  test asserts the fence rather than trusting it. Widening the vocabulary
  is a decision-entry edit with the reason written down, never a quiet
  addition.
- **An enemy's research is not on the wire and must never enter a hash.**
  You are told your own lines and your allies' (D-050), and nothing else
  — it is exactly the thing a scout is for. The client resolves its OWN
  defs for cosmetic range hints and draws enemy squads from base defs,
  which is not an approximation but the correct answer.
- **Three civs cannot research mobility at all and two cannot research
  siege**, because a stables or a forge is simply a `.tres` they do not
  have. Gildedreach alone has both, which is its "economy & flexibility"
  axis expressed as structure instead of as a stat. The rule that keeps a
  hole from LOCKING a civ out of the ladder: a rung's **defining** line
  only ever sits on universal sites or on the civ's own buildings, and
  `test_every_civ_can_climb_every_rung` asserts it. **That check is not
  hypothetical** — the tree's first draft had a real cycle in it, where
  Windmarch's epoch-2 defining tech was researched at the Home Herd and
  the Home Herd required that same tech.
- **`BuildingSim.all_defs()` is no longer the right question**, and four
  callers had to change: the AI's building plan, the client's build menu,
  the load-test bots and the tests. Buildings are per-civ now (two
  archetypes of them), so `defs_for_civ` is what a player is offered.
  `BuildingDef.archetype` defaults EMPTY and falls back to the def's own
  id, which is why adding it edited none of the nine shipped building
  files.
- **The AI climbs, and the bots research too.** An AI that never
  researched would sit at epoch 1 against one that did, and every ladder
  number after this would measure that rather than the civs — D-107's
  failure, where ten minutes of nothing was read as an AI weakness for a
  whole milestone. `AI_STATS` gains `epoch=`, `techs=` and
  `techs_ordered=`, which separates **"it never asked"** from **"it asked
  and was refused"**: different faults, same symptom. The load-test bots
  research as well, and that is not a nicety — every archetype past the
  levy is gated now, so without it `just test-load` would field levies
  and gatherers for a whole run and touch the research path not at all.
  A gate landing and the harness quietly asserting less afterwards is
  this project's own recurring shape (#123's empty `raid_pool`,
  D-20260818's "the fast loop carries the gate"), so it is fixed here
  rather than discovered later.

**Every timing tuned against a no-progression match is stale**, per the
standing rule, and this is the largest instance of it the project has
had. `just ai-ladder`'s cap, `just test-load`'s duration and every
scenario's assumptions all move. `ScenarioDef.techs` exists so a scenario
can start mid-tree rather than being re-timed — grant the lines, and a
siege scenario reaches a siege engine.

**`war_footing` puts `squad_cap` back in `docs/status/civ-knobs.md`'s
worst-case arithmetic.** That page pins 880 squads at D-018's 20 players
and 1,056 at the lobby's 24 seats from `CivDef.squad_cap_bonus` alone. A
tech adding 6 per player moves both, and Windmarch's own line adds a
further 8. Re-read the ceiling off the current tree rather than quoting
those numbers.

## The ladder had three descriptions, and now has one

`decisions/` described three different ladders — D-069's five historical
rungs, D-20260823's four fantasy ones, and #206's defining-line
transition, the newest of which lived in an ISSUE rather than a file.
**`D-20260828-the-epoch-ladder` is the single description now** (#278):
the rung count, the verbs, the per-civ names and the advance-cost table
live there, and `epoch_def.gd`, `TechRoster.defining_lines`,
`ResearchState.epoch_of` and `TechDef.epoch`/`defining` all cite it.
`D-20260827-the-tree-is-the-ladder` keeps the tech MECHANISM — the
schema, the closed effect vocabulary, per-player def resolution, the fog
rule. **The two were split because they have different lifetimes**: the
rung count is an open owner call and the effect vocabulary is
architecture, and superseding one must not force a re-read of the other.

## The costs are now checkable, and they do not check out

`D-20260828-the-phase-table-has-numbers` (#281) put a measured rate under
D-068's phase table, which had six minute-ranges and **no rate at all** —
so every cost in the ladder had been authored against empty cells.
Measured through the real haul loop with the shipped crew:
**105 / 90 / 75 units per minute** at 2 / 5 / 10 cells from the drop-off.

Against that, **every rung's defining line costs under two minutes of the
income of the phase that pays for it**, and D-068 makes those phases 8 to
20 minutes long. The whole ladder is about seven minutes of banking in a
match designed to run ninety. D-069 required the gate to "cost enough
that paying it visibly means not fielding troops for a stretch"; it does
not. **The implied change is ×3 across the advance table, and it is
deliberately NOT applied here** — re-pricing is a balance call with a
playtest attached, it invalidates the `test-load` figures below, and
doing it in the same change as the measurement would make a later
regression impossible to attribute.

The same entry finally answers the open question `OPEN-QUESTIONS.md` has
carried since 2026-08-02: **at 20 players a long match DOES exhaust the
map, food first.** One civ's whole tree costs 10,200 food against a
20-start share of 10,180, and 5,060 gold against 5,760 — before a single
soldier. At four players nothing binds, which is why no load test noticed.
`tests/test_pacing.gd` is the instrument and prints all of it.

**The rung COUNT is an open owner call, and it was built to stay cheap.**
Five rungs ship, with D-069's verbs, because the six civs that actually
ship carry a five-stage arc table in `docs/plans/fantasy-civs.md` and
issue #206 names those five verbs — while D-20260823's four-rung arc
table is written for the Dominion/Warhost set that **does not ship**
(the same open naming tension `docs/status/fantasy-civs.md` records).
Collapsing to four is deleting one `EpochDef`, merging two rungs and
moving a `defining` flag on ten `.tres`, with **no script change**,
because no script names an epoch or a tech. That property is the whole
reason the disagreement is cheap rather than expensive.

**Deliberately not done:** upkeep (D-068), replacement rosters (D-070 —
this tree gates the 39 unit defs that ship rather than authoring the
70–100 a full ladder needs), per-civ walls or town centres, any strength
ordering between the six civs, and an epoch-scoped train UI. D-069
flagged unlock overload and D-074 owns detecting it; the tree makes it
real a rung earlier, and the build menu's existing category drill-down is
the surface that will have to absorb it.

## What the gate measured, and what it cost

`just test-load 4 300` on this tree, 2026-08-28, native bots against a
docker server: **`VERDICT ok`, 0 desyncs over 1,180 state-hash checks, 0
building desyncs, 0 dropped ticks**, all three `gate-check.sh`
comparisons green, and **173.44 µs/squad at 29 squads** (worst tick
121.5 ms). Quote it with its squad count, as ever — and now with its
roster, per `docs/status/fantasy-civs.md`.

⚠ **Every docker recipe needs `#223` fixed before anyone can repeat
this.** `just _import` is OOM-killed at the test service's `mem_limit:
1g` (exit 137), which takes `test-unit`, `test-load`, `test-scenario` and
`test-client` with it. The runs above were taken with that limit raised
locally to 2g, **uncommitted** — #223 owns the real fix. Unit tests were
run with `EDOTMW_RUNTIME=native`, where `test_recipe_args.gd` and
`test_gate_checks.gd` cannot fork a shell and fail for that reason alone
(the known gap #215 records).

**The bots research, and making them do so took three measured runs.**
This is worth writing down because the first two looked fine:

| run | verdict | squads | µs/squad | techs ordered |
|---|---|---|---|---|
| `4 300`, no reserve | ok | 35 | 127.86 | **0** |
| `4 480`, no reserve | ok | 46 | 131.30 | **0** |
| `4 300`, with reserve | ok | 29 | 173.44 | **3** |

Both of the first two are green runs in which the entire tech tree was
never touched. **It is structural, not a duration problem** — that is
what the 480 s run bought: a bot enqueues at every building every other
tick, so its wallet never simultaneously holds one tech's cost however
long the run is. Without the reserve, `test-load` would exercise
strictly LESS of the roster than it did before the tree, because every
archetype past the levy is gated now. That is #123's empty `raid_pool`
with a new cause, and it would have shipped behind a green verdict.

`techs_ordered=` and `techs_held=` are in the verdict for exactly that
reason — **metrics, not gates**, for `nodes_felled`'s reason: how long a
bot takes to afford a tech is a property of the map, the seed and the
duration, and gating on it would re-set D-031's stale-timing trap. A run
reporting `techs_held=0` means the coverage is gone whatever else is
green.

**The reserve costs load, and that is the trade.** Bots bank for their
first two techs once they have three hauling crews, which took squads
35 → 29 and `military_peak` 9 → 4 in a 300 s window. Bounded three ways
(after three crews so a bot cannot starve the economy that pays for it,
for two techs only, and never with nothing to bank for) — but a shorter
run now measures a slightly smaller army than it did. Read the squad
count, never the per-squad figure alone.

**The other thing the gate found is in the tree itself**: epoch 1's arc
tech came first, so the first researchable thing in the game cost 550 RP
and a clean 300 s run researched nothing at all. Epoch 1 is flipped now
(`hand_tools` has no prerequisite); epochs 2–5 keep arc-first, where the
arc tech IS the unit unlock. The line totals are unchanged, so D-069's
advance table and the test pinning it are intact.

**Owed:** a `just ai-ladder` run on this tree, at a cap well past the
600 s the last one used — a stronger opponent lengthens matches and a
truncated one reads as a draw, so quote the result **with its cap, its
squad count and now its roster**.

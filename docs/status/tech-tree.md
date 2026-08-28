**Buildings research techs, and completing an epoch's defining line IS
the age-up** (`D-20260827-the-tree-is-the-ladder`,
`D-20260827-a-research-site-is-a-building`, issue #206, 2026-08-27).
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
just test-unit tech          # 50 tests: 22 tree invariants, 28 effects
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

**Owed:** a `just ai-ladder` run on this tree, at a cap well past the
600 s the last one used — a stronger opponent lengthens matches and a
truncated one reads as a draw, so quote the result **with its cap, its
squad count and now its roster**.

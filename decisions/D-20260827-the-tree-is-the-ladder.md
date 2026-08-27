### D-20260827-the-tree-is-the-ladder · 2026-08-27 · Provisional — buildings research techs, and completing an epoch's defining line IS the age-up

**Decision:** The game gets a **civ tech tree**. Buildings research techs;
a researched tech modifies its owner's units, buildings and civ knobs
through a **closed vocabulary of declarative fields** (D-047 — knobs every
civ has, never a per-civ branch). **There is no age-up button.** An epoch's
`defining` techs are marked in the data, and a player advances to epoch
*N+1* at the moment the last defining tech of epoch *N* completes. The
tree IS the ladder; the ladder is not a thing beside it.

This supersedes **D-069's advance gate** ("a new `/epochs/*.tres`
(`EpochDef`) carrying … `cost_*`, `research_time` … researched at a town
centre") and **D-20260823's re-derivation of the same table at four
gates**. What it keeps from both is everything else: the verbs, the
shared-ladder rule, "no script may name an epoch", and the *total* cost of
an advance — which is now paid across a line of two techs rather than in
one lump. Issue #206.

---

#### Why the gate had to stop being a button

D-069's gate is a payment. A payment has exactly one decision in it — *now
or later* — and D-056's finding is that the game's problem is not that its
one decision arrives too early, it is that **there is no progression at
all**, so "after roughly three minutes there is nothing to do but fight."
A button does not fix that. It adds one moment of interest per rung and
leaves the other fourteen minutes as empty as they were.

A tree with a marked line through it costs the same resources and buys
four things a button cannot:

- **The line is a sequence, so an epoch has an interior.** In epoch 2 you
  are always part-way through something, and the thing you are part-way
  through is named after your civ's own story.
- **The branches are the choice.** Everything off the line is optional
  depth you buy instead of troops — D-068's row-2 fork ("bank toward the
  next epoch, or field levy troops now") reappears at every rung instead
  of once.
- **A civ without a research SITE cannot walk that branch** — which is
  civ identity expressed structurally, for free, with no knob
  (see `D-20260827-a-research-site-is-a-building`).
- **"Who is ahead" stays legible**, which is D-069's stated reason for a
  shared ladder: epoch is still one integer, still the same integer for
  everybody, and still derived from a rule nobody can opt out of.

---

#### The ladder: five rungs, D-069's verbs, the shipped civs' own arc

**Owner call outstanding, and the entry is written so it does not block on
it.** D-069 specified five rungs (settle / field / hold / break / decide);
D-20260823 superseded that with four (medieval → imperial → modern →
futuristic). Issue #206 names D-069's five verbs. The tie-break used here
is **which civs actually ship**: `/civs` holds the six of
`docs/plans/fantasy-civs.md` (Stoneblood, Gravesworn, Thornwood,
Windmarch, Gildedreach, Emberdeep), whose *own* five-stage arc table is
printed in that document and is the only per-civ epoch content that exists
for them. D-20260823's four-rung arc table is written for the
Dominion / Warhost / Centaurs / Deepholds / Gilded / Sylvans set, **which
does not ship** — `docs/status/fantasy-civs.md` records that naming
tension as deliberately open. Designing giant-kin and sylvan elves a
*futuristic* rung would be inventing content for civs on the strength of a
table written for different ones.

**The count is DATA, and that is what makes this cheap to overturn.**
Epochs are `/epochs/*.tres` and the line is a `defining` flag on each
`TechDef`. Collapsing to four rungs is deleting one `EpochDef` and moving
a flag on ten files — six of which are one civ each — with **no script
change at all**, because no script names an epoch or a tech. If the owner
prefers D-20260823's four, that is a data edit, not a redesign, and this
paragraph is the reason it was built that way.

| # | Epoch | Verb | The epoch is when… |
|---|---|---|---|
| 1 | The Founding | **settle** | …a place becomes possible. |
| 2 | The Mustering | **field** | …a standing army becomes possible; the counter triangle arrives whole. |
| 3 | The Holding | **hold** | …ground you keep becomes possible — stone, sight, and the speed to cover it. |
| 4 | The Breaking | **break** | …fortified ground becomes attackable again. |
| 5 | The Reckoning | **decide** | …scarce, decisive troops become possible. Every civ's signature is here or one rung below it. |

Each rung's **defining line is two techs**: one shared trunk tech every
civ researches, and one tech that is the civ's own arc line from
`docs/plans/fantasy-civs.md` Part 2, in the civ's own words. Epoch 5 has
no defining line — nothing is above it — so its arc tech is the payoff
rather than a gate. Full tree, all names, costs and effects:
`docs/plans/tech-tree.md`.

**Advance costs are D-069's table, split across the line**, so the total
price of a rung is the number that entry derived and this one does not
re-derive:

| Advance | food | wood | gold | stone | research | D-069's total |
|---|---|---|---|---|---|---|
| 1→2 | 500 | 300 | — | — | 90 s | ✔ unchanged |
| 2→3 | 800 | 500 | 200 | — | 120 s | ✔ unchanged |
| 3→4 | 1200 | 800 | 500 | — | 150 s | ✔ unchanged |
| 4→5 | 1800 | 1200 | 900 | 400 | 180 s | ✔ unchanged |

Provisional, to be replaced by telemetry, exactly as D-069 said.

---

#### The schema, logged against D-010

**New resource: `TechDef` (`tech_def.gd`, `/techs/*.tres`).** It is
`UnitDef`'s structural sibling and deliberately reads like one — the
`archetype` / `civ` split is copied verbatim, because it is the mechanism
that keeps every script civ-agnostic (D-047).

| Field | Type | Default | Purpose |
|---|---|---|---|
| `id` | `StringName` | — | file-unique, e.g. `emberdeep_the_shieldwall` |
| `display_name` | `String` | `""` | the in-world name a player reads |
| `description` | `String` | `""` | flavour; what it means, not what it does |
| `line` | `StringName` | — | **the shared mechanical identity** — `UnitDef.archetype`'s exact analogue. Prerequisites, unit gates and the defining line all name a LINE, never an id. |
| `civ` | `StringName` | `&"neutral"` | `neutral` is the shared trunk: one file, every civ gets it. A per-civ file shadows it for that civ. |
| `epoch` | `int` | `1` | earliest epoch at which research may START |
| `defining` | `bool` | `false` | completing every defining tech of epoch *N* advances the player to *N+1* |
| `research_at` | `StringName` | `&"town_centre"` | the building **archetype** that researches it |
| `requires` | `Array[StringName]` | `[]` | prerequisite LINES |
| `cost_food/wood/gold/stone` | `int` | `0` | |
| `research_time` | `float` | `30.0` | seconds, scaled by `CivDef.production_time` like a unit's |
| `unit_effects` | `Array[TechEffect]` | `[]` | |
| `building_effects` | `Array[TechEffect]` | `[]` | |
| `civ_effects` | `Array[TechEffect]` | `[]` | |

**New sub-resource: `TechEffect` (`tech_effect.gd`)** — the pattern
`ScenarioSquad` and `ScenarioBuilding` already set for sub-resources of a
`.tres`.

| Field | Type | Default | Purpose |
|---|---|---|---|
| `target` | `StringName` | `&"*"` | a unit ARCHETYPE, a building ARCHETYPE, or `*` for every one |
| `field` | `StringName` | — | the stat, from the **closed list** below |
| `mode` | `"add" \| "multiply"` | `"add"` | |
| `value` | `float` | `0.0` | |

**Additions to existing schemas, all defaulting to "unchanged":**

| Field | Type | Default | Purpose |
|---|---|---|---|
| `UnitDef.requires_tech` | `StringName` | `&""` | a tech LINE; empty means always producible |
| `BuildingDef.requires_tech` | `StringName` | `&""` | ditto |
| `BuildingDef.archetype` | `StringName` | `&""` | `UnitDef.archetype`'s analogue; empty falls back to `id`, so every shipped def keeps its meaning without being edited |
| `CivDef.epoch_names` | `Array[String]` | `[]` | five display strings (D-070 proposed this; it lands here) |
| `ScenarioDef.techs` | `Array[StringName]` | `[]` | LINES granted at scenario start |

**Deliberately NOT added: `UnitDef.epoch` / `BuildingDef.epoch`** (D-070
proposed both). Two gates on one question is one too many, and the pair
would be free to disagree — the D-058/D-065 family, which this project has
now paid for four times. **Epoch gates TECHS; techs gate everything
else.** A unit names the tech that frees it and nothing else, so there is
exactly one answer to "may I build this" and one place it is written.

---

#### The closed field vocabulary, and why the fence is the interesting part

A `TechEffect.field` outside these lists is a **load error**, not a
silently-ignored line. That is the whole point: this project's
most-repeated defect is a declared field that nothing reads (D-055, D-106,
#158 — four instances and counting), and a tech whose effect is a typo
would be a fifth wearing a green verdict.

**Unit fields (permitted):** `damage`, `health`, `attack_range`,
`attack_interval`, `move_speed`, `vision_range`, `morale`,
`morale_recovery_per_second`, `rout_threshold`, `rout_rally_margin`,
`damage_vs_buildings`, `gather_rate`, `carry_capacity`, `cost_food`,
`cost_wood`, `cost_gold`, `cost_stone`, `build_time`.

**Building fields (permitted):** `max_health`, `damage`, `attack_range`,
`attack_interval`, `vision_range`, `build_time`, `no_build_radius`,
`top_range_bonus`, `top_vision_bonus`, `cost_food`, `cost_wood`,
`cost_gold`, `cost_stone`.

**Civ fields (permitted):** `squad_cap_bonus`, `production_speed`,
`gather_speed` — the three D-20260823 wired up. A tech raising one of them
goes through `CivDef`'s applied functions like everything else does.

**Forbidden, each for a stated reason:**

- `squad_size`, `formation_shape`, `formation_spacing` — the client
  derives soldier geometry from these and `composition_hash` reads
  `shape`, `spacing` and `files`. Spacing and shape happen to be
  replicated (D-058/D-065), so a tech touching them would *probably* be
  safe; `squad_size` is not replicated at all and would desync every
  client of the player who researched it. The three are fenced together
  because "probably safe" is not a thing to leave on the near side of a
  wire boundary.
- `model_id`, `slot_models`, `model_mix`, `mesh_primitive` — the client
  resolves these itself from (civ, archetype), so a server-side change
  would draw a different army from the one that exists.
- `armour_class`, `bonus_vs` — D-032's counter triangle is a design
  invariant, not a stat. And `bonus_vs` is a Dictionary: "add 0.3" has no
  meaning without naming a key, which is a second schema this vocabulary
  does not want.
- `archetype`, `civ`, `id`, `is_general` — identity. A tech that changed
  what a unit *is* would break every lookup keyed on it.

---

#### How an effect reaches the simulation: resolve the def, change nothing else

**A researched tech produces a RESOLVED `UnitDef` per (player,
archetype), and every existing reader is already correct.** `SquadSim`
holds `_defs[squad]` — a `UnitDef` reference per squad — and
`combat.gd`, `vision.gd`, `economy.gd` and `squad_sim.gd` read `def.damage`,
`def.vision_range`, `def.move_speed` and the rest off that reference at
roughly forty sites. Handing those sites a duplicated def with the
modifiers already baked in means **not one of the forty changes**, and
there is no per-site "and now apply the player's techs" that a
forty-first site could forget.

`TechEffects.resolve(base, lines, civ)` is the one definition, all-static
and pure in `formation.gd`'s style, memoised per (player, archetype) and
dropped when that player completes a tech.

**Techs are RETROACTIVE.** On completion the server re-resolves and
re-points `_defs` for every squad the player owns, so a research finishing
mid-battle is felt in that battle. This is the genre norm and it is what
makes the mid-game decision feel like a decision. It is safe precisely
*because* of the fence above: `alive` is an integer the tech cannot touch,
`health` is read per damage application, and nothing the client derives
geometry from is in the vocabulary.

**Fog: your techs are yours.** A player is sent their own researched lines
and their own epoch, and their allies' (D-050 shares a front). **An
enemy's are not sent, and must never enter `composition_hash`** — the
server hashes `visible_to(player)` and a client hashing an upgrade it was
never told about would desync a perfectly healthy system, which is D-099's
ghost rule pointed at a different field. The client resolves its OWN defs
through the same `TechEffects` call for cosmetic range and pursuit hints;
enemy squads draw from base defs, which is not an approximation but the
correct answer — **you do not know what they have researched until you
meet it.**

---

#### Research occupies the site

A building either trains or researches, never both — D-069's "occupying it
for the duration", which is also what stops the tree being free. It is the
existing production queue carrying one more kind of entry, rather than a
second queue beside it: two queues would need two definitions of
"is this building busy", and D-047's `production_time` would have to be
applied in both.

A tech is researched **once per player**, not once per building, and a
second building may not start one already complete or in progress.

---

#### Rejected alternatives

- **Keep D-069's age-up button and add a tech tree beside it.** Rejected —
  two progression systems, and the button is the weaker one. It also
  re-opens "which of these two do I pay first" as a decision that is
  really a UI question.
- **`UnitDef.epoch` as the availability gate** (D-070's proposal).
  Rejected — everyone climbs, so an epoch gate is not a decision, and
  issue #206 asks specifically for the signature units to sit behind a
  *tech* so the mid-game has one. Kept as the coarse gate on TECHS, where
  it is the ladder rather than a duplicate of it.
- **Effects as a `Dictionary` of field→value on `TechDef`.** Rejected —
  a dictionary cannot be validated at load without the same closed list,
  and it cannot express `multiply` and `add` on one field or target a
  single archetype without inventing a key-encoding grammar.
- **Per-tech GDScript hooks.** Rejected outright: it is the per-civ branch
  D-047 exists to forbid, wearing a different noun.
- **Techs apply only to newly produced squads.** Rejected — it makes every
  research a decision about *the next twenty minutes* rather than about
  the fight in front of you, and it needs a second def per squad-vintage,
  which is per-squad state the resolve-and-re-point design does not have.
- **Send every player's epoch to everybody.** Rejected — it is exactly the
  information a scout is for, and D-102 already settled the shape of this
  question for army size.

---

#### Consequences

- **Every timing tuned against a no-progression match is stale**, per the
  standing rule, and this is the largest instance of it the project has
  had: `just ai-ladder`'s cap, `just test-load`'s duration and every
  scenario's assumptions all move. `ScenarioDef.techs` exists so a
  scenario can start mid-tree rather than being re-timed.
- **The AI must climb the tree or the ladder cannot exercise it.** An AI
  that never researches would be an AI permanently at epoch 1 fighting one
  that is not, and every ladder number after this would measure that
  instead of the civs. The research policy is a `AiProfileDef` knob
  (`research_bias`), and `just test-ai-teams`-style vacuity gates apply:
  a run in which no seat researched anything fails rather than reporting a
  draw. This is #119's finding — *the configuration nothing runs is the one
  that breaks* — applied before rather than after.
- **`squad_cap` is now reachable by a tech**, which puts it back in
  `docs/status/civ-knobs.md`'s worst-case arithmetic. The tech tree's
  cap-raising techs must be counted there, not just `CivDef.squad_cap_bonus`.
- **The build menu and the HUD grow a research surface.** D-069 already
  flagged unlock overload; the tree makes it real one rung earlier.
- **D-068's upkeep is NOT delivered here and D-070 says it is
  load-bearing** — "without upkeep, replacement rosters manufacture
  trash." This tree does not replace rosters (it gates the roster that
  already ships), so the specific trap D-070 names is not sprung; but the
  90-minute target still needs upkeep, and this entry does not claim to
  reach it alone.
- **Rosters still do not grow by replacement** (D-070). The shipped 39
  unit defs are gated across five rungs rather than 70–100 defs being
  authored. That is a deliberate scope line, not an oversight: the tree
  can be played and measured before the content bill is paid.

---

#### Revisit trigger

D-069's, unchanged, restated for techs: **any rung a player enters and
leaves without their behaviour changing is a stat bump, not an epoch.**
And one of this entry's own: **the first tech whose effect cannot be
expressed in the closed vocabulary.** The honest response to that is to
widen the vocabulary in this file with the reason written down — never a
hook, and never a field the validator does not know.

---

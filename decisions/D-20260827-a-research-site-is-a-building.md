### D-20260827-a-research-site-is-a-building · 2026-08-27 · Provisional — the stables and the forge, and why three civs cannot have one

**Decision:** A tech is researched **at a building archetype**
(`TechDef.research_at`, `D-20260827-the-tree-is-the-ladder`), so the shape
of a civ's tech tree follows the shape of its building list. Two new
building archetypes ship with the tree:

- **`stables`** — the mobility branch. Speed, vision, reach on the move,
  and the mounted units themselves.
- **`forge`** — the metallurgy-and-siege branch. Weapon damage,
  `damage_vs_buildings`, and the engines.

Both are **per-civ `.tres` with per-civ names**, and **a civ that does not
field one simply has no file for it** — at which point the branch hanging
off it does not exist for that civ, with no knob, no flag and no code
anywhere knowing why. Issue #206.

This needs one schema addition: **`BuildingDef.archetype`**, `UnitDef`'s
analogue, so `produces`, `built_by`, `research_at` and the build menu can
name a building type without naming a civ's version of it.

---

#### Who has what, and why the holes ARE the identity

| civ | stables — what they call it | forge — what they call it |
|---|---|---|
| **Stoneblood** | — | **the Breaking Yard** |
| **Gravesworn** | — | **the Bone Kiln** |
| **Thornwood** | **the Stag Glade** | — |
| **Windmarch** | **the Home Herd** | — |
| **Gildedreach** | **the Hiring Yard** | **the Contract House** |
| **Emberdeep** | — | **the Deep Forge** |

Every one of those holes is already written down in
`docs/plans/fantasy-civs.md` as a stated weakness, and each is now a
structural fact rather than a sentence in a design doc:

- **Stoneblood** — *"No cavalry, no engines — a giant is his own siege
  train."* No stables. Its forge is a **Breaking Yard**, because giant-kin
  do not forge: they quarry, and what comes out of the yard is a
  Gatebreaker, not a machine.
- **Gravesworn** — *"No cavalry."* The dead do not ride. Its forge is a
  **Bone Kiln**, because the Carrion Hurler is grown and fired, not
  hammered.
- **Thornwood** — *"No siege of any kind — the civ's stated hole."* No
  forge. Its stables are a **Stag Glade**, which is not a building that
  keeps animals so much as a place the animals agree to be.
- **Windmarch** — *"No siege, no heavy foot."* No forge. Its "stables" are
  the **Home Herd**: centaurs do not stable mounts, they *are* the mounts,
  and the Home Herd is where the clan foals and where a clan's speed is
  taught.
- **Gildedreach** — **has both, and is the only civ that does.** That is
  *"economy & flexibility"* and *"the broadest roster"* expressed as
  structure instead of as a stat: it buys its horses (**Hiring Yard**) and
  hires its engineers (**Contract House**) rather than raising or forging
  either.
- **Emberdeep** — *"No cavalry; lowest move speeds in the game."* No
  stables. The **Deep Forge** is the civ.

**Three civs cannot research mobility at all and two cannot research
siege.** That is the sharpest asymmetry in the game and it costs one
absent file per hole.

---

#### The rule that keeps the holes from breaking the ladder

**A defining tech's LINE must resolve for every civ, and a test asserts
it.** If the epoch-4 defining tech lived at the forge, Thornwood and
Windmarch could never leave epoch 4 — a civ locked out of the ladder by
its own identity, which is not asymmetry, it is a bug with a story
attached.

So the spine and the branches are separated on purpose:

- **The spine** — the defining line of every rung — lives only at
  **universal sites**: the town centre, the storehouse and the barracks,
  which every civ has. A civ's own arc tech may sit at any site *it* owns,
  because it is authored per civ and its author can see which buildings
  that civ has.
- **The branches** — the optional depth you buy instead of troops — are
  where `stables` and `forge` live. Missing one costs a civ *options*,
  never *progress*.

This is the same reasoning D-069 used for a shared ladder ("it breaks the
shared advance gate that makes 'who is ahead' legible"), applied one level
down.

---

#### `BuildingDef.archetype`, and why it defaults to empty

`UnitDef` has carried `archetype` since D-047 and `BuildingDef` never did,
because until now every building was `civ = &"neutral"` and its `id` was
its type. A per-civ stables breaks that: `research_at` cannot name
`emberdeep_deep_forge` without a script or a `.tres` learning a civ id,
and the build menu would show a player six civs' stables.

```
@export var archetype: StringName = &""      # empty ⇒ this def's own id
```

**Empty falling back to `id` is what makes the migration free.** Every one
of the nine shipped `.tres` keeps its exact current meaning without being
edited: `barracks.tres` has archetype `barracks` because its id is
`barracks`. `produces`, `built_by` and `upgrade_from` already name ids
that are also archetypes, so none of them move. The only defs that set the
field explicitly are the seven new ones, whose ids must differ (one
directory, six civs) and whose type must not.

`BuildingRoster.for_civ_archetype(civ, archetype)` is
`UnitRoster.for_civ_archetype`'s exact sibling, including the
`neutral`-is-available-to-everyone rule and including the trap that came
with it: **a neutral def SHADOWS a per-civ one** if it sorts first, which
is how a whole feature went quietly absent in
`D-20260823-the-opening-is-a-crew-and-a-general`. There is therefore **no
neutral `stables.tres` or `forge.tres`** — a civ has its own or has none,
and a test asserts that no `stables` or `forge` def is neutral.

---

#### What the two buildings are, mechanically

Both are ordinary `BuildingDef`s. Neither shoots, neither is a drop-off,
both are built by gatherers, both are `military` category.

| | stables | forge |
|---|---|---|
| `max_health` | 900 | 1100 |
| `build_time` | 45 s | 55 s |
| cost | 180w 60g | 150w 120s |
| `no_build_radius` | 3 | 3 |
| `vision_range` | 14 | 12 |
| `requires_tech` | the epoch-2 defining trunk line | the epoch-3 defining trunk line |
| produces | that civ's mounted archetypes | that civ's siege archetypes |

The costs are deliberately **asymmetric in KIND** rather than in size —
stables cost gold and forges cost stone — so the two branches pull a civ's
economy in different directions and a civ with both (Gildedreach) is
paying for the privilege in both currencies rather than getting breadth
free.

**Mounted and siege production MOVES to them.** Today `barracks.produces`
lists the union of every archetype in the roster, which is why the build
menu already copes with a civ that fields none of a thing. Cavalry,
bowriders and stag riders move to `stables`; engines, rams, bombards and
Gatebreakers move to `forge`. This is the second half of "a civ without
the building cannot walk that branch" — without it, the branch is optional
and the *units* are not, so a Thornwood player would still be fielding
engines they have no forge for. (They field none today, so the move costs
Thornwood nothing; it costs Emberdeep a 55-second building before its
Deepram, which is the point.)

---

#### Rejected alternatives

- **One neutral `stables.tres` and `forge.tres` for everybody, gated by a
  `CivDef` boolean.** Rejected — that is a per-civ branch wearing a knob's
  clothes (D-047), and it throws away the per-civ *names*, which is where
  the identity actually reads. A Home Herd and a Deep Forge are not the
  same building with a different label; one is a nursery and one is an
  industry.
- **Research at the town centre for everything.** Rejected — it deletes
  the structural asymmetry entirely, and it makes the town centre the
  single busiest building in the game while D-069 wants research to
  *occupy* its site.
- **A `research_sites: Array` on `CivDef`.** Rejected for the reason the
  unit roster is not a field on `CivDef` (`civ_def.gd`'s own header): a
  register that can disagree with the files. Which buildings a civ has is
  derived from which `.tres` name it, and there is nowhere for a second
  answer to live.
- **Give every civ both, and differentiate by stats.** Rejected — it is
  the "mechanism correct, shipped numbers do nothing" failure (D-066)
  chosen deliberately. An absent building is felt; a forge with 10% worse
  numbers is not.

---

#### Consequences

- **The build menu gains two entries and the roster gains seven files.**
  `BuildingSim.all_defs()` is currently unfiltered by civ — every civ sees
  every building — so it needs the same `_available_to` filter
  `UnitRoster` has, or a Thornwood player is offered a Deep Forge. That
  filter is new behaviour on a function four other callers use (the AI,
  the client menu, the placement ghost, the tests) and each has to be
  checked, not assumed.
- **The AI must learn to build them**, or three civs' branches are
  unreachable in every automated exercise the project has — the walls
  precedent, where *"no AI builds or uses walls, so `just ai-ladder`
  cannot exercise any of this feature"* has stood for two milestones.
- **`docs/status/fantasy-civs.md`'s "deliberately not done: per-civ
  walls/buildings" line stops being true**, for exactly two archetypes.
- **Any scenario placing a siege squad now needs the forge to exist or the
  squad to be granted directly.** `Scenario.apply_player` adds squads
  through `SquadSim.add_squad` and never through production, so shipped
  scenarios are unaffected — but a scenario that expected a player to
  *train* siege is not.

---

#### Revisit trigger

**The first civ that wants a third research site**, or the first tech that
wants to be researched at a building two civs call by names that are not
equivalents. Either means `research_at` should name a *branch* rather than
a building archetype, and the branch should name its sites — one more
indirection, worth taking only when something asks for it.

And the honest one: **if the ladder shows a civ without a forge losing
every match after epoch 4**, the asymmetry is not identity, it is a hole,
and the fix is that civ's own break-tech being worth more — not a forge
for everybody.

---

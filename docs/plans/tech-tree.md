# The Tech Tree — five rungs, six stories (design product)

Status: **IMPLEMENTED** as of 2026-08-27 (issue #206) — see
`docs/status/tech-tree.md` for what shipped and what it means for the
rest of the estate. The mechanism and its schema are decided in
`decisions/D-20260827-the-tree-is-the-ladder.md`; the research sites are
`decisions/D-20260827-a-research-site-is-a-building.md`. This document is
the CONTENT: every tech, its in-world name for every civ that flavours it,
its mechanical effect as a declarative knob, where it is researched, what
it costs, and which techs are marked as an epoch's **defining line**.

Issue #206. Written against the six civs that actually ship
(`docs/plans/fantasy-civs.md`) and the rosters in `/units` as they stand —
**this tree gates the roster that exists; it does not add units.**

---

## Part 1 — How to read this

**A tech has a LINE and a CIV**, exactly the way a unit has an archetype
and a civ (D-047). The line is the mechanical identity — `masonry`,
`breaking`, `siegecraft` — and it is what prerequisites, unit gates and
the defining line all name. A `civ = neutral` tech is the **shared trunk**:
one file, every civ researches it, same name for everybody. A per-civ tech
**shadows** the trunk for that civ: the same knob, wearing that civ's name
and its myth.

So `siegecraft` is one line and four files, and it is called *Quarried
Heads* by Stoneblood, *Grave-tar Payloads* by Gravesworn, *Engineers'
Retainer* by Gildedreach and *Runeforged Charges* by Emberdeep. One schema
field, four `.tres`, and no script has learned a civ id.

**Every effect below is a `TechEffect`** — `target` (a unit or building
archetype, or `*` for all), `field` (from the closed list in the decision
entry), `mode` (`add` or `multiply`), `value`. Anything this document
describes that is not expressible that way is a bug in this document.

**Notation:** `×1.12` is `multiply`, `+4` is `add`. **★** marks a civ's
signature unit from the frame table. **▣** marks a tech on an epoch's
**defining line**.

---

## Part 2 — The ladder, and the shape of a rung

| # | Epoch | Verb | The epoch is when… |
|---|---|---|---|
| 1 | **The Founding** | settle | …a place becomes possible. |
| 2 | **The Mustering** | field | …a standing army becomes possible. |
| 3 | **The Holding** | hold | …ground you keep becomes possible. |
| 4 | **The Breaking** | break | …fortified ground becomes attackable again. |
| 5 | **The Reckoning** | decide | …scarce, decisive troops become possible. |

**Every rung has the same shape, and the order is forced by
prerequisites:**

```
   ┌─ the ARC tech ─────────────┐   the civ's own story, expensive,
   │  ▣ defining                │   and it unlocks this rung's unit
   └────────────┬───────────────┘
                │ requires
   ┌────────────▼───────────────┐   the shared trunk, cheaper,
   │  ▣ the TRUNK tech          │   and completing it advances the epoch
   └────────────────────────────┘
        ...and hanging off the arc tech, the BRANCHES:
        optional depth bought instead of troops.
```

**The arc tech comes first on purpose — from epoch 2 up.** It is what
unlocks the rung's new troops, so a player gets the toy in the *first
half* of the rung and plays with it, rather than receiving it as a parting
gift on the way out. The trunk tech is the consolidation you do afterward,
and completing it is the age-up — there is no button.

**Epoch 1 is deliberately the other way round, and that was found by
running the gate rather than by arguing.** E1's arc tech unlocks no unit
(the levy, the crew and the general are all free), so arc-first buys
nothing there and costs the whole opening its accessibility: with
`hand_tools` behind `settling`, the FIRST researchable thing in the game
was a 550-RP commitment, and a `just test-load 4 300` run came back with
every gate green and **not one tech researched by anybody**. D-068 wants
the opening to be economic and the *expansion* row to carry the first
real fork — an opening in which nothing is affordable is not economic, it
is empty. So in epoch 1 `hand_tools` has no prerequisite and `settling`
requires it. **The line's total is unchanged** (500f 300w, 90 s), which is
what keeps D-069's advance table intact and the sum test green.

**The defining line is two techs and both are on universal sites or the
civ's own.** A defining tech is never gated behind a building some civ
does not have; that rule and its reasoning are in
`D-20260827-a-research-site-is-a-building`.

**Epoch 5 has no defining line** — nothing is above it. Its arc tech is
the payoff.

### Pacing, against D-068's six-phase table

D-068 is the derivation base and this is the row-by-row map onto it. A
number here that cannot be traced to a row there is unjustified.

| D-068 phase | min | Epoch | What the player is deciding, in the tree |
|---|---|---|---|
| Opening | 0–8 | 1 | Site quality vs safety, unchanged. Hand Tools is affordable almost at once; the arc tech is not. |
| Expansion | 8–22 | 1→2 | **The fork D-068 names**: finish the settle line now, or field levy troops with the same 500 food. |
| First contact | 22–35 | 2 | Your civ's second archetype has just arrived and the counter triangle is live. Drill, or more of them? |
| Consolidation | 35–55 | 3 | The hold arc tech, and the first branch worth having — stables if you have one, masonry if you do not. |
| Mid-war | 55–75 | 3→4 | Siege. *An investment that does not defend you* — the forge and its two branches are the largest sink in the game. |
| Decision | 75–95 | 4→5 | The Reckoning. The signature is one tech away and it is the most expensive thing on the board. |

**D-056's acceptance test — "something to DO after minute three" — is met
at minute one and never lapses**: at every point in the table above there
is a named, priced, in-world thing being researched, and refusing to
research is itself the fork.

---

## Part 3 — The research sites

| site | archetype | universal? | what it researches |
|---|---|---|---|
| Town centre | `town_centre` | ✔ | settlement, gathering, the civ's founding |
| Storehouse | `storehouse` | ✔ | haulage, supply |
| Barracks | `barracks` | ✔ | drill, discipline, morale, sapping |
| **Stables** | `stables` | ✗ (3 of 6) | mobility: speed, vision, mounted troops |
| **Forge** | `forge` | ✗ (4 of 6) | metallurgy and siege |

| civ | stables | forge |
|---|---|---|
| Stoneblood | — | **the Breaking Yard** |
| Gravesworn | — | **the Bone Kiln** |
| Thornwood | **the Stag Glade** | — |
| Windmarch | **the Home Herd** | — |
| Gildedreach | **the Hiring Yard** | **the Contract House** |
| Emberdeep | — | **the Deep Forge** |

**Gildedreach is the only civ with both**, and every other civ is missing
exactly one. That is the frame's *economy & flexibility* axis expressed as
structure rather than as a stat, and it is worth saying plainly: three
civs cannot research mobility **at all**, and two cannot research siege
**at all**. The full argument, and the rule that keeps a hole from
blocking the ladder, is in the decision entry.

Both buildings are built by gatherers, `category = military`, and neither
shoots. Stables cost gold; the forge costs stone — the branches pull a
civ's economy in different directions, and the civ with both pays in both
currencies.

| | stables | forge |
|---|---|---|
| cost | 180w 60g | 150w 120s |
| build time | 45 s | 55 s |
| max health | 900 | 1100 |
| requires | `settling` (the E1 arc) | `mustering` (the E2 arc) |
| produces | that civ's mounted archetypes | that civ's siege archetypes |

**Mounted and siege production MOVES to them** — `cavalry`, `bowriders`
and Thornwood's stags to the stables; `engine`, `ram`, `bombard` and
Stoneblood's `breaker` to the forge. Without that move the *branch* is
optional while the *units* are not, and a civ with no forge would still be
fielding engines.

---

## Part 4 — The trunk

Shared techs, `civ = neutral`, one file each, the same name for every
player. The four **▣** techs are the trunk half of each defining line.

### Epoch 1 — The Founding

| line | name | site | requires | cost | time | effect |
|---|---|---|---|---|---|---|
| ▣ `hand_tools` | **Hand Tools** | town centre | — | 150f 100w | 30 s | `gatherers` `gather_rate` ×1.10, `build_time` ×0.92 |
| `wide_baskets` | **Wide Baskets** | storehouse | `hand_tools` | 120f 80w | 25 s | `gatherers` `carry_capacity` +4 |
| `waymarks` | **Waymarks** | town centre | `hand_tools` | 100f 60w | 25 s | `gatherers` `vision_range` +4, `move_speed` ×1.08 |

*`hand_tools` is the only tech in the tree with no prerequisite at all —
it is where every civ's game starts, and at 150f 100w it is affordable in
the first couple of minutes. Everything else in epoch 1, the civ's own
settlement tech included, hangs off it.*

*Waymarks is the cheapest tech in the game and it is quietly one of the
best: D-087 put 3,413 wood nodes on the shipped map and a crew that can
see the next tree walks less.*

### Epoch 2 — The Mustering

| line | name | site | requires | cost | time | effect |
|---|---|---|---|---|---|---|
| ▣ `drill` | **Drill** | barracks | `mustering` | 250f 150w 50g | 40 s | `*` `damage` ×1.08 · `*` `attack_interval` ×0.96 |
| `hardened_kit` | **Hardened Kit** | barracks | `mustering` | 200f 150w | 35 s | `*` `health` ×1.12 |
| `standards` | **Standards** | barracks | `mustering` | 180f 120w 60g | 35 s | `*` `morale` +10 · `*` `morale_recovery_per_second` ×1.25 |

*`Standards` does nothing for Gravesworn, whose every def carries
`rout_threshold 0` and `morale_loss_per_casualty 0` — the deathless court
has no morale to steady. That is not an oversight to fix; it is the
fearless identity costing them a trunk tech, which is the kind of
asymmetry that comes free once effects are declarative.*

### Epoch 3 — The Holding

| line | name | site | requires | cost | time | effect |
|---|---|---|---|---|---|---|
| ▣ `masonry` | **Masonry** | town centre | `holding` | 400f 300w 150g | 50 s | buildings `*` `max_health` ×1.20 · buildings `*` `build_time` ×0.90 |
| `watchfires` | **Watchfires** | town centre | `holding` | 300f 250w 100g | 45 s | buildings `*` `vision_range` +4 · `tower` + `town_centre` `attack_range` +1 |
| `deep_stores` | **Deep Stores** | storehouse | `holding` | 350f 200w 150g | 45 s | civ `gather_speed` ×1.10 |

### Epoch 4 — The Breaking

| line | name | site | requires | cost | time | effect |
|---|---|---|---|---|---|---|
| ▣ `sapping` | **Sapping** | barracks | `breaking` | 600f 400w 300g 150s | 60 s | `*` `damage_vs_buildings` +0.10 |
| `sharpened_steel` | **Sharpened Steel** | barracks | `breaking` | 450f 350w 250g 150s | 55 s | `*` `damage` ×1.10 |

*`sharpened_steel` is at the BARRACKS and not the forge, deliberately: a
flat damage tech gated behind a building four civs of six have would hand
those four a permanent edge in every fight, which is not what "no forge"
is supposed to cost. What the forge gates is siege, and only siege.*

### Epoch 5 — The Reckoning

| line | name | site | requires | cost | time | effect |
|---|---|---|---|---|---|---|
| `veterancy` | **Veterancy** | barracks | `reckoning` | 700f 500w 400g 200s | 90 s | `*` `health` ×1.12 · `*` `morale` +15 · `*` `rout_rally_margin` ×0.80 |
| `war_footing` | **War Footing** | town centre | `reckoning` | 600f 400w 500g 200s | 80 s | civ `squad_cap_bonus` +6 · civ `production_speed` ×1.15 |
| `long_supply` | **Long Supply** | storehouse | `reckoning` | 500f 400w 300g | 70 s | civ `gather_speed` ×1.10 · `gatherers` `carry_capacity` +6 |

⚠ **`war_footing` puts `squad_cap` back in `docs/status/civ-knobs.md`'s
worst-case arithmetic.** That page pins 880 squads at D-018's 20 players
and 1,056 at the lobby's 24 seats, computed from `CivDef.squad_cap_bonus`
alone. A tech that adds 6 more per player moves both, and the pinning test
must count it.

---

## Part 5 — The six defining lines

This is the part that is supposed to read like a story. Each civ's five
arc techs are its five-stage development arc from
`docs/plans/fantasy-civs.md` Part 2, verbatim, turned into research.

---

### STONEBLOOD — *quality · giant-kin and their hill-tribe thralls*

> scattered hill-clans → thrall levies → giants walk to war → gatebreaker broods → the Old Blood wakes

| E | ▣ | line | **name** | site | unlocks | cost / time |
|---|---|---|---|---|---|---|
| 1 | ▣ | `settling` | **Scattered Hill-Clans** | town centre | — | 350f 200w · 60 s |
| 2 | ▣ | `mustering` | **Thrall Levies** | barracks | `skirmishers` (Cragthrowers) | 550f 350w 150g · 80 s |
| 3 | ▣ | `holding` | **Giants Walk to War** | barracks | `heavy` (Young Giants) | 800f 500w 350g · 100 s |
| 4 | ▣ | `breaking` | **Gatebreaker Broods** | Breaking Yard | `breaker` (**Gatebreakers ★**) | 1200f 800w 600g 250s · 120 s |
| 5 | | `reckoning` | **The Old Blood Wakes** | Breaking Yard | — | 1000f 700w 800g 300s · 150 s |

- **Scattered Hill-Clans** — *The giants do not gather. The hill tribes
  gather for them, and the tribes must first be persuaded there is a hill
  worth holding.* `gatherers` `gather_rate` ×1.12, `carry_capacity` +3.
- **Thrall Levies** — *They are given mauls, and told where to stand, and
  they stand there.* `levy` `health` ×1.10.
- **Giants Walk to War** — *The Old Blood's children come down off the
  crags. There are eight of them and it is enough.* `levy` `morale` +8
  (the thralls fight harder with a giant in the line).
- **Gatebreaker Broods** — *Elder giants bred for one purpose, quarried
  out of the deep hills like everything else Stoneblood owns.*
  `skirmishers` `damage_vs_buildings` +0.15 — the Cragthrowers learn to
  aim at masonry.
- **The Old Blood Wakes** — *What sleeps under the hills remembers being
  worshipped.* `heavy` `health` ×1.25, `damage` ×1.15, `morale` +15;
  `breaker` `damage_vs_buildings` +0.15.

*Stoneblood's signature arrives at epoch 4, one rung early, because for
this civ **break and decide are the same event** — a giant is his own
siege train, so the thing that cracks the wall is also the thing that
wins the battle. Its Reckoning is therefore not a new unit but the eight
giants it already has becoming unanswerable.*

---

### GRAVESWORN — *quantity · a deathless court and its raised legions*

> a barrow court → corpse levies → bone legions → carrion engines → the Court rides out

| E | ▣ | line | **name** | site | unlocks | cost / time |
|---|---|---|---|---|---|---|
| 1 | ▣ | `settling` | **A Barrow Court** | town centre | — | 350f 200w · 60 s |
| 2 | ▣ | `mustering` | **Corpse Levies** | barracks | `spearmen` (Bone Pikes) | 550f 350w 150g · 80 s |
| 3 | ▣ | `holding` | **Bone Legions** | barracks | — | 800f 500w 350g · 100 s |
| 4 | ▣ | `breaking` | **Carrion Engines** | Bone Kiln | `engine` (Carrion Hurler) | 1200f 800w 600g 250s · 120 s |
| 5 | | `reckoning` | **The Court Rides Out** | Bone Kiln | `shades` (**Barrow Shades ★**) | 1000f 700w 800g 300s · 150 s |

- **A Barrow Court** — *A hall is dug, not built. The court prefers a roof
  of earth.* `gatherers` `gather_rate` ×1.12; civ `production_speed`
  ×1.05.
- **Corpse Levies** — *Every field the court has ever fought over is a
  muster roll.* `levy` `cost_food` ×0.88.
- **Bone Legions** — *Discipline outlasts the flesh that learned it.*
  civ `squad_cap_bonus` +5, civ `production_speed` ×1.12; `levy` and
  `spearmen` `health` ×1.10.
- **Carrion Engines** — *A gallows-frame that throws what the court has
  too much of.* `engine` `attack_range` +1.
- **The Court Rides Out** — *The hunting dead are let off the leash.*
  `shades` `move_speed` ×1.10, `vision_range` +4.

*Gravesworn is the only civ whose HOLD rung unlocks no unit at all, and
that is its axis arriving as a tech: **Bone Legions is the quantity
identity**, +5 squad cap and +12% production, which is worth more to this
civ than any single archetype would be. It is also the civ that gets least
from `standards` (nothing) and most from `war_footing`.*

---

### THORNWOOD — *ranged attrition · sylvan elves of a sentient forest*

> glade wardens → heartbows strung → the forest marches → sentinel groves → the Wood itself moves

| E | ▣ | line | **name** | site | unlocks | cost / time |
|---|---|---|---|---|---|---|
| 1 | ▣ | `settling` | **Glade Wardens** | town centre | — | 350f 200w · 60 s |
| 2 | ▣ | `mustering` | **Heartbows Strung** | barracks | `archers` (Heartbow Archers) | 550f 350w 150g · 80 s |
| 3 | ▣ | `holding` | **The Forest Marches** | Stag Glade | `cavalry` (Stag Riders) | 800f 500w 350g · 100 s |
| 4 | ▣ | `breaking` | **Sentinel Groves** | barracks | `greatbow` (**Dawnfletch Sentinels ★**) | 1200f 800w 600g 250s · 120 s |
| 5 | | `reckoning` | **The Wood Itself Moves** | Stag Glade | — | 1000f 700w 800g 300s · 150 s |

- **Glade Wardens** — *A glade is not cleared. It is asked.* `gatherers`
  `gather_rate` ×1.12, `vision_range` +4.
- **Heartbows Strung** — *Heartwood takes a century to grow and an
  afternoon to string.* `archers` `attack_range` +0.5.
- **The Forest Marches** — *The wood does not defend a border. It moves
  the border.* `levy` `move_speed` ×1.10; `*` `vision_range` +3.
- **Sentinel Groves** — *Stakes planted where a wall used to matter, and
  fletching dipped in slow fire.* `archers` and `greatbow`
  `damage_vs_buildings` +0.30.
- **The Wood Itself Moves** — *Every tree between here and the sea is a
  Thornwood soldier that has not been asked yet.* `greatbow`
  `attack_range` +1, `damage` ×1.15; `archers` `attack_interval` ×0.90.

*⚑ **Thornwood's break is arrows, not engines**, and this is the design's
answer to "a civ with no forge cannot leave epoch 4". Sentinel Groves is
researched at the BARRACKS — a universal site — and what it buys is
`damage_vs_buildings` on the longest bows in the game. The civ that cannot
build a siege engine cracks a wall by standing outside its reach and never
stopping. That is the frame's *"grinding down at distance"* applied to
masonry, and it is slower than a bombard on purpose.*

---

### WINDMARCH — *mobility · centaur clans of the open steppe*

> wandering clans → colt musters → the great herds → the clans confederate → storm-host at full gallop

| E | ▣ | line | **name** | site | unlocks | cost / time |
|---|---|---|---|---|---|---|
| 1 | ▣ | `settling` | **Wandering Clans** | town centre | — | 350f 200w · 60 s |
| 2 | ▣ | `mustering` | **Colt Musters** | Home Herd | `skirmishers` (Harriers) | 550f 350w 150g · 80 s |
| 3 | ▣ | `holding` | **The Great Herds** | Home Herd | `cavalry` (Storm Lancers) | 800f 500w 350g · 100 s |
| 4 | ▣ | `breaking` | **The Clans Confederate** | barracks | — | 1200f 800w 600g 250s · 120 s |
| 5 | | `reckoning` | **Storm-Host at Full Gallop** | Home Herd | `bowriders` (**Bowriders ★**) | 1000f 700w 800g 300s · 150 s |

- **Wandering Clans** — *A camp is a decision to stop, and the clans
  distrust it.* `gatherers` `move_speed` ×1.15, `gather_rate` ×1.08,
  `vision_range` +4.
- **Colt Musters** — *The yearlings are given javelins and a direction.*
  `levy` `move_speed` ×1.05.
- **The Great Herds** — *Not an army. A migration with lances in it.*
  civ `squad_cap_bonus` +3; `*` `move_speed` ×1.05.
- **The Clans Confederate** — *No single clan can take a wall. Every clan,
  arriving on the same morning, does not have to.* civ `squad_cap_bonus`
  +5; `*` `damage_vs_buildings` +0.20; `*` `move_speed` ×1.05.
- **Storm-Host at Full Gallop** — *The whole steppe, moving as one
  animal.* `bowriders` `attack_range` +1, `vision_range` +4; `cavalry`
  `damage` ×1.12.

*⚑ **Windmarch's break is arithmetic, not engineering.** The Clans
Confederate is the only defining tech in the game that unlocks no unit and
grants no new capability — it grants MORE, +8 squad cap across two rungs
and a fifth again of everyone's building damage. A civ that cannot besiege
takes fortified ground by bringing all of it at once, which is what
*"punishing overextension"* means when the overextension is a wall.*

---

### GILDEDREACH — *economy & flexibility · free cities of men and half-bloods*

> a market town → the city watch → charter companies → contract engines → coin buys anything

| E | ▣ | line | **name** | site | unlocks | cost / time |
|---|---|---|---|---|---|---|
| 1 | ▣ | `settling` | **A Market Town** | town centre | — | 350f 200w · 60 s |
| 2 | ▣ | `mustering` | **The City Watch** | barracks | `spearmen` (Pike Serjeants) · `archers` (Quarrel Companies) | 550f 350w 150g · 80 s |
| 3 | ▣ | `holding` | **Charter Companies** | Hiring Yard | `cavalry` (Hired Outriders) | 800f 500w 350g · 100 s |
| 4 | ▣ | `breaking` | **Contract Engines** | Contract House | `engine` (Contract Engines) | 1200f 800w 600g 250s · 120 s |
| 5 | | `reckoning` | **Coin Buys Anything** | Contract House | `sellswords` (**Gilded Sellswords ★**) | 1000f 700w 800g 300s · 150 s |

- **A Market Town** — *A charter, a set of scales, and somewhere to keep
  the ledger dry.* civ `gather_speed` ×1.10; `gatherers` `carry_capacity`
  +4.
- **The City Watch** — *Guild levies, paid monthly, drilled fortnightly.*
  `levy` `health` ×1.10.
- **Charter Companies** — *A company is a contract with a banner on it.*
  civ `production_speed` ×1.10; `*` `cost_gold` ×0.92.
- **Contract Engines** — *You do not build a springald. You buy the men
  who have already built one.* `engine` `build_time` ×0.80.
- **Coin Buys Anything** — *Including, eventually, the other side's army.*
  civ `gather_speed` ×1.10; `sellswords` `health` ×1.10; `*` `cost_gold`
  ×0.90.

*Gildedreach is the only civ whose defining line **unlocks two archetypes
at one rung** (E2 gives it both a spearman and a missile unit), which is
"the broadest roster" arriving on schedule — and the only civ whose arc
techs are three-quarters about MONEY rather than about troops. It is also
the only civ that can walk both branches, and it pays for the privilege in
gold and stone at once.*

---

### EMBERDEEP — *fortification & siege · deep-hold dwarves*

> a delved hold → hearth levies → the shieldwall → rams and bombards → the deep gates open

| E | ▣ | line | **name** | site | unlocks | cost / time |
|---|---|---|---|---|---|---|
| 1 | ▣ | `settling` | **A Delved Hold** | town centre | — | 350f 200w · 60 s |
| 2 | ▣ | `mustering` | **Hearth Levies** | barracks | `archers` (Tunnel Quarrels) | 550f 350w 150g · 80 s |
| 3 | ▣ | `holding` | **The Shieldwall** | barracks | `heavy` (Shieldwall Vanguard) | 800f 500w 350g · 100 s |
| 4 | ▣ | `breaking` | **Rams and Bombards** | Deep Forge | `ram` (**Deepram ★**) | 1200f 800w 600g 250s · 120 s |
| 5 | | `reckoning` | **The Deep Gates Open** | Deep Forge | `bombard` (**Ember Bombard ★**) | 1000f 700w 800g 300s · 150 s |

- **A Delved Hold** — *Nobody builds a hold. You find the mountain, and
  you disagree with it.* `gatherers` `gather_rate` ×1.12; buildings `*`
  `max_health` ×1.10.
- **Hearth Levies** — *Every dwarf owns an axe. The hold merely writes
  down which.* `levy` `health` ×1.12.
- **The Shieldwall** — *Not a formation. A decision, held by twenty
  dwarves at once.* `levy` and `heavy` `morale` +10; buildings `*`
  `max_health` ×1.10.
- **Rams and Bombards** — *The hold's considered opinion of somebody
  else's gate.* `ram` `health` ×1.15.
- **The Deep Gates Open** — *What the hold has been building since the
  first epoch, wheeled out.* `bombard` `attack_range` +1; `ram` and
  `bombard` `damage_vs_buildings` +0.10.

*Emberdeep is the only civ with **two** signature units and it gets one at
each of the last two rungs, which is the frame's *"holding ground AND
cracking it"* spread across the two verbs those words name. It is also the
only civ whose arc techs touch BUILDING health twice — the fortification
half of its axis, which no other civ's line goes near.*

---

## Part 6 — The branches

Optional depth, bought instead of troops. Every branch tech requires its
epoch's arc tech, so nothing here can be reached ahead of the story.

### Stables — three civs, three names for each line

| line | epoch | Thornwood · Stag Glade | Windmarch · Home Herd | Gildedreach · Hiring Yard |
|---|---|---|---|---|
| `remounts` | 2 | **Antler-Broke** | **The Long Gallop** | **Post Horses** |
| `long_stride` | 3 | **Deerpaths** | **Grasslore** | **Relay Stations** |
| `barded_mounts` | 5 | **Thornmail** | **Warpaint** | **Barding, Bought** |

| line | cost | time | effect |
|---|---|---|---|
| `remounts` | 200f 100w 100g | 40 s | `cavalry` `bowriders` `move_speed` ×1.10, `vision_range` +3 |
| `long_stride` | 300f 200w 200g | 50 s | `cavalry` `bowriders` `move_speed` ×1.08, `attack_range` +0.5 |
| `barded_mounts` | 500f 300w 500g | 80 s | `cavalry` `bowriders` `health` ×1.20 |

*Windmarch's are not really about horses — the clans ARE the horses, so
**The Long Gallop** is a discipline and **Warpaint** is a ritual, where
Gildedreach's **Post Horses** and **Barding, Bought** are line items. Same
knob, and the two civs would never write the same word on it.*

### Forge — four civs, four names for each line

| line | epoch | Stoneblood · Breaking Yard | Gravesworn · Bone Kiln | Gildedreach · Contract House | Emberdeep · Deep Forge |
|---|---|---|---|---|---|
| `siegecraft` | 4 | **Quarried Heads** | **Grave-tar Payloads** | **Engineers' Retainer** | **Runeforged Charges** |
| `foundry_stock` | 4 | **Pick and Wedge** | **Kiln-Fired Frames** | **Bulk Order** | **Hold-Iron Fittings** |
| `master_work` | 5 | **The Long Grudge** | **The Sexton's Art** | **A Better Contract** | **Mastersmith's Mark** |

| line | cost | time | effect |
|---|---|---|---|
| `siegecraft` | 500f 400w 300g 200s | 60 s | `breaker` `engine` `ram` `bombard` `damage_vs_buildings` +0.20 |
| `foundry_stock` | 400f 350w 200g 250s | 55 s | `breaker` `engine` `ram` `bombard` `health` ×1.25, `cost_stone` ×0.85 |
| `master_work` | 500f 400w 400g 300s | 80 s | `*` `damage` ×1.08; `breaker` `engine` `ram` `bombard` `attack_range` +1 |

*`siegecraft` is issue #206's own worked example — "a damage-vs-buildings
tech is 'Runeforged Rams' to Stoneblood and 'Grave-tar Payloads' to
Emberdeep". The names are assigned the other way round here because
Stoneblood does not forge anything: it quarries, so its siege upgrade is
**Quarried Heads** and Emberdeep, which does forge, gets **Runeforged
Charges**.*

---

## Part 7 — Unit gates: the whole roster, by rung

`UnitDef.requires_tech` names a LINE; empty means always producible. Every
`gatherers`, `general` and `levy` def is left empty, so **the opening does
not change** and every scenario, bot and AI that fields them keeps
working.

| civ | E1 free | E2 `mustering` | E3 `holding` | E4 `breaking` | E5 `reckoning` |
|---|---|---|---|---|---|
| Stoneblood | levy, gatherers, general | skirmishers | heavy | **breaker ★** | — |
| Gravesworn | levy, gatherers, general | spearmen | — | engine | **shades ★** |
| Thornwood | levy, gatherers, general | archers | cavalry | **greatbow ★** | — |
| Windmarch | levy, gatherers, general | skirmishers | cavalry | — | **bowriders ★** |
| Gildedreach | levy, gatherers, general | spearmen, archers | cavalry | engine | **sellswords ★** |
| Emberdeep | levy, gatherers, general | archers | heavy | **ram ★** | **bombard ★** |

**Every signature unit sits behind a tech**, which is issue #206's
explicit ask. Four of the six arrive at the Reckoning; Stoneblood's and
Emberdeep's Deepram arrive at the Breaking, because for those two civs the
signature IS the siege train and putting it a rung later would mean the
break epoch had no way to break.

**Buildings:** `stables` requires `settling`, `forge` requires
`mustering`. Every other shipped building — town centre, barracks,
storehouse, tower, and the five wall-family defs — is left ungated, so the
build menu a player already knows is unchanged at epoch 1.

---

## Part 8 — Counts, and what has to be true

**65 tech `.tres`:**

| | files |
|---|---|
| trunk, `civ = neutral` | 14 |
| civ arc techs (6 civs × 5 rungs) | 30 |
| stables branches (3 lines × 3 civs) | 9 |
| forge branches (3 lines × 4 civs) | 12 |

**7 building `.tres`** (3 stables, 4 forges) and **`BuildingDef.archetype`**
added to the schema with an empty default, so none of the nine shipped
building files is edited.

**Invariants a test must assert**, each of which this document could get
wrong silently:

1. **Every civ fields a TechDef for every defining line.** Otherwise a civ
   cannot leave that epoch — the ladder locked by identity, which is a bug
   with a story attached.
2. **The dependency graph is acyclic and every tech is reachable from a
   fresh start, for every civ.** The Home Herd is required by Windmarch's
   `mustering` and itself requires `settling`; get that one edge wrong and
   Windmarch can never research anything again. (It was wrong in the first
   draft of this document.)
3. **A defining tech's `research_at` resolves for its civ.** Universal
   sites for the trunk; the civ's own for the arc.
4. **No `stables` or `forge` def is `civ = neutral`** — a neutral def
   shadows every per-civ one (`UnitRoster.for_civ_archetype` returns the
   first id-order match), which is how a whole feature went quietly absent
   in `D-20260823-the-opening-is-a-crew-and-a-general`.
5. **Every `TechEffect.field` is in the closed vocabulary**, and every
   `target` is a real archetype or `*`. A typo'd field is a tech that
   silently does nothing — the declared-and-unread family, fifth instance.
6. **No `.gd` file names a tech id, a tech line or an epoch**, the same
   scan `tests/test_civs.gd` runs for civ ids.
7. **The four advance totals equal D-069's table** — the two halves of
   each defining line sum to the row. That is the one number in this
   document not derived here, and a test is what stops it drifting.
8. **`squad_cap` worst case is re-pinned** including `war_footing`,
   `Bone Legions`, `The Great Herds` and `The Clans Confederate`. The
   worst civ is Windmarch at +8 from its own line, +6 from `war_footing`,
   on top of `CivDef.squad_cap_bonus`.

---

## Part 9 — What is deliberately NOT here

- **Rosters do not grow by replacement** (D-070). This tree gates the 39
  unit defs that ship across five rungs; it does not author the 70–100 a
  full replacement ladder needs. That is a separate content bill and it
  can be paid after the tree has been played.
- **No upkeep** (D-068). D-070 calls upkeep load-bearing for replacement
  rosters — *"without upkeep, replacement rosters manufacture trash"* —
  and this tree does not replace rosters, so that specific trap is not
  sprung. The 90-minute target still needs it, and nothing here claims to
  reach 90 minutes alone.
- **No active abilities, no spells, no heroes.** Combat is D-024 and stays
  D-024. Every effect above is a number on a def.
- **No per-civ walls, towers or town centres.** Exactly two building
  archetypes become per-civ, and the reason is that they are research
  SITES.
- **No strength ordering between civs.** That is `just ai-ladder`'s job
  once the tree exists — and a ladder run against this tree needs a cap
  well past the 600 s the last one used, plus the standing rule that a
  result is quoted **with its cap, its squad count and now its roster**.
- **No epoch-scoped train UI.** D-069 flagged unlock overload and D-074
  owns detecting it; the tree makes it real a rung earlier, and the build
  menu's existing category drill-down is the surface that will have to
  absorb it.

---

## Part 10 — The open naming tension, restated

`docs/status/fantasy-civs.md` records that the shipped civ ids
(`stoneblood`, `gravesworn`, `thornwood`, `windmarch`, `gildedreach`,
`emberdeep`) and `D-20260823-fantasy-civs-on-a-four-epoch-ladder`'s set
(Dominion, Warhost, Centaurs, Deepholds, Gilded, Sylvans) name the same
six AXES differently, and that resolving it is the owner's call. **This
document is written against the ids that ship**, and everything in it is
an id sweep away from the other naming if the owner settles it the other
way.

The same paragraph applies to the rung count. **Five rungs here, D-069's
verbs, because the shipped civs' own arc table has five stages and issue
#206 names those five verbs.** D-20260823 asks for four. Collapsing this
tree to four is: delete one `EpochDef`, merge the Holding and Breaking
rungs, move a `defining` flag on ten files. **No script changes**, because
no script names an epoch or a tech — which is the property the whole
design was built to have, and the reason this disagreement is cheap
rather than expensive.

# Naval — water as a second movement domain

**Written:** 2026-08-28, against `main` at `cc2f4c6`.
**Directive:** issue #301 (owner, 2026-08-28) — *"at least two naval
units per civ, or a combined attack-transport where that fits the civ
better; docks; water as a second movement domain."*
**Resolves:** #280's "retire or naval" in favour of naval.
**Decisions this doc carries the detail for:**
`D-20260828-water-is-a-second-movement-domain`,
`D-20260828-a-carried-squad-is-cargo`,
`D-20260828-a-dock-stands-on-a-shore`.

**Design only. No sim code is written until this is reviewed** — #301
says the implementation is to be parallelised, and §7 is the cut-list
that makes that possible.

---

## 0. The shape of the answer, in one page

**Water is a third value of `SquadSim._tier`**, which D-076 already
established as "which layer of the world is this squad on". It becomes a
movement DOMAIN with three values — ground, wall-top, water — and every
piece of machinery D-076 built for the wall-top tier is driven a third
time rather than generalised: a separate `FlowField` layer with its own
cell budget, an explicit one-hop transition, and a targeting rule that
says which domains can reach which.

**A carried squad is cargo, and cargo is not in the world.** It has no
cell, no formation, no vision and no entry in anybody's `visible_to` — it
is a property of the ship carrying it, replicated on the ship's own
`SQUAD_INFO`. That is what keeps `composition_hash()` identical on both
sides, which is the D-099 ghost lesson applied before it can bite.

**You load at a dock and you land anywhere.** Embarking is a logistics
operation you build for; disembarking is an assault. The asymmetry is
deliberate and §3 argues it.

**Six civs, ten ships**, four of them transports and two of them
combined attack-transports where the civ's axis argues for it (§5). Every
one passes the D-072 screen; the numbers are computed in §5.3, not
asserted.

**The AI builds docks and lands armies, or none of this exists.** D-076
shipped a whole wall system that `just ai-ladder` has never exercised
because no AI was taught to want a wall, and its own entry says so. §6 is
the plan that stops this repeating, and it includes the gates that fail
if the AI stops doing it.

---

## 1. What already exists, and what is genuinely new

Worth being precise, because the amount of NEW machinery here is smaller
than "a second movement domain" sounds.

| already exists | where |
|---|---|
| a per-squad layer value with its own passability | `SquadSim._tier`, `is_passable(cell, tier)` |
| a second `FlowField` layer with its own budget | `_fields_top` / `top_field_cells_per_tick` (D-076) |
| a two-leg "walk there, then transition" order | `_begin_tier_crossing` / `_advance_tier_transitions` |
| an explicit teleporting hop, no interpolated walk | `_teleport_curve` |
| a per-instance door cell on a building | `BuildingSim.door_cell_of` (the access tower's `access_direction`) |
| a targeting rule about who can reach which layer | `Combat._can_reach_tier` |
| water as a terrain fact | `TerrainGen.is_water`, `Biome.WATER` / `DEEP_WATER`, `sea_level` |
| squad-level stochastic combat, server-only | `combat.gd` (D-024) — ships are squads, no change |
| curve replication and fog gating | D-003 / D-004 / D-025 — ships are squads, no change |
| a component walk over a passability field | `MapConfig.walkable_components` (D-20260827, PR #216) |

| genuinely new | why |
|---|---|
| a **navigability** field (water's inverse of `passable`) | nothing computes it today |
| `UnitDef.movement_domain` | a unit belongs to a domain; the ORDER must not decide it |
| `UnitDef.transport_capacity` | how many squads a hull carries |
| cargo: a list on a ship, replicated on its `SQUAD_INFO` | there is no "squad inside a squad" concept |
| `BuildingDef.needs_shore` + a shore placement refusal | no placement rule looks at what a cell is NEXT to |
| ship production spawning into WATER | `_spawn_cell_near` walks land |
| `Combat._can_reach_domain` (generalising `_can_reach_tier`) | melee must not cross a shoreline |

Everything else is data.

---

## 2. The water domain

### 2.1 Navigability is the inverse of passability, and it is its own field

`TerrainGen.passability(space)` answers "may a land squad stand here"
(D-20260826: flat enough to cross, never merely low). The naval
counterpart is a second `PackedByteArray`:

```
navigable[i] = 1  iff  elevation(i) < sea_level
```

Derived from the same replicated `MapSettings` numbers both sides
already hold (D-049), so client and server derive identical arrays and
nothing new crosses the wire. It is a **separate array**, not a flag in
the existing one, for the reason D-076 kept its field cache separate: a
single tri-state array would be read by every existing caller of
`_passable`, most of which mean "land".

**All water is navigable in v1.** Deep water is a biome and an
appearance, not a draft rule. Introducing shallow/deep as a navigability
distinction doubles the field count and the transition surface to buy a
mechanic nothing else asks for yet; it is named as a revisit trigger on
the water-domain decision instead.

### 2.2 A domain, not a tier — but the same field

`_tier` gains a third value:

| value | domain | passability source |
|---|---|---|
| 0 | ground | `SquadSim._passable` (terrain minus living buildings) |
| 1 | wall-top | `BuildingSim.is_walkable_top_cell` (D-076) |
| 2 | **water** | `SquadSim._navigable` (terrain minus… see below) |

The field keeps its name to avoid churning D-076's call sites; its doc
comment says "domain" and the constants are named `DOMAIN_GROUND`,
`DOMAIN_WALL_TOP`, `DOMAIN_WATER`. Three values in one field is right
because they are **mutually exclusive by construction**: a ship is never
on a wall, and a land squad is never on open water except as cargo, which
is not in the world at all (§3).

**Buildings on water.** A dock's own cell is LAND (§4), so `_navigable`
needs no building subtraction in v1 — but the moment a future structure
occupies a water cell (a sea wall, a floating platform), it must be
stamped out of `_navigable` exactly as `occupied_cells()` is stamped out
of `_passable`. Stated now so it is not rediscovered.

### 2.3 A third `FlowField` layer, with its own budget

Following D-076 exactly, and for the reason its entry gives — sharing
D-040's counter would let a naval solve silently halve ground-pathing
throughput on any tick both run:

```
_fields_water, _pending_fields_water, water_field_cells_per_tick
```

`FlowField` itself is **not modified**. It is driven a third time.

**The budget must be measured, not guessed.** D-076 set the wall layer to
1,024 cells/tick and D-20260818 later took the ground layer to 16,384
after finding the solver was 93% neighbour lookup. Water is a *large*
region on the maps that matter — `islands` is 65–71% water, so a naval
field can be bigger than a ground field on the same map. **Stage 2's exit
criterion is a measured cell budget and a measured worst tick**, taken
the way D-076 measured the wall layer and quoted with its squad count.

**One thing to check before writing it, not after** (this is the D-040
lesson): `TorusSpace.neighbor_table()` is memoised per `TorusSpace`
instance and the sim holds one, so the naval layer gets the existing
table for free. Confirm that by reading `_field_for`'s budget accounting
first, exactly as D-076 says it did.

### 2.4 Orders never choose a domain

D-076 infers the target tier from the destination cell
(`_tier_for_destination`), which is what let it add a whole tier with **no
wire change to movement orders**. Naval must not break that, but it
cannot use the same rule: a shore cell is legal for a land squad AND
adjacent to legal water, so "which domain did they mean" is genuinely
ambiguous from the cell alone.

**Resolution: the UNIT decides its domain, the cell decides only whether
the order is legal.**

- `UnitDef.movement_domain` is `ground` (default) or `water`.
- A water squad ordered to a land cell is **corrected to the nearest
  navigable cell** — the same shape as `_approachable`, which already
  corrects a destination rather than refusing an order, and which
  D-20260818 explicitly left omniscient because it can never refuse.
- A land squad ordered to a water cell is corrected to the nearest
  passable land cell, unless it is an embark order (§3).
- A land squad ordered *across* water to a reachable land cell is refused
  by ordinary pathing — its own belief field (`terrain_knowledge.gd`)
  finds no route, and D-20260818's give-up rule already handles that.

So **no new opcode for movement**, which is the property worth
protecting.

### 2.5 Naval combat is D-024, plus one rule

`combat.gd` is untouched except to generalise one predicate. Ships are
squads: `squad_size` hulls, `health` per hull, the same bucket map, the
same disk scan, the same `TorusSpace.disk_offsets` (never `distance()`
per cell — the standing rule).

The one new rule generalises D-076's `_can_reach_tier`:

> **Melee cannot cross a domain boundary. Ranged can.**

| attacker | defender | may attack |
|---|---|---|
| land melee | ship | ✗ |
| land ranged / building | ship | ✓ |
| ship melee (ram) | land | ✗ |
| ship ranged | land | ✓ |
| ship | ship | ✓ (same domain) |

This is the same sentence D-076 already enforces between ground and
wall-top, and it makes a shoreline mean something: an army caught on a
beach by a warship can be shot and cannot shoot back unless it brought
archers. It also gives the Ember Monitor (§5) its identity — a siege ship
that outranges shore towers — without a single civ-specific branch.

**A ram is the exception that proves it.** A ship whose `attack_range`
is short is a ship that can only fight other ships. That is a data
consequence, not a rule.

---

## 3. Embark, disembark, and what a carried squad is

### 3.1 Cargo is not in the world

A squad that boards a ship is **removed from the domain entirely**:

- no cell, no curve, no formation, no soldier derivation
- **no vision stamp of its own** (#301 asked for this to be decided —
  decided: none; the ship sees for it)
- **not in `visible_to` for anybody, including its owner**
- **not targetable**; the ship is the only thing on the map
- still counts against the squad cap — it is an army slot you are using

**Why "not visible even to its owner" is the right answer and not a
compromise.** The server hashes exactly `visible_to(player)` and the
client hashes exactly what it treats as live (D-026 criterion 8). D-099
already paid for this once: a ghost must never be folded into
`composition_hash()`, because a client counting its own ghosts hashes a
strictly larger set and desyncs on a perfectly healthy system. Cargo is
the same shape. Excluding it from `visible_to` on both sides makes the
hashes agree **by construction**, with no rule anybody has to remember.

The owner still sees their army, because **cargo is replicated as a
property of the carrier**: `SQUAD_INFO` for a ship gains a `cargo` list
of `{def_id, alive}`. That is an addition to an existing message, not a
new mechanism — the same "extend the curve/info path, never duplicate it"
rule D-003 and D-025 are built on. The HUD draws it in the ship's
selection panel.

### 3.2 If the ship sinks, the cargo drowns

Stated plainly because the alternative is worse. Ejecting cargo onto the
nearest shore when a transport dies would make transports strictly
better than not using them, and would produce the one thing this project
already learned to avoid: an invisible rule a player cannot see operating
(D-076 chose the opposite for wall destruction — *evict, do not kill* —
and the reason it chose it does not transfer: a squad on a razed wall is
standing on ground that still exists, while a squad on a sunk ship is in
open water it could never have entered on its own).

The casualty path reports it as ordinary deaths, with
`D-20260819-a-casualty-is-visible`'s `fell` byte set — men lost with a
ship died by violence.

### 3.3 Load at a dock, land anywhere

**Embark** is a two-leg order in exactly `_begin_tier_crossing`'s shape:

1. The land squad walks to the dock's **land cell** (its own tier).
2. On arrival, if a friendly transport with spare capacity is at the
   dock's **water cell**, one explicit hop moves the squad into that
   ship's cargo. No curve interpolation, nothing partial — which is what
   keeps it legal under D-006 clause 1: **there is nowhere for a
   half-embarked value to live.**

**Disembark** is one leg: the ship is ordered to a land cell, sails to the
nearest navigable cell adjacent to it, and the cargo hops out onto
passable land cells around that point.

**Why the asymmetry.** D-076 faced the same question and chose "one
door", after explicitly rejecting "any adjacent cell" because it made a
wall's LINE pointless. **There is no line to defend at sea.** A rule that
only let you land where somebody had already built a dock would mean you
can only invade an island that has already been settled by the enemy —
which on `islands`, the map this whole feature exists for, is a
contradiction. Loading is slow and needs infrastructure; landing is the
attack. That is the shape every RTS in the genre uses, and it is the one
that makes the feature a game.

### 3.4 What this deliberately does not do

- **No partial loads mid-sea.** A ship loads at a dock and unloads at a
  shore. No ship-to-ship transfer, no loading from a beach.
- **No shore bombardment bonus, no amphibious-assault penalty.** A landed
  squad is an ordinary squad the tick it lands. Both are tempting and
  both are new combat rules for a feature that does not need them to be
  playable.
- **No naval upkeep or supply.** D-068's upkeep is unbuilt for land too.

---

## 4. Docks

### 4.1 The placement rule

A dock must stand on a **shore cell**: a passable LAND cell with at least
one navigable neighbour. `BuildingDef.needs_shore = true` adds one
refusal to `server._build_refusal`, beside the ones that already exist
for water, steep ground, resource nodes and occupied cells.

Its **water cell** — where ships appear and where transports wait — is
per-INSTANCE, chosen at placement from the navigable neighbours, and
stored on `BuildingSim` exactly as the access tower's `access_direction`
is. **A def cannot carry it**: a def is one resource per archetype, so a
shared water-side would give every dock on the map the same one. That is
D-076's own reasoning, reused verbatim because the situation is identical.

### 4.2 Ships appear in water

`SquadSim._spawn_cell_near` walks `disk_offsets` over land. Ship
production needs the same function over `_navigable`, seeded from the
dock's water cell. Same shape, same determinism argument, different
array — and it is where the "a recruit steps out of the near door"
behaviour (D-20260821) applies again.

### 4.3 One dock def, six civs

**Not six dock defs.** `barracks` already serves all six civs, because
`produces` lists ARCHETYPES and the server resolves each against the
acting player's civ (D-047). A dock does the same: it produces
`transport` and `warship`, and which hull you get depends on who is
asking. Per-civ dock *identity* — a Gravesworn bone-yard, an Emberdeep
sea-gate — is naming and art, and belongs with #206's stables/forges
work rather than here.

A `shipyard` upgrade (via the existing `upgrade_from`, like `wall_tower`)
is named as the natural home for naval techs when #206's tree lands, and
is **not** in this cut.

---

## 5. The ships

### 5.1 How the roster was built

Every civ's ships express its axis (`docs/plans/fantasy-civs.md` Part 2)
and are screened by D-072: **V = sqrt(DPS × EHP)**, **RP = food + wood +
1.5 × (gold + stone)**, with the two standing rules — within a role,
**price buys power**, and **no unit leads on both V and V/RP**.

Two civs get a **combined attack-transport** rather than two hulls,
because their axis argues for it:

- **Stoneblood (quality)** — few and mighty is the whole civ. One great
  vessel that fights and carries is that thesis at sea; two mediocre
  hulls would not be.
- **Windmarch (mobility)** — a steppe folk with no naval tradition. One
  fast, cheap, genuinely poor raft is an honest expression of *"bad at
  taking fortified ground"* extended to the water, and it keeps their
  identity on land where it belongs.

### 5.2 The roster

| civ | unit | archetype | role | class | sz | hp | dmg | int | rng | spd | cap | cost |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Stoneblood | **Stonewright Barge** ★ | `warboat` | combined | infantry | 4 | 420 | 26 | 2.2 | 6.0 | 4.0 | 2 | 60f 70w 30s |
| Gravesworn | **Bone Skiff** | `warship` | warship | infantry | 8 | 90 | 9 | 1.6 | 5.0 | 4.6 | 0 | 30f 45w |
| Gravesworn | **Corpse Barge** | `transport` | transport | infantry | 4 | 150 | 0 | — | — | 4.2 | 3 | 20f 55w |
| Thornwood | **Heartwood Cutter** | `warship` | warship | missile | 6 | 140 | 14 | 2.0 | **9.0** | 4.4 | 0 | 35f 70w |
| Thornwood | **Leafskiff** | `transport` | transport | infantry | 3 | 120 | 0 | — | — | **5.2** | 2 | 15f 50w |
| Windmarch | **Reed Raft** ★ | `warboat` | combined | infantry | 5 | 110 | 7 | 1.8 | 4.0 | **5.6** | 2 | 25f 30w |
| Gildedreach | **Charter Galley** | `warship` | warship | missile | 5 | 180 | 18 | 1.9 | 7.0 | 4.8 | 0 | 40f 40w 40g |
| Gildedreach | **Merchant Hull** | `transport` | transport | infantry | 3 | 220 | 0 | — | — | 4.6 | 3 | 20f 40w 30g |
| Emberdeep | **Ember Monitor** ★ | `warship` | siege ship | missile | 3 | 220 | 34 | 4.2 | **11.0** | 3.4 | 0 | 50f 70w 60s |
| Emberdeep | **Ironhull** | `transport` | transport | infantry | 3 | **380** | 0 | — | — | 3.2 | 2 | 30f 60w 40s |

★ the civ's naval signature. All ten take `movement_domain = water`.
`armour_class` follows the existing three values — a gunned ship is
`missile` so the counter triangle keeps working; a ramming or boarding
hull is `infantry`. **No fourth armour class**, because the triangle is
D-032's and adding to it would re-balance every land unit as a side
effect.

### 5.3 The screen, computed

```
warships, by price:   Bone Skiff  V 180  RP  75  V/RP 2.40
                      Heartwood   V 188  RP 105  V/RP 1.79
                      Charter     V 206  RP 140  V/RP 1.47
   price buys power ✓        cheapest leads V/RP, dearest leads V ✓

combined, by price:   Reed Raft   V 103  RP  55  V/RP 1.88
                      Stonewright V 282  RP 175  V/RP 1.61
   price buys power ✓        cheapest leads V/RP, dearest leads V ✓

siege ship (exempt):  Ember Monitor V 127 RP 210 — named property:
                      range 11.0 outranges every shore tower, and
                      damage_vs_buildings 0.85 wrecks what it reaches.

transports (exempt — V cannot price carrying):
   capacity per RP:   Corpse Barge 0.040 · Leafskiff 0.031 ·
                      Merchant Hull 0.029 · Ironhull 0.013
```

The transport ordering is the civ story told in one column: Gravesworn
(quantity) moves armies cheapest, Emberdeep (fortification) moves them in
the toughest and dearest hull in the game. Nobody had to write a
civ-specific rule for that.

**A test must recompute this**, not quote it — `tests/test_naval_roster.gd`
in the same shape as the existing power-budget screen, so a `.tres` edit
that breaks "price buys power" goes red rather than shipping.

### 5.4 Flavour, one line each

- **Stonewright Barge** — a raft of quarried stone and lashed trunks that
  should not float and does. Carries two squads of giants or their
  thralls, and fights anything that comes near it.
- **Bone Skiff** — eight low hulls rowed by things that do not tire.
  Fearless (`rout_threshold 0`, like the rest of the civ), brittle,
  and there are always more.
- **Corpse Barge** — a flat scow piled with the dead, sitting low.
- **Heartwood Cutter** — a living hull grown rather than built; the
  longest reach on the water, as the longest bows are on land.
- **Leafskiff** — the fastest transport in the game and the flimsiest.
- **Reed Raft** — bundled reed and hide, poled rather than sailed. Fast,
  cheap, and a bad idea in a fight.
- **Charter Galley** — hired, gold-priced, and the best fighting ship
  money can buy in a game where Gildedreach has the money.
- **Merchant Hull** — a fat trader carrying three squads and no weapon.
- **Ember Monitor** — a low iron gun-platform that outranges a shore
  tower and takes its time.
- **Ironhull** — a riveted troop-carrier built to be shot at.

Art: `model_id` stays empty for all ten (#301's own constraint), so they
draw as the primitive tier — `mesh_primitive = "hull"` already exists in
the schema. Nothing gates on the blocked `bpy` pipeline.

---

## 6. Consumers — the part D-076 got wrong

D-076's own entry ends: *"no AI behavior for building or using
walls/gates exists yet — `just ai-ladder` cannot exercise any of this
feature until an AI player is taught to want one."* Sixteen days later
that was still true, and it is exactly why #210 (an auto gate never
opened for an ally) sat undetected: **the estate had no way to run the
feature.**

This design treats the consumers as part of the feature, not as
follow-up.

### 6.1 The AI

`ai_player.gd` gains one question and one behaviour, both expressed
against data so no script names a civ:

- **"Is there an enemy I cannot walk to?"** The AI already has
  `terrain_knowledge.gd`-style belief; the naval trigger is
  *my start's landmass does not contain a known enemy building or
  spawn*. On `islands` that is true immediately; on `continents` it is
  almost never true, so the behaviour costs nothing where it is not
  wanted.
- **Then: build a dock → train a transport → embark the raid pool →
  land near the enemy → resume ordinary attacking.** Every step reuses an
  existing AI mechanism (`_raise_buildings` with a site rule,
  `_train`, the raid pool from #123).

Difficulty stays data (`AiProfileDef`, D-20260818): one knob,
`naval_commitment`, deciding how much of the army is willing to sail.
**No profile may be given a naval bonus** — a profile changes what the AI
DECIDES, never what it KNOWS or is GIVEN.

### 6.2 The gates, which are the point

New `AI_STATS` keys: `docks`, `ships_peak`, `embarks`, `landings`,
`naval_attacks`.

| harness | new gate |
|---|---|
| `just ai-ladder` on an islands map | **fails** unless `landings > 0` across the run |
| `just test-load` on an islands map | **fails** unless `embarks > 0` and `landings > 0` |
| `just test-ai-teams` | unchanged, but an allied landing is the natural next case |

And the vacuity guards this project always needs, because
`landings = 0` is what a free-for-all, an unplayed match and a broken
transport all report: the verdict must fail FIRST on "no dock was ever
built", then "no ship was ever trained", then "no squad ever embarked" —
so a zero tells you *which* leg broke rather than that something did.

**A scenario, so the loop is fast.** `scenarios/beachhead.tres` — two
players on separate landmasses, docks standing, wallets full — in the
same shape as `siege` and `clash`. `just test-scenario beachhead 4 30`
becomes the naval loop, and `test-load` on `maps/isles.tres` stays the
gate. Per D-098 a scenario cannot see founding or production, so the
gate keeps its job.

### 6.3 The bots

`bot_client.gd` must exercise embark and landing under the real wire —
that is what makes `test-load`'s new gate mean anything. It follows
`bot_patrol.gd`'s existing shape: a pure, static, testable decision
module (`bot_naval.gd`) deciding when a crew sails, so the half with the
interesting failure mode is testable without a server.

### 6.4 Everything else that has to know

- **Minimap** (`minimap_paint.gd`): ships are squads and already paint
  through `squad_marks`; **check** they do rather than assume it.
- **Render**: a ship sits at sea level, not on the terrain surface — the
  sampler must not lift it onto the seabed. `PrimitiveUnit` needs a
  domain-aware height, and it is the one render change that is not free.
- **Fog**: unchanged. Ships are squads; D-004 gates them.
- **Spawn placement**: once ships exist, `D-20260827`'s
  "every start shares one landmass" rule is **wrong** for naval maps and
  must become "every start shares one *reachable* component, where
  reachable includes water for civs that can cross it". §7 stage 9.

---

## 7. The staged cut-list

Written so the orchestrator can hand these to separate workers. The
dependency graph is deliberately shallow: **1 → {2, 3} → {4, 5, 6, 8} →
{7, 9}**.

| # | stage | depends on | deliverable | done when |
|---|---|---|---|---|
| **1** | **The water graph** | — | `TerrainGen.navigability(space)`; a shore-cell predicate; water components via the existing component walk | tests only, no sim change; navigability + passability are disjoint and cover the map |
| **2** | **The water domain** | 1 | `DOMAIN_WATER`; `is_passable` dispatch; `_fields_water` + `water_field_cells_per_tick`; `UnitDef.movement_domain`; order correction (§2.4) | a water squad paths; **a measured budget and worst tick**, quoted with squad count, the way D-076 measured the wall layer |
| **3** | **Docks** | 1 | `BuildingDef.needs_shore`; shore refusal; per-instance water cell; `dock.tres`; ship spawn into water | a dock refuses inland ground and accepts a shore; a hull appears in water |
| **4** | **Embark / disembark** | 2, 3 | cargo on the carrier; the two hops; sink-kills-cargo; `SQUAD_INFO.cargo` | a land squad crosses water and lands; **`composition_hash` matches with cargo aboard** |
| **5** | **Naval combat** | 2 | `_can_reach_domain` generalising `_can_reach_tier` | melee cannot cross a shoreline, ranged can, both observed to fail first |
| **6** | **Content** | 3 | the ten ship `.tres` + `dock.tres`; `tests/test_naval_roster.gd` recomputing the D-072 screen | every rule in §5.3 holds as a test, not a table |
| **7** | **AI + bots** | 4, 5, 6 | the AI's naval question and behaviour; `bot_naval.gd`; `AI_STATS` keys; ladder + load gates; `beachhead` scenario | **a landing happens in a played match**, and the gate fails when it does not |
| **8** | **Presentation** | 2 | ship height at sea level; minimap check; selection over water | a rendered frame with ships on water, looked at |
| **9** | **Maps** | 1, 7 | spawn placement over the water graph; `islands` back in the lobby | `islands` seats its full slot count with every start reachable |

### 7.1 Interface contract — PINNED

**These signatures are the contract three other workers are writing
against. Stage 2 owns them; nobody else changes them without saying so.**
Ruled by the orchestrator 2026-08-28 in response to this document's own
sequencing note that stage 2's signatures should be agreed before it is
written.

#### The decoupling that lets stages 1, 2 and 3 run in parallel

**Stage 2 never calls `TerrainGen`.** The navigability array is HANDED to
the simulation exactly as passability already is:

```gdscript
# SquadSim - the input. Mirrors set_passable, including the cache flush.
func set_navigable(p: PackedByteArray) -> void
```

So stage 1 produces the array, stage 2 consumes an argument, and the
server wires the two together in whichever stage lands second. Neither
worker edits the other's file, and stage 2 is testable with a
hand-authored field before stage 1 exists at all — which is how
`_passable` has always been testable.

#### Domains

```gdscript
# SquadSim - three mutually exclusive values of the field formerly
# meaning "tier". `tier_of(squad)` keeps its NAME (D-076's call sites
# are not churned) and returns one of these.
const DOMAIN_GROUND := 0
const DOMAIN_WALL_TOP := 1
const DOMAIN_WATER := 2
```

#### Passability dispatch, and the empty-array default per domain

```gdscript
func is_passable(cell: Vector2i, domain: int = DOMAIN_GROUND) -> bool
```

The defaults are **not** uniform, and each one has a reason that is
already in the codebase:

| domain | array | empty means | why |
|---|---|---|---|
| `DOMAIN_GROUND` | `_passable` | **open** | a bare `SquadSim` in a test is an open field; unchanged |
| `DOMAIN_WALL_TOP` | `_passable_top` | **closed** | D-076: "no walkway exists at all"; most sims have no walls |
| `DOMAIN_WATER` | `_navigable` | **closed** | same argument as wall-top: most sims have no sea, and "everything is navigable" would sail a ship across a test map that is meant to be a field |

That last row also makes the domains **disjoint by construction in a
terrain-less sim**: everything is land, nothing is water.

#### Flow fields

```gdscript
# `domain` is the third parameter and defaults to DOMAIN_GROUND, so every
# existing call site is unchanged.
func _field_for(destination_index: int, knower: int,
        domain: int = DOMAIN_GROUND) -> FlowField
```

| domain | cache | key | solved against | budget |
|---|---|---|---|---|
| ground | `_fields` | `(destination, side)` | `knowledge.believed_passable(side)` | `field_cells_per_tick` (D-040) |
| wall-top | `_fields_top` | `destination` | `_passable_top` (ground truth) | `top_field_cells_per_tick` (D-076) |
| **water** | `_fields_water` | **`(destination, side)`** | **`knowledge.believed_navigable(side)`** | **`water_field_cells_per_tick`** |

**Water is keyed by SIDE and solved against BELIEF, like ground and
unlike wall-top — and that is a decision, not a copy.**
`D-20260818-pathing-knows-only-what-the-player-knows` deliberately leaves
the wall-top tier omniscient, and states why: *"the wall-top tier
(D-076), whose network is made of buildings a side put there itself."*
Water is not that. **The obstacles at sea are LAND**, and an undiscovered
island is exactly the thing belief exists to stop a side routing around.
A ground-truth naval field would rebuild #96 in a second domain.

So **stage 2 also owns extending `TerrainKnowledge`** with a second
per-side array:

```gdscript
# TerrainKnowledge - mirrors believed_passable / believes_passable.
func believed_navigable(group: int) -> PackedByteArray
func believes_navigable(group: int, cell: int) -> bool
# absorb() gains the second truth array; discover() gains a domain.
```

Optimism is unchanged and points the same way: **unknown reads
NAVIGABLE**, so believed-navigable is a superset of truly-navigable and a
side can only ever be refused a voyage that was genuinely impossible.

#### The per-tick accounting

```gdscript
var water_field_cells_per_tick: int = <MEASURED - see below>
var _fields_water := {}
var _pending_fields_water: Array[Vector2i] = []
var _field_cells_this_tick_water: int = 0   # reset at tick start
```

**The number is a measurement, not a copy of D-076's 1,024.** `islands`
is 65-71% water, so on the map this feature exists for the naval layer
solves over roughly twice the area the ground layer does — and it lands
on a tick already at 204.5 ms against D-020's 100 ms at 1,000 squads
(#105). Stage 2 ships a derived figure with its worst tick and squad
count, the way D-076 measured the wall layer.

#### Unit schema (D-010 log)

```gdscript
# UnitDef
@export_enum("ground", "water") var movement_domain: String = "ground"
@export var transport_capacity: int = 0
```

`movement_domain` is a STRING enum, matching `armour_class` and
`formation_shape`, so a `.tres` reads as words rather than a magic
integer. The mapping to `DOMAIN_*` happens once, in `SquadSim.add_squad`.

#### Building schema (stage 3, pinned here so stage 3 need not wait)

```gdscript
# BuildingDef
@export var needs_shore: bool = false
```

```gdscript
# TerrainGen - stage 1's output, consumed by stages 2 and 3.
func navigability(space: TorusSpace) -> PackedByteArray   # 1 iff elevation < sea_level
func is_shore(space: TorusSpace, cell: Vector2i) -> bool  # passable land, >=1 navigable neighbour
```

`is_shore` walks `TorusSpace.disk_offsets(1)`, never `distance()` — the
standing rule.

#### Who owns what

| symbol | owner |
|---|---|
| `TerrainGen.navigability`, `TerrainGen.is_shore`, water components | stage 1 |
| `DOMAIN_*`, `set_navigable`, `is_passable` dispatch, `_fields_water`, `TerrainKnowledge` water belief, `UnitDef.movement_domain` | stage 2 |
| `BuildingDef.needs_shore`, the shore refusal, the per-instance water cell, ship spawn into water | stage 3 |
| `UnitDef.transport_capacity` (the field), cargo, the hops | stage 4 |
| the ten ship `.tres` and `dock.tres` | stage 6 |

**`transport_capacity` is declared by stage 2** (it is one line in the
same schema edit) and **read by nobody until stage 4**, so stage 6 can
author `.tres` files against it immediately. A field declared and unread
is normally this project's most-repeated defect — it is deliberate here,
it is bounded to two stages, and stage 4's exit criterion is what closes
it.

**Two sequencing notes for whoever schedules this.**

Stage 2 is the long pole and everything downstream waits on its
interfaces, so its **signatures should be agreed before it is written** —
`is_passable(cell, domain)`, `_field_for(destination, domain)`,
`movement_domain`. Stages 3 and 6 can start immediately after 1 and touch
almost nothing stage 2 touches.

Stage 7 is the one that must not be dropped. If the schedule slips,
**cut content (6) before consumers (7)** — two ships that the AI sails are
worth more than ten it has never heard of, and that is the whole lesson
of D-076's standing gap.

---

## 8. What this costs, and the honest unknowns

**Measured before designing, so the risk is stated rather than
discovered:**

- **`islands` is 65–71% water** across 12 sampled worlds (29–35%
  walkable). So on the map this feature exists for, the naval flow-field
  layer solves over roughly **twice the area** the ground layer does. The
  budget in stage 2 is therefore not a copy of D-076's 1,024.
- **The 1,000-squad tick is already over budget** — 204.5 ms against
  D-020's 100 ms (#105) — and this adds a third field layer. Stage 2's
  measurement must be read against that, and `just profile` should sweep
  a water map before stage 7 lands.
- **The client frame is already 5.4–5.9 fps at 1,000 squads** (#229) and
  ships add drawn entities. They are few and large, which is the cheap
  direction, but "few" is an assumption until a ship count exists.

**Genuinely unknown, and named so nobody pretends otherwise:**

- Whether a naval game is *fun* here. Nothing in this document can
  establish that; the owner playing a match on `islands` is the only
  instrument, and it is D-085 criterion 14's lesson applied in advance.
- Whether two ships per civ is enough content for the axis differences to
  read in play, or whether it will feel like one ship with six paint
  jobs. §5.3's capacity-per-RP spread is the argument that it will; a
  playtest is the evidence.
- What happens to match length. A naval map means marches become
  voyages, and `docs/status/load-testing.md`'s standing rule applies with
  force: **when the opening changes, every timing tuned against the old
  one is stale.** Expect `test-load`'s contact-dependent fog gates to
  need re-measuring on any water map.

---

## 9. What happens to #280

`D-20260828-a-map-a-player-can-pick-is-a-map-an-army-can-cross` retired
`islands` from the lobby on the measurement that it cannot host a match.
**The owner has overruled the conclusion, and this design is the other
exit that entry named.** That decision is superseded by the water-domain
decision; its `TerrainPreset.playable` mechanism survives and becomes the
switch stage 9 flips.

**One question for the owner, and it is one line either way:** should
`islands` be *offered in the lobby while naval is being built* — a period
in which it is still a map that cannot host a match — or stay hidden
until stage 9? The measurement says hidden; the directive says naval.
Recommendation: **keep it hidden until stage 9, and make flipping it the
last item of the cut-list**, so the preset becomes visible on the day it
becomes playable. If the owner would rather it stay visible throughout,
that is one bool in `terrain/islands.tres` and this document's stage 9
loses its last row.

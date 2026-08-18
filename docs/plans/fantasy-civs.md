# Fantasy Civilisations — six civs and their rosters (design product)

Status: DESIGN ONLY. Nothing here is implemented — no `.tres` exists for
any of it, `/units` and `/civs` are untouched, and the pivot itself is
awaiting the owner's call
(`decisions/D-20260818-fantasy-civs-supersede-the-historical-frame.md`,
Proposed). This document is the content: the civ set, full unit rosters
with stats, strengths/weaknesses, and visual direction — packaged so
Claude Design can produce one-page roster sheets from it without knowing
the codebase.

---

## Part 1 — Brief to Claude Design

Produce **six one-page civ roster sheets**, one per civilisation in
Part 3. Each sheet should carry:

- The civ's name, emblem concept, colour swatch, and one-line thesis
  (the **Axis** row of the frame table).
- The seven-column identity row (Part 2) rendered as a readable header
  block — playstyle, best-at, bad-at, signature.
- The unit roster as cards or rows: name, role, the key stats
  (squad size, HP, damage, range, speed, cost), and the one-paragraph
  description with strengths/weaknesses from Part 3.
- A silhouette sketch or visual treatment per unit, following the visual
  notes given with each unit.

**Art constraints that are real, not stylistic preference:**

- **Silhouette first.** Models are stylised low-poly at **~300 triangles
  per soldier**, generated procedurally (Blender headless from committed
  Python — D-081). A unit must be readable at RTS zoom among up to
  40,000 soldiers on screen. Design shapes, not surface detail: helmet
  profile, weapon angle, mount vs foot, tall vs squat, banner vs none.
- **Colour belongs to the PLAYER, not the civ.** In a match, ownership
  is shown by per-player colour (D-052); a civ's swatch appears only in
  the lobby. So two civs must be distinguishable **by shape alone** —
  never rely on "the undead are the green ones".
- **No visual effects.** No glows, transparency, particles, trails or
  emissive magic — the shipping shaders don't do them (the one
  transparent shader the project had was deliberately deleted, D-099).
  Fantasy reads through silhouette and animation, not VFX.
- **Animation is a single looping clip per model** (vertex animation
  texture, D-082). One walk/attack cycle; no ragdolls, no staged
  transformations.

---

## Part 2 — The design frame

The frame is inherited from D-071 with the historical **Basis** column
replaced by a fantasy folk. Governing rule unchanged: **no two civs may
match on more than one column.**

| | Stoneblood | Gravesworn | Thornwood | Windmarch | Gildedreach | Emberdeep |
|---|---|---|---|---|---|---|
| **Axis** | quality | quantity | ranged attrition | mobility | economy & flexibility | fortification & siege |
| **Folk** | giant-kin and their hill-tribe thralls | a deathless court and its raised legions | sylvan elves of a sentient forest | centaur clans of the open steppe | free cities of men and half-bloods | deep-hold dwarves |
| **Economy** | steady; strong from few well-held sites | tithed, not grown; cheapest army to raise | forage-led, wood-rich, gold-poor | low infrastructure; settles late and lightly | highest gather and the broadest use of gold | slow, secure, stone-heavy |
| **Military** | few, mighty foot; no cavalry, no engines | fearless brittle hordes + one horror engine | the longest bows; adequate foot, light stags | everything mounted; no siege, no heavy foot | broadest roster, most of it gold-priced | defensive foot, rams and bombards; no cavalry |
| **Best at** | winning even fights; holding a line | trading armies; never breaking | grinding down at distance; forest fighting | map control; punishing overextension | out-scaling; adapting late | holding ground *and* cracking it |
| **Bad at** | reacting; being everywhere | per-soldier quality; speed | being closed on; cracking walls | taking fortified ground | any specific fight before it is rich | open field; early tempo |
| **Signature** | Gatebreakers — elder giants who ARE the siege train | the Barrow Shades — fearless flankers | Dawnfletch Sentinels — longest reach in the game | Bowriders — mounted missile at reach | Gilded Sellswords — elite heavy, gold-priced | the Ember Bombard — outranges towers |

**Frame audit** (the two closest pairs, checked rather than assumed):
*Emberdeep and Stoneblood* both fight slow and heavy, but one holds with
structures and cracks them with engines, the other holds with bodies and
cracks nothing it can't reach with a fist — they share no column.
*Thornwood and Windmarch* both harass, but one stands still and shoots
furthest, the other never stands still — no shared column. Rule holds.

**All six ids verified** against every non-addon `.gd` file
(`grep -ril <id> --include=*.gd .` returns nothing for all six),
checked before the names were chosen, per D-071's own procedure.

**Arc test (M9 compatibility).** Each civ has a five-stage development
arc for D-069's epochs (settle → field → hold → break → decide), one
line each, so this set survives the epoch plan if M9 proceeds:

| Civ | settle → field → hold → break → decide |
|---|---|
| Stoneblood | scattered hill-clans → thrall levies → giants walk to war → gatebreaker broods → the Old Blood wakes |
| Gravesworn | a barrow court → corpse levies → bone legions → carrion engines → the Court rides out |
| Thornwood | glade wardens → heartbows strung → the forest marches → sentinel groves → the Wood itself moves |
| Windmarch | wandering clans → colt musters → the great herds → the clans confederate → storm-host at full gallop |
| Gildedreach | a market town → the city watch → charter companies → contract engines → coin buys anything |
| Emberdeep | a delved hold → hearth levies → the shieldwall → rams and bombards → the deep gates open |

---

## Part 3 — The civilisations and their rosters

### Reading the stat blocks

Fields are the actual `UnitDef` schema (D-010) — every number below maps
to a field that exists today:

- **sz** squad_size · **hp** health per soldier · **dmg** damage per
  soldier · **int** attack_interval (s) · **rng** attack_range ·
  **spd** move_speed · **cost** food/wood/gold/stone
- **class** is `armour_class` — exactly three values exist
  (infantry / cavalry / missile) and the counter triangle (D-032) is:
  **spears counter cavalry, cavalry counters missile, missile counters
  infantry**, expressed as `bonus_vs` multipliers.
- **V** = sqrt(DPS × EHP) and **RP** = food + wood + 1.5×(gold + stone),
  the D-072 power budget. Line units target the band **V 550–780,
  V/RP 11–21**; specialists are exempt but each names the property V
  cannot price. Two rules hold throughout: within a role, **price buys
  power** (more expensive ⇒ higher V), and **no unit leads on both V and
  V/RP** in its role.
- All six civs also field the neutral `founders` and `gatherers`
  (unchanged, D-031).

Mounted missile units take `armour_class = cavalry`, not missile —
they are mounted, so spears must counter them (D-072's rule).

---

### 1. STONEBLOOD — the giant-kin (quality)

Few and mighty. A Stoneblood army is small, slow to muster, and wins
any fight it is allowed to stand in. Its weakness is arithmetic: it
cannot be in two places, and every casualty is a real loss.

**CivDef:** colour slate `(0.45, 0.50, 0.58)` · start 250f / 180w / 0g / 60s ·
knobs at default (see Part 4 on the knobs).

| unit | archetype | class | sz | hp | dmg | int | rng | spd | cost | V | V/RP |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Hillkin Clubs | levy | infantry | 24 | 95 | 8.5 | 1.0 | 1.9 | 3.2 | 50f | 682 | 13.6 |
| Young Giants | heavy | infantry | 8 | 380 | 30 | 1.2 | 2.2 | 3.0 | 70f 30g | 780 | 6.8 |
| Cragthrowers | skirmishers | missile | 12 | 110 | 14 | 1.8 | 5.5 | 3.0 | 45f 20w | 351 | 5.4 |
| Gatebreakers ★ | breaker | infantry | 6 | 420 | 24 | 1.5 | 2.4 | 2.6 | 60f 60s | 492 | 3.3 |

★ exclusive. No cavalry, no engines — a giant is his own siege train.
Budget check: levy leads V/RP, heavy leads V; price buys power ✓.

- **Hillkin Clubs** — the hill tribes who serve the giants; ordinary men
  with heavy mauls. *Strong:* tough for a levy, holds a line. *Weak:*
  slow, no reach, melts to massed archery.
  *Visual:* squat broad silhouette, fur cloak, two-handed club held
  across the body; the "normal-sized" unit that makes the giants read
  as giants beside them.
- **Young Giants** — eight to a squad and each worth a file of men.
  *Strong:* highest per-soldier stats in the game; wins even fights
  outright. *Weak:* missile fire (armour_class infantry — archers get
  their bonus against them), and there are only eight of them.
  *Visual:* 2.5× human height, hunched shoulders, tree-trunk club,
  bare head. Spend the triangle budget on mass, not detail — the
  silhouette IS the unit. `formation_spacing` ~2.4.
- **Cragthrowers** — giants who throw quarried stone. *Strong:* thrown
  rocks also chip walls (`damage_vs_buildings 0.35`). *Weak:* slow rate
  of fire; outranged by every true bow.
  *Visual:* giant leaning back mid-throw, boulder overhead — a readable
  "ranged" pose at distance.
- **Gatebreakers ★** — elder giants bred to break fortifications.
  *Strong:* `damage_vs_buildings 0.85` — walls and towers come apart
  under them. *Weak:* slowest unit in the roster; terrible value against
  flesh (V 492 at RP 150); named property: wall-breaking, which V does
  not price.
  *Visual:* biggest silhouette in the game, dragging a stone maul,
  head-down walk like a battering ram deciding to be a person.

---

### 2. GRAVESWORN — the deathless court (quantity)

The cheapest army in the game and the only one that never runs.
Gravesworn squads have `rout_threshold 0` — they fight to the last —
but every soldier is brittle and slow, and quality kills them faster
than they can be mourned. (They are not mourned.)

**CivDef:** colour bone `(0.72, 0.74, 0.62)` · start 280f / 140w / 20g / 0s ·
`squad_cap_bonus +4`, `production_speed 1.15` — **both currently inert,
see Part 4.**

| unit | archetype | class | sz | hp | dmg | int | rng | spd | cost | V | V/RP |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Corpse Levy | levy | infantry | 48 | 40 | 4.8 | 1.0 | 1.9 | 3.0 | 32f | 665 | 20.8 |
| Bone Pikes | spearmen | infantry | 40 | 45 | 5.2 | 1.1 | 1.9 | 3.0 | 30f 14w | 583 | 13.3 |
| Barrow Shades ★ | shades | infantry | 20 | 38 | 7.5 | 1.0 | 1.9 | 4.8 | 25f 15g | 338 | 7.1 |
| Carrion Hurler | engine | missile | 3 | 90 | 30 | 4.0 | 10.0 | 2.2 | 30f 60w 30g | 78 | siege |

★ exclusive. No cavalry. All squads: `rout_threshold 0`,
`morale_loss_per_casualty 0` (nothing to lose).

- **Corpse Levy** — forty-eight raised dead with rusted blades.
  *Strong:* the best V/RP in the game (20.8, band ceiling); never routs,
  so every engagement is paid in full. *Weak:* worst per-soldier stats
  in the game; slow; a lost squad is 48 bodies gone.
  *Visual:* gaunt, hunched, ragged silhouette; broken-line ranks
  (formation `sparse` reads well) — the ONE unit whose formation should
  look untidy on purpose.
- **Bone Pikes** — skeletons under old discipline, pikes levelled.
  *Strong:* `bonus_vs cavalry 1.6` — the hard stop against mounted civs;
  fearless, so cavalry cannot scatter them. *Weak:* crumbles to any
  dedicated melee push.
  *Visual:* vertical pike-line silhouette, tattered banners; reads as a
  hedge of points at zoom.
- **Barrow Shades ★** — the court's hunting dead: fast, quiet, fearless.
  *Strong:* speed 4.8 on foot, vision 15 — flanker and economy-raider
  that never checks its morale. *Weak:* paper-thin; loses to anything
  that turns and fights. Named property: speed + fearlessness.
  *Visual:* tall thin silhouette, long ragged cloak pulled to a point —
  shape says "wraith" with zero transparency or glow (none available).
- **Carrion Hurler** — a gallows-frame engine that lobs corpses and
  worse. *Strong:* range 10, `damage_vs_buildings 1.0` — the horde's
  answer to walls. *Weak:* three crew, near-defenceless, slowest thing
  on the field.
  *Visual:* crooked trebuchet-silhouette built of bone and timber; the
  throwing arm's arc is the animation.

---

### 3. THORNWOOD — the sylvan elves (ranged attrition)

Thornwood wins by never letting the fight start. The longest bows in
the game, backed by adequate wardens and fast stags — and almost no
answer to a wall, or to an enemy already at arm's length.

**CivDef:** colour deep green `(0.22, 0.42, 0.28)` · start 240f / 260w / 0g / 0s.

| unit | archetype | class | sz | hp | dmg | int | rng | spd | cost | V | V/RP |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Glade Wardens | levy | infantry | 28 | 62 | 6.4 | 1.0 | 1.9 | 3.5 | 40f | 558 | 13.9 |
| Heartbow Archers | archers | missile | 26 | 50 | 9.0 | 1.5 | 8.0 | 3.2 | 35f 35w | 450 | 6.4 |
| Stag Riders | cavalry | cavalry | 14 | 70 | 8.0 | 1.0 | 1.9 | 5.8 | 40f 20g | 331 | 4.7 |
| Dawnfletch Sentinels ★ | greatbow | missile | 16 | 55 | 16 | 2.2 | 9.5 | 2.8 | 40f 50w | 320 | 2.8 |

★ exclusive. No siege of any kind — the civ's stated hole.

- **Glade Wardens** — spear-and-leaf-blade foot who exist to stand in
  front of the bows. *Strong:* cheap, quick for line infantry. *Weak:*
  bottom of the line band (V 558) — they hold ground, they do not take
  it.
  *Visual:* slender upright silhouette, leaf-bladed spear, high pointed
  helm — the vertical line that contrasts with dwarf/giant bulk.
- **Heartbow Archers** — recurves of heartwood, range 8. *Strong:*
  `bonus_vs infantry 1.4`; outranges every other common archer; vision
  14. *Weak:* folds instantly in melee; expensive in wood.
  *Visual:* drawn-bow profile, quiver at hip, asymmetric stance —
  the draw animation is the identity.
- **Stag Riders** — wardens on great forest stags. *Strong:* speed 5.8,
  vision 18, `bonus_vs missile 1.4` — runs down enemy archers and
  scouts. *Weak:* fragile for cavalry; loses to any true lancer. Named
  property: speed + vision.
  *Visual:* antlered mount silhouette — the antlers make it readable as
  "not a horse" at any zoom, which is the whole visual job.
- **Dawnfletch Sentinels ★** — man-tall bows loosed from planted
  stakes. *Strong:* range **9.5, the longest reach in the game** —
  outranges a tower's return fire is NOT claimed (tower stats decide
  that at implementation); picks apart formations before contact.
  *Weak:* slowest elves fielded; dreadful in melee; slow loosing rhythm.
  Named property: reach.
  *Visual:* kneeling archer behind an angled stake, bow taller than the
  soldier — a distinct two-element silhouette.

---

### 4. WINDMARCH — the centaur clans (mobility)

Everything Windmarch fields is mounted because everything Windmarch IS
is mounted. It cannot take a fortified position and does not want to —
it wants your gatherers, your reinforcements, and every map objective
you left lightly held.

**CivDef:** colour steppe tan `(0.72, 0.60, 0.38)` · start 260f / 160w / 20g / 0s.

| unit | archetype | class | sz | hp | dmg | int | rng | spd | cost | V | V/RP |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Colt Levy | levy | cavalry | 28 | 61 | 6.5 | 1.0 | 1.9 | 4.4 | 38f | 558 | 14.7 |
| Harriers | skirmishers | cavalry | 24 | 48 | 6.0 | 1.0 | 1.9 | 4.6 | 26f | 408 | 15.7 |
| Storm Lancers | cavalry | cavalry | 16 | 85 | 11 | 1.1 | 1.9 | 6.0 | 50f 30g | 466 | 4.9 |
| Bowriders ★ | bowriders | cavalry | 16 | 58 | 7.5 | 1.2 | 5.0 | 6.2 | 35f 25g | 305 | 4.2 |

★ exclusive. No siege, no heavy foot. **Every unit is
`armour_class cavalry`** — the entire civ is countered by spears, and
that is the deliberate cost of an all-mounted roster.

- **Colt Levy** — young centaurs with spear and hide shield; the only
  "line" in the clans. *Strong:* a line unit that moves at 4.4 — it
  arrives first. *Weak:* every enemy spearman gets a bonus against the
  whole civ, this unit included.
  *Visual:* the four-legged silhouette does all the work; keep the spear
  upright so the line reads as a line.
- **Harriers** — light youths who circle and prod. *Strong:* dirt cheap
  screen and chaser (V/RP 15.7). *Weak:* wins nothing on its own.
  *Visual:* smaller, lighter centaur frame, javelin raised; visually the
  "colt" beside the Lancers' "stallion".
- **Storm Lancers** — the clans' shock: full gallop, levelled lances.
  *Strong:* speed 6.0, `bonus_vs missile 1.5` — archers die to it, by
  design of the triangle. *Weak:* impales itself on any braced pike
  line. Named property: shock speed.
  *Visual:* biggest centaur silhouette, lance couched horizontal —
  horizontal line vs the levy's vertical.
- **Bowriders ★** — mounted missile at reach (class cavalry, per the
  triangle's rule: they are mounted, so spears must counter them).
  *Strong:* range 5 at speed 6.2, vision 20 — the map-control unit;
  shoots and cannot be caught by foot. *Weak:* loses to spears AND to
  longer bows standing still. Named property: information + reach while
  moving.
  *Visual:* centaur twisted at the waist loosing backwards — the Parthian
  shot IS the silhouette.

---

### 5. GILDEDREACH — the free cities (economy & flexibility)

Gildedreach fields the broadest roster in the game and excels with none
of it until the gold flows. Its identity is the ledger: the best
gatherers, the widest options, and an army that is bought rather than
bred.

**CivDef:** colour gold-on-crimson `(0.78, 0.62, 0.20)` · start
250f / 200w / 60g / 0s · `gather_speed 1.15` — **currently inert, see
Part 4.**

| unit | archetype | class | sz | hp | dmg | int | rng | spd | cost | V | V/RP |
|---|---|---|---|---|---|---|---|---|---|---|---|
| City Watch | levy | infantry | 30 | 68 | 6.3 | 1.0 | 1.9 | 3.4 | 45f | 621 | 13.8 |
| Pike Serjeants | spearmen | infantry | 28 | 72 | 6.8 | 1.1 | 1.9 | 3.2 | 35f 20w | 591 | 10.7 |
| Quarrel Companies | archers | missile | 24 | 55 | 10 | 1.8 | 6.5 | 3.2 | 30f 30w 10g | 420 | 5.6 |
| Hired Outriders | cavalry | cavalry | 14 | 75 | 9.0 | 1.0 | 1.9 | 5.6 | 30f 30g | 364 | 4.9 |
| Gilded Sellswords ★ | sellswords | infantry | 18 | 120 | 12 | 1.05 | 1.9 | 3.1 | 40f 60g | 666 | 5.1 |
| Contract Engines | engine | missile | 4 | 100 | 26 | 3.5 | 9.0 | 2.4 | 60w 70g | 108 | siege |

★ exclusive. Six combat units — the broadest roster, most of it
gold-priced. Budget check: Watch leads V/RP, Sellswords lead V ✓.

- **City Watch** — halberdiers of the city companies. *Strong:* the best
  all-round levy in the game (V 621). *Weak:* best-all-round is another
  word for unremarkable.
  *Visual:* polearm over shoulder, kettle hat, tabard — "town guard" at
  a glance.
- **Pike Serjeants** — professional pike blocks. *Strong:*
  `bonus_vs cavalry 1.5`; solid. *Weak:* slow to reposition; loses the
  archery exchange it will be standing in.
  *Visual:* dense vertical pike-forest silhouette, tighter and neater
  than the Gravesworn hedge — discipline vs decay, same archetype.
- **Quarrel Companies** — crossbow companies under contract. *Strong:*
  `bonus_vs infantry 1.3`; hits harder per bolt than any elf bow.
  *Weak:* range 6.5 — outranged by Thornwood everything; slow reload.
  *Visual:* horizontal crossbow held at eye line, pavise on the back —
  boxy silhouette against the elves' curves.
- **Hired Outriders** — mercenary light horse (true horses; the
  distinction from centaurs is the rider). *Strong:*
  `bonus_vs missile 1.4`; the flexible answer the rest of the roster
  lacks. *Weak:* mediocre at everything cavalry does.
  *Visual:* standard horse-and-rider — deliberately the baseline the
  fantasy mounts diverge from.
- **Gilded Sellswords ★** — companies of veteran heavy foot, paid in
  coin. *Strong:* V 666, best heavy infantry money buys; high morale.
  *Weak:* RP 130 of which 90 is gold-weighted — a fight lost with them
  is a treasury lost. Named property: elite line quality on demand.
  *Visual:* full plate silhouette, closed helm, banner-carrying front
  rank — the "expensive" read.
- **Contract Engines** — hired engineers and their springald batteries.
  *Strong:* range 9, `damage_vs_buildings 0.9` — walls are a line item.
  *Weak:* fragile, slow, and gold-hungry.
  *Visual:* wheeled frame with a horizontal bolt-thrower arm; crew of
  four gives it scale.

---

### 6. EMBERDEEP — the deep-hold dwarves (fortification & siege)

Emberdeep is the slowest army in the game and the hardest to remove
from anywhere it has decided to stand — and the one civ that both holds
walls and reliably brings them down.

**CivDef:** colour ember-on-iron `(0.68, 0.36, 0.16)` · start
250f / 160w / 0g / 100s.

| unit | archetype | class | sz | hp | dmg | int | rng | spd | cost | V | V/RP |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Hearth Levy | levy | infantry | 26 | 85 | 6.7 | 1.1 | 1.9 | 2.9 | 48f | 592 | 12.3 |
| Shieldwall Vanguard | heavy | infantry | 20 | 130 | 10.5 | 1.15 | 1.9 | 2.8 | 55f 25s | 689 | 7.4 |
| Tunnel Quarrels | archers | missile | 22 | 60 | 11 | 2.0 | 5.5 | 2.9 | 38f 25w | 400 | 6.3 |
| Deepram ★ | ram | infantry | 6 | 200 | 8 | 1.5 | 1.5 | 2.4 | 80w 20s | 111 | siege |
| Ember Bombard ★ | bombard | missile | 3 | 110 | 34 | 4.5 | 11.0 | 2.0 | 60w 80s | 87 | siege |

★ exclusive (two — the siege train is the civ). No cavalry; lowest
move speeds in the game across the board.

- **Hearth Levy** — every dwarf owns an axe and a shield. *Strong:*
  toughest levy per soldier after the giants' thralls. *Weak:* speed
  2.9 — it fights where it already is.
  *Visual:* squat wide silhouette, round shield, braided beard —
  half the height and twice the width of an elf, which is the pairing
  the sheets should show.
- **Shieldwall Vanguard** — the holds' professional wall of iron.
  *Strong:* V 689 heavy infantry that costs stone, not gold — the
  economy the civ already runs on. *Weak:* anything it cannot reach,
  which at speed 2.8 is most things.
  *Visual:* interlocked tower shields, only helms and axe-heads
  showing over the rim — the formation IS the silhouette (formation
  `tight`).
- **Tunnel Quarrels** — crossbows sighted in the dark of the delvings.
  *Strong:* hard-hitting bolts, `bonus_vs infantry 1.3`. *Weak:* short
  range for a shooting civ's bow — Emberdeep shoots to defend, not to
  attrit.
  *Visual:* heavy arbalest braced on a shield-spike; squat kneeling
  pose.
- **Deepram ★** — a covered ram on stone rollers, crewed by six.
  *Strong:* `damage_vs_buildings 1.0`, hp 200 per crew-dwarf — it
  reaches the gate and it opens the gate. *Weak:* damage 8 against
  flesh; an unescorted ram is a gift.
  *Visual:* roofed shed silhouette with a swinging iron-headed beam;
  reads as architecture on the move.
- **Ember Bombard ★** — the holds' answer to a tower: a squat mortar
  of hold-iron. *Strong:* range **11 — outranges every tower and every
  bow in this document**; `damage_vs_buildings 1.0`. *Weak:* three
  crew, interval 4.5, speed 2.0 — commit it or lose it. Named property:
  reach against structures.
  *Visual:* fat vertical-angled barrel on a stone carriage, crew with
  ram-rods; smoke puff is the animation beat (geometry, not particles).

---

## Part 4 — Constraints, caveats, and what was left out

**Everything above is expressible in the current schema**, with the
following honest exceptions and flags:

1. **The three CivDef mechanical knobs are read by nothing** (issue
   #158): `squad_cap_bonus`, `production_speed`, `gather_speed`. Two
   civ identities above lean on them (Gravesworn's cap/production,
   Gildedreach's gather). Until #158 is resolved — wire them or delete
   them — those identities are roster-and-numbers only, and the sheets
   should not promise them as live mechanics. They are marked inert at
   each use above.
2. **`rout_threshold 0` semantics need verifying before Gravesworn is
   built.** "Fearless" assumes morale can never fall strictly below 0;
   the rally-hysteresis path (`rout_rally_margin`) has never been
   exercised at threshold 0. One unit test settles it. Flagged, not
   assumed.
3. **Per-civ models break the current art convention.** `model_id` is
   keyed by ARCHETYPE, never by civ (unit_def.gd, D-081's reasoning:
   a model keyed by civ makes every new civ an art project). Six
   fantasy folks sharing one `levy` model is visually wrong in a way
   two human civs sharing it was not — a dwarf levy and a centaur levy
   cannot wear the same mesh. The rosters above minimise the collision
   by giving civs mostly DIFFERENT archetypes (the shared ones are
   levy, spearmen, archers, skirmishers, cavalry, heavy, engine), but
   the tension is real and is an owner decision recorded in the
   proposed decision entry, not something this document resolves.
   The art bill either multiplies per civ, or archetype models must be
   designed race-neutral (they cannot be, for centaurs).
4. **No active abilities of any kind.** Combat is squad-level,
   stochastic, aggregate server arithmetic (D-024). Nothing above
   requires — and nothing designed later may casually add — spells,
   healing, regeneration, summoning, flying, stealth, terrain
   alteration, unit conversion, auras, or hero units with progression.
   Each of those is an engine change, to be flagged as such.
   Fantasy in this game is stat shape, morale, and silhouette.
5. **Test constraints honoured on paper** (`tests/test_civs.gd`):
   every civ fields >2 archetypes with ≥1 exclusive; every shared
   archetype differs across civs in `damage`, `health` AND `cost_food`
   (checked for all shared archetypes above — implementers must keep
   this when tuning, including the engines' food components, which
   exist partly to satisfy it).
6. **V/RP numbers are D-072's first-pass screen, not balance.** V
   systematically undervalues range, speed, vision, `bonus_vs` and
   morale — which is why every specialist above names its non-V
   property, per D-072's own practice. All line units sit in the
   550–780 / 11–21 band; both budget rules hold within every civ.
7. **Left out deliberately:** epoch-by-epoch rosters (M9 is planned,
   not built — these are current-game-scale rosters of 4–6 units plus
   neutrals; the arc lines in Part 2 keep them M9-compatible);
   buildings beyond what BuildingDef already expresses (walls, gates,
   towers, drop-off, produces/built_by cover everything above); and
   any strength ordering between civs — that is `just ai-ladder`'s job
   once they exist, not this document's.

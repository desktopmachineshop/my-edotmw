# PROMPT FOR CLAUDE DESIGN — Six Fantasy Civilisation Roster Sheets

Copy everything in this file into Claude Design as one prompt. It is
self-contained: no game files or codebase access are needed.

---

## The job

Design **six one-page civilisation roster sheets** for a large-scale
fantasy real-time strategy game (think *Empires: Dawn of the Modern
World* meets *Rome: Total War*, at 40,000 soldiers on screen). One page
per civilisation, all six sharing a single visual layout system so they
read as a set. Print/PDF-friendly; portrait or landscape is your call,
but pick once and keep it.

Each sheet must carry:

1. **Civ header** — name, an emblem concept, the civ's colour swatch,
   and its one-line thesis (the "Axis" below).
2. **Identity block** — playstyle, what it's best at, worst at, and its
   signature unit, taken from the identity table below.
3. **The unit roster** — one card or row per unit with: name, role,
   key stats (squad size, HP, damage, attack speed, range, move speed,
   cost), the strengths/weaknesses description, and a silhouette
   illustration following each unit's visual note.
4. A small **counter-triangle reminder** somewhere on every sheet:
   **spears beat cavalry, cavalry beats missile, missile beats
   infantry.** Every unit lists its class (infantry / cavalry /
   missile) — that class is what the triangle acts on.

## Hard art constraints (engine facts, not taste)

- **Silhouette first.** In-game models are stylised low-poly, authored
  at roughly **10,000 triangles per unit** and automatically simplified
  at distance. A unit must be readable at RTS zoom in a crowd of
  thousands, so shape comes before surface detail: helmet profile,
  weapon angle, mount vs foot, tall vs squat, banner vs none. Your
  sheet illustrations should be silhouette-forward for the same
  reason — they are the reference the 3D models will be built to.
- **Colour belongs to the PLAYER, not the civ.** In a match, armies are
  tinted by per-player colour; a civ's swatch appears only in the
  lobby and on your sheet. **Two civs must be tellable apart by shape
  alone.** Never lean on "the undead are the green ones".
- **No visual effects.** No glows, transparency, particles, trails, or
  emissive magic — the engine's shaders don't do them. Fantasy reads
  through silhouette and animation only.
- **One looping animation per unit** (walk/attack cycle). No ragdolls,
  no transformations. Where a note below mentions an animation beat,
  it means geometry in motion, not effects.
- **No active abilities exist in this game.** No spells, healing,
  summoning, flying, stealth, or hero units. Do not imply them in
  descriptions or art. Fantasy here is stat shape, morale, and
  silhouette.

## Stat glossary

- **sz** — soldiers per squad (squads are the unit of play)
- **hp / dmg** — per soldier
- **int** — seconds between attacks (lower = faster)
- **rng** — attack range (melee ≈ 1.9; bows 5–9.5; engines 9–11)
- **spd** — move speed (2.0 crawling … 6.2 fastest thing alive)
- **cost** — food / wood / gold / stone

---

## The six civilisations

| | Stoneblood | Gravesworn | Thornwood | Windmarch | Gildedreach | Emberdeep |
|---|---|---|---|---|---|---|
| **Axis** | quality | quantity | ranged attrition | mobility | economy & flexibility | fortification & siege |
| **Folk** | giant-kin and their hill-tribe thralls | a deathless court and its raised legions | sylvan elves of a sentient forest | centaur clans of the open steppe | free cities of men and half-bloods | deep-hold dwarves |
| **Economy** | steady; strong from few well-held sites | tithed, not grown; cheapest army to raise | forage-led, wood-rich, gold-poor | low infrastructure; settles late and lightly | highest gather and the broadest use of gold | slow, secure, stone-heavy |
| **Military** | few, mighty foot; no cavalry, no engines | fearless brittle hordes + one horror engine | the longest bows; adequate foot, light stags | everything mounted; no siege, no heavy foot | broadest roster, most of it gold-priced | defensive foot, rams and bombards; no cavalry |
| **Best at** | winning even fights; holding a line | trading armies; never breaking | grinding down at distance; forest fighting | map control; punishing overextension | out-scaling; adapting late | holding ground *and* cracking it |
| **Bad at** | reacting; being everywhere | per-soldier quality; speed | being closed on; cracking walls | taking fortified ground | any specific fight before it is rich | open field; early tempo |
| **Signature** | Gatebreakers — elder giants who ARE the siege train | the Barrow Shades — fearless flankers | Dawnfletch Sentinels — longest reach in the game | Bowriders — mounted missile at reach | Gilded Sellswords — elite heavy, gold-priced | the Ember Bombard — outranges towers |

All six civs also field two shared civilian units — **Founders** (the
expedition that plants the first hall) and **Gatherers** (the work
crews) — which may appear as a small footnote row, identical on every
sheet.

---

### SHEET 1 · STONEBLOOD — the giant-kin (quality)

Few and mighty. A Stoneblood army is small, slow to muster, and wins
any fight it is allowed to stand in. Its weakness is arithmetic: it
cannot be in two places, and every casualty is a real loss.

**Swatch:** slate blue-grey. **Emblem concept:** a standing stone with
a fist-shaped shadow.

| unit | role | class | sz | hp | dmg | int | rng | spd | cost |
|---|---|---|---|---|---|---|---|---|---|
| Hillkin Clubs | line | infantry | 24 | 95 | 8.5 | 1.0 | 1.9 | 3.2 | 50f |
| Young Giants | heavy line | infantry | 8 | 380 | 30 | 1.2 | 2.2 | 3.0 | 70f 30g |
| Cragthrowers | ranged | missile | 12 | 110 | 14 | 1.8 | 5.5 | 3.0 | 45f 20w |
| Gatebreakers ★ | siege | infantry | 6 | 420 | 24 | 1.5 | 2.4 | 2.6 | 60f 60s |

★ = signature, unique to this civ. No cavalry, no engines — a giant is
his own siege train.

- **Hillkin Clubs** — the hill tribes who serve the giants; ordinary
  men with heavy mauls. *Strong:* tough for a levy, holds a line.
  *Weak:* slow, no reach, melts to massed archery.
  *Visual:* squat broad silhouette, fur cloak, two-handed club held
  across the body; the "normal-sized" unit that makes the giants read
  as giants beside them.
- **Young Giants** — eight to a squad and each worth a file of men.
  *Strong:* highest per-soldier stats in the game; wins even fights
  outright. *Weak:* missile fire, and there are only eight of them.
  *Visual:* 2.5× human height, hunched shoulders, tree-trunk club, bare
  head. Spend the shape budget on mass, not detail — the silhouette IS
  the unit.
- **Cragthrowers** — giants who throw quarried stone. *Strong:* thrown
  rocks also chip walls. *Weak:* slow rate of fire; outranged by every
  true bow.
  *Visual:* giant leaning back mid-throw, boulder overhead — a readable
  "ranged" pose at any distance.
- **Gatebreakers ★** — elder giants bred to break fortifications.
  *Strong:* walls and towers come apart under them. *Weak:* slowest
  unit in the roster; poor value against flesh.
  *Visual:* biggest silhouette in the game, dragging a stone maul,
  head-down walk like a battering ram deciding to be a person.

---

### SHEET 2 · GRAVESWORN — the deathless court (quantity)

The cheapest army in the game and the only one that never runs.
Gravesworn squads are **fearless — they fight to the last** — but
every soldier is brittle and slow, and quality kills them faster than
they can be mourned. (They are not mourned.)

**Swatch:** bone-white over pale grave-green. **Emblem concept:** a
crowned skull in profile, crown askew.

| unit | role | class | sz | hp | dmg | int | rng | spd | cost |
|---|---|---|---|---|---|---|---|---|---|
| Corpse Levy | line | infantry | 48 | 40 | 4.8 | 1.0 | 1.9 | 3.0 | 32f |
| Bone Pikes | anti-cavalry | infantry | 40 | 45 | 5.2 | 1.1 | 1.9 | 3.0 | 30f 14w |
| Barrow Shades ★ | flanker | infantry | 20 | 38 | 7.5 | 1.0 | 1.9 | 4.8 | 25f 15g |
| Carrion Hurler | siege engine | missile | 3 | 90 | 30 | 4.0 | 10.0 | 2.2 | 30f 60w 30g |

★ = signature. No cavalry. Every squad is fearless.

- **Corpse Levy** — forty-eight raised dead with rusted blades.
  *Strong:* most army per resource in the game; never routs, so every
  engagement is paid in full. *Weak:* worst per-soldier stats in the
  game; slow; a lost squad is 48 bodies gone.
  *Visual:* gaunt, hunched, ragged silhouette; deliberately untidy
  broken-line ranks — the ONE unit whose formation should look ragged
  on purpose.
- **Bone Pikes** — skeletons under old discipline, pikes levelled.
  *Strong:* the hard stop against mounted civs; fearless, so cavalry
  cannot scatter them. *Weak:* crumbles to any dedicated melee push.
  *Visual:* vertical pike-line silhouette, tattered banners; reads as a
  hedge of points at zoom.
- **Barrow Shades ★** — the court's hunting dead: fast, quiet,
  fearless. *Strong:* fastest thing on foot in this army; flanker and
  economy-raider that never checks its morale. *Weak:* paper-thin;
  loses to anything that turns and fights.
  *Visual:* tall thin silhouette, long ragged cloak pulled to a point —
  the shape says "wraith" with zero transparency or glow.
- **Carrion Hurler** — a gallows-frame engine that lobs corpses and
  worse. *Strong:* long reach; the horde's answer to walls. *Weak:*
  three crew, near-defenceless, slowest thing on the field.
  *Visual:* crooked trebuchet silhouette built of bone and timber; the
  throwing arm's arc is the animation.

---

### SHEET 3 · THORNWOOD — the sylvan elves (ranged attrition)

Thornwood wins by never letting the fight start. The longest bows in
the game, backed by adequate wardens and fast stags — and almost no
answer to a wall, or to an enemy already at arm's length.

**Swatch:** deep forest green. **Emblem concept:** a bow curved around
a bare tree.

| unit | role | class | sz | hp | dmg | int | rng | spd | cost |
|---|---|---|---|---|---|---|---|---|---|
| Glade Wardens | line | infantry | 28 | 62 | 6.4 | 1.0 | 1.9 | 3.5 | 40f |
| Heartbow Archers | ranged | missile | 26 | 50 | 9.0 | 1.5 | 8.0 | 3.2 | 35f 35w |
| Stag Riders | light cavalry | cavalry | 14 | 70 | 8.0 | 1.0 | 1.9 | 5.8 | 40f 20g |
| Dawnfletch Sentinels ★ | long-range | missile | 16 | 55 | 16 | 2.2 | 9.5 | 2.8 | 40f 50w |

★ = signature. No siege of any kind — the civ's stated hole.

- **Glade Wardens** — spear-and-leaf-blade foot who exist to stand in
  front of the bows. *Strong:* cheap, quick for line infantry. *Weak:*
  they hold ground; they do not take it.
  *Visual:* slender upright silhouette, leaf-bladed spear, high pointed
  helm — the vertical line that contrasts with dwarf and giant bulk.
- **Heartbow Archers** — recurves of heartwood. *Strong:* outranges
  every other common archer; punishes infantry hard. *Weak:* folds
  instantly in melee; expensive in wood.
  *Visual:* drawn-bow profile, quiver at hip, asymmetric stance — the
  draw is the identity.
- **Stag Riders** — wardens on great forest stags. *Strong:* fast,
  far-seeing; runs down enemy archers and scouts. *Weak:* fragile for
  cavalry; loses to any true lancer.
  *Visual:* antlered mount silhouette — the antlers make it readable as
  "not a horse" at any zoom, which is the whole visual job.
- **Dawnfletch Sentinels ★** — man-tall bows loosed from planted
  stakes. *Strong:* the longest reach in the game; picks apart
  formations before contact. *Weak:* slowest elves fielded; dreadful in
  melee; slow loosing rhythm.
  *Visual:* kneeling archer behind an angled stake, bow taller than the
  soldier — a distinct two-element silhouette.

---

### SHEET 4 · WINDMARCH — the centaur clans (mobility)

Everything Windmarch fields is mounted because everything Windmarch IS
is mounted. It cannot take a fortified position and does not want to —
it wants your gatherers, your reinforcements, and every objective you
left lightly held. The price: **the entire civ counts as cavalry, so
every enemy spear counters all of it.**

**Swatch:** steppe tan and sky. **Emblem concept:** a horsetail
standard streaming sideways.

| unit | role | class | sz | hp | dmg | int | rng | spd | cost |
|---|---|---|---|---|---|---|---|---|---|
| Colt Levy | line | cavalry | 28 | 61 | 6.5 | 1.0 | 1.9 | 4.4 | 38f |
| Harriers | screen | cavalry | 24 | 48 | 6.0 | 1.0 | 1.9 | 4.6 | 26f |
| Storm Lancers | shock | cavalry | 16 | 85 | 11 | 1.1 | 1.9 | 6.0 | 50f 30g |
| Bowriders ★ | mounted missile | cavalry | 16 | 58 | 7.5 | 1.2 | 5.0 | 6.2 | 35f 25g |

★ = signature. No siege, no heavy foot.

- **Colt Levy** — young centaurs with spear and hide shield; the only
  "line" in the clans. *Strong:* a line unit that arrives first.
  *Weak:* every enemy spearman gets a bonus against the whole civ,
  this unit included.
  *Visual:* the four-legged silhouette does the work; keep the spear
  upright so the line reads as a line.
- **Harriers** — light youths who circle and prod. *Strong:* dirt-cheap
  screen and chaser. *Weak:* wins nothing on its own.
  *Visual:* smaller, lighter centaur frame, javelin raised; visually
  the "colt" beside the Lancers' "stallion".
- **Storm Lancers** — the clans' shock: full gallop, levelled lances.
  *Strong:* fastest shock in the game; archers die to it. *Weak:*
  impales itself on any braced pike line.
  *Visual:* biggest centaur silhouette, lance couched horizontal —
  horizontal line against the levy's vertical.
- **Bowriders ★** — mounted archers at reach. *Strong:* shoots on the
  move and cannot be caught by foot; the map-control unit. *Weak:*
  loses to spears AND to longer bows standing still.
  *Visual:* centaur twisted at the waist loosing backwards — the
  Parthian shot IS the silhouette.

---

### SHEET 5 · GILDEDREACH — the free cities (economy & flexibility)

Gildedreach fields the broadest roster in the game and excels with none
of it until the gold flows. Its identity is the ledger: the best
gatherers, the widest options, and an army that is bought rather than
bred.

**Swatch:** gold on crimson. **Emblem concept:** a coin bearing a
city gate.

| unit | role | class | sz | hp | dmg | int | rng | spd | cost |
|---|---|---|---|---|---|---|---|---|---|
| City Watch | line | infantry | 30 | 68 | 6.3 | 1.0 | 1.9 | 3.4 | 45f |
| Pike Serjeants | anti-cavalry | infantry | 28 | 72 | 6.8 | 1.1 | 1.9 | 3.2 | 35f 20w |
| Quarrel Companies | ranged | missile | 24 | 55 | 10 | 1.8 | 6.5 | 3.2 | 30f 30w 10g |
| Hired Outriders | light cavalry | cavalry | 14 | 75 | 9.0 | 1.0 | 1.9 | 5.6 | 30f 30g |
| Gilded Sellswords ★ | elite heavy | infantry | 18 | 120 | 12 | 1.05 | 1.9 | 3.1 | 40f 60g |
| Contract Engines | siege engine | missile | 4 | 100 | 26 | 3.5 | 9.0 | 2.4 | 60w 70g |

★ = signature. Six combat units — the broadest roster, most of it
gold-priced.

- **City Watch** — halberdiers of the city companies. *Strong:* the
  best all-round levy in the game. *Weak:* best-all-round is another
  word for unremarkable.
  *Visual:* polearm over shoulder, kettle hat, tabard — "town guard" at
  a glance.
- **Pike Serjeants** — professional pike blocks. *Strong:* solid
  anti-cavalry. *Weak:* slow to reposition; loses the archery exchange
  it will be standing in.
  *Visual:* dense vertical pike-forest, tighter and neater than the
  Gravesworn hedge — discipline vs decay, same weapon.
- **Quarrel Companies** — crossbow companies under contract. *Strong:*
  hits harder per bolt than any elf bow. *Weak:* outranged by Thornwood
  everything; slow reload.
  *Visual:* horizontal crossbow held at eye line, pavise on the back —
  boxy silhouette against the elves' curves.
- **Hired Outriders** — mercenary light horse (true horses; the
  distinction from centaurs is the rider). *Strong:* the flexible
  answer the rest of the roster lacks. *Weak:* mediocre at everything
  cavalry does.
  *Visual:* standard horse-and-rider — deliberately the baseline the
  fantasy mounts diverge from.
- **Gilded Sellswords ★** — companies of veteran heavy foot, paid in
  coin. *Strong:* the best heavy infantry money buys; high morale.
  *Weak:* a fight lost with them is a treasury lost.
  *Visual:* full plate silhouette, closed helm, banner-carrying front
  rank — the "expensive" read.
- **Contract Engines** — hired engineers and their springald batteries.
  *Strong:* walls are a line item. *Weak:* fragile, slow, gold-hungry.
  *Visual:* wheeled frame with a horizontal bolt-thrower arm; crew of
  four gives it scale.

---

### SHEET 6 · EMBERDEEP — the deep-hold dwarves (fortification & siege)

Emberdeep is the slowest army in the game and the hardest to remove
from anywhere it has decided to stand — and the one civ that both
holds walls and reliably brings them down.

**Swatch:** ember orange on iron grey. **Emblem concept:** an anvil
under an arched gate.

| unit | role | class | sz | hp | dmg | int | rng | spd | cost |
|---|---|---|---|---|---|---|---|---|---|
| Hearth Levy | line | infantry | 26 | 85 | 6.7 | 1.1 | 1.9 | 2.9 | 48f |
| Shieldwall Vanguard | heavy line | infantry | 20 | 130 | 10.5 | 1.15 | 1.9 | 2.8 | 55f 25s |
| Tunnel Quarrels | ranged | missile | 22 | 60 | 11 | 2.0 | 5.5 | 2.9 | 38f 25w |
| Deepram ★ | siege ram | infantry | 6 | 200 | 8 | 1.5 | 1.5 | 2.4 | 80w 20s |
| Ember Bombard ★ | siege engine | missile | 3 | 110 | 34 | 4.5 | 11.0 | 2.0 | 60w 80s |

★ = signature (two — the siege train is the civ). No cavalry; the
lowest move speeds in the game across the board.

- **Hearth Levy** — every dwarf owns an axe and a shield. *Strong:*
  toughest levy per soldier after the giants' thralls. *Weak:* it
  fights where it already is.
  *Visual:* squat wide silhouette, round shield, braided beard — half
  the height and twice the width of an elf; the sheets should show that
  pairing.
- **Shieldwall Vanguard** — the holds' professional wall of iron.
  *Strong:* elite heavy infantry paid in stone, not gold — the economy
  the civ already runs on. *Weak:* anything it cannot reach, which at
  this speed is most things.
  *Visual:* interlocked tower shields, only helms and axe-heads showing
  over the rim — the formation IS the silhouette.
- **Tunnel Quarrels** — crossbows sighted in the dark of the delvings.
  *Strong:* hard-hitting bolts. *Weak:* short range for a shooting
  civ's bow — Emberdeep shoots to defend, not to attrit.
  *Visual:* heavy arbalest braced on a shield-spike; squat kneeling
  pose.
- **Deepram ★** — a covered ram on stone rollers, crewed by six.
  *Strong:* it reaches the gate and it opens the gate. *Weak:* nearly
  harmless against flesh; an unescorted ram is a gift.
  *Visual:* roofed shed silhouette with a swinging iron-headed beam;
  reads as architecture on the move.
- **Ember Bombard ★** — the holds' answer to a tower: a squat mortar
  of hold-iron. *Strong:* range 11 — outranges every tower and every
  bow on these six sheets. *Weak:* three crew, slow firing, slowest
  mover in the game — commit it or lose it.
  *Visual:* fat vertical-angled barrel on a stone carriage, crew with
  ram-rods; a smoke puff modelled as geometry is the animation beat.

---

## Output

Six sheets, one per civ, in a shared layout system. Deliver as
print-ready pages (PDF or one image per sheet). If you propose layout
or copy edits, keep every stat and every strength/weakness claim
exactly as written — the numbers are balance-audited and the
weaknesses are load-bearing gameplay facts, not flavour.

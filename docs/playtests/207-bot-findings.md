# #207 — civ differentiation across the six fantasy civs

Bot-observation pass, 2026-08-28, worktree `ao/my-edotmw-88/playtest-207`.

Everything here goes through the simulation's own objects — `UnitRoster`,
`CivRoster`, `SquadSim`, `Combat`, `Economy`, `MatchState` — and through
`just ai-ladder` for whole matches. `playtest_obs/obs_civs.gd` is the
harness; `logs/obs207-civs.log` and `logs/207-ai-ladder.log` are what it
and the ladder printed.

**Ticket status: LEFT OPEN.** The measurable half is discharged and three
of the six pass criteria are answered with numbers. The question the
ticket is actually *for* — do six civs FEEL different — is not a thing a
bot can answer, and neither is criterion 5.

**Seven defects filed**, none fixed here. They are listed at the end with
their issue numbers, and each says which of worker 82's in-flight PRs it
sits beside so the two are not read as one finding.

---

## Checklist, classified

| # | Ticket item | Class | Outcome |
|---|---|---|---|
| 1 | Play ~10 min as each civ, produce its roster, fight with it | production **bot-observable**, "note its character" **needs a human** | roster + fights measured; character is the owner's |
| 2 | Compare the shared archetypes side by side — is the tuning difference perceptible? | **bot-observable** (that there IS one, and how big) | measured; see SPREAD and DUELS |
| 3 | Judge the two live knobs (gravesworn cap+production, gildedreach gather) | **bot-observable** as magnitude, **needs a human** as "reads at the table" | both work; sizes below |
| 4 | Judge the four civs with no knobs; name the knob each wants | **bot-observable** as roster shape, **needs a human** for the verdict | four distinct shapes; a knob named for each |
| 5 | Every roster button matches the civ — no cross-civ leakage | **bot-observable** | **PASS**, 0 leaks, all six |
| 6 | Colours/models tell two armies apart mid-battle | **needs a human** — and the item rests on a false premise, see below | extent measured, judgement not |
| C1 | Each civ fields exactly its own roster | **bot-observable** | **PASS** |
| C2 | The six FEEL different beyond the unit list | **needs a human** | evidence supplied both ways |
| C3 | Gravesworn quantity / Gildedreach economy perceptible | **bot-observable** as magnitude | **both live**, 3.1x and 1.10x |
| C4 | The four knob-less civs read as distinct, or name the knob | **bot-observable** as shape | distinct on four axes; knobs named |
| C5 | Armies tell-apart-able in a melee, capsule vs capsule | **needs a human** | 4 of 6 civs are wholly capsule |
| C6 | "Fearless" reads as fearless at the table | **bot-observable**, and it does not | **FAIL** — filed |

---

## 5 / C1. No cross-civ leakage — PASS

`obs_civs.gd`, `OBS207 ROSTER`. Each civ's archetypes resolved through
`UnitRoster.for_civ_archetype` and compared against #207's own table
(transcribed into the harness, so the roster is not checking itself):

```
emberdeep    combat=[archers bombard heavy levy ram]                    matches_ticket=true
gildedreach  combat=[archers cavalry engine levy sellswords spearmen]   matches_ticket=true
gravesworn   combat=[engine levy shades spearmen]                       matches_ticket=true
stoneblood   combat=[breaker heavy levy skirmishers]                    matches_ticket=true
thornwood    combat=[archers cavalry greatbow levy]                     matches_ticket=true
windmarch    combat=[bowriders cavalry levy skirmishers]                matches_ticket=true
leaks=0
```

Asked the other way round too — for each of the barracks' 14 union
entries, who resolves it — and the answer is #207's table exactly. Eight
of the fourteen are fielded by exactly one civ, which is what makes a
leak visible; none occurred.

---

## 1. Before any of it: one civ cannot open, and two more never got a start

Two things came out of trying to run six civs against each other, and
both had to be separated from the civ comparison before any of it could
be read. They are in this file first because everything below depends on
them being understood as harness and data faults rather than as
identities.

### Gravesworn starts with 140 wood; its town hall costs 150 — #275

A player opens with a crew, a general and **no base**, so there is also
no drop-off, and `Economy._try_unload` credits nothing when
`_nearest_drop_off` finds none. A civ under the town centre's price
therefore cannot raise the difference by gathering.

```
civ           wood   town centre needs   can open?
emberdeep      160                 150   yes
gildedreach    200                 150   yes
gravesworn     140                 150   NO
stoneblood     180                 150   yes
thornwood      260                 150   yes
windmarch      160                 150   yes
```

Confirmed in play — every ladder match, all three:
`civ=gravesworn buildings=0 squads_peak=2 peak_wood=140`. Its opening
bank is untouched after 600 seconds.

A human can route around it (a 60-wood storehouse is also a drop-off);
no automated opponent does, because `AiPlayer._idle_builder` wants two
gatherer squads and a player opens with one.

### `--lobby=0` builds the world before it seats the AI — #276

`just ai-ladder 3 600 6 0` seats six players on `maps/ladder.tres`, whose
authored `player_slots` is 4, and the server printed:

```
server: world 42x48, preset continents, seed 1 — 4 spawn points
```

Six players, four starts, **no warning**. `_build_world()` runs at
`server.gd:372` and samples `_spawn_points` once; the `--ai=N` seating
loop runs at 421, so `D-20260817-starting-positions-follow-the-seats`
never reaches the generator on this path. Seats 4 and 5 are placed on
seats 0 and 1 by `spawn_index_in`'s modulo and never founded a base in
any match.

The map is not the constraint — asked for six, it finds six:

```
The REAL search, on real terrain, for the ladder map at 6 slots:
  seed 1: player_slots=6 -> 6 starting positions   validate_spawns: "" (silent)
  seed 2: player_slots=6 -> 6 starting positions   validate_spawns: ""
  seed 3: player_slots=6 -> 6 starting positions   validate_spawns: ""
```

**Consequence for this pass, stated plainly:** the six-way ladder run is
**not usable as a civ comparison**, and no per-civ conclusion is drawn
from it below except gravesworn's, whose cause is independent and
sufficient. A four-seat control with randomised civ assignment was run
instead. This is `docs/playtests/README.md`'s own rule — *where a result
looked like a finding and turned out to be the harness, the mistake is
recorded rather than quietly corrected*.

---

## 2. The shared archetypes: equal power, genuinely different shape

`OBS207 SPREAD`. D-072's `V = sqrt(DPS x EHP)` per SQUAD, so a cheap
numerous squad and a dear elite one are compared the way a player buys
them.

```
levy         n     hp    dmg    spd       V      RP   V/RP
emberdeep   26   85.0   6.70   2.90   591.6    48.0 12.325
gildedreach 30   68.0   6.30   3.40   620.9    45.0 13.799
gravesworn  48   40.0   4.80   3.00   665.1    32.0 20.785
stoneblood  24   95.0   8.50   3.20   682.0    50.0 13.640
thornwood   28   62.0   6.40   3.50   557.8    40.0 13.944
windmarch   28   61.0   6.50   4.40   557.5    38.0 14.672
spread: 1.22x
```

**This part is working.** A 48-man 40 HP levy and a 24-man 95 HP levy are
the same archetype tuned to opposite ends, land within 1.22x on power,
and cost 32 against 50. That is a sidegrade on paper and it is exactly
what D-047 asks a civ to do.

`cavalry` spreads 1.41x, `archers` 1.13x on power but **5.5 → 8.0 on
reach**, `heavy` 1.13x on power over a 20-man/130 HP against an
8-man/380 HP block. Every shared archetype is genuinely re-shaped rather
than re-skinned.

**One exception, and it is total: `gatherers` are bit-identical across
all six civs** — 7 men, 30 HP, 1.0 damage, 3.5 speed, carry 45, rate
0.28, 14 food, spread 1.00x. The unit a player fields more of than any
other carries no civ differentiation at all. **Filed as #269.**

---

## 2 (continued). The shared archetype is a LADDER, not a sidegrade

`OBS207 DUELS`. Each civ's levy against each other civ's levy, flat equal
ground, both ordered onto the other's own start cell, 3 seeds played both
ways round so the lower-id advantage #38 hunted cannot masquerade as a
civ difference. 15 pairings, 6 fights each:

```
emberdeep   vs gildedreach  6-0-0  survivors 0.69 / 0.00
emberdeep   vs gravesworn   6-0-0  survivors 0.34 / 0.00
emberdeep   vs stoneblood   5-1-0  survivors 0.31 / 0.10
emberdeep   vs thornwood    6-0-0  survivors 0.75 / 0.00
emberdeep   vs windmarch    6-0-0  survivors 0.73 / 0.00
gildedreach vs gravesworn   6-0-0  survivors 0.38 / 0.00
gildedreach vs stoneblood   6-0-0  survivors 0.48 / 0.00
gildedreach vs thornwood    6-0-0  survivors 0.43 / 0.00
gildedreach vs windmarch    6-0-0  survivors 0.75 / 0.00
gravesworn  vs stoneblood   3-3-0  survivors 0.09 / 0.31   <- the only even one
gravesworn  vs thornwood    6-0-0  survivors 0.54 / 0.00
gravesworn  vs windmarch    6-0-0  survivors 0.61 / 0.00
stoneblood  vs thornwood    6-0-0  survivors 0.79 / 0.00
stoneblood  vs windmarch    6-0-0  survivors 0.78 / 0.00
thornwood   vs windmarch    6-0-0  survivors 0.68 / 0.00
```

**14 of 15 pairings are 6-0 and the loser is wiped out.** The result is a
near-total order — emberdeep > gildedreach > {gravesworn ~ stoneblood} >
thornwood > windmarch — and it is stable across seed and across which
side holds the lower squad id.

Two things follow, and the second is the more useful:

- The backbone unit every civ fields is **ranked, not sidegraded**. A
  player picking windmarch takes a levy that loses to every other civ's
  levy, 0 of 6, with no survivors.
- **A 1.22x spread in D-072's V produces total annihilation.** The power
  metric does not predict outcomes under the contact-set combat model
  (`D-20260819-only-men-in-contact-fight`), where fewer tougher men in
  the same frontage win the exchange decisively. That is the same metric
  worker 82's **#220 / PR #260** is screening the roster with, seen from
  the outcome side: **#220 says `gravesworn_levy` leads on both power and
  cost-efficiency; measured, it loses 0-6 to two other civs' levies.**

**Filed as #267**, cross-referencing #220 and #219.

`cavalry` behaves the same way: `windmarch_cavalry` beats both others
6-0 with 0.60-0.70 of itself left. That is on-identity for the mobility
civ and the margin is still total.

---

## 3 / C3. Both live knobs work, and their sizes are very different

`OBS207 KNOBS`, `OBS207 QUANTITY`, `OBS207 ECONOMY`. The knobs are read
through `CivDef`'s applied functions and through the real `Economy` haul
cycle, with `sim.civs[player]` set the way `server._hand_civs_to_sim()`
sets it — the handover a previous pass skipped and nearly filed a working
feature as dead over (`docs/playtests/README.md`).

**Gravesworn — quantity. Real, and mostly not the knobs.**

```
civ          levy   n  cost  squads/1000f   men/1000f  train_s  cap
emberdeep          26    48            20         520     10.0   40
gildedreach        30    45            22         660      9.0   40
gravesworn         48    32            31        1488      7.0   44
stoneblood         24    50            20         480      9.0   40
thornwood          28    40            25         700      9.0   40
windmarch          28    38            26         728      9.0   40
```

1000 food buys gravesworn **1,488 men against stoneblood's 480 — 3.1x**,
its levy trains in 7.0 s against 9-10, and its cap is 44 against 40. The
identity is unmistakable in the numbers.

Worth saying plainly: **the knobs are the small part of it.** The cap
bonus is +10% and `production_speed` +15%; the 3.1x comes from a 48-man
squad costing 32 food, which is roster. If the two knobs were reverted to
default tomorrow, gravesworn would still be the quantity civ.

**Gildedreach — economy. Real, and smaller than it says.**

240 s of the real haul cycle, one crew, one node, a drop-off two cells
away, identical for every civ:

```
civ          rate    banked   vs median
emberdeep    0.280      450       1.00x
gildedreach  0.322      495       1.10x     <- gather_speed 1.15
(the other four)        450       1.00x
```

**A nominal 1.15x delivers 1.10x.** The difference is the walk: the
multiplier applies to gathering, and a haul cycle also spends time
travelling, which it does not touch. Not a defect — it is what
`gather_speed` means — but it is worth knowing before anyone tunes the
number, and it is the whole of gildedreach's economic identity, because
its gatherers are the same seven men everybody else's are (above).

---

## 4 / C4. The four knob-less civs — distinct in shape, and each wants a knob

`OBS207 PROFILE`, over each civ's combat defs:

```
civ           defs   meanV    maxV  meanRP    V/RP   reach   speed  siege
emberdeep        5   398.3   689.0    98.7   4.036   11.00    2.90   1.00
gildedreach      6   461.8   666.6    90.8   5.084    9.00    5.60   0.90
gravesworn       4   416.0   665.1    64.6   6.438   10.00    4.80   1.00
stoneblood       4   576.1   779.7    95.0   6.065    5.50    3.20   0.85
thornwood        4   414.8   557.8    67.5   6.146    9.50    5.80   0.15
windmarch        4   434.0   557.5    57.9   7.499    5.00    6.20   0.15
```

Read down the columns and the four knob-less civs are **not one army with
four unit lists**:

- **stoneblood** — `meanV` 576 against a 415-462 field and the shortest
  reach: quality, expressed.
- **emberdeep** — longest reach (11.0), slowest army (2.90), full siege
  (1.00): fortification and siege, expressed.
- **thornwood** — long reach (9.5) with fast legs (5.8) and **no siege at
  all** (0.15): ranged attrition, expressed.
- **windmarch** — fastest (6.2), cheapest (V/RP 7.5), shortest reach, no
  siege: mobility, expressed.

So C4's first branch is satisfied on the roster axes. **The knob each one
is asking for**, from the frame in `docs/plans/fantasy-civs.md` against
what `CivDef` can currently say:

| civ | its frame says | the knob it wants, which does not exist |
|---|---|---|
| stoneblood | "steady; strong from few well-held sites" | a **squad-cap PENALTY** (the inverse of gravesworn's bonus) and/or a territory knob on `no_build_radius`. Quality civs need fewer, better; `squad_cap_bonus` only goes up. |
| emberdeep | "slow, secure, stone-heavy" | a **building** knob — `build_speed` or a building-cost multiplier. `production_speed` covers units only, so the fortification civ cannot fortify faster. |
| thornwood | "forage-led, wood-rich, gold-poor" | a **per-RESOURCE** gather modifier. `gather_speed` is one scalar over all four resources, so "wood-rich, gold-poor" is inexpressible. |
| windmarch | "low infrastructure; settles late and lightly" | a **march or settle** knob — an army-wide `move_speed` multiplier, or cheaper/faster town centres. Unit speed alone puts the whole identity on four `.tres` numbers. |

**Filed as #270** — a schema request with the four cases, not a
balance complaint.

---

## C6. "Fearless" does NOT read — and 12 units are fearless by accident

`OBS207 FEARLESS`. Every civ's levy put under the identical beating (one
`stoneblood_heavy` squad, chosen because it beats a levy badly without
wiping it in one round — `alive <= 0` returns before the rout check,
which is the vacuity `tests/test_fearless.gd` records):

```
civ          levy                threshold   routed    at_s    left
emberdeep    emberdeep_levy           25.0      NO        -    0/26
gildedreach  gildedreach_levy         25.0     yes      8.7    0/30
gravesworn   gravesworn_levy           0.0      NO        -    0/48
stoneblood   stoneblood_levy          25.0      NO        -    0/24
thornwood    thornwood_levy           25.0     yes      7.5    0/28
windmarch    windmarch_levy           25.0     yes      7.5    0/28
```

Gravesworn does not rout — as designed. **But neither do emberdeep's or
stoneblood's levies, which carry the ordinary threshold of 25.** Against
three of five controls the identity is invisible.

`OBS207 ROUT REACH` says why, and it generalises far past levies. Morale
falls by a **flat** `morale_loss_per_casualty` (4.0 on every def but
gravesworn's) while this roster's squads run **3 to 48 men**. Casualties
needed to reach the threshold: `(100 - 25) / 4.0 = 18.75`, a constant. So
any squad of 18 men or fewer is **wiped out before it can be
frightened**:

```
12 of 27 combat defs can never rout, and are not gravesworn's:
  emberdeep_bombard, emberdeep_ram, gildedreach_cavalry, gildedreach_engine,
  gildedreach_sellswords, stoneblood_breaker, stoneblood_heavy,
  stoneblood_skirmishers, thornwood_cavalry, thornwood_greatbow,
  windmarch_bowriders, windmarch_cavalry
```

**Every cavalry def in the game is unroutable.** So is stoneblood's
entire non-levy roster. Gravesworn's four fearless defs are joined by
twelve accidental ones across five other civs, which is precisely the
identity #191 named as its distinguishing feature.

**Filed as #266.** It is NOT #218: worker 82's **PR #257** fixes
morale *recovery* under fire, and this survives it — with recovery
suppressed entirely, a 14-man cavalry squad losing all 14 men sheds 56
morale against a 75-point gap and still cannot reach the threshold.

---

## An asymmetry nobody has named: armour class is assigned by FLAVOUR

Not a ticket item; found while comparing the shared archetypes, and it
bears directly on C2.

**Three archetypes carry a different `armour_class` depending on the
civ:**

```
archetype    classes across civs
general      ['cavalry', 'infantry']    windmarch is cavalry
levy         ['cavalry', 'infantry']    windmarch is cavalry
skirmishers  ['cavalry', 'missile']     stoneblood missile, windmarch cavalry
```

Windmarch are centaurs, so "everything is cavalry" is clearly deliberate
flavour. The mechanical consequence is probably not:

- Every spearman in the game carries `bonus_vs {"cavalry": 1.5}` or
  `1.6`. **Windmarch is the only civ whose BASIC INFANTRY — and whose
  general — is hit by the anti-cavalry counter.** No other civ's levy can
  be countered at all.
- `skirmishers` means a 12-man 110 HP missile unit at reach 5.5 for
  stoneblood ("Cragthrowers") and a 24-man 48 HP melee unit at reach 1.9
  for windmarch ("Harriers"). Cavalry's `bonus_vs {"missile": 1.4}` hits
  one and not the other, under one build-menu label.

It also fits the duel data: windmarch has the lowest levy V *and* is the
only civ whose levy is counterable.

**Filed as #268.** It sits beside worker 82's **#219 / PR #261**
and is not the same claim: #261 is about the `infantry` class spanning
11.1x and one multiplier covering all of it; this is about which class an
archetype is *in*, and it survives splitting `infantry` untouched.

---

## C5 / 6. Telling two armies apart — and a false premise in the ticket

`OBS207 LOOK`. What a bot can contribute:

```
civ          civ colour  authored models                  primitive-tier archetypes
emberdeep    #ad5c29     archers gatherers militia spearmen   ram
gildedreach  #c79e33     cavalry heavy_infantry               archers engine gatherers general levy spearmen
gravesworn   #b8bd9e     <none>                               all six
stoneblood   #738094     <none>                               all six
thornwood    #386b47     <none>                               all six
windmarch    #b89961     <none>                               all six
```

**Four of six civs are wholly capsule-tier**, one is wholly authored, and
**gildedreach is MIXED** — authored cavalry and heavy infantry beside
capsule levy, spearmen, archers and engine. The mixed case is not one the
ticket anticipates and may read worse than uniform capsules; it is worth
the owner looking at it specifically.

**The premise correction:** criterion 5 says *"colours/models make two
armies distinguishable"*, and civ colour is **not** what a player sees in
a melee. D-052 gives the colour to the **player**, not the civ — two
seats of the same civ are different colours, and two seats of different
civs may be adjacent hues. The civ's entire contribution to telling
armies apart is its **models**, and the table above is all of it. The
criterion as written cannot be met or failed by anything in `civs/`.

Not filed: this is a wording fix on the ticket, not a defect.

---

## Whole matches, and why they cannot answer C2 on this tree

Two ladder runs. Both are in `logs/`; **neither supports a per-civ
conclusion**, and saying so is the useful output.

**Run A — `just ai-ladder 3 600 6 0`**, six AI, 600 s cap, seeds 1-3,
`maps/ladder.tres`. Quoted with its cap, as the recipe insists:

```
decided: 2 of 3   draws (time cap): 1
seat civ           wins  squads_peak  workers  buildings  first_attack
0    emberdeep        0         17.3     16.0        1.7  ~154 s / 50 men
1    gildedreach      0          9.3      6.0        0.7  ~137 s / 31 men
2    gravesworn       0          2.0      1.0        0.0  never
3    stoneblood       2         45.0     16.3        2.0  ~142 s / 31 men
4    thornwood        0          2.0      1.0        0.0  never
5    windmarch        0          2.0      1.0        0.0  never
```

Three of six seats never founded a base. **This is not a civ result** —
the run seated six players on a world generated with four starting
positions (#276), so it is not a six-way match at all.

**Run B — the control.** Four seats (which the map really has) with
`--random-civs=1` so civ and seat decorrelate, 420 s, seeds 11-14, driven
directly at `server.tscn` with the ladder's own command line:

```
seed 11  stoneblood(0)=2  emberdeep(1)=2  gravesworn(2)=0  stoneblood(3)=0
seed 12  stoneblood(0)=2  stoneblood(1)=2  gildedreach(2)=0 emberdeep(3)=0
seed 13  gravesworn(0)=0  thornwood(1)=2  emberdeep(2)=2   gravesworn(3)=0
seed 14  gildedreach(0)=2 gildedreach(1)=2 gravesworn(2)=0 gildedreach(3)=2
                                                    (figures are `buildings`)
```

**Seats still fail to found with the spawns adequate**, so the six-way
run's failures were never attributable to the mis-seating alone. The
refusal lines separate the two causes cleanly:

- `Cannot build there — a forest is in the way` / `a food source is in
  the way` — **#217**, and worker 80's **PR #255** fixes exactly this
  (*"a refused founding retries elsewhere"*: `_found_town` re-sent the
  same refused cell for the whole match). Not re-filed.
- `Cannot afford a Town Centre` — **every one of these belongs to a
  gravesworn seat**, and gravesworn founded in **0 of the 4 seats** it
  was dealt across the four matches. That is #275, and it is a civ
  property rather than a harness one.

**So: whole-match evidence for C2 is unavailable on `main`, and the
re-run is owed once PR #255 lands.** That is the honest state of the one
instrument #207 names for this (*"no run of it against these civs exists
yet"*) — there still is not one, and now there is a reason.

What the runs DO establish, because it survives both faults: **a match
that reaches contact reaches it at 137-157 s with 30-51 men**, and
`stoneblood` won 2 of 2 decided matches in run A. One civ winning two
matches is not an ordering and is not offered as one.

---

## What is left for the owner, and why a bot cannot do it

1. **C2 — do the six FEEL different?** The evidence is genuinely two-sided
   and a bot cannot weigh it. *For:* four measurable identity axes, a
   3.1x quantity difference, real reach/speed/siege separation. *Against:*
   a strictly ranked levy, identical gatherers, and an economy knob worth
   10%. Ten minutes each with the build menu answers this and nothing else
   does.
2. **C5 — capsule vs capsule in a melee.** Four of six civs draw every
   unit as the same capsule, distinguished only by player colour.
   `just test-client` frames a spawn, which is the one place a melee is
   not; `just gen-duel-preview` renders two squads but draws the AUTHORED
   models it is written around. Neither points at the case that matters.
3. **C3's "perceptible" half.** The magnitudes are measured (3.1x, 1.10x).
   Whether 10% more gathering reads as "the economy civ" at the table is
   a judgement.
4. **Item 1's "note its character".** Producing every def and fighting
   with it is measured; what the civ is *like* is not a number.
5. **Whether the levy ladder is a bug or the design.** #267
   reports the ordering; whether a civ's backbone unit is *allowed* to be
   strictly worse than another's, compensated elsewhere, is a design call.

---

## Defects filed by this pass

| issue | what | sits beside |
|---|---|---|
| #266 | 12 of 27 combat defs can never rout; every cavalry def is unroutable | #218 / PR #257 (different mechanism) |
| #267 | every civ's levy is strictly ranked, 14 of 15 pairings 6-0 with no survivors | #220 / PR #260, #219 / PR #261 |
| #268 | `armour_class` differs by civ for `levy`, `general`, `skirmishers`; windmarch alone is counterable | #219 / PR #261 (survives the class split) |
| #269 | all six civs' gatherers are bit-identical | — |
| #270 | the four knob-less civs each want a knob `CivDef` cannot express | M9 (#191, D-047) |
| #275 | gravesworn starts with 140 wood and its town hall costs 150 — the civ cannot open | — |
| #276 | `--lobby=0` builds the world before it seats the AI, so seats past the map's authored `player_slots` share a start | — |

**Found and NOT filed, because somebody already owns it:** every non-
gravesworn founding failure in both ladder runs is **#217**, fixed by
worker 80's **PR #255**. It was chased to its refusal lines before that
was established, which is why the ladder sections above read the way they
do.

Nothing was fixed. `main` is red at this commit (22 failures, #215 and
siblings) and none of it was re-filed.

## The tree these were taken on

Base commit **`b08043d`** (`ao/my-edotmw-84/playtest-bot-findings`, which
is `cc2f4c6` plus that pass's documents) — chosen so this file joins its
siblings rather than duplicating the harness directory. **No engine file
is touched by this pass.** Native runtime throughout
(`EDOTMW_RUNTIME=native`); the docker `test` service OOM-killed a cold
import twice on this host, which is the same condition #223 records.

**Explicitly NOT measured on `ao/my-edotmw-88/renewable-food` (PR #246,
this session's other branch).** That change adds a renewable food economy
and would move every economic number here; the ticket is about the roster
as it ships, so the roster as it ships is what was measured. When #246
lands, the gildedreach economy figure is the one to re-take.

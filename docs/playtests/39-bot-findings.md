# #39 — siege: razing rules, defensive fire, health UI, tower upgrades

Bot-observation pass, 2026-08-27, worktree `ao/my-edotmw-84/root`.
Staged through `SquadSim` + `BuildingSim` + `Combat` with shipped defs,
using the same approach geometry as `tests/test_buildings.gd::_rush_cost`.

**Ticket status: LEFT OPEN.** The damage arithmetic and the health-wire
path are discharged; the tower-upgrade step cannot be performed as
written, and every "is it FELT" criterion needs the owner.

---

## Checklist, classified

| # | Ticket item | Class | Outcome |
|---|---|---|---|
| 1 | ONE line squad vs a defended town centre | guarded by `tests/test_buildings.gd` | **PASS** (that guard is green) |
| 2 | TWO squads vs a fresh one | guarded — **and the guard is RED**, see #215 | **FAILS for 12 of 22 troops** |
| 3 | Repeat 1–2 against a tower | guarded — **and the guard is RED** | **FAILS for 15 of 22 troops** |
| 4 | Stand in tower range; return fire costs real casualties | bot-observable | **PASS on damage — but it never breaks morale, #218** |
| 5 | Watch the building health bar throughout | bot-observable (wire) / human (bar) | wire **PASS** |
| 6 | Upgrade a tower; cost, visual change, improved behaviour | bot-observable | **CANNOT BE DONE — no tower upgrade exists** |
| 7 | Raze all of an AI's buildings and squads; elimination triggers | bot-observable | **PASS** (see #42's findings) |
| P1 | One squad loses, two raze it | bot-observable | **FAILS both ways** — broken outright for most troops (#215), and reversed by a garrison even for the troops it works for (#227) |
| P2 | Second squad finds a fighting position in reach | bot-observable | **PASS** |
| P3 | Defensive fire is FELT | mixed | damage yes; morale no (**#218**) |
| P4 | Health UI tracks damage live, yours and visible enemies' | wire yes / **HUD needs a human** | wire **PASS** |
| P5 | Tower upgrade works end to end | **needs a human**, and see step 6 | blocked |
| P6 | Destruction contributes to a decided match | bot-observable | **PASS** |

### Correction: the suite is NOT green, and steps 1–3 do not pass

An earlier draft of this file said steps 1–3 were "already guarded and
the suite is green", and did not re-run them. That was wrong. `just
test-unit` at `cc2f4c6` is **red**, and two of the failures are exactly
D-067's guards:

```
test_two_squads_of_any_line_troop_can_take_a_town_centre
    two squads of thornwood_levy could not take a town centre (36 HP left)
    two squads of gildedreach_archers ... (1252 HP left)
    ... 12 archetypes in total
test_two_squads_of_any_line_troop_but_light_skirmishers_can_take_a_tower
    two squads of gildedreach_spearmen could not take a tower (17 HP left)
    two squads of emberdeep_levy ... (46 HP left)
    ... 15 archetypes in total
```

**Already filed, by another worker, at this same commit: #215** (with
#212, #211, #203, #202 and the older #152 covering the same ground) —
every one of them `#191` roster fallout. Not re-filed here.

So **#39's pass criterion 1 fails on two independent counts**: the rule
is broken outright for most of the roster (#215), and for the troops it
still works for it is reversed by a single screening squad (#227, below).

`test_no_single_starting_squad_can_raze_a_defended_building` — the *one
squad cannot* half — is green.

Full run: `docs/playtests/logs/test-unit-full.log`.

This pass covered what those tests do not.

---

## 4. Defensive fire — D-066's joke is thoroughly dead

`playtest_obs/obs_siege.gd`, log `docs/playtests/logs/obs39-siege.log`. A squad
parked in reach, not trading, shipped defs:

```
town_centre vs emberdeep_levy        : 26 -> 16 at 30s -> 5 at 60s   (81% lost)
town_centre vs gildedreach_levy      : 30 -> 17 at 30s -> 4 at 60s   (87% lost)
town_centre vs stoneblood_heavy      :  8 ->  6 at 30s -> 4 at 60s   (50% lost)
town_centre vs windmarch_skirmishers : 24 -> wiped before 30s        (100% lost)
tower       vs every one of the four : wiped inside 60s              (100% lost)
```

D-066 recorded a town centre costing a squad **4 men out of 36 over a
whole engagement**. It now kills 81–100%. That half of P3 passes
decisively.

**What does not pass:** none of those squads ever routed. See **#218** —
morale recovery (2.0/s, unconditional) outruns a building's morale
pressure (1.4–1.9/s for a town centre), so a squad is annihilated at
morale ~94 against a rout threshold of 25.

## 5. Health on the wire — PASS

Read through `BuildingSim.info_entries()` and `take_dirty()` — the path
the wire and the HUD panel use — **not** `health_of()`, which would pass
even with D-061's dirty-flag bug present:

```
health_fraction over one siege: 1.0, 0.99, 0.97, 0.95, ... 0.05, 0.04, 0.03, 0.01
33 ticks marked dirty over 60.4s; destroyed=true
```

64 distinct steps. The regression where `health_fraction` was pinned at
1.0 is not present. **The bar itself still needs the owner's eyes** —
this proves the number moves and reaches the encoder, not that it is
drawn.

## P2. The second squad is in reach — PASS

The unsorted-`disk_offsets` regression parked the second besieger outside
its own reach, so two squads dealt barely more than one. Damage dealt in a
fixed window:

```
emberdeep_levy        1 squad 852,  2 squads 2140  (x2.51)  both engaged
stoneblood_heavy      1 squad 1308, 2 squads 2955  (x2.26)  both engaged
gildedreach_spearmen  1 squad 847,  2 squads 2310  (x2.73)  both engaged
```

Superlinear, because two squads also survive the building's fire longer.
Not present.

## 6. There is no tower upgrade — the step cannot be performed

Every `upgrade_from` in the shipped building set:

```
wall_tower  upgrades from [wall, gate, garrison_wall, garrison_gate]
            cost w60 s130 | hp 1000 | damage 0.0 | range 0.0
```

and the tower-like buildings:

```
tower       hp 1700  dmg 56.7  rng 15.6   upgrade_from = []
town_centre hp 3000  dmg 42.0  rng 12.1   upgrade_from = []
wall_tower  hp 1000  dmg  0.0  rng  0.0   upgrade_from = [wall, gate, ...]
```

So: **nothing upgrades from a `tower`**, and the one thing that *is* an
upgrade produces a building that does not shoot. #39 step 6 asks to
"upgrade a tower ... and confirm improved behaviour"; what the game
actually offers is upgrading a **wall or gate into a wall tower**, which
is a wall-network feature (D-076), not a defensive-fire one.

This is a **ticket/documentation mismatch rather than a defect** —
`docs/status/playtests-2026-08.md` lists "tower upgrades" among the landed
work and #35's row B7 says "partial — `upgrade_from` exists, towers only",
both of which are true of the *wall* tower. Not filed as a bug; the step
needs rewriting to "upgrade a wall segment into a wall tower", and then a
human can perform it.

## 7 / P6. Elimination and decided matches — PASS

Covered in `docs/playtests/42-bot-findings.md`: all four combinations of
(squads, buildings) drive `MatchState.update()` correctly, and razing was
observed to decide real AI matches (`MATCH_ELIMINATED` / `MATCH_OVER` in
`docs/playtests/logs/ai-ladder.log`).

---

## The finding this pass turned up: a screen reverses D-067 (#227)

`playtest_obs/obs_siege_diag.gd`, log `docs/playtests/logs/obs39-siege-diag.log`.
Add **one squad of the cheapest levy** in front of the town centre:

```
attacker           n  defender     razed  building hp    attackers left  closest
stoneblood_heavy   2  none         true   0/3000  60.4s   12/16          1 cell
stoneblood_heavy   2  1 in front   FALSE  3000/3000  -      0/16          3 cells
emberdeep_levy     2  none         true   0/3000  98.5s   18/52          1 cell
emberdeep_levy     2  1 in front   FALSE  3000/3000  -      0/52          3 cells
```

Two squads of the roster's strongest infantry are wiped **without
scratching the building**. Control — the same defender placed *behind* the
building, off the approach — restores the original outcome exactly, with
the defenders untouched:

```
stoneblood_heavy   2  1 BEHIND     true   0/3000  60.4s   12/16   defenders 30 left
```

So it is interception, not extra strength: the attack-move halts at the
screen ~3 cells out and the town centre shoots for free. Filed as
**#227**, explicitly flagged as possibly-intended and needing a design
call — what is certainly true is that `_rush_cost` places no defenders, so
**nothing measures the rule under the conditions a real base presents**.

---

## What still needs the owner

1. **The health BAR and panel** — this pass proved the number moves and
   reaches the encoder, not that it is drawn, for your buildings and for
   visible enemy ones.
2. **P3's "FELT"** — attacking into a tower now costs 100% of a levy
   squad. Whether that reads as a real price at the camera is a feel.
3. **Step 6, rewritten** — upgrade a wall/gate into a wall tower and
   confirm the cost, the visual change and the wall-network behaviour.
4. **Whether #227 is intended.** If a garrisoned base is *meant* to stop
   two line squads, the siege train is presumably the answer and D-067's
   text should say so.

---

## Artifacts

| file | what |
|---|---|
| `docs/playtests/logs/obs39-siege.log` | defensive fire, health wire, second squad, upgrades, elimination |
| `docs/playtests/logs/obs39-siege-diag.log` | the screening-squad finding and its control |
| `playtest_obs/obs_siege.gd`, `obs_siege_diag.gd` | the harnesses |

## Filed from this ticket

- **#218** — building fire never routs a squad (shared with #38)
- **#227** — D-067's two-squads rule is only measured against an ungarrisoned base

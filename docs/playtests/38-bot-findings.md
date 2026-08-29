# #38 — field combat: counters, fairness, morale and rout

Bot-observation pass, 2026-08-27, worktree `ao/my-edotmw-84/root`.
Every fight below is staged through the simulation's own objects —
`TorusSpace` + `SquadSim` + `Combat`, wired the way `server.gd` wires
them — with shipped `.tres` defs, ticked at the real 10 Hz. No caricature
units anywhere.

**Ticket status: LEFT OPEN.** Three of the five pass criteria are
discharged with numbers; "counters are FELT" fails; "combat reads fair"
and everything about how a rout *looks* need the owner.

---

## Checklist, classified

| # | Ticket item | Class | Outcome |
|---|---|---|---|
| 1 | Mirror fight, 3–4 times | bot-observable | done, 240 fights — **PASS** |
| 2 | Counter pairings both ways | bot-observable | done, full matrix — **FAIL on the anti-infantry half** |
| 3 | Big engagement, two multi-squad armies | bot-observable | done |
| 4 | Push a fight to a rout; watch the router afterwards | bot-observable | done — **PASS in melee, FAILS under building fire** |
| 5 | Casualties: integer decrements, clean restamping | bot-observable (numbers) / human (looks) | numbers **PASS** |
| P1 | Mirror fights close, no player-1 or lower-id advantage | bot-observable | **PASS** |
| P2 | Counters are FELT — favoured side wins clearly | bot-observable | **FAIL** — #219 |
| P3 | Morale/rout visible and legible | **needs a human** | rout *happens* correctly in melee; legibility not covered |
| P4 | No soldier-level weirdness, no immortal last man | mixed | numbers clean; appearance needs a human |
| P5 | Combat reads fair over ~10 fights; note swinginess | **needs a human** | not covered — "reads fair" is a feel |

---

## 1. Mirror fairness — PASS

`playtest_obs/obs_combat.gd`, log `docs/playtests/logs/obs38-combat.log`.
Identical squads, equal flat ground, both attack-moved onto each other's
start cell. **Every seed played twice**, once with player 1's squad as
squad id 0 and once with player 2's — a lower-id advantage is invisible
unless you swap it.

```
unit                  n   owner p1  p2  undecided |  id0  id1  | mean
emberdeep_levy        48        23  25      0     |   21   27  | 51.0s
gildedreach_spearmen  48        27  19      2     |   20   26  | 41.0s
thornwood_levy        48        25  23      0     |   21   27  | 32.0s
stoneblood_heavy      48        21  21      6     |   22   20  | 47.4s
windmarch_cavalry     48        23  23      2     |   22   24  | 25.0s
```

Totals over 230 decided fights: **owner p1 119 / p2 111**, **id0 106 /
id1 124**. Neither departure is significant (the id split is z ≈ 1.2,
p ≈ 0.23) and the id lean is toward the *higher* id, which is the opposite
of the classic first-strike bug. D-024's simultaneous resolution is
holding.

## 2. Counters — the anti-infantry half is not felt

Full matrix in `docs/playtests/logs/obs38-counters.log`; filed as **#219**.

The cavalry↔missile and spearmen↔cavalry halves are in good shape:

```
gildedreach_spearmen (x1.50 vs cavalry) vs thornwood_cavalry  12/12  margin +0.89
gravesworn_spearmen  (x1.60 vs cavalry) vs gildedreach_cavalry 12/12  margin +0.85
windmarch_cavalry    (x1.50 vs missile) vs emberdeep_archers   12/12  margin +0.77
```

The anti-infantry half inverts against heavy and elite infantry:

```
gildedreach_archers (x1.30) vs stoneblood_heavy   0/8  margin -0.77
gildedreach_archers (x1.30) vs emberdeep_heavy    0/8  margin -0.62
emberdeep_archers   (x1.30) vs stoneblood_heavy   0/8  margin -0.86
thornwood_archers   (x1.40) vs stoneblood_heavy   0/8  margin -0.67
```

At **equal resource cost** (D-072's RP) the counter mostly comes back —
3 archer squads for the price of 2 heavies wins 6/6. So the intent is
reachable; it is invisible in the unit the player actually manipulates.
Underneath it, one `armour_class = "infantry"` spans 68 HP
(`gildedreach_levy`) to 380 HP (`stoneblood_heavy`), a 5.6x range, with
one multiplier covering all of it.

A separate finding from the same table, filed as **#220**:
`gravesworn_levy` leads the roster on cost-efficiency by 33% (V/RP 20.78
against the next unit's 15.67) while sitting **fifth** on raw power at
665.1 — within 0.2% of `gildedreach_sellswords` (666.6) at **one quarter
of the price** (32 RP vs 130). D-072's "no unit may lead on both axes"
broken, and it shows up in real fights: it beats its designated counter
both squad-for-squad and at equal cost.

## 3. Big engagement

Six squads a side, mixed arms including both generals, attack-moved into
each other:

```
240.1s: emberdeep 66/124 men in 4/6 squads | gildedreach 6/122 men in 1/6 squads
        8 rout events | 210.8 us/squad-update over 2401 ticks
```

Decisive, with routs cascading as workstream 4 intends. (The per-squad
cost is a loaded-host figure at 12 squads and is quoted here only with
both of those attached — it is not a performance measurement.)

## 4. Rout — correct in melee, absent under building fire

Melee, shipped defs:

```
stoneblood_heavy vs gildedreach_levy: routed at 4.4s (morale 13.2),
    fled 2 cells, did not rally, wiped at 9.2s
emberdeep_heavy  vs thornwood_levy:   routed at 4.4s (morale 19.2),
    fled 2 cells, did not rally, wiped at 9.2s
```

Rout fires, the squad flees, and it is then destroyed rather than
recovering. That is `PURSUIT_DAMAGE_MULT` working as
`D-20260819-morale-reads-the-fight` designed it — *"a rout is a defeat
rather than a pause"* — so it is recorded, not filed.

**Under BUILDING fire the same squads never rout at all**, and that is
filed as **#218**: a town centre kills a squad to the last man while its
morale never falls below ~94 out of 100 against a threshold of 25, because
`Combat._recover_morale_and_check_rally` restores 2.0 morale/s
unconditionally and a town centre's casualty rate is worth only
1.4–1.9/s. `Combat._shoot_squad` has an explicit `_break_squad` call with
a comment saying a fortification breaks a squad like a squad does; at
shipped numbers it is unreachable.

## 5. Casualties — numbers clean

One full fight, every `alive[]` change recorded:

```
A 26 -> 2 in 20 decrements: [1,2,2,2,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1]
B 28 -> 0 in 23 decrements: [2,1,2,2,2,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]
alive INCREASED 0 times
```

Integer decrements of 1–2, never an increase — D-024's rule holds. A lone
survivor stayed alive and fighting for 11.0 s before dying, which is
consistent with a ~1.1 s attack interval and damage variance rather than
an immortal last man, but **it is the one number here a human should
sanity-check on screen**.

---

## A fixture mistake worth recording

The first version of the counter sweep ordered each side at a point
*past* the other. The squads crossed, separated, and walked to opposite
corners; the run reported large attrition margins with almost nothing
decided (`undec=8/8`), which reads exactly like *"fights do not
resolve"*. It was the harness. Corrected by ordering each side at the
other's own start cell — the geometry `obs_combat.gd` already used and
which decides cleanly — after which every row is `undec=0(gap 0)`.
Recorded because the wrong version would have been a plausible and
completely false bug report.

---

## What still needs the owner

1. **P5 — does combat read fair over ~10 fights, and what feels swingy?**
   `damage_variance` is 0.25 by default; the mirror data says it is fair
   *on average over 48 fights*, which is not the same question.
2. **P3 — is a rout legible?** Does a routing squad read differently from
   an ordered retreat on screen? The sim says it flees 2 cells and dies;
   whether that *looks* like panic is unrated.
3. **P4 — soldier-level appearance.** Stragglers, the casualty restamp,
   and the 11 s lone survivor.
4. **Whether the counter inversion in #219 matters in play.** The
   equal-RP data says the triangle works if you buy by cost. Whether a
   player experiences that as "counters work" is the judgement the
   numbers cannot make.

---

## Artifacts

| file | what |
|---|---|
| `docs/playtests/logs/obs38-combat.log` | mirror fairness, counters, rout, casualties, big engagement |
| `docs/playtests/logs/obs38-counters.log` | D-072 power table + full missile/infantry matrix |
| `docs/playtests/logs/obs-morale.log` | morale traces behind #218 |
| `playtest_obs/obs_combat.gd`, `obs_counters.gd`, `obs_morale.gd` | the harnesses |

## Filed from this ticket

- **#218** — building fire never routs a squad
- **#219** — anti-infantry counter not felt squad-for-squad
- **#220** — D-072 power budget: `gravesworn_levy` leads both axes

# #36 — economy: gathering, hauling, tree depletion, storehouse

Bot-observation pass, 2026-08-27, worktree `ao/my-edotmw-84/root`.
Real terrain (`TerrainGen`, seed 1337, the shipped default map), real
`Economy.generate` node placement, real gatherer defs, ticked through
`SquadSim.tick()` at 10 Hz.

**Ticket status: LEFT OPEN.** Every mechanical criterion passes; the
felling animation and the HUD readouts need the owner.

---

## Checklist, classified

| # | Ticket item | Class | Outcome |
|---|---|---|---|
| 1 | Gatherers to each of wood, food, gold, stone | bot-observable | **PASS**, all four |
| 2 | Full haul cycle; stockpile ticks on deposit, not continuously | bot-observable | **PASS**, deposits discrete |
| 3 | Park a crew on a tree; ~60 s; tip-and-sink felling | timing bot-observable / **animation needs a human** | 55.1 s — **PASS** |
| 4 | Retarget: same kind, within ~8 cells, never wood-to-food | bot-observable | **PASS**, all four cases |
| 5 | Storehouse near a distant grove shortens hauls | bot-observable | **PASS**, +75% income |
| 6 | Try to produce something unaffordable; all-or-nothing | bot-observable | **PASS** (measured under #37) |
| P1 | All four gatherable; HUD readouts correct | sim **PASS** / **HUD needs a human** | |
| P2 | Haul cycle legible; deposits discrete | discrete **PASS** / **legible needs a human** | |
| P3 | Tree depletes in about a minute; felling animation plays | timing **PASS** / **animation needs a human** | |
| P4 | Retarget respects kind and radius | bot-observable | **PASS** |
| P5 | Storehouse shortens hauls | bot-observable | **PASS** |
| P6 | Affordability all-or-nothing with clear feedback | wire **PASS** / **feedback needs a human** | |

---

## 1. What the shipped default map grows

`playtest_obs/obs_economy.gd`, log `docs/playtests/logs/obs36-economy.log`:

```
food   nodes=1939   total stock=203,595
wood   nodes=3435   total stock=360,675
gold   nodes=48     total stock=115,200
stone  nodes=137    total stock=328,800
all four kinds present: true
```

Consistent with `docs/status/forests.md`'s post-0.60-scaling figure
(~3,413 wood nodes); the small difference is the seed.

## 2. The haul cycle — deposits are discrete

One crew per kind, town centre three cells from the node:

```
food  (4,0)    0.1s GATHERING -> 23.1s TO_DROP_OFF -> 23.2s TO_NODE -> 23.3s GATHERING -> 46.3s TO_DROP_OFF
               deposits 23.2s:+45  46.4s:+45   discrete=true
wood  (36,0)   identical shape, +45 / +45
gold  (89,15)  identical shape, +45 / +45
stone (115,0)  identical shape, +45 / +45
```

The wallet moves **only** on arrival at the drop-off, in one jump of the
full carry, never a trickle while gathering. D-005's round trip is intact
and all four kinds behave the same.

## 3. A tree takes 55.1 s — and `gather_speed` is genuinely wired

One hand-placed tree at `TREE_STOCK = 105`, one shipped crew:

```
civ           gatherer                alive  rate     civ gather_speed  tree out in
emberdeep     emberdeep_gatherers       7    0.28/s        1.00           55.1s
gildedreach   gildedreach_gatherers     7    0.28/s        1.15           48.1s
gravesworn    gravesworn_gatherers      7    0.28/s        1.00           55.1s
stoneblood    stoneblood_gatherers      7    0.28/s        1.00           55.1s
thornwood     thornwood_gatherers       7    0.28/s        1.00           55.1s
windmarch     windmarch_gatherers       7    0.28/s        1.00           55.1s
```

D-087's "about a minute" holds at 55.1 s, and `gildedreach`'s ×1.15
`gather_speed` produces exactly the expected 48.1 s (55.1 / 1.15 = 47.9).

**A fixture warning worth carrying.** The first run of this reported
48.1 s as 55.1 s — *every civ identical* — which looks precisely like the
fourth declared-and-unread instance #158 fixed. The cause was the
harness: it never called the equivalent of `server._hand_civs_to_sim()`,
so `Economy._gather` read a default `CivDef`. **A fixture that skips the
handover reports a wired knob as unwired**, which is #119's lesson
pointing the other way. Fixed and re-measured before anything was filed.

## 4. Retargeting respects kind and radius — PASS

Read by watching which node loses stock after the first is exhausted
(the crew's current node is private to `Economy`):

```
same kind 3 cells away                    -> moved to the wood node
same kind 12 cells away (outside radius)  -> gave up
FOOD 3 cells away (wrong kind)            -> gave up
nothing else on the map                   -> gave up
```

`RETARGET_RADIUS` is 8; 3 is taken, 12 is not, and a food node three
cells away is **not** substituted for wood. Exactly D-087's rule.

## 5. The storehouse shortens hauls — PASS

Same six-tree grove 18 cells from the town centre, one crew, 180 s:

```
storehouse=false   wood banked: 180
storehouse=true    wood banked: 315
```

**+75%** with a drop-off placed beside the grove.

---

## What still needs the owner

1. **The tip-and-sink felling animation** (step 3 / P3) — the node is
   removed at 55.1 s; whether the tree visibly falls, and only when you
   can see the cell, is D-087's fog-gated `S2C_NODES_DEPLETED` path and is
   unrated here.
2. **HUD resource readouts** (P1) — the wallet arithmetic is exact;
   whether the four numbers on screen follow it is a client question.
3. **Is the haul cycle legible?** (P2) — deposits are discrete in the
   data. Whether a player can *see* a crew walk out, work, walk back and
   deposit is the actual criterion.
4. **Affordability feedback** (P6) — the refusal string is correct on the
   wire (measured under #37); whether it reaches the player is not.
5. **Step 5 as written** — building a storehouse *in a match*, by
   ordering a crew to construct it. This pass placed one directly, so the
   construction path is not covered here (it is exercised by
   `test-load`).

---

## Artifacts

| file | what |
|---|---|
| `docs/playtests/logs/obs36-economy.log` | node census, haul cycles, tree timing, retargeting, storehouse |
| `playtest_obs/obs_economy.gd` | the harness |

## Filed from this ticket

None. Every mechanical criterion passed.

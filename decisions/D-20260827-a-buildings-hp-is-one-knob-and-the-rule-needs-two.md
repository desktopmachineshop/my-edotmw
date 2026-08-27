### D-20260827 · 2026-08-27 · Accepted — a building's HP is one knob, and D-067's rule needs two

**Decision:** D-067's anti-rush rule stands as a design statement and its
NUMBERS are re-derived against the fantasy roster (#191). Three changes,
and only the first is a number:

1. **Tower `max_health` 1700 → 1250; town centre `max_health` 3000 →
   2400.** Both building `damage` values are UNCHANGED.
2. **The PAIR rule is asked of LINE troops** (`LINE_TROOPS` in
   `tests/test_buildings.gd`: every shipped def whose `archetype` is
   `levy`, `spearmen`, `heavy` or `sellswords` — asserted against the
   roster, not hand-maintained). The SOLO rule is unchanged and still
   covers every starting troop, both gatherers and two generals.
3. **`TOWER_EXCEPTIONS` is deleted.** The carve-out is a CLASS now, not a
   list of ids, and the guard that keeps it honest is generalised from
   one unit to all ten excluded ones.

This supersedes D-067's tower/town-centre numbers and its one named
exception. D-067's *rule* — one squad of any starting troop cannot raze a
defended building, two line squads can — is untouched, and so is
everything else in that entry (the `disk_offsets` ordering, the reasoning
about why HP alone cannot express the rule).

**How this was found.** `tests/test_buildings.gd::test_two_squads_of_any_
line_troop_but_light_skirmishers_can_take_a_tower` was reported RED on
`main` (#152) with one unit failing by 86 HP, and the report guessed at
#146 (footprint separation) or #142 (wheeling) having moved where a
besieger stands. Re-verified on `cc2f4c6`, 111 commits later, the file
has **three** failing tests, not one: 15 of 21 troops fail the tower rule
and 8 fail the town-centre rule. (The third is `test_the_opening_general_
outfights_basic_infantry`, which asks the roster for a `militia` —
unrelated, filed as #202.)

**The measurement, and why it settles which side is wrong.** Both halves
of D-067's rule are statements about a building's HP, so the useful
quantity is not "did it fall" but **how much damage a squad DELIVERS
before it is destroyed**. Measured against an effectively infinite HP
pool, HP becomes a free parameter afterwards:

    solo fails  <=>  HP >  max(solo delivered)
    pair razes  <=>  HP <= pair delivered

At the shipped tower damage of 56.7, over all 22 troops:

| | delivered |
|---|---|
| strongest SOLO (stoneblood_heavy) | **860** |
| weakest PAIR (windmarch_bowriders) | **479** |
| weakest LINE-troop pair (thornwood_levy) | **1,470** |

**The weakest pair delivers less than the strongest solo**, so no tower
HP whatever satisfies "every pair razes, no solo razes" over the whole
roster. And sweeping the tower's damage does not help: coverage was
measured **INVARIANT at 15 of 22 across 56.7 / 45 / 34 / 24** — a 2.4x
range — and at 42 / 32 / 24 / 16 on the town centre. The reason is that
`damage` and `max_health` are **one knob, not two**: lowering a
building's damage lets attackers live longer and deliver proportionally
more, on both sides of the comparison. Solo and pair delivery rescaled
together to within the ordering at every setting.

That is exactly D-067's own revisit trigger, fired: *"if a later unit
lands outside the measured band — tankier than legion_heavy or flimsier
than skirmishers — the single flat `BuildingDef.damage` stops expressing
this rule."* Both ends fired at once. `stoneblood_heavy` is 8 men at 380
HP (3,040 effective squad HP) where legion_heavy was 3,360 across a
36-man squad that died piecemeal; `windmarch_bowriders` and
`gravesworn_shades` are flimsier than northmen_skirmishers ever were.

**So the rule needs a second dimension, and the roster already had one:
the troop's ROLE.** D-067 states its two halves in deliberately different
words — "any starting TROOP" for the solo half, "any LINE troop" for the
pair half. Under the old eight-unit roster the difference barely bit,
because six of the eight were line infantry, so ONE list served both
tests. #191 replaced the roster with 22 troops and carried that single
list across whole — and **ten of the 22 are cavalry, missile troops or
light infiltrators**. The pair rule was asking a squad of horse archers
to crack a fortification.

**This is a category correction, not a relaxed assertion**, and the
distinction matters because #152 explicitly forbids the latter. Three
things separate them:

- the excluded set is exactly the set of NON-LINE archetypes, derived
  from `UnitDef.archetype`, and a new test fails if `LINE_TROOPS` drifts
  from what the roster ships — so a `windmarch_spearmen` added tomorrow
  is covered automatically, which is precisely the failure that produced
  this bug;
- every excluded troop must still take **at least a quarter** of a tower
  with two squads, so the carve-out cannot quietly become "harmless" —
  the guard D-067 wrote for its one exception, generalised to all ten;
- the SOLO rule still covers everything. The half that prevents a
  two-minute win is not narrowed by one unit.

**The numbers, and the margins they were chosen for.** With role
separating the two populations, HP has a real window again:

| | solo ceiling | weakest line pair | chosen HP | margins |
|---|---|---|---|---|
| tower | 860 | 1,470 | **1,250** | +45% / −15% |
| town centre | 1,679 | 2,964 | **2,400** | +43% / −19% |

Both shipped values sat OUTSIDE their window (1700 and 3000 are above the
weakest line pair), which is the whole of the observed failure. Chosen
near the geometric middle so that neither half of the rule is a knife
edge; the old 1700 left `gildedreach_spearmen` failing by **17 HP**, a
margin no data change could be made against safely.

**Rejected alternatives:**
- *Adjusting where a besieging squad stands* — #152's first hypothesis
  (option 1: #146/#142 moved the attacker out of reach), rejected on the
  measurement. `test_two_melee_squads_besiege_a_building_about_twice_as_
  fast_as_one` passes, and the successful pairs finish in 37–103 s with
  roughly half their men alive. Nothing is standing out of reach; the
  losing squads are fighting and losing.
- *Lowering the buildings' `damage` instead of their HP* (rejected on the
  measurement above — it moves both halves together and changed coverage
  by zero units across a 2.4x sweep).
- *Raising `damage_vs_buildings` on the eleven line troops instead*
  (rejected — same effect on defence in aggregate, spread over eleven
  files and eleven arbitrary numbers instead of two measured ones. It
  remains the lever if the owner would rather buildings kept their HP.)
- *Growing `TOWER_EXCEPTIONS` to 15 names and leaving the numbers alone*
  (rejected — that IS the relaxed assertion #152 forbids. It would have
  excluded five genuine line troops, three of them failing by under 150
  HP.)
- *Changing the mechanism — siege damage types, building armour classes*
  (rejected HERE as out of scope for a bug fix, and it is the honest
  long-term answer. See the revisit trigger.)

**Consequences, stated plainly because one of them is a design cost.**
**Defended buildings are 26% (tower) and 20% (town centre) weaker than
they were**, and D-056 wants matches LONGER rather than shorter. Two
things bound that: the solo rule is refused with a 45% margin rather than
the old knife edge, so the two-minute rush stays impossible; and the
fantasy roster fields 20–30 man squads where legion/northmen fielded 36,
so a building facing one squad faces fewer men than the old numbers were
set against. Whether the net effect on pacing is visible is a PLAYTEST
question and is not claimed here.

`just ai-ladder` results taken before this are measured against different
building numbers — the standing "quote it with its cap, its squad count
and its roster" rule gains a fourth clause.

**Measured:** `just test-unit buildings` — 68 of 69 passing, the one
failure being #202, which is unrelated and pre-existing. All three new or
changed guards were **observed to fail before being trusted** (D-022):
restoring the tower to 1700 reds the pair rule for five line troops
(gravesworn_spearmen 149 HP left, thornwood_levy 230, windmarch_levy 147,
gildedreach_spearmen 17, emberdeep_levy 46); dropping `emberdeep_heavy`
from `LINE_TROOPS` reds the roster-drift test; and setting
`windmarch_bowriders.damage_vs_buildings` to 0.002 reds the
still-hurts-a-tower guard at 1,244 of 1,250 HP left. The sweep and the
whole 22-troop table were taken with a temporary harness that is
deliberately not committed — its numbers are above, and re-taking them is
a fifteen-line copy of `_rush_cost`.

**Through the wire** (`just test-load 4 120`, docker, 2026-08-27):
`VERDICT ok`, **0 desyncs over 476 state-hash checks**, 0 dropped ticks,
all three `gate-check.sh` comparisons green (`casualties_applied=41
conceal_events=27 reveal_events=20 raid_orders=45`), and **180.99
µs/squad at 32 squads** — quoted with its count, and not comparable to
the 167.7 at 48 or 159.88 at 49 recorded elsewhere without the standing
caveat that per-tick fixed overhead inflates the figure when squads are
few. Two `max_health` values cannot move a per-squad cost; the run is
here to show the change is not felt through the wire, which it is not.
The same run reported `worst_tick=493.8ms` against D-020's 100 ms with
zero dropped ticks — **not quoted as a result**, because the host was
carrying ~3 GB of swap and had been OOM-killing docker all evening
(#153), which is the condition M6 discarded a session's worst-tick
figures over.

**A note on the runtime**, because it affects how much to trust the unit
numbers: **docker `_import` was OOM-killed (exit 137) three times** with
the machine at 400–2,000 MB free (#153) before it finally admitted the
load test, so every unit-test and sweep number above is from
`EDOTMW_RUNTIME=native`. Combat is pure GDScript over a seeded RNG
(D-024) and reads no imported asset, so the runtime cannot change these
results; the failures reproduced identically across four separate native
runs, and the original 86 HP figure in #152 was reproduced by two other
sessions under docker.

**Revisit trigger:** the next unit that lands outside the measured band
moves the window again, and the window is now only 1.7x wide on the tower
(860 to 1,470). When it closes — a line troop weaker than thornwood_levy,
or a solo attacker tankier than stoneblood_heavy — HP has run out as a
lever for the second time and the answer is the mechanism D-067 already
named: siege equipment or a damage type, not another number. The siege
train (breaker, engine, ram, bombard) already exists and is already
scoped out of both halves of this rule, so the parts for that are on the
shelf.

---

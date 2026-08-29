### D-20260828-the-phase-table-has-numbers · 2026-08-28 · Accepted — D-068's phase table, with a measured rate under it

**Decision:** D-068's six-phase account of a 90-minute match gains the
thing it was always missing — **an income rate, a crew count and a bank
per phase** — measured from the shipped economy rather than asserted.
`tests/test_pacing.gd` is the measurement and re-takes it on every run.

Issue #281, from the gap assessment's §1.6 (C5). D-068 named itself "the
derivation base for D-069's epoch timings and D-072's costs" and carried
six minute-ranges and **no rate at all**; `decisions/OPEN-QUESTIONS.md`
has recorded that hole since 2026-08-02 as "the one part of this brief
that D-068–D-074 did not close". Every cost in the ladder was therefore
authored against a table with empty cells — which is exactly the trap
D-056 named for health tuning, one layer up.

**This entry does not re-price anything.** It supplies the numbers, shows
what they say about the prices already shipped, and names the change they
imply. Re-pricing is a balance decision with a playtest attached and it
is the owner's, not a side effect of measuring.

---

#### The measured rate

One shipped gatherer crew, working a wood stand through the **real**
`Economy.tick` haul loop — gather, walk, unload, retarget — for 180 s.
Not `gather_rate × soldiers`, which is the number that is wrong: it
ignores the walk, and the walk is most of the elapsed time.

| haul distance | income |
|---|---|
| 2 cells | **105 / min** |
| 5 cells | **90 / min** |
| 10 cells | **75 / min** |

**5 cells is the figure everything below uses** — a crew working the
stand nearest its hall. The spread is the point as much as the value:
where you settle is worth ±30%, which is what D-104's "a start is a
PLACE" was arguing about with no number to hand.

Income is quantised by `carry_capacity` (45) — a crew earns in
deliveries, not continuously — so these are 7, 6 and 5 round trips in
three minutes. A shorter window would land between deliveries and read
as noise.

#### D-068's table, filled

Crew counts are **design targets**, not measurements: they say what a
player is expected to have working in each phase, and they are what turns
the measured rate into a per-phase income. Everything to the right of
them is arithmetic.

| Phase | Minutes | Epoch | Crews | Income / min | Bank over the phase |
|---|---|---|---|---|---|
| Opening | 0–8 | 1 | 1 → 3 | 90–270 | ~1,100 |
| Expansion | 8–22 | 1→2 | 3 → 6 | 270–540 | ~5,700 |
| First contact | 22–35 | 2 | 6 → 9 | 540–810 | ~8,800 |
| Consolidation | 35–55 | 3 | 9 → 12 | 810–1,080 | ~18,900 |
| Mid-war | 55–75 | 3→4 | 12 → 14 | 1,080–1,260 | ~23,400 |
| Decision | 75–95 | 4→5 | 14 | ~1,260 | ~25,200 |

Read "income" as **per resource a player is actively working**, not as a
total: a crew works one node at a time, so a player splitting crews
between food and wood earns roughly half of each. The bank column is the
gross a phase produces before anything is spent on troops, which is the
ceiling a cost has to fit inside — never the money actually available.

#### What the numbers say about the prices already shipped

This is the finding, and it is uncomfortable:

| Advance | cost (D-069) | at that phase's crews | **minutes of income** |
|---|---|---|---|
| 1→2 | 500f 300w | 3 | **1.9** |
| 2→3 | 800f 500w 200g | 6 | **1.5** |
| 3→4 | 1200f 800w 500g | 9 | **1.5** |
| 4→5 | 1800f 1200w 900g 400s | 12 | **1.7** |

**Every rung costs under two minutes of the income of the phase that pays
for it, against phases D-068 makes 8 to 20 minutes long.** D-069 set
itself the requirement that the gate "cost enough that paying it visibly
means not fielding troops for a stretch"; two minutes is not a stretch,
it is a rounding error. The whole ladder is roughly **seven minutes of
banking** in a match designed to run ninety.

So the ladder as costed cannot pace a 90-minute match, and it was never
going to — the costs were derived from a table with no rate in it, so
there was nothing to check them against. That is the gap the ticket
names, arriving as a number.

**The implied change is about ×3 across the table**, which would put each
rung at 4–6 minutes of its phase's income. Recorded as a recommendation
and deliberately not applied — see the fence at the top of this entry,
and the revisit trigger below.

#### And the open question, finally recomputed

`OPEN-QUESTIONS.md` has asked since 2026-08-02 whether an hour-long match
exhausts the map, and recorded that it needed the real constants and a
consumption rate. Both now exist.

The shipped default map, from `just gen-terrain-preview` (2026-08-28,
168×194 = 32,592 cells): **5,559 nodes — 1,939 food, 3,435 wood, 48 gold,
137 stone.** At `TREE_STOCK` 105 for food and wood and `RICH_STOCK` 2,400
for gold and stone:

| | total on the map | per player at 20 starts |
|---|---|---|
| food | 203,595 | 10,180 |
| wood | 360,675 | 18,034 |
| **gold** | **115,200** | **5,760** |
| stone | 328,800 | 16,440 |

Against one civ's tree (measured, `tests/test_pacing.gd`): the **spine**
— every defining line — is 4,300f / 2,800w / 1,600g / 400s, and the
**whole tree** including every branch is 10,200f / 7,160w / 5,060g /
2,000s.

**At D-018's 20 players the whole tree costs 100% of a player's food
share and 88% of their gold share, before a single soldier.** That is not
a tight budget, it is a collision — and it gets worse, not better, under
the ×3 the pacing asks for. At four players the same map gives each
player five times as much and none of this binds, which is why no load
test has ever noticed.

Three things follow, and none of them is "make nodes richer":

- **Gold is the scarce resource and nothing treats it as one.** 48 seams
  on the whole map against 3,435 wood nodes. It is the resource the tree
  leans on hardest and the one a player is least able to find.
- **Food has to stop being a fixed stock.** A renewable source is already
  in flight (#159), which is the correct lever: an economy that can only
  ever spend down cannot support a ninety-minute anything.
- **It is another entry in the player-count column.**
  `D-20260818-battle-quality-outranks-player-count` already trades
  D-018's 20 players away and says its successor will be MEASURED. This
  is one of the measurements: the map's resource budget does not support
  20 players climbing a full tree, and that is a fact about the target
  rather than about the tree.

---

#### Rejected alternatives

- **Derive the rate from `gather_rate × squad_size`.** Rejected — it
  reads 1.96/s = 118/min for the shipped crew, against a measured 90, and
  the difference is the entire haul. A closed form that ignores the walk
  would have made "where you settle" worth nothing and priced the tree
  against an economy nobody has.
- **Pin the exact income in the test.** Rejected — it would go red on
  every balance pass and be deleted inside a month, and then the table
  would have no guard at all. The test asserts wide bands; the numbers
  live here, dated, per `decisions/README.md` rule 5.
- **Re-price the ladder in this change.** Rejected — it invalidates the
  `test-load` figures taken against the current costs, it changes a table
  `tests/test_tech_tree.gd` pins, and it is a balance call that wants a
  playtest. Measuring and re-pricing in one commit also makes it
  impossible to tell which of the two a later regression came from.
- **Raise `TREE_STOCK` or add gold seams so the tree fits.** Rejected as
  the answer to the wrong question. The tree costing a player's whole
  share is a statement about the player COUNT and about food being a
  fixed stock; making the pile bigger hides both.

#### Consequences

- **D-068 stops being a table with empty cells**, and D-069's and D-072's
  claims to derive from it become checkable. Neither entry is edited —
  they are frozen and cited — but a reader of either now has somewhere to
  go for the rate.
- **`OPEN-QUESTIONS.md`'s pacing bullet is discharged**, and the answer
  it was waiting for turns out to be "yes, at 20 players, food first".
- **A rate that changes is now visible.** Anything touching
  `gather_rate`, `carry_capacity`, `TREE_STOCK`, gatherer `move_speed` or
  the haul loop moves these figures, and `tests/test_pacing.gd` prints
  them on every run rather than leaving them to be rediscovered.

#### Revisit trigger

**The first time the ladder is re-priced**, this entry's ×3 recommendation
is either applied or superseded with the reason. And the standing one:
**if telemetry ever shows matches landing outside 60–120 minutes in the
majority**, D-068's phase table is wrong and these numbers are re-derived
from a corrected one — not patched individually, which is precisely the
failure D-056 recorded.

---

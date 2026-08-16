### D-056 · 2026-08-02 · Provisional — match pacing, and what it is NOT solved by
**Decision:** Target match length is **1–2 hours** (stated by the project
owner, 2026-08-02). Two changes toward it, both data:

1. **`UnitDef.damage_vs_buildings`** (schema addition against D-010),
   default **0.15**. A squad's siege output is its ordinary damage scaled
   by this. Soldiers are not siege engines.
2. **Building health roughly tripled** — town centre 900 → 3000, barracks
   600 → 1600, tower 450 → 1400, storehouse 300 → 700 — and **`squad_cap`
   15 → 40** on both shipped maps.

**Rationale:** matches were deciding at ~200–230 s. Measured cause, one
squad against a 900 HP town centre with no modifier:

| | time to raze |
|---|---|
| legion_militia (36 × 9.5) | **2.1 s** |
| legion_heavy (24 × 15.0) | 2.9 s |
| northmen_militia (44 × 6.5) | 3.1 s |

A base evaporated the instant any army reached it. **That number was
introduced by D-055 the same day**: siege damage was written as
`damage * alive`, mirroring squad-vs-squad, because there was no prior
building balance to mirror — buildings had never been damageable at all.

`squad_cap` was 15 against D-018's target of **~50 squads/player**. About
9 go to gatherers, so an "army" was ~6 squads. The architecture is built
for 3× more army than the maps permitted, and M4 already showed the sim
carrying 120 squads at 20 players inside D-020's tick budget — this was a
data ceiling, never a performance one.

**A separate field rather than an entry in `bonus_vs`.** `bonus_vs` reads
1.0 for a missing key, which is right for a counter table (no entry =
generalist) and exactly wrong here: forgetting it on a new unit would
silently restore the three-second base. `damage_vs_buildings` defaults to
the SAFE end, so an unaware .tres is conservative rather than
catastrophic. It is also the hook a future siege archetype hangs on, with
no code change.

**Rejected alternatives:**
- *Tune building HP alone.* Would need absurd numbers (a 6-squad army at
  full damage is ~1,800 HP/second) and would make towers unkillable in
  the same stroke.
- *A constant in `combat.gd`.* Violates D-010, and forecloses siege units.

**Consequences and the honest limit:** this does **not** reach 1–2 hours,
and is not expected to. It stops bases evaporating and lets armies be
armies. **The structural reason an hour is unreachable is that there is
no progression at all** — four buildings and four units per civ, no ages,
no tech, no upgrades — so after roughly three minutes there is nothing to
do but fight. *Empires: DotMW* and *AoE* both stretch matches with epochs
to climb, and that machinery does not exist here.

**That is deliberately deferred to its own planning milestone** (project
owner's call, 2026-08-02): get the basics working first, plan age/tech
progression in a separate session. See Q15 in the open questions.

**Amended 2026-08-04 — the slower opening is WANTED, not a regression.**

Shrinking gatherer crews 16 → 5 tripled the time to staff an economy,
because `AiPlayer.TRAIN_COOLDOWN` gates production ORDERS rather than
labour: the same ~110 workers take 22 productions instead of 7. First
contact moved from 121–160 s to ~326 s.

I raised that as a bug to fix. **The owner's call is that the old ramp was
far too quick and the longer one should stay.** It pulls the same
direction as this decision's 1–2 hour target: an opening you can be
attacked out of in two minutes is a race, not a strategy game.

Recorded because the cooldown looks like a scaling defect to anyone
reading it cold — the comment on the constant now says so too. The thing
to re-derive when pacing changes is `ai-ladder`'s SECONDS default, which
has already been stale once for precisely this reason: it ran 300 s while
first contact landed at 326 s, reported `attacks=0`, and was read as a
broken AI for a whole session.

**Measured after the change** (`ai-ladder 2 900`), and two corrections
worth keeping because both were confident and wrong:

- Match length **~215 s → ~325 s decided**. Longer, still not the target.
- **The economy was never the constraint.** I predicted the raised cap
  would hit an economy wall on the reasoning that 7 gatherers could not
  fund 33 squads. There is no upkeep, so a worker count caps the RATE of
  buying and never the SIZE of an army. Legion banked a peak stockpile of
  **2,480 while pinned at the squad cap**; northmen sat on 985 and
  fielded eight squads. `AI_STATS` now reports `peak_stockpile`,
  `afford_refusals` and `cap_refusals` so this is a number rather than an
  argument.
- **The cap of 15 WAS binding — for the AI.** I said it was not, which
  was true of `test-load`'s bots (6 squads of 15) and false for the AI,
  pinned at exactly 15–16 and reaching 41 once the cap moved. Generalised
  from the bots without checking.

**Still open, and an AI defect rather than a mechanic one:** legion held
41 squads against northmen's 8, knew all three of its buildings, attacked
93 times over 900 s and never finished the match.

**Revisit trigger:** the age/tech milestone landing, which will re-derive
these numbers from a phase-by-phase account of what a 1–2 hour match is
made of, rather than from stopping the worst behaviour.

**Trigger FIRED, 2026-08-04 — see D-068 through D-074.** The
phase-by-phase account this entry asked for is D-068. What it means for
the numbers here:

- **`damage_vs_buildings` (0.15) stands**, and gains a second job: it is
  the knob Byzantine siege and Magyar non-siege are both expressed
  through (D-073).
- **The tripled building health is superseded by D-066/D-067**, which
  landed on main the same day from the other direction: tower **1400 →
  1700 HP**, town centre damage **12 → 60**, tower damage **20 → 85**,
  against an explicit rule that **one squad must fail and two must
  succeed**. Whatever the values, they are now *epoch-1* figures rather
  than global ones — buildings gain `BuildingDef.epoch` (D-070) and later
  rungs get their own.
- **`squad_cap` 40 is superseded in ROLE, not in value.** D-068 makes
  upkeep the binding constraint and returns `squad_cap` to being the
  engineering ceiling protecting D-018 and D-020. It should end up set
  high enough that a player never feels it.
- **The "still open" AI defect stands** — Legion holding 41 squads
  against 8, attacking 93 times over 900 s and never finishing. Upkeep
  makes an unfinished match expensive rather than free, which pressures
  the symptom but is not a fix for it.

This entry stays **Provisional**: its numbers were tuned to stop the worst
behaviour, and D-072 is the beginning of replacing them with derived ones,
not the end.

---

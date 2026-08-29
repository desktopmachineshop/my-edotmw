### D-20260828 · 2026-08-28 · Accepted — a fortification frightens men, and morale does not recover under fire

**Decision:** `morale_recovery_per_second` is suppressed for
`Combat.MORALE_SUPPRESSED_TICKS` (20 ticks, 2 s) after a squad **takes
damage** — from any source. Recorded on the BLOW, before the casualty
rounding, at both places damage is applied (`_shoot_squad`, which is what
building fire and missiles come through, and the melee resolution), so
"under fire" means one thing whatever is doing the shooting.

**Rationale.** `Combat._shoot_squad` calls `_break_squad` and has carried
this comment since `D-20260819-morale-reads-the-fight`:

> Being shelled by a fortification breaks a squad the same way being
> beaten by another squad does — through the same `_break_squad`, so a
> tower-driven rout shocks nearby allies exactly like a melee one.

The mechanism was correct and, at the shipped numbers, **unreachable**
(#218). A squad parked in a town centre's reach was shot to the last man
with its morale never below **~94 of 100** against a rout threshold of
25.

The cause was not the building's damage. Recovery was restored every tick
with no condition, so it acted as a **floor on how fast anything could
frighten anybody**: it is 2.0 on every shipped def, and a town centre's
morale pressure on a levy squad is 1.4–1.9 a second. The net was
**positive** — morale rising while the squad was annihilated. Fifth
instance of the D-055/D-066 family: mechanism correct, shipped numbers do
nothing, and a test proving `_shoot_squad` can rout a squad with a
caricature def passed throughout.

**Keyed on DAMAGE, not on casualties, and that is load-bearing.** The
first version keyed it on losing a man. That took the town centre case
from 94 to **41** and still did not rout, because a town centre firing
every 1.4 s kills an 85 HP levy only every ~2.8 s and recovery leaked
through every gap. The repair for THAT would have been lengthening the
window until it outlasted one particular building's rate of fire — a
constant fitted to a fixture, which this project has paid for before
(`D-20260818`'s chord measured in seconds). Being shot at is what stops
men steadying, whether or not the shell killed one, and it needs no
knowledge of any building's cadence.

**Not building-specific, though #218 was reported about a tower.** The
defect is that recovery ignored whether anything was happening; a rule
that only noticed fortifications would leave slow melee attrition reading
the same wrong way.

**Two clauses keep it from being blunt.** The fearless are untouched —
gravesworn ship `rout_threshold 0` and `morale_loss_per_casualty 0` by
design (#191) and a change to how morale RECOVERS must not reach them. And
a squad that breaks contact still recovers: the suppression is a window,
not a rule that morale never returns, because a squad that can never
recover can never rally (D-019) and a rout stops being a setback and
becomes a death sentence. A test drives both.

**Rejected alternatives:**
- *A morale multiplier on building fire alone* (#218's second candidate;
  rejected — it leaves unconditional recovery in place as a floor under
  every other slow source of attrition, and adds a constant where the
  general fix removes one.)
- *Lengthening the window until the slowest building routs* (rejected on
  the measurement above — that is a number fitted to a town centre's
  attack interval, and the next building with a slower one would need it
  raised again.)
- *Suppressing recovery for the whole engagement* (rejected — it deletes
  the rally.)

**Consequences, and the important one is a COUPLING.** Squads now break
under building fire, which means besiegers flee, which means buildings
are harder to take. **Measured on a probe tree carrying both this change
and `D-20260827-a-buildings-hp-is-one-knob-and-the-rule-needs-two`'s
re-derived HP (tower 1250, town centre 2400):** D-067's pair rule fails
for the two flimsiest line troops, narrowly —

| | HP left |
|---|---|
| thornwood_levy vs town centre | 121 of 2400 |
| windmarch_levy vs town centre | 86 of 2400 |
| thornwood_levy vs tower | 168 of 1250 |
| windmarch_levy vs tower | 94 of 1250 |

all under 7% of the building. **Also measured: tower 1050 and town centre
2200 restore the rule** — 68 of 69 in `test_buildings.gd`, the one
failure being #202's unrelated `militia` fixture, with the solo half
still holding.

Those numbers are **deliberately not shipped here.** They belong to the
decision that derived them, that PR is in review, and a second agent is
re-deriving the same fixture — two branches moving one set of numbers is
the collision this work was split to avoid. Whoever merges both should
apply them and re-run the table rather than trusting the arithmetic.

**Measured:** `just test-unit fortifications` — 6 tests, every one a whole
encounter with shipped defs. Lowest morale under a town centre's fire
goes **94.8 → below 25** for the levy the issue named, and both buildings
now break every non-fearless levy in the roster. Full suite 1232/1255 on
this branch, against `main`'s baseline of 22 failures — no new ones.

**Revisit trigger:** if `MORALE_SUPPRESSED_TICKS` is ever raised past a
second or two, check the rally first — the window's whole safety comes
from being much shorter than the time a fled squad spends out of contact.
And if a future unit ships a `morale_recovery_per_second` far above 2.0,
re-take the town-centre trace: the floor this removes is proportional to
that number.

---

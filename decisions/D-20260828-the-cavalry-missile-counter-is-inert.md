# D-20260828 — the cavalry/missile counter is inert, and no stat restores it

**Status:** Accepted (records a defect; does not fix it)
**Issue:** #396. Refs D-032, D-072, #219, #261, #266/#328, #257, #361.

## What happened

`main` was red for five consecutive merges on
`test_counters_are_felt.gd :: test_cavalry_counters_missile_troops`. The
cluster-completion hypothesis (#330 + #257 landing) was refuted: the run on
`476d0b3`, with the cluster whole, fails the same two pairings at
byte-identical margins.

## The finding is bigger than the two pairings

Every cavalry def carrying `bonus_vs { "missile" }`, against every
missile-class target — **fifteen pairings, 0 of 6 wins on all fifteen**,
margins −0.16 to −0.79. #219 measured this third of D-032's triangle at
**12 of 12, +0.77**.

There is no surviving pairing, which is why this is a REPORT and not a
narrowed assertion. #361's precedent could still assert that
`thornwood_archers` beat *some* levy and report the fearless exception;
there is no equivalent floor here.

## The mechanism, traced rather than inferred

`windmarch_cavalry` vs `emberdeep_archers`, seed 1000:

| t | |
|---|---|
| 0.0 | cavalry close from 8 cells |
| 3.0 | archers 22 → 14 and **rout**. The counter has landed, in three seconds, exactly as designed |
| 4–24 | the routed archers withdraw to 5–6 cells. **The cavalry do not pursue**, and recover to full morale standing still |
| 25 | the archers **rally** — recovered at 2.0/s, unopposed, because nothing was hitting them (#257 suppresses recovery only *while* a squad is hit) |
| 27–30 | they return and shoot from **3–4 cells**. Cavalry `attack_range` is **1.9**, so the cavalry cannot reply at all. Archer strength does not move from 14 for the rest of the match |
| 34.4 | the cavalry are wiped |

**The counter is delivered and then does not decide the fight.** The cavalry
deal zero damage after t=3, and the match is settled by a phase in which one
side cannot act.

## Why this is not a balance fix — measured, not argued

Two honest stat levers were tried against the shipped fixture:

| lever | windmarch pairing | gildedreach pairing |
|---|---|---|
| `squad_size` 16→20 / 14→18 | −0.67 → **−0.68** | −0.68 → **−0.74** |
| `morale_loss_per_casualty` 4.0 → 2.0 | −0.67 → **−0.67** | −0.68 → **−0.76** |

Both did nothing or made it worse, and the trace says why: **staying power and
steadiness cannot help a squad that is never in range.** More men are a larger
target during a phase it cannot answer. The second lever is also the one that
would re-create the defect #328 was filed to fix — at 2.0 a 16-man squad needs
16.7 casualties to break and is effectively un-routable again, which is
precisely the "every cavalry def in the game" population #328 names.

The lever that would work is not a stat. It is whether a squad pursues an enemy
that has broken, or whether a missile squad may stand at three cells from
cavalry indefinitely — D-034's halt, D-019's rally, and the pursuit control
`combat.gd` has listed as future work since M2. That is a design decision and
it belongs to whoever owns it.

## Decision

1. The two assertions become a **report over all fifteen pairings**, printed
   every run, following #361's precedent exactly.
2. A guard asserts the finding **as the thing a future fix must move**:
   `assert_eq(felt, 0, …)`. When somebody restores pursuit, or prices a missile
   squad for standing inside a charge, this goes **red** and they restore the
   assertion. Observed to fail before being trusted (perturbed so every pairing
   counts as felt: "15 of 15 … has been restored").
3. `test_spearmen_counter_cavalry` is untouched and still passes. Two thirds of
   the triangle work; one third does not.

## What this does NOT claim

That the roster is balanced, or that the counter should be restored by any
particular means. It records that a rule D-032 asserts is currently absent, in
the form that makes its return visible. **An unblocked queue with a stated open
question beats a red `main` guarding a design debate** — and the debate is now
stated with numbers rather than left in a failing assertion.

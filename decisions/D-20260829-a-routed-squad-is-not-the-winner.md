# D-20260829 — a routed squad is not the winner

**Status:** Accepted (fixes an instrument, not a balance number)
**Issue:** the last two reds on `main`. Refs D-019, #396, #347/#267, D-022.

## What was wrong

`test_levies_are_sidegrades.gd` played one levy pairing through the real
sim and scored it by **surviving fraction**. That metric crowns the side
that runs away.

Traced at seed 11, before this change:

| t | |
|---|---|
| 0–4 | the squads close and fight — gildedreach 30 → 22, windmarch 28 → 22 |
| 6 | **windmarch breaks** (morale 4.9) and withdraws |
| 6–24 | it sits at eight cells. Gildedreach does not pursue. **Both frozen at exactly 20 men** |
| end | gildedreach **20/30 = 0.67**, windmarch **20/28 = 0.71** |

Gildedreach lost ten men, windmarch eight, and windmarch broke. The
fixture reported *"windmarch's levy swept gildedreach's in every fight"*.

**A fleeing squad stops taking casualties and nothing chases it**, so
routing *raises* your score. The metric was measuring which side quit
first and calling it a win.

## The control was not weak — it was inverted

The same test rigs a control: double gildedreach's damage and it must
sweep. It did not, and that read as "this fixture cannot see a gross
imbalance".

It sees it perfectly. **Doubling the damage breaks windmarch sooner, so
windmarch flees with more men, so the buff moves the fraction the wrong
way.** A control that measures the wrong quantity does not merely fail to
detect an effect; it detects it with the sign reversed. That is worse than
an insensitive control, because a failing control reads as "the fixture is
broken" when the fixture is working and the *question* is wrong.

## Decision

**A side that breaks has lost the engagement.** First-to-rout decides the
fight; surviving fraction remains the tie-break where neither side breaks.

This is not a new rule invented for a test. It is D-019's premise, and
`docs/status/rtw-battles.md` states it in words already: *"a rout is a
defeat rather than a pause."* The fixture was the only thing that
disagreed.

First-to-rout is **latched**, because a broken squad can rally (D-019) and
"is routed at the end" would instead score a fight by whether the loser
had recovered yet.

Every fight now prints its fractions *and* who broke, so the two readings
can never silently diverge again.

## What this does not claim

That the levies are balanced. It claims only that the previous answer was
produced by a metric that rewarded routing, so **neither the sweep nor the
even result it reported meant anything**. Whatever the corrected fixture
says is the first real measurement of this pairing.

**If the corrected metric shows a genuine sweep**, that is a balance
finding for the roster's owner and belongs on the reported list under
#399's precedent — not a reason to change the metric again.

## The family this belongs to

Third instance in two days of the same shape: **an instrument that
disagrees with the game's own stated rule**. #396 found the counter
triangle decided by a phase in which one side could not act; this found a
scoreboard that rewards breaking. Both trace to rout-plus-no-pursuit, and
both were invisible to every number until somebody watched a single fight
tick by tick.

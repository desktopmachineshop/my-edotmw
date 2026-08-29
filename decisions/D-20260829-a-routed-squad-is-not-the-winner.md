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

## The measurement, taken by CI once the metric was right

**Even: gildedreach 3 – 3 windmarch. Control: 6 – 0.** The levies are
sidegrades, the control works, and both were previously unknowable.

| seed | swap | gilded | wind | broke |
|---|---|---|---|---|
| 11 | false | 0.67 | 0.71 | wind |
| 11 | true | 0.60 | 0.68 | gilded |
| 2029 | false | 0.70 | 0.71 | wind |
| 2029 | true | 0.63 | 0.79 | gilded |
| 7919 | false | 0.67 | 0.71 | wind |
| 7919 | true | 0.57 | 0.68 | gilded |

Two things fall out of that table, and neither was visible before.

**The old metric favoured the SMALLER SQUAD systematically.** Windmarch
scores higher on fraction in *all six* fights — including the three it
broke in. It fields 28 men against gildedreach's 30, so the same absolute
losses read as a better fraction. The fixture was not measuring a levy; it
was measuring squad size.

**Who breaks is POSITIONAL, 6 out of 6.** The squad starting at the second
position breaks every time, and swapping the sides swaps who breaks. That
is why playing both sides is load-bearing rather than tidy, and why 3 – 3
is the honest answer: each levy breaks exactly when it is put in the
losing seat. A fixture that played one side only would have reported a
6 – 0 sweep for whichever civ it happened to place second.

---

## Amendment, same day (#406) — annihilation outranks breaking

The rule above was right and incomplete: **a rout is not final.** A broken
squad can rally (D-019) and go on to destroy the side that held, so
first-to-break is the correct rule for fights that end in a rout and the
wrong one for fights that end in a wipe.

Caught in this fixture's own printed output, one run after it was written:

```
seed 2029  swap=true   gilded 0.00  wind 0.39  broke=wind
```

Gildedreach was **annihilated** and the metric credited it the win. The
control's 6 – 0 therefore included a fight its winner had lost outright —
a green control worth exactly nothing, which is the thing this entry was
written to stop.

**A squad reduced to nothing has lost, whatever the morale ledger says.**
The wipe is read first; first-to-break decides only among survivors.

### The control was recalibrated, and the factor was MEASURED

Adding the clause takes the control to **5 – 1** at x2 — one fight short.
That is the honest red, and it makes 81's reading on #346 live: x2 was
calibrated against a world that has since moved, with sweep thresholds
going from 2% to 10–20%.

Swept on CI over the shipped defs:

| factor | result |
|---|---|
| **x2** | **5 – 1** — no longer sweeps |
| **x3** | **6 – 0** |
| x4 | 6 – 0 |
| x5 | 6 – 0 |
| x7 | 6 – 0 |

**x3 is the smallest measured factor that sweeps**, and the sweep is stable
above it rather than perched on a threshold. The boundary between x2 and x3
is deliberately not narrowed: this control asks whether the fixture can see
a GROSS imbalance, and one tuned to the edge would be measuring its own
precision instead.

The even case is **unchanged at 3 – 3** — no fight in it contains a 0.00,
so the clause cannot touch it. `main` stayed green throughout.

### What was refused

Quieting the control by tuning unit data. That would leave the fixture
measuring the tuning, and it is the outcome this entry's parent already
warned against.

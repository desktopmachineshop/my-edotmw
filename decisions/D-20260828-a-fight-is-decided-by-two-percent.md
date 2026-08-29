# D-20260828-a-fight-is-decided-by-two-percent

**Date:** 2026-08-28 · **Status:** Accepted

From issue #346, which came out of #267: a **2% edge in squad damage wins
10 of 12 mirror fights**, and every duel runs to annihilation. That is far
narrower than any balance pass can hold, so it is the mechanism behind
#267's levy tier list rather than a roster fault — and it means no unit
anywhere can carry genuinely trading strengths.

This entry measures the three candidate fixes the issue named and
**ships none of them**, because two were measured not to work and the one
that does is already in the review queue.

## The baseline

Stoneblood's levy against itself, one side's `damage` multiplied, probed
unit placed on **both** sides so position bias divides out. 6 seeds x 2
sides = 12 fights per row.

| edge | stronger-weaker | mean fight |
|---|---|---|
| 0% | 6-6 | 44.3 s |
| **2%** | **10-1** | 40.9 s |
| 4% | 11-1 | 34.1 s |
| 6% | 11-1 | 31.5 s |
| 8% | 11-1 | 30.7 s |
| 10% | 12-0 | 27.8 s |
| 15% | 12-0 | 23.9 s |

`V² = n²·(damage/interval)·health` is exactly Lanchester's square-law
strength for a melee where everyone is engaged, and it compounds: the
side a single rounding puts one man ahead kills marginally faster and
pulls away. Traced in a mirror, the two squads track in **exact lockstep
for ~20 s** and then separate and never re-converge.

**Why nothing stops it: a squad must lose 85% of its men before it
routs.** Shipped defaults are morale 100, `rout_threshold` 25,
`morale_loss_per_casualty` 4.0 — so a 22-man levy needs **18.8
casualties of 22** to break. The rout can never end a fight; the squad is
destroyed first. Every duel therefore runs to annihilation, and whoever
is ahead wins regardless of margin.

## Option A — casualty softening. Measured, rejected.

Make output fall with a root of strength rather than with strength:
multiply damage by `(alive/squad_size)^(k-1)`, which is exactly 1.0 at
full strength so no shipped balance number moves for a fresh squad. It
is D-024-legal — D-024 says damage output is "a function of aggregate
squad state" and never that the function is linear, and the multiplier
had already stopped being raw `alive` when D-20260819 made it the men in
contact.

Implemented and swept over four exponents, same harness:

| k | 0% edge | 5% | 10% | 20% | mean fight at 0% |
|---|---|---|---|---|---|
| 1.00 (off) | 6-6 | 11-1 | 12-0 | 12-0 | 44.3 s |
| 0.75 | 6-6 | 11-1 | 12-0 | 12-0 | 32.9 s |
| 0.50 | 6-6 | 11-1 | 12-0 | 12-0 | 24.4 s |
| 0.25 | 5-5 | 11-1 | 12-0 | 12-0 | 19.1 s |

**It changes nothing about who wins, at any exponent.** Obvious in
hindsight and not before: the softening applies to both sides equally, so
it changes the *pace* of the runaway and not its direction. All it buys
is shorter fights, which is the wrong direction for D-056's match-length
target. Reverted.

## Option B — engagement-width cap. Measured, rejected.

Cap the men who can fight at an absolute number, so that while both
squads are above the cap they trade evenly whatever their casualties.
Measured at a cap of 12, on top of option C:

| edge | C alone | C + width cap |
|---|---|---|
| 0% | 6-6 (22.3 s) | 6-6 (30.1 s) |
| 2% | **8-4** | 9-3 |
| 5% | **9-3** | 10-2 |
| 10% | 11-1 | 11-1 |

**Slightly worse than not doing it**, and it lengthens fights. It also
flattens what `squad_size` means, which would invalidate D-072's power
number for every unit at once.

## Option C — morale-first, per D-019. This is the lever.

Make the fight END by rout instead of by annihilation. Measured with
**PR #328** (morale scales with squad size, #266) and **PR #257** (no
morale recovery under fire, #218) applied together:

| edge | baseline | with #328 + #257 |
|---|---|---|
| 0% | 6-6 | 6-6 |
| **2%** | **10-1** | **8-4** |
| 5% | 11-1 | 9-3 |
| 10% | 12-0 | 11-1 |
| 20% | 12-0 | 12-0 |

**The sweep threshold moves from ~2% to ~10-20% — a five- to tenfold
widening of the band in which a fight is still a fight.** The mechanism
is visible in a trace: with #328 a 22-man levy breaks at **alive = 10
(55% casualties)** instead of 85%, so the rout finally fires while there
is still a squad left to save.

**Both PRs are already open and reviewed-pending. They are the fix for
#346, and this entry's practical recommendation is to merge them.**

## What is NOT fixed by C, and why nothing further ships

With #328 + #257 the duel still ends in annihilation, because a broken
squad **rallies and walks back into the fight it just lost**. Traced:
breaks at t=11.6 s, rallies at t=22.8 s, breaks again at t=47.3 s, final
separation **1 cell**. `rout_rally_margin` 15 at 2 morale/s is about ten
seconds, and the pursuer is never left behind.

Two further mechanisms were built and measured:

- **Flee pace** (a broken squad runs at 1.5x): decisiveness *identical*
  to C alone (8-4 / 9-3 / 11-1); fights get longer. No.
- **Rally requires breaking contact** (no rally within 6 cells of a
  hostile): this does end fights without annihilation — seed 11 finishes
  **10 v 10** — but it creates a worse state than it cures. Two routed
  squads end up **1 cell apart, neither able to rally, permanently out of
  the game**. Fixing *that* needs a disengagement mechanism that does not
  exist, and inventing one here would be a third mechanism deep into a
  change nobody has playtested.

So: **no new combat mechanism ships from #346.** What ships is the
measurement, the instrument, and the finding that the fix is already in
the queue.

## Decision

1. **Combat is unchanged by this entry.** Options A and B are rejected on
   their own numbers; C is already implemented in #328 and #257.
2. **`tests/test_battle_decisiveness.gd` is an INSTRUMENT, not a gate**,
   in the style of `bench-render` and `gen-terrain-shot`: it prints the
   decisiveness curve and asserts only what must hold whatever the tuning
   is. A tight threshold belongs with #328/#257 once those land and the
   curve has moved — pinning today's number would go red on the fix.
3. **The exit criterion for #346 is a re-measurement**, not a feature:
   re-run the instrument once #328 and #257 are merged and record the
   curve. If a 2% edge still wins 10 of 12, this entry is wrong.

## Two corrections to my own measurements, recorded rather than buried

- **"Loser survivors 0.0% at every edge" is partly an artifact.** The
  harness loops until one side reaches zero, so a wipe is close to
  guaranteed by the termination condition. The honest claim is narrower:
  *every duel ended in annihilation inside the window rather than by one
  side withdrawing* — which is still the finding, but it is not an
  independent measurement of survivors.
- **The first version of the mirror test could not see what it claimed
  to.** It scored by which *def* was buffed and played both ways round,
  so a side bias cancels out of it exactly. Perturbing `combat.gd` to
  give squad 0 a flat 25% damage bonus left it reporting a tidy 2-2. It
  counts by POSITION now, and the perturbation was the only thing that
  revealed it.

## A separate finding: some mirror matches are decided by POSITION

Identical squads, identical orders, symmetric positions on a torus, six
seeds — and the result is often constant across every seed:

| levy | first-placed | second-placed |
|---|---|---|
| emberdeep | 0 | 6 |
| windmarch | 0 | 6 |
| gravesworn | 5 | 1 |
| stoneblood | 4 | 1 (1 draw) |
| gildedreach | 4 | 2 |
| thornwood | 4 | 2 |

Seed-independence means this is not the RNG; something in approach,
facing or arrival order is worth a man or two, and the square law then
magnifies it into the whole result. Measured on the pre-#347 roster.
**Not diagnosed and not filed as fixed here** — it is a plausible partial
explanation of why #267's pairings clustered on exact 6-6 splits, and it
wants its own investigation.

## Rejected

- **Shipping option A anyway for its pacing effect.** It shortens fights
  by up to half, and D-056 wants matches *longer*. A change that fails
  its own purpose should not be re-justified by a side effect.
- **A threshold assertion in the instrument.** Written, run, removed: at
  a sample small enough for the suite it reports 4-0 on the current tree,
  so it would have shipped red.
- **Any per-soldier resolution.** D-024's rejected-alternatives list
  already covers this and nothing measured here reopens it.

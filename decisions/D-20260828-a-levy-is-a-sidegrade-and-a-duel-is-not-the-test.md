# D-20260828-a-levy-is-a-sidegrade-and-a-duel-is-not-the-test

**Date:** 2026-08-28 · **Status:** Accepted

From issue #267: every civ's levy is strictly ranked, 14 of 15 pairings
6-0, 13 of them with zero survivors — so a player's starting infantry is
a tier list rather than six different units, and the civ you picked
decides the fight before it starts. The issue closes with the right
question: *"If the answer is 'no', the lever is not the levy numbers — it
is whatever makes a 1.22x paper difference produce a 6-0 outcome."*

The answer is no, and this entry is what the lever turned out to be.

## What was measured first, because #267's numbers are stale

**Re-measured on the #334 base** (`armour class is a role, not a
flavour`), which landed after #267 was filed. 15 pairings, both ways
round, 3 seeds:

- **#267's 14-of-15 sweep does not reproduce.** It is **2 of 15**.
  Reclassifying windmarch's levy from `cavalry` to `infantry` removed
  most of the strict ranking on its own, because the counter triangle
  had been firing against a levy for being flavoured as horse.
- **The mechanism #267 names is not the one operating.** The issue
  blames `D-20260819-only-men-in-contact-fight` — frontage capped by
  geometry. Measured directly off `Engagement.contact_count`, a levy at
  full strength gets **100% of its men into contact up to n=40, 92% at
  n=48, 82% at n=60**. The cap is real and mild; it is not what produced
  a 6-0.

So the ranking was smaller than reported and caused by something else.

## What actually produces a sweep

`V² = n²·(damage/interval)·health` — D-072's power number is *exactly*
Lanchester's square-law strength for a melee where everyone is engaged,
which is what these fights are. Probing one levy against itself with a
single field changed, 12 fights each, probed unit on both sides so side
bias divides out:

| perturbation | result | net men |
|---|---|---|
| `damage` ×1.10 (V ×1.05) | **12-0** | +82 |
| `attack_range` 1.9 → 2.6 | 11-1 | +21 |
| `attack_range` 1.9 → 3.4 | 11-1 | +21 |
| `move_speed` 3.2 → 6.4 | 6-6 | +4 |
| `formation_spacing` 1.0 → 1.6 | 0-12 | −47 |

And the exchange rate between the two, which is the load-bearing
measurement:

| | ×1.00 damage | ×0.85 (V ×0.92) | ×0.75 (V ×0.87) |
|---|---|---|---|
| reach 2.1 | 4-4 | 0-8 | 0-8 |
| reach 2.3 | 7-1 | 0-8 | 0-8 |
| reach 2.6 | 7-1 | 0-8 | 0-8 |

**A 5% edge in V is a clean sweep. No other field in `UnitDef` is worth
8% of V** — at ×0.85 damage the three reach settings return identical
margins (−72, −72, −71), i.e. reach contributes nothing once you are
behind on the scalar. `move_speed` is worth nothing *in a duel* at all,
which is correct and important: it is spent choosing whether to fight,
and a duel cannot see it.

**That is the lever.** The square law compounds: the side a rounding
puts one man ahead kills marginally faster, so it gets further ahead. In
a mirror match the two sides track in lockstep for ~20 s and then run
away from each other; the loser of that first rounding loses the fight.
A 1.22x paper difference does not produce a 6-0 — a **1.05x** one does.

## Decision

1. **Levies are priced to be a near-draw against each other, and their
   identity lives on the axes a duel cannot express.** Since any scalar
   edge sweeps, "sidegrade" cannot mean *different strengths that trade
   off*; at this sensitivity that is just a tier list with extra steps.
   It has to mean **equal squad power, different units**. What differs:
   how many men, how tough each is, how fast they arrive, how they are
   priced, how quickly they train, whether they rout at all, and how
   wide a front they hold.
2. **V within the sweep threshold, and V/RP with it.** Every levy sits
   inside a band narrower than the 8% at which a sweep becomes certain,
   on both power and power-per-resource. `V/RP` spans 13.88–14.25 (2.7%)
   and V spans 639–662 (3.6%).
3. **Price the EFFECTIVE power, not the paper power.** Gravesworn's 48
   men in a `sparse` block do not all reach and are spread wider, so a
   nominal V equal to everyone else's is a smaller real squad. It is
   *not* charged extra for the V that compensates — charging for a
   handicap is paying twice.
4. **Quantity means bodies per squad, not a discount.** Gravesworn's
   levy cost goes 32 → 47. At 32 it was 20.78 V/RP against everyone
   else's 12.3–14.7 — a 50% efficiency lead, which is not an identity,
   it is a strictly better unit. Its identity is 48 men on the field and
   fearlessness, both of which it keeps.
5. **One counter relationship survives on purpose.** Stoneblood's narrow,
   very tough block beats gravesworn's sparse horde 12-0, and **raising
   gravesworn's V does not touch it** — measured at V 662 and V 734 the
   result is 0-12 both times, while the same increase sweeps the other
   four opponents 12-0. It is a shape matchup, not a power gap, so it is
   left as the one thing on this roster that is genuinely
   rock-paper-scissors.

## The numbers

| levy | n | hp | dmg | int | reach | speed | shape/spacing | V | cost | V/RP |
|---|---|---|---|---|---|---|---|---|---|---|
| emberdeep | 24 | 100 | 8.2 | 1.10 | 1.8 | 2.8 | line | 655 | 46 | 14.25 |
| stoneblood | 22 | 104 | 8.1 | 1.00 | 2.0 | 3.1 | line | 639 | 46 | 13.88 |
| gravesworn | 48 | 38 | 5.0 | 1.00 | 1.9 | 3.0 | sparse, fearless | 662 | 47 | 14.08 |
| gildedreach | 30 | 68 | 6.7 | 1.00 | 1.9 | 3.4 | line, trains in 8.0 s | 640 | 46 | 13.92 |
| thornwood | 30 | 66 | 6.9 | 1.00 | 2.2 | 3.5 | line | 640 | 46 | 13.92 |
| windmarch | 28 | 74 | 7.5 | 1.00 | 1.9 | 4.4 | line, spacing 1.2 | 660 | 47 | 14.03 |

Reach differences are ≤0.4 and are **flavour that was measured to be
affordable** — a dwarf's hand axe is short, a sylvan glaive is long —
rather than a balance lever: at equal V, reach 2.1 scores 4-4.

Windmarch keeps its 1.2 spacing (centaurs are large) and is paid for it
with a small V premium, because loose spacing is a pure handicap in a
mechanic where contact decides damage and it had never been priced.

## Result

15 pairings, both ways round, 6 seeds — 12 fights per pairing:

| | before (#267, as filed) | on the #334 base | after |
|---|---|---|---|
| pairings swept | 14 of 15 | 2 of 15 | **1 of 15** |
| pairings dead even | 0 | 9 | **13** |
| win totals, of 60 | strict order | 15–36 | **22–36** |

The surviving sweep is clause 5's counter. No levy loses to everything,
which is what #267 asked for: thornwood and windmarch were bottom of the
ranking and are now even against four opponents each.

## Consequences

- **Levy costs move a long way and the opening moves with them.**
  Gravesworn 32 → 47, windmarch 38 → 47, thornwood 40 → 46, stoneblood
  50 → 46, emberdeep 48 → 46, gildedreach 45 → 46. Every AI-ladder and
  `test-load` timing taken before this was measured against a different
  price list — the standing "quote it with its roster" rule from
  `docs/status/fantasy-civs.md` applies. The opening itself is
  unaffected: a town hall costs **wood**, and #247/#275's blocker was a
  wood figure.
- **`test_levies_are_sidegrades.gd` guards the property, not the
  numbers**, so it survives #266 (morale scaling) and #218 (suppression)
  landing on top: it asserts the V and V/RP bands, that no levy is
  dominated on both axes, and that every pair differs on at least one
  axis a duel cannot see. Five of its six checks were observed to go red
  under a data perturbation before being trusted (D-022).
- **The sixth — the played one — was observed NOT to, and that is
  recorded rather than papered over.** It stayed green with one side
  given a **20% damage edge**, and only went red at ×2.0. A cross-civ
  pairing carries position effects a mirror match does not, so a played
  fixture over one pairing catches a gross imbalance and not a fine one.
  It therefore ships with a **positive control inside it**: the same six
  fights are replayed with one levy's damage doubled and the test fails
  unless that sweeps. Without it there is no way to distinguish "these
  levies are even" from "this fixture stopped resolving" — the vacuous
  pass D-022's audit block is about. The fine case is caught by the
  arithmetic bands, which is the honest division of labour between the
  two halves.
- **The 5%-sweep measurement is a MIRROR result and must be quoted as
  one.** It was taken with one levy fighting itself and a single field
  changed, which isolates the perturbation; across two different civs the
  same edge can be absorbed by everything else that differs between them.
  That is why the roster band is drawn at 8% rather than 5%, and why the
  played guard is the weaker of the two instruments.
- **The band is 8% because 8% was measured**, not chosen. If the combat
  model's sensitivity changes, that constant is wrong and the test says
  where it came from.

## Rejected

- **Tuning the levies closer together on their existing axes.** This is
  what "make them sidegrades" sounds like and it cannot work: the
  sensitivity is 5%, so tighter scalars make the sweep noisier, not
  absent.
- **Reach or speed as the differentiating currency.** Measured worth
  less than 8% of V (reach) and nothing at all in a duel (speed). Using
  either as the balancing axis would have been the "shipped numbers do
  nothing" family, written deliberately.
- **Changing gravesworn's `sparse` shape to `line`.** It fixes the
  stoneblood matchup (0-12 → 3-9) and costs the swarm its look, and at
  any V that makes the stoneblood fight competitive it sweeps the other
  four. Clause 5 keeps the shape and accepts the counter.
- **Changing the combat model so that a 5% edge is not a sweep.** That is
  the real lever and it is not a roster change — it is an amendment to
  D-024, and it belongs to the owner. Filed separately.

## Revisit trigger

The square-law runaway is filed as its own issue. If it is ever damped —
sub-linear damage in `alive`, a diminishing-returns term, anything that
widens the band between "even" and "sweep" — then this entry's central
claim ("equal power, difference elsewhere") stops being forced, and
levies could carry genuinely trading strengths instead. Re-open then.

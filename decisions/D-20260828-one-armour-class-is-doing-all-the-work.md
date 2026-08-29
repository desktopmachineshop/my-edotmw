### D-20260828 · 2026-08-28 · Accepted — the counter triangle is measured, and one armour class is doing all the work

**Decision:** D-032's counter triangle gains a committed measurement
(`tests/test_counters_are_felt.gd`). The two thirds of the triangle that
work are now **guarded**; the third that does not is **reported every run
with its numbers**, not asserted. No `.tres` is changed, and the reason is
recorded below with what a fix has to move.

**Rationale.** Playtest ticket #38's pass criterion is *"Counters are
FELT: the favoured side wins clearly, not marginally"*, and nothing in the
estate had ever measured it. #219 measured it by hand from a playtest
branch and found the triangle two-thirds real.

Reproduced independently here, 6 seeds a pairing, both sides
attack-moved onto the other's start cell, every fight resolved:

| | wins | mean margin |
|---|---|---|
| cavalry vs missile | **felt** | +0.77 (#219) |
| spearmen vs cavalry | **felt** | +0.89 (#219) |
| archers vs a LEVY | **felt** | positive |
| `gildedreach_archers` vs `stoneblood_heavy` | **0 of 6** | **−0.77** |
| `gildedreach_archers` vs `emberdeep_heavy` | **0 of 6** | **−0.63** |
| `emberdeep_archers` vs `gildedreach_sellswords` | **0 of 6** | **−0.61** |
| `thornwood_archers` vs `stoneblood_heavy` | **0 of 6** | **−0.63** |

**The structural cause, and it is not the size of the bonus.**
`armour_class` has three values and one of them is carrying everything.
`infantry` spans **thirteen shipped units from 38 HP a man
(`gravesworn_shades`) to 420 (`stoneblood_breaker`) — 11.1x** — and a
single `"infantry": 1.3` is asked to cover all of it. Against a levy that
is plenty. Against a heavy it cannot close a gap where the target already
leads on **both** axes before any bonus applies: `gildedreach_archers` is
1,320 squad HP and 133 squad DPS (173 with the bonus) against
`emberdeep_heavy`'s 2,600 and 183 **unbonused**.

That is why raising the multiplier is the wrong lever. To turn that
matchup round on the bonus alone would take roughly 2x, which would then
make archers dominant against the levies they already beat 8 of 8. **One
number cannot be right for both ends of an 11x class.**

**What a fix has to do, stated so it is not rediscovered:** split the
`infantry` class so heavy infantry is its own armour class, and then
decide **who counters the new one** — because at present nothing would.
Spearmen counter cavalry; archers counter infantry; heavy infantry, given
its own class, is uncountered until something is granted a bonus against
it. That is a roster design decision with its own measurement, not a
number change, and it is the owner's.

**Rejected alternatives:**
- *Raise the anti-infantry multiplier* (rejected on the arithmetic above
  — it breaks the half of the pairing that already works.)
- *Accept that counters are priced in RP and say so in the UI* (#219's
  own alternative; rejected as the primary answer because the RP column
  is not what a player manipulates. Selection, the n/cap readout,
  production and the army a player counts are all in SQUADS, and nothing
  in the interface prices a fight in resource points. A player who builds
  "the counter" and loses 0 of 6 is being told the triangle does not
  work. Worth revisiting only if the class split is rejected.)
- *Assert the failing pairings so the suite goes red* (rejected — pinning
  a defect in place is not a guard, and `main` already carries 22
  failures. The pairings are measured and printed every run instead, so
  the finding cannot drift unnoticed.)
- *Ship the split here* (rejected on sequencing, not on merit. It changes
  every combat outcome in the game, and four PRs in review right now rest
  on measurements taken against the current roster — D-067's re-derived
  building HP, the garrison table, and the morale coupling. Landing it
  before those would invalidate all of them at once.)

**Consequences:** the working two thirds of the triangle are guarded for
the first time, so a future roster change that breaks cavalry-beats-
missile fails immediately. The failing third is visible in every run of
the file rather than in a playtest branch. And
`test_one_armour_class_is_doing_all_the_work` asserts the 11x spread as
the thing a fix must move — **it goes red when the class is split**, which
is deliberate: whoever splits it is then required to re-measure the
anti-infantry counter and update the record.

**This is the same finding as #220 seen from the other side.** The D-072
screen (`D-20260828-the-power-budget-is-a-screen-with-a-known-blind-spot`)
flags both civs' spearmen as costing more than their levy for less power,
and excuses them because what they buy is `bonus_vs` — which V does not
price. **The roster prices counters as if they work; this file measures
them not working.** Neither is answerable alone: if `bonus_vs` is ever
given a price in V, it has to be priced at what it is measured to be
worth, and that measurement is this one.

**Measured:** `just test-unit counters_are_felt` — 5 tests, native
runtime (#223/#153). Combat is pure GDScript over a seeded RNG (D-024) and
reads no imported asset, so the runtime does not bear on these numbers.

**A fixture trap #219 already paid for and this file inherits:** an
earlier version of that sweep ordered each side to a point PAST the other,
so squads crossed, separated and walked away — it reported large margins
with nothing decided and read exactly like "fights do not resolve". Every
sweep here returns `decided` and the assertions refuse a conclusion drawn
from a fight that did not happen.

**Revisit trigger:** the class split, whenever it is taken — and it should
be taken after the siege PRs land, with `just test-unit buildings`,
`test_siege_against_a_garrison` and a fresh `just ai-ladder` re-run
against it, because all three currently rest on this roster.

---

### D-20260828 · 2026-08-28 · Accepted — D-072's screen is runnable, and every violation it finds is in its blind spot

**Decision:** D-072's power budget becomes a **committed instrument**
(`tests/test_power_budget.gd`) that computes V and V/RP from the shipped
roster and asserts D-072's two rules — **bounded by the metric's own
stated competence**. A comparison is skipped when the dearer unit buys
something D-072 says V does not price, and **every skip is printed with
what it bought**.

No `.tres` is changed. The reason is the finding.

**Rationale.** D-072 states two rules —

> - **Price buys power.** Within a role, a more expensive unit must have
>   higher **V**.
> - **No free lunch.** Within a civ, epoch and role, no unit may lead on
>   both **V** and **V/RP**.

— says epoch 1 "is built to satisfy them", and `docs/plans/fantasy-civs.md`
records the fantasy roster as "V/RP-screened". **Nothing has ever checked
either claim.** #220 ran the arithmetic by hand from a playtest branch and
found it false.

**Run mechanically against the shipped roster, the two rules flag nine
pairs. Every single one is a case where the dearer unit buys exactly one
of the things D-072 says V cannot see:**

| flagged | what the dearer unit buys |
|---|---|
| `emberdeep_bombard` over `emberdeep_ram` | `attack_range` 11.0 > 1.5 |
| `gildedreach_spearmen` over `gildedreach_levy` | `bonus_vs` |
| `gravesworn_spearmen` over `gravesworn_levy` | `bonus_vs` |
| `gravesworn_shades` over both | `move_speed` 4.8 > 3.0 |
| `thornwood_greatbow` over `thornwood_archers` | `attack_range` 9.5 > 8.0 |
| `windmarch_bowriders` over `windmarch_skirmishers` | `attack_range` 5.0 > 1.9, `move_speed` 6.2 > 4.6 |

D-072's own text: *"What V does not price, stated up front so it is not
misread as a verdict: `attack_range`, `move_speed`, `vision_range`,
`bonus_vs`, `morale`. It is a first-pass screen for line infantry and it
systematically undervalues missile and scouting units."*

So the honest reading of #220 is **not** that the roster is mispriced. It
is that **D-072's rules, applied to a roster in which specialists exist,
flag every specialist** — because a specialist's entire premium sits in
the columns V cannot see. The rules were written when a civ fielded one
line unit plus one exclusive; they do not survive a 27-unit roster where
most civs field a generalist levy AND a counter to something.

**#220's specific claim, corrected and sharpened.** The issue reports
`gravesworn_levy` leading "the roster" on both power and cost-efficiency.
That is a wider comparison than the rule makes — across civs and roles it
is comparing a levy with a siege engine, and the siege train is *expected*
to sit at the bottom on V/RP (it buys building damage, unpriced). What is
true, and is pinned by a test, is narrower and more interesting:
**within its own civ and role, `gravesworn_levy` leads both axes, and
gravesworn's own spearmen are dominated on both** — 44 RP for V 583
against 32 RP for V 665. What those 12 RP buy is `bonus_vs`.

**And that is where this meets #219.** Whether `bonus_vs` is worth its
premium is a question V cannot answer and the counter sweep can — and
#219 measures the anti-infantry counter losing squad-for-squad, 0 of 8
seeds against heavy and elite infantry. **So the roster prices counters as
if they work, and the sweep says they do not.** #219 and #220 are one
finding seen from two sides, and neither is answered by changing V.

**Rejected alternatives:**
- *Re-price `gravesworn_levy`* (rejected — cheap, numerous and fearless
  IS the gravesworn thesis (#191), so this is a civ-identity call for the
  owner, not a screen result. And the screen cannot show it is wrong:
  the comparison it fails is one the metric admits it cannot judge.)
- *Extend V to price `bonus_vs`* (rejected here, and it is the most
  likely real answer — it needs a stated exchange rate between a counter
  multiplier and raw power, which is a design decision with its own
  measurement, and #219's sweep is the evidence it would be built on.)
- *Assert the two rules unconditionally and let the suite go red*
  (rejected — nine red comparisons that are all explained by the
  metric's documented blind spot is not a signal, it is noise that
  teaches people to ignore the file. `main` already carries 22 failures
  and does not need more.)
- *Ship it as a `just` recipe rather than a test* (rejected — a recipe
  reports, a test refuses. The value here is that a FUTURE unit which is
  dearer, weaker and buys nothing unpriced fails at once.)

**Consequences:** the screen is now something anyone can run, and the
claim "V/RP-screened" is checkable rather than asserted. The test is
deliberately non-vacuous in three ways: it fails if a new archetype has
no role mapping; it fails if NO comparison is ever skipped (which would
mean the premium detection has stopped working); and it fails if the
no-free-lunch rule is never asked at all. That last one it caught on
itself — the first version asserted nothing when every group was excused
and GUT correctly reported it RISKY, which is the estate working.

**Measured:** `just test-unit power_budget` — 4 tests, 88 assertions,
seven rule-1 comparisons and four rule-2 groups reported as outside the
metric's competence, with what each bought. The full V/RP table is in
#220 and reproduced by the test on demand.

**Found on the way, and filed rather than fixed (#259):** all six civ
`.tres` files and one AI profile contain byte `0x97` — a Windows-1252
em-dash in a UTF-8 file — inside the player-facing `summary` field, so
every civ shows a `U+FFFD` replacement character in the lobby. It
surfaced as an unexplained "Unicode parsing error" repeated a dozen times
in this test's own runs, and cost a wrong diagnosis first: the file was
stripped to pure ASCII before it became clear the warning was the data.

**Revisit trigger:** when `bonus_vs` acquires a price — which #219 is the
argument for — this test's `_unpriced_premium` should stop excusing it,
and the two spearmen comparisons become real rule-1 failures that a
roster change has to answer. That is the moment to re-read this entry.

---

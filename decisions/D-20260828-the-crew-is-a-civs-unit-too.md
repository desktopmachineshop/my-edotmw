### D-20260828 · 2026-08-28 · Accepted — the crew is a civ's unit too

**Decision:** the six per-civ gatherers are shaped per civ. They were six
copies of one file — identical field for field except `id`,
`display_name`, `civ` and `model_id`.

| civ | men | rate | product | carry | hp | speed | food |
|---|---|---|---|---|---|---|---|
| gildedreach | 8 | 0.26 | 2.08 | 52 | 28 | 3.5 | 15 |
| gravesworn | 9 | 0.22 | 1.98 | 38 | 24 | 3.4 | 11 |
| stoneblood | 5 | 0.40 | 2.00 | 48 | 52 | 3.1 | 18 |
| emberdeep | 7 | 0.27 | 1.89 | 50 | 42 | 2.9 | 15 |
| thornwood | 7 | 0.26 | 1.82 | 42 | 26 | 3.9 | 13 |
| windmarch | 6 | 0.30 | 1.80 | 40 | 26 | 4.4 | 13 |

**The band is the design constraint, and it was already in the estate.**
`test_a_tree_lasts_about_a_minute_under_one_crew` pins every civ's crew
to emptying a 105-stock tree in 45–75 s **against the shipped def**, so
`squad_size × gather_rate` must stay in [1.4, 2.33]. Every shape above is
drawn inside it: 50–58 s. **The economy stays comparable and the crews
stop being one file copied six times** — which is exactly what that test
exists to protect, and it is why the shapes vary the *composition* of the
rate rather than the rate itself.

**Rationale.** `D-20260823-the-opening-is-a-crew-and-a-general` made
per-civ gatherers mandatory — a neutral `gatherers.tres` would shadow
every per-civ one, since `UnitRoster.for_civ_archetype` returns the first
match in id order — so the neutral def was deleted and six files created.
A test asserts each names its own civ. **The files exist; the numbers
were identical** (#269), and `test_the_civs_gatherers_are_actually_
different_troops` has been red on `main` saying so.

It matters because **this is the unit a player fields more of than any
other**, on screen for the whole match, and it was the one shared
archetype in the roster that was not re-shaped: `levy` already spreads
1.22x on power, `cavalry` 1.41x, `archers` 5.5 to 8.0 on reach.

Each shape is that civ's declared axis, expressed in the crew:

- **gildedreach** (economy and flexibility) — the biggest crew and the
  deepest baskets, the fastest raw rate. Its gatherers are the one place
  it should be plainly ahead.
- **gravesworn** (quantity) — the most hands, each worth least, cheapest
  to replace and the flimsiest to raid off a node.
- **stoneblood** (quality) — five of them, gathering as fast as nine of
  anybody else's, and at 52 HP the hardest crew in the game to chase off
  a seam.
- **emberdeep** (fortification) — steady and hard to shift, slowest on
  its feet.
- **thornwood** (ranged attrition) — light, quick between stands.
- **windmarch** (mobility) — the fewest hands moving fastest between
  them.

**`move_speed` is a real economic knob and not flavour**, which #269
measures without naming: gildedreach's `gather_speed 1.15` delivers only
**1.10x** over a real 240 s haul cycle, because the multiplier applies to
gathering and a haul also spends time *walking*, which it does not touch.
So a crew's speed is part of its income, and varying it is a way to give
the four knob-less civs an economic difference the `CivDef` schema cannot
currently express (#270).

**Rejected alternatives:**
- *Varying `gather_rate` alone and holding squad size at 7* (rejected —
  it changes only how fast the same crew works, and leaves every civ's
  crew the same thing on screen and the same thing to raid. Squad size is
  what a player sees and what an enemy has to kill.)
- *Letting the tree time vary between civs* (rejected — `TREE_STOCK` and
  the 45–75 s band are what make a forest mean the same thing on every
  map for every player, per D-087. A civ that emptied trees twice as fast
  would change what the terrain is worth, which is a much larger decision
  than this one.)
- *Waiting for #270's schema knobs* (rejected — those are a `CivDef`
  question and this is a `UnitDef` one. The crew can carry an identity
  today, in data, with no schema at all.)

**Consequences:** every civ's early economy now differs in shape as well
as in `gather_speed`, so opening timings differ per civ and **any
economic measurement taken before this was taken against six identical
crews**. `docs/status/renewable-economy.md` records the shipped crew as
"7 × 0.28 = 1.96 units/s with `carry_capacity` 45" and derives the farm's
1.2/s from it; the products here span 1.80–2.08, so that derivation still
holds to within ±6% and the note wants updating rather than the farm
re-deriving.

Raiding a crew now means different things against different civs, which
is the point: five stoneblood gatherers at 52 HP are a genuinely
different raid target from nine gravesworn at 24.

**Measured:** `just test-unit economy` 44 passing, `opening` 10,
`civs` 14, `unit_defs` 9 — including
`test_the_civs_gatherers_are_actually_different_troops`, one of `main`'s
22 standing failures, which this retires.

**Revisit trigger:** if `TREE_STOCK` or the 45–75 s band moves, every
product here is re-derived from the new band rather than nudged — the
band is the contract, and the shapes are drawn inside it.

---

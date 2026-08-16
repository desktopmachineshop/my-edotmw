### D-072 · 2026-08-04 · Provisional — epoch 1 in full, and the budget its numbers come from
**Decision:** Epoch 1 is specified to shipping depth as the vertical
slice. Every civ fields **four archetypes**: `founders` and `gatherers`
(neutral pool, unchanged), one shared `levy`, and **exactly one exclusive
unit that is the civ's thesis in miniature**.

**The power budget, and why it exists.** Costs are derived from a stated
exchange rate, not authored per unit, because otherwise every unit ends up
independently slightly too good:

- **DPS** = `squad_size × damage / attack_interval`
- **EHP** = `squad_size × health`
- **V** (squad power) = `sqrt(DPS × EHP)` — geometric so it stays roughly
  linear in squad size rather than quadratic
- **RP** (resource points) = `food + wood + 1.5 × (gold + stone)`

**What V does not price, stated up front so it is not misread as a
verdict:** `attack_range`, `move_speed`, `vision_range`, `bonus_vs`,
`morale`. It is a first-pass screen for line infantry and it
systematically **undervalues missile and scouting units**.

**The screen was run against the shipped roster first, and it found a
real defect.** Computed from the `.tres` as they stand:

| unit | V | RP | V/RP |
|---|---|---|---|
| legion_militia | 1064 | 75 | **14.2** |
| legion_spearmen | 802 | 100 | 8.0 |
| legion_archers | 682 | 105 | 6.5 |
| legion_heavy | **930** | **190** | 4.9 |
| northmen_militia | 883 | 40 | **22.1** |
| northmen_spearmen | 666 | 53 | 12.6 |
| northmen_skirmishers | 556 | 55 | 10.1 |
| northmen_cavalry | 656 | 98 | 6.7 |

Two things fall out, and both are arithmetic on shipped data rather than
opinion:

1. **Militia leads on both V and V/RP for both civs.** Massing militia is
   correct play, and only `bonus_vs` argues against it — which militia
   dodges by being a generalist with `bonus_vs = {}`, so it is never hard
   countered, merely un-bonused.
2. **`legion_heavy` has lower DPS than `legion_militia` (257 vs 342) and
   near-identical EHP (3360 vs 3312), at 2.5× the cost.** What it buys is
   `bonus_vs {cavalry: 1.5}` and better morale — against a Legion mirror,
   nothing; against Northmen, one of four archetypes. It is very likely
   overpriced. *Not proven*: range, morale and counters are outside the
   metric. Recorded as a finding to verify in play, not a fixed defect.

**Two rules follow, and epoch 1 is built to satisfy them:**

- **Price buys power.** Within a role, a more expensive unit must have
  higher **V**. `legion_heavy` fails this today.
- **No free lunch.** Within a civ, epoch and role, no unit may lead on
  both **V** and **V/RP**. (Largely an epoch-2+ rule; at epoch 1 only
  Legion fields two line units, and it is the test case.)

**Band for epoch-1 line units: V 550–780, V/RP 11–21.** Where a civ sits
*within* the V/RP range is its quality-versus-quantity axis — that is the
axis, expressed as one number.

| Unit | role | sz | hp | dmg | int | rng | spd | cost | V | V/RP |
|---|---|---|---|---|---|---|---|---|---|---|
| `legion_levy` | line | 30 | 78 | 7.5 | 1.0 | 1.9 | 3.3 | 55f | 726 | 13.2 |
| `legion_veterans` ★ | line | 20 | 130 | 13.0 | 1.05 | 1.8 | 3.2 | 55f 20w | **802** | 10.7 |
| `northmen_levy` | line | 40 | 55 | 5.5 | 1.0 | 1.9 | 3.8 | 34f | 696 | **20.5** |
| `northmen_raiders` ★ | spec | 24 | 50 | 7.0 | 1.0 | 1.9 | **5.2** | 30f 10w | 449 | 11.2 |
| `magyar_levy` | line | 30 | 62 | 6.0 | 1.0 | 1.9 | 3.6 | 38f | 579 | 15.2 |
| `magyar_outriders` ★ | spec | 16 | 58 | 7.0 | 1.1 | 2.0 | **6.4** | 30f 10g | 307 | 6.8 |
| `byzantine_levy` | line | 32 | 82 | 6.0 | 1.1 | 1.9 | 3.1 | 50f | 677 | 13.5 |
| `byzantine_watchmen` ★ | spec | 28 | 105 | 5.5 | 1.2 | 2.0 | 2.6 | 45f 25w | 614 | 8.8 |
| `carthaginian_levy` | line | 30 | 62 | 6.2 | 1.0 | 1.9 | 3.4 | 30f 20w | 588 | 11.8 |
| `carthaginian_tradesmen` ★ | econ | 6 | 40 | 1.0 | 2.5 | 2.0 | 3.4 | 22f | *exempt* | — |
| `chinese_levy` | line | 34 | 64 | 6.0 | 1.0 | 1.9 | 3.4 | 42f | 666 | 15.9 |
| `chinese_bowmen` ★ | spec | 26 | 52 | 8.5 | 1.6 | **6.8** | 3.0 | 35f 35w | 432 | 6.2 |

★ = the civ's exclusive archetype. All six levies sit in band; Legion's
veterans beat its levy on V (802 > 726) at lower V/RP (10.7 < 13.2), so
both rules hold.

**Specialists are exempt from the band, and each one's non-V property is
named** — this is the metric's blind spot being handled honestly rather
than by tuning numbers until they hit a target:

- `northmen_raiders` — speed 5.2 and vision 16. Buys tempo and the
  ability to reach an undefended economy.
- `magyar_outriders` — speed 6.4, vision 22, `armour_class = cavalry`.
  Buys information. The clearest case of V being the wrong lens; it is
  6.8 V/RP and still correct.
- `byzantine_watchmen` — **105 EHP per soldier, the highest in epoch 1.**
  Under per-soldier upkeep (D-068) that is durability you do not pay a
  crowd for, which is precisely what holding ground means.
- `chinese_bowmen` — range 6.8, the only ranged unit in epoch 1. V cannot
  price not being hit back.
- `carthaginian_tradesmen` — economic; exempt entirely, like `gatherers`
  (V/RP 1.2). Higher `carry_capacity` and gold-weighted gathering.

**Horse archers take `armour_class = cavalry`, not `missile`.** They are
mounted, so spears must counter them, and D-032's triangle only works if
the class describes what beats the unit rather than what it carries.
Reach is expressed by `attack_range`, which is where it belongs.

**Per-soldier upkeep automatically taxes the quantity civs, and that is
why D-068 made it per soldier rather than per squad.** `northmen_levy`
carries 40 soldiers to Legion's 30 for comparable squad power, so it pays
33% more upkeep for the same V. Quantity's advantage is bought back over
time instead of being free — no extra knob, no special case.

**Test constraints, checked on paper before any file is written:**
`tests/test_civs.gd:93` requires each civ to field more than two
archetypes with at least one exclusive — every civ has four and exactly
one exclusive. `tests/test_civs.gd:113` requires a shared archetype to
differ across civs in `damage`, `health` and `cost_food` — `levy` differs
on all three across all six.

**Epochs 2–5, one paragraph each, deliberately no more.** E2 completes the
counter triangle per civ and lands the Northmen and Chinese signatures.
E3 adds cavalry, missile specialists and the tower/claimed-ground game,
plus Carthage's mercenary breadth. E4 adds siege and heavy horse, and the
Legion and Byzantine signatures. E5 adds scarce elite troops and the
castle tier. Numbers for these are **not** set here: they should be
derived from D-068's table after epoch 1 has been played, exactly as
epoch 1's were derived before it.

**Revisit trigger:** the first time a levy is still the correct
front-line purchase at epoch 3, the ladder is not delivering new verbs
and D-069 is wrong, not this table.

---

# D-20260828 · A guard is written in a vocabulary, and the vocabulary moves

**Status:** ACCEPTED. **Closes:** #215 (and its duplicates #202, #203,
#211, #212), #204, #208, #209. **Extends:**
D-20260818-fantasy-civs-supersede-the-historical-frame (#191, which
landed the data), D-20260823-the-opening-is-a-crew-and-a-general (the
per-civ gatherer rule), D-20260819-a-formation-is-a-fighting-style (the
grants), D-095, D-20260818-dev-work-is-admitted-against-a-host-budget.
**Sits on:** D-20260827-a-buildings-hp-is-one-knob-and-the-rule-needs-two
(#152 / PR #222), which re-derived D-067 and is the other half of this
red.

## The fault

`just test-unit` was red on `main` for a week and reported by five
separate workers (#202, #203, #211, #212, #215) as five overlapping
failure lists. Deduped, it is **eight** real failures — every one of
them a guard that was correct when written and was never re-read after
#191 changed what it depended on.

Nothing was broken by a code change. The roster moved underneath the
tests.

## The eight, and what each one actually was

| test | what it was |
|---|---|
| `test_shipped_roster_has_a_real_counter_triangle` | asks for `militia`; the archetype is `levy` since #191 |
| `test_the_opening_general_outfights_basic_infantry` | same word, so `assert_not_null` fired first and **all four of its claims went unasserted for every civ** |
| `test_every_armed_unit_can_reach_an_adjacent_cell` | `emberdeep_ram` ships `attack_range 1.5` against a hex width of 1.73 — a **live gameplay bug** |
| `test_granted_formations_exist_and_are_not_globally_offered` | #191 dropped every `formations` grant, so `shield_wall` and `testudo` shipped reachable by nobody |
| `test_the_civs_gatherers_are_actually_different_troops` | six per-civ files, one stat block |
| `test_every_building_s_train_list_fits_at_the_smallest_window` | measures the 14-archetype UNION; a player is shown a per-civ list |
| `test_every_recipe_that_runs_real_work_declares_a_class` | `gen-formation-icons` runs Godot twice with no host slot (#208) |
| `test_every_compose_invocation_is_scoped_to_this_instance` | `--name` matched a **Python** argument (#209) |

Only two of the eight are a test being wrong. Two are live defects
(the ram, the ungated recipe), three are shipped rules that quietly
stopped existing, and one is a guard that was both failing wrongly
*and* no longer measuring the thing it protects.

## The decisions

**The ram reaches.** `attack_range 1.5 -> 1.9`, the roster's own melee
reach and the value every other melee unit carries. The design plan
(`docs/plans/fantasy-civs.md`) specifies 1.5 and the plan is what is
wrong: a hex is 1.73 across, so 1.5 floors to a radius of **zero
cells** and a ram could only ever attack its own cell. 1.9 keeps it the
shortest reach in the roster — "it fights where it already is" — while
letting it fight at all. Note the **schema default is also 1.5** and is
therefore a value that cannot work; left alone here because changing it
moves fixtures across the suite, and filed separately.

**The specials are granted again**, by the rule D-20260819 already
wrote — *spearmen know the wall; the fortification civ's heavy knows
the testudo* — transplanted onto the roster #191 shipped, with no
script naming a civ:

- `shield_wall` -> `gildedreach_spearmen` (Pike Serjeants),
  `gravesworn_spearmen` (Bone Pikes), `emberdeep_heavy` (**Shieldwall
  Vanguard**, whose design text is *"interlocked tower shields ... the
  formation IS the silhouette"*)
- `testudo` -> `stoneblood_heavy`

A grant is **opt-in only** — it adds a button in the client and an
allowance in the server's validation (`server.gd`), and changes no
default shape. So it does not disturb PR #222's re-derived D-067
numbers, which was checked before choosing this over editing
`formation_shape`.

**The six crews are actually six crews.** Each is differentiated along
its own civ's stated axis, with **steady-state throughput deliberately
held in a tight band** — this makes the crews different, it does not
re-balance six economies:

| civ | sz | hp | carry | rate | food | spd | tree | food/head | throughput |
|---|---|---|---|---|---|---|---|---|---|
| stoneblood (quality) | 5 | 48 | 48 | 0.40 | 16 | 3.2 | 52.5 s | 3.20 | +1.1% |
| gravesworn (quantity) | 10 | 22 | 40 | 0.21 | 14 | 3.0 | 50.0 s | 1.40 | -0.9% |
| thornwood (reference) | 7 | 26 | 45 | 0.29 | 14 | 3.8 | 51.7 s | 2.00 | +4.5% |
| windmarch (mobility) | 6 | 32 | 60 | 0.28 | 14 | 4.6 | 62.5 s | 2.33 | -4.6% |
| gildedreach (economy) | 7 | 28 | 54 | 0.30 | 15 | 3.5 | 50.0 s | 2.14 | **+9.5%** |
| emberdeep (siege/slow) | 8 | 36 | 50 | 0.26 | 15 | 2.9 | 50.5 s | 1.88 | +3.0% |

Throughput is `carry / (fill + travel)` over a representative 10-unit
haul, against a 1.569/s baseline for the identical crew that shipped.
Gildedreach is best on purpose — economy is its stated axis and the one
identity that should show up in a crew. Both shipped bands are
respected rather than discovered afterwards: `cost_food / squad_size`
stays inside `(1.0, 6.0)` (`test_unit_defs`) and
`TREE_STOCK / (squad_size * gather_rate)` inside `[45, 75] s`
(`test_economy`) — a crew outside that band changes what every forest
on the map means. Gravesworn's `rout_threshold 0` /
`morale_loss_per_casualty 0` are untouched: that civ is fearless by
identity and `test_fearless.gd` pins it.

**The HUD guard measures what a player can reach.** It counted
`def.produces.size()` — 14 since #191 made `barracks.produces` the
union of every civ's archetypes. `Client._show_train_chips` resolves
each archetype through `UnitRoster.for_civ_archetype` and drops what
the civ does not field, so the union is a list nobody is ever shown. It
now measures the **worst per-civ resolved list** (6 — barracks as
gildedreach, against a capacity of 6 at 1600x900) and names the civ
when it fails. This was the important one: the old form failed for a
reason that was not a bug **and had stopped being able to catch the
real one**, which is D-20260817-selection-bar-three-columns' *"a cap
that hides a CONTROL"*.

**The isolation guard asks about containers.** `--name` is not a
docker-only token: `art/attach_kit.py --name "{{TARGET}}"` passes a
`.blend` id. The scan is per-line and only on lines that invoke
`docker`. D-095's rule is unweakened — verified by putting
`--name edotmw-lobby` on a real compose line and watching it go red.

**`gen-formation-icons` takes a slot** (`medium`, four lines copied
from `gen-terrain-shot`), closing the hole #208 describes: an ungated
recipe both starves the machine and hides itself from
`just host-status`.

## The nerve clause, which is the one that needed a real decision

`test_the_opening_general_outfights_basic_infantry` asserts a general
*holds his nerve longer* than his levy. Renaming `militia` to `levy`
un-hid all four claims, and three hold across the roster. The fourth
cannot: **gravesworn's general and levy both have `rout_threshold 0`**,
because that civ never routs at all. A strict `<` there would force one
of the two to become routable — breaking a shipped civ identity to
satisfy a fixture.

So the claim is stated in the only form that is true of the whole
roster: **never worse, and strictly better wherever nerve exists.**
Both halves were observed to fail (a gravesworn general at 5.0 against
his levy's 0.0; an emberdeep general at 25.0 against his levy's 25.0).

## The rule

> **A guard is written in the vocabulary of its day.** `militia`,
> `produces`, `--name` and "spearmen know the wall" were all correct
> when written. Each stopped meaning what it said without anything
> failing at the time, and the failure surfaced later as a red test
> whose message pointed at the wrong thing.

Two specific shapes worth naming, because both nearly got "fixed" the
cheap way here:

- **A red test is not evidence that the test is wrong.** Six of these
  eight were the guard telling the truth. The temptation on a week-old
  red baseline is to relax assertions until it passes, which is how a
  guard stops guarding.
- **A guard failing for the wrong reason has usually also stopped
  catching the right one.** The train-list test is the clean example:
  it failed on a union nobody sees, and would not have failed when a
  seventh gildedreach unit became unreachable. Fixing *why it is red*
  and fixing *what it measures* were two different edits.

## What is not claimed

**Balance is not measured.** The gatherer numbers keep throughput
inside a band and honour both shipped guards; whether the six crews
*feel* different is a playtest question. Every `just ai-ladder` figure
taken before this is measured against identical crews, no formation
specials and a ram that could not attack — quote a ladder result with
its cap, its squad count, and now which side of this it came from.

## Revisit trigger

A seventh archetype fielded by gildedreach, or any civ reaching seven
trainables, takes the chip strip past its capacity at 1600x900 — the
train-list guard now fails at exactly that point and names the civ.
The answer at that point is the strip's geometry, not a bigger cap.

### D-20260828 · 2026-08-28 · Accepted — a civ must be able to afford its own opening

**Decision:** `gravesworn.starting_wood` 140 → **150**, and a standing rule
with a test behind it: **every civ's opening bank must cover the cost of
the building its opening requires**, resolved through the defs rather than
against a literal.

**Rationale.** Gravesworn shipped 140 starting wood against a 150-wood
town centre (#247, #275). Under
`D-20260823-the-opening-is-a-crew-and-a-general` founding that hall *is*
the whole opening, so a Gravesworn player began ten wood short of the only
building they are allowed to raise.

**And there is no way out by playing.** With no base there is no
drop-off — `Economy._try_unload` credits nothing when `_nearest_drop_off`
finds none, and the only two drop-offs in the roster are the town centre
itself and the storehouse. So the wallet cannot rise by gathering either.
Measured over three 600 s ladder matches: `buildings=0 first_attack=-1.0
peak_wood=140`, three times out of three, with `peak_stockpile=440`
exactly equal to the untouched opening bank. **A shipped civ that could
not open.**

A human could work out the escape — a 60-wood storehouse is a drop-off,
so 140 → storehouse → gather 70 → hall. Nothing hints at it, and no
automated opponent takes it: `AiPlayer._found_town_hall` asks for the
town centre only, `_raise_buildings` skips it and needs two gatherer
squads when a player opens with one, and `bot_client._raise_buildings`
returns `"no hall"` while it owns no buildings.

**Why 150 and not more.** The opening banks express identity — gravesworn
has the most food (280) and the least wood, which is a real statement
about a civ of cheap food-costed hordes. 150 is the smallest number that
makes the civ playable while keeping that ordering intact: it stays
strictly the poorest in wood. There is no functional cost to the zero
margin, because a gatherer costs 14 food and nothing else, so a player who
founds with nothing left can still produce a crew and gather.

**The number is not the fix; the rule is.** A value that exactly equals a
cost is only safe because something now checks it, and the check resolves
the opening building as *the one that spends its builder*
(`BuildingDef.consumes_builder`, which `test_exactly_one_shipped_building_
costs_its_builder` already pins at exactly one) and reads its costs off
that def. So a change to the hall's price, or a seventh civ, is covered
the day it is written.

**Why nothing caught it, which is the part worth carrying.** There is
already a test called **`test_every_civ_can_actually_open`** — and it
checks that a civ HAS a settler and a general. The name reads as covering
this and does not. The missing check is a cross-reference between
`CivDef.starting_*` and `BuildingDef.cost_*` that no single file owns, and
it went a whole roster rewrite unnoticed behind a reassuring label. This
project's most-repeated defect shape, wearing the name of the test that
should have caught it.

**Rejected alternatives:**
- *Raising it to 160, matching the next-poorest civs* (rejected — it
  erases the one thing gravesworn's opening bank says, and buys nothing:
  the margin is not functionally used, because the next purchase after
  the hall needs a gathering trip either way.)
- *Lowering the town centre's cost* (rejected — it is shared by all six
  civs and priced against the opening's pacing; moving it to
  accommodate one civ's bank is the tail wagging the dog.)
- *Treating 140 as intentional, with the storehouse as gravesworn's
  authored opening* (rejected, though it is the one reading under which
  the data is not a slip: nothing documents it, no AI or bot can take it,
  and `D-20260823` states the opening as founding the hall. If it ever
  becomes intentional it needs the AI taught, and it is a decision, not
  a `.tres` value nobody mentioned.)

**Consequences:** gravesworn plays. Measured on `just ai-ladder 2 200 6`
after the change: `civ=gravesworn buildings=2 squads_peak=17
workers_peak=16 attacks=5 first_attack=146.7 peak_wood=300` — it opened,
built, and fought, where it had previously never built anything in any
match. **`afford_refusals=0` for every seat**, which is the specific
deadlock this removes.

Any ladder or load-test number taken before this was measured with one of
six civs unable to participate.

**A residual, and it is not this:** in the same run three seats still
reported `buildings=0`, and the server logged *"4 spawn points"* for six
AI. That is **#276** — `--lobby=0` builds the world before it seats the
AI, so seats past the map's authored `player_slots` share another
player's start. Independent of this, already filed, and worth knowing
before reading a ladder result with more AI than the map has starts.

**Revisit trigger:** if the opening ever stops being "found one building",
this rule needs restating rather than extending — it currently assumes a
single `consumes_builder` def, which is the same assumption
`test_exactly_one_shipped_building_costs_its_builder` makes and would
fail loudly on.

---

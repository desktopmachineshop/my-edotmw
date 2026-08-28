### D-20260828 · 2026-08-28 · Accepted — four more knobs, and every one has a caller

**Decision:** `CivDef` gains three fields and one widened range, each
answering a civ identity the schema could not express (#270):

| field | civ line it serves | applied through | read by |
|---|---|---|---|
| `build_speed` | *"slow, secure, stone-heavy"* | `construction_time(base)` | `server._handle_order_build` |
| `march_speed` | *"low infrastructure; settles late and lightly"* | `march_rate(base)` | `SquadSim.add_squad` |
| `gather_speed_by_kind` | *"forage-led, wood-rich, gold-poor"* | `gather_rate(base, kind)` | `Economy._gather` |
| `squad_cap_bonus` **may be negative** | *"steady; strong from few well-held sites"* | `squad_cap(base)`, floored at 1 | `MatchState.squad_cap_for` |

All additive with neutral defaults. An empty `gather_speed_by_kind` means
the scalar applies to all four resources, which is what every civ did
before and what five of six still do — **five of the six read exactly as
they did.** Recorded in D-010's schema log.

**Rationale.** #270 measured that the roster already expresses four of
the six identities through unit shape — quality by mean power, siege by
reach and building damage, attrition by reach on fast legs, mobility by
speed — and that what it *cannot* express is the economic and structural
half. Each of the four is one line in
`docs/plans/fantasy-civs.md` that no existing field could say:

- **A quality civ is FEWER and better.** `squad_cap_bonus` only
  meaningfully went up, so such a civ fielded the same forty squads as
  everyone and merely paid more per squad. The floor at one squad is
  because a cap of zero is a civ that cannot play and is one data entry
  away.
- **`production_speed` divides `UnitDef.build_time` only**, so it touches
  units alone and a fortification civ could not fortify faster or
  cheaper than anybody else.
- **"Wood-rich, gold-poor" is not a smaller number, it is four numbers.**
  One scalar over all four resources cannot say it.
- **A mobility identity living in four `.tres` move speeds** can make
  individual units quick; it cannot say "this host redeploys faster than
  it fights", which is a claim about the army.

**The trap this decision is mostly about.** `CivDef`'s first three fields
shipped **read by nothing for a whole milestone** — the fourth instance
of this project's declared-and-unread class, fixed only in #158, with two
of six civ identities depending on them. #270 names the requirement
plainly, and it is met here: every field has an applied function on the
schema, a named caller, and a test that drives **the thing that runs in a
match** rather than the arithmetic.

That last clause is the one with teeth. `tests/test_civ_knobs.gd` records
why: when all three original knobs were unwired, **both production
behaviour tests stayed green**, because they called `BuildingSim.enqueue`
themselves. Arithmetic tests cannot see a missing caller. So the march
knob is driven through `SquadSim.add_squad` and a real 4-second race, the
build knob through `BuildingSim.advance_construction` with the time
banked as the server banks it, and a generalised caller scan asserts each
accessor is applied somewhere outside `CivDef`.

**Where each is applied, and why there.**

- **`construction_time` is resolved by the SERVER and banked on the
  building as real seconds**, exactly as `BuildingSim.enqueue` already
  takes its production time — and for the same reason its comment gives:
  construction progress is replicated, so a multiplier applied per tick
  would make the bar a client draws disagree with the server.
- **`march_rate` is applied once in `add_squad`**, where `SquadSim`
  already latches a squad's cells-per-second, so an army-wide multiplier
  costs nothing per tick.
- **`gather_rate` takes the node's kind from the one caller that already
  has it**, so no lookup is added anywhere.

**Rejected alternatives:**
- *A `no_build_radius` territory knob for the quality civ* (#270 offers
  it as an alternative to the cap penalty; rejected as the FIRST answer
  because "fields fewer squads" is the identity line and the cap says it
  directly, while a territory knob says something adjacent. It remains
  available and needs no schema change to `CivDef` to be added later.)
- *A building COST multiplier as well as a speed one* (deferred — cost
  and speed are different levers and a fortification civ that gets both
  is two knobs' worth of identity from one line. Speed first; cost when
  something asks for it.)
- *Folding `gather_speed` into the table and deleting the scalar*
  (rejected — it would force all six civs to carry four numbers to say
  what one says, and the scalar is the honest default for a civ with no
  per-resource opinion.)

**Consequences:** four civs now carry a mechanical difference they did
not have, so **any ladder or economic measurement taken before this was
taken against four civs that differed only in roster shape.** The
shipped values are deliberately modest (a 6-squad cap penalty, ±12–25%
multipliers) because #270 is explicitly *not* a balance complaint and
this is a schema change with four demonstrations, not a balance pass.
They are the first numbers, not the right ones, and `just ai-ladder` is
what will say — quoted with its cap, as ever.

**Measured:** `just test-unit civ_knobs_reach` — 11 tests. A fixture
lesson worth keeping: the march race first ran 120 ticks and **both
squads arrived**, so it saturated at 20 vs 20 and reported "the knob has
no caller" about a knob that worked. A race has to be measured before the
finish line, and the test now asserts it did not saturate.

**Revisit trigger:** if a fifth knob is ever wanted, check first whether
it is a `CivDef` field at all — two of these four (the resource table and
the march multiplier) wanted a *shape* the schema did not have rather
than another scalar, and the next one may want a shape too.

---

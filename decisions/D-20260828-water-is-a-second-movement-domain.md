# D-20260828 · Water is a second movement domain

**Date:** 2026-08-28
**Status:** Accepted (the owner's directive, #301). Design only — no code.
**Issue:** #301
**Design doc:** `docs/plans/naval.md`
**Supersedes:** `D-20260828-a-map-a-player-can-pick-is-a-map-an-army-can-cross`
(#280 offered "retire the preset or write the naval decision"; the owner
chose naval, so this is that decision and the retirement is no longer the
answer — see "What happens to #280").

## Decision

**Water becomes a third value of `SquadSim._tier`**, which D-076 already
established as "which layer of the world a squad is on". The field's
meaning is widened from *tier* to **movement domain**, with three
mutually exclusive values:

| value | domain | passability source |
|---|---|---|
| `DOMAIN_GROUND` (0) | ground | `_passable` (terrain minus living buildings) |
| `DOMAIN_WALL_TOP` (1) | wall-top | `BuildingSim.is_walkable_top_cell` (D-076) |
| `DOMAIN_WATER` (2) | water | `_navigable` |

**`navigable[i] = 1 iff elevation(i) < sea_level`** — a separate
`PackedByteArray`, derived on both sides from the replicated
`MapSettings` numbers (D-049), so nothing new crosses the wire.

**A third `FlowField` layer with its OWN cell budget**
(`_fields_water`, `water_field_cells_per_tick`), never sharing D-040's
counter or D-076's. `FlowField` itself is not modified; it is driven a
third time.

**A unit's domain is a property of the UNIT, not of the order.**
`UnitDef.movement_domain` (`land` default, `water`) decides it; a
destination in the wrong domain is CORRECTED to the nearest cell in the
right one, never refused. **No new movement opcode** — D-076 added a
whole tier with no wire change to orders and this keeps that property.

**Melee cannot cross a domain boundary; ranged can.**
`Combat._can_reach_tier` generalises to `_can_reach_domain` and gains
nothing else. Naval combat is D-024 unchanged: ships are squads,
squad-level, stochastic, server-only, same bucket map, same
`TorusSpace.disk_offsets`.

## Rationale

### Why the existing tier machinery, rather than something new

D-076 built, and this project has already paid for, every hard part:
a per-squad layer value with its own passability, a second flow-field
layer with a separate budget, an explicit teleporting hop that keeps
D-006 clause 1 intact, and a targeting rule about which layers reach
which. Water needs exactly that list.

**Driving it a third time is cheaper than generalising it**, and D-076
already made that call for the same reason it applies here — its own
rejected alternatives include *"a unified multi-tier BFS graph: rejected
for cost/complexity; two independently-solved layers plus an explicit hop
is far cheaper to reason about and to budget."* Three is not different
from two in kind.

### Why one field with three values, not two orthogonal axes

A domain and a tier could be separate per-squad values. They should not
be, because **the three states are mutually exclusive by construction**:
a ship is never on a wall-top, and a land squad is never on open water
except as cargo — which is not in the world at all (see the cargo
decision). Two fields would make representable a combination that can
never occur, and every reader would then have to know it cannot.

The field keeps the name `_tier` so D-076's call sites are not churned;
its doc comment and its constants say *domain*.

### Why navigability is its own array

`_passable` is read by a dozen callers that all mean "may a land squad
stand here" — soldier clamping (#97), separation, building placement,
`_approachable`, `terrain_knowledge`. Making it tri-state would change
the meaning under every one of them silently, which is precisely the
shape of defect this project keeps finding. A second array is a few
kilobytes and changes nothing that already works.

**And it is derived, not replicated**, for the reason `terrain_passable`
already is (D-20260818's soldier clamp): both sides compute it from the
identical `MapSettings` numbers, so they cannot disagree, and a test
should assert the client's array is byte-identical to the server's
exactly as one already does for land.

### Why the unit decides its domain and the order does not

D-076 infers the target tier from the destination cell, which is what let
it avoid a wire change. Naval cannot reuse that rule: **a shore cell is
simultaneously legal land and adjacent to legal water**, so the cell
alone genuinely cannot say what was meant.

Making the UNIT decide keeps the wire unchanged anyway, and it makes the
ambiguous case impossible rather than adjudicated. The correction
behaviour — nearest cell in the right domain — follows `_approachable`,
which D-20260818 deliberately left omniscient precisely because it
corrects a destination and can never refuse an order.

### Why all water is navigable in v1

A draft rule (deep-only hulls, shallow-only hulls) doubles the field
count and the transition surface. Nothing in the roster or the AI plan
asks for it. Deep water stays what it is today: a biome and an
appearance. Named as a revisit trigger rather than built.

### Why melee cannot cross a shoreline

It is the same sentence D-076 already enforces between ground and
wall-top, and it is what makes a coast mean something: an army caught on
a beach by a warship is shot and cannot answer unless it brought
missiles. It also gives Emberdeep's Ember Monitor its identity —
outranging a shore tower — with no civ-specific branch anywhere, which is
D-047's requirement.

## Rejected alternatives

- **A unified graph over land and water with transition edges.** The
  clean computer-science answer, and the wrong engineering one for the
  same reasons D-076 rejected it: `FlowField.expand()` stays untouched,
  and two budgets you can reason about beat one you cannot.
- **Water as a flag on `_passable` (tri-state).** Rejected above — it
  changes the meaning of an array a dozen correct callers already read.
- **Amphibious units that walk into the sea.** Attractive for Stoneblood
  ("giants wade") and rejected: a squad that belongs to two domains makes
  every domain check a question instead of a lookup, and the same
  fantasy is served by the Stonewright Barge.
- **A fourth `armour_class` for ships.** The counter triangle is D-032's
  and shared with every land unit; adding to it re-balances the whole
  roster as a side effect. Ships use the existing three — a gunned hull
  is `missile`, a ramming hull is `infantry`.
- **Shallow/deep draft.** See above; revisit trigger.

## Consequences

- **Two schema additions** (D-010 log): `UnitDef.movement_domain` and
  `UnitDef.transport_capacity` (the latter belongs to the cargo
  decision but is one edit).
- **`islands` becomes the map this feature exists for**, and it is
  65–71% water — so the naval field layer solves over roughly **twice**
  the area the ground layer does there. **D-076's 1,024 cells/tick must
  not be copied**; the budget is a measurement, taken the way D-076 took
  the wall layer's and quoted with its squad count.
- **It lands on a tick that is already over budget at scale** — #105 has
  the 1,000-squad worst tick at 204.5 ms against D-020's 100 ms. This
  adds a third layer. `just profile` should sweep a water map before the
  AI stage lands, and the number goes in that stage's exit criteria.
- **`D-20260827-every-start-shares-one-landmass` becomes wrong for naval
  maps.** "One walkable component" is the right rule only while armies
  cannot cross water; it must become "one *reachable* component, where
  reachable includes water for a side that can cross it". That is the
  last stage of the cut-list and it is what re-enables `islands`.
- **Ships render at sea level, not on the terrain surface.** The one
  render change that is not free — the sampler would otherwise put a hull
  on the seabed.
- **Nothing about fog, curves or replication changes.** Ships are squads
  (D-003, D-004, D-025 extend, never duplicate).

## What happens to #280

`D-20260828-a-map-a-player-can-pick-is-a-map-an-army-can-cross` measured
that `islands` cannot host a match — 29–35% walkable across 12–268
components, **failing at two seats** — and retired it from the lobby. It
named two exits and the owner has taken the other one: build the game
that map needs.

**Its measurement stands and is the reason this feature is worth
building.** What is superseded is its conclusion. The
`TerrainPreset.playable` mechanism survives as the switch the last stage
flips.

**One question left for the owner**, one bool either way: whether
`islands` is offered *while* naval is built — a period in which it is
still a map that cannot host a match — or stays hidden until the water
graph reaches spawn placement. Recommendation in `docs/plans/naval.md`
§9: **hidden until then**, so it becomes visible on the day it becomes
playable.

## Revisit trigger

- **Draft.** The first ship or map that wants shallow water to mean
  something reopens "all water is navigable".
- **The measured budget.** If the naval layer's cell budget cannot be set
  without pushing the worst tick past D-020's 100 ms on a water map, that
  is not a tuning problem — it is this decision's own revisit, the same
  way D-040 was D-038's.
- **A third consumer of the domain idea** (air, tunnels, a second
  wall-top network). Three drove layers is fine; a fourth is where the
  unified graph rejected above earns its cost.

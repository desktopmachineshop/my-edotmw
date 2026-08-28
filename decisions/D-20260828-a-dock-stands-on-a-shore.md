# D-20260828 · A dock stands on a shore, and ships appear in the water

**Date:** 2026-08-28
**Status:** Accepted (the owner's directive, #301). Design only — no code.
**Issue:** #301, which names *"a dock/shipyard building family (shore
placement — a new placement rule) with per-civ identity"*.
**Design doc:** `docs/plans/naval.md` §4
**Builds on:** `D-20260828-water-is-a-second-movement-domain`

## Decision

**A dock must stand on a shore cell** — a passable LAND cell with at
least one navigable neighbour. `BuildingDef.needs_shore` (bool, default
`false`) adds one refusal to `server._build_refusal`, beside the ones
that already exist for water, steep ground, resource nodes and occupied
cells.

**Its water cell is per-INSTANCE**, chosen at placement from the
navigable neighbours and stored on `BuildingSim` exactly as the access
tower's `access_direction` is. Ships appear there; transports wait there
to be loaded.

**Ships spawn into water**, through the naval sibling of
`SquadSim._spawn_cell_near` — the same nearest-first `disk_offsets` walk,
the same determinism argument, over `_navigable` instead of `_passable`.

**One `dock` def serves all six civs.** It `produces` the ARCHETYPES
`transport` and `warship`; the server resolves each against the acting
player's civ (D-047), which is how one `barracks` already fields six
civs' troops.

## Rationale

### Why the water cell cannot live on the def

This is D-076's argument, reused because the situation is identical. Its
own entry says it plainly for the access tower: *"a def is one resource
per archetype, so a door facing can't live there without every tower
sharing one facing."*

A dock's water side is chosen by where it was built. Putting it on
`BuildingDef` would give every dock on the map the same water direction —
which on a coastline that bends is wrong for most of them immediately.
Per-instance on `BuildingSim`, like `_facing`.

### Why one dock def and not six

The strong pull here is to mirror #206's stables/forges — a per-civ
building family. **That would be the wrong lesson to take from it.**

`barracks` is one def and it fields six civs' troops, because `produces`
lists archetypes and D-047's resolution does the rest. That mechanism is
already the thing that makes civs data. Six dock defs would be six copies
of one building differing only in name, each needing its own placement
rule, cost table and upgrade chain kept in step.

**Per-civ dock IDENTITY is naming and art**, and it belongs with #206's
tree — a Gravesworn bone-yard and an Emberdeep sea-gate are the same
building with different words and a different model, exactly as the six
civs' levies are the same archetype with different stat blocks.

A `shipyard` upgrade through the existing `upgrade_from` (as `wall_tower`
upgrades) is the natural home for naval techs when #206 lands. **Not in
this cut**, so that the tree's design is not pre-empted by a building
placed before it.

### Why a shore rule is genuinely new, and small

Every existing placement refusal asks about the cell itself: is it
passable, does it hold a node, does a building already stand there, is it
inside an enemy's claim. **None asks what a cell is NEXT to.** A shore
test is one `disk_offsets(1)` walk over `_navigable` — the cheapest
possible new predicate, and it reuses the table the standing rule already
insists on rather than calling `distance()`.

It also gives `needs_shore` a second, later use for free: any structure
that must touch water (a sea wall, a fish trap, a lighthouse) asks the
same question.

### Why ships spawn in water rather than at the dock's own cell

`_spawn_cell_near` walks land and would put a hull on the quay. The naval
version is the same function over the other array — and it inherits
`D-20260821-a-recruit-steps-out-the-near-door` for free, which matters
more at a dock than on land: a ship that appeared on the landward side of
a peninsula would have to sail around it.

## Rejected alternatives

- **A dock built ON a water cell.** Physically the more obvious model,
  and it drags in everything the land version avoids: `_navigable` needs
  building subtraction on day one, the builder has to reach a cell it
  cannot stand on, and `_passable`'s occupied-cell stamp does not apply.
  A land building with a water side is the cheap shape and reads the same
  on screen.
- **Six per-civ dock defs.** See above — it copies #206's *form* while
  discarding D-047's *mechanism*.
- **Any shore cell as an embark point, no dock required.** Then the dock
  is decorative, and there is no structure to raid, blockade or lose. The
  asymmetric rule in `D-20260828-a-carried-squad-is-cargo` — load at a
  dock, land anywhere — depends on the dock being the thing you must
  build.
- **Auto-placing the water cell as "whichever neighbour faces the most
  open sea".** A better rule and an unnecessary one for v1; the
  placement facing the player already chose is available, and a
  cleverer default can be added without changing the stored shape.

## Consequences

- **One schema addition** (D-010 log): `BuildingDef.needs_shore`.
- **`BuildingSim` gains a per-instance water cell**, alongside `_facing`
  and `_rally` — the same append-in-`add_building` shape, which is the
  one place every parallel array is kept in step.
- **A dock is a raidable, blockadeable objective.** It is the only way
  an army leaves an island, so it is worth attacking — which is a
  gameplay consequence, not just a placement rule, and it is the reason
  the asymmetric embark rule works.
- **`no_build_radius` and footprint interact with a coastline.** A dock
  claiming a settlement-sized radius would make a narrow isthmus
  unbuildable; its radius should be small and the shipped number is a
  measurement on a real coastline, not a copy of the barracks'.
- **The AI must want one.** A dock nothing builds is D-076's wall system
  again; the trigger and its gates are in `docs/plans/naval.md` §6.

## Revisit trigger

- **A structure that must stand ON water.** The moment one exists,
  `_navigable` needs the building subtraction this decision deliberately
  avoids, and the "land building with a water side" model stops being
  sufficient.
- **#206's tree landing.** The `shipyard` upgrade and per-civ dock
  naming are deliberately deferred to it; when it lands, this entry's
  "one def, six civs" is the thing to re-read before adding a second.
- **A map with no coastline at all.** `plains` at some seeds is nearly
  landless-water-free; a dock that cannot be placed anywhere should
  degrade to "this civ has no navy this match" rather than to an AI
  spinning on an impossible build — the #217 shape, and worth checking
  when the AI stage lands.

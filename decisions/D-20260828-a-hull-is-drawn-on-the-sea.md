### D-20260828 · Accepted — a hull is drawn ON the sea, not on the seabed

**Decision:** `Formation.soldier_transforms_sampled` takes a
`water_height`. NAN — every caller that has ever existed — means "not a
ship" and nothing changes. A number means the men of this squad derive at
exactly that height, and the LAND passability clamp (#97) is skipped for
them. `ClientState` supplies it from `tier_of(squad) == DOMAIN_WATER`,
which already crosses the wire as SQUAD_INFO's tier byte, so **nothing
new is replicated**.

Naval stage 8 of #301 (`docs/plans/naval.md` §6.4 and §7 row 8:
"ship height at sea level; minimap check; selection over water", done
when there is "a rendered frame with ships on water, looked at").

---

**Two thirds of it was already true, and that is worth saying first.**

`TerrainGen.build_fields` clamps every vertex of a water cell up to
`sea_level` before scaling (`clamped[i] = maxf(e, sea_level)`, read by
both the corner mean and the centre pillow), so the drawn sea is FLAT and
a hull in open water lands at the right height through the ordinary
ground sampler with no special case at all. The plan's §6.4 expected
`PrimitiveUnit` to need a domain-aware height and it does not: the
sampler was already right everywhere the sea is only sea.

That is now pinned by a test rather than left to be rediscovered, so a
future change that un-clamps those vertices fails next to this reason
instead of shipping as ships in the seabed.

**What was NOT already true is the SHORE.** A water cell that shares
corners with land takes their heights, which is exactly what makes the
coastline a smooth beach rather than a step — and it lifts a hull out of
the sea as it closes with the land. Measured with `--seabed=1` on the
shot below: the inshore hull derives at **1.120..1.175** where the plane
is **1.120**, against **1.120..1.120** with this change. About a tenth of
a soldier's height, on the cells where every landing in the game happens.

**Why the passability clamp is skipped with it.** That array describes
LAND. A hull overhanging a shoal is not standing on illegal ground; it is
floating over it, and clamping would drag the ship's men back toward
their own centre for a reason that does not exist at sea.

## Consequences

- **The plane is `sea_level * height_scale`, derived on the client from
  the replicated `MapSettings`** — the same product `build_fields`
  clamps with, one expression, rather than a constant that would drift
  the moment a preset moved.
- **`ClientState.DOMAIN_*` ALIAS `SquadSim`'s constants.** They ride the
  tier byte, so the two sides agreeing is a wire obligation, and two
  literals free to drift is the defect family this project keeps finding.
  A source-scanning test asserts the alias, because a copy with the right
  value passes every value comparison there is.
- **Selection needed nothing, and that is a finding rather than an
  omission.** `_stamp_selection_discs` stamps from the derived man
  transforms, so a ship's discs are on the plane because its men are.
  `SelectionPick` ranks by screen distance over drawn geometry. Both
  asserted rather than assumed.
- **The minimap needed nothing either.** `squad_marks` reads
  `composition`, where the owner lives (D-20260817), so a ship is painted
  like any squad. Also asserted.
- **`soldier_transforms` — the full-detail entry point — is deliberately
  left alone.** It takes no surface field, so a ship derived through it
  would fall back to the sampler; its only caller is `derive_all`'s cost
  metric, and the renderer uses the LOD path. Named here so that the next
  reader finds a decision rather than an oversight.

## The instrument, and what it cannot show

`just gen-naval-shot` frames the busiest piece of coast on the map with
two hulls — one against the beach, one in open water — and a land squad
ashore. **Look at `artifacts/naval-godot.png`**;
`docs/playtest/p40-naval-hulls-on-water.png` is the shipped copy.

It exists because every other rendered instrument frames somewhere a hull
cannot be: `gen-terrain-shot` prefers a mountain and draws no units,
`gen-model-preview` uses a studio plane with no sea, `gen-forest-preview`
frames a wood, and `test-client` aims at a spawn — walkable ground by
construction. Same rule as D-097's cliffs and D-108's forests: when a
rendered check has to see something specific, frame it on purpose.

**And the honest limit: the shore lift is not visible in it.** 0.055
world units on a hull 0.6 thick, seen from a dozen units away, is a
number and not a picture — `--seabed=1` prints it and the two frames look
the same. The shot proves "ships are on the water"; the numbers beside it
prove "and at exactly the plane, inshore as well as out".

Three things the shot had to do that are not about ships, each of which
would have made it lie:

- **It draws every lattice copy** (D-20260818): the frame is a few hexes
  across and routinely straddles a seam, so a canonical-only squad is
  simply absent from half the shots.
- **The camera focus is a wrapped midpoint.** Averaging two world
  positions put it in the middle of the map looking at open sea, with
  every printed number healthy — D-008's ghost-copy rule, in a preview.
- **The shore is ranked by HEIGHT first and water sides second.** Ranked
  the other way, six water sides beats any relief and the shot frames the
  flattest sandbar on the map: measured at 0.002 world units above the
  waterline, which is a picture of two squads at the same height proving
  nothing.

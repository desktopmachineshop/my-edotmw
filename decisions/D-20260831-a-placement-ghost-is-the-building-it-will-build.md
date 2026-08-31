# D-20260831 · A placement ghost is the building it will build

**ID:** D-20260831-a-placement-ghost-is-the-building-it-will-build
**Date:** 2026-08-31
**Status:** Accepted (owner's call, from a live playtest: "authored
building build preview needs to show the actual building in as a semi
transparent type ghost rather than plain old squares")

## Decision

The build preview wears the model it is about to raise — resolved
through `BuildingDef.model_for` against the VIEWING player's civ, so an
emberdeep player previewing a town centre sees the dwarf hall they will
actually get (D-20260830-a-building-wears-a-civs-own-body) — drawn
semi-transparent and tinted green or red by whether the ground will take
it. Both preview paths change: the single cursor ghost and every segment
of a wall drag-line.

1. **One resolver, two callers.** `client._ghost_visual_for` answers
   "what does this preview wear", `_place_ghost` puts one instance on the
   ground. The single ghost and the drag line share both, because they
   had already drifted: the line pool copied the single ghost's
   hardcoded 1.5 lift, which is half the DEFAULT box's height, so every
   wall segment — mesh 1.95 tall — previewed floating half a unit up.
   D-096's shared-arithmetic rule, fourth occurrence after the drag
   preview's `slot_world_offset`, the minimap click mapping and the
   terrain sampler.
2. **The lift rule has ONE definition now** (`UnitMesh.ground_lift`): an
   authored model is built with its origin at its base and needs none, a
   primitive is centred on its own origin and rises by half its height.
   It was written out longhand in the real building path and hardcoded
   wrongly in both preview paths — three copies, two of them wrong.
3. **The ghost is its own shader, and that is the load-bearing part.**
   `shaders/building_ghost.gdshader` reads `COLOR.rgb` and applies one
   `opacity` uniform. A `StandardMaterial3D` with
   `vertex_color_use_as_albedo` — the obvious implementation — multiplies
   the vertex colour into ALBEDO **including its alpha**, and COLOR_0's
   alpha is the OWNER-COLOUR MASK (D-052): 1.0 on a roof or banner, 0.0
   on most walls. That ghost would be transparent exactly where the
   building shows least owner colour, so the walls would vanish and a
   roof would hang in the air, with every count healthy and nothing
   failing. Same family as the MultiMesh-overrides-COLOR trap in
   `art/lib/bake.py` and the linear-to-sRGB one in D-100: **assert the
   value on the far side of the boundary.**
4. **Tinted, not replaced** (`tint_mix` 0.55). A flat green silhouette
   says where the building goes and not WHICH building, and telling a
   barracks from a storehouse at a glance is most of what a preview is
   for.
5. **Unshaded**, like the box before it: a ghost is a statement about an
   INTENT rather than an object standing in the world's light, and
   D-086's rig has no shadows, so a lit ghost half inside the terrain
   reads as a real building that has sunk into the ground.

## The instrument, because there was none

A preview exists only while somebody is holding a build order, which no
capture had ever done — so `just test-client`, the one thing that
renders the real client, structurally could not photograph this.
`--preview-building=<def_id>` arms one (the sibling of `--hold-opening`,
added for exactly this reason in #284), and the recipe takes a fifth
argument:

```
just test-client 60 2 0 1280x720 town_centre
```

It gates on the client's own `GHOST … drawn=true` marker rather than on
the flag having been passed — "the client was told to arm a preview" and
"a ghost was rendered" are different claims, and a photograph of a
feature not working is still a valid PNG (`browser-shot`'s rule).

**Fifth time this framing has had to be aimed on purpose**, after
cliffs (a spawn is walkable by construction), forest interiors (a spawn
is open ground), the fog edge, and the opening hint.

**Owed: a frame with the player's BASE in it.** The capture arms the
preview beside home (`GHOST_AIM … via=beside home`) with the camera put
there too, and the gate is honest either way — but `test-client` rolls a
fresh seed per run (D-100), so which ground home lands on is luck, and
the frames taken for this entry sit on quiet terrain with nothing beside
the ghost to judge its size or colour against. What is verified by
picture is that the ghost is the MODEL and not a box; what is not is how
it reads next to the real thing. A seed-pinned capture would settle it
and does not exist.

Two diagnostics were paid for on the way, both worth keeping. The aim
prints WHICH BRANCH it took, because the first version printed only the
resolved target and "projected to the centre" and "fell back to the
centre" are the same two numbers with opposite meanings — a whole render
run to notice. And arming waits for `_camera_homed`: projecting a world
point against a camera still sitting at the middle of the map answers
nothing, which is why the first aimed run silently fell back.

## Known and accepted

- **The fallback is unchanged and still reached.** A def with no
  authored model for this civ — every wall-family def today — previews
  as the same tinted box it always did (D-064's designed degradation),
  and so does a clone with no `generated/`.
- **Sorting artefacts inside a self-overlapping transparent mesh** are
  accepted, as they are for every alpha-blended object in the engine;
  `depth_draw_never` keeps the ghost from carving holes in the world
  behind it.
- **The access-tower door marker is untouched** — it is a separate
  sphere and still says which side the door opens onto.

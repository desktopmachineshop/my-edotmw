# D-20260818 · Entities are drawn at every visible lattice copy

**Date:** 2026-08-18
**Status:** Accepted
**Milestone:** M10 (scale optimisation), workstream 6 of 8 — issue #110
**Supersedes nothing; amends the render half of D-035 and D-045.**

## Decision

Every entity the client draws — squad, building, wall junction, forest
chunk, falling tree, arrow, selection disc, selection ring, build-site
mark — **exists at every lattice copy of the torus the camera can see**,
sharing one derived resource per entity. Nothing anywhere picks a copy.

`RenderCull.visible_offset_of_extent` is gone and
`RenderCull.visible_offsets_of_extent` replaces it: same margin
arithmetic, same per-copy depth handling, but it returns the **list** of
copies on screen. An empty list is the derivation gate D-045 asks for
(don't derive forty soldiers nobody can see); a non-empty list is where
the thing is drawn, all of it.

`LatticeCopies` is the mechanism. Given a source node and a caller-owned
pool, it poses the source at the first offset and thin mirrors at the
rest, each sharing the source's `MultiMesh` / `Mesh` /
`material_override` and, for a composite, its children. Mirrors are
**siblings**, not children: a building carries its facing as rotation and
its construction progress as scale, and a child's local offset would be
turned and squashed by both.

`_lattice_offset_for` survives in `client.gd` with exactly two callers —
the placement ghost and its drag line. Those follow the mouse, and the
mouse is a ray into ONE copy of the ground; previewing a barracks at nine
places would be this same bug mirrored. A test pins the count at two.

## Rationale

Of roughly twenty wrap-attributed defects in this project's history, the
inherent-tax ones (toroidal distance, periodic noise, cell-derived UVs)
were each paid once and stayed fixed. The recurring class is **render
copy-choice**, and every instance is the same asymmetry — terrain drawn
nine times (D-035), everything standing on it drawn once:

- armies vanishing at the seam (M5)
- squads never drawn on the tiled copies at all (D-045)
- "half the screen will not render units" (D-045)
- click exactly on a unit and select nothing — `node.position` vs
  canonical (2026-08-03)
- forest chunks snapping a map period sideways (#62)
- chunk centres normalising into a different copy than their own trees
  (#74 review)

Every one of those was fixed by improving the CHOICE. **There is no
correct choice.** A view can genuinely contain two copies of the same
ground, and one node cannot be in two places; whichever copy the rule
names, the other is real terrain with nothing standing on it. That is
what `RenderCull.max_camera_height`'s own header already said in the one
sentence it could not act on: *"no choice of offset fixes that; only
keeping the second copy off screen does."*

Two defects were live in the tree when this was written, and both are
fixed by the asymmetry going away rather than by a rule of their own:

- **per-soldier selection discs** were stamped at canonical positions
  with no lattice offset at all, so a squad drawn across the seam left
  its highlight a whole map behind;
- **a missile's endpoints were baked at launch** from the shooter's
  chosen render position, freezing the arrow to a copy the camera had
  since left.

## Why it is affordable

`PrimitiveUnit`'s soldier transforms already live in a shared `MultiMesh`
in **canonical** world space; the wrap was supplied purely by moving the
node. So an extra copy is a `MultiMeshInstance3D` holding two references
and a transform — **zero extra derivation**, and derivation is ~96% of
this client's frame at scale (D-045). The same holds for forest chunks
(one MultiMesh per species per chunk) and buildings (cached mesh and
material). Godot frustum-culls the off-screen copies at the
RenderingServer level, which is already what makes 1,287 terrain mesh
instances affordable.

Mirrors are created **lazily**, so a squad standing well inside the map —
nearly all of them — costs exactly what it did before.

The one real cost is in the cull: nine projections per entity per frame
where the old first-hit version paid one for an unwrapped entity. That is
the price of answering the question honestly, and it is still far less
than deriving forty soldiers.

`UnitMesh.material_for` allocating a fresh `ShaderMaterial` per call was
flagged in #110 as needing a cache before copies could share one. It does
not: the copies share the source's `material_override` **reference**, so
no second material is ever built. A test asserts the identity rather than
the cache, which is the check that would actually have caught the leak.

## Consequences

- **Selection had to stop reading `node.position`.** A squad on two
  visible copies has two screen positions, and both are things the player
  can see and aim at. `PrimitiveUnit.lattice_offsets` records what the
  renderer drew and selection ranks across it — reading it from the thing
  that drew it, which is the same discipline `node.position` was itself
  introduced for. Buildings get the same treatment via
  `_building_offsets`; resource-node picking tests all nine copies,
  because it runs on a click rather than per frame and an off-screen copy
  simply never wins.
- **LOD is per squad, not per copy**, because `visible_instance_count`
  lives on the one `MultiMesh` every copy reads. Policy: **nearest
  visible copy wins**. Taking the farthest would thin a squad in the
  foreground because a twin of it sits near the horizon.
- **`visible_offsets_of_extent` is a cull decision and nothing else.** A
  cull mistake can no longer MOVE anything — the worst it can do is fail
  to draw a copy, which is what culling is for.
- **`RenderCull.max_camera_height` stops being a correctness
  constraint.** It exists solely because entities were drawn once. It is
  left in force and untouched here — raising the cap is a taste question
  now, and belongs with whoever decides how much of a world a player
  should see at once (`MapSettings.sizes`), not with this change.
- **`bench_render.gd` draws the copies too.** A benchmark that still drew
  one of them would be measuring a client that does not ship — the same
  reason it already duplicates the client's LOD tiers.
- Simulation, netcode and `state_curve.gd` are untouched. This is
  strictly the render side of D-035.

## Rejected alternatives

- **Keep improving the choice.** Six fixes over five milestones, each
  correct, each followed by another instance. The pattern is the argument.
- **Duplicate whole entity subtrees with `Node.duplicate()`.** It copies
  scripts, metadata and resources by rules that differ per property, and
  what is wanted is precisely a thin second view of ONE resource.
  `LatticeCopies.clone` is explicit about which references are shared.
- **Nine copy nodes per entity, created up front and toggled.** Simpler
  per frame, but 1,000 squads would mint 9,000 `MultiMeshInstance3D`s for
  a world in which almost every squad needs one. Lazy creation keeps the
  common case exactly as it was.
- **Mirrors as CHILDREN of the source.** One line shorter and wrong for
  anything with a rotation or a scale, which includes every building.

## Revisit trigger

If `bench_render` at 1,000 squads shows the extra copies costing
measurable CPU rather than draw calls — the claim above is that they
cannot, because nothing is derived twice — this needs re-measuring
before anything is built on it. Equally, if a future entity type is added
whose expensive state is per NODE rather than per resource, it does not
fit this mechanism and should say so rather than quietly deriving nine
times.

# D-20260817-fog-covers-props · 2026-08-17 · Accepted

**Fog of war reaches everything that STANDS on the ground, not just the
ground.** The forests, ore seams and stone piles a client draws
(D-087) read the same per-cell field `shaders/terrain.gdshader` reads,
per fragment, at a coordinate taken from the CELL and carried in
MultiMesh per-instance custom data. Buildings are deliberately excluded.

Closes issue #81. Extends D-106, which is one day old and stopped at
the terrain shader.

## The defect

The owner's report, from a playtest of the minimap-fog branch, was
"cliffs are showing through the fog". The cliff **skirts** were
innocent — they are a second surface of the same terrain mesh, wearing
the same material, and `terrain_chunk.gd` already bakes them their own
`fog_uvs` channel. What was actually visible was tree canopies and rock
props, which look like cliffs at a glance.

`TerrainChunk.set_fog` had exactly one call site, for exactly one
material, and `shaders/terrain.gdshader` was the only shader in the
project with a `fog` uniform. So the ground went black and everything
standing on it did not. `docs/playtest/p31-prop-fog-before.png` is the
frame: the lit wedge is what one player can see, and the entire left
third of the map — genuinely unexplored, drawn near-black — carries a
fully lit forest, a white stone pile and a boulder field on top of it.
`p31-prop-fog-after.png` is the same camera, the same fog wedge, one
commit later.

**Those two frames were taken at base `d6a5f9b`, and `test-client` can
no longer produce their like.** Rebasing onto the map-ladder change
(#113/#115, same day) moved the client's opening camera close enough to
its own spawn that the whole visible island is inside the player's own
vision, and an A/B on the new base is nearly identical by eye. It is not
identical numerically — 4,395 of 97,500 sampled world pixels change
strongly, against 14,415 on the old base — and
`p31-prop-fog-edge-diff.png` is what those pixels are: a rim of tree
canopies hugging the fog boundary at the north tip and the western
shore, plus a handful of selection discs that are ordinary
run-to-run noise. So the fix is confirmed on top of #74, and **the
instrument is now nearly blind to the defect it just caught**. That is
the same fact D-097 recorded about `test-client` aiming at a spawn (the
one place a cliff cannot be) and D-108 recorded about it aiming at open
ground (the one place a wood cannot be) — a third entry in the same
list, and a reason `gen-forest-preview`'s deliberate framing is the
model to copy if this ever needs a picture again.

**Sixth instance of the declared-and-unread family**, and the second in
two days: nothing failed, every number stayed green (`test-client`
reported `terrain=true`, 97 distinct colours and a clean verdict both
before and after), and the game quietly lacked a rule. D-106's own
status note says the instrument that catches this class is a test that
asserts the CALLER exists — and D-106 wrote that test for the terrain
material only, which is why the gap it left survived its own review.

**The information leak is real, not only cosmetic, but it is smaller
than it first looks.** Resource nodes are fog-gated on the wire
(`server.gd::_send_visible_nodes`, D-061), so a client is never told
about a forest it has not scouted and cannot draw one. What it *was*
drawing at full brightness was every node it had EVER seen, over ground
it had walked away from and over the near-black ground at the blurred
edge of a vision disk. Ground cover (D-100) is the case that would leak
outright — it is derived client-side from the seed and gated by nothing
— and it is not drawn by `client.gd` at all today; `ground_cover.gd`'s
own doc table now says so, and says what a client-side draw of it would
owe.

## Decision

1. **Per-fragment, like the ground.** Option 1 of the three the issue
   sketched. A prop straddling a vision edge fades exactly as the
   ground under it does, and the fog texture is already re-uploaded
   four times a second, so following it costs nothing per refresh.

2. **The coordinate comes from the CELL, per instance.** Trees batch
   one MultiMesh per (16-cell chunk, model) and the chunk root is moved
   every frame to whichever of the nine torus copies is on screen
   (D-035), so one tree renders at nine world positions over a match. A
   world-derived lookup would fog forests correctly mid-map and wrongly
   at a seam. `PropFog.instance_data` calls `TerrainChunk.fog_uv` — the
   same function the terrain mesh bakes into its own vertices, not a
   second copy of the arithmetic — so a tree and the ground under it
   can only ever read the same texel. This was the exact constraint
   #74's author flagged on the issue before any code was written.

3. **The authored materials are re-expressed, not configured.** The
   models arrive as ordinary glTF: one StandardMaterial3D per part
   colour, flat albedo, no textures. A StandardMaterial3D cannot
   multiply its albedo by a texture read at a coordinate the mesh does
   not carry, and `material_override` on a MultiMeshInstance3D replaces
   every surface at once — a tree would lose the difference between its
   trunk and its canopy, which is `art/lib/bake.py`'s own recorded
   trap. So `PropFog.shaded()` builds a COPY of the mesh whose surfaces
   wear `shaders/prop_fog.gdshader`, with the authored albedo,
   roughness, metallic and emission passed straight through.

4. **`UnitMesh.mesh_for` is left alone.** It is a shared cache read by
   the previews and asserted against by `tests/test_ground_cover.gd`;
   rewriting its materials in place would change what every other
   caller draws without any of them asking. `forest_preview.gd` was
   moved onto `PropFog.shaded` deliberately, so the preview and the
   game cannot drift on the one thing the preview is looked at for —
   the trees' colour — and it binds no field, so it still renders the
   whole wood lit.

5. **Buildings are NOT dimmed.** A building once seen is KNOWLEDGE, not
   sight (D-030), and D-101 has just settled that it is drawn un-dimmed
   for that reason. Dimming it in the world while the minimap draws it
   un-dimmed is how the two surfaces drift.

6. **`.z` of the instance data is a validity flag.** A plain
   MeshInstance3D — a felled tree mid-animation, a preview's parade —
   gets an all-zero `INSTANCE_CUSTOM` and is drawn fully lit. Same
   bargain the terrain shader's `hint_default_white` already makes: a
   renderer with no player whose knowledge could be asked about draws
   the whole world. It is a UV rather than a finished brightness for
   the same reason: a baked-in brightness would mean rewriting every
   instance in every chunk four times a second.

## Rejected alternatives

- **Per-instance colour modulation** (option 2 on the issue). Cheaper
  per fragment and much worse everywhere else: a MultiMesh overrides
  `COLOR`, which is the trap D-100 and M7 both recorded, and the
  imported materials would need `vertex_color_use_as_albedo` turned on
  behind their authors' backs to notice it. It also makes fog a
  per-tree constant, so a canopy at a vision edge steps rather than
  fades, and it costs a write per instance per refresh — ~4,200 writes
  four times a second on the shipped map, on a frame M5 and M7 both
  measured as CPU-bound.

- **Culling props on unexplored cells** (option 3). Cheapest and
  truthful, and it answers the wrong question: what is actually drawn
  wrong is *remembered* ground, where culling would delete the map the
  player earned. It also needs the felling animation to cope with a
  tree that was never drawn.

- **Mutating `UnitMesh`'s cached meshes in place.** One path instead of
  two, and action at a distance: three previews and a test read those
  exact materials.

## Consequences

- One texture tap, one `mix` and a `varying vec3` per prop fragment.
  Props are drawn in the tens of thousands, so this is the cost worth
  watching; it is the same shape as the two extra atlas taps D-096
  measured at "nothing resolvable at 1,000 squads" on Intel Iris Xe,
  against a frame that is CPU-bound on soldier derivation. **Not
  re-measured on hardware here** — `bench-render` needs a real GPU and
  this branch was verified through the software rasteriser. That is an
  open number, not a claim.
- One `vec4` of per-instance custom data per drawn tree.
- `PropFog` holds two static caches and one bound texture. They outlive
  a match — the meshes are cached per model and the next match's
  forests wear the same materials — so `client.gd::_teardown_match`
  releases the field explicitly. Left bound, the next match would open
  drawing its trees through the previous match's record of who had been
  where.
- `_push_fog_to_terrain` is now `_push_fog_to_world`, because it feeds
  two surfaces and the old name is exactly the assumption that caused
  this.

## Revisit trigger

- **Ground cover becomes something `client.gd` draws.** It must take
  the same treatment on the way in, and unlike the nodes it is NOT
  wire-gated, so drawing it unfogged would paint a complete map of
  unscouted terrain. `ground_cover.gd`'s doc table records this.
- **A prop-heavy frame measured on a discrete GPU shows the tap.** The
  fallback is option 2's per-instance modulation for cover only, which
  leaks nothing extra because cover has no wire presence to gate.
- **Elevation or props acquire tactical meaning.** This is a rendering
  change with no desync surface — the same split D-084/D-096 keep — and
  it stops being free the moment anything simulated reads it.

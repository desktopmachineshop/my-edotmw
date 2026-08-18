**Entities are drawn at every visible lattice copy now, and the
copy-choice bug class is closed
(`decisions/D-20260818-entities-are-drawn-at-every-visible-copy.md`,
2026-08-18, M10 issue #110).** Terrain has been drawn nine times since
D-035; every squad, building, wall, forest chunk and arrow was drawn
ONCE, repositioned each frame to whichever copy some rule picked. That
asymmetry is the most-repeated defect in this project's history —
armies vanishing at the seam (M5), squads never drawn on the tiled copies
at all and "half the screen will not render units" (D-045), a click
landing exactly on a soldier and selecting nothing (2026-08-03), forest
chunks snapping a map period sideways (#62), chunk centres normalising
into a different copy than their own trees (#74).

**Every one of those was fixed by improving the CHOICE, and there is no
correct choice.** A view can genuinely contain two copies of the same
ground and one node cannot be in two places; whichever copy the rule
names, the other is real terrain with nothing standing on it.
`RenderCull.max_camera_height`'s own header had said exactly this for a
milestone and could not act on it: *"no choice of offset fixes that; only
keeping the second copy off screen does."*

Three things to carry forward:

- **The fix is a plural return type.** `visible_offset_of_extent` is gone;
  `visible_offsets_of_extent` returns the LIST of copies on screen. Empty
  is D-045's derivation gate (don't derive forty soldiers nobody can
  see); non-empty is where the thing is drawn, all of it. **A cull
  mistake can no longer MOVE anything** — the worst it can do is fail to
  draw, which is what culling is for.
- **It is nearly free because the expensive part was already shared.**
  Soldier transforms live in one `MultiMesh` in CANONICAL world space and
  the wrap was supplied purely by moving the node, so a copy is two
  references and a transform — zero extra derivation, and derivation is
  ~96% of the client's frame at scale. `LatticeCopies` mirrors are
  created lazily, so a squad well inside the map costs what it always
  did. They are SIBLINGS, not children: a building carries its facing as
  rotation and its progress as scale, and a child's offset would be
  turned and squashed by both.
- **Selection had to stop reading `node.position`.** A squad on two
  visible copies has two screen positions and both are aimable.
  `PrimitiveUnit.lattice_offsets` records what the renderer drew and the
  pick ranks across it — read from the thing that drew it, which is the
  same discipline `node.position` was itself introduced for.

Two bugs that were live in the tree went with it, neither by a rule of
its own: per-soldier **selection discs** were stamped at canonical
positions with no offset, so a wrapped squad's highlight stayed a map
behind; and a **missile's endpoints were baked at launch** from the
shooter's chosen render copy, freezing the arrow to a copy the camera had
since left.

**`RenderCull.max_camera_height` stops being a correctness constraint**
and becomes taste — it exists only because entities were drawn once. It
is deliberately left untouched here: how much of a world a player should
see at once is an argument about map SIZE, not about this change.

`bench_render.gd` draws the copies too, for the same reason it already
duplicates the client's LOD tiers — a benchmark that drew one of them
would be measuring a client that does not ship.

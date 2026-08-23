# D-20260821 · 2026-08-21 · Provisional — the soldiers read as blocks because of their SILHOUETTE, not their edges; smoothing them is measured to buy nothing

**Status is Provisional and the decision is deliberately narrow:** it records
what was measured, and it does **not** change a single shipped model. The
roster, `generated/` and every triangle count are untouched by this entry. The
art-direction call it sets up is D-081's to amend and the owner's to make,
which is what `just blender-gui` now exists to let them do by looking.

**The question:** the owner asked whether the project can have "proper game
assets rather than blocky units made from primitives".

**The finding, in one line:** it can, the ceiling is much lower than it looks,
and **the obvious fix is the wrong one** — rounding the models off costs
23.7x the triangles and changes nothing anybody can see.

## What was measured

All three pictures are in `docs/playtest/`, rendered through
`art/preview.py`'s own rasteriser so they are directly comparable with
everything else this project has looked at.

**1. What ships today** (`p32-roster-as-shipped.png`). Eight archetypes,
72-256 triangles each against a 300 budget. A leg is ONE box from hip to
floor; an arm is ONE box from shoulder to hand; a head is a cube. In the
`walk` and `rout` columns the leg swings 0.52 rad about the hip as a rigid
plank and reads, at four frames a cycle, as a log lying on the ground next to
the man.

**2. Smoothing, and what it costs** (`p32-bevel-buys-nothing.png`). Every
rigid part bevelled separately — separately, because parts must stay separate
to rotate about their own pivots, and welding the figure into one shell would
fuse the sword to the hand holding it. Measured on four archetypes:

| bevel | militia | founders | multiple |
|---|---|---|---|
| none (shipped) | 132 | 172 | 1.0x |
| width 0.012, 1 segment | 756 | 984 | **5.7x** |
| width 0.012, 2 segments | 1,716 | 2,236 | **13.0x** |
| width 0.020, 3 segments | 3,132 | 4,080 | **23.7x** |

**The four columns of that picture are not distinguishable.** At 23.7x the
triangles the figure looks the same. This is exactly the failure family
`docs/status/m6.md` names — "a mechanism can be correct, its data nonzero, and
the feature still absent" — applied to geometry: bevelling works perfectly and
does nothing at the size a soldier is actually seen.

**3. Articulation, and what it costs** (`p32-articulation-vs-shipped.png`,
rows alternate shipped / articulated). Same 1.8 units, same palette, same
clips, no new animation data: thigh + shin, upper arm + forearm, a pelvis, a
chest with pauldrons, boots, and a head that is a tapered hexagonal prism
rather than a cube. Knee and elbow bend is **derived from the hip and shoulder
swing the clip already carries** — a leg swung back bends, a leg swung forward
straightens — so `clips.py` gains no keyframes.

**288 triangles, against the 300 budget and the shipped militia's 132.** The
walk and rout rows are where it shows: the plank becomes a leg with a knee and
a boot on the ground.

## What this says about where the fidelity ceiling actually is

- **It is not the triangle budget.** D-081 already recorded that "nothing
  shipped is geometry-limited" and D-086 leaned on that to spend the art
  budget on lighting. Both are still true: the heaviest foot unit is 172 of
  300, and a fully articulated figure fits in the same budget.
- **It is not the runtime.** This is the load-bearing fact and it was not
  obvious. **D-082's VAT stores final vertex positions and has no opinion
  about how they were produced** — `geom.py`'s own header says an armature
  "would add skinning weights, bind poses and an evaluation dependency graph
  to produce the same numbers, and none of that survives the bake." Read
  forwards rather than backwards, that means the shipping client can already
  display arbitrarily articulated, skinned, subdivided animation at exactly
  the cost it pays now. **Nothing in the engine, the shader, the wire or the
  simulation has to change to fix the way these look.** The blockiness is
  purely an authoring-side choice.
- **It IS the part model.** `Part` has one pivot and belongs to one group, so
  a shin cannot both follow the hip and bend at the knee: put in the leg
  group it would hinge at its own knee by the hip's angle and detach from the
  thigh. Articulation needs a **parent chain** on `Part` — a list of
  (pivot, group) applied deepest-first — and that is the single architectural
  change the picture above required. It is confined to `geom.py` and
  `clips.py`.
- **And beyond articulation, it is LOD.** There is no LOD chain: `MODEL_PARAMS`
  disables Godot's LOD generation, so every soldier is the same mesh at every
  distance and the one budget has to cover D-018's 40,000-visible worst case.
  A generated LOD chain is what would let a near mesh be 800-1,200 triangles
  while the far one stays at 60. Until that exists, 300 is the right number
  and "proper game assets" means *better shapes at 300*, not more triangles.

## Rejected, with the measurement

- **Bevel or subdivide the existing models** (rejected — the table above.
  23.7x the cost for no visible change. If edge hardness is ever wanted, the
  cheap version is smooth shading with custom normals, which costs no
  triangles at all, and it should be tried before any geometry is spent).
- **Hand-sculpting in the Blender GUI now that one exists** (rejected here,
  and it is worth saying explicitly because the GUI landing the same day makes
  it the obvious next step — see
  `D-20260821-the-blender-gui-is-a-window-on-the-generators` clause 1 and
  D-081's rationale, both unchanged. The GUI is a window; a `.blend` under
  `art/` is the exception `CLAUDE.md` flags, not the default path).
- **Raising the triangle budget first** (rejected — a budget raised without a
  LOD chain is raised for all 40,000 soldiers at once, and D-086 already
  measured the frame at 3.2x a 60 fps budget before spending anything).

## What a "yes" would cost, if the owner wants it

In order, each independently landable and independently visible in
`just blender-gui`:

1. **A parent chain on `Part`** — geom.py and clips.py only. The bake, the
   wire and the runtime are untouched. This is what buys knees and elbows.
2. **Re-cut the eight archetypes as articulated figures** — a data change in
   `art/units/`, with the budget check already in `art/build.py` enforcing
   300. Expect ~250-290 triangles each.
3. **A generated LOD chain**, which is the prerequisite for anything richer
   than that, and is M10's kind of work rather than art's.

Step 2 rebuilds `generated/`, which is where the cross-platform wrinkle
recorded in the sibling entry starts to matter: the committed VATs are
Windows-built and a Linux rebuild differs by ~31 bytes of EXR header per
archetype with identical geometry. Whoever does step 2 should do it on one
machine and say which.

**Rejected alternative for this entry itself:** landing the articulated roster
now. It changes every soldier in the game, it is an aesthetic call rather than
a correctness one, and the owner asked whether it was possible rather than for
it to be done. The evidence is a picture and the implementation is three small
steps; deciding from the picture is cheaper than deciding from a revert.

**Consequences:** none to the running game — nothing here is wired to
anything. `docs/status/art-pipeline.md` carries the summary and the pictures
are in `docs/playtest/`.

**Revisit trigger:** the owner choosing an art direction off
`p32-articulation-vs-shipped.png`, or a LOD chain landing (which changes the
budget arithmetic every number above rests on and makes the whole question
worth re-asking).

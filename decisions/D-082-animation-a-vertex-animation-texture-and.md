### D-082 · 2026-08-09 (reconstructed 2026-08-11) · Accepted — animation: a vertex animation texture, and a phase that is derived, never accumulated

**This entry is a reconstruction — see the editorial note above.**
`CLAUDE.md` cites this work at `D-065`, which collides with the real
D-065 below (formation shape, replicated state). This entry gives VAT
animation its own ID.

**Decision:** Soldiers animate via a vertex animation texture (VAT),
sampled per-vertex in `shaders/unit_anim.gdshader` /
`unit_anim_ghost.gdshader` through the shared `unit_vat.gdshaderinc`.
The VAT layout is `width = vertex count`, `height = total_frames*2 + 1`:
rows `[0, 64)` are per-frame position OFFSETS from the rest pose, rows
`[64, 128)` are animated normals, row 128 carries the part's `rgb` colour
and an owner-tint `alpha` mask. Baked as half-float RGBA EXR with the
view transform forced to `Raw` so no colour management touches the
numeric payload.

**The phase is derived from `TIME` in the shader every frame —
`phase = fract(t*rate + hash(slot))` — never accumulated.** This is the
clause that makes animation legal under D-006's ban on per-soldier
integration state: there is nowhere for a phase counter to live, because
`animation_state.gd` is all-static for the same structural reason
`formation.gd` and `cosmetic_offset.gd` are. A phase counter advanced by
delta time, or a blend weight carried between frames, would be
integration state in a cosmetic disguise and would violate D-006 clause 1
exactly as an emergent per-soldier movement system would.

**Rationale — why a MultiMesh needs this instead of a normal
`AnimationPlayer`.** Soldiers render one `MultiMeshInstance3D` per squad
(D-009), not one node per soldier — an `AnimationPlayer` has no notion of
"this instance is at a different phase than that one" within a single
mesh. A VAT sampled with a per-soldier phase hash is what lets thousands
of soldiers in one draw call each look like they are not marching in
lockstep, at the cost of three `texelFetch`es per vertex instead of a
skeletal skin.

**Consequences — the defect this shape doesn't prevent, and did
happen.** A `MultiMeshInstance3D` overrides the shader's `COLOR` with its
own per-instance colour, so a mesh's vertex `COLOR_0` never reaches the
fragment stage on this render path — the reason every soldier rendered
black before this was diagnosed, and the reason unit colour lives in the
VAT's own colour row (fetched with the same column index as position and
normal) rather than in vertex colour the way building colour does
(buildings render as individual `MeshInstance3D`s, so `COLOR` reaches
them fine). Column index is carried in `UV2.x` rather than `VERTEX_ID`,
so it survives glTF re-ordering and works under the GL Compatibility
renderer `test-client` and `gen-model-preview` both depend on.

**Revisit trigger:** none identified; VAT sampling cost at full scale is
now measured by D-086's `bench-render` run, which folds this shader's
cost into the same number that includes culling and LOD.

---

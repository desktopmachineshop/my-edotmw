### D-081 · 2026-08-09 (reconstructed 2026-08-11) · Accepted — art direction and pipeline: stylised low poly, generated, not hand-modelled

**This entry is a reconstruction — see the editorial note above, and
supersedes D-011.** `CLAUDE.md` cites this work at `D-064`, an ID never
actually written in this file — the only trace of it was a two-line Q12
closure. This entry gives the art pipeline its real ID and content, and
corrects that closure below.

**Decision:** Closes Q12 ("art direction for mesh tiers 2 and 3, and who
produces it"). Style: stylised low poly with strong silhouettes, ~300
triangles per soldier. Produced by **committed Python scripts driving
Blender headless as a library** (`bpy`, a PyPI wheel — no GUI, no system
Blender, no GPU needed for generation), not by hand in the Godot editor
or a DCC tool. D-011's tier 2 (parametric composition) is absorbed rather
than skipped: parametric composition is *how* the generators are
written, not a separate stop on the way to tier 3.

**Geometry is exactly two primitives** (`art/lib/geom.py`): `box()`
(axis-aligned, `taper`/`taper_z` for wedges and gable ridges) and
`prism()` (N-sided about Y, for helmets/shields/spearheads/spires). No
spheres, no bevels, no UV unwrap. Every soldier and building is composed
from these via an ordered list of named, coloured `Part`s
(`art/lib/soldier.py`, `art/buildings/__init__.py`).

**Vertex colour carries two channels**, not one: a part's own `rgb`, and
a `mask` (carried in alpha) for how much of that part takes the owning
player's colour (D-052) — 1.0 on cloaks/banners, 0.9 on shields, 0.85 on
tunics, 0.0 on skin and steel.

**Triangle budgets are enforced, not advisory** — `art/build.py` raises
`SystemExit` over `TRIANGLE_BUDGET = 300` (`MOUNTED_TRIANGLE_BUDGET =
460`, `BUILDING_TRIANGLE_BUDGET = 400`). The heaviest shipped foot unit
(founders, 172 tris) is still well under budget — nothing shipped is
geometry-limited, which is the fact D-086 leans on to justify spending
the art budget on lighting instead of more geometric detail.

**Both the generators and their output are committed.** `art/` is the
source of truth; `generated/` (`.glb`, VAT `.exr`, the terrain atlas) is
a committed build product anyway, so a fresh clone plays without
installing Blender. Two runs of `just build-assets` must be
byte-identical — fixed seeds, sorted iteration, no timestamps — and a
test fails if `generated/`'s manifest hash is stale against `art/`'s
source. Import settings (`detect_3d/compress_to=0` above all — Godot's
default silently VRAM-compresses a VAT, which is corruption, not
compression, on a texture where neighbouring texels are unrelated
vertices) are generated data via `art/lib/godot_import.py`, not
hand-set in the editor.

**Rationale:** Matches D-011's original tiering philosophy (zero art
dependency validates the architecture before art investment) while
finally spending the art budget D-011 deferred — the trigger D-011
itself named ("M3 complete, and playtesting suggests visual fidelity is
limiting engagement, or tiers 2/3 explicitly prioritized") had fired by
the time this was written: M3 had completed three milestones earlier and
the owner had explicitly prioritised tiers 2/3.

**Rejected alternatives:** Hand-authored final meshes in a DCC tool
(rejected — the project's whole premise, stated in `CLAUDE.md`'s "What
this project is", is that plain-text/scriptable assets keep the project
editable by Claude Code; a hand-sculpted `.blend` is the one thing this
project's own rules flag as an exception rather than the default path).
Jumping straight to tier 3 fidelity without the parametric layer
(rejected — every archetype needing its own bespoke script would multiply
the ~90-130 unit count D-070 already accepts for M9's roster growth).

**Consequences:** Nothing shipped is geometry-limited (see triangle
budget numbers above), which is the load-bearing fact behind D-086's
choice to spend on lighting rather than more detailed models. Adding an
archetype is a data change in `art/units/__init__.py`'s `ROSTER` dict,
not a new script.

**Revisit trigger:** none identified since D-011's trigger fired and
this decision was made in response to it.

---

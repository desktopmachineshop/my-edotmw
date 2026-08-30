# D-20260830 · A ship takes up its own water

**ID:** D-20260830-a-ship-takes-up-its-own-water
**Date:** 2026-08-30
**Status:** Accepted

## Decision

Two halves, one defect: hulls interpenetrated because nothing anywhere
tied a ship's drawn size to the numbers the simulation spaces it by.
From a playtest (2026-08-30): *"the boats are appearing on top of each
other. It looks like model collision size doesn't match unit visual
size"* — a screenshot of one squad's hulls fanned into each other, and
the diagnosis in it essentially correct.

1. **Every def drawn as a hull carries `formation_spacing = 3.4`.**
   Every water def (transport, warship, warboat — 10 files) shipped with
   the field ABSENT, inheriting the schema default of **1.0 world
   unit** — a soldier's shoulder spacing, documented as such in
   `unit_def.gd` — while the hull primitive is a **1.5 × 3.0 box**
   (`PrimitiveUnit.HULL_SIZE`). A squad of 3–8 "ships" was a line of
   3-unit hulls placed 1 unit apart: interpenetrating by construction,
   at every facing, from the first frame. 3.4 clears the hull's
   horizontal diagonal (√(1.5² + 3.0²) ≈ 3.354), which is the spacing
   that guarantees two neighbouring slots cannot overlap at ANY squad
   facing — the length alone only covers rank-behind-rank.

   The four LAND hull defs (ram, engines, bombard — spacing 1.5–1.6)
   take the same number, because they are the same defect: a 3-unit
   hull spaced under its own length. `tests/test_naval_separation.gd`
   enumerates the CLASS — every roster def with
   `mesh_primitive == "hull"` — rather than naming the water ones,
   per D-106's caveat that a check naming one instance covers only the
   instance it names.

2. **The separation pass exempts WALL-TOP and nothing else.**
   `SquadSim._separate_arrivals` skipped `_tier[i] != 0`. The comment
   said tier 1 (D-076's wall-top, where stacking is expected); the
   condition said "everything that is not ground", written when tier 1
   was the only other tier. When `DOMAIN_WATER` (tier 2) arrived with
   naval stage 2, the condition silently exempted every ship — so two
   ship squads sent to one spot settled on ONE CELL, and D-060's
   original guarantee ("no two settled squads share a centre cell")
   never applied on water at all. The condition is
   `_tier[i] == DOMAIN_WALL_TOP` now, and `_free_cell_near` passes the
   asking squad's own domain to `is_passable`, so a displaced ship is
   displaced onto WATER rather than onto the beach beside it.

## Rationale

- **The renderer was telling the truth.** The hull is drawn at the size
  the def's `mesh_primitive` says; the formation placed those hulls at
  a spacing authored for men. This is `formation.md`'s selection-marker
  lesson in reverse — there the marker showed a real overlap nobody
  read as a bug report; here the overlap WAS the bug report.
- **Spacing is the right knob, not the mesh.** Shrinking the hull to
  fit soldier spacing would make a warship the size of two men.
  `Formation.footprint` derives from spacing, so the data fix also
  corrects `footprint_cells` for ship squads with no further change.
- **Clearance stays D-20260821's one cell, deliberately.** This entry
  restores the ground rule to water; it does not re-litigate the
  owner's call that ally overlap beyond one cell is resolved at the
  drawn level, not by displacing whole squads. Ship squads at adjacent
  cells with correctly-spaced hulls read as a fleet in formation.
- **Cross-domain crowding is impossible by construction, so ground and
  water squads sharing one `held` map is harmless.** Clearance 1 means
  only a SHARED cell crowds, and no cell is both passable and
  navigable (`terrain_gen.build_fields` makes the domains disjoint).

## Rejected alternatives

- **A footprint-based clearance for ships.** Re-opens
  D-20260821-a-fight-loosens-a-formation, which reverted exactly that
  for allies on the owner's call. Nothing about water changes that
  argument.
- **Deriving spacing from the mesh at load.** Ties simulation data to
  a render constant at runtime — the def is the single source of truth
  for both, and a test asserting the relationship keeps them honest
  without coupling them.
- **Leaving the land hulls (ram/engine/bombard) at 1.5–1.6.** Would
  have needed the class guard to carve them out by id — a hand-written
  exclusion list of unit ids, the exact shape
  `docs/status/fantasy-civs.md` records `TOWER_EXCEPTIONS` dying of.
  Building-attack reach is cell-based, so wider siege spacing changes
  no combat rule; the full suite was run to check rather than argue.

## Consequences

- Ship squads' `footprint_cells` grows (a squad of 8 warships is now
  ~7 cells across), which sizes the separation scan and the selection
  marker correctly.
- `tests/test_naval_separation.gd` guards both halves and the class
  relationship; both its gates were observed red before the fix.
- Every timing or count tuned against ships that stacked freely is
  stale where ships appear — today that is nothing in the automated
  estate (no harness fields two ship squads at one destination), which
  is itself the standing naval gap, not this entry's.

## Revisit trigger

- Authored ship models (naval stage 8's named upgrade path): a `.blend`
  hull with a different length re-reads `HULL_SIZE`'s role — the guard
  should then compare against the authored model's bounds, not the
  primitive's.
- Any third movement domain: the separation filter is now an explicit
  wall-top exemption, so a new domain separates by default — decide,
  don't inherit.

## Amendment — the hulls are authored models now (same day)

The owner supplied two marketplace `.glb`s and they are the ships:
`art/source/warship.blend` (a two-masted sailer) and
`art/source/transport.blend` (a viking rowing boat, cargo aboard), both
imported by `art/import_glb_source.py` — Tripo exports, single mesh, no
rig, decimated to 2,500 triangles at import, textures kept
(D-20260824). The warboat defs wear the transport model until a third
body arrives; that is D-064's designed degradation pointed at a better
floor than a red box.

**Both are sized so the HULL IS 3.0 ENGINE UNITS LONG —
`PrimitiveUnit.HULL_SIZE`'s length — and that is this entry's own
spacing rule holding, not a coincidence.** The importer scales to a
stated HEIGHT, so each model's height argument was derived from its own
proportions to land the length at 3.0 (sailer 2.964 tall, rowboat
1.432). The viking boat lies along the 45° diagonal in its own file —
which is why its bounding box read square — and takes `--yaw 45`;
the sailer already faces -Y.

The guard in `tests/test_naval_separation.gd` still reads `HULL_SIZE`,
and stays honest BECAUSE the models are sized to it. The revisit
trigger above (compare against authored bounds instead) fires when a
ship model stops matching the primitive's length.

**Found on the way: `just build-assets ARCHETYPE` rewrites the
manifest's whole `units` table with only that one archetype in it** —
two consecutive `--only` runs left every other model's entry (and the
warship's own texture reference) missing, with UnitMesh falling back in
silence. A full `build-assets` restores it; filed as its own task
rather than fixed here.

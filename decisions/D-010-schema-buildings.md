# D-010 schema log — BuildingDef

Part of **D-010** (data-driven definitions). The decision, the rules for
adding to this log, and the index of the other schema logs live in
[`D-010.md`](D-010.md); this file is only the log for buildingdef.

**Append at the END. Never reorder, never edit an entry in place.** One
file per workstream is what stops four branches conflicting on one
monolith — see `README.md` rule 1, which this split exists to make D-010
obey.

**Scope:** fields on `BuildingDef` (`building_def.gd`) that are
not owned by a workstream below.

---

- **2026-08-28 — added `BuildingDef.grows: String = "none"`,
  `BuildingDef.grow_capacity: int = 0`, `BuildingDef.grow_per_second:
  float = 0.0` and `BuildingDef.blocks_movement: bool = true`.**
  D-20260828-food-is-grown-not-only-found, the renewable economy (#159).
  The first three make a building a WORK SITE an ordinary gatherer crew is
  put on, so the map's economy stops being a fixed pile; the fourth exists
  because a crew has to be able to STAND on a field to work it, and it is
  read in exactly one place (`BuildingSim.blocking_cells`).

  All four default to the behaviour that existed before, so every shipped
  `.tres` but the new `farm` is unchanged. `grows` names a resource KIND
  rather than being a `grows_food` flag on purpose: a later woodlot or
  quarry is then a file and no code, which is the same reasoning
  `mesh_primitive` is a string and `bonus_vs` is a table. The one place
  it differs from `bonus_vs` is the default — "none" and 0.0 are inert, so
  an unaware def grows nothing rather than growing something nobody
  authored, the same SAFE-end rule `damage_vs_buildings` records above.

  Also added **`AiProfileDef.farms_wanted: int = 4`**, which is a
  difficulty axis rather than a floor (see that field's own comment): how
  many one-time wood costs an opponent will pay against perpetual food IS
  its long-game ambition.


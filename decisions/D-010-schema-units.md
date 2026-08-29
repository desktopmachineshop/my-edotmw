# D-010 schema log — UnitDef

Part of **D-010** (data-driven definitions). The decision, the rules for
adding to this log, and the index of the other schema logs live in
[`D-010.md`](D-010.md); this file is only the log for unitdef.

**Append at the END. Never reorder, never edit an entry in place.** One
file per workstream is what stops four branches conflicting on one
monolith — see `README.md` rule 1, which this split exists to make D-010
obey.

**Scope:** fields on `UnitDef` (`unit_def.gd`) that are not
owned by a workstream below. A field added *by* naval, techs or audio is
logged in THAT file even though it lives on `UnitDef` — the point of the
split is that one workstream appends to one file.

---

- **2026-07-29, M1 — added `formation_spacing: float = 1.0`.** Formation
  geometry (D-006/D-019) needs a per-unit centre-to-centre spacing;
  cavalry and skirmishers do not occupy the footprint of line infantry.
  Existing `.tres` files pick up the default, so this is backward
  compatible.

- **2026-07-30, M2 — added `vision_range: float = 12.0`,
  `morale_recovery_per_second: float = 2.0`, `rout_rally_margin: float =
  15.0`, `morale_loss_per_casualty: float = 4.0`, `damage_variance: float
  = 0.25`.** D-024's combat model and D-019's morale/routing need these
  as per-unit tuning rather than script constants; `vision_range` is
  D-025's vision-field radius, added here (combat's file) rather than by
  the fog worker so `unit_def.gd` only gets one schema-touching editor
  per unit. All five are additive with defaults; existing `.tres` files
  pick them up unchanged.

- **2026-07-30, M3 — added `armour_class: String = "infantry"` and
  `bonus_vs: Dictionary = {}`.** D-032's counters. `armour_class` is what
  a unit *is* for targeting; `bonus_vs` maps an opponent's armour class
  to a damage multiplier, so the counter table is data and adding a
  counter never means editing `combat.gd`. A missing entry means 1.0, so
  a generalist unit needs no special-casing and both existing `.tres`
  files stayed valid. Shipped alongside two new units — `spearmen.tres`
  and `cavalry.tres` — completing D-015's 3-4 unit cut line with a real
  triangle: spears counter cavalry, cavalry counter missile, missile
  counters infantry.

- **2026-08-02, M6 — added `damage_vs_buildings: float = 0.15`.**
  *Logged retroactively on 2026-08-04.* D-056 introduced this field and
  called it "a schema addition against D-010", but never recorded it
  here, which is the omission this log exists to prevent. Defaults to the
  SAFE end deliberately: an unaware `.tres` is conservative rather than
  catastrophic, unlike `bonus_vs`, whose missing-key default of 1.0 is
  right for a counter table and would have been exactly wrong here. See
  D-056 for the full reasoning.

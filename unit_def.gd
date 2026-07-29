extends Resource
class_name UnitDef

## Data-driven squad/soldier definition (D-010). New units are added as
## .tres files under /units/, not new script subclasses. Extend fields
## here when a unit needs a stat that doesn't exist yet — per CLAUDE.md,
## record the schema change in game_design_decisions.md.

@export var id: StringName
@export var display_name: String = ""
@export var civ: StringName = &"neutral"

# Squad composition (D-005: squads are the atomic sim unit; D-018: full
# scale target is ~40 soldiers/squad, ~50 squads/player).
@export var squad_size: int = 40

# Per-soldier stats. Combat resolution model (Q7) is not yet decided —
# these are the stats a deterministic-per-soldier or stochastic-squad
# model would both need as inputs.
@export var health: float = 100.0
@export var damage: float = 10.0
@export var move_speed: float = 3.5
@export var attack_range: float = 1.5
@export var attack_interval: float = 1.0

# Formation & morale (D-019: Total War-style formations/morale/routing,
# no campaign layer). Exact rout behavior (Q7) is still open.
@export_enum("line", "column", "wedge", "loose") var formation_shape: String = "line"
# Centre-to-centre spacing between adjacent soldiers, in world units.
# Schema addition 2026-07-29 (M1, recorded against D-010): formation
# geometry needs a per-unit spacing — cavalry and skirmishers do not
# occupy the same footprint as line infantry. Existing .tres files pick
# up the default.
@export var formation_spacing: float = 1.0
@export var morale: float = 100.0
@export var rout_threshold: float = 25.0

# Primitive-tier mesh generation (D-011, see primitive_unit.gd). Tiers 2
# (modular/parametric) and 3 (Blender/glTF final-fidelity) are
# unscheduled — don't add fields for them speculatively.
@export_enum("capsule", "box", "cylinder", "hull") var mesh_primitive: String = "capsule"
@export var mesh_color: Color = Color.WHITE

# Economy
@export var build_time: float = 10.0
@export var cost: int = 50

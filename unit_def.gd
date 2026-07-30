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

# Schema addition 2026-07-30 (M2, recorded against D-010): combat and
# morale tuning for D-024/D-019, plus vision for D-025 (owned by the fog
# worker, added here because this file is combat's, not theirs, to touch).
# Existing .tres files pick up these defaults, same as formation_spacing.
#
# How far this unit's squad can see, in world units (D-025). Radius-only
# on the torus — elevation does not occlude in M2.
@export var vision_range: float = 12.0
# Morale regained per second while not taking casualties (D-024/D-019).
@export var morale_recovery_per_second: float = 2.0
# Hysteresis above rout_threshold a routed squad must recover past before
# it rallies — without this a squad sitting exactly at the threshold
# would flicker in and out of routing every tick it takes no damage.
@export var rout_rally_margin: float = 15.0
# Morale lost per soldier this squad loses to casualties.
@export var morale_loss_per_casualty: float = 4.0
# Stochastic spread on this unit's damage roll: output is drawn uniformly
# from [damage * (1 - variance), damage * (1 + variance)] per D-024's
# "rolled stochastically". 0 would make combat deterministic attrition,
# which D-024's rejected alternatives explicitly reads as too decided by
# stat ties alone.
@export var damage_variance: float = 0.25

# Primitive-tier mesh generation (D-011, see primitive_unit.gd). Tiers 2
# (modular/parametric) and 3 (Blender/glTF final-fidelity) are
# unscheduled — don't add fields for them speculatively.
@export_enum("capsule", "box", "cylinder", "hull") var mesh_primitive: String = "capsule"
@export var mesh_color: Color = Color.WHITE

# Economy
@export var build_time: float = 10.0
@export var cost: int = 50

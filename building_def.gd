extends Resource
class_name BuildingDef

## Data-driven building definition (D-010, D-031), the structural sibling
## of `UnitDef`. New buildings are added as .tres files under /buildings/,
## not as new scripts.

@export var id: StringName
@export var display_name: String = ""
@export var civ: StringName = &"neutral"

@export var max_health: float = 400.0

## Seconds of construction at full rate. Replicated as a curve rather
## than a per-tick number: a build is two keyframes — progress now,
## completion at a known time — so it costs nothing further until
## something interrupts it (D-003, which names build progress explicitly).
@export var build_time: float = 20.0

## Buildings see, like squads do. Stamped into the same per-player vision
## coverage (D-025), because coverage is about cells and does not care
## what put a cell in it.
@export var vision_range: float = 16.0

## How much ground this building denies to OTHER players, in cells
## (D-062). Nobody hostile may found anything inside this radius.
##
## Per building rather than one global constant, because a town centre
## claims a settlement's worth of ground and a tower claims its own
## footprint — and making it data means a civ or a scenario can tune
## territory without touching a script (D-010).
##
## Allies are exempt: D-050 gives teams shared vision and a shared front,
## and a teammate unable to build beside your hall would be a worse
## partner than an enemy. It is enforced server-side (D-002) and re-checked
## on arrival, because a builder ordered from out of reach walks for
## twenty seconds and the ground may be claimed by the time it gets there.
@export var no_build_radius: int = 4

# Combat (D-032). Only the tower has an attack; everything else leaves
# `damage` at zero and is simply a target. Buildings resolve attacks in a
# pass separate from the squad path — `Combat._check_rout` calls
# `force_move`, and a building has neither morale nor the ability to move.
@export var attack_range: float = 0.0
@export var damage: float = 0.0
@export var attack_interval: float = 1.0

## True if this building can receive gathered resources (D-028's
## round-trip hauling). Data rather than a hardcoded list of ids, so
## adding a drop-off never means editing the economy.
@export var is_drop_off: bool = false

## What this building can produce, as UnitDef ids. Empty means it produces
## nothing.
@export var produces: Array[StringName] = []

## Which squad types may construct this, as UnitDef ids. **Empty means
## any builder may.**
##
## Data rather than a hardcoded check, per D-010, so restricting a
## building to a particular unit never means editing the construction
## code. The town centre lists `founders` and nothing else: settling a new
## base is deliberately a specific act by a specific unit, not something
## any squad can do wherever it happens to be standing.
@export var built_by: Array[StringName] = []

# Cost, per resource (D-028's four: food, wood, gold, stone). Declared
# now, consumed in slice 5 — unlike UnitDef.cost, which sat unread for two
# milestones, this one has a named consumer already designed.
@export var cost_food: int = 0
@export var cost_wood: int = 0
@export var cost_gold: int = 0
@export var cost_stone: int = 0

# Primitive-tier mesh (D-011), same tiering as units.
@export_enum("box", "cylinder", "capsule", "hull") var mesh_primitive: String = "box"
@export var mesh_color: Color = Color(0.7, 0.68, 0.6)
@export var footprint_radius: int = 1

extends Resource
class_name BuildingDef

## Data-driven building definition (D-010, D-031), the structural sibling
## of `UnitDef`. New buildings are added as .tres files under /buildings/,
## not as new scripts.

@export var id: StringName
@export var display_name: String = ""
@export var civ: StringName = &"neutral"

## The shared idea of a building type, `UnitDef.archetype`'s analogue
## (`D-20260827-a-research-site-is-a-building`).
##
## EMPTY MEANS "my own id", which is what makes this free: every shipped
## def keeps its exact current meaning without being edited, because
## `barracks.tres` has id `barracks` and therefore archetype `barracks`.
## `produces`, `built_by`, `upgrade_from` and the build menu already name
## ids that are also types, so none of them moved.
##
## It exists because two archetypes became PER-CIV — the stables and the
## forge, which are research SITES — and six civs' versions cannot share
## one id in one directory. `TechDef.research_at` names this, never an id,
## so a tech can say "at the forge" for four civs that call it four
## different things.
##
## Read through `BuildingSim.archetype_of`, never directly, so the
## fallback has one definition.
@export var archetype: StringName = &""

## The tech LINE that makes this building foundable, or empty for
## "always" (`D-20260827-the-tree-is-the-ladder`). `UnitDef.requires_tech`'s
## sibling, with the same safe-empty default: every building that ships
## today leaves it empty, so the build menu a player already knows is
## unchanged at epoch 1.
@export var requires_tech: StringName = &""

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

# Combat (D-032). The tower and the town centre have an attack; everything
# else leaves `damage` at zero and is simply a target. Buildings resolve
# attacks in a pass separate from the squad path — `Combat._check_rout`
# calls `force_move`, and a building has neither morale nor the ability to
# move.
#
# READ THIS BEFORE TUNING `damage` (D-066). It is NOT on the same scale as
# `UnitDef.damage`, and the difference is a factor of ~40. A squad's volley
# is `damage x alive` — 36 militia at 9.5 is 342 per second. A building
# fires one flat `damage`, multiplied by nothing, so a number that looks
# comparable to a unit's is worth about one soldier. The shipped values
# were authored that way and the defence was invisible in play: a town
# centre cost a lone attacking squad 4 men out of 36.
@export var attack_range: float = 0.0
@export var damage: float = 0.0
@export var attack_interval: float = 1.0

## True if this building can receive gathered resources (D-028's
## round-trip hauling). Data rather than a hardcoded list of ids, so
## adding a drop-off never means editing the economy.
@export var is_drop_off: bool = false

## Which resource a complete, living building of this type GROWS, or
## "none" (D-20260828-food-is-grown-not-only-found). A growing building is
## a work site an ordinary gatherer crew is ordered onto exactly as it is
## ordered onto a forest — the whole D-028 haul cycle, unchanged.
##
## Named as a resource KIND rather than a `grows_food` flag because the
## same three fields answer "a renewable of any kind": a later woodlot or
## quarry is a .tres file and no code, which is the difference between
## this and a market (deferred, see the decision).
@export_enum("none", "food", "wood", "gold", "stone") var grows: String = "none"

## How much grown stock this building banks while nobody is working it, so
## a fresh farm yields IMMEDIATELY (a crew takes whatever has grown, not
## whatever has filled) and a farm left alone while its crew hauls is not
## wasting its rate. Read by `Economy.sync_farms`.
@export var grow_capacity: int = 0

## Units of `grows` per second. This is the number that matters: a farm
## does not add STOCK to the map, it adds INCOME, which is the only kind
## of quantity D-068's per-second upkeep can be paid out of. The steady
## state per building is this rate no matter how many crews stand on it —
## more income is more farms, not more workers on one square.
@export var grow_per_second: float = 0.0

## Whether this building's cells block ground movement
## (`BuildingSim.blocking_cells`). True for everything that has ever
## existed here; false only for a field, which a crew has to be able to
## STAND on — `Economy` decides a crew has arrived by comparing its cell
## with the work cell, so a farm that blocked its own cell could never be
## worked.
@export var blocks_movement: bool = true

## What this building can produce, as UnitDef ids. Empty means it produces
## nothing.
@export var produces: Array[StringName] = []

## Which squad types may construct this, as UnitDef ids. **Empty means
## any builder may.**
##
## Data rather than a hardcoded check, per D-010, so restricting a
## building to a particular unit never means editing the construction
## code. Matched against the builder's ARCHETYPE, so one entry covers
## every civ's version of a unit (D-047). The general is barred from
## building simply by being listed nowhere
## (D-20260823-the-opening-is-a-crew-and-a-general).
@export var built_by: Array[StringName] = []

## Founding this building SPENDS the squad that founds it, at the moment
## the build commits (D-20260823-the-opening-is-a-crew-and-a-general,
## superseding D-031's founders). Data rather than a unit/building pair
## hardcoded in `_finish_build`, so the M7 playtest fix — "consumed ANY
## builder unconditionally" — keeps its scope by construction: only the
## town centre sets this, and a gatherer finishing a barracks or a wall
## walks away free.
@export var consumes_builder: bool = false

## Playtest fix: which EXISTING building ids (as BuildingDef.id) this
## archetype may be raised in place of, upgrading it rather than requiring
## it be torn down first — the natural way a player expects to add a
## tower to a wall that already exists. Empty (every def but wall_tower)
## means this can only ever be founded on genuinely empty, unbuilt ground.
## Checked against the EXISTING building's def id, and only ever lets an
## owner upgrade their OWN, COMPLETE building (server.gd's
## `_upgrade_target_at`) — an enemy's wall is not yours to upgrade, and a
## still-under-construction one has nothing finished to replace yet.
@export var upgrade_from: Array[StringName] = []

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

## Which tier of the build menu this belongs to (playtest fix): the roster
## outgrew a single flat list of buttons once D-076 added five wall-family
## defs, so the menu groups by this instead of showing every buildable def
## at once. Data-driven per D-010, same reason `mesh_primitive` is a string
## and not a per-building branch — client.gd names no building here, only
## this field.
@export_enum("civic", "military", "defensive") var category: String = "civic"

## Which authored model this building wears (D-064). Schema addition
## 2026-08-09 (M7), mirroring `UnitDef.model_id`.
##
## Empty means "use the primitive", and the primitive now actually reads
## `mesh_primitive` above. It did not until M7: every building rendered as a
## hardcoded 2.4x3.0x2.4 box, and `mesh_primitive` sat with no readers at all
## for four milestones — the fifth instance of the declared-and-unread defect
## class after `UnitDef.cost`, `BuildingDef.cost` and `BuildingSim.damage()`.
@export var model_id: StringName = &""
@export var footprint_radius: int = 1

# Walls, gates and the walkable wall-top tier (D-076). A wall is a chain of
# single-cell segments (no edge/footprint geometry exists in TorusSpace, so
# this reuses the ordinary single-cell building model rather than inventing
# one) that blocks ground passability for free, the same way any building's
# occupied cell already does via BuildingSim.occupied_cells().

## Marks this structure as a gate: it can be opened/closed (manually or
## automatically near the owner's own squads) rather than being a permanent
## blocker like a plain wall segment.
@export var is_gate: bool = false

## True only on garrison-grade wall/gate/tower defs. Marks this cell as part
## of the tier-1 (wall-top) passable network — a second, much smaller
## FlowField layer squads can be routed across once they're up there.
## False (the default, and every plain wall/gate segment) means this cell
## has no tier-1 presence at all.
@export var walkable_top: bool = false

## Added, in world units, to a squad's own `UnitDef.attack_range` while it
## is standing on this structure's tier-1 cell — the height advantage.
## Combat is still resolved with the squad's own stats (D-076); the
## structure itself never attacks on its own when this is nonzero.
@export var top_range_bonus: float = 0.0

## Added to a squad's effective vision while standing on this structure's
## tier-1 cell.
@export var top_vision_bonus: float = 0.0

## World-unit height of the walkway above ground level, used both to place
## the walkway mesh and to position soldiers standing on it.
@export var top_height: float = 0.0

## True only on the access-tower def. Marks this archetype as a climb
## point — the wall-top network is otherwise unreachable. The actual door
## FACING is deliberately NOT stored here: `BuildingDef` is one shared
## Resource per archetype (every `wall_tower` a player builds points at
## the same `.tres`), so a per-placement choice like "which of the 6 hex
## sides the door faces" has to live on the building INSTANCE instead —
## see `BuildingSim._access_direction`, set from the build order at
## construction time. This flag only says "this archetype has a door
## somewhere"; where is per-instance.
@export var is_access_tower: bool = false

## Override for primitive-mesh dimensions; Vector3.ZERO means "use the
## existing hardcoded per-primitive size". Wall segments need this to
## render as thin, long blocks instead of the square building box every
## other primitive building uses.
@export var mesh_size: Vector3 = Vector3.ZERO

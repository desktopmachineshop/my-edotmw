extends RefCounted
class_name ResourceVisuals

## Which model a resource node wears, how it stands, and how it falls —
## the pure half of the forest rework, split out of client.gd the same way
## RenderCull and SelectionPick were (D-045, D-061): the choices with
## interesting failure modes (wrong species in a desert, a felling that
## never ends) are testable without a GPU, and the client keeps only the
## scene-tree plumbing.
##
## ## Everything here is cosmetic, and deterministic anyway
##
## The server decides WHERE nodes are and WHEN they run dry; nothing below
## feeds back into simulation, so in principle each client could disagree
## about which oak variant a cell grows. They still never do: every choice
## is a pure hash of the cell index, so two clients — and one client
## across two sessions — always dress the same map identically. That costs
## nothing and spares "your forest looks different from mine" reports that
## would read as desyncs.
##
## ## Species follow the ground
##
## A wood node picks its species pool from the biome it stands on: dense
## temperate forest in FOREST, parkland species on GRASSLAND, arid types
## (acacia, saguaro) on DRY_GRASSLAND, palms on the BEACH — with the
## wettest forest ground swapping toward willow and swamp cypress. On
## region boundaries a tree sometimes borrows a NEIGHBOUR cell's biome
## instead (see `model_for`), so a treeline frays naturally into the next
## region's species rather than snapping along the hex where the noise
## crossed a threshold.
##
## All-static on purpose, like Formation and AnimationState: there is
## nowhere to put per-tree state, so nothing here can drift into the
## integration-state trap D-006 forbids.

## Every species ships VARIANTS numbered models: tree_<species>_<n>.glb
## (art/resources/split_markers.gd discovers them from the source asset).
const VARIANTS := 5

## Wood species pools by ground. Wet forest is a moisture band INSIDE the
## forest biome, not its own biome — the threshold below picks it.
const FOREST_SPECIES: Array[String] = ["oak", "pine", "spruce", "birch"]
const WET_FOREST_SPECIES: Array[String] = ["willow", "swamp_cypress", "oak", "spruce"]
const GRASS_SPECIES: Array[String] = ["oak", "poplar", "birch", "willow"]
const ARID_SPECIES: Array[String] = ["acacia", "saguaro"]
const BEACH_SPECIES: Array[String] = ["palm"]

## Forest ground wetter than this grows the willow/cypress pool.
const WET_MOISTURE := 0.80

## Standing size range. The source models span ~2.3-2.6 world units of
## canopy, authored as lone landmarks — at one tree per cell (~1.73 units
## across at hex_size 1.0) that merged every dense forest into a single
## blob, so trees stand at roughly cell size instead, with enough jitter
## that no two neighbours read as clones.
const SCALE_MIN := 0.60
const SCALE_MAX := 0.92

## How often a tree on a biome boundary borrows the neighbour's species
## pool instead of its own.
const BOUNDARY_MIX := 0.35

# Salt per decision stream, so "which species" and "which yaw" are
# independent rolls of the same cell rather than correlated ones.
const _SALT_MIX := 1
const _SALT_NEIGHBOUR := 2
const _SALT_SPECIES := 3
const _SALT_YAW := 4
const _SALT_SCALE := 5
const _SALT_AXIS := 6
const _SALT_VARIANT := 7

## How a felled thing leaves the map, in seconds.
const TIP_SECONDS := 1.4
const SINK_SECONDS := 1.2
const SINK_DEPTH := 1.8
const ORE_SINK_SECONDS := 1.5
const ORE_SINK_DEPTH := 1.4


## The model a node at `cell` wears. `biome` is the cell's own ground,
## `neighbour_biomes` its six neighbours' (any order), `moisture` the
## cell's moisture sample — all client-derivable from the same TerrainGen
## the terrain mesh was built from, so the dressing agrees with the ground
## by construction.
static func model_for(kind: int, biome: int, neighbour_biomes: Array,
		moisture: float, cell: int) -> StringName:
	match kind:
		Economy.ResourceKind.FOOD:
			return &"resource_food"
		Economy.ResourceKind.GOLD:
			return &"resource_gold"
		Economy.ResourceKind.STONE:
			return &"resource_stone"

	# Wood: species follows the ground, frayed at region boundaries.
	var ground := biome
	if not neighbour_biomes.is_empty() and _roll(cell, _SALT_MIX) < BOUNDARY_MIX:
		var pick: int = neighbour_biomes[
			int(_roll(cell, _SALT_NEIGHBOUR) * neighbour_biomes.size()) % neighbour_biomes.size()]
		# Only borrow ground trees can actually grow on — a shoreline tree
		# should not roll "water" and fall back to somewhere arbitrary.
		if not _species_for(pick, moisture).is_empty():
			ground = pick

	var pool := _species_for(ground, moisture)
	if pool.is_empty():
		# A wood node on ground with no pool (a fairness top-up can put one
		# anywhere walkable): wear the generic wood tree rather than nothing.
		return &"resource_wood"

	var species: String = pool[int(_roll(cell, _SALT_SPECIES) * pool.size()) % pool.size()]
	var variant := int(_roll(cell, _SALT_VARIANT) * VARIANTS) % VARIANTS
	return StringName("tree_%s_%d" % [species, variant])


static func _species_for(biome: int, moisture: float) -> Array[String]:
	match biome:
		TerrainGen.Biome.FOREST:
			return WET_FOREST_SPECIES if moisture >= WET_MOISTURE else FOREST_SPECIES
		TerrainGen.Biome.GRASSLAND:
			return GRASS_SPECIES
		TerrainGen.Biome.DRY_GRASSLAND:
			return ARID_SPECIES
		TerrainGen.Biome.BEACH:
			return BEACH_SPECIES
	return []


## Standing pose: every tree gets its own facing and a little size
## variation, or a forest of identical clones reads as wallpaper.
static func yaw_for(cell: int) -> float:
	return _roll(cell, _SALT_YAW) * TAU


static func scale_for(cell: int) -> float:
	return lerpf(SCALE_MIN, SCALE_MAX, _roll(cell, _SALT_SCALE))


## The horizontal axis a felled tree tips around — which way it falls.
static func tip_axis_for(cell: int) -> Vector3:
	var angle := _roll(cell, _SALT_AXIS) * TAU
	return Vector3(cos(angle), 0.0, sin(angle))


## Where a felled thing is, `age` seconds after the felling.
##
## Trees TIP — rotate about their base to horizontal, accelerating the way
## a cut trunk does — then sink away. Ore has nothing to tip, so it only
## sinks. Returned as parts ({"angle", "sink", "done"}) rather than a
## finished Transform3D so the caller composes them with the standing yaw
## and scale it already applies, and so this stays trivially assertable.
static func fall_pose(kind: int, age: float) -> Dictionary:
	var is_tree := kind == Economy.ResourceKind.WOOD or kind == Economy.ResourceKind.FOOD
	if not is_tree:
		var t := clampf(age / ORE_SINK_SECONDS, 0.0, 1.0)
		return {"angle": 0.0, "sink": t * ORE_SINK_DEPTH, "done": age >= ORE_SINK_SECONDS}

	var tip := clampf(age / TIP_SECONDS, 0.0, 1.0)
	var sink := clampf((age - TIP_SECONDS) / SINK_SECONDS, 0.0, 1.0)
	return {
		"angle": tip * tip * (PI / 2.0),  # accelerating: slow lean, fast crash
		"sink": sink * SINK_DEPTH,
		"done": age >= TIP_SECONDS + SINK_SECONDS,
	}


## Deterministic roll in [0, 1) from (cell, salt) — Combat._roll_unit's
## FNV mixing, for the same bit-identical-everywhere reason.
const _FNV_PRIME := 0x01000193


static func _roll(cell: int, salt: int) -> float:
	var h := 0x811C9DC5
	h = ((h ^ (cell & 0xFFFFFFFF)) * _FNV_PRIME) & 0xFFFFFFFF
	h = ((h ^ (salt & 0xFFFFFFFF)) * _FNV_PRIME) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * _FNV_PRIME) & 0xFFFFFFFF
	return float(h & 0xFFFFFF) / float(0x1000000)

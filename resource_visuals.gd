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
## ## A forest is not one tree per cell
##
## Trees stood at the exact centre of their node cell, one apiece, and a
## wood read as ranks and files you could count along — the hex lattice
## showing straight through the dressing. Placement is now a small,
## hash-chosen NUMBER of trees per cell, each on its own jittered offset
## from the centre, so a forest clumps and thins instead of tiling.
##
## Two things make that safe to do:
##
## - the offset is bounded by `MAX_OFFSET`, which is under a hex's
##   inradius, so a tree never leaves the cell it belongs to. It cannot
##   drift onto water or over a cliff, and it never stands nearer some
##   other cell's centre than its own;
## - it is RENDERING ONLY. A node's *cell* is simulation state — economy
##   targeting, gather range, the depletion event and its fog gating are
##   all per-cell — and none of it moves. Exactly the split D-084/D-096
##   kept for terrain: the picture interpolates, the simulation stays
##   discrete. Gatherers work the cell whatever the trees on it look like.
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

## Standing size range for a TREE. The source models span ~2.3-2.6 world
## units of canopy, authored as lone landmarks, against ~1.73 units of cell
## spacing at hex_size 1.0 — so at this range a canopy is wider than the
## cell under it and neighbouring trees interlock. That is now wanted: a
## hard gap around every canopy is most of what made a forest read as a
## grid. It was NOT safe at one tree per cell centre, where full-size
## canopies on a regular lattice merged into one undifferentiated blob;
## what makes it safe is that position varies first (see `trees_for`).
const SCALE_MIN := 0.68
const SCALE_MAX := 1.10

## Ore keeps the old, tighter range. A seam is ONE object on its cell and
## gains nothing from growing — the range above is about canopies
## overlapping each other, which a lone boulder cannot do.
const ORE_SCALE_MIN := 0.60
const ORE_SCALE_MAX := 0.92

## How far from the cell centre a tree may stand, **in units of hex_size**
## (the caller multiplies by `space.hex_size`, as GroundCover's callers do).
##
## A pointy-top hex's inradius is sqrt(3)/2 ~ 0.866 of hex_size, so this
## bound keeps every tree strictly inside its OWN cell: it cannot wander
## onto water or over the cliff next door, and it stays nearer its own
## cell's centre than any other's. A test pins the relationship rather
## than the number, because that is the property, not 0.78.
const MAX_OFFSET := 0.78

## And no nearer than this, so a cell's trees ring its centre instead of
## piling on it. At one tree per cell this alone is what breaks the ranks
## and files: the tree is never where the lattice would draw it.
##
## It also sets the WORST CASE separation inside a cell, with SECTOR_JITTER
## below: two trees in adjacent sectors, both drawn at this radius, are
## still 2 * MIN_OFFSET * sin((1 - SECTOR_JITTER) * PI / MAX_PER_CELL)
## apart — about 0.16 of a hex_size at the shipped values. Trees closer
## than that read as one fat tree and waste the instance.
const MIN_OFFSET := 0.34

## How much of its own angular sector a tree may wander within, as a
## fraction. Under 1.0 so two trees either side of a sector boundary keep a
## gap; see MIN_OFFSET for the arithmetic that pins it.
const SECTOR_JITTER := 0.62

## Ore wanders less. A player clicks a seam to gather from it and the click
## test works from the cell, so a boulder drawn most of a cell off-centre
## would misreport where the node actually is. Trees are a mass and are
## clicked as one, so they may take the full span.
const ORE_MAX_OFFSET := 0.35

## Trees per node cell before the spread roll, by the ground it stands on.
## Absent means DEFAULT_TREES — a fairness top-up can put a wood node on
## ground with no entry here, and it should still grow something.
##
## These are the SHIPPED numbers and the ones tests assert against: a
## placement mechanism that is right and yields one tree per cell anyway is
## D-066's "mechanism correct, shipped numbers do nothing" all over again.
const BASE_TREES := {
	TerrainGen.Biome.FOREST: 3.4,
	TerrainGen.Biome.GRASSLAND: 2.4,
	TerrainGen.Biome.DRY_GRASSLAND: 1.5,
	TerrainGen.Biome.BEACH: 1.8,
}
const DEFAULT_TREES := 2.0

## How much moisture swings the count either way, as a fraction. Wet ground
## grows a thicket, dry ground a stand of a few — the same idea that already
## picks WET_FOREST_SPECIES, applied to how many rather than which.
const TREE_MOISTURE_SWING := 0.30

## The most trees one cell may hold, whatever the table says. A bound on the
## worst case rather than a tuning knob, like GroundCover.MAX_PER_CELL: the
## client sizes MultiMeshes from what it is handed.
const MAX_PER_CELL := 5

## How often a tree on a biome boundary borrows the neighbour's species
## pool instead of its own.
const BOUNDARY_MIX := 0.35

# Salt per decision stream, so "which species" and "which yaw" are
# independent rolls of the same cell rather than correlated ones. Every
# per-TREE stream also takes the tree's index within its cell, which is
# what stops a cell's trees landing on one spot wearing one model.
const _SALT_MIX := 1
const _SALT_NEIGHBOUR := 2
const _SALT_SPECIES := 3
const _SALT_YAW := 4
const _SALT_SCALE := 5
const _SALT_AXIS := 6
const _SALT_VARIANT := 7
const _SALT_COUNT := 8
const _SALT_RADIUS := 9
const _SALT_ANGLE := 10

## How a felled thing leaves the map, in seconds.
const TIP_SECONDS := 1.4
const SINK_SECONDS := 1.2
const SINK_DEPTH := 1.8
const ORE_SINK_SECONDS := 1.5
const ORE_SINK_DEPTH := 1.4


## Everything standing on one node cell, as an Array of
## `{"model": StringName, "offset": Vector3, "yaw": float, "scale": float}`.
##
## `biome`, `neighbour_biomes` and `moisture` are the same TerrainGen
## samples `model_for` has always taken; the caller feeds them once and gets
## the whole cell back, the way `GroundCover.props_for` does. One call per
## cell rather than per tree on purpose: this runs at chunk build, and a
## per-tree entry point would invite a second traversal per frame.
##
## `offset` is on the ground plane with y always 0, in units of hex_size.
## The caller adds `offset * space.hex_size` to the cell's world position
## and samples terrain height AT THAT POINT — on a slope, sampling at the
## cell centre instead is a tree standing in the air.
static func trees_for(kind: int, biome: int, neighbour_biomes: Array,
		moisture: float, cell: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count := tree_count_for(kind, biome, moisture, cell)
	var tree := _is_tree(kind)
	var near: float = MIN_OFFSET if tree else 0.0
	var far: float = MAX_OFFSET if tree else ORE_MAX_OFFSET

	for i in range(count):
		# A jittered RING rather than a uniform disk: sector i of count,
		# wandering within SECTOR_JITTER of it. Rolling the angle freely
		# would let two of a cell's trees land on top of each other, which
		# reads as one fat tree and wastes the instance — and at count 1
		# the sector is the whole circle, so a lone tree still goes
		# anywhere its offset allows.
		var wander := (1.0 - SECTOR_JITTER) / 2.0 \
			+ _roll_at(cell, _SALT_ANGLE, i) * SECTOR_JITTER
		var angle := (float(i) + wander) / float(count) * TAU
		var radius := lerpf(near, far, sqrt(_roll_at(cell, _SALT_RADIUS, i)))
		out.append({
			"model": model_for(kind, biome, neighbour_biomes, moisture, cell, i),
			"offset": Vector3(cos(angle) * radius, 0.0, sin(angle) * radius),
			"yaw": yaw_for(cell, i),
			"scale": scale_for(kind, cell, i),
		})
	return out


## How many things stand on a node cell of this ground.
##
## Ore is one seam, always. Trees spread UNIFORMLY over a range around
## `expected_trees` rather than landing on the rounded mean, because an
## equal count in every cell is the ranks-and-files problem again one scale
## up — clumps and thin patches are the whole point. Never zero: the cell
## holds a node a player must be able to see and click.
static func tree_count_for(kind: int, biome: int, moisture: float,
		cell: int) -> int:
	if not _is_tree(kind):
		return 1
	var span := maxf(0.0, 2.0 * expected_trees(biome, moisture) - 1.0)
	return mini(1 + int(_roll(cell, _SALT_COUNT) * span), MAX_PER_CELL)


## Trees on an average cell of this ground, before the spread roll above.
##
## Public because the interesting assertions are about the SHAPE of this —
## forest denser than dry grassland, wet ground denser than dry — and
## testing that through the integer count would be testing the spread.
static func expected_trees(biome: int, moisture: float) -> float:
	var base: float = BASE_TREES.get(biome, DEFAULT_TREES)
	return base * lerpf(1.0 - TREE_MOISTURE_SWING, 1.0 + TREE_MOISTURE_SWING,
		clampf(moisture, 0.0, 1.0))


## Whether this kind of node grows rather than sits — which decides both how
## many stand on a cell and how one leaves the map (see `fall_pose`).
static func _is_tree(kind: int) -> bool:
	return kind == Economy.ResourceKind.WOOD or kind == Economy.ResourceKind.FOOD


## The model a node at `cell` wears. `biome` is the cell's own ground,
## `neighbour_biomes` its six neighbours' (any order), `moisture` the
## cell's moisture sample — all client-derivable from the same TerrainGen
## the terrain mesh was built from, so the dressing agrees with the ground
## by construction.
##
## `index` is which tree of the cell this is: a cell's trees roll species
## and variant independently, so a stand is mixed the way woodland is
## rather than one model repeated at three sizes.
static func model_for(kind: int, biome: int, neighbour_biomes: Array,
		moisture: float, cell: int, index: int = 0) -> StringName:
	match kind:
		Economy.ResourceKind.FOOD:
			return &"resource_food"
		Economy.ResourceKind.GOLD:
			return &"resource_gold"
		Economy.ResourceKind.STONE:
			return &"resource_stone"

	# Wood: species follows the ground, frayed at region boundaries.
	var ground := biome
	if not neighbour_biomes.is_empty() \
			and _roll_at(cell, _SALT_MIX, index) < BOUNDARY_MIX:
		var pick: int = neighbour_biomes[
			int(_roll_at(cell, _SALT_NEIGHBOUR, index) * neighbour_biomes.size())
				% neighbour_biomes.size()]
		# Only borrow ground trees can actually grow on — a shoreline tree
		# should not roll "water" and fall back to somewhere arbitrary.
		if not _species_for(pick, moisture).is_empty():
			ground = pick

	var pool := _species_for(ground, moisture)
	if pool.is_empty():
		# A wood node on ground with no pool (a fairness top-up can put one
		# anywhere walkable): wear the generic wood tree rather than nothing.
		return &"resource_wood"

	var species: String = pool[
		int(_roll_at(cell, _SALT_SPECIES, index) * pool.size()) % pool.size()]
	var variant := int(_roll_at(cell, _SALT_VARIANT, index) * VARIANTS) % VARIANTS
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
## variation, or a forest of identical clones reads as wallpaper. `index`
## is the tree's place in its cell, so two trees a metre apart are not the
## same tree twice.
static func yaw_for(cell: int, index: int = 0) -> float:
	return _roll_at(cell, _SALT_YAW, index) * TAU


## How far a drawn man's centre must stay from a TRUNK, scaled by that
## tree's own draw scale: roughly the trunk's radius plus half the widest
## soldier body. Small on purpose — canopies overlap each other by design
## (D-108), so men walking under canopy edges is the woods working, and a
## disc sized for canopies would carve empty moats through every forest.
const TRUNK_CLEARANCE := 0.45

## Species whose FOLIAGE reaches near the ground — a conifer's skirt, not
## a canopy held overhead — so a man standing at trunk clearance is
## waist-deep in the tree. Looked at, not assumed: the first per-trunk
## clearance render showed two soldiers inside pine skirts with every
## trunk correctly clear. These take the wider disc below; broadleaf
## species keep the trunk disc, because walking under a held-up canopy is
## the woods working (D-108).
const SKIRTED_SPECIES: Array[String] = ["pine", "spruce", "swamp_cypress"]
const SKIRT_CLEARANCE := 0.85


## The clearance discs one node cell carries — where a drawn man may NOT
## stand — as {offset (world units, relative to the cell centre), radius}.
##
## Per TRUNK for trees, derived from the SAME `trees_for` placements the
## renderer draws, so the clearance and the picture cannot drift (D-096's
## shared-arithmetic rule). This is the fix for a playtest report of
## "models don't adhere to collision avoidance with resources": a stand's
## trees jitter between MIN_OFFSET and MAX_OFFSET of a hex (D-108), and
## the one 0.7 disc the client used to carve at the CELL CENTRE guarded
## the only spot a tree can never stand while the outer half of every
## stand sat past its rim. Ore keeps a single wide centred disc: a seam
## wanders at most ORE_MAX_OFFSET and its pile is wider than any trunk.
static func clearance_discs(kind: int, biome: int, neighbour_biomes: Array,
		moisture: float, cell: int, hex_size: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _is_tree(kind):
		out.append({"offset": Vector3.ZERO, "radius": 1.0})
		return out
	for tree in trees_for(kind, biome, neighbour_biomes, moisture, cell):
		var clearance := TRUNK_CLEARANCE
		for species in SKIRTED_SPECIES:
			if String(tree["model"]).contains(species):
				clearance = SKIRT_CLEARANCE
				break
		out.append({
			"offset": (tree["offset"] as Vector3) * hex_size,
			"radius": clearance * float(tree["scale"]),
		})
	return out


static func scale_for(kind: int, cell: int, index: int = 0) -> float:
	if not _is_tree(kind):
		return lerpf(ORE_SCALE_MIN, ORE_SCALE_MAX, _roll_at(cell, _SALT_SCALE, index))
	return lerpf(SCALE_MIN, SCALE_MAX, _roll_at(cell, _SALT_SCALE, index))


## The horizontal axis a felled tree tips around — which way it falls. Per
## tree, not per cell: a stand that all went over the same way at the same
## moment would read as a single object breaking.
static func tip_axis_for(cell: int, index: int = 0) -> Vector3:
	var angle := _roll_at(cell, _SALT_AXIS, index) * TAU
	return Vector3(cos(angle), 0.0, sin(angle))


## Where a felled thing is, `age` seconds after the felling.
##
## Trees TIP — rotate about their base to horizontal, accelerating the way
## a cut trunk does — then sink away. Ore has nothing to tip, so it only
## sinks. Returned as parts ({"angle", "sink", "done"}) rather than a
## finished Transform3D so the caller composes them with the standing yaw
## and scale it already applies, and so this stays trivially assertable.
static func fall_pose(kind: int, age: float) -> Dictionary:
	if not _is_tree(kind):
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


## The same roll for tree `index` of a cell. A third mixed input rather
## than `salt + index`, which would make tree 0's yaw stream and tree 1's
## scale stream the same numbers whenever two salts sit one apart —
## GroundCover._roll_at's reasoning, and the same arithmetic.
static func _roll_at(cell: int, salt: int, index: int) -> float:
	var h := 0x811C9DC5
	h = ((h ^ (cell & 0xFFFFFFFF)) * _FNV_PRIME) & 0xFFFFFFFF
	h = ((h ^ (salt & 0xFFFFFFFF)) * _FNV_PRIME) & 0xFFFFFFFF
	h = ((h ^ (index & 0xFFFFFFFF)) * _FNV_PRIME) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * _FNV_PRIME) & 0xFFFFFFFF
	return float(h & 0xFFFFFF) / float(0x1000000)

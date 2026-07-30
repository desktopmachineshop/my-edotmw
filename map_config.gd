extends Resource
class_name MapConfig

## Map parameters as data, not constants (CLAUDE.md: everything that can
## be data-driven should be). Lives in /maps/*.tres so a map can be added
## or resized without touching a script.
##
## Kept deliberately small for M1: this is map *dimensions*, not terrain
## generation, which is out of M1's scope (D-022). Terrain-gen parameters
## join this resource when they land rather than getting their own file.

@export var id: StringName = &"default"
@export var display_name: String = ""

# Torus dimensions in hex cells. `height` must be even — see D-008's row
# parity, enforced by validate() and by the map test suite so a bad value
# fails the build rather than misaligning the seam at runtime.
#
# 128x64 as of M3 (D-036). The old 64x32 was too small to exercise the
# things M3 is meant to demonstrate: M2's load test gated only 5 of 48
# squads, because one squad's vision covers ~169 cells and twelve squads
# could nearly blanket a 2,048-cell map.
@export var width: int = 128
@export var height: int = 64
@export var hex_size: float = 1.0

# How many squads each connecting player is given at spawn. M3's cut line
# is ~12-15 per player (D-015); full scale is ~50 (D-018).
@export var squads_per_player: int = 12

## Hard per-player squad ceiling (D-033). Covers military and gatherer
## squads alike — one shared cap, so every villager crew is an army slot
## not spent. That makes the economy-versus-army trade structural rather
## than a balance number, and it bounds total squad count, which is the
## axis the architecture is actually sensitive to (D-018).
@export var squad_cap: int = 15

## How many times terrain repeats along each axis, and therefore how many
## symmetric starting positions the map has (D-036). Must match
## TerrainGen.axis_repeats, or the spawns will be symmetric while the
## terrain under them is not.
##
## 2 means four identical quadrants and four fair spawns. Player capacity
## is the square of this, which is why changing the supported player count
## is a map-generation change rather than a config tweak.
@export var symmetry_order: int = 2

## Where a player spawns *within its quadrant*. The actual spawn points
## are derived from this by tiling it across the quadrants (see
## spawn_points), so all players necessarily start at the same relative
## position on identical terrain. Authoring four points separately would
## let them drift apart; deriving them cannot.
@export var spawn_offset: Vector2i = Vector2i(16, 8)


func to_space() -> TorusSpace:
	return TorusSpace.new(width, height, hex_size)


## How many players this map seats — one per symmetric quadrant.
func player_capacity() -> int:
	return symmetry_order * symmetry_order


## The starting cell for each player, tiled across the symmetric
## quadrants. Fair by construction: every point is the same offset into a
## quadrant, and the quadrants are bit-identical terrain (D-036).
##
## Ordered so player 0 and player 1 are diagonally opposite rather than
## adjacent, which is the sensible default for a 4-player free-for-all.
func spawn_points() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var quadrant_width := width / maxi(symmetry_order, 1)
	var quadrant_height := height / maxi(symmetry_order, 1)
	for qy in range(symmetry_order):
		for qx in range(symmetry_order):
			out.append(Vector2i(
				spawn_offset.x + qx * quadrant_width,
				spawn_offset.y + qy * quadrant_height))
	return out


## Returns "" if valid, else the reason. Delegates the geometry rules to
## TorusSpace so there is one definition of a legal torus, not two.
func validate() -> String:
	var space_error := to_space().validate()
	if space_error != "":
		return space_error
	if squads_per_player <= 0:
		return "squads_per_player must be positive (got %d)" % squads_per_player

	if squad_cap < squads_per_player:
		# Otherwise a player is over its own ceiling the instant it spawns,
		# and the first thing the cap does is forbid something that already
		# happened.
		return "squad_cap (%d) must be at least squads_per_player (%d)" % [squad_cap, squads_per_player]

	if symmetry_order < 1:
		return "symmetry_order must be at least 1 (got %d)" % symmetry_order
	if width % symmetry_order != 0 or height % symmetry_order != 0:
		return "symmetry_order (%d) must divide both width (%d) and height (%d), or the quadrants are not identical" % [
			symmetry_order, width, height]

	# Each quadrant's height must itself be even, not merely the map's.
	# D-008's row parity is what makes the seam line up; a quadrant with
	# odd height shifts parity across the repeat boundary, so the terrain
	# would be numerically symmetric while neighbour relationships across
	# the seam were not.
	if (height / symmetry_order) % 2 != 0:
		return "height / symmetry_order (%d) must be even for row parity (D-008)" % (height / symmetry_order)

	if spawn_offset.x < 0 or spawn_offset.y < 0:
		return "spawn_offset must be non-negative (got %s)" % spawn_offset
	if spawn_offset.x >= width / symmetry_order or spawn_offset.y >= height / symmetry_order:
		return "spawn_offset %s must lie inside one quadrant (%dx%d)" % [
			spawn_offset, width / symmetry_order, height / symmetry_order]

	return ""


func is_valid() -> bool:
	return validate() == ""

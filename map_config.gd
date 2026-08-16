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
@export var symmetry_order: int = 1

## How many starting positions the map offers. Players take them in join
## order and wrap, so a 4-player match uses the first four of these.
@export var player_slots: int = 20

## Closest two starting positions may be, in cells.
##
## Spawns are scattered RANDOMLY rather than laid out on a grid, so that
## who ends up next to whom differs every match and the map grows natural
## flashpoints — two players sharing a valley, someone isolated behind
## mountains. A grid gave every match the same neighbours at the same
## distances, which made the opening the same conversation every time.
##
## The minimum spacing is what keeps "random" from meaning "two players
## on top of each other". It is the only guarantee spacing gives;
## resource fairness is separately handled by
## Economy.balance_for_spawns.
@export var min_spawn_spacing: int = 12

## Fixed so a map's spawns are the same every run — replays depend on it
## (D-016), and so does a client being told where players start.
@export var spawn_seed: int = 20260801

## Smallest connected patch of walkable ground a start may sit on, in
## cells (D-101).
##
## A spawn used to be accepted on the strength of its OWN cell being
## passable, which says nothing about what surrounds it. On `islands`,
## where ~70% of the map is water, that seated one player in twenty on a
## SIX-CELL rock: legal ground, and a dead player — six cells cannot hold
## a town hall and the resources to work, and D-031 means the founding
## party is the entire opening. It was visible from orbit and invisible to
## every check, because `validate_spawns` compares COUNTS and twenty of
## twenty points were found.
##
## Measured across four presets x four sizes x three seeds: 96 rejects
## every stranded start the sweep found while still seating 20 players on
## `islands` at Standard and above. Smaller maps are bounded by
## `min_spawn_spacing` long before they are bounded by this.
##
## Zero disables the check, which is what a caller with no terrain gets
## anyway — the flood fill needs `passable` to mean anything.
@export var min_spawn_landmass: int = 96

## How far from a spawn resources must be topped up, and how many of each
## kind a start is guaranteed (D-036 revised). This is what replaces
## quadrant symmetry as the fairness mechanism: generate freely, then make
## sure nobody starts with no wood in reach.
## Kept inside a starting unit's vision_range (~12): a guaranteed
## resource the player cannot SEE is not a guarantee. With nodes four
## times sparser (D-056 follow-up) the AI stopped finding wood at all —
## 3,248 food against 180 wood — and never afforded a barracks.
@export var fairness_radius: int = 9
@export var fairness_quota: int = 1

# What a player starts with (D-028). Non-zero on purpose: gatherers cost
# food, and food comes from gatherers, so a player starting empty could
# never begin. A starting stockpile is the usual way out and keeps the
# opening a choice — spend it on economy or on soldiers.
@export var starting_food: int = 250
@export var starting_wood: int = 200
@export var starting_gold: int = 0
@export var starting_stone: int = 0


func to_space() -> TorusSpace:
	return TorusSpace.new(width, height, hex_size)


## How many players this map seats.
func player_capacity() -> int:
	return player_slots


## The starting cell for each player: scattered at random, no two closer
## than `min_spawn_spacing` (D-039).
##
## Spawn placement is INDEPENDENT of terrain symmetry (D-036, revised),
## and as of D-039 it is not a grid either. A grid gave every match the
## same neighbours at the same distances; random placement means who you
## end up beside — and who ends up sharing a resource hotspot with you —
## differs every match. That is the point: the flashpoints should come
## from the map, not from a layout decided once.
##
## Fairness survives this in two pieces that are deliberately separate:
## `min_spawn_spacing` here bounds how close anyone can be placed, and
## `Economy.balance_for_spawns` guarantees each start a minimum of every
## resource within reach. Neither tries to do the other's job.
##
## Pass `passable` (indexed by TorusSpace.index) to keep starts off water
## and mountain. A grid never needed this — it could be authored onto
## known-good ground. Random placement cannot, so an unpassable spawn is
## a live failure mode rather than a hypothetical one, and the caller
## that has the terrain is the one that must supply it.
##
## Passable is necessary and NOT sufficient (D-101): a candidate must
## also stand on a landmass of at least `min_spawn_landmass` cells, or a
## start can be legal ground and still be a six-cell rock in the sea.
##
## Deterministic: same `spawn_seed` and same terrain give the same
## points, every run. Replays (D-016) depend on that.
func spawn_points(passable := PackedByteArray()) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if player_slots <= 0:
		return out

	var space := to_space()
	var rng := RandomNumberGenerator.new()
	rng.seed = spawn_seed

	# Rejection sampling. The attempt ceiling is what stops an
	# over-constrained map (too many slots, too much spacing, too little
	# dry land) from spinning forever — it returns fewer points instead,
	# and `validate_spawns` is what turns that into a visible error
	# rather than a silently short-seated match.
	var attempts := 0
	var ceiling := player_slots * 500
	while out.size() < player_slots and attempts < ceiling:
		attempts += 1
		var cell := Vector2i(rng.randi_range(0, width - 1), rng.randi_range(0, height - 1))

		if not passable.is_empty():
			var index := space.index(cell)
			if index >= 0 and index < passable.size() and passable[index] == 0:
				continue

		var far_enough := true
		for existing in out:
			# Toroidal distance, so spacing holds across the seam too —
			# otherwise two players either side of the wrap would read as
			# a map apart while standing next to each other.
			if space.distance(existing, cell) < min_spawn_spacing:
				far_enough = false
				break
		if not far_enough:
			continue

		# Landmass LAST, though it is a property of the candidate alone:
		# it is the only test here that is not O(1)-ish, and the two above
		# reject the overwhelming majority of candidates on exactly the
		# maps where it matters. The three are an AND, so the order
		# changes nothing but the cost — and the cost is real. Sampling 20
		# starts on the over-packed Skirmish maps (20 slots on 2,016 cells,
		# where the sampler burns its whole attempt ceiling) measured
		# 1.0-3.5 s with the fill first and 0.2-0.4 s with it last.
		if not passable.is_empty() and _landmass_at(space, cell, passable) < min_spawn_landmass:
			continue

		out.append(cell)

	return out


## How much walkable ground `cell` is connected to, counting no further
## than `min_spawn_landmass` (D-101).
##
## Capped rather than exhaustive, which is the whole reason this is cheap
## enough to run per candidate: a real landmass stops the fill at the cap
## after visiting that many cells, and an islet stops it by running out
## of island. Nothing here needs the true size — only whether it clears
## the bar.
##
## A flood fill, not a disk, for `Economy._reachable_from`'s reason:
## passability is not reachability, and a start with plenty of dry land
## across a channel is still a start on a rock.
func _landmass_at(space: TorusSpace, cell: Vector2i, passable: PackedByteArray) -> int:
	if min_spawn_landmass <= 1:
		return min_spawn_landmass

	var seen := {space.index(cell): true}
	var queue := [cell]
	var head := 0
	while head < queue.size() and seen.size() < min_spawn_landmass:
		var at: Vector2i = queue[head]
		head += 1
		for neighbour in space.neighbors(at):
			var index := space.index(neighbour)
			if seen.has(index):
				continue
			if index < passable.size() and passable[index] == 0:
				continue
			seen[index] = true
			queue.append(neighbour)
			if seen.size() >= min_spawn_landmass:
				break
	return seen.size()


## Returns "" if the map can actually seat everyone it claims to.
##
## Separate from validate() because it needs terrain, which the resource
## alone does not have. Kept explicit so a short seating is reported at
## startup rather than discovered as players quietly sharing a cell.
func validate_spawns(passable := PackedByteArray()) -> String:
	var got := spawn_points(passable).size()
	if got < player_slots:
		return "map seats %d of %d players at spacing %d — lower min_spawn_spacing, lower player_slots, or enlarge the map" % [
			got, player_slots, min_spawn_spacing]
	return ""


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
		return "symmetry_order (%d) must divide both width (%d) and height (%d), or the repeats do not line up" % [
			symmetry_order, width, height]

	# A repeat's height must itself be even, not merely the map's. D-008's
	# row parity is what makes the seam line up; an odd-height repeat
	# shifts parity across the boundary, so the terrain would be
	# numerically periodic while neighbour relationships were not.
	if (height / symmetry_order) % 2 != 0:
		return "height / symmetry_order (%d) must be even for row parity (D-008)" % (height / symmetry_order)

	if player_slots < 1:
		return "player_slots must be at least 1 (got %d)" % player_slots
	if min_spawn_spacing < 1:
		return "min_spawn_spacing must be at least 1 (got %d)" % min_spawn_spacing
	if min_spawn_landmass < 0:
		return "min_spawn_landmass must be non-negative (got %d)" % min_spawn_landmass

	# Whether random placement can *actually* satisfy the spacing is a
	# packing question, and rejection sampling answers it by failing to
	# terminate usefully rather than by saying so. This is the cheap
	# necessary condition, checked up front: disjoint hex disks of half
	# the spacing, one per slot, must fit in the map at all. It cannot
	# prove a layout exists, but it catches the configuration that asks
	# for one that cannot.
	var radius := min_spawn_spacing / 2
	var disk := 3 * radius * radius + 3 * radius + 1
	if player_slots * disk > width * height:
		return "%d spawns at spacing %d cannot fit a %dx%d map (needs ~%d cells of %d)" % [
			player_slots, min_spawn_spacing, width, height, player_slots * disk, width * height]

	if fairness_quota < 0 or fairness_radius < 1:
		return "fairness_radius must be positive and fairness_quota non-negative"

	return ""


func is_valid() -> bool:
	return validate() == ""

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

## Which `/terrain` preset this map's ground is generated from. EMPTY —
## every map that shipped before this one — means "whatever the settings
## default to", so nothing about `default`, `huge` or `ladder` moves.
##
## The file header above says terrain generation is out of scope and that
## its parameters "join this resource when they land". This is the
## smallest form of that: not the parameters, just WHICH preset, because
## a map's identity and its terrain cannot be separated and the naval gate
## is what proved it. `maps/isles.tres` exists to make the AI want a navy;
## selected by dimensions alone it generated a CONTINENTS world at isles
## dimensions — one landmass, `wants_navy = 0` correctly, and a gate that
## passes green having tested nothing. That is D-076's lesson exactly: a
## gate that cannot fire is a gate that lies.
##
## `--preset=` still overrides this, because `server.gd` applies the
## override first and then resolves whatever `_settings.preset` ends up
## as — so a dev can still point any map at any ground.
@export var preset: StringName = &""

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
## cells (D-104).
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
##
## As of #128 this is a FLOOR on one number and no longer the whole rule.
## An absolute size cannot express "isolated": 96 is 1.19% of the shipped
## Standard map and 0.29% of the Huge one, so a start could clear it
## comfortably and still share its landmass with nobody. The rule that
## actually prevents that is CONNECTIVITY — see `spawn_points` — and it
## is scale-free, which is why this constant was left where the D-104
## sweep put it rather than being re-expressed as a fraction. Setting it
## to 1 or less turns BOTH landmass rules off together: a caller asking
## for no size bar is asking for the placement that predates D-104, and
## splitting the two switches would leave a map able to seat a player on
## a rock the size bar was the only thing forbidding.
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
## Passable is necessary and NOT sufficient (D-104): a candidate must
## also stand on a landmass of at least `min_spawn_landmass` cells, or a
## start can be legal ground and still be a six-cell rock in the sea.
##
## And a big enough landmass is not sufficient either (#128): every start
## must stand on the SAME one. D-104's bar is an absolute size, so it
## says nothing about whether the component holding spawn A also holds
## spawn B — a player could be seated alone on a perfectly roomy island,
## unable to attack or be attacked, which under D-033 leaves the match
## undecidable by elimination and reports as a draw at the time cap. That
## is D-055's silent stalemate reached by a second door, and `ai_ladder`
## would blame the AI for it. So the mainland — the LARGEST walkable
## component, ties to the one discovered first in cell-index order — is
## the only ground this samples from.
##
## The connectivity test is O(1) per candidate because the components are
## labelled ONCE, before sampling, rather than flooded per candidate.
## That also retires D-104's cost trade (it measured 1.0-3.5 s with the
## capped fill first against 0.2-0.4 s with it last): one pass over the
## field is cheaper than the capped fills it replaces, and it reports
## component sizes EXACTLY where the capped fill could only answer
## "at least 96".
##
## Deterministic: same `spawn_seed` and same terrain give the same
## points, every run. Replays (D-016) depend on that.
func spawn_points(passable := PackedByteArray(),
		navigable := PackedByteArray()) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if player_slots <= 0:
		return out

	var space := to_space()
	var rng := RandomNumberGenerator.new()
	rng.seed = spawn_seed

	# Labelled once, before a single candidate is drawn. `mainland` is -1
	# when the landmass rules are off (no terrain, or the caller asked for
	# the pre-D-104 placement), and `_mainland_of` returns -1 again when no
	# component on this map clears `min_spawn_landmass` — in which case
	# nothing is placed at all and `validate_spawns` says so out loud,
	# which is what the old rule did too: the largest component is at
	# least as big as every other, so a map whose biggest island is under
	# the bar seated nobody before this change either.
	var labels := PackedInt32Array()
	var mainland := -1
	if not passable.is_empty() and min_spawn_landmass > 1:
		var components := walkable_components(space, passable)
		labels = components["labels"]
		mainland = _mainland_of(components["sizes"], min_spawn_landmass)
		if mainland < 0:
			return out

	# REACHABILITY IS THE LAND-AND-WATER GRAPH NOW (naval stage 9, #301).
	#
	# #128 required every start to share ONE walkable component, because an
	# army that cannot walk to its enemy is a match nobody can finish, and
	# that is what retired `islands` — 12 to 268 components, and as little
	# as 7.8% of the map on the mainland.
	#
	# Ships change what "reachable" means, not whether it is required. Two
	# starts on different islands are mutually reachable if a hull can sail
	# between them, so the rule becomes: every start in the same component
	# of the graph where a cell is traversable if it is passable OR
	# navigable. On a dry map that graph is the walkable one and this is
	# exactly #128's rule; on a wet one it is the whole world.
	#
	# `reach` is a SECOND labelling rather than a widened first one,
	# because the two answer different questions and both are needed:
	# `labels`/`mainland` still enforce D-104's "a start needs ground
	# enough to build on", which water can never satisfy however well
	# connected it is.
	var reach := PackedInt32Array()
	var reach_home := -1
	if not navigable.is_empty() and not passable.is_empty():
		reach = _reachable_components(space, passable, navigable)
		if mainland >= 0:
			reach_home = _first_reach_label_on(labels, reach, mainland)

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
			# Same landmass as everyone else (#128). Folded in here rather
			# than left where D-104's flood fill was, because it is now a
			# single array read: the ordering argument that put the size
			# test last was entirely about its cost, and that cost is gone.
			# The three tests are an AND, so moving one changes what a
			# candidate costs and never whether it is accepted — and the
			# rng is drawn once at the top of the loop, so the point
			# sequence for a given seed is untouched by the reordering.
			# A start still needs ground enough to build on (D-104), and
			# that is its OWN landmass rather than the mainland once water
			# connects them: an island of `min_spawn_landmass` cells is a
			# home if a ship can reach it.
			if mainland >= 0 and reach_home < 0 and (index < 0
					or index >= labels.size() or labels[index] != mainland):
				continue
			if reach_home >= 0:
				if index < 0 or index >= reach.size() or reach[index] != reach_home:
					continue
				if not _landmass_is_big_enough(labels, index):
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

		out.append(cell)

	return out


## Every walkable component of `passable`, wrap-aware (#128).
##
## Components of the graph an ARMY WITH SHIPS can move through: a cell is
## traversable if it is passable OR navigable (naval stage 9).
##
## One flood fill over the union, not two fills stitched together — a
## shore cell is in both arrays and is what joins an island to the sea, so
## the union is connected exactly where a landing is possible and nowhere
## else. That is the whole rule, and expressing it as one graph is what
## keeps it from needing a second "and can they meet" pass afterwards.
##
## Reuses `walkable_components`' own walk by handing it the union array,
## so there is ONE definition of a component on this map and the naval
## question cannot drift from the land one.
static func reachable_components(space: TorusSpace, passable: PackedByteArray,
		navigable: PackedByteArray) -> PackedInt32Array:
	return _reachable_components(space, passable, navigable)


static func _reachable_components(space: TorusSpace, passable: PackedByteArray,
		navigable: PackedByteArray) -> PackedInt32Array:
	var union := PackedByteArray()
	union.resize(space.cell_count())
	for index in range(space.cell_count()):
		var wet := index < navigable.size() and navigable[index] != 0
		var dry := index < passable.size() and passable[index] != 0
		union[index] = 1 if (wet or dry) else 0
	return walkable_components(space, union)["labels"]


## Which reach-component the mainland sits in — the one every start must
## share. Taken from the mainland rather than from the first start, so the
## answer does not depend on which candidate the rng drew first.
static func _first_reach_label_on(labels: PackedInt32Array,
		reach: PackedInt32Array, mainland: int) -> int:
	for index in range(mini(labels.size(), reach.size())):
		if labels[index] == mainland:
			return reach[index]
	return -1


## Does the landmass under `index` clear `min_spawn_landmass`? D-104's
## size bar, asked of the start's OWN island now that the mainland is no
## longer the only legal home.
func _landmass_is_big_enough(labels: PackedInt32Array, index: int) -> bool:
	if labels.is_empty() or index < 0 or index >= labels.size():
		return false
	var want := labels[index]
	if want < 0:
		return false
	var n := 0
	for other in range(labels.size()):
		if labels[other] == want:
			n += 1
			if n >= min_spawn_landmass:
				return true
	return false


## Returns `{"labels": PackedInt32Array, "sizes": PackedInt32Array}`:
## one label per cell, -1 where the ground is not walkable, and the exact
## cell count of each component. This REPLACES D-104's per-candidate
## capped flood fill, which could only ever answer "at least
## `min_spawn_landmass`" — it returned 96 for a 96-cell rock and for a
## 20,000-cell continent alike, so no caller could have asked it whether
## two starts shared a landmass even if one had wanted to.
##
## One pass over the field rather than one per candidate — but NOT free,
## and the decision entry has the table rather than an argument. It is
## faster than the fills it replaces on the two small map sizes and on
## every `islands` world, and slower at the top of the ladder (Huge
## `continents`: 16.6 ms for the whole old sampler against 61.5 ms now),
## because the old cost was dominated by rejection sampling and was
## near-flat in map size. The shipped default map is 12.9 -> 13.3 ms.
##
## Wrap-aware, and it pays the torus tax (D-008) in ARITHMETIC rather
## than through `TorusSpace.neighbor_table`. The table is the right answer
## for the flow-field solver, which walks the same lattice thousands of
## times per match and amortises the build away
## (D-20260818-the-flow-field-solver-was-93-percent-neighbour-lookup);
## it is the wrong answer here, because `to_space()` mints a fresh
## `TorusSpace` per call and this walk visits each cell ONCE. Measured on
## the Huge map (336x388, 130,368 cells), a table-backed component pass
## cost 76.0 ms against 16.6 ms for the whole of the sampler this
## replaces — most of it spent building a 3.1 MB table to read each entry
## a single time.
##
## The six offsets are `TorusSpace.DIRECTIONS` inlined against this
## file's own index layout (`index(c) == c.y * width + c.x`); a test pins
## them against `TorusSpace.neighbors` so the copy cannot drift, which is
## the same bargain `TerrainGen._carve_ramps` already makes for its own
## component walk.
##
## Deterministic: components are discovered in cell-index order and each
## frontier expands in direction order, so labels are a property of the
## field rather than of visit luck, and both sides of the wire and every
## replay (D-016) agree.
##
## A cell past the end of `passable` reads as walkable, matching every
## other passability test here — a caller with a short array has supplied
## no opinion about those cells rather than a negative one.
static func walkable_components(space: TorusSpace, passable: PackedByteArray) -> Dictionary:
	var w := space.width
	var h := space.height
	var count := w * h
	var labels := PackedInt32Array()
	var sizes := PackedInt32Array()
	if count <= 0:
		return {"labels": labels, "sizes": sizes}
	labels.resize(count)
	labels.fill(-1)

	var known := passable.size()
	for start in range(count):
		if labels[start] >= 0:
			continue
		if start < known and passable[start] == 0:
			continue
		var id := sizes.size()
		var size := 0
		labels[start] = id
		var frontier := PackedInt32Array([start])
		while not frontier.is_empty():
			var at := frontier[frontier.size() - 1]
			frontier.resize(frontier.size() - 1)
			size += 1
			var y := at / w
			var x := at - y * w
			var east := x + 1 if x + 1 < w else 0
			var west := x - 1 if x > 0 else w - 1
			var north := (y - 1 if y > 0 else h - 1) * w
			var south := (y + 1 if y + 1 < h else 0) * w
			var row := y * w
			# Unrolled rather than looped over an array literal: this is
			# the innermost line of a walk over every cell of a 130,368-
			# cell map, and building a six-element Array per cell to
			# iterate it cost half the pass. Same lesson, one layer down,
			# as the neighbour table not being worth its own construction
			# here. Written out rather than factored into a helper because
			# a GDScript Packed*Array argument is copy-on-write: a helper
			# would mutate its own copy of `labels` and the walk would
			# never terminate.
			var n := row + east
			if labels[n] < 0 and (n >= known or passable[n] != 0):
				labels[n] = id
				frontier.append(n)
			n = north + east
			if labels[n] < 0 and (n >= known or passable[n] != 0):
				labels[n] = id
				frontier.append(n)
			n = north + x
			if labels[n] < 0 and (n >= known or passable[n] != 0):
				labels[n] = id
				frontier.append(n)
			n = row + west
			if labels[n] < 0 and (n >= known or passable[n] != 0):
				labels[n] = id
				frontier.append(n)
			n = south + west
			if labels[n] < 0 and (n >= known or passable[n] != 0):
				labels[n] = id
				frontier.append(n)
			n = south + x
			if labels[n] < 0 and (n >= known or passable[n] != 0):
				labels[n] = id
				frontier.append(n)
		sizes.append(size)
	return {"labels": labels, "sizes": sizes}


## The component every start is sampled from: the LARGEST one that clears
## `minimum`, or -1 if none does (#128).
##
## Largest rather than "any that clears the bar", because the harm being
## prevented is isolation and the mainland is the one component that
## cannot be the small side of it. Ties break to the component discovered
## first, which is a fact about cell order rather than luck, so this stays
## deterministic for replays.
static func _mainland_of(sizes: PackedInt32Array, minimum: int) -> int:
	var best := -1
	for id in range(sizes.size()):
		if best < 0 or sizes[id] > sizes[best]:
			best = id
	if best < 0 or sizes[best] < minimum:
		return -1
	return best


## How many of `points` cannot walk to the first of them (#128).
##
## Public and independent of `spawn_points` on purpose: the sampler makes
## a disconnected seating impossible by construction now, and a check that
## can only be reached through the thing it is checking is a check nobody
## can watch fail. Handed a seating directly — one a test can author, or
## one a future caller placed some other way — this answers the question
## on its own terms.
##
## Zero when there is no terrain to reason about, for the same reason
## every other passability test here degrades open: an empty `passable` is
## the absence of an opinion, not a map with no ground on it.
func disconnected_spawns(points: Array[Vector2i], passable := PackedByteArray()) -> int:
	if passable.is_empty() or points.size() < 2:
		return 0
	var space := to_space()
	var labels: PackedInt32Array = walkable_components(space, passable)["labels"]
	var home := labels[space.index(points[0])]
	var stranded := 0
	for i in range(1, points.size()):
		if labels[space.index(points[i])] != home:
			stranded += 1
	return stranded


## Returns "" if the map can actually seat everyone it claims to.
##
## Separate from validate() because it needs terrain, which the resource
## alone does not have. Kept explicit so a short seating is reported at
## startup rather than discovered as players quietly sharing a cell.
func validate_spawns(passable := PackedByteArray(),
		navigable := PackedByteArray()) -> String:
	var points := spawn_points(passable, navigable)
	if points.size() < player_slots:
		return "map seats %d of %d players at spacing %d — lower min_spawn_spacing, lower player_slots, or enlarge the map" % [
			points.size(), player_slots, min_spawn_spacing]

	# A COMPLETE seating can still be a broken one (#128). The sampler
	# above cannot produce a disconnected one any more, so this is the
	# check that turns a future regression into a startup error rather
	# than into a match that runs to the time cap and reads as a draw.
	var stranded := disconnected_spawns(points, passable)
	if stranded > 0:
		return "map seats all %d players but strands %d of them on ground the others cannot walk to — a player who can neither attack nor be attacked leaves the match undecidable (D-033)" % [
			player_slots, stranded]
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

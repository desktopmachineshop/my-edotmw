extends RefCounted
class_name AiNaval

## The AI's naval question, and where a landing goes (naval plan §6.1,
## #301 stage 7).
##
## All-static and pure — `bot_patrol.gd`'s shape, for its reason: the
## half of an AI with the interesting failure mode should be testable
## without a server. Everything here takes plain fields and returns plain
## answers; `ai_player.gd` supplies what it KNOWS and acts on the reply.
##
## ## The question is about REACHABILITY, not about water
##
## "Is there an enemy I cannot walk to?" — precisely, *does my landmass
## contain a known enemy building or spawn?* On an archipelago that is
## false immediately, so the AI wants ships from the first think. On
## `continents` it is almost never false, so the whole behaviour costs
## nothing where it is not wanted, and no map needs a flag saying
## "naval".
##
## That framing is what keeps this honest about FOG. The AI answers it
## from `ClientState` — what it has been sent — so an AI that has not
## scouted an enemy yet simply does not know it cannot walk to them, and
## says no. It is not given the map. D-051's whole argument is that an AI
## win means something because the AI is a client, and an AI that quietly
## saw more would not look like a bug, it would look like a good AI.
##
## ## What it does NOT decide
##
## Which cell a ship sails through: that is stage 2's flow field. Where a
## dock may stand: that is stage 3's shore rule. This file decides
## whether to want ships, how many squads may sail, and which shore to
## aim at.


## Components, as `MapConfig.walkable_components` labels them.
##
## Its own tiny helper so the naming wart is confined: that function is
## domain-agnostic and its name is not (flagged on #216). Callers here
## read `component_of`, which says what it means.
static func component_of(labels: PackedInt32Array, cell_index: int) -> int:
	if cell_index < 0 or cell_index >= labels.size():
		return -1
	return labels[cell_index]


## Whether this AI has a reason to put an army on a boat.
##
## `home` is its own start cell; `enemy_cells` are the cells of enemy
## buildings it has been TOLD about. Land components come from
## `MapConfig.walkable_components` over the same passability the ground
## layer uses.
##
## THREE states, not two, and conflating the last two is the defect this
## function shipped with (#351, found by worker 88 on the integrated
## tree):
##
## 1. **A known enemy on my landmass** — fight them on foot. No.
## 2. **A known enemy off it** — that is what a navy is for. Yes.
## 3. **No known enemy at all** — and here the first version said "no",
##    on the argument that ignorance is not evidence of separation. That
##    is right for a land map and creates its exact MIRROR on a water
##    one: an AI cannot LEARN of an enemy across water without crossing,
##    and would not cross until it had learned. Measured on the default
##    map: four seats on 3-4 different islands, placement working, and
##    `wants_navy=0` with `enemy_buildings_seen=0` on every seat-match.
##
## So state 3 splits on whether the AI has LOOKED. Having scouted and
## found nobody, with substantial land it cannot walk to, is not
## ignorance — it is having run out of world, which is a different fact
## and wants the opposite answer.
##
## `has_scouted` is the AI's own scouting progress, not a clock: the
## question is "have I looked", and a timeout would answer "has it been a
## while" (the #69/#84 rule — legs are events).
##
## `min_landmass` is `MapConfig.min_spawn_landmass` — D-104's own
## definition of enough ground to be worth anything — reused rather than
## restated. Without it a single stray islet counts as "land I cannot
## reach", and generated maps are full of them, so every AI on every map
## would build a dock.
static func needs_ships(land_labels: PackedInt32Array, home: int,
		enemy_cells: Array, has_scouted: bool = false,
		land_sizes := PackedInt32Array(), min_landmass: int = 0) -> bool:
	var mine := component_of(land_labels, home)
	if mine < 0:
		return false

	# Knowledge outranks exhaustion: once the AI has SEEN an enemy, where
	# they are is a better answer than where they might be — in both
	# directions, and neither depends on having finished scouting.
	if not enemy_cells.is_empty():
		for cell in enemy_cells:
			if component_of(land_labels, int(cell)) == mine:
				return false
		return true

	# Nobody known. Ignorance decides nothing; exhausted search does.
	if not has_scouted:
		return false
	return _worthwhile_land_elsewhere(land_labels, land_sizes, mine, min_landmass)


## Is there a landmass I cannot walk to that is big enough to matter?
##
## Land only: `walkable_components` leaves an impassable cell unlabelled,
## so any label at all is ground somebody could stand on.
static func _worthwhile_land_elsewhere(land_labels: PackedInt32Array,
		land_sizes: PackedInt32Array, mine: int, min_landmass: int) -> bool:
	var seen := {}
	for index in range(land_labels.size()):
		var label := land_labels[index]
		if label < 0 or label == mine or seen.has(label):
			continue
		seen[label] = true
		# A component whose size we were not told is NOT counted. The
		# permissive reading — unknown means qualifying — turns a caller
		# that forgets `land_sizes` into one that funds a fleet for every
		# rock on the map, which is the same 'ignorance decides nothing'
		# rule this function already applies to `has_scouted`, and
		# `bot_naval.gd` calls needs_ships with three arguments today.
		if label < land_sizes.size() and land_sizes[label] >= min_landmass:
			return true
	return false


## Where to put an army ashore: the known enemy cell whose own landmass
## the AI cannot reach, nearest to `from`.
##
## Nearest so the crossing is short, and DETERMINISTIC on ties by cell
## index, so a replay lands the same army on the same beach — the same
## bargain `disembark` already makes when it deals riders to cells.
##
## Returns -1 when there is nothing to sail to, which the caller must
## treat as "do not embark" rather than "sail somewhere arbitrary": a
## transport that puts to sea with no destination is an army removed from
## the match by its own side.
static func landing_target(space: TorusSpace, land_labels: PackedInt32Array,
		home: int, enemy_cells: Array,
		land_sizes := PackedInt32Array(), min_landmass: int = 0) -> int:
	var mine := component_of(land_labels, home)
	var best := -1
	var best_distance := 0
	var origin := space.from_index(home)
	for cell in enemy_cells:
		var index := int(cell)
		if component_of(land_labels, index) == mine:
			continue
		var d := space.distance(origin, space.from_index(index))
		if best == -1 or d < best_distance or (d == best_distance and index < best):
			best = index
			best_distance = d
	if best >= 0:
		return best

	# NOBODY KNOWN, AND THAT IS A REASON TO SAIL RATHER THAN A REASON TO
	# STAY. `needs_ships` has three states, and its third — I have looked,
	# found nobody, and there is worthwhile land I cannot walk to — is
	# satisfied precisely when `enemy_cells` is EMPTY. Serving only the
	# known-enemy case left that AI boarding a transport with nowhere to
	# go: the header above warns that "a transport that puts to sea with
	# no destination is an army removed from the match by its own side",
	# and an AI sailing because it had run out of world walked straight
	# into it. Measured at a 1200 s cap on maps/isles.tres: docks=1,
	# ships_peak=2, embarks=1, landings=0, stuck on `naval_step=landing`.
	#
	# So it sails to FIND OUT — the nearest cell of the nearest landmass
	# it cannot walk to and that is big enough to hold a base. That is the
	# same set `_worthwhile_land_elsewhere` says yes to, so the AI lands
	# exactly where its own reason for sailing pointed.
	return _nearest_worthwhile_landfall(
		space, land_labels, land_sizes, mine, min_landmass, origin)


## The nearest cell on a landmass this side cannot walk to and that could
## hold a base.
##
## Deterministic on ties by cell index, like the enemy scan above, so a
## replay puts the same army on the same beach.
static func _nearest_worthwhile_landfall(space: TorusSpace,
		land_labels: PackedInt32Array, land_sizes: PackedInt32Array,
		mine: int, min_landmass: int, origin: Vector2i) -> int:
	var best := -1
	var best_distance := 0
	for index in range(land_labels.size()):
		var label := land_labels[index]
		if label < 0 or label == mine:
			continue
		# An unknown size does not qualify, for the same reason it does
		# not in `_worthwhile_land_elsewhere`: a caller that forgot the
		# sizes must get "nowhere to go", never "anywhere will do".
		if label >= land_sizes.size() or land_sizes[label] < min_landmass:
			continue
		var d := space.distance(origin, space.from_index(index))
		if best == -1 or d < best_distance or (d == best_distance and index < best):
			best = index
			best_distance = d
	return best


## The steps of the naval investment, in the order they must happen.
##
## Expressed through `AiInvestment` rather than as a chain of `if`s so
## that walls can reuse the shape (#337) — and so a harness can ask which
## step is next, which is what makes a zero in the gate say WHICH leg
## broke instead of merely that something did.
##
## `have` answers "have I got one of these?" for a def id; `act` is what
## the caller does. Both are Callables so this file stays free of any
## knowledge of orders, the wire or `ai_player`'s internals.
static func steps(have_dock: Callable, raise_dock: Callable,
		have_transport: Callable, train_transport: Callable,
		cargo_aboard: Callable, embark: Callable,
		landed: Callable, land: Callable) -> Array:
	return [
		AiInvestment.step("dock", have_dock, raise_dock),
		AiInvestment.step("transport", have_transport, train_transport),
		AiInvestment.step("embark", cargo_aboard, embark),
		AiInvestment.step("landing", landed, land),
	]


## How many of an AI's fighting squads may sail.
##
## `naval_commitment` is the profile knob (D-20260818-ai-profiles-are-data):
## what the AI DECIDES, never what it knows or is given, so a less
## committed difficulty keeps more of its army at home rather than being
## handed a worse fleet. (No profile is NAMED here — `test_ai_profiles`
## forbids it for the same reason `test_civs` forbids naming a civ, and
## it caught this comment doing it.) Capped by what the hull can actually carry, because an
## AI that embarked more squads than `transport_capacity` would leave the
## remainder standing on the quay believing they had sailed.
static func sailing_party(available: int, capacity: int, commitment: float) -> int:
	if available <= 0 or capacity <= 0:
		return 0
	return mini(AiInvestment.share_of(available, commitment), capacity)

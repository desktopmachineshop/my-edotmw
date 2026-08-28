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


## Whether every enemy thing this AI KNOWS ABOUT is off its own landmass.
##
## `home` is the AI's own start cell; `enemy_cells` are the cells of
## enemy buildings and spawns it has been told about. Land components
## come from `MapConfig.walkable_components` over the same passability
## the ground layer uses.
##
## **Returns false when it knows of no enemy at all**, and that is the
## load-bearing case rather than an edge one. "I have seen nothing, so
## there must be an ocean between us" is how an AI on a perfectly
## ordinary land map would talk itself into a navy before it had scouted
## — and it would then read as an AI that does nothing for two minutes.
## No knowledge is not evidence of separation.
static func needs_ships(land_labels: PackedInt32Array, home: int,
		enemy_cells: Array) -> bool:
	if enemy_cells.is_empty():
		return false
	var mine := component_of(land_labels, home)
	if mine < 0:
		return false
	for cell in enemy_cells:
		if component_of(land_labels, int(cell)) == mine:
			return false
	return true


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
		home: int, enemy_cells: Array) -> int:
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

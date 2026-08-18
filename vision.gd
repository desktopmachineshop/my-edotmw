extends RefCounted
class_name Vision

## Per-player vision field over cells (D-025 part 1), closing D-022's
## "known stub: `SquadSim.visible_to()` returns every squad".
##
## ## Why a per-player field, not a per-pair test
##
## The obvious implementation — for every player, for every squad, is any
## of MY squads within range of it — is exactly the O(n^2) shape D-025
## rejects and Combat's bucket map (see combat.gd's header) rejects for
## the identical reason. At D-018's full-scale counts (~1,000 squads,
## ~50/player, 20 players) that is ~50,000 distance tests per player per
## tick, ~1,000,000 per tick across all players, against a 100 ms budget
## (D-020) that also has to cover movement, flow fields, and combat.
##
## Instead, `rebuild()` stamps each player's vision coverage ONCE, from
## that player's own squads' positions and `vision_range` — a handful of
## cells per squad, never the whole squad list. `is_visible()` then
## answers a squad's visibility with a single dictionary lookup into the
## owning player's coverage: O(1), not O(other players' squad count).
## Total rebuild cost is O(squads * radius^2 cells), the same shape as
## Combat's per-attacker disk scan, not O(players * squads^2).
##
## This is also the structure D-025's rationale names as the one
## terrain-occluded LOS would extend later rather than replace: a height
## field would change what `_stamp_squad` marks reachable, not the
## per-player-coverage / O(1)-lookup shape itself.
##
## ## Recompute frequency is decoupled from the 10 Hz tick (D-020)
##
## See `SquadSim.vision_recompute_every_ticks` for the tunable and its
## default — this class only does the stamping; SquadSim.tick() decides
## how often to call `rebuild()`.
##
## ## Wrap-awareness (D-008)
##
## Every cell stamped into coverage is `origin + offset`, run through
## `TorusSpace.index()` (which normalizes). `TorusSpace.disk_offsets()` —
## the cached hex disk `_stamp_squad` walks — is itself proven correct
## against `TorusSpace.distance()`'s ghost-copy-aware shortest distance
## (see its header); this file no longer needs to call `distance()` per
## candidate to get that guarantee. An enemy just across the seam is
## exactly as visible as one the same distance away on the same side —
## nothing here special-cases the wrap because `TorusSpace` already does.
##
## Radius-only: elevation does not occlude in M2 (D-025's explicitly
## deferred terrain-occluded LOS).

# player -> Dictionary(cell_index -> true). A Dictionary rather than a
# PackedByteArray sized to the map, matching Combat's own bucket-map
# convention (combat.gd's `_build_buckets`) — GDScript Dictionary lookups
# are the O(1) this file's header rationale is about, and staying
# consistent with the sibling file's chosen shape is worth more here than
# the marginal constant-factor win of a flat array.
var _coverage := {}


## Rebuild every player's vision coverage from scratch, from their own
## live squads' current positions and `UnitDef.vision_range`. Cleared and
## restamped rather than incrementally maintained — same rationale as
## Combat._build_buckets: SquadSim already re-derives each squad's cell
## from its curve every tick, so an incrementally-updated field would just
## be a second source of truth to keep synchronised for no real saving at
## these counts.
func rebuild(sim: SquadSim, buildings: BuildingSim = null) -> void:
	# Allies share sight (D-050). Coverage is keyed by SIDE rather than by
	# player, so a team stamps once into one field and the lookup below
	# stays a single dictionary hit — D-025 part 1's cost claim survives
	# sharing. Unioning per query instead would have made every lookup
	# O(allies), which is exactly what that claim rules out.
	_teams = sim.teams.duplicate()
	_coverage = {}
	for squad in range(sim.squad_count()):
		if sim.alive_of(squad) <= 0:
			continue
		var def := sim.def_of(squad)
		if def == null:
			continue
		# D-076: a squad standing at tier 1 sees farther, from whatever
		# structure it is standing on — purely additive, since Vision's
		# per-cell coverage has no concept of tier or elevation otherwise
		# (radius-only, per this file's own header).
		var vision_range := def.vision_range
		if buildings != null and sim.tier_of(squad) == 1:
			var standing_on := buildings.building_at(sim.cell_of(squad))
			if standing_on >= 0:
				var top_def := buildings.def_of(standing_on)
				if top_def != null:
					vision_range += top_def.top_vision_bonus
		_stamp(sim.space, _group_of(sim.owner_of(squad)), sim.cell_index_of(squad), vision_range)

	# Buildings see too (D-029). Coverage is about CELLS and does not care
	# what put a cell in it, so they stamp into the same per-player field
	# rather than needing a parallel one — which is also why a squad
	# standing next to a friendly tower gains nothing extra: the union is
	# the point.
	#
	# Rubble sees nothing, but a half-built structure does: it is a real
	# thing standing on the map with people on it.
	if buildings != null:
		for building in range(buildings.building_count()):
			if buildings.is_destroyed(building):
				continue
			var building_def := buildings.def_of(building)
			if building_def != null:
				_stamp(buildings.space, _group_of(buildings.owner_of(building)),
					buildings.cell_index_of(building), building_def.vision_range)


## O(1): a single dictionary lookup into the owning player's coverage.
## This — not a scan over the player's squads — is D-025 part 1's actual
## cost claim; `rebuild()` pays the scan once, this pays nothing per call.
func is_visible(player: int, cell_index: int) -> bool:
	var coverage = _coverage.get(_group_of(player), null)
	if coverage == null:
		return false
	return coverage.has(cell_index)


## Every side with coverage this rebuild, and the cells it covers.
##
## Exposed so `TerrainKnowledge.absorb` can fold sight into what a side
## believes the GROUND to be without walking every squad's disk a second
## time (D-20260818-pathing-knows-only-what-the-player-knows). Nothing
## else should read the raw field: `is_visible()` is the answer to "can
## this player see it".
func coverage_by_group() -> Dictionary:
	return _coverage


## Cells any of `player`'s squads currently cover. Exposed for tests that
## need to inspect the field directly (e.g. cross-checking against a
## brute-force reference); `SquadSim.visible_to()` should use
## `is_visible()`, not this.
func coverage_of(player: int) -> Dictionary:
	return _coverage.get(_group_of(player), {})


## Stamp one seeing thing's coverage. Takes a cell and a range rather than
## a squad, so a building stamps through exactly this path — the field has
## no notion of what kind of entity is looking, only which cells it can
## see (D-029).
func _stamp(space: TorusSpace, owner: int, origin_index: int, world_range: float) -> void:
	var radius_cells := _range_in_cells(space, world_range)
	if radius_cells <= 0.0:
		return

	# floori(), not ceili(): distance() returns an integer, and for an
	# integer d and float radius_cells, "d <= radius_cells" is identical to
	# "d <= floori(radius_cells)" in every case (radius_cells integral or
	# not) — so the integer floor is the exact cache key for "every cell
	# within radius_cells", not an approximation of it.
	var radius := floori(radius_cells)
	var origin := space.from_index(origin_index)
	var coverage: Dictionary = _coverage.get(owner, {})

	# TorusSpace.disk_offsets(radius) IS the hex disk of exactly the cells
	# within radius_cells — see its header for why the diamond bound needs
	# no further per-cell distance() test on top of it. index() wraps each
	# candidate, so this is correct across the seam (D-008) with zero
	# distance() calls, replacing what used to be one distance() call
	# (plus two per-call ghost-copy array allocations inside it) per cell
	# in the disk.
	for offset in TorusSpace.disk_offsets(radius):
		coverage[space.index(origin + offset)] = true

	_coverage[owner] = coverage


## World-units -> cells conversion for vision_range, mirroring
## SquadSim._cells_per_second and Combat._range_in_cells's conversion of
## move_speed/attack_range by the same hex width, so all three stats stay
## in the same intuitive world units in the data files.
static func _range_in_cells(space: TorusSpace, vision_range: float) -> float:
	var hex_width := space.hex_size * TorusSpace.SQRT_3
	if hex_width <= 0.0:
		return 0.0
	return vision_range / hex_width


# --- shared sight (D-050) ---------------------------------------------

## player -> team, copied from the sim at rebuild so a lookup here needs
## no reference back to it.
var _teams := {}


## The coverage bucket a player reads and writes.
##
## Teams share one bucket; a player with no team gets their own. Team keys
## are NEGATIVE so they cannot collide with player ids, which are always
## positive — including the AI seats, which are numbered from 1000 and
## would otherwise be a plausible team number one day.
func _group_of(player: int) -> int:
	return group_of_player(player, _teams)


## The same answer for a caller that holds the teams table itself rather
## than a rebuilt Vision: `SquadSim` keying a flow field on whose
## knowledge solved it, specifically
## (D-20260818-pathing-knows-only-what-the-player-knows). Static, and the
## ONE definition -- a second copy of this arithmetic would eventually
## disagree, and the symptom would be an ally pathing differently from you
## through ground you both explored.
static func group_of_player(player: int, teams: Dictionary) -> int:
	var team := int(teams.get(player, 0))
	return -team if team != 0 else player

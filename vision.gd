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
func rebuild(sim: SquadSim) -> void:
	_coverage = {}
	for squad in range(sim.squad_count()):
		if sim.alive_of(squad) <= 0:
			continue
		_stamp_squad(sim, sim.owner_of(squad), squad)


## O(1): a single dictionary lookup into the owning player's coverage.
## This — not a scan over the player's squads — is D-025 part 1's actual
## cost claim; `rebuild()` pays the scan once, this pays nothing per call.
func is_visible(player: int, cell_index: int) -> bool:
	var coverage = _coverage.get(player, null)
	if coverage == null:
		return false
	return coverage.has(cell_index)


## Cells any of `player`'s squads currently cover. Exposed for tests that
## need to inspect the field directly (e.g. cross-checking against a
## brute-force reference); `SquadSim.visible_to()` should use
## `is_visible()`, not this.
func coverage_of(player: int) -> Dictionary:
	return _coverage.get(player, {})


func _stamp_squad(sim: SquadSim, owner: int, squad: int) -> void:
	var def := sim.def_of(squad)
	if def == null:
		return
	var radius_cells := _range_in_cells(sim.space, def.vision_range)
	if radius_cells <= 0.0:
		return

	# floori(), not ceili(): distance() returns an integer, and for an
	# integer d and float radius_cells, "d <= radius_cells" is identical to
	# "d <= floori(radius_cells)" in every case (radius_cells integral or
	# not) — so the integer floor is the exact cache key for "every cell
	# within radius_cells", not an approximation of it.
	var radius := floori(radius_cells)
	var origin := sim.space.from_index(sim.cell_index_of(squad))
	var coverage: Dictionary = _coverage.get(owner, {})

	# TorusSpace.disk_offsets(radius) IS the hex disk of exactly the cells
	# within radius_cells — see its header for why the diamond bound needs
	# no further per-cell distance() test on top of it. index() wraps each
	# candidate, so this is correct across the seam (D-008) with zero
	# distance() calls, replacing what used to be one distance() call
	# (plus two per-call ghost-copy array allocations inside it) per cell
	# in the disk.
	for offset in TorusSpace.disk_offsets(radius):
		coverage[sim.space.index(origin + offset)] = true

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

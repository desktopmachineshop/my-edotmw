extends RefCounted
class_name Combat

## Squad-vs-squad combat resolution, server-only (D-024). Owned by
## SquadSim, which calls `resolve()` once per tick and applies whatever it
## returns.
##
## ## Why a bucket map, not a pairwise scan
##
## The naive approach — for every squad, test every other squad — is
## exactly the O(n^2) scan D-025 part 1 rejects for vision, and the same
## cost argument applies here unchanged: at D-018's ~1,000-squad full
## scale, a per-pair scan is ~1,000,000 distance tests every tick, against
## a 100 ms budget (D-020) that also has to cover movement, flow fields,
## and (per D-025) vision. This file instead rebuilds a cell-index ->
## squad-ids bucket map once per round (`_build_buckets`) and, for each
## squad, scans only the hex disk of cells within its OWN engagement
## radius (`_find_target`) — a handful of cells for a melee unit, a few
## dozen for an archer, never the whole map and never the whole squad
## list. Cost is O(squads * radius^2), not O(squads^2).
##
## ## Determinism (D-016, D-026 criterion 2)
##
## Every stochastic roll is a pure function of (seed, tick, squad id) —
## `_roll_unit` — rather than a draw from one shared mutable RNG stream.
## A shared stream would reproduce fine as long as nothing ever reorders
## iteration, but the counter-based form reproduces even if it later does,
## which is the more durable property to have banked. `seed` is
## `SquadSim.combat_seed`, set by the server from map configuration (see
## `NetProtocol.seed_from` and `server.gd`) — never from
## `Time.get_ticks_usec()`. A wall-clock seed would make a replay replay a
## *different* battle than the one that actually happened, defeating the
## one thing D-016 exists for.
##
## ## What this file does not do
##
## It never stores a soldier's position, health, or target — only
## aggregate per-squad state that already lives in SquadSim's packed
## arrays (`_alive`, `_morale`, `_routed`, `_damage_accum`,
## `_last_attack_tick`), which is exactly what D-006 clause 1 permits
## Formation to keep deriving from. Casualties are integer decrements to
## `alive`; `Formation.slot_offset` restamps the survivors on the next
## derivation with no work here at all (D-006 clause 3, and D-024's
## decisive detail that `alive` is the only formation input a death
## changes).

# How many extra cells a routed squad's flee order reaches past its
# current separation from the squad that broke it. A heuristic for "get
# away from here", not a tuned game-balance number.
const ROUT_FLEE_MULTIPLIER := 3

# The squad pass's bucket map, kept so the buildings pass in the same
# tick does not rebuild an identical one.
var _buckets := {}
var _buckets_tick := -1

# Squads that found an enemy SQUAD to fight this tick, so the siege pass
# can leave them to it. Cleared at the top of each round.
var _engaged := {}

const _FNV_OFFSET_BASIS := 2166136261
const _FNV_PRIME := 16777619


## Resolve one tick of combat over `sim`. `tick` and `dt` come from the
## sim's own clock (D-020's fixed 10 Hz step) — never wall-clock.
##
## Returns the squads whose `alive` or routed state actually changed this
## tick, which is exactly the sparse event SquadSim replicates (D-026
## criterion 3). It is computed as a before/after diff over every squad
## rather than accumulated opportunistically while resolving attacks, so
## "no target found", "attacked but the roll produced zero casualties",
## and "recovered morale but stayed above the rally margin" all correctly
## produce nothing to send — the diff can't accidentally report a change
## that didn't happen, because it only ever looks at final state.
func resolve(sim: SquadSim, tick: int, dt: float) -> Array:
	var before_alive := sim.alive_snapshot()
	var before_routed := sim.routed_snapshot()

	_recover_morale_and_check_rally(sim, dt)

	# The round is SIMULTANEOUS (D-024 amendment). Every attack this tick
	# reads strength and rout state as they stood at the start of the
	# round, not as they stand part-way through it.
	#
	# This used to read live state, which made the round sequential in
	# squad-id order: squad 0 killed part of squad 5, and squad 5 then
	# answered at reduced strength. It was deterministic, so replays were
	# fine — but it was not neutral. Identical unit types share an
	# attack_interval and both start at _last_attack_tick = -1, so they
	# fire on the same ticks indefinitely and the bias never averages out.
	# Squads are spawned in join order, so player 1 systematically won
	# mirror engagements. Reading the snapshot removes id order from the
	# outcome entirely.
	#
	# Taken AFTER the rally pass so a squad that rallies this tick can act
	# this tick; `before_routed` above is the pre-rally state, which is
	# what the event diff needs.
	var round_alive := sim.alive_snapshot()
	var round_routed := sim.routed_snapshot()

	var buckets := _build_buckets(sim)
	_engaged.clear()

	# Kept for the buildings pass, which runs later in the same tick and
	# would otherwise rebuild an identical map. Wiring the two passes
	# together like this is what stopped adding buildings from doubling
	# combat's share of the tick.
	_buckets = buckets
	_buckets_tick = tick

	for attacker in range(sim.squad_count()):
		if round_alive[attacker] <= 0 or round_routed[attacker] == 1:
			continue
		var attacker_def := sim.def_of(attacker)
		if attacker_def == null:
			continue
		var target := _find_target(sim, buckets, attacker, attacker_def)
		if target == -1:
			continue

		# Recorded for the siege pass below: a squad with a defender in
		# front of it is busy, and must not spend the same attack on a
		# wall. See resolve_squads_vs_buildings.
		_engaged[attacker] = true

		# Attack-move halts on contact (D-034). This is the one place that
		# knows contact has happened, so it is where the stance is spent —
		# sim.stop() clears the flag, so a squad that stays engaged is not
		# re-halted every tick and does not rebuild its curve every tick
		# for no change (D-003's zero-cost-when-idle).
		if sim.is_attack_moving(attacker):
			sim.stop(attacker)

		if _should_attack(sim, attacker, tick, attacker_def):
			_resolve_attack(sim, attacker, target, tick, round_alive[attacker])

	return _diff(sim, before_alive, before_routed)


## Idle squads pursue a nearby enemy instead of waiting for one to walk all
## the way into attack_range. A "for now" default aggressive stance — a
## per-squad control to opt out (hold position / passive) is future work,
## not built yet.
##
## Only squads that are genuinely idle (arrived, not already under an
## attack-move or a fresh player order), combat-capable (`damage > 0`), and
## not a worker (`carry_capacity > 0` — the same signal client.gd's own
## "Gather" action reads, so a gatherer parked on a node is never yanked
## off it to go fight) are considered. Detection radius is the squad's own
## `vision_range`, so a squad only ever reacts to something it could
## plausibly have seen — reusing `_range_in_cells` the same way `resolve()`
## and `resolve_buildings` do for their own range stats.
##
## Issuing `order_attack_move` reuses D-034's existing halt-on-contact
## machinery rather than adding a second kind of engagement: once a later
## tick's `resolve()` finds the target in actual attack_range, the squad
## halts and fights there exactly as if a player had clicked attack-move.
## `is_idle()` goes false the moment the order lands, which is what stops
## this from reissuing the same order — and rebuilding the same flow field
## — every tick a squad is already en route.
##
## Reuses this tick's bucket map and `_engaged` (from `resolve()`, called
## first every tick): a squad that already found a target standing where
## it is has nothing to chase.
func assign_idle_engagements(sim: SquadSim, tick: int) -> void:
	var buckets: Dictionary = _buckets if _buckets_tick == tick else _build_buckets(sim)
	for squad in range(sim.squad_count()):
		if sim.alive_of(squad) <= 0 or sim.is_routed(squad):
			continue
		if _engaged.has(squad) or sim.is_attack_moving(squad) or not sim.is_idle(squad):
			continue
		var def := sim.def_of(squad)
		if def == null or def.damage <= 0.0 or def.carry_capacity > 0:
			continue
		var target := _find_squad_near(sim, buckets, sim.cell_index_of(squad),
			sim.owner_of(squad), _range_in_cells(sim.space, def.vision_range))
		if target == -1:
			continue
		sim.order_attack_move(squad, sim.cell_of(target))


## Armed buildings shoot (D-032, D-029).
##
## A SEPARATE pass from the squad path, deliberately. `_resolve_attack`
## and `_check_rout` are steeped in squad assumptions — `_check_rout`
## unconditionally calls `force_move` once morale breaks, and a building
## has neither morale nor the ability to move. Making BuildingSim
## duck-type its way through squad-shaped functions would be a fine source
## of a subtle bug; sharing the bucket map and the seed convention is all
## the overlap that is safe.
##
## Written as a loop over every armed building rather than a tower special
## case, because the roster already has two shooters: the tower, and the
## town centre, which defends itself so an early rush cannot walk into a
## base before anything has been built.
##
## Cost stays O(armed buildings x disk), via the same cached hex-disk
## offsets vision and squad targeting use — never a scan over all squads.
func resolve_buildings(sim: SquadSim, buildings: BuildingSim, tick: int) -> Array:
	if buildings == null or buildings.building_count() == 0:
		return []

	var before_alive := sim.alive_snapshot()

	# Reuse the squad pass's bucket map when it is from this same tick.
	# Squad positions do not change between the two passes — combat moves
	# nobody except a routing squad, whose curve is rebuilt but whose CELL
	# is unchanged until the next tick samples it.
	var buckets: Dictionary = _buckets if _buckets_tick == tick else _build_buckets(sim)

	for building in range(buildings.building_count()):
		if not buildings.is_complete(building):
			continue  # a building site does not shoot
		var def := buildings.def_of(building)
		if def == null or def.damage <= 0.0:
			continue

		var interval_ticks := maxi(1, roundi(def.attack_interval * SquadSim.TICK_HZ))
		var last := buildings.last_attack_tick_of(building)
		if last >= 0 and tick - last < interval_ticks:
			continue

		var range_cells := _range_in_cells(sim.space, def.attack_range)
		var target := -1

		# A player-assigned focus-fire target (C2S_ORDER_BUILDING_TARGET)
		# overrides the automatic nearest-enemy pick. Cleared here the
		# moment it dies rather than left dangling, so a squad id can never
		# be silently reused for a different squad later. While it is
		# alive but OUT of range, the building holds fire rather than
		# opportunistically switching to whatever else wandered close —
		# that quiet retarget is exactly what "assign a target" is for the
		# player to avoid.
		var forced := buildings.forced_target_of(building)
		if forced != -1:
			if forced >= sim.squad_count() or sim.alive_of(forced) <= 0:
				buildings.set_forced_target(building, -1)
			else:
				var origin := sim.space.from_index(buildings.cell_index_of(building))
				var d := TorusSpace.hex_length(sim.space.delta(origin, sim.cell_of(forced)))
				if d <= range_cells:
					target = forced
				else:
					continue

		if target == -1 and buildings.forced_target_of(building) == -1:
			target = _find_squad_near(sim, buckets, buildings.cell_index_of(building),
				buildings.owner_of(building), range_cells)
		if target == -1:
			continue

		buildings.set_last_attack_tick(building, tick)
		_shoot_squad(sim, target, def.damage, buildings.cell_index_of(building))

	# Same before/after diff the squad pass uses, and for the same reason:
	# it reports only what actually changed and cannot invent an event.
	var events := []
	for i in range(sim.squad_count()):
		if sim.alive_of(i) != before_alive[i]:
			events.append({"id": i, "alive": sim.alive_of(i), "routed": sim.is_routed(i)})
	return events


## Squads shoot BACK at buildings — the other half of resolve_buildings,
## and until now the missing one.
##
## `BuildingSim.damage()` existed, was fully written, set `_dirty` so
## destruction would replicate, and was called by nothing outside its own
## tests for two milestones. Buildings were therefore indestructible, and
## the consequences were larger than they sound: a match can only be
## decided by eliminating a player (D-033), an eliminated player is one
## with nothing left, and a town centre that cannot be destroyed keeps
## producing replacements forever. Every AI ladder match ended in a draw
## at the time cap, and it was read as an AI weakness through several
## rounds of AI work. It was not. Nobody could win.
##
## That is the third time this project has shipped a declared-and-unread
## mechanic — `UnitDef.cost` went unread for two milestones, then
## `BuildingDef.cost`. The pattern is a field or method with no caller,
## and the reason it survives so long is that nothing fails: the game runs
## and simply lacks a rule.
##
## Two rules worth keeping in mind here:
##
## 1. **Defenders come first.** A squad that found an enemy squad this
##    tick is skipped entirely. Soldiers hammering a wall while being cut
##    down behind them would be a bug wearing a siege costume, and it also
##    makes defence meaningless — an attacker could ignore the garrison.
##
##    Two things enforce this and EITHER ALONE IS SUFFICIENT, which was
##    discovered by perturbing them: `_engaged` below, and the fact that
##    `_should_attack` stamps `_last_attack_tick` in the squad pass, so a
##    squad that has already swung is on cooldown when this pass reaches
##    it. Removing one leaves the test green; only removing both turns it
##    red. `_engaged` is kept anyway, and deliberately: the cooldown
##    version is implicit and holds only while both passes share one
##    attack clock, which stops being true the moment anything wants a
##    separate rate against buildings — a fairly obvious future want, and
##    a silent regression when it lands.
## 2. **Damage is continuous, not a casualty roll.** A building has
##    `max_health` as a float and no `alive` count, so there is no
##    fractional carry to keep: D-024's accumulator exists because
##    casualties must be whole soldiers, and that problem does not arise
##    here. `bonus_vs` is skipped for the same kind of reason — a
##    BuildingDef has no `armour_class`, so the counter triangle (D-032)
##    has nothing to key on and a missing lookup would silently read 1.0
##    rather than mean anything.
##
## Returns the LOCAL ids of buildings destroyed this tick.
func resolve_squads_vs_buildings(sim: SquadSim, buildings: BuildingSim, tick: int) -> Array:
	if buildings == null or buildings.building_count() == 0:
		return []

	var destroyed := []
	# Built once and shared by every attacker — that sharing is the whole
	# saving, so do not move it inside the loop.
	var building_buckets := _build_building_buckets(buildings)

	for attacker in range(sim.squad_count()):
		if _engaged.has(attacker):
			continue
		if sim.alive_of(attacker) <= 0 or sim.is_routed(attacker):
			continue
		var def := sim.def_of(attacker)
		if def == null or def.damage <= 0.0:
			continue

		var target := _find_building_near(sim, buildings, building_buckets,
			sim.cell_index_of(attacker), sim.owner_of(attacker),
			_range_in_cells(sim.space, def.attack_range))
		if target == -1:
			continue

		# Attack-move halts on contact (D-034), exactly as it does against
		# a squad — an army ordered onto a town should stop and besiege it,
		# not walk through and out the far side.
		if sim.is_attack_moving(attacker):
			sim.stop(attacker)

		if not _should_attack(sim, attacker, tick, def):
			continue

		# Same counter-based roll as _resolve_attack, so a siege is a pure
		# function of (seed, tick, squad) and reproduces in a replay.
		var roll := _roll_unit(sim.combat_seed, tick, attacker)
		var variance := clampf(def.damage_variance, 0.0, 1.0)
		var multiplier := (1.0 - variance) + 2.0 * variance * roll
		# Scaled by damage_vs_buildings (D-056): soldiers are not siege
		# engines. Unscaled, a 36-strong militia squad razed a 900 HP town
		# centre in 2.1 seconds, measured — so a base evaporated the moment
		# any army reached it and matches decided in about three minutes.
		var total := def.damage * float(sim.alive_of(attacker)) * multiplier \
			* maxf(def.damage_vs_buildings, 0.0)
		if buildings.damage(target, total):
			destroyed.append(target)
	return destroyed


## Nearest enemy building to a cell, within range, or -1. The building
## mirror of _find_squad_near, down to the deterministic lower-id
## tiebreak — but it cannot share that function's bucket map, because
## buildings live in their own id space (BuildingSim's header explains
## why mixing the two is the one genuinely dangerous thing here).
##
## Scans the attacker's own hex disk against a bucket map, NOT every
## building per squad. The first version did the latter, on the reasoning
## that buildings are far rarer than squads so a scan would beat a bucket
## rebuild. Measured at 20 players it was wrong: 120 squads x 64 buildings
## is ~7,700 `distance()` calls per tick, and `test-load 20 120` put the
## siege pass at ~15 us/squad — combat's share went 5.99 -> 24.24 us.
##
## This is the fourth time the same defect has appeared here: a
## `distance()` call per candidate cell in vision (232 -> 15 us/squad,
## M2), `UnitRoster.by_id` walking the filesystem per produced squad
## (858 ms in one tick, M4), terrain noise sampled per soldier per frame
## (M5). A hex disk is translation-invariant on a torus, so
## `TorusSpace.disk_offsets` is the cached answer, and any radius-scanning
## system should reach for it before it reaches for `distance()`.
##
## The bucket map is rebuilt once per tick and shared by every attacker,
## so its cost is O(buildings) against the O(squads x buildings) it
## replaces.
func _find_building_near(sim: SquadSim, buildings: BuildingSim, buckets: Dictionary,
		origin_index: int, owner: int, range_cells: float) -> int:
	var origin := sim.space.from_index(origin_index)
	var best := -1
	var best_distance := 0

	for offset in TorusSpace.disk_offsets(floori(range_cells)):
		var idx := sim.space.index(origin + offset)
		if not buckets.has(idx):
			continue
		for building in buckets[idx]:
			if sim.are_allied(buildings.owner_of(building), owner):
				continue
			var d := TorusSpace.hex_length(offset)
			# Deterministic tiebreak (lower id wins), the same rule
			# _find_squad_near uses, so target choice never depends on
			# dictionary iteration order.
			if best == -1 or d < best_distance or (d == best_distance and building < best):
				best = building
				best_distance = d
	return best


## Cell index -> Array of live building ids. Destroyed buildings are left
## out entirely rather than filtered later, so the scan above never sees
## rubble.
##
## A building SITE is deliberately included — a half-raised tower is a
## real thing standing on the map, and `BuildingSim.damage()` already
## takes that view. Denying an opponent a building under construction is
## the counter to walling forward.
func _build_building_buckets(buildings: BuildingSim) -> Dictionary:
	var buckets := {}
	for building in range(buildings.building_count()):
		if buildings.is_destroyed(building):
			continue
		var cell := buildings.cell_index_of(building)
		if not buckets.has(cell):
			buckets[cell] = []
		buckets[cell].append(building)
	return buckets


## Nearest enemy squad to a cell, within range. Mirrors _find_target's
## bounds and tiebreak, but takes a cell rather than an attacking squad so
## a building can use it.
func _find_squad_near(sim: SquadSim, buckets: Dictionary, origin_index: int,
		owner: int, range_cells: float) -> int:
	var origin := sim.space.from_index(origin_index)
	var best := -1
	var best_distance := 0

	for offset in TorusSpace.disk_offsets(floori(range_cells)):
		var idx := sim.space.index(origin + offset)
		if not buckets.has(idx):
			continue
		for other in buckets[idx]:
			# Allies are not targets (D-050).
			if sim.are_allied(sim.owner_of(other), owner):
				continue
			var d := TorusSpace.hex_length(offset)
			# Deterministic tiebreak (lower id wins), so target choice
			# never depends on bucket iteration order.
			if best == -1 or d < best_distance or (d == best_distance and other < best):
				best = other
				best_distance = d
	return best


## Building fire against a squad. Flat damage — BuildingDef carries no
## variance, and a fortification that rolls badly is not a mechanic
## anybody asked for.
func _shoot_squad(sim: SquadSim, squad: int, amount: float, from_cell_index: int) -> void:
	var def := sim.def_of(squad)
	if def == null:
		return

	var health := maxf(def.health, 0.001)
	var accum := sim.damage_accum_of(squad) + amount / health
	var casualties := int(floor(accum))
	sim.set_damage_accum(squad, accum - float(casualties))
	if casualties <= 0:
		return

	sim.set_alive(squad, maxi(0, sim.alive_of(squad) - casualties))
	var morale := sim.morale_of(squad) - float(casualties) * def.morale_loss_per_casualty
	sim.set_morale(squad, maxf(morale, 0.0))

	# Being shelled by a fortification breaks a squad the same way being
	# beaten by another squad does. Handled here rather than by calling
	# _check_rout, which needs an attacking SQUAD to flee from.
	if sim.is_routed(squad) or sim.alive_of(squad) <= 0:
		return
	if sim.morale_of(squad) >= def.rout_threshold:
		return
	sim.set_routed(squad, true)
	var here := sim.space.from_index(sim.cell_index_of(squad))
	var away := sim.space.delta(sim.space.from_index(from_cell_index), here)
	if away == Vector2i.ZERO:
		away = Vector2i(1, 0)
	sim.flee_move(squad, here + away * ROUT_FLEE_MULTIPLIER)


func _diff(sim: SquadSim, before_alive: PackedInt32Array, before_routed: PackedByteArray) -> Array:
	var events := []
	for i in range(sim.squad_count()):
		var routed_now := sim.is_routed(i)
		if sim.alive_of(i) != before_alive[i] or routed_now != (before_routed[i] == 1):
			events.append({"id": i, "alive": sim.alive_of(i), "routed": routed_now})
	return events


func _recover_morale_and_check_rally(sim: SquadSim, dt: float) -> void:
	for i in range(sim.squad_count()):
		if sim.alive_of(i) <= 0:
			continue
		var def := sim.def_of(i)
		if def == null:
			continue
		var morale := minf(sim.morale_of(i) + def.morale_recovery_per_second * dt, def.morale)
		sim.set_morale(i, morale)
		if sim.is_routed(i) and morale > def.rout_threshold + def.rout_rally_margin:
			sim.set_routed(i, false)


## Cell index -> Array of squad ids, live squads only. Rebuilt fresh every
## round rather than maintained incrementally: SquadSim.tick() already
## re-derives every squad's cell from its curve every tick ("the curve IS
## the state"), so an incrementally-maintained bucket map would just be a
## second source of truth to keep synchronised for no real saving at
## these counts.
func _build_buckets(sim: SquadSim) -> Dictionary:
	var buckets := {}
	for i in range(sim.squad_count()):
		if sim.alive_of(i) <= 0:
			continue
		var cell := sim.cell_index_of(i)
		if not buckets.has(cell):
			buckets[cell] = []
		buckets[cell].append(i)
	return buckets


## Nearest live enemy squad within `attacker`'s attack_range, or -1.
##
## Scans only the hex disk of radius floor(range_in_cells) around the
## attacker's own cell, via `TorusSpace.disk_offsets()` — see its header
## for why that cached table is exactly the set of cells within
## range_cells, needing no per-candidate distance() re-check.
## `TorusSpace.index()` wraps each candidate cell, so the scan is correct
## across a seam without any extra handling; if `radius` happens to
## exceed half the map's width or height the same wrapped cell can be
## visited from more than one (dq, dr) offset, which is harmless (just a
## redundant check, never a wrong answer) and not a real concern at
## plausible attack ranges relative to map size.
##
## Ranking uses each offset's own `TorusSpace.hex_length()` as `d`,
## instead of calling `TorusSpace.distance()` on the candidate. That is
## exact, not approximate: every offset in the disk already has
## hex_length() <= range_cells, and hex_length() of the DIRECT offset is
## itself one representative of the wrapped distance, so the true wrapped
## distance (the minimum over all representatives) can never exceed it.
## In the ordinary case they're equal. In the "radius past half the map"
## case where the same target is reachable via more than one offset, the
## shortest such offset is also enumerated and its hex_length() equals
## the target's true distance exactly — and because the running
## best/best_distance below only ever moves strictly down, the final
## winner converges to that true minimum regardless of enumeration order,
## so the choice (and its id tie-break) is identical to what re-deriving
## each candidate's wrapped distance() would have produced.
func _find_target(sim: SquadSim, buckets: Dictionary, attacker: int, attacker_def: UnitDef) -> int:
	var range_cells := _range_in_cells(sim.space, attacker_def.attack_range)
	var radius := floori(range_cells)
	var origin := sim.space.from_index(sim.cell_index_of(attacker))
	var owner := sim.owner_of(attacker)

	var best := -1
	var best_distance := 0

	for offset in TorusSpace.disk_offsets(radius):
		var idx := sim.space.index(origin + offset)
		if not buckets.has(idx):
			continue
		var d := TorusSpace.hex_length(offset)
		for other in buckets[idx]:
			if other == attacker or sim.are_allied(sim.owner_of(other), owner):
				continue
			# Deterministic tiebreak (lower id wins) so target choice
			# never depends on bucket iteration order.
			if best == -1 or d < best_distance or (d == best_distance and other < best):
				best = other
				best_distance = d

	return best


func _should_attack(sim: SquadSim, squad: int, tick: int, attacker_def: UnitDef) -> bool:
	# Quantised to whole ticks (D-020's 100 ms minimum round granularity),
	# not a continuous timer: "every attack_interval seconds" becomes
	# "every N ticks", which is exactly what D-024 means by a round.
	var interval_ticks := maxi(1, roundi(attacker_def.attack_interval * SquadSim.TICK_HZ))
	var last := sim.last_attack_tick_of(squad)
	if last >= 0 and tick - last < interval_ticks:
		return false
	sim.set_last_attack_tick(squad, tick)
	return true


## `attacker_strength` is the attacker's strength at the START of the
## round, passed in rather than read live — that is what makes the round
## simultaneous. See resolve()'s comment for why id order used to decide
## mirror matchups.
func _resolve_attack(sim: SquadSim, attacker: int, defender: int, tick: int, attacker_strength: int) -> void:
	var attacker_def := sim.def_of(attacker)
	var defender_def := sim.def_of(defender)
	if attacker_def == null or defender_def == null:
		return

	# Counter-based roll (see header comment): a pure function of
	# (seed, tick, squad id), so it reproduces regardless of iteration
	# order even if that order changes later.
	var roll := _roll_unit(sim.combat_seed, tick, attacker)
	var variance := clampf(attacker_def.damage_variance, 0.0, 1.0)
	var multiplier := (1.0 - variance) + 2.0 * variance * roll
	# Counter multiplier from data, not from a match statement here
	# (D-032). A missing entry is 1.0, so a generalist unit needs no
	# special-casing and adding a counter never means touching this file.
	var counter := float(attacker_def.bonus_vs.get(defender_def.armour_class, 1.0))
	var total_damage := attacker_def.damage * float(attacker_strength) * multiplier * counter

	# Fractional damage carries in the DEFENDER's accumulator (D-024);
	# casualties only ever leave it as a whole-number decrement to alive.
	var defender_health := maxf(defender_def.health, 0.001)
	var accum := sim.damage_accum_of(defender) + total_damage / defender_health
	var casualties := int(floor(accum))
	sim.set_damage_accum(defender, accum - float(casualties))

	if casualties <= 0:
		return

	sim.set_alive(defender, maxi(0, sim.alive_of(defender) - casualties))
	var morale := sim.morale_of(defender) - float(casualties) * defender_def.morale_loss_per_casualty
	sim.set_morale(defender, maxf(morale, 0.0))
	_check_rout(sim, defender, defender_def, attacker)


func _check_rout(sim: SquadSim, defender: int, defender_def: UnitDef, attacker: int) -> void:
	if sim.is_routed(defender) or sim.alive_of(defender) <= 0:
		return
	if sim.morale_of(defender) >= defender_def.rout_threshold:
		return

	sim.set_routed(defender, true)

	# Flee as a squad, away from the nearest enemy, torus-aware (D-024).
	# TorusSpace.delta() already returns the shortest wrapped vector, so
	# the flee direction is correct across a seam with no extra handling
	# here. This goes through `force_move`, not `order_move` — a routed
	# squad ignores PLAYER orders, but this is the sim's own order, and is
	# exactly the move a routed squad should make.
	var defender_coord := sim.space.from_index(sim.cell_index_of(defender))
	var attacker_coord := sim.space.from_index(sim.cell_index_of(attacker))
	var away := sim.space.delta(attacker_coord, defender_coord)
	if away == Vector2i.ZERO:
		away = Vector2i(1, 0)  # degenerate same-cell case; any fixed direction is fine
	sim.flee_move(defender, defender_coord + away * ROUT_FLEE_MULTIPLIER)


## World-units -> cells conversion for attack_range, mirroring
## SquadSim._cells_per_second's conversion of move_speed by the same hex
## width, so both stats stay in the same intuitive world units in the
## data files.
static func _range_in_cells(space: TorusSpace, attack_range: float) -> float:
	var hex_width := space.hex_size * TorusSpace.SQRT_3
	if hex_width <= 0.0:
		return 0.0
	return attack_range / hex_width


## Deterministic pseudo-random value in [0, 1), a pure function of three
## integers. FNV-style byte mixing rather than a bare multiply-hash: a
## naive `seed * big_prime` with a 32-bit seed can overflow GDScript's
## 64-bit int in a single step, whereas repeatedly hashing one 32-bit
## accumulator against a ~2^24 prime (as NetProtocol's composition hash
## already does) never approaches that ceiling. Integer ops only, so it is
## bit-identical on every machine — the same property Formation._hash_unit
## relies on for the "loose" formation's deterministic jitter.
static func _roll_unit(seed_value: int, tick: int, squad_id: int) -> float:
	var h := _FNV_OFFSET_BASIS
	h = _mix(h, seed_value)
	h = _mix(h, tick)
	h = _mix(h, squad_id)
	h = _mix(h, h >> 15)  # extra avalanche so nearby inputs don't produce nearby rolls
	return float(h & 0xFFFFFF) / float(0x1000000)


static func _mix(h: int, value: int) -> int:
	return ((h ^ (value & 0xFFFFFFFF)) * _FNV_PRIME) & 0xFFFFFFFF

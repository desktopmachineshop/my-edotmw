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

	var buckets := _build_buckets(sim)
	for attacker in range(sim.squad_count()):
		if sim.alive_of(attacker) <= 0 or sim.is_routed(attacker):
			continue
		var attacker_def := sim.def_of(attacker)
		if attacker_def == null:
			continue
		var target := _find_target(sim, buckets, attacker, attacker_def)
		if target == -1:
			continue
		if _should_attack(sim, attacker, tick, attacker_def):
			_resolve_attack(sim, attacker, target, tick)

	return _diff(sim, before_alive, before_routed)


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
			if other == attacker or sim.owner_of(other) == owner:
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


func _resolve_attack(sim: SquadSim, attacker: int, defender: int, tick: int) -> void:
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
	var total_damage := attacker_def.damage * float(sim.alive_of(attacker)) * multiplier

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
	sim.force_move(defender, defender_coord + away * ROUT_FLEE_MULTIPLIER)


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

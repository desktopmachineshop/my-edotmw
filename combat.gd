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

# The morale terms (D-20260819-morale-reads-the-fight). Universal battle
# rules in ROUT_FLEE_MULTIPLIER's style — constants until a civ or unit
# identity asks to vary one, at which point they become schema through
# D-010's log, never a branch here.
#
# Morale loss multipliers by where the blow came from. Damage is
# untouched: Tier 2's frontage already prices the geometry in blood;
# these price it in terror, which is what makes envelopment BREAK a line
# rather than merely out-trade it.
const FLANK_MORALE_MULT := 1.5
const REAR_MORALE_MULT := 2.5
# A fleeing squad neither faces nor fights back. Catching it is
# emergent — a faster pursuer stays in reach — so this one multiplier is
# the whole pursuit mechanic, and it is what makes a rout a defeat
# rather than a pause.
const PURSUIT_DAMAGE_MULT := 2.0
# Watching a friend break, within this many cells, costs this much
# morale — and can cascade, which is how battles END. Bounded: a squad
# routs at most once, and the scan reuses the tick's buckets over
# TorusSpace.disk_offsets (the standing any-radius-scan rule).
const CHAIN_ROUT_RADIUS_CELLS := 8
const CHAIN_ROUT_MORALE_LOSS := 12.0
# A charge's one impact blow (D-20260819-a-charge-is-spent-on-its-impact)
# multiplies CONTACT damage, so a wide charge hits with more men, and its
# casualties carry the aspect shock, so a rear charge compounds — the
# terms stack because each reads the same replicated state.
const CHARGE_IMPACT_MULT := 3.0
# Height (D-20260819-tired-men-fight-uphill): attacking downhill hits
# harder, uphill softer, read from the sim's discrete per-cell elevation
# (empty field = flat = 1.0, so every bare test sim is untouched).
const HEIGHT_STEP := 0.05
const DOWNHILL_MULT := 1.15
const UPHILL_MULT := 0.85

# The squad pass's bucket map, kept so the buildings pass in the same
# tick does not rebuild an identical one.
var _buckets := {}
var _buckets_tick := -1

# This tick's derived soldier transforms, at the ROUND SNAPSHOT strengths
# (D-20260819-only-men-in-contact-fight). A memo of a pure function,
# cleared every round — NOT state: deriving from live `alive` mid-round
# would let an earlier attack's casualties shrink a later attack's
# contact count, which is D-024's simultaneity bias sneaking back in
# through the formation restamp.
var _round_transforms := {}

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
	_round_transforms.clear()

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
		#
		# A CHARGING squad skips the halt until its blow actually fires:
		# stop() spends the charge, and spending it one line before the
		# attack it was meant to carry is the misfire
		# D-20260819-a-charge-is-spent-on-its-impact exists to close.
		var charging := sim.is_charging(attacker)
		if sim.is_attack_moving(attacker) and not charging:
			sim.stop(attacker)

		if _should_attack(sim, attacker, tick, attacker_def):
			# Tier 2 (D-20260819-only-men-in-contact-fight): the damage
			# multiplier is the men actually IN CONTACT, not the squad's
			# whole strength. Frontage becomes real here — a wide line
			# lands more men than a deep column — and the pairing is the
			# same Engagement function the client's duels draw from.
			_resolve_attack(sim, attacker, target, tick,
				_contact_strength(sim, attacker, target, round_alive, attacker_def),
				round_routed[target] == 1, charging)
			if charging:
				# The charge is spent ON the blow: halt here, once, and
				# the flag goes with the halt.
				sim.stop(attacker)

	return _diff(sim, before_alive, before_routed)


## The attacker's men within fighting reach of the defender's, over both
## squads' derived positions at the round snapshot. Pure per tick; the
## per-squad derivation is memoised for the round in `_round_transforms`.
func _contact_strength(sim: SquadSim, attacker: int, defender: int,
		round_alive: PackedInt32Array, attacker_def: UnitDef) -> int:
	var attackers := _snapshot_transforms(sim, attacker, round_alive)
	var defenders := _snapshot_transforms(sim, defender, round_alive)
	if attackers.is_empty() or defenders.is_empty():
		return 0
	# The torus tax: an engaged pair straddling a seam derives a whole map
	# apart in canonical coordinates. Engagement's own header has the
	# failure this prevents.
	var aligned := Engagement.shifted(defenders, Engagement.aligning_offset(
		attackers[0].origin, defenders[0].origin, sim.space.lattice_offsets()))
	return Engagement.contact_count(attackers, aligned,
		Engagement.contact_reach(attacker_def.attack_range))


func _snapshot_transforms(sim: SquadSim, squad: int,
		round_alive: PackedInt32Array) -> Array[Transform3D]:
	if _round_transforms.has(squad):
		return _round_transforms[squad]
	var out := Formation.soldier_transforms(
		sim.curve_of(squad), sim.time, round_alive[squad],
		sim.shape_of(squad), sim.spacing_of(squad), sim.space,
		Callable(), PackedByteArray(), sim.files_of(squad),
		sim.facing_angle_of(squad))
	_round_transforms[squad] = out
	return out


## Whether this squad has something in reach THIS TICK — an enemy squad
## (`resolve`) or a building it is battering (`resolve_squads_vs_buildings`).
##
## Read by SquadSim._separate_arrivals, which must leave a squad in a
## fight exactly where it stands: separation and engagement are the same
## arithmetic pointed in opposite directions, and separation is the one
## that has to give way (#104).
func is_engaged(squad: int) -> bool:
	return _engaged.has(squad)


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
		# GUARD holds position; HOLD FIRE will not shoot what it catches —
		# chasing either way is theatre (D-20260819-stances).
		if sim.has_stance(squad, SquadSim.STANCE_GUARD) 				or sim.has_stance(squad, SquadSim.STANCE_HOLD_FIRE):
			continue
		var def := sim.def_of(squad)
		if def == null or def.damage <= 0.0 or def.carry_capacity > 0:
			continue
		var target := _find_squad_near(sim, buckets, sim.cell_index_of(squad),
			sim.owner_of(squad), _range_in_cells(sim.space, def.vision_range),
			sim.tier_of(squad), def.armour_class)
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
	# `fell` marks men killed by violence — building fire counts — so the
	# client may lay corpses for them (D-20260819-a-casualty-is-visible).
	var events := []
	for i in range(sim.squad_count()):
		if sim.alive_of(i) != before_alive[i]:
			events.append({"id": i, "alive": sim.alive_of(i),
				"routed": sim.is_routed(i),
				"fell": sim.alive_of(i) < before_alive[i]})
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

		# Besieging counts as engaged, exactly as fighting a squad does.
		# Recorded AFTER this loop's own `_engaged` guard above, so the
		# "already spent this tick's attack" rule is untouched — the
		# reader this is for is SquadSim._separate_arrivals, which must
		# not shuffle a squad off the wall it is battering (#104).
		_engaged[attacker] = true

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
##
## `attacker_tier`/`attacker_class` (D-076) feed `_can_reach_tier` — see
## that function. Defaulted to (0, "missile") so every caller that does
## not pass them (buildings, both existing shooting passes) treats itself
## as ranged and can therefore still hit a tier-1 defender, matching the
## rule that a fortification's own fire "arcs up" the same as an archer's;
## `assign_idle_engagements` passes the ACTUAL chasing squad's tier and
## armour class instead, so a tier-0 melee squad does not idle-chase a
## wall-top target it could never actually reach.
func _find_squad_near(sim: SquadSim, buckets: Dictionary, origin_index: int,
		owner: int, range_cells: float, attacker_tier: int = 0,
		attacker_class: String = "missile") -> int:
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
			if not _can_reach_tier(attacker_tier, attacker_class, sim.tier_of(other)):
				continue
			var d := TorusSpace.hex_length(offset)
			# Deterministic tiebreak (lower id wins), so target choice
			# never depends on bucket iteration order.
			if best == -1 or d < best_distance or (d == best_distance and other < best):
				best = other
				best_distance = d
	return best


## Whether an attacker (tier `attacker_tier`, armour class
## `attacker_class`) may reach a squad standing at `target_tier` (D-076).
## A tier-1 squad can be reached only by another tier-1 squad, or by a
## RANGED attacker (`armour_class == "missile"`) — never a tier-0 melee
## squad. This is what makes climbing the wall a real defensive choice
## ("you cannot melee someone on top of a wall from the ground") rather
## than cosmetic — recorded as its own rule in D-076, not left implicit.
static func _can_reach_tier(attacker_tier: int, attacker_class: String, target_tier: int) -> bool:
	if target_tier != 1:
		return true
	return attacker_tier == 1 or attacker_class == "missile"


## A squad's effective attack range in cells, including the height bonus
## from whatever `walkable_top` structure it is standing on at tier 1
## (D-076). Tier-0 squads are unaffected; `sim.buildings` may be null (a
## bare SquadSim has nothing to stand on), which degrades to the plain
## conversion exactly as it did before tiers existed.
static func _attacker_range_cells(sim: SquadSim, attacker: int, attacker_def: UnitDef) -> float:
	var world_range := attacker_def.attack_range
	if sim.buildings != null and sim.tier_of(attacker) == 1:
		var standing_on := sim.buildings.building_at(sim.cell_of(attacker))
		if standing_on >= 0:
			var top_def := sim.buildings.def_of(standing_on)
			if top_def != null:
				world_range += top_def.top_range_bonus
	return _range_in_cells(sim.space, world_range)


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
	# beaten by another squad does — through the same _break_squad, so a
	# tower-driven rout shocks nearby allies exactly like a melee one
	# (D-20260819-morale-reads-the-fight). _check_rout is not used only
	# because it wants an attacking SQUAD; the flee-from cell is here.
	if sim.is_routed(squad) or sim.alive_of(squad) <= 0:
		return
	if sim.morale_of(squad) >= def.rout_threshold:
		return
	_break_squad(sim, squad, from_cell_index)


func _diff(sim: SquadSim, before_alive: PackedInt32Array, before_routed: PackedByteArray) -> Array:
	# `fell` is true only when this event actually subtracts men — a pure
	# rout-state flip carries fell=false, and the two non-combat writers of
	# this event shape (consume_squad, eliminate_player) never set the key
	# at all, which the encoder defaults to false
	# (D-20260819-a-casualty-is-visible).
	var events := []
	for i in range(sim.squad_count()):
		var routed_now := sim.is_routed(i)
		if sim.alive_of(i) != before_alive[i] or routed_now != (before_routed[i] == 1):
			events.append({"id": i, "alive": sim.alive_of(i), "routed": routed_now,
				"fell": sim.alive_of(i) < before_alive[i]})
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
	# D-076: range includes any height bonus for a tier-1 attacker, and
	# eligibility excludes a tier-1 defender this attacker cannot reach
	# (melee on the ground cannot touch the wall-top).
	var range_cells := _attacker_range_cells(sim, attacker, attacker_def)
	var radius := floori(range_cells)
	var origin := sim.space.from_index(sim.cell_index_of(attacker))
	var owner := sim.owner_of(attacker)
	var attacker_tier := sim.tier_of(attacker)

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
			if not _can_reach_tier(attacker_tier, attacker_def.armour_class, sim.tier_of(other)):
				continue
			# Deterministic tiebreak (lower id wins) so target choice
			# never depends on bucket iteration order.
			if best == -1 or d < best_distance or (d == best_distance and other < best):
				best = other
				best_distance = d

	return best


## The skirmish stance (D-20260819-stances-are-standing-orders): an IDLE
## missile squad holding it steps directly away from an enemy that closes
## inside the trigger, and keeps shooting. Through the ordinary move
## order on purpose, so separation, walls and every standing movement
## rule apply to the step — and only while idle, so a player's live order
## always outranks the stance (D-065's suggest-vs-set principle).
const SKIRMISH_TRIGGER_CELLS := 3
const SKIRMISH_STEP_CELLS := 4


func apply_skirmish(sim: SquadSim, tick: int) -> void:
	var buckets: Dictionary = _buckets if _buckets_tick == tick else _build_buckets(sim)
	for squad in range(sim.squad_count()):
		if sim.alive_of(squad) <= 0 or sim.is_routed(squad):
			continue
		if not sim.has_stance(squad, SquadSim.STANCE_SKIRMISH):
			continue
		if sim.is_attack_moving(squad) or not sim.is_idle(squad):
			continue
		var threat := _find_squad_near(sim, buckets, sim.cell_index_of(squad),
			sim.owner_of(squad), SKIRMISH_TRIGGER_CELLS, sim.tier_of(squad))
		if threat == -1:
			continue
		var here := sim.space.from_index(sim.cell_index_of(squad))
		var away := sim.space.delta(sim.cell_of(threat), here)
		if away == Vector2i.ZERO:
			away = Vector2i(1, 0)
		sim.order_move(squad, here + away * SKIRMISH_STEP_CELLS)


func _should_attack(sim: SquadSim, squad: int, tick: int, attacker_def: UnitDef) -> bool:
	# HOLD FIRE (D-20260819-stances): no attacks while held. An explicit
	# attack order RELEASES the hold (see order_attack_move) — gating on
	# the attack-move flag instead would fall to D-034's halt spending
	# that flag on contact, and a held squad ordered to attack would fire
	# once and fall silent. Checked before the interval so a held squad's
	# cadence is not silently spent.
	if sim.has_stance(squad, SquadSim.STANCE_HOLD_FIRE):
		return false
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
## `attacker_strength` is the men IN CONTACT since Tier 2
## (D-20260819-only-men-in-contact-fight), not the squad's whole
## strength; zero contact resolves as zero damage through the ordinary
## arithmetic rather than a special case. `defender_routed` is the ROUND
## SNAPSHOT's answer, for the same reason the strength is — a defender
## chain-routed mid-round must not take pursuit damage until next round.
func _resolve_attack(sim: SquadSim, attacker: int, defender: int, tick: int,
		attacker_strength: int, defender_routed: bool = false,
		charging: bool = false) -> void:
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
	# Pursuit (D-20260819-morale-reads-the-fight): a fleeing squad
	# neither faces nor fights back, and cutting it down is what makes a
	# rout a defeat rather than a pause.
	if defender_routed:
		total_damage *= PURSUIT_DAMAGE_MULT
	# The impact blow (D-20260819-a-charge-is-spent-on-its-impact).
	if charging:
		total_damage *= CHARGE_IMPACT_MULT
	# The formation's fighting style (D-20260819): directional defence,
	# priced by the same aspect the morale shock below reads.
	var aspect := _aspect_of(sim, attacker, defender)
	total_damage *= _formation_taken_mult(sim, attacker_def, defender, aspect)
	# Tired men hit softer (D-20260819-tired-men-fight-uphill): an
	# exhausted squad fights at half strength.
	total_damage *= 0.5 + 0.5 * sim.fatigue_of(attacker) / 100.0
	# And the slope has a say.
	total_damage *= _height_mult(sim, attacker, defender)

	# Fractional damage carries in the DEFENDER's accumulator (D-024);
	# casualties only ever leave it as a whole-number decrement to alive.
	var defender_health := maxf(defender_def.health, 0.001)
	var accum := sim.damage_accum_of(defender) + total_damage / defender_health
	var casualties := int(floor(accum))
	sim.set_damage_accum(defender, accum - float(casualties))

	if casualties <= 0:
		return

	sim.set_alive(defender, maxi(0, sim.alive_of(defender) - casualties))
	# Flank/rear shock (D-20260819-morale-reads-the-fight): the morale
	# cost of a casualty is multiplied by where the blow came from — the
	# SAME aspect the formation's defence already priced above, so the
	# terror and the shield agree about where the blow landed.
	var morale := sim.morale_of(defender) \
		- float(casualties) * defender_def.morale_loss_per_casualty \
			* _morale_mult_for(aspect)
	sim.set_morale(defender, maxf(morale, 0.0))
	_check_rout(sim, defender, defender_def, attacker)


## Where a blow from `attacker` lands on `defender` — computed ONCE per
## landed attack and read by BOTH consumers (the formation's directional
## defence and the morale shock); two aspect computations would
## eventually disagree at a cone boundary.
func _aspect_of(sim: SquadSim, attacker: int, defender: int) -> int:
	var defender_pos := sim.curve_of(defender).sample_world(sim.time, sim.space)
	var attacker_pos := sim.curve_of(attacker).sample_world(sim.time, sim.space)
	attacker_pos += Engagement.aligning_offset(
		defender_pos, attacker_pos, sim.space.lattice_offsets())
	# THE facing resolver (D-20260819-facing-and-width-are-orders): a
	# braced line's ordered facing is exactly what the shock term reads,
	# which is what makes bracing a defence.
	var angle := Formation.facing_angle(sim.curve_of(defender), sim.time,
		sim.space, sim.facing_angle_of(defender))
	var facing := Vector3(sin(angle), 0.0, cos(angle))
	return Engagement.aspect(facing, defender_pos, attacker_pos)


## The slope's price (D-20260819-tired-men-fight-uphill). Discrete
## per-cell elevation, SERVER-side only — D-084's "the picture
## interpolates, the simulation does not" split survives untouched.
func _height_mult(sim: SquadSim, attacker: int, defender: int) -> float:
	if sim.elevation.is_empty():
		return 1.0
	var dh := sim.elevation[sim.cell_index_of(attacker)] \
		- sim.elevation[sim.cell_index_of(defender)]
	if dh >= HEIGHT_STEP:
		return DOWNHILL_MULT
	if dh <= -HEIGHT_STEP:
		return UPHILL_MULT
	return 1.0


func _morale_mult_for(aspect: int) -> float:
	match aspect:
		Engagement.ASPECT_REAR:
			return REAR_MORALE_MULT
		Engagement.ASPECT_FLANK:
			return FLANK_MORALE_MULT
		_:
			return 1.0


## The defender's formation as a fighting style
## (D-20260819-a-formation-is-a-fighting-style): directional damage-taken
## plus the missile multiplier. 1.0 whenever the shape resolves to
## nothing — a missing def must cost nothing, not crash a fight.
func _formation_taken_mult(sim: SquadSim, attacker_def: UnitDef,
		defender: int, aspect: int) -> float:
	var style := FormationRoster.by_id(StringName(sim.shape_of(defender)))
	if style == null:
		return 1.0
	var mult := style.taken_front
	match aspect:
		Engagement.ASPECT_REAR:
			mult = style.taken_rear
		Engagement.ASPECT_FLANK:
			mult = style.taken_flank
	if attacker_def.armour_class == "missile":
		mult *= style.missile_taken
	return mult


func _check_rout(sim: SquadSim, defender: int, defender_def: UnitDef, attacker: int) -> void:
	if sim.is_routed(defender) or sim.alive_of(defender) <= 0:
		return
	if sim.morale_of(defender) >= defender_def.rout_threshold:
		return
	_break_squad(sim, defender, sim.cell_index_of(attacker))


## Break one squad: rout it, flee it away from `from_cell_index`, and
## shock its nearby allies — which can break THEM by the same machinery
## (D-20260819-morale-reads-the-fight). The cascade terminates because a
## squad routs at most once (`is_routed` guards every entry) and each
## break only ever lowers morale.
##
## Fleeing is as a squad, away from the threat, torus-aware (D-024):
## TorusSpace.delta() already returns the shortest wrapped vector, so the
## direction is correct across a seam. `force_move`, not `order_move` — a
## routed squad ignores PLAYER orders, but this is the sim's own.
func _break_squad(sim: SquadSim, squad: int, from_cell_index: int) -> void:
	sim.set_routed(squad, true)
	var here := sim.space.from_index(sim.cell_index_of(squad))
	var from_coord := sim.space.from_index(from_cell_index)
	var away := sim.space.delta(from_coord, here)
	if away == Vector2i.ZERO:
		away = Vector2i(1, 0)  # degenerate same-cell case; any fixed direction is fine
	sim.flee_move(squad, here + away * ROUT_FLEE_MULTIPLIER)
	_shock_allies(sim, squad, from_cell_index)


## Watching a friend break costs morale (D-20260819-morale-reads-the-
## fight): every allied squad within CHAIN_ROUT_RADIUS_CELLS of the
## routing one loses CHAIN_ROUT_MORALE_LOSS, and one pushed below its own
## threshold breaks too, fleeing the same threat. The scan reuses the
## tick's cell buckets over TorusSpace.disk_offsets — the standing
## any-radius-scan rule — so it costs the disk, never the squad list.
func _shock_allies(sim: SquadSim, routed_squad: int, from_cell_index: int) -> void:
	var owner := sim.owner_of(routed_squad)
	var centre := sim.space.from_index(sim.cell_index_of(routed_squad))
	for offset in TorusSpace.disk_offsets(CHAIN_ROUT_RADIUS_CELLS):
		var cell := sim.space.index(centre + offset)
		if not _buckets.has(cell):
			continue
		for ally in _buckets[cell]:
			if ally == routed_squad or sim.alive_of(ally) <= 0 \
					or sim.is_routed(ally):
				continue
			if not sim.are_allied(sim.owner_of(ally), owner):
				continue
			sim.set_morale(ally,
				maxf(sim.morale_of(ally) - CHAIN_ROUT_MORALE_LOSS, 0.0))
			var ally_def := sim.def_of(ally)
			if ally_def != null and sim.morale_of(ally) < ally_def.rout_threshold:
				_break_squad(sim, ally, from_cell_index)


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

extends GutTest

## Guards #337's shared half: WHEN an AI spends on something that cannot
## chase anybody.
##
## `static_defence.gd` is domain-free on purpose — naval stage 7 (#301)
## has to answer the identical question about shore defences, and #337 was
## filed asking that the two share it rather than each growing their own.
## So the first test here is the CONTRACT that makes sharing possible, and
## it is a source scan, because "this file knows nothing about walls" is
## not something a behavioural test can see.


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


## Comments stripped, so prose explaining a rule cannot be mistaken for
## code breaking it. Same helper, same reason, as `test_steam_boundary.gd`
## and `test_opening_brief.gd` — a guard that fires on an English word in
## a comment is one people learn to edit rather than obey (#204).
func _code_of(path: String) -> String:
	var out := ""
	for line in _read(path).split("\n"):
		var text := String(line).strip_edges()
		if text.begins_with("#"):
			continue
		out += line + "\n"
	return out


func _wallet(food: int, wood: int, gold: int = 0, stone: int = 0) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(Economy.RESOURCE_COUNT)
	out[Economy.ResourceKind.FOOD] = food
	out[Economy.ResourceKind.WOOD] = wood
	out[Economy.ResourceKind.GOLD] = gold
	out[Economy.ResourceKind.STONE] = stone
	return out


## An economy that satisfies the precondition, so a test about THREAT is
## not silently answering "no army yet".
func _ready_economy(army: int = 0) -> Dictionary:
	return {"military_buildings": 1, "army_squads": army}


# --- the contract naval stage 7 is writing against ---------------------


func test_the_shared_decision_knows_nothing_about_walls() -> void:
	# The whole reason this is not three lines inside `ai_player.gd`. If it
	# named a wall, stage 7 would have to fork it, and #337's "share the
	# machinery" would quietly become "write it twice".
	var code := _code_of("res://static_defence.gd")
	# WHOLE WORDS. The first version matched substrings and fired on
	# `wallet`, which is this project's own "a guard that red-flags a good
	# file is worse than no guard" rule catching itself: the next person
	# would have renamed the variable rather than obeyed the rule.
	# `"\b"` — TWO backslashes in the source, so RegEx receives one. The
	# first version had one, which GDScript reads as a backspace
	# character, so every pattern compiled to something no source file
	# contains and the guard passed against a file that DID name a wall.
	# Observed: adding `_probe_wall()` to static_defence.gd left it green.
	var word := RegEx.new()
	for domain in ["wall", "walls", "gate", "gates", "tower", "dock", "ship",
			"shore", "WallPlan", "BuildingSim"]:
		word.compile("\\b%s\\b" % domain)
		var hit := word.search(code)
		assert_null(hit,
			("static_defence.gd names '%s'. It is shared with naval stage 7 "
			+ "(#301) and must stay domain-free — the geometry belongs in "
			+ "wall_plan.gd, or in whatever stage 7 writes.") % domain)


func test_an_unknown_key_can_only_lower_the_pressure() -> void:
	# The property that lets stage 7 supply a threat this file has never
	# heard of without teaching it anything: absent evidence is no
	# evidence, never alarming evidence. A caller that has not yet learned
	# to report something new must not start fortifying because of it.
	var empty := StaticDefence.pressure({}, _ready_economy())
	assert_eq(empty, 0.0, "no evidence is no case")
	var some := StaticDefence.pressure({"hostiles_near": 1}, _ready_economy())
	assert_gt(some, empty, "Setup: evidence raises it, so the comparison means something")


# --- the precondition --------------------------------------------------


func test_nothing_is_fortified_before_something_trains() -> void:
	# Measured on `main`: a ladder seat builds exactly two buildings in a
	# 300 s match, and a wall bought instead of the barracks is a wall the
	# enemy walks round on the way to an undefended town.
	var besieged := {"hostiles_near": 9, "nearest_hostile": 0, "buildings_lost": 4}
	assert_eq(StaticDefence.pressure(besieged, {"military_buildings": 0}), 0.0,
		"an AI with nothing that trains has no business buying masonry")
	assert_gt(StaticDefence.pressure(besieged, _ready_economy()), 0.0,
		"and every bit of that case counts once the barracks is up")


func test_no_appetite_however_high_buys_past_the_precondition() -> void:
	var besieged := {"hostiles_near": 9, "nearest_hostile": 0}
	assert_false(StaticDefence.wants_to_invest(besieged,
		{"military_buildings": 0}, 1.0, 0, 6),
		"the precondition is a precondition, not a weighting")


# --- the case, and that it follows the evidence ------------------------


func test_a_hostile_at_the_door_outweighs_one_across_the_map() -> void:
	var near := StaticDefence.pressure({"nearest_hostile": 1}, _ready_economy())
	var far := StaticDefence.pressure(
		{"nearest_hostile": StaticDefence.THREAT_CELLS - 1}, _ready_economy())
	assert_gt(near, far, "distance has to matter or every seat fortifies")
	assert_eq(StaticDefence.pressure(
		{"nearest_hostile": StaticDefence.THREAT_CELLS + 5}, _ready_economy()), 0.0,
		"a neighbour beyond the threat radius is not a reason to build a wall")


func test_being_raided_keeps_arguing_for_defence() -> void:
	# Buildings are persistent-explored (D-030) and a loss does not
	# un-happen, so this only ever grows — which is right. A player raided
	# once should stay fortified rather than un-fortifying the moment the
	# raider goes home.
	var quiet := StaticDefence.pressure({}, _ready_economy())
	var raided := StaticDefence.pressure({"buildings_lost": 2}, _ready_economy())
	assert_gt(raided, quiet, "a building lost is a case for the next wall")


func test_an_army_in_the_field_argues_against_masonry() -> void:
	var threat := {"hostiles_near": 2}
	var small := StaticDefence.pressure(threat, _ready_economy(0))
	var large := StaticDefence.pressure(threat, _ready_economy(12))
	assert_gt(small, large,
		"an army is the alternative use of the same wallet")
	assert_gte(large, 0.0, "but it never makes the case negative")


func test_appetite_is_how_much_of_the_case_is_needed() -> void:
	# Monotone and statable in one sentence, which the first version was
	# not — it was an arithmetic knot that produced plausible numbers, and
	# a threshold nobody can state is a threshold nobody can tune.
	var threat := {"nearest_hostile": 8}
	var economy := _ready_economy()
	assert_true(StaticDefence.wants_to_invest(threat, economy, 1.0, 0, 6),
		"appetite 1.0 acts on any case at all")
	assert_false(StaticDefence.wants_to_invest(threat, economy, 0.0, 0, 6),
		"appetite 0.0 never acts")
	# And the shipped ordering is a real ordering rather than three equal
	# numbers: the cautious profile fortifies where the relentless one
	# does not, on the same evidence.
	var cautious := AiProfileRoster.by_id(&"cautious")
	var relentless := AiProfileRoster.by_id(&"relentless")
	assert_not_null(cautious)
	assert_not_null(relentless)
	if cautious == null or relentless == null:
		return
	assert_gt(cautious.defence_appetite, relentless.defence_appetite,
		"a cautious opponent should want a wall sooner than a relentless one")


func test_the_investment_is_capped() -> void:
	# A wall is a means and the army is the end. An AI whose pressure
	# stays high — which is every AI in a match it is losing — would
	# otherwise fortify itself out of the game.
	var besieged := {"hostiles_near": 9, "nearest_hostile": 0}
	assert_true(StaticDefence.wants_to_invest(besieged, _ready_economy(), 1.0, 5, 6))
	assert_false(StaticDefence.wants_to_invest(besieged, _ready_economy(), 1.0, 6, 6),
		"at the cap it stops, whatever the case")


# --- paying for it -----------------------------------------------------


func test_a_wall_is_never_bought_with_the_barracks_money() -> void:
	var floors := _wallet(180, 200)
	var price := _wallet(0, 30, 0, 40)
	assert_false(StaticDefence.can_afford_with_reserve(_wallet(0, 40, 0, 60), price, floors),
		"40 wood is the price and nothing else — the economy keeps its share")
	assert_true(StaticDefence.can_afford_with_reserve(_wallet(200, 200, 0, 100), price, floors),
		"with the reserve intact on top of the price, it can spend")


func test_the_reserve_is_a_share_and_not_the_whole_floor() -> void:
	# Holding the WHOLE floor means never fortifying: the floor is where
	# the economy is trying to sit, not a surplus it climbs above.
	var floors := _wallet(180, 200)
	var price := _wallet(0, 30, 0, 40)
	var at_the_floor := _wallet(180, 200, 0, 100)
	assert_true(StaticDefence.can_afford_with_reserve(at_the_floor, price, floors),
		"an economy sitting exactly on its floors can still buy a wall")


# --- the root cause #337 turned out to hinge on ------------------------


func test_the_shortfall_names_the_resource_the_purchase_is_waiting_on() -> void:
	# This is the half that made the whole feature reachable. The AI's
	# resource priorities were a fixed FOOD/WOOD list, so it never
	# gathered stone — and every wall, gate and tower in the roster costs
	# stone. The feature was not merely unexercised by the ladder; it was
	# unaffordable by construction.
	var wallet := _wallet(300, 300, 0, 0)
	var wall := _wallet(0, 30, 0, 40)
	assert_eq(StaticDefence.scarcest_shortfall(wallet, wall),
		Economy.ResourceKind.STONE,
		"a stone price with no stone in the bank says STONE")
	assert_eq(StaticDefence.scarcest_shortfall(_wallet(300, 300, 0, 300), wall), -1,
		"and says nothing when the purchase is already affordable")


func test_the_shortfall_picks_the_biggest_gap_so_a_price_converges() -> void:
	# The SCARCEST rather than the first: a two-resource price whose
	# priority alternated would leave an AI switching crews every think
	# and closing neither gap.
	var wallet := _wallet(0, 100, 0, 10)
	var price := _wallet(0, 120, 0, 130)
	assert_eq(StaticDefence.scarcest_shortfall(wallet, price),
		Economy.ResourceKind.STONE, "120 short of stone beats 20 short of wood")


func test_a_price_is_read_off_the_def_rather_than_written_out() -> void:
	var def := BuildingDef.new()
	def.cost_wood = 30
	def.cost_stone = 40
	var cost := StaticDefence.cost_of(def)
	assert_eq(cost[Economy.ResourceKind.WOOD], 30)
	assert_eq(cost[Economy.ResourceKind.STONE], 40)
	assert_eq(cost.size(), Economy.RESOURCE_COUNT,
		"wallet-shaped, in the order every wallet in this project uses")

extends GutTest

## Guards the naval roster — #301, `docs/plans/naval.md` §5, stage 6.
##
## The design's §5.3 prints a screen and then says, in its own words:
##
## > **A test must recompute this**, not quote it — so a `.tres` edit that
## > breaks "price buys power" goes red rather than shipping.
##
## So nothing here is a transcribed number. Every figure is recomputed
## from the shipped `.tres` through D-072's own arithmetic, and the RULES
## are what is asserted:
##
##     DPS = squad_size x damage / attack_interval
##     EHP = squad_size x health
##     V   = sqrt(DPS x EHP)
##     RP  = food + wood + 1.5 x (gold + stone)
##
##   1. PRICE BUYS POWER — within a role, a dearer hull has higher V.
##   2. NO FREE LUNCH — within a role, no hull leads on both V and V/RP.
##
## ## What is exempt, and why an exemption is stated rather than skipped
##
## D-072 is explicit that V cannot see `attack_range`, `move_speed`,
## `vision_range`, `bonus_vs` or `morale`. Two of the four naval roles are
## outside the metric for reasons the design names:
##
## - **transports** carry, and V prices no part of carrying. They are
##   screened on `transport_capacity` per RP instead, which is a real
##   ordering and not an absence of one.
## - **the siege ship** buys reach and `damage_vs_buildings`, both
##   unpriced. It is exempt from the warship comparison and asserted
##   against the property the design NAMES — that it outranges a shore
##   tower — because "exempt" with nothing behind it is the vacuous pass
##   D-022's audit block was written about.
##
## ## The relationship to `tests/test_power_budget.gd`
##
## That file (#220, worker 82's branch) screens the LAND roster and owns
## a `ROLES` table keyed by archetype. It does not know `warship`,
## `transport` or `warboat`, so when both land the ten hulls would fall
## into its `"other"` bucket and be compared against each other with no
## role separation and with transports at V = 0. Naval roles are screened
## HERE, and that file's table should exclude the naval archetypes rather
## than guess at them. Flagged in the PR; not editable from this branch.

const SEA_ROLES := {
	&"warship": "warship",
	&"warboat": "combined",
	&"transport": "transport",
}

## The one hull the design exempts from the warship comparison by name,
## and the property it is exempt FOR.
const SIEGE_SHIP := &"emberdeep_warship"


func _ships() -> Array:
	var out := []
	for def in UnitRoster.load_all():
		if not SEA_ROLES.has(def.archetype):
			continue
		var interval := maxf(def.attack_interval, 0.001)
		var dps := float(def.squad_size) * def.damage / interval
		var ehp := float(def.squad_size) * def.health
		var rp := float(def.cost_food + def.cost_wood) \
			+ 1.5 * float(def.cost_gold + def.cost_stone)
		out.append({
			"def": def, "id": def.id, "civ": String(def.civ),
			"role": String(SEA_ROLES[def.archetype]),
			"v": sqrt(dps * ehp), "rp": rp,
			"vrp": (sqrt(dps * ehp) / rp) if rp > 0.0 else 0.0,
			"cap_per_rp": (float(def.transport_capacity) / rp) if rp > 0.0 else 0.0,
		})
	out.sort_custom(func(a, b): return float(a["rp"]) < float(b["rp"]))
	return out


func _in_role(role: String, include_siege := false) -> Array:
	var out := []
	for row in _ships():
		if String(row["role"]) != role:
			continue
		if not include_siege and StringName(row["id"]) == SIEGE_SHIP:
			continue
		out.append(row)
	return out


# --- the roster is there at all ---------------------------------------

func test_every_civ_can_put_something_on_the_water() -> void:
	# #301's directive is "at least two naval units per civ, OR a combined
	# unit where that fits the civ better". Both shapes are legal; having
	# NOTHING is not, and a civ silently missing its hulls is the kind of
	# gap only a roster-wide check sees.
	var by_civ := {}
	for row in _ships():
		var civ := String(row["civ"])
		by_civ[civ] = int(by_civ.get(civ, 0)) + 1
	var civs := CivRoster.ids()
	assert_gt(civs.size(), 1, "Setup: there must be civs to check")
	for id in civs:
		var civ := String(id)
		assert_true(by_civ.has(civ), "civ %s fields no ship at all" % civ)
		var n := int(by_civ.get(civ, 0))
		# Two hulls, or one that both fights and carries.
		if n == 1:
			var only: Dictionary = _only_ship_of(civ)
			assert_eq(String(only["role"]), "combined",
				"civ %s fields one hull, so it must be a combined attack-transport" % civ)
			assert_gt(int(only["def"].transport_capacity), 0,
				"%s is a civ's only hull and carries nothing" % only["id"])
			assert_gt(float(only["def"].damage), 0.0,
				"%s is a civ's only hull and cannot fight" % only["id"])
		else:
			assert_gte(n, 2, "civ %s fields %d hulls" % [civ, n])


func _only_ship_of(civ: String) -> Dictionary:
	for row in _ships():
		if String(row["civ"]) == civ:
			return row
	return {}


func test_every_ship_is_a_water_unit_and_no_land_unit_is() -> void:
	# `movement_domain`'s first reader. The pathing half is stage 2; this
	# is what stops the field being declared and unread in the meantime,
	# and it is a real check either way — a land unit marked `water` would
	# be unpathable the day stage 2 lands.
	var ships := 0
	for def in UnitRoster.load_all():
		if SEA_ROLES.has(def.archetype):
			ships += 1
			assert_eq(def.movement_domain, "water",
				"%s is a naval archetype and must live in the water domain" % def.id)
		else:
			assert_eq(def.movement_domain, "ground",
				"%s is a land unit and must not be marked water" % def.id)
	assert_eq(ships, 10, "the design ships ten hulls; found %d" % ships)


func test_a_dock_produces_ships_and_nothing_else_does() -> void:
	# The build menu resolves `produces` per civ (D-047), so a dock listing
	# the union is how six civs get their own hulls from one def — the same
	# reason there is one barracks and not six.
	var dock := BuildingSim.def_by_id(&"dock")
	assert_not_null(dock, "the roster must ship a dock")
	for archetype in SEA_ROLES:
		assert_true(dock.produces.has(archetype),
			"a dock must offer %s" % archetype)
	for def in BuildingSim.all_defs():
		if String(def.id) == "dock":
			continue
		for archetype in SEA_ROLES:
			assert_false(def.produces.has(archetype),
				"%s offers %s — ships come from a dock" % [def.id, archetype])


func test_every_civ_resolves_its_own_hulls_from_the_shared_dock() -> void:
	# The leak check #207's pass ran over the land roster, asked of the
	# naval one: one dock def, six civs, each resolving only its own.
	var dock := BuildingSim.def_by_id(&"dock")
	assert_not_null(dock)
	for id in CivRoster.ids():
		var civ := String(id)
		var got := []
		for archetype in dock.produces:
			var def := UnitRoster.for_civ_archetype(StringName(civ), archetype)
			if def == null:
				continue
			assert_true(String(def.civ) == civ,
				"civ %s asked a dock for %s and got %s's hull" % [civ, archetype, def.civ])
			got.append(String(def.id))
		assert_gt(got.size(), 0, "civ %s resolves no hull from a dock" % civ)


# --- D-072's two rules, recomputed ------------------------------------

func test_price_buys_power_among_warships() -> void:
	_assert_price_buys_power(_in_role("warship"), "warship")


func test_price_buys_power_among_combined_hulls() -> void:
	_assert_price_buys_power(_in_role("combined"), "combined")


## Rule 1, over a role sorted by price: V must rise with RP.
##
## Reported with the numbers on failure, because "price does not buy
## power" without the pair that broke it is a defect nobody can act on.
func _assert_price_buys_power(rows: Array, role: String) -> void:
	assert_gt(rows.size(), 1,
		"role %s has fewer than two hulls, so the rule is vacuous" % role)
	for i in range(rows.size() - 1):
		var cheap: Dictionary = rows[i]
		var dear: Dictionary = rows[i + 1]
		assert_gt(float(dear["v"]), float(cheap["v"]),
			"price must buy power: %s costs RP %.0f for V %.1f, %s costs RP %.0f for V %.1f" % [
				dear["id"], dear["rp"], dear["v"],
				cheap["id"], cheap["rp"], cheap["v"]])


func test_no_warship_leads_on_both_power_and_efficiency() -> void:
	_assert_no_free_lunch(_in_role("warship"), "warship")


func test_no_combined_hull_leads_on_both_power_and_efficiency() -> void:
	_assert_no_free_lunch(_in_role("combined"), "combined")


## Rule 2: the hull with the highest V must not also have the highest
## V/RP. That is what makes a role a CHOICE rather than a ladder — the
## thing #267 found the land roster's levies failing.
func _assert_no_free_lunch(rows: Array, role: String) -> void:
	assert_gt(rows.size(), 1,
		"role %s has fewer than two hulls, so the rule is vacuous" % role)
	var best_v := {}
	var best_vrp := {}
	for row in rows:
		if best_v.is_empty() or float(row["v"]) > float(best_v["v"]):
			best_v = row
		if best_vrp.is_empty() or float(row["vrp"]) > float(best_vrp["vrp"]):
			best_vrp = row
	assert_ne(String(best_v["id"]), String(best_vrp["id"]),
		"%s leads role %s on BOTH V (%.1f) and V/RP (%.3f) — no free lunch (D-072)" % [
			best_v["id"], role, best_v["v"], best_v["vrp"]])
	# And the design's own shape: the cheapest leads efficiency, the
	# dearest leads power. Rows are price-sorted.
	assert_eq(String(best_vrp["id"]), String(rows[0]["id"]),
		"the cheapest %s should lead V/RP" % role)
	assert_eq(String(best_v["id"]), String(rows[rows.size() - 1]["id"]),
		"the dearest %s should lead V" % role)


# --- the two exemptions, each with something behind it ----------------

func test_transports_are_ordered_by_what_they_carry_per_resource_point() -> void:
	# V prices no part of carrying, so a transport's screen is capacity
	# per RP. The design reads the resulting order as the civ story —
	# quantity moves armies cheapest, fortification moves them in the
	# dearest and toughest hull — so this asserts the ORDER, which is the
	# claim, rather than the numbers, which are arithmetic.
	var rows := _in_role("transport")
	assert_eq(rows.size(), 4, "four civs field a pure transport")
	for row in rows:
		assert_eq(float(row["v"]), 0.0,
			"%s is a transport and should carry no weapon" % row["id"])
		assert_gt(int(row["def"].transport_capacity), 0,
			"%s is a transport that carries nothing" % row["id"])

	var by_cap := rows.duplicate()
	by_cap.sort_custom(func(a, b): return float(a["cap_per_rp"]) > float(b["cap_per_rp"]))
	assert_eq(String(by_cap[0]["civ"]), "gravesworn",
		"the quantity civ should move armies most cheaply per resource point")
	assert_eq(String(by_cap[by_cap.size() - 1]["civ"]), "emberdeep",
		"the fortification civ should move them in the dearest hull")


func test_the_siege_ship_outranges_every_shore_defence() -> void:
	# It fails "price buys power" on purpose — it is the dearest hull in
	# the game at RP 210 and its V is under every warship's. What it buys
	# is reach and demolition, neither of which V prices, so the exemption
	# is asserted against those instead of waved through.
	#
	# THE FIRST RUN OF THIS TEST FAILED AND THE DESIGN WAS WHAT WAS WRONG
	# (#311). §5.3 justified the exemption with "range 11.0 outranges
	# every shore tower" and `buildings/tower.tres` reaches 15.6, so it
	# outranged neither the tower nor the town centre. The DATA was
	# corrected rather than the claim — see the .tres and #311 for why the
	# alternative was rejected — and this is now the design's own claim,
	# asserted.
	#
	# Against EVERY armed building rather than against the tower by name:
	# the claim is "a shore defence cannot answer it", and pinning that to
	# one def would go quietly false the day something outranges a tower.
	var def := UnitRoster.by_id(SIEGE_SHIP)
	assert_not_null(def, "the siege ship must be in the roster")

	var longest := 0.0
	var longest_id := ""
	for building in BuildingSim.all_defs():
		if building.damage <= 0.0:
			continue  # not a defence; it does not answer anything
		if building.attack_range > longest:
			longest = building.attack_range
			longest_id = String(building.id)
	assert_gt(longest, 0.0, "Setup: something on shore must shoot back")
	assert_gt(def.attack_range, longest,
		"the siege ship's exemption is that it outranges a shore defence — %.1f against %s's %.1f" % [
			def.attack_range, longest_id, longest])

	# And by enough to survive a one-cell positioning error, which is what
	# makes the standoff a capability rather than a coin toss: a hex is
	# `SQRT_3` across at the shipped `hex_size` of 1.0.
	assert_gte(def.attack_range - longest, TorusSpace.SQRT_3,
		"the standoff must clear a whole hex (%.1f - %.1f = %.2f, need %.2f)" % [
			def.attack_range, longest, def.attack_range - longest, TorusSpace.SQRT_3])

	var ordinary := UnitDef.new().damage_vs_buildings
	assert_gt(def.damage_vs_buildings, ordinary,
		"and that it wrecks what it reaches, against the %.2f default" % ordinary)

	# The exemption has to be NARROW, or it is a hole. It is the only hull
	# with a building bonus above the default, and the only one that
	# outranges the shore.
	for row in _ships():
		if StringName(row["id"]) == SIEGE_SHIP:
			continue
		assert_eq(float(row["def"].damage_vs_buildings), ordinary,
			"%s also carries a siege bonus — the exemption covers one hull" % row["id"])
		assert_lt(float(row["def"].attack_range), longest,
			"%s also outranges the shore — the exemption covers one hull" % row["id"])


func test_correcting_the_siege_ships_reach_moved_no_screen_row() -> void:
	# Why #311 was fixed in the DATA and not by re-wording: `attack_range`
	# is not an input to V, so raising it moves no V, no RP and no V/RP —
	# every figure §5.3 prints is untouched, and the two rules above still
	# decide the roster. A fix that changed the screen would have needed
	# the whole roster re-derived instead.
	var def := UnitRoster.by_id(SIEGE_SHIP)
	assert_not_null(def)
	var dps := float(def.squad_size) * def.damage / maxf(def.attack_interval, 0.001)
	var ehp := float(def.squad_size) * def.health
	assert_almost_eq(sqrt(dps * ehp), 126.6, 0.1,
		"V is unchanged by the reach correction")
	var rp := float(def.cost_food + def.cost_wood) 		+ 1.5 * float(def.cost_gold + def.cost_stone)
	assert_almost_eq(rp, 210.0, 0.01, "and so is its price")


# --- the roster keeps the rules the land roster already lives under ---

func test_no_ship_invents_a_fourth_armour_class() -> void:
	# D-032's triangle has three values and adding to it would re-balance
	# every land unit as a side effect. A gunned hull is `missile` so the
	# counters keep working; a ramming or boarding hull is `infantry`.
	for row in _ships():
		var cls: String = row["def"].armour_class
		assert_true(cls == "missile" or cls == "infantry",
			"%s uses armour class %s" % [row["id"], cls])


func test_the_fearless_civ_is_fearless_at_sea_too() -> void:
	# Gravesworn ship `rout_threshold 0` and `morale_loss_per_casualty 0`
	# on every land def (#191, tests/test_fearless.gd). A hull that routed
	# would be the one place the identity stopped.
	for row in _ships():
		if String(row["civ"]) != "gravesworn":
			continue
		assert_eq(float(row["def"].rout_threshold), 0.0,
			"%s can rout, and its civ cannot" % row["id"])
		assert_eq(float(row["def"].morale_loss_per_casualty), 0.0,
			"%s loses morale, and its civ does not" % row["id"])


func test_no_ship_needs_an_authored_model() -> void:
	# #301's own constraint: nothing gates on the blocked bpy pipeline, so
	# every hull draws at the primitive tier (D-064's designed degradation).
	for row in _ships():
		assert_eq(String(row["def"].model_id), "",
			"%s names an authored model; the art pipeline is blocked" % row["id"])
		assert_eq(String(row["def"].mesh_primitive), "hull",
			"%s should draw as a hull" % row["id"])


func test_the_screen_is_printed_so_a_reviewer_can_read_it() -> void:
	# The design's §5.3 is a table in a document; this is the same table
	# recomputed from the files, so a reviewer can compare them without
	# trusting either. Printed, never asserted — the assertions above are
	# the rules.
	gut.p("naval roster screen, recomputed from /units:")
	gut.p("  %-24s %-11s %-10s %7s %6s %6s %7s" % [
		"id", "civ", "role", "V", "RP", "V/RP", "cap/RP"])
	for row in _ships():
		gut.p("  %-24s %-11s %-10s %7.1f %6.0f %6.3f %7.4f" % [
			row["id"], row["civ"], row["role"],
			row["v"], row["rp"], row["vrp"], row["cap_per_rp"]])
	assert_eq(_ships().size(), 10, "ten hulls")


func test_an_unresolved_seat_still_resolves_a_unit() -> void:
	# The bug this file's own narrowing caused, and the one that makes it
	# worth a test rather than a comment.
	#
	# `_resolve` was narrowed here so that a caller naming a REAL civ is
	# never handed another civ's hull (a dock offers `warship` first and
	# two civs field a `warboat` instead). That is right. What it missed
	# is that `CivRoster.RANDOM` is the ABSENCE of a choice, not a civ:
	# `MatchState` seats a player with it and only `_on_match_started`
	# resolves it, so on the `--lobby=0` path every seat added afterwards
	# — every load-test bot, since they connect after the match begins —
	# still said "random".
	#
	# The result was silent: `for_civ_archetype` answers null for
	# "random", `_resolve` returned null, `archetype_for` returned &"",
	# and the bot never SENT a produce order. Nothing was refused because
	# nothing was asked, so the server log was clean and it read as an
	# economy fault. Measured: squads flatlined at 14 against main's 42.
	assert_null(UnitRoster.for_civ_archetype(CivRoster.RANDOM, &"gatherers"),
		"fixture: 'random' must not name a civ, or this proves nothing")
	assert_not_null(BotBuildPlan._resolve(&"gatherers", CivRoster.RANDOM),
		"an unresolved seat must still resolve SOME unit to ask for — it is "
		+ "civ-less, not civ'd")
	assert_not_null(BotBuildPlan._resolve(&"gatherers", &""),
		"and the genuinely civ-less caller must keep working")


func test_a_caller_naming_a_real_civ_is_still_never_handed_another_civs_unit() -> void:
	# The narrowing itself must survive the fix above: this is what stops
	# a dock handing a warboat civ somebody else's warship.
	for civ in CivRoster.ids():
		for archetype in [&"warship", &"warboat", &"transport"]:
			var resolved := BotBuildPlan._resolve(archetype, StringName(civ))
			if resolved == null:
				continue
			assert_eq(resolved.civ, StringName(civ),
				"%s asked for %s and must never be handed %s's" % [
					civ, archetype, resolved.civ])


func test_a_mid_match_seat_can_still_be_asked_what_to_build() -> void:
	# The WHOLE CHAIN, on this branch alone — no union, no merge, no other
	# worker's PR. 82 asked, fairly, whether a hand-reconciled union might
	# itself have caused the production failure, and this answers that
	# without another union run: the defect needs only THIS branch's
	# narrowing plus `MatchState`'s own seating, both of which are here.
	#
	# `MatchState` seats a player with `civ = CivRoster.RANDOM` and only
	# `_on_match_started` resolves it, so any player seated after the
	# match begins — every load-test bot — asks with "random".
	var state := MatchState.new()
	state.add_player(1)
	state.add_player(2)
	# Seat 2 is the one that keeps the placeholder; seating resolves the
	# first seat's Random through `civ_rng`. That asymmetry is why exactly
	# one bot per match worked and the rest did not, which read as
	# per-civ and was not.
	var seat: Dictionary = state.seats[state.seat_of(2)]
	assert_eq(StringName(seat["civ"]), CivRoster.RANDOM,
		"fixture: a later seat must still hold the placeholder, or this "
		+ "test is not about the case that broke")

	var hall := BuildingSim.def_by_id(&"town_centre")
	assert_not_null(hall, "fixture: the town centre must exist")
	assert_false(hall.produces.is_empty(), "fixture: and produce something")

	var asked := BotBuildPlan.archetype_for(hall, StringName(seat["civ"]), 0)
	assert_ne(asked, &"",
		"a bot at an unresolved seat must still find something to ask its "
		+ "town centre for — returning \"\" here is the whole defect: the "
		+ "bot sends NO produce order at all, so the server refuses "
		+ "nothing and the log shows no refusals to find")

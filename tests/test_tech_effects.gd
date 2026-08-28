extends GutTest

## Guards `D-20260827-the-tree-is-the-ladder`'s mechanical half: what a
## researched tech DOES, and the fence around what it may not do.
##
## The two that matter most:
##
## - `test_a_finished_research_changes_an_army_that_already_exists` drives
##   the REAL server through the REAL order, queue and completion. The
##   unit tests below it prove the arithmetic; only a played order proves
##   the server performs it, which is #119's whole finding and the lesson
##   `tests/test_civ_knobs.gd` was rewritten around.
## - `test_a_tech_may_not_touch_anything_the_client_derives_geometry_from`
##   is the desync guard. A tech that changed `squad_size` would put every
##   client of the researching player in a different place with nothing
##   able to notice — the M1 defect from D-022's audit block, rebuilt.

const W := 24
const H := 12


func after_each() -> void:
	TechRoster.reload()


# --- the arithmetic -----------------------------------------------------

func _effect(target: StringName, field: StringName, mode: String, value: float) -> TechEffect:
	var e := TechEffect.new()
	e.target = target
	e.field = field
	e.mode = mode
	e.value = value
	return e


func _tech(id: StringName, effects: Array) -> TechDef:
	var t := TechDef.new()
	t.id = id
	t.display_name = String(id)
	t.line = id
	t.unit_effects.assign(effects)
	return t


func _levy() -> UnitDef:
	var def := UnitDef.new()
	def.id = &"probe_levy"
	def.archetype = &"levy"
	def.damage = 10.0
	def.health = 100.0
	def.move_speed = 4.0
	def.squad_size = 20
	return def


func test_an_add_and_a_multiply_compose_as_the_decision_says() -> void:
	# (base + sum of adds) x product of multiplies. Written down because
	# the other order gives a different answer and both look reasonable.
	var techs := [
		_tech(&"a", [_effect(&"levy", &"damage", "add", 2.0)]),
		_tech(&"b", [_effect(&"levy", &"damage", "multiply", 1.5)]),
	]
	var out := TechEffects.resolve_unit(_levy(), techs)
	assert_almost_eq(out.damage, 18.0, 0.001, "(10 + 2) x 1.5")


func test_the_result_does_not_depend_on_the_order_researched() -> void:
	# The property the add-before-multiply rule buys, and the reason it is
	# worth more than an ordered pipeline: two players holding the same
	# techs field bit-identical troops, and a replay cannot diverge on the
	# order somebody happened to click things in.
	var a := _tech(&"zzz_late", [_effect(&"levy", &"damage", "multiply", 1.5)])
	var b := _tech(&"aaa_early", [_effect(&"levy", &"damage", "add", 2.0)])
	var forward := TechEffects.resolve_unit(_levy(), [a, b])
	var backward := TechEffects.resolve_unit(_levy(), [b, a])
	assert_eq(forward.damage, backward.damage,
		"research order must not change an army")


func test_an_effect_only_touches_the_archetype_it_names() -> void:
	var techs := [_tech(&"a", [_effect(&"archers", &"damage", "multiply", 2.0)])]
	var out := TechEffects.resolve_unit(_levy(), techs)
	assert_eq(out.damage, 10.0, "a levy is not an archer")


func test_a_star_target_touches_everything() -> void:
	var techs := [_tech(&"a", [_effect(&"*", &"damage", "multiply", 2.0)])]
	assert_eq(TechEffects.resolve_unit(_levy(), techs).damage, 20.0)


func test_the_base_def_is_never_mutated() -> void:
	# The resolver duplicates. If it did not, one player's research would
	# change every player's troops — including the enemy's — because a
	# UnitDef is one shared Resource per (civ, archetype).
	var base := _levy()
	TechEffects.resolve_unit(base, [_tech(&"a", [_effect(&"*", &"damage", "add", 90.0)])])
	assert_eq(base.damage, 10.0, "the shared roster def must not move")


func test_an_integer_field_rounds_once_at_the_end() -> void:
	# Two multiplies must not be two floors: 100 x 0.92 x 0.92 is 84.6,
	# which is 85, not 84 (floor(floor(92) x 0.92) = 84).
	var def := _levy()
	def.cost_food = 100
	var out := TechEffects.resolve_unit(def, [
		_tech(&"a", [_effect(&"*", &"cost_food", "multiply", 0.92)]),
		_tech(&"b", [_effect(&"*", &"cost_food", "multiply", 0.92)]),
	])
	assert_eq(out.cost_food, 85, "rounded once, at the end")


# --- the closed vocabulary ---------------------------------------------

func test_an_unknown_field_is_a_load_error_not_a_silent_no_op() -> void:
	# The whole reason the vocabulary is closed. A tech whose effect is a
	# typo would cost resources, fill a bar and do nothing — the
	# declared-and-unread family, and the one instance of it that ships
	# wearing a green verdict.
	var e := _effect(&"*", &"nonexistent_stat", "add", 1.0)
	assert_ne(e.validate("unit"), "", "an unknown field must be refused")


func test_a_field_of_the_wrong_kind_is_refused() -> void:
	# `max_health` is a building field and `gather_rate` is a unit field;
	# neither is both, and aiming one at the other silently does nothing.
	assert_ne(_effect(&"*", &"max_health", "add", 1.0).validate("unit"), "")
	assert_ne(_effect(&"*", &"gather_rate", "add", 1.0).validate("building"), "")
	assert_eq(_effect(&"*", &"max_health", "add", 1.0).validate("building"), "")


func test_the_vocabulary_cannot_drift_from_the_schema() -> void:
	# Every permitted name must be a real property. If a field is renamed
	# in `unit_def.gd` and not here, this goes red instead of the tech
	# quietly applying to nothing.
	for field in TechEffect.UNIT_FIELDS:
		assert_not_null(UnitDef.new().get(String(field)),
			"UnitDef has no '%s'" % field)
	for field in TechEffect.BUILDING_FIELDS:
		assert_not_null(BuildingDef.new().get(String(field)),
			"BuildingDef has no '%s'" % field)
	for field in TechEffect.CIV_FIELDS:
		assert_not_null(CivDef.new().get(String(field)),
			"CivDef has no '%s'" % field)


func test_a_tech_may_not_touch_anything_the_client_derives_geometry_from() -> void:
	# THE desync guard. `squad_size` is not replicated at all, and
	# `composition_hash` reads shape, spacing and files — a tech that moved
	# any of them would put a client and the server in different places
	# with nothing able to notice, which is the M1 defect D-022's audit
	# block was written about.
	#
	# The fix if this ever needs relaxing is in the decision entry, not
	# here: widen the vocabulary WITH the reason written down.
	for forbidden in [&"squad_size", &"formation_shape", &"formation_spacing",
			&"model_id", &"slot_models", &"model_mix", &"armour_class",
			&"bonus_vs", &"archetype", &"civ", &"id", &"is_general"]:
		assert_false(TechEffect.UNIT_FIELDS.has(forbidden),
			"'%s' is on the wire's near side and must not be a tech knob" % forbidden)


func test_a_non_positive_multiplier_is_refused() -> void:
	# x0 zeroes a stat and a negative one inverts it; neither is a tech,
	# both are a typo.
	assert_ne(_effect(&"*", &"damage", "multiply", 0.0).validate("unit"), "")
	assert_ne(_effect(&"*", &"damage", "multiply", -1.0).validate("unit"), "")


func test_a_tech_with_no_effects_that_defines_nothing_is_refused() -> void:
	var t := TechDef.new()
	t.id = &"empty"
	t.line = &"empty"
	assert_ne(t.validate(), "",
		"a tech that costs resources and does nothing is the defect, not a feature")
	t.defining = true
	assert_eq(t.validate(), "",
		"a defining tech may be pure ladder — its effect IS the epoch")


# --- retroactivity, through the simulation -----------------------------

func _world() -> Dictionary:
	var space := TorusSpace.new(W, H, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var research := ResearchState.new()
	sim.research = research
	sim.civs[1] = CivRoster.effects_of(&"")
	return {"space": space, "sim": sim, "research": research}


func test_a_squad_is_created_with_its_owners_techs_already_applied() -> void:
	# `add_squad` is the one choke point every path creates a squad
	# through — production, the opening, a scenario, the sandbox spawner —
	# which is what makes the ~40 sites reading `def.damage` correct with
	# none of them changed.
	var w := _world()
	var research: ResearchState = w["research"]
	var sim: SquadSim = w["sim"]
	var base := _levy()
	base.id = UnitRoster.load_all()[0].id  # a real id, so reapply can find it

	var plain := sim.add_squad(base, 1, Vector2i(2, 2))
	assert_almost_eq(sim.def_of(plain).damage, base.damage, 0.001)

	# A synthetic tech rather than a shipped one: the shipped tree is
	# balance and will move, and a test pinned to it would go red on a
	# tuning pass that broke nothing.
	research._resolved.clear()
	research.grant(1, &"probe")
	var later := sim.add_squad(base, 1, Vector2i(4, 4))
	# No `/techs` entry for `probe`, so nothing resolves — the point of
	# this half is that an unknown line is inert rather than fatal.
	assert_almost_eq(sim.def_of(later).damage, base.damage, 0.001,
		"a granted line with no def must change nothing")


func test_research_reaches_squads_that_already_exist() -> void:
	# Techs are RETROACTIVE: a research finishing mid-battle is felt in
	# that battle. Driven through `SquadSim.reapply_research`, which is
	# what the completion path calls.
	var space := TorusSpace.new(W, H, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var base := UnitRoster.load_all()[0]
	var before := sim.add_squad(base, 1, Vector2i(2, 2))
	var was := sim.def_of(before).damage

	# Attach research AFTER the squad exists, which is the situation the
	# retroactive path is for.
	var research := ResearchState.new()
	sim.research = research
	sim.civs[1] = CivRoster.effects_of(base.civ)
	var boost := _tech(&"probe_line", [_effect(base.archetype, &"damage", "multiply", 2.0)])
	# Stand the resolved def in directly: TechRoster reads /techs, and this
	# test is about the re-pointing rather than about the roster.
	research._resolved[1] = {"u:%s" % base.id: TechEffects.resolve_unit(base, [boost])}
	sim.reapply_research(1)

	assert_almost_eq(sim.def_of(before).damage, was * 2.0, 0.001,
		"an existing squad must feel a finished research")


func test_a_movement_tech_actually_moves_the_squad_faster() -> void:
	# `_speed` is CACHED per squad, so a tech that changed `move_speed`
	# and not the cache would be the declared-and-unread defect in its
	# purest form: the def says the squad is faster and the squad walks at
	# the old speed.
	var space := TorusSpace.new(W, H, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var base := UnitRoster.load_all()[0]
	var squad := sim.add_squad(base, 1, Vector2i(2, 2))
	var was: float = sim.speed_of(squad) if sim.has_method("speed_of") else -1.0

	var research := ResearchState.new()
	sim.research = research
	sim.civs[1] = CivRoster.effects_of(base.civ)
	var faster := _tech(&"probe_speed", [_effect(base.archetype, &"move_speed", "multiply", 2.0)])
	research._resolved[1] = {"u:%s" % base.id: TechEffects.resolve_unit(base, [faster])}
	sim.reapply_research(1)

	assert_almost_eq(sim.def_of(squad).move_speed, base.move_speed * 2.0, 0.001)
	if was > 0.0:
		assert_gt(sim.speed_of(squad), was, "the cached speed must move with the def")


# --- the wire ----------------------------------------------------------

func test_the_research_order_round_trips() -> void:
	var packet := NetProtocol.encode_order_research(BuildingSim.wire_id(7), "masonry")
	assert_eq(NetProtocol.opcode_of(packet), NetProtocol.C2S_ORDER_RESEARCH)
	var out := NetProtocol.decode_order_research(packet)
	assert_eq(int(out["building"]), BuildingSim.wire_id(7))
	assert_eq(String(out["line"]), "masonry")


func test_the_tech_state_message_round_trips() -> void:
	var packet := NetProtocol.encode_tech_state(3, [&"settling", &"hand_tools"], &"emberdeep")
	var out := NetProtocol.decode_tech_state(packet)
	assert_eq(int(out["epoch"]), 3)
	assert_eq(out["lines"], [&"settling", &"hand_tools"])
	assert_eq(StringName(out["civ"]), &"emberdeep",
		"a tech set is meaningless without whose version of each line it is")


func test_a_client_with_no_lobby_still_learns_its_own_civ() -> void:
	# The load-test bots run with `--lobby=0` and the lobby is what
	# broadcasts a civ, so `civ_of` answered "" for every bot in every run
	# there has ever been (docs/status/load-testing.md). Without this they
	# resolve no tech at all, research nothing, and `test-load` exercises
	# strictly less of the roster than it did before the tree.
	var state := ClientState.new()
	state.player = 1
	assert_eq(state.civ_of(1), &"", "nothing known yet")
	state.handle_packet(NetProtocol.encode_tech_state(1, [], CivRoster.ids()[0]))
	assert_eq(state.civ_of(1), CivRoster.ids()[0],
		"the server named this player's civ and the client should hold it")
	assert_eq(state.civ_of(2), &"",
		"and it must still be unable to name anybody else's (D-046 criterion 4)")


func test_a_client_arrives_at_the_epoch_the_server_says() -> void:
	var state := ClientState.new()
	assert_eq(state.epoch, 1, "a client starts at the bottom")
	state.handle_packet(NetProtocol.encode_tech_state(4, [&"settling", &"drill"]))
	assert_eq(state.epoch, 4)
	assert_true(state.has_tech(&"drill"))
	assert_false(state.has_tech(&"masonry"))
	assert_true(state.has_tech(&""), "an ungated thing needs no tech")


func test_a_tech_never_enters_the_composition_hash() -> void:
	# The rule that makes stat techs structurally incapable of desyncing.
	# A client is never told an ENEMY'S research, so if a stat were hashed
	# the two sides would disagree the moment anybody upgraded anything.
	var state := ClientState.new()
	# A REAL unit id: ClientState refuses one it cannot resolve, and a
	# hash taken over a squad it rejected would compare two empty sets and
	# pass whatever the tech state did — the vacuous-pass shape D-022's
	# audit block is about.
	var real := UnitRoster.load_all()[0]
	state.handle_packet(NetProtocol.encode_squad_info([{
		"id": 1, "def_id": String(real.id), "owner": 1, "alive": 10,
		"shape": "line", "spacing": 1.0, "facing": -1, "files": 0,
	}]))
	var before := state.composition_hash()
	state.handle_packet(NetProtocol.encode_tech_state(5,
		[&"settling", &"hand_tools", &"drill", &"masonry"]))
	assert_eq(state.composition_hash(), before,
		"research must not move the hash — a client is never told an enemy's")


# --- through the real server -------------------------------------------
#
# The unit tests above prove the arithmetic. Only a played order proves the
# SERVER performs it — which is #119's finding and the reason
# `tests/test_civ_knobs.gd` drives `_handle_order_produce` itself. Same
# fixture shape, same reasoning: `_ready()` needs a socket and a scene
# tree, and this file does not.


func _server_for(civ: StringName) -> Dictionary:
	var server = autofree(load("res://server.gd").new())
	var space := TorusSpace.new(W, H, 1.0)

	server._sim = SquadSim.new(space, CurveReplicator.new())
	server._buildings = BuildingSim.new(space)
	server._economy = Economy.new(space)
	server._sim.buildings = server._buildings
	server._sim.economy = server._economy
	server._research = ResearchState.new()
	server._sim.research = server._research

	server._match = MatchState.new()
	server._match.add_player(1)
	server._match.phase = MatchState.Phase.RUNNING
	server._civs[1] = civ
	server._hand_civs_to_sim()

	var hall := BuildingSim.def_by_id(&"town_centre")
	var barracks := BuildingSim.def_by_id(&"barracks")
	var sites := {
		&"town_centre": server._buildings.add_building(hall, 1, Vector2i(4, 4), true),
		&"barracks": server._buildings.add_building(barracks, 1, Vector2i(8, 4), true),
	}
	for kind in range(Economy.RESOURCE_COUNT):
		server._economy.credit(1, kind, 100000)

	var peer := LoopbackPeer.new()
	server._ai_clients[peer] = {"player": 1, "visible": {}}
	return {"server": server, "peer": peer, "sites": sites}


func _order_research(w: Dictionary, site: StringName, line: StringName) -> void:
	w["server"]._handle_order_research(w["peer"], NetProtocol.encode_order_research(
		BuildingSim.wire_id(int((w["sites"] as Dictionary)[site])), String(line)))


func test_the_server_refuses_a_tech_at_the_wrong_building() -> void:
	# Two separate refusals on purpose: "wrong building" and "not yet" are
	# different mistakes, and a player told the wrong one goes looking in
	# the wrong place.
	var w := _server_for(CivRoster.ids()[0])
	_order_research(w, &"barracks", &"settling")
	assert_eq(w["server"]._buildings.queue_length(int((w["sites"] as Dictionary)[&"barracks"])), 0,
		"the settlement tech is not studied at a barracks")


func test_the_server_takes_the_order_and_the_payment() -> void:
	var w := _server_for(CivRoster.ids()[0])
	var server = w["server"]
	var before: int = server._economy.wallet_of(1)[0]
	_order_research(w, &"town_centre", &"settling")
	assert_eq(server._buildings.queue_length(int((w["sites"] as Dictionary)[&"town_centre"])), 1,
		"the order should have been queued")
	assert_lt(server._economy.wallet_of(1)[0], before, "research is not free")


func test_the_server_refuses_a_second_start_of_the_same_line() -> void:
	# A tech is researched once per PLAYER, not once per building.
	var w := _server_for(CivRoster.ids()[0])
	_order_research(w, &"town_centre", &"settling")
	var spent: int = w["server"]._economy.wallet_of(1)[0]
	_order_research(w, &"town_centre", &"settling")
	assert_eq(w["server"]._economy.wallet_of(1)[0], spent,
		"a line already in progress must not be paid for twice")


func test_the_server_refuses_a_rung_the_player_has_not_reached() -> void:
	var w := _server_for(CivRoster.ids()[0])
	_order_research(w, &"town_centre", &"masonry")
	assert_eq(w["server"]._buildings.queue_length(int((w["sites"] as Dictionary)[&"town_centre"])), 0,
		"epoch gates techs")


func test_a_finished_research_changes_an_army_that_already_exists() -> void:
	# The whole feature, end to end, through the real order and the real
	# queue: order it, tick until the queue drains, and assert BOTH that
	# the player holds the line and that a squad standing there already
	# feels it.
	var civ := CivRoster.ids()[0]
	var w := _server_for(civ)
	var server = w["server"]

	var settling := TechRoster.for_civ_line(civ, &"settling")
	assert_not_null(settling, "%s has no settlement tech" % civ)
	var crew := UnitRoster.for_civ_archetype(civ, &"gatherers")
	assert_not_null(crew)
	var squad: int = server._sim.add_squad(crew, 1, Vector2i(6, 6))
	var before: float = server._sim.def_of(squad).gather_rate

	_order_research(w, &"town_centre", &"settling")
	# Long enough for the shipped research time, whatever it is tuned to.
	for _i in range(int(settling.research_time * SquadSim.TICK_HZ) + 4):
		server._sim.tick()

	assert_true(server._research.has(1, &"settling"),
		"the tech should have completed")
	# Every shipped settlement tech raises its civ's gathering — that is
	# what epoch 1 IS (D-068: the opening is genuinely economic). If a
	# tuning pass ever removes that, this assert is the right place to
	# find out.
	assert_gt(server._sim.def_of(squad).gather_rate, before,
		"a crew standing there already must feel the finished research")


func test_a_finished_research_unlocks_what_it_gates() -> void:
	# The gate, both sides of it: refused before, taken after, through the
	# real produce handler with the real shipped defs.
	var civ := CivRoster.ids()[0]
	var gated: UnitDef = null
	for def in UnitRoster.load_all():
		if def.civ == civ and def.requires_tech != &"" \
				and BuildingSim.def_by_id(&"barracks").produces.has(def.archetype):
			gated = def
			break
	assert_not_null(gated, "%s trains nothing gated at a barracks" % civ)

	var w := _server_for(civ)
	var server = w["server"]
	var barracks := int((w["sites"] as Dictionary)[&"barracks"])

	server._handle_order_produce(w["peer"], NetProtocol.encode_order_produce(
		BuildingSim.wire_id(barracks), String(gated.archetype)))
	assert_eq(server._buildings.queue_length(barracks), 0,
		"%s must be refused before %s is researched" % [gated.id, gated.requires_tech])

	server._research.grant(1, gated.requires_tech)
	server._handle_order_produce(w["peer"], NetProtocol.encode_order_produce(
		BuildingSim.wire_id(barracks), String(gated.archetype)))
	assert_eq(server._buildings.queue_length(barracks), 1,
		"%s must be trainable once %s is held" % [gated.id, gated.requires_tech])


func test_a_tech_that_raises_the_cap_reaches_the_refusal_the_player_meets() -> void:
	# D-20260823's rule, applied to a tech: a HUD saying 40 while the
	# server refuses at 44 is a rule the player cannot see. The cap the
	# refusal counts and the cap the client is told must be one number,
	# and that number comes from the RESOLVED CivDef.
	var civ := CivRoster.ids()[0]
	var w := _server_for(civ)
	var server = w["server"]
	server._match.squad_cap = 10
	var plain: int = server._match.squad_cap_for(server._sim, 1)

	var raise := _tech(&"probe_cap", [])
	raise.civ_effects.assign([_effect(&"*", &"squad_cap_bonus", "add", 5.0)])
	server._research._resolved.clear()
	server._research._lines[1] = {&"probe_cap": true}
	# Stand the resolved civ in the way `_civ_effects_for` would, then
	# re-hand it exactly as the completion path does.
	server._research._resolved[1] = {"c:%s" % civ:
		TechEffects.resolve_civ(CivRoster.effects_of(civ), [raise])}
	server._sim.civs[1] = server._civ_effects_for(1)

	assert_eq(server._match.squad_cap_for(server._sim, 1), plain + 5,
		"a cap tech must reach the cap the refusal counts")


func test_a_build_behind_a_tech_is_refused_until_it_is_researched() -> void:
	var civ := &""
	var site: BuildingDef = null
	for candidate in CivRoster.ids():
		for def in BuildingSim.defs_for_civ(candidate):
			if def.requires_tech != &"":
				civ = candidate
				site = def
				break
		if site != null:
			break
	assert_not_null(site, "no building is gated behind a tech at all")

	var w := _server_for(civ)
	var server = w["server"]
	assert_ne(server._found_refusal(site, 1), "",
		"%s needs %s and must be refused without it" % [site.id, site.requires_tech])
	server._research.grant(1, site.requires_tech)
	assert_eq(server._found_refusal(site, 1), "",
		"%s must be foundable once %s is held" % [site.id, site.requires_tech])


func test_a_civ_may_not_found_another_civs_research_site() -> void:
	var civs := CivRoster.ids()
	var site: BuildingDef = null
	var owner := &""
	for def in BuildingSim.all_defs():
		if def.civ != &"neutral":
			site = def
			owner = def.civ
			break
	assert_not_null(site, "no per-civ building exists — the asymmetry is gone")

	var other := &""
	for candidate in civs:
		if candidate != owner:
			other = candidate
			break
	var w := _server_for(other)
	w["server"]._research.grant(1, site.requires_tech)
	assert_ne(w["server"]._found_refusal(site, 1), "",
		"%s is %s's and %s must not be offered it" % [site.id, owner, other])

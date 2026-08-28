extends GutTest

## Guards D-20260818-ai-profiles-are-data — an AI's difficulty is a .tres
## under /ai/, and it is never a cheat.
##
## Two halves, and both are load-bearing.
##
## The DATA half checks that the engine does not know which difficulties
## exist, which is what makes "add Hard" a file rather than a programming
## task — the same property D-046 criterion 3 buys for civs, tested the
## same way.
##
## The WIRING half checks that a profile field actually reaches a
## decision. Every field here replaced a `const` whose doc comment had
## promised for two milestones that it "becomes a profile field in the
## next slice (D-053)" — a decision nobody ever wrote. A schema that
## loaded, validated and was read by nothing would be the fifth instance
## of this project's declared-and-unread family, and it would look
## exactly like a finished feature.

const W := 48
const H := 24

const ENEMY := 2000


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


# --- the data half ----------------------------------------------------

func test_the_shipped_profiles_load_and_validate() -> void:
	var profiles := AiProfileRoster.load_all()
	assert_gt(profiles.size(), 2,
		"Fewer than three difficulties ship, so there is no ladder to choose from")
	for def in profiles:
		assert_eq(def.validate(), "", "profile %s is invalid" % def.id)
		assert_ne(def.display_name, "", "profile %s has no display name" % def.id)
		assert_ne(def.summary, "",
			"profile %s says nothing about itself, so a lobby cannot describe it" % def.id)


func test_exactly_one_profile_is_the_default() -> void:
	# Two would make "the default" depend on filename sort order, which is
	# the kind of answer that is right until somebody adds a file. None
	# would silently fall back to the schema, so a shipped profile could
	# be quietly bypassed by everything.
	var defaults := []
	for def in AiProfileRoster.load_all():
		if def.is_default:
			defaults.append(def.id)
	assert_eq(defaults.size(), 1,
		"Exactly one shipped profile must be the default, found: %s" % [defaults])
	assert_eq(AiProfileRoster.default().id, StringName(defaults[0]),
		"AiProfileRoster.default() did not return the profile the data marks")


## Directories whose scripts may name a profile. Tests are excluded
## because a test's job is to assert things about the data, which
## sometimes means naming it — and nothing under tests/ ships.
const EXEMPT_PREFIXES := ["res://tests/", "res://addons/"]


func _all_scripts(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		_all_scripts(path.path_join(sub), out)
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".gd"):
			out.append(path.path_join(normalised))


func test_no_script_mentions_a_profile_id() -> void:
	# The criterion the whole decision turns on, and the check that
	# actually failed for civs before CivDef existed. If this goes red,
	# the fix is never to add the id to an exempt list; it is to find the
	# knob the branch wanted and give it to every profile.
	var profile_ids := AiProfileRoster.ids()
	assert_gt(profile_ids.size(), 1, "This check is vacuous with fewer than two profiles")

	var scripts: Array = []
	_all_scripts("res://", scripts)
	assert_gt(scripts.size(), 10, "Found almost no scripts — the walk is broken, not the code clean")

	var offences: Array = []
	for script_path in scripts:
		var exempt := false
		for prefix in EXEMPT_PREFIXES:
			if String(script_path).begins_with(prefix):
				exempt = true
				break
		if exempt:
			continue

		var handle := FileAccess.open(script_path, FileAccess.READ)
		if handle == null:
			continue
		var text := handle.get_as_text()
		handle.close()

		for id in profile_ids:
			if text.contains(String(id)):
				offences.append("%s names AI profile '%s'" % [script_path, id])

	assert_eq(offences, [],
		"Scripts must not know which difficulties exist — adding one would stop being a data change")


func test_the_default_profile_is_the_ai_that_already_shipped() -> void:
	# Clause 3. Every ladder figure ever taken was taken against these
	# numbers, so moving them would leave the ladder measuring two things
	# at once — the shape of M6's still-unattributed 40.8 -> ~77 µs/squad
	# rise. Pinned rather than described, because a comment saying "these
	# are the old constants" is not evidence that they are.
	var built_in := AiProfileDef.new()
	assert_eq(built_in.think_interval, 1.0)
	assert_eq(built_in.gatherer_soldiers_wanted, 110)
	assert_eq(built_in.train_cooldown, 5.0)
	assert_eq(built_in.attack_squads_minimum, 2)
	assert_eq(built_in.attack_regroup_thinks, 8.0)
	assert_eq(built_in.food_floor, 180)
	assert_eq(built_in.wood_floor, 200)
	# #337 added this one, and it is the ONE field on which the shipped
	# default is deliberately NOT the AI that already shipped: the old one
	# built no static defence at all, because it could not — every wall,
	# gate and tower costs stone and it never gathered any.
	#
	# 0.0 would have preserved the letter of the clause above and shipped
	# a knob no profile exercises, which is `gather_speed` sitting at 1.0
	# on every civ for a milestone (#158). So the default USES the
	# feature, and the honest consequence is stated where it belongs:
	# **every ladder figure taken before #337 was taken against an AI that
	# never fortified**, and the standing "quote a result with its cap"
	# rule gains a clause — quote which side of this change it came from.
	assert_eq(built_in.defence_appetite, 0.5)

	# ...and the shipped default is those defaults written out, so a
	# missing /ai costs difficulty and never the game (clause 2).
	var shipped := AiProfileRoster.default()
	assert_eq(shipped.think_interval, built_in.think_interval)
	assert_eq(shipped.gatherer_soldiers_wanted, built_in.gatherer_soldiers_wanted)
	assert_eq(shipped.train_cooldown, built_in.train_cooldown)
	assert_eq(shipped.attack_squads_minimum, built_in.attack_squads_minimum)
	assert_eq(shipped.attack_regroup_thinks, built_in.attack_regroup_thinks)
	assert_eq(shipped.defence_appetite, built_in.defence_appetite)


func test_every_profile_carries_the_same_resource_floors() -> void:
	# Clause 4. The floors were lifted because ai_player.gd's comment
	# asked for them, not because they are a difficulty axis: a floor is
	# where the economy stalls, and moving one without measuring is how
	# the AI spent a whole session gathering zero wood beside a healthy
	# food pile.
	var profiles := AiProfileRoster.load_all()
	for def in profiles:
		assert_eq(def.food_floor, profiles[0].food_floor,
			"profile %s moves the food floor, which is not a measured axis yet" % def.id)
		assert_eq(def.wood_floor, profiles[0].wood_floor,
			"profile %s moves the wood floor, which is not a measured axis yet" % def.id)


func test_the_levels_ramp_harder_the_further_down_the_list() -> void:
	# Asked of the ORDER field rather than of ids, so this file names no
	# profile either. A list a player is shown easiest-first must actually
	# be ordered on the pacing axis, or the lobby is lying about what it
	# offers.
	#
	# Note this asserts the SHAPE of the ladder, not its strength: whether
	# a harder ramp wins is a ladder measurement (clause 5), and this test
	# would be exactly as green if it did not.
	var profiles := AiProfileRoster.load_all()
	for i in range(1, profiles.size()):
		var easier := profiles[i - 1]
		var harder := profiles[i]
		assert_true(harder.gatherer_soldiers_wanted <= easier.gatherer_soldiers_wanted,
			"%s spends longer on its economy than %s, which is further up the list"
				% [harder.id, easier.id])
		assert_true(harder.train_cooldown <= easier.train_cooldown,
			"%s ramps its army more slowly than %s" % [harder.id, easier.id])
		assert_true(harder.think_interval <= easier.think_interval,
			"%s reconsiders less often than %s" % [harder.id, easier.id])


# --- dealing profiles to seats ---------------------------------------

func test_nothing_chosen_deals_the_default_to_every_seat() -> void:
	# What `test-load`, `test-scenario` and the existing ladder invocation
	# all get, and the reason none of them measures a different AI today
	# than it measured yesterday.
	var dealt := AiProfileRoster.resolve_list("", 3)
	assert_eq(dealt.size(), 3)
	for def in dealt:
		assert_eq(def.id, AiProfileRoster.default().id)


func test_a_list_is_dealt_round_robin_across_the_seats() -> void:
	var ids := AiProfileRoster.ids()
	var spec := "%s,%s" % [ids[0], ids[1]]
	var dealt := AiProfileRoster.resolve_list(spec, 5)
	assert_eq(dealt.size(), 5)
	assert_eq(dealt[0].id, ids[0])
	assert_eq(dealt[1].id, ids[1])
	assert_eq(dealt[2].id, ids[0], "The list did not wrap round to the first profile")
	assert_eq(dealt[4].id, ids[0])


func test_an_unknown_profile_is_refused_rather_than_defaulted() -> void:
	# D-20260817-recipe-args-are-positional's lesson on the far side of
	# the boundary: a silent fallback here is a ladder run reporting a
	# pairing it never played. An empty result is a caller's cue to refuse
	# to start.
	assert_eq(AiProfileRoster.resolve_list("no_such_difficulty", 2), [],
		"An unknown profile name was quietly replaced with a real one")
	var ids := AiProfileRoster.ids()
	assert_eq(AiProfileRoster.resolve_list("%s,nonsense" % ids[0], 2), [],
		"One bad name in a list must refuse the whole list, not seat half of it")


# --- the wiring half --------------------------------------------------
#
# Every test below fails if `AiPlayer` still reads a constant. That is the
# whole point: a schema that loads and validates and is read by nothing is
# indistinguishable from a finished feature.


## A military unit this civ actually fields — a real roster def, because
## `_fight` resolves `UnitRoster.by_id` and a synthetic one would not be
## found. The general is excluded so the fixture is not also measuring the
## morale aura while we watch what an AI attacks with.
func _military_def(civ: StringName) -> UnitDef:
	for def in UnitRoster.for_civ(civ):
		if def.damage > 1.0 and def.carry_capacity <= 0 and not def.is_general:
			return def
	return null


## An AI holding `squads` military squads, with one enemy town centre
## standing where it can see it, and nothing else to do but decide
## whether to march.
func _army_ai(profile: AiProfileDef, squads: int) -> Dictionary:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var ai := AiPlayer.new(1000, CivRoster.ids()[0])
	ai.profile = profile

	var def := _military_def(ai.civ)
	assert_not_null(def, "This civ fields no military unit, so the fixture proves nothing")
	for i in range(squads):
		sim.add_squad(def, 1000, Vector2i(8 + i, 8))
	sim.tick()

	var seats := [{"kind": "ai", "player": 1000, "civ": String(ai.civ),
		"team": 0, "name": "AI 1000"}]
	ai.state.handle_packet(NetProtocol.encode_lobby(0, seats, {}, 1))

	var spawn_indices := [space.index(Vector2i(8, 8)), space.index(Vector2i(30, 8))]
	var visible := sim.visible_to(1000)
	ai.state.handle_packet(NetProtocol.encode_welcome(1000, W, H, visible, spawn_indices))
	ai.state.handle_packet(NetProtocol.encode_squad_info(sim.squad_info_entries(visible)))
	for packet in sim.replicator.collect_for_client(1000, sim.time, visible):
		ai.state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))

	# Something to march ON. Buildings are the objective (see
	# `_enemy_target`), so this is what a decision to attack looks like.
	var buildings := BuildingSim.new(space)
	var hall := buildings.add_building(
		BuildingSim.def_by_id(&"town_centre"), ENEMY, Vector2i(30, 8), true)
	ai.state.handle_packet(NetProtocol.encode_building_info(buildings.info_entries([hall])))
	assert_false(ai.state.are_allied(ENEMY, 1000), "Setup: the fixture has no enemy in it")

	var sent := []
	ai.send = func(packet: PackedByteArray) -> void: sent.append(packet)
	ai.set_time(sim.time)
	return {"sim": sim, "ai": ai, "sent": sent}


func _attack_orders(sent: Array) -> int:
	var count := 0
	for packet in sent:
		if NetProtocol.opcode_of(packet) == NetProtocol.C2S_ORDER_ATTACK_MOVE:
			count += 1
	return count


func _profile(fields: Dictionary) -> AiProfileDef:
	var def := AiProfileDef.new()
	def.id = &"test_profile"
	def.display_name = "Test"
	for key in fields:
		def.set(key, fields[key])
	return def


func test_an_ai_seated_with_no_profile_still_has_one() -> void:
	# The fallback matters more than it looks: `server.gd` seats AI from
	# three different doors (the command line, the lobby, a return to the
	# lobby), and a null profile on any of them is a crash on the first
	# think rather than a difficulty that did not apply.
	var ai := AiPlayer.new(1000, CivRoster.ids()[0])
	assert_not_null(ai.profile, "An AI was constructed with no profile at all")
	assert_eq(ai.profile.think_interval, AiProfileRoster.default().think_interval)


func test_a_profile_governs_how_often_the_ai_reconsiders() -> void:
	# THINK_INTERVAL was a const, so an AI told to think every ten seconds
	# thought every one.
	#
	# Watched through `_record_stats` rather than through orders, and that
	# is not incidental. The first version of this test asserted that no
	# further ORDER was sent, and passed against the un-wired code: every
	# order the fixture can produce is behind a second cooldown of its
	# own, so "did not act" said nothing about whether it had thought.
	# Stats are recorded on every think with nothing else gating them, so
	# they answer the question actually being asked.
	var w := _army_ai(_profile({"think_interval": 10.0}), 3)
	var ai: AiPlayer = w["ai"]
	var t: float = w["sim"].time

	ai.update(t)
	assert_eq(ai.peak_food, 0, "Setup: the fixture started with food in the bank")

	# A wallet it can only have noticed by thinking again. One second
	# later is a think under the old constant, and far too soon under this
	# profile.
	ai.state.handle_packet(NetProtocol.encode_wallet(PackedInt32Array([500, 0, 0, 0])))
	ai.set_time(t + 1.0)
	ai.update(t + 1.0)
	assert_eq(ai.peak_food, 0,
		"The AI thought again after 1 s while its profile asks for 10 — the field is not read")

	ai.set_time(t + 10.0)
	ai.update(t + 10.0)
	assert_eq(ai.peak_food, 500,
		"...and it never thought again at all, so the check above is vacuous")


func test_a_profile_governs_how_much_army_it_commits_with() -> void:
	# The knob a human actually feels: what ARRIVES, rather than when.
	# Three squads is enough for the shipped default and not enough for a
	# profile that masses four.
	var massing := _army_ai(_profile({"attack_squads_minimum": 4}), 3)
	var ai: AiPlayer = massing["ai"]
	ai.update(massing["sim"].time)
	assert_eq(_attack_orders(massing["sent"]), 0,
		"An AI told to mass four squads attacked with three")

	var eager := _army_ai(_profile({"attack_squads_minimum": 2}), 3)
	var eager_ai: AiPlayer = eager["ai"]
	eager_ai.update(eager["sim"].time)
	assert_eq(_attack_orders(eager["sent"]), 3,
		"...and one told to commit with two did not march, so the check above is vacuous")


func test_a_profile_governs_how_long_an_attack_is_left_to_run() -> void:
	# `_attack_at` was `now + THINK_INTERVAL * 8.0` — two constants
	# multiplied together, so neither could be moved without the other.
	var w := _army_ai(_profile({"think_interval": 1.0, "attack_regroup_thinks": 4.0}), 3)
	var ai: AiPlayer = w["ai"]
	var sim: SquadSim = w["sim"]

	ai.update(sim.time)
	assert_eq(_attack_orders(w["sent"]), 3, "Setup: it should have marched")
	w["sent"].clear()

	# Under the shipped 8 thinks this is still inside the window; under
	# this profile's 4 it is not.
	var later := sim.time + 5.0
	ai.set_time(later)
	ai.update(later)
	assert_eq(_attack_orders(w["sent"]), 3,
		"The AI did not re-order its army after its own regroup window had passed")


func test_the_stats_line_says_which_profile_played_and_how_big_the_first_attack_was() -> void:
	# The pacing metric #93 asks for, and the field that lets the ladder
	# attribute a result to a pairing at all. `first_attack` on its own
	# says when the army arrived and nothing about what turned up.
	var w := _army_ai(_profile({"attack_squads_minimum": 2}), 3)
	var ai: AiPlayer = w["ai"]
	ai.update(w["sim"].time)

	var line := ai.stats_line()
	assert_true(line.contains("profile=test_profile"),
		"AI_STATS does not name the profile that played: %s" % line)

	var expected := 0
	for squad in ai.state.squads:
		expected += ai.state.alive_of(squad)
	assert_gt(expected, 0, "Setup: this AI has no soldiers, so the size below is vacuous")
	assert_eq(ai.first_attack_soldiers, expected,
		"The size of the first attack was not recorded")
	assert_true(line.contains("first_attack_soldiers=%d" % expected),
		"AI_STATS does not carry the size of the first attack: %s" % line)

extends GutTest

## Guards D-047 (civilizations as data) and D-046's criteria 1-4.
##
## The centrepiece is test_no_script_mentions_a_civ_id. Everything else
## here checks that the data says what it should; that one checks that the
## ENGINE does not know which civs exist, which is the property that makes
## D-015's "4-6 civilizations at launch" a content job instead of six
## engineering projects.


func _first_civ() -> StringName:
	var ids := CivRoster.ids()
	assert_gt(ids.size(), 0, "no civs are shipped at all")
	return ids[0]


# --- the criterion the milestone turns on -----------------------------

## Directories whose scripts are allowed to name a civ.
##
## Tests are excluded because a test's job is to assert things about the
## data, which sometimes means naming it. Excluding them does not weaken
## the check: the check is about the ENGINE, and nothing under tests/
## ships.
##
## `playtest_obs/` is excluded for the same reason and it is the same
## sentence: those are observation harnesses that print and assert
## nothing, they are run by hand and collected by nothing, and a
## civ-differentiation harness cannot compare civs without naming them.
## Nothing under it ships either — which is the clause the exclusion
## actually rests on, so if anything there ever becomes engine code it
## belongs outside that directory rather than inside this list.
const EXEMPT_PREFIXES := ["res://tests/", "res://addons/", "res://playtest_obs/"]


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


func test_no_script_mentions_a_civ_id() -> void:
	# D-046 criterion 3, and the reason CivDef, the archetype field and
	# UnitRoster.for_civ_archetype all exist.
	#
	# If this fails, adding the third civilization has stopped being a
	# matter of dropping .tres files in and has become a programming task
	# — which is the exact failure the milestone was written to prevent.
	# The fix is never to add the id to an exempt list; it is to find the
	# knob the branch wanted and give it to every civ (D-047).
	var civ_ids := CivRoster.ids()
	assert_gt(civ_ids.size(), 1, "This check is vacuous with fewer than two civs")

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

		for civ in civ_ids:
			if text.contains(String(civ)):
				offences.append("%s names civ '%s'" % [script_path, civ])

	assert_eq(offences, [],
		"Scripts must not know which civs exist — adding a civ would stop being a data change")


# --- a civ is data (D-047) --------------------------------------------

func test_the_shipped_civs_load_and_validate() -> void:
	var civs := CivRoster.load_all()
	assert_gt(civs.size(), 1, "M6 needs a second civ to be about anything")
	for civ in civs:
		assert_eq(civ.validate(), "", "civ %s is invalid" % civ.id)
		assert_ne(civ.display_name, "", "civ %s has no display name" % civ.id)


func test_each_civ_fields_a_different_subset_of_archetypes() -> void:
	# The subset is the point (D-047): a civ that fielded everything would
	# make the roster a menu rather than an identity.
	var seen := {}
	for civ in CivRoster.ids():
		var archetypes := UnitRoster.archetypes_for(civ)
		assert_gt(archetypes.size(), 2, "civ %s fields almost nothing" % civ)
		seen[civ] = archetypes

	var civs := CivRoster.ids()
	var a: Array = seen[civs[0]]
	var b: Array = seen[civs[1]]
	assert_ne(a, b, "Two civs field the identical set of archetypes, so neither has an identity")

	var a_only := a.filter(func(x): return not b.has(x))
	var b_only := b.filter(func(x): return not a.has(x))
	assert_gt(a_only.size() + b_only.size(), 0,
		"Neither civ has an exclusive archetype (D-046 criterion 2)")


func test_a_shared_archetype_is_tuned_differently_per_civ() -> void:
	# "The same type is not the same troops in two armies." Without this,
	# the subset alone would make civs differ only in what they lack.
	var civs := CivRoster.ids()
	var differing := 0
	for archetype in UnitRoster.archetypes_for(civs[0]):
		var first := UnitRoster.for_civ_archetype(civs[0], archetype)
		var second := UnitRoster.for_civ_archetype(civs[1], archetype)
		if first == null or second == null or first == second:
			continue  # not shared, or the neutral pool
		if first.damage != second.damage or first.health != second.health \
				or first.cost_food != second.cost_food:
			differing += 1
	assert_gt(differing, 0,
		"Every shared archetype has identical stats in both civs — the tuning half of D-047 is missing")


func test_a_civ_only_fields_its_own_units_and_the_neutral_pool() -> void:
	for civ in CivRoster.ids():
		for def in UnitRoster.for_civ(civ):
			assert_true(def.civ == civ or def.civ == &"neutral",
				"%s is offered to civ %s but belongs to %s" % [def.id, civ, def.civ])


func test_asking_for_an_archetype_a_civ_lacks_returns_nothing() -> void:
	# What the server relies on to refuse production (D-046 criterion 4).
	# If this returned some other civ's unit, a player could field an army
	# they have no right to and nothing would notice.
	var civs := CivRoster.ids()
	var exclusive := &""
	for archetype in UnitRoster.archetypes_for(civs[0]):
		if UnitRoster.for_civ_archetype(civs[1], archetype) == null:
			exclusive = archetype
			break

	assert_ne(exclusive, &"", "No archetype is exclusive, so this cannot be tested")
	assert_null(UnitRoster.for_civ_archetype(civs[1], exclusive),
		"A civ was handed another civ's exclusive unit")
	assert_not_null(UnitRoster.for_civ_archetype(civs[0], exclusive),
		"The owning civ cannot field its own exclusive unit")


func test_every_unit_declares_an_archetype() -> void:
	for def in UnitRoster.load_all():
		assert_ne(def.archetype, &"", "%s has no archetype" % def.id)


# --- random civ selection (D-048 criterion 8) -------------------------

func test_random_resolves_to_a_real_civ() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for _i in range(20):
		var picked := CivRoster.resolve(CivRoster.RANDOM, rng)
		assert_not_null(CivRoster.by_id(picked), "random gave '%s', which is not a civ" % picked)


func test_random_is_unbiased_across_civs() -> void:
	# "Unbiased toward any specific civ for now" is a stated intent, and
	# an intent is worth checking rather than trusting — a draw that
	# favoured one civ would quietly shape every match and look like
	# balance feedback.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var counts := {}
	var draws := 4000
	for _i in range(draws):
		var picked := CivRoster.resolve(CivRoster.RANDOM, rng)
		counts[picked] = int(counts.get(picked, 0)) + 1

	var civs := CivRoster.ids()
	var expected := float(draws) / float(civs.size())
	for civ in civs:
		var got := float(counts.get(civ, 0))
		assert_almost_eq(got, expected, expected * 0.15,
			"civ %s drawn %d times of %d, expected about %.0f" % [civ, got, draws, expected])


func test_the_same_seed_draws_the_same_civ() -> void:
	# Replays reconstruct a match (D-016), and a match whose civs differed
	# on replay would not be a replay of that match.
	var first := RandomNumberGenerator.new()
	first.seed = 7
	var second := RandomNumberGenerator.new()
	second.seed = 7
	for _i in range(10):
		assert_eq(CivRoster.resolve(CivRoster.RANDOM, first),
			CivRoster.resolve(CivRoster.RANDOM, second),
			"The same seed produced a different civ")


func test_an_explicit_choice_is_honoured_rather_than_rerolled() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var wanted := _first_civ()
	for _i in range(10):
		assert_eq(CivRoster.resolve(wanted, rng), wanted,
			"An explicit civ choice was overridden by the random path")


func test_an_unknown_choice_falls_back_rather_than_failing() -> void:
	# A client can send anything (D-002). An unknown civ must not leave a
	# player with no civ at all, which would strand them with no roster.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var picked := CivRoster.resolve(&"not_a_civ", rng)
	assert_not_null(CivRoster.by_id(picked), "An unknown civ choice left the player with nothing")


# --- replays record who played as whom (D-046 criterion 11) -----------

func test_a_replay_records_seats_with_civ_and_team() -> void:
	# With asymmetric civs (D-047), "who won" is most of "what happened".
	# A replay that reconstructed only the motion could not answer it.
	var seats := [
		{"player": 1, "team": 1, "civ": String(CivRoster.ids()[0]), "name": "Player 1"},
		{"player": 2, "team": 2, "civ": String(CivRoster.ids()[1]), "name": "AI 1000"},
	]
	var decoded := ReplayLog.decode_seats(_encoded_seats(seats))

	assert_eq(decoded.size(), 2)
	assert_eq(int(decoded[0]["player"]), 1)
	assert_eq(String(decoded[0]["civ"]), String(CivRoster.ids()[0]))
	assert_eq(int(decoded[1]["team"]), 2, "The side a player fought on is part of the record")
	assert_eq(String(decoded[1]["name"]), "AI 1000")


## Round-trips a seat list through the real writer and reader, so this
## tests the format rather than a re-implementation of it.
func _encoded_seats(seats: Array) -> PackedByteArray:
	var path := "user://test-seats-replay.edmw"
	var writer := ReplayLog.new()
	assert_eq(writer.open_for_write(path, 10.0, TorusSpace.new(16, 8, 1.0)), OK)
	writer.record_seats(0.0, seats)
	writer.close()

	var replay := ReplayLog.read(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for record in replay["records"]:
		if int(record["kind"]) == ReplayLog.Kind.SEATS:
			# Re-encode so the assertions above run against the decoder,
			# not against the dictionary that went in.
			var buf := StreamPeerBuffer.new()
			buf.put_u32(record["seats"].size())
			for seat in record["seats"]:
				buf.put_u32(int(seat["player"]))
				buf.put_u8(int(seat["team"]))
				var civ := String(seat["civ"]).to_utf8_buffer()
				buf.put_u16(civ.size())
				buf.put_data(civ)
				var name := String(seat["name"]).to_utf8_buffer()
				buf.put_u16(name.size())
				buf.put_data(name)
			return buf.data_array
	assert_true(false, "No SEATS record survived the round trip")
	return PackedByteArray()


func test_an_old_replay_without_seats_is_still_readable() -> void:
	# SEATS is a new record kind. A reader skips unknown kinds by their
	# length prefix, so adding one must not strand replays written before
	# it existed — which is the reason it was added as a kind rather than
	# folded into the header.
	var path := "user://test-noseats-replay.edmw"
	var writer := ReplayLog.new()
	assert_eq(writer.open_for_write(path, 10.0, TorusSpace.new(16, 8, 1.0)), OK)
	writer.record_squad_info(0.0, NetProtocol.encode_squad_info([]))
	writer.close()

	var replay := ReplayLog.read(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_gt(int(replay["records"].size()), 0, "A replay with no seats record should still read")


# --- a civ's pitch is SHOWN (#214) ------------------------------------

func test_every_shipped_civ_has_a_pitch_worth_showing() -> void:
	# `CivDef.summary` is player-facing text now
	# (D-20260828-a-summary-is-shown-or-it-is-deleted), so it is held to
	# the standard player-facing text is held to — including being real
	# UTF-8, which all six were not (#231; `test_data_encoding.gd` is the
	# general guard, this is the one that reads the STRING).
	var seen := 0
	for id in CivRoster.ids():
		var def := CivRoster.by_id(id)
		assert_not_null(def, "civ %s must load" % id)
		assert_ne(def.summary.strip_edges(), "",
			"civ %s tells a player nothing about itself" % id)
		assert_false(def.summary.contains("�"),
			"civ %s's pitch contains a replacement character — its file is not UTF-8" % id)
		seen += 1
	assert_gt(seen, 1, "there must be civs to check, or this proves nothing")


func test_the_lobby_actually_reads_a_civs_pitch() -> void:
	# The caller-exists scan (D-106's pattern), and the ONLY check that
	# could have caught #214: every assertion above passes with the field
	# shown nowhere, which is exactly the state it shipped in for a
	# milestone. A field kept "for the lobby" that the lobby has never
	# shown is what teaches the next reader to distrust the next comment.
	var source := FileAccess.get_file_as_string("res://client.gd")
	assert_ne(source, "", "Setup: client.gd should be readable")
	var code := ""
	for line in source.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	assert_true(code.contains("def.summary"),
		"nothing in client.gd reads CivDef.summary")
	assert_true(code.contains("_civ_summary("),
		"and nothing calls the helper that would put it on screen")
	# On the control a civ is CHOSEN with, not merely computed somewhere.
	assert_true(code.contains("set_item_tooltip(") or code.contains("picker.tooltip_text"),
		"the pitch is computed and never attached to the civ picker")

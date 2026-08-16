extends GutTest

## Guards D-104: `MapSettings.to_spawn_config` is the ONE derivation of
## where players start, and what it needs travels on the wire.
##
## The defect this exists for: `client.gd` drew spawn markers on the lobby
## map preview from its own `MapConfig`, seeded with the match seed, while
## `server.gd` seeded its own with the map file's base PLUS the match seed.
## Both called `MapConfig.spawn_points` — the shared implementation — under
## a comment saying so, and on the reported world not one of the twenty
## markers the preview drew was a place anybody started. Sharing an
## implementation is not sharing its arguments.
##
## Modelled on test_world_look_is_the_only_light.gd, and for the same
## reason: a convention that only lives in a comment is what failed here,
## so this scans source text as well as behaviour. The comment asserting
## correctness is the part that let it survive (the D-065 family).

const EXEMPT_PREFIXES := ["res://tests/", "res://addons/"]
const EXEMPT_FILES := ["res://map_settings.gd", "res://map_config.gd"]


func _settings() -> MapSettings:
	# The reported world: 168x194 `islands`, seed 1337, 20 slots.
	var out := MapSettings.new()
	out.width = 168
	out.height = 194
	out.player_slots = 20
	out.seed = 1337
	out.apply_preset(TerrainPresetRoster.by_id(&"islands"))
	# Every spawn rule deliberately AWAY from its script default, the way
	# `maps/ladder.tres` already sets its own. Leave them at the defaults
	# and the comparison below passes whether or not the wire carries
	# them, because both sides fall back to the same numbers — which is
	# how the bug looked from the client right up until a map file
	# disagreed.
	out.spawn_seed = 4242
	out.min_spawn_spacing = 11
	out.min_spawn_landmass = 90
	return out


func test_the_lobby_preview_samples_exactly_the_server_points() -> void:
	# The server holds a MapSettings it seeded from the map file; the
	# client holds whatever came off the wire. Same points, or the preview
	# is a picture of somewhere else.
	var server_side := _settings()
	var client_side := MapSettings.from_dict(server_side.to_dict())

	var space := server_side.to_space()
	var passable := server_side.to_terrain().passability(space)

	var server_points := server_side.to_spawn_config().spawn_points(passable)
	var preview_points := client_side.to_spawn_config().spawn_points(passable)

	assert_eq(preview_points.size(), server_points.size(),
		"The preview and the server disagree about how many starts there are")
	assert_gt(server_points.size(), 0, "No points at all, so the comparison proves nothing")
	assert_eq(preview_points, server_points,
		"Every marker the lobby preview draws must be a place somebody actually starts")


func test_the_wire_carries_the_spawn_seed_rather_than_defaulting_to_it() -> void:
	# The counter-test. Without it, the check above would pass just as
	# happily if `to_dict` dropped the spawn fields and both sides fell
	# back to the same script defaults — which is exactly how the bug
	# looked from the client's side, right up until a map file changed one.
	var server_side := _settings()
	server_side.spawn_seed = 999
	server_side.min_spawn_landmass = 12

	var wire := server_side.to_dict()
	assert_eq(int(wire.get("spawn_seed", -1)), 999,
		"MapSettings.to_dict must carry the spawn seed — the preview cannot reproduce a number it was never sent")

	var client_side := MapSettings.from_dict(wire)
	assert_eq(client_side.spawn_seed, 999)
	assert_eq(client_side.min_spawn_spacing, server_side.min_spawn_spacing)
	assert_eq(client_side.min_spawn_landmass, 12)


func test_the_spawn_rules_survive_the_map_settings_PACKET() -> void:
	# Not the dictionary — the PACKET. `to_dict` carrying a field and the
	# wire carrying it are different claims, and `encode_map_settings` is
	# field by field, so a value added to the dictionary alone arrives as
	# whatever the client's default happens to be. That is D-065 exactly:
	# a decision saying a field is replicated is not evidence that it is,
	# and the way to find out is to open the encoder.
	var sent := _settings()
	var received := MapSettings.from_dict(
		NetProtocol.decode_map_settings(
			NetProtocol.encode_map_settings(sent.to_dict())))

	assert_eq(received.spawn_seed, sent.spawn_seed,
		"the spawn seed did not survive the wire — the client would sample somewhere else entirely")
	assert_eq(received.min_spawn_spacing, sent.min_spawn_spacing)
	assert_eq(received.min_spawn_landmass, sent.min_spawn_landmass)
	assert_eq(received.to_spawn_config().spawn_seed, sent.to_spawn_config().spawn_seed)


func test_the_spawn_seed_mixes_the_map_base_with_the_match_seed() -> void:
	# Re-rolling the seed in the lobby must move the STARTS as well as the
	# ground, and two maps sharing a match seed must not share a layout.
	var a := _settings()
	var b := _settings()
	b.seed = a.seed + 1

	assert_eq(a.to_spawn_config().spawn_seed, a.spawn_seed + a.seed,
		"The sampler seed is the map's base plus the match seed")
	assert_ne(a.to_spawn_config().spawn_points(), b.to_spawn_config().spawn_points(),
		"Changing the match seed did not move anybody's start")


func test_the_spawn_config_carries_every_rule_the_sampler_reads() -> void:
	# A field added to MapConfig and forgotten here is the same defect
	# again, one field along: the preview would sample by a rule the server
	# does not use.
	var settings := _settings()
	settings.min_spawn_spacing = 17
	settings.min_spawn_landmass = 44

	var config := settings.to_spawn_config()
	assert_eq(config.width, settings.width)
	assert_eq(config.height, settings.height)
	assert_eq(config.player_slots, settings.player_slots)
	assert_eq(config.min_spawn_spacing, 17)
	assert_eq(config.min_spawn_landmass, 44)


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


func test_no_script_seeds_its_own_spawn_sampler() -> void:
	var scripts: Array = []
	_all_scripts("res://", scripts)
	assert_gt(scripts.size(), 10, "Found almost no scripts — the walk is broken, not the code clean")

	# Anything assigning `spawn_seed` is deciding for itself where players
	# start. Only the two files that OWN that decision may.
	var seeding := RegEx.new()
	seeding.compile("\\bspawn_seed\\s*=")

	var offences: Array = []
	for script_path in scripts:
		var path_str := String(script_path)
		if path_str in EXEMPT_FILES:
			continue
		var exempt := false
		for prefix in EXEMPT_PREFIXES:
			if path_str.begins_with(prefix):
				exempt = true
				break
		if exempt:
			continue

		var handle := FileAccess.open(path_str, FileAccess.READ)
		if handle == null:
			continue
		var text := handle.get_as_text()
		handle.close()

		if seeding.search(text) != null:
			offences.append("%s seeds a spawn sampler of its own — call MapSettings.to_spawn_config()" % path_str)

	assert_eq(offences, [],
		"Only MapSettings may decide what the spawn sampler is fed (D-104)")

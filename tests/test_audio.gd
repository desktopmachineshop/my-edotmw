extends GutTest

## Guards the audio foundations (#344).
##
## Everything here runs headless with no audio device, which is the
## point: `audio_cue.gd` is the decision layer and `audio_director.gd` is
## the only part that needs hardware — the same split `render_cull.gd`
## makes against `client.gd`, and for the same reason. The half with the
## interesting failure mode is the GATING, and a gate that needs a
## speaker to test is a gate nobody tests.
##
## The rules being guarded:
##
## - **D-006 clause 2** — audio is a one-way client cosmetic. The
##   simulation must not learn that sound exists.
## - **#344 / D-004 / D-106** — a sound whose cause a player could not
##   SEE must not play, and the check must reuse the ONE vision query
##   rather than inventing a second.
## - **D-024** — a volley is one sound, not thirty-six. Combat resolves
##   as aggregate arithmetic over a whole squad, so one exchange can burst
##   many casualty events in a single tick.
## - **D-047's spirit / D-046 criterion 3** — audio is data; no script
##   names a sound file.

const WIDTH := 32
const HEIGHT := 16

const AUDIO_MANIFEST := "res://generated/audio/manifest.json"
const GENERATOR := "res://audio/sfx.py"


func _space() -> TorusSpace:
	return TorusSpace.new(WIDTH, HEIGHT, 1.0)


func _def(event: StringName, fog_gated := true, audible := 20,
		interval := 0.0, voices := 8) -> SoundDef:
	var d := SoundDef.new()
	d.event = event
	d.stream_path = "res://generated/audio/%s.wav" % event
	d.gain_db = 0.0
	d.audible_cells = audible
	d.min_interval = interval
	d.max_voices = voices
	d.fog_gated = fog_gated
	return d


func _at(space: TorusSpace, q: int, r: int) -> int:
	return space.index(Vector2i(q, r))


# --- fog: the rule the issue leads with --------------------------------

func test_a_sound_you_cannot_see_the_cause_of_does_not_play() -> void:
	# THE gate. #344: "a sound a player could not SEE the cause of must
	# not play". Anything else is an audible maphack — the ear version of
	# the defect #96 and #120 are both about.
	var space := _space()
	var cue := AudioCue.resolve(_def(&"combat_volley"), _at(space, 8, 8),
		_at(space, 9, 8), space, TerrainFog.UNEXPLORED, 0.0, {})
	assert_true(cue.is_empty(), "unexplored ground makes no sound")


func test_remembering_ground_is_not_hearing_it() -> void:
	# EXPLORED is not enough, and this is the interesting half. A player
	# who once saw a hill does not hear the battle happening on it now —
	# the same distinction D-030 draws for buildings, where seeing once is
	# KNOWLEDGE and not sight.
	var space := _space()
	var cue := AudioCue.resolve(_def(&"combat_volley"), _at(space, 8, 8),
		_at(space, 9, 8), space, TerrainFog.EXPLORED, 0.0, {})
	assert_true(cue.is_empty(),
		"explored-but-not-visible ground must be silent, or fog leaks through the ears")


func test_what_you_can_see_you_can_hear() -> void:
	var space := _space()
	var cue := AudioCue.resolve(_def(&"combat_volley"), _at(space, 8, 8),
		_at(space, 9, 8), space, TerrainFog.VISIBLE, 0.0, {})
	assert_false(cue.is_empty(), "visible ground must be audible, or nothing ever plays")
	assert_eq(String(cue["event"]), "combat_volley")


func test_a_world_sound_with_no_place_fails_closed() -> void:
	# A fog-gated cue that cannot say WHERE it happened cannot be checked,
	# and the safe direction is silence: the alternative leaks that
	# something happened somewhere, which is exactly what fog withholds.
	var space := _space()
	var cue := AudioCue.resolve(_def(&"combat_volley"), -1, _at(space, 9, 8),
		space, TerrainFog.VISIBLE, 0.0, {})
	assert_true(cue.is_empty(), "no cell means no fog check means no sound")


func test_interface_sounds_are_exempt_by_data_not_by_a_branch() -> void:
	# A click has no cause on the map. Gating it on sight would silence
	# the one category of sound that is unambiguously the player's own —
	# and the exemption is a FIELD, so a civ or a later pass can move a
	# cue between the two categories without touching code.
	var space := _space()
	var cue := AudioCue.resolve(_def(&"ui_click", false, 0), -1, -1,
		space, TerrainFog.UNEXPLORED, 0.0, {})
	assert_false(cue.is_empty(), "a UI click must play under full fog")


# --- distance ----------------------------------------------------------

func test_distance_is_measured_across_the_seam() -> void:
	# D-008's tax, paid here too: a battle just across the seam is as
	# loud as one the same distance on the same side. Two candidates at
	# equal toroidal distance and very different naive distance, so the
	# check cannot pass with the torus torn out.
	var space := _space()
	var near_wrapped := _at(space, 1, 8)      # 3 cells from q=30 the short way
	var listener := _at(space, 30, 8)
	var same_distance := _at(space, 27, 8)    # 3 cells the direct way
	var a := AudioCue.resolve(_def(&"combat_volley"), near_wrapped, listener,
		space, TerrainFog.VISIBLE, 0.0, {})
	var b := AudioCue.resolve(_def(&"combat_volley"), same_distance, listener,
		space, TerrainFog.VISIBLE, 0.0, {})
	assert_false(a.is_empty(), "a sound across the seam is still audible")
	assert_eq(int(a["distance"]), int(b["distance"]),
		"the seam must not make a near sound far")
	assert_almost_eq(float(a["volume_db"]), float(b["volume_db"]), 0.001,
		"and must not make it quieter")


func test_too_far_is_silence_rather_than_a_whisper() -> void:
	# A voice spent on something inaudible is a voice not spent on
	# something the player can hear.
	var space := _space()
	var cue := AudioCue.resolve(_def(&"combat_volley", true, 3),
		_at(space, 8, 8), _at(space, 8, 0), space, TerrainFog.VISIBLE, 0.0, {})
	assert_true(cue.is_empty(), "past audible_cells is silence")


func test_further_is_quieter() -> void:
	var space := _space()
	var listener := _at(space, 8, 8)
	var near := AudioCue.resolve(_def(&"combat_volley"), _at(space, 9, 8),
		listener, space, TerrainFog.VISIBLE, 0.0, {})
	var far := AudioCue.resolve(_def(&"combat_volley"), _at(space, 16, 8),
		listener, space, TerrainFog.VISIBLE, 0.0, {})
	assert_false(near.is_empty() or far.is_empty(), "setup: both audible")
	assert_lt(float(far["volume_db"]), float(near["volume_db"]),
		"the far one must be quieter")


# --- a volley is ONE sound (D-024) -------------------------------------

func test_a_burst_of_casualties_is_one_sound_not_thirty_six() -> void:
	# THE squad-level rule. Combat resolves as aggregate arithmetic over a
	# whole squad, so one exchange can produce a burst of events inside a
	# single tick. Unthrottled that is a click, not a clash — and it is
	# thirty-six voices spent on one event.
	var space := _space()
	var def := _def(&"combat_volley", true, 40, 0.10)
	var heard := {}
	var played := 0
	for _i in range(36):
		var cue := AudioCue.resolve(def, _at(space, 8, 8), _at(space, 9, 8),
			space, TerrainFog.VISIBLE, 0.0, heard)
		if not cue.is_empty():
			played += 1
			heard = AudioCue.note_played(heard, def.event, 0.0)
	assert_eq(played, 1, "thirty-six casualties in one tick are one volley")


func test_the_throttle_lets_go_once_the_interval_has_passed() -> void:
	# The other half: a throttle that never releases is silence with
	# extra steps.
	var space := _space()
	var def := _def(&"combat_volley", true, 40, 0.10)
	var heard := AudioCue.note_played({}, def.event, 0.0)
	var too_soon := AudioCue.resolve(def, _at(space, 8, 8), _at(space, 9, 8),
		space, TerrainFog.VISIBLE, 0.05, heard)
	var later := AudioCue.resolve(def, _at(space, 8, 8), _at(space, 9, 8),
		space, TerrainFog.VISIBLE, 0.5, heard)
	assert_true(too_soon.is_empty(), "inside the interval, silence")
	assert_false(later.is_empty(), "past it, the cue plays again")


func test_voices_are_capped_independently_of_rate() -> void:
	# A different limit from the interval and needed separately: twenty
	# simultaneous engagements across a map are not thirty-six casualties
	# in one tick. Interval is 0 here, so ONLY the voice cap can refuse.
	var space := _space()
	var def := _def(&"combat_volley", true, 40, 0.0, 3)
	var heard := {}
	var played := 0
	for i in range(10):
		var cue := AudioCue.resolve(def, _at(space, 8, 8), _at(space, 9, 8),
			space, TerrainFog.VISIBLE, float(i), heard)
		if not cue.is_empty():
			played += 1
			heard = AudioCue.note_played(heard, def.event, float(i))
	assert_eq(played, 3, "the voice cap holds when the interval does not")

	heard = AudioCue.note_finished(heard, def.event)
	assert_false(AudioCue.resolve(def, _at(space, 8, 8), _at(space, 9, 8),
		space, TerrainFog.VISIBLE, 99.0, heard).is_empty(),
		"a finished voice frees a slot")


func test_a_bigger_volley_is_louder() -> void:
	var space := _space()
	var def := _def(&"combat_volley")
	var small := AudioCue.resolve(def, _at(space, 8, 8), _at(space, 9, 8),
		space, TerrainFog.VISIBLE, 0.0, {}, AudioCue.volley_magnitude(2, 30))
	var big := AudioCue.resolve(def, _at(space, 8, 8), _at(space, 9, 8),
		space, TerrainFog.VISIBLE, 0.0, {}, AudioCue.volley_magnitude(25, 30))
	assert_lt(float(small["volume_db"]), float(big["volume_db"]),
		"losing twenty-five men must sound worse than losing two")


func test_volley_magnitude_is_a_count_not_a_soldier() -> void:
	# Squad-level by construction: the input is a COUNT and there is
	# nowhere in it for per-soldier state to live (D-006 clause 1).
	assert_eq(AudioCue.volley_magnitude(0, 30), 0.0, "nobody fell, nothing to hear")
	assert_eq(AudioCue.volley_magnitude(30, 30), 1.0, "a wipe is full weight")
	assert_between(AudioCue.volley_magnitude(15, 30), 0.0, 1.0, "and it stays bounded")
	assert_eq(AudioCue.volley_magnitude(5, 0), 0.0, "an empty squad cannot lose men")


# --- purity, and the one-way rule --------------------------------------

func test_the_resolver_is_pure() -> void:
	# Same inputs, same answer, and NO instance state — which is what
	# makes every test above meaningful and what keeps D-006 clause 2
	# structural rather than remembered.
	var space := _space()
	var def := _def(&"combat_volley")
	var heard := {}
	var a := AudioCue.resolve(def, _at(space, 8, 8), _at(space, 9, 8),
		space, TerrainFog.VISIBLE, 0.0, heard)
	var b := AudioCue.resolve(def, _at(space, 8, 8), _at(space, 9, 8),
		space, TerrainFog.VISIBLE, 0.0, heard)
	assert_eq(a, b, "a pure resolver cannot answer differently the second time")
	assert_true(heard.is_empty(),
		"resolve() must not record anything — note_played() is the writer, "
		+ "so the same call can be made twice with the same answer")

	var script: GDScript = load("res://audio_cue.gd")
	for method in script.get_script_method_list():
		assert_true(method["flags"] & METHOD_FLAG_STATIC != 0,
			"AudioCue.%s must be static" % method["name"])
	for property in script.get_script_property_list():
		assert_eq(int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE, 0,
			"AudioCue.%s is instance state" % property["name"])


func test_the_simulation_does_not_know_sound_exists() -> void:
	# D-006 clause 2, as a scan. Audio is a client cosmetic and one-way;
	# a simulation file that mentioned it would be a per-client divergence
	# with no wire evidence — the worst shape of bug this project names.
	var sim_files := ["res://squad_sim.gd", "res://combat.gd", "res://economy.gd",
		"res://building_sim.gd", "res://vision.gd", "res://server.gd",
		"res://formation.gd", "res://match_state.gd"]
	for path in sim_files:
		var handle := FileAccess.open(path, FileAccess.READ)
		assert_not_null(handle, "%s must be readable" % path)
		if handle == null:
			continue
		var text := handle.get_as_text()
		handle.close()
		for token in ["AudioCue", "SoundRoster", "AudioStreamPlayer", "AudioServer"]:
			assert_false(text.contains(token),
				"%s names %s — the simulation must not know sound exists (D-006)"
					% [path, token])


# --- the table is DATA (D-047's spirit) --------------------------------

func test_no_script_names_a_sound_file() -> void:
	# D-046 criterion 3's rule, applied to audio: adding or changing a
	# sound is editing `/audio/*.tres`, never a `.gd`. The generator is
	# exempt — it is what WRITES the files, and it is Python.
	var dir := DirAccess.open("res://")
	assert_not_null(dir, "the project root must be readable")
	if dir == null:
		return
	var offenders := []
	for file in dir.get_files():
		if not String(file).ends_with(".gd"):
			continue
		var handle := FileAccess.open("res://" + String(file), FileAccess.READ)
		if handle == null:
			continue
		var text := handle.get_as_text()
		handle.close()
		# CODE lines only. A doc comment that DESCRIBES this rule
		# ("a test fails if any .gd names a .wav") is prose, not a
		# reference, and counting it makes the guard fire on the file
		# that documents it — which is how a scan gets muted. Same
		# correction `test_starting_positions.gd` needed when its own
		# count included comments.
		for raw in text.split("
"):
			var line := String(raw).strip_edges()
			if line.begins_with("#"):
				continue
			if line.contains(".wav") or line.contains("generated/audio/"):
				offenders.append(String(file))
				break
	assert_eq(offenders.size(), 0,
		"these name a sound file directly; the table is /audio/*.tres: %s" % str(offenders))


func test_the_shipped_table_loads_and_makes_sense() -> void:
	var events := SoundRoster.events()
	assert_gt(events.size(), 0, "the shipped table must answer something")
	for event in events:
		var def := SoundRoster.by_event(event)
		assert_not_null(def, "%s must resolve" % event)
		assert_ne(def.stream_path, "", "%s must name a stream" % event)
		assert_true(FileAccess.file_exists(def.stream_path),
			"%s points at %s, which does not exist — run `just build-audio`"
				% [event, def.stream_path])
		assert_gt(def.max_voices, 0, "%s must allow at least one voice" % event)
		assert_gte(def.min_interval, 0.0, "%s cannot have a negative interval" % event)


func test_an_unknown_event_is_silence_not_a_crash() -> void:
	assert_null(SoundRoster.by_event(&"no_such_event_at_all"),
		"an event with no cue is silence, which is what an incomplete table sounds like")
	assert_true(AudioCue.resolve(null, 0, 0, _space(), TerrainFog.VISIBLE, 0.0, {}).is_empty(),
		"and a null def resolves to silence rather than crashing")


func test_the_table_and_the_generator_have_not_drifted() -> void:
	# `audio/sfx.py` writes `generated/audio/<event>.wav` and
	# `/audio/<event>.tres` names the same event, so the two are a matched
	# pair by construction — and a pair that nothing compares is a pair
	# that drifts. A cue added to one and not the other is silence with a
	# resource behind it, or a file nothing can ever play.
	var generated := {}
	var dir := DirAccess.open("res://generated/audio")
	assert_not_null(dir, "generated/audio must exist — run `just build-audio`")
	if dir == null:
		return
	for file in dir.get_files():
		var name := String(file)
		if name.ends_with(".import") or name.ends_with(".remap"):
			continue
		if name.ends_with(".wav"):
			generated[name.substr(0, name.length() - 4)] = true

	var tabled := {}
	for event in SoundRoster.events():
		tabled[String(event)] = true

	var unplayable := []
	for name in generated:
		if not tabled.has(name):
			unplayable.append(name)
	var missing := []
	for name in tabled:
		if not generated.has(name):
			missing.append(name)

	assert_eq(missing.size(), 0,
		"these events name a stream the generator does not write: %s" % str(missing))
	assert_eq(unplayable.size(), 0,
		"these cues are generated and nothing can ever play them: %s" % str(unplayable))


func test_the_generated_audio_matches_the_generator_that_wrote_it() -> void:
	# D-081's staleness rule, audio's own half.
	#
	# The generator lives in `audio/`, NOT under `art/`, and that is not
	# tidiness. `art/build.py` hashes every `.py` under `art/` into the
	# model manifest, so a generator there made a sound edit mark every
	# MODEL stale — and adding it to build.py's exclusion list broke the
	# same test a second way, because build.py is itself hashed. Both reds
	# are clearable only by `just build-assets`, which needs a bpy wheel
	# that is blocked host-wide.
	#
	# Separate pipeline, separate manifest — and this is its guard.
	# Without it, editing the generator and forgetting to rebuild ships
	# yesterday's sounds with everything green, which is exactly what the
	# model hash exists to stop.
	if not FileAccess.file_exists(AUDIO_MANIFEST):
		pass_test("generated/audio not built; silence is the designed degradation (D-064)")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(AUDIO_MANIFEST))
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "the audio manifest must be an object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var manifest: Dictionary = parsed

	var source := FileAccess.get_file_as_bytes(GENERATOR)
	assert_gt(source.size(), 0, "the generator must be readable to hash")
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(source)
	var expected := context.finish().hex_encode()

	assert_eq(String(manifest.get("source_hash", "")), expected,
		"generated/audio is stale: it was built from a different "
		+ "audio/sfx.py than the one in this tree. Run `just build-audio`.")

	# And the manifest must describe the table, not drift beside it.
	var cues := []
	for name in manifest.get("cues", []):
		cues.append(String(name))
	cues.sort()
	var events := []
	for event in SoundRoster.events():
		events.append(String(event))
	events.sort()
	assert_eq(cues, events,
		"the generator writes %s while the table answers %s" % [str(cues), str(events)])

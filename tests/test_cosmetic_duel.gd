extends GutTest

## Guards D-20260818-rome-total-war-formations-in-three-tiers Tier 1 and
## D-006 clauses 1 and 2: cosmetic duels are pure, bounded, one-way and
## client-only.
##
## The boundary tests here are the load-bearing ones. A duel that leaked
## into simulation would not fail anything by itself — the same
## declared-and-read-by-the-wrong-side family as D-065 — so the scan
## asserts both directions: nothing simulation-side reads CosmeticDuel,
## and client.gd actually CALLS it (the D-055 "caller exists" rule —
## every other assertion in this file can pass while nothing draws a
## duel).

const EPS := 0.01


func _line(points: Array) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for p in points:
		out.append(Transform3D(Basis(), p))
	return out


func test_pairing_picks_the_nearest_opponent() -> void:
	var attackers := _line([Vector3(0, 0, 0), Vector3(4, 0, 0)])
	var defenders := _line([Vector3(0, 0, 2), Vector3(4, 0, 2), Vector3(20, 0, 2)])
	var paired := CosmeticDuel.opponents(attackers, defenders)
	assert_eq(paired[0], 0, "the man at x=0 duels the defender straight ahead")
	assert_eq(paired[1], 1, "the man at x=4 duels his own opposite number")


func test_pairing_is_deterministic() -> void:
	var attackers := _line([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])
	var defenders := _line([Vector3(0.5, 0, 3), Vector3(1.5, 0, 3)])
	var first := CosmeticDuel.opponents(attackers, defenders)
	var second := CosmeticDuel.opponents(attackers, defenders)
	assert_eq(first, second,
		"identical inputs must pair identically — a man keeps his opponent "
		+ "because the answer comes out the same, not because it was stored "
		+ "(D-006 clause 1's trick, and the Tier 2 collapse-trigger probe)")


func test_engage_faces_the_opponent() -> void:
	var attackers := _line([Vector3(0, 0, 0)])
	var defenders := _line([Vector3(3, 0, 4)])
	var out := CosmeticDuel.engage(attackers, defenders, PackedInt32Array([0]))
	# Formation-local forward is +z (Formation.soldier_transform), so the
	# man's chest points along basis * (0,0,1).
	var forward: Vector3 = out[0].basis * Vector3(0, 0, 1)
	var toward := (defenders[0].origin - out[0].origin).normalized()
	assert_almost_eq(forward.dot(toward), 1.0, EPS,
		"an engaged man faces the man he is fighting, not his march heading")


func test_engage_steps_into_contact_and_no_further() -> void:
	# BOTH sides run engage against the other's authoritative slots, so
	# each man closes half the excess and a mutually paired pair meets
	# exactly CONTACT_GAP apart. That is the contract — asserting one
	# side alone was how the first version of this file passed while two
	# whole squads stopped 2.5 apart, swinging at the air.
	var a := _line([Vector3(0, 0, 0)])
	var b := _line([Vector3(0, 0, 1.5)])
	var paired := PackedInt32Array([0])
	var engaged_a := CosmeticDuel.engage(a, b, paired)
	var engaged_b := CosmeticDuel.engage(b, a, paired)
	assert_almost_eq(
		engaged_a[0].origin.distance_to(engaged_b[0].origin),
		CosmeticDuel.CONTACT_GAP, EPS,
		"a mutually paired pair of men stands toe to toe, CONTACT_GAP apart")

	# Close enough that his half-share reaches contact, but only just —
	# 2.89 rather than the exact REACH boundary of 2.9, which float
	# arithmetic tips into the rear-lean branch. He takes very nearly his
	# full clamped step, because the duel may never scatter the squad's
	# true footprint.
	var pressing := CosmeticDuel.engage(
		_line([Vector3(0, 0, 0)]), _line([Vector3(0, 0, 2.89)]),
		PackedInt32Array([0]))
	assert_almost_eq(pressing[0].origin.distance_to(Vector3.ZERO),
		(2.89 - CosmeticDuel.CONTACT_GAP) / 2.0, EPS,
		"a man on the edge of the fight steps his full half-share")

	# Deep in the formation, in range but unable to REACH contact even
	# with both sides paying half: he leans in a short step and queues.
	# The first preview picture is why — his full step arrived inside
	# his own front rank and two squads read as one blob.
	var deep := CosmeticDuel.engage(
		_line([Vector3(0, 0, 0)]), _line([Vector3(0, 0, 4.0)]),
		PackedInt32Array([0]))
	assert_almost_eq(deep[0].origin.distance_to(Vector3.ZERO),
		CosmeticDuel.REAR_LEAN, EPS,
		"a rear-rank man queues behind the fight instead of piling into it")

	# Beyond ENGAGE_RANGE: he faces the enemy and does not move — the far
	# end of a long line walking sideways at nothing reads as the
	# formation dissolving.
	var far := CosmeticDuel.engage(
		_line([Vector3(0, 0, 0)]), _line([Vector3(0, 0, 10.0)]),
		PackedInt32Array([0]))
	assert_almost_eq(far[0].origin.distance_to(Vector3.ZERO), 0.0, EPS,
		"a man out of engage range holds formation exactly")
	var forward: Vector3 = far[0].basis * Vector3(0, 0, 1)
	assert_almost_eq(forward.dot(Vector3(0, 0, 1)), 1.0, EPS,
		"but he still braces toward the enemy")


func test_a_crowded_pair_steps_back_to_the_gap() -> void:
	var a := _line([Vector3(0, 0, 0)])
	var b := _line([Vector3(0, 0, 0.2)])
	var paired := PackedInt32Array([0])
	var engaged_a := CosmeticDuel.engage(a, b, paired)
	var engaged_b := CosmeticDuel.engage(b, a, paired)
	assert_almost_eq(
		engaged_a[0].origin.distance_to(engaged_b[0].origin),
		CosmeticDuel.CONTACT_GAP, EPS,
		"men fight toe to toe, not inside each other's models")


func test_engage_never_mutates_the_authoritative_input() -> void:
	var attackers := _line([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	var before: Array[Transform3D] = attackers.duplicate()
	CosmeticDuel.engage(attackers,
		_line([Vector3(0, 0, 2)]), PackedInt32Array([0, 0]))
	assert_eq(attackers, before,
		"the authoritative transforms are read, never written — the caller "
		+ "keeps the true value and renders the returned one (D-006 clause 2)")


func test_strike_decorate_leans_each_man_at_his_own_opponent() -> void:
	# Two men, opponents on opposite sides. Squad-level decoration leaned
	# everyone at ONE point; the duel must lean them apart.
	# Opponents WITHIN STRIKE_REACH: a man only swings at a mark he can
	# actually hit (the windmilling-at-air fix from the owner's siege
	# screenshot).
	var eased := _line([Vector3(0, 0, 0), Vector3(2, 0, 0)])
	var defenders := _line([Vector3(-1.4, 0, 0), Vector3(3.4, 0, 0)])
	# A time at which slot 0's swing is near its peak and positive.
	var time := 1.5 / 5.5
	var out := CosmeticDuel.strike_decorate(
		eased, defenders, PackedInt32Array([0, 1]), time, 0.0)
	var plain0 := CosmeticOffset.decorate(eased[0], 0, time, 0.0)
	var lean0 := out[0].origin - plain0.origin
	assert_true(lean0.x < -EPS,
		"the man whose opponent is to his -x leans -x, not at a squad point")


func test_the_duel_is_all_static() -> void:
	# The structural half of purity, the same way Formation and
	# AnimationState keep it: nowhere to put per-soldier state.
	var handle := FileAccess.open("res://cosmetic_duel.gd", FileAccess.READ)
	assert_not_null(handle, "cosmetic_duel.gd must exist")
	var text := handle.get_as_text()
	handle.close()
	for line in text.split("\n"):
		assert_false(line.begins_with("var "),
			"CosmeticDuel may hold no instance state — a remembered opponent "
			+ "is the Tier 2 collapse trigger, and the decision says stop and "
			+ "re-decide, not cache: '%s'" % line)


func test_the_simulation_never_reads_a_duel_and_the_client_draws_one() -> void:
	var scripts: Array = []
	_all_scripts("res://", scripts)
	var readers: Array = []
	for script_path in scripts:
		var path_str := String(script_path)
		if path_str == "res://cosmetic_duel.gd" or path_str.begins_with("res://tests/"):
			continue
		var handle := FileAccess.open(path_str, FileAccess.READ)
		if handle == null:
			continue
		var text := handle.get_as_text()
		handle.close()
		if text.contains("CosmeticDuel"):
			readers.append(path_str)

	assert_true(readers.has("res://squad_render.gd"),
		"the render pipeline must actually run the duel — every other test "
		+ "here can pass while nothing on screen fights (the D-055 "
		+ "caller-exists rule). The call moved out of client.gd into "
		+ "squad_render.gd when the benchmark had to run it too (#240); "
		+ "what the rule cares about is that SOMETHING on the render path "
		+ "calls it.")
	for reader in readers:
		assert_true(String(reader) == "res://client.gd"
			or String(reader) == "res://squad_render.gd"
			or String(reader) == "res://bench_render.gd"
			or String(reader) == "res://duel_preview.gd",
			("only the render path, the benchmark that measures it and its "
			+ "preview may read CosmeticDuel — %s reading it means a "
			+ "cosmetic value is one call from an outcome, which is D-006's "
			+ "revisit trigger firing") % reader)


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

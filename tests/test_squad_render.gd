extends GutTest

## Guards `squad_render.gd` — the per-squad render pipeline (#240).
##
## Everything here used to live inside `client.gd`'s `_refresh_squads`,
## which is the file this project has spent two milestones calling
## untestable. That claim was always too wide (D-075's 2026-08-16
## amendment made the same correction about node lifetime), and this is
## the rest of it: the duel pass, the static-target deal, the building and
## tree push-outs, the easing and the decoration are pure over their
## inputs, so they need no GPU, no camera and no scene tree — only
## somebody willing to hand them their inputs.
##
## The reason it is worth testing at all is #240: `bench_render.gd` did
## not run ANY of this while claiming to do "exactly what client.gd's
## `_refresh_squads` does". One definition now, called by both, and the
## behaviour of that definition is pinned here.

const SLOT := 1.2


func _line(count: int, at: Vector3, facing := 0.0) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in range(count):
		var local := Vector3((float(i) - float(count - 1) * 0.5) * SLOT, 0.0, 0.0)
		out.append(Transform3D(Basis(Vector3.UP, facing),
			at + local.rotated(Vector3.UP, facing)))
	return out


func _fighting(enemy_squad := 7) -> Dictionary:
	return {
		"activity": CosmeticOffset.Activity.FIGHTING, "toward": Vector3.ZERO,
		"working": AnimationState.NOT_WORKING,
		"swing": CosmeticOffset.SWING_AMPLITUDE,
		"is_ranged": false, "interval": 1.0, "enemy_squad": enemy_squad,
	}


func _idle() -> Dictionary:
	return {
		"activity": CosmeticOffset.Activity.IDLE, "toward": Vector3.ZERO,
		"working": AnimationState.NOT_WORKING,
		"swing": CosmeticOffset.SWING_AMPLITUDE,
		"is_ranged": false, "interval": 0.0, "enemy_squad": -1,
	}


func _working(node_at: Vector3) -> Dictionary:
	return {
		"activity": CosmeticOffset.Activity.WORKING, "toward": node_at,
		"working": 0, "swing": CosmeticOffset.SWING_AMPLITUDE,
		"is_ranged": false, "interval": 0.0, "enemy_squad": -1,
		"ring_centre": node_at, "ring_radius": 0.9, "target_key": "n:42",
	}


# --- the duel pass ------------------------------------------------------

func test_a_melee_steps_men_toward_their_opponents() -> void:
	var mine := _line(8, Vector3(0.0, 0.0, 0.0))
	var theirs := _line(8, Vector3(0.0, 0.0, 3.0), PI)
	var before := []
	for man in mine:
		before.append(man.origin)

	var out := SquadRender.frame({
		"transforms": mine.duplicate(), "doing": _fighting(),
		"enemy_transforms": theirs, "now": 0.0, "speed": 0.0,
	})
	assert_true(bool(out["dueling"]), "a melee with drawn opponents duels")
	var men: Array[Transform3D] = out["transforms"]
	assert_eq(men.size(), 8)

	var closed := 0
	for i in range(men.size()):
		var was := (before[i] as Vector3).distance_to(theirs[i].origin)
		var now := men[i].origin.distance_to(theirs[i].origin)
		if now < was:
			closed += 1
	assert_gt(closed, 4, "most men close on their opponent")


func test_no_man_leaves_his_slot_by_more_than_the_step() -> void:
	# The duel can never scatter a formation — Tier 1's binding
	# constraint. Asserted through the whole pipeline rather than of
	# `CosmeticDuel.engage` alone, because easing and decoration run after
	# it and this is the composition a player sees.
	var mine := _line(10, Vector3.ZERO)
	var theirs := _line(10, Vector3(0.0, 0.0, 2.5), PI)
	var out := SquadRender.frame({
		"transforms": mine.duplicate(), "doing": _fighting(),
		"enemy_transforms": theirs, "now": 0.4, "speed": 0.0,
	})
	var men: Array[Transform3D] = out["transforms"]
	for i in range(men.size()):
		var drift := men[i].origin.distance_to(mine[i].origin)
		assert_lt(drift, Engagement.MAX_STEP + CosmeticOffset.SWING_AMPLITUDE + 0.6,
			"man %d stays near his slot (%.2f)" % [i, drift])


func test_the_authoritative_transforms_are_never_mutated() -> void:
	# D-006 clause 2's one-way rule, structurally: the simulation's own
	# array must come back untouched however much the render layer moves
	# the drawn men.
	var mine := _line(6, Vector3.ZERO)
	var copy := mine.duplicate()
	var theirs := _line(6, Vector3(0.0, 0.0, 2.0), PI)
	SquadRender.frame({
		"transforms": mine, "doing": _fighting(),
		"enemy_transforms": theirs, "now": 1.0, "speed": 0.0,
	})
	for i in range(mine.size()):
		assert_eq(mine[i].origin, copy[i].origin,
			"slot %d was not written back" % i)


# --- the static-target deal --------------------------------------------

func test_a_working_crew_wraps_its_node_and_the_deal_holds() -> void:
	var node_at := Vector3(4.0, 0.0, 4.0)
	var crew := _line(7, node_at + Vector3(0.0, 0.0, -2.0))
	var first := SquadRender.frame({
		"transforms": crew.duplicate(), "doing": _working(node_at),
		"now": 0.0, "speed": 0.0,
	})
	assert_true(bool(first["dueling"]), "a static target runs the duel pipeline")
	var deal: Dictionary = first["deal"]
	assert_true(deal.has("paired"), "and produces a deal to cache")
	assert_eq((deal["paired"] as PackedInt32Array).size(), 7,
		"one mark per man")

	# Handed back its own deal with the target and the strength unchanged,
	# it must reuse it rather than re-dealing — the fix for men hopping
	# along the wall as their slots drift (D-20260821).
	var again := SquadRender.frame({
		"transforms": crew.duplicate(), "doing": _working(node_at),
		"deal": deal, "now": 0.1, "speed": 0.0,
	})
	assert_eq((again["deal"]["paired"] as PackedInt32Array),
		(deal["paired"] as PackedInt32Array), "the deal holds")

	# A casualty changes the strength, so the deal is re-cut.
	var fewer := SquadRender.frame({
		"transforms": _line(5, node_at + Vector3(0.0, 0.0, -2.0)),
		"doing": _working(node_at), "deal": deal, "now": 0.2, "speed": 0.0,
	})
	assert_eq((fewer["deal"]["paired"] as PackedInt32Array).size(), 5,
		"a restamped crew is dealt again")


# --- the obstacles ------------------------------------------------------

func test_a_drawn_man_is_pushed_out_of_a_building() -> void:
	var box := {"centre": Vector3(0.0, 0.0, 0.0),
		"half": Vector2(2.0, 2.0), "yaw": 0.0}
	var men := _line(5, Vector3.ZERO)          # straight through the box
	var out := SquadRender.frame({
		"transforms": men.duplicate(), "doing": _idle(),
		"boxes": [box], "now": 0.0, "speed": 0.0,
	})
	var drawn: Array[Transform3D] = out["transforms"]
	for i in range(drawn.size()):
		var p := drawn[i].origin
		var inside := absf(p.x - box["centre"].x) < (box["half"] as Vector2).x - 0.01 \
			and absf(p.z - box["centre"].z) < (box["half"] as Vector2).y - 0.01
		assert_false(inside, "man %d is outside the footprint" % i)


func test_a_drawn_man_is_pushed_out_of_a_tree() -> void:
	var disc := {"centre": Vector3(0.0, 0.0, 0.0), "radius": 0.85}
	var men := _line(5, Vector3.ZERO)
	var out := SquadRender.frame({
		"transforms": men.duplicate(), "doing": _idle(),
		"discs": [disc], "now": 0.0, "speed": 0.0,
	})
	var drawn: Array[Transform3D] = out["transforms"]
	for i in range(drawn.size()):
		var flat := Vector2(drawn[i].origin.x - 0.0, drawn[i].origin.z - 0.0)
		assert_gte(flat.length(), 0.85 - 0.01,
			"man %d stands outside the trunk" % i)


# --- easing and the clip -----------------------------------------------

func test_easing_walks_men_in_rather_than_snapping_them() -> void:
	# `SoldierMotion` is the one piece of per-soldier RENDER state D-006's
	# amended clause 2 permits, and the pipeline takes it from the caller
	# rather than owning one — so a benchmark and a client can each keep
	# their own without this file holding any.
	var motion := SoldierMotion.new()
	var here := _line(6, Vector3.ZERO)
	SquadRender.frame({
		"transforms": here.duplicate(), "doing": _idle(), "motion": motion,
		"squad_id": 3, "delta": 0.016, "now": 0.0, "speed": 0.0,
		"pursuit_speed": 2.0,
	})
	var moved := _line(6, Vector3(0.0, 0.0, 6.0))
	var out := SquadRender.frame({
		"transforms": moved.duplicate(), "doing": _idle(), "motion": motion,
		"squad_id": 3, "delta": 0.016, "now": 0.016, "speed": 0.0,
		"pursuit_speed": 2.0,
	})
	var drawn: Array[Transform3D] = out["transforms"]
	var travelled := drawn[0].origin.distance_to(here[0].origin)
	assert_lt(travelled, 6.0,
		"a man walks toward a jumped slot instead of teleporting to it")


func test_the_clip_follows_what_the_squad_is_doing() -> void:
	var men := _line(4, Vector3.ZERO)
	var fighting := SquadRender.frame({
		"transforms": men.duplicate(), "doing": _fighting(),
		"enemy_transforms": _line(4, Vector3(0.0, 0.0, 2.0), PI),
		"now": 0.0, "speed": 0.0,
	})
	var idle := SquadRender.frame({
		"transforms": men.duplicate(), "doing": _idle(), "now": 0.0, "speed": 0.0,
	})
	var walking := SquadRender.frame({
		"transforms": men.duplicate(), "doing": _idle(), "now": 0.0, "speed": 3.0,
	})
	var routed := SquadRender.frame({
		"transforms": men.duplicate(), "doing": _idle(), "now": 0.0,
		"speed": 3.0, "routed": true,
	})
	assert_ne(int(fighting["clip"]), int(idle["clip"]), "fighting is not idling")
	assert_ne(int(walking["clip"]), int(idle["clip"]), "walking is not idling")
	assert_ne(int(routed["clip"]), int(walking["clip"]), "a rout is not a march")


func test_drawn_men_are_the_eased_positions() -> void:
	# The client caches these for the next frame's cross-squad jostle, so
	# they have to be the positions men were actually EASED to — not the
	# decorated ones, which sway.
	var out := SquadRender.frame({
		"transforms": _line(5, Vector3.ZERO), "doing": _idle(),
		"now": 0.3, "speed": 1.0,
	})
	var eased: Array[Transform3D] = out["eased"]
	var drawn: PackedVector3Array = out["drawn_men"]
	assert_eq(drawn.size(), eased.size())
	for i in range(eased.size()):
		assert_eq(drawn[i], eased[i].origin, "man %d" % i)


func test_an_empty_squad_costs_nothing_and_returns_nothing() -> void:
	var out := SquadRender.frame({
		"transforms": [] as Array[Transform3D], "doing": _idle(), "now": 0.0,
	})
	assert_eq((out["transforms"] as Array[Transform3D]).size(), 0)
	assert_eq((out["drawn_men"] as PackedVector3Array).size(), 0)


# --- the reason this file exists ---------------------------------------

func test_the_client_and_the_benchmark_run_the_same_pipeline() -> void:
	# #240 itself. `bench_render.gd` claimed to do "exactly what
	# client.gd's `_refresh_squads` does" while running none of the RTW
	# render passes, so every frame time recorded since was a floor for a
	# client nobody was timing. A scan, because there is no other way to
	# assert that two files call the same function — the D-106
	# caller-exists test, which carries D-106's own caveat: it covers the
	# caller it names.
	for path in ["res://client.gd", "res://bench_render.gd"]:
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text, "", "%s is readable" % path)
		assert_true(text.contains("SquadRender.frame("),
			("%s must run the shared render pipeline — a benchmark that "
			+ "skips it measures a client that does not ship (#240)") % path)

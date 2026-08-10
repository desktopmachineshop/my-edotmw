extends GutTest

## Guards D-065 — animated soldiers — and specifically the property that makes
## animation legal under D-006 at all.
##
## D-006 clause 1 forbids per-soldier integration state, and its revisit trigger
## names a walk cycle's usual implementation directly. The escape is that phase
## is DERIVED rather than advanced. So what is asserted here is not that the
## animation looks right — `just gen-model-preview` is for that — but that
## nothing in it remembers anything, and that nothing it produces can reach the
## simulation.
##
## The interesting failure mode is a well-meaning later change: someone adds
## blending between clips, or a footfall that depends on the previous frame, and
## the game still runs. These tests are what should go red.


# --- purity: same inputs, same outputs, no history (D-006 clause 1) ------


func test_phase_offset_is_a_pure_function_of_squad_and_slot() -> void:
	var first := AnimationState.phase_offset(7, 3)
	# Interleave other calls: if anything were accumulating, the repeat would
	# drift rather than repeat.
	for i in range(50):
		AnimationState.phase_offset(i, i * 3)
	var again := AnimationState.phase_offset(7, 3)
	assert_eq(first, again,
		"phase_offset must not depend on what was asked before it — that is "
		+ "per-soldier history, which D-006 clause 1 forbids")


func test_phase_offsets_are_in_range_and_spread_across_a_squad() -> void:
	var buckets := {}
	for slot in range(40):
		var phase := AnimationState.phase_offset(11, slot)
		assert_between(phase, 0.0, 1.0, "phase must be a fraction of a cycle")
		buckets[int(phase * 8.0)] = true
	# Without spread every soldier is on the same foot and a squad reads as a
	# chorus line rather than a body of troops.
	assert_gt(buckets.size(), 4,
		"a squad's phase offsets should spread across the cycle, got %d of 8 "
			% buckets.size() + "eighths occupied")


func test_neighbouring_slots_do_not_share_a_phase() -> void:
	var collisions := 0
	for slot in range(39):
		if is_equal_approx(AnimationState.phase_offset(3, slot),
				AnimationState.phase_offset(3, slot + 1)):
			collisions += 1
	assert_eq(collisions, 0,
		"adjacent slots landing on the same phase would march in lockstep")


func test_rate_is_a_pure_function_of_clip_and_speed() -> void:
	assert_eq(AnimationState.rate_for(AnimationState.CLIP_WALK, 4.0),
		AnimationState.rate_for(AnimationState.CLIP_WALK, 4.0))
	assert_eq(AnimationState.rate_for(AnimationState.CLIP_IDLE, 0.0),
		AnimationState.rate_for(AnimationState.CLIP_IDLE, 99.0),
		"idle's cadence must not depend on how fast the squad is not moving")


# --- the animation actually tracks the squad ----------------------------


func test_walking_faster_plays_the_walk_cycle_faster() -> void:
	var slow := AnimationState.rate_for(AnimationState.CLIP_WALK, 2.0)
	var fast := AnimationState.rate_for(AnimationState.CLIP_WALK, 6.0)
	assert_gt(fast, slow,
		"footfalls are tied to ground speed; if they are not, soldiers skate")


func test_a_stationary_squad_still_animates_rather_than_freezing() -> void:
	assert_gt(AnimationState.rate_for(AnimationState.CLIP_WALK, 0.0), 0.0,
		"a very slow squad must not appear frozen mid-step")


# --- clip selection ordering (D-063 criterion 7) ------------------------


func test_routing_outranks_everything_else() -> void:
	assert_eq(AnimationState.clip_for(true, true, true), AnimationState.CLIP_ROUT,
		"a broken squad that still swings reads as a squad that is fine — "
		+ "D-019's rout has been invisible on screen since M2")


func test_fighting_outranks_moving() -> void:
	assert_eq(AnimationState.clip_for(false, true, true), AnimationState.CLIP_ATTACK)


func test_a_still_squad_that_is_doing_nothing_idles() -> void:
	assert_eq(AnimationState.clip_for(false, false, false), AnimationState.CLIP_IDLE)


func test_custom_data_packs_clip_phase_and_rate_in_that_order() -> void:
	var data := AnimationState.custom_data(5, 2, AnimationState.CLIP_WALK, 4.0)
	assert_eq(int(data.r), AnimationState.CLIP_WALK,
		"the shader reads the clip index from red")
	# Colour components are 32-bit; the sources are 64-bit. Compared
	# approximately for that reason, not out of vagueness about the value.
	assert_almost_eq(data.g, AnimationState.phase_offset(5, 2), 1e-6)
	assert_almost_eq(data.b, AnimationState.rate_for(AnimationState.CLIP_WALK, 4.0), 1e-6)


# --- one-way: nothing here reaches the simulation (D-006 clause 2) ------


## `AnimationState` is all-static so there is nowhere for state to live. This
## asserts the property structurally rather than trusting the file to stay that
## way, in the same spirit as the test that a squad renders as one MultiMesh.
func test_animation_state_has_nowhere_to_put_per_soldier_state() -> void:
	var instance := AnimationState.new()
	var properties := instance.get_property_list()
	var declared: Array[String] = []
	for property in properties:
		# Script-declared storage only; built-in Object properties are noise.
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			declared.append(String(property["name"]))
	assert_eq(declared, [],
		"AnimationState gained instance state (%s). That is where a phase "
			% ", ".join(declared)
		+ "accumulator would live, and it is exactly what D-006 clause 1 bans.")


## The composition hash is what client and server compare (D-025/D-045). If any
## animation input reached it, two clients drawing the same squad mid-stride at
## different phases would report a desync on a perfectly healthy system — the
## trap D-058 records for formation shape.
func test_no_animation_input_can_reach_the_composition_hash() -> void:
	var state := ClientState.new()
	state.space = TorusSpace.new(16, 8)
	state.composition[1] = {
		"def_id": "legion_militia", "alive": 10, "shape": "line",
		"spacing": 1.0, "owner": 0,
	}
	var before := state.composition_hash()

	# Everything animation reads or writes, changed.
	state.composition[1]["routed"] = true
	var after := state.composition_hash()
	assert_eq(before, after,
		"routing changed the composition hash. Routing drives the rout clip, "
		+ "so a client that had not yet heard about a rout would desync on a "
		+ "healthy system.")

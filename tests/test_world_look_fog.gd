extends GutTest

## Guards the playtest fix to WorldLook's depth fog (see world_look.gd's
## fog constants doc): fog_density used to be one number tuned only
## against the Standard map's ~31-unit max_camera_height. A Huge map's
## max_camera_height reaches D-045's 90-unit ceiling, and the same density
## at that height fogs out roughly two thirds of the view — reported from
## play as "the terrain is just grey". `fog_density_for` must scale the
## density down as the camera ceiling rises, not hand back one constant.


func test_the_default_height_reproduces_the_original_tuned_density() -> void:
	# The old FOG_DENSITY constant this replaces was 0.006, tuned by eye
	# against the Standard map. DEFAULT_CAMERA_MAX_HEIGHT is chosen to
	# reproduce that exact value, so every caller that never passes a
	# map-specific height (bench_render.gd, model_preview.gd) keeps
	# rendering exactly what it always has.
	var density := WorldLook.fog_density_for(WorldLook.DEFAULT_CAMERA_MAX_HEIGHT)
	assert_almost_eq(density, 0.006, 0.0001)


func test_a_taller_camera_ceiling_gets_a_thinner_fog() -> void:
	# The bug this guards: a flat density fogs out MORE of the view as the
	# camera is allowed higher, since the same density applies over a
	# longer forward reach. A map that lets the camera zoom out further
	# (Huge, at the 90-unit ceiling) must get a LOWER density, not the
	# same one, or the fog thickens instead of staying calibrated.
	var standard := WorldLook.fog_density_for(31.6)
	var huge := WorldLook.fog_density_for(90.0)
	assert_lt(huge, standard,
		"a taller camera ceiling must produce a thinner fog, not the same density")


func test_fog_opacity_at_the_horizon_stays_calibrated_across_map_sizes() -> void:
	# The actual promise: whatever the camera ceiling, the haze at THAT
	# ceiling's own forward reach lands back near TARGET_HORIZON_FOG —
	# proving the fix, not just that density changed in the right
	# direction. Same formula make_environment() uses to convert a height
	# into an opacity, inverted here to check the round trip.
	var heights: Array[float] = [8.0, 31.6, 47.5, 90.0]
	for camera_max_height in heights:
		var density: float = WorldLook.fog_density_for(camera_max_height)
		var forward_reach: float = WorldLook.FORWARD_REACH_FACTOR * camera_max_height
		var opacity: float = 1.0 - exp(-density * forward_reach)
		assert_almost_eq(opacity, WorldLook.TARGET_HORIZON_FOG, 0.001,
			"camera_max_height=%.1f should land near the target horizon fog" % camera_max_height)


func test_make_environment_actually_uses_the_passed_height() -> void:
	# The wiring bug this would have caught: fog_density_for existing but
	# never actually being called with the real per-map height (client.gd
	# forgetting to update it after computing _camera_max_height).
	var standard_env := WorldLook.make_environment(false, 31.6)
	var huge_env := WorldLook.make_environment(false, 90.0)
	assert_lt(huge_env.fog_density, standard_env.fog_density)

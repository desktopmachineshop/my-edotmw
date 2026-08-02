extends GutTest

## Guards D-045 — wrap-aware render culling and the cosmetic-only render
## LOD tier.
##
## The client itself cannot be tested headless (D-014), so what is proven
## here is the part with the interesting failure mode: which lattice copy
## of a squad the renderer should be looking at, and that drawing fewer
## soldiers never changes anything the simulation reads.

const W := 128
const H := 64


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


# --- wrap-aware offset selection (D-044 criterion 5) -------------------

func test_a_squad_across_the_seam_resolves_to_its_near_copy() -> void:
	# THE failure this exists to catch. The world tiles nine times
	# (D-035), so a squad just past the seam is on screen at a WRAPPED
	# position while its canonical coordinates are a whole map away.
	# Culling on canonical coordinates alone makes armies vanish as they
	# cross the seam.
	var space := _space()
	var offsets := space.lattice_offsets()

	# Camera looking at the far right edge; squad just past it, so its
	# canonical x is near zero.
	var camera_at := space.to_world(Vector2i(W - 2, H / 2))
	var squad_at := space.to_world(Vector2i(1, H / 2))

	var offset := RenderCull.nearest_offset(offsets, squad_at, camera_at)

	assert_ne(offset, Vector3.ZERO,
		"The squad was placed at its canonical position, a whole map from the camera")
	assert_lt((squad_at + offset).distance_to(camera_at), (squad_at).distance_to(camera_at),
		"The chosen copy is further from the camera than the canonical position")
	# Three cells apart across the seam, so the wrapped copy must be close.
	assert_lt((squad_at + offset).distance_to(camera_at), 10.0,
		"The wrapped copy should be a few cells from the camera, not a map away")


func test_a_squad_in_plain_sight_keeps_its_canonical_position() -> void:
	# The other side of the boundary: wrapping must not fire when it is
	# not needed, or every squad would be drawn at an offset.
	var space := _space()
	var camera_at := space.to_world(Vector2i(W / 2, H / 2))
	var squad_at := space.to_world(Vector2i(W / 2 + 3, H / 2))

	assert_eq(RenderCull.nearest_offset(space.lattice_offsets(), squad_at, camera_at),
		Vector3.ZERO,
		"A squad next to the camera should not be drawn at a wrapped copy")


func test_the_lattice_offsets_are_the_nine_tiling_copies() -> void:
	var offsets := _space().lattice_offsets()
	assert_eq(offsets.size(), 9, "The world tiles as a 3x3 lattice (D-035)")
	assert_eq(offsets[0], Vector3.ZERO,
		"The canonical copy must be first, so it wins ties against a wrapped one")

	var seen := {}
	for offset in offsets:
		assert_false(seen.has(offset), "Duplicate lattice offset %s" % offset)
		seen[offset] = true


func test_the_lattice_steps_match_the_worlds_own_geometry() -> void:
	# The steps are what tiling, camera wrap and culling all share
	# (criterion 6). If they drift from TorusSpace.to_world, terrain tiles
	# and squads land in different places and the seam tears.
	var space := _space()
	var steps := space.lattice_steps()

	# Stepping a full width in q must land exactly where the world wraps.
	var origin := space.to_world(Vector2i(0, 0))
	var one_short := space.to_world(Vector2i(W - 1, 0))
	var wrapped := one_short + (space.to_world(Vector2i(1, 0)) - origin)
	assert_almost_eq(wrapped.distance_to(origin + steps[0]), 0.0, 0.001,
		"A full lap in q does not equal the q lattice step")


# --- render LOD is cosmetic only (D-044 criterion 8) -------------------

func _curve(space: TorusSpace) -> StateCurve:
	var curve := StateCurve.new()
	curve.append_cell(0.0, Vector2i(10, 10), space)
	curve.append_cell(2.0, Vector2i(30, 20), space)
	return curve


func test_lod_draws_fewer_soldiers_without_shrinking_the_formation() -> void:
	# A thinned squad must keep its true FOOTPRINT. Drawing a distant
	# 40-man line as a compact 5-man one would misreport unit size, which
	# is tactical information a player reads off the screen.
	var space := _space()
	var curve := _curve(space)

	var full := Formation.soldier_transforms(curve, 1.0, 40, "line", 1.0, space)
	var thin := Formation.soldier_transforms_sampled(
		curve, 1.0, 40, "line", 1.0, space, Callable(), 5)

	assert_eq(full.size(), 40)
	assert_eq(thin.size(), 5, "LOD should have drawn five soldiers")

	var full_extent := _extent(full)
	var thin_extent := _extent(thin)
	assert_gt(thin_extent, full_extent * 0.6,
		"The thinned squad collapsed to %.1f from %.1f — it is drawn smaller, not sparser" % [
			thin_extent, full_extent])


func test_every_lod_soldier_stands_where_a_full_detail_one_would() -> void:
	# LOD selects a SUBSET of the real slots; it does not invent new
	# positions. So each drawn soldier must coincide exactly with one from
	# the full-detail derivation.
	var space := _space()
	var curve := _curve(space)
	var full := Formation.soldier_transforms(curve, 0.7, 40, "line", 1.0, space)
	var thin := Formation.soldier_transforms_sampled(
		curve, 0.7, 40, "line", 1.0, space, Callable(), 8)

	for t in thin:
		var matched := false
		for f in full:
			if f.origin.distance_to(t.origin) < 0.0001:
				matched = true
				break
		assert_true(matched, "A LOD soldier stands at %s, where no real slot is" % t.origin)


func test_full_detail_is_bit_identical_to_the_unsampled_path() -> void:
	# The LOD parameter must be inert at full detail, or every existing
	# client/server agreement guarantee is renegotiated by a rendering
	# change.
	var space := _space()
	var curve := _curve(space)
	for alive in [1, 7, 12, 40]:
		var plain := Formation.soldier_transforms(curve, 1.3, alive, "line", 1.0, space)
		var sampled := Formation.soldier_transforms_sampled(
			curve, 1.3, alive, "line", 1.0, space, Callable(), alive)
		assert_eq(sampled, plain, "Sampling at full detail changed the answer for %d alive" % alive)


func test_lod_never_changes_what_the_simulation_reads() -> void:
	# D-006 clause 2's one-way boundary, and D-012's reason render LOD may
	# be camera-keyed at all: it cannot affect an outcome. Deriving at
	# reduced detail must leave `alive` and the composition hash untouched.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var id := sim.add_squad(UnitRoster.first(), 1, Vector2i(4, 4))
	sim.order_move(id, Vector2i(20, 12))
	for _i in range(5):
		sim.tick()

	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, sim.visible_to(1)))
	state.handle_packet(NetProtocol.encode_squad_info(sim.squad_info_entries(sim.visible_to(1))))
	for packet in sim.replicator.collect_for_client(1, sim.time, sim.visible_to(1)):
		state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))

	var before_alive := state.alive_of(id)
	var before_hash := state.composition_hash()

	var drawn := state.soldier_transforms_lod(id, sim.time, 3)
	assert_eq(drawn.size(), 3, "The renderer should have been given three soldiers")

	assert_eq(state.alive_of(id), before_alive,
		"Drawing fewer soldiers changed how many the client thinks are alive")
	assert_eq(state.composition_hash(), before_hash,
		"Drawing fewer soldiers changed the composition hash — this would desync a healthy client")


## Largest distance between any two soldiers, i.e. how much ground the
## formation covers.
func _extent(transforms: Array) -> float:
	var worst := 0.0
	for a in transforms:
		for b in transforms:
			worst = maxf(worst, (a as Transform3D).origin.distance_to((b as Transform3D).origin))
	return worst


# --- more than one copy on screen (the "half the screen is empty" bug) --

## A camera placed exactly as client.gd places it: above and behind the
## point it looks at, tilted down.
func _camera_looking_at(target: Vector3, height: float) -> Camera3D:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.position = target + Vector3(0.0, height, height * 0.6)
	camera.look_at(target, Vector3.UP)
	return camera


func test_the_zoom_cap_does_not_bound_the_z_direction() -> void:
	# The root cause, as pure geometry — no camera, no GPU.
	#
	# client.gd caps zoom from the map's WIDTH, on the stated assumption
	# that less than one full copy is ever on screen. A 128x64 torus is
	# `width * SQRT_3` = ~221 units wide but only `height * 1.5` = 96 deep,
	# so a cap derived from width says nothing about z. That is what let
	# more than one lattice copy be visible at once, which is exactly the
	# condition nearest_offset documents as unsafe.
	var space := _space()
	var x_period := float(W) * space.hex_size * TorusSpace.SQRT_3
	var z_period := float(H) * 1.5 * space.hex_size

	assert_lt(z_period, x_period,
		"this map is shallower than it is wide, which is the whole problem")

	# The cap client.gd computes, from width alone.
	var cap := x_period * 0.25
	assert_gt(cap * 2.0, z_period,
		"a width-derived zoom cap must be shown NOT to bound z — if this ever "
		+ "fails the map got deep enough that the old assumption held")




func test_visible_offset_still_culls_something_genuinely_off_screen() -> void:
	# The other side of the boundary. Testing all nine copies must not
	# become "never cull anything" — that would silently undo D-045 and
	# show up only as a frame-rate regression at scale.
	var space := _space()
	var offsets := space.lattice_offsets()
	var size := Vector2(1280.0, 720.0)

	var target := space.to_world(Vector2i(W / 2, H / 2))
	var camera := _camera_looking_at(target, 12.0)  # zoomed right in

	# Diagonally opposite on both axes, so no copy of it is near the view.
	var squad_at := space.to_world(Vector2i(0, 0))
	var visible = RenderCull.visible_offset(camera, offsets, squad_at, 0.0, size)

	assert_null(visible,
		"a squad on the far side of the map was reported visible — culling is doing nothing")


func test_the_zoom_cap_keeps_a_second_terrain_copy_off_screen() -> void:
	# THE bug behind "half the screen will not render units as visible".
	#
	# Terrain is drawn nine times (D-035) but every squad, building and
	# node is drawn ONCE, so as soon as the view spans a second terrain
	# copy that copy is bare ground — real terrain, no units on it.
	#
	# Measured on 128x64 at 1280x720: forward ground reach is ~1.9x camera
	# height and the camera sits 0.6h behind its target, so the on-screen
	# z span is ~2.6h. This asserts the cap client.gd computes keeps that
	# span inside the SHALLOWER lattice period. The old cap took a quarter
	# of the map's WIDTH and allowed 106 units of a 96-unit period.
	var space := _space()
	var x_period := float(W) * space.hex_size * TorusSpace.SQRT_3
	var z_period := float(H) * 1.5 * space.hex_size

	# The shipped function, not a copy of it — client.gd calls this too.
	var cap := RenderCull.max_camera_height(space, 8.0, 90.0)

	assert_lt(cap * 2.6, z_period,
		"at max zoom the view spans more than one lattice copy, so the second "
		+ "copy shows terrain with no units on it")

	# And the old formula must be shown to FAIL this, or the assertion
	# above is just describing whatever the code happens to do.
	var old_cap := x_period * 0.25
	assert_gt(old_cap * 2.6, z_period,
		"the width-derived cap should be demonstrably unsafe — if this fails, "
		+ "the map shape changed and this test is no longer testing anything")

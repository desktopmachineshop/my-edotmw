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

extends GutTest

## Guards D-045 — wrap-aware render culling and the cosmetic-only render
## LOD tier.
##
## The client itself cannot be tested headless (D-014), so what is proven
## here is the part with the interesting failure mode: which lattice copy
## of a squad the renderer should be looking at, and that drawing fewer
## soldiers never changes anything the simulation reads.
##
## Since #155 that includes WHEN a squad changes tier, which the client
## used to answer with a memoryless lookup and is the last section of this
## file. It moved into `render_cull.gd` for exactly the reason everything
## else here did: a frame-to-frame flip is arithmetic, and arithmetic can
## be tested without a GPU.

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


# --- the cap's actual promise: never the same ground twice --------------
#
# The old cap was `min(period) * 0.33`, from a ruler held against a
# 128x64 map at 1280x720. It modelled the on-screen Z span and nothing
# else, and z is not the binding axis: the frame is a truncated pyramid,
# so its widest ground line is the FAR edge, whose width comes from the
# HORIZONTAL half-angle (the vertical one times the aspect). Measured at
# 16:9 that is 5.90h against 2.65h for z, so the cap was out by more than
# a factor of two on the axis that mattered, and the shipped 84x96 map at
# the default height showed a 236-unit band against a 145.5-unit x
# period. Playtest report: forests appearing and disappearing while
# panning.


func test_the_far_edge_is_wider_than_the_view_is_deep() -> void:
	# The finding in one line. If this ever inverts, the rig's pitch or fov
	# changed enough that the binding axis moved, and `max_camera_height`
	# needs re-deriving rather than re-tuning.
	var k_x := RenderCull.span_x_per_height(16.0 / 9.0, 75.0)
	var k_z := RenderCull.span_z_per_height(75.0)

	assert_almost_eq(k_z, 2.65, 0.01,
		"the z span is the one number the old cap got right; it should not move")
	assert_almost_eq(k_x, 5.90, 0.01, "the far edge spans 5.9x the camera height")
	assert_gt(k_x, k_z * 2.0,
		"x is the binding axis by more than a factor of two — this is why a "
		+ "z-derived cap was not merely imprecise but wrong")


func test_a_wider_window_earns_a_lower_cap() -> void:
	# The aspect is a parameter, not a constant, because it genuinely
	# changes the answer — an ultrawide monitor fans the far edge out
	# further and must be allowed to zoom less. The old constant was
	# measured at one window size and applied to every window.
	var space := _shipped_space()
	var wide := RenderCull.max_camera_height(space, 12.0, 90.0, 21.0 / 9.0, 75.0)
	var normal := RenderCull.max_camera_height(space, 12.0, 90.0, 16.0 / 9.0, 75.0)

	assert_lt(wide, normal,
		"an ultrawide window sees more ground across and must cap zoom lower")


func test_the_zoom_cap_never_shows_the_same_ground_twice() -> void:
	# THE property the cap exists to guarantee, asserted by projection
	# rather than by arithmetic — so it cannot pass by agreeing with the
	# formula it is checking. At the cap, on every shipped map size, no
	# cell may be on screen at two lattice offsets at once.
	#
	# Sampled on a fixed ~50x50 grid rather than every cell, to stay inside
	# a unit test's budget on the largest map. Safe because duplication is
	# never a stray cell: it is a band across the whole far edge of the
	# frame, hundreds of cells wide.
	var camera := Camera3D.new()
	add_child_autofree(camera)
	var size := camera.get_viewport().get_visible_rect().size
	var aspect := size.x / size.y

	for entry in MapSettings.sizes():
		var space := TorusSpace.new(int(entry["width"]), int(entry["height"]), 1.0)
		var offsets := space.lattice_offsets()
		var cap := RenderCull.max_camera_height(space, 12.0, 90.0, aspect, camera.fov)
		var step := maxi(1, space.width / 50)

		var worst := 0
		for tq in [0, space.width / 3, 2 * space.width / 3]:
			for tr in [0, space.height / 3, 2 * space.height / 3]:
				var target := space.to_world(Vector2i(tq, tr))
				camera.position = target + Vector3(
					0.0, cap, cap * RenderCull.PITCH_RUN)
				camera.look_at(target, Vector3.UP)
				worst = maxi(worst, _most_copies_on_screen(
					camera, space, offsets, size, step))

		assert_eq(worst, 1,
			"%s (%dx%d) at its cap of %.1f shows some ground %d times — every copy "
			% [entry["name"], space.width, space.height, cap, worst]
			+ "past the first is real terrain with no units, buildings or trees on it")


## The largest number of lattice copies any sampled cell is on screen at.
## 1 is correct (you can see the world); 0 means the sampling missed the
## view entirely and the caller should treat that as a broken setup.
func _most_copies_on_screen(camera: Camera3D, space: TorusSpace,
		offsets: Array[Vector3], size: Vector2, step: int) -> int:
	var worst := 0
	for q in range(0, space.width, step):
		for r in range(0, space.height, step):
			var at := space.axial_offset_to_world(Vector2(float(q), float(r)))
			var seen := 0
			for off in offsets:
				if RenderCull.is_on_screen(camera, at + off, 0.0, size):
					seen += 1
			worst = maxi(worst, seen)
	return worst

func test_every_shipped_map_is_roughly_square_in_world_units() -> void:
	# A map that is much wider than it is deep forces the zoom cap down,
	# because the cap is bounded by the SHALLOWER lattice period — and
	# past that cap a second terrain copy enters view showing bare ground
	# with no units on it.
	#
	# Cells are not the measure: a hex column is SQRT_3 (~1.732) wide and
	# a row is 1.5 deep, so 128x64 cells is 2.31:1 on the ground, not 2:1.
	# Every shipped size was 2:1 in cells, so every one of them was oblong.
	var sizes := MapSettings.sizes()
	assert_gt(sizes.size(), 0, "no sizes to check")

	for entry in sizes:
		var w := int(entry["width"])
		var h := int(entry["height"])
		var x_period := float(w) * TorusSpace.SQRT_3
		var z_period := float(h) * 1.5
		var ratio := maxf(x_period, z_period) / minf(x_period, z_period)
		assert_lt(ratio, 1.15,
			"%s (%dx%d) is %.2f:1 on the ground — the shallow axis caps the zoom" % [
				entry["name"], w, h, ratio])
		assert_eq(h % 2, 0, "%s has an odd height, which D-008 forbids" % entry["name"])


func test_the_shipped_map_files_are_square_too() -> void:
	# The lobby sizes and the .tres files on disk are separate lists, and
	# a fix applied to one and not the other is exactly the drift this
	# project keeps getting caught by.
	for path in ["res://maps/default.tres", "res://maps/ladder.tres"]:
		var config := load(path) as MapConfig
		assert_not_null(config, "%s is missing" % path)
		var ratio := maxf(float(config.width) * TorusSpace.SQRT_3, float(config.height) * 1.5) \
			/ minf(float(config.width) * TorusSpace.SQRT_3, float(config.height) * 1.5)
		assert_lt(ratio, 1.15,
			"%s is %.2f:1 on the ground" % [path, ratio])


# --- culling a thing with real EXTENT ----------------------------------
#
# Playtest #62: whole blocks of forest snapped in and out of view on
# small camera moves, the terrain under them unchanged. Trees batch into
# one MultiMesh per (16-cell chunk, model) and the chunk was culled as a
# single POINT with a flat pixel margin — so a block ~48 world units
# across lived or died on where its middle projected — and on a miss it
# fell through to `nearest_offset`, which relocated it a whole map period
# instead of hiding it. Third instance of the same defect: squads got the
# radius-aware margin in an earlier playtest fix, and `_select_nearest`
# got it before that. This is the shared rule all of them go through now.

## Cells per side of a forest chunk (client.gd's NODE_CHUNK). Named here
## because client.gd needs a GPU and cannot be loaded (D-014).
const NODE_CHUNK := 16

## client.gd's CULL_MARGIN_PIXELS as a FRACTION of viewport width — 192
## of 1280. `unproject_position` answers in the viewport's OWN pixels and
## headless renders into a 64x64 one, so a literal 192 here would be three
## screens of slack and every one of these would pass vacuously.
const CULL_MARGIN_FRACTION := 192.0 / 1280.0


## The SHIPPED map, not this file's 128x64 constants. Those are the old
## oblong shape, whose z period is only four chunk-radii deep — close
## enough that a lattice copy sits near the horizon of any view, which is
## the condition `max_camera_height` and
## `test_every_shipped_map_is_roughly_square_in_world_units` exist to rule
## out. Culling with extent has to be judged on a map that obeys them.
func _shipped_space() -> TorusSpace:
	var config := load("res://maps/default.tres") as MapConfig
	return TorusSpace.new(config.width, config.height, config.hex_size)


## The viewport `unproject_position` is actually answering in. Passing
## anything else compares projected coordinates against a rectangle in a
## different space.
func _screen_size(camera: Camera3D) -> Vector2:
	return camera.get_viewport().get_visible_rect().size


func test_a_chunks_radius_accounts_for_the_row_shear() -> void:
	# 3 x half the chunk, not the half-diagonal of a rectangle: axial rows
	# shear half a column per row, so two of the four corners run with the
	# shear and reach much further than the naive answer.
	var space := _shipped_space()
	var radius := RenderCull.block_radius(space, NODE_CHUNK)

	assert_almost_eq(radius, 24.0, 0.001,
		"a 16-cell chunk at hex_size 1.0 reaches 24 world units from its centre")

	var naive := Vector2(float(NODE_CHUNK) / 2.0 * TorusSpace.SQRT_3,
		float(NODE_CHUNK) / 2.0 * 1.5).length()
	assert_gt(radius, naive * 1.2,
		"treating the chunk as an unsheared rectangle understates it, which is "
		+ "the direction that culls trees the player can still see")


func test_the_chunk_bound_covers_the_stand_not_just_the_cell_centres() -> void:
	# D-108: a node cell is a STAND of several trees on their own offsets
	# inside it, not one tree on the lattice point. So the outermost trees
	# of a chunk hang past the block of CELL CENTRES `block_radius`
	# measures, and the cull bound the client stores is that plus
	# `ResourceVisuals.MAX_OFFSET`.
	#
	# Small — 0.78 against 24 — and that is the point: without it the
	# outer row of every forest is culled a fraction early, which is a
	# quieter instance of the defect this whole section exists to fix, and
	# no counter anywhere would move.
	var space := _shipped_space()
	var centres := RenderCull.block_radius(space, NODE_CHUNK)
	var bound := centres + ResourceVisuals.MAX_OFFSET * space.hex_size

	# The worst case, built from the shipped geometry rather than asserted
	# as a number: the furthest corner cell of the block, with a tree
	# standing at the furthest offset ResourceVisuals allows, pointing
	# directly away from the chunk centre.
	var half := float(NODE_CHUNK) / 2.0
	var corner := space.axial_offset_to_world(Vector2(-half, -half))
	var tree := corner + corner.normalized() * ResourceVisuals.MAX_OFFSET * space.hex_size

	assert_gt(tree.length(), centres,
		"setup: a tree at the worst stand offset should reach past the block of "
		+ "cell centres — if it does not, MAX_OFFSET stopped meaning what this "
		+ "test assumes and the bound below is free")
	assert_almost_eq(bound, tree.length(), 0.001,
		"the chunk's cull bound does not reach its outermost tree, so the outer "
		+ "row of every forest is culled early")


func test_a_tree_never_leaves_the_cell_the_bound_was_derived_from() -> void:
	# The other side of it. The bound above is only correct while a tree
	# stays inside its own cell — if a stand could spill into a
	# neighbouring cell, one MAX_OFFSET of slack would stop covering it.
	# ResourceVisuals guarantees this for its own reasons (a tree must not
	# wander onto water or over a cliff); this records that the cull
	# depends on it too, so the two cannot drift apart silently.
	assert_lt(ResourceVisuals.MAX_OFFSET, TorusSpace.SQRT_3 / 2.0,
		"a tree can stand outside its own cell, so a chunk bound grown by one "
		+ "MAX_OFFSET no longer covers the stand")

func test_a_block_centre_stays_in_the_same_lattice_copy_as_its_cells() -> void:
	# THE bug this pair exists to catch, and it needs the DEFAULT map:
	# 84 is not a whole number of 16-cell blocks, so the last column owns
	# cells 80-83 while its nominal centre is 88 — off the map. `to_world`
	# normalizes, so that centre came back at q = 4, one whole x period
	# from the trees it stands for. Culling reads the centre and the
	# CONTENTS are drawn at the offset it chose, so the entire strip was
	# placed a map away. `maps/ladder.tres` escapes it (42/16 leaves the
	# last block centred at 40, still in range), which is exactly why a
	# test on that map would prove nothing.
	var space := _shipped_space()
	var last := Vector2i((space.width - 1) / NODE_CHUNK, 0)
	var centre := RenderCull.block_centre(space, last, NODE_CHUNK)

	# The property the whole test rests on, asserted directly rather than
	# left to the shipped width's good luck: the default map's width mod
	# NODE_CHUNK must land in 1..8, or the last block's nominal centre is
	# ON the map and there is nothing here to catch. 84 gave 4; 168 gives
	# 8, which is the last value that still works. A map change to 160,
	# 176 or anything from 169 to 175 would defuse this test silently, and
	# `maps/ladder.tres` at 42 already does (42 mod 16 = 10) — which is
	# why this loads the default map and not that one.
	var overhang := space.width % NODE_CHUNK
	assert_between(overhang, 1, NODE_CHUNK / 2,
		"setup: default map width %d mod %d = %d, so the last block's nominal "
		% [space.width, NODE_CHUNK, overhang]
		+ "centre is on the map and this test no longer tests anything — pick a "
		+ "width whose remainder is 1..%d" % (NODE_CHUNK / 2))

	var nominal := Vector2i(last.x * NODE_CHUNK + NODE_CHUNK / 2, NODE_CHUNK / 2)
	assert_gt(nominal.x, space.width - 1,
		"setup: the last block's nominal centre should be off the map")

	# Every cell the block actually owns must be inside the radius culling
	# will use, measured from the centre culling will use. That is the
	# whole contract between the two, and a wrapped centre fails it by a
	# map period rather than by a little.
	var radius := RenderCull.block_radius(space, NODE_CHUNK)
	for q in range(last.x * NODE_CHUNK, space.width):
		for r in range(0, NODE_CHUNK):
			var at := space.axial_offset_to_world(Vector2(float(q), float(r)))
			assert_lt(at.distance_to(centre), radius,
				"cell (%d,%d) is %.1f from its own chunk's centre, outside the "
				% [q, r, at.distance_to(centre)]
				+ "%.1f radius culling uses" % radius)


func test_a_block_centre_is_the_plain_answer_when_the_block_fits() -> void:
	# The other side of the boundary. Fixing the edge case must not move
	# any of the blocks that were always fine, or every forest on the map
	# shifts to fix six chunks.
	var space := _shipped_space()
	for key in [Vector2i(0, 0), Vector2i(1, 2), Vector2i(2, 3)]:
		var nominal := Vector2i(key.x * NODE_CHUNK + NODE_CHUNK / 2,
			key.y * NODE_CHUNK + NODE_CHUNK / 2)
		assert_lt(nominal.x, space.width, "setup: block %s should fit" % key)
		assert_lt(nominal.y, space.height, "setup: block %s should fit" % key)
		# A full block's owned cells run lo..lo+15, so their midpoint is
		# lo + 7.5 — half a cell short of the nominal lo + 8. Compare
		# against the midpoint, which is what "the middle of the cells it
		# owns" means, not against the nominal corner-biased centre.
		var mid := Vector2(float(key.x * NODE_CHUNK) + (NODE_CHUNK - 1) * 0.5,
			float(key.y * NODE_CHUNK) + (NODE_CHUNK - 1) * 0.5)
		assert_almost_eq(
			RenderCull.block_centre(space, key, NODE_CHUNK).distance_to(
				space.axial_offset_to_world(mid)),
			0.0, 0.001,
			"a block that fits on the map moved")

func test_a_forest_is_culled_by_its_trees_not_by_the_point_at_its_middle() -> void:
	# THE reported bug, as geometry. Pan until the chunk's centre leaves
	# the viewport while most of its trees are still well inside it.
	var space := _shipped_space()
	var offsets := space.lattice_offsets()
	var radius := RenderCull.block_radius(space, NODE_CHUNK)

	var target := space.to_world(Vector2i(space.width / 2, space.height / 2))
	var camera := _camera_looking_at(target, 20.0)
	var size := _screen_size(camera)
	var margin := size.x * CULL_MARGIN_FRACTION

	# Walk the chunk out to the left, half a unit at a time, and stop the
	# frame its centre crosses the margin — which is the frame the shipped
	# point test used to blink the whole 16x16 block out.
	var centre := target
	for _step in range(400):
		if not RenderCull.is_on_screen(camera, centre, margin, size):
			break
		centre.x -= 0.5

	assert_false(RenderCull.is_on_screen(camera, centre, margin, size),
		"setup: the chunk centre never left the viewport")
	assert_true(RenderCull.is_on_screen(camera, centre + Vector3(radius, 0.0, 0.0),
		margin, size),
		"setup: the chunk's near edge should still be plainly on screen")

	assert_null(RenderCull.visible_offset(camera, offsets, centre, margin, size),
		"setup: the point test should still be culling this — if it is not, the "
		+ "walk above stopped reproducing the defect and the assertions below are free")

	# The margin itself, before the offset. Asserting only on the combined
	# call would pass vacuously against the old code, which returned the
	# canonical offset here too — as a FALLBACK, having culled the chunk.
	# Same answer, opposite meaning.
	var scale := RenderCull.extent_scale(camera, radius, size)
	assert_true(RenderCull.is_on_screen(camera, centre,
		RenderCull.extent_margin(camera, centre, scale, margin), size),
		"the chunk's own on-screen radius does not reach its trees, so the "
		+ "block is still being culled on the point at its middle")

	assert_true(RenderCull.visible_offsets_of_extent(camera, offsets, centre,
		radius, margin, size).has(Vector3.ZERO),
		"a forest whose trees are on screen was culled by the point at its middle")


func test_the_extent_margin_is_a_projected_size() -> void:
	# It must not depend on which way the camera is facing (D-063 made the
	# camera turn), and it must fall off with distance. The version this
	# replaces projected an edge point along world x — the axis running
	# away from the viewer at 90 degrees of yaw, foreshortened to a
	# fraction of its true width.
	var space := _shipped_space()
	var target := space.to_world(Vector2i(space.width / 2, space.height / 2))
	var radius := RenderCull.block_radius(space, NODE_CHUNK)

	var north := _camera_looking_at(target, 20.0)
	var east := _camera_looking_at(target, 20.0)
	east.position = target + Vector3(20.0 * 0.6, 20.0, 0.0)
	east.look_at(target, Vector3.UP)

	var size := _screen_size(north)
	var scale := RenderCull.extent_scale(north, radius, size)
	var facing_north := RenderCull.extent_margin(north, target, scale, 0.0)
	var facing_east := RenderCull.extent_margin(east, target,
		RenderCull.extent_scale(east, radius, size), 0.0)

	assert_gt(facing_north, 0.0, "the margin should grow by something")
	assert_almost_eq(facing_east, facing_north, facing_north * 0.05,
		"turning the camera changed how wide the same chunk is considered to be")

	# A chunk twice as deep covers half as much screen, or this is not a
	# projected size at all — and a margin that does not shrink with
	# distance is what drags a far lattice copy into view.
	var forward := -north.global_transform.basis.z
	var far_off := target + forward * forward.dot(target - north.global_position)
	assert_almost_eq(RenderCull.extent_margin(north, far_off, scale, 0.0),
		facing_north * 0.5, facing_north * 0.02,
		"doubling the depth should halve the margin")


func test_a_forest_with_no_visible_copy_is_hidden_rather_than_relocated() -> void:
	# The other half of the fix. `nearest_offset` answers "which copy is
	# closest to the look-at point", which is the right rule for a thing
	# that must always be drawn somewhere — a rally marker, a placement
	# ghost — and the wrong rule for something being culled.
	var space := _shipped_space()
	var offsets := space.lattice_offsets()
	var radius := RenderCull.block_radius(space, NODE_CHUNK)

	var target := space.to_world(Vector2i(0, space.height / 2))
	var camera := _camera_looking_at(target, 20.0)
	var size := _screen_size(camera)
	var margin := size.x * CULL_MARGIN_FRACTION
	# Half a map away in q, so the canonical copy and the wrapped one are
	# both as far from the camera as this torus allows.
	var centre := space.to_world(Vector2i(space.width / 2, space.height / 2))

	assert_true(RenderCull.visible_offsets_of_extent(camera, offsets, centre,
		radius, margin, size).is_empty(),
		"a forest on the far side of the map must report nowhere, so the client "
		+ "can hide it — falling through to a fallback is what teleports it")

	# And the fallback must be shown to be a genuinely different answer,
	# or the assertion above is describing nothing.
	var fallback := RenderCull.nearest_offset(offsets, centre, target)
	assert_gt(fallback.length(), 100.0,
		"setup: the nearest copy should be most of a map period from the canonical one")
	assert_false(RenderCull.is_on_screen(camera, centre + fallback, margin, size),
		"the fallback copy is off screen too, so relocating the block buys "
		+ "nothing and costs a map-wide jump the frame it flips")


# --- the tier is STABLE, not merely correct (#155) ---------------------
#
# Every LOD check above this line is single-frame, and #155 is a
# frame-to-frame difference: a squad sitting near 55 or 110 flipped tier
# on the smallest movement of itself or the camera, taking a forty-man
# squad to twelve (-70%) and back in the MIDDLE of the view. No test could
# see it, because none of them asked the question twice.

func test_a_squad_jittering_across_a_boundary_holds_its_tier() -> void:
	# THE defect, stated as the issue asks for it: the tier for a fixed
	# squad must not change when the camera moves by a small amount across
	# a boundary.
	#
	# 3 units of wobble either side of 55 — less than two soldiers' worth
	# of spacing, and far less than a squad drifting on its curve while a
	# player nudges the camera.
	var tier := RenderCull.detail_tier(30.0, -1)
	assert_eq(tier, 0, "setup: a squad 30 units from the camera is drawn in full")

	var flips := 0
	for i in range(400):
		var distance := 55.0 + sin(float(i) * 0.37) * 3.0
		var next := RenderCull.detail_tier(distance, tier)
		if next != tier:
			flips += 1
		tier = next

	assert_eq(flips, 0,
		"the tier changed %d times while the squad wobbled 3 units around a boundary" % flips)
	assert_eq(tier, 0, "the squad ended up thinned without ever having receded")


func test_the_far_boundary_is_as_stable_as_the_near_one() -> void:
	# Both boundaries, because 12 -> 5 is a 58% drop and the issue reports
	# the same symptom at both. A band expressed as a FRACTION covers the
	# far one without a second constant, which is the reason it is one.
	var tier := RenderCull.detail_tier(112.0, 1)
	assert_eq(tier, 1, "setup: a squad just past 110 is on the middle tier")

	var flips := 0
	for i in range(400):
		var distance := 110.0 + sin(float(i) * 0.37) * 6.0
		var next := RenderCull.detail_tier(distance, tier)
		if next != tier:
			flips += 1
		tier = next

	assert_eq(flips, 0,
		"the tier changed %d times while the squad wobbled 6 units around 110" % flips)


func test_detail_is_lost_going_out_and_regained_at_the_plain_boundary() -> void:
	# The band is one-sided on purpose, so state both sides of it. Erring
	# toward detail is the cheap direction to err: the cost of coming back
	# early is a little derivation, and the cost of leaving early is
	# under-drawing a squad the player is looking straight at.
	assert_eq(RenderCull.detail_tier(60.0, 0), 0,
		"a squad that has receded to 60 thinned before it left the band")
	assert_eq(RenderCull.detail_tier(64.0, 0), 1,
		"a squad 64 units out — past the whole band — kept full detail")
	assert_eq(RenderCull.detail_tier(60.0, 1), 1,
		"a thinned squad regained detail at 60, which is outside 55")
	assert_eq(RenderCull.detail_tier(54.0, 1), 0,
		"a squad that came back inside 55 was still drawn thinned")


func test_a_squad_with_no_history_reads_the_plain_ladder() -> void:
	# A first sighting has no side of the band to be on, so it takes the
	# tiers as tuned. The band must not become a permanent 15% shift of
	# the whole ladder — that would be a retune of numbers measured
	# against `just bench-render`, smuggled in as a stability fix.
	assert_eq(RenderCull.detail_tier(54.0, -1), 0)
	assert_eq(RenderCull.detail_tier(56.0, -1), 1)
	assert_eq(RenderCull.detail_tier(109.0, -1), 1)
	assert_eq(RenderCull.detail_tier(111.0, -1), 2)


func test_a_squad_that_really_recedes_still_loses_detail() -> void:
	# The other half of a hysteresis guard, and the one that keeps it
	# honest: "never changes" would pass every assertion above and delete
	# D-045's only lever on the frame budget. Every tier must still be
	# reached, in order, by a squad that genuinely walks away.
	var tier := -1
	var seen: Array[int] = []
	for step in range(400):
		tier = RenderCull.detail_tier(20.0 + float(step), tier)
		if seen.is_empty() or seen[seen.size() - 1] != tier:
			seen.append(tier)
	assert_eq(seen, [0, 1, 2] as Array[int],
		"a squad walking from 20 to 420 units out passed through tiers %s" % [seen])

	# And it must not take forever about it: the band is 15%, so the
	# latest a squad may thin is one step past 63.25.
	assert_eq(RenderCull.detail_tier(64.0, 0), 1)
	assert_eq(RenderCull.detail_tier(127.0, 1), 2)


func test_the_ladder_only_ever_thins() -> void:
	# D-045's thinner-never-smaller rule needs the ladder to be monotone:
	# a further tier may not draw MORE men. Cheap, and it is the check
	# that would catch a tier inserted in the wrong place.
	var previous := 1 << 30
	for tier in range(RenderCull.LOD_TIERS.size()):
		var soldiers := RenderCull.lod_soldiers(tier)
		assert_true(soldiers <= previous,
			"tier %d draws %d soldiers, more than the tier before it" % [tier, soldiers])
		previous = soldiers
	assert_true(RenderCull.lod_soldiers(-1) >= previous,
		"a caller with no tier at all must be given FULL detail, never the coarsest")
	assert_eq(RenderCull.lod_soldiers(RenderCull.LOD_TIERS.size()),
		RenderCull.lod_soldiers(-1),
		"an out-of-range tier must over-draw, exactly as a missing one does")


# --- the distance the ladder is asked about (#155's second trigger) ----

func test_lod_distance_takes_the_nearest_visible_copy() -> void:
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3(0.0, 0.0, 100.0)]
	var distance := RenderCull.lod_distance(offsets, Vector3.ZERO, Vector3(0.0, 0.0, 90.0))
	assert_almost_eq(distance, 10.0, 0.001,
		"the wrapped copy sits 10 units from the camera and was not the one measured")


func test_lod_distance_does_not_jump_when_the_nearest_copy_changes() -> void:
	# Since D-20260818-entities-are-drawn-at-every-visible-copy a squad is
	# drawn at every copy on screen, and `nearest_offset` picks one of them
	# for the things that need a single position. That is an ARGMIN, and it
	# is taken against what the camera LOOKS AT while the ladder measures
	# to where the camera IS — two different points on this rig, so the
	# distance handed to the ladder jumped a whole map period the moment
	# the argmin flipped, with the camera perfectly still.
	#
	# A minimum is continuous across exactly that tie. Sweeping the look-at
	# point over it, the argmin must flip (or this fixture proves nothing)
	# while `lod_distance` must not move.
	var period := 100.0
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3(0.0, 0.0, period)]
	var centre := Vector3.ZERO

	var chosen: Array[Vector3] = []
	var distances: Array[float] = []
	var argmin_distances: Array[float] = []
	for i in range(11):
		# The look-at point crossing the halfway line, and the eye on
		# client.gd's own rig: `RenderCull.PITCH_RUN` behind it, one
		# height above.
		var target := Vector3(0.0, 0.0, period * 0.5 + (float(i) - 5.0) * 0.01)
		var eye := target + Vector3(0.0, 40.0, 40.0 * RenderCull.PITCH_RUN)
		var offset := RenderCull.nearest_offset(offsets, centre, target)
		if not chosen.has(offset):
			chosen.append(offset)
		argmin_distances.append((centre + offset).distance_to(eye))
		distances.append(RenderCull.lod_distance(offsets, centre, eye))

	assert_eq(chosen.size(), 2,
		"setup: the sweep never crossed the tie, so this fixture measures nothing")
	assert_gt(argmin_distances.max() - argmin_distances.min(), 20.0,
		"setup: the argmin's distance did not move, so there was nothing to fix")
	# Not zero: the sweep moves the CAMERA 0.1 units, so the honest answer
	# moves with it. What must not happen is a jump of the size the argmin
	# takes above — and 0.5 is two orders of magnitude below it.
	assert_lt(distances.max() - distances.min(), 0.5,
		"lod_distance moved %.2f units across a tie the camera never noticed"
			% (distances.max() - distances.min()))


func test_a_still_camera_cannot_flip_a_tier_across_a_lattice_tie() -> void:
	# The consequence, in the units the player sees: the argmin's distance
	# straddles 55 at this rig, so the same motionless squad was drawn with
	# every man on one frame and twelve on the next.
	var period := 100.0
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3(0.0, 0.0, period)]
	var centre := Vector3.ZERO

	var tier := -1
	var flips := 0
	var argmin_tiers: Array[int] = []
	for i in range(21):
		var target := Vector3(0.0, 0.0, period * 0.5 + (float(i) - 10.0) * 0.01)
		var eye := target + Vector3(0.0, 40.0, 40.0 * RenderCull.PITCH_RUN)
		var next := RenderCull.detail_tier(
			RenderCull.lod_distance(offsets, centre, eye), tier)
		if tier >= 0 and next != tier:
			flips += 1
		tier = next
		var offset := RenderCull.nearest_offset(offsets, centre, target)
		argmin_tiers.append(
			RenderCull.detail_tier((centre + offset).distance_to(eye), -1))

	assert_true(argmin_tiers.has(0) and argmin_tiers.has(1),
		"setup: the old argmin distance did not cross a tier boundary here, so this proves nothing")
	assert_eq(flips, 0,
		"the tier changed %d times while nothing moved but the tie" % flips)

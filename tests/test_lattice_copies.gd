extends GutTest

## Guards D-20260818-entities-are-drawn-at-every-visible-copy — an entity
## exists at EVERY lattice copy of the torus the camera can see, and
## nothing anywhere chooses one of them.
##
## Terrain has been drawn nine times since D-035 and everything standing
## on it exactly once, repositioned per frame to a chosen copy. That
## asymmetry is the most-repeated defect in this project's history
## (armies vanishing at the seam; half the screen rendering no units; a
## click landing on a soldier and selecting nothing; forest chunks
## snapping a map period sideways), and every fix so far improved the
## CHOICE. There is no correct choice — a view can genuinely contain two
## copies of the same ground.
##
## `client.gd` cannot be tested headless (D-014), so what is proven here
## is the two halves with the interesting failure modes: the cull that
## now reports EVERY visible copy, and the node pooling that draws them
## sharing one derived MultiMesh. The third check is a source scan, for
## the reason `tests/test_terrain_fog.gd` has one — every other check can
## pass while nothing in the client actually calls the thing.


func _shipped_space() -> TorusSpace:
	var config := load("res://maps/default.tres") as MapConfig
	return TorusSpace.new(config.width, config.height, config.hex_size)


func _camera_looking_at(target: Vector3, height: float) -> Camera3D:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.position = target + Vector3(0.0, height, height * RenderCull.PITCH_RUN)
	camera.look_at(target, Vector3.UP)
	return camera


func _screen_size(camera: Camera3D) -> Vector2:
	return camera.get_viewport().get_visible_rect().size


# --- the cull now reports every copy, not one -------------------------

func test_a_view_holding_two_copies_of_the_same_ground_is_told_about_both() -> void:
	# The measurement that made the whole choice-of-copy question
	# unanswerable, as a test. Zoom past `max_camera_height` — the cap that
	# exists ONLY because entities were drawn once — and the same cell is
	# genuinely on screen twice. A function returning one offset has to
	# name one of two right answers, and whichever it names, the other
	# copy is bare terrain with nothing standing on it.
	var space := _shipped_space()
	var offsets := space.lattice_offsets()
	var target := space.to_world(Vector2i(0, space.height / 2))
	var cap := RenderCull.max_camera_height(space, 8.0, 4000.0)
	var camera := _camera_looking_at(target, cap * 6.0)
	var size := _screen_size(camera)

	var drawn := RenderCull.visible_offsets_of_extent(
		camera, offsets, target, 2.0, 0.0, size)

	assert_gt(drawn.size(), 1,
		"zoomed well past the cap, more than one lattice copy of the same "
		+ "point is on screen — if this is 1 the setup stopped reproducing "
		+ "the condition and the rest of this file proves nothing")
	# Every one of them is genuinely on screen, or this is just a longer
	# list rather than a truthful one.
	for offset in drawn:
		assert_true(RenderCull.is_on_screen(camera, target + offset, 0.0, size),
			"an offset was reported that is not on screen")
	assert_eq(drawn[0], Vector3.ZERO,
		"the canonical copy comes first, so a caller taking one still takes "
		+ "the unwrapped one (TorusSpace.lattice_offsets' own ordering)")


func test_a_thing_with_no_copy_on_screen_reports_nowhere() -> void:
	# The half that was already right and must stay right: empty means
	# HIDE, never "put it at the nearest copy instead".
	var space := _shipped_space()
	var target := space.to_world(Vector2i(0, space.height / 2))
	var camera := _camera_looking_at(target, 20.0)
	var size := _screen_size(camera)
	var far_side := space.to_world(Vector2i(space.width / 2, space.height / 2))

	assert_true(RenderCull.visible_offsets_of_extent(camera,
		space.lattice_offsets(), far_side, 2.0, 0.0, size).is_empty(),
		"a squad on the far side of the map must report nowhere")


# --- one derivation, several views ------------------------------------

func _unit() -> PrimitiveUnit:
	var unit := PrimitiveUnit.new()
	add_child_autofree(unit)
	unit.rebuild(UnitRoster.by_id(&"legion_militia"))
	return unit


func _drawn_children(unit: PrimitiveUnit) -> Array:
	var out := []
	for child in unit.get_children():
		if child is MultiMeshInstance3D and (child as MultiMeshInstance3D).visible:
			out.append(child)
	return out


func test_a_squad_is_drawn_at_every_copy_it_is_given() -> void:
	# THE defect. One node was placed at one offset, so a squad straddling
	# the seam appeared on one visible copy of the ground and not on the
	# other.
	var unit := _unit()
	var copies: Array[Vector3] = [
		Vector3.ZERO, Vector3(100.0, 0.0, 0.0), Vector3(0.0, 0.0, 200.0)]
	unit.set_lattice_offsets(copies)

	var drawn := _drawn_children(unit)
	assert_eq(drawn.size(), 3, "a squad on three visible copies is drawn three times")
	var at := []
	for child in drawn:
		at.append((child as Node3D).position)
	for offset in copies:
		assert_true(at.has(offset),
			"no view of the squad was placed at %s" % offset)
	assert_eq(unit.lattice_offsets, copies,
		"the renderer must record where it drew, because selection reads it")


func test_the_extra_copies_share_the_one_derived_multimesh() -> void:
	# The whole affordability claim. Per-soldier derivation is ~96% of the
	# client's frame at scale (D-045); a copy that derived its own
	# soldiers would multiply that by nine. Every view points at the SAME
	# MultiMesh resource and the same material, so a copy is a transform
	# and two references.
	var unit := _unit()
	unit.set_lattice_offsets([Vector3.ZERO, Vector3(100.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 200.0)] as Array[Vector3])

	var drawn := _drawn_children(unit)
	assert_gt(drawn.size(), 1, "setup: more than one view")
	var first := drawn[0] as MultiMeshInstance3D
	for child in drawn:
		var view := child as MultiMeshInstance3D
		assert_true(view.multimesh == first.multimesh,
			"a copy allocated its own MultiMesh, so its soldiers are derived twice")
		assert_true(view.material_override == first.material_override,
			"a copy allocated its own material — UnitMesh.material_for builds a "
			+ "fresh ShaderMaterial per call and has no cache")


func test_a_squad_with_no_visible_copy_is_drawn_nowhere() -> void:
	var unit := _unit()
	unit.set_lattice_offsets([Vector3.ZERO, Vector3(100.0, 0.0, 0.0)] as Array[Vector3])
	assert_true(unit.visible, "setup: the squad was on screen")

	unit.set_lattice_offsets([] as Array[Vector3])
	assert_false(unit.visible,
		"an empty copy list is the DERIVATION GATE (D-045) — it means hide, "
		+ "and it must not leave a stale view standing")
	assert_eq(_drawn_children(unit).size(), 0, "a view was left visible")


func test_a_squad_that_shrinks_its_copies_hides_the_spare_views() -> void:
	# The pool is reused rather than rebuilt, so the shrink is the case
	# that leaves ghosts standing if it is got wrong.
	var unit := _unit()
	unit.set_lattice_offsets([Vector3.ZERO, Vector3(100.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 200.0)] as Array[Vector3])
	unit.set_lattice_offsets([Vector3.ZERO] as Array[Vector3])
	assert_eq(_drawn_children(unit).size(), 1,
		"a squad that walked back inside the map left a copy of itself behind")


# --- the generic mechanism --------------------------------------------

func _source(parent: Node3D) -> MeshInstance3D:
	var source := MeshInstance3D.new()
	source.mesh = BoxMesh.new()
	source.material_override = StandardMaterial3D.new()
	parent.add_child(source)
	return source


func test_a_copy_carries_the_sources_rotation_and_scale() -> void:
	# A building is drawn rotated to its `facing` and scaled by its
	# construction progress. A copy placed as a CHILD would have both
	# applied to its lattice offset — the offset turned and squashed — so
	# copies are siblings differing only in position.
	var root := Node3D.new()
	add_child_autofree(root)
	var source := _source(root)
	source.rotation.y = 0.7
	source.scale = Vector3(1.0, 0.4, 1.0)
	var mirrors: Array[Node3D] = []

	var base := Vector3(5.0, 1.0, 9.0)
	var away := Vector3(100.0, 0.0, 0.0)
	LatticeCopies.draw(source, mirrors, base, [Vector3.ZERO, away] as Array[Vector3])

	assert_eq(mirrors.size(), 1, "one extra copy for one extra offset")
	var copy := mirrors[0] as MeshInstance3D
	assert_eq(copy.position, base + away, "the copy is at the offset it was given")
	assert_eq(source.position, base, "the source keeps the canonical copy")
	assert_almost_eq(copy.basis.get_euler().y, source.basis.get_euler().y, 0.0001,
		"the copy did not inherit the source's facing")
	assert_almost_eq(copy.scale.y, source.scale.y, 0.0001,
		"the copy did not inherit the source's construction progress")
	assert_true(copy.mesh == source.mesh, "the copy allocated its own mesh")
	assert_true(copy.material_override == source.material_override,
		"the copy allocated its own material")


func test_a_composite_copies_its_children() -> void:
	# A forest chunk is a Node3D of one MultiMesh per tree species and a
	# wall junction a Node3D of a bastion and its stair treads. A copy of
	# one that dropped its children would draw an empty wood.
	var root := Node3D.new()
	add_child_autofree(root)
	var source := Node3D.new()
	root.add_child(source)
	for i in range(2):
		var part := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = BoxMesh.new()
		part.multimesh = mm
		part.position = Vector3(float(i), 0.0, 0.0)
		source.add_child(part)

	var mirrors: Array[Node3D] = []
	LatticeCopies.draw(source, mirrors, Vector3.ZERO,
		[Vector3.ZERO, Vector3(100.0, 0.0, 0.0)] as Array[Vector3])

	var copy := mirrors[0]
	assert_eq(copy.get_child_count(), 2, "the copy lost the chunk's contents")
	for i in range(2):
		var part := source.get_child(i) as MultiMeshInstance3D
		var twin := copy.get_child(i) as MultiMeshInstance3D
		assert_true(twin.multimesh == part.multimesh,
			"a copy of a chunk rebuilt its trees instead of sharing them")
		assert_eq(twin.position, part.position, "a part moved inside its copy")

	# A species added later must reach the copies — the chunk is rebuilt
	# on a reveal or a felling, and a copy that kept the old set would
	# draw a wood that no longer exists.
	var extra := MultiMeshInstance3D.new()
	extra.multimesh = MultiMesh.new()
	source.add_child(extra)
	LatticeCopies.resync(source, mirrors)
	assert_eq(copy.get_child_count(), 3, "a rebuilt chunk did not reach its copies")


# --- the copies and the props' fog (D-20260817-fog-covers-props) ------

func test_a_wrapped_forest_reads_the_same_fog_as_its_canonical_copy() -> void:
	# The interaction between this change and
	# D-20260817-fog-covers-props, pinned because neither file alone
	# states it and both depend on it.
	#
	# A tree reads the fog field at a coordinate carried in per-instance
	# custom data, taken from its CELL. That was already the right rule
	# when a chunk was drawn at ONE lattice copy at a time; it is
	# load-bearing now that a chunk is drawn at up to nine SIMULTANEOUSLY.
	# What makes it safe is that a copy shares the source's MultiMesh —
	# the buffer the fog coordinate lives in — so there is one answer and
	# no second place to get it wrong.
	#
	# And one answer is the CORRECT number of answers: a lattice copy is a
	# copy of the whole world (D-035), so a tree drawn at a wrapped copy
	# stands on the same cell as the canonical one and has the same fog
	# state by construction. A copy that carried its own custom data could
	# only ever disagree with the ground under it.
	var root := Node3D.new()
	add_child_autofree(root)
	var chunk := Node3D.new()
	root.add_child(chunk)

	var trees := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# Declared before instance_count, exactly as `_rebuild_tree_chunk`
	# does it — the format flags decide the buffer layout and Godot
	# reallocates rather than reinterprets when they change afterwards.
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = 3
	trees.multimesh = mm
	chunk.add_child(trees)

	var mirrors: Array[Node3D] = []
	LatticeCopies.draw(chunk, mirrors, Vector3.ZERO,
		[Vector3.ZERO, Vector3(100.0, 0.0, 0.0)] as Array[Vector3])

	var twin := mirrors[0].get_child(0) as MultiMeshInstance3D
	assert_true(twin.multimesh == mm,
		"the wrapped copy of a forest has its own MultiMesh, so its trees "
		+ "carry their own fog coordinates and can be lit differently from "
		+ "the ground they stand on")
	assert_true(twin.multimesh.use_custom_data,
		"the copy lost the per-instance channel the fog coordinate rides in")


func test_the_fog_coordinate_comes_from_the_cell_not_the_world() -> void:
	# The other half, and the reason the assertion above is enough: what
	# rides in that shared buffer must be derived from the CELL. A
	# world-derived coordinate would be wrong the moment a chunk is drawn
	# anywhere but its canonical copy — which, after this change, is most
	# of the time for anything near a seam.
	#
	# Asserted against `PropFog` rather than assumed, because this file
	# and that one are the two halves of the claim and neither imports the
	# other.
	var space := _shipped_space()
	var cell := Vector2i(3, 5)
	var here := PropFog.instance_data(space, cell)
	assert_eq(PropFog.instance_data(space, cell), here,
		"the fog coordinate is not a pure function of the cell")
	assert_eq(here.r, TerrainChunk.fog_uv(space, cell, -1).x,
		"PropFog re-derives the fog coordinate instead of asking "
		+ "TerrainChunk for it, so a tree and the ground under it can drift")
	assert_eq(here.g, TerrainChunk.fog_uv(space, cell, -1).y,
		"PropFog re-derives the fog coordinate instead of asking "
		+ "TerrainChunk for it, so a tree and the ground under it can drift")


# --- the caller has to exist (D-106's lesson) -------------------------

func test_the_client_draws_entities_at_every_copy_rather_than_choosing_one() -> void:
	# Every check above can pass while `client.gd` still places one node
	# at one chosen offset — which is precisely how the ground went six
	# milestones with no fog of war on it (D-106). So this scans the
	# client for the callers.
	var source := FileAccess.get_file_as_string("res://client.gd")
	assert_false(source.is_empty(), "setup: client.gd should be readable")

	assert_true(source.contains("RenderCull.visible_offsets_of_extent")
			or source.contains("_visible_copies_of("),
		"client.gd never asks which copies are visible, so nothing it draws "
		+ "can be at more than one of them")
	assert_true(source.contains("LatticeCopies.draw("),
		"client.gd never draws a lattice copy — the entities are still drawn once")
	assert_true(source.contains("set_lattice_offsets("),
		"squads are not handed their copies, so a squad across the seam is "
		+ "still drawn on one of the two visible copies of its ground")

	# `_lattice_offset_for` is the surviving one-copy rule, and it is
	# allowed exactly two callers: the placement ghost and its drag line.
	# Those follow the MOUSE, which is a ray into one copy of the ground,
	# so previewing a barracks at nine places would be the same bug
	# mirrored. Anything else reaching for it is an entity being drawn
	# once again.
	var calls := 0
	for line in source.split("\n"):
		var text := line.strip_edges()
		if text.begins_with("#"):
			continue
		if text.begins_with("func _lattice_offset_for"):
			continue
		calls += text.count("_lattice_offset_for(")
	assert_eq(calls, 2,
		"one-copy placement is back in client.gd — `_lattice_offset_for` is "
		+ "for the cursor's own placement preview and nothing else")

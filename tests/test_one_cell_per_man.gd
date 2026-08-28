extends GutTest

## Guards the single ground derivation per drawn man (#245).
##
## A man's height and his footing are both answers about the CELL he
## stands in, and until this change each was found by converting his
## world position to that cell separately — `Formation._stands_on_passable`
## and then `TerrainChunk.height_at`, one line apart, for every drawn man
## every frame. `TerrainChunk.ground_at` answers both from one
## derivation.
##
## The only thing that makes that safe is that the answers are
## IDENTICAL, and identical is what is asserted here — against the path
## it replaces, over real generated terrain, including the places the
## clamp actually fires. A "close enough" height is a soldier standing
## somewhere else on two machines, which is the failure D-006 exists to
## prevent.

const W := 64
const H := 32


func _world() -> Dictionary:
	var space := TorusSpace.new(W, H, 1.0)
	var fields := TerrainGen.new().build_fields(space)
	return {"space": space, "surface": fields.surface, "passable": fields.passable}


func _sampler(space: TorusSpace, surface: PackedFloat32Array) -> Callable:
	return func(x: float, z: float) -> float:
		return TerrainChunk.height_at(space, surface, x, z)


func _curve(space: TorusSpace, at: Vector2i) -> StateCurve:
	var curve := StateCurve.new()
	curve.append_cell(0.0, at, space)
	curve.append_cell(1.0, Vector2i(at.x + 1, at.y), space)
	return curve


# --- the two paths agree, everywhere -----------------------------------

func test_one_derivation_gives_the_same_man_as_two() -> void:
	var world := _world()
	var space: TorusSpace = world["space"]
	var surface: PackedFloat32Array = world["surface"]
	var passable: PackedByteArray = world["passable"]
	var sampler := _sampler(space, surface)

	var shapes := ["line", "column", "wedge", "ring", "sparse"]
	var compared := 0
	var clamped := 0
	for cell_index in range(0, space.cell_count(), 7):
		var at := space.from_index(cell_index)
		var curve := _curve(space, at)
		var shape: String = shapes[cell_index % shapes.size()]
		for alive in [8, 24, 40]:
			var two := Formation.soldier_transforms_sampled(
				curve, 0.5, alive, shape, 1.0, space, sampler, -1, passable)
			var one := Formation.soldier_transforms_sampled(
				curve, 0.5, alive, shape, 1.0, space, sampler, -1, passable,
				0, NAN, surface)
			assert_eq(one.size(), two.size(), "same men at cell %d" % cell_index)
			for i in range(two.size()):
				# BIT identical, not almost: both machines derive this.
				assert_eq(one[i].origin, two[i].origin,
					"cell %d, %s, man %d" % [cell_index, shape, i])
				compared += 1
				# Did the clamp actually fire anywhere? A run where it
				# never does proves nothing about the half that matters.
				if not Formation.grounded_offset(
						curve.sample_world(0.5, space),
						two[i].origin - curve.sample_world(0.5, space),
						space, passable).is_equal_approx(
						two[i].origin - curve.sample_world(0.5, space)):
					clamped += 1
	assert_gt(compared, 5000, "the sweep really compared men")
	gut.p("compared %d drawn men; the clamp moved %d of them" % [compared, clamped])


func test_the_clamp_is_exercised_by_this_map() -> void:
	# The vacuity check the sweep above needs: if the generated terrain
	# were open everywhere, every assertion in this file would be about
	# the easy half.
	var world := _world()
	var passable: PackedByteArray = world["passable"]
	var blocked := 0
	for i in range(passable.size()):
		if passable[i] == 0:
			blocked += 1
	assert_gt(blocked, 0,
		"the test map has ground a squad cannot walk on, or the clamp "
		+ "never fires and this file proves nothing")


func test_the_split_out_interpolation_is_the_same_interpolation() -> void:
	var world := _world()
	var space: TorusSpace = world["space"]
	var surface: PackedFloat32Array = world["surface"]
	var passable: PackedByteArray = world["passable"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x60D
	for _i in range(2000):
		var at := Vector3(rng.randf_range(-200.0, 200.0), 0.0,
			rng.randf_range(-200.0, 200.0))
		var fractional := space.world_to_axial(at)
		var cell := space.round_axial(fractional)
		assert_eq(
			TerrainChunk.height_in_cell(space, surface, fractional, cell,
				space.index(cell)),
			TerrainChunk.height_at(space, surface, at.x, at.z),
			"height at %s" % at)


func test_no_terrain_still_means_flat_and_open() -> void:
	# The convention every other caller relies on: an empty field is "no
	# terrain", not "everything is at zero and impassable". The one-sample
	# path is only taken when there IS a field, so a caller with none
	# derives exactly what it always did.
	var space := TorusSpace.new(16, 8, 1.0)
	var curve := StateCurve.new()
	curve.append_cell(0.0, Vector2i(4, 4), space)
	var men := Formation.soldier_transforms_sampled(
		curve, 0.0, 9, "line", 1.0, space, Callable(), -1, PackedByteArray(),
		0, NAN, PackedFloat32Array())
	assert_eq(men.size(), 9)
	for man in men:
		assert_eq(man.origin.y, 0.0, "flat ground")


# --- the wall tier ------------------------------------------------------

func test_a_squad_on_the_wall_is_still_lifted() -> void:
	# `ClientState._sampler_for` used to wrap the sampler in a SECOND
	# lambda per squad per frame to add the wall-tier bump (D-076). The
	# bump is an argument now — same answer, one less closure allocated
	# per squad per frame.
	var world := _world()
	var space: TorusSpace = world["space"]
	var surface: PackedFloat32Array = world["surface"]
	var passable: PackedByteArray = world["passable"]
	var curve := _curve(space, Vector2i(5, 5))
	var ground := Formation.soldier_transforms_sampled(
		curve, 0.5, 12, "line", 1.0, space, Callable(), -1, passable,
		0, NAN, surface, 0.0)
	var wall := Formation.soldier_transforms_sampled(
		curve, 0.5, 12, "line", 1.0, space, Callable(), -1, passable,
		0, NAN, surface, 2.5)
	for i in range(ground.size()):
		assert_almost_eq(wall[i].origin.y, ground[i].origin.y + 2.5, 0.0001,
			"man %d stands on the walkway" % i)
		assert_eq(wall[i].origin.x, ground[i].origin.x, "and not beside it")
		assert_eq(wall[i].origin.z, ground[i].origin.z)


# --- the callers --------------------------------------------------------

func test_the_client_hands_over_the_field_it_draws_from() -> void:
	# The caller-exists half (D-106's rule): `ground_at` can be perfect
	# and cost nothing if nobody passes the surface in. Both drawing
	# surfaces must — and they must pass the SAME field the mesh is built
	# from, or the men stand on a ground nobody drew.
	for path in ["res://client.gd", "res://bench_render.gd"]:
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text, "", "%s is readable" % path)
		assert_true(text.contains("terrain_surface"),
			("%s must hand ClientState the surface field, or every drawn "
			+ "man pays for his cell twice (#245)") % path)

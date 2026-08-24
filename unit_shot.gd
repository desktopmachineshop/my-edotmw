extends Node3D

## A close-up of ONE unit model, through the real render path.
##
## `gen-model-preview` frames the whole roster, which puts every soldier at
## about thirty pixels — fine for "did they all draw", useless for "what does
## this one look like". Same pipeline (a UnitDef, a PrimitiveUnit, the shipping
## shaders and lighting rig), one model, filling the frame.
##
##   tools/godot.exe --headless -s res://unit_shot.gd -- --model=gatherers

const SIZE := Vector2i(1000, 1000)

var model_id := &"gatherers"
var out_path := "res://artifacts/unit-shot.png"
var seconds := 0.35


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text.begins_with("--model="):
			model_id = StringName(text.trim_prefix("--model="))
		elif text.begins_with("--out="):
			out_path = text.trim_prefix("--out=")

	var def: UnitDef = null
	for candidate in UnitRoster.load_all():
		if candidate.model_id == model_id:
			def = candidate
			break
	if def == null:
		push_error("unit_shot: no UnitDef uses model '%s'" % model_id)
		get_tree().quit(1)
		return

	print("unit_shot: %s (model '%s') textured=%s"
		% [def.id, def.model_id,
			"yes" if UnitMesh.texture_for(def.model_id) != null else "no"])

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.05, 3.1)
	camera.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
	camera.fov = 42.0
	add_child(camera)
	camera.make_current()

	add_child(WorldLook.make_sun(true))
	var world := WorldEnvironment.new()
	world.environment = WorldLook.make_environment(true)
	add_child(world)

	# One soldier, at the origin, drawn exactly as a squad member is.
	var unit := PrimitiveUnit.new()
	add_child(unit)
	unit.rebuild(def, PlayerColours.of_index(0))
	unit.set_slot_transforms([Transform3D(Basis(), Vector3.ZERO)] as Array[Transform3D])

	_shoot()


func _shoot() -> void:
	# Let the VAT advance off its rest frame before capturing, the same reason
	# gen-model-preview takes a `--seconds`.
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(seconds * 1000.0):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	image.save_png(absolute)
	print("unit_shot: wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	get_tree().quit(0)

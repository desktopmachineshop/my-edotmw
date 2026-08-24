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
var clip_name := "walk"
var front_view := false
var burst := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text.begins_with("--model="):
			model_id = StringName(text.trim_prefix("--model="))
		elif text.begins_with("--out="):
			out_path = text.trim_prefix("--out=")
		elif text.begins_with("--clip="):
			clip_name = text.trim_prefix("--clip=")
		elif text.begins_with("--seconds="):
			seconds = float(text.trim_prefix("--seconds="))
		elif text == "--front":
			front_view = true
		elif text.begins_with("--burst="):
			burst = int(text.trim_prefix("--burst="))

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

	# THE GAME'S CAMERA ANGLE, not a turntable's.
	#
	# `client.gd` places the camera at `target + (0, h, h * PITCH_RUN)`, which
	# is 59 degrees below horizontal — very nearly overhead. This shot used to
	# sit at -6 degrees, roughly eye level, and that is a good way to judge a
	# MODEL and a bad way to judge a WALK: at eye level a leg swing is the
	# most obvious thing on screen; from above it is foreshortened to almost
	# nothing while the helmet and backpack fill the silhouette.
	#
	# An animation tuned on the wrong angle was reported from play as "no
	# walking" while every measurement said the clip was fine. Same family as
	# `test-client` pointing at a spawn and `gen-model-preview` framing the
	# whole roster: when a rendered check has to see something specific, frame
	# it the way the player will. `--front` keeps the old view, which is what
	# it was always good for.
	var camera := Camera3D.new()
	if front_view:
		camera.position = Vector3(0.0, 1.05, 3.1)
		camera.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
	else:
		var h := 3.0
		camera.position = Vector3(0.0, h, h * RenderCull.PITCH_RUN)
		camera.look_at_from_position(
			camera.position, Vector3(0.0, 0.75, 0.0), Vector3.UP)
	camera.fov = 42.0
	add_child(camera)
	camera.make_current()
	print("unit_shot: camera %s" % ("front (model view)" if front_view
		else "GAME angle, %.0f deg down"
			% rad_to_deg(atan2(1.0, RenderCull.PITCH_RUN))))

	add_child(WorldLook.make_sun(true))
	var world := WorldEnvironment.new()
	world.environment = WorldLook.make_environment(true)
	add_child(world)

	# One soldier, at the origin, drawn exactly as a squad member is.
	var unit := PrimitiveUnit.new()
	add_child(unit)
	unit.rebuild(def, PlayerColours.of_index(0))
	unit.set_slot_transforms([Transform3D(Basis(), Vector3.ZERO)] as Array[Transform3D])

	# Which CLIP to show. Without this the shot is always the rest pose, and a
	# walk cycle that never ran would look exactly like a walk cycle that did.
	var clip := AnimationState.CLIP_NAMES.find(clip_name)
	if clip < 0:
		push_error("unit_shot: no clip '%s' — have %s"
			% [clip_name, str(AnimationState.CLIP_NAMES)])
		get_tree().quit(1)
		return
	unit.set_clip_data(0, clip, 3.2)
	print("unit_shot: clip '%s'" % clip_name)

	_shoot()


func _shoot() -> void:
	# Let the VAT advance off its rest frame before capturing, the same reason
	# gen-model-preview takes a `--seconds`.
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(seconds * 1000.0):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	if burst > 0:
		# A BURST of consecutive frames, for judging MOTION. A tracking eye
		# follows a marching squad, so a stabilised view of the cycle — which
		# with no ground in frame is simply the model in place — is exactly
		# what a player perceives of the animation itself. A single still
		# cannot answer "does this read as walking"; a strip of them can.
		var base := out_path.trim_suffix(".png")
		for i in range(burst):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			var path := ProjectSettings.globalize_path("%s-%03d.png" % [base, i])
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			img.save_png(path)
		print("unit_shot: wrote %d burst frames to %s-NNN.png" % [burst, base])
		get_tree().quit(0)
		return

	var image: Image = get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	image.save_png(absolute)
	print("unit_shot: wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	get_tree().quit(0)

extends Node3D

## Renders a melee between two real squads with the Tier 1 duel pass
## applied, and screenshots it. Run by `just gen-duel-preview`.
##
## This exists for the same reason every gen-*-preview does: the feature
## is a PICTURE. Every assertion in `tests/test_cosmetic_duel.gd` is
## about indices, distances and boundaries; none of them can see two
## squads politely swinging at the air a stride apart, which is exactly
## what Tier 1 replaces. And no existing instrument can frame a fight:
## `test-client` points its camera at a spawn, and a spawn is the one
## place a melee is not.
##
## Everything visual goes through the REAL path — `Formation.slot_offset`
## for the lines, `CosmeticDuel.opponents/engage/strike_decorate` exactly
## as client.gd calls them, `PrimitiveUnit` with authored models and the
## ATTACK clip. A preview that posed its own melee would prove nothing
## about what the game draws.
##
## Software-rasterised: answers "is the picture right", never "how fast".
## The µs number it prints is a same-host relative figure for the duel
## arithmetic only, quoted with its squad sizes per the standing rule.

const PATCH_WIDTH := 32
const PATCH_HEIGHT := 24
const SQUAD_SIZE := 24
const LINE_SEPARATION := 2.6
const TIMING_ROUNDS := 200

@export var seconds: float = 0.6
@export var out_path: String = "res://artifacts/duel-godot.png"

var _space: TorusSpace
var _terrain: TerrainGen
var _surface: PackedFloat32Array
var _centre: Vector3
var _elapsed := 0.0
var _shot := false


func _ready() -> void:
	_parse_arguments()
	_build_terrain()
	_build_environment()
	_build_melee()


func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text.begins_with("--seconds="):
			seconds = float(text.trim_prefix("--seconds="))
		elif text.begins_with("--out="):
			out_path = text.trim_prefix("--out=")


func _build_terrain() -> void:
	_space = TorusSpace.new(PATCH_WIDTH, PATCH_HEIGHT)
	_terrain = TerrainGen.new()
	var fields := _terrain.build_fields(_space)
	_surface = fields.surface
	_centre = _space.to_world(_flattest_cell())

	var material := TerrainChunk.make_material()
	var grid := TerrainChunk.chunk_grid(_space, 16)
	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := TerrainChunk.build_mesh(_space, _terrain, Vector2i(cx, cy),
				16, fields)
			if mesh == null:
				continue
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			instance.material_override = material
			add_child(instance)


## The flattest patch of dry land — same rule and same reason as
## cover_preview: a fixed focus on height_scale-15 terrain frames a
## hillside as readily as a meadow, and this shot is of the MEN.
func _flattest_cell() -> Vector2i:
	var best := Vector2i.ZERO
	var best_relief := INF
	const FOCUS_RADIUS := 6.0
	var middle := _space.to_world(Vector2i(PATCH_WIDTH / 2, PATCH_HEIGHT / 2))
	for i in range(_space.cell_count()):
		var coord := _space.from_index(i)
		var here := _space.to_world(coord)
		if Vector2(here.x - middle.x, here.z - middle.z).length() > FOCUS_RADIUS:
			continue
		if _terrain.is_water(_space, coord):
			continue
		var low := _surface[i * TerrainGen.SURFACE_STRIDE]
		var high := low
		for dir in range(6):
			var h := _surface[_space.neighbor_index(i, dir) * TerrainGen.SURFACE_STRIDE]
			low = minf(low, h)
			high = maxf(high, h)
		if high - low < best_relief:
			best_relief = high - low
			best = coord
	return best


func _build_environment() -> void:
	var camera := Camera3D.new()
	# Low and oblique, looking down the seam where the two lines meet —
	# a melee is invisible from the strategy camera's height and obvious
	# at eye level, the same lesson as forest_preview's lattice.
	var focus := _centre
	focus.y = _ground(focus.x, focus.z)
	# Nearly down the CONTACT SEAM (the lines run along x and meet near
	# z=0), so the frame shows two distinct bodies of men with a fight
	# between them — the diagonal first framing read as one clump.
	camera.position = focus + Vector3(11.0, 3.6, 2.6)
	add_child(camera)
	camera.look_at(focus + Vector3(0.0, 0.9, 0.0))
	camera.fov = 55.0
	camera.make_current()

	add_child(WorldLook.make_sun(true))
	var world := WorldEnvironment.new()
	world.environment = WorldLook.make_environment(true)
	add_child(world)


func _ground(x: float, z: float) -> float:
	return TerrainChunk.height_at(_space, _surface, x, z)


## Two authored infantry lines, facing each other a stride apart, with
## the duel pass applied exactly as client.gd applies it per frame.
func _build_melee() -> void:
	# Two authored MELEE archetypes, NOT named ones: unit ids are
	# civ-prefixed (D-047) and no .gd may name a civ. The second is the
	# first fighter from a DIFFERENT civ than the first (a field
	# comparison, which names nothing) — the first version took the same
	# civ's first two entries and the picture was one red blob fighting
	# itself.
	var defs: Array = []
	for candidate in UnitRoster.load_all():
		if candidate.model_id == &"" or candidate.damage <= 0.0 \
				or candidate.armour_class == "missile":
			continue
		if defs.is_empty():
			defs.append(candidate)
		elif candidate.civ != defs[0].civ:
			defs.append(candidate)
			break
	if defs.size() < 2:
		push_error("duel_preview: needs two authored melee archetypes")
		get_tree().quit(1)
		return

	var centre_a := _centre + Vector3(0.0, 0.0, -LINE_SEPARATION / 2.0)
	var centre_b := _centre + Vector3(0.0, 0.0, LINE_SEPARATION / 2.0)
	# A faces +z (angle 0), B faces -z (angle PI) — formation-local
	# forward is +z, as in Formation.soldier_transform.
	var line_a := _line_transforms(centre_a, 0.0)
	var line_b := _line_transforms(centre_b, PI)

	# THE REAL PATH: pair, engage, strike — the same three calls, in the
	# same order, against the other side's authoritative positions, that
	# client.gd makes per frame. Easing is skipped only because a first
	# frame eases from the target itself.
	var paired_a := CosmeticDuel.opponents(line_a, line_b)
	var paired_b := CosmeticDuel.opponents(line_b, line_a)
	var sampler := Callable(self, "_ground")
	var engaged_a := CosmeticDuel.engage(line_a, line_b, paired_a, sampler)
	var engaged_b := CosmeticDuel.engage(line_b, line_a, paired_b, sampler)
	var strike_time := 1.5 / 5.5
	var drawn_a := CosmeticDuel.strike_decorate(
		engaged_a, line_b, paired_a, strike_time, 0.0)
	var drawn_b := CosmeticDuel.strike_decorate(
		engaged_b, line_a, paired_b, strike_time, 0.0)

	_spawn_squad(defs[0], 0, drawn_a)
	_spawn_squad(defs[1], 1, drawn_b)
	_lay_corpses(defs)
	# Gaps are measured DRAWN man to DRAWN man — both sides step, and the
	# first version measured against the enemy's authoritative slots,
	# reporting "swinging at the air" about men the picture showed nose
	# to nose.
	_report(line_a, engaged_a, engaged_b, paired_a)
	_time_the_duel(line_a, line_b)


## The fallen (D-20260819-a-casualty-is-visible), through the REAL corpse
## path — CorpseLayer, its ledger, its shader. Each side has lost men in
## earlier rounds: their bodies lie in and behind the contact seam, most
## long settled, one per side still mid-fall so the picture shows the tip
## as well as the rest. Fog is deliberately unbound (the prop_fog
## bargain: a renderer with no player draws the world fully lit).
func _lay_corpses(defs: Array) -> void:
	var layer := CorpseLayer.new()
	add_child(layer)
	layer.set_offsets([Vector3.ZERO] as Array[Vector3])

	for side in range(2):
		var def: UnitDef = defs[side]
		var angle := 0.0 if side == 0 else PI
		var forward := Vector3(sin(angle), 0.0, cos(angle))
		var centre: Vector3 = _centre \
			+ Vector3(0.0, 0.0, -LINE_SEPARATION / 2.0 if side == 0 else LINE_SEPARATION / 2.0)
		# The dead of earlier rounds: slots the restamp vacated, derived
		# exactly as the living were, then pushed into the seam and toward
		# the CAMERA side of it — the first framing laid them faithfully
		# under the standing crowd, and eleven of twelve bodies were
		# invisible, which makes a poor instrument for "the corpse is
		# still there a minute later". Yaw varies per body: men do not
		# fall on parade.
		var fallen := _line_transforms(centre, angle)
		for i in range(6):
			var slot := (i * 7 + side * 3) % fallen.size()
			var xform: Transform3D = fallen[slot]
			xform.origin += forward * (0.6 + 0.5 * float(i % 3))
			xform.origin.x += 1.0 + 0.85 * float(i)
			xform.origin.y = _ground(xform.origin.x, xform.origin.z)
			xform.basis = Basis(Vector3.UP, angle + float(i * (side + 2)) * 0.9)
			# One per side mid-fall (phase ~0.5); the rest settled long ago.
			var age := CorpseLedger.FALL_SECONDS * (0.5 if i == 0 else 30.0)
			layer.spawn(def.model_id, side, xform, -age, Vector2.ZERO,
				PlayerColours.of_index(side))
	layer.update(0.0)
	print("duel_preview: %d corpses laid, %d skipped"
		% [layer.corpses_drawn, layer.corpses_skipped])


func _line_transforms(centre: Vector3, angle: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var basis := Basis(Vector3.UP, angle)
	for slot in range(SQUAD_SIZE):
		var local := Formation.slot_offset("line", slot, SQUAD_SIZE, 1.0)
		var offset := Vector3(local.x, 0.0, local.y).rotated(Vector3.UP, angle)
		var origin := centre + offset
		origin.y = _ground(origin.x, origin.z)
		out.append(Transform3D(basis, origin))
	return out


func _spawn_squad(def: UnitDef, colour_index: int,
		transforms: Array[Transform3D]) -> void:
	var unit := PrimitiveUnit.new()
	add_child(unit)
	unit.rebuild(def, PlayerColours.of_index(colour_index))
	# Transforms are already world space; the node stays at the origin,
	# exactly as client.gd keeps canonical transforms in the MultiMesh.
	unit.set_slot_transforms(transforms)
	unit.set_clip_data(colour_index, AnimationState.CLIP_ATTACK, 0.0)


## The numbers the recipe gates on. They cannot say the picture is right —
## that is what the PNG is for — but they can say whether a duel HAPPENED,
## which is the failure mode that would otherwise screenshot two squads
## standing in ranks and call it a melee.
func _report(before: Array[Transform3D], after: Array[Transform3D],
		enemy: Array[Transform3D], paired: PackedInt32Array) -> void:
	var moved := 0
	var in_contact := 0
	var gap_sum := 0.0
	for i in range(before.size()):
		if before[i].origin.distance_to(after[i].origin) > 0.05:
			moved += 1
		var opponent: Vector3 = enemy[paired[i]].origin
		var gap := Vector2(opponent.x - after[i].origin.x,
			opponent.z - after[i].origin.z).length()
		gap_sum += gap
		if gap <= CosmeticDuel.CONTACT_GAP + 0.1:
			in_contact += 1
	print("duel_preview: %d men, %d moved, %d in contact, mean gap %.2f"
		% [before.size(), moved, in_contact, gap_sum / before.size()])
	print("duel_preview: renderer=%s adapter=%s"
		% [ProjectSettings.get_setting("rendering/renderer/rendering_method"),
			RenderingServer.get_video_adapter_name()])


## Same-host cost of the duel arithmetic for one fighting squad pair per
## frame, quoted with its squad sizes (the standing rule). Relative
## figure only — software renderer, whatever host happens to run it.
func _time_the_duel(line_a: Array[Transform3D],
		line_b: Array[Transform3D]) -> void:
	var sampler := Callable(self, "_ground")
	var started := Time.get_ticks_usec()
	for _round in range(TIMING_ROUNDS):
		var paired := CosmeticDuel.opponents(line_a, line_b)
		var engaged := CosmeticDuel.engage(line_a, line_b, paired, sampler)
		CosmeticDuel.strike_decorate(engaged, line_b, paired, 0.3, 0.0)
	var usec := float(Time.get_ticks_usec() - started) / float(TIMING_ROUNDS)
	print("duel_preview: duel pass %.1f us per squad per frame at %dv%d"
		% [usec, line_a.size(), line_b.size()])


func _process(delta: float) -> void:
	_elapsed += delta
	if _shot or _elapsed < seconds:
		return
	_shot = true

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	# `res://` cannot be written in an exported build (#201,
	# D-20260828-artifacts-are-written-where-the-build-can-write); the
	# identity in a checkout, so the recipe's own --out= still lands
	# exactly where the justfile looks for it.
	out_path = ArtifactPath.resolve(out_path)
	var absolute := ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var err := image.save_png(absolute)
	if err != OK:
		push_error("duel_preview: could not write %s (%d)" % [absolute, err])
		get_tree().quit(1)
		return
	print("duel_preview: wrote %s (%dx%d)"
		% [out_path, image.get_width(), image.get_height()])
	get_tree().quit(0)

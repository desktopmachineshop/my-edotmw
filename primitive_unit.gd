extends Node3D
class_name PrimitiveUnit

## Tier-1 mesh generation (D-011): capsule/box/cylinder placeholder
## meshes composed from UnitDef data, zero art dependency.
##
## Renders a whole squad as one MultiMeshInstance3D (D-009) — never one
## Node per soldier. Soldier slot transforms are expected to come from a
## formation function (D-019) driven by the squad's curve (D-006), not
## from per-soldier simulation state; this script only owns the mesh/
## MultiMesh setup, not movement.

@export var unit_def: UnitDef

var _multimesh_instance: MultiMeshInstance3D

## Whether this squad is wearing an authored model (D-064) rather than a
## primitive. Decides which material path applies and whether the MultiMesh
## carries the per-soldier animation data D-065 needs.
var _authored := false
var _model_id: StringName = &""
var _owner_colour := Color(0, 0, 0, 0)

## The last animation state written into custom data. Custom data is rewritten
## on CHANGE, not per frame: D-045 measured the client frame at 97% CPU in
## per-soldier derivation, and this is that same loop. Phase advances in the
## shader from TIME, so a squad walking at a steady speed writes nothing.
var _last_clip := -1
var _last_rate := -1.0

## How many times the per-soldier animation buffer has actually been rewritten.
##
## Exists to be TESTABLE. Under `--headless` Godot uses a dummy rendering
## server, and MultiMesh per-instance buffers do not round-trip through it at
## all — `get_instance_custom_data` returns zeros, and so does
## `get_instance_transform`. So a test cannot read back what was written and
## must count the writes instead.
##
## Counting is the better check anyway: what D-045 cares about is that a squad
## walking at a steady speed rewrites NOTHING, and an absence of work is
## exactly what a read-back cannot show.
var custom_data_writes := 0


func _ready() -> void:
	if unit_def:
		rebuild(unit_def)


## Builds (or rebuilds) the MultiMesh for this squad from its UnitDef.
## Call again if unit_def changes or squad_size changes mid-match
## (reinforcement/attrition).
## `owner_colour` identifies WHOSE squad this is (D-052). Colour used to
## come from `UnitDef.mesh_color`, which described the unit TYPE — so
## every spearman on the map was the same grey whoever owned him. The
## first thing a player needs to read off a battle is whose units those
## are; the roster is the second, and shape still carries it.
func rebuild(def: UnitDef, owner_colour := Color(0, 0, 0, 0)) -> void:
	unit_def = def

	if _multimesh_instance == null:
		_multimesh_instance = MultiMeshInstance3D.new()
		add_child(_multimesh_instance)

	_owner_colour = owner_colour
	_model_id = def.model_id
	_last_clip = -1
	_last_rate = -1.0
	custom_data_writes = 0

	# Authored model first, primitive as the fallback (D-064). A missing
	# `generated/` degrades to the capsule rather than failing, which is what
	# keeps the bots, the tests and an unbuilt fresh clone running.
	var mesh: Mesh = null
	if _model_id != &"":
		mesh = UnitMesh.mesh_for(_model_id)
	_authored = mesh != null
	if not _authored:
		mesh = _build_primitive_mesh(def)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# Per-soldier clip, phase and rate (D-065). Declared before instance_count,
	# because changing the format after allocation discards the buffer.
	mm.use_custom_data = _authored
	mm.mesh = mesh
	mm.instance_count = def.squad_size

	_multimesh_instance.multimesh = mm
	_apply_material(def)


## Attach the right material for the current model and owner.
##
## Split out of `rebuild` because the two render paths answer it differently:
## an authored model gets a whole ShaderMaterial built around its VAT, a
## primitive a StandardMaterial3D, and the caller should not have to know
## which one a squad is using.
func _apply_material(def: UnitDef) -> void:
	if _authored:
		var colour := _owner_colour
		if colour.a <= 0.0:
			colour = def.mesh_color
		var material := UnitMesh.material_for(_model_id, colour)
		if material != null:
			_multimesh_instance.material_override = material
			return
		# The mesh loaded but its VAT did not. Fall through rather than render
		# an un-materialled model.
		push_warning("PrimitiveUnit: no VAT for '%s'; falling back" % _model_id)
		_authored = false

	var standard := StandardMaterial3D.new()
	# The unit's own colour survives as a tint on the player's, so two
	# unit types are still distinguishable within one army without
	# muddying whose army it is.
	if _owner_colour.a <= 0.0:
		standard.albedo_color = def.mesh_color
	else:
		standard.albedo_color = _owner_colour.lerp(def.mesh_color, 0.25)
	# Opaque, always. There used to be a fog-ghost branch here fading a
	# concealed squad; D-099 draws one not at all, so a squad this file
	# renders is a squad someone can see.
	_multimesh_instance.material_override = standard


## Per-soldier animation state (D-065).
##
## `clip` comes from `AnimationState.clip_for`, `speed` from the squad's curve.
## Writes only when the state actually changed: at a steady walk this costs one
## comparison per squad per frame and nothing else.
func set_clip_data(squad_id: int, clip: int, speed: float) -> void:
	if not _authored or _multimesh_instance == null:
		return
	var mm := _multimesh_instance.multimesh
	if mm == null or not mm.use_custom_data:
		return

	var rate := AnimationState.rate_for(clip, speed)
	# A rate that drifts by a fraction of a percent is not worth rewriting the
	# buffer for; a squad accelerating out of a stand is.
	if clip == _last_clip and absf(rate - _last_rate) < maxf(_last_rate, 0.01) * 0.05:
		return
	_last_clip = clip
	_last_rate = rate
	custom_data_writes += 1

	for i in range(mm.instance_count):
		mm.set_instance_custom_data(
			i, AnimationState.custom_data(squad_id, i, clip, speed))


## Sets per-soldier slot transforms. Caller (formation/curve code, not
## yet implemented — see D-006/D-019) is responsible for computing
## `transforms` from the squad curve + formation shape; this function
## just pushes them into the MultiMesh.
func set_slot_transforms(transforms: Array[Transform3D]) -> void:
	if _multimesh_instance == null or _multimesh_instance.multimesh == null:
		push_error("PrimitiveUnit.set_slot_transforms called before rebuild()")
		return

	var mm := _multimesh_instance.multimesh
	var count: int = mini(transforms.size(), mm.instance_count)
	for i in range(count):
		mm.set_instance_transform(i, transforms[i])

	# Draw only the slots that were actually written this frame.
	#
	# Without this the MultiMesh keeps drawing all `instance_count`
	# instances, and the ones past `count` render at whatever transform
	# they last held. A squad that lost half its soldiers therefore went
	# on displaying them, frozen, for the rest of the match — casualties
	# were literally invisible, because `alive` falls and the formation
	# restamps the survivors (D-006 clause 3) while the dead stayed put.
	#
	# It is also what makes render LOD possible at all (D-045): drawing
	# fewer soldiers than the squad has is exactly writing fewer
	# transforms than `instance_count`.
	mm.visible_instance_count = count


func _build_primitive_mesh(def: UnitDef) -> Mesh:
	match def.mesh_primitive:
		"capsule":
			var m := CapsuleMesh.new()
			m.radius = 0.3
			m.height = 1.8
			return m
		"box":
			var m := BoxMesh.new()
			m.size = Vector3(0.5, 1.8, 0.3)
			return m
		"cylinder":
			var m := CylinderMesh.new()
			m.top_radius = 0.3
			m.bottom_radius = 0.3
			m.height = 1.8
			return m
		"hull":
			var m := BoxMesh.new()
			m.size = Vector3(1.5, 0.6, 3.0)
			return m
		_:
			push_error("Unknown mesh_primitive '%s' on UnitDef '%s'" % [def.mesh_primitive, def.id])
			return CapsuleMesh.new()

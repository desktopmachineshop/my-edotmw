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

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _build_primitive_mesh(def)
	mm.instance_count = def.squad_size

	_multimesh_instance.multimesh = mm

	var material := StandardMaterial3D.new()
	# The unit's own colour survives as a tint on the player's, so two
	# unit types are still distinguishable within one army without
	# muddying whose army it is.
	if owner_colour.a <= 0.0:
		material.albedo_color = def.mesh_color
	else:
		material.albedo_color = owner_colour.lerp(def.mesh_color, 0.25)
	_multimesh_instance.material_override = material


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

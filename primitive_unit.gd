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
func rebuild(def: UnitDef) -> void:
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
	material.albedo_color = def.mesh_color
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

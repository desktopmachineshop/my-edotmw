extends SceneTree

## Splits the hand-authored resource-marker source asset (D-028's food/wood/
## gold/stone nodes) into one standalone .glb per resource kind.
##
## ## Why this lives outside the art/ Python pipeline
##
## Every other model in `generated/models` is parametric — built from
## `art/**/*.py` driving `bpy` (D-081) — and `art/build.py`'s manifest hash
## covers exactly those sources. This asset is hand-authored (exported from
## a third-party tool, per the "Exported by three-d-stage" comment in the
## source .mtl), which CLAUDE.md carves out as an explicit exception: a
## forced binary/GUI-only step, flagged rather than folded into the
## parametric pipeline it doesn't belong in.
##
## It still needs no Blender/bpy at all — the source is already a glTF
## binary, and Godot's own GLTFDocument can both read and write that format,
## so this runs on the project's existing headless Godot image with nothing
## extra installed.
##
## ## What "split" means here
##
## The source scene lays its four resource types out side by side for
## preview purposes (`tree_food`, `tree_wood`, `gold_ore`, `stone_pile`, each
## a Node3D with its own X offset so they don't overlap on screen), and each
## one is itself many separate parts (a tree is a trunk, root flare, branches,
## several canopy blobs and a scatter of apples). Splitting takes each
## group's parts, folds their local transforms into the vertex data (so the
## side-by-side layout offset and every part's own position/rotation both
## disappear into baked geometry) and merges them into ONE mesh per resource
## kind, with one surface per distinct material.
##
## That merge matters beyond tidiness: `UnitMesh.mesh_for()` — the loader
## this feeds, shared with units and buildings (D-064) — takes the FIRST
## MeshInstance3D it finds under a model's scene root and returns its `.mesh`.
## Left as 8-18 separate MeshInstance3Ds per kind, only the trunk would ever
## load; everything else would silently vanish. A single merged mesh is also
## one MeshInstance3D per resource node on the map instead of up to 18 —
## D-028 shipped 467 nodes on the slice-1 map, so that is the difference
## between ~467 draw calls and several thousand.
##
## Re-run with: godot --headless --path . --script res://art/resources/split_markers.gd
## (see `just build-resource-models`).

const SRC := "res://art/resources/source/resource-markers.glb"
const OUT_DIR := "res://generated/models"

## Source group name -> output model_id. model_id is what UnitMesh.mesh_for()
## takes, so these names ARE the filenames under generated/models/.
const GROUPS := {
	"tree_food": "resource_food",
	"tree_wood": "resource_wood",
	"gold_ore": "resource_gold",
	"stone_pile": "resource_stone",
}


func _initialize() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(SRC, state)
	if err != OK:
		push_error("split_markers: could not read %s (error %d)" % [SRC, err])
		quit(1)
		return

	var scene := doc.generate_scene(state)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var ok := true
	for group_name in GROUPS:
		var model_id: String = GROUPS[group_name]
		var group := scene.find_child(group_name, true, false)
		if group == null or not (group is Node3D):
			push_error("split_markers: no group node named '%s' in the source" % group_name)
			ok = false
			continue

		var merged := _merge(group as Node3D)
		if merged == null:
			push_error("split_markers: %s has no mesh parts" % group_name)
			ok = false
			continue

		var instance := MeshInstance3D.new()
		instance.name = model_id
		instance.mesh = merged

		var out_doc := GLTFDocument.new()
		var out_state := GLTFState.new()
		var append_err := out_doc.append_from_scene(instance, out_state)
		if append_err != OK:
			push_error("split_markers: append_from_scene failed for %s (error %d)"
				% [model_id, append_err])
			ok = false
			instance.queue_free()
			continue

		var out_path := "%s/%s.glb" % [OUT_DIR, model_id]
		var write_err := out_doc.write_to_filesystem(out_state, out_path)
		if write_err != OK:
			push_error("split_markers: write_to_filesystem failed for %s (error %d)"
				% [model_id, write_err])
			ok = false
		else:
			var tris := 0
			for si in range(merged.get_surface_count()):
				tris += _tri_count(merged, si)
			print("  %-14s %d surfaces  %4d tris  -> %s"
				% [model_id, merged.get_surface_count(), tris, out_path])

		instance.queue_free()

	quit(0 if ok else 1)


## Bakes every part's local transform into its vertex data and merges parts
## sharing a material into one surface, so the exported model is one mesh
## with a handful of surfaces rather than a dozen-plus separate objects.
##
## Grouped by MATERIAL rather than one surface per part: the source shares one
## Material resource per named .mtl entry across every part that used it
## (confirmed by dumping the imported scene — every "bark" part carries the
## identical albedo, i.e. the same Resource, not merely the same colour), so
## keying a Dictionary on the material object itself deduplicates for free.
func _merge(group: Node3D) -> ArrayMesh:
	var tools_by_material := {}
	var material_order: Array = []

	for child in group.get_children():
		if not (child is MeshInstance3D) or child.mesh == null:
			continue
		var mesh: Mesh = child.mesh
		for si in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(si)
			if not tools_by_material.has(mat):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools_by_material[mat] = tool
				material_order.append(mat)
			# append_from bakes `child.transform` into the appended
			# positions/normals, which is exactly the per-part placement
			# (trunk at the base, canopy blobs offset and rotated outward,
			# apples scattered) that must survive the merge.
			tools_by_material[mat].append_from(mesh, si, child.transform)

	if material_order.is_empty():
		return null

	var merged := ArrayMesh.new()
	for mat in material_order:
		var tool: SurfaceTool = tools_by_material[mat]
		tool.index()
		var surface_mesh := tool.commit()
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			surface_mesh.surface_get_arrays(0))
		merged.surface_set_material(merged.get_surface_count() - 1, mat)
	return merged


func _tri_count(mesh: Mesh, surface: int) -> int:
	var arrays := mesh.surface_get_arrays(surface)
	var indices = arrays[Mesh.ARRAY_INDEX]
	if indices != null:
		return indices.size() / 3
	var verts = arrays[Mesh.ARRAY_VERTEX]
	return verts.size() / 3

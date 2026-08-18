extends RefCounted
class_name LatticeCopies

## One thing in the world, drawn at EVERY lattice copy of the torus the
## camera can see (D-20260818-entities-are-drawn-at-every-visible-copy).
##
## ## The bug class this exists to delete
##
## Terrain has been drawn nine times since D-035, and every squad,
## building, wall and forest chunk exactly ONCE — repositioned each frame
## to whichever copy some rule picked. That asymmetry is the single most
## repeated defect in this project's history, and it always wears a
## different face: armies vanishing at the seam, half the screen
## rendering no units, a click landing exactly on a soldier and selecting
## nothing, a block of forest snapping a whole map period sideways. Each
## was fixed by improving the CHOICE. There is no correct choice — a view
## can genuinely contain two copies of the same ground, and one node
## cannot be in two places.
##
## So nothing chooses any more. The caller asks
## `RenderCull.visible_offsets_of_extent` which copies are on screen and
## hands the whole list here.
##
## ## Why it is cheap
##
## A mirror shares the SOURCE's drawable resource — the same `MultiMesh`,
## the same `Mesh`, the same `material_override`. Per-soldier derivation
## is ~96% of this client's frame at scale (D-045) and it happens once,
## into a resource every copy reads; a mirror is a transform and a
## reference. Godot frustum-culls the off-screen ones at the
## RenderingServer level, which is already what makes 1,287 terrain mesh
## instances affordable.
##
## Mirrors are created LAZILY, so a squad standing well inside the map —
## which is nearly all of them — costs exactly what it did before.
##
## ## Siblings, not children
##
## A mirror is added to the source's PARENT, never to the source. A
## building carries its own rotation and its construction progress as
## scale, and a child's local offset would be turned and squashed by
## both. The mirror copies the source's basis and differs only in
## position, which is exactly what a lattice offset is.


## Pose `source` and its mirrors at every offset in `offsets`, growing the
## caller's `mirrors` pool as needed. An empty `offsets` means NO copy of
## this thing is on screen, and it is drawn nowhere.
##
## `base` is the CANONICAL world position — the one the simulation means.
## Offsets are added to it here, so no caller ever holds a wrapped
## position and no caller can bake one in (which is how a missile came to
## be frozen to the copy it was fired at).
static func draw(source: Node3D, mirrors: Array[Node3D], base: Vector3,
		offsets: Array[Vector3]) -> void:
	source.visible = not offsets.is_empty()
	if offsets.is_empty():
		for mirror in mirrors:
			mirror.visible = false
		return

	source.position = base + offsets[0]
	var wanted := offsets.size() - 1
	while mirrors.size() < wanted:
		var extra := clone(source)
		source.get_parent().add_child(extra)
		mirrors.append(extra)
	for i in range(mirrors.size()):
		var mirror := mirrors[i]
		mirror.visible = i < wanted
		if i < wanted:
			# The source's own basis — rotation AND scale, which is how a
			# building's construction progress reaches its copies — with
			# only the position differing.
			mirror.transform = Transform3D(source.basis, base + offsets[i + 1])


## Re-point every mirror at what the source draws NOW.
##
## Called when the source's drawable changes rather than every frame: a
## `material_override` is a shared resource reference, so recolouring one
## recolours every copy for free, and only swapping the resource itself
## (a rebuilt MultiMesh, a model that finally loaded) needs this.
static func resync(source: Node3D, mirrors: Array[Node3D]) -> void:
	for mirror in mirrors:
		_adopt(mirror, source)


## A bare node of the same kind as `source`, sharing its drawable.
##
## Deliberately not `Node.duplicate()`: that copies the script, the
## metadata and the whole subtree by rules that differ per property, and
## what is wanted here is precisely a thin second view of one resource.
static func clone(source: Node3D) -> Node3D:
	var out: Node3D
	if source is MultiMeshInstance3D:
		out = MultiMeshInstance3D.new()
	elif source is MeshInstance3D:
		out = MeshInstance3D.new()
	else:
		out = Node3D.new()
	_adopt(out, source)
	return out


## Point one node at everything `source` draws, recursing into a COMPOSITE
## — a forest chunk is a Node3D of one MultiMesh per tree species, and a
## wall junction a Node3D of a bastion and its stair treads.
static func _adopt(copy: Node3D, source: Node3D) -> void:
	if copy is MultiMeshInstance3D and source is MultiMeshInstance3D:
		(copy as MultiMeshInstance3D).multimesh = \
			(source as MultiMeshInstance3D).multimesh
	elif copy is MeshInstance3D and source is MeshInstance3D:
		(copy as MeshInstance3D).mesh = (source as MeshInstance3D).mesh
	if copy is GeometryInstance3D and source is GeometryInstance3D:
		(copy as GeometryInstance3D).material_override = \
			(source as GeometryInstance3D).material_override

	# Surplus children first, so the index-by-index pass below can assume
	# the two subtrees are the same length.
	while copy.get_child_count() > source.get_child_count():
		var surplus := copy.get_child(copy.get_child_count() - 1)
		copy.remove_child(surplus)
		surplus.free()
	for i in range(source.get_child_count()):
		var child := source.get_child(i) as Node3D
		if child == null:
			continue
		var twin: Node3D = null
		if i < copy.get_child_count():
			twin = copy.get_child(i) as Node3D
		if twin == null or twin.get_class() != child.get_class():
			if twin != null:
				copy.remove_child(twin)
				twin.free()
			twin = clone(child)
			copy.add_child(twin)
			copy.move_child(twin, i)
		else:
			_adopt(twin, child)
		twin.transform = child.transform
		twin.visible = child.visible

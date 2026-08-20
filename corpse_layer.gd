extends Node3D
class_name CorpseLayer

## Draws the fallen (D-20260819-a-casualty-is-visible). The render half of
## `CorpseLedger` — every decision (the cap, eviction, phases) is made
## there and tested headless; this node only replays the ledger's ops into
## MultiMeshes, because a headless MultiMesh stores nothing and code here
## is therefore only ever checked by looking at a picture.
##
## One MultiMesh per (model, owner): the material carries the owner's
## colour (D-052) and the model's VAT, so neither can be per-instance.
## The whole layer is mirrored at every visible lattice copy
## (D-20260818-entities-are-drawn-at-every-visible-copy) — corpses
## accumulate over the whole map, so the layer tiles the way terrain does
## rather than per-squad.
##
## ## Two fall modes, decided by the manifest
##
## A bake that carries a "death" clip animates the fall in the VAT: the
## transform never changes and the per-instance phase float sweeps 0 -> 1.
## A bake that does not (today's — see the decision's host-policy note)
## keeps the pose frozen and TIPS the transform instead, hinging at the
## feet, the same visual language as the felled trees. Either way the
## phase is `CorpseLedger.fall_phase` — derived from the event time, never
## accumulated — and a settled corpse costs zero writes per frame.

## Sink into the ground at full phase, in world units. Reads as a body
## settling rather than a plank on the grass.
const SETTLE_SINK := 0.05

var _ledger := CorpseLedger.new()
# bucket key -> {"instance": MultiMeshInstance3D, "mirrors": Array[Node3D],
#   "capacity": int, "vat_fall": bool}
var _buckets := {}
var _fog: Texture2D = null
var _offsets: Array[Vector3] = [Vector3.ZERO]

## Drawn / skipped-for-want-of-a-model, for the capture verdicts.
var corpses_drawn: int = 0
var corpses_skipped: int = 0


## The torus copies the layer draws at. The caller hands the same list the
## terrain tiles with; every bucket follows it.
func set_offsets(offsets: Array[Vector3]) -> void:
	_offsets = offsets
	for key in _buckets:
		var bucket: Dictionary = _buckets[key]
		LatticeCopies.draw(bucket["instance"], bucket["mirrors"],
			Vector3.ZERO, _offsets)


## The fog field, once the client has one. Bound to every material made
## before and after this call — a corpse laid before the first bake would
## otherwise stay fully lit forever.
func set_fog(fog: Texture2D) -> void:
	_fog = fog
	for key in _buckets:
		var instance: MultiMeshInstance3D = _buckets[key]["instance"]
		var material := instance.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("fog", fog)


## Lay one man down where he fell. `xform` is his derived transform at the
## moment the casualty event was applied; `colour` is his owner's (D-052,
## resolved by the caller through ClientState.colour_of).
func spawn(model: StringName, owner: int, xform: Transform3D, time: float,
		fog_uv: Vector2, colour: Color) -> void:
	if model == &"" or UnitMesh.mesh_for(model) == null:
		# The primitive tier has no VAT to pose a corpse from; missing art
		# costs the body, never the game (D-081).
		corpses_skipped += 1
		return
	var ops := _ledger.add(model, owner, xform, time, fog_uv)
	corpses_drawn += 1
	for op in ops:
		_apply(op, colour, time)


## Animate the falls still playing. Zero work when nothing fell lately.
func update(now: float) -> void:
	for record in _ledger.falling(now):
		var bucket: Dictionary = _buckets.get(String(record["bucket"]), {})
		if bucket.is_empty():
			continue
		var mm: MultiMesh = (bucket["instance"] as MultiMeshInstance3D).multimesh
		var index := int(record["index"])
		if index >= mm.visible_instance_count:
			continue
		var phase := CorpseLedger.fall_phase(record, now)
		if bool(bucket["vat_fall"]):
			mm.set_instance_custom_data(index, _custom_for(record, phase))
		else:
			mm.set_instance_transform(index, _tipped(record, phase))


func clear() -> void:
	_ledger = CorpseLedger.new()
	for key in _buckets:
		var bucket: Dictionary = _buckets[key]
		(bucket["instance"] as Node3D).queue_free()
		for mirror in bucket["mirrors"]:
			(mirror as Node3D).queue_free()
	_buckets = {}
	corpses_drawn = 0
	corpses_skipped = 0


func count() -> int:
	return _ledger.count()


func _apply(op: Dictionary, colour: Color, now: float) -> void:
	var key := String(op["bucket"])
	var bucket := _bucket_for(key, colour, op)
	if bucket.is_empty():
		return
	var mm: MultiMesh = (bucket["instance"] as MultiMeshInstance3D).multimesh
	match String(op["op"]):
		"set":
			var index := int(op["index"])
			if index >= int(bucket["capacity"]):
				_grow(key, bucket, index + 1, now)
				mm = (bucket["instance"] as MultiMeshInstance3D).multimesh
			mm.visible_instance_count = maxi(mm.visible_instance_count, index + 1)
			_write(mm, index, op["record"], bool(bucket["vat_fall"]), now)
		"shrink":
			mm.visible_instance_count = int(op["count"])


func _bucket_for(key: String, colour: Color, op: Dictionary) -> Dictionary:
	if _buckets.has(key):
		return _buckets[key]
	# A shrink for a bucket never built cannot happen (the ledger only
	# evicts from buckets it appended to), so only "set" creates one.
	var record: Dictionary = op.get("record", {})
	if record.is_empty():
		return {}
	var model := StringName(record["model"])
	var material := UnitMesh.corpse_material_for(model, colour, _fog)
	var mesh := UnitMesh.mesh_for(model)
	if material == null or mesh == null:
		return {}

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 16
	mm.visible_instance_count = 0

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mm
	instance.material_override = material
	add_child(instance)

	var bucket := {
		"instance": instance, "mirrors": [] as Array[Node3D],
		"capacity": 16, "vat_fall": UnitMesh.has_death_clip(model),
	}
	_buckets[key] = bucket
	LatticeCopies.draw(instance, bucket["mirrors"], Vector3.ZERO, _offsets)
	return bucket


## Grow a bucket's MultiMesh. Setting instance_count WIPES a MultiMesh, so
## everything the ledger holds for the bucket is rewritten — rare (doubling
## amortises) and bounded by the ledger's cap. The mirrors share the same
## MultiMesh resource, so they follow without being touched.
func _grow(key: String, bucket: Dictionary, needed: int, now: float) -> void:
	var capacity := int(bucket["capacity"])
	while capacity < needed:
		capacity *= 2
	var mm: MultiMesh = (bucket["instance"] as MultiMeshInstance3D).multimesh
	mm.instance_count = capacity
	bucket["capacity"] = capacity
	var records := _ledger.bucket_records(key)
	mm.visible_instance_count = records.size()
	for record in records:
		_write(mm, int(record["index"]), record, bool(bucket["vat_fall"]), now)


func _write(mm: MultiMesh, index: int, record: Dictionary,
		vat_fall: bool, now: float) -> void:
	# Written at its CURRENT phase, not zero: an eviction can move a
	# long-settled record into a vacated slot, and re-playing its fall
	# there would read as a body twitching back to life. A record still
	# mid-fall keeps animating — `update()` follows the index the ledger
	# moved it to.
	var phase := CorpseLedger.fall_phase(record, now)
	if vat_fall:
		mm.set_instance_transform(index, record["xform"])
		mm.set_instance_custom_data(index, _custom_for(record, phase))
	else:
		mm.set_instance_transform(index, _tipped(record, phase))
		mm.set_instance_custom_data(index, _custom_for(record, phase))


func _custom_for(record: Dictionary, phase: float) -> Color:
	var uv: Vector2 = record["fog_uv"]
	var flagged := 1.0 if _fog != null else 0.0
	return Color(phase, uv.x, uv.y, flagged)


## The tip-over fall: hinge at the feet about the man's own right axis,
## sinking slightly as he settles. Same language as the felled trees, and
## retired per model the moment its bake ships a death clip.
static func _tipped(record: Dictionary, phase: float) -> Transform3D:
	var base: Transform3D = record["xform"]
	var eased := phase * phase * (3.0 - 2.0 * phase)
	var tipped := Transform3D(
		base.basis * Basis(Vector3.RIGHT, -eased * PI / 2.0), base.origin)
	tipped.origin.y -= SETTLE_SINK * eased
	return tipped

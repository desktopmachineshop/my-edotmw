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

## The extra views of this squad's ONE MultiMesh, one per lattice copy of
## the torus beyond the first that the camera can see
## (D-20260818-entities-are-drawn-at-every-visible-copy). Empty for a squad
## standing well inside the map, which is nearly all of them.
var _mirrors: Array[Node3D] = []

## Where this squad is DRAWN this frame — every visible lattice offset, in
## the order `RenderCull.visible_offsets_of_extent` returned them, so the
## first is the canonical copy whenever the canonical copy is on screen.
##
## Public because SELECTION has to read it. A click ranks candidates by
## screen distance, and with several copies on screen there is no single
## `node.position` to project — the node is in more than one place, which
## is the entire point. Reading it from the thing that drew it is what
## keeps the pick and the picture from drifting, the same reason
## `_squad_footprint` reached for `node.position` in the first place.
var lattice_offsets: Array[Vector3] = []

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
var _clip_guard_reported := 0
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
	# Every copy reads the SAME MultiMesh and the SAME material, so a
	# rebuild has to be re-pointed at them rather than repeated.
	LatticeCopies.resync(_multimesh_instance, _mirrors)


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
## `man_speeds`, when given, sets each soldier's WALK CADENCE from his own
## drawn ground speed rather than the squad's (D-20260824): a man creeping
## the last inch into his slot strides slowly, a man jogging to catch a
## re-fronted formation strides fast, and the squad speed is only the
## fallback for anyone the render layer has no measurement for. Writes
## stay change-driven per man (>7%), and a rate change re-anchors the
## man's PHASE so his feet do not pop to a different point in the cycle —
## phase is fract(offset + TIME*rate), so the offset absorbs the switch.
func set_clip_data(squad_id: int, clip: int, speed: float,
		man_speeds: PackedFloat32Array = PackedFloat32Array()) -> void:
	if not _authored or _multimesh_instance == null:
		if _clip_guard_reported == 0:
			# Once, not per frame: this return is why a squad can march with
			# its model in the rest pose — no custom data means the shader
			# derives phase from zeros. Silent for a whole diagnosis session.
			_clip_guard_reported = 1
			print("client: CLIP-GUARD squad=%d model=%s authored=%s no-mmi=%s" % [
				squad_id, _model_id, _authored, _multimesh_instance == null])
		return
	var mm := _multimesh_instance.multimesh
	if mm == null or not mm.use_custom_data:
		if _clip_guard_reported == 0:
			_clip_guard_reported = 1
			print("client: CLIP-GUARD squad=%d no-mm=%s custom=%s" % [
				squad_id, mm == null, mm != null and mm.use_custom_data])
		return

	var rate := AnimationState.rate_for(clip, speed)
	# Which BLOCK of this model's VAT that clip lives in. Only the gatherer
	# bakes the work clips, so every other model resolves `chop` to its
	# `attack` rather than sampling a row that holds normals — see
	# `UnitMesh.clip_index`, which is where that would go silently wrong.
	var row := UnitMesh.clip_index(_model_id, clip)
	if man_speeds.size() > 0 and AnimationState.is_work_clip(clip):
		# A man starts his first stroke when HE settles at the node, not when
		# the squad's centre stopped — see `_write_work_phases`.
		_write_work_phases(squad_id, clip, row, man_speeds)
		return
	var per_man := man_speeds.size() > 0 		and (clip == AnimationState.CLIP_WALK or clip == AnimationState.CLIP_ROUT)
	if per_man:
		_write_per_man_rates(squad_id, clip, man_speeds)
		return
	# A rate that drifts by a fraction of a percent is not worth rewriting the
	# buffer for; a squad accelerating out of a stand is.
	if clip == _last_clip and absf(rate - _last_rate) < maxf(_last_rate, 0.01) * 0.05:
		return
	_last_clip = clip
	_last_rate = rate
	_man_rates = PackedFloat32Array()
	custom_data_writes += 1
	# Diagnosis print (issue: walk reads as frozen during a steady march).
	# Writes happen on CHANGE only, so this is a handful of lines per squad
	# per order, not spam. What it separates: "the renderer was never told
	# to walk" (no walk line during a march) from "it was told and the
	# picture still froze" (walk line present) — the same
	# instrument-the-live-run move D-038's ownership bug needed.
	print("client: CLIP squad=%d %s rate=%.2f speed=%.2f row=%d" % [
		squad_id, AnimationState.CLIP_NAMES[clip], rate, speed, row])

	for i in range(mm.instance_count):
		mm.set_instance_custom_data(
			i, AnimationState.custom_data(squad_id, i, clip, speed, row))


## Per-man cadence, change-driven per man. `_man_offsets` carries each
## man's running phase offset: rewriting a rate without re-anchoring the
## offset jumps `fract(offset + TIME*rate)` to an unrelated point in the
## stride, which reads as a foot POP on every speed change — with per-man
## rates changing often, a permanent shuffle. Ticks time approximates the
## shader's TIME closely enough here because both clocks start with the
## engine, and the residual scales with the rate DELTA, which the 7%
## threshold keeps small.
var _man_rates := PackedFloat32Array()
var _man_offsets := PackedFloat32Array()


func _write_per_man_rates(squad_id: int, clip: int,
		man_speeds: PackedFloat32Array) -> void:
	var mm := _multimesh_instance.multimesh
	var count := mini(mm.instance_count, man_speeds.size())
	var now := Time.get_ticks_msec() / 1000.0
	var resized := _man_rates.size() != mm.instance_count
	if resized:
		_man_rates = PackedFloat32Array()
		_man_rates.resize(mm.instance_count)
		_man_offsets = PackedFloat32Array()
		_man_offsets.resize(mm.instance_count)
		for i in range(mm.instance_count):
			_man_rates[i] = -1.0
			_man_offsets[i] = AnimationState.phase_offset(squad_id, i)
	var clip_changed := clip != _last_clip
	var row := UnitMesh.clip_index(_model_id, clip)
	_last_clip = clip
	_last_rate = -1.0
	for i in range(count):
		var rate := AnimationState.rate_for(clip, man_speeds[i])
		var old_rate := _man_rates[i]
		if not clip_changed and old_rate > 0.0 				and absf(rate - old_rate) < maxf(old_rate, 0.01) * 0.07:
			continue
		if old_rate > 0.0:
			# Keep fract(offset + now*rate) continuous across the switch.
			_man_offsets[i] = fposmod(
				_man_offsets[i] + now * (old_rate - rate), 1.0)
		_man_rates[i] = rate
		custom_data_writes += 1
		mm.set_instance_custom_data(i,
			Color(float(row), _man_offsets[i], rate, 0.0))


## Below this drawn speed a man counts as having ARRIVED and settled into
## his slot. A hair above zero rather than zero: the render layer eases men
## toward their slots exponentially, so a soldier approaches his without ever
## formally reaching it, and a test for exact rest would never fire.
const SETTLE_SPEED := 0.08

## Which men have started working, so an arrival is latched once rather than
## re-latched every frame. Cleared whenever the clip leaves the work family.
var _man_working := PackedByteArray()
## When the first and last man of this crew started, for the diagnostic below.
var _work_first := -1.0
var _work_last := -1.0


## Per-man work phase, anchored on ARRIVAL.
##
## ## Why arrival rather than a hash
##
## `phase = fract(offset + TIME * rate)` is keyed to the global clock, so a
## crew that has just settled is already somewhere in the middle of a stroke:
## a man can be caught with his axe buried in the tree the instant he stops
## walking. Anchoring the cycle to the moment he starts working makes the
## first thing he does the wind-up, which is what it should be.
##
## And it is ARRIVAL, not the squad stopping. Those are different moments: the
## squad's curve goes quiet when its CENTRE reaches the node, while its men are
## still easing into a ring around it for a measured 0.272 s afterwards.
## Keying every man to the squad's stop would put them all on the same beat
## again, which is the thing being fixed.
##
## This file never asks for that easing itself — `man_speeds` arrives as a
## plain array from `client.gd`, which is the only place allowed to hold the
## render layer's per-soldier motion. `tests/test_tier_three.gd` enforces
## that by grepping for the class name, so do not name it here even in a
## comment: the whole point of that guard is that a grep finds every toucher.
##
## ## Why this is allowed
##
## `_man_offsets` is already per-soldier render state, and has been since
## D-20260824 gave each man his own stride. D-006 clause 2 as amended by
## D-20260819-tier-three-lives-on-the-render-side permits exactly this:
## bounded, one-way and outcome-blind. Nothing simulation-side reads it, two
## clients may legitimately disagree about where in his swing a man is, and no
## outcome depends on the answer — the same freedom `CosmeticOffset` has.
##
## The per-man RATE spread stays on top of it (`AnimationState.man_rate`).
## Arrival decides where each man starts; the rate spread is what stops a crew
## that happened to arrive together from staying in step forever.
func _write_work_phases(squad_id: int, clip: int, row: int,
		man_speeds: PackedFloat32Array) -> void:
	var mm := _multimesh_instance.multimesh
	var count := mini(mm.instance_count, man_speeds.size())
	var now := Time.get_ticks_msec() / 1000.0

	if clip != _last_clip:
		# The same diagnosis line the other two write paths emit. Without it a
		# work clip is the one thing in this file that changes silently, and
		# "the renderer was never told to chop" and "it was told and the
		# picture still froze" are the two cases this print exists to
		# separate (see `set_clip_data`).
		print("client: CLIP squad=%d %s rate=%.2f row=%d (per-man, on arrival)"
			% [squad_id, AnimationState.CLIP_NAMES[clip],
				AnimationState.rate_for(clip, 0.0), row])

	if _man_working.size() != mm.instance_count or clip != _last_clip:
		_man_working = PackedByteArray()
		_man_working.resize(mm.instance_count)
		_man_rates = PackedFloat32Array()
		_man_rates.resize(mm.instance_count)
		_man_offsets = PackedFloat32Array()
		_man_offsets.resize(mm.instance_count)
		for i in range(mm.instance_count):
			_man_rates[i] = -1.0
		_work_first = -1.0
		_work_last = -1.0
	_last_clip = clip
	_last_rate = -1.0

	for i in range(count):
		if _man_working[i] != 0:
			continue
		if man_speeds[i] > SETTLE_SPEED:
			# Still walking in. HOLD him at the start of the wind-up, with the
			# tool at rest, until he actually arrives.
			#
			# Held by writing rate ZERO rather than by re-anchoring his offset
			# every frame: `phase = fract(offset + TIME * rate)` freezes on its
			# own when the rate is nothing, so this is one write per man
			# instead of one per man per frame on the client's hottest loop
			# (D-041 measured the frame at 97% CPU in derivation). The same
			# rate-zero idiom D-20260819 already uses to hold a falling man's
			# pose.
			if _man_rates[i] != 0.0:
				_man_rates[i] = 0.0
				_man_offsets[i] = 0.0
				custom_data_writes += 1
				mm.set_instance_custom_data(i, Color(float(row), 0.0, 0.0, 0.0))
			continue

		# Arrived. Anchor his cycle so that fract(offset + t * rate) is 0 at
		# t = now — the first thing he does is the wind-up — and let it run.
		var rate := AnimationState.man_rate(squad_id, i, clip, 0.0)
		var offset := fposmod(-now * rate, 1.0)
		_man_offsets[i] = offset
		_man_rates[i] = rate
		_man_working[i] = 1
		custom_data_writes += 1
		mm.set_instance_custom_data(i, Color(float(row), offset, rate, 0.0))
		if _work_first < 0.0:
			_work_first = now
		_work_last = now
		if _worked_count() == count:
			# The number the design question turns on: how far apart a crew
			# actually arrives. Printed once per crew per stint, because a
			# guess about it is what the hash was standing in for.
			print("client: WORK squad=%d %s — %d men settled over %.2fs"
				% [squad_id, AnimationState.CLIP_NAMES[clip], count,
					_work_last - _work_first])


func _worked_count() -> int:
	var n := 0
	for byte in _man_working:
		if byte != 0:
			n += 1
	return n


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


## Draw this squad at EVERY lattice copy of the torus the camera can see,
## or nowhere at all when the list is empty
## (D-20260818-entities-are-drawn-at-every-visible-copy).
##
## Costs one thin `MultiMeshInstance3D` per extra copy, sharing this
## squad's single MultiMesh and its single material. Nothing is derived
## twice: `set_slot_transforms` wrote canonical world-space transforms
## once, and per-soldier derivation is ~96% of the client's frame at scale
## (D-045), so a second view of that buffer is a transform and a
## reference. Godot culls the off-screen ones at the RenderingServer
## level, which is what already makes 1,287 terrain mesh instances
## affordable.
##
## The mirrors are children of THIS node, which never moves — the soldier
## transforms are canonical world space, so a copy is a pure translation
## and nothing here has a rotation or a scale for a child offset to be
## bent by.
func set_lattice_offsets(offsets: Array[Vector3]) -> void:
	lattice_offsets = offsets
	if _multimesh_instance == null:
		return
	visible = not offsets.is_empty()
	LatticeCopies.draw(_multimesh_instance, _mirrors, Vector3.ZERO, offsets)


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

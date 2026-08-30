extends Node3D
class_name PrimitiveUnit

## Tier-1 mesh generation (D-011): capsule/box/cylinder placeholder
## meshes composed from UnitDef data, zero art dependency.
##
## Renders a whole squad as MultiMeshInstance3D buckets (D-009) — never one
## Node per soldier. Soldier slot transforms are expected to come from a
## formation function (D-019) driven by the squad's curve (D-006), not
## from per-soldier simulation state; this script only owns the mesh/
## MultiMesh setup, not movement.
##
## ## A squad may wear MORE THAN ONE model
## (D-20260826-a-squad-wears-more-than-one-model)
##
## A hero squad is one general and a retinue with mixed kit; a cannon crew
## is one gun carriage and its tenders. `UnitDef.slot_models` names the
## models of the leading slots and `UnitDef.model_mix` is dealt across the
## rest, so this file groups slots by model and draws one MultiMesh per
## distinct model — still a handful of draw calls per squad, never a node
## per soldier. Every group hangs off ONE `_body` node, which is what the
## lattice mirrors clone: `LatticeCopies` already recurses into composites
## (a forest chunk is exactly this shape), so a mixed squad wraps the seam
## the same way a uniform one does.
##
## Slots are routed by DRAWN index: the LOD sampler
## (`Formation.soldier_transforms_sampled`) picks `i * alive / n`, so drawn
## index 0 is always slot 0 and the leader survives every thinning tier.
## The remaining drawn indices deal the mix in drawn order — which mix
## entry a particular background dwarf wears at half detail is cosmetic,
## and no outcome reads it (D-006 clause 2).

@export var unit_def: UnitDef

## The hull primitive's box, in world units (x = beam, z = length).
## A CONSTANT rather than three literals in `_build_primitive_mesh`,
## because `formation_spacing` on every def drawn as a hull must clear
## this size or the squad's own hulls interpenetrate — which is exactly
## what shipped (playtest 2026-08-30, "the boats are appearing on top of
## each other"): every water def left spacing at the schema default of
## 1.0, a SOLDIER's shoulder spacing, against a 3.0-long hull.
## `tests/test_naval_separation.gd` reads this and asserts the
## relationship over the whole roster, so a bigger hull or a new hull
## def cannot silently reintroduce the overlap
## (D-20260830-a-ship-takes-up-its-own-water).
const HULL_SIZE := Vector3(1.5, 0.6, 3.0)

## The composite this squad draws: one MultiMeshInstance3D child per
## distinct model. Mirrors clone THIS node, so a rebuild that changes the
## group list only needs a resync.
var _body: Node3D

var _groups: Array[MultiMeshInstance3D] = []
var _group_models: Array[StringName] = []
var _group_authored: Array[bool] = []
## Drawn index -> (group, instance-within-group). Locals are assigned in
## drawn order, so however many soldiers are written this frame, each
## group's written instances are a PREFIX of its buffer — which is what
## `visible_instance_count` needs to be true.
var _index_group := PackedInt32Array()
var _index_local := PackedInt32Array()
var _total_instances := 0

## The extra views of this squad's body, one per lattice copy of
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


## Which model formation slot `i` of this squad wears.
##
## Static and pure so a test can ask it the same question the renderer
## answers, without a scene tree. The order is: the named leading slots,
## then the mix dealt round-robin, then `model_id` for everyone else —
## and both extra fields default empty, so the whole existing roster
## resolves to `model_id` exactly as before.
static func model_for_slot(def: UnitDef, i: int) -> StringName:
	if i < def.slot_models.size():
		return def.slot_models[i]
	if not def.model_mix.is_empty():
		return def.model_mix[(i - def.slot_models.size()) % def.model_mix.size()]
	return def.model_id


## Builds (or rebuilds) the model groups for this squad from its UnitDef.
## Call again if unit_def changes or squad_size changes mid-match
## (reinforcement/attrition).
## `owner_colour` identifies WHOSE squad this is (D-052). Colour used to
## come from `UnitDef.mesh_color`, which described the unit TYPE — so
## every spearman on the map was the same grey whoever owned him. The
## first thing a player needs to read off a battle is whose units those
## are; the roster is the second, and shape still carries it.
func rebuild(def: UnitDef, owner_colour := Color(0, 0, 0, 0)) -> void:
	unit_def = def

	if _body == null:
		_body = Node3D.new()
		add_child(_body)

	# Freed NOW, not queued: `LatticeCopies.resync` below copies the body's
	# CURRENT children, and a queue_free'd group is still a child until the
	# end of the frame — every mirror would adopt a mesh about to vanish.
	for group in _groups:
		_body.remove_child(group)
		group.free()
	_groups = []
	_group_models = []
	_group_authored = []

	_owner_colour = owner_colour
	_model_id = def.model_id
	_last_clip = -1
	_last_rate = -1.0
	custom_data_writes = 0
	_man_rates = PackedFloat32Array()
	_man_offsets = PackedFloat32Array()
	_man_working = PackedByteArray()

	# One group per distinct model, in first-appearance (= slot) order.
	_total_instances = maxi(def.squad_size, 1)
	_index_group.resize(_total_instances)
	_index_local.resize(_total_instances)
	var group_of_model := {}
	var counts: Array[int] = []
	for i in range(_total_instances):
		var model := model_for_slot(def, i)
		if not group_of_model.has(model):
			group_of_model[model] = _group_models.size()
			_group_models.append(model)
			counts.append(0)
		var g: int = group_of_model[model]
		_index_group[i] = g
		_index_local[i] = counts[g]
		counts[g] += 1

	for g in range(_group_models.size()):
		# Authored model first, primitive as the fallback (D-064). A missing
		# `generated/` degrades to the capsule rather than failing, which is
		# what keeps the bots, the tests and an unbuilt fresh clone running.
		var mesh: Mesh = null
		if _group_models[g] != &"":
			mesh = UnitMesh.mesh_for(_group_models[g])
		var authored := mesh != null
		if not authored:
			mesh = _build_primitive_mesh(def)
		_group_authored.append(authored)

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		# Per-soldier clip, phase and rate (D-065). Declared before
		# instance_count, because changing the format after allocation
		# discards the buffer.
		mm.use_custom_data = authored
		mm.mesh = mesh
		mm.instance_count = counts[g]

		var instance := MultiMeshInstance3D.new()
		instance.multimesh = mm
		_body.add_child(instance)
		_groups.append(instance)
		_apply_material(def, g)

	# Every copy reads the SAME MultiMeshes and the SAME materials, so a
	# rebuild has to be re-pointed at them rather than repeated.
	LatticeCopies.resync(_body, _mirrors)


## Attach the right material for one group's model and the owner.
##
## Split out of `rebuild` because the two render paths answer it differently:
## an authored model gets a whole ShaderMaterial built around its VAT, a
## primitive a StandardMaterial3D, and the caller should not have to know
## which one a group is using.
func _apply_material(def: UnitDef, g: int) -> void:
	if _group_authored[g]:
		var colour := _owner_colour
		if colour.a <= 0.0:
			colour = def.mesh_color
		var material := UnitMesh.material_for(_group_models[g], colour)
		if material != null:
			_groups[g].material_override = material
			return
		# The mesh loaded but its VAT did not. Fall through rather than render
		# an un-materialled model.
		push_warning("PrimitiveUnit: no VAT for '%s'; falling back"
			% _group_models[g])
		_group_authored[g] = false
		_groups[g].multimesh.use_custom_data = false

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
	_groups[g].material_override = standard


func _any_authored() -> bool:
	for authored in _group_authored:
		if authored:
			return true
	return false


## Route one soldier's custom data to the MultiMesh his slot's model lives
## in. Silently skips a primitive-fallback group — a capsule has no VAT to
## index, and its MultiMesh carries no custom data buffer at all.
func _write_custom(i: int, data: Color) -> void:
	var g := _index_group[i]
	if not _group_authored[g]:
		return
	_groups[g].multimesh.set_instance_custom_data(_index_local[i], data)


## Which VAT row block each group plays for `clip` — resolved per MODEL,
## because a mixed squad's members do not share a clip table: the tenders'
## body bakes a walk, the gun carriage bakes nothing but its rest pose, and
## `UnitMesh.clip_index` is where "this model has no such clip" degrades
## safely instead of sampling a normals row.
func _rows_for(clip: int) -> PackedInt32Array:
	var rows := PackedInt32Array()
	rows.resize(_groups.size())
	for g in range(_groups.size()):
		rows[g] = UnitMesh.clip_index(_group_models[g], clip) \
			if _group_authored[g] else 0
	return rows


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
	if _groups.is_empty() or not _any_authored():
		if _clip_guard_reported == 0:
			# Once, not per frame: this return is why a squad can march with
			# its model in the rest pose — no custom data means the shader
			# derives phase from zeros. Silent for a whole diagnosis session.
			_clip_guard_reported = 1
			print("client: CLIP-GUARD squad=%d model=%s no-groups=%s" % [
				squad_id, _model_id, _groups.is_empty()])
		return

	var rate := AnimationState.rate_for(clip, speed)
	if man_speeds.size() > 0 and AnimationState.is_work_clip(clip):
		# A man starts his first stroke when HE settles at the node, not when
		# the squad's centre stopped — see `_write_work_phases`.
		_write_work_phases(squad_id, clip, man_speeds)
		return
	var per_man := man_speeds.size() > 0 \
		and (clip == AnimationState.CLIP_WALK or clip == AnimationState.CLIP_ROUT)
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
	var rows := _rows_for(clip)
	# Diagnosis print (issue: walk reads as frozen during a steady march).
	# Writes happen on CHANGE only, so this is a handful of lines per squad
	# per order, not spam. What it separates: "the renderer was never told
	# to walk" (no walk line during a march) from "it was told and the
	# picture still froze" (walk line present) — the same
	# instrument-the-live-run move D-038's ownership bug needed.
	print("client: CLIP squad=%d %s rate=%.2f speed=%.2f rows=%s" % [
		squad_id, AnimationState.CLIP_NAMES[clip], rate, speed, rows])

	for i in range(_total_instances):
		_write_custom(i, AnimationState.custom_data(
			squad_id, i, clip, speed, rows[_index_group[i]]))


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
	var count := mini(_total_instances, man_speeds.size())
	var now := Time.get_ticks_msec() / 1000.0
	var resized := _man_rates.size() != _total_instances
	if resized:
		_man_rates = PackedFloat32Array()
		_man_rates.resize(_total_instances)
		_man_offsets = PackedFloat32Array()
		_man_offsets.resize(_total_instances)
		for i in range(_total_instances):
			_man_rates[i] = -1.0
			_man_offsets[i] = AnimationState.phase_offset(squad_id, i)
	var clip_changed := clip != _last_clip
	var rows := _rows_for(clip)
	_last_clip = clip
	_last_rate = -1.0
	for i in range(count):
		var rate := AnimationState.rate_for(clip, man_speeds[i])
		var old_rate := _man_rates[i]
		if not clip_changed and old_rate > 0.0 \
			and absf(rate - old_rate) < maxf(old_rate, 0.01) * 0.07:
			continue
		if old_rate > 0.0:
			# Keep fract(offset + now*rate) continuous across the switch.
			_man_offsets[i] = fposmod(
				_man_offsets[i] + now * (old_rate - rate), 1.0)
		_man_rates[i] = rate
		custom_data_writes += 1
		_write_custom(i,
			Color(float(rows[_index_group[i]]), _man_offsets[i], rate, 0.0))


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
func _write_work_phases(squad_id: int, clip: int,
		man_speeds: PackedFloat32Array) -> void:
	var count := mini(_total_instances, man_speeds.size())
	var now := Time.get_ticks_msec() / 1000.0
	var rows := _rows_for(clip)

	if clip != _last_clip:
		# The same diagnosis line the other two write paths emit. Without it a
		# work clip is the one thing in this file that changes silently, and
		# "the renderer was never told to chop" and "it was told and the
		# picture still froze" are the two cases this print exists to
		# separate (see `set_clip_data`).
		print("client: CLIP squad=%d %s rate=%.2f rows=%s (per-man, on arrival)"
			% [squad_id, AnimationState.CLIP_NAMES[clip],
				AnimationState.rate_for(clip, 0.0), rows])

	if _man_working.size() != _total_instances or clip != _last_clip:
		_man_working = PackedByteArray()
		_man_working.resize(_total_instances)
		_man_rates = PackedFloat32Array()
		_man_rates.resize(_total_instances)
		_man_offsets = PackedFloat32Array()
		_man_offsets.resize(_total_instances)
		for i in range(_total_instances):
			_man_rates[i] = -1.0
		_work_first = -1.0
		_work_last = -1.0
	_last_clip = clip
	_last_rate = -1.0

	for i in range(count):
		if _man_working[i] != 0:
			continue
		var row := rows[_index_group[i]]
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
				_write_custom(i, Color(float(row), 0.0, 0.0, 0.0))
			continue

		# Arrived. Anchor his cycle so that fract(offset + t * rate) is 0 at
		# t = now — the first thing he does is the wind-up — and let it run.
		var rate := AnimationState.man_rate(squad_id, i, clip, 0.0)
		var offset := fposmod(-now * rate, 1.0)
		_man_offsets[i] = offset
		_man_rates[i] = rate
		_man_working[i] = 1
		custom_data_writes += 1
		_write_custom(i, Color(float(row), offset, rate, 0.0))
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


## Sets per-soldier slot transforms. Caller (formation/curve code) is
## responsible for computing `transforms` from the squad curve + formation
## shape; this function just routes them into each model group's MultiMesh.
func set_slot_transforms(transforms: Array[Transform3D]) -> void:
	if _groups.is_empty():
		push_error("PrimitiveUnit.set_slot_transforms called before rebuild()")
		return

	var count: int = mini(transforms.size(), _total_instances)
	var written := PackedInt32Array()
	written.resize(_groups.size())
	for i in range(count):
		var g := _index_group[i]
		_groups[g].multimesh.set_instance_transform(_index_local[i], transforms[i])
		written[g] += 1

	# Draw only the slots that were actually written this frame.
	#
	# Without this each MultiMesh keeps drawing all `instance_count`
	# instances, and the ones past `count` render at whatever transform
	# they last held. A squad that lost half its soldiers therefore went
	# on displaying them, frozen, for the rest of the match — casualties
	# were literally invisible, because `alive` falls and the formation
	# restamps the survivors (D-006 clause 3) while the dead stayed put.
	#
	# It is also what makes render LOD possible at all (D-045): drawing
	# fewer soldiers than the squad has is exactly writing fewer
	# transforms than `instance_count`. Per group the written instances
	# are a prefix of the buffer, because locals were dealt in drawn
	# order at rebuild — see `_index_local`.
	for g in range(_groups.size()):
		_groups[g].multimesh.visible_instance_count = written[g]


## Draw this squad at EVERY lattice copy of the torus the camera can see,
## or nowhere at all when the list is empty
## (D-20260818-entities-are-drawn-at-every-visible-copy).
##
## Costs one thin composite per extra copy, sharing this squad's
## MultiMeshes and materials. Nothing is derived twice: `set_slot_transforms`
## wrote canonical world-space transforms once, and per-soldier derivation
## is ~96% of the client's frame at scale (D-045), so a second view of
## those buffers is a transform and a few references. Godot culls the
## off-screen ones at the RenderingServer level, which is what already
## makes 1,287 terrain mesh instances affordable.
##
## The mirrors are children of THIS node, which never moves — the soldier
## transforms are canonical world space, so a copy is a pure translation
## and nothing here has a rotation or a scale for a child offset to be
## bent by.
func set_lattice_offsets(offsets: Array[Vector3]) -> void:
	lattice_offsets = offsets
	if _body == null:
		return
	visible = not offsets.is_empty()
	LatticeCopies.draw(_body, _mirrors, Vector3.ZERO, offsets)


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
			m.size = HULL_SIZE
			return m
		_:
			push_error("Unknown mesh_primitive '%s' on UnitDef '%s'" % [def.mesh_primitive, def.id])
			return CapsuleMesh.new()

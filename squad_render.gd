extends RefCounted
class_name SquadRender

## The per-squad RENDER pipeline: everything that happens to a squad's
## derived slots between `Formation` and the MultiMesh (#240).
##
## ## Why this is its own file
##
## It used to live inside `client.gd`'s `_refresh_squads`, and
## `bench_render.gd` — the only instrument this project has for "how fast
## does the client draw" — did not run any of it. Its own comment claimed
## it did ("exactly what client.gd's `_refresh_squads` does, minus the
## ghost pass"), and that stopped being true the moment the RTW battle
## programme landed: the duels, the corpse layer, the survivor easing, the
## cross-squad jostle and the building/tree push-outs are all per drawn
## man, all shipped, and none of them were measured. Every frame time this
## project has recorded since was a FLOOR for a client nobody was timing.
##
## That is M4's `just profile` lesson wearing render clothes — a harness
## reported ~29 ms while a live server spent 866 (D-043 criterion 11) —
## and the answer is the same one D-096 gives for terrain UVs and D-102
## gives for a player's colour: **one definition, called by both**. A
## benchmark cannot drift from a client whose code it is running.
##
## ## The shape
##
## All-static and pure over its inputs, the `formation.gd` family — with
## the deliberate exception of `motion`, a `SoldierMotion` the caller owns
## and passes in, because D-006's amended clause 2 puts the eased
## per-soldier positions THERE and nowhere else. Nothing here reads
## `ClientState`, a scene tree, a camera or a viewport: the caller gathers
## (what the squad is doing, which enemy men to pair against, which
## building boxes and tree discs are near, which foreign men to jostle
## against) and this decides where the drawn men end up.
##
## Everything it does is D-006 clause 2 render work — bounded, one-way,
## outcome-blind. Nothing computed here is ever read back by the
## simulation, and the authoritative transforms it is handed are never
## mutated.


## Below this speed a squad is standing still: it stops bobbing, its men
## may be jostled by neighbours, and it plays an idle clip rather than a
## walk. One definition, referenced by the client rather than copied into
## it — the constant lived in `client.gd` while the code that read it
## lived here.
const MOVING_SPEED_EPSILON := 0.15


## Run the pipeline for one squad.
##
## `params` (all optional unless noted):
##
##   transforms      Array[Transform3D] — the authoritative slots (required)
##   doing           Dictionary from the caller's activity resolver (required)
##   enemy_transforms Array[Transform3D] — the enemy squad's drawn men, for
##                   a melee. Empty for anything else.
##   deal            Dictionary — the caller's cached static-target deal
##                   {"key", "paired"}; returned updated.
##   offsets         Array[Vector3] — the torus lattice offsets
##   boxes, discs    Array — nearby building boxes and tree clearance discs
##   terrain_sampler Callable(x, z) -> float
##   motion          SoldierMotion (required for easing; omit and the men
##                   are drawn at their engaged positions)
##   squad_id        the key `motion` stores this squad under
##   delta, now      float — frame delta and the client's clock
##   speed           float — the squad's own speed, for footfall and clip
##   pursuit_speed   float — cap on how fast a drawn man chases his slot
##   neighbours      PackedVector3Array — foreign drawn men to jostle from
##   routed          bool — for the clip
##   model_id        StringName — for "does this model animate its own work"
##   surround_step   float — the wrap-a-static-target budget
##
## Returns {"transforms", "eased", "drawn_men", "clip", "deal", "dueling"}.
static func frame(params: Dictionary) -> Dictionary:
	var transforms: Array[Transform3D] = params.get("transforms", [] as Array[Transform3D])
	var doing: Dictionary = params.get("doing", {})
	var offsets: Array[Vector3] = params.get("offsets", [] as Array[Vector3])
	var now := float(params.get("now", 0.0))
	var speed := float(params.get("speed", 0.0))
	var terrain_sampler: Callable = params.get("terrain_sampler", Callable())
	var deal: Dictionary = params.get("deal", {})

	var enemy_transforms: Array[Transform3D] = params.get(
		"enemy_transforms", [] as Array[Transform3D])
	var paired := PackedInt32Array()
	var dueling: bool = int(doing.get("activity", CosmeticOffset.Activity.IDLE)) \
			== CosmeticOffset.Activity.FIGHTING \
		and not bool(doing.get("is_ranged", false)) \
		and int(doing.get("enemy_squad", -1)) >= 0
	if dueling:
		dueling = not enemy_transforms.is_empty()
	elif (doing.has("ring_centre") or doing.has("rect_centre")) \
			and not transforms.is_empty():
		# A STATIC target (D-20260820-men-gather-round-what-they-
		# strike): perimeter points stand in for the duel's defenders,
		# dealt ONE PER MAN so the squad wraps the target instead of
		# piling onto the near arc. A building is a BOX and gets its
		# rectangle (second amendment); a tree keeps the ring.
		var ring: Array[Transform3D]
		if doing.has("rect_centre"):
			ring = Engagement.rect_points(doing["rect_centre"],
				(doing["rect_half"] as Vector2)
					+ Vector2(Engagement.CONTACT_GAP, Engagement.CONTACT_GAP),
				float(doing["rect_yaw"]), transforms.size())
		else:
			ring = Engagement.ring_points(doing["ring_centre"],
				float(doing["ring_radius"]) + Engagement.CONTACT_GAP,
				transforms.size())
		# The deal HOLDS while the target and the strength hold
		# (D-20260821): recomputing it every frame hopped every man's mark
		# along the wall as his slot drifted.
		var deal_key: String = str(doing.get("target_key", "")) \
			+ "|" + str(transforms.size())
		if String(deal.get("key", "")) == deal_key:
			paired = deal["paired"]
		else:
			var ring_positions := PackedVector3Array()
			ring_positions.resize(ring.size())
			for i in range(ring.size()):
				ring_positions[i] = ring[i].origin
			paired = SoldierMotion.assign(ring_positions, transforms)
			deal = {"key": deal_key, "paired": paired}
		enemy_transforms = ring
		dueling = true

	if dueling and not transforms.is_empty():
		# The torus tax (Engagement's own note): an enemy engaged across
		# the seam derives a whole map away in canonical coordinates, and
		# unaligned the duel would pair every man with a phantom on the
		# far side of the world.
		enemy_transforms = Engagement.shifted(enemy_transforms,
			Engagement.aligning_offset(transforms[0].origin,
				enemy_transforms[0].origin, offsets))
		var surround := doing.has("rect_centre") or doing.has("ring_centre")
		if paired.is_empty():
			paired = CosmeticDuel.opponents(transforms, enemy_transforms)
		# A static target grants the SURROUND budget (D-20260820, third
		# amendment): a building does not hit back, so men may leave
		# formation properly to wrap it.
		transforms = CosmeticDuel.engage(
			transforms, enemy_transforms, paired, terrain_sampler,
			float(params.get("surround_step", Engagement.MAX_STEP)) if surround
				else Engagement.MAX_STEP)

	# No drawn man stands inside a building (D-20260820, third amendment):
	# slots clamp against terrain only, so a line's slots can land inside a
	# footprint — projected out to the nearest face here, BEFORE easing, so
	# men walk out rather than popping. Trees are obstacles for drawn men
	# too (D-20260821, amended): a marching line filters around a wood man
	# by man and the velocity clamp walks each one back to his slot beyond
	# it. A crew's OWN worked node is exempt — standing at the tree is the
	# job, and the caller leaves it out of `discs`.
	var boxes: Array = params.get("boxes", [])
	var discs: Array = params.get("discs", [])
	if not transforms.is_empty() and (not boxes.is_empty() or not discs.is_empty()):
		for i in range(transforms.size()):
			var pushed := transforms[i]
			for box in boxes:
				pushed.origin = Engagement.push_out_of_box(
					pushed.origin, box["centre"], box["half"], box["yaw"])
			for disc in discs:
				pushed.origin = Engagement.push_out_of_disc(
					pushed.origin, disc["centre"], disc["radius"])
			transforms[i] = pushed

	# Eased so soldiers walk to their slots when the squad turns instead of
	# the whole block snapping round (D-059), then decorated with sway,
	# footfall and whatever the squad is visibly doing.
	var motion: SoldierMotion = params.get("motion", null)
	var eased := transforms
	if motion != null:
		eased = motion.ease(params.get("squad_id", 0), transforms,
			float(params.get("delta", 0.0)),
			float(params.get("pursuit_speed", 0.0)),
			params.get("neighbours", PackedVector3Array()))

	var drawn_men := PackedVector3Array()
	drawn_men.resize(eased.size())
	for i in range(eased.size()):
		drawn_men[i] = eased[i].origin

	# A model that draws its own work stroke takes NO cosmetic lunge or
	# sway — see `CosmeticDuel.strike_decorate`. Only the WORKING case can
	# have one: a soldier's `attack` clip is a stroke at an enemy, not at
	# the tree he is standing on.
	var self_animated := int(doing.get("activity", CosmeticOffset.Activity.IDLE)) \
			== CosmeticOffset.Activity.WORKING \
		and UnitMesh.animates_work(params.get("model_id", &""))
	var swing := float(doing.get("swing", CosmeticOffset.SWING_AMPLITUDE))
	var decorated := CosmeticDuel.strike_decorate(
			eased, enemy_transforms, paired, now, speed,
			0.0 if self_animated else swing) if dueling \
		else CosmeticOffset.decorate_activity(
			eased, now, speed, int(doing.get("activity", CosmeticOffset.Activity.IDLE)),
			doing.get("toward", Vector3.ZERO), swing)

	# Which clip these soldiers play (D-065). Derived from state the client
	# already holds, so nothing is sent for it and every client agrees by
	# construction — the same shape as D-052's colour.
	var clip := AnimationState.clip_for(
		bool(params.get("routed", false)),
		int(doing.get("activity", CosmeticOffset.Activity.IDLE))
			== CosmeticOffset.Activity.FIGHTING,
		speed > float(params.get("moving_epsilon", MOVING_SPEED_EPSILON)),
		int(doing.get("working", AnimationState.NOT_WORKING)))

	return {
		"transforms": decorated,
		"eased": eased,
		"drawn_men": drawn_men,
		"clip": clip,
		"deal": deal,
		"dueling": dueling,
	}

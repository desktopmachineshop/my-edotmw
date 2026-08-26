extends GutTest

## Guards `D-20260825-a-gatherer-carries-the-tool-for-the-job`: a gatherer wears
## an axe and a pickaxe on its back, draws the right one for the node it is
## working, and uses neither for fruit.
##
## ## What is actually at risk here, and it is not the animation
##
## Two things, and both are this project's oldest defect family rather than
## anything about art.
##
## **The feature going silently absent.** Every mechanism can be correct while
## the gatherer's bake carries four clips — because `generated/` is committed
## and a `.blend` that nobody rebuilt draws yesterday's model with every number
## green (D-055's family; `civ-knobs.md` is the fourth instance and this would
## be the next). So the manifest is asked directly whether the clips exist,
## rather than the code being asked whether it would use them.
##
## **A model sampling a clip it never baked.** `unit_vat.gdshaderinc` finds a
## row at `clip * frames_per_clip + local`. That is arithmetic, not a lookup:
## asking a four-clip militia for clip 4 lands on the first NORMALS row and the
## model comes apart into a cloud, with nothing reporting anything anywhere.
## `UnitMesh.clip_index` is the whole defence, so it is checked across the
## SHIPPED roster and every clip in the numbering rather than on one example.
##
## The half that cannot be asserted is whether a chop looks like a chop.
## `just gen-model-preview` draws it and `docs/playtest/` holds the picture —
## the same split D-097's cliffs and D-108's forests already live under.

const MAX_VAT_WIDTH := 16384


func _models() -> Array[StringName]:
	var seen := {}
	var out: Array[StringName] = []
	for def in UnitRoster.load_all():
		if def.model_id == &"" or seen.has(def.model_id):
			continue
		seen[def.model_id] = true
		out.append(def.model_id)
	return out


func _clips_of(model_id: StringName) -> Array:
	return Array(UnitMesh.layout_for(model_id).get("clips", []))


# --- which tool the job calls for -------------------------------------

## The mapping the whole feature rests on. Stated once, in `AnimationState`,
## so the axe and the pickaxe cannot end up on opposite sides of it in two
## callers — which is how the minimap came to draw allies in the enemy tone
## for two milestones (D-20260817-minimap-squad-colours).
func test_each_resource_calls_for_its_own_tool() -> void:
	assert_eq(AnimationState.work_clip_for(Economy.ResourceKind.WOOD),
		AnimationState.CLIP_CHOP, "felling a tree wants the axe")
	assert_eq(AnimationState.work_clip_for(Economy.ResourceKind.STONE),
		AnimationState.CLIP_MINE, "cutting stone wants the pickaxe")
	assert_eq(AnimationState.work_clip_for(Economy.ResourceKind.GOLD),
		AnimationState.CLIP_MINE, "ore wants the pickaxe, same as stone")
	assert_eq(AnimationState.work_clip_for(Economy.ResourceKind.FOOD),
		AnimationState.CLIP_FORAGE, "fruit is picked by hand — no tool at all")


## Every kind the economy can hand over resolves to a real work clip. A new
## resource added to `ResourceKind` would otherwise fall through to whatever
## the `match` statement's default happened to be, and a crew would be seen
## working the new thing with the wrong tool — or with none.
func test_every_resource_kind_the_economy_has_maps_to_a_work_clip() -> void:
	var work := [AnimationState.CLIP_CHOP, AnimationState.CLIP_MINE,
		AnimationState.CLIP_FORAGE]
	for kind in range(Economy.RESOURCE_COUNT):
		assert_true(work.has(AnimationState.work_clip_for(kind)),
			"resource kind %d resolves to clip %d, which is not a work clip"
				% [kind, AnimationState.work_clip_for(kind)])


## `NOT_WORKING` must not collide with a resource kind. It is -1 rather than 0
## for exactly this reason: FOOD is 0, so a caller that passed a default of
## zero would put every idle squad in the game into `forage`.
func test_not_working_is_not_a_resource() -> void:
	assert_true(AnimationState.NOT_WORKING < 0,
		"NOT_WORKING must be outside ResourceKind, which counts from 0")
	for kind in range(Economy.RESOURCE_COUNT):
		assert_ne(AnimationState.NOT_WORKING, kind)


# --- when a work clip wins -------------------------------------------

func test_a_settled_crew_plays_its_work_clip() -> void:
	assert_eq(AnimationState.clip_for(false, false, false,
		Economy.ResourceKind.WOOD), AnimationState.CLIP_CHOP)


## A crew hauling a load is WALKING. Working outranks only idling, because a
## crew keeps its gathering shape for the whole round trip (D-058's replicated
## `shape` is what the client reads) — so a crew that worked while it walked
## would slide across the map swinging an axe at nothing.
func test_a_crew_on_the_move_walks_rather_than_works() -> void:
	assert_eq(AnimationState.clip_for(false, false, true,
		Economy.ResourceKind.WOOD), AnimationState.CLIP_WALK)


## Fighting and routing both outrank work, and rout outranks everything —
## D-063 criterion 7's rule, unchanged: a broken squad that still swings reads
## as a squad that is fine.
func test_violence_outranks_work() -> void:
	assert_eq(AnimationState.clip_for(false, true, false,
		Economy.ResourceKind.WOOD), AnimationState.CLIP_ATTACK)
	assert_eq(AnimationState.clip_for(true, false, false,
		Economy.ResourceKind.STONE), AnimationState.CLIP_ROUT)
	assert_eq(AnimationState.clip_for(true, true, true,
		Economy.ResourceKind.FOOD), AnimationState.CLIP_ROUT)


## Everyone who is not a gatherer passes NOT_WORKING and must be unaffected.
func test_the_default_leaves_every_other_squad_where_it_was() -> void:
	assert_eq(AnimationState.clip_for(false, false, false),
		AnimationState.CLIP_IDLE)
	assert_eq(AnimationState.clip_for(false, false, true),
		AnimationState.CLIP_WALK)


## Each work clip has its own cadence, and none of them is the idle rate.
## Gathering resolves as a rate per tick with no stroke in it, so there is no
## authoritative number to derive these from — which makes them exactly the
## kind of constant that gets left at a default and never noticed.
func test_the_work_clips_have_cadences_of_their_own() -> void:
	var rates := {}
	for clip in [AnimationState.CLIP_CHOP, AnimationState.CLIP_MINE,
			AnimationState.CLIP_FORAGE]:
		var rate := AnimationState.rate_for(clip, 0.0)
		assert_gt(rate, 0.0, "clip %d must play at some cadence" % clip)
		assert_ne(rate, AnimationState.IDLE_RATE,
			"clip %d fell through to the idle rate" % clip)
		rates[rate] = true
	assert_gt(rates.size(), 1,
		"a pick chipping twice a cycle and an axe taking one big stroke "
		+ "should not share a cadence")


# --- a crew is not a chorus line --------------------------------------

## A phase offset spreads a crew across the cycle; it does NOT stop them
## beating in unison, because every man then plays at the same RATE and the
## crew holds its spacing forever. Marching avoids that by giving each man the
## cadence of his own drawn ground speed (D-20260824). Work has no such
## measurement — gathering is a rate per tick with no stroke in it — so the
## variation is hashed instead.
func test_each_man_works_at_his_own_cadence() -> void:
	var rates := {}
	for slot in range(8):
		rates[AnimationState.man_rate(7, slot, AnimationState.CLIP_CHOP, 0.0)] = true
	assert_gt(rates.size(), 1,
		"every man in the crew chops at the same rate, so the squad keeps "
		+ "whatever spacing its phase offsets gave it and reads as "
		+ "choreography rather than as men working")


## Bounded, and bounded on BOTH sides. These are men doing one job beside
## each other: too little and they are a chorus line, too much and the
## slowest visibly lags the fastest inside a single cycle.
func test_that_cadence_stays_near_the_crews() -> void:
	for clip in [AnimationState.CLIP_CHOP, AnimationState.CLIP_MINE,
			AnimationState.CLIP_FORAGE]:
		var squad_rate := AnimationState.rate_for(clip, 0.0)
		for slot in range(24):
			var mine := AnimationState.man_rate(3, slot, clip, 0.0)
			assert_almost_eq(mine, squad_rate,
				squad_rate * AnimationState.WORK_RATE_SPREAD + 0.0001,
				"slot %d strays past the stated spread" % slot)


## Everyone else keeps the squad's rate exactly. The jitter is for work, and a
## marching rank that acquired it would undo D-20260824's per-man cadence with
## a hash of the slot number.
func test_only_the_work_clips_vary() -> void:
	for clip in [AnimationState.CLIP_IDLE, AnimationState.CLIP_WALK,
			AnimationState.CLIP_ATTACK, AnimationState.CLIP_ROUT]:
		for slot in range(6):
			assert_eq(AnimationState.man_rate(3, slot, clip, 2.0),
				AnimationState.rate_for(clip, 2.0),
				"clip %d must keep the squad's rate" % clip)


## Cadence and starting phase must not come from the same hash. If they did,
## the man who starts latest would also be the slowest, so the crew would fan
## out in one direction rather than scattering.
func test_cadence_and_phase_are_independent() -> void:
	var agree := 0
	for slot in range(32):
		var phase := AnimationState.phase_offset(11, slot)
		var rate := AnimationState.man_rate(11, slot, AnimationState.CLIP_CHOP, 0.0)
		var fast := rate > AnimationState.rate_for(AnimationState.CLIP_CHOP, 0.0)
		if (phase > 0.5) == fast:
			agree += 1
	assert_between(agree, 8, 24,
		"a man's cadence tracks his phase offset (%d of 32 agree), so the "
			% agree
		+ "crew fans out in one direction instead of scattering")


# --- when a man starts working ----------------------------------------

## Does a crew actually arrive at different moments? The whole case for
## anchoring each man's stroke on his own arrival rather than on a hash rests
## on this, and it is a measurement rather than an opinion — so it is taken
## here instead of guessed at.
##
## The squad's CURVE goes quiet when its centre reaches the node. Its men are
## still easing into a ring around it afterwards (`SoldierMotion`), and they
## have different distances to cover, so they settle at different moments.
## That spread is what `PrimitiveUnit._write_work_phases` keys the stroke to.
func test_a_crew_settles_over_a_spread_of_time_not_all_at_once() -> void:
	var motion := SoldierMotion.new()
	var slots: Array[Transform3D] = []
	var start: Array[Transform3D] = []
	# A ring of eight around a node, approached from one side — which is what
	# a crew walking up to a tree does.
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		slots.append(Transform3D(Basis(),
			Vector3(cos(angle) * 1.6, 0.0, sin(angle) * 1.6)))
		start.append(Transform3D(Basis(), Vector3(0.0, 0.0, -6.0)))

	# Settle them from the approach, stepping at a plausible frame time.
	motion.ease(1, start, 0.016)
	var settled := PackedFloat32Array()
	settled.resize(8)
	for i in range(8):
		settled[i] = -1.0
	var elapsed := 0.0
	for step in range(600):
		motion.ease(1, slots, 0.016)
		elapsed += 0.016
		var speeds := motion.speeds(1)
		if speeds.size() < 8:
			continue
		for i in range(8):
			if settled[i] < 0.0 and speeds[i] <= PrimitiveUnit.SETTLE_SPEED:
				settled[i] = elapsed

	var first := 1e9
	var last := -1.0
	for i in range(8):
		assert_gt(settled[i], 0.0, "slot %d never settled" % i)
		first = minf(first, settled[i])
		last = maxf(last, settled[i])
	var spread := last - first
	gut.p("crew settled over %.3fs (first %.3f, last %.3f)"
		% [spread, first, last])

	# A tenth of a second is the floor worth having: the shortest work cycle
	# here is `chop` at 0.62 cycles/second, so 0.1s is about 6% of a stroke —
	# below that, arrival is not telling the men apart and the per-man RATE
	# spread is doing all the work.
	assert_gt(spread, 0.1,
		"a crew settles within %.3fs, so arrival cannot separate their "
			% spread
		+ "strokes and `_write_work_phases` is anchoring them all to the same "
		+ "moment — the per-man rate spread would be carrying it alone")


## The anchor is a LATCH, not a per-frame recompute: a man who has started
## working keeps running his cycle rather than being re-pinned to the start of
## the wind-up on every frame, which would freeze him mid-pose forever.
func test_a_man_who_has_started_is_not_re_anchored() -> void:
	var source := FileAccess.get_file_as_string("res://primitive_unit.gd")
	assert_true(source.contains("if _man_working[i] != 0:"),
		"the arrival latch is gone from _write_work_phases; without it every "
		+ "frame re-pins each man to phase zero and nobody ever swings")


# --- the row a model actually samples ---------------------------------

## THE check. A clip index is a place in the numbering, not a promise that a
## model has that row, and the shader cannot tell the difference — see this
## file's header for what row 64 of a four-clip VAT actually holds.
func test_no_model_is_ever_asked_for_a_row_it_did_not_bake() -> void:
	var models := _models()
	if models.is_empty():
		pass_test("generated/ not built; nothing to resolve")
		return
	for model_id in models:
		var clips := _clips_of(model_id)
		assert_false(clips.is_empty(), "%s has no clip list" % model_id)
		for clip in range(AnimationState.CLIP_NAMES.size()):
			var row := UnitMesh.clip_index(model_id, clip)
			assert_between(row, 0, clips.size() - 1,
				"%s resolved clip %s to row %d of %d — the shader would read "
					% [model_id, AnimationState.CLIP_NAMES[clip], row, clips.size()]
				+ "position rows as normals and the model would come apart")


## A model that HAS the clip must get it, or the resolution is free to return
## anything and the test above would still pass.
func test_a_model_that_baked_the_clip_gets_that_clip() -> void:
	var models := _models()
	if models.is_empty():
		pass_test("generated/ not built")
		return
	for model_id in models:
		var clips := _clips_of(model_id)
		for clip in range(AnimationState.CLIP_NAMES.size()):
			var name := String(AnimationState.CLIP_NAMES[clip])
			if not clips.has(name):
				continue
			assert_eq(UnitMesh.clip_index(model_id, clip), clips.find(name),
				"%s baked '%s' and did not resolve to it" % [model_id, name])


## A model without the work clips degrades to a stroke it does have, rather
## than standing still. Nothing ships that needs this — only the gatherer ever
## asks — but a roster where a second unit gathers, or a `generated/` built
## before this change, both land here.
func test_a_model_without_the_work_clips_falls_back_to_something_it_has() -> void:
	var militia := StringName("militia")
	var clips := _clips_of(militia)
	if clips.is_empty() or clips.has("chop"):
		pass_test("militia is not the four-clip case this asserts")
		return
	assert_eq(UnitMesh.clip_index(militia, AnimationState.CLIP_CHOP),
		clips.find("attack"), "a swing degrades to the nearest swing")
	assert_eq(UnitMesh.clip_index(militia, AnimationState.CLIP_MINE),
		clips.find("attack"))
	assert_eq(UnitMesh.clip_index(militia, AnimationState.CLIP_FORAGE),
		clips.find("idle"), "forage has no tool in it and no stroke either")


# --- no placeholder motion on a model that animates itself -------------

## A working crew goes through the DUEL pipeline now
## (D-20260820-men-gather-round-what-they-strike): its men are dealt to
## perimeter points round the node and stepped into contact. That path applies
## `CosmeticOffset`'s lunge and sway — placeholders from before this model
## drew anything — at the FIGHTING rate of 5.5 Hz, against a chop cycle of
## 0.62. Nine beats a stroke, which is how a correct animation ends up looking
## broken; the owner's playtest called it "bobbing around, floating side to
## side".
##
## Passing zero turns the whole decoration off rather than merely shrinking
## it, because halving one placeholder and leaving the other is not a decision
## anybody made on purpose.
func test_a_self_animating_model_takes_no_cosmetic_lunge() -> void:
	var men: Array[Transform3D] = []
	var marks: Array[Transform3D] = []
	var paired := PackedInt32Array()
	for i in range(4):
		men.append(Transform3D(Basis(), Vector3(float(i) * 0.6, 0.0, 0.0)))
		marks.append(Transform3D(Basis(), Vector3(float(i) * 0.6, 0.0, 0.9)))
		paired.append(i)

	var still := CosmeticDuel.strike_decorate(men, marks, paired, 3.7, 0.0, 0.0)
	assert_eq(still.size(), men.size())
	for i in range(men.size()):
		assert_almost_eq(still[i].origin.distance_to(men[i].origin), 0.0,
			0.00001,
			"slot %d was moved by the placeholder decoration even though its "
				% i
			+ "model animates its own work")

	# And the guard is not vacuous: at the normal amplitude somebody moves.
	var swung := CosmeticDuel.strike_decorate(
		men, marks, paired, 3.7, 0.0, CosmeticOffset.SWING_AMPLITUDE)
	var moved := 0.0
	for i in range(men.size()):
		moved = maxf(moved, swung[i].origin.distance_to(men[i].origin))
	assert_gt(moved, 0.01,
		"nobody moved at full amplitude either, so the check above proves "
		+ "nothing about the gate")


# --- the hands close on the tool --------------------------------------

## The supplied rig ends at one bone per hand: no fingers, so the mitts are
## rigid and stay flat open beside whatever the soldier is holding. The grip
## is knuckle joints added by `art/attach_tools.py` and folded by
## `art/author_clips.py`.
##
## None of that is visible from Godot — bones do not survive into the VAT,
## which stores final vertex positions and has no opinion about how they were
## produced (D-082). So what is guarded here is that the BUILD-TIME checks
## still exist, which is this project's caller-exists idiom (D-106's
## `TerrainChunk.set_fog` scan) applied to an art step.
func test_the_rig_still_grows_finger_joints() -> void:
	var source := FileAccess.get_file_as_string("res://art/attach_tools.py")
	assert_true(source.contains("GRIP_BONES"),
		"attach_tools.py no longer adds finger joints, so the hands cannot "
		+ "close and every tool is held by an open mitt")
	assert_true(source.contains("_add_grip_bones"),
		"the finger joints are defined but nothing adds them — the "
		+ "declared-and-unread family, which this project has hit five times")


## And that the fold is CHECKED at build time, not merely applied. The first
## version of that check measured the nearest fingertip to the haft and was
## vacuous: with the grip sitting in the fist's hole an OPEN hand scored 0.0036
## against a closed one's 0.0040, so zeroing the curl left it green. It
## measures the fold ANGLE now, which an unfolded hand cannot pass.
func test_the_grip_is_asserted_at_build_time() -> void:
	var source := FileAccess.get_file_as_string("res://art/author_clips.py")
	assert_true(source.contains("MIN_FINGER_FOLD_DEGREES"),
		"nothing checks that the fists actually close; a hand left open beside "
		+ "the haft passes every other check in the build")
	assert_true(source.contains("_assert_hands_grip("),
		"the grip check exists but is never called")


# --- the bake itself --------------------------------------------------

## The feature is DATA. Every rule above can be perfect while the shipped
## gatherer carries four clips, and the only symptom would be a crew that
## looks the same at a tree as at a seam — which is what it looked like
## before any of this. So the manifest is asked outright.
func test_the_shipped_gatherer_bakes_the_work_clips() -> void:
	var gatherers := StringName("gatherers")
	var clips := _clips_of(gatherers)
	if clips.is_empty():
		pass_test("generated/ not built")
		return
	for name in ["chop", "mine", "forage"]:
		assert_true(clips.has(name),
			"the shipped gatherer does not bake '%s'. Run "
				% name
			+ "`just attach-tools` then `just author-clips gatherers` then "
			+ "`just build-assets` — until then the tools are on its back and "
			+ "it never draws them.")


## Every gatherer def in the roster resolves to the model that carries the
## tools. Both civs share one gatherer MODEL (archetype, never civ), so a civ
## whose def pointed at something else would silently lose the feature.
func test_every_civs_gatherer_uses_the_tooled_model() -> void:
	var found := 0
	for def in UnitRoster.load_all():
		if def.archetype != &"gatherers":
			continue
		found += 1
		if def.model_id == &"":
			continue
		var clips := _clips_of(def.model_id)
		if clips.is_empty():
			continue
		assert_true(clips.has("chop"),
			"%s draws model '%s', which has no work clips"
				% [def.id, def.model_id])
	assert_gt(found, 0, "Setup: the roster should field gatherers")


## The VAT's rows and its clip list have to describe the same texture. They
## come from different places — the frames from the `.blend`'s timeline, the
## list from `clips_for` — and a mismatch is how every lookup past the drift
## point lands on the wrong animation with nothing failing.
func test_the_baked_rows_and_the_clip_list_agree() -> void:
	var models := _models()
	if models.is_empty():
		pass_test("generated/ not built")
		return
	for model_id in models:
		var layout := UnitMesh.layout_for(model_id)
		var clips := Array(layout.get("clips", []))
		if clips.is_empty():
			continue
		assert_eq(int(layout.get("total_frames", 0)),
			clips.size() * int(layout.get("frames_per_clip", 16)),
			"%s: %d frames against %d clips" % [model_id,
				int(layout.get("total_frames", 0)), clips.size()])


## A model's triangle count is a TEXTURE WIDTH (one VAT column per flattened
## vertex), and 16,384 is the 2D limit every GPU this game targets shares.
## Over it, the texture is not created at all — so the squad does not render,
## on somebody else's machine, long after the build said fine. `art/build.py`
## refuses to write one; this is the same rule asserted against what shipped.
func test_no_models_vat_is_wider_than_a_texture_can_be() -> void:
	var models := _models()
	if models.is_empty():
		pass_test("generated/ not built")
		return
	for model_id in models:
		var width := int(UnitMesh.layout_for(model_id).get("width", 0))
		assert_between(width, 1, MAX_VAT_WIDTH,
			"%s's VAT is %d pixels wide, past the %d texture limit"
				% [model_id, width, MAX_VAT_WIDTH])

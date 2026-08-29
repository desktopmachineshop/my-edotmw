extends GutTest

## Guards `preview_framing.gd` — that a preview camera holds EVERYTHING
## the scene drew (#228).
##
## `model_preview.gd` has clipped its own picture four times, each time
## through a dimension the previous fix did not measure: a constant tuned
## for four clip columns, a building roster that grew from four to nine,
## the gatherer's three work clips, and finally the building row itself,
## which sits in FRONT of the squad grid and was never part of the extents
## the camera was derived from.
##
## The instrument that would have caught any of them is a frustum test
## over the whole content box, and that is arithmetic — no GPU, no scene,
## the `test_hud_layout.gd` / `test_render_cull.gd` split. The preview
## itself calls the same `covers()` this file does, so the picture and the
## check cannot come to disagree (D-096's shared-arithmetic rule).

const ASPECTS := [1400.0 / 900.0, 16.0 / 9.0, 4.0 / 3.0, 1.0, 21.0 / 9.0]

# The scene `model_preview.gd` actually builds, to scale: seven clip
# columns at 5.5 apart, six archetype rows at 7.0 apart running back from
# z = 0, and nine buildings at 4.2 apart standing at z = +6.5, the largest
# of them a few units across.
const SQUAD_GRID := AABB(Vector3(-19.0, 0.0, -37.0), Vector3(38.0, 2.4, 39.0))
const BUILDING_ROW := AABB(Vector3(-19.6, 0.0, 3.5), Vector3(39.2, 6.0, 6.0))


func _whole_scene() -> AABB:
	return SQUAD_GRID.merge(BUILDING_ROW)


# --- the reported bug --------------------------------------------------

func test_the_building_row_is_in_shot() -> void:
	# #228 itself. Frame the whole scene and every corner of the building
	# row must be inside the picture — including the ends of it, which is
	# what was cut.
	for aspect in ASPECTS:
		var at := PreviewFraming.position_for(_whole_scene(), aspect)
		assert_true(PreviewFraming.covers(BUILDING_ROW, at, aspect),
			"buildings held at aspect %.2f" % aspect)
		assert_true(PreviewFraming.covers(SQUAD_GRID, at, aspect),
			"squads held at aspect %.2f" % aspect)


func test_framing_only_the_squads_loses_the_buildings() -> void:
	# The defect, stated as arithmetic: this is what the shipped camera
	# did, and it is why the ninth building ran off the right-hand edge.
	# Observing the check go red on the old behaviour is what makes the
	# green above worth anything (CLAUDE.md's rule 2).
	var aspect := 1400.0 / 900.0
	var at := PreviewFraming.position_for(SQUAD_GRID, aspect)
	assert_false(PreviewFraming.covers(_whole_scene(), at, aspect),
		"a camera framed on the squads alone cannot hold the buildings")


func test_a_tenth_building_reframes_the_shot() -> void:
	# The generalisation, and the perturbation #228 asks for: grow the row
	# and the camera follows it instead of the row falling off the edge.
	var aspect := 1400.0 / 900.0
	var wider := _whole_scene().merge(
		AABB(Vector3(-23.8, 0.0, 3.5), Vector3(47.6, 6.0, 6.0)))
	var at := PreviewFraming.position_for(wider, aspect)
	assert_true(PreviewFraming.covers(wider, at, aspect),
		"a tenth building is framed rather than clipped")
	assert_gt(at.distance_to(wider.get_center()),
		PreviewFraming.position_for(_whole_scene(), aspect)
			.distance_to(_whole_scene().get_center()),
		"a wider scene is framed from further back")


# --- the contract, over shapes nobody has drawn yet --------------------

func test_any_content_box_is_held_at_any_aspect() -> void:
	# The class, not the instance. Deep, wide, tall, tiny, off-centre and
	# behind the aim point — a preview that grows a new kind of content is
	# the case every previous fix failed.
	var boxes := [
		AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 2.0, 2.0)),
		AABB(Vector3(-60.0, 0.0, -4.0), Vector3(120.0, 3.0, 8.0)),
		AABB(Vector3(-4.0, 0.0, -90.0), Vector3(8.0, 3.0, 180.0)),
		AABB(Vector3(-2.0, 0.0, -2.0), Vector3(4.0, 40.0, 4.0)),
		AABB(Vector3(12.0, -3.0, 30.0), Vector3(9.0, 5.0, 4.0)),
		AABB(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 0.4, 0.4)),
	]
	for pitch in [12.0, 27.0, 45.0, 70.0]:
		for aspect in ASPECTS:
			for box in boxes:
				var at := PreviewFraming.position_for(box, aspect, 62.0, pitch)
				assert_true(PreviewFraming.covers(box, at, aspect, 62.0, pitch),
					"held %s at pitch %.0f aspect %.2f" % [box, pitch, aspect])


func test_the_camera_looks_down_at_the_content() -> void:
	# A frustum test alone would be satisfied by standing underneath the
	# scene, which is a picture of nothing.
	var box := _whole_scene()
	var at := PreviewFraming.position_for(box, 1.5)
	assert_gt(at.y, box.get_center().y, "camera is above the content")
	assert_gt(at.z, box.get_center().z, "camera is in front of the content")


func test_covers_rejects_what_is_off_the_edge() -> void:
	# The check has to be able to say no, or every assertion above is
	# vacuous — the shape of the load test's `desync` scan that matched no
	# code path for a whole milestone.
	var box := _whole_scene()
	var at := PreviewFraming.position_for(box, 1.5)
	assert_false(PreviewFraming.covers(
		AABB(at + Vector3(0.0, 0.0, 5.0), Vector3(1.0, 1.0, 1.0)), at, 1.5),
		"content behind the camera is not covered")
	assert_false(PreviewFraming.covers(
		box.merge(AABB(Vector3(400.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0))), at, 1.5),
		"content far off to the side is not covered")


func test_the_margin_only_adds_slack() -> void:
	# Margin is taste; correctness is the frustum test. A zero margin must
	# still hold the content, or the margin is load-bearing and the next
	# person to tune it breaks the picture.
	var box := _whole_scene()
	for aspect in ASPECTS:
		var tight := PreviewFraming.position_for(box, aspect, 62.0, 27.0, 0.0)
		assert_true(PreviewFraming.covers(box, tight, aspect),
			"held with no margin at aspect %.2f" % aspect)
		var padded := PreviewFraming.position_for(box, aspect, 62.0, 27.0, 0.5)
		assert_gt(padded.distance_to(box.get_center()),
			tight.distance_to(box.get_center()),
			"a margin stands further back at aspect %.2f" % aspect)


func test_it_is_all_static() -> void:
	var source := FileAccess.get_file_as_string("res://preview_framing.gd")
	assert_ne(source, "", "preview_framing.gd is readable")
	for line in source.split("
"):
		var text := String(line)
		# Top level only — an indented `var` is a local, which is the
		# arithmetic doing its job.
		assert_false(text.begins_with("var ") or text.begins_with("func "),
			"PreviewFraming must stay all-static: '%s'" % text)

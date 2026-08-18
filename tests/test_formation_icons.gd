extends GutTest

## Guards D-058 (as amended 2026-08-18: all six shapes are offered) and the
## formation icon strip that made room for them.
##
## The defect these exist for: `offered` is a flag in six .tres files and
## the grid that had to hold them was a constant in hud_layout.gd, with
## nothing linking the two. Flipping three flags put two buttons below the
## panel's own bottom edge, and no test could see it — the numbers were all
## fine and the picture was wrong, which is this project's recurring class.

## The real panel at the reference window, not a made-up rect: the
## commands column is what is LEFT after the chip strip reserves its
## width, so an invented panel can hand it zero and fail for a reason
## that has nothing to do with icons.
func _panel(viewport := HudLayout.REFERENCE) -> Rect2:
	return HudLayout.compute(HudLayout.design_size(viewport), Vector2(216.0, 216.0))["panel"]


func test_every_shape_a_player_is_offered_draws_an_icon() -> void:
	for def in FormationRoster.offered():
		var dots := FormationIcon.dots(String(def.id))
		assert_eq(dots.size(), FormationIcon.SAMPLE_STRENGTH,
			"%s draws no icon, so its button would be blank" % def.id)


func test_an_unknown_shape_draws_nothing_rather_than_the_wrong_shape() -> void:
	# Deliberately not a fallback to line: an icon quietly showing the
	# wrong formation cannot be noticed by the player it misleads.
	assert_eq(FormationIcon.dots("no_such_formation").size(), 0)


func test_every_dot_stays_inside_its_button() -> void:
	for def in FormationRoster.load_all():
		for p in FormationIcon.dots(String(def.id)):
			assert_between(p.x, -0.5, 0.5, "%s spills sideways" % def.id)
			assert_between(p.y, -0.5, 0.5, "%s spills vertically" % def.id)


func test_line_and_column_are_visibly_different_icons() -> void:
	# The regression the SAMPLE_STRENGTH note warns about: line is 3 ranks
	# and column is 4 files, so at 12 men both are 4 wide by 3 deep and the
	# two buttons are identical pictures.
	var line := _extent(FormationIcon.dots("line"))
	var column := _extent(FormationIcon.dots("column"))
	assert_gt(line.x, column.x, "line is not drawn wider than column")
	assert_gt(column.y, line.y, "column is not drawn deeper than line")


func test_tight_and_sparse_are_told_apart_by_regularity_not_size() -> void:
	# Each icon fills its own box, so these two cannot be distinguished by
	# extent — what separates them is that `sparse` is jittered off the
	# lattice and `tight` is not. If that stops being true the two buttons
	# become the same picture.
	assert_gt(_distinct_columns(FormationIcon.dots("sparse")),
		_distinct_columns(FormationIcon.dots("tight")),
		"sparse is not visibly more irregular than tight")


## How many distinct x positions the dots occupy, to a coarse tolerance —
## a lattice has few, a scatter has many.
func _distinct_columns(dots: PackedVector2Array) -> int:
	var seen := {}
	for p in dots:
		seen[roundi(p.x * 40.0)] = true
	return seen.size()


func test_the_front_rank_is_at_the_top_of_the_icon() -> void:
	# Slot 0 is the front rank; screen -y is up.
	var dots := FormationIcon.dots("line")
	var front: float = dots[0].y
	for p in dots:
		assert_lte(front, p.y + 0.0001, "slot 0 is not drawn at the front")


func test_every_offered_formation_fits_the_strip_it_is_drawn_in() -> void:
	# THE check that the flag flip needed and did not have.
	var count := FormationRoster.offered().size()
	var icon := HudLayout.formation_icon_size(_panel(), count)
	var column := HudLayout.commands_column_rect(_panel())
	assert_gt(icon.x, 1.0, "icons collapsed to nothing at %d formations" % count)
	var last := HudLayout.formation_icon_slot(count - 1, icon)
	assert_lte(last.x + icon.x, column.size.x,
		"%d formation icons overflow the commands column" % count)
	assert_lte(last.y + icon.y, _panel().size.y,
		"the formation strip hangs below the panel")


func test_icons_do_not_overlap_each_other() -> void:
	var count := FormationRoster.offered().size()
	var icon := HudLayout.formation_icon_size(_panel(), count)
	for i in range(count - 1):
		var a := HudLayout.formation_icon_slot(i, icon)
		var b := HudLayout.formation_icon_slot(i + 1, icon)
		assert_lte(a.x + icon.x, b.x + 0.0001, "icon %d overlaps its neighbour" % i)


func test_the_remaining_actions_start_below_the_strip() -> void:
	var icon := HudLayout.formation_icon_size(_panel(), FormationRoster.offered().size())
	var button := HudLayout.action_button_size(_panel())
	var first := HudLayout.action_slot(HudLayout.actions_start_index(), button)
	assert_gte(first.y, HudLayout.formation_icon_slot(0, icon).y + icon.y,
		"Stop and Gather are drawn over the formation icons")


func _extent(dots: PackedVector2Array) -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in dots:
		lo = lo.min(p)
		hi = hi.max(p)
	return hi - lo

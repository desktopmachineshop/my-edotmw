extends GutTest

## Guards `selection_pick.gd` — which thing a click selects when squads
## and buildings overlap.
##
## Same split as `test_render_cull.gd`: the client cannot run headless
## (D-014), but the ranking is arithmetic and the ranking is what was
## wrong. Squads scored `distance - allowance` (negative inside the
## footprint, more negative the larger the formation) and buildings scored
## raw `distance` (always positive), and the two were then compared to each
## other. A building could not win a click that any squad had claimed.


func _squad(id: int, distance: float, allowance: float) -> Dictionary:
	return {"id": id, "distance": distance, "allowance": allowance}


# --- the reported bug -------------------------------------------------

func test_a_building_covered_in_units_is_still_selectable() -> void:
	# THE case. A town centre right under the cursor, inside the footprint
	# of a forty-man militia line standing on it. On the old two-scale
	# comparison the militia scored -70 and the building scored 5, and
	# `5 < -70` is false — so the building was unselectable exactly when a
	# player most wants it, which is when it is under attack.
	var picked := SelectionPick.choose(
		[_squad(7, 20.0, 90.0)],
		[{"id": 1001, "distance": 5.0, "allowance": 30.0}])
	assert_eq(int(picked["building"]), 1001, "the building wins the click")
	assert_eq(int(picked["squad"]), -1, "and the squad is not also selected")


func test_the_bigger_the_covering_army_the_less_it_matters() -> void:
	# The old bug got WORSE the larger the covering formation, because the
	# score it compared against was that formation's own footprint.
	#
	# This is also the case that decided how the two kinds are compared.
	# Normalising both to "fraction of my own allowance" was tried first
	# and fails here: an army filling the screen scores near zero almost
	# everywhere, so at an allowance of 90 and up it still swallowed the
	# building. Raw distance to centre does not care how big either thing
	# is, which is the whole point.
	for allowance in [40.0, 90.0, 200.0, 600.0]:
		var picked := SelectionPick.choose(
			[_squad(7, 10.0, allowance)],
			[{"id": 1001, "distance": 4.0, "allowance": 26.0}])
		assert_eq(int(picked["building"]), 1001,
			"building still wins under a squad of allowance %d" % allowance)


# --- but not at any cost ----------------------------------------------

func test_a_squad_clicked_well_away_from_a_building_still_wins() -> void:
	# The fix must not turn into "buildings always win": clicking a soldier
	# standing near the barracks has to select the soldier.
	var picked := SelectionPick.choose(
		[_squad(7, 5.0, 90.0)],
		[{"id": 1001, "distance": 29.0, "allowance": 30.0}])
	assert_eq(int(picked["squad"]), 7)
	assert_eq(int(picked["building"]), -1)


func test_a_click_outside_everything_selects_nothing() -> void:
	var picked := SelectionPick.choose(
		[_squad(7, 300.0, 90.0)],
		[{"id": 1001, "distance": 300.0, "allowance": 30.0}])
	assert_eq(int(picked["squad"]), -1)
	assert_eq(int(picked["building"]), -1)


func test_a_click_just_outside_a_building_does_not_take_it() -> void:
	# The preference multiplies the score, it does not extend the reach.
	var picked := SelectionPick.choose([],
		[{"id": 1001, "distance": 40.0, "allowance": 30.0}])
	assert_eq(int(picked["building"]), -1)


# --- ranking within a kind --------------------------------------------

func test_two_overlapping_squads_resolve_to_the_one_clicked_nearer() -> void:
	# Normalised, so a small squad clicked dead centre beats a huge one
	# whose edge the click merely grazed — the reason the metric is a
	# fraction of the allowance and not a pixel count.
	var picked := SelectionPick.choose([
		_squad(1, 85.0, 90.0),   # 0.94 — barely inside a big formation
		_squad(2, 6.0, 30.0),    # 0.20 — squarely on a small one
	], [])
	assert_eq(int(picked["squad"]), 2)


func test_the_nearer_of_two_buildings_wins() -> void:
	var picked := SelectionPick.choose([], [
		{"id": 1001, "distance": 25.0, "allowance": 30.0},
		{"id": 1002, "distance": 3.0, "allowance": 30.0},
	])
	assert_eq(int(picked["building"]), 1002)


func test_a_tiny_building_on_screen_is_still_clickable() -> void:
	# Zoomed out, a town centre projects to a couple of pixels. Without a
	# floor on the allowance it would need pixel-exact aim.
	var picked := SelectionPick.choose([],
		[{"id": 1001, "distance": 15.0, "allowance": 2.0}])
	assert_eq(int(picked["building"]), 1001)


# --- the metric itself ------------------------------------------------

func test_score_is_zero_at_the_centre_and_one_at_the_edge() -> void:
	assert_almost_eq(SelectionPick.score(0.0, 50.0), 0.0, 0.0001)
	assert_almost_eq(SelectionPick.score(50.0, 50.0), 1.0, 0.0001)
	assert_almost_eq(SelectionPick.score(25.0, 50.0), 0.5, 0.0001)


func test_a_miss_scores_infinity_rather_than_merely_a_lot() -> void:
	# So that no pile-up of near-misses can ever out-rank a real hit, and
	# so callers never have to re-test eligibility separately.
	assert_eq(SelectionPick.score(51.0, 50.0), INF)
	assert_eq(SelectionPick.score(10.0, 0.0), INF,
		"a candidate with no footprint cannot be hit")


func test_no_candidates_at_all_selects_nothing() -> void:
	var picked := SelectionPick.choose([], [])
	assert_eq(int(picked["squad"]), -1)
	assert_eq(int(picked["building"]), -1)

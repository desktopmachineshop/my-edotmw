extends GutTest

## Guards `hud_layout.gd` — that the HUD covers whatever window it is
## given, at whatever shape.
##
## The client cannot be tested headless (D-014), so what is proven here is
## the half with the interesting failure mode, the same split
## `test_render_cull.gd` makes. Every element used to be placed at a
## literal pixel coordinate written against a 1280x720 window, and
## full-screened at 1920x1080 the resource bar therefore stopped
## two-thirds of the way across with the panel floating mid-screen. That is
## arithmetic, and it is checkable without a GPU.

const SIZES := [
	Vector2(1280.0, 720.0),    # the reference window
	Vector2(1152.0, 648.0),    # Godot's default, smaller than reference
	Vector2(1920.0, 1080.0),   # the one the bug was reported on
	Vector2(2560.0, 1440.0),
	Vector2(3440.0, 1440.0),   # 21:9 — scale alone cannot fix this one
	Vector2(1024.0, 768.0),    # 4:3, taller than it is wide for its width
]


func _laid_out(viewport: Vector2, minimap := Vector2(216.0, 216.0)) -> Dictionary:
	return HudLayout.compute(HudLayout.design_size(viewport), minimap)


# --- the reported bug --------------------------------------------------

func test_the_resource_bar_spans_the_whole_window() -> void:
	# THE failure this file exists for. In real pixels, not design units:
	# a bar that is "full width" of a design space the window does not
	# match is exactly the bug being fixed.
	for viewport in SIZES:
		var scale := HudLayout.scale_for(viewport)
		var bar: Rect2 = _laid_out(viewport)["resource_bar"]
		assert_almost_eq(bar.position.x * scale, 0.0, 0.5,
			"bar starts at the left edge at %s" % viewport)
		assert_almost_eq(bar.size.x * scale, viewport.x, 1.0,
			"bar reaches the right edge at %s" % viewport)


func test_the_panel_sits_at_the_bottom_left_of_any_window() -> void:
	for viewport in SIZES:
		var design := HudLayout.design_size(viewport)
		var panel: Rect2 = _laid_out(viewport)["panel"]
		assert_almost_eq(panel.position.x, HudLayout.MARGIN, 0.01,
			"panel hugs the left edge at %s" % viewport)
		assert_almost_eq(panel.position.y + panel.size.y,
			design.y - HudLayout.MARGIN, 0.01,
			"panel bottom sits a margin above the floor at %s" % viewport)


func test_nothing_lands_outside_the_window() -> void:
	for viewport in SIZES:
		var design := HudLayout.design_size(viewport)
		var at := _laid_out(viewport)
		for key in at:
			var rect: Rect2 = at[key]
			assert_true(rect.position.x >= -0.01 and rect.position.y >= -0.01,
				"%s starts on screen at %s" % [key, viewport])
			assert_true(rect.position.x + rect.size.x <= design.x + 0.01,
				"%s ends on screen at %s" % [key, viewport])
			assert_true(rect.position.y + rect.size.y <= design.y + 0.01,
				"%s fits vertically at %s" % [key, viewport])


# --- the reference window is reproduced exactly ------------------------

func test_a_16_9_window_reproduces_the_hand_tuned_layout() -> void:
	# The whole reason REFERENCE is 1280x720: every 16:9 window comes back
	# to that design space, so the HUD that was looked at and tuned by hand
	# is the HUD that is still drawn. If this fails, some window shape has
	# quietly become the odd one out.
	var reference := _laid_out(HudLayout.REFERENCE)
	for viewport in [Vector2(1920.0, 1080.0), Vector2(2560.0, 1440.0),
			Vector2(1152.0, 648.0)]:
		var at := _laid_out(viewport)
		for key in reference:
			assert_eq(at[key], reference[key],
				"%s is identical in design space at %s" % [key, viewport])


func test_the_panel_keeps_its_hand_tuned_position_at_the_reference_size() -> void:
	# The literals this file replaced, asserted rather than described:
	# panel at (12, 408), 430x300.
	var panel: Rect2 = _laid_out(HudLayout.REFERENCE)["panel"]
	assert_eq(panel, Rect2(12.0, 408.0, 430.0, 300.0))


# --- scale ------------------------------------------------------------

func test_scale_grows_with_the_window_but_is_bounded() -> void:
	assert_almost_eq(HudLayout.scale_for(HudLayout.REFERENCE), 1.0, 0.001)
	assert_almost_eq(HudLayout.scale_for(Vector2(1920.0, 1080.0)), 1.5, 0.001)
	# Clamped at both ends: a 4K HUD that keeps growing eats the map, and a
	# tiny one stops being legible.
	assert_eq(HudLayout.scale_for(Vector2(7680.0, 4320.0)), HudLayout.MAX_SCALE)
	assert_eq(HudLayout.scale_for(Vector2(320.0, 200.0)), HudLayout.MIN_SCALE)


func test_scale_follows_the_smaller_dimension() -> void:
	# A short, wide window must not be scaled by its width — that pushes
	# the selection panel off the bottom, which is worse than a small HUD.
	var wide := Vector2(3440.0, 1440.0)
	assert_almost_eq(HudLayout.scale_for(wide), 2.0, 0.001)
	var short := Vector2(1920.0, 600.0)
	assert_true(HudLayout.scale_for(short) < 1.0,
		"a 600px-tall window scales down, not up")


func test_an_ultrawide_still_reaches_both_edges() -> void:
	# Scale alone cannot do this, which is why anchoring exists as well:
	# 3440x1440 scales by its HEIGHT, so a bar sized in design units from
	# the reference width would stop well short.
	var design := HudLayout.design_size(Vector2(3440.0, 1440.0))
	assert_true(design.x > HudLayout.REFERENCE.x,
		"an ultrawide's design space is wider than the reference")
	var bar: Rect2 = _laid_out(Vector2(3440.0, 1440.0))["resource_bar"]
	assert_almost_eq(bar.size.x, design.x, 0.01)


# --- pieces that must not collide -------------------------------------

func test_the_minimap_sits_between_the_bar_and_the_panel() -> void:
	for viewport in SIZES:
		var at := _laid_out(viewport)
		var minimap: Rect2 = at["minimap"]
		var panel: Rect2 = at["panel"]
		assert_true(minimap.position.y >= HudLayout.BAR_HEIGHT,
			"minimap clears the resource bar at %s" % viewport)
		assert_true(minimap.position.y + minimap.size.y <= panel.position.y + 0.01,
			"minimap clears the selection panel at %s" % viewport)


func test_a_very_short_window_keeps_the_panel_clear_of_the_bar() -> void:
	# Degenerate, but it is what a dragged-down window does, and a panel
	# drawn under the resource bar hides the resource counts entirely.
	var at := _laid_out(Vector2(1280.0, 240.0))
	var panel: Rect2 = at["panel"]
	assert_true(panel.position.y >= HudLayout.BAR_HEIGHT,
		"panel never climbs under the bar")


func test_the_status_readout_stays_clear_of_the_resource_counts() -> void:
	# It was at a fixed x=700, which on a narrow window sat on top of the
	# stone count.
	for viewport in SIZES:
		var status: Rect2 = _laid_out(viewport)["status"]
		var last_resource := HudLayout.resource_slot(3)
		assert_true(status.position.x >= last_resource.x,
			"status starts past the last resource swatch at %s" % viewport)


func test_the_notice_is_centred_on_the_window() -> void:
	for viewport in SIZES:
		var design := HudLayout.design_size(viewport)
		var notice: Rect2 = _laid_out(viewport)["notice"]
		# Full width plus centred text, rather than an x that happened to
		# look centred at one size.
		assert_almost_eq(notice.size.x, design.x, 0.01,
			"notice spans the window at %s" % viewport)
		assert_true(notice.position.y >= HudLayout.BAR_HEIGHT,
			"notice sits below the bar at %s" % viewport)


# --- minimap shape ----------------------------------------------------

func test_the_minimap_keeps_the_shape_it_is_given() -> void:
	# Its proportions come from the MAP (see Client._layout_minimap), and
	# this must not quietly re-shape them — a square world drawn into a 2:1
	# box reads distances wrong.
	var tall := Vector2(216.0, 340.0)
	var at := _laid_out(Vector2(1920.0, 1080.0), tall)
	assert_eq(Rect2(at["minimap"]).size, tall)


# --- the top bar's new occupants (D-063) ------------------------------

func test_the_menu_button_sits_at_the_right_end_of_the_bar() -> void:
	for viewport in SIZES:
		var design := HudLayout.design_size(viewport)
		var at := _laid_out(viewport)
		var menu: Rect2 = at["menu_button"]
		var bar: Rect2 = at["resource_bar"]
		assert_almost_eq(menu.position.x + menu.size.x, design.x - HudLayout.MARGIN, 0.01,
			"menu hugs the right edge at %s" % viewport)
		assert_true(menu.position.y >= 0.0
			and menu.position.y + menu.size.y <= bar.size.y + 0.01,
			"menu sits inside the bar at %s" % viewport)


func test_the_status_readout_never_runs_under_the_menu_button() -> void:
	# The status line grew from a squad count to a squad count AND a
	# clock, and the menu button appeared to its right in the same change.
	# Two things that both want the right-hand end is exactly how a
	# readout ends up drawn underneath a button.
	for viewport in SIZES:
		var at := _laid_out(viewport)
		var status: Rect2 = at["status"]
		var menu: Rect2 = at["menu_button"]
		assert_true(status.position.x + status.size.x <= menu.position.x + 0.01,
			"status ends before the menu button at %s" % viewport)


func test_the_compass_clears_the_bar_and_the_minimap() -> void:
	for viewport in SIZES:
		var at := _laid_out(viewport)
		var compass: Rect2 = at["compass"]
		var minimap: Rect2 = at["minimap"]
		assert_true(compass.position.y >= HudLayout.BAR_HEIGHT,
			"compass clears the resource bar at %s" % viewport)
		assert_false(compass.intersects(minimap),
			"compass does not overlap the minimap at %s" % viewport)


func test_the_compass_stays_on_screen_on_a_narrow_window() -> void:
	# It is placed from the RIGHT edge, so a window narrower than the
	# compass plus its margin is where it would walk off to the left.
	var at := HudLayout.compute(Vector2(60.0, 400.0), Vector2(216.0, 216.0))
	var compass: Rect2 = at["compass"]
	assert_true(compass.position.x >= 0.0, "compass never starts off-screen")


# --- the compass dial -------------------------------------------------

func test_north_is_up_when_the_view_is_not_turned() -> void:
	var north := HudLayout.compass_offset(0.0, 0, 20.0)
	assert_almost_eq(north.x, 0.0, 0.001)
	assert_almost_eq(north.y, -20.0, 0.001, "screen y grows downward, so up is negative")


func test_east_is_to_the_right_of_north_on_the_dial() -> void:
	# If this comes out mirrored the compass reads plausibly and is wrong,
	# which is the whole reason the geometry was pulled out here.
	var east := HudLayout.compass_offset(0.0, 1, 20.0)
	assert_almost_eq(east.x, 20.0, 0.001)
	assert_almost_eq(east.y, 0.0, 0.001)


func test_turning_the_view_turns_the_dial_the_other_way() -> void:
	# THE case this exists for. The dial turns and the needle does not: a
	# compass answers "which way am I facing", so turning the camera a
	# quarter-turn one way must swing the world's north a quarter-turn the
	# other. Building it the other way round produces a magnetic compass —
	# a different instrument, and one that looks fine until you try to
	# navigate by it.
	var turned := HudLayout.compass_offset(PI * 0.5, 0, 20.0)
	assert_almost_eq(turned.x, -20.0, 0.001,
		"a quarter-turn right puts north on the LEFT of the dial")
	assert_almost_eq(turned.y, 0.0, 0.001)


func test_the_cardinals_stay_square_at_any_angle() -> void:
	for yaw in [0.0, 0.3, 1.0, PI, 5.9, TAU]:
		var points := []
		for i in range(4):
			points.append(HudLayout.compass_offset(yaw, i, 20.0))
		for i in range(4):
			assert_almost_eq(points[i].length(), 20.0, 0.001,
				"cardinal %d stays on the ring at yaw %f" % [i, yaw])
			# Opposite cardinals are opposite: N against S, E against W.
			var opposite: Vector2 = points[(i + 2) % 4]
			assert_almost_eq((points[i] + opposite).length(), 0.0, 0.001,
				"cardinal %d is opposite its counterpart at yaw %f" % [i, yaw])


func test_a_full_turn_comes_back_to_where_it_started() -> void:
	var at_rest := HudLayout.compass_offset(0.0, 0, 20.0)
	var round_trip := HudLayout.compass_offset(TAU, 0, 20.0)
	assert_almost_eq(at_rest.distance_to(round_trip), 0.0, 0.001)


# --- readouts ---------------------------------------------------------

func test_the_clock_reads_as_minutes_until_an_hour_then_hours() -> void:
	assert_eq(HudLayout.clock_text(0.0), "0:00")
	assert_eq(HudLayout.clock_text(9.0), "0:09")
	assert_eq(HudLayout.clock_text(65.0), "1:05")
	assert_eq(HudLayout.clock_text(547.0), "9:07")
	# The boundary this game is actually aiming at: D-056 wants 1-2 hour
	# matches, so the hour rollover is a case that WILL be hit, not a
	# theoretical one.
	assert_eq(HudLayout.clock_text(3599.0), "59:59")
	assert_eq(HudLayout.clock_text(3600.0), "1:00:00")
	assert_eq(HudLayout.clock_text(4147.0), "1:09:07")


func test_the_clock_never_shows_a_negative_time() -> void:
	# Defensive, and cheap: the clock is derived from a server tick and a
	# local timestamp, and a clock that can print "-1:-3" once is a clock
	# nobody trusts again.
	assert_eq(HudLayout.clock_text(-5.0), "0:00")


func test_the_squad_count_shows_the_cap_when_there_is_one() -> void:
	assert_eq(HudLayout.squad_count_text(12, 40), "12/40 squads")
	assert_eq(HudLayout.squad_count_text(40, 40), "40/40 squads",
		"at the cap reads as at the cap, not as an error")


func test_the_squad_count_omits_an_unknown_cap_rather_than_printing_zero() -> void:
	# A server that never stated a cap sends 0. "12/0 squads" would read
	# as a broken rule rather than as an absent number.
	assert_eq(HudLayout.squad_count_text(12, 0), "12 squads")


func test_action_buttons_fill_rows_of_three_inside_the_panel() -> void:
	for i in range(9):
		var slot := HudLayout.action_slot(i)
		assert_true(slot.x + HudLayout.ACTION_BUTTON.x
			<= HudLayout.PANEL_SIZE.x - HudLayout.PANEL_PAD + 0.01,
			"button %d fits the panel's width" % i)
		assert_true(slot.y + HudLayout.ACTION_BUTTON.y <= HudLayout.PANEL_SIZE.y,
			"button %d fits the panel's height" % i)
	assert_almost_eq(HudLayout.action_slot(0).y, HudLayout.action_slot(2).y, 0.01,
		"the first three buttons share a row")
	assert_true(HudLayout.action_slot(3).y > HudLayout.action_slot(0).y,
		"the fourth button starts a new row")

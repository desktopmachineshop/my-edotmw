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

func test_a_16_9_window_at_or_under_the_reference_reproduces_the_hand_tuned_layout() -> void:
	# The whole reason REFERENCE is 1280x720: a 16:9 window no larger than
	# it comes back to exactly that design space, so the HUD that was looked
	# at and tuned by hand is the HUD that is still drawn. If this fails,
	# some window shape has quietly become the odd one out.
	#
	# 16:9 windows LARGER than the reference deliberately no longer
	# reproduce it — that identity was the same statement as "the HUD keeps
	# a constant fraction of the window at every size", which is #90. See
	# `test_a_bigger_window_gives_more_battlefield_not_a_bigger_hud`.
	var reference := _laid_out(HudLayout.REFERENCE)
	for viewport in [Vector2(1152.0, 648.0), Vector2(1280.0, 720.0)]:
		var at := _laid_out(viewport)
		for key in reference:
			assert_eq(at[key], reference[key],
				"%s is identical in design space at %s" % [key, viewport])


func test_the_panel_keeps_its_hand_tuned_position_at_the_reference_size() -> void:
	# The panel is now a WIDE bar (the chip design needs the room), full
	# width minus margins, rather than a narrow corner card.
	var panel: Rect2 = _laid_out(HudLayout.REFERENCE)["panel"]
	assert_eq(panel, Rect2(12.0, 720.0 - HudLayout.PANEL_HEIGHT - 12.0,
		1280.0 - 24.0, HudLayout.PANEL_HEIGHT))


# --- scale ------------------------------------------------------------

func test_scale_grows_with_the_window_but_is_bounded() -> void:
	assert_almost_eq(HudLayout.scale_for(HudLayout.REFERENCE), 1.0, 0.001)
	# Between the reference and MAGNIFY_ABOVE the HUD is drawn at its
	# design size — magnification is what #90 was about, and it now starts
	# where a monitor is genuinely bigger than the common one.
	assert_almost_eq(HudLayout.scale_for(HudLayout.MAGNIFY_ABOVE), 1.0, 0.001)
	assert_almost_eq(HudLayout.scale_for(Vector2(2560.0, 1440.0)), 1440.0 / 1080.0, 0.001)
	# Clamped at both ends: a 4K HUD that keeps growing eats the map, and a
	# tiny one stops being legible.
	assert_eq(HudLayout.scale_for(Vector2(7680.0, 4320.0)), HudLayout.MAX_SCALE)
	assert_eq(HudLayout.scale_for(Vector2(320.0, 200.0)), HudLayout.MIN_SCALE)


func test_min_window_size_is_the_reference_at_the_scale_floor() -> void:
	# 1280x720 * MIN_SCALE — the smallest window `scale_for` still treats as
	# "shrink the HUD to match" rather than "the HUD no longer fits".
	assert_eq(HudLayout.min_window_size(),
		Vector2i(HudLayout.REFERENCE * HudLayout.MIN_SCALE))


func test_scale_follows_the_smaller_dimension() -> void:
	# A short, wide window must not be scaled by its width — that pushes
	# the selection panel off the bottom, which is worse than a small HUD.
	var wide := Vector2(3440.0, 1440.0)
	assert_almost_eq(HudLayout.scale_for(wide),
		HudLayout.scale_for(Vector2(2560.0, 1440.0)), 0.001,
		"an ultrawide is scaled by its height, exactly like a 16:9 window of the same height")
	var short := Vector2(1920.0, 600.0)
	assert_true(HudLayout.scale_for(short) < 1.0,
		"a 600px-tall window scales down, not up")


# --- a bigger window buys battlefield, not a bigger HUD (#90) ---------


## The tallest HUD element, as a fraction of the REAL window's height —
## design units times the scale actually applied. Design units alone cannot
## see this bug at all: the panel is 264 of them at every window size, by
## construction, which is precisely why it went unnoticed.
func _panel_share(viewport: Vector2) -> float:
	var panel: Rect2 = _laid_out(viewport)["panel"]
	return panel.size.y * HudLayout.scale_for(viewport) / viewport.y


func test_a_bigger_window_gives_more_battlefield_not_a_bigger_hud() -> void:
	# THE bug this section exists for (#90, from playtest #30). `scale_for`
	# was linear in the window, so every element kept a CONSTANT FRACTION of
	# it at every resolution: the command panel was 36.7% of the height at
	# the 1280x720 reference and still 36.7% at 1920x1080 and at 2560x1440.
	# A player who bought a bigger window got no more of the battlefield,
	# only a bigger HUD — reported as far too big at 1080p.
	var reference := _panel_share(HudLayout.REFERENCE)
	for viewport in [Vector2(1600.0, 900.0), Vector2(1920.0, 1000.0),
			Vector2(1920.0, 1080.0), Vector2(2560.0, 1440.0)]:
		# A RATIO, not a fixed margin: the panel's own height was cut from
		# 264 units to 146 by the three-column rework, and a margin
		# calibrated against the tall panel started reading a real
		# improvement as a failure at 1600x900.
		assert_true(_panel_share(viewport) < reference * 0.9,
			"the panel takes a smaller share of a %s window than of the reference (%.3f)"
				% [viewport, reference])
	# The window it was reported on — a ~1920x1000 client area, where the
	# panel measured ~357 real pixels of 1000. This is the number a fix has
	# to move, and it is quoted in real pixels for the same reason
	# `_panel_share` exists.
	assert_true(_panel_share(Vector2(1920.0, 1000.0)) <= 0.28,
		"the command panel is at most about a quarter of the reported window")


func test_the_hud_s_share_of_the_window_never_grows_with_the_window() -> void:
	# The property, rather than one resolution's number: enlarging a window
	# may give the HUD a smaller share of it or the same share, never a
	# bigger one. A future scale curve that dips and then rises again would
	# pass the test above and still surprise a player dragging a window.
	var previous := 1.0
	for viewport in [Vector2(1152.0, 648.0), HudLayout.REFERENCE,
			Vector2(1600.0, 900.0), Vector2(1920.0, 1080.0),
			Vector2(2560.0, 1440.0), Vector2(3840.0, 2160.0)]:
		var share := _panel_share(viewport)
		assert_true(share <= previous + 0.001,
			"the panel's share does not grow on the way up to %s" % viewport)
		previous = share


func test_the_hud_is_never_magnified_more_than_it_used_to_be() -> void:
	# The safety half of #90's fix, and the reason it needed no re-check of
	# every anchoring test: the new curve is <= the old linear one at every
	# window size, so no element can overflow anywhere it used to fit. The
	# risk it does carry is legibility, not layout — which is why the floor
	# and the manual scale slider (D-063) both stay.
	for viewport in SIZES + [Vector2(1920.0, 1000.0), Vector2(3840.0, 2160.0),
			Vector2(1920.0, 600.0), Vector2(800.0, 600.0)]:
		var linear := clampf(minf(viewport.x / HudLayout.REFERENCE.x,
			viewport.y / HudLayout.REFERENCE.y), HudLayout.MIN_SCALE, HudLayout.MAX_SCALE)
		assert_true(HudLayout.scale_for(viewport) <= linear + 0.001,
			"scale at %s is no larger than the old linear rule's %.3f" % [viewport, linear])


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

func test_the_minimap_sits_inside_the_ring() -> void:
	# The compass and the minimap were merged into one widget (the chosen
	# reference synthesis: "compass on the minimap ring"). The minimap no
	# longer lives in its own bottom-left box — it is centred inside the
	# ring that replaced the old top-right compass dial.
	#
	# True only for a square-ish minimap (the default here) — the ring is
	# sized around the SHORTER side (see RING_MIN_SIZE's doc comment), so an
	# oblong minimap's longer side is expected to run past the ring's own
	# bounding box; that overflow is what the crop shader hides. See
	# `test_the_ring_follows_the_minimap_s_shorter_dimension` for that case.
	for viewport in SIZES:
		var at := _laid_out(viewport)
		var minimap: Rect2 = at["minimap"]
		var ring: Rect2 = at["ring"]
		assert_true(ring.encloses(minimap) or ring.grow(0.01).encloses(minimap),
			"the minimap sits inside the ring that bounds it at %s" % viewport)


func test_the_ring_clears_the_resource_bar() -> void:
	for viewport in SIZES:
		var at := _laid_out(viewport)
		var ring: Rect2 = at["ring"]
		assert_true(ring.position.y >= HudLayout.BAR_HEIGHT,
			"ring clears the resource bar at %s" % viewport)


func test_the_ring_crop_radius_stays_inside_the_border() -> void:
	# The crop circle (the minimap) must sit strictly inside the ring's own
	# outer edge, with room left for the border band drawn over it —
	# otherwise the map would be visible bleeding past its own frame.
	var ring_diameter := HudLayout.RING_MIN_SIZE
	var crop_r := HudLayout.ring_crop_radius(ring_diameter)
	assert_true(crop_r > 0.0, "the crop radius is positive at the minimum ring size")
	assert_true(crop_r + HudLayout.RING_PADDING <= ring_diameter * 0.5,
		"the crop radius plus the border band fits inside the ring")


func test_the_ring_follows_the_minimap_s_shorter_dimension() -> void:
	# Sizing the ring from the DIAGONAL (circumscribing the whole rectangle)
	# was the actual bug behind a minimap that reportedly "still looks
	# square inside a circle": a ring sized to just contain a rectangle's
	# diagonal comes out almost exactly the size of that rectangle's own
	# bounding circle, so a crop at that radius clips next to nothing — the
	# ring LOOKED like a frame but the crop inside it was a no-op. Sizing
	# from the shorter side instead means an oblong minimap gets a
	# meaningfully SMALLER ring than a square one of the same width, which
	# is what makes the crop actually visible.
	var square: Rect2 = _laid_out(Vector2(1920.0, 1080.0), Vector2(216.0, 216.0))["ring"]
	var wide: Rect2 = _laid_out(Vector2(1920.0, 1080.0), Vector2(216.0, 80.0))["ring"]
	assert_true(wide.size.x < square.size.x,
		"a wide minimap gets a smaller ring than a square one of the same width")


func test_the_ring_diameter_tracks_the_minimap_s_shorter_side_directly() -> void:
	# Chosen so the shorter side alone (plus the border) already exceeds
	# RING_MIN_SIZE — otherwise the floor clamp, not the formula being
	# tested, would decide the answer.
	var minimap := Vector2(300.0, 200.0)
	var ring: Rect2 = _laid_out(Vector2(1920.0, 1080.0), minimap)["ring"]
	assert_almost_eq(ring.size.x, minf(minimap.x, minimap.y) + HudLayout.RING_PADDING * 2.0, 0.01)


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


func test_the_ring_stays_on_screen_on_a_narrow_window() -> void:
	# It is placed from the RIGHT edge, so a window narrower than the
	# ring plus its margin is where it would walk off to the left.
	var at := HudLayout.compute(Vector2(60.0, 400.0), Vector2(216.0, 216.0))
	var ring: Rect2 = at["ring"]
	assert_true(ring.position.x >= 0.0, "ring never starts off-screen")


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


func test_action_buttons_fill_rows_of_three_inside_their_own_column() -> void:
	# Relative to a COLUMN's own corner, not the whole panel's: the panel is
	# a wide bar whose middle and right columns each own a grid (see
	# `commands_column_rect` / `build_column_rect`), and the same grid
	# function serves both.
	for viewport in SIZES:
		var panel: Rect2 = _laid_out(viewport)["panel"]
		var button := HudLayout.action_button_size(panel)
		var width := HudLayout.actions_column_width(panel)
		for i in range(HudLayout.ACTION_ROWS * HudLayout.ACTION_COLUMNS):
			var slot := HudLayout.action_slot(i, button)
			assert_true(slot.x + button.x <= width - HudLayout.PANEL_PAD + 0.01,
				"button %d fits its column's width at %s" % [i, viewport])
			assert_true(slot.y + button.y <= HudLayout.PANEL_HEIGHT - HudLayout.PANEL_PAD_Y + 0.01,
				"button %d fits the panel's height at %s" % [i, viewport])
			assert_true(slot.y >= HudLayout.ACTIONS_Y - 0.01,
				"button %d sits below its column's caption at %s" % [i, viewport])
	var button := HudLayout.action_button_size(_laid_out(HudLayout.REFERENCE)["panel"])
	assert_almost_eq(HudLayout.action_slot(0, button).y, HudLayout.action_slot(2, button).y, 0.01,
		"the first three buttons share a row")
	assert_true(HudLayout.action_slot(3, button).y > HudLayout.action_slot(0, button).y,
		"the fourth button starts a new row")


func test_the_button_grid_grows_with_the_panel_between_two_bounds() -> void:
	# Button width is a function of the panel now, because two grids side by
	# side cannot share one width across a 1280-to-1920 design space. Both
	# clamps are real: the floor is what keeps the chip strip wide enough to
	# reach a building's whole train list on the smallest window (see
	# `test_every_building_s_train_list_fits_at_the_smallest_window`), and
	# the ceiling is where a button stops growing rather than sprawling.
	var narrow := HudLayout.action_button_size(_laid_out(Vector2(1280.0, 720.0))["panel"])
	var wide := HudLayout.action_button_size(_laid_out(Vector2(1920.0, 1080.0))["panel"])
	assert_true(wide.x > narrow.x, "a wider panel buys wider buttons")
	for viewport in SIZES + [Vector2(7680.0, 4320.0), Vector2(640.0, 480.0)]:
		var button := HudLayout.action_button_size(_laid_out(viewport)["panel"])
		assert_true(button.x <= HudLayout.ACTION_BUTTON_MAX_WIDTH + 0.01,
			"buttons stop growing at %s" % viewport)
		assert_eq(button.y, HudLayout.ACTION_BUTTON_HEIGHT,
			"button height is fixed, so the grid's row count is too")


# --- the wide panel's three columns ------------------------------------

func test_the_panel_is_three_columns_left_to_right() -> void:
	# Selection, then what you can ORDER it to do, then what you can BUILD —
	# in that order, never overlapping, all inside the panel. Requested from
	# playtest #30: the two action grids used to be STACKED in one right-hand
	# column, which is what made the panel tall.
	for viewport in SIZES:
		var panel: Rect2 = _laid_out(viewport)["panel"]
		var title := HudLayout.title_column_rect(panel)
		var strip := HudLayout.chip_strip_rect(panel)
		var commands := HudLayout.commands_column_rect(panel)
		var build := HudLayout.build_column_rect(panel)
		assert_true(title.position.x + title.size.x <= strip.position.x + 0.01,
			"the title column ends before the chips at %s" % viewport)
		assert_true(strip.position.x + strip.size.x <= commands.position.x + 0.01,
			"the chips end before the orders column at %s" % viewport)
		assert_almost_eq(commands.position.x + commands.size.x, build.position.x, 0.01,
			"the orders column meets the build column at %s" % viewport)
		assert_almost_eq(build.position.x + build.size.x,
			panel.position.x + panel.size.x, 0.01,
			"the build column ends at the panel's right edge at %s" % viewport)
		assert_true(commands.position.x >= title.position.x + title.size.x - 0.01,
			"the orders column never runs back over the title at %s" % viewport)


func test_the_panel_is_only_as_tall_as_its_tallest_column() -> void:
	# THE reason this rework exists (#90's follow-up, "even less room"). The
	# stacked layout paid for the title stack AND the commands grid AND the
	# build grid, one under the other; three columns pay for the worst of
	# the three. Asserted as the relationship, not as the number, so a
	# column that grows a row takes the panel with it — and a second grid
	# added back UNDER the first would fail this immediately.
	assert_eq(HudLayout.PANEL_HEIGHT,
		maxf(HudLayout.TITLE_COLUMN_HEIGHT,
			maxf(HudLayout.CHIP_STRIP_HEIGHT, HudLayout.ACTION_GRID_HEIGHT)))
	assert_true(HudLayout.PANEL_HEIGHT
		< HudLayout.TITLE_COLUMN_HEIGHT + HudLayout.ACTION_GRID_HEIGHT,
		"the panel is not the sum of two columns")
	# Every column's own content still fits inside it. The selection column
	# is a TABLE now (two sub-columns), so this walks every entry in it
	# rather than trusting the lowest one to be the one that was moved.
	for at in [HudLayout.TITLE_AT, HudLayout.DETAIL_AT, HudLayout.HEALTH_AT,
			HudLayout.PROGRESS_CAPTION_AT, HudLayout.PROGRESS_AT,
			HudLayout.QUEUE_CAPTION_AT, HudLayout.QUEUE_SWATCH_AT]:
		assert_true(at.y + HudLayout.QUEUE_SWATCH_SIZE <= HudLayout.TITLE_COLUMN_HEIGHT + 0.01,
			"the selection column's row at %s fits its own height" % at)
		assert_true(at.x + HudLayout.PROGRESS_BAR_WIDTH
			<= HudLayout.TITLE_COLUMN_WIDTH + 0.01,
			"the selection column's row at %s fits its own width" % at)
	assert_true(HudLayout.CHIP_STRIP_HEIGHT >= float(HudLayout.CHIP_ROWS) * HudLayout.CHIP_SIZE.y,
		"the chip rows fit the strip")


func test_the_bar_is_half_the_height_the_three_column_rework_started_at() -> void:
	# Playtest #30, in order: 264 units (two grids stacked under a title
	# stack) -> 146 (three columns, tallest wins) -> "50% shorter". The
	# number is pinned because it is what was ASKED for; the arithmetic
	# above is what makes it hold together.
	assert_almost_eq(HudLayout.PANEL_HEIGHT, 73.0, 1.5,
		"the bar is half of the 146 the three-column rework landed at")
	# At the window this came from, that is the difference between a bar
	# you look past and a bar you look at.
	assert_true(_panel_share(Vector2(1920.0, 1000.0)) <= 0.08,
		"the bar is under a twelfth of the reported window")


func test_a_column_rule_separates_the_columns_without_leaving_the_panel() -> void:
	# The vertical rules replace the horizontal divider the stacked
	# segments needed — same visual break between two KINDS of order, no
	# height spent on it.
	var panel: Rect2 = _laid_out(Vector2(1920.0, 1080.0))["panel"]
	for column in [HudLayout.commands_column_rect(panel), HudLayout.build_column_rect(panel)]:
		var rule := HudLayout.column_rule_rect(column)
		assert_almost_eq(rule.position.x, column.position.x, 0.01,
			"the rule sits on the column's leading edge")
		assert_true(rule.position.y >= panel.position.y
			and rule.position.y + rule.size.y <= panel.position.y + panel.size.y + 0.01,
			"the rule stays inside the panel")
		assert_true(rule.size.y > 0.0, "the rule is visible at all")


func test_the_chip_strip_fills_the_gap_between_the_title_and_the_orders() -> void:
	var panel: Rect2 = _laid_out(HudLayout.REFERENCE)["panel"]
	var title := HudLayout.title_column_rect(panel)
	var strip := HudLayout.chip_strip_rect(panel)
	var commands := HudLayout.commands_column_rect(panel)
	assert_almost_eq(strip.position.x, title.position.x + title.size.x + HudLayout.PANEL_PAD,
		0.01)
	assert_almost_eq(strip.position.x + strip.size.x, commands.position.x - HudLayout.PANEL_PAD,
		0.01)


func test_the_strip_is_wider_when_the_build_column_is_free() -> void:
	# The rule that lets a barracks show all six train tiles — and the trap
	# that comes with it: the strip's width now depends on the SELECTION, so
	# the two capacities genuinely differ and measuring against the wrong
	# one overflows the chips into the orders column.
	for viewport in [Vector2(1600.0, 900.0), Vector2(1920.0, 1080.0)]:
		var panel: Rect2 = _laid_out(viewport)["panel"]
		var narrow := HudLayout.chip_strip_rect(panel, true)
		var wide := HudLayout.chip_strip_rect(panel, false)
		assert_true(wide.size.x > narrow.size.x,
			"a free build column widens the strip at %s" % viewport)
		assert_almost_eq(wide.position.x + wide.size.x,
			HudLayout.build_column_rect(panel).position.x - HudLayout.PANEL_PAD, 0.01,
			"the wide strip stops where the build column starts at %s" % viewport)
		assert_true(HudLayout.chip_capacity(wide) > HudLayout.chip_capacity(narrow),
			"the two strips do not hold the same number of chips at %s" % viewport)


func test_the_client_re_measures_the_strip_whenever_it_fills_it() -> void:
	# THE bug this exists for, found by playing the first three-column
	# build: six squads selected drew six chips straight across the
	# formation buttons. `_chip_strip_rect` was computed in `_layout_chips`,
	# which only runs on a RESIZE — fine while the strip's width was a
	# function of the window alone, and stale the moment it became a
	# function of the selection as well (see the test above). The panel's
	# last resize had nothing selected, so every chip count was measured
	# against the wide strip.
	#
	# The rule lives in client.gd, which needs a GPU — so this is the same
	# shape of check `test_terrain_fog.gd` uses for the same reason: scan
	# the source and assert the CALLER exists. Every other check here can
	# pass while the client measures a rect it laid out a minute ago.
	var source := FileAccess.get_file_as_string("res://client.gd")
	assert_false(source.is_empty(), "client.gd is readable")
	for fill in ["_show_chips", "_show_train_chips"]:
		var at := source.find("func %s(" % fill)
		assert_true(at >= 0, "%s exists" % fill)
		var ends := source.find("\nfunc ", at + 1)
		var body := source.substr(at, (ends if ends > at else source.length()) - at)
		assert_true(body.contains("_layout_chips()"),
			"%s re-measures the chip strip before filling it" % fill)


func test_a_per_squad_chip_list_collapses_before_it_stops_fitting() -> void:
	# The other half of the overlap fix: rather than paging through six
	# identical "Gatherers 5/5" tiles, a uniform selection collapses to one
	# chip per archetype. The threshold can therefore never be larger than
	# what the strip holds — if it were, a selection just under it would
	# page instead of collapsing, which is the worse answer at every size.
	for viewport in SIZES:
		var panel: Rect2 = _laid_out(viewport)["panel"]
		for in_use in [true, false]:
			var strip := HudLayout.chip_strip_rect(panel, in_use)
			var collapse_at := HudLayout.chip_collapse_at(strip)
			assert_true(collapse_at <= HudLayout.chip_capacity(strip),
				"a per-squad list that reaches the collapse point still fits at %s" % viewport)
			assert_true(collapse_at >= 1,
				"one squad is always shown per-squad at %s" % viewport)
			assert_true(collapse_at <= HudLayout.CHIP_COLLAPSE_THRESHOLD,
				"the legibility threshold is still a ceiling at %s" % viewport)


# --- prices are drawn, not spelled -------------------------------------

func test_a_price_leaves_room_for_the_thing_it_is_the_price_of() -> void:
	# The point of drawing a price rather than spelling it is the room it
	# gives back, so the strip has to be small enough that the NAME still
	# has a button to sit on — at the narrowest button, not just at 1080p.
	var two := HudLayout.cost_strip_width(2)
	assert_true(two + HudLayout.PANEL_PAD * 2.0 <= HudLayout.ACTION_BUTTON_MIN_WIDTH,
		"a two-resource price plus padding fits the narrowest build button")
	assert_true(HudLayout.cost_strip_width(HudLayout.CHIP_COST_SLOTS)
		<= HudLayout.CHIP_SIZE.x - 16.0,
		"a train tile's price fits the tile")
	# Pairs do not overlap, and an empty price takes no room at all.
	assert_eq(HudLayout.cost_strip_width(0), 0.0)
	for i in range(1, HudLayout.COST_SLOTS):
		assert_true(HudLayout.cost_entry_x(i)
			>= HudLayout.cost_entry_x(i - 1) + HudLayout.cost_entry_width(),
			"price entry %d clears the one before it" % i)


func test_no_shipped_price_names_more_resources_than_a_button_can_draw() -> void:
	# The icons replaced words, so a price that does not fit is now a
	# SILENT truncation rather than a clipped sentence. Asserted against the
	# shipped defs: a unit or building that ever costs more kinds than
	# COST_SLOTS fails here rather than quietly showing three quarters of
	# its own price.
	var checked := 0
	for def in BuildingSim.all_defs():
		var kinds := 0
		for cost in [def.cost_food, def.cost_wood, def.cost_gold, def.cost_stone]:
			if int(cost) > 0:
				kinds += 1
		assert_true(kinds <= HudLayout.COST_SLOTS,
			"%s names %d resources, and a button draws %d"
				% [def.id, kinds, HudLayout.COST_SLOTS])
		checked += 1
	for def in UnitRoster.load_all():
		var kinds := 0
		for cost in [def.cost_food, def.cost_wood, def.cost_gold, def.cost_stone]:
			if int(cost) > 0:
				kinds += 1
		assert_true(kinds <= HudLayout.COST_SLOTS,
			"%s names %d resources, and a button draws %d"
				% [def.id, kinds, HudLayout.COST_SLOTS])
		checked += 1
	assert_true(checked > 0, "the shipped defs were actually read")


func test_no_chip_is_ever_drawn_outside_the_panel() -> void:
	# The strip is two rows deep now, so its capacity is a real bound rather
	# than a formality — and a chip past the end does not vanish, it draws
	# over the battlefield looking entirely deliberate. `chip_capacity` is
	# what a caller must respect; this is the check that respecting it is
	# sufficient.
	for viewport in SIZES:
		var panel: Rect2 = _laid_out(viewport)["panel"]
		var strip := HudLayout.chip_strip_rect(panel)
		var columns := HudLayout.chip_columns(strip.size.x)
		var capacity := HudLayout.chip_capacity(strip)
		assert_true(capacity >= 1, "at least one chip is always showable at %s" % viewport)
		for i in range(capacity):
			var at := strip.position + HudLayout.chip_slot(i, columns)
			assert_true(at.y + HudLayout.CHIP_SIZE.y
				<= panel.position.y + panel.size.y + 0.01,
				"chip %d of %d stays inside the panel at %s" % [i, capacity, viewport])


func test_every_building_s_train_list_fits_at_the_smallest_window() -> void:
	# The train tiles ARE the train controls (Client._show_train_chips), so
	# a chip strip too narrow for a building's whole `produces` list does
	# not crop a display — it makes an ORDER unreachable, which is this
	# project's oldest defect family. Checked against the shipped defs, so
	# a civ that gains a fifth trainable unit fails here rather than in a
	# match, and at the SMALLEST window the HUD allows, which is the worst
	# case by construction.
	var widest := 0
	for def in BuildingSim.all_defs():
		widest = maxi(widest, def.produces.size())
	assert_true(widest > 0, "the shipped roster has something to train at all")

	# On a window anyone actually plays on, the whole list is on screen at
	# once — no paging to reach a unit you can already see the building for.
	# The strip a BUILDING gets takes the build column's width, because a
	# building builds nothing (see `HudLayout.chip_strip_rect`).
	for viewport in [Vector2(1600.0, 900.0), Vector2(1920.0, 1080.0)]:
		var roomy := HudLayout.chip_strip_rect(_laid_out(viewport)["panel"], false)
		assert_true(HudLayout.chip_capacity(roomy) >= widest,
			"a %d-unit train list fits at %s without paging (capacity %d)"
				% [widest, viewport, HudLayout.chip_capacity(roomy)])

	# At the SMALLEST window the HUD allows it does not fit, and that is
	# what `Client._chip_window`'s pager is for — but paging only reaches
	# the rest if a page can hold at least one real tile beside the pager
	# itself. Two is therefore the floor everywhere, and a capacity of one
	# would be a strip that pages forever without ever showing anything.
	for viewport in SIZES + [Vector2(640.0, 480.0)]:
		for in_use in [true, false]:
			var strip := HudLayout.chip_strip_rect(_laid_out(viewport)["panel"], in_use)
			assert_true(HudLayout.chip_capacity(strip) >= 2,
				"a page holds a tile as well as the pager at %s (build column in use: %s)"
					% [viewport, in_use])


func test_chip_columns_is_never_zero() -> void:
	# A strip too narrow to fit even one chip must still report one column,
	# not zero — a caller dividing an index by a zero column count is a
	# crash, and a chip drawn slightly off the edge of a tiny window is a
	# far smaller failure than the whole selection panel going blank.
	assert_eq(HudLayout.chip_columns(0.0), 1)
	assert_eq(HudLayout.chip_columns(-50.0), 1)


func test_chips_fill_rows_left_to_right() -> void:
	var columns := 3
	assert_eq(HudLayout.chip_slot(0, columns), Vector2.ZERO)
	assert_almost_eq(HudLayout.chip_slot(1, columns).x,
		HudLayout.CHIP_SIZE.x + HudLayout.CHIP_GAP, 0.01)
	assert_almost_eq(HudLayout.chip_slot(1, columns).y, 0.0, 0.01,
		"the second chip stays on the first row")
	assert_almost_eq(HudLayout.chip_slot(3, columns).x, 0.0, 0.01,
		"the fourth chip wraps to a new row")
	assert_true(HudLayout.chip_slot(3, columns).y > 0.0, "the wrapped row is lower")

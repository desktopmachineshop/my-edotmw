extends GutTest

## Guards `lobby_layout.gd` and #91 — the lobby fits the window it is drawn
## in, and whatever it cannot fit is still reachable.
##
## ## What was wrong, in numbers
##
## Built as it shipped and measured against the reported ~1920x1000 client
## area, the lobby's content wanted **896 design pixels of height and was
## handed 672**: the chat panel was clipped mid-panel, GAME SETTINGS
## crossed the bottom edge, the SANDBOX panel was not on screen at all, and
## with no `ScrollContainer` anywhere above the root there was no way to
## reach any of it. Making the window bigger did not help, because the
## lobby was laid out against the HUD's 720-tall design space no matter how
## tall the window was.
##
## ## Why this test can exist at all
##
## The geometry used to be hand-rolled inside `client.gd`, which is why
## nothing covered it. It lives in `LobbyLayout` now, all-static and pure
## the way `HudLayout` is (D-061) — so the arithmetic half needs no GPU.
##
## The other half is measured off the REAL lobby. `client.gd` is
## native-only (D-014), but that is true of what it DRAWS: a container's
## minimum size is a question about fonts and layout, and a headless
## SceneTree answers it. What the client cannot do headless is `_ready()`,
## which opens a socket — so the lobby's own CanvasLayer is taken out of an
## un-started client and added to the test's tree instead. It has to be IN
## a tree: off-tree the same measurement comes back 486 instead of 896,
## because theme fonts do not resolve, and a test that trusted that number
## would have called the reported bug fixed while it was still on screen.

## Real client areas, and what each is here to prove. `MIN_SCALE` floors
## the lobby's scale at 0.9, so a window at least 900 tall lays out against
## at least `DESIGN_HEIGHT` and must FIT; anything shorter genuinely cannot
## and must SCROLL.
const FITTING_WINDOWS := [
	Vector2(1920.0, 1000.0),   # the one the bug was reported on
	Vector2(1920.0, 1080.0),
	Vector2(1600.0, 900.0),
	Vector2(2560.0, 1440.0),
	Vector2(3440.0, 1440.0),   # 21:9
]

const SHORT_WINDOWS := [
	Vector2(1152.0, 648.0),    # HudLayout.min_window_size() — the floor
	Vector2(1366.0, 768.0),
]


# --- the arithmetic ----------------------------------------------------

func test_a_bigger_window_gives_the_lobby_more_room() -> void:
	# THE coupling this file exists for. The lobby used to take the HUD's
	# scale, and `HudLayout.scale_for` divides by a 720-tall reference — so
	# a 1000-tall window was laid out against exactly the same 720 design
	# pixels a 1280x720 window gets, and there was no window size at which
	# the content fit.
	var small := LobbyLayout.design_size(Vector2(1280.0, 720.0))
	for window in FITTING_WINDOWS:
		var design := LobbyLayout.design_size(window)
		assert_gt(design.y, small.y,
			"a %s window must lay the lobby out taller than a 1280x720 one" % window)
		assert_true(design.y >= LobbyLayout.DESIGN_HEIGHT - 0.01,
			"%s is tall enough for the lobby's own content (%.0f)" % [window, design.y])


func test_a_window_too_short_for_the_lobby_is_not_scaled_into_fitting() -> void:
	# The floor is legibility (HudLayout.MIN_SCALE): shrinking further to
	# make the content fit would trade a scrollbar for text nobody can
	# read. These windows are meant to scroll, and the test below checks
	# that they can.
	for window in SHORT_WINDOWS:
		assert_almost_eq(LobbyLayout.scale_for(window), HudLayout.MIN_SCALE, 0.001,
			"%s should sit on the legibility floor" % window)


func test_nothing_moves_on_the_window_the_lobby_was_drawn_against() -> void:
	# The fractions are the old fixed pixel counts, expressed against the
	# 1280x720 window they were chosen on — so this change is a rescaling
	# of a layout somebody looked at, not a new one.
	var design := Vector2(1280.0, 720.0)
	assert_almost_eq(LobbyLayout.margin(design).x, 40.0, 0.5, "left/right margin")
	assert_almost_eq(LobbyLayout.margin(design).y, 24.0, 0.5, "top/bottom margin")
	assert_almost_eq(LobbyLayout.seat_list_height(Vector2(1280.0, LobbyLayout.DESIGN_HEIGHT)),
		LobbyLayout.SEAT_ROW_HEIGHT * LobbyLayout.SEAT_ROWS_VISIBLE, 0.5,
		"4.5 seat rows show on a window with room for them")
	assert_almost_eq(LobbyLayout.map_preview_height(Vector2(1280.0, 960.0)), 168.0, 0.5,
		"the map preview keeps the height it was authored at")


func test_a_short_window_gives_every_panel_a_smaller_share() -> void:
	# Item 3 of the report: the fixed heights were the reason a short
	# window did not shrink each panel a little, it dropped the last one
	# off the bottom entirely.
	var short := Vector2(1280.0, 720.0)
	var tall := Vector2(1280.0, LobbyLayout.DESIGN_HEIGHT)
	assert_lt(LobbyLayout.map_preview_height(short), LobbyLayout.map_preview_height(tall),
		"map preview")
	assert_lt(LobbyLayout.chat_log_height(short), LobbyLayout.chat_log_height(tall),
		"chat log")
	assert_lt(LobbyLayout.seat_list_height(short), LobbyLayout.seat_list_height(tall),
		"seat list")
	assert_lt(LobbyLayout.map_blurb_height(short), LobbyLayout.map_blurb_height(tall),
		"map blurb")


func test_the_columns_divide_the_window_rather_than_demanding_pixels() -> void:
	# Item 1: the right column was a flat 400 and the left a flat 560.
	var narrow := Vector2(1280.0, 1000.0)
	var wide := Vector2(2389.0, 1000.0)
	assert_lt(LobbyLayout.right_column_width(narrow), LobbyLayout.right_column_width(wide),
		"a wider window gives the map column more room")
	assert_lt(LobbyLayout.right_column_width(wide), wide.x * 0.5,
		"but the left column keeps the majority of a wide window")
	assert_lt(LobbyLayout.left_column_width(narrow), narrow.x,
		"neither column may claim the whole width on its own")


func test_a_players_hud_scale_cannot_push_the_lobby_off_its_own_screen() -> void:
	# A player who set 2.0 because the in-match HUD is hard to read (D-063)
	# did not ask for the SANDBOX panel to leave the screen. The choice can
	# make the lobby smaller than the fit; it cannot make it bigger.
	var window := Vector2(1920.0, 1000.0)
	var fit := LobbyLayout.scale_for(window)
	assert_almost_eq(LobbyLayout.scale_for(window, 2.0), fit, 0.001,
		"an override bigger than the fit is clamped to the fit")
	assert_almost_eq(LobbyLayout.scale_for(window, fit * 0.5), fit * 0.5, 0.001,
		"an override smaller than the fit is honoured")


# --- the real lobby ----------------------------------------------------

## The real `client.gd`, sat in a lobby it is NOT the admin of — the taller
## of the two states, because a non-admin also gets the two "Only the host
## can change these." captions. Never added to the tree: `_ready()` opens a
## socket.
func _client_in_a_lobby(admin: bool) -> Node3D:
	var state := ClientState.new()
	if admin:
		state.handle_packet(NetProtocol.encode_welcome(
			1, 16, 8, PackedInt32Array([0, 1]), [], 40, 0))
	state.handle_packet(NetProtocol.encode_lobby(1, [
		{"kind": "human", "player": 1, "civ": "legion", "team": 0, "name": "Player 1"},
		{"kind": "ai", "player": 2, "civ": "northmen", "team": 0, "name": "AI 2"},
	], MapSettings.new().to_dict(), int(MatchState.Phase.LOBBY), true, false, false))
	assert_eq(state.is_admin(), admin, "Setup: the client should know whether it hosts")

	var client: Node3D = autofree(load("res://client.gd").new())
	client._state = state
	client._build_lobby_ui()
	client._refresh_lobby()
	return client


## The lobby's own layer, in the test's tree so its fonts and containers
## are the shipping ones, laid out for `window`. Returns the client, which
## still owns every control.
func _lobby_laid_out(window: Vector2, admin := false) -> Node3D:
	var client := _client_in_a_lobby(admin)
	var layer: CanvasLayer = client._lobby_layer
	client.remove_child(layer)
	add_child_autofree(layer)
	layer.visible = true
	await get_tree().process_frame
	client._layout_lobby(LobbyLayout.design_size(window))
	await get_tree().process_frame
	await get_tree().process_frame
	return client


## How much height the lobby's content wants, against how much the page it
## sits in actually has.
func _wanted_and_available(client: Node3D) -> Array:
	return [client._lobby_root.get_combined_minimum_size().y, client._lobby_scroll.size.y]


func test_the_lobby_fits_the_window_it_was_reported_against() -> void:
	# 1920x1000, the playtest's client area. Measured before the fix: 896
	# wanted against 672 available, and 224 design pixels of GAME SETTINGS
	# and SANDBOX below the fold with no way to scroll to them.
	var client: Node3D = await _lobby_laid_out(Vector2(1920.0, 1000.0))
	var at := _wanted_and_available(client)
	gut.p("1920x1000: wants %.0f, has %.0f" % [at[0], at[1]])
	assert_lt(at[0], at[1] + 0.01,
		"the lobby's content must fit the page it is drawn in")


func test_the_lobby_fits_every_window_it_is_meant_to() -> void:
	for window in FITTING_WINDOWS:
		for admin in [false, true]:
			var client: Node3D = await _lobby_laid_out(window, admin)
			var at := _wanted_and_available(client)
			assert_lt(at[0], at[1] + 0.01,
				"%s (admin=%s) wants %.0f and has %.0f" % [window, admin, at[0], at[1]])


func test_content_a_short_window_cannot_fit_is_still_reachable() -> void:
	# The backstop, and the half that is true whatever the arithmetic above
	# gets wrong. These windows genuinely cannot show the whole lobby at a
	# legible scale — so the failure has to be a scrollbar, not a panel
	# sitting on the window's bottom border.
	for window in SHORT_WINDOWS:
		var client: Node3D = await _lobby_laid_out(window)
		var at := _wanted_and_available(client)
		assert_gt(at[0], at[1],
			"Setup: %s is meant to be too short for the lobby" % window)

		var scroll: ScrollContainer = client._lobby_scroll
		var bar := scroll.get_v_scroll_bar()
		assert_true(bar.max_value >= at[0] - 1.0,
			"%s: the page must scroll to the bottom of its content (%.0f of %.0f)"
				% [window, bar.max_value, at[0]])
		assert_gt(bar.max_value, bar.page,
			"%s: there must be something to scroll" % window)


func test_the_lobby_is_still_the_size_of_the_window_it_is_drawn_on() -> void:
	# The margin is a share of the design rect now, so this is the check
	# that it did not quietly become a border the size of the screen.
	var window := Vector2(1920.0, 1000.0)
	var client: Node3D = await _lobby_laid_out(window)
	var design := LobbyLayout.design_size(window)
	var page: Rect2 = LobbyLayout.root_rect(design)
	assert_gt(page.size.x, design.x * 0.85, "the page spans the window's width")
	assert_gt(page.size.y, design.y * 0.85, "the page spans the window's height")
	assert_almost_eq(client._lobby_backdrop.size.x, design.x, 0.01,
		"the backdrop still covers the whole design rect")


func test_the_lobbys_own_content_still_fits_the_height_it_claims() -> void:
	# The anti-drift pin, and the reason `DESIGN_HEIGHT` is not a taste.
	# Every scale above is derived from it, so a lobby that quietly grew
	# past it — two more GAME SETTINGS rows, a fourth sandbox toggle —
	# would go back to overflowing every window. It fails HERE instead,
	# naming the number to raise.
	var design := Vector2(LobbyLayout.REFERENCE_WIDTH, LobbyLayout.DESIGN_HEIGHT)
	var client: Node3D = await _lobby_laid_out(
		design * HudLayout.MIN_SCALE)  # the shortest window that lays out at DESIGN_HEIGHT
	var wanted: float = client._lobby_root.get_combined_minimum_size().y
	var margin := LobbyLayout.margin(design).y * 2.0
	gut.p("lobby content: %.0f + %.0f margin against DESIGN_HEIGHT %.0f"
		% [wanted, margin, LobbyLayout.DESIGN_HEIGHT])
	assert_lt(wanted + margin, LobbyLayout.DESIGN_HEIGHT,
		"the lobby has outgrown LobbyLayout.DESIGN_HEIGHT — raise it, or the screen overflows")
